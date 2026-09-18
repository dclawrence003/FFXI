-- Separate, screen-space navigation arrow.  Windower image primitives cannot
-- rotate textures, so ExpeditionGuide swaps among pre-rendered direction
-- frames.  This object is display-only: it never moves the player or consumes
-- input.

local Arrow = {}
Arrow.__index = Arrow

local function finite(value)
    value = tonumber(value)
    return value and value == value and value > -math.huge
        and value < math.huge and value or nil
end

local function screen_width(windower_api)
    local value = type(windower_api) == 'table'
        and type(windower_api.get_windower_settings) == 'function'
        and windower_api.get_windower_settings() or nil
    return finite(value and (value.ui_x_res or value.x_res)) or 1920
end

local function position(settings, windower_api)
    local size = math.max(48, math.floor(finite(settings.size) or 180))
    local configured_x = finite(settings.pos and settings.pos.x)
    local x = settings.auto_center ~= false
        and math.floor((screen_width(windower_api) - size) / 2)
        or math.floor(configured_x or 0)
    local y = math.floor(finite(settings.pos and settings.pos.y) or 54)
    return x, y, size
end

function Arrow.new(images, settings, asset_path, windower_api)
    settings = settings or {}
    local x, y, size = position(settings, windower_api)
    local frame_count = math.max(8,
        math.floor(finite(settings.frame_count) or 32))
    local prefix = type(settings.prefix) == 'string'
        and settings.prefix:match('^[A-Za-z0-9_-]+$')
        and settings.prefix or 'arrow_'
    local object = images.new({
        pos={x=x,y=y},
        size={width=size,height=size},
        texture={path=asset_path .. prefix .. '00.png',fit=true},
        color={alpha=tonumber(settings.alpha) or 245,
            red=255,green=255,blue=255},
        repeatable={x=1,y=1},
        draggable=false,
        visible=false,
    })
    local self = setmetatable({
        object=object, settings=settings,
        asset_path=asset_path, windower=windower_api,
        frame_count=frame_count, x=x, y=y, size=size,
        prefix=prefix, visible=false, last_frame=0,
    }, Arrow)
    self:hide()
    return self
end

function Arrow:destroy()
    if self.object then pcall(function() self.object:destroy() end) end
    self.object = nil
end

function Arrow:hide()
    self.visible = false
    if self.object then self.object:hide() end
end

function Arrow:show()
    self.visible = true
    if self.object then self.object:show() end
end

function Arrow:pos(x, y)
    x, y = finite(x), finite(y)
    if not x or not y then return false end
    self.settings.auto_center = false
    self.settings.pos.x, self.settings.pos.y = x, y
    self.x, self.y = math.floor(x), math.floor(y)
    if self.object then self.object:pos(self.x, self.y) end
    return true
end

function Arrow:render(model)
    if not self.object
        or self.settings.visible == false
        or type(model) ~= 'table'
    then
        self:hide()
        return
    end
    self:show()
    -- A transient missing facing/report should not make the navigation aid
    -- vanish. Retain the last known direction until fresh local data arrives.
    local frame = model.available == true and finite(model.frame)
        and (math.floor(model.frame) - 1) % self.frame_count
        or self.last_frame or 0
    if frame ~= self.last_frame then
        self.last_frame = frame
        self.object:path(self.asset_path
            .. (self.prefix..'%02d.png'):format(frame))
    end
end

return Arrow
