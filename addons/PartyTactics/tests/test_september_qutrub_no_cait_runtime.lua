-- Deterministic cooperative-runtime tests for no-Cait Bozzetto Bigwig.

local BASE = 'addons/PartyTactics/'
local sandbox_loader, sandbox_error = loadfile(BASE..'lib/sandbox.lua')
assert(sandbox_loader, sandbox_error)
local sandbox = sandbox_loader()
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/ambuscade-2026-09-v1-qutrub-bigwig-no-cait/'
        ..'runtime.lua', loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()

local IDS = {
    Dolomedes=1, Tackleberry=2, Kickpuncher=3,
    Barneystinson=4, Smalls=5, Achoo=6,
}

local function make_harness(options)
    options = options or {}
    local h = {
        now=0, zone=options.zone or 287, armed=false,
        authority=nil, calls={}, selected=nil, mobs={}, members={},
        tp={
            Dolomedes=options.dolo_tp or 0,
            Tackleberry=options.tackle_tp or 0,
            Kickpuncher=options.kick_tp or 0,
            Barneystinson=options.barney_tp or 0,
        },
    }
    h.boss = {
        id=300, index=1300, name=options.name or 'Bozzetto Bigwig',
        spawn_type=16, valid_target=true, hpp=100,
        claim_id=options.foreign and 999999 or 0,
        x=0, y=0, distance=4,
    }
    h.mobs[#h.mobs + 1] = h.boss
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher',
        'Barneystinson','Smalls','Achoo',
    } do
        local mob = {
            id=IDS[name], index=IDS[name], name=name,
            valid_target=true, hpp=100,
            x=name == 'Tackleberry' and (options.tackle_x or 30) or 2,
            y=0, distance=4,
        }
        h.members[name] = mob
        h.mobs[#h.mobs + 1] = mob
    end
    h.runtime = runtime_module.create()

    function h:record(call)
        call.at = self.now
        self.calls[#self.calls + 1] = call
    end
    function h:count(kind, fields)
        local count = 0
        for _, call in ipairs(self.calls) do
            local matches = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then matches = false end
            end
            if matches then count = count + 1 end
        end
        return count
    end
    function h:last(kind, fields)
        for index=#self.calls,1,-1 do
            local call = self.calls[index]
            local matches = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then matches = false end
            end
            if matches then return call end
        end
    end
    function h:mob_by_id(id)
        id = tonumber(id)
        for _, mob in ipairs(self.mobs) do
            if mob.id == id then return mob end
        end
        return nil
    end
    function h:add(name, id, add_options)
        add_options = add_options or {}
        local mob = {
            id=id, index=id + 1000, name=name, spawn_type=16,
            valid_target=true, hpp=100, claim_id=IDS.Dolomedes,
            x=add_options.x or 30, y=add_options.y or 0, distance=4,
        }
        self.mobs[#self.mobs + 1] = mob
        return mob
    end
    function h:remove(mob)
        mob.valid_target = false
        mob.hpp = 0
    end
    function h:claim()
        self.boss.claim_id = IDS.Dolomedes
    end

    h.context = {
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        operator_armed=function() return h.armed end,
        current_target=function() return h.selected end,
        mob_array=function() return h.mobs end,
        mob_by_id=function(id) return h:mob_by_id(id) end,
        party_claimed=function(mob)
            local claim = mob and tonumber(mob.claim_id) or 0
            for _, id in pairs(IDS) do
                if claim == id then return true end
            end
            return false
        end,
        party_tp=function(name) return h.tp[name] end,
        authorize_encounter=function(id)
            h:record({kind='authorize', id=id})
            if options.authorization_fails then return false end
            h.authority = id
            return true
        end,
        release_encounter=function(id)
            h:record({kind='release', id=id})
            h.authority = nil
            return true
        end,
        monster_ability=function(id)
            local names = {
                [7001]='Triple Reversal',[7002]='Perfect Dodge',
                [7003]='Phantom Whorl',[7004]='Fortifying Wail',
                [7005]='Animating Wail',
            }
            return names[tonumber(id)] and {en=names[tonumber(id)]} or nil
        end,
        job_ability=function(id)
            return tonumber(id) == 131 and {en='Light Shot'} or nil
        end,
        spell=function(id)
            local names = {
                [250]='Ice Spikes',[340]='Utsusemi: San',
                [25]='Dia III',[260]='Dispel',[592]='Blank Gaze',
                [259]='Sleep II',[273]='Sleepga',[274]='Sleepga II',
            }
            return names[tonumber(id)] and {en=names[tonumber(id)]} or nil
        end,
        actions={
            party_adapter=function(recipient, semantic, id, token, subject)
                h:record({kind='controller', recipient=recipient,
                    semantic=semantic, id=id, token=token, subject=subject})
                if options.reject_semantic == semantic then return false end
                return true
            end,
            combat_force=function(id)
                h:record({kind='force', id=id})
                h.selected = h:mob_by_id(id)
                return options.force_fails ~= true
            end,
            combat_force_members=function(id, members)
                h:record({kind='force-members', id=id,
                    members=table.concat(members, ',')})
                h.selected = h:mob_by_id(id)
                return options.force_fails ~= true
            end,
            combat_stop_members=function(members)
                h:record({kind='stop-members',
                    members=table.concat(members, ',')})
                return true
            end,
            combat_stop=function()
                h:record({kind='stop'})
                return true
            end,
        },
    }

    function h:activate() self.runtime:on_activate(self.context) end
    function h:tick(at)
        self.now = at
        self.runtime:on_tick(self.context, at)
    end
    function h:action(packet, at)
        self.now = at
        self.runtime:on_action(self.context, packet)
    end
    function h:boss_targets(name, at)
        self:action({
            category=1, actor_id=self.boss.id, target_count=1,
            targets={{id=assert(IDS[name]), actions={{message=1,param=10}}}},
        }, at)
    end
    function h:add_targets(add, name, at)
        self:action({
            category=1, actor_id=add.id, target_count=1,
            targets={{id=assert(IDS[name]), actions={{message=1,param=10}}}},
        }, at)
    end
    function h:boss_aoe_targets(primary, secondary, at)
        self:action({
            category=7, actor_id=self.boss.id, target_count=2,
            targets={
                {id=assert(IDS[secondary]), actions={{message=31,param=7001}}},
                {id=assert(IDS[primary]), actions={{message=185,param=7001}}},
            },
        }, at)
    end
    return h
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name, callback=callback}
end

test('runtime stays stopped while operator state is off', function()
    local h = make_harness()
    h:activate()
    h:tick(0)
    h:tick(10)
    assert(#h.calls == 0)
end)

test('arm prepares in place until the operator pull starts combat',
function()
    local h = make_harness({
        authorization_fails=true, reject_semantic='pull', force_fails=true,
        dolo_tp=3000, kick_tp=3000, barney_tp=3000,
    })
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h:count('authorize', {id=h.boss.id}) == 1)
    assert(h:count('force-members') == 0,
        'arming moved an attacker before the operator pull')
    assert(h:count('stop-members') == 0,
        'arming changed a combat assignment before the operator pull')
    assert(h:count('controller', {semantic='reraise'}) == 6)
    h:tick(1.25)
    h:tick(2.5)
    h:tick(3.75)
    h:tick(5.0)
    h:tick(6.25)
    h:tick(7.5)
    h:tick(8.75)
    h:tick(10.0)
    h:tick(11.25)
    h:tick(12.5)
    assert(h:count('controller', {semantic='food'}) == 4)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='cocoon'}) >= 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='crusade'}) >= 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='reprisal'}) >= 1)
    assert(h:count('controller', {
        recipient='Achoo', semantic='frailty-target', subject=h.boss.id}) == 0,
        'preparation cast hostile GEO magic before the operator pull')
    assert(h:count('controller', {
        recipient='Smalls', semantic='dia-iii', subject=h.boss.id}) == 0,
        'preparation cast Dia before the operator pull')
    assert(h:count('controller', {semantic='slow-ii'}) == 0)
    assert(h:count('controller', {semantic='paralyze-ii'}) == 0)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='pull'}) == 0)
    for _, name in ipairs{'Dolomedes','Kickpuncher','Barneystinson'} do
        assert(h:count('controller', {
            recipient=name, semantic='shadow-ni'}) >= 1)
        assert(h:count('controller', {
            recipient=name, semantic='shadow-ichi'}) >= 1)
    end
    assert(h:count('force-members') == 0,
        'defensive maintenance released combat without a pull')

    h:claim()
    h:tick(13.75)
    assert(h:count('force-members', {
        id=h.boss.id, members='Dolomedes,Kickpuncher,Barneystinson'}) == 1,
        'the observed party claim did not release the boss trio')
    assert(h:count('stop-members', {
        members='Tackleberry,Achoo'}) == 1)
    assert(h:count('controller', {
        recipient='Achoo', semantic='frailty-target', subject=h.boss.id}) >= 1)
    assert(h:count('controller', {
        recipient='Smalls', semantic='dia-iii', subject=h.boss.id}) >= 1)
    for _, semantic in ipairs{'lead','middle','close'} do
        assert(h:count('controller', {semantic=semantic}) == 0)
    end
    assert(h:count('stop') == 0)
