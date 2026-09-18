local source = arg and arg[1] or 'addons/JubileeKeeper/JubileeKeeper.lua'
local now = 100

local function make_client(name, has_ring)
    local client = {
        callbacks = {}, commands = {}, chats = {},
        zone = 190,
        equipment = {
            left_ring=1, left_ring_bag=0,
            right_ring=2, right_ring_bag=0,
        },
        bags = {
            [0] = {
                [1]={id=111,count=1}, [2]={id=222,count=1}, max=80,
            },
            [16] = {max=80, enabled=true},
        },
    }
    if has_ring then client.bags[16][7] = {id=27593,count=1} end

    local env = setmetatable({}, {__index=_G})
    env._addon = {}
    env.os = setmetatable({clock=function() return now end}, {__index=os})
    env.windower = {
        add_to_chat=function(_, message)
            client.chats[#client.chats + 1] = message
        end,
        send_command=function(command)
            client.commands[#client.commands + 1] = command
            if command == 'input /equip ring2 "Jubilee Ring"'
                and has_ring
            then
                client.equipment.right_ring = 7
                client.equipment.right_ring_bag = 16
            elseif command == 'gs enable ring2; gs c update' then
                client.equipment.right_ring = 2
                client.equipment.right_ring_bag = 0
            end
        end,
        send_ipc_message=function() end,
        register_event=function(event, fn) client.callbacks[event] = fn end,
        ffxi = {
            get_player=function() return {name=name, main_job='COR'} end,
            get_info=function() return {zone=client.zone} end,
            get_items=function(bag, index)
                if bag == nil then return {equipment=client.equipment} end
                if bag == 'equipment' then return client.equipment end
                local selected = client.bags[bag]
                if index ~= nil then return selected and selected[index] end
                return selected
            end,
        },
    }
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(source)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(source, 't', env)
    end
    assert(loader, load_error)()
    local addon_command = client.callbacks['addon command']
    client.callbacks['addon command'] = function(command, ...)
        local args = {...}
        if command == 'armpt' and #args == 4 then
            args[5] = '0.13.2'
            args[6] = 'abcdef012345'
            args[7] = 'Dolomedes'
            args[8] = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
        end
        return addon_command(command, (table.unpack or unpack)(args))
    end
    return client
end

local function count_command(client, exact)
    local count = 0
    for _, command in ipairs(client.commands) do
        if command == exact then count = count + 1 end
    end
    return count
end

local function tick(client, seconds)
    local command_count_before = #client.commands
    now = now + (seconds or 0.3)
    client.callbacks.prerender()
    -- The game applies native /equip asynchronously. Model the next frame so
    -- production code must observe raw item ID 27593 before it locks ring2.
    if #client.commands > command_count_before
        and client.commands[#client.commands]
            == 'input /equip ring2 "Jubilee Ring"'
    then
        now = now + 0.3
        client.callbacks.prerender()
    end
end

local generation = '1800000000-123-456'
local epoch = '7'
local profile_id = 'locus-dire-bats-tomb-signet'
local profile_version = '1.1.0'
local engine_version = '0.13.2'
local signature = 'abcdef012345'
local roster = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
local equip_command =
    'input /equip ring2 "Jubilee Ring"'

-- Initial activation authorization is a lifecycle fence, not a recovery
-- error. It blocks a foreign probe and lets stop-before-arm tombstone the
-- queued target.
local initial = make_client('Dolomedes', true)
local initial_generation = '1800000000-123-450'
local initial_foreign = '1800000000-123-451'
initial.callbacks['addon command']('authorize', initial_generation, '0',
    profile_id, profile_version, engine_version, signature, 'Dolomedes',
    roster)
for _, message in ipairs(initial.chats) do
    assert(not message:find('unauthorized PartyTactics recovery successor',
        1, true), 'initial authorization emitted a false recovery warning')
end
initial.callbacks['addon command']('armpt', initial_foreign, '0', profile_id,
    profile_version)
tick(initial, 0.3)
assert(count_command(initial, equip_command) == 0,
    'foreign arm bypassed pending initial Jubilee authorization')
initial.callbacks['addon command']('armpt', initial_generation, '0', profile_id,
    profile_version)
tick(initial, 0.3)
assert(count_command(initial, equip_command) == 1,
    'exact initially authorized Jubilee authority did not bind')

local initial_stopped = make_client('Dolomedes', true)
local initial_stopped_generation = '1800000000-123-452'
initial_stopped.callbacks['addon command']('authorize',
    initial_stopped_generation, '0', profile_id, profile_version,
    engine_version, signature, 'Dolomedes', roster)
initial_stopped.callbacks['addon command']('stoppt',
    initial_stopped_generation, engine_version, profile_id, profile_version,
    signature, 'Smalls')
initial_stopped.callbacks['addon command']('armpt',
    initial_stopped_generation, '0', profile_id, profile_version)
tick(initial_stopped, 0.3)
assert(count_command(initial_stopped, equip_command) == 0,
    'initial stop-before-arm resurrected Jubilee ownership')

-- Pending initial authority is bounded. The first late arm/stop after the
-- 25-second window must consume and tombstone it rather than treating it as a
-- new unfenced activation.
local expired_initial_arm = make_client('Dolomedes', true)
local expired_initial_arm_generation = '1800000000-123-453'
expired_initial_arm.callbacks['addon command']('authorize',
    expired_initial_arm_generation, '0', profile_id, profile_version,
    engine_version, signature, 'Dolomedes', roster)
now = now + 25.1
expired_initial_arm.callbacks['addon command']('armpt',
    expired_initial_arm_generation, '0', profile_id, profile_version)
tick(expired_initial_arm, 0.3)
assert(count_command(expired_initial_arm, equip_command) == 0,
    'expired initial Jubilee authorization allowed a late arm')

local expired_initial_stop = make_client('Dolomedes', true)
local expired_initial_stop_generation = '1800000000-123-454'
expired_initial_stop.callbacks['addon command']('authorize',
    expired_initial_stop_generation, '0', profile_id, profile_version,
    engine_version, signature, 'Dolomedes', roster)
now = now + 25.1
expired_initial_stop.callbacks['addon command']('stoppt',
    expired_initial_stop_generation, engine_version, profile_id,
    profile_version, signature, 'Smalls')
expired_initial_stop.callbacks['addon command']('armpt',
    expired_initial_stop_generation, '0', profile_id, profile_version)
tick(expired_initial_stop, 0.3)
assert(count_command(expired_initial_stop, equip_command) == 0,
    'late Jubilee stop lost the expired initial-authority tombstone')

local dolo = make_client('Dolomedes', true)
tick(dolo, 1)
assert(#dolo.commands == 0, 'addon was not inert before PartyTactics arm')
dolo.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
dolo.callbacks['addon command']('__ackpt', generation, epoch)
assert(count_command(dolo,
    ('gs c ptgs action locus-signet companion-ready %s %s 2 jk %s %s %s %s Dolomedes COR')
        :format(generation, epoch, profile_id, profile_version,
            engine_version, signature)) == 1,
    'JubileeKeeper did not return exact actual binding metadata')
tick(dolo, 0.3)
assert(count_command(dolo, equip_command) == 1,
    'exact local arm did not equip and lock Jubilee Ring without IPC loopback')
assert(dolo.equipment.left_ring == 1 and dolo.equipment.left_ring_bag == 0,
    'Jubilee guard touched the left ring')
tick(dolo, 0.3)
assert(count_command(dolo, 'gs disable ring2') == 1,
    'raw confirmation did not install the ring2 lock exactly once')

-- Simulate external displacement and a GearSwap reload.
dolo.equipment.right_ring = 2
dolo.equipment.right_ring_bag = 0
tick(dolo, 2)
assert(count_command(dolo, equip_command) == 2,
    'external ring displacement was not repaired')
local refreshes = count_command(dolo, 'gs disable ring2')
tick(dolo, 2.1)
assert(count_command(dolo, 'gs disable ring2') == refreshes,
    'ordinary polling spammed a redundant GearSwap ring2 disable')

-- An exact GearSwap-reload marker retains the physical guard. An idempotent
-- old-authority probe must not erase the explicit successor fence.
local releases_before_reload = count_command(dolo,
    'gs enable ring2; gs c update')
dolo.callbacks['addon command']('gsreload', generation, epoch)
tick(dolo, 2.1)
assert(count_command(dolo, 'gs disable ring2') == refreshes + 1,
    'validated GearSwap reload did not reassert the ring2 lock exactly once')
assert(count_command(dolo, 'gs enable ring2; gs c update')
    == releases_before_reload,
    'GearSwap reload marker released Jubilee ownership')
dolo.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(dolo, 2)
assert(count_command(dolo, 'gs enable ring2; gs c update')
    == releases_before_reload,
    'same-authority rebind released the ring during recovery')

-- Full recovery admits only its explicitly authorized opaque successor.
-- Merely arriving as a different generation at epoch zero during the grace
-- period is insufficient.
local replacement = make_client('Dolomedes', true)
local replacement_generation = '1700000001-999-1'
local foreign_generation = '1800000002-123-458'
replacement.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(replacement, 0.3)
replacement.callbacks['addon command']('gsreload', generation, epoch)
replacement.callbacks['addon command'](
    'armpt', foreign_generation, '0', profile_id, profile_version)
replacement.callbacks['addon command']('detach', foreign_generation, '0')
local replacement_releases = count_command(replacement,
    'gs enable ring2; gs c update')
assert(replacement_releases == 0,
    'foreign epoch-zero probe displaced the old ring authority')
replacement.callbacks['addon command'](
    'authorize', replacement_generation, '0', profile_id, profile_version,
    engine_version, signature, 'Dolomedes', roster)
replacement.callbacks['addon command']('detach', generation, epoch)
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases,
    'recovery teardown released the physical ring lock before successor arm')
replacement.callbacks['addon command'](
    'armpt', replacement_generation, '0', profile_id, profile_version)
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases,
    'stale old detach released the authorized successor ring guard')
tick(replacement, 26)
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases,
    'old reload deadline released a newer-generation ring guard')
replacement.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
replacement.callbacks['addon command']('detach', generation, epoch)
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases,
    'delayed older arm probe replaced the newer ring authority')
