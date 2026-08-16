-- PartyStart PLD controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
--
-- This controller owns HP decisions and a conservative tank-cooldown policy.
-- Selindrile's native PLD controller continues to own Majesty upkeep, self
-- buffs, and Flash after this higher-priority pass returns false. While this
-- controller is active on PLD/WAR, it intercepts the native SubJobEnmity
-- command so Defender is an emergency tool instead of an offensive-rotation
-- step. PartyStart disables native AutoTankFull so Sentinel/Rampart/Palisade
-- have exactly one automation owner.
-- Load at the end of a participating character's PLD gear file:
--     include('Common/PartyStart_PLD.lua')

local pstart_pld = {
    active = false,
    profile = nil,
    leader = nil,
    pending = nil,
    retry_at = 0,
    cure_count = 0,
    last_action = 'none',
    last_health_report = nil,
    last_health_report_at = 0,
    autows_paused = false,
    target_id = nil,
    target_seen_at = 0,
    flash_target_id = nil,
    pressure_until = 0,
    last_self_hpp = nil,
}

local PSTART_PLD_ROUTINE_HPP = 82
local PSTART_PLD_CLUSTER_HPP = 90
local PSTART_PLD_CLUSTER_COUNT = 3
local PSTART_PLD_EMERGENCY_HPP = 55
local PSTART_PLD_ROUTINE_MP_FLOOR = 30
local PSTART_PLD_CONSERVE_MP_HPP = 50
local PSTART_PLD_LOW_MP_HPP = 35
local PSTART_PLD_CONSERVE_ROUTINE_HPP = 72
local PSTART_PLD_LOW_MP_ROUTINE_HPP = 65
local PSTART_PLD_CURE_INTERVAL_HIGH = 3
local PSTART_PLD_CURE_INTERVAL_MID = 5
local PSTART_PLD_CURE_INTERVAL_LOW = 8
local PSTART_PLD_MAJESTY_ACTION_ID = 394
local PSTART_PLD_CHIVALRY_ACTION_ID = 158
local PSTART_PLD_CHIVALRY_RESERVE_HPP = 45
local PSTART_PLD_CHIVALRY_USE_HPP = 45
local PSTART_PLD_CHIVALRY_RELEASE_HPP = 55
local PSTART_PLD_CHIVALRY_TP = 1000
local PSTART_PLD_SENTINEL_ACTION_ID = 48
local PSTART_PLD_RAMPART_ACTION_ID = 92
local PSTART_PLD_PALISADE_ACTION_ID = 278
local PSTART_PLD_BERSERK_ACTION_ID = 31
local PSTART_PLD_WARCRY_ACTION_ID = 32
local PSTART_PLD_DEFENDER_ACTION_ID = 33
local PSTART_PLD_AGGRESSOR_ACTION_ID = 34
local PSTART_PLD_PROVOKE_ACTION_ID = 35
local PSTART_PLD_DEFENDER_TRIGGER_HPP = 50
local PSTART_PLD_DEFENDER_RELEASE_HPP = 70
local PSTART_PLD_ESTABLISH_DELAY = 5
local PSTART_PLD_RAMPART_CLUSTER_HPP = 85
local PSTART_PLD_RAMPART_CLUSTER_COUNT = 2
local PSTART_PLD_PRESSURE_WINDOW = 12
local PSTART_PLD_V1_HUNDRED_FISTS_HPP = 52
local PSTART_PLD_PROFILES = {
    master=true,
    apexbats=true,
    locusbats=true,
    apexcrabs=true,
    limbus=true,
    ['ambuscade-v1']=true,
    ['ambuscade-v2']=true,
}
local PSTART_PLD_SUSTAINED_PROFILES = {
    master=true,
    apexbats=true,
    locusbats=true,
    apexcrabs=true,
}

