-- Deterministic orchestration tests for September V2 Alluttu.

local BASE = 'addons/PartyTactics/'
local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/ambuscade-2026-09-v2-hydra-alluttu/runtime.lua',
    loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()

local NAMES = {
    'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo',
}
local IDS = {
    Dolomedes=1, Tackleberry=2, Kickpuncher=3,
    Barneystinson=4, Smalls=5, Achoo=6,
}
local SPELL = {
    Barparalyzra=88, Flash=112, ThunderIV=167, MinuetIV=397,
    Crusade=476, GeoFrailty=818,
}
local WS = {Evisceration=25, SavageBlade=42, LastStand=221}
local JA = {
    Provoke=35, ShieldBash=46, Sentinel=48, BoxStep=202,
    ViolentFlourish=207, DivineEmblem=255, ClarionCall=332,
}
local MOVE = {
    PyricBlast=1828, PyricBulwark=1829, PolarBlast=1830,
    PolarBulwark=1831, Barofield=1832, Trembling=1834,
    SerpentineTail=1835, NerveGas=1836,
}

local function result(param, message, add_message, add_param)
    return {
        param=param == nil and 1 or param,
        message=message,
        add_effect_message=add_message,
        add_effect_param=add_param,
    }
end

local function action(category, source, param, target_id, target_result)
    return {
        category=category,
        actor_id=IDS[source] or source,
        param=param,
        targets={{id=target_id,
            actions={target_result or result(1)}}},
    }
end

