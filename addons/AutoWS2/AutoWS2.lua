--[[
AutoWS2

Aftermath-aware weapon-skill automation inspired by AutoWS 0.3.1 by Lorand.
This is a clean implementation and does not require Lorand's lor_libs.
Original AutoWS: https://github.com/lorand-ffxi/addons/tree/master/AutoWS
No AutoWS source is redistributed in this file.

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

_addon.name = 'AutoWS2'
_addon.author = 'OpenAI Codex, inspired by Lorand'
_addon.version = '0.1.0'
_addon.command = 'autows2'
_addon.commands = {'autows2', 'aws2'}

local config = require('config')
local texts = require('texts')
local res = require('resources')

local AFTERMATH_IDS = {
    lv1 = 270,
    lv2 = 271,
    lv3 = 272,
    relic = 273,
}

local defaults = {
    display = {
        visible = true,
        pos = {x = 500, y = 50},
        text = {
            font = 'Consolas',
            size = 10,
            color = {alpha = 255, red = 255, green = 255, blue = 255},
            stroke = {width = 2, alpha = 180, red = 0, green = 0, blue = 0},
        },
        bg = {
            visible = true,
            alpha = 145,
            red = 0,
            green = 0,
            blue = 0,
        },
        flags = {
            bold = true,
            draggable = true,
            right = false,
            bottom = false,
        },
        padding = 5,
    },
    profiles = {},
}

local settings = config.load(defaults)
local display = texts.new('${value}', settings.display)

local enabled = false
local current_profile_key = nil
local current_profile = nil
local current_weapon = nil
local reserve_latched = false
local reserve_reason = nil
local aftermath_expires_at = nil
local aftermath_timer_unknown = false
local last_aftermath_active = nil
local last_command_at = 0
local last_check_at = 0
local pause_until = 0
local last_decision = 'Idle'

local telemetry = {
    last_tp = nil,
    cumulative_gain = 0,
    samples = {},
}

local function chat(color, message)
    windower.add_to_chat(color or 207, '[AutoWS2] ' .. message)
end

local function trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function bool_word(value)
    return value and 'ON' or 'OFF'
end

local function sanitize(value)
    return tostring(value or 'Unknown'):gsub('[^%w_-]', '_')
end

local function get_player()
    return windower.ffxi.get_player()
end

local function get_main_weapon_name()
    local items = windower.ffxi.get_items()
    if not items or not items.equipment then
        return 'Unknown'
    end

    local slot = tonumber(items.equipment.main)
    local bag = tonumber(items.equipment.main_bag)
    if not slot or slot == 0 or not bag then
        return 'Unarmed'
    end

    local ok, item = pcall(windower.ffxi.get_items, bag, slot)
    if not ok or not item or not item.id then
        return 'Unknown'
    end

    local resource = res.items[item.id]
    return resource and resource.en or ('Item ' .. tostring(item.id))
end

local function base_profile(weapon)
    local profile = {
        normal_ws = '',
        normal_tp = 1000,
        hp_min = 5,
        hp_max = 100,
        aftermath_enabled = false,
        aftermath_mode = 'shadow',
        aftermath_type = 'lv3',
        aftermath_ws = '',
        aftermath_duration = 180,
        fallback_reserve = 20,
        minimum_reserve = 12,
        maximum_reserve = 35,
        safety_margin = 4,
        rate_window = 12,
        minimum_rate_span = 4,
    }

    if weapon == 'Tizona' then
        profile.normal_ws = 'Expiacion'
        profile.aftermath_enabled = true
        profile.aftermath_type = 'lv3'
        profile.aftermath_ws = 'Expiacion'
        profile.aftermath_duration = 180
    end

    return profile
end

local function fill_missing(profile, weapon)
    local template = base_profile(weapon)
    for key, value in pairs(template) do
        if profile[key] == nil then
            profile[key] = value
        end
    end
    return profile
end

local function profile_key(player, weapon)
    return table.concat({
        sanitize(player and player.name),
        sanitize(player and player.main_job),
        sanitize(weapon),
    }, '__')
end

local function save_settings()
    settings:save()
end

local function reset_telemetry(tp)
    telemetry.last_tp = tp
    telemetry.cumulative_gain = 0
    telemetry.samples = {}
end

local function reset_runtime(reason)
    reserve_latched = false
    reserve_reason = nil
    aftermath_expires_at = nil
    aftermath_timer_unknown = false
    last_aftermath_active = nil
    last_decision = reason or 'Reset'
    local player = get_player()
    reset_telemetry(player and player.vitals and player.vitals.tp or nil)
end

local function load_current_profile(force)
    local player = get_player()
    if not player then
        return false
    end

    local weapon = get_main_weapon_name()
    local key = profile_key(player, weapon)
    if not force and key == current_profile_key then
        return true
    end

    settings.profiles[key] = settings.profiles[key] or {}
    current_profile = fill_missing(settings.profiles[key], weapon)
    current_profile_key = key
    current_weapon = weapon
    save_settings()
    reset_runtime('Profile changed')
    chat(207, ('Profile: %s / %s / %s'):format(
        player.name, player.main_job, weapon))
    return true
end

local function target_aftermath_id()
    local kind = current_profile and
        tostring(current_profile.aftermath_type or 'lv3'):lower() or 'lv3'
    return AFTERMATH_IDS[kind] or AFTERMATH_IDS.lv3
end

local function has_buff(player, buff_id)
    if not player or not player.buffs then
        return false
    end
    for _, id in pairs(player.buffs) do
        if id == buff_id then
            return true
        end
    end
    return false
end

local function target_is_valid(mob)
    if not mob or not mob.hpp then
        return false
    end
    if mob.is_npc == false then
        return false
    end
    local minimum = tonumber(current_profile.hp_min) or 5
    local maximum = tonumber(current_profile.hp_max) or 100
    return mob.hpp > minimum and mob.hpp < maximum
end

local function update_telemetry(now, tp, engaged)
    if not engaged then
        reset_telemetry(tp)
        return
    end

    if telemetry.last_tp == nil then
        telemetry.last_tp = tp
    elseif tp > telemetry.last_tp then
        local delta = tp - telemetry.last_tp
        -- Ignore implausibly large one-tick jumps. This keeps temporary
        -- debug/admin effects from teaching the predictor a dangerous rate.
        if delta <= 750 then
            telemetry.cumulative_gain = telemetry.cumulative_gain + delta
        end
    end
    telemetry.last_tp = tp

    table.insert(telemetry.samples, {
        time = now,
        gain = telemetry.cumulative_gain,
    })

    local window = tonumber(current_profile.rate_window) or 12
    while #telemetry.samples > 2 and
        telemetry.samples[2].time < now - window do
        table.remove(telemetry.samples, 1)
    end
end

local function tp_rate(now)
    if #telemetry.samples < 2 then
        return nil, 0
    end

    local first = telemetry.samples[1]
    local last = telemetry.samples[#telemetry.samples]
    local span = last.time - first.time
    local minimum_span = tonumber(current_profile.minimum_rate_span) or 4
    if span < minimum_span then
        return nil, span
    end

    local gained = last.gain - first.gain
    if gained <= 0 then
        return nil, span
    end
    return gained / span, span
end

local function reserve_window(now)
    local rate = tp_rate(now)
    local fallback = tonumber(current_profile.fallback_reserve) or 20
    if not rate or rate <= 0 then
        return fallback, nil
    end

    local safety = tonumber(current_profile.safety_margin) or 4
    local minimum = tonumber(current_profile.minimum_reserve) or 12
    local maximum = tonumber(current_profile.maximum_reserve) or 35
    local predicted = (3000 / rate) + safety
    return clamp(predicted, minimum, maximum), rate
end

local function remaining_aftermath(now)
    if aftermath_timer_unknown or not aftermath_expires_at then
        return nil
    end
    return math.max(0, aftermath_expires_at - now)
end

local function enter_reserve(reason)
    if reserve_latched then
        return
    end
    reserve_latched = true
    reserve_reason = reason or 'Aftermath reserve'
    chat(158, 'Reserve latched: no WS until exactly 3000 TP, then hold for AM loss.')
end

local function observe_aftermath(now, active)
    if last_aftermath_active == nil then
        last_aftermath_active = active
        if active then
            aftermath_timer_unknown = true
            aftermath_expires_at = nil
            last_decision = 'AM active; remaining time unknown'
        elseif current_profile.aftermath_enabled and
            current_profile.aftermath_mode == 'active' then
            enter_reserve('Aftermath absent at startup')
        end
        return
    end

    if active and not last_aftermath_active then
        aftermath_expires_at = now +
            (tonumber(current_profile.aftermath_duration) or 180)
        aftermath_timer_unknown = false
        reserve_latched = false
        reserve_reason = nil
        last_decision = 'Aftermath confirmed'
        chat(158, ('Aftermath confirmed; timer started at %ds.'):format(
            tonumber(current_profile.aftermath_duration) or 180))
    elseif not active and last_aftermath_active then
        aftermath_expires_at = nil
        aftermath_timer_unknown = false
        if current_profile.aftermath_enabled and
            current_profile.aftermath_mode == 'active' then
            enter_reserve('Aftermath expired')
        end
        last_decision = 'Aftermath expired'
    end
    last_aftermath_active = active
end

local function send_ws(name, reason)
    name = trim(name)
    if name == '' then
        last_decision = 'WS not configured'
        return false
    end

    local now = os.clock()
    if now - last_command_at < 2.8 then
        return false
    end

    windower.send_command(('input /ws "%s" <t>'):format(
        name:gsub('"', '')))
    last_command_at = now
    last_decision = reason .. ': ' .. name
    return true
end

local function format_time(seconds)
    if seconds == nil then
        return 'unknown'
    end
    seconds = math.max(0, math.floor(seconds + 0.5))
    return ('%d:%02d'):format(math.floor(seconds / 60), seconds % 60)
end

local function update_display(now, player, active, rate, reserve_seconds)
    if not settings.display.visible then
        display:hide()
        return
    end

    local tp = player and player.vitals and player.vitals.tp or 0
    local mode = current_profile and current_profile.aftermath_mode or 'shadow'
    local remaining = remaining_aftermath(now)
    local phase = 'NORMAL'

    if not enabled then
        phase = 'OFF'
    elseif current_profile and current_profile.aftermath_enabled then
        if mode == 'shadow' then
            if not active then
                phase = tp == 3000 and 'WOULD REAPPLY' or 'WOULD RESERVE'
            elseif remaining and remaining <= reserve_seconds then
                phase = 'WOULD RESERVE'
            else
                phase = 'SHADOW'
            end
        elseif reserve_latched then
            if tp == 3000 and active then
                phase = 'ARMED / HOLD'
            elseif tp == 3000 then
                phase = 'REAPPLY'
            else
                phase = 'RESERVE'
            end
        elseif active then
            phase = 'NORMAL'
        else
            phase = 'RESERVE'
        end
    end

    local rate_text = rate and ('%.1f TP/s'):format(rate) or 'learning'
    local am_text = active and
        ('AM %s'):format(format_time(remaining)) or 'AM DOWN'
    local value = table.concat({
        ('AutoWS2 %s | %s | %s'):format(
            bool_word(enabled), string.upper(mode), phase),
        ('%s | TP %d/3000 | %s'):format(am_text, tp, rate_text),
        ('Reserve %.1fs | %s'):format(reserve_seconds, last_decision),
        ('%s | Normal: %s | AM: %s'):format(
            current_weapon or 'Unknown',
            trim(current_profile and current_profile.normal_ws) ~= '' and
                current_profile.normal_ws or '(unset)',
            trim(current_profile and current_profile.aftermath_ws) ~= '' and
                current_profile.aftermath_ws or '(unset)'),
    }, '\n')

    display:text(value)
    display:show()
end

local function print_status()
    if not load_current_profile(false) then
        chat(123, 'No logged-in player detected.')
        return
    end

    chat(207, ('%s | weapon=%s | normal="%s" @ %d TP'):format(
        bool_word(enabled),
        current_weapon,
        trim(current_profile.normal_ws),
        tonumber(current_profile.normal_tp) or 1000))
    chat(207, ('aftermath=%s | mode=%s | type=%s | ws="%s" | duration=%ds'):format(
        bool_word(current_profile.aftermath_enabled),
        current_profile.aftermath_mode,
        current_profile.aftermath_type,
        trim(current_profile.aftermath_ws),
        tonumber(current_profile.aftermath_duration) or 180))
    chat(207, ('reserve fallback=%ss min=%ss max=%ss safety=%ss | latched=%s'):format(
        tostring(current_profile.fallback_reserve),
        tostring(current_profile.minimum_reserve),
        tostring(current_profile.maximum_reserve),
        tostring(current_profile.safety_margin),
        bool_word(reserve_latched)))
end

local function set_number(field, value, low, high)
    local number = tonumber(value)
    if not number or number < low or number > high then
        chat(123, ('Expected a number from %s to %s.'):format(low, high))
        return false
    end
    current_profile[field] = number
    save_settings()
    return true
end

local function print_help()
    chat(207, 'Commands:')
    chat(207, '  //aws2 on|off|toggle|status')
    chat(207, '  //aws2 use <normal WS> | //aws2 tp <1000-3000>')
    chat(207, '  //aws2 hp <min> <max>')
    chat(207, '  //aws2 aftermath on|off')
    chat(207, '  //aws2 aftermath mode shadow|active')
    chat(207, '  //aws2 aftermath ws <WS> | duration <seconds>')
    chat(207, '  //aws2 aftermath reserve fallback|min|max|safety <seconds>')
    chat(207, '  //aws2 reserve reset (manually releases the hard latch)')
    chat(207, '  //aws2 display on|off|pos <x> <y>')
end

local function handle_aftermath_command(args)
    local sub = tostring(args[1] or ''):lower()
    if sub == 'on' or sub == 'off' then
        current_profile.aftermath_enabled = sub == 'on'
        if not current_profile.aftermath_enabled then
            reserve_latched = false
            reserve_reason = nil
        end
        save_settings()
        print_status()
    elseif sub == 'mode' then
        local mode = tostring(args[2] or ''):lower()
        if mode ~= 'shadow' and mode ~= 'active' then
            chat(123, 'Mode must be shadow or active.')
            return
        end
        current_profile.aftermath_mode = mode
        reserve_latched = false
        reserve_reason = nil
        last_aftermath_active = nil
        save_settings()
        print_status()
    elseif sub == 'ws' then
        current_profile.aftermath_ws = trim(table.concat(args, ' ', 2))
        save_settings()
        print_status()
    elseif sub == 'duration' then
        if set_number('aftermath_duration', args[2], 10, 1800) then
            aftermath_expires_at = nil
            aftermath_timer_unknown = last_aftermath_active == true
            print_status()
        end
    elseif sub == 'type' then
        local kind = tostring(args[2] or ''):lower()
        if not AFTERMATH_IDS[kind] then
            chat(123, 'Type must be lv1, lv2, lv3, or relic.')
            return
        end
        current_profile.aftermath_type = kind
        reset_runtime('Aftermath type changed')
        save_settings()
        print_status()
    elseif sub == 'reserve' then
        local field_map = {
            fallback = 'fallback_reserve',
            min = 'minimum_reserve',
            max = 'maximum_reserve',
            safety = 'safety_margin',
        }
        local field = field_map[tostring(args[2] or ''):lower()]
        if not field then
            chat(123, 'Reserve field must be fallback, min, max, or safety.')
            return
        end
        if set_number(field, args[3], 0, 120) then
            print_status()
        end
    else
        chat(123, 'Unknown aftermath command. Use //aws2 help.')
    end
end

windower.register_event('addon command', function(command, ...)
    if not load_current_profile(false) then
        chat(123, 'No logged-in player detected.')
        return
    end

    command = tostring(command or 'help'):lower()
    local args = {...}

    if command == 'on' or command == 'enable' or command == 'start' then
        enabled = true
        print_status()
    elseif command == 'off' or command == 'disable' or command == 'stop' then
        enabled = false
        reserve_latched = false
        reserve_reason = nil
        print_status()
    elseif command == 'toggle' then
        enabled = not enabled
        if not enabled then
            reserve_latched = false
            reserve_reason = nil
        end
        print_status()
    elseif command == 'status' then
        print_status()
    elseif command == 'use' or command == 'ws' or command == 'set' then
        current_profile.normal_ws = trim(table.concat(args, ' '))
        save_settings()
        print_status()
    elseif command == 'tp' then
        if set_number('normal_tp', args[1], 1000, 3000) then
            print_status()
        end
    elseif command == 'hp' then
        local minimum = tonumber(args[1])
        local maximum = tonumber(args[2])
        if not minimum or not maximum or minimum < 0 or maximum > 100 or
            minimum >= maximum then
            chat(123, 'Usage: //aws2 hp <minimum 0-99> <maximum 1-100>')
            return
        end
        current_profile.hp_min = minimum
        current_profile.hp_max = maximum
        save_settings()
        print_status()
    elseif command == 'aftermath' or command == 'am' then
        handle_aftermath_command(args)
    elseif command == 'reserve' and tostring(args[1] or ''):lower() == 'reset' then
        reserve_latched = false
        reserve_reason = nil
        last_decision = 'Reserve manually reset'
        chat(158, 'Reserve latch manually released.')
    elseif command == 'display' then
        local sub = tostring(args[1] or ''):lower()
        if sub == 'on' or sub == 'off' then
            settings.display.visible = sub == 'on'
            save_settings()
        elseif sub == 'pos' then
            local x, y = tonumber(args[2]), tonumber(args[3])
            if not x or not y then
                chat(123, 'Usage: //aws2 display pos <x> <y>')
                return
            end
            display:pos(x, y)
            settings.display.pos.x = x
            settings.display.pos.y = y
            save_settings()
        else
            chat(123, 'Usage: //aws2 display on|off|pos <x> <y>')
        end
    elseif command == 'reload' or command == 'unload' then
        windower.send_command(('lua %s AutoWS2'):format(command))
    elseif command == 'help' or command == '--help' then
        print_help()
    else
        chat(123, 'Unknown command. Use //aws2 help.')
    end
end)

windower.register_event('gain buff', function(buff_id)
    if not current_profile or buff_id ~= target_aftermath_id() then
        return
    end
    local now = os.clock()
    aftermath_expires_at = now +
        (tonumber(current_profile.aftermath_duration) or 180)
    aftermath_timer_unknown = false
    last_aftermath_active = true
    reserve_latched = false
    reserve_reason = nil
    last_decision = 'Aftermath gained'
end)

windower.register_event('lose buff', function(buff_id)
    if not current_profile or buff_id ~= target_aftermath_id() then
        return
    end
    aftermath_expires_at = nil
    aftermath_timer_unknown = false
    last_aftermath_active = false
    if current_profile.aftermath_enabled and
        current_profile.aftermath_mode == 'active' then
        enter_reserve('Aftermath lost')
    end
    last_decision = 'Aftermath lost'
end)

windower.register_event('job change', function()
    enabled = false
    current_profile_key = nil
    current_profile = nil
    reset_runtime('Job changed')
end)

windower.register_event('zone change', function()
    pause_until = os.clock() + 15
    reset_runtime('Zone changed')
end)

windower.register_event('logout', function()
    enabled = false
    reset_runtime('Logout')
end)

windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_check_at < 0.20 then
        return
    end
    last_check_at = now

    if not load_current_profile(false) then
        display:hide()
        return
    end

    local player = get_player()
    if not player or not player.vitals then
        display:hide()
        return
    end

    local mob = windower.ffxi.get_mob_by_target('t')
    local engaged = player.status == 1 and mob ~= nil
    local tp = tonumber(player.vitals.tp) or 0
    update_telemetry(now, tp, engaged)

    local aftermath_active = has_buff(player, target_aftermath_id())
    observe_aftermath(now, aftermath_active)
    local reserve_seconds, rate = reserve_window(now)
    local remaining = remaining_aftermath(now)

    if enabled and current_profile.aftermath_enabled and
        current_profile.aftermath_mode == 'active' and not reserve_latched then
        if not aftermath_active then
            enter_reserve('Aftermath absent')
        elseif remaining and remaining <= reserve_seconds then
            enter_reserve(('Predicted reserve window %.1fs'):format(
                reserve_seconds))
        end
    end

    update_display(now, player, aftermath_active, rate, reserve_seconds)

    if not enabled or now < pause_until or not engaged or
        not target_is_valid(mob) then
        return
    end

    if current_profile.aftermath_enabled and
        current_profile.aftermath_mode == 'active' and reserve_latched then
        -- Hard safety invariant:
        --   * no WS of any kind below 3000 after reserve is latched;
        --   * at 3000, hold while the configured aftermath remains active;
        --   * only the configured aftermath WS may fire after confirmed loss.
        if tp ~= 3000 then
            last_decision = ('Hard reserve: %d/3000'):format(tp)
            return
        end
        if aftermath_active then
            last_decision = 'Armed at 3000; holding for AM loss'
            return
        end
        send_ws(current_profile.aftermath_ws, 'Reapply aftermath')
        return
    end

    if tp >= (tonumber(current_profile.normal_tp) or 1000) then
        send_ws(current_profile.normal_ws, 'Normal WS')
    end
end)

windower.register_event('load', function()
    load_current_profile(true)
    display:show()
    chat(207, 'Loaded in OFF state. Tizona profiles default to aftermath shadow mode.')
    chat(207, 'Use //aws2 help. Do not run another AutoWS controller simultaneously.')
end)
