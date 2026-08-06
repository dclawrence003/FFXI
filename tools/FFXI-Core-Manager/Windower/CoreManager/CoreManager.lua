_addon.name = 'CoreManager'
_addon.author = 'OpenAI Codex'
_addon.version = '1.1.2'
_addon.command = 'core'
_addon.commands = {'core', 'cores'}

local manager_root = (os.getenv('LOCALAPPDATA') or '.') .. '\\FFXIManager'
local request_root = manager_root .. '\\requests'
local status_root = manager_root .. '\\status'
local layout_root = manager_root .. '\\layouts'
local applied_layout_signature = nil

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
    elseif command == 'status' or command == '' then
        status()
    else
        windower.add_to_chat(207, '[CoreManager] Commands:')
        windower.add_to_chat(207, '  //core status  - show this character\'s assignment')
        windower.add_to_chat(207, '  //core apply   - reapply this character\'s CPU assignment')
        windower.add_to_chat(207, '  //core layout  - reapply this character\'s saved window rectangle')
        windower.add_to_chat(207, '  //core aspect  - correct aspect ratio for this window')
    end
end)

windower.register_event('login', function()
    coroutine.schedule(function()
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end, 5)
end)

coroutine.schedule(function()
    if get_character() then
        request('apply')
        local width, height = get_saved_layout_dimensions()
        apply_aspect_ratio(width, height)
    end
end, 5)

local function poll_layout()
    apply_layout(false)
    coroutine.schedule(poll_layout, 2)
end

coroutine.schedule(poll_layout, 7)