local PSTART_PLD_DEFAULT_HEAL_POLICY = {
    routine_hpp = PSTART_PLD_ROUTINE_HPP,
    cluster_hpp = PSTART_PLD_CLUSTER_HPP,
    cluster_count = PSTART_PLD_CLUSTER_COUNT,
    cluster_mp_floor = PSTART_PLD_CONSERVE_MP_HPP,
    emergency_hpp = PSTART_PLD_EMERGENCY_HPP,
    routine_mp_floor = PSTART_PLD_ROUTINE_MP_FLOOR,
    conserve_mp_hpp = PSTART_PLD_CONSERVE_MP_HPP,
    low_mp_hpp = PSTART_PLD_LOW_MP_HPP,
    conserve_routine_hpp = PSTART_PLD_CONSERVE_ROUTINE_HPP,
    low_mp_routine_hpp = PSTART_PLD_LOW_MP_ROUTINE_HPP,
    cure_interval_high = PSTART_PLD_CURE_INTERVAL_HIGH,
    cure_interval_mid = PSTART_PLD_CURE_INTERVAL_MID,
    cure_interval_low = PSTART_PLD_CURE_INTERVAL_LOW,
    cure_iv_hpp = 65,
    chivalry_reserve_hpp = PSTART_PLD_CHIVALRY_RESERVE_HPP,
    chivalry_use_hpp = PSTART_PLD_CHIVALRY_USE_HPP,
    chivalry_release_hpp = PSTART_PLD_CHIVALRY_RELEASE_HPP,
}

-- Crab AoE arrives in bursts across several melee characters. Begin Majesty
-- recovery earlier and keep cheap Cure III flowing at lower MP instead of
-- waiting for individual members to reach the Eft profile's danger line.
local PSTART_PLD_CRAB_HEAL_POLICY = {
    routine_hpp = 88,
    cluster_hpp = 92,
    cluster_count = 2,
    cluster_mp_floor = 35,
    emergency_hpp = 65,
    routine_mp_floor = 25,
    conserve_mp_hpp = 50,
    low_mp_hpp = 35,
    conserve_routine_hpp = 78,
    low_mp_routine_hpp = 68,
    cure_interval_high = 2.5,
    cure_interval_mid = 4,
    cure_interval_low = 6,
    cure_iv_hpp = 70,
    chivalry_reserve_hpp = 60,
    chivalry_use_hpp = 55,
    chivalry_release_hpp = 70,
}

local function pstart_pld_heal_policy()
    return (pstart_pld.profile == 'apexcrabs'
            or pstart_pld.profile == 'limbus')
        and PSTART_PLD_CRAB_HEAL_POLICY
        or PSTART_PLD_DEFAULT_HEAL_POLICY
end

local function pstart_pld_valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function pstart_pld_known_ability(action_id)
    local abilities = windower.ffxi.get_abilities() or {}
    for _, learned_id in ipairs(abilities.job_abilities or {}) do
        if learned_id == action_id then return true end
    end
    return false
end

local function pstart_pld_ready(spell)
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return spell
        and not midaction()
        and not moving
        and not silent_check_disable()
        and (not tickdelay or os.clock() >= tickdelay)
        and os.clock() >= (pstart_pld.retry_at or 0)
        and (recasts[spell.id] or 0) < spell_latency
        and player.mp >= spell.mp_cost
        and silent_can_use(spell.id)
end

local function pstart_pld_ready_spell(choices)
    local learned = windower.ffxi.get_spells() or {}
    for _, name in ipairs(choices) do
        local spell = res.spells:with('en', name)
        if spell and learned[spell.id] and pstart_pld_ready(spell) then
            return spell
        end
    end
    return nil
end

local function pstart_pld_ability_ready(action_id)
    local ability = res.job_abilities[action_id]
    local recasts = windower.ffxi.get_ability_recasts() or {}
    return ability
        and pstart_pld_known_ability(action_id)
        and not midaction()
        and not moving
        and not silent_check_disable()
        and not silent_check_amnesia()
        and (not tickdelay or os.clock() >= tickdelay)
        and os.clock() >= (pstart_pld.retry_at or 0)
        and (recasts[ability.recast_id] or 999) < latency
