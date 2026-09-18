local source = arg and arg[1] or 'addons/SignetKeeper/SignetKeeper.lua'
local names = {
    'Achoo','Barneystinson','Dolomedes','Kickpuncher','Smalls','Tackleberry',
}
local jobs = {
    Achoo='GEO', Barneystinson='BRD', Dolomedes='COR',
    Kickpuncher='DNC', Smalls='RDM', Tackleberry='PLD',
}
local generation = '1800000000-123-456'
local epoch = 7
local profile_id = 'locus-dire-bats-tomb-signet'
local profile_version = '1.1.0'
local engine_version = '0.13.2'
local signature = 'abcdef012345'
local roster = table.concat(names, ',')
local weapon_restore_command =
    'gs enable main sub; gs c weapons; gs c update auto'
local now = 100
local network = {}
local clients = {}
local heartbeat_operator = nil
local drop_message = nil

local function make_client(name)
    local client = {
        name=name, callbacks={}, commands={}, chats={}, buffs={253},
        status=0, adapter_ack=true, resume_ack=true,
        restore_equipment=true,
        puller_resume_ack=true, zone=190,
        equipment={main=2, main_bag=0, sub=3, sub_bag=0},
        inventory={
            [1]={id=17583,count=1,enchantment={
                type='Enchanted Equipment', charges_remaining=25,
                usable=true,
            }},
            [2]={id=999,count=1},
            [3]={id=998,count=1},
            [4]={id=997,count=1},
            [5]={id=996,count=1}, max=80,
        },
    }
    local env = setmetatable({}, {__index=_G})
    env._addon = {}
    env.os = setmetatable({clock=function() return now end}, {__index=os})
    env.require = function(module)
        if module == 'extdata' then
            return {decode=function(item) return item.enchantment end}
        end
        return require(module)
    end
    env.windower = {
        add_to_chat=function(_, message)
            client.chats[#client.chats + 1] = message
        end,
        send_ipc_message=function(message)
            network[#network + 1] = {sender=name, message=message}
        end,
        send_command=function(command)
            client.commands[#client.commands + 1] = command
            if command == 'input /equip main "Kgd. Signet Staff"' then
                client.equipment.main, client.equipment.main_bag = 1, 0
                client.equipment.sub, client.equipment.sub_bag = 0, 0
            elseif command == weapon_restore_command then
                if client.restore_equipment == true then
                    client.equipment.main, client.equipment.main_bag = 2, 0
                    client.equipment.sub, client.equipment.sub_bag = 3, 0
                elseif client.restore_equipment == 'wrong-sub' then
                    client.equipment.main, client.equipment.main_bag = 2, 0
                    client.equipment.sub, client.equipment.sub_bag = 0, 0
                elseif client.restore_equipment == 'unreadable-sub' then
                    client.equipment.main, client.equipment.main_bag = 2, 0
                    client.equipment.sub, client.equipment.sub_bag = 99, 0
                elseif client.restore_equipment == 'alternate' then
                    client.equipment.main, client.equipment.main_bag = 4, 0
                    client.equipment.sub, client.equipment.sub_bag = 5, 0
                elseif client.restore_equipment == 'alternate-empty-sub' then
                    client.equipment.main, client.equipment.main_bag = 4, 0
                    client.equipment.sub, client.equipment.sub_bag = 0, 0
                end
            end
            local prefix = 'gs c ptgs action locus-signet suspend '
            if client.adapter_ack and command:sub(1, #prefix) == prefix then
                local gen, ep, cycle = command:match(
                    '^gs c ptgs action locus%-signet suspend ([^ ]+) ([^ ]+) 2 ([^ ]+)$')
                assert(gen and ep and cycle,
                    'malformed suspend command: '..command)
                client.callbacks['addon command'](
                    '__adapter', gen, name, ep, 'suspended', cycle)
            end
            local resume_prefix = 'gs c ptgs action locus-signet resume '
            if client.resume_ack
                and command:sub(1, #resume_prefix) == resume_prefix
            then
                local gen, ep, cycle = command:match(
                    '^gs c ptgs action locus%-signet resume ([^ ]+) ([^ ]+) 2 [^ ]+ [01] ([^ ]+)$')
                assert(gen and ep and cycle,
                    'malformed resume command: '..command)
                -- The 1.6 adapter uses this local cross-addon bridge. The
                -- keeper's next report distributes the resulting state.
                client.callbacks['addon command'](
                    '__adapter', gen, name, ep, 'resumed', cycle)
            end
            if name == 'Tackleberry' and client.puller_resume_ack
                and command:match('^lp operator [^ ]+ [^ ]+ [^ ]+ [^ ]+ resume [^ ]+$')
            then
                local gen, ep, cycle = command:match(
                    '^lp operator [^ ]+ ([^ ]+) ([^ ]+) [^ ]+ resume ([^ ]+)$')
                assert(gen and ep and cycle,
                    'malformed puller resume command: '..command)
                client.callbacks['addon command'](
                    '__pullerresumed', gen, ep, cycle)
            end
        end,
        register_event=function(event, fn) client.callbacks[event] = fn end,
        ffxi={
            get_player=function()
                return {id=10, name=name, status=client.status,
                    main_job=jobs[name], buffs=client.buffs}
            end,
            get_info=function() return {zone=client.zone} end,
            get_items=function(bag, slot)
                if bag == nil then return {equipment=client.equipment} end
                if bag == 'equipment' then return client.equipment end
                if bag == 'inventory' or bag == 0 and slot == nil then
                    return client.inventory
                end
                if bag == 0 and slot then return client.inventory[slot] end
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
        if command == 'armpt' and #args == 6 then
            args[7], args[8] = engine_version, signature
            args[9], args[10] = '0', '0'
        elseif command == 'armpt' and #args == 8 then
            args[9], args[10] = '0', '0'
        end
        return addon_command(command, (table.unpack or unpack)(args))
    end
    clients[name] = client
    return client
end

for _, name in ipairs(names) do make_client(name) end

for name, client in pairs(clients) do
    local announcements = 0
    for _, command in ipairs(client.commands) do
        if command:match(
            '^gs c ptgs action locus%-signet keeper%-instance %d+%-%d+$')
        then
            announcements = announcements + 1
        end
    end
    assert(announcements == 1,
        name..' did not emit one inert keeper-instance load announcement')
end

local function flush()
    local rounds = 0
    while #network > 0 do
        rounds = rounds + 1
        assert(rounds < 100, 'IPC did not quiesce')
        local batch = network
        network = {}
        for _, packet in ipairs(batch) do
            for name, client in pairs(clients) do
                -- Windower IPC does not promise sender loopback. The harness
                -- intentionally withholds it to exercise local ACK/report paths.
                if name ~= packet.sender
                    and not (drop_message and drop_message(packet, name))
                then
                    client.callbacks['ipc message'](packet.message)
                end
            end
        end
    end
end

local function tick(seconds, excluded)
    now = now + (seconds or 1)
    for name, client in pairs(clients) do
        if name ~= excluded then
            if heartbeat_operator then
                client.callbacks['addon command']('operator',
                    heartbeat_operator.generation,
                    tostring(heartbeat_operator.epoch),
                    tostring(heartbeat_operator.revision),
                    heartbeat_operator.bit)
            end
            client.callbacks.prerender()
        end
    end
    flush()
end

local function tick_for(total, step, excluded)
    step = step or 1
    local remaining = total
    while remaining > 0 do
        local delta = math.min(step, remaining)
        tick(delta, excluded)
        remaining = remaining - delta
    end
end

local function count_command(client, exact)
    local count = 0
    for _, command in ipairs(client.commands) do
        if command == exact then count = count + 1 end
    end
    return count
end

local function has_command(client, exact)
    return count_command(client, exact) > 0
end

local function status_header(client)
    client.callbacks['addon command']('status')
    for index = #client.chats, 1, -1 do
        if client.chats[index]:find('generation=', 1, true) then
            return client.chats[index]
        end
    end
    return ''
end

local function status_weapon_detail(client)
    client.callbacks['addon command']('status')
    for index = #client.chats, 1, -1 do
        if client.chats[index]:find('raw-main=', 1, true) then
            return client.chats[index]
        end
    end
    return ''
end

local function status_terminal_detail(client)
    client.callbacks['addon command']('status')
    for index = #client.chats, 1, -1 do
        if client.chats[index]:find('last-terminal=', 1, true) then
            return client.chats[index]
        end
    end
    return ''
end

local operator_states = {}
local function state_operator_tuple(gen, operator, revision)
    local previous = operator_states[gen]
    if revision == nil then
        revision = previous and previous.revision or 1
        if previous and previous.operator ~= operator then
            revision = revision + 1
        end
    end
    operator_states[gen] = {revision=revision, operator=operator}
    return revision, operator and '1' or '0'
end

local function pt_state(operator, revision)
    local operator_revision, operator_bit = state_operator_tuple(
        generation, operator, revision)
    return table.concat({
        'PARTYTACTICS1','state',generation,engine_version,profile_id,
        profile_version,signature,'Dolomedes',roster,tostring(epoch),
        '-','-','-',tostring(operator_revision),operator_bit,
    }, '|')
end

for _, client in pairs(clients) do
    client.callbacks['addon command']('armpt', generation, tostring(epoch),
        'Dolomedes', roster, profile_id, profile_version)
end
flush()

for name, client in pairs(clients) do
    client.callbacks['addon command']('__ackpt', generation, tostring(epoch))
    local prefix =
        ('gs c ptgs action locus-signet companion-ready %s %d 2 sk %s %s %s %s %s %s ')
            :format(generation, epoch, profile_id, profile_version,
                engine_version, signature, name, jobs[name])
    local matched_command = nil
    for _, command in ipairs(client.commands) do
        local nonce = command:sub(1, #prefix) == prefix
            and command:sub(#prefix + 1) or nil
        if nonce and nonce:match('^%d+%-%d+$') then
            matched_command = command
            break
        end
    end
    assert(matched_command,
        name..' did not return exact binding metadata and keeper nonce')
    client.callbacks['addon command']('__ackpt', generation, tostring(epoch))
    assert(count_command(client, matched_command) == 2,
        name..' changed its keeper nonce within one Lua instance')
end

-- The real cross-addon heartbeat is the adapter's exact local `sk operator`
-- command on every client. Raw PartyTactics IPC is intentionally absent.
local heartbeat_revision, heartbeat_bit = state_operator_tuple(
    generation, true)
heartbeat_operator = {
    generation=generation, epoch=epoch, revision=heartbeat_revision,
    bit=heartbeat_bit,
}
for _, client in pairs(clients) do
    client.callbacks['addon command']('operator', generation,
        tostring(epoch), tostring(heartbeat_revision), heartbeat_bit)
end
assert(not has_command(clients.Tackleberry,
    ('lp operator on %s %s 1'):format(generation, epoch)),
    'initial operator ON escaped before the six-client Signet census')
for _, client in pairs(clients) do
    assert(not has_command(client, 'pc off'),
        'startup census shut down PartyCombat before the drain barrier')
end
for _, client in pairs(clients) do client.buffs = {} end
tick(1)
tick(1.1)
tick(1.1)
tick(1.1)
assert(has_command(clients.Tackleberry,
    ('lp drain %s %s 1'):format(generation, epoch)),
    'all-missing consensus did not request an exact puller drain')
local puller_drain = ('lp drain %s %s 1'):format(generation, epoch)
local first_drain_requests = count_command(clients.Tackleberry, puller_drain)
tick(1.1)
assert(count_command(clients.Tackleberry, puller_drain)
        > first_drain_requests,
    'unacknowledged exact puller drain was not retried automatically')
for _, client in pairs(clients) do
    assert(not has_command(client,
        ('gs c ptgs action locus-signet suspend %s %s 2 1')
            :format(generation, epoch)),
        'automation suspended before explicit puller drain acknowledgment')
end

-- Wrong-epoch evidence cannot advance the transaction.
network[#network + 1] = {
    sender='external',
    message=('SIGNETKEEPER1|pullerdrained|%s|Tackleberry|%s|1|extra')
        :format(generation, epoch),
}
network[#network + 1] = {
    sender='external',
    message=('SIGNETKEEPER1|pullerdrained|%s|Tackleberry|%s|1')
        :format(generation, epoch + 1),
}
flush()
tick(3)
for _, client in pairs(clients) do
    assert(not has_command(client,
        ('gs c ptgs action locus-signet suspend %s %s 2 1')
            :format(generation, epoch)),
        'wrong-epoch drain acknowledgment advanced the transaction')
end

clients.Tackleberry.callbacks['addon command'](
    '__pullerdrained', generation, tostring(epoch), '1')
flush()
clients.Kickpuncher.status = 1
tick(3)
for _, client in pairs(clients) do
    assert(not has_command(client,
        ('gs c ptgs action locus-signet suspend %s %s 2 1')
            :format(generation, epoch)),
        'one engaged member did not hold the idle barrier')
end
clients.Kickpuncher.status = 0
clients.Achoo.adapter_ack = false
tick(1)
tick(1.1)
tick(1.1)

-- Withhold one adapter ACK. All six receive suspend, but no staff slot can be
-- touched until the missing local+IPC acknowledgment arrives.
tick(1.1)
tick(0.5)
local suspend_command = ('gs c ptgs action locus-signet suspend %s %s 2 1')
    :format(generation, epoch)
for _, client in pairs(clients) do
    assert(has_command(client, suspend_command),
        'idle barrier did not request adapter suspend on '..client.name
            ..': '..table.concat(client.commands, ' || ')
            ..' CHATS '..table.concat(clients.Dolomedes.chats, ' || '))
    assert(not has_command(client, 'gs disable main sub'),
        'staff phase started before the six-adapter barrier')
end

clients.Achoo.callbacks['addon command'](
    '__adapter', generation, 'Achoo', tostring(epoch), 'suspended', '1',
    'extra')
network[#network + 1] = {
    sender='Achoo',
    message=('SIGNETKEEPER1|adapter|%s|Achoo|%s|suspended|1|extra')
        :format(generation, epoch),
}
flush()
tick(1.1)
assert(not has_command(clients.Dolomedes, 'gs disable main sub'),
    'surplus-field adapter acknowledgment advanced staff work')

clients.Achoo.callbacks['addon command'](
    '__adapter', generation, 'Achoo', tostring(epoch), 'suspended', '1')
network[#network + 1] = {
    sender='Achoo',
    message=('SIGNETKEEPER1|adapter|%s|Achoo|%s|suspended|1')
        :format(generation, epoch),
}
flush()
-- A valid nonstaff pair can still be a transient action set. The apply phase
-- must reapply GearSwap's selected Weapons mode and stabilize 2/3 instead of
-- snapshotting this temporary 4/5 pair.
clients.Dolomedes.equipment.main, clients.Dolomedes.equipment.main_bag = 4, 0
clients.Dolomedes.equipment.sub, clients.Dolomedes.equipment.sub_bag = 5, 0
tick(1)
tick(1)
tick(0.1)
tick_for(4, 1)
for _, client in pairs(clients) do
    assert(has_command(client, 'gs disable main sub'),
        'six fresh suspend acknowledgments did not start staff work')
end
tick(0.6)
tick(0.1)
for _, client in pairs(clients) do
    assert(has_command(client, 'input /equip main "Kgd. Signet Staff"'),
        'staff was not equipped after slot ownership')
    assert(not has_command(client, 'input /item "Kgd. Signet Staff" <me>'),
        'staff fired before the observed-equipped delay')
end

-- A GearSwap reload can erase disabled-slot state without moving the staff.
local locks = count_command(clients.Dolomedes, 'gs disable main sub')
tick(2.1)
assert(count_command(clients.Dolomedes, 'gs disable main sub') > locks,
    'main/sub ownership was not periodically reasserted')

-- Physical displacement restarts all 42.5 seconds; elapsed time before the
-- displacement cannot leak into the new timer.
tick(8)
clients.Dolomedes.equipment.main = 2
clients.Dolomedes.equipment.main_bag = 0
tick(0.1)
tick(0.1)
local uses = count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>')
tick_for(41)
assert(count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>') == uses,
    'staff displacement did not restart the use timer')
tick(2)
assert(count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>') > uses,
    'raw-verified staff was not used after a fresh 42.5-second delay')
local first_uses = count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>')
tick(11)
assert(count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>') == first_uses,
    'staff retry fired before its 12-second interval')
tick(1.1)
assert(count_command(clients.Dolomedes,
    'input /item "Kgd. Signet Staff" <me>') == first_uses + 1,
    'staff did not retry while Signet remained absent')

-- Reproduce the live failure: GearSwap accepts the restore command but leaves
-- Dolo's raw main/sub on the staff/empty pair. Signet alone must not advance
-- the transaction, and the restore request must retry until the original
-- raw weapon pair is observed continuously.
clients.Dolomedes.restore_equipment = false
for index, name in ipairs(names) do
    if index < #names then clients[name].buffs = {253} end
end
tick(1.1)
tick(1.1)
local resume_true = ('gs c ptgs action locus-signet resume %s %s 2 1 1 1')
    :format(generation, epoch)
for _, client in pairs(clients) do
    assert(not has_command(client, resume_true),
        'five Signet confirmations incorrectly resumed the party')
end

-- With the final Signet present, an un-restored weapon must still hold the
-- apply phase before any adapter resume command is allowed.
clients.Achoo.resume_ack = false
clients.Tackleberry.buffs = {253}
tick(1.1)
tick(1.1)
tick(1.1)
for _, client in pairs(clients) do
    assert(not has_command(client, resume_true),
        'Signet confirmation bypassed raw main/sub restoration')
end
assert(count_command(clients.Dolomedes, weapon_restore_command) >= 2,
    'failed weapon restoration was not retried')
assert(clients.Dolomedes.equipment.main == 1
        and clients.Dolomedes.equipment.sub == 0,
    'no-op restore fixture did not preserve the staff failure')

clients.Dolomedes.restore_equipment = 'wrong-sub'
tick(2.1)
assert(clients.Dolomedes.equipment.main == 2
        and clients.Dolomedes.equipment.sub == 0,
    'partial-restore fixture did not leave the original sub missing')
tick(1.1)
for _, client in pairs(clients) do
    assert(not has_command(client, resume_true),
        'matching main with the wrong sub bypassed restoration')
end

clients.Dolomedes.restore_equipment = true
tick(2.1)
assert(clients.Dolomedes.equipment.main == 2
        and clients.Dolomedes.equipment.sub == 3,
    'GearSwap-owned retry did not restore the original weapon pair')
tick(1.1)
tick(1.1)
tick(1.1)

-- Even after raw weapon restoration, all adapters must acknowledge resume
-- before the separately delivered puller release can cross.
assert(not has_command(clients.Tackleberry,
    ('lp operator on %s %s 1 resume 1'):format(generation, epoch)),
    'puller resumed before all six adapters acknowledged restoration')
local achoo_resume_attempts = count_command(clients.Achoo, resume_true)
tick(1.1)
assert(count_command(clients.Achoo, resume_true) > achoo_resume_attempts,
    'missing adapter resume acknowledgment was not retried')
clients.Achoo.resume_ack = true
local first_puller_release_dropped = false
drop_message = function(packet, recipient)
    if not first_puller_release_dropped and recipient == 'Tackleberry'
        and packet.message:find('SIGNETKEEPER1|pullerrelease|', 1, true) == 1
    then
        first_puller_release_dropped = true
        return true
    end
    return false
end
tick(1.1)
tick(1.1)
tick(1.1)
drop_message = nil
assert(first_puller_release_dropped,
    'resume fixture did not isolate the first puller-release packet')
assert(has_command(clients.Tackleberry, resume_true),
    'Tackle did not resume with the latest validated operator state')
assert(has_command(clients.Tackleberry,
    ('lp operator on %s %s 1 resume 1'):format(generation, epoch)),
    'Tackle puller did not follow the restored operator state')
assert(has_command(clients.Dolomedes, resume_true),
    'Tackle did not relay validated operator state to the no-loopback leader')
for _, client in pairs(clients) do
    assert(not has_command(client, 'pc on'),
        'SignetKeeper issued a blind PartyCombat arm')
end

-- A later mixed-timer census renews when ANY member is missing. Kick keeps
-- Signet and must never touch the staff, while delayed cycle-one evidence is
-- unable to advance the second transaction.
for _, name in ipairs(names) do
    clients[name].buffs = name == 'Kickpuncher' and {253} or {}
    clients[name].adapter_ack = name ~= 'Achoo'
end
local cycle_two_counts = {}
for _, name in ipairs(names) do
    cycle_two_counts[name] = {
        equips=count_command(clients[name],
            'input /equip main "Kgd. Signet Staff"'),
        uses=count_command(clients[name],
            'input /item "Kgd. Signet Staff" <me>'),
    }
end
local kick_locks = count_command(clients.Kickpuncher, 'gs disable main sub')
local kick_equips = count_command(clients.Kickpuncher,
    'input /equip main "Kgd. Signet Staff"')
tick(1.1)
tick(1.1)
tick(1.1)
assert(has_command(clients.Tackleberry,
    ('lp drain %s %s 2'):format(generation, epoch)),
    'mixed Signet timers did not trigger renewal cycle two')
local suspend_two = ('gs c ptgs action locus-signet suspend %s %s 2 2')
    :format(generation, epoch)
network[#network + 1] = {sender='delayed',
    message=('SIGNETKEEPER1|pullerdrained|%s|Tackleberry|%s|1')
        :format(generation, epoch)}
flush()
tick(2.1)
assert(not has_command(clients.Dolomedes, suspend_two),
    'delayed cycle-one drain ACK advanced cycle two')
clients.Tackleberry.callbacks['addon command'](
    '__pullerdrained', generation, tostring(epoch), '2')
flush()
tick(1.1)
tick(1.1)
tick(1.1)
assert(has_command(clients.Dolomedes, suspend_two),
    'exact cycle-two drain did not reach adapter suspension')
network[#network + 1] = {sender='delayed',
    message=('SIGNETKEEPER1|adapter|%s|Achoo|%s|suspended|1')
        :format(generation, epoch)}
network[#network + 1] = {sender='delayed',
    message=('SIGNETKEEPER1|report|%s|Achoo|%s|0|0|1|suspend|1|1|1')
        :format(generation, epoch)}
network[#network + 1] = {sender='delayed',
    message=('SIGNETKEEPER1|phase|%s|Dolomedes|%s|apply|1')
        :format(generation, epoch)}
flush()
local dolo_locks_before_cycle_two = count_command(clients.Dolomedes,
    'gs disable main sub')
tick(1.1)
assert(count_command(clients.Dolomedes, 'gs disable main sub')
    == dolo_locks_before_cycle_two,
    'delayed cycle-one adapter ACK entered cycle-two staff work')
clients.Achoo.callbacks['addon command']('__adapter', generation, 'Achoo',
    tostring(epoch), 'suspended', '2')
network[#network + 1] = {sender='Achoo',
    message=('SIGNETKEEPER1|adapter|%s|Achoo|%s|suspended|2')
        :format(generation, epoch)}
flush()
tick_for(5, 1)
assert(count_command(clients.Dolomedes, 'gs disable main sub')
    > dolo_locks_before_cycle_two,
    'current cycle-two ACK did not enter staff work: '
        ..table.concat(clients.Dolomedes.chats, ' || '))
-- Followers observe the leader's apply phase one IPC flush apart. Let every
-- missing member issue its one equip before starting the shared 42.5-second
-- equip-to-use delay, then audit the exact transaction counts.
for _ = 1, 10 do
    local all_equipped = true
    for _, name in ipairs(names) do
        if name ~= 'Kickpuncher' and count_command(clients[name],
            'input /equip main "Kgd. Signet Staff"')
            == cycle_two_counts[name].equips
        then
            all_equipped = false
        end
    end
    if all_equipped then break end
    tick(0.5)
end
tick(0.5)
tick_for(43)
assert(count_command(clients.Kickpuncher, 'gs disable main sub') == kick_locks
    and count_command(clients.Kickpuncher,
        'input /equip main "Kgd. Signet Staff"') == kick_equips,
    'member already holding Signet was allowed to touch the staff')
for _, name in ipairs(names) do
    local expected = name == 'Kickpuncher' and 0 or 1
    local equips = count_command(clients[name],
        'input /equip main "Kgd. Signet Staff"')
        - cycle_two_counts[name].equips
    local uses = count_command(clients[name],
        'input /item "Kgd. Signet Staff" <me>')
        - cycle_two_counts[name].uses
    assert(equips == expected,
        name..' had cycle-two staff equip delta '..tostring(equips))
    assert(uses == expected,
        name..' had cycle-two staff use delta '..tostring(uses))
end
for _, client in pairs(clients) do client.buffs = {253} end
for _ = 1, 7 do tick(1.1) end
assert(has_command(clients.Tackleberry,
    ('lp operator on %s %s 1 resume 2'):format(generation, epoch)),
    'cycle-two completion did not restore captured operator ON')

-- Tackle relays only the first exact operator state and real transitions.
-- Repeated, older, and eventually stale state cannot generate extra commands.
local relay = clients.Tackleberry
heartbeat_operator = nil
local relay_generation = '1800000050-123-700'
relay.commands = {}
relay.callbacks['addon command']('detach', generation, tostring(epoch))
relay.callbacks['addon command']('armpt', relay_generation, '8',
    'Dolomedes', roster, profile_id, profile_version)
local function relay_state(gen, operator, revision)
    local operator_revision, operator_bit = state_operator_tuple(
        gen, operator, revision)
    return table.concat({
        'PARTYTACTICS1','state',gen,engine_version,profile_id,
        profile_version,signature,'Dolomedes',roster,'8',
        '-','-','-',tostring(operator_revision),operator_bit,
    }, '|')
end
relay.callbacks['ipc message'](
    ('SIGNETKEEPER1|census|%s|Dolomedes|8|ready|0')
        :format(relay_generation))
relay.callbacks['ipc message'](relay_state(relay_generation, false)..'|extra')
assert(count_command(relay,
    ('lp operator off %s 8 1'):format(relay_generation)) == 0,
    'surplus-field PartyTactics state was accepted')
relay.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','operator',relay_generation,'Tackleberry','8','2','1','extra',
}, '|'))
assert(count_command(relay,
    ('lp operator on %s 8 2'):format(relay_generation)) == 0,
    'surplus-field Signet operator relay was accepted')
relay.callbacks['ipc message'](relay_state(relay_generation, false))
assert(count_command(relay,
    ('lp operator off %s 8 1'):format(relay_generation)) == 1,
    'first exact operator-OFF state was not relayed')
relay.callbacks['ipc message'](relay_state(relay_generation, false))
assert(count_command(relay,
    ('lp operator off %s 8 1'):format(relay_generation)) == 2,
    'equal/same state did not reapply the local puller side effect')
relay.callbacks['ipc message'](pt_state(true))
assert(count_command(relay,
    ('lp operator on %s 8 2'):format(relay_generation)) == 0,
    'older nonmatching state was relayed to LocusPuller')
relay.callbacks['ipc message'](relay_state(relay_generation, true))
assert(count_command(relay,
    ('lp operator on %s 8 2'):format(relay_generation)) == 1,
    'exact operator-ON transition was not relayed')
relay.callbacks['ipc message'](relay_state(relay_generation, false))
assert(count_command(relay,
    ('lp operator off %s 8 3'):format(relay_generation)) == 1,
    'exact operator-OFF transition was not relayed')
relay.callbacks['ipc message'](relay_state(relay_generation, true, 2))
relay.callbacks['ipc message'](relay_state(relay_generation, true, 3))
assert(status_header(relay):find('operator=unarmed@3', 1, true),
    'lower or equal/conflicting state rolled back the operator register')
assert(count_command(relay,
    ('lp operator on %s 8 2'):format(relay_generation)) == 1,
    'reordered stale ON generated another puller side effect')
relay.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','operator-state',relay_generation,engine_version,
    profile_id,profile_version,signature,'8','Dolomedes','4','1',
}, '|'))
assert(count_command(relay,
    ('lp operator on %s 8 4'):format(relay_generation)) == 1,
    'exact authoritative operator-state was not applied locally')
relay.callbacks['ipc message'](relay_state(relay_generation, true, 4))
assert(count_command(relay,
    ('lp operator on %s 8 4'):format(relay_generation)) == 2,
    'periodic equal/same state did not heal a dropped local side effect')
local relay_on_before_stale = count_command(relay,
    ('lp operator on %s 8 4'):format(relay_generation))
local relay_off_before_stale = count_command(relay,
    ('lp operator off %s 8 3'):format(relay_generation))
now = now + 13
relay.callbacks.prerender()
assert(count_command(relay,
    ('lp operator on %s 8 4'):format(relay_generation))
        == relay_on_before_stale
    and count_command(relay,
        ('lp operator off %s 8 3'):format(relay_generation))
        == relay_off_before_stale,
    'stale PartyTactics state generated a puller relay')

-- Manual emergency off during an apply phase keeps the exact adapter asleep
-- until GearSwap has physically restored the captured main/sub pair. A no-op
-- request and a wrong-sub partial restore both retry without reopening combat.
local solo = clients.Dolomedes
local next_generation = '1800000100-123-999'
solo.commands = {}
solo.buffs = {}
solo.callbacks['addon command']('detach', generation, tostring(epoch))
solo.callbacks['addon command']('armpt', next_generation, '9',
    'Dolomedes', roster, profile_id, profile_version)
solo.callbacks['ipc message'](
    ('SIGNETKEEPER1|phase|%s|Dolomedes|9|drain|1')
        :format(next_generation))
solo.callbacks['ipc message'](
    ('SIGNETKEEPER1|phase|%s|Dolomedes|9|suspend|1')
        :format(next_generation))
solo.callbacks['addon command'](
    '__adapter', next_generation, 'Dolomedes', '9', 'suspended', '1')
solo.callbacks['ipc message'](
    ('SIGNETKEEPER1|phase|%s|Dolomedes|9|apply|1')
        :format(next_generation))
for _ = 1, 4 do
    now = now + 1.1
    solo.callbacks.prerender()
end
assert(has_command(solo, 'gs disable main sub'),
    'manual-off fixture did not own main/sub')
solo.callbacks['addon command']('detach', next_generation, '8')
now = now + 0.1
solo.callbacks.prerender()
assert(count_command(solo, 'gs disable main sub') >= 1,
    'stale detach altered the current authority')
solo.restore_equipment = false
solo.callbacks['addon command']('off')
local terminal_resume =
    ('gs c ptgs action locus-signet resume %s 9 2 0 0 1')
        :format(next_generation)
assert(not has_command(solo, terminal_resume),
    'manual off resumed the adapter before physical weapon restoration')
assert(has_command(solo, weapon_restore_command),
    'manual off did not release GearSwap weapon slots')
local terminal_restore_attempts = count_command(solo, weapon_restore_command)
now = now + 2.1
solo.callbacks.prerender()
assert(count_command(solo, weapon_restore_command)
        > terminal_restore_attempts,
    'manual-off no-op restoration was not retried')
assert(not has_command(solo, terminal_resume),
    'manual-off no-op restoration reopened the adapter')
solo.restore_equipment = 'wrong-sub'
now = now + 2.1
solo.callbacks.prerender()
now = now + 1.1
solo.callbacks.prerender()
assert(not has_command(solo, terminal_resume),
    'manual-off wrong-sub restoration reopened the adapter')
solo.restore_equipment = true
now = now + 2.1
solo.callbacks.prerender()
now = now + 0.1
solo.callbacks.prerender()
assert(not has_command(solo, terminal_resume),
    'manual-off restoration skipped its stability confirmation')
now = now + 1.1
solo.callbacks.prerender()
assert(has_command(solo, terminal_resume),
    'manual off did not resume after exact stable weapon restoration')

-- If raw unload lands after terminal GearSwap restoration is physically exact
-- but before the one-second worker confirmation, consume that retained proof
-- and resume once. Process destruction must not orphan a safe adapter asleep.
local terminal_unload = make_client('Dolomedes')
local terminal_unload_generation = '1800000197-123-997'
terminal_unload.buffs = {}
terminal_unload.callbacks['addon command']('armpt',
    terminal_unload_generation, '11', 'Dolomedes', roster, profile_id,
    profile_version)
for _, value in ipairs({'drain','suspend','apply'}) do
    terminal_unload.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',terminal_unload_generation,'Dolomedes','11',
        value,'1',
    }, '|'))
