-- Cooperative boundary tests for the direct-Rancibus GearSwap adapter.

local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1] or
    (test_dir..'/../gearswap/adapters/'
        ..'vagary-direct-rancibus/1.1.0.lua')

local function shallow(value)
    local out = {}
    for key, entry in pairs(value) do out[key] = entry end
    return out
end

local function new_world(job, options)
    options = options or {}
    local clock = 100
    local inputs, commands = {}, {}
    local identities = {
        COR={id=1001,name='Dolomedes'}, PLD={id=1002,name='Tackleberry'},
        DNC={id=1003,name='Kickpuncher'}, BRD={id=1004,name='Barneystinson'},
        RDM={id=1005,name='Smalls'}, GEO={id=1006,name='Achoo'},
    }
    local identity = assert(identities[job])
    local player = {id=identity.id, name=identity.name, main_job=job,
        status='Engaged', mp=1000, tp=3000}
    local target = {id=17990001, index=411, name='Rancibus',
        claim_id=player.id, spawn_type=16, valid_target=true,
        distance=16, model_size=1.5}
    local party = {}
    for index, entry in ipairs({
        {'Dolomedes',1001},{'Tackleberry',1002},{'Kickpuncher',1003},
        {'Barneystinson',1004},{'Smalls',1005},{'Achoo',1006},
    }) do
        party['p'..tostring(index - 1)] = {
            name=entry[1], mob={id=entry[2]},
        }
    end
    local spell_recasts = {[25]=0,[71]=0,[79]=0,[80]=0,[90]=0,
        [112]=0,[476]=0,[818]=0,[884]=0}
    local ability_recasts = {[5]=0,[73]=0,[75]=0,[77]=0,
        [220]=0,[221]=0,[223]=0}
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.PARTYTACTICS_RANCIBUS_TEST_MODE = true
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = player
    env.moving = false
    env.tickdelay = 0
    env.next_cast = 0
    env.latency = 1
    env.spell_latency = 1
    env.midaction = function() return false end
    env.silent_check_disable = function() return false end
    env.silent_check_amnesia = function() return false end
    env.silent_can_use = function() return true end
    env.add_to_chat = function() end
    env.res = {
        weapon_skills={
            [25]={id=25,en='Evisceration'},
            [42]={id=42,en='Savage Blade'},
            [221]={id=221,en='Last Stand'},
        },
        job_abilities={
            [35]={id=35,en='Provoke',recast_id=5},
            [46]={id=46,en='Shield Bash',recast_id=73},
            [48]={id=48,en='Sentinel',recast_id=75},
            [92]={id=92,en='Rampart',recast_id=77},
            [202]={id=202,en='Box Step',recast_id=220},
            [207]={id=207,en='Violent Flourish',recast_id=221},
            [239]={id=239,en='No Foot Rise',recast_id=223},
        },
        spells={
            [25]={id=25,en='Dia III',recast_id=25,mp_cost=45},
            [71]={id=71,en='Barwatera',recast_id=71,mp_cost=12},
            [79]={id=79,en='Slow II',recast_id=79,mp_cost=45},
            [80]={id=80,en='Paralyze II',recast_id=80,mp_cost=36},
            [90]={id=90,en='Barsilencera',recast_id=90,mp_cost=30},
            [112]={id=112,en='Flash',recast_id=112,mp_cost=25},
            [476]={id=476,en='Crusade',recast_id=476,mp_cost=18},
            [818]={id=818,en='Geo-Frailty',recast_id=818,mp_cost=294},
            [884]={id=884,en='Addle II',recast_id=884,mp_cost=63},
        },
    }
    env.windower = {
        chat={input=function(command) inputs[#inputs + 1] = command end},
        send_command=function(command) commands[#commands + 1] = command end,
        ffxi={
            get_player=function() return shallow(player) end,
            get_info=function() return {logged_in=true,zone=277} end,
            get_mob_by_id=function(id)
                return tonumber(id) == target.id and shallow(target) or nil
            end,
            get_mob_by_target=function(token)
                return token == 'bt' and shallow(target) or nil
            end,
            get_party=function() return party end,
            get_abilities=function()
                return {weapon_skills={25,42,221},
                    job_abilities={35,46,48,92,202,207,239}}
            end,
            get_spells=function()
                return {[25]=true,[71]=true,[79]=true,[80]=true,
                    [90]=true,[112]=true,[476]=true,[818]=true,[884]=true}
            end,
            get_spell_recasts=function() return spell_recasts end,
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
    assert(adapter.activate() == true)
    local world = {env=env, adapter=adapter, state=adapter._test_state,
        player=player, target=target, inputs=inputs, commands=commands,
        spell_recasts=spell_recasts,
        generation='1700000000-1001-1', epoch='0'}
    function world:advance(seconds) clock = clock + seconds end
    function world:command(semantic, token)
        return self.adapter.handle_action('rancibus', semantic,
            {tostring(self.target.id), self.generation, self.epoch,
                token or 'lane-1'})
    end
    return world
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name, callback=callback}
end

test('new adapter is cooperative and installs no input filters', function()
    local w = new_world('COR')
    assert(w.adapter.id == 'vagary-direct-rancibus')
    assert(w.adapter.version == '1.1.0')
    assert(w.adapter.filter_pretarget == nil)
    assert(w.adapter.filter_precast == nil)
    assert(w.adapter.action_event == nil)
    assert(w.adapter.pre_tick() == false)
    assert(w.adapter.user_job_tick() == false)
end)

test('first action works without a probe or readiness acknowledgement', function()
    local w = new_world('COR')
    local accepted = w:command('shoot')
    assert(accepted == true)
    assert(#w.inputs == 1, w.adapter.status())
    assert(w.inputs[1] == '/ra '..tostring(w.target.id))
    assert(w.state.accepted == 1 and w.state.dispatched == 1)
end)

test('a blocked lane cannot suppress another ready lane', function()
    local w = new_world('PLD')
    w.spell_recasts[112] = 30
    assert(w:command('flash', 'flash-lane') == true)
    assert(#w.inputs == 0)
    assert(w:command('middle', 'ws-lane') == true)
    w:advance(0.11)
    assert(w.adapter.pre_tick() == false)
    assert(#w.inputs == 1)
    assert(w.inputs[1] == '/ws "Savage Blade" '..tostring(w.target.id))
    assert(w.state.pending.flash ~= nil)
end)

test('cancel and deactivate clear only automated requests', function()
    local w = new_world('PLD')
    w.spell_recasts[112] = 30
    assert(w:command('flash') == true)
    assert(w.state.pending.flash ~= nil)
    assert(w.adapter.handle_action('rancibus', 'cancel',
        {tostring(w.target.id), w.generation, w.epoch}) == true)
    assert(next(w.state.pending) == nil)
    assert(w.adapter.deactivate('operator stop') == nil)
    assert(next(w.state.pending) == nil)
    assert(w.adapter.filter_pretarget == nil
        and w.adapter.filter_precast == nil)
end)

test('all six jobs accept their independent profile lane', function()
    local cases = {
        {'COR','shoot'}, {'PLD','middle'}, {'DNC','lead'},
        {'BRD','barwatera-prepare'}, {'RDM','dia3'},
        {'GEO','geo-frailty'},
    }
    for _, case in ipairs(cases) do
        local w = new_world(case[1])
        assert(w:command(case[2], case[1]:lower()) == true)
        assert(w.state.accepted == 1)
    end
end)

for _, entry in ipairs(tests) do
    local ok, failure = pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end

io.write(('Rancibus adapter tests passed: %d\n'):format(#tests))
