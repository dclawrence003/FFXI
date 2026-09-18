local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1] or
    (test_dir..'/../gearswap/adapters/'
        ..'locus-dire-bats-tomb-signet/1.0.0.lua')
local host_path = test_dir..'/../gearswap/PartyTactics_Host.lua'

local GENERATION = '1789390000-1001-7'
local OLDER_GENERATION = '1789389999-1001-999999'
local NEW_GENERATION = '1789390012-1001-8'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
local SIGNATURE = '1a2b3c4d'

local JOBS = {
    Achoo={'GEO','BLM'},
    Barneystinson={'BRD','WHM'},
    Dolomedes={'COR','THF'},
    Kickpuncher={'DNC','WAR'},
    Smalls={'RDM','WHM'},
    Tackleberry={'PLD','WAR'},
}

local function contains(values, fragment)
    for _, value in ipairs(values) do
        if tostring(value):find(fragment, 1, true) then return true end
    end
    return false
end

local function count(values, fragment)
    local total = 0
    for _, value in ipairs(values) do
        if tostring(value):find(fragment, 1, true) then total = total + 1 end
    end
    return total
end

local function clear(values)
    while #values > 0 do table.remove(values) end
end

local function new_world(name, options)
    options = options or {}
    local jobs = assert(JOBS[name])
    local clock = 100
    local commands, ipc, chats = {}, {}, {}
    local info = {
        logged_in=options.logged_in ~= false,
        zone=options.zone or 190,
    }
    local local_player = {
        id=1001,
        name=name,
        main_job=options.main_job or jobs[1],
        sub_job=options.sub_job or jobs[2],
        status='Idle',
    }
    local current_player = local_player
    local bat = {
        id=17990001,
        index=411,
        name=options.target_name or 'Locus Dire Bat',
        spawn_type=16,
        valid_target=options.valid_target == nil and true
            or options.valid_target,
        hpp=100,
        claim_id=options.claim_id or 0,
        distance=(options.distance or 10)^2,
    }
    local party = {
        p0={name=name, mob={id=1001}},
        p1={name='Dolomedes', mob={id=1002}},
        p2={name='Tackleberry', mob={id=1003}},
        p3={name='Kickpuncher', mob={id=1004}},
        p4={name='Barneystinson', mob={id=1005}},
        p5={name='Smalls', mob={id=1006}},
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.PARTYTACTICS_LOCUS_SIGNET_TEST_MODE = true
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = local_player
    env.add_to_chat = function(color, message)
        chats[#chats + 1] = {color=color, message=message}
    end
    env.windower = {
        send_command=function(command) commands[#commands + 1] = command end,
        send_ipc_message=function(message) ipc[#ipc + 1] = message end,
        ffxi={
            get_player=function() return current_player end,
            get_info=function() return info end,
            get_mob_by_id=function(id)
                return tonumber(id) == bat.id and bat or nil
            end,
            get_mob_by_target=function(token)
                if token == 'me' then return {id=local_player.id,x=0,y=0} end
                return nil
            end,
            get_party=function() return party end,
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
    if not options.skip_activate then
        local activated = adapter.activate()
        if options.activation_expected == false then
            -- Invalid-zone/identity activation is deliberately retained by
            -- the stable host as an inert adapter. That gives its prerender
            -- callback ownership of one delayed terminal-OFF reassertion; it
            -- never grants profile authority or boots companions.
            assert(activated == true)
            assert(adapter._test_state.active == false)
        else
            assert(activated == true)
        end
    end

    local world = {
        env=env,
        adapter=adapter,
        state=adapter._test_state,
        commands=commands,
        ipc=ipc,
        chats=chats,
        player=local_player,
        bat=bat,
        party=party,
        info=info,
        generation=GENERATION,
        epoch=0,
    }
    function world:advance(seconds) clock = clock + seconds end
    function world:authorize(generation, epoch, protocol, signature)
        return self.adapter.handle_action('locus-signet', 'authorize', {
            generation or self.generation,
            tostring(epoch == nil and self.epoch or epoch),
            tostring(protocol or 1),
            'locus-dire-bats-tomb-signet', '1.0.0',
            signature or SIGNATURE, 'Dolomedes', ROSTER,
        })
    end
    function world:raw_probe(generation, epoch, protocol)
        return self.adapter.handle_action('locus-signet', 'probe', {
            generation or self.generation,
            tostring(epoch == nil and self.epoch or epoch),
            tostring(protocol or 1),
        })
    end
    function world:probe(generation, epoch, protocol)
        generation = generation or self.generation
        epoch = epoch == nil and self.epoch or epoch
        protocol = protocol or 1
        local authority = self.state.authority
        if not authority or authority.generation ~= generation
            or authority.epoch ~= epoch
        then
            self:authorize(generation, epoch, protocol)
        end
        return self:raw_probe(generation, epoch, protocol)
    end
    function world:action(semantic, arguments)
        return self.adapter.handle_action('locus-signet', semantic, arguments)
    end
    function world:clear()
        clear(self.commands)
        clear(self.ipc)
        clear(self.chats)
    end
    function world:drop_player()
        current_player = nil
        self.env.player = nil
    end
    return world
end

-- Exercise the real stable-host raw logout chain with the real adapter. The
-- host invokes adapter.logout, immediately invokes deactivate('logout'), and
-- removes the adapter record. Only the exact PartyTactics callback may survive
-- that sequence; the adapter-owned prerender retry must be cancelled.
do
    local w = new_world('Dolomedes', {skip_activate=true})
    local raw_events = {}
    w.env.windower.raw_register_event = function(name, callback)
        raw_events[name] = raw_events[name] or {}
        raw_events[name][#raw_events[name] + 1] = callback
    end
    w.env.include = function(path)
        assert(path == 'Common/PartyTactics/adapters/'
            ..'locus-dire-bats-tomb-signet/1.0.0.lua')
        return w.adapter
    end
    w.env.pre_tick = function() end
    w.env.user_job_tick = function() end
    w.env.user_filter_pretarget = function() end
    w.env.user_filter_precast = function() end
    w.env.job_aftercast = function() end
    w.env.user_job_self_command = function() end
    w.env.file_unload = function() end
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(host_path)
        if loader then setfenv(loader, w.env) end
    else
        loader, load_error = loadfile(host_path, 't', w.env)
    end
    assert(loader, load_error)
    local host = loader()
    local event_args = {handled=false}
    w.env.user_job_self_command({'ptgs','activate',
        'locus-dire-bats-tomb-signet','1.0.0'}, event_args)
    assert(event_args.handled and host.active_metadata())
    event_args = {handled=false}
    w.env.user_job_self_command({'ptgs','action','locus-signet','authorize',
        GENERATION,'0','1','locus-dire-bats-tomb-signet','1.0.0',
        SIGNATURE,'Dolomedes',ROSTER}, event_args)
    assert(event_args.handled)
    event_args = {handled=false}
    w.env.user_job_self_command({'ptgs','action','locus-signet','probe',
        GENERATION,'0','1'}, event_args)
    assert(event_args.handled and w.state.authority)
    w:clear()
    w:drop_player()
    assert(raw_events.logout and #raw_events.logout == 1)
    raw_events.logout[1]('raw-logout')
    assert(host.active_metadata() == nil)
    assert(contains(w.commands,
        'wait 2; pt __controller_terminal locus-signet '
            ..GENERATION..' 0 1'))
    assert(contains(w.commands, 'pc localstop; aws2 off'))
    assert(w.commands[#w.commands]
        == 'pt __gearswap_host_lost 1.2.1 logout')
    w:clear()
    w:advance(2.1)
    assert(raw_events.prerender and #raw_events.prerender == 1)
    raw_events.prerender[1]()
    assert(not contains(w.commands, 'pc localstop'))
    assert(not contains(w.commands, 'aws2 off'))
end

-- Exact metadata and capability bootstrap. No probe means no companion may
-- receive lifecycle authority.
do
    local w = new_world('Dolomedes')
    assert(w.adapter.id == 'locus-dire-bats-tomb-signet')
    assert(w.adapter.version == '1.0.0')
    assert(w.adapter.controller == 'locus-signet')
    assert(w.adapter.protocol == 1)
    assert(w:action('suspend', {GENERATION,'0','1','1'}) == false)
    assert(w:probe('bad;generation') == false)
    assert(w:probe('01789390000-1001-7') == false)
    assert(w:probe(GENERATION, -1) == false)
    assert(w:probe(GENERATION, 0, 2) == false)
    assert(w.adapter.handle_action('other', 'probe',
        {GENERATION,'0','1'}) == false)
    assert(w:raw_probe() == false,
        'an uncommitted generation reached controller authority')
    assert(w:probe() == true)
    assert(contains(w.commands,
        'sk authorize '..GENERATION..' 0 Dolomedes '..ROSTER
            ..' locus-dire-bats-tomb-signet 1.0.0 0.13.1 '
            ..SIGNATURE))
    assert(contains(w.commands,
        'sk armpt '..GENERATION
            ..' 0 Dolomedes '..ROSTER
            ..' locus-dire-bats-tomb-signet 1.0.0'))
    assert(contains(w.commands,
        'jk armpt '..GENERATION
            ..' 0 locus-dire-bats-tomb-signet 1.0.0 0.13.1 '
            ..SIGNATURE..' Dolomedes '..ROSTER))
    assert(contains(w.commands,
        'pt __controller_ready locus-signet '..GENERATION..' 0 1'))
    assert(not contains(w.commands, 'lp bindpt'))
end

-- Every private semantic has an exact field count. A syntactically valid
-- prefix plus surplus data is not a compatible protocol revision and cannot
-- mutate controller, maintenance, or opener state.
do
    local w = new_world('Smalls')
    assert(w:authorize())
    assert(w:action('probe', {GENERATION,'0','1','surplus'}) == false)
    assert(w.state.authority == nil)
    assert(w:raw_probe())
    assert(w:action('suspend', {
        GENERATION,'0','1','1','surplus'}) == false)
    assert(w.state.suspended == false)
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    assert(w:action('resume', {
        GENERATION,'0','1','0','1','surplus'}) == false)
    assert(w.state.suspended == true)
    assert(w:action('resume', {GENERATION,'0','1','0','1'}))

    local tackle = new_world('Tackleberry')
    assert(tackle:probe())
    assert(tackle:action('opener-arm', {
        tostring(tackle.bat.id),GENERATION,'0','1','surplus'}) == false)
    assert(tackle.state.opener == nil)
end

-- A validated PartyTactics stop is also a local no-loopback tombstone. It is
-- accepted before capability authority exists, fences an already queued
-- authorize/probe, and delegates each companion's exact stop syntax locally.
do
    local w = new_world('Dolomedes')
    w:clear()
    local retired = {
        GENERATION, '0.13.1', 'locus-dire-bats-tomb-signet', '1.0.0',
        SIGNATURE, 'Dolomedes',
    }
    local surplus = {}
    for index, value in ipairs(retired) do surplus[index] = value end
    surplus[#surplus + 1] = 'surplus'
    assert(w:action('retire', surplus) == false)
    assert(#w.commands == 0)
    assert(w:action('retire', retired))
    assert(contains(w.commands,
        'sk stoppt '..GENERATION
            ..' 0.13.1 locus-dire-bats-tomb-signet 1.0.0 '
            ..SIGNATURE..' Dolomedes'))
    assert(contains(w.commands,
        'jk stoppt '..GENERATION
            ..' 0.13.1 locus-dire-bats-tomb-signet 1.0.0 '
            ..SIGNATURE..' Dolomedes'))
    assert(w:authorize() == false)
    assert(w:raw_probe() == false)

    local tackle = new_world('Tackleberry')
    tackle:clear()
    assert(tackle:action('retire', retired))
    assert(contains(tackle.commands,
        'lp retirept '..GENERATION
            ..' 0.13.1 locus-dire-bats-tomb-signet 1.0.0 '
            ..SIGNATURE..' Dolomedes'))
end

-- Every exact roster identity/main job is supported. Subjobs in the profile
-- are recommendations and never withhold controller authority.
do
    for name, _ in pairs(JOBS) do
        local w = new_world(name)
        assert(w:probe() == true, name..' did not accept exact probe')
    end
    assert(new_world('Tackleberry', {sub_job='BLU'}):probe() == true)
    assert(new_world('Achoo', {sub_job='WHM'}):probe() == true)
    assert(new_world('Barneystinson', {sub_job='BLM'}):probe() == true)
    assert(new_world('Dolomedes', {sub_job='WAR'}):probe() == true)
    assert(new_world('Tackleberry', {
        main_job='WAR', activation_expected=false}):probe() == false)
end

-- Suspension reserves automatic callbacks only, turns off external automatic
-- lanes, and acknowledges both IPC peers and the local keeper.
do
    local w = new_world('Smalls')
    assert(w:probe())
    w:clear()
    assert(w:action('suspend', {GENERATION,'0','1','1'}) == true)
    assert(contains(w.commands, 'pc off; aws2 off'))
    assert(contains(w.ipc,
        'SIGNETKEEPER1|adapter|'..GENERATION..'|Smalls|0|suspended|1'))
    assert(contains(w.commands,
        'sk __adapter '..GENERATION..' Smalls 0 suspended 1'))
    assert(w.adapter.pre_tick() == true)
    assert(w.adapter.user_job_tick() == true)
    assert(w.adapter.user_job_self_command({'pstartrdm','tick'}, {}) == true)
    assert(w.adapter.user_job_self_command({'pstartrdm','anything'}, {}) == false)
    assert(w.adapter.user_job_self_command({'input','/ma'}, {}) == false)
    assert(w.adapter.filter_pretarget({}, nil, {}) == false)
    assert(w.adapter.filter_precast({}, nil, {}) == false)
    w:clear()
    assert(w:action('resume', {GENERATION,'0','1','0','1'}) == true)
    assert(contains(w.commands, 'aws2 on'))
    assert(contains(w.commands,
        'hb deactivateindoors off; hb disable cure; hb enable na'))
    assert(contains(w.commands,
        'sk __adapter '..GENERATION..' Smalls 0 resumed 1'))
    assert(not contains(w.commands, 'pc on'))
    assert(w.adapter.pre_tick() == false)
end

-- Renewal cycles are monotonic within one PartyTactics generation. Delayed
-- ACK/action traffic from an earlier cycle cannot resume or re-suspend a
-- later cycle.
do
    local w = new_world('Smalls')
    assert(w:probe())
    w:clear()
    assert(w:action('suspend', {GENERATION,'0','1','3'}) == false)
    assert(w.state.maintenance_cycle == nil)
    assert(not contains(w.commands, 'pc off'))
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    assert(w:action('resume', {GENERATION,'0','1','0','1'}))
    assert(w:action('suspend', {GENERATION,'0','1','3'}) == false)
    assert(w:action('suspend', {GENERATION,'0','1','2'}))
    w:clear()
    assert(w:action('resume', {GENERATION,'0','1','0','1'}) == false)
    assert(w:action('suspend', {GENERATION,'0','1','1'}) == false)
    assert(not contains(w.commands, 'aws2 on'))
    assert(w.adapter.pre_tick() == true)
    assert(w:action('resume', {GENERATION,'0','1','0','2'}))
    w:clear()
    assert(w:action('suspend', {GENERATION,'0','1','2'}) == false)
    assert(not contains(w.commands, 'aws2 off'))
end

-- A duplicate exact probe is a reload retry, not a new authority. It rebinds
-- companions without detaching them or losing the active renewal cycle.
do
    local w = new_world('Smalls')
    assert(w:probe())
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    w:clear()
    assert(w:probe())
    assert(not contains(w.commands, 'sk detach'))
    assert(contains(w.commands, 'sk armpt '..GENERATION..' 0'))
    assert(w.state.suspended == true)
    assert(w.state.maintenance_cycle == 1)
    assert(w.adapter.pre_tick() == true)
end

-- A normal PartyTactics transition must first deactivate the exact old
-- authority. A different generation cannot replace a still-bound adapter,
-- and the retired predecessor cannot reclaim it after the new bind.
do
    local w = new_world('Smalls')
    assert(w:probe())
    w:clear()
    assert(w:probe(NEW_GENERATION, 0, 1) == false)
    assert(not contains(w.commands, 'sk detach'))
    assert(not contains(w.commands, 'sk armpt'))
    assert(w.state.authority.generation == GENERATION)
    assert(w.adapter.deactivate('profile replaced'))
    assert(contains(w.commands, 'sk detach '..GENERATION..' 0'))
    w:clear()
    assert(w.adapter.activate())
    w:clear()
    assert(w:probe(NEW_GENERATION, 0, 1))
    assert(contains(w.commands, 'sk armpt '..NEW_GENERATION..' 0'))
    w:clear()
    assert(w:probe(GENERATION, 0, 1) == false)
    assert(not contains(w.commands, 'sk detach'))
    assert(not contains(w.commands, 'sk armpt'))
    assert(w.state.authority.generation == NEW_GENERATION
        and w.state.authority.epoch == 0)
    assert(w:action('suspend', {GENERATION,'0','1','1'}) == false)
    assert(not contains(w.commands, 'pc off'))
    assert(w:action('suspend', {NEW_GENERATION,'0','1','1'}))
    assert(contains(w.commands, 'pc off; aws2 off'))
end

-- Epochs are monotonic only inside one bound generation. Different
-- generations are deliberately not compared numerically because their nonce
-- player/clock components belong to different processes.
do
    local w = new_world('Tackleberry')
    assert(w:probe(GENERATION, 0, 1))
    w:clear()
    assert(w:probe(OLDER_GENERATION, 0, 1) == false)
    assert(w:probe(NEW_GENERATION, 1, 1) == false)
    assert(not contains(w.commands, 'lp unbindpt'))
    assert(not contains(w.commands, 'lp bindpt'))
    assert(w.state.authority.generation == GENERATION
        and w.state.authority.epoch == 0)

    assert(w:probe(GENERATION, 3, 1))
    assert(contains(w.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(contains(w.commands, 'lp bindpt '..GENERATION..' 3'))
    assert(w.state.authority.generation == GENERATION
        and w.state.authority.epoch == 3)

    w:clear()
    assert(w:probe(GENERATION, 2, 1) == false)
    assert(not contains(w.commands, 'lp unbindpt'))
    assert(not contains(w.commands, 'lp bindpt'))
    assert(w.state.authority.epoch == 3)
    assert(w:probe(GENERATION, 3, 1))
    assert(not contains(w.commands, 'lp unbindpt'))
    assert(contains(w.commands, 'lp bindpt '..GENERATION..' 3'))

    -- Once normal teardown leaves the adapter unbound, an unrelated nonce
    -- that sorts lower is still a valid new lifecycle. Only retired exact
    -- predecessor generations remain fenced.
    assert(w.adapter.deactivate('command'))
    assert(w.adapter.activate())
    w:clear()
    assert(w:probe(OLDER_GENERATION, 0, 1))
    assert(contains(w.commands, 'lp bindpt '..OLDER_GENERATION..' 0'))
    assert(w:probe(GENERATION, 3, 1) == false)
end

-- A puller release delayed until after Signet suspension is idempotent but
-- may not revive AutoWS2 inside the staff transaction.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    w:clear()
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    assert(contains(w.commands, 'aws2 off'))
    w:clear()
    assert(w:action('opener-release', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    assert(not contains(w.commands, 'aws2 on'))
    assert(w.adapter.pre_tick() == true)
end

-- Teardown uses the identity proven at probe time. Windower may clear its
-- player object before raw logout/unload callbacks arrive.
do
    local dolo = new_world('Dolomedes')
    assert(dolo:probe())
    dolo:clear()
    dolo:drop_player()
    assert(dolo.adapter.logout())
    assert(contains(dolo.commands, 'sk detach '..GENERATION..' 0'))
    assert(contains(dolo.commands, 'jk detach '..GENERATION..' 0'))
    assert(contains(dolo.commands,
        'wait 2; pt __controller_terminal locus-signet '
            ..GENERATION..' 0 1'))
    assert(not contains(dolo.commands, 'aws2 on'))
    assert(not contains(dolo.commands, 'pc on'))
    -- Match the stable host's exact raw-logout chain: it invokes logout and
    -- immediately deactivates/removes the adapter. The adapter timer is gone,
    -- but the generation-scoped PartyTactics callback remains queued.
    assert(dolo.adapter.deactivate('logout'))
    dolo:clear()
    dolo:advance(2.1)
    dolo.adapter.prerender()
    assert(not contains(dolo.commands, 'pc localstop'))
    assert(not contains(dolo.commands, 'aws2 off'))

    local tackle = new_world('Tackleberry')
    assert(tackle:probe())
    assert(tackle:action('opener-arm', {
        tostring(tackle.bat.id),GENERATION,'0','1'}))
    tackle:clear()
    tackle:drop_player()
    tackle.adapter.zone_change()
    assert(contains(tackle.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(not contains(tackle.commands, 'aws2 on'))
    assert(not contains(tackle.commands, 'pc on'))
end

-- The generation-bound SignetKeeper supplies its already validated operator
-- bit. Tackle alone may translate a true bit into a PartyCombat arm.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    assert(contains(w.commands,
        'lp authorize '..GENERATION
            ..' 0 locus-dire-bats-tomb-signet 1.0.0 0.13.1 '
            ..SIGNATURE..' Dolomedes '..ROSTER))
    assert(contains(w.commands,
        'lp bindpt '..GENERATION
            ..' 0 locus-dire-bats-tomb-signet 1.0.0 0.13.1 '
            ..SIGNATURE..' Dolomedes '..ROSTER))
    local ordered_lifecycle = false
    for _, command in ipairs(w.commands) do
        local puller = command:find('lp bindpt '..GENERATION..' 0', 1, true)
        local keeper = command:find('sk armpt '..GENERATION..' 0', 1, true)
        if puller and keeper and puller < keeper then
            ordered_lifecycle = true
        end
    end
    assert(ordered_lifecycle,
        'puller binding must precede the initial SignetKeeper state replay')
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    w:clear()
    assert(w:action('resume', {GENERATION,'0','1','1','1'}))
    assert(contains(w.commands, 'pc on'))

    assert(w:action('suspend', {GENERATION,'0','1','2'}))
    w:clear()
    assert(w:action('resume', {GENERATION,'0','1','0','2'}))
    assert(not contains(w.commands, 'pc on'))
end

do
    local w = new_world('Dolomedes')
    assert(w:probe())
    w:clear()
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    assert(contains(w.commands, 'r2 off'))
    w:clear()
    assert(w:action('resume', {GENERATION,'0','1','1','1'}))
    assert(contains(w.commands, 'r2 on'))
    assert(not contains(w.commands, 'pc on'),
        'non-puller issued a competing resume arm')
end

-- Tackle's first-hit reservation requires the exact in-zone bat, suppresses
-- only automatic helper work, and is idempotently releasable.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    w:clear()
    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}) == true)
    assert(contains(w.commands, 'aws2 off'))
    assert(contains(w.commands,
        'lp __gate_armed '..w.bat.id..' '..GENERATION..' 0'))
    assert(w.adapter.pre_tick() == true)
    assert(w.adapter.user_job_tick() == true)
    assert(w.adapter.user_job_self_command({'pstartpld','tick'}, {}) == true)
    assert(w.adapter.user_job_self_command(
        {'pstartpld','subjobenmity'}, {}) == true)
    assert(w.adapter.user_job_self_command({'pstartpld','opener'}, {}) == false)
    assert(w.adapter.user_job_self_command({'input','/ja'}, {}) == false)
    assert(w.adapter.filter_pretarget({}, nil, {}) == false)
    assert(w.adapter.filter_precast({}, nil, {}) == false)
    w:clear()
    assert(w:action('opener-release', {
        tostring(w.bat.id),GENERATION,'0','1'}) == true)
    assert(contains(w.commands, 'aws2 on'))
    assert(w.adapter.pre_tick() == false)
    -- A duplicate release is silent because the first release already
    -- restored AutoWS2 exactly once.
    w:clear()
    assert(w:action('opener-release', {
        tostring(w.bat.id),GENERATION,'0','1'}) == true)
    assert(not contains(w.commands, 'aws2 on'))

    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    w:clear()
    assert(w:action('opener-release', {
        tostring(w.bat.id),GENERATION,'0','1','keepoff'}))
    assert(not contains(w.commands, 'aws2 on'))
    assert(w.adapter.pre_tick() == false)
    assert(w:action('opener-release', {
        tostring(w.bat.id),GENERATION,'0','1','anything'}) == false)
end

-- Independent six-second timeout: Flash or first-melee packet loss cannot
-- strand PLD automation or AutoWS2.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    w:clear()
    w:advance(6.1)
    w.adapter.prerender()
    assert(contains(w.commands, 'aws2 on'))
    assert(w.adapter.pre_tick() == false)
    assert(w.state.opener_timeouts == 1)
end

-- Target, zone, claim, identity, and authority failures affect only this
-- semantic request; they never add an input filter.
do
    local zone = new_world('Tackleberry', {
        zone=191, activation_expected=false})
    assert(not contains(zone.commands, 'lua load SignetKeeper'))
    assert(not contains(zone.commands, 'lua load LocusPuller'))
    assert(contains(zone.commands, 'pc localstop; aws2 off'))
    assert(not contains(zone.commands, 'wait 2; pc localstop'))
    assert(contains(zone.commands, 'gs c pstartpld off'))
    assert(contains(zone.commands, 'gs c unset AutoTankMode'))
    zone:clear()
    zone.commands[#zone.commands + 1] =
        'compiler-emulation: aws2 on; pc on; gs c pstartpld locusbats'
    zone:advance(2.1)
    zone.adapter.prerender()
    assert(zone.commands[#zone.commands]:find(
        'pc localstop; aws2 off', 1, true))
    assert(zone.commands[#zone.commands]:find(
        'gs c pstartpld off', 1, true))
    zone:clear()
    assert(zone:probe() == false)
    assert(not contains(zone.commands, 'sk armpt'))
    assert(not contains(zone.commands, 'lp bindpt'))
    assert(contains(zone.commands, 'pc localstop; aws2 off'))

    -- The host keeps that invalid-zone activation only as an inert timer
    -- owner and short-circuits a later same-id activate. Once back in Tomb,
    -- the accepted probe must therefore load and bind its companions itself,
    -- and cancel the old terminal retry.
    local returned = new_world('Tackleberry', {
        zone=191, activation_expected=false})
    assert(not contains(returned.commands, 'lua load SignetKeeper'))
    returned.info.zone = 190
    returned:clear()
    assert(returned:probe())
    assert(contains(returned.commands, 'lua load SignetKeeper'))
    assert(contains(returned.commands, 'lua load LocusPuller'))
    assert(contains(returned.commands,
        'lp bindpt '..GENERATION..' 0'))
    returned:clear()
    returned:advance(2.1)
    returned.adapter.prerender()
    assert(not contains(returned.commands, 'pc localstop'))
    assert(not contains(returned.commands, 'aws2 off'))

    local raced = new_world('Tackleberry')
    raced:clear()
    raced.info.zone = 191
    assert(raced:probe() == false)
    assert(not contains(raced.commands, 'sk armpt'))
    assert(not contains(raced.commands, 'lp bindpt'))
    assert(contains(raced.commands, 'pc localstop; aws2 off'))

    local missed_zone_callback = new_world('Tackleberry')
    assert(missed_zone_callback:probe())
    missed_zone_callback.info.zone = 191
    missed_zone_callback:clear()
    assert(missed_zone_callback.adapter.activate() == true)
    assert(missed_zone_callback.state.active == false)
    assert(contains(missed_zone_callback.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(missed_zone_callback.commands[#missed_zone_callback.commands]:find(
        'pc localstop; aws2 off', 1, true))
    assert(not contains(missed_zone_callback.commands, 'lp bindpt'))

    local departed = new_world('Tackleberry')
    assert(departed:probe())
    departed:clear()
    departed.info.zone = 191
    departed.adapter.zone_change()
    assert(contains(departed.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(contains(departed.commands, 'pc localstop; aws2 off'))
    departed:clear()
    -- The stable GearSwap host may short-circuit activate for the same pinned
    -- adapter. Deliver only its delayed higher-epoch probe, then emulate
    -- already-queued compiler support commands arriving after that immediate
    -- rejection. The adapter-owned timer must append the terminal OFF baseline
    -- after those commands without embedding a raw delayed OFF command.
    assert(departed:probe(GENERATION, 1, 1) == false)
    assert(not contains(departed.commands, 'sk armpt'))
    assert(not contains(departed.commands, 'lp bindpt'))
    departed.commands[#departed.commands + 1] =
        'compiler-emulation: aws2 on; hb on; gs c pstartpld locusbats'
    departed:advance(2.1)
    departed.adapter.prerender()
    assert(departed.commands[#departed.commands]:find(
        'pc localstop; aws2 off', 1, true))
    assert(departed.commands[#departed.commands]:find(
        'gs c pstartpld off', 1, true))

    departed:clear()
    assert(departed.adapter.activate() == true)
    assert(departed.commands[#departed.commands]:find(
        'pc localstop; aws2 off', 1, true))

    -- A profile replacement cancels the adapter-owned retry. Even calling the
    -- old module directly after the deadline (stronger than the real host,
    -- which no longer dispatches to it) cannot shut the new profile down.
    local switched = new_world('Tackleberry', {
        zone=191, activation_expected=false})
    switched:clear()
    assert(switched.adapter.deactivate('replaced'))
    switched.commands[#switched.commands + 1] =
        'different-profile-emulation: pc on; aws2 on'
    switched:advance(2.1)
    switched.adapter.prerender()
    assert(#switched.commands == 1)
    assert(not contains(switched.commands, 'pc localstop'))
    assert(not contains(switched.commands, 'aws2 off'))

    -- A later return to the owned zone may advance the still-current PT
    -- generation. Only the retired exact departure tuple is fenced; opaque
    -- generation-wide numeric ordering is deliberately absent.
    departed.info.zone = 190
    departed:clear()
    assert(departed:probe(GENERATION, 2, 1))
    assert(contains(departed.commands,
        'lp bindpt '..GENERATION..' 2'))

    local delayed_suspend = new_world('Smalls')
    assert(delayed_suspend:probe())
    delayed_suspend.info.zone = 191
    delayed_suspend:clear()
    assert(delayed_suspend:action('suspend', {
        GENERATION,'0','1','1'}) == false)
    assert(not contains(delayed_suspend.commands, 'pc off'))

    local delayed_resume = new_world('Smalls')
    assert(delayed_resume:probe())
    assert(delayed_resume:action('suspend', {
        GENERATION,'0','1','1'}))
    delayed_resume.info.zone = 191
    delayed_resume:clear()
    assert(delayed_resume:action('resume', {
        GENERATION,'0','1','0','1'}) == false)
    assert(not contains(delayed_resume.commands, 'aws2 on'))
    assert(not contains(delayed_resume.commands, 'pc on'))

    local far = new_world('Tackleberry', {distance=21})
    assert(far:probe())
    assert(far:action('opener-arm', {
        tostring(far.bat.id),GENERATION,'0','1'}) == false)

    local foreign = new_world('Tackleberry', {claim_id=999999})
    assert(foreign:probe())
    assert(foreign:action('opener-arm', {
        tostring(foreign.bat.id),GENERATION,'0','1'}) == false)

    local wrong = new_world('Tackleberry', {target_name='Locus Dire Bird'})
    assert(wrong:probe())
    assert(wrong:action('opener-arm', {
        tostring(wrong.bat.id),GENERATION,'0','1'}) == false)
end

do
    local w = new_world('Dolomedes')
    assert(w:probe())
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    w:clear()
    assert(w.adapter.deactivate('profile replaced'))
    assert(contains(w.commands, 'sk detach '..GENERATION..' 0'))
    assert(contains(w.commands, 'jk detach '..GENERATION..' 0'))
    assert(not contains(w.commands, 'aws2 on'))
    assert(not contains(w.commands, 'r2 on'))
    assert(not contains(w.commands, 'hb on'))
    assert(not contains(w.commands, 'pc on'))
end

-- Normal profile teardown stays inert even during a PLD reservation. The
-- keepoff token prevents LocusPuller's own fail-open release from racing the
-- compiler's final AutoWS2 OFF command.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    w:clear()
    assert(w.adapter.deactivate('command'))
    assert(contains(w.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(w.commands[1]:find('lp unbindpt', 1, true)
        and w.commands[2]:find('sk detach', 1, true),
        'keepoff puller release must precede Signet authority detach')
    assert(not contains(w.commands, 'aws2 on'))
    assert(not contains(w.commands, 'pc on'))
end

-- GearSwap reload hands exact authority to reload-safe companions instead of
-- detaching them. Automatic lanes remain OFF during the host gap, and the
-- host's follow-up deactivate forgets only this dead adapter instance.
do
    local w = new_world('Tackleberry')
    assert(w:probe())
    assert(w:action('opener-arm', {
        tostring(w.bat.id),GENERATION,'0','1'}))
    w:clear()
    assert(w.adapter.file_unload())
    assert(contains(w.commands, 'pc off; aws2 off'))
    assert(contains(w.commands, 'lp gsreload '..GENERATION..' 0'))
    assert(contains(w.commands, 'sk gsreload '..GENERATION..' 0'))
    assert(not contains(w.commands, 'lp unbindpt'))
    assert(not contains(w.commands, 'sk detach'))
    assert(not contains(w.commands, 'sk stoppt'))
    assert(not contains(w.commands, 'lp retirept'))
    assert(not contains(w.commands, 'aws2 on'))
    assert(not contains(w.commands, 'pc on'))
    w:clear()
    assert(w.adapter.deactivate('file-unload'))
    assert(not contains(w.commands, 'lp unbindpt'))
    assert(not contains(w.commands, 'sk detach'))
    assert(not contains(w.commands, 'aws2 on'))
    assert(not contains(w.commands, 'pc on'))

    -- A different generation may take over a still-loaded module only during
    -- the explicit bounded GearSwap reload handoff, at epoch zero.
    local handoff = new_world('Tackleberry')
    assert(handoff:probe())
    assert(handoff.adapter.file_unload())
    handoff:clear()
    assert(handoff:probe(NEW_GENERATION, 1, 1) == false)
    assert(not contains(handoff.commands, 'lp unbindpt'))
    assert(handoff:probe(NEW_GENERATION, 0, 1))
    assert(contains(handoff.commands,
        'lp unbindpt '..GENERATION..' 0 keepoff'))
    assert(contains(handoff.commands, 'lp bindpt '..NEW_GENERATION..' 0'))
    handoff:clear()
    assert(handoff:probe(GENERATION, 0, 1) == false)
    assert(not contains(handoff.commands, 'lp bindpt'))
    -- A full-profile successor restarts SignetKeeper's renewal transaction,
    -- so even an interrupted later cycle begins again at cycle 1 under the
    -- fresh generation instead of poisoning the new adapter's high-water.
    handoff:clear()
    assert(handoff:action('suspend', {
        NEW_GENERATION,'0','1','7'}) == false)
    assert(handoff.state.maintenance_cycle == nil)
    assert(handoff:action('suspend', {
        NEW_GENERATION,'0','1','1'}))

    local dolo = new_world('Dolomedes')
    assert(dolo:probe())
    dolo:clear()
    assert(dolo.adapter.file_unload())
    assert(contains(dolo.commands, 'pc off; aws2 off'))
    assert(contains(dolo.commands, 'r2 off'))
    assert(contains(dolo.commands, 'jk gsreload '..GENERATION..' 0'))
    assert(contains(dolo.commands, 'sk gsreload '..GENERATION..' 0'))
    assert(not contains(dolo.commands, 'jk detach'))
    assert(not contains(dolo.commands, 'jk stoppt'),
        'GearSwap recovery must preserve JubileeKeeper ownership')
    assert(not contains(dolo.commands, 'sk stoppt'),
        'GearSwap recovery must preserve SignetKeeper ownership')

    local raw = new_world('Dolomedes')
    assert(raw:probe())
    raw:clear()
    assert(raw.adapter.unload())
    assert(contains(raw.commands, 'jk gsreload '..GENERATION..' 0'))
    raw:clear()
    assert(raw.adapter.deactivate('unload'))
    assert(not contains(raw.commands, 'jk detach'))
    assert(not contains(raw.commands, 'sk detach'))

    -- Full `pt reapply` creates a fresh nonce at epoch zero. Recovery never
    -- assumes that the old nonce survives or that its epoch increments.
    local recovered = new_world('Tackleberry')
    recovered.generation = NEW_GENERATION
    assert(recovered:probe())
    assert(contains(recovered.commands,
        'lp bindpt '..NEW_GENERATION..' 0'))
    assert(contains(recovered.commands,
        'sk armpt '..NEW_GENERATION..' 0'))
end

-- An actual adapter callback exception is the one teardown path that restores
-- owned automatic lanes fail-open while still never arming PartyCombat.
do
    local w = new_world('Dolomedes')
    assert(w:probe())
    assert(w:action('suspend', {GENERATION,'0','1','1'}))
    w:clear()
    assert(w.adapter.deactivate('error:pre_tick'))
    assert(contains(w.commands, 'aws2 on'))
    assert(contains(w.commands, 'r2 on'))
    assert(not contains(w.commands, 'pc on'))
end

print('PartyTactics Locus Signet adapter tests passed.')
