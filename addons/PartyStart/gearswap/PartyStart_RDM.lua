-- PartyStart RDM controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
-- Selindrile's shared include credits Motenten's base files. No upstream
-- GearSwap source is redistributed in this controller.
-- Load at the end of a participating character's RDM gear file:
--     include('Common/PartyStart_RDM.lua')

local pstart_rdm_profiles = {
    master = {
        sustained = true,
        -- Black Halo is 70% MND / 30% STR, so MND is the stronger equal-cost
        -- Gain spell for Smalls's Maxentius offense.
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        -- Apex Efts do not cast spells. Their magical TP effects apply status
        -- ailments without listed magic damage, which Shell does not prevent.
        party_shell = false,
        routine_buff_mp_floor = 35,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 55,
        debuff_min_target_hpp = 65,
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=150},
        },
    },
    apexbats = {
        sustained = true,
        -- The Dho Gates flock bats use Water-aligned Sonic Boom for Attack
        -- Down without listed damage. Barwatera and job-aware Erase are useful;
        -- a six-target Shell pass is not.
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        party_shell = false,
        routine_buff_mp_floor = 35,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 55,
        debuff_min_target_hpp = 65,
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=150},
        },
    },
    apexcrabs = {
        sustained = true,
        -- Bubble Shower deals Water damage and applies STR Down, so the
        -- one-time Shell rotation has real value here in addition to
        -- Barwatera and HealBot's job-aware Erase policy.
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        party_shell = true,
        routine_buff_mp_floor = 35,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 55,
        debuff_min_target_hpp = 65,
        heal_hpp = 45,
        heal_mp_floor = 25,
        dispel = {
            target_names={'Apex Crab'},
            moves={
                ['Bubble Curtain']=true,
                ['Metallic Body']=true,
                ['Scissor Guard']=true,
            },
            mp_floor=55,
            min_target_hpp=15,
            ttl=30,
            max_pending=3,
        },
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=150},
        },
    },
    physical = {
        gain = {spells={'Gain-STR'}, buff='STR Boost'},
        temper = true,
        debuff_mp_floor = 45,
        debuff_min_target_hpp = 50,
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=45},
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150},
        },
    },
    accuracy = {
        gain = {spells={'Gain-DEX'}, buff='DEX Boost'},
        temper = true,
        debuff_mp_floor = 35,
        debuff_min_target_hpp = 35,
        debuffs = {
            {spells={'Frazzle III', 'Frazzle II', 'Frazzle'}, duration=150},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=45},
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150},
        },
    },
    magic = {
        gain = {spells={'Gain-INT'}, buff='INT Boost'},
        temper = false,
        debuff_mp_floor = 35,
        debuff_min_target_hpp = 35,
        debuffs = {
            {spells={'Frazzle III', 'Frazzle II', 'Frazzle'}, duration=150},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=45},
            {spells={'Addle II', 'Addle'}, duration=150},
        },
    },
    safe = {
        gain = {spells={'Gain-VIT'}, buff='VIT Boost'},
        temper = false,
        debuff_mp_floor = 35,
        debuff_min_target_hpp = 35,
        debuffs = {
            {spells={'Frazzle III', 'Frazzle II', 'Frazzle'}, duration=150},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=45},
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150},
            {spells={'Slow II', 'Slow'}, duration=150},
            {spells={'Paralyze II', 'Paralyze'}, duration=150},
            {spells={'Blind II', 'Blind'}, duration=150},
            {spells={'Addle II', 'Addle'}, duration=150},
        },
    },
    ['ambuscade-v1'] = {
        gain = {spells={'Gain-MND'}, buff='MND Boost'},
        temper = false,
        lean = true,
        reraise = true,
        party_shell = true,
        party_protect = false,
        routine_buff_mp_floor = 25,
        tank_buff_mp_floor = 15,
        debuff_mp_floor = 20,
        debuff_min_target_hpp = 5,
        healing = true,
        heal_hpp = 55,
        heal_mp_floor = 20,
        priority_debuff = true,
        opener = {
            target_names={'Bozzetto Breadwinner'},
            abilities={'Stymie', 'Saboteur'},
        },
        debuffs = {
            {spells={'Silence'}, duration=45, confirm_result=true,
                target_names={'Bozzetto Breadwinner'}},
            {spells={'Paralyze II', 'Paralyze'}, duration=120,
                target_names={'Bozzetto Breadwinner'}},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=120,
                target_names={'Bozzetto Breadwinner'}},
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150,
                target_names={'Bozzetto Breadwinner'}},
        },
    },
    ['ambuscade-v2'] = {
        gain = {spells={'Gain-MND'}, buff='MND Boost'},
        temper = false,
        lean = true,
        reraise = true,
        party_shell = true,
        party_protect = false,
        routine_buff_mp_floor = 25,
        tank_buff_mp_floor = 15,
        debuff_mp_floor = 20,
        debuff_min_target_hpp = 10,
        healing = true,
        heal_hpp = 65,
        heal_mp_floor = 20,
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=120,
                target_names={'Popular Penelope'}},
        },
    },
}

