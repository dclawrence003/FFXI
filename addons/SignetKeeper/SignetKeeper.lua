_addon.name = 'SignetKeeper'
_addon.author = 'OpenAI Codex'
_addon.version = '2.3.4'
_addon.commands = {'sk', 'signetkeeper'}

local extdata = nil
do
    local ok, library = pcall(require, 'extdata')
    if ok and type(library) == 'table'
        and type(library.decode) == 'function'
    then
        extdata = library
    end
end

local SIGNET_BUFF_ID = 253
local STAFF_ID = 17583
local STAFF_NAME = 'Kgd. Signet Staff'
local LOCUS_PROFILE_ID = 'locus-dire-bats-tomb-signet'
local EXPECTED_ROSTER_SIZE = 6
local OWNED_ZONE = 190
local PREFIX = 'SIGNETKEEPER1'
local PT_PREFIX = 'PARTYTACTICS1'
local ADAPTER_CONTROLLER = 'locus-signet'
local ADAPTER_PROTOCOL = '2'
local REPORT_INTERVAL = 1
local REPORT_STALE_AFTER = 4
local ROSTER_STATE_STALE_AFTER = 30
-- Census release is replicated state, not a one-shot event. Re-advertise it
-- slowly while all six reports remain fresh so a Tackleberry helper that was
-- still starting (or missed one IPC packet) cannot remain OFF forever.
local CENSUS_REPAIR_INTERVAL = 2
local PHASE_REPAIR_INTERVAL = 1
local ADAPTER_RETRY_INTERVAL = 1
local EMERGENCY_REQUEST_RETRY_INTERVAL = 1
-- The pinned GearSwap adapter repeats its exact local operator tuple on every
-- PartyTactics heartbeat. That local command crosses addon boundaries; raw
-- PartyTactics IPC does not. Allow a generous scheduler stall before treating
-- the control authority as gone; exact stop/replacement fences stay immediate.
local CONTROL_LEASE_STALE_AFTER = 30
local ANY_MISSING_CONFIRM = 2
local ALL_IDLE_CONFIRM = 2
local ALL_RESTORED_CONFIRM = 1
-- BGWiki lists a 30-second enchantment activation delay, but the six-client
-- live cycle showed every command at 30.5 seconds being silently discarded
-- and every retry at 42.5 seconds succeeding. Use that empirically proven
-- boundary for the first attempt; losing twelve seconds once per Signet timer
-- is preferable to manufacturing a predictable failed action.
local STAFF_USE_DELAY = 42.5
local STAFF_REUSE_DELAY = 12
local STAFF_ATTEMPT_CHAT_INTERVAL = 60
local EQUIP_RETRY_DELAY = 3
local LOCK_REFRESH_INTERVAL = 2
local WEAPON_RESTORE_RETRY_INTERVAL = 2
local WEAPON_RESTORE_CONFIRM = 1
local WEAPON_RESTORE_CHAT_INTERVAL = 30
local WEAPON_RESTORE_COMMAND =
    'gs enable main sub; gs c weapons; gs c update auto'
-- The profile-local GearSwap adapter survives a raw SignetKeeper reload. This
-- process-clock token lets that adapter distinguish an idempotent ACK from a
-- new keeper instance without weakening generation/epoch authority. os.clock
-- is monotonic for the lifetime of this pol.exe; a new pol.exe also creates a
-- fresh GearSwap adapter, where the first token is simply the baseline.
local INSTANCE_NONCE = ('%d-%d'):format(os.time(),
    math.floor(os.clock() * 1000000))
local PULLER_DRAIN_RETRY_INTERVAL = 1
local GS_RELOAD_GRACE = 25
local EQUIPPABLE_BAG_IDS = {0, 8, 10, 11, 12, 13, 14, 15, 16}

-- This tiny handoff survives only an exact full-profile reapply in this addon
-- process. It never survives zone/logout/off teardown or its short deadline.
local reload_handoff = nil
local pending_authority = nil
local terminal_restore = nil
local retired_authorities = {}
local stopped_generations = {}
-- Diagnostics only: terminal teardown clears live authority, but status must
-- still identify the last exact reason and authority after that reset.
local last_terminal = nil

local function remember_terminal(reason, generation, epoch)
    if generation == nil then return end
    last_terminal = {
        reason = reason or 'coordinator',
        generation = generation,
        epoch = epoch,
    }
end

local state = {
    armed = false,
    generation = nil,
    apply_epoch = nil,
    leader = nil,
    roster = {},
    roster_token = nil,
    roster_set = {},
    profile_id = nil,
    profile_version = nil,
    pt_engine_version = nil,
    pt_signature = nil,
    pt_state_seen = false,
    last_pt_state_at = nil,
    control_lease_seen = false,
    last_control_lease_at = nil,
    bound_at = nil,
    operator_armed = false,
    operator_seen = false,
    operator_revision = nil,
    last_operator_relay = nil,
    census_ready = false,
    next_census_at = 0,
    reports = {},
    suspend_acks = {},
    adapter_suspended = false,
    emergency_hold_cycle = nil,
    emergency_request_pending = false,
    next_emergency_request_at = 0,
    next_adapter_suspend_at = 0,
    next_adapter_resume_at = 0,
    phase = 'off',
    next_phase_repair_at = 0,
    renewal_cycle = 0,
    next_report_at = 0,
    all_missing_since = nil,
    all_idle_since = nil,
    all_restored_since = nil,
    puller_drained = false,
    next_puller_drain_at = 0,
    puller_resumed = false,
    puller_release_authorized = false,
    next_puller_release_at = 0,
    next_puller_resume_at = 0,
    weapon_locked = false,
    next_lock_at = 0,
    next_equip_at = 0,
    weapon_restore_pending = false,
    weapon_restored_since = nil,
    weapon_candidate_main_id = nil,
    weapon_candidate_sub_id = nil,
    weapon_restore_requests = 0,
    next_weapon_restore_at = 0,
    next_weapon_restore_chat_at = 0,
    pre_staff_main_id = nil,
    pre_staff_sub_id = nil,
    staff_seen_at = nil,
    next_use_at = math.huge,
    use_attempts = 0,
    next_attempt_chat_at = 0,
    next_blocker_chat_at = 0,
    last_cycle_at = nil,
    reload_pending = false,
    reload_deadline = 0,
    next_reload_attempt = 0,
    reload_requests = {},
    reload_request_relays = {},
    reload_operator = nil,
    reload_operator_revision = nil,
    reload_reapply_sent = false,
}

local function valid_revision(revision)
    revision = tonumber(revision)
    return revision and revision >= 0 and revision <= 2147483647
        and revision == math.floor(revision) and revision or nil
end

-- Reload metadata is another replica of the authoritative operator tuple.
-- It may advance, but an out-of-order relay may never roll it backward or
-- give the same revision a different meaning.
local function merge_reload_operator(revision, operator_armed)
    revision = valid_revision(revision)
    if revision == nil then return false end
    local targets = {}
    local function add_target(target, revision_key, bit_key)
        targets[#targets + 1] = {
            target=target, revision_key=revision_key, bit_key=bit_key,
        }
    end
    if state.reload_pending or state.reload_reapply_sent then
        add_target(state, 'reload_operator_revision', 'reload_operator')
    end
    if reload_handoff and reload_handoff.generation == state.generation
        and reload_handoff.old_epoch == state.apply_epoch
    then
        add_target(reload_handoff, 'operator_revision', 'desired_operator')
    end
    -- Validate every recovery replica before mutating any of them. A lower
    -- tuple or equal/conflicting bit is rejected atomically, so reordered
    -- carrier traffic cannot split the reload high-water from live state.
    for _, entry in ipairs(targets) do
        local target, revision_key, bit_key = entry.target,
            entry.revision_key, entry.bit_key
        local current = valid_revision(target[revision_key])
        if current and revision < current then return false end
        if current and revision == current then
            if target[bit_key] ~= (operator_armed == true) then return false end
        end
    end
    for _, entry in ipairs(targets) do
        local target, revision_key, bit_key = entry.target,
            entry.revision_key, entry.bit_key
        local current = valid_revision(target[revision_key])
        if not current or revision > current then
            target[revision_key] = revision
            target[bit_key] = operator_armed == true
        end
    end
    return true
end

local function authority_key(generation, epoch)
    return tostring(generation)..'|'..tostring(tonumber(epoch))
end

local function retire_authority(generation, epoch)
    if generation ~= nil and epoch ~= nil then
        retired_authorities[authority_key(generation, epoch)] = true
    end
end

local function authority_is_retired(generation, epoch)
    return stopped_generations[tostring(generation)] == true
        or retired_authorities[authority_key(generation, epoch)] == true
end

local function in_locus_tomb()
    local info = windower.ffxi.get_info and windower.ffxi.get_info() or nil
    return info and info.logged_in ~= false
        and tonumber(info.zone) == OWNED_ZONE
end

local function enforce_suspended_combat_hold()
    if state.operator_armed
        and (state.phase == 'suspend' or state.phase == 'apply'
            or state.weapon_restore_pending)
    then
        -- PartyTactics Ctrl-P legitimately records the desired ON bit, but its
        -- core `pc on` must not pierce a fully suspended maintenance phase.
        -- This is internal convergence, not a new operator OFF edge. Keep it
        -- local, silent, and idempotent so equal PartyTactics heartbeats cannot
        -- broadcast or print another visible disarm while Signet is applying.
        windower.send_command('pc reconcile off')
    end
end

local function chat(message, color)
    windower.add_to_chat(color or 207, '[SignetKeeper] '..tostring(message))
end

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function valid_token(value, max_length)
    return type(value) == 'string' and #value > 0
        and #value <= (max_length or 96)
        and value:match('^[A-Za-z0-9_.-]+$') ~= nil
end

local function valid_generation(generation)
    return type(generation) == 'string'
        and generation:match('^[0-9]+%-[0-9]+%-[0-9]+$') ~= nil
end

local function valid_epoch(epoch)
    epoch = tonumber(epoch)
    return epoch and epoch >= 0 and epoch <= 2147483647
        and epoch == math.floor(epoch)
end

local function valid_bit(value)
    return value == '0' or value == '1'
end

local function valid_report_phase(value)
    return value == 'monitor' or value == 'drain'
        or value == 'suspend' or value == 'apply'
end

local function split(value, separator)
    local result = {}
    if type(value) ~= 'string' then return result end
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
end

local function roster_identity(roster_token, leader)
    local roster, seen = split(roster_token, ','), {}
    if #roster ~= EXPECTED_ROSTER_SIZE or not valid_name(leader) then
        return nil
    end
    for _, name in ipairs(roster) do
        if not valid_name(name) or seen[name] then return nil end
        seen[name] = true
    end
    if not seen[leader] then return nil end
    return seen
end

local function reload_handoff_is_live()
    if not reload_handoff then return false end
    if os.clock() >= reload_handoff.deadline then
        -- Expiry is a failed recovery transaction, not an ordinary detach.
        -- Fence both the detached predecessor and any explicitly authorized
        -- successor before discarding the metadata that identifies them.
        if reload_handoff.generation then
            stopped_generations[tostring(reload_handoff.generation)] = true
        end
        if reload_handoff.authorized_generation then
            stopped_generations[tostring(
                reload_handoff.authorized_generation)] = true
        end
        reload_handoff = nil
        return false
    end
    return true
end

local function successor_is_authorized(generation, epoch, leader, roster_csv,
    profile_id, profile_version, engine, signature)
    return reload_handoff_is_live()
        and reload_handoff.authorized_generation == generation
        and reload_handoff.authorized_epoch == tonumber(epoch)
        and reload_handoff.profile_id == profile_id
        and reload_handoff.profile_version == profile_version
        and reload_handoff.engine == engine
        and reload_handoff.signature == signature
        and reload_handoff.leader == leader
        and reload_handoff.roster_token == roster_csv
end

local function pending_authority_is_live()
    if not pending_authority then return false end
    if os.clock() >= pending_authority.deadline then
        -- An initial authorization that never reaches armpt is terminally
        -- consumed at expiry; its delayed arm must not become a fresh bind.
        if pending_authority.generation then
            stopped_generations[tostring(pending_authority.generation)] = true
        end
        pending_authority = nil
        return false
    end
    return true
end

