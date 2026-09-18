-- PartyTactics GearSwap adapter: Genbu fixed actions plus one bounded
-- next-legal Thunder request per configured client.
--
-- The normal RDM and GEO helpers remain the owners of buffs, cures, and
-- enfeebles. Invincible creates short exact-target Thunder Shot/Thunder
-- requests, while Light creates Thunder IV requests. Only an RDM/GEO client
-- with its own request pending consumes its automatic job tick; COR is polled
-- without owning that tick. Manual actions are never filtered or cancelled.

local M = {
    id = 'escha-ruaun-genbu-genmei',
    version = '2.4.0',
    controller = 'genmei',
    protocol = 1,
}

local ZONE = 289
local TARGET_NAME = 'Genbu'
local MIN_REPEAT = 0.75
local REQUEST_RESULT_TIMEOUT = 4.0
local REQUEST_RETRY = 0.25
local REQUEST_MAX_ATTEMPTS = 3
local REQUEST_POLL = 0.10
local MAX_MODEL_SIZE = 10
local QUEUE_JOBS = {COR=true, RDM=true, GEO=true}
local HELPER_TICK_JOBS = {RDM=true, GEO=true}
local RDM_NA_HOLD = 35

local QUEUED = {
    COR={
        proc={kind='ability', command='/ja', id=129,
            name='Thunder Shot', range=21.5, ttl=6, priority=20},
        ['triple-shot']={kind='ability', command='/ja', id=301,
            name='Triple Shot', self_target=true, ttl=8, priority=10},
    },
    RDM={
        proc={kind='spell', command='/ma', id=164,
            name='Thunder', range=20.4, ttl=6, priority=20},
        burst={kind='spell', command='/ma', id=167,
            name='Thunder IV', range=20.4, ttl=8, priority=40},
    },
    GEO={
        proc={kind='spell', command='/ma', id=164,
            name='Thunder', range=20.4, ttl=6, priority=20},
        burst={kind='spell', command='/ma', id=167,
            name='Thunder IV', range=20.4, ttl=8, priority=40},
    },
}

local ACTIONS = {
    BRD = {
        barwatera={command='/ma', name='Barwatera', self_target=true},
        finale={command='/ma', name='Magic Finale'},
    },
    COR = {
        disengage={command='/attack', off=true},
        shoot={command='/ra'},
        ['last-stand']={command='/ws', name='Last Stand'},
    },
    DNC = {
        ['haste-samba']={command='/ja', name='Haste Samba', self_target=true},
        ['box-step']={command='/ja', name='Box Step'},
        evisceration={command='/ws', name='Evisceration'},
    },
    GEO = {
        setup={command='/ma', name='Geo-Malaise'},
    },
    PLD = {
        crusade={command='/ma', name='Crusade', self_target=true},
        ['divine-emblem']={
            command='/ja', name='Divine Emblem', self_target=true,
        },
        sentinel={command='/ja', name='Sentinel', self_target=true},
        flash={command='/ma', name='Flash'},
        provoke={command='/ja', name='Provoke'},
        ['savage-blade']={command='/ws', name='Savage Blade'},
    },
    RDM = {
        dispel={command='/ma', name='Dispel'},
    },
}

