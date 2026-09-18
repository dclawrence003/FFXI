-- SPDX-License-Identifier: MIT
-- Three-panel Windower display using the same frame geometry and typography
-- as THHUD. Transaction state remains entirely outside this presentation layer.

local images = require('images')
local texts = require('texts')

local Hud = {}
Hud.__index = Hud

-- The source art is THHUD's 112x82 frame. Render it about 14% larger here so
-- long currency values have breathing room, while keeping text deliberately
-- smaller than THHUD's single large numeric value.
local FRAME_WIDTH = 128
local FRAME_HEIGHT = 94
local PANEL_SPACING = 134
local LABEL_FONT_SIZE = 9
local VALUE_FONT_SIZE = 12
local LABEL_CENTER_X = 62
local LABEL_CENTER_Y = 15
local VALUE_CENTER_X = 61
local VALUE_CENTER_Y = 45

local LABELS = {'CP', 'GIL', 'ETA'}
local LABEL_COLOR = {255, 255, 255}
local UNKNOWN_COLOR = {133, 148, 163}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function nearest_pixel(value)
    return math.floor(value + 0.5)
end

local function text_settings(font_size, color, opacity)
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

-- texts.extents() can report the previous frame's font metrics immediately
-- after a value changes. Deterministic Consolas metrics prevent the alternating
-- large/small feedback loop seen during rapid purchase and sale updates.
local function stable_text_size(value, font_size)
    return #tostring(value or '') * font_size * 0.61, font_size * 1.35
end

-- Header strings never change, so Windower's real extents are safe here and
-- center CP/GIL/ETA more precisely inside the narrow ornamental banners.
local function header_text_size(text_object, value, font_size)
    local ok, width, height = pcall(function() return text_object:extents() end)
    width, height = tonumber(width), tonumber(height)
    if ok and width and width > 0 and height and height > 0 then
        return width, height
    end
    return stable_text_size(value, font_size)
end

local function destroy(object)
    if object then pcall(function() object:destroy() end) end
end

function Hud.new(options)
    assert(type(options) == 'table', 'HUD options are required')
    assert(type(options.settings) == 'table', 'HUD settings are required')
    local self = setmetatable({
        settings = options.settings,
        asset_path = assert(options.asset_path, 'HUD asset path is required'),
        frames = {},
        labels = {},
        values = {},
        placement = false,
        last_key = nil,
    }, Hud)
    self:build()
    return self
end

function Hud:scale()
    return clamp(tonumber(self.settings.scale) or 1, 0.5, 3)
end

function Hud:opacity()
    return clamp(tonumber(self.settings.opacity) or 235, 0, 255)
end

function Hud:origin()
    local pos = self.settings.pos or {}
    return tonumber(pos.x) or 30, tonumber(pos.y) or 350
end

function Hud:destroy()
    for _, object in ipairs(self.frames) do destroy(object) end
    for _, object in ipairs(self.labels) do destroy(object) end
    for _, object in ipairs(self.values) do destroy(object) end
    self.frames, self.labels, self.values = {}, {}, {}
    self.last_key = nil
end

function Hud:set_visible(visible)
    for _, group in ipairs({self.frames, self.labels, self.values}) do
        for _, object in ipairs(group) do
            if visible then object:show() else object:hide() end
        end
    end
end

function Hud:set_placement(enabled)
    self.placement = enabled == true
    for _, frame in ipairs(self.frames) do
        frame:draggable(self.placement)
    end
    self.last_key = nil
end

function Hud:is_placement()
    return self.placement
end

function Hud:build()
    self:destroy()
    local scale, opacity = self:scale(), self:opacity()
    -- The display is larger than the native THHUD frame, so always downsample
    -- its 2x source rather than upscaling the smaller texture.
    local texture = 'ccash_frame@2x.png'
    local x, y = self:origin()

    for index = 1, 3 do
        local panel_x = x + (index - 1) * PANEL_SPACING * scale
        self.frames[index] = images.new({
            pos = {x = panel_x, y = y},
            size = {width = nearest_pixel(FRAME_WIDTH * scale),
                height = nearest_pixel(FRAME_HEIGHT * scale)},
            texture = {path = self.asset_path .. texture, fit = true},
            color = {alpha = opacity, red = 255, green = 255, blue = 255},
            repeatable = {x = 1, y = 1},
            draggable = self.placement,
            visible = false,
        })
        self.labels[index] = texts.new('${value}', text_settings(
            math.max(7, nearest_pixel(LABEL_FONT_SIZE * scale)),
            LABEL_COLOR, opacity))
        self.values[index] = texts.new('${value}', text_settings(
            math.max(9, nearest_pixel(VALUE_FONT_SIZE * scale)),
            UNKNOWN_COLOR, opacity))
        self.labels[index].value = LABELS[index]
        self.values[index].value = '--'
    end
    self:position({'--', '--', '--'})
    self:set_visible(false)
