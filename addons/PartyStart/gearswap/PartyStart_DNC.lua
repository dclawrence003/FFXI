-- PartyStart DNC controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
--
-- It replaces the stock No Foot Rise-dependent loop in PartyStart profiles,
-- verifies every learned ability directly, and keeps Saber Dance disabled so
-- TP-funded emergency Waltzes remain available.
-- Load at the end of a participating character's DNC gear file:
--     include('Common/PartyStart_DNC.lua')

local pstart_dnc = {
    active = false,
    profile = nil,
    leader = nil,
    pending = nil,
    retry_at = 0,
    stepped_targets = {},
    last_action = 'none',
    autows_paused = false,
}

local PSTART_DNC_ACTIONS = {
    haste_samba = 189,
    curing_waltz_iii = 192,
    curing_waltz_iv = 193,
    box_step = 202,
    reverse_flourish = 206,
    no_foot_rise = 239,
    presto = 261,
    curing_waltz_v = 311,
}

local PSTART_DNC_EMERGENCY_HPP = 42
local PSTART_DNC_CRITICAL_HPP = 25
local PSTART_DNC_STEP_RETRY = 45
local PSTART_DNC_NO_FOOT_RISE_HEALTHY_HPP = 70
local PSTART_DNC_NO_FOOT_RISE_TP_CEILING = 900

local function pstart_dnc_valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function pstart_dnc_known(action_id)
    local abilities = windower.ffxi.get_abilities() or {}
    for _, learned_id in ipairs(abilities.job_abilities or {}) do
        if learned_id == action_id then return true end
    end
    return false
end

local function pstart_dnc_ready(action_id)
    local ability = res.job_abilities[action_id]
    local recasts = windower.ffxi.get_ability_recasts() or {}
    return ability
        and pstart_dnc_known(action_id)
        and not midaction()
        and not moving
        and not silent_check_disable()
        and not silent_check_amnesia()
        and (not tickdelay or os.clock() >= tickdelay)
        and os.clock() >= (pstart_dnc.retry_at or 0)
        and (recasts[ability.recast_id] or 999) < latency
        and player.tp >= (ability.tp_cost or 0)
end

local function pstart_dnc_member_in_range(member)
    if not member or not member.name then return false end
    if member.name:lower() == player.name:lower() then return true end
    local mob = windower.ffxi.get_mob_by_name(member.name)
    return mob and mob.distance and mob.distance:sqrt() <= 20.5
end

local function pstart_dnc_lowest_party_member()
    local lowest = nil
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table'
            and type(member.hpp) == 'number'
            and member.hpp > 0
            and pstart_dnc_member_in_range(member)
            and (not lowest or member.hpp < lowest.hpp)
        then
            lowest = {
                name = member.name,
                token = member.name:lower() == player.name:lower()
                    and '<me>' or '<'..key..'>',
                hpp = member.hpp,
            }
        end
    end
    return lowest
end

local function pstart_dnc_leader_target()
    local leader = pstart_dnc.leader
        and windower.ffxi.get_mob_by_name(pstart_dnc.leader)
        or nil
    if not leader or not leader.target_index or leader.target_index == 0 then
        return nil
    end
    local target = windower.ffxi.get_mob_by_index(leader.target_index)
    if not target or target.spawn_type ~= 16 or not target.valid_target
        or not target.hpp or target.hpp <= 0
    then
        return nil
    end
    return target
end

local function pstart_dnc_use(action_id, target, detail)
    local ability = res.job_abilities[action_id]
    if not pstart_dnc_ready(action_id) then return false end
    pstart_dnc.pending = {
        action_id = action_id,
        action_name = ability.en,
        detail = detail,
    }
    windower.chat.input('/ja "'..ability.en..'" '..target)
    tickdelay = os.clock() + 1.5
    pstart_dnc.last_action = detail or ability.en
    return true
end