local function pending_authority_matches(generation, epoch, leader, roster_csv,
    profile_id, profile_version, engine, signature)
    return pending_authority_is_live()
        and pending_authority.generation == generation
        and pending_authority.epoch == tonumber(epoch)
        and pending_authority.leader == leader
        and pending_authority.roster_token == roster_csv
        and pending_authority.profile_id == profile_id
        and pending_authority.profile_version == profile_version
        and pending_authority.engine == engine
        and pending_authority.signature == signature
end

local function authorize_successor(generation, epoch, leader, roster_csv,
    profile_id, profile_version, engine, signature)
    epoch = tonumber(epoch)
    local roster_set = roster_identity(roster_csv, leader)
    if not valid_generation(generation) or not valid_epoch(epoch)
        or not in_locus_tomb()
        or authority_is_retired(generation, epoch)
        or not roster_set
        or not valid_token(profile_id) or not valid_token(profile_version)
        or not valid_token(engine) or not valid_token(signature, 160)
    then
        chat('Ignored invalid PartyTactics authority authorization.', 123)
        return false
    end
    if not state.armed and not reload_handoff_is_live() then
        if pending_authority_is_live()
            and not pending_authority_matches(generation, epoch, leader,
                roster_csv, profile_id, profile_version, engine, signature)
        then
            chat('Ignored conflicting pending PartyTactics authorization.', 123)
            return false
        end
        pending_authority = {
            generation=generation, epoch=epoch, leader=leader,
            roster_token=roster_csv, roster_set=roster_set,
            profile_id=profile_id, profile_version=profile_version,
            engine=engine, signature=signature,
            deadline=os.clock() + GS_RELOAD_GRACE,
        }
        return true
    end
    if state.armed and not reload_handoff_is_live()
        and generation == state.generation and epoch >= state.apply_epoch
        and state.profile_id == profile_id
        and state.profile_version == profile_version
        and state.pt_engine_version == engine
        and state.pt_signature == signature
        and state.leader == leader and state.roster_token == roster_csv
    then
        return true
    end
    if not reload_handoff_is_live() or epoch ~= 0
        or generation == reload_handoff.generation
        or (reload_handoff.authorized_generation ~= nil
            and (reload_handoff.authorized_generation ~= generation
                or reload_handoff.authorized_epoch ~= epoch))
        or reload_handoff.profile_id ~= profile_id
        or reload_handoff.profile_version ~= profile_version
        or reload_handoff.engine ~= engine
        or reload_handoff.signature ~= signature
        or reload_handoff.leader ~= leader
        or reload_handoff.roster_token ~= roster_csv
    then
        chat('Ignored unauthorized PartyTactics recovery successor.', 123)
        return false
    end
    reload_handoff.authorized_generation = generation
    reload_handoff.authorized_epoch = epoch
    return true
end

local function player()
    return windower.ffxi.get_player()
end

local function acknowledge_adapter_binding(generation, epoch)
    local p = player()
    if not state.armed or not p or type(p.name) ~= 'string'
        or type(p.main_job) ~= 'string'
        or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
    then
        return false
    end
    windower.send_command(
        ('gs c ptgs action %s companion-ready %s %d %s sk %s %s %s %s %s %s %s')
            :format(ADAPTER_CONTROLLER, state.generation,
                state.apply_epoch, ADAPTER_PROTOCOL, state.profile_id,
                state.profile_version, state.pt_engine_version,
                state.pt_signature, p.name, p.main_job, INSTANCE_NONCE))
    return true
end

local function has_signet()
    local p = player()
    for _, buff_id in ipairs(p and p.buffs or {}) do
        if tonumber(buff_id) == SIGNET_BUFF_ID then return true end
    end
    return false
end

local function local_status()
    local p = player()
    if not p then return -1 end
    if type(p.status) == 'number' then return p.status end
    local names = {Idle=0, Engaged=1, Dead=2, Event=3}
    return names[p.status] or -1
end

local function decode_enchantment(item)
    if not item or not extdata then return nil end
    local ok, decoded = pcall(extdata.decode, item)
    if ok and type(decoded) == 'table'
        and decoded.type == 'Enchanted Equipment'
    then
        return decoded
    end
    return nil
end

local function accessible_staff_status()
    local found = false
    local all_known_depleted = true
    for _, bag_id in ipairs(EQUIPPABLE_BAG_IDS) do
        local bag = windower.ffxi.get_items(bag_id)
        if bag and bag.enabled ~= false then
            for _, item in pairs(bag) do
                if type(item) == 'table' and tonumber(item.id) == STAFF_ID
                    and (tonumber(item.count) or 1) > 0
                then
                    found = true
                    local enchantment = decode_enchantment(item)
                    if not enchantment
                        or tonumber(enchantment.charges_remaining) ~= 0
                    then
                        all_known_depleted = false
                    end
                end
            end
        end
    end
    return found, found and all_known_depleted
end

local function accessible_staff_available()
    local found = accessible_staff_status()
    return found
end

local function equipped_slot_item(slot_name)
    local equipment = (windower.ffxi.get_items() or {}).equipment
    if not equipment then return nil end
    local slot = tonumber(equipment[slot_name])
    local bag = tonumber(equipment[slot_name..'_bag'])
    if not slot or slot <= 0 or not bag then return nil end
    return windower.ffxi.get_items(bag, slot)
end

local function equipped_slot_id(slot_name)
    local equipment = (windower.ffxi.get_items() or {}).equipment
    if not equipment then return nil end
    local slot = tonumber(equipment[slot_name])
    if not slot or slot <= 0 then return 0 end
    local item = equipped_slot_item(slot_name)
    return item and tonumber(item.id) or nil
end

local function equipped_staff()
    local equipped = equipped_slot_item('main')
    if equipped and tonumber(equipped.id) == STAFF_ID then return equipped end
    return nil
end

local function staff_equipped()
    return equipped_staff() ~= nil
end

local function staff_enchantment()
    local item = equipped_staff()
    return decode_enchantment(item)
end

-- GearSwap remains the sole owner of the normal combat weapon. The captured
-- pair is the usual restoration proof; the Locus profile may also accept a
-- newly selected Weapons mode after repeated GearSwap reapplies and a stable,
-- occupied raw pair. SignetKeeper never names or equips a combat weapon.
local function combat_weapon_restored()
    local main_id = equipped_slot_id('main')
    local sub_id = equipped_slot_id('sub')
    if main_id == nil or main_id <= 0 or main_id == STAFF_ID
        or sub_id == nil
        or state.profile_id == LOCUS_PROFILE_ID and sub_id <= 0
    then
        return false
    end
    if state.pre_staff_main_id and main_id ~= state.pre_staff_main_id then
        return false
    end
    if state.pre_staff_sub_id ~= nil
        and sub_id ~= state.pre_staff_sub_id
    then
        return false
    end
    return true
end

local function capture_combat_weapon()
    local main_id = equipped_slot_id('main')
    local sub_id = equipped_slot_id('sub')
    if main_id == nil or main_id <= 0 or main_id == STAFF_ID
        or sub_id == nil
        or state.profile_id == LOCUS_PROFILE_ID and sub_id <= 0
        or main_id ~= state.weapon_candidate_main_id
        or sub_id ~= state.weapon_candidate_sub_id
    then
        return false
    end
    state.pre_staff_main_id = main_id
    state.pre_staff_sub_id = sub_id
    return true
end

local function raw_nonstaff_pair()
    local main_id = equipped_slot_id('main')
    local sub_id = equipped_slot_id('sub')
    if main_id == nil or main_id <= 0 or main_id == STAFF_ID
        or sub_id == nil
    then
        return nil, nil
    end
    return main_id, sub_id
end

local function restoration_pair_ready()
    local main_id, sub_id = raw_nonstaff_pair()
    if not main_id then return false end
    if state.profile_id == LOCUS_PROFILE_ID and sub_id <= 0 then
        return false
    end
    if state.pre_staff_main_id == nil
        or state.pre_staff_sub_id == nil
        or main_id == state.pre_staff_main_id
            and sub_id == state.pre_staff_sub_id
    then
        return true
    end
    -- A player can change the selected GearSwap Weapons mode while the staff
    -- is equipped. A changed raw pair is not accepted on the first reapply:
    -- require two requests, then the ordinary continuous stability window.
    -- This is scoped to the Locus profile, whose six roles all use a sub item.
    return state.profile_id == LOCUS_PROFILE_ID
        and state.weapon_restore_requests >= 2
end

-- Emergency detach can outlive the PartyTactics authority, but gear cleanup
-- must not. This worker owns no combat/operator state: it only asks GearSwap
-- to reapply the mode currently selected by whichever profile is active, then
-- releases the old adapter (which will reject the command if already retired)
-- after a stable physical pair is visible. If waking a suspended adapter, the
-- exact pre-staff pair is mandatory; a partial restore may never reopen an
-- automatic lane. Profile replacement has no old adapter to wake and accepts
-- the new profile's stable nonstaff pair instead.
local function tick_terminal_restore(now)
    if not terminal_restore then return false end
    now = tonumber(now) or os.clock()
    local main_id, sub_id = raw_nonstaff_pair()
    if main_id and terminal_restore.exact_required
        and (main_id ~= terminal_restore.expected_main_id
            or sub_id ~= terminal_restore.expected_sub_id)
    then
        main_id, sub_id = nil, nil
    end
    if main_id then
        if main_id ~= terminal_restore.candidate_main_id
            or sub_id ~= terminal_restore.candidate_sub_id
        then
            terminal_restore.candidate_main_id = main_id
            terminal_restore.candidate_sub_id = sub_id
            terminal_restore.observed_since = now
        elseif now - (terminal_restore.observed_since or now)
            >= WEAPON_RESTORE_CONFIRM
        then
            local resume_command = terminal_restore.resume_command
            terminal_restore = nil
            if resume_command then windower.send_command(resume_command) end
            return true
        end
    else
        terminal_restore.candidate_main_id = nil
        terminal_restore.candidate_sub_id = nil
        terminal_restore.observed_since = nil
    end
    if now >= terminal_restore.next_attempt_at then
        windower.send_command(WEAPON_RESTORE_COMMAND)
        terminal_restore.next_attempt_at = now + WEAPON_RESTORE_RETRY_INTERVAL
    end
    return false
end

local function begin_terminal_restore(resume_command, synchronous_only)
    local expected_main_id = state.pre_staff_main_id
    local expected_sub_id = state.pre_staff_sub_id
    local exact_required = resume_command ~= nil
        and expected_main_id ~= nil and expected_sub_id ~= nil

    -- An unloading addon has no future prerender with which to prove physical
    -- completion. Preserve local command ordering, but never wake a suspended
    -- adapter from a raw staff/partial pair merely because a GearSwap request
    -- was queued. A safe raw pair may resume; an unsafe pair stays fail-closed
    -- until the controller is explicitly recovered.
    if synchronous_only then
        local main_id, sub_id = raw_nonstaff_pair()
        local physically_ready = main_id ~= nil
            and (not exact_required
                or main_id == expected_main_id
                    and sub_id == expected_sub_id)
        windower.send_command(WEAPON_RESTORE_COMMAND)
        if resume_command and physically_ready then
            windower.send_command(resume_command)
        end
        terminal_restore = nil
        return
    end

    terminal_restore = {
        resume_command=resume_command,
        exact_required=exact_required,
        expected_main_id=expected_main_id,
        expected_sub_id=expected_sub_id,
        candidate_main_id=nil,
        candidate_sub_id=nil,
        observed_since=nil,
        next_attempt_at=os.clock(),
    }
    tick_terminal_restore(os.clock())
end

local function consume_terminal_restore_on_unload()
    if not terminal_restore then return false end
    local pending = terminal_restore
    local main_id, sub_id = raw_nonstaff_pair()
    local physically_ready = main_id ~= nil
        and (not pending.exact_required
            or main_id == pending.expected_main_id
                and sub_id == pending.expected_sub_id)
    -- The queued GearSwap reapply remains first even when raw observation is
    -- already safe. Only that preexisting physical proof can release the
    -- retained adapter before this process loses its prerender worker.
    windower.send_command(WEAPON_RESTORE_COMMAND)
    if physically_ready and pending.resume_command then
        windower.send_command(pending.resume_command)
    end
    terminal_restore = nil
    return true
end

local function send(fields)
    windower.send_ipc_message(table.concat(fields, '|'))
end

