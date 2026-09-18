local Fingerprint = {}

local function hash_text(value)
    local hash = 5381
    for index = 1, #(value or '') do
        hash = (hash * 33 + value:byte(index)) % 2147483647
    end
    return ('%08x'):format(hash)
end

local function canonical(value, seen)
    local kind = type(value)
    if kind == 'nil' then return 'n' end
    if kind == 'boolean' then return value and 'b1' or 'b0' end
    if kind == 'number' then return 'd' .. tostring(value) end
    if kind == 'string' then return ('s%d:%s'):format(#value, value) end
    if kind ~= 'table' then error('unsupported fingerprint type ' .. kind) end
    if seen[value] then error('cyclic fingerprint input') end
    seen[value] = true
    local entries = {}
    for key, child in pairs(value) do
        local encoded_key = canonical(key, seen)
        entries[#entries + 1] = {
            key=encoded_key,
            value=canonical(child, seen),
        }
    end
    table.sort(entries, function(left, right) return left.key < right.key end)
    local result = {'t', tostring(#entries), '{'}
    for _, entry in ipairs(entries) do
        result[#result + 1] = entry.key
        result[#result + 1] = '='
        result[#result + 1] = entry.value
        result[#result + 1] = ';'
    end
    result[#result + 1] = '}'
    seen[value] = nil
    return table.concat(result)
end

function Fingerprint.value(value)
    return hash_text(canonical(value, {}))
end

return Fingerprint
