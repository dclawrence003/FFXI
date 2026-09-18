local BASE = 'addons/PartyTactics/'
local now = 100
local clients = {}
local dropped_ack = nil
local held_ipc = {}
local hold_ipc = nil

-- Fengari's test runtime omits io.open. Production Windower supplies it; a
-- deterministic read-only stand-in keeps the source-fingerprint path covered.
io.open = function(path, mode)
    assert(mode == 'rb')
    local normalized = tostring(path):gsub('\\', '/'):lower()
    local content = 'test-source:'..normalized
    for _, job in ipairs{'brd','rdm','geo','pld','dnc'} do
        if normalized:find('partytactics_legacy_'..job..'.lua', 1, true)
            or normalized:find('partystart_'..job..'.lua', 1, true)
        then
            content = 'frozen-legacy-support:'..job
            break
        end
    end
    if normalized:find('/partytactics_host.lua', 1, true) then
        content = 'partytactics-gearswap-host-v1'
    elseif normalized:find(
        '/adapters/escha-ruaun-genbu-genmei/2.7.0.lua', 1, true)
    then
        content = 'partytactics-genmei-adapter-v2.7.0'
    end
    return {
        read=function() return content end,
        close=function() end,
    }
end

package.preload.resources = function()
    return {
        monster_abilities=setmetatable({}, {__index=function() return nil end}),
        buffs={
            [33]={id=33,en='Haste'},
            [43]={id=43,en='Refresh'},
            [551]={id=551,en='Magic Atk. Boost'},
            with=function(_, key, value)
            if key == 'en' and value == 'Reraise' then return {id=113} end
            if key == 'en' and value == 'Clarion Call' then return {id=499} end
            if key == 'en' and value == 'Stymie' then return {id=1000} end
            if key == 'en' and value == 'Saboteur' then return {id=1001} end
            if key == 'en' and value == 'Barsilence' then return {id=1002} end
            if key == 'en' and value == 'Protect' then return {id=40} end
            if key == 'en' and value == 'Shell' then return {id=41} end
            if key == 'en' and value == 'Barwater' then return {id=105} end
            if key == 'en' and value == 'Haste' then return {id=33} end
            if key == 'en' and value == 'Refresh' then return {id=43} end
            if key == 'en' and value == 'Phalanx' then return {id=116} end
            if key == 'en' and value == 'Ballad' then return {id=196} end
            if key == 'en' and value == 'Minne' then return {id=197} end
            if key == 'en' and value == 'March' then return {id=214} end
            if key == 'en' and value == 'Magic Atk. Boost' then return {id=551} end
            if key == 'en' and value == "Warlock's Roll" then return {id=314} end
            if key == 'en' and value == 'Samurai Roll' then return {id=321} end
            end,
        },
        items={
            [100]={id=100,en='Rostam'}, [101]={id=101,en='Tauret'},
            [102]={id=102,en='Death Penalty'},
            [103]={id=103,en='Animikii Bullet'},
            [104]={id=104,en='Living Bullet'},
            [105]={id=105,en='Trump Card'},
            [106]={id=106,en='Compensator'},
            [107]={id=107,en='Nusku Shield'},
            [110]={id=110,en='Naegling'},
            [111]={id=111,en='Diamond Aspis'},
            [112]={id=112,en="Gleti's Knife"},
            [113]={id=113,en='Ternion Dagger +1'},
            [120]={id=120,en='Maxentius'}, [121]={id=121,en='Sors Shield'},
            [122]={id=122,en='Dunna'},
            [130]={id=130,en='Echo Drops'},
        },
        weapon_skills={
            [42]={id=42,en='Savage Blade'}, [221]={id=221,en='Last Stand'},
            [25]={id=25,en='Evisceration'}, [169]={id=169,en='Black Halo'},
        },
        job_abilities={
            [35]={id=35,en='Provoke'}, [48]={id=48,en='Sentinel'},
            [75]={id=75,en='Elemental Seal'}, [129]={id=129,en='Thunder Shot'},
            [301]={id=301,en='Triple Shot'},
            [192]={id=192,en='Curing Waltz III'},
            [193]={id=193,en='Curing Waltz IV'},
            [206]={id=206,en='Reverse Flourish'},
            [239]={id=239,en='No Foot Rise'},
            [311]={id=311,en='Curing Waltz V'},
            [386]={id=386,en='Entrust'},
            [49]={id=49,en='Rampart'}, [200]={id=200,en='Stymie'},
            [201]={id=201,en='Saboteur'},
            [255]={id=255,en='Divine Emblem'},
            [189]={id=189,en='Haste Samba'},
            [202]={id=202,en='Box Step'},
            [261]={id=261,en='Presto'},
        },
        spells={
            [4]={id=4,en='Cure IV',levels={[3]=48,[5]=48}},
            [13]={id=13,en='Cure III',levels={[3]=21,[21]=21}},
            [47]={id=47,en='Protect V',levels={[3]=76,[5]=77}},
            [52]={id=52,en='Shell V',levels={[3]=76,[5]=87}},
            [71]={id=71,en='Barwatera',levels={[3]=9}},
            [107]={id=107,en='Phalanx II',levels={[5]=75}},
            [135]={id=135,en='Reraise',levels={[3]=25}},
            [59]={id=59,en='Silence',levels={[5]=18}},
            [112]={id=112,en='Flash',levels={[7]=37}},
            [143]={id=143,en='Erase',levels={[3]=32}},
            [164]={id=164,en='Thunder',levels={[5]=29,[21]=29}},
            [167]={id=167,en='Thunder IV',levels={[5]=92,[21]=91}},
            [168]={id=168,en='Thunder V',levels={[21]=100}},
            [252]={id=252,en='Stun',levels={[4]=45,[8]=37}},
            [260]={id=260,en='Dispel',levels={[5]=32}},
            [274]={id=274,en='Sleepga',levels={[4]=31}},
            [376]={id=376,en='Horde Lullaby II',levels={[10]=92}},
            [388]={id=388,en="Mage's Ballad III",levels={[10]=85}},
            [393]={id=393,en="Knight's Minne V",levels={[10]=80}},
            [401]={id=401,en='Barsilencera',levels={[3]=23}},
            [420]={id=420,en='Victory March',levels={[10]=60}},
            [476]={id=476,en='Crusade',levels={[7]=88}},
            [462]={id=462,en='Magic Finale',levels={[10]=33}},
            [511]={id=511,en='Haste II',levels={[5]=96}},
            [768]={id=768,en='Indi-Fury',levels={[21]=34}},
            [769]={id=769,en='Geo-Frailty',levels={[21]=44}},
            [770]={id=770,en='Indi-Fend',levels={[21]=75}},
            [781]={id=781,en='Indi-Acumen',levels={[21]=46}},
            [794]={id=794,en='Indi-Languor',levels={[21]=64}},
            [820]={id=820,en='Geo-Malaise',levels={[21]=92}},
            [894]={id=894,en='Refresh III',levels={[5]=99}},
        },
        key_items={
            [2894]={id=2894,en='tribulens'},
            [2944]={id=2944,en="Kammavaca's binding"},
            [2949]={id=2949,en="Genbu's Honor"},
            [3031]={id=3031,en='radialens'},
        },
    }
end
package.preload.tables = function() return {} end

local roster = {
    {name='Dolomedes', id=1001, index=1001, main_job='COR', main_job_id=17,
        main_job_level=99, sub_job='DNC', sub_job_id=19, sub_job_level=49,
        job_points={cor={jp_spent=2100}},
        buffs={33,40,41,105,116,214,314,321}},
    {name='Tackleberry', id=1002, index=1002, main_job='PLD', main_job_id=7,
        main_job_level=99, sub_job='WAR', sub_job_id=1, sub_job_level=49,
        buffs={33,40,41,43,105,116,197,214,321}},
    {name='Kickpuncher', id=1003, index=1003, main_job='DNC', main_job_id=19,
        main_job_level=99, sub_job='WAR', sub_job_id=1, sub_job_level=49,
        buffs={33,40,41,105,116,197,214,321}},
    {name='Barneystinson', id=1004, index=1004, main_job='BRD', main_job_id=10,
        main_job_level=99, sub_job='WHM', sub_job_id=3, sub_job_level=49,
        buffs={40,41,43,105,196}},
    {name='Smalls', id=1005, index=1005, main_job='RDM', main_job_id=5,
        main_job_level=99, sub_job='WHM', sub_job_id=3, sub_job_level=49,
        buffs={33,40,41,43,105,196,314}},
    {name='Achoo', id=1006, index=1006, main_job='GEO', main_job_id=21,
        main_job_level=99, sub_job='WHM', sub_job_id=3, sub_job_level=49,
        job_points={geo={jp_spent=2100}},
        buffs={33,40,41,43,105,196,314,551}},
}

local PREFLIGHT_FIXTURES = {
    Dolomedes={
        equipment={main=1,main_bag=8,sub=2,sub_bag=8,range=3,range_bag=8,
            ammo=4,ammo_bag=8},
        equipped={['8:1']={id=100,count=1},['8:2']={id=101,count=1},
            ['8:3']={id=102,count=1},['8:4']={id=104,count=1}},
        bags={Inventory={enabled=true,{id=105,count=50},{id=130,count=12}},
            Wardrobe={enabled=true,{id=103,count=1},{id=104,count=454}}},
        key_items={2894,2944,2949},
        abilities={job_abilities={129,301},weapon_skills={42,221}}, spells={},
    },
    Tackleberry={
        equipment={main=1,main_bag=8,sub=2,sub_bag=8},
        equipped={['8:1']={id=110,count=1},['8:2']={id=111,count=1}},
        bags={Inventory={enabled=true,{id=130,count=12}}}, key_items={2894},
        abilities={job_abilities={35,48,49,255},weapon_skills={42}},
        spells={[112]=true,[476]=true},
    },
    Kickpuncher={
        equipment={main=1,main_bag=8,sub=2,sub_bag=8},
        equipped={['8:1']={id=101,count=1},['8:2']={id=113,count=1}},
        bags={Inventory={enabled=true,{id=130,count=12}}}, key_items={2894},
        abilities={
            job_abilities={189,192,193,202,206,239,261,311},
            weapon_skills={25},
        },
        spells={},
    },
    Barneystinson={equipment={},equipped={},
        bags={Inventory={enabled=true,{id=130,count=12}}}, key_items={2894},
        abilities={job_abilities={},weapon_skills={}},
        spells={[71]=true,[135]=true,[143]=true,[376]=true,[388]=true,
            [393]=true,[401]=true,[420]=true,[462]=true}},
    Smalls={equipment={},equipped={},
        bags={Inventory={enabled=true,{id=130,count=12}}}, key_items={2894},
        abilities={job_abilities={75,200,201},weapon_skills={}},
        spells={[4]=true,[47]=true,[52]=true,[59]=true,[107]=true,
            [164]=true,[167]=true,[252]=true,[260]=true,[274]=true,
            [511]=true,[894]=true}},
    Achoo={
        equipment={main=1,main_bag=8,sub=2,sub_bag=8,range=3,range_bag=8},
        equipped={['8:1']={id=120,count=1},['8:2']={id=121,count=1},
            ['8:3']={id=122,count=1}},
        bags={Inventory={enabled=true,{id=130,count=12}}}, key_items={2894},
        abilities={job_abilities={386},weapon_skills={}},
        spells={[13]=true,[164]=true,[167]=true,[168]=true,
            [768]=true,[769]=true,[770]=true,[781]=true,[794]=true,
            [820]=true},
    },
}

local EASYFARM_ARTIFACTS = {
    'profiles/locus-dire-bats-tomb/easyfarm/'
        ..'Tackleberry-Locus-Dire-Bats-Stationary.eup',
    'profiles/limbus-119-stationary/easyfarm/'
        ..'Tackleberry-Limbus-119-Stationary.eup',
}
local AUGUST_SHORTCUT_SIDECAR =
    'ambuscade-2026-08-v1-breadwinner.lua'

local function party_table()
    local result = {}
    for index, player in ipairs(roster) do
        result['p'..tostring(index - 1)] = {
            name=player.name,
            tp=1000,
            hpp=100,
            mob={id=player.id, name=player.name},
        }
    end
    -- A same-alliance claimant must not satisfy the local six-party gate.
    result.a10 = {name='Allianceguest', mob={id=9999, name='Allianceguest'}}
    return result
end

local function file_exists(path)
    for _, artifact in ipairs(EASYFARM_ARTIFACTS) do
        if path:find(artifact, 1, true) then return true end
    end
    if path:find('adapters/manual/brd-pack-sleep.lua', 1, true)
        or path:find('adapters/manual/typed-action.lua', 1, true)
        or path:find('adapters/manual/clarion-extra-song.lua', 1, true)
        or path:find('adapters/manual/exact-enemy-action.lua', 1, true)
        or path:find('adapters/manual/rdm-exact-silence.lua', 1, true)
    then
        return true
    end
    if path:find('data/supplemental_aliases/'..AUGUST_SHORTCUT_SIDECAR,
        1, true)
    then
        return true
    end
    if path:find('data/profile_identities/', 1, true)
        and path:sub(-4) == '.lua'
    then
        return true
    end
    if path:find('profiles/ambuscade-2026-08-v1-breadwinner/runtime.lua',
        1, true)
        or path:find('profiles/escha-ruaun-genbu-genmei/runtime.lua',
            1, true)
        or path:find('profiles/escha-ruaun-kammavaca/runtime.lua',
            1, true)
        or path:find('profiles/sortie-boss-skomora-v1/runtime.lua',
            1, true)
        or path:find('profiles/sortie-main-v1/runtime.lua',
            1, true)
    then
        return true
    end
    return path:find('/profile.lua', 1, true) ~= nil
end

for _, artifact in ipairs(EASYFARM_ARTIFACTS) do
    assert(file_exists(BASE..artifact), 'mock omitted EasyFarm artifact '..artifact)
end

