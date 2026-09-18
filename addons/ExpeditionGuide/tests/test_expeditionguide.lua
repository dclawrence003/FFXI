-- Isolated regression suite for ExpeditionGuide's pure modules and content.
-- This deliberately does not load Windower or any other addon.

package.path = table.concat({
    'addons/ExpeditionGuide/?.lua',
    'addons/ExpeditionGuide/?/init.lua',
    package.path,
}, ';')

local Schema = require('lib.schema')
local Engine = require('lib.route_engine')
local Navigation = require('lib.navigation')
local Protocol = require('lib.protocol')
local PartyState = require('lib.party_state')
local Bridge = require('lib.profile_bridge')
local AutomationBridge = require('lib.automation_bridge')
local Store = require('lib.state_store')
local Loader = require('lib.content_loader')
local Sensors = require('lib.sensors')
local Sandbox = require('lib.sandbox')
local Fingerprint = require('lib.fingerprint')
local StateValidation = require('lib.state_validation')
local RunSession = require('lib.run_session')
local Region = require('lib.region')
local RewardSafety = require('lib.reward_safety')
local HUD = require('lib.hud')

local total = 0
local passed = 0
local failures = {}

local function fail(message)
    error(message or 'assertion failed', 2)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(('%s (expected %s, got %s)'):format(
            message or 'values differ', tostring(expected), tostring(actual)))
    end
end

local function truthy(value, message)
    if not value then fail(message or 'expected truthy value') end
end

local function falsy(value, message)
    if value then fail(message or 'expected falsy value') end
end

local function near(actual, expected, epsilon, message)
    epsilon = epsilon or 0.000001
    if type(actual) ~= 'number' or math.abs(actual - expected) > epsilon then
        fail(('%s (expected %.8f, got %s)'):format(
            message or 'numbers differ', expected, tostring(actual)))
    end
end

local function contains(value, needle, message)
    if not tostring(value):find(tostring(needle), 1, true) then
        fail(('%s (missing %q in %q)'):format(
            message or 'substring absent', tostring(needle), tostring(value)))
    end
end

local function test(name, body)
    total = total + 1
    local ok, reason = pcall(body)
    if ok then
        passed = passed + 1
        print(('PASS %02d - %s'):format(total, name))
    else
        failures[#failures + 1] = {name=name, reason=tostring(reason)}
        print(('FAIL %02d - %s'):format(total, name))
        print('  ' .. tostring(reason))
    end
end

local function basic_route(version)
    return {
        schema=1, id='test-route', version=version or '1.0.0',
        title='Test route', content='test', allowed_zones={[1]=true},
        guide_only=true,
        steps={
            {id='manual', area='A', instruction='Advance manually.',
                completion={kind='manual'}},
            {id='quorum', area='B', instruction='Wait for sensors.',
                completion={kind='sensor_quorum', auto=true}},
            {id='item', area='C', instruction='Wait for an item.',
                completion={kind='all_temp_item', item='key_a', auto=true}},
        },
    }
end

local function run_evidence(run_id, items)
    return {run_quorum=true,run_id=run_id,all_items=items or {}}
end

local function make_catalog(entries)
    local ordered, by_key, by_id = {}, {}, {}
    for index, source in ipairs(entries or {}) do
        local item = {
            key=source.key or ('item_' .. index),
            id=source.id or index,
            name=source.name or source.key or ('Item ' .. index),
            protocol_index=index,
        }
        ordered[index], by_key[item.key], by_id[item.id] = item, item, item
    end
    return {ordered=ordered, by_key=by_key, by_id=by_id}
end

local function fixture_pack(fields)
    fields = fields or {}
    fields.id = fields.id or 'test'
    fields.allowed_zones = fields.allowed_zones or {[1]=true}
    fields.instance_zones = fields.instance_zones or {[1]=true}
    fields.run_seconds = fields.run_seconds or 3600
    fields.stale_run_seconds = fields.stale_run_seconds or 7200
    fields.catalog_revision = fields.catalog_revision or 1
    fields.items = fields.items or 'items'
    fields.key_items = fields.key_items or 'key_items'
    fields.landmarks = fields.landmarks or 'landmarks'
    return fields
end

local function reward_scope(zones)
    return {
        label='Fixture reward floor',
        regions={{kind='z_band', zones=zones or {[1]=true},
            min=-240, max=-110}},
    }
end

local function clone(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[clone(key, seen)] = clone(child, seen)
    end
    return result
end

test('route engine starts inert and advances deterministically', function()
    local engine = Engine.new(basic_route(), nil, 100)
    equal(engine.state.active, false, 'new engine must be inert')
    equal(engine:current().id, 'manual')
    local ok, reason = engine:advance('too early', 'manual', 101)
    falsy(ok); contains(reason, 'not active')
    truthy(engine:bind_run('test-run', run_evidence('test-run'), 89))
    truthy(engine:start(102, 90))
    equal(engine.state.run_started_at, 90)
    truthy(engine:advance('operator', 'manual', 103))
    equal(engine:current().id, 'quorum')
    equal(engine.state.completed.manual.resolution, 'operator')
    equal(#engine.state.history, 1)
    equal(engine.state.waypoint_index, 1)
end)

test('route engine pause, observe, auto-complete, back, and skip gates', function()
    local engine = Engine.new(basic_route(), nil, 100)
    engine:start(100)
    engine:advance('operator', 'manual', 101)
    truthy(engine:set_paused(true, 102))
    local ok, reason = engine:observe({sensor_quorum=true}, 103)
    falsy(ok); equal(reason, 'inactive')
    equal(engine:current().id, 'quorum')
    truthy(engine:set_paused(false, 104))
    ok = engine:observe({sensor_quorum=false}, 105)
    falsy(ok)
    truthy(engine:observe({sensor_quorum=true}, 106))
    equal(engine:current().id, 'item')
    equal(engine.state.completed.quorum.confidence, 'confirmed')
    truthy(engine:back(107))
    equal(engine:current().id, 'quorum')
    falsy(engine.state.completed.quorum)
    truthy(engine:skip(108))
    equal(engine:current().id, 'item')
    truthy(engine:observe({all_items={key_a=true}}, 109))
    truthy(engine.state.complete)
    equal(engine.state.current_index, 3, 'completed route stays on final step')
    ok, reason = engine:advance('again', 'manual', 110)
    falsy(ok); contains(reason, 'complete')
end)

test('manual completion evidence is observed but never auto-advances', function()
    local route = basic_route()
    route.steps[1].completion = {kind='landmark', landmark='device_start'}
    local engine = Engine.new(route, nil, 200)
    engine:start(200)
    local ok, reason = engine:observe({landmark='device_start'}, 201)
    truthy(ok); equal(reason, 'observed')
    equal(engine:current().id, 'manual')
    equal(engine.state.observed.kind, 'landmark')
end)

test('interaction evidence is exact and run start rejects bad input', function()
    local route = basic_route()
    route.steps[1].completion = {kind='interaction', menu_id=1001, auto=true}
    local engine = Engine.new(route, nil, 200)
    engine:start(200)
    falsy(engine:set_run_started_at('not-a-time'))
    falsy(engine:observe({menu_id=1002}, 201))
    truthy(engine:observe({menu_id=1001}, 202))
    equal(engine:current().id, 'quorum')
end)

test('target interaction evidence advances only its exact declared landmark', function()
    local route = basic_route()
    route.steps[1].completion = {
        kind='target_interaction', landmark='gate_b1', auto=true,
    }
    local engine = Engine.new(route, nil, 210)
    engine:start(210)
    falsy(engine:observe({interaction_landmark='gate_b2'}, 211))
    equal(engine:current().id, 'manual')
    truthy(engine:observe({interaction_landmark='gate_b1'}, 212))
    equal(engine:current().id, 'quorum')
end)

test('warp steps advance only after a confirmed large relocation', function()
    local route = basic_route()
    route.steps[1].completion = {kind='relocation',auto=true}
    local engine = Engine.new(route,nil,215)
    engine:start(215)
    falsy(engine:observe({interaction_landmark='gadget_c'},216))
    equal(engine:current().id,'manual')
    truthy(engine:observe({relocation=true},217))
    equal(engine:current().id,'quorum')
end)

test('all-client key-item evidence uses the same fail-closed route gate', function()
    local route = basic_route()
    route.steps[1].completion = {
        kind='all_key_item', item='shiny_plate', auto=true,
    }
    local engine = Engine.new(route, nil, 220)
    engine:start(220)
    falsy(engine:observe({all_key_items={shiny_plate=false}}, 221))
    equal(engine:current().id, 'manual')
    truthy(engine:observe({all_key_items={shiny_plate=true}}, 222))
    equal(engine:current().id, 'quorum')
end)

test('all-client multi-item evidence requires every listed unlock', function()
    local route = basic_route()
    route.steps[1].completion = {
        kind='all_temp_items', items={'key_a','plate_a','sheet_a'}, auto=true,
    }
    local engine = Engine.new(route, nil, 230)
    engine:start(230)
    falsy(engine:observe({all_items={
        key_a=true, plate_a=true, sheet_a=false,
    }}, 231))
    equal(engine:current().id, 'manual')
    truthy(engine:observe({all_items={
        key_a=true, plate_a=true, sheet_a=true,
    }}, 232))
    equal(engine:current().id, 'quorum')
end)

test('route restoration requires exact id and version', function()
    local route = basic_route('2.3.4')
    local engine = Engine.new(route, nil, 300)
    engine:start(300)
    engine:advance('done', 'manual', 301)
    engine:set_waypoint_index(4)
    local saved = engine:snapshot(302)
    local restored = Engine.new(route, saved, 303)
    equal(restored.state.current_index, 2)
    equal(restored.state.waypoint_index, 4)
    equal(restored.state.last_seen_at, 303)
    local changed = Engine.new(basic_route('2.3.5'), saved, 304)
    equal(changed.state.current_index, 1)
    falsy(changed.state.active)
    local other = basic_route('2.3.4'); other.id = 'other-route'
    local wrong_id = Engine.new(other, saved, 305)
    equal(wrong_id.state.current_index, 1)
end)

test('route fingerprint changes refuse restore despite an unchanged id and version', function()
    local original = basic_route('4.5.6')
    local original_digest = Fingerprint.value(original)
    local engine = Engine.new(original, nil, 310, original_digest)
    engine:start(310)
    engine:advance('completed first step', 'manual', 311)
    local saved = engine:snapshot(312)
    equal(saved.route_digest, original_digest)

    local exact = Engine.new(original, saved, 313, original_digest)
    equal(exact.state.current_index, 2)
    truthy(exact.state.active)

    local changed = basic_route('4.5.6')
    changed.steps[1].instruction = 'Semantics changed without a version bump.'
    local changed_digest = Fingerprint.value(changed)
    truthy(changed_digest ~= original_digest)
    local refused = Engine.new(changed, saved, 314, changed_digest)
    equal(refused.state.current_index, 1)
    falsy(refused.state.active)
    equal(refused.state.route_id, original.id)
    equal(refused.state.route_version, original.version)
    equal(refused.state.route_digest, changed_digest)
end)

test('completion readiness restores only when bound to the current step', function()
    local route = basic_route()
    route.steps[1].completion = {
        kind='landmark', landmark='device_start', auto=false,
    }
    local engine = Engine.new(route, nil, 320)
    truthy(engine:bind_run('test-run', run_evidence('test-run'), 319))
    engine:start(320)
    falsy(engine:can_advance(), 'unobserved non-manual step must stay gated')
    truthy(engine:observe({landmark='device_start'}, 321))
    equal(engine.state.completion_ready_for, 'manual')
    truthy(engine:can_advance())

    local saved = engine:snapshot(322)
    local restored = Engine.new(route, saved, 323)
    equal(restored.state.completion_ready_for, 'manual')
    truthy(restored:can_advance())

    local stale_binding = {}
    for key, value in pairs(saved) do stale_binding[key] = value end
    stale_binding.completion_ready_for = 'quorum'
    local rejected = Engine.new(route, stale_binding, 324)
    falsy(rejected.state.completion_ready_for)
    falsy(rejected:can_advance())

    local wrong_step = {}
    for key, value in pairs(saved) do wrong_step[key] = value end
    wrong_step.current_index = 2
    wrong_step.completion_ready_for = 'manual'
    local rebound = Engine.new(route, wrong_step, 325)
    falsy(rebound.state.completion_ready_for)
end)

test('back from a completed route reopens its final step exactly once', function()
    local engine = Engine.new(basic_route(), nil, 330)
    engine:start(330)
    engine:advance('first', 'manual', 331)
    engine:advance('second', 'manual', 332)
    engine:advance('third', 'manual', 333)
    truthy(engine.state.complete)
    equal(engine.state.current_index, 3)
    truthy(engine.state.completed.item)
    truthy(engine:back(334))
    falsy(engine.state.complete)
    equal(engine.state.current_index, 3,
        'back from complete must reopen, not skip over, the final step')
    falsy(engine.state.completed.item)
    falsy(engine.state.completion_ready_for)
    falsy(engine:can_advance(), 'reopened evidence step must be observed again')
    truthy(engine:observe({all_items={key_a=true}}, 335))
    truthy(engine.state.complete)
    equal(engine.state.current_index, 3)
end)

test('route timers start, count down, restore, clear, and expire safely', function()
    local engine = Engine.new(basic_route(), nil, 340)
    truthy(engine:bind_run('test-run', run_evidence('test-run'), 339))
    engine:start(340)
    local ok, reason = engine:start_timer('', 120, 340)
    falsy(ok); contains(reason, 'key')
    ok, reason = engine:start_timer('gate', 0, 340)
    falsy(ok); contains(reason, 'duration')
    truthy(engine:start_timer('gate', 120, 340))
    local timer = engine:timer('gate')
    equal(timer.started_at, 340); equal(timer.deadline_at, 460)
    equal(timer.duration, 120); equal(timer.step_id, 'manual')
    equal(engine:timer_remaining('gate', 340), 120)
    equal(engine:timer_remaining('gate', 410), 50)
    equal(engine:timer_remaining('gate', 999), 0)
    falsy(engine:timer_remaining('missing', 350))

    local restored = Engine.new(basic_route(), engine:snapshot(350), 351)
    equal(restored:timer_remaining('gate', 400), 60)
    truthy(restored:clear_timer('gate'))
    falsy(restored:timer('gate')); falsy(restored:clear_timer('gate'))

    truthy(engine:advance('done', 'manual', 352))
    falsy(engine:timer('gate'), 'step advance must clear step-local timers')
    truthy(engine:start_timer('second', 10, 353))
    truthy(engine:back(354))
    falsy(engine:timer('second'), 'back must clear stale step-local timers')
    truthy(engine:start_timer('reset', 10, 355))
    truthy(engine:reset(356))
    falsy(engine:timer('reset')); equal(next(engine.state.timers), nil)
end)

test('route reset discards progress without mutating route data', function()
    local route = basic_route()
    local engine = Engine.new(route, nil, 1)
    engine:start(2); engine:advance('done', 'manual', 3)
    truthy(engine:reset(4))
    equal(engine.state.current_index, 1)
    equal(engine.state.active, false)
    equal(#engine.state.history, 0)
    equal(route.steps[1].id, 'manual')
end)

local function transaction_route()
    return {
        schema=1,id='transaction-route',version='1.0.0',title='Transactions',
        content='test',allowed_zones={[275]=true},guide_only=true,
        run_transactions={
            {id='b-key',rewind='b_start',
                goal={kind='all_temp_item',item='key_b'}},
            {id='b-sheet',rewind='b_start',
                goal={kind='all_temp_item',item='sheet_b'}},
            {id='c-sheet',rewind='c_kill',
                goal={kind='all_temp_item',item='sheet_c'}},
            {id='d-sheet',rewind='d_clear',
                goal={kind='all_temp_item',item='sheet_d'}},
        },
        steps={
            {id='entry',area='E',instruction='Entry.',completion={kind='manual'}},
            {id='b_start',area='B',instruction='Start B.',completion={kind='manual'}},
            {id='b_key',area='B',instruction='Get B key.',
                completion={kind='all_temp_item',item='key_b',auto=true}},
            {id='b_sheet',area='B',instruction='Get B sheet.',
                completion={kind='all_temp_item',item='sheet_b',auto=true}},
            {id='c_kill',area='C',instruction='Current-run kill.',completion={kind='manual'}},
            {id='c_plate',area='C',instruction='Plate proof.',
                completion={kind='all_temp_item',item='plate_c',auto=true}},
            {id='c_sheet',area='C',instruction='Get C sheet.',
                completion={kind='all_temp_item',item='sheet_c',auto=true}},
            {id='d_clear',area='D',instruction='Current-run clear.',completion={kind='manual'}},
            {id='d_sheet',area='D',instruction='Get D sheet.',
                completion={kind='all_temp_item',item='sheet_d',auto=true}},
            {id='done',area='F',instruction='Done.',completion={kind='manual'}},
        },
    }
end

local function bound_transaction_engine(index, complete)
    local engine = Engine.new(transaction_route(), nil, 6000)
    engine:start(6000)
    truthy(engine:bind_run('old-run', run_evidence('old-run', {
        key_b=true,sheet_b=true,sheet_c=true,sheet_d=true,
    }), 6001))
    engine.state.current_index = index
    engine.state.complete = complete == true
    return engine
end

test('new run binding clears ephemeral artifacts and rewinds earliest missing goal', function()
    local engine = bound_transaction_engine(10, true)
    engine.state.completed.entry = {durable=false,resolution='manual'}
    engine.state.completed.b_key = {durable=true,resolution='confirmed'}
    engine:mark_observed('manual','old run evidence',6002,true)
    engine:start_timer('old-timer', 30, 6002)
    engine:set_waypoint_index(4)
    local changed, reason, rewind = engine:bind_run('new-run',
        run_evidence('new-run', {}), 6003)
    truthy(changed); contains(reason, 'rewound'); equal(rewind, 2)
    equal(engine.state.current_index, 2); falsy(engine.state.complete)
    equal(engine.state.active_run_id, 'new-run')
    equal(engine.state.run_started_at, 6003)
    equal(engine.state.waypoint_index, 1)
    falsy(engine.state.observed); falsy(engine.state.completion_ready_for)
    equal(next(engine.state.timers), nil)
    falsy(engine.state.completed.entry)
    truthy(engine.state.completed.b_key,
        'durable permanent evidence survives a run rollover')
end)

test('B C and D transactions rewind only when their durable goal is missing', function()
    local b = bound_transaction_engine(8)
    local changed, _, rewind = b:bind_run('b-new',
        run_evidence('b-new', {plate_b=true}), 6100)
    truthy(changed); equal(rewind, 2); equal(b:current().id, 'b_start')

    local c = bound_transaction_engine(8)
    changed, _, rewind = c:bind_run('c-new', run_evidence('c-new', {
        key_b=true,sheet_b=true,plate_c=true,sheet_c=false,
    }), 6101)
    truthy(changed); equal(rewind, 5); equal(c:current().id, 'c_kill')

    local d = bound_transaction_engine(10, true)
    changed, _, rewind = d:bind_run('d-new', run_evidence('d-new', {
        key_b=true,sheet_b=true,plate_c=true,sheet_c=true,sheet_d=false,
    }), 6102)
    truthy(changed); equal(rewind, 8); equal(d:current().id, 'd_clear')
    falsy(d.state.complete)

    local owned = bound_transaction_engine(10, true)
    changed, _, rewind = owned:bind_run('owned-new',
        run_evidence('owned-new', {
            key_b=true,sheet_b=true,sheet_c=true,sheet_d=true,
        }), 6103)
    truthy(changed); falsy(rewind)
    equal(owned.state.current_index, 10); truthy(owned.state.complete)

    local not_beyond = bound_transaction_engine(2)
    changed, _, rewind = not_beyond:bind_run('early-new',
        run_evidence('early-new', {}), 6104)
    truthy(changed); falsy(rewind)
    equal(not_beyond.state.current_index, 2,
        'a transaction can rewind but can never move progress forward')
end)

test('run binding requires exact quorum evidence and is idempotent', function()
    local engine = Engine.new(transaction_route(), nil, 6200)
    engine:start(6200)
    local ok, reason = engine:bind_run('run-one', {}, 6201)
    falsy(ok); contains(reason, 'six-client')
    ok, reason = engine:bind_run('run-one',
        {run_quorum=true,run_id='some-other-run',all_items={}}, 6201)
    falsy(ok); contains(reason, 'six-client')
    truthy(engine:bind_run('run-one',run_evidence('run-one',{}),6202))
    engine:start_timer('keep', 30, 6203)
    ok, reason = engine:bind_run('run-one',run_evidence('run-one',{}),6204)
    falsy(ok); contains(reason, 'already')
    truthy(engine:timer('keep'), 'same-run bind must preserve local artifacts')
    truthy(engine:unbind_run(6205, true))
    falsy(engine.state.active_run_id); falsy(engine:timer('keep'))
    truthy(engine.state.paused)
end)

test('navigation cardinal headings follow Windower facing convention', function()
    local origin = {x=0, y=0, z=10, ready=true}
    near(Navigation.heading(origin, {x=1,y=0}), 0)
    near(Navigation.heading(origin, {x=0,y=-1}), math.pi / 2)
    near(Navigation.heading(origin, {x=-1,y=0}), math.pi)
    near(Navigation.heading(origin, {x=0,y=1}), -math.pi / 2)
    near(Navigation.relative_heading(origin, {x=0,y=-1}, 0), math.pi / 2)
    local distance, dz = Navigation.distance(origin, {x=3,y=4,z=2})
    near(distance, 5); near(dz, -8)
end)

test('navigation angle normalization and all eight arrow sectors are stable', function()
    near(Navigation.normalize_angle(3 * math.pi), math.pi)
    near(Navigation.normalize_angle(-3 * math.pi), math.pi)
    local words = {'ahead','ahead-right','right','back-right','behind',
        'back-left','left','ahead-left'}
    for index, word in ipairs(words) do
        local relative = (index - 1) * math.pi / 4
        if relative > math.pi then relative = relative - 2 * math.pi end
        local arrow, actual, actual_index = Navigation.arrow(relative)
        truthy(type(arrow) == 'string' and arrow ~= '')
        equal(actual, word)
        equal(actual_index, index)
    end
    local _, left = Navigation.arrow(-math.pi / 2)
    equal(left, 'left')
    equal(Navigation.frame(0, 32), 1)
    equal(Navigation.frame(math.pi / 2, 32), 9)
    equal(Navigation.frame(-math.pi / 2, 32), 25)
end)

test('waypoint lookup honors calibrated overrides and route paths', function()
    local landmarks = {
        first={name='First',x=1,y=2,z=3,radius=4,confidence='static'},
        second={name='Second',x=8,y=9,radius=6,cue='Turn east.'},
    }
    local overrides = {first={name='Live First',x=10,y=20,z=30,
        radius=2,confidence='live'}}
    local first = Navigation.current_waypoint({path={'first','second'}}, 1,
        landmarks, overrides)
    equal(first.x, 10); equal(first.name, 'Live First')
    local second = Navigation.current_waypoint({path={'first','second'}}, 2,
        landmarks, overrides)
    equal(second.x, 8)
    equal(second.cue, 'Turn east.')
    falsy(Navigation.current_waypoint({path={'first'}}, 2, landmarks, overrides))
    falsy(Navigation.resolve_landmark('missing', landmarks, overrides))
end)

test('waypoint dwell hysteresis resets after leaving or switching', function()
    local waypoint = {id='a',x=0,y=0,radius=5}
    local tracker = {}
    local arrived, distance
    arrived, tracker, distance = Navigation.observe_waypoint(
        tracker, {x=4,y=0,ready=true}, waypoint, 10.0, 0.6)
    falsy(arrived); near(distance, 4)
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=4,y=0,ready=true}, waypoint, 10.59, 0.6)
    falsy(arrived)
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=4,y=0,ready=true}, waypoint, 10.61, 0.6)
    truthy(arrived)
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=6,y=0,ready=true}, waypoint, 10.7, 0.6)
    falsy(arrived); falsy(tracker.id)
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=1,y=0,ready=true}, waypoint, 11.0, 0.6)
    falsy(arrived)
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=1,y=0,ready=true}, {id='b',x=1,y=0,radius=5}, 11.8, 0.6)
    falsy(arrived); equal(tracker.id, 'b')
