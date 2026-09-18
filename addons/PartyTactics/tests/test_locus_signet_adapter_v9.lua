local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = test_dir..'/../gearswap/adapters/'
    ..'locus-dire-bats-tomb-signet/1.8.1.lua'

local GENERATION = '1789437000-1001-1'
local SUCCESSOR = '1789437001-1001-2'
local PROFILE_ID = 'locus-dire-bats-tomb-signet'
local PROFILE_VERSION = '1.8.1'
local ENGINE_VERSION = '0.13.3'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
local SIGNATURE = '1a2b3c4d'
local now = 100

local function count_contains(values, text)
    local total = 0
    for _, value in ipairs(values) do
        if value:find(text, 1, true) then total = total + 1 end
    end
    return total
end

local function clear(values)
    for index = #values, 1, -1 do values[index] = nil end
end

local function world(name, job)
    now = 100
    local commands = {}
    local current = {
        id=1001, index=101, name=name or 'Smalls',
        main_job=job or 'RDM', sub_job='WHM',
        status='Idle', buffs={},
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.player = current
    env.PARTYTACTICS_LOCUS_SIGNET_TEST_MODE = true
    env.os = {clock=function() return now end}
    env.add_to_chat = function() end
    env.windower = {
        send_command=function(command) commands[#commands + 1] = command end,
        send_ipc_message=function() end,
        ffxi={
            get_player=function() return current end,
            get_info=function() return {logged_in=true, zone=190} end,
            get_party=function()
                return {p0={name=current.name, mob={id=current.id}}}
            end,
            get_mob_by_target=function(token)
                return token == 'me' and {
                    id=current.id, index=current.index, x=0, y=0,
                } or nil
            end,
        },
    }
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(adapter_path)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(adapter_path, 't', env)
    end
    assert(loader, load_error)
    local adapter = loader()
    assert(adapter.activate())

    local function action(semantic, arguments)
        return adapter.handle_action('locus-signet', semantic, arguments)
    end
    local function authorize(generation, revision, bit)
        return action('authorize', {
            generation or GENERATION, '0', '2', PROFILE_ID, PROFILE_VERSION,
            SIGNATURE, 'Dolomedes', ROSTER, tostring(revision or 4), bit or '1',
        })
    end
    local function helper_ack(helper, generation, nonce)
        local arguments = {
            generation or GENERATION, '0', '2', helper, PROFILE_ID,
            PROFILE_VERSION, ENGINE_VERSION, SIGNATURE,
            current.name, current.main_job,
        }
        if helper == 'sk' then arguments[#arguments + 1] = nonce end
        return action('companion-ready', arguments)
    end
    local function ack(generation, nonce)
        return helper_ack('sk', generation, nonce)
    end
    return {
        adapter=adapter, state=adapter._test_state, commands=commands,
        action=action, authorize=authorize, ack=ack,
        helper_ack=helper_ack,
        advance=function(seconds) now = now + seconds end,
    }
end

-- A missing LP or Jubilee ACK repairs only that helper; a healthy SignetKeeper
-- is not rearmed on every retry. The first Tackle bootstrap still orders LP
-- before SK, and neither helper can pull without SK's Signet census.
do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(GENERATION, 4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack(GENERATION, '1789437000-1000000'))
    clear(w.commands)
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'lp authorize '..GENERATION..' 0') == 1)
    assert(count_contains(w.commands, 'lp bindpt '..GENERATION..' 0') == 1)
    assert(count_contains(w.commands, 'sk authorize '..GENERATION..' 0') == 0)
    assert(count_contains(w.commands, 'sk armpt '..GENERATION..' 0') == 0)
    assert(w.helper_ack('lp', GENERATION))
    assert(w.adapter.status():find('helpers=sk:ack,lp:ack', 1, true))
end

do
    local w = world('Dolomedes', 'COR')
    assert(w.authorize(GENERATION, 4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack(GENERATION, '1789437000-1000000'))
    clear(w.commands)
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'jk authorize '..GENERATION..' 0') == 1)
    assert(count_contains(w.commands, 'jk armpt '..GENERATION..' 0') == 1)
    assert(count_contains(w.commands, 'sk authorize '..GENERATION..' 0') == 0)
    assert(count_contains(w.commands, 'sk armpt '..GENERATION..' 0') == 0)
    assert(w.helper_ack('jk', GENERATION))
    assert(w.adapter.status():find('helpers=sk:ack,lp:wait,jk:ack', 1, true))
    clear(w.commands)
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'jk armpt '..GENERATION..' 0') == 1,
        'current adapter did not reprove Jubilee authority after cached ACK')
    assert(count_contains(w.commands, 'sk armpt '..GENERATION..' 0') == 0,
        'Jubilee reproof unnecessarily rearmed SignetKeeper')
    clear(w.commands)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'jk armpt '..GENERATION..' 0') == 0,
        'Jubilee reproof was emitted more than once per retry interval')
end

