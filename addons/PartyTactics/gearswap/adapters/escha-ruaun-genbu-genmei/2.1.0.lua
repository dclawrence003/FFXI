-- PartyTactics GearSwap adapter: bounded, authority-bound action queue for the
-- Escha Ru'Aun Genbu encounter.
--
-- This file returns a module table. The shared PartyTactics GearSwap host is
-- the only owner of global GearSwap callbacks and Windower event handlers; it
-- routes fixed semantic actions and lifecycle/event notifications here. The
-- adapter never accepts caller-provided spell, ability, or weaponskill names.
-- GearSwap's ordinary action resolver and the character's native job file
-- remain the sole owners of action gear.

local M = {
    id = 'escha-ruaun-genbu-genmei',
    version = '2.1.0',
    controller = 'genmei',
    protocol = 1,
}

local PTGS_GENMEI_TARGET_NAME = 'Genbu'
local PTGS_GENMEI_ZONE = 289
local PTGS_GENMEI_PROTOCOL = M.protocol
local PTGS_GENMEI_POLL_INTERVAL = 0.10
local PTGS_GENMEI_RETRY_DELAY = 0.40
local PTGS_GENMEI_RESULT_TIMEOUT = 7.0
local PTGS_GENMEI_DISPATCH_TOKEN = 1.0
local PTGS_GENMEI_TICK_DELAY = 1.5
-- Match the fight runtime's chain floor. If anyone drops below this point,
-- release the action slot immediately so the established PLD/RDM healing
-- controllers can recover the party before damage automation resumes.
local PTGS_GENMEI_EMERGENCY_HPP = 70
local PTGS_GENMEI_CONVERT_MPP = 12
local PTGS_GENMEI_MAX_MODEL_SIZE = 10

-- IDs are deliberately fixed.  Looking actions up by caller-provided names
-- would turn this small semantic interface into a general remote-action API.
local PTGS_GENMEI_ACTIONS = {
    -- This is a private, probe-triggered preparation action, not a public
    -- fight verb.  It proves Barwater through the ordinary GearSwap action
    -- path before a Genbu entity exists, while leaving Barney's native job
    -- file as the sole owner of casting gear and every instrument decision.
    BRD = {
        barwatera_prepare = {
            kind='spell', id=71, name='Barwatera', category=4,
            command='/ma', target='self', buff_id=105,
            pre_encounter=true, auto_probe=true,
            ttl=12, max_attempts=3, priority=20,
        },
        ['recover-songs'] = {
            kind='fixed_recovery',
            buff_ids={214, 197, 196},
        },
    },
    DNC = {
        lead = {
            kind='weaponskill', id=25, name='Evisceration', category=3,
            command='/ws', range=3.2, min_tp=1000, ttl=8, max_attempts=3,
            priority=10,
        },
    },
    PLD = {
        crusade = {
            kind='spell', id=476, name='Crusade', category=4,
            command='/ma', target='self',
            ttl=12, max_attempts=3, priority=20,
        },
        ['divine-emblem'] = {
            kind='job_ability', id=255, name='Divine Emblem', category=6,
            command='/ja', target='self',
            ttl=10, max_attempts=3, priority=25,
        },
        sentinel = {
            kind='job_ability', id=48, name='Sentinel', category=6,
            command='/ja', target='self',
            ttl=10, max_attempts=3, priority=30,
        },
        flash = {
            kind='spell', id=112, name='Flash', category=4,
            command='/ma', range=12, ttl=12, max_attempts=3,
            priority=40,
        },
        provoke = {
            kind='job_ability', id=35, name='Provoke', category=6,
            command='/ja', range=11, ttl=10, max_attempts=3,
            priority=40,
        },
        middle = {
            kind='weaponskill', id=42, name='Savage Blade', category=3,
            command='/ws', range=3.2, min_tp=1000, ttl=8, max_attempts=3,
            priority=10,
        },
    },
    COR = {
        ['recover-rolls'] = {
            kind='fixed_recovery',
            buff_ids={321, 314},
        },
        close = {
            kind='weaponskill', id=221, name='Last Stand', category=3,
            command='/ws', range=19.7, min_tp=1000, ttl=8, max_attempts=3,
            priority=10,
        },
        proc = {
            kind='job_ability', id=129, name='Thunder Shot', category=6,
            command='/ja', range=20.4, ttl=10, max_attempts=3,
            priority=30,
        },
    },
    GEO = {
        setup = {
            kind='spell', id=820, name='Geo-Malaise', category=4,
            command='/ma', range=20.4, ttl=12, max_attempts=3,
            priority=20,
        },
        proc = {
            kind='spell', id=164, name='Thunder', category=4,
            command='/ma', range=20.4, ttl=10, max_attempts=3,
            priority=30,
        },
        burst = {
            kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4, ttl=10, max_attempts=3,
            priority=20,
        },
    },
    RDM = {
        dispel = {
            kind='spell', id=260, name='Dispel', category=4,
            command='/ma', range=20.4, ttl=12, max_attempts=3,
            priority=40,
        },
        proc = {
            kind='spell', id=164, name='Thunder', category=4,
            command='/ma', range=20.4, ttl=10, max_attempts=3,
            priority=30,
        },
        burst = {
            kind='spell', id=167, name='Thunder IV', category=4,
            command='/ma', range=20.4, ttl=10, max_attempts=3,
            priority=20,
        },
    },
}

