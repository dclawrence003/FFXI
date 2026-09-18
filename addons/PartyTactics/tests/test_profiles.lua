local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local util = module('lib/util.lua')
local schema = module('lib/schema.lua')
local compiler = module('lib/compiler.lua')
local profile_loader = module('lib/profile_loader.lua')
local action_api = module('lib/action_api.lua')
local sandbox = module('lib/sandbox.lua')
local fingerprint = module('lib/fingerprint.lua')
profile_registry = module('data/profile_registry.lua')

local function load_profile(id)
    local loader, load_error = loadfile(BASE..'profiles/'..id..'/profile.lua')
    assert(loader, load_error)
    return loader()
end

local function deep_copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do
        result[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return result
end

local function compile(id)
    local profile = load_profile(id)
    local plan, errors = compiler.compile(util, schema, profile)
    assert(plan, table.concat(errors or {}, ' '))
    return profile, plan
end

local function joined_commands(member)
    return table.concat(member.commands or {}, '\n')
end

local function plan_fingerprint(plan)
    local parts = {plan.id, plan.version, plan.policy_command}
    for _, name in ipairs(util.sorted_keys(plan.members)) do
        parts[#parts + 1] = name
        for _, command in ipairs(plan.members[name].commands or {}) do
            parts[#parts + 1] = command
        end
    end
    local text = table.concat(parts, string.char(30))
    local hash = 5381
    for index = 1, #text do
        hash = (hash * 33 + text:byte(index)) % 2147483647
    end
    return ('%08x'):format(hash)
end

local locus, locus_plan = compile('locus-dire-bats-tomb')
local limbus, limbus_plan = compile('limbus-119-stationary')
local v1, v1_plan = compile('ambuscade-2026-08-v1-breadwinner')
local route, route_plan = compile('dynamis-divergence-wave1-route-corsair')
local boss, boss_plan = compile('dynamis-divergence-wave1-boss-magic')
local genmei, genmei_plan = compile('escha-ruaun-genbu-genmei')
local kammavaca, kammavaca_plan = compile('escha-ruaun-kammavaca')
september_qutrub, september_qutrub_plan =
    compile('ambuscade-2026-09-v1-qutrub-bigwig')
september_hydra, september_hydra_plan =
    compile('ambuscade-2026-09-v2-hydra-alluttu')
september_qutrub_no_cait, september_qutrub_no_cait_plan =
    compile('ambuscade-2026-09-v1-qutrub-bigwig-no-cait')
rancibus, rancibus_plan = compile('vagary-direct-rancibus')
sortie_c, sortie_c_plan = compile('sortie-objective-c-device-kill-v1')

registry_by_id = {}
for ordinal, identity in ipairs(profile_registry.identities or {}) do
    assert(identity.ordinal == ordinal and not registry_by_id[identity.id])
    registry_by_id[identity.id] = identity
end
extension_identities = {
    module('data/profile_identities/ambuscade-2026-09-v1-qutrub-bigwig.lua'),
    module('data/profile_identities/ambuscade-2026-09-v2-hydra-alluttu.lua'),
    module('data/profile_identities/ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua'),
    module('data/profile_identities/vagary-direct-rancibus.lua'),
    module('data/profile_identities/sortie-objective-c-device-kill-v1.lua'),
}
qutrub_identity = extension_identities[1]
hydra_identity = extension_identities[2]
qutrub_no_cait_identity = extension_identities[3]
rancibus_identity = extension_identities[4]
sortie_c_identity = extension_identities[5]
assert(qutrub_identity.ordinal == #profile_registry.identities + 1)
assert(hydra_identity.ordinal == #profile_registry.identities + 2)
assert(qutrub_no_cait_identity.ordinal == #profile_registry.identities + 3)
assert(rancibus_identity.ordinal == #profile_registry.identities + 4)
assert(sortie_c_identity.ordinal == #profile_registry.identities + 5)
assert(not registry_by_id[qutrub_identity.id])
assert(not registry_by_id[hydra_identity.id])
assert(not registry_by_id[qutrub_no_cait_identity.id])
assert(not registry_by_id[rancibus_identity.id])
assert(not registry_by_id[sortie_c_identity.id])
registry_by_id[qutrub_identity.id] = qutrub_identity
registry_by_id[hydra_identity.id] = hydra_identity
registry_by_id[qutrub_no_cait_identity.id] = qutrub_no_cait_identity
registry_by_id[rancibus_identity.id] = rancibus_identity
registry_by_id[sortie_c_identity.id] = sortie_c_identity
established_identities = {
    {ordinal=1, id='locus-dire-bats-tomb', policy_id='pt-locus-bats',
        aliases={'locus','locusbats','direbats','tombbats','ranperre'}},
    {ordinal=2, id='limbus-119-stationary', policy_id='pt-limbus119',
        aliases={'limbus','lim','limbus119','limbus-stationary'}},
    {ordinal=3, id='ambuscade-2026-08-v1-breadwinner',
        policy_id='pt-ambu2608v1',
        aliases={'v1','ambuv1','breadwinner','ambuscade-v1'}},
    {ordinal=4, id='dynamis-divergence-wave1-route-corsair',
        policy_id='pt-ddw1-route',
        aliases={'ddw1route','dyna-w1-route','dynamis-w1-route'}},
    {ordinal=5, id='dynamis-divergence-wave1-boss-magic',
        policy_id='pt-ddw1-boss',
        aliases={'ddw1boss','dyna-w1-boss','dynamis-w1-boss'}},
    {ordinal=6, id='escha-ruaun-kammavaca',
        policy_id='pt-ruaun-kammavaca',
        aliases={'kammavaca','kamma','ruaun-kammavaca'}},
    {ordinal=7, id='escha-ruaun-genbu-genmei',
        policy_id='pt-genbu-genmei',
        aliases={'genmei','genbu','eschagenbu','genmeishield'}},
}
assert(#profile_registry.identities >= #established_identities)
for ordinal, expected in ipairs(established_identities) do
    assert(fingerprint.canonical(profile_registry.identities[ordinal])
        == fingerprint.canonical(expected),
        'established profile identity '..ordinal..' changed')
end
established_public_commands = {
    'use','preview','reapply','on','start','off','stop','arm','disarm',
    'force','action','status','check','preflight','version','list','show',
    'errors','audit','sleep',
    'acumen','clarion','ballad2','crusade','emblem','sentinel','flash',
    'provoke','cdc','leaden','wildfire','rudra','blizzard','silence',
}
assert(#profile_registry.reserved_commands == #established_public_commands)
for index, command in ipairs(established_public_commands) do
    assert(profile_registry.reserved_commands[index] == command,
        'established public command '..index..' changed')
end
for _, profile in ipairs{
    locus, limbus, v1, route, boss, genmei, kammavaca,
    september_qutrub, september_hydra, september_qutrub_no_cait,
    rancibus, sortie_c,
} do
    local identity = assert(registry_by_id[profile.id])
    assert(identity.policy_id == profile.policy_id)
    assert(fingerprint.canonical(identity.aliases)
        == fingerprint.canonical(profile.aliases))
end

-- Every reviewed profile has an independent compiled-plan sentinel. Adding or
-- revising one profile must not silently alter any other profile's commands.
local expected_plan_fingerprints = {
    ['locus-dire-bats-tomb']='212652af',
    ['limbus-119-stationary']='4dff597a',
    ['ambuscade-2026-08-v1-breadwinner']='652866a7',
    ['dynamis-divergence-wave1-route-corsair']='4a425652',
    ['dynamis-divergence-wave1-boss-magic']='52475c78',
    ['escha-ruaun-genbu-genmei']='267a043c',
    ['escha-ruaun-kammavaca']='022931eb',
    ['ambuscade-2026-09-v1-qutrub-bigwig']='14a32de7',
    ['ambuscade-2026-09-v2-hydra-alluttu']='1652eefc',
    ['ambuscade-2026-09-v1-qutrub-bigwig-no-cait']='368a98b2',
    ['vagary-direct-rancibus']='664fca96',
    ['sortie-objective-c-device-kill-v1']='01f07eb5',
}
local fingerprint_errors = {}
for _, plan in ipairs{
    locus_plan, limbus_plan, v1_plan, route_plan, boss_plan, genmei_plan,
    kammavaca_plan, september_qutrub_plan, september_hydra_plan,
    september_qutrub_no_cait_plan,
    rancibus_plan, sortie_c_plan,
} do
    local actual = plan_fingerprint(plan)
    if actual ~= expected_plan_fingerprints[plan.id] then
        fingerprint_errors[#fingerprint_errors + 1] =
            ('unexpected %s plan fingerprint %s')
                :format(plan.id, actual)
    end
end
assert(#fingerprint_errors == 0, table.concat(fingerprint_errors, '\n'))

assert(locus_plan.policy_command ==
    'pc policy pt-locus-bats Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - -')
assert(limbus_plan.policy_command ==
    'pc policy pt-limbus119 Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - elemental')
assert(v1_plan.policy_command ==
    'pc policy pt-ambu2608v1 Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Smalls,Achoo mobile Bozzetto_Urchin Dolomedes,Kickpuncher -')
assert(route_plan.policy_command ==
    'pc policy pt-ddw1-route Dolomedes Dolomedes Dolomedes Dolomedes stationary - - -')
assert(boss_plan.policy_command ==
    'pc policy pt-ddw1-boss Dolomedes Tackleberry Dolomedes,Tackleberry Dolomedes,Tackleberry,Kickpuncher,Smalls,Achoo mobile - - -')
assert(genmei_plan.policy_command ==
    'pc policy pt-genbu-genmei Dolomedes Tackleberry Tackleberry,Kickpuncher Tackleberry,Kickpuncher,Smalls stationary - - -')
assert(kammavaca_plan.policy_command ==
    'pc policy pt-ruaun-kammavaca Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo mobile - - -')
assert(september_qutrub_plan.policy_command ==
    'pc policy pt-ambu2609v1-qutrub Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - -')
assert(september_hydra_plan.policy_command ==
    'pc policy pt-ambu2609v2-hydra Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - -')
assert(september_qutrub_no_cait_plan.policy_command ==
    'pc policy pt-ambu2609v1-qutrub-nocait Dolomedes Dolomedes Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Achoo Dolomedes,Kickpuncher,Barneystinson mobile - - -')
assert(rancibus_plan.policy_command ==
    'pc policy pt-vagary-rancibus Dolomedes Tackleberry Tackleberry,Kickpuncher Tackleberry,Kickpuncher stationary - - -')
assert(sortie_c_plan.policy_command ==
    'pc policy pt-sortie-c-device Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo stationary - - -')

local locus_brd = joined_commands(locus_plan.members.Barneystinson)
local limbus_brd = joined_commands(limbus_plan.members.Barneystinson)
local v1_brd = joined_commands(v1_plan.members.Barneystinson)
local route_brd = joined_commands(route_plan.members.Barneystinson)
local boss_brd = joined_commands(boss_plan.members.Barneystinson)
local genmei_brd = joined_commands(genmei_plan.members.Barneystinson)
local kammavaca_brd = joined_commands(
    kammavaca_plan.members.Barneystinson)
local september_qutrub_brd = joined_commands(
    september_qutrub_plan.members.Barneystinson)
local september_hydra_brd = joined_commands(
    september_hydra_plan.members.Barneystinson)
local september_qutrub_no_cait_brd = joined_commands(
    september_qutrub_no_cait_plan.members.Barneystinson)
rancibus_brd = joined_commands(rancibus_plan.members.Barneystinson)
sortie_c_brd = joined_commands(sortie_c_plan.members.Barneystinson)
assert(locus_brd:find('gs c pstartbrd locusbats Tackleberry', 1, true))
assert(limbus_brd:find('gs c pstartbrd limbus Tackleberry', 1, true))
assert(v1_brd:find('gs c pstartbrd ambuscade-v1 Tackleberry', 1, true))
assert(v1_plan.members.Barneystinson.owns_autows2 == false)
assert(v1_brd:find('aws2 off', 1, true))
assert(route_brd:find('gs c pstartbrd off', 1, true))
assert(route_brd:find('aws2 off', 1, true))
assert(boss_brd:find('gs c pstartbrd magicboss Tackleberry', 1, true))
assert(boss_brd:find('hb enable cure; hb enable na', 1, true))
assert(boss_brd:find('aws2 off', 1, true))
assert(genmei_brd:find('gs c pstartbrd magicboss Tackleberry', 1, true))
assert(genmei_brd:find('hb db off; hb as off; hb as attack off; hb off',
    1, true))
assert(kammavaca_brd:find('gs c pstartbrd physical Tackleberry', 1, true))
assert(kammavaca_brd:find('hb enable cure; hb enable na', 1, true))
assert(kammavaca_plan.members.Barneystinson.owns_autows2 == false)
assert(kammavaca_brd:find('aws2 off', 1, true))
assert(september_qutrub_brd:find(
    'gs c ptgs activate ambuscade-2026-09-v1-qutrub-bigwig 1.1.0',
    1, true))
assert(september_hydra_brd:find(
    'gs c ptgs activate ambuscade-2026-09-v2-hydra-alluttu 1.0.0',
    1, true))
assert(september_qutrub_no_cait_brd:find(
    'gs c ptgs activate ambuscade-2026-09-v1-qutrub-bigwig-no-cait 1.10.0',
    1, true))
assert(september_qutrub_brd:find('aws2 off', 1, true))
assert(september_hydra_brd:find('aws2 off', 1, true))
assert(september_qutrub_no_cait_brd:find(
    'gs c weapons DualSavage; wait 1; aws2 aftermath off; '
        ..'aws2 use Savage Blade; aws2 tp 1000; aws2 hp 0 100; aws2 on',
    1, true))
assert(rancibus_brd:find(
    'gs c ptgs activate vagary-direct-rancibus 1.1.0', 1, true))
assert(rancibus_brd:find(
    'gs c pstartbrd magicboss Tackleberry', 1, true))
assert(rancibus_brd:find('hb enable cure; hb enable na', 1, true))
assert(rancibus_brd:find('aws2 off', 1, true))
assert(sortie_c_brd:find(
    'gs c pstartbrd physical Tackleberry', 1, true))
assert(sortie_c_brd:find('hb enable cure; hb enable na', 1, true))
assert(sortie_c_brd:find('aws2 on', 1, true))

local route_dolo = joined_commands(route_plan.members.Dolomedes)
local locus_dolo = joined_commands(locus_plan.members.Dolomedes)
local boss_dolo = joined_commands(boss_plan.members.Dolomedes)
local boss_tackle = joined_commands(boss_plan.members.Tackleberry)
local boss_kick = joined_commands(boss_plan.members.Kickpuncher)
local genmei_dolo = joined_commands(genmei_plan.members.Dolomedes)
local genmei_tackle = joined_commands(genmei_plan.members.Tackleberry)
local genmei_kick = joined_commands(genmei_plan.members.Kickpuncher)
local genmei_rdm = joined_commands(genmei_plan.members.Smalls)
local genmei_geo = joined_commands(genmei_plan.members.Achoo)
local kammavaca_dolo = joined_commands(kammavaca_plan.members.Dolomedes)
local kammavaca_tackle = joined_commands(kammavaca_plan.members.Tackleberry)
local kammavaca_kick = joined_commands(kammavaca_plan.members.Kickpuncher)
local kammavaca_rdm = joined_commands(kammavaca_plan.members.Smalls)
local kammavaca_geo = joined_commands(kammavaca_plan.members.Achoo)
local locus_rdm = joined_commands(locus_plan.members.Smalls)
local locus_geo = joined_commands(locus_plan.members.Achoo)
local locus_dnc = joined_commands(locus_plan.members.Kickpuncher)
local limbus_rdm = joined_commands(limbus_plan.members.Smalls)
local limbus_geo = joined_commands(limbus_plan.members.Achoo)
local v1_rdm = joined_commands(v1_plan.members.Smalls)
local v1_geo = joined_commands(v1_plan.members.Achoo)
local boss_rdm = joined_commands(boss_plan.members.Smalls)
local boss_geo = joined_commands(boss_plan.members.Achoo)
september_qutrub_dolo = joined_commands(
    september_qutrub_plan.members.Dolomedes)
september_qutrub_tackle = joined_commands(
    september_qutrub_plan.members.Tackleberry)
september_qutrub_kick = joined_commands(
    september_qutrub_plan.members.Kickpuncher)
september_qutrub_rdm = joined_commands(
    september_qutrub_plan.members.Smalls)
september_qutrub_geo = joined_commands(
    september_qutrub_plan.members.Achoo)
september_hydra_dolo = joined_commands(
    september_hydra_plan.members.Dolomedes)
september_hydra_tackle = joined_commands(
    september_hydra_plan.members.Tackleberry)
september_hydra_kick = joined_commands(
    september_hydra_plan.members.Kickpuncher)
september_hydra_geo = joined_commands(
    september_hydra_plan.members.Achoo)
september_qutrub_no_cait_dolo = joined_commands(
    september_qutrub_no_cait_plan.members.Dolomedes)
september_qutrub_no_cait_tackle = joined_commands(
    september_qutrub_no_cait_plan.members.Tackleberry)
september_qutrub_no_cait_kick = joined_commands(
    september_qutrub_no_cait_plan.members.Kickpuncher)
september_qutrub_no_cait_rdm = joined_commands(
    september_qutrub_no_cait_plan.members.Smalls)
september_qutrub_no_cait_geo = joined_commands(
    september_qutrub_no_cait_plan.members.Achoo)
rancibus_dolo = joined_commands(rancibus_plan.members.Dolomedes)
rancibus_tackle = joined_commands(rancibus_plan.members.Tackleberry)
rancibus_kick = joined_commands(rancibus_plan.members.Kickpuncher)
rancibus_rdm = joined_commands(rancibus_plan.members.Smalls)
rancibus_geo = joined_commands(rancibus_plan.members.Achoo)
sortie_c_dolo = joined_commands(sortie_c_plan.members.Dolomedes)
sortie_c_tackle = joined_commands(sortie_c_plan.members.Tackleberry)
sortie_c_kick = joined_commands(sortie_c_plan.members.Kickpuncher)
sortie_c_rdm = joined_commands(sortie_c_plan.members.Smalls)
sortie_c_geo = joined_commands(sortie_c_plan.members.Achoo)
assert(locus_rdm:find(
    'gs c pstartrdm locusbats-protect Tackleberry', 1, true))
assert(locus_geo:find('gs c pstartgeo leanmanaged', 1, true))
assert(locus_geo:find('gs c unset CombatEntrustOnly', 1, true))
assert(locus_dnc:find('gs c pstartdnc locusbats Tackleberry', 1, true))
assert(limbus_rdm:find('gs c pstartrdm limbus-protect Tackleberry', 1, true))
assert(limbus_geo:find('gs c pstartgeo leanmanaged', 1, true))
assert(limbus_geo:find('gs c unset CombatEntrustOnly', 1, true))
assert(v1_rdm:find(
    'gs c pstartrdm ambuscade-v1-protect Tackleberry', 1, true))
assert(v1_geo:find('gs c pstartgeo leanrrmanaged', 1, true))
assert(v1_geo:find('gs c unset CombatEntrustOnly', 1, true))
assert(boss_rdm:find('gs c pstartrdm magicboss-protect Tackleberry', 1, true))
assert(boss_rdm:find('aws2 off', 1, true))
assert(boss_geo:find('gs c pstartgeo leanrrmanaged', 1, true))
assert(boss_geo:find('gs c unset CombatEntrustOnly', 1, true))
assert(boss_geo:find('aws2 off', 1, true))
local geo_teardown = table.concat(compiler.teardown('GEO', true), '\n')
assert(geo_teardown:find('gs c pstartgeo idle', 1, true))
assert(geo_teardown:find('gs c set CombatEntrustOnly', 1, true))
assert(geo_teardown:find('aws2 exclude none', 1, true))
assert(route_dolo:find('r2 roll1 tactician; r2 roll2 wizard', 1, true))
assert(route_dolo:find('aws2 tp 1500', 1, true))
assert(locus_dolo:find(
    'gs c weapons DualSavage; wait 1; aws2 aftermath off;', 1, true))
for _, plan in ipairs{
    locus_plan, limbus_plan, v1_plan, route_plan, boss_plan, genmei_plan,
    kammavaca_plan, september_qutrub_plan, september_hydra_plan,
    september_qutrub_no_cait_plan,
    rancibus_plan, sortie_c_plan,
} do
    local cor_commands = joined_commands(plan.members.Dolomedes)
    local guard_at = cor_commands:find(
        'gs c set CompensatorMode Never; gs c unset UnlockWeapons', 1, true)
    local roller_at = cor_commands:find('r2 policy conservative', 1, true)
    assert(guard_at and roller_at and guard_at < roller_at)
    assert(cor_commands:find('r2 randomdeal off', 1, true))
    assert(not cor_commands:find('gs c set Weapons', 1, true))
end
for _, plan in ipairs{
    locus_plan, limbus_plan, v1_plan, route_plan, boss_plan, kammavaca_plan,
    sortie_c_plan,
} do
    for _, member in pairs(plan.members) do
        assert(joined_commands(member):find('gs c ptgs off', 1, true),
            plan.id..' does not revoke a stale fight adapter')
    end
end
assert(sortie_c.gearswap_adapter == nil)
assert(sortie_c.runtime == nil)
assert(sortie_c.preflight == nil)
assert(util.count(sortie_c.manual_actions) == 0)
assert(sortie_c.combat.movement == 'stationary')
assert(#sortie_c.combat.attackers == 6)
assert(#sortie_c.combat.targeters == 6)
assert(sortie_c_dolo:find('r2 roll1 chaos; r2 roll2 samurai', 1, true))
assert(sortie_c_dolo:find(
    'gs c weapons DualSavage; wait 1; aws2 aftermath off;', 1, true))
assert(sortie_c_tackle:find(
    'gs c pstartpld manualsc Dolomedes', 1, true))
assert(sortie_c_kick:find(
    'gs c pstartdnc physical Tackleberry', 1, true))
assert(sortie_c_rdm:find(
    'gs c pstartrdm magicboss-protect Tackleberry', 1, true))
assert(sortie_c_geo:find('gs c pstartgeo leanmanaged', 1, true))
assert(sortie_c_geo:find(
    'gs c autoindi Fury; gs c autogeo Frailty;', 1, true))
for _, member in pairs(sortie_c_plan.members) do
    local commands = joined_commands(member)
    assert(commands:find('gs c ptgs off', 1, true))
    assert(commands:find('aws2 exclude none', 1, true))
end
assert(boss_dolo:find('r2 roll1 samurai; r2 roll2 wizard', 1, true))
assert(boss_dolo:find('gs c weapons DualLeaden; wait 1; aws2 off', 1, true))
assert(not boss_dolo:find('aws2 on', 1, true))
assert(boss_tackle:find('gs c pstartpld manualsc Dolomedes', 1, true))
assert(boss_tackle:find('gs c set AutoBuffMode Off; gs c unset AutoTankMode;',
    1, true))
assert(boss_tackle:find('gs c weapons Naegling; wait 1; aws2 off', 1, true))
assert(not boss_tackle:find('aws2 on', 1, true))
assert(boss_kick:find('gs c pstartdnc tankheal Tackleberry', 1, true))
assert(boss_kick:find("gs c weapons Tauret; wait 1; aws2 off", 1, true))
assert(genmei_dolo:find('r2 roll1 warlock; r2 roll2 samurai', 1, true))
assert(genmei_dolo:find(
    'gs c weapons DeathPenalty; wait 1; aws2 off', 1, true))
assert(genmei_tackle:find('gs c pstartpld manualsc Dolomedes', 1, true))
assert(genmei_tackle:find(
    'gs c set AutoBuffMode Off; gs c unset AutoTankMode;', 1, true))
assert(genmei_tackle:find(
    'gs c weapons Naegling; wait 1; aws2 off', 1, true))
assert(genmei_kick:find('gs c pstartdnc off', 1, true))
assert(not genmei_kick:find('gs c pstartdnc tankheal', 1, true))
assert(genmei_kick:find(
    'gs c weapons Tauret; wait 1; aws2 off', 1, true))
assert(genmei_rdm:find(
    'gs c pstartrdm limbus-protect Tackleberry', 1, true))
assert(genmei_rdm:find('aws2 off', 1, true))
assert(genmei_geo:find('gs c pstartgeo leanmanaged', 1, true))
assert(genmei_geo:find('gs c unset CombatEntrustOnly', 1, true))
assert(genmei_geo:find('hb db off; hb as off; hb as attack off; hb off',
    1, true))
assert(genmei_geo:find('gs c weapons Maxentius; wait 1; aws2 off', 1, true))
assert(genmei_brd:find('aws2 off', 1, true))
for _, member in pairs(genmei_plan.members) do
    assert(joined_commands(member):find(
        'gs c ptgs activate escha-ruaun-genbu-genmei 2.7.0', 1, true))
end
for _, member in pairs(rancibus_plan.members) do
    assert(joined_commands(member):find(
        'gs c ptgs activate vagary-direct-rancibus 1.1.0', 1, true))
end
assert(rancibus.gearswap_adapter.id == 'vagary-direct-rancibus')
assert(rancibus.gearswap_adapter.version == '1.1.0')
assert(rancibus.gearswap_adapter.controller == 'rancibus')
assert(rancibus.gearswap_adapter.protocol == 1)
assert(table.concat(rancibus.gearswap_adapter.actions, ',') ==
    'barwatera-prepare,barsilencera-prepare,crusade,barwatera-recover,barsilencera-recover,sentinel,rampart,flash,provoke,shoot,stun,shield-bash,no-foot-rise,box-step,lead,middle,close,dia3,addle2,slow2,paralyze2,geo-frailty,cancel')
assert(rancibus.roles.skillchain_starter == nil)
assert(rancibus.roles.skillchain_middle == nil)
assert(rancibus.roles.skillchain_closer == nil)
assert(util.count(rancibus.manual_actions) == 0)
assert(rancibus.preflight.required_before_combat == false)
assert(rancibus.preflight.auto_after_apply == nil)
assert(rancibus.preflight.auto_retry_seconds == nil)
assert(rancibus.preflight.zone == 277)
assert(rancibus.preflight.max_age_seconds == 300)
assert(rancibus.preflight.all.items[1].name == 'Echo Drops')
assert(rancibus.preflight.all.items[1].minimum == 12)
assert(rancibus.preflight.members.Dolomedes.equipment.range
    == 'Death Penalty')
assert(rancibus.preflight.members.Dolomedes.equipment.ammo
    == 'Living Bullet')
assert(rancibus_dolo:find('r2 roll1 chaos; r2 roll2 magus', 1, true))
assert(rancibus_dolo:find(
    'gs c weapons DualLastStandRanged; wait 1; aws2 off', 1, true))
assert(rancibus_tackle:find(
    'gs c pstartpld manualsc Dolomedes', 1, true))
assert(rancibus_kick:find(
    'gs c pstartdnc tankheal Tackleberry', 1, true))
assert(rancibus_rdm:find(
    'gs c pstartrdm magicboss-protect Tackleberry', 1, true))
assert(rancibus_geo:find('gs c pstartgeo leanrrmanaged', 1, true))
assert(rancibus_geo:find('gs c autoindi Refresh; gs c autogeo Frailty;',
    1, true))
for _, commands in ipairs{
    rancibus_dolo, rancibus_tackle, rancibus_kick,
    rancibus_brd, rancibus_rdm, rancibus_geo,
} do
    assert(commands:find('aws2 off', 1, true))
    assert(commands:find('aws2 exclude none', 1, true))
end
assert(genmei.gearswap_adapter.id == 'escha-ruaun-genbu-genmei')
assert(genmei.gearswap_adapter.version == '2.7.0')
assert(genmei.support.dnc.enabled == false)
assert(table.concat(genmei.support.rdm.refresh, ',')
    == 'Smalls,Achoo,Tackleberry')
assert(genmei.gearswap_adapter.controller == 'genmei')
assert(genmei.gearswap_adapter.protocol == 1)
assert(table.concat(genmei.gearswap_adapter.actions, ',') ==
    'barwatera,setup,crusade,divine-emblem,sentinel,flash,provoke,haste-samba,presto,box-step,evisceration,savage-blade,disengage,shoot,last-stand,triple-shot,proc,burst,recover-songs,recover-rolls,combat-start,combat-end,cancel')
assert(genmei.roles.skillchain_starter == 'Kickpuncher')
assert(genmei.roles.skillchain_opener == 'Tackleberry')
assert(genmei.roles.skillchain_closer == 'Dolomedes')
assert(genmei.roles.primary_healer == 'Tackleberry')
assert(genmei.roles.backup_healer == 'Smalls')
assert(genmei.members.Dolomedes.sub_jobs[1] == 'THF')
assert(genmei.members.Achoo.sub_jobs[1] == 'BLM')
assert(genmei.offense.Dolomedes.weapon_mode == 'DeathPenalty')
assert(util.count(genmei.manual_actions) == 0)
assert(genmei.preflight.required_before_combat == false)
assert(genmei.preflight.auto_after_apply == nil)
assert(genmei.preflight.auto_retry_seconds == nil)
assert(genmei.preflight.max_age_seconds == nil)
assert(genmei.preflight.zone == 289)
assert(genmei.preflight.members.Barneystinson.controller.name == 'genmei')
assert(genmei.preflight.members.Barneystinson.controller.protocol == 1)
function buff_labels(values)
    local result = {}
    for _, value in ipairs(values) do
        result[#result + 1] = type(value) == 'table' and value.label or value
    end
    return table.concat(result, ',')
end
assert(buff_labels(genmei.preflight.members.Dolomedes.buffs)
    == "Protect,Shell,Barwater,March,Samurai Roll,Warlock's Roll,Haste,Phalanx")
assert(buff_labels(genmei.preflight.members.Tackleberry.buffs)
    == 'Protect,Shell,Barwater,March,Minne,Samurai Roll,Haste,Refresh,Phalanx')
assert(buff_labels(genmei.preflight.members.Barneystinson.buffs)
    == 'Protect,Shell,Barwater,Ballad')
assert(buff_labels(genmei.preflight.members.Smalls.buffs)
    == "Protect,Shell,Barwater,Ballad,Warlock's Roll,Haste,Refresh")
assert(buff_labels(genmei.preflight.members.Achoo.buffs)
    == "Protect,Shell,Barwater,Ballad,Indi-Acumen,Warlock's Roll,Haste,Refresh")
assert(genmei.preflight.members.Dolomedes.equipment.sub == 'Nusku Shield')
assert(not genmei_dolo:find('aws2 on', 1, true))
assert(not genmei_tackle:find('aws2 on', 1, true))
assert(not genmei_kick:find('aws2 on', 1, true))
assert(not genmei_geo:find('aws2 on', 1, true))
assert(genmei_tackle:find(
    'gs c set AutoBuffMode Off; gs c unset AutoTankMode;', 1, true))
assert(genmei_kick:find('gs c pstartdnc off', 1, true))
assert(genmei_dolo:find(
    'gs c weapons DeathPenalty; wait 1; aws2 off', 1, true))
assert(genmei_rdm:find(
    'gs c pstartrdm limbus-protect Tackleberry', 1, true))
assert(genmei_rdm:find('hb disable cure; hb enable na', 1, true))
assert(genmei_brd:find('hb db off; hb as off; hb as attack off; hb off',
    1, true))
assert(genmei_geo:find('hb db off; hb as off; hb as attack off; hb off',
    1, true))
assert(kammavaca_dolo:find('r2 roll1 chaos; r2 roll2 samurai', 1, true))
assert(kammavaca_dolo:find(
    'gs c weapons DualSavage; wait 1; aws2 aftermath off; '
        ..'aws2 use Savage Blade; aws2 tp 1000; aws2 hp 0 100; aws2 on',
    1, true))
assert(kammavaca_tackle:find('gs c pstartpld manualsc Dolomedes', 1, true))
assert(kammavaca_tackle:find(
    'gs c set AutoBuffMode Auto; gs c set AutoTankMode;', 1, true))
assert(kammavaca_tackle:find(
    'gs c weapons Naegling; wait 1; aws2 off', 1, true))
assert(not kammavaca_tackle:find('aws2 on', 1, true))
assert(kammavaca_kick:find(
    'gs c pstartdnc physical Tackleberry', 1, true))
assert(kammavaca_kick:find(
    'gs c weapons Tauret; wait 1; aws2 aftermath off; '
        ..'aws2 use Evisceration; aws2 tp 1000; aws2 hp 0 100; aws2 on',
    1, true))
assert(kammavaca_rdm:find(
    'gs c pstartrdm magicboss-protect Tackleberry '
        ..'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry '
        ..'Smalls,Achoo,Barneystinson,Tackleberry '
        ..'Dolomedes,Tackleberry,Kickpuncher,Achoo '
        ..'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry',
    1, true))
assert(kammavaca_rdm:find('aws2 off', 1, true))
assert(kammavaca_geo:find('gs c pstartgeo leanrrmanaged', 1, true))
assert(kammavaca_geo:find('gs c set CombatEntrustOnly', 1, true))
assert(kammavaca_geo:find(
    'gs c autoindi Fury; gs c autogeo Frailty; '
        ..'gs c autoentrust Fend; gs c autoentrustee Tackleberry;',
    1, true))
assert(kammavaca_geo:find('hb enable cure; hb enable na', 1, true))
assert(kammavaca_geo:find(
    'gs c unset AutoWSMode; gs c weapons Maxentius; wait 1; aws2 off',
    1, true))
assert(not kammavaca_geo:find('aws2 on', 1, true))
assert(kammavaca.offense.Achoo.disable_native_autows == true)
assert(genmei_geo:find('gs c unset AutoWSMode; gs c weapons', 1, true))
assert(kammavaca_plan.members.Dolomedes.owns_autows2 == true)
assert(kammavaca_plan.members.Tackleberry.owns_autows2 == true)
assert(kammavaca_plan.members.Kickpuncher.owns_autows2 == true)
assert(kammavaca_plan.members.Achoo.owns_autows2 == true)
assert(kammavaca_plan.members.Smalls.owns_autows2 == false)

-- September profiles are isolated, adapter-owned encounter controllers.
-- Their declarative plans may select reviewed GearSwap modes, and the no-Cait
-- variant explicitly delegates automatic weaponskills to AutoWS2. No manifest
-- can own equipment slots.
function assert_september_profile_case(case)
    assert(case.profile.gearswap_adapter.id == case.id)
    assert(case.profile.gearswap_adapter.version == case.adapter_version)
    assert(case.profile.gearswap_adapter.controller == case.controller)
    assert(case.profile.gearswap_adapter.protocol == 1)
    assert(util.count(case.profile.manual_actions) == 0)
    if case.advisory_preflight then
        assert(case.profile.preflight.required_before_combat == false)
        assert(case.profile.preflight.auto_after_apply == nil)
    else
        assert(case.profile.preflight.required_before_combat == true)
        assert(case.profile.preflight.auto_after_apply == 30)
    end
    if case.automatic_attackers then
        local ws_command = case.session_ws
            and 'aws2 sessionws' or 'aws2 use'
        assert(case.dolo:find(
            'gs c weapons DualLastStandRanged; wait 1; aws2 aftermath off; '
                ..ws_command
                ..' Last Stand; aws2 tp 1000; aws2 hp 0 100; aws2 on',
            1, true))
    else
        assert(case.dolo:find(
            'gs c weapons DualLastStandRanged; wait 1; aws2 off', 1, true))
    end
    if case.tackle_automatic then
        assert(case.tackle:find(
            'gs c weapons Naegling; wait 1; aws2 aftermath off; '
                ..'aws2 use Savage Blade; aws2 tp 1000; '
                ..'aws2 hp 0 100; aws2 on', 1, true))
    elseif case.tackle_loadout_only then
        assert(case.tackle:find('gs c pstartpld off Dolomedes', 1, true))
        assert(case.tackle:find('gs c weapons Naegling', 1, true))
        assert(case.tackle:find('aws2 off', 1, true))
        assert(not case.tackle:find('aws2 use Savage Blade', 1, true))
        assert(not case.tackle:find('pstartpld manualsc', 1, true))
    else
        assert(case.tackle:find(
            'gs c weapons Naegling; wait 1; aws2 off', 1, true))
    end
    if case.automatic_attackers then
        assert(case.kick:find(
            'gs c weapons Tauret; wait 1; aws2 aftermath off; '
                ..'aws2 use Evisceration; aws2 tp 1000; '
                ..'aws2 hp 0 100; aws2 on', 1, true))
    else
        assert(case.kick:find(
            'gs c weapons Tauret; wait 1; aws2 off', 1, true))
    end
    if case.geo_automatic then
        assert(case.geo:find(
            'gs c weapons Maxentius; wait 1; aws2 aftermath off; '
                ..'aws2 use Black Halo; aws2 tp 1000; '
                ..'aws2 hp 0 100; aws2 on', 1, true))
    else
        assert(case.geo:find('aws2 off', 1, true))
    end
    local automatic = {
        Dolomedes=true, Kickpuncher=true, Barneystinson=true,
    }
    if case.tackle_automatic then automatic.Tackleberry = true end
    if case.geo_automatic then automatic.Achoo = true end
    for name, member in pairs(case.plan.members) do
        local commands = joined_commands(member)
        assert(commands:find(
            'gs c ptgs activate '..case.id..' '..case.adapter_version,
            1, true))
        if case.automatic_attackers and automatic[name] then
            assert(commands:find('aws2 on', 1, true))
        else
            assert(commands:find('aws2 off', 1, true))
        end
        assert(not commands:lower():find('equip ', 1, true))
        assert(not commands:find('gs c disable', 1, true))
        assert(not commands:find('gs c enable', 1, true))
    end
end
assert_september_profile_case(
    {
        profile=september_qutrub, plan=september_qutrub_plan,
        id='ambuscade-2026-09-v1-qutrub-bigwig',
        controller='qutrub-bigwig', adapter_version='1.1.0',
        dolo=september_qutrub_dolo, tackle=september_qutrub_tackle,
        kick=september_qutrub_kick, geo=september_qutrub_geo,
    })
assert_september_profile_case(
    {
        profile=september_hydra, plan=september_hydra_plan,
        id='ambuscade-2026-09-v2-hydra-alluttu',
        controller='hydra', adapter_version='1.0.0',
        dolo=september_hydra_dolo, tackle=september_hydra_tackle,
        kick=september_hydra_kick, geo=september_hydra_geo,
    })
assert_september_profile_case(
    {
        profile=september_qutrub_no_cait,
        plan=september_qutrub_no_cait_plan,
        id='ambuscade-2026-09-v1-qutrub-bigwig-no-cait',
        controller='qutrub-bigwig-no-cait', adapter_version='1.10.0',
        session_ws=true,
        dolo=september_qutrub_no_cait_dolo,
        tackle=september_qutrub_no_cait_tackle,
        kick=september_qutrub_no_cait_kick,
        geo=september_qutrub_no_cait_geo,
        tackle_automatic=true,
        geo_automatic=true,
        advisory_preflight=true,
        automatic_attackers=true,
    })
assert(september_qutrub.members.Dolomedes.sub_jobs[1] == 'NIN')
assert(september_qutrub.members.Tackleberry.sub_jobs[1] == 'NIN')
assert(september_qutrub.members.Kickpuncher.sub_jobs[1] == 'NIN')
assert(september_qutrub.members.Barneystinson.sub_jobs[1] == 'SMN')
assert(september_qutrub.members.Smalls.sub_jobs[1] == 'SMN')
assert(september_qutrub.members.Achoo.sub_jobs[1] == 'WHM')
assert(september_qutrub.roles.primary_mew == 'Barneystinson')
assert(september_qutrub.roles.secondary_mew == 'Smalls')
assert(september_qutrub_geo:find('hb enable cure; hb enable na', 1, true))
assert(september_qutrub_rdm:find('hb disable cure; hb enable na', 1, true))
function september_has_action(member, kind, name)
    for _, action in ipairs(
        september_qutrub.preflight.members[member].actions or {})
    do
        if action.kind == kind and action.name == name then return true end
    end
    return false
end
for _, member in ipairs{'Barneystinson','Smalls'} do
    assert(september_has_action(member, 'spell', 'Cait Sith'))
    assert(september_has_action(member, 'ability', 'Mewing Lullaby'))
    assert(september_has_action(member, 'ability', 'Retreat'))
end
assert(not september_has_action('Achoo', 'spell', 'Cait Sith'))
assert(not september_has_action('Achoo', 'ability', 'Mewing Lullaby'))
assert(not september_has_action('Achoo', 'ability', 'Retreat'))
assert(not september_has_action('Barneystinson', 'spell', 'Reraise'))
assert(september_has_action('Achoo', 'spell', 'Reraise'))
assert(september_qutrub_no_cait.members.Dolomedes.sub_jobs[1] == 'NIN')
assert(september_qutrub_no_cait.members.Tackleberry.sub_jobs[1] == 'BLU')
assert(september_qutrub_no_cait.members.Kickpuncher.sub_jobs[1] == 'NIN')
assert(september_qutrub_no_cait.members.Barneystinson.sub_jobs[1] == 'NIN')
assert(september_qutrub_no_cait.members.Smalls.sub_jobs[1] == 'WHM')
assert(september_qutrub_no_cait.members.Achoo.sub_jobs[1] == 'WHM')
function september_no_cait_has_action(member, kind, name)
    for _, action in ipairs(
        september_qutrub_no_cait.preflight.members[member].actions or {})
    do
        if action.kind == kind and action.name == name then return true end
    end
    return false
end
for _, member in ipairs{'Dolomedes','Kickpuncher','Barneystinson'} do
    assert(september_no_cait_has_action(member, 'spell', 'Utsusemi: Ni'))
    assert(september_no_cait_has_action(member, 'spell', 'Utsusemi: Ichi'))
    local shihei = nil
    for _, item in ipairs(
        september_qutrub_no_cait.preflight.members[member].items or {})
    do
        if item.name == 'Shihei' then shihei = item end
    end
    assert(shihei and shihei.bag_group == 'inventory')
end
assert(september_qutrub_no_cait.roles.add_handler == 'Tackleberry')
assert(september_qutrub_no_cait.roles.boss_anchor == 'Dolomedes')
assert(september_qutrub_no_cait.roles.boss_holder == nil)
assert(september_qutrub_no_cait.roles.boss_side_damage == 'Kickpuncher')
assert(september_qutrub_no_cait.roles.add_tank == 'Tackleberry')
assert(september_qutrub_no_cait.roles.add_damage_one == 'Kickpuncher')
assert(september_qutrub_no_cait.roles.add_damage_two == 'Barneystinson')
assert(september_qutrub_no_cait.roles.tank == nil)
assert(september_qutrub_no_cait.roles.evisceration_user == 'Kickpuncher')
assert(september_qutrub_no_cait.roles.savage_blade_user == 'Barneystinson')
assert(september_qutrub_no_cait.roles.last_stand_user == 'Dolomedes')
assert(september_qutrub_no_cait.roles.skillchain_starter == nil)
assert(september_qutrub_no_cait.roles.skillchain_opener == nil)
assert(september_qutrub_no_cait.roles.skillchain_closer == nil)
assert(september_qutrub_no_cait.combat.movement == 'mobile')
for _, spell in ipairs{
    'Cocoon','Crusade','Reprisal','Blank Gaze','Sheep Song','Geist Wall',
    'Jettatura','Cure IV',
} do
    assert(september_no_cait_has_action('Tackleberry', 'spell', spell))
end
assert(not september_no_cait_has_action(
    'Tackleberry', 'ability', 'Shield Bash'))
assert(september_no_cait_has_action('Achoo', 'spell', 'Indi-Wilt'))
assert(september_no_cait_has_action('Achoo', 'spell', 'Flash'))
assert(september_no_cait_has_action('Achoo', 'spell', 'Curaga II'))
assert(not september_no_cait_has_action('Achoo', 'spell', 'Cure IV'))
assert(not september_no_cait_has_action('Achoo', 'spell', 'Indi-Gravity'))
assert(september_qutrub_no_cait_tackle:find(
    'gs c pstartpld off Dolomedes', 1, true))
assert(not september_qutrub_no_cait_tackle:find(
    'pstartpld manualsc', 1, true))
assert(september_qutrub_no_cait_tackle:find(
    'gs c weapons Naegling', 1, true))
assert(september_qutrub_no_cait_tackle:find('aws2 on', 1, true))
for _, member in ipairs{
    'Dolomedes','Tackleberry','Kickpuncher','Barneystinson','Achoo',
} do
    assert(joined_commands(
        september_qutrub_no_cait_plan.members[member]):find(
            'aws2 on', 1, true))
end
assert(september_qutrub_no_cait_kick:find('gs c pstartdnc off', 1, true))
assert(september_qutrub_no_cait_geo:find(
    'gs c autoentrust None; gs c autoentrustee Tackleberry;', 1, true))
assert(september_qutrub_no_cait_geo:find(
    'gs c set CombatEntrustOnly', 1, true))
assert(september_qutrub_no_cait_rdm:find('hb disable cure; hb enable na',
    1, true))
assert(september_qutrub_no_cait_rdm:find(
    'gs c pstartrdm sortieacuex Dolomedes', 1, true))
assert(september_qutrub_no_cait_geo:find(
    'hb db off; hb as off; hb as attack off; hb off', 1, true))
assert(september_no_cait_has_action('Achoo', 'weaponskill', 'Black Halo'))
assert(september_no_cait_has_action('Kickpuncher', 'ability', 'Box Step'))
assert(september_hydra.members.Tackleberry.sub_jobs[1] == 'WAR')
assert(september_hydra.members.Kickpuncher.sub_jobs[1] == 'WAR')
assert(september_hydra.members.Barneystinson.sub_jobs[1] == 'WHM')
assert(september_hydra.members.Smalls.sub_jobs[1] == 'WHM')
assert(september_hydra.members.Achoo.sub_jobs[1] == 'WHM')

-- Target exclusions are explicitly opt-in and are reset by every other
-- profile, preventing Limbus's Elemental filter from leaking across fights.
for _, plan in ipairs{
    locus_plan, v1_plan, route_plan, boss_plan, genmei_plan, kammavaca_plan,
    september_qutrub_plan, september_hydra_plan,
    september_qutrub_no_cait_plan,
    rancibus_plan, sortie_c_plan,
} do
    for _, member in pairs(plan.members) do
        assert(joined_commands(member):find('aws2 exclude none', 1, true))
    end
end
for _, member in pairs(limbus_plan.members) do
    assert(joined_commands(member):find('aws2 exclude elemental', 1, true))
    assert(not joined_commands(member):find('aws2 exclude none', 1, true))
end

-- Barney is the regression sentinel for a universal contract: orchestration
-- may select a reviewed GearSwap preset, but it may not manipulate equipment.
for _, commands in ipairs{
    locus_brd, limbus_brd, v1_brd, route_brd, boss_brd, genmei_brd,
    kammavaca_brd, september_qutrub_brd, september_hydra_brd,
    september_qutrub_no_cait_brd, rancibus_brd, sortie_c_brd,
} do
    local lower = commands:lower()
    assert(not lower:find('equip', 1, true))
    assert(not lower:find('range=', 1, true))
    assert(not lower:find('ammo=', 1, true))
    assert(not lower:find('fullength', 1, true))
    assert(not lower:find('gs c disable', 1, true))
    assert(not lower:find('gs c enable', 1, true))
end

-- Kammavaca's fight-local manifest freezes the exact opening safety barrier,
-- typed controls, and GearSwap-owned melee assumptions. In particular, Dolo's
-- empty range slot proves this physical profile cannot inherit Genmei's gun.
assert(kammavaca.preflight.required_before_combat == true)
assert(kammavaca.preflight.auto_after_apply == 3)
assert(#kammavaca.preflight.all.items == 1)
local echo_drops = kammavaca.preflight.all.items[1]
assert(echo_drops.name == 'Echo Drops')
assert(echo_drops.minimum == 12)
assert(echo_drops.bag_group == 'inventory')
assert(#kammavaca.preflight.all.key_items == 1)
local lens = kammavaca.preflight.all.key_items[1]
assert(lens.label == 'Tribulens or Radialens')
assert(#lens.ids == 2 and lens.ids[1] == 2894 and lens.ids[2] == 3031)

local kammavaca_preflight = kammavaca.preflight.members
assert(kammavaca_preflight.Dolomedes.equipment.main == 'Naegling')
assert(kammavaca_preflight.Dolomedes.equipment.sub == "Gleti's Knife")
assert(kammavaca_preflight.Dolomedes.equipment.range == 'empty')
assert(#kammavaca_preflight.Dolomedes.key_items == 1)
assert(kammavaca_preflight.Dolomedes.key_items[1].id == 2944)
assert(kammavaca_preflight.Dolomedes.key_items[1].label
    == "Kammavaca's binding")
assert(kammavaca_preflight.Tackleberry.equipment.main == 'Naegling')
assert(kammavaca_preflight.Tackleberry.equipment.sub == 'Diamond Aspis')
assert(kammavaca_preflight.Kickpuncher.equipment.main == 'Tauret')
assert(kammavaca_preflight.Kickpuncher.equipment.sub
    == 'Ternion Dagger +1')
assert(kammavaca_preflight.Achoo.equipment.main == 'Maxentius')
assert(kammavaca_preflight.Achoo.equipment.sub == 'Sors Shield')

local function assert_action_list(actual, expected)
    assert(#actual == #expected)
    for index, wanted in ipairs(expected) do
        local found = actual[index]
        assert(found.kind == wanted.kind and found.name == wanted.name)
        assert(found.optional == wanted.optional)
    end
end
assert_action_list(kammavaca_preflight.Dolomedes.actions, {
    {kind='weaponskill', name='Savage Blade'},
})
assert_action_list(kammavaca_preflight.Tackleberry.actions, {
    {kind='spell', name='Flash'},
    {kind='ability', name='Provoke'},
    {kind='ability', name='Sentinel'},
})
assert_action_list(kammavaca_preflight.Kickpuncher.actions, {
    {kind='weaponskill', name='Evisceration'},
})
assert_action_list(kammavaca_preflight.Barneystinson.actions, {
    {kind='spell', name='Horde Lullaby II'},
    {kind='spell', name='Barsilencera'},
    {kind='spell', name='Erase'},
})
assert_action_list(kammavaca_preflight.Smalls.actions, {
    {kind='spell', name='Silence'},
    {kind='spell', name='Cure IV'},
    {kind='ability', name='Elemental Seal', optional=true},
    {kind='spell', name='Sleepga', optional=true},
    {kind='spell', name='Stun', optional=true},
})
assert_action_list(kammavaca_preflight.Achoo.actions, {
    {kind='spell', name='Indi-Fury'},
    {kind='spell', name='Geo-Frailty'},
    {kind='spell', name='Indi-Fend'},
    {kind='spell', name='Cure III'},
})

local kammavaca_manual = kammavaca.manual_actions
assert(kammavaca_manual.sleep.character == 'Barneystinson')
assert(kammavaca_manual.sleep.adapter == 'brd-pack-sleep')
assert(kammavaca_manual.sleep.kind == nil)
assert(kammavaca_manual.sleep.name == nil)
assert(kammavaca_manual.sleep.target_names == nil)
assert(kammavaca_manual.silence.character == 'Smalls')
assert(kammavaca_manual.silence.adapter == 'rdm-exact-silence')
assert(#kammavaca_manual.silence.target_names == 1)
assert(kammavaca_manual.silence.target_names[1] == 'Kammavaca')
assert(util.count(kammavaca_manual) == 2)

-- Compiling or changing another profile cannot mutate an existing plan.
local locus_before = joined_commands(locus_plan.members.Barneystinson)
v1.support.brd.preset = 'safe'
local changed_v1 = assert(compiler.compile(util, schema, v1))
assert(joined_commands(changed_v1.members.Barneystinson)
    :find('gs c pstartbrd safe Tackleberry', 1, true))
local _, locus_again = compile('locus-dire-bats-tomb')
assert(joined_commands(locus_again.members.Barneystinson) == locus_before)

-- The distributed signature covers the complete declarative manifest, its
-- optional runtime, the compiled plan, all core engine sources, and only the
-- manual adapters actually used by that profile. This is broader than the
-- human-facing compiled-plan sentinel above by design.
local function full_signature(profile, plan, options)
    options = options or {}
    local copy = deep_copy(profile)
    local host_source = options.gearswap_host_source or 'host-source-v1'
    local host_live = options.gearswap_host_live or 'host-live-v1'
    copy.__profile_source_digest = options.profile_source or 'profile-v1'
    copy.__runtime_source_digest = options.runtime_source or 'runtime-v1'
    copy.__easyfarm_source_digest = options.easyfarm_source
        or (copy.easyfarm and copy.easyfarm.artifact
            and 'easyfarm-v1' or 'none')
    copy.__gearswap_host_source_digest = host_source
    copy.__gearswap_host_live_digest = host_live
    copy.__gearswap_adapter_source_digest = options.gearswap_adapter_source
        or 'profile-adapter-source-v1'
    copy.__gearswap_adapter_live_digest = options.gearswap_adapter_live
        or 'profile-adapter-live-v1'
    local adapters = deep_copy(options.adapters or {
        ['typed-action']={__source_digest='typed-v1'},
        ['clarion-extra-song']={__source_digest='clarion-v1'},
        ['brd-pack-sleep']={__source_digest='sleep-v1'},
        ['exact-enemy-action']={__source_digest='exact-enemy-v1'},
        ['rdm-exact-silence']={__source_digest='rdm-silence-v1'},
        unused={__source_digest='unused-v1'},
    })
    -- The dormant host wraps every job callback, so its exact source/live
    -- pair belongs to every engine closure. The selected fight adapter below
    -- remains profile-local.
    local engine_source = options.engine_source
        or ('engine-v1:'..host_source..':'..host_live)
    return fingerprint.plan(copy, deep_copy(plan), adapters, engine_source)
end

local boss_signature = full_signature(boss, boss_plan)
local function assert_manifest_change(mutator, label)
    local changed = deep_copy(boss)
    mutator(changed)
    assert(full_signature(changed, boss_plan) ~= boss_signature,
        label..' was omitted from the full profile signature')
end
assert_manifest_change(function(value)
    value.members.Tackleberry.sub_jobs = {'BLU'}
end, 'subjob')
assert_manifest_change(function(value)
    value.roles.primary_healer = 'Barneystinson'
end, 'role')
assert_manifest_change(function(value)
    value.manual_actions.flash.name = 'Cure IV'
end, 'manual action')
assert_manifest_change(function(value)
    value.safety.reraise = false
end, 'safety policy')
assert_manifest_change(function(value)
    value.easyfarm = {character='Dolomedes', note='manual test'}
end, 'EasyFarm policy')
assert_manifest_change(function(value)
    value.advisories[1] = value.advisories[1]..' changed'
end, 'advisory')
assert_manifest_change(function(value)
    value.combat.target_exclusions = {'elemental'}
end, 'target exclusion')

assert(full_signature(boss, boss_plan, {profile_source='profile-v2'})
    ~= boss_signature)
assert(full_signature(boss, boss_plan, {runtime_source='runtime-v2'})
    ~= boss_signature)
assert(full_signature(boss, boss_plan, {engine_source='engine-v2'})
    ~= boss_signature)

-- EasyFarm files are profile-owned signature inputs. Changing the Locus
-- artifact invalidates only Locus; unrelated Limbus and boss signatures stay
-- byte-for-byte stable when their own files and manifests are unchanged.
local function profile_signature_set(locus_artifact_digest)
    return {
        locus=full_signature(locus, locus_plan, {
            easyfarm_source=locus_artifact_digest,
        }),
        limbus=full_signature(limbus, limbus_plan, {
            easyfarm_source='limbus-easyfarm-v1',
        }),
        boss=full_signature(boss, boss_plan, {
            easyfarm_source='none',
        }),
    }
end
local artifact_signatures_before = profile_signature_set('locus-easyfarm-v1')
local artifact_signatures_after = profile_signature_set('locus-easyfarm-v2')
assert(artifact_signatures_after.locus ~= artifact_signatures_before.locus)
assert(artifact_signatures_after.limbus == artifact_signatures_before.limbus)
assert(artifact_signatures_after.boss == artifact_signatures_before.boss)
local changed_adapter = {
    ['typed-action']={__source_digest='typed-v2'},
    ['clarion-extra-song']={__source_digest='clarion-v1'},
    ['brd-pack-sleep']={__source_digest='sleep-v1'},
}
assert(full_signature(boss, boss_plan, {adapters=changed_adapter})
    ~= boss_signature)
local changed_unused_adapter = {
    ['typed-action']={__source_digest='typed-v1'},
    ['clarion-extra-song']={__source_digest='clarion-v1'},
    ['brd-pack-sleep']={__source_digest='sleep-v1'},
    unused={__source_digest='unused-v2'},
}
assert(full_signature(boss, boss_plan, {adapters=changed_unused_adapter})
    == boss_signature)
local kammavaca_signature = full_signature(kammavaca, kammavaca_plan)
local changed_unused_exact_enemy_adapter = {
    ['typed-action']={__source_digest='typed-v1'},
    ['clarion-extra-song']={__source_digest='clarion-v1'},
    ['brd-pack-sleep']={__source_digest='sleep-v1'},
    ['exact-enemy-action']={__source_digest='exact-enemy-v2'},
    ['rdm-exact-silence']={__source_digest='rdm-silence-v1'},
}
assert(full_signature(kammavaca, kammavaca_plan, {
    adapters=changed_unused_exact_enemy_adapter,
}) == kammavaca_signature)
local changed_rdm_silence_adapter = {
    ['typed-action']={__source_digest='typed-v1'},
    ['clarion-extra-song']={__source_digest='clarion-v1'},
    ['brd-pack-sleep']={__source_digest='sleep-v1'},
    ['exact-enemy-action']={__source_digest='exact-enemy-v1'},
    ['rdm-exact-silence']={__source_digest='rdm-silence-v2'},
}
assert(full_signature(kammavaca, kammavaca_plan, {
    adapters=changed_rdm_silence_adapter,
}) ~= kammavaca_signature)
local changed_sleep_adapter = {
    ['typed-action']={__source_digest='typed-v1'},
    ['clarion-extra-song']={__source_digest='clarion-v1'},
    ['brd-pack-sleep']={__source_digest='sleep-v2'},
    ['exact-enemy-action']={__source_digest='exact-enemy-v1'},
    ['rdm-exact-silence']={__source_digest='rdm-silence-v1'},
}
assert(full_signature(kammavaca, kammavaca_plan, {
    adapters=changed_sleep_adapter,
}) ~= kammavaca_signature)

-- The stable host is in every callback path and therefore every closure.
-- A versioned fight adapter remains part of only its declaring profile.
genmei_signature = full_signature(genmei, genmei_plan)
for _, option in ipairs{
    'gearswap_host_source', 'gearswap_host_live',
} do
    local changed = {[option]=option..'-v2'}
    assert(full_signature(genmei, genmei_plan, changed) ~= genmei_signature)
    assert(full_signature(locus, locus_plan, changed)
        ~= full_signature(locus, locus_plan))
    assert(full_signature(kammavaca, kammavaca_plan, changed)
        ~= kammavaca_signature)
end
for _, option in ipairs{
    'gearswap_adapter_source', 'gearswap_adapter_live',
} do
    local changed = {[option]=option..'-v2'}
    assert(full_signature(genmei, genmei_plan, changed) ~= genmei_signature,
        option..' was omitted from the pinned Genmei closure')
    assert(full_signature(locus, locus_plan, changed)
        == full_signature(locus, locus_plan),
        option..' leaked into the adapter-free Locus closure')
    assert(full_signature(kammavaca, kammavaca_plan, changed)
        == kammavaca_signature,
        option..' leaked into the adapter-free Kammavaca closure')
end
local changed_plan = deep_copy(boss_plan)
changed_plan.members.Dolomedes.commands[#changed_plan.members.Dolomedes.commands + 1]
    = 'synthetic compiled change'
assert(full_signature(boss, changed_plan) ~= boss_signature)
assert(fingerprint.canonical({z=3, a=1, m=2})
    == fingerprint.canonical({m=2, z=3, a=1}))

local raw_profile = deep_copy(locus)
raw_profile.commands = {'equip range "Blurred Harp +1"'}
local raw_plan, raw_errors = compiler.compile(util, schema, raw_profile)
assert(raw_plan == nil)
assert(table.concat(raw_errors, ' '):find(
    'Profiles may not contain raw setup/teardown commands.', 1, true))

-- A broken runtime quarantines only its own directory.
local bad_runtime_profile = deep_copy(locus)
bad_runtime_profile.id = 'zz-bad-runtime'
bad_runtime_profile.policy_id = 'pt-bad-runtime'
bad_runtime_profile.aliases = {'bad-runtime'}
local fake_root = '/virtual/'
local function fake_artifact_path(profile)
    return fake_root..profile.id..'/'..profile.easyfarm.artifact
end
local fake_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_artifact_path(locus)] = true,
    [fake_root..bad_runtime_profile.id..'/profile.lua'] =
        function() return deep_copy(bad_runtime_profile) end,
    [fake_artifact_path(bad_runtime_profile)] = true,
    [fake_root..bad_runtime_profile.id..'/runtime.lua'] =
        function() return {} end,
}
local discovered, discovered_aliases, discovery_errors = profile_loader.discover(
    util, schema, fake_root,
    function() return {bad_runtime_profile.id, locus.id} end,
    function(path) return fake_files[path] ~= nil end,
    function(path) return fake_files[path] end,
    function(path) return 'digest:'..path end)
assert(discovered[locus.id] ~= nil)
assert(discovered[bad_runtime_profile.id] == nil)
assert(discovered_aliases.locus == locus.id)
assert(#discovery_errors == 1)
assert(discovered[locus.id].__profile_source_digest
    == 'digest:'..fake_root..locus.id..'/profile.lua')
assert(discovered[locus.id].__runtime_source_digest == 'none')
assert(discovered[locus.id].__easyfarm_source_digest
    == 'digest:'..fake_artifact_path(locus))

-- A declared but absent EasyFarm artifact quarantines only its owner. A
-- separate valid profile remains loadable with its canonical aliases intact.
local missing_artifact_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_root..boss.id..'/profile.lua'] = function() return deep_copy(boss) end,
}
local asset_profiles, asset_aliases, asset_errors = profile_loader.discover(
    util, schema, fake_root,
    function() return {locus.id, boss.id} end,
    function(path) return missing_artifact_files[path] ~= nil end,
    function(path) return missing_artifact_files[path] end,
    function(path) return 'digest:'..path end)
assert(asset_profiles[locus.id] == nil)
assert(asset_aliases.locus == nil)
assert(asset_profiles[boss.id] ~= nil)
assert(asset_aliases.ddw1boss == boss.id)
assert(#asset_errors == 1)
assert(asset_errors[1]:find(
    'EasyFarm artifact is missing: '..locus.easyfarm.artifact, 1, true))

-- The append-only identity registry protects established commands. Even a
-- lexicographically earlier new directory that claims `locus` is quarantined;
-- the existing shortcut remains usable.
local collision = deep_copy(locus)
collision.id = 'aaa-new-profile'
collision.policy_id = 'pt-new-profile'
collision.aliases = {'locus'}
local collision_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_artifact_path(locus)] = true,
    [fake_root..collision.id..'/profile.lua'] = function() return collision end,
    [fake_artifact_path(collision)] = true,
}
local collision_profiles, collision_aliases, collision_errors =
    profile_loader.discover(util, schema, fake_root,
        function() return {collision.id, locus.id} end,
        function(path) return collision_files[path] ~= nil end,
        function(path) return collision_files[path] end, nil, {
            schema=1,
            reserved_commands={},
            identities={
                {ordinal=1, id=locus.id, policy_id=locus.policy_id,
                    aliases=deep_copy(locus.aliases)},
                {ordinal=2, id=collision.id, policy_id=collision.policy_id,
                    aliases=deep_copy(collision.aliases)},
            },
        })
assert(collision_profiles[locus.id] and not collision_profiles[collision.id])
assert(collision_aliases.locus == locus.id)
assert(table.concat(collision_errors, ' '):find(
    'reuses established command locus', 1, true))

-- Published manual-action shorthands share the public command namespace and
-- cannot later be repurposed as a profile alias.
reserved_command_collision = deep_copy(locus)
reserved_command_collision.id = 'aaa-silence-profile'
reserved_command_collision.policy_id = 'pt-silence-profile'
reserved_command_collision.aliases = {'silence'}
reserved_command_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_artifact_path(locus)] = true,
    [fake_root..reserved_command_collision.id..'/profile.lua'] =
        function() return reserved_command_collision end,
    [fake_artifact_path(reserved_command_collision)] = true,
}
reserved_command_profiles, reserved_command_aliases,
    reserved_command_errors = profile_loader.discover(
        util, schema, fake_root,
        function() return {reserved_command_collision.id, locus.id} end,
        function(path) return reserved_command_files[path] ~= nil end,
        function(path) return reserved_command_files[path] end, nil, {
            schema=1,
            reserved_commands={'silence'},
            identities={
                {ordinal=1, id=locus.id, policy_id=locus.policy_id,
                    aliases=deep_copy(locus.aliases)},
                {ordinal=2, id=reserved_command_collision.id,
                    policy_id=reserved_command_collision.policy_id,
                    aliases=deep_copy(reserved_command_collision.aliases)},
            },
        })
assert(reserved_command_profiles[locus.id]
    and not reserved_command_profiles[reserved_command_collision.id])
assert(reserved_command_aliases.locus == locus.id)
assert(table.concat(reserved_command_errors, ' '):find(
    'reuses established command silence', 1, true))

-- A command appended after an established profile cannot reverse ownership
-- and quarantine that profile. The older identity remains authoritative.
later_reserved_profiles, later_reserved_aliases, later_reserved_errors =
    profile_loader.discover(util, schema, fake_root,
        function() return {locus.id} end,
        function(path) return collision_files[path] ~= nil end,
        function(path) return collision_files[path] end, nil, {
            schema=1,
            reserved_commands={'locus'},
            identities={
                {ordinal=1, id=locus.id, policy_id=locus.policy_id,
                    aliases=deep_copy(locus.aliases)},
            },
        })
assert(later_reserved_profiles[locus.id])
assert(later_reserved_aliases.locus == locus.id)
assert(table.concat(later_reserved_errors, ' '):find(
    'later command ignored', 1, true))

-- The same registry rule protects established PartyCombat authority names.
-- A later entry cannot seize the old policy even if its directory sorts first.
local duplicate_policy = deep_copy(locus)
duplicate_policy.id = 'aaa-policy-copy'
duplicate_policy.policy_id = locus.policy_id
duplicate_policy.aliases = {'zzpolicycopy'}
local duplicate_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_artifact_path(locus)] = true,
    [fake_root..duplicate_policy.id..'/profile.lua'] =
        function() return duplicate_policy end,
    [fake_artifact_path(duplicate_policy)] = true,
}
local policy_profiles, policy_aliases, policy_errors =
    profile_loader.discover(util, schema, fake_root,
        function() return {duplicate_policy.id, locus.id} end,
        function(path) return duplicate_files[path] ~= nil end,
        function(path) return duplicate_files[path] end, nil, {
            schema=1,
            reserved_commands={},
            identities={
                {ordinal=1, id=locus.id, policy_id=locus.policy_id,
                    aliases=deep_copy(locus.aliases)},
                {ordinal=2, id=duplicate_policy.id,
                    policy_id=duplicate_policy.policy_id,
                    aliases=deep_copy(duplicate_policy.aliases)},
            },
        })
assert(policy_profiles[locus.id] ~= nil)
assert(policy_profiles[duplicate_policy.id] == nil)
assert(policy_aliases.locus == locus.id)
assert(policy_aliases.zzpolicycopy == nil)
assert(table.concat(policy_errors, ' '):find(
    'reuses an established id or policy_id', 1, true))

-- A malformed profile that crashes schema validation is quarantined without
-- preventing an unrelated reviewed profile from loading.
local crashing_schema = {
    validate=function(_, profile, directory_id)
        if directory_id == 'zz-schema-crash' then error('synthetic schema fault') end
        return schema.validate(util, profile, directory_id)
    end,
}
local schema_crash = deep_copy(locus)
schema_crash.id = 'zz-schema-crash'
schema_crash.policy_id = 'pt-schema-crash'
schema_crash.aliases = {'schemacrash'}
local schema_files = {
    [fake_root..locus.id..'/profile.lua'] = function() return deep_copy(locus) end,
    [fake_artifact_path(locus)] = true,
    [fake_root..schema_crash.id..'/profile.lua'] = function() return schema_crash end,
}
local schema_profiles, _, schema_errors = profile_loader.discover(
    util, crashing_schema, fake_root,
    function() return {schema_crash.id, locus.id} end,
    function(path) return schema_files[path] ~= nil end,
    function(path) return schema_files[path] end)
assert(schema_profiles[locus.id] ~= nil)
assert(schema_profiles[schema_crash.id] == nil)
local schema_error_text = table.concat(schema_errors, ' ')
assert(schema_error_text:find('schema validation failed:', 1, true))
assert(schema_error_text:find('synthetic schema fault', 1, true))

-- Profile runtimes receive typed action requests, never a raw command API.
local issued = {}
local actions = action_api.create(function(command) issued[#issued + 1] = command end)
assert(actions.controller('brd', 'warble', 1234))
assert(issued[#issued] == 'gs c pstartbrd warble 1234')
assert(actions.cast('Cure IV', '<stpc>'))
assert(issued[#issued] == 'input /ma "Cure IV" <stpc>')
assert(actions.ability('Sentinel', '<me>'))
assert(issued[#issued] == 'input /ja "Sentinel" <me>')
assert(actions.weaponskill('Leaden Salute', '<t>'))
assert(issued[#issued] == 'input /ws "Leaden Salute" <t>')
assert(actions.cast('Silence', '1'))
assert(issued[#issued] == 'input /ma "Silence" 1')
assert(actions.ability('Provoke', '4294967295'))
assert(issued[#issued] == 'input /ja "Provoke" 4294967295')
assert(actions.weaponskill('Savage Blade', '314159'))
assert(issued[#issued] == 'input /ws "Savage Blade" 314159')
assert(actions.item('Echo Drops', '271828'))
assert(issued[#issued] == 'input /item "Echo Drops" 271828')
assert(actions.controller('rdm', 'silence', '000400'))
assert(issued[#issued] == 'gs c pstartrdm silence 400')
local before_reject = #issued
assert(actions.controller('brd', 'sleep;equip') == false)
assert(actions.controller('brd', 'off') == false)
assert(actions.controller('brd', 'ambuscade-v1', 'Tackleberry') == false)
assert(actions.controller('rdm', 'anything') == false)
assert(actions.cast('Cure"; equip', '<me>') == false)
for _, unsafe_target in ipairs{
    '0', '4294967296', '-1', '1.0', '123;equip', '123 target',
} do
    assert(actions.cast('Silence', unsafe_target) == false)
end
assert(actions.controller('unknown', 'anything') == false)
assert(#issued == before_reject)

local typed = module('adapters/manual/typed-action.lua')
assert(typed.execute({actions=actions}, {
    kind='cast', name='Crusade', target='<me>',
}))
assert(issued[#issued] == 'input /ma "Crusade" <me>')
local pack_sleep = module('adapters/manual/brd-pack-sleep.lua')
assert(pack_sleep.execute({actions=actions}, limbus.manual_actions.sleep))
assert(issued[#issued] == 'gs c pstartbrd sleep')
assert(not issued[#issued]:lower():find('equip', 1, true))
assert(not issued[#issued]:lower():find('range=', 1, true))
assert(not issued[#issued]:lower():find('ammo=', 1, true))

local exact_enemy = module('adapters/manual/exact-enemy-action.lua')
local exact_mobs = {
    {id=199, name='Wrong Enemy', spawn_type=16,
        valid_target=true, hpp=100, distance=0.1},
    {id=400, name='Kammavaca', spawn_type=16,
        valid_target=true, hpp=100, distance=4},
}
local exact_context = {
    actions=actions,
    mob_array=function() return exact_mobs end,
}
local exact_policy = {
    kind='cast', name='Silence', target_names={'Kammavaca'},
}
assert(exact_enemy.execute(exact_context, exact_policy))
assert(issued[#issued] == 'input /ma "Silence" 400')

local before_exact_reject = #issued
local bad_exact_policy = deep_copy(exact_policy)
bad_exact_policy.target_names = {'Kammavaca; equip'}
local exact_ok, exact_reason = exact_enemy.execute(
    exact_context, bad_exact_policy)
assert(exact_ok == false and exact_reason == 'invalid exact-enemy action policy')
local no_living_context = {
    actions=actions,
    mob_array=function()
        return {
            {id=0, name='Kammavaca', spawn_type=16,
                valid_target=true, hpp=100},
            {id=4294967296, name='Kammavaca', spawn_type=16,
                valid_target=true, hpp=100},
            {id=401, name='Kammavaca', spawn_type=14,
                valid_target=true, hpp=100},
            {id=402, name='Kammavaca', spawn_type=16,
                valid_target=false, hpp=100},
            {id=403, name='Kammavaca', spawn_type=16,
                valid_target=true, hpp=0},
        }
    end,
}
exact_ok, exact_reason = exact_enemy.execute(
    no_living_context, exact_policy)
assert(exact_ok == false and exact_reason == 'no living exact enemy is visible')
assert(#issued == before_exact_reject)

local queued_silence = module('adapters/manual/rdm-exact-silence.lua')
local queue_context = {
    actions=actions,
    mob_array=function() return exact_mobs end,
    party_claimed=function(mob) return mob.id == 400 end,
}
local queued_policy = {
    target_names={'Kammavaca'}, prefer_highest_hpp=true,
}
assert(queued_silence.execute(queue_context, queued_policy))
assert(issued[#issued] == 'gs c pstartrdm silence 400')
local queued_count = #issued
queue_context.party_claimed = function() return false end
local queue_ok, queue_reason = queued_silence.execute(
    queue_context, queued_policy)
assert(queue_ok == false
    and queue_reason == 'no living party-claimed exact enemy is visible')
local malformed_queue_policy = {target_names={'Kammavaca; equip'}}
queue_ok, queue_reason = queued_silence.execute(
    queue_context, malformed_queue_policy)
assert(queue_ok == false and queue_reason == 'invalid exact Silence policy')
assert(#issued == queued_count)

local clarion = module('adapters/manual/clarion-extra-song.lua')
local clarion_context = {
    actions=actions,
    has_buff=function(name) return name == 'Clarion Call' end,
}
assert(clarion.execute(clarion_context, {
    kind='cast', name="Mage's Ballad II", target='<me>',
}))
assert(issued[#issued] == 'input /ma "Mage\'s Ballad II" <me>')
clarion_context.has_buff = function() return false end
local clarion_count = #issued
assert(clarion.execute(clarion_context, {
    kind='cast', name="Mage's Ballad II", target='<me>',
}) == false)
assert(#issued == clarion_count)

local bad_typed = deep_copy(boss)
bad_typed.manual_actions.flash.target = '<t>;equip'
local bad_typed_plan, bad_typed_errors = compiler.compile(
    util, schema, bad_typed)
assert(bad_typed_plan == nil)
assert(table.concat(bad_typed_errors, ' '):find(
    'Invalid typed manual action flash.', 1, true))

local bad_pld_switch = deep_copy(boss)
bad_pld_switch.support.pld.native_tank = 'off'
local bad_pld_plan, bad_pld_errors = compiler.compile(
    util, schema, bad_pld_switch)
assert(bad_pld_plan == nil)
assert(table.concat(bad_pld_errors, ' '):find(
    'support.pld.native_tank must be boolean.', 1, true))

do
    local bad_pld_weapon = deep_copy(september_qutrub_no_cait)
    bad_pld_weapon.support.pld.weapon_mode = 'Naegling; equip'
    local bad_pld_weapon_plan, bad_pld_weapon_errors = compiler.compile(
        util, schema, bad_pld_weapon)
    assert(bad_pld_weapon_plan == nil)
    assert(table.concat(bad_pld_weapon_errors, ' '):find(
        'support.pld.weapon_mode is invalid.', 1, true))

    local bad_rdm_healbot = deep_copy(september_qutrub_no_cait)
    bad_rdm_healbot.support.rdm.healbot = 'unbounded'
    local bad_rdm_healbot_plan, bad_rdm_healbot_errors = compiler.compile(
        util, schema, bad_rdm_healbot)
    assert(bad_rdm_healbot_plan == nil)
    assert(table.concat(bad_rdm_healbot_errors, ' '):find(
        'support.rdm.healbot must be off or cure-na.', 1, true))

    local bad_action_label = deep_copy(september_qutrub_no_cait)
    bad_action_label.preflight.members.Dolomedes.actions[1].name =
        'Last Stand; equip'
    local bad_action_plan, bad_action_errors = compiler.compile(
        util, schema, bad_action_label)
    assert(bad_action_plan == nil)
    assert(table.concat(bad_action_errors, ' '):find(
        'contains an invalid action requirement.', 1, true))
end

local bad_geo_entrust = deep_copy(locus)
bad_geo_entrust.support.geo.combat_entrust_only = 'sometimes'
local bad_geo_plan, bad_geo_errors = compiler.compile(
    util, schema, bad_geo_entrust)
assert(bad_geo_plan == nil)
assert(table.concat(bad_geo_errors, ' '):find(
    'support.geo.combat_entrust_only must be boolean.', 1, true))

local bad_native_autows = deep_copy(kammavaca)
bad_native_autows.offense.Achoo.disable_native_autows = 'sometimes'
local bad_native_plan, bad_native_errors = compiler.compile(
    util, schema, bad_native_autows)
assert(bad_native_plan == nil)
assert(table.concat(bad_native_errors, ' '):find(
    'Offense disable_native_autows must be boolean for Achoo.', 1, true))

local bad_preflight_buffs = deep_copy(genmei)
bad_preflight_buffs.preflight.members.Dolomedes.buffs = {'March', 'march'}
local bad_buff_plan, bad_buff_errors = compiler.compile(
    util, schema, bad_preflight_buffs)
assert(bad_buff_plan == nil)
assert(table.concat(bad_buff_errors, ' '):find(
    'invalid or duplicate buff requirement', 1, true))

local bad_preflight_retry = deep_copy(genmei)
bad_preflight_retry.preflight.auto_retry_seconds = 1
local bad_retry_plan, bad_retry_errors = compiler.compile(
    util, schema, bad_preflight_retry)
assert(bad_retry_plan == nil)
assert(table.concat(bad_retry_errors, ' '):find(
    'preflight.auto_retry_seconds must be between 3 and 30 seconds.',
    1, true))

bad_preflight_age = deep_copy(genmei)
bad_preflight_age.preflight.max_age_seconds = 20
bad_age_plan, bad_age_errors = compiler.compile(
    util, schema, bad_preflight_age)
assert(bad_age_plan == nil)
assert(table.concat(bad_age_errors, ' '):find(
    'preflight.max_age_seconds must be between 30 and 600 seconds.',
    1, true))

bad_gearswap_adapter = deep_copy(genmei)
bad_gearswap_adapter.gearswap_adapter.actions = {'lead', 'lead'}
bad_adapter_plan, bad_adapter_errors = compiler.compile(
    util, schema, bad_gearswap_adapter)
assert(bad_adapter_plan == nil)
assert(table.concat(bad_adapter_errors, ' '):find(
    'gearswap_adapter.actions contains an invalid, reserved, or duplicate semantic.',
    1, true))

-- GearSwap adapter metadata must use the stable host's exact lower-case
-- grammar.  Catalog validation must reject values the host would reject.
bad_adapter_id_grammar = deep_copy(genmei)
bad_adapter_id_grammar.gearswap_adapter.id = 'Genmei'
bad_adapter_id_plan, bad_adapter_id_errors = compiler.compile(
    util, schema, bad_adapter_id_grammar)
assert(bad_adapter_id_plan == nil)
assert(table.concat(bad_adapter_id_errors, ' '):find(
    'GearSwap-host-compatible lower-case grammar', 1, true))

bad_adapter_underscore_id = deep_copy(genmei)
bad_adapter_underscore_id.gearswap_adapter.id = 'genmei_adapter'
bad_adapter_underscore_plan, bad_adapter_underscore_errors = compiler.compile(
    util, schema, bad_adapter_underscore_id)
assert(bad_adapter_underscore_plan == nil)
assert(table.concat(bad_adapter_underscore_errors, ' '):find(
    'GearSwap-host-compatible lower-case grammar', 1, true))

bad_adapter_controller_grammar = deep_copy(genmei)
bad_adapter_controller_grammar.gearswap_adapter.controller = 'gen_mei'
bad_adapter_controller_plan, bad_adapter_controller_errors = compiler.compile(
    util, schema, bad_adapter_controller_grammar)
assert(bad_adapter_controller_plan == nil)
assert(table.concat(bad_adapter_controller_errors, ' '):find(
    'GearSwap-host-compatible lower-case grammar', 1, true))

bad_adapter_action_grammar = deep_copy(genmei)
bad_adapter_action_grammar.gearswap_adapter.actions = {'Lead'}
bad_adapter_action_plan, bad_adapter_action_errors = compiler.compile(
    util, schema, bad_adapter_action_grammar)
assert(bad_adapter_action_plan == nil)
assert(table.concat(bad_adapter_action_errors, ' '):find(
    'gearswap_adapter.actions contains an invalid', 1, true))

bad_adapter_semver = deep_copy(genmei)
bad_adapter_semver.gearswap_adapter.version = '02.1.0'
bad_adapter_semver_plan, bad_adapter_semver_errors = compiler.compile(
    util, schema, bad_adapter_semver)
assert(bad_adapter_semver_plan == nil)
assert(table.concat(bad_adapter_semver_errors, ' '):find(
    'canonical semantic version', 1, true))

bad_adapter_protocol = deep_copy(genmei)
bad_adapter_protocol.gearswap_adapter.protocol = 3
for _, policy in pairs(bad_adapter_protocol.preflight.members) do
    policy.controller.protocol = 3
end
bad_adapter_protocol_plan, bad_adapter_protocol_errors = compiler.compile(
    util, schema, bad_adapter_protocol)
assert(bad_adapter_protocol_plan == nil)
assert(table.concat(bad_adapter_protocol_errors, ' '):find(
    'supported protocol 1 or 2', 1, true))

incomplete_protocol_two = deep_copy(genmei)
incomplete_protocol_two.gearswap_adapter.protocol = 2
for _, policy in pairs(incomplete_protocol_two.preflight.members) do
    policy.controller.protocol = 2
end
incomplete_protocol_two_plan, incomplete_protocol_two_errors = compiler.compile(
    util, schema, incomplete_protocol_two)
assert(incomplete_protocol_two_plan == nil)
assert(table.concat(incomplete_protocol_two_errors, ' '):find(
    'revisioned operator semantic', 1, true))

-- A new adapter controller is profile data, not a central schema edit.  Any
-- host-compatible name compiles when every member pins the same proof.
future_adapter = deep_copy(genmei)
future_adapter.gearswap_adapter.controller = 'future-fight'
for _, policy in pairs(future_adapter.preflight.members) do
    policy.controller.name = 'future-fight'
end
future_adapter_plan, future_adapter_errors = compiler.compile(
    util, schema, future_adapter)
assert(future_adapter_plan, table.concat(future_adapter_errors or {}, ' '))

foreign_adapter_owner = deep_copy(genmei)
foreign_adapter_owner.id = 'new-fight-copy'
foreign_adapter_owner.policy_id = 'pt-new-fight-copy'
foreign_adapter_owner.aliases = {'newfightcopy'}
foreign_adapter_owner_plan, foreign_adapter_owner_errors = compiler.compile(
    util, schema, foreign_adapter_owner)
assert(foreign_adapter_owner_plan == nil)
assert(table.concat(foreign_adapter_owner_errors, ' '):find(
    'fight adapters cannot be shared between profiles', 1, true))

nonblocking_adapter = deep_copy(genmei)
nonblocking_adapter.preflight.required_before_combat = false
nonblocking_adapter_plan, nonblocking_adapter_errors = compiler.compile(
    util, schema, nonblocking_adapter)
assert(nonblocking_adapter_plan,
    table.concat(nonblocking_adapter_errors or {}, ' '))

unproved_adapter_member = deep_copy(genmei)
unproved_adapter_member.preflight.members.Barneystinson.controller = nil
unproved_adapter_plan, unproved_adapter_errors = compiler.compile(
    util, schema, unproved_adapter_member)
assert(unproved_adapter_plan == nil)
assert(#(unproved_adapter_errors or {}) > 0)

missing_adapter_preflight = deep_copy(genmei)
missing_adapter_preflight.preflight = nil
missing_adapter_preflight_plan, missing_adapter_preflight_errors =
    compiler.compile(util, schema, missing_adapter_preflight)
assert(missing_adapter_preflight_plan == nil)
assert(#(missing_adapter_preflight_errors or {}) > 0)

missing_gearswap_adapter = deep_copy(genmei)
missing_gearswap_adapter.gearswap_adapter = nil
missing_adapter_plan, missing_adapter_errors = compiler.compile(
    util, schema, missing_gearswap_adapter)
assert(missing_adapter_plan == nil)
assert(table.concat(missing_adapter_errors, ' '):find(
    'does not match the pinned GearSwap adapter.', 1, true))

local bad_exact_action = deep_copy(kammavaca)
bad_exact_action.manual_actions.silence.target_names = {
    'Kammavaca', 'kammavaca',
}
local bad_exact_plan, bad_exact_errors = compiler.compile(
    util, schema, bad_exact_action)
assert(bad_exact_plan == nil)
assert(table.concat(bad_exact_errors, ' '):find(
    'Invalid queued-Silence manual action silence.', 1, true))

local bad_sleep = deep_copy(locus)
bad_sleep.manual_actions = {
    sleep={character='Smalls', adapter='typed-action',
        kind='cast', name='Sleep', target='<t>'},
}
local bad_sleep_plan, bad_sleep_errors = compiler.compile(
    util, schema, bad_sleep)
assert(bad_sleep_plan == nil)
assert(table.concat(bad_sleep_errors, ' '):find(
    'Manual action sleep is reserved for the Barneystinson '
        ..'brd-pack-sleep controller.', 1, true))

-- Command names are reserved globally so a future profile cannot shadow the
-- control plane, either as a canonical id, alias, or direct manual action.
local reserved_id = deep_copy(locus)
reserved_id.id = 'use'
reserved_id.policy_id = 'pt-reserved-id'
reserved_id.aliases = {'reservedid'}
local reserved_id_plan, reserved_id_errors = compiler.compile(
    util, schema, reserved_id)
assert(reserved_id_plan == nil)
assert(table.concat(reserved_id_errors, ' '):find(
    'Profile id is a reserved PartyTactics command.', 1, true))

local reserved_alias = deep_copy(locus)
reserved_alias.aliases = {'status'}
local reserved_alias_plan, reserved_alias_errors = compiler.compile(
    util, schema, reserved_alias)
assert(reserved_alias_plan == nil)
assert(table.concat(reserved_alias_errors, ' '):find(
    'Alias status is a reserved PartyTactics command.', 1, true))

local reserved_sleep_alias = deep_copy(locus)
reserved_sleep_alias.aliases = {'sleep'}
local reserved_sleep_alias_plan, reserved_sleep_alias_errors = compiler.compile(
    util, schema, reserved_sleep_alias)
assert(reserved_sleep_alias_plan == nil)
assert(table.concat(reserved_sleep_alias_errors, ' '):find(
    'Alias sleep is a reserved PartyTactics command.', 1, true))

local reserved_action = deep_copy(locus)
reserved_action.manual_actions = {
    arm={
        character='Tackleberry', adapter='typed-action',
        kind='ability', name='Sentinel', target='<me>',
    },
}
local reserved_action_plan, reserved_action_errors = compiler.compile(
    util, schema, reserved_action)
assert(reserved_action_plan == nil)
assert(table.concat(reserved_action_errors, ' '):find(
    'Manual action arm is a reserved PartyTactics command.', 1, true))

local missing_exclusions = deep_copy(locus)
missing_exclusions.combat.target_exclusions = nil
local missing_exclusions_plan, missing_exclusions_errors = compiler.compile(
    util, schema, missing_exclusions)
assert(missing_exclusions_plan == nil)
assert(table.concat(missing_exclusions_errors, ' '):find(
    'combat.target_exclusions must be explicitly declared.', 1, true))

local unsupported_exclusion = deep_copy(locus)
unsupported_exclusion.combat.target_exclusions = {'arcana'}
local unsupported_exclusion_plan, unsupported_exclusion_errors =
    compiler.compile(util, schema, unsupported_exclusion)
assert(unsupported_exclusion_plan == nil)
assert(table.concat(unsupported_exclusion_errors, ' '):find(
    'Unsupported target exclusion arcana.', 1, true))

-- Any non-attacker may receive a reviewed GearSwap weapon mode without
-- joining synchronized targeting. That is a loadout only: AutoWS2 stays off.
-- Automatic offense still requires membership in the attacker set.
assert(boss_plan.members.Kickpuncher.owns_autows2 == true)
assert(boss_kick:find('gs c weapons Tauret; wait 1; aws2 off', 1, true))
local automatic_non_attacker = deep_copy(boss)
automatic_non_attacker.offense.Kickpuncher.automatic = true
local automatic_non_attacker_plan, automatic_non_attacker_errors =
    compiler.compile(util, schema, automatic_non_attacker)
assert(automatic_non_attacker_plan == nil)
assert(table.concat(automatic_non_attacker_errors, ' '):find(
    'must be loadout-only (automatic=false).', 1, true))

local untargeted_non_attacker = deep_copy(boss)
for index, name in ipairs(untargeted_non_attacker.combat.targeters) do
    if name == 'Kickpuncher' then
        table.remove(untargeted_non_attacker.combat.targeters, index)
        break
    end
end
local untargeted_non_attacker_plan, untargeted_non_attacker_errors =
    compiler.compile(util, schema, untargeted_non_attacker)
assert(untargeted_non_attacker_plan ~= nil,
    table.concat(untargeted_non_attacker_errors, ' '))
assert(table.concat(
    untargeted_non_attacker_plan.members.Kickpuncher.commands, '; '):find(
    'gs c weapons Tauret; wait 1; aws2 off', 1, true))

-- Loaded fight code cannot reach Windower, require/io/debug, or mutate the
-- standard libraries even if a future module attempts to do so directly.
local chunk_factory = loadstring or load
local previous_windower = _G.windower
_G.windower = {send_command=function() error('sandbox escape') end}
local unsafe_chunk = assert(chunk_factory([[
    return function()
        local write_ok = pcall(function() math.profile_escape = true end)
        return windower, require, io, debug, _G, write_ok, math.sqrt(9)
    end
]]))
local wrapped, sandbox_error = sandbox.wrap(unsafe_chunk)
assert(wrapped, sandbox_error)
local probe = wrapped()
exposed_windower, exposed_require, exposed_io, exposed_debug,
    exposed_global, write_ok, square_root = probe()
assert(exposed_windower == nil and exposed_require == nil and exposed_io == nil)
assert(exposed_debug == nil and exposed_global == nil)
assert(write_ok == false and square_root == 3)
_G.windower = previous_windower

print('PartyTactics profile/compiler tests passed')
