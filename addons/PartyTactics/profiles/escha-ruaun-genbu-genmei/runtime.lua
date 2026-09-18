-- Genbu best-effort encounter automation.
--
-- This runtime coordinates independent lanes.  Exact encounter identity is
-- retained, but readiness, preflight, action results, and earlier setup steps
-- never authorize later work.  Operator arm is solely the explicit start/stop
-- switch.  Failed requests simply expire; native helpers, AutoWS2, and every
-- manual control remain available.  The only coordinated state is a bounded,
-- fail-open physical skillchain lane; it never filters operator input.

local M = {}

local BOSS = 'Genbu'
local ZONE = 289
local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'
local PARTY_MEMBER = {
    [DOLO]=true, [TACKLE]=true, [KICK]=true,
    [BARNEY]=true, [SMALLS]=true, [ACHOO]=true,
}

local POLL_INTERVAL = 0.25
local CLAIM_GAP_GRACE = 2.0
local MEMBER_ACTION_SPACING = 1.35
local SHOT_INTERVAL = 3.1
local TRIPLE_SHOT_INTERVAL = 300
local TRIPLE_SHOT_RETRY = 12
local HATE_REFRESH_INTERVAL = 30
local BARWATER_REFRESH_INTERVAL = 420
local SAMBA_REFRESH_INTERVAL = 80
local STEP_REFRESH_INTERVAL = 45
local DNC_RETRY_INTERVAL = 5
local PRESTO_RETRY_INTERVAL = 2
local PRESTO_CONFIRM_WINDOW = 5
local PRESTO_MAX_ATTEMPTS = 2
local PRESTO_EFFECT_DURATION = 30
local SAMBA_TP_COST = 350
local STEP_TP_COST = 100
local EVENT_DEDUPE = 4
local INVINCIBLE_DURATION = 30
local INVINCIBLE_SHOT_HOLD = 8
local OPENING_PROC_MERGE_WINDOW = 2
local FORCE_ATTEMPTS = 2
local FORCE_INTERVAL = 1.5
local FIRST_OFFENSE_DELAY = 2.0
local FIRST_CHAIN_DELAY = 10.0
local CHAIN_STEP_DELAY = 3.1
local CHAIN_RESULT_TIMEOUT = 8.0
local PARTNER_TP_WAIT = 10.0
local FAILED_CHAIN_KICK_BYPASS = 20.0
local SOLO_WS_RETRY = 10.0

local DNC_ABILITY = {HasteSamba=189, BoxStep=202, Presto=261}
local TRIPLE_SHOT_ABILITY = 301
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

local OPENING = {
    -- Ctrl-P is deliberately the universal immediate-force control.  Make the
    -- opener safe after that edge instead of pretending combat waits for it:
    -- Barney and Tackle act independently, Sentinel is immediate protection,
    -- and Crusade gets its full three-second base cast window before the next
    -- Tackle action is attempted.
    {recipient=BARNEY, semantic='barwatera', offset=0.05, attempts=1,
        interval=4.0},
    {recipient=TACKLE, semantic='sentinel', offset=0.05, attempts=1,
        interval=4.0},
    {recipient=DOLO, semantic='triple-shot', offset=0.10, attempts=1,
        interval=4.0},
    {recipient=TACKLE, semantic='crusade', offset=1.5, attempts=1,
        interval=4.0},
    {recipient=TACKLE, semantic='divine-emblem', offset=5.0, attempts=1,
        interval=4.0},
    {recipient=TACKLE, semantic='flash', offset=6.5, attempts=1,
        interval=4.0},
    {recipient=TACKLE, semantic='provoke', offset=8.0, attempts=1,
        interval=4.0},
    -- PartyCombat has already sent the melee edge, so hostile geomancy cannot
    -- become a hidden prerequisite.  It remains a single best-effort request.
    {recipient=ACHOO, semantic='setup', offset=2.0, attempts=1,
        interval=4.0},
}

