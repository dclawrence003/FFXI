local M = {}

local BOSS = 'Alluttu'
local ZONES = {[183]=true, [287]=true}
local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'

local QUEUE_MEMBERS = {DOLO, TACKLE, KICK, BARNEY, SMALLS, ACHOO}
local OFFENSE_MEMBERS = {DOLO, TACKLE, KICK, SMALLS, ACHOO}
local FOOD_MEMBERS = {DOLO, TACKLE, KICK}

local POLL_INTERVAL = 0.20
local ENTITY_GAP_GRACE = 2
local FOREIGN_CLAIM_GRACE = 2
local PREP_MIN_SECONDS = 10
local PREP_MAX_SECONDS = 24
local REQUEST_RETRY = 0.75
local MAX_REQUESTS = 3
local FORCE_RETRY = 1.0
local MAX_FORCE_REQUESTS = 3
local FOOD_HEARTBEAT_SECONDS = 5
local MIN_PARTY_HPP = 85
local MIN_CHAIN_TP = 1000
local MIN_SC_DELAY = 3.1
local MAX_SC_DELAY = 8.0
local MB_WINDOW = 9.0
local SHIELD_HOLD_SECONDS = 65
local STUN_FALLBACK_DELAY = 0.70
local STUN_WINDOW = 3.0
local HATE_INTERVAL = 18
local BOX_INTERVAL = 45
local BOX_ATTEMPT_WINDOW = 5
local BOX_RETRY_BACKOFF = 20
local PLD_STEP_TIMEOUT = 4
local PULL_RETRY_BACKOFF = 3
local GEO_RETRY_BACKOFF = 5
local MAINTENANCE_WINDOW = 12
local MAINTENANCE_RETRY = 60
local GEO_REFRESH_SECONDS = 180
local BARPARA_REFRESH_SECONDS = 480
local CRUSADE_REFRESH_SECONDS = 300

local SPELL = {
    Barparalyzra=88,
    Flash=112,
    ThunderIV=167,
    MinuetIV=397,
    Crusade=476,
    GeoFrailty=818,
}
local WS = {Evisceration=25, SavageBlade=42, LastStand=221}
local JA = {
    Provoke=35,
    ShieldBash=46,
    Sentinel=48,
    BoxStep=202,
    ViolentFlourish=207,
    DivineEmblem=255,
    ClarionCall=332,
}
local MOVE = {
    PyricBlast=1828,
    PyricBulwark=1829,
    PolarBlast=1830,
    PolarBulwark=1831,
    Barofield=1832,
    Trembling=1834,
    SerpentineTail=1835,
    NerveGas=1836,
}

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

local PLD_PREP = {
    {semantic='crusade', category=4, id=SPELL.Crusade, self_target=true},
    {semantic='divine-emblem', category=6, id=JA.DivineEmblem,
        self_target=true},
    {semantic='sentinel', category=6, id=JA.Sentinel, self_target=true},
}

local function exact_boss(mob)
    return type(mob) == 'table'
        and mob.name == BOSS
        and mob.spawn_type == 16
        and type(mob.id) == 'number'
        and mob.id >= 1 and mob.id <= 4294967295
        and mob.id == math.floor(mob.id)
        and type(mob.index) == 'number'
        and mob.index >= 0 and mob.index <= 65535
        and mob.index == math.floor(mob.index)
end

local function live_boss(mob)
    return exact_boss(mob) and mob.valid_target
        and (tonumber(mob.hpp) or 0) > 0
end

local function claim_state(ctx, mob)
    if ctx.party_claimed(mob) then return 'party' end
    local claim = tonumber(mob and mob.claim_id)
    if claim and claim >= 1 and claim <= 4294967295
        and claim == math.floor(claim)
    then
        return 'foreign'
    end
    return 'unclaimed'
end

local function target_result(action, target_id)
    for _, target in ipairs(action and action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id) then
            return target.actions and target.actions[1] or nil
        end
    end
    return nil
end

local function successful(result)
    if type(result) ~= 'table' then return false end
    local message = tonumber(result.message)
    return message == nil or not FAILURE_MESSAGES[message]
end

local function positive(action, target_id)
    local result = target_result(action, target_id)
    return successful(result) and (tonumber(result.param) or 0) > 0
end

local function party_aoe_covered(ctx, action)
    local covered = {}
    for _, target in ipairs(action and action.targets or {}) do
        local result = target.actions and target.actions[1] or nil
        if successful(result) then
            local id = tonumber(target.id)
            local mob = id and ctx.mob_by_id(id) or nil
            if mob and mob.name then covered[mob.name] = true end
        end
    end
    for _, name in ipairs(QUEUE_MEMBERS) do
        if not covered[name] then return false end
    end
    return true
end

local function skillchain(action, target_id, message_id)
    local result = target_result(action, target_id)
    return successful(result)
        and tonumber(result.add_effect_message) == message_id
        and (tonumber(result.add_effect_param) or 0) > 0
end

local function actor(ctx, action)
    return type(action) == 'table' and ctx.mob_by_id(action.actor_id) or nil
end