end
for _ = 1, 5 do
    now = now + 1.1
    terminal_unload.callbacks.prerender()
end
assert(terminal_unload.equipment.main == 1,
    'terminal-unload fixture did not equip the Signet staff')
terminal_unload.callbacks['addon command']('off')
local terminal_unload_resume =
    ('gs c ptgs action locus-signet resume %s 11 2 0 0 1')
        :format(terminal_unload_generation)
assert(terminal_unload.equipment.main == 2
        and terminal_unload.equipment.sub == 3,
    'terminal-unload fixture did not expose an exact restored raw pair')
assert(not has_command(terminal_unload, terminal_unload_resume),
    'terminal-unload fixture resumed before stability confirmation')
terminal_unload.callbacks.unload()
assert(has_command(terminal_unload, terminal_unload_resume),
    'safe raw unload dropped the terminal worker adapter resume')

-- A replicated resume edge can race a delayed GearSwap/aftercast displacement
-- after the client previously reported restored. Re-observe raw equipment on
-- the edge and keep the adapter asleep until the exact pair is stable again.
local resume_race = make_client('Achoo')
local resume_race_generation = '1800000198-123-997'
resume_race.buffs = {}
resume_race.callbacks['addon command']('armpt', resume_race_generation, '10',
    'Dolomedes', roster, profile_id, profile_version)
