-- Persistent Sortie encounter router.
--
-- This runtime never loads, reapplies, arms, disarms, or stops a PartyTactics
-- profile. One active profile owns the whole run; exact hostile actions select
-- only an internal combat recipe. Manual game input is never filtered.

local M = {}

local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'

local PARTY = {DOLO,TACKLE,KICK,BARNEY,SMALLS,ACHOO}
local PARTY_SET = {
    [DOLO]=true,[TACKLE]=true,[KICK]=true,
    [BARNEY]=true,[SMALLS]=true,[ACHOO]=true,
}
local ALLOWED_ZONES = {[133]=true,[189]=true,[275]=true}
local HOSTILE_CATEGORIES = {[1]=true,[2]=true,[3]=true,[4]=true,[6]=true}

local CACH = {
    ['Cachaemic Skeleton']=true,['Cachaemic Ghoul']=true,
}

local WS_EVIS = 25
local WS_RED_LOTUS = 34
local WS_FLAT = 35
local WS_SAVAGE = 42
local WS_BLACK_HALO = 169
local SPELL_FIRE_III = 146
local SPELL_FIRE_IV = 147
local SPELL_THUNDER = 164
local FRAGMENTATION_MESSAGE = 291
local LIQUEFACTION_MESSAGE = 295
local MAGIC_BURST_MESSAGES = {[252]=true,[265]=true}

local POLL_INTERVAL = 0.20
local CLAIM_GRACE = 2.0
local ACTION_TIMEOUT = 7.0
local CHAIN_DELAY = 3.1
local REQUEST_INTERVAL = 1.25
local ACUEX_CHAIN_HPP = 70
local ACUEX_HOLD_HPP = 45
local ACUEX_DIRECT_MAGIC_HPP = 30

