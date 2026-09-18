-- Cooperative no-Cait Qutrub automation.
--
-- A direct profile alias selects and arms this runtime automatically; an
-- explicit operator stop stays authoritative until a later re-arm. Arming
-- begins non-hostile preparation only. The operator's first observed Bigwig
-- claim/action releases combat assignments and hostile support without a
-- second command, check, ACK, or readiness gate. Every active-fight action
-- lane remains best-effort and independent. The GearSwap adapter only
-- submits fixed actions and always passes manual input through.

local M = {}

local BOSS_NAMES = {
    bozzettobigwig=true,
}
local ASTROLOGER_NAMES = {
    bozzettoastrologer=true,
    bozzettoastrol=true,
}
local TORMENTOR_NAMES = {
    bozzettotormentor=true,
    bozzettotormenter=true,
    bozzettotorment=true,
    bozzettotormen=true,
}
local ZONES = {[183]=true, [287]=true}

local DOLO = 'Dolomedes'
local TACKLE = 'Tackleberry'
local KICK = 'Kickpuncher'
local BARNEY = 'Barneystinson'
local SMALLS = 'Smalls'
local ACHOO = 'Achoo'
local MEMBERS = {DOLO,TACKLE,KICK,BARNEY,SMALLS,ACHOO}
local ATTACKERS = {DOLO,TACKLE,KICK,BARNEY}
local COMBAT_MEMBERS = {DOLO,TACKLE,KICK,BARNEY,ACHOO}
local COMBAT_MEMBER_SET = {
    [DOLO]=true, [TACKLE]=true, [KICK]=true, [BARNEY]=true, [ACHOO]=true,
}
local SHADOW_USERS = {DOLO,KICK,BARNEY}
local BOSS_KILLERS = {DOLO,KICK,BARNEY}
-- Dolo and Kick are the deliberate Bigwig-hate pair. Barney remains on add
-- damage whenever a holder is known instead of becoming a third tank lane.
local BOSS_HOLDER_SET = {
    [DOLO]=true, [KICK]=true,
}
local SLEEP_SPELLS = {
    Sleep=true, ['Sleep II']=true, Sleepga=true, ['Sleepga II']=true,
}
local ADD_CAPTURE_SEMANTICS = {
    ['flash-add']=true,
    ['blank-gaze-add']=true,
    ['light-shot-target']=true,
    ['box-step-add']=true,
    ['stun-add']=true,
}
local RDM_HEALING_SEMANTICS = {
    ['wake-pack']=true,
    ['lowhp-cure']=true,
    ['support-cure']=true,
    ['cure-iv']=true,
}

-- Bars derives its monster-target display from the primary target in the
-- monster's latest action packet. These result messages identify the primary
-- target when an action also contains secondary AoE victims. Keeping the same
-- interpretation here gives the wave split the same evidence the operator
-- already sees in Bars without coupling the addons together.
local AOE_MAIN_TARGET_MESSAGES = {
    [2]=true,[7]=true,[14]=true,[67]=true,[75]=true,[83]=true,
    [85]=true,[102]=true,[103]=true,[110]=true,[116]=true,
    [127]=true,[131]=true,[134]=true,[141]=true,[148]=true,
    [150]=true,[156]=true,[185]=true,[186]=true,[187]=true,
    [188]=true,[189]=true,[194]=true,[197]=true,[224]=true,
    [225]=true,[226]=true,[227]=true,[228]=true,[230]=true,
    [231]=true,[236]=true,[237]=true,[238]=true,[242]=true,
    [243]=true,[252]=true,[268]=true,[271]=true,[274]=true,
    [275]=true,[306]=true,[317]=true,[318]=true,[319]=true,
    [320]=true,[321]=true,[322]=true,[323]=true,[324]=true,
    [341]=true,[342]=true,[362]=true,[373]=true,[375]=true,
    [379]=true,[408]=true,[412]=true,[413]=true,[435]=true,
    [441]=true,[570]=true,[645]=true,[658]=true,
}
local DIA_LAND_MESSAGES = {
    [2]=true,[230]=true,[236]=true,[252]=true,
}
local DISPEL_SUCCESS_MESSAGES = {
    [341]=true,[342]=true,
}
local WAIL_STATUS_BY_BUFF_ID = {
    [33]='Animating Wail', -- Haste
    [40]='Fortifying Wail', -- Protect
}
local POLL_INTERVAL = 0.25
local MEMBER_ACTION_SPACING = 1.25
-- Local adapters react immediately when Copy Image count drops. This slower
-- controller cadence is only a watchdog for a missed buff transition or a
-- rejected cast, not the primary recast trigger.
local SHADOW_INTERVAL = 10
local SHADOW_ICHI_FALLBACK = 1.25
local COCOON_INTERVAL = 45
local CRUSADE_INTERVAL = 180
local REPRISAL_INTERVAL = 60
local RERAISE_INTERVAL = 20
local GEO_INTERVAL = 90
local DEBUFF_INTERVAL = 60
local LOW_HP_MAGIC_INTERVAL = 15
local PACK_CONTROL_INTERVAL = 8
-- The live Normal capture showed one add appearing about every five seconds.
-- Each new entity is anchored immediately, but common-focus offense waits for
-- one bounded quiet interval so a late spawn cannot become an unowned third
-- target on Bigwig's holder. This is encounter timing, never a start gate.
local WAVE_ASSEMBLY_QUIET = 6.25
local ANCHOR_CAPTURE_RETRY = 3
-- This is tactical clearance, not an encounter damage rule. At 15 yalms,
-- requiring Tackle inside the 4.5-yalm arrival radius leaves at least 10.5
-- yalms to Bigwig, clear of the nine-yalm Jettatura cone and six-yalm pulses.
local SAFE_ADD_CONTROL_SEPARATION = 15
-- PartyCombat owns continuous movement after a directed edge.  This profile
-- gives a stalled initial acquisition one exact repair, then a separate
-- bounded repair only if an arrived member drifts from the add. Neither lane
-- polls a force command over the operator's later manual override.
local ADD_PURSUE_INTERVAL = 1.25
local ADD_PURSUE_SEPARATION = 4.5
local ADD_ACQUIRE_REPAIR_AFTER = 4.5
local ADD_ACQUIRE_PROGRESS = .75
-- A 2.5-second post-assembly pickup edge often expired before a distant owner
-- could close, swing, and produce direct target evidence. Eight seconds is
-- still bounded, while ownership confirmation releases the owner as soon as
-- the fixed quiet assembly phase has safely ended.
local PARK_PICKUP_SECONDS = 8
local PARK_REPAIR_INTERVAL = 8
local LIGHT_SHOT_RANGE = 22
-- Light Shot's Dia enhancement is attached to the executed shot and caps
-- after one.  On these sleep-immune Qutrub, message 324 can describe only
-- the separate Sleep miss, so any exact-target action result completes the
-- cycle.  A retry is permitted only when no action packet was observed at
-- all, which means the submitted command may never have executed.
local LIGHT_SHOT_RESULT_TIMEOUT = 4
local LIGHT_SHOT_RETRY = 12
local LIGHT_SHOT_MAX_ATTEMPTS = 3
local DIA_RESULT_TIMEOUT = 4
local DIA_RETRY = 5
local DIA_MAX_ATTEMPTS = 3
local FOCUS_DISPEL_RETRY = 3.5
local FOCUS_DISPEL_MAX_ATTEMPTS = 6
local EVENT_DEDUPE = 4
local BOSS_TARGET_CONFIDENCE = 7
local BOSS_HOLDER_REVIEW_INTERVAL = 5
local RDM_HEAL_PRIORITY_HPP = 74
local SUPPORT_CURE_RANGE = 20.5
local EMERGENCY_HEAL_POLL = 1
local TACKLE_EMERGENCY_HPP = 40
local TACKLE_EMERGENCY_DELAY = 1.25

local function uint32(value)
    value = tonumber(value)
    return value and value >= 1 and value <= 4294967295
        and value == math.floor(value)
end

local function normalized_name(name)
    return type(name) == 'string'
        and name:lower():gsub('[^%w]', '') or nil
end

local function exact_entity(mob)
    return type(mob) == 'table'
        and tonumber(mob.spawn_type) == 16
        and uint32(mob.id)
        and type(mob.index) == 'number'
        and mob.index >= 0 and mob.index <= 65535
        and mob.index == math.floor(mob.index)
end

local function named_entity(mob, names)
    local name = normalized_name(mob and mob.name)
    return exact_entity(mob) and name ~= nil and names[name] == true
end

local function live_boss(mob)
    return named_entity(mob, BOSS_NAMES)
        and mob.valid_target == true
        and (tonumber(mob.hpp) or 0) > 0
end

local function add_rank(mob)
    if named_entity(mob, ASTROLOGER_NAMES) then return 1 end
    if named_entity(mob, TORMENTOR_NAMES) then return 2 end
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
    if (tonumber(mob.claim_id) or 0) ~= 0 then return false end
    local separation = squared_separation(boss, mob)
    if separation then return separation <= 35 * 35 end
    local boss_distance = tonumber(boss.distance)
    local add_distance = tonumber(mob.distance)
    return boss_distance ~= nil and add_distance ~= nil
        and boss_distance >= 0 and add_distance >= 0
        and boss_distance <= 35 * 35 and add_distance <= 35 * 35
