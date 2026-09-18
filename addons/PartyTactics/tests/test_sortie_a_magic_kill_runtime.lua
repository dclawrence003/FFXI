local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path)
    assert(loader,reason)
    return loader()
end

local sandbox=module('lib/sandbox.lua')
local loader,reason=sandbox.load(BASE
    ..'profiles/sortie-objective-a-magic-kill-v1/runtime.lua',loadfile)
assert(loader,reason)
local runtime_module=loader()

local ACTOR={Dolomedes=1001,Tackleberry=1002,Kickpuncher=1003,
    Barneystinson=1004,Smalls=1005,Achoo=1006}
local ALL='Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo'

local function harness()
    local h={now=0,armed=true,zone=275,calls={},alerts={},authority=nil,
        tp={Dolomedes=0,Tackleberry=0,Kickpuncher=0,
            Barneystinson=0,Smalls=0,Achoo=0},party_mobs={}}
    for name,id in pairs(ACTOR) do
        h.party_mobs[id]={id=id,index=id,name=name,spawn_type=13}
    end
    h.mob={id=300,index=1300,name='Abject Acuex',spawn_type=16,
        valid_target=true,hpp=100,claim_id=0,distance=4}
    h.current=h.mob
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
        recent_target=function() return h.current end,
        current_target=function() return h.current end,
        mob_by_id=function(id)
            if tonumber(id)==h.mob.id then return h.mob end
            return h.party_mobs[tonumber(id)]
        end,
        party_claimed=function(mob)
            return mob==h.mob and h.party_mobs[tonumber(mob.claim_id)]~=nil
        end,
        party_tp=function(name) return h.tp[name] or 0 end,
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
            h.armed=keep==true and h.armed==true
            return true
        end,
        alert=function(message,audible)
            h.alerts[#h.alerts+1]={message=message,audible=audible}
            h:record('alert',{message=message,audible=audible})
        end,
        actions={
            party_adapter=function(name,semantic,id)
                h:record('adapter',{name=name,semantic=semantic,id=id})
                return true
            end,
            combat_force_members=function(id,members)
                h:record('force',{id=id,members=table.concat(members,',')})
                return true
            end,
            combat_stop_members=function(members)
                h:record('stop',{members=table.concat(members,',')})
                return true
            end,
        },client={},
    }
    function h:activate() self.runtime:on_activate(self.ctx) end
    function h:tick(at) self.now=at; self.runtime:on_tick(self.ctx,at) end
    function h:action(value,at)
        self.now=at; self.runtime:on_action(self.ctx,value)
    end
    return h
end

local function hit(h,actor,category,param,options)
    options=options or {}
    return {category=category,actor_id=ACTOR[actor],param=param,
        targets={{id=options.target_id or h.mob.id,actions={{
            message=options.message or 1,param=options.damage or 1000,
            add_effect_message=options.liquefaction and 295 or nil,
            add_effect_param=options.liquefaction and 500 or nil,
        }}}}}
end

-- Exact identity and instance scope remain fail closed.
local inert=harness(); inert:activate(); inert.mob.name='Abject Leech'; inert:tick(0)
assert(inert:count('authorize')==0)
inert.mob.name='Abject Acuex'; inert.zone=267; inert:tick(1)
assert(inert:count('authorize')==0)
for _,zone in ipairs({133,189,275}) do
    local accepted=harness(); accepted.zone=zone; accepted:activate(); accepted:tick(0)
    assert(accepted:last('authorize',{id=accepted.mob.id}),tostring(zone))
end

-- Tackle receives first threat, but his first real party claim releases all
-- six immediately so tank-first behavior cannot become a speed gate.
local h=harness(); h:activate(); h:tick(0)
assert(h:last('authorize',{id=h.mob.id}))
assert(h:last('stop',{members=ALL}))
assert(h:last('force',{members='Tackleberry'}))
h.mob.claim_id=ACTOR.Tackleberry
h:action(hit(h,'Tackleberry',1,0),0.2)
assert(h:last('force',{members=ALL}))

