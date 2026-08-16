--[[
PartyStart is an original support orchestrator. Its optional GearSwap
controllers integrate with Selindrile's callback/override framework:
https://github.com/Selindrile/GearSwap

Selindrile's shared include credits Motenten's base files. Neither
Selindrile's nor Motenten's GearSwap source is redistributed here.
PartyStart also sends public commands to Roller2 and HealBot; it does not
bundle either addon.
]]

_addon.name = 'PartyStart'
_addon.author = 'OpenAI Codex'
_addon.version = '1.3.0'
_addon.commands = {'partystart', 'pstart', 'partyup'}

require('tables')
res = require('resources')

local PREFIX = 'PARTYSTART2'
local DISCOVERY_TIMEOUT = 5
local sessions = {}
local current_profile = nil
local current_composition = nil
local autows2_owned = false
local last_profile = 'master'
local last_composition = 'progression'
local next_maintenance = 0
local MAINTENANCE_INTERVAL = 0.75
local zone_rearm_at = nil
local active_session = nil
local zone_epoch = 0
local job_revalidate_at = nil
local pending_revalidation = nil
local nonce_counter = 0
local encounter_alerts = {}
local housemaker_tracker = {next_poll=0, mobs={}}
local reraise_guard = {
    active=false, profile=nil, next_check=0, had=false, warned=false,
}

local profiles = {
    master = {
        sustained = true,
        stationary = true,
        physical_offense = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', "Mage's Ballad III", 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh',
            entrust_jobs={'PLD','RUN','RDM','COR'}},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
        },
    },
    apexbats = {
        label = 'Sustained Apex Bats: Dho Gates',
        sustained = true,
        stationary = true,
        physical_offense = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', "Mage's Ballad III", 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh',
            entrust_jobs={'PLD','RUN','RDM','COR'}},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
        },
        advisories = {
            'Apex Bats: Barwatera is maintained for Water-aligned Sonic Boom; HealBot removes Attack Down only from physical jobs by default.',
            'Apex Bats: Blade Madrigal is retained for the Dho Gates 1113 accuracy target; switch profiles only after live hit-rate evidence supports it.',
            'Apex Bats detect by sound. PartyStart configures support/offense only; pulling and camp safety remain external responsibilities.',
        },
    },
    apexcrabs = {
        label = 'Sustained Apex Crabs: Dho Gates',
        sustained = true,
        stationary = true,
        physical_offense = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', "Mage's Ballad III", 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh',
            entrust_jobs={'PLD','RUN','RDM','COR'}},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
        },
        advisories = {
            'Apex Crabs: stationary camp mode is active; PartyCombat engages and faces but never approaches. Load EasyFarm\'s stationary Flash profile.',
            'Apex Crabs: Barwatera and Shell cover Water-aligned Bubble Shower; HealBot removes STR Down only from physical jobs by default.',
            'Apex Crabs: Smalls makes one MP-reserved Dispel attempt after each observed Bubble Curtain, Metallic Body, or Scissor Guard; it does not poll blindly.',
            'Apex Crabs: Tackleberry uses the aggressive AoE-heal policy and pre-reserves 1000 TP for Chivalry without suspending needed cures.',
            'Apex Crabs: Blade Madrigal is retained for the Dho Gates 1113 accuracy target. The G-11 Crab Bowl supports an independent infinite chain.',
        },
    },
    limbus = {
        label = 'Limbus 119: Mobile Speed Floors',
        -- Limbus is manually driven from Dolo.  The progression composition
        -- keeps Tackleberry as its unattended-XP puller, so override only the
        -- active target source for this tactical profile.
        target_source = 'command_leader',
        physical_offense = true,
        pld_controller = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh', lean=true,
            entrust_jobs={'PLD','RUN','RDM','COR'}},
        rdm = {
            haste_scope='attackers', refresh_scope='mp',
            phalanx_scope='tank', defense_scope='party',
            gearswap_healing=true,
        },
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
        },
        advisories = {
            'Limbus: Dolomedes is the mobile target source; all six attackers follow that synchronized target and use their configured AutoWS2 offense.',
            'Limbus: use //pstart sleep (Alt-L in the supplied init binding) for one queued Horde Lullaby centered on the active target; the current target stays awake under melee while linked enemies are slept.',
            'Limbus: sleep is deliberate, not periodic. Fire it on a linked pack or once the floor item is secured, then move to the exit without waiting for unnecessary kills.',
        },
    },
    physical = {
        physical_offense = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh',
            entrust_jobs={'PLD','RUN','DRK','BLU'}},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
            {'Distract III', 'Distract II', 'Distract'},
        },
    },
    accuracy = {
        cor = {'chaos', 'hunter'},
        brd = {'Victory March', 'Blade Madrigal', 'Valor Minuet V'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Torpor', geo='Frailty', entrust='Fury',
            entrust_jobs={'BLU','PLD','RUN','DNC'}},
        rdm_debuffs = {
            {'Frazzle III', 'Frazzle II', 'Frazzle'},
            {'Dia III', 'Dia II', 'Dia'},
            {'Distract III', 'Distract II', 'Distract'},
        },
    },
    magic = {
        cor = {'wizard', 'warlock'},
        brd = {"Mage's Ballad III", 'Victory March', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
            {'Pining Nocturne'},
        },
        geo = {indi='Acumen', geo='Malaise', entrust='Refresh',
            entrust_jobs={'PLD','RUN','RDM','BLU'}},
        rdm_debuffs = {
            {'Frazzle III', 'Frazzle II', 'Frazzle'},
            {'Dia III', 'Dia II', 'Dia'},
            {'Addle II', 'Addle'},
        },
    },
    safe = {
        cor = {'chaos', 'gallant'},
        brd = {'Victory March', "Sentinel's Scherzo", 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
            {'Pining Nocturne'},
        },
        geo = {indi='Barrier', geo='Frailty', entrust='Refresh',
            entrust_jobs={'PLD','RUN','DRK','BLU'}},
        rdm_debuffs = {
            {'Frazzle III', 'Frazzle II', 'Frazzle'},
            {'Dia III', 'Dia II', 'Dia'},
            {'Distract III', 'Distract II', 'Distract'},
            {'Slow II', 'Slow'},
            {'Paralyze II', 'Paralyze'},
            {'Blind II', 'Blind'},
            {'Addle II', 'Addle'},
        },
    },
    ['ambuscade-v1'] = {
        label = 'August 2026 V1: Bozzetto Breadwinner',
        reraise = true,
        physical_offense = true,
        attackers = {'Dolomedes', 'Tackleberry', 'Kickpuncher'},
        target_all = true,
        priority_target = 'Bozzetto Urchin',
        priority_attackers = {'Dolomedes', 'Kickpuncher'},
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Wilt', lean=true,
            entrust_jobs={'PLD','COR','DNC'}},
        rdm = {
            haste_scope='attackers', refresh_scope='mp',
            phalanx_scope='tank', defense_scope='party',
            gearswap_healing=true,
        },
        pld_controller = true,
        required_sub_jobs = {
            Barneystinson = {
                jobs={'WHM'},
                reason='Barstonra/Barsilencera Housemaker bait and Reraise',
            },
            Smalls = {
                jobs={'WHM'},
                reason='status removal, backup cures, and Reraise',
            },
            Achoo = {
                jobs={'WHM'},
                reason='Paralyna/Erase support, backup cures, and Reraise',
            },
        },
        advisories = {
            'V1: Tackleberry tanks Breadwinner in the starting corner facing the wall; Dolomedes and Kickpuncher attack from behind.',
            'V1: Smalls opens Stymie + Saboteur + Silence, confirms the result, retries a resist, then applies Paralyze II. Silence is critical because it shrinks Warble range and suppresses invisible Urchin activation.',
            'V1: Barney must be BRD/WHM; he supplies Barstonra/Barsilencera and is the intended Housemaker bait. Keep him with the group, move only Barney 20+ yalms away when the movement alarm fires, then return immediately after Earthshaker for Cure/Paralyna and renewed Barspell coverage.',
            'V1: Barney, Smalls, and Achoo maintain self-Reraise. Dolomedes, Tackleberry, and Kickpuncher require Reraise items; each client warns while unprotected.',
            'V1: Entrusted Indi-Wilt follows Tackleberry to reduce physical pressure. Encounter alerts identify Warble elements, Housemaker movement/Earthshaker, and Hundred Fists.',
            'V1: Dolo and Kickpuncher automatically split to a visible Bozzetto Urchin and return to Breadwinner after it dies; Tackleberry and all supports remain anchored on Breadwinner.',
            'V1: Hundred Fists/Gale Spikes begin near 50%. PLD automation reserves Sentinel for that threshold.',
        },
    },
    ['ambuscade-v2'] = {
        label = 'August 2026 V2: Popular Penelope',
        reraise = true,
        physical_offense = true,
        attackers = {'Dolomedes', 'Tackleberry', 'Kickpuncher'},
        target_all = true,
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh', lean=true,
            entrust_jobs={'PLD','RDM','GEO','BRD'}},
        rdm = {
            haste_scope='attackers', refresh_scope='mp',
            phalanx_scope='tank', defense_scope='party',
            gearswap_healing=true,
        },
        pld_controller = true,
        advisories = {
            'V2: Tackleberry and Dolomedes stand in front to split Bad Breath; Kickpuncher attacks from behind; Barney, Smalls, and Achoo stay outside the cone.',
            'V2: Use Poison Potions before the pull and carry Echo Drops, Remedies, and Holy Water. The final Extremely Bad Breath can inflict Doom.',
            'V2: Sweet Breath resets enmity. PLD automation deliberately saves Sentinel for manual post-reset hate recovery; use Flash/Provoke/Sentinel as needed.',
            'V2: Barsleepra and Barstonra are maintained, but positioning and consumables remain manual responsibilities.',
        },
    },
}