end

function Hud:position(display_values)
    local scale, opacity = self:scale(), self:opacity()
    local x, y = self:origin()
    local label_size = math.max(7, nearest_pixel(LABEL_FONT_SIZE * scale))
    local value_size = math.max(8, nearest_pixel(VALUE_FONT_SIZE * scale))

    for index = 1, 3 do
        local panel_x = x + (index - 1) * PANEL_SPACING * scale
        local frame, label, value = self.frames[index], self.labels[index],
            self.values[index]
        local shown = tostring(display_values[index] or '--')

        frame:pos(nearest_pixel(panel_x), nearest_pixel(y))
        frame:size(nearest_pixel(FRAME_WIDTH * scale),
            nearest_pixel(FRAME_HEIGHT * scale))
        frame:alpha(opacity)

        label:size(label_size)
        local label_width, label_height = header_text_size(
            label, LABELS[index], label_size)
        label:pos(
            nearest_pixel(panel_x + LABEL_CENTER_X * scale - label_width / 2),
            nearest_pixel(y + LABEL_CENTER_Y * scale - label_height / 2))
        label:alpha(opacity)

        value:size(value_size)
        local value_width, value_height = stable_text_size(shown, value_size)
        value:pos(
            nearest_pixel(panel_x + VALUE_CENTER_X * scale - value_width / 2),
            nearest_pixel(y + VALUE_CENTER_Y * scale - value_height / 2))
        value:alpha(opacity)
        frame:draggable(self.placement)
    end
end

-- Every panel is a valid drag handle. Whichever one moved determines the new
-- common origin; the other two snap back into the coordinated strip.
function Hud:capture_dragged_position()
    if not self.placement or #self.frames ~= 3 then return false end
    local scale = self:scale()
    local expected_x, expected_y = self:origin()
    for index, frame in ipairs(self.frames) do
        local ok, actual_x, actual_y = pcall(function() return frame:pos() end)
        if ok and tonumber(actual_x) and tonumber(actual_y) then
            local panel_x = expected_x + (index - 1) * PANEL_SPACING * scale
            if math.abs(actual_x - panel_x) > 0.5
                    or math.abs(actual_y - expected_y) > 0.5 then
                self.settings.pos = self.settings.pos or {}
                self.settings.pos.x = nearest_pixel(
                    actual_x - (index - 1) * PANEL_SPACING * scale)
                self.settings.pos.y = nearest_pixel(actual_y)
                self.last_key = nil
                return true
            end
        end
    end
    return false
end

function Hud:render(entries, visible, force)
    entries = entries or {}
    local values, key_parts = {}, {tostring(visible), tostring(self.placement)}
    local x, y = self:origin()
    key_parts[#key_parts + 1] = tostring(x)
    key_parts[#key_parts + 1] = tostring(y)
    key_parts[#key_parts + 1] = tostring(self:scale())
    key_parts[#key_parts + 1] = tostring(self:opacity())

    for index = 1, 3 do
        local entry = entries[index] or {}
        values[index] = tostring(entry.text or '--')
        local color = entry.color or UNKNOWN_COLOR
        key_parts[#key_parts + 1] = values[index]
        key_parts[#key_parts + 1] = table.concat(color, ',')
    end
    local key = table.concat(key_parts, '|')
    if not force and key == self.last_key then return end
    self.last_key = key

    for index = 1, 3 do
        local color = (entries[index] and entries[index].color) or UNKNOWN_COLOR
        self.values[index].value = values[index]
        self.values[index]:color(color[1], color[2], color[3])
    end
    self:position(values)
    self:set_visible(visible == true)
end

return Hud
