_addon.name = 'JubileeKeeper'
_addon.author = 'OpenAI Codex'
_addon.version = '2.1.3'
_addon.commands = {'jk', 'jubileekeeper'}

local ITEM_ID = 27593
local ITEM_NAME = 'Jubilee Ring'
local OWNER_NAME = 'Dolomedes'
local EXPECTED_ROSTER_SIZE = 6
local OWNED_ZONE = 190
local EQUIPMENT_KEY = 'right_ring'
local EQUIP_SLOT = 'ring2'
local PT_PREFIX = 'PARTYTACTICS1'
local ADAPTER_CONTROLLER = 'locus-signet'
local ADAPTER_PROTOCOL = '2'
local POLL_INTERVAL = 0.25
local EQUIP_RETRY_INTERVAL = 1.5
local MISSING_CHAT_INTERVAL = 30
local PT_STATE_STALE_AFTER = 12
local GS_RELOAD_GRACE = 25
local EQUIPPABLE_BAG_IDS = {0, 8, 10, 11, 12, 13, 14, 15, 16}

local state = {
    armed = false,
    generation = nil,
    apply_epoch = nil,
    profile_id = nil,
    profile_version = nil,
    pt_engine_version = nil,
    pt_signature = nil,
    leader = nil,
    roster_token = nil,
    roster_set = {},
    pt_state_seen = false,
    last_pt_state_at = nil,
    stale_lease = false,
    stale_lease_since = nil,
    stale_state_reproved_at = nil,
    slot_owned = false,
    lock_needs_reassert = false,
    confirmed = false,
    next_poll_at = 0,
    next_equip_at = 0,
    next_missing_chat_at = 0,
    reload_pending = false,
    reload_deadline = 0,
}
local retired_authorities = {}
local reload_handoff = nil
local pending_authority = nil
local stopped_generations = {}

local function chat(message, color)
    windower.add_to_chat(color or 207,
        '[JubileeKeeper] '..tostring(message))
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
        ('gs c ptgs action %s companion-ready %s %d %s jk %s %s %s %s %s %s')
            :format(ADAPTER_CONTROLLER, state.generation,
                state.apply_epoch, ADAPTER_PROTOCOL, state.profile_id,
                state.profile_version, state.pt_engine_version,
                state.pt_signature, p.name, p.main_job))
    return true
end

local function is_owner()
    local p = player()
    return p and p.name == OWNER_NAME
end

local function in_owned_zone()
    local info = windower.ffxi.get_info and windower.ffxi.get_info() or nil
    return type(info) == 'table' and info.logged_in ~= false
        and tonumber(info.zone) == OWNED_ZONE
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

local function valid_token(value, max_length)
    return type(value) == 'string' and #value > 0
        and #value <= (max_length or 96)
        and value:match('^[A-Za-z0-9_.-]+$') ~= nil
end