-- Monster actions are deliberately recognized only by the installed numeric
-- resource IDs. Localized names and stale wiki spelling cannot trigger a
-- barrier transition.
local function monster_move(action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local id = tonumber(result.param)
                if id and id >= 1828 and id <= 1836 then
                    return id, 'ready'
                end
            end
        end
    elseif action.category == 6 or action.category == 11 then
        local id = tonumber(action.param)
        if id and id >= 1828 and id <= 1836 then
            return id, 'complete'
        end
    end
    return nil
end

local function scan_boss(self, ctx)
    local bound, candidate
    for _, mob in pairs(ctx.mob_array() or {}) do
        if live_boss(mob) and claim_state(ctx, mob) ~= 'foreign' then
            if self.encounter_id and mob.id == self.encounter_id then
                bound = mob
            elseif not candidate or mob.id < candidate.id then
                candidate = mob
            end
        end
    end
    return bound or candidate
end

local function queue(ctx, member, semantic, target_id, token)
    return ctx.actions.party_adapter(
        member, semantic, target_id, token)
end

local function cancel_members(ctx, members, target_id)
    if not target_id then return end
    for _, member in ipairs(members) do
        queue(ctx, member, 'cancel', target_id)
    end
end

local function party_healthy(ctx, floor)
    local observed = tonumber(ctx.party_hpp_floor())
    return observed ~= nil and observed >= (floor or MIN_PARTY_HPP)
end

local function clear_chain(self, now, cooldown)
    self.chain_stage = 'idle'
    self.lead_at = nil
    self.middle_at = nil
    self.chain_requests = {lead=0, middle=0, close=0}
    self.next_chain_request = 0
    self.burst_requests = {[SMALLS]=0, [ACHOO]=0}
    self.next_burst_request = {[SMALLS]=0, [ACHOO]=0}
    self.burst_done = {[SMALLS]=false, [ACHOO]=false}
    self.mb_until = nil
    self.next_chain_at = math.max(self.next_chain_at or 0,
        (now or 0) + (cooldown or 0))
end

local function clear_encounter(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.encounter_seen_at = nil
    self.encounter_started_at = nil
    self.foreign_claim_at = nil
    self.ready_last = false
    self.prep_started_at = nil
    self.food_requests = {[DOLO]=0, [TACKLE]=0, [KICK]=0}
    self.next_food_request = {[DOLO]=0, [TACKLE]=0, [KICK]=0}
    self.clarion_done = false
    self.fourth_song_done = false
    self.barpara_done = false
    self.brd_requests = {clarion=0, song=0, bar=0}
    self.next_brd_request = 0
    self.pld_step = 1
    self.pld_requests = 0
    self.next_pld_request = 0
    self.pld_step_started_at = nil
    self.pull_flash_done = false
    self.force_requests = 0
    self.next_force_request = 0
    self.force_done = false
    self.geo_done = false
    self.geo_requests = 0
    self.next_geo_request = 0
    self.box_opening_complete = false
    self.box_cycle_active = false
    self.box_cycle_until = 0
    self.box_requests = 0
    self.next_box_request = 0
    self.next_box_at = 0
    self.next_hate_at = 0
    self.hate_toggle = false
    self.physical_until = 0
    self.magic_until = 0
    self.combat_suspended = false
    self.recovery_until = 0
    self.maintenance = nil
    self.next_maintenance_retry = 0
    self.geo_refresh_at = 0
    self.barpara_refresh_at = 0
    self.crusade_refresh_at = 0
    self.stun = nil
    self.nuke_requests = {[SMALLS]=0, [ACHOO]=0}
    self.next_nuke_request = {[SMALLS]=0, [ACHOO]=0}
    self.last_mechanic = {}
    self.next_chain_at = 0
    clear_chain(self, 0, 0)
end

local function alert(self, ctx, key, message, audible, cooldown)
    local now = ctx.now()
    if now - (self.last_alert[key] or -100000) < (cooldown or 6) then
        return
    end
    self.last_alert[key] = now
    ctx.alert(message, audible == true)
end

local function begin_encounter(self, ctx, boss, now)
    if self.arm_consumed or ctx.operator_armed() ~= true
        or not ctx.combat_ready()
        or not ctx.authorize_encounter(boss.id)
    then
        return false
    end
    self.arm_consumed = true
    clear_encounter(self)
    self.encounter_id = boss.id
    self.encounter_index = boss.index
    self.encounter_seen_at = now
    self.encounter_started_at = now
    self.prep_started_at = now
    alert(self, ctx, 'bound',
        'ALLUTTU BOUND: automatic food, song, PLD pull, and fight sequence started.',
        false, 3)
    return true
end

local function end_encounter(self, ctx)
    local id = self.encounter_id
    if id then
        cancel_members(ctx, QUEUE_MEMBERS, id)
        ctx.actions.combat_stop()
        ctx.release_encounter(id)
    end
    clear_encounter(self)
end

local function resolve_encounter(self, ctx, now)
    local boss = ctx.mob_by_id(self.encounter_id)
    if not boss then
        if now - (self.encounter_seen_at or now) > ENTITY_GAP_GRACE then
            end_encounter(self, ctx)
        end
        return nil
    end
    if not exact_boss(boss) or boss.id ~= self.encounter_id
        or boss.index ~= self.encounter_index or not boss.valid_target
        or (tonumber(boss.hpp) or 0) <= 0
    then
        end_encounter(self, ctx)
        return nil
    end
    self.encounter_seen_at = now
    if claim_state(ctx, boss) == 'foreign' then
        self.foreign_claim_at = self.foreign_claim_at or now
        cancel_members(ctx, QUEUE_MEMBERS, self.encounter_id)
        ctx.actions.combat_stop()
        if now - self.foreign_claim_at >= FOREIGN_CLAIM_GRACE then
            end_encounter(self, ctx)
        end
        return nil
    end
    self.foreign_claim_at = nil
    return boss
end

local function setup_ready(self)
    return self.pull_flash_done and self.force_done and self.geo_done
        and self.box_opening_complete
end

local function advance_pld_step(self, now)
    self.pld_step = self.pld_step + 1
    self.pld_requests = 0
    self.pld_step_started_at = nil
    self.next_pld_request = (now or 0) + 0.2
end

local function abort_chain(self, ctx, now, reason)
    cancel_members(ctx, OFFENSE_MEMBERS, self.encounter_id)
    clear_chain(self, now, 2)
    alert(self, ctx, 'chain-'..reason,
        'HYDRA CHAIN RESET: '..reason..'.', false, 3)
end

local function begin_recovery(self, ctx, now, seconds, reason)
    cancel_members(ctx, OFFENSE_MEMBERS, self.encounter_id)
    clear_chain(self, now, 2)
    self.recovery_until = math.max(self.recovery_until or 0,
        now + seconds)
    alert(self, ctx, 'recover-'..reason,
        'RECOVERY PRIORITY: '..reason..'; offense is yielding to cures and status removal.',
        false, 3)
end

local function request_maintenance(self, now, reason, flags, block_offense)
    local maintenance = self.maintenance
    if not maintenance then
        maintenance = {
            reason=reason,
            requested_at=now,
            started_at=nil,
            need={geo=false, bar=false, crusade=false},
            done={geo=false, bar=false, crusade=false},
            requests={geo=0, bar=0, crusade=0},
            next_request={geo=0, bar=0, crusade=0},
            block_offense=block_offense ~= false,
        }
        self.maintenance = maintenance
    elseif block_offense ~= false then
        maintenance.block_offense = true
    end
    for key, wanted in pairs(flags or {}) do
        if maintenance.need[key] ~= nil and wanted then
            maintenance.need[key] = true
            maintenance.done[key] = false
        end
    end
end

local function schedule_expired_maintenance(self, now)
    if now < (self.next_maintenance_retry or 0) then
        return
    end
    local flags = {
        geo=self.geo_refresh_at > 0 and now >= self.geo_refresh_at,
        bar=self.barpara_refresh_at > 0 and now >= self.barpara_refresh_at,
        crusade=self.crusade_refresh_at > 0 and now >= self.crusade_refresh_at,
    }
    if flags.geo or flags.bar or flags.crusade then
        request_maintenance(self, now, 'scheduled buff refresh', flags)
    end
end

local function maintenance_tick(self, ctx, now, boss)
    local maintenance = self.maintenance
    if not maintenance then return false end
    if not maintenance.started_at then
        maintenance.started_at = now
        if maintenance.block_offense then
            cancel_members(ctx, OFFENSE_MEMBERS, self.encounter_id)
            clear_chain(self, now, 2)
        end
    end

    local bindings = {
        geo={member=ACHOO, semantic='setup'},
        bar={member=BARNEY, semantic='barparalyzra'},
        crusade={member=TACKLE, semantic='crusade'},
    }
    local complete = true
    for _, key in ipairs({'geo','bar','crusade'}) do
        if maintenance.need[key] and not maintenance.done[key] then
            complete = false
            if maintenance.requests[key] < MAX_REQUESTS
                and now >= maintenance.next_request[key]
            then
                maintenance.requests[key] = maintenance.requests[key] + 1
                maintenance.next_request[key] = now + 1.5
                local binding = bindings[key]
                queue(ctx, binding.member, binding.semantic, boss.id,
                    'refresh-'..key)
            end
        end
    end
    if complete then
        self.maintenance = nil
        return false
    end

    if now - maintenance.started_at < MAINTENANCE_WINDOW then
        return maintenance.block_offense
    end

    local members = {}
    for _, key in ipairs({'geo','bar','crusade'}) do
        if maintenance.need[key] and not maintenance.done[key] then
            members[#members + 1] = bindings[key].member
            if key == 'geo' then
                self.geo_refresh_at = now + MAINTENANCE_RETRY
            elseif key == 'bar' then
                self.barpara_refresh_at = self.barpara_done
                    and now + MAINTENANCE_RETRY or 0
            else
                self.crusade_refresh_at = now + MAINTENANCE_RETRY
            end
        end
    end
    cancel_members(ctx, members, boss.id)
    alert(self, ctx, 'maintenance-timeout',
        'REBUFF WINDOW EXPIRED: unresolved '..maintenance.reason
            ..' actions were cancelled; offense resumes and retries in 60 seconds.',
        true, 10)
    self.next_maintenance_retry = now + MAINTENANCE_RETRY
    self.maintenance = nil
    return false
end

local function suspend_physical(self, ctx, now)
    cancel_members(ctx, {DOLO, TACKLE, KICK}, self.encounter_id)
    clear_chain(self, now, 2)
    self.physical_until = now + SHIELD_HOLD_SECONDS
    self.magic_until = 0
    self.nuke_requests = {[SMALLS]=0, [ACHOO]=0}
    self.next_nuke_request = {[SMALLS]=now, [ACHOO]=now + 0.4}
    if not self.combat_suspended then
        ctx.actions.combat_stop()
        self.combat_suspended = true
    end
    alert(self, ctx, 'polar-active',
        'POLAR BULWARK COMPLETED: melee stopped; exact Thunder IV fallback active for 65 seconds.',
        false, 3)
end

local function suppress_magic(self, ctx, now)
    cancel_members(ctx, {SMALLS, ACHOO}, self.encounter_id)
    self.magic_until = now + SHIELD_HOLD_SECONDS
    self.physical_until = 0
    self.nuke_requests = {[SMALLS]=0, [ACHOO]=0}
    if self.chain_stage == 'burst' then clear_chain(self, now, 1) end
    if self.combat_suspended then
        ctx.actions.combat_force(self.encounter_id)
        self.combat_suspended = false
    end
    alert(self, ctx, 'pyric-active',
        'PYRIC BULWARK COMPLETED: magic suppressed; physical Light chains active.',
        false, 3)
end

local function arm_stun(self, ctx, now, move_id)
    -- The ready packet is a transaction barrier. Retire every possible
    -- physical closer and magic-burst reservation before either stun is
    -- allowed to race the monster action.
    cancel_members(ctx, OFFENSE_MEMBERS, self.encounter_id)
    clear_chain(self, now, 1.5)
    self.stun = {
        move_id=move_id,
        started_at=now,
        dnc_requests=0,
        next_dnc_request=now,
        bash_requests=0,
        next_bash_request=now + STUN_FALLBACK_DELAY,
    }
    alert(self, ctx, 'stun-'..tostring(move_id),
        move_id == MOVE.NerveGas
            and 'NERVE GAS READY: Violent Flourish queued; Shield Bash armed.'
            or 'POLAR BULWARK READY: Violent Flourish queued; Shield Bash armed.',
        false, 2)
end

local function prep_tick(self, ctx, now, boss)
    local elapsed = now - self.prep_started_at

    for _, member in ipairs(FOOD_MEMBERS) do
        if now >= self.next_food_request[member] then
            self.food_requests[member] = self.food_requests[member]
                % MAX_REQUESTS + 1
            self.next_food_request[member] = now + FOOD_HEARTBEAT_SECONDS
            queue(ctx, member, 'food', boss.id,
                'food-heartbeat-'..tostring(self.food_requests[member]))
        end
    end

    if not self.clarion_done and elapsed <= 5 then
        if self.brd_requests.clarion < MAX_REQUESTS
            and now >= self.next_brd_request
        then
            self.brd_requests.clarion = self.brd_requests.clarion + 1
            self.next_brd_request = now + REQUEST_RETRY
            queue(ctx, BARNEY, 'clarion', boss.id, 'clarion')
        end
    elseif not self.fourth_song_done and elapsed <= 13 then
        if self.brd_requests.song < MAX_REQUESTS
            and now >= self.next_brd_request
        then
            self.brd_requests.song = self.brd_requests.song + 1
            self.next_brd_request = now + 1.5
            queue(ctx, BARNEY, 'fourth-song', boss.id, 'minuet4')
        end
    elseif not self.barpara_done and elapsed <= 20 then
        if self.brd_requests.bar < MAX_REQUESTS
            and now >= self.next_brd_request
        then
            self.brd_requests.bar = self.brd_requests.bar + 1
            self.next_brd_request = now + 1.5
            queue(ctx, BARNEY, 'barparalyzra', boss.id, 'barpara')
        end
    end

    local step = PLD_PREP[self.pld_step]
    if step and elapsed >= 4 then
        self.pld_step_started_at = self.pld_step_started_at or now
        if self.pld_requests < MAX_REQUESTS
            and now >= self.next_pld_request
        then
            self.pld_requests = self.pld_requests + 1
            self.next_pld_request = now + REQUEST_RETRY
            queue(ctx, TACKLE, step.semantic, boss.id,
                'pld-'..tostring(self.pld_step))
        end
        if (self.pld_requests >= MAX_REQUESTS
                and now >= self.next_pld_request)
            or now - self.pld_step_started_at >= PLD_STEP_TIMEOUT
        then
            alert(self, ctx, 'pld-step-exhausted-'..tostring(self.pld_step),
                'OPTIONAL PLD PREP SKIPPED: Tackle did not confirm '
                    ..step.semantic..' before its bounded deadline.',
                true, 100000)
            cancel_members(ctx, {TACKLE}, boss.id)
            advance_pld_step(self, now)
        end
    end

    if elapsed > 20 and not self.barpara_done and not self.maintenance
        and now >= (self.next_maintenance_retry or 0)
    then
        request_maintenance(self, now,
            'initial Barparalyzra coverage', {bar=true}, false)
    end

    if step or self.pull_flash_done then return end
    if elapsed < PREP_MIN_SECONDS then return end
    if self.pld_requests >= MAX_REQUESTS
        and now >= self.next_pld_request
    then
        alert(self, ctx, 'pull-cycle',
            'PULL STILL HELD: the exact Flash queue exhausted; it was cancelled and will retry after bounded backoff.',
            true, 5)
        cancel_members(ctx, {TACKLE}, boss.id)
        self.pld_requests = 0
        self.next_pld_request = now + PULL_RETRY_BACKOFF
        return
    end
    if self.pld_requests < MAX_REQUESTS and now >= self.next_pld_request then
        self.pld_requests = self.pld_requests + 1
        self.next_pld_request = now + REQUEST_RETRY
        queue(ctx, TACKLE, 'pull-flash', boss.id, 'pull')
    end

    if elapsed >= PREP_MAX_SECONDS and not self.pull_flash_done then
        alert(self, ctx, 'pull-wait',
            'PULL HELD: exact PLD opener has not produced a successful Flash packet.',
            true, 5)
    end

end

local function claimed_setup_tick(self, ctx, now, boss)
    if self.pull_flash_done and not self.force_done
        and now >= self.next_force_request
        and self.force_requests < MAX_FORCE_REQUESTS
    then
        self.force_requests = self.force_requests + 1
        self.next_force_request = now + FORCE_RETRY
        if ctx.actions.combat_force(boss.id) then self.force_done = true end
    end

    if not self.geo_done and self.geo_requests < MAX_REQUESTS
        and now >= self.next_geo_request
    then
        self.geo_requests = self.geo_requests + 1
        self.next_geo_request = now + 1.5
        queue(ctx, ACHOO, 'setup', boss.id, 'frailty')
    end
    if not self.geo_done and self.geo_requests >= MAX_REQUESTS
        and now >= self.next_geo_request
    then
        alert(self, ctx, 'geo-cycle',
            'GEO SETUP HELD: Geo-Frailty queue exhausted; it was cancelled and will retry after bounded backoff.',
            true, 5)
        cancel_members(ctx, {ACHOO}, boss.id)
        self.geo_requests = 0
        self.next_geo_request = now + GEO_RETRY_BACKOFF
    end

    if not self.box_opening_complete then
        if not self.box_cycle_active then
            self.box_cycle_active = true
            self.box_cycle_until = now + BOX_ATTEMPT_WINDOW
            self.box_requests = 0
            self.next_box_request = now
        end
        if now >= self.box_cycle_until then
            cancel_members(ctx, {KICK}, boss.id)
            self.box_cycle_active = false
            self.box_opening_complete = true
            self.next_box_at = now + BOX_RETRY_BACKOFF
            alert(self, ctx, 'opening-box-timeout',
                'OPENING BOX STEP MISSED: its bounded queue was cancelled; combat continues and retries later.',
                false, 10)
        elseif self.box_requests < MAX_REQUESTS
            and now >= self.next_box_request
        then
            self.box_requests = self.box_requests + 1
            self.next_box_request = now + REQUEST_RETRY
            queue(ctx, KICK, 'box-step', boss.id, 'opening-box')
        end
    end
end

local function stun_tick(self, ctx, now, boss)
    local stun = self.stun
    if not stun then return false end
    if now - stun.started_at >= STUN_WINDOW then
        cancel_members(ctx, {KICK, TACKLE}, boss.id)
        self.stun = nil
        return false
    end
    if stun.dnc_requests < MAX_REQUESTS
        and now >= stun.next_dnc_request
    then
        stun.dnc_requests = stun.dnc_requests + 1
        stun.next_dnc_request = now + REQUEST_RETRY
        queue(ctx, KICK, 'stun', boss.id,
            'vf-'..tostring(stun.move_id))
    end
    if now - stun.started_at >= STUN_FALLBACK_DELAY
        and stun.bash_requests < MAX_REQUESTS
        and now >= stun.next_bash_request
    then
        stun.bash_requests = stun.bash_requests + 1
        stun.next_bash_request = now + REQUEST_RETRY
        queue(ctx, TACKLE, 'shield-bash', boss.id,
            'bash-'..tostring(stun.move_id))
    end
    return true
end

local function hate_tick(self, ctx, now, boss)
    if now < self.next_hate_at or self.chain_stage ~= 'idle' then return end
    self.hate_toggle = not self.hate_toggle
    queue(ctx, TACKLE, self.hate_toggle and 'provoke' or 'flash',
        boss.id, self.hate_toggle and 'hate-provoke' or 'hate-flash')
    self.next_hate_at = now + HATE_INTERVAL
end

local function box_tick(self, ctx, now, boss)
    if self.chain_stage ~= 'idle' then return false end
    if not self.box_cycle_active then
        if now < self.next_box_at then return false end
        self.box_cycle_active = true
        self.box_cycle_until = now + BOX_ATTEMPT_WINDOW
        self.box_requests = 0
        self.next_box_request = now
    end
    if now >= self.box_cycle_until then
        cancel_members(ctx, {KICK}, boss.id)
        self.box_cycle_active = false
        self.box_requests = 0
        self.next_box_at = now + BOX_RETRY_BACKOFF
        alert(self, ctx, 'periodic-box-timeout',
            'PERIODIC BOX STEP MISSED: its bounded queue was cancelled; Light chains resume during backoff.',
            false, 10)
        return false
    end
    if self.box_requests < MAX_REQUESTS
        and now >= self.next_box_request
    then
        self.box_requests = self.box_requests + 1
        self.next_box_request = now + REQUEST_RETRY
        queue(ctx, KICK, 'box-step', boss.id, 'periodic-box')
    end
    return true
end

local function nuke_tick(self, ctx, now, boss)
    for _, member in ipairs({SMALLS, ACHOO}) do
        if now >= self.next_nuke_request[member] then
            if self.nuke_requests[member] < MAX_REQUESTS then
                self.nuke_requests[member] = self.nuke_requests[member] + 1
                self.next_nuke_request[member] = now + 1.5
                queue(ctx, member, 'nuke', boss.id,
                    'polar-'..tostring(self.nuke_requests[member]))
            else
                self.nuke_requests[member] = 0
                self.next_nuke_request[member] = now + 12
            end
        end
    end
end

local function chain_tick(self, ctx, now, boss)
    if now < self.next_chain_at or not party_healthy(ctx)
        or self.recovery_until > now or self.stun
    then
        return
    end
    if self.chain_stage == 'idle' then
        if (tonumber(ctx.party_tp(KICK)) or 0) < MIN_CHAIN_TP
            or (tonumber(ctx.party_tp(TACKLE)) or 0) < MIN_CHAIN_TP
            or (tonumber(ctx.party_tp(DOLO)) or 0) < MIN_CHAIN_TP
        then
            return
        end
        self.chain_stage = 'lead_pending'
        self.chain_requests.lead = 0
        self.next_chain_request = now
    end

    if self.chain_stage == 'lead_pending' then
        if self.chain_requests.lead >= MAX_REQUESTS then
            return abort_chain(self, ctx, now, 'Evisceration timed out')
        end
        if now >= self.next_chain_request then
            self.chain_requests.lead = self.chain_requests.lead + 1
            self.next_chain_request = now + REQUEST_RETRY
            queue(ctx, KICK, 'lead', boss.id, 'light-lead')
        end
    elseif self.chain_stage == 'started' then
        local elapsed = now - self.lead_at
        if elapsed > MAX_SC_DELAY then
            return abort_chain(self, ctx, now, 'Savage Blade window expired')
        end
        if elapsed >= MIN_SC_DELAY and now >= self.next_chain_request then
            if self.chain_requests.middle >= MAX_REQUESTS then
                return abort_chain(self, ctx, now, 'Savage Blade timed out')
            end
            self.chain_requests.middle = self.chain_requests.middle + 1
            self.next_chain_request = now + REQUEST_RETRY
            queue(ctx, TACKLE, 'middle', boss.id, 'fragmentation')
        end
    elseif self.chain_stage == 'opened' then
        local elapsed = now - self.middle_at
        if elapsed > MAX_SC_DELAY then
            return abort_chain(self, ctx, now, 'Last Stand window expired')
        end
        if elapsed >= MIN_SC_DELAY and now >= self.next_chain_request then
            if self.chain_requests.close >= MAX_REQUESTS then
                return abort_chain(self, ctx, now, 'Last Stand timed out')
            end
            self.chain_requests.close = self.chain_requests.close + 1
            self.next_chain_request = now + REQUEST_RETRY
            queue(ctx, DOLO, 'close', boss.id, 'light-close')
        end
    elseif self.chain_stage == 'burst' then
        if now >= (self.mb_until or 0) then
            cancel_members(ctx, {SMALLS, ACHOO}, self.encounter_id)
            return clear_chain(self, now, 2)
        end
        for _, member in ipairs({SMALLS, ACHOO}) do
            if not self.burst_done[member]
                and self.burst_requests[member] < MAX_REQUESTS
                and now >= self.next_burst_request[member]
            then
                self.burst_requests[member] = self.burst_requests[member] + 1
                self.next_burst_request[member] = now + 1.5
                queue(ctx, member, 'burst', boss.id, 'light-burst')
            end
        end
        if self.burst_done[SMALLS] and self.burst_done[ACHOO] then
            clear_chain(self, now, 2)
        end
    end
end

function M.create()
    local self = {
        active=false,
        auto_target_owned=false,
        arm_consumed=false,
        next_poll=0,
        last_alert={},
    }
    clear_encounter(self)

    function self:on_activate(ctx)
        self.active = true
        ctx.client.auto_target(false)
        self.auto_target_owned = true
    end

    function self:on_deactivate(ctx)
        if ctx.player_name() == DOLO and self.encounter_id then
            end_encounter(self, ctx)
        else
            clear_encounter(self)
        end
        self.active = false
        if self.auto_target_owned then
            ctx.client.auto_target(true)
            self.auto_target_owned = false
        end
    end

    function self:on_action(ctx, action)
        if not self.active or ctx.player_name() ~= DOLO
            or type(action) ~= 'table'
        then
            return
        end
        if not ZONES[ctx.zone_id()] then
            if self.encounter_id then end_encounter(self, ctx) end
            return
        end

        if not self.encounter_id then
            if ctx.operator_armed() ~= true then
                self.arm_consumed = false
                return
            end
            local candidate = scan_boss(self, ctx)
            if not candidate or not begin_encounter(
                self, ctx, candidate, ctx.now())
            then
                return
            end
        end
        local now = ctx.now()
        local boss = resolve_encounter(self, ctx, now)
        if not boss then return end
        local action_floor = tonumber(ctx.party_hpp_floor())
        if action_floor and action_floor <= 0 then
            alert(self, ctx, 'party-death',
                'PARTY MEMBER DOWN: all profile queues cancelled and PartyCombat stopped; a fresh //pt arm is required.',
                true, 3)
            end_encounter(self, ctx)
            return
        end
        local source = actor(ctx, action)

        if tonumber(action.actor_id) == self.encounter_id then
            local move_id, phase = monster_move(action)
            if move_id then
                local dedupe = tostring(move_id)..':'..phase
                if now - (self.last_mechanic[dedupe] or -100000) >= 0.5 then
                    self.last_mechanic[dedupe] = now
                    if phase == 'ready'
                        and (move_id == MOVE.NerveGas
                            or move_id == MOVE.PolarBulwark)
                    then
                        arm_stun(self, ctx, now, move_id)
                    elseif phase == 'complete' then
                        if self.stun and self.stun.move_id == move_id then
                            -- Whether the move landed or merely finished after
                            -- a failed stun, its reaction window is over. Retire
                            -- both exact queues before releasing the barrier so
                            -- a delayed Flourish/Bash cannot fire into the next
                            -- action or chain.
                            cancel_members(ctx, {KICK, TACKLE},
                                self.encounter_id)
                            self.stun = nil
                        end
                        if move_id == MOVE.PolarBulwark then
                            suspend_physical(self, ctx, now)
                        elseif move_id == MOVE.PyricBulwark then
                            suppress_magic(self, ctx, now)
                        elseif move_id == MOVE.NerveGas then
                            begin_recovery(self, ctx, now, 12,
                                'Nerve Gas poison and curse')
                        elseif move_id == MOVE.Trembling then
                            begin_recovery(self, ctx, now, 8,
                                'Trembling dispel and damage')
                            request_maintenance(self, now,
                                'Trembling dispel recovery', {
                                    geo=true, bar=true, crusade=true,
                                })
                        elseif move_id == MOVE.PolarBlast then
                            begin_recovery(self, ctx, now, 6,
                                'Polar Blast paralysis')
                        elseif move_id == MOVE.PyricBlast then
                            begin_recovery(self, ctx, now, 6,
                                'Pyric Blast plague')
                        elseif move_id == MOVE.Barofield then
                            begin_recovery(self, ctx, now, 4,
                                'Barofield damage and heavy')
                        elseif move_id == MOVE.SerpentineTail then
                            begin_recovery(self, ctx, now, 5,
                                'Serpentine Tail rear counter')
                            alert(self, ctx, 'rear-warning',
                                'SERPENTINE TAIL OBSERVED: keep all characters out of the rear arc.',
                                true, 3)
                        end
                    end
                end
            end
        end

        if not source then return end
        local result

        if source.name == BARNEY and action.category == 6
            and tonumber(action.param) == JA.ClarionCall
        then
            result = target_result(action, source.id)
            if successful(result) then self.clarion_done = true end
        elseif source.name == BARNEY and action.category == 4
            and tonumber(action.param) == SPELL.MinuetIV
        then
            if party_aoe_covered(ctx, action) then
                self.fourth_song_done = true
            end
        elseif source.name == BARNEY and action.category == 4
            and tonumber(action.param) == SPELL.Barparalyzra
        then
            if party_aoe_covered(ctx, action) then
                self.barpara_done = true
                self.barpara_refresh_at = now + BARPARA_REFRESH_SECONDS
                if self.maintenance and self.maintenance.need.bar then
                    self.maintenance.done.bar = true
                end
            end
        end

        local prep = PLD_PREP[self.pld_step]
        if source.name == TACKLE and prep
            and action.category == prep.category
            and tonumber(action.param) == prep.id
        then
            local wanted = prep.self_target and source.id or self.encounter_id
            if successful(target_result(action, wanted)) then
                advance_pld_step(self, now)
            end
        elseif source.name == TACKLE and action.category == 4
            and tonumber(action.param) == SPELL.Flash
            and successful(target_result(action, self.encounter_id))
            and self.pld_step > #PLD_PREP
        then
            self.pull_flash_done = true
            self.pld_requests = 0
            self.next_hate_at = now + HATE_INTERVAL
        end

        if source.name == ACHOO and action.category == 4
            and tonumber(action.param) == SPELL.GeoFrailty
            and successful(target_result(action, self.encounter_id))
        then
            self.geo_done = true
            self.geo_refresh_at = now + GEO_REFRESH_SECONDS
            if self.maintenance and self.maintenance.need.geo then
                self.maintenance.done.geo = true
            end
        end

        if source.name == TACKLE and action.category == 4
            and tonumber(action.param) == SPELL.Crusade
            and successful(target_result(action, source.id))
        then
            self.crusade_refresh_at = now + CRUSADE_REFRESH_SECONDS
            if self.maintenance and self.maintenance.need.crusade then
                self.maintenance.done.crusade = true
            end
        end

        if source.name == KICK and action.category == 6
            and tonumber(action.param) == JA.BoxStep
            and successful(target_result(action, self.encounter_id))
        then
            self.box_opening_complete = true
            self.box_cycle_active = false
            self.box_cycle_until = 0
            self.box_requests = 0
            self.next_box_at = now + BOX_INTERVAL
        end

        if self.stun and source.name == KICK and action.category == 6
            and tonumber(action.param) == JA.ViolentFlourish
            and successful(target_result(action, self.encounter_id))
        then
            -- A successful JA packet proves execution, not that Stun landed.
            -- Retire only Kick's spent lane and keep Shield Bash armed through
            -- the reaction window.
            cancel_members(ctx, {KICK}, self.encounter_id)
            self.stun.dnc_requests = MAX_REQUESTS
        elseif self.stun and source.name == TACKLE and action.category == 6
            and tonumber(action.param) == JA.ShieldBash
            and successful(target_result(action, self.encounter_id))
        then
            -- Shield Bash is the final fallback. Keep the transaction barrier
            -- until move completion or timeout, but never let its spent queue
            -- fire after combat resumes.
            cancel_members(ctx, {TACKLE}, self.encounter_id)
            self.stun.bash_requests = MAX_REQUESTS
        end

        if action.category == 3
            and target_result(action, self.encounter_id)
        then
            if source.name == KICK and tonumber(action.param) == WS.Evisceration
                and self.chain_stage == 'lead_pending'
            then
                if positive(action, self.encounter_id)
                    and party_healthy(ctx) and self.physical_until <= now
                then
                    self.chain_stage = 'started'
                    self.lead_at = now
                    self.chain_requests.middle = 0
                    self.next_chain_request = now + MIN_SC_DELAY
                else
                    abort_chain(self, ctx, now,
                        'Evisceration was not a safe positive hit')
                end
            elseif source.name == TACKLE
                and tonumber(action.param) == WS.SavageBlade
                and self.chain_stage == 'started'
            then
                local elapsed = now - self.lead_at
                if elapsed >= MIN_SC_DELAY and elapsed <= MAX_SC_DELAY
                    and positive(action, self.encounter_id)
                    and skillchain(action, self.encounter_id, 291)
                    and party_healthy(ctx)
                then
                    self.chain_stage = 'opened'
                    self.middle_at = now
                    self.chain_requests.close = 0
                    self.next_chain_request = now + MIN_SC_DELAY
                else
                    abort_chain(self, ctx, now,
                        'Fragmentation message 291 was not confirmed')
                end
            elseif source.name == DOLO
                and tonumber(action.param) == WS.LastStand
                and self.chain_stage == 'opened'
            then
                local elapsed = now - self.middle_at
                if elapsed >= MIN_SC_DELAY and elapsed <= MAX_SC_DELAY
                    and positive(action, self.encounter_id)
                    and skillchain(action, self.encounter_id, 288)
                    and party_healthy(ctx)
                then
                    if self.magic_until > now then
                        clear_chain(self, now, 1)
                    else
                        self.chain_stage = 'burst'
                        self.mb_until = now + MB_WINDOW
                        self.burst_requests = {[SMALLS]=0, [ACHOO]=0}
                        self.next_burst_request = {
                            [SMALLS]=now, [ACHOO]=now + 0.25,
                        }
                        self.burst_done = {[SMALLS]=false, [ACHOO]=false}
                    end
                else
                    abort_chain(self, ctx, now,
                        'Light message 288 was not confirmed')
                end
            end
        end

        if source and (source.name == SMALLS or source.name == ACHOO)
            and action.category == 4
            and tonumber(action.param) == SPELL.ThunderIV
            and successful(target_result(action, self.encounter_id))
        then
            if self.chain_stage == 'burst' then
                self.burst_done[source.name] = true
            end
            if self.physical_until > now then
                self.nuke_requests[source.name] = 0
                self.next_nuke_request[source.name] = now + 27
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

        if not ZONES[ctx.zone_id()] then
            if self.encounter_id then end_encounter(self, ctx) end
            return
        end

        if ctx.operator_armed() ~= true then
            self.arm_consumed = false
            if self.encounter_id then end_encounter(self, ctx) end
            return
        end

        local boss
        if self.encounter_id then
            boss = resolve_encounter(self, ctx, now)
            if not boss then return end
        else
            boss = scan_boss(self, ctx)
            if not boss or not begin_encounter(self, ctx, boss, now) then
                return
            end
        end

        local observed_floor = tonumber(ctx.party_hpp_floor())
        if observed_floor and observed_floor <= 0 then
            alert(self, ctx, 'party-death',
                'PARTY MEMBER DOWN: all profile queues cancelled and PartyCombat stopped; a fresh //pt arm is required.',
                true, 3)
            end_encounter(self, ctx)
            return
        end

        if ctx.encounter_ready(boss.id) ~= true then
            if self.ready_last then
                cancel_members(ctx, QUEUE_MEMBERS, boss.id)
                ctx.actions.combat_stop()
                clear_chain(self, now, 2)
            end
            self.ready_last = false
            return
        end
        self.ready_last = true

        prep_tick(self, ctx, now, boss)
        local claim = claim_state(ctx, boss)
        if claim ~= 'party' then return end
        claimed_setup_tick(self, ctx, now, boss)

        if not setup_ready(self) then
            if now - self.encounter_started_at >= 30 then
                alert(self, ctx, 'setup-wait',
                    'OFFENSE HELD: waiting for force engagement, Geo-Frailty, and opening Box Step.',
                    true, 5)
            end
            return
        end

        if self.physical_until > 0 and now >= self.physical_until then
            cancel_members(ctx, {SMALLS, ACHOO}, boss.id)
            self.physical_until = 0
            self.nuke_requests = {[SMALLS]=0, [ACHOO]=0}
            if self.combat_suspended then
                ctx.actions.combat_force(boss.id)
                self.combat_suspended = false
            end
        end
        if self.magic_until > 0 and now >= self.magic_until then
            self.magic_until = 0
        end

        if stun_tick(self, ctx, now, boss) then return end
        if now < self.recovery_until or not observed_floor
            or observed_floor < MIN_PARTY_HPP
        then
            return
        end


        schedule_expired_maintenance(self, now)
        if maintenance_tick(self, ctx, now, boss) then return end
        hate_tick(self, ctx, now, boss)

        if self.physical_until > now then
            if party_healthy(ctx) then nuke_tick(self, ctx, now, boss) end
            return
        end

        if self.chain_stage == 'idle' and box_tick(self, ctx, now, boss) then
            return
        end
        chain_tick(self, ctx, now, boss)
    end

    return self
end

return M