local RECOVERY = {
    BRD={
        ['recover-songs']={214, 197, 196}, -- March, Minne, Ballad
    },
    COR={
        ['recover-rolls']={321, 314}, -- Samurai, Warlock
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

local capability
local active = false
local last_dispatch = {}
local recovery_seen = {}
local dispatched = 0
local rejected = 0
local request_completed = 0
local combat_binding
local queue_request
local next_request_poll = 0
local rdm_na_disabled = false
local rdm_na_restore_at = 0

local function nonnegative_integer(value)
    if type(value) ~= 'string' or value == '' or #value > 12
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

local function uint32(value)
    if type(value) ~= 'string' or value == '' or #value > 10
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

local function generation(value)
    return type(value) == 'string' and #value <= 64
        and value:match('^%d+%-%d+%-%d+$') ~= nil
end

local function current_player()
    local live = type(windower) == 'table'
        and type(windower.ffxi) == 'table'
        and type(windower.ffxi.get_player) == 'function'
        and windower.ffxi.get_player() or nil
    return type(player) == 'table' and player or live, live
end

local function current_job()
    local current, live = current_player()
    return current and current.main_job or live and live.main_job or nil
end

local function player_dead()
    local current, live = current_player()
    local hpp = tonumber(current and current.hpp)
        or tonumber(live and live.vitals and live.vitals.hpp)
    local status = current and current.status or live and live.status
    return hpp ~= nil and hpp <= 0
        or status == 2
        or type(status) == 'string'
            and status:lower():find('dead', 1, true) ~= nil
end

local function party_claimed(target)
    local claim = target and tonumber(target.claim_id) or nil
    if not claim or claim < 1 or claim > 4294967295
        or claim ~= math.floor(claim)
    then
        return false
    end
    local current, live = current_player()
    if tonumber(current and current.id) == claim
        or tonumber(live and live.id) == claim
    then
        return true
    end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if tonumber(member and member.mob and member.mob.id) == claim then
            return true
        end
    end
    return false
end

local function exact_target(id)
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    local claim = target and tonumber(target.claim_id) or nil
    return info and info.logged_in and tonumber(info.zone) == ZONE
        and type(target) == 'table'
        and target.name == TARGET_NAME
        and tonumber(target.spawn_type) == 16
        and target.valid_target == true
        and (tonumber(target.hpp) or 0) > 0
        and (claim == 0 or party_claimed(target))
        and target or nil
end

local function valid_authority(arguments)
    return type(arguments) == 'table'
        and generation(arguments[2])
        and nonnegative_integer(arguments[3]) ~= nil
end

local function same_authority(binding, arguments)
    return binding and valid_authority(arguments)
        and binding.generation == arguments[2]
        and binding.epoch == nonnegative_integer(arguments[3])
end

local function report_ready(arguments)
    local epoch = nonnegative_integer(arguments[2])
    local protocol = nonnegative_integer(arguments[3])
    local job = current_job()
    if not generation(arguments[1]) or epoch == nil
        or protocol ~= M.protocol or ACTIONS[job] == nil
    then
        return false, 'invalid or unsupported controller probe'
    end
    capability = {
        generation=arguments[1], epoch=epoch, protocol=protocol,
    }
    windower.send_command(('pt __controller_ready genmei %s %d %d')
        :format(arguments[1], epoch, protocol))
    return true, 'ready'
end

local function report_lost()
    if not capability then return end
    windower.send_command(('pt __controller_lost genmei %s %d %d')
        :format(capability.generation, capability.epoch,
            capability.protocol))
    capability = nil
end

local function dispatch(semantic, action, id)
    local key = tostring(current_job())..':'..semantic..':'..tostring(id)
    local now = os.clock()
    if now - (last_dispatch[key] or -100000) < MIN_REPEAT then
        return true, 'recently submitted'
    end
    last_dispatch[key] = now

    if action.command == '/attack' then
        windower.chat.input(action.off and '/attack off'
            or ('/attack '..tostring(id)))
    elseif action.command == '/ra' then
        windower.chat.input('/ra '..tostring(id))
    else
        local target = action.self_target and '<me>' or tostring(id)
        windower.chat.input(action.command..' "'..action.name..'" '..target)
    end
    dispatched = dispatched + 1
    return true, 'submitted'
end

local function recover(semantic, ids, arguments, id)
    local token = arguments[4]
    if type(token) ~= 'string' or token == '' or #token > 64
        or token:match('^[A-Za-z0-9_-]+$') == nil
    then
        return false, 'recovery request requires one bounded event token'
    end
    local key = tostring(current_job())..':'..semantic..':'..token
    if recovery_seen[key] then return true, 'already submitted' end
    recovery_seen[key] = true
    if type(windower.ffxi.cancel_buff) == 'function' then
        local current, live = current_player()
        local buffs = current and current.buffs or live and live.buffs or {}
        local present = {}
        for _, buff_id in ipairs(buffs or {}) do
            present[tonumber(buff_id)] = true
        end
        for _, buff_id in ipairs(ids) do
            if present[buff_id] then windower.ffxi.cancel_buff(buff_id) end
        end
    end
    dispatched = dispatched + 1
    return true, 'support refresh requested'
end

local function clear_request(reason)
    queue_request = nil
    next_request_poll = 0
    return reason
end

local function restore_rdm_na()
    if not rdm_na_disabled then return end
    windower.send_command('hb enable na')
    rdm_na_disabled = false
    rdm_na_restore_at = 0
end

local function hold_rdm_na()
    if current_job() ~= 'RDM' then return end
    if not rdm_na_disabled then windower.send_command('hb disable na') end
    rdm_na_disabled = true
    rdm_na_restore_at = math.max(rdm_na_restore_at or 0,
        os.clock() + RDM_NA_HOLD)
end

local function maintain_rdm_na(now)
    if rdm_na_disabled and now >= rdm_na_restore_at then restore_rdm_na() end
end

local function bind_combat(id, arguments, target)
    local job = current_job()
    if not QUEUE_JOBS[job] then
        return false, 'combat binding belongs only to a queued Genbu client'
    end
    combat_binding = {
        id=id, index=target.index, zone=ZONE,
        generation=arguments[2], epoch=nonnegative_integer(arguments[3]),
    }
    clear_request('new combat binding')
    return true, job..' Thunder routing bound to exact Genbu'
end

local function end_combat(id, arguments)
    local job = current_job()
    if not QUEUE_JOBS[job] or not combat_binding
        or combat_binding.id ~= id
        or not same_authority(combat_binding, arguments)
    then
        return false, 'combat end does not match the active Thunder binding'
    end
    combat_binding = nil
    clear_request('combat ended')
    restore_rdm_na()
    return true, job..' Thunder routing released'
end

local function learned_spell(id)
    local known = windower.ffxi.get_spells() or {}
    if known[id] == true or known[id] == 1 then return true end
    for key, value in pairs(known) do
        local value_id = (type(value) == 'number'
            or type(value) == 'string') and tonumber(value) or nil
        if (tonumber(key) == id and (value == true or value == 1))
            or value_id == id
        then
            return true
        end
    end
    return false
end

local function request_resource(request)
    local resources = type(res) == 'table'
        and (request.kind == 'spell' and res.spells or res.job_abilities)
        or nil
    local resource = resources and resources[request.action_id] or nil
    local name = resource and (resource.en or resource.english)
    if not resource or tonumber(resource.id) ~= request.action_id
        or name ~= request.action_name
    then
        return nil
    end
    return resource
end

local function request_context()
    local request = queue_request
    if not request then return nil end
    if not active or current_job() ~= request.job or not combat_binding
        or request.id ~= combat_binding.id
        or request.index ~= combat_binding.index
        or request.generation ~= combat_binding.generation
        or request.epoch ~= combat_binding.epoch
        or player_dead()
    then
        clear_request('combat authority changed')
        return nil
    end
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(request.id)
    local claim = target and tonumber(target.claim_id) or nil
    if not info or not info.logged_in or tonumber(info.zone) ~= request.zone
        or type(target) ~= 'table' or target.id ~= request.id
        or target.index ~= request.index or target.name ~= TARGET_NAME
        or tonumber(target.spawn_type) ~= 16 or target.valid_target ~= true
        or (tonumber(target.hpp) or 0) <= 0
        or (claim ~= 0 and not party_claimed(target))
    then
        clear_request('exact Genbu is no longer a live party target')
        return nil
    end
    return request, target
end

local function request_blocker(request, target)
    local now = os.clock()
    if now >= request.expires then
        clear_request(request.action_name..' request expired')
        return 'expired'
    end
    if request.inflight_until then
        if now < request.inflight_until then return 'inflight' end
        request.inflight_until = nil
        if request.attempts >= REQUEST_MAX_ATTEMPTS then
            clear_request('result timeout')
            return 'expired'
        end
        request.next_attempt = now + REQUEST_RETRY
    end
    if now < (request.next_attempt or 0) then return 'backoff' end
    if type(midaction) == 'function' and midaction() then return 'busy' end
    if type(next_cast) == 'number' and now < next_cast then return 'busy' end
    if type(tickdelay) == 'number' and now < tickdelay then return 'busy' end
    if moving == true then return 'moving' end
    if type(silent_check_disable) == 'function'
        and silent_check_disable()
    then
        return 'incapacitated'
    end
    local resource = request_resource(request)
    if not resource
        or request.kind == 'spell' and not learned_spell(request.action_id)
    then
        clear_request(request.action_name..' is unavailable')
        return 'expired'
    end
    local get_recasts = request.kind == 'spell'
        and windower.ffxi.get_spell_recasts
        or windower.ffxi.get_ability_recasts
    local recasts = type(get_recasts) == 'function' and get_recasts() or {}
    if (tonumber(recasts[resource.recast_id or resource.id]) or 0) >= 1 then
        return 'recast'
    end
    if request.kind == 'ability' and type(silent_can_use) == 'function'
        and not silent_can_use(request.action_id)
    then
        return 'recast'
    elseif request.kind == 'spell' then
        local current, live = current_player()
        local mp = tonumber(current and current.mp)
            or tonumber(live and live.vitals and live.vitals.mp) or 0
        if mp < (tonumber(resource.mp_cost) or 0) then return 'mp' end
    end
    if not request.self_target then
        local squared = tonumber(target.distance)
        local model = math.max(0, math.min(MAX_MODEL_SIZE,
            tonumber(target.model_size) or 0))
        if not squared or squared < 0
            or math.sqrt(squared) > request.range + model
        then
            return 'range'
        end
    end
    return nil, resource
end

local function poll_request()
    local request, target = request_context()
    if not request then return false end
    local blocker = request_blocker(request, target)
    if blocker then return queue_request ~= nil end

    local now = os.clock()
    request.attempts = request.attempts + 1
    request.inflight_until = now + REQUEST_RESULT_TIMEOUT
    request.next_attempt = now + REQUEST_RETRY
    local target_token = request.self_target and '<me>' or tostring(request.id)
    windower.chat.input(request.command..' "'..request.action_name..'" '
        ..target_token)
    local current_delay = type(tickdelay) == 'number' and tickdelay or 0
    tickdelay = math.max(current_delay, now + 1.5)
    dispatched = dispatched + 1
    return true
end

local function reserve_request(semantic, id, arguments, target)
    local job = current_job()
    local spec = QUEUED[job] and QUEUED[job][semantic]
    if not spec then return false, job..' cannot queue '..semantic end

    -- A missed combat-start routing message cannot turn into an action gate.
    -- The exact, profile-authorized request may establish or replace its own
    -- same-encounter binding.
    if not combat_binding or combat_binding.id ~= id
        or combat_binding.index ~= target.index
        or not same_authority(combat_binding, arguments)
    then
        combat_binding = {
            id=id, index=target.index, zone=ZONE,
            generation=arguments[2], epoch=nonnegative_integer(arguments[3]),
        }
        clear_request('request established combat binding')
    end
    local now = os.clock()
    if job == 'RDM' and semantic == 'proc' then hold_rdm_na() end
    if queue_request and queue_request.id == id
        and queue_request.index == target.index
    then
        if queue_request.action_id == spec.id then
            queue_request.expires = math.max(queue_request.expires,
                now + spec.ttl)
            return true, spec.name..' is already queued'
        elseif queue_request.inflight_until then
            return true, queue_request.action_name..' is already in flight'
        elseif spec.priority <= queue_request.priority then
            return true, queue_request.action_name..' remains queued'
        end
    end
    queue_request = {
        id=id, index=target.index, zone=ZONE,
        generation=arguments[2], epoch=nonnegative_integer(arguments[3]),
        job=job, semantic=semantic, kind=spec.kind, command=spec.command,
        action_id=spec.id, action_name=spec.name, range=spec.range,
        self_target=spec.self_target == true,
        priority=spec.priority, created=now, expires=now + spec.ttl,
        attempts=0, next_attempt=now,
    }
    next_request_poll = 0
    poll_request()
    return true, spec.name..' reserved as '..job..'\'s next automatic action'
end

function M.activate()
    active = true
    return true
end

function M.deactivate(reason)
    active = false
    report_lost()
    last_dispatch = {}
    recovery_seen = {}
    combat_binding = nil
    clear_request(reason or 'adapter deactivated')
    restore_rdm_na()
    return true
end

function M.handle_action(controller, semantic, arguments)
    if controller ~= M.controller or type(semantic) ~= 'string' then
        rejected = rejected + 1
        return false, 'unsupported controller or semantic'
    end
    arguments = type(arguments) == 'table' and arguments or {}
    semantic = semantic:lower()
    if semantic == 'probe' then return report_ready(arguments) end
    if not active then
        rejected = rejected + 1
        return false, 'adapter is inactive'
    end

    local id = uint32(arguments[1])
    if not id or not valid_authority(arguments) then
        rejected = rejected + 1
        return false, 'exact Genbu ID and current authority are required'
    end
    local job = current_job()
    if semantic == 'combat-end' then
        local ok, reason = end_combat(id, arguments)
        if not ok then rejected = rejected + 1 end
        return ok, reason
    elseif semantic == 'cancel' then
        if QUEUE_JOBS[job] and combat_binding and combat_binding.id == id
            and same_authority(combat_binding, arguments)
        then
            combat_binding = nil
            clear_request('profile cancelled')
            restore_rdm_na()
        end
        return true, 'local work cancelled'
    elseif semantic == 'disengage' and job == 'COR' then
        return dispatch(semantic, ACTIONS.COR.disengage, id)
    end

    local target = exact_target(id)
    if not target then
        rejected = rejected + 1
        return false, 'exact live unclaimed or party-claimed Genbu is required'
    end
    if semantic == 'combat-start' then
        local ok, reason = bind_combat(id, arguments, target)
        if not ok then rejected = rejected + 1 end
        return ok, reason
    end

    local recovery = RECOVERY[job] and RECOVERY[job][semantic]
    if recovery then return recover(semantic, recovery, arguments, id) end
    if QUEUED[job] and QUEUED[job][semantic] then
        local ok, reason = reserve_request(semantic, id, arguments, target)
        if not ok then rejected = rejected + 1 end
        return ok, reason
    end
    local action = ACTIONS[job] and ACTIONS[job][semantic]
    if not action then
        rejected = rejected + 1
        return false, tostring(job or 'unknown job')
            ..' cannot perform '..semantic
    end
    return dispatch(semantic, action, id)
end

-- A mage's generic automatic helper is paused only while its own Thunder
-- request is waiting or in flight. COR's request is polled without consuming
-- its native tick. Typed/manual actions are never filtered.
function M.user_job_tick()
    if active and HELPER_TICK_JOBS[current_job()] and queue_request then
        return poll_request()
    end
    return false
end

function M.prerender()
    local now = os.clock()
    maintain_rdm_na(now)
    if not queue_request or now < next_request_poll then return false end
    next_request_poll = now + REQUEST_POLL
    return poll_request()
end

function M.job_aftercast(spell, spell_map, event_args)
    local request = queue_request
    if not request or not request.inflight_until or not spell
        or tonumber(spell.id) ~= request.action_id
    then
        return
    end
    if spell.interrupted then
        request.inflight_until = nil
        request.next_attempt = os.clock() + REQUEST_RETRY
        if request.attempts >= REQUEST_MAX_ATTEMPTS
            or os.clock() >= request.expires
        then
            clear_request(request.action_name..' was interrupted')
        end
    else
        request_completed = request_completed + 1
        clear_request(request.action_name..' completed')
    end
end

function M.action_event(action)
    local request = queue_request
    local expected_category = request and request.kind == 'spell' and 4 or 6
    if not request or not request.inflight_until or type(action) ~= 'table'
        or tonumber(action.category) ~= expected_category
        or tonumber(action.param) ~= request.action_id
    then
        return
    end
    local current, live = current_player()
    local player_id = tonumber(current and current.id)
        or tonumber(live and live.id)
    if tonumber(action.actor_id) ~= player_id then return end
    local expected_target = request.self_target and player_id or request.id
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == expected_target then
            local result = target.actions and target.actions[1]
            if result and FAILURE_MESSAGES[tonumber(result.message)] then
                request.inflight_until = nil
                request.next_attempt = os.clock() + REQUEST_RETRY
                if request.attempts >= REQUEST_MAX_ATTEMPTS
                    or os.clock() >= request.expires
                then
                    clear_request('server rejected '..request.action_name)
                end
            else
                request_completed = request_completed + 1
                clear_request(request.action_name..' completed')
            end
            return
        end
    end
end

-- Manual actions are unconditionally passed through, including while an
-- automatic Thunder request is waiting for its next legal opportunity.
function M.filter_pretarget(spell, spell_map, event_args)
    return false
end

function M.filter_precast(spell, spell_map, event_args)
    return false
end

function M.status()
    local queue = queue_request
        and (queue_request.action_name..'#'..tostring(queue_request.id))
        or 'idle'
    return ('manual-pass-through thunder=%s queue=%s dispatched=%d completed=%d rejected=%d')
        :format(combat_binding and 'bound' or 'unbound', queue,
            dispatched, request_completed, rejected)
end

function M.file_unload(...)
    return M.deactivate('GearSwap job file unloaded')
end

function M.zone_change(...)
    combat_binding = nil
    clear_request('zone changed')
    restore_rdm_na()
end

function M.status_change(new_status, ...)
    if new_status == 2
        or type(new_status) == 'string'
            and new_status:lower():find('dead', 1, true)
    then
        combat_binding = nil
        clear_request('character died')
        restore_rdm_na()
    end
end

function M.logout(...)
    return M.deactivate('logout')
end

function M.unload(...)
    return M.deactivate('GearSwap unloaded')
end

return M