for _, value in ipairs({'drain','suspend','apply'}) do
    resume_race.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',resume_race_generation,'Dolomedes','10',
        value,'1',
    }, '|'))
end
for _ = 1, 5 do
    now = now + 1.1
    resume_race.callbacks.prerender()
end
assert(resume_race.equipment.main == 1,
    'resume-race fixture did not equip the Signet staff')
resume_race.buffs = {253}
resume_race.callbacks['gain buff'](253)
now = now + 0.1
resume_race.callbacks.prerender()
now = now + 1.1
resume_race.callbacks.prerender()
resume_race.equipment.main, resume_race.equipment.main_bag = 1, 0
resume_race.equipment.sub, resume_race.equipment.sub_bag = 0, 0
resume_race.restore_equipment = false
resume_race.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','phase',resume_race_generation,'Dolomedes','10',
    'resume','1',
}, '|'))
local raced_resume =
    ('gs c ptgs action locus-signet resume %s 10 2 0 0 1')
        :format(resume_race_generation)
assert(not has_command(resume_race, raced_resume),
    'replicated resume edge reopened the adapter on the Signet staff')
resume_race.restore_equipment = true
now = now + 2.1
resume_race.callbacks.prerender()
now = now + 0.1
resume_race.callbacks.prerender()
assert(not has_command(resume_race, raced_resume),
    'resume-race restoration skipped stable raw confirmation')
now = now + 1.1
resume_race.callbacks.prerender()
assert(has_command(resume_race, raced_resume),
    'resume-race adapter did not reopen after exact weapon confirmation')

-- Reload recovery may lack an in-memory pre-staff snapshot, but it still needs
-- a raw-readable sub slot. A positive main plus an unreadable sub is not a
-- complete physical pair and must keep restoration pending.
local unreadable_sub = make_client('Kickpuncher')
local unreadable_generation = '1800000198-123-996'
unreadable_sub.equipment.main, unreadable_sub.equipment.sub = 1, 0
unreadable_sub.restore_equipment = 'unreadable-sub'
unreadable_sub.callbacks['addon command']('armpt', unreadable_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
unreadable_sub.callbacks.prerender()
now = now + 2.1
unreadable_sub.callbacks.prerender()
now = now + 2.1
unreadable_sub.callbacks.prerender()
assert(count_command(unreadable_sub, weapon_restore_command) >= 2,
    'unreadable sub slot did not retain restoration retries')
assert(status_header(unreadable_sub):find('weapon=restoring', 1, true),
    'unreadable sub slot was accepted as a restored weapon pair')
unreadable_sub.restore_equipment = true
now = now + 2.1
unreadable_sub.callbacks.prerender()
now = now + 0.1
unreadable_sub.callbacks.prerender()
now = now + 1.1
unreadable_sub.callbacks.prerender()
assert(status_header(unreadable_sub):find('weapon=restored', 1, true),
    'raw-readable recovery pair did not complete restoration')

-- A Weapons mode selected while the staff owns main/sub may legitimately
-- differ from the pre-staff snapshot. GearSwap must first reapply that mode
-- twice, and both raw slots must remain occupied and stable. A delayed/empty
-- sub cannot release automation even if the new main has arrived.
local mode_change = make_client('Dolomedes')
local mode_change_generation = '1800000198-123-989'
mode_change.buffs = {}
mode_change.callbacks['addon command']('armpt', mode_change_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
for _, value in ipairs({'drain','suspend','apply'}) do
    mode_change.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',mode_change_generation,'Dolomedes','0',
        value,'1',
    }, '|'))
end
for _ = 1, 5 do
    now = now + 1.1
    mode_change.callbacks.prerender()
end
assert(mode_change.equipment.main == 1,
    'mode-change fixture did not equip the Signet staff')
mode_change.restore_equipment = 'alternate'
mode_change.buffs = {253}
mode_change.callbacks['gain buff'](253)
now = now + 1.1
mode_change.callbacks.prerender()
assert(status_header(mode_change):find('weapon=restoring', 1, true),
    'one GearSwap reapply accepted a changed mode before repeat proof')
mode_change.restore_equipment = 'alternate-empty-sub'
for _ = 1, 4 do
    now = now + 2.1
    mode_change.callbacks.prerender()
end
local mode_change_status = status_header(mode_change)
assert(mode_change_status:find('weapon=restoring', 1, true),
    'new main with empty sub released the Locus weapon hold')
local mode_change_detail = status_weapon_detail(mode_change)
assert(mode_change_detail:find('raw-main=997 raw-sub=0', 1, true)
        and mode_change_detail:find('expected-main=999 expected-sub=998',
            1, true),
    'status omitted the current and captured raw weapon IDs')