local function exact_boss(mob)
    return type(mob) == 'table'
        and mob.name == BOSS
        and tonumber(mob.spawn_type) == 16
        and type(mob.id) == 'number'
        and mob.id >= 1 and mob.id <= 4294967295
        and mob.id == math.floor(mob.id)
        and type(mob.index) == 'number'
        and mob.index >= 0 and mob.index <= 65535
        and mob.index == math.floor(mob.index)
end

local function live_boss(mob)
    return exact_boss(mob) and mob.valid_target == true
        and (tonumber(mob.hpp) or 0) > 0
end

local function claimed_boss(ctx, mob)
    return live_boss(mob) and ctx.party_claimed(mob) == true
end

local function scan_boss(ctx, allow_current_unclaimed)
    local current = ctx.current_target()
    if claimed_boss(ctx, current)
        or (allow_current_unclaimed and live_boss(current)
            and (tonumber(current.claim_id) or 0) == 0)
    then
        return current
    end
    local selected
    for _, mob in pairs(ctx.mob_array() or {}) do
        if claimed_boss(ctx, mob)
            and (not selected or mob.id < selected.id)
        then
            selected = mob
        end
    end
    return selected
end

local function ability_name(ctx, action)
    if type(action) ~= 'table' then return nil end
    -- Category 7 is the monster's readying packet. Reacting there can rebuild
    -- songs before Tortoise Song lands and then dedupe the real completion.
    -- Only completed job/monster ability categories may schedule reactions.
    if action.category == 6 then
        local ability = ctx.monster_ability(action.param)
            or ctx.job_ability(action.param)
        return ability and ability.en or nil
    elseif action.category == 11 then
        local ability = ctx.monster_ability(action.param)
        return ability and ability.en or nil
    end
    return nil
end

local function light_on(action, target_id)
    for _, target in ipairs(type(action) == 'table'
        and action.targets or {})
    do
        if tonumber(target.id) == tonumber(target_id) then
            for _, result in ipairs(target.actions or {}) do
                if tonumber(result.add_effect_message) == 288
                    and (tonumber(result.add_effect_param) or 0) > 0
                then
                    return true
                end
            end
        end
    end
    return false
end

local function target_result(action, target_id)
    for _, target in ipairs(type(action) == 'table'
        and action.targets or {})
    do
        if tonumber(target.id) == tonumber(target_id) then
            return target.actions and target.actions[1] or nil
        end
    end
    return nil
end

local function successful_result(result)
    if type(result) ~= 'table' then return false end
    local message = tonumber(result.message)
    return message == nil or FAILURE_MESSAGES[message] ~= true
end

local function positive_physical_result(action, target_id)
    local category = type(action) == 'table' and tonumber(action.category)
    if category ~= 1 and category ~= 2 and category ~= 3 then return false end
    local result = target_result(action, target_id)
    return successful_result(result) and (tonumber(result.param) or 0) > 0
end

local function weapon_skill_name(ctx, action)
    if type(action) ~= 'table' or tonumber(action.category) ~= 3 then
        return nil
    end
    local weapon_skill = ctx.weapon_skill(action.param)
    return weapon_skill and weapon_skill.en or nil
end

local function action_actor_name(ctx, action)
    local actor = type(action) == 'table'
        and ctx.mob_by_id(action.actor_id) or nil
    return actor and actor.name or nil
end

local function clear_step_presto(self)
    self.presto_cycle_until = 0
    self.next_presto = 0
    self.presto_attempts = 0
    self.presto_ready_until = 0
end