replacement.callbacks['addon command'](
    'armpt', replacement_generation, '1', profile_id, profile_version)
replacement.callbacks['addon command'](
    'armpt', replacement_generation, '0', profile_id, profile_version)
replacement.callbacks['addon command']('detach', replacement_generation, '0')
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases,
    'same-generation lower-epoch arm probe replaced the current authority')
replacement.callbacks['addon command']('detach', replacement_generation, '1')
assert(count_command(replacement, 'gs enable ring2; gs c update')
    == replacement_releases + 1,
    'same-generation higher-epoch authority was not accepted')
local replacement_equips = count_command(replacement, equip_command)
replacement.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(replacement, 0.3)
assert(count_command(replacement, equip_command) == replacement_equips,
    'retired old arm rebound after replacement detached')

-- PartyTactics 0.13.2 stop uses field 3 as a request nonce and field 10 as
-- the exact authority being stopped. Only the strict ten-field authenticated
-- schema may release ring ownership.
local stopper = make_client('Dolomedes', true)
stopper.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(stopper, 0.3)
local stop_request = '1999999999-777-3'
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','wrong-target',
    '1999999998-777-2',
}, '|'))
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','extra-field',generation,'extra',
}, '|'))
assert(count_command(stopper, 'gs enable ring2; gs c update') == 0,
    'wrong-target or non-exact stop schema released ring2')
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','exact-target',generation,
}, '|'))
assert(count_command(stopper, 'gs enable ring2; gs c update') == 1,
    'field-10 exact stop did not release ring2')

