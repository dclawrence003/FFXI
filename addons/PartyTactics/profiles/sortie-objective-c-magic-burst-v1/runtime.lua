-- Exact-target, packet-confirmed Sortie C Magic Burst automation.
--
-- The runtime sequences only its own requests. It never filters operator
-- input, never treats a submitted command as success, and never turns an
-- optional setup observation into combat authorization. Each target is bound
-- from Dolo's current target and retired after one bounded encounter.

local M = {}

local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'

local ALLOWED_ZONES = {[133]=true, [189]=true, [275]=true}
local TARGET_NAMES = {
    ['Cachaemic Skeleton']=true,
    ['Cachaemic Ghoul']=true,
    ['Cachaemic Corse']=true,
    ['Cachaemic Ghost']=true,
}
local PARTY_NAMES = {
    [DOLO]=true, [TACKLE]=true, [KICK]=true,
    [BARNEY]=true, [SMALLS]=true, [ACHOO]=true,
}
local PULL_MEMBER = {TACKLE}
local CHAIN_MEMBERS = {DOLO,KICK}

local WS_Evisceration = 25
local WS_SAVAGE_BLADE = 42
local SPELL_THUNDER = 164
local FRAGMENTATION_MESSAGE = 291
local MAGIC_BURST_MESSAGES = {[252]=true, [265]=true}

local POLL_INTERVAL = 0.25
local CLAIM_GAP_GRACE = 2.0
local FORCE_ATTEMPTS = 3
local FORCE_INTERVAL = 0.65
local PULL_FALLBACK_SECONDS = 2.0
local FIRST_CHAIN_DELAY = 0.75
local CHAIN_STEP_DELAY = 3.1
local ACTION_RESULT_TIMEOUT = 7.0
local BURST_RESULT_TIMEOUT = 6.0
local FALLBACK_BURST_DELAY = 1.5
local CHAIN_RETRY_DELAY = 0.75
local FINISH_REQUEST_INTERVAL = 3.0
local WAIT_ALERT_DELAY = 20.0
local LOW_HPP_WARNING = 20
local BIND_RETRY_INTERVAL = 5.0
local RETRY_ALERT_INTERVAL = 15.0

local FAILURE_MESSAGES = {
    [4]=true, [5]=true, [16]=true, [17]=true, [18]=true, [29]=true,
    [34]=true, [40]=true, [47]=true, [48]=true, [49]=true,
    [71]=true, [72]=true, [75]=true, [76]=true, [78]=true,
    [84]=true, [85]=true, [86]=true, [87]=true, [88]=true,
    [89]=true, [90]=true, [94]=true, [106]=true, [114]=true,
    [128]=true, [154]=true, [155]=true, [156]=true, [158]=true,
    [188]=true, [189]=true, [190]=true, [191]=true, [192]=true,
    [193]=true, [198]=true, [217]=true, [219]=true, [248]=true,
    [283]=true, [284]=true, [313]=true, [316]=true, [323]=true,
    [325]=true, [328]=true, [355]=true, [422]=true, [423]=true,
    [649]=true, [655]=true, [656]=true, [659]=true, [661]=true,
}

local FINISH_ACTIONS = {
    {name=DOLO, semantic='savage-blade'},
    {name=TACKLE, semantic='savage-blade'},
    {name=KICK, semantic='evisceration'},
    {name=BARNEY, semantic='savage-blade'},
}

local function exact_normal_cachaemic(mob)
    return type(mob) == 'table'
        and TARGET_NAMES[mob.name] == true
        and tonumber(mob.spawn_type) == 16
        and type(mob.id) == 'number'
        and mob.id >= 1 and mob.id <= 4294967295
        and mob.id == math.floor(mob.id)
        and type(mob.index) == 'number'
        and mob.index >= 0 and mob.index <= 65535
        and mob.index == math.floor(mob.index)
end

local function live_normal_cachaemic(mob)
    return exact_normal_cachaemic(mob)
        and mob.valid_target == true
        and (tonumber(mob.hpp) or 0) > 0
end

local function current_candidate(ctx)
    local mob = type(ctx.recent_target) == 'function'
        and ctx.recent_target(15) or nil
    if not live_normal_cachaemic(mob) then mob = ctx.current_target() end
    if not live_normal_cachaemic(mob) then return nil end
    local claim = tonumber(mob.claim_id) or 0
    if claim ~= 0 and ctx.party_claimed(mob) ~= true then return nil end
    return mob
end

local function action_actor_name(ctx, action)
    local actor = type(action) == 'table'
        and ctx.mob_by_id(action.actor_id) or nil
    return actor and actor.name or nil
end

