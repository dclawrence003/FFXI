local source = arg and arg[1] or 'addons/LocusPuller/LocusPuller.lua'
local profile_id = 'locus-dire-bats-tomb-signet'
local profile_version = '1.6.0'
local engine_version = '0.13.3'
local signature = 'abcdef012345'
local leader = 'Dolomedes'
local roster = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'

local now = 100
local zone = 190
local callbacks, commands, chats, ipc, scheduled, turns = {}, {}, {}, {}, {}, {}
local flash_recast = 0
local player = {id=10, index=10, name='Tackleberry', main_job='PLD', status=0,
    vitals={mp=1000}}
local me = {id=10, index=10, name='Tackleberry', spawn_type=1,
    valid_target=true, hpp=100, x=0, y=0, distance=0}
local bat = {id=100, index=100, name='Locus Dire Bat', spawn_type=16,
    valid_target=true, hpp=100, claim_id=0, x=10, y=0, distance=100}
local other_bat = {id=101, index=101, name='Locus Dire Bat', spawn_type=16,
    valid_target=true, hpp=100, claim_id=0, x=12, y=0, distance=144}
local include_other_bat = false
local selected = me

_addon = {}
local real_clock = os.clock
os.clock = function() return now end

local packets = {
    new=function(direction, id, fields)
        fields.direction, fields.packet_id = direction, id
        return fields
    end,
    inject=function(packet)
        assert(packet.direction == 'incoming' and packet.packet_id == 0x058)
        selected = packet.Target == bat.id and bat
            or packet.Target == other_bat.id and other_bat or me
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
    add_to_chat=function(_, message) chats[#chats + 1] = message end,
    send_command=function(command) commands[#commands + 1] = command end,
    send_ipc_message=function(message) ipc[#ipc + 1] = message end,
    register_event=function(name, fn) callbacks[name] = fn end,
    ffxi={
        get_player=function() return player end,
        get_info=function() return {zone=zone, logged_in=true} end,
        get_mob_by_target=function(token)
            if token == 'me' then return me end
            if token == 't' then return selected end
        end,
        get_mob_by_id=function(id)
            if id == bat.id then return bat end
            if include_other_bat and id == other_bat.id then
                return other_bat
            end
        end,
        get_mob_array=function()
            local mobs = {[me.id]=me, [bat.id]=bat}
            if include_other_bat then mobs[other_bat.id] = other_bat end
            return mobs
        end,
        get_party=function()
            return {p0={name=player.name, mob={id=player.id}}}
        end,
        get_spell_recasts=function() return {[112]=flash_recast} end,
        turn=function(angle) turns[#turns + 1] = angle end,
        run=function() error('LocusPuller attempted movement') end,
    },
}

assert(loadfile(source))()
local addon_command = callbacks['addon command']

-- Windower embeds LuaJIT/Lua 5.1, where a single closure may capture at most
-- 60 upvalues. Fengari accepts a larger closure, so explicitly enforce the
-- production runtime's limit and recurse into the command dispatch handlers.
local function assert_lua51_upvalue_limit(fn, label, seen)
    seen = seen or {}
    if seen[fn] then return end
    seen[fn] = true
    local captured = {}
    local count = 0
    while true do
        local name, value = debug.getupvalue(fn, count + 1)
        if not name then break end
        count = count + 1
        captured[#captured + 1] = {name=name, value=value}
    end
    assert(count <= 60, ('%s captures %d upvalues; Lua 5.1 allows 60')
        :format(label, count))
    for _, entry in ipairs(captured) do
        if type(entry.value) == 'function' then
            assert_lua51_upvalue_limit(entry.value,
                label..' -> '..entry.name, seen)
        end
    end
end

assert_lua51_upvalue_limit(addon_command, 'addon command')
local test_operator_revision = 0
callbacks['addon command'] = function(command, ...)
    local args = {...}
    if (command == 'bindpt' or command == 'authorize') and #args == 2 then
        args[3], args[4] = profile_id, profile_version
        args[5], args[6] = engine_version, signature
        args[7], args[8] = leader, roster
        if command == 'bindpt' then args[9], args[10] = '0', '0' end
    elseif command == 'operator' and (#args == 3 or #args == 5) then
        test_operator_revision = test_operator_revision + 1
        if #args == 5 then
            args[6] = args[5]
            args[5] = args[4]
        end
        args[4] = tostring(test_operator_revision)
    elseif command == 'retirept' and #args == 1 then
        args[2], args[3], args[4] = engine_version, profile_id,
            profile_version
        args[5], args[6] = signature, 'Smalls'
    end
    return addon_command(command, (table.unpack or unpack)(args))
end

local function run_scheduled()
    local keep = {}
    for _, job in ipairs(scheduled) do
        if job.at <= now then job.fn() else keep[#keep + 1] = job end
    end
    scheduled = keep
end

local function tick(seconds)
    now = now + (seconds or 0.2)
    run_scheduled()
    callbacks.prerender()
    run_scheduled()
end

local function command_count(value)
    local count = 0
    for _, command in ipairs(commands) do
        if command == value then count = count + 1 end
    end
    return count
end

local generation = '1800000000-123-456'
local epoch = '7'
local opener_arm = 'gs c ptgs action locus-signet opener-arm 100 '
    ..generation..' '..epoch..' 2'
local opener_release = 'gs c ptgs action locus-signet opener-release 100 '
    ..generation..' '..epoch..' 2'
local opener_release_keepoff = opener_release..' keepoff'

-- Standalone standard mode retains the original select, Flash, and delayed
-- engagement semantics and never touches AutoWS2 or a PartyTactics gate.
callbacks['addon command']('on')
tick(0.21)
assert(selected == bat, 'standard mode no longer selected the nearest bat')
assert(#turns > 0 and math.abs(turns[#turns]) < 0.001,
    'standard mode did not face the selected bat without moving')
tick(0.21)
assert(command_count('input /ma "Flash" <t>') == 1,
    'standard mode did not issue Flash')
local attacks = command_count('input /attack on')
tick(1.01)
assert(command_count('input /attack on') == attacks + 1,
    'standard mode no longer engages one second after Flash')
assert(command_count('aws2 off') == 0,
    'standard mode unexpectedly touched AutoWS2')
assert(command_count(opener_arm) == 0,
    'standard mode unexpectedly touched the PartyTactics adapter')
callbacks['addon command']('off')

-- Missing position geometry must skip only turning, without blocking the
-- otherwise valid stationary acquisition.
local turns_before_missing_geometry = #turns
selected, bat.x = me, nil
callbacks['addon command']('on')
tick(0.21)
assert(selected == bat,
    'missing facing geometry incorrectly blocked target acquisition')
assert(#turns == turns_before_missing_geometry,
    'missing facing geometry emitted an invalid turn')
callbacks['addon command']('off')
bat.x = 10

-- Exact PartyTactics binding enters first-hit mode OFF. Initial operator OFF
-- and stale operator commands cannot acquire or expose a target.
selected, player.status = me, 0
callbacks['addon command']('bindpt', generation, epoch, 'extra')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'surplus-field automatic bind was accepted')
callbacks['addon command']('bindpt', generation, epoch)
callbacks['addon command']('__ackpt', generation, epoch)
assert(command_count(
    ('gs c ptgs action locus-signet companion-ready %s %s 2 lp %s %s %s %s Tackleberry PLD')
        :format(generation, epoch, profile_id, profile_version,
            engine_version, signature)) == 1,
    'LocusPuller did not return exact actual binding metadata')
tick(2.1)
assert(selected == me, 'bound first-hit mode was not initially OFF')
callbacks['addon command']('operator', 'on', generation, '8')
tick(0.21)
assert(selected == me, 'wrong-epoch operator command armed the puller')
callbacks['addon command']('operator', 'off', generation, epoch)
callbacks['addon command']('operator', 'on', generation, epoch)
tick(0.21)
assert(selected == me,
    'first-hit mode exposed the target before adapter acknowledgment')
assert(command_count(opener_arm) == 1,
    'first-hit mode did not request the exact adapter gate')
assert(command_count('aws2 off') == 0,
    'LocusPuller duplicated the adapter-owned AutoWS2 reservation')
local release_before_periodic_operator = command_count(opener_release)
local arm_before_periodic_operator = command_count(opener_arm)
addon_command('operator', 'on', generation, epoch,
    tostring(test_operator_revision))
assert(command_count(opener_release) == release_before_periodic_operator,
    'equal/same periodic ON released an active opener')
assert(command_count(opener_arm) == arm_before_periodic_operator,
    'equal/same periodic ON restarted an active opener')
tick(0.4)
assert(command_count(opener_arm) == arm_before_periodic_operator + 1,
    'missing per-pull gate ACK was not repaired at low latency')
assert(selected == me,
    'gate delivery repair exposed the target before adapter acknowledgment')
callbacks['addon command']('__gate_armed', '100', generation, '8')
assert(selected == me, 'wrong-epoch gate acknowledgment exposed the target')
callbacks['addon command']('__gate_armed', '100', generation, epoch)
assert(selected == bat, 'exact gate acknowledgment did not select the bat')
tick(0.21)
assert(command_count('input /ma "Flash" <t>') == 2,
    'first-hit mode did not issue Flash after gate acknowledgment')
assert(command_count('input /attack on') == attacks + 1,
    'first-hit mode attacked before Flash completion')
local flash_before_dispatch_retry =
    command_count('input /ma "Flash" <t>')
callbacks['outgoing chunk'](0x01A,
    {Category=3, Param=112, Target=999, ['Target Index']=999}, nil,
    false, false)
callbacks['outgoing chunk'](0x01A,
    {Category=3, Param=112, Target=bat.id,
        ['Target Index']=bat.index}, nil, false, true)
tick(0.51)
assert(command_count('input /ma "Flash" <t>')
        == flash_before_dispatch_retry + 1,
    'missing exact outgoing Flash was not retried at low latency')
callbacks['outgoing chunk'](0x01A,
    {Category=3, Param=112, Target=bat.id,
        ['Target Index']=bat.index}, nil, false, false)
tick(0.51)
assert(command_count('input /ma "Flash" <t>')
        == flash_before_dispatch_retry + 1,
    'exact outgoing Flash did not stop dispatch retries')
local release_before_equal_heal = command_count(opener_release)
callbacks['addon command']('off')
addon_command('operator', 'on', generation, epoch,
    tostring(test_operator_revision))
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('Status: ON', 1, true),
    'equal/same operator ON did not heal a local puller OFF')
assert(command_count(opener_release) == release_before_equal_heal,
    'equal/same ON healing cancelled an in-flight Flash opener')

-- A terminal server failure is not a successful Flash and releases every
-- bounded suppression immediately.
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=4}}}}})
assert(command_count(opener_release) == 1,
    'failed Flash did not release the adapter gate')