mode_change.restore_equipment = 'alternate'
now = now + 2.1
mode_change.callbacks.prerender()
now = now + 0.1
mode_change.callbacks.prerender()
assert(status_header(mode_change):find('weapon=restoring', 1, true),
    'changed mode skipped raw-pair stability confirmation')
now = now + 1.1
mode_change.callbacks.prerender()
mode_change_status = status_header(mode_change)
mode_change_detail = status_weapon_detail(mode_change)
assert(mode_change_status:find('weapon=restored', 1, true)
        and mode_change_detail:find('raw-main=997 raw-sub=996', 1, true)
        and mode_change_detail:find('expected-main=997 expected-sub=996',
            1, true),
    'stable occupied GearSwap-selected mode did not replace the snapshot')
assert(not has_command(mode_change, 'input /equip main "Tauret"')
        and not has_command(mode_change,
            'input /equip sub "Gleti\'s Knife"'),
    'SignetKeeper directly equipped a normal combat weapon')

-- A same-generation/higher-epoch reapply during staff ownership must carry the
-- physical restoration obligation into the replacement authority. The new ON
-- bit remains held locally while a no-op GearSwap restore is retried.
local reapply_staff = make_client('Smalls')
local reapply_staff_generation = '1800000198-123-995'
reapply_staff.buffs = {}
reapply_staff.callbacks['addon command']('armpt', reapply_staff_generation,
    '1', 'Dolomedes', roster, profile_id, profile_version)
for _, value in ipairs({'drain','suspend','apply'}) do
    reapply_staff.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',reapply_staff_generation,'Dolomedes','1',
        value,'1',
    }, '|'))
end
for _ = 1, 5 do
    now = now + 1.1
    reapply_staff.callbacks.prerender()
end
assert(reapply_staff.equipment.main == 1,
    'reapply fixture did not physically equip the Signet staff')
reapply_staff.restore_equipment = false
local reapply_restore_before = count_command(reapply_staff,
    weapon_restore_command)
reapply_staff.callbacks['addon command']('armpt', reapply_staff_generation,
    '2', 'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature, '1', '1')
assert(status_header(reapply_staff):find('epoch=2', 1, true),
    'same-generation replacement authority did not bind')
assert(status_header(reapply_staff):find('weapon=restoring', 1, true),
    'replacement authority forgot in-flight staff restoration')
assert(has_command(reapply_staff, 'pc reconcile off'),
    'replacement ON authority did not retain the local maintenance hold')
assert(has_command(reapply_staff,
    ('gs c ptgs action locus-signet suspend %s 2 2 1')
        :format(reapply_staff_generation)),
    'replacement authority did not immediately suspend non-PC automation')
now = now + 2.1
reapply_staff.callbacks.prerender()
now = now + 2.1
reapply_staff.callbacks.prerender()
assert(count_command(reapply_staff, weapon_restore_command)
        >= reapply_restore_before + 3,
    'replacement authority did not persistently retry staff restoration')
reapply_staff.restore_equipment = true
now = now + 2.1
reapply_staff.callbacks.prerender()
now = now + 0.1
reapply_staff.callbacks.prerender()
now = now + 1.1
reapply_staff.callbacks.prerender()
assert(status_header(reapply_staff):find('weapon=restored', 1, true),
    'replacement authority did not complete physical restoration')

-- Same-generation reapply must inherit a hard maintenance suspension even
-- after the raw pair is already safe and weapon_restore_pending is false.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local maintenance_gen = '1800000198-123-993'
local maintained = make_client('Smalls')
maintained.callbacks['addon command']('armpt', maintenance_gen, '20',
    'Dolomedes', roster, profile_id, profile_version,
    engine_version, signature, '1', '1')
local function maintained_phase(value)
    maintained.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',maintenance_gen,'Dolomedes','20',
        value,'1',
    }, '|'))
end
maintained_phase('drain')
maintained_phase('suspend')
maintained_phase('apply')
now = now + 0.1
maintained.callbacks.prerender()
now = now + 1.1
maintained.callbacks.prerender()
local maintained_before = status_header(maintained)
assert(maintained_before:find('phase=apply', 1, true)
        and maintained_before:find('weapon=restored', 1, true),
    'fixture did not reach suspended apply with a safe raw pair')
local holds_before_maintenance = count_command(maintained,
    'pc reconcile off')
network = {}
maintained.callbacks['addon command']('armpt', maintenance_gen, '21',
    'Dolomedes', roster, profile_id, profile_version,
    engine_version, signature, '1', '1')
local replacement_suspend =
    ('gs c ptgs action locus-signet suspend %s 21 2 1')
        :format(maintenance_gen)
assert(has_command(maintained, replacement_suspend),
    'same-generation reapply reopened a suspended maintenance adapter')
assert(count_command(maintained, 'pc reconcile off')
        > holds_before_maintenance,
    'same-generation reapply did not preserve the combat hold')
local maintained_after = status_header(maintained)
assert(maintained_after:find('epoch=21', 1, true)
        and maintained_after:find('phase=drain', 1, true),
    'replacement epoch did not enter a fresh emergency cycle')
local replacement_report = nil
for index = #network, 1, -1 do
    local message = network[index].message
    if message:find(('SIGNETKEEPER1|report|%s|Smalls|21|')
        :format(maintenance_gen), 1, true) == 1 then
        replacement_report = message
        break
    end
end
assert(replacement_report
        and replacement_report:find('|drain|1|1|0', 1, true),
    'replacement epoch advertised the adapter as running')

-- Ordinary drain deliberately lets the current fight finish. A reapply in
-- that state must not promote it to an emergency suspension merely because
-- the epoch changed.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local ordinary_drain_gen = '1800000198-123-992'
local ordinary_draining = make_client('Kickpuncher')
ordinary_draining.callbacks['addon command']('armpt', ordinary_drain_gen,
    '30', 'Dolomedes', roster, profile_id, profile_version,
    engine_version, signature, '1', '1')
ordinary_draining.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','phase',ordinary_drain_gen,'Dolomedes','30',
    'drain','1',
}, '|'))
local holds_before_drain = count_command(ordinary_draining,
    'pc reconcile off')
local ordinary_replacement_suspend =
    ('gs c ptgs action locus-signet suspend %s 31 2 1')
        :format(ordinary_drain_gen)
ordinary_draining.callbacks['addon command']('armpt', ordinary_drain_gen,
    '31', 'Dolomedes', roster, profile_id, profile_version,
    engine_version, signature, '1', '1')
assert(not has_command(ordinary_draining, ordinary_replacement_suspend),
    'ordinary drain was incorrectly promoted to emergency suspension')
assert(count_command(ordinary_draining, 'pc reconcile off')
        == holds_before_drain,
    'ordinary drain reapply incorrectly forced PartyCombat off')
assert(status_header(ordinary_draining):find('phase=monitor', 1, true),
    'ordinary drain reapply did not restart normal epoch monitoring')

-- If the raw staff appears while Tackle is already released, local detection
-- must stop acquisition immediately; waiting for the leader's next report
-- census would permit another pull with AutoWS/support lanes still running.
local monitor_staff = make_client('Tackleberry')
local monitor_staff_generation = '1800000198-123-994'
monitor_staff.callbacks['addon command']('armpt', monitor_staff_generation,
    '0', 'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature, '1', '1')
monitor_staff.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','census',monitor_staff_generation,'Dolomedes','0',
    'ready','0',
}, '|'))
local monitor_on =
    ('lp operator on %s 0 1'):format(monitor_staff_generation)
assert(has_command(monitor_staff, monitor_on),
    'monitor-staff fixture did not begin with released pulling')
local monitor_on_count = count_command(monitor_staff, monitor_on)
monitor_staff.buffs = {}
monitor_staff.equipment.main, monitor_staff.equipment.main_bag = 1, 0
monitor_staff.equipment.sub, monitor_staff.equipment.sub_bag = 0, 0
monitor_staff.restore_equipment = false
monitor_staff.callbacks.prerender()
assert(has_command(monitor_staff,
    ('lp drain %s 0 1'):format(monitor_staff_generation)),
    'unsafe monitor staff did not immediately drain LocusPuller')
assert(has_command(monitor_staff,
    ('gs c ptgs action locus-signet suspend %s 0 2 1')
        :format(monitor_staff_generation)),
    'unsafe monitor staff did not immediately suspend adapter lanes')
assert(has_command(monitor_staff, 'pc reconcile off'),
    'unsafe monitor staff did not hold synchronized combat')
assert(count_command(monitor_staff, monitor_on) == monitor_on_count,
    'unsafe monitor staff replayed puller ON during recovery')

-- A follower can be the only client that observes an unsafe staff. Its exact
-- emergency request must make the safe leader adopt and broadcast N+1; no
-- split-cycle report rejection may strand that follower in drain forever.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local mixed_recovery_generation = '1800000198-123-993'
for _, name in ipairs(names) do
    local client = make_client(name)
    client.callbacks['addon command']('armpt', mixed_recovery_generation, '0',
        'Dolomedes', roster, profile_id, profile_version)
end
flush()
clients.Smalls.equipment.main, clients.Smalls.equipment.main_bag = 1, 0
clients.Smalls.equipment.sub, clients.Smalls.equipment.sub_bag = 0, 0
clients.Smalls.restore_equipment = false
clients.Smalls.callbacks.prerender()
flush()
for _, client in pairs(clients) do
    local status = status_header(client)
    assert(status:find('cycle=1', 1, true)
            and status:find('phase=drain', 1, true),
        'nonleader weapon emergency did not converge '..client.name
            ..' to canonical drain cycle 1')
end
clients.Tackleberry.callbacks['addon command']('__pullerdrained',
    mixed_recovery_generation, '0', '1')
flush()
tick_for(7, 1.1)
assert(status_header(clients.Dolomedes):find('phase=apply', 1, true),
    'mixed weapon emergency did not reach the suspended apply barrier')
assert(status_header(clients.Smalls):find('weapon=restoring', 1, true),
    'mixed no-op follower did not hold the apply barrier')
clients.Smalls.restore_equipment = true
tick_for(8, 1.1)
for _, client in pairs(clients) do
    local status = status_header(client)
    assert(status:find('phase=monitor', 1, true)
            and status:find('weapon=restored', 1, true),
        'mixed weapon emergency did not restore/resume '..client.name)
end

-- An idle keeper has no ownership claim over a manually equipped Signet
-- staff. Profile isolation forbids it from issuing gear commands merely from
-- observing the item outside an authenticated lifecycle.
local idle_staff = make_client('Smalls')
idle_staff.equipment.main, idle_staff.equipment.sub = 1, 0
for _ = 1, 3 do
    now = now + 2.1
    idle_staff.callbacks.prerender()
end
idle_staff.callbacks['addon command']('off')
idle_staff.callbacks['zone change']()
idle_staff.callbacks.logout()
idle_staff.callbacks.unload()
assert(count_command(idle_staff, weapon_restore_command) == 0,
    'idle keeper altered a manually equipped Signet staff')

-- Report bits are strict protocol booleans. A truthy non-bit token must not
-- manufacture a restored peer or advance the six-client transaction.
local malformed_report = make_client('Dolomedes')
local malformed_generation = '1800000199-123-998'
malformed_report.callbacks['addon command']('armpt', malformed_generation,
    '0', 'Dolomedes', roster, profile_id, profile_version)
malformed_report.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','report',malformed_generation,'Smalls','0',
    '1','0','1','monitor','x','0','1',
}, '|'))
malformed_report.callbacks['addon command']('status')
local malformed_smalls = nil
for index = #malformed_report.chats, 1, -1 do
    if malformed_report.chats[index]:find('  Smalls:', 1, true) then
        malformed_smalls = malformed_report.chats[index]
        break
    end
end
assert(malformed_smalls and malformed_smalls:find('no report', 1, true),
    'malformed report bit was accepted as a roster report')

-- GearSwap reload recovery is one full PartyTactics reapply, not an
-- adapter-only half recovery. Six simultaneous notices coalesce; the prior
-- exact ON bit crosses only into a different generation at epoch zero.
network, clients, heartbeat_operator = {}, {}, nil
for _, name in ipairs(names) do make_client(name) end
local reload_generation = '1800000200-123-100'
local function exact_state(gen, ep, operator, revision)
    local operator_revision, operator_bit = state_operator_tuple(
        gen, operator, revision)
    return table.concat({
        'PARTYTACTICS1','state',gen,engine_version,profile_id,
        profile_version,signature,'Dolomedes',roster,tostring(ep),
        '-','-','-',tostring(operator_revision),operator_bit,
    }, '|')
end
local function recover_command(gen, ep)
    local tuple = operator_states[gen] or {revision=0, operator=false}
    return ('pt __recover_controller locus-signet %s %s 2 %s %s %s %s Dolomedes %s %s %s')
        :format(gen, tostring(ep), profile_id, profile_version,
            engine_version, signature, roster, tostring(tuple.revision),
            tuple.operator and '1' or '0')
