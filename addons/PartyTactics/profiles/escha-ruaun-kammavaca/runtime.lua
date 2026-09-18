local M = {}

local BOSS = 'Kammavaca'
local ORDER = {
    "Kammavaca's Clionid",
    "Kammavaca's Limule",
    "Kammavaca's Murex",
    "Kammavaca's Amoeban",
}

local HORDE_LULLABY_II = 377
local SILENCE = 59
local SLEEP_STATUS = 2
local SILENCE_STATUS = 6
local EFFECT_LANDED = {
    [236]=true, [237]=true, [267]=true, [268]=true,
    [269]=true, [270]=true, [271]=true, [272]=true,
}

local ALERTS = {
    ['Chainspell']='CHAINSPELL: best-effort Silence remains queued. Recover HP/MP while automatic CLMA targeting continues.',
    ['Exponential Burst']='EXPONENTIAL BURST: adds supersede Kammavaca immediately; automatic CLMA targeting continues.',
}

local POLL_INTERVAL = 0.20
local ENCOUNTER_RESET_GRACE = 2
local ADD_FREE_SETTLE = 0.75
local ADD_ASSOCIATION_RADIUS = 20
local SILENCE_REQUEST_RETRY = 2
local MAX_SILENCE_ATTEMPTS = 3
local SILENCE_REFRESH = 40
local MAX_SLEEP_ATTEMPTS = 3
local SLEEP_RETRY = 6
local SLEEP_REFRESH = 75
local SLEEP_QUEUE_TIMEOUT = 10
local SLEEP_CYCLE_COOLDOWN = 4
local OBSERVE_RETRY = 0.75
local MAX_OBSERVE_ATTEMPTS = 6
local OBSERVE_CYCLE_COOLDOWN = 2
local BAR_RETRY = 8
local FORCE_RETRY = 0.75
local MAX_FORCE_ATTEMPTS = 3
local FORCE_CYCLE_COOLDOWN = 2
local SUPPORT_WARNING_DELAY = 10

local function live_enemy(mob)
    return type(mob) == 'table'
        and mob.spawn_type == 16
        and mob.valid_target
        and (tonumber(mob.hpp) or 0) > 0
        and type(mob.id) == 'number'
        and mob.id >= 1 and mob.id <= 4294967295
end

local function ability_from_action(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = ctx.monster_ability(result.param)
                if ability then return ability end
            end
        end
    elseif action.category == 6 or action.category == 11 then
        return ctx.monster_ability(action.param)
    end
    return nil
end

local function action_actor(ctx, action)
    return type(action) == 'table' and ctx.mob_by_id(action.actor_id) or nil
end

local function effect_result(action, target_id, status_id)
    local no_effect = false
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id) then
            for _, result in ipairs(target.actions or {}) do
                if EFFECT_LANDED[tonumber(result.message)]
                    and tonumber(result.param) == status_id
                then
                    return 'landed'
                elseif tonumber(result.message) == 75 then
                    no_effect = true
                end
            end
        end
    end
    return no_effect and 'no-effect' or nil
end

local function sleep_coverage(self, adds, now)
    local complete, oldest = #adds > 0, nil
    for _, entry in ipairs(adds) do
        local landed_at = tonumber(self.sleep_covered[entry.mob.id])
        if not landed_at or now - landed_at >= SLEEP_REFRESH then
            complete = false
        elseif not oldest or landed_at < oldest then
            oldest = landed_at
        end
    end
    return complete, oldest
end

local function coordinate(value)
    local number = tonumber(value)
    if not number or number ~= number or math.abs(number) > 1000000 then
        return nil
    end
    return number
end

local function associated_add(ctx, mob, boss)
    if ctx.party_claimed(mob) then return true end
    local raw_claim_id = mob.claim_id
    local claim_id = tonumber(raw_claim_id)
    if raw_claim_id ~= nil and claim_id == nil then return false end
    if claim_id and claim_id ~= 0 then return false end
    if not boss then return false end

    local mx, my, mz = coordinate(mob.x), coordinate(mob.y), coordinate(mob.z)
    local bx, by, bz = coordinate(boss.x), coordinate(boss.y), coordinate(boss.z)
    if not mx or not my or not mz or not bx or not by or not bz then
        return false
    end
    local dx, dy, dz = mx - bx, my - by, mz - bz
    return dx * dx + dy * dy + dz * dz
        <= ADD_ASSOCIATION_RADIUS * ADD_ASSOCIATION_RADIUS
end

