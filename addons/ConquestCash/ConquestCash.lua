-- SPDX-License-Identifier: MIT AND BSD-3-Clause
--[[
The menu-release sequence uses EventGuard/Superwarp's recovery sequence.
The upstream notice retained by EventGuard also applies to that portion:

Copyright © 2019, Akaden of Asura
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of superwarp nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Superwarp: https://github.com/AkadenTK/superwarp
Its source credits Ivaar for the menu-locked-state reset functions.
ConquestCash-specific code retains the MIT terms in LICENSE.
]]
-- Converts San d'Oria conquest points into gil through a guarded, observable
-- purchase/move/sale loop. Transactions are serialized on server responses.

_addon = _addon or {}
_addon.name = 'ConquestCash'
_addon.author = 'DC03 / OpenAI Codex'
_addon.version = '0.2.4-candidate'
_addon.commands = {'conquestcash', 'ccash'}

local config = require('config')
local packets = require('packets')
local Model = assert(loadfile(windower.addon_path .. 'lib/model.lua'))()
local Hud = assert(loadfile(windower.addon_path .. 'lib/hud.lua'))()

local defaults = {
    ConquestFloor = 0,
    InteractionDistance = 4.4,
    RouteTolerance = 14.0,
    MovementTick = 0.10,
    SettleDelay = 0.35,
    MenuStepDelay = 0.18,
    PurchaseDelay = 1.00,
    GuardMenuResponseTimeout = 2.50,
    GuardMenuRetryDelay = 0.75,
    GuardMenuAttempts = 3,
    GuardStallDrainDelay = 5.00,
    GuardStallReleaseDelay = 1.00,
    PurchaseReleaseNoticeInterval = 30.00,
    VendorSettleDelay = 1.00,
    VendorMenuResponseTimeout = 2.50,
    VendorMenuRetryDelay = 0.75,
    VendorMenuAttempts = 3,
    SaleDelay = 0.20,
    TransactionTimeout = 8.0,
    CurrencyTimeout = 8.0,
    StuckTimeout = 7.0,
    MaxSalesPerSession = 40,
    MinimumVendorPrice = 4000,
    EstimatedVendorPrice = 5000,
    Verbose = true,
    Hud = {
        visible = true,
        pos = {x = 30, y = 350},
        scale = 1.0,
        opacity = 235,
    },
}

-- Each client writes a different file. Windower's normal character sections
-- live in one settings.xml, which makes six simultaneous config.save calls a
-- last-writer-wins race across processes.
local config_player = windower.ffxi.get_player()
local config_character = config_player and config_player.name
    and config_player.name:gsub('[^%w_-]', '_'):lower() or 'not_logged_in'
local settings_path = ('data/settings_%s.xml'):format(config_character)
local settings = config.load(settings_path, defaults)
settings.Hud = type(settings.Hud) == 'table' and settings.Hud or {}
settings.Hud.pos = type(settings.Hud.pos) == 'table' and settings.Hud.pos
    or {x = defaults.Hud.pos.x, y = defaults.Hud.pos.y}
local hud = Hud.new({
    settings = settings.Hud,
    asset_path = windower.addon_path .. 'assets\\',
})

-- Retail identifiers and positions for the compact Northern San d'Oria route.
-- Windower exposes the horizontal map plane as mob.x/mob.y; LandSandBoat's
-- entity data represents the second horizontal axis as its third coordinate.
local PROFILE = {
    zone = 231, -- Northern San d'Oria
    nation = 0, -- San d'Oria
    item = {
        id = 16844,
        name = "Royal Squire's halberd",
        cp = 4000,
        option = 32800,
    },
    guard = {
        id = 17723471,
        name = 'Achantere, T.K.',
        x = -247.201,
        y = 40.939,
        menu_id = 32762,
    },
    vendor = {
        id = 17723486,
        name = 'Pirvidiauce',
        x = -218.375,
        y = 60.595,
    },
}

local GIL_CAP = 999999999
local IPC_PREFIX = 'conquestcash:v1:'
local MINIMUM_PURCHASE_DELAY = 1.00

local state = {
    active = false,
    phase = 'idle',
    phase_started = 0,
    ready_at = 0,
    deadline = nil,
    last_tick = 0,
    running = false,
    last_run_x = nil,
    last_run_y = nil,
    move_target = nil,
    move_best = nil,
    move_progress_at = nil,
    cp = nil,
    planned = 0,
    cycle_purchased = 0,
    purchased = 0,
    sold = 0,
    projected_gil = nil,
    vendor_price = nil,
    vendor_session_sales = 0,
    vendor_menu_attempts = 0,
    run_started_at = nil,
    gil_earned = 0,
    eta_seconds_per_item = nil,
    eta_cycle_started_at = nil,
    acquired = {},
    acquired_order = {},
    pending_purchase = nil,
    current_sale = nil,
    menu = nil,
    menu_final_sent = false,
    local_release_attempted = false,
    preview_pending = false,
    capture = false,
    capture_path = nil,
    error_reason = nil,
    last_summary = nil,
    failing = false,
}

local HUD_COLORS = {
    cp = {255, 211, 82},
    gil = {255, 211, 82},
    eta = {255, 211, 82},
    unknown = {133, 148, 163},
}
local HUD_RENDER_INTERVAL = 0.20
local hud_last_render_at = 0
local hud_placement_dirty = false

local fail

local function now()
    return os.clock()
end

local function chat(message, color)
    windower.add_to_chat(color or 207, '[ConquestCash] ' .. tostring(message))
end

local function verbose(message)
    if settings.Verbose then chat(message) end
end

local function comma(value)
    local sign, digits = '', tostring(math.floor(tonumber(value) or 0))
    if digits:sub(1, 1) == '-' then
        sign, digits = '-', digits:sub(2)
    end
    local result = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if result:sub(1, 1) == ',' then result = result:sub(2) end
    return sign .. result
end

local function player()
    return windower.ffxi.get_player()
end

local function info()
    return windower.ffxi.get_info() or {}
end

local function self_mob()
    return windower.ffxi.get_mob_by_target('me')
end

local function all_items()
    return windower.ffxi.get_items() or {}
end

local function current_gil()
    local value = tonumber(all_items().gil)
    if value and value >= 0 then return math.floor(value) end
    return nil
end

local function acquired_count()
    return Model.table_count(state.acquired)
end

local function format_duration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 or seconds == math.huge then return '--' end
    local total_minutes = math.floor(seconds / 60 + 0.5)
    local hours = math.floor(total_minutes / 60)
    local minutes = total_minutes % 60
    if hours > 0 then
        return ('%dh%02dm'):format(hours, minutes)
    end
    return ('%dm'):format(minutes)
end

-- Count unfinished conversion units, not merely unspent CP. Purchased but
-- unsold halberds remain in the estimate until their vendor response and
-- inventory removal have both been observed.
local function remaining_work_items()
    local cp = Model.nonnegative_integer(state.cp)
    if cp == nil then return nil end
    local floor = Model.nonnegative_integer(settings.ConquestFloor) or 0
    local purchasable = math.max(0,
        math.floor((cp - floor) / PROFILE.item.cp))
    return purchasable + acquired_count()
end

local function hud_entries()
    if hud:is_placement() then
        return {
            {text = '13M', color = HUD_COLORS.cp},
            {text = '+209K', color = HUD_COLORS.gil},
            {text = '2h31m', color = HUD_COLORS.eta},
        }, true
    end

    local cp_text = state.cp and Model.compact_amount(state.cp) or '--'
    local gil_text = state.run_started_at
        and ('+' .. Model.compact_amount(state.gil_earned)) or '--'
    local eta_text, eta_color = '--', HUD_COLORS.unknown
    local remaining = remaining_work_items()

    if state.run_started_at then
        eta_color = HUD_COLORS.eta
        if state.phase == 'complete' then
            if remaining ~= nil and remaining <= 0 then
                eta_text, eta_color = 'DONE', HUD_COLORS.eta
            else
                eta_text = 'STOPPED'
            end
        elseif not state.active then
            eta_text = 'PAUSED'
        elseif remaining == nil or not state.eta_seconds_per_item then
            eta_text = 'CALC...'
        elseif remaining <= 0 then
            eta_text, eta_color = '00:00', HUD_COLORS.eta
        else
            eta_text = format_duration(remaining * state.eta_seconds_per_item)
            eta_color = HUD_COLORS.eta
        end
    end

    local visible = settings.Hud.visible == true
        and state.run_started_at ~= nil
    return {
        {text = cp_text, color = state.cp and HUD_COLORS.cp
            or HUD_COLORS.unknown},
        {text = gil_text, color = state.run_started_at and HUD_COLORS.gil
            or HUD_COLORS.unknown},
        {text = eta_text, color = eta_color},
    }, visible
