-- Cooperative Rancibus automation.
--
-- The operator's arm switch is only start/stop.  Once armed, every lane makes
-- short best-effort requests independently; no acknowledgement, preflight,
-- opener, packet result, support action, or weaponskill authorizes another
-- lane.  Disarming stops these requests and PartyCombat, but the GearSwap
-- adapter never intercepts manual actions.

local M = {}

local BOSS = 'Rancibus'
local ZONE = 277
local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'

local POLL_INTERVAL = 0.25
local CLAIM_GAP_GRACE = 2.0
local MEMBER_ACTION_SPACING = 1.25
local SHOT_INTERVAL = 3.1
local WS_INTERVAL = 2.0
local HATE_INTERVAL = 30
local STEP_INTERVAL = 30
local DEBUFF_INTERVAL = 75
local GEO_INTERVAL = 120
local BAR_INTERVAL = 90
local EVENT_DEDUPE = 4

local DANGEROUS_MOVES = {
    ['Nullifying Rain']=true,
    Cesspool=true,
    Noyade=true,
    ['Fetid Eddies']=true,
    ['Clobbering Wave']=true,
}

local DANGEROUS_SPELLS = {
    Silencega=true,
    Dispelga=true,
    Bindga=true,
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
    -- Rancibus can expose an opaque HP value in this battlefield.  Exact
    -- identity and valid_target are the only liveness signals used here.
    return exact_boss(mob) and mob.valid_target == true
end

local function claimed_boss(ctx, mob)
    return live_boss(mob) and ctx.party_claimed(mob) == true
end

local function scan_boss(ctx, allow_unclaimed)
    local current = ctx.current_target()
    if claimed_boss(ctx, current)
        or (allow_unclaimed and live_boss(current)
            and (tonumber(current.claim_id) or 0) == 0)
    then
        return current
    end

    local selected
    for _, mob in pairs(ctx.mob_array() or {}) do
        if claimed_boss(ctx, mob)
            or (allow_unclaimed and live_boss(mob)
                and (tonumber(mob.claim_id) or 0) == 0)
        then
            if not selected or mob.id < selected.id then selected = mob end
        end
    end
    return selected
end

local function clear(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.last_seen = nil
    self.claim_seen = false
    self.combat_forced = false
    self.dolo_engaged = false
    self.next_member_action = {}
    self.next_shot = 0
    self.next_dolo_ws = 0
    self.next_tackle_ws = 0
    self.next_kick_ws = 0
    self.next_flash = 0
    self.next_provoke = 0
    self.next_step = 0
    self.next_debuff = 0
    self.next_geo = 0
    self.next_bar = 0
    self.last_event = {}
    self.tasks = {}
    self.task_serial = 0
end

local function task_key(recipient, semantic, family)
    return table.concat({family or 'task', recipient, semantic}, ':')
end

local function schedule(self, recipient, semantic, at, family, priority,
    token)
    self.task_serial = self.task_serial + 1
    local key = task_key(recipient, semantic, family)
    self.tasks[key] = {
        key=key, recipient=recipient, semantic=semantic,
        at=at, priority=priority or 10, token=token,
        serial=self.task_serial,
    }
end

local function request(self, ctx, recipient, semantic, token)
    -- Acceptance is deliberately ignored.  The request is one best-effort
    -- attempt, and every other recipient/lane continues in the same tick.
    ctx.actions.party_adapter(recipient, semantic, self.encounter_id, token)
    self.next_member_action[recipient] = ctx.now() + MEMBER_ACTION_SPACING
end

local function run_tasks(self, ctx, now)
    local due = {}
    for _, task in pairs(self.tasks) do
        if now >= task.at then due[#due + 1] = task end
    end
    table.sort(due, function(left, right)
        if left.priority ~= right.priority then
            return left.priority > right.priority
        end
        return left.serial < right.serial
    end)
    for _, task in ipairs(due) do
        if now >= (self.next_member_action[task.recipient] or 0) then
            request(self, ctx, task.recipient, task.semantic, task.token)
            self.tasks[task.key] = nil
        end
    end
end

local function cancel_requests(self, ctx)
    if not self.encounter_id then return end
    for _, name in ipairs({DOLO,TACKLE,KICK,BARNEY,SMALLS,ACHOO}) do
        ctx.actions.party_adapter(name, 'cancel', self.encounter_id)
    end
end

local function finish(self, ctx)
    local id = self.encounter_id
    if not id then return end
    cancel_requests(self, ctx)
    ctx.actions.combat_stop()
    ctx.release_encounter(id)
    clear(self)
end

local function bind(self, ctx, boss, now)
    clear(self)
    self.encounter_id = boss.id
    self.encounter_index = boss.index
    self.last_seen = now
    self.claim_seen = ctx.party_claimed(boss) == true

    -- Encounter authorization is routing metadata only.  Its result cannot
    -- delay or disable any action lane.
    ctx.authorize_encounter(boss.id)

    -- Preparation is concurrent and one-shot.  The pull does not wait for it.
    schedule(self, TACKLE, 'crusade', now, 'prepare-crusade', 20)
    schedule(self, KICK, 'no-foot-rise', now, 'prepare-nfr', 20)
    schedule(self, BARNEY, 'barwatera-prepare', now,
        'prepare-barwater', 20)
    schedule(self, TACKLE, 'sentinel', now + 1.25,
        'prepare-sentinel', 20)
    schedule(self, BARNEY, 'barsilencera-prepare', now + 1.25,
        'prepare-barsilence', 20)
    -- Flash is exactly one best-effort pull request.  Nothing waits for it,
    -- and there is no alarm/retry loop if it misses.
    schedule(self, TACKLE, 'flash', now + 2.5, 'pull-flash', 30)
end

local function resolved_boss(self, ctx, now)
    local boss = ctx.mob_by_id(self.encounter_id)
    if exact_boss(boss) and boss.id == self.encounter_id
        and boss.index == self.encounter_index and live_boss(boss)
    then
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
        finish(self, ctx)
    end
    return nil
end

local function action_name(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = ctx.monster_ability(result.param)
                    or ctx.job_ability(result.param)
                if ability then return ability.en end
            end
        end
    elseif action.category == 8 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local spell = ctx.spell and ctx.spell(result.param) or nil
                if spell then return spell.en end
            end
        end
    elseif action.category == 11 then
        local ability = ctx.monster_ability(action.param)
            or ctx.job_ability(action.param)
        if ability then return ability.en end
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

local function schedule_stuns(self, now, family)
    schedule(self, KICK, 'stun', now, family..'-dnc', 100)
    schedule(self, TACKLE, 'shield-bash', now, family..'-pld', 100)
end

local function schedule_debuffs(self, now, family)
    schedule(self, SMALLS, 'dia3', now, family..'-dia', 35)
    schedule(self, SMALLS, 'addle2', now + 1.25, family..'-addle', 35)
    schedule(self, SMALLS, 'slow2', now + 2.5, family..'-slow', 35)
    schedule(self, SMALLS, 'paralyze2', now + 3.75,
        family..'-paralyze', 35)
end

local function start_claimed_lanes(self, ctx, boss, now)
    if not self.combat_forced then
        -- The profile limits PartyCombat to Tackle and Kick.  Dolo receives
        -- one local engage only, with no persistent PartyCombat target owner.
        ctx.actions.combat_force(boss.id, BOSS)
        self.combat_forced = true
    end
    if not self.dolo_engaged then
        if ctx.client and type(ctx.client.engage_once) == 'function' then
            ctx.client.engage_once(boss.id)
        end
        self.dolo_engaged = true
    end
    if self.next_flash == 0 then
        -- The pull already received its one Flash request.  Normal hate
        -- maintenance begins on its ordinary interval, not as a retry loop.
        self.next_flash = now + HATE_INTERVAL
        self.next_provoke = now + 1.25
        self.next_step = now
        self.next_debuff = now
        self.next_geo = now
        self.next_bar = now + BAR_INTERVAL
        self.next_shot = now
        self.next_dolo_ws = now
        self.next_tackle_ws = now
        self.next_kick_ws = now
    end
end

local function run_claimed_lanes(self, ctx, boss, now)
    start_claimed_lanes(self, ctx, boss, now)

    -- Each TP spender is independent.  There is no skillchain transaction and
    -- no party-health, Flash, support, or action-result gate.
    if now >= self.next_tackle_ws
        and (tonumber(ctx.party_tp(TACKLE)) or 0) >= 1000
        and now >= (self.next_member_action[TACKLE] or 0)
    then
        request(self, ctx, TACKLE, 'middle')
        self.next_tackle_ws = now + WS_INTERVAL
    end
    if now >= self.next_kick_ws
        and (tonumber(ctx.party_tp(KICK)) or 0) >= 1000
        and now >= (self.next_member_action[KICK] or 0)
    then
        request(self, ctx, KICK, 'lead')
        self.next_kick_ws = now + WS_INTERVAL
    end

    if now >= (self.next_member_action[DOLO] or 0) then
        if (tonumber(ctx.party_tp(DOLO)) or 0) >= 1000
            and now >= self.next_dolo_ws
        then
            request(self, ctx, DOLO, 'close')
            self.next_dolo_ws = now + WS_INTERVAL
        elseif now >= self.next_shot then
            request(self, ctx, DOLO, 'shoot')
            self.next_shot = now + SHOT_INTERVAL
        end
    end

    if now >= self.next_flash
        and now >= (self.next_member_action[TACKLE] or 0)
    then
        request(self, ctx, TACKLE, 'flash')
        self.next_flash = now + HATE_INTERVAL
    end
    if now >= self.next_provoke
        and now >= (self.next_member_action[TACKLE] or 0)
    then
        request(self, ctx, TACKLE, 'provoke')
        self.next_provoke = now + HATE_INTERVAL
    end
    if now >= self.next_step
        and now >= (self.next_member_action[KICK] or 0)
    then
        request(self, ctx, KICK, 'box-step')
        self.next_step = now + STEP_INTERVAL
    end
    if now >= self.next_geo
        and now >= (self.next_member_action[ACHOO] or 0)
    then
        request(self, ctx, ACHOO, 'geo-frailty')
        self.next_geo = now + GEO_INTERVAL
    end
    if now >= self.next_debuff then
        schedule_debuffs(self, now, 'debuff-'..tostring(now))
        self.next_debuff = now + DEBUFF_INTERVAL
    end
    if now >= self.next_bar then
        schedule(self, BARNEY, 'barwatera-recover', now,
            'bar-'..tostring(now)..'-water', 25)
        schedule(self, BARNEY, 'barsilencera-recover', now + 1.25,
            'bar-'..tostring(now)..'-silence', 25)
        self.next_bar = now + BAR_INTERVAL
    end
end

function M.create()
    local self = {active=false, next_poll=0}
    clear(self)

    function self:on_activate(ctx)
        self.active = true
        self.next_poll = 0
        clear(self)
    end

    function self:on_deactivate(ctx)
        if ctx.player_name() == DOLO then
            if self.encounter_id then
                finish(self, ctx)
            else
                ctx.actions.combat_stop()
            end
        end
        clear(self)
        self.active = false
    end

    function self:on_action(ctx, action)
        if not self.active or ctx.player_name() ~= DOLO
            or ctx.zone_id() ~= ZONE
            or ctx.operator_armed() ~= true
            or not self.encounter_id
            or tonumber(action and action.actor_id) ~= self.encounter_id
        then
            return
        end
        local now = ctx.now()
        local name = action_name(ctx, action)
        if not name or not event_once(self, name, now) then return end

        if DANGEROUS_MOVES[name] or DANGEROUS_SPELLS[name]
            or name:match('ga$') or name:match('ja$')
        then
            schedule_stuns(self, now, 'danger-'..name)
        end
        if name == 'Manafont' then
            schedule(self, TACKLE, 'rampart', now,
                'manafont-rampart', 90)
        elseif name == 'Nullifying Rain' then
            schedule(self, BARNEY, 'barwatera-recover', now,
                'rain-barwater', 80)
            schedule(self, BARNEY, 'barsilencera-recover', now + 1.25,
                'rain-barsilence', 80)
            schedule_debuffs(self, now, 'rain-debuff')
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
            if self.encounter_id then finish(self, ctx) end
            return
        end

        -- This is the only automation start/stop condition.  There are no
        -- readiness or controller gates behind it.
        if ctx.operator_armed() ~= true then
            if self.encounter_id then finish(self, ctx) end
            return
        end

        local boss
        if self.encounter_id then
            boss = resolved_boss(self, ctx, now)
            if not self.encounter_id then return end
        else
            boss = scan_boss(ctx, true)
            if boss then bind(self, ctx, boss, now) end
        end
        if not boss then return end

        run_tasks(self, ctx, now)

        if claimed_boss(ctx, boss) then
            self.claim_seen = true
            run_claimed_lanes(self, ctx, boss, now)
            -- Tasks scheduled above can run immediately when their recipient
            -- is free; a blocked recipient cannot suppress another one.
            run_tasks(self, ctx, now)
        end
    end

    return self
end

return M