local profile_aliases = {
    bats = 'apexbats',
    apexbat = 'apexbats',
    ['apex-bats'] = 'apexbats',
    crabs = 'apexcrabs',
    crab = 'apexcrabs',
    apexcrab = 'apexcrabs',
    ['apex-crab'] = 'apexcrabs',
    ['apex-crabs'] = 'apexcrabs',
    lim = 'limbus',
    limbus119 = 'limbus',
    ['limbus-119'] = 'limbus',
    efts = 'master',
    apexefts = 'master',
    ['apex-efts'] = 'master',
    v1 = 'ambuscade-v1',
    ambu1 = 'ambuscade-v1',
    ambuv1 = 'ambuscade-v1',
    ['ambu-v1'] = 'ambuscade-v1',
    v2 = 'ambuscade-v2',
    ambu2 = 'ambuscade-v2',
    ambuv2 = 'ambuscade-v2',
    ['ambu-v2'] = 'ambuscade-v2',
}

local composition_warning = nil
local composition_data = nil
local composition_loader, composition_load_error = loadfile(
    windower.addon_path..'data/compositions.lua')
if composition_loader then
    local ok, loaded = pcall(composition_loader)
    if ok and type(loaded) == 'table'
        and type(loaded.compositions) == 'table'
    then
        composition_data = loaded
    else
        composition_warning = ok
            and 'compositions.lua did not return a valid policy table.'
            or tostring(loaded)
    end
else
    composition_warning = tostring(composition_load_error)
end

if composition_data then
    last_composition = composition_data.default or last_composition
end

local compositions = composition_data and composition_data.compositions or {}
local composition_aliases = composition_data and composition_data.aliases or {}

local mp_jobs = S{
    'WHM','BLM','RDM','PLD','DRK','BLU','BRD','NIN','SMN','SCH','GEO','RUN'
}

local frontline_jobs = S{
    'WAR','MNK','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG',
    'BLU','COR','PUP','DNC','RUN'
}

-- Routine Haste is reserved for jobs expected to contribute physical TP.
-- BRD and GEO are included because the current physical profile arms their
-- AutoWS2 offense along with the dedicated melee jobs.
local haste_jobs = S{
    'WAR','MNK','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG',
    'BLU','COR','PUP','DNC','GEO','RUN'
}

local function chat(color, message)
    windower.add_to_chat(color or 207, '[PartyStart] '..message)
end

local V1_WARBLE_ALERTS = {
    ['Fire Meeble Warble'] = 'FIRE WARBLE: Barfira; expect Plague/Burn.',
    ['Blizzard Meeble Warble'] =
        'ICE WARBLE: Barblizzara; expect Paralyze/Frost.',
    ['Thunder Meeble Warble'] =
        'THUNDER WARBLE: Barthundra; expect Stun/Shock.',
    ['Stone Meeble Warble'] =
        'STONE WARBLE: Barstonra is already maintained; expect Petrify/Rasp.',
    ['Water Meeble Warble'] =
        'WATER WARBLE: Barwatera; expect Poison/Drown.',
    ['Aero Meeble Warble'] =
        'WIND WARBLE: Baraera; expect Silence/Choke.',
    ['Meeble Warble'] =
        'WARBLE ready: element was not exposed by the action resource.',
}

local HOUSEMAKER_POLL_INTERVAL = 0.20
local HOUSEMAKER_ACTIVATION_DISTANCE = 0.75
local HOUSEMAKER_REARM_DISTANCE = 0.35
local RERAISE_CHECK_INTERVAL = 1.0
local RERAISE_BUFF = res.buffs:with('en', 'Reraise')

local function is_housemaker(mob)
    return type(mob) == 'table' and type(mob.name) == 'string'
        and mob.name:lower():find('housemaker', 1, true) ~= nil
end

local function local_command_leader()
    local player = windower.ffxi.get_player()
    local composition = current_composition and compositions[current_composition]
        or nil
    return player and composition
        and type(composition.command_leader) == 'string'
        and player.name:lower() == composition.command_leader:lower()
end

local function housemaker_alert(message, audible)
    chat(167, '********************************************************')
    chat(167, '*** '..message..' ***')
    chat(167, '********************************************************')
    if audible and local_command_leader() then
        -- PartyStart runs on every client on one Windows host. Play one alarm
        -- from the configured command leader instead of six overlapping copies.
        pcall(windower.play_sound, 'C:\\Windows\\Media\\Alarm03.wav')
    end
end

local function reset_encounter_guards(profile_name)
    encounter_alerts = {}
    housemaker_tracker = {next_poll=0, mobs={}}
    reraise_guard = {
        active=profile_name ~= nil and profiles[profile_name]
            and profiles[profile_name].reraise == true or false,
        profile=profile_name,
        next_check=os.clock() + 6,
        had=false,
        warned=false,
    }
end