local function adapter_command(action, operator_revision, operator_bit, cycle)
    if not state.armed then return nil end
    local command = ('gs c ptgs action %s %s %s %s %s')
        :format(ADAPTER_CONTROLLER, action, state.generation,
            tostring(state.apply_epoch), ADAPTER_PROTOCOL)
    if operator_revision ~= nil then
        command = command..' '..tostring(operator_revision)
    end
    if operator_bit ~= nil then
        command = command..' '..(operator_bit == true and '1' or '0')
    end
    if cycle ~= nil then command = command..' '..tostring(cycle) end
    return command
end

local function request_adapter_suspend(now)
    local command = adapter_command('suspend', nil, nil,
        state.renewal_cycle)
    if not command then return false end
    windower.send_command(command)
    state.next_adapter_suspend_at = (tonumber(now) or os.clock())
        + ADAPTER_RETRY_INTERVAL
    return true
end

local function request_adapter_resume(now)
    if state.weapon_restore_pending or not combat_weapon_restored() then
        return false
    end
    local command = adapter_command('resume', state.operator_revision,
        state.operator_armed == true, state.renewal_cycle)
    if not command then return false end
    windower.send_command(command)
    state.next_adapter_resume_at = (tonumber(now) or os.clock())
        + ADAPTER_RETRY_INTERVAL
    return true
end

local function request_puller_resume(now)
    local p = player()
    if not state.armed or state.phase ~= 'monitor' or state.census_ready
        or state.renewal_cycle < 1 or not state.operator_seen or not p
        or p.name ~= 'Tackleberry' or not state.puller_release_authorized
        or state.weapon_restore_pending or not combat_weapon_restored()
    then
        return false
    end
    local value = state.operator_armed and 'on' or 'off'
    windower.send_command(('lp operator %s %s %s %s resume %s')
        :format(value,
            state.generation, tostring(state.apply_epoch),
            tostring(state.operator_revision),
            tostring(state.renewal_cycle)))
    state.last_operator_relay = tostring(state.operator_revision)
        ..':'..value
    state.next_puller_resume_at = (tonumber(now) or os.clock())
        + ADAPTER_RETRY_INTERVAL
    return true
end

-- Pulling is the final resume edge. The leader does not release Tackle until
-- fresh reports prove that every profile-owned adapter has restored its
-- automatic lanes. This edge is replicated until Tackle's exact-cycle ACK is
-- observed, so neither a dropped IPC packet nor a dropped local command can
-- strand the party after a successful staff transaction.
local function broadcast_puller_release(now)
    local p = player()
    if not state.armed or state.phase ~= 'monitor' or state.census_ready
        or state.renewal_cycle < 1 or not p or p.name ~= state.leader
        or state.puller_resumed
        or (tonumber(now) or os.clock()) < state.next_puller_release_at
    then
        return false
    end
    send{PREFIX, 'pullerrelease', state.generation, state.leader,
        tostring(state.apply_epoch), tostring(state.renewal_cycle)}
    state.next_puller_release_at = (tonumber(now) or os.clock())
        + ADAPTER_RETRY_INTERVAL
    return true
end

-- LocusPuller keeps the completed generation/epoch/cycle and safely replays
-- its cached acknowledgement when it receives the exact drain request again.
-- Repeat that request locally on Tackle until the leader advances the phase;
-- one lost IPC acknowledgement must not strand the party before staff use.
local function request_puller_drain(now)
    local p = player()
    if not state.armed or state.phase ~= 'drain' or not p
        or p.name ~= 'Tackleberry'
    then
        return false
    end
    windower.send_command(('lp drain %s %s %s')
        :format(state.generation, tostring(state.apply_epoch),
            tostring(state.renewal_cycle)))
    state.next_puller_drain_at = (tonumber(now) or os.clock())
        + PULLER_DRAIN_RETRY_INTERVAL
    return true
end

local function relay_operator_to_puller(force)
    local p = player()
    if not state.armed or not p or p.name ~= 'Tackleberry'
        or state.operator_armed and (not state.census_ready
            or state.weapon_restore_pending
            or not combat_weapon_restored())
    then
        return
    end
    local value = state.operator_armed and 'on' or 'off'
    local relay_key = tostring(state.operator_revision)..':'..value
    if not state.operator_seen or not force
        and state.last_operator_relay == relay_key
    then
        return
    end
    windower.send_command(('lp operator %s %s %s %s')
        :format(value, state.generation, tostring(state.apply_epoch),
            tostring(state.operator_revision)))
    state.last_operator_relay = relay_key
end

-- Merge the leader-authored operator register. A lower revision is stale;
-- equal/same is an idempotent replay; equal/conflicting is malformed. The
-- side effects live here so a periodic PartyTactics state packet heals a
-- dropped operator-state packet instead of merely changing an in-memory bit.
local function accept_operator_tuple(revision, operator, relay_source)
    revision = valid_revision(revision)
    if revision == nil or (operator ~= '0' and operator ~= '1') then
        return false, false
    end
    local desired = operator == '1'
    if state.operator_seen then
        if revision < state.operator_revision then return false, false end
        if revision == state.operator_revision then
            if desired ~= state.operator_armed then return false, false end
            if not merge_reload_operator(revision, desired) then
                return false, false
            end
            enforce_suspended_combat_hold()
            relay_operator_to_puller(true)
            return true, false
        end
    end
    if not merge_reload_operator(revision, desired) then return false, false end
    state.operator_seen = true
    state.operator_revision = revision
    state.operator_armed = desired
    enforce_suspended_combat_hold()
    relay_operator_to_puller(true)
    local p = player()
    if relay_source ~= 'Tackleberry' and p and p.name == 'Tackleberry' then
        send{PREFIX, 'operator', state.generation, p.name,
            tostring(state.apply_epoch), tostring(revision), operator}
    end
    state.next_report_at = 0
    return true, true
end

local function remember_report(name, signet, status, has_staff, phase,
    suspended, cycle, weapon_restored)
    if not state.roster_set[name] then return end
    cycle = tonumber(cycle)
    if cycle ~= state.renewal_cycle then return end
    state.reports[name] = {
        signet = signet == true,
        status = tonumber(status) or -1,
        has_staff = has_staff == true,
        phase = phase,
        suspended = suspended == true,
        cycle = cycle,
        weapon_restored = weapon_restored == true,
        received_at = os.clock(),
    }
    -- The one-shot adapter ACK establishes ownership; the local helper then
    -- carries that proof in every fresh suspend report so a slow sixth client
    -- cannot let otherwise valid acknowledgments age out permanently.
    if phase == 'suspend' and suspended == true then
        state.suspend_acks[name] = {
            received_at = os.clock(), cycle = cycle,
        }
    end
end

local function report_local()
    if not state.armed then return end
    local p = player()
    if not p or not state.roster_set[p.name] then return end
    local signet = has_signet()
    local status = local_status()
    local has_staff = accessible_staff_available()
    local weapon_restored = not state.weapon_restore_pending
        and combat_weapon_restored()
    remember_report(p.name, signet, status, has_staff, state.phase,
        state.adapter_suspended, state.renewal_cycle, weapon_restored)
    send{
        PREFIX, 'report', state.generation, p.name,
        tostring(state.apply_epoch), signet and '1' or '0',
        tostring(status), has_staff and '1' or '0', state.phase,
        state.adapter_suspended and '1' or '0',
        tostring(state.renewal_cycle),
        weapon_restored and '1' or '0',
    }
end

local function reports_are_fresh(now)
    for _, name in ipairs(state.roster) do
        local report = state.reports[name]
        if not report or now - report.received_at > REPORT_STALE_AFTER then
            return false
        end
    end
    return true
end

local function roster_state_timed_out(now)
    if not state.bound_at or now - state.bound_at <= ROSTER_STATE_STALE_AFTER
    then
        return false
    end
    for _, name in ipairs(state.roster) do
        local report = state.reports[name]
        if not report
            or now - report.received_at > ROSTER_STATE_STALE_AFTER
        then
            return true
        end
    end
    return false
end

local function suspend_acks_are_fresh(now)
    for _, name in ipairs(state.roster) do
        local ack = state.suspend_acks[name]
        if not ack or ack.cycle ~= state.renewal_cycle
            or now - ack.received_at > REPORT_STALE_AFTER
        then
            return false
        end
    end
    return true
end

local function every_report(predicate)
    for _, name in ipairs(state.roster) do
        local report = state.reports[name]
        if not report or not predicate(report, name) then return false end
    end
    return true
end

local function restore_weapon_slots(now)
    now = tonumber(now) or os.clock()
    if not state.weapon_locked and not state.weapon_restore_pending then
        return combat_weapon_restored()
    end

    -- Reapply (do not cycle) GearSwap's currently selected Weapons mode. A
    -- plain `gs c update` can observe a stale GearSwap equipment cache and
    -- decide that no weapon change is needed even while Windower's raw equip
    -- table still shows the Signet staff. `gs c weapons` unconditionally asks
    -- GearSwap to equip the selected weapon set; raw observation below is the
    -- completion proof.
    state.weapon_restore_pending = true
    state.weapon_locked = false
    state.next_lock_at = 0
    state.staff_seen_at = nil
    state.next_use_at = math.huge
    if now >= state.next_weapon_restore_at then
        windower.send_command(WEAPON_RESTORE_COMMAND)
        state.weapon_restore_requests = state.weapon_restore_requests + 1
        state.next_weapon_restore_at = now + WEAPON_RESTORE_RETRY_INTERVAL
    end

    if restoration_pair_ready() then
        local main_id = equipped_slot_id('main')
        local sub_id = equipped_slot_id('sub')
        if main_id ~= state.weapon_candidate_main_id
            or sub_id ~= state.weapon_candidate_sub_id
        then
            state.weapon_candidate_main_id = main_id
            state.weapon_candidate_sub_id = sub_id
            state.weapon_restored_since = now
        else
            state.weapon_restored_since = state.weapon_restored_since or now
        end
        if now - state.weapon_restored_since >= WEAPON_RESTORE_CONFIRM then
            if state.profile_id == LOCUS_PROFILE_ID then
                -- Promote a newly selected mode to the verified pair so all
                -- later resume edges still re-check its exact raw equipment.
                state.pre_staff_main_id = main_id
                state.pre_staff_sub_id = sub_id
            end
            state.weapon_restore_pending = false
            state.weapon_restored_since = nil
            state.next_weapon_restore_at = 0
            state.next_weapon_restore_chat_at = 0
            state.next_report_at = 0
            return true
        end
    else
        state.weapon_restored_since = nil
        state.weapon_candidate_main_id = nil
        state.weapon_candidate_sub_id = nil
        if state.armed and now >= state.next_weapon_restore_chat_at then
            state.next_weapon_restore_chat_at = now
                + WEAPON_RESTORE_CHAT_INTERVAL
            chat('Waiting for GearSwap to replace the Signet staff; automatic combat remains paused.', 167)
        end
    end
    return false
end

local function begin_staff_use()
    state.next_lock_at = 0
    state.next_equip_at = 0
    state.staff_seen_at = nil
    state.next_use_at = math.huge
    state.use_attempts = 0
    state.next_attempt_chat_at = 0
    state.next_blocker_chat_at = 0
    -- Establish a stable GearSwap-owned combat pair before taking temporary
    -- ownership. This prevents a roll/song/midaction weapon from becoming the
    -- snapshot merely because maintenance began in that instant.
    state.pre_staff_main_id = nil
    state.pre_staff_sub_id = nil
    state.weapon_restore_pending = true
    state.weapon_restored_since = nil
    state.weapon_candidate_main_id = nil
    state.weapon_candidate_sub_id = nil
    state.weapon_restore_requests = 0
    state.next_weapon_restore_at = 0
    state.next_weapon_restore_chat_at = 0
end

local function legal_phase_transition(phase, cycle)
    if phase == 'drain' then
        return state.phase == 'monitor'
            and cycle == state.renewal_cycle + 1
    end
    if cycle ~= state.renewal_cycle then return false end
    if phase == 'suspend' then return state.phase == 'drain' end
    if phase == 'apply' then return state.phase == 'suspend' end
    if phase == 'resume' then return state.phase == 'apply' end
    return false
end

