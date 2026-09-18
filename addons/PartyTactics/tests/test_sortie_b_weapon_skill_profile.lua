local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path); assert(loader,reason); return loader()
end
local util=module('lib/util.lua')
local schema=module('lib/schema.lua')
local compiler=module('lib/compiler.lua')
local profile=module('profiles/sortie-objective-b-weapon-skill-v1/profile.lua')
local plan,errors=compiler.compile(util,schema,profile)
assert(plan,table.concat(errors or {},' '))
local identity=module(
    'data/profile_identities/sortie-objective-b-weapon-skill-v1.lua')
assert(identity.ordinal==18 and identity.id==profile.id)
assert(identity.policy_id==profile.policy_id)
assert(profile.version=='1.0.0' and profile.runtime_owns_pull==true)
assert(profile.combat.movement=='mobile')
assert(#profile.combat.attackers==6 and #profile.combat.targeters==6)
assert(profile.auto_select==nil)
assert(profile.gearswap_adapter.version=='1.0.0'
    and profile.gearswap_adapter.controller=='sortie-b-ws')
assert(profile.preflight.required_before_combat==false)
assert(plan.policy_command==
    'pc policy pt-sortie-b-ws Dolomedes Tackleberry Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo mobile - - -')
for name,member in pairs(plan.members) do
    local commands=table.concat(member.commands or {},'\n')
    assert(commands:find(
        'gs c ptgs activate sortie-objective-b-weapon-skill-v1 1.0.0',
        1,true),name)
    assert(commands:find('aws2 off',1,true),name)
    assert(not commands:find('aws2 on',1,true),name)
end
local advice=table.concat(profile.advisories,'\n')
assert(advice:find('Explicit recovery profile only',1,true))
assert(advice:find('first five',1,true))
assert(advice:find('full burn',1,true))
print('PASS - Sortie B automatic weapon-skill-credit profile')
