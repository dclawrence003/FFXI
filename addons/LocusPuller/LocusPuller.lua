_addon.name = 'LocusPuller'
_addon.author = 'OpenAI Codex'
_addon.version = '2.1.9'
_addon.command = 'lp'
_addon.commands = {'lp', 'locuspuller'}

local packets = require('packets')

local EXPECTED_CHARACTER = 'Tackleberry'
local TARGET_NAME = 'Locus Dire Bat'
local OWNED_ZONE = 190
local FLASH_ID = 112
local MAX_DISTANCE = 20
local DEAD_BAT_SUPPRESSION_SECONDS = 5
local POLL_SECONDS = 0.20
local RETRY_SECONDS = 2.0
local ENGAGE_RETRY_SECONDS = 0.35
local GATE_RETRY_SECONDS = 0.35
local GATE_RETRY_LIMIT = 4
local FLASH_DISPATCH_RETRY_SECONDS = 0.50
local FLASH_DISPATCH_WINDOW = 5
local FLASH_CONFIRM_TIMEOUT = 8
local LEGACY_FIRST_MELEE_TIMEOUT = 3
-- PartyOps observed distant Flash pulls taking as long as 16.462 seconds from
-- Flash completion to Tackleberry's first melee packet. Keep the opener lane
-- reserved long enough for that normal travel, with a bounded margin.
local FIRST_MELEE_TIMEOUT = 20
local GS_RELOAD_GRACE = 25
local ADAPTER_CONTROLLER = 'locus-signet'
local ADAPTER_PROTOCOL = '2'
local FAST_GATE_PROFILE_VERSIONS = {
    ['1.4.0']=true,
    ['1.5.0']=true,
    ['1.6.0']=true,
    ['1.7.0']=true,
    ['1.8.0']=true,
    ['1.8.1']=true,
}
local EXPECTED_ROSTER_SIZE = 6

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

local enabled = false
local paused = false
local pause_reason = nil
local mode = 'standard'
local pt_bound = false
local pt_generation = nil
local pt_epoch = nil
local pt_profile_id = nil
local pt_profile_version = nil
local pt_engine_version = nil
local pt_signature = nil
local pt_leader = nil
local pt_roster_token = nil
local pt_roster_set = {}
local operator_armed = false
local operator_revision = nil
local last_poll = 0
local last_attempt = 0
local pending_target_id = nil
local opening_target_id = nil
local opening_started_at = 0
local flash_command_issued = false
local flash_dispatched = false
local flash_dispatch_attempts = 0
local next_flash_dispatch_at = 0
local flash_finished = false
local gate_acknowledged = false
local gate_requests = 0
local next_gate_request_at = 0
local first_melee_deadline = 0
local next_engage_at = 0
local drain_generation = nil
local drain_epoch = nil
local drain_cycle = nil
local drain_waiting = false
local last_drained_generation = nil
local last_drained_epoch = nil
local last_drained_cycle = nil
local last_resumed_cycle = nil
local reload_pending = false
local reload_deadline = 0
local retired_authorities = {}
local reload_handoff = nil
local stopped_generations = {}
local pending_authority = nil
local recently_killed_bats = {}

local function fast_gate_profile()
    return FAST_GATE_PROFILE_VERSIONS[pt_profile_version] == true
end

local function chat(message, color)
    windower.add_to_chat(color or 207, '[LocusPuller] '..message)
end

local function player()
    return windower.ffxi.get_player()
end

local function acknowledge_adapter_binding(generation, epoch)
    local p = player()
    if not pt_bound or not p or type(p.name) ~= 'string'
        or type(p.main_job) ~= 'string'
        or generation ~= pt_generation or tonumber(epoch) ~= pt_epoch
    then
        return false
    end
    windower.send_command(
        ('gs c ptgs action %s companion-ready %s %d %s lp %s %s %s %s %s %s')
            :format(ADAPTER_CONTROLLER, pt_generation, pt_epoch,
                ADAPTER_PROTOCOL, pt_profile_id, pt_profile_version,
                pt_engine_version, pt_signature, p.name, p.main_job))
    return true
end

local function in_owned_zone()
    local info = windower.ffxi.get_info and windower.ffxi.get_info() or nil
    return type(info) == 'table' and info.logged_in ~= false
        and tonumber(info.zone) == OWNED_ZONE
end

local function engaged(p)
    return p and (p.status == 1 or p.status == 'Engaged')
end

local function valid_generation(generation)
    return type(generation) == 'string'
        and generation:match('^[0-9]+%-[0-9]+%-[0-9]+$') ~= nil
end

local function valid_epoch(epoch)
    epoch = tonumber(epoch)
    return epoch and epoch >= 0 and epoch <= 2147483647
        and epoch == math.floor(epoch)
end

local function valid_revision(revision)
    revision = tonumber(revision)
    return revision and revision >= 0 and revision <= 2147483647
        and revision == math.floor(revision) and revision or nil
end

local function valid_token(value, max_length)
    return type(value) == 'string' and #value > 0
        and #value <= (max_length or 96)
        and value:match('^[A-Za-z0-9_.-]+$') ~= nil
end

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function split(value, separator)
    local result = {}
    if type(value) ~= 'string' then return result end
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
end

local function roster_identity(roster_token, leader)
    local roster, seen = split(roster_token, ','), {}
    if #roster ~= EXPECTED_ROSTER_SIZE or not valid_name(leader) then
        return nil
    end
    for _, name in ipairs(roster) do
        if not valid_name(name) or seen[name] then return nil end
        seen[name] = true
    end
    if not seen[leader] or not seen[EXPECTED_CHARACTER] then return nil end
    return seen
end

local function authority_key(generation, epoch)
    return tostring(generation)..'|'..tostring(tonumber(epoch))
end

local function retire_authority(generation, epoch)
    if generation ~= nil and epoch ~= nil then
        retired_authorities[authority_key(generation, epoch)] = true
    end
end

local function authority_is_retired(generation, epoch)
    return stopped_generations[tostring(generation)] == true
        or retired_authorities[authority_key(generation, epoch)] == true
end

