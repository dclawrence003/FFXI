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
_addon.version = '0.3.0'
_addon.commands = {'partycombat', 'pcombat', 'pc'}

local packets = require('packets')
local res = require('resources')
require('strings')

local PREFIX = 'PARTYCOMBAT1'
local AUTHORITY_INTERVAL = 2
local ENGAGE_RETRY_INTERVAL = 1.5
local MOVEMENT_INTERVAL = 0.08
local POST_ZONE_FOLLOW_DELAY = 3.5
local POST_ZONE_FOLLOW_ATTEMPTS = 3
local RECENT_FOLLOW_CLAIM_WINDOW = 60

local defaults = {
    leader = 'Dolomedes',
    puller = 'Tackleberry',
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
        and type(loaded.puller) == 'string'
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
local active_policy_name = 'settings'
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
local fastfollow_claimed = false
local zone_follow_restore_at = nil
local zone_follow_restore_remaining = 0
local last_fastfollow_claim_at = nil

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

local function is_puller()
    return same_name(local_name(), settings.puller)
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

local function valid_policy_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z0-9_-]+$') ~= nil
        and #name <= 32
end

local function configured_attacker_names(configuration)
    local names = {}
    for name, policy in pairs(configuration.attackers or {}) do
        if valid_name(name) and type(policy) == 'table' then
            names[#names + 1] = name:lower()
        end
    end
    table.sort(names)
    return names
end

local function same_attacker_roster(configuration, requested)
    local current = configured_attacker_names(configuration)
    if #current ~= #requested then return false end
    for index, name in ipairs(current) do
        if name ~= requested[index]:lower() then return false end
    end
    return true
end

local function distance_policy(name)
    local policy = attacker_settings(name) or defaults.attackers[name] or {}
    return {
        auto_distance = tonumber(policy.auto_distance) or 10,
        force_distance = tonumber(policy.force_distance) or 30,
        engage_distance = tonumber(policy.engage_distance) or 2.8,
    }
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
    if not fastfollow_claimed then
        windower.send_command('ffo stop')
        fastfollow_claimed = true
    end
    last_fastfollow_claim_at = os.clock()
    windower.ffxi.run(false)
    running = false
end

local function restore_fastfollow()
    -- The local player record can be temporarily unavailable during a zone
    -- transition. The claim flag itself proves this client was an attacker.
    if fastfollow_claimed and valid_name(settings.leader) then
        windower.send_command('ffo follow '..settings.leader)
    end
    fastfollow_claimed = false
end

local function face_target(self, target)
    if not self or not target then return end
    local dx = target.x - self.x
    local dy = target.y - self.y
    if dx * dx + dy * dy <= 0.01 then return end
    windower.ffxi.turn(-math.atan2(dy, dx))
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
    restore_fastfollow()
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
    zone_follow_restore_at = nil
    zone_follow_restore_remaining = 0
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

local function apply_runtime_policy(policy_name, leader, puller, attacker_names)
    if not valid_policy_name(policy_name) or not valid_name(leader)
        or not valid_name(puller)
    then
        chat(123, 'Rejected invalid PartyCombat policy metadata.')
        return false
    end
    local seen = {}
    local normalized = {}
    for _, name in ipairs(attacker_names or {}) do
        if not valid_name(name) then
            chat(123, 'Rejected invalid attacker name: '..tostring(name))
            return false
        end
        local key = name:lower()
        if not seen[key] then
            seen[key] = true
            normalized[#normalized + 1] = name
        end
    end
    table.sort(normalized, function(left, right)
        return left:lower() < right:lower()
    end)

    local unchanged = same_name(settings.leader, leader)
        and same_name(settings.puller, puller)
        and same_attacker_roster(settings, normalized)
    if unchanged then
        active_policy_name = policy_name
        return true
    end

    -- A role change is an authority change. Revoke the old policy before
    -- replacing it, and deliberately leave the new one inert until the
    -- configured command leader issues //pc on or //pc force.
    if armed and is_leader() then
        broadcast_authority(false)
        send_ipc('stop')
    end
    armed = false
    stop_local(nil, true)

    local attackers = {}
    for _, name in ipairs(normalized) do
        attackers[name] = distance_policy(name)
    end
    settings = {
        leader = leader,
        puller = puller,
        attackers = attackers,
    }
    active_policy_name = policy_name
    next_authority = 0
    chat(158, ('Policy %s loaded inert: leader %s, puller %s, %d attackers.')
        :format(policy_name, leader, puller, #normalized))
    return true
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
    local leader_authority = armed and is_leader()
    local puller_authority = authorized and is_puller()
    if not leader_authority and not puller_authority then return end
    local player = local_player()
    if not player or action.actor_id ~= player.id then return end

    local target = damage_target(action)
    if target then
        -- The puller may establish the next target, but cannot drag the party
        -- off a living synchronized target. The command leader can always
        -- override by dealing damage to a different enemy.
        if puller_authority and not leader_authority and active_target_id
            and active_target_id ~= target.id
        then
            local active = windower.ffxi.get_mob_by_id(active_target_id)
            if valid_enemy(active) then return end
        end
        if puller_authority and not leader_authority then
            -- Windower IPC delivery to the sending instance is not required
            -- for correctness. Claim the puller's own target locally before
            -- announcing it to the other attackers.
            accept_target(target.id, 'auto')
        end
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
        zone_follow_restore_at = nil
        zone_follow_restore_remaining = 0
        last_fastfollow_claim_at = nil
        stop_local(nil, true)
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()

    -- Battlefield exits rebuild each local client at different speeds. Retry
    -- the ownership handoff a few times so one slow client cannot miss the
    -- only FastFollow restore. A new combat target or explicit stop cancels
    -- the bounded recovery sequence.
    if zone_follow_restore_at and now >= zone_follow_restore_at then
        if not active_target_id and valid_name(settings.leader) then
            windower.send_command('ffo follow '..settings.leader)
        end
        zone_follow_restore_remaining = zone_follow_restore_remaining - 1
        if zone_follow_restore_remaining > 0 and not active_target_id then
            zone_follow_restore_at = now + POST_ZONE_FOLLOW_DELAY
        else
            zone_follow_restore_at = nil
            zone_follow_restore_remaining = 0
        end
    end

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
    face_target(self, target)

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

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = command and command:lower() or 'status'

    if command == 'status' then
        local role
        if is_leader() and is_puller() then
            role = 'leader+puller'
        elseif is_leader() then
            role = 'leader'
        elseif is_puller() and is_attacker() then
            role = 'puller+attacker'
        elseif is_puller() then
            role = 'puller'
        elseif is_attacker() then
            role = 'attacker'
        else
            role = 'observer'
        end
        local target = active_target_id
            and windower.ffxi.get_mob_by_id(active_target_id)
            or nil
        chat(207, ('Policy %s | role %s | leader %s | puller %s | armed %s | authorized %s | target %s | mode %s')
            :format(
                active_policy_name,
                role,
                settings.leader,
                settings.puller,
                armed and 'On' or 'Off',
                authorized and 'Yes' or 'No',
                target and target.name or 'none',
                tostring(active_mode or 'none')))
    elseif command == 'policy' then
        local policy_name = args[1]
        local leader = args[2]
        local puller = args[3]
        local attacker_csv = args[4]
        if not attacker_csv then
            chat(123, 'Usage: //pc policy <name> <leader> <puller> <attacker1,attacker2|->')
            return
        end
        local attacker_names = {}
        if attacker_csv ~= '-' then
            for name in attacker_csv:gmatch('[^,]+') do
                attacker_names[#attacker_names + 1] = name
            end
        end
        apply_runtime_policy(policy_name, leader, puller, attacker_names)
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
        zone_follow_restore_at = nil
        zone_follow_restore_remaining = 0
        last_fastfollow_claim_at = nil
        if not is_leader() then
            stop_local('Local attacker stopped.', true)
            return
        end
        stop_all()
    elseif command == 'help' then
        chat(207,
            'Commands: on | force | stop | status | policy <name> <leader> <puller> <attackers>. Force also arms tracking.')
    else
        chat(123, 'Unknown command. Use //pc help.')
    end
end)

windower.register_event('zone change', function()
    local now = os.clock()
    local recently_claimed = last_fastfollow_claim_at
        and now - last_fastfollow_claim_at <= RECENT_FOLLOW_CLAIM_WINDOW
    local restore_after_zone = fastfollow_claimed or recently_claimed
    if armed and is_leader() then
        broadcast_authority(false)
    end
    armed = false
    authorized = false
    stop_local(nil, true)
    if restore_after_zone then
        zone_follow_restore_remaining = POST_ZONE_FOLLOW_ATTEMPTS
        zone_follow_restore_at = now + POST_ZONE_FOLLOW_DELAY
    else
        zone_follow_restore_at = nil
        zone_follow_restore_remaining = 0
    end
end)

windower.register_event('logout', 'unload', function()
    if armed and is_leader() then
        broadcast_authority(false)
    end
    stop_running()
end)

chat(158,
    'Loaded inert. The leader or authorized puller can establish targets; use //pc on or //pc force on the leader.')
if settings_warning then
    chat(123,
        'settings.lua was unavailable during startup; using safe defaults. '
        ..settings_warning)
end