end
local function establish(gen, ep)
    for _, client in pairs(clients) do
        client.callbacks['addon command']('armpt', gen, tostring(ep),
            'Dolomedes', roster, profile_id, profile_version)
    end
    for name, client in pairs(clients) do
        if name ~= 'Dolomedes' then
            client.callbacks['ipc message'](exact_state(gen, ep, true))
        end
    end
    flush()
end
local function transition_to(old_gen, old_epoch, new_gen)
    local previous = operator_states[old_gen]
    if previous then
        operator_states[new_gen] = {
            revision=previous.revision, operator=previous.operator,
        }
    end
    for _, client in pairs(clients) do
        client.callbacks['addon command']('authorize', new_gen, '0',
            'Dolomedes', roster, profile_id, profile_version,
            engine_version, signature)
    end
    for _, client in pairs(clients) do
        client.callbacks['addon command']('detach', old_gen,
            tostring(old_epoch))
    end
    for _, client in pairs(clients) do
        client.callbacks['addon command']('armpt', new_gen, '0',
            'Dolomedes', roster, profile_id, profile_version)
    end
    flush()
end

establish(reload_generation, 4)
local early_lp_on = ('lp operator on %s 4 1'):format(reload_generation)
assert(not has_command(clients.Tackleberry, early_lp_on),
    'all-Signet startup relayed operator before the fresh census')
local first_census_dropped = false
drop_message = function(packet, recipient)
    if not first_census_dropped and recipient == 'Tackleberry'
        and packet.message:find('SIGNETKEEPER1|census|', 1, true) == 1
    then
        first_census_dropped = true
        return true
    end
    return false
end
tick(1.1)
drop_message = nil
assert(first_census_dropped,
    'all-Signet fixture did not isolate the first census release')
assert(not has_command(clients.Tackleberry, early_lp_on),
    'Tackle pulled without receiving the fresh census')
tick(2.1)
assert(has_command(clients.Tackleberry, early_lp_on),
    'periodic all-Signet census repair did not release captured operator ON')
for _, client in pairs(clients) do
    client.callbacks['addon command']('gsreload', reload_generation, '4')
end
flush()
local first_reload_start_dropped = false
drop_message = function(packet, recipient)
    if not first_reload_start_dropped and recipient == 'Achoo'
        and packet.message:find('SIGNETKEEPER1|reload-start|', 1, true) == 1
    then
        first_reload_start_dropped = true
        return true
    end
    return false
end
tick(1.6)
drop_message = nil
assert(first_reload_start_dropped,
    'reload fixture did not isolate the first start packet')
assert(count_command(clients.Dolomedes,
    recover_command(reload_generation, 4)) == 1,
    'six GearSwap reload notices did not coalesce into one exact recovery request')
assert(has_command(clients.Dolomedes,
    ('jk gsreload %s 4'):format(reload_generation))
    and has_command(clients.Tackleberry,
        ('lp gsreload %s 4'):format(reload_generation)),
    'coordinator did not fence local Jubilee/Locus companions for recovery')
for name, client in pairs(clients) do
    if name ~= 'Dolomedes' then
        client.callbacks['ipc message'](
            exact_state('1800000201-123-101', 0, false))
    end
end
transition_to(reload_generation, 4, '1800000201-123-101')
for name, client in pairs(clients) do
    assert(status_header(client):find(
        'generation=1800000201-123-101', 1, true),
        'gossiped reload start did not authorize successor on '..name)
end
assert(count_command(clients.Dolomedes, 'pt reapply') == 0
    and count_command(clients.Dolomedes, 'wait 1; pt arm') == 0,
    'companion issued an unfenced raw reapply or delayed arm')

-- Leader-only and remote-only notices both recover because the exact
-- operator relay survives Windower's lack of sender loopback.
establish('1800000201-123-101', 0)
clients.Dolomedes.callbacks['addon command'](
    'gsreload', '1800000201-123-101', '0')
flush()
tick(1.6)
assert(count_command(clients.Dolomedes,
    recover_command('1800000201-123-101', 0)) == 1,
    'Dolo-only GearSwap reload did not recover through Tackle operator relay')
transition_to('1800000201-123-101', 0, '1800000202-123-102')
assert(count_command(clients.Dolomedes, 'wait 1; pt arm') == 0,
    'Dolo-only recovery scheduled a stale operator override')

establish('1800000202-123-102', 0)
local first_reload_request_dropped = false
drop_message = function(packet, recipient)
    if not first_reload_request_dropped and recipient == 'Dolomedes'
        and packet.message:find('SIGNETKEEPER1|reload-request|', 1, true) == 1
    then
        first_reload_request_dropped = true
        return true
    end
    return false
end
clients.Smalls.callbacks['addon command'](
    'gsreload', '1800000202-123-102', '0')
flush()
drop_message = nil
assert(first_reload_request_dropped,
    'remote reload fixture did not isolate the first leader copy')
tick(1.6)
assert(count_command(clients.Dolomedes,
    recover_command('1800000202-123-102', 0)) == 1,
    'remote-only GearSwap reload did not request one leader reapply')
assert(has_command(clients.Dolomedes,
    'jk gsreload 1800000202-123-102 0')
    and has_command(clients.Tackleberry,
        'lp gsreload 1800000202-123-102 0'),
    'remote-only reload did not fence unaffected local companion helpers')

-- A terminal zone exit during a later pending notice cancels ownership and
-- cannot restart PartyTactics after the battlefield has gone away.
transition_to('1800000202-123-102', 0, '1800000203-123-103')
establish('1800000203-123-103', 0)
clients.Dolomedes.callbacks['addon command'](
    'gsreload', '1800000203-123-103', '0')
clients.Dolomedes.callbacks['zone change']()
flush()
tick(2)
assert(count_command(clients.Dolomedes,
    recover_command('1800000203-123-103', 0)) == 0,
    'zone cleanup restarted a pending full-profile recovery')

local function handoff_candidate(candidate_generation, candidate_epoch,
    candidate_leader, candidate_roster, candidate_profile, authorize)
    local candidate = make_client('Dolomedes')
    local old_generation = '1800000300-123-200'
    candidate.callbacks['addon command']('armpt', old_generation, '4',
        'Dolomedes', roster, profile_id, profile_version)
    candidate.callbacks['ipc message'](
        exact_state(old_generation, 4, true))
    candidate.callbacks['addon command']('gsreload', old_generation, '4')
    now = now + 1.6
    candidate.callbacks.prerender()
    assert(count_command(candidate, recover_command(old_generation, 4)) == 1,
        'handoff fixture did not begin exact controller recovery')
    if authorize then
        candidate.callbacks['addon command']('authorize',
            candidate_generation, tostring(candidate_epoch), candidate_leader,
            candidate_roster, candidate_profile, profile_version,
            engine_version, signature)
    end
    candidate.callbacks['addon command']('armpt', candidate_generation,
        tostring(candidate_epoch), candidate_leader,
        candidate_roster, candidate_profile, profile_version)
    candidate.callbacks['addon command']('status')
    local status = ''
    for index = #candidate.chats, 1, -1 do
        if candidate.chats[index]:find('generation=', 1, true) then
            status = candidate.chats[index]
            break
        end
    end
    assert(count_command(candidate, 'pt reapply') == 0
        and count_command(candidate, 'wait 1; pt arm') == 0,
        'handoff fixture emitted a raw reapply/arm command')
    return status:find('generation='..candidate_generation, 1, true) ~= nil
        and status:find('epoch='..tostring(candidate_epoch), 1, true) ~= nil
end

assert(not handoff_candidate('1800000301-123-201', 0, 'Dolomedes',
    roster, profile_id, false),
    'foreign epoch-zero generation was accepted without authorization')
assert(not handoff_candidate('1800000301-123-201', 1, 'Dolomedes', roster,
    profile_id, true), 'authorized generation outside epoch zero was accepted')
local reordered_roster =
    'Barneystinson,Achoo,Dolomedes,Kickpuncher,Smalls,Tackleberry'
assert(not handoff_candidate('1800000301-123-201', 0, 'Dolomedes',
    reordered_roster, profile_id, true),
    'recovery authorization accepted a different roster')
assert(not handoff_candidate('1800000301-123-201', 0, 'Dolomedes', roster,
    'another-profile', true),
    'recovery authorization accepted a different profile')
assert(not handoff_candidate('1800000301-123-201', 0, 'Tackleberry', roster,
    profile_id, true), 'recovery authorization accepted a different leader')
assert(handoff_candidate('1700000000-999-1', 0, 'Dolomedes', roster,
    profile_id, true),
    'exact authorization did not admit opaque lower-valued successor')

-- During an in-progress staff cycle, recovery teardown keeps the raw main/sub
-- lock physically owned until the exact successor arm is present. The new
-- authority then releases it and restarts census/cycle timing from zero.
local locked_reload = make_client('Dolomedes')
local locked_old = '1800000340-123-240'
local locked_new = '1700000340-999-2'
locked_reload.buffs = {}
locked_reload.callbacks['addon command']('armpt', locked_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
for _, phase in ipairs({'drain','suspend','apply'}) do
    locked_reload.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',locked_old,'Dolomedes','4',phase,'1',
    }, '|'))
end
for _ = 1, 4 do
    now = now + 1.1
    locked_reload.callbacks.prerender()
end
assert(has_command(locked_reload, 'gs disable main sub'),
    'locked-recovery fixture did not own main/sub')
