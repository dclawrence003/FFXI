-- PartyStart RDM controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
-- Selindrile's shared include credits Motenten's base files. No upstream
-- GearSwap source is redistributed in this controller.
-- Load at the end of a participating character's RDM gear file:
--     include('Common/PartyStart_RDM.lua')

local pstart_rdm_profiles = {
    master = {
        gain = {spells={'Gain-STR'}, buff='STR Boost'},
        temper = true,
        lean = true,
        debuff_mp_floor = 100,
        debuff_min_target_hpp = 100,
        debuffs = {},
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
}

local pstart_rdm = {
    active = false,
    profile = nil,
    leader = nil,
    haste = {},
    refresh = {},
    phalanx = {},
    buff_timers = {},
    debuff_timers = {},
    pending = nil,
    convert_recovery_until = 0,
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

local function pstart_rdm_cast_buff(name, choices, buff, duration)
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

    if pstart_rdm_ready(spell) then
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
    if pstart_rdm.profile ~= 'master'
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
    if pstart_rdm.profile ~= 'master' then
        return false
    end

    local target_name, target_token, target_hpp
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and member.name
            and type(member.hpp) == 'number'
            and member.hpp > 0 and member.hpp < 50
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
        add_to_chat(122, ('PartyStart RDM: emergency %s -> %s (%d%%).')
            :format(spell.en, target_name, target_hpp))
        return true
    end
    return false
end

local function pstart_rdm_self_first(names)
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
    local refresh = pstart_rdm_self_first(pstart_rdm.refresh)
    local defense = pstart_rdm_union_names(
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
            name, {'Haste II', 'Haste'}, 'Haste', 165)
        then
            return true
        end
    end
    for _, name in ipairs(pstart_rdm.phalanx) do
        if pstart_rdm_cast_buff(
            name, {'Phalanx II'}, 'Phalanx', 165)
        then
            return true
        end
    end
    if not pstart_rdm_profiles[pstart_rdm.profile].lean then
        -- Richer profiles retain individual party defenses. The sustained
        -- master profile omits this twelve-cast rotation to preserve MP.
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
    local self_buffs = {
        {spells=profile.gain.spells, buff=profile.gain.buff},
    }
    if not profile.lean then
        self_buffs[#self_buffs + 1] =
            {spells={'Aquaveil'}, buff='Aquaveil'}
        self_buffs[#self_buffs + 1] =
            {spells={'Phalanx'}, buff='Phalanx'}
        self_buffs[#self_buffs + 1] =
            {spells={'Reraise'}, buff='Reraise'}
    end
    for _, task in ipairs(self_buffs) do
        if not buffactive[task.buff]
            and pstart_rdm_cast_buff(
                player.name, task.spells, task.buff, 0)
        then
            return true
        end
    end

    if profile.temper and player.status == 'Engaged'
        and not buffactive['Multi Strikes']
        and pstart_rdm_cast_buff(
            player.name, {'Temper II', 'Temper'}, 'Multi Strikes', 0)
    then
        return true
    end
    return false
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

local function pstart_rdm_cast_debuff(profile)
    local target, leader = pstart_rdm_enemy()
    if not target or not leader then
        return false
    end
    if player.mpp < (profile.debuff_mp_floor or 0)
        or target.hpp < (profile.debuff_min_target_hpp or 0)
    then
        return false
    end

    for _, task in ipairs(profile.debuffs) do
        local spell = pstart_rdm_spell(task.spells)
        if spell then
            local key = tostring(target.id)..':'..tostring(spell.id)
            if (pstart_rdm.debuff_timers[key] or 0) <= os.clock() then
                if pstart_rdm_ready(spell) then
                    pstart_rdm.pending = {
                        kind = 'debuff',
                        spell_id = spell.id,
                        key = key,
                        duration = task.duration,
                    }
                    -- Cast by mob ID. Acquiring the leader's target with
                    -- /assist can interact with legacy attack-assist modes and
                    -- is unnecessary for magical support.
                    windower.chat.input(
                        '/ma "'..spell.en..'" '..tostring(target.id))
                    tickdelay = os.clock() + 3
                    return true
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
    if pstart_rdm_cast_party_buffs() then return true end
    if pstart_rdm_cast_self_buffs(profile) then return true end
    return pstart_rdm_cast_debuff(profile)
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
        return
    elseif requested == 'off' then
        pstart_rdm.active = false
        pstart_rdm.pending = nil
        pstart_rdm.convert_recovery_until = 0
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
        pstart_rdm.pending = nil
        pstart_rdm.convert_recovery_until = 0
        state.AutoBuffMode:set('Off')
        tickdelay = 0
        add_to_chat(122, ('PartyStart RDM: %s / leader %s / GearSwap owns magic.')
            :format(requested, pstart_rdm.leader))
        pstart_rdm_action()
    else
        add_to_chat(123,
            'PartyStart RDM usage: gs c pstartrdm '
            ..'<profile|status|off> <leader> <haste> <refresh> <phalanx>')
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
    if pending and spell and spell.id == pending.spell_id then
        local retry = spell.interrupted and 3 or pending.duration
        if pending.kind == 'buff' then
            pstart_rdm.buff_timers[pending.key] = os.clock() + retry
        else
            pstart_rdm.debuff_timers[pending.key] = os.clock() + retry
        end
        pstart_rdm.pending = nil
    end
    if pstart_rdm_original_job_aftercast then
        return pstart_rdm_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
