local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = test_dir..'/../gearswap/adapters/'
    ..'locus-dire-bats-tomb-signet/1.8.1.lua'
local puller_path = test_dir..'/../../LocusPuller/LocusPuller.lua'

local GENERATION = '1789438000-1001-2'
local PROFILE_ID = 'locus-dire-bats-tomb-signet'
local PROFILE_VERSION = '1.8.1'
local ENGINE_VERSION = '0.13.3'
local SIGNATURE = '1a2b3c4d'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'

local now = 100
local commands, queue, callbacks, scheduled = {}, {}, {}, {}
local player = {id=1001, index=101, name='Tackleberry', main_job='PLD',
    sub_job='WAR', status=0, vitals={mp=1000}, buffs={}}
local me = {id=1001, index=101, name='Tackleberry', x=0, y=0,
    hpp=100, spawn_type=1, valid_target=true, distance=0}
local bat = {id=9001, index=901, name='Locus Dire Bat', x=5.2, y=0,
    hpp=100, spawn_type=16, valid_target=nil, claim_id=player.id,
    distance=900}
local selected = me
local adapter
local host
local host_callbacks = {}
local fault = arg and arg[1] == '--drop-lp-ack'
local sk_fault = arg and arg[1] == '--drop-sk-ack'
local sk_callbacks = {}