local function add_callback(client, event, callback)
    client.callbacks[event] = client.callbacks[event] or {}
    client.callbacks[event][#client.callbacks[event] + 1] = callback
end

local function fire(client, event, ...)
    for _, callback in ipairs(client.callbacks[event] or {}) do callback(...) end
end

local function broadcast(message, sender)
    -- Match Windower's real inter-process behavior: the sender does not depend
    -- on receiving its own IPC packet back.
    for _, client in ipairs(clients) do
        local suppress = dropped_ack
            and message:find('PARTYTACTICS1|ack|', 1, true) == 1
            and sender.player.name == dropped_ack.sender
            and client.player.name == dropped_ack.recipient
        if client ~= sender and not suppress then
            if hold_ipc and hold_ipc(message, sender, client) then
                held_ipc[#held_ipc + 1] = {
                    message=message, sender=sender, recipient=client,
                }
            else
                fire(client, 'ipc message', message)
            end
        end
    end
end

local function build_client(player)
    local client = {
        player=player, callbacks={}, commands={}, chats={}, sounds={}, mobs={},
        ipc_messages={},
        current_target=nil, controller_probe_enabled=true,
        host_probe_enabled=true, helper_probe_enabled=true,
    }
    local fixture = assert(PREFLIGHT_FIXTURES[player.name])
    local windower = {
        addon_path=BASE,
        get_dir=function(path)
            if path:find('data/profile_identities/', 1, true) then
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
                    'sortie-main-v1.lua',
                    'locus-dire-bats-tomb-signet.lua',
                }
            end
            if path:find('data/supplemental_aliases/', 1, true) then
                -- Only the initiating leader knows the friendly name. Followers
                -- still receive and validate the canonical profile id over IPC.
                return player.name == 'Dolomedes'
                    and {AUGUST_SHORTCUT_SIDECAR} or {}
            end
            if path:find('profiles', 1, true) then
                return {
                    'locus-dire-bats-tomb',
                    'locus-dire-bats-tomb-signet',
                    'limbus-119-stationary',
                    'ambuscade-2026-08-v1-breadwinner',
                    'dynamis-divergence-wave1-route-corsair',
                    'dynamis-divergence-wave1-boss-magic',
                    'escha-ruaun-genbu-genmei',
                    'escha-ruaun-kammavaca',
                    'sortie-boss-skomora-v1',
                    'sortie-main-v1',
                }
            end
            if path:find('adapters/manual', 1, true) then
                return {
                    'brd-pack-sleep.lua',
                    'typed-action.lua',
                    'clarion-extra-song.lua',
                    'exact-enemy-action.lua',
                    'rdm-exact-silence.lua',
                }
            end
            return {}
        end,
        file_exists=file_exists,
        add_to_chat=function(color, message)
            client.chats[#client.chats + 1] = {color=color, message=message}
        end,
        send_command=function(command)
            client.commands[#client.commands + 1] = command
            local host_generation, host_epoch = command:match(
                '^gs c ptgs probe (%d+%-%d+%-%d+) (%d+)$')
            if host_generation and client.host_probe_enabled then
                -- Emulate the stable EOF host's local execution proof.
                fire(client, 'addon command', '__gearswap_host_ready',
                    '1.2.1', host_generation, host_epoch)
            end
            local helper_prefix, helper_generation, helper_epoch,
                helper_version = command:match(
                    '^gs c (pstart[a-z]+) probe '
                        ..'(%d+%-%d+%-%d+) (%d+) ([0-9%.]+)$')
            local helper_jobs = {
                pstartbrd='BRD', pstartrdm='RDM', pstartgeo='GEO',
                pstartpld='PLD', pstartdnc='DNC',
            }
            local helper_job = helper_jobs[helper_prefix]
            if helper_job and client.helper_probe_enabled then
                fire(client, 'addon command', '__legacy_helper_ready',
                    helper_version, helper_job, helper_generation,
                    helper_epoch)
            end
            local controller, generation, epoch, protocol = command:match(
                'gs c ptgs action ([a-z0-9%-]+) probe '
                    ..'(%d+%-%d+%-%d+) (%d+) (%d+)$')
            if generation and client.controller_probe_enabled then
                -- Emulate the reviewed GearSwap queue's local capability
                -- response. PartyTactics still validates generation, epoch,
                -- protocol, assigned job, and profile declaration itself.
                fire(client, 'addon command', '__controller_ready',
                    controller, generation, epoch, protocol)
            end
            local observe_id = tonumber(
                command:match('^pc observeid (%d+)$'))
            if observe_id then
                client.current_target = nil
                for _, mob in pairs(client.mobs) do
                    if mob.id == observe_id then
                        client.current_target = mob
                        break
                    end
                end
            end
        end,
        send_ipc_message=function(message)
            client.ipc_messages[#client.ipc_messages + 1] = message
            broadcast(message, client)
        end,
        play_sound=function(path) client.sounds[#client.sounds + 1] = path end,
        register_event=function(event, callback)
            add_callback(client, event, callback)
        end,
        ffxi={
            get_player=function() return player end,
            get_info=function()
                return {logged_in=true, zone=client.zone or 289}
            end,
            get_party=party_table,
            get_mob_by_id=function(id)
                id = tonumber(id)
                for _, mob in pairs(client.mobs) do
                    if mob.id == id then return mob end
                end
                for _, member in ipairs(roster) do
                    if member.id == id then return member end
                end
                return nil
            end,
            get_mob_array=function() return client.mobs end,
            get_mob_by_target=function(token)
                assert(token == 't')
                return client.current_target
            end,
            get_items=function(bag, index)
                if bag == nil then return {equipment=fixture.equipment} end
                if index ~= nil then
                    return fixture.equipped[tostring(bag)..':'..tostring(index)]
                end
                return fixture.bags[bag] or {enabled=false}
            end,
            get_key_items=function() return fixture.key_items end,
            get_abilities=function() return fixture.abilities end,
            get_spells=function() return fixture.spells end,
        },
    }
    local environment = setmetatable({
        _addon={}, windower=windower,
        os={clock=function() return now end, time=function() return 1700000000 end},
    }, {__index=_G})
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(BASE..'PartyTactics.lua')
        if loader then setfenv(loader, environment) end
    else
        loader, load_error = loadfile(BASE..'PartyTactics.lua', 't', environment)
    end
    assert(loader, load_error)
    loader()
    client.environment = environment
    return client
end

for _, player in ipairs(roster) do
    clients[#clients + 1] = build_client(player)
end

local function client_named(name)
    for _, client in ipairs(clients) do
        if client.player.name == name then return client end
    end
end

local function command_count()
    local result = {}
    for _, client in ipairs(clients) do result[client.player.name] = #client.commands end
    return result
end

local function assert_counts_unchanged(before)
    for _, client in ipairs(clients) do
        assert(#client.commands == before[client.player.name],
            client.player.name..' changed automation during a rejected/previewed prepare')
    end
end

local function contains_command(client, text, start_index)
    for index = start_index or 1, #client.commands do
        if client.commands[index]:find(text, 1, true) then return true end
    end
    return false
end

local function count_command(client, text, start_index)
    local count = 0
    for index = start_index or 1, #client.commands do
        if client.commands[index]:find(text, 1, true) then count = count + 1 end
    end
    return count
end

function assert_no_raw_partycombat(starts, label)
    for _, client in ipairs(clients) do
        local first = starts[client.player.name] + 1
        assert(not contains_command(client, 'pc on', first)
            and not contains_command(client, 'pc off', first),
            client.player.name..' received noisy PartyCombat '..label)
    end
end

function assert_silent_ordered_off(starts)
    local leader = client_named('Dolomedes')
    assert(count_command(leader, 'pc off', starts.Dolomedes + 1) == 1,
        'explicit leader disarm did not retain one immediate visible OFF edge')
    for _, client in ipairs(clients) do
        local first = starts[client.player.name] + 1
        assert(contains_command(client, 'pc reconcile off', first),
            client.player.name..' did not apply the ordered OFF locally')
        if client ~= leader then
            assert(not contains_command(client, 'pc off', first),
                client.player.name..' replayed a noisy distributed OFF')
        end
    end
end

function assert_silent_periodic_off(starts)
    assert_no_raw_partycombat(starts, 'OFF from periodic repair')
    for _, client in ipairs(clients) do
        assert(contains_command(client, 'pc reconcile off',
            starts[client.player.name] + 1),
            client.player.name..' lost silent periodic OFF convergence')
    end
end

function assert_genmei_combat_routing(starts, label)
    for _, name in ipairs{'Dolomedes','Tackleberry','Kickpuncher','Smalls'} do
        local client = client_named(name)
        assert(contains_command(client, 'pc on',
            starts[client.player.name] + 1),
            client.player.name..' lost Genmei PartyCombat ON during '..label)
    end
    for _, name in ipairs{'Barneystinson','Achoo'} do
        local client = client_named(name)
        local first = starts[client.player.name] + 1
        assert(not contains_command(client, 'pc on', first),
            client.player.name..' received Genmei PartyCombat ON during '..label)
        assert(contains_command(client, 'pc reconcile off', first),
            client.player.name..' did not remain silently combat-off during '..label)
    end
end

local function split_fields(message)
    local result = {}
    for field in (tostring(message)..'|'):gmatch('(.-)|') do
        result[#result + 1] = field
    end
    return result
end

local function find_ipc(client, prefix, start_index)
    for index = start_index or 1, #client.ipc_messages do
        local message = client.ipc_messages[index]
        if message:find(prefix, 1, true) == 1 then return message end
    end
    return nil
end

local function first_command_index(client, text, start_index)
    for index = start_index or 1, #client.commands do
        if client.commands[index] == text then return index end
    end
    return nil
end

local function contains_chat(client, text, start_index)
    for index = start_index or 1, #client.chats do
        if client.chats[index].message:find(text, 1, true) then return true end
    end
    return false
end

local function recent_chats(client, maximum)
    local messages = {}
    local first = math.max(1, #client.chats - (maximum or 8) + 1)
    for index = first, #client.chats do
        messages[#messages + 1] = client.chats[index].message
    end
    return table.concat(messages, ' || ')
end

local function named_upvalue(callback, wanted)
    for index = 1, 64 do
        local name, value = debug.getupvalue(callback, index)
        if not name then break end
        if name == wanted then return value end
    end
end

local function render_all(delta)
    now = now + delta
    for _, client in ipairs(clients) do fire(client, 'prerender') end
end

local dolo = client_named('Dolomedes')
local barney = client_named('Barneystinson')
local tackle = client_named('Tackleberry')
local kick = client_named('Kickpuncher')
local smalls = client_named('Smalls')
local achoo = client_named('Achoo')

-- PartyCombat is an explicit init/safe-reload dependency. Loading
-- PartyTactics itself is silent and inert: it must not blindly request an
-- already-loaded dependency or select profile, target, or combat state.
for _, client in ipairs(clients) do
    assert(#client.commands == 0)
end

-- Preview is a true read-only distributed validation.
local before_preview = command_count()
fire(dolo, 'addon command', 'preview', 'limbus')
assert_counts_unchanged(before_preview)

-- A profile with one invalid subjob cannot disturb the currently active one.
dropped_ack = {sender='Achoo', recipient='Dolomedes'}
local locus_commit_starts = command_count()
fire(dolo, 'addon command', 'use', 'locus')
for _, client in ipairs(clients) do
    local first = locus_commit_starts[client.player.name] + 1
    local invalidate_index = first_command_index(
        client, 'pc invalidate partytactics', first)
    assert(invalidate_index,
        client.player.name..' did not invalidate PartyCombat at commit')
    assert(count_command(client, 'lua load PartyCombat', first) == 0,
        client.player.name..' issued a blind PartyCombat load at commit')
end
render_all(2.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc policy pt-locus-bats'))
    assert(contains_command(client, 'gs c ptgs probe '),
        client.player.name..' did not prove the stable GearSwap host')
    if client.player.main_job ~= 'COR' then
        local helper_prefix = ({
            BRD='pstartbrd', RDM='pstartrdm', GEO='pstartgeo',
            PLD='pstartpld', DNC='pstartdnc',
        })[client.player.main_job]
        assert(contains_command(client,
            'gs c '..helper_prefix..' probe ',
            locus_commit_starts[client.player.name] + 1),
            client.player.name..' did not prove its frozen support helper')
    end
end
assert(contains_command(barney, 'gs c pstartbrd locusbats Tackleberry'))
assert(not contains_command(barney, 'equip'))
assert(not contains_command(barney, 'gs c disable'))
assert(not contains_command(barney, 'range='))
assert(not contains_command(barney, 'ammo='))
assert(contains_command(dolo, 'pc on'),
    'use <profile> must arm the selected profile in the same transaction')
local locus_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 5/6', locus_status_start))
local best_effort_arm_start = #dolo.commands + 1
local best_effort_arm_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', best_effort_arm_start) == 1)
assert(contains_chat(dolo, 'Profile ON requested',
    best_effort_arm_chat))

-- A leader state sync lets the missing client repeat its epoch-scoped ACK.
dropped_ack = nil
render_all(5.1)
local recovered_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 6/6', recovered_status_start))

-- Revisioned operator transport retained by 0.13.3 is intentionally a wire break from
-- 0.13.1. A mixed client must reject the distributed activation
-- barrier instead of appearing compatible and later ignoring stop traffic.
do
    local template = split_fields(assert(find_ipc(
        dolo, 'PARTYTACTICS1|prepare|')))
    local mismatch_nonce = '1700000001-9999-77'
    local mismatch_prepare = table.concat({
        'PARTYTACTICS1', 'prepare', mismatch_nonce, '0.13.1',
        template[5], template[6], template[7], template[8], template[9],
        template[10], template[11], template[12], template[13],
        template[14],
    }, '|')
    local before_mismatch = command_count()
    for _, client in ipairs(clients) do
        local vote_start = #client.ipc_messages + 1
        fire(client, 'ipc message', mismatch_prepare)
        local vote = assert(find_ipc(client,
            'PARTYTACTICS1|vote|'..mismatch_nonce..'|0.13.3|',
            vote_start))
        assert(vote:find('|reject|', 1, true))
        assert(vote:find('PartyTactics version mismatch (0.13.1)', 1, true))
    end
    local mismatch_commit = table.concat({
        'PARTYTACTICS1', 'commit', mismatch_nonce, '0.13.1',
        template[5], template[6], template[7], template[8], template[9],
        '0', '0', '0', '0', '0',
    }, '|')
    for _, client in ipairs(clients) do
        fire(client, 'ipc message', mismatch_commit)
    end
    assert_counts_unchanged(before_mismatch)
end

-- A GearSwap host reload pauses only that client's fight adapter. It cannot
-- retire the party profile or deny combat/manual controls on healthy clients.
local host_loss_starts = command_count()
fire(smalls, 'addon command', '__gearswap_host_lost',
    '1.0.0', 'file-unload')
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc invalidate partytactics',
        host_loss_starts[client.player.name] + 1))
end
fire(dolo, 'addon command', 'off')
barney.helper_probe_enabled = false
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
local missing_helper_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 5/6', missing_helper_status),
    'missing legacy helper diagnostic was not visible')
local missing_helper_arm = #dolo.commands + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', missing_helper_arm) == 1)
fire(dolo, 'addon command', 'off')
barney.helper_probe_enabled = true
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)

-- A fight-adapter callback exception is also local and advisory.
local adapter_error_starts = command_count()
fire(smalls, 'addon command', '__gearswap_host_lost',
    '1.0.0', 'adapter-error')
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc invalidate partytactics',
        adapter_error_starts[client.player.name] + 1))
end

barney.player.sub_job = 'RDM'
local before_reject = command_count()
fire(dolo, 'addon command', 'use', 'v1')
render_all(2.1)
assert(contains_command(barney, 'pc policy pt-ambu2608v1',
    before_reject.Barneystinson + 1),
    'setup observation incorrectly denied profile load')
barney.player.sub_job = 'WHM'

-- Route-owned activation can request a profile and arm state in one exact
-- command. The distributed commit applies support first, then arms every
-- client's PartyCombat policy without requiring a second operator command.
local limbus_arm_start = #dolo.commands + 1
fire(dolo, 'addon command', 'use', 'limbus', 'armed')
local limbus_command_start = #barney.commands + 1
render_all(2.1)
assert(count_command(dolo, 'pc on', limbus_arm_start) == 1,
    'use <profile> armed did not arm after the distributed commit')
local limbus_armed_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'combat armed', limbus_armed_status),
    'arm-on-load intent was not retained')
assert(contains_command(barney, 'gs c pstartbrd limbus Tackleberry',
    limbus_command_start))
for _, client in ipairs(clients) do
    assert(contains_command(client, 'aws2 exclude elemental'))
end
local before_sleep = #barney.commands + 1
fire(dolo, 'addon command', 'sleep')
assert(count_command(barney, 'gs c pstartbrd sleep', before_sleep) == 1)

-- V1 does not inherit Limbus's BRD offense or manual action behavior. The
-- leader-only supplemental name resolves through the same direct-command path;
-- followers with no shortcut sidecar commit the broadcast canonical id.
fire(dolo, 'addon command', 'v1-breadwinner')
local v1_barney_start = #barney.commands + 1
local v1_starts = command_count()
render_all(2.1)
assert(contains_command(barney,
    'gs c pstartbrd ambuscade-v1 Tackleberry', v1_barney_start))
assert(not contains_command(barney, 'aws2 on', v1_barney_start))
assert(not contains_command(barney, 'gs c weapons', v1_barney_start))
assert(contains_command(dolo, 'pc policy pt-ambu2608v1'))
for _, client in ipairs(clients) do
    assert(contains_command(client, 'aws2 exclude none',
        v1_starts[client.player.name] + 1))
end
local shortcut_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo,
    'Active ambuscade-2026-08-v1-breadwinner', shortcut_status_start))
