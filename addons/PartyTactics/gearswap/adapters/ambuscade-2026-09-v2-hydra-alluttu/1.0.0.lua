-- PartyTactics GearSwap adapter for September V2 Alluttu.
--
-- The stable host owns all global callbacks. This module exposes only a
-- finite semantic queue and fixed action IDs. It never touches action gear, changes
-- a weapon mode, selects an instrument, or accepts an arbitrary action name.

local M = {
    id='ambuscade-2026-09-v2-hydra-alluttu',
    version='1.0.0',
    controller='hydra',
    protocol=1,
}

local TARGET_NAME = 'Alluttu'
local ZONES = {[183]=true, [287]=true}
local POLL_INTERVAL = 0.10
local RETRY_DELAY = 0.40
local RESULT_TIMEOUT = 7.0
local DISPATCH_TOKEN = 1.0
local TICK_DELAY = 1.5
local EMERGENCY_HPP = 85
local CONVERT_MPP = 12
local MAX_MODEL_SIZE = 10

local ACTIONS = {
    COR = {
        food={kind='item', id=6343, name='Grape Daifuku', category=5,
            command='/item', target='self', buff_id=251,
            allow_unclaimed=true, ttl=12, max_attempts=2, priority=80},
        close={kind='weaponskill', id=221, name='Last Stand', category=3,
            command='/ws', range=19.7, min_tp=1000,
            requires_food=true,
            ttl=8, max_attempts=3, priority=30, offense=true},
    },
    PLD = {
        food={kind='item', id=6343, name='Grape Daifuku', category=5,
            command='/item', target='self', buff_id=251,
            allow_unclaimed=true, ttl=12, max_attempts=2, priority=80},
        crusade={kind='spell', id=476, name='Crusade', category=4,
            command='/ma', target='self', allow_unclaimed=true,
            ttl=12, max_attempts=3, priority=70},
        ['divine-emblem']={kind='job_ability', id=255,
            name='Divine Emblem', category=6, command='/ja', target='self',
            allow_unclaimed=true, ttl=10, max_attempts=3, priority=71},
        sentinel={kind='job_ability', id=48, name='Sentinel', category=6,
            command='/ja', target='self', allow_unclaimed=true,
            ttl=10, max_attempts=3, priority=72},
        ['pull-flash']={kind='spell', id=112, name='Flash', category=4,
            command='/ma', range=20.4, allow_unclaimed=true,
            ttl=12, max_attempts=3, priority=75},
        flash={kind='spell', id=112, name='Flash', category=4,
            command='/ma', range=20.4,
            ttl=12, max_attempts=3, priority=60},
        provoke={kind='job_ability', id=35, name='Provoke', category=6,
            command='/ja', range=20.4,
            ttl=10, max_attempts=3, priority=60},
        ['shield-bash']={kind='job_ability', id=46,
            name='Shield Bash', category=6, command='/ja', range=3.2,
            mechanic_reaction=true,
            ttl=4, max_attempts=2, priority=100},
        middle={kind='weaponskill', id=42, name='Savage Blade', category=3,
            command='/ws', range=3.2, min_tp=1000,
            requires_food=true,
            ttl=8, max_attempts=3, priority=30, offense=true},
    },
    DNC = {
        food={kind='item', id=6343, name='Grape Daifuku', category=5,
            command='/item', target='self', buff_id=251,
            allow_unclaimed=true, ttl=12, max_attempts=2, priority=80},
        ['box-step']={kind='job_ability', id=202, name='Box Step',
            category=6, command='/ja', range=3.2, min_tp=100,
            requires_food=true,
            ttl=6, max_attempts=3, priority=45, offense=true},
        stun={kind='job_ability', id=207, name='Violent Flourish',
            category=6, command='/ja', range=3.2,
            mechanic_reaction=true,
            ttl=4, max_attempts=2, priority=100},
        lead={kind='weaponskill', id=25, name='Evisceration', category=3,
            command='/ws', range=3.2, min_tp=1000,
            requires_food=true,
            ttl=8, max_attempts=3, priority=30, offense=true},
    },
    BRD = {
        clarion={kind='job_ability', id=332, name='Clarion Call',
            category=6, command='/ja', target='self', buff_id=499,
            allow_unclaimed=true, ttl=8, max_attempts=1, priority=70},
        ['fourth-song']={kind='spell', id=397, name='Valor Minuet IV',
            category=4, command='/ma', target='self',
            allow_unclaimed=true, needs_clarion=true, needs_song_core=true,
            require_party_coverage=true,
            ttl=14, max_attempts=3, priority=60},
        barparalyzra={kind='spell', id=88, name='Barparalyzra',
            category=4, command='/ma', target='self', buff_id=108,
            allow_unclaimed=true, require_party_coverage=true,
            ttl=12, max_attempts=3, priority=65},
    },
    RDM = {
        burst={kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4,
            ttl=10, max_attempts=3, priority=35, offense=true},
        nuke={kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4,
            ttl=12, max_attempts=3, priority=30, offense=true},
    },
    GEO = {
        setup={kind='spell', id=818, name='Geo-Frailty', category=4,
            command='/ma', range=20.4, needs_indi_fury=true,
            ttl=12, max_attempts=3, priority=70},
        burst={kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4,
            ttl=10, max_attempts=3, priority=35, offense=true},
        nuke={kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4,
            ttl=12, max_attempts=3, priority=30, offense=true},
    },
}

