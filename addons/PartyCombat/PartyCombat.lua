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
_addon.version = '0.6.1'
_addon.commands = {'partycombat', 'pcombat', 'pc'}

local packets = require('packets')
local res = require('resources')
require('strings')

local PREFIX = 'PARTYCOMBAT1'
local AUTHORITY_INTERVAL = 2
local ENGAGE_RETRY_INTERVAL = 1.5
local MOVEMENT_INTERVAL = 0.08
local TARGET_SYNC_INTERVAL = 1
local PRIORITY_SCAN_INTERVAL = 0.10
local PULL_FLASH_SPELL_ID = 112

local defaults = {
    leader = 'Dolomedes',
    puller = 'Tackleberry',
    stationary = false,
    attackers = {
        Dolomedes = {
            auto_distance = 10,
            force_distance = 30,
            engage_distance = 2.8,
        },
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
-- Static settings are a safe fallback for policy construction, but they do
-- not prove that PartyStart's healing/buff controllers are active in this
-- client session.  Only a validated runtime policy may unlock combat.
local runtime_policy_ready = false
local armed = false
local authorized = false
local active_target_id = nil
local shared_target_id = nil
local priority_target_id = nil
local active_mode = nil
local pursuit_limit = nil
local next_authority = 0
local next_movement = 0
local next_target_sync = 0
local next_priority_scan = 0
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

local function is_puller()
    return same_name(local_name(), settings.puller)
end

local function is_controller()
    return is_leader() or is_puller()
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

local function targeter_configured(name)
    if not valid_name(name) then return false end
    -- Older settings files predate observer targeting. Preserve their exact
    -- behavior by treating the attacker roster as the targeter roster.
    if type(settings.targeters) ~= 'table' then
        return attacker_settings(name) ~= nil
    end
    for targeter_name, enabled in pairs(settings.targeters) do
        if type(targeter_name) == 'number' then
            if valid_name(enabled) and same_name(enabled, name) then
                return true
            end
        elseif enabled and valid_name(targeter_name)
            and same_name(targeter_name, name)
        then
            return true
        end
    end
    return false
end

local function is_targeter()
    return targeter_configured(local_name())
end

local function is_priority_attacker()
    local name = local_name()
    if not valid_name(name)
        or type(settings.priority_attackers) ~= 'table'
    then
        return false
    end
    for configured_name, enabled in pairs(settings.priority_attackers) do
        local candidate = type(configured_name) == 'number'
            and enabled or configured_name
        local included = type(configured_name) == 'number' or enabled
        if included and valid_name(candidate) and same_name(candidate, name) then
            return true
        end
    end
    return false
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

local function configured_targeter_names(configuration)
    if type(configuration.targeters) ~= 'table' then
        return configured_attacker_names(configuration)
    end
    local names, seen = {}, {}
    for targeter_name, enabled in pairs(configuration.targeters) do
        local name = type(targeter_name) == 'number' and enabled or targeter_name
        local included = type(targeter_name) == 'number' or enabled
        if included and valid_name(name) and not seen[name:lower()] then
            seen[name:lower()] = true
            names[#names + 1] = name:lower()
        end
    end
    table.sort(names)
    return names
end

local function same_targeter_roster(configuration, requested)
    local current = configured_targeter_names(configuration)
    if #current ~= #requested then return false end
    for index, name in ipairs(current) do
        if name ~= requested[index]:lower() then return false end
    end
    return true
end

local function configured_priority_attacker_names(configuration)
    local names, seen = {}, {}
    for configured_name, enabled in pairs(
        configuration.priority_attackers or {})
    do
        local name = type(configured_name) == 'number'
            and enabled or configured_name
        local included = type(configured_name) == 'number' or enabled
        if included and valid_name(name) and not seen[name:lower()] then
            seen[name:lower()] = true
            names[#names + 1] = name:lower()
        end
    end
    table.sort(names)
    return names
end

local function same_priority_policy(configuration, target_name, requested)
    local configured_target = configuration.priority_target
    if configured_target ~= target_name
        and (type(configured_target) ~= 'string'
            or type(target_name) ~= 'string'
            or configured_target:lower() ~= target_name:lower())
    then
        return false
    end
    local current = configured_priority_attacker_names(configuration)
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
    for _, targeter_name in ipairs(configured_targeter_names(settings)) do
        send_ipc('authority', targeter_name, enabled and '1' or '0')
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

local function priority_target_matches(target)
    return valid_enemy(target)
        and type(settings.priority_target) == 'string'
        and type(target.name) == 'string'
        and target.name:lower() == settings.priority_target:lower()
end

local function priority_distance_limit()
    local policy = attacker_settings(local_name()) or {}
    return tonumber(policy.force_distance) or 30
end

local function find_priority_target()
    if not authorized or not is_priority_attacker()
        or type(settings.priority_target) ~= 'string'
    then
        return nil
    end

    local limit = priority_distance_limit()
    local current = priority_target_id
        and windower.ffxi.get_mob_by_id(priority_target_id)
        or nil
    if priority_target_matches(current) and distance_to(current) <= limit then
        return current
    end

    local selected = nil
    for _, target in pairs(windower.ffxi.get_mob_array() or {}) do
        local target_id = tonumber(target and target.id)
        if target_id and priority_target_matches(target)
            and distance_to(target) <= limit
            and (not selected or target_id < tonumber(selected.id))
        then
            selected = target
        end
    end
    return selected
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
    -- Stop only movement this addon previously started. FastFollow is a
    -- separate user-owned controller and is never toggled or redirected.
    stop_running()
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
    shared_target_id = nil
    priority_target_id = nil
    active_mode = nil
    pursuit_limit = nil
    last_engage_at = 0
    next_priority_scan = 0
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

local function inject_observer_target(target)
    local player = local_player()
    if not player or not valid_enemy(target) then return false end
    packets.inject(packets.new('incoming', 0x058, {
        ['Player'] = player.id,
        ['Target'] = target.id,
        ['Player Index'] = player.index,
    }))
    next_target_sync = os.clock() + TARGET_SYNC_INTERVAL
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
    if not authorized or not is_targeter() then return end

    local target = windower.ffxi.get_mob_by_id(tonumber(id))
    if not valid_enemy(target) then return end

    local priority_mode = mode == 'priority'
    local resume_mode = mode == 'resume'
    if not priority_mode and not resume_mode then
        shared_target_id = target.id
    end

    -- A normal synchronization update may refresh the encounter's shared
    -- target while this attacker is killing an encounter-priority add. Keep
    -- the local add target and use the refreshed ID only for the later return.
    local active_priority = priority_target_id
        and windower.ffxi.get_mob_by_id(priority_target_id)
        or nil
    if not priority_mode and not resume_mode
        and is_priority_attacker()
        and priority_target_matches(active_priority)
    then
        return
    end

    -- Target-only observers need the same local <t> as the damage group so
    -- their GearSwap controllers can Silence, Elegy, or otherwise debuff.
    -- They never run, face, engage, or approach.
    if not is_attacker() then
        active_target_id = target.id
        active_mode = 'observe'
        pursuit_limit = nil
        last_ignore_target = nil
        inject_observer_target(target)
        return
    end

    local attacker = attacker_settings(local_name())
    if not attacker then return end

    local force = mode == 'force' or priority_mode or resume_mode
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

    -- FastFollow is an entirely independent user-owned controller. Do not
    -- start, stop, redirect, or restore it when combat movement begins.
    if priority_mode then priority_target_id = target.id end
    active_target_id = target.id
    active_mode = mode or (force and 'force' or 'auto')
    pursuit_limit = limit
    last_ignore_target = nil
    inject_combat_target(target)
end

local function update_priority_target(now)
    if not authorized or not is_priority_attacker()
        or type(settings.priority_target) ~= 'string'
        or now < next_priority_scan
    then
        return
    end
    next_priority_scan = now + PRIORITY_SCAN_INTERVAL

    local target = find_priority_target()
    if target then
        if priority_target_id ~= target.id
            or active_target_id ~= target.id
        then
            priority_target_id = target.id
            accept_target(target.id, 'priority')
            chat(158, ('Priority target acquired: %s. Shared target remains %s.')
                :format(target.name,
                    shared_target_id
                        and (windower.ffxi.get_mob_by_id(shared_target_id) or {}).name
                        or 'none'))
        end
        return
    end

    if not priority_target_id then return end
    local finished = settings.priority_target
    priority_target_id = nil
    local shared = shared_target_id
        and windower.ffxi.get_mob_by_id(shared_target_id)
        or nil
    if valid_enemy(shared) then
        accept_target(shared.id, 'resume')
        chat(158, ('Priority target ended; resumed %s.'):format(shared.name))
    else
        stop_local(
            ('Priority target %s ended; no living shared target remains.')
                :format(finished), false)
    end
end

local function current_leader_target()
    local target = windower.ffxi.get_mob_by_target('t')
    if valid_enemy(target) then return target end
    return nil
end

local function arm()
    if not runtime_policy_ready then
        chat(167, 'Combat interlock: no fresh runtime policy. Run the desired '
            ..'PartyStart profile and wait for its ready message before //pc on.')
        return false
    end
    armed = true
    next_authority = 0
    -- IPC delivery back to the sending client is not guaranteed. A controller
    -- that is also an attacker must authorize itself synchronously.
    if is_targeter() and not authorized then
        authorized = true
        clear_healbot_combat_automation()
    end
    broadcast_authority(true)
    chat(158,
        'Armed by the configured leader/puller. Damage-target synchronization is active.')
    return true
end

local function force_current_target()
    local target = current_leader_target()
    if not target then
        chat(123, 'Force engage requires a living enemy target.')
        return
    end
    if not armed then
        if not arm() then return end
    else
        broadcast_authority(true)
    end
    if is_priority_attacker() and priority_target_matches(target) then
        accept_target(target.id, 'priority')
        chat(158, ('Priority engagement: %s; shared target unchanged.')
            :format(target.name or target.id))
        return
    end
    if is_targeter() then
        accept_target(target.id, 'force')
    end
    send_ipc('target', target.id, 'force')
    chat(158, ('Forced %s engagement: %s.')
        :format(settings.stationary and 'stationary' or 'approach',
            target.name or target.id))
end

local function stop_all()
    armed = false
    broadcast_authority(false)
    send_ipc('stop')
    stop_local(nil, true)
    chat(207, 'Disarmed and stopped all configured attackers.')
end

local function invalidate_runtime_policy(reason)
    if armed and is_controller() then
        broadcast_authority(false)
    end
    armed = false
    authorized = false
    stop_local(nil, true)
    runtime_policy_ready = false
    active_policy_name = 'settings'
    chat(123, ('Runtime policy invalidated%s; combat is locked until '
        ..'PartyStart supplies a fresh policy.')
        :format(reason and (' ('..reason..')') or ''))
end

local function apply_runtime_policy(
    policy_name, leader, puller, attacker_names, targeter_names, movement_mode,
    priority_target, priority_attacker_names)
    movement_mode = type(movement_mode) == 'string'
        and movement_mode:lower()
        or 'mobile'
    if not valid_policy_name(policy_name) or not valid_name(leader)
        or not valid_name(puller)
    then
        chat(123, 'Rejected invalid PartyCombat policy metadata.')
        return false
    end
    if movement_mode ~= 'mobile' and movement_mode ~= 'stationary' then
        chat(123, 'Rejected invalid movement mode: '..tostring(movement_mode))
        return false
    end
    if priority_target ~= nil
        and (type(priority_target) ~= 'string'
            or #priority_target > 64
            or priority_target:match('^[A-Za-z0-9][A-Za-z0-9 _-]*$') == nil)
    then
        chat(123, 'Rejected invalid priority target: '
            ..tostring(priority_target))
        return false
    end
    local stationary = movement_mode == 'stationary'
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

    local target_seen = {}
    local normalized_targeters = {}
    for _, name in ipairs(targeter_names or attacker_names or {}) do
        if not valid_name(name) then
            chat(123, 'Rejected invalid targeter name: '..tostring(name))
            return false
        end
        local key = name:lower()
        if not target_seen[key] then
            target_seen[key] = true
            normalized_targeters[#normalized_targeters + 1] = name
        end
    end
    -- Every attacker necessarily consumes target authority too. Repair an
    -- incomplete caller list instead of producing an armed-but-inert attacker.
    for _, name in ipairs(normalized) do
        local key = name:lower()
        if not target_seen[key] then
            target_seen[key] = true
            normalized_targeters[#normalized_targeters + 1] = name
        end
    end
    table.sort(normalized_targeters, function(left, right)
        return left:lower() < right:lower()
    end)

    local priority_seen = {}
    local normalized_priority_attackers = {}
    for _, name in ipairs(priority_attacker_names or {}) do
        if not valid_name(name) then
            chat(123, 'Rejected invalid priority attacker: '..tostring(name))
            return false
        end
        local key = name:lower()
        if not seen[key] then
            chat(123, 'Rejected priority attacker outside attacker roster: '
                ..name)
            return false
        end
        if not priority_seen[key] then
            priority_seen[key] = true
            normalized_priority_attackers[#normalized_priority_attackers + 1]
                = name
        end
    end
    table.sort(normalized_priority_attackers, function(left, right)
        return left:lower() < right:lower()
    end)
    if (priority_target == nil)
        ~= (#normalized_priority_attackers == 0)
    then
        chat(123, 'A priority target and at least one priority attacker '
            ..'must be configured together.')
        return false
    end

    local unchanged = active_policy_name == policy_name
        and same_name(settings.leader, leader)
        and same_name(settings.puller, puller)
        and same_attacker_roster(settings, normalized)
        and same_targeter_roster(settings, normalized_targeters)
        and same_priority_policy(
            settings, priority_target, normalized_priority_attackers)
        and (settings.stationary == true) == stationary
    if unchanged then
        active_policy_name = policy_name
        runtime_policy_ready = true
        return true
    end

    -- A role change is an authority change. Revoke the old policy before
    -- replacing it, and deliberately leave the new one inert until the
    -- configured command leader or puller issues //pc on or //pc force.
    if armed and is_controller() then
        broadcast_authority(false)
        send_ipc('stop')
    end
    armed = false
    stop_local(nil, true)

    local attackers = {}
    for _, name in ipairs(normalized) do
        attackers[name] = distance_policy(name)
    end
    local targeters = {}
    for _, name in ipairs(normalized_targeters) do
        targeters[name] = true
    end
    local priority_attackers = {}
    for _, name in ipairs(normalized_priority_attackers) do
        priority_attackers[name] = true
    end
    settings = {
        leader = leader,
        puller = puller,
        stationary = stationary,
        attackers = attackers,
        targeters = targeters,
        priority_target = priority_target,
        priority_attackers = priority_attackers,
    }
    active_policy_name = policy_name
    runtime_policy_ready = true
    next_authority = 0
    chat(158, ('Policy %s loaded inert: leader %s, puller %s, '
        ..'%d attackers, %d synchronized targeters, %s movement, priority %s/%d.')
        :format(policy_name, leader, puller, #normalized,
            #normalized_targeters, stationary and 'stationary' or 'mobile',
            priority_target or 'none', #normalized_priority_attackers))
    return true
end

local function damage_target(action, allow_stationary_pull)
    if not action or not action.targets then return nil end

    local physical = action.category == 1
        or action.category == 2
        or action.category == 3
    -- Flash is deliberately recognized only for the configured puller while
    -- a stationary policy is active. It lets a non-damaging ranged pull
    -- establish the shared target without making every enfeeble a redirect.
    local stationary_pull = allow_stationary_pull
        and action.category == 4
        and action.param == PULL_FLASH_SPELL_ID

    for _, target_action in ipairs(action.targets) do
        local target = target_action.id
            and windower.ffxi.get_mob_by_id(target_action.id)
            or nil
        if valid_enemy(target) then
            if physical or stationary_pull then return target end

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
    local puller_authority = (authorized or armed) and is_puller()
    if not leader_authority and not puller_authority then return end
    local player = local_player()
    if not player or action.actor_id ~= player.id then return end

    local target = damage_target(
        action, settings.stationary == true and puller_authority)
    if target then
        -- Encounter-priority attackers may split from the shared target
        -- without dragging the tank or support observers with them. In
        -- particular, Dolomedes damaging an Urchin must not broadcast that
        -- local add as Tackleberry's new Breadwinner target.
        if is_priority_attacker() and priority_target_matches(target) then
            if is_targeter() then accept_target(target.id, 'priority') end
            return
        end
        -- The puller may establish the next target, but cannot drag the party
        -- off a living synchronized target. The command leader can always
        -- override by dealing damage to a different enemy.
        if puller_authority and not leader_authority and active_target_id
            and active_target_id ~= target.id
        then
            local active = windower.ffxi.get_mob_by_id(active_target_id)
            if valid_enemy(active) then return end
        end
        if is_targeter() then
            -- Windower IPC delivery to the sending instance is not required
            -- for correctness. Claim the controller's own target locally
            -- before announcing it to the other attackers.
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
        -- A healthy controller continues broadcasting authority every two
        -- seconds. Never let that heartbeat reauthorize a client whose local
        -- PartyStart instance has since stopped or reloaded.
        local enabled = fields[5] == '1' and runtime_policy_ready
        if same_name(local_name(), attacker_name) and is_targeter() then
            local was_authorized = authorized
            authorized = enabled
            if enabled and not was_authorized then
                clear_healbot_combat_automation()
            elseif not enabled then
                if is_controller() then armed = false end
                stop_local(nil, true)
            end
        end
    elseif kind == 'target' and authorized then
        accept_target(fields[4], fields[5])
    elseif kind == 'stop' then
        armed = false
        if is_targeter() then
            stop_local(nil, true)
        end
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()

    if armed and is_controller() and now >= next_authority then
        next_authority = now + AUTHORITY_INTERVAL
        broadcast_authority(true)
    end

    update_priority_target(now)

    if not authorized or not active_target_id then
        return
    end

    local target = windower.ffxi.get_mob_by_id(active_target_id)
    if not valid_enemy(target) and priority_target_id then
        -- A priority target can die between the throttled 0.10-second scans.
        -- Resolve the next add or shared-target return before the ordinary
        -- invalid-target path clears the saved Breadwinner ID.
        next_priority_scan = 0
        update_priority_target(now)
        if not active_target_id then return end
        target = windower.ffxi.get_mob_by_id(active_target_id)
    end
    if not valid_enemy(target) then
        stop_local(is_attacker()
            and 'Target ended; attacker stopped.'
            or 'Target ended; observer target cleared.', false)
        return
    end

    if not is_attacker() then
        if now >= next_target_sync then
            local local_target = windower.ffxi.get_mob_by_target('t')
            if not local_target or local_target.id ~= target.id then
                inject_observer_target(target)
            else
                next_target_sync = now + TARGET_SYNC_INTERVAL
            end
        end
        return
    end

    if now < next_movement then return end
    next_movement = now + MOVEMENT_INTERVAL

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

    -- A stationary camp still synchronizes, faces, and engages every attacker,
    -- but it never asks Windower to translate the character toward the mob.
    -- Flash (or existing aggro) must bring the enemy into melee range instead.
    if settings.stationary then
        stop_running()
        return
    end

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
        elseif is_targeter() then
            role = 'target-only observer'
        else
            role = 'observer'
        end
        local target = active_target_id
            and windower.ffxi.get_mob_by_id(active_target_id)
            or nil
        chat(207, ('Policy %s | support-ready %s | role %s | leader %s | puller %s | movement %s | armed %s | authorized %s | target %s | mode %s | priority %s')
            :format(
                active_policy_name,
                runtime_policy_ready and 'Yes' or 'No',
                role,
                settings.leader,
                settings.puller,
                settings.stationary and 'stationary' or 'mobile',
                armed and 'On' or 'Off',
                authorized and 'Yes' or 'No',
                target and target.name or 'none',
                tostring(active_mode or 'none'),
                type(settings.priority_target) == 'string'
                    and (settings.priority_target..'/'
                        ..tostring(#configured_priority_attacker_names(settings)))
                    or 'none'))
    elseif command == 'policy' then
        local policy_name = args[1]
        local leader = args[2]
        local puller = args[3]
        local attacker_csv = args[4]
        local targeter_csv = args[5]
        local movement_mode = args[6] or 'mobile'
        local priority_target_token = args[7]
        local priority_attacker_csv = args[8]
        if not attacker_csv then
            chat(123, 'Usage: //pc policy <name> <leader> <puller> '
                ..'<attackers|-> [targeters|->] [mobile|stationary] '
                ..'[priority_target|->] [priority_attackers|->]')
            return
        end
        local attacker_names = {}
        if attacker_csv ~= '-' then
            for name in attacker_csv:gmatch('[^,]+') do
                attacker_names[#attacker_names + 1] = name
            end
        end
        local targeter_names = {}
        if targeter_csv == nil then
            for _, name in ipairs(attacker_names) do
                targeter_names[#targeter_names + 1] = name
            end
        elseif targeter_csv ~= '-' then
            for name in targeter_csv:gmatch('[^,]+') do
                targeter_names[#targeter_names + 1] = name
            end
        end
        local priority_target = nil
        if priority_target_token and priority_target_token ~= '-' then
            priority_target = priority_target_token:gsub('_', ' ')
        end
        local priority_attacker_names = {}
        if priority_target then
            if priority_attacker_csv == nil then
                for _, name in ipairs(attacker_names) do
                    priority_attacker_names[#priority_attacker_names + 1] = name
                end
            elseif priority_attacker_csv ~= '-' then
                for name in priority_attacker_csv:gmatch('[^,]+') do
                    priority_attacker_names[#priority_attacker_names + 1] = name
                end
            end
        elseif priority_attacker_csv and priority_attacker_csv ~= '-' then
            for name in priority_attacker_csv:gmatch('[^,]+') do
                priority_attacker_names[#priority_attacker_names + 1] = name
            end
        end
        apply_runtime_policy(
            policy_name, leader, puller, attacker_names, targeter_names,
            movement_mode, priority_target, priority_attacker_names)
    elseif command == 'invalidate' then
        if args[1] ~= 'partystart' then
            chat(123, 'Runtime invalidation is reserved for PartyStart.')
            return
        end
        invalidate_runtime_policy('PartyStart stopped or reloaded')
    elseif command == 'on' or command == 'arm' or command == 'auto' then
        if not is_controller() then
            chat(123, 'Only the configured leader or puller can arm PartyCombat.')
            return
        end
        arm()
    elseif command == 'force' or command == 'engage'
        or command == 'attack'
    then
        if not is_controller() then
            chat(123, 'Only the configured leader or puller can force engagement.')
            return
        end
        force_current_target()
    elseif command == 'off' or command == 'stop' then
        if not is_controller() then
            stop_local('Local attacker stopped.', true)
            return
        end
        stop_all()
    elseif command == 'help' then
        chat(207,
            'Commands: on | force | stop | status | policy <name> <leader> '
            ..'<puller> <attackers> [targeters] [mobile|stationary] '
            ..'[priority_target] [priority_attackers]. '
            ..'Leader or puller may arm/force.')
    else
        chat(123, 'Unknown command. Use //pc help.')
    end
end)

windower.register_event('zone change', function()
    if armed and is_controller() then
        broadcast_authority(false)
    end
    armed = false
    authorized = false
    stop_local(nil, true)
end)

windower.register_event('logout', 'unload', function()
    if armed and is_controller() then
        broadcast_authority(false)
    end
    stop_running()
end)

chat(158,
    'Loaded inert; FastFollow is untouched. Apply PartyStart (or an explicit runtime policy), then use //pc on or //pc force.')
if settings_warning then
    chat(123,
        'settings.lua was unavailable during startup; using safe defaults. '
        ..settings_warning)
end
