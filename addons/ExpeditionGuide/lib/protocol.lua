-- Read-only multi-client state protocol. No message type can request an
-- action. Version 2 binds every bitstring to an exact pack/catalog contract.
-- Its fixed 21-field shape includes entry_nonce; this was added before v2 was
-- deployed, so the earlier 20-field development shape is deliberately rejected.

local Protocol = {}
local PREFIX = 'EG|2|'

local function split(value)
    local fields = {}
    for part in (tostring(value) .. '|'):gmatch('(.-)|') do
        fields[#fields + 1] = part
    end
    return fields
end

local function finite(value, low, high)
    value = tonumber(value)
    if not value or value ~= value or value < low or value > high then
        return nil
    end
    return value
end

local function valid_name(value)
    return type(value) == 'string' and value:match('^[A-Za-z]+$') ~= nil
        and #value <= 20
end

local JOBS = {}
for _, job in ipairs({
    'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG',
    'SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN',
}) do JOBS[job] = true end

local function valid_job(value, ready)
    return JOBS[value] == true or (ready ~= true and value == '')
end

local function valid_id(value, limit)
    return type(value) == 'string' and #value >= 1
        and #value <= (limit or 96)
        and value:match('^[a-z0-9][a-z0-9_-]*$') ~= nil
end

local function catalog_count(catalog, field)
    local value = catalog and catalog[field]
    if type(value) == 'table' and type(value.ordered) == 'table' then
        return #value.ordered
    end
    return tonumber(catalog and catalog[field .. '_count'])
end

function Protocol.state(payload)
    assert(type(payload) == 'table', 'payload required')
    assert(valid_id(payload.pack_id, 80), 'valid pack id required')
    assert(valid_id(payload.catalog_id, 120), 'valid catalog id required')
    assert(payload.entry_nonce == nil or payload.entry_nonce == ''
        or valid_id(payload.entry_nonce, 96), 'valid entry nonce required')
    return table.concat({
        'EG', '2', 'STATE', payload.pack_id, payload.catalog_id,
        tostring(payload.sender or ''),
        tostring(payload.main_job or ''), tostring(payload.sub_job or ''),
        tostring(math.floor(tonumber(payload.zone) or 0)),
        tostring(math.floor(tonumber(payload.timestamp) or 0)),
        tostring(math.floor(tonumber(payload.sequence) or 0)),
        ('%.2f'):format(tonumber(payload.x) or 0),
        ('%.2f'):format(tonumber(payload.y) or 0),
        ('%.2f'):format(tonumber(payload.z) or 0),
        tostring(math.floor(tonumber(payload.status) or 0)),
        payload.ready == true and '1' or '0',
        payload.party_exact == true and '1' or '0',
        payload.leader_exact == true and '1' or '0',
        tostring(payload.entry_nonce or ''),
        tostring(payload.items or ''),
        tostring(payload.key_items or ''),
    }, '|')
end

function Protocol.validate(message, options)
    options = options or {}
    if type(message) ~= 'string' or #message > 512
        or message:sub(1, #PREFIX) ~= PREFIX then
        return nil, 'foreign, legacy, or oversized message'
    end
    local fields = split(message)
    if #fields ~= 21 or fields[1] ~= 'EG' or fields[2] ~= '2'
        or fields[3] ~= 'STATE' then
        return nil, 'invalid envelope'
    end
    local pack_id, catalog_id = fields[4], fields[5]
    if not valid_id(pack_id, 80) or not valid_id(catalog_id, 120) then
        return nil, 'invalid pack or catalog identity'
    end
    local catalog = type(options.catalogs) == 'table'
        and options.catalogs[pack_id] or nil
    if type(catalog) ~= 'table' then return nil, 'unknown pack' end
    if catalog.catalog_id ~= catalog_id then return nil, 'catalog mismatch' end

    local sender = fields[6]
    if not valid_name(sender) then return nil, 'invalid sender' end
    if type(options.allowed_sender) == 'function'
        and not options.allowed_sender(sender) then
        return nil, 'sender not allowed'
    end
    local main_job, sub_job = fields[7], fields[8]
    local zone = finite(fields[9], 0, 1024)
    local timestamp = finite(fields[10], 1, 4102444800)
    local sequence = finite(fields[11], 0, 2147483647)
    local x = finite(fields[12], -10000, 10000)
    local y = finite(fields[13], -10000, 10000)
    local z = finite(fields[14], -10000, 10000)
    local status = finite(fields[15], 0, 64)
    local ready_field = fields[16]
    local party_field, leader_field = fields[17], fields[18]
    local entry_nonce = fields[19]
    local items, key_items = fields[20], fields[21]
    if not zone or zone ~= math.floor(zone) or not timestamp
        or timestamp ~= math.floor(timestamp) or not sequence
        or sequence ~= math.floor(sequence) or not x or not y or not z
        or not status or status ~= math.floor(status) then
        return nil, 'invalid numeric field'
    end
    if ready_field ~= '0' and ready_field ~= '1' then
        return nil, 'invalid readiness evidence'
    end
    local ready = ready_field == '1'
    if not valid_job(main_job, ready) or not valid_job(sub_job, ready) then
        return nil, 'invalid job evidence'
    end
    if (party_field ~= '0' and party_field ~= '1')
        or (leader_field ~= '0' and leader_field ~= '1') then
        return nil, 'invalid party evidence'
    end
    if entry_nonce ~= '' and (not valid_id(entry_nonce, 96)
        or type(catalog.instance_zones) ~= 'table'
        or catalog.instance_zones[zone] ~= true) then
        return nil, 'invalid entry nonce'
    end
    local item_count = catalog_count(catalog, 'items')
    local key_item_count = catalog_count(catalog, 'key_items')
    if not item_count or #items ~= item_count or items:match('[^01]') then
        return nil, 'invalid item evidence'
    end
    if not key_item_count or #key_items ~= key_item_count
        or key_items:match('[^01]') then
        return nil, 'invalid key-item evidence'
    end
    local now = tonumber(options.now) or os.time()
    local max_age = tonumber(options.max_age) or 8
    if timestamp < now - max_age or timestamp > now + 2 then
        return nil, 'stale timestamp'
    end
    return {
        kind='STATE', pack_id=pack_id, catalog_id=catalog_id,
        sender=sender, main_job=main_job, sub_job=sub_job,
        zone=zone, timestamp=timestamp, sequence=sequence,
        x=x, y=y, z=z, status=status, ready=ready,
        party_exact=party_field == '1', leader_exact=leader_field == '1',
        entry_nonce=entry_nonce,
        items=items, key_items=key_items,
    }
end

function Protocol.is_ours(message)
    return type(message) == 'string' and message:sub(1, #PREFIX) == PREFIX
end

return Protocol
