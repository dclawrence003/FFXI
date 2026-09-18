--[[
PartyCombat

Role-scoped combat coordination for Windower multibox parties.

Independent implementation informed by the packet-level target coordination
concept in SendAllTarget by Selindrile, which thanks Arcon:
https://github.com/Selindrile/SendAllTarget
No SendAllTarget source is redistributed in this file.

Copyright (c) 2026 Don Lawrence

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
_addon.version = '0.6.19'
_addon.commands = {'partycombat', 'pcombat', 'pc'}

local packets = require('packets')
local res = require('resources')
require('strings')

local PREFIX = 'PARTYCOMBAT1'
local AUTHORITY_INTERVAL = 2
local ENGAGE_RETRY_INTERVAL = 1.5
-- Windower can expose the previous battle target briefly after an exact
-- 0x01A target-change packet is injected. Treat only that one known target as
-- stale during a short delivery window; a third target is still an immediate
-- manual override, and the grace ends as soon as the requested battle target
-- is observed.
local TARGET_TRANSITION_GRACE = 2.0
-- Exact named-recipient arena handoffs can require a disengage, packet
-- acknowledgement, and a long cross-room approach. Keep retrying only while
-- the observed battle target is the one known pre-handoff target. A third
-- target is still an immediate manual override, and acknowledgement clears
-- this allowance at once.
local DIRECTED_TARGET_TRANSITION_GRACE = 15.0
local FORCE_RETRANSMIT_DELAY = 1
local MOVEMENT_INTERVAL = 0.08
local TARGET_SYNC_INTERVAL = 1
local PRIORITY_SCAN_INTERVAL = 0.10
-- A directed split may cross this Ambuscade arena after the boss has been
-- pulled to a corner. It is still exact-ID, named-recipient, and bounded.
local DIRECTED_SPLIT_FORCE_DISTANCE = 50
local PULL_FLASH_SPELL_ID = 112
local SUPPORTED_TARGET_EXCLUSIONS = {
    elemental = true,
}

local defaults = {
    leader = 'Dolomedes',
    puller = 'Tackleberry',
    stationary = false,
    target_exclusions = {},
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
local manual_override = false
local active_engaged_seen = false
local target_transition = nil
local last_ignore_target = nil
local last_ignore_at = 0
local last_excluded_log_at = -10
local next_excluded_release = 0
local next_excluded_check = 0
local pending_force_retransmit = nil
-- Normal encounters continue to require a numeric positive HPP value.  A
-- controller may explicitly bind one party-claimed entity whose HP gauge is
-- opaque; only that exact id/index/name tuple may use the nil-HPP path.
local opaque_target = nil

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
    local name = local_name()
    if not valid_name(name) then return false end
    if is_leader() or is_puller() then return true end
    for attacker_name, policy in pairs(settings.attackers or {}) do
        if type(policy) == 'table' and valid_name(attacker_name)
            and same_name(attacker_name, name)
        then
            return true
        end
    end
    for targeter_name, enabled in pairs(settings.targeters or {}) do
        local configured = type(targeter_name) == 'number'
            and enabled or targeter_name
        if enabled and valid_name(configured) and same_name(configured, name) then
            return true
        end
    end
    return false
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

local function movement_mode_name()
    return settings.stationary and 'stationary' or 'mobile'
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

local function configured_target_exclusion_names(configuration)
    local names, seen = {}, {}
    if type(configuration.target_exclusions) ~= 'table' then return names end
    for configured_name, enabled in pairs(
        configuration.target_exclusions)
    do
        local name = type(configured_name) == 'number'
            and enabled or configured_name
        local included = type(configured_name) == 'number' or enabled
        local key = type(name) == 'string' and name:lower() or nil
        if included and key and SUPPORTED_TARGET_EXCLUSIONS[key]
            and not seen[key]
        then
            seen[key] = true
            names[#names + 1] = key
        end
    end
    table.sort(names)
    return names
end

local function same_target_exclusion_policy(configuration, requested)
    local current = configured_target_exclusion_names(configuration)
    if #current ~= #requested then return false end
    for index, name in ipairs(current) do
        if name ~= requested[index] then return false end
    end
    return true
end

local function target_exclusion_configured(name)
    if type(name) ~= 'string' then return false end
    local requested = name:lower()
    if type(settings.target_exclusions) ~= 'table' then return false end
    for configured_name, enabled in pairs(settings.target_exclusions) do
        local configured = type(configured_name) == 'number'
            and enabled or configured_name
        local included = type(configured_name) == 'number' or enabled
        if included and type(configured) == 'string'
            and configured:lower() == requested
        then
            return true
        end
    end
    return false
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

-- Profile-controlled exclusion, including forced targets and stale peer
-- messages. Match the whole word, not "Elementalist" or a character/pet/NPC
-- name. No exclusion is active unless the runtime policy requests it.
local function excluded_enemy(target)
    return target_exclusion_configured('elemental')
        and target and target.spawn_type == 16
        and type(target.name) == 'string'
        and target.name:lower():find('%f[%a]elemental%f[%A]') ~= nil
end

local function report_excluded(target)
    if os.clock() - last_excluded_log_at < 10 then return end
    last_excluded_log_at = os.clock()
    chat(123, ('Excluded elemental: %s. No party engagement.')
        :format(target.name or target.id))
end

local function party_claimed(target)
    local claim = target and tonumber(target.claim_id)
    if not claim or claim == 0 then return false end
    local current = local_player()
    if current and tonumber(current.id) == claim then return true end
    local party = type(windower.ffxi.get_party) == 'function'
        and windower.ffxi.get_party() or {}
    for key, member in pairs(party or {}) do
        if type(member) == 'table'
            and (type(key) ~= 'string' or key:match('^p[0-5]$'))
        then
            local member_id = member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)
            if member_id == claim then return true end
        end
    end
    return false
end

local function opaque_enemy(target)
    return opaque_target ~= nil
        and target ~= nil
        and tonumber(target.id) == opaque_target.id
        and tonumber(target.index) == opaque_target.index
        and target.name == opaque_target.name
        and target.hpp == nil
        and party_claimed(target)
end

local function valid_enemy(target)
    return target
        and target.spawn_type == 16
        and target.valid_target
        and (type(target.hpp) == 'number' and target.hpp > 0
            or opaque_enemy(target))
        and not excluded_enemy(target)
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
    pending_force_retransmit = nil
    opaque_target = nil
    active_target_id = nil
    shared_target_id = nil
    priority_target_id = nil
    active_mode = nil
    pursuit_limit = nil
    last_engage_at = 0
    manual_override = false
    active_engaged_seen = false
    target_transition = nil
    next_priority_scan = 0
    if revoke then
        authorized = false
    end
    if reason then
        chat(207, reason)
    end
end

-- Yield only this client's target-maintenance lane.  Keep the shared target
-- as a reference so an old swing from the former battle target cannot seize
-- control again while the operator is switching.  A later explicit target
-- transition, force command, or leader action on a different enemy resumes
-- automation normally.
local function yield_to_manual_control(reason)
    stop_running()
    pending_force_retransmit = nil
    opaque_target = nil
    active_target_id = nil
    priority_target_id = nil
    active_mode = nil
    pursuit_limit = nil
    last_engage_at = 0
    next_priority_scan = 0
    manual_override = true
    active_engaged_seen = false
    target_transition = nil
    chat(207, reason or 'Manual combat control detected; target maintenance yielded.')
end

local function inject_combat_target(target)
    local player = local_player()
    if not player or not valid_enemy(target) then return false end

    -- The selected <t> is user-owned.  Once the correct battle target is
    -- established, tabbing to an add, party member, or another object must not
    -- be overwritten merely to maintain engagement.
    if player.status == 1 then
        local battle = windower.ffxi.get_mob_by_target('bt')
        if battle and battle.id == target.id then return true end
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

local function release_excluded_local_target(immediate)
    if not runtime_policy_ready or not authorized then
        return false
    end
    local now = os.clock()
    if not immediate and now < next_excluded_check then return false end
    next_excluded_check = now + 0.1
    if not is_targeter() then return false end
    local player = local_player()
    if not player then return false end
    local stored = active_target_id and windower.ffxi.get_mob_by_id(active_target_id)
    local selected = windower.ffxi.get_mob_by_target('t')
    local battle = player.status == 1 and windower.ffxi.get_mob_by_target('bt')
    local rejected = excluded_enemy(stored) and stored
        or excluded_enemy(battle) and battle
        or excluded_enemy(selected) and selected
    if not rejected then return false end
    if now < next_excluded_release then return true end
    next_excluded_release = now + 0.5

    -- Drop an old stored elemental, but never discard a valid shared enemy
    -- merely because FFXI/EasyFarm temporarily selected an excluded one.
    if excluded_enemy(stored) then
        stop_local(nil, false)
    elseif excluded_enemy(battle) then
        stop_running()
        disengage_if_needed()
    end
    if excluded_enemy(selected) or excluded_enemy(stored) then
        local retained = active_target_id
            and windower.ffxi.get_mob_by_id(active_target_id)
        if valid_enemy(retained) then
            inject_observer_target(retained)
        elseif player.id and player.index then
            -- Select self to remove the hostile target from native job
            -- automation too. This is selection only, never movement.
            packets.inject(packets.new('incoming', 0x058, {
                ['Player'] = player.id,
                ['Target'] = player.id,
                ['Player Index'] = player.index,
            }))
        end
    end
    report_excluded(rejected)
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
    local directed_split_mode = mode == 'forcesubset'
    -- A profile may keep an attacker out of broad synchronized targeting and
    -- enroll it only for an exact named-recipient split. This is the add-tank
    -- shape: ordinary boss broadcasts cannot touch it, while forceidto can.
    if not authorized
        or not is_targeter() and not (directed_split_mode and is_attacker())
    then
        return
    end

    local target = windower.ffxi.get_mob_by_id(tonumber(id))
    if excluded_enemy(target) then
        report_excluded(target)
        release_excluded_local_target(true)
        return
    end
    if not valid_enemy(target) then return end

    local priority_mode = mode == 'priority'
    local resume_mode = mode == 'resume'
    if not priority_mode and not resume_mode and not directed_split_mode then
        shared_target_id = target.id
    end

    manual_override = false

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

    local force = mode == 'force' or mode == 'forceopaque'
        or priority_mode or resume_mode or directed_split_mode
    local configured_limit = tonumber(
        force and attacker.force_distance or attacker.auto_distance)
        or (force and 30 or 10)
    local limit = directed_split_mode
        and math.max(configured_limit, DIRECTED_SPLIT_FORCE_DISTANCE)
        or configured_limit
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
    if active_target_id ~= target.id then
        local player = local_player()
        local battle = player and player.status == 1
            and windower.ffxi.get_mob_by_target('bt') or nil
        active_engaged_seen = false
        target_transition = {
            target_id=target.id,
            from_id=battle and valid_enemy(battle) and battle.id or nil,
            until_at=os.clock() + (directed_split_mode
                and DIRECTED_TARGET_TRANSITION_GRACE
                or TARGET_TRANSITION_GRACE),
        }
        -- A different exact target edge must be deliverable immediately even
        -- when it follows the prior edge inside the ordinary retry interval.
        last_engage_at = os.clock() - ENGAGE_RETRY_INTERVAL
    end
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

local function unsigned_entity_id(value)
    if type(value) ~= 'string' or value:match('^%d+$') == nil then
        return nil
    end
    local id = tonumber(value)
    if not id or id % 1 ~= 0 or id < 1 or id > 4294967295 then
        return nil
    end
    return id
end

local function directed_attacker_names(value)
    if type(value) ~= 'string' or #value < 1 or #value > 95
        or value:sub(1, 1) == ',' or value:sub(-1) == ','
        or value:find(',,', 1, true)
        or value:match('^[A-Za-z0-9_,-]+$') == nil
    then
        return nil
    end
    local names, seen = {}, {}
    for name in value:gmatch('[^,]+') do
        local key = valid_name(name) and name:lower() or nil
        if not key or seen[key] or not attacker_settings(name) then
            return nil
        end
        seen[key] = true
        names[#names + 1] = name
        if #names > 6 then return nil end
    end
    return #names > 0 and names or nil
end

local function contains_name(names, requested)
    for _, name in ipairs(names or {}) do
        if same_name(name, requested) then return true end
    end
    return false
end

local function arm()
    if not runtime_policy_ready then
        chat(167, 'No combat roster is loaded. Load a PartyTactics profile '
            ..'or apply an explicit PartyCombat policy first.')
        return false
    end
    local was_armed = armed
    armed = true
    next_authority = 0
    -- IPC delivery back to the sending client is not guaranteed. A controller
    -- that is also an attacker must authorize itself synchronously.
    if is_targeter() and not authorized then
        authorized = true
        clear_healbot_combat_automation()
    end
    broadcast_authority(true)
    -- A repeated explicit ON remains a useful authority repair edge, but it is
    -- not another operator transition. Keep the repair broadcast and suppress
    -- duplicate chat so mirrored keys or ordered-state retries cannot flood all
    -- six clients with the same acknowledgement.
    if not was_armed then
        chat(158,
            'Armed by the configured leader/puller. Damage-target synchronization is active.')
    end
    return true
end

-- Silent, local-only convergence for a trusted orchestrator's periodic
-- state repair.  Unlike //pc on and //pc off, this never publishes authority
-- or stop IPC and never writes chat.  Repeating OFF after this client is
-- already inert is deliberately a no-op, so an operator remains free to
-- fight manually while PartyCombat is disarmed.  ON is accepted only while
-- an explicit runtime policy still names this client; otherwise convergence
-- is fail-closed and leaves the local controller off.
local function reconcile_local(value)
    value = type(value) == 'string' and value:lower() or ''
    if value ~= 'on' or not runtime_policy_ready or not is_controller() then
        local was_effective = armed or authorized or running
            or active_target_id ~= nil or shared_target_id ~= nil
            or priority_target_id ~= nil or pending_force_retransmit ~= nil
        armed = false
        authorized = false
        if was_effective then stop_local(nil, true) end
        return value == 'off'
    end

    armed = true
    next_authority = 0
    -- IPC loopback is not required: every named PartyTactics client receives
    -- and reconciles the same revision locally.
    if is_targeter() and not authorized then
        authorized = true
        clear_healbot_combat_automation()
    end
    return true
end

local function force_target(target, unavailable_message, mode, name_token)
    mode = mode or 'force'
    pending_force_retransmit = nil
    if excluded_enemy(target) then
        report_excluded(target)
        release_excluded_local_target(true)
        return false
    end
    if not valid_enemy(target) then
        chat(123, unavailable_message
            or 'Force engage requires a living enemy target.')
        return false
    end
    if not armed then
        if not arm() then return false end
    else
        broadcast_authority(true)
    end
    if is_priority_attacker() and priority_target_matches(target) then
        pending_force_retransmit = nil
        accept_target(target.id, 'priority')
        chat(158, ('Priority engagement: %s; shared target unchanged.')
            :format(target.name or target.id))
        return true
    end
    if is_targeter() then
        accept_target(target.id, mode)
    end
    send_ipc('target', target.id, mode, name_token or '-')
    -- Only the opt-in hidden-gauge route gets a bounded retransmit. Ordinary
    -- force/forceid remains edge-triggered so changing targets cannot snap the
    -- party back one second later. The Rancibus route is exact-name/id/claim
    -- bound and deliberately tolerates Confrontation entity-settle latency.
    if mode == 'forceopaque' then
        pending_force_retransmit = {
            id=target.id,
            at=os.clock() + FORCE_RETRANSMIT_DELAY,
            mode=mode,
            name_token=name_token,
        }
    end
    chat(158, ('Forced %s engagement: %s.')
        :format(movement_mode_name(),
            target.name or target.id))
    return true
end

local function force_current_target()
    local selected = windower.ffxi.get_mob_by_target('t')
    return force_target(selected,
        'Force engage requires a living enemy target.')
end

local function force_target_id(value)
    pending_force_retransmit = nil
    local id = unsigned_entity_id(value)
    if not id then
        chat(123, 'Invalid force target ID; expected an integer from 1 to 4294967295.')
        return false
    end
    return force_target(windower.ffxi.get_mob_by_id(id),
        'Force engage ID '..tostring(id)..' is not a living targetable enemy.')
end

-- Exact one-shot split for encounter runtimes. Unlike the persistent
-- priority-target feature, this addresses only the named attackers and never
-- scans or reacquires after an operator override.
local function force_target_id_to(value, recipient_csv)
    pending_force_retransmit = nil
    local id = unsigned_entity_id(value)
    local recipients = directed_attacker_names(recipient_csv)
    if not id or not recipients then
        chat(123, 'Directed force requires one uint32 target ID and 1-6 unique configured attackers.')
        return false
    end
    local target = windower.ffxi.get_mob_by_id(id)
    if excluded_enemy(target) then
        report_excluded(target)
        release_excluded_local_target(true)
        return false
    end
    if not valid_enemy(target) then
        chat(123, 'Directed force ID '..tostring(id)
            ..' is not a living targetable enemy.')
        return false
    end
    if not armed then
        if not arm() then return false end
    else
        broadcast_authority(true)
    end
    if contains_name(recipients, local_name()) and is_attacker() then
        accept_target(target.id, 'forcesubset')
    end
    for _, recipient in ipairs(recipients) do
        send_ipc('targetto', target.id, 'forcesubset', recipient)
    end
    chat(158, ('Directed one-shot engagement: %s -> %s.')
        :format(table.concat(recipients, ','), target.name or target.id))
    return true
end

-- Stop only named configured attackers without disarming the controller or
-- changing any peer lane. The next directed target edge can resume them. This
-- is intentionally one-shot so subsequent manual engagement remains manual.
local function stop_target_to(recipient_csv)
    local recipients = directed_attacker_names(recipient_csv)
    if not recipients then
        chat(123, 'Directed stop requires 1-6 unique configured attackers.')
        return false
    end
    if contains_name(recipients, local_name()) and is_attacker() then
        stop_local(nil, false)
    end
    for _, recipient in ipairs(recipients) do
        send_ipc('stopto', recipient)
    end
    chat(207, 'Directed one-shot stop: '..table.concat(recipients, ',')..'.')
    return true
end

-- Engage the local controller once without enrolling it in synchronized
-- targeting. This is the ranged-attacker path: it supplies battle status for
-- ranged weapon skills, but PartyCombat never re-faces, re-targets, moves, or
-- re-engages that character afterward.
local function engage_once_target_id(value)
    local id = unsigned_entity_id(value)
    if not id then
        chat(123, 'Invalid one-shot engage ID; expected an integer from 1 to 4294967295.')
        return false
    end
    local target = windower.ffxi.get_mob_by_id(id)
    if not valid_enemy(target) then
        chat(123, 'One-shot engage ID '..tostring(id)
            ..' is not a living targetable enemy.')
        return false
    end
    if not inject_combat_target(target) then return false end
    chat(158, 'One-shot local engagement requested for '
        ..tostring(target.name or target.id)..'; no target lock is active.')
    return true
end

local function opaque_name(value)
    if type(value) ~= 'string' or #value < 1 or #value > 64
        or value:match('^[A-Za-z0-9][A-Za-z0-9_-]*$') == nil
    then
        return nil
    end
    return value:gsub('_', ' ')
end

local function bind_opaque_target(target, expected_name)
    if not target or target.spawn_type ~= 16 or not target.valid_target
        or type(target.id) ~= 'number' or type(target.index) ~= 'number'
        or target.id < 1 or target.id > 4294967295
        or target.id ~= math.floor(target.id)
        or target.index < 0 or target.index > 65535
        or target.index ~= math.floor(target.index)
        or target.name ~= expected_name
        or type(target.hpp) == 'number' and target.hpp <= 0
        or target.hpp ~= nil and type(target.hpp) ~= 'number'
        or excluded_enemy(target) or not party_claimed(target)
    then
        return false
    end
    opaque_target = {
        id=target.id,
        index=target.index,
        name=target.name,
    }
    return true
end

local function force_opaque_target_id(value, name_token)
    pending_force_retransmit = nil
    local id = unsigned_entity_id(value)
    local expected_name = opaque_name(name_token)
    local target = id and windower.ffxi.get_mob_by_id(id) or nil
    if not id or not expected_name
        or not bind_opaque_target(target, expected_name)
    then
        opaque_target = nil
        chat(123, 'Opaque force requires one exact live party-claimed enemy '
            ..'ID and name.')
        return false
    end
    local accepted = force_target(target,
        'Opaque force target is no longer valid.', 'forceopaque', name_token)
    if not accepted then opaque_target = nil end
    return accepted
end

local function observe_target_id(value)
    local id = unsigned_entity_id(value)
    if not id then
        chat(123, 'Invalid observer target ID; expected an integer from 1 to 4294967295.')
        return false
    end
    if not runtime_policy_ready then
        chat(167, 'Observer interlock: no fresh runtime policy.')
        return false
    end
    if not is_targeter() or is_attacker() then
        chat(123, 'Observer targeting requires a configured target-only observer.')
        return false
    end

    local target = windower.ffxi.get_mob_by_id(id)
    if excluded_enemy(target) then
        report_excluded(target)
        return false
    end
    if not valid_enemy(target) then
        chat(123, 'Observer target ID '..tostring(id)
            ..' is not a living targetable enemy.')
        return false
    end

    local limit = tonumber(
        (attacker_settings(local_name()) or {}).force_distance) or 30
    local distance = distance_to(target)
    if distance > limit then
        chat(123, ('Cannot observe %s: %.1f yalms exceeds %.1f-yalm limit.')
            :format(target.name or target.id, distance, limit))
        return false
    end

    -- This authorization and selection are deliberately local. A target-only
    -- observer cannot enter accept_target's combat branch, and this command
    -- neither arms the controller nor emits authority/target IPC.
    authorized = true
    accept_target(target.id, 'observe')
    chat(158, ('Local observer target: %s.'):format(target.name or target.id))
    return true
end

local function retransmit_forced_target(now)
    local pending = pending_force_retransmit
    if not pending or now < pending.at then return end
    pending_force_retransmit = nil
    if pending.mode ~= 'forceopaque' then return end
    if not armed or not runtime_policy_ready or not is_controller() then
        return
    end
    local target = windower.ffxi.get_mob_by_id(pending.id)
    if pending.mode == 'forceopaque'
        and not bind_opaque_target(target, opaque_name(pending.name_token))
    then
        return
    end
    if not valid_enemy(target) then return end
    broadcast_authority(true)
    if is_targeter() then
        accept_target(target.id, pending.mode or 'force')
    end
    send_ipc('target', target.id, pending.mode or 'force',
        pending.name_token or '-')
end

local function stop_all()
    armed = false
    broadcast_authority(false)
    send_ipc('stop')
    stop_local(nil, true)
    chat(207, 'Disarmed and stopped all configured attackers.')
end

-- Fault containment path for a single client.  Unlike the operator-facing
-- stop command, this never changes authority on another Windower instance.
local function stop_this_client(reason)
    armed = false
    authorized = false
    stop_local(reason or 'Local PartyCombat automation stopped.', true)
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
    chat(123, ('Runtime policy cleared%s. Load a PartyTactics profile '
        ..'or apply an explicit PartyCombat policy before starting again.')
        :format(reason and (' ('..reason..')') or ''))
end

local function invalidate_local_runtime_policy(reason)
    armed = false
    authorized = false
    stop_local(nil, true)
    runtime_policy_ready = false
    active_policy_name = 'settings'
    chat(123, ('Local runtime policy cleared%s; other clients continue.')
        :format(reason and (' ('..reason..')') or ''))
end

local function apply_runtime_policy(
    policy_name, leader, puller, attacker_names, targeter_names, movement_mode,
    priority_target, priority_attacker_names, target_exclusion_names)
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
    -- Targeters are explicit. An attacker omitted here is directed-only: it
    -- ignores ordinary shared targets and can move only on forceidto edges.
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

    local exclusion_seen = {}
    local normalized_target_exclusions = {}
    for _, exclusion in ipairs(target_exclusion_names or {}) do
        local key = type(exclusion) == 'string' and exclusion:lower() or nil
        if not key or not SUPPORTED_TARGET_EXCLUSIONS[key] then
            chat(123, 'Rejected unsupported target exclusion: '
                ..tostring(exclusion))
            return false
        end
        if not exclusion_seen[key] then
            exclusion_seen[key] = true
            normalized_target_exclusions[#normalized_target_exclusions + 1]
                = key
        end
    end
    table.sort(normalized_target_exclusions)

    local unchanged = active_policy_name == policy_name
        and same_name(settings.leader, leader)
        and same_name(settings.puller, puller)
        and same_attacker_roster(settings, normalized)
        and same_targeter_roster(settings, normalized_targeters)
        and same_priority_policy(
            settings, priority_target, normalized_priority_attackers)
        and same_target_exclusion_policy(
            settings, normalized_target_exclusions)
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
    local target_exclusions = {}
    for _, exclusion in ipairs(normalized_target_exclusions) do
        target_exclusions[exclusion] = true
    end
    settings = {
        leader = leader,
        puller = puller,
        stationary = stationary,
        attackers = attackers,
        targeters = targeters,
        priority_target = priority_target,
        priority_attackers = priority_attackers,
        target_exclusions = target_exclusions,
    }
    active_policy_name = policy_name
    runtime_policy_ready = true
    next_authority = 0
    chat(158, ('Policy %s loaded inert: leader %s, puller %s, '
        ..'%d attackers, %d synchronized targeters, %s movement, priority %s/%d, exclusions %s.')
        :format(policy_name, leader, puller, #normalized,
            #normalized_targeters, stationary and 'stationary' or 'mobile',
            priority_target or 'none', #normalized_priority_attackers,
            #normalized_target_exclusions > 0
                and table.concat(normalized_target_exclusions, ',') or 'none'))
    return true
end

local function damage_target(action, allow_puller_flash)
    if not action or not action.targets then return nil end

    local physical = action.category == 1
        or action.category == 2
        or action.category == 3
    -- Flash is deliberately recognized only for the configured puller. It
    -- lets either a stationary camp or a mobile Limbus pull establish the
    -- shared target without making every enfeeble a redirect.
    local puller_flash = allow_puller_flash
        and action.category == 4
        and action.param == PULL_FLASH_SPELL_ID

    for _, target_action in ipairs(action.targets) do
        local target = target_action.id
            and windower.ffxi.get_mob_by_id(target_action.id)
            or nil
        if valid_enemy(target) then
            if physical or puller_flash then return target end

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

    local target = damage_target(action, puller_authority)
    if target then
        if pending_force_retransmit
            and pending_force_retransmit.id ~= target.id
        then
            pending_force_retransmit = nil
        end
        -- Encounter-priority attackers may split from the shared target
        -- without dragging the tank or support observers with them. In
        -- particular, Dolomedes damaging an Urchin must not broadcast that
        -- local add as Tackleberry's new Breadwinner target.
        if is_priority_attacker() and priority_target_matches(target) then
            if is_targeter() then accept_target(target.id, 'priority') end
            return
        end
        -- A directed lane is intentionally private to its named recipients.
        -- Ordinary swings on that exact assigned enemy must not fan the target
        -- back out to every targeter. A controller action on a different enemy
        -- is still a deliberate manual edge and follows normal synchronization.
        if active_mode == 'forcesubset'
            and active_target_id == target.id
        then
            return
        end
        -- Target synchronization is edge-triggered.  Ordinary rounds against
        -- the already shared enemy neither retransmit nor reacquire a target
        -- lane that the operator just released for a manual switch.
        if target.id == shared_target_id
            and (manual_override or target.id == active_target_id)
        then
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
    elseif kind == 'target' then
        local mode = fields[5]
        local atomic_force = not authorized
            and (mode == 'force' or mode == 'forceopaque')
            and runtime_policy_ready and is_targeter()
        if not authorized and not atomic_force then return end

        -- The hidden-gauge exception must be proven before it can authorize a
        -- follower or clear that client's HealBot combat settings. A malformed,
        -- stale, missing, unclaimed, or foreign-claimed exact target therefore
        -- leaves an inert receiver inert.
        if mode == 'forceopaque' then
            local id = unsigned_entity_id(fields[4])
            local expected_name = opaque_name(fields[6])
            local target = id and windower.ffxi.get_mob_by_id(id) or nil
            if expected_name == nil
                or not bind_opaque_target(target, expected_name)
            then
                opaque_target = nil
                return
            end
        end
        -- An explicit force is itself controller authorization for a client
        -- that already holds the matching validated runtime policy. This makes
        -- the first forced target atomic instead of depending on a preceding
        -- authority IPC message being observed first.
        if atomic_force then
            authorized = true
            clear_healbot_combat_automation()
        end
        if authorized then
            accept_target(fields[4], mode)
        end
    elseif kind == 'targetto' then
        local id = unsigned_entity_id(fields[4])
        local mode = fields[5]
        local recipient = fields[6]
        if mode ~= 'forcesubset' or not same_name(local_name(), recipient)
            or not is_attacker()
        then
            return
        end
        local target = id and windower.ffxi.get_mob_by_id(id) or nil
        if not valid_enemy(target) then return end
        local atomic_force = not authorized
            and runtime_policy_ready and is_attacker()
        if not authorized and not atomic_force then return end
        if atomic_force then
            authorized = true
            clear_healbot_combat_automation()
        end
        accept_target(id, mode)
    elseif kind == 'stopto' then
        local recipient = fields[4]
        if runtime_policy_ready and same_name(local_name(), recipient)
            and is_attacker()
        then
            stop_local(nil, false)
        end
    elseif kind == 'stop' then
        armed = false
        if is_targeter() or is_attacker() then
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

    retransmit_forced_target(now)

    update_priority_target(now)

    -- Run even without a stored target: game auto-targeting or EasyFarm can
    -- select an elemental between pulls. It must not restart a lock-on loop.
    if release_excluded_local_target() then return end

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
            if local_target and local_target.id ~= target.id then
                yield_to_manual_control(
                    'Manual target selected; observer synchronization yielded.')
            elseif not local_target then
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

    local player = local_player()
    local battle = player and player.status == 1
        and windower.ffxi.get_mob_by_target('bt') or nil
    if battle and battle.id == target.id then
        active_engaged_seen = true
        target_transition = nil
    elseif battle and valid_enemy(battle) then
        local stale_transition = target_transition
            and target_transition.target_id == target.id
            and target_transition.from_id == battle.id
            and now <= target_transition.until_at
        if not stale_transition then
            yield_to_manual_control(
                'Manual battle-target change detected; target maintenance yielded.')
            return
        end
    end
    if player and player.status ~= 1 and active_engaged_seen then
        yield_to_manual_control(
            'Manual disengage detected; target maintenance yielded.')
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

    -- Ordinary stationary policies hold their camp, but an explicit directed
    -- engagement means approach and engage.  This keeps `force` atomic and
    -- prevents a remote attacker from drawing weapons out of melee range.
    local directed = active_mode == 'force' or active_mode == 'forceopaque'
        or active_mode == 'forcesubset' or active_mode == 'priority'
    if settings.stationary and not directed then
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
        elseif is_attacker() and not is_targeter() then
            role = 'directed-only attacker'
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
        chat(207, ('v%s | Policy %s | support-ready %s | role %s | leader %s | puller %s | movement %s | armed %s | authorized %s | target %s | mode %s | priority %s')
            :format(
                _addon.version,
                active_policy_name,
                runtime_policy_ready and 'Yes' or 'No',
                role,
                settings.leader,
                settings.puller,
                movement_mode_name(),
                armed and 'On' or 'Off',
                authorized and 'Yes' or 'No',
                target and target.name or 'none',
                tostring(active_mode or 'none'),
                type(settings.priority_target) == 'string'
                    and (settings.priority_target..'/'
                        ..tostring(#configured_priority_attacker_names(settings)))
                    or 'none'))
        local exclusions = configured_target_exclusion_names(settings)
        chat(207, 'Target exclusions: '
            ..(#exclusions > 0 and table.concat(exclusions, ',') or 'none')
            ..'.')
    elseif command == 'policy' then
        local policy_name = args[1]
        local leader = args[2]
        local puller = args[3]
        local attacker_csv = args[4]
        local targeter_csv = args[5]
        local movement_mode = args[6] or 'mobile'
        local priority_target_token = args[7]
        local priority_attacker_csv = args[8]
        local target_exclusion_csv = args[9]
        if not attacker_csv then
            chat(123, 'Usage: //pc policy <name> <leader> <puller> '
                ..'<attackers|-> [targeters|->] [mobile|stationary] '
                ..'[priority_target|->] [priority_attackers|->] '
                ..'[target_exclusions|-]')
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
        local target_exclusion_names = {}
        if target_exclusion_csv and target_exclusion_csv ~= '-' then
            for exclusion in target_exclusion_csv:gmatch('[^,]+') do
                target_exclusion_names[#target_exclusion_names + 1]
                    = exclusion
            end
        end
        apply_runtime_policy(
            policy_name, leader, puller, attacker_names, targeter_names,
            movement_mode, priority_target, priority_attacker_names,
            target_exclusion_names)
    elseif command == 'invalidate' then
        local source = type(args[1]) == 'string' and args[1]:lower() or ''
        if source ~= 'partystart' and source ~= 'partytactics' then
            chat(123, 'Runtime invalidation requires a trusted support orchestrator.')
            return
        end
        invalidate_runtime_policy((source == 'partytactics'
            and 'PartyTactics' or 'PartyStart')..' stopped or reloaded')
    elseif command == 'localinvalidate' then
        local source = type(args[1]) == 'string' and args[1]:lower() or ''
        if source ~= 'partystart' and source ~= 'partytactics' then
            chat(123, 'Local runtime invalidation requires a trusted support orchestrator.')
            return
        end
        invalidate_local_runtime_policy((source == 'partytactics'
            and 'PartyTactics' or 'PartyStart')..' stopped locally')
    elseif command == 'on' or command == 'arm' or command == 'auto' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can arm PartyCombat.')
            return
        end
        arm()
    elseif command == 'force' or command == 'engage'
        or command == 'attack'
    then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can force engagement.')
            return
        end
        force_current_target()
    elseif command == 'forceid' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can force engagement.')
            return
        end
        force_target_id(#args == 1 and args[1] or nil)
    elseif command == 'forceidto' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can direct engagement.')
            return
        end
        force_target_id_to(
            #args == 2 and args[1] or nil,
            #args == 2 and args[2] or nil)
    elseif command == 'stopto' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can direct a stop.')
            return
        end
        stop_target_to(#args == 1 and args[1] or nil)
    elseif command == 'engageonceid' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can request a one-shot engagement.')
            return
        end
        engage_once_target_id(#args == 1 and args[1] or nil)
    elseif command == 'forceopaqueid' then
        if not is_controller() then
            chat(123, 'Only a configured profile participant can force engagement.')
            return
        end
        force_opaque_target_id(
            #args == 2 and args[1] or nil,
            #args == 2 and args[2] or nil)
    elseif command == 'observeid' then
        observe_target_id(#args == 1 and args[1] or nil)
    elseif command == 'off' or command == 'stop' then
        if not is_controller() then
            stop_local('Local attacker stopped.', true)
            return
        end
        stop_all()
    elseif command == 'reconcile' then
        reconcile_local(#args == 1 and args[1] or nil)
    elseif command == 'localstop' then
        stop_this_client()
    elseif command == 'help' then
        chat(207,
            'Commands: on | force | forceid <uint32> | forceidto <uint32> <attackers_csv> | stopto <attackers_csv> | engageonceid <uint32> | forceopaqueid <uint32> <exact_name> | observeid <uint32> | stop | localstop | status | policy <name> <leader> '
            ..'<puller> <attackers> [targeters] [mobile|stationary] '
            ..'[priority_target] [priority_attackers] [target_exclusions]. '
            ..'Any configured profile participant may arm/force.')
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
    armed = false
    authorized = false
    runtime_policy_ready = false
    stop_local(nil, true)
end)

chat(158,
    ('Loaded v%s inert; FastFollow is untouched. Apply PartyTactics '
        ..'(or an explicit runtime policy), then use //pc on or //pc force.')
        :format(_addon.version))
if settings_warning then
    chat(123,
        'settings.lua was unavailable during startup; using safe defaults. '
        ..settings_warning)
end