local function target_results(action, target_id)
    for _, target in ipairs(type(action) == 'table'
        and action.targets or {})
    do
        if tonumber(target.id) == tonumber(target_id) then
            return target.actions or {}
        end
    end
    return {}
end

local function first_target_result(action, target_id)
    return target_results(action, target_id)[1]
end

local function successful_result(result)
    if type(result) ~= 'table' then return false end
    local message = tonumber(result.message)
    return message == nil or FAILURE_MESSAGES[message] ~= true
end

local function fragmentation_on(action, target_id)
    for _, result in ipairs(target_results(action, target_id)) do
        if tonumber(result.add_effect_message) == FRAGMENTATION_MESSAGE
            and (tonumber(result.add_effect_param) or 0) > 0
        then
            return true
        end
    end
    return false
end

local function magic_burst_on(action, target_id)
    for _, result in ipairs(target_results(action, target_id)) do
        if MAGIC_BURST_MESSAGES[tonumber(result.message)] == true
            and (tonumber(result.param) or 0) > 0
        then
            return true
        end
    end
    return false
end

local function clear_encounter(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.encounter_name = nil
    self.last_seen = nil
    self.claim_seen = false
    self.started_at = nil
    self.next_force = nil
    self.force_attempts = 0
    self.pull_started_at = nil
    self.pull_confirmed = false
    self.chain_pair_released = false
    self.chain = nil
    self.next_chain = 0
    self.wait_alerted = false
    self.low_warned = false
    self.mb_confirmed = false
    self.finish_released = false
    self.next_finish = {}
    self.next_bind_attempt = 0
    self.last_retry_alert = -100000
end

local function action_targets(action, target_id)
    for _, target in ipairs(type(action) == 'table'
        and action.targets or {})
    do
        if tonumber(target.id) == tonumber(target_id) then return true end
    end
    return false
end

local function tackle_pull_action(ctx, action, target_id)
    if action_actor_name(ctx, action) ~= TACKLE
        or not action_targets(action, target_id)
    then return false end
    local category = tonumber(action.category)
    return category == 1 or category == 2 or category == 3
        or category == 4 or category == 6
end

local function alert(ctx, message, audible)
    if type(ctx.alert) == 'function' then
        ctx.alert(message, audible == true)
    end
end

local function cancel_requests(self, ctx)
    if not self.encounter_id then return end
    for _, name in ipairs({DOLO,TACKLE,KICK,BARNEY,SMALLS,ACHOO}) do
        ctx.actions.party_adapter(name, 'cancel', self.encounter_id)
    end
end

local function release_chain_pair(self, ctx, reason)
    if self.chain_pair_released or not self.encounter_id then return end
    self.pull_confirmed = true
    self.chain_pair_released = true
    ctx.actions.combat_force_members(self.encounter_id, CHAIN_MEMBERS)
    alert(ctx, ('C TANK PULL %s: Tackle established the first lane; Dolo and Kick released to build the chain.'):format(reason), false)
end

local function retire(self, ctx, reason, report)
    local id = self.encounter_id
    if not id then return end
    local confirmed = self.mb_confirmed
    cancel_requests(self, ctx)
    ctx.actions.combat_stop()
    ctx.release_encounter(id, true)
    clear_encounter(self)
    if report then
        if confirmed then
            alert(ctx, 'C BURST TARGET ENDED: Magic Burst was observed; verify the chest or temporary item.', false)
        else
            alert(ctx, 'C BURST TARGET ENDED WITHOUT AN OBSERVED MAGIC BURST. Use another Cachaemic; manual controls were never restricted.', true)
        end
    elseif reason == 'claim lost' then
        alert(ctx, 'C BURST TARGET RELEASED AFTER CLAIM LOSS; select another exact target when ready.', false)
    end
end

local function bind(self, ctx, mob, now)
    clear_encounter(self)
    if ctx.authorize_encounter(mob.id) ~= true then
        alert(ctx, 'C BURST COULD NOT BIND AUTOMATION AUTHORITY. Fight manually or disarm and re-arm; controls remain available.', true)
        self.next_bind_attempt = now + BIND_RETRY_INTERVAL
        return false
    end
    ctx.actions.combat_stop()
    self.encounter_id = mob.id
    self.encounter_index = mob.index
    self.encounter_name = mob.name
    self.last_seen = now
    self.claim_seen = ctx.party_claimed(mob) == true
    self.started_at = now
    self.pull_started_at = now
    self.pull_confirmed = self.claim_seen
    self.next_force = now
    self.next_chain = now + FIRST_CHAIN_DELAY
    alert(ctx, ('C BURST BOUND: %s. Tackle pulls first; Dolo + Kick then build 1000 TP for automatic Evisceration > Savage Blade > Thunder.'):format(mob.name), false)
    return true
end

local function resolved_target(self, ctx, now)
    local mob = ctx.mob_by_id(self.encounter_id)
    if exact_normal_cachaemic(mob)
        and mob.id == self.encounter_id
        and mob.index == self.encounter_index
    then
        if not live_normal_cachaemic(mob) then
            retire(self, ctx, 'target ended', true)
            return nil
        end
        local claim = tonumber(mob.claim_id) or 0
        if ctx.party_claimed(mob) == true then
            self.claim_seen = true
            self.last_seen = now
            return mob
        end
        if claim == 0 and not self.claim_seen then
            self.last_seen = now
            return mob
        end
        if claim == 0
            and now - (self.last_seen or now) <= CLAIM_GAP_GRACE
        then
            return mob
        end
    end
    if now - (self.last_seen or now) > CLAIM_GAP_GRACE then
        retire(self, ctx, 'claim lost', false)
    end
    return nil
end

local function reset_chain(self, now)
    self.chain = nil
    self.next_chain = now + CHAIN_RETRY_DELAY
end

local function request_ws(self, ctx, recipient, semantic, stage, now)
    ctx.actions.party_adapter(recipient, semantic, self.encounter_id)
    self.chain = {stage=stage, deadline=now + ACTION_RESULT_TIMEOUT}
end

local function request_primary_burst(self, ctx, now)
    ctx.actions.party_adapter(ACHOO, 'thunder', self.encounter_id)
    self.chain.primary_sent = true
    self.chain.fallback_at = now + FALLBACK_BURST_DELAY
end

local function begin_burst(self, ctx, now)
    self.chain = {
        stage='await-burst',
        deadline=now + BURST_RESULT_TIMEOUT,
        primary_sent=false,
        fallback_sent=false,
    }
    request_primary_burst(self, ctx, now)
    alert(ctx, 'FRAGMENTATION CONFIRMED: Achoo Thunder requested; Smalls is the bounded fallback.', false)
end

local function release_finishers(self, ctx)
    if self.finish_released or not self.encounter_id then return end
    self.finish_released = true
    self.mb_confirmed = true
    self.chain = nil
    -- Cancel an unneeded second Thunder without touching any manual cast.
    ctx.actions.party_adapter(ACHOO, 'cancel', self.encounter_id)
    ctx.actions.party_adapter(SMALLS, 'cancel', self.encounter_id)
    ctx.actions.combat_force_members(
        self.encounter_id, {TACKLE,BARNEY})
    alert(ctx, 'MAGIC BURST CONFIRMED: Tackle + Barney and all four automatic finisher lanes are released.', true)
end

local function advance_chain(self, ctx, now)
    local chain = self.chain
    if chain and now > (chain.deadline or now) then
        if now - (self.last_retry_alert or -100000)
            >= RETRY_ALERT_INTERVAL
        then
            if chain.stage == 'await-burst' then
                alert(ctx, 'MAGIC BURST NOT CONFIRMED: rebuilding the chain. Cast manually at any time; no input is blocked.', false)
            else
                alert(ctx, 'C BURST ACTION WAS NOT CONFIRMED: rebuilding the automatic chain.', false)
            end
            self.last_retry_alert = now
        end
        reset_chain(self, now)
        chain = nil
    end

    if chain then
        if chain.stage == 'send-savage' and now >= chain.next_at then
            if (tonumber(ctx.party_tp(DOLO)) or 0) >= 1000 then
                request_ws(self, ctx, DOLO, 'savage-blade',
                    'await-savage', now)
            end
        elseif chain.stage == 'await-burst'
            and not chain.fallback_sent
            and now >= (chain.fallback_at or math.huge)
        then
            ctx.actions.party_adapter(SMALLS, 'thunder', self.encounter_id)
            chain.fallback_sent = true
        end
        return
    end

    if now < (self.next_chain or 0) then return end
    local kick_tp = tonumber(ctx.party_tp(KICK)) or 0
    local dolo_tp = tonumber(ctx.party_tp(DOLO)) or 0
    if kick_tp >= 1000 and dolo_tp >= 1000 then
        request_ws(self, ctx, KICK, 'evisceration',
            'await-evisceration', now)
    elseif not self.wait_alerted
        and now - (self.started_at or now) >= WAIT_ALERT_DELAY
    then
        self.wait_alerted = true
        alert(ctx, ('C BURST WAITING FOR TP: Kick %d / Dolo %d. Manual actions remain available.'):format(kick_tp, dolo_tp), false)
    end
end

local function run_finishers(self, ctx, now)
    for _, action in ipairs(FINISH_ACTIONS) do
        if (tonumber(ctx.party_tp(action.name)) or 0) >= 1000
            and now >= (self.next_finish[action.name] or 0)
        then
            ctx.actions.party_adapter(
                action.name, action.semantic, self.encounter_id)
            self.next_finish[action.name] = now + FINISH_REQUEST_INTERVAL
        end
    end
end

function M.create()
    local self = {active=false, next_poll=0}
    clear_encounter(self)

    function self:on_activate(ctx)
        self.active = true
        self.next_poll = 0
        clear_encounter(self)
    end

    function self:on_deactivate(ctx)
        if ctx.player_name() == DOLO and self.encounter_id then
            retire(self, ctx, 'deactivated', false)
        else
            clear_encounter(self)
        end
        self.active = false
    end

    function self:on_action(ctx, action)
        if not self.active or ctx.player_name() ~= DOLO
            or ALLOWED_ZONES[ctx.zone_id()] ~= true
            or ctx.operator_armed() ~= true
            or type(action) ~= 'table'
        then
            return
        end

        local now = ctx.now()
        if not self.encounter_id then
            local candidate = current_candidate(ctx)
            if candidate and now >= (self.next_bind_attempt or 0) then
                bind(self, ctx, candidate, now)
            end
        end
        if not self.encounter_id then return end

        local actor = action_actor_name(ctx, action)
        local result = first_target_result(action, self.encounter_id)

        if tackle_pull_action(ctx, action, self.encounter_id) then
            release_chain_pair(self, ctx, 'CONFIRMED')
        end

        -- Any real party spell Magic Burst counts, including an improvised
        -- higher-tier or different-element cast. Automatic requests remain the
        -- low-cost Thunder spell pinned in the adapter.
        if tonumber(action.category) == 4 and PARTY_NAMES[actor] == true
            and magic_burst_on(action, self.encounter_id)
        then
            release_finishers(self, ctx)
            return
        end

        if self.mb_confirmed or tonumber(action.category) ~= 3
            or not successful_result(result)
        then
            return
        end

        if actor == KICK and tonumber(action.param) == WS_Evisceration then
            -- A manual correct opener is equivalent to the requested opener.
            self.chain = {
                stage='send-savage',
                next_at=now + CHAIN_STEP_DELAY,
                deadline=now + ACTION_RESULT_TIMEOUT,
            }
        elseif actor == DOLO and tonumber(action.param) == WS_SAVAGE_BLADE then
            if fragmentation_on(action, self.encounter_id) then
                begin_burst(self, ctx, now)
            elseif self.chain and (self.chain.stage == 'await-savage'
                or self.chain.stage == 'send-savage')
            then
                alert(ctx, 'SAVAGE BLADE LANDED WITHOUT FRAGMENTATION: rebuilding; manual recovery is available.', false)
                reset_chain(self, now)
            end
        end
    end

    function self:on_tick(ctx, now)
        if not self.active or ctx.player_name() ~= DOLO
            or now < self.next_poll
        then
            return
        end
        self.next_poll = now + POLL_INTERVAL

        if ALLOWED_ZONES[ctx.zone_id()] ~= true
            or ctx.operator_armed() ~= true
        then
            if self.encounter_id then retire(self, ctx, 'inactive', false) end
            return
        end

        local mob
        if self.encounter_id then
            mob = resolved_target(self, ctx, now)
            if not self.encounter_id then return end
        else
            mob = current_candidate(ctx)
            if not mob or now < (self.next_bind_attempt or 0)
                or not bind(self, ctx, mob, now)
            then
                return
            end
        end
        if not mob then return end

        if not self.chain_pair_released then
            if ctx.party_claimed(mob) == true then
                release_chain_pair(self, ctx, 'CONFIRMED')
            elseif self.force_attempts < FORCE_ATTEMPTS
                and now >= (self.next_force or math.huge)
            then
                ctx.actions.combat_force_members(
                    self.encounter_id, PULL_MEMBER)
                self.force_attempts = self.force_attempts + 1
                self.next_force = now + FORCE_INTERVAL
            end
            if not self.chain_pair_released
                and now - (self.pull_started_at or now)
                    >= PULL_FALLBACK_SECONDS
            then
                release_chain_pair(self, ctx, 'FALLBACK')
                alert(ctx, 'C TANK PULL FALLBACK: Tackle was directed first but no claim packet arrived within two seconds. The chain pair released so the timed route cannot deadlock.', true)
            end
            if not self.chain_pair_released then return end
        end

        if not self.mb_confirmed and not self.low_warned
            and (tonumber(mob.hpp) or 100) <= LOW_HPP_WARNING
        then
            self.low_warned = true
            alert(ctx, 'C BURST WARNING: target is at 20% or lower without observed credit. Improvise now if needed; automation will not lock or stop you.', true)
        end

        if self.mb_confirmed then
            run_finishers(self, ctx, now)
        else
            advance_chain(self, ctx, now)
        end
    end

    return self
end

return M
