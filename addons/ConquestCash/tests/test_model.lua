local Model = dofile('addons/ConquestCash/lib/model.lua')

local function equal(actual, expected, label)
    assert(actual == expected, ('%s: expected %s, got %s'):format(
        label, tostring(expected), tostring(actual)))
end

for _, case in ipairs({
    {0, '0'},
    {999, '999'},
    {1000, '1K'},
    {1499, '1K'},
    {1500, '2K'},
    {63990, '64K'},
    {100000, '100K'},
    {999499, '999K'},
    {999500, '1M'},
    {1000000, '1M'},
    {1050000, '1.1M'},
    {1140000, '1.1M'},
    {12952968, '13M'},
    {999999999, '1B'},
}) do
    equal(Model.compact_amount(case[1]), case[2],
        'compact amount ' .. tostring(case[1]))
end

equal(Model.purchase_count({
    cp = 18000,
    floor = 10000,
    cost = 4000,
    free_slots = 80,
}), 2, 'floor-limited purchase count')

equal(Model.purchase_count({
    cp = 13999,
    floor = 10000,
    cost = 4000,
    free_slots = 80,
}), 0, 'floor cannot be crossed')

equal(Model.purchase_count({
    cp = 999999,
    floor = 0,
    cost = 4000,
    free_slots = 3,
}), 3, 'inventory-limited purchase count')

equal(Model.purchase_count({
    cp = 999999,
    floor = 0,
    cost = 4000,
    free_slots = 80,
    gil = 999994999,
    gil_cap = 999999999,
    estimated_sale = 5000,
}), 1, 'gil-headroom-limited purchase count')

equal(Model.purchase_count({
    cp = 999999,
    floor = 0,
    cost = 4000,
    free_slots = 80,
    gil = 999995000,
    gil_cap = 999999999,
    estimated_sale = 5000,
}), 0, 'gil cap cannot be crossed')

local items = {
    inventory = {
        max = 5,
        count = 3,
        [1] = {id = 16844, count = 1, status = 0},
        [2] = {id = 123, count = 2, status = 0},
        [5] = {id = 16844, count = 1, status = 5},
    },
}
equal(Model.free_inventory_slots(items), 2, 'free inventory')
local slots = Model.item_slots(items, 16844)
equal(Model.table_count(slots), 2, 'target item slot count')
equal(slots[1].status, 0, 'slot status retained')

local after = Model.item_slots({inventory = {
    max = 5, count = 4,
    [1] = {id = 16844, count = 1, status = 0},
    [3] = {id = 16844, count = 1, status = 0},
    [5] = {id = 16844, count = 1, status = 5},
}}, 16844)
local additions = Model.new_item_slots(slots, after)
equal(Model.table_count(additions), 1, 'new target slot count')
assert(additions[3], 'new target slot was not identified')

local guard = {x = -247.201, y = 40.939}
local vendor = {x = -218.375, y = 60.595}
assert(Model.point_segment_distance(guard, guard, vendor) < 0.001)
assert(Model.point_segment_distance({x = -232, y = 51}, guard, vendor) < 1)
assert(Model.point_segment_distance({x = -200, y = 100}, guard, vendor) > 20)

print('ConquestCash model tests passed.')