locked_reload.callbacks['addon command']('gsreload', locked_old, '4')
now = now + 1.6
locked_reload.callbacks.prerender()
locked_reload.callbacks['addon command']('authorize', locked_new, '0',
    'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
local unlocks_before_handoff = count_command(locked_reload,
    weapon_restore_command)
locked_reload.callbacks['addon command']('detach', locked_old, '4')
assert(count_command(locked_reload, weapon_restore_command)
    == unlocks_before_handoff,
    'recovery teardown released staff ownership before successor arm')
locked_reload.callbacks['addon command']('armpt', locked_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(count_command(locked_reload, weapon_restore_command)
    == unlocks_before_handoff + 1,
    'successor arm did not safely release/restart the old staff cycle')

-- If the authorized successor state retires the old adapter before its local
-- arm command arrives, the surviving handoff remains closed to every foreign
-- probe. Only the exact authorized successor can bind the now-unarmed helper.
local unarmed_handoff = make_client('Dolomedes')
local unarmed_old = '1800000350-123-250'
local unarmed_new = '1700000350-999-2'
local unarmed_foreign = '1900000350-777-8'
unarmed_handoff.callbacks['addon command']('armpt', unarmed_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
unarmed_handoff.callbacks['addon command']('gsreload', unarmed_old, '4')
now = now + 1.6
unarmed_handoff.callbacks.prerender()
unarmed_handoff.callbacks['addon command']('authorize', unarmed_new, '0',
    'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
unarmed_handoff.callbacks['ipc message'](exact_state(unarmed_new, 0, true))
unarmed_handoff.callbacks['addon command']('armpt', unarmed_foreign, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(unarmed_handoff):find(' | OFF | ', 1, true),
    'foreign probe bound after successor state retired the old authority')
unarmed_handoff.callbacks['addon command']('armpt', unarmed_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(unarmed_handoff):find('generation='..unarmed_new, 1, true),
    'exact authorized successor could not bind after old-state retirement')

-- Exercise terminal teardown in the narrower handoff state where the old
-- authority has detached, main/sub remain raw-locked, and the named successor
-- has not delivered its arm yet. Every terminal path must unlock immediately
-- and the queued successor must stay retired.
local function preserved_unarmed_staff_client(old_generation, new_generation,
    client_name)
    local client = make_client(client_name or 'Dolomedes')
    client.buffs = {}
    client.callbacks['addon command']('armpt', old_generation, '4',
        'Dolomedes', roster, profile_id, profile_version)
    for _, phase in ipairs({'drain','suspend','apply'}) do
        client.callbacks['ipc message'](table.concat({
            'SIGNETKEEPER1','phase',old_generation,'Dolomedes','4',phase,'1',
        }, '|'))
    end
    for _ = 1, 4 do
        now = now + 1.1
        client.callbacks.prerender()
    end
    assert(has_command(client, 'gs disable main sub'),
        'terminal-gap fixture did not acquire main/sub')
    local restore_count_before_handoff = count_command(
        client, weapon_restore_command)
    client.callbacks['addon command']('gsreload', old_generation, '4')
    if client_name and client_name ~= 'Dolomedes' then
        client.callbacks['ipc message'](table.concat({
            'SIGNETKEEPER1','reload-start',old_generation,'Dolomedes','4','1','1',
        }, '|'))
    end
    now = now + 1.6
    client.callbacks.prerender()
    client.callbacks['addon command']('authorize', new_generation, '0',
        'Dolomedes', roster, profile_id, profile_version, engine_version,
        signature)
    client.callbacks['ipc message'](exact_state(new_generation, 0, true))
    assert(status_header(client):find(' | OFF | ', 1, true),
        'terminal-gap fixture did not preserve an unarmed handoff')
    assert(count_command(client, weapon_restore_command)
            == restore_count_before_handoff,
        'terminal-gap fixture released main/sub before terminal cleanup')
    client.restore_count_before_terminal = restore_count_before_handoff
    return client
end

local terminal_gap_cases = {
    {'manual off', function(client)
        client.callbacks['addon command']('off')
    end},
    {'zone change', function(client) client.callbacks['zone change']() end},
    {'logout', function(client) client.callbacks['logout']() end},
    {'addon unload', function(client) client.callbacks['unload']() end},
    {'remote coordinator disarm', function(client, old_generation)
        client.callbacks['ipc message'](table.concat({
            'SIGNETKEEPER1','disarm',old_generation,'4',
            'remote-terminal','0',
        }, '|'))
    end},
}
for index, case in ipairs(terminal_gap_cases) do
    local old_generation = ('1800000351-123-%d'):format(index)
    local new_generation = ('1700000351-999-%d'):format(index)
    local client = preserved_unarmed_staff_client(
        old_generation, new_generation)
    case[2](client, old_generation)
    assert(count_command(client, weapon_restore_command)
            == client.restore_count_before_terminal + 1,
        case[1]..' did not unlock main/sub in the preserved-unarmed gap')
    assert(has_command(client,
        ('jk stoppt %s %s %s %s %s Dolomedes'):format(old_generation,
            engine_version, profile_id, profile_version, signature)),
        case[1]..' did not terminally fence JubileeKeeper')
    client.callbacks['addon command']('armpt', new_generation, '0',
        'Dolomedes', roster, profile_id, profile_version)
    assert(status_header(client):find(' | OFF | ', 1, true),
        case[1]..' allowed the stopped recovery successor to rebind SignetKeeper')
end

-- A terminal edge can name the authorized successor during the narrow gap
-- after predecessor retirement but before the successor's local arm. It must
-- retire both sides of the handoff so the delayed successor cannot resurrect.
local successor_disarm_old = '1800000351-123-90'
local successor_disarm_new = '1700000351-999-90'
local successor_disarm = preserved_unarmed_staff_client(
    successor_disarm_old, successor_disarm_new)
successor_disarm.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','disarm',successor_disarm_new,'0',
    'remote-successor-terminal','0',
}, '|'))
assert(count_command(successor_disarm, weapon_restore_command)
        == successor_disarm.restore_count_before_terminal + 1,
    'authorized-successor disarm did not release preserved main/sub')
successor_disarm.callbacks['addon command']('armpt', successor_disarm_new,
    '0', 'Dolomedes', roster, profile_id, profile_version)
assert(status_header(successor_disarm):find(' | OFF | ', 1, true),
    'authorized-successor disarm allowed delayed successor resurrection')

-- The same successor-targeted terminal edge can arrive before the predecessor
-- has observed the successor state and detached. It still authenticates
-- against the live handoff and must retire both authorities.
local armed_successor = make_client('Dolomedes')
local armed_successor_old = '1800000351-123-92'
local armed_successor_new = '1700000351-999-92'
armed_successor.callbacks['addon command']('armpt', armed_successor_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
armed_successor.callbacks['addon command']('gsreload', armed_successor_old, '4')
now = now + 1.6
armed_successor.callbacks.prerender()
armed_successor.callbacks['addon command']('authorize', armed_successor_new,
    '0', 'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
armed_successor.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','disarm',armed_successor_new,'0',
    'armed-successor-terminal','0',
}, '|'))
assert(status_header(armed_successor):find(' | OFF | ', 1, true),
    'armed predecessor ignored its authorized-successor terminal edge')
assert(has_command(armed_successor,
    ('jk stoppt %s %s %s %s %s Dolomedes'):format(armed_successor_old,
        engine_version, profile_id, profile_version, signature)),
    'armed successor terminal edge did not fence the predecessor companion')
assert(has_command(armed_successor,
    ('jk stoppt %s %s %s %s %s Dolomedes'):format(armed_successor_new,
        engine_version, profile_id, profile_version, signature)),
    'armed successor terminal edge did not fence the authorized successor companion')
armed_successor.callbacks['addon command']('armpt', armed_successor_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(armed_successor):find(' | OFF | ', 1, true),
    'armed successor terminal edge allowed delayed successor resurrection')

-- GearSwap can acknowledge a terminal restore command without changing raw
-- equipment. The unarmed gear-only worker must retain ownership and retry
-- until a stable nonstaff pair is physically visible.
local terminal_retry_old = '1800000351-123-91'
local terminal_retry_new = '1700000351-999-91'
local terminal_retry = preserved_unarmed_staff_client(
    terminal_retry_old, terminal_retry_new)
terminal_retry.restore_equipment = false
terminal_retry.callbacks['addon command']('off')
local terminal_retry_first = count_command(terminal_retry,
    weapon_restore_command)
now = now + 2.1
terminal_retry.callbacks.prerender()
now = now + 2.1
terminal_retry.callbacks.prerender()
assert(count_command(terminal_retry, weapon_restore_command)
        >= terminal_retry_first + 2,
    'preserved-unarmed no-op restoration was not persistently retried')
assert(terminal_retry.equipment.main == 1,
    'no-op terminal fixture unexpectedly removed the Signet staff')
terminal_retry.restore_equipment = true
now = now + 2.1
terminal_retry.callbacks.prerender()
now = now + 0.1
terminal_retry.callbacks.prerender()
now = now + 1.1
terminal_retry.callbacks.prerender()
assert(terminal_retry.equipment.main == 2
        and terminal_retry.equipment.sub == 3,
    'terminal retry worker did not finish GearSwap restoration')

local predecessor_old = '1800000352-123-1'
local predecessor_new = '1700000352-999-1'
local predecessor_stop = preserved_unarmed_staff_client(
    predecessor_old, predecessor_new)
predecessor_stop.callbacks['addon command']('stoppt', predecessor_old,
    engine_version, profile_id, profile_version, signature, 'Smalls')
assert(count_command(predecessor_stop, weapon_restore_command)
        == predecessor_stop.restore_count_before_terminal + 1,
    'exact old-generation stop did not unlock preserved main/sub')
predecessor_stop.callbacks['addon command']('armpt', predecessor_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(predecessor_stop):find(' | OFF | ', 1, true),
    'old-generation stop allowed its queued Signet successor to bind')

-- Recovery expiry is terminal for every generation named by the handoff.
-- Exercise both the arm path that first observes an expired handoff and a
-- stop arriving after the 25-second metadata window.
local expired_arm_old = '1800000354-123-1'
local expired_arm_new = '1700000354-999-1'
local expired_arm = preserved_unarmed_staff_client(
    expired_arm_old, expired_arm_new)
now = now + 25.1
expired_arm.callbacks['addon command']('armpt', expired_arm_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
expired_arm.callbacks['addon command']('armpt', expired_arm_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(expired_arm):find(' | OFF | ', 1, true),
    'expired Signet handoff allowed a late successor/predecessor arm')
expired_arm.callbacks.prerender()
assert(count_command(expired_arm, weapon_restore_command)
        == expired_arm.restore_count_before_terminal + 1,
    'expired Signet handoff did not release preserved main/sub')

local expired_stop_old = '1800000355-123-1'
local expired_stop_new = '1700000355-999-1'
local expired_stop = preserved_unarmed_staff_client(
    expired_stop_old, expired_stop_new)
now = now + 25.1
expired_stop.callbacks['addon command']('stoppt', expired_stop_new,
    engine_version, profile_id, profile_version, signature, 'Smalls')
expired_stop.callbacks['addon command']('stoppt', expired_stop_old,
    engine_version, profile_id, profile_version, signature, 'Smalls')
expired_stop.callbacks.prerender()
assert(count_command(expired_stop, weapon_restore_command)
        == expired_stop.restore_count_before_terminal + 1,
    'late Signet stop did not release expired preserved main/sub')
expired_stop.callbacks['addon command']('armpt', expired_stop_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
expired_stop.callbacks['addon command']('armpt', expired_stop_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(expired_stop):find(' | OFF | ', 1, true),
    'late Signet stop lost expired handoff tombstones')

local tackle_gap_old = '1800000353-123-1'
local tackle_gap_new = '1700000353-999-1'
local tackle_gap = preserved_unarmed_staff_client(
    tackle_gap_old, tackle_gap_new, 'Tackleberry')
tackle_gap.callbacks['addon command']('off')
assert(has_command(tackle_gap,
    ('lp retirept %s %s %s %s %s Dolomedes'):format(tackle_gap_old,
        engine_version, profile_id, profile_version, signature)),
    'terminal Signet cleanup did not fence Tackleberry\'s preserved puller handoff')
tackle_gap.callbacks['addon command']('armpt', tackle_gap_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(tackle_gap):find(' | OFF | ', 1, true),
    'terminal Tackleberry cleanup allowed the queued Signet successor to bind')

-- PartyTactics 0.13.2 stop field 3 is a request nonce; field 10 is the exact
-- target generation. Reject wrong targets and non-exact schemas, then accept
-- a fully authenticated ten-field stop from the pinned roster.
local stopper = make_client('Dolomedes')
local stop_generation = '1800000360-123-260'
local stop_request = '1999999999-777-3'
stopper.callbacks['addon command']('armpt', stop_generation, '4',
    'Dolomedes', roster, profile_id, profile_version)
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','wrong-target',unarmed_foreign,
}, '|'))
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','extra',stop_generation,'extra',
}, '|'))
assert(status_header(stopper):find('generation='..stop_generation, 1, true),
    'wrong-target or non-exact stop schema released Signet authority')
stopper.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','exact',stop_generation,
}, '|'))
assert(status_header(stopper):find(' | OFF | ', 1, true),
    'field-10 exact PartyTactics stop did not release Signet authority')
assert(status_terminal_detail(stopper):find(
    'last-terminal=exact | gen/epoch='..stop_generation..'/4',
    1, true), 'exact stop target and epoch were not retained after reset')
assert(has_command(stopper,
    ('jk stoppt %s %s %s %s %s Smalls'):format(stop_generation,
        engine_version, profile_id, profile_version, signature)),
    'validated stop was not propagated to Dolo\'s Jubilee fence')

local stop_before_arm = make_client('Tackleberry')
local stop_before_old = '1800000370-123-270'
local stop_before_new = '1700000370-999-7'
stop_before_arm.callbacks['addon command']('armpt', stop_before_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
stop_before_arm.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','reload-start',stop_before_old,'Dolomedes','4','1','1',
}, '|'))
stop_before_arm.callbacks['addon command']('authorize', stop_before_new, '0',
    'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
stop_before_arm.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','successor-stop',stop_before_new,
}, '|'))
stop_before_arm.callbacks['addon command']('armpt', stop_before_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(stop_before_arm):find(' | OFF | ', 1, true),
    'stop-before-arm allowed delayed successor to resurrect Signet authority')
assert(status_terminal_detail(stop_before_arm):find(
    'last-terminal=successor-stop | gen/epoch='..stop_before_new..'/0',
    1, true), 'successor stop diagnostic named the predecessor')
assert(has_command(stop_before_arm, ('lp retirept %s %s %s %s %s Smalls')
    :format(stop_before_new, engine_version, profile_id, profile_version,
        signature)),
    'validated successor stop was not propagated to LocusPuller')
assert(has_command(stop_before_arm,
    ('lp retirept %s %s %s %s %s Dolomedes')
    :format(stop_before_old, engine_version, profile_id, profile_version,
        signature)),
    'validated successor stop did not fence the armed predecessor puller')

-- The symmetric target is equally terminal: a stop naming the armed
-- predecessor must fence the already-authorized successor too.
local stop_predecessor = make_client('Dolomedes')
local stop_predecessor_old = '1800000370-123-271'
local stop_predecessor_new = '1700000370-999-8'
stop_predecessor.callbacks['addon command']('armpt', stop_predecessor_old,
    '4', 'Dolomedes', roster, profile_id, profile_version)
stop_predecessor.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','reload-start',stop_predecessor_old,'Dolomedes','4',
    '1','1',
}, '|'))
stop_predecessor.callbacks['addon command']('authorize',
    stop_predecessor_new, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
stop_predecessor.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','stop',stop_request,engine_version,profile_id,
    profile_version,signature,'Smalls','predecessor-stop',
    stop_predecessor_old,
}, '|'))
assert(has_command(stop_predecessor,
    ('jk stoppt %s %s %s %s %s Smalls'):format(stop_predecessor_old,
        engine_version, profile_id, profile_version, signature)),
    'validated predecessor stop did not fence the armed predecessor helper')
