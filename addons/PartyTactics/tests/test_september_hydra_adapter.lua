-- Behavioral boundary tests for the isolated Alluttu GearSwap adapter.

local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1] or
    (test_dir..'/../gearswap/adapters/'
        ..'ambuscade-2026-09-v2-hydra-alluttu/1.0.0.lua')

local function shallow(value)
    local out = {}
    for key, entry in pairs(value) do out[key] = entry end
    return out
end

local function new_world(job, options)
    options = options or {}
    local clock = 100
    local input, commands, chats = {}, {}, {}
    local equip_calls = 0
    local initial_buffs
    if options.buffs ~= nil then
        initial_buffs = options.buffs
    elseif job == 'GEO' then
        initial_buffs = {549}
    elseif job == 'BRD' then
        initial_buffs = {214,198,199}
    elseif job == 'COR' or job == 'PLD' or job == 'DNC' then
        initial_buffs = {251}
    else
        initial_buffs = {}
    end
    local local_player = {
        id=1001, name='Tester', main_job=job, status='Engaged',
        hpp=100, mpp=100, hp=3000, mp=1000, tp=3000,
        buffs=initial_buffs,
    }
    local target = {
        id=17990001, index=options.index == nil and 411 or options.index,
        name=options.name or 'Alluttu',
        claim_id=options.unclaimed and 0 or options.foreign and 999999
            or local_player.id,
        spawn_type=16, valid_target=true, hpp=100,
        distance=4^2, model_size=1.5,
    }
    local party = {
        p0={name='Tester', hpp=100, mob={id=1001}},
        p1={name='One', hpp=100, mob={id=1002}},
        p2={name='Two', hpp=100, mob={id=1003}},
        p3={name='Three', hpp=100, mob={id=1004}},
        p4={name='Four', hpp=100, mob={id=1005}},
        p5={name='Five', hpp=100, mob={id=1006}},
    }
    local abilities = {
        weapon_skills={25,42,221},
        job_abilities={35,46,48,202,207,255,332},
    }
    local spells = {
        [88]=true, [112]=true, [167]=true, [397]=true,
        [476]=true, [818]=true,
    }
    local spell_recasts = {
        [88]=0, [112]=0, [167]=0, [397]=0, [476]=0, [818]=0,
    }
    local ability_recasts = {
        [5]=0, [73]=0, [75]=0, [80]=0, [220]=0, [221]=0,
        [254]=0,
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.PARTYTACTICS_HYDRA_TEST_MODE = true
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = local_player
    env.buffactive = {}
    env.pet = {isvalid=true}
    env.moving = false
    env.tickdelay = 0
    env.next_cast = 0
    env.latency = 1
    env.spell_latency = 1
    env.midaction = function() return env._busy == true end
    env.silent_check_disable = function() return env._disabled == true end
    env.silent_check_amnesia = function() return env._amnesia == true end
    env.silent_can_use = function() return env._spell_blocked ~= true end
    env.equip = function() equip_calls = equip_calls + 1 end
    env.add_to_chat = function(color, message)
        chats[#chats + 1] = {color=color, message=message}
    end
    env.res = {
        items={[6343]={id=6343, en='Grape Daifuku'}},
        weapon_skills={
            [25]={id=25, en='Evisceration'},
            [42]={id=42, en='Savage Blade'},
            [221]={id=221, en='Last Stand'},
        },
        job_abilities={
            [35]={id=35, en='Provoke', recast_id=5},
            [46]={id=46, en='Shield Bash', recast_id=73},
            [48]={id=48, en='Sentinel', recast_id=75},
            [202]={id=202, en='Box Step', recast_id=220},
            [207]={id=207, en='Violent Flourish', recast_id=221},
            [255]={id=255, en='Divine Emblem', recast_id=80},
            [332]={id=332, en='Clarion Call', recast_id=254},
        },
        spells={
            [88]={id=88, en='Barparalyzra', recast_id=88, mp_cost=22},
            [112]={id=112, en='Flash', recast_id=112, mp_cost=25},
            [167]={id=167, en='Thunder IV', recast_id=167, mp_cost=195},
            [397]={id=397, en='Valor Minuet IV', recast_id=397,
                mp_cost=0},
            [476]={id=476, en='Crusade', recast_id=476, mp_cost=18},
            [818]={id=818, en='Geo-Frailty', recast_id=818, mp_cost=294},
        },
    }
    env.windower = {
        chat={input=function(command) input[#input + 1] = command end},
        send_command=function(command) commands[#commands + 1] = command end,
        ffxi={
            get_player=function()
                return {
                    id=local_player.id, main_job=local_player.main_job,
                    status=local_player.status, buffs=local_player.buffs,
                    vitals={hpp=local_player.hpp},
                }
            end,
            get_info=function()
                return {logged_in=env._logged_out ~= true,
                    zone=env._zone or options.zone or 287}
            end,
            get_mob_by_id=function(id)
                if env._hide_target or tonumber(id) ~= target.id then return nil end
                return shallow(target)
            end,
            get_party=function() return party end,
            get_abilities=function() return abilities end,
            get_spells=function() return spells end,
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
    assert(adapter.id == 'ambuscade-2026-09-v2-hydra-alluttu')
    assert(adapter.version == '1.0.0')
    assert(adapter.controller == 'hydra' and adapter.protocol == 1)
    assert(adapter.activate() == true)
    local generation = '1700000000-1001-1'
    assert(adapter.handle_action('hydra', 'probe',
        {generation, '0', '1'}) == true)
    while #commands > 0 do table.remove(commands) end

    local world = {
        env=env, adapter=adapter, queue=adapter._test_queue,
        prepared=adapter._test_prepared,
        player=local_player, target=target, party=party,
        input=input, commands=commands, chats=chats,
        abilities=abilities, spells=spells,
        spell_recasts=spell_recasts, ability_recasts=ability_recasts,
        generation=generation, epoch=0,
    }
    function world:advance(seconds) clock = clock + seconds end
    function world:command(semantic, id, token)
        local args = {tostring(id or self.target.id), self.generation,
            tostring(self.epoch)}
        if semantic ~= 'cancel' then args[4] = token or 'test-token' end
        return self.adapter.handle_action('hydra', semantic, args)
    end
    function world:raw(controller, semantic, args)
        return self.adapter.handle_action(controller, semantic, args)
    end
    function world:fire(method, ...)
        return assert(self.adapter[method])(...)
    end
    function world:result(category, id, target_id, message)
        self.adapter.action_event({
            actor_id=self.player.id, category=category, param=id,
            targets={{id=target_id or self.target.id,
                actions={{param=1, message=message or 1}}}},
        })
    end
    function world:party_result(category, id, count, message)
        local targets = {}
        for index = 0, (count or 6) - 1 do
            local member = assert(self.party['p'..tostring(index)])
            targets[#targets + 1] = {
                id=member.mob.id,
                actions={{param=1, message=message or 1}},
            }
        end
        self.adapter.action_event({
            actor_id=self.player.id, category=category, param=id,
            targets=targets,
        })
    end
    function world:equip_count() return equip_calls end
    return world
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name, callback=callback}
end

test('capability authority is exact and revocable', function()
    local w = new_world('COR')
    assert(w:raw('hydra', 'probe',
        {'bad;generation','0','1'}) == false)
    assert(w:raw('hydra', 'probe',
        {'1700000000-1001-2','-1','1'}) == false)
    assert(w:raw('hydra', 'probe',
        {'1700000000-1001-2','0','2'}) == false)
    assert(w:raw('other', 'close', {}) == false)
    w.adapter.deactivate('retired')
    assert(#w.commands == 1 and w.commands[1]:find(
        '__controller_lost hydra', 1, true))
    assert(w:command('close') == false)
end)

test('wrong mob, foreign claim, wrong zone, and subjects fail closed', function()
    local wrong = new_world('COR', {name='Alluttu Prime'})
    assert(wrong:command('close') == false and #wrong.input == 0)
    local foreign = new_world('COR', {foreign=true})
    assert(foreign:command('close') == false and #foreign.input == 0)
    local zone = new_world('COR', {zone=130})
    assert(zone:command('close') == false and #zone.input == 0)
    local subject = new_world('COR')
    assert(subject:raw('hydra', 'close', {
        tostring(subject.target.id), subject.generation, '0',
        'token', tostring(subject.target.id),
    }) == false)
    assert(#subject.input == 0)
    for _, index in ipairs({-1, 1.5, 65536}) do
        local malformed = new_world('COR', {index=index})
        assert(malformed:command('close') == false)
        assert(#malformed.input == 0,
            'malformed entity index was dispatched: '..tostring(index))
    end
end)

test('both Ambuscade instance zones are accepted', function()
    for _, zone in ipairs({183,287}) do
        local w = new_world('COR', {zone=zone})
        assert(w:command('close') == true)
        assert(w.input[1] == '/ws "Last Stand" 17990001')
    end
end)

test('unclaimed authority permits only pre-pull semantics', function()
    local pld = new_world('PLD', {unclaimed=true})
    assert(pld:command('pull-flash') == true)
    assert(pld.input[1] == '/ma "Flash" 17990001')
    local routine = new_world('PLD', {unclaimed=true})
    assert(routine:command('flash') == false and #routine.input == 0)
    local cor = new_world('COR', {unclaimed=true})
    assert(cor:command('close') == false and #cor.input == 0)
    local food = new_world('DNC', {unclaimed=true, buffs={}})
    assert(food:command('food') == true)
    assert(food.input[1] == '/item "Grape Daifuku" <me>')
end)

test('food is self-only and never consumed while Food is active', function()
    local fed = new_world('COR', {buffs={251}})
    assert(fed:command('food') == true)
    assert(fed.queue.request == nil and #fed.input == 0)
    local hungry = new_world('COR', {buffs={}})
    assert(hungry:command('food') == true)
    local request = assert(hungry.queue.request)
    assert(request.result_id == hungry.player.id)
    assert(hungry.input[1] == '/item "Grape Daifuku" <me>')
    hungry:result(5, 6343, hungry.target.id)
    assert(hungry.queue.request ~= nil,
        'enemy-targeted item packet must not complete self food')
    hungry:result(5, 6343, hungry.player.id)
    assert(hungry.queue.request == nil)
end)

test('physical offense requires Food and expiry is self-healed by food priority', function()
    local w = new_world('COR', {buffs={}})
    assert(w:command('close') == true)
    assert(#w.input == 0 and w.queue.request.semantic == 'close')
    assert(w:command('food') == true)
    assert(w.input[1] == '/item "Grape Daifuku" <me>')
    w:result(5, 6343, w.player.id)
    w.player.buffs[#w.player.buffs + 1] = 251
    w:advance(1.6)
    assert(w:command('close') == true)
    assert(w.input[2] == '/ws "Last Stand" 17990001')
    w:result(3, 221, w.target.id)

    w:advance(1.6)
    w.player.buffs = {}
    assert(w:command('close') == true and #w.input == 2,
        'offense dispatched after Food expired')
    assert(w:command('food') == true)
    assert(w.input[3] == '/item "Grape Daifuku" <me>',
        'food heartbeat could not preempt blocked offense after expiry')
end)

test('a movement-blocked food reservation expires and accepts a late retry', function()
    local w = new_world('DNC', {buffs={}})
    w.env.moving = true
    assert(w:command('food') == true)
    assert(w.queue.request ~= nil and #w.input == 0)
    w:advance(13)
    assert(w.adapter.pre_tick() == false)
    assert(w.queue.request == nil)
    w.env.moving = false
    assert(w:command('food') == true)
    assert(w.input[1] == '/item "Grape Daifuku" <me>')
end)

test('entity index reuse and claim loss clear a reservation', function()
    local reused = new_world('DNC')
    reused.player.tp = 500
    assert(reused:command('lead') == true)
    assert(reused.queue.request and #reused.input == 0)
    reused.target.index = reused.target.index + 1
    assert(reused.adapter.pre_tick() == false)
    assert(reused.queue.request == nil)

    local lost = new_world('DNC')
    lost.player.tp = 500
    lost:command('lead')
    lost.target.claim_id = 0
    lost.adapter.pre_tick()
    assert(lost.queue.request == nil)
end)

test('semantic queues are job-scoped and deduplicated', function()
    local dnc = new_world('DNC')
    assert(dnc:command('middle') == false)
    assert(dnc:command('lead') == true)
    local request = assert(dnc.queue.request)
    local expires = request.expires
    dnc:advance(1)
    assert(dnc:command('lead') == true)
    assert(dnc.queue.request == request and request.expires == expires)
    assert(#dnc.input == 1)

    local pld = new_world('PLD')
    pld.player.tp = 500
    pld:command('middle')
    assert(pld.queue.request.semantic == 'middle')
    pld:command('shield-bash')
    assert(pld.queue.request.semantic == 'shield-bash')
end)

test('terminal failures retry finitely and success is packet-confirmed', function()
    local w = new_world('PLD')
    w:command('middle')
    assert(#w.input == 1)
    for attempt = 1, 2 do
        w:result(3, 42, w.target.id, 78)
        assert(w.queue.request ~= nil)
        w:advance(1.6)
        w.adapter.prerender()
        assert(#w.input == attempt + 1)
    end
    w:result(3, 42, w.target.id, 78)
    assert(w.queue.request == nil and #w.input == 3)

    local success = new_world('PLD')
    success:command('middle')
    success:result(3, 42, success.player.id, 1)
    assert(success.queue.request ~= nil)
    success:result(3, 42, success.target.id, 1)
    assert(success.queue.request == nil and success.queue.completed == 1)
end)

test('range TP recast health and busy states remain bounded', function()
    local w = new_world('DNC')
    w.player.tp = 500
    w:command('lead')
    assert(#w.input == 0 and w.adapter.pre_tick() == false)
    w.player.tp = 3000
    w.target.distance = 12^2
    assert(w.adapter.pre_tick() == false and #w.input == 0)
    w.target.distance = 4^2
    w.party.p2.hpp = 84
    assert(w.adapter.pre_tick() == false and #w.input == 0)
    w.party.p2.hpp = 85
    w.env._busy = true
    assert(w.adapter.pre_tick() == true and #w.input == 0)
    w.env._busy = false
    w.adapter.prerender()
    assert(#w.input == 1)
end)

test('fight action reservations yield to cures and status recovery', function()
    local rdm = new_world('RDM')
    rdm.target.distance = 15^2
    rdm:command('burst')
    assert(#rdm.input == 1)
    rdm.party.p2.hpp = 84
    assert(rdm.adapter.filter_precast({id=5, action_type='Magic',
        english='Cure IV', target={id=1002, hpp=90}}, nil, {}) == false,
        'reserved burst suppressed native healing below 85 percent')
    rdm.party.p2.hpp = 85
    assert(rdm.adapter.filter_precast({id=5, action_type='Magic',
        english='Cure IV', target={id=1002, hpp=90}}, nil, {}) == true,
        'health threshold did not release exactly at 85 percent')
    assert(rdm.adapter.filter_precast({id=20, action_type='Magic',
        english='Cursna', target={id=1002, hpp=100}}, nil, {}) == false)
    assert(rdm.adapter.filter_precast({id=999, action_type='Magic',
        english='Dia III', target={id=rdm.target.id}}, nil, {}) == true)

    local dnc = new_world('DNC')
    dnc:command('lead')
    assert(dnc.adapter.filter_precast({id=999, action_type='Ability',
        english='Curing Waltz V', target={id=1002}}, nil, {}) == false)
    assert(dnc.adapter.filter_precast({id=998, action_type='Ability',
        english='Rudra\'s Storm', target={id=dnc.target.id}}, nil, {}) == true)

    local cor = new_world('COR')
    cor:command('close')
    cor.party.p2.hpp = 84
    assert(cor.adapter.filter_precast({id=997, action_type='Ability',
        english='Curing Waltz III', target={id=1002}}, nil, {}) == false,
        'an in-flight COR/DNC closer suppressed its native Waltz')
end)

test('mechanic stuns bypass healing preference but retain hard safety gates', function()
    local dnc = new_world('DNC')
    dnc.party.p2.hpp = 20
    dnc.env.buffactive.Curse = true
    assert(dnc:command('stun') == true)
    assert(dnc.input[1] == '/ja "Violent Flourish" '..tostring(dnc.target.id),
        'low party HP or removable status blocked the Nerve Gas reaction')

    local pld = new_world('PLD')
    pld.party.p2.hpp = 20
    pld.env.buffactive.Paralysis = true
    assert(pld:command('shield-bash') == true)
    assert(pld.input[1] == '/ja "Shield Bash" '..tostring(pld.target.id),
        'low party HP or removable status blocked the fallback reaction')

    local moving = new_world('DNC')
    moving.party.p2.hpp = 20
    moving.env.moving = true
    assert(moving:command('stun') == true and #moving.input == 0)

    local disabled = new_world('DNC')
    disabled.party.p2.hpp = 20
    disabled.env._disabled = true
    assert(disabled:command('stun') == true and #disabled.input == 0)

    local amnesia = new_world('PLD')
    amnesia.party.p2.hpp = 20
    amnesia.env._amnesia = true
    assert(amnesia:command('shield-bash') == true and #amnesia.input == 0)

    local recast = new_world('PLD')
    recast.party.p2.hpp = 20
    recast.ability_recasts[73] = 30
    assert(recast:command('shield-bash') == true and #recast.input == 0)

    local far = new_world('DNC')
    far.party.p2.hpp = 20
    far.target.distance = 12^2
    assert(far:command('stun') == true and #far.input == 0)

    local dead = new_world('DNC')
    dead.player.hpp = 0
    assert(dead:command('stun') == true and #dead.input == 0)
end)

test('Clarion fourth song is opportunistic and equipment-inert', function()
    local cooling = new_world('BRD')
    cooling.ability_recasts[254] = 120
    assert(cooling:command('clarion') == true)
    assert(#cooling.input == 0 and cooling.adapter.pre_tick() == false)
    assert(cooling:equip_count() == 0)

    local ready = new_world('BRD', {buffs={214,198,199,499}})
    assert(ready:command('fourth-song') == true)
    assert(ready.input[1] == '/ma "Valor Minuet IV" <me>')
    assert(ready:equip_count() == 0,
        'adapter attempted to own Barney instrument or action gear')
    ready:party_result(4, 397, 1)
    assert(ready.queue.request ~= nil and not ready.prepared.fourth_song,
        'self-only song packet falsely satisfied party coverage')
    ready:advance(1.6)
    ready.adapter.prerender()
    assert(#ready.input == 2)
    ready:party_result(4, 397, 6)
    assert(ready.queue.request == nil and ready.prepared.fourth_song)
    assert(ready:command('fourth-song') == true)
    assert(#ready.input == 2,
        'completed fixed fourth song was cast more than once')
    assert(ready:command('cancel') == true)
    assert(not ready.prepared.fourth_song,
        'encounter cancellation did not retire fourth-song state')
    ready:advance(1.6)
    assert(ready:command('fourth-song') == true)
    assert(#ready.input == 3,
        'same-generation second encounter inherited fourth-song completion')
    ready:party_result(4, 397, 6)
    assert(ready.prepared.fourth_song)
end)

test('Barparalyzra AoE omissions retry finitely and end with an advisory', function()
    local w = new_world('BRD')
    assert(w:command('barparalyzra') == true and #w.input == 1)
    for attempt = 1, 2 do
        w:party_result(4, 88, 5)
        assert(w.queue.request ~= nil)
        if attempt == 1 then
            w.player.buffs[#w.player.buffs + 1] = 108
        end
        w:advance(1.6)
        w.adapter.prerender()
        assert(#w.input == attempt + 1)
    end
    w:party_result(4, 88, 5)
    assert(w.queue.request == nil and #w.input == 3)
    local advisory = false
    for _, entry in ipairs(w.chats) do
        if entry.message:find('AoE result missed', 1, true) then
            advisory = true
        end
    end
    assert(advisory, 'bounded AoE coverage failure emitted no advisory')
end)

test('GEO setup keeps native Full Circle available only in flight', function()
    local geo = new_world('GEO')
    geo.target.distance = 15^2
    geo:command('setup')
    assert(geo.input[1] == '/ma "Geo-Frailty" 17990001')
    assert(geo.adapter.filter_precast({id=245, action_type='Ability',
        english='Full Circle', target={id=geo.player.id}}, nil, {}) == false)
    assert(geo:equip_count() == 0)

    local nuke = new_world('GEO')
    nuke.target.distance = 15^2
    nuke:command('nuke')
    assert(nuke.adapter.filter_precast({id=245, action_type='Ability',
        english='Full Circle', target={id=nuke.player.id}}, nil, {}) == true)
end)

test('cancel death zone and deactivation clear all work', function()
    local w = new_world('PLD')
    w.player.tp = 500
    w:command('middle')
    assert(w:raw('hydra', 'cancel', {
        tostring(w.target.id), w.generation, '0', '-',
    }) == true)
    assert(w.queue.request == nil)
    w:command('middle')
    w.adapter.status_change(2)
    assert(w.queue.request == nil)
    w.player.status = 'Engaged'
    w:command('middle')
    w.adapter.zone_change(183)
    assert(w.queue.request == nil)
    w:command('middle')
    w.adapter.deactivate('profile off')
    assert(w.queue.request == nil)
end)

test('adapter surface remains instrument and equipment inert', function()
    for _, job in ipairs({'COR','PLD','DNC','BRD','RDM','GEO'}) do
        local w = new_world(job)
        assert(w:equip_count() == 0)
        assert(rawget(w.env, 'PartyTacticsHydraQueue') == nil)
        assert(type(w.adapter.handle_action) == 'function')
        assert(type(w.adapter.action_event) == 'function')
    end
end)

local passed = 0
for _, entry in ipairs(tests) do
    local ok, failure = pcall(entry.callback)
    if not ok then
        error(('FAIL %s: %s'):format(entry.name, tostring(failure)), 0)
    end
    passed = passed + 1
end
assert(passed == 18)
print(('PASS PartyTactics September Hydra adapter: %d cases'):format(passed))
