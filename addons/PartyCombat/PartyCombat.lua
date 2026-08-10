--[[
PartyCombat

Role-scoped combat coordination for Windower multibox parties.

Independent implementation informed by the packet-level target coordination
concept in SendAllTarget by Selindrile, which thanks Arcon:
https://github.com/Selindrile/SendAllTarget
No SendAllTarget source is redistributed in this file.

Copyright (c) 2026 OpenAI

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES.
]]

_addon.name = 'PartyCombat'
_addon.author = 'OpenAI Codex'
_addon.version = '0.2.2'
_addon.commands = {'partycombat', 'pcombat', 'pc'}

local packets = require('packets')
local res = require('resources')
require('strings')

local PREFIX = 'PARTYCOMBAT1'
local AUTHORITY_INTERVAL = 2
local ENGAGE_RETRY_INTERVAL = 1.5
local MOVEMENT_INTERVAL = 0.08

local defaults = {
    leader = 'Dolomedes',
    attackers = {
        Tackleberry = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
        Kickpuncher = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
        Barneystinson = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
        Smalls = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
        Achoo = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
    },
}

-- PartyCombat only needs read-only settings. Windower's shared XML config
-- loader can fail when six local processes reload together, so use a normal
-- Lua table that is never rewritten by the addon.
local settings = defaults
local settings_warning = nil
local settings_loader, settings_load_error = loadfile(
    windower.addon_path..'data/settings.lua')
if settings_loader then
    local ok, loaded = pcall(settings_loader)
    if ok and type(loaded) == 'table'
        and type(loaded.leader) == 'string'
        and type(loaded.attackers) == 'table'
    then
        settings = loaded
    else
        settings_warning = ok and 'settings.lua did not return a valid table.'
            or tostring(loaded)
    end
else
    settings_warning = tostring(settings_load_error)
end
local armed = false
local authorized = false
local active_target_id = nil
local active_mode = nil
local pursuit_limit = nil
local next_authority = 0
local next_movement = 0
local last_engage_at = 0
local running = false
local last_ignore_target = nil
local last_ignore_at = 0

local function chat(color, message)
    windower.add_to_chat(color or 207, '[PartyCombat] '..message)
end

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function same_name(left, right)
    return type(left) == 'string'
        and type(right) == 'string'
        and left:lower() == right:lower()
end

local function local_player()
    return windower.ffxi.get_player()
end

local function local_name()
    local player = local_player()
    return player and player.name or nil
end

local function is_leader()
    return same_name(local_name(), settings.leader)
end

local function attacker_settings(name)
    if not valid_name(name) then return nil end
    for attacker_name, attacker in pairs(settings.attackers or {}) do
        if type(attacker) == 'table'
            and valid_name(attacker_name)
            and same_name(attacker_name, name)
        then
            return attacker
        end
    end
    return nil
end

local function is_attacker()
    return attacker_settings(local_name()) ~= nil
end

