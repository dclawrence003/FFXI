-- Cooperative boundary tests for the Sortie C Magic Burst adapter.

local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1] or
    (test_dir..'/../gearswap/adapters/'
        ..'sortie-objective-c-magic-burst-v1/1.0.0.lua')

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
    local player = {id=identity.id,name=identity.name,main_job=job,
        status='Engaged',mp=1000,tp=3000}
    local target = {id=17990001,index=411,
        name=options.name or 'Cachaemic Ghost',claim_id=player.id,
        spawn_type=16,valid_target=true,hpp=100,distance=4,model_size=1.5}
    local party = {}
    for index, entry in ipairs({
        {'Dolomedes',1001},{'Tackleberry',1002},{'Kickpuncher',1003},
        {'Barneystinson',1004},{'Smalls',1005},{'Achoo',1006},
    }) do
        party['p'..tostring(index - 1)] = {
            name=entry[1],mob={id=entry[2]},
        }
    end
    local spell_recasts = {[164]=0}
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.PARTYTACTICS_SORTIE_C_MB_TEST_MODE = true
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = player
    env.moving = false
    env.tickdelay = 0
    env.next_cast = 0
    env.latency = 1
    env.spell_latency = 1
    env.midaction = function() return false end
    env.silent_check_disable = function() return false end
    env.silent_can_use = function() return true end
    env.res = {
        weapon_skills={
            [25]={id=25,en='Evisceration'},
            [42]={id=42,en='Savage Blade'},
        },
        spells={
            [164]={id=164,en='Thunder',recast_id=164,mp_cost=25},
        },
    }
    env.windower = {
        chat={input=function(command) inputs[#inputs + 1] = command end},
        send_command=function(command) commands[#commands + 1] = command end,
        ffxi={
            get_player=function() return shallow(player) end,
            get_info=function()
                return {logged_in=true,zone=options.zone or 275}
            end,
            get_mob_by_id=function(id)
                return tonumber(id) == target.id and shallow(target) or nil
            end,
            get_mob_by_target=function(token)
                return token == 'bt' and shallow(target) or nil
            end,
            get_party=function() return party end,
            get_abilities=function()
                return {weapon_skills={25,42},job_abilities={}}
            end,
            get_spells=function() return {[164]=true} end,
            get_spell_recasts=function() return spell_recasts end,
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
    local world = {env=env,adapter=adapter,state=adapter._test_state,
        player=player,target=target,inputs=inputs,commands=commands,
        spell_recasts=spell_recasts,
        generation='1700000000-1001-1',epoch='0'}
    function world:advance(seconds) clock = clock + seconds end
    function world:command(semantic,token)
        return self.adapter.handle_action('sortie-c-mb',semantic,
            {tostring(self.target.id),self.generation,self.epoch,
                token or 'lane-1'})
    end
    return world
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name,callback=callback}
end

test('adapter is explicit pass-through infrastructure', function()
    local w = new_world('COR')
    assert(w.adapter.id == 'sortie-objective-c-magic-burst-v1')
    assert(w.adapter.version == '1.0.0')
    assert(w.adapter.controller == 'sortie-c-mb')
    assert(w.adapter.filter_pretarget() == false)
    assert(w.adapter.filter_precast() == false)
    assert(w.adapter.pre_tick() == false)
    assert(w.adapter.user_job_tick() == false)
end)

test('exact numeric WS dispatch works without readiness ACK', function()
    local w = new_world('DNC')
    assert(w:command('evisceration') == true)
    assert(#w.inputs == 1,w.adapter.status())
    assert(w.inputs[1] == '/ws "Evisceration" '..tostring(w.target.id))
end)

test('all six member lanes accept only their pinned action', function()
    local cases = {
        {'COR','savage-blade'}, {'PLD','savage-blade'},
        {'DNC','evisceration'}, {'BRD','savage-blade'},
        {'RDM','thunder'}, {'GEO','thunder'},
    }
    for _, case in ipairs(cases) do
        local w = new_world(case[1])
        assert(w:command(case[2],case[1]:lower()) == true)
        assert(w.state.accepted == 1 and w.state.dispatched == 1)
    end
end)

test('all three Sortie instance zone ids are accepted', function()
    for _, zone in ipairs({133,189,275}) do
        local w = new_world('RDM',{zone=zone})
        assert(w:command('thunder') == true)
        assert(#w.inputs == 1)
    end
end)

test('Bhoot, foreign names, invalid life, and outside zones are refused', function()
    for _, name in ipairs({'Cachaemic Bhoot','Demisang Warrior','Skomora'}) do
        local w = new_world('RDM',{name=name})
        assert(w:command('thunder') == false)
        assert(#w.inputs == 0)
    end
    local dead = new_world('RDM')
    dead.target.hpp = 0
    assert(dead:command('thunder') == false)
    local outside = new_world('RDM',{zone=267})
    assert(outside:command('thunder') == false)
end)

test('claim, range, learned resource, TP, and engagement are enforced', function()
    local unclaimed = new_world('RDM')
    unclaimed.target.claim_id = 0
    assert(unclaimed:command('thunder') == false)

    local range = new_world('RDM')
    range.target.distance = 900
    assert(range:command('thunder') == true)
    assert(#range.inputs == 0)

    local unknown = new_world('RDM')
    unknown.env.windower.ffxi.get_spells = function() return {} end
    assert(unknown:command('thunder') == true)
    assert(#unknown.inputs == 0)

    local tp = new_world('COR')
    tp.player.tp = 999
    assert(tp:command('savage-blade') == true)
    assert(#tp.inputs == 0)

    local disengaged = new_world('COR')
    disengaged.player.status = 'Idle'
    assert(disengaged:command('savage-blade') == true)
    assert(#disengaged.inputs == 0)
end)

test('spell MP, recast, movement, and midaction remain bounded blockers', function()
    local mp = new_world('GEO')
    mp.player.mp = 0
    assert(mp:command('thunder') == true)
    assert(#mp.inputs == 0)

    local recast = new_world('GEO')
    recast.spell_recasts[164] = 10
    assert(recast:command('thunder') == true)
    assert(#recast.inputs == 0)

    local moving = new_world('GEO')
    moving.env.moving = true
    assert(moving:command('thunder') == true)
    assert(#moving.inputs == 0)

    local busy = new_world('GEO')
    busy.env.midaction = function() return true end
    assert(busy:command('thunder') == true)
    assert(#busy.inputs == 0)
end)

test('blocked requests expire and cancel without touching manual input', function()
    local w = new_world('GEO')
    w.env.moving = true
    assert(w:command('thunder') == true)
    assert(w.state.pending.thunder ~= nil)
    assert(w.adapter.handle_action('sortie-c-mb','cancel',
        {tostring(w.target.id),w.generation,w.epoch}) == true)
    assert(next(w.state.pending) == nil)
    assert(w.adapter.filter_pretarget() == false)

    assert(w:command('thunder','retry') == true)
    w:advance(3.6)
    assert(w.adapter.pre_tick() == false)
    assert(next(w.state.pending) == nil)
    assert(w.state.expired == 1)
end)

for _, entry in ipairs(tests) do
    local ok, failure = pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end

io.write(('Sortie C Magic Burst adapter tests passed: %d\n'):format(#tests))