-- Terminal action-message failures must never be mistaken for a completed
-- reservation. In particular 78 (out of range) and 84 (paralyzed) are action
-- interruptions even when the actor/category/resource fields all match.
local PTGS_GENMEI_FAILURE_MESSAGES = {
    [4]=true, [5]=true, [16]=true, [17]=true, [18]=true, [29]=true,
    [34]=true, [40]=true,
    [47]=true, [48]=true, [49]=true, [71]=true, [72]=true,
    [75]=true, [76]=true, [78]=true, [84]=true, [85]=true, [86]=true,
    [87]=true, [88]=true,
    [89]=true, [90]=true, [94]=true, [106]=true, [114]=true,
    [128]=true, [154]=true, [155]=true, [156]=true, [158]=true,
    [188]=true, [189]=true, [190]=true, [191]=true, [192]=true,
    [193]=true, [198]=true,
    [217]=true, [219]=true, [248]=true, [283]=true, [284]=true,
    [313]=true, [316]=true, [323]=true, [325]=true, [328]=true,
    [355]=true, [422]=true, [423]=true,
    [649]=true, [655]=true, [656]=true, [659]=true, [661]=true,
}

-- Dispel reporting "no effect" means Harden Shell is no longer present (or
-- another party member removed it first).  That is a resolved dispel request,
-- not a reason to recast.  These messages remain failures for every other
-- semantic action.
local PTGS_GENMEI_DISPEL_RESOLVED_MESSAGES = {
    [75]=true, [283]=true, [659]=true,
}

local ptgs_genmei_queue = {
    request = nil,
    last_result = 'idle',
    accepted = 0,
    dispatched = 0,
    completed = 0,
    rejected = 0,
    next_poll = 0,
}

-- A capability belongs to one exact PartyTactics generation.  It is not a
-- combat command and grants no authority by itself; its only purpose is to
-- prove to the local PartyTactics preflight that this reviewed queue is the
-- code GearSwap actually loaded for the assigned job.
local ptgs_genmei_capability = nil
-- After the first reviewed Geo-Malaise completion, Achoo retains only this
-- exact encounter binding. If the luopan disappears while the same claimed
-- Genbu is alive, the fixed setup request renews it automatically; no caller
-- can supply a spell name or a replacement target.
local ptgs_genmei_geo_binding = nil
local ptgs_genmei_recovery_tokens = {}
local ptgs_genmei_recovery_token_order = {}
local PTGS_GENMEI_MAX_RECOVERY_TOKENS = 32

-- Production state stays local. Standalone adapter tests may inspect the
-- returned module's read-only-by-convention queue reference without creating
-- or replacing any GearSwap global.
if rawget(_G, 'PARTYTACTICS_GENMEI_TEST_MODE') == true then
    M._test_queue = ptgs_genmei_queue
end

local function ptgs_genmei_chat(color, message)
    if type(add_to_chat) == 'function' then
        add_to_chat(color, '[PartyTactics Genmei] '..message)
    end
end

local function ptgs_genmei_uint32(value)
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

local function ptgs_genmei_nonnegative_integer(value)
    if type(value) ~= 'string' or #value == 0 or #value > 12
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

local function ptgs_genmei_player()
    local live = windower.ffxi.get_player()
    return player or live, live
end

local function ptgs_genmei_job()
    local current, live = ptgs_genmei_player()
    return current and current.main_job
        or live and live.main_job
        or nil
end

local function ptgs_genmei_probe(generation, epoch_value, protocol_value)
    local epoch = ptgs_genmei_nonnegative_integer(epoch_value)
    local protocol = ptgs_genmei_nonnegative_integer(protocol_value)
    local job = ptgs_genmei_job()
    if type(generation) ~= 'string' or #generation > 64
        or generation:match('^%d+%-%d+%-%d+$') == nil
        or epoch == nil or protocol ~= PTGS_GENMEI_PROTOCOL
        or not PTGS_GENMEI_ACTIONS[job]
    then
        return false, 'invalid or unsupported controller probe'
    end
    ptgs_genmei_capability = {
        generation=generation, epoch=epoch, protocol=protocol, job=job,
    }
    windower.send_command(
        ('pt __controller_ready genmei %s %d %d')
            :format(generation, epoch, protocol))
    return true
end

local function ptgs_genmei_report_lost()
    local capability = ptgs_genmei_capability
    ptgs_genmei_capability = nil
    ptgs_genmei_geo_binding = nil
    ptgs_genmei_recovery_tokens = {}
    ptgs_genmei_recovery_token_order = {}
    if not capability then return end
    windower.send_command(
        ('pt __controller_lost genmei %s %d %d')
            :format(capability.generation, capability.epoch,
                capability.protocol))
end

local function ptgs_genmei_authorized(generation, epoch_value)
    local epoch = ptgs_genmei_nonnegative_integer(epoch_value)
    local capability = ptgs_genmei_capability
    return type(generation) == 'string'
        and generation:match('^%d+%-%d+%-%d+$') ~= nil
        and epoch ~= nil
        and capability ~= nil
        and capability.generation == generation
        and capability.epoch == epoch
        and capability.protocol == PTGS_GENMEI_PROTOCOL
        and capability.job == ptgs_genmei_job(), epoch
end

local function ptgs_genmei_dead()
    local current, live = ptgs_genmei_player()
    local hpp = current and tonumber(current.hpp) or nil
    if hpp == nil and live and live.vitals then
        hpp = tonumber(live.vitals.hpp)
    end
    local status = current and current.status
        or live and live.status
        or nil
    return (hpp ~= nil and hpp <= 0)
        or status == 2
        or (type(status) == 'string'
            and status:lower():find('dead', 1, true) ~= nil)
end

local function ptgs_genmei_party_claimed(target)
    local claim = target and tonumber(target.claim_id)
    if not claim or claim == 0 then return false end

    local current = windower.ffxi.get_player()
    if current and tonumber(current.id) == claim then return true end

    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table'
            and (type(key) ~= 'string' or key:match('^p[0-5]$'))
        then
            local member_id = member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id)
                or tonumber(member.id)
            if member_id == claim then return true end
        end
    end
    return false
end

local function ptgs_genmei_live_target(target, request)
    return type(target) == 'table'
        and target.id == request.id
        and target.index == request.index
        and type(target.name) == 'string'
        and target.name:lower() == PTGS_GENMEI_TARGET_NAME:lower()
        and target.spawn_type == 16
        and target.valid_target
        and type(target.hpp) == 'number'
        and target.hpp > 0