end)

test('manual Dolo attack releases combat before claim color catches up',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h.boss.claim_id == 0)
    h:action({
        category=1, actor_id=IDS.Dolomedes, target_count=1,
        targets={{id=h.boss.id, actions={{message=1,param=10}}}},
    }, .1)
    assert(h.runtime.pull_started == true,
        'the exact manual Bigwig action did not release combat')
    h:tick(.3)
    assert(h:count('force-members', {
        id=h.boss.id, members='Dolomedes,Kickpuncher,Barneystinson'}) == 1)
end)

test('Normal anchors every spawn before all five smash one Astrologer', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local first = h:add('Bozzetto Tormentor', 401)
    local astrologer = h:add('Bozzetto Astrologer', 402)
    local second = h:add('Bozzetto Tormentor', 403)
    h:tick(1)

    assert(h.runtime.parked_target_by_owner.Tackleberry == first.id)
    assert(h.runtime.parked_target_by_owner.Kickpuncher == second.id)
    assert(h:last('force-members', {
        id=first.id, members='Tackleberry',
    }), 'Tackle did not receive the first parked Tormentor pickup')
    assert(h:last('force-members', {
        id=second.id, members='Kickpuncher',
    }), 'the non-Bigwig member did not receive the second pickup')
    assert(h:last('force-members', {
        id=astrologer.id, members='Achoo',
    }), 'Achoo did not receive the Astrologer anchor')
    assert(not h.runtime.combat_targets.Dolomedes)
    assert(not h.runtime.combat_targets.Barneystinson)

    h:tick(4)
    assert(h.runtime.wave_assembling == true)
    h:add_targets(first, 'Tackleberry', 6.8)
    h:add_targets(second, 'Kickpuncher', 6.9)
    local before_collapse = #h.calls
    h:tick(7.3)
    assert(h.runtime.wave_assembling == false)
    for index=before_collapse + 1,#h.calls do
        assert(h.calls[index].kind ~= 'stop-members',
            'target-to-target focus collapse emitted a late disengage edge')
    end
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == astrologer.id,
            name..' did not return to the one shared focus')
    end
    assert(h.runtime.combat_targets.Dolomedes == astrologer.id,
        'Bigwig holder did not join after bounded assembly')
end)

test('Bigwig holder chooses only the second parked owner, never a spectator',
function()
    for index, holder in ipairs{'Dolomedes','Kickpuncher'} do
        local h = make_harness()
        h:activate()
        h.armed = true
        h:claim()
        h:tick(0)
        h:boss_targets(holder, .5)
        local astrologer = h:add('Bozzetto Astrologer', 460 + index * 10)
        local first = h:add('Bozzetto Tormentor', 461 + index * 10)
        local second = h:add('Bozzetto Tormentor', 462 + index * 10)
        h:tick(1)
        local nonholder = holder == 'Dolomedes'
            and 'Kickpuncher' or 'Dolomedes'
        assert(h.runtime.wave_holder == holder)
        assert(h.runtime.parked_target_by_owner.Tackleberry == first.id)
        assert(h.runtime.parked_target_by_owner[nonholder] == second.id)
        assert(h.runtime.parked_target_by_owner[holder] == nil,
            'Bigwig holder was assigned an off-focus add')
        h:add_targets(first, 'Tackleberry', 6.8)
        h:add_targets(second, nonholder, 6.9)
        h:tick(7.3)
        assert(h.runtime.combat_targets[holder] == astrologer.id)
        assert(h.runtime.combat_targets[nonholder] == astrologer.id)
    end
end)