end

local function selectable_boss(ctx, mob)
    return live_boss(mob)
        and (ctx.party_claimed(mob)
            or (tonumber(mob.claim_id) or 0) == 0)
end

local function scan_boss(ctx)
    local current = ctx.current_target()
    if selectable_boss(ctx, current) then return current end
    local selected
    for _, mob in pairs(ctx.mob_array() or {}) do
        if selectable_boss(ctx, mob)
            and (not selected or mob.id < selected.id)
        then
            selected = mob
        end
    end
    return selected
end

local function scan_adds(ctx, boss)
    local adds = {}
    for _, mob in pairs(ctx.mob_array() or {}) do
        if associated_add(ctx, boss, mob) then adds[#adds + 1] = mob end
    end
    table.sort(adds, function(left, right)
        local left_rank, right_rank = add_rank(left), add_rank(right)
        if left_rank ~= right_rank then return left_rank < right_rank end
        if left.id ~= right.id then return left.id < right.id end
        return left.index < right.index
    end)
    return adds
end

local function party_member(ctx, name)
    local selected
    for _, mob in pairs(ctx.mob_array() or {}) do
        if type(mob) == 'table' and mob.name == name and uint32(mob.id)
            and type(mob.index) == 'number' and mob.index >= 0
            and mob.index <= 65535 and mob.index == math.floor(mob.index)
            and mob.valid_target == true
        then
            if selected then return nil end
            selected = mob
        end
    end
    return selected
end

local function lowest_cure_member(ctx, healer_name, threshold)
    local healer = party_member(ctx, healer_name)
    if not healer or (tonumber(healer.hpp) or 0) <= 0 then return nil end
    local lowest
    for _, name in ipairs(MEMBERS) do
        local member = party_member(ctx, name)
        local hpp = tonumber(member and member.hpp)
        local separation = name == healer_name and member and 0
            or squared_separation(healer, member)
        if hpp and hpp > 0 and hpp <= threshold
            and separation and separation <= SUPPORT_CURE_RANGE^2
            and (not lowest or hpp < lowest.hpp)
        then
            lowest = {id=member.id, name=name, hpp=hpp}
        end
    end
    return lowest
end

local function clear(self)
    self.encounter_id = nil
    self.encounter_index = nil
    self.pull_started = false
    self.forced_subject = nil
    self.forced_subject_id = nil
    self.boss_target_id = nil
    self.boss_target_name = nil
    self.boss_target_at = nil
    self.wave_holder = nil
    self.next_holder_review = 0
    self.wave_assembling = false
    self.wave_last_add_at = nil
    self.wave_live_add_keys = {}
    self.parking_signature = nil
    self.anchor_owner_by_key = {}
    self.parked_owner_by_key = {}
    self.parked_target_by_owner = {}
    self.park_pickup_until = {}
    self.next_park_repair = {}
    self.add_target_by_key = {}
    self.anchor_confirmed_by_key = {}
    self.capture_attempt_owner_by_key = {}
    self.transfer_hold_owner = nil
    self.transfer_wait_key = nil
    self.transfer_started_at = nil
    self.threat_holds = {}
    self.combat_targets = {}
    self.next_member_action = {}
    self.next_shadow = 0
    self.next_cocoon = 0
    self.next_crusade = 0
    self.next_reprisal = 0
    self.next_reraise = 0
    self.next_geo = 0
    self.next_debuff = 0
    self.next_low_hp_magic = 0
    self.next_support_heal = 0
    self.next_add_control = {}
    self.next_add_silence = {}
    self.next_pack_control = 0
    self.next_add_pursuit = 0
    self.add_pursuit_arrived = {}
    self.member_attack_targets = {}
    self.prepared_subjects = {}
    self.current_subject_key = nil
    self.frailty_subject_id = nil
    self.frailty_subject_key = nil
    self.frailty_requested = false
    self.focus_support = {}
    self.wail_buffs = {}
    self.seen_adds = {}
    self.add_wave = 0
    self.adds_were_present = false
    self.last_event = {}
    self.tasks = {}
    self.task_serial = 0
end

local function task_key(recipient, semantic, family)
    return table.concat({family or 'task', recipient, semantic}, ':')
end

local function smalls_periodic_coalesce_class(semantic, family)
    if semantic == 'reraise' or semantic == 'slow-ii'
        or semantic == 'paralyze-ii' or semantic == 'silence-add'
        or semantic == 'silence-boss'
    then
        return semantic
    end
    if semantic == 'diaga' and type(family) == 'string'
        and family:match('^lowhp%-')
    then
        return 'lowhp-diaga'
    end
    return nil
end

local function schedule(self, recipient, semantic, at, family, priority,
    subject_id, tracking, subject_domain)
    local effective_at = at
    local effective_priority = priority or 10
    local effective_tracking = tracking
    local coalesce_class = recipient == SMALLS
        and not RDM_HEALING_SEMANTICS[semantic]
        and smalls_periodic_coalesce_class(semantic, family) or nil
    if coalesce_class then
        -- Smalls' tactical lane pauses while an in-range party member needs
        -- primary healing. Periodic producers use timestamped families, so
        -- retaining every family would otherwise build an arbitrarily long
        -- post-recovery queue. Keep one periodic request per class/subject,
        -- preserving its earliest due time and strongest priority. Reactive
        -- Ice Spikes, Wail, and San tasks retain their independent families.
        for key, pending in pairs(self.tasks) do
            if pending.recipient == recipient
                and pending.coalesce_class == coalesce_class
                and pending.subject_id == subject_id
            then
                effective_at = math.min(effective_at, pending.at)
                effective_priority = math.max(
                    effective_priority, pending.priority or 10)
                effective_tracking = effective_tracking or pending.tracking
                self.tasks[key] = nil
            end
        end
    end
    self.task_serial = self.task_serial + 1
    local key = task_key(recipient, semantic, family)
    self.tasks[key] = {
        key=key, recipient=recipient, semantic=semantic,
        at=effective_at, priority=effective_priority, subject_id=subject_id,
        serial=self.task_serial, tracking=effective_tracking,
        coalesce_class=coalesce_class,
        subject_domain=subject_domain or (subject_id and 'hostile' or nil),
    }
end

local function request(self, ctx, recipient, semantic, subject_id)
    -- Acceptance is deliberately ignored. A rejected/busy/missing action is
    -- local to this one attempt; every other recipient continues this tick.
    ctx.actions.party_adapter(recipient, semantic, self.encounter_id,
        nil, subject_id)
    self.next_member_action[recipient] = ctx.now() + MEMBER_ACTION_SPACING
end

local function note_tracked_dispatch(self, task, now)
    local tracking = task.tracking
    if not tracking then return end
    if tracking.kind == 'focus-wail' then
        local state = self.wail_buffs[tracking.key]
        if state and state.subject_id == task.subject_id then
            state.attempts = state.attempts + 1
            state.next_at = now + FOCUS_DISPEL_RETRY
        end
        return
    end
    local support = self.focus_support[tracking.key]
    if not support or support.subject_id ~= task.subject_id then return end
    if tracking.kind == 'focus-dia' then
        support.dia_attempts = support.dia_attempts + 1
        support.dia_inflight_until = now + DIA_RESULT_TIMEOUT
        support.dia_next_at = now + DIA_RETRY
    elseif tracking.kind == 'focus-light' then
        support.light_attempts = support.light_attempts + 1
        support.light_inflight_until = now + LIGHT_SHOT_RESULT_TIMEOUT
        support.light_next_at = now + LIGHT_SHOT_RETRY
    end
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
    local healing_needed = lowest_cure_member(
        ctx, SMALLS, RDM_HEAL_PRIORITY_HPP) ~= nil
    for _, task in ipairs(due) do
        local controlled = task.subject_id
            and ctx.mob_by_id(task.subject_id) or nil
        local stale_secondary_capture = ADD_CAPTURE_SEMANTICS[task.semantic]
            and live_add(controlled)
            and task.subject_id ~= self.forced_subject_id
            and not self.wave_assembling
            and self.combat_targets[task.recipient] ~= task.subject_id
            and now >= (self.park_pickup_until[task.recipient] or 0)
        if stale_secondary_capture then
            -- A delayed anchor cast must not execute after its owner has
            -- already received the common focus; that cursor race was enough
            -- to strand AutoWS2 on the old enemy in the live run.
            self.tasks[task.key] = nil
        elseif task.recipient == SMALLS and healing_needed
            and not RDM_HEALING_SEMANTICS[task.semantic]
        then
            -- PartyStart RDM owns primary healing locally. Preserve this
            -- exact tactical task, but do not let it collide with the Cure
            -- slot while any living member is yellow or worse. Manual input
            -- is never filtered, and the task resumes as soon as HP recovers.
        elseif now >= (self.next_member_action[task.recipient] or 0) then
            request(self, ctx, task.recipient, task.semantic,
                task.subject_id)
            note_tracked_dispatch(self, task, now)
            self.tasks[task.key] = nil
        end
    end
end

local function cancel_requests(self, ctx)
    if not self.encounter_id then return end
    for _, name in ipairs(MEMBERS) do
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

    -- Encounter authority routes exact semantic requests; its result is not a
    -- readiness decision and never delays PartyCombat or manual control.
    ctx.authorize_encounter(boss.id)

    for _, name in ipairs(ATTACKERS) do
        schedule(self, name, 'food', now, 'initial-food-'..name, 20)
    end
    for _, name in ipairs(SHADOW_USERS) do
        schedule(self, name, 'shadow-ni', now + 1.25,
            'initial-shadow-'..name, 15)
        schedule(self, name, 'shadow-ichi',
            now + 1.25 + SHADOW_ICHI_FALLBACK,
            'initial-shadow-fallback-'..name, 14)
    end
    for _, name in ipairs(MEMBERS) do
        schedule(self, name, 'reraise', now,
            'initial-reraise-'..name, 80)
    end
    schedule(self, TACKLE, 'cocoon', now, 'initial-cocoon', 20)
    schedule(self, TACKLE, 'crusade', now + 1.25,
        'initial-crusade', 30)
    schedule(self, TACKLE, 'reprisal', now + 2.5,
        'initial-reprisal', 25)
    schedule(self, BARNEY, 'clarion', now, 'initial-clarion', 10)
    schedule(self, BARNEY, 'fourth-song', now + 1.25,
        'initial-fourth-song', 10)

    self.next_shadow = now + SHADOW_INTERVAL
    self.next_cocoon = now + COCOON_INTERVAL
    self.next_crusade = now + CRUSADE_INTERVAL
    self.next_reprisal = now + REPRISAL_INTERVAL
    self.next_reraise = now + RERAISE_INTERVAL
    self.next_geo = now + GEO_INTERVAL
    self.next_debuff = now + DEBUFF_INTERVAL
end

local function start_combat(self, boss, now)
    if self.pull_started then return end
    self.pull_started = true

    -- These are intentionally created only after a real pull edge. Before
    -- this transition no profile task targets Bigwig, changes an attack
    -- assignment, or moves a party member toward it.
    schedule(self, SMALLS, 'slow-ii', now + 1.25,
        'initial-slow', 20, boss.id)
    schedule(self, SMALLS, 'paralyze-ii', now + 2.5,
        'initial-paralyze', 20, boss.id)
    self.next_geo = now + GEO_INTERVAL
    self.next_debuff = now + DEBUFF_INTERVAL
end

local function resolved_boss(self, ctx, now)
    local boss = ctx.mob_by_id(self.encounter_id)
    if live_boss(boss) and boss.id == self.encounter_id
        and boss.index == self.encounter_index
    then
        -- Once exact ID/index authority is bound in an Ambuscade instance,
        -- claim color is presentation state rather than encounter lifetime.
        -- A deliberate Bigwig disengage can turn it yellow for longer than a
        -- normal packet gap; that must not silently disarm the runtime.
        return boss
    end
    if not live_boss(boss)
        or boss and boss.index ~= self.encounter_index
    then
        finish(self, ctx)
    end
    return nil
end

local function party_member_name_by_id(ctx, id)
    id = tonumber(id)
    if not uint32(id) then return nil end
    for _, name in ipairs(MEMBERS) do
        local member = party_member(ctx, name)
        if member and member.id == id then return name end
    end
    return nil
end

local function action_targets_id(action, id)
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == tonumber(id) then return true end
    end
    return false
end

local function action_starts_combat(self, ctx, source, action)
    if source.id == self.encounter_id then
        for _, target in ipairs(action.targets or {}) do
            if party_member_name_by_id(ctx, target.id) then return true end
        end
        return false
    end
    return party_member_name_by_id(ctx, source.id) ~= nil
        and action_targets_id(action, self.encounter_id)
end

local function action_primary_target_id(action)
    local targets = type(action) == 'table' and action.targets or nil
    if type(targets) ~= 'table' or type(targets[1]) ~= 'table' then
        return nil
    end
    local target_count = tonumber(action.target_count) or #targets
    if target_count <= 1 then return tonumber(targets[1].id) end
    for index=1,#targets do
        local target = targets[index]
        local result = type(target.actions) == 'table'
            and target.actions[1] or nil
        if result and AOE_MAIN_TARGET_MESSAGES[tonumber(result.message)] then
            return tonumber(target.id)
        end
    end
    -- Bars marks this case as an uncertain AoE target. Do not replace a
    -- known direct target with whichever victim happened to sort first.
    return nil
end

local function recent_boss_holder(self, now)
    if type(self.boss_target_at) ~= 'number'
        or now - self.boss_target_at > BOSS_TARGET_CONFIDENCE
        or not BOSS_HOLDER_SET[self.boss_target_name]
    then
        return nil
    end
    return self.boss_target_name
end

local function begin_add_wave(self, ctx, now)
    self.add_wave = self.add_wave + 1
    self.wave_holder = recent_boss_holder(self, now)
    self.next_holder_review = now + BOSS_HOLDER_REVIEW_INTERVAL
    self.wave_assembling = true
    self.wave_last_add_at = now
    self.wave_live_add_keys = {}
    self.parking_signature = nil
    self.anchor_owner_by_key = {}
    self.parked_owner_by_key = {}
    self.parked_target_by_owner = {}
    self.park_pickup_until = {}
    self.next_park_repair = {}
    self.add_target_by_key = {}
    self.anchor_confirmed_by_key = {}
    self.capture_attempt_owner_by_key = {}
    self.transfer_hold_owner = nil
    self.transfer_wait_key = nil
    self.transfer_started_at = nil
    self.threat_holds = {}
    -- Ambuscade may recycle the same server mob slots for a later wave. Treat
    -- every no-add -> add transition as a fresh capture generation so an old
    -- eight-second Flash/Gaze cadence can never delay the respawn pickup.
    self.seen_adds = {}
    self.next_add_control = {}
    self.next_add_silence = {}
    self.next_pack_control = now
    self.next_add_pursuit = now + ADD_PURSUE_INTERVAL
    self.add_pursuit_arrived = {}

    local tackle = party_member(ctx, TACKLE)
    local family = 'wave-'..tostring(self.add_wave)
    schedule(self, ACHOO, 'entrust', now, family..'-entrust', 30)
    -- Sentinel/Palisade are intentionally absent here. High-enmity PLD job
    -- abilities can touch the linked encounter pack and recreate the exact
    -- three-target convergence that enables Triple Reversal. Capture is by
    -- exact single-target Flash/Gaze instead.
    if tackle then
        schedule(self, ACHOO, 'indi-wilt', now + 1.25,
            family..'-wilt', 30, tackle.id, nil, 'party')
    end
end

local function live_add_key_set(adds)
    local keys = {}
    for _, add in ipairs(adds) do keys[entity_key(add)] = true end
    return keys
end

local function update_add_wave(self, ctx, adds, now)
    local present = #adds > 0
    if present and not self.adds_were_present then
        begin_add_wave(self, ctx, now)
    elseif not present and self.adds_were_present then
        self.wave_holder = nil
        self.next_holder_review = 0
        self.wave_assembling = false
        self.wave_last_add_at = nil
        self.wave_live_add_keys = {}
        self.parking_signature = nil
        self.anchor_owner_by_key = {}
        self.parked_owner_by_key = {}
        self.parked_target_by_owner = {}
        self.park_pickup_until = {}
        self.next_park_repair = {}
        self.add_target_by_key = {}
        self.anchor_confirmed_by_key = {}
        self.capture_attempt_owner_by_key = {}
        self.transfer_hold_owner = nil
        self.transfer_wait_key = nil
        self.transfer_started_at = nil
        self.threat_holds = {}
    end
    if present then
        local next_keys = live_add_key_set(adds)
        local newly_visible = false
        for key in pairs(next_keys) do
            if not self.wave_live_add_keys[key] then
                newly_visible = true
                break
            end
        end
        if newly_visible then
            self.wave_assembling = true
            self.wave_last_add_at = now
            self.parking_signature = nil
        end
        self.wave_live_add_keys = next_keys
        if self.wave_assembling and self.wave_last_add_at
            and now - self.wave_last_add_at >= WAVE_ASSEMBLY_QUIET
        then
            self.wave_assembling = false
            -- The desired targets change from unique anchors to common focus
            -- on the next assignment pass. No result proof authorizes it.
            self.parking_signature = nil
        end
    end
    self.adds_were_present = present
end

local function review_wave_holder(self, now)
    if not self.adds_were_present or now < self.next_holder_review then
        return false
    end
    self.next_holder_review = now + BOSS_HOLDER_REVIEW_INTERVAL
    local holder = recent_boss_holder(self, now)
    if not holder or holder == self.wave_holder then return false end

    -- If the incoming Bigwig holder currently anchors an off-focus add, do
    -- not also send that character onto the focus during the ownership
    -- transfer. That would temporarily make Bigwig + parked add + focus.
    -- The one stop edge is released as soon as a melee packet shows the
    -- transferred add on its new owner; manual input is never filtered.
    self.transfer_hold_owner = nil
    self.transfer_wait_key = nil
    self.transfer_started_at = nil
    if not self.wave_assembling then
        for key, owner in pairs(self.anchor_owner_by_key or {}) do
            local mob_id = tonumber(key:match('^(%d+):'))
            if owner == holder and mob_id ~= self.forced_subject_id then
                self.transfer_hold_owner = holder
                self.transfer_wait_key = key
                self.transfer_started_at = now
                break
            end
        end
    end
    self.wave_holder = holder
    -- Ownership of the second parked add follows the non-Bigwig member of
    -- the pair. Invalidate only that tactical assignment; nobody is ordered
    -- away from the shared kill focus merely because Bigwig hate changed.
    self.parking_signature = nil
    return true
end

local function parking_key(self, adds, focus)
    local parts = {
        'wave-'..tostring(self.add_wave),
        self.wave_holder or 'holder-pending',
        focus and entity_key(focus) or 'no-focus',
    }
    for _, add in ipairs(adds) do
        parts[#parts + 1] = entity_key(add)
    end
    return table.concat(parts, '|')
end

local function rebuild_parking(self, adds, focus, now)
    local signature = parking_key(self, adds, focus)
    if signature == self.parking_signature then return false end

    local previous_anchors = self.anchor_owner_by_key or {}
    local previous_confirmed = self.anchor_confirmed_by_key or {}
    local previous_attempts = self.capture_attempt_owner_by_key or {}
    local previous_by_owner = {}
    for key, owner in pairs(previous_anchors) do
        previous_by_owner[owner] = tonumber(key:match('^(%d+):'))
    end

    local anchors, owners, targets = {}, {}, {}
    local astrologers, tormentors = {}, {}
    for _, add in ipairs(adds) do
        if add_rank(add) == 1 then
            astrologers[#astrologers + 1] = add
        else
            tormentors[#tormentors + 1] = add
        end
    end

    -- Stable Normal ownership is assigned before common-focus damage begins:
    -- Achoo anchors the Astrologer with /WHM Flash, Tackle anchors the first
    -- Tormentor with PLD Flash/Gaze, and the non-Bigwig Dolo/Kick member
    -- anchors the second with Light Shot or Box Step. Once released,
    -- every one of them may hit the focus without exceeding two hostiles.
    local astrologer = astrologers[1]
    if astrologer then
        anchors[entity_key(astrologer)] = ACHOO
    end
    local first = tormentors[1]
    if first then anchors[entity_key(first)] = TACKLE end
    local nonholder = self.wave_holder == DOLO and KICK
        or self.wave_holder == KICK and DOLO or nil
    local second = tormentors[2]
    if second and nonholder then
        anchors[entity_key(second)] = nonholder
    end

    for _, add in ipairs(adds) do
        local key = entity_key(add)
        local owner = anchors[key]
        if owner and (not focus or add.id ~= focus.id) then
            owners[key] = owner
            targets[owner] = add.id
        end
    end

    self.anchor_owner_by_key = anchors
    self.parked_owner_by_key = owners
    self.parked_target_by_owner = targets
    self.anchor_confirmed_by_key = {}
    self.capture_attempt_owner_by_key = {}
    for key, owner in pairs(anchors) do
        if previous_anchors[key] == owner then
            if previous_confirmed[key] == owner then
                self.anchor_confirmed_by_key[key] = owner
            end
            if previous_attempts[key] == owner then
                self.capture_attempt_owner_by_key[key] = owner
            end
        end
    end
    self.parking_signature = signature

    for _, owner in ipairs{TACKLE,DOLO,KICK,ACHOO} do
        local prior_id = previous_by_owner[owner]
        local next_id
        for key, assigned in pairs(anchors) do
            if assigned == owner then
                next_id = tonumber(key:match('^(%d+):'))
                break
            end
        end
        if next_id and next_id ~= prior_id then
            self.park_pickup_until[owner] = now + PARK_PICKUP_SECONDS
            local add = nil
            for _, candidate in ipairs(adds) do
                if candidate.id == next_id then add = candidate break end
            end
            local key = entity_key(add)
            if key then
                self.next_add_control[key] = now
                -- A holder swap can transfer this exact parked add from the
                -- other Dolo/Kick owner. Do not inherit that owner's
                -- one-repair lockout; the new owner gets a fresh drift
                -- episode and one bounded recapture opportunity.
                self.next_park_repair[key] = now
            end
        elseif not targets[owner] then
            self.park_pickup_until[owner] = nil
        end
    end
    self.next_add_pursuit = now + ADD_PURSUE_INTERVAL
    return true
end

local function subject_generation_key(self, subject)
    local key = entity_key(subject)
    if not key then return nil end
    return live_add(subject)
        and ('wave-'..tostring(self.add_wave)..':'..key)
        or ('boss:'..key)
end

local function prepare_subject(self, subject, now)
    local key = subject_generation_key(self, subject)
    if not key then return end
    local changed = self.current_subject_key ~= key
    if changed then
        self.current_subject_key = key
        self.frailty_subject_id = subject.id
        self.frailty_subject_key = key
        self.frailty_requested = false
    end
    local support = self.focus_support[key] or {
        subject_id=subject.id,
        dia_confirmed=false,
        dia_attempts=0,
        dia_next_at=0,
        dia_inflight_until=0,
        light_complete=false,
        light_attempts=0,
        light_next_at=0,
        light_inflight_until=0,
    }
    self.focus_support[key] = support
    if changed then
        -- Returning from an add to a previously prepared Bigwig (or revisiting
        -- another surviving focus) is a new support episode. Require fresh
        -- Dia proof before another Light Shot instead of trusting a pre-wave
        -- timer that may have expired while the party was elsewhere.
        support.subject_id = subject.id
        support.dia_confirmed = false
        support.dia_attempts = 0
        support.dia_next_at = now
        support.dia_inflight_until = 0
        support.light_complete = true
        support.light_inflight_until = 0
    end
    self.prepared_subjects[key] = true
end

local function select_subject(self, ctx, subject, now)
    local key = entity_key(subject)
    if not key then return end
    local decision_key = subject_generation_key(self, subject)
    if decision_key == self.forced_subject then
        if not self.wave_assembling then prepare_subject(self, subject, now) end
        return
    end
    local subject_changed = self.forced_subject_id ~= subject.id
    -- Retire stale subject-bound work without broadcasting adapter cancel.
    -- The adapters own no hidden action queue, and cancel would unnecessarily
    -- stop their independent Copy Image loss observers on every add death.
    if self.forced_subject and subject_changed then
        for task_key_value, task in pairs(self.tasks) do
            local hostile_subject = task.subject_domain == 'hostile'
            local controlled = hostile_subject and task.subject_id
                and ctx.mob_by_id(task.subject_id) or nil
            local owner = controlled
                and self.parked_owner_by_key[entity_key(controlled)] or nil
            local live_secondary_capture = live_add(controlled)
                and ((owner == TACKLE and task.recipient == TACKLE
                        and (task.semantic == 'flash-add'
                            or task.semantic == 'blank-gaze-add'))
                    or (owner == DOLO and task.recipient == DOLO
                        and task.semantic == 'light-shot-target')
                    or (owner == KICK and task.recipient == KICK
                        and task.semantic == 'stun-add'))
            if hostile_subject and task.subject_id ~= subject.id
                and not live_secondary_capture
            then
                self.tasks[task_key_value] = nil
            end
        end
    end
    self.forced_subject = decision_key
    self.forced_subject_id = subject.id
    if subject_changed then
        self.add_pursuit_arrived = {}
        self.next_add_pursuit = now + ADD_PURSUE_INTERVAL
    end
    if not self.wave_assembling then prepare_subject(self, subject, now) end
end

local function apply_combat_assignments(self, ctx, subject, now)
    if not self.pull_started then return end
    local desired = {}
    if live_add(subject) then
        if self.wave_assembling then
            -- Each visible spawn gets one owner immediately. Nobody else
            -- accumulates add enmity until the bounded quiet interval proves
            -- only that the server has stopped extending this wave for now.
            for key, owner in pairs(self.anchor_owner_by_key or {}) do
                local id = tonumber(key:match('^(%d+):'))
                if COMBAT_MEMBER_SET[owner] and live_add(ctx.mob_by_id(id)) then
                    desired[owner] = id
                end
            end
        else
            -- The anchors have had a full quiet interval to establish. Every
            -- combat member now collapses onto the Astrologer-first focus;
            -- a later drift or holder transfer gets one bounded pickup edge.
            for _, name in ipairs(COMBAT_MEMBERS) do
                local parked_id = self.parked_target_by_owner[name]
                if parked_id and now < (self.park_pickup_until[name] or 0)
                    and live_add(ctx.mob_by_id(parked_id))
                then
                    desired[name] = parked_id
                else
                    desired[name] = subject.id
                end
            end
        end
        for name in pairs(self.threat_holds or {}) do desired[name] = nil end
        if self.transfer_hold_owner then
            desired[self.transfer_hold_owner] = nil
        end
    else
        for _, name in ipairs(BOSS_KILLERS) do desired[name] = subject.id end
    end

    local changed = {}
    local stopped = {}
    local grouped = {}
    for _, name in ipairs(COMBAT_MEMBERS) do
        local wanted = desired[name] or false
        if self.combat_targets[name] ~= wanted then
            changed[#changed + 1] = name
            self.combat_targets[name] = wanted
            self.add_pursuit_arrived[name] = wanted and live_add(
                ctx.mob_by_id(wanted)) and {
                    target_id=wanted, assigned_at=now, progress_at=now,
                    arrived=false, repair_sent=false,
                    acquire_repair_sent=false,
                } or nil
            if wanted then
                grouped[wanted] = grouped[wanted] or {}
                grouped[wanted][#grouped[wanted] + 1] = name
            else
                stopped[#stopped + 1] = name
            end
        end
    end
    if #changed == 0 then return end

    -- A target-to-target handoff is one atomic exact edge. Sending /attack
    -- off first let its late packet erase the newer add target, which both
    -- stalled pursuit and left AutoWS2 firing at the previous battle target.
    -- Only a lane whose desired assignment is actually false is disengaged.
    if #stopped > 0 then ctx.actions.combat_stop_members(stopped) end
    local target_ids = {}
    for id in pairs(grouped) do target_ids[#target_ids + 1] = id end
    table.sort(target_ids)
    for _, id in ipairs(target_ids) do
        ctx.actions.combat_force_members(id, grouped[id])
    end
end

local function maintain_add_pursuit(self, ctx, now)
    if not self.adds_were_present or now < self.next_add_pursuit then return end
    self.next_add_pursuit = now + ADD_PURSUE_INTERVAL
    local separated = {}
    local threshold = ADD_PURSUE_SEPARATION * ADD_PURSUE_SEPARATION
    for _, name in ipairs(COMBAT_MEMBERS) do
        local target_id = self.combat_targets[name]
        local target = target_id and ctx.mob_by_id(target_id) or nil
        if live_add(target) then
            local state = self.add_pursuit_arrived[name]
            if type(state) ~= 'table' or state.target_id ~= target.id then
                state = {
                    target_id=target.id, assigned_at=now, progress_at=now,
                    arrived=false, repair_sent=false,
                    acquire_repair_sent=false,
                }
                self.add_pursuit_arrived[name] = state
            end
            local member = party_member(ctx, name)
            local separation = squared_separation(member, target)
            if member and (tonumber(member.hpp) or 0) > 0 and separation then
                local distance = math.sqrt(separation)
                if not state.last_separation
                    or state.last_separation - distance >= ADD_ACQUIRE_PROGRESS
                then
                    state.progress_at = now
                end
                state.last_separation = distance
                local attack = self.member_attack_targets[name]
                if attack and attack.target_id == target.id
                    and attack.at >= state.assigned_at
                then
                    state.attack_confirmed = true
                end
                if separation <= threshold then
                    state.arrived = true
                    state.repair_sent = false
                elseif state.arrived and not state.repair_sent then
                    separated[target.id] = separated[target.id] or {}
                    separated[target.id][#separated[target.id] + 1] = name
                    -- One repair edge, then yield. A manual disengage/target
                    -- change after this edge cannot be countermanded by an
                    -- endless 1.25-second profile loop.
                    state.arrived = false
                    state.repair_sent = true
                    state.acquire_repair_sent = true
                end
                if not state.attack_confirmed
                    and not state.acquire_repair_sent
                    and now - state.assigned_at >= ADD_ACQUIRE_REPAIR_AFTER
                    and (state.arrived
                        or now - state.progress_at >= ADD_ACQUIRE_REPAIR_AFTER)
                then
                    separated[target.id] = separated[target.id] or {}
                    separated[target.id][#separated[target.id] + 1] = name
                    -- One acquisition repair covers a dropped initial IPC,
                    -- a stale battle target, or a client that never started
                    -- closing. Progressing distant clients are left alone.
                    -- This does not poll-force over later manual overrides.
                    state.acquire_repair_sent = true
                end
            end
        end
    end
    for target_id, members in pairs(separated) do
        ctx.actions.combat_force_members(target_id, members)
    end
end

local function maintain_subject_support(self, ctx, subject, now)
    if self.wave_assembling then return end
    local key = subject_generation_key(self, subject)
    if key == self.frailty_subject_key and not self.frailty_requested
        and subject.id == self.frailty_subject_id
    then
        local achoo = party_member(ctx, ACHOO)
        local separation = squared_separation(achoo, subject)
        if separation and separation <= 20 * 20 then
            schedule(self, ACHOO, 'frailty-target', now,
                'focus-frailty-'..key, 25, subject.id)
            self.frailty_requested = true
        end
    end

    local support = self.focus_support[key]
    if support and support.subject_id == subject.id
        and not support.dia_confirmed
        and support.dia_attempts < DIA_MAX_ATTEMPTS
        and now >= (support.dia_next_at or 0)
        and now >= (support.dia_inflight_until or 0)
    then
        local family = 'focus-dia-'..key
        local pending = self.tasks[task_key(SMALLS, 'dia-iii', family)]
        local smalls = party_member(ctx, SMALLS)
        local separation = squared_separation(smalls, subject)
        if not pending and separation
            and separation <= 20.5 * 20.5
        then
            -- An issued command is not success. Count the attempt only when
            -- it leaves the coordinator, then retry unless Smalls' action
            -- packet confirms Dia on this exact focus.
            schedule(self, SMALLS, 'dia-iii', now, family,
                live_add(subject) and 30 or 20, subject.id,
                {kind='focus-dia', key=key})
        end
    end
    if support and support.subject_id == subject.id
        and support.dia_confirmed and not support.light_complete
        and support.light_attempts < LIGHT_SHOT_MAX_ATTEMPTS
        and now >= (support.light_next_at or 0)
        and now >= (support.light_inflight_until or 0)
    then
        local family = 'focus-light-shot-'..key
        local pending = self.tasks[
            task_key(DOLO, 'light-shot-target', family)]
        local dolo = party_member(ctx, DOLO)
        local separation = squared_separation(dolo, subject)
        if not pending and separation
            and separation <= LIGHT_SHOT_RANGE * LIGHT_SHOT_RANGE
        then
            schedule(self, DOLO, 'light-shot-target', now, family,
                35, subject.id, {kind='focus-light', key=key})
        end
    end
end

local function wail_state(self, subject)
    local key = subject_generation_key(self, subject)
    if not key then return nil, nil end
    local state = self.wail_buffs[key]
    if not state then
        state = {
            subject_id=subject.id,
            buffs={},
            marked_at={},
            attempts=0,
            next_at=0,
        }
        self.wail_buffs[key] = state
    end
    return state, key
end

local function mark_wail(self, subject, name, now)
    local state = wail_state(self, subject)
    if not state then return end
    local previous = state.marked_at[name]
    if not previous or now - previous >= EVENT_DEDUPE then
        state.attempts = 0
        state.next_at = now
    end
    state.buffs[name] = true
    state.marked_at[name] = now
end

local function pending_wail_count(state)
    local count = 0
    for _ in pairs(state and state.buffs or {}) do count = count + 1 end
    return count
end

local function maintain_focus_dispel(self, subject, now)
    if self.wave_assembling or not live_add(subject) then return end
    local key = subject_generation_key(self, subject)
    local state = key and self.wail_buffs[key] or nil
    if not state or state.subject_id ~= subject.id
        or pending_wail_count(state) == 0
        or state.attempts >= FOCUS_DISPEL_MAX_ATTEMPTS
        or now < (state.next_at or 0)
    then
        return
    end

    for _, task in pairs(self.tasks) do
        local tracking = task.tracking
        if tracking and tracking.kind == 'focus-wail'
            and tracking.key == key and task.subject_id == subject.id
        then
            -- Count attempts only when they actually leave run_tasks. A Cure
            -- hold therefore retains one exact cleanup request instead of
            -- exhausting the retry budget with undispatched timestamp work.
            return
        end
    end

    -- Only the common kill target is stripped. Tackle's exact Blank Gaze is
    -- first because it is MP-free for Smalls and cannot create a third
    -- off-focus enmity lane; exact RDM Dispel is the alternating fallback.
    local tackle_turn = state.attempts % 2 == 0
    local recipient = tackle_turn and TACKLE or SMALLS
    local semantic = tackle_turn and 'blank-gaze-add'
        or 'dispel-ice-spikes'
    schedule(self, recipient, semantic, now,
        'focus-wail-'..key..'-'..tostring(state.attempts + 1),
        125, subject.id, {kind='focus-wail', key=key})
end

local function schedule_debuffs(self, now, boss)
    local family = 'debuff-'..tostring(math.floor(now * 10))
    local key = subject_generation_key(self, boss)
    local support = key == self.current_subject_key
        and self.focus_support[key] or nil
    if support and support.subject_id == boss.id then
        -- Periodic Dia refresh uses the same result-confirmed transaction as
        -- a new focus. The next support tick issues its bounded exact request.
        support.dia_confirmed = false
        support.dia_attempts = 0
        support.dia_next_at = now
        support.dia_inflight_until = 0
        support.light_complete = true
        support.light_inflight_until = 0
    end
    schedule(self, SMALLS, 'slow-ii', now + 1.25,
        family..'-slow', 20, boss.id)
    schedule(self, SMALLS, 'paralyze-ii', now + 2.5,
        family..'-paralyze', 20, boss.id)
end

local function safe_area_control(ctx, boss, add)
    local tackle = party_member(ctx, TACKLE)
    if not tackle then return false end
    local boss_add = squared_separation(boss, add)
    local tackle_add = squared_separation(tackle, add)
    return boss_add ~= nil and tackle_add ~= nil
        and boss_add >= SAFE_ADD_CONTROL_SEPARATION
            * SAFE_ADD_CONTROL_SEPARATION
        and tackle_add <= ADD_PURSUE_SEPARATION * ADD_PURSUE_SEPARATION
end

local function schedule_add_control(self, ctx, boss, adds, now)
    for _, mob in ipairs(adds) do
        local key = entity_key(mob)
        local owner = self.anchor_owner_by_key[key]
        if not self.seen_adds[key] then
            self.seen_adds[key] = true
            self.next_add_control[key] = now
            self.next_add_silence[key] = now
        end
        local pickup_active = owner and (
            self.wave_assembling
            or self.combat_targets[owner] == mob.id
            or now < (self.park_pickup_until[owner] or 0))
        -- Dolo's Light Shot is a claim tool only during initial anchoring or
        -- a confirmed parked-add repair. On a shared focus it belongs solely
        -- to the Dia -> Light Shot sequence below.
        if owner == DOLO and not self.wave_assembling
            and now >= (self.park_pickup_until[owner] or 0)
        then
            pickup_active = false
        end
        local confirmed = owner
            and self.anchor_confirmed_by_key[key] == owner
        if pickup_active and confirmed then
            -- Stable direct ownership ends the control cadence. The unique
            -- combat assignment remains during assembly, but there is no
            -- reason to spend another spell or ability until drift is seen.
            self.next_add_control[key] = math.huge
        elseif pickup_active and now >= (self.next_add_control[key] or 0) then
            local family = 'add-'..key..'-'..tostring(math.floor(now))
            if owner == TACKLE then
                schedule(self, TACKLE, 'flash-add', now,
                    family..'-flash', 100, mob.id)
                schedule(self, TACKLE, 'blank-gaze-add', now + 1.25,
                    family..'-gaze', 90, mob.id)
            elseif owner == DOLO then
                -- Light Shot is one exact tag per ownership episode. Its
                -- Sleep result is not ownership proof; Dolo remains engaged
                -- until the add's own direct action confirms its target. If
                -- known coordinates put him beyond Quick Draw range, let the
                -- exact combat assignment close first instead of consuming
                -- the episode on an out-of-range command.
                local actor = party_member(ctx, DOLO)
                local separation = squared_separation(actor, mob)
                local in_range = separation == nil
                    or separation <= LIGHT_SHOT_RANGE * LIGHT_SHOT_RANGE
                if self.capture_attempt_owner_by_key[key] ~= owner
                    and in_range
                then
                    schedule(self, DOLO, 'light-shot-target', now,
                        family..'-park-shot', 85, mob.id)
                    self.capture_attempt_owner_by_key[key] = owner
                end
            elseif owner == KICK then
                -- Box Step is a valid exact enmity tag and creates finishing
                -- stock. Routine pickup must never assume Violent Flourish is
                -- available; that ability is reserved for reactive stuns.
                -- Wait for known melee arrival so the one automatic Step is
                -- not burned while PartyCombat is still closing distance.
                local actor = party_member(ctx, KICK)
                local separation = squared_separation(actor, mob)
                local in_range = separation == nil
                    or separation <= ADD_PURSUE_SEPARATION
                        * ADD_PURSUE_SEPARATION
                if self.capture_attempt_owner_by_key[key] ~= owner
                    and in_range
                then
                    schedule(self, KICK, 'box-step-add', now,
                        family..'-park-step', 85, mob.id)
                    self.capture_attempt_owner_by_key[key] = owner
                end
            elseif owner == ACHOO then
                -- GEO/WHM has native Flash. It gives the Astrologer a fast,
                -- exact anchor before Smalls' Silence or common-focus damage
                -- can pull that add onto Bigwig's holder.
                schedule(self, ACHOO, 'flash-add', now,
                    family..'-geo-flash', 100, mob.id)
            end
            if owner == DOLO or owner == KICK then
                -- A direct hostile-target observation, not an action attempt,
                -- ends this capture episode. Until then the exact combat
                -- assignment builds hate without a three-second ability loop.
                self.next_add_control[key] =
                    self.capture_attempt_owner_by_key[key] == owner
                        and math.huge or now + ADD_PURSUE_INTERVAL
            else
                self.next_add_control[key] = now + ANCHOR_CAPTURE_RETRY
            end
        end
        if add_rank(mob) == 1
            and now >= (self.next_add_silence[key] or 0)
        then
            -- Silence is long-lived. Repeating it every eight seconds spent
            -- Smalls' MP and action slots without improving control. Ice
            -- Spikes and Wail are handled from their actual action packets.
            schedule(self, SMALLS, 'silence-add', now,
                'silence-'..key..'-'..tostring(math.floor(now)), 60, mob.id)
            self.next_add_silence[key] = now + 45
        end
    end

    -- Three-target AoE enmity is forbidden on Normal and above: it is exactly
    -- the convergence that unlocked the fatal Triple Reversal. The sequence
    -- remains available on VE/E, where no more than two adds can target him.
    local subject = adds[1]
    if subject and not self.wave_assembling and #adds <= 2
        and now >= self.next_pack_control
        and safe_area_control(ctx, boss, subject)
    then
        local family = 'pack-'..tostring(self.add_wave)..'-'
            ..tostring(math.floor(now))
        schedule(self, TACKLE, 'jettatura-add', now + .5,
            family..'-jettatura', 60, subject.id)
        schedule(self, TACKLE, 'sheep-song-add', now + 1.75,
            family..'-sheep', 55, subject.id)
        schedule(self, TACKLE, 'geist-wall-add', now + 3,
            family..'-geist', 50, subject.id)
        self.next_pack_control = now + PACK_CONTROL_INTERVAL
    end
end

local function schedule_emergency_healing(self, ctx, now)
    if now < (self.next_support_heal or 0) then return end
    self.next_support_heal = now + EMERGENCY_HEAL_POLL

    local primary = lowest_cure_member(ctx, SMALLS, RDM_HEAL_PRIORITY_HPP)
    local smalls_key = task_key(
        SMALLS, 'support-cure', 'smalls-primary-heal')
    if primary then
        -- One stable task follows the currently lowest exact party member.
        -- Replacing that subject on the next poll cannot create a stale cure
        -- backlog, and Smalls' unrelated tactical work remains queued until
        -- every living member has recovered above the primary-heal band.
        schedule(self, SMALLS, 'support-cure', now,
            'smalls-primary-heal', 150, primary.id, nil, 'party')
    else
        self.tasks[smalls_key] = nil
    end

    local lowest = lowest_cure_member(ctx, TACKLE, TACKLE_EMERGENCY_HPP)
    local tackle_key = task_key(
        TACKLE, 'emergency-cure', 'tackle-emergency-heal')
    if not lowest then
        self.tasks[tackle_key] = nil
        return
    end

    local tackle = party_member(ctx, TACKLE)
    if not tackle or (tonumber(tackle.hpp) or 0) <= 0 then
        self.tasks[tackle_key] = nil
        return
    end
    local pending = self.tasks[tackle_key]
    if not pending or pending.subject_id ~= lowest.id
    then
        -- This remains an independent delayed PLD backstop. Its adapter
        -- rechecks the exact member, so a successful Smalls cure turns it
        -- into a no-op without coupling either healer's task lifecycle.
        schedule(self, TACKLE, 'emergency-cure',
            now + TACKLE_EMERGENCY_DELAY, 'tackle-emergency-heal',
            135, lowest.id, nil, 'party')
    end
end

local function defensive_maintenance_tick(self, ctx, now)
    if now >= self.next_shadow then
        for _, name in ipairs(SHADOW_USERS) do
            -- Stable task families overwrite a delayed retry instead of
            -- building an unbounded per-tick shadow backlog.
            local family = 'shadow-maintenance'
            schedule(self, name, 'shadow-ni', now,
                family..'-ni', 25)
            schedule(self, name, 'shadow-ichi',
                now + SHADOW_ICHI_FALLBACK, family..'-ichi', 24)
        end
        self.next_shadow = now + SHADOW_INTERVAL
    end
    if now >= self.next_cocoon then
        schedule(self, TACKLE, 'cocoon', now,
            'cocoon-'..tostring(math.floor(now)), 25)
        self.next_cocoon = now + COCOON_INTERVAL
    end
    if now >= self.next_crusade then
        schedule(self, TACKLE, 'crusade', now,
            'crusade-'..tostring(math.floor(now)), 35)
        self.next_crusade = now + CRUSADE_INTERVAL
    end
    if now >= self.next_reprisal then
        schedule(self, TACKLE, 'reprisal', now,
            'reprisal-'..tostring(math.floor(now)), 30)
        self.next_reprisal = now + REPRISAL_INTERVAL
    end
    if now >= self.next_reraise then
        for _, name in ipairs(MEMBERS) do
            schedule(self, name, 'reraise', now,
                'reraise-'..name..'-'..tostring(math.floor(now)), 70)
        end
        self.next_reraise = now + RERAISE_INTERVAL
    end
    schedule_emergency_healing(self, ctx, now)
end

local function maintenance_tick(self, ctx, boss, adds, now)
    defensive_maintenance_tick(self, ctx, now)
    if now >= self.next_geo then
        local geo_subject = adds[1] or boss
        schedule(self, ACHOO, 'frailty-target', now,
            'geo-'..tostring(math.floor(now)), 20, geo_subject.id)
        self.next_geo = now + GEO_INTERVAL
    end
    if #adds == 0 and now >= self.next_debuff then
        schedule_debuffs(self, now, boss)
        self.next_debuff = now + DEBUFF_INTERVAL
    end
    if #adds == 0 and (tonumber(boss.hpp) or 100) <= 35
        and now >= self.next_low_hp_magic
    then
        local family = 'lowhp-'..tostring(math.floor(now))
        schedule(self, SMALLS, 'diaga', now, family..'-diaga', 45,
            boss.id)
        schedule(self, SMALLS, 'silence-boss', now + 1.25,
            family..'-silence', 40, boss.id)
        self.next_low_hp_magic = now + LOW_HP_MAGIC_INTERVAL
    end
    schedule_add_control(self, ctx, boss, adds, now)
end

local function action_name(ctx, action)
    if type(action) ~= 'table' then return nil end
    if action.category == 6 then
        local ability = ctx.job_ability(action.param)
        if ability then return ability.en end
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                ability = ctx.job_ability(result.param)
                if ability then return ability.en end
            end
        end
    elseif action.category == 7 then
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                local ability = ctx.monster_ability(result.param)
                    or ctx.job_ability(result.param)
                if ability then return ability.en end
            end
        end
    elseif action.category == 4 or action.category == 8 then
        local spell = ctx.spell(action.param)
        if spell then return spell.en end
        for _, target in ipairs(action.targets or {}) do
            for _, result in ipairs(target.actions or {}) do
                spell = ctx.spell(result.param)
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

local function target_has_message(action, target_id, messages)
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id) then
            for _, result in ipairs(target.actions or {}) do
                if messages[tonumber(result.message)] then return true end
            end
        end
    end
    return false
end

local function target_has_result(action, target_id)
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id)
            and type(target.actions) == 'table' and #target.actions > 0
        then
            return true
        end
    end
    return false
end

local function removed_wail_name(action, target_id)
    for _, target in ipairs(action.targets or {}) do
        if tonumber(target.id) == tonumber(target_id) then
            for _, result in ipairs(target.actions or {}) do
                if DISPEL_SUCCESS_MESSAGES[tonumber(result.message)] then
                    local name = WAIL_STATUS_BY_BUFF_ID[
                        tonumber(result.param)]
                    if name then return name end
                end
            end
        end
    end
    return nil
end

local function clear_wail_buff(self, subject, name, now)
    local key = subject_generation_key(self, subject)
    local state = key and self.wail_buffs[key] or nil
    if not state or not state.buffs[name] then return end
    state.buffs[name] = nil
    state.attempts = 0
    state.next_at = now + .75
    if pending_wail_count(state) == 0 then
        self.wail_buffs[key] = nil
        for task_key_value, task in pairs(self.tasks) do
            local tracking = task.tracking
            if tracking and tracking.kind == 'focus-wail'
                and tracking.key == key
            then
                self.tasks[task_key_value] = nil
            end
        end
    end
end

local function wake_subject(ctx, action)
    -- Center Curaga II on the affected melee pack whenever possible. The two
    -- independent healers are kept at range, so either may be the awake one.
    for _, preferred in ipairs{TACKLE,KICK,BARNEY,DOLO,SMALLS,ACHOO} do
        for _, target in ipairs(action.targets or {}) do
            local mob = target.id and ctx.mob_by_id(target.id) or nil
            if mob and mob.name == preferred then return mob end
        end
    end
    return nil
end

local function event_once(self, key, now)
    if now - (self.last_event[key] or -100000) < EVENT_DEDUPE then
        return false
    end
    self.last_event[key] = now
    return true
end

local function observe_boss_target(self, ctx, action, now)
    if tonumber(action.actor_id) ~= self.encounter_id then return end
    -- A hostile spell can select someone other than the enmity leader (the
    -- live Astrologer Bind packet did exactly that). Only melee/TP-action
    -- categories may update Bars-equivalent ownership.
    if action.category ~= 1 and action.category ~= 7
        and action.category ~= 11
    then return end
    local target_id = action_primary_target_id(action)
    local target_name = party_member_name_by_id(ctx, target_id)
    if not target_name then return end
    self.boss_target_id = target_id
    self.boss_target_name = target_name
    self.boss_target_at = now

    -- If a wave began without fresh evidence, let the next tick establish the
    -- first holder. Once established, reassessment stays on the five-second
    -- cadence so ordinary Dolo/Kick hate bounces do not thrash assignments.
    if self.adds_were_present and BOSS_HOLDER_SET[target_name]
        and (not self.wave_holder or self.wave_assembling)
    then
        self.next_holder_review = now
    end
end

local function observe_parked_target(self, ctx, source, action, now)
    if not live_add(source)
        or (action.category ~= 1 and action.category ~= 7
            and action.category ~= 11)
    then return end
    local key = entity_key(source)
    local target_name = party_member_name_by_id(
        ctx, action_primary_target_id(action))
    if not target_name then return end
    self.add_target_by_key[key] = {name=target_name, at=now}

    -- An attempted Flash, Light Shot, Step, or Flourish is never ownership
    -- evidence. Only the add's own direct melee/TP target confirms its anchor.
    local anchor = self.anchor_owner_by_key[key]
    if anchor and target_name == anchor then
        self.anchor_confirmed_by_key[key] = anchor
        if self.parked_target_by_owner[anchor] == source.id then
            self.park_pickup_until[anchor] = now
        end
    elseif anchor then
        self.anchor_confirmed_by_key[key] = nil
    end

    if key == self.transfer_wait_key then
        local owner = self.anchor_owner_by_key[key]
        if owner and target_name == owner
            and now >= (self.transfer_started_at or now)
        then
            self.transfer_hold_owner = nil
            self.transfer_wait_key = nil
            self.transfer_started_at = nil
        end
    end

    local owner = self.parked_owner_by_key[key]
    if not owner then
        local anchor = self.anchor_owner_by_key[key]
        if anchor and target_name ~= anchor then self.next_add_control[key] = now end
        return
    end
    if target_name == owner then
        if self.next_park_repair[key] == math.huge then
            self.next_park_repair[key] = now + PARK_REPAIR_INTERVAL
        end
        return
    end
    if now < (self.next_park_repair[key] or 0) then return end

    -- A parked Tormentor has become squirmy. Give only its designated owner a
    -- short exact pickup edge, refresh that owner's control action, then let
    -- apply_combat_assignments return the owner to the common kill focus.
    self.park_pickup_until[owner] = now + PARK_PICKUP_SECONDS
    self.next_add_control[key] = now
    self.capture_attempt_owner_by_key[key] = nil
    -- One repair per drift episode. It rearms only after the add is observed
    -- targeting its owner, so a manual override can never fight a timer loop.
    self.next_park_repair[key] = math.huge
end

local function update_threat_holds(self, ctx, boss, adds, now)
    local counts = {}
    local function add_target(name)
        if name then counts[name] = (counts[name] or 0) + 1 end
    end
    if live_boss(boss) then add_target(self.boss_target_name) end
    for _, add in ipairs(adds) do
        local observed = self.add_target_by_key[entity_key(add)]
        if observed then add_target(observed.name) end
    end

    local dangerous = {}
    for name, count in pairs(counts) do
        if count >= 3 then
            dangerous[name] = true
            -- Every uniquely assigned anchor gets an immediate exact reclaim
            -- attempt. The threatened combat member receives one stop edge;
            -- it is released automatically when direct targets redistribute.
            for _, add in ipairs(adds) do
                local key = entity_key(add)
                local observed = self.add_target_by_key[key]
                local owner = self.anchor_owner_by_key[key]
                if observed and observed.name == name and owner ~= name then
                    self.next_add_control[key] = now
                end
            end
        end
    end
    for name in pairs(self.threat_holds) do
        if not dangerous[name] then self.threat_holds[name] = nil end
    end
    for name in pairs(dangerous) do
        if COMBAT_MEMBER_SET[name] then self.threat_holds[name] = true end
    end

    if self.transfer_wait_key then
        local controlled = ctx.mob_by_id(tonumber(
            self.transfer_wait_key:match('^(%d+):')))
        if not live_add(controlled) then
            self.transfer_hold_owner = nil
            self.transfer_wait_key = nil
            self.transfer_started_at = nil
        end
    end
end

local function runtime_on_activate(self, ctx)
    self.active = true
    self.next_poll = 0
    clear(self)
end

local function runtime_on_deactivate(self, ctx)
    if ctx.player_name() == DOLO then
        if self.encounter_id then finish(self, ctx)
        else ctx.actions.combat_stop() end
    end
    clear(self)
    self.active = false
end

local function runtime_on_status(self, ctx, proof)
    -- Status reports remain useful telemetry, but no status proof controls a
    -- cooperative action lane.
    return false
end

local function runtime_on_action(self, ctx, action)
    if not self.active or ctx.player_name() ~= DOLO
        or not ZONES[ctx.zone_id()] or ctx.operator_armed() ~= true
        or not self.encounter_id or type(action) ~= 'table'
    then
        return
    end
    local now = ctx.now()
    local source = ctx.mob_by_id(action.actor_id)
    if not source then return end
    if COMBAT_MEMBER_SET[source.name]
        and (action.category == 1 or action.category == 2
            or action.category == 3)
    then
        local target = action.targets and action.targets[1]
        if target and uint32(target.id) then
            self.member_attack_targets[source.name] = {
                target_id=target.id, at=now,
            }
        end
    end
    if not self.pull_started then
        local boss = ctx.mob_by_id(self.encounter_id)
        if live_boss(boss)
            and action_starts_combat(self, ctx, source, action)
        then
            start_combat(self, boss, now)
        else
            return
        end
    end
    observe_boss_target(self, ctx, action, now)
    observe_parked_target(self, ctx, source, action, now)
    local name = action_name(ctx, action)
    if not name then return end

    if action.category == 4 and source.name == SMALLS and name == 'Dia III' then
        local target = action.targets and action.targets[1]
        local subject = target and ctx.mob_by_id(target.id) or nil
        local key = subject and subject_generation_key(self, subject) or nil
        if key and key == self.current_subject_key
            and subject.id == self.forced_subject_id
        then
            local support = self.focus_support[key] or {
                subject_id=subject.id,
                dia_confirmed=false,
                dia_attempts=0,
                dia_next_at=0,
                dia_inflight_until=0,
                light_complete=false,
                light_attempts=0,
                light_next_at=0,
                light_inflight_until=0,
            }
            self.focus_support[key] = support
            support.dia_inflight_until = 0
            if target_has_message(action, subject.id, DIA_LAND_MESSAGES) then
                support.dia_confirmed = true
                support.light_complete = false
                support.light_attempts = 0
                support.light_next_at = now
                support.light_inflight_until = 0
            else
                -- A resist/no-effect/error packet is an observed failure.
                -- Re-open only this focus's Dia lane after a short delay.
                support.dia_confirmed = false
                support.dia_next_at = now + DIA_RETRY
            end
        end
    end

    if action.category == 6 and source.name == DOLO
        and name == 'Light Shot'
    then
        local target = action.targets and action.targets[1]
        local subject = target and ctx.mob_by_id(target.id) or nil
        local key = subject and subject_generation_key(self, subject) or nil
        local support = key and self.focus_support[key] or nil
        if support and support.dia_confirmed
            and support.subject_id == subject.id
            and support.light_attempts > 0
        then
            support.light_inflight_until = 0
            if target_has_result(action, subject.id) then
                support.light_complete = true
            end
        end
    end

    if action.category == 4
        and (source.name == TACKLE and name == 'Blank Gaze'
            or source.name == SMALLS and name == 'Dispel')
    then
        local target = action.targets and action.targets[1]
        local subject = target and ctx.mob_by_id(target.id) or nil
        local removed = live_add(subject)
            and removed_wail_name(action, subject.id) or nil
        if removed then
            clear_wail_buff(self, subject, removed, now)
        end
    end

    if name == 'Triple Reversal'
        and (source.id == self.encounter_id or live_add(source))
        and event_once(self, 'triple-'..entity_key(source), now)
    then
        schedule(self, KICK, 'stun-add', now,
            'triple-'..entity_key(source)..'-stun', 100, source.id)
    elseif name == 'Ice Spikes' and add_rank(source) == 1
        and event_once(self, 'spikes-'..entity_key(source), now)
    then
        schedule(self, SMALLS, 'dispel-ice-spikes', now,
            'spikes-'..entity_key(source)..'-dispel', 90, source.id)
    elseif (name == 'Fortifying Wail' or name == 'Animating Wail')
        and live_add(source)
    then
        -- Record every actual recipient. Cleanup waits until that add is the
        -- shared kill focus, so neither Tackle nor Smalls acquires a third
        -- hostile lane by stripping a parked target.
        mark_wail(self, source, name, now)
        for _, target in ipairs(action.targets or {}) do
            local mob = target.id and ctx.mob_by_id(target.id) or nil
            if live_add(mob) then mark_wail(self, mob, name, now) end
        end
    elseif name == 'Utsusemi: San' and source.id == self.encounter_id
        and event_once(self, 'san', now)
    then
        schedule(self, SMALLS, 'diaga', now, 'san-diaga', 90,
            self.encounter_id)
    elseif name == 'Phantom Whorl' and source.id == self.encounter_id
        and event_once(self, 'phantom-whorl', now)
    then
        -- Whorl is a one-hit shadow check. Top every eligible boss-side lane
        -- as soon as it readies; the adapter suppresses Ni at 3+ copies and
        -- Ichi whenever any copy remains.
        for _, member in ipairs(SHADOW_USERS) do
            local family = 'phantom-whorl-'..member
            schedule(self, member, 'shadow-ni', now,
                family..'-ni', 160)
            schedule(self, member, 'shadow-ichi',
                now + SHADOW_ICHI_FALLBACK, family..'-ichi', 159)
        end
    elseif action.category == 4 and add_rank(source) == 1
        and SLEEP_SPELLS[name]
        and event_once(self, 'wake-'..entity_key(source)..'-'..name, now)
    then
        local subject = wake_subject(ctx, action)
        if subject then
            local family = 'wake-'..entity_key(source)..'-'
                ..tostring(math.floor(now * 10))
            schedule(self, SMALLS, 'wake-pack', now,
                family..'-rdm', 120, subject.id, nil, 'party')
            schedule(self, ACHOO, 'wake-pack', now + .75,
                family..'-geo', 119, subject.id, nil, 'party')
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

    if not ZONES[ctx.zone_id()] then
        if self.encounter_id then finish(self, ctx) end
        return
    end

    -- This is the only automation start/stop switch. There are no ACK,
    -- diagnostic, controller, job, buff, item, geometry, result, or setup
    -- prerequisites behind it.
    if ctx.operator_armed() ~= true then
        if self.encounter_id then finish(self, ctx) end
        return
    end

    local boss
    if self.encounter_id then
        boss = resolved_boss(self, ctx, now)
        if not self.encounter_id then return end
    else
        boss = scan_boss(ctx)
        if boss then bind(self, ctx, boss, now) end
    end
    if not boss then return end

    if not self.pull_started and ctx.party_claimed(boss) then
        start_combat(self, boss, now)
    end
    if not self.pull_started then
        -- Armed preparation is deliberately inert toward enemies. Defensive
        -- upkeep and exact healing may continue for as long as the operator
        -- wants to buff; the manual Bigwig pull is the only release edge.
        defensive_maintenance_tick(self, ctx, now)
        run_tasks(self, ctx, now)
        return
    end

    local adds = scan_adds(ctx, boss)
    update_add_wave(self, ctx, adds, now)

    -- Bigwig ownership is refreshed every five seconds while adds live. It
    -- changes only which Dolo/Kick member briefly services the second parked
    -- add; both remain on the shared focus and Bigwig follows its hate holder
    -- into that group. There is no wave-long corner latch.
    review_wave_holder(self, now)
    local subject = adds[1] or boss
    if #adds > 0 then rebuild_parking(self, adds, subject, now) end
    select_subject(self, ctx, subject, now)
    update_threat_holds(self, ctx, boss, adds, now)
    apply_combat_assignments(self, ctx, subject, now)
    maintain_add_pursuit(self, ctx, now)
    maintain_subject_support(self, ctx, subject, now)
    maintain_focus_dispel(self, subject, now)

    maintenance_tick(self, ctx, boss, adds, now)

    -- Tasks scheduled above can run in the same tick when their recipient is
    -- free. A blocked recipient cannot suppress another character's lane.
    run_tasks(self, ctx, now)
end

function M.create()
    local self = {
        active=false,
        next_poll=0,
        on_activate=runtime_on_activate,
        on_deactivate=runtime_on_deactivate,
        on_status=runtime_on_status,
        on_action=runtime_on_action,
        on_tick=runtime_on_tick,
    }
    clear(self)
    return self
end

return M