local function pstart_dnc_emergency_waltz(lowest)
    local choices
    if lowest.hpp < PSTART_DNC_CRITICAL_HPP then
        choices = {
            PSTART_DNC_ACTIONS.curing_waltz_v,
            PSTART_DNC_ACTIONS.curing_waltz_iv,
            PSTART_DNC_ACTIONS.curing_waltz_iii,
        }
    else
        -- Waltz III is generally the best HP-per-second emergency conversion;
        -- use higher tiers only when III is not currently available.
        choices = {
            PSTART_DNC_ACTIONS.curing_waltz_iii,
            PSTART_DNC_ACTIONS.curing_waltz_iv,
            PSTART_DNC_ACTIONS.curing_waltz_v,
        }
    end
    for _, action_id in ipairs(choices) do
        if pstart_dnc_use(action_id, lowest.token,
            ('%s -> %s (%d%%)')
                :format(res.job_abilities[action_id].en, lowest.name, lowest.hpp))
        then
            add_to_chat(158, '[PartyStart DNC] '..pstart_dnc.last_action)
            return true
        end
    end
    return false
end

local function pstart_dnc_haste_samba()
    if player.status ~= 'Engaged' or buffactive['Haste Samba'] then
        return false
    end
    return pstart_dnc_use(PSTART_DNC_ACTIONS.haste_samba, '<me>',
        'Haste Samba')
end

local function pstart_dnc_box_step()
    if player.status ~= 'Engaged' then return false end
    local target = pstart_dnc_leader_target()
    if not target or (target.distance or 999):sqrt() > 4.8 then return false end

    -- FFXI text commands do not accept a server mob ID as a target token.
    -- PartyCombat owns target synchronization, so wait until this client has
    -- the leader's mob selected and then use the normal <t> token.
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not local_target or local_target.id ~= target.id then return false end

    local next_step = pstart_dnc.stepped_targets[target.id] or 0
    if next_step > os.clock() then return false end

    if pstart_dnc_known(PSTART_DNC_ACTIONS.presto)
        and not buffactive['Presto']
        and pstart_dnc_ready(PSTART_DNC_ACTIONS.presto)
    then
        return pstart_dnc_use(PSTART_DNC_ACTIONS.presto, '<me>',
            'Presto for Box Step')
    end

    if pstart_dnc_use(PSTART_DNC_ACTIONS.box_step, '<t>',
        'Box Step -> '..target.name)
    then
        pstart_dnc.stepped_targets[target.id] =
            os.clock() + PSTART_DNC_STEP_RETRY
        return true
    end
    return false
end

local function pstart_dnc_has_flourish_stock()
    return buffactive['Finishing Move 3']
        or buffactive['Finishing Move 4']
        or buffactive['Finishing Move 5']
        or buffactive['Finishing Move (6+)']
end

local function pstart_dnc_has_any_finishing_move()
    return buffactive['Finishing Move 1']
        or buffactive['Finishing Move 2']
        or pstart_dnc_has_flourish_stock()
end

local function pstart_dnc_no_foot_rise(lowest)
    if player.status ~= 'Engaged'
        or player.tp >= PSTART_DNC_NO_FOOT_RISE_TP_CEILING
        or (lowest and lowest.hpp < PSTART_DNC_NO_FOOT_RISE_HEALTHY_HPP)
        or pstart_dnc_has_any_finishing_move()
    then
        return false
    end

    -- Spend the merit ability only while this client is synchronized to the
    -- puller's living target. This avoids burning No Foot Rise while between
    -- pulls, out of range, or reserving TP for emergency healing.
    local target = pstart_dnc_leader_target()
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not target or (target.distance or 999):sqrt() > 4.8
        or not local_target or local_target.id ~= target.id
    then
        return false
    end
    return pstart_dnc_use(PSTART_DNC_ACTIONS.no_foot_rise, '<me>',
        'No Foot Rise -> safe Reverse Flourish stock')
end

local function pstart_dnc_reverse_flourish()
    if player.status ~= 'Engaged' or player.tp >= 900
        or not pstart_dnc_has_flourish_stock()
    then
        return false
    end
    return pstart_dnc_use(PSTART_DNC_ACTIONS.reverse_flourish, '<me>',
        'Reverse Flourish -> TP for Evisceration')
end

