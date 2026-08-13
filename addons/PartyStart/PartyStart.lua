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
_addon.version = '0.6.1'
_addon.commands = {'partystart', 'pstart', 'partyup'}

require('tables')
res = require('resources')

local PREFIX = 'PARTYSTART1'
local APPLY_DELAY = 1.5
local sessions = {}
local current_profile = nil
local autows2_owned = false
local last_profile = 'master'
local next_maintenance = 0
local MAINTENANCE_INTERVAL = 0.75

local profiles = {
    master = {
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {},
        geo = {indi='Fury', geo='Frailty', entrust='Regen',
            entrust_jobs={'PLD','RUN','RDM','COR'}},
        rdm_debuffs = {},
    },
    physical = {
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
}

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

-- Current roster offense assignments. PartyStart applies these during the
-- physical and master profiles. GearSwap selects the weapon; AutoWS2 remains
-- the sole weapon-skill decision maker.
local physical_offense = {
    Dolomedes = {
        jobs = S{'COR'}, weapon_mode = 'DualSavage',
        ws = 'Savage Blade', tp = 1000,
    },
    Tackleberry = {
        jobs = S{'PLD'}, weapon_mode = 'Naegling',
        ws = 'Savage Blade', tp = 1000,
    },
    Kickpuncher = {
        jobs = S{'DNC'}, weapon_mode = 'Tauret',
        ws = 'Evisceration', tp = 1000,
    },
    Barneystinson = {
        jobs = S{'BRD'}, weapon_mode = 'DualSavage',
        ws = 'Savage Blade', tp = 1000,
    },
    Smalls = {
        jobs = S{'RDM'}, weapon_mode = 'Maxentius',
        ws = 'Black Halo', tp = 1000,
    },
    Achoo = {
        jobs = S{'GEO'}, weapon_mode = 'Maxentius',
        ws = 'Black Halo', tp = 1000,
    },
}

local function chat(color, message)
    windower.add_to_chat(color or 207, '[PartyStart] '..message)
end

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function valid_nonce(nonce)
    return type(nonce) == 'string'
        and nonce:match('^[0-9]+%-[0-9]+$') ~= nil
end

local function split(value, separator)
    local result = {}
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
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

local function apply_physical_offense(player)
    local offense = physical_offense[player.name]
    if not offense or not offense.jobs:contains(player.main_job) then
        stop_owned_autows2()
        if offense then
            chat(123, ('No offense policy for %s on %s; AutoWS2 unchanged.')
                :format(player.name, player.main_job))
        end
        return
    end

    issue(('gs c set Weapons %s; wait 1; aws2 aftermath off; '
        ..'aws2 use %s; aws2 tp %d; aws2 on')
        :format(offense.weapon_mode, offense.ws, offense.tp))
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
    issue('hb db off; hb as off; hb as attack off; hb on')
end

local function apply_rdm(player, profile_name, roster, leader)
    local haste = first_known{'Haste II', 'Haste'}
    local refresh = first_known{'Refresh III', 'Refresh II', 'Refresh'}
    local phalanx_ii = first_known{'Phalanx II'}
    local haste_targets = {}
    local refresh_targets = {}
    local phalanx_targets = {}

    for _,name in ipairs(sorted_roster(roster)) do
        local job = roster[name].main_job
        if haste and haste_jobs:contains(job) then
            haste_targets[#haste_targets + 1] = name
            issue(('hb cancelbuff %s %s'):format(name, haste))
        end
        if refresh and mp_jobs:contains(job) then
            refresh_targets[#refresh_targets + 1] = name
            issue(('hb cancelbuff %s %s'):format(name, refresh))
        end
        if phalanx_ii and name ~= player.name and frontline_jobs:contains(job) then
            phalanx_targets[#phalanx_targets + 1] = name
            issue(('hb cancelbuff %s %s'):format(name, phalanx_ii))
        end
    end

    local old_self = {
        'Temper II', 'Temper', 'Gain-STR', 'Aquaveil', 'Phalanx', 'Reraise',
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
    }
    for _, spell in ipairs(old_debuffs) do
        if knows_spell(spell) then issue('hb db rm '..spell) end
    end

    local function csv(names)
        return #names > 0 and table.concat(names, ',') or '-'
    end
    issue('gs c set AutoBuffMode Off')
    issue(('gs c pstartrdm %s %s %s %s %s'):format(
        profile_name, leader, csv(haste_targets), csv(refresh_targets),
        csv(phalanx_targets)))
    if profile_name == 'master' then
        -- HealBot does not arbitrate Cure ownership between active healers.
        -- In the sustained profile PLD owns cures; RDM retains status removal.
        issue('hb disable cure; hb enable na; hb disable buff; hb db off; '
            ..'hb as off; hb as attack off; hb on')
    else
        issue('hb enable cure; hb enable na; hb disable buff; hb db off; '
            ..'hb as off; hb as attack off; hb on')
    end
end

local function apply_brd(player, profile_name, leader)
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
    issue(('gs c pstartbrd %s %s'):format(profile_name, leader))
end

local function apply_geo(player, profile, roster)
    local geo = profile.geo
    local entrustee = first_jobs(roster, geo.entrust_jobs)
        or player.name
    issue(('gs c autoindi %s; gs c autogeo %s; gs c autoentrust %s; '
        ..'gs c autoentrustee %s; gs c set AutoBuffMode Auto')
        :format(geo.indi, geo.geo, geo.entrust, entrustee))
    issue('hb db off; hb as off; hb as attack off; hb off')
end


local function apply_pld(profile_name)
    issue('gs c set AutoBuffMode Auto; gs c set AutoTankMode true; '
        ..'gs c set AutoWSMode false')
    if profile_name == 'master' then
        issue('hb enable cure; hb disable na; hb disable buff; hb mincure 2; '
            ..'hb db off; hb as off; hb as attack off; hb on')
    else
        issue('hb disable cure; hb disable na; '
            ..'hb db off; hb as off; hb as attack off; hb off')
    end
end

local function apply_dnc()
    issue('gs c set AutoBuffMode Auto; gs c set AutoSambaMode Haste; '
        ..'gs c set MainStep Box Step')
    issue('hb db off; hb as off; hb as attack off; hb off')
end

local function apply_cor(profile)
    issue(('r2 policy conservative; r2 engaged off; r2 roll1 %s; '
        ..'r2 roll2 %s; r2 on'):format(profile.cor[1], profile.cor[2]))
    issue('gs c set AutoWSMode false')
    issue('hb db off; hb as off; hb as attack off; hb off')
end

local function apply_profile(session)
    local player = windower.ffxi.get_player()
    local profile = profiles[session.profile]
    if not player or not profile or not contains_name(session.names, player.name) then
        return
    end

    -- Clear HealBot movement/assist automation when selecting a support
    -- profile. FastFollow is user-owned and must remain unchanged.
    issue('hb follow off; hb as off; hb as attack off')

    if player.main_job == 'WHM' then
        apply_whm(player)
    elseif player.main_job == 'RDM' then
        apply_rdm(player, session.profile, session.roster, session.leader)
    elseif player.main_job == 'BRD' then
        apply_brd(player, session.profile, session.leader)
    elseif player.main_job == 'GEO' then
        apply_geo(player, profile, session.roster)
    elseif player.main_job == 'PLD' then
        apply_pld(session.profile)
    elseif player.main_job == 'DNC' then
        apply_dnc()
    elseif player.main_job == 'COR' then
        apply_cor(profile)
    elseif player.main_job == 'BLU' then
        -- Uses the existing BLU GearSwap command surface; no BLU file is changed.
        issue('gs c set AutoBuffMode Auto')
        issue('hb db off; hb as off; hb as attack off; hb off')
    end

    if session.profile == 'physical' or session.profile == 'master' then
        apply_physical_offense(player)
    else
        stop_owned_autows2()
    end

    current_profile = session.profile
    chat(158, ('%s ready as %s/%s; AutoWS2 %s; combat ownership unchanged.')
        :format(session.profile, player.main_job, player.sub_job,
            autows2_owned and 'on' or 'unchanged'))
end

local function begin(profile_name)
    local player = windower.ffxi.get_player()
    if not player then
        chat(123, 'No active player.')
        return
    end
    if not profiles[profile_name] then
        chat(123, 'Unknown profile: '..tostring(profile_name))
        return
    end

    local names = party_names()
    if #names == 0 then
        chat(123, 'No party members found.')
        return
    end

    local nonce = ('%d-%d'):format(os.time(), player.id or 0)
    local session = {
        nonce = nonce,
        profile = profile_name,
        names = names,
        leader = player.name,
        roster = {},
        apply_at = os.clock() + APPLY_DELAY,
        applied = false,
    }
    sessions[nonce] = session
    last_profile = profile_name
    send_ipc{
        PREFIX, 'start', nonce, profile_name, table.concat(names, ','), player.name
    }
    report(session)
    chat(207, ('Discovering %d party jobs for profile %s...')
        :format(#names, profile_name))
end

local function stop_local()
    local player = windower.ffxi.get_player()
    if not player then return end
    stop_owned_autows2()
    issue('hb follow off; hb db off; hb as off; hb as attack off; hb off')
    windower.ffxi.run(false)
    if player.main_job == 'COR' then issue('r2 off') end
    if player.main_job == 'BRD' then issue('gs c pstartbrd off') end
    if player.main_job == 'RDM' then issue('gs c pstartrdm off') end
    if player.main_job == 'WHM' then issue('gs c pstartwhm off') end
    if player.main_job == 'GEO' or player.main_job == 'RDM'
        or player.main_job == 'BLU' or player.main_job == 'PLD'
        or player.main_job == 'DNC' then
        issue('gs c set AutoBuffMode Off')
    end
    if player.main_job == 'PLD' then
        issue('gs c set AutoTankMode false; gs c set AutoWSMode false')
    end
    if player.main_job == 'DNC' then issue('gs c set AutoSambaMode Off') end
    current_profile = nil
    next_maintenance = 0
    chat(207, 'Support automation stopped; no combat commands were issued.')
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
        local profile_name = fields[4]
        local leader = fields[6]
        if not profiles[profile_name] or type(fields[5]) ~= 'string'
            or not valid_name(leader) then return end
        local names = split(fields[5], ',')
        local player = windower.ffxi.get_player()
        if not player or not contains_name(names, player.name)
            or not contains_name(names, leader) then return end

        sessions[nonce] = sessions[nonce] or {
            nonce = nonce,
            profile = profile_name,
            names = names,
            leader = leader,
            roster = {},
            apply_at = os.clock() + APPLY_DELAY,
            applied = false,
        }
        report(sessions[nonce])
    elseif kind == 'report' then
        local session = sessions[nonce]
        local name, main_job, sub_job = fields[4], fields[5], fields[6]
        if session and valid_name(name) and contains_name(session.names, name)
            and res.jobs:with('ens', main_job) and res.jobs:with('ens', sub_job) then
            session.roster[name] = {main_job=main_job, sub_job=sub_job}
        end
    elseif kind == 'stop' then
        stop_local()
    end
end)

windower.register_event('prerender', function()
    local now = os.clock()
    for nonce,session in pairs(sessions) do
        if not session.applied and now >= session.apply_at then
            session.applied = true
            apply_profile(session)
        elseif session.applied and now - session.apply_at > 30 then
            sessions[nonce] = nil
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
            end
        end
    end
end)

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'physical'
    if profiles[command] then
        begin(command)
    elseif command == 'on' or command == 'start' then
        begin(last_profile)
    elseif command == 'stop' or command == 'off' then
        send_ipc{PREFIX, 'stop', ('%d-%d'):format(
            os.time(), (windower.ffxi.get_player() or {}).id or 0)}
        stop_local()
    elseif command == 'status' then
        chat(207, ('Active: %s | Selected: %s')
            :format(current_profile or 'off', last_profile))
    else
        chat(207, 'Commands: on | off | master | physical | accuracy | magic | safe | status')
    end
end)

chat(158, 'Loaded. Use //pstart master for sustained COR/PLD/DNC/BRD/RDM/GEO grinding.')