local pstart_rdm = {
    active = false,
    profile = nil,
    leader = nil,
    haste = {},
    refresh = {},
    phalanx = {},
    defense = {},
    buff_timers = {},
    debuff_timers = {},
    debuff_attempts = {},
    pending = nil,
    convert_recovery_until = 0,
    remote_loss_count = 0,
    last_remote_loss = 'none',
    last_loss_events = {},
    reactive_repairs = {},
    opener_targets = {},
    last_heal_at = 0,
    dispel_targets = {},
    dispel_count = 0,
    last_dispel = 'none',
}

local PSTART_RDM_LOSE_EFFECT_MESSAGES = {
    [64]=true, [74]=true, [83]=true, [123]=true, [159]=true,
    [168]=true, [204]=true, [206]=true, [322]=true, [341]=true,
    [342]=true, [343]=true, [344]=true, [350]=true, [378]=true,
    [453]=true, [531]=true, [647]=true,
}

local PSTART_RDM_DEBUFF_RETRY = 3
local PSTART_RDM_DEBUFF_COVERED_RECHECK = 15

local PSTART_RDM_MAINTAINED_BUFFS = {
    Haste = {'Haste II', 'Haste'},
    Refresh = {'Refresh III', 'Refresh II', 'Refresh'},
    Phalanx = {'Phalanx II'},
    Shell = {'Shell V', 'Shell IV', 'Shell III', 'Shell II', 'Shell'},
    Protect = {'Protect V', 'Protect IV', 'Protect III', 'Protect II', 'Protect'},
}