local function reload_handoff_is_live()
    if not reload_handoff then return false end
    if os.clock() >= reload_handoff.deadline then
        -- Expiry is a failed recovery transaction, not an ordinary unbind.
        -- Fence both the detached predecessor and any explicitly authorized
        -- successor before discarding the metadata that identifies them.
        if reload_handoff.generation then
            stopped_generations[tostring(reload_handoff.generation)] = true
        end
        if reload_handoff.authorized_generation then
            stopped_generations[tostring(
                reload_handoff.authorized_generation)] = true
        end
        reload_handoff = nil
        return false
    end
    return true
end

local function successor_is_authorized(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    return reload_handoff_is_live()
        and reload_handoff.authorized_generation == generation
        and reload_handoff.authorized_epoch == tonumber(epoch)
        and reload_handoff.profile_id == profile_id
        and reload_handoff.profile_version == profile_version
        and reload_handoff.engine == engine
        and reload_handoff.signature == signature
        and reload_handoff.leader == leader
        and reload_handoff.roster_token == roster_token
end

local pending_authority_is_live
local pending_authority_matches

local function authorize_successor(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    epoch = tonumber(epoch)
    local roster_set = roster_identity(roster_token, leader)
    if not valid_generation(generation) or not valid_epoch(epoch)
        or not in_owned_zone()
        or authority_is_retired(generation, epoch)
        or not valid_token(profile_id) or not valid_token(profile_version)
        or not valid_token(engine) or not valid_token(signature, 160)
        or not roster_set
    then
        chat('Ignored invalid PartyTactics authority authorization.', 123)
        return false
    end
    if not pt_bound and not reload_handoff_is_live() then
        if pending_authority_is_live()
            and not pending_authority_matches(generation, epoch, profile_id,
                profile_version, engine, signature, leader, roster_token)
        then
            chat('Ignored conflicting pending PartyTactics authorization.', 123)
            return false
        end
        pending_authority = {
            generation=generation, epoch=epoch, profile_id=profile_id,
            profile_version=profile_version, engine=engine,
            signature=signature, leader=leader, roster_token=roster_token,
            roster_set=roster_set, deadline=os.clock() + GS_RELOAD_GRACE,
        }
        return true
    end
    if not reload_handoff_is_live() or epoch ~= 0
        or generation == reload_handoff.generation
        or (reload_handoff.authorized_generation ~= nil
            and (reload_handoff.authorized_generation ~= generation
                or reload_handoff.authorized_epoch ~= epoch))
        or reload_handoff.profile_id ~= profile_id
        or reload_handoff.profile_version ~= profile_version
        or reload_handoff.engine ~= engine
        or reload_handoff.signature ~= signature
        or reload_handoff.leader ~= leader
        or reload_handoff.roster_token ~= roster_token
    then
        chat('Ignored unauthorized PartyTactics recovery successor.', 123)
        return false
    end
    reload_handoff.authorized_generation = generation
    reload_handoff.authorized_epoch = epoch
    return true
end

pending_authority_is_live = function()
    if not pending_authority then return false end
    if os.clock() >= pending_authority.deadline then
        -- An initial authorization that never reaches bindpt is terminally
        -- consumed at expiry; its delayed bind must not become a fresh bind.
        if pending_authority.generation then
            stopped_generations[tostring(pending_authority.generation)] = true
        end
        pending_authority = nil
        return false
    end
    return true
end

pending_authority_matches = function(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    return pending_authority_is_live()
        and pending_authority.generation == generation
        and pending_authority.epoch == tonumber(epoch)
        and pending_authority.profile_id == profile_id
        and pending_authority.profile_version == profile_version
        and pending_authority.engine == engine
        and pending_authority.signature == signature
        and pending_authority.leader == leader
        and pending_authority.roster_token == roster_token
end

local function stop_metadata_matches(engine, profile_id, profile_version,
    signature, source)
    if not valid_name(source) then return false end
    if pt_bound and engine == pt_engine_version
        and profile_id == pt_profile_id
        and profile_version == pt_profile_version
        and signature == pt_signature and pt_roster_set[source]
    then
        return true
    end
    if reload_handoff_is_live()
        and engine == reload_handoff.engine
        and profile_id == reload_handoff.profile_id
        and profile_version == reload_handoff.profile_version
        and signature == reload_handoff.signature
    then
        for _, name in ipairs(split(reload_handoff.roster_token, ',')) do
            if name == source then return true end
        end
    end
    return pending_authority_is_live()
        and engine == pending_authority.engine
        and profile_id == pending_authority.profile_id
        and profile_version == pending_authority.profile_version
        and signature == pending_authority.signature
        and pending_authority.roster_set[source] == true
end

local function exact_authority(generation, epoch)
    return pt_bound and generation == pt_generation
        and tonumber(epoch) == pt_epoch
end

local function self_mob()
    return windower.ffxi.get_mob_by_target('me')
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

-- Turning is not movement. Keep Tackle facing the exact opener target while
-- it closes from any direction, but never ask Windower to run or reposition.
local function face_mob(mob)
    local me = self_mob()
    local turn = windower.ffxi and windower.ffxi.turn
    local me_x, me_y = tonumber(me and me.x), tonumber(me and me.y)
    local mob_x, mob_y = tonumber(mob and mob.x), tonumber(mob and mob.y)
    if type(turn) ~= 'function' or not me_x or not me_y
        or not mob_x or not mob_y
    then
        return false
    end
    local dx, dy = mob_x - me_x, mob_y - me_y
    if dx * dx + dy * dy <= 0.01 then return false end
    turn(-atan2(dy, dx))
    return true
end

local function distance_to(me, mob)
    if me and mob and me.x and me.y and mob.x and mob.y then
        local dx, dy = mob.x - me.x, mob.y - me.y
        return math.sqrt(dx * dx + dy * dy)
    end
    return math.sqrt(tonumber(mob and mob.distance) or math.huge)
end

local function party_ids()
    local result = {}
    for _, member in pairs(windower.ffxi.get_party() or {}) do
        local id = nil
        if type(member) == 'table' then
            if type(member.mob) == 'table' then
                id = tonumber(member.mob.id)
            else
                id = tonumber(member.mob) or tonumber(member.id)
            end
        else
            id = tonumber(member)
        end
        if id then result[id] = true end
    end
    local me = self_mob()
    if me and me.id then result[tonumber(me.id)] = true end
    return result
end

local function recently_killed(mob)
    local id = tonumber(mob and mob.id)
    local entry = id and recently_killed_bats[id]
    if not entry then return false end
    if os.clock() >= entry.expires_at then
        recently_killed_bats[id] = nil
        return false
    end
    return tonumber(mob.index) == entry.index
end

local function eligible(mob, me, claimed_by_party)
    if not mob or mob.name ~= TARGET_NAME or tonumber(mob.spawn_type) ~= 16
        or not tonumber(mob.id) or not tonumber(mob.index)
        or mob.valid_target == false or (tonumber(mob.hpp) or 0) <= 0
        or recently_killed(mob)
    then
        return false
    end
    local claim_id = tonumber(mob.claim_id) or 0
    if claim_id ~= 0 and not claimed_by_party[claim_id] then
        return false
    end
    return distance_to(me, mob) <= MAX_DISTANCE
end

local function nearest_bat()
    local me = self_mob()
    if not me then return nil end
    local claimed_by_party = party_ids()
    local best, best_distance = nil, math.huge
    for _, mob in pairs(windower.ffxi.get_mob_array() or {}) do
        if eligible(mob, me, claimed_by_party) then
            local distance = distance_to(me, mob)
            if distance < best_distance
                or distance == best_distance and tonumber(mob.id) < tonumber(best.id)
            then
                best, best_distance = mob, distance
            end
        end
    end
    return best, best_distance
end

local function select_target(mob)
    local me = self_mob()
    if not me or not mob then return false end
    packets.inject(packets.new('incoming', 0x058, {
        ['Player'] = me.id,
        ['Target'] = mob.id,
        ['Player Index'] = me.index,
    }))
    face_mob(mob)
    return true
end

local function action_result(action, target_id)
    for _, target in ipairs(action and action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id) then
            return target.actions and target.actions[1] or nil
        end
    end
    return nil
end

local function opener_adapter_command(action, target_id, keepoff)
    if not pt_bound or not target_id then return nil end
    local command = ('gs c ptgs action %s %s %s %s %s %s')
        :format(ADAPTER_CONTROLLER, action, tostring(target_id),
            pt_generation, tostring(pt_epoch), ADAPTER_PROTOCOL)
    if keepoff then command = command..' keepoff' end
    return command
end

local function request_opener_gate()
    if not opening_target_id or gate_acknowledged
        or gate_requests >= GATE_RETRY_LIMIT
    then
        return false
    end
    local command = opener_adapter_command('opener-arm', opening_target_id)
    if not command then return false end
    windower.send_command(command)
    gate_requests = gate_requests + 1
    next_gate_request_at = os.clock() + GATE_RETRY_SECONDS
    return true
end

local function clear_opening(keepoff)
    if opening_target_id then
        local command = opener_adapter_command('opener-release',
            opening_target_id, keepoff == true)
        if command then windower.send_command(command) end
    end
    opening_target_id = nil
    opening_started_at = 0
    flash_finished = false
    flash_command_issued = false
    flash_dispatched = false
    flash_dispatch_attempts = 0
    next_flash_dispatch_at = 0
    gate_acknowledged = false
    gate_requests = 0
    next_gate_request_at = 0
    first_melee_deadline = 0
    next_engage_at = 0
    pending_target_id = nil
end

local function report_drain_complete()
    if not drain_generation or opening_target_id or engaged(player()) then
        return false
    end
    local generation, epoch, cycle = drain_generation, drain_epoch,
        drain_cycle
    if not cycle then return false end
    paused = true
    pause_reason = 'signet'
    drain_waiting = false
    drain_generation = nil
    drain_epoch = nil
    drain_cycle = nil
    last_drained_generation = generation
    last_drained_epoch = epoch
    last_drained_cycle = cycle
    windower.send_command(('sk __pullerdrained %s %s %s')
        :format(generation, tostring(epoch), tostring(cycle)))
    chat('Drain complete: no opener is pending and Tackleberry is idle.')
    return true
end

local function report_resume_complete(cycle)
    if not pt_bound or not cycle then return false end
    windower.send_command(('sk __pullerresumed %s %s %s')
        :format(pt_generation, tostring(pt_epoch), tostring(cycle)))
    return true
end

local function arm_opening(target_id)
    if not pt_bound then return false end
    opening_target_id = tonumber(target_id)
    opening_started_at = os.clock()
    flash_command_issued = false
    flash_dispatched = false
    flash_dispatch_attempts = 0
    next_flash_dispatch_at = 0
    flash_finished = false
    gate_acknowledged = false
    gate_requests = 0
    next_gate_request_at = 0
    first_melee_deadline = 0
    next_engage_at = 0
    -- The pinned adapter is the sole AutoWS2/routine owner. A few idempotent
    -- gate requests can repair a dropped command/ACK, while only the adapter
    -- owns the single effective OFF/ON edge and its chat behavior.
    if not request_opener_gate() then
        clear_opening()
        return false
    end
    return true
end

local function request_engage()
    local may_settle_issued_flash = flash_command_issued
    if mode ~= 'firsthit' or (not may_settle_issued_flash
        and (not enabled or paused))
        or not opening_target_id or not flash_finished
        or os.clock() < next_engage_at
    then
        return false
    end
    local live = windower.ffxi.get_mob_by_id(opening_target_id)
    local p = player()
    if not live or (tonumber(live.hpp) or 0) <= 0 or not p then
        clear_opening()
        return false
    end
    local target = windower.ffxi.get_mob_by_target('t')
    if not target or tonumber(target.id) ~= tonumber(live.id) then
        select_target(live)
    else
        face_mob(live)
    end
    next_engage_at = os.clock() + ENGAGE_RETRY_SECONDS
    if p.status == 0 or p.status == 'Idle' then
        windower.send_command('input /attack on')
        return true
    end
    return false
end

local function flash_ready()
    local p = player()
    if not p or not p.vitals or (tonumber(p.vitals.mp) or 0) < 25 then
        return false
    end
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return (tonumber(recasts[FLASH_ID]) or 0) <= 0
end

local function issue_flash_command(mob, announce)
    local me = self_mob()
    if not enabled or paused or not eligible(mob, me, party_ids())
    then
        if mode == 'firsthit' then clear_opening() end
        return false
    end
    local live = windower.ffxi.get_mob_by_id(mob.id)
    if not eligible(live, me, party_ids()) then
        if mode == 'firsthit' then clear_opening() end
        return false
    end
    local fast_dispatch = mode == 'firsthit' and fast_gate_profile()
    if fast_dispatch then
        if flash_dispatched or tonumber(live.id) ~= opening_target_id
            or os.clock() - opening_started_at > FLASH_DISPATCH_WINDOW
        then
            return false
        end
        local target = windower.ffxi.get_mob_by_target('t')
        if not target or tonumber(target.id) ~= opening_target_id then
            select_target(live)
            next_flash_dispatch_at = os.clock() + POLL_SECONDS
            return false
        end
    end
    if not flash_ready() then
        next_flash_dispatch_at = os.clock() + FLASH_DISPATCH_RETRY_SECONDS
        return false
    end
    last_attempt = os.clock()
    windower.send_command('input /ma "Flash" <t>')
    flash_command_issued = true
    flash_dispatch_attempts = flash_dispatch_attempts + 1
    next_flash_dispatch_at = os.clock() + FLASH_DISPATCH_RETRY_SECONDS
    if announce then
        chat(('Flash pull: %s [#%d]'):format(TARGET_NAME,
            tonumber(mob.index)))
    end
    if mode == 'standard'
        or (mode == 'firsthit' and not fast_dispatch)
    then
        flash_dispatched = true
    end
    if mode == 'standard' then
        coroutine.schedule(function()
            if not enabled or paused then return end
            local target = windower.ffxi.get_mob_by_target('t')
            local p = player()
            if target and tonumber(target.id) == tonumber(mob.id)
                and (tonumber(target.hpp) or 0) > 0 and p and p.status == 0
            then
                windower.send_command('input /attack on')
                chat('Engaged pulled bat in place.')
            end
        end, 1.0)
    end
    return true
end

local function retry_flash_dispatch()
    if mode ~= 'firsthit' or not opening_target_id
        or flash_dispatched or not gate_acknowledged
    then
        return false
    end
    local live = windower.ffxi.get_mob_by_id(opening_target_id)
    return issue_flash_command(live, flash_dispatch_attempts == 0)
end

local function select_and_queue_flash(mob)
    if not enabled or paused or not mob
        or tonumber(pending_target_id) ~= tonumber(mob.id)
    then
        return false
    end
    local live = windower.ffxi.get_mob_by_id(mob.id)
    if not eligible(live, self_mob(), party_ids()) then
        if mode == 'firsthit' then clear_opening() end
        return false
    end
    if not select_target(live) then
        if mode == 'firsthit' then clear_opening() end
        return false
    end
    last_attempt = os.clock()
    local me = self_mob()
    chat(('Targeted nearest %s at %.1f yalms.'):format(
        TARGET_NAME, distance_to(me, live)))
    coroutine.schedule(function()
        if enabled and not paused and pending_target_id == live.id then
            issue_flash_command(live, true)
        end
    end, 0.20)
    return true
end

local function acquire_and_pull()
    local p = player()
    if paused or drain_waiting or opening_target_id or not p
        or p.name ~= EXPECTED_CHARACTER or p.status == 1
        or p.status == 2 or p.status == 3
        or os.clock() - last_attempt < RETRY_SECONDS
    then
        return
    end

    local mob = nearest_bat()
    if not mob or not flash_ready() then return end

    pending_target_id = mob.id
    if mode == 'firsthit' then
        -- Do not expose the target to any GearSwap heartbeat until the exact
        -- PartyTactics adapter acknowledges its bounded PLD routine gate.
        arm_opening(mob.id)
        return
    end
    select_and_queue_flash(mob)
end

local function record_pull_retry()
    last_attempt = os.clock()
    if fast_gate_profile() then
        -- The fast-gate path already completed its bounded dispatch attempt. Do not
        -- add the standalone helper's historical two-second reset delay.
        last_attempt = last_attempt - RETRY_SECONDS
    end
end

local function operator_command(value, generation, epoch, revision,
    resume_cycle, cycle)
    if not exact_authority(generation, epoch) then
        chat('Ignored stale PartyTactics operator command.', 123)
        return false
    end
    revision = valid_revision(revision)
    if revision == nil then
        chat('Ignored invalid PartyTactics operator revision.', 123)
        return false
    end
    local desired = value == 'on'
    local same_revision = false
    local stale_resume = false
    if operator_revision ~= nil then
        if revision < operator_revision then
            if not resume_cycle then
                chat('Ignored lower PartyTactics operator revision.', 123)
                return false
            end
            -- A maintenance resume is also the transaction's liveness edge.
            -- If it was captured before a newer operator transition, finish
            -- the exact completed cycle from the current high-water instead
            -- of either replaying the stale bit or leaving the puller paused.
            revision = operator_revision
            desired = operator_armed
            stale_resume = true
        elseif revision == operator_revision
            and desired ~= operator_armed
        then
            chat('Ignored conflicting PartyTactics operator revision.', 123)
            return false
        elseif revision == operator_revision then
            same_revision = true
        end
    end
    cycle = tonumber(cycle)
    if resume_cycle and (not cycle or cycle ~= last_drained_cycle
        or cycle < (tonumber(last_resumed_cycle) or 0)
        or drain_waiting or (drain_cycle and drain_cycle > cycle))
    then
        chat('Ignored stale PartyTactics renewal resume.', 123)
        return false
    end
    operator_revision = revision
    operator_armed = desired
    if resume_cycle then
        local duplicate_resume = cycle == last_resumed_cycle
        -- Resume owns only completion of the matching Signet transaction. It
        -- applies the current operator effect and clears that mechanical pause,
        -- but does not reset acquisition cadence or any opener state. This is
        -- deliberately distinct from a strictly newer ON/OFF transition.
        last_resumed_cycle = cycle
        enabled = operator_armed
        paused = false
        pause_reason = nil
        drain_generation = nil
        drain_epoch = nil
        drain_cycle = nil
        drain_waiting = false
        report_resume_complete(cycle)
        if duplicate_resume then return true end
        chat(stale_resume
            and 'Stale Signet resume completed from the newer operator state.'
            or 'Signet maintenance resumed from the current operator state.')
        return true
    end
    if operator_armed then
        if drain_waiting or pause_reason == 'signet' then
            enabled = true
            chat('PartyTactics operator ON recorded; Signet drain remains in control.')
            return true
        end
        -- Periodic/equal state is an idempotent reconcile, not a transition.
        -- Heal only the local enabled bit. Preserve the active opener, pause,
        -- retry cadence, and every other in-flight pull state even if a local
        -- `lp off` temporarily removed that effect. Only a strictly newer
        -- operator transition is allowed to reset those mechanics below.
        if same_revision then
            enabled = true
            return true
        end
        enabled = true
        paused = false
        pause_reason = nil
        drain_generation = nil
        drain_epoch = nil
        drain_cycle = nil
        drain_waiting = false
        -- OFF deliberately preserves an issued Flash until its action result.
        -- A rapid authoritative ON must preserve the same in-flight opener;
        -- clearing it here could select and Flash a second bat while the first
        -- command is still resolving.
        if not flash_command_issued then
            last_attempt = 0
            clear_opening()
        end
        chat('PartyTactics operator ON: stationary first-hit pulling enabled.')
    else
        enabled = false
        -- Likewise, an equal/same OFF replay must not disturb an in-flight
        -- drain, opener, or acquisition cadence.
        if same_revision then return true end
        -- Once Flash has actually been issued, a drain must retain the opener
        -- until its success/failure packet or bounded timeout. Clearing it here
        -- could acknowledge idle while the queued spell is still about to pull.
        if not flash_command_issued then
            clear_opening()
        end
        -- Alt-P during a Signet drain must not strand the six-client barrier.
        -- Preserve the exact drain authority and acknowledge it as soon as the
        -- current engagement ends; no future acquisition can start.
        local p = player()
        if drain_waiting and not engaged(p) then report_drain_complete() end
        chat('PartyTactics operator OFF: automatic pulling stopped.')
    end
    return true
end

windower.register_event('prerender', function()
    if os.clock() - last_poll < POLL_SECONDS then return end
    last_poll = os.clock()
    if reload_pending and os.clock() >= reload_deadline then
        reload_pending = false
        reload_deadline = 0
    end
    if opening_target_id then
        local live = windower.ffxi.get_mob_by_id(opening_target_id)
        if not live or (tonumber(live.hpp) or 0) <= 0 then
            clear_opening()
        elseif not flash_finished
            and os.clock() - opening_started_at > FLASH_CONFIRM_TIMEOUT
        then
            chat('Flash completion was not confirmed; opener released for retry.', 123)
            clear_opening()
            record_pull_retry()
        elseif fast_gate_profile()
            and not gate_acknowledged and not flash_command_issued
            and gate_requests < GATE_RETRY_LIMIT
            and os.clock() >= next_gate_request_at
        then
            request_opener_gate()
        elseif fast_gate_profile()
            and gate_acknowledged and not flash_dispatched
            and os.clock() - opening_started_at <= FLASH_DISPATCH_WINDOW
            and os.clock() >= next_flash_dispatch_at
        then
            retry_flash_dispatch()
        elseif flash_finished and os.clock() >= first_melee_deadline then
            chat('First-melee confirmation timed out; routine actions released.', 123)
            clear_opening()
            record_pull_retry()
        else
            request_engage()
        end
        if drain_waiting and not opening_target_id and not engaged(player()) then
            report_drain_complete()
        end
        return
    end
    if drain_waiting then
        local p = player()
        if p and not engaged(p) then report_drain_complete() end
        return
    end
    if not enabled or paused then return end
    acquire_and_pull()
end)

windower.register_event('outgoing chunk', function(id, original, modified,
    injected, blocked)
    if id ~= 0x01A or blocked or mode ~= 'firsthit'
        or not fast_gate_profile()
        or not opening_target_id or flash_dispatched
    then
        return
    end
    local raw = modified
    if type(raw) ~= 'string' or #raw == 0 then raw = original end
    local packet = nil
    if type(raw) == 'table' then
        packet = raw
    elseif type(packets.parse) == 'function' then
        local ok, parsed = pcall(packets.parse, 'outgoing', raw)
        if ok then packet = parsed end
    end
    if type(packet) ~= 'table'
        or tonumber(packet['Category']) ~= 3
        or tonumber(packet['Param']) ~= FLASH_ID
        or tonumber(packet['Target']) ~= opening_target_id
    then
        return
    end
    local live = windower.ffxi.get_mob_by_id(opening_target_id)
    local packet_index = tonumber(packet['Target Index'])
    if packet_index and live and tonumber(live.index)
        and packet_index ~= tonumber(live.index)
    then
        return
    end
    flash_dispatched = true
end)

local function packet_u16(bytes, offset)
    local a, b = bytes:byte(offset + 1, offset + 2)
    if not b then return nil end
    return a + b * 256
end

local function packet_u32(bytes, offset)
    local low, high = packet_u16(bytes, offset), packet_u16(bytes, offset + 2)
    if not low or not high then return nil end
    return low + high * 65536
end

windower.register_event('incoming chunk', function(id, original, modified,
    injected, blocked)
    if id ~= 0x02D or injected or blocked or not in_owned_zone()
        or type(original) ~= 'string' or #original < 26
    then
        return
    end
    local message = packet_u16(original, 0x18)
    if not message or (message % 32768 ~= 371
        and message % 32768 ~= 372)
    then
        return
    end
    local actor_id = packet_u32(original, 0x04)
    local target_id = packet_u32(original, 0x08)
    local target_index = packet_u16(original, 0x0E)
    if not actor_id or not target_id or actor_id == target_id
        or not target_index then
        return
    end
    local mob = windower.ffxi.get_mob_by_id(target_id)
    if not mob or mob.name ~= TARGET_NAME
        or tonumber(mob.spawn_type) ~= 16
        or tonumber(mob.id) ~= target_id
        or tonumber(mob.index) ~= target_index
    then
        return
    end
    recently_killed_bats[target_id] = {
        index = target_index,
        expires_at = os.clock() + DEAD_BAT_SUPPRESSION_SECONDS,
    }
end)

windower.register_event('action', function(action)
    local p = player()
    local may_settle_issued_flash = flash_command_issued
    if mode ~= 'firsthit' or (not may_settle_issued_flash
        and (not enabled or paused)) or not p
        or not opening_target_id
        or tonumber(action and action.actor_id) ~= tonumber(p.id)
    then
        return
    end
    local result = action_result(action, opening_target_id)
    if not result then return end
    if action.category == 4 and tonumber(action.param) == FLASH_ID then
        flash_dispatched = true
        local message = tonumber(result.message)
        if FAILURE_MESSAGES[message] then
            chat('Flash returned a failure result; opener released for retry.', 123)
            clear_opening()
            record_pull_retry()
            return
        end
        flash_finished = true
        local melee_timeout = fast_gate_profile()
            and FIRST_MELEE_TIMEOUT or LEGACY_FIRST_MELEE_TIMEOUT
        first_melee_deadline = os.clock() + melee_timeout
        next_engage_at = 0
        request_engage()
        chat('Flash succeeded; first melee has bounded routine priority.')
    elseif action.category == 1 then
        local completed_id = opening_target_id
        clear_opening()
        chat('First melee established on '..tostring(completed_id)
            ..'; normal PLD actions released.')
    end
end)

local function retire_transient_authorities()
    -- Terminal teardown can overtake a queued full-profile recovery arm. Fence
    -- both sides of that handoff before clearing it so delayed commands cannot
    -- re-enable first-hit pulling after a stop, zone, or logout.
    if pt_bound and pt_generation then
        stopped_generations[pt_generation] = true
    end
    if pending_authority and pending_authority.generation then
        stopped_generations[pending_authority.generation] = true
    end
    if reload_handoff then
        if reload_handoff.generation then
            stopped_generations[reload_handoff.generation] = true
        end
        if reload_handoff.authorized_generation then
            stopped_generations[reload_handoff.authorized_generation] = true
        end
    end
end

local function reset_to_standard(keep_autows_off, preserve_reload_handoff)
    if not preserve_reload_handoff then retire_transient_authorities() end
    if pt_bound then retire_authority(pt_generation, pt_epoch) end
    enabled = false
    paused = false
    pause_reason = nil
    operator_armed = false
    operator_revision = nil
    drain_generation = nil
    drain_epoch = nil
    drain_cycle = nil
    drain_waiting = false
    last_drained_generation = nil
    last_drained_epoch = nil
    last_drained_cycle = nil
    last_resumed_cycle = nil
    recently_killed_bats = {}
    clear_opening(keep_autows_off == true)
    pt_bound = false
    pt_generation = nil
    pt_epoch = nil
    pt_profile_id = nil
    pt_profile_version = nil
    pt_engine_version = nil
    pt_signature = nil
    pt_leader = nil
    pt_roster_token = nil
    pt_roster_set = {}
    reload_pending = false
    reload_deadline = 0
    if not preserve_reload_handoff then reload_handoff = nil end
    pending_authority = nil
    mode = 'standard'
end

local function bind_new_authority(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token, roster_set,
    revision, operator)
    if pt_bound then retire_authority(pt_generation, pt_epoch) end
    clear_opening()
    pt_bound = true
    pt_generation = generation
    pt_epoch = epoch
    pt_profile_id = profile_id
    pt_profile_version = profile_version
    pt_engine_version = engine
    pt_signature = signature
    pt_leader = leader
    pt_roster_token = roster_token
    pt_roster_set = roster_set
    mode = 'firsthit'
    enabled = false
    paused = false
    pause_reason = nil
    operator_revision = revision
    operator_armed = operator == '1'
    drain_generation = nil
    drain_epoch = nil
    drain_cycle = nil
    drain_waiting = false
    last_drained_generation = nil
    last_drained_epoch = nil
    last_drained_cycle = nil
    last_resumed_cycle = nil
    reload_pending = false
    reload_deadline = 0
    pending_authority = nil
    last_attempt = 0
end

windower.register_event('zone change', function()
    local was_active = enabled or paused or pt_bound or opening_target_id
    reset_to_standard(true)
    if was_active then chat('Disabled and unbound on zone change.', 123) end
end)

windower.register_event('logout', function()
    reset_to_standard(true)
end)

windower.register_event('unload', function()
    local generation, epoch = pt_generation, pt_epoch
    local was_bound = pt_bound
    -- A raw helper unload is a recoverable component failure, not terminal
    -- PartyTactics teardown. Release an active opener normally (letting the
    -- adapter restore its reservation), then make the exact Signet coordinator
    -- abort/resume any drain or suspension that can no longer complete.
    reset_to_standard(false)
    if was_bound and generation and epoch then
        windower.send_command(('sk __pullerlost %s %s')
            :format(generation, tostring(epoch)))
    end
end)

-- Keep the authority protocol and the local/operator controls in separate
-- closures. Windower's Lua 5.1 runtime limits a function to 60 upvalues; one
-- monolithic addon-command callback crossed that limit as the recovery and
-- ordered-operator state machines grew. The dispatcher below intentionally
-- owns no runtime state beyond these two handlers.
local function handle_authority_command(command, args, p)
    if command == '__ackpt' then
        if #args == 2 then acknowledge_adapter_binding(args[1], args[2]) end
    elseif command == '__gate_armed' then
        if #args ~= 3 then return end
        local target_id = tonumber(args[1])
        if mode == 'firsthit' and pt_bound and enabled and not paused
            and target_id and target_id == opening_target_id
            and target_id == pending_target_id
            and exact_authority(args[2], args[3])
        then
            if not gate_acknowledged and not flash_command_issued then
                gate_acknowledged = true
                local live = windower.ffxi.get_mob_by_id(target_id)
                if not select_and_queue_flash(live) then clear_opening() end
            end
        end
    elseif command == 'bindpt' then
        if #args ~= 10 then return end
        local generation, epoch = tostring(args[1] or ''), tonumber(args[2])
        local profile_id, profile_version = args[3], args[4]
        local engine, signature, leader, roster_token = args[5], args[6],
            args[7], args[8]
        local incoming_revision = valid_revision(args[9])
        local incoming_operator = args[10]
        local roster_set = roster_identity(roster_token, leader)
        local authorized_successor = successor_is_authorized(generation,
            epoch, profile_id, profile_version, engine, signature, leader,
            roster_token)
        local pending_match = pending_authority_matches(generation, epoch,
            profile_id, profile_version, engine, signature, leader,
            roster_token)
        local matching_identity = pt_profile_id == profile_id
            and pt_profile_version == profile_version
            and pt_engine_version == engine and pt_signature == signature
            and pt_leader == leader and pt_roster_token == roster_token
        if not p or p.name ~= EXPECTED_CHARACTER then
            chat('Refusing PartyTactics bind: Tackleberry only.', 123)
        elseif not valid_generation(generation) or not valid_epoch(epoch)
            or not valid_token(profile_id) or not valid_token(profile_version)
            or not valid_token(engine) or not valid_token(signature, 160)
            or not roster_set or incoming_revision == nil
            or (incoming_operator ~= '0' and incoming_operator ~= '1')
        then
            chat('Refusing invalid PartyTactics authority.', 123)
        elseif not in_owned_zone() then
            reset_to_standard(true)
            chat('Refusing PartyTactics bind outside the Locus Dire Bat battlefield.', 123)
        elseif authority_is_retired(generation, epoch) then
            chat('Ignored retired PartyTactics first-hit binding.', 123)
        elseif exact_authority(generation, epoch) and matching_identity then
            -- GearSwap may reload while this addon process survives. Rebinding
            -- the same exact authority must not reset a drain, operator state,
            -- or in-flight opener. Reassert only the adapter's transient gate.
            mode = 'firsthit'
            if operator_revision ~= nil
                and (incoming_revision < operator_revision
                    or incoming_revision == operator_revision
                        and (incoming_operator == '1') ~= operator_armed)
            then
                chat('Ignored stale or conflicting operator tuple on PartyTactics rebind.', 123)
                return
            end
            operator_revision = incoming_revision
            operator_armed = incoming_operator == '1'
            if opening_target_id then
                gate_acknowledged = false
                gate_requests = 0
                next_gate_request_at = 0
                request_opener_gate()
            end
            -- Exact retry is intentionally silent; the following private
            -- __ackpt query proves this binding without resetting its opener,
            -- drain, or operator high-water.
        elseif pt_bound then
            local same_generation_reapply = generation == pt_generation
                and epoch > pt_epoch and matching_identity
            if not same_generation_reapply and not authorized_successor then
                chat('Ignored stale or unfenced PartyTactics first-hit binding.', 123)
            else
                local carried_revision, carried_operator = incoming_revision,
                    incoming_operator
                if same_generation_reapply and operator_revision ~= nil then
                    local current_operator = operator_armed and '1' or '0'
                    if operator_revision > carried_revision then
                        carried_revision, carried_operator = operator_revision,
                            current_operator
                    elseif operator_revision == carried_revision
                        and current_operator ~= carried_operator
                    then
                        chat('Ignored conflicting reapply operator tuple.', 123)
                        return
                    end
                end
                if authorized_successor and reload_handoff
                    and valid_revision(reload_handoff.operator_revision)
                then
                    local old_revision = reload_handoff.operator_revision
                    local old_operator = reload_handoff.operator_armed
                        and '1' or '0'
                    if old_revision > carried_revision then
                        carried_revision, carried_operator = old_revision,
                            old_operator
                    elseif old_revision == carried_revision
                        and old_operator ~= carried_operator
                    then
                        chat('Ignored conflicting recovery operator tuple.', 123)
                        return
                    end
                end
                bind_new_authority(generation, epoch, profile_id,
                    profile_version, engine, signature, leader, roster_token,
                    roster_set, carried_revision, carried_operator)
                reload_handoff = nil
                chat('Bound to replacement PartyTactics first-hit authority; awaiting Signet census relay.')
            end
        elseif reload_handoff_is_live() and not authorized_successor then
            chat('Ignored recovery bind without the exact authorized successor.', 123)
        elseif pending_authority_is_live() and not pending_match then
            chat('Ignored bind outside the pending exact authorization.', 123)
        else
            bind_new_authority(generation, epoch, profile_id, profile_version,
                engine, signature, leader, roster_token, roster_set,
                incoming_revision, incoming_operator)
            reload_handoff = nil
            chat('Bound to PartyTactics first-hit pulling; awaiting Signet census relay.')
        end
    elseif command == 'unbindpt' then
        if #args ~= 2 and not (#args == 3
            and tostring(args[3]):lower() == 'keepoff')
        then
            return
        end
        if exact_authority(args[1], args[2]) then
            local preserve = reload_handoff_is_live()
                and reload_handoff.generation == pt_generation
                and reload_handoff.old_epoch == pt_epoch
            reset_to_standard(tostring(args[3] or ''):lower() == 'keepoff',
                preserve)
            chat('PartyTactics binding released; standard mode is OFF.')
        else
            chat('Ignored stale PartyTactics unbind.', 123)
        end
    elseif command == 'gsreload' then
        if #args ~= 2 then return end
        if exact_authority(args[1], args[2]) then
            reload_pending = true
            reload_deadline = os.clock() + GS_RELOAD_GRACE
            reload_handoff = {
                generation=pt_generation,
                old_epoch=pt_epoch,
                profile_id=pt_profile_id,
                profile_version=pt_profile_version,
                engine=pt_engine_version,
                signature=pt_signature,
                leader=pt_leader,
                roster_token=pt_roster_token,
                operator_revision=operator_revision,
                operator_armed=operator_armed,
                deadline=reload_deadline,
            }
            chat('GearSwap reload noted; preserving exact puller state for idempotent rebind.')
        else
            chat('Ignored stale GearSwap reload marker.', 123)
        end
    elseif command == 'authorize' then
        if #args ~= 8 then return end
        authorize_successor(tostring(args[1] or ''), args[2], args[3],
            args[4], args[5], args[6], args[7], args[8])
    elseif command == 'retirept' then
        if #args ~= 6 then return end
        local target_generation = tostring(args[1] or '')
        if valid_generation(target_generation)
            and stop_metadata_matches(args[2], args[3], args[4], args[5],
                args[6])
        then
            stopped_generations[target_generation] = true
            local stops_current = pt_bound
                and target_generation == pt_generation
            local stops_successor = reload_handoff
                and reload_handoff.authorized_generation == target_generation
            local stops_predecessor = reload_handoff
                and reload_handoff.generation == target_generation
            local stops_pending = pending_authority
                and pending_authority.generation == target_generation
            if stops_current or stops_successor or stops_predecessor
                or stops_pending
            then
                reset_to_standard(true)
                chat('PartyTactics stop fenced automatic pulling.', 123)
            end
        end
    end
end

local function handle_control_command(command, argument, args, p)
    if command == 'operator'
        and (argument == 'on' or argument == 'off')
    then
        local resume_marker = tostring(args[5] or ''):lower() == 'resume'
        if (#args ~= 4 and not (#args == 6 and resume_marker)) then
            return
        end
        operator_command(argument, args[2], args[3], args[4],
            resume_marker, args[6])
    elseif pt_bound and (command == 'on' or command == 'mode'
        or command == 'resume' or command == 'now')
    then
        -- These addon controls mutate the automatic pull state and cannot
        -- bypass the exact PartyTactics/Signet transaction. FFXI actions are
        -- unaffected, and `lp off` remains an immediate local emergency stop.
        chat('PartyTactics owns this automatic pull control while bound.', 123)
    elseif command == 'on' then
        if not p or p.name ~= EXPECTED_CHARACTER then
            chat('Refusing to arm: this addon is restricted to Tackleberry.', 123)
            return
        end
        enabled = true
        paused = false
        pause_reason = nil
        drain_generation = nil
        drain_epoch = nil
        drain_cycle = nil
        drain_waiting = false
        last_attempt = 0
        clear_opening()
        chat(('ON: stationary nearest-bat Flash pulling enabled (%s mode).')
            :format(mode))
    elseif command == 'off' then
        enabled = false
        -- A local emergency stop changes the effect, not the replicated
        -- PartyTactics register. Replaying the same authoritative tuple can
        -- therefore heal this local side effect idempotently.
        if not pt_bound then operator_armed = false end
        if not flash_command_issued then
            clear_opening()
        end
        local current = player()
        if drain_waiting and not engaged(current) then report_drain_complete() end
        if not drain_waiting then
            paused = false
            pause_reason = nil
            drain_generation = nil
            drain_epoch = nil
            drain_cycle = nil
        end
        chat('OFF.')
    elseif command == 'mode'
        and (argument == 'standard' or argument == 'firsthit')
    then
        if argument == 'firsthit' and not pt_bound then
            chat('First-hit mode requires an exact PartyTactics binding.', 123)
            return
        end
        clear_opening()
        mode = argument
        drain_generation = nil
        drain_epoch = nil
        drain_cycle = nil
        drain_waiting = false
        chat('Mode: '..mode..'.')
    elseif command == 'drain' then
        if #args ~= 3 then return end
        local generation, epoch = tostring(args[1] or ''), tonumber(args[2])
        local cycle = tonumber(args[3])
        local valid_cycle = cycle and cycle >= 1
            and cycle == math.floor(cycle)
        if not exact_authority(generation, epoch) or not valid_cycle then
            chat('Refusing stale or invalid PartyTactics drain request.', 123)
        elseif generation == last_drained_generation
            and epoch == last_drained_epoch and paused
            and cycle == last_drained_cycle and pause_reason == 'signet'
        then
            -- Re-check the live opener and engagement before replaying a
            -- cached acknowledgment; an old cycle can never bless a new one.
            if not opening_target_id and not engaged(player()) then
                windower.send_command(('sk __pullerdrained %s %s %s')
                    :format(generation, tostring(epoch), tostring(cycle)))
            end
        elseif not drain_waiting
            and (tonumber(last_resumed_cycle) or 0)
                == (tonumber(last_drained_cycle) or 0)
            and cycle == (tonumber(last_drained_cycle) or 0) + 1
        then
            drain_generation = generation
            drain_epoch = epoch
            drain_cycle = cycle
            drain_waiting = true
            pause_reason = 'signet'
            if opening_target_id and not flash_command_issued then
                clear_opening()
            end
            local current = player()
            if not opening_target_id and not engaged(current) then
                report_drain_complete()
            else
                chat('Drain requested: finishing the current opener/fight; no next pull will start.')
            end
        end
    elseif command == 'pause' then
        paused = true
        pause_reason = argument ~= '' and argument or 'manual'
        drain_generation = nil
        drain_epoch = nil
        drain_cycle = nil
        drain_waiting = false
        clear_opening()
        chat('Paused: '..pause_reason..'.')
    elseif command == 'resume' then
        if not pause_reason or argument == '' or argument == pause_reason then
            paused = false
            pause_reason = nil
            drain_generation = nil
            drain_epoch = nil
            drain_cycle = nil
            drain_waiting = false
            last_attempt = 0
            chat(enabled and 'Resumed.' or 'Pause cleared; puller remains OFF.')
        end
    elseif command == 'now' then
        last_attempt = 0
        acquire_and_pull()
    else
        chat(('Status: %s%s; mode=%s; PT=%s gen=%s epoch=%s operator=%s@%s; opener=%s; drain=%s/%s cycle=%s; target=%s; range=%d; movement=none.')
            :format(enabled and 'ON' or 'OFF',
                paused and ' PAUSED('..tostring(pause_reason)..')' or '',
                mode, pt_bound and 'bound' or 'unbound',
                tostring(pt_generation or '-'), tostring(pt_epoch or '-'),
                operator_armed and 'on' or 'off',
                tostring(operator_revision or '-'),
                opening_target_id and tostring(opening_target_id) or 'clear',
                drain_waiting and tostring(drain_generation) or 'clear',
                drain_waiting and tostring(drain_epoch) or '-',
                drain_waiting and tostring(drain_cycle) or '-',
                TARGET_NAME, MAX_DISTANCE))
    end
end

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = tostring(command or 'status'):lower()
    local argument = tostring(args[1] or ''):lower()
    local p = player()
    if command == '__ackpt' or command == '__gate_armed' or command == 'bindpt'
        or command == 'unbindpt' or command == 'gsreload'
        or command == 'authorize' or command == 'retirept'
    then
        handle_authority_command(command, args, p)
        return
    end
    handle_control_command(command, argument, args, p)
end)

windower.register_event('load', function()
    chat('Loaded OFF in standard mode; PartyTactics binds first-hit mode when required.')
end)
