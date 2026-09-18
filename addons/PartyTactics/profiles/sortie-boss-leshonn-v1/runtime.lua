-- Exact-target tank-first pull orchestration for Leshonn.
--
-- Dolo's target selection is only a route cue. Tackle receives the first
-- directed engagement; the other five damage lanes release on Tackle's first
-- hostile action or party claim. A short fallback prevents pathing/recast
-- trouble from deadlocking a timed run. No manual input is filtered.

local M = {}

local DOLO='Dolomedes'
local TACKLE='Tackleberry'
local ALLOWED_ZONES={[133]=true,[189]=true,[275]=true}
local PULL_MEMBER={TACKLE}
local DAMAGE_MEMBERS={
    DOLO,'Kickpuncher','Barneystinson','Smalls','Achoo',
}
local ALL_MEMBERS={
    DOLO,TACKLE,'Kickpuncher','Barneystinson','Smalls','Achoo',
}

local TARGET_NAME='Leshonn'
local POLL_INTERVAL=0.10
local FORCE_INTERVAL=0.65
local FORCE_ATTEMPTS=3
local PULL_FALLBACK_SECONDS=2.0
local CLAIM_GAP_GRACE=2.0
local BIND_RETRY_INTERVAL=4.0

local function exact_boss(mob)
    return type(mob)=='table'
        and mob.name==TARGET_NAME
        and tonumber(mob.spawn_type)==16
        and type(mob.id)=='number'
        and mob.id>=1 and mob.id<=4294967295
        and mob.id==math.floor(mob.id)
        and type(mob.index)=='number'
        and mob.index>=0 and mob.index<=65535
        and mob.index==math.floor(mob.index)
end

local function live_boss(mob)
    return exact_boss(mob) and mob.valid_target==true
        and (tonumber(mob.hpp) or 0)>0
end

local function candidate(ctx)
    local mob=type(ctx.recent_target)=='function'
        and ctx.recent_target(15) or nil
    if not live_boss(mob) then mob=ctx.current_target() end
    if not live_boss(mob) then return nil end
    local claim=tonumber(mob.claim_id) or 0
    if claim~=0 and ctx.party_claimed(mob)~=true then return nil end
    return mob
end

local function actor_name(ctx,action)
    local actor=type(action)=='table'
        and ctx.mob_by_id(action.actor_id) or nil
    return actor and actor.name or nil
end

local function action_targets(action,target_id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(target_id) then return true end
    end
    return false
end

local function tackle_pull_action(ctx,action,target_id)
    if actor_name(ctx,action)~=TACKLE
        or not action_targets(action,target_id)
    then return false end
    local category=tonumber(action.category)
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
    self.next_bind_attempt=0
end

local function release_damage(self,ctx,reason)
    if self.damage_released or not self.encounter_id then return end
    self.damage_released=true
    ctx.actions.combat_force_members(self.encounter_id,DAMAGE_MEMBERS)
    alert(ctx,('LESHONN TANK PULL %s: Tackle took the first lane; all five damage lanes released.'):format(reason),false)
end

local function retire(self,ctx,reason,keep_armed)
    local id=self.encounter_id
    if not id then return end
    ctx.actions.combat_stop_members(ALL_MEMBERS)
    ctx.release_encounter(id,keep_armed==true)
    clear(self)
    if reason=='claim lost' then
        alert(ctx,'LESHONN target authority released after claim loss; manual play remains available.',false)
    end
end

local function bind(self,ctx,mob,now)
    clear(self)
    if ctx.authorize_encounter(mob.id)~=true then
        self.next_bind_attempt=now+BIND_RETRY_INTERVAL
        alert(ctx,'LESHONN tank-first pull could not bind; manual combat remains available and automation will retry.',true)
        return false
    end
    ctx.actions.combat_stop_members(ALL_MEMBERS)
    self.encounter_id=mob.id
    self.encounter_index=mob.index
    self.last_seen=now
    self.claim_seen=ctx.party_claimed(mob)==true
    self.pull_started_at=now
    self.next_force=now
    alert(ctx,'LESHONN BOUND: Tackle is being sent first; damage releases on his opening threat action.',false)
    return true
end

local function resolved(self,ctx,now)
    local mob=ctx.mob_by_id(self.encounter_id)
    if exact_boss(mob) and mob.id==self.encounter_id
        and mob.index==self.encounter_index
    then
        if not live_boss(mob) then
            retire(self,ctx,'target ended',true)
            return nil
        end
        local claim=tonumber(mob.claim_id) or 0
        if ctx.party_claimed(mob)==true then
            self.claim_seen=true
            self.last_seen=now
            return mob
        end
        if claim==0 and not self.claim_seen then
            self.last_seen=now
            return mob
        end
        if claim==0 and now-(self.last_seen or now)<=CLAIM_GAP_GRACE then
            return mob
        end
    end
    if now-(self.last_seen or now)>CLAIM_GAP_GRACE then
        retire(self,ctx,'claim lost',true)
    end
    return nil
end

function M.create()
    local self={active=false,next_poll=0}
    clear(self)

    function self:on_activate(ctx)
        self.active=true
        self.next_poll=0
        clear(self)
    end

    function self:on_deactivate(ctx)
        if ctx.player_name()==DOLO and self.encounter_id then
            retire(self,ctx,'deactivated',false)
        else
            clear(self)
        end
        self.active=false
    end

    function self:on_action(ctx,action)
        if not self.active or ctx.player_name()~=DOLO
            or ALLOWED_ZONES[ctx.zone_id()]~=true
            or ctx.operator_armed()~=true or not self.encounter_id
        then return end
        if tackle_pull_action(ctx,action,self.encounter_id) then
            self.claim_seen=true
            self.last_seen=ctx.now()
            release_damage(self,ctx,'CONFIRMED')
        end
    end

    function self:on_tick(ctx,now)
        if not self.active or ctx.player_name()~=DOLO
            or now<self.next_poll then return end
        self.next_poll=now+POLL_INTERVAL

        if ALLOWED_ZONES[ctx.zone_id()]~=true
            or ctx.operator_armed()~=true
        then
            if self.encounter_id then
                retire(self,ctx,'operator disarmed',false)
            end
            return
        end

        local mob
        if self.encounter_id then
            mob=resolved(self,ctx,now)
            if not self.encounter_id then return end
        else
            mob=candidate(ctx)
            if not mob or now<(self.next_bind_attempt or 0)
                or not bind(self,ctx,mob,now)
            then return end
        end
        if not mob or ctx.encounter_ready(self.encounter_id)~=true then return end

        if not self.damage_released then
            if ctx.party_claimed(mob)==true then
                release_damage(self,ctx,'CONFIRMED')
            elseif self.force_attempts<FORCE_ATTEMPTS
                and now>=(self.next_force or 0)
            then
                ctx.actions.combat_force_members(
                    self.encounter_id,PULL_MEMBER)
                self.force_attempts=self.force_attempts+1
                self.next_force=now+FORCE_INTERVAL
            end
            if not self.damage_released
                and now-(self.pull_started_at or now)
                    >=PULL_FALLBACK_SECONDS
            then
                release_damage(self,ctx,'FALLBACK')
                alert(ctx,'LESHONN TANK PULL FALLBACK: Tackle was directed first but no claim packet arrived within two seconds. Damage released so the timed route cannot deadlock.',true)
            end
        end
    end

    return self
end

return M
