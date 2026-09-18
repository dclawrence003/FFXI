local M = {}

local UINT32_MAX = 4294967295

local CONTROLLERS = {
    brd={
        prefix='pstartbrd',
        actions={sleep='none', warble='ability-id',
            warblecomplete='ability-id'},
    },
    rdm={
        prefix='pstartrdm',
        -- Exact hostile targets are the only runtime-owned RDM request. The
        -- controller validates the live mob again and owns queuing/retries.
        actions={silence='uint32'},
    },
}

local function safe_label(value, maximum)
    return type(value) == 'string' and value ~= ''
        and #value <= (maximum or 64)
        and value:match("^[A-Za-z0-9][A-Za-z0-9 ._'+-]*$") ~= nil
end

local function safe_target(value)
    if type(value) ~= 'string' or #value > 18 then return false end
    local numeric_id = value:match('^%d+$') and tonumber(value) or nil
    return value:match('^<[A-Za-z0-9]+>$') ~= nil
        or value:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        -- A resolved server ID is safer than a typed monster name: installed
        -- GearSwap deliberately excludes ordinary NPC enemies from its named
        -- target resolver. IDs remain bounded and contain no command syntax.
        or (numeric_id ~= nil and numeric_id >= 1
            and numeric_id <= 4294967295)
end

local function safe_controller_argument(value)
    value = tostring(value or '')
    return value ~= '' and #value <= 64
        and value:match('^[A-Za-z0-9_-]+$') ~= nil
end

local function normalized_uint32(value)
    if type(value) == 'string' then
        if #value == 0 or #value > 10 or value:match('^%d+$') == nil then
            return nil
        end
        value = tonumber(value)
    elseif type(value) ~= 'number' then
        return nil
    end
    if value ~= value or value < 1 or value > UINT32_MAX
        or value ~= math.floor(value)
    then
        return nil
    end
    return ('%.0f'):format(value)
end

