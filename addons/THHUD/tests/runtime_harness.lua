-- Execute the real addon against mocked Windower APIs.  The packet callbacks
-- are the same entry points used in-game; no live files or clients are touched.

package.path = 'addons/THHUD/?.lua;' .. package.path

local callbacks, ipc, text_objects, image_objects = {}, {}, {}, {}
local player = {name = 'Kickpuncher', id = 500, main_job = 'DNC',
    main_job_level = 99, sub_job = 'THF', sub_job_level = 49}
local mobs = {
    [1001] = {id = 1001, index = 41, name = 'Duplicate', spawn_type = 16,
        valid_target = true, hpp = 100},
    [1002] = {id = 1002, index = 42, name = 'Duplicate', spawn_type = 16,
        valid_target = true, hpp = 100},
    [1003] = {id = 1003, index = 43, name = 'Caster Target', spawn_type = 16,
        valid_target = true, hpp = 100},
}
local selected = mobs[1001]
local equipment = {equipment = {head = 1, head_bag = 0}}
local inventory = {[0] = {
    [1] = {id = 9001, extdata = string.rep('\0', 24)},
    [2] = {id = 9002, extdata = string.rep('\0', 24)},
}}

local function equip_packet(index, slot, bag)
    return string.rep('\0', 4) .. string.char(index, slot, bag, 0)
end

local function wait_clock(seconds)
    local until_time = os.clock() + seconds
    while os.clock() < until_time do end
end

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
    return {load = function(_, defaults) return defaults end,
        save = function() end}
end
package.preload.images = function()
    return {new = function()
        local object = primitive()
        image_objects[#image_objects + 1] = object
        return object
    end}
end
package.preload.texts = function()
    return {new = function()
        local object = primitive()
        text_objects[#text_objects + 1] = object
        return object
    end}
end
package.preload.packets = function()
    return {parse = function(_, raw) return raw end}
end
package.preload.resources = function()
    return {items = {[9001] = {en = 'Accidental TH Hat'},
            [9002] = {en = 'Ordinary Hat'}},
        item_descriptions = {[9001] = {en = 'DEF:1 "Treasure Hunter"+1'}}}
end
package.preload.extdata = function()
    return {decode = function() return {augments = {}} end}
end

coroutine.schedule = function(callback) callback() end
_addon = {}
windower = {
    addon_path = 'addons/THHUD/',
    add_to_chat = function() end,
    send_ipc_message = function(message) ipc[#ipc + 1] = message end,
    register_event = function(name, callback) callbacks[name] = callback end,
    ffxi = {
        get_player = function() return player end,
        get_info = function() return {zone = 100, logged_in = true} end,
        get_mjob_data = function() return {} end,
        get_mob_by_target = function(kind)
            return kind == 't' and selected or nil
        end,
        get_mob_by_id = function(id) return mobs[id] end,
        get_items = function(bag, index)
            if bag == nil then return equipment end
            if bag == 'equipment' then return equipment.equipment end
            return inventory[bag] and inventory[bag][index] or nil
        end,
    },
    packets = {parse_action = function(raw) return raw end},
}

assert(loadfile('addons/THHUD/THHUD.lua'))()
callbacks.load()

local value_text = assert(text_objects[2], 'value text was not created')
local frame = assert(image_objects[1], 'frame image was not created')
assert(value_text.value == '--', 'HUD did not begin unknown')
assert(frame.shown == false, 'HUD was visible without known TH')

-- Configuration mode is the only unknown-state preview. The frame itself is
-- draggable; prerender mirrors that position to the attached text primitives.
callbacks['addon command']('config', 'on')
assert(frame.shown == true and frame.can_drag == true,
    'configuration mode did not expose a draggable frame')
assert(value_text.value == '8', 'configuration mode did not show its preview')
frame:pos(321, 222)
callbacks.prerender()
assert(frame.x == 321 and frame.y == 222 and text_objects[1].x > frame.x,
    'dragged frame did not carry the text primitives')
local label_width, label_height = text_objects[1]:extents()
local value_width, value_height = value_text:extents()
assert(math.abs(text_objects[1].x + label_width / 2 - (frame.x + 54)) < 0.51
    and math.abs(text_objects[1].y + label_height / 2 - (frame.y + 13)) < 0.51,
    'TH label was not centered in the top banner')
assert(math.abs(value_text.x + value_width / 2 - (frame.x + 53)) < 0.51
    and math.abs(value_text.y + value_height / 2 - (frame.y + 38)) < 0.51,
    'TH value was not centered in the main display')
callbacks['addon command']('config', 'off')
assert(frame.shown == false and frame.can_drag == false,
    'configuration mode did not restore hidden unknown state')

-- Outgoing snapshot sees DNC/THF (TH2) plus a random TH+1 hat, then the
-- completed hostile job ability applies inferred TH3.
callbacks['outgoing chunk'](0x01A,
    {Category = 'Job ability usage', Param = 35, Target = 1001}, nil,
    false, false)
-- Simulate GearSwap restoring ordinary aftercast gear before THHUD's incoming
-- callback.  JA inference must retain the equipment committed with the action.
callbacks['outgoing chunk'](0x050, equip_packet(2, 4, 0), nil, true, false)
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 6, param = 35,
    targets = {{id = 1001, actions = {{message = 110, param = 35}}}}})
assert(value_text.value == '3', 'packet-derived inferred TH3 was not displayed')
assert(frame.shown == true, 'known TH did not reveal the HUD')
assert(value_text.rgb[1] == 112 and value_text.rgb[2] == 230,
    'inferred value did not use cyan')
assert(#ipc >= 1, 'local application was not broadcast')

-- Spell inference must use midcast gear, not either the outgoing precast set
-- or an aftercast restore emitted immediately before the result callback.
selected = mobs[1003]
callbacks['outgoing chunk'](0x01A,
    {Category = 'Magic cast', Param = 23, Target = 1003}, nil,
    false, false)
wait_clock(0.02)
callbacks['outgoing chunk'](0x050, equip_packet(1, 4, 0), nil, true, false)
wait_clock(0.07)
callbacks['outgoing chunk'](0x050, equip_packet(2, 4, 0), nil, true, false)
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 4, param = 23,
    targets = {{id = 1003, actions = {{message = 2, param = 0}}}}})
