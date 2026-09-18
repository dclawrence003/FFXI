-- PartyTactics GearSwap adapter for the isolated Locus Signet profile.
--
-- This module owns no equipment set and exposes no arbitrary action surface.
-- It binds three companion add-ons to one PartyTactics generation, suppresses
-- automatic GearSwap callbacks only during the Signet staff transaction, and
-- gives Tackleberry's Flash opener one independently bounded automatic-action
-- reservation. Manual actions always pass through.

local M = {
    id='locus-dire-bats-tomb-signet',
    version='1.0.0',
    controller='locus-signet',
    protocol=1,
}

local PROFILE_ID = M.id
local PROFILE_VERSION = M.version
local ENGINE_VERSION = '0.13.1'
local ZONE = 190
local TARGET_NAME = 'Locus Dire Bat'
local LEADER = 'Dolomedes'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
local OPENER_TTL = 6
local RELOAD_HANDOFF_TTL = 20
local AUTHORIZATION_TTL = 12
local TERMINAL_REASSERT_DELAY = 2
local SK_PREFIX = 'SIGNETKEEPER1'

local EXPECTED = {
    Achoo={job='GEO'},
    Barneystinson={job='BRD'},
    Dolomedes={job='COR'},
    Kickpuncher={job='DNC'},
    Smalls={job='RDM'},
    Tackleberry={job='PLD'},
}

local HELPER = {
    BRD='pstartbrd', RDM='pstartrdm', GEO='pstartgeo',
    PLD='pstartpld', DNC='pstartdnc',
}

local state = {
    active=false,
    authority=nil,
    suspended=false,
    opener=nil,
    maintenance_cycle=nil,
    cycle_phase=nil,
    reload_handoff=nil,
    authorization=nil,
    companions_requested=false,
    terminal_reassert_at=nil,
    terminal_job=nil,
    retired_tuples={},
    retired_generations={},
    accepted=0,
    rejected=0,
    opener_timeouts=0,
    last='inactive',
}

if rawget(_G, 'PARTYTACTICS_LOCUS_SIGNET_TEST_MODE') == true then
    M._test_state = state
end

local function now()
    return os.clock()
end

local function chat(message, color)
    if type(add_to_chat) == 'function' then
        add_to_chat(color or 207, '[PartyTactics Locus Signet] '..message)
    end
end

local function issue(command)
    if type(windower) == 'table'
        and type(windower.send_command) == 'function'
    then
        windower.send_command(command)
        return true
    end
    return false
end

local function send_ipc(fields)
    if type(windower) == 'table'
        and type(windower.send_ipc_message) == 'function'
    then
        windower.send_ipc_message(table.concat(fields, '|'))
        return true
    end
    return false
end

local function valid_generation(value)
    if type(value) ~= 'string' or #value < 5 or #value > 64 then
        return false
    end
    local first, second, third = value:match('^(%d+)%-(%d+)%-(%d+)$')
    local function canonical(part)
        return part and (part == '0' or part:sub(1, 1) ~= '0')
    end
    return canonical(first) and canonical(second) and canonical(third)
end

local function valid_epoch(value)
    if type(value) ~= 'string' or #value < 1 or #value > 12
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    return number and number >= 0 and number == math.floor(number)
        and number or nil
end

local function valid_cycle(value)
    local cycle = valid_epoch(value)
    return cycle and cycle >= 1 and cycle <= 2147483647 and cycle or nil
end

local function valid_signature(value)
    return type(value) == 'string' and #value == 8
        and value:match('^[0-9a-f]+$') ~= nil
end

local function uint32(value)
    if type(value) ~= 'string' or #value < 1 or #value > 10
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    return number and number >= 1 and number <= 4294967295
        and number == math.floor(number) and number or nil
end

local function player()
    local live = type(windower) == 'table' and windower.ffxi
        and type(windower.ffxi.get_player) == 'function'
        and windower.ffxi.get_player() or nil
    if type(live) == 'table' then return live end
    return type(_G.player) == 'table' and _G.player or nil
end

local function in_tomb()
    local info = type(windower) == 'table' and windower.ffxi
        and type(windower.ffxi.get_info) == 'function'
        and windower.ffxi.get_info() or nil
    return type(info) == 'table' and info.logged_in ~= false
        and tonumber(info.zone) == ZONE
