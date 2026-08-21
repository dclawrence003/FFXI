-- Packet-path smoke test for the Ambuscade V1 BRD reactions.

local fake_now = 100
os.clock = function() return fake_now end

local commands = {}
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
        get_spell_recasts = function() return {} end,
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
add_to_chat = function() end
update_job_states = function() end
local native_check_song_calls = 0
local native_song_result = false
check_song = function()
    native_check_song_calls = native_check_song_calls + 1
    return native_song_result
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
