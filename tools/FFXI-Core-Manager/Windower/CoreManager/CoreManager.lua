_addon.name = 'CoreManager'
_addon.author = 'OpenAI Codex'
_addon.version = '1.3.0'
_addon.command = 'core'
_addon.commands = {'core', 'cores'}

local manager_root = (os.getenv('LOCALAPPDATA') or '.') .. '\\FFXIManager'
local request_root = manager_root .. '\\requests'
local status_root = manager_root .. '\\status'
local layout_root = manager_root .. '\\layouts'
local applied_layout_signature = nil
local timers_settings_path = windower.windower_path .. 'plugins\\settings\\timers.xml'
local timers_leader = 'Dolomedes'
local timers_targets = {
    {name = 'Dolomedes', y = 300},
    {name = 'Tackleberry', y = 149},
    {name = 'Kickpuncher', y = 149},
    {name = 'Barneystinson', y = 149},
    {name = 'Smalls', y = 125},
    {name = 'Achoo', y = 125},
}
local timers_default_y = 300
local timers_by_name = {}
for _, target in ipairs(timers_targets) do
    target.key = target.name:lower()
    timers_by_name[target.key] = target
end

local timers_layout_running = false
local timers_queue = {}
local timers_queued = {}
local timers_active = nil
local timers_last_completed = {}
local timers_manual_batch = false
local timers_auto_cooldown = 8
local timers_recovery_generation = 0
local timers_recovery_all = false
local timers_last_recovery_reason = 'none'
local timers_last_recovery_at = nil

local function apply_aspect_ratio(width, height)
    width = tonumber(width)
    height = tonumber(height)
    if not width or not height then
        local settings = windower.get_windower_settings()
        width = settings and tonumber(settings.x_res)
        height = settings and tonumber(settings.y_res)
    end
    if not width or not height or height == 0 then
        windower.add_to_chat(
            123,
            '[CoreManager] Could not determine the current render dimensions.')
        return
    end

    local ratio = width / height
    windower.send_command(
        ('config AdjustAspectRatio false; config AspectRatio %.8f'):format(ratio))
    windower.add_to_chat(
        207,
        ('[CoreManager] Applied aspect ratio %.4f from %dx%d.'):format(
            ratio, width, height))
end

local function get_character()
    local player = windower.ffxi.get_player()
    return player and player.name or nil
end

local function safe_name(name)
    return name:gsub('[^%w_-]', '_')
end

local function log_timer_event(message)
    local character = get_character() or 'Unknown'
    local path = manager_root .. '\\timers-' .. safe_name(character) .. '.log'
    local file = io.open(path, 'a')
    if not file then
        return
    end
    file:write(('%s | %s\n'):format(os.date('%Y-%m-%d %H:%M:%S'), message))
    file:close()
end

local function timer_settings_fallback()
    return table.concat({
        '<?xml version="1.1" ?>',
        '<settings>',
        '    <global>',
        '        <RecastX>20</RecastX>',
        '        <RecastY>350</RecastY>',
        '        <BuffsX>200</BuffsX>',
        '        <BuffsY>350</BuffsY>',
        '        <CustomX>380</CustomX>',
        '        <CustomY>350</CustomY>',
        '    </global>',
        '</settings>',
        '',
    }, '\n')
end

local function set_timer_xml_value(xml, tag, value)
    local pattern = '(<' .. tag .. '>)[^<]*(</' .. tag .. '>)'
    local count
    xml, count = xml:gsub(pattern, function(open_tag, close_tag)
        return open_tag .. tostring(value) .. close_tag
    end, 1)
    if count > 0 then
        return xml
    end

    local close_pos = xml:find('</global>', 1, true)
    if not close_pos then
        return nil
    end
    local line = ('        <%s>%s</%s>\n'):format(tag, tostring(value), tag)
    return xml:sub(1, close_pos - 1) .. line .. xml:sub(close_pos)
end

local function write_timer_layout(y)
    local file = io.open(timers_settings_path, 'r')
    local xml = file and file:read('*a') or nil
    if file then
        file:close()
    end
    if not xml or not xml:find('<settings', 1, true)
            or not xml:find('<global>', 1, true) then
        xml = timer_settings_fallback()
    end

    local values = {
        {'RecastX', 20}, {'BuffsX', 200}, {'CustomX', 380},
        {'RecastY', y}, {'BuffsY', y}, {'CustomY', y},
    }
    for _, entry in ipairs(values) do
        xml = set_timer_xml_value(xml, entry[1], entry[2])
        if not xml then
            windower.add_to_chat(123, '[CoreManager] Timers XML has no global root.')
            return false
        end
    end

    file = io.open(timers_settings_path, 'w')
    if not file then
        windower.add_to_chat(123, '[CoreManager] Could not write Timers settings.')
        return false
    end
    file:write(xml)
    file:close()
    return true
end

local function get_timer_target(name)
    if not name then
        return nil
    end
    return timers_by_name[tostring(name):lower()]
end

local process_timer_queue

