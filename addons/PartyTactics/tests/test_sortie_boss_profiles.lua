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

local function joined(plan, name)
    return table.concat(plan.members[name].commands or {}, '\n')
end

local function check_common(id, ordinal, policy_id, version, target, rdm_preset)
    local profile = module('profiles/' .. id .. '/profile.lua')
    local plan, errors = compiler.compile(util, schema, profile)
    assert(plan, table.concat(errors or {}, ' '))
    local identity = module('data/profile_identities/' .. id .. '.lua')
    assert(identity.ordinal == ordinal)
    assert(identity.id == profile.id and identity.policy_id == policy_id)
    assert(table.concat(identity.aliases, ',') ==
        table.concat(profile.aliases, ','))
    assert(profile.version == version)
    assert(profile.runtime_owns_pull == true)
    assert(profile.gearswap_adapter == nil and profile.runtime == nil)
    assert(profile.preflight == nil)
    assert(util.count(profile.manual_actions) == 0)
    assert(profile.combat.movement == 'mobile')
    assert(#profile.combat.attackers == 6)
    assert(#profile.combat.targeters == 6)
    assert(profile.roles.primary_healer == 'Tackleberry')
    assert(profile.roles.backup_healer == 'Kickpuncher')
    assert(profile.roles.emergency_healer == 'Smalls')
    assert(profile.auto_select == nil, target)
    assert(joined(plan, 'Dolomedes'):find(
        'r2 roll1 chaos; r2 roll2 samurai', 1, true))
    assert(joined(plan, 'Dolomedes'):find(
        'gs c weapons DualSavage; wait 1; aws2 aftermath off;', 1, true))
    if id == 'sortie-boss-leshonn-v1' then
        assert(joined(plan, 'Tackleberry'):find(
            'gs c pstartpld manualsc Dolomedes', 1, true))
        assert(joined(plan, 'Tackleberry'):find(
            'gs c unset AutoTankMode', 1, true))
        assert(joined(plan, 'Tackleberry'):find(
            'gs c set AutoBuffMode Off', 1, true))
        assert(joined(plan, 'Barneystinson'):find(
            'gs c pstartbrd magicboss Tackleberry', 1, true))
    else
        assert(joined(plan, 'Tackleberry'):find(
            'gs c pstartpld locusbats Dolomedes', 1, true))
        assert(joined(plan, 'Barneystinson'):find(
            'gs c pstartbrd physical Tackleberry', 1, true))
    end
    assert(joined(plan, 'Smalls'):find(
        'gs c pstartrdm '..rdm_preset..' Tackleberry', 1, true))
    assert(joined(plan, 'Smalls'):find(
        'hb deactivateindoors off; hb disable cure; hb enable na;', 1, true))
    assert(joined(plan, 'Achoo'):find(
        'gs c autoindi Fury; gs c autogeo Frailty;', 1, true))
    assert(plan.policy_command == ('pc policy %s Dolomedes Tackleberry '
        ..'Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo '
        ..'Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo '
        ..'mobile - - -'):format(policy_id))
    for name, member in pairs(plan.members) do
        local commands = table.concat(member.commands or {}, '\n')
        assert(commands:find('gs c ptgs off', 1, true), name)
        assert(commands:find('aws2 exclude none', 1, true), name)
        local lower = commands:lower()
        assert(not lower:find('equip', 1, true), name)
        assert(not lower:find('gs c disable', 1, true), name)
        assert(not lower:find('gs c enable', 1, true), name)
    end
    return profile, plan
end

local skomora, skomora_plan = check_common(
    'sortie-boss-skomora-v1', 14, 'pt-sortie-skomora',
    '1.2.0', 'Skomora', 'sortiemelee')
assert(joined(skomora_plan, 'Kickpuncher'):find(
    'aws2 use Evisceration', 1, true))
local skomora_advice = table.concat(skomora.advisories, '\n')
assert(skomora_advice:find('three minutes', 1, true))
assert(skomora_advice:find('Setting the Stage', 1, true))
assert(skomora_advice:find('Explicit recovery profile only', 1, true))

local ghatjot, ghatjot_plan = check_common(
    'sortie-boss-ghatjot-v1', 15, 'pt-sortie-ghatjot',
    '1.2.0', 'Ghatjot', 'sortiemelee')
assert(joined(ghatjot_plan, 'Kickpuncher'):find(
    'gs c weapons Tauret', 1, true))
assert(joined(ghatjot_plan, 'Kickpuncher'):find(
    'aws2 use Dancing Edge', 1, true))
for _, name in ipairs({'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo'}) do
    local commands = joined(ghatjot_plan, name):lower()
    assert(not commands:find('water', 1, true), name)
    assert(not commands:find('leaden salute', 1, true), name)
    assert(not commands:find('hot shot', 1, true), name)
    assert(not commands:find('evisceration', 1, true), name)
end
local ghatjot_advice = table.concat(ghatjot.advisories, '\n')
assert(ghatjot_advice:find('DO NOT deal Water damage', 1, true))
assert(ghatjot_advice:find('Distortion and Darkness', 1, true))
assert(ghatjot_advice:find('Explicit recovery profile only', 1, true))

local leshonn, leshonn_plan = check_common(
    'sortie-boss-leshonn-v1', 19, 'pt-sortie-leshonn',
    '1.1.0', 'Leshonn', 'sortieacuex')
assert(joined(leshonn_plan, 'Kickpuncher'):find('aws2 off', 1, true))
assert(not joined(leshonn_plan, 'Kickpuncher'):find(
    'aws2 use Dancing Edge', 1, true))
local leshonn_advice = table.concat(leshonn.advisories, '\n')
assert(leshonn_advice:find('Zap', 1, true))
assert(leshonn_advice:find('Chokehold', 1, true))
assert(leshonn_advice:find('Wind or Lightning', 1, true))
assert(leshonn_advice:find('no Elegy, Dia, Flash', 1, true))
assert(leshonn_advice:find('never schedules Sentinel', 1, true))
assert(leshonn_advice:find('Tackle alone faces Leshonn', 1, true))

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
            'sortie-objective-a-magic-kill-v1.lua',
            'sortie-objective-b-weapon-skill-v1.lua',
            'sortie-boss-leshonn-v1.lua',
        }
    end,
    function() return true end,
    loadfile)
assert(#registry_errors == 0, table.concat(registry_errors, '\n'))
assert(#registry.identities == 19)
assert(registry.identities[14].id == skomora.id)
assert(registry.identities[15].id == ghatjot.id)
assert(registry.identities[19].id == leshonn.id)

print('PASS - Sortie Skomora, Ghatjot, and Leshonn executable profiles')
