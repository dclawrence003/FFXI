-- Deterministic encounter-state tests for September V1 Bozzetto Bigwig.

local BASE = 'addons/PartyTactics/'
local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/ambuscade-2026-09-v1-qutrub-bigwig/runtime.lua',
    loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()

local NAMES = {
    'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo',
}
local IDS = {
    Dolomedes=1,Tackleberry=2,Kickpuncher=3,
    Barneystinson=4,Smalls=5,Achoo=6,
}
local SPELL = {
    CureII=2, CureIV=4, Diaga=33, Silence=59, Flash=112, CaitSith=307,
    IceSpikes=250, Dispel=260,
    UtsusemiIchi=338, UtsusemiNi=339, UtsusemiSan=340,
    Crusade=476, GeoFrailty=818,
}
local WS = {Evisceration=25,SavageBlade=42,LastStand=221}
local JA = {
    Sentinel=48,Retreat=89,Rampart=92,DivineEmblem=255,Palisade=278,
    Clarion=332,Mewing=522,
}
local MOVE = {PerfectDodge=7001,Mewing=2449}

local spells = {
    [SPELL.CureII]={id=SPELL.CureII,en='Cure II'},
    [SPELL.CureIV]={id=SPELL.CureIV,en='Cure IV'},
    [SPELL.Diaga]={id=SPELL.Diaga,en='Diaga'},
    [SPELL.Silence]={id=SPELL.Silence,en='Silence'},
    [SPELL.Flash]={id=SPELL.Flash,en='Flash'},
    [SPELL.IceSpikes]={id=SPELL.IceSpikes,en='Ice Spikes'},
    [SPELL.Dispel]={id=SPELL.Dispel,en='Dispel'},
    [SPELL.CaitSith]={id=SPELL.CaitSith,en='Cait Sith'},
    [SPELL.UtsusemiIchi]={id=SPELL.UtsusemiIchi,en='Utsusemi: Ichi'},
    [SPELL.UtsusemiNi]={id=SPELL.UtsusemiNi,en='Utsusemi: Ni'},
    [SPELL.UtsusemiSan]={id=SPELL.UtsusemiSan,en='Utsusemi: San'},
    [SPELL.Crusade]={id=SPELL.Crusade,en='Crusade'},
    [SPELL.GeoFrailty]={id=SPELL.GeoFrailty,en='Geo-Frailty'},
}
local weapon_skills = {
    [WS.Evisceration]={id=WS.Evisceration,en='Evisceration'},
    [WS.SavageBlade]={id=WS.SavageBlade,en='Savage Blade'},
    [WS.LastStand]={id=WS.LastStand,en='Last Stand'},
}
local job_abilities = {
    [JA.Sentinel]={id=JA.Sentinel,en='Sentinel'},
    [JA.Retreat]={id=JA.Retreat,en='Retreat'},
    [JA.Rampart]={id=JA.Rampart,en='Rampart'},
    [JA.DivineEmblem]={id=JA.DivineEmblem,en='Divine Emblem'},
    [JA.Palisade]={id=JA.Palisade,en='Palisade'},
    [JA.Clarion]={id=JA.Clarion,en='Clarion Call'},
    [JA.Mewing]={id=JA.Mewing,en='Mewing Lullaby'},
}
local monster_abilities = {
    [MOVE.PerfectDodge]={id=MOVE.PerfectDodge,en='Perfect Dodge'},
    [MOVE.Mewing]={id=MOVE.Mewing,en='Mewing Lullaby'},
}

local function result(param, message, add_message, add_param)
    return {param=param == nil and 1 or param, message=message,
        add_effect_message=add_message, add_effect_param=add_param}
end

local function action(category, source, param, target_id, value)
    return {category=category,actor_id=IDS[source] or source,param=param,
        targets={{id=target_id,actions={value or result(1)}}}}
end

local function multi_action(category, source, param, targets)
    local packed = {}
    for _, target in ipairs(targets) do
        packed[#packed + 1] = {id=target.id,
            actions={target.result or result(1)}}
    end
    return {category=category,actor_id=IDS[source] or source,param=param,
        targets=packed}
end

local function monster_ready(boss_id, ability_id)
    return {category=7,actor_id=boss_id,
        targets={{id=IDS.Tackleberry,actions={{param=ability_id}}}}}
end

local function boss(id)
    return {id=id or 300,index=(id or 300)+1000,name='Bozzetto Bigwig',
        spawn_type=16,valid_target=true,hpp=100,claim_id=0,
        x=0,y=0,distance=4}
end

local function add(id, name, options)
    options = options or {}
    return {id=id,index=options.index or id+1000,name=name,
        spawn_type=16,valid_target=options.valid_target ~= false,
        hpp=options.hpp or 100,claim_id=options.claim_id or 0,
        x=options.x or 1,y=options.y or 1,distance=options.distance or 4}
