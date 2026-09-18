local root = 'addons/THHUD/'
package.path = root .. '?.lua;' .. package.path

local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then
        error(('FAILED: %s\n%s'):format(name, tostring(err)), 0)
    end
    passed = passed + 1
    print('ok - ' .. name)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message or 'value mismatch',
            tostring(expected), tostring(actual)), 2)
    end
end

local State = require('thhud_state')
local Actions = require('thhud_actions')
local Calculator = require('thhud_calculator')
local Protocol = require('thhud_protocol')

test('target switching preserves per-server-ID state and duplicate names', function()
    local state = State.new(100)
    state:apply_inferred(1001, 'AAA00001-0001-00000001-10', 3)
    state:apply_inferred(1002, 'AAA00002-0002-00000001-10', 7)
    equal(state:get(1001).value, 3, 'first duplicate-name mob')
    equal(state:get(1002).value, 7, 'second duplicate-name mob')
    equal(state:get(1001).value, 3, 'returning to first target')
end)

test('initial inferred application, higher peer, and lower peer', function()
    local state = State.new(100)
    local signature = 'AAA00001-0001-00000001-10'
    local changed = state:apply_inferred(1001, signature, 3,
        {sender = 'Dolomedes'})
    equal(changed, true, 'initial application')
    changed = state:apply_inferred(1001, signature, 6,
        {sender = 'Tackleberry'})
    equal(changed, true, 'higher other box')
    changed = state:apply_inferred(1001, signature, 2,
        {sender = 'Smalls'})
    equal(changed, false, 'lower other box')
    equal(state:get(1001).value, 6, 'highest value retained')
end)