local function send_ipc(kind, ...)
    local fields = {PREFIX, kind, settings.leader}
    for index = 1, select('#', ...) do
        fields[#fields + 1] = tostring(select(index, ...))
    end
    windower.send_ipc_message(table.concat(fields, '|'))
end

local function broadcast_authority(enabled)
    for attacker_name, attacker in pairs(settings.attackers or {}) do
        if type(attacker) == 'table' and valid_name(attacker_name) then
            send_ipc('authority', attacker_name, enabled and '1' or '0')
        end
    end
end

local function distance_to(target)
    if not target or type(target.distance) ~= 'number' then
        return math.huge
    end
    return math.sqrt(math.max(0, target.distance))
end

local function valid_enemy(target)
    return target
        and target.spawn_type == 16
        and target.valid_target
        and type(target.hpp) == 'number'
        and target.hpp > 0
end

local function stop_running()
    if running then
        windower.ffxi.run(false)
        running = false
    end
end

local function clear_healbot_combat_automation()
    windower.send_command(
        'hb follow off; hb as off; hb as attack off')
    windower.ffxi.run(false)
    running = false
end

local function claim_combat_movement()
    windower.send_command('ffo stop')
    windower.ffxi.run(false)
    running = false
end

local function disengage_if_needed()
    local player = local_player()
    if player and player.status == 1 then
        windower.send_command('input /attack off')
    end
end

local function stop_local(reason, revoke)
    stop_running()
    disengage_if_needed()
    active_target_id = nil
    active_mode = nil
    pursuit_limit = nil
    last_engage_at = 0
    if revoke then
        authorized = false
    end
    if reason then
        chat(207, reason)
    end
end

local function inject_combat_target(target)
    local player = local_player()
    if not player or not valid_enemy(target) then return false end

    if player.status == 1 and player.target_index == target.index then
        return true
    end

    local now = os.clock()
    if now - last_engage_at < ENGAGE_RETRY_INTERVAL then
        return false
    end

    local category = player.status == 1 and 0x0F or 0x02
    packets.inject(packets.new('outgoing', 0x01A, {
        ['Target'] = target.id,
        ['Target Index'] = target.index,
        ['Category'] = category,
    }))
    last_engage_at = now
    return true
end

local function ignored_target_message(target, distance, limit)
    local now = os.clock()
    if last_ignore_target ~= target.id or now - last_ignore_at > 10 then
        chat(123, ('Ignored automatic target %s at %.1f yalms (limit %.1f).')
            :format(target.name or target.id, distance, limit))
        last_ignore_target = target.id
        last_ignore_at = now
    end
end

local function accept_target(id, mode)
    if not authorized or not is_attacker() then return end

    local target = windower.ffxi.get_mob_by_id(tonumber(id))
    if not valid_enemy(target) then return end

    local attacker = attacker_settings(local_name())
    if not attacker then return end

    local force = mode == 'force'
    local limit = tonumber(
        force and attacker.force_distance or attacker.auto_distance)
        or (force and 30 or 10)
    local distance = distance_to(target)

    if distance > limit then
        if force then
            chat(123, ('Cannot force %s: %.1f yalms exceeds %.1f-yalm limit.')
                :format(target.name or target.id, distance, limit))
        else
            ignored_target_message(target, distance, limit)
        end
        return
    end

    -- FastFollow remains user-owned while PartyCombat is merely armed. Stop
    -- it only when this attacker has accepted a real combat target and
    -- PartyCombat is about to take movement control.
    claim_combat_movement()
    active_target_id = target.id
    active_mode = force and 'force' or 'auto'
    pursuit_limit = limit
    last_ignore_target = nil
    inject_combat_target(target)
end

local function current_leader_target()
    local target = windower.ffxi.get_mob_by_target('t')
    if valid_enemy(target) then return target end
    return nil
end

local function arm()
    armed = true
    next_authority = 0
    broadcast_authority(true)
    chat(158,
        'Armed. Damage-target synchronization is active for configured attackers.')
end

local function force_current_target()
    local target = current_leader_target()
    if not target then
        chat(123, 'Force engage requires a living enemy target.')
        return
    end
    if not armed then arm() else broadcast_authority(true) end
    send_ipc('target', target.id, 'force')
    chat(158, ('Forced approach and engagement: %s.')
        :format(target.name or target.id))
end

local function stop_all()
    armed = false
    broadcast_authority(false)
    send_ipc('stop')
    stop_local(nil, true)
    chat(207, 'Disarmed and stopped all configured attackers.')
end

local function damage_target(action)
    if not action or not action.targets then return nil end

    local physical = action.category == 1
        or action.category == 2
        or action.category == 3

    for _, target_action in ipairs(action.targets) do
        local target = target_action.id
            and windower.ffxi.get_mob_by_id(target_action.id)
            or nil
        if valid_enemy(target) then
            if physical then return target end

            if action.category == 4 then
                local result = target_action.actions
                    and target_action.actions[1]
                    or nil
                local message = result
                    and res.action_messages[result.message]
                    or nil
                if message and message.color == 'D' then
                    return target
                end
            end
        end
    end
    return nil
end

windower.register_event('action', function(action)
    if not armed or not is_leader() then return end
    local player = local_player()
    if not player or action.actor_id ~= player.id then return end

    local target = damage_target(action)
    if target then
        send_ipc('target', target.id, 'auto')
    end
end)

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string'
        or not message:startswith(PREFIX..'|')
    then
        return
    end

    local fields = {}
    for field in message:gmatch('[^|]+') do
        fields[#fields + 1] = field
    end
    local kind = fields[2]
    local leader = fields[3]
    if not same_name(leader, settings.leader) then return end

    if kind == 'authority' then
        local attacker_name = fields[4]
        local enabled = fields[5] == '1'
        if same_name(local_name(), attacker_name) and is_attacker() then
            local was_authorized = authorized
            authorized = enabled
            if enabled and not was_authorized then
                clear_healbot_combat_automation()
            elseif not enabled then
                stop_local(nil, true)
            end
        end
    elseif kind == 'target' and authorized then
        accept_target(fields[4], fields[5])
    elseif kind == 'stop' and is_attacker() then
        stop_local(nil, true)
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()

    if armed and is_leader() and now >= next_authority then
        next_authority = now + AUTHORITY_INTERVAL
        broadcast_authority(true)
    end

    if not authorized or not active_target_id or now < next_movement then
        return
    end
    next_movement = now + MOVEMENT_INTERVAL

    local target = windower.ffxi.get_mob_by_id(active_target_id)
    if not valid_enemy(target) then
        stop_local('Target ended; attacker stopped.', false)
        return
    end

    local self = windower.ffxi.get_mob_by_target('me')
    if not self then
        stop_running()
        return
    end

    local distance = distance_to(target)
    local attacker = attacker_settings(local_name())
    local engage_distance = tonumber(attacker and attacker.engage_distance)
        or 2.8

    if distance > (pursuit_limit or 0) then
        stop_running()
        return
    end

    inject_combat_target(target)

    if distance > engage_distance then
        local dx = target.x - self.x
        local dy = target.y - self.y
        local length = math.sqrt(dx * dx + dy * dy)
        if length > 0.1 then
            windower.ffxi.run(dx / length, dy / length)
            running = true
        end
    else
        stop_running()
    end
end)

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'status'

    if command == 'status' then
        local role = is_leader() and 'leader'
            or (is_attacker() and 'attacker' or 'observer')
        local target = active_target_id
            and windower.ffxi.get_mob_by_id(active_target_id)
            or nil
        chat(207, ('Role %s | armed %s | authorized %s | target %s | mode %s')
            :format(
                role,
                armed and 'On' or 'Off',
                authorized and 'Yes' or 'No',
                target and target.name or 'none',
                tostring(active_mode or 'none')))
    elseif command == 'on' or command == 'arm' or command == 'auto' then
        if not is_leader() then
            chat(123, 'Only the configured leader can arm PartyCombat.')
            return
        end
        arm()
    elseif command == 'force' or command == 'engage'
        or command == 'attack'
    then
        if not is_leader() then
            chat(123, 'Only the configured leader can force engagement.')
            return
        end
        force_current_target()
    elseif command == 'off' or command == 'stop' then
        if not is_leader() then
            stop_local('Local attacker stopped.', true)
            return
        end
        stop_all()
    elseif command == 'help' then
        chat(207,
            'Commands: on | force | stop | status. Force also arms automatic tracking.')
    else
        chat(123, 'Unknown command. Use //pc help.')
    end
end)

windower.register_event('zone change', function()
    if armed and is_leader() then
        broadcast_authority(false)
    end
    armed = false
    authorized = false
    stop_local(nil, true)
end)

windower.register_event('logout', 'unload', function()
    if armed and is_leader() then
        broadcast_authority(false)
    end
    stop_running()
end)

chat(158,
    'Loaded inert. Use //pc force on the leader or Alt+P; Alt+O stops combat.')
if settings_warning then
    chat(123,
        'settings.lua was unavailable during startup; using safe defaults. '
        ..settings_warning)
end