local function v1_poll_housemaker(now)
    if current_profile ~= 'ambuscade-v1'
        or now < (housemaker_tracker.next_poll or 0)
    then
        return
    end
    housemaker_tracker.next_poll = now + HOUSEMAKER_POLL_INTERVAL

    for index, mob in pairs(windower.ffxi.get_mob_array() or {}) do
        if is_housemaker(mob) and tonumber(mob.x) and tonumber(mob.y) then
            local key = tostring(mob.id or index)
            local x, y = tonumber(mob.x), tonumber(mob.y)
            local tracked = housemaker_tracker.mobs[key]
            if not tracked then
                -- The entity is present at its staging point well before it
                -- attacks. That first position is the stable home reference.
                housemaker_tracker.mobs[key] = {
                    home_x=x, home_y=y, away=false, last_seen=now,
                }
            else
                local dx, dy = x - tracked.home_x, y - tracked.home_y
                local distance = math.sqrt(dx * dx + dy * dy)
                tracked.last_seen = now
                if not tracked.away
                    and distance >= HOUSEMAKER_ACTIVATION_DISTANCE
                then
                    tracked.away = true
                    local alert_key = 'housemaker-moving:'..key
                    if now - (encounter_alerts[alert_key] or 0) >= 8 then
                        encounter_alerts[alert_key] = now
                        housemaker_alert(
                            'HOUSEMAKER MOVING: BARNEY SEPARATE NOW; '
                            ..'EVERYONE ELSE STAY PUT.', true)
                    end
                elseif tracked.away
                    and distance <= HOUSEMAKER_REARM_DISTANCE
                then
                    -- It returned to its staging point. Arm the next charge.
                    tracked.away = false
                    housemaker_alert(
                        'HOUSEMAKER RETURNED: BARNEY RETURN TO GROUP NOW; '
                        ..'CURE/PARALYNA, THEN RESTORE BAR COVERAGE.', false)
                end
            end
        end
    end
end

local function local_has_reraise()
    local player = windower.ffxi.get_player()
    if not player or not RERAISE_BUFF then return false end
    for _, buff_id in ipairs(player.buffs or {}) do
        if buff_id == RERAISE_BUFF.id then return true end
    end
    return false
end

local function check_reraise_guard(now)
    if not reraise_guard.active
        or now < (reraise_guard.next_check or 0)
    then
        return
    end
    reraise_guard.next_check = now + RERAISE_CHECK_INTERVAL
    if local_has_reraise() then
        reraise_guard.had = true
        reraise_guard.warned = false
        return
    end
    if reraise_guard.warned then return end

    local player = windower.ffxi.get_player()
    local caster = player and S{'BRD','RDM','GEO'}:contains(player.main_job)
    local remedy = caster
        and ((reraise_guard.profile or 'encounter')
            ..' support casters must use /WHM; self-Reraise should restore automatically.')
        or 'Use a Reraiser/Hi-Reraiser before the pull.'
    chat(167, ('*** NO RERAISE: %s (%s/%s). %s ***')
        :format(player and player.name or 'local player',
            player and player.main_job or 'NON',
            player and player.sub_job or 'NON', remedy))
    reraise_guard.warned = true
end

