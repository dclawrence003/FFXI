--[[
THHUD

Packet-native, multi-client Treasure Hunter display for Windower 4.

Copyright (c) 2026 Don Lawrence

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

_addon.name = 'THHUD'
_addon.author = 'OpenAI Codex at the direction of Dolomedes'
_addon.version = '1.1.2'
_addon.commands = {'thhud'}

local config = require('config')
local images = require('images')
local texts = require('texts')
local packets = require('packets')
local resources = require('resources')
local extdata = require('extdata')

local State = require('thhud_state')
local Actions = require('thhud_actions')
local Calculator = require('thhud_calculator')
local Protocol = require('thhud_protocol')

local FRAME_WIDTH = 112
local FRAME_HEIGHT = 82
local LABEL_FONT_SIZE = 10
local VALUE_FONT_SIZE = 24
-- Optical centers for the visible banner and inner panel. Consolas glyph ink
-- sits slightly right and below the bounding boxes reported by texts.lua.
local LABEL_CENTER_X = 54
local LABEL_CENTER_Y = 13
local VALUE_CENTER_X = 53
local VALUE_CENTER_Y = 38
local SLOT_NAMES = {
    [0] = 'main', [1] = 'sub', [2] = 'range', [3] = 'ammo',
    [4] = 'head', [5] = 'body', [6] = 'hands', [7] = 'legs',
    [8] = 'feet', [9] = 'neck', [10] = 'waist',
    [11] = 'left_ear', [12] = 'right_ear',
    [13] = 'left_ring', [14] = 'right_ring', [15] = 'back',
}

local defaults = {
    visible = true,
    pos = {x = 30, y = 260},
    scale = 1.0,
    opacity = 235,
    ipc_max_age = 8,
    calculation = {
        -- Windower exposes Signet but not the active Super Kupower.  Set this
        -- true only while Treasure Hound is known to be active in this area.
        treasure_hound = false,
        manual_equipment_bonus = 0,
    },
    peers = {
        Dolomedes = true,
        Tackleberry = true,
        Kickpuncher = true,
        Barneystinson = true,
        Smalls = true,
        Achoo = true,
    },
}

local settings = nil
local settings_character = nil
local frame = nil
local label_text = nil
local value_text = nil
local tracker = State.new(nil)
local debug_enabled = false
local placement_mode = false
local placement_dirty = false
local last_render_at = 0
local last_render_key = nil
local equipment_shadow = {}
local equipment_history = {}
local pending_actions = {}
local lifecycle = {}

-- GearSwap can restore aftercast gear while addons are still handling the
-- incoming result packet.  Looking a few milliseconds behind that callback
-- preserves the action/midcast set without relying on GearSwap internals.
local EQUIPMENT_RESULT_GUARD = 0.050
local EQUIPMENT_HISTORY_SECONDS = 30
local EQUIPMENT_HISTORY_LIMIT = 192

local COLORS = {
    confirmed = {255, 211, 82},
    inferred = {112, 230, 255},
    unknown = {133, 148, 163},
    label = {255, 255, 255},
}

local OUTGOING_ACTIONS = {
    [3] = {[4] = true},
    [7] = {[3] = true},
    [9] = {[6] = true, [14] = true},
    [16] = {[2] = true},
    ['Magic cast'] = {[4] = true},
    ['Weaponskill usage'] = {[3] = true},
    ['Job ability usage'] = {[6] = true, [14] = true},
    ['Ranged attack'] = {[2] = true},
}

local function chat(message)
    windower.add_to_chat(207, '[THHUD] ' .. tostring(message))
end

local function debug(message)
    if debug_enabled then
        chat('DEBUG: ' .. tostring(message))
    end
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function sanitize_filename(value)
    return tostring(value or 'Unknown'):gsub('[^%w_-]', '_')
end

local function get_player()
    return windower.ffxi.get_player()
end

local function current_zone()
    local info = windower.ffxi.get_info()
    return info and tonumber(info.zone) or nil
end

local function destroy_ui()
    if frame then pcall(function() frame:destroy() end) end
    if label_text then pcall(function() label_text:destroy() end) end
    if value_text then pcall(function() value_text:destroy() end) end
    frame, label_text, value_text = nil, nil, nil
end

local function text_settings(font_size, color)
    local opacity = settings and clamp(tonumber(settings.opacity) or 235, 0, 255)
        or 235
    return {
        pos = {x = 0, y = 0},
        bg = {visible = false, alpha = 0, red = 0, green = 0, blue = 0},
        flags = {bold = true, italic = false, draggable = false,
            right = false, bottom = false},
        padding = 0,
        text = {
            font = 'Consolas', size = font_size, alpha = opacity,
            red = color[1], green = color[2], blue = color[3],
            stroke = {width = 2, alpha = opacity, red = 5, green = 10,
                blue = 18},
        },
    }
end

local function rendered_text_size(text_object, value, font_size)
    local ok, width, height = pcall(function()
        return text_object:extents()
    end)
    width, height = tonumber(width), tonumber(height)
    if not ok or not width or width <= 0 or not height or height <= 0 then
        width = #tostring(value or '') * font_size * 0.61
        height = font_size * 1.35
    end
    return width, height
end

local function nearest_pixel(value)
    return math.floor(value + 0.5)
end

local function position_ui(value)
    if not settings or not frame or not label_text or not value_text then
        return
    end
    local scale = clamp(tonumber(settings.scale) or 1, 0.5, 3)
    local x = tonumber(settings.pos.x) or defaults.pos.x
    local y = tonumber(settings.pos.y) or defaults.pos.y
    local label_size = math.max(7,
        math.floor(LABEL_FONT_SIZE * scale + 0.5))
    local value_size = math.max(12,
        math.floor(VALUE_FONT_SIZE * scale + 0.5))

    frame:pos(x, y)
    frame:size(math.floor(FRAME_WIDTH * scale + 0.5),
        math.floor(FRAME_HEIGHT * scale + 0.5))
    frame:alpha(clamp(tonumber(settings.opacity) or 235, 0, 255))

    label_text:size(label_size)
    local label_width, label_height = rendered_text_size(
        label_text, 'TH', label_size)
    label_text:pos(
        nearest_pixel(x + LABEL_CENTER_X * scale - label_width / 2),
        nearest_pixel(y + LABEL_CENTER_Y * scale - label_height / 2))

    value_text:size(value_size)
    local value_width, value_height = rendered_text_size(
        value_text, value or '--', value_size)
    value_text:pos(
        nearest_pixel(x + VALUE_CENTER_X * scale - value_width / 2),
        nearest_pixel(y + VALUE_CENTER_Y * scale - value_height / 2))
end

local function set_ui_visible(visible)
    if not frame or not label_text or not value_text then
        return
    end
    if visible then
        frame:show()
        label_text:show()
        value_text:show()
    else
        frame:hide()
        label_text:hide()
        value_text:hide()
    end
end

local function set_placement_mode(enabled)
    placement_mode = enabled == true
    if frame then
        frame:draggable(placement_mode)
    end
end

-- The image primitive owns mouse dragging. Mirror its live coordinates into
-- the per-character settings so the two text primitives follow the frame and
-- the final placement survives a reload.
local function capture_dragged_position()
    if not placement_mode or not settings or not frame then
        return false
    end
    local ok, x, y = pcall(function()
        return frame:pos()
    end)
    if not ok or not tonumber(x) or not tonumber(y) then
        return false
    end
    x, y = math.floor(tonumber(x) + 0.5), math.floor(tonumber(y) + 0.5)
    if x == tonumber(settings.pos.x) and y == tonumber(settings.pos.y) then
        return false
    end
    settings.pos.x, settings.pos.y = x, y
    placement_dirty = true
    return true
end

local function build_ui()
    destroy_ui()
    local scale = clamp(tonumber(settings.scale) or 1, 0.5, 3)
    local opacity = clamp(tonumber(settings.opacity) or 235, 0, 255)
    local texture_name = scale > 1 and 'thhud_frame@2x.png'
        or 'thhud_frame.png'
    frame = images.new({
        pos = {x = tonumber(settings.pos.x) or defaults.pos.x,
            y = tonumber(settings.pos.y) or defaults.pos.y},
        size = {width = math.floor(FRAME_WIDTH * scale + 0.5),
            height = math.floor(FRAME_HEIGHT * scale + 0.5)},
        texture = {path = windower.addon_path .. 'assets\\' .. texture_name,
            fit = true},
        color = {alpha = opacity, red = 255, green = 255, blue = 255},
        repeatable = {x = 1, y = 1},
        draggable = placement_mode,
        visible = false,
    })
    label_text = texts.new('${value}', text_settings(
        math.max(7, math.floor(LABEL_FONT_SIZE * scale + 0.5)), COLORS.label))
    value_text = texts.new('${value}', text_settings(
        math.max(12, math.floor(VALUE_FONT_SIZE * scale + 0.5)), COLORS.unknown))
    label_text.value = 'TH'
    value_text.value = '--'
    position_ui('--')
    set_ui_visible(false)
end

local function peer_allowed(sender)
    if not settings or type(settings.peers) ~= 'table' then
        return false
    end
    local wanted = tostring(sender or ''):lower()
    for key, value in pairs(settings.peers) do
        if type(key) == 'string' and value == true and key:lower() == wanted then
            return true
        end
        if type(key) == 'number' and tostring(value):lower() == wanted then
            return true
        end
    end
    return false
end

local function mob_signature(mob)
    if type(mob) ~= 'table' or not tonumber(mob.id)
        or not tonumber(mob.index) then
        return nil
    end
    local hash = 0
    for index = 1, #tostring(mob.name or '') do
        hash = (hash * 131 + tostring(mob.name):byte(index)) % 2147483647
    end
    return ('%08X-%04X-%08X-%02X'):format(tonumber(mob.id),
        tonumber(mob.index), hash, tonumber(mob.spawn_type) or 0)
end

local function valid_enemy(mob, allow_dead)
    if type(mob) ~= 'table' or tonumber(mob.spawn_type) ~= 16
        or not tonumber(mob.id) then
        return false
    end
    if not allow_dead and ((mob.valid_target == false)
        or (tonumber(mob.hpp) and tonumber(mob.hpp) <= 0)) then
        return false
    end
    return true
end

local function get_mob(mob_id)
    local ok, mob = pcall(windower.ffxi.get_mob_by_id, tonumber(mob_id))
    return ok and mob or nil
end

local function current_target()
    return windower.ffxi.get_mob_by_target('st')
        or windower.ffxi.get_mob_by_target('t')
end

local function render(force)
    if not settings or not value_text then
        return
    end
    local now = os.clock()
    if not force and now - last_render_at < 0.08 then
        return
    end
    last_render_at = now

    local shown, confidence = '--', 'unknown'
    local known_th = false
    local target = current_target()
    if valid_enemy(target, false) then
        local signature = mob_signature(target)
        local record = tracker:get(target.id, signature)
        if not record and tracker:get(target.id)
            and tracker:get(target.id).signature ~= signature then
            -- A live signature mismatch is a recycled server ID, never an
            -- invitation to display the previous spawn's state.
            tracker:clear(target.id)
        elseif record and tonumber(record.value) and tonumber(record.value) > 0 then
            shown = tostring(record.value)
            confidence = record.confidence
            known_th = true
        end
    end

    -- Placement mode is the sole intentional exception to the normal
    -- "known TH only" visibility rule.
    if placement_mode and not known_th then
        shown, confidence = '8', 'confirmed'
    end
    local should_show = placement_mode
        or (settings.visible == true and known_th)

    local key = shown .. ':' .. confidence .. ':' .. tostring(settings.visible)
        .. ':' .. tostring(placement_mode) .. ':' .. tostring(should_show)
        .. ':' .. tostring(settings.pos.x) .. ':' .. tostring(settings.pos.y)
        .. ':' .. tostring(settings.scale) .. ':' .. tostring(settings.opacity)
    if not force and key == last_render_key then
        return
    end
    last_render_key = key
    value_text.value = shown
    local color = COLORS[confidence] or COLORS.unknown
    value_text:color(color[1], color[2], color[3])
    value_text:alpha(clamp(tonumber(settings.opacity) or 235, 0, 255))
    label_text:alpha(clamp(tonumber(settings.opacity) or 235, 0, 255))
    position_ui(shown)
    if frame then frame:draggable(placement_mode) end
    set_ui_visible(should_show)
end

local function live_equipment_state()
    local items = windower.ffxi.get_items()
    local equipped = items and items.equipment
        or windower.ffxi.get_items('equipment')
    if type(equipped) ~= 'table' then
        return {}
    end

    local state = {}
    for slot_id = 0, 15 do
        local slot_name = SLOT_NAMES[slot_id]
        state[slot_id] = {
            bag = tonumber(equipped[slot_name .. '_bag']) or 0,
            index = tonumber(equipped[slot_name]) or 0,
        }
    end
    return state
end

local function copy_equipment_state(source)
    local result = {}
    for slot_id = 0, 15 do
        local item = source and source[slot_id] or nil
        result[slot_id] = {
            bag = item and tonumber(item.bag) or 0,
            index = item and tonumber(item.index) or 0,
        }
    end
    return result
end

local function record_equipment_snapshot(at)
    equipment_history[#equipment_history + 1] = {
        at = tonumber(at) or os.clock(),
        slots = copy_equipment_state(equipment_shadow),
    }
    local now = os.clock()
    while #equipment_history > EQUIPMENT_HISTORY_LIMIT
        or (#equipment_history > 1
            and now - equipment_history[1].at > EQUIPMENT_HISTORY_SECONDS) do
        table.remove(equipment_history, 1)
    end
end

local function reset_equipment_tracking()
    equipment_shadow = live_equipment_state()
    equipment_history = {}
    -- The current set predates addon initialization; make it eligible for an
    -- action result received immediately after load.
    record_equipment_snapshot(os.clock() - EQUIPMENT_HISTORY_SECONDS)
end

local function equipment_snapshot_before(cutoff)
    cutoff = tonumber(cutoff) or os.clock()
    for index = #equipment_history, 1, -1 do
        if equipment_history[index].at <= cutoff then
            return copy_equipment_state(equipment_history[index].slots)
        end
    end
    return nil
end

local function collect_equipment(slot_state)
    slot_state = slot_state or copy_equipment_state(equipment_shadow)
    local result = {}
    for slot_id = 0, 15 do
        local slot = slot_state[slot_id]
        local bag = slot and tonumber(slot.bag) or 0
        local index = slot and tonumber(slot.index) or 0
        if bag and index and index > 0 then
            local ok, item = pcall(windower.ffxi.get_items, bag, index)
            if ok and type(item) == 'table' and tonumber(item.id)
                and tonumber(item.id) > 0 then
                result[#result + 1] = item
            end
        end
    end
    return result
end

local function calculate_local_th(slot_state)
    local player = get_player()
    if not player then
        return 0, {trait = 0, gear_total = 0, gear = {}}
    end
    local blue_data = nil
    if tostring(player.main_job or ''):upper() == 'BLU' then
        local ok, data = pcall(windower.ffxi.get_mjob_data)
        blue_data = ok and data or nil
    end
    return Calculator.calculate(player, collect_equipment(slot_state), resources,
        extdata, {
        blue_data = blue_data,
        treasure_hound = settings and settings.calculation
            and settings.calculation.treasure_hound == true,
        manual_equipment_bonus = settings and settings.calculation
            and settings.calculation.manual_equipment_bonus or 0,
    })
end

local function send_ipc(message)
    if message then
        windower.send_ipc_message(message)
    end
end

local function local_sender()
    local player = get_player()
    return player and player.name or nil
end

local function broadcast_observation(record)
    local sender, zone = local_sender(), current_zone()
    if not sender or not zone or not record then return end
    send_ipc(Protocol.observe(sender, zone, os.time(), record.mob_id,
        record.signature, record.value, record.confidence))
end

local function broadcast_clear(mob_id, signature)
    local sender, zone = local_sender(), current_zone()
    if not sender or not zone or not signature then return end
    send_ipc(Protocol.clear(sender, zone, os.time(), mob_id, signature))
end

local function clear_mob(mob_id, signature, reason)
    local record = tracker:get(mob_id)
    signature = signature or (record and record.signature)
    if tracker:clear(mob_id, signature) then
        lifecycle[tonumber(mob_id)] = nil
        debug(('cleared %u (%s)'):format(tonumber(mob_id), reason or 'reset'))
        broadcast_clear(mob_id, signature)
        render(true)
        return true
    end
    return false
end

local function apply_observation(kind, mob_id, value, source, sender)
    local mob = get_mob(mob_id)
    if not valid_enemy(mob, true) then
        debug(('rejected %s for non-live enemy %s'):format(kind, tostring(mob_id)))
        return false
    end
    local signature = mob_signature(mob)
    local metadata = {source = source or 'packet', sender = sender,
        updated_at = os.time()}
    local changed, record
    if kind == 'confirmed' then
        changed, record = tracker:apply_confirmed(mob_id, signature, value,
            metadata)
    else
        changed, record = tracker:apply_inferred(mob_id, signature, value,
            metadata)
    end
    if changed then
        debug(('%s TH%s on %s [%u] via %s'):format(kind, tostring(value),
            tostring(mob.name), tonumber(mob_id), tostring(sender or source)))
        render(true)
    end
    return changed, record
end

local function match_pending(action)
    local now = os.clock()
    local action_targets = {}
    for _, target in pairs(type(action.targets) == 'table' and action.targets
        or {}) do
        if target and tonumber(target.id) then
            action_targets[tonumber(target.id)] = true
        end
    end
    for index = #pending_actions, 1, -1 do
        local pending = pending_actions[index]
        if now - pending.at > 20 then
            table.remove(pending_actions, index)
        elseif pending.incoming[tonumber(action.category)]
            and (not pending.target or action_targets[pending.target])
            and (not pending.param or not tonumber(action.param)
                or pending.param == tonumber(action.param)) then
            table.remove(pending_actions, index)
            return pending
        end
    end
    return nil
end

local function process_action(action)
    if type(action) ~= 'table' then return end
    local player = get_player()
    if not player then return end

    local inferred, details = nil, nil
    if tonumber(action.actor_id) == tonumber(player.id)
        and Actions.is_qualifying_category(action.category) then
        local pending = match_pending(action)
        local category = tonumber(action.category)
        local slots, source
        -- WS/JA gear is committed with the action request.  Spells and ranged
        -- attacks can switch from precast/preshot to midcast/midshot after
        -- that request, so those use the last set preceding the result.
        if pending and (category == 3 or category == 6 or category == 14) then
            slots = pending.slots
            source = 'outgoing action equipment'
        else
            slots = equipment_snapshot_before(
                os.clock() - EQUIPMENT_RESULT_GUARD)
            source = 'result equipment timeline'
            if not slots and pending then
                slots = pending.slots
                source = 'outgoing action fallback'
            end
        end
        inferred, details = calculate_local_th(slots)
        if details then details.snapshot = source end
        if debug_enabled and details then
            debug(('local action category %s: TH%s (trait %s, gear %s, %s)')
                :format(tostring(action.category), tostring(inferred),
                    tostring(details.trait), tostring(details.gear_total),
                    tostring(details.snapshot or 'outgoing snapshot')))
        end
    end

    for _, event in ipairs(Actions.inspect(action, player.id, inferred)) do
        if event.kind == 'clear' then
            clear_mob(event.mob_id, nil, 'death action')
        else
            local changed, record = apply_observation(event.kind, event.mob_id,
                event.value, 'action packet', player.name)
            if event.kind == 'inferred' and record then
                -- Broadcast every valid local application.  A peer may not yet
                -- know a value that this client already held locally.
                broadcast_observation(record)
            elseif event.kind == 'confirmed' and changed then
                -- All clients normally see the raw proc packet; this also
                -- covers a client that was loading during that instant.
                broadcast_observation(record)
            end
        end
    end
end

local function remember_equipment(data, injected, at)
    if type(data) ~= 'string' or #data < at + 2 then return false end
    local index, slot, bag = data:byte(at), data:byte(at + 1), data:byte(at + 2)
    if not slot or slot < 0 or slot > 15 then return false end
    local previous = equipment_shadow[slot]
    local now = os.clock()
    if previous and previous.injected and not injected
        and now - previous.at < 0.75 then
        -- Windower reports uninjected equip chunks after GearSwap's injected
        -- chunks although the uninjected packet reaches the server first.
        return false
    end
    equipment_shadow[slot] = {index = tonumber(index) or 0,
        bag = tonumber(bag) or 0, at = now, injected = injected == true}
    return true
end

local function inspect_outgoing(id, original, modified, injected, blocked)
    if blocked then return end
    local data = modified or original
    if id == 0x050 then
        if remember_equipment(data, injected, 5) then
            record_equipment_snapshot()
        end
        return
    elseif id == 0x051 and type(data) == 'string' and #data >= 9 then
        local count = data:byte(5) or 0
        local changed = false
        for offset = 9, 9 + 4 * (count - 1), 4 do
            changed = remember_equipment(data, injected, offset) or changed
        end
        if changed then
            record_equipment_snapshot()
        end
        return
    elseif id ~= 0x01A then
        return
    end

    local ok, packet = pcall(packets.parse, 'outgoing', data)
    if not ok or type(packet) ~= 'table' then return end
    local incoming = OUTGOING_ACTIONS[packet.Category]
        or OUTGOING_ACTIONS[tonumber(packet.Category)]
    if not incoming then return end

    pending_actions[#pending_actions + 1] = {
        incoming = incoming,
        param = tonumber(packet.Param),
        target = tonumber(packet.Target),
        slots = copy_equipment_state(equipment_shadow),
        at = os.clock(),
    }
    while #pending_actions > 12 do
        table.remove(pending_actions, 1)
    end
end

local function process_reset_packet(packet)
    local mob_id = tonumber(packet and packet.NPC)
    if not mob_id or not tracker:get(mob_id) then return end
    local mask = tonumber(packet.Mask)
    if mask and math.floor(mask / 4) % 2 ~= 1 then
        -- Bit 2 controls HP/status validity.  Position-only 0x00E packets
        -- carry zeroes in those fields and must not look like passive mobs.
        return
    end
    local status = packet.Status
    local idle = tonumber(status) == 0 or tostring(status):lower() == 'idle'
    local hpp = tonumber(packet['HP %'])
    local previous = lifecycle[mob_id]
    local regenerating = idle and hpp and previous and previous.idle
        and previous.hpp and hpp > previous.hpp
    lifecycle[mob_id] = {idle = idle, hpp = hpp}
    if idle and hpp == 100 then
        clear_mob(mob_id, nil, 'passive at full HP')
    elseif regenerating then
        clear_mob(mob_id, nil, 'passive regeneration')
    end
end

local function inspect_incoming(id, original)
    if id == 0x028 then
        local ok, action = pcall(windower.packets.parse_action, original)
        if ok then process_action(action) end
    elseif id == 0x029 then
        local ok, packet = pcall(packets.parse, 'incoming', original)
        if ok and packet then
            local message = tonumber(packet.Message)
            if message then message = message % 32768 end
            if message == 6 or message == 20 then
                clear_mob(tonumber(packet.Target), nil, 'death message')
            end
        end
    elseif id == 0x038 then
        local ok, packet = pcall(packets.parse, 'incoming', original)
        if ok and packet and tostring(packet.Type):lower() == 'kesu' then
            clear_mob(tonumber(packet.Mob), nil, 'despawn')
        end
    elseif id == 0x00E then
        local ok, packet = pcall(packets.parse, 'incoming', original)
        if ok then process_reset_packet(packet) end
    end
end

local function send_hello()
    local sender, zone = local_sender(), current_zone()
    if sender and zone then
        send_ipc(Protocol.hello(sender, zone, os.time()))
    end
end

local function initialize()
    local player = get_player()
    if not player or not player.name then return false end
    if settings and settings_character == player.name and frame then
        return true
    end

    settings_character = player.name
    settings = config.load(('data/settings_%s.xml'):format(
        sanitize_filename(settings_character)), defaults)
    config.save(settings)
    tracker = State.new(current_zone())
    pending_actions, lifecycle = {}, {}
    reset_equipment_tracking()
    build_ui()
    render(true)
    send_hello()
    coroutine.schedule(send_hello, 1.0)
    return true
end

local function save_and_render()
    if settings then config.save(settings) end
    last_render_key = nil
    render(true)
end

windower.register_event('load', function()
    initialize()
end)

windower.register_event('login', function()
    coroutine.schedule(initialize, 0.5)
end)

windower.register_event('logout', function()
    capture_dragged_position()
    if placement_dirty and settings then config.save(settings) end
    set_placement_mode(false)
    placement_dirty = false
    tracker:clear_all()
    pending_actions, equipment_shadow, equipment_history, lifecycle = {}, {}, {}, {}
    destroy_ui()
    settings, settings_character = nil, nil
end)

windower.register_event('unload', function()
    capture_dragged_position()
    if placement_dirty and settings then config.save(settings) end
    destroy_ui()
end)

windower.register_event('zone change', function(new_zone)
    tracker:set_zone(tonumber(new_zone) or current_zone())
    pending_actions, lifecycle = {}, {}
    reset_equipment_tracking()
    render(true)
    coroutine.schedule(reset_equipment_tracking, 1.0)
    coroutine.schedule(send_hello, 1.0)
end)

windower.register_event('target change', function()
    render(true)
end)

windower.register_event('job change', function()
    coroutine.schedule(reset_equipment_tracking, 0.5)
end)

windower.register_event('prerender', function()
    render(capture_dragged_position())
end)

windower.register_event('outgoing chunk', inspect_outgoing)
windower.register_event('incoming chunk', inspect_incoming)

windower.register_event('ipc message', function(message)
    if not settings then return end
    local payload, reason = Protocol.validate(message, {
        zone = current_zone(),
        now = os.time(),
        max_age = tonumber(settings.ipc_max_age) or 8,
        allowed_sender = peer_allowed,
    })
    if not payload then
        if tostring(message):sub(1, 6) == 'THHUD|' then
            debug('rejected IPC: ' .. tostring(reason))
        end
        return
    end

    if payload.kind == 'HELLO' then
        for _, record in ipairs(tracker:snapshot()) do
            local mob = get_mob(record.mob_id)
            if valid_enemy(mob, false)
                and mob_signature(mob) == record.signature then
                broadcast_observation(record)
            end
        end
        return
    end

    if payload.kind == 'CLEAR' then
        -- A death/despawn clear often arrives after the entity has ceased to
        -- be a valid live target.  Validate it against our existing record's
        -- full signature instead of requiring the entity to still exist.
        if tracker:clear(payload.mob_id, payload.signature) then
            lifecycle[payload.mob_id] = nil
            render(true)
        end
        return
    end

    local mob = get_mob(payload.mob_id)
    if not valid_enemy(mob, true)
        or mob_signature(mob) ~= payload.signature then
        debug(('rejected IPC %s: stale/recycled mob %s'):format(
            payload.kind, tostring(payload.mob_id)))
        return
    end

    if payload.confidence == 'confirmed' then
        apply_observation('confirmed', payload.mob_id, payload.value,
            'ipc', payload.sender)
    else
        apply_observation('inferred', payload.mob_id, payload.value,
            'ipc', payload.sender)
    end
end)

windower.register_event('addon command', function(command, ...)
    if not settings and not initialize() then
        chat('Not logged in; settings are not available yet.')
        return
    end
    command = command and tostring(command):lower() or 'help'
    local args = {...}

    if command == 'show' then
        settings.visible = true
        save_and_render()
    elseif command == 'hide' then
        capture_dragged_position()
        set_placement_mode(false)
        placement_dirty = false
        settings.visible = false
        save_and_render()
    elseif command == 'config' or command == 'place'
        or command == 'placement' then
        local value = args[1] and tostring(args[1]):lower() or nil
        local enable
        if value == nil or value == 'toggle' then
            enable = not placement_mode
        elseif value == 'on' then
            enable = true
        elseif value == 'off' then
            enable = false
        else
            chat('Usage: //thhud config [on|off]')
            return
        end

        if not enable then
            capture_dragged_position()
        end
        set_placement_mode(enable)
        if not enable then
            config.save(settings)
            placement_dirty = false
        end
        last_render_key = nil
        render(true)
        if enable then
            chat('Placement mode enabled. Drag the TH frame, then run //thhud config off.')
        else
            chat(('Placement saved at %d, %d.'):format(
                tonumber(settings.pos.x) or defaults.pos.x,
                tonumber(settings.pos.y) or defaults.pos.y))
        end
    elseif command == 'pos' then
        local x, y = tonumber(args[1]), tonumber(args[2])
        if not x or not y then
            chat('Usage: //thhud pos <x> <y>')
            return
        end
        settings.pos.x, settings.pos.y = math.floor(x), math.floor(y)
        save_and_render()
    elseif command == 'scale' then
        local value = tonumber(args[1])
        if not value or value < 0.5 or value > 3 then
            chat('Scale must be between 0.5 and 3.0.')
            return
        end
        settings.scale = value
        build_ui()
        save_and_render()
    elseif command == 'opacity' then
        local value = tonumber(args[1])
        if not value or value < 0 or value > 255 then
            chat('Opacity must be between 0 and 255.')
            return
        end
        settings.opacity = math.floor(value)
        build_ui()
        save_and_render()
    elseif command == 'reset' then
        settings.visible = defaults.visible
        settings.pos.x, settings.pos.y = defaults.pos.x, defaults.pos.y
        settings.scale, settings.opacity = defaults.scale, defaults.opacity
        settings.ipc_max_age = defaults.ipc_max_age
        settings.calculation.treasure_hound = false
        settings.calculation.manual_equipment_bonus = 0
        build_ui()
        save_and_render()
        chat('Display and calculation settings reset for ' .. settings_character .. '.')
    elseif command == 'debug' then
        local value = args[1] and tostring(args[1]):lower() or nil
        if value == 'on' then debug_enabled = true
        elseif value == 'off' then debug_enabled = false
        else debug_enabled = not debug_enabled end
        chat('Debug ' .. (debug_enabled and 'enabled.' or 'disabled.'))
        if debug_enabled then
            local th, details = calculate_local_th()
            chat(('Local application now: TH%s (trait %s, gear %s, cap %s, hound %s).')
                :format(th, details.trait, details.gear_total,
                    details.equipment_cap, details.treasure_hound))
            for _, item in ipairs(details.gear) do
                chat(('  %s: +%s (static %s, augment %s)'):format(
                    item.name or ('item ' .. item.id), item.total,
                    item.static, item.augmented))
            end
        end
    else
        chat('Commands: show | hide | config [on|off] | pos <x> <y> | '
            .. 'scale <0.5-3> | opacity <0-255> | reset | debug [on|off]')
    end
end)
