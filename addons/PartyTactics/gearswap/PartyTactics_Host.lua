-- PartyTactics stable GearSwap adapter host.
--
-- Install this file once, at the true end of a GearSwap job file:
--
--     include('Common/PartyTactics/PartyTactics_Host.lua')
--
-- Loading the host does not activate a fight adapter.  While inactive, every
-- captured GearSwap callback is called with the original arguments and its
-- return values pass straight through.  The host never equips gear and never
-- accepts arbitrary spell, ability, item, or equipment names.
--
-- Adapter contract (all calls use dot syntax; no implicit `self` is passed):
--
-- Required metadata:
--   id          canonical lower-case adapter id
--   version     exact semantic version used in the activation command
--   controller  canonical lower-case controller id accepted by actions
--   protocol    integer 1 or 2
--
-- Required methods:
--   activate() -> true | false, reason
--   deactivate(reason)                         return value ignored
--   handle_action(controller, semantic, args) -> true | false, reason
--   status() -> nil | short string
--
-- Optional GearSwap methods:
--   pre_tick(...) -> consumed_boolean
--   user_job_tick(...) -> consumed_boolean
--   user_job_self_command(command_args, event_args) -> consumed_boolean
--   filter_pretarget(spell, spell_map, event_args) -> block_boolean
--   filter_precast(spell, spell_map, event_args) -> block_boolean
--   job_aftercast(spell, spell_map, event_args)
--   file_unload(...)
--
-- Optional raw Windower event methods:
--   action_event(...), prerender(...), zone_change(...), logout(...),
--   unload(...), status_change(...)
--
-- A tick is reserved only when its adapter method returns exactly true.  A
-- filter blocks only when it returns exactly true; the host then sets
-- event_args.cancel itself.  Observer return values are ignored and native
-- aftercast/unload callbacks always remain chained.  Any adapter exception
-- immediately removes that adapter, invalidates its cached module, calls its
-- deactivate method once, and resumes the captured native callback.  Invalid
-- activation and malformed or rejected actions execute nothing.

local HOST_GLOBAL = '__PARTYTACTICS_GEARSWAP_HOST_V1'
local HOST_PROTOCOL = 1
local HOST_REVISION = '1.2.1'
local SUPPORTED_ADAPTER_PROTOCOLS = {[1]=true, [2]=true}
local last_signet_companion_rejection = nil

local existing = type(_G) == 'table' and rawget(_G, HOST_GLOBAL) or nil
if type(existing) == 'table' and existing.revision == HOST_REVISION then
    return existing
end

if type(windower) ~= 'table'
    or type(windower.raw_register_event) ~= 'function'
    or type(include) ~= 'function'
then
    error('PartyTactics GearSwap host requires GearSwap include and raw events')
end

local original = {
    pre_tick=pre_tick,
    user_job_tick=user_job_tick,
    user_filter_pretarget=user_filter_pretarget,
    user_filter_precast=user_filter_precast,
    job_aftercast=job_aftercast,
    user_job_self_command=user_job_self_command,
    file_unload=file_unload,
}

local OPTIONAL_METHODS = {
    'pre_tick', 'user_job_tick', 'user_job_self_command',
    'filter_pretarget', 'filter_precast', 'job_aftercast', 'file_unload',
    'action_event', 'prerender', 'zone_change', 'logout', 'unload',
    'status_change',
}

local REQUIRED_METHODS = {
    'activate', 'deactivate', 'handle_action', 'status',
}

local active
local verified_cache = {}

local function say(message, color)
    local text = '[PartyTactics/GS] '..tostring(message)
    if type(add_to_chat) == 'function' then
        pcall(add_to_chat, color or 207, text)
    elseif type(windower.add_to_chat) == 'function' then
        pcall(windower.add_to_chat, color or 207, text)
    end
end

local function notify_host_lost(reason)
    if type(windower.send_command) == 'function' then
        pcall(windower.send_command,
            'pt __gearswap_host_lost '..HOST_REVISION..' '..tostring(reason))
    end
end