local function apply_phase(phase, cycle)
    cycle = tonumber(cycle)
    if not state.armed or not cycle or cycle < 1
        or cycle ~= math.floor(cycle)
        or not legal_phase_transition(phase, cycle)
    then
        return false
    end
    if phase == 'drain' and not state.weapon_restore_pending
        and not staff_equipped()
    then
        state.renewal_cycle = cycle
        state.emergency_hold_cycle = nil
        state.pre_staff_main_id = nil
        state.pre_staff_sub_id = nil
    elseif phase == 'drain' then
        state.renewal_cycle = cycle
    end
    state.phase = phase
    state.all_missing_since = nil
    state.all_idle_since = nil
    state.all_restored_since = nil

    local p = player()
    if phase == 'drain' then
        state.census_ready = false
        state.next_census_at = 0
        state.puller_drained = false
        state.next_puller_drain_at = 0
        state.puller_resumed = false
        state.puller_release_authorized = false
        state.next_puller_release_at = 0
        state.next_puller_resume_at = 0
        state.next_adapter_suspend_at = 0
        state.next_adapter_resume_at = 0
        state.suspend_acks = {}
        request_puller_drain(os.clock())
        chat('At least one member lacks Signet or a verified combat weapon. Puller drain requested; waiting for its exact-cycle acknowledgment and six idle members.')
    elseif phase == 'suspend' then
        state.next_puller_drain_at = 0
        state.adapter_suspended = false
        state.next_adapter_suspend_at = 0
        request_adapter_suspend(os.clock())
        chat('Party is idle. Waiting for all six PartyTactics adapters to suspend automatic actions.')
    elseif phase == 'apply' then
        state.next_puller_drain_at = 0
        begin_staff_use()
        chat('All six adapters are suspended. Preparing Signet staff.')
    elseif phase == 'resume' then
        state.next_puller_drain_at = 0
        restore_weapon_slots(os.clock())
        state.census_ready = false
        state.next_census_at = 0
        state.phase = 'monitor'
        state.puller_drained = false
        state.suspend_acks = {}
        state.last_cycle_at = os.clock()
        state.next_adapter_resume_at = 0
        state.puller_release_authorized = false
        state.emergency_hold_cycle = nil
        state.emergency_request_pending = false
        state.next_emergency_request_at = 0
        state.next_puller_release_at = 0
        state.next_puller_resume_at = 0
        request_adapter_resume(os.clock())
        chat('All six report Signet. Restoring automatic lanes from the current operator state.', 158)
    end
    state.next_phase_repair_at = os.clock() + PHASE_REPAIR_INTERVAL
    state.next_report_at = 0
    return true
end

local function broadcast_phase(phase)
    if not state.armed then return end
    local cycle = phase == 'drain'
        and state.renewal_cycle + 1 or state.renewal_cycle
    if not apply_phase(phase, cycle) then return end
    send{PREFIX, 'phase', state.generation, state.leader,
        tostring(state.apply_epoch), phase, tostring(cycle)}
end

-- An unexpected raw staff/partial pair in monitor is itself a maintenance
-- trigger. Enter the normal exact-cycle transaction immediately on every
-- client, suspend the local adapter without waiting for the six-client idle
-- barrier, and drain Tackle's puller. The leader also replicates the phase so
-- all peers converge even if their local raw observation arrives later.
local function begin_weapon_recovery(now)
    if not state.armed or state.phase ~= 'monitor' then return false end
    now = tonumber(now) or os.clock()
    local cycle = state.renewal_cycle + 1
    if not apply_phase('drain', cycle) then return false end
    state.emergency_hold_cycle = cycle
    request_adapter_suspend(now)
    local p = player()
    if p and p.name == state.leader then
        state.emergency_request_pending = false
        send{PREFIX, 'phase', state.generation, state.leader,
            tostring(state.apply_epoch), 'drain', tostring(cycle)}
    elseif p then
        state.emergency_request_pending = true
        state.next_emergency_request_at = now
        send{PREFIX, 'weapon-recovery', state.generation, p.name,
            tostring(state.apply_epoch), tostring(cycle)}
        state.next_emergency_request_at = now
            + EMERGENCY_REQUEST_RETRY_INTERVAL
    end
    return true
end

-- Phase is replicated state, not a one-shot notification. The leader repeats
-- its current transaction edge until fresh reports prove every client crossed
-- it. A client can therefore miss any single IPC packet without stranding the
-- six-character maintenance cycle.
local function repair_phase(now)
    local p = player()
    if not state.armed or not p or p.name ~= state.leader
        or now < state.next_phase_repair_at
    then
        return
    end
    local phase = state.phase
    if phase == 'monitor' then
        if state.renewal_cycle < 1 or state.census_ready then return end
        phase = 'resume'
    elseif phase ~= 'drain' and phase ~= 'suspend' and phase ~= 'apply' then
        return
    end
    send{PREFIX, 'phase', state.generation, state.leader,
        tostring(state.apply_epoch), phase, tostring(state.renewal_cycle)}
    state.next_phase_repair_at = now + PHASE_REPAIR_INTERVAL
end

local function mark_census_ready(now)
    now = tonumber(now) or os.clock()
    local first_ready = not state.census_ready
    state.census_ready = true
    if now < state.next_census_at then return end
    state.next_census_at = now + CENSUS_REPAIR_INTERVAL
    send{PREFIX, 'census', state.generation, state.leader,
        tostring(state.apply_epoch), 'ready',
        tostring(state.renewal_cycle)}
    if first_ready and state.operator_seen then
        relay_operator_to_puller(true)
    end
    if first_ready and state.renewal_cycle > 0 then
        chat('Signet renewal complete. All automatic lanes confirmed restored; XP is released.', 158)
    end
end

local function tick_leader(now)
    local p = player()
    if not p or p.name ~= state.leader or not reports_are_fresh(now) then
        return
    end
    repair_phase(now)

    if state.phase == 'monitor' then
        local all_signet = every_report(function(report)
            return report.signet
        end)
        local all_weapons = every_report(function(report)
            return report.weapon_restored
        end)
        local all_running = every_report(function(report)
            return report.phase == 'monitor' and not report.suspended
                and report.cycle == state.renewal_cycle
                and report.weapon_restored
        end)
        if all_signet and all_weapons then
            state.all_missing_since = nil
            if all_running then
                if state.renewal_cycle == 0 or state.puller_resumed then
                    mark_census_ready(now)
                else
                    broadcast_puller_release(now)
                end
            end
        elseif all_signet then
            -- A physically unsafe weapon is a stronger signal than a buff
            -- transition. Stop acquisition on the first fresh six-client
            -- report instead of spending the Signet debounce interval.
            state.all_missing_since = nil
            broadcast_phase('drain')
        else
            state.all_missing_since = state.all_missing_since or now
            if now - state.all_missing_since >= ANY_MISSING_CONFIRM then
                broadcast_phase('drain')
            end
        end
    elseif state.phase == 'drain' then
        local all_drained = state.puller_drained
            and every_report(function(report)
                return report.phase == 'drain'
                    and report.cycle == state.renewal_cycle
                    and report.status == 0
            end)
        if all_drained then
            state.all_idle_since = state.all_idle_since or now
            if now - state.all_idle_since >= ALL_IDLE_CONFIRM then
                broadcast_phase('suspend')
            end
        else
            state.all_idle_since = nil
        end
    elseif state.phase == 'suspend' then
        if suspend_acks_are_fresh(now)
            and every_report(function(report)
                return report.phase == 'suspend' and report.status == 0
                    and report.suspended
                    and report.cycle == state.renewal_cycle
            end)
        then
            broadcast_phase('apply')
        end
    elseif state.phase == 'apply' then
        if every_report(function(report)
            return report.phase == 'apply' and report.signet
                and report.weapon_restored
                and report.cycle == state.renewal_cycle
        end) then
            state.all_restored_since = state.all_restored_since or now
            if now - state.all_restored_since >= ALL_RESTORED_CONFIRM then
                broadcast_phase('resume')
            end
        else
            state.all_restored_since = nil
        end
    end
end

local function tick_staff(now)
    if state.phase ~= 'apply' then return end
    if has_signet() then
        restore_weapon_slots(now)
        return
    end
    local staff_available, staff_depleted = accessible_staff_status()
    if not staff_available then
        restore_weapon_slots(now)
        if now >= state.next_blocker_chat_at then
            state.next_blocker_chat_at = now + 30
            chat(STAFF_NAME..' is missing from every equip-accessible bag; party remains paused.', 167)
        end
        return
    end
    if staff_depleted then
        restore_weapon_slots(now)
        if now >= state.next_blocker_chat_at then
            state.next_blocker_chat_at = now + 60
            chat(STAFF_NAME..' has no charges remaining; party remains paused until the staff is replaced or recharged.', 167)
        end
        return
    end
    if not state.weapon_locked then
        if state.weapon_restore_pending then
            restore_weapon_slots(now)
            return
        end
        if not capture_combat_weapon() then
            state.weapon_restore_pending = true
            restore_weapon_slots(now)
            return
        end
        -- Pre-staff stabilization requests cannot count as evidence that a
        -- newly selected post-staff mode was reapplied.
        state.weapon_restore_requests = 0
        windower.send_command('gs disable main sub')
        state.weapon_locked = true
        state.next_lock_at = now + LOCK_REFRESH_INTERVAL
        state.next_equip_at = now + 0.5
        return
    end
    if now >= state.next_lock_at then
        -- A GearSwap reload clears disabled-slot state. Reassert ownership even
        -- when the raw staff is still physically equipped.
        windower.send_command('gs disable main sub')
        state.next_lock_at = now + LOCK_REFRESH_INTERVAL
    end
    if not staff_equipped() then
        -- Every displacement restarts the entire observed-equipped delay. The
        -- timer never advances from an equip command or GearSwap cache value.
        state.staff_seen_at = nil
        state.next_use_at = math.huge
        if now >= state.next_equip_at then
            windower.send_command('input /equip main "'..STAFF_NAME..'"')
            state.next_equip_at = now + EQUIP_RETRY_DELAY
        end
        return
    end
    if not state.staff_seen_at then
        state.staff_seen_at = now
        state.next_use_at = now + STAFF_USE_DELAY
        chat(('Staff equipped and raw-verified; waiting %.1f seconds for the proven activation boundary.')
            :format(STAFF_USE_DELAY))
        return
    end
    local enchantment = staff_enchantment()
    if enchantment and tonumber(enchantment.charges_remaining) == 0 then
        restore_weapon_slots(now)
        if now >= state.next_blocker_chat_at then
            state.next_blocker_chat_at = now + 60
            chat(STAFF_NAME..' has no charges remaining; party remains paused until the staff is replaced or recharged.', 167)
        end
        return
    end
    if now >= state.next_use_at then
        windower.send_command('input /item "'..STAFF_NAME..'" <me>')
        state.use_attempts = state.use_attempts + 1
        state.next_use_at = now + STAFF_REUSE_DELAY
        if state.use_attempts <= 3 or now >= state.next_attempt_chat_at then
            chat('Using '..STAFF_NAME..' (attempt '
                ..tostring(state.use_attempts)..').')
            state.next_attempt_chat_at = now + STAFF_ATTEMPT_CHAT_INTERVAL
        end
    end
end

local function reset_state(preserve_weapon_state)
    state.armed = false
    state.generation = nil
    state.apply_epoch = nil
    state.leader = nil
    state.roster = {}
    state.roster_token = nil
    state.roster_set = {}
    state.profile_id = nil
    state.profile_version = nil
    state.pt_engine_version = nil
    state.pt_signature = nil
    state.pt_state_seen = false
    state.last_pt_state_at = nil
    state.control_lease_seen = false
    state.last_control_lease_at = nil
    state.bound_at = nil
    state.operator_armed = false
    state.operator_seen = false
    state.operator_revision = nil
    state.last_operator_relay = nil
    state.census_ready = false
    state.next_census_at = 0
    state.reports = {}
    state.suspend_acks = {}
    state.adapter_suspended = false
    state.emergency_hold_cycle = nil
    state.emergency_request_pending = false
    state.next_emergency_request_at = 0
    state.next_adapter_suspend_at = 0
    state.next_adapter_resume_at = 0
    state.phase = 'off'
    state.next_phase_repair_at = 0
    state.renewal_cycle = 0
    state.next_report_at = 0
    state.all_missing_since = nil
    state.all_idle_since = nil
    state.all_restored_since = nil
    state.puller_drained = false
    state.next_puller_drain_at = 0
    state.puller_resumed = false
    state.puller_release_authorized = false
    state.next_puller_release_at = 0
    state.next_puller_resume_at = 0
    state.reload_pending = false
    state.reload_deadline = 0
    state.next_reload_attempt = 0
    state.reload_requests = {}
    state.reload_request_relays = {}
    state.reload_operator = nil
    state.reload_operator_revision = nil
    state.reload_reapply_sent = false
    state.next_attempt_chat_at = 0
    if not preserve_weapon_state then
        state.weapon_locked = false
        state.next_lock_at = 0
        state.next_equip_at = 0
        state.weapon_restore_pending = false
        state.weapon_restored_since = nil
        state.weapon_candidate_main_id = nil
        state.weapon_candidate_sub_id = nil
        state.weapon_restore_requests = 0
        state.next_weapon_restore_at = 0
        state.next_weapon_restore_chat_at = 0
        state.pre_staff_main_id = nil
        state.pre_staff_sub_id = nil
        state.staff_seen_at = nil
        state.next_use_at = math.huge
        state.use_attempts = 0
    end
