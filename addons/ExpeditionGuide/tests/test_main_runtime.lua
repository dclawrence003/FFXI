-- Mocked Windower runtime harness for ExpeditionGuide.lua itself.
-- Run in a fresh Lua process with: leader | follower | no-player

package.path = table.concat({
    'addons/ExpeditionGuide/?.lua',
    'addons/ExpeditionGuide/?/init.lua',
    package.path,
}, ';')

local scenario_name = arg and arg[1] or 'leader'

local function fail(message)
    error(message or 'assertion failed', 2)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        fail(('%s (expected %s, got %s)'):format(message or 'values differ',
            tostring(expected), tostring(actual)))
    end
end

local function truthy(value, message)
    if not value then fail(message or 'expected truthy value') end
end

local function falsy(value, message)
    if value then fail(message or 'expected falsy value') end
end

local function contains(value, needle, message)
    if not tostring(value):find(tostring(needle), 1, true) then
        fail(('%s (missing %q in %q)'):format(message or 'substring absent',
            tostring(needle), tostring(value)))
    end
end

local function clone(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[clone(key, seen)] = clone(child, seen) end
    return result
end

local function make_catalog(entries)
    local ordered, by_key, by_id = {}, {}, {}
    for index, source in ipairs(entries or {}) do
        local item = {
            key=source.key, id=source.id, name=source.name,
            protocol_index=index,
        }
        ordered[index], by_key[item.key], by_id[item.id] = item, item, item
    end
    return {ordered=ordered,by_key=by_key,by_id=by_id}
end

local runtime = {
    epoch=1788624000,
    clock=10,
    zone=scenario_name == 'follower' and 275 or 1,
    player=nil,
    me_available=true,
    position={x=0,y=0,z=0},
    peer_position={x=0,y=0,z=0},
    temporary_items={},
    key_items={[3300]=true},
    events={}, chats={}, commands={}, ipc={}, hud_objects={}, hud_texts={},
    arrow_images={},
    config_loads={}, config_saves={}, state_loads={}, state_saves={},
    get_dir_paths={}, content_load_paths={}, packet_parses={}, schedules={},
}

if scenario_name == 'leader' then
    runtime.player = {name='Dolomedes',id=1001,status=0,
        main_job='COR',sub_job='NIN'}
    -- Start deliberately unready to prove prerender cannot advance on partial
    -- evidence; readiness is restored later in the scenario.
    runtime.temporary_items = nil
elseif scenario_name == 'follower' then
    runtime.player = {name='Kickpuncher',id=1003,status=0,
        main_job='DNC',sub_job='NIN'}
elseif scenario_name ~= 'no-player' then
    fail('unknown runtime scenario ' .. tostring(scenario_name))
end

runtime.party = {party1_count=6,party1_leader=1001}
for index, member in ipairs({
    {'Dolomedes',1001},{'Tackleberry',1002},{'Kickpuncher',1003},
    {'Barneystinson',1004},{'Smalls',1005},{'Achoo',1006},
}) do
    runtime.party['p' .. tostring(index - 1)] = {
        name=member[1],id=member[2],mob={id=member[2]},
    }
end

local native_loadfile = loadfile
local native_io_open = io.open
local native_time, native_clock = os.time, os.clock

local function normalized(path)
    return tostring(path):gsub('\\', '/')
end

-- Production content paths are inspected by Sandbox via io.open, while the
-- actual chunk compiler below maps Windower-style backslashes to this tree.
io.open = function(path, mode)
    local clean = normalized(path)
    if mode == 'rb'
        and clean:match('^addons/ExpeditionGuide/content/sortie/[a-z_]+/[a-z0-9_%-]+%.lua$') then
        return {
            seek=function(_, where)
                equal(where, 'end')
                return 4096
            end,
            close=function() return true end,
        }
    end
    return nil, 'mock filesystem rejects ' .. clean
end

loadfile = function(path, ...)
    local clean = normalized(path)
    if clean:match('^addons/ExpeditionGuide/content/sortie/') then
        runtime.content_load_paths[#runtime.content_load_paths + 1] = clean
        falsy(clean:find('..', 1, true), 'content load path traversal')
    end
    return native_loadfile(clean, ...)
end

os.time = function() return runtime.epoch end
os.clock = function() return runtime.clock end

local config_mock = {}
function config_mock.load(path, defaults)
    runtime.config_loads[#runtime.config_loads + 1] = path
    return clone(defaults)
end
function config_mock.save(settings)
    runtime.config_saves[#runtime.config_saves + 1] = clone(settings)
    return true
end

local texts_mock = {}
function texts_mock.new(template, settings)
    equal(template, '${value}')
    truthy(type(settings) == 'table')
    local object = {visible=false,destroyed=false,current='',positions={}}
    function object:show() self.visible = true end
    function object:hide() self.visible = false end
    function object:destroy() self.destroyed = true end
    function object:pos(x, y)
        self.positions[#self.positions + 1] = {x=x,y=y}
    end
    function object:text(value)
        self.current = value
        runtime.hud_texts[#runtime.hud_texts + 1] = value
    end
    runtime.hud_objects[#runtime.hud_objects + 1] = object
    return object
end

local images_mock = {}
function images_mock.new(settings)
    truthy(type(settings) == 'table')
    local object = {visible=false,destroyed=false,current_path='',positions={}}
    function object:show() self.visible = true end
    function object:hide() self.visible = false end
    function object:destroy() self.destroyed = true end
    function object:pos(x, y)
        self.positions[#self.positions + 1] = {x=x,y=y}
    end
    function object:path(value) self.current_path = value end
    runtime.arrow_images[#runtime.arrow_images + 1] = object
    return object
end

local packets_mock = {}
function packets_mock.parse(direction, raw)
    runtime.packet_parses[#runtime.packet_parses + 1] = {
        direction=direction, raw=raw,
    }
    if direction == 'incoming' and raw == 'menu-packet' then
        return {['Menu ID']=1001}
    end
    if direction == 'outgoing' and raw == 'interaction-packet' then
        return {Category=0,Target=999,['Target Index']=859}
    end
    if direction == 'outgoing' and raw == 'b1-interaction-packet' then
        return {Category=0,Target=21001038,['Target Index']=846}
    end
    error('unrecognized mock packet')
end

local state_store_mock = {}
function state_store_mock.load(path)
    runtime.state_loads[#runtime.state_loads + 1] = path
    return nil, 'mock state absent'
end
function state_store_mock.save(path, value)
    runtime.state_saves[#runtime.state_saves + 1] = {
        path=path, value=clone(value),
    }
    return true
end

package.loaded.config = config_mock
package.loaded.texts = texts_mock
package.loaded.images = images_mock
package.loaded.packets = packets_mock
package.loaded['lib.state_store'] = state_store_mock

-- Install a second, route-less fixture pack before main loads. This proves the
-- production runtime projects one neutral snapshot into every installed pack
-- without allowing either catalog to collide with Sortie.
local odyssey_items = make_catalog({
    {key='moggle_mog',id=7777,name='Moogle Segment'},
})
local odyssey_key_items = make_catalog({
    {key='moglophone',id=8888,name='Moglophone'},
})
local runtime_registry = clone(require('content.registry'))
runtime_registry.reserved_aliases.odysseytest = 'odyssey-test-route'
runtime_registry.packs[#runtime_registry.packs + 1] = {
    id='odyssey-test',
    allowed_zones={[292]=true}, instance_zones={[292]=true},
    run_seconds=1800, stale_run_seconds=3600, catalog_revision=1,
    items='test.odyssey.items', key_items='test.odyssey.key_items',
    landmarks='test.odyssey.landmarks',
    routes={{module='test.odyssey.route',aliases={'odysseytest'}}},
}
package.loaded['content.registry'] = runtime_registry
package.loaded['test.odyssey.items'] = odyssey_items
package.loaded['test.odyssey.key_items'] = odyssey_key_items
package.loaded['test.odyssey.landmarks'] = {}
package.loaded['test.odyssey.route'] = {
    schema=1,id='odyssey-test-route',aliases={'odysseytest'},version='1.0.0',
    title='Odyssey Test Route',content='odyssey-test',
    allowed_zones={[292]=true},guide_only=true,
    steps={{id='hold',area='TEST',instruction='Remain inert.',
        completion={kind='manual'}}},
}

coroutine.schedule = function(callback, delay)
    runtime.schedules[#runtime.schedules + 1] = delay
    callback()
end

_addon = {}
windower = {
    addon_path='addons/ExpeditionGuide/',
    ffxi={},
}

function windower.register_event(name, callback)
    falsy(runtime.events[name], 'duplicate event registration ' .. name)
    runtime.events[name] = callback
end
function windower.add_to_chat(color, message)
    runtime.chats[#runtime.chats + 1] = {color=color,message=message}
end
function windower.send_command(command)
    runtime.commands[#runtime.commands + 1] = command
end
function windower.send_ipc_message(message)
    runtime.ipc[#runtime.ipc + 1] = message
end
function windower.get_windower_settings()
    return {ui_x_res=3840,ui_y_res=2160}
end
function windower.get_dir(path)
    local clean = normalized(path)
    runtime.get_dir_paths[#runtime.get_dir_paths + 1] = clean
    if clean:match('/content/sortie/profiles/$') then
        return {'objective_c_device_kill_v1.lua',
            'objective_c_magic_burst_v1.lua',
            'objective_d_demisang_clear_v1.lua',
            'objective_a_magic_kill_v1.lua',
            'boss_skomora_v1.lua','boss_ghatjot_v1.lua'}
    end
    if clean:match('/content/sortie/routes/$') then
        return {'postflight_ruspix.lua','onboarding_core_live.lua',
            'key_b_recovery_live.lua','key_b_sheet_d_canary_live.lua',
            'sheet_d_demisang_live.lua','two_boss_c_a_training.lua'}
    end
    return {}
end
function windower.dir_exists() return true end
function windower.create_dir(path) fail('unexpected create_dir ' .. tostring(path)) end

function windower.ffxi.get_player() return runtime.player end
function windower.ffxi.get_info()
    if not runtime.player then return nil end
    return {zone=runtime.zone}
end
function windower.ffxi.get_mob_by_target(target)
    if target == 'me' and runtime.player and runtime.me_available then
        return {id=runtime.player.id,index=runtime.player.id,
            name=runtime.player.name,x=runtime.position.x,
            y=runtime.position.y,z=runtime.position.z,facing=0,
            status=runtime.player.status}
    end
    return runtime.target
end
function windower.ffxi.get_mob_by_id(id)
    if runtime.player and id == runtime.player.id then
        return windower.ffxi.get_mob_by_target('me')
    end
    return runtime.mobs_by_id and runtime.mobs_by_id[id] or nil
end
function windower.ffxi.get_mob_by_index(index)
    return runtime.mobs_by_index and runtime.mobs_by_index[index] or nil
end
function windower.ffxi.get_mob_array()
    -- Route-action tests deliberately keep both allowable source families in
    -- interaction range. Dedicated bridge tests cover absent-source waiting.
    return {
        [9001]={id=9001,index=9001,name='Diaphanous Device',
            x=runtime.position.x,y=runtime.position.y,z=runtime.position.z,
            distance=4},
        [9002]={id=9002,index=9002,name='Diaphanous Gadget',
            x=runtime.position.x,y=runtime.position.y,z=runtime.position.z,
            distance=4},
    }
end
function windower.ffxi.get_items(bag)
    equal(bag, 3, 'only temporary-item bag may be read')
    return runtime.temporary_items
end
function windower.ffxi.get_key_items() return runtime.key_items end
function windower.ffxi.get_party()
    return runtime.player and runtime.party or nil
end

local main_chunk, main_error = native_loadfile(
    'addons/ExpeditionGuide/ExpeditionGuide.lua')
truthy(main_chunk, main_error)
main_chunk()

local function fire(name, ...)
    local callback = runtime.events[name]
    truthy(callback, 'missing registered event ' .. tostring(name))
    return callback(...)
end

local function chat_contains(needle)
    for _, item in ipairs(runtime.chats) do
        if item.message:find(needle, 1, true) then return true end
    end
    return false
end

local function last_hud()
    return runtime.hud_texts[#runtime.hud_texts] or ''
end

falsy(chat_contains('content registry unavailable:'),
    'a successful registry load printed a false failure')

local required_events = {
    'load','login','logout','unload','zone change','incoming chunk',
    'outgoing chunk','ipc message','prerender','addon command',
}
for _, name in ipairs(required_events) do
    truthy(runtime.events[name], 'main omitted event ' .. name)
end
equal(_addon.name, 'ExpeditionGuide')
equal(_addon.version, '1.2.0')
equal(_addon.commands[1], 'exg')
equal(_addon.commands[2], 'expeditionguide')
equal(#_addon.commands, 2)

-- Discovery adds both operational objective descriptors, the live and
-- recovery routes, and the standalone postflight guide. Frozen explicit and
-- discovered content must all pass through Sandbox.
equal(#runtime.get_dir_paths, 2)
truthy(runtime.get_dir_paths[1]:match('/profiles/$'))
truthy(runtime.get_dir_paths[2]:match('/routes/$'))
equal(#runtime.content_load_paths, 16)
for _, path in ipairs(runtime.content_load_paths) do
    truthy(path:match('^addons/ExpeditionGuide/content/sortie/'))
end

local Protocol = require('lib.protocol')
local items = require('content.sortie.items')
local key_items = require('content.sortie.key_items')
local Fingerprint = require('lib.fingerprint')
local function identified_pack(id, revision, item_catalog, key_item_catalog)
    local contract = {pack_id=id,revision=revision,temporary={},key_items={}}
    for index, item in ipairs(item_catalog.ordered) do
        contract.temporary[index] = {key=item.key,id=item.id}
    end
    for index, item in ipairs(key_item_catalog.ordered) do
        contract.key_items[index] = {key=item.key,id=item.id}
    end
    local instance_zones = id == 'sortie'
        and {[133]=true,[189]=true,[275]=true} or {[292]=true}
    return {id=id,items=item_catalog,key_items=key_item_catalog,
        instance_zones=instance_zones,
        catalog_id=('%s-r%d-%s'):format(id, revision,
            Fingerprint.value(contract))}
end
local sortie_pack = identified_pack('sortie', 2, items, key_items)
local odyssey_pack = identified_pack(
    'odyssey-test', 1, odyssey_items, odyssey_key_items)
local catalogs = {sortie=sortie_pack,['odyssey-test']=odyssey_pack}
local item_bits = string.rep('0', #items.ordered)

local function reports_between(first, last)
    local reports = {}
    for index = first, last do
        local report, reason = Protocol.validate(runtime.ipc[index], {
            now=runtime.epoch,max_age=8,catalogs=catalogs,
        })
        truthy(report, reason)
        falsy(reports[report.pack_id], 'duplicate report for ' .. report.pack_id)
        reports[report.pack_id] = report
    end
    return reports
end

local function peer_state(name, zone, sequence, values)
    values = values or {}
    local entry_nonce = values.entry_nonce
    if entry_nonce == nil then
        entry_nonce = (zone == 133 or zone == 189 or zone == 275)
            and (name:lower() .. '-entry-1') or ''
    end
    return Protocol.state({
        pack_id=sortie_pack.id,catalog_id=sortie_pack.catalog_id,
        sender=name,main_job='WHM',sub_job='SCH',zone=zone,
        timestamp=runtime.epoch,sequence=sequence or 1,
        x=values.x or runtime.peer_position.x,
        y=values.y or runtime.peer_position.y,
        z=values.z or runtime.peer_position.z,status=0,ready=true,
        party_exact=values.party_exact ~= false,
        leader_exact=values.leader_exact == true,
        entry_nonce=entry_nonce,
        items=item_bits,key_items=values.key_items or '100',
    })
end

if scenario_name == 'leader' then
    fire('load')
    equal(#runtime.config_loads, 1)
    equal(runtime.config_loads[1], 'data/settings_Dolomedes.xml')
    equal(#runtime.state_loads, 3,
        'primary, interrupted-write recovery, and backup state should be inspected')
    equal(#runtime.hud_objects, 1)
    equal(#runtime.arrow_images, 1)
    equal(runtime.config_saves[1].layout_revision,5)
    equal(runtime.config_saves[1].arrow.size,180)
    equal(runtime.config_saves[1].arrow.visible,false)
    equal(#runtime.ipc, 2)
    equal(#runtime.commands, 0)
    contains(last_hud(), 'STEP 1 OF')
    contains(last_hud(), 'NOT STARTED')
    contains(last_hud(), 'SENSORS 1/6')
    truthy(chat_contains('ready on Dolomedes'))
    falsy(chat_contains('quarantined'))

    local initial_reports = reports_between(1, 2)
    local initial = initial_reports.sortie
    local other = initial_reports['odyssey-test']
    truthy(initial); truthy(other); falsy(initial.ready); falsy(other.ready)
    equal(initial.sequence, other.sequence,
        'all pack projections must share one neutral snapshot sequence')
    equal(initial.sender, other.sender); equal(initial.main_job, other.main_job)
    equal(initial.timestamp, other.timestamp); equal(initial.zone, other.zone)
    equal(initial.entry_nonce, ''); equal(other.entry_nonce, '')
    equal(other.items, '0'); equal(other.key_items, '0')
    equal(initial.zone, 1, 'leader load fixture must begin outside Sortie')

    fire('addon command', 'start', 'sortie-onboarding-core-live')
    contains(last_hud(), 'Sortie Onboarding: Core Unlocks (Live Canary)')
    contains(last_hud(), 'LIVE')
    equal(#runtime.commands, 0,
        'starting the live route must not load or arm a combat profile')

    fire('addon command', 'start', 'sortie-postflight-ruspix')
    contains(last_hud(), "Sortie Postflight: Ruspix's Plate")
    falsy(last_hud():find('ENTRY CHECK', 1, true),
        'standalone postflight key-item evidence is not an entry guard')

    fire('addon command', 'start', 'odysseytest')
    contains(last_hud(), 'Odyssey Test Route')
    contains(last_hud(), 'STEP 1 OF 1')
    fire('addon command', 'status')
    truthy(chat_contains('| odyssey-test-route |'))
    truthy(chat_contains('Moglophone 0/6'))
    fire('addon command', 'time', '31:00')
    truthy(chat_contains('00:00 to 30:00'))
    equal(#runtime.commands, 0,
        'switching active packs must remain presentation/state only')
    fire('addon command', 'start', 'onboarding')
    contains(last_hud(), 'Sortie Onboarding: Core Unlocks')

    fire('addon command', 'status')
    truthy(chat_contains('| leader |'))
    fire('addon command', 'steps')
    truthy(chat_contains('Sortie Onboarding: Core Unlocks steps:'))
    fire('addon command', 'explain', '1')
    truthy(chat_contains('Step 1/'))
    truthy(chat_contains('Completion evidence: all_key_item'))
    fire('addon command', 'start', 'onboarding')
    truthy(chat_contains('Started sortie-onboarding-core'))
    contains(last_hud(), 'ACTIVE')
    equal(#runtime.commands, 0,
        'route/status/steps/explain/start must never dispatch commands')

    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 1, 1,
            {party_exact=name ~= 'Achoo'}))
    end
    fire('ipc message', 'foreign|message')
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 1 OF')
    equal(#runtime.commands, 0)

    runtime.temporary_items = {}
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 1 OF')
    contains(last_hud(), 'PARTY 5/6')
    contains(last_hud(), 'ENTRY CHECK: PARTY')
    fire('ipc message', peer_state('Achoo', 1, 2))
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 2 OF')
    truthy(chat_contains('Advanced to: Dolo requests entry'))

    -- The pre-entry success is not a one-time latch. Exact party, leadership,
    -- and Shiny-plate proof remain live until the instance transition.
    local achoo = runtime.party.p5
    runtime.party.p5 = nil
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 2 OF')
    contains(last_hud(), 'ENTRY CHECK: PARTY')

    runtime.party.p5 = achoo
    runtime.party.party1_leader = 9999
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 2 OF')
    contains(last_hud(), 'DOLO LEADER 0/1')

    runtime.party.party1_leader = 1001
    runtime.epoch = runtime.epoch + 1
    fire('ipc message', peer_state('Achoo', 1, 3, {key_items='000'}))
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 2 OF')
    contains(last_hud(), 'missing 1: Achoo')

    fire('ipc message', peer_state('Achoo', 1, 4, {key_items='001'}))
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'Dull 1: Achoo')

    fire('ipc message', peer_state('Achoo', 1, 5, {key_items='101'}))
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'INVALID 1: Achoo')

    fire('ipc message', peer_state('Achoo', 1, 6,
        {key_items='100',party_exact=false}))
    fire('addon command', 'status')
    truthy(chat_contains('unknown 1: Achoo'))
    fire('ipc message', peer_state('Achoo', 1, 7, {key_items='100'}))

    fire('addon command', 'next')
    contains(last_hud(), 'STEP 3 OF')
    truthy(chat_contains('Advanced by operator override'))
    fire('addon command', 'back')
    contains(last_hud(), 'STEP 2 OF')
    equal(#runtime.commands, 0)

    runtime.zone = 275
    runtime.epoch = runtime.epoch + 1
    fire('zone change', 275, 1)
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls'}) do
        fire('ipc message', peer_state(name, 275, 2))
    end
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 2 OF')
    contains(last_hud(), 'SENSORS UNBOUND')
    equal(#runtime.commands, 0)

    fire('ipc message', peer_state('Achoo', 275, 2))
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 3 OF')
    truthy(chat_contains('Advanced to: Hold at the starting Device'))

    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 4 OF')
    truthy(chat_contains('Advanced to: From Start go north'))
    contains(last_hud(), 'CHEST RISK: Key A chest')
    contains(last_hud(), 'report receipt stale')
    contains(last_hud(), '[Tackleberry,Kickpuncher,Barneystinson,')
    contains(last_hud(), 'Smalls,Achoo]')

    -- Reward authorization is a two-cycle, region-bound, memory-only HUD
    -- proof. It remains advisory, survives an ordinary rerender, and is
    -- immediately cleared by a lifecycle command.
    runtime.position.z = -150
    runtime.peer_position.z = -150
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 3))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'CHEST RISK: Key A chest')
    contains(last_hud(), '(scope SORTIE GROUND FLOOR, 1/2)')
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 4))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(),
        'CHEST READY: 6/6 in SORTIE GROUND FLOOR, stable 2/2 - Key A chest')
    local safe_hud = last_hud()
    truthy(safe_hud:find('DO THIS NOW',1,true)
        < safe_hud:find('CHEST READY',1,true),
        'operator instruction must remain primary and chest proof advisory')
    runtime.clock = runtime.clock + 0.2
    fire('prerender')
    contains(last_hud(), 'CHEST READY: 6/6 in SORTIE GROUND FLOOR')
    fire('addon command','pause')
    falsy(last_hud():find('CHEST READY',1,true),
        'pause must revoke an in-memory reward proof immediately')
    contains(last_hud(), 'CHEST CHECK: Key A chest - route is not active')
    fire('addon command','resume')
    falsy(last_hud():find('CHEST READY',1,true),
        'resume must require two new distinct report cycles')
    contains(last_hud(), '(scope SORTIE GROUND FLOOR, 1/2)')
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 5))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'CHEST READY: 6/6 in SORTIE GROUND FLOOR')
    runtime.position.z = -210
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 6))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    falsy(last_hud():find('CHEST READY',1,true),
        'a large relocation must revoke reward proof before HUD rendering')
    contains(last_hud(), '(scope SORTIE GROUND FLOOR, 1/2)')
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 7))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'CHEST READY: 6/6 in SORTIE GROUND FLOOR')
    fire('addon command','resync')
    falsy(last_hud():find('CHEST READY',1,true),
        'resync must replace a stale SAFE line immediately')
    contains(last_hud(), 'CHEST RISK: Key A chest')
    runtime.position.z = -150
    equal(#runtime.commands,0,
        'reward observation must never dispatch a Windower command')

    -- A full same-zone reentry is a new run. The prior five follower nonces
    -- cannot bind with Dolo's new entry even though they are fresh.
    runtime.zone = 1
    runtime.epoch = runtime.epoch + 1
    fire('zone change', 1, 275)
    runtime.zone = 275
    runtime.epoch = runtime.epoch + 1
    fire('zone change', 275, 1)
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 4,
            {entry_nonce=name:lower() .. '-entry-1'}))
    end
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'SENSORS UNBOUND')
    contains(last_hud(), 'RECOVERY REQUIRED')

    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 5,
            {entry_nonce=name:lower() .. '-entry-2'}))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 4 OF')
    falsy(last_hud():find('SENSORS UNBOUND', 1, true))

    -- A transient stale cohort freezes evidence without destroying the exact
    -- session. Fresh reports with the same nonces recover it.
    runtime.epoch = runtime.epoch + 10
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 4 OF')
    for _, name in ipairs({'Tackleberry','Kickpuncher','Barneystinson','Smalls','Achoo'}) do
        fire('ipc message', peer_state(name, 275, 6,
            {entry_nonce=name:lower() .. '-entry-2'}))
    end
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    contains(last_hud(), 'STEP 4 OF')
    falsy(last_hud():find('SENSORS UNBOUND', 1, true))

    -- Switching and resetting routes inside a stable run attach the new
    -- Engine to the already validated exact cohort instead of deadlocking.
    fire('addon command', 'start', 'onboarding')
    falsy(last_hud():find('SENSORS UNBOUND', 1, true))
    fire('addon command', 'reset', 'confirm')
    falsy(last_hud():find('SENSORS UNBOUND', 1, true))
    fire('addon command', 'resume')
    contains(last_hud(), 'ACTIVE')

    -- Reaching a combat step exposes the exact canonical command. The next
    -- prerender emits it once without transient idle/quorum/preflight gates;
    -- //exg profile remains an explicit recovery retry.
    fire('addon command', 'start', 'sortie-onboarding-core-live')
    for _ = 1, 12 do fire('addon command', 'skip') end
    contains(last_hud(), 'STEP 13 OF 19')
    contains(last_hud(),
        'AUTO - //pt use sortie-objective-c-device-kill-v1 inert')
    equal(#runtime.commands, 0)
    fire('prerender')
    equal(#runtime.commands, 1)
    equal(runtime.commands[1],
        'lua i PartyTactics use sortie-objective-c-device-kill-v1 inert')
    truthy(chat_contains('Automatic combat handoff'))
    fire('prerender')
    equal(#runtime.commands, 1,
        'automatic lifecycle must not fight a manual override by repeating')
    fire('addon command', 'profile')
    equal(#runtime.commands, 2)
    equal(runtime.commands[2],
        'lua i PartyTactics use sortie-objective-c-device-kill-v1 inert')
    truthy(chat_contains('Recovery request sent: //pt use'))
    contains(last_hud(),
        'AUTO - //pt use sortie-objective-c-device-kill-v1 inert')

    -- A real gate interaction advances its exact target_interaction step.
    -- This observation is read-only: it never clicks the gate for Dolo.
    fire('addon command', 'start', 'sortie-key-b-sheet-d-canary-live')
    for _ = 1, 4 do fire('addon command', 'skip') end
    contains(last_hud(), 'STEP 5 OF 20')
    runtime.mobs_by_id = {
        [21001038]={id=21001038,index=846,name='Gate #B1',
            x=-60,y=35,z=-182,distance=4},
    }
    runtime.mobs_by_index = {[846]=runtime.mobs_by_id[21001038]}
    fire('outgoing chunk', 0x01A, 'b1-interaction-packet', nil, false)
    contains(last_hud(), 'STEP 6 OF 20')
    truthy(chat_contains('Advanced after your interaction'))
    runtime.mobs_by_id, runtime.mobs_by_index = nil, nil
    equal(#runtime.commands, 2,
        'observing an interaction must not dispatch a Windower command')
    local parses_after_interaction = #runtime.packet_parses

    -- The next-run route goes directly to D; completed Key B work is absent.
    -- Its helper receives the same automatic one-shot plus recovery behavior.
    fire('addon command', 'start', 'dclear')
    for _ = 1, 4 do fire('addon command', 'skip') end
    contains(last_hud(), 'STEP 5 OF 14')
    contains(last_hud(), 'direct Sheet D Demisang clear')
    falsy(last_hud():find('Gate B1', 1, true))
    contains(last_hud(),
        'AUTO - //pt use sortie-objective-d-demisang-clear-v1 inert')
    fire('addon command','arrow','on')
    truthy(runtime.arrow_images[1].visible,
        'active in-instance waypoint must show the separate arrow')
    contains(runtime.arrow_images[1].current_path,
        'assets\\arrow\\arrow_')
    equal(#runtime.commands, 2)
    fire('prerender')
    equal(#runtime.commands, 3)
    equal(runtime.commands[3],
        'lua i PartyTactics use sortie-objective-d-demisang-clear-v1 inert')
    fire('prerender')
    equal(#runtime.commands, 3)
    fire('addon command', 'profile')
    equal(#runtime.commands, 4)
    equal(runtime.commands[4],
        'lua i PartyTactics use sortie-objective-d-demisang-clear-v1 inert')
    truthy(chat_contains(
        'Recovery request sent: //pt use sortie-objective-d-demisang-clear-v1'))

    -- Read-only packet observation stays outside the lifecycle apertures.
    fire('incoming chunk', 0x031, 'ignored', nil)
    equal(#runtime.packet_parses, parses_after_interaction)
    fire('incoming chunk', 0x032, 'menu-packet', nil)
    equal(#runtime.packet_parses, parses_after_interaction,
        'an unrelated menu packet must not be parsed on a non-interaction step')
    equal(#runtime.commands, 4)

    -- The two-boss route wires profile handoffs and exact Superwarp actions
    -- into main. Every transition emits once, same-profile objective steps do
    -- not re-arm, and travel away from an armed fight explicitly disarms.
    fire('addon command', 'start', 'boss2')
    fire('addon command', 'skip')
    fire('addon command', 'skip')
    contains(last_hud(), 'STEP 3 OF 18')
    fire('prerender')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    fire('addon command', 'skip')
    fire('prerender')
    local expected_boss_operations = {
        'sw so p c',
        'lua i PartyTactics use sortie-objective-c-magic-burst-v1',
        'lua i PartyTactics use sortie-boss-skomora-v1 inert',
        'lua i PartyTactics use sortie-boss-skomora-v1',
        'sw so p port',
        'lua i PartyTactics disarm',
        'sw so p port',
        'sw so p a',
        'lua i PartyTactics use sortie-objective-a-magic-kill-v1',
        'lua i PartyTactics use sortie-boss-ghatjot-v1 inert',
        'lua i PartyTactics use sortie-boss-ghatjot-v1',
        'sw so p port',
        'lua i PartyTactics disarm',
    }
    equal(#runtime.commands, 4 + #expected_boss_operations)
    for index, expected in ipairs(expected_boss_operations) do
        equal(runtime.commands[4 + index], expected,
            'wrong two-boss lifecycle operation ' .. tostring(index))
    end
    truthy(chat_contains('Automatic route action: //sw so p c'))
    truthy(chat_contains(
        'Automatic combat handoff: //pt use sortie-objective-a-magic-kill-v1'))

    fire('addon command', 'stop')
    equal(#runtime.commands, 5 + #expected_boss_operations)
    equal(runtime.commands[#runtime.commands], 'lua i PartyTactics off')
    contains(last_hud(), 'PAUSED')
    truthy(chat_contains('PartyTactics stopped and route paused'))

    local saves_before_unload = #runtime.state_saves
    fire('unload')
    truthy(runtime.hud_objects[1].destroyed)
    truthy(runtime.arrow_images[1].destroyed)
    truthy(#runtime.state_saves > saves_before_unload,
        'leader unload must persist route state')
    equal(#runtime.commands, 5 + #expected_boss_operations,
        'unload teardown must not dispatch another command')
elseif scenario_name == 'follower' then
    fire('load')
    equal(#runtime.config_loads, 1)
    equal(runtime.config_loads[1], 'data/settings_Kickpuncher.xml')
    equal(#runtime.hud_objects, 0, 'follower must be sensor-only')
    equal(#runtime.arrow_images, 0, 'follower must have no navigation overlay')
    equal(#runtime.state_loads, 0, 'follower must not load leader route state')
    equal(#runtime.state_saves, 0, 'follower must not persist leader route state')
    equal(#runtime.ipc, 2)
    local follower_reports = reports_between(1, 2)
    local report = follower_reports.sortie
    local other = follower_reports['odyssey-test']
    truthy(report); truthy(other); truthy(report.ready)
    equal(report.sender, 'Kickpuncher')
    truthy(report.party_exact); falsy(report.leader_exact)
    equal(report.sequence, other.sequence)
    equal(report.timestamp, other.timestamp); equal(report.zone, other.zone)
    equal(report.zone, 275)
    equal(report.entry_nonce, '',
        'cold load inside must remain sensor-only and unbound')
    fire('addon command', 'status')
    truthy(chat_contains('| sensor | no route |'))
    fire('addon command', 'start', 'onboarding')
    truthy(chat_contains('Route controls are leader-only'))
    fire('addon command', 'stop')
    equal(#runtime.commands, 0,
        'follower stop must not cross the leader-only command aperture')
    runtime.epoch = runtime.epoch + 1
    runtime.clock = runtime.clock + 1.1
    fire('prerender')
    equal(#runtime.ipc, 4)
    equal(#runtime.hud_objects, 0)
    equal(#runtime.arrow_images, 0)
    fire('unload')
    equal(#runtime.state_saves, 0)
    equal(#runtime.commands, 0)
elseif scenario_name == 'no-player' then
    fire('load')
    fire('login')
    fire('prerender')
    fire('addon command', 'status')
    truthy(chat_contains('Not logged in yet.'))
    equal(#runtime.config_loads, 0)
    equal(#runtime.hud_objects, 0)
    equal(#runtime.ipc, 0)
    equal(#runtime.state_loads, 0)
    equal(#runtime.state_saves, 0)
    equal(#runtime.commands, 0)
    fire('unload')
    equal(#runtime.commands, 0)
end

-- Keep accidental future host actions visible even when this harness grows.
for index, command in ipairs(runtime.commands) do
    local expected = scenario_name == 'leader' and ({
        'lua i PartyTactics use sortie-objective-c-device-kill-v1 inert',
        'lua i PartyTactics use sortie-objective-c-device-kill-v1 inert',
        'lua i PartyTactics use sortie-objective-d-demisang-clear-v1 inert',
        'lua i PartyTactics use sortie-objective-d-demisang-clear-v1 inert',
        'sw so p c',
        'lua i PartyTactics use sortie-objective-c-magic-burst-v1',
        'lua i PartyTactics use sortie-boss-skomora-v1 inert',
        'lua i PartyTactics use sortie-boss-skomora-v1',
        'sw so p port',
        'lua i PartyTactics disarm',
        'sw so p port',
        'sw so p a',
        'lua i PartyTactics use sortie-objective-a-magic-kill-v1',
        'lua i PartyTactics use sortie-boss-ghatjot-v1 inert',
        'lua i PartyTactics use sortie-boss-ghatjot-v1',
        'sw so p port',
        'lua i PartyTactics disarm',
        'lua i PartyTactics off',
    })[index] or nil
    if command ~= expected then
        fail('unexpected Windower command dispatch: ' .. tostring(command))
    end
end

io.open = native_io_open
loadfile = native_loadfile
os.time, os.clock = native_time, native_clock

print(('PASS - ExpeditionGuide mocked main runtime (%s)'):format(scenario_name))
