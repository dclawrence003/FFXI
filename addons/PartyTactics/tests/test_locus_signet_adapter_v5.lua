local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = test_dir..'/../gearswap/adapters/'
    ..'locus-dire-bats-tomb-signet/1.5.0.lua'

local GENERATION = '1789437000-1001-1'
local PROFILE_ID = 'locus-dire-bats-tomb-signet'
local PROFILE_VERSION = '1.5.0'
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
        -- Deliberately contradictory target fields. Version 1.5 leaves the
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

local function sustain_world(name, job, options)
    options = options or {}
    now = options.now or 500
    local commands, inputs = {}, {}
    local tank_mode = {value=true}
    function tank_mode:unset() self.value = false end
    local current = {
        id=1001, index=101, name=name or 'Tackleberry',
        main_job=job or 'PLD', sub_job='WAR', status=1,
        hpp=100, mp=options.mp or 1000, max_mp=1000,
        mpp=options.mpp or 100, buffs={},
    }
    local names = {
        current.name, 'Dolomedes', 'Kickpuncher',
        'Barneystinson', 'Smalls', 'Achoo',
    }
    local party, mobs = {}, {}
    for slot, member_name in ipairs(names) do
        local id = 1000 + slot
        if slot == 1 then id = current.id end
        local mob = {
            id=id, index=100+slot, name=member_name,
            distance=member_name == current.name and 0 or 10^2,
        }
        mobs[id], mobs[member_name:lower()] = mob, mob
        party['p'..tostring(slot-1)] = {
            name=member_name, hpp=100, mob=mob,
        }
    end
    local learned = {[1]=true,[2]=true,[3]=true,[4]=true}
    for id, value in pairs(options.learned or {}) do learned[id] = value end
    local spell_recasts = {[1]=0,[2]=0,[3]=0,[4]=0}
    for id, value in pairs(options.spell_recasts or {}) do
        spell_recasts[id] = value
    end
    local ability_recasts = {[150]=options.majesty_recast or 0}
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.player = current
    env.state = {AutoTankMode=tank_mode}
    env.PARTYTACTICS_LOCUS_SIGNET_TEST_MODE = true
    env.os = {clock=function() return now end}
    env.tickdelay = 0
    env.moving = false
    env.latency = 0.5
    env.spell_latency = 0.5
    env.buffactive = {Majesty=options.majesty ~= false}
    env.midaction = function() return false end
    env.silent_check_disable = function() return false end
    env.silent_check_amnesia = function() return false end
    env.silent_can_use = function() return true end
    env.add_to_chat = function() end
    env.windower = {
        send_command=function(command) commands[#commands + 1] = command end,
        send_ipc_message=function() end,
        chat={input=function(command) inputs[#inputs + 1] = command end},
        ffxi={
            get_player=function() return current end,
            get_info=function() return {logged_in=true, zone=190} end,
            get_party=function() return party end,
            get_mob_by_id=function(id) return mobs[tonumber(id)] end,
            get_mob_by_name=function(wanted)
                return type(wanted) == 'string' and mobs[wanted:lower()] or nil
            end,
            get_mob_by_target=function(token)
                if token == 'me' then return mobs[current.id] end
                return nil
            end,
            get_spells=function() return learned end,
            get_spell_recasts=function() return spell_recasts end,
            get_abilities=function()
                return {job_abilities={394}}
            end,
            get_ability_recasts=function() return ability_recasts end,
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
    assert(action('authorize', {
        GENERATION, '0', '2', PROFILE_ID, PROFILE_VERSION,
        SIGNATURE, 'Dolomedes', ROSTER, '1', '1',
    }))
    assert(action('probe', {GENERATION, '0', '2'}))
    local result = {
        adapter=adapter, state=adapter._test_state, action=action,
        current=current, party=party, mobs=mobs, inputs=inputs,
        commands=commands, env=env, learned=learned,
        spell_recasts=spell_recasts, ability_recasts=ability_recasts,
    }
    function result:set_hpp(member_name, hpp)
        for slot=0,5 do
            local member = party['p'..tostring(slot)]
            if member and member.name == member_name then
                member.hpp = hpp
                if member_name == current.name then current.hpp = hpp end
                return
            end
        end
        error('unknown party member '..tostring(member_name))
    end
    function result:advance(seconds)
        now = now + seconds
        env.tickdelay = 0
    end
    return result
end

local function input_count(world_state, text)
    local total = 0
    for _, command in ipairs(world_state.inputs) do
        if command:find(text, 1, true) then total = total + 1 end
    end
    return total
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'healthy party consumed the PLD tick')
    w:set_hpp('Dolomedes', 65)
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'strict routine threshold fired at exactly 65 percent')
    w:set_hpp('Dolomedes', 64)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'routine lane did not choose Cure III on the exact lowest member')
    local before = #w.inputs
    w.env.moving = true
    assert(w.adapter.user_job_tick() == true and #w.inputs == before,
        'pending lease did not reserve the callback ahead of movement')
    w.env.moving = false
    w.env.midaction = function() return true end
    assert(w.adapter.user_job_tick() == true and #w.inputs == before,
        'pending lease did not reserve the callback ahead of midaction')
    w.env.midaction = function() return false end
    w.adapter.job_aftercast({id=999,english='Unrelated',interrupted=false})
    assert(w.state.pld_pending ~= nil,
        'unrelated aftercast released the cure lease')
    w.adapter.job_aftercast({id=3,english='Cure III',target={id=1003},interrupted=false})
    assert(w.state.pld_pending ~= nil,
        'same-name manual cure on another member released the automatic lease')
    w.adapter.job_aftercast({id=3,english='Cure III',target={id=1002},interrupted=false})
    assert(w.state.pld_pending == nil and w.state.pld_cures == 1)
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 69)
    w:set_hpp('Kickpuncher', 69)
    assert(w.adapter.user_job_tick() == false,
        'two members below 70 incorrectly triggered the cluster lane')
    w:set_hpp('Barneystinson', 70)
    assert(w.adapter.user_job_tick() == false,
        'exactly 70 percent counted inside the strict cluster threshold')
    w:set_hpp('Barneystinson', 69)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'three-member cluster did not use Cure III on the lowest exact member')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {mpp=30})
    w:set_hpp('Dolomedes', 55)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'exactly 55 percent entered emergency or the 30-percent MP boundary held')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {mpp=29})
    w:set_hpp('Dolomedes', 64)
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'routine cure ignored the 30-percent MP floor')
    w:set_hpp('Dolomedes', 54)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure IV" <p1>',
        'emergency lane did not bypass the routine MP floor with Cure IV')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {
        learned={[4]=false},
    })
    w:set_hpp('Dolomedes', 54)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'emergency Cure IV did not fall back safely')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {mp=60})
    w:set_hpp('Dolomedes', 54)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'emergency Cure IV did not fall back when raw MP was insufficient')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Tackleberry', 64)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <me>',
        'self-lowest cure did not retain the safe local party-slot token')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 20)
    w.mobs.Dolomedes = nil
    w.party.p1.mob.distance = 25^2
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'out-of-range injury triggered an automatic cure')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 69)
    w:set_hpp('Kickpuncher', 69)
    w:set_hpp('Barneystinson', 0)
    w:set_hpp('Achoo', 69)
    w.party.p5.mob.distance = 25^2
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'dead or out-of-range members contributed to the cluster count')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {majesty=false})
    w:set_hpp('Dolomedes', 64)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ja "Majesty" <me>',
        'routine injury did not request Majesty before Cure III')
    w.adapter.job_aftercast({id=394,recast_id=150,english='Majesty',
        interrupted=false})
    w.env.buffactive.Majesty = true
    w:advance(0.6)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure III" <p1>',
        'Cure III did not follow confirmed Majesty')