end

local function release_local_companions(generation, epoch, terminal,
    authority)
    local p = player()
    if not p then return end
    authority = authority or state
    local engine = authority.pt_engine_version or authority.engine
    local profile_id = authority.profile_id
    local profile_version = authority.profile_version
    local signature = authority.pt_signature or authority.signature
    local source = authority.leader
    if terminal and engine and profile_id and profile_version and signature
        and source
    then
        if p.name == 'Dolomedes' then
            windower.send_command(
                ('jk stoppt %s %s %s %s %s %s'):format(generation,
                    engine, profile_id, profile_version, signature, source))
        elseif p.name == 'Tackleberry' then
            windower.send_command(
                ('lp retirept %s %s %s %s %s %s'):format(generation,
                    engine, profile_id, profile_version, signature, source))
        end
        return
    end
    if p.name == 'Dolomedes' then
        windower.send_command(('jk detach %s %s')
            :format(generation, tostring(epoch)))
    elseif p.name == 'Tackleberry' then
        windower.send_command(('lp unbindpt %s %s keepoff')
            :format(generation, tostring(epoch)))
    end
end

local function disarm(reason, resume_if_suspended, preserve_reload_handoff,
    preserve_weapon_lock, terminal_companions, skip_companions,
    synchronous_restore)
    if not state.armed then return end
    local was_armed = state.armed
    local generation, epoch = state.generation, state.apply_epoch
    local resume_command = nil
    if resume_if_suspended and (state.adapter_suspended
        or state.phase == 'suspend' or state.phase == 'apply')
    then
        resume_command = adapter_command('resume', state.operator_revision,
            state.operator_armed == true, state.renewal_cycle)
    end
    if not preserve_weapon_lock then
        local restore_needed = state.weapon_locked
            or state.weapon_restore_pending or staff_equipped()
        if restore_needed then
            begin_terminal_restore(resume_command,
                synchronous_restore == true)
            resume_command = nil
        end
    end
    -- Automatic lanes may wake only after the GearSwap restoration request is
    -- ahead of them in the local command queue. When the addon will remain
    -- loaded, the gear-only worker above waits for raw physical confirmation.
    if resume_command then windower.send_command(resume_command) end
    if not skip_companions then
        release_local_companions(generation, epoch,
            terminal_companions == true, state)
    end
    retire_authority(generation, epoch)
    reset_state(preserve_weapon_lock == true)
    if not preserve_reload_handoff then
        reload_handoff = nil
        pending_authority = nil
    end
    if was_armed then
        chat('Detached'..(reason and ': '..reason or '')..'.')
    end
end

local function retire_transient_authorities()
    -- Terminal cleanup must fence work that was authorized but has not reached
    -- its local arm yet.  Otherwise a delayed recovery arm can reacquire the
    -- staff/puller lanes after the old profile has already stopped.
    if pending_authority and pending_authority.generation then
        stopped_generations[pending_authority.generation] = true
    end
    if reload_handoff then
        if reload_handoff.generation then
            stopped_generations[reload_handoff.generation] = true
        end
        if reload_handoff.authorized_generation then
            stopped_generations[reload_handoff.authorized_generation] = true
        end
    end
end

local function terminal_disarm_local(reason, resume_if_suspended,
    companions_already_fenced, synchronous_restore,
    terminal_generation, terminal_epoch)
    retire_transient_authorities()
    if not state.armed then
        -- A recovery detach can leave this process temporarily unarmed while
        -- it still owns main/sub and an exact successor/pending-arm fence.
        -- Manual off, zone/logout, or raw unload must remain terminal even in
        -- that narrow gap.
        local authority = reload_handoff or pending_authority
        if authority then
            remember_terminal(reason,
                terminal_generation or authority.authorized_generation
                    or authority.generation,
                terminal_epoch or authority.authorized_epoch
                    or authority.old_epoch or authority.epoch)
        end
        if authority and not companions_already_fenced then
            release_local_companions(authority.generation,
                authority.old_epoch or authority.epoch, true, authority)
            if authority.authorized_generation then
                release_local_companions(authority.authorized_generation,
                    authority.authorized_epoch or 0, true, authority)
            end
        end
        local restore_needed = state.weapon_locked
            or state.weapon_restore_pending
        if restore_needed then
            begin_terminal_restore(nil, synchronous_restore == true)
        end
        reload_handoff = nil
        pending_authority = nil
        reset_state(false)
        return nil, nil, false
    end
    local generation, epoch = state.generation, state.apply_epoch
    remember_terminal(reason, terminal_generation or generation,
        terminal_epoch or epoch)
    -- A terminal edge can name an already-authorized recovery successor while
    -- the predecessor is still armed. The ordinary armed disarm below fences
    -- only the current generation, so explicitly retire the successor's local
    -- companion before clearing the handoff metadata. Otherwise a delayed
    -- successor adapter could remain live even though both Signet authorities
    -- have been tombstoned.
    if not companions_already_fenced and reload_handoff
        and reload_handoff.authorized_generation
        and reload_handoff.authorized_generation ~= generation
    then
        release_local_companions(reload_handoff.authorized_generation,
            reload_handoff.authorized_epoch or 0, true, reload_handoff)
    end
    disarm(reason, resume_if_suspended, false, false,
        not companions_already_fenced, companions_already_fenced,
        synchronous_restore == true)
    return generation, epoch, true
end

local function disarm_all(reason, resume_if_suspended,
    companions_already_fenced, synchronous_restore,
    terminal_generation, terminal_epoch)
    local generation, epoch, was_armed = terminal_disarm_local(
        reason, resume_if_suspended, companions_already_fenced,
        synchronous_restore == true, terminal_generation, terminal_epoch)
    if not was_armed then return end
    send{PREFIX, 'disarm', generation, tostring(epoch),
        reason or 'coordinator', resume_if_suspended and '1' or '0'}
end

local function stop_metadata_matches(engine, profile_id, profile_version,
    signature, source)
    if not valid_name(source) then return false end
    if state.armed and engine == state.pt_engine_version
        and profile_id == state.profile_id
        and profile_version == state.profile_version
        and signature == state.pt_signature
        and state.roster_set[source]
    then
        return true
    end
    if reload_handoff_is_live()
        and engine == reload_handoff.engine
        and profile_id == reload_handoff.profile_id
        and profile_version == reload_handoff.profile_version
        and signature == reload_handoff.signature
    then
        for _, name in ipairs(split(reload_handoff.roster_token, ',')) do
            if name == source then return true end
        end
    end
    return pending_authority_is_live()
        and engine == pending_authority.engine
        and profile_id == pending_authority.profile_id
        and profile_version == pending_authority.profile_version
        and signature == pending_authority.signature
        and pending_authority.roster_set[source] == true
end

local function fence_local_stop(target_generation, engine, profile_id,
    profile_version, signature, source)
    local p = player()
    if not p then return end
    if p.name == 'Dolomedes' then
        windower.send_command(
            ('jk stoppt %s %s %s %s %s %s'):format(target_generation,
                engine, profile_id, profile_version, signature, source))
    elseif p.name == 'Tackleberry' then
        windower.send_command(
            ('lp retirept %s %s %s %s %s %s'):format(target_generation,
                engine, profile_id, profile_version, signature, source))
    end
end

local function accept_stop(target_generation, engine, profile_id,
    profile_version, signature, source, reason)
    if not valid_generation(target_generation)
        or not stop_metadata_matches(engine, profile_id, profile_version,
            signature, source)
    then
        return false
    end
    stopped_generations[target_generation] = true
    fence_local_stop(target_generation, engine, profile_id, profile_version,
        signature, source)
    local stops_current = state.armed
        and target_generation == state.generation
    local live_handoff = reload_handoff_is_live() and reload_handoff or nil
    local stops_successor = live_handoff
        and live_handoff.authorized_generation == target_generation
    local stops_predecessor = live_handoff
        and live_handoff.generation == target_generation
    local stops_pending = pending_authority_is_live()
        and pending_authority.generation == target_generation
    local target_epoch = stops_current and state.apply_epoch
        or stops_successor and live_handoff.authorized_epoch
        or stops_predecessor and live_handoff.old_epoch
        or stops_pending and pending_authority.epoch
    -- The stop wire names a generation, not an epoch. Keep an unknown epoch
    -- unknown unless a live exact local authority supplies it.
    if stops_current or stops_successor or stops_predecessor
        or stops_pending
    then
        remember_terminal(reason or 'PartyTactics stopped', target_generation,
            target_epoch)
    end
    if stops_current or stops_successor or stops_predecessor then
        if state.armed then
            -- The exact PartyTactics stop above fences its named generation.
            -- During an authorized handoff, terminal cleanup must also fence
            -- the other locally live side before companions_already_fenced
            -- suppresses the generic disarm release path.
            if target_generation ~= state.generation then
                release_local_companions(state.generation,
                    state.apply_epoch, true, state)
            end
            if live_handoff and live_handoff.authorized_generation
                and target_generation
                    ~= live_handoff.authorized_generation
            then
                release_local_companions(
                    live_handoff.authorized_generation,
                    live_handoff.authorized_epoch or 0, true,
                    live_handoff)
            end
            disarm_all(reason or 'PartyTactics stopped', false, true,
                false, target_generation, target_epoch)
        else
            terminal_disarm_local(reason or 'PartyTactics stopped', false,
                false, false, target_generation, target_epoch)
        end
    elseif stops_pending then
        terminal_disarm_local(reason or 'PartyTactics stopped', false,
            false, false, target_generation, target_epoch)
    end
    return true
end

local function detach_exact(generation, epoch, reason)
    if not state.armed or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
    then
        return false
    end
    if state.reload_reapply_sent then
        local preserve = reload_handoff ~= nil
            and reload_handoff.generation == state.generation
        disarm(reason or 'full-profile reload adapter transition', false,
            preserve, preserve)
        -- Every client is replacing the same adapter. Broadcasting this old
        -- detach could arrive at the no-loopback leader before its new probe
        -- and erase the bounded operator handoff.
        return true
    end
    disarm(reason or 'PartyTactics adapter detached', false)
    send{PREFIX, 'detach', generation, tostring(epoch),
        reason or 'adapter-detach'}
    return true
end

local function mark_gsreload(generation, epoch)
    if not state.armed or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
    then
        return false
    end
    local p = player()
    if not p or not state.roster_set[p.name] or not in_locus_tomb() then
        return false
    end
    local now = os.clock()
    state.reload_pending = true
    state.reload_deadline = now + GS_RELOAD_GRACE
    state.reload_requests[p.name] = now
    state.reload_request_relays[p.name] = true
    state.next_reload_attempt = now + 1.5
    if state.operator_seen then
        state.reload_operator_revision = state.operator_revision
        state.reload_operator = state.operator_armed
    end
    local revision = state.operator_seen
        and tostring(state.operator_revision) or '-'
    local operator = state.operator_seen
        and (state.operator_armed and '1' or '0') or '?'
    send{PREFIX, 'reload-request', state.generation, p.name,
        tostring(state.apply_epoch), revision, operator}
    chat('GearSwap reload observed; preserving item ownership until one full PartyTactics reapply restores every compiled lane.', 158)
    return true
end

local function clear_gsreload()
    if not state.reload_pending then return end
    state.reload_pending = false
    state.reload_deadline = 0
    state.next_reload_attempt = 0
    state.reload_requests = {}
    state.reload_request_relays = {}
    state.reload_operator = nil
    state.reload_operator_revision = nil
    state.reload_reapply_sent = false
end

local function mark_local_companion_reload()
    if not state.armed then return end
    local p = player()
    if not p then return end
    if p.name == 'Dolomedes' then
        windower.send_command(('jk gsreload %s %s')
            :format(state.generation, tostring(state.apply_epoch)))
    elseif p.name == 'Tackleberry' then
        windower.send_command(('lp gsreload %s %s')
            :format(state.generation, tostring(state.apply_epoch)))
    end
