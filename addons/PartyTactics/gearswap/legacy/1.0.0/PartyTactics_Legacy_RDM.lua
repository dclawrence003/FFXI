-- PartyStart RDM controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
-- Selindrile's shared include credits Motenten's base files. No upstream
-- GearSwap source is redistributed in this controller.
-- Load at the end of a participating character's RDM gear file:
--     include('Common/PartyStart_RDM.lua')

local PSTART_RDM_HELPER_VERSION = '1.0.0'

local function pstart_rdm_prove_helper(generation, epoch_text, version)
    local epoch = type(epoch_text) == 'string'
        and epoch_text:match('^%d+$') and tonumber(epoch_text) or nil
    if version ~= PSTART_RDM_HELPER_VERSION
        or type(generation) ~= 'string' or #generation > 64
        or generation:match('^%d+%-%d+%-%d+$') == nil
        or not epoch or epoch < 0 or epoch ~= math.floor(epoch)
    then return false end
    windower.send_command(('pt __legacy_helper_ready %s RDM %s %d')
        :format(PSTART_RDM_HELPER_VERSION, generation, epoch))
    return true
end

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
    locusbats = {
        sustained = true,
        -- King Ranperre's Tomb Locus Dire Bats have a 1264 accuracy target.
        -- Distract is therefore the first bounded offensive cast, while the
        -- usual MP floors keep it from threatening the overnight reserve.
        -- Blood Drain is single-target, so a six-target Shell pass costs more
        -- than it prevents in this stationary PLD-led camp.
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
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=150},
        },
    },
    sortieacuex = {
        sustained = true,
        -- Smalls must melee for Red Lotus Blade and then land two Fire bursts.
        -- Keep only the high-value lane, and explicitly preserve Aquaveil
        -- without enabling the rest of the expensive non-lean self carousel.
        gain = {
            spells={'Gain-MND', 'Gain-INT'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-INT']='INT Boost'},
        },
        temper = true,
        lean = true,
        aquaveil = true,
        reraise = true,
        party_shell = false,
        party_protect = false,
        routine_buff_mp_floor = 30,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 100,
        debuff_min_target_hpp = 100,
        convert_mpp = 30,
        heal_hpp = 30,
        heal_mp_floor = 25,
        debuffs = {},
    },
    sortiemelee = {
        sustained = true,
        -- Ground-floor boss baseline: retain only buffs that materially help
        -- this party, keep one cheap defense-down lane, and Convert before the
        -- support rotation collapses. Profile transitions preserve timers.
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        aquaveil = true,
        reraise = true,
        party_shell = false,
        party_protect = false,
        routine_buff_mp_floor = 35,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 45,
        debuff_min_target_hpp = 65,
        convert_mpp = 30,
        heal_hpp = 30,
        heal_mp_floor = 25,
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
    limbus = {
        -- Mixed-family Limbus floors reward broad, low-overhead support. Keep
        -- every physical contributor hasted, establish long Shell once, and
        -- spend offensive casting time only on cheap defense-down.
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        party_shell = true,
        party_protect = false,
        routine_buff_mp_floor = 30,
        tank_buff_mp_floor = 15,
        debuff_mp_floor = 35,
        debuff_min_target_hpp = 45,
        healing = true,
        heal_hpp = 50,
        heal_mp_floor = 25,
        pull_silence = {
            -- Identify the current claimed enemy by ID and observed casting,
            -- never by name: Limbus can give different jobs the same name.
            stall_distance=6, stall_seconds=5, progress_distance=0.5,
            max_range=20.9, mp_floor=20, max_attempts=3,
            retry_delay=3, result_timeout=8, unresolved_seconds=30,
        },
        debuffs = {
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=45},
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
    fishfly = {
        -- The encounter is decided by Dolo's synchronized AoE, not by a long
        -- one-target enfeeble rotation. Establish the short critical path in
        -- encounter order: AoE Shell, Dolo, tank, RDM, then remaining mages.
        gain = {spells={'Gain-MND'}, buff='MND Boost'},
        temper = false,
        lean = true,
        reraise = false,
        party_shell = true,
        party_shellra = true,
        party_protect = false,
        fast_magic_core = true,
        routine_buff_mp_floor = 20,
        tank_buff_mp_floor = 10,
        debuff_mp_floor = 100,
        debuff_min_target_hpp = 100,
        healing = true,
        heal_hpp = 90,
        heal_interval = 1.5,
        heal_mp_floor = 15,
        debuffs = {},
    },
    magicboss = {
        -- Reusable magic-damage boss support: establish the defensive/mage
        -- core, heal aggressively, and apply the broad bounded enfeeble set.
        -- No encounter names or mechanics live in this controller preset.
        gain = {spells={'Gain-MND'}, buff='MND Boost'},
        temper = false,
        lean = true,
        reraise = true,
        party_shell = true,
        party_protect = false,
        fast_magic_core = true,
        routine_buff_mp_floor = 20,
        tank_buff_mp_floor = 10,
        debuff_mp_floor = 20,
        debuff_min_target_hpp = 5,
        healing = true,
        heal_hpp = 85,
        heal_interval = 1.5,
        heal_mp_floor = 15,
        debuffs = {
            {spells={'Frazzle III', 'Frazzle II', 'Frazzle'}, duration=150},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=120},
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150},
            {spells={'Slow II', 'Slow'}, duration=150},
            {spells={'Paralyze II', 'Paralyze'}, duration=150},
            {spells={'Blind II', 'Blind'}, duration=150},
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
    ['locusbats-protect'] = {
        -- PartyTactics' isolated Locus policy.  The legacy locusbats preset
        -- intentionally remains unchanged so PartyStart and every previously
        -- reviewed profile keep their exact behavior.  Locus bats deal
        -- physical damage, so establish Protect before the longer Haste /
        -- Refresh rotation while continuing to omit wasteful Shell casts.
        sustained = true,
        gain = {
            spells={'Gain-MND', 'Gain-STR'},
            buff='MND Boost',
            buffs={['Gain-MND']='MND Boost', ['Gain-STR']='STR Boost'},
        },
        temper = true,
        lean = true,
        party_shell = false,
        party_protect = true,
        party_protect_first = true,
        routine_buff_mp_floor = 35,
        tank_buff_mp_floor = 20,
        debuff_mp_floor = 55,
        debuff_min_target_hpp = 65,
        debuffs = {
            {spells={'Distract III', 'Distract II', 'Distract'}, duration=150,
                confirm_result=true},
            {spells={'Dia III', 'Dia II', 'Dia'}, duration=150,
                confirm_result=true},
        },
    },
}

local function pstart_rdm_clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do
        result[pstart_rdm_clone(key)] = pstart_rdm_clone(child)
    end
    return result
end

local function pstart_rdm_protected_variant(source)
    local result = pstart_rdm_clone(pstart_rdm_profiles[source])
    result.party_protect = true
    result.party_protect_first = true
    return result
end

-- These names are isolated opt-ins. The legacy presets remain byte-for-byte
-- compatible for PartyStart users and for any profile that still selects them.
pstart_rdm_profiles['limbus-protect'] =
    pstart_rdm_protected_variant('limbus')
pstart_rdm_profiles['ambuscade-v1-protect'] =
    pstart_rdm_protected_variant('ambuscade-v1')
pstart_rdm_profiles['magicboss-protect'] =
    pstart_rdm_protected_variant('magicboss')

local pstart_rdm = {
    active = false,
    transitioning = false,
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
    opening_shellra = false,
    party_shellra_available = nil,
    dispel_targets = {},
    dispel_count = 0,
    last_dispel = 'none',
    pull_silence = nil,
    -- Populated only by an explicit typed `pstartrdm silence <id>` request.
    -- Keeping this outside every profile table makes the queue inert for all
    -- existing profiles until PartyTactics deliberately invokes it.
    priority_silence = nil,
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

-- Fishfly is a pre-buff-and-burst encounter.  The command leader must receive
-- Refresh/Haste first, the PLD must receive Phalanx before the counter volley,
-- and the RDM must establish its own Refresh before servicing the remaining
-- mages.  Other profiles retain their historical self-first ordering.
local function pstart_rdm_priority_order(names)
    local ordered = {}
    for _, name in ipairs(names or {}) do
        ordered[#ordered + 1] = name
    end

    if pstart_rdm.profile ~= 'fishfly' then
        for index, name in ipairs(ordered) do
            if name:lower() == player.name:lower() then
                table.remove(ordered, index)
                table.insert(ordered, 1, name)
                break
            end
        end
        return ordered
    end

    local function rank(name)
        if pstart_rdm.leader
            and name:lower() == pstart_rdm.leader:lower()
        then
            return 1
        elseif pstart_rdm_name_in(pstart_rdm.phalanx, name) then
            return 2
        elseif name:lower() == player.name:lower() then
            return 3
        end
        return 4
    end
    table.sort(ordered, function(left, right)
        local left_rank, right_rank = rank(left), rank(right)
        return left_rank == right_rank and left:lower() < right:lower()
            or left_rank < right_rank
    end)
    return ordered
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
local pstart_rdm_silence_event
local pstart_rdm_silence_loss
local pstart_rdm_priority_silence_event
windower.raw_register_event('action', function(action)
    if pstart_rdm_priority_silence_event then
        pstart_rdm_priority_silence_event(action)
    end
    if pstart_rdm_silence_event then pstart_rdm_silence_event(action) end
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
            if pstart_rdm_silence_loss then
                pstart_rdm_silence_loss(target.id, result.message, result.param)
            end
            pstart_rdm_register_remote_buff_loss(
                target.id, result.message, result.param)
        end
    end
end)

windower.raw_register_event('action message', function(
    actor_id, target_id, actor_index, target_index,
    message_id, param_1, param_2, param_3)
    if pstart_rdm_silence_loss then
        pstart_rdm_silence_loss(target_id, message_id, param_1)
    end
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
    local keys = {}
    for key in pairs(pstart_rdm.reactive_repairs) do
        keys[#keys + 1] = key
    end
    if pstart_rdm.profile == 'fishfly' then
        table.sort(keys, function(left, right)
            local left_task = pstart_rdm.reactive_repairs[left]
            local right_task = pstart_rdm.reactive_repairs[right]
            local ordered = pstart_rdm_priority_order{
                left_task.name, right_task.name,
            }
            if ordered[1]:lower() == ordered[2]:lower() then
                return left < right
            end
            return ordered[1]:lower() == left_task.name:lower()
        end)
    end
    for _, key in ipairs(keys) do
        local task = pstart_rdm.reactive_repairs[key]
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
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    local threshold = profile and tonumber(profile.convert_mpp) or 15
    if player.mpp >= threshold or player.hpp < 70 or not player.in_combat
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
    local heal_interval = profile and profile.heal_interval or 2.5
    if not profile
        or (not profile.sustained and not profile.healing)
        or os.clock() - (pstart_rdm.last_heal_at or 0) < heal_interval
    then
        return false
    end

    -- PLD owns routine healing in sustained profiles.  Fishfly deliberately
    -- promotes RDM to an aggressive second healer because ten synchronized
    -- magic counters can land faster than one Majesty recovery cycle.
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
        local command_delay = pstart_rdm.profile == 'fishfly'
            and math.min(3, heal_interval) or 3
        tickdelay = os.clock() + command_delay
        pstart_rdm.last_heal_at = os.clock()
        add_to_chat(122, ('PartyStart RDM: emergency %s -> %s (%d%%).')
            :format(spell.en, target_name, target_hpp))
        return true
    end
    return false
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

local function pstart_rdm_cast_opening_shellra(profile)
    if not profile.party_shellra or not pstart_rdm.opening_shellra then
        return false
    end

    local spell = pstart_rdm_spell{
        'Shellra V', 'Shellra IV', 'Shellra III', 'Shellra II', 'Shellra',
    }
    if not spell then
        pstart_rdm.opening_shellra = false
        pstart_rdm.party_shellra_available = false
        add_to_chat(123,
            'PartyStart RDM: no learned Shellra; falling back to individual Shell.')
        return false
    end
    pstart_rdm.party_shellra_available = true
    if not pstart_rdm_ready(spell) then return false end

    pstart_rdm.pending = {
        kind = 'buff',
        spell_id = spell.id,
        key = 'fishfly:shellra',
        duration = 1650,
        opening_shellra = true,
    }
    pstart_rdm.opening_shellra = false
    windower.chat.input('/ma "'..spell.en..'" <me>')
    tickdelay = os.clock() + 3
    add_to_chat(158, '[PartyStart RDM] Opening '..spell.en..' for the party.')
    return true
end

local function pstart_rdm_cast_party_protect(defense, mp_floor)
    for _, name in ipairs(defense) do
        if pstart_rdm_cast_buff(name,
            {'Protect V', 'Protect IV', 'Protect III', 'Protect II', 'Protect'},
            'Protect', 1800, mp_floor)
        then
            return true
        end
    end
    return false
end

local function pstart_rdm_cast_party_buffs()
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    local routine_floor = profile.routine_buff_mp_floor or 0
    local tank_floor = profile.tank_buff_mp_floor or routine_floor
    local defense = #pstart_rdm.defense > 0 and pstart_rdm.defense
        or pstart_rdm_union_names(
            pstart_rdm.haste, pstart_rdm.refresh, pstart_rdm.phalanx)

    if pstart_rdm_cast_opening_shellra(profile) then return true end
    if profile.party_protect_first
        and pstart_rdm_cast_party_protect(defense, routine_floor)
    then
        return true
    end

    if profile.fast_magic_core then
        local core = pstart_rdm_priority_order(pstart_rdm_union_names(
            pstart_rdm.refresh, pstart_rdm.haste, pstart_rdm.phalanx))
        for _, name in ipairs(core) do
            -- The tank's one unique defensive spell is front-loaded before its
            -- generic recovery buffs.  Everyone else receives Refresh before
            -- Haste so the pre-pull rotation immediately begins repaying MP.
            if pstart_rdm_name_in(pstart_rdm.phalanx, name)
                and pstart_rdm_cast_buff(
                    name, {'Phalanx II'}, 'Phalanx', 225, tank_floor)
            then
                return true
            end
            if pstart_rdm_name_in(pstart_rdm.refresh, name)
                and pstart_rdm_cast_buff(name,
                    {'Refresh III', 'Refresh II', 'Refresh'},
                    'Refresh', 135, routine_floor)
            then
                return true
            end
            if pstart_rdm_name_in(pstart_rdm.haste, name)
                and pstart_rdm_cast_buff(
                    name, {'Haste II', 'Haste'}, 'Haste', 165, routine_floor)
            then
                return true
            end
        end
    else
        -- General profiles retain their historical self-first Refresh pass.
        local refresh = pstart_rdm_priority_order(pstart_rdm.refresh)
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
    end
    if profile.party_shell then
        -- General-purpose profiles retain one long-duration Shell pass.
        -- Protect is kept separate so profiles can choose their defense cost.
        for _, name in ipairs(defense) do
            if profile.party_shellra
                and pstart_rdm.party_shellra_available ~= false
            then
                break
            end
            if pstart_rdm_cast_buff(name,
                {'Shell V', 'Shell IV', 'Shell III', 'Shell II', 'Shell'},
                'Shell', 1650)
            then
                return true
            end
        end
    end
    if profile.party_protect and not profile.party_protect_first
        and pstart_rdm_cast_party_protect(defense, routine_floor)
    then
        return true
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
    if not profile.lean or profile.aquaveil then
        self_buffs[#self_buffs + 1] =
            {spells={'Aquaveil'}, buff='Aquaveil'}
    end
    if not profile.lean then
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

-- This pull-support path is opt-in for Limbus only. It does not participate
-- in PartyCombat's engagement/movement policy or the ordinary debuff timers.
local PSTART_RDM_SILENCE_ID = 59
local PSTART_RDM_SILENCE_STATUS = 6
local PSTART_RDM_SILENCE_LANDED = {
    [236]=true, [237]=true, [267]=true, [268]=true,
    [269]=true, [270]=true, [271]=true, [272]=true,
}
local PSTART_RDM_PRIORITY_SILENCE_WINDOW = 30
local PSTART_RDM_PRIORITY_SILENCE_RANGE = 20.9
local PSTART_RDM_PRIORITY_SILENCE_RETRY = 2
local PSTART_RDM_PRIORITY_SILENCE_RESULT_TIMEOUT = 6
local PSTART_RDM_PRIORITY_SILENCE_MAX_ATTEMPTS = 3
local PSTART_RDM_PRIORITY_SILENCE_POLL = 0.1

local function pstart_rdm_party_claimed(target)
    local claim = tonumber(target.claim_id)
    if not claim or claim == 0 then return false end
    local current = windower.ffxi.get_player()
    if current and current.id == claim then return true end
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and member.mob
            and member.mob.id == claim
        then
            return true
        end
    end
    return false
end

local function pstart_rdm_uint32(value)
    if type(value) ~= 'string' or #value == 0 or #value > 10
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    if not number or number < 1 or number > 4294967295
        or number ~= math.floor(number)
    then
        return nil
    end
    return number
end

local function pstart_rdm_clear_priority_silence()
    pstart_rdm.priority_silence = nil
end

local function pstart_rdm_live_priority_target(target, request)
    return type(target) == 'table'
        and target.id == request.id
        and target.index == request.index
        and target.spawn_type == 16
        and target.valid_target
        and type(target.hpp) == 'number' and target.hpp > 0
end

local function pstart_rdm_priority_silence_context()
    local request = pstart_rdm.priority_silence
    if not request then return nil end
    local now = os.clock()
    if now > request.expires then
        add_to_chat(123, ('[PartyStart RDM] Queued Silence #%d expired: %s.')
            :format(request.id, request.last_blocker or request.last_result
                or 'no legal casting opportunity'))
        pstart_rdm_clear_priority_silence()
        return nil
    end

    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.zone ~= request.zone
        or player and ((tonumber(player.hpp) or 0) <= 0
            or player.status == 'Dead' or player.status == 'Engaged dead')
    then
        pstart_rdm_clear_priority_silence()
        return nil
    end

    local target = windower.ffxi.get_mob_by_id(request.id)
    -- A just-created entity can disappear for a frame. Preserve its exact ID
    -- until the bounded deadline, but never cast without a fresh live lookup.
    if not target then return request, nil end
    if not pstart_rdm_live_priority_target(target, request)
        or not pstart_rdm_party_claimed(target)
    then
        pstart_rdm_clear_priority_silence()
        return nil
    end
    return request, target
end

local function pstart_rdm_priority_silence_reserved()
    return pstart_rdm_priority_silence_context() ~= nil
end

local function pstart_rdm_priority_silence_blocker(spell, target)
    local now = os.clock()
    if midaction() then return 'another action is in progress' end
    if now < (tonumber(next_cast) or 0) then return 'current action recovery' end
    if moving then return 'Smalls is moving' end
    if silent_check_disable() then return 'Smalls is incapacitated' end
    if not target then return 'exact enemy is not currently visible' end
    if type(target.distance) ~= 'number' or target.distance < 0
        or math.sqrt(target.distance) > PSTART_RDM_PRIORITY_SILENCE_RANGE
    then
        return 'exact enemy is outside Silence range'
    end
    local recasts = windower.ffxi.get_spell_recasts() or {}
    if (recasts[spell.recast_id or spell.id] or 0) >= spell_latency then
        return spell.en..' is on recast'
    end
    if not player or (player.mp or 0) < (spell.mp_cost or 0) then
        return 'insufficient MP'
    end
    if not silent_can_use(spell.id) then return 'spell access/status' end
    return nil
end

local function pstart_rdm_cast_priority_silence()
    local request, target = pstart_rdm_priority_silence_context()
    if not request then return false end
    local now = os.clock()

    if request.inflight_until then
        if now < request.inflight_until then return true end
        request.inflight_until = nil
        request.last_result = 'no result received'
        request.next_attempt = now + PSTART_RDM_PRIORITY_SILENCE_RETRY
        if request.attempts >= PSTART_RDM_PRIORITY_SILENCE_MAX_ATTEMPTS then
            add_to_chat(123, ('[PartyStart RDM] Silence #%d stopped after '
                ..'%d unconfirmed attempt(s).')
                :format(request.id, request.attempts))
            pstart_rdm_clear_priority_silence()
            return false
        end
    end
    if now < (request.next_attempt or 0) then return true end

    local spell = pstart_rdm_spell({'Silence'})
    if not spell then
        add_to_chat(123,
            '[PartyStart RDM] Queued Silence cancelled: spell is not learned.')
        pstart_rdm_clear_priority_silence()
        return false
    end
    local blocker = pstart_rdm_priority_silence_blocker(spell, target)
    if blocker then
        request.last_blocker = blocker
        return true
    end

    request.attempts = request.attempts + 1
    request.inflight_until = now + PSTART_RDM_PRIORITY_SILENCE_RESULT_TIMEOUT
    request.dispatch_token_until = now + 1
    request.last_blocker = nil
    request.last_result = 'awaiting result'
    -- GearSwap consumes the numeric target through its normal outgoing-text
    -- resolver, then executes the character's ordinary pre/mid/aftercast sets.
    -- No target selection, equipment command, or packet injection occurs here.
    windower.chat.input('/ma "'..spell.en..'" '..tostring(request.id))
    tickdelay = now + 3
    add_to_chat(158, ('[PartyStart RDM] Silence #%d dispatched (%d/%d).')
        :format(request.id, request.attempts,
            PSTART_RDM_PRIORITY_SILENCE_MAX_ATTEMPTS))
    return true
end

pstart_rdm_priority_silence_event = function(action)
    local request = pstart_rdm.priority_silence
    if not request or type(action) ~= 'table' or action.category ~= 4
        or action.param ~= PSTART_RDM_SILENCE_ID
    then
        return
    end
    local current = windower.ffxi.get_player()
    local own_cast = current and action.actor_id == current.id
    for _, result_target in ipairs(action.targets or {}) do
        if result_target.id == request.id then
            for _, result in ipairs(result_target.actions or {}) do
                local landed = PSTART_RDM_SILENCE_LANDED[result.message]
                    and result.param == PSTART_RDM_SILENCE_STATUS
                if landed or (own_cast and result.message == 75) then
                    add_to_chat(158, ('[PartyStart RDM] Silence %s on #%d.')
                        :format(landed and 'confirmed' or 'already covered',
                            request.id))
                    pstart_rdm_clear_priority_silence()
                    return
                elseif own_cast then
                    request.inflight_until = nil
                    request.last_result = 'not confirmed (message '
                        ..tostring(result.message)..')'
                    if result.message == 655 or result.message == 656
                        or request.attempts
                            >= PSTART_RDM_PRIORITY_SILENCE_MAX_ATTEMPTS
                    then
                        add_to_chat(123, ('[PartyStart RDM] Silence #%d '
                            ..'stopped after %d attempt(s): %s.')
                            :format(request.id, request.attempts,
                                request.last_result))
                        pstart_rdm_clear_priority_silence()
                    else
                        request.next_attempt = os.clock()
                            + PSTART_RDM_PRIORITY_SILENCE_RETRY
                    end
                    return
                end
            end
        end
    end
end

local function pstart_rdm_reserve_priority_silence(value)
    local id = pstart_rdm_uint32(value)
    if not id then return false, 'target ID must be a uint32 integer' end
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    if not info or not info.logged_in or not target
        or target.id ~= id or type(target.index) ~= 'number'
        or target.spawn_type ~= 16 or not target.valid_target
        or type(target.hpp) ~= 'number' or target.hpp <= 0
        or not pstart_rdm_party_claimed(target)
    then
        return false, 'target must be a live party-claimed enemy'
    end

    local existing = pstart_rdm.priority_silence
    if existing and existing.id == id and existing.zone == info.zone then
        -- Button spam and repeated runtime ticks describe the same one action.
        -- They do not extend its deadline, reset its attempts, or enqueue more.
        return true, 'already queued'
    end
    if existing and existing.inflight_until then
        return false, 'another exact Silence is already in flight'
    end
    pstart_rdm.priority_silence = {
        id=id, index=target.index, zone=info.zone,
        expires=os.clock() + PSTART_RDM_PRIORITY_SILENCE_WINDOW,
        attempts=0, next_attempt=0, last_result='queued',
    }
    return true, 'queued'
end

-- Reserve every local automation entry point while this explicit request is
-- pending. The wrappers are dormant when no request exists, preserving every
-- established profile's prior scheduling and GearSwap hooks.
local pstart_rdm_original_pre_tick = pre_tick
function pre_tick()
    if pstart_rdm_cast_priority_silence() then return true end
    if pstart_rdm_original_pre_tick then
        return pstart_rdm_original_pre_tick()
    end
    return false
end

local function pstart_rdm_priority_silence_blocks_action(spell, phase)
    if not pstart_rdm_priority_silence_reserved() then return false end
    local request = pstart_rdm.priority_silence
    local name = spell and (spell.english or spell.en or spell.name)
    if spell and spell.action_type == 'Magic' and request
        and request.inflight_until and spell.id == PSTART_RDM_SILENCE_ID
    then
        local target_id = spell.target and tonumber(spell.target.id) or nil
        if target_id == request.id then return false end
        -- GearSwap may call pretarget before its numeric-ID resolver has
        -- populated (or replaced a stale) spell.target. This one-second local
        -- token is created immediately before our own outgoing command; at
        -- precast, use the exact resolved ID whenever it is available.
        if os.clock() <= (request.dispatch_token_until or 0)
            and (phase == 'pretarget' or target_id == nil)
        then
            return false
        end
    end
    -- Preserve the normal escape path if Silence itself prevents the request.
    if spell and spell.action_type == 'Item' and buffactive.silence
        and (name == 'Echo Drops' or name == 'Remedy' or name == 'Panacea')
    then
        return false
    end
    return true
end

local pstart_rdm_original_filter_pretarget = user_filter_pretarget
function user_filter_pretarget(spell, spellMap, eventArgs)
    if pstart_rdm_priority_silence_blocks_action(spell, 'pretarget') then
        eventArgs.cancel = true
        return
    end
    if pstart_rdm_original_filter_pretarget then
        return pstart_rdm_original_filter_pretarget(
            spell, spellMap, eventArgs)
    end
end

local pstart_rdm_original_filter_precast = user_filter_precast
function user_filter_precast(spell, spellMap, eventArgs)
    if pstart_rdm_priority_silence_blocks_action(spell, 'precast') then
        eventArgs.cancel = true
        return
    end
    if pstart_rdm_original_filter_precast then
        return pstart_rdm_original_filter_precast(
            spell, spellMap, eventArgs)
    end
end

local pstart_rdm_next_priority_silence_poll = 0
windower.raw_register_event('prerender', function()
    if not pstart_rdm_priority_silence_reserved() then return end
    local now = os.clock()
    if now < pstart_rdm_next_priority_silence_poll then return end
    pstart_rdm_next_priority_silence_poll =
        now + PSTART_RDM_PRIORITY_SILENCE_POLL
    pstart_rdm_cast_priority_silence()
end)
windower.raw_register_event('zone change', pstart_rdm_clear_priority_silence)
windower.raw_register_event('logout', pstart_rdm_clear_priority_silence)

local function pstart_rdm_pull_distance(target, leader)
    if not target or not leader
        or type(target.x) ~= 'number' or type(leader.x) ~= 'number'
        or type(target.y) ~= 'number' or type(leader.y) ~= 'number'
        or type(target.z) ~= 'number' or type(leader.z) ~= 'number'
    then return nil end
    local dx, dy, dz = target.x-leader.x, target.y-leader.y, target.z-leader.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function pstart_rdm_silence_context()
    local profile = pstart_rdm.active and pstart_rdm_profiles[pstart_rdm.profile]
    local policy = profile and profile.pull_silence
    if not policy then
        pstart_rdm.pull_silence = nil
        return nil
    end
    local info = windower.ffxi.get_info()
    local target, leader = pstart_rdm_enemy()
    if not info or not info.logged_in or not target or not leader
        or not pstart_rdm_party_token(pstart_rdm.leader)
        or not pstart_rdm_party_claimed(target)
        or (type(target.name) == 'string'
            and target.name:lower():find('%f[%a]elemental%f[%A]'))
    then
        pstart_rdm.pull_silence = nil
        return nil
    end
    local now = os.clock()
    local distance = pstart_rdm_pull_distance(target, leader)
    local pull = pstart_rdm.pull_silence
    if not pull or pull.id ~= target.id or pull.index ~= target.index
        or pull.zone ~= info.zone
    then
        pull = {
            id=target.id, index=target.index, zone=info.zone,
            progress_at=now, progress_distance=distance,
            leader_x=leader.x, leader_y=leader.y, leader_z=leader.z,
            attempts=0, next_attempt=0,
            caster=false, fallback_used=false, covered=false,
            last_result='none',
        }
        pstart_rdm.pull_silence = pull
    end
    -- Measure lack of progress toward the puller, not distance from Smalls.
    -- Relocating the camp or entering melee range restarts the stall clock.
    local leader_moved = pstart_rdm_pull_distance(leader, {
        x=pull.leader_x, y=pull.leader_y, z=pull.leader_z,
    })
    if moving or not distance or distance <= policy.stall_distance
        or not pull.progress_distance
        or distance <= pull.progress_distance - policy.progress_distance
        or (leader_moved and leader_moved >= policy.progress_distance)
    then
        pull.progress_at = now
        pull.progress_distance = distance
        pull.leader_x, pull.leader_y, pull.leader_z = leader.x, leader.y, leader.z
    end
    if not pull.request and not pull.covered and not pull.fallback_used
        and distance and distance > policy.stall_distance
        and now-pull.progress_at >= policy.stall_seconds
    then
        pull.request = 'stalled pull'
    end
    if pull.inflight_until and now >= pull.inflight_until then
        pull.inflight_until = nil
        pull.last_result = 'no result received'
        pull.next_attempt = now + policy.retry_delay
    end
    if not pull.unresolved_warned and distance and distance > policy.stall_distance
        and now-pull.progress_at >= policy.unresolved_seconds
    then
        pull.unresolved_warned = true
        add_to_chat(123, ('[PartyStart RDM] Pull #%d remains at %.1fy; '
            ..'Silence result: %s. Check the puller; no movement requested.')
            :format(pull.id, distance, pull.last_result))
    end
    return pull, target, leader, policy
end

local function pstart_rdm_silence_rearm(pull, reason)
    -- Only genuine new casting/wear-off after coverage opens a new cycle.
    -- More casting from a resistant mob must not reset its attempt budget.
    if pull.covered then
        pull.attempts = 0
        pull.budget_warned = false
    end
    pull.covered = false
    pull.request = reason
end

pstart_rdm_silence_event = function(action)
    if type(action) ~= 'table' or (action.category ~= 8 and action.category ~= 4) then return end
    local pull, target, leader, policy = pstart_rdm_silence_context()
    if not pull then return end
    local started = action.category == 8 and action.param == 24931
    if action.actor_id == pull.id and (started or action.category == 4) then
        pull.caster = true
        -- A completed spell can have started before Silence landed. Do not
        -- interpret that completion as a new cast through confirmed Silence.
        if started or not pull.covered then
            pstart_rdm_silence_rearm(pull, 'observed casting')
        end
        return
    end
    if action.category ~= 4 or action.param ~= PSTART_RDM_SILENCE_ID then return end
    local current = windower.ffxi.get_player()
    local own_cast = current and action.actor_id == current.id and pull.inflight_until
    for _, result_target in ipairs(action.targets or {}) do
        if result_target.id == pull.id then
            for _, result in ipairs(result_target.actions or {}) do
                local landed = PSTART_RDM_SILENCE_LANDED[result.message]
                    and result.param == PSTART_RDM_SILENCE_STATUS
                if landed or (own_cast and result.message == 75) then
                    pull.covered = true
                    pull.request = nil
                    pull.inflight_until = nil
                    pull.last_result = landed and 'landed' or 'already covered (no effect)'
                    add_to_chat(158, ('[PartyStart RDM] Silence %s on #%d.')
                        :format(pull.last_result, pull.id))
                    return
                elseif own_cast then
                    pull.inflight_until = nil
                    pull.next_attempt = os.clock() + policy.retry_delay
                    -- Unknown results are failures, never presumed success.
                    pull.last_result = 'not confirmed (message '..tostring(result.message)..')'
                    pull.complete_resist = result.message == 655 or result.message == 656
                    return
                end
            end
        end
    end
end

pstart_rdm_silence_loss = function(target_id, message_id, status_id)
    local pull = pstart_rdm.pull_silence
    if pull and pull.id == target_id and status_id == PSTART_RDM_SILENCE_STATUS
        and PSTART_RDM_LOSE_EFFECT_MESSAGES[message_id]
    then
        pstart_rdm_silence_rearm(pull, 'Silence wore off')
    end
end

local function pstart_rdm_cast_pull_silence()
    local pull, target, leader, policy = pstart_rdm_silence_context()
    if not pull or not pull.request or pull.covered or pull.inflight_until then return false end
    local budget = pull.caster and policy.max_attempts or 1
    if pull.complete_resist or pull.attempts >= budget then
        if not pull.budget_warned then
            pull.budget_warned = true
            add_to_chat(123, ('[PartyStart RDM] Silence stopped for #%d after %d attempt(s): %s.')
                :format(pull.id, pull.attempts, pull.last_result))
        end
        return false
    end
    if os.clock() < pull.next_attempt
        or type(target.distance) ~= 'number'
        or target.distance < 0 or math.sqrt(target.distance) > policy.max_range
    then return false end
    local spell = pstart_rdm_spell({'Silence'})
    if not spell or not pstart_rdm_can_spend(spell, policy.mp_floor)
        or not pstart_rdm_ready(spell)
    then return false end

    -- GearSwap's outgoing-text handler accepts a numeric server ID and sends
    -- it through the normal precast/midcast/aftercast gear path. Do not wait
    -- for <t>: PartyCombat intentionally rejects melee targets beyond 10y,
    -- and its selection can differ from the pull that needs Silence. This
    -- neither changes the selected target nor injects a select/engage packet.
    pull.attempts = pull.attempts + 1
    pull.fallback_used = true
    pull.inflight_until = os.clock() + policy.result_timeout
    pull.last_result = 'awaiting result'
    windower.chat.input('/ma "Silence" '..tostring(pull.id))
    tickdelay = os.clock() + 3
    add_to_chat(122, ('[PartyStart RDM] Silence #%d: %s (%d/%d).')
        :format(pull.id, pull.request, pull.attempts, budget))
    return true
end

local function pstart_rdm_action()
    if not pstart_rdm.active then
        return false
    end
    local profile = pstart_rdm_profiles[pstart_rdm.profile]
    if not profile then
        return false
    end
    if pstart_rdm_priority_silence_reserved() then
        -- This explicit exact-target request owns the next legal action. If it
        -- is temporarily blocked, returning true also suppresses the native
        -- GearSwap tick so routine maintenance cannot jump the queue.
        if pstart_rdm_cast_priority_silence() then return true end
        if pstart_rdm_priority_silence_reserved() then return true end
    end
    if profile.pull_silence then
        local pull = pstart_rdm_silence_context()
        if pull and pull.request and not pull.covered then
            -- Limbus CC takes the next usable action, after emergency cures
            -- and Convert recovery. All other profiles retain their order.
            if pstart_rdm_emergency_heal() then return true end
            if pstart_rdm_convert_recovery() then return true end
            if pstart_rdm_convert() then return true end
            if pstart_rdm_cast_pull_silence() then return true end
        end
    end
    -- Do not spend the first damaged Fishfly heartbeat activating Composure;
    -- synchronized counters can make that one action the difference between a
    -- recovered party and a wipe.  Other profiles retain their old order.
    if pstart_rdm.profile == 'fishfly'
        and pstart_rdm_emergency_heal()
    then
        return true
    end
    if pstart_rdm_cast_composure() then return true end
    if pstart_rdm.profile ~= 'fishfly'
        and pstart_rdm_emergency_heal()
    then
        return true
    end
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
    if requested == 'probe' then
        pstart_rdm_prove_helper(
            commandArgs[3], commandArgs[4], commandArgs[5])
        return
    elseif requested == 'tick' then
        pstart_rdm_action()
        return
    elseif requested == 'silence' then
        local accepted, reason = pstart_rdm_reserve_priority_silence(
            commandArgs[3])
        if not accepted then
            add_to_chat(123, '[PartyStart RDM] Silence request rejected: '
                ..tostring(reason)..'.')
        elseif reason ~= 'already queued' then
            add_to_chat(122, ('[PartyStart RDM] Silence #%s reserved as the '
                ..'next legal action.')
                :format(tostring(commandArgs[3])))
        end
        pstart_rdm_cast_priority_silence()
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
                ..'reserve %d%% / Protect %s / Shell %s / backup cure <%d%%')
            :format(player.mpp or 0, #pstart_rdm.haste,
                #pstart_rdm.refresh, #pstart_rdm.phalanx,
                #pstart_rdm.defense,
                profile.routine_buff_mp_floor or 0,
                profile.party_protect and 'On' or 'Off',
                profile.party_shell and 'On' or 'Off',
                profile.heal_hpp or (profile.sustained and 25 or 0)))
        add_to_chat(122,
            ('PartyStart RDM bounded Dispels: %d / last %s')
            :format(pstart_rdm.dispel_count,
                tostring(pstart_rdm.last_dispel)))
        if profile.pull_silence then
            local pull = pstart_rdm.pull_silence
            add_to_chat(122, ('PartyStart RDM selective Silence: On / mob ID %s / %s / attempts %d')
                :format(pull and tostring(pull.id) or 'none',
                    pull and pull.last_result or 'waiting for a claimed pull',
                    pull and pull.attempts or 0))
        end
        local priority = pstart_rdm.priority_silence
        add_to_chat(122, ('PartyStart RDM exact Silence queue: %s')
            :format(priority and ('#'..tostring(priority.id)..' / '
                ..tostring(priority.last_blocker or priority.last_result
                    or 'queued')..' / attempts '
                ..tostring(priority.attempts or 0)) or 'Ready on request'))
        return
    elseif requested == 'transition' then
        -- Profile switches preserve still-valid remote buff/debuff timers.
        -- Exact combat adapters are revoked separately before the new profile
        -- applies, so retaining these scheduling hints cannot leak actions.
        pstart_rdm.active = false
        pstart_rdm.transitioning = true
        pstart_rdm.pull_silence = nil
        pstart_rdm_clear_priority_silence()
        pstart_rdm.pending = nil
        pstart_rdm.debuff_attempts = {}
        pstart_rdm.convert_recovery_until = 0
        pstart_rdm.reactive_repairs = {}
        pstart_rdm.opener_targets = {}
        pstart_rdm.dispel_targets = {}
        state.AutoBuffMode:set('Off')
        return
    elseif requested == 'off' then
        pstart_rdm.active = false
        pstart_rdm.transitioning = false
        pstart_rdm.pull_silence = nil
        pstart_rdm_clear_priority_silence()
        pstart_rdm.pending = nil
        -- Remote party effects are not observable through buffactive.  Their
        -- timers are only local scheduling hints, so no timer may survive an
        -- explicit stop and suppress the next profile's opening buff pass.
        pstart_rdm.buff_timers = {}
        pstart_rdm.debuff_timers = {}
        pstart_rdm.debuff_attempts = {}
        pstart_rdm.convert_recovery_until = 0
        pstart_rdm.last_loss_events = {}
        pstart_rdm.reactive_repairs = {}
        pstart_rdm.opener_targets = {}
        pstart_rdm.last_heal_at = 0
        pstart_rdm.opening_shellra = false
        pstart_rdm.party_shellra_available = nil
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
        local preserve_timers = pstart_rdm.transitioning == true
        pstart_rdm.active = true
        pstart_rdm.transitioning = false
        pstart_rdm.pull_silence = nil
        pstart_rdm_clear_priority_silence()
        pstart_rdm.profile = requested
        pstart_rdm.leader = commandArgs[3]
        pstart_rdm.haste = pstart_rdm_names(commandArgs[4])
        pstart_rdm.refresh = pstart_rdm_names(commandArgs[5])
        pstart_rdm.phalanx = pstart_rdm_names(commandArgs[6])
        pstart_rdm.defense = pstart_rdm_names(commandArgs[7])
        pstart_rdm.pending = nil
        -- A profile activation is a new maintenance authority epoch.  Recheck
        -- every requested remote buff instead of inheriting stale proof from
        -- another encounter or a previous life.
        if not preserve_timers then
            pstart_rdm.buff_timers = {}
            pstart_rdm.debuff_timers = {}
        end
        pstart_rdm.debuff_attempts = {}
        pstart_rdm.convert_recovery_until = 0
        pstart_rdm.remote_loss_count = 0
        pstart_rdm.last_remote_loss = 'none'
        pstart_rdm.last_loss_events = {}
        pstart_rdm.reactive_repairs = {}
        pstart_rdm.opener_targets = {}
        pstart_rdm.last_heal_at = 0
        local selected_profile = pstart_rdm_profiles[requested]
        pstart_rdm.opening_shellra = selected_profile.party_shellra == true
        pstart_rdm.party_shellra_available = nil
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
            ..'<profile|silence ID|status|transition|off> <leader> <haste> <refresh> <phalanx> '
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
    local priority = pstart_rdm.priority_silence
    if priority and priority.inflight_until and spell
        and spell.id == PSTART_RDM_SILENCE_ID and spell.interrupted
    then
        priority.inflight_until = nil
        priority.last_result = 'interrupted'
        priority.next_attempt = os.clock()
            + PSTART_RDM_PRIORITY_SILENCE_RETRY
    end
    local pull = pstart_rdm.pull_silence
    if pull and pull.inflight_until and spell
        and spell.id == PSTART_RDM_SILENCE_ID and spell.interrupted
    then
        pull.inflight_until = nil
        pull.last_result = 'interrupted'
        pull.next_attempt = os.clock() + 3
    end
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
            if pending.opening_shellra and spell.interrupted then
                pstart_rdm.opening_shellra = true
            end
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
    local original_result
    if pstart_rdm_original_job_aftercast then
        original_result = pstart_rdm_original_job_aftercast(
            spell, spellMap, eventArgs)
    end
    if pstart_rdm_priority_silence_reserved() then
        -- Let normal aftercast equipment handling finish first. The independent
        -- render poll takes the first legal slot after action recovery.
        pstart_rdm_next_priority_silence_poll = 0
    end
    return original_result
end
