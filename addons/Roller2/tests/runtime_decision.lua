-- Actual Roller's result-event decision wiring with simulated Windower resources.
-- This supplements the pure decision module with the production event handler.
local callbacks, scheduled, commands = {}, {}, {}
local noop = function() end
local job_abilities, next_job_ability_id = {}, 100
local text_api = {new = function()
    return {pos = noop, font = noop, size = noop, bold = noop, bg_alpha = noop,
        right_justified = noop, stroke_width = noop, stroke_transparency = noop,
        clear = noop, append = noop, update = noop, show = noop, hide = noop, destroy = noop}
end}

function unpack(values, index, last)
    index, last = index or 1, last or #values
    if index > last then return end
    return values[index], unpack(values, index + 1, last)
end

_addon = {}
debug.setmetatable(function() end, {__index = {loop = noop}})

function S(values)
    local out = values or {}
    return setmetatable(out, {__index = {
        contains = function(self, value)
            for _, entry in ipairs(self) do if entry == value then return true end end
            return false
        end,
        map = function(self, fn)
            local mapped = {}
            for _, entry in ipairs(self) do mapped[#mapped + 1] = fn(entry) end
            return S(mapped)
        end,
    }, __add = function(left, right)
        local joined = {}
        for _, entry in ipairs(left) do joined[#joined + 1] = entry end
        for _, entry in ipairs(right) do joined[#joined + 1] = entry end
        return S(joined)
    end})
end

string.endswith = setmetatable({}, {__sub = function() return {} end})
table.get = setmetatable({}, {__sub = function() return function(value) return value.en end end})
table.containskey = function(values, key) return values[key] ~= nil end
config = {load = function(value) return value end, save = noop}
res = {
    buffs = setmetatable({
        [308] = {en = 'Double-Up Chance'}, [357] = {en = 'Snake Eye'},
    }, {__index = {english = function() return {} end}}),
    job_abilities = setmetatable({}, {__index = {with = function(_, _, name)
        if not job_abilities[name] then
            job_abilities[name] = {id = next_job_ability_id}
            next_job_ability_id = next_job_ability_id + 1
        end
        return job_abilities[name]
    end}}),
    statuses = {[0] = {english = 'Idle'}},
}
require = function(name)
    assert(name == 'luau' or name == 'chat' or name == 'chat.chars'
        or name == 'packets' or name == 'texts')
    if name == 'texts' then return text_api end
    return {}
end
coroutine.schedule = function(fn) scheduled[#scheduled + 1] = fn end

local player = {id = 1, buffs = {308}, main_job = 'COR', main_job_level = 99, status = 0}
windower = {
    addon_path = './', add_to_chat = noop, send_command = noop,
    register_event = function(name, fn) callbacks[name] = fn end,
    chat = {input = function(command) commands[#commands + 1] = command end},
    get_windower_settings = function() return {} end,
    ffxi = {
        get_player = function() return player end,
        get_abilities = function() return {job_abilities = {177, 178}} end,
        get_ability_recasts = function() return {[197] = 0, [198] = 0, [194] = 0, [193] = 0} end,
    },
}
assert(loadfile('Roller2.lua'))()
callbacks['load']()
callbacks['addon command']('on')

local function run_scheduled()
    local pending = scheduled
    scheduled = {}
    for _, fn in ipairs(pending) do fn() end
end

local function result(roll, total)
    callbacks['action']({category = 6, actor_id = player.id, param = job_abilities[roll].id,
        targets = {{actions = {{param = total, message = 424}}}}})
    run_scheduled()
end

lastRollCrooked = true
result('Chaos Roll', 2)
assert(commands[#commands] == '/ja "Double-Up" <me>',
    'Crooked Cards low total did not keep safe Double-Up progression')

commands, scheduled = {}, {}
reset_snake_eye_state()
lastRollCrooked = true
result('Chaos Roll', 3)
assert(commands[#commands] == '/ja "Snake Eye" <me>',
    'Crooked Cards lucky approach did not queue Snake Eye')

commands, scheduled = {}, {}
reset_snake_eye_state()
lastRollCrooked = false
result('Samurai Roll', 9)
assert(commands[#commands] == '/ja "Snake Eye" <me>',
    'Snake Eye ready at 9 did not queue the safe continuation')

print('PASS Roller2 actual result-event policy wiring')