end)

test('waypoint arrival rejects a nearby coordinate on the wrong Z layer', function()
    local waypoint = {id='layered',x=10,y=10,z=100,radius=5,z_tolerance=12}
    local tracker = {}
    local arrived, distance
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=10,y=10,z=100,ready=true}, waypoint, 1.0, 0.6)
    falsy(arrived); equal(tracker.id, 'layered')
    arrived, tracker, distance = Navigation.observe_waypoint(
        tracker, {x=10,y=10,z=113,ready=true}, waypoint, 2.0, 0.6)
    falsy(arrived); near(distance, 0)
    falsy(tracker.id, 'wrong-Z observation must reset dwell state')
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=10,y=10,z=112,ready=true}, waypoint, 3.0, 0.6)
    falsy(arrived, 'Z tolerance boundary still begins a new dwell')
    arrived, tracker = Navigation.observe_waypoint(
        tracker, {x=10,y=10,z=112,ready=true}, waypoint, 3.61, 0.6)
    truthy(arrived, 'position inside the configured Z tolerance may arrive')

    local resolved = Navigation.resolve_landmark('layered', {
        layered={x=10,y=10,z=100,radius=5,z_tolerance=7},
    })
    equal(resolved.z_tolerance, 7)
    local defaulted = Navigation.resolve_landmark('default', {
        default={x=0,y=0,z=0},
    })
    equal(defaulted.z_tolerance, 12)
end)

local protocol_now = 1788537600
local protocol_pack = {
    id='sortie', catalog_id='sortie-r1-deadbeef',
    items=make_catalog({{key='a'},{key='b'},{key='c'},
        {key='d'},{key='e'},{key='f'}}),
    key_items=make_catalog({{key='shiny'},{key='ruspix'}}),
    instance_zones={[133]=true,[189]=true,[275]=true},
}
local state_payload = {
    pack_id=protocol_pack.id, catalog_id=protocol_pack.catalog_id,
    sender='Dolomedes', main_job='COR', sub_job='NIN',
    zone=275, timestamp=protocol_now, sequence=7,
    x=-12.25, y=80.5, z=0, status=0, ready=true,
    party_exact=true, leader_exact=true,
    entry_nonce='sortie-dolo-1',
    items='101001', key_items='10',
}

test('state protocol round trips its fixed read-only envelope', function()
    local message = Protocol.state(state_payload)
    equal(message, 'EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR|NIN|275|1788537600|7|-12.25|80.50|0.00|0|1|1|1|sortie-dolo-1|101001|10')
    truthy(Protocol.is_ours(message))
    local report, reason = Protocol.validate(message, {
        now=protocol_now, max_age=8, catalogs={sortie=protocol_pack},
        allowed_sender=function(name) return name == 'Dolomedes' end,
    })
    truthy(report, reason)
    equal(report.kind, 'STATE'); equal(report.sender, 'Dolomedes')
    equal(report.main_job, 'COR'); equal(report.sub_job, 'NIN')
    equal(report.pack_id, 'sortie'); equal(report.catalog_id, protocol_pack.catalog_id)
    equal(report.sequence, 7); near(report.x, -12.25)
    truthy(report.ready); truthy(report.party_exact); truthy(report.leader_exact)
    equal(report.entry_nonce, 'sortie-dolo-1')
    equal(report.items, '101001'); equal(report.key_items, '10')
end)

test('state protocol rejects foreign, action, malformed, and oversized envelopes', function()
    local options = {now=protocol_now, catalogs={sortie=protocol_pack}}
    local report, reason = Protocol.validate('XX|1|STATE|Dolomedes', options)
    falsy(report); contains(reason, 'foreign')
    report, reason = Protocol.validate(
        'EG|2|ACTION|sortie|sortie-r1-deadbeef|Dolomedes', options)
    falsy(report); contains(reason, 'envelope')
    report, reason = Protocol.validate(('EG|2|'):rep(110), options)
    falsy(report); contains(reason, 'oversized')
    report, reason = Protocol.validate(
        'EG|2|STATE|sortie|sortie-r1-deadbeef|Dolo-evil|COR|NIN|275|1788537600|1|0|0|0|0|1|1|1|sortie-dolo-1|101001|10', options)
    falsy(report); contains(reason, 'sender')
    report, reason = Protocol.validate(
        Protocol.state(state_payload) .. '|EXTRA', options)
    falsy(report); contains(reason, 'envelope')
    report, reason = Protocol.validate(
        'EG|1|STATE|Dolomedes|275|1788537600|1|0|0|0|0|1|101001|10', options)
    falsy(report); contains(reason, 'legacy')
end)

test('state protocol rejects untrusted numeric, evidence, sender, and time fields', function()
    local function validate(message, extra)
        local options = {now=protocol_now, max_age=8,
            catalogs={sortie={id='sortie',catalog_id=protocol_pack.catalog_id,
                items=make_catalog({{key='a'},{key='b'},{key='c'}}),
                key_items=protocol_pack.key_items,
                instance_zones={[275]=true}}},
            allowed_sender=function(name) return name == 'Dolomedes' end}
        for key, value in pairs(extra or {}) do options[key] = value end
        return Protocol.validate(message, options)
    end
    local template = 'EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR|NIN|%s|%s|%s|%s|0|0|%s|1|1|1|sortie-dolo-1|%s|%s'
    local bad = {
        template:format('275.5', protocol_now, 1, 0, 0, '101', '11'),
        template:format(275, protocol_now, '1.5', 0, 0, '101', '11'),
        template:format(275, protocol_now, 1, 'nan', 0, '101', '11'),
        template:format(275, protocol_now, 1, 10001, 0, '101', '11'),
        template:format(275, protocol_now, 1, 0, 65, '101', '11'),
        template:format(275, protocol_now, 1, 0, 0, '10x', '11'),
        template:format(275, protocol_now, 1, 0, 0, '10', '11'),
        template:format(275, protocol_now, 1, 0, 0, '101', '1x'),
    }
    for index, message in ipairs(bad) do
        local report = validate(message)
        falsy(report, 'malformed protocol case ' .. index .. ' was accepted')
    end
    local bad_ready = ('EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR|NIN|275|%s|1|0|0|0|0|x|1|1|sortie-dolo-1|101|11')
        :format(protocol_now)
    local report, reason = validate(bad_ready)
    falsy(report); contains(reason, 'readiness')
    local bad_party = ('EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR|NIN|275|%s|1|0|0|0|0|1|x|1|sortie-dolo-1|101|11')
        :format(protocol_now)
    report, reason = validate(bad_party)
    falsy(report); contains(reason, 'party evidence')
    local bad_job = ('EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR;attack|NIN|275|%s|1|0|0|0|0|1|1|1|sortie-dolo-1|101|11')
        :format(protocol_now)
    report, reason = validate(bad_job)
    falsy(report); contains(reason, 'job evidence')
    local stale = template:format(275, protocol_now - 9, 1, 0, 0, '101', '11')
    report, reason = validate(stale)
    falsy(report); contains(reason, 'stale')
    local future = template:format(275, protocol_now + 3, 1, 0, 0, '101', '11')
    report, reason = validate(future)
    falsy(report); contains(reason, 'stale')
    local denied = template:format(275, protocol_now, 1, 0, 0, '101', '11')
    report, reason = validate(denied, {allowed_sender=function() return false end})
    falsy(report); contains(reason, 'not allowed')
end)

test('state protocol scopes entry nonces to instance zones and rejects injection', function()
    local options = {now=protocol_now,max_age=8,
        catalogs={sortie=protocol_pack}}
    local function copy_payload()
        local result = {}
        for key, value in pairs(state_payload) do result[key] = value end
        return result
    end
    for _, nonce in ipairs({'has space','UPPER','pipe|value',string.rep('a',97)}) do
        local payload = copy_payload(); payload.entry_nonce = nonce
        local ok = pcall(Protocol.state, payload)
        falsy(ok, 'encoder accepted malformed nonce ' .. nonce:sub(1, 12))
    end

    local outside = copy_payload()
    outside.zone = 267
    local forged = Protocol.state(outside)
    local report_value, reason = Protocol.validate(forged, options)
    falsy(report_value); contains(reason, 'entry nonce')

    outside.entry_nonce = ''
    report_value, reason = Protocol.validate(Protocol.state(outside), options)
    truthy(report_value, reason)
    equal(report_value.entry_nonce, '')

    local malformed_catalog = {
        id='sortie',catalog_id=protocol_pack.catalog_id,
        items=protocol_pack.items,key_items=protocol_pack.key_items,
    }
    local ok, decoded, decode_reason = pcall(Protocol.validate,
        Protocol.state(state_payload), {
            now=protocol_now,catalogs={sortie=malformed_catalog},
        })
    truthy(ok, 'missing instance_zones must return an error, not throw')
    falsy(decoded); contains(decode_reason, 'entry nonce')

    local old_v2 = 'EG|2|STATE|sortie|sortie-r1-deadbeef|Dolomedes|COR|NIN|275|1788537600|7|-12.25|80.50|0.00|0|1|1|1|101001|10'
    report_value, reason = Protocol.validate(old_v2, options)
    falsy(report_value); contains(reason, 'envelope')
end)

test('pack and catalog identities prevent same-length evidence collisions', function()
    local odyssey = {
        id='odyssey', catalog_id='odyssey-r1-cafebabe',
        items=protocol_pack.items, key_items=protocol_pack.key_items,
        instance_zones={[275]=true},
    }
    local options = {now=protocol_now,
        catalogs={sortie=protocol_pack,odyssey=odyssey}}
    local payload = {}
    for key, value in pairs(state_payload) do payload[key] = value end
    payload.pack_id, payload.catalog_id = odyssey.id, odyssey.catalog_id
    local report = Protocol.validate(Protocol.state(payload), options)
    truthy(report); equal(report.pack_id, 'odyssey')

    payload.pack_id = 'sortie'
    local rejected, reason = Protocol.validate(Protocol.state(payload), options)
    falsy(rejected); contains(reason, 'catalog mismatch')
end)

test('read-only sensor capture creates deterministic item and key-item bitmaps', function()
    local requested_bag = nil
    local sensor_roster = {'Dolomedes','Tackleberry','Kickpuncher',
        'Barneystinson','Smalls','Achoo'}
    local party = {party1_count=6,party1_leader=42}
    for index, name in ipairs(sensor_roster) do
        party['p' .. tostring(index - 1)] = {name=name,id=41 + index}
    end
    local api = {ffxi={
        get_player=function() return {name='Dolomedes',id=42,status=1,
            main_job='COR',sub_job='NIN'} end,
        get_info=function() return {zone=275} end,
        get_mob_by_target=function(target)
            equal(target, 'me')
            return {x=1.25,y=-2.5,z=3.75,facing=0.5,status=0}
        end,
        get_items=function(bag)
            requested_bag = bag
            return {{id=9894},{id=9900},[15]={id=6685}}
        end,
        get_key_items=function()
            return {[3300]=true,{id=9999}}
        end,
        get_party=function() return party end,
    }}
    local pack = {id='sortie',catalog_id='sortie-r1-test',
        items=make_catalog({{id=9894},{id=9895},{id=9900},{id=6685}}),
        key_items=make_catalog({{id=3300},{id=3328}})}
    local snapshot = Sensors.snapshot(api, 500, sensor_roster, 'Dolomedes')
    local captured = Sensors.report(snapshot, pack, 9)
    equal(requested_bag, 3, 'temporary items must come only from bag 3')
    equal(captured.sender, 'Dolomedes'); equal(captured.zone, 275)
    equal(captured.main_job, 'COR'); equal(captured.sub_job, 'NIN')
    equal(captured.timestamp, 500); equal(captured.status, 1)
    truthy(captured.ready); truthy(captured.party_exact)
    truthy(captured.leader_exact)
    equal(captured.items, '1011'); equal(captured.key_items, '10')
    equal(captured.pack_id, 'sortie'); equal(captured.sequence, 9)
    near(captured.x, 1.25); near(captured.facing, 0.5)

    party.a10 = {name='Allianceguest',id=99}
    local allied = Sensors.report(
        Sensors.snapshot(api, 501, sensor_roster, 'Dolomedes'), pack, 10)
    falsy(allied.party_exact, 'an attached alliance must fail exact-party proof')
    falsy(allied.leader_exact)

    party.a10 = nil
    party.p0 = {name='Dolomedes'}
    api.ffxi.get_player = function() return {
        name='Kickpuncher',id=44,status=0,main_job='DNC',sub_job='NIN',
    } end
    local distant_follower = Sensors.report(
        Sensors.snapshot(api, 502, sensor_roster, 'Dolomedes'), pack, 11)
    truthy(distant_follower.party_exact,
        'a follower must not need a distant Dolo mob/id to prove roster names')
    falsy(distant_follower.leader_exact,
        'only the configured leader may make the local leadership claim')
end)

test('sensor capture fails inertly without a logged-in player', function()
    local api = {ffxi={
        get_player=function() return nil end,
        get_info=function() return {zone=275} end,
    }}
    falsy(Sensors.snapshot(api, 500))
end)