local function scan(ctx, preferred_boss_id)
    local boss, claimed_boss, fallback_boss = nil, nil, nil
    local candidates, adds = {}, {}
    for _, mob in pairs(ctx.mob_array() or {}) do
        if live_enemy(mob) then
            if mob.name == BOSS then
                if preferred_boss_id and mob.id == preferred_boss_id then
                    boss = mob
                elseif ctx.party_claimed(mob)
                    and (not claimed_boss or mob.id < claimed_boss.id)
                then
                    claimed_boss = mob
                elseif not fallback_boss or mob.id < fallback_boss.id then
                    fallback_boss = mob
                end
            else
                for order, name in ipairs(ORDER) do
                    if mob.name == name then
                        local entry = {mob=mob, order=order}
                        candidates[#candidates + 1] = entry
                        break
                    end
                end
            end
        end
    end
    boss = boss or claimed_boss or fallback_boss
    for _, entry in ipairs(candidates) do
        if associated_add(ctx, entry.mob, boss) then
            adds[#adds + 1] = entry
        end
    end
    table.sort(adds, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        return left.mob.id < right.mob.id
    end)
    return boss, adds
end

local function reset_encounter(self)
    self.encounter_id = nil
    self.encounter_seen_at = nil
    self.last_visible_at = nil
    self.sleep_confirmed = false
    self.sleep_confirmed_at = nil
    self.sleep_covered = {}
    self.previous_add_ids = {}
    self.retired_add_ids = {}
    self.sleep_attempts = 0
    self.sleep_inflight_until = nil
    self.next_sleep_attempt = 0
    self.sleep_cycle_reset_at = 0
    self.sleep_anchor_id = nil
    self.observe_attempts = 0
    self.next_observe_attempt = 0
    self.observe_cycle_reset_at = 0
    self.silence_confirmed = false
    self.silence_confirmed_at = nil
    self.silence_refresh_at = nil
    self.silence_request_issued = false
    self.silence_attempts = 0
    self.next_silence_attempt = 0
    self.last_forced_id = nil
    self.force_issued_for_target = false
    self.force_attempts = 0
    self.next_force_attempt = 0
    self.force_cycle_reset_at = 0
    self.silence_warning = false
    self.sleep_warning = false
end

local function begin_encounter(self, boss, now)
    reset_encounter(self)
    self.encounter_id = boss.id
    self.encounter_seen_at = now
    self.last_visible_at = now
end

local function encounter_snapshot(self, ctx, now)
    local boss, adds = scan(ctx, self.encounter_id)
    local claimed = boss and ctx.party_claimed(boss)
    if claimed and self.encounter_id ~= boss.id then
        begin_encounter(self, boss, now)
    end

    if self.encounter_id then
        if boss and boss.id == self.encounter_id and claimed then
            self.last_visible_at = now
        elseif boss and boss.id == self.encounter_id then
            -- Claim loss can mean a wipe or another party's encounter. Never
            -- carry Silence/Sleep authorization across that boundary.
            reset_encounter(self)
            return nil, {}, {}
        elseif now - (self.last_visible_at or now) >= ENCOUNTER_RESET_GRACE then
            reset_encounter(self)
            return nil, {}, {}
        end
    end

    if not self.encounter_id or not boss or boss.id ~= self.encounter_id
        or not claimed
    then
        return nil, {}, {}
    end

    local current_add_ids = {}
    local new_add = false
    for _, entry in ipairs(adds) do
        current_add_ids[entry.mob.id] = true
        if not self.previous_add_ids[entry.mob.id] then new_add = true end
    end
    for id, _ in pairs(self.previous_add_ids) do
        if not current_add_ids[id] then self.retired_add_ids[id] = true end
    end
    for id, _ in pairs(current_add_ids) do
        if self.retired_add_ids[id] then
            -- A wrong-order respawn can reuse the same server entity ID. Its
            -- earlier sleep result does not describe the new life, and the
            -- same ID still needs a fresh PartyCombat force broadcast.
            self.sleep_confirmed = false
            self.sleep_covered[id] = nil
            self.sleep_attempts = 0
            self.next_sleep_attempt = now
            self.sleep_cycle_reset_at = 0
            self.last_forced_id = nil
            self.force_issued_for_target = false
            self.force_attempts = 0
            self.next_force_attempt = now
            self.force_cycle_reset_at = 0
            self.retired_add_ids[id] = nil
        end
    end
    if new_add then
        self.sleep_confirmed = false
        self.sleep_attempts = 0
        self.next_sleep_attempt = now
        self.sleep_cycle_reset_at = 0
    end
    self.previous_add_ids = current_add_ids
    if self.sleep_confirmed and #adds > 0 then
        local covered = sleep_coverage(self, adds, now)
        if not covered then
            self.sleep_confirmed = false
            self.sleep_attempts = 0
            self.next_sleep_attempt = now
            self.sleep_cycle_reset_at = 0
        end
    end
    if self.silence_confirmed and self.silence_refresh_at
        and now >= self.silence_refresh_at
    then
        self.silence_confirmed = false
        self.silence_request_issued = false
        self.silence_attempts = 0
        self.next_silence_attempt = now
    end
    return boss, adds
end

local function smalls_tick(self, ctx, now, boss)
    if self.silence_confirmed or self.silence_request_issued
        or self.silence_attempts >= MAX_SILENCE_ATTEMPTS
        or now < (self.next_silence_attempt or 0)
    then return end

    -- The RDM GearSwap controller owns next-action priority, casting, bounded
    -- retries, and completion. This runtime owns encounter-level rearm and the
    -- 40-second refresh cycle; Silence is never an engagement prerequisite.
    local accepted = ctx.actions.controller('rdm', 'silence', boss.id)
    self.silence_attempts = self.silence_attempts + 1
    if accepted ~= false then
        self.silence_request_issued = true
    else
        self.next_silence_attempt = now + SILENCE_REQUEST_RETRY
    end
end

local function barney_tick(self, ctx, now, adds)
    if #adds == 0 or self.sleep_confirmed then return end
    local anchor = adds[1].mob
    if self.sleep_anchor_id ~= anchor.id then
        self.sleep_anchor_id = anchor.id
        self.observe_attempts = 0
        self.next_observe_attempt = now
        self.observe_cycle_reset_at = 0
        self.sleep_attempts = 0
        self.sleep_inflight_until = nil
        self.next_sleep_attempt = now
        self.sleep_cycle_reset_at = 0
    end

    local selected = ctx.current_target()
    if not selected or selected.id ~= anchor.id then
        if now < self.next_observe_attempt then return end
        if self.observe_attempts >= MAX_OBSERVE_ATTEMPTS then
            if now < self.observe_cycle_reset_at then return end
            self.observe_attempts = 0
        end
        if self.observe_attempts < MAX_OBSERVE_ATTEMPTS then
            ctx.actions.combat_observe(anchor.id)
            self.observe_attempts = self.observe_attempts + 1
            self.next_observe_attempt = now + OBSERVE_RETRY
            if self.observe_attempts >= MAX_OBSERVE_ATTEMPTS then
                self.observe_cycle_reset_at = now + OBSERVE_CYCLE_COOLDOWN
            end
        end
        return
    end
    self.observe_attempts = 0
    self.observe_cycle_reset_at = 0

    if self.sleep_inflight_until then
        if now < self.sleep_inflight_until then return end
        self.sleep_inflight_until = nil
        self.next_sleep_attempt = now + SLEEP_RETRY
    end
    if now < (self.next_sleep_attempt or 0) then return end
    if self.sleep_attempts >= MAX_SLEEP_ATTEMPTS then
        if now < self.sleep_cycle_reset_at then return end
        self.sleep_attempts = 0
    end

    -- PartyCombat performs selection only on target-only Barney. After that
    -- exact selection is visible locally, the reviewed GearSwap-owned queue
    -- casts against <t>; numeric-ID Bard song commands are not reliable.
    local accepted = ctx.actions.controller('brd', 'sleep')
    if accepted ~= false then
        self.sleep_attempts = self.sleep_attempts + 1
        self.sleep_inflight_until = now + SLEEP_QUEUE_TIMEOUT
        if self.sleep_attempts >= MAX_SLEEP_ATTEMPTS then
            self.sleep_cycle_reset_at = now + SLEEP_CYCLE_COOLDOWN
        end
    else
        self.next_sleep_attempt = now + SLEEP_RETRY
    end
end

local function barsilence_tick(self, ctx, now)
    if ctx.has_buff('Barsilence') or now < self.next_bar_attempt then return end
    ctx.actions.cast('Barsilencera', '<me>')
    self.next_bar_attempt = now + BAR_RETRY
end

local function support_warning_tick(self, ctx, now, adds)
    if not self.silence_confirmed and not self.silence_warning
        and now - self.encounter_seen_at >= SUPPORT_WARNING_DELAY
    then
        self.silence_warning = true
        ctx.alert('SUPPORT NOTE: Kammavaca Silence is not confirmed. Ordered combat continues; //pt silence remains a fallback.', false)
    end
    if #adds > 0 and not self.sleep_confirmed and not self.sleep_warning
        and now - self.encounter_seen_at >= SUPPORT_WARNING_DELAY
    then
        self.sleep_warning = true
        ctx.alert('SUPPORT NOTE: full Horde Lullaby coverage is not confirmed. Exact CLMA combat continues; //pt sleep remains a fallback.', false)
    end
end

local function dolo_tick(self, ctx, now, boss, adds)
    support_warning_tick(self, ctx, now, adds)
    if not ctx.combat_ready() then
        self.force_issued_for_target = false
        self.force_attempts = 0
        self.next_force_attempt = now
        self.force_cycle_reset_at = 0
        return
    end

    local target
    if #adds > 0 then
        target = adds[1].mob
    else
        local settled = now - (self.encounter_seen_at or now)
            >= ADD_FREE_SETTLE
        if not settled then return end
        target = boss
    end
    if not target then return end

    if target.id ~= self.last_forced_id then
        self.last_forced_id = target.id
        self.force_issued_for_target = false
        self.force_attempts = 0
        self.next_force_attempt = now
        self.force_cycle_reset_at = 0
    end

    local selected = ctx.current_target()
    local target_matches = live_enemy(selected) and selected.id == target.id
    if self.force_issued_for_target and target_matches then
        self.force_attempts = 0
        self.force_cycle_reset_at = 0
        return
    end
    if now < self.next_force_attempt then return end
    if self.force_attempts >= MAX_FORCE_ATTEMPTS then
        if now < self.force_cycle_reset_at then return end
        self.force_attempts = 0
    end

    local accepted = ctx.actions.combat_force(target.id)
    self.force_attempts = self.force_attempts + 1
    self.next_force_attempt = now + FORCE_RETRY
    if self.force_attempts >= MAX_FORCE_ATTEMPTS then
        self.force_cycle_reset_at = now + FORCE_CYCLE_COOLDOWN
    end
    if accepted ~= false then
        self.force_issued_for_target = true
    end
end

function M.create()
    local self = {
        active=false, next_poll=0, next_bar_attempt=0, last_alert={},
    }
    reset_encounter(self)

    function self:on_activate(ctx)
        self.active = true
        ctx.client.auto_target(false)
    end

    function self:on_deactivate(ctx)
        self.active = false
        reset_encounter(self)
        ctx.client.auto_target(true)
    end

    function self:on_action(ctx, action)
        if not self.active or type(action) ~= 'table' then return end
        local now = ctx.now()
        local actor = action_actor(ctx, action)

        local ability = ability_from_action(ctx, action)
        if actor and actor.name == BOSS and ability then
            local message = ALERTS[ability.en]
            if message and now - (self.last_alert[ability.en] or 0) >= 6 then
                self.last_alert[ability.en] = now
                ctx.alert(message, true)
            end
        end

        if not self.encounter_id then return end
        if actor and actor.name == BOSS and actor.id == self.encounter_id
            and action.category == 8 and self.silence_confirmed
        then
            -- A fresh enemy cast start opens one new semantic controller
            -- cycle. It never changes the ordered combat target.
            self.silence_confirmed = false
            self.silence_request_issued = false
            self.silence_attempts = 0
            self.next_silence_attempt = now
        end

        if action.category == 4 and tonumber(action.param) == SILENCE
            and effect_result(action, self.encounter_id, SILENCE_STATUS)
                == 'landed'
        then
            self.silence_confirmed = true
            self.silence_confirmed_at = now
            self.silence_refresh_at = now + SILENCE_REFRESH
            self.silence_request_issued = true
            self.silence_attempts = 0
            self.silence_warning = false
        end

        if action.category == 4 and tonumber(action.param) == HORDE_LULLABY_II
            and actor and actor.name == 'Barneystinson'
        then
            local _, adds = scan(ctx, self.encounter_id)
            for _, entry in ipairs(adds) do
                local id = entry.mob.id
                if effect_result(action, id, SLEEP_STATUS) == 'landed' then
                    -- Positive results accumulate across bounded retries. A
                    -- later no-effect can preserve this proof, but can never
                    -- create or extend it.
                    self.sleep_covered[id] = now
                end
            end
            local complete, oldest = sleep_coverage(self, adds, now)
            self.sleep_inflight_until = nil
            if complete then
                self.sleep_confirmed = true
                self.sleep_confirmed_at = oldest
                self.sleep_warning = false
            else
                self.sleep_confirmed = false
                self.next_sleep_attempt = now + SLEEP_RETRY
            end
        end
    end

    function self:on_tick(ctx, now)
        if not self.active or now < self.next_poll then return end
        self.next_poll = now + POLL_INTERVAL

        local boss, adds = encounter_snapshot(self, ctx, now)
        local player_name = ctx.player_name()
        if not boss then
            if player_name == 'Barneystinson' and not self.encounter_id then
                barsilence_tick(self, ctx, now)
            end
            return
        end

        if player_name == 'Smalls' then
            smalls_tick(self, ctx, now, boss)
        elseif player_name == 'Barneystinson' then
            barney_tick(self, ctx, now, adds)
        elseif player_name == 'Dolomedes' then
            dolo_tick(self, ctx, now, boss, adds)
        end
    end

    return self
end

return M