local function establish(w, nonce)
    assert(w.authorize(GENERATION, 4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack(GENERATION, nonce or '1789437000-1000000'))
end

-- An exact authorized probe proves the controller even before the helper
-- ACK. The operator heartbeat must run so SignetKeeper cannot lose its lease.
-- The first keeper nonce remains a baseline, and the later ACK is diagnostic.
do
    local w = world()
    assert(w.adapter.version == PROFILE_VERSION and w.adapter.protocol == 2)
    assert(w.authorize(GENERATION, 4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands,
        'pt __controller_ready locus-signet '..GENERATION..' 0 2') == 1,
        'exact probe did not establish controller proof immediately')
    clear(w.commands)
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'sk authorize '..GENERATION..' 0') == 1,
        'missing helper ACK did not reassert exact pending authority')
    assert(count_contains(w.commands, 'sk armpt '..GENERATION..' 0') == 1,
        'missing helper ACK did not trigger exact bootstrap repair')
    clear(w.commands)
    assert(w.action('keeper-instance', {'1789437000-1000000'}))
    assert(w.state.keeper_recovery == nil)
    assert(count_contains(w.commands, 'sk gsreload') == 0,
        'first keeper nonce incorrectly started recovery')
    assert(w.ack(GENERATION, '1789437000-1000000'))
    assert(count_contains(w.commands,
        'pt __controller_ready locus-signet '..GENERATION..' 0 2') == 0,
        'diagnostic companion ACK duplicated controller proof')
    assert(w.adapter.status():find('helpers=sk:ack', 1, true),
        'status did not expose companion ACK')
    clear(w.commands)
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'sk armpt '..GENERATION..' 0') == 0,
        'completed helper ACK kept retrying bootstrap')
end

-- Malformed, missing, and lower process-clock tokens are inert. Ordering uses
-- the process clock first, so wall-clock correction cannot manufacture age.
do
    local w = world()
    establish(w, '1800000000-100')
    clear(w.commands)
    for _, token in ipairs({
        'bad', '01800000000-101', '1800000000-0101',
        '1800000000-101-extra', '9007199254740992-101',
    }) do
        assert(not w.action('keeper-instance', {token}))
    end
    assert(not w.action('keeper-instance', {}))
    assert(not w.action('keeper-instance', {'1900000000-99'}),
        'lower process clock won because its wall clock was newer')
    assert(w.state.keeper_recovery == nil)
    assert(w.state.keeper_instance_nonce.token == '1800000000-100')
    assert(count_contains(w.commands, 'sk gsreload') == 0)
    assert(w.action('keeper-instance', {'1800000000-100'}))
    assert(w.state.keeper_recovery == nil,
        'equal nonce was not idempotent')
end

-- A strictly newer process instance under the exact current authority applies
-- the complete local OFF baseline and starts one fixed 20-second recovery.
-- Additional newer instances advance only the high-water and retain the same
-- deadline/next scheduled attempt.
do
    local w = world()
    establish(w, '1800000000-100')
    clear(w.commands)
    assert(w.action('keeper-instance', {'1700000000-101'}),
        'newer process clock was rejected after wall-clock rollback')
    local recovery = assert(w.state.keeper_recovery)
    local expires, next_attempt = recovery.expires, recovery.next_attempt
    assert(expires == 120 and next_attempt == 103)
    assert(w.state.reload_handoff
        and w.state.reload_handoff.generation == GENERATION)
    assert(count_contains(w.commands, 'pc localstop') == 1)
    assert(count_contains(w.commands, 'aws2 off') == 1)
    assert(count_contains(w.commands, 'gs c unset AutoWSMode') == 1)
    local request = 'sk armpt '..GENERATION..' 0 Dolomedes '..ROSTER
        ..' '..PROFILE_ID..' '..PROFILE_VERSION..' '..ENGINE_VERSION
        ..' '..SIGNATURE..' 4 1; sk __ackpt '..GENERATION
        ..' 0; sk gsreload '..GENERATION..' 0'
    assert(count_contains(w.commands, request) == 1,
        'new keeper was not rebound before requesting leader-coalesced recovery')
    assert(count_contains(w.commands, 'pt __recover_controller') == 0,
        'client adapter bypassed the single-leader recovery coordinator')
    assert(w.adapter.pre_tick() == true,
        'automatic callback lane was not reserved during recovery')
    assert(w.adapter.filter_precast({english='Cure III'}, nil, {}) == false,
        'recovery introduced a manual action filter')

    assert(w.action('keeper-instance', {'1600000000-102'}))
    assert(w.state.keeper_instance_nonce.token == '1600000000-102')
    assert(recovery.expires == expires and recovery.next_attempt == next_attempt,
        'second raw reload extended or restarted the bounded recovery')
    assert(count_contains(w.commands, request) == 1,
        'coalesced newer nonce created an immediate second transaction')
    assert(not w.action('keeper-instance', {'1700000000-101'}),
        'delayed predecessor nonce replaced the retained high-water')
    assert(w.ack(GENERATION, '1600000000-102'))
    assert(count_contains(w.commands, request) == 1,
        'equal companion ACK retriggered recovery')

    w.advance(2.9)
    w.adapter.prerender()
    assert(count_contains(w.commands, request) == 1)
    w.advance(0.1)
    w.adapter.prerender()
    assert(count_contains(w.commands, request) == 2,
        'dropped recovery request was not retried at the three-second bound')
    assert(recovery.expires == expires,
        'retry extended the original recovery deadline')