test('sensor capture reports not-ready when navigation evidence is incomplete', function()
    local api = {ffxi={
        get_player=function() return {name='Dolomedes',id=42,status=0} end,
        get_info=function() return {zone=275} end,
        get_mob_by_target=function() return {x=1,y=2,z=3,facing=0} end,
        get_items=function() return nil end,
        get_key_items=function() return {} end,
    }}
    local snapshot = Sensors.snapshot(api, 501)
    local captured = Sensors.report(snapshot, {
        id='sortie',catalog_id='sortie-r1-test',
        items=make_catalog({{id=9894}}),
        key_items=make_catalog({{id=3300},{id=3328}}),
    }, 1)
    truthy(captured, 'partial sensor capture should remain reportable')
    falsy(captured.ready,
        'missing temporary-item/navigation evidence must mark report unready')
    equal(captured.items, '0'); equal(captured.key_items, '00')
end)

test('live landmark calibration validates both entity index and identity', function()
    local by_index = {index=865,name='Gate #A1',x=1,y=2,z=3}
    local target = nil
    local api = {ffxi={
        get_mob_by_index=function(index)
            equal(index, 865)
            return by_index
        end,
        get_mob_by_target=function(which)
            equal(which, 't')
            return target
        end,
    }}
    local landmark = {name='Gate #A1',entity_index=865,
        entity_family='Gate',radius=5}
    local live = Sensors.live_landmark(api, 'gate_a1', landmark)
    truthy(live); equal(live.confidence, 'live_entity'); equal(live.x, 1)
    by_index = {index=865,name='Not A Gate',x=50,y=50,z=0}
    target = {index=865,name='Gate #A1',x=4,y=5,z=6}
    live = Sensors.live_landmark(api, 'gate_a1', landmark)
    truthy(live); equal(live.confidence, 'live_target'); equal(live.x, 4)
    target = {index=999,name='Gate #A1',x=7,y=8,z=9}
    falsy(Sensors.live_landmark(api, 'gate_a1', landmark),
        'a matching name at the wrong index must not calibrate')
end)

test('numbered landmark identity rejects a same-family wrong numbered name', function()
    local by_index = {index=865,name='Gate #A2',x=1,y=2,z=3}
    local target = nil
    local api = {ffxi={
        get_mob_by_index=function() return by_index end,
        get_mob_by_target=function() return target end,
    }}
    local landmark = {name='Gate #A1',entity_index=865,
        entity_family='Gate',radius=5}
    falsy(Sensors.live_landmark(api, 'gate_a1', landmark),
        'Gate family prefix must not turn Gate #A2 into Gate #A1')
    target = {index=865,name='Gate #A3',x=4,y=5,z=6}
    falsy(Sensors.live_landmark(api, 'gate_a1', landmark),
        'even an in-index target needs the exact numbered identity')
end)

