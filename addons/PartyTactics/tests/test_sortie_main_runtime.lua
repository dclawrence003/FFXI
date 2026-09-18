local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path)
    assert(loader,reason)
    return loader()
end

local sandbox=module('lib/sandbox.lua')
local loader,reason=sandbox.load(
    BASE..'profiles/sortie-main-v1/runtime.lua',loadfile)
assert(loader,reason)
local runtime_module=loader()

local ACTOR={Dolomedes=1001,Tackleberry=1002,Kickpuncher=1003,
    Barneystinson=1004,Smalls=1005,Achoo=1006}

local function harness(name)
    local h={now=0,armed=true,zone=275,calls={},authority=nil,
        selected=false,other=nil,
        tp={Dolomedes=0,Tackleberry=0,Kickpuncher=0,
            Barneystinson=0,Smalls=0,Achoo=0},party_mobs={}}
    for member,id in pairs(ACTOR) do
        h.party_mobs[id]={id=id,index=id,name=member,spawn_type=13}
    end
    h.mob={id=300,index=1300,name=name or 'Skomora',spawn_type=16,
        valid_target=true,hpp=100,claim_id=0,distance=4}
    h.runtime=runtime_module.create()
    function h:record(kind,fields)
        fields=fields or {}; fields.kind=kind; fields.at=self.now
        self.calls[#self.calls+1]=fields
    end
    function h:count(kind,fields)
        local count=0
        for _,call in ipairs(self.calls) do
            local match=call.kind==kind
            for key,value in pairs(fields or {}) do
                if call[key]~=value then match=false end
            end
            if match then count=count+1 end
        end
        return count
    end
    function h:last(kind,fields)
        for index=#self.calls,1,-1 do
            local call,match=self.calls[index],true
            if call.kind~=kind then match=false end
            for key,value in pairs(fields or {}) do
                if call[key]~=value then match=false end
            end
            if match then return call end
        end
    end
    h.ctx={
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        mob_by_id=function(id)
            if tonumber(id)==h.mob.id then return h.mob end
            if h.other and tonumber(id)==h.other.id then return h.other end
            return h.party_mobs[tonumber(id)]
        end,
        current_target=function() return h.selected and h.mob or nil end,
        monster_ability=function(id)
            local names={
                [3363]='Tearing Gust',[3364]='Concussive Shock',
                [3365]='Chokehold',[3366]='Zap',
                [3367]='Shrieking Gale',[3368]='Undulating Shockwave',
            }
            return names[tonumber(id)] and {en=names[tonumber(id)]} or nil
        end,
        party_claimed=function(mob)
            return (mob==h.mob or mob==h.other)
                and h.party_mobs[tonumber(mob.claim_id)]~=nil
        end,
        party_tp=function(member) return h.tp[member] or 0 end,
        operator_armed=function() return h.armed end,
        authorize_encounter=function(id)
            h:record('authorize',{id=id})
            if h.authorize_result==false then return false end
            h.authority=id; return true
        end,
        encounter_ready=function(id) return h.authority==id end,
        release_encounter=function(id,keep)
            h:record('release',{id=id,keep=keep})
            h.authority=nil
            return true
        end,
        actions={
            party_adapter=function(member,semantic,id)
                h:record('adapter',{name=member,semantic=semantic,id=id})
                return true
            end,
            combat_force=function(id)
                h:record('force',{id=id}); return true
            end,
            combat_force_members=function(id,members)
                h:record('force_members',{
                    id=id,members=table.concat(members,',')})
                return true
            end,
            combat_stop_members=function(members)
                h:record('stop',{members=table.concat(members,',')})
                return true
            end,
        },
    }
    function h:activate() self.runtime:on_activate(self.ctx) end
    function h:tick(at) self.now=at; self.runtime:on_tick(self.ctx,at) end
    function h:action(value,at)
        self.now=at; self.runtime:on_action(self.ctx,value)
    end
    return h
end

local function boss_move(h,param)
    return {category=6,actor_id=h.mob.id,param=param,
        targets={{id=ACTOR.Dolomedes,actions={{message=1,param=500}}}}}
end

local function hit(h,actor,category,param,options)
    options=options or {}
    return {category=category,actor_id=ACTOR[actor],param=param,
        targets={{id=options.target_id or h.mob.id,actions={{
            message=options.message or 1,param=options.damage or 1000,
            add_effect_message=options.add_effect,
            add_effect_param=options.add_effect and 500 or nil,
        }}}}}
end

-- Merely selecting a target or ticking never starts combat. A Tackle hostile
-- action binds it and gets exactly one synchronization edge. The same is true
-- for an improvised pull; no initiating character is a lifecycle gate.
local native=harness(); native:activate(); native:tick(0)
assert(native:count('authorize')==0)
native:action(hit(native,'Tackleberry',4,112),0.1)
assert(native:last('authorize',{id=native.mob.id}))
assert(native:count('force',{id=native.mob.id})==1)
assert(native:count('adapter',{semantic='combat-mode'})==6)

local improvised=harness(); improvised:activate()
improvised:action(hit(improvised,'Kickpuncher',1,0),0.1)
assert(improvised:count('force',{id=improvised.mob.id})==1)

-- Selecting exact Leshonn on Dolo stages safe support but never engages,
-- stops, moves, or spends TP. Tackle's hostile action starts immediately;
-- any other party opener would do the same.
local leshonn=harness('Leshonn'); leshonn.selected=true; leshonn:activate()
leshonn:tick(0)
assert(leshonn:last('authorize',{id=leshonn.mob.id}))
assert(leshonn:count('adapter',{semantic='leshonn-mode'})==6)
assert(leshonn:count('force')==0 and leshonn:count('stop')==0)
leshonn:action(hit(leshonn,'Tackleberry',1,0),0.1)
assert(leshonn:count('force',{id=leshonn.mob.id})==1)
for member in pairs(leshonn.tp) do leshonn.tp[member]=1000 end
leshonn:tick(0.4)
for _,lane in ipairs{
    {'Dolomedes','savage-blade'},{'Tackleberry','savage-blade'},
    {'Barneystinson','savage-blade'},{'Smalls','black-halo'},
    {'Achoo','black-halo'},
} do
    assert(leshonn:last('adapter',{name=lane[1],semantic=lane[2]}),lane[1])
end
assert(not leshonn:last('adapter',{
    name='Kickpuncher',semantic='evisceration'}))
assert(leshonn:count('stop')==0)

-- Form-specific monster actions refine telemetry without changing the common
-- no-debuff/no-Sentinel safety baseline. Wind may offer conditional /DRK Last
-- Resort; the Thunder transition removes that offer.
leshonn:action(boss_move(leshonn,3365),0.5)
assert(leshonn:count('adapter',{semantic='leshonn-wind-mode'})==6)
leshonn:action(boss_move(leshonn,3366),0.6)
assert(leshonn:count('adapter',{semantic='leshonn-thunder-mode'})==6)

-- Staging is never an encounter gate. If the party improvises onto another
-- exact enemy, release staged Leshonn and synchronize the target actually hit.
local diverted=harness('Leshonn'); diverted.selected=true; diverted:activate()
diverted:tick(0)
diverted.other={id=301,index=1301,name='Skomora',spawn_type=16,
    valid_target=true,hpp=100,claim_id=0,distance=4}
diverted:action(hit(diverted,'Kickpuncher',1,0,
    {target_id=diverted.other.id}),0.1)
assert(diverted:last('release',{id=diverted.mob.id,keep=true}))
assert(diverted:last('authorize',{id=diverted.other.id}))
assert(diverted:last('force',{id=diverted.other.id}))
assert(diverted:count('stop')==0)

-- Ordinary combat is full-party mobile burn with one semantic WS lane per
-- member and no runtime disengage.
for member in pairs(native.tp) do native.tp[member]=1000 end
native:tick(0.4)
for _,lane in ipairs{
    {'Dolomedes','savage-blade'},{'Tackleberry','savage-blade'},
    {'Kickpuncher','evisceration'},{'Barneystinson','savage-blade'},
    {'Smalls','black-halo'},{'Achoo','black-halo'},
} do
    assert(native:last('adapter',{name=lane[1],semantic=lane[2]}),lane[1])
end
assert(native:count('stop')==0)

-- Cachaemics hold WS only long enough to perform the automatic chain/burst;
-- everyone remains engaged, and all six return to normal WS after the burst.
local c=harness('Cachaemic Skeleton'); c:activate()
c:action(hit(c,'Tackleberry',4,112),0.1)
c.tp.Kickpuncher,c.tp.Dolomedes=1000,1000
c:tick(0.4)
assert(c:last('adapter',{name='Kickpuncher',semantic='evisceration'}))
c:action(hit(c,'Kickpuncher',3,25),0.5)
c:tick(3.5)
assert(c:count('adapter',{name='Dolomedes',semantic='savage-blade'})==0)
c:tick(3.7)
assert(c:last('adapter',{name='Dolomedes',semantic='savage-blade'}))
c:action(hit(c,'Dolomedes',3,42,{add_effect=291}),3.8)
assert(c:last('adapter',{name='Smalls',semantic='thunder'}))
assert(c:last('adapter',{name='Achoo',semantic='thunder'}))
c:action(hit(c,'Achoo',4,164,{message=252,damage=4000}),4.0)
for member in pairs(c.tp) do c.tp[member]=1000 end
c:tick(5.4)
assert(c:last('adapter',{name='Smalls',semantic='black-halo'}))
assert(c:last('adapter',{name='Achoo',semantic='black-halo'}))
assert(c:count('stop')==0)

-- Other Cachaemics are ordinary interruption targets, not burst-objective
-- targets. A Bhoot therefore gets the fast general recipe.
local bhoot=harness('Cachaemic Bhoot'); bhoot:activate()
bhoot:action(hit(bhoot,'Tackleberry',4,112),0.1)
for member in pairs(bhoot.tp) do bhoot.tp[member]=1000 end
bhoot:tick(0.4)
assert(bhoot:last('adapter',{name='Dolomedes',semantic='savage-blade'}))
assert(bhoot:last('adapter',{name='Smalls',semantic='black-halo'}))
assert(not bhoot:last('adapter',{semantic='thunder'}))

-- Acuex performs one bounded handoff. Four builders stop once, the two chain
-- partners stop once after Liquefaction, and Fire IV/III are queued. Ticks do
-- not create a disengage/re-engage loop.
local a=harness('Abject Acuex'); a.mob.hpp=65; a:activate()
a:action(hit(a,'Tackleberry',4,112),0.1)
assert(a:last('adapter',{name='Smalls',semantic='acuex-mode'}))
a.tp.Tackleberry,a.tp.Smalls=1000,1000
a:tick(0.4)
assert(a:count('stop',{members=
    'Dolomedes,Kickpuncher,Barneystinson,Achoo'})==1)
assert(a:last('adapter',{name='Tackleberry',semantic='flat-blade'}))
a:action(hit(a,'Tackleberry',3,35),0.5)
a:tick(3.5)
assert(a:count('adapter',{name='Smalls',semantic='red-lotus-blade'})==0)
a:tick(3.7)
assert(a:last('adapter',{name='Smalls',semantic='red-lotus-blade'}))
a:action(hit(a,'Smalls',3,34,{add_effect=295}),3.8)
assert(a:count('stop',{members='Tackleberry,Smalls'})==1)
assert(a:last('adapter',{name='Smalls',semantic='fire-iv'}))
assert(a:last('adapter',{name='Smalls',semantic='fire-iii'}))
a:tick(4.2); a:tick(5.6)
assert(a:count('stop',{members=
    'Dolomedes,Kickpuncher,Barneystinson,Achoo'})==1)
assert(a:count('stop',{members='Tackleberry,Smalls'})==1)

-- A missed Flat/Red-Lotus handoff resumes exactly the members this runtime
-- stopped, then permits a fresh attempt instead of leaving them at 3000 TP.
local retry=harness('Abject Acuex'); retry.mob.hpp=65; retry:activate()
retry:action(hit(retry,'Tackleberry',4,112),0.1)
retry.tp.Tackleberry,retry.tp.Smalls=1000,1000
retry:tick(0.4)
retry:tick(7.5)
assert(retry:count('force_members',{id=retry.mob.id,members=
    'Dolomedes,Kickpuncher,Barneystinson,Achoo'})==1)
retry:tick(8.1)
assert(retry:count('stop',{members=
    'Dolomedes,Kickpuncher,Barneystinson,Achoo'})==2)

-- Encounter retirement schedules movement support before releasing authority,
-- but never disarms the persistent profile. Deactivation only cancels its own
-- adapter requests and emits no PartyCombat or profile lifecycle operation.
a.mob.hpp=0; a:tick(5.9)
assert(a:last('release',{id=a.mob.id,keep=true}))
assert(a:count('adapter',{semantic='movement-mode'})==6)
local isolated=harness('Leshonn'); isolated:activate()
isolated:action(hit(isolated,'Tackleberry',4,112),0.1)
isolated.runtime:on_deactivate(isolated.ctx)
assert(isolated:count('stop')==0 and isolated:count('release')==0)
assert(isolated:count('adapter',{semantic='cancel'})==6)

-- Alt-P remains authoritative. It retires only this profile's encounter and
-- does not create an automatic re-arm or fresh bind on later ticks.
local disarm=harness(); disarm:activate()
disarm:action(hit(disarm,'Tackleberry',1,0),0.1)
disarm.armed=false; disarm:tick(0.4)
assert(disarm:last('release',{id=disarm.mob.id,keep=false}))
disarm:tick(2.0)
assert(disarm:count('authorize',{id=disarm.mob.id})==1)

print('PASS - persistent Sortie main runtime and isolation')