assert(has_command(stop_predecessor,
    ('jk stoppt %s %s %s %s %s Dolomedes'):format(stop_predecessor_new,
        engine_version, profile_id, profile_version, signature)),
    'validated predecessor stop did not fence its authorized successor helper')

-- Direct adapter probes are lifecycle-fenced independently of PT-state IPC.
-- Normal detach admits an opaque lower-valued new nonce; a retired old tuple
-- cannot return, while same-generation higher epoch remains legitimate.
local monotonic = make_client('Dolomedes')
local monotonic_old = '1800000400-123-300'
local monotonic_new = '1700000401-999-1'
monotonic.callbacks['addon command']('armpt', monotonic_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('detach', monotonic_old, '4')
monotonic.callbacks['addon command']('armpt', monotonic_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('armpt', monotonic_new, '1',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('armpt', monotonic_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('armpt', monotonic_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('detach', monotonic_new, '0')
monotonic.callbacks['addon command']('status')
local monotonic_status = ''
for index = #monotonic.chats, 1, -1 do
    if monotonic.chats[index]:find('generation=', 1, true) then
        monotonic_status = monotonic.chats[index]
        break
    end
end
assert(monotonic_status:find('generation='..monotonic_new, 1, true)
    and monotonic_status:find('epoch=1', 1, true),
    'opaque lower-valued generation was rejected or delayed probe downgraded Signet authority: '
        ..monotonic_status)
monotonic.callbacks['addon command']('detach', monotonic_new, '1')
monotonic.callbacks['addon command']('status')
local detached_status = ''
for index = #monotonic.chats, 1, -1 do
    if monotonic.chats[index]:find('generation=', 1, true) then
        detached_status = monotonic.chats[index]
        break
    end
end
assert(detached_status:find(' | OFF | ', 1, true),
    'same-generation higher-epoch Signet authority was not accepted')
monotonic.callbacks['addon command']('armpt', monotonic_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
monotonic.callbacks['addon command']('status')
local retired_status = ''
for index = #monotonic.chats, 1, -1 do
    if monotonic.chats[index]:find('generation=', 1, true) then
        retired_status = monotonic.chats[index]
        break
    end
end
assert(retired_status:find(' | OFF | ', 1, true),
    'retired Signet authority rebound after replacement detached')

-- An explicit operator OFF after recovery begins must never be overwritten by
-- a companion-side delayed arm. PartyTactics owns the carried operator bit.
local handoff_off = make_client('Dolomedes')
local handoff_off_old = '1800000500-123-400'
local handoff_off_new = '1800000501-123-401'
handoff_off.callbacks['addon command']('armpt', handoff_off_old, '4',
    'Dolomedes', roster, profile_id, profile_version)
handoff_off.callbacks['ipc message'](exact_state(handoff_off_old, 4, true))
handoff_off.callbacks['addon command']('gsreload', handoff_off_old, '4')
now = now + 1.6
handoff_off.callbacks.prerender()
assert(count_command(handoff_off,
    recover_command(handoff_off_old, 4)) == 1,
    'operator-OFF handoff fixture did not start exact recovery')
handoff_off.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','operator',handoff_off_old,'Tackleberry','4','2','0',
}, '|'))
handoff_off.callbacks['addon command']('authorize', handoff_off_new, '0',
    'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
handoff_off.callbacks['addon command']('armpt', handoff_off_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(count_command(handoff_off, 'wait 1; pt arm') == 0,
    'operator OFF during reload handoff was overwritten by stale carried ON')
assert(status_header(handoff_off):find('operator=unarmed@2', 1, true),
    'recovery successor did not inherit the newest revisioned OFF tuple')

-- Reload metadata is a monotonic replica too. A higher carried OFF must make
-- an equal/conflicting PT state invalid without partially changing live state;
-- the matching authoritative OFF can then converge both replicas.
local reload_conflict = make_client('Dolomedes')
local reload_conflict_generation = '1800000525-123-425'
reload_conflict.callbacks['addon command']('armpt',
    reload_conflict_generation, '4', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature, '10', '1')
reload_conflict.callbacks['addon command']('gsreload',
    reload_conflict_generation, '4')
reload_conflict.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','reload-request',reload_conflict_generation,'Smalls',
    '4','11','0',
}, '|'))
reload_conflict.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','state',reload_conflict_generation,engine_version,
    profile_id,profile_version,signature,'Dolomedes',roster,'4',
    '-','-','-','11','1',
}, '|'))
assert(status_header(reload_conflict):find('operator=armed@10', 1, true),
    'equal/conflicting reload carrier partially changed live operator state')
reload_conflict.callbacks['ipc message'](table.concat({
    'PARTYTACTICS1','state',reload_conflict_generation,engine_version,
    profile_id,profile_version,signature,'Dolomedes',roster,'4',
    '-','-','-','11','0',
}, '|'))
assert(status_header(reload_conflict):find('operator=unarmed@11', 1, true),
    'matching higher reload operator state did not converge')

-- The adapter sends exact lifecycle authorization on initial activation too.
-- It must not produce a false recovery error, and the pending tuple must fence
-- both a foreign arm and a stop that arrives before the real armpt command.
local initial_auth = make_client('Dolomedes')
local initial_generation = '1800000550-123-450'
local initial_foreign = '1800000551-123-451'
initial_auth.callbacks['addon command']('authorize', initial_generation, '0',
    'Dolomedes', roster, profile_id, profile_version, engine_version,
    signature)
for _, message in ipairs(initial_auth.chats) do
    assert(not message:find('unauthorized PartyTactics recovery successor',
        1, true), 'initial authorization emitted a false recovery warning')
end
initial_auth.callbacks['addon command']('armpt', initial_foreign, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(initial_auth):find(' | OFF | ', 1, true),
    'foreign arm bypassed the pending initial authorization')
initial_auth.callbacks['addon command']('armpt', initial_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(initial_auth):find('generation='..initial_generation,
    1, true), 'exact initially authorized Signet authority did not bind')

