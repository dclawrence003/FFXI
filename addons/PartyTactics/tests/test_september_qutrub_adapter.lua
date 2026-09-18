-- Behavioral boundary tests for the isolated Bigwig GearSwap adapter.

local source = debug.getinfo(1,'S').source:gsub('^@','')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1] or
    (test_dir..'/../gearswap/adapters/'
        ..'ambuscade-2026-09-v1-qutrub-bigwig/1.1.0.lua')

local EXPECTED_SUB = {
    COR='NIN',PLD='NIN',DNC='NIN',BRD='SMN',RDM='SMN',GEO='WHM',
}
local CHARACTER = {
    COR='Dolomedes',PLD='Tackleberry',DNC='Kickpuncher',
    BRD='Barneystinson',RDM='Smalls',GEO='Achoo',
}
local PARTY_NAMES = {
    'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo',
}
local PARTY_IDS = {
    Dolomedes=1001,Tackleberry=1002,Kickpuncher=1003,
    Barneystinson=1004,Smalls=1005,Achoo=1006,
}

local function new_world(job, options)
    options=options or {}
    local clock=100
    local inputs,commands,chats,cancelled_buffs={},{},{},{}
    local local_name=assert(CHARACTER[job])
    local equipment_calls=0
    local local_player={
        id=PARTY_IDS[local_name],name=local_name,main_job=job,
        sub_job=options.sub_job or EXPECTED_SUB[job],
        status=options.status or 'Engaged',hpp=100,mpp=100,
        hp=3000,mp=1000,tp=3000,buffs=options.buffs or {},
    }
    local boss={id=17990001,index=411,
        name=options.name or 'Bozzetto Bigwig',spawn_type=16,
        valid_target=true,hpp=100,
        claim_id=options.unclaimed and 0 or options.foreign and 999999
            or local_player.id,
        distance=16,model_size=1,x=0,y=0}
    local mobs={boss}
    local party={}
    local party_mobs={}
    for index,name in ipairs(PARTY_NAMES) do
        local slot=index-1
        local support=name=='Barneystinson' or name=='Smalls' or name=='Achoo'
        local hpp=options.party_hpp and options.party_hpp[name] or 100
        local mob={id=PARTY_IDS[name],index=PARTY_IDS[name]%65535,
            name=name,valid_target=true,hpp=hpp,
            x=support and 18 or 1,y=0,distance=4,model_size=0}
        party_mobs[name]=mob
        mobs[#mobs+1]=mob
        party['p'..slot]={name=name,hpp=hpp,id=mob.id,mob_id=mob.id,
            mob=mob}
    end
    local spells={
        [2]=true,[4]=true,[33]=true,[59]=true,[112]=true,[260]=true,
        [307]=true,[338]=true,[339]=true,
        [393]=true,[476]=true,[818]=true,
    }
    local abilities={
        weapon_skills={25,42,221},
        job_abilities={48,89,92,255,278,332,522},
    }
    local spell_recasts={
        [2]=0,[4]=0,[33]=0,[59]=0,[112]=0,[260]=0,[307]=0,
        [338]=0,[339]=0,
        [393]=0,[476]=0,[818]=0,
    }
    local ability_recasts={
        [42]=0,[75]=0,[77]=0,[80]=0,[171]=0,[174]=0,[254]=0,
    }
    local items=options.has_food_item == false and {}
        or {{id=6343,count=6}}

    local env=setmetatable({}, {__index=_G})
    env._G=env
    env.PARTYTACTICS_QUTRUB_TEST_MODE=true
    env.os=setmetatable({clock=function() return clock end},{__index=os})
    env.player=local_player
    env.buffactive={}
    env.pet=not options.no_pet and (options.pet
        or {id=800,index=800,name='Cait Sith',isvalid=true,
            valid_target=true}) or nil
    env.moving=false
    env.tickdelay=0
    env.next_cast=0
    env.latency=1
    env.spell_latency=1
    env.midaction=function() return env._busy==true end
    env.silent_check_disable=function() return env._disabled==true end
    env.silent_check_amnesia=function() return env._amnesia==true end
    env.silent_can_use=function() return env._spell_blocked~=true end
    env.equip=function() equipment_calls=equipment_calls+1 end
    env.add_to_chat=function(color,message)
        chats[#chats+1]={color=color,message=message}
    end
    env.res={
        items={[6343]={id=6343,en='Grape Daifuku'}},
        weapon_skills={
            [25]={id=25,en='Evisceration'},
            [42]={id=42,en='Savage Blade'},
            [221]={id=221,en='Last Stand'},
        },
        job_abilities={
            [48]={id=48,en='Sentinel',recast_id=75},
            [89]={id=89,en='Retreat',recast_id=171,mp_cost=0},
            [92]={id=92,en='Rampart',recast_id=77},
            [255]={id=255,en='Divine Emblem',recast_id=80},
            [278]={id=278,en='Palisade',recast_id=42},
            [332]={id=332,en='Clarion Call',recast_id=254},
            [522]={id=522,en='Mewing Lullaby',recast_id=174,mp_cost=61},
        },
        spells={
            [2]={id=2,en='Cure II',recast_id=2,mp_cost=24},
            [4]={id=4,en='Cure IV',recast_id=4,mp_cost=88},
            [33]={id=33,en='Diaga',recast_id=33,mp_cost=12},
            [59]={id=59,en='Silence',recast_id=59,mp_cost=16},
            [112]={id=112,en='Flash',recast_id=112,mp_cost=25},
            [260]={id=260,en='Dispel',recast_id=260,mp_cost=25},
            [307]={id=307,en='Cait Sith',recast_id=307,mp_cost=5},
            [338]={id=338,en='Utsusemi: Ichi',recast_id=338,mp_cost=0},
            [339]={id=339,en='Utsusemi: Ni',recast_id=339,mp_cost=0},
            [393]={id=393,en="Knight's Minne V",recast_id=393,mp_cost=0},
            [476]={id=476,en='Crusade',recast_id=476,mp_cost=18},
            [818]={id=818,en='Geo-Frailty',recast_id=818,mp_cost=294},
        },
    }
    env.windower={
        chat={input=function(command) inputs[#inputs+1]=command end},
        send_command=function(command) commands[#commands+1]=command end,
        ffxi={
            get_player=function()
                return {id=local_player.id,main_job=local_player.main_job,
                    sub_job=local_player.sub_job,status=local_player.status,
                    buffs=local_player.buffs,vitals={hpp=local_player.hpp}}
            end,
            get_info=function()
                return {logged_in=env._logged_out~=true,
                    zone=env._zone or options.zone or 287}
            end,
            get_mob_by_id=function(id)
                for _,mob in ipairs(mobs) do
                    if tonumber(id)==mob.id and not mob.hidden then return mob end
                end
            end,
            get_mob_by_target=function(token)
                return token=='pet' and env.pet or nil
            end,
            get_mob_array=function() return mobs end,
            get_party=function() return party end,
            get_abilities=function() return abilities end,
            get_spells=function() return spells end,
            get_spell_recasts=function() return spell_recasts end,
            get_ability_recasts=function() return ability_recasts end,
            get_items=function(bag) return bag==0 and items or {} end,
            cancel_buff=function(id) cancelled_buffs[#cancelled_buffs+1]=id end,
        },
    }

    local loader,load_error
    if setfenv then
        loader,load_error=loadfile(adapter_path)
        if loader then setfenv(loader,env) end
    else
        loader,load_error=loadfile(adapter_path,'t',env)
    end
    assert(loader,load_error)
    local adapter=loader()
    assert(adapter.id=='ambuscade-2026-09-v1-qutrub-bigwig')
    assert(adapter.version=='1.1.0' and adapter.controller=='qutrub-bigwig')
    local generation='1700000000-1001-1'
    local probe_ok=adapter.handle_action('qutrub-bigwig','probe',
        {generation,'0','1'})
    if options.bad_probe then
        assert(probe_ok==false)
    else
        assert(probe_ok==true)
    end
    while #commands>0 do table.remove(commands) end

    local world={env=env,adapter=adapter,queue=adapter._test_queue,
        player=local_player,boss=boss,mobs=mobs,party=party,inputs=inputs,
        commands=commands,chats=chats,spells=spells,abilities=abilities,
        party_mobs=party_mobs,cancelled_buffs=cancelled_buffs,
        spell_recasts=spell_recasts,ability_recasts=ability_recasts,
        generation=generation,epoch=0}
    function world:add(id,name,opts)
        opts=opts or {}
        local mob={id=id,index=opts.index or id%65535,name=name,
            spawn_type=16,valid_target=opts.valid_target~=false,
            hpp=opts.hpp or 100,claim_id=opts.claim_id or 0,
            distance=opts.distance or 16,model_size=1,
            x=opts.x or 1,y=opts.y or 1}
        self.mobs[#self.mobs+1]=mob
        return mob
    end
    function world:member(name) return self.party_mobs[name] end
    function world:set_hpp(name,hpp)
        local mob=assert(self:member(name))
        mob.hpp=hpp
        for index=0,5 do
            local member=self.party['p'..index]
            if member and member.name==name then member.hpp=hpp end
        end
        if name==self.player.name then self.player.hpp=hpp end
    end
    function world:advance(seconds) clock=clock+seconds end
    function world:command(semantic,subject,token)
        local args={tostring(self.boss.id),self.generation,tostring(self.epoch)}
        if semantic~='cancel' and subject then
            args[4]=token or '-'
            args[5]=tostring(subject.id or subject)
        elseif semantic~='cancel' and token then
            args[4]=token
        end
        return self.adapter.handle_action('qutrub-bigwig',semantic,args)
    end
    function world:packet(category,param,actor,targets)
        local packed={}
        for _,target in ipairs(targets) do
            packed[#packed+1]={id=target.id or target,
                actions={{param=1,message=target.message}}}
        end
        self.adapter.action_event({category=category,param=param,
            actor_id=actor or self.player.id,targets=packed})
    end
    function world:equipment_count() return equipment_calls end
    return world
end

-- Capability is exact to the assigned job/subjob and revokes cleanly.
new_world('COR')
new_world('PLD')
new_world('DNC')
new_world('BRD')
new_world('RDM')
new_world('GEO')
new_world('PLD',{sub_job='WAR',bad_probe=true})
new_world('RDM',{sub_job='WHM',bad_probe=true})
new_world('GEO',{sub_job='SMN',bad_probe=true})

-- Both Ambuscade instance IDs work; any other zone, wrong boss, or foreign
-- boss is rejected before a command reaches GearSwap.
for _,zone in ipairs({183,287}) do
    local w=new_world('COR',{zone=zone,buffs={251,446}})
    assert(w:command('close')==true)
    assert(w.inputs[1]=='/ws "Last Stand" 17990001')
end
for _,options in ipairs({{zone=130},{name='Bozzetto Bigwig Prime'},
    {foreign=true}}) do
    local w=new_world('COR',options)
    assert(w:command('food')==false and #w.inputs==0)
end

-- Unclaimed authority allows bounded preparation and exact pull Flash, never
-- offense. Food is consumed only if its server buff is absent.
local hungry=new_world('PLD',{unclaimed=true})
assert(hungry:command('food')==true)
assert(hungry.inputs[1]=='/item "Grape Daifuku" <me>')
local fed=new_world('PLD',{unclaimed=true,buffs={251},has_food_item=false})
assert(fed:command('food')==true and #fed.inputs==0)
assert(fed:command('flash')==true)
assert(fed.inputs[1]=='/ma "Flash" 17990001')
local unclaimed_dd=new_world('DNC',{unclaimed=true,buffs={251,446}})
assert(unclaimed_dd:command('lead')==false and #unclaimed_dd.inputs==0)

-- All cooldown mitigation is opportunistic. A repeat run with every JA and
-- Crusade on recast still reaches exact Flash without a queued cooldown gate.
local cooldown=new_world('PLD',{unclaimed=true,buffs={251}})
cooldown.spell_recasts[476]=99
for _,id in ipairs({42,75,77,80}) do cooldown.ability_recasts[id]=99 end
for _,semantic in ipairs({'crusade','divine-emblem','sentinel','rampart',
    'palisade'}) do
    assert(cooldown:command(semantic)==true)
    assert(cooldown.queue.request==nil)
end
assert(cooldown:command('flash')==true)
assert(cooldown.inputs[#cooldown.inputs]=='/ma "Flash" 17990001')

-- Geo-Frailty is pinned to spell 818 and actual Indi-Fury buff 549. Regen
-- buff 539 must neither satisfy nor accidentally dispatch the setup.
local wrong_colure=new_world('GEO',{buffs={539}})
assert(wrong_colure:command('setup')==true)
assert(#wrong_colure.inputs==0 and wrong_colure.queue.request)
wrong_colure.player.buffs={549}
wrong_colure.adapter.pre_tick()
assert(wrong_colure.inputs[1]=='/ma "Geo-Frailty" 17990001')

-- Exact add subjects accept both observed spellings. Foreign, distant, and
-- unrelated entities cannot receive Silence, Flash, or a weaponskill.
for _,name in ipairs({'Bozzetto Tormentor','Bozzetto Tormenter'}) do
    local w=new_world('PLD',{buffs={251}})
    local mob=w:add(17990010,name)
    assert(w:command('flash-add',mob)==true)
    assert(w.inputs[1]=='/ma "Flash" 17990010')
end
local exact=new_world('RDM')
local astro=exact:add(17990011,'Bozzetto Astrologer')
assert(exact:command('silence-add',astro)==true)
assert(exact.inputs[1]=='/ma "Silence" 17990011')
exact:packet(4,59,exact.player.id,{{id=astro.id}})
exact:advance(2)
assert(exact:command('dispel-ice-spikes',astro)==true)
assert(exact.inputs[2]=='/ma "Dispel" 17990011')
for _,opts in ipairs({{claim_id=999},{x=100,y=100,distance=10000}}) do
    local w=new_world('PLD',{buffs={251}})
    local mob=w:add(17990012,'Bozzetto Tormentor',opts)
    assert(w:command('flash-add',mob)==false and #w.inputs==0)
end
local unrelated=new_world('RDM')
local fake=unrelated:add(17990013,'Bozzetto Astrologer Prime')
assert(unrelated:command('silence-add',fake)==false)

-- Flash/Silence/Dispel maintenance is opportunistic at the adapter boundary:
-- a recast collision leaves no stale queue, while the runtime may retry it.
local maintenance=new_world('PLD',{buffs={251}})
local maintenance_add=maintenance:add(17990015,'Bozzetto Tormentor')
maintenance.spell_recasts[112]=99
assert(maintenance:command('flash-add',maintenance_add)==true)
assert(maintenance.queue.request==nil and #maintenance.inputs==0)
maintenance.spell_recasts[112]=0
assert(maintenance:command('flash-add',maintenance_add)==true)
assert(maintenance.inputs[1]=='/ma "Flash" 17990015')

local dispel_recast=new_world('RDM')
local dispel_astro=dispel_recast:add(17990016,'Bozzetto Astrologer')
dispel_recast.spell_recasts[260]=99
assert(dispel_recast:command('dispel-ice-spikes',dispel_astro)==true)
assert(dispel_recast.queue.request==nil and #dispel_recast.inputs==0)

-- A queued add action revalidates id+index every attempt; index reuse clears
-- it. No request can inherit an entity ID after the original life disappears.
local reuse=new_world('RDM')
reuse.env._busy=true
local original=reuse:add(17990014,'Bozzetto Astrologer',{index=514})
assert(reuse:command('silence-add',original)==true and reuse.queue.request)
original.index=614
reuse.adapter.pre_tick()
assert(reuse.queue.request==nil and #reuse.inputs==0)

-- Every attacker refuses WS without Copy Image. Losing the local shadow while
-- offense is queued cancels it, then the autonomous heartbeat selects Ni (or
-- Ichi when Ni is on recast) before any later WS can dispatch.
for _,job in ipairs({'COR','PLD','DNC'}) do
    local w=new_world(job,{buffs={251,446}})
    w.env._busy=true
    local semantic=job=='COR' and 'close' or job=='PLD' and 'middle' or 'lead'
    assert(w:command(semantic)==true)
    assert(w.queue.request)
    w.player.buffs={251}
    w.adapter.pre_tick()
    assert(w.queue.request==nil,'shadow loss did not cancel queued offense')
    w.env._busy=false
    w.adapter.pre_tick()
    assert(w.inputs[#w.inputs]=='/ma "Utsusemi: Ni" <me>')
end
local ichi=new_world('DNC',{buffs={251}})
ichi.spell_recasts[339]=99
assert(ichi:command('food')==true) -- binds the exact encounter; Food is no-op
ichi.adapter.pre_tick()
assert(ichi.inputs[1]=='/ma "Utsusemi: Ichi" <me>')

-- The runtime's explicit Ni request must not occupy the lane when Ni is on
-- recast; its Ichi fallback 1.5s later remains immediately dispatchable.
local ni_fallback=new_world('DNC',{buffs={251}})
ni_fallback.spell_recasts[339]=99
assert(ni_fallback:command('shadow-ni')==true)
assert(ni_fallback.queue.request==nil and #ni_fallback.inputs==0)
ni_fallback:advance(2)
assert(ni_fallback:command('shadow-ichi')==true)
assert(ni_fallback.inputs[1]=='/ma "Utsusemi: Ichi" <me>')

-- The two independent /SMN jobs own Cait/Mew; GEO/WHM must reject both so its
-- luopan remains available. Partial Mew packets are not completion: every
-- currently live associated add must have a successful result. Adapter
-- retries, then completes only on
-- a full boss+pack result. Foreign adds are deliberately outside the set.
local summon=new_world('RDM',{no_pet=true})
assert(summon:command('summon')==true)
assert(summon.inputs[1]=='/ma "Cait Sith" <me>')
local no_geo_pet=new_world('GEO')
assert(no_geo_pet:command('summon')==false)
assert(no_geo_pet:command('mew')==false and #no_geo_pet.inputs==0)

local mew=new_world('RDM')
local a=mew:add(17990020,'Bozzetto Astrologer')
local t=mew:add(17990021,'Bozzetto Tormentor')
mew:add(17990022,'Bozzetto Tormentor',{claim_id=999})
assert(mew:command('mew')==true)
assert(mew.inputs[1]=='/pet "Mewing Lullaby" 17990001')
mew:packet(11,2449,mew.env.pet.id,{{id=mew.boss.id},{id=a.id}})
assert(mew.queue.request and mew.queue.request.inflight_until==nil)
mew:advance(2)
mew.adapter.prerender()
assert(#mew.inputs==2)
mew:packet(11,2449,mew.env.pet.id,
    {{id=mew.boss.id},{id=a.id},{id=t.id}})
assert(mew.queue.request==nil)

-- Retreat keeps Cait summoned but stops the post-Blood-Pact re-engagement.
-- Its result may identify the master or exact current pet. It is short-lived,
-- best-effort cleanup and never gains authority without an existing Cait.
local retreat=new_world('BRD')
assert(retreat:command('retreat')==true)
assert(retreat.inputs[1]=='/pet "Retreat" <me>')
retreat:packet(6,89,retreat.player.id,{{id=retreat.env.pet.id}})
assert(retreat.queue.request==nil)
local retreat_without_pet=new_world('BRD',{no_pet=true})
assert(retreat_without_pet:command('retreat')==true)
assert(retreat_without_pet.queue.request==nil
    and #retreat_without_pet.inputs==0)

local retreat_failure=new_world('BRD')
assert(retreat_failure:command('retreat')==true)
retreat_failure:packet(6,89,retreat_failure.player.id,
    {{id=retreat_failure.player.id,message=4}})
assert(retreat_failure.queue.request==nil)
assert(retreat_failure:command('mew')==true)
retreat_failure:advance(2)
retreat_failure.adapter.prerender()
assert(retreat_failure.inputs[2]=='/pet "Mewing Lullaby" 17990001')

local retreat_timeout=new_world('BRD')
assert(retreat_timeout:command('retreat')==true)
retreat_timeout:advance(4.1)
retreat_timeout.adapter.prerender()
assert(retreat_timeout.queue.request==nil,
    'unconfirmed Retreat outlived its four-second cleanup window')
assert(retreat_timeout:command('mew')==true)
assert(retreat_timeout.inputs[2]=='/pet "Mewing Lullaby" 17990001')

local interrupted=new_world('RDM')
interrupted:add(17990023,'Bozzetto Astrologer')
interrupted:add(17990024,'Bozzetto Tormentor')
assert(interrupted:command('mew')==true and #interrupted.inputs==1)
interrupted.adapter.job_aftercast({id=522,interrupted=true,
    target={id=interrupted.boss.id}})
assert(interrupted.queue.request
    and interrupted.queue.request.inflight_until==nil)
interrupted:advance(2)
interrupted.adapter.prerender()
assert(#interrupted.inputs==2)

local mew_recast=new_world('BRD')
mew_recast.ability_recasts[174]=99
assert(mew_recast:command('mew')==true)
assert(mew_recast.queue.request and #mew_recast.inputs==0)
mew_recast:advance(13)
mew_recast.adapter.prerender()
assert(mew_recast.queue.request==nil,
    'Mewing recast blocker outlived its bounded reservation')

-- Smalls's supplemental Mew is lower priority than his encounter-critical
-- exact work. A waiting Mew can be preempted by Silence/Dispel and by the
-- low-HP exact cure; ordinary emergency Cure/-na also bypasses the queue.
local mew_priority=new_world('RDM')
mew_priority.env._busy=true
local priority_astro=mew_priority:add(
    17990030,'Bozzetto Astrologer')
assert(mew_priority:command('mew')==true)
assert(mew_priority.queue.request.semantic=='mew')
assert(mew_priority:command('silence-add',priority_astro)==true)
assert(mew_priority.queue.request.semantic=='silence-add')
local dispel_priority=new_world('RDM')
dispel_priority.env._busy=true
local dispel_priority_astro=dispel_priority:add(
    17990031,'Bozzetto Astrologer')
assert(dispel_priority:command('mew')==true)
assert(dispel_priority:command(
    'dispel-ice-spikes',dispel_priority_astro)==true)
assert(dispel_priority.queue.request.semantic=='dispel-ice-spikes')
local diaga_priority=new_world('RDM')
diaga_priority.env._busy=true
assert(diaga_priority:command('mew')==true)
assert(diaga_priority:command('diaga')==true)
assert(diaga_priority.queue.request.semantic=='diaga')

local retreat_priority=new_world('RDM')
local retreat_priority_astro=retreat_priority:add(
    17990032,'Bozzetto Astrologer')
assert(retreat_priority:command('retreat')==true)
assert(retreat_priority.queue.request.inflight_until)
assert(retreat_priority:command(
    'silence-add',retreat_priority_astro)==true)
assert(retreat_priority.queue.request.semantic=='silence-add',
    'in-flight Retreat blocked Astrologer Silence')

local cure_priority=new_world('RDM')
cure_priority.env._busy=true
cure_priority.boss.hpp=29
for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
    cure_priority:set_hpp(name,20)
end
for _,name in ipairs({'Barneystinson','Smalls','Achoo'}) do
    cure_priority:set_hpp(name,100)
    cure_priority:member(name).x=18
end
assert(cure_priority:command('lowhp-on')==true)
assert(cure_priority:command('mew')==true)
cure_priority:set_hpp('Dolomedes',12)
assert(cure_priority:command(
    'lowhp-cure',cure_priority:member('Dolomedes'))==true)
assert(cure_priority.queue.request.semantic=='lowhp-cure')

local retreat_cure_priority=new_world('RDM')
retreat_cure_priority.boss.hpp=29
for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
    retreat_cure_priority:set_hpp(name,20)
end
for _,name in ipairs({'Barneystinson','Smalls','Achoo'}) do
    retreat_cure_priority:set_hpp(name,100)
    retreat_cure_priority:member(name).x=18
end
assert(retreat_cure_priority:command('lowhp-on')==true)
assert(retreat_cure_priority:command('retreat')==true)
assert(retreat_cure_priority.queue.request.inflight_until)
retreat_cure_priority:set_hpp('Dolomedes',12)
assert(retreat_cure_priority:command(
    'lowhp-cure',retreat_cure_priority:member('Dolomedes'))==true)
assert(retreat_cure_priority.queue.request.semantic=='lowhp-cure',
    'in-flight Retreat blocked exact low-HP healing')

local emergency_bypass=new_world('RDM')
emergency_bypass.env._busy=true
assert(emergency_bypass:command('mew')==true)
assert(emergency_bypass.adapter.filter_pretarget({id=4,en='Cure IV',
    target={id=PARTY_IDS.Tackleberry,name='Tackleberry'}})==false)
assert(emergency_bypass.adapter.filter_pretarget({id=15,en='Poisona',
    target={id=PARTY_IDS.Tackleberry,name='Tackleberry'}})==false)
local retreat_emergency_bypass=new_world('RDM')
assert(retreat_emergency_bypass:command('retreat')==true)
assert(retreat_emergency_bypass.adapter.filter_pretarget({id=4,en='Cure IV',
    target={id=PARTY_IDS.Tackleberry,name='Tackleberry'}})==false)
assert(retreat_emergency_bypass.adapter.filter_pretarget({id=15,en='Poisona',
    target={id=PARTY_IDS.Tackleberry,name='Tackleberry'}})==false)
assert(retreat_emergency_bypass:equipment_count()==0)

local function lowhp_ready(w)
    w.boss.hpp=29
    for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
        w:set_hpp(name,20)
    end
    for _,name in ipairs({'Barneystinson','Smalls','Achoo'}) do
        w:set_hpp(name,100)
        w:member(name).x=18
        w:member(name).y=0
    end
end

-- Low-HP authority is exact, claimed, heartbeat-bound, and shared by all six
-- clients. Each attacker still needs local Copy Image proof, while the three
-- named attacker HP values, support health, evacuation, and Cure II reach all
-- independently fail closed before a final-phase WS can dispatch.
for _,job in ipairs({'COR','PLD','DNC'}) do
    local w=new_world(job,{buffs={251,446}})
    lowhp_ready(w)
    assert(w:command('lowhp-on')==true)
    local semantic=job=='COR' and 'close' or job=='PLD' and 'middle' or 'lead'
    assert(w:command(semantic)==true)
    assert(#w.inputs==1,
        job..' did not dispatch from the fully proven low-HP band')
end
for _,options in ipairs({{unclaimed=true},{foreign=true}}) do
    local w=new_world('RDM',options)
    assert(w:command('lowhp-on')==false)
end

local function assert_lowhp_offense_blocked(mutator,label)
    local w=new_world('COR',{buffs={251,446}})
    lowhp_ready(w)
    mutator(w)
    assert(w:command('lowhp-on')==true)
    assert(w:command('close')==true)
    assert(#w.inputs==0 and w.queue.request,
        label..' did not hold final-phase offense')
end
assert_lowhp_offense_blocked(function(w) w:set_hpp('Dolomedes',12) end,
    'attacker below 13%')
assert_lowhp_offense_blocked(function(w) w:set_hpp('Kickpuncher',26) end,
    'attacker above 25%')
assert_lowhp_offense_blocked(function(w) w:set_hpp('Achoo',59) end,
    'low support')
assert_lowhp_offense_blocked(function(w) w:member('Barneystinson').x=16 end,
    'support inside Spin range')
assert_lowhp_offense_blocked(function(w) w:member('Achoo').x=nil end,
    'missing support coordinates')
assert_lowhp_offense_blocked(function(w) w:member('Smalls').x=22 end,
    'Smalls outside exact Cure II reach')

-- The RDM-owned rescue spells accept only a live exact party member and
-- bypass the legacy-heal filter only for the adapter's own in-flight action.
local no_guard=new_world('RDM')
no_guard.boss.hpp=29
no_guard:set_hpp('Dolomedes',12)
assert(no_guard:command('lowhp-cure',no_guard:member('Dolomedes'))==false)
assert(no_guard:command('lowhp-on')==true)
no_guard:member('Dolomedes').valid_target=nil
assert(no_guard:command('lowhp-cure',no_guard:member('Dolomedes'))==false,
    'unobservable party target passed exact Cure validation')

local stale_roster=new_world('RDM')
stale_roster.boss.hpp=29
assert(stale_roster:command('lowhp-on')==true)
stale_roster:member('Dolomedes').hpp=0
assert(stale_roster:command('lowhp-cure',
    stale_roster:member('Dolomedes'))==false,
    'stale positive roster HP fabricated a live Cure subject')

local rescue=new_world('RDM')
lowhp_ready(rescue)
rescue:set_hpp('Dolomedes',12)
assert(rescue:command('lowhp-on')==true)
assert(rescue:command('lowhp-cure',rescue:member('Dolomedes'))==true)
assert(rescue.inputs[1]=='/ma "Cure II" 1001')
assert(rescue.adapter.filter_precast({id=2,en='Cure II',
    target={id=PARTY_IDS.Dolomedes,name='Dolomedes'}})==false)
rescue:packet(4,2,rescue.player.id,{{id=PARTY_IDS.Dolomedes}})
assert(rescue.queue.request==nil)
rescue:set_hpp('Barneystinson',55)
rescue:advance(2)
assert(rescue:command('support-cure',rescue:member('Barneystinson'))==true)
assert(rescue.inputs[2]=='/ma "Cure IV" 1004')

local reused_member=new_world('RDM')
lowhp_ready(reused_member)
reused_member.env._busy=true
assert(reused_member:command('lowhp-on')==true)
local dolo=reused_member:member('Dolomedes')
assert(reused_member:command('lowhp-cure',dolo)==true)
dolo.index=dolo.index+1
reused_member.adapter.pre_tick()
assert(reused_member.queue.request==nil,
    'reused party entity inherited an exact Cure reservation')

local expired_rescue=new_world('RDM')
lowhp_ready(expired_rescue)
expired_rescue.env._busy=true
assert(expired_rescue:command('lowhp-on')==true)
assert(expired_rescue:command('lowhp-cure',
    expired_rescue:member('Dolomedes'))==true)
expired_rescue:advance(7)
expired_rescue.adapter.pre_tick()
expired_rescue.env._busy=false
expired_rescue.adapter.pre_tick()
assert(expired_rescue.queue.request==nil and #expired_rescue.inputs==0,
    'expired low-HP authority left a delayed Cure dispatchable')

local healed_boss=new_world('RDM')
lowhp_ready(healed_boss)
assert(healed_boss:command('lowhp-on')==true)
healed_boss.boss.hpp=45
healed_boss:advance(7)
healed_boss.adapter.pre_tick()
assert(healed_boss:command('lowhp-on')==true,
    'expired heartbeat could not rearm after Bigwig healed above 30%')

local cancelled_rescue=new_world('RDM')
lowhp_ready(cancelled_rescue)
cancelled_rescue.env._busy=true
assert(cancelled_rescue:command('lowhp-on')==true)
assert(cancelled_rescue:command('lowhp-cure',
    cancelled_rescue:member('Dolomedes'))==true)
assert(cancelled_rescue:command('lowhp-off')==true)
cancelled_rescue.env._busy=false
cancelled_rescue.adapter.pre_tick()
assert(cancelled_rescue.queue.request==nil and #cancelled_rescue.inputs==0,
    'explicit lowhp-off left a delayed Cure dispatchable')

-- Legacy healing is suppressed narrowly: targeted heals cannot top up an
-- attacker, all AoE HP restoration and Majesty are blocked, while a targeted
-- support Cure remains available. Expiry/explicit off/deactivation release
-- the guard, and PLD cancels an already-active Majesty on entry.
local filters=new_world('RDM')
filters.boss.hpp=29
assert(filters:command('lowhp-on')==true)
local attacker_target={id=PARTY_IDS.Tackleberry,name='Tackleberry'}
local support_target={id=PARTY_IDS.Achoo,name='Achoo'}
assert(filters.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=attacker_target})==true)
assert(filters:command('cancel')==true)
assert(filters.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=attacker_target})==true,
    'generic queue cancel incorrectly cleared the low-HP guard')
assert(filters.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=support_target})==false)
assert(filters.adapter.filter_pretarget(
    {id=7,en='Curaga III',target=support_target})==true)
assert(filters.adapter.filter_pretarget(
    {id=190,en='Divine Waltz II',target=support_target})==true)
filters:advance(7)
assert(filters.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=attacker_target})==false,
    'expired heartbeat left the low-HP heal filter active')

local majesty=new_world('PLD',{buffs={621}})
majesty.boss.hpp=29
assert(majesty:command('lowhp-on')==true)
assert(majesty.cancelled_buffs[1]==621)
assert(majesty.adapter.filter_pretarget(
    {id=394,en='Majesty',target={id=majesty.player.id,
        name=majesty.player.name}})==true)
assert(majesty:command('lowhp-off')==true)
assert(majesty.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=attacker_target})==false)

local guarded_deactivate=new_world('RDM')
guarded_deactivate.boss.hpp=29
assert(guarded_deactivate:command('lowhp-on')==true)
guarded_deactivate.env._busy=true
assert(guarded_deactivate:command('lowhp-cure',
    guarded_deactivate:member('Dolomedes'))==true)
guarded_deactivate.adapter.deactivate('test low-HP teardown')
assert(guarded_deactivate.queue.request==nil)
assert(guarded_deactivate.adapter.filter_pretarget(
    {id=4,en='Cure IV',target=attacker_target})==false)

-- Clarion and the fourth song are opportunistic. Cooldown/missing Clarion
-- status leaves the native three-song baseline untouched and never queues.
local songs=new_world('BRD')
songs.ability_recasts[254]=99
assert(songs:command('clarion')==true and songs.queue.request==nil)
assert(songs:command('fourth-song')==true and songs.queue.request==nil)
assert(#songs.inputs==0)
local ready_songs=new_world('BRD')
assert(ready_songs:command('clarion')==true)
assert(ready_songs.inputs[1]=='/ja "Clarion Call" <me>')
ready_songs:packet(6,332,ready_songs.player.id,
    {{id=ready_songs.player.id}})
ready_songs.player.buffs={499}
ready_songs:advance(2)
assert(ready_songs:command('fourth-song')==true)
assert(ready_songs.inputs[2]=='/ma "Knight\'s Minne V" <me>')
assert(ready_songs:equipment_count()==0)

-- Local death and deactivation revoke all request/binding state. The adapter
-- never invokes an equipment function, including BRD song and Mew paths.
local lifecycle=new_world('BRD')
assert(lifecycle:command('summon')==true) -- existing Cait, no cast
lifecycle.adapter.status_change(2)
assert(lifecycle.queue.request==nil)
lifecycle.adapter.deactivate('test complete')
assert(lifecycle.commands[1]
    and lifecycle.commands[1]:find('__controller_lost qutrub-bigwig',1,true))
assert(lifecycle:equipment_count()==0)

print('PartyTactics September Qutrub adapter tests passed.')