end

local function render_hud(force)
    local timestamp = now()
    if not force and timestamp - hud_last_render_at < HUD_RENDER_INTERVAL then
        return
    end
    hud_last_render_at = timestamp
    local entries, visible = hud_entries()
    hud:render(entries, visible, force)
end

local function hud_prerender()
    local moved = hud:capture_dragged_position()
    if moved then hud_placement_dirty = true end
    render_hud(moved)
end

local function update_eta_cycle_sample()
    local count = tonumber(state.cycle_purchased) or 0
    local started = tonumber(state.eta_cycle_started_at)
    if count > 0 and started then
        local elapsed = now() - started
        if elapsed > 0 then
            local sample = elapsed / count
            if state.eta_seconds_per_item then
                -- A light moving average adapts to congestion without making
                -- the display jump sharply after one unusual cycle.
                state.eta_seconds_per_item = state.eta_seconds_per_item * 0.65
                    + sample * 0.35
            else
                state.eta_seconds_per_item = sample
            end
        end
    end
    state.eta_cycle_started_at = now()
end

local function stop_running()
    if state.running then
        windower.ffxi.run(false)
    end
    state.running = false
    state.last_run_x = nil
    state.last_run_y = nil
end

local function run_direction(x, y)
    if not state.running or not state.last_run_x
            or math.abs(x - state.last_run_x) > 0.02
            or math.abs(y - state.last_run_y) > 0.02 then
        windower.ffxi.run(x, y)
        state.last_run_x = x
        state.last_run_y = y
    end
    state.running = true
end

local function set_phase(phase, delay, timeout)
    local timestamp = now()
    state.phase = phase
    state.phase_started = timestamp
    state.ready_at = timestamp + (tonumber(delay) or 0)
    state.deadline = timeout and (timestamp + timeout) or nil
end

local function parse_packet(direction, raw)
    if type(raw) == 'table' then return raw end -- isolated test harness
    if type(raw) ~= 'string' then return nil end
    local ok, parsed = pcall(packets.parse, direction, raw)
    return ok and parsed or nil
end

local function inject(packet, purpose)
    local ok, err = pcall(packets.inject, packet)
    if not ok then
        if fail then fail(('Could not %s: %s'):format(purpose, tostring(err))) end
        return false
    end
    return true
end

local function npc_for(kind)
    local expected = PROFILE[kind]
    if not expected then return nil end
    local mob = windower.ffxi.get_mob_by_id(expected.id)
    if mob and mob.name == expected.name and tonumber(mob.id) == expected.id then
        return mob
    end

    for _, candidate in pairs(windower.ffxi.get_mob_array() or {}) do
        if candidate and candidate.name == expected.name
                and tonumber(candidate.id) == expected.id then
            return candidate
        end
    end
    return nil
end

local function expected_position(kind)
    local mob = npc_for(kind)
    if mob and tonumber(mob.x) and tonumber(mob.y) then
        return {x = tonumber(mob.x), y = tonumber(mob.y)}
    end
    local expected = PROFILE[kind]
    return {x = expected.x, y = expected.y}
end

local function target_distance(kind)
    local me = self_mob()
    local target = npc_for(kind)
    if not me or not target then return nil end
    return Model.distance(me, target)
end

local function inventory_slots()
    return Model.item_slots(all_items(), PROFILE.item.id)
end

local function inventory_item(index)
    local items = all_items()
    return items.inventory and items.inventory[tonumber(index)] or nil
end

local function untracked_item_slots()
    local result = {}
    for index in pairs(inventory_slots()) do
        if not state.acquired[index] then result[index] = true end
    end
    return result
end

