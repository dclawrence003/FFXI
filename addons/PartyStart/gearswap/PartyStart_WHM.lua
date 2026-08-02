-- PartyStart WHM controller for Selindrile-style GearSwap files.
-- Load at the end of a participating character's WHM gear file:
--     include('Common/PartyStart_WHM.lua')

local pstart_whm = {
    active = false,
    opening = {
        protect = false,
        shell = false,
    },
    pending = nil,
}

local function pstart_whm_spell(choices)
    local learned = windower.ffxi.get_spells() or {}
    for _, name in ipairs(choices) do
        local spell = res.spells:with('en', name)
        if spell and learned[spell.id] then
            return spell
        end
    end
    return nil
end

local function pstart_whm_cast_spell(choices, buff, opening_key)
    local opening_required = opening_key and pstart_whm.opening[opening_key]
    if (buffactive[buff] and not opening_required) or midaction() or moving
        or silent_check_disable() or (tickdelay and os.clock() < tickdelay)
    then
        return false
    end
    local spell = pstart_whm_spell(choices)
    local recasts = windower.ffxi.get_spell_recasts() or {}
    if spell and (recasts[spell.id] or 0) < spell_latency
        and player.mp >= spell.mp_cost and silent_can_use(spell.id)
    then
        pstart_whm.pending = {
            spell_id = spell.id,
            opening_key = opening_key,
        }
        windower.chat.input('/ma "'..spell.en..'" <me>')
        tickdelay = os.clock() + 3
        return true
    end
    return false
end

local function pstart_whm_cast_solace()
    if buffactive['Afflatus Solace'] or midaction() or moving
        or silent_check_disable() or (tickdelay and os.clock() < tickdelay)
    then
        return false
    end
    local ability = res.job_abilities:with('en', 'Afflatus Solace')
    local recasts = windower.ffxi.get_ability_recasts() or {}
    if ability and (recasts[ability.recast_id] or 0) < latency then
        windower.chat.input('/ja "Afflatus Solace" <me>')
        tickdelay = os.clock() + 2
        return true
    end
    return false
end

local function pstart_whm_action()
    if not pstart_whm.active then return false end
    if pstart_whm_cast_solace() then return true end
    if pstart_whm_cast_spell(
        {'Protectra V', 'Protectra IV'}, 'Protect', 'protect')
    then
        return true
    end
    if pstart_whm_cast_spell(
        {'Shellra V', 'Shellra IV'}, 'Shell', 'shell')
    then
        return true
    end
    if pstart_whm_cast_spell({'Auspice'}, 'Auspice') then return true end
    if pstart_whm_cast_spell({'Aquaveil'}, 'Aquaveil') then return true end
    if pstart_whm_cast_spell(
        {'Reraise IV', 'Reraise III', 'Reraise II', 'Reraise'}, 'Reraise')
    then
        return true
    end
    return false
end

local function pstart_whm_status()
    local blockers = {}
    if not pstart_whm.active then blockers[#blockers + 1] = 'controller Off' end
    if midaction() then blockers[#blockers + 1] = 'midaction' end
    if moving then blockers[#blockers + 1] = 'moving' end
    if silent_check_disable() then blockers[#blockers + 1] = 'incapacitated' end
    if tickdelay and os.clock() < tickdelay then
        blockers[#blockers + 1] =
            ('delay %.1fs'):format(tickdelay - os.clock())
    end

    local next_action = 'maintenance complete'
    local spell
    if not buffactive['Afflatus Solace'] then
        next_action = 'Afflatus Solace'
    elseif pstart_whm.opening.protect or not buffactive['Protect'] then
        spell = pstart_whm_spell({'Protectra V', 'Protectra IV'})
        next_action = spell and spell.en or 'Protectra unavailable'
    elseif pstart_whm.opening.shell or not buffactive['Shell'] then
        spell = pstart_whm_spell({'Shellra V', 'Shellra IV'})
        next_action = spell and spell.en or 'Shellra unavailable'
    elseif not buffactive['Auspice'] then
        spell = pstart_whm_spell({'Auspice'})
        next_action = spell and spell.en or 'Auspice unavailable'
    elseif not buffactive['Aquaveil'] then
        spell = pstart_whm_spell({'Aquaveil'})
        next_action = spell and spell.en or 'Aquaveil unavailable'
    elseif not buffactive['Reraise'] then
        spell = pstart_whm_spell(
            {'Reraise IV', 'Reraise III', 'Reraise II', 'Reraise'})
        next_action = spell and spell.en or 'Reraise unavailable'
    end

    if spell then
        local recasts = windower.ffxi.get_spell_recasts() or {}
        local recast = recasts[spell.id] or 0
        if recast >= spell_latency then
            blockers[#blockers + 1] = ('recast %.1fs'):format(recast)
        end
        if player.mp < spell.mp_cost then
            blockers[#blockers + 1] =
                ('MP %d/%d'):format(player.mp, spell.mp_cost)
        end
        if not silent_can_use(spell.id) then
            blockers[#blockers + 1] = 'no current spell access'
        end
    end

    add_to_chat(122, ('PartyStart WHM: %s / next %s / %s')
        :format(
            pstart_whm.active and 'On' or 'Off',
            next_action,
            #blockers == 0 and 'ready' or table.concat(blockers, ', ')))
end

local pstart_whm_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartwhm' then
        if pstart_whm_original_self_command then
            return pstart_whm_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'tick' then
        pstart_whm_action()
    elseif not requested or requested == 'status' then
        pstart_whm_status()
    elseif requested == 'off' then
        pstart_whm.active = false
        pstart_whm.pending = nil
        state.AutoBuffMode:set('Off')
        add_to_chat(122, 'PartyStart WHM routine buff maintenance is Off.')
    elseif requested == 'on' then
        pstart_whm.active = true
        -- Always establish party-wide defenses once at startup. Checking only
        -- Smalls' own Protect/Shell could incorrectly skip the AoE cast when
        -- another source had already protected her.
        pstart_whm.opening.protect = true
        pstart_whm.opening.shell = true
        pstart_whm.pending = nil
        state.AutoBuffMode:set('Off')
        tickdelay = 0
        add_to_chat(122,
            'PartyStart WHM: GearSwap owns routine buffs; HealBot owns healing.')
        pstart_whm_action()
    else
        add_to_chat(123,
            'PartyStart WHM usage: gs c pstartwhm <on|status|off>')
    end
end

local pstart_whm_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_whm.pending
    if pending and spell and spell.id == pending.spell_id then
        if not spell.interrupted and pending.opening_key then
            pstart_whm.opening[pending.opening_key] = false
        end
        pstart_whm.pending = nil
    end

    if pstart_whm_original_job_aftercast then
        return pstart_whm_original_job_aftercast(spell, spellMap, eventArgs)
    end
end

local pstart_whm_original_user_job_tick = user_job_tick
function user_job_tick()
    if pstart_whm_action() then
        return true
    end
    if pstart_whm_original_user_job_tick then
        return pstart_whm_original_user_job_tick()
    end
    return false
end