end

local function tick_reload(now)
    if not state.armed then return end
    if state.reload_pending and now >= state.reload_deadline then
        disarm_all('GearSwap reload recovery expired', true)
        return
    end
    local p = player()
    if state.reload_pending and p and p.name == state.leader
        and not state.reload_reapply_sent
        and next(state.reload_requests) ~= nil
        and now >= state.next_reload_attempt
    then
        if not in_locus_tomb() then
            disarm_all('left the Locus Dire Bat battlefield', false)
            return
        end
        local revision = state.reload_operator_revision
            or state.operator_revision
        local desired = state.operator_armed == true
        if state.reload_operator_revision ~= nil then
            desired = state.reload_operator == true
        end
        reload_handoff = {
            generation=state.generation, profile_id=state.profile_id,
            profile_version=state.profile_version, leader=state.leader,
            roster_token=state.roster_token,
            engine=state.pt_engine_version,
            signature=state.pt_signature,
            old_epoch=state.apply_epoch,
            operator_revision=revision,
            desired_operator=desired, deadline=now + GS_RELOAD_GRACE,
        }
        state.reload_reapply_sent = true
        mark_local_companion_reload()
        send{PREFIX, 'reload-start', state.generation, state.leader,
            tostring(state.apply_epoch), tostring(revision),
            desired and '1' or '0'}
        windower.send_command(
            ('pt __recover_controller %s %s %s %s %s %s %s %s %s %s %s %s')
                :format(ADAPTER_CONTROLLER, state.generation,
                    tostring(state.apply_epoch), ADAPTER_PROTOCOL,
                    state.profile_id, state.profile_version,
                    state.pt_engine_version, state.pt_signature,
                    state.leader, state.roster_token, tostring(revision),
                    desired and '1' or '0'))
        state.next_reload_attempt = math.huge
    end
end

local function armpt(generation, epoch, leader, roster_csv, profile_id,
    profile_version, engine, signature, operator_revision, operator)
    local roster = split(roster_csv, ',')
    local seen = {}
    epoch = tonumber(epoch)
    operator_revision = valid_revision(operator_revision)
    if not valid_generation(generation) or not valid_epoch(epoch)
        or not valid_name(leader) or #roster ~= EXPECTED_ROSTER_SIZE
        or not valid_token(profile_id) or not valid_token(profile_version)
        or not valid_token(engine) or not valid_token(signature, 160)
        or operator_revision == nil
        or (operator ~= '0' and operator ~= '1')
    then
        chat('Refusing invalid PartyTactics arm request; exact authority and six validated names are required.', 167)
        return false
    end
    for _, name in ipairs(roster) do
        if not valid_name(name) or seen[name] then
            chat('Refusing invalid or duplicate roster name.', 167)
            return false
        end
        seen[name] = true
    end
    if not seen[leader] then
        chat('Refusing arm request whose leader is outside the roster.', 167)
        return false
    end
    local p = player()
    if not p or not seen[p.name] then
        chat('This character is outside the validated Signet roster.', 167)
        return false
    end
    if not in_locus_tomb() then
        disarm_all('outside the Locus Dire Bat battlefield', false)
        return false
    end
    local matching_identity = state.profile_id == profile_id
        and state.profile_version == profile_version
        and state.pt_engine_version == engine
        and state.pt_signature == signature
        and state.leader == leader and state.roster_token == roster_csv
    local same_authority = state.armed and state.generation == generation
        and state.apply_epoch == epoch and matching_identity
    local same_generation_reapply = state.armed
        and generation == state.generation and epoch > state.apply_epoch
        and matching_identity
    local handoff_matches = successor_is_authorized(generation, epoch,
        leader, roster_csv, profile_id, profile_version, engine, signature)
    local pending_matches = pending_authority_matches(generation, epoch,
        leader, roster_csv, profile_id, profile_version, engine, signature)
    if authority_is_retired(generation, epoch) then
        chat('Ignored retired PartyTactics arm request.', 123)
        return false
    end
    if state.armed and not same_authority then
        if not same_generation_reapply and not handoff_matches then
            chat('Ignored stale, conflicting, or unfenced PartyTactics arm request.', 123)
            return false
        end
    elseif not state.armed and reload_handoff_is_live()
        and not handoff_matches
    then
        chat('Ignored recovery arm without the exact authorized successor.', 123)
        return false
    elseif not state.armed and pending_authority_is_live()
        and not pending_matches
    then
        chat('Ignored arm outside the pending exact authorization.', 123)
        return false
    end
    if same_authority then
        local accepted = accept_operator_tuple(operator_revision, operator)
        if not accepted then return false end
        if state.phase == 'suspend' or state.phase == 'apply' then
            request_adapter_suspend()
            enforce_suspended_combat_hold()
        end
        if state.operator_seen and state.census_ready then
            relay_operator_to_puller(true)
        end
        report_local()
        return true
    end
    -- A newly accepted controller owns GearSwap from this point forward. An
    -- exact reapply inherits any in-flight staff ownership so a no-op first
    -- restore cannot disappear between epochs. Unrelated terminal cleanup is
    -- canceled before it can issue into the new lifecycle.
    local prior_revision = state.operator_seen and state.operator_revision
        or nil
    local prior_operator = state.operator_armed and '1' or '0'
    local prior_hard_suspension = same_generation_reapply and (
        state.adapter_suspended or state.phase == 'suspend'
        or state.phase == 'apply'
        or (state.phase == 'drain'
            and state.emergency_hold_cycle == state.renewal_cycle))
    if state.armed then
        disarm('new PartyTactics authority', false, handoff_matches,
            handoff_matches or same_generation_reapply)
    end
    terminal_restore = nil
    pending_authority = nil
    state.armed = true
    state.generation = generation
    state.apply_epoch = epoch
    state.leader = leader
    state.roster = roster
    state.roster_token = roster_csv
    state.roster_set = seen
    state.profile_id = profile_id
    state.profile_version = profile_version
    state.pt_engine_version = engine
    state.pt_signature = signature
    state.pt_state_seen = false
    state.last_pt_state_at = nil
    state.control_lease_seen = false
    state.last_control_lease_at = nil
    state.bound_at = os.clock()
    state.operator_armed = false
    state.operator_seen = false
    state.operator_revision = nil
    state.last_operator_relay = nil
    state.census_ready = false
    state.next_census_at = 0
    state.reports = {}
    state.suspend_acks = {}
    state.adapter_suspended = false
    state.next_adapter_suspend_at = 0
    state.next_adapter_resume_at = 0
    state.phase = 'monitor'
    state.next_phase_repair_at = 0
    state.renewal_cycle = 0
    state.next_report_at = 0
    state.all_missing_since = nil
    state.all_idle_since = nil
    state.all_restored_since = nil
    state.puller_drained = false
    state.next_puller_drain_at = 0
    state.puller_resumed = false
    state.puller_release_authorized = false
    state.next_puller_release_at = 0
    state.next_puller_resume_at = 0
    state.reload_pending = false
    state.reload_deadline = 0
    state.next_reload_attempt = 0
    state.reload_requests = {}
    state.reload_request_relays = {}
    state.reload_operator = nil
    state.reload_operator_revision = nil
    state.reload_reapply_sent = false
    state.next_attempt_chat_at = 0
    local carried_revision, carried_operator = operator_revision, operator
    if same_generation_reapply and valid_revision(prior_revision) then
        if prior_revision > carried_revision then
            carried_revision, carried_operator = prior_revision,
                prior_operator
        elseif prior_revision == carried_revision
            and prior_operator ~= carried_operator
        then
            disarm_all('conflicting reapply operator revision', false)
            return false
        end
    end
    if handoff_matches and reload_handoff
        and valid_revision(reload_handoff.operator_revision)
    then
        local handoff_revision = reload_handoff.operator_revision
        local handoff_operator = reload_handoff.desired_operator and '1' or '0'
        if handoff_revision > carried_revision then
            carried_revision, carried_operator = handoff_revision,
                handoff_operator
        elseif handoff_revision == carried_revision
            and handoff_operator ~= carried_operator
        then
            disarm_all('conflicting recovery operator revision', false)
            return false
        end
    end
    if not accept_operator_tuple(carried_revision, carried_operator) then
        disarm_all('invalid recovery operator revision', false)
        return false
    end
    if prior_hard_suspension then
        -- A higher-epoch reapply replaces the profile-local adapter. Its fresh
        -- instance has not inherited the predecessor's suspended state, even
        -- when main/sub were already restored. Start a new exact emergency
        -- cycle under the replacement epoch, hold PartyCombat immediately,
        -- and re-prove the physical pair before any automatic lane can reopen.
        -- Ordinary drain is intentionally excluded so an in-flight fight may
        -- still finish before the normal suspension barrier.
        state.weapon_restore_pending = true
        state.weapon_restored_since = nil
        state.weapon_candidate_main_id = nil
        state.weapon_candidate_sub_id = nil
        state.weapon_restore_requests = 0
        state.next_weapon_restore_at = 0
        enforce_suspended_combat_hold()
        begin_weapon_recovery(os.clock())
        restore_weapon_slots(os.clock())
    elseif state.weapon_locked or state.weapon_restore_pending
        or staff_equipped()
    then
        state.weapon_restore_pending = true
        enforce_suspended_combat_hold()
        if not state.adapter_suspended then
            begin_weapon_recovery(os.clock())
        end
        restore_weapon_slots(os.clock())
    end
    chat(('Bound to PartyTactics %s v%s; monitoring exact six-member Signet consensus.')
        :format(profile_id, profile_version), 158)
    send{PREFIX, 'ready', generation, p.name, tostring(epoch),
        profile_id, profile_version}
    report_local()
    if handoff_matches then
        -- PartyTactics carries the live operator bit through its exact recovery
        -- transaction. The companion never emits a delayed `pt arm`, which
        -- could otherwise overwrite an Alt-P arriving during the handoff.
        reload_handoff = nil
        restore_weapon_slots()
    end
    return true
end

local function process_pt_state(fields)
    if not state.armed or fields[1] ~= PT_PREFIX or fields[2] ~= 'state'
        or #fields ~= 15
    then
        return
    end
    local generation, engine, profile_id, profile_version =
        fields[3], fields[4], fields[5], fields[6]
    local signature, leader, roster_token = fields[7], fields[8], fields[9]
    local epoch = tonumber(fields[10])
    local operator_revision, operator = valid_revision(fields[14]), fields[15]
    local syntactically_valid = valid_generation(generation)
        and valid_token(engine) and valid_token(profile_id)
        and valid_token(profile_version) and valid_token(signature, 160)
        and valid_name(leader) and type(roster_token) == 'string'
        and valid_epoch(epoch) and operator_revision ~= nil
        and (operator == '0' or operator == '1')
    if not syntactically_valid then return end

    local exact = generation == state.generation
        and epoch == state.apply_epoch and profile_id == state.profile_id
        and profile_version == state.profile_version
        and engine == state.pt_engine_version
        and signature == state.pt_signature
        and leader == state.leader and roster_token == state.roster_token
    if exact then
        local accepted = accept_operator_tuple(operator_revision, operator)
        if accepted then
            state.pt_state_seen = true
            state.last_pt_state_at = os.clock()
            state.control_lease_seen = true
            state.last_control_lease_at = os.clock()
        end
        return
    end

    -- A well-formed different-generation or higher-epoch state for this local
    -- roster is positive evidence that the bound profile departed. Exact
    -- retired tuples are ignored so delayed packets cannot tear down the
    -- replacement binding; generation nonces themselves are never ordered.
    local p = player()
    local packet_roster = split(roster_token, ',')
    local contains_local = false
    for _, name in ipairs(packet_roster) do
        if p and name:lower() == p.name:lower() then contains_local = true end
    end
    if authority_is_retired(generation, epoch) then return end
    local different_generation = generation ~= state.generation
    local newer_same_generation = not different_generation
        and epoch > state.apply_epoch
    local conflicting_current = not different_generation
        and epoch == state.apply_epoch
    local expected_reload_authority = successor_is_authorized(generation,
        epoch, leader, roster_token, profile_id, profile_version, engine,
        signature)
    if contains_local and expected_reload_authority then
        disarm('authorized full-profile GearSwap reload transition', false,
            true, true)
        return
    end
    if contains_local and different_generation and reload_handoff_is_live() then
        -- A foreign generation at epoch zero is not a recovery successor merely
        -- because it arrived during the grace period. Wait for the exact local
        -- adapter authorization or terminal lifecycle teardown.
        return
    end
    if contains_local and (different_generation or newer_same_generation
        or conflicting_current)
    then
        disarm_all('PartyTactics profile departed', false)
    end
