local HUD = {}
HUD.__index = HUD

local function display(value)
    return tostring(value or ''):gsub('[%z\1-\31\127]+', ' ')
end

local function append_wrapped(lines, prefix, value, width)
    value = display(value)
    width = tonumber(width) or 100
    local first = true
    repeat
        local room = math.max(20, width - (first and #prefix or 2))
        local part
        if #value <= room then
            part, value = value, ''
        else
            local candidate = value:sub(1, room)
            local split_at = candidate:match('^.*()%s+')
            split_at = split_at and split_at > math.floor(room * 0.55)
                and split_at or room
            part = value:sub(1, split_at):gsub('%s+$', '')
            value = value:sub(split_at + 1):gsub('^%s+', '')
        end
        lines[#lines + 1] = (first and prefix or '  ') .. part
        first = false
    until value == ''
end

function HUD.new(texts, display_settings, root_settings)
    local object = texts.new('${value}', display_settings, root_settings)
    return setmetatable({object=object, visible=true, last=nil,
        wrap_width=tonumber(display_settings.wrap_width) or 88}, HUD)
end

function HUD:destroy()
    if self.object then pcall(function() self.object:destroy() end) end
    self.object = nil
end

function HUD:show()
    self.visible = true
    if self.object then self.object:show() end
end

function HUD:hide()
    self.visible = false
    if self.object then self.object:hide() end
end

function HUD:pos(x, y)
    if self.object then self.object:pos(x, y) end
end

function HUD:render(model)
    if not self.object then return end
    if not model.visible then self:hide(); return end
    self:show()
    local width = self.wrap_width
    local step_index = tonumber(model.step_index) or 0
    local step_count = math.max(1, tonumber(model.step_count) or 1)
    local progress_width = 20
    local filled = math.max(0, math.min(progress_width,
        math.floor((step_index - 1) / math.max(1, step_count - 1)
            * progress_width + 0.5)))
    local progress = string.rep('#', filled)
        .. string.rep('-', progress_width - filled)
    local lines = {
        ('EXPEDITION GUIDE  v%s  |  %s  |  %s'):format(
            display(model.version), display(model.mode), display(model.time)),
    }
    append_wrapped(lines, '', model.route, width)
    lines[#lines + 1] = ('[%s]  CURRENT STEP %s OF %s [%s]  |  %s  |  %s'):format(
        progress, display(model.step_index), display(model.step_count),
        display(model.step_id), display(model.area), display(model.state))
    lines[#lines + 1] = string.rep('-', math.min(width, 88))
    lines[#lines + 1] = 'DO THIS NOW'
    append_wrapped(lines, '  ', model.instruction, width)
    if model.navigation then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'WAYPOINT'
        append_wrapped(lines, '  ', model.navigation, width)
    end
    if model.timer and model.timer ~= '' then
        append_wrapped(lines, '  TIMER: ', model.timer, width)
    end
    if model.reward and model.reward ~= '' then
        append_wrapped(lines, '  ', model.reward, width)
    end
    if type(model.detail) == 'table' and #model.detail > 0 then
        lines[#lines + 1] = ''
        lines[#lines + 1] = 'STEP NOTES'
        for _, detail in ipairs(model.detail) do
            append_wrapped(lines, '  - ', detail, width)
        end
    end
    if model.warning and model.warning ~= '' then
        lines[#lines + 1] = ''
        append_wrapped(lines, 'WATCH: ', model.warning, width)
    end
    lines[#lines + 1] = ''
    append_wrapped(lines, 'COMBAT: ', model.combat, width)
    if model.observed and model.observed ~= '' then
        append_wrapped(lines, 'OBSERVED: ', model.observed, width)
    end
    if model.next_step and model.next_step ~= '' then
        append_wrapped(lines, 'UP NEXT: ', model.next_step, width)
    end
    lines[#lines + 1] = ('SENSORS %s/%s | PARTY %s/%s | DOLO LEADER %s/%s'):format(
        display(model.fresh), display(model.expected),
        display(model.party_exact), display(model.expected),
        display(model.leader_exact), display(model.leader_expected))
    lines[#lines + 1] = 'CONTROLS: //exg next | back | wp | explain | stop'
    lines[#lines + 1] = 'Manual play is always available. Alt-P stops combat immediately.'
    local value = table.concat(lines, '\n')
    if value ~= self.last then
        self.last = value
        self.object:text(value)
    end
end

return HUD