test('five-second Bigwig review safely hands off parked ownership', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 490)
    local first = h:add('Bozzetto Tormentor', 491)
    local second = h:add('Bozzetto Tormentor', 492)
    h:tick(1)
    h:add_targets(first, 'Tackleberry', 6.8)
    h:add_targets(second, 'Kickpuncher', 6.9)
    h:tick(7.3)
    assert(h.runtime.wave_holder == 'Dolomedes')
    assert(h.runtime.parked_target_by_owner.Tackleberry == first.id)
    assert(h.runtime.parked_target_by_owner.Kickpuncher == second.id)
    assert(h.runtime.combat_targets.Dolomedes == astrologer.id)
    assert(h.runtime.combat_targets.Kickpuncher == astrologer.id)

    h:boss_targets('Kickpuncher', 8)
    h:tick(10)
    assert(h.runtime.wave_holder == 'Dolomedes',
        'holder ownership thrashed before its review boundary')
    h:tick(12.4)
    assert(h.runtime.wave_holder == 'Kickpuncher')
    assert(h.runtime.parked_target_by_owner.Dolomedes == second.id)
    assert(h.runtime.parked_target_by_owner.Kickpuncher == nil)
    assert(h.runtime.combat_targets.Dolomedes == second.id,
        'new nonholder did not receive the short parked pickup')
    assert(not h.runtime.combat_targets.Kickpuncher,
        'new Bigwig holder joined focus before parked hate transferred')

    h:add_targets(second, 'Dolomedes', 12.6)
    h:tick(12.7)
    assert(h.runtime.combat_targets.Kickpuncher == astrologer.id,
        'direct ownership evidence did not release the new holder')
    h:tick(15.1)
    assert(h.runtime.combat_targets.Dolomedes == astrologer.id)
    assert(h.runtime.combat_targets.Kickpuncher == astrologer.id)
    h:add_targets(second, 'Kickpuncher', 15.2)
    h:tick(15.4)
    assert(h.runtime.combat_targets.Dolomedes == second.id,
        'transferred parked ownership inherited a stale repair lockout')
end)

test('a squirmy parked add gets one pickup repair per drift episode',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 500)
    local parked = h:add('Bozzetto Tormentor', 501)
    h:add('Bozzetto Tormentor', 502)
    h:tick(1)
    h:add_targets(parked, 'Tackleberry', 6.9)
    h:tick(7.3)
    assert(h.runtime.combat_targets.Tackleberry == astrologer.id)

    h:add_targets(parked, 'Kickpuncher', 7.5)
    h:tick(7.6)
    assert(h.runtime.combat_targets.Tackleberry == parked.id)
    local repair_count = h:count('force-members', {
        id=parked.id, members='Tackleberry',
    })
    assert(repair_count >= 2,
        'parked-add drift did not issue a fresh Tackle pickup')

    h:add_targets(parked, 'Kickpuncher', 7.8)
    h:tick(8.5)
    assert(h:count('force-members', {
        id=parked.id, members='Tackleberry',
    }) == repair_count,
        'the same drift episode created a repeated target-snap loop')
    h:add_targets(parked, 'Tackleberry', 8.7)
    h:tick(8.8)
    assert(h.runtime.combat_targets.Tackleberry == astrologer.id,
        'Tackle did not return to the common focus after recapture')
end)

test('AoE primary-target evidence matches Bars for parking ownership',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_aoe_targets('Kickpuncher', 'Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 470)
    h:add('Bozzetto Tormentor', 471)
    local second = h:add('Bozzetto Tormentor', 472)
    h:tick(1)
    assert(h.runtime.wave_holder == 'Kickpuncher')
    assert(h.runtime.parked_target_by_owner.Dolomedes == second.id)
    h:tick(7.3)
    assert(h.runtime.combat_targets.Kickpuncher == astrologer.id)
end)

test('stale holder evidence keeps sequential assembly safe', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .25)
    local astrologer = h:add('Bozzetto Astrologer', 480)
    h:add('Bozzetto Tormentor', 481)
    local second = h:add('Bozzetto Tormentor', 482)
    h:tick(8)
    assert(h.runtime.wave_holder == nil)
    assert(h.runtime.parked_target_by_owner.Tackleberry ~= nil)
    assert(h.runtime.parked_target_by_owner.Dolomedes == nil)
    assert(h.runtime.parked_target_by_owner.Kickpuncher == nil)
    assert(not h.runtime.combat_targets.Dolomedes)
    assert(not h.runtime.combat_targets.Kickpuncher)
    assert(h.runtime.combat_targets.Achoo == astrologer.id)

    h:boss_targets('Kickpuncher', 8.25)
    h:tick(8.5)
    assert(h.runtime.wave_holder == 'Kickpuncher')
    assert(h.runtime.parked_target_by_owner.Dolomedes == second.id,
        'fresh holder evidence did not assign the nonholder pickup')
    h:tick(14.8)
    assert(h.runtime.combat_targets.Kickpuncher == astrologer.id)
end)

test('Tackle controls one parked add instead of blanketing all three',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 404)
    local first = h:add('Bozzetto Tormentor', 405)
    local second = h:add('Bozzetto Tormentor', 406)
    h:tick(1)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='box-step-add', subject=second.id,
    }) == 0, 'DNC spent its one Step before closing into melee range')
    h.members.Kickpuncher.x = second.x
    h:tick(2.3)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash-add', subject=first.id,
    }) >= 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash-add', subject=second.id,
    }) == 0, 'Tackle attempted to acquire a third add target')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash-add', subject=astrologer.id,
    }) == 0, 'Tackle blanketed the shared focus on Normal')
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='box-step-add', subject=second.id,
    }) >= 1, 'the nonholder did not tag the second parked add')
    local step_attempts = h:count('controller', {
        recipient='Kickpuncher', semantic='box-step-add', subject=second.id,
    })
    h:tick(5.5)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='box-step-add', subject=second.id,
    }) == step_attempts, 'DNC pickup entered an unconfirmed action loop')
    assert(h:count('controller', {
        recipient='Achoo', semantic='flash-add', subject=astrologer.id,
    }) >= 1, 'Achoo did not Flash-anchor the Astrologer')
    assert(h:count('controller', {semantic='sentinel-add'}) == 0)
    assert(h:count('controller', {semantic='palisade-add'}) == 0)
end)