end

local function pstart_pld_enemy_target()
    local target = windower.ffxi.get_mob_by_target('t')
    if not target or target.spawn_type ~= 16 or not target.valid_target
        or not target.hpp or target.hpp <= 0
    then
        pstart_pld.target_id = nil
        pstart_pld.target_seen_at = 0
        pstart_pld.flash_target_id = nil
        return nil
    end
    if pstart_pld.target_id ~= target.id then
        pstart_pld.target_id = target.id
        pstart_pld.target_seen_at = os.clock()
        pstart_pld.flash_target_id = nil
    end
    return target
end

local function pstart_pld_observe_pressure()
    if type(player.hpp) == 'number' then
        if type(pstart_pld.last_self_hpp) == 'number'
            and player.hpp < pstart_pld.last_self_hpp
        then
            pstart_pld.pressure_until = os.clock()
                + PSTART_PLD_PRESSURE_WINDOW
        end
        pstart_pld.last_self_hpp = player.hpp
    end
end

local function pstart_pld_use_tank_ability(action_id, detail)
    local ability = res.job_abilities[action_id]
    if not ability or not pstart_pld_ability_ready(action_id) then
        return false
    end
    pstart_pld.pending = {
        kind = 'tank_ability',
        action_id = action_id,
        spell_name = ability.en,
    }
    windower.chat.input('/ja "'..ability.en..'" <me>')
    tickdelay = os.clock() + 1.5
    pstart_pld.last_action = detail or ability.en
    add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
    return true
end

-- Selindrile's native PLD/WAR sequence treats Defender as the next generic
-- enmity action after Warcry. That overlaps an attack penalty with offensive
-- buffs and can leave the tank in Defender for routine, healthy combat. This
-- replacement deliberately ignores tickdelay because the native job tick sets
-- tickdelay immediately after queueing `gs c SubJobEnmity`; all other safety
-- gates remain intact.
local function pstart_pld_use_war_ability(action_id, target, detail)
    local ability = res.job_abilities[action_id]
    local recasts = windower.ffxi.get_ability_recasts() or {}
    if not ability
        or not pstart_pld_known_ability(action_id)
        or midaction()
        or silent_check_disable()
        or silent_check_amnesia()
        or os.clock() < (pstart_pld.retry_at or 0)
        or (recasts[ability.recast_id] or 999) >= latency
    then
        return false
    end
    pstart_pld.pending = {
        kind = 'tank_ability',
        action_id = action_id,
        spell_name = ability.en,
    }
    windower.chat.input('/ja "'..ability.en..'" '..target)
    tickdelay = os.clock() + 1.5
    pstart_pld.last_action = detail or ability.en
    add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
    return true
end