assert(value_text.value == '3', 'spell did not use the midcast TH equipment')

-- Same-name target retains independent unknown state.
selected = mobs[1002]
callbacks['target change']()
assert(value_text.value == '--', 'duplicate-name target inherited wrong mob state')
assert(frame.shown == false, 'unknown duplicate-name target left HUD visible')

-- A higher peer observation is accepted for the live matching signature.
local Protocol = require('thhud_protocol')
local signature = '000003EA-002A-1AE97C8C-10'
-- Obtain the runtime's deterministic signature by first applying locally,
-- then use the resulting outbound payload rather than duplicating its hash.
callbacks['outgoing chunk'](0x01A,
    {Category = 'Job ability usage', Param = 35, Target = 1002}, nil,
    false, false)
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 6, param = 35,
    targets = {{id = 1002, actions = {{message = 110, param = 35}}}}})
local outbound = assert(Protocol.decode(ipc[#ipc]))
signature = outbound.signature
callbacks['ipc message'](Protocol.observe('Dolomedes', 100, os.time(), 1002,
    signature, 5, 'inferred'))
assert(value_text.value == '5', 'higher peer application was not merged')

-- Server-confirmed 603 proc changes both value and confidence color.
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 1,
    targets = {{id = 1002, actions = {{message = 1,
        add_effect_message = 603, add_effect_param = 6}}}}})
assert(value_text.value == '6', '603 proc was not applied')
assert(value_text.rgb[1] == 255 and value_text.rgb[2] == 211,
    'confirmed value did not use gold')

-- A peer clear remains valid after the entity disappears; validation is
-- against the locally stored signature rather than a no-longer-live mob.
local saved_mob = mobs[1002]
mobs[1002] = nil
callbacks['ipc message'](Protocol.clear('Dolomedes', 100, os.time(), 1002,
    signature))
assert(value_text.value == '--', 'peer despawn clear required a live entity')
assert(frame.shown == false, 'cleared peer state left HUD visible')
mobs[1002] = saved_mob
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 1,
    targets = {{id = 1002, actions = {{message = 1,
        add_effect_message = 603, add_effect_param = 6}}}}})

callbacks['incoming chunk'](0x00E,
    {NPC = 1002, Mask = 0, Status = 0, ['HP %'] = 0})
assert(value_text.value == '6', 'position-only update caused a false reset')
callbacks['incoming chunk'](0x00E,
    {NPC = 1002, Mask = 4, Status = 0, ['HP %'] = 50})
callbacks['incoming chunk'](0x00E,
    {NPC = 1002, Mask = 4, Status = 0, ['HP %'] = 51})
assert(value_text.value == '--', 'passive regeneration did not clear TH')
assert(frame.shown == false, 'passive reset left HUD visible')
callbacks['incoming chunk'](0x028, {actor_id = 500, category = 1,
    targets = {{id = 1002, actions = {{message = 1,
        add_effect_message = 603, add_effect_param = 6}}}}})

callbacks['incoming chunk'](0x029, {Target = 1002, Message = 20})
assert(value_text.value == '--', 'death packet did not clear the mob')
assert(frame.shown == false, 'death left HUD visible')

print('THHUD runtime harness: packet, IPC, target, color, and death paths passed')