local roster = {'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}
local item_catalog = make_catalog({{key='key_a'},{key='plate_a'},
    {key='sheet_a'}})
local key_item_catalog = make_catalog({{key='shiny_plate'},
    {key='ruspix_plate'}})
local sortie_zones = {[133]=true,[189]=true,[275]=true}
local party_pack = {id='sortie',catalog_id='sortie-r1-party',
    items=item_catalog,key_items=key_item_catalog,
    allowed_zones=sortie_zones,instance_zones=sortie_zones}

local function report(name, timestamp, sequence, values)
    values = values or {}
    local leader_exact = values.leader_exact
    if leader_exact == nil then leader_exact = name == 'Dolomedes' end
    local zone = values.zone or 275
    local entry_nonce = values.entry_nonce
    if entry_nonce == nil then
        entry_nonce = sortie_zones[zone]
            and ('entry-' .. name:lower()) or ''
    end
    return {
        pack_id=values.pack_id or party_pack.id,
        catalog_id=values.catalog_id or party_pack.catalog_id,
        sender=name, timestamp=timestamp, sequence=sequence or 1,
        zone=zone, status=values.status or 0,
        ready=values.ready ~= false,
        party_exact=values.party_exact ~= false,
        leader_exact=leader_exact == true,
        items=values.items or '111', key_items=values.key_items or '11',
        entry_nonce=entry_nonce,
        x=0, y=0, z=0,
    }
end

local function cohort_summary(run_id, zone, nonces)
    local entries = {}
    for _, name in ipairs(roster) do
        entries[#entries + 1] = name:lower() .. '=' .. nonces[name]
    end
    return {
        run_quorum=true, run_id=run_id, run_zone=zone,
        run_cohort=table.concat(entries, '|'),
        entry_nonces=nonces,
        leader_entry_nonce=nonces.Dolomedes,
        all_items={},
    }
end

test('run session mints entry identity only for a proven outside transition', function()
    local issued = 0
    local function factory(_, identity, zone)
        issued = issued + 1
        return ('entry-%s-%d-%d'):format(identity:lower(), zone, issued)
    end
    for _, zone in ipairs({133,189,275}) do
        local session = RunSession.new(party_pack, 'Dolomedes', factory)
        equal(session:cold_start(267), 'outside')
        falsy(session.entry_nonce)
        equal(session:observe_zone(zone, 267, 4000), 'entered')
        local first = session.entry_nonce
        truthy(first and first ~= '')

        local nonces = {}
        for _, name in ipairs(roster) do
            nonces[name] = name == 'Dolomedes' and first
                or ('entry-' .. name:lower() .. '-old')
        end
        truthy(session:reconcile(cohort_summary('run-' .. zone, zone, nonces)))
        equal(session.bound_run_id, 'run-' .. zone)
        equal(session:observe_zone(zone, zone, 4001), 'unchanged_inside')
        equal(session.entry_nonce, first)
        equal(session.bound_run_id, 'run-' .. zone,
            'duplicate zone notification must not erase a binding')

        equal(session:observe_zone(267, zone, 4002), 'exited')
        falsy(session.entry_nonce); falsy(session.bound_run_id)
        equal(session:observe_zone(zone, 267, 4002), 'entered')
        truthy(session.entry_nonce ~= first,
            'same-zone reentry must mint a different entry nonce')
    end
end)

test('cold inside, invalid transitions, and direct U-zone changes fail closed', function()
    for _, zone in ipairs({133,189,275}) do
        local session = RunSession.new(party_pack, 'Dolomedes')
        equal(session:cold_start(zone), 'unbound_inside')
        truthy(session.blocked); falsy(session.entry_nonce)
        local bound, reason = session:reconcile({run_quorum=true})
        falsy(bound); equal(reason, 'unbound')
    end

    for _, transition in ipairs({
        {275,nil},{nil,267},{275,267.5},{1025,267},{275,-1},
    }) do
        local session = RunSession.new(party_pack, 'Dolomedes')
        session:cold_start(267)
        equal(session:observe_zone(transition[1], transition[2], 4100),
            'invalid_zone_transition')
        truthy(session.blocked); falsy(session.entry_nonce)
    end

    for _, from in ipairs({133,189,275}) do
        for _, to in ipairs({133,189,275}) do
            if from ~= to then
                local session = RunSession.new(party_pack, 'Dolomedes')
                session:cold_start(267)
                equal(session:observe_zone(from, 267, 4200), 'entered')
                equal(session:observe_zone(to, from, 4201),
                    'ambiguous_instance_change')
                truthy(session.blocked); falsy(session.entry_nonce)
            end
        end
    end
end)

test('entry nonce factories are unique by default and validated fail closed', function()
    local first = RunSession.new(party_pack, 'Dolomedes')
    local second = RunSession.new(party_pack, 'Dolomedes')
    first:cold_start(267); second:cold_start(267)
    equal(first:observe_zone(275, 267, 4300), 'entered')
    equal(second:observe_zone(275, 267, 4300), 'entered')
    truthy(first.entry_nonce ~= second.entry_nonce,
        'two same-second sessions must not collide')
    package.loaded['lib.run_session'] = nil
    local ReloadedSession = require('lib.run_session')
    local reloaded = ReloadedSession.new(party_pack, 'Dolomedes')
    reloaded:cold_start(267)
    equal(reloaded:observe_zone(275, 267, 4300), 'entered')
    truthy(reloaded.entry_nonce ~= first.entry_nonce
        and reloaded.entry_nonce ~= second.entry_nonce,
        'a same-second module reload needs a distinct boot nonce')
    for _, bad in ipairs({'','has space','UPPER','pipe|value',string.rep('a',97)}) do
        local session = RunSession.new(party_pack, 'Dolomedes',
            function() return bad end)
        session:cold_start(267)
        equal(session:observe_zone(275, 267, 4301), 'invalid_entry_nonce')
        truthy(session.blocked); falsy(session.entry_nonce)
    end
end)

test('run binding is exact, atomic across reentry, and tolerant of dropout', function()
    local issued = 0
    local session = RunSession.new(party_pack, 'Dolomedes', function()
        issued = issued + 1
        return issued == 1 and 'dolo-old' or 'dolo-new'
    end)
    session:cold_start(267)
    session:observe_zone(275, 267, 4400)
    local old = {}
    for _, name in ipairs(roster) do
        old[name] = name == 'Dolomedes' and session.entry_nonce
            or (name:lower() .. '-old')
    end
    local first = cohort_summary('same-hash-label', 275, old)
    local bound, status = session:reconcile(first)
    truthy(bound); equal(status, 'bound')

    bound, status = session:reconcile({run_quorum=false})
    truthy(bound); equal(status, 'waiting')
    equal(session.bound_run_id, 'same-hash-label')
    bound, status = session:reconcile(first)
    truthy(bound); equal(status, 'stable')

    session:observe_zone(267, 275, 4401)
    session:observe_zone(275, 267, 4401)
    local mixed = {}
    for name, nonce in pairs(old) do mixed[name] = nonce end
    mixed.Dolomedes = session.entry_nonce
    bound, status = session:reconcile(
        cohort_summary('mixed-label', 275, mixed))
    falsy(bound); equal(status, 'mixed_entry_cohort')
    falsy(session.bound_run_id)

    local fresh = {}
    for _, name in ipairs(roster) do
        fresh[name] = name == 'Dolomedes' and session.entry_nonce
            or (name:lower() .. '-new')
    end
    bound, status = session:reconcile(
        cohort_summary('same-hash-label', 275, fresh))
    truthy(bound); equal(status, 'bound')

    local collision = {}
    for name, nonce in pairs(fresh) do collision[name] = nonce end
    collision.Achoo = 'achoo-another'
    bound, status = session:reconcile(
        cohort_summary('same-hash-label', 275, collision))
    falsy(bound); equal(status, 'binding_changed')
    truthy(session.blocked)
end)

test('party state rejects unknown senders and replayed or reordered reports', function()
    local party = PartyState.new(roster, party_pack)
    falsy(party:update(report('Intruder', 100, 1)))
    falsy(party:update(report('Dolomedes', 100, 1,
        {pack_id='odyssey'})))
    falsy(party:update(report('Dolomedes', 100, 1,
        {catalog_id='sortie-r2-wrong'})))
    truthy(party:update(report('DOLOMEDES', 100, 1)))
    equal(party.reports.Dolomedes.sender, 'Dolomedes')
    falsy(party:update(report('Dolomedes', 100, 1)))
    falsy(party:update(report('Dolomedes', 100, 0)))
    truthy(party:update(report('Dolomedes', 100, 2)))
    falsy(party:update(report('Dolomedes', 99, 999)))
    truthy(party:update(report('Dolomedes', 101, 0)))
end)

test('exact party and Dolo leader evidence gate all-in-pack independently', function()
    local party = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        party:update(report(name, 500, index, {
            party_exact=name ~= 'Achoo',
            leader_exact=name ~= 'Dolomedes',
        }))
    end
    local summary = party:summary(500, 8, 275)
    truthy(summary.sensor_quorum)
    falsy(summary.party_quorum); falsy(summary.leader_quorum)
    equal(summary.party_exact, 5); equal(summary.leader_exact, 0)
    equal(summary.leader_expected, 1)
    falsy(summary.all_in_pack)
    equal(summary.key_item_counts.shiny_plate, 6,
        'party mismatch must not be mislabeled as a missing key item')
    falsy(summary.key_item_presence.Achoo,
        'party-mismatch key items must remain unknown diagnostics')
    truthy(summary.key_item_presence.Dolomedes.shiny_plate)
    equal(#summary.party_mismatch_clients, 1)
    equal(#summary.leader_mismatch_clients, 1)
end)

test('six-client quorum requires all six fresh, same-zone, idle reports', function()
    local party = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        truthy(party:update(report(name, 1000, index)))
    end
    local summary = party:summary(1004, 8, 275)
    equal(summary.expected, 6); equal(summary.fresh, 6)
    equal(summary.same_zone, 6); equal(summary.in_pack, 6)
    truthy(summary.sensor_quorum); truthy(summary.all_in_pack)
    truthy(summary.leader_quorum); equal(summary.leader_exact, 1)
    equal(summary.leader_expected, 1)
    truthy(summary.all_clients_idle)
    truthy(summary.all_items.key_a); truthy(summary.all_items.plate_a)
    equal(summary.key_item_counts.shiny_plate, 6)
    equal(summary.key_item_counts.ruspix_plate, 6)
    for _, name in ipairs(roster) do
        truthy(summary.key_item_presence[name].shiny_plate)
        truthy(summary.key_item_presence[name].ruspix_plate)
    end
    equal(#summary.missing.key_a, 0)
    truthy(summary.entry_nonce_quorum)
    truthy(summary.run_quorum)
    truthy(type(summary.run_id) == 'string' and #summary.run_id > 16)
    truthy(type(summary.run_cohort) == 'string')
    equal(summary.leader_entry_nonce, 'entry-dolomedes')
end)

test('run identity is arrival-order independent and duplicate nonces fail closed', function()
    local forward = PartyState.new(roster, party_pack)
    local reverse = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        truthy(forward:update(report(name, 1500, index)))
    end
    for index = #roster, 1, -1 do
        truthy(reverse:update(report(roster[index], 1500, index)))
    end
    local one = forward:summary(1500, 8, 275)
    local two = reverse:summary(1500, 8, 275)
    truthy(one.run_quorum); truthy(two.run_quorum)
    equal(one.run_id, two.run_id)
    equal(one.run_cohort, two.run_cohort)

    local duplicate = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        duplicate:update(report(name, 1501, index, {
            entry_nonce=(name == 'Achoo' or name == 'Smalls')
                and 'shared-entry' or ('unique-' .. name:lower()),
        }))
    end
    local rejected = duplicate:summary(1501, 8, 275)
    falsy(rejected.entry_nonce_quorum)
    falsy(rejected.run_quorum); falsy(rejected.run_id)
end)

test('nonce rollover permits sequence restart and rejects retired replay', function()
    local party = PartyState.new(roster, party_pack)
    truthy(party:update(report('Dolomedes', 1600, 99,
        {entry_nonce='dolo-first'})))
    truthy(party:update(report('Dolomedes', 1600, 0,
        {entry_nonce='dolo-second'})),
        'a new process nonce may restart its sequence in the same second')
    falsy(party:update(report('Dolomedes', 1601, 100,
        {entry_nonce='dolo-first'})),
        'a delayed retired nonce must never resurrect an incarnation')
    equal(party.reports.Dolomedes.entry_nonce, 'dolo-second')
end)

test('five-of-six, empty nonce, and mixed-zone reports cannot bind a run', function()
    local party = PartyState.new(roster, party_pack)
    for index = 1, 5 do
        party:update(report(roster[index], 1700, index))
    end
    local summary = party:summary(1700, 8, 275)
    equal(summary.fresh, 5); falsy(summary.run_quorum)
    falsy(summary.run_id)

    party:update(report('Achoo', 1700, 6, {entry_nonce=''}))
    summary = party:summary(1700, 8, 275)
    truthy(summary.all_in_pack,
        'location proof remains separate from entry-incarnation proof')
    falsy(summary.entry_nonce_quorum); falsy(summary.run_quorum)

    party:update(report('Achoo', 1701, 7,
        {entry_nonce='achoo-new',zone=189}))
    summary = party:summary(1701, 8, 275)
    falsy(summary.sensor_quorum); falsy(summary.run_quorum)
end)

test('six-client quorum fails closed for stale, zoned, engaged, or missing evidence', function()
    local party = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        party:update(report(name, name == 'Smalls' and 1990 or 2000, index))
    end
    party:update(report('Tackleberry', 2001, 7, {zone=189,items='101'}))
    party:update(report('Kickpuncher', 2001, 7, {status=1}))
    party:update(report('Achoo', 2001, 7, {key_items='00'}))
    local summary = party:summary(2001, 8, 275)
    equal(summary.fresh, 5, 'one report should be stale')
    equal(summary.same_zone, 4, 'stale and wrong-zone clients are excluded')
    equal(summary.in_pack, 5, 'fresh wrong-zone pack client remains in pack')
    falsy(summary.sensor_quorum); falsy(summary.all_in_pack)
    falsy(summary.all_clients_idle)
    falsy(summary.all_items.plate_a)
    equal(#summary.missing.plate_a, 2)
    equal(summary.key_item_counts.shiny_plate, 3)
    equal(summary.key_item_counts.ruspix_plate, 3)
    falsy(summary.all_key_items.shiny_plate)
    falsy(summary.all_key_items.ruspix_plate)
    equal(#summary.missing_key_items.shiny_plate, 3)
    equal(#summary.missing_key_items.ruspix_plate, 3)
end)

test('a client outside its pack makes all-in-pack false even with fresh quorum', function()
    local party = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        party:update(report(name, 3000, index, {
            zone=name == 'Achoo' and 1 or 275,
        }))
    end
    local summary = party:summary(3000, 8, 275)
    equal(summary.fresh, 6); equal(summary.same_zone, 5)
    equal(summary.in_pack, 5)
    falsy(summary.sensor_quorum); falsy(summary.all_in_pack)
end)

test('guide zones never satisfy an expedition instance transition', function()
    local guide_pack = {
        id='sortie',catalog_id='sortie-r1-guide-zones',
        items=item_catalog,key_items=key_item_catalog,
        allowed_zones={[267]=true,[275]=true},instance_zones={[275]=true},
    }
    local party = PartyState.new(roster, guide_pack, 'Dolomedes')
    for index, name in ipairs(roster) do
        party:update(report(name, 3050, index, {zone=267,
            catalog_id=guide_pack.catalog_id}))
    end
    local summary = party:summary(3050, 8, 267)
    truthy(summary.sensor_quorum); truthy(summary.party_quorum)
    truthy(summary.leader_quorum)
    equal(summary.in_pack, 0)
    falsy(summary.all_in_pack,
        'Kamihr may guide preflight but cannot prove entry into Sortie')
end)

test('ready=false report cannot satisfy quorum, all-in-pack, or item evidence', function()
    local party = PartyState.new(roster, party_pack)
    for index, name in ipairs(roster) do
        party:update(report(name, 3100, index, {
            ready=name ~= 'Achoo',
        }))
    end
    local summary = party:summary(3100, 8, 275)
    equal(summary.fresh, 6)
    equal(summary.ready, 5)
    equal(summary.same_zone, 5)
    equal(summary.in_pack, 5)
    falsy(summary.sensor_quorum)
    falsy(summary.all_in_pack)
    falsy(summary.all_clients_idle)
    falsy(summary.all_items.key_a)
    equal(#summary.unready_clients, 1)
    equal(summary.unready_clients[1], 'Achoo')
    equal(#summary.missing.key_a, 1)
    equal(summary.missing.key_a[1], 'Achoo')
end)

test('shipped content validates without quarantine', function()
    local registry = require('content.registry')
    local content, errors = Loader.load(registry, Schema, require, {
        fingerprint=Fingerprint.value,
    })
    equal(#errors, 0, table.concat(errors, '; '))
    truthy(content.packs.sortie)
    equal(registry.packs[1].catalog_revision, 2)
    truthy(content.packs.sortie.allowed_zones[267])
    truthy(content.packs.sortie.allowed_zones[281])
    falsy(content.packs.sortie.instance_zones[267])
    falsy(content.packs.sortie.instance_zones[281])
    truthy(content.packs.sortie.instance_zones[133])
    truthy(content.packs.sortie.instance_zones[189])
    truthy(content.packs.sortie.instance_zones[275])
    truthy(content.packs.sortie.objectives)
    truthy(content.routes['sortie-onboarding-core'])
    truthy(content.routes['sortie-onboarding-sheet-d'])
    equal(content.aliases.onboarding, 'sortie-onboarding-core')
    equal(content.aliases.unlocks, 'sortie-onboarding-core')
    equal(content.aliases.core, 'sortie-onboarding-core')
    equal(content.aliases.sheetd, 'sortie-onboarding-sheet-d')
    equal(registry.reserved_aliases.onboarding, 'sortie-onboarding-core')
    equal(registry.reserved_aliases.sheetd, 'sortie-onboarding-sheet-d')
    equal(registry.reserved_aliases.boss2,
        'sortie-two-boss-c-a-training')
    truthy(content.packs.sortie.profiles.sortie_objective_d_demisang_clear)
    truthy(type(content.packs.sortie.route_digests[
        'sortie-onboarding-core']) == 'string')
    truthy(type(content.packs.sortie.route_digests[
        'sortie-onboarding-sheet-d']) == 'string')
    local ground_floor = content.packs.sortie.route_reward_scopes[
        'sortie-onboarding-core'].ground_floor
    equal(ground_floor.label, 'Sortie ground floor')
    for _, zone in ipairs({133,189,275}) do
        truthy(Region.contains_scope(ground_floor,
            {zone=zone,x=0,y=0,z=-150}))
        falsy(Region.contains_scope(ground_floor,
            {zone=zone,x=0,y=0,z=-100}))
    end
    local core = content.routes['sortie-onboarding-core']
    equal(core.version, '0.4.1')
    truthy(core.allowed_zones[267]); truthy(core.allowed_zones[281])
    equal(#core.run_transactions, 3)
    equal(core.run_transactions[1].id, 'b_key_gate_sequence')
    equal(core.run_transactions[1].rewind, 'b_gates_1_4')
    equal(core.run_transactions[1].goal.item, 'key_b')
    equal(core.run_transactions[2].rewind, 'b_gates_1_4')
    equal(core.run_transactions[2].goal.item, 'sheet_b')
    equal(core.run_transactions[3].rewind, 'c_controlled_kill')
    equal(core.run_transactions[3].goal.item, 'sheet_c')
    local c_kill_index, c_plate_index, a_sheet, b_sheet, c_materialize,
        c_sheet, core_complete
    for index, step in ipairs(core.steps) do
        if step.id == 'c_controlled_kill' then c_kill_index = index end
        if step.id == 'c_plate' then c_plate_index = index end
        if step.id == 'a_sheet' then a_sheet = step end
        if step.id == 'b_sheet' then b_sheet = step end
        if step.id == 'c_materialize' then c_materialize = step end
        if step.id == 'c_sheet' then c_sheet = step end
        if step.id == 'core_complete' then core_complete = step end
    end
    truthy(c_kill_index and c_plate_index and c_kill_index < c_plate_index)
    equal(core.steps[c_kill_index].completion.kind, 'manual')
    equal(core.steps[c_kill_index].objective, 'plate_c')
    falsy(core.steps[c_kill_index].reward,
        'the current-run controlled kill cannot claim chest receipt')
    equal(core.steps[c_plate_index].completion.item, 'plate_c')
    equal(core.steps[c_plate_index].reward.scope, 'ground_floor')
    contains(a_sheet.instruction, 'Kickpuncher')
    contains(b_sheet.instruction, 'Kickpuncher')
    contains(c_materialize.instruction, 'Kickpuncher')
    contains(c_sheet.instruction, 'Kickpuncher')
    equal(core_complete.completion.kind, 'all_temp_items')
    truthy(core_complete.completion.auto)
    equal(#core_complete.completion.items, 11)
    local core_reward_steps = 0
    for _, step in ipairs(core.steps) do
        if step.reward then
            core_reward_steps = core_reward_steps + 1
            equal(step.reward.scope, 'ground_floor')
            truthy(step.completion.kind == 'all_temp_item'
                or step.completion.kind == 'all_temp_items')
        end
    end
    equal(core_reward_steps, 11)

    -- Operational promotion is additive: the immutable guide route and its
    -- unavailable placeholder remain unchanged while a discovered v1
    -- descriptor and live-canary route carry the tested combat dependency.
    local live_profile = require(
        'content.sortie.profiles.objective_c_device_kill_v1')
    local profile_valid, profile_errors = Schema.validate_profile(live_profile)
    truthy(profile_valid, table.concat(profile_errors, '; '))
    equal(live_profile.canonical_id,
        'sortie-objective-c-device-kill-v1')
    truthy(live_profile.available)
    local planned_profile = content.packs.sortie.profiles[
        'sortie_objective_c_device_kill']
    truthy(planned_profile); falsy(planned_profile.available)

    local live_core = require('content.sortie.routes.onboarding_core_live')
    local live_profiles = {}
    for key, value in pairs(content.packs.sortie.profiles) do
        live_profiles[key] = value
    end
    live_profiles[live_profile.key] = live_profile
    local live_landmarks, landmark_errors = Schema.compose_landmarks(
        live_core, content.packs.sortie.landmarks)
    local live_scopes, scope_errors = Schema.compose_reward_scopes(
        live_core, content.packs.sortie.reward_scopes)
    equal(#landmark_errors, 0, table.concat(landmark_errors, '; '))
    equal(#scope_errors, 0, table.concat(scope_errors, '; '))
    local live_valid, live_errors = Schema.validate_route(live_core,
        live_landmarks, live_profiles, content.packs.sortie.objectives,
        content.packs.sortie.items, content.packs.sortie.key_items,
        content.packs.sortie, live_scopes)
    truthy(live_valid, table.concat(live_errors, '; '))
    equal(live_core.id, 'sortie-onboarding-core-live')
    equal(live_core.version, '1.0.1')
    falsy(live_core.guide_only)
    equal(#live_core.steps, #core.steps)
    local live_c_kill
    for _, step in ipairs(live_core.steps) do
        if step.id == 'c_controlled_kill' then live_c_kill = step end
    end
    truthy(live_c_kill)
    equal(live_c_kill.profile, 'sortie_objective_c_device_kill_v1')
    contains(live_c_kill.instruction, '//exg profile')
    contains(live_c_kill.instruction, 'Ctrl-P')
    contains(live_c_kill.warning, 'Stationary')
    contains(live_c_kill.warning, 'improvise')

    local live_b_gates, live_b_key, live_complete
    for _, step in ipairs(live_core.steps) do
        if step.id == 'b_gates_1_4' then live_b_gates = step end
        if step.id == 'b_key' then live_b_key = step end
        if step.id == 'core_complete' then live_complete = step end
    end
    contains(live_b_gates.instruction, 'DO NOT open nearby B3 first')
    contains(live_b_gates.warning, 'forfeits the Key B objective')
    contains(live_b_key.warning, 'B1 > B2 > B3 > B4 > B5 > B6')
    contains(live_b_key.detail[1], '//exg skip')
    contains(live_complete.instruction, '//exg stop')
    contains(live_complete.warning, 'Ruspix 6/6')

    local calibrated = content.packs.sortie.landmarks
    local expected_gate_positions = {
        gate_b1={-60,35,-182}, gate_b2={-155,-60,-172},
        gate_b3={-100,197,-172}, gate_b4={-315,20,-162},
        gate_b5={-315,-60,-162}, gate_b6={-220,5,-172},
    }
    for id, expected in pairs(expected_gate_positions) do
        local landmark = calibrated[id]
        equal(landmark.x, expected[1]); equal(landmark.y, expected[2])
        equal(landmark.z, expected[3])
        equal(landmark.coordinate_semantics, 'live_entity_capture')
        equal(landmark.confidence, 'high_live_capture')
    end

    local key_b_recovery = require(
        'content.sortie.routes.key_b_recovery_live')
    local recovery_valid, recovery_errors = Schema.validate_route(
        key_b_recovery, content.packs.sortie.landmarks,
        content.packs.sortie.profiles, content.packs.sortie.objectives,
        content.packs.sortie.items, content.packs.sortie.key_items,
        content.packs.sortie,
        content.packs.sortie.route_reward_scopes['sortie-onboarding-core'])
    truthy(recovery_valid, table.concat(recovery_errors, '; '))
    equal(key_b_recovery.id, 'sortie-key-b-recovery-live')
    equal(key_b_recovery.version, '1.0.0')
    falsy(key_b_recovery.guide_only)
    equal(#key_b_recovery.run_transactions, 1)
    equal(key_b_recovery.run_transactions[1].rewind, 'b_gates_1_4')
    equal(key_b_recovery.run_transactions[1].goal.item, 'key_b')
    equal(#key_b_recovery.steps, 7)
    equal(key_b_recovery.steps[5].path[1], 'gate_b1')
    equal(key_b_recovery.steps[5].path[4], 'gate_b4')
    contains(key_b_recovery.steps[5].instruction,
        'DO NOT open nearby B3 first')
    equal(key_b_recovery.steps[6].completion.item, 'key_b')
    equal(key_b_recovery.steps[6].reward.scope, 'ground_floor')
    contains(key_b_recovery.steps[6].warning,
        'B1 > B2 > B3 > B4 > B5 > B6')

    local d_profile = require(
        'content.sortie.profiles.objective_d_demisang_clear_v1')
    local d_profile_valid, d_profile_errors =
        Schema.validate_profile(d_profile)
    truthy(d_profile_valid, table.concat(d_profile_errors, '; '))
    equal(d_profile.key, 'sortie_objective_d_demisang_clear_v1')
    equal(d_profile.canonical_id,
        'sortie-objective-d-demisang-clear-v1')
    truthy(d_profile.available)

    local combined = require(
        'content.sortie.routes.key_b_sheet_d_canary_live')
    local combined_profiles = {}
    for key, value in pairs(content.packs.sortie.profiles) do
        combined_profiles[key] = value
    end
    combined_profiles[d_profile.key] = d_profile
    local combined_scopes, combined_scope_errors =
        Schema.compose_reward_scopes(
            combined, content.packs.sortie.reward_scopes)
    local combined_landmarks, combined_landmark_errors =
        Schema.compose_landmarks(combined, content.packs.sortie.landmarks)
    equal(#combined_scope_errors, 0,
        table.concat(combined_scope_errors, '; '))
    equal(#combined_landmark_errors, 0,
        table.concat(combined_landmark_errors, '; '))
    local combined_valid, combined_errors = Schema.validate_route(
        combined, combined_landmarks, combined_profiles,
        content.packs.sortie.objectives, content.packs.sortie.items,
        content.packs.sortie.key_items, content.packs.sortie,
        combined_scopes)
    truthy(combined_valid, table.concat(combined_errors, '; '))
    equal(combined.id, 'sortie-key-b-sheet-d-canary-live')
    equal(combined.version, '2.0.0')
    falsy(combined.guide_only)
    equal(#combined.run_transactions, 2)
    equal(combined.run_transactions[1].goal.item, 'key_b')
    equal(combined.run_transactions[2].rewind, 'd_opening_party')
    equal(combined.run_transactions[2].goal.item, 'sheet_d')
    equal(#combined.steps, 20)
    for index = 5, 10 do
        equal(combined.steps[index].completion.kind, 'target_interaction')
    end
    equal(combined.steps[5].path[1], 'kb_start_east')
    equal(combined.steps[5].path[#combined.steps[5].path], 'gate_b1')
    equal(combined.steps[11].completion.item, 'key_b')
    equal(combined.steps[13].profile,
        'sortie_objective_d_demisang_clear_v1')
    contains(combined.steps[13].instruction, '//exg profile')
    contains(combined.steps[13].detail[1], 'Ctrl-P')
    contains(combined.steps[13].detail[2], 'Alt-P')
    contains(combined.steps[14].warning,
        'Demisang Deleterious is optional')
    equal(combined.steps[19].completion.item, 'sheet_d')
    equal(combined.steps[19].reward.scope, 'ground_floor')
    equal(combined.steps[20].completion.kind, 'all_temp_items')
    equal(#combined.steps[20].completion.items, 2)

    local d_live = require(
        'content.sortie.routes.sheet_d_demisang_live')
    local d_live_landmarks, d_live_landmark_errors =
        Schema.compose_landmarks(d_live, content.packs.sortie.landmarks)
    local d_live_scopes, d_live_scope_errors =
        Schema.compose_reward_scopes(d_live,
            content.packs.sortie.reward_scopes)
    equal(#d_live_landmark_errors, 0,
        table.concat(d_live_landmark_errors, '; '))
    equal(#d_live_scope_errors, 0,
        table.concat(d_live_scope_errors, '; '))
    local d_live_valid, d_live_errors = Schema.validate_route(
        d_live, d_live_landmarks, combined_profiles,
        content.packs.sortie.objectives, content.packs.sortie.items,
        content.packs.sortie.key_items, content.packs.sortie,
        d_live_scopes)
    truthy(d_live_valid, table.concat(d_live_errors, '; '))
    equal(d_live.id, 'sortie-sheet-d-demisang-live')
    equal(d_live.version, '1.0.0')
    equal(d_live.aliases[1], 'dclear')
    equal(#d_live.run_transactions, 1)
    equal(d_live.run_transactions[1].rewind, 'load_d_profile')
    equal(d_live.run_transactions[1].goal.item, 'sheet_d')
    equal(#d_live.steps, 14)
    equal(d_live.steps[5].profile,
        'sortie_objective_d_demisang_clear_v1')
    contains(d_live.steps[1].warning, 'Key B is already complete')
    contains(d_live.steps[5].instruction, 'Ctrl-P')
    contains(d_live.steps[5].warning, 'No ACK')
    contains(d_live.steps[11].warning, 'bonus-only')
    equal(d_live.steps[13].completion.item, 'sheet_d')
    equal(d_live.steps[14].completion.item, 'sheet_d')

    local sheet_d = content.routes['sortie-onboarding-sheet-d']
    equal(sheet_d.version, '0.4.0')
    truthy(sheet_d.allowed_zones[267])
    equal(#sheet_d.run_transactions, 1)
    equal(sheet_d.run_transactions[1].rewind, 'clear_demisang')
    equal(sheet_d.run_transactions[1].goal.item, 'sheet_d')
    local sheet_d_complete = sheet_d.steps[#sheet_d.steps]
    equal(sheet_d_complete.id, 'complete')
    equal(sheet_d_complete.completion.kind, 'all_temp_items')
    truthy(sheet_d_complete.completion.auto)
    equal(#sheet_d_complete.completion.items, 12)
    local sheet_d_reward
    for _, step in ipairs(sheet_d.steps) do
        if step.id == 'sheet_d' then sheet_d_reward = step.reward end
    end
    truthy(sheet_d_reward); equal(sheet_d_reward.scope, 'ground_floor')

    local postflight = require('content.sortie.routes.postflight_ruspix')
    local postflight_valid, postflight_errors = Schema.validate_route(
        postflight, content.packs.sortie.landmarks,
        content.packs.sortie.profiles, content.packs.sortie.objectives,
        content.packs.sortie.items, content.packs.sortie.key_items,
        content.packs.sortie)
    truthy(postflight_valid, table.concat(postflight_errors, '; '))
    equal(postflight.id, 'sortie-postflight-ruspix')
    truthy(postflight.allowed_zones[281]); falsy(postflight.allowed_zones[275])
    equal(#postflight.steps, 1)
    equal(postflight.steps[1].completion.kind, 'all_key_item')
    equal(postflight.steps[1].completion.item, 'ruspix_plate')
    truthy(postflight.steps[1].completion.auto)
    for id, route in pairs(content.routes) do
        local valid, route_errors = Schema.validate_route(
            route, content.packs.sortie.landmarks,
            content.packs.sortie.profiles, content.packs.sortie.objectives,
            content.packs.sortie.items, content.packs.sortie.key_items,
            content.packs.sortie,
            content.packs.sortie.route_reward_scopes[id])
        truthy(valid, id .. ': ' .. table.concat(route_errors, '; '))
    end
end)

test('route-local landmarks are composed privately for each route', function()
    local route_a = basic_route(); route_a.id='route-a'
    route_a.content = 'pack'
    route_a.landmarks = {checkpoint={name='Route A checkpoint',
        x=10,y=11,z=12,radius=4}}
    route_a.steps[1].waypoint = 'checkpoint'
    local route_b = basic_route(); route_b.id='route-b'
    route_b.content = 'pack'
    route_b.landmarks = {checkpoint={name='Route B checkpoint',
        x=20,y=21,z=22,radius=6}}
    route_b.steps[1].waypoint = 'checkpoint'
    local base = {pack_anchor={name='Pack anchor',x=0,y=0,z=0,radius=5}}
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),landmarks=base,
        route_a=route_a,route_b=route_b}
    local registry = {schema=1,packs={fixture_pack({id='pack',
        routes={{module='route_a'},{module='route_b'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value})
    equal(#errors, 0, table.concat(errors, '; '))
    local pack = content.packs.pack
    local landmarks_a = pack.route_landmarks['route-a']
    local landmarks_b = pack.route_landmarks['route-b']
    truthy(landmarks_a); truthy(landmarks_b)
    truthy(landmarks_a ~= landmarks_b)
    equal(landmarks_a.checkpoint.x, 10)
    equal(landmarks_b.checkpoint.x, 20)
    equal(landmarks_a.pack_anchor.x, 0)
    equal(landmarks_b.pack_anchor.x, 0)
    falsy(pack.landmarks.checkpoint,
        'route-local landmark must never leak into the pack catalog')
    truthy(type(pack.route_digests['route-a']) == 'string')
    truthy(type(pack.route_digests['route-b']) == 'string')
    landmarks_a.checkpoint.x = 99
    equal(landmarks_b.checkpoint.x, 20,
        'one route local composition must not mutate another route')
    falsy(pack.landmarks.checkpoint)
end)

test('route dependency fingerprints ignore unrelated pack additions', function()
    local route = basic_route(); route.id='dependency-route'
    route.content = 'pack'
    route.steps[1].waypoint = 'used_anchor'
    route.steps[3].objective = 'key_a'
    route.steps[3].reward = {scope='used_floor',label='Fixture chest'}
    local items = make_catalog({{key='key_a',id=1,name='Key A'}})
    local landmarks = {
        used_anchor={name='Used',x=0,y=0,z=0,radius=5},
        unused_anchor={name='Unused',x=10,y=10,z=0,radius=5},
    }
    local objectives = {
        key_a={sector='A',reward='key_a',objective='Open the gate.'},
        unused={sector='Z',reward='key_a',objective='Unused fact.'},
    }
    local scopes = {
        used_floor=reward_scope(),
        unused_floor={label='Unused floor',regions={{kind='z_band',
            zones={[1]=true},min=-200,max=-100}}},
    }
    local modules = {items=items,key_items=make_catalog({}),landmarks=landmarks,
        objectives=objectives,reward_scopes=scopes,route=route}
    local registry = {schema=1,packs={fixture_pack({id='pack',
        objectives='objectives',reward_scopes='reward_scopes',
        routes={{module='route'}}})}}
    local function load_digest()
        local content, errors = Loader.load(registry, Schema, function(name)
            return modules[name]
        end, {fingerprint=Fingerprint.value})
        equal(#errors, 0, table.concat(errors, '; '))
        return content.packs.pack.route_digests['dependency-route']
    end
    local original = load_digest()
    landmarks.unused_anchor.x = 11
    objectives.unused.objective = 'An unrelated addition changed.'
    scopes.unused_floor.label = 'Changed but still unused'
    equal(load_digest(), original,
        'unreferenced pack data must not invalidate an established route')
    landmarks.used_anchor.x = 1
    local landmark_changed = load_digest()
    truthy(landmark_changed ~= original,
        'a referenced landmark change must invalidate saved route state')
    landmarks.used_anchor.x = 0
    objectives.key_a.objective = 'The referenced objective changed.'
    truthy(load_digest() ~= original,
        'a referenced objective change must invalidate saved route state')
    objectives.key_a.objective = 'Open the gate.'
    scopes.used_floor.regions[1].min = -239
    truthy(load_digest() ~= original,
        'a referenced reward scope change must invalidate saved route state')
end)

test('local landmark override and malformed local data quarantine only their routes', function()
    local stable = basic_route(); stable.id='stable-route'
    stable.content = 'pack'
    stable.steps[1].waypoint = 'pack_anchor'
    local overriding = basic_route(); overriding.id='override-route'
    overriding.content = 'pack'
    overriding.landmarks = {pack_anchor={name='Imposter anchor',
        x=900,y=900,z=900,radius=1}}
    overriding.steps[1].waypoint = 'pack_anchor'
    local malformed = basic_route(); malformed.id='malformed-route'
    malformed.content = 'pack'
    malformed.landmarks = {broken={name='Broken local landmark',
        x=1,radius=-5}}
    malformed.steps[1].waypoint = 'broken'
    local base = {pack_anchor={name='Pack anchor',x=0,y=0,z=0,radius=5}}
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),landmarks=base,
        stable=stable,overriding=overriding,malformed=malformed}
    local registry = {schema=1,packs={fixture_pack({id='pack',
        routes={{module='stable'},{module='overriding'},
            {module='malformed'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value})
    truthy(content.routes['stable-route'])
    falsy(content.routes['override-route'])
    falsy(content.routes['malformed-route'])
    equal(content.packs.pack.landmarks.pack_anchor.x, 0)
    truthy(content.packs.pack.route_landmarks['stable-route'])
    falsy(content.packs.pack.route_landmarks['override-route'])
    falsy(content.packs.pack.route_landmarks['malformed-route'])
    equal(#errors, 2, table.concat(errors, '; '))
    local joined = table.concat(errors, '; ')
    contains(joined, 'route landmark pack_anchor cannot override pack data')
    contains(joined, 'route landmark broken requires both x and y')
    contains(joined, 'route landmark broken has invalid radius')
end)

test('every shipped modular profile descriptor validates independently', function()
    local modules = {
        'boss_aita','boss_aminon_normal','boss_degei','boss_dhartok',
        'boss_gartell','boss_ghatjot','boss_leshonn','boss_skomora',
        'boss_triboulex','objective_c_device_kill',
        'objective_c_device_kill_v1','objective_c_magic_burst_v1',
        'objective_d_demisang_clear',
        'objective_d_demisang_clear_v1',
    }
    local seen_keys, seen_ids = {}, {}
    for _, name in ipairs(modules) do
        local profile = require('content.sortie.profiles.' .. name)
        local valid, errors = Schema.validate_profile(profile)
        truthy(valid, name .. ': ' .. table.concat(errors, '; '))
        falsy(seen_keys[profile.key], 'duplicate profile key ' .. profile.key)
        falsy(seen_ids[profile.canonical_id],
            'duplicate canonical profile id ' .. profile.canonical_id)
        seen_keys[profile.key] = true
        seen_ids[profile.canonical_id] = true
    end
end)

test('temporary-item protocol order is append-only and canonical', function()
    local items = require('content.sortie.items')
    local expected = {
        {'key_a',9894},{'key_b',9895},{'key_c',9896},{'key_d',9897},
        {'plate_a',9898},{'plate_b',9899},{'plate_c',9900},{'plate_d',9901},
        {'sheet_a',9902},{'sheet_b',9903},{'sheet_c',9904},{'sheet_d',9905},
    }
    truthy(#items.ordered >= #expected)
    for index, pair in ipairs(expected) do
        equal(items.ordered[index].key, pair[1], 'item key at protocol slot ' .. index)
        equal(items.ordered[index].id, pair[2], 'item id at protocol slot ' .. index)
        equal(items.ordered[index].protocol_index, index)
        equal(items.by_key[pair[1]], items.ordered[index])
        equal(items.by_id[pair[2]], items.ordered[index])
    end
end)

test('Sortie key-item protocol appends Dull plate as diagnostic evidence', function()
    local key_items = require('content.sortie.key_items')
    local expected = {
        {'shiny_plate',3300},{'ruspix_plate',3328},{'dull_plate',3301},
    }
    equal(#key_items.ordered, #expected)
    for index, pair in ipairs(expected) do
        equal(key_items.ordered[index].key, pair[1])
        equal(key_items.ordered[index].id, pair[2])
        equal(key_items.ordered[index].protocol_index, index)
    end
    local diagnostic = key_items.diagnostics.entry_plate
    equal(diagnostic.primary, 'shiny_plate')
    equal(diagnostic.secondary, 'dull_plate')
    equal(diagnostic.primary_label, 'Shiny')
    equal(diagnostic.secondary_label, 'Dull')
    equal(diagnostic.missing_label, 'missing')
    equal(diagnostic.invalid_label, 'INVALID')
    equal(diagnostic.unknown_label, 'unknown')
end)

test('one broken route is quarantined without hiding an established route', function()
    local good = basic_route()
    good.content = 'pack'
    local bad = basic_route(); bad.id='broken-route'
    bad.content = 'pack'
    bad.steps[1].command = 'input /attack'
    local modules = {
        items=make_catalog({{key='key_a'}}), key_items=make_catalog({}),
        landmarks={}, profiles={}, good=good, bad=bad,
    }
    local registry = {schema=1,reserved_aliases={stable='test-route'},
        packs={fixture_pack({id='pack',profiles='profiles',routes={
            {module='good',aliases={'stable'}},
            {module='bad',aliases={'broken'}},
        }})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        local value = modules[name]
        if value == nil then error('missing ' .. name) end
        return value
    end, {fingerprint=Fingerprint.value})
    truthy(content.routes['test-route'])
    equal(content.aliases.stable, 'test-route')
    falsy(content.routes['broken-route'])
    falsy(content.aliases.broken)
    equal(#errors, 1); contains(errors[1], 'broken-route')
    contains(errors[1], 'unsupported field command')
end)

test('malformed discovered route and profile quarantine only themselves', function()
    local stable_route = basic_route(); stable_route.id='stable-route'
    stable_route.content = 'pack'
    local discovered_route = basic_route(); discovered_route.id='new-route'
    discovered_route.content = 'pack'
    discovered_route.aliases = {'new-alias'}
    discovered_route.steps[1].profile = 'new_profile'
    local bad_route = basic_route(); bad_route.id='bad-route'
    bad_route.content = 'pack'
    bad_route.steps[1].send_command = 'input /attack'
    local stable_profile = {schema=1,key='stable_profile',
        canonical_id='stable-profile',version='1.0.0',available=false}
    local new_profile = {schema=1,key='new_profile',
        canonical_id='new-profile',version='1.0.0',available=false}
    local bad_profile = {schema=1,key='bad_profile',
        canonical_id='bad;input-attack',version='1.0.0',available=true}
    local modules = {
        items=make_catalog({{key='key_a'}}), key_items=make_catalog({}), landmarks={}, stable_route=stable_route,
        new_route=discovered_route, bad_route=bad_route,
        stable_profile=stable_profile, new_profile=new_profile,
        bad_profile=bad_profile,
    }
    local registry = {schema=1,reserved_aliases={
            ['stable-alias']='stable-route', ['new-alias']='new-route'},
        packs={fixture_pack({id='pack',
        profile_modules={{module='stable_profile'}},
        routes={{module='stable_route',aliases={'stable-alias'}}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        local value = modules[name]
        if value == nil then error('missing ' .. name) end
        return value
    end, {fingerprint=Fingerprint.value,discover=function(_, kind)
        if kind == 'profiles' then
            return {{module='new_profile'},{module='bad_profile'}}
        end
        return {{module='new_route'},{module='bad_route'}}
    end})
    truthy(content.packs.pack)
    truthy(content.packs.pack.profiles.stable_profile)
    truthy(content.packs.pack.profiles.new_profile)
    falsy(content.packs.pack.profiles.bad_profile)
    truthy(content.routes['stable-route'])
    truthy(content.routes['new-route'])
    falsy(content.routes['bad-route'])
    equal(content.aliases['stable-alias'], 'stable-route')
    equal(content.aliases['new-alias'], 'new-route')
    equal(#errors, 2, table.concat(errors, '; '))
    local joined = table.concat(errors, '; ')
    contains(joined, 'bad_profile'); contains(joined, 'canonical')
    contains(joined, 'bad-route'); contains(joined, 'unsupported field send_command')
end)

test('discovery failure is reported while explicit content remains usable', function()
    local stable_route = basic_route(); stable_route.id='stable-route'
    stable_route.content = 'pack'
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),
        landmarks={},route=stable_route}
    local registry = {schema=1,packs={fixture_pack({id='pack',
        routes={{module='route'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value,discover=function(_, kind)
        if kind == 'routes' then error('directory unavailable') end
        return {}
    end})
    truthy(content.routes['stable-route'])
    equal(#errors, 1); contains(errors[1], 'route')
    contains(errors[1], 'discovery failed')
end)

test('lexically earlier discovered imposters cannot replace explicit identities', function()
    local old_route = basic_route('1.0.0'); old_route.id='protected-route'
    old_route.content = 'pack'
    old_route.aliases = {'protected'}
    local fake_route = basic_route('9.9.9'); fake_route.id='protected-route'
    fake_route.content = 'pack'
    fake_route.aliases = {'protected'}
    local old_profile = {schema=1,key='protected_profile',
        canonical_id='protected-profile',version='1.0.0',available=false}
    local fake_profile = {schema=1,key='protected_profile',
        canonical_id='protected-profile',version='9.9.9',available=true}
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),landmarks={},
        z_route=old_route,a_route=fake_route,
        z_profile=old_profile,a_profile=fake_profile}
    local registry = {schema=1,reserved_aliases={
        protected='protected-route'},packs={fixture_pack({id='pack',
        profile_modules={{module='z_profile'}},routes={{module='z_route'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value,discover=function(_, kind)
        if kind == 'profiles' then return {{module='a_profile'}} end
        return {{module='a_route'}}
    end})
    equal(content.routes['protected-route'].version, '1.0.0')
    equal(content.packs.pack.profiles.protected_profile.version, '1.0.0')
    equal(content.packs.pack.profiles.protected_profile.available, false)
    equal(content.aliases.protected, 'protected-route')
    local joined = table.concat(errors, '; ')
    contains(joined, 'duplicate route protected-route')
    contains(joined, 'duplicate profile descriptor protected_profile')
end)

test('path-derived identities reject a discovered file impersonating old content', function()
    local route = basic_route(); route.id='sortie-onboarding-core'
    route.content = 'sortie'
    route.aliases = {'onboarding'}
    local profile = {schema=1,key='sortie_objective_c_device_kill',
        canonical_id='sortie-objective-c-device-kill',version='1.0.0',
        available=true}
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),landmarks={},
        imposter_route=route,imposter_profile=profile}
    local registry = {schema=1,reserved_aliases={
        onboarding='sortie-onboarding-core'},packs={fixture_pack({id='sortie'})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value,discover=function(_, kind)
        if kind == 'profiles' then return {{module='imposter_profile',
            path='profiles/aaa.lua',identity='sortie_aaa'}} end
        return {{module='imposter_route',path='routes/aaa.lua',
            identity='sortie-aaa'}}
    end})
    falsy(content.routes['sortie-onboarding-core'])
    falsy(content.packs.sortie.profiles.sortie_objective_c_device_kill)
    falsy(content.aliases.onboarding)
    local joined = table.concat(errors, '; ')
    contains(joined, 'identity must be sortie-aaa')
    contains(joined, 'identity must be sortie_aaa')
end)

test('reserved aliases stay with their registered owner and unknown aliases are ignored', function()
    local owner = basic_route(); owner.id='owner-route'; owner.aliases={'home'}
    owner.content = 'pack'
    local imposter = basic_route(); imposter.id='aaa-imposter'
    imposter.content = 'pack'
    imposter.aliases={'home','unregistered'}
    local modules = {items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),
        landmarks={},owner=owner,imposter=imposter}
    local registry = {schema=1,reserved_aliases={home='owner-route'},
        packs={fixture_pack({id='pack',routes={{module='owner'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value,discover=function(_, kind)
        if kind == 'routes' then return {{module='imposter'}} end
        return {}
    end})
    equal(content.aliases.home, 'owner-route')
    falsy(content.aliases.unregistered)
    truthy(content.routes['aaa-imposter'],
        'a valid route remains usable even when its aliases are rejected')
    local joined = table.concat(errors, '; ')
    contains(joined, 'alias home is reserved for owner-route')
    contains(joined, 'unregistered alias unregistered')
end)

test('path-bearing route and profile declarations use data loader, never require', function()
    local route = basic_route(); route.id='pack-safe-route'
    route.content = 'pack'
    local profile = {schema=1,key='pack_safe_profile',
        canonical_id='pack-safe-profile',version='1.0.0',available=false}
    route.steps[1].profile = 'pack_safe_profile'
    local required, loaded = {}, {}
    local registry = {schema=1,packs={fixture_pack({id='pack',
        profile_modules={{module='profile.module',
            path='profiles/safe.lua',identity='pack_safe_profile'}},
        routes={{module='route.module',path='routes/safe.lua',
            identity='pack-safe-route'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        required[#required + 1] = name
        if name == 'items' then return make_catalog({{key='key_a'}}) end
        if name == 'key_items' then return make_catalog({}) end
        if name == 'landmarks' then return {} end
        error('content module escaped sandbox path: ' .. name)
    end, {fingerprint=Fingerprint.value,load_data=function(declaration)
        loaded[#loaded + 1] = declaration.path
        if declaration.path == 'profiles/safe.lua' then return profile end
        if declaration.path == 'routes/safe.lua' then return route end
        error('unexpected data path')
    end})
    equal(#errors, 0, table.concat(errors, '; '))
    truthy(content.routes['pack-safe-route'])
    truthy(content.packs.pack.profiles.pack_safe_profile)
    equal(#required, 3); equal(required[1], 'items')
    equal(required[2], 'key_items'); equal(required[3], 'landmarks')
    equal(#loaded, 2)
end)

test('pack dependency failure is quarantined without crashing other packs', function()
    local good = basic_route(); good.id='survivor'
    good.content = 'good'
    local modules = {
        items=make_catalog({{key='key_a'}}), key_items=make_catalog({}),
        landmarks={}, profiles={}, route=good,
        baditems='not-a-table',
    }
    local registry = {schema=1,packs={
        fixture_pack({id='bad',items='baditems',profiles='profiles'}),
        fixture_pack({id='good',profiles='profiles',routes={{module='route'}}}),
    }}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value})
    falsy(content.packs.bad)
    truthy(content.packs.good)
    truthy(content.routes.survivor)
    equal(#errors, 1); contains(errors[1], 'pack bad quarantined')
end)

test('duplicate pack ids are rejected without replacing the first pack', function()
    local modules = {
        items=make_catalog({{key='key_a'}}), key_items=make_catalog({}),
        landmarks={},
    }
    local registry = {schema=1,packs={
        fixture_pack({id='pack'}), fixture_pack({id='pack'}),
    }}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value})
    truthy(content.packs.pack)
    equal(#errors, 1, table.concat(errors, '; '))
    contains(errors[1], 'duplicate pack pack quarantined')
end)

test('a route claiming another pack is quarantined at its owner boundary', function()
    local imposter = basic_route(); imposter.id='foreign-route'
    imposter.content = 'other-pack'
    local modules = {
        items=make_catalog({{key='key_a'}}), key_items=make_catalog({}),
        landmarks={}, route=imposter,
    }
    local registry = {schema=1,packs={fixture_pack({id='pack',
        routes={{module='route'}}})}}
    local content, errors = Loader.load(registry, Schema, function(name)
        return modules[name]
    end, {fingerprint=Fingerprint.value})
    truthy(content.packs.pack)
    falsy(content.routes['foreign-route'])
    equal(#errors, 1, table.concat(errors, '; '))
    contains(errors[1], 'route content must be owning pack pack')
end)

test('catalog and route fingerprints bind pack evidence dependencies', function()
    local route = basic_route(); route.id='bound-route'; route.content='pack'
    local modules = {
        items=make_catalog({{key='key_a',id=10}}),
        key_items=make_catalog({{key='entry',id=20}}),
        landmarks={}, route=route,
    }
    local declaration = fixture_pack({id='pack',routes={{module='route'}}})
    local registry = {schema=1,packs={declaration}}
    local function identities()
        local content, errors = Loader.load(registry, Schema, function(name)
            return modules[name]
        end, {fingerprint=Fingerprint.value})
        equal(#errors, 0, table.concat(errors, '; '))
        return content.packs.pack.catalog_id,
            content.route_digests['bound-route']
    end
    local catalog_id, route_digest = identities()
    modules.items = make_catalog({{key='key_a',id=11}})
    local changed_catalog, changed_route = identities()
    truthy(changed_catalog ~= catalog_id)
    truthy(changed_route ~= route_digest)

    modules.items = make_catalog({{key='key_a',id=10}})
    declaration.run_seconds = 3660
    local restored_catalog, changed_pack_route = identities()
    equal(restored_catalog, catalog_id,
        'run duration must not masquerade as an item catalog change')
    truthy(changed_pack_route ~= route_digest,
        'route state must bind its owning pack runtime contract')
end)

test('schema rejects unknown paths, profiles, duplicate ids, and command fields', function()
    local route = basic_route()
    route.steps[1].path = {'missing-landmark'}
    route.steps[1].profile = 'missing-profile'
    route.steps[1].commands = {'anything'}
    route.steps[2].id = 'manual'
    local valid, errors = Schema.validate_route(route, {}, {})
    falsy(valid)
    local joined = table.concat(errors, '; ')
    contains(joined, 'unknown')
    contains(joined, 'duplicate step id')
    contains(joined, 'unsupported field commands')
end)

test('schema validates objective contracts and multi-item completion catalogs', function()
    local route = basic_route()
    route.steps[3].objective = 'key_a'
    route.steps[3].completion = {
        kind='all_temp_items',items={'key_a','plate_a'},auto=true,
    }
    route.steps[3].reward = {scope='fixture_floor',label='Fixture chest'}
    local items = {by_key={key_a={},plate_a={}}}
    local objectives = {
        key_a={sector='A',reward='key_a',objective='Open a gate.'},
    }
    local objective_ok, objective_errors = Schema.validate_objectives(
        objectives, items)
    truthy(objective_ok, table.concat(objective_errors, '; '))
    local scopes = assert(Schema.compose_reward_scopes(route,
        {fixture_floor=reward_scope()}))
    local fixture = {id='test',allowed_zones={[1]=true},
        instance_zones={[1]=true}}
    local valid, errors = Schema.validate_route(route, {}, {}, objectives, items,
        nil, fixture, scopes)
    truthy(valid, table.concat(errors, '; '))

    route.steps[3].completion.items = {'key_a','missing'}
    valid, errors = Schema.validate_route(route, {}, {}, objectives, items,
        nil, fixture, scopes)
    falsy(valid); contains(table.concat(errors, '; '), 'unknown completion item')
    route.steps[3].completion.items = {'plate_a'}
    valid, errors = Schema.validate_route(route, {}, {}, objectives, items,
        nil, fixture, scopes)
    falsy(valid); contains(table.concat(errors, '; '), 'objective reward is absent')
    route.steps[3].objective = 'missing_objective'
    valid, errors = Schema.validate_route(route, {}, {}, objectives, items,
        nil, fixture, scopes)
    falsy(valid); contains(table.concat(errors, '; '), 'unknown objective')
end)

test('schema validates bounded declarative run transactions fail closed', function()
    local items = {by_key={key_b={},sheet_b={},plate_c={},sheet_c={},sheet_d={}}}
    local function validate(route)
        local valid, errors = Schema.validate_route(route, {}, {}, {}, items)
        return valid, table.concat(errors, '; ')
    end
    local valid, joined = validate(transaction_route())
    truthy(valid, joined)

    local route = transaction_route()
    route.run_transactions[1].extra = true
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'unsupported field extra')

    route = transaction_route()
    route.run_transactions[2].id = route.run_transactions[1].id
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'duplicated')

    route = transaction_route()
    route.run_transactions[1].rewind = 'missing'
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'unknown rewind')

    route = transaction_route()
    route.run_transactions[1].goal.item = 'unknown'
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'invalid durable all-six goal')

    route = transaction_route()
    route.run_transactions[1].goal.kind = 'manual'
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'invalid durable all-six goal')

    route = transaction_route()
    route.run_transactions[1].rewind = 'b_key'
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'rewind must precede')

    route = transaction_route()
    route.run_transactions[2].goal = {kind='all_temp_item',item='key_b'}
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'duplicates a run transaction goal')

    route = transaction_route()
    route.run_transactions = {}
    valid, joined = validate(route)
    falsy(valid); contains(joined, 'non-empty array')

    route = transaction_route()
    local original = Fingerprint.value(route)
    route.run_transactions[1].rewind = 'entry'
    truthy(Fingerprint.value(route) ~= original,
        'transaction semantics must be part of route identity')
end)

test('multi-item transaction goals are set-equivalent but reject duplicates', function()
    local route = basic_route()
    route.steps[1].completion = {
        kind='all_temp_items',items={'key_a','plate_a'},auto=true,
    }
    route.run_transactions={{id='multi',rewind='manual',
        goal={kind='all_temp_items',items={'plate_a','key_a'}}}}
    local items = {by_key={key_a={},plate_a={}}}
    local valid, errors = Schema.validate_route(route, {}, {}, {}, items)
    falsy(valid, 'rewind step and goal step cannot be the same')
    contains(table.concat(errors, '; '), 'rewind must precede')

    route.steps[1].completion = {kind='manual'}
    route.steps[2].completion = {
        kind='all_temp_items',items={'key_a','plate_a'},auto=true,
    }
    valid, errors = Schema.validate_route(route, {}, {}, {}, items)
    truthy(valid, table.concat(errors, '; '))

    route.run_transactions[1].goal.items={'key_a','key_a'}
    valid, errors = Schema.validate_route(route, {}, {}, {}, items)
    falsy(valid); contains(table.concat(errors, '; '), 'invalid durable')
end)

test('guide_only is mandatory and command-shaped fields are unsupported everywhere', function()
    local missing = basic_route(); missing.guide_only = nil
    missing.command = 'input /attack'
    missing.steps[1].send_command = 'input /attack'
    missing.steps[1].completion.command = 'input /attack'
    local valid, errors = Schema.validate_route(missing, {}, {})
    falsy(valid)
    local joined = table.concat(errors, '; ')
    contains(joined, 'guide_only must be boolean')
    contains(joined, 'route has unsupported field command')
    contains(joined, 'step 1 has unsupported field send_command')
    contains(joined, 'completion has unsupported field command')
    local live = basic_route(); live.guide_only = false
    truthy(Schema.validate_route(live, {}, {}, {},
        {by_key={key_a={}}}),
        'explicit operational false is a valid guide_only declaration')
end)

local lifecycle_context = {
    is_leader=true, in_allowed_zone=true, route_active=true,
    source_ready=true, now=100,
}

test('profile bridge uses only structural route lifecycle gates', function()
    local sent = {}
    local catalog = {
        good={canonical_id='sortie-objective',available=true},
        planned={canonical_id='sortie-planned',available=false},
    }
    local bridge = Bridge.new(catalog, function(command) sent[#sent+1]=command end,
        {enabled=true})
    local ok, reason = bridge:reconcile('missing', false, lifecycle_context)
    falsy(ok); contains(reason, 'allowlisted')
    ok, reason = bridge:reconcile('planned', false, lifecycle_context)
    falsy(ok); contains(reason, 'not installed')
    bridge:set_enabled(false)
    ok, reason = bridge:reconcile('good', false, lifecycle_context)
    falsy(ok); contains(reason, 'disabled')
    bridge:set_enabled(true)
    local gates = {
        {'is_leader',false,'leader'}, {'in_allowed_zone',false,'zone'},
        {'route_active',false,'not active'},
    }
    for _, gate in ipairs(gates) do
        local context = {}
        for key, value in pairs(lifecycle_context) do context[key] = value end
        context[gate[1]] = gate[2]
        ok, reason = bridge:reconcile('good', false, context)
        falsy(ok, gate[1] .. ' should fail closed')
        contains(reason, gate[3])
    end
    equal(#sent, 0)

    local noisy = {
        is_leader=true,in_allowed_zone=true,route_active=true,
        player_status=1,all_clients_idle=false,sensor_quorum=false,
        encounter_active=true,activation_pending=true,
        partytactics_safe=false,
    }
    ok, reason = bridge:reconcile('good', true, noisy)
    truthy(ok, reason)
    equal(sent[1], 'lua i PartyTactics use sortie-objective')
end)

test('profile bridge emits each desired state once and disarms on travel', function()
    local sent = {}
    local bridge = Bridge.new({good={canonical_id='sortie-boss_safe-1',available=true}},
        function(command) sent[#sent+1]=command end, {enabled=true})
    local ok, reason = bridge:reconcile('good', false, lifecycle_context)
    truthy(ok, reason)
    equal(#sent, 1)
    equal(sent[1], 'lua i PartyTactics use sortie-boss_safe-1 inert')
    ok, reason = bridge:reconcile('good', false, lifecycle_context)
    falsy(ok); contains(reason, 'already emitted')
    equal(#sent, 1)
    truthy(bridge:reconcile('good', true, lifecycle_context))
    equal(#sent, 2)
    equal(sent[2], 'lua i PartyTactics use sortie-boss_safe-1')
    falsy(bridge:reconcile('good', true, lifecycle_context))
    equal(#sent, 2)
    truthy(bridge:reconcile(nil, false, lifecycle_context))
    equal(sent[3], 'lua i PartyTactics disarm')
    falsy(bridge:reconcile(nil, false, lifecycle_context))
    equal(#sent, 3)
    bridge:reset()
    truthy(bridge:reconcile('good', true, lifecycle_context))
    equal(sent[4], 'lua i PartyTactics use sortie-boss_safe-1')
end)

test('operator profile recovery exposes and dispatches the exact operation', function()
    local sent = {}
    local bridge = Bridge.new({
        good={canonical_id='sortie-objective-c-device-kill-v1',available=true},
        planned={canonical_id='sortie-planned',available=false},
    }, function(command) sent[#sent+1]=command end, {enabled=false})
    local ok, result = bridge:request_operator('good', true)
    truthy(ok, result)
    equal(result,
        'lua i PartyTactics use sortie-objective-c-device-kill-v1')
    equal(#sent, 1)
    equal(sent[1],
        'lua i PartyTactics use sortie-objective-c-device-kill-v1')
    ok, result = bridge:request_operator('good')
    truthy(ok, result, 'an explicit retry must not be duplicate-suppressed')
    equal(#sent, 2)
    equal(sent[2],
        'lua i PartyTactics use sortie-objective-c-device-kill-v1 inert')
    ok, result = bridge:request_operator('planned')
    falsy(ok); contains(result, 'not installed')
    ok, result = bridge:request_operator('missing')
    falsy(ok); contains(result, 'allowlisted')
    local unavailable = Bridge.new({
        good={canonical_id='safe',available=true},
    }, nil, {enabled=false})
    ok, result = unavailable:request_operator('good')
    falsy(ok); contains(result, 'dispatcher')
end)

test('profile bridge rejects command injection and stop is an exact emergency action', function()
    local sent = {}
    local bridge = Bridge.new({
        injected={canonical_id='safe; input /attack',available=true},
        whitespace={canonical_id='safe profile',available=true},
        uppercase={canonical_id='SAFE',available=true},
    }, function(command) sent[#sent+1]=command end, {enabled=true})
    for _, key in ipairs({'injected','whitespace','uppercase'}) do
        local ok, reason = bridge:reconcile(key, false, lifecycle_context)
        falsy(ok); contains(reason, 'invalid canonical')
        ok, reason = bridge:request_operator(key)
        falsy(ok); contains(reason, 'invalid canonical')
    end
    equal(#sent, 0)
    local ok, reason = bridge:emergency_stop()
    truthy(ok, reason)
    equal(#sent, 1)
    equal(sent[1], 'lua i PartyTactics off')
    falsy(bridge.current_profile)
    falsy(bridge.current_armed)
end)

test('bridge description shows exact automatic or recovery command', function()
    local bridge = Bridge.new({
        planned={canonical_id='planned',available=false},
        ready={canonical_id='ready',available=true},
    }, function() end, {enabled=false})
    local state, reason = bridge:describe(nil)
    equal(state, 'none'); contains(reason, 'travel step')
    state, reason = bridge:describe('missing')
    equal(state, 'none'); contains(reason, 'unknown profile key')
    state, reason = bridge:describe('planned')
    equal(state, 'planned'); contains(reason, 'not installed')
    state, reason = bridge:describe('ready')
    equal(state, 'manual'); equal(reason, '//pt use ready inert')
    state, reason = bridge:describe('ready', true)
    equal(state, 'manual'); equal(reason, '//pt use ready')
    bridge:set_enabled(true)
    state, reason = bridge:describe('ready', true)
    equal(state, 'auto'); equal(reason, '//pt use ready')
end)

test('route automation waits for its source and retries without blocking', function()
    local sent = {}
    local bridge = AutomationBridge.new(
        function(command) sent[#sent+1]=command end, {enabled=true})
    equal(bridge:describe({kind='sortie_superwarp',operation='device_a'}),
        'AUTO //sw so p a')
    local actions = {
        device_a='sw so p a',device_c='sw so p c',port='sw so p port',
    }
    local index = 0
    for operation, command in pairs(actions) do
        index = index + 1
        local token = 'route:step-' .. tostring(index)
        local ok, reason = bridge:reconcile(
            {kind='sortie_superwarp',operation=operation}, token,
            lifecycle_context)
        truthy(ok, reason)
        equal(sent[#sent], command)
        ok, reason = bridge:reconcile(
            {kind='sortie_superwarp',operation=operation}, token,
            lifecycle_context)
        falsy(ok); contains(reason, 'waiting before retry')
    end
    equal(#sent, 3)

    local retry_context = {}
    for key, value in pairs(lifecycle_context) do retry_context[key]=value end
    retry_context.now = lifecycle_context.now + 12
    local retried, retry_reason, attempt = bridge:reconcile(
        {kind='sortie_superwarp',operation='device_a'}, 'route:step-1',
        retry_context)
    truthy(retried,retry_reason); equal(attempt,2)
    equal(sent[4],'sw so p a')

    local missing_source = {}
    for key, value in pairs(lifecycle_context) do missing_source[key]=value end
    missing_source.source_ready=false
    local ok, reason = bridge:reconcile(
        {kind='sortie_superwarp',operation='device_b'}, 'no-source',
        missing_source)
    falsy(ok); contains(reason,'source is not in range')

    for _, action in ipairs({
        'sw so p a',
        {kind='raw',operation='device_a'},
    }) do
        local ok, reason = bridge:reconcile(action, 'safe-token',
            lifecycle_context)
        falsy(ok); contains(reason, 'invalid route action')
    end
    ok, reason = bridge:reconcile(
        {kind='sortie_superwarp',operation='a; input /attack'},
        'safe-token', lifecycle_context)
    falsy(ok); contains(reason, 'not allowlisted')
    ok, reason = bridge:reconcile(
        {kind='sortie_superwarp',operation='device_a'}, 'bad token!',
        lifecycle_context)
    falsy(ok); contains(reason, 'invalid route action')

    for _, gate in ipairs({
        {'is_leader',false,'leader'}, {'in_allowed_zone',false,'zone'},
        {'route_active',false,'not active'},
    }) do
        local context = {}
        for key, value in pairs(lifecycle_context) do context[key]=value end
        context[gate[1]]=gate[2]
        ok, reason = bridge:reconcile(
            {kind='sortie_superwarp',operation='device_a'},
            'gate-' .. gate[1], context)
        falsy(ok); contains(reason, gate[3])
    end
    equal(#sent, 4)

    bridge:reset()
    truthy(bridge:reconcile(
        {kind='sortie_superwarp',operation='device_a'}, 'route:step-1',
        lifecycle_context))
    equal(sent[5], 'sw so p a')
    bridge:set_enabled(false)
    ok, reason = bridge:reconcile(
        {kind='sortie_superwarp',operation='device_c'}, 'disabled',
        lifecycle_context)
    falsy(ok); contains(reason, 'disabled')
end)

local function sandbox_source(source, reported_size)
    local old_open = io.open
    io.open = function(_, mode)
        equal(mode, 'rb', 'sandbox must inspect content read-only')
        return {
            seek=function(_, position)
                equal(position, 'end')
                return reported_size or #source
            end,
            close=function() return true end,
        }
    end
    local compiler = loadstring or load
    local ok, value, reason = pcall(Sandbox.load, 'virtual_content.lua',
        function(path)
            equal(path, 'virtual_content.lua')
            return compiler(source, '@virtual_content.lua')
        end)
    io.open = old_open
    if not ok then error(value, 0) end
    return value, reason
end

local function sandbox_manifest(path)
    local old_open = io.open
    io.open = function(requested, mode)
        equal(requested, path)
        equal(mode, 'rb')
        return {
            seek=function(_, position)
                equal(position, 'end')
                return 512
            end,
            close=function() return true end,
        }
    end
    local started = os.clock()
    local ok, value, reason = pcall(Sandbox.load, path, loadfile)
    local elapsed = os.clock() - started
    io.open = old_open
    if not ok then error(value, 0) end
    return value, reason, elapsed
end

test('content sandbox accepts bounded computation returning only plain data', function()
    local value, reason = sandbox_source([[
        local start = tonumber('2')
        local total = start
        for index = 1, 20 do total = total + index end
        return {
            schema=1,
            title='safe',
            total=total,
            rendered=tostring(start),
            kind=type(total),
            nested={2, true, false},
        }
    ]])
    truthy(value, reason)
    equal(value.title, 'safe'); equal(value.total, 212)
    equal(value.rendered, '2'); equal(value.kind, 'number')
    equal(value.nested[1], 2)
end)

test('content sandbox exposes only three explicit pure conversion globals', function()
    local value, reason = sandbox_source([[
        return {
            tonumber_kind=type(tonumber),
            tostring_kind=type(tostring),
            type_kind=type(type),
            math_kind=type(math),
            string_kind=type(string),
            table_kind=type(table),
            pairs_kind=type(pairs),
            ipairs_kind=type(ipairs),
            next_kind=type(next),
            select_kind=type(select),
            unpack_kind=type(unpack),
            assert_kind=type(assert),
            error_kind=type(error),
            pcall_kind=type(pcall),
        }
    ]])
    truthy(value, reason)
    equal(value.tonumber_kind, 'function')
    equal(value.tostring_kind, 'function')
    equal(value.type_kind, 'function')
    for _, key in ipairs({'math_kind','string_kind','table_kind','pairs_kind',
        'ipairs_kind','next_kind','select_kind','unpack_kind','assert_kind',
        'error_kind','pcall_kind'}) do
        equal(value[key], 'nil', key .. ' must be absent')
    end
end)

test('content sandbox cannot access Windower, require, or host libraries', function()
    local attacks = {
        'return windower.ffxi.get_player()',
        "return require('lib.profile_bridge')",
        "return io.open('anything', 'w')",
        'return os.execute("anything")',
        'return debug.sethook(function() end)',
        'return package.path',
    }
    for index, source in ipairs(attacks) do
        local value, reason = sandbox_source(source)
        falsy(value, 'sandbox host-access case ' .. index .. ' succeeded')
        truthy(type(reason) == 'string' and reason ~= '',
            'sandbox host-access case ' .. index .. ' lacked an error')
    end
end)

test('content sandbox exposes no stateful or allocation-amplifying library helpers', function()
    local attacks = {
        'math.randomseed(1); return {}',
        "return {value=string.rep('x', 10)}",
        "return {value=table.concat({'a','b'})}",
        'math.huge = 1; return {}',
        'table.insert = nil; return {}',
        'string.lower = nil; return {}',
    }
    for index, source in ipairs(attacks) do
        local value, reason = sandbox_source(source)
        falsy(value, 'forbidden standard-library case ' .. index .. ' succeeded')
        contains(reason, 'nil value', 'forbidden standard-library case ' .. index)
    end
end)

test('content sandbox interrupts an unbounded loop', function()
    local value, reason = sandbox_source('while true do end')
    falsy(value)
    contains(reason, 'instruction limit exceeded')
end)

test('content sandbox fails closed when no instruction hook is available', function()
    local old_hook = debug.sethook
    debug.sethook = nil
    local ok, value, reason = pcall(sandbox_source, 'return {}')
    debug.sethook = old_hook
    truthy(ok, value)
    falsy(value)
    contains(reason, 'cannot enforce content instruction limit')
end)

test('content sandbox finitely rejects a pcall-swallowed instruction-limit manifest', function()
    local path = 'addons/ExpeditionGuide/tests/manifests/pcall_swallowed_limit.lua'
    local value, reason, elapsed = sandbox_manifest(path)
    falsy(value, 'manifest must never swallow the sandbox instruction limit')
    contains(reason, 'pcall', 'pcall must be absent from the content environment')
    truthy(elapsed < 5,
        ('malicious manifest did not fail finitely (%.3fs)'):format(elapsed))
end)

test('content sandbox rejects non-plain, cyclic, non-finite, and oversized data', function()
    local long_text = string.rep('x', 2049)
    local entries = {}
    for index = 1, 4097 do entries[index] = '1' end
    local cases = {
        {'return function() end', 'did not return a table'},
        {'return {callback=function() end}', 'contains function'},
        {'local value={}; value.self=value; return value', 'contains a cycle'},
        {'return {number=1e999}', 'non-finite'},
        {'return {text=' .. string.format('%q', long_text) .. '}', 'string exceeds'},
        {'local root={}; local cursor=root; for i=1,34 do cursor.child={}; cursor=cursor.child end; return root', 'nesting limit'},
        {'return {' .. table.concat(entries, ',') .. '}', 'node limit'},
        {'return setmetatable({}, {})', 'nil value'},
    }
    for index, case in ipairs(cases) do
        local value, reason = sandbox_source(case[1])
        falsy(value, 'sandbox non-plain case ' .. index .. ' succeeded')
        contains(reason, case[2], 'sandbox non-plain case ' .. index)
    end
    local value, reason = sandbox_source('return {}', 65537)
    falsy(value); contains(reason, 'size limit')
end)

test('every shipped route and profile manifest loads in the minimal sandbox', function()
    local paths = {
        'addons/ExpeditionGuide/content/sortie/routes/onboarding_core.lua',
        'addons/ExpeditionGuide/content/sortie/routes/onboarding_sheet_d.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_aita.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_aminon_normal.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_degei.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_dhartok.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_gartell.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_ghatjot.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_ghatjot_v1.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_leshonn.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_skomora.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_skomora_v1.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/boss_triboulex.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/objective_c_device_kill.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/objective_c_device_kill_v1.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/objective_c_magic_burst_v1.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/objective_d_demisang_clear.lua',
        'addons/ExpeditionGuide/content/sortie/profiles/objective_d_demisang_clear_v1.lua',
        'addons/ExpeditionGuide/content/sortie/routes/onboarding_core_live.lua',
        'addons/ExpeditionGuide/content/sortie/routes/key_b_recovery_live.lua',
        'addons/ExpeditionGuide/content/sortie/routes/key_b_sheet_d_canary_live.lua',
        'addons/ExpeditionGuide/content/sortie/routes/postflight_ruspix.lua',
        'addons/ExpeditionGuide/content/sortie/routes/two_boss_c_a_training.lua',
    }
    for _, path in ipairs(paths) do
        local value, reason = sandbox_manifest(path)
        truthy(value, path .. ': ' .. tostring(reason))
        truthy(type(value) == 'table')
    end
end)

test('state serialization is deterministic and rejects cycles', function()
    local one = Store.serialize({z=2,a=1,nested={b=true,a=false}})
    local two = Store.serialize({nested={a=false,b=true},a=1,z=2})
    equal(one, two)
    local cycle = {}; cycle.self = cycle
    local ok, reason = pcall(Store.serialize, cycle)
    falsy(ok); contains(reason, 'cyclic')
    ok, reason = pcall(Store.serialize, {unsafe=function() end})
    falsy(ok); contains(reason, 'unsupported')
end)

test('persisted state validation binds identity, digest, evidence, and waypoints', function()
    local route = basic_route('3.2.1')
    local digest = 'route-digest'
    local engine = Engine.new(route, nil, 5000, digest)
    engine:start(5000)
    engine:advance('manual', 'manual', 5001)
    local snapshot = engine:snapshot(5002)
    snapshot.completion_ready_for = 'quorum'
    snapshot.observed = nil
    local wrapper = {
        schema=2, addon_version='0.1.0', character='Dolomedes',
        active_route_id=route.id, route_state=snapshot,
        navigation_overrides={
            [route.id]={
                safe={x=1,y=2,z=3,confidence='live_entity',captured_at=5001},
                malformed={x='bad',y=2},
            },
            unknown_route={safe={x=9,y=9,z=9}},
        },
        recovery_required=true, saved_at=5002,
    }
    local options = {
        character='Dolomedes',routes={[route.id]=route},
        route_digests={[route.id]=digest},
        route_landmarks={[route.id]={
            safe={name='Safe waypoint',radius=5,z_tolerance=9},
        }},
    }
    local clean, reason, notes = StateValidation.sanitize(wrapper, options)
    truthy(clean, reason)
    truthy(clean.route_state)
    falsy(clean.route_state.completion_ready_for,
        'saved next permission requires matching sanitized evidence')
    equal(clean.navigation_overrides[route.id].safe.name, 'Safe waypoint')
    falsy(clean.navigation_overrides[route.id].malformed)
    falsy(clean.navigation_overrides.unknown_route)
    equal(notes.discarded_overrides, 2)

    snapshot.observed = {kind='sensor_quorum',note='all present',at=5002,
        satisfies_completion=true,run_id='old-run'}
    snapshot.completion_ready_run_id = 'old-run'
    snapshot.active_run_id = 'old-run'
    snapshot.run_started_at = 5000
    clean, reason = StateValidation.sanitize(wrapper, options)
    truthy(clean, reason)
    falsy(clean.route_state.completion_ready_for,
        'disk restore must discard per-foray completion authorization')
    falsy(clean.route_state.active_run_id)
    falsy(clean.route_state.run_started_at)
    falsy(clean.route_state.observed)
    truthy(clean.route_state.paused)

    local wrong_character = {}
    for key, value in pairs(wrapper) do wrong_character[key] = value end
    wrong_character.character = 'Achoo'
    clean, reason = StateValidation.sanitize(wrong_character, options)
    falsy(clean); contains(reason, 'identity')

    local changed_options = {}
    for key, value in pairs(options) do changed_options[key] = value end
    changed_options.route_digests = {[route.id]='changed-digest'}
    clean, reason, notes = StateValidation.sanitize(wrapper, changed_options)
    truthy(clean, reason)
    falsy(clean.route_state)
    truthy(notes.route_identity_reset)
end)

test('persisted state validation rejects malformed route state and cyclic input', function()
    local route = basic_route()
    local engine = Engine.new(route, nil, 5100, 'digest')
    engine:start(5100)
    local wrapper = {schema=2,character='Dolomedes',
        active_route_id=route.id,route_state=engine:snapshot(5101),
        navigation_overrides={}}
    local options = {character='Dolomedes',routes={[route.id]=route},
        route_digests={[route.id]='digest'},route_landmarks={[route.id]={}}}
    wrapper.route_state.current_index = 999
    local clean, reason = StateValidation.sanitize(wrapper, options)
    falsy(clean); contains(reason, 'current step')
    wrapper.route_state.current_index = 1
    wrapper.loop = wrapper
    clean, reason = StateValidation.sanitize(wrapper, options)
    falsy(clean); contains(reason, 'cycle')
end)

test('disk migration preserves durable progress but strips every foray authority', function()
    local route = transaction_route()
    local digest = Fingerprint.value(route)
    local engine = Engine.new(route, nil, 5200, digest)
    engine:start(5200)
    truthy(engine:bind_run('old-run',run_evidence('old-run',{
        key_b=true,sheet_b=true,sheet_c=true,sheet_d=true,
    }),5201))
    engine.state.current_index = 3
    engine:mark_observed('all_temp_item','all six key B',5202,true)
    truthy(engine:advance('all six key B','confirmed',5202))
    engine.state.completed.entry = {
        at=5201,resolution='manual',confidence='confirmed',durable=true,
    }
    engine:start_timer('foray-only', 60, 5203)
    engine:mark_observed('manual','old observation',5203,true)
    local wrapper = {
        schema=3,character='Dolomedes',active_route_id=route.id,
        route_state=engine:snapshot(5204),navigation_overrides={},saved_at=5204,
    }
    local options = {character='Dolomedes',routes={[route.id]=route},
        route_digests={[route.id]=digest},route_landmarks={[route.id]={}}}
    local clean, reason, notes = StateValidation.sanitize(wrapper, options)
    truthy(clean, reason); truthy(clean.route_state)
    truthy(clean.route_state.completed.b_key)
    falsy(clean.route_state.completed.entry,
        'a durable flag cannot make a manual step permanent')
    falsy(clean.route_state.active_run_id)
    falsy(clean.route_state.run_started_at)
    falsy(clean.route_state.observed)
    falsy(clean.route_state.completion_ready_for)
    equal(next(clean.route_state.timers), nil)
    truthy(clean.route_state.paused); truthy(clean.recovery_required)
    truthy(notes.foray_reset); falsy(notes.wrapper_migrated)

    local restored = Engine.new(route, clean.route_state, 5205, digest)
    local changed, _, rewind = restored:bind_run('fresh-run',
        run_evidence('fresh-run', {}), 5206)
    truthy(changed); equal(rewind, 2)
    equal(restored:current().id, 'b_start')
    truthy(restored.state.completed.b_key,
        'new-run rewind retains prior permanent evidence')
end)

test('legacy route-state migration imports only confirmed durable completion', function()
    local route = transaction_route()
    local digest = Fingerprint.value(route)
    local legacy = {
        schema=1,route_id=route.id,route_version=route.version,
        route_digest=digest,active=true,paused=false,complete=false,
        current_index=7,waypoint_index=1,started_at=5300,
        run_started_at=5300,last_seen_at=5301,last_transition_at=5301,
        completion_ready_for='c_sheet',observed={kind='all_temp_item'},
        completed={
            b_key={at=5301,resolution='proof',confidence='confirmed'},
            b_sheet={at=5301,resolution='skip',confidence='manual'},
            c_kill={at=5301,resolution='forged',confidence='confirmed'},
        },
        history={},timers={old={deadline_at=5400}},
    }
    local wrapper={schema=2,character='Dolomedes',active_route_id=route.id,
        route_state=legacy,navigation_overrides={},saved_at=5301}
    local clean, reason, notes = StateValidation.sanitize(wrapper, {
        character='Dolomedes',routes={[route.id]=route},
        route_digests={[route.id]=digest},route_landmarks={[route.id]={}},
    })
    truthy(clean, reason)
    truthy(clean.route_state.completed.b_key)
    falsy(clean.route_state.completed.b_sheet)
    falsy(clean.route_state.completed.c_kill)
    falsy(clean.route_state.active_run_id)
    equal(next(clean.route_state.timers), nil)
    truthy(notes.wrapper_migrated); truthy(notes.foray_reset)
end)

-- Fengari intentionally exposes no io.open.  This small deterministic file
-- system drives StateStore's real save/load code, including rename failure
-- paths, without touching anything outside this isolated test process.
local function with_fake_filesystem(body)
    local files = {}
    local controls = {}
    local old_open, old_remove, old_rename, old_loadfile =
        io.open, os.remove, os.rename, loadfile

    io.open = function(path, mode)
        mode = mode or 'r'
        if mode == 'r' then
            if files[path] == nil then return nil, 'file not found' end
            return {close=function() return true end}
        elseif mode == 'w' then
            local chunks = {}
            return {
                write=function(_, ...)
                    if controls.fail_write then
                        controls.fail_write = false
                        return nil, 'injected write failure'
                    end
                    for index = 1, select('#', ...) do
                        chunks[#chunks + 1] = tostring(select(index, ...))
                    end
                    return true
                end,
                flush=function()
                    if controls.fail_flush then
                        controls.fail_flush = false
                        return nil, 'injected flush failure'
                    end
                    return true
                end,
                close=function()
                    if controls.fail_close then
                        controls.fail_close = false
                        return nil, 'injected close failure'
                    end
                    files[path] = table.concat(chunks)
                    return true
                end,
            }
        end
        return nil, 'unsupported mode'
    end
    os.remove = function(path)
        files[path] = nil
        return true
    end
    os.rename = function(source, destination)
        if controls.fail_rename_source == source
            and controls.fail_rename_destination == destination then
            controls.fail_rename_source = nil
            controls.fail_rename_destination = nil
            return nil, 'injected rename failure'
        end
        if files[source] == nil then return nil, 'source missing' end
        if files[destination] ~= nil then return nil, 'destination exists' end
        files[destination] = files[source]
        files[source] = nil
        return true
    end
    loadfile = function(path)
        local payload = files[path]
        if payload == nil then return nil, 'file not found' end
        local compiler = loadstring or load
        return compiler(payload, '@' .. path)
    end

    local ok, reason = pcall(body, files, controls)
    io.open, os.remove, os.rename, loadfile =
        old_open, old_remove, old_rename, old_loadfile
    if not ok then error(reason, 0) end
end

test('atomic state save preserves backup and supports corrupt-primary recovery', function()
    with_fake_filesystem(function(files)
        local path = 'state.lua'
        local ok, reason = Store.save(path, {schema=1,generation=1})
        truthy(ok, reason)
        local first = Store.load(path)
        equal(first.generation, 1)
        ok, reason = Store.save(path, {schema=1,generation=2})
        truthy(ok, reason)
        local current = Store.load(path)
        local backup = Store.load(path .. '.bak')
        equal(current.generation, 2); equal(backup.generation, 1)
        files[path] = 'this is not valid Lua state'
        local corrupt = Store.load(path)
        falsy(corrupt)
        local recovered = Store.load(path .. '.bak')
        truthy(recovered); equal(recovered.generation, 1)
    end)
end)

test('backup recovery cannot resurrect prior-foray authorization', function()
    with_fake_filesystem(function(files)
        local route = transaction_route()
        local digest = Fingerprint.value(route)
        local engine = bound_transaction_engine(10, true)
        engine.state.route_digest = digest
        engine:start_timer('old-run-timer', 60, 5400)
        engine:mark_observed('manual','old permission',5400,true)
        local wrapper = {schema=3,character='Dolomedes',
            active_route_id=route.id,route_state=engine:snapshot(5400),
            navigation_overrides={},saved_at=5400}
        truthy(Store.save('foray.lua', wrapper))
        wrapper.saved_at = 5401
        truthy(Store.save('foray.lua', wrapper))
        files['foray.lua'] = 'corrupt primary'
        falsy(Store.load('foray.lua'))
        local backup = Store.load('foray.lua.bak')
        truthy(backup)
        local clean, reason = StateValidation.sanitize(backup, {
            character='Dolomedes',routes={[route.id]=route},
            route_digests={[route.id]=digest},route_landmarks={[route.id]={}},
        })
        truthy(clean, reason)
        falsy(clean.route_state.active_run_id)
        falsy(clean.route_state.observed)
        falsy(clean.route_state.completion_ready_for)
        equal(next(clean.route_state.timers), nil)
        truthy(clean.route_state.paused)
        local restored = Engine.new(route, clean.route_state, 5402, digest)
        local changed, _, rewind = restored:bind_run('new-run',
            run_evidence('new-run', {}), 5403)
        truthy(changed); equal(rewind, 2)
    end)
end)

test('failed state serialization leaves the last good primary intact', function()
    with_fake_filesystem(function(files)
        local path = 'state.lua'
        truthy(Store.save(path, {generation=9}))
        local cycle = {}; cycle.self = cycle
        local ok, reason = Store.save(path, cycle)
        falsy(ok); contains(reason, 'cyclic')
        local retained = Store.load(path)
        truthy(retained); equal(retained.generation, 9)
        falsy(files[path .. '.tmp'], 'failed save must remove temporary file')
    end)
end)

test('failed atomic replacement restores the previous primary', function()
    with_fake_filesystem(function(files, controls)
        local path = 'state.lua'
        truthy(Store.save(path, {generation=1}))
        truthy(Store.save(path, {generation=2}))
        controls.fail_rename_source = path .. '.tmp'
        controls.fail_rename_destination = path
        local ok, reason = Store.save(path, {generation=3})
        falsy(ok); contains(reason, 'injected rename failure')
        local retained = Store.load(path)
        truthy(retained); equal(retained.generation, 2)
        local backup = Store.load(path .. '.bak')
        truthy(backup); equal(backup.generation, 1,
            'an older backup must survive until primary replacement succeeds')
        falsy(files[path .. '.tmp'])
        falsy(files[path .. '.previous'])
    end)
end)

test('state write, flush, and close failures preserve the primary', function()
    for _, failure in ipairs({'fail_write','fail_flush','fail_close'}) do
        with_fake_filesystem(function(files, controls)
            local path = 'state.lua'
            truthy(Store.save(path, {generation=7}))
            controls[failure] = true
            local ok, reason = Store.save(path, {generation=8})
            falsy(ok); contains(reason, 'injected')
            local retained = Store.load(path)
            truthy(retained); equal(retained.generation, 7)
            falsy(files[path .. '.tmp'])
        end)
    end
end)

test('generic regions validate all supported shapes and inclusive boundaries', function()
    local z_band = {kind='z_band',zones={[133]=true,[189]=true},
        min=-240,max=-110}
    truthy(Region.validate(z_band))
    truthy(Region.contains(z_band,{zone=133,x=9999,y=-9999,z=-240}))
    truthy(Region.contains(z_band,{zone=189,x=0,y=0,z=-110}))
    falsy(Region.contains(z_band,{zone=275,x=0,y=0,z=-150}))
    falsy(Region.contains(z_band,{zone=133,x=0,y=0,z=-109.99}))

    local aabb = {kind='aabb',zones={[1]=true},min_x=-10,max_x=10,
        min_y=-20,max_y=20,min_z=-30,max_z=30}
    truthy(Region.contains(aabb,{zone=1,x=-10,y=20,z=30}))
    falsy(Region.contains(aabb,{zone=1,x=10.01,y=0,z=0}))

    local cylinder = {kind='cylinder',zones={[2]=true},x=5,y=-5,
        radius=10,min_z=-2,max_z=2}
    truthy(Region.contains(cylinder,{zone=2,x=15,y=-5,z=2}))
    falsy(Region.contains(cylinder,{zone=2,x=15.01,y=-5,z=0}))

    local polygon = {kind='polygon_prism',zones={[3]=true},
        points={{x=0,y=0},{x=10,y=0},{x=10,y=10},{x=0,y=10}},
        min_z=-5,max_z=5}
    truthy(Region.contains(polygon,{zone=3,x=5,y=5,z=0}))
    truthy(Region.contains(polygon,{zone=3,x=0,y=5,z=0}),
        'polygon boundary is intentionally inclusive')
    falsy(Region.contains(polygon,{zone=3,x=11,y=5,z=0}))
end)

test('region and reward-scope validation reject ambiguous or unbounded data', function()
    local invalid = {
        {kind='unknown',zones={[1]=true},min=0,max=1},
        {kind='z_band',zones={},min=0,max=1},
        {kind='z_band',zones={[1]=false},min=0,max=1},
        {kind='z_band',zones={[1]=true},min=1,max=1},
        {kind='z_band',zones={[1]=true},min=-math.huge,max=1},
        {kind='z_band',zones={[1]=true},min=0,max=1,extra=true},
        {kind='cylinder',zones={[1]=true},x=0,y=0,radius=-1,
            min_z=0,max_z=1},
        {kind='polygon_prism',zones={[1]=true},
            points={{x=0,y=0},{x=10,y=10},{x=0,y=10},{x=10,y=0}},
            min_z=0,max_z=1},
    }
    for _, value in ipairs(invalid) do
        local valid = Region.validate(value)
        falsy(valid)
    end
    local union = assert(Region.compile_scope({label='Two safe islands',regions={
        {kind='aabb',zones={[1]=true},min_x=0,max_x=10,
            min_y=0,max_y=10,min_z=0,max_z=10},
        {kind='cylinder',zones={[2]=true},x=100,y=100,radius=5,
            min_z=-2,max_z=2},
    }}))
    truthy(union.zones[1]); truthy(union.zones[2])
    truthy(Region.contains_scope(union,{zone=1,x=5,y=5,z=5}))
    truthy(Region.contains_scope(union,{zone=2,x=100,y=100,z=0}))
    falsy(Region.contains_scope(union,{zone=2,x=90,y=100,z=0}))
    falsy(Region.compile_scope({label='Bad',regions={},extra=true}))
    falsy(Region.compile_scope({label='FREEZE CHESTS',
        regions=reward_scope().regions}),
        'scope labels cannot contain reserved safety claims')
    falsy(Region.compile_scope({label='Floor\nREWARD SAFE',
        regions=reward_scope().regions}),
        'scope labels cannot inject HUD control lines')
    local widened = clone(union); widened.zones[3] = true
    falsy(Region.validate_scope(widened),
        'derived zone unions cannot broaden a scope')
end)

test('schema binds reward metadata only to proven item-receipt steps', function()
    local route = basic_route()
    route.steps[3].objective = 'key_a'
    route.steps[3].reward = {scope='fixture_floor',label='Key A chest'}
    local items = {by_key={key_a={}}}
    local objectives = {
        key_a={sector='A',reward='key_a',objective='Open the gate.'},
    }
    local scopes, scope_errors = Schema.compose_reward_scopes(route,
        {fixture_floor=reward_scope()})
    equal(#scope_errors, 0, table.concat(scope_errors, '; '))
    local pack = {id='test',allowed_zones={[1]=true},
        instance_zones={[1]=true}}
    local valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, scopes)
    truthy(valid, table.concat(errors, '; '))

    route.steps[3].reward = nil
    valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, {})
    falsy(valid); contains(table.concat(errors, '; '),
        'objective reward requires reward scope data')

    route.steps[3].reward = {scope='fixture_floor',label='Key A chest',
        command='input /target'}
    valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, scopes)
    falsy(valid); contains(table.concat(errors, '; '),
        'reward has unsupported field command')

    route.steps[3].reward = {scope='missing',label='Key A chest'}
    valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, scopes)
    falsy(valid); contains(table.concat(errors, '; '),
        'unknown reward scope')

    for _, spoof in ipairs({'Key A\nREWARD SAFE: 6/6',
        'FREEZE CHESTS', 'stable 2/2', ' Key A chest'}) do
        route.steps[3].reward = {scope='fixture_floor',label=spoof}
        valid, errors = Schema.validate_route(route, {}, {}, objectives,
            items, nil, pack, scopes)
        falsy(valid); contains(table.concat(errors, '; '),
            'reward label is invalid')
    end

    route.steps[3].reward = nil
    route.steps[3].objective = nil
    route.steps[1].objective = 'key_a'
    valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, {})
    truthy(valid, table.concat(errors, '; '),
        'a controlled manual action may name its objective without claiming receipt')

    route.steps[1].reward = {scope='fixture_floor',label='Wrong place'}
    valid, errors = Schema.validate_route(route, {}, {}, objectives,
        items, nil, pack, scopes)
    falsy(valid); contains(table.concat(errors, '; '),
        'reward requires all-temp-item receipt evidence')
end)

test('HUD flattens control characters so content cannot forge a safety line', function()
    local object = {value=nil}
    function object:show() end
    function object:hide() end
    function object:text(value) self.value=value end
    local texts = {new=function() return object end}
    local hud = HUD.new(texts, {}, {})
    hud:render({visible=true,version='1',mode='GUIDE',route='Route',
        step_index=1,step_count=1,area='A',time='59:00',fresh=6,
        party_exact=6,leader_exact=1,leader_expected=1,expected=6,
        state='ACTIVE',reward=('FREEZE CHESTS: test\nREWARD SAFE: forged '
            .. ('named failure; '):rep(20)),
        instruction='Wait.\nREWARD SAFE: forged',combat='OFF'})
    falsy(object.value:find('\nREWARD SAFE: forged',1,true),
        'embedded controls must never create an authoritative-looking line')
    contains(object.value,'FREEZE CHESTS: test REWARD SAFE: forged')
    for line in (object.value .. '\n'):gmatch('(.-)\n') do
        truthy(#line <= 106,
            'long exact reward diagnostics must remain visible on the HUD')
    end
end)

test('reward scopes compose privately and quarantine only dependent routes', function()
    local stable = basic_route(); stable.id='stable-route'; stable.content='pack'
    local dependent = basic_route(); dependent.id='dependent-route';
    dependent.content='pack'
    dependent.steps[3].reward={scope='bad_pack',label='Bad chest'}
    local local_good = basic_route(); local_good.id='local-good';
    local_good.content='pack'
    local_good.reward_scopes={local_floor=reward_scope()}
    local_good.steps[3].reward={scope='local_floor',label='Local chest'}
    local malformed = basic_route(); malformed.id='local-malformed';
    malformed.content='pack'
    malformed.reward_scopes={broken={label='Broken',regions={
        {kind='z_band',zones={[1]=true},min=1,max=1}}}}
    local overriding = basic_route(); overriding.id='local-override';
    overriding.content='pack'
    overriding.reward_scopes={ground_floor=reward_scope()}
    local missing = basic_route(); missing.id='missing-ref'; missing.content='pack'
    missing.steps[3].reward={scope='absent',label='Missing chest'}

    local scopes = {
        ground_floor=reward_scope(),
        bad_pack={label='Bad pack scope',regions={{kind='z_band',
            zones={[1]=true},min=9,max=9}}},
    }
    local modules = {
        items=make_catalog({{key='key_a'}}),key_items=make_catalog({}),
        landmarks={},reward_scopes=scopes,
        stable=stable,dependent=dependent,local_good=local_good,
        malformed=malformed,overriding=overriding,missing=missing,
    }
    local declaration = fixture_pack({id='pack',reward_scopes='reward_scopes',
        routes={{module='stable'},{module='dependent'},
            {module='local_good'},{module='malformed'},
            {module='overriding'},{module='missing'}}})
    local content, errors = Loader.load({schema=1,packs={declaration}},
        Schema,function(name) return modules[name] end,
        {fingerprint=Fingerprint.value})
    truthy(content.routes['stable-route'])
    truthy(content.routes['local-good'])
    falsy(content.routes['dependent-route'])
    falsy(content.routes['local-malformed'])
    falsy(content.routes['local-override'])
    falsy(content.routes['missing-ref'])
    truthy(#errors >= 4)
    local joined = table.concat(errors, '; ')
    contains(joined, 'bad_pack')
    contains(joined, 'route reward scope broken is invalid')
    contains(joined, 'cannot override pack data')
    contains(joined, 'absent')
    truthy(content.packs.pack.route_reward_scopes['local-good'].local_floor)
    falsy(content.packs.pack.reward_scopes.local_floor,
        'route-local scopes must never leak into pack data')
end)

local function reward_fixture(wall, receipt)
    wall, receipt = wall or 7000, receipt or 100
    local nonces, parts = {}, {}
    for _, name in ipairs(roster) do
        nonces[name] = 'entry-' .. name:lower()
        parts[#parts + 1] = name:lower() .. '=' .. nonces[name]
    end
    local cohort = table.concat(parts, '|')
    local scope = assert(Region.compile_scope({
        label='Sortie ground floor',
        regions={
            {kind='z_band',zones={[133]=true,[189]=true,[275]=true},
                min=-240,max=-110},
            {kind='cylinder',zones={[275]=true},x=500,y=500,radius=5,
                min_z=-10,max_z=10},
        },
    }))
    local context = {
        pack_id='sortie',catalog_id='sortie-r2-abc12345',
        route_id='sortie-onboarding-core',route_digest='abc12345',
        step_id='a-key',scope_id='ground_floor',scope=scope,
        roster=clone(roster),expected_leader='Dolomedes',zone=275,
        run_id='sortie-run-abc12345',run_cohort=cohort,
        session_run_id='sortie-run-abc12345',session_cohort=cohort,
        engine_run_id='sortie-run-abc12345',now_wall=wall,
        entry_nonces=clone(nonces),
    }
    local reports = {}
    for _, name in ipairs(roster) do
        reports[name]={pack_id=context.pack_id,catalog_id=context.catalog_id,
            sender=name,timestamp=wall,sequence=40,zone=275,
            ready=true,party_exact=true,leader_exact=name == 'Dolomedes',
            entry_nonce=nonces[name],received_at=receipt,x=0,y=0,z=-150}
    end
    return context, reports
end

local function refresh_reward_reports(context, reports, sequence, receipt, wall)
    context.now_wall = wall
    for _, name in ipairs(roster) do
        reports[name].sequence = sequence
        reports[name].received_at = receipt
        reports[name].timestamp = wall
    end
end

test('reward gate requires two distinct cycles and stays safe on repeated renders', function()
    local context, reports = reward_fixture(7000, 100)
    local gate = RewardSafety.new()
    local status = gate:observe(context, reports, 100)
    falsy(status.safe); equal(status.progress, 1); equal(status.expected, 2)
    equal(status.reason, 'first_cycle')
    status = gate:observe(context, reports, 100.2)
    falsy(status.safe); equal(status.progress, 1)
    equal(#status.missing, 6,
        'an identical render is not a distinct all-six cycle')

    refresh_reward_reports(context, reports, 41, 100.4, 7000.4)
    status = gate:observe(context, reports, 100.4)
    falsy(status.safe); equal(status.reason, 'cycle_interval')
    refresh_reward_reports(context, reports, 42, 100.6, 7000.6)
    status = gate:observe(context, reports, 100.6)
    truthy(status.safe); equal(status.progress, 2); truthy(gate:is_open())

    status = gate:observe(context, reports, 100.7)
    truthy(status.safe,
        'HUD rerenders must not consume or flicker a current proof')
    reports.Dolomedes.sequence = 43
    reports.Dolomedes.received_at = 101.1
    reports.Dolomedes.timestamp = 7001.1
    context.now_wall = 7001.1
    status = gate:observe(context, reports, 101.1)
    truthy(status.safe,
        'a partially refreshed but wholly valid cohort remains safe')
    for _, name in ipairs(roster) do
        if name ~= 'Dolomedes' then
            reports[name].sequence = 43
            reports[name].received_at = 101.2
            reports[name].timestamp = 7001.2
        end
    end
    context.now_wall = 7001.2
    status = gate:observe(context, reports, 101.2)
    truthy(status.safe, 'a full fresh cycle rolls the in-memory baseline')
    gate:reset('route paused')
    falsy(gate:is_open()); equal(gate:status().progress, 0)
end)

test('reward gate aggregates exact offending names and revokes immediately', function()
    local context, reports = reward_fixture(7100, 200)
    local gate = RewardSafety.new()
    gate:observe(context,reports,200)
    refresh_reward_reports(context,reports,41,200.6,7100.6)
    truthy(gate:observe(context,reports,200.6).safe)

    reports.Tackleberry.timestamp = 7097
    reports.Smalls.timestamp = 7097
    local status = gate:observe(context,reports,200.7)
    falsy(status.safe); equal(status.reason,'report_wall_clock_stale')
    equal(table.concat(status.missing,','),'Tackleberry,Smalls')
    falsy(gate:is_open())

    context, reports = reward_fixture(7200,300)
    reports.Tackleberry.z = -100
    reports.Achoo.z = -100
    status = RewardSafety.new():observe(context,reports,300)
    falsy(status.safe); equal(status.reason,'report_out_of_scope')
    equal(table.concat(status.missing,','),'Tackleberry,Achoo')

    status = RewardSafety.new():observe(context,nil,300)
    equal(status.reason,'reports_invalid_shape')
    equal(table.concat(status.missing,','),table.concat(roster,','))

    context, reports = reward_fixture(7250,350)
    reports.Tackleberry.timestamp = 7247
    reports.Smalls.z = -100
    status = RewardSafety.new():observe(context,reports,350)
    equal(status.reason,'report_wall_clock_stale')
    equal(table.concat(status.missing,','),'Tackleberry,Smalls')
    equal(#status.failures,2)
    equal(status.failures[1].reason,'report_wall_clock_stale')
    equal(table.concat(status.failures[1].names,','),'Tackleberry')
    equal(status.failures[2].reason,'report_out_of_scope')
    equal(table.concat(status.failures[2].names,','),'Smalls')

end)

test('any client large relocation revokes proof across approved OR regions', function()
    local context, reports = reward_fixture(7260,360)
    local gate = RewardSafety.new()
    gate:observe(context,reports,360)
    refresh_reward_reports(context,reports,41,360.6,7260.6)
    truthy(gate:observe(context,reports,360.6).safe)
    refresh_reward_reports(context,reports,42,361.2,7261.2)
    reports.Smalls.x, reports.Smalls.y, reports.Smalls.z = 500,500,0
    local status = gate:observe(context,reports,361.2)
    falsy(status.safe); equal(status.reason,'report_large_relocation')
    equal(table.concat(status.missing,','),'Smalls')
    equal(status.progress,1)
    refresh_reward_reports(context,reports,43,361.8,7261.8)
    truthy(gate:observe(context,reports,361.8).safe,
        'a relocation needs a new second complete cycle')
end)

test('reward gate fails closed across party, nonce, age, and run invariants', function()
    local function rejected(mutator, expected_reason, expected_names)
        local context, reports = reward_fixture(7300,400)
        mutator(context,reports)
        local status = RewardSafety.new():observe(context,reports,400)
        falsy(status.safe)
        equal(status.reason,expected_reason)
        if expected_names then
            equal(table.concat(status.missing,','),expected_names)
        end
    end
    rejected(function(_,reports)
        reports.Kickpuncher.party_exact=false
        reports.Barneystinson.party_exact=false
    end,'report_not_ready','Kickpuncher,Barneystinson')
    rejected(function(_,reports)
        reports.Dolomedes.leader_exact=false
    end,'report_leader_mismatch','Dolomedes')
    rejected(function(_,reports)
        reports.Achoo.entry_nonce='different-entry'
    end,'report_nonce_mismatch','Achoo')
    rejected(function(_,reports)
        reports.Kickpuncher.received_at=397
        reports.Smalls.received_at=397
    end,'report_receipt_stale','Kickpuncher,Smalls')
    rejected(function(_,reports)
        reports.Barneystinson.zone=133
    end,'report_context_mismatch','Barneystinson')
    rejected(function(context)
        context.entry_nonces=nil
    end,'entry nonce map does not match run cohort')
    rejected(function(context)
        context.engine_run_id='sortie-run-other'
    end,'run identity invariant failed')
    rejected(function(context)
        context.session_cohort=context.session_cohort .. '-other'
    end,'run cohort invariant failed')

    local context, reports = reward_fixture(7400,500)
    local gate = RewardSafety.new()
    gate:observe(context,reports,500)
    refresh_reward_reports(context,reports,41,500.6,7400.6)
    truthy(gate:observe(context,reports,500.6).safe)
    context = clone(context); context.step_id='a-plate'
    local status = gate:observe(context,reports,500.7)
    falsy(status.safe); equal(status.reason,'context_changed')
    equal(status.progress,1,
        'a valid changed context starts over rather than inheriting proof')
end)

test('party receipt time is monotonic-local and never enters the wire contract', function()
    local party = PartyState.new(roster, party_pack)
    local value = report('Dolomedes',8000,1)
    truthy(party:update(value,25.5))
    equal(party.reports.Dolomedes.received_at,25.5)
    falsy(party:update(report('Dolomedes',8001,2),25.4),
        'a reordered local receipt clock cannot replace accepted evidence')
    equal(party.reports.Dolomedes.received_at,25.5)
    local wire = Protocol.state(value)
    falsy(wire:find('25.5',1,true),
        'local receipt time must not be sent over IPC')
end)

test('sensor readiness requires finite three-axis position evidence', function()
    local coordinates = {
        {x=0/0,y=0,z=0}, {x=0,y=math.huge,z=0},
        {x=0,y=0,z=-math.huge}, {x='0',y=0,z=0},
    }
    for _, position in ipairs(coordinates) do
        local api = {ffxi={
            get_player=function() return {name='Dolomedes',id=1,status=0} end,
            get_info=function() return {zone=275} end,
            get_mob_by_target=function() return position end,
            get_items=function() return {} end,
            get_key_items=function() return {} end,
        }}
        local snapshot = Sensors.snapshot(api, 9000)
        truthy(snapshot)
        falsy(snapshot.ready,
            'non-finite or non-numeric xyz must make the report unready')
    end
end)

print(('-'):rep(72))
print(('ExpeditionGuide Lua tests: %d/%d passed'):format(passed, total))
if #failures > 0 then
    print('Failures:')
    for _, failure in ipairs(failures) do
        print(('  - %s: %s'):format(failure.name, failure.reason))
    end
    os.exit(1)
end