local function pstart_dnc_action()
    if not pstart_dnc.active
        or player.main_job ~= 'DNC'
        or midaction() or moving or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
        or os.clock() < (pstart_dnc.retry_at or 0)
    then
        return false
    end

    local lowest = pstart_dnc_lowest_party_member()
    if lowest and lowest.hpp < PSTART_DNC_EMERGENCY_HPP then
        -- AutoWS2 normally consumes TP at 1000. Pause it before that threshold
        -- so the DNC can actually accumulate enough TP for a Waltz instead of
        -- being only an opportunistic healer.
        if not pstart_dnc.autows_paused then
            windower.send_command('aws2 off')
            pstart_dnc.autows_paused = true
            add_to_chat(207,
                ('[PartyStart DNC] Pausing AutoWS2 to fund emergency healing '
                    ..'for %s (%d%%).'):format(lowest.name, lowest.hpp))
        end
        if buffactive['Saber Dance'] then
            windower.send_command('cancel 410')
            pstart_dnc.last_action = 'cancelling Saber Dance for emergency Waltz'
            return true
        end
        if pstart_dnc_emergency_waltz(lowest) then return true end
        pstart_dnc.last_action =
            ('building TP for emergency Waltz -> %s (%d%%)')
                :format(lowest.name, lowest.hpp)
        return true
    elseif pstart_dnc.autows_paused then
        windower.send_command('aws2 on')
        pstart_dnc.autows_paused = false
        pstart_dnc.last_action = 'party stabilized; AutoWS2 resumed'
    end

    if pstart_dnc_haste_samba() then return true end
    if pstart_dnc_box_step() then return true end
    if pstart_dnc_no_foot_rise(lowest) then return true end
    return pstart_dnc_reverse_flourish()
end

local function pstart_dnc_status()
    local lowest = pstart_dnc_lowest_party_member()
    local target = pstart_dnc_leader_target()
    add_to_chat(122,
        ('PartyStart DNC: %s / profile %s / lowest %s / target %s / last %s')
        :format(
            pstart_dnc.active and 'On' or 'Off',
            tostring(pstart_dnc.profile or 'none'),
            lowest and (lowest.name..' '..lowest.hpp..'%') or 'none',
            target and target.name or 'none',
            pstart_dnc.last_action))
end

local pstart_dnc_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartdnc' then
        if pstart_dnc_original_self_command then
            return pstart_dnc_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'tick' then
        pstart_dnc_action()
    elseif not requested or requested == 'status' then
        pstart_dnc_status()
    elseif requested == 'off' then
        -- PartyStart stop disables the AutoWS2 instance it owns before this
        -- command arrives. Never undo that stop just because DNC emergency
        -- mode happened to be holding TP.
        pstart_dnc.active = false
        pstart_dnc.profile = nil
        pstart_dnc.pending = nil
        pstart_dnc.autows_paused = false
        add_to_chat(122, 'PartyStart DNC support is Off.')
    elseif requested and S{
        'master','physical','accuracy','magic','safe'
    }:contains(requested)
        and pstart_dnc_valid_name(commandArgs[3])
    then
        pstart_dnc.active = true
        pstart_dnc.profile = requested
        pstart_dnc.leader = commandArgs[3]
        pstart_dnc.pending = nil
        pstart_dnc.retry_at = 0
        pstart_dnc.stepped_targets = {}
        pstart_dnc.autows_paused = false
        tickdelay = 0
        add_to_chat(122,
            'PartyStart DNC: Haste Samba, Box Step, safe No Foot Rise, '
            ..'Reverse Flourish, and emergency Waltz are On; Saber Dance remains Off.')
        -- PartyStart configures AutoWS2 immediately after this command. The
        -- shared maintenance heartbeat performs the first DNC action after
        -- that ownership handoff, allowing emergency mode to pause it safely.
    else
        add_to_chat(123,
            'PartyStart DNC usage: gs c pstartdnc '
            ..'<master|physical|accuracy|magic|safe|status|off> <leader>')
    end
end

local pstart_dnc_original_user_job_tick = user_job_tick
function user_job_tick()
    if pstart_dnc_action() then return true end
    if pstart_dnc_original_user_job_tick then
        return pstart_dnc_original_user_job_tick()
    end
    return false
end

local pstart_dnc_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_dnc.pending
    local completed_action = pending and spell
        and (spell.id == pending.action_id
            or spell.recast_id == pending.action_id)
    if pending and completed_action then
        if spell.interrupted then
            pstart_dnc.retry_at = os.clock() + 1.5
            pstart_dnc.last_action = pending.action_name..' interrupted; retry armed'
        else
            pstart_dnc.retry_at = os.clock() + 0.75
        end
        pstart_dnc.pending = nil
    end
    if pstart_dnc_original_job_aftercast then
        return pstart_dnc_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