local initial_stopped = make_client('Dolomedes')
local initial_stopped_generation = '1800000552-123-452'
initial_stopped.callbacks['addon command']('authorize',
    initial_stopped_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
initial_stopped.callbacks['addon command']('stoppt',
    initial_stopped_generation, engine_version, profile_id, profile_version,
    signature, 'Smalls')
initial_stopped.callbacks['addon command']('armpt',
    initial_stopped_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version)
assert(status_header(initial_stopped):find(' | OFF | ', 1, true),
    'initial stop-before-arm resurrected Signet authority')

local initial_manual_off = make_client('Dolomedes')
local initial_manual_generation = '1800000553-123-453'
initial_manual_off.callbacks['addon command']('authorize',
    initial_manual_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
initial_manual_off.callbacks['addon command']('off')
initial_manual_off.callbacks['addon command']('armpt',
    initial_manual_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version)
assert(status_header(initial_manual_off):find(' | OFF | ', 1, true),
    'manual off allowed a delayed pending arm to resurrect Signet authority')

-- Initial authorization has the same bounded semantics: once its 25-second
-- window expires, neither a late arm nor a late stop followed by arm can make
-- that generation look like an unfenced first activation.
local expired_initial_arm = make_client('Dolomedes')
local expired_initial_arm_generation = '1800000554-123-454'
expired_initial_arm.callbacks['addon command']('authorize',
    expired_initial_arm_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
now = now + 25.1
expired_initial_arm.callbacks['addon command']('armpt',
    expired_initial_arm_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version)
assert(status_header(expired_initial_arm):find(' | OFF | ', 1, true),
    'expired initial Signet authorization allowed a late arm')

local expired_initial_stop = make_client('Dolomedes')
local expired_initial_stop_generation = '1800000555-123-455'
expired_initial_stop.callbacks['addon command']('authorize',
    expired_initial_stop_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
now = now + 25.1
expired_initial_stop.callbacks['addon command']('stoppt',
    expired_initial_stop_generation, engine_version, profile_id,
    profile_version, signature, 'Smalls')
expired_initial_stop.callbacks['addon command']('armpt',
    expired_initial_stop_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version)
assert(status_header(expired_initial_stop):find(' | OFF | ', 1, true),
    'late Signet stop lost the expired initial-authority tombstone')

local late_after_zone = make_client('Dolomedes')
local late_zone_generation = '1800000556-123-456'
late_after_zone.zone = 191
late_after_zone.callbacks['zone change']()
late_after_zone.callbacks['addon command']('authorize',
    late_zone_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version, engine_version, signature)
late_after_zone.callbacks['addon command']('armpt', late_zone_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
assert(status_header(late_after_zone):find(' | OFF | ', 1, true),
    'late queued authority rebound SignetKeeper outside the owned zone')

-- Raw SignetKeeper unload is process-local. It may restore/resume its own safe
-- state, but it must emit no IPC while Windower is destroying the Lua state.
-- Surviving followers remain fail-closed until the bounded controller lease
-- expires, then retire and restore themselves.
local function unload_during(terminal_phase, unload_generation)
    network, clients, heartbeat_operator = {}, {}, nil
    for _, name in ipairs(names) do make_client(name) end
    for _, client in pairs(clients) do
        client.buffs = {}
        client.callbacks['addon command']('armpt', unload_generation, '0',
            'Dolomedes', roster, profile_id, profile_version)
    end
    flush()
    local function deliver_phase(phase)
        local message = table.concat({
            'SIGNETKEEPER1','phase',unload_generation,'Dolomedes','0',
            phase,'1',
        }, '|')
        for _, client in pairs(clients) do
            client.callbacks['ipc message'](message)
        end
        flush()
    end
    deliver_phase('drain')
    deliver_phase('suspend')
    if terminal_phase == 'apply' then deliver_phase('apply') end
    local suspend = ('gs c ptgs action locus-signet suspend %s 0 2 1')
        :format(unload_generation)
    for _, client in pairs(clients) do
        assert(has_command(client, suspend),
            'unload fixture did not suspend '..client.name)
    end
    assert(#network == 0, 'unload fixture began with pending IPC')
    local unloaded = clients.Dolomedes
    local unloaded_raw_pair_was_safe = unloaded.equipment.main == 2
        and unloaded.equipment.sub == 3
    unloaded.callbacks.unload()
    assert(#network == 0,
        'raw addon unload emitted cross-client IPC during Lua teardown')
    local resume = ('gs c ptgs action locus-signet resume %s 0 2 0 0 1')
        :format(unload_generation)
    for name, client in pairs(clients) do
        if name ~= 'Dolomedes' then
            assert(not has_command(client, resume),
                ('raw unload immediately woke surviving %s before lease expiry')
                    :format(name))
        end
    end
    clients.Dolomedes = nil
    tick_for(32, 1)
    tick_for(2, 1)
    for _, client in pairs(clients) do
        assert(has_command(client, resume),
            ('lease fallback after raw unload during %s orphaned %s suspended')
                :format(terminal_phase, client.name))
    end
    if unloaded_raw_pair_was_safe then
        assert(has_command(unloaded, resume),
            'safe local unload dropped its exact adapter resume')
    else
        assert(not has_command(unloaded, resume),
            'unsafe local unload resumed before physical restoration proof')
    end
end

unload_during('suspend', '1800000600-123-500')
unload_during('apply', '1800000601-123-501')

-- Raw addon unload has no future prerender on which to verify an asynchronous
-- GearSwap repair. If the staff is physically present and that repair is a
-- no-op, it may queue the restore but must not blindly wake automatic lanes.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local unsafe_unload_generation = '1800000601-123-599'
local unsafe_unload = make_client('Dolomedes')
unsafe_unload.buffs = {}
unsafe_unload.callbacks['addon command']('armpt', unsafe_unload_generation,
    '0', 'Dolomedes', roster, profile_id, profile_version)
for _, value in ipairs({'drain','suspend','apply'}) do
    unsafe_unload.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',unsafe_unload_generation,'Dolomedes','0',
        value,'1',
    }, '|'))
end
for _ = 1, 6 do
    now = now + 1.1
    unsafe_unload.callbacks.prerender()
end
assert(unsafe_unload.equipment.main == 1,
    'unsafe-unload fixture did not physically equip the Signet staff')
unsafe_unload.restore_equipment = false
unsafe_unload.callbacks.unload()
local unsafe_unload_resume =
    ('gs c ptgs action locus-signet resume %s 0 2 0 0 1')
        :format(unsafe_unload_generation)
assert(has_command(unsafe_unload, weapon_restore_command),
    'unsafe raw unload did not queue GearSwap restoration')
assert(not has_command(unsafe_unload, unsafe_unload_resume),
    'unsafe raw unload blindly resumed automatic lanes on the staff')

-- Reproduce the live failure shape: five remote clients enter raw unload in
-- the same interval while all are holding the staff. No unload callback may
-- append IPC, and each process must still queue its own GearSwap restoration.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local mass_unload_generation = '1800000601-123-600'
for _, name in ipairs(names) do
    local client = make_client(name)
    client.buffs = {}
    client.callbacks['addon command']('armpt', mass_unload_generation, '0',
        'Dolomedes', roster, profile_id, profile_version)
end
flush()
for _, phase in ipairs({'drain','suspend','apply'}) do
    local message = table.concat({
        'SIGNETKEEPER1','phase',mass_unload_generation,'Dolomedes','0',
        phase,'1',
    }, '|')
    for _, client in pairs(clients) do
        client.callbacks['ipc message'](message)
    end
    flush()
end
tick_for(6, 1)
local mass_unload_names = {
    'Dolomedes','Tackleberry','Kickpuncher','Achoo','Smalls',
}
for _, name in ipairs(mass_unload_names) do
    assert(clients[name].equipment.main == 1,
        'mass-unload fixture did not put the staff on '..name)
end
assert(#network == 0, 'mass-unload fixture began with pending IPC')
local restore_counts = {}
for _, name in ipairs(mass_unload_names) do
    restore_counts[name] = count_command(clients[name], weapon_restore_command)
end
for _, name in ipairs(mass_unload_names) do
    clients[name].callbacks.unload()
end
assert(#network == 0,
    'simultaneous raw unloads emitted reentrant cross-client IPC')
for _, name in ipairs(mass_unload_names) do
    assert(count_command(clients[name], weapon_restore_command)
            == restore_counts[name] + 1,
        'mass unload did not queue local weapon restoration for '..name)
end

-- A receiver consumes an authenticated terminal broadcast exactly once. It
-- must never gossip the packet from inside Windower's IPC callback.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local no_gossip_generation = '1800000601-123-601'
local no_gossip = make_client('Achoo')
no_gossip.callbacks['addon command']('armpt', no_gossip_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
flush()
no_gossip.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','disarm',no_gossip_generation,'0','remote-terminal','1',
}, '|'))
assert(#network == 0,
    'terminal disarm receiver rebroadcast from inside its IPC callback')
assert(status_header(no_gossip):find(' | OFF | ', 1, true),
    'terminal disarm receiver did not retire its local authority')

-- Ctrl-P during apply updates the desired operator bit but cannot pierce the
-- full suspension. Core keeps ON inert and every keeper reasserts the local
-- hold defensively; the stored ON is honored only by the exact final resume.
network, clients, heartbeat_operator = {}, {}, nil
local apply_arm_generation = '1800000602-123-502'
for _, name in ipairs(names) do make_client(name) end
for _, client in pairs(clients) do
    client.buffs = {}
    client.callbacks['addon command']('armpt', apply_arm_generation, '0',
        'Dolomedes', roster, profile_id, profile_version)
end
local function apply_arm_phase(phase)
    local message = table.concat({
        'SIGNETKEEPER1','phase',apply_arm_generation,'Dolomedes','0',
        phase,'1',
    }, '|')
    for _, client in pairs(clients) do client.callbacks['ipc message'](message) end
    flush()
end
apply_arm_phase('drain')
apply_arm_phase('suspend')
apply_arm_phase('apply')
local early_resume =
    ('gs c ptgs action locus-signet resume %s 0 2 1 1 1')
        :format(apply_arm_generation)
for _, client in pairs(clients) do
    local pc_off_before = count_command(client, 'pc off')
    local reconcile_before = count_command(client, 'pc reconcile off')
    client.callbacks['ipc message'](exact_state(apply_arm_generation, 0, true))
    client.callbacks['ipc message'](exact_state(apply_arm_generation, 0, true))
    assert(count_command(client, 'pc off') == pc_off_before,
        'Ctrl-P during apply emitted a visible PartyCombat OFF on '..client.name)
    assert(count_command(client, 'pc reconcile off') == reconcile_before + 2,
        'repeated Ctrl-P state did not silently retain the maintenance hold on '
            ..client.name)
    assert(not has_command(client, early_resume),
        'Ctrl-P during apply resumed the adapter early on '..client.name)
end
flush()
for _, client in pairs(clients) do client.buffs = {253} end
apply_arm_phase('resume')
for _, client in pairs(clients) do
    assert(not has_command(client, early_resume),
        'final Signet edge skipped physical weapon confirmation on '..client.name)
end
tick(1.1)
tick(0.1)
for _, client in pairs(clients) do
    assert(has_command(client, early_resume),
        'final Signet resume did not honor stored operator ON on '..client.name)
end

-- A coordinator heartbeat lapse during maintenance retires the authority but
-- first wakes the exact adapter and releases any owned weapon slots. A normal
-- 13-second scheduler stall is tolerated; the conservative 30-second lease is
-- only a final fallback behind exact stop/replacement messages.
local function stale_coordinator_during(terminal_phase, stale_generation)
    network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
    local client = make_client('Dolomedes')
    client.buffs = {}
    client.callbacks['addon command']('armpt', stale_generation, '0',
        'Dolomedes', roster, profile_id, profile_version)
    local revision, bit = state_operator_tuple(stale_generation, true)
    client.callbacks['addon command']('operator', stale_generation, '0',
        tostring(revision), bit)
    local function phase(value)
        client.callbacks['ipc message'](table.concat({
            'SIGNETKEEPER1','phase',stale_generation,'Dolomedes','0',
            value,'1',
        }, '|'))
    end
    phase('drain')
    phase('suspend')
    if terminal_phase == 'apply' then
        phase('apply')
        for _ = 1, 4 do
            now = now + 1.1
            client.callbacks.prerender()
        end
        assert(has_command(client, 'gs disable main sub'),
            'stale apply fixture did not own main/sub')
    end
    now = now + 20
    client.callbacks.prerender()
    assert(not status_header(client):find(' | OFF | ', 1, true),
        '20-second scheduler stall expired the conservative PT lease')
    now = now + 11
    client.callbacks.prerender()
    local resume =
        ('gs c ptgs action locus-signet resume %s 0 2 %s 1 1')
            :format(stale_generation, tostring(revision))
    if terminal_phase == 'apply' then
        assert(not has_command(client, resume),
            'stale PT state resumed before exact weapon confirmation')
        now = now + 0.1
        client.callbacks.prerender()
        now = now + 1.1
        client.callbacks.prerender()
    end
    assert(has_command(client, resume),
        'stale PT state orphaned the exact adapter during '..terminal_phase)
    assert(status_header(client):find(' | OFF | ', 1, true),
        'expired PT lease did not retire Signet authority')
    if terminal_phase == 'apply' then
        assert(has_command(client, weapon_restore_command),
            'stale PT state did not release main/sub during apply')
    end
end

stale_coordinator_during('suspend', '1800000610-123-510')
stale_coordinator_during('apply', '1800000611-123-511')

network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local never_heartbeat_generation = '1800000611-123-599'
local never_heartbeat = make_client('Smalls')
never_heartbeat.callbacks['addon command']('armpt',
    never_heartbeat_generation, '0', 'Dolomedes', roster, profile_id,
    profile_version)
now = now + 31
never_heartbeat.callbacks.prerender()
assert(status_header(never_heartbeat):find(' | OFF | ', 1, true),
    'authority with no local adapter heartbeat survived past its lease')

-- If an isolated client's teardown packet is lost, its missing replicated
-- report is still detected. A fresh PartyTactics heartbeat cannot conceal
-- that six-member visibility is gone or leave the other adapters suspended.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local roster_loss_generation = '1800000612-123-512'
local roster_loss = make_client('Tackleberry')
roster_loss.buffs = {}
roster_loss.callbacks['addon command']('armpt', roster_loss_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
local roster_loss_revision, roster_loss_bit = state_operator_tuple(
    roster_loss_generation, true, 1)
roster_loss.callbacks['addon command']('operator', roster_loss_generation,
    '0', tostring(roster_loss_revision), roster_loss_bit)
for _, value in ipairs({'drain','suspend','apply'}) do
    roster_loss.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',roster_loss_generation,'Dolomedes','0',
        value,'1',
    }, '|'))
end
now = now + 31
roster_loss.callbacks['addon command']('operator', roster_loss_generation,
    '0', tostring(roster_loss_revision), roster_loss_bit)
roster_loss.callbacks.prerender()
local roster_loss_resume =
    ('gs c ptgs action locus-signet resume %s 0 2 1 1 1')
        :format(roster_loss_generation)
assert(not has_command(roster_loss, roster_loss_resume),
    'lost client teardown resumed before stable weapon confirmation')
now = now + 0.1
roster_loss.callbacks.prerender()
now = now + 1.1
roster_loss.callbacks.prerender()
assert(has_command(roster_loss, roster_loss_resume),
    'lost client teardown left a surviving adapter suspended')
assert(status_header(roster_loss):find(' | OFF | ', 1, true),
    'missing six-client report did not retire automatic pulling')

-- Once the all-adapter barrier releases Tackle, a newer authoritative OFF is
-- still immediate even before the final census packet arrives. ON remains
-- gated, so this closes the narrow Alt-P race without weakening startup.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local pre_census_generation = '1800000620-123-520'
local pre_census = make_client('Tackleberry')
pre_census.callbacks['addon command']('armpt', pre_census_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
pre_census.callbacks['addon command']('operator', pre_census_generation, '0',
    '1', '1')
local function pre_census_phase(value)
    pre_census.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',pre_census_generation,'Dolomedes','0',
        value,'1',
    }, '|'))
end
pre_census_phase('drain')
pre_census_phase('suspend')
pre_census_phase('apply')
pre_census.buffs = {253}
for _ = 1, 4 do
    now = now + 1.1
    pre_census.callbacks.prerender()
end
pre_census_phase('resume')
pre_census.callbacks['ipc message'](table.concat({
    'SIGNETKEEPER1','pullerrelease',pre_census_generation,'Dolomedes','0','1',
}, '|'))
assert(has_command(pre_census,
    ('lp operator on %s 0 1 resume 1'):format(pre_census_generation)),
    'pre-census fixture did not release the exact puller')
pre_census.callbacks['addon command']('operator', pre_census_generation, '0',
    '2', '0')
assert(has_command(pre_census,
    ('lp operator off %s 0 2'):format(pre_census_generation)),
    'newer operator OFF was withheld until census')

-- A decoded zero-charge staff is an explicit paused condition. It never
-- enters the equipment transaction or loops item commands indefinitely.
network, clients, heartbeat_operator, drop_message = {}, {}, nil, nil
local depleted_generation = '1800000630-123-530'
local depleted = make_client('Smalls')
depleted.buffs = {}
depleted.inventory[1].enchantment.charges_remaining = 0
depleted.callbacks['addon command']('armpt', depleted_generation, '0',
    'Dolomedes', roster, profile_id, profile_version)
local function depleted_phase(value)
    depleted.callbacks['ipc message'](table.concat({
        'SIGNETKEEPER1','phase',depleted_generation,'Dolomedes','0',
        value,'1',
    }, '|'))
end
depleted_phase('drain')
depleted_phase('suspend')
depleted_phase('apply')
now = now + 1
depleted.callbacks.prerender()
assert(not has_command(depleted, 'gs disable main sub')
    and not has_command(depleted,
        'input /item "Kgd. Signet Staff" <me>'),
    'zero-charge staff entered the equipment/use transaction')
local depleted_warning = false
for _, message in ipairs(depleted.chats) do
    if message:find('no charges remaining', 1, true) then
        depleted_warning = true
        break
    end
end
assert(depleted_warning, 'zero-charge staff did not report its blocker')

-- The status breadcrumb survives terminal reset, an idle repeated OFF, and a
-- later nonterminal adapter detach. It never becomes an authority itself.
local diagnostic = make_client('Smalls')
local diagnostic_old = '1800000640-123-540'
local diagnostic_new = '1800000640-123-541'
assert(status_terminal_detail(diagnostic):find(
    'last-terminal=- | gen/epoch=-/-', 1, true),
    'fresh SignetKeeper reported a fabricated terminal cause')
diagnostic.callbacks['addon command']('armpt', diagnostic_old, '3',
    'Dolomedes', roster, profile_id, profile_version)
diagnostic.callbacks['addon command']('off')
local expected_terminal = 'last-terminal=manual emergency stop | gen/epoch='
    ..diagnostic_old..'/3'
assert(status_terminal_detail(diagnostic):find(expected_terminal, 1, true),
    'manual terminal reason and authority disappeared after reset')
diagnostic.callbacks['addon command']('off')
assert(status_terminal_detail(diagnostic):find(expected_terminal, 1, true),
    'idle repeated OFF overwrote the prior terminal cause')
diagnostic.callbacks['addon command']('armpt', diagnostic_new, '0',
    'Dolomedes', roster, profile_id, profile_version)
diagnostic.callbacks['addon command']('detach', diagnostic_new, '0')
assert(status_terminal_detail(diagnostic):find(expected_terminal, 1, true),
    'nonterminal adapter detach overwrote the terminal cause')

print('SignetKeeper PartyTactics six-client runtime simulation OK')
