-- Strict, namespaced IPC codec.  Payloads contain no free-form mob names;
-- receivers independently validate the live mob signature before accepting.

local Protocol = {PREFIX = 'THHUD', VERSION = '1'}
local MAX_TH = 14

local function split(value)
    local result = {}
    for field in (tostring(value or '') .. '|'):gmatch('(.-)|') do
        result[#result + 1] = field
    end
    return result
end

local function integer(value, low, high)
    local number = tonumber(value)
    if not number or number ~= math.floor(number)
        or (low and number < low) or (high and number > high) then
        return nil
    end
    return number
end

local function valid_sender(sender)
    return type(sender) == 'string' and #sender >= 1 and #sender <= 24
        and sender:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
end

local function valid_signature(signature)
    return type(signature) == 'string' and #signature >= 8 and #signature <= 64
        and signature:match('^[0-9A-Fa-f%-]+$') ~= nil
end

function Protocol.hello(sender, zone, sent_at)
    return table.concat({Protocol.PREFIX, Protocol.VERSION, 'HELLO', sender,
        tostring(zone), tostring(sent_at)}, '|')
end

function Protocol.observe(sender, zone, sent_at, mob_id, signature, value,
    confidence)
    local compact = confidence == 'confirmed' and 'C' or 'I'
    return table.concat({Protocol.PREFIX, Protocol.VERSION, 'OBS', sender,
        tostring(zone), tostring(sent_at), tostring(mob_id), signature,
        tostring(value), compact}, '|')
end

function Protocol.clear(sender, zone, sent_at, mob_id, signature)
    return table.concat({Protocol.PREFIX, Protocol.VERSION, 'CLEAR', sender,
        tostring(zone), tostring(sent_at), tostring(mob_id), signature}, '|')
end

function Protocol.decode(message)
    local fields = split(message)
    if fields[1] ~= Protocol.PREFIX or fields[2] ~= Protocol.VERSION then
        return nil, 'foreign namespace or version'
    end

    local kind, sender = fields[3], fields[4]
    if not valid_sender(sender) then
        return nil, 'invalid sender'
    end
    local zone = integer(fields[5], 0, 4095)
    local sent_at = integer(fields[6], 0)
    if not zone or not sent_at then
        return nil, 'invalid zone or timestamp'
    end

    if kind == 'HELLO' and #fields == 6 then
        return {kind = kind, sender = sender, zone = zone, sent_at = sent_at}
    elseif kind == 'OBS' and #fields == 10 then
        local mob_id = integer(fields[7], 1, 4294967295)
        local value = integer(fields[9], 1, MAX_TH)
        local confidence = fields[10] == 'C' and 'confirmed'
            or fields[10] == 'I' and 'inferred' or nil
        if not mob_id or not valid_signature(fields[8]) or not value
            or not confidence then
            return nil, 'invalid observation payload'
        end
        return {kind = kind, sender = sender, zone = zone, sent_at = sent_at,
            mob_id = mob_id, signature = fields[8], value = value,
            confidence = confidence}
    elseif kind == 'CLEAR' and #fields == 8 then
        local mob_id = integer(fields[7], 1, 4294967295)
        if not mob_id or not valid_signature(fields[8]) then
            return nil, 'invalid clear payload'
        end
        return {kind = kind, sender = sender, zone = zone, sent_at = sent_at,
            mob_id = mob_id, signature = fields[8]}
    end

    return nil, 'invalid message kind or field count'
end

function Protocol.validate(message, context)
    local payload, reason = Protocol.decode(message)
    if not payload then
        return nil, reason
    end
    context = context or {}
    if tonumber(context.zone) ~= payload.zone then
        return nil, 'wrong zone'
    end
    local now = tonumber(context.now) or os.time()
    local max_age = tonumber(context.max_age) or 8
    if payload.sent_at > now + 2 or now - payload.sent_at > max_age then
        return nil, 'stale timestamp'
    end
    if context.allowed_sender and not context.allowed_sender(payload.sender) then
        return nil, 'sender is not an allowed peer'
    end
    return payload
end

return Protocol
