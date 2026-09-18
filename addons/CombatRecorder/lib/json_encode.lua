-- SPDX-License-Identifier: MIT
-- Small, dependency-free encoder. FFXI's non-UTF8 bytes are escaped, not emitted
-- as invalid JSON. Combat names on this installation are English.
local M = {}
local array_mt = {}
function M.array(value) return setmetatable(value or {}, array_mt) end

local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"\127-\255]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        return string.format('\\u%04x', c:byte())
    end) .. '"'
end

function M.encode(value)
    local seen = {}
    local function visit(v, depth)
        local kind = type(v)
        if kind == 'nil' then return 'null' end
        if kind == 'boolean' then return v and 'true' or 'false' end
        if kind == 'number' then
            if v ~= v or v == math.huge or v == -math.huge then return 'null' end
            return tostring(v)
        end
        if kind == 'string' then return quote(v) end
        assert(kind == 'table' and depth < 24 and not seen[v], 'invalid JSON value')
        seen[v] = true
        local count, is_array, entries = 0, true, {}
        for key in pairs(v) do
            count = count + 1
            if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then is_array = false end
        end
        is_array = is_array and (count > 0 or getmetatable(v) == array_mt) and count == #v
        if is_array then
            for i = 1, #v do entries[i] = visit(v[i], depth + 1) end
        else
            local keys = {}
            for key in pairs(v) do assert(type(key) == 'string', 'non-string JSON key'); keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do entries[#entries + 1] = quote(key) .. ':' .. visit(v[key], depth + 1) end
        end
        seen[v] = nil
        return (is_array and '[' or '{') .. table.concat(entries, ',') .. (is_array and ']' or '}')
    end
    return visit(value, 0)
end
return M