-- The no-loopback local stop fence can retire an authorized recovery
-- successor before its queued arm arrives. Surplus fields are rejected, while
-- the exact six-argument fence releases the old guard and tombstones the new
-- lifecycle generation.
local stopped_successor = make_client('Dolomedes', true)
local stopped_old = '1800000090-123-490'
local stopped_new = '1700000090-999-4'
stopped_successor.callbacks['addon command'](
    'armpt', stopped_old, '4', profile_id, profile_version)
tick(stopped_successor, 0.3)
stopped_successor.callbacks['addon command']('gsreload', stopped_old, '4')
stopped_successor.callbacks['addon command'](
    'authorize', stopped_new, '0', profile_id, profile_version,
    engine_version, signature, 'Dolomedes', roster)
stopped_successor.callbacks['addon command']('stoppt', stopped_new,
    engine_version, profile_id, profile_version, signature, 'Smalls', 'extra')
assert(count_command(stopped_successor,
    'gs enable ring2; gs c update') == 0,
    'surplus-field local stop fence altered Jubilee ownership')
stopped_successor.callbacks['addon command']('stoppt', stopped_new,
    engine_version, profile_id, profile_version, signature, 'Smalls')
stopped_successor.callbacks['addon command'](
    'armpt', stopped_new, '0', profile_id, profile_version)