end

-- Cycle ordering remains intact while raw-keeper recovery is pending. A late
-- valid resume cannot reopen lanes, and malformed/non-sequential cycles retain
-- their original rejection behavior.
do
    local w = world()
    establish(w, '1800000000-200')
    assert(w.action('suspend', {GENERATION, '0', '2', '1'}))
    assert(w.action('keeper-instance', {'1800000000-201'}))
    assert(not w.action('resume', {
        GENERATION, '0', '2', '4', '1', '1',
    }), 'maintenance resume pierced keeper recovery')
    assert(w.state.maintenance_cycle == 1
        and w.state.cycle_phase == 'suspended')
    assert(not w.action('suspend', {GENERATION, '0', '2', '3'}),
        'non-sequential maintenance cycle bypassed validation')
    assert(not w.action('suspend', {GENERATION, '0', '2', '0'}),
        'cycle zero bypassed validation')
end

-- The authorized successor clears only the pending recovery. It retains the
-- accepted nonce high-water, so the successor's equal SK proof is ordinary
-- readiness and a delayed predecessor remains inert.
do
    local w = world()
    establish(w, '1800000000-300')
    assert(w.action('keeper-instance', {'1800000000-301'}))
    local recovery_requests = count_contains(w.commands, 'sk gsreload')
    assert(w.authorize(SUCCESSOR, 4, '1'))
    assert(w.action('probe', {SUCCESSOR, '0', '2'}))
    assert(w.state.authority.generation == SUCCESSOR)
    assert(w.state.keeper_recovery == nil and w.state.reload_handoff == nil)
    assert(w.state.keeper_instance_nonce.token == '1800000000-301')
    assert(w.ack(SUCCESSOR, '1800000000-301'))
    assert(count_contains(w.commands, 'sk gsreload') == recovery_requests,
        'successor equal ACK created another recovery')
    assert(not w.action('keeper-instance', {'1800000000-300'}))
    assert(w.state.authority.generation == SUCCESSOR)
    assert(w.action('suspend', {SUCCESSOR, '0', '2', '1'}),
        'successor did not accept a fresh maintenance cycle one')
    assert(w.action('resume', {SUCCESSOR, '0', '2', '4', '1', '1'}),
        'successor could not complete its first normal renewal cycle')
    assert(w.state.maintenance_cycle == 1
        and w.state.cycle_phase == 'resumed')
end

-- An operator-OFF profile remains OFF throughout rebinding and successor
-- creation. Recovery transports the exact revision/bit tuple as data; it does
-- not infer ON merely because a fresh keeper appeared.
do
    local w = world()
    assert(w.authorize(GENERATION, 7, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack(GENERATION, '1800000000-350'))
    clear(w.commands)
    assert(w.action('keeper-instance', {'1800000000-351'}))
    local request = 'sk armpt '..GENERATION..' 0 Dolomedes '..ROSTER
        ..' '..PROFILE_ID..' '..PROFILE_VERSION..' '..ENGINE_VERSION
        ..' '..SIGNATURE..' 7 0; sk __ackpt '..GENERATION
        ..' 0; sk gsreload '..GENERATION..' 0'
    assert(count_contains(w.commands, request) == 1,
        'recovery did not preserve the exact operator-OFF tuple')
    assert(w.state.operator_armed == false)
    assert(w.authorize(SUCCESSOR, 7, '0'))
    assert(w.action('probe', {SUCCESSOR, '0', '2'}))
    assert(w.ack(SUCCESSOR, '1800000000-351'))
    assert(w.state.operator_armed == false,
        'successor changed operator OFF into ON')
end

-- Expiry is terminal and fail-closed. It retires the old authority, emits one
-- controller-lost edge, stops retrying, and never reopens automatic lanes.
do
    local w = world()
    establish(w, '1800000000-400')
    clear(w.commands)
    assert(w.action('keeper-instance', {'1800000000-401'}))
    w.advance(20)
    w.adapter.prerender()
    assert(w.state.authority == nil and w.state.active == false)
    assert(w.state.keeper_recovery == nil and w.state.reload_handoff == nil)
    assert(w.state.keeper_instance_nonce == nil,
        'terminal timeout retained a stale keeper-instance high-water')
    assert(count_contains(w.commands,
        'pt __controller_lost locus-signet '..GENERATION..' 0 2') == 1,
        'timeout did not publish exactly one controller-lost edge')
    assert(count_contains(w.commands, 'pc localstop') >= 2,
        'timeout failed to retain the terminal OFF baseline')
    local retries = count_contains(w.commands, 'sk gsreload')
    w.advance(4)
    w.adapter.prerender()
    assert(count_contains(w.commands, 'sk gsreload') == retries,
        'terminal timeout continued retrying recovery')
    assert(not w.action('keeper-instance', {'1800000000-402'}),
        'terminally fenced authority was revived by another keeper load')
end

print('PartyTactics Locus Signet raw-keeper recovery adapter v1.8 tests passed.')