local FAILURE_MESSAGES = {
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

local BURN_ACTIONS = {
    {name=DOLO,semantic='savage-blade'},
    {name=TACKLE,semantic='savage-blade'},
    {name=KICK,semantic='evisceration'},
    {name=BARNEY,semantic='savage-blade'},
    {name=SMALLS,semantic='black-halo'},
    {name=ACHOO,semantic='black-halo'},
}

-- Do not let an opportunistic WS close Wind/Lightning-aligned Fragmentation
-- on Leshonn. Kick continues to melee and Box Step, but holds automatic WS.
local LESHONN_ACTIONS = {
    {name=DOLO,semantic='savage-blade'},
    {name=TACKLE,semantic='savage-blade'},
    {name=BARNEY,semantic='savage-blade'},
    {name=SMALLS,semantic='black-halo'},
    {name=ACHOO,semantic='black-halo'},
}

local LESHONN_WIND_ABILITIES = {
    ['Chokehold']=true,
    ['Tearing Gust']=true,
}
local LESHONN_THUNDER_ABILITIES = {
    ['Zap']=true,
    ['Concussive Shock']=true,
}
local LESHONN_TRANSITION_ABILITIES = {
    ['Shrieking Gale']=true,
    ['Undulating Shockwave']=true,
}

local ACUEX_BUILDERS = {DOLO,KICK,BARNEY,ACHOO}
local ACUEX_CHAINERS = {TACKLE,SMALLS}

local function exact_enemy(mob)
    return type(mob)=='table' and tonumber(mob.spawn_type)==16
        and type(mob.id)=='number' and mob.id>=1
        and mob.id<=4294967295 and mob.id==math.floor(mob.id)
        and type(mob.index)=='number' and mob.index>=0
        and mob.index<=65535 and mob.index==math.floor(mob.index)
end

local function live_enemy(mob)
    return exact_enemy(mob) and mob.valid_target==true
        and (tonumber(mob.hpp) or 0)>0
end

local function actor_name(ctx,action)
    local actor=type(action)=='table' and ctx.mob_by_id(action.actor_id) or nil
    return actor and actor.name or nil
end

local function action_results(action,target_id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(target_id) then
            return target.actions or {}
        end
    end
    return {}
end

local function action_targets(action,target_id)
    for _,target in ipairs(type(action)=='table' and action.targets or {}) do
        if tonumber(target.id)==tonumber(target_id) then return true end
    end
    return false
end

local function successful(result)
    return type(result)=='table'
        and FAILURE_MESSAGES[tonumber(result.message)]~=true
end

local function successful_action(action,target_id)
    for _,result in ipairs(action_results(action,target_id)) do
        if successful(result) then return true end
    end
    return false
end

local function add_effect(action,target_id,message)
    for _,result in ipairs(action_results(action,target_id)) do
        if tonumber(result.add_effect_message)==message
            and (tonumber(result.add_effect_param) or 0)>0
        then return true end
    end
    return false
end

local function magic_burst(action,target_id)
    for _,result in ipairs(action_results(action,target_id)) do
        if MAGIC_BURST_MESSAGES[tonumber(result.message)]==true
            and (tonumber(result.param) or 0)>0
        then return true end
    end
    return false
end

local function classify(name)
    if CACH[name] then return 'cachaemic' end
    if name=='Abject Acuex' then return 'acuex' end
    if type(name)=='string' and name:match('^Biune ') then return 'biune' end
    if name=='Skomora' then return 'skomora' end
    if name=='Leshonn' then return 'leshonn' end
    if name=='Ghatjot' then return 'ghatjot' end
    return 'general'
end

local function hostile_target(ctx,action)
    local actor=actor_name(ctx,action)
    if not PARTY_SET[actor] or not HOSTILE_CATEGORIES[tonumber(action.category)]
    then return nil end
    for _,target in ipairs(action.targets or {}) do
        local mob=ctx.mob_by_id(tonumber(target.id))
        if live_enemy(mob) then
            local claim=tonumber(mob.claim_id) or 0
            if claim==0 or ctx.party_claimed(mob)==true then return mob,actor end
        end
    end
    return nil
end

local function reset_encounter(self)
    self.encounter_id=nil
    self.encounter_index=nil
    self.encounter_name=nil
    self.kind=nil
    self.phase=nil
    self.stage=nil
    self.deadline=0
    self.next_at=0
    self.last_seen=0
    self.claim_seen=false
    self.next_request={}
    self.builders_stopped=false
    self.chainers_stopped=false
    self.last_damage_kind=nil
    self.prepared=false
    self.combat_started=false
    self.leshonn_form='unknown'
end

local function request(self,ctx,name,semantic,now)
    local due=self.next_request[name..':'..semantic] or 0
    if now<due then return false end
    self.next_request[name..':'..semantic]=now+REQUEST_INTERVAL
    return ctx.actions.party_adapter(name,semantic,self.encounter_id)
end

local function cancel_requests(self,ctx)
    if not self.encounter_id then return end
    for _,name in ipairs(PARTY) do
        ctx.actions.party_adapter(name,'cancel',self.encounter_id)
    end
end

local function set_party_mode(self,ctx,semantic)
    if not self.encounter_id then return end
    for _,name in ipairs(PARTY) do
        ctx.actions.party_adapter(name,semantic,self.encounter_id)
    end
end

local function retire(self,ctx,keep_armed)
    local id=self.encounter_id
    if not id then return end
    cancel_requests(self,ctx)
    if keep_armed then set_party_mode(self,ctx,'movement-mode') end
    ctx.release_encounter(id,keep_armed==true)
    reset_encounter(self)
end

local function abandon(self,ctx)
    local id=self.encounter_id
    if not id then return end
    cancel_requests(self,ctx)
    set_party_mode(self,ctx,'movement-mode')
    ctx.release_encounter(id,false)
    reset_encounter(self)
end

local function configure_encounter(self,ctx,mob,now)
    reset_encounter(self)
    self.encounter_id=mob.id
    self.encounter_index=mob.index
    self.encounter_name=mob.name
    self.kind=classify(mob.name)
    self.phase=self.kind=='cachaemic' and 'c-chain'
        or self.kind=='acuex' and 'a-build'
        or self.kind=='leshonn' and 'leshonn-burn' or 'burn'
    self.stage=self.kind=='cachaemic' and 'ready' or nil
    self.last_seen=now
    self.claim_seen=ctx.party_claimed(mob)==true

    return true
end

local function begin_combat(self,ctx)
    if not self.encounter_id or self.combat_started then return false end
    self.prepared=false
    self.combat_started=true

    -- Support safety reaches every client before PartyCombat is told to
    -- synchronize the target. Leshonn keeps the no-debuff/no-Sentinel mode;
    -- every other target receives the ordinary physical package.
    set_party_mode(self,ctx,self.kind=='leshonn'
        and 'leshonn-mode' or 'combat-mode')
    if self.kind=='acuex' then
        ctx.actions.party_adapter(SMALLS,'acuex-mode',self.encounter_id)
        self.rdm_acuex=true
    elseif self.rdm_acuex then
        ctx.actions.party_adapter(SMALLS,'normal-mode',self.encounter_id)
        self.rdm_acuex=false
    end

    -- Every configured member may improvise a pull. Emit one exact-target
    -- synchronization edge for every new encounter even when Tackle or Dolo
    -- initiated it; correctness never depends on event-handler order or a
    -- separate native PartyCombat broadcast.
    ctx.actions.combat_force(self.encounter_id)
    return true
end

local function bind(self,ctx,mob,now,initiating_actor)
    if ctx.authorize_encounter(mob.id)~=true then return false end
    configure_encounter(self,ctx,mob,now)
    return begin_combat(self,ctx)
end

local function prepare_leshonn(self,ctx,mob,now)
    if mob.name~='Leshonn' or ctx.authorize_encounter(mob.id)~=true
    then return false end
    configure_encounter(self,ctx,mob,now)
    self.prepared=true
    set_party_mode(self,ctx,'leshonn-mode')
    if self.rdm_acuex then
        ctx.actions.party_adapter(SMALLS,'normal-mode',self.encounter_id)
        self.rdm_acuex=false
    end
    return true
end

local function resolve(self,ctx,now)
    local mob=ctx.mob_by_id(self.encounter_id)
    if exact_enemy(mob) and tonumber(mob.id)==self.encounter_id
        and tonumber(mob.index)==self.encounter_index
    then
        if not live_enemy(mob) then
            retire(self,ctx,true)
            return nil
        end
        local claim=tonumber(mob.claim_id) or 0
        if ctx.party_claimed(mob)==true then
            self.claim_seen=true
            self.last_seen=now
            return mob
        end
        if claim==0 and (not self.claim_seen
            or now-(self.last_seen or now)<=CLAIM_GRACE)
        then
            self.last_seen=now
            return mob
        end
    end
    if now-(self.last_seen or now)>CLAIM_GRACE then retire(self,ctx,true) end
    return nil
end

local function burn(self,ctx,now,actions)
    for _,lane in ipairs(actions or BURN_ACTIONS) do
        if (tonumber(ctx.party_tp(lane.name)) or 0)>=1000 then
            request(self,ctx,lane.name,lane.semantic,now)
        end
    end
end

local function handle_leshonn_action(self,ctx,action)
    if self.kind~='leshonn'
        or tonumber(action.actor_id)~=tonumber(self.encounter_id)
    then return false end
    local ability=type(ctx.monster_ability)=='function'
        and ctx.monster_ability(tonumber(action.param)) or nil
    local name=ability and (ability.en or ability.english or ability.name)
    if LESHONN_WIND_ABILITIES[name] then
        self.leshonn_form='wind'
        set_party_mode(self,ctx,'leshonn-wind-mode')
        return true
    elseif LESHONN_THUNDER_ABILITIES[name] then
        self.leshonn_form='thunder'
        set_party_mode(self,ctx,'leshonn-thunder-mode')
        return true
    elseif LESHONN_TRANSITION_ABILITIES[name] then
        -- References disagree on whether these moves always switch form or
        -- only do so after an opposing-element proc. Keep the universally
        -- safe support policy and return optional /DRK behavior to neutral.
        self.leshonn_form='unknown'
        set_party_mode(self,ctx,'leshonn-mode')
        return true
    end
    return false
end

local function reset_c_chain(self,now)
    self.stage='ready'
    self.deadline=0
    self.next_at=now+0.50
end

local function tick_c(self,ctx,now)
    if self.phase=='burn' then burn(self,ctx,now); return end
    if self.deadline>0 and now>=self.deadline then
        reset_c_chain(self,now)
    end
    if self.stage=='ready' and now>=self.next_at
        and (tonumber(ctx.party_tp(KICK)) or 0)>=1000
        and (tonumber(ctx.party_tp(DOLO)) or 0)>=1000
    then
        request(self,ctx,KICK,'evisceration',now)
        self.stage='await-evis'
        self.deadline=now+ACTION_TIMEOUT
    elseif self.stage=='wait-savage' and now>=self.next_at then
        request(self,ctx,DOLO,'savage-blade',now)
        self.stage='await-savage'
        self.deadline=now+ACTION_TIMEOUT
    end
end

local function stop_acuex_builders(self,ctx)
    if self.builders_stopped then return end
    self.builders_stopped=true
    ctx.actions.combat_stop_members(ACUEX_BUILDERS)
end

local function stop_acuex_chainers(self,ctx)
    if self.chainers_stopped then return end
    self.chainers_stopped=true
    ctx.actions.combat_stop_members(ACUEX_CHAINERS)
end

local function request_fire(self,ctx,now)
    request(self,ctx,SMALLS,'fire-iv',now)
    request(self,ctx,SMALLS,'fire-iii',now)
end

local function direct_magic(self,ctx,now)
    stop_acuex_builders(self,ctx)
    stop_acuex_chainers(self,ctx)
    self.phase='a-magic'
    self.stage=nil
    self.deadline=0
    request_fire(self,ctx,now)
end

local function begin_acuex_chain(self,ctx,now)
    stop_acuex_builders(self,ctx)
    request(self,ctx,TACKLE,'flat-blade',now)
    self.phase='a-chain'
    self.stage='await-flat'
    self.deadline=now+ACTION_TIMEOUT
end

local function resume_acuex_build(self,ctx,now)
    local resume={}
    if self.builders_stopped then
        for _,name in ipairs(ACUEX_BUILDERS) do resume[#resume+1]=name end
    end
    if self.chainers_stopped then
        for _,name in ipairs(ACUEX_CHAINERS) do resume[#resume+1]=name end
    end
    if #resume>0 then
        ctx.actions.combat_force_members(self.encounter_id,resume)
    end
    self.builders_stopped=false
    self.chainers_stopped=false
    self.phase='a-build'
    self.stage=nil
    self.deadline=0
    self.next_at=now+0.50
end

local function tick_acuex(self,ctx,mob,now)
    local hpp=tonumber(mob.hpp) or 100
    if self.phase=='a-magic' then request_fire(self,ctx,now); return end
    if self.phase=='a-burst' then
        request_fire(self,ctx,now)
        if now>=self.deadline then self.phase='a-magic' end
        return
    end
    if self.phase=='a-chain' then
        if self.stage=='wait-red' and now>=self.next_at then
            request(self,ctx,SMALLS,'red-lotus-blade',now)
            self.stage='await-red'
            self.deadline=now+ACTION_TIMEOUT
        elseif now>=self.deadline then
            resume_acuex_build(self,ctx,now)
        end
        return
    end

    if hpp<=ACUEX_DIRECT_MAGIC_HPP then
        direct_magic(self,ctx,now)
        return
    end
    if hpp<=ACUEX_HOLD_HPP then stop_acuex_builders(self,ctx) end
    if hpp<=ACUEX_CHAIN_HPP and now>=self.next_at
        and (tonumber(ctx.party_tp(TACKLE)) or 0)>=1000
        and (tonumber(ctx.party_tp(SMALLS)) or 0)>=1000
    then begin_acuex_chain(self,ctx,now) end
end

local function handle_c_action(self,ctx,action,actor,now)
    if self.phase~='c-chain' then return end
    local category=tonumber(action.category)
    local param=tonumber(action.param)
    if category==3 and successful_action(action,self.encounter_id) then
        if actor==KICK and param==WS_EVIS and self.stage=='await-evis' then
            self.stage='wait-savage'
            self.next_at=now+CHAIN_DELAY
            self.deadline=now+CHAIN_DELAY+ACTION_TIMEOUT
        elseif actor==DOLO and param==WS_SAVAGE
            and self.stage=='await-savage'
        then
            if add_effect(action,self.encounter_id,FRAGMENTATION_MESSAGE) then
                request(self,ctx,SMALLS,'thunder',now)
                request(self,ctx,ACHOO,'thunder',now)
                self.stage='await-burst'
                self.deadline=now+ACTION_TIMEOUT
            else
                reset_c_chain(self,now)
            end
        end
    elseif category==4 and (actor==SMALLS or actor==ACHOO)
        and param==SPELL_THUNDER and self.stage=='await-burst'
        and magic_burst(action,self.encounter_id)
    then
        self.phase='burn'
        self.stage=nil
        self.deadline=0
    end
end

local function handle_acuex_action(self,ctx,action,actor,now)
    local category=tonumber(action.category)
    local param=tonumber(action.param)
    for _,result in ipairs(action_results(action,self.encounter_id)) do
        if successful(result) and (tonumber(result.param) or 0)>0 then
            if category==4 and actor==SMALLS
                and (param==SPELL_FIRE_IV or param==SPELL_FIRE_III)
            then self.last_damage_kind='fire'
            else self.last_damage_kind='other' end
        end
    end
    if category~=3 or not successful_action(action,self.encounter_id)
    then return end
    if actor==TACKLE and param==WS_FLAT and self.phase=='a-chain'
        and self.stage=='await-flat'
    then
        self.stage='wait-red'
        self.next_at=now+CHAIN_DELAY
        self.deadline=now+CHAIN_DELAY+ACTION_TIMEOUT
    elseif actor==SMALLS and param==WS_RED_LOTUS
        and self.phase=='a-chain' and self.stage=='await-red'
    then
        if add_effect(action,self.encounter_id,LIQUEFACTION_MESSAGE) then
            stop_acuex_chainers(self,ctx)
            self.phase='a-burst'
            self.stage=nil
            self.deadline=now+ACTION_TIMEOUT
            request_fire(self,ctx,now)
        else
            resume_acuex_build(self,ctx,now)
        end
    end
end

function M.create()
    local self={active=false,next_poll=0,rdm_acuex=false}
    reset_encounter(self)

    function self:on_activate(ctx)
        self.active=true
        self.next_poll=0
        self.rdm_acuex=false
        reset_encounter(self)
    end

    function self:on_deactivate(ctx)
        -- Deactivation clears only requests owned by this exact generation.
        -- It deliberately emits no PartyCombat stop and no profile command.
        cancel_requests(self,ctx)
        reset_encounter(self)
        self.active=false
    end

    function self:on_action(ctx,action)
        if not self.active or ctx.player_name()~=DOLO
            or ALLOWED_ZONES[ctx.zone_id()]~=true
            or ctx.operator_armed()~=true or type(action)~='table'
        then return end
        local now=ctx.now()
        local target,initiating_actor=hostile_target(ctx,action)
        if self.prepared and target
            and tonumber(target.id)~=tonumber(self.encounter_id)
        then
            -- Selection is preparation, never a gate. An improvised pull on a
            -- different enemy immediately releases the staged Leshonn and
            -- binds the target the party actually chose.
            retire(self,ctx,true)
        end
        if not self.encounter_id and target then
            bind(self,ctx,target,now,initiating_actor)
        elseif self.prepared and target
            and tonumber(target.id)==tonumber(self.encounter_id)
        then
            self.claim_seen=ctx.party_claimed(target)==true
            begin_combat(self,ctx)
        end
        handle_leshonn_action(self,ctx,action)
        if not self.encounter_id
            or not action_targets(action,self.encounter_id)
        then return end
        self.last_seen=now
        local actor=actor_name(ctx,action)
        if self.kind=='cachaemic' then
            handle_c_action(self,ctx,action,actor,now)
        elseif self.kind=='acuex' then
            handle_acuex_action(self,ctx,action,actor,now)
        end
    end

    function self:on_tick(ctx,now)
        if not self.active or ctx.player_name()~=DOLO or now<self.next_poll
        then return end
        self.next_poll=now+POLL_INTERVAL
        if ALLOWED_ZONES[ctx.zone_id()]~=true then
            if self.encounter_id then retire(self,ctx,true) end
            return
        end
        if ctx.operator_armed()~=true then
            if self.encounter_id then abandon(self,ctx) end
            return
        end
        if not self.encounter_id then
            local selected=ctx.current_target()
            if live_enemy(selected) and selected.name=='Leshonn' then
                prepare_leshonn(self,ctx,selected,now)
            end
            return
        end
        local mob=resolve(self,ctx,now)
        if not mob or not self.encounter_id
            or ctx.encounter_ready(self.encounter_id)~=true
        then return end
        if self.prepared then return end
        if self.kind=='cachaemic' then tick_c(self,ctx,now)
        elseif self.kind=='acuex' then tick_acuex(self,ctx,mob,now)
        elseif self.kind=='leshonn' then burn(self,ctx,now,LESHONN_ACTIONS)
        else burn(self,ctx,now) end
    end

    return self
end

return M