tick(stopped_successor, 0.3)
assert(count_command(stopped_successor,
    'gs enable ring2; gs c update') == 1,
    'delayed stopped-successor arm resurrected Jubilee ownership')

-- The old adapter can detach after naming its exact recovery successor but
-- before that successor arm is delivered. Every terminal path must release
-- ring2 from this preserved-unarmed gap and tombstone the queued successor.
local function preserved_unarmed_client(old_generation, new_generation)
    local client = make_client('Dolomedes', true)
    client.callbacks['addon command'](
        'armpt', old_generation, '4', profile_id, profile_version)
    tick(client, 0.3)
    client.callbacks['addon command']('gsreload', old_generation, '4')
    client.callbacks['addon command'](
        'authorize', new_generation, '0', profile_id, profile_version,
        engine_version, signature, 'Dolomedes', roster)
    client.callbacks['addon command']('detach', old_generation, '4')
    assert(count_command(client, 'gs enable ring2; gs c update') == 0,
        'test setup did not preserve ring2 across old-authority detach')
    return client
end

local terminal_cases = {
    {'manual off', function(client)
        client.callbacks['addon command']('off')
    end},
    {'zone change', function(client) client.callbacks['zone change']() end},
    {'logout', function(client) client.callbacks['logout']() end},
    {'addon unload', function(client) client.callbacks['unload']() end},
}
for index, case in ipairs(terminal_cases) do
    local old_generation = ('1800000200-123-%d'):format(index)
    local new_generation = ('1700000200-999-%d'):format(index)
    local client = preserved_unarmed_client(old_generation, new_generation)
    case[2](client)
    assert(count_command(client, 'gs enable ring2; gs c update') == 1,
        case[1]..' did not release ring2 in the preserved-unarmed gap')
    local equips = count_command(client, equip_command)
    client.callbacks['addon command'](
        'armpt', new_generation, '0', profile_id, profile_version)
    tick(client, 0.3)
    assert(count_command(client, equip_command) == equips,
        case[1]..' allowed the stopped recovery successor to reacquire ring2')
end

local stopped_predecessor_old = '1800000300-123-1'
local stopped_predecessor_new = '1700000300-999-1'
local stopped_predecessor = preserved_unarmed_client(
    stopped_predecessor_old, stopped_predecessor_new)
stopped_predecessor.callbacks['addon command']('stoppt',
    stopped_predecessor_old, engine_version, profile_id, profile_version,
    signature, 'Smalls')
assert(count_command(stopped_predecessor,
    'gs enable ring2; gs c update') == 1,
    'exact old-generation profile stop did not release preserved ring2')
local predecessor_equips = count_command(stopped_predecessor, equip_command)
stopped_predecessor.callbacks['addon command'](
    'armpt', stopped_predecessor_new, '0', profile_id, profile_version)
tick(stopped_predecessor, 0.3)
assert(count_command(stopped_predecessor, equip_command) == predecessor_equips,
    'old-generation profile stop allowed its queued successor to reacquire ring2')

-- Expiring a preserved-unarmed recovery fences both the old detached
-- generation and its named successor. Cover the arm path that first notices
-- expiry and a stop delivered after the metadata window.
local expired_arm_old = '1800000301-123-1'
local expired_arm_new = '1700000301-999-1'
local expired_arm = preserved_unarmed_client(expired_arm_old, expired_arm_new)
local expired_arm_equips = count_command(expired_arm, equip_command)
now = now + 25.1
expired_arm.callbacks['addon command'](
    'armpt', expired_arm_new, '0', profile_id, profile_version)
