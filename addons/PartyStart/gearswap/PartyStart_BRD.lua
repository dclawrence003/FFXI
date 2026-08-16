-- PartyStart BRD controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
-- Selindrile's shared include credits Motenten's base files. No upstream
-- GearSwap source is redistributed in this controller.
--
-- Load this after the character's BRD gear file:
--     include('Common/PartyStart_BRD.lua')
--
-- PartyStart drives it with:
--     gs c pstartbrd <master|apexbats|locusbats|apexcrabs|limbus|physical|accuracy|magic|safe|ambuscade-v1|ambuscade-v2> <leader>
--     gs c pstartbrd sleep
--     gs c pstartbrd off

local pstart_brd_packets = require('packets')

local pstart_brd_profiles = {
    master = {
        song_mode = 'Sustain',
        songs = {
            {spell='Victory March', buff='march'},
            {spell="Mage's Ballad III", buff='ballad'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    apexbats = {
        song_mode = 'Sustain',
        songs = {
            {spell='Victory March', buff='march'},
            {spell="Mage's Ballad III", buff='ballad'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        party_buffs = {
            {spell='Barwatera', buff='Barwater'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    locusbats = {
        song_mode = 'Sustain',
        songs = {
            {spell='Victory March', buff='march'},
            {spell="Mage's Ballad III", buff='ballad'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        -- Ultrasonics is Ice-aligned AoE Evasion Down. This inexpensive,
        -- long-duration ward reduces status landings without sacrificing the
        -- Ballad needed for an unattended camp.
        party_buffs = {
            {spell='Barblizzara', buff='Barblizzard'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    apexcrabs = {
        song_mode = 'Sustain',
        songs = {
            {spell='Victory March', buff='march'},
            {spell="Mage's Ballad III", buff='ballad'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        party_buffs = {
            {spell='Barwatera', buff='Barwater'},
        },
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    limbus = {
        song_mode = 'Melee',
        songs = {
            {spell='Victory March', buff='march'},
            {spell='Valor Minuet V', buff='minuet'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        debuff_min_target_hpp = 45,
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    physical = {
        song_mode = 'Melee',
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
        song_mode = 'Melee',
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
        song_mode = 'Mage',
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
        song_mode = 'Tank',
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
    ['ambuscade-v1'] = {
        song_mode = 'Melee',
        self_heal_hpp = 85,
        self_buffs = {
            {spell='Reraise', buff='Reraise'},
        },
        songs = {
            {spell='Victory March', buff='march'},
            {spell='Valor Minuet V', buff='minuet'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        party_buffs = {
            {spell='Barsilencera', buff='Barsilence'},
        },
        default_bar = {spell='Barstonra', buff='Barstone'},
        warble_reactions = true,
        auto_urchin_sleep = true,
        debuff_target_names = {'Bozzetto Breadwinner'},
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
    ['ambuscade-v2'] = {
        song_mode = 'Melee',
        self_buffs = {
            {spell='Reraise', buff='Reraise'},
        },
        songs = {
            {spell='Victory March', buff='march'},
            {spell='Valor Minuet V', buff='minuet'},
            {spell='Blade Madrigal', buff='madrigal'},
        },
        party_buffs = {
            {spell='Barstonra', buff='Barstone'},
            {spell='Barsleepra', buff='Barsleep'},
        },
        debuff_target_names = {'Popular Penelope'},
        debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
    },
}

local pstart_brd = {
    active = false,
    profile = nil,
    leader = nil,
    pending = nil,
    debuff_timers = {},
    sleep_requested_until = 0,
    warble = nil,
    urchin_sleep_requested_until = 0,
    urchin_sleep_not_before = 0,
    urchin_sleep_issued_at = 0,
    last_warble_complete_key = nil,
    last_warble_complete_at = 0,
}

local PSTART_BRD_DEBUFF_RETRY = 90
local PSTART_BRD_SLEEP_WINDOW = 8
local PSTART_BRD_WARBLE_WINDOW = 4.25
local PSTART_BRD_URCHIN_SLEEP_WINDOW = 15
local PSTART_BRD_URCHIN_APPEAR_DELAY = 0.15
local PSTART_BRD_HORDE_MAX_RADIUS = 8
local PSTART_BRD_REISSUE_DELAY = 1.25
local PSTART_BRD_SLEEP_CHOICES = {
    'Horde Lullaby II', 'Horde Lullaby', 'Foe Lullaby II', 'Foe Lullaby',
}
local PSTART_BRD_URCHIN_SLEEP_CHOICES = {
    'Horde Lullaby II', 'Horde Lullaby',
}
local PSTART_BRD_WARBLE_REACTIONS = {
    ['Fire Meeble Warble'] = {spell='Barfira', buff='Barfire'},
    ['Blizzard Meeble Warble'] = {spell='Barblizzara', buff='Barblizzard'},
    ['Aero Meeble Warble'] = {spell='Baraera', buff='Baraero'},
    ['Stone Meeble Warble'] = {spell='Barstonra', buff='Barstone'},
    ['Thunder Meeble Warble'] = {spell='Barthundra', buff='Barthunder'},
    ['Water Meeble Warble'] = {spell='Barwatera', buff='Barwater'},
}

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

local PSTART_BRD_EQUIPPABLE_BAGS = {
    'Inventory',
    'Wardrobe',
    'Wardrobe2',
    'Wardrobe3',
    'Wardrobe4',
    'Wardrobe5',
    'Wardrobe6',
    'Wardrobe7',
    'Wardrobe8',
}

-- Use Windower's raw bag data instead of Sel-Utility's name-keyed
-- item_available(). The latter can return false for an item that FindAll and
-- GearSwap can both see, which silently reduces the controller to two songs.
local function pstart_brd_instrument_bag(instrument)
    if type(instrument) ~= 'string' then
        return nil
    end

    local item = res.items:with('en', instrument)
    if not item then
        return nil
    end

    for _, bag_name in ipairs(PSTART_BRD_EQUIPPABLE_BAGS) do
        local bag = windower.ffxi.get_items(bag_name)
        if bag and bag.enabled then
            for _, slot in ipairs(bag) do
                if slot.id == item.id and (slot.count or 0) > 0 then
                    return bag_name
                end
            end
        end
    end
    return nil
end

local function pstart_brd_spent_job_points()
    local current = windower.ffxi.get_player()
    local brd = current
        and current.job_points
        and current.job_points.brd
        or nil
    return brd and (tonumber(brd.jp_spent) or 0) or 0
end

local function pstart_brd_extra_instrument()
    local extra = tonumber(info.ExtraSongs) or 0
    local instrument = info.ExtraSongInstrument
    if extra <= 0 or type(instrument) ~= 'string' then
        return nil, 'not configured'
    end

    local bag_name = pstart_brd_instrument_bag(instrument)
    if not bag_name then
        return nil, 'not in an equip-accessible bag'
    end

    local minimum_jp = tonumber(info.ExtraSongMinimumJobPoints) or 0
    local spent_jp = pstart_brd_spent_job_points()
    if spent_jp < minimum_jp then
        return nil, ('requires %d BRD JP; currently %d')
            :format(minimum_jp, spent_jp)
    end

    return instrument, bag_name
end

local function pstart_brd_report_instrument()
    local configured = info.ExtraSongInstrument
    local instrument, detail = pstart_brd_extra_instrument()
    if instrument then
        local song_count = 2 + math.max(0, tonumber(info.ExtraSongs) or 0)
        add_to_chat(122, ('PartyStart BRD: %d-song mode enabled; %s found in %s.')
            :format(song_count, instrument, detail))
    elseif type(configured) == 'string' then
        add_to_chat(123, ('PartyStart BRD: 2-song mode; cannot use %s (%s).')
            :format(configured, tostring(detail)))
    else
        add_to_chat(123, 'PartyStart BRD: 2-song mode; no extra-song instrument configured.')
    end
end

local function pstart_brd_ready(spell)
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

-- Warble has only a four-second ready window on Difficult/Very Difficult.
-- Ignore Selendrile's routine tick delay for encounter reactions while still
-- respecting real casting blockers and spell recasts.
local function pstart_brd_reaction_ready(spell)
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return spell
        and not pstart_brd.pending
        and not midaction()
        and not moving
        and not silent_check_disable()
        and (recasts[spell.id] or 0) < spell_latency
        and player
        and (player.mp or 0) >= (spell.mp_cost or 0)
        and silent_can_use(spell.id)
end

local function pstart_brd_reset_reactions()
    pstart_brd.warble = nil
    pstart_brd.urchin_sleep_requested_until = 0
    pstart_brd.urchin_sleep_not_before = 0
    pstart_brd.urchin_sleep_issued_at = 0
    pstart_brd.last_warble_complete_key = nil
    pstart_brd.last_warble_complete_at = 0
end

local function pstart_brd_cast_self_heal(profile)
    local threshold = tonumber(profile and profile.self_heal_hpp)
    local hpp = tonumber(player and player.hpp)
    if not threshold or not hpp or hpp <= 0 or hpp >= threshold then
        return false
    end

    -- Earthshaker's selected target always takes 1,000 damage and can be
    -- outside every other healer's cast range. Retry a learned self-Cure as
    -- the isolated BRD's last-resort backstop; potent Paralyze may interrupt
    -- an attempt, so the normal maintenance heartbeat deliberately retries.
    local choices = hpp < 65
        and {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
        or {'Cure III', 'Cure IV', 'Cure II', 'Cure'}
    for _, name in ipairs(choices) do
        local spell = pstart_brd_spell(name)
        if spell and pstart_brd_ready(spell) then
            pstart_brd.pending = {
                kind = 'self_heal',
                spell_id = spell.id,
            }
            windower.chat.input('/ma "'..spell.en..'" <me>')
            tickdelay = os.clock() + 3
            add_to_chat(158, ('PartyStart BRD: emergency %s at %d%% HP.')
                :format(spell.en, hpp))
            return true
        end
    end
    return false
end

local function pstart_brd_target()
    local leader = pstart_brd.leader
        and windower.ffxi.get_mob_by_name(pstart_brd.leader)
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

local function pstart_brd_target_allowed(target, names)
    if not names or #names == 0 then return true end
    if not target or type(target.name) ~= 'string' then return false end
    for _, name in ipairs(names) do
        if target.name:lower() == name:lower() then return true end
    end
    return false
end

local function pstart_brd_live_enemy(target)
    return target
        and target.spawn_type == 16
        and target.valid_target
        and tonumber(target.hpp)
        and target.hpp > 0
end

local function pstart_brd_lullaby_target_allowed(target)
    return pstart_brd_live_enemy(target)
        and (target.name == 'Bozzetto Breadwinner'
            or target.name == 'Bozzetto Urchin')
end

local function pstart_brd_visible_urchins()
    local found = {}
    for _, mob in pairs(windower.ffxi.get_mob_array() or {}) do
        if pstart_brd_live_enemy(mob)
            and mob.name == 'Bozzetto Urchin'
        then
            found[#found + 1] = mob
        end
    end
    table.sort(found, function(left, right)
        local left_distance = tonumber(left.distance) or math.huge
        local right_distance = tonumber(right.distance) or math.huge
        if left_distance == right_distance then
            return (tonumber(left.id) or math.huge)
                < (tonumber(right.id) or math.huge)
        end
        return left_distance < right_distance
    end)
    return found
end

-- PartyCombat uses this same incoming target packet for observer clients. It
-- changes the selected target without engaging, moving, or turning Barney.
local function pstart_brd_set_observer_target(target)
    local current = windower.ffxi.get_player()
    if not current or not current.id or not current.index
        or not target or not target.id
    then
        return false
    end
    pstart_brd_packets.inject(pstart_brd_packets.new('incoming', 0x058, {
        ['Player'] = current.id,
        ['Target'] = target.id,
        ['Player Index'] = current.index,
    }))
    return true
end

local function pstart_brd_sleep_target(urchins)
    local battle_target = windower.ffxi.get_mob_by_target('bt')
    if pstart_brd_lullaby_target_allowed(battle_target) then
        return '<bt>', battle_target, nil
    end

    local selected_target = windower.ffxi.get_mob_by_target('t')
    if pstart_brd_lullaby_target_allowed(selected_target) then
        return '<t>', selected_target, nil
    end

    local urchin = urchins and urchins[1] or nil
    if not urchin then return nil end
    local restore_target_id = selected_target and selected_target.id or nil
    if not pstart_brd_set_observer_target(urchin) then return nil end
    return '<t>', urchin, restore_target_id
end

local function pstart_brd_restore_sleep_target(pending)
    if not pending or not pending.restore_target_id then return end
    local selected_target = windower.ffxi.get_mob_by_target('t')
    if not selected_target or selected_target.id ~= pending.target_id then
        return
    end
    local restore_target = windower.ffxi.get_mob_by_id(
        pending.restore_target_id)
    if restore_target then
        pstart_brd_set_observer_target(restore_target)
    end
end

local function pstart_brd_cast_warble_bar()
    local request = pstart_brd.warble
    if not pstart_brd.active or pstart_brd.profile ~= 'ambuscade-v1'
        or not request
    then
        return false
    end

    local now = os.clock()
    if now > request.deadline then
        pstart_brd.warble = nil
        add_to_chat(123, ('PartyStart BRD: %s reaction window expired before %s landed.')
            :format(request.ability, request.spell))
        return false
    end
    if request.satisfied or buffactive[request.buff] then
        request.satisfied = true
        return false
    end
    if request.issued_at and request.issued_at > 0 then
        if now - request.issued_at < PSTART_BRD_REISSUE_DELAY
            or (pstart_brd.pending
                and pstart_brd.pending.kind == 'warble_bar')
        then
            return true
        end
        request.issued_at = 0
    end

    local spell = pstart_brd_spell(request.spell)
    if not spell then
        pstart_brd.warble = nil
        add_to_chat(123, ('PartyStart BRD: cannot react to %s; %s is not learned.')
            :format(request.ability, request.spell))
        return false
    end
    -- A queued but temporarily blocked reaction owns the casting slot; routine
    -- songs and maintenance must not consume the remainder of the ready window.
    if not pstart_brd_reaction_ready(spell) then return true end

    request.issued_at = now
    pstart_brd.pending = {
        kind = 'warble_bar',
        spell_id = spell.id,
        ability = request.ability,
    }
    windower.chat.input('/ma "'..spell.en..'" <me>')
    tickdelay = now + 0.75
    add_to_chat(158, ('PartyStart BRD: %s -> %s now.')
        :format(request.ability, spell.en))
    return true
end

local function pstart_brd_cast_urchin_sleep()
    local profile = pstart_brd_profiles[pstart_brd.profile]
    local deadline = tonumber(pstart_brd.urchin_sleep_requested_until) or 0
    if not pstart_brd.active or pstart_brd.profile ~= 'ambuscade-v1'
        or not profile or not profile.auto_urchin_sleep or deadline <= 0
    then
        return false
    end

    local now = os.clock()
    if now > deadline then
        pstart_brd.urchin_sleep_requested_until = 0
        pstart_brd.urchin_sleep_not_before = 0
        pstart_brd.urchin_sleep_issued_at = 0
        return false
    end
    if now < (pstart_brd.urchin_sleep_not_before or 0) then
        return true
    end

    local urchins = pstart_brd_visible_urchins()
    if #urchins == 0 then return false end
    local closest_distance = math.sqrt(math.max(0,
        tonumber(urchins[1].distance) or math.huge))
    -- Horde Lullaby's AoE is centered on Barney, not on the selected mob. Even
    -- the maximum String-skill radius is eight yalms, so wait for Barney to
    -- return from Housemaker rather than spending the one-shot cast out of range.
    if closest_distance > PSTART_BRD_HORDE_MAX_RADIUS then return false end

    local spell = pstart_brd_first_spell(PSTART_BRD_URCHIN_SLEEP_CHOICES)
    if not spell then
        pstart_brd.urchin_sleep_requested_until = 0
        add_to_chat(123,
            'PartyStart BRD: no learned Horde Lullaby is available; Urchin sleep cancelled.')
        return false
    end
    if pstart_brd.urchin_sleep_issued_at > 0 then
        if now - pstart_brd.urchin_sleep_issued_at < PSTART_BRD_REISSUE_DELAY
            or (pstart_brd.pending
                and pstart_brd.pending.kind == 'urchin_sleep')
        then
            return true
        end
        pstart_brd.urchin_sleep_issued_at = 0
    end
    if not pstart_brd_reaction_ready(spell) then return true end

    local target_token, target, restore_target_id =
        pstart_brd_sleep_target(urchins)
    if not target_token or not target then return true end

    pstart_brd.urchin_sleep_issued_at = now
    pstart_brd.pending = {
        kind = 'urchin_sleep',
        spell_id = spell.id,
        target_id = target.id,
        restore_target_id = restore_target_id,
    }
    windower.chat.input('/ma "'..spell.en..'" '..target_token)
    tickdelay = now + 3
    add_to_chat(158, ('PartyStart BRD: %s -> %s; %d visible Urchin%s targeted for sleep.')
        :format(spell.en, target.name, #urchins, #urchins == 1 and '' or 's'))
    return true
end

local function pstart_brd_warble_from_action(action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = res.monster_abilities[result.param]
                if ability and PSTART_BRD_WARBLE_REACTIONS[ability.en] then
                    return ability, 'ready'
                end
            end
        end
        return nil
    end
    if action.category == 6 or action.category == 11 then
        local ability = res.monster_abilities[action.param]
        if ability and PSTART_BRD_WARBLE_REACTIONS[ability.en] then
            return ability, 'complete'
        end
    end
    return nil
end

local function pstart_brd_handle_warble(action)
    local profile = pstart_brd_profiles[pstart_brd.profile]
    if not pstart_brd.active or pstart_brd.profile ~= 'ambuscade-v1'
        or not profile or not profile.warble_reactions
    then
        return
    end

    local ability, phase = pstart_brd_warble_from_action(action)
    local actor = ability and windower.ffxi.get_mob_by_id(action.actor_id)
        or nil
    if not actor or actor.name ~= 'Bozzetto Breadwinner' then return end

    local now = os.clock()
    local reaction = PSTART_BRD_WARBLE_REACTIONS[ability.en]
    if phase == 'ready' then
        pstart_brd.warble = {
            ability = ability.en,
            spell = reaction.spell,
            buff = reaction.buff,
            deadline = now + PSTART_BRD_WARBLE_WINDOW,
            issued_at = 0,
            satisfied = false,
        }
        -- Wake Selendrile's heartbeat immediately if another action currently
        -- prevents the direct packet-path attempt.
        tickdelay = 0
        pstart_brd_cast_warble_bar()
        return
    end

    local completion_key = tostring(action.actor_id)..':'..ability.en
    if pstart_brd.last_warble_complete_key == completion_key
        and now - (pstart_brd.last_warble_complete_at or 0) < 1.5
    then
        return
    end
    pstart_brd.last_warble_complete_key = completion_key
    pstart_brd.last_warble_complete_at = now
    pstart_brd.warble = nil
    if profile.auto_urchin_sleep then
        pstart_brd.urchin_sleep_requested_until =
            now + PSTART_BRD_URCHIN_SLEEP_WINDOW
        pstart_brd.urchin_sleep_not_before =
            now + PSTART_BRD_URCHIN_APPEAR_DELAY
        pstart_brd.urchin_sleep_issued_at = 0
    end
    tickdelay = 0
    pstart_brd_cast_urchin_sleep()
end

windower.raw_register_event('action', pstart_brd_handle_warble)

-- A Limbus sleep request is a single deliberate cast, not a maintained
-- debuff. It uses the synchronized active target while Horde Lullaby's actual
-- area is centered on Barney. The short queue lets the request survive a song
-- already in flight without creating an autonomous sleep loop.
local function pstart_brd_cast_sleep()
    local deadline = tonumber(pstart_brd.sleep_requested_until) or 0
    if not pstart_brd.active or pstart_brd.profile ~= 'limbus'
        or deadline <= 0
    then
        return false
    end

    local now = os.clock()
    if now > deadline then
        pstart_brd.sleep_requested_until = 0
        add_to_chat(123,
            'PartyStart BRD: pack-sleep request expired before target/recast was ready.')
        return false
    end

    local target, leader = pstart_brd_target()
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not target or not leader or not local_target
        or local_target.id ~= target.id
    then
        return false
    end

    local spell = pstart_brd_first_spell(PSTART_BRD_SLEEP_CHOICES)
    if not spell then
        pstart_brd.sleep_requested_until = 0
        add_to_chat(123,
            'PartyStart BRD: no learned Lullaby spell is available; request cancelled.')
        return false
    end
    if not pstart_brd_ready(spell) then return false end

    pstart_brd.pending = {
        kind = 'sleep',
        spell_id = spell.id,
        target_id = target.id,
    }
    windower.chat.input('/ma "'..spell.en..'" <t>')
    tickdelay = os.clock() + 3
    add_to_chat(158, ('PartyStart BRD: %s -> %s; linked pack sleep attempted.')
        :format(spell.en, target.name))
    return true
end

local function pstart_brd_cast_buff_tasks(tasks)
    for _, task in ipairs(tasks or {}) do
        local spell = pstart_brd_spell(task.spell)
        if spell and not buffactive[task.buff] and pstart_brd_ready(spell) then
            pstart_brd.pending = {
                kind = 'party_buff',
                spell_id = spell.id,
            }
            windower.chat.input('/ma "'..spell.en..'" <me>')
            tickdelay = os.clock() + 3
            return true
        end
    end
    return false
end

local function pstart_brd_cast_self_buff(profile)
    return pstart_brd_cast_buff_tasks(profile.self_buffs)
end

local function pstart_brd_cast_party_buff(profile)
    return pstart_brd_cast_buff_tasks(profile.party_buffs)
end

local function pstart_brd_cast_default_bar(profile)
    if not profile or not profile.default_bar then return false end
    return pstart_brd_cast_buff_tasks({profile.default_bar})
end

local function pstart_brd_timer_key(target, spell)
    return tostring(target.id)..':'..tostring(spell.id)
end

local function pstart_brd_cast_debuff(profile)
    local target, leader = pstart_brd_target()
    if not target or not leader then
        return false
    end
    if not pstart_brd_target_allowed(target, profile.debuff_target_names) then
        return false
    end
    if target.hpp < (profile.debuff_min_target_hpp or 0) then
        return false
    end
    -- PartyCombat owns target synchronization. A server mob ID is not a
    -- valid text-command target, so cast only once local <t> matches the
    -- leader's mob.
    local local_target = windower.ffxi.get_mob_by_target('t')
    if not local_target or local_target.id ~= target.id then
        return false
    end

    local now = os.clock()
    for _, choices in ipairs(profile.debuffs or {}) do
        local spell = pstart_brd_first_spell(choices)
        if spell then
            local key = pstart_brd_timer_key(target, spell)
            if (pstart_brd.debuff_timers[key] or 0) <= now then
                if pstart_brd_ready(spell) then
                    pstart_brd.pending = {
                        kind = 'debuff',
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

local function pstart_brd_maintenance(profile)
    if pstart_brd_cast_warble_bar() then return true end
    if pstart_brd_cast_urchin_sleep() then return true end
    if pstart_brd_cast_self_heal(profile) then return true end
    if pstart_brd_cast_sleep() then return true end
    if pstart_brd_cast_self_buff(profile) then return true end
    if pstart_brd_cast_party_buff(profile) then return true end
    if pstart_brd_cast_default_bar(profile) then return true end
    return pstart_brd_cast_debuff(profile)
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
    if requested == 'tick' then
        local profile = pstart_brd_profiles[pstart_brd.profile]
        if pstart_brd.active and profile then
            -- Barney's character GearSwap remains the sole party-song owner.
            -- This heartbeat owns only encounter barspells and hostile songs.
            pstart_brd_maintenance(profile)
        end
        return
    elseif requested == 'sleep' then
        if not pstart_brd.active or pstart_brd.profile ~= 'limbus' then
            add_to_chat(123,
                'PartyStart BRD: pack sleep requires the active Limbus profile.')
        else
            pstart_brd.sleep_requested_until =
                os.clock() + PSTART_BRD_SLEEP_WINDOW
            add_to_chat(122,
                'PartyStart BRD: one pack sleep queued for the synchronized target.')
            pstart_brd_cast_sleep()
        end
        return
    elseif not requested then
        local target = pstart_brd_target()
        local target_text = target
            and (target.name..' @ '
                ..('%.1f'):format((target.distance or 0):sqrt())..'y')
            or 'none'
        add_to_chat(122, ('PartyStart BRD: %s / profile %s / leader %s')
            :format(
                pstart_brd.active and 'On' or 'Off',
                tostring(pstart_brd.profile or 'none'),
                tostring(pstart_brd.leader or 'none')))
        add_to_chat(122, 'PartyStart BRD debuff target: '..target_text)
        local profile = pstart_brd_profiles[pstart_brd.profile] or {}
        add_to_chat(122, ('PartyStart BRD encounter self-buffs: %d')
            :format(#(profile.self_buffs or {})))
        add_to_chat(122, ('PartyStart BRD encounter barspells: %d')
            :format(#(profile.party_buffs or {})
                + (profile.default_bar and 1 or 0)))
        add_to_chat(122, ('PartyStart BRD emergency self-Cure: %s')
            :format(profile.self_heal_hpp
                and ('below '..profile.self_heal_hpp..'% HP') or 'Off'))
        add_to_chat(122, ('PartyStart BRD Limbus pack sleep: %s')
            :format((pstart_brd.sleep_requested_until or 0) > os.clock()
                and 'Queued' or (pstart_brd.profile == 'limbus'
                    and 'Ready on request' or 'Off')))
        add_to_chat(122, ('PartyStart BRD V1 Warble Barspells: %s')
            :format(profile.warble_reactions and 'Armed' or 'Off'))
        add_to_chat(122, ('PartyStart BRD V1 Urchin Lullaby: %s')
            :format((pstart_brd.urchin_sleep_requested_until or 0) > os.clock()
                and 'Scanning/Queued' or (profile.auto_urchin_sleep
                    and 'Armed' or 'Off')))
        pstart_brd_report_instrument()
        return
    end

    if requested == 'off' then
        pstart_brd.active = false
        pstart_brd.pending = nil
        pstart_brd.sleep_requested_until = 0
        pstart_brd_reset_reactions()
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
        pstart_brd.sleep_requested_until = 0
        pstart_brd_reset_reactions()
        state.SongMode:set(pstart_brd_profiles[requested].song_mode)
        state.AutoSongMode:set(true)
        tickdelay = 0
        add_to_chat(122, ('PartyStart BRD: %s / leader %s / native GearSwap owns songs.')
            :format(requested, pstart_brd.leader))
        pstart_brd_report_instrument()
        add_to_chat(122,
            'PartyStart BRD: debuffs armed; party songs delegated to character GearSwap.')
    else
        add_to_chat(123,
            'PartyStart BRD usage: gs c pstartbrd '
            ..'<master|apexbats|locusbats|apexcrabs|limbus|physical|accuracy|magic|safe|ambuscade-v1|'
            ..'ambuscade-v2|off> <leader>; or gs c pstartbrd sleep')
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
    -- Encounter Reraise must be established before the multi-song startup
    -- rotation. It is a one-time self buff, so this does not interfere with
    -- the character GearSwap's continuing ownership of party songs.
    if pstart_brd_cast_warble_bar() then return true end
    if pstart_brd_cast_urchin_sleep() then return true end
    if pstart_brd_cast_self_heal(profile) then return true end
    if pstart_brd_cast_sleep() then return true end
    if pstart_brd_cast_self_buff(profile) then return true end
    if pstart_brd_original_check_song
        and pstart_brd_original_check_song()
    then
        return true
    end
    return pstart_brd_maintenance(profile)
end

local pstart_brd_original_job_aftercast = job_aftercast
function job_aftercast(spell, spellMap, eventArgs)
    local pending = pstart_brd.pending
    if pending and spell and spell.id == pending.spell_id then
        if pending.kind == 'debuff' then
            if spell.interrupted then
                pstart_brd.debuff_timers[pending.key] = os.clock() + 3
            else
                pstart_brd.debuff_timers[pending.key]
                    = os.clock() + PSTART_BRD_DEBUFF_RETRY
            end
        elseif pending.kind == 'sleep' then
            if spell.interrupted then
                pstart_brd.sleep_requested_until = math.max(
                    pstart_brd.sleep_requested_until or 0,
                    os.clock() + 4)
                add_to_chat(123,
                    'PartyStart BRD: Lullaby interrupted; short retry remains queued.')
            else
                pstart_brd.sleep_requested_until = 0
            end
        elseif pending.kind == 'warble_bar' then
            local request = pstart_brd.warble
            if request and request.ability == pending.ability then
                if spell.interrupted then
                    request.issued_at = 0
                    tickdelay = 0
                    add_to_chat(123, ('PartyStart BRD: %s interrupted; retrying inside the Warble window.')
                        :format(request.spell))
                else
                    request.satisfied = true
                end
            end
        elseif pending.kind == 'urchin_sleep' then
            pstart_brd_restore_sleep_target(pending)
            if spell.interrupted then
                pstart_brd.urchin_sleep_issued_at = 0
                tickdelay = 0
                add_to_chat(123,
                    'PartyStart BRD: Urchin Lullaby interrupted; retry remains queued inside the original scan window.')
            else
                pstart_brd.urchin_sleep_requested_until = 0
                pstart_brd.urchin_sleep_not_before = 0
                pstart_brd.urchin_sleep_issued_at = 0
            end
        end
        pstart_brd.pending = nil
    end

    if pstart_brd_original_job_aftercast then
        pstart_brd_original_job_aftercast(spell, spellMap, eventArgs)
    end
end
