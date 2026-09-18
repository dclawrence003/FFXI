local M = {}

local function readonly(source, label)
    return setmetatable({}, {
        __index=source,
        __newindex=function()
            error((label or 'library')..' is read-only', 2)
        end,
        __metatable=false,
    })
end

local function environment()
    return {
        assert=assert,
        error=error,
        ipairs=ipairs,
        next=next,
        pairs=pairs,
        pcall=pcall,
        select=select,
        tonumber=tonumber,
        tostring=tostring,
        type=type,
        unpack=unpack,
        math=readonly(math, 'math'),
        string=readonly(string, 'string'),
        table=readonly(table, 'table'),
    }
end

local function apply_environment(chunk, target)
    if type(setfenv) == 'function' then
        setfenv(chunk, target)
        return true
    end
    -- Test runners may use Lua 5.2+. Windower uses Lua 5.1/setfenv, but
    -- supporting _ENV here keeps the sandbox regression-testable.
    if debug and type(debug.getupvalue) == 'function'
        and type(debug.setupvalue) == 'function'
    then
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
    return false, 'Lua runtime cannot apply a restricted chunk environment'
end

function M.wrap(chunk)
    if type(chunk) ~= 'function' then return nil, 'chunk is not callable' end
    local target = environment()
    local ok, apply_error = apply_environment(chunk, target)
    if not ok then return nil, apply_error end
    return chunk
end

function M.load(path, load_file)
    local chunk, load_error = load_file(path)
    if not chunk then return nil, load_error end
    return M.wrap(chunk)
end

return M
