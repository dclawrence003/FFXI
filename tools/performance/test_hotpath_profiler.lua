unpack = unpack or table.unpack

local wall = 1800000000
local cpu = 10
package.preload['socket'] = function()
    return {
        gettime = function()
            local value = wall
            wall = wall + 0.002
            return value
        end,
    }
end
os.clock = function()
    local value = cpu
    cpu = cpu + 0.001
    return value
end

local chat_messages = {}
windower = {
    addon_path = 'C:\\fake\\addon\\',
    add_to_chat = function(_, message)
        chat_messages[#chat_messages + 1] = message
    end,
    dir_exists = function() return true end,
    create_dir = function() error('unexpected directory creation') end,
    ffxi = {
        get_player = function() return {name='Dolomedes'} end,
    },
}

local profiler_module = assert(dofile('tools/performance/hotpath_profiler.lua'))
local profiler = profiler_module.new({
    addon = 'TestAddon',
    path = windower.addon_path,
})

local callback_calls = 0
local wrapped = profiler:wrap('action', function(value)
    callback_calls = callback_calls + 1
    return nil, value, nil
end)

local dormant = {n=select('#', wrapped('dormant')),
    wrapped('dormant')}
assert(callback_calls == 2)
assert(profiler.total_calls == 0)

profiler:start()
local measured = {n=select('#', wrapped('measured')),
    wrapped('measured')}
assert(callback_calls == 4)
assert(measured.n == 3)
assert(measured[1] == nil and measured[2] == 'measured' and measured[3] == nil)
assert(profiler.total_calls == 2)
assert(profiler.summary.action.calls == 2)
assert(profiler.summary.action.max_wall_ms >= 1.9)

local selected_calls = 0
local keyed = profiler:wrap_keyed(function(kind)
    return kind == 'measure' and 'selected' or nil
end, function()
    selected_calls = selected_calls + 1
end)
keyed('skip')
keyed('measure')
assert(selected_calls == 2)
assert(profiler.summary.selected.calls == 1)

local output = {}
io.open = function(path, mode)
    assert(path:find('testaddon%-perf%-Dolomedes'))
    assert(mode == 'w')
    return {
        write = function(_, ...)
            local values = {...}
            for _, value in ipairs(values) do output[#output + 1] = value end
        end,
        close = function() end,
    }
end
local path = profiler:stop()
assert(path and not profiler.enabled)
local csv = table.concat(output)
assert(csv:find('format,windower%-hotpath%-v1'))
assert(csv:find('summary,action'))
assert(csv:find('summary,selected'))
assert(#chat_messages >= 2)

print('Hot-path profiler Lua behavior tests passed.')