test('ranged pickup waits for direct ownership evidence',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Kickpuncher', .5)
    local astrologer = h:add('Bozzetto Astrologer', 407)
    local first = h:add('Bozzetto Tormentor', 408)
    local second = h:add('Bozzetto Tormentor', 409)
    h.members.Dolomedes.x = second.x - 20
    h:tick(1)
    h:tick(2.5)
    local key = tostring(second.id)..':'..tostring(second.index)
    local attempts = h:count('controller', {
        recipient='Dolomedes', semantic='light-shot-target',
        subject=second.id,
    })
    assert(attempts == 1, 'Dolo did not receive one exact pickup tag')
    h:action({category=6, actor_id=IDS.Dolomedes, param=131,
        targets={{id=second.id, actions={{message=324,param=131}}}}}, 2.6)
    assert(h.runtime.anchor_confirmed_by_key[key] == nil,
        'the Light Shot result was mistaken for target ownership')
    h:tick(5.5)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='light-shot-target',
        subject=second.id,
    }) == attempts, 'unconfirmed Light Shot entered a blind retry loop')
    h:add_targets(second, 'Dolomedes', 5.7)
    assert(h.runtime.anchor_confirmed_by_key[key] == 'Dolomedes',
        'direct hostile target evidence did not confirm Dolo ownership')
    h:add_targets(first, 'Tackleberry', 6.8)
    h:tick(7.3)
    assert(h.runtime.combat_targets.Dolomedes == astrologer.id,
        'confirmed ranged owner did not release to the common focus')
end)

test('compact live resource names bind Bigwig and its truncated adds',
function()
    local h = make_harness({name='BozzettoBigwig'})
    h:activate()
    h.armed = true
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('BozzettoTormen', 405)
    h:tick(1)
    h:tick(2.5)
    h:tick(7.5)
    assert(h:count('authorize', {id=h.boss.id}) == 1)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == add.id)
    end
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash-add',
        subject=add.id}) >= 1)
end)

test('unsafe area geometry skips only area tags, never exact capture or combat',
function()
    local h = make_harness({tackle_x=2})
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Tormentor', 406, {x=3})
    h:tick(1.25)
    h:tick(2.5)
    h:tick(3.75)
    h:tick(5.0)
    h:tick(7.75)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == add.id)
    end
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash-add',
        subject=add.id}) >= 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=add.id}) >= 1)
    for _, semantic in ipairs{
        'jettatura-add','geist-wall-add','sheep-song-add',
    } do
        assert(h:count('controller', {semantic=semantic}) == 0)
    end
    assert(h:count('stop') == 0)
end)

test('fifteen-yalm compact split enables pack control after Tackle arrives',
function()
    local h = make_harness({tackle_x=10.5})
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Tormentor', 407, {x=15})
    for _, at in ipairs{1.25,2.5,3.75} do h:tick(at) end
    h:add_targets(add, 'Tackleberry', 4)
    for _, at in ipairs{5,6.25,7.5,8.75,10,11.25,12.5,13.75} do
        h:tick(at)
    end
    for _, semantic in ipairs{
        'jettatura-add','geist-wall-add','sheep-song-add',
    } do
        assert(h:count('controller', {
            recipient='Tackleberry', semantic=semantic,
            subject=add.id,
        }) >= 1, semantic..' did not accept compact 15-yalm geometry')
    end
end)

test('a rejected add tag cannot stop targeting or support lanes', function()
    local h = make_harness({
        reject_semantic='flash-add',
        dolo_tp=3000, kick_tp=3000, barney_tp=3000,
    })
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Astrologer', 410)
    h:tick(1.25)
    h:tick(2.5)
    h:tick(3.75)
    h:tick(7.75)
    assert(h:count('controller', {
        recipient='Achoo', semantic='flash-add', subject=add.id}) >= 1)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == add.id)
    end
    assert(h:count('controller', {
        recipient='Smalls', semantic='silence-add', subject=add.id}) >= 1)
    assert(h:count('controller', {
        recipient='Achoo', semantic='entrust'}) == 1)
    assert(h:count('controller', {
        recipient='Achoo', semantic='indi-wilt',
        subject=IDS.Tackleberry}) == 1,
        'hostile focus transition deleted wave-start Indi-Wilt')
    assert(h:count('stop') == 0)
end)

test('arrived add attackers stick only when they separate from the focus',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:tick(0)
    h:tick(1)
    h:tick(2)
    assert(h:count('force-members') == 0,
        'pre-pull preparation assigned the boss trio')
    h:boss_targets('Dolomedes', 2.5)
    local add = h:add('Bozzetto Tormentor', 420)
    h:tick(3)
    assert(h:last('force-members', {
        id=add.id, members='Tackleberry',
    }), 'assembly did not give the sole add to its exact anchor')
    h:tick(9.5)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == add.id)
    end
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        h.members[name].x = add.x
    end
    h:tick(10.8)
    h.members.Kickpuncher.x = 10
    h:tick(12.1)
    assert(h:last('force-members', {
        id=add.id, members='Kickpuncher',
    }), 'a separated arrived attacker was not returned to the shared add')
    local repair_count = h:count('force-members', {
        id=add.id, members='Kickpuncher',
    })
    h:tick(12.7)
    assert(h:count('force-members', {
        id=add.id, members='Kickpuncher',
    }) == repair_count,
        'sticky pursuit repeatedly snapped a still-separated attacker')
    local tackle_edges = h:count('force-members', {
        id=add.id, members='Tackleberry',
    })
    h.members.Kickpuncher.x = add.x
    h.members.Tackleberry.x = add.x - 3
    h:tick(14)
    assert(h:count('force-members', {
        id=add.id, members='Tackleberry',
    }) == tackle_edges,
        'movement inside the add pack was treated as a target override')
end)

local function member_force_count(h, id, name)
    local count = 0
    for _, call in ipairs(h.calls) do
        if call.kind == 'force-members' and call.id == id
            and (','..call.members..','):find(','..name..',', 1, true)
        then
            count = count + 1
        end
    end
    return count
end

test('a stalled initial add acquire gets one bounded exact repair', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Tormentor', 460)
    h:tick(1)
    h:tick(7.5)
    local initial = member_force_count(h, add.id, 'Dolomedes')
    assert(initial == 1)
    for _, at in ipairs{8.75,10,11.25,12.5,15,20} do h:tick(at) end
    assert(member_force_count(h, add.id, 'Dolomedes') == initial + 1,
        'a dropped initial engage was not repaired exactly once')
end)

test('moving or attacking toward an add does not get acquire spam',
function()
    local moving = make_harness()
    moving:activate()
    moving.armed = true
    moving:claim()
    moving:tick(0)
    moving:boss_targets('Dolomedes', .5)
    local add = moving:add('Bozzetto Tormentor', 461)
    moving:tick(1)
    moving:tick(7.5)
    moving.members.Dolomedes.x = 10
    moving:tick(8.75)
    moving.members.Dolomedes.x = 15
    moving:tick(10)
    moving.members.Dolomedes.x = 20
    moving:tick(11.25)
    moving.members.Dolomedes.x = 24
    moving:tick(12.5)
    assert(member_force_count(moving, add.id, 'Dolomedes') == 1,
        'a member closing to the add was forced a second time')

    local attacking = make_harness()
    attacking:activate()
    attacking.armed = true
    attacking:claim()
    attacking:tick(0)
    attacking:boss_targets('Dolomedes', .5)
    local target = attacking:add('Bozzetto Tormentor', 462)
    attacking:tick(1)
    attacking:tick(7.5)
    attacking:action({category=1, actor_id=IDS.Dolomedes,
        targets={{id=target.id, actions={{message=1,param=100}}}}}, 8)
    for _, at in ipairs{8.75,10,11.25,12.5,15} do attacking:tick(at) end
    assert(member_force_count(attacking, target.id, 'Dolomedes') == 1,
        'a completed attack on the correct add did not prove acquisition')
end)

