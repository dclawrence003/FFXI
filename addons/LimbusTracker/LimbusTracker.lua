--[[
LimbusTracker

Standalone Limbus chest rotation tracker for Windower 4.

Copyright (c) 2026 OpenAI

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the names of the copyright holders nor the names of contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'LimbusTracker'
_addon.author = 'OpenAI Codex at the direction of Dolomedes'
_addon.version = '0.2.0'
_addon.commands = {'limbustracker', 'lt'}

local config = require('config')
local texts = require('texts')
local packets = require('packets')
local http = require('socket.http')
local ltn12 = require('ltn12')

http.TIMEOUT = 1

local defaults = {
    mode = 'limbus',
    view = 'self',
    sync_inventorycore = true,
    display = {
        pos = {x = 20, y = 250},
        text = {
            font = 'Consolas',
            size = 10,
            color = {alpha = 255, red = 240, green = 240, blue = 240},
            stroke = {width = 2, alpha = 190, red = 0, green = 0, blue = 0},
        },
        bg = {
            visible = true,
            alpha = 155,
            red = 0,
            green = 0,
            blue = 0,
        },
        flags = {
            bold = false,
            draggable = true,
            right = false,
            bottom = false,
        },
        padding = 5,
    },
}

local startup_player = windower.ffxi.get_player()
local settings_character = startup_player and startup_player.name or 'Unknown'
settings_character = tostring(settings_character):gsub('[^%w_-]', '_')
local settings = config.load(
    ('data/settings_%s.xml'):format(settings_character), defaults)
local display = texts.new('${value}', settings.display, settings)

local data_dir = windower.addon_path .. 'data\\'
local history_path = nil
local state = nil
local pending_chest = nil
local previous_units = {}
local current_sector = {Temenos = nil, Apollyon = nil}
local last_temp_scan = 0
local last_currency_request = 0
local last_sync_attempt = 0

local sectors = {
    Temenos = {'North', 'West', 'East', 'Central'},
    Apollyon = {'NW', 'SW', 'NE', 'SE'},
}

local function chat(color, message)
    windower.add_to_chat(color, '[LimbusTracker] ' .. message)
end

local function save_settings()
    settings:save()
end

local function player_name()
    local player = windower.ffxi.get_player()
    return player and player.name or nil
end

local function sanitize(value)
    return tostring(value or 'Unknown'):gsub('[^%w_-]', '_')
end

local function new_state(name)
    return {
        version = 1,
        character = name,
        targets = {Temenos = {}, Apollyon = {}},
        events = {Temenos = {}, Apollyon = {}},
    }
end

local function normalize_state(value, name)
    if type(value) ~= 'table' then value = new_state(name) end
    value.version = 1
    value.character = name or value.character or 'Unknown'
    value.targets = type(value.targets) == 'table' and value.targets or {}
    value.events = type(value.events) == 'table' and value.events or {}
    for area in pairs(sectors) do
        value.targets[area] = type(value.targets[area]) == 'table'
            and value.targets[area] or {}
        value.events[area] = type(value.events[area]) == 'table'
            and value.events[area] or {}
    end
    return value
end

local function is_array(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return maximum == count
end

local function serialize(value, depth)
    local kind = type(value)
    if kind == 'nil' then return 'nil' end
    if kind == 'boolean' or kind == 'number' then return tostring(value) end
    if kind == 'string' then return string.format('%q', value) end
    if kind ~= 'table' then error('Unsupported history value: ' .. kind) end

    depth = depth or 0
    local indent = string.rep('    ', depth)
    local child_indent = string.rep('    ', depth + 1)
    local output = {'{'}
    if is_array(value) then
        for index = 1, #value do
            output[#output + 1] = child_indent
                .. serialize(value[index], depth + 1) .. ','
        end
    else
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(left, right)
            return tostring(left) < tostring(right)
        end)
        for _, key in ipairs(keys) do
            output[#output + 1] = child_indent .. '[' .. serialize(key)
                .. '] = ' .. serialize(value[key], depth + 1) .. ','
        end
    end
    output[#output + 1] = indent .. '}'
    return table.concat(output, '\n')
end

local function load_history_file(path, name)
    local ok, value = pcall(dofile, path)
    if not ok then
        ok, value = pcall(dofile, path .. '.bak')
    end
    return normalize_state(ok and value or nil, name)
end

local function save_history()
    if not history_path or not state then return false end
    if not windower.dir_exists(data_dir) then windower.create_dir(data_dir) end

    local temporary = history_path .. '.tmp'
    local backup = history_path .. '.bak'
    local file, open_error = io.open(temporary, 'w')
    if not file then
        chat(167, 'Could not save history: ' .. tostring(open_error))
        return false
    end
    file:write('return ', serialize(state), '\n')
    file:close()

    os.remove(backup)
    os.rename(history_path, backup)
    local replaced, rename_error = os.rename(temporary, history_path)
    if not replaced then
        os.rename(backup, history_path)
        chat(167, 'Could not replace history: ' .. tostring(rename_error))
        return false
    end
    os.remove(backup)
    return true
end

local function initialize_character()
    local name = player_name()
    if not name then return false end
    if not windower.dir_exists(data_dir) then windower.create_dir(data_dir) end
    local path = data_dir .. 'history_' .. sanitize(name) .. '.lua'
    if history_path ~= path or not state then
        history_path = path
        state = load_history_file(history_path, name)
    end
    return true
end

local function current_area()
    local info = windower.ffxi.get_info()
    local zone_id = info and info.zone or nil
    if zone_id == 37 then return 'Temenos' end
    if zone_id == 38 then return 'Apollyon' end
    return nil
end

local function should_show()
    if settings.mode == 'off' then return false end
    if settings.mode == 'always' then return true end
    return current_area() ~= nil
end

local function sector_for_item(item_id)
    if item_id >= 9956 and item_id <= 9962 then return 'Temenos', 'North' end
    if item_id >= 9963 and item_id <= 9969 then return 'Temenos', 'West' end
    if item_id >= 9970 and item_id <= 9976 then return 'Temenos', 'East' end
    if item_id >= 9977 and item_id <= 9980 then return 'Temenos', 'Central' end
    if item_id >= 9981 and item_id <= 9985 then return 'Apollyon', 'NW' end
    if item_id >= 9986 and item_id <= 9989 then return 'Apollyon', 'SW' end
    if item_id >= 9990 and item_id <= 9994 then return 'Apollyon', 'NE' end
    if item_id >= 9995 and item_id <= 9998 then return 'Apollyon', 'SE' end
    return nil, nil
end

local function scan_limbus_data()
    local temporary = windower.ffxi.get_items('temporary') or {}
    for _, slot in pairs(temporary) do
        if type(slot) == 'table' and tonumber(slot.id or slot.item_id) then
            local area, sector = sector_for_item(tonumber(slot.id or slot.item_id))
            if area then current_sector[area] = sector end
        end
    end
end

local function request_currency_two()
    pcall(function() packets.inject(packets.new('outgoing', 0x115, {})) end)
    last_currency_request = os.time()
end

local function json_escape(value)
    return tostring(value):gsub('[%z\1-\31\\"]', function(character)
        local replacements = {['"'] = '\\"', ['\\'] = '\\\\',
            ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n',
            ['\r'] = '\\r', ['\t'] = '\\t'}
        return replacements[character]
            or ('\\u%04x'):format(character:byte())
    end)
end

local function json_encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return tostring(value) end
    if kind == 'string' then return '"' .. json_escape(value) .. '"' end
    if kind ~= 'table' then return 'null' end
    local output = {}
    if is_array(value) then
        for index = 1, #value do output[#output + 1] = json_encode(value[index]) end
        return '[' .. table.concat(output, ',') .. ']'
    end
    for key, item in pairs(value) do
        output[#output + 1] = '"' .. json_escape(key) .. '":'
            .. json_encode(item)
    end
    table.sort(output)
    return '{' .. table.concat(output, ',') .. '}'
end

local function sync_event(event, area)
    if not settings.sync_inventorycore or event.synced then return false end
    local body = json_encode({
        character = state.character,
        area = area,
        chest = event.chest,
        target_id = event.target_id,
        units = event.units,
        signature = event.signature,
    })
    local response = {}
    local ok, request_ok, code = pcall(http.request, {
        url = 'http://127.0.0.1:8787/api/limbus/chest',
        method = 'POST',
        headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response),
    })
    if ok and request_ok and tonumber(code) == 200 then
        event.synced = true
        return true
    end
    return false
end

local function sync_pending()
    if not state or not settings.sync_inventorycore then return end
    local changed, attempted = false, 0
    for area in pairs(sectors) do
        for _, event in ipairs(state.events[area]) do
            if not event.synced and attempted < 3 then
                attempted = attempted + 1
                if sync_event(event, area) then changed = true end
            end
        end
    end
    if changed then save_history() end
    last_sync_attempt = os.time()
end

local function compute_rotation(area_state, area)
    local events = area_state or {}
    local last_seen = {}
    local recent = {}
    local last_bonus = nil
    for index = #events, 1, -1 do
        local event = events[index]
        if event.chest and not last_seen[event.chest] then
            last_seen[event.chest] = index
        end
        if not last_bonus and tonumber(event.units) == 5000 then
            last_bonus = event
        end
        if #recent < 5 then recent[#recent + 1] = event end
    end

    local learned = 0
    for _ in pairs(last_seen) do learned = learned + 1 end
    local next_chest = nil
    if learned == #sectors[area] then
        for _, chest in ipairs(sectors[area]) do
            if not next_chest or last_seen[chest] < last_seen[next_chest] then
                next_chest = chest
            end
        end
    end
    return {
        next = next_chest,
        learned = learned,
        total = #sectors[area],
        last_bonus = last_bonus,
        recent = recent,
    }
end

local function next_text(rotation)
    if rotation.next then return rotation.next end
    return ('Learn %d/%d'):format(rotation.learned, rotation.total)
end

local function recent_text(rotation)
    if #rotation.recent == 0 then return '--' end
    local output = {}
    for _, event in ipairs(rotation.recent) do
        local units = tonumber(event.units) == 5000 and '5*' or '3'
        output[#output + 1] = ('%s:%s'):format(event.chest or '?', units)
    end
    return table.concat(output, ' > ')
end

local function state_lines(history)
    local lines = {('LimbusTracker [%s]'):format(history.character)}
    for _, area in ipairs({'Temenos', 'Apollyon'}) do
        local rotation = compute_rotation(history.events[area], area)
        local bonus = rotation.last_bonus and rotation.last_bonus.chest or '--'
        lines[#lines + 1] = ('%s  Next: %s  Bonus: %s'):format(
            area, next_text(rotation), bonus)
        lines[#lines + 1] = '  Recent: ' .. recent_text(rotation)
    end
    return lines
end

local function compact_name(name)
    local value = tostring(name or '?')
    return #value > 7 and value:sub(1, 7) or value
end

local function roster_states()
    local output = {}
    if not windower.dir_exists(data_dir) then return output end
    for _, filename in pairs(windower.get_dir(data_dir) or {}) do
        local character = filename:match('^history_(.+)%.lua$')
        if character then
            local path = data_dir .. filename
            local loaded = history_path == path and state
                or load_history_file(path, character)
            output[#output + 1] = loaded
        end
    end
    table.sort(output, function(left, right)
        return tostring(left.character) < tostring(right.character)
    end)
    return output
end

local function roster_lines()
    local lines = {'LimbusTracker [Roster]'}
    for _, history in ipairs(roster_states()) do
        local temenos = compute_rotation(history.events.Temenos, 'Temenos')
        local apollyon = compute_rotation(history.events.Apollyon, 'Apollyon')
        lines[#lines + 1] = ('%-7s T:%-9s A:%s'):format(
            compact_name(history.character), next_text(temenos),
            next_text(apollyon))
    end
    if #lines == 1 then lines[#lines + 1] = 'No character history yet.' end
    return lines
end

local function render()
    if not should_show() then
        display:hide()
        return
    end
    initialize_character()
    local lines = settings.view == 'roster' and roster_lines()
        or (state and state_lines(state)
            or {'LimbusTracker', 'Waiting for a logged-in character...'})
    display:text(table.concat(lines, '\n'))
    display:show()
end

local function backfill_target(area, target_id, chest)
    local target_key = 'id_' .. tostring(target_id)
    state.targets[area][target_key] = chest
    for _, event in ipairs(state.events[area]) do
        if event.target_id == target_id and not event.chest then
            event.chest = chest
            event.synced = false
        end
    end
end

local function record_chest(area, target_id, chest, units, signature)
    if not initialize_character() then return end
    local target_key = 'id_' .. tostring(target_id)
    chest = chest or state.targets[area][target_key]
    if chest then backfill_target(area, target_id, chest) end

    for _, event in ipairs(state.events[area]) do
        if event.signature == signature then return end
    end
    local event = {
        chest = chest,
        target_id = target_id,
        units = units,
        opened_at = os.time(),
        signature = signature,
        synced = false,
    }
    state.events[area][#state.events[area] + 1] = event
    save_history()
    if sync_event(event, area) then save_history() end
    render()
    chat(158, ('Recorded %s %s: %d units.'):format(
        area, chest or 'unknown chest', units))
end

local function begin_chest(target_id)
    local area = current_area()
    if not area then return end
    local mob = windower.ffxi.get_mob_by_id(target_id)
    if not mob or not mob.name or mob.name:lower() ~= 'treasure chest' then return end
    initialize_character()
    local target_key = 'id_' .. tostring(target_id)
    pending_chest = {
        area = area,
        chest = current_sector[area]
            or (state and state.targets[area][target_key] or nil),
        target_id = target_id,
        started = os.time(),
    }
    coroutine.schedule(request_currency_two, 0.5)
    coroutine.schedule(request_currency_two, 2)
end

local function finish_chest_if_ready(packet)
    if not pending_chest or os.time() - pending_chest.started > 15 then
        pending_chest = nil
        return
    end
    local field = pending_chest.area .. ' Units'
    local before = previous_units[field]
    local after = packet[field]
    local gained = before and after and (after - before) or nil
    if gained == 3000 or gained == 5000 then
        local name = player_name() or 'Unknown'
        local signature = table.concat({
            name, pending_chest.area, pending_chest.target_id,
            before, after, pending_chest.started,
        }, ':')
        record_chest(pending_chest.area, pending_chest.target_id,
            pending_chest.chest, gained, signature)
        pending_chest = nil
    end
end

local function set_mode(mode)
    if mode ~= 'limbus' and mode ~= 'always' and mode ~= 'off' then
        chat(123, 'Usage: //lt mode limbus|always|off')
        return
    end
    settings.mode = mode
    save_settings()
    render()
    chat(158, 'Display mode: ' .. mode)
end

local function print_status()
    initialize_character()
    local temenos = state and #state.events.Temenos or 0
    local apollyon = state and #state.events.Apollyon or 0
    chat(207, ('mode=%s | view=%s | character=%s'):format(
        settings.mode, settings.view, player_name() or 'unknown'))
    chat(207, ('saved openings: Temenos=%d, Apollyon=%d | InventoryCore sync=%s')
        :format(temenos, apollyon,
            settings.sync_inventorycore and 'on' or 'off'))
end

local function print_help()
    chat(207, '//lt status | refresh | toggle')
    chat(207, '//lt mode limbus|always|off | view self|roster')
    chat(207, '//lt pos <x> <y> | sync on|off|now')
end

windower.register_event('load', function()
    initialize_character()
    scan_limbus_data()
    request_currency_two()
    render()
end)

windower.register_event('login', function()
    coroutine.schedule(function()
        initialize_character()
        scan_limbus_data()
        request_currency_two()
        render()
    end, 2)
end)

windower.register_event('zone change', function()
    pending_chest = nil
    current_sector = {Temenos = nil, Apollyon = nil}
    coroutine.schedule(function()
        scan_limbus_data()
        request_currency_two()
        render()
    end, 1)
end)

windower.register_event('outgoing chunk', function(id, original)
    if id ~= 0x01A then return end
    local ok, packet = pcall(packets.parse, 'outgoing', original)
    if ok and packet and packet.Target then begin_chest(packet.Target) end
end)

windower.register_event('incoming chunk', function(id, original, modified)
    if id ~= 0x118 then return end
    local ok, packet = pcall(packets.parse, 'incoming', modified or original)
    if not ok or not packet then return end
    finish_chest_if_ready(packet)
    previous_units['Temenos Units'] = packet['Temenos Units']
    previous_units['Apollyon Units'] = packet['Apollyon Units']
end)

windower.register_event('prerender', function()
    local now = os.time()
    if now - last_temp_scan >= 1 then
        last_temp_scan = now
        scan_limbus_data()
        render()
    end
    if now - last_currency_request >= 300 then request_currency_two() end
    if now - last_sync_attempt >= 30 then sync_pending() end
end)

windower.register_event('addon command', function(command, ...)
    command = tostring(command or 'toggle'):lower()
    local args = {...}
    if command == 'status' then
        print_status()
    elseif command == 'refresh' then
        if initialize_character() then
            state = load_history_file(history_path, player_name())
        end
        render()
        chat(158, 'History reloaded from disk.')
    elseif command == 'toggle' then
        set_mode(settings.mode == 'off' and 'limbus' or 'off')
    elseif command == 'show' then
        set_mode('always')
    elseif command == 'hide' then
        set_mode('off')
    elseif command == 'mode' then
        set_mode(tostring(args[1] or ''):lower())
    elseif command == 'view' then
        local view = tostring(args[1] or ''):lower()
        if view ~= 'self' and view ~= 'roster' then
            chat(123, 'Usage: //lt view self|roster')
            return
        end
        settings.view = view
        save_settings()
        render()
        chat(158, 'View: ' .. view)
    elseif command == 'pos' then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if not x or not y then
            chat(123, 'Usage: //lt pos <x> <y>')
            return
        end
        display:pos(x, y)
        settings.display.pos.x = x
        settings.display.pos.y = y
        save_settings()
    elseif command == 'sync' then
        local action = tostring(args[1] or ''):lower()
        if action == 'on' or action == 'off' then
            settings.sync_inventorycore = action == 'on'
            save_settings()
            if settings.sync_inventorycore then sync_pending() end
            chat(158, 'InventoryCore sync: ' .. action)
        elseif action == 'now' then
            sync_pending()
            chat(158, 'InventoryCore sync attempted.')
        else
            chat(123, 'Usage: //lt sync on|off|now')
        end
    elseif command == 'help' or command == '--help' then
        print_help()
    else
        print_help()
    end
end)