end

local function ptgs_genmei_clear(reason, announce)
    local request = ptgs_genmei_queue.request
    ptgs_genmei_queue.request = nil
    ptgs_genmei_queue.last_result = reason or 'cancelled'
    if request and announce then
        ptgs_genmei_chat(123,
            ('%s #%d cancelled: %s.')
                :format(request.semantic, request.id,
                    tostring(reason or 'cancelled')))
    end
end

local function ptgs_genmei_context()
    local request = ptgs_genmei_queue.request
    if not request then return nil end

    if not ptgs_genmei_authorized(request.generation,
        tostring(request.epoch))
    then
        ptgs_genmei_clear('current PartyTactics authority was revoked', false)
        return nil
    end

    local now = os.clock()
    if now >= request.expires then
        ptgs_genmei_clear(request.last_blocker
            and ('expired while '..request.last_blocker)
            or 'expired before a legal action window', true)
        return nil
    end

    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or info.zone ~= PTGS_GENMEI_ZONE
        or info.zone ~= request.zone
    then
        ptgs_genmei_clear('zone or login state changed', false)
        return nil
    end
    if ptgs_genmei_dead() then
        ptgs_genmei_clear('character is dead', false)
        return nil
    end
    if ptgs_genmei_job() ~= request.job then
        ptgs_genmei_clear('main job changed', true)
        return nil
    end

    -- Barney's private Barwatera preparation is deliberately useful before
    -- Genbu is spawned.  It is still bound to the current capability,
    -- character, job, login state, and Ru'Aun zone; it simply has no enemy
    -- identity to validate yet.
    if request.pre_encounter then
        local current, live = ptgs_genmei_player()
        local player_id = tonumber(current and current.id)
            or tonumber(live and live.id)
        if not player_id or player_id ~= request.result_id then
            ptgs_genmei_clear('character identity changed', false)
            return nil
        end
        return request, {id=player_id, distance=0, model_size=0}
    end

    local target = windower.ffxi.get_mob_by_id(request.id)
    -- Preserve an exact ID through a momentary entity lookup gap, but never
    -- act or lease the scheduler until a fresh lookup succeeds.
    if not target then
        request.last_blocker = 'exact Genbu entity is not visible'
        return request, nil
    end
    if not ptgs_genmei_live_target(target, request) then
        ptgs_genmei_clear('exact Genbu entity died or changed', false)
        return nil
    end
    if not ptgs_genmei_party_claimed(target) then
        ptgs_genmei_clear('party claim was lost', false)
        return nil
    end
    return request, target
end

local function ptgs_genmei_resource(action)
    if not action or type(res) ~= 'table' then return nil end
    local collection
    if action.kind == 'weaponskill' then
        collection = res.weapon_skills
    elseif action.kind == 'job_ability' then
        collection = res.job_abilities
    elseif action.kind == 'spell' then
        collection = res.spells
    end
    local resource = collection and collection[action.id] or nil
    if not resource or resource.id ~= action.id
        or (resource.en or resource.english) ~= action.name
    then
        return nil
    end
    return resource
end

local function ptgs_genmei_collection_has(collection, id)
    if type(collection) ~= 'table' then return false end
    if collection[id] == true or collection[id] == 1
        or ((type(collection[id]) == 'number'
                or type(collection[id]) == 'string')
            and tonumber(collection[id]) == id)
    then
        return true
    end
    for key, value in pairs(collection) do
        if ((type(value) == 'number' or type(value) == 'string')
                and tonumber(value) == id)
            or ((value == true or value == 1) and tonumber(key) == id)
        then
            return true
        end
    end
    return false
end

local function ptgs_genmei_learned(action)
    if action.kind == 'spell' then
        return ptgs_genmei_collection_has(
            windower.ffxi.get_spells() or {}, action.id)
    end
    local abilities = windower.ffxi.get_abilities() or {}
    local collection = action.kind == 'weaponskill'
        and abilities.weapon_skills or abilities.job_abilities
    return ptgs_genmei_collection_has(collection or {}, action.id)
end

local function ptgs_genmei_function_true(name, ...)
    local callback = _G[name]
    if type(callback) ~= 'function' then return false end
    local ok, result = pcall(callback, ...)
    return ok and result == true
end

local function ptgs_genmei_recovery_needed()
    local buffs = buffactive or {}
    return buffs['Doom'] or buffs.doom
        or buffs['Silence'] or buffs.silence
end

local function ptgs_genmei_has_buff_id(wanted_id)
    local live = windower.ffxi.get_player()
    for _, buff_id in pairs(live and live.buffs or {}) do
        if tonumber(buff_id) == wanted_id then return true end
    end
    return false
end

local function ptgs_genmei_lowest_party_hpp()
    local lowest = 100
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if type(member) ~= 'table' or type(member.hpp) ~= 'number' then
            -- Missing fixed-roster vitals are unknown, never healthy.
            return 0
        end
        lowest = math.min(lowest, member.hpp)
    end
    return lowest
end

local function ptgs_genmei_emergency_priority(job)
    if ptgs_genmei_recovery_needed() then return true end
    if job ~= 'RDM' and job ~= 'PLD' and job ~= 'DNC' and job ~= 'GEO' then
        return false
    end

    local current = player or {}
    if (tonumber(current.hpp) or 100) <= PTGS_GENMEI_EMERGENCY_HPP then
        return true
    end
    local lowest = ptgs_genmei_lowest_party_hpp()
    if lowest and lowest <= PTGS_GENMEI_EMERGENCY_HPP then return true end
    return job == 'RDM'
        and (tonumber(current.mpp) or 100) <= PTGS_GENMEI_CONVERT_MPP
        and (tonumber(current.hpp) or 100) > PTGS_GENMEI_EMERGENCY_HPP
end