test('the final surviving add gets a fresh bounded acquire repair',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local first = h:add('Bozzetto Tormentor', 463)
    h:tick(1)
    local astrologer = h:add('Bozzetto Astrologer', 464)
    h:tick(6)
    local last = h:add('Bozzetto Tormentor', 465)
    h:tick(11)
    h:tick(17.5)
    h:remove(astrologer)
    h:tick(18.75)
    h:remove(first)
    h:tick(20)
    assert(h.runtime.combat_targets.Dolomedes == last.id)
    local initial = member_force_count(h, last.id, 'Dolomedes')
    for _, at in ipairs{21.25,22.5,23.75,25,27} do h:tick(at) end
    assert(member_force_count(h, last.id, 'Dolomedes') == initial + 1,
        'the last Tormentor inherited a stale no-retry handoff')
end)

test('each focus gets Dia then one nonstacking Light Shot and exact Frailty',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Astrologer', 421, {x=10})
    for _, at in ipairs{1,2.5,3.75,5,6.25,7.5,8.75,10} do h:tick(at) end
    assert(h:last('controller', {
        recipient='Smalls', semantic='dia-iii', subject=add.id,
    }), 'Smalls did not apply Dia III to the current add focus')
    assert(h:last('controller', {
        recipient='Achoo', semantic='frailty-target', subject=add.id,
    }), 'Achoo did not place exact Frailty after reaching the add focus')

    h:action({category=4, actor_id=IDS.Smalls, param=25,
        targets={{id=add.id, actions={{message=230,param=134}}}}}, 10.1)
    h:tick(11.4)
    assert(h:last('controller', {
        recipient='Dolomedes', semantic='light-shot-target', subject=add.id,
    }), 'completed Dia III did not enable one exact Light Shot')
    local first_attempts = h:count('controller', {
        recipient='Dolomedes', semantic='light-shot-target', subject=add.id,
    })
    h:action({category=6, actor_id=IDS.Dolomedes, param=131,
        targets={{id=add.id, actions={{message=324,param=131}}}}}, 11.5)
    h:tick(40)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='light-shot-target', subject=add.id,
    }) == first_attempts,
        'sleep-miss result incorrectly repeated nonstacking Dia enhancement')
end)

test('an unconfirmed focus Dia retries without pretending the request landed',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local add = h:add('Bozzetto Astrologer', 425, {x=10})
    for _, at in ipairs{1,2.5,3.75,5,6.25,7.5,8.75,10} do h:tick(at) end
    local first = h:count('controller', {
        recipient='Smalls', semantic='dia-iii', subject=add.id,
    })
    assert(first == 1, 'focus Dia did not make its first bounded attempt')
    for _, at in ipairs{15,16.25,17.5} do h:tick(at) end
    assert(h:count('controller', {
        recipient='Smalls', semantic='dia-iii', subject=add.id,
    }) == first + 1, 'missing Dia result was treated as success')
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='light-shot-target', subject=add.id,
    }) == 0, 'Light Shot ran before packet-confirmed Dia')
end)

test('Wail cleanup follows only the active focus and confirms removal',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local tormentor = h:add('Bozzetto Tormentor', 422)
    local astrologer = h:add('Bozzetto Astrologer', 423)
    for _, at in ipairs{1,2.5,3.75,5,7.5} do h:tick(at) end
    local before_tormentor = h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=tormentor.id,
    })
    local before_astrologer = h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=astrologer.id,
    })
    h.runtime.tasks = {}
    h.runtime.next_member_action.Tackleberry = 0
    h:action({category=7, actor_id=tormentor.id, target_count=2,
        targets={
            {id=tormentor.id, actions={{param=7005,message=230}}},
            {id=astrologer.id, actions={{param=7005,message=266}}},
        }}, 8)
    h:tick(8.1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=astrologer.id,
    }) > before_astrologer,
        'Tackle did not Gaze the protected common focus')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=tormentor.id,
    }) == before_tormentor, 'Wail cleanup touched a parked off-focus add')
    assert(h:count('controller', {semantic='geist-wall-add'}) == 0,
        'Wail cleanup used an area dispel')
    -- Removing an unrelated dispellable effect must not falsely retire the
    -- remembered Wail buff.
    h:action({category=4, actor_id=IDS.Tackleberry, param=592,
        targets={{id=astrologer.id,
            actions={{message=342,param=34}}}}}, 8.2)
    h:tick(11.7)
    assert(h:count('controller', {
        recipient='Smalls', semantic='dispel-ice-spikes',
        subject=astrologer.id,
    }) >= 1, 'unconfirmed Wail removal did not receive Dispel fallback')
    h:action({category=4, actor_id=IDS.Smalls, param=260,
        targets={{id=astrologer.id,
            actions={{message=341,param=33}}}}}, 11.8)
    local cleared =
        h:count('controller', {
            semantic='blank-gaze-add', subject=astrologer.id,
        }) +
        h:count('controller', {
            semantic='dispel-ice-spikes', subject=astrologer.id,
        })
    h:tick(20)
    local after =
        h:count('controller', {
            semantic='blank-gaze-add', subject=astrologer.id,
        }) +
        h:count('controller', {
            semantic='dispel-ice-spikes', subject=astrologer.id,
        })
    assert(after == cleared,
        'confirmed Wail removal kept retrying')
end)