-- Full damage builds the two required TP pools, then the runtime—not the
-- operator—pauses other damage and requests the exact Liquefaction pair.
h.tp.Tackleberry,h.tp.Smalls=1000,1000
h:tick(0.3)
assert(h:last('stop',{members=
    'Dolomedes,Kickpuncher,Barneystinson,Achoo'}))
assert(h:last('force',{members='Tackleberry,Smalls'}))
assert(h:last('adapter',{name='Tackleberry',semantic='flat-blade'}))

-- Wrong actors, targets, and failure packets cannot advance the chain.
h:action(hit(h,'Dolomedes',3,35),0.4)
h:action(hit(h,'Tackleberry',3,35,{target_id=999}),0.5)
h:action(hit(h,'Tackleberry',3,35,{message=158}),0.6)
h:tick(3.7)
assert(h:count('adapter',{name='Smalls',semantic='red-lotus-blade'})==0)

-- Packet-confirmed Flat Blade schedules Red Lotus Blade at the real chain
-- delay; packet-confirmed Liquefaction stops all melee and queues Fire V/IV/III.
h:action(hit(h,'Tackleberry',3,35),1.0)
h:tick(3.9)
assert(h:count('adapter',{name='Smalls',semantic='red-lotus-blade'})==0)
h:tick(4.1)
assert(h:last('adapter',{name='Smalls',semantic='red-lotus-blade'}))
h:action(hit(h,'Smalls',3,34,{liquefaction=true}),4.2)
assert(h:last('stop',{members=ALL}))
for _,semantic in ipairs({'fire-v','fire-iv','fire-iii'}) do
    assert(h:last('adapter',{name='Smalls',semantic=semantic}),semantic)
end

-- Bursts are observed, but a single-target Fire packet as the last positive
-- damage is what the runtime reports for the killing-blow diagnostic.
h:action(hit(h,'Smalls',4,148,{message=252,damage=8000}),4.4)
h:action(hit(h,'Smalls',4,147,{message=252,damage=6000}),4.6)
h.mob.hpp=0; h:tick(4.8)
assert(h:last('release',{id=h.mob.id,keep=true}))
local reported=false
for _,entry in ipairs(h.alerts) do
    if entry.message:find('A FIRE FINISH OBSERVED',1,true)
        and entry.message:find('2 Magic Burst packet',1,true)
    then reported=true end
end
assert(reported)

-- A broken Red Lotus result automatically returns to full TP building.
local retry=harness(); retry:activate(); retry.mob.claim_id=ACTOR.Tackleberry
retry:tick(0); retry.tp.Tackleberry,retry.tp.Smalls=1000,1000
retry:tick(0.2)
retry:action(hit(retry,'Tackleberry',3,35),0.3)
retry:tick(3.4)
retry:action(hit(retry,'Smalls',3,34),3.5)
assert(retry:last('force',{members=ALL}))

-- Reaching low HP before both TP pools are ready creates an automatic magic
-- hold and immediately queues Fire instead of leaving an autoattack bonanza.
local low=harness(); low:activate(); low.mob.claim_id=ACTOR.Tackleberry
low:tick(0); low.mob.hpp=34; low:tick(0.2)
assert(low:last('stop',{members=ALL}))
assert(low:last('adapter',{name='Smalls',semantic='fire-v'}))

-- Missing claim evidence has a short bounded fallback that releases everyone.
local fallback=harness(); fallback:activate(); fallback:tick(0)
fallback:tick(0.6); fallback:tick(1.2); fallback:tick(1.3)
assert(fallback:count('force',{members='Tackleberry'})==3)
assert(fallback:last('force',{members=ALL}))

-- Binding failure never stops existing combat, and Alt-P remains authoritative.
local unavailable=harness(); unavailable.authorize_result=false
unavailable:activate(); unavailable:tick(0)
assert(unavailable:count('stop')==0 and unavailable:count('force')==0)
local disarm=harness(); disarm:activate(); disarm:tick(0)
disarm.armed=false; disarm:tick(0.2)
assert(disarm:last('release',{id=disarm.mob.id,keep=false}))
disarm:tick(1.0)
assert(disarm:count('authorize',{id=disarm.mob.id})==1)

print('PASS - Sortie A automatic Liquefaction and Fire runtime')
