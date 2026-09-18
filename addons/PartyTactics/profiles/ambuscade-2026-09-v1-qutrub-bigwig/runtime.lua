local M = {}

local BOSS = 'Bozzetto Bigwig'
local ASTROLOGER = 'Bozzetto Astrologer'
local TORMENTORS = {
    ['Bozzetto Tormentor']=true,
    ['Bozzetto Tormenter']=true,
}
local AMBUSCADE_ZONES = {[183]=true, [287]=true}

local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'
local MEMBERS = {DOLO, TACKLE, KICK, BARNEY, SMALLS, ACHOO}
local ATTACKERS = {DOLO, TACKLE, KICK}
local SUPPORT = {BARNEY, SMALLS, ACHOO}
local LOWHP_CURE = {
    [DOLO]='lowhp-cure', [TACKLE]='lowhp-cure', [KICK]='lowhp-cure',
}

local FOOD_ITEM_ID = 6343
local FOOD_BUFF_ID = 251
local SHADOW_BUFFS = {66, 444, 445, 446}

local POLL_INTERVAL = 0.20
local ENTITY_GAP_GRACE = 2.0
local FOREIGN_CLAIM_GRACE = 2.0
local PULL_CLAIM_TIMEOUT = 20.0
local FORCE_RETRY = 0.75
local FORCE_CYCLE = 3.0
local MAX_FORCE_ATTEMPTS = 3
local SETUP_RETRY = 1.0
local MAX_SETUP_REQUESTS = 4
local FOOD_SETTLE = 5.0
local FOOD_CYCLE_BACKOFF = 15.0
local ADD_EMPTY_SETTLE = 2.0
local SECOND_WAVE_WAIT = 7.0
local FIRST_GUARD_HPP = 84
local FIRST_SPAWN_HPP = 80
local SECOND_GUARD_HPP = 34
local SECOND_SPAWN_HPP = 30
local PERFECT_DODGE_HOLD = 32.0
local MIN_PARTY_HPP = 60
local MIN_CHAIN_TP = 1000
local MIN_CHAIN_DELAY = 3.1
local MAX_CHAIN_DELAY = 8.0
local CHAIN_TIMEOUT = 10.0
local CHAIN_RETRY = 0.75
local MAX_CHAIN_REQUESTS = 3
-- A /SMN lane has the unmodified 60-second Blood Pact: Ward recast.  The
-- two fixed lanes alternate every 31 seconds so the same character is never
-- asked to Mew again before 62 seconds have elapsed.
local MEW_INTERVAL = 31.0
local MEW_REQUEST_RETRY = 1.0
local MEW_CONFIRM_TIMEOUT = 10.0
local MAX_MEW_REQUESTS = 4
local RETREAT_SETTLE = 0.25
local RETREAT_REQUEST_RETRY = 1.0
local RETREAT_CONFIRM_TIMEOUT = 6.0
local MAX_RETREAT_REQUESTS = 3
local PET_RETRY = 5.0
local ADD_FLASH_RETRY = 1.0
local ADD_FLASH_GATE = 4.0
local ADD_FLASH_REFRESH = 18.0
local MAX_ADD_FLASH_REQUESTS = 4
local ADD_FLASH_CYCLE_BACKOFF = 8.0
local SILENCE_RETRY = 2.0
local MAX_ADD_SILENCE_REQUESTS = 3
local SILENCE_REFRESH = 75.0
local SILENCE_CYCLE_BACKOFF = 8.0
local DISPEL_RETRY = 1.5
local MAX_DISPEL_REQUESTS = 3
local DISPEL_CYCLE_BACKOFF = 6.0
local BOSS_SILENCE_RETRY = 6.0
local MAX_BOSS_SILENCE_REQUESTS = 3
local DIAGA_RETRY = 1.5
local MAX_DIAGA_REQUESTS = 3
local DIAGA_CYCLE_BACKOFF = 6.0
local MECHANIC_DEDUPE = 5.0
local SHADOW_RENEW_INTERVAL = 6.0
local SHADOW_ICHI_FALLBACK = 1.5
local WAVE_MITIGATION_RETRY = 1.5
local MAX_WAVE_MITIGATION_REQUESTS = 2
local LOWHP_PHASE_HPP = 30
local LOWHP_ATTACKER_MIN = 13
local LOWHP_ATTACKER_MAX = 25
local LOWHP_SUPPORT_MIN = 60
local LOWHP_SUPPORT_RADIUS = 16
local LOWHP_CURE_RADIUS = 20
local LOWHP_CONTROL_REFRESH = 2.0
local LOWHP_CURE_RETRY = 1.5
local LOWHP_CURE_CYCLE_BACKOFF = 6.0
local MAX_LOWHP_CURE_REQUESTS = 3

local PLD_SETUP = {
    {semantic='crusade', kind='spell', name='Crusade', target='self',
        optional=true},
    {semantic='divine-emblem', kind='ability', name='Divine Emblem',
        target='self', optional=true},
    {semantic='sentinel', kind='ability', name='Sentinel', target='self',
        optional=true},
    {semantic='flash', kind='spell', name='Flash', target='boss'},
}