assert(contains_chat(dolo, 'acks 6/6', shortcut_status_start))
local old_alias_chat_start = #dolo.commands + 1
fire(dolo, 'addon command', 'v1')
assert(count_command(dolo, 'pc on', old_alias_chat_start) == 1,
    'direct profile alias did not select and arm in one command')
local explicit_alias_chat_start = #dolo.commands + 1
fire(dolo, 'addon command', 'use', 'v1-breadwinner')
assert(count_command(dolo, 'pc policy pt-ambu2608v1',
    v1_starts.Dolomedes + 1) == 1)
assert(count_command(dolo, 'pc on', explicit_alias_chat_start) == 1,
    'use <profile> did not arm an already-selected profile')

-- Zoning starts a fresh application epoch, but an early arm request is an
-- accepted operator intent and is reissued after the local profile reapplies.
for _, client in ipairs(clients) do fire(client, 'zone change') end
local pending_epoch_arm_start = #dolo.commands + 1
local pending_epoch_chat_start = #dolo.chats + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', pending_epoch_arm_start) == 0,
    'ON became effective while the replacement epoch was unavailable')
assert(contains_chat(dolo, 'Profile ON requested',
    pending_epoch_chat_start))
dropped_ack = {sender='Achoo', recipient='Dolomedes'}
render_all(8.1)
assert(count_command(dolo, 'pc on', pending_epoch_arm_start) == 1,
    'preserved ON intent was not replayed after local reapply')
local epoch_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 5/6', epoch_status_start))
local epoch_blocked_arm_start = #dolo.commands + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', epoch_blocked_arm_start) == 1)
dropped_ack = nil
render_all(5.1)
local epoch_recovered_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 6/6', epoch_recovered_status))

-- Combat remains a separate, explicit arm step.
local arm_start = #dolo.commands + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', arm_start) == 1)
local armed_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'combat armed', armed_status_start),
    'explicit arm did not latch post-positioning consent')

-- A replacement profile starts its own declared policy and arms it in the
-- same transaction. It cannot inherit V1's support or target roster.
fire(dolo, 'addon command', 'use', 'ddw1route')
local route_starts = command_count()
render_all(2.1)
local route_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'combat armed', route_status_start),
    'profile replacement did not arm its own combat policy')
assert(contains_command(dolo, 'pc policy pt-ddw1-route'))
assert(contains_command(dolo, 'aws2 tp 1500', route_starts.Dolomedes + 1))
assert(contains_command(barney, 'gs c pstartbrd off',
    route_starts.Barneystinson + 1))
assert(not contains_command(barney, 'gs c pstartbrd magicboss',
    route_starts.Barneystinson + 1))

-- Boss activation is another complete barrier. Both attacker WS loops remain
-- off, while guarded/manual requests pass only through their declared adapter.
fire(dolo, 'addon command', 'use', 'ddw1boss')
local boss_starts = command_count()
render_all(2.1)
assert(contains_command(barney, 'gs c pstartbrd magicboss Tackleberry',
    boss_starts.Barneystinson + 1))
assert(contains_command(tackle, 'gs c pstartpld manualsc Dolomedes',
    boss_starts.Tackleberry + 1))
assert(contains_command(tackle,
    'gs c set AutoBuffMode Off; gs c unset AutoTankMode;',
    boss_starts.Tackleberry + 1))
assert(contains_command(dolo,
    'gs c weapons DualLeaden; wait 1; aws2 off',
    boss_starts.Dolomedes + 1))
assert(not contains_command(dolo, 'aws2 on', boss_starts.Dolomedes + 1))
assert(not contains_command(tackle, 'aws2 on', boss_starts.Tackleberry + 1))

local clarion_start = #barney.commands + 1
fire(dolo, 'addon command', 'clarion')
assert(count_command(barney, 'input /ja "Clarion Call" <me>',
    clarion_start) == 1)
local blocked_ballad_start = #barney.commands + 1
local blocked_chat_start = #dolo.chats + 1
fire(dolo, 'addon command', 'ballad2')
assert(not contains_command(barney, 'Mage\'s Ballad II', blocked_ballad_start))
assert(contains_chat(dolo, 'ballad2 rejected by Barneystinson:',
    blocked_chat_start))
barney.player.buffs = {499}
local ballad_start = #barney.commands + 1
local accepted_chat_start = #dolo.chats + 1
fire(dolo, 'addon command', 'ballad2')
assert(count_command(barney, 'input /ma "Mage\'s Ballad II" <me>',
    ballad_start) == 1)
assert(contains_chat(dolo, 'ballad2 accepted by Barneystinson',
    accepted_chat_start))

local cdc_start = #tackle.commands + 1
fire(dolo, 'addon command', 'cdc')
assert(count_command(tackle, 'input /ws "Chant du Cygne" <t>',
    cdc_start) == 1)

local provoke_start = #tackle.commands + 1
fire(dolo, 'addon command', 'provoke')
assert(count_command(tackle, 'input /ja "Provoke" <t>',
    provoke_start) == 1)

local disarm_start = #dolo.commands + 1
fire(dolo, 'addon command', 'disarm')
assert(count_command(dolo, 'pc off', disarm_start) == 1)
local disarmed_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'combat unarmed', disarmed_status_start),
    'disarm did not consume the operator latch')
local boss_arm_start = #dolo.commands + 1
fire(dolo, 'addon command', 'arm')
assert(count_command(dolo, 'pc on', boss_arm_start) == 1)

-- Genmei is a separate automatic boss profile. Its deterministic weapon modes
-- are selected with all AutoWS loops Off; the encounter runtime owns the
-- exact-ID, packet-observed chain without any readiness barrier.
barney.player.buffs = {40,41,43,105,196}
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:2'] = {id=107,count=1}
fire(dolo, 'addon command', 'use', 'genmei')
local genmei_starts = command_count()
render_all(2.1)
assert_genmei_combat_routing(genmei_starts, 'initial apply')
assert(contains_command(dolo, 'pc policy pt-genbu-genmei',
    genmei_starts.Dolomedes + 1), recent_chats(dolo, 20))
assert(contains_command(dolo,
    'gs c weapons DeathPenalty; wait 1; aws2 off',
    genmei_starts.Dolomedes + 1))
assert(contains_command(dolo,
    'r2 roll1 warlock; r2 roll2 samurai',
    genmei_starts.Dolomedes + 1))
assert(contains_command(dolo,
    'gs c set CompensatorMode Never; gs c unset UnlockWeapons',
    genmei_starts.Dolomedes + 1))
assert(contains_command(tackle, 'gs c pstartpld manualsc Dolomedes',
    genmei_starts.Tackleberry + 1))
assert(contains_command(kick, 'gs c pstartdnc off',
    genmei_starts.Kickpuncher + 1))
assert(not contains_command(kick, 'gs c pstartdnc tankheal Tackleberry',
    genmei_starts.Kickpuncher + 1))
assert(contains_command(tackle,
    'gs c set AutoBuffMode Off; gs c unset AutoTankMode;',
    genmei_starts.Tackleberry + 1))
assert(contains_command(kick,
    'gs c weapons Tauret; wait 1; aws2 off',
    genmei_starts.Kickpuncher + 1))
assert(contains_command(tackle,
    'gs c weapons Naegling; wait 1; aws2 off',
    genmei_starts.Tackleberry + 1))
assert(contains_command(barney, 'gs c pstartbrd magicboss Tackleberry',
    genmei_starts.Barneystinson + 1))
assert(contains_command(smalls, 'gs c pstartrdm limbus-protect Tackleberry',
    genmei_starts.Smalls + 1))
assert(contains_command(achoo, 'gs c pstartgeo leanmanaged',
    genmei_starts.Achoo + 1))
assert(contains_command(achoo,
    'hb db off; hb as off; hb as attack off; hb off',
    genmei_starts.Achoo + 1))
assert(contains_command(barney,
    'hb db off; hb as off; hb as attack off; hb off',
    genmei_starts.Barneystinson + 1))
assert(contains_command(smalls,
    'hb deactivateindoors off; hb disable cure; hb enable na',
    genmei_starts.Smalls + 1))
assert(contains_command(achoo,
    'gs c weapons Maxentius; wait 1; aws2 off',
    genmei_starts.Achoo + 1))
for _, client in ipairs(clients) do
    assert(contains_command(client,
        'gs c ptgs activate escha-ruaun-genbu-genmei 2.7.0',
        genmei_starts[client.player.name] + 1),
        client.player.name..' did not activate the pinned adapter')
    assert(contains_command(client, 'gs c ptgs action genmei probe ',
        genmei_starts[client.player.name] + 1),
        client.player.name..' did not receive a controller capability probe')
end
for _, client in ipairs(clients) do
    assert(contains_command(client, 'aws2 exclude none',
        genmei_starts[client.player.name] + 1))
end
assert(not contains_command(dolo, 'aws2 on', genmei_starts.Dolomedes + 1))
assert(not contains_command(tackle, 'aws2 on', genmei_starts.Tackleberry + 1))
assert(not contains_command(kick, 'aws2 on', genmei_starts.Kickpuncher + 1))
local genmei_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 6/6', genmei_status_start))
assert(contains_chat(dolo, 'preflight not run', genmei_status_start))

-- An explicit arm from a support-only profile member is a profile-wide
-- operator request, not PartyCombat authority for that local client.
genmei_rearm_starts = command_count()
fire(barney, 'addon command', 'arm')
assert_genmei_combat_routing(genmei_rearm_starts, 'explicit rearm')

-- Alt-L's sleep command is a fixed-roster emergency surface and has no check
-- or acknowledgement prerequisite.
local universal_sleep_start = #barney.commands + 1
fire(dolo, 'addon command', 'sleep')
assert(count_command(barney, 'gs c pstartbrd sleep',
    universal_sleep_start) == 1)

-- Checks are optional diagnostics. Combat controls work before any check.
local unchecked_force = #dolo.commands + 1
fire(dolo, 'addon command', 'force')
assert(count_command(dolo, 'pc force', unchecked_force) == 1)
local initial_check_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
assert(contains_chat(dolo, 'CHECK PASS 6/6', initial_check_chat),
    recent_chats(dolo, 20))

-- A missing support effect is reported, but does not block or retry combat.
smalls.player.buffs = {33,40,41,43,105,196}
local missing_roll_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
assert(contains_chat(dolo, "Smalls: buff Warlock's Roll missing",
    missing_roll_chat))
