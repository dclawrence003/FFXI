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
    {id=101, ability='Fire Meeble Warble', spell='Barfira', buff='Barfire'},
    {id=102, ability='Blizzard Meeble Warble', spell='Barblizzara', buff='Barblizzard'},
    {id=103, ability='Aero Meeble Warble', spell='Baraera', buff='Baraero'},
    {id=104, ability='Stone Meeble Warble', spell='Barstonra', buff='Barstone'},
    {id=105, ability='Thunder Meeble Warble', spell='Barthundra', buff='Barthunder'},
    {id=106, ability='Water Meeble Warble', spell='Barwatera', buff='Barwater'},
}

res = {
    spells = {
        with = function(_, key, value)
            return key == 'en' and spells_by_name[value] or nil
        end,
    },
    items = {with = function() return nil end},
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
    valid_target=true, hpp=100, distance=4,
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
buffactive = {Reraise=true, Barsilence=true}
moving = false
spell_latency = 0.5
tickdelay = 0
midaction = function() return busy end
silent_check_disable = function() return false end
silent_can_use = function() return true end
add_to_chat = function() end
update_job_states = function() end
check_song = function() return false end

assert(loadfile('addons/PartyStart/gearswap/PartyStart_BRD.lua'))()
assert(callbacks.action, 'BRD action handler was not registered')

local event_args = {handled=false}
user_job_self_command(
    {'pstartbrd', 'ambuscade-v1', 'Dolomedes'}, event_args)
assert(event_args.handled, 'activation command was not handled')

-- A ready packet received during another action must queue, then take the next
-- GearSwap heartbeat before routine songs or maintenance.
busy = true
callbacks.action({
    category=7,
    actor_id=breadwinner.id,
    targets={{actions={{param=warbles[1].id}}}},
})
assert(#commands == 0, 'busy ready packet cast instead of queueing')
busy = false
check_song()
assert(commands[#commands] == '/ma "Barfira" <me>',
    'queued Fire Warble did not cast Barfira')
job_aftercast({id=spells_by_name.Barfira.id, interrupted=false}, nil, {})

-- Exercise every remaining ready-packet mapping through the immediate path.
for index=2,#warbles do
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
mob_array = {urchin_two, urchin_one}
fake_now = fake_now + 1
callbacks.action({
    category=11,
    actor_id=breadwinner.id,
    param=warbles[#warbles].id,
})
fake_now = fake_now + 0.2
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

local function command_count(needle)
    local count = 0
    for _, command in ipairs(commands) do
        if command == needle then count = count + 1 end
    end
    return count
end

-- A duplicate completion category cannot double-sleep the same Warble.
fake_now = fake_now + 0.5
callbacks.action({
    category=6,
    actor_id=breadwinner.id,
    param=warbles[#warbles].id,
})
fake_now = fake_now + 0.2
check_song()
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