end

do
    local w = sustain_world('Tackleberry', 'PLD', {
        majesty=false, majesty_recast=30,
    })
    w:set_hpp('Dolomedes', 54)
    assert(w.adapter.user_job_tick() == true)
    assert(w.inputs[#w.inputs] == '/ma "Cure IV" <p1>',
        'unavailable Majesty suppressed the emergency fail-soft cure')
    assert(input_count(w, 'Majesty') == 0)
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 20)
    w.env.player.status = 0
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'idle Tackle issued a cure before the next Flash opener established combat')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 64)
    assert(w.adapter.user_job_tick() == true and w.state.pld_pending ~= nil)
    assert(w.action('suspend', {GENERATION, '0', '2', '1'}))
    assert(w.state.pld_pending == nil,
        'maintenance suspension retained an in-flight sustain lease')
    w.adapter.job_aftercast({id=3,english='Cure III',target={id=1002},
        interrupted=false})
    assert(w.state.pld_cures == 0,
        'late aftercast revived a sustain action after suspension')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 64)
    assert(w.adapter.user_job_tick() == true and w.state.pld_pending ~= nil)
    assert(w.adapter.deactivate('profile-replaced'))
    assert(w.state.pld_pending == nil and w.state.active == false,
        'profile replacement retained the sustain lease or authority')
    w.adapter.job_aftercast({id=3,english='Cure III',target={id=1002},
        interrupted=false})
    assert(w.state.pld_cures == 0,
        'late aftercast revived sustain after profile replacement')
end

do
    local w = sustain_world('Tackleberry', 'PLD')
    w:set_hpp('Dolomedes', 20)
    assert(w.action('opener-arm', {'9001', GENERATION, '0', '2'}))
    local before = #w.inputs
    assert(w.adapter.user_job_tick() == true and #w.inputs == before,
        'PLD healing ran inside the Flash opener reservation')
    assert(input_count(w, 'Flash') == 0,
        'profile-local sustain lane issued Flash')
end

do
    local w = sustain_world('Achoo', 'GEO')
    w:set_hpp('Dolomedes', 20)
    assert(w.adapter.user_job_tick() == false and #w.inputs == 0,
        'non-Tackle client acquired the PLD sustain lane')
    assert(w.adapter.filter_pretarget({english='Cure III'}, nil, {}) == false)
    assert(w.adapter.filter_precast({english='Cure III'}, nil, {}) == false,
        'manual action filtering was introduced')
end

print('PartyTactics Locus Signet protocol-2 v1.5 sustain adapter tests passed.')
