-- Per-client, in-memory expedition-entry identity and leader-side binding.
-- Entry nonces are deliberately never restored from disk. A client loaded
-- while already inside an instance therefore cannot assert continuity.

local Session = {}
Session.__index = Session
local nonce_serial = 0
-- The address portion of a fresh table is process/load-local entropy in the
-- Lua runtimes supported by Windower. It is never persisted or transmitted on
-- its own; it prevents a same-second addon reload from recreating a nonce.
local boot_token = tostring({}):lower():gsub('[^a-z0-9]', '')
if #boot_token > 24 then boot_token = boot_token:sub(-24) end

local function inside(pack, zone)
    return type(pack) == 'table' and type(pack.instance_zones) == 'table'
        and pack.instance_zones[tonumber(zone)] == true
end

local function default_nonce(pack, identity, zone, now, serial)
    local pack_token = tostring(pack.id or 'pack'):lower()
        :gsub('[^a-z0-9_-]', '_'):sub(1, 16)
    local owner = tostring(identity or 'client'):lower():gsub('[^a-z0-9_-]', '_')
        :sub(1, 20)
    nonce_serial = nonce_serial + 1
    local clock = type(os.clock) == 'function'
        and math.floor((tonumber(os.clock()) or 0) * 1000000) or 0
    return ('%s-%s-%s-%d-%d-%d-%d-%d'):format(pack_token, owner, boot_token,
        math.floor(tonumber(now) or os.time()), tonumber(zone) or 0, serial,
        clock, nonce_serial)
end

local function valid_zone(zone)
    return type(zone) == 'number' and zone == math.floor(zone)
        and zone >= 0 and zone <= 1024
end

local function copy_map(source)
    local result = {}
    for key, value in pairs(type(source) == 'table' and source or {}) do
        result[key] = value
    end
    return result
end

function Session.new(pack, identity, nonce_factory)
    assert(type(pack) == 'table' and type(pack.id) == 'string'
        and type(pack.instance_zones) == 'table', 'valid pack required')
    return setmetatable({
        pack=pack,
        identity=tostring(identity or ''),
        nonce_factory=nonce_factory or default_nonce,
        serial=0,
        entry_nonce=nil,
        bound_run_id=nil,
        bound_zone=nil,
        bound_cohort=nil,
        bound_entries=nil,
        previous_entries=nil,
        blocked=false,
    }, Session)
end

function Session:cold_start(zone)
    self.entry_nonce = nil
    self.bound_run_id = nil
    self.bound_zone = nil
    self.bound_cohort = nil
    self.bound_entries = nil
    self.previous_entries = nil
    self.blocked = inside(self.pack, zone)
    return self.blocked and 'unbound_inside' or 'outside'
end

function Session:observe_zone(new_zone, old_zone, now)
    new_zone, old_zone = tonumber(new_zone), tonumber(old_zone)
    if not valid_zone(new_zone) or not valid_zone(old_zone) then
        self.entry_nonce = nil
        self:unbind(true)
        return 'invalid_zone_transition'
    end
    local new_inside = inside(self.pack, new_zone)
    local old_inside = inside(self.pack, old_zone)
    if old_inside ~= new_inside or (old_inside and new_inside
        and old_zone ~= new_zone) then
        self.previous_entries = self.bound_entries
            and copy_map(self.bound_entries) or self.previous_entries
        self.bound_run_id, self.bound_zone = nil, nil
        self.bound_cohort, self.bound_entries = nil, nil
    end

    if new_inside and not old_inside then
        self.serial = self.serial + 1
        local nonce = self.nonce_factory(self.pack, self.identity, new_zone,
            tonumber(now) or os.time(), self.serial)
        if type(nonce) ~= 'string' or nonce == ''
            or #nonce > 96 or nonce:match('^[a-z0-9][a-z0-9_-]*$') == nil then
            self.entry_nonce = nil
            self.blocked = true
            return 'invalid_entry_nonce'
        end
        self.entry_nonce = nonce
        self.blocked = false
        return 'entered'
    elseif old_inside and not new_inside then
        self.entry_nonce = nil
        self.blocked = true
        return 'exited'
    elseif old_inside and new_inside and old_zone ~= new_zone then
        -- Sortie's U1/U2/U3 IDs are parallel instance allocations, not
        -- traversable layers of one run. A direct change is ambiguous.
        self.entry_nonce = nil
        self.blocked = true
        return 'ambiguous_instance_change'
    end
    return new_inside and 'unchanged_inside' or 'unchanged_outside'
end

function Session:unbind(block)
    if self.bound_entries then
        self.previous_entries = copy_map(self.bound_entries)
    end
    self.bound_run_id, self.bound_zone = nil, nil
    self.bound_cohort, self.bound_entries = nil, nil
    if block == true then self.blocked = true end
    return true
end

function Session:reconcile(summary)
    if self.blocked or not self.entry_nonce then
        if self.bound_run_id then
            self:unbind(true)
            return false, 'binding_lost'
        end
        return false, 'unbound'
    end
    if type(summary) ~= 'table' or summary.run_quorum ~= true
        or type(summary.run_id) ~= 'string' or summary.run_id == '' then
        -- A transient stale/missing peer stops evidence but does not invent a
        -- different instance. Only a contradictory complete cohort revokes.
        return self.bound_run_id ~= nil, 'waiting', self.bound_run_id
    end
    if summary.leader_entry_nonce ~= self.entry_nonce then
        if self.bound_run_id then self:unbind(true) end
        return false, 'leader_nonce_mismatch'
    end
    if type(summary.run_cohort) ~= 'string' or summary.run_cohort == ''
        or type(summary.entry_nonces) ~= 'table' then
        if self.bound_run_id then self:unbind(true) end
        return false, 'invalid_cohort'
    end
    -- Refuse the short window in which the leader has entered a new foray but
    -- one or more same-zone reports still carry the previous foray's nonce.
    -- This makes cohort rollover atomic even when the numeric instance ID is
    -- reused and old packets are still inside the freshness window.
    for name, nonce in pairs(self.previous_entries or {}) do
        if summary.entry_nonces[name] == nonce then
            return false, 'mixed_entry_cohort'
        end
    end
    if self.bound_run_id then
        if self.bound_run_id == summary.run_id
            and self.bound_zone == tonumber(summary.run_zone)
            and self.bound_cohort == summary.run_cohort then
            return true, 'stable', self.bound_run_id
        end
        self:unbind(true)
        return false, 'binding_changed'
    end
    self.bound_run_id = summary.run_id
    self.bound_zone = tonumber(summary.run_zone)
    self.bound_cohort = summary.run_cohort
    self.bound_entries = copy_map(summary.entry_nonces)
    return true, 'bound', self.bound_run_id
end

return Session