local FAILURE_MESSAGES = {
    [4]=true, [5]=true, [16]=true, [17]=true, [18]=true, [29]=true,
    [34]=true, [40]=true, [47]=true, [48]=true, [49]=true,
    [71]=true, [72]=true, [75]=true, [76]=true, [78]=true,
    [84]=true, [85]=true, [86]=true, [87]=true, [88]=true,
    [89]=true, [90]=true, [94]=true, [106]=true, [114]=true,
    [128]=true, [154]=true, [155]=true, [156]=true, [158]=true,
    [188]=true, [189]=true, [190]=true, [191]=true, [192]=true,
    [193]=true, [198]=true, [217]=true, [219]=true, [248]=true,
    [283]=true, [284]=true, [313]=true, [316]=true, [323]=true,
    [325]=true, [328]=true, [355]=true, [422]=true, [423]=true,
    [649]=true, [655]=true, [656]=true, [659]=true, [661]=true,
}

local queue_state = {
    request=nil,
    last_result='idle',
    accepted=0,
    dispatched=0,
    completed=0,
    rejected=0,
    next_poll=0,
}
local capability = nil
local prepared = {fourth_song=false, encounter_id=nil, encounter_index=nil}

if rawget(_G, 'PARTYTACTICS_HYDRA_TEST_MODE') == true then
    M._test_queue = queue_state
    M._test_prepared = prepared
end

local function chat(color, message)
    if type(add_to_chat) == 'function' then
        add_to_chat(color, '[PartyTactics Hydra] '..message)
    end
end

local function reset_prepared()
    prepared.fourth_song = false
    prepared.encounter_id = nil
    prepared.encounter_index = nil
end

local function uint32(value)
    if type(value) ~= 'string' or #value < 1 or #value > 10
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

local function nonnegative_integer(value)
    if type(value) ~= 'string' or #value < 1 or #value > 12
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    if not number or number < 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function entity_index(value)
    return type(value) == 'number' and value >= 0 and value <= 65535
        and value == math.floor(value) and value or nil
end

local function entity_id(value)
    value = tonumber(value)
    return value and value >= 1 and value <= 4294967295
        and value == math.floor(value) and value or nil
end

local function valid_token(value)
    return value == nil or value == '-'
        or type(value) == 'string' and #value >= 1 and #value <= 64
            and value:match('^[a-z0-9][a-z0-9_-]*$') ~= nil
end

local function current_player()
    local live = windower.ffxi.get_player()
    return player or live, live
end

local function current_job()
    local current, live = current_player()
    return current and current.main_job or live and live.main_job or nil
end

local function current_player_id()
    local current, live = current_player()
    return entity_id(current and current.id)
        or entity_id(live and live.id)
end