local function party_action(category, source, param, included)
    local targets = {}
    local wanted = included or NAMES
    for _, name in ipairs(wanted) do
        targets[#targets + 1] = {id=IDS[name], actions={result(1)}}
    end
    return {
        category=category,
        actor_id=IDS[source] or source,
        param=param,
        targets=targets,
    }
end

local function move_ready(boss_id, move_id)
    return {
        category=7,
        actor_id=boss_id,
        targets={{id=IDS.Tackleberry, actions={{param=move_id}}}},
    }
end

local function move_complete(boss_id, move_id)
    return {
        category=6,
        actor_id=boss_id,
        param=move_id,
        targets={{id=IDS.Tackleberry, actions={result(500)}}},
    }
end

local function make_boss(id, options)
    options = options or {}
    return {
        id=id or 300,
        index=options.index or (id or 300) + 1000,
        name=options.name or 'Alluttu',
        spawn_type=16,
        valid_target=true,
        hpp=100,
        claim_id=options.claim_id or 0,
    }
end

local function make_harness(options)
    options = options or {}
    local h = {
        now=0,
        zone=options.zone or 287,
        armed=false,
        combat_ready=true,
        encounter_operational=true,
        can_authorize=true,
        authority=nil,
        party_hpp=100,
        tp={Dolomedes=0,Tackleberry=0,Kickpuncher=0},
        calls={}, clients={}, by_name={}, mobs={},
    }
    h.boss = make_boss(300, options.boss)
    h.mobs[1] = h.boss

    function h:mob_by_id(id)
        id = tonumber(id)
        for _, mob in ipairs(self.mobs) do
            if mob.id == id then return mob end
        end
        for name, member_id in pairs(IDS) do
            if member_id == id then return {id=member_id, name=name} end
        end
        return nil
    end

    function h:record(call)
        call.at = self.now
        self.calls[#self.calls + 1] = call
    end

    for _, name in ipairs(NAMES) do
        local client = {
            name=name,
            runtime=runtime_module.create(),
            auto_target={},
            alerts={},
        }
        h.clients[#h.clients + 1] = client
        h.by_name[name] = client
        client.context = {
            now=function() return h.now end,
            player_name=function() return client.name end,
            zone_id=function() return h.zone end,
            operator_armed=function() return h.armed end,
            combat_ready=function() return h.combat_ready end,
            current_target=function() return nil end,
            mob_by_id=function(id) return h:mob_by_id(id) end,
            mob_array=function() return h.mobs end,
            party_claimed=function(mob)
                return mob and tonumber(mob.claim_id) == IDS.Dolomedes
            end,
            party_hpp_floor=function() return h.party_hpp end,
            party_tp=function(member) return h.tp[member] end,
            authorize_encounter=function(id)
                h:record({kind='authorize', caller=client.name, id=id})
                if not h.can_authorize or h.authority and h.authority ~= id then
                    return false
                end
                h.authority = id
                return true
            end,
            encounter_ready=function(id)
                return h.encounter_operational and h.authority == id
            end,
            release_encounter=function(id)
                h:record({kind='release', caller=client.name, id=id})
                if h.authority ~= id then return false end
                h.authority = nil
                return true
            end,
            alert=function(message, audible)
                client.alerts[#client.alerts + 1] = {
                    message=message, audible=audible, at=h.now,
                }
            end,
            actions={
                party_adapter=function(recipient, semantic, id, token,
                    subject_id)
                    h:record({
                        kind='controller', caller=client.name,
                        recipient=recipient, semantic=semantic,
                        id=id, token=token, subject_id=subject_id,
                    })
                    return true
                end,
                combat_force=function(id)
                    h:record({kind='force', caller=client.name, id=id})
                    return true
                end,
                combat_stop=function()
                    h:record({kind='stop', caller=client.name})
                    return true
                end,
            },
            client={
                auto_target=function(enabled)
                    client.auto_target[#client.auto_target + 1] = enabled
                    return true
                end,
            },
        }
    end

    function h:activate()
        for _, client in ipairs(self.clients) do
            client.runtime:on_activate(client.context)
        end
    end

    function h:deactivate()
        for _, client in ipairs(self.clients) do
            client.runtime:on_deactivate(client.context)
        end
    end

    function h:tick(at)
        self.now = at
        for _, client in ipairs(self.clients) do
            client.runtime:on_tick(client.context, at)
        end
    end

    function h:perform(packet, at)
        self.now = at or self.now
        for _, client in ipairs(self.clients) do
            client.runtime:on_action(client.context, packet)
        end
    end

    function h:count(kind, fields)
        local total = 0
        for _, call in ipairs(self.calls) do
            local match = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then match = false end
            end
            if match then total = total + 1 end
        end
        return total
    end

    function h:last(kind, fields)
        for index = #self.calls, 1, -1 do
            local call = self.calls[index]
            local match = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then match = false end
            end
            if match then return call end
        end
        return nil
    end

    return h
end

local function prove_opening(h, omit_box)
    h.armed = true
    h:tick(0)
    h:tick(4.0)
    h:perform(action(4, 'Tackleberry', SPELL.Crusade,
        IDS.Tackleberry), 4.1)
    h:tick(4.4)
    h:perform(action(6, 'Tackleberry', JA.DivineEmblem,
        IDS.Tackleberry), 4.5)
    h:tick(4.8)
    h:perform(action(6, 'Tackleberry', JA.Sentinel,
        IDS.Tackleberry), 4.9)
    h:tick(10.0)
    h:perform(action(4, 'Tackleberry', SPELL.Flash,
        h.boss.id), 10.1)
    h.boss.claim_id = IDS.Dolomedes
    h:tick(10.4)
    h:perform(action(4, 'Achoo', SPELL.GeoFrailty,
        h.boss.id), 10.5)
    if not omit_box then
        h:perform(action(6, 'Kickpuncher', JA.BoxStep,
            h.boss.id), 10.6)
    end
    h:tick(10.9)
end

local function ready_tp(h)
    h.tp.Dolomedes = 1200
    h.tp.Tackleberry = 1200
    h.tp.Kickpuncher = 1200
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name, callback=callback}
end

test('arm gate and packet-confirmed PLD pull precede engagement', function()
    local h = make_harness()
    h:activate()
    for _, client in ipairs(h.clients) do
        assert(client.auto_target[1] == false)
    end
    h:tick(0)
    assert(h:count('authorize') == 0)
    assert(h:count('controller') == 0)
    assert(h:count('force') == 0)

    h.armed = true
    h:tick(0.3)
    assert(h:count('authorize') == 1)
    assert(h:last('authorize').caller == 'Dolomedes')
    assert(h:count('force') == 0)
    assert(h:count('controller', {semantic='food'}) == 3)

    -- Out-of-order packets cannot skip the opener.
    h:perform(action(6, 'Tackleberry', JA.Sentinel,
        IDS.Tackleberry), 1)
    h:tick(4.3)
    assert(h:last('controller', {recipient='Tackleberry'}).semantic
        == 'crusade')
    h:perform(action(4, 'Tackleberry', SPELL.Crusade,
        IDS.Tackleberry), 4.4)
    h:tick(4.7)
    assert(h:last('controller', {recipient='Tackleberry'}).semantic
        == 'divine-emblem')
    h:perform(action(6, 'Tackleberry', JA.DivineEmblem,
        IDS.Tackleberry), 4.8)
    h:tick(5.2)
    h:perform(action(6, 'Tackleberry', JA.Sentinel,
        IDS.Tackleberry), 5.2)
    h:tick(10.4)
    assert(h:last('controller', {recipient='Tackleberry'}).semantic
        == 'pull-flash')
    h.boss.claim_id = IDS.Dolomedes
    h:tick(10.5)
    assert(h:count('force') == 0,
        'party claim without a confirmed Tackle Flash must not engage')
    h:perform(action(4, 'Tackleberry', SPELL.Flash, h.boss.id), 10.6)
    h:tick(10.8)
    assert(h:count('force') == 1)
    assert(h:last('force').id == h.boss.id)
end)

test('exact identity, claim, zones, and ID reuse fail closed', function()
    local wrong = make_harness({boss={name='Alluttu Prime'}})
    wrong:activate()
    wrong.armed = true
    wrong:tick(0)
    assert(wrong:count('authorize') == 0)

    local foreign = make_harness({boss={claim_id=999999}})
    foreign:activate()
    foreign.armed = true
    foreign:tick(0)
    assert(foreign:count('authorize') == 0)

    for _, index in ipairs({-1, 1.5, 65536}) do
        local malformed = make_harness({boss={index=index}})
        malformed:activate()
        malformed.armed = true
        malformed:tick(0)
        assert(malformed:count('authorize') == 0,
            'malformed entity index was accepted: '..tostring(index))
    end

    for _, zone in ipairs({183,287}) do
        local accepted = make_harness({zone=zone})
        accepted:activate()
        accepted.armed = true
        accepted:tick(0)
        assert(accepted:count('authorize') == 1)
    end

    local reused = make_harness()
    reused:activate()
    reused.armed = true
    reused:tick(0)
    reused.boss.index = reused.boss.index + 1
    reused:tick(0.3)
    assert(reused:count('release') == 1)
    assert(reused:count('stop') >= 1)
end)

test('food and Clarion are automatic but never pull dependencies', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h:count('controller', {semantic='food'}) == 3)
    assert(h:count('controller', {recipient='Barneystinson',
        semantic='clarion'}) == 1)
    -- No Clarion result arrives. The PLD opener still advances and reaches
    -- Flash, proving the optional fourth song cannot stall a farm attempt.
    h:tick(4)
    h:perform(action(4, 'Tackleberry', SPELL.Crusade,
        IDS.Tackleberry), 4.1)
    h:tick(4.4)
    h:perform(action(6, 'Tackleberry', JA.DivineEmblem,
        IDS.Tackleberry), 4.5)
    h:tick(4.8)
    h:perform(action(6, 'Tackleberry', JA.Sentinel,
        IDS.Tackleberry), 4.9)
    h:tick(10)
    assert(h:count('controller', {semantic='pull-flash'}) >= 1)
end)

test('attacker food heartbeat persists beyond initial setup and retries late', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h:count('controller', {semantic='food'}) == 3)
    h:tick(4.9)
    assert(h:count('controller', {semantic='food'}) == 3)
    h:tick(5.2)
    assert(h:count('controller', {semantic='food'}) == 6,
        'observed '..tostring(h:count('controller', {semantic='food'})))
    h:tick(15.3)
    assert(h:count('controller', {semantic='food'}) == 9,
        'food heartbeat stopped after the original preparation window')
end)

test('packet-confirmed Fragmentation and Light order both bursts', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:tick(20)
    assert(h:last('controller', {semantic='lead'}).recipient
        == 'Kickpuncher')
    h:perform(action(3, 'Kickpuncher', WS.Evisceration, h.boss.id,
        result(5000, 1)), 20.1)
    h:tick(22.9)
    assert(h:count('controller', {semantic='middle'}) == 0)
    h:tick(23.3)
    assert(h:last('controller', {semantic='middle'}).recipient
        == 'Tackleberry')
    h:perform(action(3, 'Tackleberry', WS.SavageBlade, h.boss.id,
        result(8000, 1, 291, 4000)), 23.4)
    h:tick(26.6)
    assert(h:last('controller', {semantic='close'}).recipient
        == 'Dolomedes')
    h:perform(action(3, 'Dolomedes', WS.LastStand, h.boss.id,
        result(9000, 1, 288, 7000)), 26.7)
    h:tick(27.0)
    h:tick(27.2)
    assert(h:count('controller', {semantic='burst',
        recipient='Smalls'}) >= 1)
    assert(h:count('controller', {semantic='burst',
        recipient='Achoo'}) >= 1)
end)

test('a missing Fragmentation packet suppresses Last Stand and bursts', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:tick(20)
    h:perform(action(3, 'Kickpuncher', WS.Evisceration, h.boss.id,
        result(5000, 1)), 20.1)
    h:tick(23.3)
    h:perform(action(3, 'Tackleberry', WS.SavageBlade, h.boss.id,
        result(8000, 1, 290, 4000)), 23.4)
    h:tick(26.7)
    assert(h:count('controller', {semantic='close'}) == 0)
    assert(h:count('controller', {semantic='burst'}) == 0)
    assert(h:count('controller', {semantic='cancel'}) >= 5)
end)

test('Nerve Gas and Polar ready use DNC stun with PLD fallback', function()
    local primary = make_harness()
    primary:activate()
    prove_opening(primary)
    primary:perform(move_ready(primary.boss.id, MOVE.NerveGas), 15)
    for _, member in ipairs({
        'Dolomedes','Tackleberry','Kickpuncher','Smalls','Achoo',
    }) do
        assert(primary:count('controller', {semantic='cancel',
            recipient=member}) >= 1,
            'stun barrier left stale offense queued on '..member)
    end
    primary:tick(15.1)
    assert(primary:count('controller', {semantic='stun',
        recipient='Kickpuncher'}) >= 1)
    primary:perform(action(6, 'Kickpuncher', JA.ViolentFlourish,
        primary.boss.id), 15.2)
    primary:tick(15.9)
    assert(primary:count('controller', {semantic='shield-bash'}) >= 1,
        'an executed Violent Flourish incorrectly suppressed the PLD fallback')

    local fallback = make_harness()
    fallback:activate()
    prove_opening(fallback)
    fallback:perform(move_ready(fallback.boss.id,
        MOVE.PolarBulwark), 15)
    local kick_cancels = fallback:count('controller', {
        semantic='cancel', recipient='Kickpuncher'})
    local tackle_cancels = fallback:count('controller', {
        semantic='cancel', recipient='Tackleberry'})
    fallback:tick(15.1)
    fallback:tick(15.8)
    assert(fallback:count('controller', {semantic='stun',
        recipient='Kickpuncher'}) >= 1)
    assert(fallback:count('controller', {semantic='shield-bash',
        recipient='Tackleberry'}) >= 1)
    ready_tp(fallback)
    fallback:tick(18.1)
    assert(fallback:count('controller', {semantic='cancel',
        recipient='Kickpuncher'}) == kick_cancels + 1)
    assert(fallback:count('controller', {semantic='cancel',
        recipient='Tackleberry'}) == tackle_cancels + 1)
    assert(fallback:count('controller', {semantic='lead'}) >= 1,
        'expired stun lane prevented the next legal chain')
end)

test('executed stuns retire spent lanes and timeout cancels both', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    h:perform(move_ready(h.boss.id, MOVE.NerveGas), 15)
    h:tick(15.1)
    h:tick(15.8)
    assert(h:count('controller', {semantic='stun',
        recipient='Kickpuncher'}) >= 1)
    assert(h:count('controller', {semantic='shield-bash',
        recipient='Tackleberry'}) >= 1)
    local kick_cancels = h:count('controller', {
        semantic='cancel', recipient='Kickpuncher'})
    local tackle_cancels = h:count('controller', {
        semantic='cancel', recipient='Tackleberry'})
    h:perform(action(6, 'Kickpuncher', JA.ViolentFlourish,
        h.boss.id), 15.9)
    assert(h:count('controller', {semantic='cancel',
        recipient='Kickpuncher'}) == kick_cancels + 1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Tackleberry'}) == tackle_cancels)
    h:tick(18.1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Kickpuncher'}) == kick_cancels + 2)
    assert(h:count('controller', {semantic='cancel',
        recipient='Tackleberry'}) == tackle_cancels + 1)
end)

test('monster completion retires both stun queues before barrier release', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    h:perform(move_ready(h.boss.id, MOVE.NerveGas), 15)
    h:tick(15.1)
    h:tick(15.8)
    h:perform(action(6, 'Kickpuncher', JA.ViolentFlourish,
        h.boss.id), 15.9)
    local kick_cancels = h:count('controller', {
        semantic='cancel', recipient='Kickpuncher'})
    local tackle_cancels = h:count('controller', {
        semantic='cancel', recipient='Tackleberry'})
    h:perform(move_complete(h.boss.id, MOVE.NerveGas), 16.0)
    assert(h:count('controller', {semantic='cancel',
        recipient='Kickpuncher'}) >= kick_cancels + 1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Tackleberry'}) >= tackle_cancels + 1)
    ready_tp(h)
    h:tick(28.1)
    assert(h:count('controller', {semantic='lead'}) >= 1,
        'completed monster move left the stun barrier or stale queues live')
end)

test('unconfirmed optional PLD preparation skips and never deadlocks a rerun', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    h:tick(4.0)
    h:tick(4.8)
    h:tick(5.6)
    h:tick(6.4)
    assert(h:count('controller', {semantic='crusade'}) == 3)
    h:tick(6.7)
    h:tick(7.5)
    h:tick(8.3)
    h:tick(9.1)
    assert(h:count('controller', {semantic='divine-emblem'}) == 3)
    h:tick(9.4)
    h:tick(10.2)
    h:tick(11.0)
    h:tick(11.8)
    assert(h:count('controller', {semantic='sentinel'}) == 3)
    h:tick(12.1)
    assert(h:count('controller', {semantic='pull-flash'}) == 1)
    local alerts = h.by_name.Dolomedes.alerts
    local found = 0
    for _, entry in ipairs(alerts) do
        if entry.message:find('OPTIONAL PLD PREP SKIPPED', 1, true) then
            found = found + 1
            assert(entry.audible == true)
        end
    end
    assert(found == 3)
    h:perform(action(4, 'Tackleberry', SPELL.Flash, h.boss.id), 12.2)
    h.boss.claim_id = IDS.Dolomedes
    h:tick(12.5)
    assert(h:count('force') == 1,
        'successful exact Flash did not release the bounded opener')
end)

test('mandatory Flash uses bounded retry cycles and never engages unconfirmed', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    h:tick(4.0)
    h:tick(4.8)
    h:tick(5.6)
    h:tick(6.4)
    h:tick(6.7)
    h:tick(7.5)
    h:tick(8.3)
    h:tick(9.1)
    h:tick(9.4)
    h:tick(10.2)
    h:tick(11.0)
    h:tick(11.8)
    h:tick(12.1)
    h:tick(12.9)
    h:tick(13.7)
    h.boss.claim_id = IDS.Dolomedes
    h:tick(14.5)
    assert(h:count('controller', {semantic='pull-flash'}) == 3)
    assert(h:count('force') == 0,
        'party claim engaged without a successful Tackle Flash packet')
    h.boss.claim_id = 0
    h:tick(17.6)
    assert(h:count('controller', {semantic='pull-flash'}) == 4,
        'exhausted exact Flash queue did not rearm after backoff')
end)

test('Polar stops physical work and Pyric restores it while blocking magic', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    local stops_before = h:count('stop')
    h:perform(move_complete(h.boss.id, MOVE.PolarBulwark), 16)
    assert(h:count('stop') == stops_before + 1)
    h:tick(16.2)
    assert(h:count('controller', {semantic='nuke', recipient='Smalls'}) >= 1)
    h:tick(16.5)
    assert(h:count('controller', {semantic='nuke', recipient='Achoo'}) >= 1)
    assert(h:count('controller', {semantic='lead'}) == 0)

    local force_before = h:count('force')
    h:perform(move_complete(h.boss.id, MOVE.PyricBulwark), 17)
    assert(h:count('force') == force_before + 1)
    local nukes = h:count('controller', {semantic='nuke'})
    h:tick(18.2)
    assert(h:count('controller', {semantic='nuke'}) == nukes)
    assert(h:count('controller', {semantic='lead'}) >= 1,
        'physical chain did not resume under magic shield')
end)

test('natural Polar expiry cancels fallback nukes before physical resume', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    h:perform(move_complete(h.boss.id, MOVE.PolarBulwark), 16)
    h:tick(16.2)
    h:tick(16.6)
    local smalls_cancels = h:count('controller', {
        semantic='cancel', recipient='Smalls'})
    local achoo_cancels = h:count('controller', {
        semantic='cancel', recipient='Achoo'})
    local force_before = h:count('force')
    h:tick(81.1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Smalls'}) == smalls_cancels + 1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Achoo'}) == achoo_cancels + 1)
    assert(h:count('force') == force_before + 1,
        'PartyCombat did not resume after caster lanes were retired')
end)

test('damage yields through recovery and resumes only at the 85 percent floor', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:perform(move_complete(h.boss.id, MOVE.NerveGas), 20)
    h:tick(25)
    assert(h:count('controller', {semantic='lead'}) == 0)
    h.party_hpp = 84
    h:tick(33)
    assert(h:count('controller', {semantic='lead'}) == 0)
    h.party_hpp = 85
    h:tick(33.3)
    assert(h:count('controller', {semantic='lead'}) >= 1)
end)

test('fourth song and Barparalyzra require six-member AoE packet coverage', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    h:perform(action(6, 'Barneystinson', JA.ClarionCall,
        IDS.Barneystinson), 0.1)
    h:tick(0.8)
    assert(h:count('controller', {semantic='fourth-song'}) == 1)
    h:perform(party_action(4, 'Barneystinson', SPELL.MinuetIV,
        {'Barneystinson'}), 0.9)
    h:tick(2.4)
    assert(h:count('controller', {semantic='fourth-song'}) == 2,
        'self-only fourth-song result was accepted as party coverage')
    h:perform(party_action(4, 'Barneystinson', SPELL.MinuetIV), 2.5)
    h:tick(4.1)
    assert(h:count('controller', {semantic='barparalyzra'}) == 1)
    h:perform(party_action(4, 'Barneystinson', SPELL.Barparalyzra,
        {'Barneystinson'}), 4.2)
    h:tick(5.8)
    assert(h:count('controller', {semantic='barparalyzra'}) == 2,
        'self-only Barparalyzra result was accepted as party coverage')
    h:perform(party_action(4, 'Barneystinson', SPELL.Barparalyzra), 5.9)
    h:tick(7.5)
    assert(h:count('controller', {semantic='barparalyzra'}) == 2)
end)

test('missed initial Barparalyzra rearms later without blocking offense', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:tick(13.0)
    h:tick(14.6)
    h:tick(16.2)
    h:tick(17.8)
    h:tick(20.2)
    assert(h:count('controller', {recipient='Barneystinson',
        semantic='barparalyzra', token='refresh-bar'}) == 1,
        'initial all-party Barparalyzra miss was never rearmed')
    assert(h:count('controller', {semantic='lead'}) >= 1,
        'nonblocking Barparalyzra recovery stalled offense')
    h:perform(party_action(4, 'Barneystinson',
        SPELL.Barparalyzra), 20.3)
    local refreshes = h:count('controller', {recipient='Barneystinson',
        semantic='barparalyzra', token='refresh-bar'})
    h:tick(21.9)
    assert(h:count('controller', {recipient='Barneystinson',
        semantic='barparalyzra', token='refresh-bar'}) == refreshes)
end)

test('opening and periodic Box Step use finite windows and chain backoff', function()
    local h = make_harness()
    h:activate()
    prove_opening(h, true)
    h:tick(11.7)
    h:tick(12.5)
    ready_tp(h)
    h:tick(15.5)
    assert(h:count('controller', {semantic='box-step'}) == 3)
    assert(h:count('controller', {semantic='cancel',
        recipient='Kickpuncher'}) >= 1)
    assert(h:count('controller', {semantic='lead'}) == 1,
        'opening Box Step timeout stalled the damage loop')

    h:perform(action(3, 'Kickpuncher', WS.Evisceration, h.boss.id,
        result(0, 1)), 15.6)
    h.tp.Dolomedes, h.tp.Tackleberry, h.tp.Kickpuncher = 0, 0, 0
    h:tick(35.6)
    h:tick(36.4)
    h:tick(37.2)
    ready_tp(h)
    h:tick(40.7)
    assert(h:count('controller', {semantic='box-step'}) == 6)
    assert(h:count('controller', {semantic='lead'}) == 2,
        'periodic Box Step timeout did not release the chain during backoff')
end)

test('Trembling rearms repeatable buffs after recovery without hiding cures', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:perform(move_complete(h.boss.id, MOVE.Trembling), 20)
    h:tick(27.9)
    assert(h:count('controller', {token='refresh-geo'}) == 0)
    h.party_hpp = 84
    h:tick(28.2)
    assert(h:count('controller', {token='refresh-geo'}) == 0)
    h.party_hpp = 85
    h:tick(28.5)
    assert(h:count('controller', {recipient='Achoo',
        semantic='setup', token='refresh-geo'}) == 1)
    assert(h:count('controller', {recipient='Barneystinson',
        semantic='barparalyzra', token='refresh-bar'}) == 1)
    assert(h:count('controller', {recipient='Tackleberry',
        semantic='crusade', token='refresh-crusade'}) == 1)
    assert(h:count('controller', {semantic='lead'}) == 0)
    h:perform(action(4, 'Achoo', SPELL.GeoFrailty, h.boss.id), 28.6)
    h:perform(party_action(4, 'Barneystinson',
        SPELL.Barparalyzra), 28.7)
    h:perform(action(4, 'Tackleberry', SPELL.Crusade,
        IDS.Tackleberry), 28.8)
    h:tick(30.6)
    assert(h:count('controller', {semantic='lead'}) >= 1)
end)

test('confirmed buff expiry rearms through a bounded maintenance window', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:tick(20)
    h:perform(action(3, 'Kickpuncher', WS.Evisceration, h.boss.id,
        result(5000, 1)), 20.1)
    local cancels_before = h:count('controller', {semantic='cancel'})
    h:tick(190.6)
    assert(h:count('controller', {semantic='cancel'})
        >= cancels_before + 5,
        'scheduled maintenance did not retire a mid-chain transaction')
    assert(h:count('controller', {semantic='middle'}) == 0)
    assert(h:count('controller', {recipient='Achoo',
        semantic='setup', token='refresh-geo'}) == 1)
    h:tick(192.2)
    h:tick(193.8)
    h:tick(202.7)
    assert(h:count('controller', {recipient='Achoo',
        semantic='setup', token='refresh-geo'}) == 3)
    assert(h:count('controller', {recipient='Achoo',
        semantic='cancel'}) >= 1,
        'expired Geo refresh remained queued beyond its deadline')
end)

test('magic-burst expiry cancels both outstanding caster queues', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    ready_tp(h)
    h:tick(20)
    h:perform(action(3, 'Kickpuncher', WS.Evisceration, h.boss.id,
        result(5000, 1)), 20.1)
    h:tick(23.3)
    h:perform(action(3, 'Tackleberry', WS.SavageBlade, h.boss.id,
        result(8000, 1, 291, 4000)), 23.4)
    h:tick(26.6)
    h:perform(action(3, 'Dolomedes', WS.LastStand, h.boss.id,
        result(9000, 1, 288, 7000)), 26.7)
    h:tick(27.0)
    h:tick(36.0)
    assert(h:count('controller', {semantic='cancel',
        recipient='Smalls'}) >= 1)
    assert(h:count('controller', {semantic='cancel',
        recipient='Achoo'}) >= 1)
end)

test('any party death cancels globally stops combat and consumes the arm', function()
    local h = make_harness()
    h:activate()
    prove_opening(h)
    h.party_hpp = 0
    h:tick(11.2)
    assert(h:count('controller', {semantic='cancel'}) >= 6)
    assert(h:count('stop') >= 1)
    assert(h:count('release') == 1)
    local authorizations = h:count('authorize')
    h.party_hpp = 100
    h.boss = make_boss(301)
    h.mobs = {h.boss}
    h:tick(11.5)
    assert(h:count('authorize') == authorizations,
        'latched arm restarted after a party death')
    h.armed = false
    h:tick(11.8)
    h.armed = true
    h:tick(12.1)
    assert(h:count('authorize') == authorizations + 1)
end)

test('victory consumes arm and a new life requires a fresh arm edge', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h:count('authorize') == 1)
    h.boss.hpp = 0
    h:tick(1)
    assert(h:count('release') == 1)
    h.boss = make_boss(301)
    h.mobs = {h.boss}
    h:tick(2)
    assert(h:count('authorize') == 1,
        'latched arm authorized a second encounter')
    h.armed = false
    h:tick(2.3)
    h.armed = true
    h:tick(2.6)
    assert(h:count('authorize') == 2)
    assert(h:last('authorize').id == 301)
end)

test('disarm and deactivation cancel release and restore client preference', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    h.armed = false
    h:tick(0.3)
    assert(h:count('release') == 1)
    assert(h:count('stop') >= 1)
    assert(h:count('controller', {semantic='cancel'}) >= 6)

    h.armed = true
    h:tick(0.6)
    h:deactivate()
    for _, client in ipairs(h.clients) do
        assert(client.auto_target[1] == false)
        assert(client.auto_target[#client.auto_target] == true)
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
assert(passed == 23)
print(('PASS PartyTactics September Hydra runtime: %d cases'):format(passed))