for _, client in ipairs(clients) do
    local revoked_status = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(not contains_chat(client, 'preflight PASS', revoked_status))
end
smalls.player.buffs = {33,40,41,43,105,196,314}
render_all(10.1)
assert(not contains_command(barney, 'pc on',
    genmei_starts.Barneystinson + 1),
    'Genmei commit/state repair armed support-only Barney')
assert(not contains_command(achoo, 'pc on', genmei_starts.Achoo + 1),
    'Genmei commit/state repair armed support-only Achoo')
local no_automatic_retry_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'preflight not run', no_automatic_retry_status),
    'Genmei unexpectedly retried its diagnostic check')
local force_after_warning = #dolo.commands + 1
fire(dolo, 'addon command', 'force')
assert(count_command(dolo, 'pc force', force_after_warning) == 1)

-- A GearSwap-affecting reapply renews adapters without scheduling a check.
local sync_reapply_starts = command_count()
for _, client in ipairs(clients) do fire(client, 'gain buff', 269) end
render_all(3.1)
assert_genmei_combat_routing(sync_reapply_starts, 'reapply')
for _, client in ipairs(clients) do
    assert(contains_command(client, 'gs c ptgs action genmei probe ',
        sync_reapply_starts[client.player.name] + 1),
        client.player.name..' did not renew capability after reapply')
end
local post_sync_pending = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 6/6', post_sync_pending))
assert(not contains_chat(dolo, 'preflight PASS', post_sync_pending))
render_all(30.1)
local post_sync_no_check = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'preflight not run', post_sync_no_check),
    'reapplied Genmei unexpectedly ran a diagnostic check')

-- A fresh audit reads the actual range slot, but a warning never blocks force.
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:3'] = {id=106,count=1}
local wrong_range_commands = command_count()
local wrong_range_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
for _, client in ipairs(clients) do
    for index = wrong_range_commands[client.player.name] + 1,
        #client.commands
    do
        local command = client.commands[index]
        assert(command == 'pc on' or command == 'pc off'
                or command == 'pc reconcile off',
            client.player.name
                ..' changed automation outside ordered-state repair')
    end
end
    assert(contains_chat(dolo,
        'equipment range expected Death Penalty found Compensator',
        wrong_range_chat))
    for _, client in ipairs(clients) do
        local revoked_preflight_status = #client.chats + 1
        fire(client, 'addon command', 'status')
        assert(not contains_chat(client, 'preflight PASS',
            revoked_preflight_status),
            client.player.name..' retained a revoked preflight pass')
    end
local warned_force_start = #dolo.commands + 1
fire(dolo, 'addon command', 'force')
assert(count_command(dolo, 'pc force', warned_force_start) == 1)
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:3'] = {id=102,count=1}
local repaired_range_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
assert(contains_chat(dolo, 'CHECK PASS 6/6', repaired_range_chat))

-- The v1 manual combat surface was removed rather than left as a second
-- immediate-cast owner beside the automatic state machine.
for _, removed in ipairs{
    'thunderproc','thunderprocrdm','laststand','savage','thundergeo',
} do
    local before = command_count()
    fire(dolo, 'addon command', removed)
    assert_counts_unchanged(before)
end

-- Kammavaca is independently discovered and compiled. Its required audit
-- transitions from ACK-ready/action-blocked to a real six-client pass after
-- the physical GearSwap state and every fight resource are observable. The
-- preferred RDM/WHM fixture remains sufficient; /BLM is optional recovery.
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:1'] = {id=110,count=1}
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:2'] = {id=112,count=1}
PREFLIGHT_FIXTURES.Dolomedes.equipment.range = 0
PREFLIGHT_FIXTURES.Kickpuncher.equipment = {
    main=1, main_bag=8, sub=2, sub_bag=8,
}
PREFLIGHT_FIXTURES.Kickpuncher.equipped = {
    ['8:1']={id=101,count=1}, ['8:2']={id=113,count=1},
}
local kammavaca_mobs = {
    {id=5100, name='Kammavaca', spawn_type=16,
        valid_target=true, hpp=100, distance=4, claim_id=9999,
        x=0, y=0, z=0},
    {id=5001, name="Kammavaca's Clionid", spawn_type=16,
        valid_target=true, hpp=60, distance=1, x=2, y=0, z=0},
    {id=5002, name="Kammavaca's Limule", spawn_type=16,
        valid_target=true, hpp=100, distance=5, x=3, y=0, z=0},
    {id=5003, name="Kammavaca's Murex", spawn_type=16,
        valid_target=true, hpp=100, distance=2, x=4, y=0, z=0},
    {id=5004, name="Kammavaca's Amoeban", spawn_type=16,
        valid_target=true, hpp=90, distance=0.5, x=5, y=0, z=0},
}
for _, client in ipairs(clients) do client.mobs = kammavaca_mobs end

fire(dolo, 'addon command', 'use', 'kamma')
local kammavaca_starts = command_count()
render_all(2.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc policy pt-ruaun-kammavaca',
        kammavaca_starts[client.player.name] + 1))
    assert(contains_command(client, 'aws2 exclude none',
        kammavaca_starts[client.player.name] + 1))
    assert(count_command(client, 'input /autotarget off',
        kammavaca_starts[client.player.name] + 1) == 1)
end
assert(not contains_command(smalls, 'gs c pstartrdm silence 5100',
    kammavaca_starts.Smalls + 1),
    'an outsider-claimed boss must not start encounter automation')

-- The context recognizes only p0-p5 claim IDs. Once Tackle owns the claim,
-- the runtime can begin its bounded opening sequence.
kammavaca_mobs[1].claim_id = tackle.player.id
render_all(0.3)
assert(count_command(smalls, 'gs c pstartrdm silence 5100',
    kammavaca_starts.Smalls + 1) == 1)
assert(contains_command(dolo,
    'r2 roll1 chaos; r2 roll2 samurai',
    kammavaca_starts.Dolomedes + 1))
assert(contains_command(dolo,
    'gs c weapons DualSavage; wait 1; aws2 aftermath off; '
        ..'aws2 use Savage Blade; aws2 tp 1000; aws2 hp 0 100; aws2 on',
    kammavaca_starts.Dolomedes + 1))
assert(not contains_command(dolo, 'DualLastStandRanged',
    kammavaca_starts.Dolomedes + 1))
assert(contains_command(tackle, 'gs c pstartpld manualsc Dolomedes',
    kammavaca_starts.Tackleberry + 1))
assert(contains_command(tackle, 'gs c weapons Naegling; wait 1; aws2 off',
    kammavaca_starts.Tackleberry + 1))
assert(not contains_command(tackle, 'aws2 on',
    kammavaca_starts.Tackleberry + 1))
assert(contains_command(kick, 'gs c pstartdnc physical Tackleberry',
    kammavaca_starts.Kickpuncher + 1))
assert(contains_command(kick,
    'gs c weapons Tauret; wait 1; aws2 aftermath off; '
        ..'aws2 use Evisceration; aws2 tp 1000; aws2 hp 0 100; aws2 on',
    kammavaca_starts.Kickpuncher + 1))
assert(contains_command(barney, 'gs c pstartbrd physical Tackleberry',
    kammavaca_starts.Barneystinson + 1))
assert(contains_command(smalls, 'gs c pstartrdm magicboss-protect Tackleberry',
    kammavaca_starts.Smalls + 1))
assert(contains_command(achoo, 'gs c pstartgeo leanrrmanaged',
    kammavaca_starts.Achoo + 1))
assert(contains_command(achoo,
    'gs c autoindi Fury; gs c autogeo Frailty; '
        ..'gs c autoentrust Fend; gs c autoentrustee Tackleberry;',
    kammavaca_starts.Achoo + 1))
assert(contains_command(achoo,
    'gs c unset AutoWSMode; gs c weapons Maxentius; wait 1; aws2 off',
    kammavaca_starts.Achoo + 1))

for index = kammavaca_starts.Barneystinson + 1, #barney.commands do
    local lower = barney.commands[index]:lower()
    assert(not lower:find('equip', 1, true))
    assert(not lower:find('range=', 1, true))
    assert(not lower:find('ammo=', 1, true))
    assert(not lower:find('gs c disable', 1, true))
    assert(not lower:find('gs c enable', 1, true))
end

local kammavaca_status_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'acks 6/6', kammavaca_status_start))
assert(contains_chat(dolo, 'preflight not run', kammavaca_status_start))
local emergency_kammavaca_sleep = #barney.commands + 1
local emergency_kammavaca_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'sleep')
assert(count_command(barney, 'gs c pstartbrd sleep',
    emergency_kammavaca_sleep) == 1)
assert(contains_chat(dolo, 'sleep accepted by Barneystinson through '
    ..'brd-pack-sleep', emergency_kammavaca_chat))
assert(not contains_chat(dolo, 'required preflight has not passed',
    emergency_kammavaca_chat))

local kammavaca_check_start = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
assert(contains_chat(dolo, 'CHECK PASS 6/6', kammavaca_check_start))
render_all(0.3)
local kammavaca_pass_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'preflight PASS', kammavaca_pass_status))
render_all(0.3)
assert(contains_command(dolo, 'pc forceid 5001',
    kammavaca_starts.Dolomedes + 1),
    'ready Kammavaca runtime did not automatically force the first CLMA add')

-- Manual Silence resolves the same party-claimed exact boss and delegates to
-- the RDM queue; PartyTactics never emits a raw spell command.
local silence_start = #smalls.commands + 1
fire(dolo, 'addon command', 'silence')
assert(count_command(smalls, 'gs c pstartrdm silence 5100',
    silence_start) == 1)
local foreign_silence_start = #smalls.commands + 1
kammavaca_mobs[1].claim_id = 9999
fire(dolo, 'addon command', 'silence')
assert(count_command(smalls, 'gs c pstartrdm silence 5100',
    foreign_silence_start) == 0)
kammavaca_mobs[1].claim_id = tackle.player.id
local pack_sleep_start = #barney.commands + 1
fire(dolo, 'addon command', 'sleep')
assert(count_command(barney, 'gs c pstartbrd sleep',
    pack_sleep_start) == 1)
assert(not contains_command(barney, 'equip', pack_sleep_start))
assert(not contains_command(barney, 'range=', pack_sleep_start))
assert(not contains_command(barney, 'ammo=', pack_sleep_start))

-- A gun appearing in Dolo's range slot revokes this profile's pass. Repairing
-- the empty-slot contract allows a fresh distributed check to pass again.
PREFLIGHT_FIXTURES.Dolomedes.equipment.range = 3
local wrong_kammavaca_range = command_count()
local wrong_kammavaca_chat = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
for _, client in ipairs(clients) do
    for index = wrong_kammavaca_range[client.player.name] + 1,
        #client.commands
    do
        local command = client.commands[index]
        assert(command == 'pc on' or command == 'pc off',
            client.player.name
                ..' changed automation outside ordered-state repair')
    end
end
assert(contains_chat(dolo,
    'equipment range expected empty found Death Penalty',
    wrong_kammavaca_chat))
local warned_kammavaca_force = #dolo.commands + 1
fire(dolo, 'addon command', 'force')
assert(count_command(dolo, 'pc force', warned_kammavaca_force) == 1)
PREFLIGHT_FIXTURES.Dolomedes.equipment.range = 0
local repaired_kammavaca_range = #dolo.chats + 1
fire(dolo, 'addon command', 'check')
assert(contains_chat(dolo, 'CHECK PASS 6/6',
    repaired_kammavaca_range))

-- Switching back proves Kammavaca neither changes Genmei's compiled plan nor
-- leaves its physical weapon assumptions in Genmei's required readiness path.
smalls.player.sub_job = 'WHM'
smalls.player.sub_job_id = 3
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:1'] = {id=100,count=1}
PREFLIGHT_FIXTURES.Dolomedes.equipped['8:2'] = {id=107,count=1}
PREFLIGHT_FIXTURES.Dolomedes.equipment.range = 3
local kammavaca_teardown_starts = command_count()
fire(dolo, 'addon command', 'use', 'genmei')
local returned_genmei_starts = command_count()
render_all(2.1)
assert(contains_command(dolo, 'pc policy pt-genbu-genmei',
    returned_genmei_starts.Dolomedes + 1))
assert(contains_command(dolo,
    'gs c weapons DeathPenalty; wait 1; aws2 off',
    returned_genmei_starts.Dolomedes + 1))
assert(contains_command(barney, 'gs c pstartbrd magicboss Tackleberry',
    returned_genmei_starts.Barneystinson + 1))
for _, client in ipairs(clients) do
    assert(count_command(client, 'input /autotarget on',
        kammavaca_teardown_starts[client.player.name] + 1) == 1,
        client.player.name..' did not restore auto-target exactly once')
end
local returned_genmei_status = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'preflight not run', returned_genmei_status))

-- A pinned adapter may receive a distinct exact add/mechanic subject without
-- transferring the signed encounter authority to that subject. The original
-- four-argument runtime call keeps its GearSwap bytes unchanged; a subject is
-- appended after the optional request-token position. Both IDs are validated
-- again by the receiving client before it issues the local host command.
local genbu_mob = {
    id=5200, index=320, name='Genbu', spawn_type=16,
    valid_target=true, hpp=100, distance=4, claim_id=tackle.player.id,
    x=0, y=0, z=0,
}
for _, client in ipairs(clients) do client.mobs = {genbu_mob} end
fire(dolo, 'addon command', 'arm')
local genbu_ipc_start = #dolo.ipc_messages + 1
local genbu_achoo_start = #achoo.commands + 1
render_all(0.3)
render_all(7.0)
local controller_message
for index = genbu_ipc_start, #dolo.ipc_messages do
    local message = dolo.ipc_messages[index]
    if message:find('|runtime-controller|', 1, true)
        and message:find('|Achoo|genmei|setup|5200', 1, true)
    then
        controller_message = message
        break
    end
