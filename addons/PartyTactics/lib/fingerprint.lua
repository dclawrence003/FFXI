local M = {}

local function read_file(path)
    local handle = io.open(path, 'rb')
    if not handle then return nil end
    local text = handle:read('*a') or ''
    handle:close()
    return text
end

local function hash_text(text)
    local hash = 5381
    for index = 1, #(text or '') do
        hash = (hash * 33 + text:byte(index)) % 2147483647
    end
    return ('%08x'):format(hash)
end

local function encode_string(value)
    return ('s%d:%s'):format(#value, value)
end

local function canonical(value, seen)
    local kind = type(value)
    if kind == 'nil' then return 'n' end
    if kind == 'boolean' then return value and 'b1' or 'b0' end
    if kind == 'number' then return 'd'..tostring(value) end
    if kind == 'string' then return encode_string(value) end
    if kind ~= 'table' then
        error('unsupported manifest value type '..kind)
    end
    if seen[value] then error('cyclic manifest table') end
    seen[value] = true

    local entries = {}
    for key, child in pairs(value) do
        -- Loader metadata and the executable runtime module are represented by
        -- their source digests outside the declarative manifest.
        local internal = type(key) == 'string'
            and (key == 'runtime' or key:sub(1, 2) == '__')
        if not internal then
            local encoded_key = canonical(key, seen)
            entries[#entries + 1] = {
                key=encoded_key,
                value=canonical(child, seen),
            }
        end
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

function M.text(text)
    return hash_text(tostring(text or ''))
end

function M.file(path)
    local text = read_file(path)
    if text == nil then return 'unavailable' end
    return hash_text(text)
end

function M.contains(path, needle)
    if type(needle) ~= 'string' or needle == '' then return false end
    local text = read_file(path)
    return text ~= nil and text:find(needle, 1, true) ~= nil
end

function M.canonical(value)
    return canonical(value, {})
end

function M.combine(values)
    return hash_text(table.concat(values or {}, '\30'))
end

function M.plan(profile, plan, adapters, engine_digest)
    local parts = {
        'manifest', canonical(profile, {}),
        'profile-source', tostring(profile.__profile_source_digest or 'unavailable'),
        'runtime-source', tostring(profile.__runtime_source_digest or 'none'),
        'easyfarm-source', tostring(
            profile.__easyfarm_source_digest or 'none'),
        'compiled-plan', canonical(plan, {}),
        'engine-source', tostring(engine_digest or 'unavailable'),
    }
    if profile.gearswap_adapter then
        -- Only the active profile's exact GearSwap dependency closure is
        -- included. Creating or revising another fight's adapter therefore
        -- cannot alter this profile's behavior fingerprint.
        parts[#parts + 1] = 'gearswap-host-source'
        parts[#parts + 1] = tostring(
            profile.__gearswap_host_source_digest or 'unavailable')
        parts[#parts + 1] = 'gearswap-host-live'
        parts[#parts + 1] = tostring(
            profile.__gearswap_host_live_digest or 'unavailable')
        parts[#parts + 1] = 'gearswap-adapter-source:'
            ..tostring(profile.gearswap_adapter.id)..'@'
            ..tostring(profile.gearswap_adapter.version)
        parts[#parts + 1] = tostring(
            profile.__gearswap_adapter_source_digest or 'unavailable')
        parts[#parts + 1] = 'gearswap-adapter-live:'
            ..tostring(profile.gearswap_adapter.id)..'@'
            ..tostring(profile.gearswap_adapter.version)
        parts[#parts + 1] = tostring(
            profile.__gearswap_adapter_live_digest or 'unavailable')
    end
    local used = {}
    for _, policy in pairs(profile.manual_actions or {}) do
        if type(policy) == 'table' and type(policy.adapter) == 'string' then
            used[policy.adapter] = true
        end
    end
    local names = {}
    for name, _ in pairs(used) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local adapter = adapters and adapters[name]
        parts[#parts + 1] = 'adapter:'..name
        parts[#parts + 1] = tostring(adapter
            and adapter.__source_digest or 'unavailable')
    end
    return hash_text(table.concat(parts, '\30'))
end

return M
