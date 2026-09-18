local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path)
    assert(loader,reason)
    return loader()
end

local util=module('lib/util.lua')
local schema=module('lib/schema.lua')
local compiler=module('lib/compiler.lua')
local identity_extensions=module('lib/identity_extensions.lua')
local profile=module('profiles/sortie-objective-a-magic-kill-v1/profile.lua')
local plan,errors=compiler.compile(util,schema,profile)
assert(plan,table.concat(errors or {},' '))

local identity=module(
    'data/profile_identities/sortie-objective-a-magic-kill-v1.lua')
assert(identity.ordinal==17 and identity.id==profile.id)
assert(identity.policy_id==profile.policy_id)
assert(table.concat(identity.aliases,',')==table.concat(profile.aliases,','))

local sidecars={
    'ambuscade-2026-09-v1-qutrub-bigwig.lua',
    'ambuscade-2026-09-v2-hydra-alluttu.lua',
    'ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua',
    'vagary-direct-rancibus.lua','sortie-objective-c-device-kill-v1.lua',
    'sortie-objective-d-demisang-clear-v1.lua','sortie-boss-skomora-v1.lua',
    'sortie-boss-ghatjot-v1.lua','sortie-objective-c-magic-burst-v1.lua',
    'sortie-objective-a-magic-kill-v1.lua',
}
local registry,registry_errors=identity_extensions.extend(util,
    module('data/profile_registry.lua'),BASE..'data/profile_identities/',
    function() return sidecars end,function() return true end,loadfile)
assert(#registry_errors==0,table.concat(registry_errors,'\n'))
assert(#registry.identities==17)
assert(registry.identities[17].id==profile.id)

assert(profile.version=='2.0.0')
assert(profile.policy_id=='pt-sortie-a-magic')
assert(profile.runtime_owns_pull==true)
assert(profile.gearswap_adapter.controller=='sortie-a-magic')
assert(profile.gearswap_adapter.version=='1.1.0')
assert(profile.preflight.required_before_combat==false)
assert(#profile.combat.attackers==6)
assert(#profile.combat.targeters==6)
assert(profile.combat.movement=='mobile')
assert(profile.auto_select==nil)
assert(plan.policy_command==
    'pc policy pt-sortie-a-magic Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo mobile - - -')

local function joined(name)
    return table.concat(plan.members[name].commands or {},'\n')
end
assert(joined('Dolomedes'):find(
    'r2 roll1 chaos; r2 roll2 samurai',1,true))
assert(joined('Smalls'):find(
    'gs c pstartrdm sortieacuex Tackleberry',1,true))
assert(joined('Achoo'):find(
    'gs c autoindi Fury; gs c autogeo Frailty;',1,true))
for name,member in pairs(plan.members) do
    local commands=table.concat(member.commands or {},'\n')
    assert(commands:find(
        'gs c ptgs activate sortie-objective-a-magic-kill-v1 1.1.0',
        1,true),name)
    assert(commands:find('aws2 off',1,true),name)
    assert(not commands:find('aws2 on',1,true),name)
end
local advice=table.concat(profile.advisories,'\n')
assert(advice:find('Explicit recovery profile only',1,true))
assert(advice:find('Flat Blade > Red Lotus Blade',1,true))
assert(advice:find('Aquaveil',1,true))

print('PASS - Sortie A fast magic-kill profile')
