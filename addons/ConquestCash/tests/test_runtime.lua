-- Complete mocked buy/move/sell loop; no game client and no real packets.

_addon = {}

local clock = 100
os.clock = function() return clock end

local callbacks = {}
local chats = {}
local injected = {}
local local_incoming = {}
local ipc = {}
local saved = 0
local text_objects = {}
local image_objects = {}

local player = {
    id = 100,
    index = 1,
    name = 'Dolomedes',
    nation = 0,
    status = 0,
}

local me = {
    id = 100,
    index = 1,
    name = 'Dolomedes',
    status = 0,
    x = -247.201,
    y = 40.939,
}

local guard = {
    id = 17723471,
    index = 207,
    name = 'Achantere, T.K.',
    x = -247.201,
    y = 40.939,
}

local vendor = {
    id = 17723486,
    index = 222,
    name = 'Pirvidiauce',
    x = -218.375,
    y = 60.595,
}

local items = {
    gil = 1000,
    inventory = {max = 2, count = 0},
}

local function primitive()
    local object = {shown = false}
    function object:show() self.shown = true end
    function object:hide() self.shown = false end
    function object:destroy() self.destroyed = true end
    function object:pos(x, y)
        if x == nil then return self.x, self.y end
        self.x, self.y = x, y
    end
    function object:size(a, b) self.font_or_width, self.height = a, b end
    function object:alpha(value) self.opacity = value end
    function object:color(r, g, b) self.rgb = {r, g, b} end
    function object:extents()
        local size = tonumber(self.font_or_width) or 0
        return #tostring(self.value or '') * size * 0.61, size * 1.35
    end
    function object:draggable(value)
        if value == nil then return self.can_drag end
        self.can_drag = value
    end
    return object
end

package.preload.config = function()
    return {
        load = function(path, defaults)
            assert(path == 'data/settings_dolomedes.xml',
                'settings are not isolated by character')
            defaults.ConquestFloor = 10000
            return defaults
        end,
        save = function(_, scope)
            assert(scope == 'all', 'per-character file was not saved globally')
            saved = saved + 1
        end,
    }
end

