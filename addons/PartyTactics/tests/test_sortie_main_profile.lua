local BASE='addons/PartyTactics/'
local function module(path)
    local loader,reason=loadfile(BASE..path); assert(loader,reason); return loader()
end
local util=module('lib/util.lua')
local schema=module('lib/schema.lua')
local compiler=module('lib/compiler.lua')
local profile=module('profiles/sortie-main-v1/profile.lua')
local plan,errors=compiler.compile(util,schema,profile)
assert(plan,table.concat(errors or {},' '))

local identity=module('data/profile_identities/sortie-main-v1.lua')
assert(identity.ordinal==21 and identity.id==profile.id)
assert(identity.policy_id==profile.policy_id)
assert(table.concat(identity.aliases,',')==table.concat(profile.aliases,','))
assert(profile.version=='1.2.0')
assert(profile.gearswap_adapter.id=='sortie-main-v1')
assert(profile.gearswap_adapter.version=='1.2.0')
assert(profile.gearswap_adapter.controller=='sortie-main')
assert(profile.combat.movement=='mobile')
assert(#profile.combat.attackers==6 and #profile.combat.targeters==6)
assert(profile.support.rdm.preset=='sortieacuex')
assert(profile.support.brd.preset=='magicboss')
assert(profile.support.pld.preset=='manualsc')
assert(profile.support.pld.native_buffs==false)
assert(profile.support.pld.native_tank==false)
local adapter_actions={}
for _,action in ipairs(profile.gearswap_adapter.actions) do
    adapter_actions[action]=true
end
assert(adapter_actions['leshonn-mode'])
assert(adapter_actions['leshonn-wind-mode'])
assert(adapter_actions['leshonn-thunder-mode'])
assert(profile.support.cor.rolls[1]=='bolter'
    and profile.support.cor.rolls[2]=='tactician')
assert(profile.auto_select.zones[133] and profile.auto_select.zones[189]
    and profile.auto_select.zones[275])

local target_set={}
for _,name in ipairs(profile.auto_select.targets) do target_set[name]=true end
for _,name in ipairs{'Cachaemic Skeleton','Cachaemic Ghoul','Skomora',
    'Biune Fire Elemental','Leshonn','Abject Acuex','Abject Obdella','Ghatjot'}
do assert(target_set[name],name) end

for name,member in pairs(plan.members) do
    local commands=table.concat(member.commands or {},'\n')
    assert(commands:find('pc policy pt-sortie-main',1,true),name)
    assert(commands:find(
        'gs c ptgs activate sortie-main-v1 1.2.0',1,true),name)
    assert(commands:find('aws2 off',1,true),name)
    assert(not commands:find('aws2 on',1,true),name)
end

local barney=table.concat(plan.members.Barneystinson.commands or {},'\n')
assert(barney:find('gs c pstartbrd magicboss Tackleberry',1,true))
local tackle=table.concat(plan.members.Tackleberry.commands or {},'\n')
assert(tackle:find('gs c pstartpld manualsc Dolomedes',1,true))
assert(tackle:find('gs c unset AutoTankMode',1,true))

for _,id in ipairs{
    'sortie-objective-c-magic-burst-v1','sortie-objective-b-weapon-skill-v1',
    'sortie-objective-a-magic-kill-v1','sortie-boss-skomora-v1',
    'sortie-boss-leshonn-v1','sortie-boss-ghatjot-v1',
} do
    assert(module('profiles/'..id..'/profile.lua').auto_select==nil,id)
end

print('PASS - persistent Sortie main profile and ownership boundaries')
