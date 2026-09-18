-- Opt-in, bounded hot-path timing for Windower addons.
--
-- The profiler is deliberately dormant until its addon receives
-- `perf start`.  While enabled it retains aggregate counters, at most
-- MAX_SECONDS one-second buckets, and a bounded ring of slow samples.

local module = {}
local profiler = {}
profiler.__index = profiler

local MAX_SECONDS = 900
local MAX_SLOW_SAMPLES = 256
local SLOW_SAMPLE_MS = 2

local wall_clock
local clock_source
do
    local ok, socket = pcall(require, 'socket')
    if ok and socket and type(socket.gettime) == 'function' then
        wall_clock = socket.gettime
        clock_source = 'socket.gettime'
    else
        local wall_origin = os.time()
        local cpu_origin = os.clock()
        wall_clock = function()
            return wall_origin + (os.clock() - cpu_origin)
        end
        clock_source = 'os.time+os.clock fallback'
    end
end

local function pack_results(...)
    return {n = select('#', ...), ...}
end

local function new_stats()
    return {
        calls = 0,
        total_wall_ms = 0,
        max_wall_ms = 0,
        total_cpu_ms = 0,
        max_cpu_ms = 0,
        over_1ms = 0,
        over_5ms = 0,
        over_10ms = 0,
        over_20ms = 0,
    }
end

local function update_stats(stats, wall_ms, cpu_ms)
    stats.calls = stats.calls + 1
    stats.total_wall_ms = stats.total_wall_ms + wall_ms
    stats.total_cpu_ms = stats.total_cpu_ms + cpu_ms
    if wall_ms > stats.max_wall_ms then stats.max_wall_ms = wall_ms end
    if cpu_ms > stats.max_cpu_ms then stats.max_cpu_ms = cpu_ms end
    if wall_ms >= 1 then stats.over_1ms = stats.over_1ms + 1 end
    if wall_ms >= 5 then stats.over_5ms = stats.over_5ms + 1 end
    if wall_ms >= 10 then stats.over_10ms = stats.over_10ms + 1 end
    if wall_ms >= 20 then stats.over_20ms = stats.over_20ms + 1 end
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == 'number' and type(right) == 'number' then
            return left < right
        end
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function csv_value(value)
    if value == nil then return '' end
    local text = tostring(value)
    if text:find('[,\"\r\n]') then
        return '"'..text:gsub('"', '""')..'"'
    end
    return text
end

local function write_row(handle, values)
    local encoded = {}
    for index, value in ipairs(values) do
        encoded[index] = csv_value(value)
    end
    handle:write(table.concat(encoded, ','), '\n')
end

local function safe_slug(value)
    local slug = tostring(value or 'addon'):lower():gsub('[^%w_-]+', '-')
    slug = slug:gsub('^-+', ''):gsub('-+$', '')
    return slug ~= '' and slug or 'addon'
end

local function player_name()
    local player = windower.ffxi.get_player()
    local name = player and player.name or 'Unknown'
    local sanitized = tostring(name):gsub('[^%w_-]+', '_')
    return sanitized
end

local function reset_data(self)
    self.summary = {}
    self.seconds = {}
    self.slow_samples = {}
    self.slow_next = 1
    self.slow_dropped = 0
    self.seconds_truncated = false
    self.total_calls = 0
end

local function chat(self, color, message)
    windower.add_to_chat(color or 207,
        ('[HotPath:%s] %s'):format(self.addon, tostring(message)))
end

function module.new(options)
    assert(type(options) == 'table', 'hotpath profiler options are required')
    assert(type(options.addon) == 'string', 'hotpath profiler addon name is required')
    assert(type(options.path) == 'string', 'hotpath profiler addon path is required')
    local instance = setmetatable({
        addon = options.addon,
        addon_path = options.path,
        slug = safe_slug(options.slug or options.addon),
        enabled = false,
        started_wall = nil,
        started_cpu = nil,
    }, profiler)
    reset_data(instance)
    return instance
end

function profiler:begin_sample()
    if not self.enabled then return nil, nil end
    return wall_clock(), os.clock()
end