local function pstart_pld_cancel_offense_for_defender()
    local cancelled = {}
    if buffactive['Warcry'] then
        windower.send_command('cancel warcry')
        cancelled[#cancelled + 1] = 'Warcry'
    end
    if buffactive['Berserk'] then
        windower.send_command('cancel berserk')
        cancelled[#cancelled + 1] = 'Berserk'
    end
    if #cancelled == 0 then return false end
    tickdelay = os.clock() + 0.5
    pstart_pld.last_action = 'cancelled '..table.concat(cancelled, '/')
        ..' for emergency Defender'
    add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
    return true
end

local function pstart_pld_war_subjob_enmity()
    if player.sub_job ~= 'WAR' or state.Buff['SJ Restriction']
        or not pstart_pld_enemy_target()
    then
        return false
    end

    local hpp = tonumber(player.hpp) or 100
    if hpp < PSTART_PLD_DEFENDER_TRIGGER_HPP then
        if pstart_pld_cancel_offense_for_defender() then return true end
        if not buffactive['Defender']
            and pstart_pld_use_war_ability(
                PSTART_PLD_DEFENDER_ACTION_ID,
                '<me>',
                ('Defender emergency at %d%% HP'):format(hpp))
        then
            return true
        end
        -- Hate remains useful while the emergency window is active, but do
        -- not reintroduce Warcry, Berserk, or Aggressor behind Defender.
        return pstart_pld_use_war_ability(
            PSTART_PLD_PROVOKE_ACTION_ID, '<t>', 'Provoke')
    end

    if buffactive['Defender'] then
        if hpp >= PSTART_PLD_DEFENDER_RELEASE_HPP then
            windower.send_command('cancel defender')
            tickdelay = os.clock() + 0.5
            pstart_pld.last_action = ('Defender released at %d%% HP')
                :format(hpp)
            add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
            return true
        end
        -- Warcry can also arrive from another WAR after Defender was applied.
        -- Enforce mutual exclusion throughout the recovery band, not only on
        -- the initial emergency tick.
        if pstart_pld_cancel_offense_for_defender() then return true end
        -- Keep the emergency defense through the recovery band and permit
        -- only Provoke. The 50/70 hysteresis prevents cure-driven toggling.
        return pstart_pld_use_war_ability(
            PSTART_PLD_PROVOKE_ACTION_ID, '<t>', 'Provoke')
    end

    if pstart_pld_use_war_ability(
        PSTART_PLD_PROVOKE_ACTION_ID, '<t>', 'Provoke')
    then
        return true
    end
    if pstart_pld_use_war_ability(
        PSTART_PLD_WARCRY_ACTION_ID, '<me>', 'Warcry')
    then
        return true
    end
    if pstart_pld_use_war_ability(
        PSTART_PLD_AGGRESSOR_ACTION_ID, '<me>', 'Aggressor')
    then
        return true
    end
    return pstart_pld_use_war_ability(
        PSTART_PLD_BERSERK_ACTION_ID, '<me>', 'Berserk')
end

local function pstart_pld_tank_cooldown(lowest, cluster_injured)
    if player.status ~= 'Engaged' and player.status ~= 1 then return false end
    local target = pstart_pld_enemy_target()
    if not target then return false end

    -- Never overlap the automated cooldowns. A second button during an
    -- existing window adds little to routine Apex farming and wastes the next
    -- safety window.
    if buffactive['Sentinel'] or buffactive['Rampart']
        or buffactive['Palisade']
    then
        return false
    end

    if pstart_pld.profile == 'ambuscade-v1'
        and target.name == 'Bozzetto Breadwinner'
    then
        if target.hpp > PSTART_PLD_V1_HUNDRED_FISTS_HPP then
            return false
        end
        if pstart_pld_use_tank_ability(
            PSTART_PLD_SENTINEL_ACTION_ID,
            'Sentinel reserved for Breadwinner Hundred Fists')
        then
            return true
        end
        if target.hpp <= 50 and not buffactive['Sentinel']
            and pstart_pld_use_tank_ability(
                PSTART_PLD_RAMPART_ACTION_ID,
                'Rampart follow-up during Breadwinner Hundred Fists')
        then
            return true
        end
    elseif PSTART_PLD_SUSTAINED_PROFILES[pstart_pld.profile] then
        local established = pstart_pld.flash_target_id == target.id
            or os.clock() - pstart_pld.target_seen_at
                >= PSTART_PLD_ESTABLISH_DELAY
        if established and pstart_pld_use_tank_ability(
            PSTART_PLD_SENTINEL_ACTION_ID,
            'Sentinel after target establishment')
        then
            return true
        end
    end

    if lowest and lowest.hpp < PSTART_PLD_RAMPART_CLUSTER_HPP
        and cluster_injured >= PSTART_PLD_RAMPART_CLUSTER_COUNT
        and pstart_pld_use_tank_ability(
            PSTART_PLD_RAMPART_ACTION_ID,
            ('Rampart for %d injured party members'):format(cluster_injured))
    then
        return true
    end

    if os.clock() < (pstart_pld.pressure_until or 0)
        and pstart_pld_use_tank_ability(
            PSTART_PLD_PALISADE_ACTION_ID, 'Palisade under active pressure')
    then
        return true
    end
    return false
end

local function pstart_pld_member_in_range(member)
    if not member or not member.name then return false end
    if member.name:lower() == player.name:lower() then return true end
    local mob = windower.ffxi.get_mob_by_name(member.name)
    return mob and mob.distance and mob.distance:sqrt() <= 20.5
end

local function pstart_pld_scan_party()
    local lowest = nil
    local cluster_injured = 0
    local policy = pstart_pld_heal_policy()
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table'
            and type(member.hpp) == 'number'
            and member.hpp > 0
            and pstart_pld_member_in_range(member)
        then
            if member.hpp < policy.cluster_hpp then
                cluster_injured = cluster_injured + 1
            end
            if not lowest or member.hpp < lowest.hpp then
                lowest = {
                    name = member.name,
                    token = member.name:lower() == player.name:lower()
                        and '<me>' or '<'..key..'>',
                    hpp = member.hpp,
                }
            end
        end
    end
    return lowest, cluster_injured
end

local function pstart_pld_mp_policy()
    local policy = pstart_pld_heal_policy()
    if player.mpp < policy.low_mp_hpp then
        return policy.low_mp_routine_hpp,
            policy.cure_interval_low, 'low'
    elseif player.mpp < policy.conserve_mp_hpp then
        return policy.conserve_routine_hpp,
            policy.cure_interval_mid, 'conserve'
    end
    return policy.routine_hpp, policy.cure_interval_high, 'normal'
end

local function pstart_pld_needs_cure(lowest, cluster_injured)
    if not lowest then return false, 'no in-range party member' end
    local routine_hpp = pstart_pld_mp_policy()
    if lowest.hpp < routine_hpp then
        return true, lowest.hpp < pstart_pld_heal_policy().emergency_hpp
            and 'emergency' or 'routine'
    end
    local policy = pstart_pld_heal_policy()
    if cluster_injured >= policy.cluster_count
        and player.mpp >= policy.cluster_mp_floor
    then
        return true, 'cluster'
    end
    return false, 'party healthy'
end

local function pstart_pld_activate_majesty()
    if buffactive['Majesty'] or midaction() or moving
        or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
        or not pstart_pld_known_ability(PSTART_PLD_MAJESTY_ACTION_ID)
    then
        return false
    end
    local ability = res.job_abilities[PSTART_PLD_MAJESTY_ACTION_ID]
    local recasts = windower.ffxi.get_ability_recasts() or {}
    if ability and (recasts[ability.recast_id] or 999) < latency then
        windower.chat.input('/ja "Majesty" <me>')
        tickdelay = os.clock() + 1.5
        pstart_pld.last_action = 'Majesty for pending party cure'
        return true
    end
    return false
end

local function pstart_pld_cure_choices(hpp, reason)
    local policy = pstart_pld_heal_policy()
    if hpp < 35 then
        return {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
    elseif hpp < policy.cure_iv_hpp then
        return {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
    elseif reason == 'cluster' then
        return {'Cure III', 'Cure IV', 'Cure II', 'Cure'}
    end
    return {'Cure III', 'Cure II', 'Cure IV', 'Cure'}
end

local function pstart_pld_cast_cure(lowest, cluster_injured, reason)
    local choices = pstart_pld_cure_choices(lowest.hpp, reason)
    local spell = pstart_pld_ready_spell(choices)
    if not spell then return false end

    pstart_pld.pending = {
        spell_id = spell.id,
        spell_name = spell.en,
        target_name = lowest.name,
        target_hpp = lowest.hpp,
        injured = cluster_injured,
        reason = reason,
    }
    windower.chat.input('/ma "'..spell.en..'" '..lowest.token)
    tickdelay = os.clock() + 2.5
    pstart_pld.last_action = ('%s -> %s (%d%%, %s)')
        :format(spell.en, lowest.name, lowest.hpp, reason)
    add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
    return true
end

local function pstart_pld_cure_interval()
    local _, interval = pstart_pld_mp_policy()
    return interval
end

local function pstart_pld_chivalry_available()
    local ability = res.job_abilities[PSTART_PLD_CHIVALRY_ACTION_ID]
    local recasts = windower.ffxi.get_ability_recasts() or {}
    return ability
        and pstart_pld_known_ability(PSTART_PLD_CHIVALRY_ACTION_ID)
        and (recasts[ability.recast_id] or 999) < latency
end

local function pstart_pld_chivalry_ready()
    return pstart_pld_chivalry_available()
        and not midaction()
        and not moving
        and not silent_check_disable()
        and not silent_check_amnesia()
        and (not tickdelay or os.clock() >= tickdelay)
end

local function pstart_pld_sustain_mp()
    local policy = pstart_pld_heal_policy()
    if pstart_pld.autows_paused then
        local chivalry_still_ready = pstart_pld_chivalry_ready()
        if player.mpp >= policy.chivalry_release_hpp
            or not chivalry_still_ready
        then
            windower.send_command('aws2 on')
            pstart_pld.autows_paused = false
            pstart_pld.last_action = player.mpp
                >= policy.chivalry_release_hpp
                and 'MP recovered; AutoWS2 resumed'
                or 'Chivalry unavailable; AutoWS2 resumed'
            return false
        end

        if player.mpp > policy.chivalry_use_hpp
            or player.tp < PSTART_PLD_CHIVALRY_TP
        then
            -- Reserving TP must not starve native Flash/Provoke/Warcry upkeep.
            return false
        end

        pstart_pld.pending = {
            kind = 'chivalry',
            action_id = PSTART_PLD_CHIVALRY_ACTION_ID,
            spell_name = 'Chivalry',
        }
        windower.chat.input('/ja "Chivalry" <me>')
        tickdelay = os.clock() + 1.5
        pstart_pld.last_action = 'Chivalry at '..tostring(player.tp)..' TP'
        add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
        return true
    end

    if player.mpp >= policy.chivalry_reserve_hpp
        or not pstart_pld_chivalry_ready()
    then
        return false
    end

    -- Reserve one TP cycle before MP is critical. Continue curing while TP
    -- accumulates, and spend it only after the use threshold is crossed.
    if not pstart_pld.autows_paused then
        windower.send_command('aws2 off')
        pstart_pld.autows_paused = true
        pstart_pld.last_action = 'low MP; reserving 1000 TP for Chivalry'
        add_to_chat(207,
            '[PartyStart PLD] Low MP: pausing AutoWS2 for Chivalry.')
    end
    if player.mpp > policy.chivalry_use_hpp
        or player.tp < PSTART_PLD_CHIVALRY_TP
    then
        -- Reserving TP must not starve native Flash/Provoke/Warcry upkeep.
        return false
    end

    pstart_pld.pending = {
        kind = 'chivalry',
        action_id = PSTART_PLD_CHIVALRY_ACTION_ID,
        spell_name = 'Chivalry',
    }
    windower.chat.input('/ja "Chivalry" <me>')
    tickdelay = os.clock() + 1.5
    pstart_pld.last_action = 'Chivalry at '..tostring(player.tp)..' TP'
    add_to_chat(158, '[PartyStart PLD] '..pstart_pld.last_action)
    return true
end

local function pstart_pld_action()
    if not pstart_pld.active or not PSTART_PLD_PROFILES[pstart_pld.profile]
        or player.main_job ~= 'PLD'
        or midaction() or moving or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
        or os.clock() < (pstart_pld.retry_at or 0)
    then
        return false
    end

    pstart_pld_observe_pressure()
    local policy = pstart_pld_heal_policy()
    local lowest, cluster_injured = pstart_pld_scan_party()
    -- Breadwinner's 50% Hundred Fists transition is deterministic. Claim the
    -- reserved mitigation before a stream of Majesty cures can monopolize the
    -- action loop at exactly the dangerous threshold.
    if pstart_pld.profile == 'ambuscade-v1'
        and pstart_pld_tank_cooldown(lowest, cluster_injured)
    then
        return true
    end
    local needed, reason = pstart_pld_needs_cure(lowest, cluster_injured)
    if not needed then
        if lowest and lowest.hpp < 100
            and (pstart_pld.last_health_report ~= lowest.hpp
                or os.clock() - pstart_pld.last_health_report_at > 15)
        then
            add_to_chat(207,
                ('[PartyStart PLD] Holding: lowest %s %d%%; '
                    ..'routine threshold %d%% at %d%% MP.')
                    :format(lowest.name, lowest.hpp,
                        pstart_pld_mp_policy(), player.mpp))
            pstart_pld.last_health_report = lowest.hpp
            pstart_pld.last_health_report_at = os.clock()
        end
        if pstart_pld_sustain_mp() then return true end
        return pstart_pld_tank_cooldown(lowest, cluster_injured)
    end

    local emergency = lowest.hpp < policy.emergency_hpp

    -- Chivalry has a ten-minute recast. When it is ready, use it before the
    -- next non-emergency cure so an uninterrupted stream of routine damage
    -- cannot permanently starve the MP recovery branch.
    if not emergency
        and player.mpp < policy.chivalry_reserve_hpp
    then
        if pstart_pld_sustain_mp() then return true end
        -- TP reservation must not suppress a needed cure. The original
        -- implementation returned here and exposed the party while charging.
    end

    if player.mpp < policy.routine_mp_floor and not emergency then
        pstart_pld.last_action = 'routine cure held for MP reserve'
        return pstart_pld_sustain_mp()
    end

    -- Majesty is not a hard prerequisite: if it was stripped and its recast
    -- is unavailable, a single-target cure is still better than waiting.
    if not buffactive['Majesty'] and pstart_pld_activate_majesty() then
        return true
    end
    if pstart_pld_cast_cure(lowest, cluster_injured, reason) then
        return true
    end
    if pstart_pld_sustain_mp() then return true end
    return pstart_pld_tank_cooldown(lowest, cluster_injured)
end

local function pstart_pld_status()
    local lowest, cluster_injured = pstart_pld_scan_party()
    local target = lowest and ('%s %d%%'):format(lowest.name, lowest.hpp)
        or 'none'
    add_to_chat(122,
        ('PartyStart PLD: %s / profile %s / MP %d%% (%s, cure <%d%%) '
            ..'/ lowest %s / injured %d / last %s')
        :format(
            pstart_pld.active and 'On' or 'Off',
            tostring(pstart_pld.profile or 'none'),
            player.mpp,
            select(3, pstart_pld_mp_policy()),
            pstart_pld_mp_policy(),
            target,
            cluster_injured,
            pstart_pld.last_action))
    local function active(buff)
        return buffactive[buff] and 'On' or 'Off'
    end
    add_to_chat(122,
        ('PartyStart PLD sustain: cures %d / Majesty %s / Refresh %s / '
            ..'Ballad %s / Entrust %s / Chivalry %s / AutoWS2 %s')
        :format(
            pstart_pld.cure_count,
            active('Majesty'), active('Refresh'), active('Ballad'),
            active('Colure Active'),
            pstart_pld_chivalry_available() and 'Ready' or 'Cooldown',
            pstart_pld.autows_paused and 'Reserved' or 'Active'))
end

local pstart_pld_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command == 'subjobenmity' and pstart_pld.active
        and player.main_job == 'PLD' and player.sub_job == 'WAR'
    then
        eventArgs.handled = true
        pstart_pld_war_subjob_enmity()
        return
    end
    if command ~= 'pstartpld' then
        if pstart_pld_original_self_command then
            return pstart_pld_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'tick' then
        pstart_pld_action()
    elseif not requested or requested == 'status' then
        pstart_pld_status()
    elseif requested == 'off' then
        pstart_pld.active = false
        pstart_pld.profile = nil
        pstart_pld.pending = nil
        -- PartyStart owns AutoWS2's stop state; do not re-enable it here.
        pstart_pld.autows_paused = false
        pstart_pld.target_id = nil
        pstart_pld.target_seen_at = 0
        pstart_pld.flash_target_id = nil
        pstart_pld.pressure_until = 0
        pstart_pld.last_self_hpp = nil
        add_to_chat(122, 'PartyStart PLD healing is Off.')
    elseif PSTART_PLD_PROFILES[requested]
        and pstart_pld_valid_name(commandArgs[3])
    then
        pstart_pld.active = true
        pstart_pld.profile = requested
        pstart_pld.leader = commandArgs[3]
        pstart_pld.pending = nil
        pstart_pld.retry_at = 0
        pstart_pld.last_health_report = nil
        pstart_pld.last_health_report_at = 0
        pstart_pld.autows_paused = false
        pstart_pld.target_id = nil
        pstart_pld.target_seen_at = 0
        pstart_pld.flash_target_id = nil
        pstart_pld.pressure_until = 0
        pstart_pld.last_self_hpp = player.hpp
        tickdelay = 0
        add_to_chat(122,
            ('PartyStart PLD: %s primary Majesty healing and controlled '
                ..'cooldowns are On.'):format(requested))
        pstart_pld_action()
    else
        add_to_chat(123,
            'PartyStart PLD usage: gs c pstartpld '
            ..'<master|apexbats|locusbats|apexcrabs|limbus|ambuscade-v1|ambuscade-v2|status|off> <leader>')
    end
end

local pstart_pld_original_user_job_tick = user_job_tick
function user_job_tick()
    if pstart_pld_action() then return true end
    if pstart_pld_original_user_job_tick then
        return pstart_pld_original_user_job_tick()
    end
    return false
end

local pstart_pld_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_pld.pending
    local spell_name = spell and (spell.english or spell.en or spell.name)
    if spell and not spell.interrupted and spell_name == 'Flash' then
        local target = pstart_pld_enemy_target()
        if target then pstart_pld.flash_target_id = target.id end
    end
    local completed_chivalry = pending and pending.kind == 'chivalry'
        and spell
        and (spell.id == pending.action_id
            or spell.recast_id == 79)
    if completed_chivalry then
        if spell.interrupted then
            pstart_pld.retry_at = os.clock() + 1.5
            pstart_pld.last_action = 'Chivalry interrupted; retry armed'
        else
            pstart_pld.retry_at = os.clock() + 0.75
            pstart_pld.last_action = 'Chivalry complete; AutoWS2 resumed'
        end
        pstart_pld.pending = nil
        if pstart_pld.autows_paused then
            windower.send_command('aws2 on')
            pstart_pld.autows_paused = false
        end
    elseif pending and pending.kind == 'tank_ability'
        and spell and spell.id == pending.action_id
    then
        if spell.interrupted then
            pstart_pld.retry_at = os.clock() + 1.5
            pstart_pld.last_action = pending.spell_name
                ..' interrupted; retry armed'
        else
            pstart_pld.retry_at = os.clock() + 0.75
        end
        pstart_pld.pending = nil
    elseif pending and spell and spell.id == pending.spell_id then
        if spell.interrupted then
            pstart_pld.retry_at = os.clock() + 1.5
            pstart_pld.last_action = pending.spell_name..' interrupted; retry armed'
        else
            pstart_pld.cure_count = pstart_pld.cure_count + 1
            pstart_pld.retry_at = os.clock()
                + math.max(1, pstart_pld_cure_interval() - 2.5)
        end
        pstart_pld.pending = nil
    end
    if pstart_pld_original_job_aftercast then
        return pstart_pld_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
