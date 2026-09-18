-- SPDX-License-Identifier: MIT
-- Passive flight recorder: never casts, moves, equips, injects, or blocks packets.
_addon.name = 'CombatRecorder'
_addon.author = 'OpenAI Codex'
_addon.version = '0.1.1-candidate'
_addon.commands = {'combatrecorder', 'cr'}

local res = require('resources')
local json = assert(loadfile(windower.addon_path .. 'lib/json_encode.lua'))()
local storage = assert(loadfile(windower.addon_path .. 'lib/recorder.lua'))()
local recorder, character, player_id, zone
-- The installer creates these directories outside the game. Runtime directory
-- creation with an external absolute path caused all clients to hang in v0.1.0.
-- If the directory is absent, startup stays inert and reports the error.
local root = windower.addon_path .. 'data/'
local next_start, next_snapshot, next_warning, last_combat = 0, 0, 0, 0
local party_ids, dead, watched, names, ipc_seen = {}, {}, {}, {}, {}
local callback_errors, next_recasts, last_status = 0, 0, nil
local next_cache_clear = 0
local spell_watch, ability_watch = {}, {}

local function name_for(group, id)
    local entry = group and id and group[id]
    return entry and (entry.en or entry.english or entry.name)
end

local function notice(message, error)
    windower.add_to_chat(error and 123 or 207, '[CombatRecorder] ' .. message)
end

local function safe_notice(message)
    if os.time() >= next_warning then
        next_warning = os.time() + 60
        pcall(notice, message, true)
    end
end

local function capture(kind, data)
    if recorder then recorder:record(kind, data) end
end

local function entity(id)
    if not id or id == 0 then return nil end
    local cached = names[id]
    if cached then return cached end
    local mob = windower.ffxi.get_mob_by_id(id)
    local value = {id = id, name = mob and mob.name or party_ids[id], index = mob and mob.index}
    names[id] = value
    return value
end

local function mob_state(mob)
    if not mob then return nil end
    return {id = mob.id, index = mob.index, name = mob.name, hpp = mob.hpp,
        status = mob.status, claim_id = mob.claim_id, spawn_type = mob.spawn_type,
        x = mob.x, y = mob.y, z = mob.z, heading = mob.facing,
        target_index = mob.target_index,
        distance_yalms = type(mob.distance) == 'number' and math.sqrt(math.max(0, mob.distance)) or nil}
end

local function mark_death(id, source, detail)
    if not recorder or not party_ids[id] or dead[id] then return end
    dead[id] = true
    local data = {victim = entity(id), source = source, detail = detail}
    recorder:mark('party_death', data)
    capture('death', data)
    next_snapshot = 0
end

local function refresh_party(info, initial)
    local party, rows, ids = windower.ffxi.get_party() or {}, json.array(), {}
    if player_id then ids[player_id] = character end
    for i = 0, 5 do
        local member = party['p' .. i]
        if member and member.name then
            local mob = member.mob
            local id = mob and mob.id
            rows[#rows + 1] = {slot = i, id = id, name = member.name, zone = member.zone,
                hp = member.hp, hpp = member.hpp, mp = member.mp, mpp = member.mpp, tp = member.tp,
                mob = mob_state(mob)}
            if id and (not member.zone or member.zone == info.zone) then
                ids[id] = member.name
                if member.hp and member.hp > 0 then
                    dead[id] = false
                elseif member.hp == 0 and mob and (mob.status == 2 or mob.status == 3) then
                    if initial or dead[id] == nil then dead[id] = true
                    elseif not dead[id] then mark_death(id, 'party_snapshot', {status = mob.status}) end
                end
            end
        end
    end
    party_ids = ids
    return rows
end

local function recasts()
    local spells, abilities = windower.ffxi.get_spell_recasts() or {}, windower.ffxi.get_ability_recasts() or {}
    local result = {spells_seconds = {}, abilities_seconds = {}}
    for id, name in pairs(spell_watch) do
        if spells[id] ~= nil then result.spells_seconds[name] = spells[id] / 60 end
    end
    for id, name in pairs(ability_watch) do
        if abilities[id] ~= nil then result.abilities_seconds[name] = abilities[id] end
    end
    return result
end

