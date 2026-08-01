-- Minimal Windower API smoke harness for loader/runtime validation.
-- Run with LuaJIT from the repository root:
--   luajit addons/AutoWS2/tests/smoke_harness.lua

_addon = {}

local callbacks = {}
local commands = {}
local chats = {}

package.preload.config = function()
    return {
        load = function(defaults)
            function defaults:save()
            end
            return defaults
        end,
    }
end

package.preload.texts = function()
    return {
        new = function()
            return {
                hide = function() end,
                show = function() end,
                text = function() end,
                pos = function() end,
            }
        end,
    }
end

package.preload.resources = function()
    return {
        items = {
            [1] = {id = 1, en = 'Tizona'},
        },
    }
end

local player = {
    id = 1,
    name = 'Dolomedes',
    main_job = 'BLU',
    status = 1,
    buffs = {},
    vitals = {tp = 1000},
}

windower = {
    add_to_chat = function(_, message)
        table.insert(chats, message)
    end,
    register_event = function(name, callback)
        callbacks[name] = callbacks[name] or {}
        table.insert(callbacks[name], callback)
    end,
    send_command = function(command)
        table.insert(commands, command)
    end,
    ffxi = {
        get_player = function()
            return player
        end,
        get_items = function(bag, slot)
            if bag == nil then
                return {
                    equipment = {
                        main = 1,
                        main_bag = 0,
                    },
                }
            end
            return {id = 1}
        end,
        get_mob_by_target = function()
            return {
                is_npc = true,
                hpp = 50,
            }
        end,
    },
}

local function emit(name, ...)
    for _, callback in ipairs(callbacks[name] or {}) do
        callback(...)
    end
end

dofile('addons/AutoWS2/AutoWS2.lua')
emit('load')
emit('addon command', 'status')
emit('addon command', 'on')
emit('prerender')

assert(_addon.name == 'AutoWS2')
assert(#chats > 0)
print('AutoWS2 smoke harness passed.')