local function finish_timer_queue()
    -- Timers has one global XML file. Keep Dolo's layout as the harmless
    -- on-disk fallback after the requested client has captured its own Y.
    write_timer_layout(timers_default_y)
    timers_layout_running = false
    if timers_manual_batch then
        windower.add_to_chat(207, '[CoreManager] Applied per-character Timers placement.')
    end
    timers_manual_batch = false
end

process_timer_queue = function()
    if get_character() ~= timers_leader or timers_active then
        return
    end

    local target = table.remove(timers_queue, 1)
    if not target then
        finish_timer_queue()
        return
    end

    timers_queued[target.key] = nil
    timers_active = target
    timers_layout_running = true
    log_timer_event(('recovery start: %s y=%d'):format(target.name, target.y))

    -- Unload only the affected client. The old implementation unloaded all
    -- six first, leaving some clients without Timers for roughly 30 seconds.
    windower.send_command(('send %s unload timers'):format(target.name))
    coroutine.schedule(function()
        if not write_timer_layout(target.y) then
            log_timer_event('recovery failed: could not write Timers XML')
            timers_active = nil
            process_timer_queue()
            return
        end

        windower.send_command(('send %s load timers'):format(target.name))
        coroutine.schedule(function()
            write_timer_layout(timers_default_y)
            timers_last_completed[target.key] = os.time()
            log_timer_event(('recovery complete: %s y=%d'):format(target.name, target.y))
            timers_active = nil
            process_timer_queue()
        end, 2)
    end, 1)
end