local function valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function split(value, separator)
    local result = {}
    if type(value) ~= 'string' then return result end
    for part in value:gmatch('[^'..separator..']+') do
        result[#result + 1] = part
    end
    return result
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

local function roster_identity(roster_token, leader)
    local roster, seen = split(roster_token, ','), {}
    if #roster ~= EXPECTED_ROSTER_SIZE or not valid_name(leader) then
        return nil
    end
    for _, name in ipairs(roster) do
        if not valid_name(name) or seen[name] then return nil end
        seen[name] = true
    end
    if not seen[leader] or not seen[OWNER_NAME] then return nil end
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

local function successor_is_authorized(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    return reload_handoff_is_live()
        and reload_handoff.authorized_generation == generation
        and reload_handoff.authorized_epoch == tonumber(epoch)
        and reload_handoff.profile_id == profile_id
        and reload_handoff.profile_version == profile_version
        and reload_handoff.engine == engine
        and reload_handoff.signature == signature
        and reload_handoff.leader == leader
        and reload_handoff.roster_token == roster_token
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

local function pending_authority_matches(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    return pending_authority_is_live()
        and pending_authority.generation == generation
        and pending_authority.epoch == tonumber(epoch)
        and pending_authority.profile_id == profile_id
        and pending_authority.profile_version == profile_version
        and pending_authority.engine == engine
        and pending_authority.signature == signature
        and pending_authority.leader == leader
        and pending_authority.roster_token == roster_token
end

local function authorize_successor(generation, epoch, profile_id,
    profile_version, engine, signature, leader, roster_token)
    epoch = tonumber(epoch)
    local roster_set = roster_identity(roster_token, leader)
    if not valid_generation(generation) or not valid_epoch(epoch)
        or not is_owner() or not in_owned_zone()
        or authority_is_retired(generation, epoch)
        or not valid_token(profile_id) or not valid_token(profile_version)
        or not valid_token(engine) or not valid_token(signature, 160)
        or not roster_set
    then
        chat('Ignored invalid PartyTactics authority authorization.', 123)
        return false
    end
    if not state.armed and not reload_handoff_is_live() then
        if pending_authority_is_live()
            and not pending_authority_matches(generation, epoch, profile_id,
                profile_version, engine, signature, leader, roster_token)
        then
            chat('Ignored conflicting pending PartyTactics authorization.', 123)
            return false
        end
        pending_authority = {
            generation=generation, epoch=epoch, profile_id=profile_id,
            profile_version=profile_version, engine=engine,
            signature=signature, leader=leader, roster_token=roster_token,
            roster_set=roster_set, deadline=os.clock() + GS_RELOAD_GRACE,
        }
        return true
    end
    if state.armed and not reload_handoff_is_live()
        and generation == state.generation and epoch >= state.apply_epoch
        and state.profile_id == profile_id
        and state.profile_version == profile_version
        and state.pt_engine_version == engine
        and state.pt_signature == signature
        and state.leader == leader and state.roster_token == roster_token
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
        or reload_handoff.roster_token ~= roster_token
    then
        chat('Ignored unauthorized PartyTactics recovery successor.', 123)
        return false
    end
    reload_handoff.authorized_generation = generation
    reload_handoff.authorized_epoch = epoch
    return true
end

local function accessible_item_available()
    for _, bag_id in ipairs(EQUIPPABLE_BAG_IDS) do
        local bag = windower.ffxi.get_items(bag_id)
        if bag and bag.enabled ~= false then
            for _, item in pairs(bag) do
                if type(item) == 'table' and tonumber(item.id) == ITEM_ID
                    and (tonumber(item.count) or 1) > 0
                then
                    return true
                end
            end
        end
    end
    return false
end

local function raw_equipped_item_id()
    local equipment = (windower.ffxi.get_items() or {}).equipment
    if not equipment then return nil end

    local bag_id = tonumber(equipment[EQUIPMENT_KEY..'_bag'])
    local index = tonumber(equipment[EQUIPMENT_KEY])
    if not bag_id or not index or index <= 0 then return 0 end
    local item = windower.ffxi.get_items(bag_id, index)
    return item and tonumber(item.id) or 0
end

local function release_slot()
    if not state.slot_owned then return end
    windower.send_command('gs enable '..EQUIP_SLOT..'; gs c update')
    state.slot_owned = false
    state.lock_needs_reassert = false
end

local function retire_transient_authorities()
    -- A terminal event can arrive after the old adapter detached but before
    -- its explicitly authorized replacement arm reaches this addon.  Clearing
    -- the handoff without retiring that queued generation would let it acquire
    -- ring2 after the profile had already stopped or left the zone.
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

local function disarm(reason, silent, preserve_reload_handoff,
    preserve_slot_ownership)
    local was_armed = state.armed
    if state.armed then
        retire_authority(state.generation, state.apply_epoch)
    end
    if not preserve_slot_ownership then release_slot() end
    state.armed = false
    state.generation = nil
    state.apply_epoch = nil
    state.profile_id = nil
    state.profile_version = nil
    state.pt_engine_version = nil
    state.pt_signature = nil
    state.leader = nil
    state.roster_token = nil
    state.roster_set = {}
    state.pt_state_seen = false
    state.last_pt_state_at = nil
    state.stale_lease = false
    state.stale_lease_since = nil
    state.stale_state_reproved_at = nil
    state.confirmed = false
    state.next_poll_at = 0
    state.next_equip_at = 0
    state.lock_needs_reassert = false
    state.next_missing_chat_at = 0
    state.reload_pending = false
    state.reload_deadline = 0
    if not preserve_reload_handoff then
        retire_transient_authorities()
        reload_handoff = nil
        pending_authority = nil
    end
    if was_armed and not silent then
        chat('Released Dolo\'s right ring'
            ..(reason and ': '..reason or '')..'.')
    end
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

local function accept_stop(target_generation, engine, profile_id,
    profile_version, signature, source, reason)
    if not valid_generation(target_generation)
        or not stop_metadata_matches(engine, profile_id, profile_version,
            signature, source)
    then
        return false
    end
    stopped_generations[target_generation] = true
    local stops_current = state.armed
        and target_generation == state.generation
    local stops_successor = reload_handoff_is_live()
        and reload_handoff.authorized_generation == target_generation
    local stops_predecessor = reload_handoff_is_live()
        and reload_handoff.generation == target_generation
    local stops_pending = pending_authority_is_live()
        and pending_authority.generation == target_generation
    if stops_pending then pending_authority = nil end
    if stops_current or stops_successor or stops_predecessor then
        if state.armed then
            disarm(reason or 'PartyTactics stopped')
        else
            retire_transient_authorities()
            release_slot()
            reload_handoff = nil
            pending_authority = nil
        end
    end
    return true
end

local function armpt(generation, epoch, profile_id, profile_version, engine,
    signature, leader, roster_token)
    epoch = tonumber(epoch)
    local roster_set = roster_identity(roster_token, leader)
    if not is_owner() or not in_owned_zone() then
        disarm('outside owned character/zone', true)
        return false
    end
    if not valid_generation(generation) or not valid_epoch(epoch)
        or not valid_token(profile_id) or not valid_token(profile_version)
        or not valid_token(engine) or not valid_token(signature, 160)
        or not roster_set
    then
        chat('Refused invalid PartyTactics authority.', 167)
        return false
    end

    local matching_identity = state.profile_id == profile_id
        and state.profile_version == profile_version
        and state.pt_engine_version == engine
        and state.pt_signature == signature
        and state.leader == leader and state.roster_token == roster_token
    local same_authority = state.armed and state.generation == generation
        and state.apply_epoch == epoch and matching_identity
    local authorized_successor = successor_is_authorized(generation, epoch,
        profile_id, profile_version, engine, signature, leader, roster_token)
    local pending_match = pending_authority_matches(generation, epoch,
        profile_id, profile_version, engine, signature, leader, roster_token)
    -- The live checks above retire an expired pending/handoff generation.
    -- Test retirement only after they have had that chance, or the very arm
    -- that observes expiry could fall through as an otherwise fresh bind.
    if authority_is_retired(generation, epoch) then
        chat('Ignored retired PartyTactics arm request.', 123)
        return false
    end
    if state.armed and not same_authority then
        local same_generation_reapply = generation == state.generation
            and epoch > state.apply_epoch and matching_identity
        if not same_generation_reapply and not authorized_successor then
            chat('Ignored stale, conflicting, or unfenced PartyTactics arm request.', 123)
            return false
        end
    elseif not state.armed and reload_handoff_is_live()
        and not authorized_successor
    then
        chat('Ignored recovery bind without the exact authorized successor.', 123)
        return false
    elseif not state.armed and pending_authority_is_live()
        and not pending_match
    then
        chat('Ignored arm outside the pending exact authorization.', 123)
        return false
    end

    if state.armed and not same_authority then
        retire_authority(state.generation, state.apply_epoch)
    end
    state.armed = true
    state.generation = generation
    state.apply_epoch = epoch
    state.profile_id = profile_id
    state.profile_version = profile_version
    state.pt_engine_version = engine
    state.pt_signature = signature
    state.leader = leader
    state.roster_token = roster_token
    state.roster_set = roster_set
    pending_authority = nil
    state.next_poll_at = 0
    state.next_equip_at = 0
    if not same_authority then state.lock_needs_reassert = true end
    state.next_missing_chat_at = 0
    if same_authority and state.stale_lease
        and state.stale_state_reproved_at
        and state.stale_state_reproved_at > (state.stale_lease_since or 0)
        and os.clock() - state.stale_state_reproved_at <= PT_STATE_STALE_AFTER
    then
        -- A stale PT heartbeat releases ring2 immediately, but does not
        -- tombstone an otherwise live exact authority. Reacquire only after
        -- both an exact fresh PT state and the current adapter's local arm
        -- reassertion; a delayed state packet alone cannot restore the ring.
        state.stale_lease = false
        state.stale_lease_since = nil
        state.stale_state_reproved_at = nil
        state.next_poll_at = 0
    end
    -- An idempotent old-authority probe can occur while GearSwap rebuilds; it
    -- must not erase the bounded successor fence. Only an accepted replacement
    -- authority consumes recovery state.
    if not same_authority then
        state.reload_pending = false
        state.reload_deadline = 0
        reload_handoff = nil
    end
    if not same_authority then
        state.pt_state_seen = false
        state.last_pt_state_at = nil
        state.stale_lease = false
        state.stale_lease_since = nil
        state.stale_state_reproved_at = nil
        state.confirmed = false
        chat(('Bound to PartyTactics %s v%s; locking %s in Dolo\'s right ring slot.')
            :format(profile_id, profile_version, ITEM_NAME), 158)
    end
    return true
end

local function detach_exact(generation, epoch, reason)
    if not state.armed or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
    then
        return false
    end
    local preserve = reload_handoff_is_live()
        and reload_handoff.generation == state.generation
        and reload_handoff.old_epoch == state.apply_epoch
    disarm(reason or 'PartyTactics adapter detached', false, preserve,
        preserve)
    return true
end

local function maintain(now)
    if not state.armed then
        if state.slot_owned and not reload_handoff_is_live() then
            release_slot()
        end
        return
    end
    if not is_owner() or not in_owned_zone() then
        disarm('outside owned character/zone')
        return
    end
    if state.reload_pending and now >= state.reload_deadline then
        disarm('GearSwap reload recovery expired')
        return
    end
    if state.pt_state_seen and (not state.last_pt_state_at
        or now - state.last_pt_state_at > PT_STATE_STALE_AFTER)
    then
        if not state.stale_lease then
            state.stale_lease = true
            state.stale_lease_since = now
            state.stale_state_reproved_at = nil
            release_slot()
            chat('PartyTactics state became stale; right ring released until exact state and adapter authority return.', 123)
        end
        return
    end
    if state.stale_lease then return end
    if now < state.next_poll_at then return end
    state.next_poll_at = now + POLL_INTERVAL

    if not accessible_item_available() then
        release_slot()
        if now >= state.next_missing_chat_at then
            state.next_missing_chat_at = now + MISSING_CHAT_INTERVAL
            chat(ITEM_NAME..' is not in Inventory or an enabled Mog '
                ..'Wardrobe; right ring remains under normal GearSwap control.',
                167)
        end
        return
    end

    if raw_equipped_item_id() ~= ITEM_ID then
        state.confirmed = false
        if now >= state.next_equip_at then
            -- Native /equip bypasses GearSwap's cached equipment comparison.
            -- Do not lock the slot until the following raw inventory read
            -- proves that the requested ring actually reached ring2.
            windower.send_command('input /equip '..EQUIP_SLOT..' "'..ITEM_NAME
                ..'"')
            state.next_equip_at = now + EQUIP_RETRY_INTERVAL
        end
        return
    end

    local first_confirmation = not state.confirmed
    if first_confirmation then
        state.confirmed = true
        chat(ITEM_NAME..' confirmed in Dolo\'s right ring slot.', 158)
    end
    if not state.slot_owned or state.lock_needs_reassert then
        -- A validated GearSwap reload explicitly marks the lock for one repair.
        -- Ordinary polling does not resend the same disable command forever.
        windower.send_command('gs disable '..EQUIP_SLOT)
        state.slot_owned = true
        state.lock_needs_reassert = false
    end
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
    local epoch, operator_revision, operator = tonumber(fields[10]),
        tonumber(fields[14]), fields[15]
    local contains_owner = false
    for _, name in ipairs(split(roster_token, ',')) do
        if name == OWNER_NAME then contains_owner = true end
    end
    local syntactically_valid = valid_generation(generation)
        and valid_token(engine) and valid_token(profile_id)
        and valid_token(profile_version) and valid_token(signature, 160)
        and type(leader) == 'string' and contains_owner
        and valid_epoch(epoch) and valid_epoch(operator_revision)
        and (operator == '0' or operator == '1')
    if not syntactically_valid then return end
    if generation == state.generation and epoch == state.apply_epoch
        and profile_id == state.profile_id
        and profile_version == state.profile_version
        and engine == state.pt_engine_version
        and signature == state.pt_signature
        and leader == state.leader and roster_token == state.roster_token
    then
        state.pt_state_seen = true
        state.last_pt_state_at = os.clock()
        if state.stale_lease then
            state.stale_state_reproved_at = os.clock()
        end
        return
    end
    if authority_is_retired(generation, epoch) then return end
    local different_generation = generation ~= state.generation
    local newer_same_generation = not different_generation
        and epoch > state.apply_epoch
    local conflicting_current = not different_generation
        and epoch == state.apply_epoch
    local expected_reload_transition = successor_is_authorized(generation,
        epoch, profile_id, profile_version, engine, signature, leader,
        roster_token)
    if expected_reload_transition then return end
    if different_generation and reload_handoff_is_live() then return end
    if different_generation or newer_same_generation or conflicting_current then
        disarm('PartyTactics profile departed')
    end
end

local function mark_gsreload(generation, epoch)
    if not state.armed or generation ~= state.generation
        or tonumber(epoch) ~= state.apply_epoch
    then
        return false
    end
    state.reload_pending = true
    state.reload_deadline = os.clock() + GS_RELOAD_GRACE
    reload_handoff = {
        generation=state.generation,
        old_epoch=state.apply_epoch,
        profile_id=state.profile_id,
        profile_version=state.profile_version,
        engine=state.pt_engine_version,
        signature=state.pt_signature,
        leader=state.leader,
        roster_token=state.roster_token,
        deadline=state.reload_deadline,
    }
    state.next_poll_at = 0
    state.next_equip_at = 0
    state.lock_needs_reassert = true
    chat('GearSwap reload observed; preserving and reasserting the exact Jubilee Ring guard.', 158)
    return true
end

windower.register_event('prerender', function()
    maintain(os.clock())
end)

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'status'
    local args = {...}
    if command == 'armpt' then
        if #args == 8 then
            armpt(args[1], args[2], args[3], args[4], args[5], args[6],
                args[7], args[8])
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
    elseif command == 'gsreload' then
        if #args == 2 then mark_gsreload(args[1], args[2]) end
    elseif command == 'detach' then
        if #args == 2 then
            detach_exact(args[1], args[2], 'PartyTactics adapter detached')
        end
    elseif command == 'off' or command == 'disarm' then
        disarm('manual')
    elseif command == 'status' then
        chat(('v%s | %s | generation %s epoch %s | profile %s v%s | PT-state %s | reload %s | item %s | slot %s | raw %s | lock %s')
            :format(_addon.version, state.armed and 'BOUND' or 'off',
                state.generation or '-', tostring(state.apply_epoch or '-'),
                state.profile_id or '-', state.profile_version or '-',
                state.pt_state_seen and 'observed' or 'not-looped-back',
                state.reload_pending and 'pending' or 'clear',
                accessible_item_available() and 'available' or 'missing',
                EQUIP_SLOT, tostring(raw_equipped_item_id()),
                state.slot_owned and 'owned' or 'released'))
    else
        chat('Commands: status | off. PartyTactics binds this guard automatically.')
    end
end)

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string' then return end
    local fields = split(message, '|')
    if fields[1] ~= PT_PREFIX then return end
    if fields[2] == 'stop' then
        if #fields == 10 and valid_generation(fields[3]) then
            accept_stop(fields[10], fields[4], fields[5], fields[6],
                fields[7], fields[8], 'PartyTactics stopped')
        end
        return
    end
    process_pt_state(fields)
end)

windower.register_event('zone change', function()
    disarm('zone change')
end)

windower.register_event('logout', function()
    disarm('logout')
end)

windower.register_event('unload', function()
    disarm('addon unload', true)
end)

chat('Loaded v'.._addon.version..' idle; PartyTactics owns profile binding.')
