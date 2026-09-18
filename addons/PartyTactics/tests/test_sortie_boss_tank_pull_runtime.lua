local BASE='addons/PartyTactics/'

local function module(path)
    local loader,reason=loadfile(BASE..path)
    assert(loader,reason)
    return loader()
end

local sandbox=module('lib/sandbox.lua')
local ACTOR={Dolomedes=1001,Tackleberry=1002,Kickpuncher=1003,
    Barneystinson=1004,Smalls=1005,Achoo=1006}

local function runtime_module(profile_id)
    local loader,reason=sandbox.load(BASE..'profiles/'..profile_id
        ..'/runtime.lua',loadfile)
    assert(loader,reason)
    return loader()
end

local function harness(profile_id,target_name)
    local h={now=0,armed=true,zone=275,calls={},party_mobs={},authority=nil}
    for name,id in pairs(ACTOR) do
        h.party_mobs[id]={id=id,index=id,name=name,spawn_type=13}
    end
    h.mob={id=700,index=1700,name=target_name,spawn_type=16,
        valid_target=true,hpp=100,claim_id=0,distance=4}
    h.current=h.mob
    h.runtime=runtime_module(profile_id).create()
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
        current_target=function() return h.current end,
        mob_by_id=function(id)
            if tonumber(id)==h.mob.id then return h.mob end
            return h.party_mobs[tonumber(id)]
        end,
        party_claimed=function(mob)
            return mob==h.mob and h.party_mobs[tonumber(mob.claim_id)]~=nil
        end,
        operator_armed=function() return h.armed end,
        authorize_encounter=function(id)
            h.authority=id; h:record('authorize',{id=id}); return true
        end,
        encounter_ready=function(id) return h.authority==id end,
        release_encounter=function(id,keep)
            h:record('release',{id=id,keep=keep})
            h.authority=nil
            h.armed=keep==true and h.armed==true
            return true
        end,
        alert=function(message,audible)
            h:record('alert',{message=message,audible=audible})
        end,
        actions={
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
    function h:action(action,at)
        self.now=at; self.runtime:on_action(self.ctx,action)
    end
    return h
end

local function pull_action(h,category,param)
    return {category=category or 4,actor_id=ACTOR.Tackleberry,
        param=param or 112,
        targets={{id=h.mob.id,actions={{message=1,param=0}}}}}
end

for _,fixture in ipairs({
    {'sortie-boss-skomora-v1','Skomora'},
    {'sortie-boss-ghatjot-v1','Ghatjot'},
    {'sortie-boss-leshonn-v1','Leshonn'},
}) do
    local profile_id,target_name=fixture[1],fixture[2]

    local h=harness(profile_id,target_name)
    h:activate(); h:tick(0)
    assert(h:last('authorize',{id=h.mob.id}))
    assert(h:last('force',{id=h.mob.id,members='Tackleberry'}))
    assert(h:count('force',{members=
        'Dolomedes,Kickpuncher,Barneystinson,Smalls,Achoo'})==0)

    h.mob.claim_id=ACTOR.Tackleberry
    h:action(pull_action(h),0.2)
    assert(h:last('force',{id=h.mob.id,members=
        'Dolomedes,Kickpuncher,Barneystinson,Smalls,Achoo'}))
    h:tick(0.4); h:tick(1.0)
    assert(h:count('force',{members=
        'Dolomedes,Kickpuncher,Barneystinson,Smalls,Achoo'})==1)

    h.mob.hpp=0; h:tick(1.2)
    assert(h:last('stop',{members=
        'Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo'}))
    assert(h:last('release',{id=h.mob.id,keep=true}))
    assert(h.armed==true)

    local fallback=harness(profile_id,target_name)
    fallback:activate(); fallback:tick(0)
    fallback:tick(0.7); fallback:tick(1.4)
    assert(fallback:count('force',{members='Tackleberry'})==3)
    assert(fallback:count('force',{members=
        'Dolomedes,Kickpuncher,Barneystinson,Smalls,Achoo'})==0)
    fallback:tick(2.1)
    assert(fallback:count('force',{members=
        'Dolomedes,Kickpuncher,Barneystinson,Smalls,Achoo'})==1)

    local inert=harness(profile_id,target_name)
    inert:activate(); inert.mob.name='Wrong Boss'; inert:tick(0)
    assert(inert:count('authorize')==0)
    inert.mob.name=target_name; inert.zone=267; inert:tick(1)
    assert(inert:count('authorize')==0)

    local disarmed=harness(profile_id,target_name)
    disarmed:activate(); disarmed:tick(0)
    disarmed.armed=false; disarmed:tick(0.2)
    assert(disarmed:last('release',{id=disarmed.mob.id,keep=false}))
    disarmed:tick(3)
    assert(disarmed:count('authorize')==1)
end

print('PASS - Sortie boss exact-target tank-first pull runtimes')
