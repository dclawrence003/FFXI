local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local action_api = module('lib/action_api.lua')
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/ambuscade-2026-08-v1-breadwinner/runtime.lua', loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()
local runtime = runtime_module.create()

local clock = 10
local job = 'BRD'
local issued, alerts = {}, {}
local abilities = {
    [501]={id=501, en='Fire Meeble Warble'},
    [502]={id=502, en='Drill Claw'},
    [503]={id=503, en='Hundred Fists'},
    [504]={id=504, en='Earthshaker'},
}
local mobs = {
    [100]={id=100, name='Bozzetto Breadwinner'},
    [200]={id=200, name='Bozzetto Housemaker', x=0, y=0},
}
local context = {
    actions=action_api.create(function(command) issued[#issued + 1] = command end),
    now=function() return clock end,
    player_job=function() return job end,
    monster_ability=function(id) return abilities[tonumber(id)] end,
    mob_by_id=function(id) return mobs[id] end,
    mob_array=function() return mobs end,
    alert=function(message, audible)
        alerts[#alerts + 1] = {message=message, audible=audible}
    end,
}

runtime:on_action(context, {
    category=7, actor_id=100,
    targets={{actions={{param=501}}}},
})
assert(issued[#issued] == 'gs c pstartbrd warble 501')
assert(alerts[#alerts].message:find('FIRE WARBLE', 1, true))

clock = 11
runtime:on_action(context, {category=6, actor_id=100, param=501})
assert(issued[#issued] == 'gs c pstartbrd warblecomplete 501')
-- Ready/complete packets share the alert dedupe key.
assert(#alerts == 1)

clock = 20
runtime:on_action(context, {category=6, actor_id=100, param=502})
assert(alerts[#alerts].message:find('DRILL CLAW', 1, true))
clock = 27
runtime:on_action(context, {category=6, actor_id=100, param=503})
assert(alerts[#alerts].message:find('HUNDRED FISTS', 1, true))

-- Only the BRD client relays Warble controller actions.
job = 'RDM'
local before_non_brd = #issued
clock = 34
runtime:on_action(context, {category=6, actor_id=100, param=501})
assert(#issued == before_non_brd)
job = 'BRD'

-- Housemaker movement uses its first observed point as home and rearms after
-- returning. The core is responsible for sounding audible alerts only once.
clock = 40
runtime:on_tick(context, clock)
mobs[200].x = 0.8
clock = 41
runtime:on_tick(context, clock)
assert(alerts[#alerts].message:find('HOUSEMAKER MOVING', 1, true))
assert(alerts[#alerts].audible == true)
mobs[200].x = 0.2
clock = 42
runtime:on_tick(context, clock)
assert(alerts[#alerts].message:find('HOUSEMAKER RETURNED', 1, true))
assert(alerts[#alerts].audible == false)

clock = 50
runtime:on_action(context, {category=6, actor_id=200, param=504})
assert(alerts[#alerts].message:find('EARTHSHAKER', 1, true))

print('PartyTactics V1 runtime tests passed')
