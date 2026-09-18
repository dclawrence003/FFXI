-- Automatic Sortie A Acuex objective: fast group TP, Liquefaction, double Fire.
-- Exact packets advance the sequence; manual input is never filtered.

local M={}
local DOLO='Dolomedes'
local TACKLE='Tackleberry'
local SMALLS='Smalls'
local ALL={DOLO,TACKLE,'Kickpuncher','Barneystinson',SMALLS,'Achoo'}
local NON_CHAIN={DOLO,'Kickpuncher','Barneystinson','Achoo'}
local CHAIN={TACKLE,SMALLS}
local ALLOWED_ZONES={[133]=true,[189]=true,[275]=true}

local WS_RED_LOTUS=34
local WS_FLAT=35
local SPELL_FIRE_III=146
local SPELL_FIRE_IV=147
local SPELL_FIRE_V=148
local FIRE_SPELLS={[SPELL_FIRE_III]='Fire III',[SPELL_FIRE_IV]='Fire IV',
    [SPELL_FIRE_V]='Fire V'}
local LIQUEFACTION_MESSAGE=295
local MAGIC_BURST_MESSAGES={[252]=true,[265]=true}

local POLL_INTERVAL=0.10
local FORCE_INTERVAL=0.55
local FORCE_ATTEMPTS=3
local PULL_FALLBACK_SECONDS=1.25
local CLAIM_GAP_GRACE=2.0
local CHAIN_DELAY=3.0
local ACTION_TIMEOUT=7.0
local BURST_TIMEOUT=11.0
local MAGIC_REQUEST_INTERVAL=2.5
local LOW_FIRE_HPP=35

local FAILURE_MESSAGES={
    [4]=true,[5]=true,[16]=true,[17]=true,[18]=true,[29]=true,
    [34]=true,[40]=true,[47]=true,[48]=true,[49]=true,[71]=true,
    [72]=true,[75]=true,[76]=true,[78]=true,[84]=true,[85]=true,
    [86]=true,[87]=true,[88]=true,[89]=true,[90]=true,[94]=true,
    [106]=true,[114]=true,[128]=true,[154]=true,[155]=true,
    [156]=true,[158]=true,[188]=true,[189]=true,[190]=true,
    [191]=true,[192]=true,[193]=true,[198]=true,[217]=true,
    [219]=true,[248]=true,[283]=true,[284]=true,[313]=true,
    [316]=true,[323]=true,[325]=true,[328]=true,[355]=true,
    [422]=true,[423]=true,[649]=true,[655]=true,[656]=true,
    [659]=true,[661]=true,
}

local function exact(mob)
    return type(mob)=='table' and mob.name=='Abject Acuex'
        and tonumber(mob.spawn_type)==16
        and type(mob.id)=='number' and mob.id>=1 and mob.id<=4294967295
        and mob.id==math.floor(mob.id)
        and type(mob.index)=='number' and mob.index>=0 and mob.index<=65535
        and mob.index==math.floor(mob.index)
end

local function live(mob)
    return exact(mob) and mob.valid_target==true
        and (tonumber(mob.hpp) or 0)>0
end

local function candidate(ctx)
    local mob=type(ctx.recent_target)=='function'
        and ctx.recent_target(15) or nil
    if not live(mob) then mob=ctx.current_target() end
    if not live(mob) then return nil end
    local claim=tonumber(mob.claim_id) or 0
    if claim~=0 and ctx.party_claimed(mob)~=true then return nil end
    return mob
end

local function actor_name(ctx,action)
    local mob=type(action)=='table' and ctx.mob_by_id(action.actor_id) or nil
    return mob and mob.name or nil
end