end

local function make_harness(zone)
    local h = {
        now=0,zone=zone or 287,armed=false,combat_ready=true,
        encounter_operational=true,can_authorize=true,authority=nil,
        party_hpp=100,tp={},
        buffs={[251]=false,[446]=false},calls={},mobs={},selected=nil,
        members={},
    }
    h.boss = boss(300)
    h.mobs[1] = h.boss
    for _, name in ipairs(NAMES) do
        h.tp[name] = 0
        local support = name == 'Barneystinson' or name == 'Smalls'
            or name == 'Achoo'
        local mob = {id=IDS[name],index=IDS[name],name=name,
            valid_target=true,hpp=100,x=support and 18 or 1,y=0,distance=4}
        h.members[name] = mob
        h.mobs[#h.mobs + 1] = mob
    end
    function h:mob_by_id(id)
        id = tonumber(id)
        for _, mob in ipairs(self.mobs) do
            if mob.id == id then return mob end
        end
    end
    function h:record(value)
        value.at = self.now
        self.calls[#self.calls + 1] = value
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
    h.runtime = runtime_module.create()
    h.context = {
        now=function() return h.now end,
        player_name=function() return 'Dolomedes' end,
        zone_id=function() return h.zone end,
        operator_armed=function() return h.armed end,
        combat_ready=function() return h.combat_ready end,
        current_target=function() return h.selected end,
        mob_by_id=function(id) return h:mob_by_id(id) end,
        mob_array=function() return h.mobs end,
        party_claimed=function(mob)
            return mob and tonumber(mob.claim_id) == IDS.Dolomedes
        end,
        party_hpp_floor=function() return h.party_hpp end,
        party_tp=function(name) return h.tp[name] end,
        has_buff_id=function(id) return h.buffs[tonumber(id)] == true end,
        spell=function(id) return spells[tonumber(id)] end,
        weapon_skill=function(id) return weapon_skills[tonumber(id)] end,
        job_ability=function(id) return job_abilities[tonumber(id)] end,
        monster_ability=function(id)
            return monster_abilities[tonumber(id)]
        end,
        authorize_encounter=function(id)
            h:record({kind='authorize',id=id})
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
            h:record({kind='release',id=id})
            if h.authority ~= id then return false end
            h.authority = nil
            return true
        end,
        alert=function(message,audible)
            h:record({kind='alert',message=message,audible=audible})
        end,
        actions={
            party_adapter=function(recipient,semantic,id,token,subject)
                h:record({kind='controller',recipient=recipient,
                    semantic=semantic,id=id,token=token,subject=subject})
                return true
            end,
            combat_force=function(id)
                h:record({kind='force',id=id})
                h.selected = h:mob_by_id(id)
                return true
            end,
            combat_stop=function()
                h:record({kind='stop'})
                h.selected = nil
                return true
            end,
        },
        client={auto_target=function(value)
            h:record({kind='autotarget',value=value})
            return true
        end},
    }
    function h:tick(at)
        self.now=at
        self.runtime:on_tick(self.context,at)
    end
    function h:perform(packet,at)
        self.now=at or self.now
        self.runtime:on_action(self.context,packet)
    end
    function h:add(mob) self.mobs[#self.mobs+1]=mob return mob end
    function h:remove(mob) mob.valid_target=false mob.hpp=0 end
    h.runtime:on_activate(h.context)
    return h
end

local function prove_pld(h, at)
    local t = IDS.Tackleberry
    h:perform(action(4,'Tackleberry',SPELL.Crusade,t),at)
    h:perform(action(6,'Tackleberry',JA.DivineEmblem,t),at+.01)
    h:perform(action(6,'Tackleberry',JA.Sentinel,t),at+.02)
    h.boss.claim_id=IDS.Dolomedes
    h:perform(action(4,'Tackleberry',SPELL.Flash,h.boss.id),at+.03)
end

local function setup(h)
    h:tick(0)
    assert(h:count('authorize') == 0)
    h.armed=true
    h:tick(.25)
    assert(h:count('authorize') == 1)
    assert(h:count('force') == 0,
        'unclaimed boss was forced before packet-confirmed Flash')
    assert(h:count('controller',{semantic='food'}) == 3)
    assert(h:count('controller',{semantic='shadow-ni'}) == 3)
    prove_pld(h,.30)
    h:tick(.60)
    h:perform(action(4,'Achoo',SPELL.GeoFrailty,h.boss.id),.65)
    h.buffs[251]=true
    h.buffs[446]=true
    h:tick(5.50)
    return h
end

-- Both valid Ambuscade instance zones use the same exact encounter policy.
for _, zone in ipairs({183,287}) do
    local h=setup(make_harness(zone))
    assert(h.authority == h.boss.id)
end
local bad_zone=make_harness(130)
bad_zone.armed=true
bad_zone:tick(.25)
assert(bad_zone:count('authorize') == 0)

-- Cooldown mitigation is an opportunistic sequence, not a pull gate. With no
-- completion packet for any optional step, the finite windows still advance
-- to mandatory exact-ID Flash and only that result unlocks claim handling.
local cooldown=make_harness()
cooldown:tick(0)
cooldown.armed=true
cooldown:tick(.25)
cooldown.buffs[251]=true cooldown.buffs[446]=true
for _,at in ipairs({2.3,3.9,5.5,7.1,8.7,10.3}) do cooldown:tick(at) end
assert(cooldown:last('controller',{semantic='flash'}))
assert(cooldown:count('controller',{semantic='rampart'})==0
    and cooldown:count('controller',{semantic='palisade'})==0,
    'pack mitigation was wasted in the pre-pull sequence')
assert(cooldown:count('force')==0)
cooldown.boss.claim_id=IDS.Dolomedes
cooldown:perform(action(4,'Tackleberry',SPELL.Flash,cooldown.boss.id),10.4)
cooldown:tick(10.7)
cooldown:perform(action(4,'Achoo',SPELL.GeoFrailty,cooldown.boss.id),10.8)
cooldown:tick(11.1)
assert(cooldown:count('force',{id=cooldown.boss.id})>=1)

-- Food reservations run in bounded heartbeat cycles. An initially blocked
-- item action and a later Food expiration therefore cannot deadlock offense.
local food_retry=make_harness()
food_retry:tick(0) food_retry.armed=true
for _,at in ipairs({.25,1.3,2.4,3.5}) do food_retry:tick(at) end
assert(food_retry:count('controller',
    {recipient='Dolomedes',semantic='food'})==4)
food_retry:tick(18.6)
assert(food_retry:count('controller',
    {recipient='Dolomedes',semantic='food'})==5,
    'blocked food preparation never began a new bounded cycle')

local food_expiry=setup(make_harness())
food_expiry:tick(6.6) food_expiry:tick(7.7)
local food_before=food_expiry:count('controller',
    {recipient='Dolomedes',semantic='food'})
food_expiry.buffs[251]=false
food_expiry.tp={Dolomedes=1200,Tackleberry=1200,Kickpuncher=1200}
food_expiry:tick(22.8)
assert(food_expiry:count('controller',
    {recipient='Dolomedes',semantic='food'})>food_before)
assert(food_expiry:count('controller',{semantic='lead'})==0,
    'offense continued after local Food expired')

-- Force cannot precede Flash, and a fresh arm edge is required after death.
local pull=setup(make_harness())
assert(pull:count('force',{id=pull.boss.id}) >= 1)
pull.boss.hpp=0 pull.boss.valid_target=false
pull:tick(6)
assert(pull:count('release',{id=pull.boss.id}) == 1)
local replacement=pull:add(boss(301))
replacement.claim_id=0
pull:tick(6.3)
assert(pull:count('authorize',{id=replacement.id}) == 0)
pull.armed=false pull:tick(6.6)
pull.armed=true pull:tick(6.9)
assert(pull:count('authorize',{id=replacement.id}) == 1)

local death=setup(make_harness())
death.party_hpp=0
death:tick(6)
assert(death:count('release',{id=death.boss.id})==1)
assert(death:last('stop'), 'party-member death did not stop PartyCombat')

-- Add order is exact: Astrologer, then either accepted Tormentor spelling.
-- A foreign or unassociated impostor is ignored. Tackle's exact add Flash
-- gates the first force handoff, and Smalls gets the exact Astrologer ID.
local adds=setup(make_harness())
local astro=adds:add(add(400,'Bozzetto Astrologer'))
local tormenter=adds:add(add(401,'Bozzetto Tormenter'))
local tormentor=adds:add(add(402,'Bozzetto Tormentor'))
adds:add(add(399,'Bozzetto Astrologer',{claim_id=999}))
adds:add(add(398,'Unrelated Astrologer'))
adds:tick(6.0)
local flash=assert(adds:last('controller',{semantic='flash-add'}))
assert(flash.recipient=='Tackleberry' and flash.subject==astro.id)
local silence=assert(adds:last('controller',{semantic='silence-add'}))
assert(silence.recipient=='Smalls' and silence.subject==astro.id)
assert(adds:count('force',{id=astro.id}) == 0)
adds:perform(action(4,'Tackleberry',SPELL.Flash,astro.id),6.1)
adds:tick(6.3)
assert(adds:count('force',{id=astro.id}) == 1)
adds:remove(astro)
adds:tick(6.6)
assert(adds:last('controller',{semantic='flash-add'}).subject==tormenter.id)
adds:perform(action(4,'Tackleberry',SPELL.Flash,tormenter.id),6.7)
adds:tick(6.9)
assert(adds:count('force',{id=tormenter.id}) == 1)
adds:remove(tormenter)
adds:tick(7.2)
assert(adds:last('controller',{semantic='flash-add'}).subject==tormentor.id)

-- A rejected add Flash never exhausts permanently. The initial handoff is
-- bounded, later cycles keep probing, and an expired confirmed refresh does
-- not re-gate combat while Flash is temporarily on recast.
local flash_retry=setup(make_harness())
local retry_add=flash_retry:add(add(405,'Bozzetto Tormentor'))
for _,at in ipairs({6.0,7.1,8.2,9.3}) do flash_retry:tick(at) end
assert(flash_retry:count('controller',{semantic='flash-add'})==4)
flash_retry:tick(17.4)
assert(flash_retry:count('controller',{semantic='flash-add'})==5,
    'add Flash did not start a fresh bounded retry cycle')
flash_retry:perform(action(4,'Tackleberry',SPELL.Flash,retry_add.id),17.5)
local forced_before_refresh=flash_retry:count('force',{id=retry_add.id})
flash_retry:tick(35.6)
assert(flash_retry:count('force',{id=retry_add.id})>forced_before_refresh,
    'periodic Flash refresh incorrectly re-gated a proven add handoff')
for _,at in ipairs({36.7,37.8,38.9,47.0}) do flash_retry:tick(at) end
assert(flash_retry:count('controller',{semantic='flash-add'})>=10,
    'refresh collision permanently exhausted exact-add Flash')

-- Rampart and Palisade are absent from the opener and rearm independently at
-- each observed add wave after the selected add receives its Flash window.
local mitigation=setup(make_harness())
local first_pack=mitigation:add(add(406,'Bozzetto Tormentor'))
mitigation:tick(6.0)
mitigation:perform(action(4,'Tackleberry',SPELL.Flash,first_pack.id),6.1)
mitigation:tick(7.6)
assert(mitigation:count('controller',{semantic='rampart'})==1)
mitigation:perform(action(6,'Tackleberry',JA.Rampart,IDS.Tackleberry),7.7)
mitigation:tick(8.0)
assert(mitigation:count('controller',{semantic='palisade'})==1)
mitigation:remove(first_pack)
mitigation:tick(8.3) mitigation:tick(10.4)
mitigation.boss.hpp=30 mitigation:tick(10.7)
local second_pack=mitigation:add(add(407,'Bozzetto Tormentor'))
mitigation:tick(11.0)
mitigation:perform(action(4,'Tackleberry',SPELL.Flash,second_pack.id),11.1)
mitigation:tick(12.6)
assert(mitigation:count('controller',{semantic='rampart'})==2,
    'wave-two mitigation was not rearmed')

-- Silence retries in finite cycles and renews after a conservative duration.
local silence_cycles=setup(make_harness())
local silence_astro=silence_cycles:add(add(408,'Bozzetto Astrologer'))
for _,at in ipairs({6.0,8.1,10.2}) do silence_cycles:tick(at) end
assert(silence_cycles:count('controller',{semantic='silence-add'})==3)
silence_cycles:tick(18.3)
assert(silence_cycles:count('controller',{semantic='silence-add'})==4,
    'failed Astrologer Silence cycle never rearmed')
silence_cycles:perform(action(4,'Smalls',SPELL.Silence,silence_astro.id),18.4)
local silenced_count=silence_cycles:count('controller',{semantic='silence-add'})
silence_cycles:tick(93.5)
assert(silence_cycles:count('controller',{semantic='silence-add'})>silenced_count,
    'confirmed Astrologer Silence was not conservatively renewed')

local two_astrologers=setup(make_harness())
local astro_one=two_astrologers:add(add(418,'Bozzetto Astrologer'))
local astro_two=two_astrologers:add(add(419,'Bozzetto Astrologer'))
two_astrologers:tick(6.0)
two_astrologers:tick(6.3)
assert(two_astrologers:count('controller',
    {semantic='silence-add',subject=astro_one.id})==1)
assert(two_astrologers:count('controller',
    {semantic='silence-add',subject=astro_two.id})==1,
    'second live Astrologer was starved behind the first Silence backoff')
two_astrologers:perform(
    action(4,astro_one.id,SPELL.IceSpikes,astro_one.id),6.4)
two_astrologers:perform(
    action(4,astro_two.id,SPELL.IceSpikes,astro_two.id),6.5)
two_astrologers:tick(6.8)
two_astrologers:tick(7.1)
assert(two_astrologers:count('controller',
    {semantic='dispel-ice-spikes',subject=astro_one.id})==1)
assert(two_astrologers:count('controller',
    {semantic='dispel-ice-spikes',subject=astro_two.id})==1,
    'second Ice Spikes response was starved behind the first backoff')

-- A successful exact Astrologer Ice Spikes cast preempts the current chain,
-- queues exact-subject Dispel, and resumes only after the strip is confirmed.
local spikes=setup(make_harness())
spikes.tp={Dolomedes=1200,Tackleberry=1200,Kickpuncher=1200}
local spike_astro=spikes:add(add(409,'Bozzetto Astrologer'))
spikes:tick(6.0)
spikes:perform(action(4,'Tackleberry',SPELL.Flash,spike_astro.id),6.05)
spikes:perform(action(4,spike_astro.id,SPELL.IceSpikes,spike_astro.id),6.1)
spikes:tick(6.3)
local dispel=assert(spikes:last('controller',{semantic='dispel-ice-spikes'}))
assert(dispel.recipient=='Smalls' and dispel.subject==spike_astro.id)
assert(spikes:count('controller',{semantic='lead'})==0)
spikes:perform(action(4,'Smalls',SPELL.Dispel,spike_astro.id),6.4)
spikes:tick(7.2)
assert(spikes:count('controller',{semantic='lead'})==1)
local foreign_spikes=spikes:add(add(399,'Bozzetto Astrologer',{claim_id=999}))
spikes:perform(action(4,foreign_spikes.id,SPELL.IceSpikes,foreign_spikes.id),7.3)
assert(spikes.runtime.add_dispel[tostring(foreign_spikes.id)..':'
    ..tostring(foreign_spikes.index)]==nil)

-- Chain ordering is packet-driven and subject-bound. Last Stand cannot occur
-- unless Savage Blade positively proves Fragmentation message 291.
local chain=setup(make_harness())
chain.tp={Dolomedes=1200,Tackleberry=1200,Kickpuncher=1200}
chain:tick(6.6)
local lead=assert(chain:last('controller',{semantic='lead'}))
assert(lead.recipient=='Kickpuncher' and lead.subject==chain.boss.id)
chain:perform(action(3,'Kickpuncher',WS.Evisceration,chain.boss.id,
    result(500)),6.7)
chain:tick(9.7)
assert(chain:count('controller',{semantic='middle'}) == 0)
chain:tick(9.95)
assert(chain:count('controller',{semantic='middle'}) == 1)
chain:perform(action(3,'Tackleberry',WS.SavageBlade,chain.boss.id,
    result(500,nil,290,200)),10.0)
assert(chain:count('controller',{semantic='close'}) == 0)
chain:tick(11.2)
chain:perform(action(3,'Kickpuncher',WS.Evisceration,chain.boss.id,
    result(500)),11.3)
chain:tick(14.45)
chain:perform(action(3,'Tackleberry',WS.SavageBlade,chain.boss.id,
    result(500,nil,291,200)),14.5)
chain:tick(17.65)
local close=assert(chain:last('controller',{semantic='close'}))
assert(close.recipient=='Dolomedes' and close.subject==chain.boss.id)
chain:perform(action(3,'Dolomedes',WS.LastStand,chain.boss.id,
    result(600,nil,288,300)),17.7)
assert(chain.runtime.chain_stage=='idle')

-- Threshold hysteresis suppresses a boss chain before each add spawn. The
-- first wave cannot be skipped; an emptied wave remains held for two seconds.
local phase=setup(make_harness())
phase.tp={Dolomedes=1200,Tackleberry=1200,Kickpuncher=1200}
phase.boss.hpp=84
phase:tick(6)
assert(phase:count('controller',{semantic='lead'}) == 0)
phase.boss.hpp=80
phase:tick(6.3)
assert(phase.runtime.threshold_wait==1 and phase:last('stop'))
local phase_add=phase:add(add(410,'Bozzetto Tormentor'))
phase:tick(6.6)
assert(phase.runtime.wave1_seen)
phase:remove(phase_add)
phase:tick(7.0)
assert(not phase.runtime.wave1_done)
phase:tick(9.1)
assert(phase.runtime.wave1_done)
phase.boss.hpp=30
phase:tick(9.4)
assert(phase.runtime.threshold_wait==2)

-- Perfect Dodge cancels and holds all physical target control for 32 seconds.
local dodge=setup(make_harness())
local before=dodge:count('force')
dodge:perform(monster_ready(dodge.boss.id,MOVE.PerfectDodge),6)
assert(dodge.runtime.perfect_dodge_until==38)
dodge:tick(20)
assert(dodge:count('force')==before)
dodge:tick(38.1)
assert(dodge:count('force')>before)

-- Utsusemi: San queues an exact boss Diaga only after adds are gone; ordinary
-- boss Silence is finite. Astrologer Silence never targets a same-name foreign.
local magic=setup(make_harness())
magic.boss.hpp=29
magic.runtime.wave1_seen=true magic.runtime.wave1_done=true
magic.runtime.wave2_seen=true magic.runtime.wave2_done=true
magic.tp={Dolomedes=1200,Tackleberry=1200,Kickpuncher=1200}
magic.tp.Barneystinson=0 magic.tp.Smalls=0 magic.tp.Achoo=0
magic:perform(action(4,magic.boss.id,SPELL.UtsusemiSan,magic.boss.id),6)
for _,at in ipairs({6.3,7.9,9.5,15.6}) do magic:tick(at) end
assert(magic:last('controller',{semantic='diaga'}).subject==magic.boss.id)
assert(magic:count('controller',{semantic='diaga'})==4,
    'failed Diaga cycle permanently exhausted')
assert(magic:count('controller',{semantic='lead'})==0,
    'known boss shadows allowed a coordinated weapon skill')
magic:perform(action(4,'Smalls',SPELL.Diaga,magic.boss.id),15.7)
for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
    magic.members[name].hpp=20
    magic:perform(action(4,name,SPELL.UtsusemiNi,IDS[name]),15.8)
end
assert(magic.runtime.lowhp_phase==true)
assert(magic.runtime.shadow_confirmed.Dolomedes
    and magic.runtime.shadow_confirmed.Tackleberry
    and magic.runtime.shadow_confirmed.Kickpuncher)
magic:tick(16.8)
assert(magic:count('controller',{semantic='lead'})==1,
    'confirmed Diaga did not release the boss weaponskill hold: '
        ..tostring(magic:count('controller',{semantic='lead'}))
        ..' stage='..tostring(magic.runtime.chain_stage)
        ..' subject='..tostring(magic.runtime.subject_id)
        ..' boss_shadows='..tostring(magic.runtime.boss_shadows))
for i=1,10 do magic:tick(17+i*.7) end
assert(magic:count('controller',{semantic='silence-boss'}) <= 3)

local function arm_final_phase(h, boss_hpp)
    h.runtime.wave1_seen=true h.runtime.wave1_done=true
    h.runtime.wave2_seen=true h.runtime.wave2_done=true
    h.boss.hpp=boss_hpp or 29
    for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
        h.tp[name]=1200
    end
end

local function set_attacker_hpp(h, hpp)
    for _,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
        h.members[name].hpp=hpp
    end
end

local function prove_attacker_shadows(h, at)
    for index,name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
        h:perform(action(4,name,SPELL.UtsusemiNi,IDS[name]),
            at+index*.01)
    end
end

-- VD's finish is a latched profile-local controller. It waits for wave two,
-- suppresses final-phase WS until all attackers are 13-25% with shadows, and
-- remains active if Spin the Tables heals Bigwig back above 30%.
local lowhp=setup(make_harness())
arm_final_phase(lowhp,31)
lowhp:tick(6.0)
assert(lowhp.runtime.lowhp_phase==false)
lowhp.boss.hpp=29
lowhp:tick(6.3)
assert(lowhp.runtime.lowhp_phase==true)
assert(lowhp:count('controller',{semantic='lowhp-on'})==6)
assert(lowhp:count('controller',{semantic='lead'})==0,
    'high-HP attackers leaked a final-phase WS')
set_attacker_hpp(lowhp,20)
lowhp:tick(6.6)
assert(lowhp:count('controller',{semantic='lead'})==0,
    'unconfirmed remote shadows leaked a final-phase WS')
prove_attacker_shadows(lowhp,6.7)
lowhp:tick(7.8)
assert(lowhp:count('controller',{semantic='lead'})==1)
lowhp.boss.hpp=45
lowhp:tick(8.1)
assert(lowhp.runtime.lowhp_phase==true,
    'Bigwig healing above 30% incorrectly cleared the low-HP latch')

-- Unsafe or unobservable backline geometry stops PartyCombat and all WS.
-- Smalls must be outside Spin's 15-yalm AoE yet within 20 yalms of each
-- attacker so the exact Cure II rescue remains reachable.
local geometry=setup(make_harness())
arm_final_phase(geometry)
set_attacker_hpp(geometry,20)
prove_attacker_shadows(geometry,5.7)
geometry.members.Barneystinson.x=15
geometry:tick(6.0)
assert(geometry:count('controller',{semantic='lead'})==0)
assert(geometry:last('alert').message:find('beyond 16 yalms',1,true))
geometry.members.Barneystinson.x=18
geometry.members.Smalls.x=nil
geometry:tick(6.3)
assert(geometry:count('controller',{semantic='lead'})==0)
geometry.members.Smalls.x=22
geometry:tick(6.6)
assert(geometry:count('controller',{semantic='lead'})==0)
assert(geometry:last('alert').message:find('within 20 yalms',1,true))
geometry.members.Smalls.x=18
geometry:tick(6.9) geometry:tick(8.0)
assert(geometry:count('controller',{semantic='lead'})==1,
    'safe observable support geometry did not release offense')

-- Crossing below 13% preempts target control before the exact Cure II is
-- queued, so a subsequent broad cancel cannot erase the rescue. Requests are
-- finite per cycle and rearm after backoff; support receives exact Cure IV.
local rescue=setup(make_harness())
arm_final_phase(rescue)
set_attacker_hpp(rescue,20)
rescue.members.Dolomedes.hpp=12
prove_attacker_shadows(rescue,5.7)
rescue:perform(action(4,rescue.boss.id,SPELL.UtsusemiSan,
    rescue.boss.id),5.8)
rescue:tick(6.0)
local cure=assert(rescue:last('controller',{semantic='lowhp-cure'}))
assert(cure.recipient=='Smalls' and cure.subject==IDS.Dolomedes)
assert(rescue:last('controller').semantic=='lowhp-cure',
    'low-HP rescue was cancelled after it was queued')
assert(rescue:count('controller',{semantic='diaga'})==0,
    'routine boss magic starved the critical low-HP rescue lane')
for _,at in ipairs({7.6,9.2,10.8}) do rescue:tick(at) end
assert(rescue:count('controller',{semantic='lowhp-cure'})==3)
rescue:tick(16.9)
assert(rescue:count('controller',{semantic='lowhp-cure'})==4,
    'bounded low-HP Cure II cycle never rearmed')
rescue:perform(action(4,'Smalls',SPELL.CureII,IDS.Dolomedes),17.0)
rescue.members.Dolomedes.hpp=20
rescue:tick(17.3)

local support_rescue=setup(make_harness())
arm_final_phase(support_rescue)
set_attacker_hpp(support_rescue,20)
prove_attacker_shadows(support_rescue,5.7)
support_rescue.members.Barneystinson.hpp=55
support_rescue:tick(6.0)
local support_cure=assert(support_rescue:last('controller',
    {semantic='support-cure'}))
assert(support_cure.recipient=='Smalls'
    and support_cure.subject==IDS.Barneystinson)
assert(support_rescue:count('controller',{semantic='lead'})==0)

-- Mew is restricted to live add packs. The final low-HP phase evacuates both
-- pet owners with the backline instead of requiring one inside Spin range.
local final_mew=setup(make_harness())
arm_final_phase(final_mew)
set_attacker_hpp(final_mew,20)
prove_attacker_shadows(final_mew,5.7)
local mew_before=final_mew:count('controller',{semantic='mew'})
final_mew:tick(6.0) final_mew:tick(7.0)
assert(final_mew:count('controller',{semantic='mew'})==mew_before)

-- Any-party death uses the global shutdown path and explicitly removes the
-- low-HP guards from all six clients before releasing encounter authority.
local lowhp_death=setup(make_harness())
arm_final_phase(lowhp_death)
lowhp_death:tick(6.0)
lowhp_death.party_hpp=0
lowhp_death:tick(6.3)
assert(lowhp_death:count('controller',{semantic='lowhp-off'})==6)
assert(lowhp_death:count('release',{id=lowhp_death.boss.id})==1)

-- A Mew success must cover Bigwig and every currently live associated add.
-- Partial coverage keeps the same lane pending; no result triggers bounded
-- cancellation/failover, and only a full pet packet advances the 31s baton.
-- Alternating independent BRD/SMN and RDM/SMN lanes keeps each actor's own
-- Blood Pact: Ward cadence above the unmodified 60-second recast.
local mew=setup(make_harness())
local ma=mew:add(add(420,'Bozzetto Astrologer'))
local mt=mew:add(add(421,'Bozzetto Tormentor'))
local pet=mew:add({id=700,index=700,name='Cait Sith',owner_id=IDS.Barneystinson})
mew:tick(6.3)
assert(mew.runtime.mew_pending.member=='Barneystinson')
mew:perform(multi_action(11,pet.id,MOVE.Mewing,{
    {id=mew.boss.id},{id=ma.id},
}),6.4)
assert(mew.runtime.mew_pending,
    'partial-target Mew incorrectly advanced the baton')
mew:perform(multi_action(11,pet.id,MOVE.Mewing,{
    {id=mew.boss.id},{id=ma.id},{id=mt.id},
}),6.5)
assert(mew.runtime.mew_pending==nil and mew.runtime.mew_lane==2)
assert(mew.runtime.next_mew_at==37.5)
assert(mew.runtime.retreat_pending.member=='Barneystinson')
mew:tick(6.8)
local first_retreat=assert(mew:last('controller',{semantic='retreat'}))
assert(first_retreat.recipient=='Barneystinson')
mew:perform(action(6,'Smalls',JA.Retreat,IDS.Smalls),6.9)
assert(mew.runtime.retreat_pending.member=='Barneystinson',
    'the other Cait lane falsely confirmed Retreat')
mew:perform(action(6,'Barneystinson',JA.Retreat,IDS.Barneystinson,
    result(1,4)),7.0)
assert(mew.runtime.retreat_pending.member=='Barneystinson',
    'a failed Retreat result completed cleanup')
mew:perform(action(6,'Barneystinson',JA.Retreat,IDS.Barneystinson),7.1)
assert(mew.runtime.retreat_pending==nil)
mew:tick(37.4)
assert(mew.runtime.mew_pending==nil,
    'Mew baton fired before the guarded 31-second interval')
mew:tick(37.6)
assert(mew.runtime.mew_pending.member=='Smalls')
local rdm_pet=mew:add({id=701,index=701,name='Cait Sith',owner_id=IDS.Smalls})
mew:perform(multi_action(11,rdm_pet.id,MOVE.Mewing,{
    {id=mew.boss.id},{id=ma.id},{id=mt.id},
}),37.7)
assert(mew.runtime.mew_pending==nil and mew.runtime.mew_lane==1)
assert(mew.runtime.next_mew_at==68.7)
mew:tick(38.0)
local second_retreat=assert(mew:last('controller',{semantic='retreat'}))
assert(second_retreat.recipient=='Smalls')
mew:perform(action(6,'Smalls',JA.Retreat,IDS.Smalls),38.1)
assert(mew.runtime.retreat_pending==nil)
mew:tick(68.6)
assert(mew.runtime.mew_pending==nil)
mew:tick(68.8)
assert(mew.runtime.mew_pending.member=='Barneystinson',
    'same Cait lane was reused before more than 60 seconds elapsed')

local failover=setup(make_harness())
failover:add(add(430,'Bozzetto Astrologer'))
failover:add(add(431,'Bozzetto Tormentor'))
failover:tick(6.3)
assert(failover.runtime.mew_pending.member=='Barneystinson')
failover:tick(16.4)
assert(failover:last('controller',{recipient='Barneystinson',semantic='cancel'}))
failover:tick(16.7)
assert(failover.runtime.mew_pending.member=='Smalls')

-- Retreat is best-effort cleanup rather than a combat phase. Even when its
-- result never arrives, the selected add is forced and its skillchain begins;
-- the bounded follow-up then expires without cancelling target authority.
local retreat_timeout=setup(make_harness())
for _, name in ipairs({'Dolomedes','Tackleberry','Kickpuncher'}) do
    retreat_timeout.tp[name]=1200
end
local retreat_astro=retreat_timeout:add(add(432,'Bozzetto Astrologer'))
local retreat_tormentor=retreat_timeout:add(add(433,'Bozzetto Tormentor'))
local timeout_pet=retreat_timeout:add(
    {id=702,index=702,name='Cait Sith',owner_id=IDS.Barneystinson})
retreat_timeout:tick(6.3)
retreat_timeout:perform(multi_action(11,timeout_pet.id,MOVE.Mewing,{
    {id=retreat_timeout.boss.id},{id=retreat_astro.id},
    {id=retreat_tormentor.id},
}),6.4)
retreat_timeout:tick(6.7)
assert(retreat_timeout.runtime.retreat_pending)
retreat_timeout:perform(action(4,'Tackleberry',SPELL.Flash,
    retreat_astro.id),6.8)
retreat_timeout:tick(7.4)
assert(retreat_timeout:last('force',{id=retreat_astro.id}))
local retreat_lead=retreat_timeout:last('controller',{semantic='lead'})
assert(retreat_lead and retreat_lead.subject==retreat_astro.id,
    'unconfirmed Retreat held the add chain; stage='
        ..tostring(retreat_timeout.runtime.chain_stage))
retreat_timeout:tick(12.5)
assert(retreat_timeout.runtime.retreat_pending==nil)
assert(retreat_timeout.runtime.subject_id==retreat_astro.id)

-- Reused add IDs with a new index create a new subject transaction; profile
-- deactivation cancels authority and restores the client preference.
local reuse=setup(make_harness())
local first=reuse:add(add(440,'Bozzetto Astrologer',{index=1440}))
reuse:tick(6)
assert(reuse.runtime.subject_index==1440)
reuse:remove(first)
local second=reuse:add(add(440,'Bozzetto Astrologer',{index=2440}))
reuse:tick(6.3)
assert(reuse.runtime.subject_index==2440)
reuse.runtime:on_deactivate(reuse.context)
assert(reuse:last('release',{id=reuse.boss.id}))
assert(reuse:last('autotarget').value==true)

print('PartyTactics September Qutrub runtime tests passed.')
