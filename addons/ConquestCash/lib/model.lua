-- Pure calculations shared by the Windower runtime and isolated tests.

local Model = {}

local function finite_number(value)
    value = tonumber(value)
    if not value or value ~= value
            or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

function Model.nonnegative_integer(value)
    value = finite_number(value)
    if not value or value < 0 then return nil end
    return math.floor(value)
end

local function compact_scaled(value, divisor, suffix)
    local rounded_tenths = math.floor(value / divisor * 10 + 0.5)
    if rounded_tenths % 10 == 0 then
        return tostring(math.floor(rounded_tenths / 10)) .. suffix
    end
    return ('%d.%d%s'):format(math.floor(rounded_tenths / 10),
        rounded_tenths % 10, suffix)
end

-- Compact HUD-only formatting. Thousands round to a whole K; millions and
-- billions retain at most one useful decimal and suppress a trailing .0.
function Model.compact_amount(value)
    value = Model.nonnegative_integer(value)
    if value == nil then return nil end
    if value >= 999950000 then
        return compact_scaled(value, 1000000000, 'B')
    elseif value >= 999500 then
        return compact_scaled(value, 1000000, 'M')
    elseif value >= 1000 then
        return tostring(math.floor(value / 1000 + 0.5)) .. 'K'
    end
    return tostring(value)
end

function Model.distance(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then return nil end
    local lx, ly = finite_number(left.x), finite_number(left.y)
    local rx, ry = finite_number(right.x), finite_number(right.y)
    if not lx or not ly or not rx or not ry then return nil end
    local dx, dy = rx - lx, ry - ly
    return math.sqrt(dx * dx + dy * dy)
end

function Model.point_segment_distance(point, first, second)
    if type(point) ~= 'table' or type(first) ~= 'table'
            or type(second) ~= 'table' then
        return nil
    end
    local px, py = finite_number(point.x), finite_number(point.y)
    local ax, ay = finite_number(first.x), finite_number(first.y)
    local bx, by = finite_number(second.x), finite_number(second.y)
    if not px or not py or not ax or not ay or not bx or not by then
        return nil
    end

    local abx, aby = bx - ax, by - ay
    local denominator = abx * abx + aby * aby
    if denominator <= 0.000001 then
        return Model.distance(point, first)
    end

    local projection = ((px - ax) * abx + (py - ay) * aby) / denominator
    if projection < 0 then projection = 0 end
    if projection > 1 then projection = 1 end
    local closest = {x = ax + projection * abx, y = ay + projection * aby}
    return Model.distance(point, closest)
end

function Model.free_inventory_slots(items)
    local inventory = items and items.inventory
    local maximum = inventory and Model.nonnegative_integer(inventory.max)
    local count = inventory and Model.nonnegative_integer(inventory.count)
    if not maximum or not count or count > maximum then return nil end
    return maximum - count
end

-- Returns the maximum number of non-stackable rewards that can safely be
-- purchased. Every limit is applied independently so the result cannot cross
-- the configured CP floor or the gil cap after the rewards are sold.
function Model.purchase_count(arguments)
    arguments = arguments or {}
    local cp = Model.nonnegative_integer(arguments.cp)
    local floor = Model.nonnegative_integer(arguments.floor)
    local cost = Model.nonnegative_integer(arguments.cost)
    local free = Model.nonnegative_integer(arguments.free_slots)
    if not cp or not floor or not cost or cost == 0 or not free then
        return 0
    end

    local spendable = cp - floor
    if spendable < cost then return 0 end
    local result = math.min(free, math.floor(spendable / cost))

    local gil = Model.nonnegative_integer(arguments.gil)
    local gil_cap = Model.nonnegative_integer(arguments.gil_cap)
    local estimated_sale = Model.nonnegative_integer(arguments.estimated_sale)
    if gil and gil_cap and estimated_sale and estimated_sale > 0 then
        local headroom = gil_cap - gil
        if headroom < estimated_sale then return 0 end
        result = math.min(result, math.floor(headroom / estimated_sale))
    end

    return math.max(0, result)
end

function Model.item_slots(items, item_id)
    local slots = {}
    item_id = tonumber(item_id)
    local inventory = items and items.inventory
    local maximum = inventory and Model.nonnegative_integer(inventory.max) or 80
    if not item_id or type(inventory) ~= 'table' then return slots end

    for index = 1, maximum do
        local item = inventory[index]
        if type(item) == 'table' and tonumber(item.id) == item_id
                and (tonumber(item.count) or 0) > 0 then
            slots[index] = {
                id = tonumber(item.id),
                count = tonumber(item.count),
                status = tonumber(item.status),
            }
        end
    end
    return slots
end

function Model.new_item_slots(before, after)
    local result = {}
    before = before or {}
    after = after or {}
    for index, item in pairs(after) do
        if not before[index] then
            result[index] = item
        end
    end
    return result
end

function Model.table_count(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

function Model.sorted_numeric_keys(values)
    local result = {}
    for key in pairs(values or {}) do
        if tonumber(key) then result[#result + 1] = tonumber(key) end
    end
    table.sort(result)
    return result
end

return Model
