_addon.name = 'PartyStart'
_addon.author = 'OpenAI Codex'
_addon.version = '0.1.0'
_addon.commands = {'partystart', 'pstart', 'partyup'}

require('tables')
res = require('resources')

local PREFIX = 'PARTYSTART1'
local APPLY_DELAY = 1.5
local sessions = {}
local current_profile = nil
local last_profile = 'physical'

local profiles = {
    physical = {
        cor = {'chaos', 'samurai'},
        brd = {'Victory March', 'Valor Minuet V', 'Blade Madrigal'},
        brd_debuffs = {
            {'Carnage Elegy', 'Battlefield Elegy'},
        },
        geo = {indi='Fury', geo='Frailty', entrust='Refresh', entrust_job='WHM'},
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
        geo = {indi='Torpor', geo='Frailty', entrust='Fury', entrust_job='BLU'},
        rdm_debuffs = {
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
        geo = {indi='Acumen', geo='Malaise', entrust='Refresh', entrust_job='WHM'},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
            {'Frazzle III', 'Frazzle II', 'Frazzle'},
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
        geo = {indi='Barrier', geo='Frailty', entrust='Refresh', entrust_job='WHM'},
        rdm_debuffs = {
            {'Dia III', 'Dia II', 'Dia'},
            {'Distract III', 'Distract II', 'Distract'},
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

local function apply_whm(player)
    local self_spells = {
        'Protectra V', 'Shellra V', 'Auspice', 'Afflatus Solace',
        'Aquaveil', 'Reraise IV'
    }
    hb_buff(player.name, self_spells)
    issue('hb db off; hb as off; hb as attack off; hb on')
end

local function apply_rdm(player, profile, roster)
    local haste = first_known{'Haste II', 'Haste'}
    local refresh = first_known{'Refresh III', 'Refresh II', 'Refresh'}
    local phalanx_ii = first_known{'Phalanx II'}

    for _,name in ipairs(sorted_roster(roster)) do
        local job = roster[name].main_job
        if haste then hb_buff(name, {haste}) end
        if refresh and mp_jobs:contains(job) then hb_buff(name, {refresh}) end
        if phalanx_ii and name ~= player.name and frontline_jobs:contains(job) then
            hb_buff(name, {phalanx_ii})
        end
    end

    hb_buff(player.name, {
        first_known{'Temper II', 'Temper'} or '',
        'Gain-STR', 'Aquaveil', 'Phalanx', 'Reraise'
    })
    issue('input /ja "Composure" <me>')

    local debuffs = {}
    for _,choices in ipairs(profile.rdm_debuffs) do
        local spell = first_known(choices)
        if spell then debuffs[#debuffs + 1] = spell end
    end
    for _,spell in ipairs(debuffs) do
        issue('hb db '..spell)
    end

    -- Debuffs are configured but intentionally held until combat setup supplies
    -- an assist target and explicitly enables them.
    issue('hb db off; hb as off; hb as attack off; gs c set AutoBuffMode Auto; hb on')
end

local function apply_brd(player, profile)
    hb_buff(player.name, profile.brd)
    for _,choices in ipairs(profile.brd_debuffs or {}) do
        local spell = first_known(choices)
        if spell then issue('hb db '..spell) end
    end
    -- Songs begin immediately; hostile songs are only registered here and
    -- remain disabled until the future combat phase provides a target.
    issue('hb db off; hb as off; hb as attack off; hb on')
end

local function apply_geo(player, profile, roster)
    local geo = profile.geo
    local entrustee = first_job(roster, geo.entrust_job)
        or first_job(roster, 'WHM')
        or player.name
    issue(('gs c autoindi %s; gs c autogeo %s; gs c autoentrust %s; '
        ..'gs c autoentrustee %s; gs c set AutoBuffMode Auto')
        :format(geo.indi, geo.geo, geo.entrust, entrustee))
    issue('hb db off; hb as off; hb as attack off; hb on')
end

local function apply_cor(profile)
    issue(('r2 policy conservative; r2 engaged off; r2 roll1 %s; '
        ..'r2 roll2 %s; r2 on'):format(profile.cor[1], profile.cor[2]))
end

local function apply_profile(session)
    local player = windower.ffxi.get_player()
    local profile = profiles[session.profile]
    if not player or not profile or not contains_name(session.names, player.name) then
        return
    end

    if player.main_job == 'WHM' then
        apply_whm(player)
    elseif player.main_job == 'RDM' then
        apply_rdm(player, profile, session.roster)
    elseif player.main_job == 'BRD' then
        apply_brd(player, profile)
    elseif player.main_job == 'GEO' then
        apply_geo(player, profile, session.roster)
    elseif player.main_job == 'COR' then
        apply_cor(profile)
    elseif player.main_job == 'BLU' then
        -- Uses the existing BLU GearSwap command surface; no BLU file is changed.
        issue('gs c set AutoBuffMode Auto')
    end

    current_profile = session.profile
    chat(158, ('%s ready as %s/%s; combat remains disabled.')
        :format(session.profile, player.main_job, player.sub_job))
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
        roster = {},
        apply_at = os.clock() + APPLY_DELAY,
        applied = false,
    }
    sessions[nonce] = session
    last_profile = profile_name
    send_ipc{PREFIX, 'start', nonce, profile_name, table.concat(names, ',')}
    report(session)
    chat(207, ('Discovering %d party jobs for profile %s...')
        :format(#names, profile_name))
end

local function stop_local()
    local player = windower.ffxi.get_player()
    if not player then return end
    issue('hb db off; hb as off; hb as attack off; hb off')
    if player.main_job == 'COR' then issue('r2 off') end
    if player.main_job == 'GEO' or player.main_job == 'RDM'
        or player.main_job == 'BLU' then
        issue('gs c set AutoBuffMode Off')
    end
    current_profile = nil
    chat(207, 'Support automation stopped; no combat commands were issued.')
end

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string' or not message:startswith(PREFIX..'|') then
        return
    end
    local fields = split(message, '|')
    local kind = fields[2]
    local nonce = fields[3]
    if not valid_nonce(nonce) then return end

    if kind == 'start' then
        local profile_name = fields[4]
        if not profiles[profile_name] or type(fields[5]) ~= 'string' then return end
        local names = split(fields[5], ',')
        local player = windower.ffxi.get_player()
        if not player or not contains_name(names, player.name) then return end

        sessions[nonce] = sessions[nonce] or {
            nonce = nonce,
            profile = profile_name,
            names = names,
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
        chat(207, 'Commands: on | off | physical | accuracy | magic | safe | status')
    end
end)

chat(158, 'Loaded. Use //pstart physical for the current six-character party.')
