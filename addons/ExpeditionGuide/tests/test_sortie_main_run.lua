package.path = table.concat({
    'addons/ExpeditionGuide/?.lua',
    'addons/ExpeditionGuide/?/init.lua',
    package.path,
}, ';')

local Schema = require('lib.schema')
local route = require('content.sortie.routes.main_run')
local registry = require('content.registry')
local landmarks = require('content.sortie.landmarks')
local items = require('content.sortie.items')
local key_items = require('content.sortie.key_items')
local objectives = require('content.sortie.objectives')
local reward_scopes = require('content.sortie.reward_scopes')

local descriptor_modules = {
    'objective_c_magic_burst_v1',
    'objective_b_weapon_skill_v1',
    'objective_a_magic_kill_v1',
    'boss_skomora_v1',
    'boss_leshonn_v1',
    'boss_ghatjot_v1',
    'main_v1',
}
local profiles = {}
for _, name in ipairs(descriptor_modules) do
    local descriptor = require('content.sortie.profiles.' .. name)
    profiles[descriptor.key] = descriptor
end

local composed_landmarks, landmark_errors =
    Schema.compose_landmarks(route, landmarks)
assert(#landmark_errors == 0, table.concat(landmark_errors, '; '))
local composed_scopes, scope_errors =
    Schema.compose_reward_scopes(route, reward_scopes)
assert(#scope_errors == 0, table.concat(scope_errors, '; '))
local pack = {
    id='sortie',
    allowed_zones={
        [133]=true, [189]=true, [275]=true,
        [267]=true, [281]=true,
    },
    instance_zones={[133]=true, [189]=true, [275]=true},
}
local valid, errors = Schema.validate_route(route, composed_landmarks,
    profiles, objectives, items, key_items, pack, composed_scopes)
assert(valid, table.concat(errors, '; '))

assert(route.id == 'sortie-main-run')
assert(route.version == '1.2.0')
assert(route.guide_only == false)
assert(route.auto_start == true)
assert(route.target_selected_combat == false)
assert(#route.steps == 27)
assert(#route.run_transactions == 8)
assert(registry.reserved_aliases.run == route.id)
assert(registry.reserved_aliases.mainrun == route.id)
assert(registry.reserved_aliases.therun == route.id)

local expected_operations = {
    'device_c', 'port', 'port',
    'device_b', 'port', 'port',
    'device_a', 'port',
}
local actual_operations = {}
local by_id = {}
for index, step in ipairs(route.steps) do
    by_id[step.id] = step
    if index < 3 then
        assert(step.profile == nil,
            step.id .. ' must remain profile-free before entry')
        assert(step.profile_arm == nil,
            step.id .. ' must remain unarmed before entry')
    else
        assert(step.profile == 'sortie_main_v1',
            step.id .. ' must retain the single persistent profile')
        assert(step.profile_arm == true,
            step.id .. ' must retain the single armed lifecycle state')
    end
    local operator_text = table.concat({
        step.instruction or '', step.warning or '',
        table.concat(step.detail or {}, ' '),
    }, ' '):lower()
    assert(not operator_text:find('//pt', 1, true),
        step.id .. ' exposes an obsolete PartyTactics command')
    assert(not operator_text:find('//pc', 1, true),
        step.id .. ' exposes an obsolete PartyCombat command')
    assert(not operator_text:find('ctrl-p', 1, true),
        step.id .. ' exposes an obsolete force key')
    if step.detail then
        assert(#step.detail == 5, step.id .. ' needs five concise fact lines')
        assert(step.detail[1]:find('OBJECTIVE:', 1, true) == 1)
        assert(step.detail[2]:find('WHY:', 1, true) == 1)
        assert(step.detail[3]:find('SUCCESS:', 1, true) == 1)
        assert(step.detail[4]:find('AUTOMATION:', 1, true) == 1)
        assert(step.detail[5]:find('NEXT:', 1, true) == 1)
    end
    if step.automation then
        actual_operations[#actual_operations + 1] = step.automation.operation
    end
end
assert(#actual_operations == #expected_operations)
for index, operation in ipairs(expected_operations) do
    assert(actual_operations[index] == operation,
        ('automation %d expected %s, got %s'):format(
            index, operation, tostring(actual_operations[index])))
end

assert(by_id.c_shard.objective == 'shard_c_burst')
assert(by_id.c_metal.objective == 'metal_c_burst')
assert(by_id.skomora.objective == 'boss_skomora')
assert(by_id.b_shard.objective == 'shard_b_weapon_skill')
assert(by_id.leshonn.objective == 'boss_leshonn')
assert(by_id.a_shard.objective == 'shard_a_magic')
assert(by_id.a_metal.objective == 'metal_a_magic')
assert(by_id.ghatjot.objective == 'boss_ghatjot')
assert(by_id.complete.completion.kind == 'all_temp_items')
assert(table.concat(by_id.travel_c_camp.detail, ' '):find(
    'Skeletons or Ghouls', 1, true))
assert(by_id.b_shard.warning:find('Metal B', 1, true))
local acuex = table.concat(by_id.a_shard.detail, ' ')
    .. ' ' .. by_id.a_shard.warning
assert(acuex:find('Flat Blade', 1, true))
assert(acuex:find('Red Lotus Blade', 1, true))
assert(acuex:find('Fire IV', 1, true))
assert(not acuex:find('Fire V', 1, true))
assert(acuex:find('Aquaveil', 1, true))
assert(by_id.stage_skomora.completion.kind == 'relocation')
assert(by_id.exit_skomora.completion.kind == 'relocation')
assert(by_id.stage_leshonn.completion.kind == 'relocation')
assert(by_id.exit_leshonn.completion.kind == 'relocation')
assert(by_id.stage_ghatjot.completion.kind == 'relocation')
assert(by_id.stage_leshonn.warning:find('Metal B', 1, true))
assert(by_id.leshonn.warning:find('Wind or Lightning', 1, true))
local leshonn_text = by_id.leshonn.instruction .. ' '
    .. by_id.leshonn.warning .. ' '
    .. table.concat(by_id.leshonn.detail, ' ')
for _, required in ipairs{
    'Tackle alone directly in front',
    'behind or on a rear flank',
    'Dia', 'Elegy', 'Flash', 'Sentinel',
    'GEO bubbles and Box Step',
    'Kick holds WS',
    'Positioning is never an automation gate',
} do
    assert(leshonn_text:find(required, 1, true), required)
end

print('PASS - Sortie evolving C/B/A main run')
