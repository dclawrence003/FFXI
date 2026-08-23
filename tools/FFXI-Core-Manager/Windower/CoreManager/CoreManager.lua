_addon.name = 'CoreManager'
_addon.author = 'OpenAI Codex'
_addon.version = '1.2.0'
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
local timers_layout_running = false
local timers_layout_applied = false

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

local load_timer_target

local function finish_timer_layout()
    coroutine.schedule(function()
        -- Leave a sensible on-disk default after all clients have captured their own Y.
        write_timer_layout(300)
        timers_layout_running = false
        timers_layout_applied = true
        windower.add_to_chat(207, '[CoreManager] Applied per-character Timers placement.')
    end, 3)
end

load_timer_target = function(index)
    local target = timers_targets[index]
    if not target then
        finish_timer_layout()
        return
    end
    if not write_timer_layout(target.y) then
        timers_layout_running = false
        return
    end
    windower.send_command(('send %s load timers'):format(target.name))
    coroutine.schedule(function()
        load_timer_target(index + 1)
    end, 3)
end

local function unload_timer_target(index)
    local target = timers_targets[index]
    if not target then
        coroutine.schedule(function()
            load_timer_target(1)
        end, 3)
        return
    end
    windower.send_command(('send %s unload timers'):format(target.name))
    coroutine.schedule(function()
        unload_timer_target(index + 1)
    end, 2)
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
    if timers_layout_running or (timers_layout_applied and not force) then
        return
    end

    timers_layout_running = true
    windower.add_to_chat(207, '[CoreManager] Applying per-character Timers placement...')
    unload_timer_target(1)
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
end

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'status'

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
        apply_timer_layout(true)
    elseif command == 'status' or command == '' then
        status()
    else
        windower.add_to_chat(207, '[CoreManager] Commands:')
        windower.add_to_chat(207, '  //core status  - show this character\'s assignment')
        windower.add_to_chat(207, '  //core apply   - reapply this character\'s CPU assignment')
        windower.add_to_chat(207, '  //core layout  - reapply this character\'s saved window rectangle')
        windower.add_to_chat(207, '  //core aspect  - correct aspect ratio for this window')
        windower.add_to_chat(207, '  //core timers  - apply per-character Timers positions')
    end
end)

windower.register_event('login', function()
    coroutine.schedule(function()
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end, 5)
    coroutine.schedule(function()
        apply_timer_layout(false)
    end, 30)
end)

coroutine.schedule(function()
    if get_character() then
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end
end, 5)

coroutine.schedule(function()
    apply_timer_layout(false)
end, 30)

local function poll_layout()
    apply_layout(false)
    coroutine.schedule(poll_layout, 2)
end

coroutine.schedule(poll_layout, 7)