local function short_reason(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    value = value:gsub('[\r\n]', ' ')
    if #value > 160 then value = value:sub(1, 160) end
    return value
end

local function safe_identifier(value)
    return type(value) == 'string' and #value >= 1 and #value <= 64
        and value:match('^[a-z0-9][a-z0-9%-]*$') ~= nil
end

local function safe_semantic(value)
    return type(value) == 'string' and #value >= 1 and #value <= 64
        and value:match('^[a-z0-9][a-z0-9_%-]*$') ~= nil
end

local function safe_generation(value)
    return type(value) == 'string' and #value >= 5 and #value <= 64
        and value:match('^%d+%-%d+%-%d+$') ~= nil
end

local function safe_epoch(value)
    if type(value) ~= 'string' or #value == 0 or #value > 12
        or value:match('^%d+$') == nil
    then return nil end
    local number = tonumber(value)
    if not number or number < 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function valid_identifier_list(value, numeric_rules)
    if value == '' or value:sub(1, 1) == '.' or value:sub(-1) == '.'
        or value:find('..', 1, true)
    then
        return false
    end
    for identifier in value:gmatch('[^.]+') do
        if identifier:match('^[0-9A-Za-z%-]+$') == nil then return false end
        if numeric_rules and identifier:match('^%d+$')
            and #identifier > 1 and identifier:sub(1, 1) == '0'
        then
            return false
        end
    end
    return true
end

local function safe_semver(value)
    if type(value) ~= 'string' or #value < 5 or #value > 64
        or value:match('^[0-9A-Za-z%.%+%-]+$') == nil
    then
        return false
    end
    local major, minor, patch, suffix = value:match(
        '^(%d+)%.(%d+)%.(%d+)(.*)$')
    if not major or (#major > 1 and major:sub(1, 1) == '0')
        or (#minor > 1 and minor:sub(1, 1) == '0')
        or (#patch > 1 and patch:sub(1, 1) == '0')
    then
        return false
    end
    if suffix == '' then return true end
    if suffix:sub(1, 1) == '+' then
        return valid_identifier_list(suffix:sub(2), false)
    end
    if suffix:sub(1, 1) ~= '-' then return false end
    local prerelease, build = suffix:sub(2):match('^([^%+]+)%+(.+)$')
    if not prerelease then prerelease = suffix:sub(2) end
    if not valid_identifier_list(prerelease, true) then return false end
    return build == nil or valid_identifier_list(build, false)
end

local function module_path(adapter_id, version)
    return 'Common/PartyTactics/adapters/'..adapter_id..'/'..version..'.lua'
end

local function validate_module(module, adapter_id, version, path)
    if type(module) ~= 'table' then
        return nil, 'adapter module did not return a table'
    end
    if module.id ~= adapter_id then return nil, 'adapter id mismatch' end
    if module.version ~= version then return nil, 'adapter version mismatch' end
    if not safe_identifier(module.controller) then
        return nil, 'adapter controller is invalid'
    end
    if not SUPPORTED_ADAPTER_PROTOCOLS[module.protocol] then
        return nil, 'adapter protocol mismatch'
    end
    local callbacks = {}
    for _, name in ipairs(REQUIRED_METHODS) do
        if type(module[name]) ~= 'function' then
            return nil, 'adapter is missing required method '..name
        end
        callbacks[name] = module[name]
    end
    for _, name in ipairs(OPTIONAL_METHODS) do
        if module[name] ~= nil and type(module[name]) ~= 'function' then
            return nil, 'adapter method '..name..' is not callable'
        end
        callbacks[name] = module[name]
    end
    return {
        id=adapter_id,
        version=version,
        controller=module.controller,
        protocol=module.protocol,
        path=path,
        callbacks=callbacks,
    }
end

local function load_verified(adapter_id, version)
    local path = module_path(adapter_id, version)
    if verified_cache[path] then return verified_cache[path] end
    local ok, module = pcall(include, path)
    if not ok then
        return nil, 'include failed: '..short_reason(module, 'unknown include error')
    end
    local record, validation_error = validate_module(
        module, adapter_id, version, path)
    if not record then return nil, validation_error end
    verified_cache[path] = record
    return record
end

local function call_deactivate(record, reason)
    local ok, failure = pcall(record.callbacks.deactivate, reason)
    if not ok then
        say('adapter '..record.id..' deactivate failed: '
            ..short_reason(failure, 'unknown error'), 167)
    end
end

local function deactivate(reason, invalidate)
    local record = active
    if not record then return false end
    active = nil
    if invalidate then verified_cache[record.path] = nil end
    call_deactivate(record, reason or 'off')
    return true
end

local function fail_adapter(record, method, failure)
    if active ~= record then return end
    active = nil
    verified_cache[record.path] = nil
    -- Adapter cleanup is best-effort.  Revoke the distributed PartyTactics
    -- authority before calling it so even a broken deactivate callback cannot
    -- leave PartyCombat armed behind a dead controller.
    notify_host_lost('adapter-error')
    call_deactivate(record, 'error:'..method)
    say('adapter '..record.id..' failed in '..method..': '
        ..short_reason(failure, 'unknown error')..'; now inactive', 167)
end

local function invoke(record, method, ...)
    local callback = record and record.callbacks[method]
    if type(callback) ~= 'function' then return true, nil end
    local ok, first, second = pcall(callback, ...)
    if not ok then
        fail_adapter(record, method, first)
        return false, nil, first
    end
    return true, first, second
end

local function activate(adapter_id, version)
    if not safe_identifier(adapter_id) then
        say('activation rejected: invalid adapter id', 167)
        return false
    end
    if not safe_semver(version) then
        say('activation rejected: invalid semantic version', 167)
        return false
    end
    if active and active.id == adapter_id and active.version == version then
        -- PartyTactics may reassert an exact lifecycle adapter while its
        -- standalone helpers are still starting. Same-version activation is
        -- deliberately silent and state preserving.
        return true
    end

    deactivate('replaced', false)
    local record, load_error = load_verified(adapter_id, version)
    if not record then
        say('activation rejected for '..adapter_id..'@'..version..': '
            ..short_reason(load_error, 'invalid adapter'), 167)
        return false
    end

    -- Make the candidate visible only while its activation callback runs, so
    -- partial initialization can be cleaned up through the same path.
    active = record
    local ok, accepted, reason = invoke(record, 'activate')
    if not ok then return false end
    if accepted ~= true then
        active = nil
        verified_cache[record.path] = nil
        call_deactivate(record, 'activation-rejected')
        say('activation rejected for '..adapter_id..'@'..version..': '
            ..short_reason(reason, 'adapter did not accept activation'), 167)
        return false
    end
    say('active '..adapter_id..'@'..version..' controller='
        ..record.controller..' protocol='..record.protocol)
    return true
end

local function active_status()
    local record = active
    if not record then
        say('inactive')
        return
    end
    local ok, detail = invoke(record, 'status')
    if not ok then return end
    if detail ~= nil and type(detail) ~= 'string' then
        fail_adapter(record, 'status', 'status returned a non-string value')
        return
    end
    local message = 'active '..record.id..'@'..record.version
        ..' controller='..record.controller..' protocol='..record.protocol
    if detail and detail ~= '' then
        message = message..' '..short_reason(detail, '')
    end
    say(message)
end

local function copy_action_arguments(command_args, first_index)
    local result = {}
    if #command_args - first_index + 1 > 32 then
        return nil, 'too many action arguments'
    end
    for index = first_index, #command_args do
        local value = command_args[index]
        if type(value) ~= 'string' or #value > 256 then
            return nil, 'invalid action argument'
        end
        result[#result + 1] = value
    end
    return result
end

local function route_action(command_args)
    local record = active
    if not record then
        say('action rejected: no active adapter', 167)
        return false
    end
    local controller = command_args[3]
    local semantic = command_args[4]
    if not safe_identifier(controller) or controller ~= record.controller then
        say('action rejected: controller does not match active adapter', 167)
        return false
    end
    if not safe_semantic(semantic) then
        say('action rejected: invalid semantic', 167)
        return false
    end
    local arguments, argument_error = copy_action_arguments(command_args, 5)
    if not arguments then
        say('action rejected: '..argument_error, 167)
        return false
    end
    local ok, accepted, reason = invoke(
        record, 'handle_action', controller, semantic, arguments)
    if not ok then return false end
    if accepted ~= true then
        if record.id == 'locus-dire-bats-tomb-signet'
            and semantic == 'companion-ready'
            and reason == 'companion ACK does not match current local authority'
        then
            local tuple = tostring(arguments[1])..'/'..tostring(arguments[2])
            if last_signet_companion_rejection ~= tuple then
                last_signet_companion_rejection = tuple
                say('stale Locus Signet companion ACK for '..tuple
                    ..'; further identical rejects are silent. Check //pt status '
                    ..'and //sk status; a retired generation needs //pt off '
                    ..'then //pt locus-signet.', 167)
            end
            return false
        end
        say('action rejected by '..record.id..': '
            ..short_reason(reason, 'unsupported or unsafe action'), 167)
        return false
    end
    return true
end

local function handle_host_command(command_args, event_args)
    if type(event_args) == 'table' then event_args.handled = true end
    local operation = command_args[2]
    if operation == 'activate' then
        if #command_args ~= 4 then
            say('usage: ptgs activate <adapter-id> <semver>', 167)
            return
        end
        activate(command_args[3], command_args[4])
    elseif operation == 'probe' then
        if #command_args ~= 4 or not safe_generation(command_args[3])
            or safe_epoch(command_args[4]) == nil
        then
            say('usage: ptgs probe <generation> <epoch>', 167)
            return
        end
        -- This proves the stable host wrapper itself executed in the current
        -- GearSwap job file. It is independent of any optional fight adapter.
        windower.send_command(('pt __gearswap_host_ready %s %s %d')
            :format(HOST_REVISION, command_args[3],
                safe_epoch(command_args[4])))
    elseif operation == 'action' then
        if #command_args < 4 then
            say('usage: ptgs action <controller> <semantic> [arguments...]', 167)
            return
        end
        route_action(command_args)
    elseif operation == 'status' then
        if #command_args ~= 2 then
            say('usage: ptgs status', 167)
            return
        end
        active_status()
    elseif operation == 'off' then
        if #command_args ~= 2 then
            say('usage: ptgs off', 167)
            return
        end
        if deactivate('command', false) then
            say('inactive')
        else
            say('already inactive')
        end
    else
        say('unknown ptgs command', 167)
    end
end

local function adapter_consumes(method, ...)
    local record = active
    if not record or type(record.callbacks[method]) ~= 'function' then
        return false
    end
    local ok, consumed = invoke(record, method, ...)
    return ok and consumed == true
end

local function adapter_observes(method, ...)
    local record = active
    if not record or type(record.callbacks[method]) ~= 'function' then return end
    invoke(record, method, ...)
end

function pre_tick(...)
    if adapter_consumes('pre_tick', ...) then return true end
    if type(original.pre_tick) == 'function' then return original.pre_tick(...) end
end

function user_job_tick(...)
    if adapter_consumes('user_job_tick', ...) then return true end
    if type(original.user_job_tick) == 'function' then
        return original.user_job_tick(...)
    end
end

function user_filter_pretarget(spell, spell_map, event_args)
    if adapter_consumes('filter_pretarget', spell, spell_map, event_args) then
        if type(event_args) == 'table' then event_args.cancel = true end
        return
    end
    if type(original.user_filter_pretarget) == 'function' then
        return original.user_filter_pretarget(spell, spell_map, event_args)
    end
end

function user_filter_precast(spell, spell_map, event_args)
    if adapter_consumes('filter_precast', spell, spell_map, event_args) then
        if type(event_args) == 'table' then event_args.cancel = true end
        return
    end
    if type(original.user_filter_precast) == 'function' then
        return original.user_filter_precast(spell, spell_map, event_args)
    end
end

function job_aftercast(spell, spell_map, event_args)
    adapter_observes('job_aftercast', spell, spell_map, event_args)
    if type(original.job_aftercast) == 'function' then
        return original.job_aftercast(spell, spell_map, event_args)
    end
end

function user_job_self_command(command_args, event_args)
    if type(command_args) == 'table'
        and type(command_args[1]) == 'string'
        and command_args[1]:lower() == 'ptgs'
    then
        handle_host_command(command_args, event_args)
        return
    end
    -- This hook is intentionally narrower than the spell/action filters. It
    -- lets one versioned adapter consume only a coordinator-generated helper
    -- tick while retaining a higher-priority queued action. Adapters that do
    -- not implement it, inactive hosts, and every non-consumed command keep
    -- the captured job file's exact behavior and return values.
    if adapter_consumes('user_job_self_command', command_args, event_args) then
        if type(event_args) == 'table' then event_args.handled = true end
        return true
    end
    if type(original.user_job_self_command) == 'function' then
        return original.user_job_self_command(command_args, event_args)
    end
end

function file_unload(...)
    local record = active
    adapter_observes('file_unload', ...)
    if active == record then deactivate('file-unload', false) end
    -- A GearSwap job reload discards both the stable host and every frozen
    -- compatibility helper. PartyTactics must revoke the distributed profile
    -- instead of continuing with a stale application ACK.
    notify_host_lost('file-unload')
    if type(original.file_unload) == 'function' then
        return original.file_unload(...)
    end
end

windower.raw_register_event('action', function(...)
    adapter_observes('action_event', ...)
end)

windower.raw_register_event('prerender', function(...)
    adapter_observes('prerender', ...)
end)

windower.raw_register_event('zone change', function(...)
    adapter_observes('zone_change', ...)
end)

windower.raw_register_event('logout', function(...)
    local record = active
    adapter_observes('logout', ...)
    if active == record then deactivate('logout', false) end
    notify_host_lost('logout')
end)

windower.raw_register_event('unload', function(...)
    local record = active
    adapter_observes('unload', ...)
    if active == record then deactivate('unload', false) end
    notify_host_lost('addon-unload')
end)

windower.raw_register_event('status change', function(...)
    adapter_observes('status_change', ...)
end)

local host = {
    revision=HOST_REVISION,
    protocol=HOST_PROTOCOL,
}

function host.active_metadata()
    if not active then return nil end
    return {
        id=active.id,
        version=active.version,
        controller=active.controller,
        protocol=active.protocol,
    }
end

if type(_G) == 'table' then rawset(_G, HOST_GLOBAL, host) end
return host