test('healing coalesces periodic work without merging Dispel reactions',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 424, {x=10})
    for _, at in ipairs{1,2.5,3.75,5,7.5} do h:tick(at) end
    h.runtime.tasks = {}
    h.runtime.next_member_action.Tackleberry = 0
    h.runtime.next_member_action.Smalls = 0
    h.members.Dolomedes.hpp = 50

    h:action({category=7, actor_id=astrologer.id, target_count=1,
        targets={{id=astrologer.id,
            actions={{param=7004,message=230}}}}}, 8)
    h:tick(8.1)
    h:action({category=4, actor_id=astrologer.id, param=250,
        targets={{id=astrologer.id,
            actions={{param=250,message=230}}}}}, 11.6)
    h:tick(11.7)
    for _, at in ipairs{15.3,18.9,22.5} do h:tick(at) end

    local pending_dispels = 0
    local pending_wail = 0
    for _, task in pairs(h.runtime.tasks) do
        if task.recipient == 'Smalls'
            and task.semantic == 'dispel-ice-spikes'
            and task.subject_id == astrologer.id
        then
            pending_dispels = pending_dispels + 1
        end
        if task.tracking and task.tracking.kind == 'focus-wail' then
            pending_wail = pending_wail + 1
        end
    end
    assert(pending_dispels == 2,
        'Ice Spikes and Wail fallback collapsed into one Dispel intent')
    assert(pending_wail == 1,
        'healing accumulated Wail fallbacks or consumed their retry budget')

    h.members.Dolomedes.hpp = 100
    local before = h:count('controller', {
        recipient='Smalls', semantic='dispel-ice-spikes',
        subject=astrologer.id,
    })
    h:tick(24)
    h:tick(25.3)
    assert(h:count('controller', {
        recipient='Smalls', semantic='dispel-ice-spikes',
        subject=astrologer.id,
    }) == before + 2,
        'both independent Dispel intents did not resume after recovery')
end)

test('three-add Wail alternates exact focus Gaze and Dispel only', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 510)
    local tackle_parked = h:add('Bozzetto Tormentor', 511)
    local other_parked = h:add('Bozzetto Tormentor', 512)
    for _, at in ipairs{1,2.5,3.75,5,7.5} do h:tick(at) end
    assert(h.runtime.parked_target_by_owner.Tackleberry
        == tackle_parked.id)
    assert(h.runtime.parked_target_by_owner.Kickpuncher
        == other_parked.id)

    local before_tackle_parked = h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=tackle_parked.id,
    })
    local before_astro = h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=astrologer.id,
    })
    h.runtime.tasks = {}
    h.runtime.next_member_action.Tackleberry = 0
    h.runtime.next_member_action.Smalls = 0
    h:action({category=7, actor_id=tackle_parked.id, target_count=3,
        targets={
            {id=tackle_parked.id, actions={{param=7004,message=230}}},
            {id=astrologer.id, actions={{param=7004,message=266}}},
            {id=other_parked.id, actions={{param=7004,message=266}}},
        }}, 8)
    h:tick(8.1)
    h:tick(11.7)
    assert(h:count('controller', {semantic='geist-wall-add'}) == 0,
        'Geist Wall touched all three adds and recreated Triple risk')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=astrologer.id,
    }) > before_astro,
        'Tackle did not Gaze the shared focus on a three-add wave')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=other_parked.id,
    }) == 0,
        'Tackle Gazed the other owner\'s parked target')
    assert(h:count('controller', {
        recipient='Smalls', semantic='dispel-ice-spikes',
        subject=astrologer.id,
    }) >= 1, 'failed/unconfirmed focus Gaze did not fall back to Dispel')
    assert(h:count('controller', {
        recipient='Smalls', semantic='dispel-ice-spikes',
        subject=other_parked.id,
    }) == 0, 'Smalls Dispel acquired a parked off-focus add')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='blank-gaze-add',
        subject=tackle_parked.id,
    }) == before_tackle_parked,
        'Tackle acquired its parked add during focus cleanup')
end)

test('low HP and Utsusemi San reactions never hold targeting or support',
function()
    local h = make_harness({
        dolo_tp=3000, kick_tp=3000, barney_tp=3000,
    })
    h:activate()
    h.armed = true
    h:claim()
    h.boss.hpp = 20
    h:tick(0)
    h:action({category=4, actor_id=h.boss.id, param=340,
        targets={{id=h.boss.id, actions={{param=1}}}}}, .5)
    h:tick(1.25)
    h:tick(2.5)
    h:tick(3.75)
    h:tick(5.0)
    assert(h:count('controller', {
        recipient='Smalls', semantic='diaga', subject=h.boss.id}) >= 1)
    assert(h:count('force-members', {
        id=h.boss.id, members='Dolomedes,Kickpuncher,Barneystinson'}) == 1)
    assert(h:count('stop') == 0)
end)

test('Phantom Whorl readiness immediately tops all eligible shadow users',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:action({category=7, actor_id=h.boss.id,
        targets={{id=IDS.Kickpuncher,
            actions={{param=7003,message=43}}}}}, .5)
    -- The Whorl reaction preempts queued setup work at the next legal
    -- per-character action slot; it does not bypass spell/global lockout.
    h:tick(1.25)
    for _, name in ipairs{'Dolomedes','Kickpuncher','Barneystinson'} do
        assert(h:count('controller', {
            recipient=name, semantic='shadow-ni'}) >= 1,
            name..' did not receive the immediate Whorl Ni request')
    end
    h:tick(2.5)
    for _, name in ipairs{'Dolomedes','Kickpuncher','Barneystinson'} do
        assert(h:count('controller', {
            recipient=name, semantic='shadow-ichi'}) >= 1,
            name..' did not retain an Ichi fallback')
    end
end)

test('temporary yellow claim state never ends a bound live encounter',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h.boss.claim_id = 0
    h:tick(3)
    h:tick(12)
    assert(h:count('release', {id=h.boss.id}) == 0,
        'temporary claim loss silently released encounter authority')
    for _, name in ipairs{'Dolomedes','Kickpuncher','Barneystinson'} do
        assert(h:count('controller', {
            recipient=name, semantic='shadow-ni'}) >= 1,
            name..' shadow watchdog stopped after Bigwig went yellow')
    end
    assert(h.runtime.encounter_id == h.boss.id)
end)

test('Triple Reversal reaction is additive and does not pause targeting',
function()
    local h = make_harness({
        dolo_tp=3000, kick_tp=3000, barney_tp=3000,
    })
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .25)
    local add = h:add('Bozzetto Tormentor', 430)
    h:action({category=7, actor_id=add.id,
        targets={{id=IDS.Tackleberry, actions={{param=7001}}}}}, .5)
    h:tick(1.25)
    h:tick(2.5)
    h:tick(3.75)
    h:tick(5.0)
    h:tick(7.75)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='stun-add', subject=add.id}) == 1)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == add.id)
    end
    assert(h:count('stop') == 0)
end)

test('Bigwig Triple Reversal also receives the exact stun reaction',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:action({category=7, actor_id=h.boss.id,
        targets={{id=IDS.Dolomedes, actions={{param=7001}}}}}, .5)
    h:tick(1.25)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='stun-add',
        subject=h.boss.id}) == 1,
        'Bigwig Triple Reversal bypassed the stun reaction')