local function probe(generation, epoch_value, protocol_value)
    local epoch = nonnegative_integer(epoch_value)
    local protocol = nonnegative_integer(protocol_value)
    local job = current_job()
    if type(generation) ~= 'string' or #generation > 64
        or generation:match('^%d+%-%d+%-%d+$') == nil
        or epoch == nil or protocol ~= M.protocol or not ACTIONS[job]
    then
        return false, 'invalid or unsupported controller probe'
    end
    capability = {
        generation=generation,
        epoch=epoch,
        protocol=protocol,
        job=job,
    }
    reset_prepared()
    windower.send_command(
        ('pt __controller_ready hydra %s %d %d')
            :format(generation, epoch, protocol))
    return true, 'ready'
end

local function report_lost()
    local prior = capability
    capability = nil
    reset_prepared()
    if not prior then return end
    windower.send_command(
        ('pt __controller_lost hydra %s %d %d')
            :format(prior.generation, prior.epoch, prior.protocol))
end

local function authorized(generation, epoch_value)
    local epoch = nonnegative_integer(epoch_value)
    return type(generation) == 'string'
        and generation:match('^%d+%-%d+%-%d+$') ~= nil
        and epoch ~= nil
        and capability ~= nil
        and capability.generation == generation
        and capability.epoch == epoch
        and capability.protocol == M.protocol
        and capability.job == current_job(), epoch
end

local function dead()
    local current, live = current_player()
    local hpp = current and tonumber(current.hpp) or nil
    if hpp == nil and live and live.vitals then
        hpp = tonumber(live.vitals.hpp)
    end
    local status = current and current.status or live and live.status or nil
    return hpp ~= nil and hpp <= 0
        or status == 2
        or type(status) == 'string'
            and status:lower():find('dead', 1, true) ~= nil
end

local function party_claimed(target)
    local claim = target and tonumber(target.claim_id)
    if not claim or claim == 0 then return false end
    local current = windower.ffxi.get_player()
    if current and tonumber(current.id) == claim then return true end
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table'
            and (type(key) ~= 'string' or key:match('^p[0-5]$'))
        then
            local member_id = member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)
            if member_id == claim then return true end
        end
    end
    return false
end