local function monster_ability_from_action(action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = res.monster_abilities[result.param]
                if ability then return ability end
            end
        end
        return nil
    end
    if action.category == 6 or action.category == 11 then
        return res.monster_abilities[action.param]
    end
    return nil
end

local function v1_encounter_alert(action)
    if current_profile ~= 'ambuscade-v1' then return end
    local ability = monster_ability_from_action(action)
    local actor = ability and windower.ffxi.get_mob_by_id(action.actor_id)
        or nil
    if not actor or type(actor.name) ~= 'string' then return end

    local message
    if actor.name == 'Bozzetto Breadwinner' then
        message = V1_WARBLE_ALERTS[ability.en]
        if ability.en == 'Hundred Fists' then
            message = 'HUNDRED FISTS: reserved PLD mitigation is activating; Gale Spikes can reflect damage and overwrite Haste II.'
        end
    elseif actor.name:lower():find('housemaker', 1, true)
        and type(ability.en) == 'string'
        and ability.en:find('Earthshaker', 1, true)
    then
        message = 'HOUSEMAKER EARTHSHAKER: BARNEY TAKES 1,000 EVEN WHEN ISOLATED. RETURN TO GROUP NOW FOR CURE/PARALYNA.'
    end
    if not message then return end

    local key = tostring(actor.id)..':'..tostring(ability.id)
    local now = os.clock()
    if now - (encounter_alerts[key] or 0) < 6 then return end
    encounter_alerts[key] = now
    if actor.name:lower():find('housemaker', 1, true) then
        housemaker_alert(message, false)
    else
        chat(167, '*** '..message..' ***')
    end
end

windower.register_event('action', v1_encounter_alert)

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function valid_nonce(nonce)
    return type(nonce) == 'string'
        and nonce:match('^[0-9]+%-[0-9]+%-[0-9]+$') ~= nil
end

local function new_nonce(player)
    nonce_counter = nonce_counter + 1
    return ('%d-%d-%d'):format(
        os.time(), player and player.id or 0, nonce_counter)
end

local function split(value, separator)
    local result = {}
    if type(value) ~= 'string' then return result end
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
end

local function normalize_composition(name)
    if type(name) ~= 'string' then return nil end
    name = name:lower()
    return composition_aliases[name] or name
end

local function normalize_profile(name)
    if type(name) ~= 'string' then return nil end
    name = name:lower()
    return profile_aliases[name] or name
end

local function get_composition(name)
    local normalized = normalize_composition(name)
    return normalized, normalized and compositions[normalized] or nil
end

local function list_contains_name(names, wanted)
    if not valid_name(wanted) then return false end
    for _, name in ipairs(names or {}) do
        if valid_name(name) and name:lower() == wanted:lower() then
            return true
        end
    end
    return false
end

local function list_contains_value(values, wanted)
    for _, value in ipairs(values or {}) do
        if value == wanted then return true end
    end
    return false
end

local function composition_attackers(composition, active_names, profile)
    local attackers = {}
    local configured = profile and profile.attackers or composition.attackers
    for _, name in ipairs(configured or {}) do
        if list_contains_name(active_names, name) then
            attackers[#attackers + 1] = name
        end
    end
    table.sort(attackers)
    return attackers
end

local function profile_targeters(profile, active_names, attackers)
    if profile and profile.target_all then
        local targeters = {}
        for _, name in ipairs(active_names or {}) do
            if valid_name(name) then targeters[#targeters + 1] = name end
        end
        table.sort(targeters)
        return targeters
    end
    local targeters = {}
    for _, name in ipairs(attackers or {}) do
        targeters[#targeters + 1] = name
    end
    return targeters
end

local function composition_role(composition, name)
    local roles = {}
    if valid_name(composition.command_leader)
        and composition.command_leader:lower() == name:lower()
    then
        roles[#roles + 1] = 'command-leader'
    end
    if valid_name(composition.puller)
        and composition.puller:lower() == name:lower()
    then
        roles[#roles + 1] = 'puller'
    end
    for role, owner in pairs(composition.roles or {}) do
        if valid_name(owner) and owner:lower() == name:lower() then
            roles[#roles + 1] = role:gsub('_', '-')
        end
    end
    if #roles == 0 then return 'support' end
    table.sort(roles)
    return table.concat(roles, '+')
end

local function send_ipc(fields)
    windower.send_ipc_message(table.concat(fields, '|'))
end

local function party_names()
    local names = {}
    local seen = {}
    for _,member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table' and valid_name(member.name)
            and not seen[member.name] then
            names[#names + 1] = member.name
            seen[member.name] = true
        end
    end
    table.sort(names)
    return names
end

local function contains_name(names, name)
    for _,candidate in ipairs(names or {}) do
        if candidate:lower() == name:lower() then
            return true
        end
    end
    return false
end

local function report(session)
    local player = windower.ffxi.get_player()
    if not player or not contains_name(session.names, player.name) then
        return
    end
    session.roster[player.name] = {
        main_job = player.main_job,
        sub_job = player.sub_job,
    }
    send_ipc{
        PREFIX, 'report', session.nonce, player.name,
        player.main_job or 'NON', player.sub_job or 'NON'
    }
end

local function learned_spells()
    return windower.ffxi.get_spells() or {}
end

local function knows_spell(name)
    local spell = res.spells:with('en', name)
    return spell ~= nil and learned_spells()[spell.id] == true
end

local function first_known(candidates)
    for _,name in ipairs(candidates) do
        if knows_spell(name) then
            return name
        end
    end
    return nil
end

local function issue(command)
    if command and command ~= '' then
        windower.send_command(command)
    end
end

local function stop_owned_autows2()
    if autows2_owned then
        issue('aws2 off')
        autows2_owned = false
    end
end

local function composition_offense(composition, player)
    local by_character = composition
        and composition.offense
        and composition.offense[player.name]
        or nil
    return by_character and by_character[player.main_job] or nil
end

local function apply_physical_offense(player, composition, attackers)
    if not list_contains_name(attackers, player.name) then
        stop_owned_autows2()
        return
    end
    local offense = composition_offense(composition, player)
    if not offense then
        stop_owned_autows2()
        chat(123, ('No offense policy for %s on %s; AutoWS2 is Off.')
            :format(player.name, player.main_job))
        return
    end

    local aftermath = offense.aftermath
    local aftermath_command = 'aws2 aftermath off'
    if aftermath and aftermath.enabled then
        aftermath_command = ('aws2 aftermath on; aws2 aftermath mode %s; '
            ..'aws2 aftermath type %s; aws2 aftermath ws %s; '
            ..'aws2 aftermath duration %d')
            :format(
                aftermath.mode or 'active',
                aftermath.type or 'lv3',
                aftermath.ws or offense.ws,
                tonumber(aftermath.duration) or 180)
    end
    -- Ordinary weaponskills should continue through the final displayed 5%
    -- of a target. On high-HP Ambuscade enemies that last segment is still a
    -- substantial amount of HP. Aftermath profiles retain the conservative
    -- 5% floor so they do not spend a 3000-TP reapplication on a dying mob.
    local hp_min = tonumber(offense.hp_min)
    if hp_min == nil then
        hp_min = aftermath and aftermath.enabled and 5 or 0
    end
    local hp_max = tonumber(offense.hp_max) or 100
    issue(('gs c set Weapons %s; wait 1; %s; '
        ..'aws2 use %s; aws2 tp %d; aws2 hp %d %d; aws2 on')
        :format(offense.weapon_mode, aftermath_command,
            offense.ws, tonumber(offense.tp) or 1000,
            hp_min, hp_max))
    autows2_owned = true
end

local function hb_buff(target, spells)
    local known = {}
    for _,spell in ipairs(spells) do
        if knows_spell(spell) then
            known[#known + 1] = spell
        end
    end
    if #known > 0 then
        issue(('hb buff %s %s'):format(target, table.concat(known, ',')))
    end
end

local function sorted_roster(roster)
    local names = {}
    for name,_ in pairs(roster) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

local function first_job(roster, wanted)
    for _,name in ipairs(sorted_roster(roster)) do
        if roster[name].main_job == wanted then
            return name
        end
    end
    return nil
end

local function first_jobs(roster, wanted)
    for _, job in ipairs(wanted or {}) do
        local name = first_job(roster, job)
        if name then return name end
    end
    return nil
end

local function roster_record(roster, wanted)
    if not valid_name(wanted) then return nil end
    for name, record in pairs(roster or {}) do
        if valid_name(name) and name:lower() == wanted:lower() then
            return record, name
        end
    end
    return nil
end

local function expected_job(composition, wanted)
    if not valid_name(wanted) then return nil end
    for name, expected in pairs(composition.expected_jobs or {}) do
        if valid_name(name) and name:lower() == wanted:lower() then
            return expected, name
        end
    end
    return nil
end

local function profile_subjob_policy(policies, wanted)
    if not valid_name(wanted) then return nil end
    for name, policy in pairs(policies or {}) do
        if valid_name(name) and name:lower() == wanted:lower() then
            return policy
        end
    end
    return nil
end

local function roster_complete(session)
    for _, name in ipairs(session.names or {}) do
        if not roster_record(session.roster, name) then return false end
    end
    return true
end

local function validate_session(session)
    local errors = {}
    local warnings = {}
    local composition = compositions[session.composition]
    local profile = profiles[session.profile]
    if not composition then
        errors[#errors + 1] = 'unknown composition '..tostring(session.composition)
        return errors, warnings
    end

    if not list_contains_name(session.names, composition.command_leader) then
        errors[#errors + 1] = 'command leader '..composition.command_leader
            ..' is not in the active party'
    end

    for _, name in ipairs(session.names or {}) do
        local record = roster_record(session.roster, name)
        local expected = expected_job(composition, name)
        if not record then
            errors[#errors + 1] = name..' did not report its jobs'
        elseif not expected then
            errors[#errors + 1] = name..' has no policy in '
                ..session.composition
        elseif record.main_job ~= expected.main then
            errors[#errors + 1] = ('%s is %s/%s; expected %s')
                :format(name, record.main_job, record.sub_job, expected.main)
        elseif expected.sub_jobs
            and not list_contains_value(expected.sub_jobs, record.sub_job)
        then
            warnings[#warnings + 1] = ('%s subjob %s is outside the tested set (%s)')
                :format(name, record.sub_job, table.concat(expected.sub_jobs, '/'))
        end

        local required_sub = profile and profile_subjob_policy(
            profile.required_sub_jobs, name) or nil
        if record and required_sub
            and not list_contains_value(required_sub.jobs or {}, record.sub_job)
        then
            errors[#errors + 1] = ('%s is %s/%s; %s requires /%s (%s)')
                :format(name, record.main_job, record.sub_job,
                    session.profile, table.concat(required_sub.jobs or {}, '/'),
                    required_sub.reason or 'encounter support policy')
        end

        if record and expected and profile and profile.physical_offense
            and list_contains_name(
                composition_attackers(composition, session.names, profile), name)
            and not composition_offense(composition, {
                name=name, main_job=record.main_job,
            })
        then
            errors[#errors + 1] = ('%s %s has no offense policy')
                :format(name, record.main_job)
        end
    end

    for configured_name, _ in pairs(composition.expected_jobs or {}) do
        if not list_contains_name(session.names, configured_name) then
            warnings[#warnings + 1] = configured_name
                ..' is configured but not in this party'
        end
    end

    if not list_contains_name(session.names, composition.puller) then
        warnings[#warnings + 1] = 'puller '..composition.puller
            ..' is absent; combat target authority will fall back to '
            ..composition.command_leader
    end
    return errors, warnings
end

local function is_requester(session)
    local player = windower.ffxi.get_player()
    return player and valid_name(session.requester)
        and player.name:lower() == session.requester:lower()
end

local function announce_validation(session, errors, warnings)
    if not is_requester(session) then return end
    local composition = compositions[session.composition]
    local profile = profiles[session.profile]
    local attackers = composition and profile
        and composition_attackers(composition, session.names, profile) or {}
    chat(207, ('%s / %s: %s')
        :format(session.composition, session.profile,
            composition and composition.label or 'unknown'))
    for _, name in ipairs(sorted_roster(session.roster)) do
        if contains_name(session.names, name) then
            local record = session.roster[name]
            local offense = composition
                and composition_offense(composition, {
                    name=name, main_job=record.main_job,
                }) or nil
            local offense_text = list_contains_name(attackers, name) and offense
                and (offense.weapon_mode..' / '..offense.ws
                    ..' @ '..tostring(offense.tp or 1000))
                or (profile and profile.target_all
                    and 'target-only support; no AutoWS2'
                    or 'manual/no AutoWS2')
            chat(207, ('  %s %s/%s | %s | %s')
                :format(name, record.main_job, record.sub_job,
                    composition and composition_role(composition, name)
                        or 'unknown',
                    offense_text))
        end
    end
    for _, warning in ipairs(warnings) do
        chat(123, 'Warning: '..warning)
    end
    for _, validation_error in ipairs(errors) do
        chat(167, 'Blocked: '..validation_error)
    end
end

local function encode_roster(session)
    local records = {}
    for _, name in ipairs(session.names or {}) do
        local record = roster_record(session.roster, name)
        if record then
            records[#records + 1] = table.concat({
                name, record.main_job, record.sub_job,
            }, ',')
        end
    end
    return table.concat(records, ';')
end

local function decode_roster(session, encoded)
    local roster = {}
    if type(encoded) ~= 'string' then return roster end
    for record in encoded:gmatch('[^;]+') do
        local fields = split(record, ',')
        local name, main_job, sub_job = fields[1], fields[2], fields[3]
        if valid_name(name) and contains_name(session.names, name)
            and res.jobs:with('ens', main_job)
            and res.jobs:with('ens', sub_job)
        then
            roster[name] = {main_job=main_job, sub_job=sub_job}
        end
    end
    return roster
end

local function apply_whm(player)
    local self_spells = {
        'Protectra V', 'Shellra V', 'Auspice', 'Afflatus Solace',
        'Aquaveil', 'Reraise IV'
    }
    local known = {}
    for _, spell in ipairs(self_spells) do
        if knows_spell(spell) then known[#known + 1] = spell end
    end
    if #known > 0 then
        issue(('hb cancelbuff %s %s'):format(
            player.name, table.concat(known, ',')))
    end
    issue('gs c pstartwhm on')
    issue('hb deactivateindoors off; hb db off; hb as off; '
        ..'hb as attack off; hb on')
end

local function apply_rdm(
    player, profile_name, profile, roster, leader, target_source,
    composition, active_names)
    local haste = first_known{'Haste II', 'Haste'}
    local refresh = first_known{'Refresh III', 'Refresh II', 'Refresh'}
    local phalanx_ii = first_known{'Phalanx II'}
    local haste_targets = {}
    local refresh_targets = {}
    local refresh_tanks = {}
    local refresh_others = {}
    local phalanx_targets = {}
    local defense_targets = {}
    local encounter_policy = profile.rdm or {}
    local sustained = profile.sustained == true
    local attackers = composition_attackers(composition, active_names, profile)

    for _,name in ipairs(sorted_roster(roster)) do
        local job = roster[name].main_job
        local haste_wanted = encounter_policy.haste_scope == 'attackers'
            and list_contains_name(attackers, name)
            or encounter_policy.haste_scope ~= 'attackers'
                and haste_jobs:contains(job)
        if haste and haste_wanted then
            haste_targets[#haste_targets + 1] = name
            issue(('hb cancelbuff %s %s'):format(name, haste))
        end
        if refresh and mp_jobs:contains(job) then
            -- Always clear any HealBot registration inherited from an older
            -- PartyStart profile, even when GearSwap will not maintain this
            -- target in the sustained profile.
            issue(('hb cancelbuff %s %s'):format(name, refresh))
            local sustained_refresh = sustained
                and (name:lower() == player.name:lower()
                    or job == 'PLD' or job == 'RUN')
            local refresh_wanted = encounter_policy.refresh_scope == 'mp'
                or not sustained or sustained_refresh
            if refresh_wanted then
                local destination = (job == 'PLD' or job == 'RUN')
                    and refresh_tanks or refresh_others
                destination[#destination + 1] = name
            end
        end
        local configured_tank = composition.roles and composition.roles.tank
        local phalanx_wanted = encounter_policy.phalanx_scope == 'tank'
            and valid_name(configured_tank)
            and name:lower() == configured_tank:lower()
            or encounter_policy.phalanx_scope ~= 'tank'
                and (sustained and job == 'PLD'
                    or not sustained
                        and name ~= player.name
                        and frontline_jobs:contains(job))
        if phalanx_ii and phalanx_wanted then
            phalanx_targets[#phalanx_targets + 1] = name
            issue(('hb cancelbuff %s %s'):format(name, phalanx_ii))
        end
        if encounter_policy.defense_scope == 'party' then
            defense_targets[#defense_targets + 1] = name
        end
    end

    if sustained then
        -- The MP reserve can intentionally pause the tail of this list. Keep
        -- the tank/healer and primary physical contributors at the front so
        -- low-priority support melee never delays the core party.
        local function haste_rank(name)
            local job = roster[name].main_job
            if job == 'PLD' or job == 'RUN' then return 1 end
            if name:lower() == leader:lower() then return 2 end
            if job == 'DNC' then return 3 end
            if job == 'COR' or job == 'RDM' or job == 'BRD' then return 4 end
            if job == 'GEO' then return 5 end
            return 6
        end
        table.sort(haste_targets, function(left, right)
            local left_rank, right_rank = haste_rank(left), haste_rank(right)
            return left_rank == right_rank and left < right
                or left_rank < right_rank
        end)
    end

    -- RDM's controller moves itself to the front. In sustained profiles this
    -- leaves only the RDM and PLD/RUN on the Refresh rotation; Ballad supplies
    -- the other MP jobs. Richer profiles append every MP job after the tanks.
    for _, name in ipairs(refresh_tanks) do
        refresh_targets[#refresh_targets + 1] = name
    end
    for _, name in ipairs(refresh_others) do
        refresh_targets[#refresh_targets + 1] = name
    end
    if player.main_job == 'RDM' then
        for index, name in ipairs(refresh_targets) do
            if name:lower() == player.name:lower() then
                table.remove(refresh_targets, index)
                table.insert(refresh_targets, 1, name)
                break
            end
        end
    end

    local old_self = {
        'Temper II', 'Temper', 'Gain-STR', 'Gain-MND',
        'Aquaveil', 'Phalanx', 'Reraise',
    }
    for _, spell in ipairs(old_self) do
        if knows_spell(spell) then
            issue(('hb cancelbuff %s %s'):format(player.name, spell))
        end
    end
    local old_debuffs = {
        'Frazzle III', 'Frazzle II', 'Frazzle',
        'Dia III', 'Dia II', 'Dia',
        'Distract III', 'Distract II', 'Distract',
        'Slow II', 'Slow', 'Paralyze II', 'Paralyze',
        'Blind II', 'Blind', 'Addle II', 'Addle',
        'Silence',
    }
    for _, spell in ipairs(old_debuffs) do
        if knows_spell(spell) then issue('hb db rm '..spell) end
    end

    local function csv(names)
        return #names > 0 and table.concat(names, ',') or '-'
    end
    issue('gs c set AutoBuffMode Off')
    if #defense_targets == 0 then
        local seen = {}
        for _, names in ipairs{haste_targets, refresh_targets, phalanx_targets} do
            for _, name in ipairs(names) do
                if not seen[name:lower()] then
                    seen[name:lower()] = true
                    defense_targets[#defense_targets + 1] = name
                end
            end
        end
    end
    issue(('gs c pstartrdm %s %s %s %s %s %s'):format(
        profile_name, target_source, csv(haste_targets), csv(refresh_targets),
        csv(phalanx_targets), csv(defense_targets)))
    if sustained or encounter_policy.gearswap_healing then
        -- GearSwap owns all HP decisions in the sustained profile. HealBot is
        -- retained on RDM only for packet-backed status removal; letting it
        -- also cure creates a race with PLD and drains the RDM first.
        issue('hb deactivateindoors off; hb disable cure; '
            ..'hb enable na; hb disable buff; hb db off; '
            ..'hb as off; hb as attack off; hb on')
    else
        issue('hb deactivateindoors off; hb enable cure; hb mincure 1; '
            ..'hb enable na; hb disable buff; hb db off; '
            ..'hb as off; hb as attack off; hb on')
    end
end

local function apply_brd(player, profile_name, target_source)
    -- Remove registrations left by PartyStart versions that delegated BRD to
    -- HealBot. GearSwap now owns both party songs and hostile songs.
    local old_songs = {
        'Victory March', 'Valor Minuet V', 'Blade Madrigal',
        "Mage's Ballad III", "Sentinel's Scherzo",
    }
    local known_old_songs = {}
    for _, spell in ipairs(old_songs) do
        if knows_spell(spell) then
            known_old_songs[#known_old_songs + 1] = spell
        end
    end
    if #known_old_songs > 0 then
        issue(('hb cancelbuff %s %s'):format(
            player.name, table.concat(known_old_songs, ',')))
    end
    for _, spell in ipairs{
        'Carnage Elegy', 'Battlefield Elegy', 'Pining Nocturne'
    } do
        if knows_spell(spell) then issue('hb db rm '..spell) end
    end
    issue('hb db off; hb as off; hb as attack off; hb off')
    issue(('gs c pstartbrd %s %s'):format(profile_name, target_source))
end

local function apply_geo(player, profile_name, profile, roster)
    local geo = profile.geo
    local entrustee = first_jobs(roster, geo.entrust_jobs)
        or player.name
    if profile.reraise and (profile.sustained or geo.lean) then
        issue('gs c pstartgeo leanrr')
    elseif profile.sustained or geo.lean then
        issue('gs c pstartgeo lean')
    else
        issue('gs c pstartgeo restore')
    end
    issue(('gs c autoindi %s; gs c autogeo %s; gs c autoentrust %s; '
        ..'gs c autoentrustee %s; gs c set AutoBuffMode Auto')
        :format(geo.indi, geo.geo, geo.entrust, entrustee))
    issue('hb db off; hb as off; hb as attack off; hb off')
end


local function apply_pld(profile_name, profile, leader)
    -- AutoTankMode and AutoWSMode are boolean Mote states. Boolean states use
    -- `set`/`unset`; appending true/false does not reliably change them.
    issue('gs c set AutoBuffMode Auto; gs c set AutoTankMode; '
        ..'gs c unset AutoTankFull; '
        ..'gs c set HybridMode Tank; '
        ..'gs c unset AutoWSMode')
    if profile.sustained or profile.pld_controller then
        -- HealBot's optional PartyOps gate can reject a newer PartyOps phase
        -- before action selection. The PLD controller therefore lives in
        -- GearSwap and runs before native Flash/Provoke upkeep.
        issue('hb disable cure; hb disable na; hb db off; '
            ..'hb as off; hb as attack off; hb off')
        issue(('gs c pstartpld %s %s'):format(profile_name, leader))
    else
        issue('gs c pstartpld off')
        issue('hb disable cure; hb disable na; '
            ..'hb db off; hb as off; hb as attack off; hb off')
    end
end

local function apply_dnc(profile_name, target_source)
    -- PartyStart_DNC is the sole DNC action owner. Native AutoBuff is kept off
    -- because its No Foot Rise check treats a recast bucket as proof that the
    -- merit ability is learned. Dance stance stays None so emergency Waltzes
    -- remain usable.
    issue('gs c set AutoBuffMode Off; gs c unset AutoPrestoMode; '
        ..'gs c set AutoSambaMode Off; gs c set DanceStance None; '
        ..'gs c unset AutoWSMode; cancel 410')
    issue(('gs c pstartdnc %s %s'):format(profile_name, target_source))
    issue('hb db off; hb as off; hb as attack off; hb off')
end

local function apply_cor(profile)
    issue(('r2 policy conservative; r2 engaged off; r2 roll1 %s; '
        ..'r2 roll2 %s; r2 on'):format(profile.cor[1], profile.cor[2]))
    issue('gs c unset AutoWSMode')
    issue('hb db off; hb as off; hb as attack off; hb off')
end

local function runtime_puller(composition, active_names, profile)
    local target_source = composition.puller
    if profile and profile.target_source == 'command_leader' then
        target_source = composition.command_leader
    elseif profile and valid_name(profile.target_source) then
        target_source = profile.target_source
    end
    if valid_name(target_source)
        and list_contains_name(active_names, target_source)
    then
        return target_source
    end
    return composition.command_leader
end

local function apply_combat_policy(session, composition, profile)
    local attackers = composition_attackers(
        composition, session.names, profile)
    local targeters = profile_targeters(profile, session.names, attackers)
    local puller = runtime_puller(composition, session.names, profile)
    local attacker_csv = #attackers > 0 and table.concat(attackers, ',') or '-'
    local targeter_csv = #targeters > 0 and table.concat(targeters, ',') or '-'
    local policy_name = session.composition..'-'..session.profile
    local movement_mode = profile.stationary and 'stationary' or 'mobile'
    local priority_attackers = {}
    for _, name in ipairs(profile.priority_attackers or {}) do
        if list_contains_name(attackers, name) then
            priority_attackers[#priority_attackers + 1] = name
        end
    end
    table.sort(priority_attackers)
    local priority_target = type(profile.priority_target) == 'string'
        and #priority_attackers > 0
        and profile.priority_target:gsub(' ', '_') or '-'
    local priority_attacker_csv = #priority_attackers > 0
        and table.concat(priority_attackers, ',') or '-'
    issue(('pc policy %s %s %s %s %s %s %s %s')
        :format(policy_name, composition.command_leader,
            puller, attacker_csv, targeter_csv, movement_mode,
            priority_target, priority_attacker_csv))
    session.target_source = puller
    session.attackers = attackers
    session.targeters = targeters
    session.movement_mode = movement_mode
    session.priority_target = profile.priority_target
    session.priority_attackers = priority_attackers
end

local function apply_profile(session)
    local player = windower.ffxi.get_player()
    local profile = profiles[session.profile]
    local composition = compositions[session.composition]
    if not player or not profile or not composition
        or not contains_name(session.names, player.name)
    then
        return
    end

    apply_combat_policy(session, composition, profile)

    -- Clear HealBot movement/assist automation when selecting a support
    -- profile. FastFollow is user-owned and must remain unchanged.
    issue('hb follow off; hb as off; hb as attack off')

    if player.main_job == 'WHM' then
        apply_whm(player)
    elseif player.main_job == 'RDM' then
        apply_rdm(player, session.profile, profile, session.roster,
            session.leader, session.target_source, composition, session.names)
    elseif player.main_job == 'BRD' then
        apply_brd(player, session.profile, session.target_source)
    elseif player.main_job == 'GEO' then
        apply_geo(player, session.profile, profile, session.roster)
    elseif player.main_job == 'PLD' then
        apply_pld(session.profile, profile, session.leader)
    elseif player.main_job == 'DNC' then
        apply_dnc(session.profile, session.target_source)
    elseif player.main_job == 'COR' then
        apply_cor(profile)
    elseif player.main_job == 'BLU' then
        -- Uses the existing BLU GearSwap command surface; no BLU file is changed.
        issue('gs c set AutoBuffMode Auto')
        issue('hb db off; hb as off; hb as attack off; hb off')
    end

    if profile.physical_offense then
        apply_physical_offense(player, composition, session.attackers)
    else
        stop_owned_autows2()
    end

    current_profile = session.profile
    current_composition = session.composition
    active_session = session
    last_profile = session.profile
    last_composition = session.composition
    reset_encounter_guards(current_profile)
    chat(158, ('%s/%s ready as %s/%s; AutoWS2 %s; PartyCombat policy %s.')
        :format(session.composition, session.profile,
            player.main_job, player.sub_job,
            autows2_owned and 'on' or 'unchanged', session.target_source))
    if is_requester(session) then
        for _, advisory in ipairs(profile.advisories or {}) do
            chat(123, advisory)
        end
    end
end

local function schedule_zone_rearm(delay)
    if not current_profile or not active_session then return end
    zone_epoch = zone_epoch + 1
    local armed_epoch = zone_epoch
    zone_rearm_at = os.clock() + delay
    windower.send_command(('wait %d; lua i PartyStart __zonerearm %d')
        :format(delay, armed_epoch))
end

local function finalize_session(session)
    if session.applied or not is_requester(session) then return end
    local errors, warnings = validate_session(session)
    local decision = #errors > 0 and 'abort'
        or (session.preview and 'preview' or 'commit')
    session.applied = true
    session.completed_at = os.clock()
    announce_validation(session, errors, warnings)
    send_ipc{
        PREFIX, 'decision', session.nonce, decision,
        encode_roster(session), session.requester,
    }
    if #errors > 0 then
        chat(167, 'Validation failed; no automation was changed.')
        return
    end
    if session.preview then
        chat(158, 'Preview passed; no automation was changed.')
        return
    end
    apply_profile(session)
end

local function begin(composition_name, profile_name, preview, revalidation)
    local player = windower.ffxi.get_player()
    if not player then
        chat(123, 'No active player.')
        return
    end
    if composition_warning then
        chat(167, 'Composition policy is unavailable; no automation changed. '
            ..composition_warning)
        return
    end
    local normalized, composition = get_composition(composition_name)
    profile_name = normalize_profile(profile_name)
    if not composition then
        chat(123, 'Unknown composition: '..tostring(composition_name))
        return
    end
    if not profile_name or not profiles[profile_name] then
        chat(123, 'Unknown profile: '..tostring(profile_name))
        return
    end

    local names = party_names()
    if #names == 0 then
        chat(123, 'No party members found.')
        return
    end

    local nonce = new_nonce(player)
    local session = {
        nonce = nonce,
        composition = normalized,
        profile = profile_name,
        preview = preview == true,
        names = names,
        leader = composition.command_leader,
        requester = player.name,
        roster = {},
        discovery_deadline = os.clock() + DISCOVERY_TIMEOUT,
        next_report_at = 0,
        applied = false,
    }
    sessions[nonce] = session
    pending_revalidation = nil
    job_revalidate_at = nil
    send_ipc{
        PREFIX, 'start', nonce, normalized, profile_name,
        preview and '1' or '0', table.concat(names, ','),
        composition.command_leader, player.name,
    }
    report(session)
    chat(207, ('%s %d party jobs for %s/%s%s...')
        :format(preview and 'Previewing' or 'Validating', #names,
            normalized, profile_name,
            revalidation and ' after a job change' or ''))
end

local function stop_local(options)
    options = options or {}
    local player = windower.ffxi.get_player()
    if not player then return end
    stop_owned_autows2()
    issue('hb follow off; hb db off; hb as off; hb as attack off; hb off')
    if player.main_job == 'COR' then issue('r2 off') end
    if player.main_job == 'BRD' then issue('gs c pstartbrd off') end
    if player.main_job == 'RDM' then issue('gs c pstartrdm off') end
    if player.main_job == 'WHM' then issue('gs c pstartwhm off') end
    if player.main_job == 'PLD' then issue('gs c pstartpld off') end
    if player.main_job == 'DNC' then issue('gs c pstartdnc off') end
    if player.main_job == 'GEO' then issue('gs c pstartgeo idle') end
    if player.main_job == 'GEO' or player.main_job == 'RDM'
        or player.main_job == 'BLU' or player.main_job == 'PLD'
        or player.main_job == 'DNC' then
        issue('gs c set AutoBuffMode Off')
    end
    if player.main_job == 'PLD' then
        issue('gs c unset AutoTankMode; gs c unset AutoTankFull; '
            ..'gs c unset AutoWSMode')
    end
    if player.main_job == 'DNC' then
        issue('gs c set AutoSambaMode Off; gs c unset AutoPrestoMode; '
            ..'gs c set DanceStance None; gs c unset AutoWSMode')
    end
    current_profile = nil
    current_composition = nil
    active_session = nil
    reset_encounter_guards(nil)
    zone_rearm_at = nil
    zone_epoch = zone_epoch + 1
    next_maintenance = 0
    if not options.preserve_revalidation then
        pending_revalidation = nil
        job_revalidate_at = nil
    end
    if not options.silent then
        chat(207, 'Support automation stopped; no combat or FastFollow commands were issued.')
    end
end

local function queue_job_revalidation(composition_name, profile_name, silent)
    if not compositions[composition_name] or not profiles[profile_name] then
        return
    end
    pending_revalidation = {
        composition = composition_name,
        profile = profile_name,
    }
    stop_local{silent=true, preserve_revalidation=true}
    job_revalidate_at = os.clock() + 10
    if not silent then
        chat(123, ('Job change detected; %s/%s is suspended pending validation.')
            :format(composition_name, profile_name))
    end
end

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string' then return end

    if not message:startswith(PREFIX..'|') then
        return
    end
    local fields = split(message, '|')
    local kind = fields[2]
    local nonce = fields[3]
    if not valid_nonce(nonce) then return end

    if kind == 'start' then
        local composition_name = normalize_composition(fields[4])
        local composition = composition_name and compositions[composition_name]
        local profile_name = fields[5]
        local preview = fields[6] == '1'
        local leader = fields[8]
        local requester = fields[9]
        if not composition or not profiles[profile_name]
            or type(fields[7]) ~= 'string'
            or not valid_name(leader) or not valid_name(requester)
        then return end
        if leader:lower() ~= composition.command_leader:lower() then return end
        local names = split(fields[7], ',')
        local player = windower.ffxi.get_player()
        if not player or not contains_name(names, player.name)
            or not contains_name(names, leader)
            or not contains_name(names, requester) then return end

        sessions[nonce] = sessions[nonce] or {
            nonce = nonce,
            composition = composition_name,
            profile = profile_name,
            preview = preview,
            names = names,
            leader = leader,
            requester = requester,
            roster = {},
            discovery_deadline = os.clock() + DISCOVERY_TIMEOUT,
            next_report_at = 0,
            applied = false,
        }
        pending_revalidation = nil
        job_revalidate_at = nil
        report(sessions[nonce])
    elseif kind == 'report' then
        local session = sessions[nonce]
        local name, main_job, sub_job = fields[4], fields[5], fields[6]
        if session and valid_name(name) and contains_name(session.names, name)
            and res.jobs:with('ens', main_job) and res.jobs:with('ens', sub_job) then
            session.roster[name] = {main_job=main_job, sub_job=sub_job}
        end
    elseif kind == 'decision' then
        local session = sessions[nonce]
        local decision, encoded, requester = fields[4], fields[5], fields[6]
        if not session or session.applied
            or not S{'commit','preview','abort'}:contains(decision)
            or not valid_name(requester)
            or requester:lower() ~= session.requester:lower()
        then
            return
        end
        session.roster = decode_roster(session, encoded)
        local errors = validate_session(session)
        session.applied = true
        session.completed_at = os.clock()
        if decision == 'commit' and #errors == 0 then
            apply_profile(session)
        elseif decision == 'commit' then
            chat(167, 'Rejected an invalid consolidated PartyStart commit; '
                ..'no automation changed on this client.')
        end
    elseif kind == 'stop' then
        stop_local()
    elseif kind == 'jobchange' then
        local composition_name = normalize_composition(fields[4])
        local profile_name = fields[5]
        local source = fields[6]
        if not valid_name(source) then return end
        local player = windower.ffxi.get_player()
        if player and player.name:lower() == source:lower() then return end
        queue_job_revalidation(composition_name, profile_name, false)
    elseif kind == 'sleep' then
        local composition_name = normalize_composition(fields[4])
        local profile_name = normalize_profile(fields[5])
        local source = fields[6]
        local composition = composition_name and compositions[composition_name]
            or nil
        local player = windower.ffxi.get_player()
        if profile_name ~= 'limbus'
            or not composition or not valid_name(source)
            or source:lower() ~= composition.command_leader:lower()
            or not active_session
            or current_composition ~= composition_name
            or current_profile ~= profile_name
            or active_session.composition ~= composition_name
            or active_session.profile ~= profile_name
            or not player or player.main_job ~= 'BRD'
            or not contains_name(active_session.names, player.name)
        then
            return
        end
        issue('gs c pstartbrd sleep')
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()
    v1_poll_housemaker(now)
    check_reraise_guard(now)
    if zone_rearm_at and now >= zone_rearm_at then
        zone_rearm_at = nil
        if active_session then
            -- Sel-Include resets AutoBuff, AutoTank, and related states while
            -- zoning. Reapply the complete policy, not just HealBot, after the
            -- party and resource tables have settled.
            apply_profile(active_session)
        end
    end
    for nonce,session in pairs(sessions) do
        if now <= session.discovery_deadline
            and now >= (session.next_report_at or 0)
        then
            session.next_report_at = now + 0.5
            report(session)
        end
        if not session.applied and is_requester(session)
            and (roster_complete(session) or now >= session.discovery_deadline)
        then
            finalize_session(session)
        elseif session.applied and session.completed_at
            and now - session.completed_at > 30
        then
            sessions[nonce] = nil
        elseif not session.applied
            and now > session.discovery_deadline + 10
        then
            sessions[nonce] = nil
        end
    end

    if pending_revalidation and job_revalidate_at
        and now >= job_revalidate_at
    then
        local pending = pending_revalidation
        pending_revalidation = nil
        job_revalidate_at = nil
        local player = windower.ffxi.get_player()
        local composition = compositions[pending.composition]
        if player and composition
            and player.name:lower() == composition.command_leader:lower()
        then
            begin(pending.composition, pending.profile, false, true)
        end
    end

    -- Sel-Include suppresses its normal GearSwap tick while Sneak or Invisible
    -- is active. Drive PartyStart's support controllers explicitly so a
    -- stealthed follower does not perform only the first action and then stall.
    if current_profile and now >= next_maintenance then
        next_maintenance = now + MAINTENANCE_INTERVAL
        local player = windower.ffxi.get_player()
        if player then
            if player.main_job == 'WHM' then
                issue('gs c pstartwhm tick')
            elseif player.main_job == 'RDM' then
                issue('gs c pstartrdm tick')
            elseif player.main_job == 'BRD' then
                issue('gs c pstartbrd tick')
            elseif player.main_job == 'PLD' then
                issue('gs c pstartpld tick')
            elseif player.main_job == 'DNC' then
                issue('gs c pstartdnc tick')
            end
        end
    end
end)

windower.register_event('zone change', function()
    -- HealBot and Sel-Include both reset state during zoning. Reassert the
    -- complete support policy once the new zone and party tables have settled.
    if current_profile then
        -- Keep both the normal prerender timer and a Windower command-queue
        -- wakeup. Some clients spend most of a battlefield exit without
        -- yielding useful prerender ticks; either path may safely win.
        schedule_zone_rearm(8)
    end
end)

windower.register_event('job change', function()
    local composition_name = current_composition
        or (active_session and active_session.composition)
    local profile_name = current_profile
        or (active_session and active_session.profile)
    if not composition_name or not profile_name then return end
    local player = windower.ffxi.get_player()
    if not player or not valid_name(player.name) then return end
    local nonce = new_nonce(player)
    queue_job_revalidation(composition_name, profile_name, false)
    send_ipc{PREFIX, 'jobchange', nonce, composition_name, profile_name,
        player.name}
end)

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = (command or 'status'):lower()
    if command == '__zonerearm' then
        local rearm_epoch = tonumber(args[1])
        if rearm_epoch == zone_epoch and active_session then
            zone_rearm_at = nil
            apply_profile(active_session)
        end
        return
    end

    local direct_composition = normalize_composition(command)
    local direct_profile = normalize_profile(command)
    if direct_composition and compositions[direct_composition] and args[1] then
        -- Friendly shorthand: //pstart progression v1
        begin(direct_composition, normalize_profile(args[1]), false)
    elseif direct_profile and profiles[direct_profile] then
        begin(last_composition, direct_profile, false)
    elseif command == 'on' or command == 'start' then
        begin(last_composition, last_profile, false)
    elseif command == 'use' then
        begin(args[1] or last_composition,
            normalize_profile(args[2] or last_profile), false)
    elseif command == 'preview' then
        begin(args[1] or last_composition,
            normalize_profile(args[2] or last_profile), true)
    elseif command == 'stop' or command == 'off' then
        send_ipc{PREFIX, 'stop', new_nonce(windower.ffxi.get_player())}
        stop_local()
    elseif command == 'sleep' then
        local player = windower.ffxi.get_player()
        if current_profile ~= 'limbus' or not active_session then
            chat(123, 'Pack sleep requires an active Limbus profile.')
        elseif not local_command_leader() then
            chat(123, 'Use //pstart sleep from the configured command leader.')
        elseif not player or not valid_name(player.name) then
            chat(123, 'No active player; pack sleep was not sent.')
        else
            send_ipc{
                PREFIX, 'sleep', new_nonce(player),
                active_session.composition, active_session.profile, player.name,
            }
            chat(158, 'Queued one Limbus pack sleep on the active target.')
        end
    elseif command == 'status' then
        chat(207, ('Active: %s/%s | Selected: %s/%s')
            :format(current_composition or 'off', current_profile or 'off',
                last_composition, last_profile))
    elseif command == 'version' then
        chat(207, ('Version %s | selected %s/%s')
            :format(_addon.version, last_composition, last_profile))
    elseif command == 'list' then
        local names = {}
        for name, _ in pairs(compositions) do names[#names + 1] = name end
        table.sort(names)
        chat(207, 'Compositions: '..table.concat(names, ', '))
        chat(207, 'Profiles: master (Apex Efts), apexbats (bats), '
            ..'apexcrabs (crabs), '
            ..'limbus (lim), physical, accuracy, magic, safe, '
            ..'ambuscade-v1 (v1), ambuscade-v2 (v2)')
    else
        chat(207, 'Commands: use <composition> <profile> | preview '
            ..'<composition> <profile> | on | off | master | apexbats | '
            ..'apexcrabs | limbus | sleep | '
            ..'physical | accuracy | magic | safe | v1 | v2 | status | '
            ..'version | list')
    end
end)

chat(158, 'Loaded v'.._addon.version..'. Sustained aliases: '
    ..'//pstart efts, bats, or crabs. '
    ..'Limbus: //pstart limbus; Ambuscade: //pstart v1 or v2.')
if composition_warning then
    chat(167, 'Composition policy unavailable; activation is blocked. '
        ..composition_warning)
end