local function ptgs_genmei_distance(target)
    local squared = target and tonumber(target.distance)
    if not squared or squared < 0 then return nil end
    return math.sqrt(squared)
end

local function ptgs_genmei_action_range(target, action)
    local model_size = tonumber(target and target.model_size) or 0
    model_size = math.max(0, math.min(PTGS_GENMEI_MAX_MODEL_SIZE, model_size))
    return (tonumber(action and action.range) or 0) + model_size
end

-- Return a non-busy blocker.  These conditions deliberately do not lease the
-- character: normal cures, buffs, and recovery may continue while TP/MP,
-- range, recast, movement, or access is not ready.
local function ptgs_genmei_nonbusy_blocker(request, target, action, resource)
    if not target then
        return action.pre_encounter and 'waiting for the local character'
            or 'waiting for the exact Genbu entity'
    end
    if not resource then return 'fixed action resource is unavailable' end
    if not ptgs_genmei_learned(action) then
        return action.name..' is not currently learned or granted'
    end
    if request.job == 'GEO' and request.semantic == 'setup'
        and not ptgs_genmei_has_buff_id(551)
    then
        return 'waiting for exact Indi-Acumen status (buff 551)'
    end

    if action.target ~= 'self' then
        local distance = ptgs_genmei_distance(target)
        local action_range = ptgs_genmei_action_range(target, action)
        if not distance or distance > action_range then
            return ('Genbu is outside %.1fy range'):format(action_range)
        end
    end

    local current = player or {}
    if action.kind == 'weaponskill' and current.status ~= 'Engaged' then
        return 'waiting for combat engagement'
    end
    if action.min_tp and (tonumber(current.tp) or 0) < action.min_tp then
        return ('waiting for %d TP'):format(action.min_tp)
    end
    if action.kind == 'spell'
        and (tonumber(current.mp) or 0) < (tonumber(resource.mp_cost) or 0)
    then
        return 'insufficient MP for '..action.name
    end

    if action.kind == 'spell' then
        local recasts = windower.ffxi.get_spell_recasts() or {}
        local recast = tonumber(recasts[resource.recast_id or resource.id]) or 0
        local threshold = tonumber(spell_latency) or tonumber(latency) or 1
        if recast >= threshold then return action.name..' is on recast' end
        if type(silent_can_use) == 'function'
            and not ptgs_genmei_function_true('silent_can_use', action.id)
        then
            return action.name..' is blocked by spell status/access'
        end
    elseif action.kind == 'job_ability' then
        local recasts = windower.ffxi.get_ability_recasts() or {}
        local recast = tonumber(recasts[resource.recast_id]) or 0
        local threshold = tonumber(latency) or 1
        if recast >= threshold then return action.name..' is on recast' end
        if ptgs_genmei_function_true('silent_check_amnesia') then
            return 'amnesia prevents '..action.name
        end
    end

    if moving then return 'character is moving' end
    if ptgs_genmei_function_true('silent_check_disable') then
        return 'character is incapacitated'
    end
    if ptgs_genmei_recovery_needed() then
        return 'status recovery has priority'
    end
    if ptgs_genmei_emergency_priority(request.job) then
        return 'emergency healing or Convert has priority'
    end
    if os.clock() < (request.next_attempt or 0) then
        return 'bounded retry backoff'
    end
    return nil
end

local function ptgs_genmei_busy_blocker()
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

-- States are intentionally split into `blocked` (no scheduler lease), `busy`
-- (all prerequisites ready, lease the next legal action), and `ready`.
local function ptgs_genmei_evaluate()
    local request, target = ptgs_genmei_context()
    if not request then return nil, nil, nil, 'idle' end
    local action = PTGS_GENMEI_ACTIONS[request.job]
        and PTGS_GENMEI_ACTIONS[request.job][request.semantic]
        or nil
    if not action then
        ptgs_genmei_clear('fixed job/action mapping disappeared', true)
        return nil, nil, nil, 'idle'
    end

    -- A packet can be lost while the resulting status remains authoritative.
    -- Observing exact Barwater (105) resolves the private preparation without
    -- spending another bounded attempt.
    if action.auto_probe and action.buff_id
        and ptgs_genmei_has_buff_id(action.buff_id)
    then
        ptgs_genmei_queue.completed = ptgs_genmei_queue.completed + 1
        ptgs_genmei_clear(action.name..' status observed', false)
        return nil, nil, nil, 'idle'
    end


    local party_floor = ptgs_genmei_lowest_party_hpp()
    if party_floor < PTGS_GENMEI_EMERGENCY_HPP then
        request.last_blocker = 'party health is below the offense floor'
        return request, target, action, 'blocked'
    end

    if ptgs_genmei_emergency_priority(request.job) then
        request.last_blocker = 'emergency recovery has priority'
        return request, target, action, 'blocked'
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
        request.next_attempt = now + PTGS_GENMEI_RETRY_DELAY
        if request.attempts >= action.max_attempts then
            ptgs_genmei_clear(
                ('no result after %d attempt(s)'):format(request.attempts),
                true)
            return nil, nil, nil, 'idle'
        end
    end

    local resource = ptgs_genmei_resource(action)
    local blocker = ptgs_genmei_nonbusy_blocker(
        request, target, action, resource)
    if blocker then
        request.last_blocker = blocker
        return request, target, action, 'blocked'
    end

    local busy = ptgs_genmei_busy_blocker()
    if busy then
        request.last_blocker = busy
        return request, target, action, 'busy'
    end
    request.last_blocker = nil
    return request, target, action, 'ready'
end