end)

test('sequential Normal spawns extend assembly before common focus',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)

    local first = h:add('Bozzetto Tormentor', 431)
    h:tick(1)
    assert(h.runtime.combat_targets.Tackleberry == first.id)
    assert(not h.runtime.combat_targets.Dolomedes)

    local astrologer = h:add('Bozzetto Astrologer', 432)
    h:tick(6)
    assert(h.runtime.wave_assembling == true)
    assert(h.runtime.combat_targets.Achoo == astrologer.id)
    assert(h.runtime.combat_targets.Tackleberry == first.id)

    local second = h:add('Bozzetto Tormentor', 433)
    h:tick(11)
    assert(h.runtime.wave_assembling == true)
    assert(h.runtime.combat_targets.Kickpuncher == second.id)
    assert(not h.runtime.combat_targets.Dolomedes)
    assert(not h.runtime.combat_targets.Barneystinson)
    assert(h:count('controller', {semantic='jettatura-add'}) == 0,
        'area enmity fired while a third Normal add could still spawn')
    assert(h:count('controller', {semantic='sentinel'}) == 0)
    assert(h:count('controller', {semantic='palisade'}) == 0)

    h:add_targets(first, 'Tackleberry', 16.8)
    h:add_targets(second, 'Kickpuncher', 16.9)
    h:tick(17.3)
    assert(h.runtime.wave_assembling == false)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == astrologer.id,
            name..' did not collapse after the final spawn quiet interval')
    end
end)

test('observed three-target convergence stops and automatically clears',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 434)
    h:add('Bozzetto Tormentor', 435)
    local second = h:add('Bozzetto Tormentor', 436)
    h:tick(1)
    h:tick(7.3)

    h:boss_targets('Dolomedes', 7.6)
    h:add_targets(astrologer, 'Dolomedes', 7.7)
    h:add_targets(second, 'Dolomedes', 7.8)
    h:tick(8)
    assert(h.runtime.threat_holds.Dolomedes == true)
    assert(not h.runtime.combat_targets.Dolomedes)
    local stopped_dolo = false
    for _, call in ipairs(h.calls) do
        if call.kind == 'stop-members'
            and call.members:find('Dolomedes', 1, true)
        then
            stopped_dolo = true
        end
    end
    assert(stopped_dolo,
        'dangerous three-target convergence did not get one stop edge')

    h:add_targets(astrologer, 'Achoo', 8.2)
    h:add_targets(second, 'Kickpuncher', 8.3)
    h:tick(8.4)
    assert(not h.runtime.threat_holds.Dolomedes)
    assert(h.runtime.combat_targets.Dolomedes == astrologer.id,
        'Dolo did not return to focus after targets redistributed')
end)

test('hostile spell targets never masquerade as enmity owners', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local astrologer = h:add('Bozzetto Astrologer', 437)
    h:tick(1)
    h:action({category=4, actor_id=astrologer.id, param=273,
        targets={{id=IDS.Barneystinson, actions={{param=273}}}}}, 1.2)
    assert(h.runtime.add_target_by_key[
        tostring(astrologer.id)..':'..tostring(astrologer.index)] == nil)
    h:action({category=4, actor_id=h.boss.id, param=259,
        targets={{id=IDS.Kickpuncher, actions={{param=259}}}}}, 1.3)
    assert(h.runtime.boss_target_name == 'Dolomedes',
        'a spell target replaced the observed Bigwig hate holder')
end)

test('Smalls cures the exact lowest member through 74 then resumes tactics',
function()
    local boundary = make_harness()
    boundary:activate()
    boundary.armed = true
    boundary:claim()
    boundary.members.Dolomedes.hpp = 75
    boundary:tick(0)
    assert(boundary:count('controller', {
        recipient='Smalls', semantic='support-cure'}) == 0,
        'Smalls primary healing incorrectly included 75 percent')

    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h.members.Dolomedes.hpp = 74
    h.members.Barneystinson.hpp = 50
    h:tick(0)
    assert(h:count('controller', {
        recipient='Smalls', semantic='support-cure',
        subject=IDS.Barneystinson}) == 1,
        'Smalls did not cure the exact lowest living member immediately')
    assert(h:count('controller', {recipient='Smalls'}) == 1,
        'Smalls tactical work collided with the primary Cure slot')

    h.members.Barneystinson.hpp = 100
    h:tick(1.3)
    assert(h:count('controller', {
        recipient='Smalls', semantic='support-cure',
        subject=IDS.Dolomedes}) == 1,
        'Smalls did not include the exact 74-percent boundary')

    h.members.Dolomedes.hpp = 100
    h:tick(2.6)
    assert(h:count('controller', {
        recipient='Smalls', semantic='reraise'}) == 1,
        'deferred Smalls work did not resume after HP recovered')
end)

test('out-of-range damage cannot starve Smalls tactical work', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h.members.Dolomedes.hpp = 10
    h.members.Dolomedes.x = 100
    h:tick(0)
    assert(h:count('controller', {
        recipient='Smalls', semantic='support-cure'}) == 0,
        'runtime queued a cure outside Smalls\' known 20.5-yalm range')
    assert(h:count('controller', {
        recipient='Smalls', semantic='reraise'}) == 1,
        'an out-of-range injured member starved Smalls tactical work')

    h.members.Dolomedes.x = 10
    h:tick(1.3)
    assert(h:count('controller', {
        recipient='Smalls', semantic='support-cure',
        subject=IDS.Dolomedes}) == 1,
        'the same injured member did not preempt tactics after entering range')
end)

test('Smalls primary cures and delayed Tackle backup remain independent',
function()
    local h = make_harness({tackle_x=2})
    h:activate()
    h.armed = true
    h:claim()
    h.members.Kickpuncher.hpp = 40
    h:tick(0)
    assert(h:count('controller', {
        recipient='Smalls', semantic='support-cure',
        subject=IDS.Kickpuncher}) == 1,
        'Smalls did not own the immediate exact Cure IV')
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='emergency-cure'}) == 0,
        'Tackle backup ignored its independent delay')
    h:add('Bozzetto Astrologer', 481)
    h:tick(1.3)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='emergency-cure',
        subject=IDS.Kickpuncher}) == 1,
        'Tackle did not provide the delayed 40-percent Cure IV backup')

    local final = make_harness()
    final:activate()
    final.armed = true
    final:claim()
    final.boss.hpp = 20
    final.members.Dolomedes.hpp = 74
    final:tick(0)
    assert(final:count('controller', {
        recipient='Smalls', semantic='support-cure',
        subject=IDS.Dolomedes}) == 1,
        'final phase incorrectly lowered or disabled the 74-percent threshold')
    assert(final:count('controller', {
        recipient='Tackleberry', semantic='emergency-cure'}) == 0,
        'Tackle treated a 74-percent target as its critical backup band')

    local far = make_harness({tackle_x=30})
    far:activate()
    far.armed = true
    far:claim()
    far.members.Kickpuncher.hpp = 20
    far:tick(0)
    far:tick(1.3)
    assert(far:count('controller', {
        recipient='Tackleberry', semantic='emergency-cure'}) == 0,
        'a known out-of-range member consumed Tackle\'s action lane')
    assert(far:count('controller', {
        recipient='Tackleberry', semantic='reraise'}) == 1,
        'a known out-of-range member starved Tackle\'s tank upkeep')