local function snapshot(initial)
    if not recorder then return end
    local player, info = windower.ffxi.get_player(), windower.ffxi.get_info()
    if not player or not info or not info.logged_in then return end
    if zone ~= info.zone then
        capture('zone', {old = zone, new = info.zone})
        zone, watched, names, dead = info.zone, {}, {}, {}
        initial = true
    end
    player_id = player.id
    local me = windower.ffxi.get_mob_by_target('me')
    local target, battle = windower.ffxi.get_mob_by_target('t'), windower.ffxi.get_mob_by_target('bt')
    local pet = windower.ffxi.get_mob_by_target('pet')
    watched = {}
    if target then watched[target.id] = true end
    if battle then watched[battle.id] = true end
    if pet then watched[pet.id] = true end
    local rows = refresh_party(info, initial)
    local puller_target
    for _, member in ipairs(rows) do
        if member.name == 'Tackleberry' and member.mob and member.mob.target_index then
            local mob = windower.ffxi.get_mob_by_index(member.mob.target_index)
            if mob then watched[mob.id] = true; puller_target = mob_state(mob) end
        end
    end
    local vitals = player.vitals or {}
    if (player.status == 2 or player.status == 3) and vitals.hp == 0 then
        if initial then dead[player_id] = true else mark_death(player_id, 'self_snapshot', {status = player.status}) end
    elseif vitals.hp and vitals.hp > 0 then dead[player_id] = false end
    last_status = player.status
    local buffs = json.array()
    for _, id in ipairs(player.buffs or {}) do buffs[#buffs + 1] = {id = id, name = name_for(res.buffs, id)} end
    capture('snapshot', {zone = zone, zone_name = name_for(res.zones, zone), main_job = player.main_job,
        sub_job = player.sub_job, status = player.status, vitals = vitals, buffs = buffs,
        me = mob_state(me), target = mob_state(target), battle_target = mob_state(battle),
        puller_target = puller_target, pet = mob_state(pet), party = rows})
    if os.time() >= next_recasts then next_recasts = os.time() + 5; capture('recasts', recasts()) end
    next_snapshot = os.time() + ((player.status == 1 or os.time() - last_combat < 15 or recorder.incident) and 1 or 10)
end

local function prepare_watches()
    -- Direct IDs avoid scanning/materializing two complete Resource tables on
    -- the FFXI UI thread during addon load.
    for _, id in ipairs({1, 2, 3, 4, 7, 8, 59, 377, 511, 894}) do
        local spell = res.spells[id]
        if spell and spell.recast_id then spell_watch[spell.recast_id] = spell.en end
    end
    for _, id in ipairs({48, 83, 158, 192, 262, 394}) do
        local ability = res.job_abilities[id]
        if ability and ability.recast_id then ability_watch[ability.recast_id] = ability.en end
    end
end

local function start()
    if recorder or os.time() < next_start then return end
    next_start = os.time() + 10
    local player, info = windower.ffxi.get_player(), windower.ffxi.get_info()
    if not player or not player.name or not info or not info.logged_in then return end
    assert(player.name:match('^[A-Za-z]+$'), 'invalid character directory')
    local directory = root .. player.name .. '/'
    if not windower.dir_exists(directory) then
        next_start = os.time() + 60
        safe_notice('NOT recording: pre-created data directory is missing: ' .. directory)
        return
    end
    character, player_id, zone = player.name, player.id, info.zone
    party_ids, dead, watched, names, ipc_seen = {}, {}, {}, {}, {}
    recorder = storage.new({character = character, directory = directory}, {
        now = os.time, clock = os.clock, encode = json.encode, open = io.open, remove = os.remove,
        exists = windower.file_exists, list = windower.get_dir,
    })
    capture('session_start', {version = _addon.version, zone = zone, passive = true,
        action_parser_available = type(windower.packets.parse_action) == 'function'})
    snapshot(true)
    recorder:tick({version = _addon.version, recording = true, zone = zone}, true)
    if recorder.last_write > 0 then notice('Recording ' .. character .. ' to ' .. directory .. '.')
    else safe_notice('NOT writing combat data: ' .. tostring(recorder.last_error or 'unknown storage error')) end
end

local function guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            callback_errors = callback_errors + 1
            pcall(capture, 'recorder_error', {error = tostring(err):sub(1, 500)})
            safe_notice('Recorder error (combat controls untouched): ' .. tostring(err):sub(1, 160))
        end
        -- Intentionally no return value: never modifies/blocks game events.
    end
end

local function on(event, fn) windower.register_event(event, guarded(fn)) end

local function u16(data, offset)
    local a, b = data:byte(offset + 1, offset + 2)
    return a + b * 256
end
local function u32(data, offset) return u16(data, offset) + u16(data, offset + 2) * 65536 end
local death_messages = {[6] = true, [20] = true, [113] = true}
local result_fields = {'reaction', 'animation', 'effect', 'stagger', 'param', 'message',
    'has_add_effect', 'add_effect_animation', 'add_effect_effect', 'add_effect_param', 'add_effect_message',
    'has_spike_effect', 'spike_effect_animation', 'spike_effect_effect', 'spike_effect_param', 'spike_effect_message'}

local function incoming_action(original, blocked)
    if type(windower.packets.parse_action) ~= 'function' then error('native action parser unavailable') end
    local act = windower.packets.parse_action(original)
    if not act then return end
    local relevant = act.actor_id == player_id or watched[act.actor_id]
    local targets, deaths = json.array(), {}
    for i, target in ipairs(act.targets or {}) do
        if i > 32 then break end
        if target.id == player_id or watched[target.id] then relevant = true end
        local actions = json.array()
        for j, action in ipairs(target.actions or {}) do
            if j > 32 then break end
            local result = {}
            for _, field in ipairs(result_fields) do result[field] = action[field] end
            result.message_text = name_for(res.action_messages, action.message)
            actions[#actions + 1] = result
            if party_ids[target.id] and death_messages[action.message] then deaths[target.id] = action.message end
        end
        targets[#targets + 1] = {entity = entity(target.id), actions = actions}
    end
    if relevant or next(deaths) then
        last_combat = os.time()
        local label
        if act.category == 4 then label = name_for(res.spells, act.param)
        elseif act.category == 3 then label = name_for(res.weapon_skills, act.param)
        elseif act.category == 6 then label = name_for(res.job_abilities, act.param)
        elseif act.category == 11 then label = name_for(res.monster_abilities, act.param)
        elseif act.category == 8 and act.targets and act.targets[1] and act.targets[1].actions[1] then
            label = name_for(res.spells, act.targets[1].actions[1].param)
        end
        capture('action', {actor = entity(act.actor_id), category = act.category, param = act.param,
            name = label, recast = act.recast, targets = targets, blocked_for_display = blocked == true,
            original_packet = true})
    end
    for id, message in pairs(deaths) do mark_death(id, 'action_packet', {actor = entity(act.actor_id), message = message}) end
end

on('incoming chunk', function(id, original, modified, injected, blocked)
    if not recorder or injected then return end
    if id == 0x028 then incoming_action(original, blocked)
    elseif id == 0x029 and #original >= 0x1C then
        local actor, target, message = u32(original, 4), u32(original, 8), u16(original, 24) % 32768
        if actor == player_id or target == player_id or (death_messages[message] and party_ids[target]) then
            capture('action_message', {actor = entity(actor), target = entity(target), message = message,
                message_text = name_for(res.action_messages, message), param_1 = u32(original, 12),
                param_2 = u32(original, 16), blocked_for_display = blocked == true, original_packet = true})
            if death_messages[message] then mark_death(target, 'action_message', {actor = entity(actor), message = message}) end
        end
    end
end)

on('outgoing chunk', function(id, original, modified, injected, blocked)
    if not recorder or id ~= 0x01A then return end
    local data = type(modified) == 'string' and modified or original
    if #data < 16 then return end
    local category, param = u16(data, 10), u16(data, 12)
    local label = category == 3 and name_for(res.spells, param) or nil
    if category == 9 then label = name_for(res.job_abilities, param) end
    if category == 7 then label = name_for(res.weapon_skills, param) end
    capture('action_request', {target = entity(u32(data, 4)), target_index = u16(data, 8), category = category,
        param = param, name = label, injected = injected == true, blocked = blocked == true,
        modified = data ~= original})
    last_combat = os.time()
end)

for _, field in ipairs({'hp', 'mp', 'hpp', 'mpp', 'hpmax', 'mpmax'}) do
    local event_field = field
    on(field .. ' change', function(new, old)
        capture('vital_change', {field = event_field, old = old, new = new})
        if event_field == 'hp' then
            if new == 0 and old and old > 0 then
                -- A zoning/unload HP reset is not a confirmed death. The status
                -- event or server death message also catches actual transitions.
                local player = windower.ffxi.get_player()
                if player and (player.status == 2 or player.status == 3) then
                    mark_death(player_id, 'hp_change', {old_hp = old})
                end
            elseif new and new > 0 then dead[player_id or 0] = false end
        end
    end)
end
on('status change', function(new, old)
    capture('status', {old = old, new = new})
    if (new == 2 or new == 3) and old ~= 2 and old ~= 3 then mark_death(player_id, 'status_change') end
    last_status, next_snapshot = new, 0
end)
for _, event in ipairs({'gain buff', 'lose buff'}) do
    local buff_event = event
    on(event, function(id) capture('buff', {event = buff_event, id = id, name = name_for(res.buffs, id)}) end)
end
on('target change', function(index)
    capture('target', {target = mob_state(windower.ffxi.get_mob_by_index(index))})
    next_snapshot = 0
end)
on('zone change', function(new, old)
    capture('zone_event', {old = old, new = new})
    next_snapshot, names, watched, dead = 0, {}, {}, {}
end)

-- Addon diagnostics only; never subscribe to chat message or outgoing text.
local diagnostic_modes = {[123] = true, [158] = true, [160] = true, [167] = true,
    [200] = true, [207] = true, [208] = true, [209] = true}
on('incoming text', function(original, modified, mode)
    if not recorder or not diagnostic_modes[mode] or type(original) ~= 'string' then return end
    local clean = original:gsub('[%z\1-\31]', '')
    if clean:match('^%[PartyStart') or clean:match('^%[PartyCombat') or clean:match('^%[HealBot')
        or clean:match('^GearSwap:') or clean:match('^HealBot:') then
        capture('diagnostic', {text = clean:sub(1, 600), mode = mode})
    end
end)
on('ipc message', function(message)
    if not recorder or type(message) ~= 'string' then return end
    if message:sub(1, 12) ~= 'PARTYSTART2|' and message:sub(1, 13) ~= 'PARTYCOMBAT1|' then return end
    message = message:sub(1, 1200)
    if not ipc_seen[message] or os.time() - ipc_seen[message] >= 30 then
        ipc_seen[message] = os.time(); capture('automation_observed', {message = message})
    end
end)

on('prerender', function()
    start()
    if not recorder then return end
    if os.time() >= next_snapshot then snapshot(false) end
    recorder:tick({version = _addon.version, recording = true, zone = zone, status = last_status,
        callback_errors = callback_errors, action_parser_available = type(windower.packets.parse_action) == 'function'})
    if recorder.last_error then safe_notice('Disk recording impaired: ' .. recorder.last_error)
    elseif recorder.dropped > 0 then safe_notice('Recording has dropped ' .. recorder.dropped .. ' records; use //cr status.') end
    -- Bound caches even across days without zoning.
    if os.time() >= next_cache_clear then
        names, ipc_seen, next_cache_clear = {}, {}, os.time() + 60
    end
end)
on('login', function() next_start = 0; start() end)
local function finish(reason)
    if recorder then
        recorder:close({recording = false, reason = reason, version = _addon.version})
        recorder = nil
    end
    next_start = os.time() + 10
end
on('logout', function() finish('logout') end)
on('unload', function() finish('unload') end)
on('addon command', function(command, ...)
    command = (command or 'status'):lower()
    if command == 'status' then
        if not recorder then notice('NOT recording: awaiting login or storage retry. ' .. root, true); return end
        recorder:tick({version = _addon.version, recording = true, zone = zone, status = last_status,
            callback_errors = callback_errors, action_parser_available = type(windower.packets.parse_action) == 'function'}, true)
        local age = recorder.last_write > 0 and tostring(os.time() - recorder.last_write) .. 's ago' or 'NEVER'
        notice(character .. ': last disk write ' .. age .. '; queued ' .. recorder.queued_bytes .. ' bytes; dropped '
            .. recorder.dropped .. '; callback errors ' .. callback_errors .. '; write errors ' .. recorder.write_errors .. '.')
        notice(recorder.directory)
        if recorder.last_error then notice(recorder.last_error, true) end
    elseif command == 'mark' then
        if recorder then
            recorder:mark('manual', {label = table.concat({...}, ' '):sub(1, 120)})
            notice('Incident window marked; preceding history and the next two minutes will be saved.')
        end
    else notice('Commands: //cr status | //cr mark optional-note. Capture is passive and always on while loaded.') end
end)

guarded(function() prepare_watches(); start() end)()