local function results(action,target_id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(target_id) then
            return target.actions or {}
        end
    end
    return {}
end

local function successful(result)
    return type(result)=='table'
        and FAILURE_MESSAGES[tonumber(result.message)]~=true
end

local function successful_action(action,target_id)
    for _,result in ipairs(results(action,target_id)) do
        if successful(result) then return true end
    end
    return false
end

local function has_add_effect(action,target_id,message)
    for _,result in ipairs(results(action,target_id)) do
        if tonumber(result.add_effect_message)==message
            and (tonumber(result.add_effect_param) or 0)>0
        then return true end
    end
    return false
end

local function magic_burst(action,target_id)
    for _,result in ipairs(results(action,target_id)) do
        if MAGIC_BURST_MESSAGES[tonumber(result.message)]==true
            and (tonumber(result.param) or 0)>0
        then return true end
    end
    return false
end

local function action_targets(action,target_id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(target_id) then return true end
    end
    return false
end

local function hostile_category(action)
    local category=tonumber(action and action.category)
    return category==1 or category==2 or category==3
        or category==4 or category==6
end

local function alert(ctx,message,audible)
    if type(ctx.alert)=='function' then ctx.alert(message,audible==true) end
end

local function clear(self)
    self.encounter_id=nil
    self.encounter_index=nil
    self.last_seen=nil
    self.claim_seen=false
    self.pull_started_at=nil
    self.next_force=0
    self.force_attempts=0
    self.damage_released=false
    self.phase='idle'
    self.next_at=0
    self.deadline=0
    self.next_magic=0
    self.burst_count=0
    self.last_damage_kind=nil
    self.last_damage_actor=nil
    self.last_damage_action=nil
end

local function cancel(self,ctx)
    if not self.encounter_id then return end
    for _,name in ipairs(ALL) do
        ctx.actions.party_adapter(name,'cancel',self.encounter_id)
    end
end

local function release_damage(self,ctx,reason)
    if not self.encounter_id then return end
    self.damage_released=true
    self.phase='burn'
    self.deadline=0
    ctx.actions.combat_force_members(self.encounter_id,ALL)
    alert(ctx,('A BURN %s: all six are closing and building TP; the chain takes over automatically.'):format(reason),false)
end

local function request_fire(self,ctx,now)
    if now<(self.next_magic or 0) then return end
    self.next_magic=now+MAGIC_REQUEST_INTERVAL
    ctx.actions.party_adapter(SMALLS,'fire-v',self.encounter_id)
    ctx.actions.party_adapter(SMALLS,'fire-iv',self.encounter_id)
    ctx.actions.party_adapter(SMALLS,'fire-iii',self.encounter_id)
end

local function magic_finish(self,ctx,now,reason)
    cancel(self,ctx)
    ctx.actions.combat_stop_members(ALL)
    self.phase='magic'
    self.deadline=0
    self.next_magic=0
    request_fire(self,ctx,now)
    alert(ctx,('A MAGIC HOLD: %s. Melee is stopped and Smalls will keep casting Fire automatically.'):format(reason),false)
end

local function begin_chain(self,ctx,now)
    cancel(self,ctx)
    ctx.actions.combat_stop_members(NON_CHAIN)
    ctx.actions.combat_force_members(self.encounter_id,CHAIN)
    self.phase='await-flat'
    self.deadline=now+ACTION_TIMEOUT
    ctx.actions.party_adapter(TACKLE,'flat-blade',self.encounter_id)
    alert(ctx,'A CHAIN: Flat Blade > Red Lotus Blade > Liquefaction > Fire V + Fire IV/III.',false)
end

local function retry(self,ctx,now,reason,mob)
    cancel(self,ctx)
    if (tonumber(mob and mob.hpp) or 100)<=LOW_FIRE_HPP then
        magic_finish(self,ctx,now,reason)
    else
        release_damage(self,ctx,'RETRY')
        alert(ctx,'A CHAIN RETRY: '..reason..'; TP rebuild resumed automatically.',false)
    end
end

local function begin_burst(self,ctx,now)
    ctx.actions.combat_stop_members(ALL)
    self.phase='burst'
    self.deadline=now+BURST_TIMEOUT
    self.next_magic=0
    request_fire(self,ctx,now)
    alert(ctx,'A LIQUEFACTION CONFIRMED: Smalls is bursting Fire V then Fire IV/III.',false)
end

local function retire(self,ctx,report,keep_armed)
    local id=self.encounter_id
    if not id then return end
    local magic=self.last_damage_kind=='fire'
    local actor=self.last_damage_actor
    local action=self.last_damage_action
    local bursts=self.burst_count or 0
    cancel(self,ctx)
    ctx.actions.combat_stop_members(ALL)
    ctx.release_encounter(id,keep_armed==true)
    clear(self)
    if report then
        if magic then
            alert(ctx,('A FIRE FINISH OBSERVED: %s used %s; %d Magic Burst packet(s). Verify chest credit.'):format(tostring(actor),tostring(action),bursts),false)
        else
            alert(ctx,'A TARGET ENDED WITHOUT FIRE AS THE LAST TRACKED DAMAGE. The next Acuex remains automatic.',true)
        end
    end
end

local function bind(self,ctx,mob,now)
    clear(self)
    if ctx.authorize_encounter(mob.id)~=true then return false end
    ctx.actions.combat_stop_members(ALL)
    self.encounter_id=mob.id
    self.encounter_index=mob.index
    self.last_seen=now
    self.claim_seen=ctx.party_claimed(mob)==true
    self.pull_started_at=now
    self.next_force=now
    self.phase='pull'
    alert(ctx,'A ACUEX BOUND: Tackle is preferred for first threat; an existing party claim releases everyone immediately.',false)
    return true
end

local function resolved(self,ctx,now)
    local mob=ctx.mob_by_id(self.encounter_id)
    if exact(mob) and mob.id==self.encounter_id
        and mob.index==self.encounter_index
    then
        if not live(mob) then retire(self,ctx,true,true); return nil end
        local claim=tonumber(mob.claim_id) or 0
        if ctx.party_claimed(mob)==true then
            self.claim_seen=true; self.last_seen=now; return mob
        end
        if claim==0 and not self.claim_seen then self.last_seen=now; return mob end
        if claim==0 and now-(self.last_seen or now)<=CLAIM_GAP_GRACE then
            return mob
        end
    end
    if now-(self.last_seen or now)>CLAIM_GAP_GRACE then
        retire(self,ctx,false,true)
    end
    return nil
end

function M.create()
    local self={active=false,next_poll=0}
    clear(self)

    function self:on_activate(ctx)
        self.active=true; self.next_poll=0; clear(self)
    end

    function self:on_deactivate(ctx)
        if ctx.player_name()==DOLO and self.encounter_id then
            retire(self,ctx,false,false)
        else clear(self) end
        self.active=false
    end

    function self:on_action(ctx,action)
        if not self.active or ctx.player_name()~=DOLO
            or ALLOWED_ZONES[ctx.zone_id()]~=true
            or ctx.operator_armed()~=true or type(action)~='table'
        then return end
        local now=ctx.now()
        if not self.encounter_id then
            local mob=candidate(ctx)
            if mob then bind(self,ctx,mob,now) end
        end
        if not self.encounter_id or not action_targets(action,self.encounter_id) then
            return
        end
        local actor=actor_name(ctx,action)
        if actor==TACKLE and hostile_category(action) then
            self.claim_seen=true; self.last_seen=now
            if self.phase=='pull' then release_damage(self,ctx,'TACKLE') end
        end

        local category=tonumber(action.category)
        local param=tonumber(action.param)
        if category==3 and successful_action(action,self.encounter_id) then
            if actor==TACKLE and param==WS_FLAT and self.phase=='await-flat' then
                self.phase='wait-red'
                self.next_at=now+CHAIN_DELAY
                self.deadline=now+CHAIN_DELAY+ACTION_TIMEOUT
            elseif actor==SMALLS and param==WS_RED_LOTUS
                and (self.phase=='wait-red' or self.phase=='await-red')
            then
                if has_add_effect(action,self.encounter_id,LIQUEFACTION_MESSAGE) then
                    begin_burst(self,ctx,now)
                else
                    local mob=ctx.mob_by_id(self.encounter_id)
                    retry(self,ctx,now,'Red Lotus Blade landed without Liquefaction',mob)
                end
            end
        end

        for _,result in ipairs(results(action,self.encounter_id)) do
            if successful(result) and (tonumber(result.param) or 0)>0 then
                if category==4 and actor==SMALLS and FIRE_SPELLS[param] then
                    self.last_damage_kind='fire'
                    self.last_damage_actor=actor
                    self.last_damage_action=FIRE_SPELLS[param]
                else
                    self.last_damage_kind='other'
                    self.last_damage_actor=actor
                    self.last_damage_action='physical/other'
                end
            end
        end
        if category==4 and actor==SMALLS and FIRE_SPELLS[param]
            and magic_burst(action,self.encounter_id)
        then self.burst_count=self.burst_count+1 end
    end

    function self:on_tick(ctx,now)
        if not self.active or ctx.player_name()~=DOLO or now<self.next_poll then
            return
        end
        self.next_poll=now+POLL_INTERVAL
        if ALLOWED_ZONES[ctx.zone_id()]~=true or ctx.operator_armed()~=true then
            if self.encounter_id then retire(self,ctx,false,false) end
            return
        end
        local mob
        if self.encounter_id then mob=resolved(self,ctx,now)
        else
            mob=candidate(ctx)
            if mob then bind(self,ctx,mob,now) end
        end
        if not mob or not self.encounter_id
            or ctx.encounter_ready(self.encounter_id)~=true
        then return end

        if self.phase=='pull' then
            if ctx.party_claimed(mob)==true then
                release_damage(self,ctx,'EXISTING CLAIM')
            elseif self.force_attempts<FORCE_ATTEMPTS
                and now>=(self.next_force or 0)
            then
                ctx.actions.combat_force_members(self.encounter_id,{TACKLE})
                self.force_attempts=self.force_attempts+1
                self.next_force=now+FORCE_INTERVAL
            elseif now-(self.pull_started_at or now)>=PULL_FALLBACK_SECONDS then
                release_damage(self,ctx,'NO-GATE FALLBACK')
            end
            return
        end

        if self.phase=='burn' then
            local tackle_tp=tonumber(ctx.party_tp(TACKLE)) or 0
            local smalls_tp=tonumber(ctx.party_tp(SMALLS)) or 0
            if tackle_tp>=1000 and smalls_tp>=1000 then
                begin_chain(self,ctx,now)
            elseif (tonumber(mob.hpp) or 100)<=LOW_FIRE_HPP then
                magic_finish(self,ctx,now,'target reached 35% before both chain partners had TP')
            end
        elseif self.phase=='await-flat' and now>=self.deadline then
            retry(self,ctx,now,'Flat Blade did not land',mob)
        elseif self.phase=='wait-red' and now>=self.next_at then
            self.phase='await-red'
            self.deadline=now+ACTION_TIMEOUT
            ctx.actions.party_adapter(SMALLS,'red-lotus-blade',self.encounter_id)
        elseif self.phase=='await-red' and now>=self.deadline then
            retry(self,ctx,now,'Red Lotus Blade did not land',mob)
        elseif self.phase=='burst' then
            request_fire(self,ctx,now)
            if now>=self.deadline then
                retry(self,ctx,now,'burst window ended with the target alive',mob)
            end
        elseif self.phase=='magic' then
            request_fire(self,ctx,now)
        end
    end

    return self
end

return M
