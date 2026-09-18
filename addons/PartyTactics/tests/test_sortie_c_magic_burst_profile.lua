local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, reason = loadfile(BASE .. path)
    assert(loader, reason)
    return loader()
end

local util = module('lib/util.lua')
local schema = module('lib/schema.lua')
local compiler = module('lib/compiler.lua')
local identity_extensions = module('lib/identity_extensions.lua')
local profile = module(
    'profiles/sortie-objective-c-magic-burst-v1/profile.lua')
local plan, errors = compiler.compile(util, schema, profile)
assert(plan, table.concat(errors or {}, ' '))

local function joined(name)
    return table.concat(plan.members[name].commands or {}, '\n')
end

local identity = module(
    'data/profile_identities/sortie-objective-c-magic-burst-v1.lua')
assert(identity.ordinal == 16)
assert(identity.id == profile.id)
assert(identity.policy_id == profile.policy_id)
assert(table.concat(identity.aliases, ',') == table.concat(profile.aliases, ','))

local registry, registry_errors = identity_extensions.extend(util,
    module('data/profile_registry.lua'), BASE .. 'data/profile_identities/',
    function()
        return {
            'ambuscade-2026-09-v1-qutrub-bigwig.lua',
            'ambuscade-2026-09-v2-hydra-alluttu.lua',
            'ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua',
            'vagary-direct-rancibus.lua',
            'sortie-objective-c-device-kill-v1.lua',
            'sortie-objective-d-demisang-clear-v1.lua',
            'sortie-boss-skomora-v1.lua',
            'sortie-boss-ghatjot-v1.lua',
            'sortie-objective-c-magic-burst-v1.lua',
        }
    end,
    function() return true end,
    loadfile)
assert(#registry_errors == 0, table.concat(registry_errors, '\n'))
assert(#registry.identities == 16)
assert(registry.identities[16].id == profile.id)

assert(profile.id == 'sortie-objective-c-magic-burst-v1')
assert(profile.version == '1.3.0')
assert(profile.policy_id == 'pt-sortie-c-mb')
assert(profile.runtime_owns_pull == true)
assert(profile.gearswap_adapter.id == profile.id)
assert(profile.gearswap_adapter.version == '1.0.0')
assert(profile.gearswap_adapter.controller == 'sortie-c-mb')
assert(profile.gearswap_adapter.protocol == 1)
assert(profile.preflight.required_before_combat == false)
assert(profile.combat.movement == 'mobile')
assert(profile.auto_select == nil)
assert(#profile.combat.attackers == 4)
assert(#profile.combat.targeters == 2)
assert(plan.policy_command ==
    'pc policy pt-sortie-c-mb Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson Dolomedes,Kickpuncher mobile - - -')

assert(joined('Dolomedes'):find(
    'r2 roll1 tactician; r2 roll2 samurai', 1, true))
assert(joined('Dolomedes'):find(
    'gs c unset AutoWSMode; gs c weapons DualSavage; wait 1; aws2 off',
    1, true))
assert(joined('Tackleberry'):find(
    'gs c pstartpld locusbats Dolomedes', 1, true))
assert(joined('Kickpuncher'):find(
    'gs c pstartdnc tankheal Tackleberry', 1, true))
assert(joined('Barneystinson'):find(
    'gs c pstartbrd magicboss Tackleberry', 1, true))
assert(joined('Smalls'):find(
    'gs c pstartrdm off; gs c set AutoBuffMode Off', 1, true))
assert(joined('Achoo'):find(
    'gs c autoindi Refresh; gs c autogeo Haste;', 1, true))

for name, member in pairs(plan.members) do
    local commands = table.concat(member.commands or {}, '\n')
    assert(commands:find(
        'gs c ptgs activate sortie-objective-c-magic-burst-v1 1.0.0',
        1, true), name)
    assert(commands:find('aws2 off', 1, true), name)
    assert(not commands:find('aws2 on', 1, true), name)
    assert(profile.preflight.members[name].controller.name == 'sortie-c-mb')
end

local advice = table.concat(profile.advisories, '\n')
assert(advice:find('Cachaemic Bhoot', 1, true))
assert(advice:find('Only an observed Fragmentation packet', 1, true))
assert(advice:find('Explicit recovery profile only', 1, true))
assert(advice:find('never filter or cancel manual', 1, true))

print('PASS - Sortie C automatic Magic Burst profile')
