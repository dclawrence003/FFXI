-- Pure, generic bounded-region validation and membership tests.  Invalid
-- definitions and invalid positions always fail closed.

local Region = {}

local COORDINATE_LIMIT = 10000
local MAX_ZONES = 64
local MAX_POINTS = 64
local MAX_REGIONS = 32
local EPSILON = 1e-9

local FIELDS = {
    z_band={kind=true, zones=true, min=true, max=true},
    aabb={kind=true, zones=true, min_x=true, max_x=true,
        min_y=true, max_y=true, min_z=true, max_z=true},
    cylinder={kind=true, zones=true, x=true, y=true, radius=true,
        min_z=true, max_z=true},
    polygon_prism={kind=true, zones=true, points=true,
        min_z=true, max_z=true},
}

local function finite(value)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
end

local function bounded(value)
    return finite(value) and math.abs(value) <= COORDINATE_LIMIT
end

local function validate_fields(definition, allowed)
    for key in pairs(definition) do
        if not allowed[key] then
            return false, 'unsupported region field ' .. tostring(key)
        end
    end
    return true
end

local function validate_zones(zones)
    if type(zones) ~= 'table' then
        return false, 'region zones must be a non-empty set'
    end
    local count = 0
    for zone, enabled in pairs(zones) do
        if type(zone) ~= 'number' or zone ~= math.floor(zone)
            or zone < 1 or zone > 1024 or enabled ~= true then
            return false, 'region zones contains an invalid entry'
        end
        count = count + 1
        if count > MAX_ZONES then
            return false, 'region zones exceeds the bounded limit'
        end
    end
    if count == 0 then return false, 'region zones cannot be empty' end
    return true
end

