-- SPDX-License-Identifier: MIT
-- Disk/ring buffer only. No game APIs, networking, or combat control.
local M = {}
local defaults = {
    segment_bytes = 8 * 1024 * 1024, segments = 32, days = 7,
    ring_seconds = 300, ring_bytes = 2 * 1024 * 1024,
    incidents = 16, incident_bytes = 8 * 1024 * 1024,
    aftermath_seconds = 120, incident_seconds = 600,
    queue_bytes = 4 * 1024 * 1024, flush_bytes = 128 * 1024,
}

function M.new(options, deps)
    assert(options.character:match('^[A-Za-z]+$'), 'unsafe character name')
    assert(type(options.directory) == 'string' and #options.directory > 8, 'missing log directory')
    local self = {d = deps, o = {}, queues = {}, ring = {}, ring_head = 1, ring_tail = 0,
        ring_size = 0, queued_bytes = 0, dropped = 0, write_errors = 0,
        seq = 0, part = 0, incident_count = 0, last_write = 0, next_retry = 0,
        next_flush = 0, next_health = 0, ring_evicted = 0, started = deps.clock()}
    for key, value in pairs(defaults) do self.o[key] = options[key] or value end
    self.character, self.directory = options.character, options.directory:gsub('[\\/]+$', '') .. '/'
    local stamp, nonce = deps.now(), math.floor(deps.clock() * 1000000) % 1000000
    repeat
        self.session = string.format('%010d-%06d', stamp, nonce)
        nonce = (nonce + 1) % 1000000
    until not deps.exists(self.directory .. 'combat-' .. self.session .. '-0001.jsonl')
    self.nonce = self.session:match('%-(%d+)$')
    -- Never enumerate/prune synchronously during the load callback.
    self.next_prune = deps.now() + 5

    function self:new_queue(kind)
        local index
        if kind == 'combat' then self.part = self.part + 1; index = self.part
        else self.incident_count = self.incident_count + 1; index = self.incident_count end
        local name = string.format('%s-%010d-%s-%04d.jsonl', kind, self.d.now(), self.nonce, index)
        local q = {name = name, path = self.directory .. name, kind = kind,
            lines = {}, head = 1, tail = 0, bytes = 0, accepted = 0}
        self.queues[#self.queues + 1] = q
        self.needs_prune = true
        return q
    end

    function self:enqueue(q, line)
        if self.queued_bytes + #line > self.o.queue_bytes then
            self.dropped = self.dropped + 1
            return false
        end
        q.tail = q.tail + 1; q.lines[q.tail] = line
        q.bytes = q.bytes + #line; q.accepted = q.accepted + #line
        self.queued_bytes = self.queued_bytes + #line
        return true
    end

    function self:trim_ring(now)
        while self.ring_head <= self.ring_tail do
            local first = self.ring[self.ring_head]
            if self.ring_size <= self.o.ring_bytes and now - first.time <= self.o.ring_seconds then break end
            if self.ring_size > self.o.ring_bytes then self.ring_evicted = now end
            self.ring_size = self.ring_size - #first.line
            self.ring[self.ring_head] = nil; self.ring_head = self.ring_head + 1
        end
        if self.ring_head > 2048 then
            local replacement = {}
            for i = self.ring_head, self.ring_tail do replacement[#replacement + 1] = self.ring[i] end
            self.ring, self.ring_head, self.ring_tail = replacement, 1, #replacement
        end
    end

    function self:record(kind, data)
        local now = self.d.now()
        self.seq = self.seq + 1
        local record = {schema = 1, time = now, elapsed = self.d.clock() - self.started,
            seq = self.seq, session = self.session, character = self.character, kind = kind, data = data or {}}
        local line = self.d.encode(record) .. '\n'
        if #line > 64 * 1024 then self.dropped = self.dropped + 1; return false end
        if not self.current or self.current.accepted + #line > self.o.segment_bytes then
            self.current = self:new_queue('combat')
        end
        self:enqueue(self.current, line)
        self.ring_tail = self.ring_tail + 1
        self.ring[self.ring_tail] = {time = now, line = line}
        self.ring_size = self.ring_size + #line
        self:trim_ring(now)
        if self.incident then
            if now <= self.incident_until and self.incident.accepted + #line <= self.o.incident_bytes then
                self:enqueue(self.incident, line)
            else self.incident = nil end
        end
        return true
    end

    function self:mark(reason, data)
        local now = self.d.now()
        if self.incident and now > self.incident_until then self.incident = nil end
        if not self.incident then
            self:trim_ring(now)
            self.incident = self:new_queue('incident')
            self.last_incident = self.incident.name
            self.incident_start = now
            self.incident_until = now + self.o.aftermath_seconds
            -- Reuse immutable lines: copying the ring does not encode/parse it again.
            for i = self.ring_head, self.ring_tail do
                local line = self.ring[i].line
                if self.incident.accepted + #line <= self.o.incident_bytes then self:enqueue(self.incident, line) end
            end
        else
            self.incident_until = math.min(now + self.o.aftermath_seconds, self.incident_start + self.o.incident_seconds)
        end
        self:record('incident', {reason = reason, detail = data, archive = self.last_incident,
            available_pre_seconds = self.ring[self.ring_head] and now - self.ring[self.ring_head].time or 0,
            prehistory_size_limited = self.ring_evicted > 0 and now - self.ring_evicted <= self.o.ring_seconds,
            queue_dropped = self.dropped})
        self.next_flush = 0
    end

    function self:fail(message)
        self.write_errors = self.write_errors + 1
        self.last_error = tostring(message):sub(1, 300)
        self.next_retry = self.d.now() + 30
    end

    function self:flush()
        if self.d.now() < self.next_retry then return end
        local budget = self.o.flush_bytes
        for _, q in ipairs(self.queues) do
            if budget <= 0 then break end
            if q.bytes > 0 then
                local batch, bytes, last = {}, 0, q.head - 1
                for i = q.head, q.tail do
                    if bytes > 0 and bytes + #q.lines[i] > budget then break end
                    batch[#batch + 1] = q.lines[i]; bytes = bytes + #q.lines[i]; last = i
                end
                local file, message = self.d.open(q.path, 'ab')
                if not file then self:fail(message or 'open failed'); return end
                local ok, result, detail = pcall(file.write, file, table.concat(batch))
                local closed, close_result = pcall(file.close, file)
                -- A failed write/close can have partially reached disk. Do not retry
                -- and duplicate these records; expose the loss/ambiguity in health.
                for i = q.head, last do q.lines[i] = nil end
                q.head = last + 1; q.bytes = q.bytes - bytes
                self.queued_bytes = self.queued_bytes - bytes; budget = budget - bytes
                if q.head > q.tail then q.lines, q.head, q.tail = {}, 1, 0 end
                if not ok or not result or not closed or not close_result then
                    self.dropped = self.dropped + #batch
                    self:fail(detail or result or 'write/close failed; partial batch possible')
                    return
                end
                self.last_write, self.last_error = self.d.now(), nil
            end
        end
        local keep = {}
        for _, q in ipairs(self.queues) do
            if q.bytes > 0 or q == self.current or q == self.incident then keep[#keep + 1] = q end
        end
        self.queues = keep
    end

    function self:prune()
        local groups, protected = {combat = {}, incident = {}}, {}
        for _, q in ipairs(self.queues) do protected[q.name] = true end
        for _, name in pairs(self.d.list(self.directory) or {}) do
            if type(name) == 'string' then
                local kind, stamp = name:match('^(combat)%-(%d+)%-%d+%-%d+%.jsonl$')
                if not kind then kind, stamp = name:match('^(incident)%-(%d+)%-%d+%-%d+%.jsonl$') end
                if kind then groups[kind][#groups[kind] + 1] = {name = name, time = tonumber(stamp)} end
            end
        end
        for kind, files in pairs(groups) do
            table.sort(files, function(a, b) return a.name > b.name end)
            local limit = kind == 'combat' and self.o.segments or self.o.incidents
            for i, file in ipairs(files) do
                local too_old = kind == 'combat' and self.d.now() - file.time > self.o.days * 86400
                if not protected[file.name] and (i > limit or too_old) then
                    local ok, message = self.d.remove(self.directory .. file.name)
                    if not ok then self.retention_error = tostring(message or 'retention deletion failed') end
                end
            end
        end
        self.needs_prune = false
    end

    function self:health(extra)
        return {schema = 1, character = self.character, session = self.session, heartbeat = self.d.now(),
            last_data_write = self.last_write, queued_bytes = self.queued_bytes, dropped_records = self.dropped,
            write_errors = self.write_errors, last_error = self.last_error, retention_error = self.retention_error,
            segment = self.current and self.current.name, incident = self.last_incident, state = extra or {}}
    end

    function self:tick(extra, force)
        local now = self.d.now()
        if force or now >= self.next_flush then
            self.next_flush = now + 1; self:flush()
            if now >= self.next_prune then
                self:prune(); self.next_prune = now + 60
            end
        end
        if (force or now >= self.next_health) and now >= self.next_retry then
            self.next_health = now + 10
            local file, message = self.d.open(self.directory .. 'health.json', 'wb')
            if file then
                local ok, result = pcall(file.write, file, self.d.encode(self:health(extra)) .. '\n')
                local closed, close_result = pcall(file.close, file)
                if not ok or not result or not closed or not close_result then self:fail('health write failed') end
            else self:fail(message or 'health open failed') end
        end
    end

    function self:close(extra)
        self:record('session_end', extra)
        for _ = 1, math.ceil(self.o.queue_bytes / self.o.flush_bytes) + 2 do
            if self.queued_bytes == 0 or self.d.now() < self.next_retry then break end
            self:flush()
        end
        self:tick(extra, true)
    end
    return self
end
return M
