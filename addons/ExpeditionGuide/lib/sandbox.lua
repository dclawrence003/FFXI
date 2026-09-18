-- Restricted loader for declarative Lua content. Content can construct and
-- return plain tables, but cannot see Windower, require, io, os, debug, or any
-- mutable shared library. Production discovery never executes route/profile
-- files through require.

local Sandbox = {}
local MAX_BYTES = 65536
local MAX_DEPTH = 16
local MAX_NODES = 4096
local MAX_STRING_BYTES = 2048
local MAX_INSTRUCTIONS = 25000

local function environment()
    -- Manifests are data, not extension scripts.  These three conversions are
    -- pure and bounded by the already-limited manifest input.  Do not expose
    -- whole standard-library tables: even read-only wrappers still expose
    -- stateful functions (for example math.randomseed) and cheap allocation
    -- amplifiers (string.rep/table.concat).
    return {
        tonumber=tonumber,
        tostring=tostring,
        type=type,
    }
end

local function apply_environment(chunk, target)
    if type(setfenv) == 'function' then
        setfenv(chunk, target)
        return true
    end
    if debug and type(debug.getupvalue) == 'function'
        and type(debug.setupvalue) == 'function' then
        local index = 1
        while true do
            local name = debug.getupvalue(chunk, index)
            if not name then break end
            if name == '_ENV' then
                debug.setupvalue(chunk, index, target)
                return true
            end
            index = index + 1
        end
    end
    return false, 'Lua runtime cannot apply a restricted content environment'
end

function Sandbox.load(path, load_file)
    local file = io.open(path, 'rb')
    if not file then return nil, 'content file is unavailable' end
    local size = file:seek('end') or 0
    file:close()
    if size > MAX_BYTES then return nil, 'content file exceeds size limit' end
    local chunk, load_error = (load_file or loadfile)(path)
    if not chunk then return nil, load_error end
    local applied, apply_error = apply_environment(chunk, environment())
    if not applied then return nil, apply_error end
    local previous_hook, previous_mask, previous_count
    local hooked = debug and type(debug.sethook) == 'function'
    if not hooked then
        return nil, 'Lua runtime cannot enforce content instruction limit'
    end
    if hooked and type(debug.gethook) == 'function' then
        previous_hook, previous_mask, previous_count = debug.gethook()
    end
    if hooked then
        debug.sethook(function() error('content instruction limit exceeded') end,
            '', MAX_INSTRUCTIONS)
    end
    local ok, value = pcall(chunk)
    if hooked then
        if previous_hook then
            debug.sethook(previous_hook, previous_mask or '', previous_count or 0)
        else
            debug.sethook()
        end
    end
    if not ok then return nil, value end
    if type(value) ~= 'table' then return nil, 'content did not return a table' end

    local seen, nodes = {}, 0
    local function validate_plain(item, depth)
        nodes = nodes + 1
        if nodes > MAX_NODES then return false, 'content node limit exceeded' end
        if depth > MAX_DEPTH then return false, 'content nesting limit exceeded' end
        local kind = type(item)
        if kind == 'string' then
            return #item <= MAX_STRING_BYTES, 'content string exceeds size limit'
        end
        if kind == 'number' then
            return item == item and item > -math.huge and item < math.huge,
                'content contains a non-finite number'
        end
        if kind == 'nil' or kind == 'boolean' then return true end
        if kind ~= 'table' then return false, 'content contains ' .. kind end
        if getmetatable(item) ~= nil then return false, 'content contains a metatable' end
        if seen[item] then return false, 'content contains a cycle' end
        seen[item] = true
        for key, child in pairs(item) do
            local key_ok, key_error = validate_plain(key, depth + 1)
            if not key_ok then return false, key_error end
            local child_ok, child_error = validate_plain(child, depth + 1)
            if not child_ok then return false, child_error end
        end
        seen[item] = nil
        return true
    end
    local plain, plain_error = validate_plain(value, 0)
    if not plain then return nil, plain_error end
    return value
end

return Sandbox
