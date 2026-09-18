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
local loader, reason = loadfile(BASE
    .. 'profiles/sortie-objective-d-demisang-clear-v1/profile.lua')
assert(loader, reason)
local profile = loader()
local plan, errors = compiler.compile(util, schema, profile)
assert(plan, table.concat(errors or {}, ' '))

local function joined(name)
    return table.concat(plan.members[name].commands or {}, '\n')
end

local identity = module(
    'data/profile_identities/sortie-objective-d-demisang-clear-v1.lua')
assert(identity.ordinal == 13)
assert(identity.id == profile.id)
assert(identity.policy_id == profile.policy_id)
assert(table.concat(identity.aliases, ',') == table.concat(profile.aliases, ','))

local registry, registry_errors = identity_extensions.extend(util,
    module('data/profile_registry.lua'), BASE .. 'data/profile_identities/',
    function()
        return {
            'vagary-direct-rancibus.lua',
            'sortie-objective-c-device-kill-v1.lua',
            'sortie-objective-d-demisang-clear-v1.lua',
            'ambuscade-2026-09-v2-hydra-alluttu.lua',
            'ambuscade-2026-09-v1-qutrub-bigwig.lua',
            'ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua',
        }
    end,
    function() return true end,
    loadfile)
assert(#registry_errors == 0, table.concat(registry_errors, '\n'))
assert(#registry.identities == 13)
assert(registry.identities[13].id == profile.id)
assert(profile.id == 'sortie-objective-d-demisang-clear-v1')
assert(profile.version == '1.1.0')
assert(profile.gearswap_adapter == nil)
assert(profile.runtime == nil)
assert(profile.preflight == nil)
assert(util.count(profile.manual_actions) == 0)
assert(profile.combat.movement == 'stationary')
assert(#profile.combat.attackers == 6)
assert(#profile.combat.targeters == 6)
assert(#profile.combat.target_exclusions == 0)
assert(profile.roles.primary_healer == 'Tackleberry')
assert(profile.roles.backup_healer == 'Kickpuncher')
assert(profile.roles.emergency_healer == 'Smalls')
assert(plan.policy_command ==
    'pc policy pt-sortie-d-demisang Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - -')

assert(joined('Dolomedes'):find(
    'r2 roll1 chaos; r2 roll2 samurai', 1, true))
assert(joined('Dolomedes'):find(
    'gs c weapons DualSavage; wait 1; aws2 aftermath off;', 1, true))
assert(joined('Tackleberry'):find(
    'gs c pstartpld locusbats Dolomedes', 1, true))
assert(joined('Kickpuncher'):find(
    'gs c pstartdnc physical Tackleberry', 1, true))
assert(joined('Barneystinson'):find(
    'gs c pstartbrd physical Tackleberry', 1, true))
assert(joined('Smalls'):find(
    'gs c pstartrdm locusbats Tackleberry', 1, true))
assert(joined('Smalls'):find(
    'hb deactivateindoors off; hb disable cure; hb enable na;', 1, true))
assert(joined('Achoo'):find('gs c pstartgeo leanmanaged', 1, true))
assert(joined('Achoo'):find(
    'gs c autoindi Fury; gs c autogeo Frailty;', 1, true))
assert(joined('Barneystinson'):find(
    'hb db off; hb as off; hb as attack off; hb off', 1, true))
assert(joined('Achoo'):find(
    'hb db off; hb as off; hb as attack off; hb off', 1, true))

for name, member in pairs(plan.members) do
    local commands = table.concat(member.commands or {}, '\n')
    assert(commands:find('gs c ptgs off', 1, true), name)
    assert(commands:find('aws2 exclude none', 1, true), name)
    assert(commands:find('aws2 on', 1, true), name)
    local lower = commands:lower()
    assert(not lower:find('equip', 1, true), name)
    assert(not lower:find('gs c disable', 1, true), name)
    assert(not lower:find('gs c enable', 1, true), name)
end

local advisory_text = table.concat(profile.advisories, '\n')
assert(advisory_text:find('no Demisang-name filter', 1, true))
assert(advisory_text:find('Demisang Deleterious is not required', 1, true))
assert(advisory_text:find('press Alt-P at any time', 1, true))
assert(advisory_text:find('Manual targets, movement', 1, true))
assert(advisory_text:find('five Converts', 1, true))
assert(advisory_text:find('Majesty lane', 1, true))

print('PASS - Sortie D regular-Demisang cooperative profile')