end
assert(controller_message, 'leader did not issue the signed setup request')
local controller_fields = {}
for field in controller_message:gmatch('[^|]+') do
    controller_fields[#controller_fields + 1] = field
end
assert(#controller_fields == 13,
    'legacy no-token/no-subject IPC bytes unexpectedly changed')
local legacy_host_command = ('gs c ptgs action genmei setup 5200 %s %s')
    :format(controller_fields[3], controller_fields[8])
assert(first_command_index(achoo, legacy_host_command, genbu_achoo_start),
    'legacy four-argument runtime request changed its GearSwap bytes')

local subject_host_command = legacy_host_command..' - 5003'
local subject_start = #achoo.commands + 1
broadcast(controller_message..'|-|5003', dolo)
assert(first_command_index(achoo, subject_host_command, subject_start),
    'validated secondary subject did not reach the pinned adapter')

local invalid_subject_start = #achoo.commands + 1
broadcast(controller_message..'|-|0', dolo)
assert(not first_command_index(achoo,
    legacy_host_command..' - 0', invalid_subject_start),
    'receiver accepted a non-uint32 secondary subject')

local wrong_authority = controller_message:gsub('|setup|5200$', '|setup|5201')
local wrong_authority_start = #achoo.commands + 1
broadcast(wrong_authority..'|-|5003', dolo)
assert(not first_command_index(achoo,
    ('gs c ptgs action genmei setup 5201 %s %s - 5003')
        :format(controller_fields[3], controller_fields[8]),
    wrong_authority_start),
    'secondary target support weakened the encounter authority check')

-- Adapter status fast paths use a separate authenticated relay.  The local
-- hidden command derives its source identity from the live client and accepts
-- only the current capability, exact encounter life, declared adapter action,
-- exact party subject, and a bounded request token before emitting IPC.
local status_ipc_start = #achoo.ipc_messages + 1
fire(achoo, 'addon command', '__adapter_status', 'genmei',
    controller_fields[3], controller_fields[8], 'setup',
    '5200', '320', '1002', '1002', 'relay_setup_1')
local status_message = achoo.ipc_messages[status_ipc_start]
assert(status_message
    and status_message:find('|adapter-status|', 1, true)
    and status_message:find('|Achoo|1006|1006|genmei|setup|5200|320|'
        ..'1002|1002|relay_setup_1$', 1) ~= nil,
    'authenticated adapter status proof was not relayed')
local status_fields = {}
for field in status_message:gmatch('[^|]+') do
    status_fields[#status_fields + 1] = field
end
assert(#status_fields == 18,
    'adapter status proof did not preserve its fixed 18-field protocol')

for _, invalid in ipairs({
    {'stale generation', '1-1-1', controller_fields[8], 'setup',
        '5200', '320', '1002', '1002', 'relay_setup_2'},
    {'undeclared action', controller_fields[3], controller_fields[8],
        'not-declared', '5200', '320', '1002', '1002', 'relay_setup_3'},
    {'wrong encounter index', controller_fields[3], controller_fields[8],
        'setup', '5200', '321', '1002', '1002', 'relay_setup_4'},
    {'wrong subject index', controller_fields[3], controller_fields[8],
        'setup', '5200', '320', '1002', '1003', 'relay_setup_5'},
}) do
    local before = #achoo.ipc_messages
    fire(achoo, 'addon command', '__adapter_status', 'genmei',
        invalid[2], invalid[3], invalid[4], invalid[5], invalid[6],
        invalid[7], invalid[8], invalid[9])
    assert(#achoo.ipc_messages == before,
        invalid[1]..' emitted an adapter status proof')
end

-- Replaying a valid network packet is harmless.  The leader's exact proof-key
-- ledger consumes it at most once, and no runtime/fault surface is reopened.
local replay_commands = command_count()
broadcast(status_message, achoo)
assert_counts_unchanged(replay_commands)

-- A callback exception quarantines only that callback method. In particular,
-- one bad action packet must not disable ticks, status delivery, deactivation,
-- manual controls, or any peer.
local action_event = assert(dolo.callbacks.action
    and dolo.callbacks.action[1], 'core action callback was not registered')
local runtime_dispatch = assert(named_upvalue(action_event, 'invoke_runtime'),
    'could not inspect the core runtime dispatcher')
local runtime_record = assert(named_upvalue(runtime_dispatch, 'active'),
    'could not inspect the active runtime record')
assert(runtime_record.runtime, 'Genmei runtime is not active for fault isolation')
local saved_action = runtime_record.runtime.on_action
local saved_tick = runtime_record.runtime.on_tick
local saved_status = runtime_record.runtime.on_status
local saved_deactivate = runtime_record.runtime.on_deactivate
local action_attempts, tick_calls, status_calls, deactivate_calls = 0, 0, 0, 0
runtime_record.runtime.on_action = function()
    action_attempts = action_attempts + 1
    error('intentional on_action isolation test')
end
runtime_record.runtime.on_tick = function()
    tick_calls = tick_calls + 1
end
runtime_record.runtime.on_status = function()
    status_calls = status_calls + 1
end
runtime_record.runtime.on_deactivate = function(self, context)
    deactivate_calls = deactivate_calls + 1
    if saved_deactivate then return saved_deactivate(self, context) end
end

local fault_chat_start = #dolo.chats + 1
fire(dolo, 'action', {})
fire(dolo, 'action', {})
assert(action_attempts == 1,
    'the failed on_action callback was invoked again')
assert(contains_chat(dolo, 'Profile callback paused locally after on_action',
    fault_chat_start), 'on_action callback failure was not reported')
local peer_fault_chat_start = #smalls.chats + 1
fire(dolo, 'prerender')
assert(tick_calls == 1,
    'an on_action exception disabled the independent on_tick callback')
assert(not contains_chat(smalls, 'intentional on_action isolation test',
    peer_fault_chat_start), 'a local callback exception leaked to a peer')

fire(achoo, 'addon command', '__adapter_status', 'genmei',
    controller_fields[3], controller_fields[8], 'setup',
    '5200', '320', '1002', '1002', 'relay_setup_fault_isolation')
assert(status_calls == 1,
    'an on_action exception disabled the independent on_status callback')

-- Profile replacement still deactivates the runtime after a callback fault,
-- and the replacement receives a fresh per-method failure ledger.
runtime_record.runtime.on_action = saved_action
runtime_record.runtime.on_tick = saved_tick
runtime_record.runtime.on_status = saved_status
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
assert(deactivate_calls == 1,
    'an on_action exception prevented runtime deactivation')

-- Exact hostile targets may bootstrap the persistent Sortie owner only while
-- PartyTactics is inactive. They can never replace or alter an active profile.
for _, client in ipairs(clients) do client.zone = 275 end
local skomora = {id=7001,index=1701,name='Skomora',spawn_type=16,
    valid_target=true,hpp=100,claim_id=0,distance=4}
dolo.mobs.skomora = skomora
local auto_select = assert(named_upvalue(action_event, 'auto_select_profile'),
    'could not inspect exact-target selector')
local target_probe = assert(named_upvalue(auto_select, 'automatic_target'),
    'could not inspect automatic target parser')
local auto_targets = assert(named_upvalue(target_probe, 'auto_profile_targets'),
    'could not inspect automatic target catalog')
assert(auto_targets[275]
    and auto_targets[275].skomora == 'sortie-main-v1',
    'Skomora was not registered to the persistent Sortie owner')
local auto_starts = command_count()
local auto_chat_start = #dolo.chats + 1
fire(dolo, 'action', {
    actor_id=tackle.player.id, category=1,
    targets={{id=skomora.id,actions={{message=1,param=500}}}},
})
render_all(2.1)
assert(not contains_chat(dolo,
    'AUTO sortie-main-v1: Skomora engaged', auto_chat_start),
    'exact target replaced an unrelated active profile')
for _, client in ipairs(clients) do
    local first = auto_starts[client.player.name] + 1
    assert(not contains_command(client, 'pc policy pt-sortie-main', first),
        client.player.name..' let target selection cross a profile boundary')
end
auto_chat_start = #dolo.chats + 1
fire(dolo, 'addon command', 'status')
assert(contains_chat(dolo, 'Active locus-dire-bats-tomb',
    auto_chat_start), 'target selection changed the active profile')

-- An explicit profile command is the only legal boundary transition.
auto_starts = command_count()
fire(dolo, 'addon command', 'sortie-boss-skomora-v1')
render_all(2.1)
for _, client in ipairs(clients) do
    local first = auto_starts[client.player.name] + 1
    assert(contains_command(client, 'pc policy pt-sortie-skomora', first),
        client.player.name..' did not receive the explicit profile')
    assert(contains_command(client, 'pc on', first),
        client.player.name..' did not arm the explicit profile')
end
assert(contains_command(smalls, 'gs c pstartrdm transition',
    auto_starts.Smalls + 1),
    'RDM profile transition discarded its valid remote-buff timers')
local duplicate_starts = command_count()
fire(dolo, 'action', {
    actor_id=kick.player.id, category=3, param=25,
    targets={{id=skomora.id,actions={{message=1,param=5000}}}},
})
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc policy pt-sortie-skomora',
        duplicate_starts[client.player.name] + 1),
        'same exact target reloaded the already-active profile')
end

-- `pt off` is a terminal fence for every exact generation already known to
-- the caller, including an undecided CLI reapply. Deliver the stop to Barney
-- before his delayed prepare and commit: neither reordered packet may revive
-- the profile. A later explicit load remains valid, and a stale stop naming
-- only the retired generations cannot kill that newer active generation.
held_ipc = {}
hold_ipc = function(message, sender, recipient)
    return sender == dolo and recipient == barney
        and message:find('PARTYTACTICS1|prepare|', 1, true) == 1
end
fire(dolo, 'addon command', 'reapply')
hold_ipc = nil
assert(#held_ipc == 1, 'test did not isolate Barney\'s reapply prepare')
local delayed_prepare = held_ipc[1].message
local prepare_fields = split_fields(delayed_prepare)
local cancelled_generation = prepare_fields[3]
assert(cancelled_generation and prepare_fields[5] == 'sortie-boss-skomora-v1')

local stop_ipc_start = #dolo.ipc_messages + 1
local terminal_starts = command_count()
fire(dolo, 'addon command', 'off')
local terminal_stop
for index = stop_ipc_start, #dolo.ipc_messages do
    local message = dolo.ipc_messages[index]
    if message:find('PARTYTACTICS1|stop|', 1, true) == 1 then
        local fields = split_fields(message)
        if fields[10] == cancelled_generation then
            terminal_stop = message
            break
        end
    end
end
assert(terminal_stop, 'off omitted the undecided reapply generation')
local stop_fields = split_fields(terminal_stop)
assert(stop_fields[10] == cancelled_generation)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc invalidate partytactics',
        terminal_starts[client.player.name] + 1),
        client.player.name..' did not stop the old active generation')
end

local delayed_vote_start = #barney.ipc_messages + 1
local delayed_apply_start = #barney.commands + 1
fire(barney, 'ipc message', delayed_prepare)
assert(find_ipc(barney,
    'PARTYTACTICS1|vote|'..cancelled_generation,
    delayed_vote_start) == nil,
    'stop-before-prepare did not preserve the exact tombstone')
local delayed_commit = table.concat({
    'PARTYTACTICS1', 'commit', cancelled_generation,
    prepare_fields[4], prepare_fields[5], prepare_fields[6],
    prepare_fields[7], prepare_fields[8], prepare_fields[9],
    '0', prepare_fields[11],
}, '|')
fire(barney, 'ipc message', delayed_commit)
render_all(2.1)
assert(not contains_command(barney, 'pc policy pt-sortie-skomora',
    delayed_apply_start),
    'delayed commit resurrected a generation cancelled by pt off')
for _, client in ipairs(clients) do
    local chat_start = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client, 'Inactive', chat_start),
        client.player.name..' remained active after exact terminal stop')
end

local fresh_starts = command_count()
local fresh_ipc_start = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'use', 'sortie-boss-skomora-v1')
render_all(2.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc policy pt-sortie-skomora',
        fresh_starts[client.player.name] + 1),
        client.player.name..' rejected a fresh explicit post-stop load')
end
local fresh_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', fresh_ipc_start))
local fresh_fields = split_fields(fresh_commit)
local fresh_generation = fresh_fields[3]
stop_fields[3] = '1700000001-1001-999'
local stale_stop = table.concat(stop_fields, '|')
local stale_starts = command_count()
for _, client in ipairs(clients) do
    fire(client, 'ipc message', stale_stop)
end
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc invalidate partytactics',
        stale_starts[client.player.name] + 1),
        'stale exact stop killed a newer active generation on '
            ..client.player.name)
    local chat_start = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client, 'Active sortie-boss-skomora-v1', chat_start),
        client.player.name..' lost the newer post-stop generation')
end

-- Also stop a replacement after its commit packet has created a delayed local
-- apply. Fire the exact pending stop first, advance the transition timer, and
-- deliver the predecessor stop afterward. The cancelled pending record must
-- be cleared independently and apply_pending_commit must defend the tombstone.
local pending_ipc_start = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'reapply')
local replacement_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', pending_ipc_start),
    'reapply did not reach the pending-commit phase')
local replacement_fields = split_fields(replacement_commit)
local replacement_generation = replacement_fields[3]
assert(replacement_generation ~= fresh_generation)
local barney_pending_start = #barney.commands + 1
local pending_stop = table.concat({
    'PARTYTACTICS1', 'stop', '1700000002-1001-997',
    replacement_fields[4], replacement_fields[5], replacement_fields[6],
    replacement_fields[7], 'Dolomedes', 'reordered pending stop',
    replacement_generation,
}, '|')
fire(barney, 'ipc message', pending_stop)
now = now + 2.1
fire(barney, 'prerender')
assert(not contains_command(barney, 'pc policy pt-sortie-skomora',
    barney_pending_start),
    'cancelled pending generation applied before predecessor stop arrived')
local predecessor_stop = table.concat({
    'PARTYTACTICS1', 'stop', '1700000002-1001-998',
    fresh_fields[4], fresh_fields[5], fresh_fields[6], fresh_fields[7],
    'Dolomedes', 'reordered predecessor stop', fresh_generation,
}, '|')
fire(barney, 'ipc message', predecessor_stop)
assert(not contains_command(barney, 'pc policy pt-sortie-skomora',
    barney_pending_start))

