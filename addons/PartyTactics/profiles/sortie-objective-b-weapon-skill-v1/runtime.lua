-- Automatic exact-target WS finishing for Sortie B Biune elementals.
local M={}
local DOLO='Dolomedes'
local TACKLE='Tackleberry'
local ALL={DOLO,TACKLE,'Kickpuncher','Barneystinson','Smalls','Achoo'}
local ALLOWED_ZONES={[133]=true,[189]=true,[275]=true}
local TARGETS={
    ['Biune Fire Elemental']=true,['Biune Ice Elemental']=true,
    ['Biune Air Elemental']=true,['Biune Earth Elemental']=true,
    ['Biune Thunder Elemental']=true,['Biune Water Elemental']=true,
    ['Biune Light Elemental']=true,['Biune Dark Elemental']=true,
}
local WS_IDS={[23]=true,[25]=true,[42]=true,[169]=true}
local FINISHERS={
    {name=DOLO,semantic='savage-blade'},
    {name='Barneystinson',semantic='savage-blade'},
    {name='Kickpuncher',semantic='evisceration'},
    {name=TACKLE,semantic='savage-blade'},
    {name='Smalls',semantic='black-halo'},
    {name='Achoo',semantic='black-halo'},
}
local POLL=0.10
local CLAIM_GRACE=2.0
local PULL_FALLBACK=1.25
local FINISH_HPP=65
local HARD_HOLD_HPP=30
local ACTION_TIMEOUT=7
local FAILURE_MESSAGES={[4]=true,[5]=true,[16]=true,[17]=true,[18]=true,
    [29]=true,[34]=true,[40]=true,[47]=true,[48]=true,[49]=true,
    [71]=true,[72]=true,[75]=true,[76]=true,[78]=true,[84]=true,
    [85]=true,[86]=true,[87]=true,[88]=true,[89]=true,[90]=true,
    [94]=true,[106]=true,[114]=true,[128]=true,[154]=true,[155]=true,
    [156]=true,[158]=true,[188]=true,[189]=true,[190]=true,
    [191]=true,[192]=true,[193]=true,[198]=true,[217]=true,
    [219]=true,[248]=true,[283]=true,[284]=true,[313]=true,
    [316]=true,[323]=true,[325]=true,[328]=true,[355]=true,
    [422]=true,[423]=true,[649]=true,[655]=true,[656]=true,
    [659]=true,[661]=true}

local function exact(mob)
    return type(mob)=='table' and TARGETS[mob.name]==true
        and tonumber(mob.spawn_type)==16 and type(mob.id)=='number'
        and type(mob.index)=='number'
end
local function live(mob)
    return exact(mob) and mob.valid_target==true
        and (tonumber(mob.hpp) or 0)>0
end
local function candidate(ctx)
    local mob=type(ctx.recent_target)=='function' and ctx.recent_target(15) or nil
    if not live(mob) then mob=ctx.current_target() end
    if not live(mob) then return nil end
    local claim=tonumber(mob.claim_id) or 0
    if claim~=0 and ctx.party_claimed(mob)~=true then return nil end
    return mob
end
local function actor(ctx,action)
    local mob=ctx.mob_by_id(action and action.actor_id)
    return mob and mob.name or nil
