package.path = table.concat({
    'addons/ExpeditionGuide/?.lua',
    'addons/ExpeditionGuide/?/init.lua',
    package.path,
}, ';')

local Schema = require('lib.schema')
local route = require('content.sortie.routes.two_boss_c_a_training')
local registry = require('content.registry')
local landmarks = require('content.sortie.landmarks')
local items = require('content.sortie.items')
local key_items = require('content.sortie.key_items')
local objectives = require('content.sortie.objectives')
local reward_scopes = require('content.sortie.reward_scopes')
local c_burst = require(
    'content.sortie.profiles.objective_c_magic_burst_v1')
local a_magic = require(
    'content.sortie.profiles.objective_a_magic_kill_v1')
local skomora = require('content.sortie.profiles.boss_skomora_v1')
local ghatjot = require('content.sortie.profiles.boss_ghatjot_v1')

local composed_landmarks, landmark_errors =
    Schema.compose_landmarks(route, landmarks)
assert(#landmark_errors == 0, table.concat(landmark_errors, '; '))
local composed_scopes, scope_errors =
    Schema.compose_reward_scopes(route, reward_scopes)
assert(#scope_errors == 0, table.concat(scope_errors, '; '))
local profiles = {
    [c_burst.key]=c_burst,
    [a_magic.key]=a_magic,
    [skomora.key]=skomora,
    [ghatjot.key]=ghatjot,
}
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

assert(route.id == 'sortie-two-boss-c-a-training')
assert(route.aliases[1] == 'boss2')
assert(registry.reserved_aliases.boss2 == route.id)
assert(registry.reserved_aliases.twoboss == route.id)
assert(registry.reserved_aliases.ca == route.id)
assert(route.version == '2.1.0')
assert(route.guide_only == false)
assert(#route.run_transactions == 6)
assert(#route.steps == 18)
assert(route.steps[1].completion.kind == 'all_key_item')
assert(route.steps[4].id == 'c_objective_setup')
assert(route.steps[4].profile == 'sortie_objective_c_magic_burst_v1')
assert(route.steps[5].completion.item == 'shard_c')
assert(route.steps[5].profile == 'sortie_objective_c_magic_burst_v1')
assert(route.steps[6].completion.item == 'metal_c')
assert(route.steps[6].profile == 'sortie_objective_c_magic_burst_v1')
assert(route.steps[3].automation.operation == 'device_c')
assert(route.steps[4].profile_arm == true)
assert(route.steps[4].completion.kind == 'landmark')
assert(route.steps[4].instruction:find(
    '//pt use sortie-objective-c-magic-burst-v1 armed',1,true))
assert(route.steps[4].instruction:find(
    'Tackle pulls first automatically',1,true))
assert(not route.steps[5].instruction:find('Ctrl-P',1,true))
assert(route.steps[4].warning:find('never blocks',1,true))
assert(#route.steps[7].path >= 10)
assert(route.steps[8].profile == 'sortie_boss_skomora_v1')
assert(route.steps[8].profile_arm == true)
assert(route.steps[8].automation.operation == 'port')
assert(route.steps[8].completion.kind == 'target_interaction')
assert(route.steps[8].instruction:find(
    'Tackle pulls first automatically',1,true))
assert(route.steps[9].completion.item == 'shard_g')
assert(route.steps[10].automation.operation == 'port')
assert(route.steps[11].automation.operation == 'device_a')
assert(route.steps[12].id == 'a_objective_setup')
assert(#route.steps[12].path >= 9)
assert(route.steps[12].profile == 'sortie_objective_a_magic_kill_v1')
assert(route.steps[12].profile_arm == true)
assert(route.steps[12].instruction:find(
    'Tackle pulls first',1,true))
assert(route.steps[13].completion.item == 'shard_a')
assert(route.steps[13].profile == 'sortie_objective_a_magic_kill_v1')
assert(route.steps[14].completion.item == 'metal_a')
assert(route.steps[16].profile == 'sortie_boss_ghatjot_v1')
assert(route.steps[16].automation.operation == 'port')
assert(route.steps[16].instruction:find(
    'Tackle pulls first automatically',1,true))
assert(route.steps[17].completion.item == 'shard_e')
assert(route.steps[18].completion.kind == 'all_temp_items')
assert(route.steps[17].warning:find(
    'NO WATER DAMAGE', 1, true))

for _, step in ipairs(route.steps) do
    local text = table.concat({step.instruction or '', step.warning or ''}, ' ')
    assert(not text:find('REMA required', 1, true))
end

assert(skomora.available and skomora.canonical_id ==
    'sortie-boss-skomora-v1')
assert(ghatjot.available and ghatjot.canonical_id ==
    'sortie-boss-ghatjot-v1')
assert(c_burst.available and c_burst.canonical_id ==
    'sortie-objective-c-magic-burst-v1')
assert(a_magic.available and a_magic.canonical_id ==
    'sortie-objective-a-magic-kill-v1')

print('PASS - Sortie two-boss C/A training route')