-- Retire the replacement on the remaining clients, then prove this second
-- terminal fence likewise does not poison an unrelated explicit load.
fire(dolo, 'addon command', 'off')
local post_pending_stop_starts = command_count()
fire(dolo, 'addon command', 'use', 'sortie-boss-skomora-v1')
render_all(2.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc policy pt-sortie-skomora',
        post_pending_stop_starts[client.player.name] + 1),
        client.player.name..' did not recover after pending-stop ordering test')
end

-- A job change pauses only that local client's fight callbacks.
local stop_starts = {}
for _, client in ipairs(clients) do stop_starts[client.player.name] = #client.commands + 1 end
fire(client_named('Smalls'), 'job change')
for _, client in ipairs(clients) do
    if client == smalls then
        assert(contains_command(client, 'pc localstop',
            stop_starts[client.player.name]))
        assert(not contains_command(client, 'pc off',
            stop_starts[client.player.name]))
    else
        assert(not contains_command(client, 'pc localstop',
            stop_starts[client.player.name]))
        assert(not contains_command(client, 'pc invalidate partytactics',
            stop_starts[client.player.name]))
    end
end

-- Unloading one active client tears down only that client. Peers keep their
-- profile and manual controls.
PREFLIGHT_FIXTURES.Dolomedes.equipment.range = 0
fire(dolo, 'addon command', 'use', 'kamma')
render_all(2.1)
local unload_starts = command_count()
fire(smalls, 'unload')
for _, client in ipairs(clients) do
    if client == smalls then
        assert(count_command(client, 'input /autotarget on',
            unload_starts[client.player.name] + 1) == 1)
        assert(contains_command(client, 'pc localinvalidate partytactics',
            unload_starts[client.player.name] + 1))
        assert(not contains_command(client, 'pc invalidate partytactics',
            unload_starts[client.player.name] + 1))
    else
        assert(not contains_command(client, 'input /autotarget on',
            unload_starts[client.player.name] + 1))
        assert(not contains_command(client, 'pc localinvalidate partytactics',
            unload_starts[client.player.name] + 1))
        assert(not contains_command(client, 'pc invalidate partytactics',
            unload_starts[client.player.name] + 1))
    end
end

-- Raw GearSwap logout durability is routed back through a generation-scoped
-- private PartyTactics callback because the stable host removes the adapter
-- immediately after its logout callback. A profile switch before the delayed
-- callback makes it a no-op; the exact still-current lifecycle receives a
-- local-only complete teardown after the compiler's older wait commands.
for _, client in ipairs(clients) do client.zone = 289 end
local old_terminal_ipc = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'use', 'genmei')
render_all(2.1)
local old_terminal_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', old_terminal_ipc))
local old_terminal_fields = split_fields(old_terminal_commit)
assert(old_terminal_fields[5] == 'escha-ruaun-genbu-genmei')
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
local switched_terminal_starts = command_count()
for _, client in ipairs(clients) do
    fire(client, 'addon command', '__controller_terminal', 'genmei',
        old_terminal_fields[3], old_terminal_fields[10], '1')
end
assert_counts_unchanged(switched_terminal_starts)

local exact_terminal_ipc = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'use', 'genmei')
render_all(2.1)
local exact_terminal_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', exact_terminal_ipc))
local exact_terminal_fields = split_fields(exact_terminal_commit)
local exact_terminal_starts = command_count()
for _, client in ipairs(clients) do
    fire(client, 'addon command', '__controller_terminal', 'genmei',
        exact_terminal_fields[3], exact_terminal_fields[10], '1')
end
for _, client in ipairs(clients) do
    assert(contains_command(client, 'pc localinvalidate partytactics',
        exact_terminal_starts[client.player.name] + 1),
        client.player.name..' did not receive scoped terminal teardown')
    assert(not contains_command(client, 'pc invalidate partytactics',
        exact_terminal_starts[client.player.name] + 1),
        client.player.name..' broadcast a local logout teardown')
    local status_start = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client, 'Inactive', status_start),
        client.player.name..' retained the terminal generation')
end

-- The Signet derivative opts into a commit-scoped controller authorization.
-- Every client must authorize the exact generation/profile/signature/roster
-- before the ordinary delayed probe is allowed to bind its local adapter and
-- standalone keepers.
for _, client in ipairs(clients) do client.zone = 190 end
tackle.controller_probe_enabled = false
local signet_starts = command_count()
local signet_ipc_start = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'use', 'locus-signet')
local signet_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', signet_ipc_start),
    'Signet derivative did not commit')
local signet_fields = split_fields(signet_commit)
assert(signet_fields[4] == '0.13.3')
assert(signet_fields[5] == 'locus-dire-bats-tomb-signet')
assert(signet_fields[6] == '1.8.1')

-- While the commit is still pending, drop its operator-state only for Smalls.
-- The next commit retry must carry the newer tuple into Smalls' pending record
-- so eventual activation cannot apply the original stale bit.
held_ipc = {}
hold_ipc = function(message, sender, recipient)
    return sender == dolo and recipient == smalls
        and message:find('PARTYTACTICS1|operator-state|', 1, true) == 1
end
fire(dolo, 'addon command', 'arm')
hold_ipc = nil
assert(#held_ipc == 1, 'did not drop pending-commit operator-state for Smalls')
signet_retry_start = #dolo.ipc_messages + 1
render_all(0.8)
signet_retry = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|'..signet_fields[3]..'|',
    signet_retry_start),
    'leader did not retry the pending Signet commit')
signet_retry_fields = split_fields(signet_retry)
assert(tonumber(signet_retry_fields[12]) > tonumber(signet_fields[12])
    and signet_retry_fields[13] == '1',
    'commit retry did not carry the newer ordered ON tuple')
smalls_carrier_callback = assert(smalls.callbacks['addon command'][1])
smalls_carrier_request = assert(named_upvalue(
    smalls_carrier_callback, 'request_operator_state'))
smalls_pending_carrier = assert(named_upvalue(
    smalls_carrier_request, 'pending_commit'))
assert(tostring(smalls_pending_carrier.operator_revision)
        == signet_retry_fields[12]
    and smalls_pending_carrier.operator_armed == true,
    'commit retry left Smalls pending with stale operator state')
signet_fields = signet_retry_fields
render_all(1.3)
for _, client in ipairs(clients) do
    local authorization = table.concat({
        'gs c ptgs action locus-signet authorize', signet_fields[3],
        signet_fields[10], '2', signet_fields[5], signet_fields[6],
        signet_fields[7], 'Dolomedes', signet_fields[9],
        signet_fields[12], signet_fields[13],
    }, ' ')
    local probe = table.concat({
        'wait 1; gs c ptgs action locus-signet probe', signet_fields[3],
        signet_fields[10], '2',
    }, ' ')
    local authorize_index = first_command_index(
        client, authorization, signet_starts[client.player.name] + 1)
    local probe_index = first_command_index(
        client, probe, signet_starts[client.player.name] + 1)
    assert(authorize_index,
        client.player.name..' did not receive exact successor authorization')
    assert(probe_index and authorize_index < probe_index,
        client.player.name..' probed before exact authorization')
end

-- Losing the one delayed controller callback used to strand this client with
-- an active PartyTactics profile but no bound SignetKeeper/LocusPuller. The
-- lifecycle repair refreshes exact authorization and retries the idempotent
-- probe; controller-ready then delivers the already-recorded Ctrl-P ON tuple.
assert(not contains_command(tackle,
    'gs c ptgs action locus-signet operator ',
    signet_starts.Tackleberry + 1),
    'Tackle received operator state without controller readiness')
;(function()
local tackle_callback = assert(tackle.callbacks['addon command'][1])
local tackle_request = assert(named_upvalue(tackle_callback,
    'request_operator_state'))
local tackle_record = assert(named_upvalue(tackle_request, 'active'))
for _ = 1, 20 do
    if (tackle_record.controller_probe_attempts or 0) >= 10 then break end
    render_all(2.1)
end
assert((tackle_record.controller_probe_attempts or 0) >= 10,
    'test did not reach slow controller-proof repair')
render_all(12.1)
assert(contains_chat(tackle, 'Low-rate retries continue.'),
    'slow proof repair omitted its one actionable warning')
local tackle_probe_repair_start = #tackle.commands + 1
tackle.controller_probe_enabled = true
render_all(12.1)
assert(contains_command(tackle,
    'gs c ptgs activate locus-dire-bats-tomb-signet 1.8.1',
    tackle_probe_repair_start),
    'lost lifecycle controller callback did not reassert pinned activation')
assert(contains_command(tackle,
    'gs c ptgs action locus-signet authorize '..signet_fields[3],
    tackle_probe_repair_start),
    'lost lifecycle controller callback did not refresh authorization')
assert(contains_command(tackle,
    'gs c ptgs action locus-signet probe '..signet_fields[3],
    tackle_probe_repair_start),
    'lost lifecycle controller callback did not retry the exact probe')
assert(contains_command(tackle,
    'gs c ptgs action locus-signet operator '..signet_fields[3],
    tackle_probe_repair_start),
    'controller repair did not deliver captured Ctrl-P ON to Tackle')
assert(not contains_command(tackle, 'pc on', tackle_probe_repair_start),
    'controller repair emitted a noisy raw PartyCombat ON')
assert(tackle_record.controller_probe_attempts == 0,
    'late successful controller proof did not reset slow retry state')
end)()

-- A member's delayed ON request cannot overtake that same member's newer OFF.
-- The leader is the sole revision allocator, and the sender-side sequence is
-- checked before a request is serialized into authoritative state.
held_ipc = {}
hold_ipc = function(message, sender, recipient)
    return sender == barney and recipient == dolo
        and message:find('PARTYTACTICS1|operator-request|', 1, true) == 1
        and message:sub(-2) == '|1'
end
fire(barney, 'addon command', 'arm')
hold_ipc = nil
assert(#held_ipc == 1, 'did not isolate delayed member ON request')
fire(barney, 'addon command', 'disarm')
stale_request_ipc_count = #dolo.ipc_messages
fire(dolo, 'ipc message', held_ipc[1].message)
assert(#dolo.ipc_messages == stale_request_ipc_count,
    'stale lower-sequence ON created a new authoritative revision')
for _, client in ipairs(clients) do
    stale_request_status = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client, 'combat unarmed', stale_request_status),
        client.player.name..' accepted delayed ON after newer OFF')
end

-- Delivery may also reorder leader broadcasts. Smalls receives revision N+1
-- OFF before held revision N ON; the held state must be a no-op locally.
held_ipc = {}
hold_ipc = function(message, sender, recipient)
    return sender == dolo and recipient == smalls
        and message:find('PARTYTACTICS1|operator-state|', 1, true) == 1
        and message:sub(-2) == '|1'
end
fire(dolo, 'addon command', 'arm')
hold_ipc = nil
assert(#held_ipc == 1, 'did not isolate delayed leader ON state')
fire(dolo, 'addon command', 'disarm')
smalls_stale_state_commands = #smalls.commands
fire(smalls, 'ipc message', held_ipc[1].message)
assert(#smalls.commands == smalls_stale_state_commands,
    'lower-revision leader ON reached the adapter after newer OFF')
smalls_stale_state_status = #smalls.chats + 1
fire(smalls, 'addon command', 'status')
assert(contains_chat(smalls, 'combat unarmed', smalls_stale_state_status),
    'lower-revision leader state changed Smalls operator bit')

-- If one authoritative operator-state packet is dropped, the leader's next
-- full 15-field periodic state repairs that peer's local side effect without
-- allocating a transition. An equal revision with the opposite bit is still
-- rejected as a conflict and cannot trigger any adapter command.
held_ipc = {}
hold_ipc = function(message, sender, recipient)
    return sender == dolo and recipient == smalls
        and message:find('PARTYTACTICS1|operator-state|', 1, true) == 1
        and message:sub(-2) == '|1'
end
fire(dolo, 'addon command', 'arm')
hold_ipc = nil
assert(#held_ipc == 1, 'did not drop leader ON state for periodic repair')
repair_callback = assert(dolo.callbacks['addon command'][1])
repair_request = assert(named_upvalue(repair_callback, 'request_operator_state'))
repair_active = assert(named_upvalue(repair_request, 'active'))
repair_revision = tostring(repair_active.operator_revision)
repair_epoch = tostring(repair_active.apply_epoch)
smalls_repair_start = #smalls.commands + 1
periodic_on_raw_starts = command_count()
render_all(5.1)
assert_no_raw_partycombat(periodic_on_raw_starts,
    'ON/OFF from periodic repair')
assert(contains_command(smalls,
    'gs c ptgs action locus-signet operator '..signet_fields[3]
        ..' '..repair_epoch..' 2 '..repair_revision..' 1',
    smalls_repair_start),
    'periodic state did not repair Smalls after dropped operator-state')
smalls_conflict_start = #smalls.commands
equal_conflict = table.concat({
    'PARTYTACTICS1', 'operator-state', signet_fields[3], '0.13.3',
    'locus-dire-bats-tomb-signet', '1.8.1', signet_fields[7],
    repair_epoch, 'Dolomedes', repair_revision, '0',
}, '|')
fire(smalls, 'ipc message', equal_conflict)
assert(#smalls.commands == smalls_conflict_start,
    'equal-revision conflicting OFF triggered a local side effect')
smalls_conflict_status = #smalls.chats + 1
fire(smalls, 'addon command', 'status')
assert(contains_chat(smalls, 'combat armed', smalls_conflict_status),
    'equal-revision conflicting OFF changed Smalls operator bit')
explicit_disarm_starts = command_count()
fire(dolo, 'addon command', 'disarm')
assert_silent_ordered_off(explicit_disarm_starts)
periodic_off_raw_starts = command_count()
render_all(5.1)
assert_silent_periodic_off(periodic_off_raw_starts)

-- Ctrl-P is globally bound to `pt force`, but this profile's protocol-2
-- lifecycle owns both the effective ON edge and automatic bat acquisition.
-- No target is required to enable LocusPuller. Even with a selected enemy,
-- core must submit only the ordered ON request; a trailing raw force could
-- bypass a live Signet maintenance suspension.
signet_force_starts = command_count()
assert(dolo.current_target == nil)
fire(dolo, 'addon command', 'force')
for _, client in ipairs(clients) do
    assert(contains_command(client,
        'gs c ptgs action locus-signet operator ',
        signet_force_starts[client.player.name] + 1),
        client.player.name..' did not receive the ordered protocol-2 ON')
    assert(not contains_command(client, 'pc force',
        signet_force_starts[client.player.name] + 1),
        client.player.name
            ..' required a target for protocol-2 automatic pulling')
end
fire(dolo, 'addon command', 'disarm')

selected_signet_force_starts = command_count()
dolo.current_target = {id=99001, index=901, name='Locus Dire Bat', hpp=100,
    spawn_type=16, claim_id=dolo.player.id, distance=25}
fire(dolo, 'addon command', 'force')
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc force',
        selected_signet_force_starts[client.player.name] + 1),
        client.player.name
            ..' let protocol-2 force bypass automatic pull ownership')