local function queue_acquired_slot(index)
    index = tonumber(index)
    if not index or state.acquired[index] then return end
    state.acquired[index] = true
    state.acquired_order[#state.acquired_order + 1] = index
end

local function remove_acquired_slot(index)
    index = tonumber(index)
    state.acquired[index] = nil
    for position, value in ipairs(state.acquired_order) do
        if value == index then
            table.remove(state.acquired_order, position)
            return
        end
    end
end

local function next_acquired_slot()
    while #state.acquired_order > 0 do
        local index = state.acquired_order[1]
        if state.acquired[index] then return index end
        table.remove(state.acquired_order, 1)
    end
    return nil
end

local function send_interaction(target, purpose)
    if not target then return false end
    return inject(packets.new('outgoing', 0x01A, {
        ['Target'] = target.id,
        ['Target Index'] = target.index,
        ['Category'] = 0,
        ['Param'] = 0,
        ['_unknown1'] = 0,
    }), purpose or 'interact with NPC')
end

local function send_dialog(option, automated, unknown1, purpose)
    local menu = state.menu
    if not menu then
        fail('No verified conquest menu is open.')
        return false
    end
    return inject(packets.new('outgoing', 0x05B, {
        ['Target'] = menu.npc,
        ['Option Index'] = option,
        ['_unknown1'] = unknown1 or 0,
        ['Target Index'] = menu.npc_index,
        ['Automated Message'] = automated,
        ['_unknown2'] = 0,
        ['Zone'] = menu.zone,
        ['Menu ID'] = menu.menu_id,
    }), purpose or 'advance conquest menu')
end

local function cancel_open_menu()
    if not state.menu or state.menu_final_sent then return true end
    if not send_dialog(0, false, 16384, 'cancel conquest menu') then
        return false
    end
    state.menu = nil
    return true
end

-- Apply the standard local menu-release sequence used by EventGuard and
-- Superwarp. These are client-side incoming injections only: they cannot buy
-- another item or submit any choice to the server. This is attempted once per
-- completed-purchase stall; if it does not repair the local Event flag, the
-- addon remains in the safe wait instead of repeating the sequence.
local function apply_local_event_release()
    if state.local_release_attempted then return false end
    state.local_release_attempted = true

    local api = windower and windower.packets
    if not api or type(api.inject_incoming) ~= 'function' then
        verbose('Local Event-release API is unavailable; continuing the safe wait.')
        return false
    end

    local ok, err = pcall(function()
        api.inject_incoming(0x052, string.char(0, 0, 0, 0, 0, 0, 0, 0))
        api.inject_incoming(0x052, string.char(0, 0, 0, 0, 1, 0, 0, 0))
    end)
    if not ok then
        verbose('Local Event-release attempt failed safely: ' .. tostring(err))
        return false
    end
    verbose('Applied one local Event-release sequence; waiting for Idle confirmation.')
    return true
end

local function transaction_phase()
    return state.phase:sub(1, 4) == 'buy_'
        or state.phase:sub(1, 7) == 'vendor_'
        or state.phase:sub(1, 5) == 'sale_'
end

fail = function(reason)
    if state.failing then return end
    state.failing = true
    stop_running()
    state.active = false
    state.phase = 'error'
    cancel_open_menu()
    state.error_reason = tostring(reason)
    state.deadline = nil
    chat('STOPPED: ' .. state.error_reason, 123)
    if acquired_count() > 0 then
        chat(('Holding %d run-owned halberd(s); do not sort or move them. '
            .. 'Fix the issue and use //ccash start confirm to resume.'):format(
            acquired_count()), 123)
    end
    if state.pending_purchase and state.menu_final_sent
            and not state.pending_purchase.item_received then
        chat('The last purchase outcome is uncertain. Wait for its inventory '
            .. 'update before restarting.', 123)
    end
    if state.current_sale and state.current_sale.final_sent
            and not state.current_sale.sale_response then
        chat('The last vendor sale outcome is uncertain. Wait for its response '
            .. 'before restarting.', 123)
    end
    state.failing = false
end

local function complete(reason)
    stop_running()
    state.active = false
    state.phase = 'complete'
    state.deadline = nil
    state.last_summary = reason
    chat(('%s Bought %d, sold %d; CP=%s, floor=%s%s.'):format(
        reason,
        state.purchased,
        state.sold,
        state.cp and comma(state.cp) or 'unknown',
        comma(settings.ConquestFloor),
        state.vendor_price and (', vendor=' .. comma(state.vendor_price) .. ' gil') or ''))
end

local function begin_move(kind)
    local target = npc_for(kind)
    local me = self_mob()
    if not target then
        fail(('Expected NPC %s (ID %d) is not loaded.'):format(
            PROFILE[kind].name, PROFILE[kind].id))
        return
    end
    if not me then
        fail('Local player entity is unavailable.')
        return
    end

    local distance = Model.distance(me, target)
    if not distance then
        fail('Could not calculate route distance.')
        return
    end
    state.move_target = kind
    state.move_best = distance
    state.move_progress_at = now()
    set_phase('move_' .. kind, 0, math.max(20, distance * 1.5 + 10))
    verbose(('Moving to %s (%.1f yalms).'):format(PROFILE[kind].name, distance))
end

local function request_currency()
    if not inject(packets.new('outgoing', 0x10F, {}),
            'request conquest-point balance') then
        return
    end
    set_phase('wait_currency', 0, tonumber(settings.CurrencyTimeout) or 8)
end

local function preflight_route()
    local current = self_mob()
    if not current then return false, 'Local player entity is unavailable.' end
    local distance = Model.point_segment_distance(
        current, expected_position('guard'), expected_position('vendor'))
    if not distance then return false, 'Could not validate the route corridor.' end
    local tolerance = tonumber(settings.RouteTolerance) or 14
    if distance > tolerance then
        return false, ('Start within %.1f yalms of the Achantere-Pirvidiauce '
            .. 'route corridor (currently %.1f).'):format(tolerance, distance)
    end
    return true
end

-- Windower can occasionally retain status 4 (Event) after the server has
-- completed and released a conquest purchase. A stopped run may re-enter the
-- automatic recovery wait only when its completed inventory is already owned
-- by this addon and there is no transaction whose outcome is uncertain.
local function can_resume_into_release_wait(current_player)
    if not current_player or tonumber(current_player.status) ~= 4
            or acquired_count() < 1
            or state.pending_purchase
            or state.current_sale
            or state.menu
            or state.menu_final_sent then
        return false
    end

    for index in pairs(state.acquired) do
        local item = inventory_item(index)
        if not item or tonumber(item.id) ~= PROFILE.item.id
                or (tonumber(item.count) or 0) ~= 1
                or tonumber(item.status) ~= 0 then
            return false
        end
    end
    return true
end

local function preflight()
    local current_player = player()
    local current_info = info()
    if not current_player or current_info.logged_in == false then
        return false, 'No logged-in player is available.'
    end
    if tonumber(current_info.zone) ~= PROFILE.zone then
        return false, 'This route only runs in Northern San d\'Oria (zone 231).'
    end
    if tonumber(current_player.nation) ~= PROFILE.nation then
        return false, 'The current character is not pledged to San d\'Oria.'
    end
    local release_wait = false
    local status = tonumber(current_player.status)
    if status ~= 0 then
        release_wait = can_resume_into_release_wait(current_player)
        if not release_wait then
            return false, ('The character must be idle (not fighting, resting, '
                .. 'or in a menu); Windower reports status %s.'):format(
                tostring(status))
        end
    end
    if not npc_for('guard') or not npc_for('vendor') then
        return false, 'Achantere or Pirvidiauce is not present with the expected retail ID.'
    end
    local floor = Model.nonnegative_integer(settings.ConquestFloor)
    if not floor then return false, 'ConquestFloor is invalid.' end
    local route_ok, route_reason = preflight_route()
    if not route_ok then return false, route_reason end
    return true, nil, release_wait
end

local function guard_menu_attempt_limit()
    return math.max(1, math.floor(tonumber(settings.GuardMenuAttempts) or 3))
end

local function vendor_menu_attempt_limit()
    return math.max(1, math.floor(tonumber(settings.VendorMenuAttempts) or 3))
end

local function finish_partial_batch_recovery(reason)
    local count = acquired_count()
    if count < 1 or state.current_sale or state.menu or state.menu_final_sent then
        fail('Partial-batch guard recovery state is inconsistent.')
        return false
    end
    state.pending_purchase = nil
    state.menu = nil
    state.menu_final_sent = false
    state.planned = math.max(count, tonumber(state.cycle_purchased) or 0)
    local delay = math.max(0.5,
        tonumber(settings.GuardStallReleaseDelay) or 1.0)
    chat(('RECOVERY: %s Vending the partial batch of %d halberd(s), then '
        .. 'returning to Achantere.'):format(
        reason or 'Safe transaction boundary reached.', count))
    set_phase('buy_batch_settle', delay,
        delay + (tonumber(settings.TransactionTimeout) or 8))
    return true
end

local function request_guard_menu()
    local pending = state.pending_purchase
    if not pending or state.menu or state.menu_final_sent then
        fail('Guard-menu retry state is inconsistent.')
        return false
    end

    local current_player = player()
    if not current_player or tonumber(current_player.status) ~= 0 then
        fail('Achantere did not return a menu while the client is in Event '
            .. 'status; refusing an ambiguous interaction retry.')
        return false
    end

    local target = npc_for('guard')
    local distance = target_distance('guard')
    if not target or not distance or distance > settings.InteractionDistance then
        fail('Achantere moved or is outside interaction range.')
        return false
    end

    pending.menu_attempts = (tonumber(pending.menu_attempts) or 0) + 1
    if not send_interaction(target, 'open Achantere conquest menu') then
        return false
    end
    set_phase('buy_wait_menu', 0,
        math.max(1, tonumber(settings.GuardMenuResponseTimeout) or 2.5))
    return true
end

local function begin_purchase()
    if state.cycle_purchased >= state.planned then
        begin_move('vendor')
        return
    end

    if not state.cp or state.cp - PROFILE.item.cp < settings.ConquestFloor then
        if acquired_count() > 0 then begin_move('vendor')
        else complete('Conquest-point floor reached.') end
        return
    end

    local free = Model.free_inventory_slots(all_items())
    if not free or free < 1 then
        if acquired_count() > 0 then begin_move('vendor')
        else fail('Inventory has no free slot before a purchase.') end
        return
    end

    state.menu = nil
    state.menu_final_sent = false
    state.local_release_attempted = false
    state.pending_purchase = {
        before = inventory_slots(),
        cp_before = state.cp,
        item_received = false,
        release_received = false,
        slot = nil,
        final_at = nil,
        saw_event_status = false,
        menu_attempts = 0,
    }
    request_guard_menu()
end

local function plan_cycle()
    local floor = Model.nonnegative_integer(settings.ConquestFloor) or 0
    local free = Model.free_inventory_slots(all_items())
    if free == nil then
        fail('Inventory totals are unavailable or inconsistent.')
        return
    end

    local gil = current_gil() or state.projected_gil
    state.projected_gil = gil or state.projected_gil
    state.planned = Model.purchase_count({
        cp = state.cp,
        floor = floor,
        cost = PROFILE.item.cp,
        free_slots = free,
        gil = gil,
        gil_cap = GIL_CAP,
        estimated_sale = state.vendor_price or settings.EstimatedVendorPrice,
    })
    state.cycle_purchased = 0

    if state.planned < 1 then
        if state.cp and state.cp - floor < PROFILE.item.cp then
            complete('Conquest-point floor reached.')
        elseif free < 1 then
            fail('No free inventory slots are available.')
        else
            complete('Gil-cap headroom is too small for another safe cycle.')
        end
        return
    end

    verbose(('Cycle plan: %d halberd(s), %d free slots, CP %s -> at least %s.'):format(
        state.planned, free, comma(state.cp),
        comma(state.cp - state.planned * PROFILE.item.cp)))
    begin_purchase()
end

local function scan_pending_purchase()
    local pending = state.pending_purchase
    if not pending or pending.item_received then return true end
    local additions = Model.new_item_slots(pending.before, inventory_slots())
    local slots = Model.sorted_numeric_keys(additions)
    if #slots > 1 then
        fail('More than one new target item appeared during a single purchase.')
        return false
    end
    if #slots == 1 then
        pending.slot = slots[1]
        pending.item_received = true
    end
    return true
end

local function finish_purchase_if_ready()
    local pending = state.pending_purchase
    if not pending then return end
    scan_pending_purchase()
    if not pending.item_received then return end

    local current_player = player()
    local idle = current_player and tonumber(current_player.status) == 0
    local settled_without_event = not pending.saw_event_status
        and pending.final_at and now() - pending.final_at >= 0.25
    local released = pending.release_received
        or (pending.saw_event_status and idle)
        or settled_without_event
    if not released then
        return
    end

    queue_acquired_slot(pending.slot)
    state.purchased = state.purchased + 1
    state.cycle_purchased = state.cycle_purchased + 1
    -- A purchase can provoke an unsolicited 0x113 currency refresh before the
    -- inventory assignment. Clamp to the expected post-purchase value instead
    -- of blindly subtracting twice when that happens.
    local expected_cp = (tonumber(pending.cp_before) or state.cp)
        - PROFILE.item.cp
    state.cp = math.min(tonumber(state.cp) or expected_cp, expected_cp)
    state.pending_purchase = nil
    state.menu = nil
    state.menu_final_sent = false
    verbose(('Purchased %d/%d this cycle; CP estimate %s.'):format(
        state.cycle_purchased, state.planned, comma(state.cp)))

    if state.cycle_purchased >= state.planned then
        set_phase('buy_batch_settle', settings.SettleDelay,
            tonumber(settings.TransactionTimeout) or 8)
    else
        set_phase('buy_cooldown', math.max(MINIMUM_PURCHASE_DELAY,
                tonumber(settings.PurchaseDelay) or MINIMUM_PURCHASE_DELAY),
            tonumber(settings.TransactionTimeout) or 8)
    end
end

local function request_vendor_shop()
    if state.current_sale then
        fail('Vendor-shop retry state is inconsistent with an active sale.')
        return false
    end

    local current_player = player()
    if not current_player or tonumber(current_player.status) ~= 0 then
        fail('Pirvidiauce did not return a shop while the client is in Event '
            .. 'status; refusing an ambiguous interaction retry.')
        return false
    end

    local target = npc_for('vendor')
    local distance = target_distance('vendor')
    if not target or not distance or distance > settings.InteractionDistance then
        fail('Pirvidiauce moved or is outside interaction range.')
        return false
    end

    state.vendor_menu_attempts = (tonumber(state.vendor_menu_attempts) or 0) + 1
    if send_interaction(target, 'open Pirvidiauce shop') then
        set_phase('vendor_wait_shop', 0,
            math.max(1, tonumber(settings.VendorMenuResponseTimeout) or 2.5))
        return true
    end
    return false
end

local function valid_sale_item(index)
    local item = inventory_item(index)
    return item and tonumber(item.id) == PROFILE.item.id
        and (tonumber(item.count) or 0) == 1
        and tonumber(item.status) == 0
end

local function send_appraisal(index)
    return inject(packets.new('outgoing', 0x084, {
        ['Count'] = 1,
        ['Item'] = PROFILE.item.id,
        ['Inventory Index'] = index,
        ['_unknown3'] = 0,
    }), 'request vendor price')
end

local function send_sale_pair(index)
    if not send_appraisal(index) then return false end
    return inject(packets.new('outgoing', 0x085, {
        ['_unknown1'] = 1,
    }), 'confirm vendor sale')
end

local function begin_sale()
    local index = next_acquired_slot()
    if not index then
        state.current_sale = nil
        begin_move('guard')
        return
    end
    if not valid_sale_item(index) then
        fail(('Run-owned inventory slot %d no longer contains one unequipped %s.'):format(
            index, PROFILE.item.name))
        return
    end

    local live_gil = current_gil()
    if live_gil then state.projected_gil = live_gil end
    local expected = state.vendor_price or settings.EstimatedVendorPrice
    if state.projected_gil and state.projected_gil > GIL_CAP - expected then
        fail('Gil cap would be crossed by the next sale.')
        return
    end

    state.current_sale = {
        index = index,
        price = nil,
        sale_response = false,
        final_sent = false,
    }
    if not state.vendor_price then
        if send_appraisal(index) then
            set_phase('sale_wait_quote', 0,
                tonumber(settings.TransactionTimeout) or 8)
        end
    elseif send_sale_pair(index) then
        state.current_sale.price = state.vendor_price
        state.current_sale.final_sent = true
        set_phase('sale_wait_confirm', 0,
            tonumber(settings.TransactionTimeout) or 8)
    end
end

local function complete_sale_if_inventory_updated()
    local sale = state.current_sale
    if not sale or not sale.sale_response then return end
    local item = inventory_item(sale.index)
    if item and tonumber(item.id) == PROFILE.item.id
            and (tonumber(item.count) or 0) > 0 then
        return
    end

    remove_acquired_slot(sale.index)
    state.sold = state.sold + 1
    state.vendor_session_sales = state.vendor_session_sales + 1
    local realized = sale.price or state.vendor_price or 0
    state.gil_earned = (tonumber(state.gil_earned) or 0) + realized
    if state.projected_gil then
        state.projected_gil = state.projected_gil + realized
    end
    state.current_sale = nil

    if not state.active then
        state.phase = 'stopped'
        state.deadline = nil
        chat(('Reconciled the completed sale from inventory slot %d.'):format(
            sale.index), 123)
        return
    end

    if acquired_count() < 1 then
        update_eta_cycle_sample()
        verbose(('Cycle sold; total sold %d. Returning to Achantere.'):format(state.sold))
        set_phase('vendor_batch_settle', settings.SettleDelay,
            tonumber(settings.TransactionTimeout) or 8)
    elseif state.vendor_session_sales >= settings.MaxSalesPerSession then
        state.vendor_session_sales = 0
        set_phase('vendor_reopen', settings.SaleDelay,
            (tonumber(settings.SaleDelay) or 0.2) + 2)
    else
        set_phase('sale_cooldown', settings.SaleDelay,
            (tonumber(settings.SaleDelay) or 0.2) + 2)
    end
end

local function unpack_u32(parameters, offset)
    if type(parameters) == 'table' then
        return tonumber(parameters[math.floor((offset - 1) / 4) + 1])
    end
    if type(parameters) ~= 'string' or #parameters < offset + 3 then return nil end
    local ok, value = pcall(function() return parameters:unpack('I', offset) end)
    return ok and tonumber(value) or nil
end

local function capture_write(line)
    if not state.capture or not state.capture_path then return end
    local file = io.open(state.capture_path, 'a')
    if not file then return end
    file:write(os.date('%Y-%m-%d %H:%M:%S'), '|', tostring(line), '\n')
    file:close()
end

local function hex_parameters(value)
    if type(value) ~= 'string' then return tostring(value or '') end
    local result = {}
    for index = 1, #value do
        result[#result + 1] = ('%02X'):format(value:byte(index))
    end
    return table.concat(result)
end

local function capture_incoming(id, packet)
    if not state.capture then return end
    if id == 0x032 or id == 0x034 then
        capture_write(('IN 0x%03X npc=%s index=%s zone=%s menu=%s params=%s'):format(
            id, tostring(packet and packet['NPC']),
            tostring(packet and packet['NPC Index']),
             tostring(packet and packet['Zone']),
             tostring(packet and packet['Menu ID']),
             hex_parameters(packet and packet['Menu Parameters'])))
    elseif id == 0x05C then
        capture_write(('IN 0x05C params=%s'):format(
            hex_parameters(packet and packet['Menu Parameters'])))
    elseif id == 0x01F or id == 0x020 then
        capture_write(('IN 0x%03X item=%s bag=%s index=%s count=%s status=%s'):format(
            id, tostring(packet and packet['Item']), tostring(packet and packet['Bag']),
            tostring(packet and packet['Index']), tostring(packet and packet['Count']),
            tostring(packet and packet['Status'])))
    elseif id == 0x03D then
        capture_write(('IN 0x03D price=%s index=%s type=%s count=%s'):format(
            tostring(packet and packet['Price']),
            tostring(packet and packet['Inventory Index']),
            tostring(packet and packet['Type']), tostring(packet and packet['Count'])))
    elseif id == 0x052 or id == 0x03C or id == 0x03E or id == 0x113 then
        capture_write(('IN 0x%03X'):format(id))
    end
end

local function handle_menu_packet(packet)
    if not packet then return false end
    local npc = tonumber(packet['NPC'])
    local npc_index = tonumber(packet['NPC Index'])
    local zone = tonumber(packet['Zone'])
    local menu_id = tonumber(packet['Menu ID'])
    if npc ~= PROFILE.guard.id then return false end

    if state.phase == 'buy_wait_menu' or state.phase == 'buy_retry_menu'
            or state.phase == 'buy_stall_drain' then
        if zone ~= PROFILE.zone or menu_id ~= PROFILE.guard.menu_id then
            fail(('Unexpected Achantere menu (zone=%s, menu=%s); capture it '
                .. 'with //ccash capture start.'):format(tostring(zone), tostring(menu_id)))
            return true
        end
        state.menu = {
            npc = npc,
            npc_index = npc_index,
            zone = zone,
            menu_id = menu_id,
        }
        if state.phase == 'buy_stall_drain' then
            verbose('A delayed Achantere menu arrived during partial-batch '
                .. 'recovery; cancelling it without submitting a purchase.')
            if cancel_open_menu() then
                finish_partial_batch_recovery('Delayed guard menu cancelled.')
            end
        else
            set_phase('buy_send_update', settings.MenuStepDelay,
                (tonumber(settings.MenuStepDelay) or 0.18) + 2)
        end
    end

    -- Keep the native dialogue from taking client-side movement/menu ownership.
    -- The server-side event remains open and is advanced with injected 0x05B
    -- packets, then releases normally after the non-automated finish packet.
    return state.phase:sub(1, 4) == 'buy_'
end

local function handle_validation_packet(packet)
    if state.phase ~= 'buy_wait_validation' then return false end
    local parameters = packet and packet['Menu Parameters']
    local eligibility = unpack_u32(parameters, 1)
    local insufficient_cp = unpack_u32(parameters, 5)
    local item_id = unpack_u32(parameters, 9)
    if insufficient_cp ~= 0 or item_id ~= PROFILE.item.id then
        fail(('Conquest validation rejected the purchase '
            .. '(eligibility=%s, insufficient_cp=%s, item=%s).'):format(
            tostring(eligibility), tostring(insufficient_cp), tostring(item_id)))
        return true
    end
    set_phase('buy_send_finish', settings.MenuStepDelay,
        (tonumber(settings.MenuStepDelay) or 0.18) + 2)
    return true
end

local function update_currency(packet)
    if not packet then return end
    local cp = Model.nonnegative_integer(packet["Conquest Points (San d'Oria)"])
    if cp == nil then return end
    state.cp = cp

    if state.preview_pending then
        state.preview_pending = false
        local free = Model.free_inventory_slots(all_items()) or 0
        local count = Model.purchase_count({
            cp = cp,
            floor = settings.ConquestFloor,
            cost = PROFILE.item.cp,
            free_slots = free,
            gil = current_gil(),
            gil_cap = GIL_CAP,
            estimated_sale = state.vendor_price or settings.EstimatedVendorPrice,
        })
        chat(('Preview: CP=%s, floor=%s, free=%d, next cycle=%d halberd(s).'):format(
            comma(cp), comma(settings.ConquestFloor), free, count))
    end

    if state.active and state.phase == 'wait_currency' then
        set_phase('plan_cycle', 0, 2)
    end
end

local function begin_automation(delay)
    if state.active then
        chat('Already active; use //ccash status.')
        return
    end
    local ok, reason, release_wait = preflight()
    if not ok then
        chat('Cannot start: ' .. reason, 123)
        return
    end

    if state.pending_purchase and state.menu_final_sent then
        if not scan_pending_purchase() then return end
        if state.pending_purchase.item_received then
            queue_acquired_slot(state.pending_purchase.slot)
            chat(('Recovered the completed purchase in inventory slot %d.'):format(
                state.pending_purchase.slot), 123)
        else
            chat('Cannot restart: the last purchase result is uncertain. Wait '
                .. 'for its item update, or verify CP and inventory manually then '
                .. 'use //ccash resolve none confirm.', 123)
            return
        end
    end


    if state.current_sale and state.current_sale.final_sent then
        if not valid_sale_item(state.current_sale.index) then
            state.current_sale.sale_response = true
            complete_sale_if_inventory_updated()
        else
            chat('Cannot restart: the last vendor sale result is uncertain. '
                .. 'Wait for its response, or verify the item and gil manually '
                .. 'then use //ccash resolve sale-none confirm.', 123)
            return
        end
    elseif state.current_sale then
        -- An appraisal without a confirm cannot have sold the item.
        state.current_sale = nil
    end

    local untracked = Model.sorted_numeric_keys(untracked_item_slots())
    if #untracked > 0 then
        chat(('Cannot start: Inventory contains %d untracked %s item(s). '
            .. 'Use //ccash adopt confirm only if every one may be sold.'):format(
            #untracked, PROFILE.item.name), 123)
        return
    end

    if release_wait then
        state.active = true
        state.error_reason = nil
        state.vendor_session_sales = 0
        state.vendor_menu_attempts = 0
        state.last_summary = nil
        state.local_release_attempted = false
        if not state.run_started_at then
            state.run_started_at = now()
            state.gil_earned = 0
            state.eta_seconds_per_item = nil
            state.eta_cycle_started_at = state.run_started_at
            state.projected_gil = current_gil()
        end
        local interval = math.max(10,
            tonumber(settings.PurchaseReleaseNoticeInterval) or 30)
        apply_local_event_release()
        set_phase('buy_release_wait', 0, interval)
        chat(('RECOVERY: Windower still reports Event status after a completed '
            .. 'purchase. Holding %d tracked halberd(s) and waiting for Idle; '
            .. 'no movement or NPC packet will be sent.'):format(acquired_count()), 123)
        return
    end

    state.active = true
    state.error_reason = nil
    state.cp = nil
    state.planned = 0
    state.cycle_purchased = 0
    state.purchased = 0
    state.sold = 0
    state.vendor_price = nil
    state.vendor_session_sales = 0
    state.vendor_menu_attempts = 0
    state.run_started_at = now()
    state.gil_earned = 0
    state.eta_seconds_per_item = nil
    state.eta_cycle_started_at = state.run_started_at
    state.projected_gil = current_gil()
    state.menu = nil
    state.menu_final_sent = false
    state.local_release_attempted = false
    state.pending_purchase = nil
    state.current_sale = nil
    state.last_summary = nil
    set_phase('start_delay', tonumber(delay) or 0, (tonumber(delay) or 0) + 3)
    chat(('Armed for %s; CP floor %s.'):format(
        PROFILE.item.name, comma(settings.ConquestFloor)))
    if acquired_count() > 0 then
        chat(('Resuming with %d tracked unsold halberd(s).'):format(acquired_count()), 123)
    end
end

local function deterministic_start_delay()
    local current_player = player()
    local name = current_player and current_player.name or ''
    local total = 0
    for index = 1, #name do total = (total + name:byte(index) * index) % 60 end
    return total / 100
end

local function show_status()
    local free = Model.free_inventory_slots(all_items())
    local guard_distance = target_distance('guard')
    local vendor_distance = target_distance('vendor')
    chat(('active=%s; phase=%s; floor=%s; CP=%s; free=%s; tracked=%d; '
        .. 'bought=%d; sold=%d; made=%s gil; vendor=%s gil'):format(
        tostring(state.active), state.phase, comma(settings.ConquestFloor),
        state.cp and comma(state.cp) or 'unknown', tostring(free or 'unknown'),
        acquired_count(), state.purchased, state.sold, comma(state.gil_earned),
        state.vendor_price and comma(state.vendor_price) or 'unknown'))
    chat(('distance: Achantere=%s, Pirvidiauce=%s.'):format(
        guard_distance and ('%.1f'):format(guard_distance) or 'unavailable',
        vendor_distance and ('%.1f'):format(vendor_distance) or 'unavailable'))
    if state.error_reason then chat('Last error: ' .. state.error_reason, 123) end
end

local function set_floor(value)
    if state.active then
        chat('Stop the active run before changing its conquest-point floor.', 123)
        return
    end
    local floor = Model.nonnegative_integer(value)
    if not floor or floor > 999999999 then
        chat('Floor must be a whole number from 0 through 999,999,999.', 123)
        return
    end
    settings.ConquestFloor = floor
    config.save(settings, 'all')
    chat(('Per-character conquest-point floor saved as %s.'):format(comma(floor)))
end

local function adopt_inventory()
    if state.active then
        chat('Stop the active run before adopting inventory items.', 123)
        return
    end
    if state.pending_purchase and state.menu_final_sent then
        chat('Resolve the uncertain finalized purchase before adopting items.', 123)
        return
    end
    if state.current_sale then
        chat('Resolve the pending vendor sale before adopting items.', 123)
        return
    end

    state.acquired = {}
    state.acquired_order = {}
    for _, index in ipairs(Model.sorted_numeric_keys(inventory_slots())) do
        queue_acquired_slot(index)
    end
    state.pending_purchase = nil
    state.menu = nil
    state.menu_final_sent = false
    chat(('Adopted %d inventory %s item(s) as run-owned. They will all be '
        .. 'sold on the next start.'):format(acquired_count(), PROFILE.item.name), 123)
end

local function stop_automation(reason)
    if not state.active then
        stop_running()
        chat('Already stopped.')
        return
    end
    stop_running()
    state.active = false
    if not cancel_open_menu() then return end
    state.phase = 'stopped'
    state.deadline = nil
    chat(reason or 'Stopped by command.', 123)
    if acquired_count() > 0 then
        chat(('Still tracking %d unsold halberd(s); do not sort inventory.'):format(
            acquired_count()), 123)
    end
end

local function save_hud_settings()
    config.save(settings, 'all')
    hud_placement_dirty = false
    render_hud(true)
end

local function process_hud_command(arguments)
    local command = tostring(arguments[1] or 'help'):lower()
    local value = arguments[2]

    if command == 'show' then
        settings.Hud.visible = true
        save_hud_settings()
    elseif command == 'hide' then
        if hud:capture_dragged_position() then hud_placement_dirty = true end
        hud:set_placement(false)
        settings.Hud.visible = false
        save_hud_settings()
    elseif command == 'config' or command == 'place'
            or command == 'placement' then
        local choice = value and tostring(value):lower() or nil
        local enable
        if choice == nil or choice == 'toggle' then
            enable = not hud:is_placement()
        elseif choice == 'on' then
            enable = true
        elseif choice == 'off' then
            enable = false
        else
            chat('Usage: //ccash hud config [on|off]', 123)
            return
        end
        if not enable and hud:capture_dragged_position() then
            hud_placement_dirty = true
        end
        hud:set_placement(enable)
        if not enable then save_hud_settings() else render_hud(true) end
        if enable then
            chat('HUD placement enabled. Drag any panel, then use '
                .. '//ccash hud config off.')
        else
            chat(('HUD placement saved at %d, %d.'):format(
                tonumber(settings.Hud.pos.x) or defaults.Hud.pos.x,
                tonumber(settings.Hud.pos.y) or defaults.Hud.pos.y))
        end
    elseif command == 'pos' then
        local x, y = tonumber(arguments[2]), tonumber(arguments[3])
        if not x or not y then
            chat('Usage: //ccash hud pos <x> <y>', 123)
            return
        end
        settings.Hud.pos.x = math.floor(x)
        settings.Hud.pos.y = math.floor(y)
        save_hud_settings()
    elseif command == 'scale' then
        local scale = tonumber(value)
        if not scale or scale < 0.5 or scale > 3 then
            chat('HUD scale must be between 0.5 and 3.0.', 123)
            return
        end
        settings.Hud.scale = scale
        hud:build()
        hud:set_placement(false)
        save_hud_settings()
    elseif command == 'opacity' then
        local opacity = tonumber(value)
        if not opacity or opacity < 0 or opacity > 255 then
            chat('HUD opacity must be between 0 and 255.', 123)
            return
        end
        settings.Hud.opacity = math.floor(opacity)
        hud:build()
        hud:set_placement(false)
        save_hud_settings()
    elseif command == 'reset' then
        settings.Hud.visible = defaults.Hud.visible
        settings.Hud.pos.x, settings.Hud.pos.y =
            defaults.Hud.pos.x, defaults.Hud.pos.y
        settings.Hud.scale = defaults.Hud.scale
        settings.Hud.opacity = defaults.Hud.opacity
        hud:build()
        hud:set_placement(false)
        save_hud_settings()
        chat('HUD display settings reset for this character.')
    else
        chat('HUD commands: show | hide | config [on|off] | pos <x> <y> | '
            .. 'scale <0.5-3> | opacity <0-255> | reset')
    end
end

local function show_help()
    chat('Commands:')
    chat('  //ccash floor <CP>          save this character\'s floor')
    chat('  //ccash preview             show the next safe batch size')
    chat('  //ccash start confirm       start/resume this character')
    chat('  //ccash stop | status       stop or inspect this character')
    chat('  //ccash adopt confirm       track every inventory halberd for sale')
    chat('  //ccash resolve none confirm clear a verified failed purchase')
    chat('  //ccash resolve sale-none confirm clear a verified failed sale')
    chat('  //ccash hud <command>       show, place, scale, or hide the HUD')
    chat('  //ccash all floor <CP>      set the floor on every loaded client')
    chat('  //ccash all start confirm   start all clients concurrently')
    chat('  //ccash all stop            stop all clients')
    chat('  //ccash capture start|stop  log one manual transaction for diagnosis')
end

local function process_command(command, arguments, from_ipc)
    command = command and tostring(command):lower() or 'status'
    arguments = arguments or {}

    if command == 'start' then
        if tostring(arguments[1] or ''):lower() ~= 'confirm' then
            chat('Start requires //ccash start confirm. Stop FastFollow and '
                .. 'unload NpcInteract first.', 123)
            return
        end
        if state.capture then
            chat('Stop packet capture before starting automation.', 123)
            return
        end
        begin_automation(from_ipc and deterministic_start_delay() or 0)
    elseif command == 'stop' or command == 'off' then
        stop_automation('Stopped by command.')
    elseif command == 'status' or command == '' then
        show_status()
    elseif command == 'floor' then
        set_floor(arguments[1])
    elseif command == 'adopt' then
        if tostring(arguments[1] or ''):lower() ~= 'confirm' then
            chat('Adopt requires //ccash adopt confirm; every inventory '
                .. 'halberd will become eligible for sale.', 123)
        else
            adopt_inventory()
        end
    elseif command == 'preview' then
        state.preview_pending = true
        if not inject(packets.new('outgoing', 0x10F, {}),
                'request conquest-point preview') then
            state.preview_pending = false
        end
    elseif command == 'resolve' then
        local outcome = tostring(arguments[1] or ''):lower()
        local confirmation = tostring(arguments[2] or ''):lower()
        if state.active then
            chat('Stop automation before resolving an uncertain transaction.', 123)
        elseif outcome == 'none' and confirmation == 'confirm' then
            if not state.pending_purchase or not state.menu_final_sent then
                chat('There is no uncertain finalized purchase to resolve.')
                return
            end
            if not scan_pending_purchase() then return end
            if state.pending_purchase and state.pending_purchase.item_received then
                chat('A purchased halberd is present; use start confirm to recover it.', 123)
            else
                state.pending_purchase = nil
                state.menu_final_sent = false
                state.menu = nil
                chat('Manually verified failed purchase cleared.')
            end
        elseif outcome == 'sale-none' and confirmation == 'confirm' then
            local sale = state.current_sale
            if not sale or not sale.final_sent then
                chat('There is no uncertain finalized sale to resolve.')
            elseif not valid_sale_item(sale.index) then
                chat('The tracked slot no longer contains the halberd; use '
                    .. 'start confirm to reconcile it as sold.', 123)
            else
                state.current_sale = nil
                chat('Manually verified failed vendor sale cleared.')
            end
        else
            chat('Usage: //ccash resolve none confirm, or '
                .. '//ccash resolve sale-none confirm after manual verification.', 123)
        end
    elseif command == 'capture' then
        local choice = tostring(arguments[1] or ''):lower()
        if choice == 'start' then
            if state.active then stop_automation('Stopped for packet capture.') end
            local current_player = player()
            local safe_name = current_player and current_player.name:gsub('[^%w_-]', '_')
                or 'unknown'
            state.capture_path = windower.addon_path .. 'data\\capture_' .. safe_name .. '.log'
            state.capture = true
            capture_write('CAPTURE START')
            chat('Capturing menu/shop packets to ' .. state.capture_path)
        elseif choice == 'stop' then
            capture_write('CAPTURE STOP')
            state.capture = false
            chat('Packet capture stopped.')
        else
            chat('Usage: //ccash capture start|stop', 123)
        end
    elseif command == 'hud' then
        process_hud_command(arguments)
    elseif command == 'help' then
        show_help()
    elseif command == 'all' and not from_ipc then
        local forwarded = {}
        for index = 2, #arguments do forwarded[#forwarded + 1] = arguments[index] end
        local subcommand = tostring(arguments[1] or ''):lower()
        if subcommand ~= 'start' and subcommand ~= 'stop'
                and subcommand ~= 'status' and subcommand ~= 'floor'
                and subcommand ~= 'adopt' and subcommand ~= 'hud' then
            chat('All supports only start, stop, status, floor, adopt, and hud.', 123)
            return
        end
        local pieces = {subcommand}
        for _, value in ipairs(forwarded) do pieces[#pieces + 1] = tostring(value) end
        windower.send_ipc_message(IPC_PREFIX .. table.concat(pieces, ':'))
        process_command(subcommand, forwarded, false)
    else
        show_help()
    end
end

local function tick_movement(kind)
    local current_player = player()
    if not current_player or tonumber(current_player.status) ~= 0 then
        fail('Character left Idle status while moving.')
        return
    end
    local me, target = self_mob(), npc_for(kind)
    if not me or not target then
        fail('A route NPC or the local player disappeared while moving.')
        return
    end
    local distance = Model.distance(me, target)
    if not distance then
        fail('Movement distance became unavailable.')
        return
    end

    if distance <= (tonumber(settings.InteractionDistance) or 4.4) then
        stop_running()
        local settle_delay = tonumber(settings.SettleDelay) or 0.35
        if kind == 'vendor' then
            settle_delay = tonumber(settings.VendorSettleDelay) or 1.00
        end
        set_phase(kind .. '_settle', settle_delay, settle_delay + 3)
        return
    end

    if distance < (state.move_best or distance) - 0.25 then
        state.move_best = distance
        state.move_progress_at = now()
    elseif now() - (state.move_progress_at or now())
            > (tonumber(settings.StuckTimeout) or 7) then
        fail(('No route progress toward %s for %.1f seconds.'):format(
            PROFILE[kind].name, tonumber(settings.StuckTimeout) or 7))
        return
    end

    local dx, dy = target.x - me.x, target.y - me.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length <= 0.01 then
        fail('Movement vector collapsed outside interaction range.')
        return
    end
    run_direction(dx / length, dy / length)
end

local function tick()
    if not state.active then return end
    local timestamp = now()
    if timestamp - state.last_tick < (tonumber(settings.MovementTick) or 0.1) then
        return
    end
    state.last_tick = timestamp

    local current_info = info()
    if tonumber(current_info.zone) ~= PROFILE.zone then
        fail('Zone changed while automation was active.')
        return
    end
    local current_player = player()
    if not current_player then
        fail('Player state disappeared.')
        return
    end
    local status = tonumber(current_player.status)
    if status == 1 then
        fail('Combat engagement detected.')
        return
    end
    if status ~= 0 and status ~= 4 then
        fail(('Unexpected player status %s while active.'):format(tostring(status)))
        return
    end
    if status == 4 and not transaction_phase() then
        fail('Unexpected Event status outside an NPC transaction.')
        return
    end
    if state.pending_purchase and status == 4 then
        state.pending_purchase.saw_event_status = true
    end

    if state.deadline and timestamp > state.deadline then
        if state.phase == 'buy_wait_menu' then
            local pending = state.pending_purchase
            local attempts = pending and (tonumber(pending.menu_attempts) or 0) or 0
            local maximum = guard_menu_attempt_limit()
            if pending and not state.menu and attempts < maximum and status == 0 then
                local delay = math.max(0.25,
                    tonumber(settings.GuardMenuRetryDelay) or 0.75)
                verbose(('Achantere menu attempt %d/%d received no response; '
                    .. 'safely retrying in %.2f seconds.'):format(
                    attempts, maximum, delay))
                set_phase('buy_retry_menu', delay, delay + 2)
                return
            elseif status == 4 then
                fail('Achantere menu packet was not received, but the client is '
                    .. 'in Event status; interaction was not retried.')
            elseif pending and not state.menu and not state.menu_final_sent
                    and acquired_count() > 0
                    and (tonumber(state.cycle_purchased) or 0) > 0 then
                local delay = math.max(2,
                    tonumber(settings.GuardStallDrainDelay) or 5.0)
                verbose(('Achantere returned no menu after %d attempts; '
                    .. 'holding the partial batch for %.1f seconds to drain '
                    .. 'any late response before vending it.'):format(
                    attempts, delay))
                set_phase('buy_stall_drain', delay,
                    delay + (tonumber(settings.TransactionTimeout) or 8))
            else
                fail(('Achantere returned no menu after %d safe interaction '
                    .. 'attempt(s); no purchase was submitted.'):format(attempts))
            end
            return
        elseif state.phase == 'buy_cooldown'
                or state.phase == 'buy_release_wait' then
            if state.pending_purchase or state.menu or state.menu_final_sent
                    or state.current_sale or acquired_count() < 1 then
                fail('Post-purchase release recovery state is inconsistent.')
                return
            end
            if status == 0 then
                finish_partial_batch_recovery(
                    'Post-purchase Event status returned to Idle.')
            else
                local interval = math.max(10,
                    tonumber(settings.PurchaseReleaseNoticeInterval) or 30)
                if state.phase == 'buy_cooldown' then
                    apply_local_event_release()
                    verbose(('Post-purchase Event status remained active beyond '
                        .. 'the normal cooldown; waiting safely for Idle before '
                        .. 'vending %d tracked halberd(s).'):format(
                        acquired_count()))
                else
                    verbose(('Still waiting for post-purchase Event release; '
                        .. '%d halberd(s) remain safely tracked.'):format(
                        acquired_count()))
                end
                set_phase('buy_release_wait', 0, interval)
            end
            return
        elseif state.phase == 'vendor_wait_shop' then
            local attempts = tonumber(state.vendor_menu_attempts) or 0
            local maximum = vendor_menu_attempt_limit()
            if not state.current_sale and attempts < maximum and status == 0 then
                local delay = math.max(0.25,
                    tonumber(settings.VendorMenuRetryDelay) or 0.75)
                verbose(('Pirvidiauce shop attempt %d/%d received no response; '
                    .. 'safely retrying in %.2f seconds.'):format(
                    attempts, maximum, delay))
                set_phase('vendor_retry_shop', delay, delay + 2)
                return
            elseif status == 4 then
                fail('Pirvidiauce shop packet was not received, but the client '
                    .. 'is in Event status; interaction was not retried.')
            else
                fail(('Pirvidiauce returned no shop after %d safe interaction '
                    .. 'attempt(s); no sale was submitted.'):format(attempts))
            end
            return
        elseif state.phase == 'buy_wait_result' then
            scan_pending_purchase()
            finish_purchase_if_ready()
            if not state.active or state.phase ~= 'buy_wait_result' then return end
        elseif state.phase == 'sale_wait_inventory' then
            complete_sale_if_inventory_updated()
            if not state.active or state.phase ~= 'sale_wait_inventory' then return end
        end
        fail('Timed out in phase ' .. state.phase .. '; transaction was not retried.')
        return
    end
    if timestamp < (state.ready_at or 0) then return end

    if state.phase == 'start_delay' then
        if acquired_count() > 0 then begin_move('vendor')
        else begin_move('guard') end
    elseif state.phase == 'move_guard' then
        tick_movement('guard')
    elseif state.phase == 'move_vendor' then
        tick_movement('vendor')
    elseif state.phase == 'guard_settle' then
        if status ~= 0 then fail('Character is not idle at Achantere.')
        else request_currency() end
    elseif state.phase == 'vendor_settle' then
        if status ~= 0 then fail('Character is not idle at Pirvidiauce.')
        else
            state.vendor_session_sales = 0
            state.vendor_menu_attempts = 0
            request_vendor_shop()
        end
    elseif state.phase == 'plan_cycle' then
        plan_cycle()
    elseif state.phase == 'buy_send_update' then
        if send_dialog(PROFILE.item.option, true, 0, 'validate conquest purchase') then
            set_phase('buy_wait_validation', 0,
                tonumber(settings.TransactionTimeout) or 8)
        end
    elseif state.phase == 'buy_send_finish' then
        if send_dialog(PROFILE.item.option, false, 0, 'complete conquest purchase') then
            state.menu_final_sent = true
            state.pending_purchase.final_at = timestamp
            set_phase('buy_wait_result', 0,
                tonumber(settings.TransactionTimeout) or 8)
        end
    elseif state.phase == 'buy_wait_result' then
        finish_purchase_if_ready()
    elseif state.phase == 'buy_cooldown' then
        if status == 0 then begin_purchase() end
    elseif state.phase == 'buy_retry_menu' then
        request_guard_menu()
    elseif state.phase == 'buy_stall_drain' then
        if status == 0 then
            finish_partial_batch_recovery('Guard response drain completed.')
        end
    elseif state.phase == 'buy_release_wait' then
        if status == 0 then
            finish_partial_batch_recovery(
                'Post-purchase Event status returned to Idle.')
        end
    elseif state.phase == 'buy_batch_settle' then
        if status == 0 then begin_move('vendor') end
    elseif state.phase == 'vendor_reopen' then
        state.vendor_menu_attempts = 0
        request_vendor_shop()
    elseif state.phase == 'vendor_retry_shop' then
        request_vendor_shop()
    elseif state.phase == 'sale_ready' then
        begin_sale()
    elseif state.phase == 'sale_send_confirm' then
        local sale = state.current_sale
        if not sale or not valid_sale_item(sale.index) then
            fail('Sale target changed after appraisal.')
        elseif send_sale_pair(sale.index) then
            sale.final_sent = true
            set_phase('sale_wait_confirm', 0,
                tonumber(settings.TransactionTimeout) or 8)
        end
    elseif state.phase == 'sale_wait_inventory' then
        complete_sale_if_inventory_updated()
    elseif state.phase == 'sale_cooldown' then
        begin_sale()
    elseif state.phase == 'vendor_batch_settle' then
        if status == 0 then begin_move('guard') end
    end
end

windower.register_event('prerender', tick)
windower.register_event('prerender', hud_prerender)

windower.register_event('incoming chunk', function(id, original, modified)
    local raw = modified or original
    local packet = nil
    if id == 0x032 or id == 0x034 or id == 0x05C
            or id == 0x01F or id == 0x020
            or id == 0x03D or id == 0x113 then
        packet = parse_packet('incoming', raw)
    end
    capture_incoming(id, packet)

    if id == 0x113 then
        update_currency(packet)
    elseif id == 0x032 or id == 0x034 then
        if state.active and handle_menu_packet(packet) then
            return true
        end
    elseif id == 0x05C then
        if state.active and handle_validation_packet(packet) then
            return true
        end
    elseif id == 0x052 and state.pending_purchase and state.menu_final_sent then
        -- The server also sends 0x052 after the validation/update step. Only
        -- the one received after our non-automated finish can acknowledge it.
        state.pending_purchase.release_received = true
        if state.active and state.phase == 'buy_wait_result' then
            finish_purchase_if_ready()
        end
    elseif (id == 0x01F or id == 0x020) and state.pending_purchase then
        if packet and tonumber(packet['Item']) == PROFILE.item.id
                and tonumber(packet['Bag']) == 0 then
            local index = tonumber(packet['Index'])
            if index and not state.pending_purchase.before[index] then
                state.pending_purchase.slot = index
                state.pending_purchase.item_received = true
                if state.active and state.phase == 'buy_wait_result' then
                    finish_purchase_if_ready()
                end
            end
        end
    elseif (id == 0x01F or id == 0x020) and state.current_sale
            and state.current_sale.sale_response then
        complete_sale_if_inventory_updated()
    elseif (id == 0x03C or id == 0x03E) and state.active
            and (state.phase == 'vendor_wait_shop'
                or state.phase == 'vendor_retry_shop') then
        set_phase('sale_ready', settings.MenuStepDelay,
            (tonumber(settings.MenuStepDelay) or 0.18) + 2)
        return true -- keep the native shop UI from taking movement ownership
    elseif id == 0x03D and packet then
        local index = tonumber(packet['Inventory Index'])
        local response_type = tonumber(packet['Type'])
        local price = Model.nonnegative_integer(packet['Price'])
        local sale = state.current_sale
        if state.active and sale and index == sale.index
                and state.phase == 'sale_wait_quote'
                and response_type == 0 then
            if not price or price < settings.MinimumVendorPrice then
                fail(('Pirvidiauce quoted %s gil; minimum is %s.'):format(
                    tostring(price), comma(settings.MinimumVendorPrice)))
            elseif (state.projected_gil or current_gil() or 0) > GIL_CAP - price then
                fail('Gil cap would be crossed by the quoted sale.')
            else
                state.vendor_price = price
                sale.price = price
                verbose(('Pirvidiauce verified at %s gil per halberd.'):format(comma(price)))
                set_phase('sale_send_confirm', settings.MenuStepDelay,
                    (tonumber(settings.MenuStepDelay) or 0.18) + 2)
            end
        elseif sale and index == sale.index and sale.final_sent
                and response_type == 1 then
            if not price or price <= 0 then
                fail('Vendor returned a zero-value sale response.')
            else
                sale.price = price
                sale.sale_response = true
                if state.active then
                    set_phase('sale_wait_inventory', 0,
                        tonumber(settings.TransactionTimeout) or 8)
                end
                complete_sale_if_inventory_updated()
            end
        end
    end

    if (id == 0x03C or id == 0x03E) and state.active
            and (state.phase:sub(1, 7) == 'vendor_'
                or state.phase:sub(1, 5) == 'sale_') then
        return true
    end
end)

windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
    local raw = modified or original
    if state.capture and (id == 0x01A or id == 0x05B
            or id == 0x084 or id == 0x085) then
        local packet = parse_packet('outgoing', raw)
        if id == 0x01A then
            capture_write(('OUT 0x01A target=%s index=%s category=%s injected=%s'):format(
                tostring(packet and packet['Target']),
                tostring(packet and packet['Target Index']),
                tostring(packet and packet['Category']), tostring(injected)))
        elseif id == 0x05B then
            capture_write(('OUT 0x05B target=%s option=%s u1=%s index=%s auto=%s '
                .. 'u2=%s zone=%s menu=%s injected=%s'):format(
                tostring(packet and packet['Target']),
                tostring(packet and packet['Option Index']),
                tostring(packet and packet['_unknown1']),
                tostring(packet and packet['Target Index']),
                tostring(packet and packet['Automated Message']),
                tostring(packet and packet['_unknown2']),
                tostring(packet and packet['Zone']),
                tostring(packet and packet['Menu ID']), tostring(injected)))
        else
            capture_write(('OUT 0x%03X injected=%s'):format(id, tostring(injected)))
        end
    end

    if state.active and not injected and not blocked then
        if id == 0x01A or id == 0x05B or id == 0x029 or id == 0x028
                or id == 0x084 or id == 0x085 then
            fail(('Manual action packet 0x%03X detected while active.'):format(id))
        end
    end
end)

local MOVEMENT_KEYS = {
    [0x11] = true, -- W
    [0x1E] = true, -- A
    [0x1F] = true, -- S
    [0x20] = true, -- D
    [0xC8] = true, -- Up
    [0xCB] = true, -- Left
    [0xCD] = true, -- Right
    [0xD0] = true, -- Down
}

windower.register_event('keyboard', function(dik, pressed)
    if state.active and pressed and MOVEMENT_KEYS[tonumber(dik)] then
        stop_automation('Manual movement key detected; automation stopped.')
    end
end)

windower.register_event('addon command', function(command, ...)
    process_command(command, {...}, false)
end)

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string' or message:sub(1, #IPC_PREFIX) ~= IPC_PREFIX then
        return
    end
    local values = {}
    for value in message:sub(#IPC_PREFIX + 1):gmatch('[^:]+') do
        values[#values + 1] = value
    end
    local command = table.remove(values, 1)
    process_command(command, values, true)
end)

windower.register_event('zone change', function()
    if state.active then fail('Zone change detected.') end
end)

windower.register_event('logout', function()
    stop_running()
    state.active = false
    state.phase = 'idle'
    state.run_started_at = nil
    state.gil_earned = 0
    state.eta_seconds_per_item = nil
    state.eta_cycle_started_at = nil
    hud:set_placement(false)
    hud:render(nil, false, true)
end)

windower.register_event('unload', function()
    stop_running()
    if hud:capture_dragged_position() then hud_placement_dirty = true end
    if hud_placement_dirty then config.save(settings, 'all') end
    hud:destroy()
end)

chat(('Loaded inert (v%s). San d\'Oria route: %s -> %s. Floor=%s.'):format(
    _addon.version, PROFILE.guard.name, PROFILE.vendor.name,
    comma(settings.ConquestFloor)))
chat('Before use, stop FastFollow and unload NpcInteract on all six clients.', 123)

-- Returning an API is harmless in Windower and makes the complete state
-- machine observable to the isolated regression harness.
return {
    state = state,
    profile = PROFILE,
    hud = hud,
    tick = tick,
    process_command = process_command,
}
