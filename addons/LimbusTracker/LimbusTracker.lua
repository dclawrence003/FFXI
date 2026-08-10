--[[
LimbusTracker

Lightweight read-only Windower display for InventoryCore's Limbus history.

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
_addon.version = '0.1.0'
_addon.commands = {'limbustracker', 'lt'}

local config = require('config')
local texts = require('texts')
local http = require('socket.http')
local json = require('json')

http.TIMEOUT = 1

local defaults = {
    mode = 'limbus',
    view = 'self',
    poll_seconds = 5,
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

local api_url = 'http://127.0.0.1:8787/api/dashboard'
local latest = nil
local last_poll = 0
local last_error = nil

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

local function current_area()
    local info = windower.ffxi.get_info()
    -- Player zone names are available through the resources table only when
    -- requested. Avoid that larger dependency by using the stable Limbus IDs.
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

local function compact_name(name)
    local value = tostring(name or '?')
    return #value > 7 and value:sub(1, 7) or value
end

local function next_text(rotation)
    if not rotation then return '--' end
    if rotation.next then return rotation.next end
    return ('Learn %d/%d'):format(
        tonumber(rotation.learned) or 0, tonumber(rotation.total) or 4)
end

local function recent_text(rotation)
    if not rotation or type(rotation.recent) ~= 'table'
        or #rotation.recent == 0 then
        return '--'
    end
    local output = {}
    for index = 1, math.min(5, #rotation.recent) do
        local event = rotation.recent[index]
        local chest = event.chest or '?'
        local units = tonumber(event.units) == 5000 and '5*' or '3'
        output[#output + 1] = ('%s:%s'):format(chest, units)
    end
    return table.concat(output, ' > ')
end

local function self_lines(row)
    local lines = {('LimbusTracker [%s]'):format(row.character)}
    for _, area in ipairs({'Temenos', 'Apollyon'}) do
        local rotation = row.areas and row.areas[area] or nil
        local bonus = rotation and rotation.last_bonus
            and rotation.last_bonus.chest or '--'
        lines[#lines + 1] = ('%s  Next: %s  Bonus: %s'):format(
            area, next_text(rotation), bonus)
        lines[#lines + 1] = '  Recent: ' .. recent_text(rotation)
    end
    return lines
end

local function roster_lines(rows)
    local lines = {'LimbusTracker [Roster]'}
    for _, row in ipairs(rows or {}) do
        local temenos = row.areas and row.areas.Temenos or nil
        local apollyon = row.areas and row.areas.Apollyon or nil
        lines[#lines + 1] = ('%-7s T:%-9s A:%s'):format(
            compact_name(row.character), next_text(temenos),
            next_text(apollyon))
    end
    return lines
end

local function find_character(rows, name)
    for _, row in ipairs(rows or {}) do
        if row.character == name then return row end
    end
    return nil
end

local function render()
    if not should_show() then
        display:hide()
        return
    end

    local lines
    if not latest or type(latest.characters) ~= 'table' then
        lines = {'LimbusTracker', last_error or 'Waiting for InventoryCore...'}
    elseif settings.view == 'roster' then
        lines = roster_lines(latest.characters)
    else
        local row = find_character(latest.characters, player_name())
        lines = row and self_lines(row)
            or {'LimbusTracker', 'Character not found in InventoryCore.'}
    end
    display:text(table.concat(lines, '\n'))
    display:show()
end

local function refresh(silent)
    local ok, body, code = pcall(http.request, api_url)
    if not ok or tonumber(code) ~= 200 or not body then
        last_error = 'InventoryCore offline (127.0.0.1:8787).'
        render()
        if not silent then chat(123, last_error) end
        return false
    end

    local parsed_ok, payload = pcall(json.parse, body)
    if not parsed_ok or type(payload) ~= 'table'
        or type(payload.characters) ~= 'table' then
        last_error = 'InventoryCore returned invalid dashboard data.'
        render()
        if not silent then chat(123, last_error) end
        return false
    end

    latest = payload
    last_error = nil
    render()
    if not silent then chat(158, 'Limbus history refreshed.') end
    return true
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
    chat(207, ('mode=%s | view=%s | character=%s | api=%s'):format(
        settings.mode, settings.view, player_name() or 'unknown',
        last_error and 'offline' or (latest and 'ready' or 'waiting')))
end

local function print_help()
    chat(207, '//lt refresh | status | toggle')
    chat(207, '//lt mode limbus|always|off')
    chat(207, '//lt view self|roster | pos <x> <y>')
end

windower.register_event('load', function()
    refresh(true)
end)

windower.register_event('login', function()
    coroutine.schedule(function() refresh(true) end, 2)
end)

windower.register_event('zone change', function()
    coroutine.schedule(function()
        refresh(true)
        render()
    end, 1)
end)

windower.register_event('prerender', function()
    local now = os.clock()
    local interval = math.max(1, tonumber(settings.poll_seconds) or 3)
    if now - last_poll >= interval then
        last_poll = now
        refresh(true)
    end
end)

windower.register_event('addon command', function(command, ...)
    command = tostring(command or 'toggle'):lower()
    local args = {...}
    if command == 'refresh' then
        refresh(false)
    elseif command == 'status' then
        print_status()
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
    elseif command == 'help' or command == '--help' then
        print_help()
    else
        print_help()
    end
end)