assert(command_count('aws2 on') == 0,
    'failed Flash duplicated the adapter-owned AutoWS2 restore')

-- Retry with a successful Flash. PartyOps observed valid distant pulls taking
-- as long as 16.462 seconds after Flash to reach first melee, so missing
-- confirmation remains reserved through that window and fails open at twenty.
selected = me
local arms_before_fast_retry = command_count(opener_arm)
tick(0.21)
assert(command_count(opener_arm) == arms_before_fast_retry + 1,
    'profile 1.5 added the legacy two-second delay before Flash retry')
callbacks['addon command']('__gate_armed', '100', generation, epoch)
tick(0.21)
local attack_before_success = command_count('input /attack on')
local turns_before_success = #turns
bat.x, bat.y = -10, 0
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
assert(command_count('input /attack on') == attack_before_success + 1,
    'successful Flash did not request immediate engagement')
assert(#turns == turns_before_success + 1
        and math.abs(math.abs(turns[#turns]) - math.pi) < 0.001,
    'successful Flash did not turn toward a bat closing from behind')
local turns_before_tracking = #turns
bat.x, bat.y = 0, 10
tick(0.36)
assert(#turns == turns_before_tracking + 1
        and math.abs(turns[#turns] + math.pi / 2) < 0.001,
    'opener did not keep facing a moving bat before first melee')
tick(0.4)
assert(command_count('input /attack on') >= attack_before_success + 2,
    'idle engagement was not retried while awaiting first melee')
local releases_before_timeout = command_count(opener_release)
tick(16.1)
assert(command_count(opener_release) == releases_before_timeout,
    'valid observed Flash-to-melee latency released the adapter gate early')
tick(4.1)
assert(command_count(opener_release) == releases_before_timeout + 1,
    'twenty-second first-melee timeout did not release the adapter gate')
assert(command_count('aws2 on') == 0,
    'first-melee timeout duplicated the adapter-owned AutoWS2 restore')

-- A normal first melee releases immediately.
selected, player.status = me, 0
tick(2.1)
callbacks['addon command']('__gate_armed', '100', generation, epoch)
tick(0.21)
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
player.status = 1
local releases_before_melee = command_count(opener_release)
callbacks.action({actor_id=player.id, category=1, param=0,
    targets={{id=bat.id, actions={{message=1}}}}})
assert(command_count(opener_release) == releases_before_melee + 1,
    'first melee did not release the adapter gate')
assert(command_count('aws2 on') == 0,
    'first melee duplicated the adapter-owned AutoWS2 restore')
local turns_after_melee = #turns
tick(0.4)
assert(#turns == turns_after_melee,
    'first-melee completion did not stop opener-facing retries')

-- Alt-P/operator OFF during an active drain disables acquisition but retains
-- exact drain authority until Tackle becomes idle. Old `resume signet` cannot
-- re-enable a puller whose operator remains off.
local drained_message = ('sk __pullerdrained %s %s 1')
    :format(generation, epoch)
callbacks['addon command']('drain', generation, epoch, '1')
assert(command_count(drained_message) == 0,
    'engaged current fight was incorrectly reported as drained')
callbacks['addon command']('operator', 'off', generation, epoch)
assert(command_count(drained_message) == 0,
    'operator off discarded the in-flight idle requirement')
callbacks['addon command']('operator', 'on', generation, epoch)
assert(command_count(drained_message) == 0,
    'operator on during drain incorrectly cancelled the idle requirement')
callbacks['addon command']('operator', 'off', generation, epoch)
player.status, selected = 0, me
tick(0.21)
assert(command_count(drained_message) > 0,
    'operator-off drain did not acknowledge immediately after idle')
local arms_after_off = command_count(opener_arm)
callbacks['addon command']('resume', 'signet')
tick(3)
assert(command_count(opener_arm) == arms_after_off,
    'legacy resume re-enabled pulling while PartyTactics operator was off')

callbacks['addon command']('operator', 'off', generation, epoch, 'resume', '1')
tick(0.3)
assert(command_count(opener_arm) == arms_after_off,
    'final OFF resume enabled pulling')

-- A later exact operator ON resumes. Pre-Flash acknowledgment timeout also
-- releases both ownership surfaces. Zone exit repeats the same guarantee.
callbacks['addon command']('operator', 'on', generation, epoch)
selected = me
tick(0.21)
local release_before_confirm_timeout = command_count(opener_release)
tick(8.1)
assert(command_count(opener_release) == release_before_confirm_timeout + 1,
    'missing Flash completion did not release the adapter gate')
assert(command_count('aws2 on') == 0,
    'Flash timeout duplicated the adapter-owned AutoWS2 restore')
tick(2.1)
assert(command_count(opener_arm) >= arms_after_off + 2,
    'operator ON did not restore first-hit acquisition')
local release_before_zone = command_count(opener_release_keepoff)
callbacks['zone change']()
assert(command_count(opener_release_keepoff) == release_before_zone + 1,
    'zone change did not keepoff-release an active adapter gate')
assert(command_count('aws2 on') == 0,
    'zone change duplicated adapter AutoWS2 ownership')

-- Unbound standard mode remains available after the profile exits.
selected, player.status = me, 0
callbacks['addon command']('on')
tick(0.21)
assert(selected == bat, 'standard mode did not survive PT bind/unbind lifecycle')
callbacks['addon command']('off')

-- Normal adapter teardown uses keepoff so its nested unbind cannot undo the
-- compiler's final AutoWS2 OFF. Plain unbind remains fail-open for recovery.
selected, player.status = me, 0
local keepoff_generation = '1700000000-900-1'
callbacks['addon command']('bindpt', keepoff_generation, '0')
callbacks['addon command']('operator', 'on', keepoff_generation, '0')
tick(0.21)
local autows_before_keepoff = command_count('aws2 on')
local keepoff_release =
    ('gs c ptgs action locus-signet opener-release 100 %s 0 2 keepoff')
        :format(keepoff_generation)
local release_before_keepoff = command_count(keepoff_release)
callbacks['addon command']('unbindpt', keepoff_generation, '0', 'keepoff')
assert(command_count(keepoff_release) == release_before_keepoff + 1,
    'keepoff teardown did not release the adapter opener gate')
assert(command_count('aws2 on') == autows_before_keepoff,
    'keepoff teardown overrode PartyTactics final AutoWS2 OFF')

selected = me
local plain_generation = '1700000001-900-2'
callbacks['addon command']('bindpt', plain_generation, '0')
callbacks['addon command']('operator', 'on', plain_generation, '0')
tick(0.21)
local autows_before_plain_unbind = command_count('aws2 on')
callbacks['addon command']('unbindpt', plain_generation, '0')
assert(command_count('aws2 on') == autows_before_plain_unbind,
    'plain unbind duplicated adapter AutoWS2 ownership')

-- If drain and Alt-P arrive after the Flash command but before its action
-- packet, the in-flight opener remains owned. No idle ACK is possible until
-- Flash settles and the resulting engagement is over.
selected, player.status = me, 0
local drain_test_generation = '1700000002-900-3'
callbacks['addon command']('bindpt', drain_test_generation, '0')
local cycle_two = ('sk __pullerdrained %s %s 2')
    :format(drain_test_generation, '0')
local drain_test_cycle_one =
    ('sk __pullerdrained %s 0 1')
        :format(drain_test_generation)
local poison_cycle =
    ('sk __pullerdrained %s 0 3')
        :format(drain_test_generation)
local drain_test_arm =
    ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(drain_test_generation)
callbacks['addon command']('drain', drain_test_generation, '0', '1', 'extra')
assert(command_count(drain_test_cycle_one) == 0,
    'surplus-field drain request was accepted')
callbacks['addon command']('drain', drain_test_generation, '0', '3')
assert(command_count(poison_cycle) == 0,
    'jumped drain cycle poisoned a fresh authority')
callbacks['addon command']('drain', drain_test_generation, '0', '1')
assert(command_count(drain_test_cycle_one) == 1,
    'exact first drain cycle was not accepted after rejected jump')
callbacks['addon command']('operator', 'off', drain_test_generation, '0',
    'resume', '1')
callbacks['addon command']('operator', 'on', drain_test_generation, '0')
tick(0.21)
callbacks['addon command']('__gate_armed', '100', drain_test_generation, '0')
tick(0.21)
local cycle_two_before = command_count(cycle_two)
callbacks['addon command']('drain', drain_test_generation, '0', '2')
callbacks['addon command']('operator', 'off', drain_test_generation, '0')
local cycle_one_before_active_delay = command_count(drain_test_cycle_one)
callbacks['addon command']('drain', drain_test_generation, '0', '1')
assert(command_count(drain_test_cycle_one) == cycle_one_before_active_delay,
    'delayed cycle one overwrote an active cycle-two drain')
local arms_before_stale_resume = command_count(drain_test_arm)
callbacks['addon command']('operator', 'on', drain_test_generation, '0',
    'resume', '1')
assert(command_count(drain_test_arm) == arms_before_stale_resume,
    'delayed cycle-one resume cancelled active cycle-two drain')
tick(0.21)
assert(command_count(cycle_two) == cycle_two_before,
    'drain acknowledged while issued Flash still lacked an action result')
local attack_before_drained_flash = command_count('input /attack on')
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
assert(command_count('input /attack on') > attack_before_drained_flash,
    'successful in-flight Flash was not settled by engagement after Alt-P')
player.status = 1
callbacks.action({actor_id=player.id, category=1, param=0,
    targets={{id=bat.id, actions={{message=1}}}}})
tick(0.21)
assert(command_count(cycle_two) == cycle_two_before,
    'drain acknowledged while the Flash-pulled fight remained engaged')
player.status, selected = 0, me
tick(0.21)
assert(command_count(cycle_two) == cycle_two_before + 1,
    'drain did not acknowledge after the in-flight Flash fight settled')

-- Same-authority GearSwap rebind/marker preserves the completed cycle and
-- operator OFF. A stale prior-cycle drain cannot be replayed into cycle two.
callbacks['addon command']('gsreload', drain_test_generation, '0')
callbacks['addon command']('bindpt', drain_test_generation, '0')
local arms_before_preserved_on = command_count(drain_test_arm)
callbacks['addon command']('operator', 'on', drain_test_generation, '0')
tick(2.1)
assert(command_count(drain_test_arm) == arms_before_preserved_on,
    'same-authority rebind reset the Signet pause')
local cycle_one_count = command_count(drain_test_cycle_one)
callbacks['addon command']('drain', drain_test_generation, '0', '1')
assert(command_count(drain_test_cycle_one) == cycle_one_count,
    'delayed prior-cycle drain produced a cached acknowledgment')

-- Cached current-cycle acknowledgment still rechecks engagement.
player.status = 1
local cycle_two_acks = command_count(cycle_two)
callbacks['addon command']('drain', drain_test_generation, '0', '2')
assert(command_count(cycle_two) == cycle_two_acks,
    'cached drain acknowledgment ignored a current engagement')
player.status = 0
callbacks['addon command']('drain', drain_test_generation, '0', '2')
assert(command_count(cycle_two) == cycle_two_acks + 1,
    'idle current-cycle drain did not replay its exact acknowledgment')
callbacks['addon command']('operator', 'off', drain_test_generation, '0',
    'resume', '2')
local cycle_two_resume_revision = test_operator_revision
callbacks['addon command']('operator', 'on', drain_test_generation, '0')
tick(0.21)
addon_command('operator', 'off', drain_test_generation, '0',
    tostring(cycle_two_resume_revision), 'resume', '2')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('operator=on', 1, true),
    'delayed duplicate OFF resume overrode later Ctrl-P ON')

-- A gsreload marker alone authorizes no successor. A foreign epoch-zero bind
-- is rejected; the exact adapter authorization admits one opaque, numerically
-- lower successor. Normal unbind then accepts another future nonce, while
-- retired probes cannot erase its cycle high-water mark.
local foreign_generation = '1900000000-999-9'
callbacks['addon command']('bindpt', foreign_generation, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('gen='..drain_test_generation, 1, true),
    'foreign epoch-zero bind used a bare gsreload grace as authority')
local reload_generation = '1600000000-888-9'
callbacks['addon command']('authorize', reload_generation, '0')
callbacks['addon command']('bindpt', reload_generation, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('gen='..reload_generation, 1, true),
    'explicit recovery authorization did not admit opaque successor binding')
callbacks['addon command']('unbindpt', reload_generation, '0', 'keepoff')
local newer_generation = '1500000000-999-1'
callbacks['addon command']('bindpt', newer_generation, '0')
    local newer_cycle = ('sk __pullerdrained %s 0 3')
    :format(newer_generation)
callbacks['addon command']('drain', newer_generation, '0', '3')
assert(command_count(newer_cycle) == 0,
    'jumped cycle was accepted on replacement authority')
newer_cycle = ('sk __pullerdrained %s 0 1')
    :format(newer_generation)
callbacks['addon command']('drain', newer_generation, '0', '1')
local newer_cycle_acks = command_count(newer_cycle)
assert(newer_cycle_acks == 1,
    'newer authority did not establish its drain high-water mark')
callbacks['addon command']('bindpt', drain_test_generation, '0')
callbacks['addon command']('drain', newer_generation, '0', '1')
assert(command_count(newer_cycle) == newer_cycle_acks + 1,
    'delayed older bind replaced newer puller authority/high-water state')
callbacks['addon command']('operator', 'on', newer_generation, '0',
    'resume', '1')
local newer_resume_revision = test_operator_revision
callbacks['addon command']('operator', 'off', newer_generation, '0')
addon_command('operator', 'on', newer_generation, '0',
    tostring(newer_resume_revision), 'resume', '1')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('operator=off', 1, true),
    'delayed duplicate ON resume overrode later Alt-P OFF')
callbacks['addon command']('bindpt', newer_generation, '1')
callbacks['addon command']('bindpt', newer_generation, '0')
callbacks['addon command']('status')
local monotonic_status = chats[#chats] or ''
assert(monotonic_status:find('gen='..newer_generation, 1, true)
    and monotonic_status:find('epoch=1', 1, true),
    'same-generation lower-epoch bind rolled back puller authority')
callbacks['addon command']('unbindpt', newer_generation, '1', 'keepoff')
callbacks['addon command']('bindpt', drain_test_generation, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'retired puller authority rebound after replacement unbound')

-- Pending initial authorization is bounded. Once its 25-second window
-- expires, both a direct late bind and a late stop followed by bind must see
-- that generation as terminally consumed.
local pending_initial = '1800000788-123-788'
local conflicting_pending = '1800000789-123-789'
callbacks['addon command']('authorize', pending_initial, '0')
callbacks['addon command']('authorize', conflicting_pending, '0')
callbacks['addon command']('bindpt', conflicting_pending, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'conflicting authorization replaced a live pending puller authority')
callbacks['addon command']('bindpt', pending_initial, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('gen='..pending_initial, 1, true),
    'exact pending puller authorization did not survive a conflicting retry')
callbacks['addon command']('unbindpt', pending_initial, '0', 'keepoff')

local expired_initial_arm = '1800000790-123-790'
callbacks['addon command']('authorize', expired_initial_arm, '0')
now = now + 25.1
callbacks['addon command']('bindpt', expired_initial_arm, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'expired initial puller authorization allowed a late bind')

local expired_initial_stop = '1800000791-123-791'
callbacks['addon command']('authorize', expired_initial_stop, '0')
now = now + 25.1
callbacks['addon command']('retirept', expired_initial_stop)
callbacks['addon command']('bindpt', expired_initial_stop, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'late puller stop lost the expired initial-authority tombstone')

-- A validated PartyTactics stop can target an authorized recovery successor
-- before its delayed bind arrives. The authenticated local fence tombstones that
-- lifecycle generation and clears the old recovery binding; the queued bind
-- can never resurrect automatic pulling.
local stop_old = '1800000800-123-800'
local stop_successor = '1700000800-999-8'
callbacks['addon command']('bindpt', stop_old, '0')
callbacks['addon command']('gsreload', stop_old, '0')
callbacks['addon command']('authorize', stop_successor, '0')
callbacks['addon command']('retirept', stop_successor)
callbacks['addon command']('bindpt', stop_successor, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'delayed stopped-successor bind resurrected LocusPuller')

-- The old adapter can unbind during a full-profile reload after an exact
-- successor was authorized but before its bind arrives. Terminal callbacks
-- and an exact stop of that old handoff generation must fence the queued
-- successor even though LocusPuller is temporarily unbound.
local function enter_preserved_unbound(old_generation, new_generation)
    callbacks['addon command']('bindpt', old_generation, '0')
    callbacks['addon command']('gsreload', old_generation, '0')
    callbacks['addon command']('authorize', new_generation, '0')
    callbacks['addon command']('unbindpt', old_generation, '0', 'keepoff')
    callbacks['addon command']('status')
    assert((chats[#chats] or ''):find('PT=unbound', 1, true),
        'terminal-gap fixture did not preserve an unbound handoff')
end

local terminal_gap_cases = {
    {'zone change', function() callbacks['zone change']() end},
    {'logout', function() callbacks['logout']() end},
    {'addon unload', function() callbacks['unload']() end},
}
for index, case in ipairs(terminal_gap_cases) do
    local old_generation = ('1800000810-123-%d'):format(index)
    local new_generation = ('1700000810-999-%d'):format(index)
    enter_preserved_unbound(old_generation, new_generation)
    case[2]()
    callbacks['addon command']('bindpt', new_generation, '0')
    callbacks['addon command']('status')
    assert((chats[#chats] or ''):find('PT=unbound', 1, true),
        case[1]..' allowed a queued recovery successor to rebind LocusPuller')
end

local predecessor_stop_old = '1800000820-123-1'
local predecessor_stop_new = '1700000820-999-1'
enter_preserved_unbound(predecessor_stop_old, predecessor_stop_new)
callbacks['addon command']('retirept', predecessor_stop_old)
callbacks['addon command']('bindpt', predecessor_stop_new, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'old-generation profile stop allowed its queued puller successor to bind')

-- A preserved-unbound recovery expiring after 25 seconds consumes both the
-- detached predecessor and explicitly authorized successor. Exercise the bind
-- path that first notices expiry and the equivalent late-stop path.
local expired_arm_old = '1800000821-123-1'
local expired_arm_new = '1700000821-999-1'
enter_preserved_unbound(expired_arm_old, expired_arm_new)
now = now + 25.1
callbacks['addon command']('bindpt', expired_arm_new, '0')
callbacks['addon command']('bindpt', expired_arm_old, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'expired puller handoff allowed a late successor/predecessor bind')

local expired_stop_old = '1800000822-123-1'
local expired_stop_new = '1700000822-999-1'
enter_preserved_unbound(expired_stop_old, expired_stop_new)
now = now + 25.1
callbacks['addon command']('retirept', expired_stop_new)
callbacks['addon command']('retirept', expired_stop_old)
callbacks['addon command']('bindpt', expired_stop_new, '0')
callbacks['addon command']('bindpt', expired_stop_old, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'late puller stop lost expired handoff tombstones')

-- The puller is a monotonic replica of the leader-authored operator tuple.
-- Reordered ON cannot defeat a newer OFF, equal/conflicting is rejected, an
-- equal/same replay heals a lost local effect, and a stale captured resume
-- cannot re-enable acquisition after Alt-P.
local ordered_generation = '1800000825-123-1'
callbacks['addon command']('bindpt', ordered_generation, '0')
addon_command('operator', 'on', ordered_generation, '0', '10000')
addon_command('operator', 'off', ordered_generation, '0', '10001')
addon_command('operator', 'on', ordered_generation, '0', '10000')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('operator=off@10001', 1, true),
    'reordered lower-revision ON defeated the newer OFF')
addon_command('operator', 'on', ordered_generation, '0', '10001')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('operator=off@10001', 1, true),
    'equal-revision conflicting ON changed the operator register')
addon_command('operator', 'on', ordered_generation, '0', '10002')
addon_command('off')
addon_command('operator', 'on', ordered_generation, '0', '10002')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('Status: ON', 1, true),
    'equal/same operator replay did not heal the local pull effect')
addon_command('drain', ordered_generation, '0', '1')
addon_command('operator', 'off', ordered_generation, '0', '10003')
addon_command('operator', 'on', ordered_generation, '0', '10002',
    'resume', '1')
local ordered_resume_one = ('sk __pullerresumed %s 0 1')
    :format(ordered_generation)
assert(command_count(ordered_resume_one) == 1,
    'accepted stale-snapshot resume did not acknowledge its exact cycle')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('operator=off@10003', 1, true),
    'stale captured resume re-enabled the puller after newer OFF')
assert((chats[#chats] or ''):find('Status: OFF; mode=', 1, true)
    and (chats[#chats] or ''):find('drain=clear/-', 1, true),
    'stale captured resume did not finish the exact cycle from newer OFF')
addon_command('operator', 'off', ordered_generation, '0', '10003',
    'resume', '1')
assert(command_count(ordered_resume_one) == 2,
    'duplicate current-cycle resume did not replay its acknowledgment')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('Status: OFF; mode=', 1, true),
    'duplicate current OFF resume changed the completed maintenance state')

-- The ordinary all-ON case carries the same operator revision through the
-- maintenance transaction. Its resume clears only the exact Signet pause; it
-- does not require a fabricated newer operator transition.
addon_command('operator', 'on', ordered_generation, '0', '10004')
addon_command('drain', ordered_generation, '0', '2')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PAUSED(signet)', 1, true),
    'idle cycle-two drain did not establish the Signet pause')
addon_command('operator', 'on', ordered_generation, '0', '10004',
    'resume', '2')
assert(command_count(('sk __pullerresumed %s 0 2')
        :format(ordered_generation)) == 1,
    'ordinary ON resume did not acknowledge its exact cycle')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('Status: ON; mode=', 1, true)
    and (chats[#chats] or ''):find('drain=clear/-', 1, true),
    'equal/same ON resume left LocusPuller paused after maintenance')
callbacks['addon command']('unbindpt', ordered_generation, '0', 'keepoff')

-- Public helper controls cannot bypass an exact Signet pause while the
-- profile owns the puller. They affect no FFXI manual-action surface, and the
-- explicit local OFF command remains independently tested above.
local fenced_generation = '1800000826-123-2'
selected, player.status, bat.hpp = me, 0, 100
addon_command('bindpt', fenced_generation, '0', profile_id, profile_version,
    engine_version, signature, leader, roster, '1', '1')
addon_command('drain', fenced_generation, '0', '1')
local fenced_arms = command_count(
    ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(fenced_generation))
callbacks['addon command']('on')
callbacks['addon command']('mode', 'standard')
callbacks['addon command']('resume', 'signet')
callbacks['addon command']('now')
tick(0.21)
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PAUSED(signet)', 1, true)
    and (chats[#chats] or ''):find('mode=firsthit', 1, true),
    'public helper control bypassed the bound Signet pause or mode')
assert(command_count(
    ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(fenced_generation)) == fenced_arms,
    'public helper control acquired a target during Signet maintenance')
addon_command('unbindpt', fenced_generation, '0', 'keepoff')

-- A rapid authoritative OFF -> ON cannot forget a Flash already submitted.
-- The first target remains owned until its action result or timeout, preventing
-- a second pull from being selected while the spell is still resolving.
local inflight_generation = '1800000827-123-3'
selected, player.status, bat.hpp = me, 0, 100
addon_command('bindpt', inflight_generation, '0', profile_id,
    profile_version, engine_version, signature, leader, roster, '1', '1')
addon_command('operator', 'on', inflight_generation, '0', '1')
tick(0.21)
local inflight_arm =
    ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(inflight_generation)
assert(command_count(inflight_arm) == 1,
    'in-flight operator fixture did not acquire its first target')
addon_command('__gate_armed', '100', inflight_generation, '0')
tick(0.21)
assert(command_count('input /ma "Flash" <t>') > 0,
    'in-flight operator fixture did not submit Flash')
local inflight_release =
    ('gs c ptgs action locus-signet opener-release 100 %s 0 2')
        :format(inflight_generation)
local releases_before_toggle = command_count(inflight_release)
addon_command('operator', 'off', inflight_generation, '0', '2')
addon_command('operator', 'on', inflight_generation, '0', '3')
tick(0.21)
assert(command_count(inflight_release) == releases_before_toggle
    and command_count(inflight_arm) == 1,
    'OFF -> ON discarded an issued Flash or selected a second opener')
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
player.status = 1
callbacks.action({actor_id=player.id, category=1, param=0,
    targets={{id=bat.id, actions={{message=1}}}}})
addon_command('unbindpt', inflight_generation, '0', 'keepoff')
player.status = 0

local late_zone_generation = '1800000830-123-1'
zone = 191
callbacks['zone change']()
callbacks['addon command']('authorize', late_zone_generation, '0')
callbacks['addon command']('bindpt', late_zone_generation, '0')
callbacks['addon command']('status')
assert((chats[#chats] or ''):find('PT=unbound', 1, true),
    'late queued authority rebound LocusPuller outside the owned zone')
zone = 190

-- Loading the new helper beside frozen profile 1.3 must retain that pair's
-- original semantics: command submission counts immediately, no 1.4 packet
-- retry is introduced, and the first-melee reservation remains three seconds.
local legacy_generation = '1800000831-123-1'
selected, player.status, bat.hpp = me, 0, 100
addon_command('bindpt', legacy_generation, '0', profile_id, '1.3.0',
    engine_version, signature, leader, roster, '1', '1')
addon_command('operator', 'on', legacy_generation, '0', '1')
tick(0.21)
local legacy_arm =
    ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(legacy_generation)
assert(command_count(legacy_arm) == 1,
    'frozen 1.3 binding did not retain first-hit acquisition')
addon_command('__gate_armed', '100', legacy_generation, '0')
tick(0.21)
local legacy_flash_count = command_count('input /ma "Flash" <t>')
tick(0.6)
assert(command_count('input /ma "Flash" <t>') == legacy_flash_count,
    '1.4 outgoing-packet retries leaked into frozen profile 1.3')
callbacks.action({actor_id=player.id, category=4, param=112,
    targets={{id=bat.id, actions={{message=2}}}}})
local legacy_release =
    ('gs c ptgs action locus-signet opener-release 100 %s 0 2')
        :format(legacy_generation)
local legacy_releases = command_count(legacy_release)
tick(3.1)
assert(command_count(legacy_release) == legacy_releases + 1,
    'frozen profile 1.3 did not retain its three-second melee bound')
addon_command('unbindpt', legacy_generation, '0', 'keepoff')

-- Current Signet versions retain the fast first-hit path without changing
-- frozen 1.3 above. Distant Flash pulls may take over three seconds to reach
-- first melee, but release at the twenty-second bound. Check every version
-- introduced since the last helper update so a profile bump cannot silently
-- fall back to the legacy three-second path again.
for index, version in ipairs({'1.7.0', '1.8.0', '1.8.1'}) do
    local generation = ('1800000832-123-%d'):format(index)
    selected, player.status, bat.hpp = me, 0, 100
    addon_command('bindpt', generation, '0', profile_id, version,
        engine_version, signature, leader, roster, '1', '1')
    addon_command('operator', 'on', generation, '0', '1')
    tick(0.21)
    local arm = ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(generation)
    assert(command_count(arm) == 1,
        version..' did not acquire the first-hit adapter gate')
    addon_command('__gate_armed', '100', generation, '0')
    tick(0.21)
    callbacks.action({actor_id=player.id, category=4, param=112,
        targets={{id=bat.id, actions={{message=2}}}}})
    local release = ('gs c ptgs action locus-signet opener-release 100 %s 0 2')
        :format(generation)
    local releases = command_count(release)
    tick(3.1)
    assert(command_count(release) == releases,
        version..' regressed to the three-second melee bound')
    tick(16.8)
    assert(command_count(release) == releases,
        version..' released before twenty seconds')
    tick(0.4)
    assert(command_count(release) == releases + 1,
        version..' did not release at the twenty-second bound')
    tick(0.21)
    assert(command_count(arm) == 2,
        version..' added the legacy two-second retry delay')
    addon_command('unbindpt', generation, '0', 'keepoff')
end

-- A bat's XP reward can precede the local entity's hpp=0 update. The exact
-- dead ID/index must be skipped while it still looks alive; unrelated player
-- rewards and an index mismatch must not suppress a valid bat.
local function reward_packet(actor_id, target_id, target_index, message)
    local bytes = {}
    for i = 1, 28 do bytes[i] = 0 end
    local function write16(offset, value)
        bytes[offset + 1] = value % 256
        bytes[offset + 2] = math.floor(value / 256) % 256
    end
    local function write32(offset, value)
        write16(offset, value % 65536)
        write16(offset + 2, math.floor(value / 65536))
    end
    write32(0x04, actor_id)
    write32(0x08, target_id)
    write16(0x0E, target_index)
    write16(0x18, message)
    return string.char((table.unpack or unpack)(bytes))
end

include_other_bat = true
selected, player.status, bat.hpp = me, 0, 100
callbacks['incoming chunk'](0x02D,
    reward_packet(player.id, player.id, player.index, 371), nil,
    false, false)
callbacks['incoming chunk'](0x02D,
    reward_packet(player.id, bat.id, bat.index + 1, 372), nil,
    false, false)
callbacks['addon command']('on')
tick(2.1)
assert(selected == bat,
    'player reward or mismatched target index suppressed a live bat')
callbacks['addon command']('off')

selected = me
callbacks['incoming chunk'](0x02D,
    reward_packet(player.id, bat.id, bat.index, 372), nil,
    false, false)
callbacks['addon command']('on')
tick(2.1)
assert(bat.hpp == 100 and selected == other_bat,
    'dead-bat reward did not skip the stale positive-hpp target')
callbacks['addon command']('off')

selected = me
tick(5.1)
callbacks['addon command']('on')
tick(2.1)
assert(selected == bat,
    'expired kill tombstone permanently blacklisted a respawned bat')
callbacks['addon command']('off')
include_other_bat = false

local autows_before_logout = command_count('aws2 on')
callbacks['logout']()
assert(command_count('aws2 on') == autows_before_logout,
    'logout terminal cleanup re-enabled AutoWS2')

assert(ipc == ipc and chats == chats)
os.clock = real_clock
print('LocusPuller standard + PartyTactics runtime simulation OK')