local function tokens(value)
    local result = {}
    for token in tostring(value):gmatch('%S+') do result[#result + 1] = token end
    return result
end

local function count_contains(text)
    local count = 0
    for _, command in ipairs(commands) do
        if command:find(text, 1, true) then count = count + 1 end
    end
    return count
end

local function dispatch_one(command)
    for part in tostring(command):gmatch('[^;]+') do
        part = part:match('^%s*(.-)%s*$')
        local fields = tokens(part)
        if fields[1] == 'lp' and callbacks['addon command'] then
            local args = {}
            for index = 3, #fields do args[#args + 1] = fields[index] end
            callbacks['addon command'](fields[2],
                (table.unpack or unpack)(args))
        elseif fields[1] == 'sk' and sk_callbacks['addon command'] then
            local args = {}
            for index = 2, #fields do args[#args+1] = fields[index] end
            sk_callbacks['addon command']((table.unpack or unpack)(args))
        elseif fields[1] == 'gs' and fields[2] == 'c'
            and fields[3] == 'ptgs'
        then
            local args = {}
            for index = 3, #fields do args[#args + 1] = fields[index] end
            if fault and fields[6] == 'companion-ready' and fields[10] == 'lp' then
                print('INJECTED FAULT: dropped real LP readiness ACK at transport')
            elseif sk_fault and fields[6] == 'companion-ready' and fields[10] == 'sk' then
                print('INJECTED FAULT: dropped real SK readiness ACK at transport')
            else
                local event = {}
                user_job_self_command(args, event)
                assert(event.handled, 'host did not consume '..part)
            end
        end
    end
end

local function flush_commands()
    local rounds = 0
    while #queue > 0 do
        rounds = rounds + 1
        assert(rounds < 100, 'local command routing did not quiesce')
        local command = table.remove(queue, 1)
        dispatch_one(command)
    end
end

_addon = {}
PARTYTACTICS_LOCUS_SIGNET_TEST_MODE = true
local real_clock = os.clock
os.clock = function() return now end

local packets = {
    new=function(direction, id, fields)
        fields.direction, fields.packet_id = direction, id
        return fields
    end,
    inject=function(packet)
        assert(packet.direction == 'incoming' and packet.packet_id == 0x058)
        selected = packet.Target == bat.id and bat or me
    end,
}
require = function(name)
    assert(name == 'packets')
    return packets
end
coroutine.schedule = function(fn, delay)
    scheduled[#scheduled + 1] = {fn=fn, at=now + delay}
end
windower = {
    add_to_chat=function() end,
    send_command=function(command)
        commands[#commands + 1] = command
        queue[#queue + 1] = command
    end,
    send_ipc_message=function() end,
    register_event=function(name, fn) callbacks[name] = fn end,
    raw_register_event=function(name, fn) host_callbacks[name] = fn end,
    ffxi={
        get_player=function() return player end,
        get_info=function() return {zone=190, logged_in=true} end,
        get_mob_by_target=function(token)
            if token == 'me' then return me end
            if token == 't' then return selected end
        end,
        get_mob_by_id=function(id) return tonumber(id) == bat.id and bat end,
        get_mob_array=function() return {[me.id]=me, [bat.id]=bat} end,
        get_party=function()
            return {p0={name=player.name, mob={id=player.id}}}
        end,
        get_spell_recasts=function() return {[112]=0} end,
        get_items=function() return {equipment={},inventory={}} end,
    },
}

assert(loadfile(puller_path))()
local sk_env=setmetatable({_addon={},os=os}, {__index=_G})
sk_env._G=sk_env
sk_env.require=function(name) error('Optional dependency unavailable: '..name) end
sk_env.windower=setmetatable({register_event=function(name,fn) sk_callbacks[name]=fn end},
    {__index=windower})
local sk_path=test_dir..'/../../SignetKeeper/SignetKeeper.lua'
if setfenv then setfenv(assert(loadfile(sk_path)),sk_env)()
else assert(loadfile(sk_path,'t',sk_env))() end
include = function(path)
    assert(path == 'Common/PartyTactics/adapters/'
        ..PROFILE_ID..'/'..PROFILE_VERSION..'.lua')
    adapter = assert(loadfile(adapter_path))()
    return adapter
end
host = assert(loadfile(test_dir..'/../gearswap/PartyTactics_Host.lua'))()
user_job_self_command({'ptgs','activate',PROFILE_ID,PROFILE_VERSION}, {})
assert(host.active_metadata() and host.active_metadata().id == PROFILE_ID,
    'real host failed adapter activation')
flush_commands()

local function action(controller, semantic, args)
    local command = {'ptgs','action',controller,semantic}
    for _, value in ipairs(args) do command[#command + 1] = value end
    local event = {}
    user_job_self_command(command, event)
    assert(event.handled, 'real host did not consume action')
    return true -- consumption only; independent assertions check outcomes
end

local accepted, reason = action('locus-signet', 'authorize', {
    GENERATION, '0', '2', PROFILE_ID, PROFILE_VERSION, SIGNATURE,
    'Dolomedes', ROSTER, '1', '1',
})
assert(accepted, reason)
flush_commands()
accepted, reason = action('locus-signet', 'probe', {
    GENERATION, '0', '2',
})
assert(accepted, reason)
flush_commands()

-- The LP ACK above traveled through its real addon command dispatcher and
-- back through the adapter action parser. The exact controller probe is ready
-- independent of SK's ACK. Both real local companion reply paths are exercised;
-- this fixture does not tick the six-client Signet census.
assert(adapter._test_state.companion_ready.lp == true,
    'READINESS FAILURE: real LP ACK did not reach actual GearSwap host/adapter')
assert(count_contains('pt __controller_ready locus-signet '..GENERATION
    ..' 0 2') == 1)
assert(adapter._test_state.companion_ready.sk == true,
    'READINESS FAILURE: real SK ACK did not reach actual GearSwap host/adapter')
assert(count_contains('pt __controller_ready locus-signet '..GENERATION
    ..' 0 2') == 1)

assert(action('locus-signet', 'operator', {
    GENERATION, '0', '2', '1', '1',
}))
callbacks['addon command']('operator', 'on', GENERATION, '0', '1')

local function run_due()
    local pending = {}
    for _, item in ipairs(scheduled) do
        if item.at <= now then item.fn() else pending[#pending + 1] = item end
    end
    scheduled = pending
end

-- Acquire with valid_target absent and a contradictory squared-distance
-- fallback. LP and adapter must both prefer the exact 5.2-yalm coordinates.
callbacks.prerender()
flush_commands()
assert(adapter._test_state.opener
    and adapter._test_state.opener.id == bat.id,
    'LP opener request did not survive adapter target validation')
assert(selected == bat, 'adapter gate did not return control to LP selection')

-- Dispatch occurs at its real scheduled edge and is confirmed by the exact
-- outgoing packet. Its result may still settle near the eight-second bound,
-- followed by first melee near the twenty-second bound. Adapter TTL is an
-- outer failsafe and must not release this valid sequence early.
now = now + 0.21
run_due()
flush_commands()
assert(count_contains('input /ma "Flash" <t>') == 1)
callbacks['outgoing chunk'](0x01A, {
    Category=3, Param=112, Target=bat.id, ['Target Index']=bat.index,
}, nil, false, false)
now = now + 7.4
host_callbacks.prerender()
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
flush_commands()
now = now + 19.9
host_callbacks.prerender()
callbacks.prerender()
assert(adapter._test_state.opener ~= nil,
    'adapter expired before LP first-melee window completed')
callbacks.action({actor_id=player.id, category=1, param=0,
    targets={{id=bat.id, actions={{message=1}}}}})
flush_commands()
assert(adapter._test_state.opener == nil,
    'real LP first-melee result did not release adapter reservation')

-- A new opener with no legal completion still fails open at the adapter's
-- independent thirty-second outer bound.
bat = {id=9002, index=902, name='Locus Dire Bat', x=5.2, y=0,
    hpp=100, spawn_type=16, valid_target=nil, claim_id=player.id,
    distance=900}
selected, player.status = me, 0
now = now + 0.21
callbacks.prerender()
flush_commands()
assert(adapter._test_state.opener ~= nil)
local timeouts = adapter._test_state.opener_timeouts
now = now + 30.1
host_callbacks.prerender()
flush_commands()
callbacks.prerender()
flush_commands()
assert(adapter._test_state.opener == nil
    and adapter._test_state.opener_timeouts == timeouts + 1,
    'adapter outer opener bound did not fail open exactly once')

user_job_self_command({'ptgs','off'}, {})
flush_commands()
assert(host.active_metadata() == nil, 'host retained stopped adapter')
local ready_before = count_contains('pt __controller_ready locus-signet')
local flash_before = count_contains('input /ma "Flash" <t>')
action('locus-signet','companion-ready',{
    GENERATION,'0','2','lp',PROFILE_ID,PROFILE_VERSION,
    ENGINE_VERSION,SIGNATURE,'Tackleberry','PLD','1789437000-1000000',
})
flush_commands()
now = now + 1
host_callbacks.prerender()
callbacks.prerender()
flush_commands()
assert(host.active_metadata() == nil, 'late ACK reactivated stopped host')
assert(count_contains('pt __controller_ready locus-signet') == ready_before)
assert(count_contains('input /ma "Flash" <t>') == flash_before)

os.clock = real_clock
print('Real host/Locus adapter/LocusPuller integration and stopped-late-ACK checks passed.')