end

local function local_identity()
    local current = player()
    local name = current and current.name or nil
    local expected = name and EXPECTED[name] or nil
    if not expected or current.main_job ~= expected.job then
        return nil, nil, nil
    end
    return name, expected.job, current.sub_job
end

local function terminal_baseline(job)
    -- This profile can be re-applied best-effort after a zone event. Its
    -- rejection therefore needs a complete local OFF baseline instead of
    -- assuming a later compiler teardown will run.
    local commands = {
        'pc localstop',
        'aws2 off',
        'hb follow off',
        'hb db off',
        'hb as off',
        'hb as attack off',
        'hb off',
        'gs c unset AutoWSMode',
    }
    if job == 'COR' then
        commands[#commands + 1] = 'r2 off'
    end
    local helper = HELPER[job]
    if helper then
        commands[#commands + 1] = 'gs c '..helper..' off'
    end
    if job == 'RDM' or job == 'PLD' or job == 'DNC' or job == 'GEO' then
        commands[#commands + 1] = 'gs c set AutoBuffMode Off'
    end
    if job == 'PLD' then
        commands[#commands + 1] = 'gs c unset AutoTankMode'
        commands[#commands + 1] = 'gs c unset AutoTankFull'
    elseif job == 'DNC' then
        commands[#commands + 1] = 'gs c unset AutoPrestoMode'
        commands[#commands + 1] = 'gs c set AutoSambaMode Off'
        commands[#commands + 1] = 'gs c set DanceStance None'
    elseif job == 'GEO' then
        commands[#commands + 1] = 'gs c set CombatEntrustOnly'
    end
    return table.concat(commands, '; ')
end

local function cancel_terminal_reassert()
    state.terminal_reassert_at = nil
    state.terminal_job = nil
end

local function terminal_off(job, reason)
    local baseline = terminal_baseline(job)
    state.authorization = nil
    -- Offense compilation intentionally waits one second after changing a
    -- weapon mode before enabling AutoWS2, and an armed commit can queue PC ON
    -- immediately after its controller probe. Apply now, then let this exact
    -- adapter instance reassert once after those older queued commands drain.
    -- The retry is adapter-owned rather than embedded in a raw Windower wait:
    -- profile replacement/deactivation cancels it, so it cannot turn a later
    -- unrelated profile back off.
    issue(baseline)
    state.terminal_job = job
    state.terminal_reassert_at = now() + TERMINAL_REASSERT_DELAY
    state.last = reason or 'terminal local automation baseline applied'
end

local function expire_terminal_reassert()
    if not state.terminal_reassert_at
        or now() < state.terminal_reassert_at
    then
        return false
    end
    local job = state.terminal_job
    cancel_terminal_reassert()
    issue(terminal_baseline(job))
    state.last = 'terminal local automation baseline reasserted'
    return true
end

local function same_authority(generation, epoch_value, protocol_value)
    local authority = state.authority
    return authority ~= nil
        and generation == authority.generation
        and valid_epoch(epoch_value) == authority.epoch
        and tonumber(protocol_value) == M.protocol
end

local function authority_key(generation, epoch)
    return tostring(generation)..'/'..tostring(epoch)
end

local function retire_authority(authority)
    if not authority then return end
    state.retired_tuples[authority_key(
        authority.generation, authority.epoch)] = true
end

local function authority_retired(generation, epoch)
    return state.retired_generations[generation] == true
        or state.retired_tuples[authority_key(generation, epoch)] == true
end

local function valid_reload_handoff(current, generation, epoch)
    local handoff = state.reload_handoff
    return type(handoff) == 'table' and now() <= handoff.expires
        and epoch == 0 and generation ~= handoff.generation
        and (not current or current.generation == handoff.generation
            and current.epoch == handoff.epoch)
end

local function announce_lost(authority, reason)
    if not authority then return end
    issue(('pt __controller_lost %s %s %d %d'):format(
        M.controller, authority.generation, authority.epoch, M.protocol))
    state.last = reason or 'controller authority released'
end

local function companion_detach(authority, keep_automatic_off)
    if not authority then return end
    -- Raw logout/zone callbacks may run after Windower has already removed
    -- the live player object. The identity captured by the validated probe is
    -- the teardown authority; never guess from a later client snapshot.
    local name = authority.name
    if name == 'Dolomedes' then
        issue(('jk detach %s %d'):format(
            authority.generation, authority.epoch))
    elseif name == 'Tackleberry' then
        issue(('lp unbindpt %s %d%s'):format(
            authority.generation, authority.epoch,
            keep_automatic_off and ' keepoff' or ''))
    end
    -- Detach the local slot/puller owner first. In particular, Tackle's
    -- keepoff release must be queued before a distributed SK detach can retire
    -- the authority used to validate it.
    issue(('sk detach %s %d'):format(
        authority.generation, authority.epoch))
end

local function release_opener(reason, restore_automatic)
    if not state.opener then return false end
    state.opener = nil
    if restore_automatic ~= false and not state.suspended
        and not state.reload_handoff
    then
        issue('aws2 on')
    end
    state.last = reason or 'PLD opener released'
    return true
end

local function clear_local(reason, notify_lost, restore_automatic)
    local authority = state.authority
    retire_authority(authority)
    companion_detach(authority, not restore_automatic)
    if restore_automatic and (state.opener or state.suspended) then
        -- Only a genuine adapter exception fails open. Normal profile stop,
        -- replacement, zone/logout, and GearSwap teardown must leave the
        -- compiler's later OFF commands authoritative.
        issue('aws2 on')
    end
    if restore_automatic and state.suspended then
        local job = authority and authority.job or nil
        if job == 'COR' then issue('r2 on') end
        if job == 'RDM' then
            issue('hb deactivateindoors off; hb disable cure; hb enable na; '
                ..'hb disable buff; hb db off; hb as off; '
                ..'hb as attack off; hb on')
        end
    end
    state.opener = nil
    state.suspended = false
    state.maintenance_cycle = nil
    state.cycle_phase = nil
    state.reload_handoff = nil
    state.companions_requested = false
    state.authority = nil
    if notify_lost then announce_lost(authority, reason) end
    state.last = reason or 'local state cleared'
end

local function party_claimed(target)
    local claim = tonumber(target and target.claim_id) or 0
    if claim == 0 then return true end
    local current = player()
    if current and tonumber(current.id) == claim then return true end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        local id = type(member) == 'table' and tonumber(
            member.mob and member.mob.id or member.mob_id or member.id) or nil
        if id == claim then return true end
    end
    return false
end

local function target_distance(target)
    local squared = tonumber(target and target.distance)
    if squared and squared >= 0 then return math.sqrt(squared) end
    local me = type(windower.ffxi.get_mob_by_target) == 'function'
        and windower.ffxi.get_mob_by_target('me') or nil
    if me and target and me.x and me.y and target.x and target.y then
        local x, y = target.x - me.x, target.y - me.y
        return math.sqrt(x * x + y * y)
    end
    return nil
end

local function exact_bat(id)
    local info = windower.ffxi.get_info()
    if not info or info.logged_in == false or tonumber(info.zone) ~= ZONE then
        return nil
    end
    local target = windower.ffxi.get_mob_by_id(id)
    local distance = target_distance(target)
    if type(target) ~= 'table' or tonumber(target.id) ~= id
        or target.name ~= TARGET_NAME or tonumber(target.spawn_type) ~= 16
        or target.valid_target ~= true or (tonumber(target.hpp) or 0) <= 0
        or not tonumber(target.index) or not distance or distance > 20
        or not party_claimed(target)
    then
        return nil
    end
    return target
end

local function bootstrap_companions(authority, name)
    -- Helpers were loaded inert during adapter activation. Rechecking the
    -- exact zone here makes the authority handoff atomic with respect to a
    -- zoning event; no delayed `wait` can arm ownership after Tomb departure.
    if not in_tomb() then return false end
    local keeper = ('sk armpt %s %d %s %s %s %s %s %s'):format(
            authority.generation, authority.epoch, LEADER, ROSTER,
            PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
            authority.signature)
    if name == 'Tackleberry' then
        -- Bind the puller before SignetKeeper observes/replays the initial
        -- PartyTactics operator bit. One Windower command queue makes this
        -- ordering deterministic even when both add-ons were initially off.
        issue(('lp bindpt %s %d %s %s %s %s %s %s; %s')
            :format(authority.generation, authority.epoch,
                PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
                authority.signature, LEADER, ROSTER, keeper))
    else
        issue(keeper)
    end
    if name == 'Dolomedes' then
        issue(('jk armpt %s %d %s %s %s %s %s %s')
            :format(authority.generation, authority.epoch,
                PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
                authority.signature, LEADER, ROSTER))
    end
    return true
end

local function load_companions(name)
    if state.companions_requested then return end
    issue('lua load SignetKeeper')
    if name == 'Dolomedes' then
        issue('lua load JubileeKeeper')
    elseif name == 'Tackleberry' then
        issue('lua load LocusPuller')
    end
    state.companions_requested = true
end

local function authorize(arguments)
    local generation = arguments[1]
    local epoch = valid_epoch(arguments[2])
    local protocol = tonumber(arguments[3])
    local signature = arguments[6]
    local name = local_identity()
    if #arguments ~= 8 or not name or not in_tomb()
        or not valid_generation(generation) or epoch == nil
        or protocol ~= M.protocol
        or arguments[4] ~= PROFILE_ID
        or arguments[5] ~= PROFILE_VERSION
        or not valid_signature(signature)
        or arguments[7] ~= LEADER or arguments[8] ~= ROSTER
        or authority_retired(generation, epoch)
    then
        return false, 'exact committed profile authorization required'
    end
    local current = state.authority
    if current and generation == current.generation
        and epoch < current.epoch
    then
        return false, 'authorization epoch predates current authority'
    end
    if current and generation ~= current.generation
        and not valid_reload_handoff(current, generation, epoch)
    then
        return false, 'different generation lacks bounded reload handoff'
    end
    state.authorization = {
        generation=generation, epoch=epoch, protocol=protocol,
        signature=signature, expires=now() + AUTHORIZATION_TTL,
    }
    load_companions(name)
    issue(('sk authorize %s %d %s %s %s %s %s %s'):format(
        generation, epoch, LEADER, ROSTER, PROFILE_ID, PROFILE_VERSION,
        ENGINE_VERSION, signature))
    if name == 'Dolomedes' then
        issue(('jk authorize %s %d %s %s %s %s %s %s'):format(
            generation, epoch, PROFILE_ID, PROFILE_VERSION,
            ENGINE_VERSION, signature, LEADER, ROSTER))
    elseif name == 'Tackleberry' then
        issue(('lp authorize %s %d %s %s %s %s %s %s'):format(
            generation, epoch, PROFILE_ID, PROFILE_VERSION,
            ENGINE_VERSION, signature, LEADER, ROSTER))
    end
    state.last = 'exact committed controller lifecycle authorized'
    return true, 'controller lifecycle authorized'
end

local function retire_generation(arguments)
    local generation = arguments[1]
    local source = arguments[6]
    if #arguments ~= 6 or not valid_generation(generation)
        or arguments[2] ~= ENGINE_VERSION
        or arguments[3] ~= PROFILE_ID
        or arguments[4] ~= PROFILE_VERSION
        or not valid_signature(arguments[5])
        or EXPECTED[source] == nil
    then
        return false, 'retire requires exact stopped profile lifecycle'
    end

    -- This terminal fence deliberately does not depend on current adapter
    -- authority. A validated PartyTactics stop can overtake an already queued
    -- authorize/probe during profile application; remembering the generation
    -- here makes both delayed messages inert and gives each local companion
    -- the same no-loopback tombstone before any armpt/bindpt can arrive.
    state.retired_generations[generation] = true
    if state.authorization
        and state.authorization.generation == generation
    then
        state.authorization = nil
    end

    local authority = state.authority
    local current = player()
    local name = authority and authority.name
        or current and current.name or nil
    issue(('sk stoppt %s %s %s %s %s %s'):format(
        generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
        arguments[5], source))
    if name == 'Dolomedes' then
        issue(('jk stoppt %s %s %s %s %s %s'):format(
            generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
            arguments[5], source))
    elseif name == 'Tackleberry' then
        issue(('lp retirept %s %s %s %s %s %s'):format(
            generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
            arguments[5], source))
    end
    state.last = 'stopped controller generation retired locally'
    return true, 'stopped controller generation retired locally'
end

local function probe_authorized(generation, epoch, protocol)
    local authorization = state.authorization
    return type(authorization) == 'table'
        and now() <= authorization.expires
        and generation == authorization.generation
        and epoch == authorization.epoch
        and protocol == authorization.protocol
end

local function probe(arguments)
    local generation = arguments[1]
    local epoch_value = valid_epoch(arguments[2])
    local protocol_value = tonumber(arguments[3])
    local name, job, sub_job = local_identity()
    if #arguments ~= 3 then
        return false, 'probe requires exact generation, epoch, and protocol'
    end
    if not name or not in_tomb() then
        local authority = state.authority
        local current = player()
        local terminal_job = authority and authority.job
            or current and current.main_job
        if authority then
            retire_authority(authority)
            clear_local('controller probe left owned zone/identity', true)
        end
        terminal_off(terminal_job,
            'controller probe refused outside owned zone/identity')
        state.active = false
        return false, 'Tomb zone and exact name/main job required'
    end
    if not valid_generation(generation) or epoch_value == nil
        or protocol_value ~= M.protocol
    then
        return false, 'generation, epoch, and protocol required'
    end
    if authority_retired(generation, epoch_value) then
        return false, 'retired controller authority cannot be reclaimed'
    end
    local current = state.authority
    local idempotent = current and current.generation == generation
        and current.epoch == epoch_value
    if not idempotent
        and not probe_authorized(generation, epoch_value, protocol_value)
    then
        return false, 'probe lacks exact committed lifecycle authorization'
    end
    if current then
        local identity_matches = current.profile_id == PROFILE_ID
            and current.profile_version == PROFILE_VERSION
            and current.name == name and current.job == job
        if not identity_matches then
            return false, 'probe identity differs from current pinned authority'
        end
        if generation == current.generation
            and epoch_value < current.epoch
        then
            return false, 'stale controller probe cannot replace current authority'
        end
        if generation ~= current.generation
            and not valid_reload_handoff(current, generation, epoch_value)
        then
            return false, 'different generation requires GearSwap reload handoff'
        end
    elseif state.reload_handoff
        and not valid_reload_handoff(nil, generation, epoch_value)
    then
        return false, 'reload handoff requires a fresh generation at epoch zero'
    end
    if current and current.generation == generation
        and current.epoch == epoch_value
    then
        -- The stable host deliberately retains an inert adapter after an
        -- outside-zone activation. A later same-id activation short-circuits
        -- in the host, so the first accepted probe must also ensure the local
        -- companion add-ons exist before handing them authority.
        load_companions(name)
        if not bootstrap_companions(state.authority, name) then
            clear_local('companion rebind left the owned zone', true)
            terminal_off(job, 'companion rebind refused outside Tomb')
            state.active = false
            return false, 'companion rebind refused outside Tomb'
        end
        state.active = true
        cancel_terminal_reassert()
        issue(('pt __controller_ready %s %s %d %d'):format(
            M.controller, generation, epoch_value, M.protocol))
        state.last = 'same controller authority reasserted'
        return true, 'controller authority reasserted'
    end
    if state.authority then
        if state.authority.generation ~= generation then
            retire_authority(state.authority)
        end
        clear_local('superseded by a fresh controller probe', false)
    end
    local authorization = state.authorization
    state.authority = {
        generation=generation,
        epoch=epoch_value,
        established_at=now(),
        profile_id=PROFILE_ID,
        profile_version=PROFILE_VERSION,
        name=name,
        job=job,
        sub_job=sub_job,
        signature=authorization.signature,
    }
    state.suspended = false
    state.opener = nil
    state.maintenance_cycle = nil
    state.cycle_phase = nil
    state.reload_handoff = nil
    load_companions(name)
    if not bootstrap_companions(state.authority, name) then
        state.authority = nil
        terminal_off(job, 'companion bootstrap refused outside Tomb')
        state.active = false
        return false, state.last
    end
    state.active = true
    state.authorization = nil
    cancel_terminal_reassert()
    issue(('pt __controller_ready %s %s %d %d'):format(
        M.controller, generation, epoch_value, M.protocol))
    state.last = 'controller ready; companion lifecycle armed'
    return true, 'controller ready'
end

local function suspend(arguments)
    local cycle = valid_cycle(arguments[4])
    if #arguments ~= 4
        or not same_authority(arguments[1], arguments[2], arguments[3])
        or not cycle or not in_tomb()
    then
        return false, 'suspend requires current authority and positive cycle'
    end
    if not state.maintenance_cycle and cycle ~= 1
        or state.maintenance_cycle and (
        cycle > state.maintenance_cycle + 1
        or cycle < state.maintenance_cycle
        or cycle == state.maintenance_cycle
            and state.cycle_phase == 'resumed') then
        return false, 'stale maintenance-cycle suspend'
    end
    local name, job = local_identity()
    if not name then return false, 'local profile identity changed' end
    state.maintenance_cycle = cycle
    state.cycle_phase = 'suspended'
    state.suspended = true
    release_opener('Signet suspension replaced PLD opener', false)
    local command = 'pc off; aws2 off; hb follow off; hb db off; '
        ..'hb as off; hb as attack off; hb off'
    if job == 'COR' then command = command..'; r2 off' end
    issue(command)
    send_ipc({SK_PREFIX, 'adapter', state.authority.generation, name,
        tostring(state.authority.epoch), 'suspended', tostring(cycle)})
    -- Windower does not guarantee IPC delivery back to the sender. Feed the
    -- same exact-authority proof to the local keeper as well as its peers.
    issue(('sk __adapter %s %s %d suspended %d'):format(
        state.authority.generation, name, state.authority.epoch, cycle))
    state.last = 'automatic lanes suspended for Signet staff'
    return true, 'automatic lanes suspended; manual actions pass through'
end

local function resume(arguments)
    local cycle = valid_cycle(arguments[5])
    if #arguments ~= 5
        or not same_authority(arguments[1], arguments[2], arguments[3])
        or arguments[4] ~= '0' and arguments[4] ~= '1'
        or not cycle or cycle ~= state.maintenance_cycle or not in_tomb()
    then
        return false, 'resume requires current authority, operator bit, and active cycle'
    end
    if state.cycle_phase == 'resumed' then
        return true, 'maintenance cycle already resumed'
    end
    if state.cycle_phase ~= 'suspended' then
        return false, 'maintenance cycle was not suspended'
    end
    local name, job = local_identity()
    if not name then return false, 'local profile identity changed' end

    state.suspended = false
    state.cycle_phase = 'resumed'
    issue('aws2 on')
    if job == 'COR' then issue('r2 on') end
    if job == 'RDM' then
        issue('hb deactivateindoors off; hb disable cure; hb enable na; '
            ..'hb disable buff; hb db off; hb as off; '
            ..'hb as attack off; hb on')
    end
    -- SignetKeeper accepts this bit only from a fresh exact PartyTactics
    -- generation/profile/epoch state and tears its binding down when that
    -- state goes stale. Tackle is the sole resume sender, avoiding both a
    -- leader IPC-loopback dependency and six competing arm commands.
    if name == 'Tackleberry' and arguments[4] == '1' then
        issue('pc on')
    end
    send_ipc({SK_PREFIX, 'adapter', state.authority.generation, name,
        tostring(state.authority.epoch), 'resumed', tostring(cycle)})
    issue(('sk __adapter %s %s %d resumed %d'):format(
        state.authority.generation, name, state.authority.epoch, cycle))
    state.last = 'automatic lanes resumed from current profile policy'
    return true, 'automatic lanes resumed from current operator state'
end

local function opener_arm(arguments)
    local id = uint32(arguments[1])
    if #arguments ~= 4 or not id or not same_authority(
        arguments[2], arguments[3], arguments[4])
    then
        return false, 'opener-arm requires exact target and current authority'
    end
    local name, job = local_identity()
    if name ~= 'Tackleberry' or job ~= 'PLD' or state.suspended then
        return false, 'only active unsuspended Tackleberry PLD owns the opener'
    end
    local target = exact_bat(id)
    if not target then
        return false, 'exact live party-eligible Locus Dire Bat within 20 yalms required'
    end
    if state.opener and state.opener.id ~= id then
        release_opener('new exact opener replaced the prior reservation')
    end
    issue('aws2 off')
    state.opener = {
        id=id,
        index=tonumber(target.index),
        expires=now() + OPENER_TTL,
    }
    issue(('lp __gate_armed %.0f %s %d'):format(
        id, state.authority.generation, state.authority.epoch))
    state.last = 'bounded PLD opener armed for '..tostring(id)
    return true, 'bounded PLD opener armed'
end

local function opener_release(arguments)
    local id = uint32(arguments[1])
    local keepoff = arguments[5] == 'keepoff'
    if not id or not same_authority(
        arguments[2], arguments[3], arguments[4])
        or arguments[5] ~= nil and not keepoff
        or #arguments > 5
    then
        return false, 'opener-release requires exact target and current authority'
    end
    if state.opener and state.opener.id ~= id then
        return false, 'release target differs from active opener'
    end
    -- `keepoff` belongs only to terminal LocusPuller cleanup. It clears the
    -- reservation without racing the compiler's final AutoWS2 OFF. A later
    -- idempotent release after the adapter's own timeout also stays silent:
    -- that timeout already restored the lane exactly once.
    release_opener('PLD opener released', not keepoff)
    return true, 'PLD opener released'
end

local function expire_temporary_state()
    if state.opener and now() >= state.opener.expires then
        state.opener_timeouts = state.opener_timeouts + 1
        release_opener('PLD opener timed out fail-open')
        chat('Flash opener exceeded six seconds; AutoWS2 and PLD automation were released.', 123)
    end
end

function M.activate()
    local name = local_identity()
    if not name or not in_tomb() then
        local authority = state.authority
        local current = player()
        local job = authority and authority.job
            or current and current.main_job
        if authority then
            retire_authority(authority)
            clear_local('activation left owned zone/identity', true)
        end
        terminal_off(job,
            'activation refused outside Tomb or wrong main job')
        state.active = false
        -- Stay installed as an inert adapter so its prerender callback owns
        -- the one delayed terminal reassertion. A profile replacement invokes
        -- deactivate and cancels that retry before the new profile can run.
        return true, state.last
    end
    state.active = true
    load_companions(name)
    state.last = 'active and awaiting capability probe'
    return true
end

function M.deactivate(reason)
    cancel_terminal_reassert()
    state.authorization = nil
    if (reason == 'file-unload' or reason == 'unload')
        and state.reload_handoff
    then
        -- file_unload already transferred this exact authority to the
        -- reload-safe companions. The stable host must forget this adapter
        -- instance without converting a transient GearSwap outage into a
        -- profile teardown.
        local handoff = state.reload_handoff
        retire_authority(state.authority)
        state.active = false
        state.authority = nil
        state.suspended = false
        state.opener = nil
        state.maintenance_cycle = nil
        state.cycle_phase = nil
        state.reload_handoff = handoff
        state.last = 'GearSwap reload handoff preserved companion ownership'
        return true
    end
    if state.authority then
        retire_authority(state.authority)
        local fail_open = type(reason) == 'string'
            and reason:match('^error:') ~= nil
        clear_local(reason or 'adapter deactivated', true, fail_open)
    end
    state.companions_requested = false
    state.active = false
    state.last = reason or 'adapter deactivated'
    return true
end

function M.handle_action(controller, semantic, arguments)
    if controller ~= M.controller or type(semantic) ~= 'string'
        or type(arguments) ~= 'table'
    then
        state.rejected = state.rejected + 1
        return false, 'unsupported controller request'
    end
    semantic = semantic:lower()
    local accepted, reason
    if semantic == 'probe' then
        accepted, reason = probe(arguments)
    elseif semantic == 'authorize' then
        accepted, reason = authorize(arguments)
    elseif semantic == 'retire' then
        accepted, reason = retire_generation(arguments)
    elseif not state.active or not state.authority then
        accepted, reason = false, 'adapter has no current profile authority'
    elseif semantic == 'suspend' then
        accepted, reason = suspend(arguments)
    elseif semantic == 'resume' then
        accepted, reason = resume(arguments)
    elseif semantic == 'opener-arm' then
        accepted, reason = opener_arm(arguments)
    elseif semantic == 'opener-release' then
        accepted, reason = opener_release(arguments)
    else
        accepted, reason = false, 'unsupported semantic'
    end
    if accepted then
        state.accepted = state.accepted + 1
    else
        state.rejected = state.rejected + 1
    end
    return accepted, reason
end

local function automatic_callback_reserved()
    expire_temporary_state()
    return state.active and (state.suspended or state.opener ~= nil)
end

function M.pre_tick(...)
    return automatic_callback_reserved()
end

function M.user_job_tick(...)
    return automatic_callback_reserved()
end

function M.user_job_self_command(command_args, event_args)
    if not automatic_callback_reserved()
        or type(command_args) ~= 'table' or #command_args ~= 2
        or type(command_args[1]) ~= 'string'
        or type(command_args[2]) ~= 'string'
    then
        return false
    end
    local current = player()
    local helper = current and HELPER[current.main_job] or nil
    local command = command_args[1]:lower()
    local operation = command_args[2]:lower()
    if not helper or command ~= helper then return false end
    if operation == 'tick' then return true end
    -- A delayed frozen PLD subjob-enmity request is automatic work from the
    -- same helper lane. Consume only that exact token; typed /ma, /ja, /ws,
    -- and every other self-command remain untouched.
    return current.main_job == 'PLD' and operation == 'subjobenmity'
end

function M.prerender(...)
    expire_temporary_state()
    expire_terminal_reassert()
    return false
end

-- No maintenance state is permission to cancel an operator action.
function M.filter_pretarget(spell, spell_map, event_args)
    return false
end

function M.filter_precast(spell, spell_map, event_args)
    return false
end

function M.status()
    local authority = state.authority
    return ('manual-pass-through authority=%s suspended=%s cycle=%s/%s opener=%s accepted=%d rejected=%d timeouts=%d last=%s')
        :format(authority and (authority.generation..'/'..authority.epoch)
                or 'none',
            state.suspended and 'yes' or 'no',
            tostring(state.maintenance_cycle or 'none'),
            tostring(state.cycle_phase or 'none'),
            state.opener and tostring(state.opener.id) or 'none',
            state.accepted, state.rejected, state.opener_timeouts,
            state.last)
end

function M.zone_change(...)
    local authority = state.authority
    local current = player()
    local job = authority and authority.job or current and current.main_job
    if state.authority then
        retire_authority(state.authority)
        clear_local('zone changed', true)
    end
    terminal_off(job, 'zone changed; local automation is terminally off')
    state.active = false
    return true
end

function M.file_unload(...)
    local authority = state.authority
    if not authority or not in_tomb() then
        return M.deactivate('GearSwap job file unloaded')
    end

    -- A GearSwap reload clears disabled-slot and callback state before the
    -- new job file exists. Freeze automatic lanes during that gap, but leave
    -- the standalone keepers bound so they can raw-reassert owned equipment
    -- and coalesce one exact PartyTactics reapply after GearSwap returns.
    local command = 'pc off; aws2 off; hb follow off; hb db off; '
        ..'hb as off; hb as attack off; hb off'
    if authority.job == 'COR' then command = command..'; r2 off' end
    issue(command)
    if authority.name == 'Dolomedes' then
        issue(('jk gsreload %s %d'):format(
            authority.generation, authority.epoch))
    elseif authority.name == 'Tackleberry' then
        issue(('lp gsreload %s %d'):format(
            authority.generation, authority.epoch))
    end
    issue(('sk gsreload %s %d'):format(
        authority.generation, authority.epoch))
    announce_lost(authority, 'GearSwap reload handoff')
    state.opener = nil
    state.reload_handoff = {
        generation=authority.generation,
        epoch=authority.epoch,
        expires=now() + RELOAD_HANDOFF_TTL,
    }
    state.last = 'GearSwap reload pending; companion ownership preserved'
    return true
end

function M.logout(...)
    local authority = state.authority
    local current = player()
    local job = authority and authority.job or current and current.main_job
    if authority then
        retire_authority(authority)
        clear_local('logout', true)
    end
    terminal_off(job, 'logout; local automation is terminally off')
    if authority then
        -- The stable host immediately deactivates this adapter after returning
        -- from the raw logout callback, so its prerender timer cannot own the
        -- delayed durability pass. Route that one pass through PartyTactics;
        -- the core accepts it only while this exact generation/epoch and its
        -- pinned controller/protocol are still current. A switch or reapply
        -- therefore cancels it without leaving a raw delayed OFF command.
        issue(('wait 2; pt __controller_terminal %s %s %d %d'):format(
            M.controller, authority.generation, authority.epoch, M.protocol))
    end
    state.active = false
    return true
end

function M.unload(...)
    -- Depending on GearSwap/Windower teardown ordering, a reload can surface
    -- through either callback. Both enter the same bounded companion handoff;
    -- zone/logout callbacks remain terminal and never use this path.
    return M.file_unload(...)
end

return M
