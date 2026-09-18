local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local sandbox = module('lib/sandbox.lua')
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/escha-ruaun-kammavaca/runtime.lua', loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()

local clock = 10
local combat_ready = false
local claims_enabled = true
local claimed_ids = {}
local visible = {}
local mobs_by_id = {}
local abilities = {
    [701]={id=701, en='Chainspell'},
    [702]={id=702, en='Exponential Burst'},
}
local actor_ids = {
    Dolomedes=101, Tackleberry=102, Kickpuncher=103,
    Barneystinson=104, Smalls=105, Achoo=106,
}
for name, id in pairs(actor_ids) do mobs_by_id[id] = {id=id, name=name} end

local function enemy(id, name, x, y, z, claim_id)
    local mob = {
        id=id, index=id, name=name, spawn_type=16,
        valid_target=true, hpp=100, x=x, y=y, z=z,
        claim_id=claim_id,
    }
    mobs_by_id[id] = mob
    return mob
end

local clients = {}
local function make_client(name, register)
    local c = {
        name=name, calls={}, alerts={}, auto_target={}, buffs={},
        selected=nil, runtime=runtime_module.create(),
    }
    local function call(kind, action, target, argument)
        c.calls[#c.calls + 1] = {
            kind=kind, action=action, target=target,
            argument=argument, at=clock,
        }
        return true
    end
    c.context = {
        actions={
            cast=function(spell, target) return call('cast', spell, target) end,
            ability=function(ability, target)
                return call('ability', ability, target)
            end,
            controller=function(controller, action, argument)
                return call('controller', controller, action, argument)
            end,
            combat_force=function(id) return call('force', 'forceid', id) end,
            combat_observe=function(id)
                return call('observe', 'observeid', id)
            end,
        },
        client={
            auto_target=function(enabled)
                c.auto_target[#c.auto_target + 1] = enabled
                return true
            end,
        },
        now=function() return clock end,
        player_name=function() return name end,
        current_target=function() return c.selected end,
        combat_ready=function() return combat_ready end,
        party_claimed=function(mob)
            return claims_enabled and mob and claimed_ids[mob.id] == true
        end,
        has_buff=function(buff) return c.buffs[buff] == true end,
        monster_ability=function(id) return abilities[tonumber(id)] end,
        mob_by_id=function(id) return mobs_by_id[tonumber(id)] end,
        mob_array=function() return visible end,
        alert=function(message, audible)
            c.alerts[#c.alerts + 1] = {message=message, audible=audible}
        end,
    }
    c.runtime:on_activate(c.context)
    if register ~= false then clients[#clients + 1] = c end
    return c
end

local by_name = {}
for _, name in ipairs{
    'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo',
} do
    by_name[name] = make_client(name)
end

local function count(c, kind, action)
    local result = 0
    for _, call in ipairs(c.calls) do
        if call.kind == kind and (not action or call.action == action) then
            result = result + 1
        end
    end
    return result
end

local function latest(c, kind, action)
    for index = #c.calls, 1, -1 do
        local call = c.calls[index]
        if call.kind == kind and (not action or call.action == action) then
            return call
        end
    end
end

local function tick_all()
    for _, c in ipairs(clients) do c.runtime:on_tick(c.context, clock) end
end

local function advance(seconds)
    clock = clock + seconds
    tick_all()
end

local function broadcast(action)
    for _, c in ipairs(clients) do c.runtime:on_action(c.context, action) end
end

local function status_result(id, status, message)
    return {id=id, actions={{message=message or 236, param=status}}}
end

-- Activation owns only the reversible native auto-target preference. Barney
-- maintains Barsilencera before a claimed encounter with a bounded throttle.
for _, c in ipairs(clients) do
    assert(#c.auto_target == 1 and c.auto_target[1] == false)
end
tick_all()
local barney = by_name.Barneystinson
local smalls = by_name.Smalls
local dolo = by_name.Dolomedes
assert(count(barney, 'cast', 'Barsilencera') == 1)
advance(1)
assert(count(barney, 'cast', 'Barsilencera') == 1)
barney.buffs.Barsilence = true
advance(8)
assert(count(barney, 'cast', 'Barsilencera') == 1)

-- Non-damaging support may queue as soon as the party claim appears, but
-- automatic force remains blocked until the shared readiness barrier passes.
local boss = enemy(500, 'Kammavaca', 0, 0, 0, actor_ids.Dolomedes)
claimed_ids[boss.id] = true
visible = {boss}
advance(0.3)
assert(count(smalls, 'controller', 'rdm') == 1)
local silence_request = latest(smalls, 'controller', 'rdm')
assert(silence_request.target == 'silence')
assert(silence_request.argument == boss.id)
assert(count(smalls, 'cast', 'Silence') == 0)
assert(count(smalls, 'ability', 'Stymie') == 0)
assert(count(smalls, 'ability', 'Saboteur') == 0)
assert(count(dolo, 'force') == 0)

combat_ready = true
advance(0.3)
assert(count(dolo, 'force') == 0, 'boss settle window was skipped')
advance(0.5)
assert(count(dolo, 'force') == 1,
    'unconfirmed Silence incorrectly blocked boss engagement')
assert(latest(dolo, 'force').target == boss.id)
dolo.selected = boss
advance(0.8)
assert(count(dolo, 'force') == 1, 'matching boss target was force-spammed')

-- Exact adds are associated only with the active party encounter. A white
-- add inside 20 yalms is legal. Foreign-claimed near/far copies and a white
-- copy outside 20 yalms are rejected even when their names match exactly.
local foreign_near = enemy(550, "Kammavaca's Clionid", 1, 0, 0, 9999)
local foreign_far = enemy(551, "Kammavaca's Clionid", 80, 0, 0, 9998)
local white_far = enemy(552, "Kammavaca's Limule", 40, 0, 0, 0)
local white_missing = enemy(553, "Kammavaca's Clionid", nil, nil, nil, 0)
local malformed_claim = enemy(554, "Kammavaca's Clionid", 1, 0, 0,
    'foreign')
local clionid = enemy(601, "Kammavaca's Clionid", 3, 0, 0, 0)
local limule = enemy(602, "Kammavaca's Limule", 45, 0, 0,
    actor_ids.Tackleberry)
local murex = enemy(603, "Kammavaca's Murex", 4, 1, 0, nil)
local amoeban = enemy(604, "Kammavaca's Amoeban", 5, 1, 0, 0)
claimed_ids[limule.id] = true
visible = {
    boss, foreign_near, foreign_far, white_far,
    white_missing, malformed_claim,
    clionid, limule, murex, amoeban,
}

-- A newly visible legal add must supersede an established Kammavaca lock on
-- the very next profile poll. Neither Silence nor Lullaby is a damage gate.
local force_before_add = count(dolo, 'force')
advance(0.3)
assert(count(dolo, 'force') == force_before_add + 1)
assert(latest(dolo, 'force').target == clionid.id)
assert(count(barney, 'observe') == 1)
assert(latest(barney, 'observe').target == clionid.id)
assert(count(barney, 'controller', 'brd') == 0)

-- Observer selection is asynchronous. Once Barney's exact current target is
-- visible, GearSwap queues its normal <t> sleep; no numeric Bard cast occurs.
barney.selected = clionid
advance(0.3)
assert(count(barney, 'controller', 'brd') == 1)
assert(latest(barney, 'controller', 'brd').target == 'sleep')
assert(count(barney, 'cast', 'Horde Lullaby II') == 0)

-- A stale boss selection/action cannot permanently undo the add force. The
-- profile reasserts under a bounded rolling throttle until Dolo shows the
-- desired live add, then becomes quiet.
dolo.selected = boss
advance(0.5)
assert(count(dolo, 'force') == force_before_add + 2)
advance(0.8)
assert(count(dolo, 'force') == force_before_add + 3)
local burst_end = count(dolo, 'force')
advance(1)
assert(count(dolo, 'force') == burst_end,
    'force reassertion ignored its bounded cooldown')
advance(1.1)
assert(count(dolo, 'force') == burst_end + 1,
    'stale boss target permanently defeated exact add priority')
dolo.selected = clionid
local matched_count = count(dolo, 'force')
advance(0.8)
assert(count(dolo, 'force') == matched_count)

-- A no-effect sleep result does not create proof, but combat already follows
-- CLMA. Positive coverage remains support telemetry rather than authorization.
broadcast({
    category=4, param=377, actor_id=actor_ids.Barneystinson,
    targets={
        status_result(clionid.id, 2), status_result(limule.id, 2),
        status_result(murex.id, 2), status_result(amoeban.id, 0, 75),
    },
})
advance(0.3)
assert(latest(dolo, 'force').target == clionid.id)

-- Each death forces only the first living associated CLMA entry. The
-- party-claimed Limule remains associated even beyond the coordinate bound;
-- the foreign and far-white lookalikes are never chosen.
clionid.hpp = 0
dolo.selected = clionid
advance(0.3)
assert(latest(dolo, 'force').target == limule.id)
limule.valid_target = false
advance(0.3)
assert(latest(dolo, 'force').target == murex.id)
murex.spawn_type = 14
advance(0.3)
assert(latest(dolo, 'force').target == amoeban.id)
amoeban.hpp = 0
advance(0.3)
assert(latest(dolo, 'force').target == boss.id)

-- A newly spawned legal add also supersedes the boss after the add phase.
dolo.selected = boss
local replacement = enemy(605, "Kammavaca's Clionid", 2, 0, 0, 0)
visible[#visible + 1] = replacement
local before_replacement = count(dolo, 'force')
advance(0.3)
assert(count(dolo, 'force') == before_replacement + 1)
assert(latest(dolo, 'force').target == replacement.id)

-- Observer selection and the queued sleep use bounded rolling bursts, not a
-- permanent exhaustion counter. A transient target miss eventually retries.
local observe_after_first = count(barney, 'observe')
barney.selected = boss
for _ = 1, 5 do advance(0.8) end
assert(count(barney, 'observe') == observe_after_first + 5)
local observe_burst_end = count(barney, 'observe')
advance(1)
assert(count(barney, 'observe') == observe_burst_end)
advance(1.1)
assert(count(barney, 'observe') == observe_burst_end + 1)

barney.selected = replacement
local sleep_before_retry_cycle = count(barney, 'controller', 'brd')
advance(0.3)
assert(count(barney, 'controller', 'brd') == sleep_before_retry_cycle + 1)
for _ = 1, 3 do
    broadcast({
        category=4, param=377, actor_id=actor_ids.Barneystinson,
        targets={status_result(replacement.id, 0, 655)},
    })
    advance(6.1)
end
assert(count(barney, 'controller', 'brd') >= sleep_before_retry_cycle + 4,
    'queued sleep became permanently exhausted after bounded failures')

-- Dropping readiness blocks all reassertion and clears the runtime's local
-- acknowledgement. A fresh pass reissues once even if Dolo already has <t>.
dolo.selected = replacement
combat_ready = false
local before_not_ready = count(dolo, 'force')
advance(0.8)
assert(count(dolo, 'force') == before_not_ready)
combat_ready = true
advance(0.3)
assert(count(dolo, 'force') == before_not_ready + 1)
assert(latest(dolo, 'force').target == replacement.id)

-- Losing party claim clears encounter state. Reacquiring the same entities
-- starts fresh and may immediately force the living associated add.
local before_claim_loss = count(dolo, 'force')
claims_enabled = false
advance(0.3)
claims_enabled = true
advance(0.3)
assert(count(dolo, 'force') == before_claim_loss + 1)
assert(latest(dolo, 'force').target == replacement.id)

-- Silence success affects only future controller cycles, never target
-- selection. A boss cast start opens one new semantic queue request.
broadcast({
    category=4, param=59, actor_id=actor_ids.Smalls,
    targets={status_result(boss.id, 6)},
})
local rdm_before_cast = count(smalls, 'controller', 'rdm')
broadcast({category=8, param=24931, actor_id=boss.id, targets={}})
advance(0.3)
assert(count(smalls, 'controller', 'rdm') == rdm_before_cast + 1)
assert(latest(smalls, 'controller', 'rdm').argument == boss.id)

-- Existing exact-actor alerts remain throttled and describe continuing combat.
local alerts_before = #dolo.alerts
broadcast({
    category=7, actor_id=boss.id,
    targets={{actions={{param=701}}}},
})
assert(#dolo.alerts == alerts_before + 1)
assert(dolo.alerts[#dolo.alerts].message:find('CHAINSPELL', 1, true))
broadcast({category=6, actor_id=boss.id, param=701})
assert(#dolo.alerts == alerts_before + 1)

-- An unclaimed zone copy never starts encounter automation or force.
boss.hpp, replacement.hpp = 0, 0
visible = {}
advance(2.2)
local unclaimed_dolo = make_client('Dolomedes', false)
local boss2 = enemy(700, 'Kammavaca', 0, 0, 0, 9999)
visible = {boss2}
clock = clock + 1
unclaimed_dolo.runtime:on_tick(unclaimed_dolo.context, clock)
assert(count(unclaimed_dolo, 'force') == 0)

-- Deactivation restores native auto-target on every client.
for _, c in ipairs(clients) do
    c.runtime:on_deactivate(c.context)
    assert(c.auto_target[#c.auto_target] == true)
end
unclaimed_dolo.runtime:on_deactivate(unclaimed_dolo.context)
assert(unclaimed_dolo.auto_target[#unclaimed_dolo.auto_target] == true)

print('PartyTactics Kammavaca v1.2 runtime tests passed')
