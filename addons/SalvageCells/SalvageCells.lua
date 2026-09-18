_addon = _addon or {}
_addon.name = 'SalvageCells'
_addon.author = 'DC03 / OpenAI Codex'
_addon.version = '0.5.1'
_addon.commands = {'salvagecells', 'scells'}

local config = require('config')

local defaults = {
    Enabled = true,
    AutoLot = true,
    AutoPass = true,
    AutoUse = true,
    AutoDrop = true,
    ActionDelay = 3.0,
    UseTimeout = 8.0,
    MaxUseFailures = 3,
    LotRetryDelay = 12.0,
    AssignmentRebroadcastDelay = 1.0,
    Verbose = true,
    -- Stable multibox rotation. This matches the progression roster used by
    -- PartyStart; edit it in settings if the roster or preferred order changes.
    Roster = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo',
    Coordinator = 'Dolomedes',
    PrioritizeCoordinator = true,
}

local settings = config.load(defaults)

-- Old Salvage and Salvage II share these zone IDs. Salvage II has no cells, so
-- this addon remains inert there unless an old-Salvage cell actually appears.
local SALVAGE_ZONES = {
    [73] = true, -- Zhayolm Remnants
    [74] = true, -- Arrapago Remnants
    [75] = true, -- Bhaflau Remnants
    [76] = true, -- Silver Sea Remnants
}

-- Ordered roughly by how quickly a newly-entered character normally wants to
-- regain core combat functions. IDs are the current Windower resource IDs.
local CELLS = {
    {id=5365, name='Incus Cell',          unlock='weapons and shields'},
    {id=5374, name='Opacus Cell',         unlock='job abilities and weapon skills'},
    {id=5375, name='Praecipitatio Cell', unlock='magic'},
    {id=5383, name='Humilus Cell',        unlock='maximum HP'},
    {id=5384, name='Spissatus Cell',      unlock='maximum MP'},
    {id=5373, name='Duplicatus Cell',     unlock='support job'},
    {id=5367, name='Cumulus Cell',        unlock='body equipment'},
    {id=5368, name='Radiatus Cell',       unlock='hand equipment'},
    {id=5369, name='Stratus Cell',        unlock='leg and foot equipment'},
    {id=5366, name='Castellanus Cell',    unlock='head and neck equipment'},
    {id=5372, name='Virga Cell',          unlock='earring and ring equipment'},
    {id=5370, name='Cirrocumulus Cell',   unlock='back and waist equipment'},
    {id=5371, name='Undulatus Cell',      unlock='ranged and ammo equipment'},
    {id=5376, name='Pannus Cell',         unlock='STR'},
    {id=5377, name='Fractus Cell',        unlock='DEX'},
    {id=5378, name='Congestus Cell',      unlock='VIT'},
    {id=5379, name='Nimbus Cell',         unlock='AGI'},
    {id=5380, name='Velum Cell',          unlock='INT'},
    {id=5381, name='Pileus Cell',         unlock='MND'},
    {id=5382, name='Mediocris Cell',      unlock='CHR'},
}

local CELL_BY_ID = {}
local CELL_BY_KEY = {}
for _, cell in ipairs(CELLS) do
    CELL_BY_ID[cell.id] = cell
    CELL_BY_KEY[cell.name:lower()] = cell
    CELL_BY_KEY[cell.name:lower():gsub(' cell$', '')] = cell
end

local state = {
    active_zone = false,
    run_known = false,
    needs = {},
    use_failures = {},
    pending_use = nil,
    pool_actions = {},
    lot_claims = {},
    pool_assignments = {},
    assignment_broadcasts = {},
    assigned_cells = {},
    rotation_cursor = 1,
    last_tick = 0,
    last_item_action = 0,
    last_drop_action = 0,
    last_zone = nil,
    warned_full = false,
}

local function now()
    return os.clock()
end

local function chat(message, color)
    windower.add_to_chat(color or 207, '[SalvageCells] ' .. message)
end

local function verbose(message)
    if settings.Verbose then
        chat(message)
    end
end

local function clear_transient_state()
    state.pending_use = nil
    state.pool_actions = {}
    state.lot_claims = {}
    state.warned_full = false
end

local function reset_coordination()
    state.pool_assignments = {}
    state.assignment_broadcasts = {}
    state.assigned_cells = {}
    state.rotation_cursor = 1
end