end)

test('prolonged primary healing keeps deferred Smalls work bounded',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h.boss.hpp = 20
    h.members.Dolomedes.hpp = 50
    for step=0,140 do h:tick(step * 1.3) end

    local deferred = 0
    for _, task in pairs(h.runtime.tasks) do
        if task.recipient == 'Smalls'
            and task.semantic ~= 'support-cure'
            and task.semantic ~= 'wake-pack'
            and task.semantic ~= 'lowhp-cure'
            and task.semantic ~= 'cure-iv'
        then
            deferred = deferred + 1
        end
    end
    assert(deferred <= 6,
        'timestamped Smalls work accumulated during prolonged healing: '
            ..tostring(deferred))

    h.members.Dolomedes.hpp = 100
    local before = #h.calls
    for step=141,145 do h:tick(step * 1.3) end
    local recovered_control = false
    for index=before + 1,#h.calls do
        local call = h.calls[index]
        if call.kind == 'controller' and call.recipient == 'Smalls'
            and (call.semantic == 'diaga'
                or call.semantic == 'silence-boss'
                or call.semantic == 'dia-iii')
        then
            recovered_control = true
            break
        end
    end
    assert(recovered_control,
        'bounded deferred queue did not resume fresh control within 6.5s')
end)

test('later add generations repeat the same automatic focus transition',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local first = h:add('Bozzetto Tormentor', 440)
    h:tick(1)
    h:remove(first)
    h:tick(2)
    h:boss_targets('Kickpuncher', 2.5)
    local second_tormentor = h:add('Bozzetto Tormentor', 441)
    local second_astrologer = h:add('Bozzetto Astrologer', 442)
    h:tick(3)
    assert(h:last('force-members', {
        id=second_astrologer.id,
        members='Achoo',
    }), 'second generation did not immediately anchor Astrologer')
    assert(h:last('force-members', {
        id=second_tormentor.id, members='Tackleberry',
    }), 'second generation did not stage the parked pickup')
    assert(not h.runtime.combat_targets.Dolomedes)
    assert(not h.runtime.combat_targets.Kickpuncher)
    assert(not h.runtime.combat_targets.Barneystinson)
    h:add_targets(second_tormentor, 'Tackleberry', 9.1)
    h:tick(9.3)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == second_astrologer.id,
            name..' did not rejoin the second-wave focus')
    end
    h:remove(second_astrologer)
    h:tick(9.6)
    assert(h:last('force-members', {
        id=second_tormentor.id,
        members='Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Achoo',
    }), 'second generation did not continue to Tormentor')
end)

test('later waves immediately recapture recycled mob slots', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:boss_targets('Dolomedes', .5)
    local recycled = h:add('Bozzetto Astrologer', 445)
    h:tick(1)
    h:tick(2.5)
    assert(h:count('controller', {
        recipient='Achoo', semantic='flash-add',
        subject=recycled.id}) == 1)

    h:remove(recycled)
    h:tick(3)
    h:boss_targets('Kickpuncher', 3.25)
    recycled.valid_target = true
    recycled.hpp = 100
    h:tick(4)
    assert(h:count('controller', {
        recipient='Achoo', semantic='flash-add',
        subject=recycled.id}) == 2,
        'prior-wave add cadence delayed the recycled-slot pickup')
    assert(h.runtime.combat_targets.Achoo == recycled.id)
    assert(not h.runtime.combat_targets.Dolomedes)
    h:tick(10.3)
    for _, name in ipairs{
        'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
    } do
        assert(h.runtime.combat_targets[name] == recycled.id,
            name..' did not collapse onto the recycled-slot wave')
    end
end)

test('Astrologer sleep completion wakes the melee pack automatically',
function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    local astrologer = h:add('Bozzetto Astrologer', 450)
    h:action({category=4, actor_id=astrologer.id, param=273,
        targets={
            {id=IDS.Kickpuncher, actions={{param=1}}},
            {id=IDS.Tackleberry, actions={{param=1}}},
            {id=IDS.Barneystinson, actions={{param=1}}},
        }}, .5)
    h:tick(1.25)
    assert(h:count('controller', {
        recipient='Smalls', semantic='wake-pack',
        subject=IDS.Tackleberry}) == 1)
    h:tick(2.5)
    assert(h:count('controller', {
        recipient='Achoo', semantic='wake-pack',
        subject=IDS.Tackleberry}) == 1)
end)

test('Reraise maintenance repeats for every member without gating combat',
function()
    local h = make_harness({reject_semantic='reraise'})
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    assert(h:count('controller', {semantic='reraise'}) == 6)
    assert(h:count('force-members', {
        id=h.boss.id,
        members='Dolomedes,Kickpuncher,Barneystinson',
    }) == 1)
    h:tick(20)
    assert(h:count('controller', {semantic='reraise'}) == 12)
    assert(h:count('stop') == 0)
end)

test('disarm cancels automation and stops PartyCombat', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h.armed = false
    h:tick(.3)
    assert(h:count('controller', {semantic='cancel'}) == 6)
    assert(h:count('stop') == 1)
    assert(h:count('release', {id=h.boss.id}) == 1)
    local count = #h.calls
    h:tick(20)
    assert(#h.calls == count)
end)

test('both Ambuscade zones work and unrelated zones remain inert', function()
    for _, zone in ipairs{183,287} do
        local h = make_harness({zone=zone})
        h:activate()
        h.armed = true
        h:tick(0)
        assert(h:count('authorize', {id=h.boss.id}) == 1)
    end
    local h = make_harness({zone=130})
    h:activate()
    h.armed = true
    h:tick(0)
    assert(#h.calls == 0)
end)

for _, entry in ipairs(tests) do
    local ok, failure = pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end

io.write(('September Qutrub no-Cait runtime tests passed: %d\n')
    :format(#tests))
