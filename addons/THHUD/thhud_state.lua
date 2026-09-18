-- Pure per-mob Treasure Hunter state.  This module has no Windower dependency
-- so packet-derived transitions can be regression tested outside the game.

local State = {}
State.__index = State
local MAX_TH = 14

local function valid_value(value)
    value = tonumber(value)
    if not value or value < 1 or value > MAX_TH
        or value ~= math.floor(value) then
        return nil
    end
    return value
end

local function valid_identity(mob_id, signature)
    mob_id = tonumber(mob_id)
    if not mob_id or mob_id <= 0 or type(signature) ~= 'string'
        or signature == '' then
        return nil
    end
    return mob_id
end

local function fresh_record(self, mob_id, signature, value, confidence, meta)
    local record = {
        mob_id = mob_id,
        signature = signature,
        value = value,
        confidence = confidence,
        source = meta and meta.source or 'local',
        sender = meta and meta.sender or nil,
        updated_at = meta and tonumber(meta.updated_at) or 0,
    }
    self.mobs[mob_id] = record
    return true, record
end

function State.new(zone)
    return setmetatable({zone = tonumber(zone), mobs = {}}, State)
end

function State:set_zone(zone)
    zone = tonumber(zone)
    if self.zone == zone then
        return false
    end
    self.zone = zone
    self.mobs = {}
    return true
end

function State:clear_all()
    self.mobs = {}
end

function State:get(mob_id, signature)
    local record = self.mobs[tonumber(mob_id)]
    if not record then
        return nil
    end
    if signature and record.signature ~= signature then
        return nil
    end
    return record
end

function State:apply_inferred(mob_id, signature, value, meta)
    mob_id = valid_identity(mob_id, signature)
    value = valid_value(value)
    if not mob_id or not value then
        return false, nil, 'invalid inferred observation'
    end

    local record = self.mobs[mob_id]
    if not record or record.signature ~= signature then
        return fresh_record(self, mob_id, signature, value, 'inferred', meta)
    end

    -- TH never falls because a later character applies a weaker base value.
    if value <= record.value then
        return false, record, 'not higher'
    end

    record.value = value
    record.confidence = 'inferred'
    record.source = meta and meta.source or record.source
    record.sender = meta and meta.sender or record.sender
    record.updated_at = meta and tonumber(meta.updated_at) or record.updated_at
    return true, record
end

function State:apply_confirmed(mob_id, signature, value, meta)
    mob_id = valid_identity(mob_id, signature)
    value = valid_value(value)
    if not mob_id or not value then
        return false, nil, 'invalid confirmed observation'
    end

    local record = self.mobs[mob_id]
    if not record or record.signature ~= signature then
        return fresh_record(self, mob_id, signature, value, 'confirmed', meta)
    end

    -- An authoritative packet corrects an inferred estimate even when the
    -- estimate was too high.  Confirmed TH packets themselves are monotonic,
    -- so delayed/duplicate lower confirmed values are ignored.
    if record.confidence == 'confirmed' and value <= record.value then
        return false, record, 'confirmed duplicate or stale value'
    end

    local changed = record.value ~= value or record.confidence ~= 'confirmed'
    record.value = value
    record.confidence = 'confirmed'
    record.source = meta and meta.source or record.source
    record.sender = meta and meta.sender or record.sender
    record.updated_at = meta and tonumber(meta.updated_at) or record.updated_at
    return changed, record
end

function State:clear(mob_id, signature)
    mob_id = tonumber(mob_id)
    local record = mob_id and self.mobs[mob_id] or nil
    if not record then
        return false
    end
    if signature and record.signature ~= signature then
        return false
    end
    self.mobs[mob_id] = nil
    return true
end

function State:snapshot()
    local result = {}
    for _, record in pairs(self.mobs) do
        result[#result + 1] = {
            mob_id = record.mob_id,
            signature = record.signature,
            value = record.value,
            confidence = record.confidence,
            source = record.source,
            sender = record.sender,
            updated_at = record.updated_at,
        }
    end
    table.sort(result, function(left, right)
        return left.mob_id < right.mob_id
    end)
    return result
end

return State