local function configured_roster()
    local roster = {}
    local value = tostring(settings.Roster or '')
    for raw_name in value:gmatch('[^,]+') do
        local name = raw_name:gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then
            roster[#roster + 1] = name
        end
    end

    if #roster == 0 then
        local player = windower.ffxi.get_player()
        if player and player.name then
            roster[1] = player.name
        end
    end
    return roster
end

local function same_name(left, right)
    return left and right and left:lower() == right:lower()
end

local function local_player_name()
    local player = windower.ffxi.get_player()
    return player and player.name
end

local function is_coordinator()
    return same_name(local_player_name(), tostring(settings.Coordinator or ''))
end

-- Only characters in p0-p5 whose reported zone matches the coordinator's
-- current zone may receive a pool assignment. This deliberately excludes
-- party members waiting outside the Remnants instance.
local function eligible_roster()
    local roster = configured_roster()
    local party = windower.ffxi.get_party() or {}
    local info = windower.ffxi.get_info() or {}
    local zone = tonumber(info.zone)
    if not zone and party.p0 then
        zone = tonumber(party.p0.zone)
    end

    local present = {}
    for index = 0, 5 do
        local member = party['p' .. index]
        if type(member) == 'table' and member.name
                and tonumber(member.zone) == zone then
            present[member.name:lower()] = true
        end
    end

    -- p0 can briefly be unavailable just after zoning. The coordinator still
    -- knows that its own client is in the active Remnants zone.
    local player_name = local_player_name()
    if player_name and SALVAGE_ZONES[zone] then
        present[player_name:lower()] = true
    end

    local eligible = {}
    for _, name in ipairs(roster) do
        if present[name:lower()] then
            eligible[#eligible + 1] = name
        end
    end
    return eligible
end

local function broadcast_assignment(index, item_id, owner)
    windower.send_ipc_message(('salvagecells:v1:assign:%d:%d:%s'):format(
        index, item_id, owner or '-'))
end

local function assign_next_owner(item_id)
    local roster = configured_roster()
    if #roster == 0 then
        return nil
    end

    local eligible = {}
    for _, name in ipairs(eligible_roster()) do
        eligible[name:lower()] = true
    end

    -- Dolo gets the first copy of every distinct cell type. Once that type has
    -- been assigned to him, duplicate copies continue through the rotation.
    local coordinator = tostring(settings.Coordinator or '')
    if settings.PrioritizeCoordinator and eligible[coordinator:lower()] then
        local coordinator_key = coordinator:lower()
        state.assigned_cells[coordinator_key] = state.assigned_cells[coordinator_key] or {}
        if not state.assigned_cells[coordinator_key][item_id] then
            state.assigned_cells[coordinator_key][item_id] = true
            for index, name in ipairs(roster) do
                if same_name(name, coordinator) then
                    state.rotation_cursor = (index % #roster) + 1
                    break
                end
            end
            return coordinator
        end
    end

    for offset = 0, #roster - 1 do
        local index = ((state.rotation_cursor - 1 + offset) % #roster) + 1
        local owner = roster[index]
        local owner_key = owner:lower()
        state.assigned_cells[owner_key] = state.assigned_cells[owner_key] or {}
        if eligible[owner_key] and not state.assigned_cells[owner_key][item_id] then
            state.assigned_cells[owner_key][item_id] = true
            state.rotation_cursor = (index % #roster) + 1
            return owner
        end
    end

    return nil
end

local function start_run(reason)
    state.needs = {}
    state.use_failures = {}
    for _, cell in ipairs(CELLS) do
        state.needs[cell.id] = true
    end
    state.run_known = true
    clear_transient_state()
    reset_coordination()
    chat('Tracking a fresh old-Salvage run (' .. reason .. ').')
end

local function set_unknown(reason)
    state.run_known = false
    state.needs = {}
    state.use_failures = {}
    clear_transient_state()
    reset_coordination()
    if reason then
        chat(reason, 123)
    end
end

local function inventory_snapshot()
    local bag = windower.ffxi.get_items('inventory')
    local counts = {}
    local slots = {}
    if not bag then
        return counts, slots, 0
    end

    for index, item in pairs(bag) do
        if type(index) == 'number' and type(item) == 'table' and CELL_BY_ID[item.id] then
            local count = tonumber(item.count) or 0
            counts[item.id] = (counts[item.id] or 0) + count
            slots[#slots + 1] = {
                index = index,
                id = item.id,
                count = count,
                status = item.status,
            }
        end
    end

    local free = math.max(0, (tonumber(bag.max) or 0) - (tonumber(bag.count) or 0))
    return counts, slots, free
end

local function treasure_snapshot()
    return windower.ffxi.get_items('treasure') or {}
end

local function pool_has_active_lot(item_id, timestamp)
    local claim = state.lot_claims[item_id]
    return claim and timestamp - claim < settings.LotRetryDelay
end

local function mark_unlocked(item_id)
    local cell = CELL_BY_ID[item_id]
    if not cell then
        return
    end

    state.needs[item_id] = false
    state.use_failures[item_id] = nil
    state.lot_claims[item_id] = nil
    verbose(cell.name .. ' confirmed used; ' .. cell.unlock .. ' no longer needs a cell.')
end

local function scan_treasure(counts, free_slots, timestamp)
    if not settings.Enabled then
        return
    end

    local treasure = treasure_snapshot()
    local present = {}
    local entries = {}

    for index, item in pairs(treasure) do
        if type(index) == 'number' and type(item) == 'table' and CELL_BY_ID[item.item_id] then
            entries[#entries + 1] = {index=index, item_id=item.item_id}
        end
    end
    table.sort(entries, function(left, right) return left.index < right.index end)

    -- Only the configured coordinator creates assignments. Other clients wait
    -- for its IPC broadcast, eliminating rotation drift from load/packet timing.
    for _, entry in ipairs(entries) do
        local index = entry.index
        local item_id = entry.item_id
        present[index] = item_id

        local assignment = state.pool_assignments[index]
        if assignment and assignment.item_id ~= item_id then
            state.pool_actions[index] = nil
            state.pool_assignments[index] = nil
            state.assignment_broadcasts[index] = nil
            assignment = nil
        end
        if not assignment and state.active_zone and state.run_known and is_coordinator() then
            local owner = assign_next_owner(item_id)
            assignment = {
                item_id = item_id,
                owner = owner or false,
            }
            state.pool_assignments[index] = assignment
            broadcast_assignment(index, item_id, owner)
            state.assignment_broadcasts[index] = timestamp
        elseif assignment and state.active_zone and state.run_known and is_coordinator()
                and timestamp - (state.assignment_broadcasts[index] or 0)
                    >= (tonumber(settings.AssignmentRebroadcastDelay) or 1.0) then
            broadcast_assignment(index, item_id, assignment.owner)
            state.assignment_broadcasts[index] = timestamp
        end
    end

    local player_name = local_player_name()

    for _, entry in ipairs(entries) do
        local index = entry.index
        local item_id = entry.item_id
        local assignment = state.pool_assignments[index]
        local owner = assignment and assignment.owner

        local prior = state.pool_actions[index]
        if prior and prior.item_id ~= item_id then
            state.pool_actions[index] = nil
            prior = nil
        end

        if not state.active_zone then
            if settings.AutoPass and not prior then
                windower.ffxi.pass_item(index)
                state.pool_actions[index] = {item_id=item_id, action='pass'}
                verbose('Passing ' .. CELL_BY_ID[item_id].name .. ' outside Salvage.')
            end
        elseif not state.run_known then
            -- A mid-run load has no trustworthy per-cell history. Doing
            -- nothing is safer than lotting a cell another player needs.
        elseif not assignment then
            -- Wait for the coordinator. Passing before an assignment exists
            -- could destroy the cell when the designated client is not ready.
        elseif owner and same_name(owner, player_name)
                and state.needs[item_id] and (counts[item_id] or 0) == 0 then
            if settings.AutoLot and not prior and not pool_has_active_lot(item_id, timestamp) then
                if free_slots > 0 then
                    windower.ffxi.lot_item(index)
                    state.pool_actions[index] = {item_id=item_id, action='lot'}
                    state.lot_claims[item_id] = timestamp
                    verbose('Lotting assigned ' .. CELL_BY_ID[item_id].name
                        .. ' for ' .. CELL_BY_ID[item_id].unlock .. '.')
                    free_slots = free_slots - 1
                elseif not state.warned_full then
                    state.warned_full = true
                    chat('Inventory is full; leaving needed cells untouched.', 123)
                end
            end
        elseif settings.AutoPass and not prior then
            windower.ffxi.pass_item(index)
            state.pool_actions[index] = {item_id=item_id, action='pass'}
            if owner then
                verbose('Passing ' .. CELL_BY_ID[item_id].name .. '; assigned to ' .. owner .. '.')
            else
                verbose('Passing ' .. CELL_BY_ID[item_id].name .. '; every roster member was already assigned one.')
            end
        end
    end

    for index, action in pairs(state.pool_actions) do
        if present[index] ~= action.item_id then
            state.pool_actions[index] = nil
        end
    end
    for index, assignment in pairs(state.pool_assignments) do
        if present[index] ~= assignment.item_id then
            state.pool_assignments[index] = nil
            state.assignment_broadcasts[index] = nil
        end
    end
end

local function update_pending_use(counts, timestamp)
    local pending = state.pending_use
    if not pending then
        return false
    end

    if (counts[pending.id] or 0) < pending.count_before then
        mark_unlocked(pending.id)
        state.pending_use = nil
        return false
    end

    if timestamp - pending.started >= settings.UseTimeout then
        local failures = (state.use_failures[pending.id] or 0) + 1
        state.use_failures[pending.id] = failures
        state.pending_use = nil
        local maximum = math.max(1, tonumber(settings.MaxUseFailures) or 3)
        if failures >= maximum then
            state.needs[pending.id] = false
            state.lot_claims[pending.id] = nil
            chat(CELL_BY_ID[pending.id].name .. ' failed to consume '
                .. failures .. ' times; assuming it was unlocked before reload and moving on.', 123)
        else
            verbose(CELL_BY_ID[pending.id].name .. ' was not consumed (attempt '
                .. failures .. '/' .. maximum .. '); it will be retried.')
        end
        return false
    end

    return true
end

local function use_next_cell(counts, timestamp)
    if not settings.Enabled or not settings.AutoUse or not state.active_zone or not state.run_known then
        return
    end
    if state.pending_use or timestamp - state.last_item_action < settings.ActionDelay then
        return
    end

    for _, cell in ipairs(CELLS) do
        if state.needs[cell.id] and (counts[cell.id] or 0) > 0 then
            windower.send_command('input /item "' .. cell.name .. '" <me>')
            state.pending_use = {
                id = cell.id,
                count_before = counts[cell.id],
                started = timestamp,
            }
            state.last_item_action = timestamp
            verbose('Using ' .. cell.name .. ' to restore ' .. cell.unlock .. '.')
            return
        end
    end
end

local function drop_one_unneeded(slots, timestamp)
    if not settings.Enabled or not settings.AutoDrop then
        return
    end
    if timestamp - state.last_drop_action < 1.0 then
        return
    end

    for _, item in ipairs(slots) do
        local available = item.status == nil or item.status == 0
        local pending_same = state.pending_use and state.pending_use.id == item.id
        local unneeded = (not state.active_zone) or (state.run_known and state.needs[item.id] == false)
        if available and unneeded and not pending_same and item.count > 0 then
            windower.ffxi.drop_item(item.index, item.count)
            state.last_drop_action = timestamp
            verbose('Dropping unneeded ' .. CELL_BY_ID[item.id].name .. ' x' .. item.count .. '.')
            return
        end
    end
end

local function tick(force)
    local timestamp = now()
    if not force and timestamp - state.last_tick < 0.5 then
        return
    end
    state.last_tick = timestamp

    local counts, slots, free_slots = inventory_snapshot()
    update_pending_use(counts, timestamp)
    scan_treasure(counts, free_slots, timestamp)
    use_next_cell(counts, timestamp)
    drop_one_unneeded(slots, timestamp)
end

local function find_cell(words)
    local key = table.concat(words, ' '):lower()
    key = key:gsub('^%s+', ''):gsub('%s+$', '')
    return CELL_BY_KEY[key]
end

local function status()
    local mode
    if not settings.Enabled then
        mode = 'paused'
    elseif not state.active_zone then
        mode = 'outside Salvage'
    elseif not state.run_known then
        mode = 'safe/unknown (use //scells begin at the start of a run)'
    else
        local remaining = 0
        for _, cell in ipairs(CELLS) do
            if state.needs[cell.id] then
                remaining = remaining + 1
            end
        end
        mode = tostring(remaining) .. ' unlocks remaining; coordinator='
            .. tostring(settings.Coordinator)
        if is_coordinator() then
            local eligible = eligible_roster()
            mode = mode .. '; eligible=' .. (#eligible > 0 and table.concat(eligible, ',') or 'none')
        end
    end
    chat('Status: ' .. mode .. '. Lot=' .. tostring(settings.AutoLot)
        .. ', pass=' .. tostring(settings.AutoPass)
        .. ', use=' .. tostring(settings.AutoUse)
        .. ', drop=' .. tostring(settings.AutoDrop) .. '.')
end

windower.register_event('load', function()
    local info = windower.ffxi.get_info() or {}
    state.last_zone = info.zone
    state.active_zone = SALVAGE_ZONES[info.zone] or false
    if state.active_zone then
        set_unknown('Loaded inside a Remnants zone; automation is in safe mode. Use //scells begin only if this is the start of an old-Salvage run.')
    else
        verbose('Loaded. Cells found outside Salvage will be cleaned up.')
    end
    tick(true)
end)
windower.register_event('login', function()
    local info = windower.ffxi.get_info() or {}
    state.last_zone = info.zone
    state.active_zone = SALVAGE_ZONES[info.zone] or false
    if state.active_zone then
        set_unknown('Logged in inside Remnants; per-cell state is unknown and automation is paused safely.')
    end
end)

windower.register_event('zone change', function(new_id, old_id)
    local was_active = SALVAGE_ZONES[old_id or state.last_zone] or false
    state.active_zone = SALVAGE_ZONES[new_id] or false
    state.last_zone = new_id

    if state.active_zone and not was_active then
        start_run('zone entry')
    elseif not state.active_zone and was_active then
        set_unknown(nil)
        verbose('Left Remnants; any leftover cells will be dropped.')
    end
end)

windower.register_event('incoming chunk', function(id)
    if id == 0x0D2 or id == 0x01F or id == 0x020 then
        coroutine.schedule(function() tick(true) end, 0.2)
    end
end)

windower.register_event('prerender', function()
    tick(false)
end)

windower.register_event('ipc message', function(message)
    local index, item_id, owner = message:match('^salvagecells:v1:assign:(%d+):(%d+):([^:]+)$')
    if not index then
        return
    end

    index = tonumber(index)
    item_id = tonumber(item_id)
    if not state.active_zone or not CELL_BY_ID[item_id] then
        return
    end

    local prior = state.pool_assignments[index]
    state.pool_assignments[index] = {
        item_id = item_id,
        owner = owner ~= '-' and owner or false,
    }
    if not prior or prior.item_id ~= item_id or prior.owner ~= state.pool_assignments[index].owner then
        state.pool_actions[index] = nil
    end
    tick(true)
end)

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'status'
    local args = {...}

    if command == 'status' or command == 's' then
        status()
    elseif command == 'on' or command == 'enable' then
        settings.Enabled = true
        settings:save()
        chat('Enabled.')
        tick(true)
    elseif command == 'off' or command == 'disable' or command == 'pause' then
        settings.Enabled = false
        settings:save()
        chat('Paused; no lot, pass, use, or drop actions will be taken.')
    elseif command == 'begin' or command == 'reset' then
        if state.active_zone then
            start_run('manual begin')
            -- Allow every client receiving a Send command to reset before the
            -- coordinator assigns pool entries that are already present.
            coroutine.schedule(function() tick(true) end, 1.0)
        else
            chat('Begin is only accepted inside a Remnants zone.', 123)
        end
    elseif command == 'turn' then
        local wanted = table.concat(args, ' ')
        local roster = configured_roster()
        for index, name in ipairs(roster) do
            if same_name(name, wanted) then
                state.rotation_cursor = index
                chat('The next duplicate cell will be assigned from ' .. name
                    .. '; coordinator priority still applies to first copies.')
                return
            end
        end
        chat('Unknown roster member: ' .. wanted, 123)
    elseif command == 'need' or command == 'done' then
        if args[1] and args[1]:lower() == 'all' then
            if not state.run_known then
                state.run_known = true
            end
            for _, cell in ipairs(CELLS) do
                state.needs[cell.id] = command == 'need'
                state.use_failures[cell.id] = nil
            end
            clear_transient_state()
            chat('Marked all cells as ' .. (command == 'need' and 'needed.' or 'done.'))
            tick(true)
        else
            local cell = find_cell(args)
            if not cell then
                chat('Unknown cell. Example: //scells done incus', 123)
                return
            end
            if not state.run_known then
                state.run_known = true
            end
            state.needs[cell.id] = command == 'need'
            state.use_failures[cell.id] = nil
            state.lot_claims[cell.id] = nil
            chat(cell.name .. ' marked ' .. (command == 'need' and 'needed.' or 'done.'))
            tick(true)
        end
    elseif command == 'help' then
        chat('Commands: status | on | off | begin | turn <name> | need <cell|all> | done <cell|all>.')
        chat('Use begin only at the start of old Salvage when a mid-run load left state unknown.')
    else
        chat('Unknown command. Use //scells help.', 123)
    end
end)