local function enqueue_timer_target(target, force)
    if not target or timers_queued[target.key]
            or (timers_active and timers_active.key == target.key) then
        return false
    end

    local last_completed = timers_last_completed[target.key]
    if not force and last_completed
            and os.time() - last_completed < timers_auto_cooldown then
        return false
    end

    timers_queue[#timers_queue + 1] = target
    timers_queued[target.key] = true
    return true
end

local function queue_timer_targets(targets, force, announce)
    local added = 0
    for _, target in ipairs(targets) do
        if enqueue_timer_target(target, force) then
            added = added + 1
        end
    end

    if announce then
        timers_manual_batch = true
        if added > 0 then
            windower.add_to_chat(207, '[CoreManager] Applying per-character Timers placement...')
        elseif timers_layout_running then
            windower.add_to_chat(207, '[CoreManager] Timers placement is already in progress.')
        end
    end

    if added > 0 then
        process_timer_queue()
    elseif not timers_active and #timers_queue == 0 then
        finish_timer_queue()
    end
end

local function request_timer_target(name, force, announce)
    local target = get_timer_target(name)
    if not target then
        if announce then
            windower.add_to_chat(123, '[CoreManager] Unknown Timers character: ' .. tostring(name))
        end
        return
    end

    if get_character() == timers_leader then
        queue_timer_targets({target}, force, announce)
        return
    end

    local force_arg = force and ' force' or ''
    windower.send_command(
        ('send %s core timer-recover %s%s'):format(
            timers_leader, target.name, force_arg))
    if announce then
        windower.add_to_chat(
            207,
            ('[CoreManager] Forwarded %s Timers recovery to %s.'):format(
                target.name, timers_leader))
    end
end

local function apply_timer_layout(force)
    local character = get_character()
    if character ~= timers_leader then
        if force then
            windower.send_command('send ' .. timers_leader .. ' core timers')
            windower.add_to_chat(
                207,
                '[CoreManager] Forwarded Timers placement to ' .. timers_leader .. '.')
        end
        return
    end

    queue_timer_targets(timers_targets, force, force)
end

local function schedule_timer_recovery(reason, delay, recover_all)
    timers_recovery_generation = timers_recovery_generation + 1
    timers_recovery_all = timers_recovery_all or recover_all
    local generation = timers_recovery_generation

    coroutine.schedule(function()
        if generation ~= timers_recovery_generation then
            return
        end

        local character = get_character()
        if not character then
            return
        end

        local run_all = timers_recovery_all and character == timers_leader
        timers_recovery_all = false
        timers_last_recovery_reason = reason
        timers_last_recovery_at = os.date('%H:%M:%S')
        log_timer_event(
            ('automatic request: %s (%s)'):format(
                reason, run_all and 'all clients' or character))

        if run_all then
            queue_timer_targets(timers_targets, false, false)
        else
            request_timer_target(character, false, false)
        end
    end, delay)
end

local function show_timer_status()
    local character = get_character()
    local target = get_timer_target(character)
    if not target then
        windower.add_to_chat(123, '[CoreManager] No configured Timers layout for this character.')
        return
    end

    local last_request = timers_last_recovery_at
        and (timers_last_recovery_reason .. ' at ' .. timers_last_recovery_at)
        or 'none this session'
    windower.add_to_chat(
        207,
        ('[CoreManager] %s Timers target: X 20/200/380, Y %d; last recovery: %s.'):format(
            character, target.y, last_request))
    if character == timers_leader then
        local active = timers_active and timers_active.name or 'none'
        windower.add_to_chat(
            207,
            ('[CoreManager] Timers coordinator: active %s, queued %d.'):format(
                active, #timers_queue))
    end
end

local function get_saved_layout_dimensions()
    local character = get_character()
    if not character then
        return nil, nil
    end

    local path = layout_root .. '\\' .. safe_name(character) .. '.txt'
    local file = io.open(path, 'r')
    if not file then
        return nil, nil
    end

    local layout = file:read('*a'):gsub('%s+$', '')
    file:close()
    local x, y, width, height = layout:match(
        '^([^|]+)|([^|]+)|(%d+)|(%d+)|')
    return tonumber(width), tonumber(height)
end

local function request(action)
    local character = get_character()
    if not character then
        windower.add_to_chat(123, '[CoreManager] No logged-in character was detected.')
        return
    end

    local path = request_root .. '\\' .. safe_name(character) .. '.request'
    local file = io.open(path, 'w')
    if not file then
        windower.add_to_chat(
            123,
            '[CoreManager] Companion manager is not installed or its request folder is unavailable.')
        return
    end

    file:write(action)
    file:close()
    windower.add_to_chat(
        207,
        ('[CoreManager] Requested %s for %s.'):format(action, character))
end

local function status()
    local character = get_character()
    if not character then
        windower.add_to_chat(123, '[CoreManager] No logged-in character was detected.')
        return
    end

    local path = status_root .. '\\' .. safe_name(character) .. '.txt'
    local file = io.open(path, 'r')
    if not file then
        windower.add_to_chat(
            123,
            '[CoreManager] No status is available. Check that the companion manager is running.')
        return
    end

    local message = file:read('*a')
    file:close()
    windower.add_to_chat(207, '[CoreManager] ' .. message:gsub('%s+$', ''))
end

local function apply_layout(force)
    local character = get_character()
    if not character then
        return
    end

    local path = layout_root .. '\\' .. safe_name(character) .. '.txt'
    local file = io.open(path, 'r')
    if not file then
        return
    end

    local layout = file:read('*a'):gsub('%s+$', '')
    file:close()
    if not force and layout == applied_layout_signature then
        return
    end

    local x, y, width, height = layout:match(
        '^([^|]+)|([^|]+)|(%d+)|(%d+)|')
    if not x then
        windower.add_to_chat(123, '[CoreManager] Invalid saved window layout.')
        return
    end

    windower.send_command(
        ('wincontrol resize %s %s; wait 1; wincontrol move %s %s'):format(
            width, height, x, y))
    coroutine.schedule(function()
        apply_aspect_ratio(width, height)
    end, 2)
    applied_layout_signature = layout
    windower.add_to_chat(
        207,
        ('[CoreManager] Applied %sx%s at %s,%s through WinControl.'):format(
            width, height, x, y))
    schedule_timer_recovery('window layout reapplied', 6, false)
end

windower.register_event('addon command', function(command, option, argument)
    command = command and command:lower() or 'status'
    option = option and option:lower() or nil

    if command == 'apply' then
        request('apply')
    elseif command == 'layout' then
        request('layout')
        coroutine.schedule(function()
            apply_layout(true)
        end, 3)
    elseif command == 'aspect' then
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    elseif command == 'timers' then
        if option == 'me' then
            request_timer_target(get_character(), true, true)
        elseif option == 'status' then
            show_timer_status()
        else
            apply_timer_layout(true)
        end
    elseif command == 'timer-recover' then
        -- Internal IPC command. Dolo alone serializes writes to the one shared
        -- Timers XML file, preventing clients from racing each other.
        if get_character() == timers_leader then
            local force = argument and argument:lower() == 'force'
            local target = get_timer_target(option)
            if target then
                queue_timer_targets({target}, force, false)
            end
        end
    elseif command == 'status' or command == '' then
        status()
    else
        windower.add_to_chat(207, '[CoreManager] Commands:')
        windower.add_to_chat(207, '  //core status  - show this character\'s assignment')
        windower.add_to_chat(207, '  //core apply   - reapply this character\'s CPU assignment')
        windower.add_to_chat(207, '  //core layout  - reapply this character\'s saved window rectangle')
        windower.add_to_chat(207, '  //core aspect  - correct aspect ratio for this window')
        windower.add_to_chat(207, '  //core timers  - apply per-character Timers positions')
        windower.add_to_chat(207, '  //core timers me      - recover only this client\'s Timers position')
        windower.add_to_chat(207, '  //core timers status  - show recovery state and expected position')
    end
end)

windower.register_event('login', function()
    coroutine.schedule(function()
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end, 5)
    schedule_timer_recovery(
        'login', 20, get_character() == timers_leader)
end)

windower.register_event('zone change', function()
    -- Allow the post-zone UI and IPC channel to settle, then recover. Dolo
    -- performs a catch-up pass for the party; an independently zoning client
    -- requests only its own placement.
    schedule_timer_recovery(
        'zone change', 12, get_character() == timers_leader)
end)

coroutine.schedule(function()
    if get_character() then
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end
end, 5)

schedule_timer_recovery(
    'addon load', 20, get_character() == timers_leader)

local function poll_layout()
    apply_layout(false)
    coroutine.schedule(poll_layout, 2)
end

coroutine.schedule(poll_layout, 7)
