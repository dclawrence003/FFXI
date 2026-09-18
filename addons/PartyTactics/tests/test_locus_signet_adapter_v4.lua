local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = test_dir..'/../gearswap/adapters/'
    ..'locus-dire-bats-tomb-signet/1.4.0.lua'

local GENERATION = '1789437000-1001-1'
local PROFILE_ID = 'locus-dire-bats-tomb-signet'
local PROFILE_VERSION = '1.4.0'
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

local function world(name, job)
    local commands = {}
    local tank_mode = {value=true, unset_count=0}
    function tank_mode:unset()
        self.value = false
        self.unset_count = self.unset_count + 1
    end
    local current = {
        id=1001, index=101, name=name, main_job=job,
        sub_job=job == 'PLD' and 'WAR' or 'WHM', status='Idle', buffs={},
    }
    local target = {
        id=9001, index=901, name='Locus Dire Bat', spawn_type=16,
        valid_target=nil, hpp=100, claim_id=current.id,
        -- Deliberately contradictory target fields. Version 1.4 leaves the
        -- time-sensitive target check with LocusPuller and only owns the
        -- automatic-callback reservation.
        x=5.2, y=0, distance=900,
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.player = current
    env.state = {AutoTankMode=tank_mode}
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
                return {p0={name=name, mob={id=current.id}}}
            end,
            get_mob_by_id=function(id)
                return tonumber(id) == target.id and target or nil
            end,
            get_mob_by_target=function(token)
                if token == 'me' then
                    return {id=current.id, index=current.index, x=0, y=0}
                end
                return nil
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
    local function authorize(revision, bit)
        return action('authorize', {
            GENERATION, '0', '2', PROFILE_ID, PROFILE_VERSION,
            SIGNATURE, 'Dolomedes', ROSTER, tostring(revision), bit,
        })
    end
    local function ack(helper, values)
        values = values or {}
        return action('companion-ready', {
            values.generation or GENERATION,
            values.epoch or '0', values.protocol or '2', helper,
            values.profile_id or PROFILE_ID,
            values.profile_version or PROFILE_VERSION,
            values.engine or ENGINE_VERSION,
            values.signature or SIGNATURE,
            values.name or name, values.job or job,
        })
    end
    return {
        adapter=adapter, state=adapter._test_state, commands=commands,
        action=action, authorize=authorize, ack=ack, target=target,
        tank_mode=tank_mode,
    }
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.adapter.version == PROFILE_VERSION and w.adapter.protocol == 2)
    assert(w.tank_mode.value == false and w.tank_mode.unset_count == 1,
        'activation did not reserve Flash by silently disabling native AutoTank')
    assert(count_contains(w.commands, 'gs c unset AutoTankMode') == 0,
        'adapter used a noisy command despite a live GearSwap mode object')
    w.tank_mode.value = true
    w.adapter.pre_tick()
    assert(w.tank_mode.value == false and w.tank_mode.unset_count == 2,
        'pre-tick did not repair a later native AutoTank re-enable')
    w.adapter.pre_tick()
    assert(w.tank_mode.unset_count == 2,
        'native AutoTank repair repeated while the mode was already off')
    assert(w.authorize(4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, 'pt __controller_ready') == 0,
        'adapter reported ready before either Tackle helper proved binding')
    local bootstrap = 'lp bindpt '..GENERATION..' 0 '..PROFILE_ID..' '
        ..PROFILE_VERSION..' '..ENGINE_VERSION..' '..SIGNATURE..' Dolomedes '
        ..ROSTER..' 4 1; lp __ackpt '..GENERATION..' 0; sk armpt '
        ..GENERATION..' 0 Dolomedes '..ROSTER..' '..PROFILE_ID..' '
        ..PROFILE_VERSION..' '..ENGINE_VERSION..' '..SIGNATURE
        ..' 4 1; sk __ackpt '..GENERATION..' 0'
    assert(count_contains(w.commands, bootstrap) == 1,
        'Tackle bootstrap did not bind then query LP and SK exactly')
    assert(w.ack('sk'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 0,
        'SK-only ACK incorrectly satisfied Tackle readiness')
    assert(not w.ack('lp', {job='RDM'}))
    assert(not w.action('companion-ready', {
        GENERATION, '0', '2', 'lp', PROFILE_ID, PROFILE_VERSION,
        ENGINE_VERSION, SIGNATURE, 'Tackleberry', 'PLD', 'surplus',
    }))
    assert(w.ack('lp'))
    assert(count_contains(w.commands, 'pt __controller_ready locus-signet '
        ..GENERATION..' 0 2') == 1)
    assert(w.ack('lp'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 1,
        'duplicate companion ACK announced controller readiness twice')

    assert(w.action('operator', {GENERATION, '0', '2', '5', '1'}))
    assert(w.action('opener-arm', {'9001', GENERATION, '0', '2'}),
        'adapter rejected its bound LocusPuller opener reservation')
    assert(count_contains(w.commands,
        'lp __gate_armed 9001 '..GENERATION..' 0') == 1)
    local opener = w.state.opener
    local opener_expiry = opener.expires
    assert(w.action('opener-arm', {'9001', GENERATION, '0', '2'}))
    assert(w.state.opener == opener and w.state.opener.expires == opener_expiry,
        'duplicate opener request restarted its independent outer bound')
    assert(count_contains(w.commands, 'aws2 off') == 1,
        'duplicate opener request replayed noisy AutoWS2 suppression')
    assert(count_contains(w.commands,
        'lp __gate_armed 9001 '..GENERATION..' 0') == 2,
        'duplicate opener request did not repair a missing helper ACK')
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.state.opener == opener,
        'same-authority probe reset the in-flight opener')
    assert(count_contains(w.commands, 'pt __controller_ready') == 2,
        'same-authority probe did not repair a dropped ready callback')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(1, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack('sk') and w.ack('lp'))
    assert(w.action('operator', {GENERATION, '0', '2', '2', '0'}))
    local aws2_off_before = count_contains(w.commands, 'aws2 off')
    local gate_ack_before = count_contains(w.commands, 'lp __gate_armed')
    assert(not w.action('opener-arm', {'9001', GENERATION, '0', '2'}),
        'delayed opener reservation was accepted after operator OFF')
    assert(w.state.opener == nil,
        'delayed opener reservation survived operator OFF')
    assert(count_contains(w.commands, 'aws2 off') == aws2_off_before,
        'rejected post-OFF opener suppressed AutoWS2')
    assert(count_contains(w.commands, 'lp __gate_armed') == gate_ack_before,
        'rejected post-OFF opener acknowledged the stale helper request')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(1, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.authorize(2, '0'))
    assert(w.state.authority.operator_revision == 2
        and w.state.authority.operator_armed == false,
        'pre-ready Alt-P tuple did not merge into current authority')
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, ROSTER..' 2 0; lp __ackpt') == 1,
        'retry rebound LP with a stale pre-Alt-P operator tuple')
    assert(count_contains(w.commands, SIGNATURE..' 2 0; sk __ackpt') == 1,
        'retry rebound SK with a stale pre-Alt-P operator tuple')
    assert(count_contains(w.commands, 'pc reconcile ') == 0,
        'authorization data made PartyCombat effective before readiness')
    assert(w.ack('sk') and w.ack('lp'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 1)
end

do
    local w = world('Dolomedes', 'COR')
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.ack('sk'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 0,
        'Dolo became ready before JubileeKeeper proved binding')
    assert(w.ack('jk'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 1)
end

do
    local w = world('Achoo', 'GEO')
    assert(w.tank_mode.value == true and w.tank_mode.unset_count == 0,
        'Tackle-only native AutoTank reservation changed another job')
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(not w.ack('lp'), 'surplus LP ACK was accepted on Achoo')
    assert(w.ack('sk'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 1,
        'ordinary member did not become ready from its exact SK proof')
end

do
    local w = world('Smalls', 'RDM')
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, 'lua load SignetKeeper') == 1)
    now = now + 2.1
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, 'lua load SignetKeeper') == 1,
        'ordinary 2s bind/ACK repair repeated a noisy lua load')
    now = now + 4.1
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, 'lua load SignetKeeper') == 2,
        'bounded delayed load repair did not make its second attempt')
    now = now + 7
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(count_contains(w.commands, 'lua load SignetKeeper') == 2,
        'missing helper caused unbounded already-loaded churn')
    assert(count_contains(w.commands, 'sk armpt '..GENERATION) == 4,
        'silent bind/proof retries stopped with readiness still missing')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(0, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.action('retire', {
        GENERATION, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
        SIGNATURE, 'Dolomedes',
    }))
    assert(w.state.authority == nil and w.state.active == false,
        'stop did not revoke the current adapter authority')
    assert(not w.ack('sk') and not w.ack('lp'))
    assert(count_contains(w.commands, 'pt __controller_ready') == 0,
        'delayed helper ACK revived a stopped generation')
end

print('PartyTactics Locus Signet protocol-2 v1.4 adapter tests passed.')