local function normalized_member_csv(members)
    if type(members) ~= 'table' then return nil end
    local count, names, seen = 0, {}, {}
    for key in pairs(members) do
        if type(key) ~= 'number' or key < 1 or key > 6
            or key ~= math.floor(key)
        then
            return nil
        end
        count = count + 1
    end
    if count < 1 or count > 6 or count ~= #members then return nil end
    for index=1,#members do
        local name = members[index]
        if type(name) ~= 'string' or #name < 1 or #name > 15
            or name:match('^[A-Za-z][A-Za-z0-9_-]*$') == nil
            or seen[name:lower()]
        then
            return nil
        end
        seen[name:lower()] = true
        names[#names + 1] = name
    end
    return table.concat(names, ',')
end

local function quoted_action(issue, kind, name, target)
    if not safe_label(name, 64) or not safe_target(target) then
        return false, 'invalid action name or target'
    end
    issue(('input /%s "%s" %s'):format(kind, name, target))
    return true
end

function M.create(issue, authority)
    assert(type(issue) == 'function', 'action API requires an issue function')
    local api = {}
    local client = {}

    function api.cast(spell, target)
        return quoted_action(issue, 'ma', spell, target)
    end

    function api.ability(ability, target)
        return quoted_action(issue, 'ja', ability, target)
    end

    function api.weaponskill(weaponskill, target)
        return quoted_action(issue, 'ws', weaponskill, target)
    end

    function api.item(item, target)
        return quoted_action(issue, 'item', item, target)
    end

    function api.controller(controller, action, ...)
        local contract = CONTROLLERS[controller]
        local shape = contract and contract.actions[action] or nil
        if not shape then return false, 'unknown controller action' end
        local arguments = {...}
        if shape == 'none' and #arguments ~= 0 then
            return false, 'controller action accepts no arguments'
        elseif shape == 'ability-id' and (#arguments ~= 1
            or tostring(arguments[1]):match('^%d+$') == nil)
        then
            return false, 'controller action requires one ability id'
        elseif shape == 'uint32' then
            if #arguments ~= 1 then
                return false, 'controller action requires one exact target id'
            end
            local encoded = normalized_uint32(arguments[1])
            if not encoded then
                return false, 'invalid controller target id'
            end
            arguments[1] = encoded
        elseif shape == 'probe' then
            local generation = arguments[1]
            local epoch = tonumber(arguments[2])
            local protocol = tonumber(arguments[3])
            if #arguments ~= 3 or type(generation) ~= 'string'
                or generation:match('^%d+%-%d+%-%d+$') == nil
                or not epoch or epoch < 0 or epoch ~= math.floor(epoch)
                or not protocol or protocol < 1 or protocol > 999
                or protocol ~= math.floor(protocol)
            then
                return false, 'controller probe requires generation, epoch, and protocol'
            end
            arguments[2] = ('%.0f'):format(epoch)
            arguments[3] = ('%.0f'):format(protocol)
        end
        local encoded = {action}
        for _, argument in ipairs(arguments) do
            if not safe_controller_argument(argument) then
                return false, 'invalid controller argument'
            end
            encoded[#encoded + 1] = tostring(argument)
        end
        -- This is a request to a GearSwap-owned controller. Profiles never
        -- receive an equip API, a raw command API, or access to slot locks.
        issue(('gs c %s %s'):format(
            contract.prefix, table.concat(encoded, ' ')))
        return true
    end

    -- Profile runtimes use only this semantic surface for a pinned GearSwap
    -- adapter. The profile/core validates the controller and semantic; this
    -- final boundary validates the encounter, optional exact subject, and
    -- current authority epoch.
    function api.profile_adapter(controller, action, target_id, request_token,
        subject_id)
        if not safe_controller_argument(controller)
            or not safe_controller_argument(action)
            or (request_token ~= nil
                and not safe_controller_argument(request_token))
        then
            return false, 'invalid profile adapter controller or action'
        end
        local encoded_id = normalized_uint32(target_id)
        if not encoded_id then return false, 'invalid controller target id' end
        local encoded_subject_id
        if subject_id ~= nil then
            encoded_subject_id = normalized_uint32(subject_id)
            if not encoded_subject_id then
                return false, 'invalid controller subject id'
            end
        end
        local generation, epoch
        if type(authority) == 'function' then
            generation, epoch = authority()
        end
        epoch = tonumber(epoch)
        if type(generation) ~= 'string'
            or generation:match('^%d+%-%d+%-%d+$') == nil
            or not epoch or epoch < 0 or epoch ~= math.floor(epoch)
        then
            return false, 'current profile adapter authority is unavailable'
        end
        local command = ('gs c ptgs action %s %s %s %s %.0f'):format(
            controller, action, encoded_id, generation, epoch)
        if request_token ~= nil then
            command = command..' '..tostring(request_token)
        end
        if encoded_subject_id ~= nil then
            -- Keep the established five-token authority payload byte-for-byte
            -- identical when no subject is present. A dash is an internal
            -- positional sentinel only when a subject has no event token.
            if request_token == nil then command = command..' -' end
            command = command..' '..encoded_subject_id
        end
        issue(command)
        return true
    end

    function api.profile_adapter_probe(controller, generation, epoch,
        protocol)
        epoch, protocol = tonumber(epoch), tonumber(protocol)
        if not safe_controller_argument(controller)
            or type(generation) ~= 'string'
            or generation:match('^%d+%-%d+%-%d+$') == nil
            or not epoch or epoch < 0 or epoch ~= math.floor(epoch)
            or not protocol or protocol < 1 or protocol > 999
            or protocol ~= math.floor(protocol)
        then
            return false, 'invalid profile adapter probe'
        end
        issue(('gs c ptgs action %s probe %s %.0f %.0f'):format(
            controller, generation, epoch, protocol))
        return true
    end

    function api.combat_force(id, opaque_enemy_name)
        local encoded = normalized_uint32(id)
        if not encoded then return false, 'invalid combat target id' end
        if opaque_enemy_name ~= nil then
            if type(opaque_enemy_name) ~= 'string'
                or #opaque_enemy_name < 1 or #opaque_enemy_name > 64
                or opaque_enemy_name:match(
                    '^[A-Za-z0-9][A-Za-z0-9 _-]*$') == nil
            then
                return false, 'invalid opaque combat target name'
            end
            local name_token = opaque_enemy_name:gsub(' ', '_')
            issue(('pc forceopaqueid %s %s'):format(encoded, name_token))
            return true
        end
        issue('pc forceid '..encoded)
        return true
    end

    function api.combat_force_members(id, members)
        local encoded = normalized_uint32(id)
        local recipients = normalized_member_csv(members)
        if not encoded then return false, 'invalid combat target id' end
        if not recipients then
            return false, 'invalid combat target member list'
        end
        issue(('pc forceidto %s %s'):format(encoded, recipients))
        return true
    end

    function api.combat_stop_members(members)
        local recipients = normalized_member_csv(members)
        if not recipients then
            return false, 'invalid combat stop member list'
        end
        issue('pc stopto '..recipients)
        return true
    end

    function api.combat_observe(id)
        local encoded = normalized_uint32(id)
        if not encoded then return false, 'invalid combat target id' end
        issue('pc observeid '..encoded)
        return true
    end

    function api.combat_stop()
        issue('pc off')
        return true
    end

    function client.auto_target(enabled)
        if type(enabled) ~= 'boolean' then
            return false, 'auto-target state must be boolean'
        end
        issue('input /autotarget '..(enabled and 'on' or 'off'))
        return true
    end

    function client.engage_once(id)
        local encoded = normalized_uint32(id)
        if not encoded then return false, 'invalid one-shot engage target id' end
        issue('pc engageonceid '..encoded)
        return true
    end

    return api, client
end

return M
