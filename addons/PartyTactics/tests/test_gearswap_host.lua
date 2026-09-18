local HOST_PATH = 'addons/PartyTactics/gearswap/PartyTactics_Host.lua'
local ADAPTER_PATH =
    'Common/PartyTactics/adapters/genmei-cor/1.2.3.lua'

local function load_in_environment(path, environment)
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(path)
        if loader then setfenv(loader, environment) end
    else
        loader, load_error = loadfile(path, 't', environment)
    end
    assert(loader, load_error)
    return loader()
end

local function make_adapter(overrides)
    local state = {
        activate_count=0,
        deactivate_reasons={},
        actions={},
        calls={},
        consume_pre=false,
        consume_job=false,
        consume_command=false,
        block_pretarget=false,
        block_precast=false,
    }
    local function called(name, ...)
        local values = {...}
        state.calls[name] = state.calls[name] or {}
        state.calls[name][#state.calls[name] + 1] = values
    end
    local adapter = {
        id='genmei-cor',
        version='1.2.3',
        controller='genmei',
        protocol=1,
        activate=function()
            state.activate_count = state.activate_count + 1
            return true
        end,
        deactivate=function(reason)
            state.deactivate_reasons[#state.deactivate_reasons + 1] = reason
        end,
        handle_action=function(controller, semantic, arguments)
            state.actions[#state.actions + 1] = {
                controller=controller,
                semantic=semantic,
                arguments=arguments,
            }
            if semantic == 'reject' then return false, 'semantic rejected' end
            return true
        end,
        status=function() return 'queue=idle' end,
        pre_tick=function(...)
            called('pre_tick', ...)
            return state.consume_pre
        end,
        user_job_tick=function(...)
            called('user_job_tick', ...)
            return state.consume_job
        end,
        user_job_self_command=function(...)
            called('user_job_self_command', ...)
            return state.consume_command
        end,
        filter_pretarget=function(...)
            called('filter_pretarget', ...)
            return state.block_pretarget
        end,
        filter_precast=function(...)
            called('filter_precast', ...)
            return state.block_precast
        end,
        job_aftercast=function(...) called('job_aftercast', ...) end,
        file_unload=function(...) called('file_unload', ...) end,
        action_event=function(...) called('action_event', ...) end,
        prerender=function(...) called('prerender', ...) end,
        zone_change=function(...) called('zone_change', ...) end,
        logout=function(...) called('logout', ...) end,
        unload=function(...) called('unload', ...) end,
        status_change=function(...) called('status_change', ...) end,
    }
    for key, value in pairs(overrides or {}) do adapter[key] = value end
    return adapter, state
end

local function harness(modules)
    local h = {
        events={},
        registrations={},
        included={},
        chat={},
        commands={},
        originals={},
    }
    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.windower = {
        raw_register_event=function(name, callback)
            h.registrations[name] = (h.registrations[name] or 0) + 1
            h.events[name] = h.events[name] or {}
            h.events[name][#h.events[name] + 1] = callback
        end,
    }
    env.add_to_chat = function(color, message)
        h.chat[#h.chat + 1] = {color=color, message=message}
    end
    env.windower.send_command = function(command)
        h.commands[#h.commands + 1] = command
    end
    env.include = function(path)
        h.included[#h.included + 1] = path
        local result = modules[path]
        if result == nil then error('missing test include '..path) end
        return result
    end

    local function native(name)
        return function(...)
            local args = {...}
            h.originals[name] = h.originals[name] or {}
            h.originals[name][#h.originals[name] + 1] = args
            return h.native_first, nil, h.native_third
        end
    end
    env.pre_tick = native('pre_tick')
    env.user_job_tick = native('user_job_tick')
    env.user_filter_pretarget = native('user_filter_pretarget')
    env.user_filter_precast = native('user_filter_precast')
    env.job_aftercast = native('job_aftercast')
    env.user_job_self_command = native('user_job_self_command')
    env.file_unload = native('file_unload')
    h.native_first = {}
    h.native_third = {}
    h.env = env

    function h.load()
        return load_in_environment(HOST_PATH, env)
    end
    function h.command(arguments)
        local event_args = {handled=false}
        env.user_job_self_command(arguments, event_args)
        return event_args
    end
    function h.fire(name, ...)
        assert(h.events[name] and #h.events[name] == 1,
            'raw event '..name..' was not registered exactly once')
        return h.events[name][1](...)
    end
    return h
end

local adapter, adapter_state = make_adapter()
local h = harness({[ADAPTER_PATH]=adapter})
local host = h.load()
assert(type(host) == 'table' and host.revision == '1.2.1'
    and host.protocol == 1)

-- Every profile uses this adapter-independent proof to show that the stable
-- EOF host actually executed in the current GearSwap job file.
local host_probe = h.command({'ptgs', 'probe', '1700000000-1000-1', '0'})
assert(host_probe.handled == true)
assert(h.commands[#h.commands]
    == 'pt __gearswap_host_ready 1.2.1 1700000000-1000-1 0')
local host_probe_count = #h.commands
h.command({'ptgs', 'probe', 'bad-generation', '0'})
h.command({'ptgs', 'probe', '1700000000-1000-1', '-1'})
assert(#h.commands == host_probe_count,
    'invalid stable-host proof was emitted')

-- Re-including the stable host neither captures the wrappers again nor adds a
-- second raw callback.
local wrappers = {
    h.env.pre_tick, h.env.user_job_tick, h.env.user_filter_pretarget,
    h.env.user_filter_precast, h.env.job_aftercast,
    h.env.user_job_self_command, h.env.file_unload,
}
assert(h.load() == host)
local event_names = {
    'action', 'prerender', 'zone change', 'logout', 'unload', 'status change',
}
for _, event_name in ipairs(event_names) do
    assert(h.registrations[event_name] == 1,
        event_name..' registered more than once')
end
for index, callback in ipairs(wrappers) do
    local current = ({
        h.env.pre_tick, h.env.user_job_tick, h.env.user_filter_pretarget,
        h.env.user_filter_precast, h.env.job_aftercast,
        h.env.user_job_self_command, h.env.file_unload,
    })[index]
    assert(current == callback, 'host wrapper changed on second include')
end

-- Dormant callbacks preserve identity, argument identity, nil positions, and
-- the captured callback's exact returned objects.
local dormant_token = {}
local first, middle, third = h.env.pre_tick(dormant_token)
assert(first == h.native_first and middle == nil and third == h.native_third)
assert(h.originals.pre_tick[1][1] == dormant_token)
first, middle, third = h.env.user_job_tick(dormant_token)
assert(first == h.native_first and middle == nil and third == h.native_third)
local dormant_filter = {cancel=false}
first, middle, third = h.env.user_filter_pretarget(
    dormant_token, 'map', dormant_filter)
assert(first == h.native_first and middle == nil and third == h.native_third)
assert(dormant_filter.cancel == false)
first, middle, third = h.env.user_filter_precast(
    dormant_token, 'map', dormant_filter)
assert(first == h.native_first and middle == nil and third == h.native_third)
first, middle, third = h.env.job_aftercast(dormant_token, 'map', {})
assert(first == h.native_first and middle == nil and third == h.native_third)
first, middle, third = h.env.user_job_self_command({'native'}, dormant_token)
assert(first == h.native_first and middle == nil and third == h.native_third)
first, middle, third = h.env.file_unload(dormant_token)
assert(first == h.native_first and middle == nil and third == h.native_third)

-- Neither path component can escape the fixed Common adapter root.
assert(h.command({'ptgs', 'activate', '../evil', '1.2.3'}).handled)
assert(h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3/evil'}).handled)
assert(h.command({'ptgs', 'activate', 'genmei-cor', '01.2.3'}).handled)
assert(#h.included == 0, 'an unsafe activation reached include')
assert(host.active_metadata() == nil)

-- A valid activation performs the one exact lazy include and verifies all
-- metadata before calling activate.
assert(h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'}).handled)
assert(#h.included == 1 and h.included[1] == ADAPTER_PATH)
assert(adapter_state.activate_count == 1)
local metadata = host.active_metadata()
assert(metadata.id == 'genmei-cor' and metadata.version == '1.2.3'
    and metadata.controller == 'genmei' and metadata.protocol == 1)

local idempotent_chat_count = #h.chat
assert(h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'}).handled)
assert(#h.included == 1 and adapter_state.activate_count == 1,
    'same pinned activation reloaded or reset the active adapter')
assert(#h.chat == idempotent_chat_count,
    'same pinned activation produced repeated visible status chatter')

-- Active tick hooks either chain or consume deterministically.
local before_pre = #h.originals.pre_tick
first, middle, third = h.env.pre_tick('chain-pre')
assert(#h.originals.pre_tick == before_pre + 1)
assert(first == h.native_first and middle == nil and third == h.native_third)
adapter_state.consume_pre = true
assert(h.env.pre_tick('owned-pre') == true)
assert(#h.originals.pre_tick == before_pre + 1)
assert(adapter_state.calls.pre_tick[#adapter_state.calls.pre_tick][1]
    == 'owned-pre')

local before_job = #h.originals.user_job_tick
adapter_state.consume_job = true
assert(h.env.user_job_tick('owned-job') == true)
assert(#h.originals.user_job_tick == before_job)
adapter_state.consume_job = false
assert(h.env.user_job_tick('chain-job') == h.native_first)
assert(#h.originals.user_job_tick == before_job + 1)

-- Filter ownership is a boolean adapter decision; the host owns cancellation.
local before_pretarget = #h.originals.user_filter_pretarget
adapter_state.block_pretarget = true
local blocked = {cancel=false}
h.env.user_filter_pretarget({id=1}, 'map', blocked)
assert(blocked.cancel == true)
assert(#h.originals.user_filter_pretarget == before_pretarget)
adapter_state.block_pretarget = false
local allowed = {cancel=false}
assert(h.env.user_filter_pretarget({id=2}, 'map', allowed) == h.native_first)
assert(allowed.cancel == false)
assert(#h.originals.user_filter_pretarget == before_pretarget + 1)

local before_precast = #h.originals.user_filter_precast
adapter_state.block_precast = true
blocked = {cancel=false}
h.env.user_filter_precast({id=3}, 'map', blocked)
assert(blocked.cancel == true)
assert(#h.originals.user_filter_precast == before_precast)

-- Observer hooks never suppress the native GearSwap callbacks.
local aftercast_token = {}
local before_aftercast = #h.originals.job_aftercast
assert(h.env.job_aftercast(aftercast_token, 'map', {}) == h.native_first)
assert(#h.originals.job_aftercast == before_aftercast + 1)
assert(adapter_state.calls.job_aftercast[1][1] == aftercast_token)
local before_native_command = #h.originals.user_job_self_command
assert(h.env.user_job_self_command({'unrelated'}, {}) == h.native_first)
assert(#h.originals.user_job_self_command == before_native_command + 1)

-- An active adapter may consume one private maintenance command without
-- changing the `ptgs` control path or any unrelated job self command.
adapter_state.consume_command = true
local owned_command_args = {'pstartrdm', 'tick'}
local owned_command_event = {handled=false}
assert(h.env.user_job_self_command(
    owned_command_args, owned_command_event) == true)
assert(owned_command_event.handled == true)
assert(#h.originals.user_job_self_command == before_native_command + 1)
local observed_command = adapter_state.calls.user_job_self_command[#adapter_state.calls.user_job_self_command]
assert(observed_command[1] == owned_command_args
    and observed_command[2] == owned_command_event)
adapter_state.consume_command = false
assert(h.env.user_job_self_command({'native-again'}, {}) == h.native_first)
assert(#h.originals.user_job_self_command == before_native_command + 2)

-- Only the active adapter's exact controller receives an arguments-only array.
local action_event = h.command({
    'ptgs', 'action', 'genmei', 'close', '123456', 'generation-7',
})
assert(action_event.handled and #adapter_state.actions == 1)
local routed = adapter_state.actions[1]
assert(routed.controller == 'genmei' and routed.semantic == 'close')
assert(#routed.arguments == 2 and routed.arguments[1] == '123456'
    and routed.arguments[2] == 'generation-7')
h.command({'ptgs', 'action', 'other', 'close', '123456'})
assert(#adapter_state.actions == 1, 'mismatched controller reached adapter')
h.command({'ptgs', 'action', 'genmei', '../close', '123456'})
assert(#adapter_state.actions == 1, 'unsafe semantic reached adapter')
h.command({'ptgs', 'action', 'genmei', 'reject'})
assert(#adapter_state.actions == 2, 'valid adapter rejection was not routed')

-- Status is active-adapter-only and reports the adapter's bounded detail.
h.command({'ptgs', 'status'})
assert(h.chat[#h.chat].message:find('queue=idle', 1, true))

-- Every raw event has one stable dispatcher and preserves event arguments.
local raw_token = {}
h.fire('action', raw_token)
h.fire('prerender', raw_token)
h.fire('zone change', 289, 288)
h.fire('status change', 1, 0)
assert(adapter_state.calls.action_event[1][1] == raw_token)
assert(adapter_state.calls.prerender[1][1] == raw_token)
assert(adapter_state.calls.zone_change[1][1] == 289
    and adapter_state.calls.zone_change[1][2] == 288)
assert(adapter_state.calls.status_change[1][1] == 1)

-- Logout dispatches first, then retires the adapter.  Reactivation reuses only
-- the already verified module and raw unload follows the same bounded cleanup.
h.fire('logout', 'logout-token')
assert(adapter_state.calls.logout[1][1] == 'logout-token')
assert(adapter_state.deactivate_reasons[#adapter_state.deactivate_reasons]
    == 'logout')
assert(host.active_metadata() == nil)
assert(h.commands[#h.commands]
    == 'pt __gearswap_host_lost 1.2.1 logout')
h.command({'ptgs', 'action', 'genmei', 'close'})
assert(#adapter_state.actions == 2, 'inactive action reached adapter')
h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(#h.included == 1 and adapter_state.activate_count == 2,
    'verified adapter was not lazily reused')
h.fire('unload', 'unload-token')
assert(adapter_state.calls.unload[1][1] == 'unload-token')
assert(adapter_state.deactivate_reasons[#adapter_state.deactivate_reasons]
    == 'unload')
assert(host.active_metadata() == nil)
assert(h.commands[#h.commands]
    == 'pt __gearswap_host_lost 1.2.1 addon-unload')

-- Explicit off and file-unload both deactivate while preserving native cleanup.
h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
h.command({'ptgs', 'off'})
assert(adapter_state.deactivate_reasons[#adapter_state.deactivate_reasons]
    == 'command')
local dormant_before = #h.originals.pre_tick
assert(h.env.pre_tick('dormant-again') == h.native_first)
assert(#h.originals.pre_tick == dormant_before + 1)
h.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
local before_file_unload = #h.originals.file_unload
assert(h.env.file_unload('file-token') == h.native_first)
assert(adapter_state.calls.file_unload[1][1] == 'file-token')
assert(#h.originals.file_unload == before_file_unload + 1)
assert(adapter_state.deactivate_reasons[#adapter_state.deactivate_reasons]
    == 'file-unload' and host.active_metadata() == nil)
assert(h.commands[#h.commands]
    == 'pt __gearswap_host_lost 1.2.1 file-unload')

-- An adapter exception is fail-closed: retire it, run its bounded cleanup,
-- and immediately resume the native callback for the same GearSwap event.
local broken, broken_state = make_adapter({
    pre_tick=function() error('intentional adapter failure') end,
})
local failure = harness({[ADAPTER_PATH]=broken})
local failure_host = failure.load()
failure.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(failure.env.pre_tick('native-fallback') == failure.native_first)
assert(failure_host.active_metadata() == nil)
assert(broken_state.deactivate_reasons[1] == 'error:pre_tick')
assert(failure.commands[#failure.commands]
    == 'pt __gearswap_host_lost 1.2.1 adapter-error')
assert(#failure.originals.pre_tick == 1
    and failure.originals.pre_tick[1][1] == 'native-fallback')

-- Revocation cannot depend on a failed adapter successfully cleaning itself
-- up.  Notify PartyTactics first, contain the cleanup exception, and still
-- return control to the native GearSwap callback.
local cleanup_attempts = 0
local doubly_broken = make_adapter({
    pre_tick=function() error('primary adapter failure') end,
    deactivate=function()
        cleanup_attempts = cleanup_attempts + 1
        error('cleanup failure')
    end,
})
local cleanup_failure = harness({[ADAPTER_PATH]=doubly_broken})
local cleanup_failure_host = cleanup_failure.load()
cleanup_failure.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(cleanup_failure.env.pre_tick('native-after-cleanup-failure')
    == cleanup_failure.native_first)
assert(cleanup_attempts == 1 and cleanup_failure_host.active_metadata() == nil)
assert(cleanup_failure.commands[#cleanup_failure.commands]
    == 'pt __gearswap_host_lost 1.2.1 adapter-error')

-- Returned metadata must match the requested module exactly.  A mismatch is
-- inactive, never calls activate, and cannot receive an action.
local wrong_id, wrong_id_state = make_adapter({id='other-adapter'})
local mismatch_id = harness({[ADAPTER_PATH]=wrong_id})
local mismatch_id_host = mismatch_id.load()
mismatch_id.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(mismatch_id_host.active_metadata() == nil)
assert(wrong_id_state.activate_count == 0)
mismatch_id.command({'ptgs', 'action', 'genmei', 'close', '123'})
assert(#wrong_id_state.actions == 0)

local wrong_version, wrong_version_state = make_adapter({version='9.9.9'})
local mismatch_version = harness({[ADAPTER_PATH]=wrong_version})
local mismatch_version_host = mismatch_version.load()
mismatch_version.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(mismatch_version_host.active_metadata() == nil)
assert(wrong_version_state.activate_count == 0)

-- Host revision 1.2.1 retains the pinned protocol allowlist and bounds only
-- the exact stale Signet companion-ACK diagnostic.
-- Legacy protocol 1 remains accepted above, protocol 2 activates through the
-- same exact metadata path, and an unknown future protocol remains inert.
local protocol_two, protocol_two_state = make_adapter({protocol=2})
local protocol_two_harness = harness({[ADAPTER_PATH]=protocol_two})
local protocol_two_host = protocol_two_harness.load()
protocol_two_harness.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
local protocol_two_metadata = protocol_two_host.active_metadata()
assert(protocol_two_metadata and protocol_two_metadata.protocol == 2)
assert(protocol_two_state.activate_count == 1)

local unsupported_protocol, unsupported_protocol_state = make_adapter({protocol=3})
local unsupported_harness = harness({[ADAPTER_PATH]=unsupported_protocol})
local unsupported_host = unsupported_harness.load()
unsupported_harness.command({'ptgs', 'activate', 'genmei-cor', '1.2.3'})
assert(unsupported_host.active_metadata() == nil)
assert(unsupported_protocol_state.activate_count == 0)

-- A retired Signet tuple may keep sending stale companion ACKs while the
-- core's bounded proof repair runs. Reject every ACK, but explain this exact
-- failure once per tuple instead of flooding every GearSwap chat log.
do
    local signet_path =
        'Common/PartyTactics/adapters/locus-dire-bats-tomb-signet/1.8.0.lua'
    local rejected = 0
    local signet = make_adapter({
        id='locus-dire-bats-tomb-signet', version='1.8.0',
        controller='locus-signet', protocol=2,
        handle_action=function(_, semantic)
            if semantic == 'companion-ready' then
                rejected = rejected + 1
                return false,
                    'companion ACK does not match current local authority'
            end
            return false, 'unrelated rejection'
        end,
    })
    local stale = harness({[signet_path]=signet})
    stale.load()
    stale.command({'ptgs', 'activate', 'locus-dire-bats-tomb-signet', '1.8.0'})
    local baseline = #stale.chat
    for _ = 1, 5 do
        stale.command({'ptgs', 'action', 'locus-signet', 'companion-ready',
            '1789667564-544906-697989001', '0'})
    end
    assert(rejected == 5 and #stale.chat == baseline + 1,
        'identical Signet ACK rejections were not silently bounded')
    assert(stale.chat[#stale.chat].message:find('retired generation', 1, true),
        'one-time ACK warning omitted recovery guidance')
    stale.command({'ptgs', 'action', 'locus-signet', 'companion-ready',
        '1789667564-544906-697989002', '0'})
    assert(#stale.chat == baseline + 2,
        'a distinct generation did not receive its own warning')
    stale.command({'ptgs', 'action', 'locus-signet', 'reject'})
    assert(#stale.chat == baseline + 3,
        'unrelated adapter failures were hidden by Signet suppression')
end

print('PartyTactics GearSwap host tests passed')