expired_arm.callbacks['addon command'](
    'armpt', expired_arm_old, '4', profile_id, profile_version)
tick(expired_arm, 0.3)
assert(count_command(expired_arm, equip_command) == expired_arm_equips,
    'expired Jubilee handoff allowed a late successor/predecessor arm')
assert(count_command(expired_arm, 'gs enable ring2; gs c update') == 1,
    'expired Jubilee handoff did not release preserved ring2')

local expired_stop_old = '1800000302-123-1'
local expired_stop_new = '1700000302-999-1'
local expired_stop = preserved_unarmed_client(
    expired_stop_old, expired_stop_new)
local expired_stop_equips = count_command(expired_stop, equip_command)
now = now + 25.1
expired_stop.callbacks['addon command']('stoppt', expired_stop_new,
    engine_version, profile_id, profile_version, signature, 'Smalls')
expired_stop.callbacks['addon command']('stoppt', expired_stop_old,
    engine_version, profile_id, profile_version, signature, 'Smalls')
tick(expired_stop, 0.3)
expired_stop.callbacks['addon command'](
    'armpt', expired_stop_new, '0', profile_id, profile_version)
expired_stop.callbacks['addon command'](
    'armpt', expired_stop_old, '4', profile_id, profile_version)
tick(expired_stop, 0.3)
assert(count_command(expired_stop, equip_command) == expired_stop_equips,
    'late Jubilee stop lost expired handoff tombstones')
assert(count_command(expired_stop, 'gs enable ring2; gs c update') == 1,
    'late Jubilee stop did not release expired preserved ring2')

-- Stale/mismatched detach authority cannot release the slot.
dolo = make_client('Dolomedes', true)
dolo.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(dolo, 0.3)
dolo.callbacks['addon command']('detach', generation, '8')
tick(dolo, 0.3)
assert(count_command(dolo, 'gs enable ring2; gs c update') == 0,
    'wrong-epoch detach released ring2')

-- Once a matching state was actually observed, its silence becomes valid
-- liveness evidence and releases the slot. The exact tuple remains recoverable
-- only after both a fresh matching PT state and a local adapter arm reproof.
local state_message = table.concat({
    'PARTYTACTICS1','state',generation,engine_version,profile_id,
    profile_version,signature,'Dolomedes',roster,epoch,
    '-','-','-','1','1',
}, '|')
dolo.callbacks['ipc message'](state_message..'|extra')
tick(dolo, 13)
assert(count_command(dolo, 'gs enable ring2; gs c update') == 0,
    'surplus-field PartyTactics state established false liveness')
dolo.callbacks['ipc message'](state_message)
tick(dolo, 13)
assert(count_command(dolo, 'gs enable ring2; gs c update') == 1,
    'stale observed PartyTactics state did not release ring2')
local stale_equip_count = count_command(dolo, equip_command)
local stale_lock_count = count_command(dolo, 'gs disable ring2')
tick(dolo, 0.3)
dolo.callbacks['ipc message'](state_message)
tick(dolo, 0.3)
assert(count_command(dolo, equip_command) == stale_equip_count
    and count_command(dolo, 'gs disable ring2') == stale_lock_count,
    'a fresh PT state alone reclaimed Jubilee ownership after stale lease')
dolo.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(dolo, 0.3)
assert(count_command(dolo, equip_command) == stale_equip_count + 1
    and count_command(dolo, 'gs disable ring2') == stale_lock_count + 1,
    'fresh PT state plus exact adapter arm failed to reclaim ring2')

local stale_stopped = make_client('Dolomedes', true)
stale_stopped.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(stale_stopped, 0.3)
stale_stopped.callbacks['ipc message'](state_message)
tick(stale_stopped, 13)
stale_stopped.callbacks['addon command']('stoppt', generation,
    engine_version, profile_id, profile_version, signature, 'Smalls')
local stopped_equips = count_command(stale_stopped, equip_command)
stale_stopped.callbacks['ipc message'](state_message)
stale_stopped.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(stale_stopped, 0.3)
assert(count_command(stale_stopped, equip_command) == stopped_equips,
    'terminally stopped stale authority reacquired Jubilee ring2')

