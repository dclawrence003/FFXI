local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = test_dir..'/../gearswap/adapters/'
    ..'locus-dire-bats-tomb-signet/1.2.0.lua'

local GENERATION = '1789391000-1001-1'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
local SIGNATURE = '1a2b3c4d'

local function count(values, exact)
    local total = 0
    for _, value in ipairs(values) do
        if value == exact then total = total + 1 end
    end
    return total
end

local function world(name, job)
    local commands, messages = {}, {}
    local current = {
        id=1001, name=name, main_job=job,
        sub_job=job == 'PLD' and 'WAR' or 'THF', status='Idle', buffs={},
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.player = current
    env.PARTYTACTICS_LOCUS_SIGNET_TEST_MODE = true
    env.add_to_chat = function() end
    env.windower = {
        send_command=function(command) commands[#commands + 1] = command end,
        send_ipc_message=function(message) messages[#messages + 1] = message end,
        ffxi={
            get_player=function() return current end,
            get_info=function() return {logged_in=true, zone=190} end,
            get_party=function()
                return {p0={name=name, mob={id=current.id}}}
            end,
            get_mob_by_id=function() return nil end,
            get_mob_by_target=function(token)
                return token == 'me' and {id=current.id, x=0, y=0} or nil
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
            GENERATION, '0', '2', 'locus-dire-bats-tomb-signet', '1.2.0',
            SIGNATURE, 'Dolomedes', ROSTER, tostring(revision), bit,
        })
    end
    return {
        adapter=adapter, state=adapter._test_state, commands=commands,
        messages=messages, action=action, authorize=authorize,
    }
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.adapter.version == '1.2.0' and w.adapter.protocol == 2)
    assert(w.authorize(4, '0'))
    assert(not w.authorize(3, '1'),
        'authorization accepted an operator revision below high-water')
    assert(not w.authorize(4, '1'),
        'authorization accepted a conflicting bit at equal revision')
    w.state.operator_armed = true -- stale unrelated in-memory fallback
    assert(w.authorize(4, '0'),
        'pending OFF authorization fell through to stale boolean state')
    w.state.operator_armed = false
    assert(w.action('probe', {GENERATION, '0', '2'}))
    local bootstrap = ('lp bindpt %s 0 locus-dire-bats-tomb-signet 1.2.0 '
        ..'0.13.2 %s Dolomedes %s 4 0; sk armpt %s 0 Dolomedes %s '
        ..'locus-dire-bats-tomb-signet 1.2.0 0.13.2 %s 4 0')
        :format(GENERATION, SIGNATURE, ROSTER, GENERATION, ROSTER, SIGNATURE)
    assert(count(w.commands, bootstrap) == 1,
        'protocol-2 bootstrap did not pin latest revision/bit for SK and LP')

    assert(w.action('operator', {GENERATION, '0', '2', '5', '1'}))
    assert(count(w.commands, 'pc reconcile on') == 1)
    assert(count(w.commands,
        ('sk operator %s 0 5 1'):format(GENERATION)) == 1)
    assert(w.action('operator', {GENERATION, '0', '2', '5', '1'}))
    assert(count(w.commands, 'pc reconcile on') == 2,
        'equal/same operator replay did not repair local PartyCombat ON')
    assert(count(w.commands,
        ('sk operator %s 0 5 1'):format(GENERATION)) == 2,
        'equal/same operator replay did not repair the local keeper tuple')

    assert(w.action('operator', {GENERATION, '0', '2', '6', '0'}))
    assert(count(w.commands, 'pc reconcile off') == 1,
        'authoritative OFF was not immediate')
    local pc_on_before = count(w.commands, 'pc reconcile on')
    assert(not w.action('operator', {GENERATION, '0', '2', '5', '1'}))
    assert(not w.action('operator', {GENERATION, '0', '2', '6', '1'}))
    assert(count(w.commands, 'pc reconcile on') == pc_on_before,
        'stale/conflicting ON defeated revision-6 OFF')

    assert(w.action('suspend', {GENERATION, '0', '2', '1'}))
    assert(w.action('operator', {GENERATION, '0', '2', '7', '1'}))
    assert(count(w.commands, 'pc reconcile on') == pc_on_before,
        'ON pierced the active Signet suspension')
    assert(w.action('resume', {GENERATION, '0', '2', '6', '0', '1'}),
        'stale resume stranded the mechanical Signet suspension')
    assert(w.state.operator_revision == 7 and w.state.operator_armed == true,
        'stale resume replaced the newer operator high-water')
    assert(count(w.commands, 'pc reconcile on') == pc_on_before + 1,
        'stale resume did not restore from the newer current ON state')
    assert(w.action('resume', {GENERATION, '0', '2', '7', '1', '1'}))
    assert(count(w.commands, 'pc reconcile on') == pc_on_before + 2,
        'equal/current resumed repair did not reconcile PartyCombat')
    local off_before = count(w.commands, 'pc reconcile off')
    assert(w.action('resume', {GENERATION, '0', '2', '8', '0', '1'}))
    assert(count(w.commands, 'pc reconcile off') == off_before + 1,
        'already-resumed recovery did not apply its newer ordered OFF')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(4, '0'))
    assert(w.authorize(7, '0'))
    assert(not w.authorize(6, '0'),
        'delayed authorization overtook a newer pending authorization')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(4, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.adapter.file_unload())
    assert(w.adapter.deactivate('file-unload'))
    local before = #w.commands
    assert(not w.action('authorize', {
        '1789391001-1001-2', '1', '2',
        'locus-dire-bats-tomb-signet', '1.2.0', SIGNATURE,
        'Dolomedes', ROSTER, '5', '0',
    }), 'foreign authorization bypassed the preserved reload handoff')
    assert(#w.commands == before,
        'rejected post-unload authorization reached a companion side effect')
end

do
    local w = world('Dolomedes', 'COR')
    assert(w.authorize(10, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    local jk = ('jk armpt %s 0 locus-dire-bats-tomb-signet 1.2.0 '
        ..'0.13.2 %s Dolomedes %s'):format(GENERATION, SIGNATURE, ROSTER)
    assert(count(w.commands, jk) == 1,
        'Jubilee identity bootstrap changed shape or lost profile pinning')
    assert(w.action('suspend', {GENERATION, '0', '2', '1'}))
    assert(w.action('operator', {GENERATION, '0', '2', '11', '0'}))
    local on_before = count(w.commands, 'pc reconcile on')
    assert(w.action('resume', {GENERATION, '0', '2', '10', '1', '1'}),
        'stale ON resume stranded the adapter in suspension')
    assert(w.state.suspended == false and w.state.operator_revision == 11
        and w.state.operator_armed == false)
    assert(count(w.commands, 'pc reconcile on') == on_before,
        'delayed pre-OFF resume rearmed PartyCombat')
    assert(w.action('resume', {GENERATION, '0', '2', '11', '0', '1'}))
    assert(count(w.commands, 'pc reconcile off') >= 2)
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(4, '1'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.action('suspend', {GENERATION, '0', '2', '1'}))
    assert(w.action('operator', {GENERATION, '0', '2', '6', '0'}))
    local on_before = count(w.commands, 'pc reconcile on')
    assert(w.action('resume', {GENERATION, '0', '2', '5', '1', '1'}),
        'stale resume stranded the adapter in mechanical suspension')
    assert(w.state.suspended == false and w.state.operator_revision == 6
        and w.state.operator_armed == false,
        'stale resume replaced or failed to apply the newer OFF high-water')
    assert(count(w.commands, 'pc reconcile on') == on_before,
        'stale ON resume defeated the newer ordered OFF')
    assert(w.action('operator', {GENERATION, '0', '2', '7', '1'}))
    assert(count(w.commands, 'pc reconcile on') == on_before + 1,
        'later ordered ON remained stuck after stale-resume recovery')
end

do
    local w = world('Tackleberry', 'PLD')
    assert(w.authorize(0, '0'))
    assert(w.action('probe', {GENERATION, '0', '2'}))
    assert(w.action('operator', {GENERATION, '0', '2', '0', '0'}))
    assert(w.action('operator', {GENERATION, '0', '2', '0', '0'}))
    assert(w.action('operator', {GENERATION, '0', '2', '1', '1'}))
    assert(w.action('operator', {GENERATION, '0', '2', '1', '1'}))
    assert(count(w.commands, 'pc on') == 0
        and count(w.commands, 'pc off') == 0,
        'periodic operator repair used noisy PartyCombat commands')
    assert(count(w.commands, 'pc reconcile off') == 2
        and count(w.commands, 'pc reconcile on') == 2,
        'periodic operator repair lost silent ON/OFF convergence')
end

print('PartyTactics Locus Signet protocol-2 v1.2 adapter tests passed.')