package.preload.packets = function()
    return {
        new = function(direction, id, fields)
            fields = fields or {}
            fields._direction = direction
            fields._id = id
            return fields
        end,
        inject = function(packet)
            injected[#injected + 1] = packet
        end,
        parse = function(_, raw) return raw end,
    }
end

package.preload.images = function()
    return {new = function(options)
        local object = primitive()
        object.options = options
        image_objects[#image_objects + 1] = object
        return object
    end}
end

package.preload.texts = function()
    return {new = function(_, options)
        local object = primitive()
        object.options = options
        text_objects[#text_objects + 1] = object
        return object
    end}
end

windower = {
    addon_path = 'addons/ConquestCash/',
    add_to_chat = function(_, message) chats[#chats + 1] = message end,
    register_event = function(name, callback)
        callbacks[name] = callbacks[name] or {}
        callbacks[name][#callbacks[name] + 1] = callback
    end,
    send_ipc_message = function(message) ipc[#ipc + 1] = message end,
    packets = {
        inject_incoming = function(id, data)
            local_incoming[#local_incoming + 1] = {id = id, data = data}
        end,
    },
    ffxi = {
        get_player = function() return player end,
        get_info = function() return {zone = 231, logged_in = true} end,
        get_mob_by_target = function(target)
            if target == 'me' then return me end
        end,
        get_mob_by_id = function(id)
            if id == guard.id then return guard end
            if id == vendor.id then return vendor end
        end,
        get_mob_array = function()
            return {[guard.index] = guard, [vendor.index] = vendor}
        end,
        get_items = function() return items end,
        run = function() end,
    },
}

local function emit(name, ...)
    local result
    for _, callback in ipairs(callbacks[name] or {}) do
        local value = callback(...)
        if value ~= nil then result = value end
    end
    return result
end

local function advance(seconds, ticks)
    ticks = ticks or 1
    for _ = 1, ticks do
        clock = clock + seconds / ticks
        emit('prerender')
    end
end

local function last_packet(id)
    for index = #injected, 1, -1 do
        if injected[index]._id == id then return injected[index] end
    end
end

local function packet_count(id, predicate)
    local count = 0
    for _, packet in ipairs(injected) do
        if packet._id == id and (not predicate or predicate(packet)) then
            count = count + 1
        end
    end
    return count
end

local runtime = dofile('addons/ConquestCash/ConquestCash.lua')
local state = runtime.state

assert(#image_objects == 3 and #text_objects == 6,
    'three-panel HUD primitives were not created')
assert(text_objects[1].value == 'CP'
        and text_objects[3].value == 'GIL'
        and text_objects[5].value == 'ETA',
    'HUD labels do not describe the requested metrics')
assert(not image_objects[1].shown and not image_objects[2].shown
        and not image_objects[3].shown,
    'HUD was visible before a conversion run began')
assert(image_objects[1].options.texture.path:match('ccash_frame@2x%.png$'),
    'enlarged HUD did not use the sharp THHUD-style 2x frame')
assert(image_objects[1].options.size.width == 128
        and image_objects[1].options.size.height == 94,
    'HUD frame was not enlarged to the fixed display geometry')
local fixed_value_size = text_objects[2].font_or_width
assert(fixed_value_size == 12, 'HUD value font is not the fixed compact size')

emit('addon command', 'start', 'confirm')
assert(state.active and state.phase == 'start_delay')
emit('addon command', 'floor', '0')
assert(saved == 0, 'floor changed while a run was active')
advance(0.2)
assert(state.phase == 'move_guard')
assert(image_objects[1].shown and image_objects[2].shown
        and image_objects[3].shown,
    'HUD did not appear when the run began')
for index = 1, 3 do
    local label = text_objects[index * 2 - 1]
    local width = label:extents()
    assert(math.abs(label.x + width / 2 - (image_objects[index].x + 62)) < 0.51,
        'HUD header was not optically centered')
end
advance(0.2)
assert(state.phase == 'guard_settle')
advance(0.5)
assert(state.phase == 'wait_currency')
assert(last_packet(0x10F), 'currency request was not sent')

emit('incoming chunk', 0x113, {
    ["Conquest Points (San d'Oria)"] = 18000,
})
advance(0.2)
assert(state.phase == 'buy_wait_menu')
assert(text_objects[2].value == '18K',
    'HUD did not display the current conquest points')
assert(text_objects[4].value == '+0',
    'HUD session-gil counter did not begin at zero')
assert(text_objects[6].value == 'CALC...',
    'HUD claimed an ETA before a complete measured cycle')
for _, index in ipairs({2, 4, 6}) do
    assert(text_objects[index].rgb[1] == 255
            and text_objects[index].rgb[2] == 211
            and text_objects[index].rgb[3] == 82,
        'known HUD values did not share the gold palette')
end
assert(text_objects[2].font_or_width == fixed_value_size
        and text_objects[4].font_or_width == fixed_value_size
        and text_objects[6].font_or_width == fixed_value_size,
    'HUD value fonts changed size during a transaction update')
assert(last_packet(0x01A).Target == guard.id)
assert(state.pending_purchase.menu_attempts == 1)

-- A missing initial menu is safe to retry because no validation or finish
-- packet has been sent. This reproduces the intermittent live six-box stall.
local interactions_before_retry = packet_count(0x01A, function(packet)
    return packet.Target == guard.id
end)
advance(2.6)
assert(state.active and state.phase == 'buy_retry_menu',
    'missing guard menu stopped instead of scheduling a safe retry')
advance(0.8)
assert(state.phase == 'buy_wait_menu')
assert(state.pending_purchase.menu_attempts == 2)
assert(packet_count(0x01A, function(packet)
    return packet.Target == guard.id
end) == interactions_before_retry + 1, 'guard interaction was not retried once')

local function complete_purchase(slot, refreshed_cp)
    assert(emit('incoming chunk', 0x034, {
        NPC = guard.id,
        ['NPC Index'] = guard.index,
        Zone = 231,
        ['Menu ID'] = 32762,
        ['Menu Parameters'] = {0, 0, 0},
    }) == true, 'native conquest menu was not blocked')
    advance(0.25)
    local update = last_packet(0x05B)
    assert(update['Option Index'] == 32800)
    assert(update['Automated Message'] == true)

    assert(emit('incoming chunk', 0x05C, {
        ['Menu Parameters'] = {2, 0, 16844},
    }) == true, 'conquest validation update was not consumed')
    emit('incoming chunk', 0x052, {})
    assert(not state.pending_purchase.release_received,
        'validation-step 0x052 was mistaken for final purchase acknowledgement')
    advance(0.25)
    local finish = last_packet(0x05B)
    assert(finish['Option Index'] == 32800)
    assert(finish['Automated Message'] == false)

    if refreshed_cp then
        emit('incoming chunk', 0x113, {
            ["Conquest Points (San d'Oria)"] = refreshed_cp,
        })
    end

    items.inventory[slot] = {id = 16844, count = 1, status = 0}
    items.inventory.count = items.inventory.count + 1
    emit('incoming chunk', 0x01F, {
        Item = 16844, Bag = 0, Index = slot, Count = 1, Status = 0,
    })
    emit('incoming chunk', 0x052, {})
end

complete_purchase(1, 14000)
assert(state.purchased == 1 and state.cp == 14000)
advance(0.5)
assert(state.phase == 'buy_cooldown', 'retail-safe purchase cooldown was bypassed')
advance(0.6)
assert(state.phase == 'buy_wait_menu')
complete_purchase(2)
assert(state.purchased == 2 and state.cp == 10000)
assert(state.phase == 'buy_batch_settle')
advance(0.5)
assert(state.phase == 'move_vendor')

me.x, me.y = vendor.x, vendor.y
advance(0.2)
assert(state.phase == 'vendor_settle')
advance(1.1)
assert(state.phase == 'vendor_wait_shop')
assert(last_packet(0x01A).Target == vendor.id)

-- An unanswered vendor interaction is safe to retry because no appraisal or
-- sale packet has been sent. This reproduces Achoo's intermittent live stall.
local vendor_interactions_before_retry = packet_count(0x01A, function(packet)
    return packet.Target == vendor.id
end)
local appraisals_before_vendor_retry = packet_count(0x084)
local sale_confirms_before_vendor_retry = packet_count(0x085)
advance(2.6)
assert(state.active and state.phase == 'vendor_retry_shop',
    'missing vendor shop stopped instead of scheduling a safe retry')
advance(0.8)
assert(state.phase == 'vendor_wait_shop')
assert(state.vendor_menu_attempts == 2)
assert(packet_count(0x01A, function(packet)
    return packet.Target == vendor.id
end) == vendor_interactions_before_retry + 1,
    'vendor interaction was not retried once')
assert(packet_count(0x084) == appraisals_before_vendor_retry
        and packet_count(0x085) == sale_confirms_before_vendor_retry,
    'vendor open retry submitted a sale transaction')

-- 0x03E is the shop-open packet and normally precedes the 0x03C item list;
-- either is sufficient proof that the server accepted the interaction.
assert(emit('incoming chunk', 0x03E, {}) == true,
    'native vendor shop-open packet was not blocked or acknowledged')
advance(0.25)
assert(state.phase == 'sale_wait_quote')
assert(last_packet(0x084)['Inventory Index'] == 1)

emit('incoming chunk', 0x03D, {
    Price = 4183, ['Inventory Index'] = 1, Type = 0, Count = 1,
})
advance(0.25)
assert(state.phase == 'sale_wait_confirm')
assert(last_packet(0x085), 'first sale confirmation was not sent')
items.inventory[1] = nil
items.inventory.count = items.inventory.count - 1
items.gil = items.gil + 4183
emit('incoming chunk', 0x03D, {
    Price = 4183, ['Inventory Index'] = 1, Type = 1, Count = 1,
})
assert(state.sold == 1 and state.phase == 'sale_cooldown')
assert(state.gil_earned == 4183, 'confirmed first sale was not added to HUD gil')

advance(0.25)
assert(state.phase == 'sale_wait_confirm')
assert(last_packet(0x084)['Inventory Index'] == 2)
items.inventory[2] = nil
items.inventory.count = items.inventory.count - 1
items.gil = items.gil + 4183
emit('incoming chunk', 0x03D, {
    Price = 4183, ['Inventory Index'] = 2, Type = 1, Count = 1,
})
assert(state.sold == 2 and state.phase == 'vendor_batch_settle')
assert(state.gil_earned == 8366, 'HUD gil did not total confirmed sales')
assert(state.eta_seconds_per_item and state.eta_seconds_per_item > 0,
    'completed conversion cycle did not establish an ETA rate')
advance(0.5)
assert(state.phase == 'move_guard')
assert(text_objects[4].value == '+8K',
    'HUD did not render realized session gil')
assert(text_objects[6].value ~= 'CALC...' and text_objects[6].value ~= '--',
    'HUD did not render the measured ETA')
assert(text_objects[2].font_or_width == fixed_value_size
        and text_objects[4].font_or_width == fixed_value_size
        and text_objects[6].font_or_width == fixed_value_size,
    'HUD value fonts did not remain fixed after sales')

me.x, me.y = guard.x, guard.y
advance(0.2)
advance(0.5)
assert(state.phase == 'wait_currency')
emit('incoming chunk', 0x113, {
    ["Conquest Points (San d'Oria)"] = 10000,
})
advance(0.2)
assert(not state.active and state.phase == 'complete')
assert(state.purchased == 2 and state.sold == 2)
assert(state.cp == 10000, 'CP floor was crossed')
assert(next(state.acquired) == nil, 'sold slots remained tracked')
advance(0.3)
assert(text_objects[6].value == 'DONE',
    'HUD did not mark the floor-complete run as done')

-- A malformed validation response must stop before the final purchase packet.
emit('addon command', 'floor', '0')
assert(saved == 1, 'per-character floor was not persisted')
emit('addon command', 'start', 'confirm')
advance(0.2)
advance(0.2)
advance(0.5)
emit('incoming chunk', 0x113, {
    ["Conquest Points (San d'Oria)"] = 4000,
})
advance(0.2)
local finalized_before = packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
        and packet['Automated Message'] == false
end)
assert(emit('incoming chunk', 0x034, {
    NPC = guard.id,
    ['NPC Index'] = guard.index,
    Zone = 231,
    ['Menu ID'] = 32762,
    ['Menu Parameters'] = {0, 0, 0},
}) == true, 'native conquest menu was not blocked in rejection test')
advance(0.25)
emit('incoming chunk', 0x05C, {
    ['Menu Parameters'] = {2, 0, 9999},
})
assert(not state.active and state.phase == 'error')
assert(packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
        and packet['Automated Message'] == false
end) == finalized_before, 'invalid purchase was finalized')
assert(last_packet(0x05B)['Option Index'] == 0,
    'invalid conquest menu was not cancelled')

emit('addon command', 'floor', '12345')
assert(saved == 2, 'floor did not persist after the failed-closed run')

-- A delayed completed-sale response must reconcile even after emergency stop.
state.pending_purchase = nil
state.menu_final_sent = false
state.menu = nil
state.acquired = {[1] = true}
state.acquired_order = {1}
items.inventory[1] = {id = 16844, count = 1, status = 0}
items.inventory.count = 1
state.current_sale = {
    index = 1,
    price = 4183,
    sale_response = false,
    final_sent = true,
}
state.active = true
state.phase = 'sale_wait_confirm'
emit('addon command', 'stop')
items.inventory[1] = nil
items.inventory.count = 0
items.gil = items.gil + 4183
emit('incoming chunk', 0x03D, {
    Price = 4183, ['Inventory Index'] = 1, Type = 1, Count = 1,
})
assert(not state.active and state.phase == 'stopped')
assert(state.current_sale == nil and next(state.acquired) == nil,
    'completed sale was not reconciled after stop')

emit('addon command', 'all', 'stop')
assert(ipc[#ipc] == 'conquestcash:v1:stop')

-- Reload recovery must refuse untracked matching items until the user
-- explicitly adopts every matching slot as expendable.
state.pending_purchase = nil
state.current_sale = nil
state.menu_final_sent = false
state.acquired = {}
state.acquired_order = {}
items.inventory[1] = {id = 16844, count = 1, status = 0}
items.inventory.count = 1
player.status = 4
emit('addon command', 'start', 'confirm')
assert(not state.active,
    'Event-status recovery started with an untracked target halberd')
emit('addon command', 'adopt', 'confirm')
assert(state.acquired[1] and state.acquired_order[1] == 1,
    'explicit inventory adoption did not track the target halberd')
emit('addon command', 'all', 'adopt', 'confirm')
assert(ipc[#ipc] == 'conquestcash:v1:adopt:confirm')

-- A confirmed restart with safe tracked inventory may wait out Windower's
-- stale post-purchase Event status, but it must not move or inject any packet.
state.pending_purchase = nil
state.current_sale = nil
state.menu = nil
state.menu_final_sent = false
state.cycle_purchased = 0
state.run_started_at = nil
local packets_before_release_restart = #injected
local local_releases_before_restart = #local_incoming
emit('addon command', 'start', 'confirm')
assert(state.active and state.phase == 'buy_release_wait',
    'safe tracked inventory could not enter the Event-release wait')
assert(#injected == packets_before_release_restart and not state.running,
    'Event-release restart moved or injected a transaction packet')
assert(#local_incoming == local_releases_before_restart + 2
        and local_incoming[#local_incoming - 1].id == 0x052
        and local_incoming[#local_incoming].id == 0x052,
    'Event-release restart did not apply exactly one local release sequence')
player.status = 0
advance(0.2)
assert(state.active and state.phase == 'buy_batch_settle',
    'Event-release restart did not resume after Idle returned')
emit('addon command', 'stop')

-- Menu retries are bounded, and exhausting them must not send any 0x05B
-- validation/finalization packet or change the purchase counters.
state.acquired = {}
state.acquired_order = {}
items.inventory[1] = nil
items.inventory.count = 0
emit('addon command', 'floor', '0')
emit('addon command', 'start', 'confirm')
advance(0.2)
advance(0.2)
advance(0.5)
emit('incoming chunk', 0x113, {
    ["Conquest Points (San d'Oria)"] = 4000,
})
advance(0.2)
local dialog_packets_before_exhaustion = packet_count(0x05B)
for _ = 1, 2 do
    advance(2.6)
    assert(state.active and state.phase == 'buy_retry_menu')
    advance(0.8)
    assert(state.active and state.phase == 'buy_wait_menu')
end
assert(state.pending_purchase.menu_attempts == 3)
advance(2.6)
assert(not state.active and state.phase == 'error')
assert(state.pending_purchase.menu_attempts == 3,
    'guard interaction retry exceeded its configured bound')
assert(packet_count(0x05B) == dialog_packets_before_exhaustion,
    'menu retry exhaustion sent a transaction packet')

-- After a nonempty partial batch, the same exhaustion should recover through
-- the vendor round trip instead of requiring an operator restart. No purchase
-- transaction may be emitted, and a drain window protects against late menus.
local function arm_partial_guard_stall()
    state.pending_purchase = {
        before = {[1] = true}, cp_before = 8000,
        item_received = false, release_received = false,
        slot = nil, final_at = nil, saw_event_status = false,
        menu_attempts = 3,
    }
    state.current_sale = nil
    state.menu = nil
    state.menu_final_sent = false
    state.acquired = {[1] = true}
    state.acquired_order = {1}
    state.cycle_purchased = 1
    state.planned = 2
    state.cp = 8000
    items.inventory[1] = {id = 16844, count = 1, status = 0}
    items.inventory.count = 1
    me.x, me.y = guard.x, guard.y
    player.status = 0
    state.active = true
    state.phase = 'buy_wait_menu'
    state.phase_started = clock
    state.ready_at = clock
    state.deadline = clock + 2.5
end

arm_partial_guard_stall()
local purchases_before_partial_recovery = packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
end)
advance(2.6)
assert(state.active and state.phase == 'buy_stall_drain',
    'nonempty partial batch stopped after guard interaction exhaustion')
assert(state.pending_purchase and state.pending_purchase.menu_attempts == 3,
    'guard correlation was discarded before the late-response drain')
advance(5.1)
assert(state.active and state.phase == 'buy_batch_settle')
assert(state.pending_purchase == nil and state.acquired[1],
    'safe partial batch was not retained after the guard drain')
assert(packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
end) == purchases_before_partial_recovery,
    'partial-batch recovery submitted a purchase transaction')
advance(1.1)
assert(state.phase == 'move_vendor',
    'partial-batch recovery did not continue toward the vendor')

-- A genuinely late menu during the drain is owned, cancelled, and never
-- advanced to the conquest validation/finalization steps.
arm_partial_guard_stall()
advance(2.6)
assert(state.phase == 'buy_stall_drain')
local purchases_before_late_menu = packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
end)
assert(emit('incoming chunk', 0x034, {
    NPC = guard.id,
    ['NPC Index'] = guard.index,
    Zone = 231,
    ['Menu ID'] = 32762,
    ['Menu Parameters'] = {0, 0, 0},
}) == true, 'late guard menu was not blocked during recovery')
assert(state.active and state.phase == 'buy_batch_settle')
assert(state.pending_purchase == nil and last_packet(0x05B)['Option Index'] == 0,
    'late guard menu was not safely cancelled')
assert(packet_count(0x05B, function(packet)
    return packet['Option Index'] == 32800
end) == purchases_before_late_menu,
    'late menu recovery advanced a conquest purchase')

-- A completed purchase can leave Windower in Event status after the item and
-- release were both acknowledged. This is a safe wait, not a fatal timeout.
state.pending_purchase = nil
state.current_sale = nil
state.menu = nil
state.menu_final_sent = false
state.local_release_attempted = false
state.acquired = {[1] = true}
state.acquired_order = {1}
state.cycle_purchased = 1
state.planned = 2
state.cp = 4000
items.inventory[1] = {id = 16844, count = 1, status = 0}
items.inventory.count = 1
me.x, me.y = guard.x, guard.y
player.status = 4
state.active = true
state.phase = 'buy_cooldown'
state.phase_started = clock
state.ready_at = clock
state.deadline = clock + 8
local packets_before_release_wait = #injected
local local_releases_before_wait = #local_incoming
advance(8.1)
assert(state.active and state.phase == 'buy_release_wait',
    'post-purchase Event status still caused a fatal cooldown timeout')
assert(#injected == packets_before_release_wait,
    'post-purchase Event recovery injected a packet while status was Event')
assert(#local_incoming == local_releases_before_wait + 2,
    'post-purchase Event recovery did not apply one local release sequence')
advance(30.1)
assert(state.active and state.phase == 'buy_release_wait',
    'extended post-purchase Event status stopped the run')
assert(#injected == packets_before_release_wait,
    'extended Event-release wait injected a transaction packet')
assert(#local_incoming == local_releases_before_wait + 2,
    'extended Event-release wait repeated the local release sequence')
player.status = 0
advance(0.2)
assert(state.active and state.phase == 'buy_batch_settle',
    'post-purchase Event recovery did not continue after Idle returned')

-- Vendor interaction retries are also bounded and cannot emit appraisal or
-- confirmation packets before an actual shop-open acknowledgement.
state.pending_purchase = nil
state.current_sale = nil
state.acquired = {[1] = true}
state.acquired_order = {1}
items.inventory[1] = {id = 16844, count = 1, status = 0}
items.inventory.count = 1
me.x, me.y = vendor.x, vendor.y
state.active = true
state.phase = 'vendor_wait_shop'
state.phase_started = clock
state.ready_at = clock
state.deadline = clock + 2.5
state.vendor_menu_attempts = 1
local appraisals_before_vendor_exhaustion = packet_count(0x084)
local sale_confirms_before_vendor_exhaustion = packet_count(0x085)
for _ = 1, 2 do
    advance(2.6)
    assert(state.active and state.phase == 'vendor_retry_shop')
    advance(0.8)
    assert(state.phase == 'vendor_wait_shop')
end
advance(2.6)
assert(not state.active and state.phase == 'error')
assert(state.vendor_menu_attempts == 3,
    'vendor interaction retry exceeded its configured bound')
assert(packet_count(0x084) == appraisals_before_vendor_exhaustion
        and packet_count(0x085) == sale_confirms_before_vendor_exhaustion,
    'vendor retry exhaustion sent a sale transaction')

-- Match THHUD's placement workflow: any panel drags the coordinated strip,
-- and leaving configuration mode persists the per-character position.
emit('addon command', 'hud', 'config', 'on')
assert(image_objects[1].can_drag and image_objects[2].can_drag
        and image_objects[3].can_drag,
    'HUD configuration mode did not enable panel dragging')
local old_x, old_y = image_objects[1].x, image_objects[1].y
image_objects[2]:pos(image_objects[2].x + 37, image_objects[2].y + 12)
emit('prerender')
assert(image_objects[1].x == old_x + 37 and image_objects[1].y == old_y + 12,
    'dragging a panel did not move the coordinated HUD strip')
emit('addon command', 'hud', 'config', 'off')
assert(not image_objects[1].can_drag and not image_objects[2].can_drag
        and not image_objects[3].can_drag,
    'HUD placement remained draggable after configuration ended')

print('ConquestCash complete mocked runtime passed.')
