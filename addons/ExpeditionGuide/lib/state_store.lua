-- Small deterministic Lua-table store with recoverable replacement.  Runtime
-- state is per character so six Windower processes never share a writer.

local Store = {}
local MAX_STATE_BYTES = 1048576
local MAX_STATE_INSTRUCTIONS = 100000

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return left < right end
        return type(left) < type(right)
    end)
    return keys
end

local function serialize(value, seen)
    local kind = type(value)
    if kind == 'nil' then return 'nil' end
    if kind == 'boolean' or kind == 'number' then return tostring(value) end
    if kind == 'string' then return string.format('%q', value) end
    if kind ~= 'table' then error('unsupported state type ' .. kind) end
    seen = seen or {}
    if seen[value] then error('cyclic state table') end
    seen[value] = true
    local parts = {'{'}
    for _, key in ipairs(sorted_keys(value)) do
        parts[#parts + 1] = '[' .. serialize(key, seen) .. ']='
            .. serialize(value[key], seen) .. ','
    end
    parts[#parts + 1] = '}'
    seen[value] = nil
    return table.concat(parts)
end

function Store.load(path)
    local probe, probe_error = io.open(path, 'r')
    if not probe then return nil, probe_error end
    if type(probe.seek) == 'function' then
        local size, size_error = probe:seek('end')
        probe:close()
        if not size then return nil, size_error or 'could not inspect state size' end
        if size > MAX_STATE_BYTES then return nil, 'state file exceeds size limit' end
    else
        probe:close()
    end
    local loader, load_error = loadfile(path)
    if not loader then return nil, load_error end
    if setfenv then
        setfenv(loader, {})
    elseif debug and type(debug.getupvalue) == 'function'
        and type(debug.setupvalue) == 'function' then
        local applied, index = false, 1
        while true do
            local name = debug.getupvalue(loader, index)
            if not name then break end
            if name == '_ENV' then
                debug.setupvalue(loader, index, {})
                applied = true
                break
            end
            index = index + 1
        end
        if not applied then return nil, 'could not restrict state environment' end
    else
        return nil, 'could not restrict state environment'
    end

    local previous_hook, previous_mask, previous_count
    if not debug or type(debug.sethook) ~= 'function' then
        return nil, 'state runtime has no instruction-limit support'
    end
    if type(debug.gethook) == 'function' then
        previous_hook, previous_mask, previous_count = debug.gethook()
    end
    debug.sethook(function() error('state instruction limit exceeded') end,
        '', MAX_STATE_INSTRUCTIONS)
    local ok, value = pcall(loader)
    if previous_hook then
        debug.sethook(previous_hook, previous_mask or '', previous_count or 0)
    else
        debug.sethook()
    end
    if not ok or type(value) ~= 'table' then
        return nil, ok and 'state did not return a table' or tostring(value)
    end
    return value
end

function Store.save(path, value)
    local temporary = path .. '.tmp'
    local backup = path .. '.bak'
    local previous = path .. '.previous'
    local ok, payload = pcall(serialize, value)
    if not ok then os.remove(temporary); return false, payload end
    local file, open_error = io.open(temporary, 'w')
    if not file then return false, open_error end
    local function abort_write(reason)
        pcall(function() file:close() end)
        os.remove(temporary)
        return false, reason
    end
    local written, write_error = file:write('return ', payload, '\n')
    if not written then return abort_write(write_error or 'state write failed') end
    local flushed, flush_error = file:flush()
    if not flushed then return abort_write(flush_error or 'state flush failed') end
    local closed, close_error = file:close()
    if not closed then
        os.remove(temporary)
        return false, close_error or 'state close failed'
    end

    local existing = io.open(path, 'r')
    local had_primary = existing ~= nil
    if existing then
        existing:close()
        local stale = io.open(previous, 'r')
        if stale then
            stale:close()
            local removed, remove_error = os.remove(previous)
            if not removed then
                os.remove(temporary)
                return false, remove_error or 'could not clear stale recovery state'
            end
        end
        local moved, move_error = os.rename(path, previous)
        if not moved then os.remove(temporary); return false, move_error end
    end
    local replaced, replace_error = os.rename(temporary, path)
    if not replaced then
        if had_primary then os.rename(previous, path) end
        os.remove(temporary)
        return false, replace_error
    end
    if had_primary then
        -- Keep the older .bak intact until the new primary is safely in place.
        -- If backup rotation itself fails, .previous remains another recoverable
        -- copy and the successfully replaced primary is never rolled back.
        local old_backup = io.open(backup, 'r')
        if old_backup then
            old_backup:close()
            local removed = os.remove(backup)
            if not removed then return true, 'previous state retained in .previous' end
        end
        local rotated = os.rename(previous, backup)
        if not rotated then return true, 'previous state retained in .previous' end
    end
    return true
end

function Store.serialize(value)
    return serialize(value)
end

return Store