end
dolo.current_target = nil
fire(dolo, 'addon command', 'disarm')

-- A same-generation GearSwap-affecting reapply keeps a Ctrl-P-compatible
-- `force` request as operator intent data, but cannot make PartyCombat
-- effective before the replacement epoch's exact lifecycle controller proof.
-- This is the same ordering used by zone reapply, and protocol 2 must not emit
-- a trailing raw force that bypasses the controller/census barrier.
signet_operator_revision, signet_operator_bit = nil, nil
do
    for _, client in ipairs(clients) do
        client.controller_probe_enabled = false
        fire(client, 'gain buff', 269)
    end
    local reapply_force_starts = command_count()
    fire(dolo, 'addon command', 'force')
    render_all(3.1)
    for _, client in ipairs(clients) do
        assert(not contains_command(client, 'pc on',
            reapply_force_starts[client.player.name] + 1),
            client.player.name..' armed before same-generation reapply proof')
        assert(not contains_command(client, 'pc force',
            reapply_force_starts[client.player.name] + 1),
            client.player.name..' bypassed protocol-2 reapply proof with force')
    end
    local callback = assert(dolo.callbacks['addon command'][1])
    local operator_request = assert(named_upvalue(
        callback, 'request_operator_state'))
    local current = assert(named_upvalue(operator_request, 'active'))
    local epoch = tostring(current.apply_epoch)
    signet_operator_revision = tostring(current.operator_revision)
    signet_operator_bit = current.operator_armed and '1' or '0'
    carrier_process = assert(named_upvalue(
        operator_request, 'process_operator_request'))
    carrier_carry = assert(named_upvalue(
        carrier_process, 'carry_operator_snapshot'))
    carrier_sessions = assert(named_upvalue(carrier_carry, 'sessions'))
    carrier_session = assert(carrier_sessions[current.nonce])
    assert(tostring(carrier_session.operator_revision)
            == signet_operator_revision
        and (carrier_session.operator_armed and '1' or '0')
            == signet_operator_bit,
        'active session carrier retained stale operator state during reapply')
    signet_fields[10] = epoch
    for _, client in ipairs(clients) do
        local ready_start = #client.commands + 1
        fire(client, 'addon command', '__controller_ready', 'locus-signet',
            signet_fields[3], epoch, '2')
        assert(contains_command(client,
            'gs c ptgs action locus-signet operator '..signet_fields[3]
                ..' '..epoch..' 2 '..signet_operator_revision..' '
                ..signet_operator_bit,
            ready_start), client.player.name
                ..' did not receive ordered state after exact reapply proof')
        client.controller_probe_enabled = true
    end
end

-- An operator //pt reapply is not a GearSwap reload. It creates a fresh
-- generation, so every client must terminally fence the predecessor before
-- authorizing/probing that successor. Otherwise the retained same-version
-- adapter rejects the new generation and Signet/Jubilee/Puller remain bound
-- to (or later retire) the wrong lifecycle.
(function()
    local old_generation = signet_fields[3]
    local old_epoch = signet_fields[10]
    local callback = assert(dolo.callbacks['addon command'][1])
    local operator_request = assert(named_upvalue(callback,
        'request_operator_state'))
    local parent = assert(named_upvalue(operator_request, 'active'))
    local revision = tostring(parent.operator_revision)
    local bit = parent.operator_armed and '1' or '0'
    local starts = command_count()
    local ipc_start = #dolo.ipc_messages + 1
    fire(dolo, 'addon command', 'reapply')
    local successor_commit = assert(find_ipc(dolo,
        'PARTYTACTICS1|commit|', ipc_start),
        'explicit Signet reapply did not commit')
    local successor = split_fields(successor_commit)
    assert(successor[3] ~= old_generation and successor[10] == '0'
        and successor[12] == revision and successor[13] == bit
        and successor[14] == '1',
        'explicit reapply did not carry terminal mode and operator high-water')
    render_all(2.1)
    for _, client in ipairs(clients) do
        local first = starts[client.player.name] + 1
        local function first_containing(fragment)
            for index = first, #client.commands do
                if client.commands[index]:find(fragment, 1, true) then
                    return index
                end
            end
        end
        local fence = first_containing('sk stoppt '..old_generation)
        local authorize = first_containing(
            'gs c ptgs action locus-signet authorize '..successor[3])
        local probe = first_containing(
            'gs c ptgs action locus-signet probe '..successor[3])
        assert(fence and authorize and probe and fence < authorize
            and authorize < probe,
            client.player.name..' did not fence old Signet before new proof')
        assert(not contains_command(client,
            'sk stoppt '..successor[3], first),
            client.player.name..' retired the fresh reapply generation')
        local status_start = #client.chats + 1
        fire(client, 'addon command', 'status')
        assert(contains_chat(client,
            'generation '..successor[3], status_start),
            client.player.name..' did not apply the fresh generation')
    end
    assert(contains_command(dolo, 'jk stoppt '..old_generation,
        starts.Dolomedes + 1),
        'leader did not retire predecessor Jubilee authority')
    assert(contains_command(tackle, 'lp retirept '..old_generation,
        starts.Tackleberry + 1),
        'Tackle did not retire predecessor first-hit authority')

    -- A previous lost stop can leave one peer on a different Signet nonce.
    -- Dolo's clean off only names generations he knows; the next explicit
    -- load must fence that peer's retained predecessor locally before it
    -- probes the newly committed generation.
    held_ipc = {}
    hold_ipc = function(message, sender, recipient)
        return sender == dolo and recipient == smalls
            and message:find('PARTYTACTICS1|stop|', 1, true) == 1
    end
    fire(dolo, 'addon command', 'off')
    hold_ipc = nil
    assert(#held_ipc >= 1, 'test did not isolate Smalls from stop IPC')
    local retained_status = #smalls.chats + 1
    fire(smalls, 'addon command', 'status')
    assert(contains_chat(smalls, 'generation '..successor[3],
        retained_status), 'test peer did not retain its old Signet generation')
    local split_starts = command_count()
    local split_ipc_start = #dolo.ipc_messages + 1
    fire(dolo, 'addon command', 'use', 'locus-signet')
    local clean_commit = assert(find_ipc(dolo,
        'PARTYTACTICS1|commit|', split_ipc_start))
    local clean = split_fields(clean_commit)
    assert(clean[3] ~= successor[3] and clean[14] == '1',
        'fresh explicit load did not mark terminal predecessor replacement')
    render_all(2.1)
    local first = split_starts.Smalls + 1
    local stop_index, authorize_index
    for index = first, #smalls.commands do
        local command = smalls.commands[index]
        if not stop_index and command:find('sk stoppt '..successor[3],
            1, true) then stop_index = index end
        if not authorize_index and command:find(
            'gs c ptgs action locus-signet authorize '..clean[3],
            1, true) then authorize_index = index end
    end
    assert(stop_index and authorize_index and stop_index < authorize_index,
        'split-brain peer did not fence old Signet before fresh authorization')
    for _, packet in ipairs(held_ipc) do
        fire(smalls, 'ipc message', packet.message)
    end
    local clean_status = #smalls.chats + 1
    fire(smalls, 'addon command', 'status')
    assert(contains_chat(smalls, 'generation '..clean[3], clean_status),
        'delayed predecessor stop killed the fresh Signet generation')
    signet_fields = clean
    signet_operator_revision, signet_operator_bit = clean[12], clean[13]
end)()

-- Private lifecycle callbacks are fixed-shape local protocols too. Extra
-- tokens cannot overwrite readiness, retire the active generation, or begin
-- a recovery successor.
do
    local proof = {}
    proof.callback = assert(dolo.callbacks['addon command'][1])
    proof.request = assert(named_upvalue(
        proof.callback, 'request_operator_state'))
    proof.active = assert(named_upvalue(proof.request, 'active'))
    proof.ready = proof.active.controller_ready
    fire(dolo, 'addon command', '__controller_ready', 'locus-signet',
        signet_fields[3], signet_fields[10], '2', 'surplus')
    assert(proof.active.controller_ready == proof.ready)
    fire(dolo, 'addon command', '__controller_lost', 'locus-signet',
        signet_fields[3], signet_fields[10], '2', 'surplus')
    assert(proof.active.controller_ready == proof.ready)
    fire(dolo, 'addon command', '__controller_terminal', 'locus-signet',
        signet_fields[3], signet_fields[10], '2', 'surplus')
    local status_start = #dolo.chats + 1
    fire(dolo, 'addon command', 'status')
    assert(contains_chat(dolo, 'Active locus-dire-bats-tomb-signet',
        status_start), 'surplus terminal callback stopped the profile')
    proof.ipc_count = #dolo.ipc_messages
    fire(dolo, 'addon command', '__recover_controller', 'locus-signet',
        signet_fields[3], signet_fields[10], '2', signet_fields[5],
        signet_fields[6], signet_fields[4], signet_fields[7], 'Dolomedes',
        signet_fields[9], signet_operator_revision, signet_operator_bit,
        'surplus')
    assert(#dolo.ipc_messages == proof.ipc_count,
        'surplus recovery callback created a successor')
end

-- Recovery snapshots the current operator bit, but that snapshot is never a
-- delayed command. Alt-P during the successor's pending-commit window updates
-- the exact successor record, so the old armed bit in the commit packet cannot
-- turn PartyCombat back on when the transition timer fires.
fire(dolo, 'addon command', 'arm')
recovery_callback = assert(dolo.callbacks['addon command'][1])
recovery_request = assert(named_upvalue(
    recovery_callback, 'request_operator_state'))
recovery_parent = assert(named_upvalue(recovery_request, 'active'))
local recovery_starts = command_count()
local recovery_ipc_start = #dolo.ipc_messages + 1
fire(dolo, 'addon command', '__recover_controller', 'locus-signet',
    signet_fields[3], signet_fields[10], '2', signet_fields[5],
    signet_fields[6], signet_fields[4], signet_fields[7], 'Dolomedes',
    signet_fields[9], tostring(recovery_parent.operator_revision),
    recovery_parent.operator_armed and '1' or '0')
local recovery_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', recovery_ipc_start),
    'exact controller recovery did not create a successor')
local recovery_fields = split_fields(recovery_commit)
assert(recovery_fields[3] ~= signet_fields[3])
assert(recovery_fields[10] == '0' and recovery_fields[11] == '1'
    and recovery_fields[12] == tostring(recovery_parent.operator_revision)
    and recovery_fields[13] == '1',
    'recovery did not carry the ordered armed parent state')
fire(dolo, 'addon command', 'disarm')
render_all(2.1)
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc on',
        recovery_starts[client.player.name] + 1),
        client.player.name..' restored a stale armed bit after Alt-P')
    assert(not contains_command(client,
        'sk stoppt '..signet_fields[3],
        recovery_starts[client.player.name] + 1),
        client.player.name..' fenced the predecessor during same-profile recovery')
    local status_start = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client,
        'Active locus-dire-bats-tomb-signet', status_start)
        and contains_chat(client, 'combat unarmed', status_start),
        client.player.name..' did not apply the disarmed successor')
end
assert(not contains_command(dolo,
    'jk stoppt '..signet_fields[3], recovery_starts.Dolomedes + 1),
    'same-profile recovery destroyed JubileeKeeper continuity')
assert(not contains_command(tackle,
    'lp retirept '..signet_fields[3], recovery_starts.Tackleberry + 1),
    'same-profile recovery retired the bound puller before successor authorization')

-- A second armed recovery proves the effective PC lane waits for each local
-- lifecycle controller. One client may become ready and arm; an Alt-P before
-- the other delayed probes arrive changes the desired successor bit, so none
-- of those late readiness callbacks can restore the stale ON state.
do
fire(dolo, 'addon command', 'arm')
gated_parent = assert(named_upvalue(recovery_request, 'active'))
for _, client in ipairs(clients) do
    client.controller_probe_enabled = false
end
local gated_recovery_starts = command_count()
local gated_recovery_ipc = #dolo.ipc_messages + 1
fire(dolo, 'addon command', '__recover_controller', 'locus-signet',
    recovery_fields[3], recovery_fields[10], '2', recovery_fields[5],
    recovery_fields[6], recovery_fields[4], recovery_fields[7], 'Dolomedes',
    recovery_fields[9], tostring(gated_parent.operator_revision),
    gated_parent.operator_armed and '1' or '0')
local gated_recovery_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', gated_recovery_ipc))
local gated_recovery_fields = split_fields(gated_recovery_commit)
render_all(2.1)
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc on',
        gated_recovery_starts[client.player.name] + 1),
        client.player.name..' armed before its lifecycle controller was ready')
end
local barney_ready_start = #barney.commands + 1
fire(barney, 'addon command', '__controller_ready', 'locus-signet',
    gated_recovery_fields[3], gated_recovery_fields[10], '2')
assert(contains_command(barney,
    'gs c ptgs action locus-signet operator '..gated_recovery_fields[3]
        ..' '..gated_recovery_fields[10]..' 2 '
        ..gated_recovery_fields[12]..' '..gated_recovery_fields[13],
    barney_ready_start),
    'a proven recovery did not receive its ordered operator state')
