local M = {}

function M.valid_name(value)
    return type(value) == 'string'
        and value:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #value <= 15
end

function M.valid_id(value, maximum)
    return type(value) == 'string'
        and value:match('^[a-z0-9][a-z0-9_-]*$') ~= nil
        and #value <= (maximum or 64)
end

function M.same_name(left, right)
    return type(left) == 'string' and type(right) == 'string'
        and left:lower() == right:lower()
end

function M.contains_name(values, wanted)
    if not M.valid_name(wanted) then return false end
    for _, value in ipairs(values or {}) do
        if M.valid_name(value) and M.same_name(value, wanted) then
            return true
        end
    end
    return false
end

function M.contains_value(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then return true end
    end
    return false
end

function M.sorted_keys(values)
    local result = {}
    for key, _ in pairs(values or {}) do result[#result + 1] = key end
    table.sort(result, function(left, right)
        return tostring(left):lower() < tostring(right):lower()
    end)
    return result
end

function M.csv(values)
    return values and #values > 0 and table.concat(values, ',') or '-'
end

function M.copy_array(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

function M.split(value, separator)
    local result = {}
    if type(value) ~= 'string' then return result end
    separator = separator or '|'
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
end

function M.clean_field(value)
    return tostring(value or ''):gsub('[|\r\n]', ' '):sub(1, 180)
end

function M.count(values)
    local total = 0
    for _, _ in pairs(values or {}) do total = total + 1 end
    return total
end

function M.party_name_set(party)
    local result = {}
    for key, member in pairs(party or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and M.valid_name(member.name)
        then
            result[member.name:lower()] = true
        end
    end
    return result
end

return M