end
local function target_results(action,id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(id) then return target.actions or {} end
    end
    return {}
end
local function success(result)
    return type(result)=='table' and FAILURE_MESSAGES[tonumber(result.message)]~=true
end
local function alert(ctx,message,audible)
    if type(ctx.alert)=='function' then ctx.alert(message,audible==true) end
end
local function clear(self)
    self.id=nil; self.index=nil; self.last_seen=nil; self.claim_seen=false
    self.phase='idle'; self.pull_at=0; self.next_force=0; self.force_count=0
    self.finisher=nil; self.deadline=0; self.ws_observed=false
end
local function cancel(self,ctx)
    if not self.id then return end
    for _,name in ipairs(ALL) do ctx.actions.party_adapter(name,'cancel',self.id) end
end
local function release(self,ctx,reason)
    self.phase='burn'; self.finisher=nil; self.deadline=0
    ctx.actions.combat_force_members(self.id,ALL)
    alert(ctx,'B BURN '..reason..': all six are building a fast WS finish.',false)
end
local function ready_finisher(ctx)
    for _,entry in ipairs(FINISHERS) do
        if (tonumber(ctx.party_tp(entry.name)) or 0)>=1000 then return entry end
    end
    return nil
end
local function request_finish(self,ctx,now,entry)
    cancel(self,ctx)
    ctx.actions.combat_stop_members(ALL)
    self.phase='await-ws'; self.finisher=entry; self.deadline=now+ACTION_TIMEOUT
    ctx.actions.combat_force_members(self.id,{entry.name})
    ctx.actions.party_adapter(entry.name,entry.semantic,self.id)
    alert(ctx,('B FINISH: %s is using %s; melee is held for objective credit.'):format(entry.name,entry.semantic),false)
end
local function retire(self,ctx,report,keep)
    local id=self.id; if not id then return end
    local qualified=self.ws_observed==true
    cancel(self,ctx); ctx.actions.combat_stop_members(ALL)
    ctx.release_encounter(id,keep==true); clear(self)
    if report then
        alert(ctx,qualified and 'B WS CREDIT OBSERVED: verify Shard/Metal chest credit.'
            or 'B target ended without a tracked WS; the next elemental remains automatic.',not qualified)
    end
end
local function bind(self,ctx,mob,now)
    clear(self)
    if ctx.authorize_encounter(mob.id)~=true then return false end
    ctx.actions.combat_stop_members(ALL)
    self.id=mob.id; self.index=mob.index; self.last_seen=now
    self.claim_seen=ctx.party_claimed(mob)==true
    self.phase='pull'; self.pull_at=now; self.next_force=now
    return true
end
local function resolved(self,ctx,now)
    local mob=ctx.mob_by_id(self.id)
    if exact(mob) and mob.id==self.id and mob.index==self.index then
        if not live(mob) then retire(self,ctx,true,true); return nil end
        local claim=tonumber(mob.claim_id) or 0
        if ctx.party_claimed(mob)==true then
            self.claim_seen=true; self.last_seen=now; return mob
        end
        if claim==0 and not self.claim_seen then self.last_seen=now; return mob end
        if claim==0 and now-(self.last_seen or now)<=CLAIM_GRACE then return mob end
    end
    if now-(self.last_seen or now)>CLAIM_GRACE then retire(self,ctx,false,true) end
    return nil
end

function M.create()
    local self={active=false,next_poll=0}; clear(self)
    function self:on_activate(ctx) self.active=true; clear(self) end
    function self:on_deactivate(ctx)
        if ctx.player_name()==DOLO and self.id then retire(self,ctx,false,false)
        else clear(self) end
        self.active=false
    end
    function self:on_action(ctx,action)
        if not self.active or ctx.player_name()~=DOLO
            or ALLOWED_ZONES[ctx.zone_id()]~=true
            or ctx.operator_armed()~=true or not self.id
        then return end
        local who=actor(ctx,action)
        local category=tonumber(action.category)
        local landed=false
        for _,result in ipairs(target_results(action,self.id)) do
            if success(result) and (tonumber(result.param) or 0)>0 then
                landed=true
                if category==3 and WS_IDS[tonumber(action.param)] then
                    self.ws_observed=true
                end
            end
        end
        if self.phase=='pull' and who==TACKLE and landed then
            release(self,ctx,'TACKLE CLAIM')
        elseif self.phase=='await-ws' and self.finisher
            and who==self.finisher.name and category==3 and landed
        then
            local mob=ctx.mob_by_id(self.id)
            if live(mob) then release(self,ctx,'TARGET SURVIVED WS') end
        end
    end
    function self:on_tick(ctx,now)
        if not self.active or ctx.player_name()~=DOLO or now<self.next_poll then return end
        self.next_poll=now+POLL
        if ALLOWED_ZONES[ctx.zone_id()]~=true or ctx.operator_armed()~=true then
            if self.id then retire(self,ctx,false,false) end; return
        end
        local mob=self.id and resolved(self,ctx,now) or candidate(ctx)
        if not self.id and mob then bind(self,ctx,mob,now) end
        if not mob or not self.id or ctx.encounter_ready(self.id)~=true then return end
        if self.phase=='pull' then
            if ctx.party_claimed(mob)==true then release(self,ctx,'EXISTING CLAIM')
            elseif self.force_count<3 and now>=self.next_force then
                ctx.actions.combat_force_members(self.id,{TACKLE})
                self.force_count=self.force_count+1; self.next_force=now+0.55
            elseif now-self.pull_at>=PULL_FALLBACK then release(self,ctx,'NO-GATE FALLBACK') end
        elseif self.phase=='burn' then
            local entry=ready_finisher(ctx)
            if entry and (tonumber(mob.hpp) or 100)<=FINISH_HPP then
                request_finish(self,ctx,now,entry)
            elseif (tonumber(mob.hpp) or 100)<=HARD_HOLD_HPP then
                ctx.actions.combat_stop_members(ALL)
                self.phase='hold'
            end
        elseif self.phase=='hold' then
            local entry=ready_finisher(ctx)
            if entry then request_finish(self,ctx,now,entry) end
        elseif self.phase=='await-ws' and now>=self.deadline then
            self.phase='hold'; self.finisher=nil
        end
    end
    return self
end
return M