local function ordered_array(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function validate_range(low, high, label)
    if not bounded(low) or not bounded(high) or low >= high then
        return false, 'region ' .. label .. ' range is invalid'
    end
    return true
end

local function orientation(a, b, c)
    return (b.x - a.x) * (c.y - a.y)
        - (b.y - a.y) * (c.x - a.x)
end

local function between(value, low, high)
    return value >= math.min(low, high) - EPSILON
        and value <= math.max(low, high) + EPSILON
end

local function on_segment(point, a, b)
    return math.abs(orientation(a, b, point)) <= EPSILON
        and between(point.x, a.x, b.x)
        and between(point.y, a.y, b.y)
end

local function sign(value)
    if value > EPSILON then return 1 end
    if value < -EPSILON then return -1 end
    return 0
end

local function segments_intersect(a, b, c, d)
    local ab_c, ab_d = orientation(a, b, c), orientation(a, b, d)
    local cd_a, cd_b = orientation(c, d, a), orientation(c, d, b)
    if sign(ab_c) * sign(ab_d) < 0 and sign(cd_a) * sign(cd_b) < 0 then
        return true
    end
    return on_segment(c, a, b) or on_segment(d, a, b)
        or on_segment(a, c, d) or on_segment(b, c, d)
end

local function adjacent_edges(first, second, count)
    if first == second then return true end
    if math.abs(first - second) == 1 then return true end
    return (first == 1 and second == count)
        or (second == 1 and first == count)
end

local function validate_polygon(points)
    if not ordered_array(points) or #points < 3 or #points > MAX_POINTS then
        return false, 'polygon points must be an array of 3 to '
            .. tostring(MAX_POINTS) .. ' points'
    end
    local area = 0
    for index, point in ipairs(points) do
        if type(point) ~= 'table' then
            return false, 'polygon point is invalid'
        end
        for key in pairs(point) do
            if key ~= 'x' and key ~= 'y' then
                return false, 'polygon point has an unsupported field'
            end
        end
        if not bounded(point.x) or not bounded(point.y) then
            return false, 'polygon point is outside coordinate bounds'
        end
        local next_point = points[index % #points + 1]
        if type(next_point) ~= 'table' or point.x == next_point.x
            and point.y == next_point.y then
            return false, 'polygon contains a zero-length edge'
        end
        if bounded(next_point.x) and bounded(next_point.y) then
            area = area + point.x * next_point.y - next_point.x * point.y
        end
    end
    if math.abs(area) <= EPSILON then
        return false, 'polygon has no bounded area'
    end
    -- A self-intersecting polygon has ambiguous interior semantics.  Reject it
    -- at validation time instead of guessing during a safety decision.
    for first = 1, #points do
        local first_end = points[first % #points + 1]
        for second = first + 1, #points do
            if not adjacent_edges(first, second, #points) then
                local second_end = points[second % #points + 1]
                if segments_intersect(points[first], first_end,
                    points[second], second_end) then
                    return false, 'polygon is self-intersecting'
                end
            end
        end
    end
    return true
end

function Region.validate(definition)
    if type(definition) ~= 'table' or type(definition.kind) ~= 'string'
        or not FIELDS[definition.kind] then
        return false, 'unknown or missing region kind'
    end
    local valid, reason = validate_fields(definition, FIELDS[definition.kind])
    if not valid then return false, reason end
    valid, reason = validate_zones(definition.zones)
    if not valid then return false, reason end

    if definition.kind == 'z_band' then
        return validate_range(definition.min, definition.max, 'z')
    elseif definition.kind == 'aabb' then
        valid, reason = validate_range(definition.min_x,
            definition.max_x, 'x')
        if not valid then return false, reason end
        valid, reason = validate_range(definition.min_y,
            definition.max_y, 'y')
        if not valid then return false, reason end
        return validate_range(definition.min_z, definition.max_z, 'z')
    elseif definition.kind == 'cylinder' then
        if not bounded(definition.x) or not bounded(definition.y)
            or not finite(definition.radius) or definition.radius <= 0
            or definition.radius > COORDINATE_LIMIT
            or math.abs(definition.x) + definition.radius > COORDINATE_LIMIT
            or math.abs(definition.y) + definition.radius > COORDINATE_LIMIT then
            return false, 'cylinder footprint is invalid or out of bounds'
        end
        return validate_range(definition.min_z, definition.max_z, 'z')
    end
    valid, reason = validate_range(definition.min_z,
        definition.max_z, 'z')
    if not valid then return false, reason end
    return validate_polygon(definition.points)
end

local function copy_zones(zones)
    local result = {}
    for zone in pairs(zones) do result[zone] = true end
    return result
end

function Region.compile(definition)
    if type(definition) == 'table' and definition.kind == nil
        and definition.regions ~= nil then
        return Region.compile_scope(definition)
    end
    local valid, reason = Region.validate(definition)
    if not valid then return nil, reason end
    local result = {kind=definition.kind, zones=copy_zones(definition.zones)}
    for key, value in pairs(definition) do
        if key ~= 'kind' and key ~= 'zones' and key ~= 'points' then
            result[key] = value
        end
    end
    if definition.points then
        result.points = {}
        for index, point in ipairs(definition.points) do
            result.points[index] = {x=point.x, y=point.y}
        end
    end
    return result
end

local function valid_label(value)
    if type(value) ~= 'string' or #value < 1 or #value > 160
        or value:match('[%z\1-\31\127]') ~= nil
        or value:match('^%s') or value:match('%s$') then return false end
    local lower = value:lower()
    return lower:find('reward safe', 1, true) == nil
        and lower:find('freeze chest', 1, true) == nil
        and lower:find('stable 2/2', 1, true) == nil
end

local function same_zone_set(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then return false end
    local left_count, right_count = 0, 0
    for zone, enabled in pairs(left) do
        if enabled ~= true or right[zone] ~= true then return false end
        left_count = left_count + 1
    end
    for zone, enabled in pairs(right) do
        if enabled ~= true or left[zone] ~= true then return false end
        right_count = right_count + 1
    end
    return left_count == right_count
end

-- A reward scope is a labeled OR-of-regions. `zones` is accepted only as the
-- exact derived union emitted by compile_scope; callers cannot use it to
-- broaden or narrow any member region.
function Region.validate_scope(definition)
    if type(definition) ~= 'table' then
        return false, 'reward scope must be a table'
    end
    for key in pairs(definition) do
        if key ~= 'label' and key ~= 'regions' and key ~= 'zones' then
            return false, 'unsupported reward scope field ' .. tostring(key)
        end
    end
    if not valid_label(definition.label) then
        return false, 'reward scope label is invalid'
    end
    if not ordered_array(definition.regions) or #definition.regions < 1
        or #definition.regions > MAX_REGIONS then
        return false, 'reward scope requires 1 to '
            .. tostring(MAX_REGIONS) .. ' regions'
    end
    local union = {}
    for _, region in ipairs(definition.regions) do
        local valid, reason = Region.validate(region)
        if not valid then return false, reason end
        for zone in pairs(region.zones) do union[zone] = true end
    end
    if definition.zones ~= nil
        and not same_zone_set(definition.zones, union) then
        return false, 'reward scope zones do not match its region union'
    end
    return true
end

function Region.compile_scope(definition)
    local valid, reason = Region.validate_scope(definition)
    if not valid then return nil, reason end
    local result = {label=definition.label, regions={}, zones={}}
    for index, region in ipairs(definition.regions) do
        local compiled
        compiled, reason = Region.compile(region)
        if not compiled then return nil, reason end
        result.regions[index] = compiled
        for zone in pairs(compiled.zones) do result.zones[zone] = true end
    end
    return result
end

local function valid_position(position)
    return type(position) == 'table'
        and type(position.zone) == 'number'
        and position.zone == math.floor(position.zone)
        and position.zone >= 1 and position.zone <= 1024
        and bounded(position.x) and bounded(position.y) and bounded(position.z)
end

local function polygon_contains(points, position)
    local inside = false
    local previous = points[#points]
    for _, current in ipairs(points) do
        if on_segment(position, previous, current) then return true end
        if (current.y > position.y) ~= (previous.y > position.y) then
            local crossing = (previous.x - current.x)
                * (position.y - current.y) / (previous.y - current.y)
                + current.x
            if position.x < crossing then inside = not inside end
        end
        previous = current
    end
    return inside
end

function Region.contains(definition, position)
    local valid, reason = Region.validate(definition)
    if not valid then return false, reason end
    if not valid_position(position) then return false, 'invalid position' end
    if definition.zones[position.zone] ~= true then
        return false, 'position zone is outside region'
    end
    if definition.kind == 'z_band' then
        return position.z >= definition.min and position.z <= definition.max
    elseif definition.kind == 'aabb' then
        return position.x >= definition.min_x
            and position.x <= definition.max_x
            and position.y >= definition.min_y
            and position.y <= definition.max_y
            and position.z >= definition.min_z
            and position.z <= definition.max_z
    elseif definition.kind == 'cylinder' then
        local dx, dy = position.x - definition.x,
            position.y - definition.y
        return dx * dx + dy * dy <= definition.radius * definition.radius
            and position.z >= definition.min_z
            and position.z <= definition.max_z
    end
    return position.z >= definition.min_z
        and position.z <= definition.max_z
        and polygon_contains(definition.points, position)
end

function Region.contains_scope(scope, position)
    local compiled, reason = Region.compile_scope(scope)
    if not compiled then return false, reason end
    if not valid_position(position) then return false, 'invalid position' end
    if compiled.zones[position.zone] ~= true then
        return false, 'position zone is outside reward scope'
    end
    for _, region in ipairs(compiled.regions) do
        if Region.contains(region, position) == true then return true end
    end
    return false, 'position is outside every reward region'
end

Region.in_scope = Region.contains
Region.in_reward_scope = Region.contains_scope
Region.COORDINATE_LIMIT = COORDINATE_LIMIT

return Region