end

local function process_pt_operator_state(fields)
    if not state.armed or fields[1] ~= PT_PREFIX
        or fields[2] ~= 'operator-state' or #fields ~= 11
        or fields[3] ~= state.generation
        or fields[4] ~= state.pt_engine_version
        or fields[5] ~= state.profile_id
        or fields[6] ~= state.profile_version
        or fields[7] ~= state.pt_signature
        or tonumber(fields[8]) ~= state.apply_epoch
        or fields[9] ~= state.leader
    then
        return false
    end
    return accept_operator_tuple(fields[10], fields[11])
end

local function accept_adapter_ack(generation, name, epoch, status, cycle)
    if not state.armed or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
        or not valid_name(name) or not state.roster_set[name]
        or tonumber(cycle) ~= state.renewal_cycle
    then
        return false
    end
    local p = player()
    local maintenance_suspend = status == 'suspended'
        and (state.phase == 'suspend' or state.phase == 'apply')
    local emergency_suspend = status == 'suspended'
        and state.phase == 'drain'
        and state.emergency_hold_cycle == state.renewal_cycle
    if maintenance_suspend or emergency_suspend
    then
        if maintenance_suspend then
            state.suspend_acks[name] = {
                received_at = os.clock(), cycle = state.renewal_cycle,
            }
        end
        if p and p.name == name then
            state.adapter_suspended = true
            state.next_adapter_suspend_at = math.huge
            state.next_report_at = 0
        end
        return true
    elseif status == 'resumed' and state.phase == 'monitor'
        and state.renewal_cycle > 0
    then
        if p and p.name == name then
            state.adapter_suspended = false
            state.emergency_hold_cycle = nil
            state.next_adapter_resume_at = math.huge
            state.next_report_at = 0
        end
        return true
    end
    return false
end

-- Windower IPC is scoped to matching addon instances. LocusPuller therefore
-- hands its exact completion to the SignetKeeper in Tackle's own process; this
-- instance validates it, records the no-loopback local result, and relays it
-- over SignetKeeper's same-addon IPC channel to the leader and other clients.
local function accept_local_puller_drained(generation, epoch, cycle)
    local p = player()
    cycle = tonumber(cycle)
    if not state.armed or not p or p.name ~= 'Tackleberry'
        or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
        or cycle ~= state.renewal_cycle or state.phase ~= 'drain'
        or local_status() ~= 0
    then
        return false
    end
    state.puller_drained = true
    state.next_report_at = 0
    send{PREFIX, 'pullerdrained', state.generation, p.name,
        tostring(state.apply_epoch), tostring(state.renewal_cycle)}
    return true
end

-- The puller uses the same local bridge for resume proof. Tackle keeps
-- replaying the exact resume until the leader advertises a completed census,
-- so a lost same-addon relay is repaired without opening a second authority.
local function accept_local_puller_resumed(generation, epoch, cycle)
    local p = player()
    cycle = tonumber(cycle)
    if not state.armed or not p or p.name ~= 'Tackleberry'
        or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
        or cycle ~= state.renewal_cycle or state.phase ~= 'monitor'
        or cycle < 1
    then
        return false
    end
    state.puller_resumed = true
    send{PREFIX, 'pullerresumed', state.generation, p.name,
        tostring(state.apply_epoch), tostring(state.renewal_cycle)}
    return true
end

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string' then return end
    local fields = split(message, '|')
    if fields[1] == PT_PREFIX then
        if fields[2] == 'stop' then
            if #fields == 10 and valid_generation(fields[3]) then
                accept_stop(fields[10], fields[4], fields[5], fields[6],
                    fields[7], fields[8], fields[9])
            end
            return
        elseif fields[2] == 'operator-state' then
            process_pt_operator_state(fields)
            return
        end
        process_pt_state(fields)
        return
    end
    if fields[1] ~= PREFIX then return end
    local kind = fields[2]
    if kind == 'disarm' then
        local epoch = tonumber(fields[4])
        local exact_current = state.armed and fields[3] == state.generation
            and epoch == state.apply_epoch
        local exact_handoff = not state.armed and reload_handoff_is_live()
            and fields[3] == reload_handoff.generation
            and epoch == reload_handoff.old_epoch
        local exact_successor = reload_handoff_is_live()
            and fields[3] == reload_handoff.authorized_generation
            and epoch == reload_handoff.authorized_epoch
        local exact_pending = not state.armed and pending_authority_is_live()
            and fields[3] == pending_authority.generation
            and epoch == pending_authority.epoch
        if #fields == 6 and (exact_current or exact_handoff
            or exact_successor or exact_pending) then
            terminal_disarm_local(fields[5] or 'remote request',
                fields[6] == '1', false)
            -- A terminal packet is already broadcast by its coordinator.
            -- Never rebroadcast it from a receiver: Windower IPC may deliver
            -- synchronously, and recursive teardown traffic can deadlock
            -- multiple pol.exe processes while their Lua states are unloading.
            -- A missed packet remains fail-closed and is repaired locally by
            -- the control-lease/roster-state expiry paths.
        end
        return
    elseif kind == 'detach' then
        if #fields == 5 and state.armed and fields[3] == state.generation
            and tonumber(fields[4]) == state.apply_epoch
        then
            local generation, epoch = state.generation, state.apply_epoch
            local reason = fields[5] or 'remote adapter detach'
            -- An isolated adapter vanished. Wake every surviving exact
            -- adapter before retiring pulling, then gossip a terminal edge so
            -- one dropped detach cannot orphan the remaining five suspended.
            terminal_disarm_local(reason, true, false)
            send{PREFIX, 'disarm', generation, tostring(epoch), reason, '1'}
        end
        return
    elseif kind == 'reload-request' then
        if #fields == 7 and state.armed and fields[3] == state.generation
            and tonumber(fields[5]) == state.apply_epoch
            and state.roster_set[fields[4]]
            and ((valid_revision(fields[6]) ~= nil
                    and (fields[7] == '0' or fields[7] == '1'))
                or (fields[6] == '-' and fields[7] == '?'))
        then
            local p = player()
            local now = os.clock()
            if not state.reload_request_relays[fields[4]] then
                state.reload_request_relays[fields[4]] = true
                -- One peer relaying this exact request is enough to repair a
                -- copy dropped on the no-loopback leader. Per-source dedupe
                -- keeps the same-addon fan-out finite.
                send{PREFIX, 'reload-request', fields[3], fields[4],
                    fields[5], fields[6], fields[7]}
            end
            if p and p.name == state.leader and in_locus_tomb() then
                state.reload_pending = true
                state.reload_deadline = now + GS_RELOAD_GRACE
                state.reload_requests[fields[4]] = now
                state.next_reload_attempt = state.next_reload_attempt > now
                    and state.next_reload_attempt or now + 1.5
                if fields[7] ~= '?' then
                    merge_reload_operator(fields[6], fields[7] == '1')
                end
            end
            if p and p.name == 'Tackleberry' and state.pt_state_seen then
                send{PREFIX, 'reload-operator', state.generation, p.name,
                    tostring(state.apply_epoch),
                    tostring(state.operator_revision),
                    state.operator_armed and '1' or '0'}
            end
        end
        return
    elseif kind == 'reload-operator' then
        local p = player()
        if #fields == 7 and state.armed and p and p.name == state.leader
            and fields[3] == state.generation
            and fields[4] == 'Tackleberry'
            and tonumber(fields[5]) == state.apply_epoch
            and valid_revision(fields[6]) ~= nil
            and (fields[7] == '0' or fields[7] == '1')
        then
            merge_reload_operator(fields[6], fields[7] == '1')
        end
        return
    elseif kind == 'reload-start' then
        if #fields == 7 and state.armed and fields[3] == state.generation
            and fields[4] == state.leader
            and tonumber(fields[5]) == state.apply_epoch
            and valid_revision(fields[6]) ~= nil
            and (fields[7] == '0' or fields[7] == '1')
            and in_locus_tomb()
        then
            if state.reload_reapply_sent then return end
            local revision = valid_revision(fields[6])
            local desired = fields[7] == '1'
            if state.operator_seen then
                if revision < state.operator_revision then
                    revision, desired = state.operator_revision,
                        state.operator_armed
                elseif revision == state.operator_revision
                    and desired ~= state.operator_armed
                then
                    return
                elseif revision > state.operator_revision then
                    accept_operator_tuple(revision, fields[7])
                end
            end
            state.reload_pending = true
            state.reload_deadline = os.clock() + GS_RELOAD_GRACE
            state.reload_reapply_sent = true
            mark_local_companion_reload()
            reload_handoff = {
                generation=state.generation,
                profile_id=state.profile_id,
                profile_version=state.profile_version,
                engine=state.pt_engine_version,
                signature=state.pt_signature,
                leader=state.leader,
                roster_token=state.roster_token,
                old_epoch=state.apply_epoch,
                operator_revision=revision,
                desired_operator=desired,
                deadline=os.clock() + GS_RELOAD_GRACE,
            }
            -- Gossip the first authenticated start once. This repairs a start
            -- packet dropped for one follower without delayed callbacks or a
            -- second recovery authority.
            send{PREFIX, 'reload-start', fields[3], fields[4], fields[5],
                fields[6], fields[7]}
        end
        return
    elseif kind == 'operator' then
        if #fields == 7 and state.armed and fields[3] == state.generation
            and fields[4] == 'Tackleberry'
            and tonumber(fields[5]) == state.apply_epoch
            and valid_revision(fields[6]) ~= nil
            and (fields[7] == '0' or fields[7] == '1')
        then
            accept_operator_tuple(fields[6], fields[7], 'Tackleberry')
        end
        return
    elseif kind == 'weapon-recovery' then
        local source = fields[4]
        local epoch = tonumber(fields[5])
        local cycle = tonumber(fields[6])
        local p = player()
        if #fields == 6 and state.armed
            and fields[3] == state.generation
            and valid_name(source) and state.roster_set[source]
            and epoch == state.apply_epoch
            and cycle and cycle >= 1 and cycle == math.floor(cycle)
            and p and p.name == state.leader
        then
            if state.phase == 'monitor'
                and cycle == state.renewal_cycle + 1
            then
                broadcast_phase('drain')
            elseif state.phase == 'drain'
                and cycle == state.renewal_cycle
            then
                -- Repair a leader phase packet missed by the detecting peer.
                send{PREFIX, 'phase', state.generation, state.leader,
                    tostring(state.apply_epoch), 'drain', tostring(cycle)}
            end
        end
        return
    end
    if not state.armed or fields[3] ~= state.generation then return end
    if kind == 'report' then
        local name = fields[4]
        local status = tonumber(fields[7])
        local cycle = tonumber(fields[11])
        if #fields == 12 and tonumber(fields[5]) == state.apply_epoch
            and valid_name(name)
            and state.roster_set[name]
            and valid_bit(fields[6]) and valid_bit(fields[8])
            and valid_bit(fields[10]) and valid_bit(fields[12])
            and status and status >= -1 and status <= 3
            and status == math.floor(status)
            and valid_report_phase(fields[9])
            and cycle and cycle >= 0 and cycle == math.floor(cycle)
        then
            remember_report(name, fields[6] == '1', status,
                fields[8] == '1', fields[9], fields[10] == '1', cycle,
                fields[12] == '1')
        end
    elseif kind == 'pullerdrained' then
        if #fields == 6 and fields[4] == 'Tackleberry'
            and tonumber(fields[5]) == state.apply_epoch
            and tonumber(fields[6]) == state.renewal_cycle
            and state.phase == 'drain'
        then
            state.puller_drained = true
        end
    elseif kind == 'pullerresumed' then
        if #fields == 6 and fields[4] == 'Tackleberry'
            and tonumber(fields[5]) == state.apply_epoch
            and tonumber(fields[6]) == state.renewal_cycle
            and state.phase == 'monitor' and state.renewal_cycle > 0
        then
            state.puller_resumed = true
        end
    elseif kind == 'pullerrelease' then
        local p = player()
        if #fields == 6 and fields[4] == state.leader
            and tonumber(fields[5]) == state.apply_epoch
            and tonumber(fields[6]) == state.renewal_cycle
            and state.phase == 'monitor' and state.renewal_cycle > 0
            and p and p.name == 'Tackleberry'
        then
            state.puller_release_authorized = true
            state.next_puller_resume_at = 0
            request_puller_resume(os.clock())
        end
    elseif kind == 'adapter' then
        if #fields == 7 then
            accept_adapter_ack(fields[3], fields[4], fields[5], fields[6],
                fields[7])
        end
    elseif kind == 'phase' then
        local source, epoch = fields[4], tonumber(fields[5])
        local phase, cycle = fields[6], fields[7]
        if #fields == 7 and source == state.leader
            and epoch == state.apply_epoch
            and (phase == 'drain' or phase == 'suspend'
                or phase == 'apply' or phase == 'resume')
        then
            if phase == 'drain' and state.phase == 'drain'
                and tonumber(cycle) == state.renewal_cycle
            then
                state.emergency_request_pending = false
                state.next_emergency_request_at = 0
            else
                apply_phase(phase, cycle)
            end
        end
    elseif kind == 'census' then
        local source, epoch = fields[4], tonumber(fields[5])
        if #fields == 7 and source == state.leader
            and epoch == state.apply_epoch
            and fields[6] == 'ready'
            and tonumber(fields[7]) == state.renewal_cycle
            and state.phase == 'monitor'
        then
            local first_ready = not state.census_ready
            state.census_ready = true
            if first_ready and state.operator_seen then
                relay_operator_to_puller(true)
            end
        end
    end
