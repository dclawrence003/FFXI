local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local profile = module('profiles/locus-dire-bats-tomb-signet/profile.lua')
local identity = module(
    'data/profile_identities/locus-dire-bats-tomb-signet.lua')
local util = module('lib/util.lua')
local schema = module('lib/schema.lua')
local compiler = module('lib/compiler.lua')

assert(profile.id == 'locus-dire-bats-tomb-signet')
assert(profile.version == '1.8.1')
assert(profile.policy_id == 'pt-locus-bats-signet')
assert(profile.easyfarm == nil,
    'Signet derivative must not acquire an EasyFarm owner')
assert(identity.ordinal == 20 and identity.id == profile.id)
assert(identity.policy_id == profile.policy_id)
assert(table.concat(identity.aliases, ',')
    == 'locusbats-signet,locus-signet,signetbats')
assert(table.concat(profile.aliases, ',')
    == table.concat(identity.aliases, ','))

local validation = schema.validate(util, profile, profile.id)
assert(#validation == 0, table.concat(validation, '\n'))
local plan, compile_errors = compiler.compile(util, schema, profile)
assert(plan and #compile_errors == 0, table.concat(compile_errors, '\n'))

assert(profile.members.Dolomedes.main_job == 'COR')
for name, member in pairs(profile.members) do
    assert(member.sub_jobs == nil,
        name..' subjob recommendations must not become apply gates')
end

assert(#profile.combat.attackers == 6 and #profile.combat.targeters == 6)
assert(profile.combat.movement == 'stationary')
assert(profile.combat.puller == 'Tackleberry')
assert(profile.support.brd.preset == 'locusbats')
assert(profile.support.rdm.preset == 'locusbats-protect')
assert(profile.support.geo.mode == 'leanmanaged')
assert(profile.support.geo.indi == 'Fury')
assert(profile.support.geo.geo == 'Frailty')
assert(profile.support.pld.preset == 'off')
assert(profile.support.pld.native_tank == false,
    'generic PLD AutoTank must not spend the next pull\'s Flash mid-combat')
assert(profile.support.dnc.preset == 'locusbats')
assert(profile.offense.Dolomedes.weapon_mode == 'DualEvis'
    and profile.offense.Dolomedes.ws == 'Evisceration',
    'Dolo must use the Tauret/Gleti dual-wield Evisceration lane')

assert(profile.gearswap_adapter.id == profile.id)
assert(profile.gearswap_adapter.version == profile.version)
assert(profile.gearswap_adapter.controller == 'locus-signet')
assert(profile.gearswap_adapter.lifecycle_authorization == true)
assert(profile.gearswap_adapter.lifecycle_stop_fences['*'] == 'sk stoppt')
assert(profile.gearswap_adapter.lifecycle_stop_fences.Dolomedes
    == 'jk stoppt')
assert(profile.gearswap_adapter.lifecycle_stop_fences.Tackleberry
    == 'lp retirept')
assert(table.concat(profile.gearswap_adapter.actions, ',')
    == 'operator,suspend,resume,opener-arm,opener-release,companion-ready,keeper-instance')
assert(profile.gearswap_adapter.protocol == 2)
assert(profile.preflight.required_before_combat == false)
assert(profile.preflight.zone == 190)
local advisory_text = table.concat(profile.advisories, '\n'):lower()
assert(advisory_text:find('when any member is missing signet', 1, true))
assert(advisory_text:find('initial all-missing profile load', 1, true))
assert(advisory_text:find('already-buffed members count complete', 1, true))
assert(advisory_text:find('one full partytactics reapply', 1, true))
assert(advisory_text:find('raw signetkeeper reload', 1, true))
assert(advisory_text:find(
    'interrupted staff timer and cycle restart safely at cycle 1', 1, true))

for name, requirement in pairs(profile.preflight.members) do
    assert(requirement.controller.name == 'locus-signet')
    assert(requirement.controller.protocol == 2)
    local staff = false
    for _, item in ipairs(requirement.items or {}) do
        if item.name == 'Kgd. Signet Staff' then
            staff = item.minimum == 1 and item.bag_group == 'equippable'
        end
    end
    assert(staff, name..' lacks exact equippable Signet staff diagnostic')
end
local dolo_items = profile.preflight.members.Dolomedes.items
assert(dolo_items[2].name == 'Jubilee Ring'
    and dolo_items[2].bag_group == 'equippable')

local dolo_commands = table.concat(plan.members.Dolomedes.commands, '\n')
assert(dolo_commands:find(
    'gs c ptgs activate locus-dire-bats-tomb-signet 1.8.1', 1, true))
assert(dolo_commands:find('gs c weapons DualEvis; wait 1; '
    ..'aws2 aftermath off; aws2 use Evisceration; aws2 tp 1000', 1, true))
assert(not dolo_commands:find('EasyFarm', 1, true))

local tackle_commands = table.concat(plan.members.Tackleberry.commands, '\n')
assert(tackle_commands:find('gs c unset AutoTankMode', 1, true),
    'Locus Signet must reserve Flash exclusively for LocusPuller')
assert(tackle_commands:find('gs c set AutoBuffMode Auto', 1, true),
    'reserving Flash must not disable Tackleberry\'s native buff upkeep')
assert(tackle_commands:find(
    'gs c pstartpld off', 1, true),
    'frozen shared PLD presets must remain outside the profile-local sustain lane')
assert(not tackle_commands:find('gs c pstartpld locusbats', 1, true),
    'Locus Signet must not mutate or invoke the frozen locusbats PLD preset')

local unsafe = module('profiles/locus-dire-bats-tomb-signet/profile.lua')
unsafe.gearswap_adapter.lifecycle_stop_fences['*'] = 'sk stoppt;pc on'
local unsafe_plan, unsafe_errors = compiler.compile(util, schema, unsafe)
assert(unsafe_plan == nil)
assert(table.concat(unsafe_errors, ' '):find(
    'two lower-case command tokens', 1, true))

local foreign = module('profiles/locus-dire-bats-tomb-signet/profile.lua')
foreign.gearswap_adapter.lifecycle_stop_fences.NotInRoster = 'sk stoppt'
local foreign_plan, foreign_errors = compiler.compile(util, schema, foreign)
assert(foreign_plan == nil)
assert(table.concat(foreign_errors, ' '):find(
    'two lower-case command tokens', 1, true))

print('PartyTactics Locus Signet profile tests passed.')