-- Current/newer conflicting PartyTactics state is immediate departure proof.
local next_generation = '1800000100-123-999'
dolo.callbacks['addon command'](
    'armpt', generation, '8', profile_id, profile_version)
tick(dolo, 0.3)
local releases_before_old_epoch = count_command(dolo,
    'gs enable ring2; gs c update')
dolo.callbacks['ipc message'](state_message)
assert(count_command(dolo, 'gs enable ring2; gs c update')
    == releases_before_old_epoch,
    'delayed lower-epoch state released newer ring ownership')
local conflicting = table.concat({
    'PARTYTACTICS1','state',next_generation,engine_version,'another-profile',
    '9.9.9','fedcba987654','Dolomedes',roster,'1','-','-','-','1','0',
}, '|')
dolo.callbacks['ipc message'](conflicting)
assert(count_command(dolo, 'gs enable ring2; gs c update') == 2,
    'newer conflicting PartyTactics state did not release ring2')

-- Exact detach and zoning are also deterministic exits.
-- Generation nonces are opaque: after normal detach, a numerically lower
-- different-initiator generation is legitimate and must be accepted.
local lower_generation = '1700000000-999-1'
dolo.callbacks['addon command'](
    'armpt', lower_generation, '0', profile_id, profile_version)
tick(dolo, 0.3)
dolo.callbacks['addon command']('detach', lower_generation, '0')
assert(count_command(dolo, 'gs enable ring2; gs c update') == 3,
    'exact adapter detach did not release ring2')
dolo.callbacks['addon command'](
    'armpt', next_generation, '1', profile_id, profile_version)
tick(dolo, 0.3)
dolo.callbacks['addon command'](
    'armpt', lower_generation, '0', profile_id, profile_version)
dolo.callbacks['addon command']('detach', lower_generation, '0')
assert(count_command(dolo, 'gs enable ring2; gs c update') == 3,
    'retired pre-transition arm rebound after a newer profile was active')
dolo.callbacks['zone change']()
assert(count_command(dolo, 'gs enable ring2; gs c update') == 4,
    'zone change did not release ring2')

dolo.callbacks['addon command'](
    'armpt', next_generation, '2', profile_id, profile_version)
tick(dolo, 0.3)
dolo.callbacks['logout']()
assert(count_command(dolo, 'gs enable ring2; gs c update') == 5,
    'logout did not release ring2')

local equipped_before = count_command(dolo, equip_command)
tick(dolo, 3)
assert(count_command(dolo, equip_command) == equipped_before,
    'detached addon continued equipping Jubilee Ring')

local follower = make_client('Smalls', true)
follower.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(follower, 1)
assert(#follower.commands == 0,
    'non-Dolomedes client was allowed to own a ring slot')

local missing = make_client('Dolomedes', false)
missing.callbacks['addon command'](
    'armpt', generation, epoch, profile_id, profile_version)
tick(missing, 1)
assert(#missing.commands == 0,
    'missing Jubilee Ring caused a ring-slot lock')
local warned = false
for _, message in ipairs(missing.chats) do
    if message:find('not in Inventory or an enabled Mog Wardrobe', 1, true) then
        warned = true
    end
end
assert(warned, 'missing Jubilee Ring warning was not emitted')

-- A lifecycle command queued before zoning cannot acquire the ring after the
-- zone callback has already run, even if the addon had not seen its authority
-- at the time of that callback.
local late_after_zone = make_client('Dolomedes', true)
late_after_zone.zone = 191
late_after_zone.callbacks['zone change']()
late_after_zone.callbacks['addon command']('authorize', generation, '0',
    profile_id, profile_version, engine_version, signature, 'Dolomedes',
    roster)
late_after_zone.callbacks['addon command'](
    'armpt', generation, '0', profile_id, profile_version)
tick(late_after_zone, 0.3)
assert(count_command(late_after_zone, equip_command) == 0,
    'late queued authority acquired Jubilee Ring outside the owned zone')

print('JubileeKeeper PartyTactics runtime simulation OK')