end)

windower.register_event('prerender', function()
    if not state.armed then
        if terminal_restore then
            tick_terminal_restore(os.clock())
            return
        end
        -- Never infer ownership from the equipped item while idle. A manually
        -- equipped Signet staff may belong to the user or another profile.
        -- Only retained in-process ownership from this exact lifecycle may
        -- start the orphan-recovery worker.
        local restore_needed = state.weapon_locked
            or state.weapon_restore_pending
        if restore_needed and not reload_handoff_is_live() then
            -- A failed/expired recovery handoff or a freshly loaded keeper can
            -- inherit the physical staff without an active controller. Convert
            -- that orphaned ownership into the same persistent gear-only worker
            -- instead of losing the retry after one GearSwap command.
            begin_terminal_restore(nil, false)
            pending_authority = nil
            reset_state(false)
        end
        return
    end
    local now = os.clock()
    if not in_locus_tomb() then
        disarm_all('left the Locus Dire Bat battlefield', false)
        return
    end
    -- Windower IPC does not promise sender loopback, so the explicit adapter
    -- arm remains authoritative. Only an instance that actually observed the
    -- matching leader state can use its later silence as departure evidence.
    local control_lease_at = state.last_control_lease_at or state.bound_at
    if not control_lease_at
        or now - control_lease_at > CONTROL_LEASE_STALE_AFTER
    then
        -- The exact coordinator disappeared. Fail open only for the adapter
        -- lanes this authority had suspended, then retire the authority. A
        -- transient heartbeat loss must not orphan AutoWS, rolls, or support
        -- helpers OFF after SignetKeeper forgets how to resume them.
        disarm_all('PartyTactics control lease became stale', true)
        return
    end
    if roster_state_timed_out(now) then
        -- A required client or its keeper has vanished. Retire automatic
        -- pulling and wake any suspended adapter instead of continuing without
        -- six-member Signet visibility or hanging in maintenance forever.
        disarm_all('six-client Signet reporting became stale', true)
        return
    end
    tick_reload(now)
    if not state.armed then return end
    if state.phase == 'monitor' and (state.weapon_restore_pending
        or staff_equipped())
    then
        if not state.weapon_restore_pending then
            -- A retained snapshot remains exact across an authenticated reapply.
            -- After a raw addon reload the snapshot is nil, so fail closed on
            -- the temporary staff and verify GearSwap's stable current mode.
            state.weapon_restore_pending = true
            state.weapon_restore_requests = 0
        end
        state.census_ready = false
        state.next_census_at = 0
        enforce_suspended_combat_hold()
        if not state.adapter_suspended then
            begin_weapon_recovery(now)
        end
        restore_weapon_slots(now)
    end
    if state.emergency_request_pending
        and state.phase == 'drain'
        and state.emergency_hold_cycle == state.renewal_cycle
        and now >= state.next_emergency_request_at
    then
        local p = player()
        if p then
            send{PREFIX, 'weapon-recovery', state.generation, p.name,
                tostring(state.apply_epoch),
                tostring(state.renewal_cycle)}
            state.next_emergency_request_at = now
                + EMERGENCY_REQUEST_RETRY_INTERVAL
        end
    end
    if state.phase == 'drain' and now >= state.next_puller_drain_at then
        request_puller_drain(now)
    end
    if state.phase == 'drain'
        and state.emergency_hold_cycle == state.renewal_cycle
        and not state.adapter_suspended
        and now >= state.next_adapter_suspend_at
    then
        request_adapter_suspend(now)
    end
    if state.emergency_hold_cycle == state.renewal_cycle
        and (state.phase == 'drain' or state.phase == 'suspend')
        and state.weapon_restore_pending
    then
        enforce_suspended_combat_hold()
        restore_weapon_slots(now)
    end
    if (state.phase == 'suspend' or state.phase == 'apply')
        and not state.adapter_suspended
        and now >= state.next_adapter_suspend_at
    then
        request_adapter_suspend(now)
    elseif state.phase == 'monitor' and state.renewal_cycle > 0
        and not state.census_ready
    then
        if state.adapter_suspended and now >= state.next_adapter_resume_at then
            request_adapter_resume(now)
        end
        if state.puller_release_authorized
            and now >= state.next_puller_resume_at
        then
            request_puller_resume(now)
        end
    end
    tick_staff(now)
    if now >= state.next_report_at then
        state.next_report_at = now + REPORT_INTERVAL
        report_local()
    end
    tick_leader(now)
end)

windower.register_event('gain buff', function(buff_id)
    if state.armed and tonumber(buff_id) == SIGNET_BUFF_ID then
        restore_weapon_slots()
        state.next_report_at = 0
        chat('Local Signet confirmed; waiting for the other members.', 158)
    end
end)

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = tostring(command or 'status'):lower()
    if command == 'armpt' then
        if #args == 10 then
            armpt(args[1], args[2], args[3], args[4], args[5], args[6],
                args[7], args[8], args[9], args[10])
        end
    elseif command == '__ackpt' then
        if #args == 2 then
            acknowledge_adapter_binding(args[1], args[2])
        end
    elseif command == 'authorize' then
        if #args == 8 then
            authorize_successor(args[1], args[2], args[3], args[4], args[5],
                args[6], args[7], args[8])
        end
    elseif command == 'stoppt' then
        if #args == 6 then
            accept_stop(args[1], args[2], args[3], args[4], args[5],
                args[6], 'PartyTactics local stop fence')
        end
    elseif command == '__adapter' then
        if #args == 5 then
            accept_adapter_ack(args[1], args[2], args[3], args[4], args[5])
        end
    elseif command == '__pullerdrained' then
        if #args == 3 then
            accept_local_puller_drained(args[1], args[2], args[3])
        end
    elseif command == '__pullerresumed' then
        if #args == 3 then
            accept_local_puller_resumed(args[1], args[2], args[3])
        end
    elseif command == 'operator' then
        if #args == 4 and state.armed
            and args[1] == state.generation
            and tonumber(args[2]) == state.apply_epoch
        then
            local accepted = accept_operator_tuple(args[3], args[4])
            if accepted then
                -- This exact local adapter replay is the real cross-addon
                -- PartyTactics heartbeat. Remote SignetKeeper relays update
                -- operator state but do not extend this local control lease.
                state.control_lease_seen = true
                state.last_control_lease_at = os.clock()
            end
        end
    elseif command == 'gsreload' then
        if #args == 2 then mark_gsreload(args[1], args[2]) end
    elseif command == '__pullerlost' then
        if #args == 2 and state.armed and args[1] == state.generation
            and tonumber(args[2]) == state.apply_epoch
        then
            disarm_all('LocusPuller addon unloaded', true)
        end
    elseif command == 'detach' then
        if #args == 2 then
            detach_exact(args[1], args[2], 'PartyTactics adapter detached')
        end
    elseif command == 'off' or command == 'disarm' then
        disarm_all('manual emergency stop', true)
    elseif command == 'status' then
        chat(('v%s | %s | generation=%s epoch=%s cycle=%s | profile=%s v%s | phase=%s | census=%s | control-lease=%s | PT-IPC=%s | operator=%s@%s | puller-drained=%s | reload=%s | staff=%s | Signet=%s | lock=%s | weapon=%s.')
            :format(_addon.version, state.armed and 'BOUND' or 'OFF',
                tostring(state.generation or '-'),
                tostring(state.apply_epoch or '-'),
                tostring(state.renewal_cycle),
                tostring(state.profile_id or '-'),
                tostring(state.profile_version or '-'), state.phase,
                state.census_ready and 'ready' or 'holding',
                state.control_lease_seen and 'local' or 'awaiting',
                state.pt_state_seen and 'observed' or 'not-looped-back',
                state.operator_armed and 'armed' or 'unarmed',
                tostring(state.operator_revision or '-'),
                state.puller_drained and 'yes' or 'no',
                state.reload_pending and 'pending' or 'clear',
                accessible_staff_available() and 'available' or 'missing',
                has_signet() and 'up' or 'down',
                state.weapon_locked and 'owned' or 'released',
                state.weapon_restore_pending and 'restoring'
                    or combat_weapon_restored() and 'restored' or 'unverified'))
        chat(('  last-terminal=%s | gen/epoch=%s/%s')
            :format(last_terminal and last_terminal.reason or '-',
                last_terminal and tostring(last_terminal.generation) or '-',
                last_terminal and tostring(last_terminal.epoch or '-') or '-'))
        chat(('  raw-main=%s raw-sub=%s | expected-main=%s expected-sub=%s | GearSwap reapplies=%s')
            :format(tostring(equipped_slot_id('main') or '?'),
                tostring(equipped_slot_id('sub') or '?'),
                tostring(state.pre_staff_main_id or '-'),
                tostring(state.pre_staff_sub_id or '-'),
                tostring(state.weapon_restore_requests)))
        if state.armed and player() and player().name == state.leader then
            for _, name in ipairs(state.roster) do
                local report = state.reports[name]
                chat(('  %s: %s / status %s / staff %s / phase %s / adapter %s / weapon %s')
                    :format(name,
                        report and (report.signet and 'Signet' or 'no Signet') or 'no report',
                        report and tostring(report.status) or '-',
                        report and (report.has_staff and 'yes' or 'NO') or '-',
                        report and tostring(report.phase) or '-',
                        report and (report.suspended and 'suspended' or 'running') or '-',
                        report and (report.weapon_restored and 'restored' or 'WAIT') or '-'))
            end
        end
    else
        chat('Commands: status | off. PartyTactics arms and detaches this companion automatically.')
    end
end)

windower.register_event('zone change', function()
    disarm_all('zone change', true)
end)

windower.register_event('logout', function()
    disarm_all('logout', true)
end)

windower.register_event('unload', function()
    -- Raw coordinator loss is recoverable, unlike zone/logout teardown. Wake
    -- every exact adapter before releasing distributed ownership so its
    -- AutoWS/support lanes cannot remain orphaned in the suspended state.
    consume_terminal_restore_on_unload()
    -- Unload callbacks must be strictly process-local. Broadcasting from an
    -- unloading Lua state can synchronously enter the same teardown callback
    -- in every client and hang the Windower processes. Surviving peers remain
    -- fail-closed and retire themselves when the controller lease expires.
    terminal_disarm_local('addon unload', true, false, true)
end)

-- GearSwap survives a raw SignetKeeper reload, while this new Lua state starts
-- intentionally unbound. Announce only the process-local instance token to the
-- currently active pinned adapter. The adapter cannot arm from this message;
-- a newer token merely holds its own lanes OFF and asks PartyTactics for the
-- existing fully validated successor-authority recovery.
windower.send_command(('gs c ptgs action %s keeper-instance %s')
    :format(ADAPTER_CONTROLLER, INSTANCE_NONCE))

chat('Loaded v'.._addon.version..' idle; PartyTactics owns profile binding.')
