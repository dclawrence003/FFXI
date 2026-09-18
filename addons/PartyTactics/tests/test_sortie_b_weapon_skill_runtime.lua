local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path); assert(loader,reason); return loader()
end
local sandbox=module('lib/sandbox.lua')
local loader,reason=sandbox.load(BASE
    ..'profiles/sortie-objective-b-weapon-skill-v1/runtime.lua',loadfile)
assert(loader,reason)
local runtime_module=loader()
local ACTOR={Dolomedes=1001,Tackleberry=1002,Kickpuncher=1003,
    Barneystinson=1004,Smalls=1005,Achoo=1006}
local ALL='Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo'

local function harness()
    local h={now=0,armed=true,zone=275,calls={},authority=nil,
        authorize_result=true,tp={},party_mobs={}}
    for name,id in pairs(ACTOR) do
        h.party_mobs[id]={id=id,index=id,name=name,spawn_type=13}
        h.tp[name]=0
    end
    h.mob={id=400,index=1400,name='Biune Fire Elemental',spawn_type=16,
        valid_target=true,hpp=100,claim_id=0,distance=4}
    h.runtime=runtime_module.create()
    function h:record(kind,fields)
        fields=fields or {}; fields.kind=kind; self.calls[#self.calls+1]=fields
    end
    function h:count(kind,fields)
        local n=0
        for _,call in ipairs(self.calls) do
            local ok=call.kind==kind
            for key,value in pairs(fields or {}) do if call[key]~=value then ok=false end end
            if ok then n=n+1 end
        end
        return n
    end
    function h:last(kind,fields)
        for i=#self.calls,1,-1 do
            local call,ok=self.calls[i],true
            if call.kind~=kind then ok=false end
            for key,value in pairs(fields or {}) do if call[key]~=value then ok=false end end
            if ok then return call end
        end
    end
    h.ctx={
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        recent_target=function() return h.mob end,
        current_target=function() return h.mob end,
        mob_by_id=function(id)
            return tonumber(id)==h.mob.id and h.mob or h.party_mobs[tonumber(id)]
        end,
        party_claimed=function(mob)
            return mob==h.mob and h.party_mobs[tonumber(mob.claim_id)]~=nil
        end,
        party_tp=function(name) return h.tp[name] or 0 end,
        operator_armed=function() return h.armed end,
        authorize_encounter=function(id)
            h:record('authorize',{id=id})
            if not h.authorize_result then return false end
            h.authority=id; return true
        end,
        encounter_ready=function(id) return h.authority==id end,
        release_encounter=function(id,keep)
            h:record('release',{id=id,keep=keep}); h.authority=nil
            h.armed=keep==true and h.armed==true; return true
        end,
        alert=function(message,audible)
            h:record('alert',{message=message,audible=audible})
        end,
        actions={
            party_adapter=function(name,semantic,id)
                h:record('adapter',{name=name,semantic=semantic,id=id}); return true
            end,
            combat_force_members=function(id,members)
                h:record('force',{id=id,members=table.concat(members,',')}); return true
            end,
            combat_stop_members=function(members)
                h:record('stop',{members=table.concat(members,',')}); return true
            end,
        },client={},
    }
    function h:activate() self.runtime:on_activate(self.ctx) end
    function h:tick(at) self.now=at; self.runtime:on_tick(self.ctx,at) end
    function h:action(actor,category,param,damage)
        self.runtime:on_action(self.ctx,{category=category,
            actor_id=ACTOR[actor],param=param,
            targets={{id=self.mob.id,actions={{message=1,param=damage or 1000}}}}})
    end
    return h
end

local h=harness(); h:activate(); h:tick(0)
assert(h:last('authorize',{id=h.mob.id}) and h:last('force',{members='Tackleberry'}))
assert(h:last('stop',{members=ALL}))
h.mob.claim_id=ACTOR.Tackleberry; h:tick(0.2)
assert(h:last('force',{members=ALL}))
h.mob.hpp=64; h.tp.Dolomedes=1000; h:tick(0.4)
assert(h:last('stop',{members=ALL}))
assert(h:last('force',{members='Dolomedes'}))
assert(h:last('adapter',{name='Dolomedes',semantic='savage-blade'}))
h:action('Dolomedes',3,42,10000)
assert(h:last('force',{members=ALL}),
    'surviving a qualifying WS must resume full damage')
h:action('Kickpuncher',1,0,500)
h.mob.hpp=0; h:tick(0.6)
local credit=false
for _,call in ipairs(h.calls) do
    if call.kind=='alert' and call.message:find('B WS CREDIT OBSERVED',1,true)
    then credit=true end
end
assert(credit,'a later melee hit erased the already-earned WS credit')
assert(h:last('release',{id=h.mob.id,keep=true}))

local hold=harness(); hold:activate(); hold.mob.claim_id=ACTOR.Tackleberry
hold:tick(0); hold.mob.hpp=29; hold:tick(0.2)
assert(hold:last('stop',{members=ALL}))
hold.tp.Smalls=1000; hold:tick(0.4)
assert(hold:last('adapter',{name='Smalls',semantic='black-halo'}))

local fallback=harness(); fallback:activate(); fallback:tick(0)
fallback:tick(0.6); fallback:tick(1.2); fallback:tick(1.3)
assert(fallback:count('force',{members='Tackleberry'})==3)
assert(fallback:last('force',{members=ALL}))

for _,zone in ipairs({133,189,275}) do
    local accepted=harness(); accepted.zone=zone; accepted:activate(); accepted:tick(0)
    assert(accepted:last('authorize',{id=accepted.mob.id}),tostring(zone))
end
local inert=harness(); inert.mob.name='Biune Porxie'; inert:activate(); inert:tick(0)
assert(inert:count('authorize')==0)
local lookalike=harness(); lookalike.mob.name='Biune Fake Elemental'
lookalike:activate(); lookalike:tick(0)
assert(lookalike:count('authorize')==0)
local unavailable=harness(); unavailable.authorize_result=false
unavailable:activate(); unavailable:tick(0)
assert(unavailable:count('stop')==0 and unavailable:count('force')==0)

print('PASS - Sortie B automatic weapon-skill-credit runtime')