local WAVE_MITIGATION = {
    {semantic='rampart', name='Rampart'},
    {semantic='palisade', name='Palisade'},
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

local function uint32(value)
    value = tonumber(value)
    return value and value >= 1 and value <= 4294967295
        and value == math.floor(value)
end

local function exact_entity(mob, name)
    return type(mob) == 'table'
        and mob.name == name
        and mob.spawn_type == 16
        and uint32(mob.id)
        and type(mob.index) == 'number'
        and mob.index >= 0 and mob.index <= 65535
        and mob.index == math.floor(mob.index)
end

local function live_boss(mob)
    return exact_entity(mob, BOSS)
        and mob.valid_target == true
        and (tonumber(mob.hpp) or 0) > 0
end

local function add_rank(mob)
    if exact_entity(mob, ASTROLOGER) then return 1 end
    if type(mob) == 'table' and TORMENTORS[mob.name]
        and exact_entity(mob, mob.name)
    then
        return 2
    end
    return nil
end

local function live_add(mob)
    return add_rank(mob) ~= nil
        and mob.valid_target == true
        and (tonumber(mob.hpp) or 0) > 0
end

local function entity_key(mob)
    return mob and (tostring(mob.id)..':'..tostring(mob.index)) or nil
end

local function squared_separation(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table'
        or type(left.x) ~= 'number' or type(left.y) ~= 'number'
        or type(right.x) ~= 'number' or type(right.y) ~= 'number'
    then
        return nil
    end
    local dx, dy = left.x - right.x, left.y - right.y
    return dx * dx + dy * dy
end

local function associated_add(ctx, boss, mob)
    if not live_add(mob) then return false end
    if ctx.party_claimed(mob) then return true end
    local claim = tonumber(mob.claim_id) or 0
    if claim ~= 0 then return false end
    local separation = squared_separation(boss, mob)
    if separation then return separation <= 35 * 35 end
    local boss_distance = tonumber(boss.distance)
    local add_distance = tonumber(mob.distance)
    return boss_distance ~= nil and add_distance ~= nil
        and boss_distance >= 0 and add_distance >= 0
        and boss_distance <= 35 * 35 and add_distance <= 35 * 35
end

local function claimed_or_unclaimed(ctx, mob)
    if ctx.party_claimed(mob) then return true end
    return (tonumber(mob and mob.claim_id) or 0) == 0
end

local function actor(ctx, action)
    return type(action) == 'table' and ctx.mob_by_id(action.actor_id) or nil
end

local function target_result(action, wanted_id)
    for _, target in ipairs(type(action) == 'table' and action.targets or {}) do
        if tonumber(target.id) == tonumber(wanted_id) then
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

local function positive_damage(action, target_id)
    local result = target_result(action, target_id)
    return successful_result(result) and (tonumber(result.param) or 0) > 0
end

local function confirmed_skillchain(action, target_id, message_id)
    local result = target_result(action, target_id)
    return result ~= nil
        and tonumber(result.add_effect_message) == message_id
        and (tonumber(result.add_effect_param) or 0) > 0
end

local function resource_name(resource)
    return type(resource) == 'table'
        and (resource.en or resource.english or resource.name) or nil
end

local function action_name(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 3 then
        return resource_name(ctx.weapon_skill(action.param))
    elseif action.category == 4 then
        return resource_name(ctx.spell(action.param))
    elseif action.category == 6 then
        return resource_name(ctx.job_ability(action.param))
            or resource_name(ctx.monster_ability(action.param))
    elseif action.category == 11 then
        return resource_name(ctx.monster_ability(action.param))
            or resource_name(ctx.job_ability(action.param))
    end
    return nil
end

local function monster_ability_from_action(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = ctx.monster_ability(result.param)
                    or ctx.job_ability(result.param)
                if ability then return resource_name(ability), 'ready' end
            end
        end
    elseif action.category == 6 or action.category == 11 then
        local ability = ctx.monster_ability(action.param)
            or ctx.job_ability(action.param)
        return resource_name(ability), 'complete'
    end
    return nil
end

local function queue_for(ctx, member, semantic, boss_id, token, subject_id)
    return ctx.actions.party_adapter(
        member, semantic, boss_id, token, subject_id)
end

local function cancel_all(ctx, boss_id)
    if not boss_id then return end
    for _, member in ipairs(MEMBERS) do
        queue_for(ctx, member, 'cancel', boss_id)
    end
end

local function clear_chain(self, now, cooldown)
    self.chain_stage = 'idle'
    self.chain_subject_id = nil
    self.chain_subject_index = nil
    self.stage_at = nil
    self.stage_requests = 0
    self.next_stage_request = 0
    self.next_chain_at = math.max(self.next_chain_at or 0,
        (now or 0) + (cooldown or 0))
end

local function clear_encounter(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.encounter_started_at = nil
    self.encounter_seen_at = nil
    self.claim_seen = false
    self.unclaimed_since = nil
    self.foreign_since = nil
    self.pull_confirmed = false
    self.setup_pld = false
    self.setup_pld_step = 1
    self.setup_pld_requests = 0
    self.next_setup_pld = 0
    self.setup_pld_optional_sent = false
    self.setup_pld_optional_until = 0
    self.setup_geo = false
    self.setup_geo_requests = 0
    self.next_setup_geo = 0
    self.food_started_at = nil
    self.food_requests = {}
    self.next_food_request = {}
    self.food_cycle_at = {}
    self.food_seen = {}
    self.shadow_phase = 'ni'
    self.next_shadow_request = 0
    self.shadow_confirmed = {}
    self.pet_requests = {}
    self.next_pet_request = {}
    self.clarion_requested = false
    self.clarion_confirmed = false
    self.fourth_song_requests = 0
    self.next_fourth_song = 0
    self.next_mew_at = 0
    self.mew_lane = 1
    self.mew_pending = nil
    self.retreat_pending = nil
    self.add_silence = {}
    self.add_dispel = {}
    self.add_flash = {}
    self.member_ids = {}
    self.boss_silence_requests = 0
    self.next_boss_silence = 0
    self.boss_silenced = false
    self.boss_shadows = false
    self.diaga_requests = 0
    self.next_diaga = 0
    self.diaga_cycle_at = 0
    self.wave1_seen = false
    self.wave1_done = false
    self.wave2_seen = false
    self.wave2_done = false
    self.current_wave = nil
    self.wave_mitigation_wave = nil
    self.wave_mitigation_step = 0
    self.wave_mitigation_requests = 0
    self.next_wave_mitigation = 0
    self.lowhp_phase = false
    self.next_lowhp_control = 0
    self.lowhp_cures = {}
    self.adds_present = false
    self.add_empty_since = nil
    self.threshold_wait = nil
    self.threshold_wait_since = nil
    self.perfect_dodge_until = 0
    self.last_mechanic = {}
    self.subject_id = nil
    self.subject_index = nil
    self.subject_key = nil
    self.force_attempts = 0
    self.next_force = 0
    self.force_cycle_at = 0
    self.engagement_proven_key = nil
    self.ready_last = false
    clear_chain(self, 0, 0)
end

local function alert_once(self, ctx, key, message, audible, cooldown)
    local now = ctx.now()
    if now - (self.last_alert[key] or -100000) < (cooldown or 6) then
        return
    end
    self.last_alert[key] = now
    ctx.alert(message, audible == true)
end

local function scan_boss(ctx)
    local candidate
    for _, mob in pairs(ctx.mob_array() or {}) do
        if live_boss(mob) and claimed_or_unclaimed(ctx, mob)
            and (not candidate or mob.id < candidate.id)
        then
            candidate = mob
        end
    end
    return candidate
end

local function scan_adds(ctx, boss)
    local adds = {}
    for _, mob in pairs(ctx.mob_array() or {}) do
        if associated_add(ctx, boss, mob) then
            adds[#adds + 1] = mob
        end
    end
    table.sort(adds, function(left, right)
        local left_rank, right_rank = add_rank(left), add_rank(right)
        if left_rank ~= right_rank then return left_rank < right_rank end
        if left.id ~= right.id then return left.id < right.id end
        return left.index < right.index
    end)
    return adds
end

local function begin_encounter(self, ctx, boss, now)
    if not ctx.operator_armed() or self.arm_consumed
        or not ctx.combat_ready() or not ctx.authorize_encounter(boss.id)
    then
        return false
    end
    clear_encounter(self)
    self.encounter_id = boss.id
    self.encounter_index = boss.index
    self.encounter_started_at = now
    self.encounter_seen_at = now
    self.unclaimed_since = now
    self.food_started_at = now
    self.next_mew_at = now + 6
    self.arm_consumed = true
    return true
end

local function end_encounter(self, ctx, reason)
    local boss_id = self.encounter_id
    if boss_id then
        if self.lowhp_phase then
            for _, member in ipairs(MEMBERS) do
                queue_for(ctx, member, 'lowhp-off', boss_id)
            end
        end
        cancel_all(ctx, boss_id)
        ctx.actions.combat_stop()
        ctx.release_encounter(boss_id)
        if reason then
            alert_once(self, ctx, 'end-'..reason,
                'QUTRUB AUTOMATION STOPPED: '..reason..'.',
                reason ~= 'victory', 3)
        end
    end
    clear_encounter(self)
end

local function resolve_boss(self, ctx, now)
    local boss = self.encounter_id and ctx.mob_by_id(self.encounter_id) or nil
    if not boss then
        if now - (self.encounter_seen_at or now) > ENTITY_GAP_GRACE then
            end_encounter(self, ctx, 'authorized Bigwig disappeared')
        else
            cancel_all(ctx, self.encounter_id)
            ctx.actions.combat_stop()
        end
        return nil
    end
    if not live_boss(boss) or boss.index ~= self.encounter_index then
        end_encounter(self, ctx,
            (tonumber(boss.hpp) or 0) <= 0 and 'victory'
                or 'authorized entity changed')
        return nil
    end
    self.encounter_seen_at = now
    if ctx.party_claimed(boss) then
        self.claim_seen = true
        self.unclaimed_since = nil
        self.foreign_since = nil
        return boss, 'party'
    end
    local claim = tonumber(boss.claim_id) or 0
    if claim ~= 0 then
        self.foreign_since = self.foreign_since or now
        cancel_all(ctx, self.encounter_id)
        ctx.actions.combat_stop()
        if now - self.foreign_since >= FOREIGN_CLAIM_GRACE then
            end_encounter(self, ctx, 'foreign claim')
        end
        return nil
    end
    self.foreign_since = nil
    self.unclaimed_since = self.unclaimed_since or now
    if self.claim_seen then
        cancel_all(ctx, self.encounter_id)
        ctx.actions.combat_stop()
        if now - self.unclaimed_since >= ENTITY_GAP_GRACE then
            end_encounter(self, ctx, 'party claim was lost')
        end
        return nil
    end
    if now - self.encounter_started_at >= PULL_CLAIM_TIMEOUT then
        end_encounter(self, ctx, 'automatic Flash did not establish claim')
        return nil
    end
    return boss, 'unclaimed'
end

local function observe_pld_setup(self, ctx, action, source)
    local step = PLD_SETUP[self.setup_pld_step]
    if not step or not source or source.name ~= TACKLE then return end
    local category = step.kind == 'spell' and 4 or 6
    if action.category ~= category or action_name(ctx, action) ~= step.name then
        return
    end
    local target_id = step.target == 'boss' and self.encounter_id or source.id
    if not successful_result(target_result(action, target_id)) then return end
    self.setup_pld_step = self.setup_pld_step + 1
    self.setup_pld_requests = 0
    self.next_setup_pld = ctx.now()
    self.setup_pld_optional_sent = false
    self.setup_pld_optional_until = 0
    if step.semantic == 'flash' then
        self.pull_confirmed = true
        self.setup_pld = true
    end
end

local function food_tick(self, ctx, now)
    for _, member in ipairs(ATTACKERS) do
        local requests = self.food_requests[member] or 0
        if requests >= MAX_SETUP_REQUESTS
            and now >= (self.food_cycle_at[member] or 0)
        then
            requests = 0
            self.food_requests[member] = 0
            self.next_food_request[member] = now
        end
        if requests < MAX_SETUP_REQUESTS
            and now >= (self.next_food_request[member]
                or self.food_started_at or now)
        then
            queue_for(ctx, member, 'food', self.encounter_id)
            requests = requests + 1
            self.food_requests[member] = requests
            self.next_food_request[member] = now + SETUP_RETRY
            if requests >= MAX_SETUP_REQUESTS then
                self.food_cycle_at[member] = now + FOOD_CYCLE_BACKOFF
            end
        end
    end
end

local function shadow_tick(self, ctx, now)
    if self.chain_stage ~= 'idle' or now < self.next_shadow_request then
        return
    end
    local semantic = self.shadow_phase == 'ni'
        and 'shadow-ni' or 'shadow-ichi'
    for _, member in ipairs({DOLO, TACKLE, KICK}) do
        queue_for(ctx, member, semantic, self.encounter_id)
    end
    if self.shadow_phase == 'ni' then
        self.shadow_phase = 'ichi'
        self.next_shadow_request = now + SHADOW_ICHI_FALLBACK
    else
        self.shadow_phase = 'ni'
        self.next_shadow_request = now + SHADOW_RENEW_INTERVAL
    end
end

local function pld_setup_tick(self, ctx, now)
    if self.setup_pld then return end
    if now - (self.food_started_at or now) < 2 then return end
    local step = PLD_SETUP[self.setup_pld_step]
    if not step then
        self.setup_pld = true
        return
    end
    if step.optional and self.setup_pld_optional_sent then
        if now < self.setup_pld_optional_until then return end
        self.setup_pld_step = self.setup_pld_step + 1
        self.setup_pld_requests = 0
        self.setup_pld_optional_sent = false
        self.setup_pld_optional_until = 0
        self.next_setup_pld = now
        return pld_setup_tick(self, ctx, now)
    end
    if now < (self.next_setup_pld or 0) then return end
    if self.setup_pld_requests >= MAX_SETUP_REQUESTS then
        self.setup_pld_requests = 0
        self.next_setup_pld = now + 3
        alert_once(self, ctx, 'pld-setup',
            'PULL HELD: retrying Tackle\'s ordered '..step.name..' step.',
            true, 4)
        return
    end
    queue_for(ctx, TACKLE, step.semantic, self.encounter_id)
    self.setup_pld_requests = self.setup_pld_requests + 1
    self.next_setup_pld = now + SETUP_RETRY
    if step.optional then
        self.setup_pld_optional_sent = true
        self.setup_pld_optional_until = now + 1.5
    end
end

local function geo_setup_tick(self, ctx, now, claim_state)
    if self.setup_geo or claim_state ~= 'party' then return end
    if self.setup_geo_requests >= MAX_SETUP_REQUESTS then
        if now < self.next_setup_geo then return end
        self.setup_geo_requests = 0
        alert_once(self, ctx, 'geo-setup',
            'OFFENSE HELD: retrying exact Geo-Frailty setup.', true, 4)
    end
    if now < (self.next_setup_geo or 0) then return end
    queue_for(ctx, ACHOO, 'setup', self.encounter_id)
    self.setup_geo_requests = self.setup_geo_requests + 1
    self.next_setup_geo = now + SETUP_RETRY
end

local function optional_song_tick(self, ctx, now)
    if not self.clarion_requested then
        queue_for(ctx, BARNEY, 'clarion', self.encounter_id)
        self.clarion_requested = true
    end
    if self.clarion_confirmed and self.fourth_song_requests < 3
        and now >= self.next_fourth_song
    then
        queue_for(ctx, BARNEY, 'fourth-song', self.encounter_id)
        self.fourth_song_requests = self.fourth_song_requests + 1
        self.next_fourth_song = now + SETUP_RETRY
    end
end

local function pet_tick(self, ctx, now)
    -- A luopan occupies Achoo's one pet slot, so the GEO can never also own
    -- Cait Sith.  Keep the two summon lanes on the independent BRD and RDM
    -- clients while GEO continuously owns Frailty.
    for _, member in ipairs({BARNEY, SMALLS}) do
        if now >= (self.next_pet_request[member] or 0) then
            queue_for(ctx, member, 'summon', self.encounter_id)
            self.pet_requests[member] = (self.pet_requests[member] or 0) + 1
            self.next_pet_request[member] = now + PET_RETRY
        end
    end
end

local function mew_tick(self, ctx, now, enemy_count)
    if enemy_count < 3 then
        if self.mew_pending then
            queue_for(ctx, self.mew_pending.member, 'cancel', self.encounter_id)
            self.mew_pending = nil
        end
        return
    end
    -- Barney is first because his queue has no Astrologer Silence/Dispel
    -- responsibility. Smalls is the redundant lane and critical RDM work is
    -- assigned higher priority by the pinned adapter.
    local lanes = {BARNEY, SMALLS}
    if self.mew_pending then
        local pending = self.mew_pending
        if now - pending.started_at >= MEW_CONFIRM_TIMEOUT then
            queue_for(ctx, pending.member, 'cancel', self.encounter_id)
            self.mew_lane = self.mew_lane == 1 and 2 or 1
            self.mew_pending = nil
            self.next_mew_at = now
            alert_once(self, ctx, 'mew-failover',
                'MEW UNCONFIRMED: cancelled the stale lane and failing over to the other Cait Sith.',
                false, 3)
            return
        end
        if pending.requests < MAX_MEW_REQUESTS and now >= pending.next_at then
            queue_for(ctx, pending.member, 'mew', self.encounter_id)
            pending.requests = pending.requests + 1
            pending.next_at = now + MEW_REQUEST_RETRY
        end
        return
    end
    if now < (self.next_mew_at or 0) then return end
    local member = lanes[self.mew_lane]
    self.mew_pending = {
        member=member, started_at=now, requests=1,
        next_at=now + MEW_REQUEST_RETRY,
    }
    queue_for(ctx, member, 'mew', self.encounter_id)
end

local function retreat_tick(self, ctx, now)
    local pending = self.retreat_pending
    if not pending then return end
    -- Retreat is cleanup, never a combat gate.  A missing result abandons
    -- only this follow-up; add targeting, healing, and chains continue.
    if now - pending.started_at >= RETREAT_CONFIRM_TIMEOUT then
        self.retreat_pending = nil
        alert_once(self, ctx, 'retreat-unconfirmed-'..pending.member,
            'PET RETREAT UNCONFIRMED: continuing combat without blocking the active target.',
            false, 3)
        return
    end
    if pending.requests < MAX_RETREAT_REQUESTS
        and now >= pending.next_at
    then
        queue_for(ctx, pending.member, 'retreat', self.encounter_id)
        pending.requests = pending.requests + 1
        pending.next_at = now + RETREAT_REQUEST_RETRY
    end
end

local function member_entity(ctx, name)
    if type(name) ~= 'string' or ctx.party_tp(name) == nil then return nil end
    local candidate
    for _, mob in pairs(ctx.mob_array() or {}) do
        if type(mob) == 'table' and mob.name == name and uint32(mob.id)
            and type(mob.index) == 'number' and mob.index >= 0
            and mob.index <= 65535 and mob.index == math.floor(mob.index)
            and type(mob.hpp) == 'number' and mob.hpp >= 0
            and mob.valid_target == true
        then
            if candidate then return nil end
            candidate = mob
        end
    end
    return candidate
end

local function member_id(ctx, name)
    local mob = member_entity(ctx, name)
    return mob and mob.id or nil
end

local function mew_source_matches(self, ctx, action, source, member)
    if not source then return false end
    if source.name == member then return true end
    if source.name ~= 'Cait Sith' then return false end
    local wanted = self.member_ids[member] or member_id(ctx, member)
    return wanted ~= nil and (tonumber(source.owner_id) == tonumber(wanted)
        or tonumber(source.owner) == tonumber(wanted))
end

local function observe_mew(self, ctx, action, source, now)
    local pending = self.mew_pending
    if not pending or (action.category ~= 6 and action.category ~= 11)
        or not mew_source_matches(self, ctx, action, source, pending.member)
    then
        return false
    end
    local name = resource_name(ctx.monster_ability(action.param))
        or resource_name(ctx.job_ability(action.param))
    if name ~= 'Mewing Lullaby'
        or not successful_result(target_result(action, self.encounter_id))
    then
        return false
    end
    local boss = ctx.mob_by_id(self.encounter_id)
    if not live_boss(boss) or boss.index ~= self.encounter_index then
        return false
    end
    for _, add in ipairs(scan_adds(ctx, boss)) do
        if not successful_result(target_result(action, add.id)) then
            pending.next_at = math.min(pending.next_at or now, now)
            return false
        end
    end
    self.mew_pending = nil
    self.mew_lane = self.mew_lane == 1 and 2 or 1
    self.next_mew_at = now + MEW_INTERVAL
    self.retreat_pending = {
        member=pending.member, started_at=now, requests=0,
        next_at=now + RETREAT_SETTLE,
    }
    return true
end

local function observe_retreat(self, ctx, action, source)
    local pending = self.retreat_pending
    if not pending or action.category ~= 6
        or not mew_source_matches(self, ctx, action, source, pending.member)
        or resource_name(ctx.job_ability(action.param)) ~= 'Retreat'
    then
        return false
    end
    for _, target in ipairs(action.targets or {}) do
        if successful_result(target.actions and target.actions[1]) then
            self.retreat_pending = nil
            return true
        end
    end
    return false
end

local function add_flash_tick(self, ctx, subject, now)
    if subject.name == BOSS then return true end
    local key = entity_key(subject)
    local state = self.add_flash[key]
    if not state then
        state = {
            started_at=now, requests=0, next_at=now, confirmed=false,
            ever_confirmed=false, cycle_at=0,
        }
        self.add_flash[key] = state
    end
    if state.confirmed and now - state.confirmed_at >= ADD_FLASH_REFRESH then
        state.requests = 0
        state.next_at = now
        state.confirmed = false
        state.started_at = now
    end
    if not state.confirmed and state.requests >= MAX_ADD_FLASH_REQUESTS
        and now >= (state.cycle_at or 0)
    then
        state.requests = 0
        state.next_at = now
    end
    if not state.confirmed and state.requests < MAX_ADD_FLASH_REQUESTS
        and now >= state.next_at
    then
        queue_for(ctx, TACKLE, 'flash-add', self.encounter_id,
            nil, subject.id)
        state.requests = state.requests + 1
        state.next_at = now + ADD_FLASH_RETRY
        if state.requests >= MAX_ADD_FLASH_REQUESTS then
            state.cycle_at = now + ADD_FLASH_CYCLE_BACKOFF
        end
    end
    return state.ever_confirmed or state.confirmed
        or now - state.started_at >= ADD_FLASH_GATE
end

local function update_waves(self, ctx, boss, adds, now)
    if #adds > 0 then
        local new_wave = false
        if not self.wave1_seen then
            self.wave1_seen = true
            self.current_wave = 1
            new_wave = true
        elseif self.wave1_done and not self.wave2_seen then
            self.wave2_seen = true
            self.current_wave = 2
            new_wave = true
        end
        if new_wave then
            self.wave_mitigation_wave = self.current_wave
            self.wave_mitigation_step = 1
            self.wave_mitigation_requests = 0
            -- Let exact-subject Flash win Tackle's first action window, then
            -- spend ready long-recast mitigation on the dangerous pack.
            self.next_wave_mitigation = now + WAVE_MITIGATION_RETRY
        end
        self.adds_present = true
        self.add_empty_since = nil
        self.threshold_wait = nil
        self.threshold_wait_since = nil
        return true
    end

    if self.adds_present then
        self.add_empty_since = self.add_empty_since or now
        cancel_all(ctx, self.encounter_id)
        ctx.actions.combat_stop()
        clear_chain(self, now, 1)
        if now - self.add_empty_since < ADD_EMPTY_SETTLE then return true end
        if self.current_wave == 1 then self.wave1_done = true end
        if self.current_wave == 2 then self.wave2_done = true end
        self.current_wave = nil
        self.adds_present = false
        self.add_empty_since = nil
    end

    local hpp = tonumber(boss.hpp) or 100
    local wanted
    if not self.wave1_seen and hpp <= FIRST_SPAWN_HPP then
        wanted = 1
    elseif self.wave1_done and not self.wave2_seen and not self.wave2_done
        and hpp <= SECOND_SPAWN_HPP
    then
        wanted = 2
    end
    if wanted then
        if self.threshold_wait ~= wanted then
            self.threshold_wait = wanted
            self.threshold_wait_since = now
            cancel_all(ctx, self.encounter_id)
            ctx.actions.combat_stop()
            clear_chain(self, now, 1)
        end
        if wanted == 2
            and now - (self.threshold_wait_since or now) >= SECOND_WAVE_WAIT
        then
            -- Very Easy has no second wave. A bounded absence is safer than
            -- deadlocking that difficulty; higher tiers normally expose the
            -- respawn well inside this conservative settle window.
            self.wave2_done = true
            self.threshold_wait = nil
            self.threshold_wait_since = nil
            alert_once(self, ctx, 'no-wave-two',
                'No second add wave appeared during the bounded settle window; resuming exact boss control.',
                false, 3)
            return false
        end
        return true
    end
    self.threshold_wait = nil
    self.threshold_wait_since = nil
    return false
end

local function wave_mitigation_tick(self, ctx, now)
    if not self.current_wave
        or self.wave_mitigation_wave ~= self.current_wave
    then
        return
    end
    local step = WAVE_MITIGATION[self.wave_mitigation_step]
    if not step or now < (self.next_wave_mitigation or 0) then return end
    if self.wave_mitigation_requests >= MAX_WAVE_MITIGATION_REQUESTS then
        self.wave_mitigation_step = self.wave_mitigation_step + 1
        self.wave_mitigation_requests = 0
        self.next_wave_mitigation = now
        return wave_mitigation_tick(self, ctx, now)
    end
    queue_for(ctx, TACKLE, step.semantic, self.encounter_id)
    self.wave_mitigation_requests = self.wave_mitigation_requests + 1
    self.next_wave_mitigation = now + WAVE_MITIGATION_RETRY
end

local function threshold_guard(self, boss)
    local hpp = tonumber(boss.hpp) or 100
    return (not self.wave1_seen and hpp <= FIRST_GUARD_HPP)
        or (self.wave1_done and not self.wave2_seen and not self.wave2_done
            and hpp <= SECOND_GUARD_HPP)
end

local function set_subject(self, ctx, subject, now)
    local key = entity_key(subject)
    if key == self.subject_key then return end
    cancel_all(ctx, self.encounter_id)
    clear_chain(self, now, 1)
    self.subject_id = subject and subject.id or nil
    self.subject_index = subject and subject.index or nil
    self.subject_key = key
    self.engagement_proven_key = nil
    self.force_attempts = 0
    self.next_force = now
    self.force_cycle_at = 0
    -- Stop the prior PartyCombat target before any exact-subject handoff.
    -- This prevents the previous boss/add policy from snapping clients back
    -- while Tackle establishes the next add's initial Flash.
    ctx.actions.combat_stop()
end

local function force_tick(self, ctx, now, subject)
    if self.engagement_proven_key == self.subject_key then return end
    local selected = ctx.current_target()
    if selected and entity_key(selected) == self.subject_key
        and now < (self.next_force or 0)
    then
        return
    end
    if now < (self.next_force or 0) then return end
    if self.force_attempts >= MAX_FORCE_ATTEMPTS then
        if now < (self.force_cycle_at or 0) then return end
        self.force_attempts = 0
    end
    ctx.actions.combat_force(subject.id)
    self.force_attempts = self.force_attempts + 1
    self.next_force = now + FORCE_RETRY
    if self.force_attempts >= MAX_FORCE_ATTEMPTS then
        self.force_cycle_at = now + FORCE_CYCLE
    end
end

local function silence_adds_tick(self, ctx, adds, now)
    for _, mob in ipairs(adds) do
        if mob.name == ASTROLOGER then
            local key = entity_key(mob)
            local state = self.add_silence[key]
            if not state then
                state = {
                    requests=0, next_at=now, done=false,
                    confirmed_at=0, cycle_at=0,
                }
                self.add_silence[key] = state
            end
            if state.done and now - (state.confirmed_at or 0)
                >= SILENCE_REFRESH
            then
                state.done = false
                state.requests = 0
                state.next_at = now
            end
            if not state.done
                and state.requests >= MAX_ADD_SILENCE_REQUESTS
                and now >= (state.cycle_at or 0)
            then
                state.requests = 0
                state.next_at = now
            end
            if not state.done and state.requests < MAX_ADD_SILENCE_REQUESTS
                and now >= state.next_at
            then
                queue_for(ctx, SMALLS, 'silence-add', self.encounter_id,
                    nil, mob.id)
                state.requests = state.requests + 1
                state.next_at = now + SILENCE_RETRY
                if state.requests >= MAX_ADD_SILENCE_REQUESTS then
                    state.cycle_at = now + SILENCE_CYCLE_BACKOFF
                end
                return
            end
        end
    end
end

local function dispel_adds_tick(self, ctx, adds, now)
    for _, mob in ipairs(adds) do
        if mob.name == ASTROLOGER then
            local state = self.add_dispel[entity_key(mob)]
            if state and state.active then
                if state.requests >= MAX_DISPEL_REQUESTS
                    and now >= (state.cycle_at or 0)
                then
                    state.requests = 0
                    state.next_at = now
                end
                if state.requests < MAX_DISPEL_REQUESTS
                    and now >= (state.next_at or 0)
                then
                    queue_for(ctx, SMALLS, 'dispel-ice-spikes',
                        self.encounter_id, nil, mob.id)
                    state.requests = state.requests + 1
                    state.next_at = now + DISPEL_RETRY
                    if state.requests >= MAX_DISPEL_REQUESTS then
                        state.cycle_at = now + DISPEL_CYCLE_BACKOFF
                    end
                    return
                end
            end
        end
    end
end

local function boss_magic_tick(self, ctx, boss, adds, now)
    if #adds > 0 or self.threshold_wait then return end
    if self.boss_shadows then
        if self.diaga_requests >= MAX_DIAGA_REQUESTS then
            if now < (self.diaga_cycle_at or 0) then return end
            self.diaga_requests = 0
            self.next_diaga = now
        end
        if now >= self.next_diaga then
            queue_for(ctx, SMALLS, 'diaga', self.encounter_id,
                nil, boss.id)
            self.diaga_requests = self.diaga_requests + 1
            self.next_diaga = now + DIAGA_RETRY
            if self.diaga_requests >= MAX_DIAGA_REQUESTS then
                self.diaga_cycle_at = now + DIAGA_CYCLE_BACKOFF
            end
        end
        return
    end
    if (tonumber(boss.hpp) or 100) <= 30 and not self.boss_silenced
        and self.boss_silence_requests < MAX_BOSS_SILENCE_REQUESTS
        and now >= self.next_boss_silence
    then
        queue_for(ctx, SMALLS, 'silence-boss', self.encounter_id,
            nil, boss.id)
        self.boss_silence_requests = self.boss_silence_requests + 1
        self.next_boss_silence = now + BOSS_SILENCE_RETRY
    end
end

local function has_local_shadows(ctx)
    for _, id in ipairs(SHADOW_BUFFS) do
        if ctx.has_buff_id(id) then return true end
    end
    return false
end

local function ice_spikes_hold(self, subject, now)
    local state = self.add_dispel[entity_key(subject)]
    return state and state.active
        and now < (state.hold_until or 0)
end

local function setup_ready(self, ctx, now)
    return self.pull_confirmed and self.setup_pld and self.setup_geo
        and now - (self.food_started_at or now) >= FOOD_SETTLE
        and ctx.has_buff_id(FOOD_BUFF_ID)
end

local function request_lowhp_cure(self, ctx, mob, semantic, now)
    local state = self.lowhp_cures[mob.name]
    if not state or state.id ~= mob.id or state.index ~= mob.index then
        state = {
            id=mob.id, index=mob.index, requests=0,
            next_at=now, cycle_at=0,
        }
        self.lowhp_cures[mob.name] = state
    end
    if state.requests >= MAX_LOWHP_CURE_REQUESTS then
        if now < (state.cycle_at or 0) then return end
        state.requests = 0
        state.next_at = now
    end
    if now < (state.next_at or 0) then return end
    queue_for(ctx, SMALLS, semantic, self.encounter_id, nil, mob.id)
    state.requests = state.requests + 1
    state.next_at = now + LOWHP_CURE_RETRY
    if state.requests >= MAX_LOWHP_CURE_REQUESTS then
        state.cycle_at = now + LOWHP_CURE_CYCLE_BACKOFF
    end
end

local function lowhp_phase_tick(self, ctx, boss, now)
    local entered = false
    if not self.lowhp_phase and self.wave2_done
        and (tonumber(boss.hpp) or 100) <= LOWHP_PHASE_HPP
    then
        self.lowhp_phase = true
        self.next_lowhp_control = now
        self.lowhp_cures = {}
        entered = true
        if self.chain_stage ~= 'idle' then
            cancel_all(ctx, self.encounter_id)
            clear_chain(self, now, 1)
        end
        alert_once(self, ctx, 'lowhp-phase',
            'LOW-HP PHASE: attacker top-ups suppressed; holding weapon skills until Dolo, Tackle, and Kick are 13-25%.',
            false, 3)
    end
    if not self.lowhp_phase then return false, false, false end

    if now >= (self.next_lowhp_control or 0) then
        for _, member in ipairs(MEMBERS) do
            queue_for(ctx, member, 'lowhp-on', self.encounter_id)
        end
        self.next_lowhp_control = now + LOWHP_CONTROL_REFRESH
    end

    local danger
    local attacker_mobs = {}
    for _, name in ipairs(ATTACKERS) do
        local mob = member_entity(ctx, name)
        if not mob then return true, true, entered end
        attacker_mobs[name] = mob
        if mob.hpp < LOWHP_ATTACKER_MIN
            and (not danger or mob.hpp < danger.hpp)
        then
            danger = mob
        elseif mob.hpp >= LOWHP_ATTACKER_MIN then
            self.lowhp_cures[name] = nil
        end
    end
    if danger then
        set_subject(self, ctx, nil, now)
        request_lowhp_cure(self, ctx, danger, LOWHP_CURE[danger.name], now)
        return true, true, entered
    end

    local support_low
    local support_positioned = true
    local support_mobs = {}
    for _, name in ipairs(SUPPORT) do
        local mob = member_entity(ctx, name)
        if not mob then return true, true, entered end
        support_mobs[name] = mob
        local separation = squared_separation(boss, mob)
        if not separation
            or separation <= LOWHP_SUPPORT_RADIUS * LOWHP_SUPPORT_RADIUS
        then
            support_positioned = false
        end
        if mob.hpp < LOWHP_SUPPORT_MIN
            and (not support_low or mob.hpp < support_low.hpp)
        then
            support_low = mob
        elseif mob.hpp >= LOWHP_SUPPORT_MIN then
            self.lowhp_cures[name] = nil
        end
    end
    if support_low then
        set_subject(self, ctx, nil, now)
        request_lowhp_cure(self, ctx, support_low, 'support-cure', now)
    end
    if not support_positioned then
        set_subject(self, ctx, nil, now)
        alert_once(self, ctx, 'lowhp-support-position',
            'LOW-HP POSITION HOLD: move Barney, Smalls, and Achoo beyond 16 yalms from Bigwig while keeping Smalls in cure range.',
            true, 5)
    end
    local cure_reachable = true
    for _, name in ipairs(ATTACKERS) do
        local separation = squared_separation(
            support_mobs[SMALLS], attacker_mobs[name])
        if not separation
            or separation > LOWHP_CURE_RADIUS * LOWHP_CURE_RADIUS
        then
            cure_reachable = false
            break
        end
    end
    if not cure_reachable then
        set_subject(self, ctx, nil, now)
        alert_once(self, ctx, 'lowhp-cure-position',
            'LOW-HP CURE HOLD: keep Smalls within 20 yalms of Dolo, Tackle, and Kick.',
            true, 5)
    end
    return true, support_low ~= nil or not support_positioned
        or not cure_reachable, entered
end

local function lowhp_band_ready(self, ctx, boss)
    if not self.lowhp_phase then return true end
    for _, name in ipairs(ATTACKERS) do
        local mob = member_entity(ctx, name)
        if not mob or mob.hpp < LOWHP_ATTACKER_MIN
            or mob.hpp > LOWHP_ATTACKER_MAX
            or not self.shadow_confirmed[name]
        then
            return false
        end
    end
    for _, name in ipairs(SUPPORT) do
        local mob = member_entity(ctx, name)
        local separation = squared_separation(boss, mob)
        if not mob or not separation
            or separation <= LOWHP_SUPPORT_RADIUS * LOWHP_SUPPORT_RADIUS
        then
            return false
        end
    end
    local smalls = member_entity(ctx, SMALLS)
    if not smalls then return false end
    for _, name in ipairs(ATTACKERS) do
        local separation = squared_separation(smalls, member_entity(ctx, name))
        if not separation
            or separation > LOWHP_CURE_RADIUS * LOWHP_CURE_RADIUS
        then
            return false
        end
    end
    return true
end

local function party_healthy(self, ctx)
    if self.lowhp_phase then
        for _, name in ipairs(ATTACKERS) do
            local mob = member_entity(ctx, name)
            if not mob or mob.hpp < LOWHP_ATTACKER_MIN then return false end
        end
        for _, name in ipairs(SUPPORT) do
            local mob = member_entity(ctx, name)
            if not mob or mob.hpp < LOWHP_SUPPORT_MIN then return false end
        end
        return true
    end
    local floor = tonumber(ctx.party_hpp_floor())
    return floor ~= nil and floor >= MIN_PARTY_HPP
end

local function safe_to_start(self, ctx, boss, subject, now)
    if self.chain_stage ~= 'idle' or now < (self.next_chain_at or 0)
        or not setup_ready(self, ctx, now) or not party_healthy(self, ctx)
        or not lowhp_band_ready(self, ctx, boss)
        or now < (self.perfect_dodge_until or 0)
        or not has_local_shadows(ctx)
        or ice_spikes_hold(self, subject, now)
        or self.boss_shadows and subject.id == boss.id
        or threshold_guard(self, boss) and subject.id == boss.id
    then
        return false
    end
    return (tonumber(ctx.party_tp(KICK)) or 0) >= MIN_CHAIN_TP
        and (tonumber(ctx.party_tp(TACKLE)) or 0) >= MIN_CHAIN_TP
        and (tonumber(ctx.party_tp(DOLO)) or 0) >= MIN_CHAIN_TP
end

local function abort_chain(self, ctx, now, message)
    cancel_all(ctx, self.encounter_id)
    clear_chain(self, now, 1)
    if message then
        alert_once(self, ctx, 'chain-reset', message, false, 3)
    end
end

local function chain_tick(self, ctx, boss, subject, now)
    if self.chain_subject_id and (self.chain_subject_id ~= subject.id
        or self.chain_subject_index ~= subject.index)
    then
        abort_chain(self, ctx, now)
    end
    if self.chain_stage == 'idle' then
        if not safe_to_start(self, ctx, boss, subject, now) then return end
        self.chain_stage = 'lead'
        self.chain_subject_id = subject.id
        self.chain_subject_index = subject.index
        self.stage_at = now
        self.stage_requests = 0
        self.next_stage_request = now
    end

    if not party_healthy(self, ctx)
        or ice_spikes_hold(self, subject, now)
        or self.boss_shadows and subject.id == boss.id
        or now >= (self.perfect_dodge_until or 0)
            and threshold_guard(self, boss) and subject.id == boss.id
    then
        abort_chain(self, ctx, now)
        return
    end
    if now - (self.stage_at or now) > CHAIN_TIMEOUT then
        abort_chain(self, ctx, now,
            'CHAIN RESET: a fixed Qutrub weaponskill did not confirm in time.')
        return
    end
    if self.stage_requests >= MAX_CHAIN_REQUESTS
        or now < (self.next_stage_request or 0)
    then
        return
    end

    local recipient, semantic
    if self.chain_stage == 'lead' then
        recipient, semantic = KICK, 'lead'
    elseif self.chain_stage == 'middle'
        and now - self.stage_at >= MIN_CHAIN_DELAY
    then
        recipient, semantic = TACKLE, 'middle'
    elseif self.chain_stage == 'close'
        and now - self.stage_at >= MIN_CHAIN_DELAY
    then
        recipient, semantic = DOLO, 'close'
    else
        return
    end
    if (tonumber(ctx.party_tp(recipient)) or 0) < MIN_CHAIN_TP then return end
    queue_for(ctx, recipient, semantic, self.encounter_id, nil, subject.id)
    self.stage_requests = self.stage_requests + 1
    self.next_stage_request = now + CHAIN_RETRY
end

local function begin_perfect_dodge(self, ctx, now)
    if now - (self.last_mechanic['Perfect Dodge'] or -100000)
        < MECHANIC_DEDUPE
    then
        return
    end
    self.last_mechanic['Perfect Dodge'] = now
    self.perfect_dodge_until = now + PERFECT_DODGE_HOLD
    set_subject(self, ctx, nil, now)
    alert_once(self, ctx, 'perfect-dodge',
        'PERFECT DODGE: all physical offense stopped for 32 seconds.',
        false, MECHANIC_DEDUPE)
end

local function runtime_on_activate(self, ctx)
        self.active = true
        self.arm_consumed = ctx.operator_armed() == true
        ctx.client.auto_target(false)
        self.auto_target_owned = true
    end

local function runtime_on_deactivate(self, ctx)
        if ctx.player_name() == DOLO and self.encounter_id then
            end_encounter(self, ctx, 'profile deactivated')
        else
            clear_encounter(self)
        end
        self.active = false
        if self.auto_target_owned then
            ctx.client.auto_target(true)
            self.auto_target_owned = false
        end
    end

local function runtime_on_action(self, ctx, action)
        if not self.active or ctx.player_name() ~= DOLO
            or type(action) ~= 'table'
            or not AMBUSCADE_ZONES[ctx.zone_id()]
            or not self.encounter_id
        then
            return
        end
        local now = ctx.now()
        local boss = ctx.mob_by_id(self.encounter_id)
        if not live_boss(boss) or boss.index ~= self.encounter_index then
            return
        end
        local source = actor(ctx, action)
        if not source and tonumber(action.actor_id) == self.encounter_id then
            source = {id=self.encounter_id, name=BOSS}
        end
        if source and (source.name == DOLO or source.name == TACKLE
            or source.name == KICK or source.name == BARNEY
            or source.name == SMALLS or source.name == ACHOO)
        then
            self.member_ids[source.name] = source.id
        end

        if source and LOWHP_CURE[source.name] and action.category == 4 then
            local spell_name = resource_name(ctx.spell(action.param))
            if (spell_name == 'Utsusemi: Ni'
                or spell_name == 'Utsusemi: Ichi')
                and successful_result(target_result(action, source.id))
            then
                self.shadow_confirmed[source.name] = now
            end
        end

        observe_mew(self, ctx, action, source, now)
        observe_retreat(self, ctx, action, source)

        if source and source.id == self.encounter_id then
            local ability = monster_ability_from_action(ctx, action)
            if ability == 'Perfect Dodge' then
                begin_perfect_dodge(self, ctx, now)
            end
            if action.category == 4
                and resource_name(ctx.spell(action.param)) == 'Utsusemi: San'
                and successful_result(target_result(action, self.encounter_id))
            then
                self.boss_shadows = true
                self.diaga_requests = 0
                self.next_diaga = now
                self.diaga_cycle_at = 0
                if self.chain_subject_id == self.encounter_id then
                    abort_chain(self, ctx, now)
                end
            end
        end

        if source and source.name == ASTROLOGER
            and associated_add(ctx, boss, source)
            and action.category == 4
            and resource_name(ctx.spell(action.param)) == 'Ice Spikes'
            and successful_result(target_result(action, source.id))
        then
            self.add_dispel[entity_key(source)] = {
                active=true, requests=0, next_at=now, cycle_at=0,
                hold_until=now + MAX_DISPEL_REQUESTS * DISPEL_RETRY + 1,
            }
            if self.chain_subject_id == source.id
                and self.chain_subject_index == source.index
            then
                abort_chain(self, ctx, now)
            end
        end

        if source and action.category == 5
            and tonumber(action.param) == FOOD_ITEM_ID
            and self.food_requests[source.name]
            and successful_result(target_result(action, source.id))
        then
            self.food_seen[source.name] = true
        end

        observe_pld_setup(self, ctx, action, source)

        if source and source.name == TACKLE and action.category == 4
            and resource_name(ctx.spell(action.param)) == 'Flash'
        then
            for key, state in pairs(self.add_flash) do
                local id = tonumber(key:match('^(%d+):'))
                if id and successful_result(target_result(action, id)) then
                    state.confirmed = true
                    state.confirmed_at = now
                    state.ever_confirmed = true
                end
            end
        end

        if source and source.name == TACKLE and action.category == 6
            and self.current_wave
        then
            local step = WAVE_MITIGATION[self.wave_mitigation_step]
            if step and action_name(ctx, action) == step.name
                and successful_result(target_result(action, source.id))
            then
                self.wave_mitigation_step = self.wave_mitigation_step + 1
                self.wave_mitigation_requests = 0
                self.next_wave_mitigation = now
            end
        end

        if source and source.name == ACHOO and action.category == 4
            and resource_name(ctx.spell(action.param)) == 'Geo-Frailty'
            and successful_result(target_result(action, self.encounter_id))
        then
            self.setup_geo = true
        end

        if source and source.name == BARNEY and action.category == 6
            and resource_name(ctx.job_ability(action.param)) == 'Clarion Call'
            and successful_result(target_result(action, source.id))
        then
            self.clarion_confirmed = true
            self.next_fourth_song = now
        end

        if source and source.name == SMALLS and action.category == 4 then
            local spell_name = resource_name(ctx.spell(action.param))
            if spell_name == 'Cure II' or spell_name == 'Cure IV' then
                for name, state in pairs(self.lowhp_cures) do
                    local mob = member_entity(ctx, name)
                    if mob and state.id == mob.id and state.index == mob.index
                        and successful_result(target_result(action, mob.id))
                    then
                        state.requests = 0
                        state.next_at = now + LOWHP_CURE_RETRY
                        state.cycle_at = 0
                        state.confirmed_at = now
                    end
                end
            elseif spell_name == 'Silence' then
                for key, state in pairs(self.add_silence) do
                    local id = tonumber(key:match('^(%d+):'))
                    if id and successful_result(target_result(action, id)) then
                        state.done = true
                        state.confirmed_at = now
                    end
                end
                if successful_result(target_result(action, self.encounter_id))
                then
                    self.boss_silenced = true
                end
            elseif spell_name == 'Diaga'
                and successful_result(target_result(action, self.encounter_id))
            then
                self.boss_shadows = false
                self.diaga_requests = 0
                self.diaga_cycle_at = 0
            elseif spell_name == 'Dispel' then
                for key, state in pairs(self.add_dispel) do
                    local id = tonumber(key:match('^(%d+):'))
                    if state.active and id
                        and successful_result(target_result(action, id))
                    then
                        state.active = false
                    end
                end
            end
        end

        if action.category ~= 3 or not source or not self.chain_subject_id
            or not target_result(action, self.chain_subject_id)
        then
            return
        end
        local ws_name = resource_name(ctx.weapon_skill(action.param))
        if self.chain_stage == 'lead' and source.name == KICK
            and ws_name == 'Evisceration'
        then
            if positive_damage(action, self.chain_subject_id)
                and party_healthy(self, ctx)
            then
                self.chain_stage = 'middle'
                self.stage_at = now
                self.stage_requests = 0
                self.next_stage_request = now + MIN_CHAIN_DELAY
            else
                abort_chain(self, ctx, now)
            end
        elseif self.chain_stage == 'middle' and source.name == TACKLE
            and ws_name == 'Savage Blade'
        then
            local elapsed = now - (self.stage_at or now)
            if elapsed >= MIN_CHAIN_DELAY and elapsed <= MAX_CHAIN_DELAY
                and positive_damage(action, self.chain_subject_id)
                and confirmed_skillchain(action, self.chain_subject_id, 291)
            then
                self.chain_stage = 'close'
                self.stage_at = now
                self.stage_requests = 0
                self.next_stage_request = now + MIN_CHAIN_DELAY
            else
                abort_chain(self, ctx, now,
                    'FRAGMENTATION NOT CONFIRMED: Last Stand suppressed.')
            end
        elseif self.chain_stage == 'close' and source.name == DOLO
            and ws_name == 'Last Stand'
        then
            local elapsed = now - (self.stage_at or now)
            if elapsed >= MIN_CHAIN_DELAY and elapsed <= MAX_CHAIN_DELAY
                and positive_damage(action, self.chain_subject_id)
                and confirmed_skillchain(action, self.chain_subject_id, 288)
            then
                self.engagement_proven_key = self.subject_key
                clear_chain(self, now, 1)
            else
                abort_chain(self, ctx, now,
                    'LIGHT NOT CONFIRMED: transaction reset.')
            end
        end
    end

local function runtime_on_tick(self, ctx, now)
        if not self.active or ctx.player_name() ~= DOLO
            or now < self.next_poll
        then
            return
        end
        self.next_poll = now + POLL_INTERVAL

        if not AMBUSCADE_ZONES[ctx.zone_id()] then
            if self.encounter_id then
                end_encounter(self, ctx, 'left the Ambuscade battlefield')
            end
            if ctx.operator_armed() then self.arm_consumed = true end
            return
        end

        if not ctx.operator_armed() then
            if self.encounter_id then end_encounter(self, ctx, 'operator disarmed') end
            self.arm_consumed = false
            return
        end

        local boss, claim_state
        if self.encounter_id then
            boss, claim_state = resolve_boss(self, ctx, now)
            if not boss then return end
        else
            if self.arm_consumed or not ctx.combat_ready() then return end
            boss = scan_boss(ctx)
            if not boss or not begin_encounter(self, ctx, boss, now) then return end
            claim_state = ctx.party_claimed(boss) and 'party' or 'unclaimed'
        end

        if ctx.encounter_ready(boss.id) ~= true then
            if self.ready_last then
                cancel_all(ctx, boss.id)
                ctx.actions.combat_stop()
                clear_chain(self, now, 1)
            end
            self.ready_last = false
            return
        end
        self.ready_last = true

        local party_floor = tonumber(ctx.party_hpp_floor())
        if party_floor ~= nil and party_floor <= 0 then
            end_encounter(self, ctx, 'a party member was knocked out')
            return
        end

        food_tick(self, ctx, now)
        shadow_tick(self, ctx, now)
        optional_song_tick(self, ctx, now)
        pet_tick(self, ctx, now)
        pld_setup_tick(self, ctx, now)
        geo_setup_tick(self, ctx, now, claim_state)

        -- No PartyCombat engagement is legal until the exact Flash result
        -- completed and the party claim became visible.
        if not self.pull_confirmed or claim_state ~= 'party' then return end

        local adds = scan_adds(ctx, boss)
        dispel_adds_tick(self, ctx, adds, now)
        silence_adds_tick(self, ctx, adds, now)
        mew_tick(self, ctx, now, 1 + #adds)
        retreat_tick(self, ctx, now)

        if update_waves(self, ctx, boss, adds, now) then
            if #adds == 0 then
                set_subject(self, ctx, nil, now)
                return
            end
        end

        local _, lowhp_hold =
            lowhp_phase_tick(self, ctx, boss, now)
        if lowhp_hold then return end

        -- Exact low-HP rescue and evacuation holds outrank routine boss
        -- Silence/Diaga reservations on Smalls.
        boss_magic_tick(self, ctx, boss, adds, now)

        if now < (self.perfect_dodge_until or 0) then
            set_subject(self, ctx, nil, now)
            return
        end

        if not setup_ready(self, ctx, now) then
            set_subject(self, ctx, nil, now)
            return
        end

        local subject = adds[1] or boss
        if subject.id == boss.id and threshold_guard(self, boss) then
            -- Keep auto-attacks available to reach the exact phase boundary,
            -- but never start or continue a weaponskill transaction there.
            if self.chain_stage ~= 'idle' then abort_chain(self, ctx, now) end
        end
        set_subject(self, ctx, subject, now)
        if not add_flash_tick(self, ctx, subject, now) then return end
        wave_mitigation_tick(self, ctx, now)
        force_tick(self, ctx, now, subject)
        chain_tick(self, ctx, boss, subject, now)
    end

function M.create()
    local self = {
        active=false,
        auto_target_owned=false,
        next_poll=0,
        last_alert={},
        arm_consumed=false,
        on_activate=runtime_on_activate,
        on_deactivate=runtime_on_deactivate,
        on_action=runtime_on_action,
        on_tick=runtime_on_tick,
    }
    clear_encounter(self)
    return self
end

return M
