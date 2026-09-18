-- Runtime regression tests for Ambuscade reactions and manual Limbus sleep.

local fake_now = 100
os.clock = function() return fake_now end

local commands = {}
local chat_messages = {}
local spell_recasts = {}
local callbacks = {}
local injected = {}
local selected_target = nil
local battle_target = nil
local mob_array = {}
local mobs_by_id = {}
local busy = false

local packet_mock = {}
packet_mock.new = function(direction, id, fields)
    fields._direction = direction
    fields._id = id
    return fields
end
packet_mock.inject = function(packet)
    injected[#injected + 1] = packet
    selected_target = mobs_by_id[packet.Target]
end
package.preload.packets = function() return packet_mock end

local spell_names = {
    'Barfira', 'Barblizzara', 'Baraera', 'Barstonra', 'Barthundra',
    'Barwatera', 'Horde Lullaby II', 'Horde Lullaby', 'Reraise',
    'Barsilencera', 'Carnage Elegy', 'Battlefield Elegy',
}
local spells_by_name = {}
local learned = {}
for id, name in ipairs(spell_names) do
    spells_by_name[name] = {id=id, en=name, mp_cost=10}
    learned[id] = true
end

local warbles = {
    {id=3968, ability='Fire Meeble Warble', spell='Barfira', buff='Barfire'},
    {id=3969, ability='Blizzard Meeble Warble', spell='Barblizzara', buff='Barblizzard'},
    {id=3973, ability='Aero Meeble Warble', spell='Baraera', buff='Baraero'},
    {id=3971, ability='Stone Meeble Warble', spell='Barstonra', buff='Barstone'},
    {id=3970, ability='Thunder Meeble Warble', spell='Barthundra', buff='Barthunder'},
    {id=3972, ability='Water Meeble Warble', spell='Barwatera', buff='Barwater'},
}

local startup_abilities = {
    Nightingale={id=201, en='Nightingale', recast_id=109},
    Troubadour={id=202, en='Troubadour', recast_id=110},
}

res = {
    spells = {
        with = function(_, key, value)
            return key == 'en' and spells_by_name[value] or nil
        end,
    },
    items = {with = function() return nil end},
    job_abilities = {
        with = function(_, key, value)
            return key == 'en' and startup_abilities[value] or nil
        end,
    },
    monster_abilities = {},
}
for _, warble in ipairs(warbles) do
    res.monster_abilities[warble.id] = {
        id=warble.id,
        en=warble.ability,
    }
end

local breadwinner = {
    id=500, index=50, name='Bozzetto Breadwinner', spawn_type=16,
    valid_target=true, hpp=100, distance=4, status=0,
}
local housemaker = {
    id=600, index=60, name='Bozzetto Housemaker', spawn_type=16,
    valid_target=true, hpp=100, distance=400,
}
local urchin_one = {
    id=701, index=71, name='Bozzetto Urchin', spawn_type=16,
    valid_target=true, hpp=100, distance=4,
}
local urchin_two = {
    id=702, index=72, name='Bozzetto Urchin', spawn_type=16,
    valid_target=true, hpp=100, distance=9,
}
for _, mob in ipairs({breadwinner, housemaker, urchin_one, urchin_two}) do
    mobs_by_id[mob.id] = mob
end

windower = {
    chat = {
        input = function(command) commands[#commands + 1] = command end,
    },
    ffxi = {
        get_spells = function() return learned end,
        get_spell_recasts = function() return spell_recasts end,
        get_ability_recasts = function() return {[109]=0, [110]=0} end,
        get_player = function()
            return {id=900, index=90, job_points={brd={jp_spent=0}}}
        end,
        get_items = function() return {enabled=false} end,
        get_mob_array = function() return mob_array end,
        get_mob_by_id = function(id) return mobs_by_id[id] end,
        get_mob_by_name = function() return nil end,
        get_mob_by_index = function() return nil end,
        get_mob_by_target = function(token)
            if token == 'bt' then return battle_target end
            if token == 't' then return selected_target end
            return nil
        end,
    },
    raw_register_event = function(name, callback)
        callbacks[name] = callback
    end,
}

local function mode(value)
    return {
        value=value,
        set=function(self, next_value) self.value = next_value end,
    }
end

state = {
    AutoSongMode=mode(false),
    SongMode=mode('None'),
    DisplayMode=mode(false),
}
info = {ExtraSongs=0}
player = {mp=999, hpp=100}
buffactive = {Reraise=true, Barsilence=true, Barstone=true}
moving = false
spell_latency = 0.5
tickdelay = 0
midaction = function() return busy end
silent_check_disable = function() return false end
silent_can_use = function() return true end
add_to_chat = function(_, message)
    chat_messages[#chat_messages + 1] = message
end
update_job_states = function() end
local native_check_song_calls = 0
local native_song_result = false
check_song = function()
    native_check_song_calls = native_check_song_calls + 1
    return native_song_result
end
local native_pre_tick_calls = 0
pre_tick = function()
    native_pre_tick_calls = native_pre_tick_calls + 1
    return false
end
local native_filter_calls = {pretarget=0, precast=0}
user_filter_pretarget = function()
    native_filter_calls.pretarget = native_filter_calls.pretarget + 1
end
user_filter_precast = function()
    native_filter_calls.precast = native_filter_calls.precast + 1
end

assert(loadfile('addons/PartyStart/gearswap/PartyStart_BRD.lua'))()
assert(callbacks.action, 'BRD action handler was not registered')

local event_args = {handled=false}
user_job_self_command(
    {'pstartbrd', 'ambuscade-v1', 'Dolomedes'}, event_args)
assert(event_args.handled, 'activation command was not handled')

-- PartyStart's independent heartbeat must never invoke Barney's native song
-- owner. The normal GearSwap job tick owns songs; a second call path can queue
-- the same missing song twice before midaction() changes.
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(native_check_song_calls == 0,
    'PartyStart BRD tick created a second native song scheduler')

-- The wrapped native path applies Nightingale/Troubadour before delegating the
-- unchanged three-song scheduler. This is the documented V1 opening sequence;
-- no instrument or song-selection code lives in the bridge.
check_song()
assert(commands[#commands] == '/ja "Nightingale" <me>',
    'V1 opening did not start with Nightingale')
job_aftercast({id=startup_abilities.Nightingale.id, interrupted=false}, nil, {})
fake_now = fake_now + 1
check_song()
assert(commands[#commands] == '/ja "Troubadour" <me>',
    'V1 opening did not apply Troubadour')
job_aftercast({id=startup_abilities.Troubadour.id, interrupted=false}, nil, {})
fake_now = fake_now + 1
check_song()
assert(native_check_song_calls == 1,
    'normal GearSwap song path did not reach the native song routine')

-- The safe activation script asks for an explicit status token. It must be a
-- supported alias rather than falling through to the usage error.
local status_args = {handled=false}
user_job_self_command({'pstartbrd', 'status'}, status_args)
assert(status_args.handled, 'explicit BRD status command was not handled')

-- A ready packet received during another action must queue, then take the next
-- GearSwap heartbeat before routine songs or maintenance.
busy = true
local command_count_before_ready = #commands
callbacks.action({
    category=7,
    actor_id=breadwinner.id,
    targets={{actions={{param=warbles[1].id}}}},
})
assert(#commands == command_count_before_ready,
    'busy ready packet cast instead of queueing')
busy = false
check_song()
assert(commands[#commands] == '/ma "Barfira" <me>',
    'queued Fire Warble did not cast Barfira')
job_aftercast({id=spells_by_name.Barfira.id, interrupted=false}, nil, {})

-- PartyStart's standard action-event relay is a second trigger path. It must
-- work independently and deduplicate the GearSwap-local packet fallback.
fake_now = fake_now + 2
user_job_self_command({'pstartbrd', 'warble', tostring(warbles[2].id)},
    {handled=false})
assert(commands[#commands] == '/ma "Barblizzara" <me>',
    'standard PartyStart relay did not cast the mapped Barspell')
local relay_command_count = #commands
callbacks.action({
    category=7,
    actor_id=breadwinner.id,
    targets={{actions={{param=warbles[2].id}}}},
})
assert(#commands == relay_command_count,
    'duplicate relay and raw callback issued the Barspell twice')
job_aftercast({id=spells_by_name.Barblizzara.id, interrupted=false}, nil, {})

-- Exercise every remaining ready-packet mapping through the immediate path.
for index=3,#warbles do
    fake_now = fake_now + 1
    local warble = warbles[index]
    buffactive[warble.buff] = nil
    callbacks.action({
        category=7,
        actor_id=breadwinner.id,
        targets={{actions={{param=warble.id}}}},
    })
    assert(commands[#commands] == '/ma "'..warble.spell..'" <me>',
        warble.ability..' selected the wrong Barspell')
    job_aftercast({
        id=spells_by_name[warble.spell].id,
        interrupted=false,
    }, nil, {})
end

-- Completion scans after the mob table updates. With no <bt> and Housemaker
-- selected, Barney must observer-target the nearest Urchin, cast one Horde
-- Lullaby, and restore Housemaker afterward.
selected_target = housemaker
battle_target = nil
mob_array = {}
urchin_one.distance = 100
urchin_two.distance = 121
fake_now = fake_now + 1
user_job_self_command({
    'pstartbrd', 'warblecomplete', tostring(warbles[#warbles].id),
}, {handled=false})
-- Category 6/11 and the standard addon relay can describe the same completion.
-- The immediate duplicate must not create another sleep generation.
callbacks.action({
    category=6,
    actor_id=breadwinner.id,
    param=warbles[#warbles].id,
})
fake_now = fake_now + 0.2
check_song()
assert(commands[#commands] ~= '/ma "Horde Lullaby II" <t>',
    'Horde Lullaby cast before an Urchin became targetable')
fake_now = fake_now + 2.1
check_song()
mob_array = {urchin_two, urchin_one}
fake_now = fake_now + 0.1
check_song()
assert(commands[#commands] ~= '/ma "Horde Lullaby II" <t>',
    'Horde Lullaby was spent while Barney was outside its maximum radius')
assert(#injected == 0, 'out-of-radius Urchin changed Barney target')
if commands[#commands] == '/ma "Barstonra" <me>' then
    job_aftercast({
        id=spells_by_name.Barstonra.id,
        interrupted=false,
    }, nil, {})
    buffactive.Barstone = true
end
urchin_one.distance = 4
urchin_two.distance = 9
fake_now = fake_now + 0.5
check_song()
assert(commands[#commands] == '/ma "Horde Lullaby II" <t>',
    'visible Urchins did not trigger Horde Lullaby II')
assert(injected[#injected].Target == urchin_one.id,
    'nearest visible Urchin was not observer-targeted')
job_aftercast({
    id=spells_by_name['Horde Lullaby II'].id,
    interrupted=false,
}, nil, {})
assert(selected_target == housemaker, 'prior observer target was not restored')
-- Combat permits exactly one native-song repair in the short window following
-- a completed Warble. This keeps long fights buffed without arbitrary casts.
local song_calls_in_combat = native_check_song_calls
native_song_result = true
check_song()
assert(native_check_song_calls == song_calls_in_combat + 1,
    'V1 post-Warble song repair window did not reach the native scheduler')
native_song_result = false
check_song()
assert(native_check_song_calls == song_calls_in_combat + 1,
    'V1 post-Warble song repair window allowed more than one song')

local function command_count(needle)
    local count = 0
    for _, command in ipairs(commands) do
        if command == needle then count = count + 1 end
    end
    return count
end

-- The relay/raw completion pair above cannot double-sleep the same Warble.
assert(command_count('/ma "Horde Lullaby II" <t>') == 1,
    'duplicate completion packet caused a second Lullaby')

-- The next real Warble wakes the pack and must arm exactly one fresh sleep.
fake_now = fake_now + 30
callbacks.action({
    category=11,
    actor_id=breadwinner.id,
    param=warbles[#warbles].id,
})
fake_now = fake_now + 0.2
check_song()
assert(command_count('/ma "Horde Lullaby II" <t>') == 2,
    'later Warble did not rearm Urchin Lullaby')

print('PartyStart BRD reaction packet paths OK')

-- Manual Limbus sleep is local to Barney. No readable Tackleberry target is
-- required, and even a long routine buff delay cannot postpone the request.
user_job_self_command({'pstartbrd', 'limbus', 'Tackleberry'}, {handled=false})
fake_now = fake_now + 30
local limbus_enemy = {
    id=801, index=81, name="Demon's Elemental", spawn_type=16,
    valid_target=true, hpp=100, distance=4,
}
selected_target = limbus_enemy
battle_target = nil
tickdelay = fake_now + 60
local native_calls_before_limbus = native_check_song_calls
local injected_before_limbus = #injected
local sleeps_before_request = command_count('/ma "Horde Lullaby II" <t>')
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>') == sleeps_before_request + 1,
    'manual Limbus sleep waited for a remote target or the routine tick delay')
assert(native_check_song_calls == native_calls_before_limbus,
    'manual sleep called the party-song scheduler')

-- The heartbeat can run before midaction() changes. The in-flight request must
-- not issue a duplicate spell during that gap or after cast completion.
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>') == sleeps_before_request + 1,
    'manual sleep was dispatched twice before midaction updated')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})
fake_now = fake_now + 10
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>') == sleeps_before_request + 1,
    'completed manual sleep became automatic upkeep')

-- A real action may finish first, but the next opportunity belongs to the
-- manual request instead of starting another routine party song.
busy = true
tickdelay = fake_now + 60
local before_busy_request = #commands
native_song_result = true
local pre_ticks_before_request = native_pre_tick_calls
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(#commands == before_busy_request, 'busy manual request interrupted an action')
assert(chat_messages[#chat_messages]:find('another action is in progress', 1, true),
    'busy request did not report its actual blocker')
check_song()
assert(native_check_song_calls == native_calls_before_limbus,
    'routine song took the pending manual sleep slot')
assert(pre_tick() == true and native_pre_tick_calls == pre_ticks_before_request,
    'native pre_tick took the reserved CC slot')

-- Scheduled casts and AutoWS2 do not pass through the song/tick scheduler.
-- Both action filters must protect the reservation before any gear handling.
local filters_before_request = native_filter_calls.pretarget + native_filter_calls.precast
for _, other_action in ipairs({
    {id=30, english='Cure IV', action_type='Magic'},
    {id=31, english='Haste', action_type='Magic'},
    {id=32, english='Victory March', action_type='Magic'},
    {id=33, english='Carnage Elegy', action_type='Magic'},
    {id=34, english='Savage Blade', action_type='Ability', type='WeaponSkill'},
    {id=spells_by_name['Horde Lullaby II'].id, action_type='Ability'},
}) do
    for _, filter in ipairs({user_filter_pretarget, user_filter_precast}) do
        local args = {cancel=false}
        filter(other_action, nil, args)
        assert(args.cancel, 'non-CC action bypassed the reservation')
    end
end
assert(native_filter_calls.pretarget + native_filter_calls.precast == filters_before_request,
    'non-CC action reached native filters or delayed-cast handling')

-- A cast longer than the old eight-second queue cannot discard the request.
-- Hammering the hotkey still represents only one reserved action.
state.AutoSongMode:set(false)
for _ = 1, 12 do
    fake_now = fake_now + 1
    callbacks.prerender()
    user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
end
assert(#commands == before_busy_request, 'busy request interrupted or duplicated an action')
busy = false
job_aftercast({id=32, action_type='Magic', interrupted=false}, nil, {})
next_cast = fake_now + 2.6 -- Sel-Include sets the real recovery in default_aftercast.
tickdelay = fake_now + 60
callbacks.prerender()
assert(#commands == before_busy_request, 'sleep was sent into MiniQueue during recovery')
fake_now = next_cast - 0.01
callbacks.prerender()
assert(#commands == before_busy_request, 'sleep ignored the current action recovery')
fake_now = next_cast + 0.11
callbacks.prerender()
assert(commands[#commands] == '/ma "Horde Lullaby II" <t>',
    'manual request waited for a heartbeat or buff tick after recovery finished')
local expected_sleep = {
    id=spells_by_name['Horde Lullaby II'].id, english='Horde Lullaby II',
    action_type='Magic', type='BardSong',
}
for _, filter in ipairs({user_filter_pretarget, user_filter_precast}) do
    local args = {cancel=false}
    filter(expected_sleep, nil, args)
    assert(not args.cancel, 'CC reservation blocked its own Lullaby')
end
assert(native_filter_calls.pretarget + native_filter_calls.precast == filters_before_request + 2,
    'reserved Lullaby bypassed the native spell/instrument path')
busy = true
for _ = 1, 12 do
    fake_now = fake_now + 1
    user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
    callbacks.prerender()
    assert(pre_tick() == true, 'CC slot released before Lullaby completed')
end
assert(#commands == before_busy_request + 1, 'repeated presses queued multiple Lullabies')
busy = false
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})
assert(pre_tick() == false and native_pre_tick_calls == pre_ticks_before_request + 1,
    'native automation did not resume after completed Lullaby')
state.AutoSongMode:set(true)
next_cast = 0
native_song_result = false

-- A friendly/menu selection can fall back to Barney's existing battle target.
-- The request must never inject a new target or require party synchronization.
selected_target = {id=900, spawn_type=1, valid_target=true, hpp=100}
battle_target = limbus_enemy
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(commands[#commands] == '/ma "Horde Lullaby II" <bt>',
    'manual request did not use the existing battle target')
assert(#injected == injected_before_limbus, 'Limbus sleep changed a client target')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})

-- When Barney really has no enemy, report that instead of blaming recast.
selected_target = nil
battle_target = nil
local before_missing_target = #commands
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(#commands == before_missing_target, 'no-target request cast at a missing target')
assert(chat_messages[#chat_messages]:find('no live enemy selected or engaged', 1, true),
    'no-target request did not identify the missing local enemy')
selected_target = limbus_enemy
fake_now = fake_now + 1
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(#commands == before_missing_target + 1, 'new local target did not release the queue')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})

-- Actual recast and movement still block; expiry states the last real blocker.
spell_recasts[spells_by_name['Horde Lullaby II'].id] = 600
local before_recast = #commands
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(#commands == before_recast, 'manual request ignored a real recast')
assert(chat_messages[#chat_messages]:find('Horde Lullaby II is on recast', 1, true),
    'recast request did not report the spell on cooldown')
spell_recasts = {}
fake_now = fake_now + 1
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(#commands == before_recast + 1, 'cleared recast did not release manual sleep')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})
moving = true
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
local before_expiry = #commands
fake_now = fake_now + 9
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(#commands == before_expiry, 'expired request unexpectedly cast')
assert(chat_messages[#chat_messages]:find('request expired: Barney is moving', 1, true),
    'expired request lost its specific movement blocker')
moving = false

-- Interruption permits a brief retry, and that retry is also consumed once.
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=true}, nil, {})
local before_retry = command_count('/ma "Horde Lullaby II" <t>')
fake_now = fake_now + 1
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
user_job_self_command({'pstartbrd', 'tick'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>') == before_retry + 1,
    'interruption retry failed or issued duplicate casts')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id, interrupted=false}, nil, {})
assert(#injected == injected_before_limbus, 'manual Limbus sleep injected a target')

-- Missing-target/recast/movement requests stay bounded; repeated presses do
-- not keep the whole BRD reserved forever. A new press after expiry is new work.
selected_target = nil
local before_coalesced_expiry = #commands
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
fake_now = fake_now + 7
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
fake_now = fake_now + 1.1
callbacks.prerender()
assert(chat_messages[#chat_messages]:find('request expired:', 1, true),
    'repeated presses restarted the no-target timeout')
selected_target = limbus_enemy
fake_now = fake_now + 1
callbacks.prerender()
assert(#commands == before_coalesced_expiry, 'expired request became later automatic sleep')

-- GearSwap can reject a dispatched command before midaction/aftercast. Retry
-- at a bounded rate, then release the reservation rather than deadlocking BRD.
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
local before_unstarted_retry = #commands
fake_now = fake_now + 1
callbacks.prerender()
assert(#commands == before_unstarted_retry, 'unstarted dispatch retried too quickly')
fake_now = fake_now + 1.1
callbacks.prerender()
assert(#commands == before_unstarted_retry + 1, 'unstarted dispatch never retried')
fake_now = fake_now + 7
callbacks.prerender()
assert(pre_tick() == false, 'unstarted dispatch held the CC reservation forever')

-- Silence recovery is still possible; arbitrary item/ability spam is not.
busy = true
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
buffactive.silence = true
local remedy_args = {cancel=false}
user_filter_precast({english='Echo Drops', action_type='Item'}, nil, remedy_args)
assert(not remedy_args.cancel, 'CC reservation blocked silence recovery')
buffactive.silence = nil
busy = false
callbacks['zone change']()
local normal_args = {cancel=false}
user_filter_precast({id=30, english='Cure IV', action_type='Magic'}, nil, normal_args)
assert(not normal_args.cancel, 'zone change left a stale CC action filter')

-- Alt-L is a universal current-target safety action. A non-Limbus profile
-- must use the exact same native GearSwap path and must not select a target
-- or handle instruments itself.
user_job_self_command({'pstartbrd', 'physical', 'Tackleberry'}, {handled=false})
selected_target = limbus_enemy
battle_target = nil
next_cast = 0
tickdelay = fake_now + 60
local before_physical_sleep = command_count('/ma "Horde Lullaby II" <t>')
local injected_before_physical_sleep = #injected
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>')
        == before_physical_sleep + 1,
    'non-Limbus profile did not use universal current-target Horde Lullaby')
assert(#injected == injected_before_physical_sleep,
    'universal pack sleep changed the current target')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id,
    interrupted=false}, nil, {})

-- A PartyTactics route may intentionally disable routine BRD support. Alt-L
-- is still a one-shot operator safety action and must not turn upkeep back on.
user_job_self_command({'pstartbrd', 'off'}, {handled=false})
assert(state.AutoSongMode.value == false)
local before_disabled_sleep = command_count('/ma "Horde Lullaby II" <t>')
user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
assert(command_count('/ma "Horde Lullaby II" <t>')
        == before_disabled_sleep + 1,
    'disabled routine support blocked universal current-target Horde Lullaby')
assert(state.AutoSongMode.value == false,
    'one-shot universal sleep re-enabled routine BRD upkeep')
job_aftercast({id=spells_by_name['Horde Lullaby II'].id,
    interrupted=false}, nil, {})

for _, stop in ipairs({'off', 'ambuscade-v1'}) do
    user_job_self_command({'pstartbrd', 'limbus', 'Tackleberry'}, {handled=false})
    busy = true
    user_job_self_command({'pstartbrd', 'sleep'}, {handled=false})
    user_job_self_command({'pstartbrd', stop, 'Dolomedes'}, {handled=false})
    busy = false
    local args = {cancel=false}
    user_filter_pretarget({id=30, english='Cure IV', action_type='Magic'}, nil, args)
    assert(not args.cancel, 'CC reservation leaked through stop/profile change')
    assert(pre_tick() == false, 'native automation stayed blocked outside Limbus sleep')
end

print('PartyStart BRD universal current-target sleep paths OK')
