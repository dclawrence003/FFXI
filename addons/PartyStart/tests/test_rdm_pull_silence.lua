-- Full-controller Lua 5.1 regression tests; no live client or packet writes.
local controller_path = arg and arg[1]
    or 'addons/PartyStart/gearswap/PartyStart_RDM.lua'
debug.setmetatable(0, {__index={sqrt=math.sqrt}})

local function new_client(profile)
    local c = {now=100, commands={}, logs={}, packets={}, callbacks={},
        selected=nil, busy=false, disabled=false,
        recasts={}, learned={}, spells={}, by_id={}, by_index={},
        info={logged_in=true, zone=38}}
    local env = setmetatable({}, {__index=_G})
    c.env = env
    env.os = setmetatable({clock=function() return c.now end}, {__index=os})
    env.player = {name='Smalls', id=1, index=1, mp=1000, max_mp=1000,
        mpp=100, hpp=100, in_combat=true, status='Idle'}
    c.leader = {name='Tackleberry', id=2, index=2, target_index=100,
        x=0, y=0, z=0, distance=0}
    c.self = {name='Smalls', id=1, index=1, x=0, y=0, z=0, distance=0}
    c.party = {p0={name='Smalls', hpp=100, mob=c.self},
        p1={name='Tackleberry', hpp=100, mob=c.leader}}
    function c.mob(id, index, distance)
        local mob = {id=id, index=index, name='Identical Enemy Name',
            spawn_type=16, valid_target=true, hpp=100, claim_id=2,
            x=distance, y=0, z=0, distance=distance*distance}
        c.by_id[id], c.by_index[index] = mob, mob
        return mob
    end
    c.enemy = c.mob(1000, 100, 18)
    c.other = c.mob(1001, 101, 18)
    function c.spell(id, name, cost)
        c.spells[name] = {id=id, en=name, mp_cost=cost, recast_id=id}
        c.learned[id] = true
    end
    c.spell(59, 'Silence', 16)
    for id, name in ipairs({'Cure', 'Cure II', 'Cure III', 'Cure IV'}) do
        c.spell(id, name, id*20)
    end
    env.res = {
        spells={with=function(_, key, name) return c.spells[name] end},
        buffs={}, action_messages={}, monster_abilities={},
        job_abilities={with=function() return nil end},
    }
    env.state = {AutoBuffMode={set=function() end}}
    env.buffactive = {Composure=true}
    env.moving, env.spell_latency, env.tickdelay = false, 0.5, 0
    env.midaction = function() return c.busy end
    env.silent_check_disable = function() return c.disabled end
    env.silent_can_use = function() return true end
    env.add_to_chat = function(_, message) c.logs[#c.logs+1] = message end
    env.require = function(name)
        error('Pull Silence must not depend on packet selection: '..name)
    end
    env.windower = {
        raw_register_event=function(name, callback) c.callbacks[name] = callback end,
        chat={input=function(command)
            local target_id = tonumber(command:match('^/ma "Silence" (%d+)$'))
            c.commands[#c.commands+1] = {command=command, target=target_id,
                selected=c.selected and c.selected.id}
        end},
        ffxi={
            get_info=function() return c.info end,
            get_player=function() return {id=1, index=1} end,
            get_party=function() return c.party end,
            get_spells=function() return c.learned end,
            get_spell_recasts=function() return c.recasts end,
            get_ability_recasts=function() return {[49]=0, [50]=0} end,
            get_abilities=function() return {job_abilities={}} end,
            get_mob_by_name=function(name)
                if name == 'Tackleberry' then return c.leader end
                if name == 'Smalls' then return c.self end
                error('Enemy names must not be used for targeting/classification: '..tostring(name))
            end,
            get_mob_by_id=function(id) return c.by_id[id] end,
            get_mob_by_index=function(index) return c.by_index[index] end,
            get_mob_by_target=function(token)
                if token == 't' then return c.selected end
                if token == 'me' then return c.self end
            end,
            run=function() error('Silence requested movement') end,
            turn=function() error('Silence requested facing') end,
            follow=function() error('Silence requested follow') end,
        },
    }
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(controller_path)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(controller_path, 't', env)
    end
    assert(loader, load_error)()
    function c.activate(name)
        env.user_job_self_command({'pstartrdm', name, 'Tackleberry', '-', '-', '-', '-'}, {})
    end
    function c.reserve(value)
        env.user_job_self_command({'pstartrdm', 'silence', value}, {})
    end
    function c.filter(spell, phase)
        local event = {}
        if phase == 'precast' then
            env.user_filter_precast(spell, nil, event)
        else
            env.user_filter_pretarget(spell, nil, event)
        end
        return event.cancel == true
    end
    function c.tick(seconds)
        c.now = c.now + (seconds or 0)
        env.user_job_tick()
    end
    function c.render(seconds)
        c.now = c.now + (seconds or 0)
        c.callbacks.prerender()
    end
    function c.begin(mob)
        c.callbacks.action({actor_id=(mob or c.enemy).id, category=8,
            param=24931, targets={{id=2, actions={{param=144, message=327}}}}})
    end
    function c.finish(mob)
        c.callbacks.action({actor_id=(mob or c.enemy).id, category=4,
            param=144, targets={{id=2, actions={{param=100, message=2}}}}})
    end
    function c.result(message, status, target_id, actor_id)
        c.callbacks.action({actor_id=actor_id or 1, category=4, param=59,
            targets={{id=target_id or c.enemy.id, actions={{message=message, param=status or 6}}}}})
    end
    function c.silences()
        local result = {}
        for _, command in ipairs(c.commands) do
            if command.command:match('^/ma "Silence" ') then
                assert(command.target, 'Silence must use the exact numeric server ID')
                result[#result+1] = command
            end
        end
        return result
    end
    function c.ready_cast()
        c.tick(0.1) -- one usable tick; no target-selection round trip
    end
    c.activate(profile or 'limbus')
    return c
end

local tests = 0
local function test(name, callback)
    callback()
    tests = tests + 1
    print('PASS '..name)
end

test('observed caster outside melee range is Silenced on the first tick without selecting', function()
    for _, distance in ipairs({13.2, 18, 19.1, 20.9}) do
        local c = new_client()
        c.enemy.x, c.enemy.distance = distance, distance*distance
        c.begin()
        c.tick(0.1)
        assert(#c.silences() == 1 and c.silences()[1].target == c.enemy.id, distance)
        assert(#c.packets == 0 and c.selected == nil,
            'Silence must not acquire a melee target or inject selection')
    end
end)

test('a different enemy with the identical name does not trigger Silence', function()
    local c = new_client()
    c.begin(c.other)
    c.ready_cast()
    assert(#c.silences() == 0 and #c.packets == 0)
end)

test('target switch cancels the old queued request and does not transfer caster identity', function()
    local c = new_client()
    c.begin()
    c.leader.target_index = c.other.index
    c.ready_cast()
    assert(#c.silences() == 0)
    c.begin(c.other)
    c.ready_cast()
    assert(#c.silences() == 1 and c.silences()[1].target == c.other.id)
end)

test('unclaimed and outsider-claimed mobs are never silenced', function()
    for _, claim in ipairs({0, 9999}) do
        local c = new_client()
        c.enemy.claim_id = claim
        c.begin()
        c.tick(60)
        c.ready_cast()
        assert(#c.silences() == 0 and #c.packets == 0)
    end
end)

test('five-second stalled-pull fallback tries once, not once per tick', function()
    local c = new_client()
    c.tick(4.9)
    assert(#c.packets == 0)
    c.tick(0.2)
    c.tick(0.1)
    assert(#c.silences() == 1)
    c.result(85)
    for _=1,6 do c.tick(12) end
    assert(#c.silences() == 1, 'unknown noncaster fallback retried repeatedly')
end)

test('regular progress toward Tackleberry prevents the stall fallback', function()
    local c = new_client()
    for _=1,8 do
        c.enemy.x = c.enemy.x - 1
        c.enemy.distance = c.enemy.x*c.enemy.x
        c.tick(3)
    end
    assert(#c.silences() == 0)
    c.enemy.x, c.enemy.distance = 5, 25
    c.tick(100)
    assert(#c.silences() == 0)
end)

test('camp movement resets the fallback delay', function()
    local c = new_client()
    c.tick(4)
    c.leader.x = 2
    c.tick(1)
    c.tick(4)
    assert(#c.silences() == 0 and #c.packets == 0)
end)

test('missing position cannot invent a stall but observed casting still works', function()
    local c = new_client()
    c.enemy.z = nil
    c.tick(60)
    assert(#c.silences() == 0)
    c.begin()
    c.ready_cast()
    assert(#c.silences() == 1)
end)

test('busy caster queues Silence and gives it the next action before routine support', function()
    local c = new_client()
    c.busy = true
    c.spell(57, 'Haste', 40)
    c.env.user_job_self_command(
        {'pstartrdm', 'limbus', 'Tackleberry', 'Tackleberry', '-', '-', '-'}, {})
    c.begin()
    c.tick(1)
    assert(#c.commands == 0)
    c.busy = false
    c.ready_cast()
    assert(c.commands[1].command == '/ma "Silence" '..c.enemy.id)
    c.result(237, 6)
    c.tick(3.1)
    assert(c.commands[2].command == '/ma "Haste" <p1>',
        'routine buff maintenance did not resume after Silence')
end)

test('emergency healing precedes pull Silence without losing the request', function()
    local c = new_client()
    c.party.p1.hpp = 10
    c.begin()
    c.tick(0.1)
    assert(c.commands[1].command == '/ma "Cure IV" <p1>')
    c.party.p1.hpp = 100
    c.tick(3.1)
    c.ready_cast()
    assert(#c.silences() == 1)
end)

test('Convert and self-recovery precede Silence without changing Convert thresholds', function()
    local c = new_client()
    c.env.player.mp, c.env.player.mpp = 100, 10
    c.begin()
    c.tick(0.1)
    assert(c.commands[1].command == '/ja "Convert" <me>')
    c.env.player.mp, c.env.player.mpp, c.env.player.hpp = 1000, 100, 15
    c.party.p0.hpp = 15
    c.tick(2.1)
    assert(c.commands[2].command == '/ma "Cure IV" <me>')
    c.env.player.hpp, c.party.p0.hpp = 100, 100
    c.tick(3.1)
    c.ready_cast()
    assert(#c.silences() == 1)
end)

test('range, recast, movement, status and MP guards do not discard the queued request', function()
    for _, guard in ipairs({'range', 'recast', 'moving', 'disabled', 'mp'}) do
        local c = new_client()
        if guard == 'range' then c.enemy.distance = 22*22 end
        if guard == 'recast' then c.recasts[59] = 600 end
        if guard == 'moving' then c.env.moving = true end
        if guard == 'disabled' then c.disabled = true end
        if guard == 'mp' then c.env.player.mp, c.env.player.mpp = 200, 20 end
        c.begin()
        c.ready_cast()
        assert(#c.silences() == 0 and #c.packets == 0, guard)
        c.enemy.distance, c.recasts[59], c.env.moving, c.disabled = 18*18, 0, false, false
        c.env.player.mp, c.env.player.mpp = 1000, 100
        c.ready_cast()
        assert(#c.silences() == 1, 'request lost after '..guard)
    end
end)

test('only a matching status-result confirms Silence', function()
    local c = new_client()
    c.begin()
    c.ready_cast()
    c.result(237, 4) -- another status is not Silence
    c.tick(12)
    assert(#c.silences() == 2, 'unrelated effect was treated as landed Silence')
    c.result(237, 6)
    c.tick(120)
    assert(#c.silences() == 2, 'confirmed coverage was blindly recast')
end)

test('a spell completion after Silence landed is not a fresh cast', function()
    local c = new_client()
    c.begin()
    c.ready_cast()
    c.result(236)
    c.finish()
    c.tick(12)
    assert(#c.silences() == 1)
    c.begin()
    c.tick(0.1)
    assert(#c.silences() == 2, 'new casting did not invalidate coverage')
end)

test('Silence wear-off rearms only the same enemy ID', function()
    local c = new_client()
    c.begin()
    c.ready_cast()
    c.result(236)
    c.callbacks['action message'](c.other.id, c.other.id, 101, 101, 64, 6)
    c.tick(12)
    assert(#c.silences() == 1)
    c.callbacks['action message'](c.enemy.id, c.enemy.id, 100, 100, 64, 6)
    c.tick(0.1)
    assert(#c.silences() == 2)
end)

test('another character landing Silence prevents redundant casting', function()
    local c = new_client()
    c.begin()
    c.result(236, 6, c.enemy.id, 2)
    c.ready_cast()
    assert(#c.silences() == 0)
end)

test('no effect is held as covered, while complete resistance stops attempts', function()
    for _, message in ipairs({75, 655, 656}) do
        local c = new_client()
        c.begin()
        c.ready_cast()
        c.result(message)
        for _=1,5 do c.tick(12) end
        assert(#c.silences() == 1, 'unbounded attempts on result '..message)
    end
end)

test('continuous casting does not reset a resistant caster attempt budget', function()
    local c = new_client()
    c.begin()
    c.ready_cast()
    for _=1,8 do
        c.result(85)
        c.begin()
        c.tick(12)
    end
    assert(#c.silences() == 3, 'known caster must have at most three attempts per cycle')
end)

test('unknown fallback becomes a confirmed caster without inheriting a new full budget', function()
    local c = new_client()
    c.tick(5.1)
    c.tick(0.1)
    c.result(85)
    c.begin()
    for _=1,5 do c.tick(12); c.result(85) end
    assert(#c.silences() == 3, 'fallback plus caster evidence exceeded total attempt budget')
end)

test('unconfirmed or interrupted attempts are bounded and never counted as landed', function()
    for _, interrupted in ipairs({false, true}) do
        local c = new_client()
        c.begin()
        c.ready_cast()
        for _=1,10 do
            if interrupted then c.env.job_aftercast({id=59, interrupted=true}, nil, {}) end
            c.tick(12)
        end
        assert(#c.silences() == 3)
    end
end)

test('unsynchronized same-name local target cannot block or misdirect Silence', function()
    local c = new_client()
    c.selected = c.other
    c.begin()
    c.ready_cast()
    assert(#c.silences() == 1 and c.silences()[1].target == c.enemy.id)
    assert(c.selected == c.other and #c.packets == 0,
        'must leave PartyCombat and the selected target alone')
    c.result(85)
    -- A retry also targets the exact pull while <t> remains on another mob.
    c.tick(12)
    assert(#c.silences() == 2 and c.silences()[2].target == c.enemy.id)
    assert(c.selected == c.other)
end)

test('observed or stalled Elementals cannot use the ranged Silence path', function()
    for _, name in ipairs({"Demon's Elemental", 'Fire Elemental', 'ELEMENTAL'}) do
        local c = new_client()
        c.enemy.name = name
        c.begin()
        c.tick(60)
        assert(#c.silences() == 0, name)
    end
    local c = new_client()
    c.enemy.name = 'Demon Elementalist'
    c.begin()
    c.ready_cast()
    assert(#c.silences() == 1, 'must not exclude non-Elemental spellcasters')
end)

test('death, claim loss, zoning, logout and stopping clear queued identity', function()
    for _, change in ipairs({'death', 'claim', 'zone', 'logout', 'stop'}) do
        local c = new_client()
        c.begin()
        if change == 'death' then c.enemy.hpp = 0 end
        if change == 'claim' then c.enemy.claim_id = 0 end
        if change == 'zone' then c.info.zone = 37 end
        if change == 'logout' then c.info.logged_in = false end
        if change == 'stop' then c.env.user_job_self_command({'pstartrdm', 'off'}, {}) end
        c.ready_cast()
        assert(#c.silences() == 0, change)
    end
end)

test('all non-Limbus profiles ignore pull-caster and stall events', function()
    for _, profile in ipairs({'master', 'apexbats', 'locusbats', 'apexcrabs',
        'physical', 'accuracy', 'magic', 'safe', 'fishfly', 'ambuscade-v1', 'ambuscade-v2'}) do
        local c = new_client(profile)
        c.begin()
        c.tick(60)
        c.ready_cast()
        assert(#c.silences() == 0 and #c.packets == 0, profile)
    end
end)

test('switching from Limbus to another profile drops pending Silence', function()
    local c = new_client()
    c.begin()
    c.activate('locusbats')
    c.ready_cast()
    assert(#c.silences() == 0 and #c.packets == 0)
end)

test('typed exact Silence reserves the next action in an unrelated profile', function()
    local c = new_client('physical')
    c.busy = true
    c.reserve('1000')
    c.reserve('1000')
    c.tick(2)
    assert(#c.silences() == 0)
    c.busy = false
    c.ready_cast()
    assert(#c.silences() == 1 and c.silences()[1].target == c.enemy.id)
    assert(c.silences()[1].selected == nil,
        'exact Silence must not alter or depend on the selected target')
end)

test('typed exact Silence remains available with routine RDM upkeep off', function()
    local c = new_client('physical')
    c.env.user_job_self_command({'pstartrdm', 'off'}, {})
    c.busy = true
    c.reserve('1000')
    assert(#c.silences() == 0)
    c.busy = false
    c.render(0.1)
    assert(#c.silences() == 1 and c.silences()[1].target == 1000)
end)

test('typed exact Silence rejects malformed, dead, missing and outsider targets', function()
    local c = new_client('physical')
    for _, value in ipairs({
        '', '0', '-1', '+1', '1.0', '1e3', '4294967296',
        '1000;input /attack', {}, false,
    }) do
        c.reserve(value)
    end
    c.reserve(nil)
    c.reserve('4294967295')
    c.enemy.hpp = 0
    c.reserve('1000')
    c.enemy.hpp, c.enemy.claim_id = 100, 9999
    c.reserve('1000')
    assert(#c.silences() == 0)
end)

test('typed exact Silence holds across temporary blockers but expires boundedly', function()
    for _, guard in ipairs({'range', 'recast', 'moving', 'disabled', 'mp'}) do
        local c = new_client('physical')
        if guard == 'range' then c.enemy.distance = 22*22 end
        if guard == 'recast' then c.recasts[59] = 600 end
        if guard == 'moving' then c.env.moving = true end
        if guard == 'disabled' then c.disabled = true end
        if guard == 'mp' then c.env.player.mp = 0 end
        c.reserve('1000')
        assert(#c.silences() == 0, guard)
        c.enemy.distance, c.recasts[59] = 18*18, 0
        c.env.moving, c.disabled, c.env.player.mp = false, false, 1000
        c.ready_cast()
        assert(#c.silences() == 1, 'request lost after '..guard)
    end
    local expired = new_client('physical')
    expired.busy = true
    expired.reserve('1000')
    expired.tick(31)
    expired.busy = false
    expired.ready_cast()
    assert(#expired.silences() == 0, 'expired request later cast')
end)

test('typed exact Silence blocks new actions except its cast and Silence remedies', function()
    local c = new_client('physical')
    c.busy = true
    c.reserve('1000')
    assert(c.filter({id=57, english='Haste', action_type='Magic',
        target={id=2}}), 'routine spell bypassed the reservation')
    c.env.buffactive.silence = true
    assert(not c.filter({id=1, english='Echo Drops', action_type='Item'}),
        'Silence remedy was blocked')
    c.env.buffactive.silence = nil
    c.busy = false
    c.ready_cast()
    assert(not c.filter({id=59, english='Silence', action_type='Magic'}),
        'numeric Silence was blocked before pretarget resolution')
    assert(not c.filter({id=59, english='Silence', action_type='Magic',
        target={id=1001}}),
        'stale pretarget state blocked the locally dispatched Silence')
    assert(not c.filter({id=59, english='Silence', action_type='Magic',
        target={id=1000}}, 'precast'),
        'the exact resolved Silence blocked itself at precast')
    assert(c.filter({id=59, english='Silence', action_type='Magic',
        target={id=1001}}, 'precast'),
        'a different resolved Silence bypassed the exact precast guard')
end)

test('typed exact Silence retries are bounded and repeated requests do not multiply', function()
    local c = new_client('physical')
    c.reserve('1000')
    c.reserve('1000')
    assert(#c.silences() == 1)
    for attempt=1,3 do
        c.reserve('1000')
        c.result(85)
        c.tick(2.1)
    end
    assert(#c.silences() == 3, 'exact Silence exceeded its attempt budget')
    c.tick(60)
    assert(#c.silences() == 3)
end)

test('typed exact Silence success and lifecycle changes release the reservation', function()
    local c = new_client('physical')
    c.reserve('1000')
    c.result(236)
    c.tick(20)
    assert(#c.silences() == 1, 'confirmed Silence was maintained blindly')

    for _, change in ipairs({
        'targetdeath', 'selfdeath', 'claim', 'zone', 'logout', 'profile', 'stop',
    }) do
        local client = new_client('physical')
        client.busy = true
        client.reserve('1000')
        if change == 'targetdeath' then client.enemy.hpp = 0 end
        if change == 'selfdeath' then client.env.player.hpp = 0 end
        if change == 'claim' then client.enemy.claim_id = 0 end
        if change == 'zone' then client.info.zone = 39 end
        if change == 'logout' then client.info.logged_in = false end
        if change == 'profile' then client.activate('safe') end
        if change == 'stop' then
            client.env.user_job_self_command({'pstartrdm', 'off'}, {})
        end
        client.busy = false
        client.ready_cast()
        assert(#client.silences() == 0, change)
    end
end)

print(('PASS %d RDM Silence queue runtime tests'):format(tests))
