-- Minimal Windower API smoke harness for loader/runtime validation.
-- Run with LuaJIT from the repository root:
--   luajit addons/AutoWS2/tests/smoke_harness.lua

_addon = {}

local callbacks = {}
local commands = {}
local chats = {}
local loaded_settings
local now = 100
os.clock = function() return now end
local mob = {id=100, name='Apollyon Demon', spawn_type=16, is_npc=true, hpp=50}
local mobs = {
    [100] = mob,
    [200] = {id=200, name='Apollyon Demon', spawn_type=16,
        is_npc=true, hpp=50},
}

package.preload.config = function()
    return {
        load = function(filepath, defaults)
            defaults = defaults or filepath
            loaded_settings = defaults
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

package.preload.packets = function()
    return {
        parse = function(_, packet) return packet end,
    }
end

package.preload.resources = function()
    local weapon_skills = {
        [2] = {id = 2, en = 'Expiacion'},
        [3] = {id = 3, en = 'Last Stand'},
    }
    function weapon_skills:with(field, value)
        for _, resource in pairs(self) do
            if type(resource) == 'table' and resource[field] == value then
                return resource
            end
        end
    end
    return {
        items = {
            [1] = {id = 1, en = 'Tizona'},
        },
        weapon_skills = weapon_skills,
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
        get_abilities = function()
            return {weapon_skills = {2,3}}
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
            return mob
        end,
        get_mob_by_id = function(id)
            return mobs[id]
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
assert(#commands > 0, 'ordinary target did not receive a weapon skill')
assert(commands[#commands]:find(' 100', 1, true),
    'weapon skill did not use the exact acknowledged battle-target ID')

-- A directed target-change packet must suppress only automatic WS until the
-- new exact battle target is visible. Manual /ws input is never intercepted.
local before_handoff = #commands
emit('outgoing chunk', 0x01A, {Category=0x0F, Target=200}, nil, true, false)
now = now + 10
emit('prerender')
assert(#commands == before_handoff,
    'automatic WS fired at the stale pre-handoff battle target')
mob = mobs[200]
now = now + .25
emit('prerender')
assert(#commands == before_handoff + 1,
    'automatic WS did not resume after exact battle-target acknowledgement')
assert(commands[#commands]:find(' 200', 1, true),
    'handoff weapon skill did not retain the exact new target ID')

-- A transient <bt> regression cannot pull automatic WS back to the old mob.
-- A completed direct attack on the assigned target remains authoritative and
-- lets exact-ID WS continue even while the local cursor display lags.
local before_drift = #commands
mob = mobs[100]
now = now + 3
emit('prerender')
assert(#commands == before_drift,
    'unacknowledged battle-target drift leaked an automatic weapon skill')
emit('action', {actor_id=player.id, category=1,
    targets={{id=200, actions={{message=1,param=10}}}}})
now = now + .25
emit('prerender')
assert(#commands == before_drift + 1,
    'direct combat evidence did not restore exact-target weapon skills')
assert(commands[#commands]:find(' 200', 1, true),
    'direct combat evidence resolved through the stale cursor')
mob = mobs[200]
local ordinary_commands = #commands

-- The safety is opt-in and session-only: an elemental is a normal target
-- until the active fight profile requests the exclusion.
mob.name = 'Fire Elemental'
now = now + 10
emit('prerender')
assert(#commands == ordinary_commands + 1,
    'default none exclusion blocked an elemental')
emit('addon command', 'exclude', 'elemental')
assert(chats[#chats]:find('Target exclusion: elemental', 1, true),
    'exclude command did not report the elemental exclusion')
emit('addon command', 'status')
assert(chats[#chats]:find('target exclusion=elemental', 1, true),
    'status did not report the elemental exclusion')
local excluded_commands = #commands
for _, mode in ipairs({'shadow','active'}) do
    emit('addon command', 'am', 'mode', mode)
    for _, name in ipairs({"Demon's Elemental", "Yagudo's Elemental",
        'Fire Elemental','Ice Elemental','Air Elemental','Earth Elemental',
        'Thunder Elemental','Water Elemental','Light Elemental','Dark Elemental',
        "DEMON'S ELEMENTAL"}) do
        mob.name = name
        player.vitals.tp = 3000
        now = now + 10
        emit('prerender')
        assert(#commands == excluded_commands, 'weapon skill fired at '..name..' in '..mode)
    end
end
mob.name = 'Elementalist'
now = now + 10
emit('prerender')
assert(#commands == excluded_commands + 1, 'non-elemental enemy was blocked')
emit('addon command', 'exclude', 'none')
assert(chats[#chats]:find('Target exclusion: none', 1, true),
    'exclude command did not report the cleared exclusion')
mob.name = 'Fire Elemental'
player.vitals.tp = 3000
now = now + 10
emit('prerender')
assert(#commands == excluded_commands + 2,
    'none exclusion did not restore elemental weapon skills')
assert(loaded_settings.profiles.dolomedes__blu__tizona__0,
    'weapon profile key was not canonicalized for XML reloads')

emit('addon command', 'sessionws', 'Last', 'Stand')
emit('addon command', 'aftermath', 'off')
player.vitals.tp = 1000
now = now + 10
emit('prerender')
assert(commands[#commands]:find('"Last Stand"', 1, true),
    'session automatic WS did not override the weapon profile')
emit('addon command', 'use', 'Expiacion')
now = now + 10
emit('prerender')
assert(commands[#commands]:find('"Expiacion"', 1, true),
    'manual //aws2 use did not release the session choice')
emit('addon command', 'sessionws', 'Last', 'Stand')
emit('addon command', 'off')
emit('addon command', 'on')
now = now + 10
emit('prerender')
assert(commands[#commands]:find('"Expiacion"', 1, true),
    'AutoWS2 off did not clear the fight-scoped automatic WS')
print('AutoWS2 smoke harness passed.')
print('AutoWS2 opt-in elemental rejection passed in shadow and active aftermath modes.')