fire(dolo, 'addon command', 'disarm')
local late_ready_starts = command_count()
for _, client in ipairs(clients) do
    if client ~= barney then
        fire(client, 'addon command', '__controller_ready', 'locus-signet',
            gated_recovery_fields[3], gated_recovery_fields[10], '2')
    end
    client.controller_probe_enabled = true
end
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc on',
        late_ready_starts[client.player.name] + 1),
        client.player.name..' restored a stale armed bit after delayed probe')
end
recovery_fields = gated_recovery_fields
end

-- Exact stop processing reaches local standalone owners even while GearSwap
-- is absent. The declarative commands are profile data; core appends the
-- validated lifecycle tuple and then routes the same tombstone through a live
-- adapter as defense in depth.
do
local signet_stop_starts = command_count()
fire(dolo, 'addon command', 'off')
for _, client in ipairs(clients) do
    local first = signet_stop_starts[client.player.name] + 1
    assert(contains_command(client,
        'sk stoppt '..recovery_fields[3]
            ..' 0.13.3 locus-dire-bats-tomb-signet 1.8.1 '
            ..recovery_fields[7]..' Dolomedes', first),
        client.player.name..' missed the core-owned Signet stop fence')
    assert(contains_command(client,
        'gs c ptgs action locus-signet retire '..recovery_fields[3], first),
        client.player.name..' missed the live-adapter stop tombstone')
end
assert(contains_command(dolo,
    'jk stoppt '..recovery_fields[3],
    signet_stop_starts.Dolomedes + 1))
assert(contains_command(tackle,
    'lp retirept '..recovery_fields[3]
        ..' 0.13.3 locus-dire-bats-tomb-signet 1.8.1',
    signet_stop_starts.Tackleberry + 1))
end

-- A recovery request is valid only while its exact predecessor remains the
-- active lifecycle. Once a terminal stop and explicit profile switch win, a
-- delayed keeper request for the retired Signet generation cannot create
-- another session.
local retired_recovery_fields = recovery_fields
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
local delayed_recovery_counts = command_count()
local delayed_recovery_ipc = #dolo.ipc_messages
fire(dolo, 'addon command', '__recover_controller', 'locus-signet',
    retired_recovery_fields[3], retired_recovery_fields[10], '2',
    retired_recovery_fields[5], retired_recovery_fields[6],
    retired_recovery_fields[4], retired_recovery_fields[7], 'Dolomedes',
    retired_recovery_fields[9], retired_recovery_fields[12],
    retired_recovery_fields[13])
assert_counts_unchanged(delayed_recovery_counts)
assert(#dolo.ipc_messages == delayed_recovery_ipc,
    'delayed recovery request emitted a successor after profile switch')

-- A terminal stop can land halfway through a compiler command containing a
-- delayed `aws2 on`. The exact old lifecycle owns one bounded OFF reassertion,
-- which defeats that stale command after two seconds without touching a later
-- active profile.
fire(dolo, 'addon command', 'off')
local stale_on_indices = {}
for _, client in ipairs(clients) do
    client.commands[#client.commands + 1] = 'aws2 on -- simulated stale wait1'
    stale_on_indices[client.player.name] = #client.commands
end
render_all(2.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'aws2 off',
        stale_on_indices[client.player.name] + 1),
        client.player.name..' did not defeat a stale post-stop aws2 on')
end

-- If a replacement commit stalls beyond the retry expiry, the old lifecycle
-- still emits its inert baseline instead of silently dropping the tombstone.
-- The pending generation may later apply and intentionally restore its own
-- complete policy, or it may be aborted as below.
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
fire(dolo, 'addon command', 'off')
fire(dolo, 'addon command', 'use', 'genmei')
local stalled_on_indices = {}
for _, client in ipairs(clients) do
    local callback = assert(client.callbacks['addon command'][1])
    local operator_request = assert(named_upvalue(
        callback, 'request_operator_state'),
        'could not inspect operator request closure')
    local pending = assert(named_upvalue(operator_request, 'pending_commit'),
        'could not inspect stalled pending commit')
    pending.apply_at = now + 30
    client.commands[#client.commands + 1] =
        'aws2 on -- simulated stale wait1 before stalled pending'
    stalled_on_indices[client.player.name] = #client.commands
end
render_all(6.1)
for _, client in ipairs(clients) do
    assert(contains_command(client, 'aws2 off',
        stalled_on_indices[client.player.name] + 1),
        client.player.name..' dropped terminal OFF while pending stalled')
end
fire(dolo, 'addon command', 'off')
for _, client in ipairs(clients) do
    local status_start = #client.chats + 1
    fire(client, 'addon command', 'status')
    assert(contains_chat(client, 'Inactive', status_start),
        client.player.name..' retained the aborted stalled commit')
end

-- Conversely, a replacement that applies before the terminal retry owns its
-- full compiler plan. The predecessor timer observes the new active lifecycle
-- and cancels without leaking OFF commands across the profile boundary.
fire(dolo, 'addon command', 'use', 'locus')
render_all(2.1)
fire(dolo, 'addon command', 'off')
do
local final_genmei_ipc_start = #dolo.ipc_messages + 1
fire(dolo, 'addon command', 'use', 'genmei')
local final_genmei_commit = assert(find_ipc(
    dolo, 'PARTYTACTICS1|commit|', final_genmei_ipc_start))
local final_genmei_fields = split_fields(final_genmei_commit)
render_all(2.1)
local switched_timer_starts = command_count()
render_all(5.1)
for _, client in ipairs(clients) do
    assert(not contains_command(client, 'pc invalidate partytactics',
        switched_timer_starts[client.player.name] + 1)
        and not contains_command(client, 'aws2 off',
            switched_timer_starts[client.player.name] + 1),
        client.player.name..' received a predecessor OFF after replacement')
end

-- Fixed-shape IPC is part of the lifecycle contract. Surplus stop/state data
-- represents an incompatible protocol revision and must not split core state
-- from the strict standalone companions that consume the same messages.
do
local surplus_stop_starts = command_count()
local surplus_stop = table.concat({
    'PARTYTACTICS1', 'stop', '1700000005-1001-991',
    final_genmei_fields[4], final_genmei_fields[5],
    final_genmei_fields[6], final_genmei_fields[7], 'Dolomedes',
    'surplus stop must fail', final_genmei_fields[3], 'surplus',
}, '|')
fire(barney, 'ipc message', surplus_stop)
assert_counts_unchanged(surplus_stop_starts)
local surplus_stop_status = #barney.chats + 1
fire(barney, 'addon command', 'status')
assert(contains_chat(barney, 'Active escha-ruaun-genbu-genmei',
    surplus_stop_status), '11-field stop changed active state')
end

do
local surplus_state = table.concat({
    'PARTYTACTICS1', 'state', final_genmei_fields[3],
    final_genmei_fields[4], final_genmei_fields[5],
    final_genmei_fields[6], final_genmei_fields[7], 'Dolomedes',
    final_genmei_fields[9], final_genmei_fields[10], '-', '-', '-',
    final_genmei_fields[12], final_genmei_fields[13], 'surplus',
}, '|')
fire(barney, 'ipc message', surplus_state)
local surplus_state_status = #barney.chats + 1
fire(barney, 'addon command', 'status')
assert(contains_chat(barney, 'combat armed', surplus_state_status),
    '16-field state changed the operator bit')
end

do
local surplus_operator_starts = command_count()
local surplus_operator = table.concat({
    'PARTYTACTICS1', 'operator-request', final_genmei_fields[3],
    final_genmei_fields[4], final_genmei_fields[5],
    final_genmei_fields[6], final_genmei_fields[7], final_genmei_fields[10],
    'Dolomedes', '1', '1', 'surplus',
}, '|')
fire(barney, 'ipc message', surplus_operator)
assert_counts_unchanged(surplus_operator_starts)
local surplus_operator_status = #barney.chats + 1
fire(barney, 'addon command', 'status')
assert(contains_chat(barney, 'combat armed', surplus_operator_status),
    '12-field operator-request changed the operator bit')
end

do
for _, invalid_epoch in ipairs{'nonnumeric', '00', '2147483648'} do
    local malformed_state = table.concat({
        'PARTYTACTICS1', 'state', final_genmei_fields[3],
        final_genmei_fields[4], final_genmei_fields[5],
        final_genmei_fields[6], final_genmei_fields[7], 'Dolomedes',
        final_genmei_fields[9], invalid_epoch, '-', '-', '-',
        final_genmei_fields[12], final_genmei_fields[13],
    }, '|')
    fire(barney, 'ipc message', malformed_state)
    local malformed_status = #barney.chats + 1
    fire(barney, 'addon command', 'status')
    assert(contains_chat(barney, 'combat armed', malformed_status),
        'malformed state epoch '..invalid_epoch..' changed operator state')
end
end
end

-- Replacing the Signet lifecycle with a genuinely different profile must
-- directly fence every standalone owner before compiler teardown. This path
-- cannot depend on the GearSwap host: a simultaneous host gap is the reason
-- the declarative core-owned commands exist. Unlike recovery above, no
-- Jubilee/Signet/Puller ownership is meant to cross this profile boundary.
do
    for _, client in ipairs(clients) do
        client.zone = 190
        client.controller_probe_enabled = true
    end
    local proof = {ipc_start=#dolo.ipc_messages + 1}
    fire(dolo, 'addon command', 'use', 'locus-signet')
    proof.commit = assert(find_ipc(
        dolo, 'PARTYTACTICS1|commit|', proof.ipc_start))
    proof.fields = split_fields(proof.commit)
    render_all(2.1)
    for _, client in ipairs(clients) do
        client.controller_probe_enabled = false
    end
    proof.starts = command_count()
    fire(dolo, 'addon command', 'use', 'locus')
    for _, client in ipairs(clients) do
        local first = proof.starts[client.player.name] + 1
        assert(contains_command(client,
            'sk stoppt '..proof.fields[3]
                ..' 0.13.3 locus-dire-bats-tomb-signet 1.8.1 '
                ..proof.fields[7]..' Dolomedes', first),
            client.player.name..' missed different-profile Signet fencing')
    end
    assert(contains_command(dolo,
        'jk stoppt '..proof.fields[3], proof.starts.Dolomedes + 1),
        'different-profile replacement did not fence JubileeKeeper')
    assert(contains_command(tackle,
        'lp retirept '..proof.fields[3]
            ..' 0.13.3 locus-dire-bats-tomb-signet 1.8.1',
        proof.starts.Tackleberry + 1),
        'different-profile replacement did not fence LocusPuller')
    render_all(2.1)
    for _, client in ipairs(clients) do
        client.controller_probe_enabled = true
    end
end

-- Reapplying the lifecycle profile outside its owned zone must remain inert
-- even if Ctrl-P records desired operator intent during the delay. With no
-- exact adapter proof, neither the reapply path nor state sync may issue ON.
do
    for _, client in ipairs(clients) do client.zone = 190 end
    -- Barney misses every initial epoch-0 commit/state carrier. The leader
    -- advances the live generation to epoch 1 and revision 1 while that gap is
    -- held; the next periodic state must merge both high-waters into Barney's
    -- existing prepare session so the resulting join commit can apply.
    held_ipc = {}
    hold_ipc = function(message, sender, recipient)
        return sender == dolo and recipient == barney
            and (message:find('PARTYTACTICS1|commit|', 1, true) == 1
                or message:find('PARTYTACTICS1|state|', 1, true) == 1)
    end
    fire(dolo, 'addon command', 'use', 'locus-signet')
    render_all(2.1)
    assert(#held_ipc > 0, 'did not isolate Barney from the initial commit')
    fire(dolo, 'gain buff', 269)
    fire(dolo, 'addon command', 'arm')
    render_all(3.1)
    hold_ipc = nil
    render_all(2.1)
    barney_join_callback = assert(barney.callbacks['addon command'][1])
    barney_join_request = assert(named_upvalue(
        barney_join_callback, 'request_operator_state'))
    barney_join_pending = assert(named_upvalue(
        barney_join_request, 'pending_commit'))
    assert(tonumber(barney_join_pending.apply_epoch) == 1
        and tonumber(barney_join_pending.operator_revision) == 1
        and barney_join_pending.operator_armed == true,
        'periodic state did not advance Barney\'s stale prepare carrier')
    render_all(2.1)
    barney_join_status = #barney.chats + 1
    fire(barney, 'addon command', 'status')
    assert(contains_chat(barney,
        'locus-dire-bats-tomb-signet', barney_join_status)
        and contains_chat(barney, 'combat armed r1', barney_join_status),
        'Barney did not apply the higher-epoch/high-water join commit')
    for _, client in ipairs(clients) do
        client.zone = 191
        client.controller_probe_enabled = false
        fire(client, 'zone change')
    end
    local outside_arm_starts = command_count()
    fire(dolo, 'addon command', 'arm')
    render_all(8.1)
    for _, client in ipairs(clients) do
        assert(not contains_command(client, 'pc on',
            outside_arm_starts[client.player.name] + 1),
            client.player.name..' armed an outside-Tomb lifecycle reapply')
        client.controller_probe_enabled = true
    end

    -- Raw PartyTactics unload is local-only, and can coincide with the exact
    -- GearSwap host gap which triggered recovery. Each client must therefore
    -- issue its own declarative companion tombstone before forgetting core
    -- state; no IPC sender loopback or live adapter is required.
    for _, client in ipairs(clients) do
        client.controller_probe_enabled = false
        local first = #client.commands + 1
        fire(client, 'unload')
        assert(contains_command(client, 'sk stoppt ', first),
            client.player.name..' missed its unload-time SignetKeeper fence')
        if client == dolo then
            assert(contains_command(client, 'jk stoppt ', first),
                'PartyTactics unload did not fence local JubileeKeeper')
        elseif client == tackle then
            assert(contains_command(client, 'lp retirept ', first),
                'PartyTactics unload did not fence local LocusPuller')
        end
    end
end

print('PartyTactics six-client activation tests passed')