local function intended_party_ids()
    local party = windower.ffxi.get_party() or {}
    local ids, seen = {}, {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        local id = type(member) == 'table'
            and entity_id(member.mob and member.mob.id
                or member.mob_id or member.id) or nil
        if not id or seen[id] then return nil end
        seen[id] = true
        ids[#ids + 1] = id
    end
    return ids
end

local function unclaimed(target)
    local claim = tonumber(target and target.claim_id)
    return claim == nil or claim == 0
end

local function live_target(target, request)
    return type(target) == 'table'
        and target.id == request.id
        and entity_index(target.index) ~= nil
        and entity_index(request.index) ~= nil
        and target.index == request.index
        and target.name == TARGET_NAME
        and target.spawn_type == 16
        and target.valid_target
        and type(target.hpp) == 'number' and target.hpp > 0
end

local function has_buff_id(wanted)
    local live = windower.ffxi.get_player()
    for _, id in pairs(live and live.buffs or {}) do
        if tonumber(id) == wanted then return true end
    end
    return false
end

local function clear(reason, announce)
    local request = queue_state.request
    queue_state.request = nil
    queue_state.last_result = reason or 'cancelled'
    if request and announce then
        chat(123, ('%s #%d cancelled: %s.')
            :format(request.semantic, request.id,
                tostring(reason or 'cancelled')))
    end
end

local function context()
    local request = queue_state.request
    if not request then return nil end
    if not authorized(request.generation, tostring(request.epoch)) then
        clear('current PartyTactics authority was revoked', false)
        return nil
    end
    local now = os.clock()
    if now >= request.expires then
        clear(request.last_blocker
            and ('expired while '..request.last_blocker)
            or 'expired before a legal action window', true)
        return nil
    end
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or not ZONES[info.zone]
        or info.zone ~= request.zone
    then
        clear('zone or login state changed', false)
        return nil
    end
    if dead() then
        clear('character is dead', false)
        return nil
    end
    if current_job() ~= request.job then
        clear('main job changed', true)
        return nil
    end
    local target = windower.ffxi.get_mob_by_id(request.id)
    if not target then
        request.last_blocker = 'exact Alluttu entity is not visible'
        return request, nil
    end
    if not live_target(target, request) then
        clear('exact Alluttu entity died or changed', false)
        return nil
    end
    local claimed = party_claimed(target)
    if claimed then
        request.claim_seen = true
    elseif not unclaimed(target) then
        clear('Alluttu acquired a foreign claim', false)
        return nil
    elseif not request.allow_unclaimed or request.claim_seen then
        clear('party claim was lost or never established', false)
        return nil
    end
    return request, target
end

local function resource(action)
    if not action or type(res) ~= 'table' then return nil end
    local collection
    if action.kind == 'weaponskill' then
        collection = res.weapon_skills
    elseif action.kind == 'job_ability' then
        collection = res.job_abilities
    elseif action.kind == 'spell' then
        collection = res.spells
    elseif action.kind == 'item' then
        collection = res.items
    end
    local found = collection and collection[action.id] or nil
    if not found or tonumber(found.id) ~= action.id
        or (found.en or found.english) ~= action.name
    then
        return nil
    end
    return found
end

local function collection_has(collection, id)
    if type(collection) ~= 'table' then return false end
    if collection[id] == true or collection[id] == 1
        or (type(collection[id]) == 'number'
            or type(collection[id]) == 'string')
            and tonumber(collection[id]) == id
    then
        return true
    end
    for key, value in pairs(collection) do
        if (type(value) == 'number' or type(value) == 'string')
                and tonumber(value) == id
            or (value == true or value == 1) and tonumber(key) == id
        then
            return true
        end
    end
    return false
end

local function learned(action)
    if action.kind == 'item' then return true end
    if action.kind == 'spell' then
        return collection_has(windower.ffxi.get_spells() or {}, action.id)
    end
    local abilities = windower.ffxi.get_abilities() or {}
    local collection = action.kind == 'weaponskill'
        and abilities.weapon_skills or abilities.job_abilities
    return collection_has(collection or {}, action.id)
end

local function function_true(name, ...)
    local callback = _G[name]
    if type(callback) ~= 'function' then return false end
    local ok, value = pcall(callback, ...)
    return ok and value == true
end

local function recovery_needed()
    local buffs = buffactive or {}
    return buffs.Doom or buffs.doom or buffs.Silence or buffs.silence
        or buffs.Paralysis or buffs.paralysis or buffs.Curse or buffs.curse
end

local function lowest_party_hpp()
    local lowest = 100
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if type(member) ~= 'table' or type(member.hpp) ~= 'number' then
            return 0
        end
        lowest = math.min(lowest, member.hpp)
    end
    return lowest
end

local function emergency_priority(job)
    if recovery_needed() then return true end
    if job ~= 'RDM' and job ~= 'PLD' and job ~= 'DNC'
        and job ~= 'GEO' and job ~= 'BRD'
    then
        return false
    end
    local current = player or {}
    if (tonumber(current.hpp) or 100) < EMERGENCY_HPP then return true end
    if lowest_party_hpp() < EMERGENCY_HPP then return true end
    return job == 'RDM'
        and (tonumber(current.mpp) or 100) <= CONVERT_MPP
        and (tonumber(current.hpp) or 100) >= EMERGENCY_HPP
end

local function distance(target)
    local squared = target and tonumber(target.distance)
    if not squared or squared < 0 then return nil end
    return math.sqrt(squared)
end

local function legal_range(target, action)
    local size = tonumber(target and target.model_size) or 0
    size = math.max(0, math.min(MAX_MODEL_SIZE, size))
    return (tonumber(action.range) or 0) + size
end

local function nonbusy_blocker(request, target, action, found)
    if not target then return 'waiting for the exact Alluttu entity' end
    if not found then return 'fixed action resource is unavailable' end
    if not learned(action) then
        return action.name..' is not currently learned or granted'
    end
    if action.buff_id and not action.require_party_coverage
        and has_buff_id(action.buff_id)
    then
        return 'fixed status is already active'
    end
    if action.requires_food and not has_buff_id(251) then
        return 'waiting for exact Food status (buff 251)'
    end
    if action.needs_clarion and not has_buff_id(499) then
        return 'waiting for exact Clarion Call status (buff 499)'
    end
    if action.needs_song_core
        and (not has_buff_id(214) or not has_buff_id(198)
            or not has_buff_id(199))
    then
        return 'waiting for March, Minuet, and Madrigal song statuses'
    end
    if action.needs_indi_fury and not has_buff_id(549) then
        return 'waiting for exact Indi-Fury status (buff 549)'
    end
    if action.target ~= 'self' then
        local observed = distance(target)
        local maximum = legal_range(target, action)
        if not observed or observed > maximum then
            return ('Alluttu is outside %.1fy range'):format(maximum)
        end
    end
    local current = player or {}
    if (action.kind == 'weaponskill'
            or action.kind == 'job_ability' and action.offense)
        and current.status ~= 'Engaged'
    then
        return 'waiting for combat engagement'
    end
    if action.min_tp and (tonumber(current.tp) or 0) < action.min_tp then
        return ('waiting for %d TP'):format(action.min_tp)
    end
    if action.kind == 'spell'
        and (tonumber(current.mp) or 0) < (tonumber(found.mp_cost) or 0)
    then
        return 'insufficient MP for '..action.name
    end
    if action.kind == 'spell' then
        local recasts = windower.ffxi.get_spell_recasts() or {}
        local recast = tonumber(recasts[found.recast_id or found.id]) or 0
        local threshold = tonumber(spell_latency) or tonumber(latency) or 1
        if recast >= threshold then return action.name..' is on recast' end
        if type(silent_can_use) == 'function'
            and not function_true('silent_can_use', action.id)
        then
            return action.name..' is blocked by spell status/access'
        end
    elseif action.kind == 'job_ability' then
        local recasts = windower.ffxi.get_ability_recasts() or {}
        local recast = tonumber(recasts[found.recast_id]) or 0
        if recast >= (tonumber(latency) or 1) then
            return action.name..' is on recast'
        end
        if function_true('silent_check_amnesia') then
            return 'amnesia prevents '..action.name
        end
    end
    if moving then return 'character is moving' end
    if function_true('silent_check_disable') then
        return 'character is incapacitated'
    end
    if recovery_needed() and not action.mechanic_reaction then
        return 'status recovery has priority'
    end
    if action.offense and lowest_party_hpp() < EMERGENCY_HPP then
        return 'party health is below the offense floor'
    end
    if not action.mechanic_reaction and emergency_priority(request.job) then
        return 'emergency healing or Convert has priority'
    end
    if os.clock() < (request.next_attempt or 0) then
        return 'bounded retry backoff'
    end
    return nil
end

local function busy_blocker()
    if type(midaction) == 'function' and midaction() then
        return 'another action is in progress'
    end
    local now = os.clock()
    if type(tickdelay) == 'number' and now < tickdelay then
        return 'GearSwap tick delay'
    end
    if type(next_cast) == 'number' and now < next_cast then
        return 'current action recovery'
    end
    return nil
end

local function evaluate()
    local request, target = context()
    if not request then return nil, nil, nil, 'idle' end
    local action = ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if not action then
        clear('fixed job/action mapping disappeared', true)
        return nil, nil, nil, 'idle'
    end
    if action.buff_id and not action.require_party_coverage
        and has_buff_id(action.buff_id)
    then
        queue_state.completed = queue_state.completed + 1
        clear(action.name..' status observed', false)
        return nil, nil, nil, 'idle'
    end
    if request.semantic == 'fourth-song' and prepared.fourth_song then
        queue_state.completed = queue_state.completed + 1
        clear('fixed fourth song already completed', false)
        return nil, nil, nil, 'idle'
    end
    local now = os.clock()
    if request.inflight_until then
        if now < request.inflight_until then
            request.last_blocker = 'awaiting action result'
            return request, target, action, 'inflight'
        end
        request.inflight_until = nil
        request.dispatch_token_until = nil
        request.last_result = 'no matching action result received'
        request.next_attempt = now + RETRY_DELAY
        if request.attempts >= action.max_attempts then
            clear(('no result after %d attempt(s)'):format(request.attempts),
                true)
            return nil, nil, nil, 'idle'
        end
    end
    local found = resource(action)
    local blocker = nonbusy_blocker(request, target, action, found)
    if blocker then
        request.last_blocker = blocker
        return request, target, action, 'blocked'
    end
    local busy = busy_blocker()
    if busy then
        request.last_blocker = busy
        return request, target, action, 'busy'
    end
    request.last_blocker = nil
    return request, target, action, 'ready'
end

local function dispatch(request, action)
    local now = os.clock()
    request.attempts = request.attempts + 1
    request.inflight_until = now + RESULT_TIMEOUT
    request.dispatch_token_until = now + DISPATCH_TOKEN
    request.last_result = 'awaiting action result'
    request.last_blocker = nil
    local target_token = action.target == 'self'
        and '<me>' or tostring(request.id)
    windower.chat.input(action.command..' "'..action.name..'" '
        ..target_token)
    local prior = type(tickdelay) == 'number' and tickdelay or 0
    tickdelay = math.max(prior, now + TICK_DELAY)
    queue_state.dispatched = queue_state.dispatched + 1
    queue_state.last_result = action.name..' dispatched'
    chat(158, ('%s -> %s dispatched (%d/%d).')
        :format(action.name,
            action.target == 'self' and 'self'
                or ('Alluttu #'..tostring(request.id)),
            request.attempts, action.max_attempts))
    return true
end

local function poll()
    local request, _, action, state = evaluate()
    if not request then return false end
    if state == 'ready' then return dispatch(request, action) end
    return state == 'busy' or state == 'inflight'
end

local function reserve(semantic, value, generation, epoch_value,
    request_token, subject_value)
    local allowed, epoch = authorized(generation, epoch_value)
    if not allowed then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'current-generation PartyTactics authority is required'
    end
    if subject_value ~= nil then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'Hydra actions accept no secondary subject'
    end
    if not valid_token(request_token) then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'request token is malformed'
    end
    local job = current_job()
    local action = job and ACTIONS[job] and ACTIONS[job][semantic] or nil
    if not action then
        queue_state.rejected = queue_state.rejected + 1
        return false, ('%s cannot perform semantic action %s')
            :format(tostring(job or 'unknown job'), tostring(semantic))
    end
    local id = uint32(value)
    if not id then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'encounter ID must be a uint32 integer'
    end
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    local index = target and entity_index(target.index) or nil
    local candidate = {id=id, index=index}
    if not info or not info.logged_in or not ZONES[info.zone]
        or not target or not index
        or not live_target(target, candidate)
        or not party_claimed(target) and not unclaimed(target)
        or not action.allow_unclaimed and not party_claimed(target)
    then
        queue_state.rejected = queue_state.rejected + 1
        return false,
            'target must be the exact live unclaimed or party-claimed Alluttu allowed by this semantic'
    end
    if prepared.encounter_id ~= id or prepared.encounter_index ~= index then
        reset_prepared()
        prepared.encounter_id = id
        prepared.encounter_index = index
    end
    if not resource(action) then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'fixed action resource is unavailable'
    end
    if not learned(action) then
        queue_state.rejected = queue_state.rejected + 1
        return false, action.name..' is not currently learned or granted'
    end
    local player_id = current_player_id()
    if action.target == 'self' and not player_id then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'local character identity is unavailable'
    end
    local expected_result_ids = action.require_party_coverage
        and intended_party_ids() or nil
    if action.require_party_coverage and not expected_result_ids then
        queue_state.rejected = queue_state.rejected + 1
        return false,
            'all six intended party identities are required for AoE result coverage'
    end

    if action.buff_id and not action.require_party_coverage
        and has_buff_id(action.buff_id)
    then
        return true, action.name..' status already active'
    end
    if semantic == 'fourth-song' and prepared.fourth_song then
        return true, 'fixed fourth song already completed'
    end

    local existing = queue_state.request
    if existing and existing.id == id and existing.index == target.index
        and existing.zone == info.zone and existing.job == job
        and existing.semantic == semantic
        and existing.generation == generation and existing.epoch == epoch
    then
        return true, 'already queued'
    end
    if existing then
        if existing.inflight_until then
            queue_state.rejected = queue_state.rejected + 1
            return false, 'another Hydra action is already in flight'
        end
        local old = ACTIONS[existing.job]
            and ACTIONS[existing.job][existing.semantic] or nil
        if not old or action.priority <= old.priority then
            queue_state.rejected = queue_state.rejected + 1
            return false, 'another Hydra action is already queued'
        end
        clear('preempted by higher-priority '..semantic, false)
    end

    local now = os.clock()
    queue_state.request = {
        semantic=semantic,
        job=job,
        action_id=action.id,
        generation=generation,
        epoch=epoch,
        id=id,
        index=index,
        zone=info.zone,
        result_id=action.target == 'self' and player_id or id,
        expected_result_ids=expected_result_ids,
        allow_unclaimed=action.allow_unclaimed == true,
        claim_seen=party_claimed(target),
        request_token=request_token,
        created=now,
        expires=now + action.ttl,
        attempts=0,
        next_attempt=0,
        last_result='queued',
    }
    queue_state.accepted = queue_state.accepted + 1
    queue_state.last_result = semantic..' queued'
    return true, 'queued'
end

local RECOVERY_ITEMS = {
    ['Echo Drops']=true,
    Remedy=true,
    Panacea=true,
    ['Holy Water']=true,
}
local RECOVERY_SPELLS = {
    Erase=true, Poisona=true, Paralyna=true, Silena=true,
    Blindna=true, Stona=true, Viruna=true, Cursna=true,
}

local function action_name(spell)
    return spell and (spell.english or spell.en or spell.name) or nil
end

local function emergency_action(spell)
    if not spell then return false end
    local name = action_name(spell)
    if spell.action_type == 'Item' and RECOVERY_ITEMS[name] then return true end
    local job = current_job()
    if job == 'RDM' and name == 'Convert' then return true end
    if type(name) == 'string'
        and (name:match('^Curing Waltz') or name:match('^Divine Waltz')
            or name == 'Healing Waltz' or name == 'No Foot Rise'
            or name == 'Reverse Flourish')
    then
        return true
    end
    if (job == 'RDM' or job == 'PLD' or job == 'GEO' or job == 'BRD')
        and type(name) == 'string'
    then
        if RECOVERY_SPELLS[name] then return true end
        if name == 'Cure' or name:match('^Cure [IVX]+$')
            or name:match('^Cura')
        then
            local hpp = spell.target and tonumber(spell.target.hpp) or nil
            return hpp == nil or hpp <= EMERGENCY_HPP
                or emergency_priority(job)
        end
    end
    return false
end

local function own_dispatch(spell, phase)
    local request = queue_state.request
    if not request or not request.inflight_until or not spell
        or tonumber(spell.id) ~= request.action_id
    then
        return false
    end
    local target_id = spell.target and tonumber(spell.target.id) or nil
    if target_id == request.result_id then return true end
    return os.clock() <= (request.dispatch_token_until or 0)
        and (phase == 'pretarget' or target_id == nil)
end

local function blocks_action(spell, phase)
    local request, _, _, state = evaluate()
    if not request then return false end
    if own_dispatch(spell, phase) or emergency_action(spell) then return false end
    if request.job == 'DNC' then return true end
    if request.job == 'GEO' and request.semantic == 'setup'
        and request.inflight_until and action_name(spell) == 'Full Circle'
    then
        return false
    end
    return state == 'ready' or state == 'busy' or state == 'inflight'
end

function M.activate()
    return true
end

function M.pre_tick()
    return poll()
end

function M.user_job_tick()
    return poll()
end

function M.filter_pretarget(spell, spellMap, eventArgs)
    return blocks_action(spell, 'pretarget')
end

function M.filter_precast(spell, spellMap, eventArgs)
    return blocks_action(spell, 'precast')
end

function M.job_aftercast(spell, spellMap, eventArgs)
    local request = queue_state.request
    if request and request.inflight_until and spell
        and tonumber(spell.id) == request.action_id and spell.interrupted
    then
        local action = ACTIONS[request.job]
            and ACTIONS[request.job][request.semantic] or nil
        request.inflight_until = nil
        request.dispatch_token_until = nil
        request.last_result = 'interrupted'
        if not action or request.attempts >= action.max_attempts then
            clear(('interrupted after %d attempt(s)')
                :format(request.attempts), true)
        else
            request.next_attempt = os.clock() + RETRY_DELAY
        end
    end
end

function M.handle_action(controller, semantic, arguments)
    if type(controller) ~= 'string' or controller:lower() ~= M.controller then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'unsupported controller'
    end
    if type(semantic) ~= 'string' then
        queue_state.rejected = queue_state.rejected + 1
        return false, 'semantic action is required'
    end
    local requested = semantic:lower()
    local args = type(arguments) == 'table' and arguments or {}
    if requested == 'probe' then
        local accepted, reason = probe(args[1], args[2], args[3])
        if not accepted then chat(123, 'probe rejected: '..tostring(reason)..'.') end
        return accepted, reason
    elseif requested == 'cancel' then
        local id = uint32(args[1])
        if not id or not authorized(args[2], args[3])
            or args[4] ~= nil and args[4] ~= '-'
        then
            queue_state.rejected = queue_state.rejected + 1
            return false, 'cancel requires exact target and current authority'
        end
        local request = queue_state.request
        if request and request.id ~= id then
            queue_state.rejected = queue_state.rejected + 1
            return false, 'cancel target does not match queued Alluttu'
        end
        clear('profile cancelled', false)
        reset_prepared()
        return true, 'cancelled'
    elseif requested == 'status' then
        return true, M.status()
    end
    local accepted, reason = reserve(requested, args[1], args[2], args[3],
        args[4], args[5])
    if not accepted then
        chat(123, 'request rejected: '..tostring(reason)..'.')
        return false, reason
    end
    poll()
    return true, reason
end

function M.status()
    local request = queue_state.request
    local current = request and (request.semantic..'#'..tostring(request.id))
        or 'idle'
    return ('queue=%s accepted=%d dispatched=%d completed=%d rejected=%d')
        :format(current, queue_state.accepted, queue_state.dispatched,
            queue_state.completed, queue_state.rejected)
end

function M.deactivate(reason)
    report_lost()
    clear(reason or 'adapter deactivated', false)
    return true
end

function M.file_unload(...)
    return M.deactivate('GearSwap job file unloaded')
end

function M.action_event(packet)
    local request = queue_state.request
    if not request or not request.inflight_until or type(packet) ~= 'table' then
        return
    end
    local current = windower.ffxi.get_player()
    if not current or tonumber(packet.actor_id) ~= tonumber(current.id) then
        return
    end
    local action = ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if not action or packet.category ~= action.category
        or tonumber(packet.param) ~= action.id
    then
        return
    end
    local results = {}
    for _, target in ipairs(packet.targets or {}) do
        local id = entity_id(target.id)
        if id then results[id] = target.actions and target.actions[1] or nil end
    end

    local failure
    if request.expected_result_ids then
        local missing = 0
        for _, id in ipairs(request.expected_result_ids) do
            local result = results[id]
            local message = result and tonumber(result.message) or nil
            if not result or FAILURE_MESSAGES[message] then
                missing = missing + 1
            end
        end
        if missing > 0 then
            failure = ('AoE result missed %d of %d intended party members')
                :format(missing, #request.expected_result_ids)
        end
    else
        local result = results[tonumber(request.result_id)]
        if not result then return end
        local message = tonumber(result.message)
        if FAILURE_MESSAGES[message] then failure = 'server rejected action' end
    end

    if failure then
        request.inflight_until = nil
        request.dispatch_token_until = nil
        request.last_result = failure
        if request.attempts >= action.max_attempts then
            clear(('%s failed after %d attempt(s): %s')
                :format(action.name, request.attempts, failure), true)
        else
            request.next_attempt = os.clock() + RETRY_DELAY
        end
        return
    end
    if request.semantic == 'fourth-song' then
        prepared.fourth_song = true
    end
    queue_state.completed = queue_state.completed + 1
    chat(158, action.name..' completed through GearSwap.')
    clear(action.name..' completed', false)
end

function M.prerender()
    if not queue_state.request then return false end
    local now = os.clock()
    if now < queue_state.next_poll then return false end
    queue_state.next_poll = now + POLL_INTERVAL
    return poll()
end

function M.zone_change(...)
    reset_prepared()
    clear('zone changed', false)
end

function M.logout(...)
    reset_prepared()
    clear('logout', false)
end

function M.unload(...)
    return M.deactivate('GearSwap unloaded')
end

function M.status_change(new_status, ...)
    if new_status == 2 or type(new_status) == 'string'
        and new_status:lower():find('dead', 1, true)
    then
        clear('character died', false)
    end
end

return M
