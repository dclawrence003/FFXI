-- Full PartyCombat runtime tests; no game client, movement, or real packets.
local source = arg and arg[1] or 'addons/PartyCombat/PartyCombat.lua'
local roster = {'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}
local roster_csv = table.concat(roster, ',')
local unpack_values = table.unpack or unpack
function string.startswith(value, prefix) return value:sub(1, #prefix) == prefix end
-- Windower's Lua runtime exposes math.atan2; Fengari follows Lua 5.3 and
-- exposes the equivalent two-argument math.atan instead.
if not math.atan2 then
    math.atan2 = function(y, x) return math.atan(y, x) end
end

local function client(name, target_exclusion, options)
    options = options or {}
    local c = {now=100, callbacks={}, packets={}, commands={}, chats={}, ipc={},
        mobs={}, turns=0, runs={}}
    local env = setmetatable({}, {__index=_G})
    env._addon = {}
    env.os = setmetatable({clock=function() return c.now end}, {__index=os})
    c.player = {id=10, index=10, name=name or 'Dolomedes', status=0, target_index=0}
    c.self = {id=10, index=10, name=c.player.name, spawn_type=1,
        valid_target=true, hpp=100, distance=0, x=0, y=0, z=0}
    c.mobs[10] = c.self
    function c.mob(id, mob_name)
        local mob = {id=id, index=id, name=mob_name, spawn_type=16,
            valid_target=true, hpp=100, distance=16, x=4, y=0, z=0}
        c.mobs[id] = mob
        return mob
    end
    c.normal = c.mob(100, 'Apollyon Demon')
    c.elemental = c.mob(101, "Demon's Elemental")
    c.selected = c.self
    local packets = {
        new=function(direction, id, fields)
            fields.direction, fields.packet_id = direction, id
            return fields
        end,
        inject=function(packet)
            c.packets[#c.packets+1] = packet
            if packet.direction == 'outgoing' then
                assert(packet.packet_id == 0x01A)
                c.selected, c.battle = c.mobs[packet.Target], c.mobs[packet.Target]
                c.player.status, c.player.target_index = 1, packet['Target Index']
            elseif packet.direction == 'incoming' then
                assert(packet.packet_id == 0x058, 'unexpected target-release packet')
                c.selected = c.mobs[packet.Target]
                c.player.target_index = c.selected and c.selected.index or 0
            end
        end,
    }
    env.require = function(module)
        if module == 'packets' then return packets end
        if module == 'resources' then return {action_messages={[99]={color='D'}}} end
        assert(module == 'strings', 'unexpected dependency: '..module)
        return true
    end
    env.windower = {
        addon_path='addons/PartyCombat/',
        add_to_chat=function(_, message) c.chats[#c.chats+1] = message end,
        send_command=function(command)
            assert(not command:lower():find('ffo', 1, true), 'FastFollow was changed')
            c.commands[#c.commands+1] = command
            if command == 'input /attack off' then c.player.status, c.battle = 0, nil end
        end,
        send_ipc_message=function(message) c.ipc[#c.ipc+1] = message end,
        register_event=function(...)
            local values = {...}
            for index=1,#values-1 do c.callbacks[values[index]] = values[#values] end
        end,
        ffxi={
            get_player=function() return c.player end,
            get_mob_by_id=function(id) return c.mobs[id] end,
            get_mob_array=function() return c.mobs end,
            get_party=function()
                return {p0={name=c.player.name, mob={id=c.player.id}}}
            end,
            get_mob_by_target=function(token)
                if token == 't' then return c.selected end
                if token == 'bt' then return c.battle end
                if token == 'me' then return c.self end
            end,
            run=function(value) c.runs[#c.runs+1]=value end,
            turn=function() c.turns = c.turns + 1 end,
        },
    }
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(source)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(source, 't', env)
    end
    assert(loader, load_error)()
    function c.command(...) c.callbacks['addon command'](...) end
    function c.tick(seconds)
        c.now = c.now + (seconds or 0.1)
        c.callbacks.prerender()
    end
    function c.share(mob, mode, name_token)
        c.callbacks['ipc message']('PARTYCOMBAT1|target|Dolomedes|'
            ..mob.id..'|'..(mode or 'auto')..'|'..(name_token or '-'))
    end
    function c.share_to(mob, recipient)
        c.callbacks['ipc message']('PARTYCOMBAT1|targetto|Dolomedes|'
            ..mob.id..'|forcesubset|'..recipient)
    end
    function c.damage(mob, category, spell_id)
        c.callbacks.action({actor_id=c.player.id, category=category or 1, param=spell_id,
            targets={{id=mob.id, actions={{message=99}}}}})
    end
    function c.select(mob, engaged)
        c.selected, c.player.target_index = mob, mob.index
        if engaged then c.battle, c.player.status = mob, 1 end
    end
    function c.attacks()
        local result = {}
        for _, packet in ipairs(c.packets) do
            if packet.direction == 'outgoing' then result[#result+1] = packet end
        end
        return result
    end
    function c.status()
        c.command('status')
        return c.chats[#c.chats-1]
    end
    function c.exclusion_status()
        c.command('status')
        return c.chats[#c.chats]
    end
    if target_exclusion == nil then target_exclusion = 'elemental' end
    local attacker_csv = options.attacker_csv or roster_csv
    local targeter_csv = options.targeter_csv or roster_csv
    local puller = options.puller or 'Tackleberry'
    if target_exclusion == false then
        c.command('policy', 'progression-limbus', 'Dolomedes', puller,
            attacker_csv, targeter_csv, 'stationary', '-', '-')
    else
        c.command('policy', 'progression-limbus', 'Dolomedes', puller,
            attacker_csv, targeter_csv, 'stationary', '-', '-', target_exclusion)
    end
    if not options.skip_authorize then
        if c.player.name == 'Dolomedes' or c.player.name == 'Tackleberry' then
            c.command('on')
        else
            c.callbacks['ipc message']('PARTYCOMBAT1|authority|Dolomedes|'..c.player.name..'|1')
        end
    end
    return c
end

local total = 0
local function test(name, fn)
    fn()
    total = total + 1
    print('PASS '..name)
end

local function target_message_count(c)
    local count = 0
    for _, message in ipairs(c.ipc) do
        if message:find('|target|', 1, true) then count = count + 1 end
    end
    return count
end

local function directed_message_count(c)
    local count = 0
    for _, message in ipairs(c.ipc) do
        if message:find('|targetto|', 1, true) then count = count + 1 end
    end
    return count
end

test('forceid validates a uint32 and preserves current-target force', function()
    local by_id = client('Dolomedes', '-')
    by_id.command('forceid', tostring(by_id.normal.id))
    assert(#by_id.attacks() == 1)
    assert(by_id.attacks()[1].Target == by_id.normal.id)
    assert(target_message_count(by_id) == 1)

    local current = client('Dolomedes', '-')
    current.select(current.normal)
    current.command('force')
    assert(#current.attacks() == 1)
    assert(current.attacks()[1].Target == current.normal.id)
    assert(target_message_count(current) == 1)

    local maximum = client('Dolomedes', '-')
    local maximum_id = maximum.mob(4294967295, 'Boundary Target')
    maximum_id.index = 200
    maximum.command('forceid', '4294967295')
    assert(#maximum.attacks() == 1)
    assert(maximum.attacks()[1].Target == 4294967295)

    for _, value in ipairs({'0','-1','1.5','1e2','abc','4294967296'}) do
        local invalid = client('Dolomedes', '-')
        invalid.command('forceid', value)
        assert(#invalid.attacks() == 0, 'invalid forceid attacked: '..value)
        assert(target_message_count(invalid) == 0,
            'invalid forceid broadcast: '..value)
    end
    local missing = client('Dolomedes', '-')
    missing.command('forceid')
    missing.command('forceid', '999')
    missing.command('forceid', tostring(missing.normal.id), 'extra')
    assert(#missing.attacks() == 0 and target_message_count(missing) == 0)

    local excluded = client('Dolomedes')
    excluded.command('forceid', tostring(excluded.elemental.id))
    assert(#excluded.attacks() == 0 and target_message_count(excluded) == 0)

    local participant = client('Kickpuncher', '-', {skip_authorize=true})
    participant.command('forceid', tostring(participant.normal.id))
    assert(#participant.attacks() == 1
        and target_message_count(participant) == 1,
        'a configured participant was gated from an explicit force')

    local outsider = client('Spectator', '-', {skip_authorize=true})
    outsider.command('forceid', tostring(outsider.normal.id))
    assert(#outsider.attacks() == 0 and target_message_count(outsider) == 0)
end)

test('forceidto peels only named attackers once and preserves manual control',
function()
    local attackers = 'Dolomedes,Kickpuncher,Barneystinson'
    local controller = client('Dolomedes', '-', {
        attacker_csv=attackers, targeter_csv=attackers,
    })
    controller.command('forceidto', tostring(controller.normal.id),
        'Barneystinson')
    assert(#controller.attacks() == 0,
        'non-recipient controller was redirected')
    assert(directed_message_count(controller) == 1)
    assert(controller.ipc[#controller.ipc] ==
        'PARTYCOMBAT1|targetto|Dolomedes|100|forcesubset|Barneystinson')

    local boss_side = client('Dolomedes', '-', {
        attacker_csv=attackers, targeter_csv=attackers,
    })
    boss_side.command('forceidto', tostring(boss_side.normal.id),
        'Dolomedes,Kickpuncher')
    assert(#boss_side.attacks() == 1
        and directed_message_count(boss_side) == 2)
    boss_side.damage(boss_side.normal, 1)
    assert(target_message_count(boss_side) == 0,
        'boss-side controller damage escaped the directed lane')

    local barney = client('Barneystinson', '-', {
        skip_authorize=true, attacker_csv=attackers, targeter_csv=attackers,
    })
    barney.normal.distance = 40 * 40
    barney.share_to(barney.normal, 'Barneystinson')
    assert(#barney.attacks() == 1
        and barney.attacks()[1].Target == barney.normal.id,
        'named attacker did not accept the arena-width split')
    assert(barney.status():find('mode forcesubset', 1, true))

    for _, name in ipairs{'Dolomedes','Kickpuncher'} do
        local other = client(name, '-', {
            skip_authorize=true,
            attacker_csv=attackers, targeter_csv=attackers,
        })
        other.share_to(other.normal, 'Barneystinson')
        assert(#other.attacks() == 0
            and other.status():find('target none', 1, true),
            name..' followed Barney to the split target')
    end

    local boss = barney.mob(102, 'Bozzetto Bigwig')
    barney.select(boss, true)
    local packets = #barney.packets
    barney.tick()
    barney.tick(2)
    assert(#barney.packets == packets
        and barney.selected.id == boss.id and barney.battle.id == boss.id,
        'directed split reacquired after a manual target override')
    assert(barney.status():find('target none', 1, true))

    local too_far = client('Barneystinson', '-', {
        skip_authorize=true, attacker_csv=attackers, targeter_csv=attackers,
    })
    too_far.normal.distance = 51 * 51
    too_far.share_to(too_far.normal, 'Barneystinson')
    assert(#too_far.attacks() == 0,
        'directed split exceeded its bounded arena distance')
end)

test('directed target delivery tolerates only the stale prior battle target',
function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson'
    local c = client('Barneystinson', '-', {
        skip_authorize=true, attacker_csv=attackers,
        targeter_csv='Dolomedes,Kickpuncher,Barneystinson',
    })
    local boss = c.mob(102, 'Bozzetto Bigwig')
    c.select(boss, true)
    c.share_to(c.normal, 'Barneystinson')
    assert(#c.attacks() == 1 and c.battle.id == c.normal.id)

    -- Model the live client frame where the injected change has been sent but
    -- Windower still reports the exact previous battle target.
    c.battle, c.player.status = boss, 1
    c.tick(.1)
    assert(c.status():find('target Apollyon Demon', 1, true),
        'stale prior battle target incorrectly yielded the directed handoff')
    c.tick(3)
    assert(c.status():find('target Apollyon Demon', 1, true),
        'directed handoff yielded at the ordinary two-second window')
    c.tick(1.5)
    assert(#c.attacks() == 2 and c.battle.id == c.normal.id,
        'bounded delivery retry did not establish the directed target')

    -- Once the requested target is observed, an operator-selected battle
    -- target must still win immediately.
    local manual = c.mob(103, 'Bozzetto Tormentor')
    c.select(manual, true)
    c.tick(.1)
    assert(c.status():find('target none', 1, true),
        'confirmed directed target retained a snap-back lock')
end)

test('rapid consecutive directed edges bypass the prior engage throttle',
function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson'
    local c = client('Tackleberry', '-', {
        skip_authorize=true, attacker_csv=attackers,
        targeter_csv='Dolomedes,Kickpuncher,Barneystinson',
    })
    local astrologer = c.mob(102, 'Bozzetto Astrologer')
    c.share_to(c.normal, 'Tackleberry')
    c.now = c.now + .5
    c.share_to(astrologer, 'Tackleberry')
    assert(#c.attacks() == 2 and c.battle.id == astrologer.id,
        'new exact target edge was suppressed by the previous edge throttle')
end)

test('directed-only attacker ignores boss sync but accepts exact add splits',
function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson'
    local targeters = 'Dolomedes,Kickpuncher,Barneystinson'
    local tackle = client('Tackleberry', '-', {
        skip_authorize=true, attacker_csv=attackers,
        targeter_csv=targeters, puller='Dolomedes',
    })
    assert(tackle.status():find('role directed-only attacker', 1, true))

    tackle.callbacks['ipc message'](
        'PARTYCOMBAT1|authority|Dolomedes|Tackleberry|1')
    tackle.share(tackle.normal, 'force')
    assert(#tackle.attacks() == 0
        and tackle.status():find('target none', 1, true),
        'broad boss authority reached a directed-only attacker')

    tackle.normal.distance = 40 * 40
    tackle.share_to(tackle.normal, 'Tackleberry')
    assert(#tackle.attacks() == 1
        and tackle.attacks()[1].Target == tackle.normal.id,
        'exact add split did not atomically authorize directed attacker')
    local status = tackle.status()
    assert(status:find('authorized Yes', 1, true)
        and status:find('mode forcesubset', 1, true))
end)

test('stopto stops only its exact recipient and leaves policy reusable',
function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson'
    local targeters = 'Dolomedes,Kickpuncher,Barneystinson'
    local tackle = client('Tackleberry', '-', {
        skip_authorize=true, attacker_csv=attackers,
        targeter_csv=targeters, puller='Dolomedes',
    })
    tackle.share_to(tackle.normal, 'Tackleberry')
    assert(tackle.player.status == 1)
    tackle.callbacks['ipc message'](
        'PARTYCOMBAT1|stopto|Dolomedes|Kickpuncher')
    assert(tackle.player.status == 1,
        'foreign directed stop affected Tackleberry')
    tackle.callbacks['ipc message'](
        'PARTYCOMBAT1|stopto|Dolomedes|Tackleberry')
    assert(tackle.player.status == 0)
    local stopped = tackle.status()
    assert(stopped:find('support-ready Yes', 1, true)
        and stopped:find('target none', 1, true),
        'directed stop invalidated the reusable policy')
    tackle.share_to(tackle.normal, 'Tackleberry')
    assert(tackle.player.status == 1 and #tackle.attacks() == 2,
        'next directed edge did not resume a stopped member')

    local controller = client('Dolomedes', '-', {
        attacker_csv=attackers, targeter_csv=targeters,
    })
    controller.command('stopto', 'Dolomedes,Tackleberry')
    local sent = {}
    for _, message in ipairs(controller.ipc) do
        if message:find('|stopto|', 1, true) then sent[#sent + 1] = message end
    end
    assert(#sent == 2)
    assert(sent[1] == 'PARTYCOMBAT1|stopto|Dolomedes|Dolomedes')
    assert(sent[2] == 'PARTYCOMBAT1|stopto|Dolomedes|Tackleberry')
end)

test('forceidto rejects malformed targets but accepts configured participants', function()
    local attackers = 'Dolomedes,Kickpuncher,Barneystinson'
    local invalid = client('Dolomedes', nil, {
        attacker_csv=attackers, targeter_csv=attackers,
    })
    for _, arguments in ipairs{
        {}, {'0','Barneystinson'}, {'100'}, {'100','Tackleberry'},
        {'100','Barneystinson,barneystinson'},
        {'100','Barneystinson,,Kickpuncher'},
        {'100','Barneystinson;pc'}, {'100','Barneystinson','extra'},
    } do
        invalid.command('forceidto', unpack_values(arguments))
    end
    invalid.command('forceidto', tostring(invalid.elemental.id),
        'Barneystinson')
    assert(directed_message_count(invalid) == 0
        and #invalid.attacks() == 0)

    local participant = client('Kickpuncher', '-', {
        skip_authorize=true, attacker_csv=attackers, targeter_csv=attackers,
    })
    participant.command('forceidto', tostring(participant.normal.id),
        'Barneystinson')
    assert(directed_message_count(participant) == 1
        and #participant.attacks() == 0,
        'a configured participant was gated from a directed force')

    local outsider = client('Spectator', '-', {
        skip_authorize=true, attacker_csv=attackers, targeter_csv=attackers,
    })
    outsider.command('forceidto', tostring(outsider.normal.id),
        'Barneystinson')
    assert(directed_message_count(outsider) == 0 and #outsider.attacks() == 0)

    local spoofed = client('Barneystinson', '-', {
        skip_authorize=true, attacker_csv=attackers, targeter_csv=attackers,
    })
    spoofed.share_to(spoofed.normal, 'Smalls')
    assert(#spoofed.attacks() == 0
        and spoofed.status():find('authorized No', 1, true))
end)

test('engageonceid is one local engage with no synchronized target ownership', function()
    local c = client('Dolomedes', '-', {
        attacker_csv='Tackleberry,Kickpuncher',
        targeter_csv='Tackleberry,Kickpuncher',
    })
    c.command('engageonceid', tostring(c.normal.id))
    assert(#c.attacks() == 1)
    assert(c.attacks()[1].Target == c.normal.id)
    assert(target_message_count(c) == 0,
        'one-shot local engage was broadcast as a synchronized target')
    local packet_count, turn_count = #c.attacks(), c.turns
    c.tick(2)
    assert(#c.attacks() == packet_count,
        'one-shot local engage retried after the command edge')
    assert(c.turns == turn_count,
        'one-shot local engage introduced automatic facing')

    for _, value in ipairs({'0','-1','1.5','abc','4294967296'}) do
        local invalid = client('Dolomedes', '-', {
            attacker_csv='Tackleberry,Kickpuncher',
            targeter_csv='Tackleberry,Kickpuncher',
        })
        invalid.command('engageonceid', value)
        assert(#invalid.attacks() == 0, 'invalid engageonceid attacked: '..value)
        assert(target_message_count(invalid) == 0,
            'invalid engageonceid broadcast: '..value)
    end

    local excluded = client('Dolomedes', nil, {
        attacker_csv='Tackleberry,Kickpuncher',
        targeter_csv='Tackleberry,Kickpuncher',
    })
    excluded.command('engageonceid', tostring(excluded.elemental.id))
    assert(#excluded.attacks() == 0 and target_message_count(excluded) == 0)

    local participant = client('Kickpuncher', '-', {
        attacker_csv='Tackleberry,Kickpuncher',
        targeter_csv='Tackleberry,Kickpuncher',
        skip_authorize=true,
    })
    participant.command('engageonceid', tostring(participant.normal.id))
    assert(#participant.attacks() == 1
        and target_message_count(participant) == 0,
        'a configured participant was gated from a local one-shot engage')

    local outsider = client('Spectator', '-', {
        attacker_csv='Tackleberry,Kickpuncher',
        targeter_csv='Tackleberry,Kickpuncher',
        skip_authorize=true,
    })
    outsider.command('engageonceid', tostring(outsider.normal.id))
    assert(#outsider.attacks() == 0 and target_message_count(outsider) == 0)
end)

test('opaque force is exact party-claimed and isolated from normal targets', function()
    local c = client('Dolomedes', '-')
    c.normal.hpp = nil
    c.normal.claim_id = c.player.id
    c.command('forceid', tostring(c.normal.id))
    assert(#c.attacks() == 0, 'ordinary force accepted a nil-HPP enemy')
    c.command('forceopaqueid', tostring(c.normal.id), 'Apollyon_Demon')
    assert(#c.attacks() == 1 and c.attacks()[1].Target == c.normal.id)
    assert(c.ipc[#c.ipc] ==
        'PARTYCOMBAT1|target|Dolomedes|100|forceopaque|Apollyon_Demon')
    c.tick(0.2)
    assert(c.status():find('target Apollyon Demon', 1, true))

    c.normal.claim_id = 0
    c.tick(0.2)
    assert(c.status():find('target none', 1, true),
        'opaque target survived party claim loss')

    for _, bad_name in ipairs({'Wrong_Name','bad;name','-'}) do
        local rejected = client('Dolomedes', '-')
        rejected.normal.hpp = nil
        rejected.normal.claim_id = rejected.player.id
        rejected.command('forceopaqueid', tostring(rejected.normal.id), bad_name)
        assert(#rejected.attacks() == 0,
            'opaque force accepted name '..bad_name)
    end
    local unclaimed = client('Dolomedes', '-')
    unclaimed.normal.hpp = nil
    unclaimed.normal.claim_id = 0
    unclaimed.command('forceopaqueid', tostring(unclaimed.normal.id),
        'Apollyon_Demon')
    assert(#unclaimed.attacks() == 0)

    local follower = client('Kickpuncher', '-', {skip_authorize=true})
    follower.normal.hpp = nil
    follower.normal.claim_id = follower.player.id
    follower.share(follower.normal, 'forceopaque', 'Apollyon_Demon')
    assert(#follower.attacks() == 1)
    assert(follower.status():find('mode forceopaque', 1, true))

    local rejected_followers = {
        function(rejected)
            rejected.normal.hpp = nil
            rejected.normal.claim_id = rejected.player.id
            rejected.share(rejected.normal, 'forceopaque', 'Wrong_Name')
        end,
        function(rejected)
            rejected.callbacks['ipc message'](
                'PARTYCOMBAT1|target|Dolomedes|999|forceopaque|Apollyon_Demon')
        end,
        function(rejected)
            rejected.normal.hpp = nil
            rejected.normal.claim_id = 0
            rejected.share(rejected.normal, 'forceopaque', 'Apollyon_Demon')
        end,
        function(rejected)
            rejected.normal.hpp = nil
            rejected.normal.claim_id = 999999
            rejected.share(rejected.normal, 'forceopaque', 'Apollyon_Demon')
        end,
        function(rejected)
            rejected.normal.hpp = nil
            rejected.normal.claim_id = rejected.player.id
            rejected.share(rejected.normal, 'forceopaque', '-')
        end,
    }
    for index, reject in ipairs(rejected_followers) do
        local rejected = client('Kickpuncher', '-', {skip_authorize=true})
        reject(rejected)
        local status = rejected.status()
        assert(#rejected.attacks() == 0,
            'invalid opaque follower case '..index..' attacked')
        assert(status:find('authorized No', 1, true)
            and status:find('target none', 1, true),
            'invalid opaque follower case '..index..' escaped inert state')
        assert(#rejected.commands == 0,
            'invalid opaque follower case '..index..' changed HealBot')
    end
end)

test('forced target atomically authorizes a runtime-ready targeter', function()
    local c = client('Kickpuncher', '-', {skip_authorize=true})
    assert(c.status():find('authorized No', 1, true))
    c.share(c.normal, 'auto')
    assert(#c.attacks() == 0 and c.status():find('target none', 1, true))
    c.share(c.normal, 'force')
    assert(#c.attacks() == 1 and c.attacks()[1].Target == c.normal.id)
    local status = c.status()
    assert(status:find('authorized Yes', 1, true))
    assert(status:find('target Apollyon Demon', 1, true))

    local stale = client('Kickpuncher', '-', {skip_authorize=true})
    stale.command('invalidate', 'partytactics')
    stale.share(stale.normal, 'force')
    assert(#stale.attacks() == 0)
    local stale_status = stale.status()
    assert(stale_status:find('support-ready No', 1, true))
    assert(stale_status:find('authorized No', 1, true))
end)

test('only exact opaque force retransmits once after one second', function()
    local ordinary = client('Dolomedes', '-')
    ordinary.command('forceid', tostring(ordinary.normal.id))
    ordinary.tick(1.01)
    assert(target_message_count(ordinary) == 1,
        'ordinary force unexpectedly retained a snap-back retry')

    local c = client('Dolomedes', '-')
    c.normal.hpp = nil
    c.normal.claim_id = c.player.id
    c.command('forceopaqueid', tostring(c.normal.id), 'Apollyon_Demon')
    assert(target_message_count(c) == 1)
    c.tick(0.99)
    assert(target_message_count(c) == 1)
    c.tick(0.02)
    assert(target_message_count(c) == 2)
    for _=1,5 do c.tick(1) end
    assert(target_message_count(c) == 2, 'force retry was not bounded')
end)

test('stop invalidate and zone clear a pending force retransmit', function()
    local cases = {
        function(c) c.command('stop') end,
        function(c) c.command('invalidate', 'partytactics') end,
        function(c) c.callbacks['zone change']() end,
    }
    for _, cancel in ipairs(cases) do
        local c = client('Dolomedes', '-')
        c.normal.hpp = nil
        c.normal.claim_id = c.player.id
        c.command('forceopaqueid', tostring(c.normal.id), 'Apollyon_Demon')
        assert(target_message_count(c) == 1)
        cancel(c)
        c.tick(2)
        assert(target_message_count(c) == 1,
            'cancelled force was retransmitted')
    end
end)

test('logout and unload fully revoke combat and pending opaque force', function()
    for _, event_name in ipairs({'logout','unload'}) do
        local c = client('Dolomedes', '-')
        c.normal.hpp = nil
        c.normal.claim_id = c.player.id
        c.command('forceopaqueid', tostring(c.normal.id), 'Apollyon_Demon')
        assert(#c.attacks() == 1 and c.player.status == 1)
        local targets_before = target_message_count(c)

        c.callbacks[event_name]()
        local attack_off = 0
        for _, command in ipairs(c.commands) do
            if command == 'input /attack off' then attack_off = attack_off + 1 end
        end
        assert(attack_off == 1 and c.player.status == 0,
            event_name..' did not disengage the injected attacker')
        local status = c.status()
        assert(status:find('armed Off', 1, true)
            and status:find('authorized No', 1, true)
            and status:find('support-ready No', 1, true)
            and status:find('target none', 1, true),
            event_name..' retained combat authority or target state')
        c.tick(2)
        assert(target_message_count(c) == targets_before,
            event_name..' allowed a pending opaque retransmit')
    end
end)

test('observeid selects only a validated local target-only observer target', function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Achoo'
    local c = client('Barneystinson', '-', {
        skip_authorize=true,
        attacker_csv=attackers,
        targeter_csv=roster_csv,
    })
    assert(c.status():find('role target-only observer', 1, true))
    assert(c.status():find('armed Off', 1, true))
    assert(c.status():find('authorized No', 1, true))

    c.command('observeid', tostring(c.normal.id))
    assert(#c.packets == 1 and c.packets[1].direction == 'incoming')
    assert(c.packets[1].packet_id == 0x058)
    assert(c.packets[1].Target == c.normal.id)
    assert(#c.attacks() == 0 and #c.ipc == 0 and #c.commands == 0)
    assert(c.turns == 0)
    local status = c.status()
    assert(status:find('armed Off', 1, true))
    assert(status:find('authorized Yes', 1, true))
    assert(status:find('target Apollyon Demon', 1, true))
    assert(status:find('mode observe', 1, true))
    c.tick(2)
    assert(#c.packets == 1 and #c.ipc == 0 and #c.attacks() == 0)
end)

test('observeid rejects unsafe roles readiness ids targets and distance', function()
    local attackers = 'Dolomedes,Tackleberry,Kickpuncher,Achoo'
    local function observer(options)
        options = options or {}
        options.skip_authorize = true
        options.attacker_csv = attackers
        if options.targeter_csv == nil then options.targeter_csv = roster_csv end
        return client('Barneystinson', '-', options)
    end

    local invalid = observer()
    invalid.command('observeid', '0')
    invalid.command('observeid')
    invalid.command('observeid', tostring(invalid.normal.id), 'extra')
    invalid.command('observeid', '999')
    assert(#invalid.packets == 0 and #invalid.ipc == 0)
    assert(invalid.status():find('authorized No', 1, true))

    local distant = observer()
    distant.normal.distance = 31 * 31
    distant.command('observeid', tostring(distant.normal.id))
    assert(#distant.packets == 0 and #distant.ipc == 0)
    assert(distant.status():find('authorized No', 1, true))

    local excluded = client('Barneystinson', 'elemental', {
        skip_authorize=true,
        attacker_csv=attackers,
        targeter_csv=roster_csv,
    })
    excluded.command('observeid', tostring(excluded.elemental.id))
    assert(#excluded.packets == 0 and #excluded.ipc == 0)

    local stale = observer()
    stale.command('invalidate', 'partytactics')
    stale.command('observeid', tostring(stale.normal.id))
    assert(#stale.packets == 0 and #stale.ipc == 0)
    assert(stale.status():find('support-ready No', 1, true))

    local attacker = client('Kickpuncher', '-', {skip_authorize=true})
    attacker.command('observeid', tostring(attacker.normal.id))
    assert(#attacker.packets == 0 and #attacker.ipc == 0)

    local inert = observer({targeter_csv='Dolomedes,Tackleberry'})
    inert.command('observeid', tostring(inert.normal.id))
    assert(#inert.packets == 0 and #inert.ipc == 0)
end)

test('every character rejects ordinary and summoned elementals in all target modes', function()
    for _, name in ipairs(roster) do
        for _, mob_name in ipairs({"Demon's Elemental", "Aern's Elemental", "Yagudo's Elemental",
            'Fire Elemental','Ice Elemental','Air Elemental','Earth Elemental',
            'Thunder Elemental','Water Elemental','Light Elemental','Dark Elemental',
            "DEMON'S ELEMENTAL"}) do
            for _, mode in ipairs({'auto','force','priority','resume'}) do
                local c = client(name)
                c.elemental.name = mob_name
                c.share(c.elemental, mode)
                c.tick()
                assert(#c.attacks() == 0, name..' attacked '..mob_name..' in '..mode)
                assert(c.status():find('target none', 1, true))
            end
        end
    end
end)

test('status reports the configured elemental exclusion', function()
    local c = client()
    assert(c.exclusion_status():find(
        'Target exclusions: elemental.', 1, true))
end)

test('a policy with no exclusions permits elemental targets', function()
    for index, name in ipairs(roster) do
        -- Cover both an explicit '-' and the backward-compatible omitted
        -- final argument. Both mean no exclusions.
        local exclusion = '-'
        if index == 1 then exclusion = false end
        local c = client(name, exclusion)
        c.share(c.elemental)
        c.tick()
        assert(#c.attacks() > 0, name..' did not attack an allowed elemental')
        assert(c.exclusion_status():find('Target exclusions: none.', 1, true))
    end
end)

test('unsupported exclusion tokens are rejected without replacing the policy', function()
    local c = client('Dolomedes', '-')
    c.command('policy', 'progression-limbus', 'Dolomedes', 'Tackleberry',
        roster_csv, roster_csv, 'stationary', '-', '-', 'avatar')
    assert(c.exclusion_status():find('Target exclusions: none.', 1, true))
    local rejected = false
    for _, message in ipairs(c.chats) do
        if message:find('Rejected unsupported target exclusion: avatar', 1, true) then
            rejected = true
        end
    end
    assert(rejected, 'unsupported exclusion was not reported')
end)

test('force cannot bypass the elemental exclusion for either controller', function()
    for _, name in ipairs({'Dolomedes','Tackleberry'}) do
        local c = client(name)
        c.select(c.elemental)
        c.command('force')
        c.tick()
        assert(#c.attacks() == 0 and c.selected.id == c.self.id)
        for _, message in ipairs(c.ipc) do
            assert(not message:find('|target|', 1, true), 'excluded force was broadcast')
        end
    end
end)

test('melee, ranged, weaponskill, magic and puller Flash never broadcast elementals', function()
    for _, name in ipairs({'Dolomedes','Tackleberry'}) do
        for _, category in ipairs({1,2,3,4}) do
            local c = client(name)
            c.damage(c.elemental, category, 112)
            assert(#c.attacks() == 0)
            for _, message in ipairs(c.ipc) do
                assert(not message:find('|target|', 1, true))
            end
        end
    end
end)

test('a retained target that becomes excluded is released on every character', function()
    for _, name in ipairs(roster) do
        local c = client(name)
        c.share(c.normal)
        assert(#c.attacks() == 1)
        c.normal.name = "Demon's Elemental" -- exercises an already stored ID
        c.tick()
        assert(c.player.status == 0 and c.selected.id == c.self.id)
        assert(c.status():find('target none', 1, true))
        for _=1,20 do c.tick(0.6) end
        assert(#c.attacks() == 1, 'retained elemental was re-engaged')
    end
end)

test('game auto-targeting an elemental without a stored target is released', function()
    for _, name in ipairs(roster) do
        local c = client(name)
        c.select(c.elemental, true)
        c.tick()
        assert(c.player.status == 0 and c.selected.id == c.self.id)
        assert(#c.attacks() == 0)
    end
end)

test('an excluded peer message does not erase an allowed shared target', function()
    local c = client()
    c.share(c.normal)
    c.share(c.elemental, 'force')
    assert(c.status():find('target Apollyon Demon', 1, true))
    c.tick(2)
    assert(c.battle.id == c.normal.id)
end)

test('local elemental auto-target drift restores the retained non-elemental', function()
    local c = client('Achoo')
    c.share(c.normal)
    c.select(c.elemental, true)
    c.tick()
    assert(c.selected.id == c.normal.id and c.player.status == 0)
    c.tick(2)
    assert(c.battle.id == c.normal.id and c.player.status == 1)
    assert(c.turns > 0, 'allowed stationary target was not faced')
    for _, packet in ipairs(c.attacks()) do assert(packet.Target ~= c.elemental.id) end
end)

test('ordinary enemies, including an Elementalist name, still engage and face', function()
    for _, name in ipairs(roster) do
        for _, mob_name in ipairs({'Apollyon Demon','Locus Dire Bat','Breadwinner',
            'Bozzetto Urchin','Apex Crab','Elementalist'}) do
            local c = client(name)
            c.normal.name = mob_name
            c.share(c.normal)
            c.tick()
            assert(#c.attacks() > 0 and c.turns > 0, name..': '..mob_name)
        end
    end
end)

test('stationary auto holds while any directed force closes distance', function()
    local held = client('Dolomedes', '-')
    held.share(held.normal, 'auto')
    held.tick()
    for _, value in ipairs(held.runs) do
        assert(value == false, 'ordinary stationary synchronization moved')
    end

    for _, mode in ipairs({'forceid','forceopaqueid'}) do
        local moving = client('Dolomedes', '-')
        moving.normal.claim_id = moving.player.id
        if mode == 'forceopaqueid' then
            moving.normal.hpp = nil
            moving.command(mode, tostring(moving.normal.id), 'Apollyon_Demon')
        else
            moving.command(mode, tostring(moving.normal.id))
        end
        moving.tick()
        local translated = false
        for _, value in ipairs(moving.runs) do
            if value ~= false then translated = true end
        end
        assert(translated, mode .. ' did not close distance')
    end
end)

test('exclusion messages are globally rate-limited across different elemental IDs', function()
    local c = client()
    for id=200,230 do c.share(c.mob(id, 'Fire Elemental')) end
    local count = 0
    for _, message in ipairs(c.chats) do
        if message:find('Excluded elemental:', 1, true) then count = count + 1 end
    end
    assert(count == 1)
end)

test('stopped automation does not interfere with manual targeting', function()
    local c = client()
    c.command('stop')
    c.select(c.elemental, true)
    local packets = #c.packets
    c.tick(2)
    assert(c.player.status == 1 and c.selected.id == c.elemental.id)
    assert(#c.packets == packets)
end)

test('selecting another enemy never gets snapped away from the active battle target', function()
    local c = client('Dolomedes', '-')
    c.share(c.normal)
    c.tick()
    local alternate = c.mob(102, 'Bozzetto Tormentor')
    local packets = #c.packets
    c.select(alternate, false)
    c.tick(2)
    assert(c.selected.id == alternate.id,
        'PartyCombat overwrote the operator-selected enemy')
    assert(c.battle.id == c.normal.id,
        'selection alone unexpectedly changed the battle target')
    assert(#c.packets == packets,
        'maintaining an established battle target injected another packet')
end)

test('manual battle-target changes yield locally and old swings cannot reclaim control', function()
    local c = client('Dolomedes', '-')
    c.share(c.normal)
    c.tick()
    local alternate = c.mob(102, 'Bozzetto Tormentor')
    local packets = #c.packets
    local messages = target_message_count(c)
    c.select(alternate, true)
    c.tick()
    assert(c.selected.id == alternate.id and c.battle.id == alternate.id)
    assert(#c.packets == packets,
        'manual battle-target change was snapped back')
    assert(c.status():find('target none', 1, true),
        'manual override retained an automatic target lock')

    c.damage(c.normal, 1)
    assert(target_message_count(c) == messages,
        'an old shared-target swing reclaimed manual control')
    assert(c.selected.id == alternate.id)

    c.damage(alternate, 1)
    assert(target_message_count(c) == messages + 1,
        'leader damage on the manual target did not publish the new edge')
    assert(c.status():find('target Bozzetto Tormentor', 1, true))
end)

test('manual disengage remains disengaged until a new target edge', function()
    local c = client('Dolomedes', '-')
    c.share(c.normal)
    c.tick()
    local packets = #c.packets
    c.player.status, c.battle = 0, nil
    c.tick()
    c.tick(2)
    assert(c.player.status == 0 and #c.packets == packets,
        'PartyCombat re-engaged after a manual disengage')
    assert(c.status():find('target none', 1, true))
end)

test('target-only observers may select something else without snap-back', function()
    local c = client('Barneystinson', '-', {
        attacker_csv='Dolomedes', targeter_csv='Barneystinson',
    })
    c.share(c.normal)
    local alternate = c.mob(102, 'Bozzetto Tormentor')
    c.select(alternate, false)
    local packets = #c.packets
    c.tick(2)
    assert(c.selected.id == alternate.id and #c.packets == packets,
        'observer synchronization overwrote a manual target')
    assert(c.status():find('target none', 1, true))
end)

test('local fault containment never broadcasts a party stop', function()
    local stopped = client('Dolomedes', '-')
    local before_stop = #stopped.ipc
    stopped.command('localstop')
    assert(#stopped.ipc == before_stop,
        'localstop broadcast authority or stop to peer clients')
    assert(stopped.status():find('support-ready Yes', 1, true),
        'localstop discarded the reusable combat roster')

    local unloaded = client('Dolomedes', '-')
    local before_clear = #unloaded.ipc
    unloaded.command('localinvalidate', 'partytactics')
    assert(#unloaded.ipc == before_clear,
        'localinvalidate broadcast authority or stop to peer clients')
    assert(unloaded.status():find('support-ready No', 1, true),
        'localinvalidate retained a stale local combat roster')
end)

test('orchestrator reconciliation is silent local idempotent and fail closed', function()
    local c = client('Dolomedes', '-', {skip_authorize=true})
    local chats, ipc = #c.chats, #c.ipc
    c.command('reconcile', 'on')
    assert(#c.chats == chats and #c.ipc == ipc,
        'reconcile ON emitted chat or IPC')
    local local_commands = #c.commands
    c.command('reconcile', 'on')
    assert(#c.chats == chats and #c.ipc == ipc,
        'repeated reconcile ON emitted chat or IPC')
    assert(#c.commands == local_commands,
        'repeated reconcile ON replayed local activation work')

    c.damage(c.normal, 1)
    assert(target_message_count(c) == 1,
        'reconcile ON did not restore local controller authority')
    chats, ipc = #c.chats, #c.ipc
    c.command('reconcile', 'off')
    assert(#c.chats == chats and #c.ipc == ipc,
        'reconcile OFF emitted chat or IPC')
    c.damage(c.normal, 1)
    assert(target_message_count(c) == 1,
        'reconcile OFF left local controller authority active')

    -- Once the automation state is already inert, a periodic OFF repair must
    -- not disengage a later manual fight.
    c.select(c.normal, true)
    local commands = #c.commands
    c.command('reconcile', 'off')
    assert(#c.commands == commands and c.player.status == 1,
        'idempotent reconcile OFF interfered with manual combat')

    local missing = client('Dolomedes', '-', {skip_authorize=true})
    missing.command('localinvalidate', 'partytactics')
    chats, ipc = #missing.chats, #missing.ipc
    missing.command('reconcile', 'on')
    assert(#missing.chats == chats and #missing.ipc == ipc,
        'policy-less reconcile ON was not silent and local')
    assert(missing.status():find('support-ready No', 1, true)
        and missing.status():find('armed Off', 1, true),
        'policy-less reconcile ON did not remain fail closed')

    local outsider = client('Spectator', '-', {skip_authorize=true})
    chats, ipc = #outsider.chats, #outsider.ipc
    outsider.command('reconcile', 'on')
    assert(#outsider.chats == chats and #outsider.ipc == ipc,
        'foreign reconcile ON was not silent and local')
    assert(outsider.status():find('armed Off', 1, true),
        'foreign reconcile ON armed an unconfigured client')
end)

test('repeated explicit ON repairs authority without repeating chat', function()
    local c = client('Dolomedes', '-', {skip_authorize=true})
    local before = #c.chats
    c.command('on')
    assert(#c.chats == before + 1,
        'first explicit ON did not acknowledge the transition exactly once')
    local chats, ipc = #c.chats, #c.ipc
    c.command('on')
    assert(#c.chats == chats,
        'repeated explicit ON repeated the armed acknowledgement')
    assert(#c.ipc > ipc,
        'repeated explicit ON did not retain its authority repair broadcast')
end)

test('Salvage duo policy lets Dolo drive only Kick without a six-client barrier', function()
    local dolo = client('Dolomedes', '-', {skip_authorize=true})
    dolo.command('policy', 'salvage-duo', 'Dolomedes', 'Dolomedes',
        'Kickpuncher', 'Kickpuncher', 'mobile', '-', '-', '-')
    dolo.command('on')
    dolo.damage(dolo.normal, 1)
    assert(target_message_count(dolo) == 1,
        'Dolo did not broadcast his physical target')
    assert(#dolo.attacks() == 0,
        'controller-only Dolo was incorrectly driven by PartyCombat')

    local kick = client('Kickpuncher', '-', {skip_authorize=true})
    kick.command('policy', 'salvage-duo', 'Dolomedes', 'Dolomedes',
        'Kickpuncher', 'Kickpuncher', 'mobile', '-', '-', '-')
    kick.callbacks['ipc message']('PARTYCOMBAT1|authority|Dolomedes|Kickpuncher|1')
    kick.share(kick.normal, 'auto')
    assert(#kick.attacks() == 1 and kick.attacks()[1].Target == kick.normal.id,
        'Kick did not engage Dolo\'s shared target')

    local smalls = client('Smalls', '-', {skip_authorize=true})
    smalls.command('policy', 'salvage-duo', 'Dolomedes', 'Dolomedes',
        'Kickpuncher', 'Kickpuncher', 'mobile', '-', '-', '-')
    smalls.callbacks['ipc message']('PARTYCOMBAT1|authority|Dolomedes|Smalls|1')
    smalls.share(smalls.normal, 'force')
    assert(#smalls.attacks() == 0,
        'a character outside the duo was incorrectly engaged')
end)

test('Salvage emergency stop cannot be rearmed by force without a fresh policy', function()
    local dolo = client('Dolomedes', '-', {skip_authorize=true})
    dolo.command('policy', 'salvage-duo', 'Dolomedes', 'Dolomedes',
        'Kickpuncher', 'Kickpuncher', 'mobile', '-', '-', '-')
    dolo.command('on')
    dolo.command('stop')
    dolo.command('invalidate', 'partytactics')
    dolo.select(dolo.normal)
    dolo.command('force')
    assert(#dolo.attacks() == 0 and target_message_count(dolo) == 0,
        'force restarted an invalidated Salvage policy')
    assert(dolo.status():find('support-ready No', 1, true),
        'emergency stop left the runtime policy ready')
end)

print(('PASS %d PartyCombat elemental-exclusion runtime groups'):format(total))