local function pstart_rdm_valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function pstart_rdm_names(value)
    local names = {}
    if type(value) ~= 'string' or value == '-' then
        return names
    end
    for name in value:gmatch('[^,]+') do
        if pstart_rdm_valid_name(name) then
            names[#names + 1] = name
        end
    end
    return names
end

local function pstart_rdm_spell(choices)
    local learned = windower.ffxi.get_spells() or {}
    for _, name in ipairs(choices) do
        local spell = res.spells:with('en', name)
        if spell and learned[spell.id] then
            return spell
        end
    end
    return nil
end

local function pstart_rdm_ready(spell)
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return spell
        and not midaction()
        and not moving
        and not silent_check_disable()
        and (not tickdelay or os.clock() >= tickdelay)
        and (recasts[spell.id] or 0) < spell_latency
        and player.mp >= spell.mp_cost
        and silent_can_use(spell.id)
end

local function pstart_rdm_ready_spell(choices)
    local learned = windower.ffxi.get_spells() or {}
    for _, name in ipairs(choices) do
        local spell = res.spells:with('en', name)
        if spell and learned[spell.id] and pstart_rdm_ready(spell) then
            return spell
        end
    end
    return nil
end

local function pstart_rdm_known_ability(ability)
    if not ability then return false end
    local abilities = windower.ffxi.get_abilities() or {}
    for _, learned_id in ipairs(abilities.job_abilities or {}) do
        if learned_id == ability.id then return true end
    end
    return false
end

local function pstart_rdm_party_token(name)
    if name:lower() == player.name:lower() then
        return '<me>'
    end
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and member.name
            and member.name:lower() == name:lower()
        then
            return '<'..key..'>'
        end
    end
    return nil
end

local function pstart_rdm_in_range(name)
    if name:lower() == player.name:lower() then
        return true
    end
    local mob = windower.ffxi.get_mob_by_name(name)
    return mob and mob.distance and mob.distance:sqrt() <= 20.5
end

local function pstart_rdm_buff_key(name, spell)
    return name:lower()..':'..tostring(spell.id)
end

local function pstart_rdm_name_in(names, wanted)
    for _, name in ipairs(names or {}) do
        if name:lower() == wanted:lower() then
            return true
        end
    end
    return false
end

local function pstart_rdm_owns_buff(name, buff)
    if buff == 'Haste' then
        return pstart_rdm_name_in(pstart_rdm.haste, name)
    elseif buff == 'Refresh' then
        return pstart_rdm_name_in(pstart_rdm.refresh, name)
    elseif buff == 'Phalanx' then
        return pstart_rdm_name_in(pstart_rdm.phalanx, name)
    end

    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    local defensive_target = pstart_rdm_name_in(pstart_rdm.defense, name)
        or pstart_rdm_name_in(pstart_rdm.haste, name)
        or pstart_rdm_name_in(pstart_rdm.refresh, name)
        or pstart_rdm_name_in(pstart_rdm.phalanx, name)
    if not profile or not defensive_target then
        return false
    end
    if buff == 'Shell' then
        return profile.party_shell or not profile.lean
    elseif buff == 'Protect' then
        -- Majesty supplies initial Protect in sustained profiles. RDM repairs
        -- only an individual copy that a loss packet confirms was dispelled,
        -- subject to the sustained profile's routine MP reserve.
        return profile.party_protect
            or profile.sustained or not profile.lean
    end
    return false
end

local function pstart_rdm_register_remote_buff_loss(
    target_id, message_id, buff_id)
    if not pstart_rdm.active
        or not PSTART_RDM_LOSE_EFFECT_MESSAGES[message_id]
    then
        return
    end
    local buff = res.buffs[buff_id]
    local choices = buff and PSTART_RDM_MAINTAINED_BUFFS[buff.en]
        or nil
    if not choices then return end

    local target = windower.ffxi.get_mob_by_id(target_id)
    if not target or not pstart_rdm_valid_name(target.name) then return end
    if not pstart_rdm_party_token(target.name) then return end
    if not pstart_rdm_owns_buff(target.name, buff.en) then return end
    local spell = pstart_rdm_spell(choices)
    if not spell then return end

    local event_key = tostring(target_id)..':'..tostring(buff_id)
    local now = os.clock()
    if now - (pstart_rdm.last_loss_events[event_key] or 0) < 0.5 then
        return
    end
    pstart_rdm.last_loss_events[event_key] = now
    local repair_key = pstart_rdm_buff_key(target.name, spell)
    pstart_rdm.buff_timers[repair_key] = 0
    pstart_rdm.reactive_repairs[repair_key] = {
        name = target.name,
        choices = choices,
        buff = buff.en,
        duration = ({
            Haste=165, Refresh=135, Phalanx=225,
            Shell=1650, Protect=1800,
        })[buff.en] or 165,
    }
    pstart_rdm.remote_loss_count = pstart_rdm.remote_loss_count + 1
    pstart_rdm.last_remote_loss = buff.en..' -> '..target.name
end

local function pstart_rdm_debuff_outcome(message_id)
    local message = res.action_messages[message_id]
    if not message then return 'unknown' end
    local text = type(message.en) == 'string' and message.en:lower() or ''
    if message_id == 66 or text:find('resist', 1, true) then
        return 'resisted'
    end
    -- "No effect" normally means another source already has an equal or
    -- stronger enfeeble on the target. Treat it as temporarily covered rather
    -- than retrying every maintenance tick.
    if text:find('no effect', 1, true) then
        return 'covered'
    end
    if message.color == 'R'
        or text:find('fails to take effect', 1, true)
    then
        return 'failed'
    end
    return 'landed'
end

local function pstart_rdm_register_debuff_result(action)
    local local_player = windower.ffxi.get_player()
    if not local_player or type(action) ~= 'table'
        or action.actor_id ~= local_player.id
        or action.category ~= 4
    then
        return
    end
    local spell_id = tonumber(action.param)
    if not spell_id then return end

    for _, target in ipairs(action.targets or {}) do
        local key = tostring(target.id)..':'..tostring(spell_id)
        local attempt = pstart_rdm.debuff_attempts[key]
        local result = target.actions and target.actions[1] or nil
        if attempt and result and result.message then
            local outcome = pstart_rdm_debuff_outcome(result.message)
            local now = os.clock()
            attempt.outcome = outcome
            attempt.resolved_at = now
            if outcome == 'landed' then
                pstart_rdm.debuff_timers[key] = now + attempt.duration
                add_to_chat(158, ('[PartyStart RDM] %s confirmed on %s.')
                    :format(attempt.spell_name, attempt.target_name))
            elseif outcome == 'covered' then
                pstart_rdm.debuff_timers[key] =
                    now + PSTART_RDM_DEBUFF_COVERED_RECHECK
                add_to_chat(207, ('[PartyStart RDM] %s reported no effect on '
                    ..'%s; treating the target as temporarily covered.')
                    :format(attempt.spell_name, attempt.target_name))
            else
                pstart_rdm.debuff_timers[key] =
                    now + PSTART_RDM_DEBUFF_RETRY
                add_to_chat(123, ('[PartyStart RDM] %s did not land on %s; '
                    ..'retrying as soon as recast permits.')
                    :format(attempt.spell_name, attempt.target_name))
            end
        end
    end
end

-- Apex Eft's Geist Wall can remove a maintained buff long before its normal
-- duration expires. Invalidate only that target's GearSwap timer from the
-- authoritative action packet so it is recast without giving HealBot buff
-- ownership or restarting the whole six-character rotation.
windower.raw_register_event('action', function(action)
    pstart_rdm_register_debuff_result(action)
    local profile = pstart_rdm.active
        and pstart_rdm_profiles[pstart_rdm.profile]
        or nil
    local policy = profile and profile.dispel or nil
    -- Category 7 announces the readying move and stores its ID inside the
    -- first target result. Category 11 is the completed move and exposes the
    -- same ID in action.param. Queue only on completion so one move cannot
    -- create two Dispel attempts or survive an interrupted readying action.
    local ability = policy and action and action.category == 11
        and res.monster_abilities[action.param]
        or nil
    local actor = ability and windower.ffxi.get_mob_by_id(action.actor_id)
        or nil
    local local_target = actor and windower.ffxi.get_mob_by_target('t')
        or nil
    if actor and type(actor.name) == 'string'
        and local_target and local_target.id == actor.id
        and pstart_rdm_name_in(policy.target_names, actor.name)
        and policy.moves[ability.en]
    then
        local now = os.clock()
        local queue = pstart_rdm.dispel_targets[actor.id]
        if not queue then
            queue = {entries={}}
        end
        queue.entries = queue.entries or {}
        for index = #queue.entries, 1, -1 do
            if (queue.entries[index].expires or 0) <= now then
                table.remove(queue.entries, index)
            end
        end
        if #queue.entries < (tonumber(policy.max_pending) or 3) then
            queue.entries[#queue.entries + 1] = {
                move = ability.en,
                expires = now + (tonumber(policy.ttl) or 30),
            }
        end
        queue.name = actor.name
        pstart_rdm.dispel_targets[actor.id] = #queue.entries > 0
            and queue or nil
    end

    for _, target in ipairs((action and action.targets) or {}) do
        for _, result in ipairs(target.actions or {}) do
            pstart_rdm_register_remote_buff_loss(
                target.id, result.message, result.param)
        end
    end
end)

windower.raw_register_event('action message', function(
    actor_id, target_id, actor_index, target_index,
    message_id, param_1, param_2, param_3)
    pstart_rdm_register_remote_buff_loss(target_id, message_id, param_1)
end)

local function pstart_rdm_can_spend(spell, mp_floor)
    if not mp_floor or mp_floor <= 0 then
        return true
    end
    -- GearSwap's packet parser exposes max_mp directly. Retain a derived
    -- fallback for startup frames before that field has populated.
    local max_mp = player.max_mp or 0
    if max_mp <= 0 and player.mp > 0 and player.mpp > 0 then
        max_mp = player.mp * 100 / player.mpp
    end
    if max_mp <= 0 then
        return false
    end
    local post_cast_mpp = (player.mp - spell.mp_cost)
        * 100 / max_mp
    return post_cast_mpp >= mp_floor
end

local function pstart_rdm_cast_buff(
    name, choices, buff, duration, mp_floor)
    local spell = pstart_rdm_spell(choices)
    local token = pstart_rdm_party_token(name)
    if not spell or not token or not pstart_rdm_in_range(name) then
        return false
    end

    if name:lower() == player.name:lower() and buffactive[buff] then
        return false
    end

    local key = pstart_rdm_buff_key(name, spell)
    if name:lower() ~= player.name:lower()
        and (pstart_rdm.buff_timers[key] or 0) > os.clock()
    then
        return false
    end

    if pstart_rdm_can_spend(spell, mp_floor)
        and pstart_rdm_ready(spell)
    then
        pstart_rdm.pending = {
            kind = 'buff',
            spell_id = spell.id,
            key = key,
            duration = duration,
        }
        windower.chat.input('/ma "'..spell.en..'" '..token)
        tickdelay = os.clock() + 3
        return true
    end
    return false
end

local function pstart_rdm_cast_reactive_repair()
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    for key, task in pairs(pstart_rdm.reactive_repairs) do
        local mp_floor = 0
        if profile and profile.lean and task.buff ~= 'Refresh' then
            if task.buff == 'Phalanx' then
                mp_floor = profile.tank_buff_mp_floor or 0
            else
                mp_floor = profile.routine_buff_mp_floor or 0
            end
        end
        if not pstart_rdm_party_token(task.name) then
            pstart_rdm.reactive_repairs[key] = nil
        elseif pstart_rdm_in_range(task.name)
            and pstart_rdm_cast_buff(
                task.name, task.choices, task.buff, task.duration, mp_floor)
        then
            -- pstart_rdm_cast_buff created the pending cast record. Retain the
            -- repair on interruption and retire it only after a completed cast.
            pstart_rdm.pending.repair_key = key
            return true
        end
    end
    return false
end

local function pstart_rdm_convert()
    if player.mpp >= 15 or player.hpp < 70 or not player.in_combat
        or midaction() or moving or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
    then
        return false
    end
    local recasts = windower.ffxi.get_ability_recasts() or {}
    if (recasts[49] or 999) < 1 then
        windower.chat.input('/ja "Convert" <me>')
        pstart_rdm.convert_recovery_until = os.clock() + 20
        tickdelay = os.clock() + 2
        add_to_chat(122, 'PartyStart RDM: low MP; using guarded Convert.')
        return true
    end
    return false
end

local function pstart_rdm_convert_recovery()
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    if not profile
        or (not profile.sustained and not profile.healing)
        or os.clock() > (pstart_rdm.convert_recovery_until or 0)
    then
        return false
    end
    if player.hpp >= 90 then
        pstart_rdm.convert_recovery_until = 0
        return false
    end

    local choices
    if player.hpp < 45 then
        choices = {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
    elseif player.hpp < 70 then
        choices = {'Cure III', 'Cure IV', 'Cure II', 'Cure'}
    else
        choices = {'Cure II', 'Cure III', 'Cure IV', 'Cure'}
    end
    local spell = pstart_rdm_ready_spell(choices)
    if spell then
        windower.chat.input('/ma "'..spell.en..'" <me>')
        tickdelay = os.clock() + 3
        add_to_chat(122,
            'PartyStart RDM: healing self after Convert with '..spell.en..'.')
        return true
    end
    return false
end

local function pstart_rdm_emergency_heal()
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    if not profile
        or (not profile.sustained and not profile.healing)
        or os.clock() - (pstart_rdm.last_heal_at or 0) < 2.5
    then
        return false
    end

    -- PLD owns routine healing and DNC owns TP-funded emergency healing.
    -- RDM is the final low-HP/low-complexity safety net only.
    local heal_hpp = profile.heal_hpp or 25
    if player.mpp < (profile.heal_mp_floor or 20) then
        return false
    end

    local target_name, target_token, target_hpp
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and member.name
            and type(member.hpp) == 'number'
            and member.hpp > 0 and member.hpp < heal_hpp
            and pstart_rdm_in_range(member.name)
            and (not target_hpp or member.hpp < target_hpp)
        then
            target_name = member.name
            target_token = member.name:lower() == player.name:lower()
                and '<me>' or '<'..key..'>'
            target_hpp = member.hpp
        end
    end
    if not target_name then
        return false
    end

    local choices
    if target_hpp < 25 then
        choices = {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
    elseif target_hpp < 40 then
        choices = {'Cure III', 'Cure IV', 'Cure II', 'Cure'}
    else
        choices = {'Cure III', 'Cure II', 'Cure IV', 'Cure'}
    end
    local spell = pstart_rdm_ready_spell(choices)
    if spell then
        windower.chat.input('/ma "'..spell.en..'" '..target_token)
        tickdelay = os.clock() + 3
        pstart_rdm.last_heal_at = os.clock()
        add_to_chat(122, ('PartyStart RDM: emergency %s -> %s (%d%%).')
            :format(spell.en, target_name, target_hpp))
        return true
    end
    return false
end

local function pstart_rdm_refresh_priority(names)
    local ordered = {}
    for _, name in ipairs(names or {}) do
        if name:lower() == player.name:lower() then
            table.insert(ordered, 1, name)
        else
            ordered[#ordered + 1] = name
        end
    end
    return ordered
end

local function pstart_rdm_union_names(...)
    local names, seen = {}, {}
    for _, list in ipairs({...}) do
        for _, name in ipairs(list or {}) do
            local key = name:lower()
            if not seen[key] then
                seen[key] = true
                names[#names + 1] = name
            end
        end
    end
    return names
end

local function pstart_rdm_cast_party_buffs()
    -- Refresh the RDM first so offensive work cannot consume the reserve
    -- before MP recovery is established.
    local refresh = pstart_rdm_refresh_priority(pstart_rdm.refresh)
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    local routine_floor = profile.routine_buff_mp_floor or 0
    local tank_floor = profile.tank_buff_mp_floor or routine_floor
    local defense = #pstart_rdm.defense > 0 and pstart_rdm.defense
        or pstart_rdm_union_names(
            pstart_rdm.haste, pstart_rdm.refresh, pstart_rdm.phalanx)
    for _, name in ipairs(refresh) do
        if pstart_rdm_cast_buff(
            name, {'Refresh III', 'Refresh II', 'Refresh'}, 'Refresh', 135)
        then
            return true
        end
    end
    for _, name in ipairs(pstart_rdm.haste) do
        if pstart_rdm_cast_buff(
            name, {'Haste II', 'Haste'}, 'Haste', 165, routine_floor)
        then
            return true
        end
    end
    for _, name in ipairs(pstart_rdm.phalanx) do
        if pstart_rdm_cast_buff(
            name, {'Phalanx II'}, 'Phalanx', 225, tank_floor)
        then
            return true
        end
    end
    if profile.party_shell then
        -- General-purpose profiles retain one long-duration Shell pass.
        -- Protect is kept separate so profiles can choose their defense cost.
        for _, name in ipairs(defense) do
            if pstart_rdm_cast_buff(name,
                {'Shell V', 'Shell IV', 'Shell III', 'Shell II', 'Shell'},
                'Shell', 1650)
            then
                return true
            end
        end
    end
    if profile.party_protect then
        for _, name in ipairs(defense) do
            if pstart_rdm_cast_buff(name,
                {'Protect V', 'Protect IV', 'Protect III', 'Protect II', 'Protect'},
                'Protect', 1800)
            then
                return true
            end
        end
    end
    if not profile.lean then
        -- Richer profiles retain individual party defenses. Sustained profiles
        -- omit this twelve-cast rotation to preserve MP.
        for _, name in ipairs(defense) do
            if pstart_rdm_cast_buff(name,
                {'Protect V', 'Protect IV', 'Protect III', 'Protect II', 'Protect'},
                'Protect', 1800)
            then
                return true
            end
        end
        for _, name in ipairs(defense) do
            if pstart_rdm_cast_buff(name,
                {'Shell V', 'Shell IV', 'Shell III', 'Shell II', 'Shell'},
                'Shell', 1800)
            then
                return true
            end
        end
    end
    return false
end

local function pstart_rdm_cast_self_buffs(profile)
    local routine_floor = profile.routine_buff_mp_floor or 0
    local self_buffs = {}
    local gain_spell = pstart_rdm_spell(profile.gain.spells)
    if gain_spell then
        local gain_buff = profile.gain.buffs
            and profile.gain.buffs[gain_spell.en]
            or profile.gain.buff
        self_buffs[#self_buffs + 1] = {
            spells=profile.gain.spells,
            buff=gain_buff,
        }
    end
    if not profile.lean then
        self_buffs[#self_buffs + 1] =
            {spells={'Aquaveil'}, buff='Aquaveil'}
        self_buffs[#self_buffs + 1] =
            {spells={'Phalanx'}, buff='Phalanx'}
        if not profile.reraise then
            self_buffs[#self_buffs + 1] =
                {spells={'Reraise'}, buff='Reraise'}
        end
    end
    for _, task in ipairs(self_buffs) do
        if not buffactive[task.buff]
            and pstart_rdm_cast_buff(
                player.name, task.spells, task.buff, 0, routine_floor)
        then
            return true
        end
    end

    if profile.temper and player.status == 'Engaged'
        and not buffactive['Multi Strikes']
        and pstart_rdm_cast_buff(
            player.name, {'Temper II', 'Temper'}, 'Multi Strikes', 0,
            routine_floor)
    then
        return true
    end
    return false
end

local function pstart_rdm_cast_reraise(profile)
    if not profile.reraise or buffactive['Reraise'] then return false end
    return pstart_rdm_cast_buff(
        player.name, {'Reraise'}, 'Reraise', 0,
        profile.routine_buff_mp_floor or 0)
end

local function pstart_rdm_cast_composure()
    if buffactive['Composure'] or midaction() or moving
        or silent_check_disable()
    then
        return false
    end
    local ability = res.job_abilities:with('en', 'Composure')
    local recasts = windower.ffxi.get_ability_recasts() or {}
    if ability and (recasts[ability.recast_id] or 0) < latency then
        windower.chat.input('/ja "Composure" <me>')
        tickdelay = os.clock() + 2
        return true
    end
    return false
end

local function pstart_rdm_enemy()
    local leader = pstart_rdm.leader
        and windower.ffxi.get_mob_by_name(pstart_rdm.leader)
        or nil
    if not leader or not leader.target_index or leader.target_index == 0 then
        return nil, leader
    end
    local target = windower.ffxi.get_mob_by_index(leader.target_index)
    if not target or target.spawn_type ~= 16 or not target.valid_target
        or not target.hpp or target.hpp <= 0
    then
        return nil, leader
    end
    return target, leader
end

local function pstart_rdm_target_allowed(target, names)
    if not names or #names == 0 then return true end
    if not target or type(target.name) ~= 'string' then return false end
    for _, name in ipairs(names) do
        if target.name:lower() == name:lower() then return true end
    end
    return false
end

local function pstart_rdm_cast_dispel(profile)
    local policy = profile.dispel
    if not policy then return false end

    local target, leader = pstart_rdm_enemy()
    if not target or not leader
        or not pstart_rdm_target_allowed(target, policy.target_names)
    then
        return false
    end
    local queue = pstart_rdm.dispel_targets[target.id]
    if not queue then return false end
    queue.entries = queue.entries or {}
    local now = os.clock()
    for index = #queue.entries, 1, -1 do
        if (queue.entries[index].expires or 0) <= now then
            table.remove(queue.entries, index)
        end
    end
    local entry = queue.entries[1]
    if not entry then
        pstart_rdm.dispel_targets[target.id] = nil
        return false
    end

    local local_target = windower.ffxi.get_mob_by_target('t')
    if not local_target or local_target.id ~= target.id then return false end
    if player.mpp < (policy.mp_floor or 0)
        or target.hpp < (policy.min_target_hpp or 0)
    then
        return false
    end

    local spell = pstart_rdm_spell({'Dispel'})
    if spell and pstart_rdm_can_spend(spell, policy.mp_floor)
        and pstart_rdm_ready(spell)
    then
        -- Consume the observation when issuing the command, not aftercast.
        -- This guarantees one command attempt per observed move even if the
        -- cast is interrupted or the client never produces an aftercast.
        table.remove(queue.entries, 1)
        if #queue.entries == 0 then
            pstart_rdm.dispel_targets[target.id] = nil
        end
        pstart_rdm.pending = {
            kind = 'dispel',
            spell_id = spell.id,
            target_id = target.id,
            entry = entry,
            move = entry.move,
            target_name = target.name,
        }
        pstart_rdm.dispel_count = pstart_rdm.dispel_count + 1
        pstart_rdm.last_dispel = (entry.move or 'buff')
            ..' -> '..(target.name or 'target')
        windower.chat.input('/ma "'..spell.en..'" <t>')
        tickdelay = os.clock() + 3
        return true
    end
    return false
end

local function pstart_rdm_cast_opener(profile)
    local opener = profile.opener
    if not opener then return false end
    local target = pstart_rdm_enemy()
    if not target or not pstart_rdm_target_allowed(
        target, opener.target_names)
    then
        return false
    end
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not local_target or local_target.id ~= target.id then return false end

    local progress = pstart_rdm.opener_targets[target.id]
    if not progress then
        progress = {stage=1, complete=false}
        pstart_rdm.opener_targets[target.id] = progress
    end
    if progress.complete then return false end

    while progress.stage <= #(opener.abilities or {}) do
        local ability_name = opener.abilities[progress.stage]
        local ability = res.job_abilities:with('en', ability_name)
        if not pstart_rdm_known_ability(ability)
            or buffactive[ability_name]
        then
            progress.stage = progress.stage + 1
        else
            local recasts = windower.ffxi.get_ability_recasts() or {}
            if (recasts[ability.recast_id] or 999) >= latency then
                -- Do not hold the critical Silence waiting for a long JA
                -- recast. Use every opener ability that is ready now, then
                -- proceed with the best available enfeebling set.
                progress.stage = progress.stage + 1
            elseif midaction() or moving or silent_check_disable()
                or silent_check_amnesia()
                or (tickdelay and os.clock() < tickdelay)
            then
                return false
            else
                pstart_rdm.pending = {
                    kind = 'opener',
                    action_id = ability.id,
                    target_id = target.id,
                    next_stage = progress.stage + 1,
                }
                windower.chat.input('/ja "'..ability.en..'" <me>')
                tickdelay = os.clock() + 2
                return true
            end
        end
    end
    progress.complete = true
    return false
end

local function pstart_rdm_cast_debuff(profile)
    local target, leader = pstart_rdm_enemy()
    if not target or not leader then
        return false
    end
    -- PartyCombat owns target synchronization. Use FFXI's valid <t> token
    -- only after this client is looking at the same mob as the leader; a raw
    -- numeric server ID is not a valid /ma target argument.
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not local_target or local_target.id ~= target.id then
        return false
    end
    if player.mpp < (profile.debuff_mp_floor or 0)
        or target.hpp < (profile.debuff_min_target_hpp or 0)
    then
        return false
    end

    for _, task in ipairs(profile.debuffs or {}) do
        if pstart_rdm_target_allowed(target, task.target_names) then
            local spell = pstart_rdm_spell(task.spells)
            if spell then
                local key = tostring(target.id)..':'..tostring(spell.id)
                if (pstart_rdm.debuff_timers[key] or 0) <= os.clock() then
                    if pstart_rdm_ready(spell) then
                        pstart_rdm.pending = {
                            kind = 'debuff',
                            spell_id = spell.id,
                            target_id = target.id,
                            key = key,
                            duration = task.duration,
                            confirm_result = task.confirm_result == true,
                        }
                        if task.confirm_result then
                            pstart_rdm.debuff_attempts[key] = {
                                spell_id = spell.id,
                                spell_name = spell.en,
                                target_id = target.id,
                                target_name = target.name,
                                duration = task.duration,
                                expires = os.clock() + 10,
                            }
                        end
                        windower.chat.input('/ma "'..spell.en..'" <t>')
                        tickdelay = os.clock() + 3
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function pstart_rdm_action()
    if not pstart_rdm.active then
        return false
    end
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    if not profile then
        return false
    end
    if pstart_rdm_cast_composure() then return true end
    if pstart_rdm_emergency_heal() then return true end
    if pstart_rdm_convert_recovery() then return true end
    if pstart_rdm_convert() then return true end
    if pstart_rdm_cast_opener(profile) then return true end
    if profile.priority_debuff and pstart_rdm_cast_debuff(profile) then
        return true
    end
    if pstart_rdm_cast_reraise(profile) then return true end
    if pstart_rdm_cast_reactive_repair() then return true end
    if pstart_rdm_cast_dispel(profile) then return true end
    if pstart_rdm_cast_party_buffs() then return true end
    if pstart_rdm_cast_self_buffs(profile) then return true end
    if not profile.priority_debuff then
        return pstart_rdm_cast_debuff(profile)
    end
    return false
end

local pstart_rdm_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartrdm' then
        if pstart_rdm_original_self_command then
            return pstart_rdm_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'tick' then
        pstart_rdm_action()
        return
    elseif not requested or requested == 'status' then
        local target = pstart_rdm_enemy()
        local target_text = target
            and (target.name..' @ '
                ..('%.1f'):format((target.distance or 0):sqrt())..'y')
            or 'none'
        add_to_chat(122, ('PartyStart RDM: %s / profile %s / leader %s / target %s')
            :format(
                pstart_rdm.active and 'On' or 'Off',
                tostring(pstart_rdm.profile or 'none'),
                tostring(pstart_rdm.leader or 'none'),
                target_text))
        add_to_chat(122,
            ('PartyStart RDM reactive buff repairs: %d / last %s')
            :format(pstart_rdm.remote_loss_count,
                tostring(pstart_rdm.last_remote_loss)))
        local profile = pstart_rdm_profiles[pstart_rdm.profile] or {}
        add_to_chat(122,
            ('PartyStart RDM MP %d%% / targets H:%d R:%d P:%d D:%d / '
                ..'reserve %d%% / Shell %s / backup cure <%d%%')
            :format(player.mpp or 0, #pstart_rdm.haste,
                #pstart_rdm.refresh, #pstart_rdm.phalanx,
                #pstart_rdm.defense,
                profile.routine_buff_mp_floor or 0,
                profile.party_shell and 'On' or 'Off',
                profile.heal_hpp or (profile.sustained and 25 or 0)))
        add_to_chat(122,
            ('PartyStart RDM bounded Dispels: %d / last %s')
            :format(pstart_rdm.dispel_count,
                tostring(pstart_rdm.last_dispel)))
        return
    elseif requested == 'off' then
        pstart_rdm.active = false
        pstart_rdm.pending = nil
        pstart_rdm.debuff_attempts = {}
        pstart_rdm.convert_recovery_until = 0
        pstart_rdm.last_loss_events = {}
        pstart_rdm.reactive_repairs = {}
        pstart_rdm.opener_targets = {}
        pstart_rdm.last_heal_at = 0
        pstart_rdm.dispel_targets = {}
        pstart_rdm.dispel_count = 0
        pstart_rdm.last_dispel = 'none'
        state.AutoBuffMode:set('Off')
        add_to_chat(122, 'PartyStart RDM buff and debuff maintenance is Off.')
        return
    end

    if pstart_rdm_profiles[requested]
        and pstart_rdm_valid_name(commandArgs[3])
    then
        pstart_rdm.active = true
        pstart_rdm.profile = requested
        pstart_rdm.leader = commandArgs[3]
        pstart_rdm.haste = pstart_rdm_names(commandArgs[4])
        pstart_rdm.refresh = pstart_rdm_names(commandArgs[5])
        pstart_rdm.phalanx = pstart_rdm_names(commandArgs[6])
        pstart_rdm.defense = pstart_rdm_names(commandArgs[7])
        pstart_rdm.pending = nil
        pstart_rdm.debuff_timers = {}
        pstart_rdm.debuff_attempts = {}
        pstart_rdm.convert_recovery_until = 0
        pstart_rdm.remote_loss_count = 0
        pstart_rdm.last_remote_loss = 'none'
        pstart_rdm.last_loss_events = {}
        pstart_rdm.reactive_repairs = {}
        pstart_rdm.opener_targets = {}
        pstart_rdm.last_heal_at = 0
        pstart_rdm.dispel_targets = {}
        pstart_rdm.dispel_count = 0
        pstart_rdm.last_dispel = 'none'
        state.AutoBuffMode:set('Off')
        tickdelay = 0
        add_to_chat(122, ('PartyStart RDM: %s / leader %s / GearSwap owns magic.')
            :format(requested, pstart_rdm.leader))
        pstart_rdm_action()
    else
        add_to_chat(123,
            'PartyStart RDM usage: gs c pstartrdm '
            ..'<profile|status|off> <leader> <haste> <refresh> <phalanx> '
            ..'[defense]')
    end
end

local pstart_rdm_original_user_job_tick = user_job_tick
function user_job_tick()
    if pstart_rdm_action() then
        return true
    end
    if pstart_rdm_original_user_job_tick then
        return pstart_rdm_original_user_job_tick()
    end
    return false
end

local pstart_rdm_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_rdm.pending
    local completed_opener = pending and pending.kind == 'opener' and spell
        and (spell.id == pending.action_id
            or spell.recast_id == pending.action_id)
    if completed_opener then
        if not spell.interrupted then
            local progress = pstart_rdm.opener_targets[pending.target_id]
            if progress then progress.stage = pending.next_stage end
        end
        pstart_rdm.pending = nil
    elseif pending and pending.kind == 'dispel'
        and spell and spell.id == pending.spell_id
    then
        pstart_rdm.pending = nil
    elseif pending and spell and spell.id == pending.spell_id then
        local retry = spell.interrupted and 3 or pending.duration
        if pending.kind == 'buff' then
            pstart_rdm.buff_timers[pending.key] = os.clock() + retry
            if pending.repair_key and not spell.interrupted then
                pstart_rdm.reactive_repairs[pending.repair_key] = nil
            end
        else
            if pending.confirm_result and not spell.interrupted then
                local attempt = pstart_rdm.debuff_attempts[pending.key]
                if attempt and attempt.outcome == 'landed' then
                    retry = pending.duration
                elseif attempt and attempt.outcome == 'covered' then
                    retry = PSTART_RDM_DEBUFF_COVERED_RECHECK
                else
                    -- Use a short provisional timer until the authoritative
                    -- action result confirms success or failure. The raw
                    -- action callback may run immediately before or after
                    -- GearSwap's aftercast callback; either order is safe.
                    retry = PSTART_RDM_DEBUFF_RETRY
                end
            end
            pstart_rdm.debuff_timers[pending.key] = os.clock() + retry
            if pending.confirm_result and spell.interrupted then
                pstart_rdm.debuff_attempts[pending.key] = nil
            end
        end
        pstart_rdm.pending = nil
    end
    if pstart_rdm_original_job_aftercast then
        return pstart_rdm_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