local function ptgs_genmei_dispatch(request, action)
    local now = os.clock()
    request.attempts = request.attempts + 1
    request.inflight_until = now + PTGS_GENMEI_RESULT_TIMEOUT
    request.dispatch_token_until = now + PTGS_GENMEI_DISPATCH_TOKEN
    request.last_result = 'awaiting action result'
    request.last_blocker = nil

    local target_token = action.target == 'self'
        and '<me>' or tostring(request.id)
    windower.chat.input(action.command..' "'..action.name..'" '
        ..target_token)
    local current_delay = type(tickdelay) == 'number' and tickdelay or 0
    tickdelay = math.max(current_delay, now + PTGS_GENMEI_TICK_DELAY)
    ptgs_genmei_queue.dispatched = ptgs_genmei_queue.dispatched + 1
    ptgs_genmei_queue.last_result = action.name..' dispatched'
    local target_label = action.target == 'self'
        and 'self' or ('Genbu #'..tostring(request.id))
    ptgs_genmei_chat(158,
        ('%s -> %s dispatched (%d/%d).')
            :format(action.name, target_label, request.attempts,
                action.max_attempts))
    return true
end

local function ptgs_genmei_poll()
    local request, _, action, state_name = ptgs_genmei_evaluate()
    if not request then return false end
    if state_name == 'ready' then
        return ptgs_genmei_dispatch(request, action)
    end
    -- Only a fully prepared request waiting on current action recovery owns
    -- the next slot.  Resource/range/recast/status blockers remain non-leasing.
    return state_name == 'busy' or state_name == 'inflight'
end

local function ptgs_genmei_reserve(semantic, value, generation, epoch_value)
    local authorized, epoch = ptgs_genmei_authorized(
        generation, epoch_value)
    if not authorized then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'current-generation PartyTactics authority is required'
    end
    local job = ptgs_genmei_job()
    local action = job and PTGS_GENMEI_ACTIONS[job]
        and PTGS_GENMEI_ACTIONS[job][semantic]
        or nil
    if not action or action.auto_probe then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, ('%s cannot perform semantic action %s')
            :format(tostring(job or 'unknown job'), tostring(semantic))
    end

    local id = ptgs_genmei_uint32(value)
    if not id then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'target ID must be a uint32 integer'
    end
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    local candidate = {id=id, index=target and target.index or nil}
    if not info or not info.logged_in or info.zone ~= PTGS_GENMEI_ZONE
        or not target or type(target.index) ~= 'number'
        or not ptgs_genmei_live_target(target, candidate)
        or not ptgs_genmei_party_claimed(target)
    then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'target must be the exact live party-claimed Genbu'
    end
    if not ptgs_genmei_resource(action) then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'fixed action resource is unavailable'
    end
    if not ptgs_genmei_learned(action) then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, action.name..' is not currently learned or granted'
    end
    local current, live = ptgs_genmei_player()
    local player_id = tonumber(current and current.id)
        or tonumber(live and live.id)
    if action.target == 'self' and not player_id then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'local character identity is unavailable'
    end

    local existing = ptgs_genmei_queue.request
    if existing and existing.id == id and existing.index == target.index
        and existing.zone == info.zone and existing.job == job
        and existing.semantic == semantic
        and existing.generation == generation and existing.epoch == epoch
    then
        -- Repeated orchestration ticks describe one action.  They never extend
        -- its lifetime, reset attempts, or append duplicates.
        return true, 'already queued'
    end
    if existing then
        if existing.inflight_until then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            return false, 'another Genmei action is already in flight'
        end
        local old_action = PTGS_GENMEI_ACTIONS[existing.job]
            and PTGS_GENMEI_ACTIONS[existing.job][existing.semantic]
            or nil
        if not old_action or action.priority <= old_action.priority then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            return false, 'another Genmei action is already queued'
        end
        -- Any higher-priority mechanic response may replace lower-priority
        -- work that has not reached the server.  Nothing in flight is replaced.
        ptgs_genmei_clear(
            'preempted by higher-priority '..semantic..' response', false)
    end

    local now = os.clock()
    ptgs_genmei_queue.request = {
        semantic=semantic, job=job, action_id=action.id,
        generation=generation, epoch=epoch,
        id=id, index=target.index, zone=info.zone,
        result_id=action.target == 'self' and player_id or id,
        created=now, expires=now + action.ttl,
        attempts=0, next_attempt=0, last_result='queued',
    }
    ptgs_genmei_queue.accepted = ptgs_genmei_queue.accepted + 1
    ptgs_genmei_queue.last_result = semantic..' queued'
    return true, 'queued'
end