function profiler:finish_sample(event, started_wall, started_cpu)
    if not self.enabled or not started_wall then return end
    event = tostring(event or 'unknown')
    local finished_wall = wall_clock()
    local finished_cpu = os.clock()
    local wall_ms = math.max(0, (finished_wall - started_wall) * 1000)
    local cpu_ms = math.max(0, (finished_cpu - (started_cpu or finished_cpu)) * 1000)

    local aggregate = self.summary[event]
    if not aggregate then
        aggregate = new_stats()
        self.summary[event] = aggregate
    end
    update_stats(aggregate, wall_ms, cpu_ms)
    self.total_calls = self.total_calls + 1

    local second = math.floor(started_wall - self.started_wall)
    local bucket_epoch = math.floor(started_wall)
    if second >= 0 and second < MAX_SECONDS then
        local bucket = self.seconds[bucket_epoch]
        if not bucket then
            bucket = {}
            self.seconds[bucket_epoch] = bucket
        end
        local bucket_stats = bucket[event]
        if not bucket_stats then
            bucket_stats = new_stats()
            bucket[event] = bucket_stats
        end
        update_stats(bucket_stats, wall_ms, cpu_ms)
    else
        self.seconds_truncated = true
    end

    if wall_ms >= SLOW_SAMPLE_MS then
        local sample = {
            event = event,
            second = second,
            started_epoch = started_wall,
            wall_ms = wall_ms,
            cpu_ms = cpu_ms,
        }
        if #self.slow_samples < MAX_SLOW_SAMPLES then
            self.slow_samples[#self.slow_samples + 1] = sample
        else
            self.slow_samples[self.slow_next] = sample
            self.slow_next = self.slow_next + 1
            if self.slow_next > MAX_SLOW_SAMPLES then self.slow_next = 1 end
            self.slow_dropped = self.slow_dropped + 1
        end
    end
end

function profiler:wrap(event, callback)
    assert(type(callback) == 'function', 'hotpath callback must be a function')
    local owner = self
    return function(...)
        if not owner.enabled then return callback(...) end
        local started_wall, started_cpu = owner:begin_sample()
        local results = pack_results(callback(...))
        owner:finish_sample(event, started_wall, started_cpu)
        return unpack(results, 1, results.n)
    end
end

function profiler:wrap_keyed(selector, callback)
    assert(type(selector) == 'function', 'hotpath selector must be a function')
    assert(type(callback) == 'function', 'hotpath callback must be a function')
    local owner = self
    return function(...)
        if not owner.enabled then return callback(...) end
        local event = selector(...)
        if not event then return callback(...) end
        local started_wall, started_cpu = owner:begin_sample()
        local results = pack_results(callback(...))
        owner:finish_sample(event, started_wall, started_cpu)
        return unpack(results, 1, results.n)
    end
end

function profiler:start()
    reset_data(self)
    self.started_wall = wall_clock()
    self.started_cpu = os.clock()
    self.enabled = true
    chat(self, 158, 'Profiler started (bounded in-memory capture).')
end

function profiler:report()
    if not self.started_wall then
        chat(self, 123, 'No profiler run is available. Use perf start first.')
        return nil
    end

    local stopped_wall = wall_clock()
    local output_dir = self.addon_path..'data\\performance\\'
    if not windower.dir_exists(self.addon_path..'data\\') then
        windower.create_dir(self.addon_path..'data\\')
    end
    if not windower.dir_exists(output_dir) then windower.create_dir(output_dir) end

    local seconds = math.floor(stopped_wall)
    local milliseconds = math.floor((stopped_wall - seconds) * 1000 + 0.5)
    if milliseconds > 999 then
        seconds = seconds + 1
        milliseconds = 0
    end
    local stamp = os.date('%Y%m%d-%H%M%S', seconds)
        ..('-%.3d'):format(milliseconds)
    local path = output_dir..self.slug..'-perf-'..player_name()..'-'..stamp..'.csv'
    local handle, open_error = io.open(path, 'w')
    if not handle then
        chat(self, 123, 'Could not write report: '..tostring(open_error))
        return nil
    end

    write_row(handle, {'format', 'windower-hotpath-v1'})
    write_row(handle, {'character', player_name()})
    write_row(handle, {'addon', self.addon})
    write_row(handle, {'clock_source', clock_source})
    write_row(handle, {'started_epoch', ('%.6f'):format(self.started_wall)})
    write_row(handle, {'stopped_epoch', ('%.6f'):format(stopped_wall)})
    write_row(handle, {'duration_seconds', ('%.3f'):format(stopped_wall - self.started_wall)})
    write_row(handle, {'second_bucket_limit', MAX_SECONDS})
    write_row(handle, {'seconds_truncated', tostring(self.seconds_truncated)})
    write_row(handle, {'slow_sample_threshold_ms', SLOW_SAMPLE_MS})
    write_row(handle, {'slow_sample_limit', MAX_SLOW_SAMPLES})
    write_row(handle, {'slow_samples_dropped', self.slow_dropped})
    write_row(handle, {
        'record_type', 'event', 'second', 'started_epoch', 'calls',
        'total_wall_ms', 'average_wall_ms', 'max_wall_ms',
        'total_cpu_ms', 'average_cpu_ms', 'max_cpu_ms',
        'over_1ms', 'over_5ms', 'over_10ms', 'over_20ms',
    })

    local function write_stats(record_type, event, second, started_epoch, stats)
        local calls = stats.calls
        write_row(handle, {
            record_type, event, second, started_epoch, calls,
            ('%.6f'):format(stats.total_wall_ms),
            ('%.6f'):format(calls > 0 and stats.total_wall_ms / calls or 0),
            ('%.6f'):format(stats.max_wall_ms),
            ('%.6f'):format(stats.total_cpu_ms),
            ('%.6f'):format(calls > 0 and stats.total_cpu_ms / calls or 0),
            ('%.6f'):format(stats.max_cpu_ms),
            stats.over_1ms, stats.over_5ms, stats.over_10ms, stats.over_20ms,
        })
    end

    for _, event in ipairs(sorted_keys(self.summary)) do
        write_stats('summary', event, '', '', self.summary[event])
    end
    for _, bucket_epoch in ipairs(sorted_keys(self.seconds)) do
        local bucket = self.seconds[bucket_epoch]
        local second = math.floor(bucket_epoch - self.started_wall)
        for _, event in ipairs(sorted_keys(bucket)) do
            write_stats('second', event, second,
                ('%.6f'):format(bucket_epoch), bucket[event])
        end
    end
    table.sort(self.slow_samples, function(left, right)
        return left.started_epoch < right.started_epoch
    end)
    for _, sample in ipairs(self.slow_samples) do
        local stats = new_stats()
        update_stats(stats, sample.wall_ms, sample.cpu_ms)
        write_stats('slow', sample.event, sample.second,
            ('%.6f'):format(sample.started_epoch), stats)
    end
    handle:close()
    chat(self, 158, 'Profiler report: '..path)
    return path
end

function profiler:stop()
    if not self.started_wall then
        chat(self, 123, 'No profiler run is available. Use perf start first.')
        return nil
    end
    self.enabled = false
    return self:report()
end

function profiler:reset()
    local was_enabled = self.enabled
    reset_data(self)
    self.started_wall = wall_clock()
    self.started_cpu = os.clock()
    self.enabled = was_enabled
    chat(self, 158, 'Profiler counters reset; state is '
        ..(self.enabled and 'running.' or 'stopped.'))
end

function profiler:status()
    if not self.started_wall then
        chat(self, 207, 'Profiler is stopped; no run is buffered.')
        return
    end
    chat(self, 207, ('Profiler %s | %.1fs | %d measured callbacks | %d slow samples%s.'):format(
        self.enabled and 'running' or 'stopped',
        wall_clock() - self.started_wall,
        self.total_calls,
        #self.slow_samples,
        self.slow_dropped > 0 and (' | '..self.slow_dropped..' slow samples rotated') or ''))
end

function profiler:command(action)
    action = tostring(action or 'status'):lower()
    if action == 'start' then
        self:start()
    elseif action == 'stop' then
        self:stop()
    elseif action == 'report' then
        self:report()
    elseif action == 'reset' then
        self:reset()
    elseif action == 'status' then
        self:status()
    else
        chat(self, 207, 'Commands: perf start | stop | report | reset | status')
    end
end

return module
