local source = arg and arg[1] or 'addons/LocusPuller/LocusPuller.lua'

local function run_unload_case(during_drain)
    local now = 100
    local client = {callbacks={}, commands={}, ipc={}, scheduled={}}
    local player = {id=10, index=10, name='Tackleberry', status=0,
        vitals={mp=1000}}
    local me = {id=10, index=10, name='Tackleberry', spawn_type=1,
        valid_target=true, hpp=100, x=0, y=0, distance=0}
    local bat = {id=100, index=100, name='Locus Dire Bat', spawn_type=16,
        valid_target=true, hpp=100, claim_id=0, x=10, y=0, distance=100}
    local selected = me

    local packets = {
        new=function(direction, id, fields)
            fields.direction, fields.packet_id = direction, id
            return fields
        end,
        inject=function(packet)
            selected = packet.Target == bat.id and bat or me
        end,
    }
    local env = setmetatable({}, {__index=_G})
    env._addon = {}
    env.os = setmetatable({clock=function() return now end}, {__index=os})
    env.require = function(name)
        assert(name == 'packets')
        return packets
    end
    env.coroutine = setmetatable({
        schedule=function(fn, delay)
            client.scheduled[#client.scheduled + 1] = {
                fn=fn, at=now + delay,
            }
        end,
    }, {__index=coroutine})
    env.windower = {
        add_to_chat=function() end,
        send_command=function(command)
            client.commands[#client.commands + 1] = command
        end,
        send_ipc_message=function(message)
            client.ipc[#client.ipc + 1] = message
        end,
        register_event=function(event, fn)
            client.callbacks[event] = fn
        end,
        ffxi={
            get_player=function() return player end,
            get_info=function() return {zone=190, logged_in=true} end,
            get_mob_by_target=function(token)
                if token == 'me' then return me end
                if token == 't' then return selected end
            end,
            get_mob_by_id=function(id) return id == bat.id and bat or nil end,
            get_mob_array=function() return {[me.id]=me, [bat.id]=bat} end,
            get_party=function()
                return {p0={name=player.name, mob={id=player.id}}}
            end,
            get_spell_recasts=function() return {[112]=0} end,
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

    local function run_scheduled()
        local pending = {}
        for _, job in ipairs(client.scheduled) do
            if job.at <= now then
                job.fn()
            else
                pending[#pending + 1] = job
            end
        end
        client.scheduled = pending
    end
    local function tick(seconds)
        now = now + (seconds or 0.21)
        run_scheduled()
        client.callbacks.prerender()
        run_scheduled()
    end
    local function count_command(expected)
        local count = 0
        for _, command in ipairs(client.commands) do
            if command == expected then count = count + 1 end
        end
        return count
    end

    local generation = during_drain
        and '1800000701-123-601' or '1800000700-123-600'
    local epoch = '0'
    client.callbacks['addon command']('bindpt', generation, epoch,
        'locus-dire-bats-tomb-signet', '1.1.0', '0.13.2', 'abcdef012345',
        'Dolomedes',
        'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry',
        '0', '0')
    client.callbacks['addon command']('operator', 'on', generation, epoch,
        '1')
    tick()
    local opener_arm = ('gs c ptgs action locus-signet opener-arm 100 %s 0 2')
        :format(generation)
    assert(count_command(opener_arm) == 1,
        'unload fixture did not reserve the opener')
    client.callbacks['addon command']('__gate_armed', '100', generation, epoch)
    tick()
    assert(count_command('input /ma "Flash" <t>') == 1,
        'unload fixture did not leave an issued Flash in flight')
    if during_drain then
        client.callbacks['addon command']('drain', generation, epoch, '1')
        local drained = ('SIGNETKEEPER1|pullerdrained|%s|Tackleberry|0|1')
            :format(generation)
        for _, message in ipairs(client.ipc) do
            assert(message ~= drained,
                'drain fixture acknowledged before issued Flash settled')
        end
    end

    client.callbacks.unload()
    local opener_release =
        ('gs c ptgs action locus-signet opener-release 100 %s 0 2')
            :format(generation)
    assert(count_command(opener_release) == 1,
        during_drain
            and 'raw unload during drain did not fail-open the adapter gate'
            or 'raw unload during opener did not fail-open the adapter gate')
    assert(count_command(opener_release..' keepoff') == 0,
        'raw helper unload incorrectly used terminal keepoff release')
    assert(count_command(('sk __pullerlost %s 0'):format(generation)) == 1,
        during_drain
            and 'raw unload did not abort the exact Signet drain'
            or 'raw unload did not notify the exact Signet coordinator')
end

run_unload_case(false)
run_unload_case(true)

print('LocusPuller raw-unload recovery simulations OK')