-- Tortoise Song can strip only part of a formation.  Cancel the reviewed
-- Genmei statuses on the two native casters once per runtime recovery request
-- so their established schedulers republish a complete party-wide set.  This
-- surface accepts neither a buff ID nor a command string from the caller and
-- never touches equipment or action callbacks.
local function ptgs_genmei_fixed_recovery(
    semantic, value, generation, epoch_value, request_token)
    local authorized, epoch = ptgs_genmei_authorized(
        generation, epoch_value)
    if not authorized then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'current-generation PartyTactics authority is required'
    end
    local job = ptgs_genmei_job()
    local action = job and PTGS_GENMEI_ACTIONS[job]
        and PTGS_GENMEI_ACTIONS[job][semantic]
        or nil
    if not action or action.kind ~= 'fixed_recovery'
        or type(action.buff_ids) ~= 'table'
    then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, ('%s cannot perform semantic action %s')
            :format(tostring(job or 'unknown job'), tostring(semantic))
    end
    if type(request_token) ~= 'string' or #request_token < 1
        or #request_token > 64
        or request_token:match('^[a-z0-9][a-z0-9_-]*$') == nil
    then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'fixed recovery requires one bounded event token'
    end

    local id = ptgs_genmei_uint32(value)
    local info = windower.ffxi.get_info()
    local target = id and windower.ffxi.get_mob_by_id(id) or nil
    local candidate = {id=id, index=target and target.index or nil}
    if not info or not info.logged_in or info.zone ~= PTGS_GENMEI_ZONE
        or not target or type(target.index) ~= 'number'
        or not ptgs_genmei_live_target(target, candidate)
        or not ptgs_genmei_party_claimed(target)
        or ptgs_genmei_dead()
    then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'target must be the exact live party-claimed Genbu'
    end
    if type(windower.ffxi.cancel_buff) ~= 'function' then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'fixed status cancellation is unavailable'
    end

    local token_key = job..':'..semantic..':'..request_token
    local prior = ptgs_genmei_recovery_tokens[token_key]
    if prior then
        if prior.id ~= id or prior.index ~= target.index
            or prior.generation ~= generation or prior.epoch ~= epoch
        then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            return false, 'recovery token is already bound to another authority'
        end
        return true, 'fixed recovery token already accepted'
    end

    local cancelled = 0
    for _, buff_id in ipairs(action.buff_ids) do
        if ptgs_genmei_has_buff_id(buff_id) then
            windower.ffxi.cancel_buff(buff_id)
            cancelled = cancelled + 1
        end
    end
    ptgs_genmei_recovery_tokens[token_key] = {
        id=id, index=target.index, generation=generation, epoch=epoch,
    }
    ptgs_genmei_recovery_token_order[#ptgs_genmei_recovery_token_order + 1]
        = token_key
    if #ptgs_genmei_recovery_token_order
        > PTGS_GENMEI_MAX_RECOVERY_TOKENS
    then
        local expired = table.remove(ptgs_genmei_recovery_token_order, 1)
        ptgs_genmei_recovery_tokens[expired] = nil
    end
    ptgs_genmei_queue.accepted = ptgs_genmei_queue.accepted + 1
    ptgs_genmei_queue.completed = ptgs_genmei_queue.completed + 1
    ptgs_genmei_queue.last_result = semantic..' requested'
    return true, ('fixed recovery requested; %d status(es) cancelled')
        :format(cancelled)
end

-- A valid BRD capability probe is the complete authority for this one private
-- preparation action.  Unlike public fight semantics it does not accept a
-- target and therefore cannot be widened into a pre-pop remote-action API.
local function ptgs_genmei_prepare_brd()
    local capability = ptgs_genmei_capability
    local action = PTGS_GENMEI_ACTIONS.BRD.barwatera_prepare
    if not capability or capability.job ~= 'BRD'
        or ptgs_genmei_job() ~= 'BRD'
    then
        return false, 'BRD capability is required'
    end
    if ptgs_genmei_has_buff_id(action.buff_id) then
        return true, 'already prepared'
    end

    local info = windower.ffxi.get_info()
    local current, live = ptgs_genmei_player()
    local player_id = tonumber(current and current.id)
        or tonumber(live and live.id)
    if not info or not info.logged_in or info.zone ~= PTGS_GENMEI_ZONE
        or not player_id
    then
        return false, 'Barwatera preparation requires BRD in Escha Ru\'Aun'
    end
    if not ptgs_genmei_resource(action)
        or not ptgs_genmei_learned(action)
    then
        return false, 'Barwatera is unavailable'
    end

    local existing = ptgs_genmei_queue.request
    if existing and existing.semantic == 'barwatera_prepare'
        and existing.job == 'BRD' and existing.result_id == player_id
        and existing.generation == capability.generation
        and existing.epoch == capability.epoch
    then
        return true, 'already queued'
    end
    if existing then
        -- A fresh probe is a new authority boundary. No request from an older
        -- generation may survive it, including an action awaiting a result.
        ptgs_genmei_clear('superseded by a fresh BRD capability probe', false)
    end

    local now = os.clock()
    ptgs_genmei_queue.request = {
        semantic='barwatera_prepare', job='BRD', action_id=action.id,
        generation=capability.generation, epoch=capability.epoch,
        id=player_id, result_id=player_id, zone=info.zone,
        pre_encounter=true,
        created=now, expires=now + action.ttl,
        attempts=0, next_attempt=0, last_result='queued',
    }
    ptgs_genmei_queue.accepted = ptgs_genmei_queue.accepted + 1
    ptgs_genmei_queue.last_result = 'barwatera_prepare queued'
    ptgs_genmei_poll()
    return true, 'queued'
end

local function ptgs_genmei_status()
    local request = ptgs_genmei_queue.request
    if not request then
        ptgs_genmei_chat(122,
            ('idle / accepted %d / dispatched %d / completed %d / rejected %d')
                :format(ptgs_genmei_queue.accepted,
                    ptgs_genmei_queue.dispatched,
                    ptgs_genmei_queue.completed,
                    ptgs_genmei_queue.rejected))
        return
    end
    ptgs_genmei_evaluate()
    request = ptgs_genmei_queue.request
    if not request then return ptgs_genmei_status() end
    ptgs_genmei_chat(122,
        ('%s #%d / %s / attempts %d / %.1fs remaining')
            :format(request.semantic, request.id,
                tostring(request.last_blocker or request.last_result),
                request.attempts,
                math.max(0, request.expires - os.clock())))
end

local function ptgs_genmei_renew_geo_if_needed()
    if ptgs_genmei_job() ~= 'GEO' or ptgs_genmei_queue.request
        or not ptgs_genmei_geo_binding
    then
        return false
    end
    local binding = ptgs_genmei_geo_binding
    local capability = ptgs_genmei_capability
    local now = os.clock()
    if not capability
        or capability.generation ~= binding.generation
        or capability.epoch ~= binding.epoch
        or now < (binding.next_attempt or 0)
    then
        return false
    end
    if type(pet) == 'table' and pet.isvalid == true then return false end

    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(binding.id)
    if not info or not info.logged_in or info.zone ~= binding.zone
        or not target or not ptgs_genmei_live_target(target, binding)
        or not ptgs_genmei_party_claimed(target)
    then
        ptgs_genmei_geo_binding = nil
        return false
    end

    binding.next_attempt = now + 3
    local accepted = ptgs_genmei_reserve('setup', tostring(binding.id),
        binding.generation, tostring(binding.epoch))
    if accepted then ptgs_genmei_poll() end
    return accepted == true
end

local PTGS_GENMEI_RECOVERY_ITEMS = {
    ['Echo Drops']=true,
    ['Remedy']=true,
    ['Panacea']=true,
    ['Holy Water']=true,
}

local PTGS_GENMEI_RECOVERY_SPELLS = {
    Erase=true, Poisona=true, Paralyna=true, Silena=true, Blindna=true,
    Stona=true, Viruna=true, Cursna=true,
}

local function ptgs_genmei_action_name(spell)
    return spell and (spell.english or spell.en or spell.name) or nil
end

local function ptgs_genmei_is_emergency_action(spell)
    if not spell then return false end
    local name = ptgs_genmei_action_name(spell)
    if spell.action_type == 'Item' and PTGS_GENMEI_RECOVERY_ITEMS[name] then
        return true
    end
    local job = ptgs_genmei_job()
    if job == 'RDM' and name == 'Convert' then return true end
    if job == 'DNC' and type(name) == 'string'
        and (name:match('^Curing Waltz')
            or name:match('^Divine Waltz')
            or name == 'Healing Waltz'
            or name == 'No Foot Rise'
            or name == 'Reverse Flourish')
    then
        return true
    end
    if (job == 'RDM' or job == 'PLD' or job == 'GEO')
        and type(name) == 'string'
    then
        if PTGS_GENMEI_RECOVERY_SPELLS[name] then return true end
        if name:match('^Cure [IVX]+$') or name == 'Cure'
            or name:match('^Cura')
        then
            local target_hpp = spell.target and tonumber(spell.target.hpp)
                or nil
            return target_hpp == nil
                or target_hpp <= PTGS_GENMEI_EMERGENCY_HPP
                or ptgs_genmei_emergency_priority(job)
        end
    end
    return false
end

local function ptgs_genmei_is_own_dispatch(spell, phase)
    local request = ptgs_genmei_queue.request
    if not request or not request.inflight_until or not spell
        or spell.id ~= request.action_id
    then
        return false
    end
    local target_id = spell.target and tonumber(spell.target.id) or nil
    if target_id == (request.result_id or request.id) then return true end
    -- GearSwap's pretarget callback can occur before its numeric-ID resolver
    -- has populated spell.target.  This token exists only around our command.
    return os.clock() <= (request.dispatch_token_until or 0)
        and (phase == 'pretarget' or target_id == nil)
end

local function ptgs_genmei_blocks_action(spell, phase)
    local request, _, _, state_name = ptgs_genmei_evaluate()
    if not request then return false end
    if ptgs_genmei_is_own_dispatch(spell, phase)
        or ptgs_genmei_is_emergency_action(spell)
    then
        return false
    end
    -- DNC is a controlled skillchain participant.  Even when its lead is
    -- waiting on TP/range or party recovery (a non-leasing blocker for other
    -- jobs), only the fixed lead or explicit emergency actions may pass.
    -- This prevents the native loop from spending TP on a Step, Samba, or an
    -- unrelated weaponskill while the leader is holding Evisceration.
    if request.job == 'DNC' then return true end
    if state_name ~= 'ready' and state_name ~= 'busy'
        and state_name ~= 'inflight'
    then
        return false
    end
    -- The GEO controller may need to dismiss a stale luopan immediately after
    -- this queue has dispatched Geo-Malaise.  Full Circle is legal only inside
    -- that exact, in-flight setup reservation; it is never a general bypass.
    local name = ptgs_genmei_action_name(spell)
    if request.job == 'GEO' and request.semantic == 'setup'
        and request.inflight_until and name == 'Full Circle'
    then
        return false
    end
    return true
end

-- The shared host owns every global callback. Adapter hooks return whether
-- they consumed/blocked work and never invoke a previously installed hook.
function M.activate()
    return true
end

function M.pre_tick()
    return ptgs_genmei_poll()
end

function M.user_job_tick()
    return ptgs_genmei_poll()
end

function M.filter_pretarget(spell, spellMap, eventArgs)
    return ptgs_genmei_blocks_action(spell, 'pretarget')
end

function M.filter_precast(spell, spellMap, eventArgs)
    return ptgs_genmei_blocks_action(spell, 'precast')
end

function M.job_aftercast(spell, spellMap, eventArgs)
    local request = ptgs_genmei_queue.request
    if request and request.inflight_until and spell
        and spell.id == request.action_id and spell.interrupted
    then
        local action = PTGS_GENMEI_ACTIONS[request.job]
            and PTGS_GENMEI_ACTIONS[request.job][request.semantic]
            or nil
        request.inflight_until = nil
        request.dispatch_token_until = nil
        request.last_result = 'interrupted'
        if not action or request.attempts >= action.max_attempts then
            ptgs_genmei_clear(
                ('interrupted after %d attempt(s)'):format(request.attempts),
                true)
        else
            request.next_attempt = os.clock() + PTGS_GENMEI_RETRY_DELAY
        end
    end
end

-- Host-routed semantic entry point. `arguments` contains only the raw tokens
-- following the semantic, never an arbitrary spell/action name.
function M.handle_action(controller, semantic, arguments)
    if type(controller) ~= 'string'
        or controller:lower() ~= M.controller
    then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'unsupported controller'
    end
    if type(semantic) ~= 'string' then
        ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
        return false, 'semantic action is required'
    end
    local requested = semantic:lower()
    local command_args = type(arguments) == 'table' and arguments or {}

    if requested == 'probe' then
        local accepted, reason = ptgs_genmei_probe(
            command_args[1], command_args[2], command_args[3])
        if not accepted then
            ptgs_genmei_chat(123,
                'capability probe rejected: '..tostring(reason)..'.')
        elseif ptgs_genmei_job() == 'BRD' then
            -- Readiness acknowledgement proves this adapter revision; the
            -- separately observed Barwater status proves preparation. Keep
            -- the action bounded even when it is temporarily blocked.
            ptgs_genmei_prepare_brd()
        end
        return accepted, reason
    elseif requested == 'recover-songs' or requested == 'recover-rolls' then
        if #command_args ~= 4 then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            return false, 'fixed recovery accepts only target and current authority'
        end
        local accepted, reason = ptgs_genmei_fixed_recovery(
            requested, command_args[1], command_args[2], command_args[3],
            command_args[4])
        if not accepted then
            ptgs_genmei_chat(123,
                'recovery request rejected: '..tostring(reason)..'.')
        else
            ptgs_genmei_chat(122, tostring(reason)..'.')
        end
        return accepted, reason
    elseif requested == 'cancel' then
        local target_id = ptgs_genmei_uint32(command_args[1])
        if not target_id
            or not ptgs_genmei_authorized(command_args[2], command_args[3])
        then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            ptgs_genmei_chat(123,
                'cancel rejected: exact target and current-generation PartyTactics authority are required.')
            return false, 'exact target and current authority are required'
        end
        local request = ptgs_genmei_queue.request
        if request and request.id ~= target_id then
            ptgs_genmei_queue.rejected = ptgs_genmei_queue.rejected + 1
            ptgs_genmei_chat(123,
                'cancel rejected: target does not match queued Genbu.')
            return false, 'target does not match queued Genbu'
        end
        ptgs_genmei_clear('profile cancelled', false)
        ptgs_genmei_chat(122, 'queue cancelled.')
        return true, 'cancelled'
    elseif requested == 'status' then
        ptgs_genmei_status()
        return true, 'status'
    end

    local accepted, reason = ptgs_genmei_reserve(
        requested, command_args[1], command_args[2], command_args[3])
    if not accepted then
        ptgs_genmei_chat(123, 'request rejected: '..tostring(reason)..'.')
        return false, reason
    end
    if reason ~= 'already queued' then
        local request = ptgs_genmei_queue.request
        ptgs_genmei_chat(122,
            ('%s #%d reserved as the next legal action.')
                :format(request.semantic, request.id))
    end
    ptgs_genmei_poll()
    return true, reason
end

function M.status()
    ptgs_genmei_status()
    local request = ptgs_genmei_queue.request
    local current = request and (request.semantic..'#'..tostring(request.id))
        or 'idle'
    return ('queue=%s accepted=%d dispatched=%d completed=%d rejected=%d')
        :format(current, ptgs_genmei_queue.accepted,
            ptgs_genmei_queue.dispatched, ptgs_genmei_queue.completed,
            ptgs_genmei_queue.rejected)
end

function M.deactivate(reason)
    ptgs_genmei_report_lost()
    ptgs_genmei_clear(reason or 'adapter deactivated', false)
    return true
end

-- GearSwap job-file reloads call file_unload() without unloading the Windower
-- GearSwap addon. Revoke the exact capability at both boundaries.
function M.file_unload(...)
    return M.deactivate('GearSwap job file unloaded')
end

function M.action_event(action_packet)
    local request = ptgs_genmei_queue.request
    if not request or not request.inflight_until
        or type(action_packet) ~= 'table'
    then
        return
    end
    local current = windower.ffxi.get_player()
    if not current or action_packet.actor_id ~= current.id then return end

    local action = PTGS_GENMEI_ACTIONS[request.job]
        and PTGS_GENMEI_ACTIONS[request.job][request.semantic]
        or nil
    if not action or action_packet.category ~= action.category
        or action_packet.param ~= action.id
    then
        return
    end
    local wanted_result_id = request.result_id or request.id
    for _, result_target in ipairs(action_packet.targets or {}) do
        if result_target.id == wanted_result_id then
            local result = result_target.actions and result_target.actions[1]
            local message_id = result and tonumber(result.message) or nil
            local dispel_resolved = request.semantic == 'dispel'
                and PTGS_GENMEI_DISPEL_RESOLVED_MESSAGES[message_id]
            if result and PTGS_GENMEI_FAILURE_MESSAGES[message_id]
                and not dispel_resolved
            then
                request.inflight_until = nil
                request.dispatch_token_until = nil
                request.last_result = 'server rejected action'
                if request.attempts >= action.max_attempts then
                    ptgs_genmei_clear(
                        ('server rejected %s after %d attempt(s)')
                            :format(action.name, request.attempts), true)
                else
                    request.next_attempt = os.clock()
                        + PTGS_GENMEI_RETRY_DELAY
                end
                return
            end
            ptgs_genmei_queue.completed = ptgs_genmei_queue.completed + 1
            if request.job == 'GEO' and request.semantic == 'setup' then
                ptgs_genmei_geo_binding = {
                    id=request.id, index=request.index, zone=request.zone,
                    generation=request.generation, epoch=request.epoch,
                    next_attempt=os.clock() + 2,
                }
            end
            local target_label = action.target == 'self'
                and 'self' or ('Genbu #'..tostring(request.id))
            ptgs_genmei_chat(158,
                ('%s -> %s completed.')
                    :format(action.name, target_label))
            ptgs_genmei_clear(action.name..' completed', false)
            return
        end
    end
end

function M.prerender()
    ptgs_genmei_renew_geo_if_needed()
    if not ptgs_genmei_queue.request then return false end
    local now = os.clock()
    if now < ptgs_genmei_queue.next_poll then return false end
    ptgs_genmei_queue.next_poll = now + PTGS_GENMEI_POLL_INTERVAL
    return ptgs_genmei_poll()
end

function M.zone_change(...)
    ptgs_genmei_geo_binding = nil
    ptgs_genmei_clear('zone changed', false)
end

function M.logout(...)
    ptgs_genmei_geo_binding = nil
    ptgs_genmei_clear('logout', false)
end

function M.unload(...)
    return M.deactivate('GearSwap unloaded')
end

function M.status_change(new_status, ...)
    if new_status == 2
        or (type(new_status) == 'string'
            and new_status:lower():find('dead', 1, true))
    then
        ptgs_genmei_geo_binding = nil
        ptgs_genmei_clear('character died', false)
    end
end

return M