test('authoritative 603 and 608 action messages override inference', function()
    local state = State.new(100)
    local signature = 'AAA00001-0001-00000001-10'
    state:apply_inferred(1001, signature, 8)
    local add_effect = Actions.inspect({actor_id = 50, category = 1,
        targets = {{id = 1001, actions = {{message = 1,
            add_effect_message = 603, add_effect_param = 9}}}}}, 50, 8)
    equal(#add_effect, 1, '603 event count')
    state:apply_confirmed(1001, signature, add_effect[1].value)
    equal(state:get(1001).value, 9, '603 value')
    equal(state:get(1001).confidence, 'confirmed', '603 confidence')

    local bounty = Actions.inspect({actor_id = 60, category = 3,
        targets = {{id = 1001, actions = {{message = 608, param = 10}}}}},
        50, nil)
    equal(#bounty, 1, '608 event count')
    state:apply_confirmed(1001, signature, bounty[1].value)
    equal(state:get(1001).value, 10, '608 value')
end)

test('multi-target and multi-result packets retain each target and highest proc', function()
    local events = Actions.inspect({actor_id = 50, category = 1,
        targets = {
            {id = 1001, actions = {
                {message = 1, add_effect_message = 603,
                    add_effect_param = 5},
                {message = 1, add_effect_message = 603,
                    add_effect_param = 6},
            }},
            {id = 1002, actions = {{message = 1}}},
        }}, 50, 3)
    equal(#events, 2, 'one observation per target')
    local by_id = {}
    for _, event in ipairs(events) do by_id[event.mob_id] = event end
    equal(by_id[1001].kind, 'confirmed', 'confirmed target')
    equal(by_id[1001].value, 6, 'highest proc in action list')
    equal(by_id[1002].kind, 'inferred', 'second target inferred')
    equal(by_id[1002].value, 3, 'second target value')
end)

test('confirmed packet corrects an overestimated inference', function()
    local state = State.new(100)
    local signature = 'AAA00001-0001-00000001-10'
    state:apply_inferred(1001, signature, 8)
    state:apply_confirmed(1001, signature, 6)
    equal(state:get(1001).value, 6, 'authoritative correction')
    equal(state:get(1001).confidence, 'confirmed', 'authoritative color')
end)

test('death, reset, despawn, zone, and recycled identity clear safely', function()
    local state = State.new(100)
    local sig1 = 'AAA00001-0001-00000001-10'
    local sig2 = 'AAA00001-0001-00000002-10'
    state:apply_inferred(1001, sig1, 4)
    local death = Actions.inspect({actor_id = 50, category = 1,
        targets = {{id = 1001, actions = {{message = 20}}}}}, 50, 4)
    equal(death[#death].kind, 'clear', 'death transition')
    state:clear(death[#death].mob_id)
    equal(state:get(1001), nil, 'death clear')

    state:apply_inferred(1001, sig1, 4)
    state:clear(1001, sig1) -- reset/passive regeneration
    equal(state:get(1001), nil, 'reset clear')
    state:apply_inferred(1001, sig1, 4)
    state:clear(1001, sig1) -- despawn packet
    equal(state:get(1001), nil, 'despawn clear')

    state:apply_inferred(1001, sig1, 4)
    state:apply_inferred(1001, sig2, 2)
    equal(state:get(1001, sig1), nil, 'recycled ID rejects old signature')
    equal(state:get(1001, sig2).value, 2, 'recycled ID starts fresh')
    state:set_zone(101)
    equal(state:get(1001), nil, 'zone clear')
end)

test('addon reload begins unknown and can recover from peer snapshot', function()
    local before = State.new(100)
    local signature = 'AAA00001-0001-00000001-10'
    before:apply_inferred(1001, signature, 5)
    local snapshot = before:snapshot()
    local reloaded = State.new(100)
    equal(reloaded:get(1001), nil, 'reload is initially honest/unknown')
    reloaded:apply_inferred(snapshot[1].mob_id, snapshot[1].signature,
        snapshot[1].value, {source = 'ipc reload sync'})
    equal(reloaded:get(1001).value, 5, 'peer reload recovery')
end)

test('job-agnostic calculator handles THF subjob and random TH gear', function()
    local resources = {
        items = {[1] = {en = 'Random Hat'}, [2] = {en = 'Augmented Boots'}},
        item_descriptions = {[1] = {en = 'DEF:1 "Treasure Hunter"+1'}},
    }
    local extdata = {decode = function(item)
        return item.id == 2 and {augments = {'"Treasure Hunter"+2'}}
            or {augments = {}}
    end}
    local value, details = Calculator.calculate({main_job = 'DNC',
        main_job_level = 99, sub_job = 'THF', sub_job_level = 49},
        {{id = 1}, {id = 2}}, resources, extdata, {})
    equal(details.trait, 2, '/THF trait')
    equal(details.gear_total, 3, 'static plus augment gear')
    equal(value, 4, 'non-THF application cap')
    local gear_only = Calculator.calculate({main_job = 'WHM',
        main_job_level = 99, sub_job = 'SCH', sub_job_level = 56},
        {{id = 1}}, resources, extdata, {})
    equal(gear_only, 1, 'random TH gear works without THF or BLU')
end)

test('THF main cap, Treasure Hound, and non-stat effect text', function()
    local resources = {items = {}, item_descriptions = {
        [1] = {en = '"Treasure Hunter"+5'},
        [2] = {en = '"Treasure Hunter" effect +5%'},
    }}
    equal(Calculator.text_value(resources.item_descriptions[2].en), 0,
        'effect percentage is not TH levels')
    local value = Calculator.calculate({main_job = 'THF', main_job_level = 99},
        {{id = 1}}, resources, {decode = function() return {} end},
        {treasure_hound = true})
    equal(value, 9, 'THF base 8 plus Treasure Hound')
end)

test('BLU trait requires its full three-spell set and is never a job gate', function()
    local value, details = Calculator.calculate({main_job = 'BLU',
        main_job_level = 99, job_points = {blu = {jp_spent = 1200}}}, {},
        {items = {}, item_descriptions = {}}, nil,
        {blue_data = {spells = {680, 683, 697}}})
    equal(details.blue_trait, 3, 'BLU gift-raised trait')
    equal(value, 3, 'BLU trait application')
    local two_spells, two_details = Calculator.calculate({main_job = 'BLU',
        main_job_level = 99}, {}, {items = {}, item_descriptions = {}}, nil,
        {blue_data = {spells = {680, 683}}})
    equal(two_details.blue_trait, 0, 'two spells grant Gilfinder, not TH')
    equal(two_spells, 0, 'two-spell set applies no TH')
    local no_th = Calculator.calculate({main_job = 'WAR', main_job_level = 99},
        {}, {items = {}, item_descriptions = {}}, nil, {})
    equal(no_th, 0, 'arbitrary job with no TH applies none')
end)

test('IPC accepts current peers and rejects stale/wrong-zone payloads', function()
    local message = Protocol.observe('Dolomedes', 100, 1000, 1001,
        'AAA00001-0001-00000001-10', 7, 'inferred')
    local context = {zone = 100, now = 1004, max_age = 8,
        allowed_sender = function(name) return name == 'Dolomedes' end}
    local payload = Protocol.validate(message, context)
    equal(payload.value, 7, 'valid payload')
    context.now = 1010
    local stale = Protocol.validate(message, context)
    equal(stale, nil, 'stale payload')
    context.now, context.zone = 1004, 101
    local wrong_zone = Protocol.validate(message, context)
    equal(wrong_zone, nil, 'wrong-zone payload')
    context.zone = 100
    local impossible = Protocol.observe('Dolomedes', 100, 1000, 1001,
        'AAA00001-0001-00000001-10', 15, 'confirmed')
    equal(Protocol.validate(impossible, context), nil,
        'impossible value above retail TH14')
end)

print(('THHUD packet/state harness: %d tests passed'):format(passed))
