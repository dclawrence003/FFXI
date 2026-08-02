-- PartyStart BRD controller for Selindrile-style GearSwap files.
--
-- Load this after the character's BRD gear file:
--     include('Common/PartyStart_BRD.lua')
--
-- PartyStart drives it with:
--     gs c pstartbrd <physical|accuracy|magic|safe> <leader>
--     gs c pstartbrd off

local pstart_brd_profiles = {
    physical = {
        songs = {
            {spell='Victory March', buff='march'},
            {spell='Valor Minuet V', buff='minuet'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    accuracy = {
        songs = {
            {spell='Victory March', buff='march'},
            {spell='Blade Madrigal', buff='madrigal'},
            {spell='Valor Minuet V', buff='minuet'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    magic = {
        songs = {
            {spell="Mage's Ballad III", buff='ballad'},
            {spell='Victory March', buff='march'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
            {'Pining Nocturne'},
        },
    },
    safe = {
        songs = {
            {spell='Victory March', buff='march'},
            {spell="Sentinel's Scherzo", buff='scherzo'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
            {'Pining Nocturne'},
        },
    },
}

local pstart_brd = {
    active = false,
    profile = nil,
    leader = nil,
    pending = nil,
    debuff_timers = {},
}

local PSTART_BRD_DEBUFF_RETRY = 90

local function pstart_brd_valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function pstart_brd_spell(name)
    local spell = res.spells:with('en', name)
    local learned = windower.ffxi.get_spells() or {}
    if spell and learned[spell.id] then
        return spell
    end
    return nil
end

local function pstart_brd_first_spell(choices)
    for _, name in ipairs(choices) do
        local spell = pstart_brd_spell(name)
        if spell then
            return spell
        end
    end
    return nil
end

local function pstart_brd_song_limit(profile)
    local extra = tonumber(info.ExtraSongs) or 0
    return math.min(#profile.songs, 2 + math.max(0, extra))
end

local function pstart_brd_ready(spell)
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return spell
        and not midaction()
        and not moving
        and not silent_check_disable()
        and (recasts[spell.id] or 0) < spell_latency
        and player.mp >= spell.mp_cost
        and silent_can_use(spell.id)
end

local function pstart_brd_target()
    local leader = pstart_brd.leader
        and windower.ffxi.get_mob_by_name(pstart_brd.leader)
        or nil
    if not leader or not leader.target_index or leader.target_index == 0 then
        return nil, leader
    end

    local target = windower.ffxi.get_mob_by_index(leader.target_index)
    if not target or not target.valid_target or not target.hpp or target.hpp <= 0 then
        return nil, leader
    end
    return target, leader
end

local function pstart_brd_timer_key(target, spell)
    return tostring(target.id)..':'..tostring(spell.id)
end

local function pstart_brd_cast_party_song(profile)
    local limit = pstart_brd_song_limit(profile)
    for index = 1, limit do
        local song = profile.songs[index]
        if not buffactive[song.buff] then
            local spell = pstart_brd_spell(song.spell)
            if pstart_brd_ready(spell) then
                if index > 2 and state.ExtraSongsMode then
                    state.ExtraSongsMode:set('FullLength')
                end
                windower.chat.input('/ma "'..spell.en..'" <me>')
                tickdelay = os.clock() + 3
                return true
            end
        end
    end
    return false
end

local function pstart_brd_cast_debuff(profile)
    local target, leader = pstart_brd_target()
    if not target or not leader then
        return false
    end

    local now = os.clock()
    for _, choices in ipairs(profile.debuffs) do
        local spell = pstart_brd_first_spell(choices)
        if spell then
            local key = pstart_brd_timer_key(target, spell)
            if (pstart_brd.debuff_timers[key] or 0) <= now then
                local me = windower.ffxi.get_player()
                if not me or me.target_index ~= leader.target_index then
                    windower.chat.input('/assist '..pstart_brd.leader)
                    tickdelay = os.clock() + 1.3
                    return true
                end

                if pstart_brd_ready(spell) then
                    pstart_brd.pending = {
                        spell_id = spell.id,
                        target_id = target.id,
                        key = key,
                    }
                    windower.chat.input('/ma "'..spell.en..'" <t>')
                    tickdelay = os.clock() + 3
                    return true
                end
            end
        end
    end
    return false
end

local pstart_brd_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartbrd' then
        if pstart_brd_original_self_command then
            return pstart_brd_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if not requested then
        add_to_chat(122, ('PartyStart BRD: %s / profile %s / leader %s')
            :format(
                pstart_brd.active and 'On' or 'Off',
                tostring(pstart_brd.profile or 'none'),
                tostring(pstart_brd.leader or 'none')))
        return
    end

    if requested == 'off' then
        pstart_brd.active = false
        pstart_brd.pending = nil
        state.AutoSongMode:set(false)
        add_to_chat(122, 'PartyStart BRD song and debuff maintenance is Off.')
    elseif pstart_brd_profiles[requested]
        and pstart_brd_valid_name(commandArgs[3])
    then
        pstart_brd.active = true
        pstart_brd.profile = requested
        pstart_brd.leader = commandArgs[3]
        pstart_brd.pending = nil
        pstart_brd.debuff_timers = {}
        state.AutoSongMode:set(true)
        tickdelay = 0
        add_to_chat(122, ('PartyStart BRD: %s / leader %s / GearSwap owns songs.')
            :format(requested, pstart_brd.leader))
    else
        add_to_chat(123,
            'PartyStart BRD usage: gs c pstartbrd '
            ..'<physical|accuracy|magic|safe|off> <leader>')
    end

    if state.DisplayMode and state.DisplayMode.value then
        update_job_states()
    end
end

local pstart_brd_original_check_song = check_song
function check_song()
    if not pstart_brd.active then
        if pstart_brd_original_check_song then
            return pstart_brd_original_check_song()
        end
        return false
    end

    local profile = pstart_brd_profiles[pstart_brd.profile]
    if not profile or not state.AutoSongMode.value then
        return false
    end
    if pstart_brd_cast_party_song(profile) then
        return true
    end
    return pstart_brd_cast_debuff(profile)
end

local pstart_brd_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_brd.pending
    if pending and spell and spell.id == pending.spell_id then
        if spell.interrupted then
            pstart_brd.debuff_timers[pending.key] = os.clock() + 3
        else
            pstart_brd.debuff_timers[pending.key]
                = os.clock() + PSTART_BRD_DEBUFF_RETRY
        end
        pstart_brd.pending = nil
    end

    if pstart_brd_original_job_aftercast then
        return pstart_brd_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