local function clear_encounter(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.last_seen = nil
    self.claim_seen = false
    self.started_at = nil
    self.tasks = {}
    self.task_serial = 0
    self.next_member_action = {}
    self.next_shot = 0
    self.next_triple = 0
    self.next_hate = 0
    self.next_barwater = 0
    self.next_samba = 0
    self.next_step = 0
    clear_step_presto(self)
    self.force_at = nil
    self.next_force = nil
    self.force_attempts = 0
    self.last_event = {}
    self.recovery_serial = 0
    self.chain = nil
    self.next_chain = 0
    self.invincible_until = 0
    self.kick_bypass_until = 0
    self.dolo_ready_since = nil
    self.next_solo_ws = 0
    self.last_dolo_proc_request = -100000
end

local function task_key(recipient, semantic, family)
    return table.concat({family or 'task', recipient, semantic}, ':')
end

local function schedule(self, recipient, semantic, at, attempts, interval,
    family, token, priority)
    self.task_serial = self.task_serial + 1
    local key = task_key(recipient, semantic, family)
    self.tasks[key] = {
        key=key, recipient=recipient, semantic=semantic,
        next_at=at, attempts=0, max_attempts=attempts or 1,
        interval=interval or 3, token=token,
        priority=priority or 10, serial=self.task_serial,
    }
end

local function queue(self, ctx, task)
    local ok = ctx.actions.party_adapter(task.recipient, task.semantic,
        self.encounter_id, task.token)
    if task.recipient == DOLO and task.semantic == 'proc' then
        self.last_dolo_proc_request = ctx.now()
    end
    task.attempts = task.attempts + 1
    task.next_at = ctx.now() + task.interval
    self.next_member_action[task.recipient] = ctx.now()
        + MEMBER_ACTION_SPACING
    if task.attempts >= task.max_attempts then
        self.tasks[task.key] = nil
    end
    return ok == true
end

local function run_tasks(self, ctx, now)
    local due = {}
    for _, task in pairs(self.tasks) do
        if now >= task.next_at then due[#due + 1] = task end
    end
    table.sort(due, function(left, right)
        if left.priority ~= right.priority then
            return left.priority > right.priority
        end
        return left.serial < right.serial
    end)
    for _, task in ipairs(due) do
        local triple_yields = task.semantic == 'triple-shot'
            and (self.chain ~= nil
                or (tonumber(ctx.party_tp(DOLO)) or 0) >= 1500)
        if not triple_yields
            and (task.semantic ~= 'box-step'
                or now >= (self.invincible_until or 0))
            and now >= (self.next_member_action[task.recipient] or 0)
        then
            queue(self, ctx, task)
        end
    end
end

local function schedule_opening(self, now)
    for index, action in ipairs(OPENING) do
        schedule(self, action.recipient, action.semantic,
            now + action.offset, action.attempts, action.interval,
            'opening-'..tostring(index), nil, 40)
    end
end

local function bind(self, ctx, boss, now)
    clear_encounter(self)
    self.encounter_id = boss.id
    self.encounter_index = boss.index
    self.last_seen = now
    self.claim_seen = ctx.party_claimed(boss) == true
    self.started_at = now
    self.encounter_serial = (self.encounter_serial or 0) + 1

    -- Identity binding is routing metadata only.  Its result cannot delay or
    -- disable any action lane, and it is not polled or retried as readiness.
    ctx.authorize_encounter(boss.id)
    -- Bind each short Thunder queue to this exact Genbu life. These are
    -- routing messages, not actions or readiness gates, and their results do
    -- not delay any opening or combat lane.
    ctx.actions.party_adapter(DOLO, 'combat-start', boss.id)
    ctx.actions.party_adapter(TACKLE, 'combat-start', boss.id)
    ctx.actions.party_adapter(SMALLS, 'combat-start', boss.id)
    ctx.actions.party_adapter(ACHOO, 'combat-start', boss.id)
    schedule_opening(self, now)
    -- Genbu can complete its opening Invincible before the operator arms and
    -- before this runtime can observe the packet. One fixed Thunder Shot
    -- request covers that case without inferring immunity or holding any
    -- other lane. It shares the normal Dolo-proc task key, so a freshly
    -- observed Invincible replaces rather than duplicates pending work.
    schedule(self, DOLO, 'proc', now + 0.10, 1, 4,
        'invincible-dolo', 'opening-proc', 50)
    -- Ctrl-P already forces the selected target.  Sending the same exact-ID
    -- edge here makes //pt arm behave the same way and gives either entry path
    -- one bounded retransmission.  Nothing waits for either result.
    self.force_at = now
    self.next_force = self.force_at
    self.next_shot = self.force_at + FIRST_OFFENSE_DELAY
    -- The opening request is best effort. Until an actual completion packet
    -- starts Triple Shot's 300-second recast, issue another bounded request
    -- every twelve seconds instead of guessing an ability-use timestamp.
    self.next_triple = self.force_at + TRIPLE_SHOT_RETRY
    -- Tackle's fixed opening actions finish by eight seconds. Do not spend
    -- his TP on an early chain that would collide with Crusade/Flash/Provoke.
    self.next_chain = self.force_at + FIRST_CHAIN_DELAY
    self.next_hate = now + HATE_REFRESH_INTERVAL
    self.next_barwater = now + BARWATER_REFRESH_INTERVAL
    -- These DNC actions have TP costs. Check immediately, but do not emit a
    -- doomed command before Kick has enough live TP for the exact action.
    self.next_samba = now
    self.next_step = now
end

local function finish(self, ctx, stop_combat)
    local id = self.encounter_id
    if not id then return end
    -- Release only this fight's local Thunder reservations before discarding
    -- encounter authority. Neither message gates stop/disarm cleanup.
    ctx.actions.party_adapter(DOLO, 'combat-end', id)
    ctx.actions.party_adapter(TACKLE, 'combat-end', id)
    ctx.actions.party_adapter(SMALLS, 'combat-end', id)
    ctx.actions.party_adapter(ACHOO, 'combat-end', id)
    ctx.actions.party_adapter(DOLO, 'disengage', id)
    if stop_combat then ctx.actions.combat_stop() end
    ctx.release_encounter(id)
    clear_encounter(self)
end

local function resolved_boss(self, ctx, now)
    local boss = ctx.mob_by_id(self.encounter_id)
    if exact_boss(boss) and boss.id == self.encounter_id
        and boss.index == self.encounter_index
    then
        if not live_boss(boss) then
            finish(self, ctx, true)
            return nil
        end
        local claim = tonumber(boss.claim_id) or 0
        if ctx.party_claimed(boss) then
            self.claim_seen = true
            self.last_seen = now
            return boss
        end
        if claim == 0 and not self.claim_seen then
            self.last_seen = now
            return boss
        end
        if claim == 0
            and now - (self.last_seen or now) <= CLAIM_GAP_GRACE
        then
            return boss
        end
    end
    if now - (self.last_seen or now) > CLAIM_GAP_GRACE then
        finish(self, ctx, true)
    end
    return nil
end

local function event_once(self, name, now)
    if now - (self.last_event[name] or -100000) < EVENT_DEDUPE then
        return false
    end
    self.last_event[name] = now
    return true
end

local function schedule_invincible(self, ctx, now)
    -- Earlier evidence suggested that Thunder might end physical immunity
    -- early; the successful c049 capture instead resumed near 30 seconds.
    -- Keep that full duration as the normal hold, while an actually observed
    -- positive physical result remains a safe opportunistic release.
    self.invincible_until = math.max(self.invincible_until or 0,
        now + INVINCIBLE_DURATION)
    -- A zero-damage ranged attack every 3.1 seconds starved four otherwise
    -- ready Thunder Shot requests in the successful capture. Give the queued
    -- proc one short action window; no other lane waits on it, and normal
    -- ranged fire resumes automatically whether the proc succeeds or not.
    self.next_shot = math.max(self.next_shot or 0,
        now + INVINCIBLE_SHOT_HOLD)
    self.chain = nil
    self.dolo_ready_since = nil
    -- Presto lasts only thirty seconds, the same length as the nominal
    -- physical-immunity hold. Discard the observation and start a fresh,
    -- bounded Step preparation after physical work can resume.
    clear_step_presto(self)
    -- A Savage Blade may be waiting behind a Majesty cure on Tackle's local
    -- next-legal queue. Retire it with the runtime chain so it cannot emerge
    -- during physical immunity; the next intended chain request rebinds it.
    ctx.actions.party_adapter(TACKLE, 'cancel', self.encounter_id)
    -- If the one opening insurance request just crossed IPC, it already
    -- answers an Invincible observed on the same bind edge. Later events get
    -- their normal independent request. This is request dedupe only; it does
    -- not extend the physical hold or wait for any result.
    if now - (self.last_dolo_proc_request or -100000)
        >= OPENING_PROC_MERGE_WINDOW
    then
        schedule(self, DOLO, 'proc', now, 1, 4,
            'invincible-dolo', nil, 100)
    end
    schedule(self, ACHOO, 'proc', now + 1.5, 1, 4,
        'invincible-achoo', nil, 100)
    schedule(self, SMALLS, 'proc', now + 3.0, 1, 4,
        'invincible-smalls', nil, 100)
end

local function cancel_invincible_fallbacks(self, ctx)
    self.tasks[task_key(ACHOO, 'proc', 'invincible-achoo')] = nil
    self.tasks[task_key(SMALLS, 'proc', 'invincible-smalls')] = nil
    -- A backup request may already have crossed IPC while its character was
    -- busy. Cancel only that adapter's short local queue. Future Light or
    -- Invincible requests can re-establish their exact encounter binding.
    ctx.actions.party_adapter(ACHOO, 'cancel', self.encounter_id)
    ctx.actions.party_adapter(SMALLS, 'cancel', self.encounter_id)
end

local function schedule_tortoise_song(self, now)
    self.recovery_serial = self.recovery_serial + 1
    -- The adapter remembers recovery tokens across a same-version profile
    -- reapply. Include the exact boss life and monotonic event time so a new
    -- runtime instance cannot accidentally reuse an earlier fight's token.
    local token = ('tortoise-%s-%d-%d'):format(
        tostring(self.encounter_id or 0), math.floor(now * 1000),
        self.recovery_serial)
    schedule(self, BARNEY, 'recover-songs', now, 1, 1,
        'tortoise-songs-'..token, token, 130)
    schedule(self, DOLO, 'recover-rolls', now + 0.5, 1, 1,
        'tortoise-rolls-'..token, token, 130)
end

local function schedule_burst(self, now)
    schedule(self, SMALLS, 'burst', now, 1, 2.5,
        'light-smalls', nil, 80)
    schedule(self, ACHOO, 'burst', now + 0.75, 1, 2.5,
        'light-achoo', nil, 80)
end

local function reset_chain(self, now)
    self.chain = nil
    self.next_chain = now + 0.5
end

local function send_chain_ws(self, ctx, recipient, semantic, waiting, now)
    ctx.actions.party_adapter(recipient, semantic, self.encounter_id)
    self.next_member_action[recipient] = now + MEMBER_ACTION_SPACING
    self.chain = {
        stage=waiting,
        deadline=now + CHAIN_RESULT_TIMEOUT,
    }
end

local function advance_chain(self, ctx, now)
    if now < (self.invincible_until or 0) then return false end

    local chain = self.chain
    if chain and now > (chain.deadline or now) then
        -- A missed action result cannot keep choosing the optional Kick step.
        -- The next attempt falls back to the complete two-step Light chain.
        self.kick_bypass_until = math.max(self.kick_bypass_until or 0,
            now + FAILED_CHAIN_KICK_BYPASS)
        if chain.stage == 'await-last-stand' then
            -- If the close request failed and Dolo retained TP, let the
            -- standalone fail-open lane retry immediately.  If it actually
            -- fired, the live TP value naturally suppresses the retry.
            self.dolo_ready_since = now - PARTNER_TP_WAIT
        end
        reset_chain(self, now)
        chain = nil
    end
    if chain then
        if chain.stage == 'send-savage' and now >= chain.next_at then
            if (tonumber(ctx.party_tp(TACKLE)) or 0) >= 1000
                and now >= (self.next_member_action[TACKLE] or 0)
            then
                send_chain_ws(self, ctx, TACKLE, 'savage-blade',
                    'await-savage', now)
                return true
            end
        elseif chain.stage == 'send-last-stand'
            and now >= chain.next_at
        then
            if (tonumber(ctx.party_tp(DOLO)) or 0) >= 1000
                and now >= (self.next_member_action[DOLO] or 0)
            then
                send_chain_ws(self, ctx, DOLO, 'last-stand',
                    'await-last-stand', now)
                return true
            end
        end
        return false
    end

    if now < (self.next_chain or 0) then return false end
    local tackle_tp = tonumber(ctx.party_tp(TACKLE)) or 0
    local dolo_tp = tonumber(ctx.party_tp(DOLO)) or 0
    if dolo_tp >= 1500 then
        self.dolo_ready_since = self.dolo_ready_since or now
    else
        self.dolo_ready_since = nil
    end
    if tackle_tp < 1250 or dolo_tp < 1500 then
        -- Do not park Dolo forever at capped/ready TP if Tackle cannot supply
        -- the opener.  After one bounded partner window, use Last Stand for
        -- damage and try the coordinated chain again on the next TP cycle.
        if dolo_tp >= 1500 and self.dolo_ready_since
            and now - self.dolo_ready_since >= PARTNER_TP_WAIT
            and now >= (self.next_member_action[DOLO] or 0)
            and now >= (self.next_solo_ws or 0)
        then
            ctx.actions.party_adapter(DOLO, 'last-stand', self.encounter_id)
            self.next_member_action[DOLO] = now + MEMBER_ACTION_SPACING
            self.next_solo_ws = now + SOLO_WS_RETRY
            self.dolo_ready_since = now
            self.next_chain = now + 0.5
            return true
        end
        return false
    end
    self.dolo_ready_since = nil

    local kick_tp = tonumber(ctx.party_tp(KICK)) or 0
    if kick_tp >= 1000
        and now >= (self.kick_bypass_until or 0)
        and now >= (self.next_member_action[KICK] or 0)
    then
        send_chain_ws(self, ctx, KICK, 'evisceration',
            'await-evisceration', now)
    elseif now >= (self.next_member_action[TACKLE] or 0) then
        -- Savage Blade -> Last Stand is already Light.  Kick's opening step is
        -- opportunistic, so low Kick TP can never stall a ready two-step chain.
        send_chain_ws(self, ctx, TACKLE, 'savage-blade',
            'await-savage', now)
    end
    return self.chain ~= nil
end

function M.create()
    local self = {active=false, next_poll=0, encounter_serial=0}
    clear_encounter(self)

    function self:on_activate(ctx)
        self.active = true
        self.next_poll = 0
        clear_encounter(self)
    end

    function self:on_deactivate(ctx)
        if ctx.player_name() == DOLO and self.encounter_id then
            finish(self, ctx, true)
        else
            clear_encounter(self)
        end
        self.active = false
    end

    function self:on_action(ctx, action)
        if not self.active or ctx.player_name() ~= DOLO
            or ctx.zone_id() ~= ZONE or type(action) ~= 'table'
            or ctx.operator_armed() ~= true
        then
            return
        end

        local now = ctx.now()
        if not self.encounter_id then
            local boss = scan_boss(ctx, true)
            if boss then bind(self, ctx, boss, now) end
        end
        if not self.encounter_id then return end

        local actor = action_actor_name(ctx, action)
        local category = tonumber(action.category)
        local ability_id = tonumber(action.param)
        if now < (self.invincible_until or 0) and PARTY_MEMBER[actor]
            and positive_physical_result(action, self.encounter_id)
        then
            -- Do not infer early release from Thunder alone. If a positive
            -- melee/ranged/WS result actually lands before the nominal timer,
            -- that server result is authoritative: clear stale chain state,
            -- discard undelivered backup Thunder requests, and resume. The
            -- successful c049 capture normally used the full 30-second hold.
            self.invincible_until = 0
            cancel_invincible_fallbacks(self, ctx)
            reset_chain(self, now)
        end
        if actor == KICK and (category == 6 or category == 14) then
            if ability_id == DNC_ABILITY.HasteSamba
                and successful_result(target_result(action, action.actor_id))
            then
                -- A manual Haste Samba counts too.  The long timer starts
                -- only from a completed action packet, never from a command
                -- submission that may have collided with movement/casting.
                self.next_samba = now + SAMBA_REFRESH_INTERVAL
            elseif ability_id == DNC_ABILITY.Presto
                and successful_result(target_result(
                    action, action.actor_id))
                and now >= (self.invincible_until or 0)
                and now >= (self.next_step or 0)
            then
                -- A command submission is not proof of Presto. Only its
                -- successful local action packet opens the enhanced Step
                -- path. A manually issued Presto is equally valid while a
                -- Step is actually due.
                self.presto_ready_until = now + PRESTO_EFFECT_DURATION
                self.presto_cycle_until = 0
                self.next_presto = 0
                self.presto_attempts = 0
            elseif ability_id == DNC_ABILITY.BoxStep
                and successful_result(target_result(
                    action, self.encounter_id))
            then
                self.next_step = now + STEP_REFRESH_INTERVAL
                clear_step_presto(self)
            end
        end
        if actor == DOLO and (category == 6 or category == 14)
            and ability_id == TRIPLE_SHOT_ABILITY
            and successful_result(target_result(action, action.actor_id))
        then
            -- Successful completion, including a manual use, is the only
            -- event that advances the real five-minute cadence. Retire any
            -- not-yet-dispatched retry for this same completed action.
            self.next_triple = now + TRIPLE_SHOT_INTERVAL
            for key, task in pairs(self.tasks) do
                if task.recipient == DOLO
                    and task.semantic == 'triple-shot'
                then
                    self.tasks[key] = nil
                end
            end
        end

        if tonumber(action.actor_id) == self.encounter_id then
            local name = ability_name(ctx, action)
            if name == 'Invincible' and event_once(self, name, now) then
                schedule_invincible(self, ctx, now)
            elseif name == 'Tortoise Song'
                and event_once(self, name, now)
            then
                schedule_tortoise_song(self, now)
            end
        end

        if successful_result(target_result(action, self.encounter_id))
            and now >= (self.invincible_until or 0)
        then
            local ws = weapon_skill_name(ctx, action)
            if ws == 'Evisceration' and actor == KICK then
                -- A completed manual Evisceration is just as valid as the
                -- requested opener.  Observing it may recover a lost request
                -- or replace any stale in-flight chain state.
                self.chain = {
                    stage='send-savage', next_at=now + CHAIN_STEP_DELAY,
                    deadline=now + CHAIN_RESULT_TIMEOUT,
                }
            elseif ws == 'Savage Blade' and actor == TACKLE then
                -- Also close a manually issued Savage Blade. Manual input is
                -- never reserved or filtered; this is only an opportunistic
                -- automatic response to an observed, completed opener.
                self.chain = {
                    stage='send-last-stand',
                    next_at=now + CHAIN_STEP_DELAY,
                    deadline=now + CHAIN_RESULT_TIMEOUT,
                }
            elseif ws == 'Last Stand' and actor == DOLO then
                self.dolo_ready_since = nil
                reset_chain(self, now)
            end
        end

        if light_on(action, self.encounter_id)
            and event_once(self, 'Light', now)
        then
            schedule_burst(self, now)
        end
    end

    function self:on_tick(ctx, now)
        if not self.active or ctx.player_name() ~= DOLO
            or now < self.next_poll
        then
            return
        end
        self.next_poll = now + POLL_INTERVAL

        if ctx.zone_id() ~= ZONE then
            if self.encounter_id then finish(self, ctx, true) end
            return
        end

        if ctx.operator_armed() ~= true then
            if self.encounter_id then finish(self, ctx, true) end
            return
        end

        local boss
        if self.encounter_id then
            boss = resolved_boss(self, ctx, now)
            if not self.encounter_id then return end
        else
            boss = scan_boss(ctx, true)
            if not boss then return end
            bind(self, ctx, boss, now)
        end
        if not boss then return end

        -- Establish combat before dispatching any same-frame hostile support.
        -- This ordering still advances strictly by time; it does not wait for
        -- or inspect an engage result.
        if self.force_attempts < FORCE_ATTEMPTS
            and now >= (self.next_force or math.huge)
        then
            ctx.client.engage_once(boss.id)
            ctx.actions.combat_force(boss.id)
            self.force_attempts = self.force_attempts + 1
            self.next_force = now + FORCE_INTERVAL
        end

        if now >= self.next_triple then
            schedule(self, DOLO, 'triple-shot', now, 1, 4,
                'triple-shot-refresh', nil, 20)
            -- A missing/busy/rejected request gets another bounded chance;
            -- it never postpones itself by a full ability recast.
            self.next_triple = now + TRIPLE_SHOT_RETRY
        end

        if now >= self.next_barwater then
            -- Refresh once near seven minutes (and again only if an unusually
            -- long encounter reaches another full interval). Two submissions
            -- are bounded insurance against Barney already singing; neither
            -- result is observed or used as permission for any other lane.
            schedule(self, BARNEY, 'barwatera', now, 2, 4,
                'barwater-refresh', nil, 15)
            self.next_barwater = now + BARWATER_REFRESH_INTERVAL
        end

        run_tasks(self, ctx, now)

        local chain_action = advance_chain(self, ctx, now)
        local dolo_tp = tonumber(ctx.party_tp(DOLO)) or 0
        if not chain_action and dolo_tp < 1500 and now >= self.next_shot
            and now >= (self.next_member_action[DOLO] or 0)
        then
            ctx.actions.party_adapter(DOLO, 'shoot', boss.id)
            self.next_member_action[DOLO] = now + MEMBER_ACTION_SPACING
            self.next_shot = now + SHOT_INTERVAL
        end

        local kick_tp = tonumber(ctx.party_tp(KICK)) or 0
        local kick_available = now >= (self.next_member_action[KICK] or 0)
        if now >= self.next_samba and kick_tp >= SAMBA_TP_COST
            and kick_available
        then
            -- Submit directly from the TP sample. Deferring this into the
            -- task queue could spend a stale TP value after another DNC
            -- action and then suppress the retry for an entire refresh.
            ctx.actions.party_adapter(KICK, 'haste-samba', self.encounter_id)
            self.next_member_action[KICK] = now + MEMBER_ACTION_SPACING
            -- Failed/busy/out-of-range submissions retry independently.  No
            -- other action waits for this confirmation.
            self.next_samba = now + DNC_RETRY_INTERVAL
        elseif now >= self.next_step and kick_tp >= STEP_TP_COST
            and now >= (self.invincible_until or 0)
            and kick_available
        then
            -- Presto lets the next Step raise Sluggish Daze by up to five
            -- levels and adds Step accuracy. Give it two independent,
            -- completion-driven chances inside one five-second window. If
            -- neither completion is observed, fail open to an ordinary Box
            -- Step; a missing Presto packet can never gate defense-down work.
            if (self.presto_ready_until or 0) > 0
                and now >= self.presto_ready_until
            then
                clear_step_presto(self)
            end

            if now < (self.presto_ready_until or 0) then
                ctx.actions.party_adapter(
                    KICK, 'box-step', self.encounter_id)
                self.next_member_action[KICK] = now + MEMBER_ACTION_SPACING
                self.next_step = now + DNC_RETRY_INTERVAL
            else
                if (self.presto_cycle_until or 0) <= 0 then
                    self.presto_cycle_until = now + PRESTO_CONFIRM_WINDOW
                    self.next_presto = now
                    self.presto_attempts = 0
                end

                if now >= self.presto_cycle_until then
                    -- The bounded enhancement window expired. Clear only its
                    -- local observation and proceed with the same Box Step
                    -- retry behavior used by the proven v2.6 plan.
                    clear_step_presto(self)
                    ctx.actions.party_adapter(
                        KICK, 'box-step', self.encounter_id)
                    self.next_member_action[KICK] =
                        now + MEMBER_ACTION_SPACING
                    self.next_step = now + DNC_RETRY_INTERVAL
                elseif self.presto_attempts < PRESTO_MAX_ATTEMPTS
                    and now >= (self.next_presto or 0)
                then
                    ctx.actions.party_adapter(
                        KICK, 'presto', self.encounter_id)
                    self.presto_attempts = self.presto_attempts + 1
                    self.next_presto = now + PRESTO_RETRY_INTERVAL
                    self.next_member_action[KICK] =
                        now + MEMBER_ACTION_SPACING
                end
            end
        end

        if now >= self.next_hate then
            schedule(self, TACKLE, 'flash', now, 1, 4,
                'hate-flash', nil, 30)
            schedule(self, TACKLE, 'provoke', now + 1.5, 1, 4,
                'hate-provoke', nil, 30)
            self.next_hate = now + HATE_REFRESH_INTERVAL
        end
    end

    return self
end

return M
