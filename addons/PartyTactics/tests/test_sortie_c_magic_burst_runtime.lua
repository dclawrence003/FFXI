-- Behavioral contract for the exact-target Sortie C burst runtime.

local BASE = 'addons/PartyTactics/'
local function module(path)
    local loader, reason = loadfile(BASE .. path)
    assert(loader, reason)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local loader, reason = sandbox.load(BASE
    .. 'profiles/sortie-objective-c-magic-burst-v1/runtime.lua', loadfile)
assert(loader, reason)
local runtime_module = loader()

local ACTOR = {
    Dolomedes=1001, Tackleberry=1002, Kickpuncher=1003,
    Barneystinson=1004, Smalls=1005, Achoo=1006,
}
local WS = {Evisceration=25, SavageBlade=42}

local function make_harness()
    local party_mobs = {}
    for name, id in pairs(ACTOR) do
        party_mobs[id] = {id=id,index=id,name=name,spawn_type=13}
    end
    local h = {
        now=0, armed=false, zone=275, calls={}, alerts={},
        tp={Dolomedes=0,Tackleberry=0,Kickpuncher=0,
            Barneystinson=0,Smalls=0,Achoo=0},
        party_mobs=party_mobs, authorize_result=true,
        mob={id=300,index=1300,name='Cachaemic Ghost',spawn_type=16,
            valid_target=true,hpp=100,claim_id=0,distance=4},
    }
    h.current = h.mob
    h.runtime = runtime_module.create()

    function h:record(kind, fields)
        fields = fields or {}
        fields.kind, fields.at = kind, self.now
        self.calls[#self.calls + 1] = fields
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
            local call, match = self.calls[index], true
            if call.kind ~= kind then match = false end
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then match = false end
            end
            if match then return call end
        end
    end

    h.ctx = {
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        current_target=function() return h.current end,
        mob_by_id=function(id)
            if tonumber(id) == h.mob.id then return h.mob end
            return h.party_mobs[tonumber(id)]
        end,
        party_claimed=function(mob)
            return mob == h.mob
                and h.party_mobs[tonumber(mob.claim_id)] ~= nil
        end,
        party_tp=function(name) return h.tp[name] end,
        operator_armed=function() return h.armed end,
        authorize_encounter=function(id)
            h:record('authorize',{id=id})
            return h.authorize_result
        end,
        release_encounter=function(id,keep_armed)
            h:record('release',{id=id,keep_armed=keep_armed})
            h.armed = keep_armed == true and h.armed == true
            return true
        end,
        alert=function(message,audible)
            h.alerts[#h.alerts + 1] = {message=message,audible=audible}
            h:record('alert',{message=message,audible=audible})
        end,
        actions={
            party_adapter=function(recipient,semantic,id)
                h:record('adapter',{recipient=recipient,
                    semantic=semantic,id=id})
                return true
            end,
            combat_force_members=function(id,members)
                h:record('force-members',{id=id,
                    members=table.concat(members,',')})
                return true
            end,
            combat_stop=function()
                h:record('stop')
                return true
            end,
        },
        client={},
    }

    function h:activate() self.runtime:on_activate(self.ctx) end
    function h:tick(at)
        self.now = at
        self.runtime:on_tick(self.ctx,at)
    end
    function h:action(packet,at)
        self.now = at
        self.runtime:on_action(self.ctx,packet)
    end
    return h
end

local function ws(h,actor,id,options)
    options = options or {}
    return {
        category=3,actor_id=ACTOR[actor],param=id,
        targets={{id=options.target_id or h.mob.id,actions={{
            message=options.message or 1,param=options.damage or 1000,
            add_effect_message=options.fragmentation and 291 or nil,
            add_effect_param=options.fragmentation and 500 or nil,
        }}}},
    }
end

local function spell(h,actor,options)
    options = options or {}
    return {
        category=4,actor_id=ACTOR[actor],param=options.spell_id or 164,
        targets={{id=options.target_id or h.mob.id,actions={{
            message=options.message or 252,param=options.damage or 321,
        }}}},
    }
end

local function arm_claimed(h)
    h:activate()
    h.armed = true
    h.mob.claim_id = ACTOR.Dolomedes
end

-- Inert load, wrong zones, wrong targets, and the Bhoot never bind.
local inert = make_harness()
inert:activate()
inert:tick(0)
assert(inert:count('authorize') == 0)
inert.armed = true
inert.zone = 267
inert:tick(1)
assert(inert:count('authorize') == 0)
inert.zone = 275
inert.mob.name = 'Cachaemic Bhoot'
inert:tick(2)
assert(inert:count('authorize') == 0)
inert.mob.name = 'Demisang Warrior'
inert:tick(3)
assert(inert:count('authorize') == 0)

-- Only the selected exact normal mob binds. Tackle receives the first exact
-- engagement; no chain request exists before his opening action or claim.
local chain = make_harness()
chain:activate()
chain.armed = true
chain.tp.Kickpuncher, chain.tp.Dolomedes = 1000, 1000
chain:tick(0)
assert(chain:count('authorize',{id=chain.mob.id}) == 1)
assert(chain:last('force-members',{
    id=chain.mob.id,members='Tackleberry'}))
chain:tick(1)
assert(chain:count('adapter',{semantic='evisceration'}) == 0)
chain.mob.claim_id = ACTOR.Tackleberry
chain:action({category=1,actor_id=ACTOR.Tackleberry,param=0,
    targets={{id=chain.mob.id,actions={{message=1,param=500}}}}},1.1)
assert(chain:last('force-members',{
    id=chain.mob.id,members='Dolomedes,Kickpuncher'}))
chain:tick(1.25)
assert(chain:last('adapter',{
    recipient='Kickpuncher',semantic='evisceration',id=chain.mob.id}))
assert(chain:count('force-members',{
    members='Tackleberry,Barneystinson'}) == 0)
assert(chain:count('adapter',{recipient='Tackleberry',
    semantic='savage-blade'}) == 0)

-- Wrong actor, wrong target, and a known failure cannot advance the closer.
chain:action(ws(chain,'Barneystinson',WS.Evisceration),1.4)
chain:action(ws(chain,'Kickpuncher',WS.Evisceration,
    {target_id=999}),1.5)
chain:action(ws(chain,'Kickpuncher',WS.Evisceration,
    {message=158}),1.6)
chain:tick(4.8)
assert(chain:count('adapter',{recipient='Dolomedes',
    semantic='savage-blade'}) == 0)

-- A completed manual/correct Evisceration schedules Dolo at the real SC
-- delay. The closer is not inferred from command submission.
chain:action(ws(chain,'Kickpuncher',WS.Evisceration),2.0)
chain:tick(5.0)
assert(chain:count('adapter',{recipient='Dolomedes',
    semantic='savage-blade'}) == 0)
chain:tick(5.2)
assert(chain:last('adapter',{recipient='Dolomedes',
    semantic='savage-blade',id=chain.mob.id}))
assert(chain:count('adapter',{recipient='Achoo',semantic='thunder'}) == 0)

-- A Savage Blade without Fragmentation rebuilds instead of pretending credit.
chain:action(ws(chain,'Dolomedes',WS.SavageBlade),5.3)
assert(chain:count('adapter',{recipient='Achoo',semantic='thunder'}) == 0)

-- Packet-confirmed Fragmentation immediately requests low-cost Thunder.
chain:action(ws(chain,'Kickpuncher',WS.Evisceration),6.0)
chain:tick(9.2)
chain:action(ws(chain,'Dolomedes',WS.SavageBlade,
    {fragmentation=true}),9.3)
assert(chain:last('adapter',{
    recipient='Achoo',semantic='thunder',id=chain.mob.id}))
assert(chain:count('force-members',{
    members='Tackleberry,Barneystinson'}) == 0,
    'finishers released on skillchain rather than Magic Burst')
chain:tick(10.9)
assert(chain:last('adapter',{
    recipient='Smalls',semantic='thunder',id=chain.mob.id}))

-- Wrong-target and non-party burst-looking packets do not release damage.
chain:action(spell(chain,'Smalls',{target_id=999}),11.0)
local enemy_spell = spell(chain,'Smalls')
enemy_spell.actor_id = chain.mob.id
chain:action(enemy_spell,11.1)
assert(chain:count('force-members',{
    members='Tackleberry,Barneystinson'}) == 0)

-- Any real party Magic Burst packet counts, so a manual spell is a first-class
-- recovery path. Only then do Tackle/Barney and finisher WS lanes release.
chain:action(spell(chain,'Smalls',{spell_id=167}),11.2)
assert(chain:last('force-members',{
    id=chain.mob.id,members='Tackleberry,Barneystinson'}))
chain.tp.Tackleberry, chain.tp.Barneystinson = 1000, 1000
chain.tp.Kickpuncher, chain.tp.Dolomedes = 1000, 1000
chain:tick(11.5)
for _, expected in ipairs({
    {'Dolomedes','savage-blade'}, {'Tackleberry','savage-blade'},
    {'Kickpuncher','evisceration'}, {'Barneystinson','savage-blade'},
}) do
    assert(chain:last('adapter',{
        recipient=expected[1],semantic=expected[2],id=chain.mob.id}))
end

-- Target end cancels reservations and target authority while retaining the
-- route-owned arm latch for the next exact mob.
chain.mob.hpp = 0
chain:tick(12.0)
assert(chain:count('stop') == 2,
    'bind and retirement each clear stale combat atomically')
assert(chain:count('release',{id=chain.mob.id}) == 1)
assert(chain.armed == true)
assert(chain:last('release',{id=chain.mob.id,keep_armed=true}))
assert(chain:count('adapter',{semantic='cancel'}) == 8,
    'two burst-confirmation cancels plus six retirement cancels expected')

-- Missing burst confirmation has a bounded retry and never releases finishers.
local missed = make_harness()
arm_claimed(missed)
missed.tp.Kickpuncher, missed.tp.Dolomedes = 1000, 1000
missed:tick(0)
missed:tick(1)
missed:action(ws(missed,'Kickpuncher',WS.Evisceration),1.1)
missed:tick(4.3)
missed:action(ws(missed,'Dolomedes',WS.SavageBlade,
    {fragmentation=true}),4.4)
missed:tick(10.4)
assert(missed:count('force-members',{
    members='Tackleberry,Barneystinson'}) == 0)
missed:tick(10.7)
missed:tick(11.5)
assert(missed:count('adapter',{semantic='evisceration'}) == 2,
    'burst timeout did not return to a fresh automatic chain')

-- Binding authority failure leaves both combat and player controls untouched.
local unavailable = make_harness()
unavailable:activate()
unavailable.armed = true
unavailable.authorize_result = false
unavailable:tick(0)
assert(unavailable:count('force-members') == 0)
assert(unavailable:count('adapter') == 0)
assert(unavailable:count('stop') == 0)
unavailable:tick(1)
assert(unavailable:count('authorize') == 1,
    'authority failure retried and alerted every poll')
unavailable:tick(5.1)
assert(unavailable:count('authorize') == 2,
    'bounded authority retry did not remain available')

-- Post-claim loss is bounded and cannot retain stale exact-target authority.
local lost = make_harness()
arm_claimed(lost)
lost:tick(0)
lost.mob.claim_id = 0
lost:tick(0.5)
lost:tick(2.0)
assert(lost:count('release') == 0)
lost:tick(2.3)
assert(lost:count('release',{id=lost.mob.id}) == 1)
assert(lost:count('stop') == 2,
    'bind and bounded claim-loss retirement each clear combat')

print('PASS - Sortie C automatic Magic Burst runtime')
