local M = {}

local function copy_map(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function is_array(values)
    if type(values) ~= 'table' then return false end
    local count, maximum = 0, 0
    for key, _ in pairs(values) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    return count == maximum
end

local function basename(entry)
    if type(entry) ~= 'string' then return nil end
    entry = entry:gsub('[\\/]+$', '')
    return entry:match('([^\\/]+)$')
end

local function filename_id(entry)
    local name = basename(entry)
    return name and name:match('^([a-z0-9][a-z0-9_-]*)%.lua$') or nil
end

local function valid_sidecar(util, sidecar, id)
    if type(sidecar) ~= 'table' or sidecar.schema ~= 1
        or sidecar.target ~= id or not util.valid_id(sidecar.target, 64)
        or not is_array(sidecar.aliases) or #sidecar.aliases == 0
    then
        return false
    end
    local seen = {}
    for _, alias in ipairs(sidecar.aliases) do
        if not util.valid_id(alias, 48) or seen[alias] then return false end
        seen[alias] = true
    end
    return true
end

-- Each canonical target owns one isolated sidecar. Files load independently,
-- so a syntax or validation error cannot remove a shortcut supplied by a
-- sibling. Optional operator vocabulary is deliberately excluded from profile
-- behavior signatures: the leader resolves it before IPC sends a canonical id.
local function discover(util, root, get_dir, file_exists, load_file)
    local sidecars, errors = {}, {}
    local directory_ok, directory = pcall(get_dir, root)
    if not directory_ok or type(directory) ~= 'table' then
        return sidecars, {'sidecar directory could not be read: '
            ..tostring(directory)..'; shortcuts disabled.'}
    end
    local entries = {}
    for _, entry in pairs(directory) do entries[#entries + 1] = entry end
    table.sort(entries, function(left, right)
        local left_lower, right_lower = tostring(left):lower(),
            tostring(right):lower()
        if left_lower ~= right_lower then return left_lower < right_lower end
        return tostring(left) < tostring(right)
    end)

    local seen_files = {}
    local saw_lua = false
    for _, entry in ipairs(entries) do
        local name = basename(entry)
        local id = filename_id(entry)
        if name and name:lower():match('%.lua$') then
            saw_lua = true
            local path = root..name
            if not id or not util.valid_id(id, 64) then
                errors[#errors + 1] = tostring(name)
                    ..': invalid supplemental alias filename.'
            elseif seen_files[id] then
                errors[#errors + 1] = id
                    ..': duplicate supplemental alias sidecar.'
            else
                seen_files[id] = true
                local exists_ok, exists = pcall(file_exists, path)
                if not exists_ok then
                    errors[#errors + 1] = id..': file check failed: '
                        ..tostring(exists)
                elseif not exists then
                    errors[#errors + 1] = id
                        ..': supplemental alias sidecar is unavailable.'
                else
                    local load_ok, loader, load_error = pcall(load_file, path)
                    if not load_ok then
                        errors[#errors + 1] = id..': loader failed: '
                            ..tostring(loader)
                    elseif not loader then
                        errors[#errors + 1] = id..': '..tostring(load_error)
                    else
                        local ok, sidecar = pcall(loader)
                        if not ok or not valid_sidecar(util, sidecar, id) then
                            errors[#errors + 1] = id
                                ..': invalid isolated supplemental aliases.'
                        else
                            sidecars[#sidecars + 1] = sidecar
                        end
                    end
                end
            end
        end
    end
    if not saw_lua then
        errors[#errors + 1] = 'no supplemental alias sidecars found; '
            ..'shortcuts disabled.'
    end
    return sidecars, errors
end

function M.discover(...)
    local ok, sidecars, errors = pcall(discover, ...)
    if not ok then
        return {}, {'sidecar discovery failed: '..tostring(sidecars)
            ..'; shortcuts disabled.'}
    end
    return sidecars, errors
end

local function registry_namespace(util, registry)
    if type(registry) ~= 'table' or registry.schema ~= 1
        or not is_array(registry.reserved_commands)
        or not is_array(registry.identities)
    then
        return nil, nil
    end

    local owners, canonical_ids, policy_ids = {}, {}, {}
    for _, command in ipairs(registry.reserved_commands) do
        if not util.valid_id(command, 64) or owners[command] then
            return nil, nil
        end
        owners[command] = 'PartyTactics command'
    end
    for ordinal, identity in ipairs(registry.identities) do
        if type(identity) ~= 'table' or identity.ordinal ~= ordinal
            or not util.valid_id(identity.id, 64)
            or not util.valid_id(identity.policy_id, 64)
            or not is_array(identity.aliases)
            or owners[identity.id] or canonical_ids[identity.id]
            or policy_ids[identity.policy_id]
        then
            return nil, nil
        end
        canonical_ids[identity.id] = true
        policy_ids[identity.policy_id] = true
        owners[identity.id] = 'canonical profile '..identity.id
        for _, alias in ipairs(identity.aliases) do
            if not util.valid_id(alias, 64) or owners[alias] then
                return nil, nil
            end
            owners[alias] = 'profile alias for '..identity.id
        end
    end
    return owners, canonical_ids
end

-- Apply only direct references to canonical profiles that survived every
-- compile and dependency check. Ambiguous shortcuts are disabled as a group;
-- established aliases are copied and can never be removed or overwritten.
local function apply(util, sidecars, profiles, established_aliases,
    identity_registry, manual_actions)
    local result = copy_map(established_aliases)
    local errors = {}
    local namespace, canonical_ids = registry_namespace(
        util, identity_registry)
    if not namespace then
        errors[#errors + 1] = 'identity namespace is invalid; shortcuts disabled.'
        return result, errors
    end
    if not is_array(sidecars) then
        errors[#errors + 1] = 'sidecar set is invalid; shortcuts disabled.'
        return result, errors
    end

    local claims = {}
    for index, sidecar in ipairs(sidecars) do
        if not valid_sidecar(util, sidecar, sidecar and sidecar.target) then
            errors[#errors + 1] = ('sidecar %d is invalid; shortcuts ignored.')
                :format(index)
        else
            for _, alias in ipairs(sidecar.aliases) do
                claims[alias] = claims[alias] or {}
                claims[alias][#claims[alias] + 1] = sidecar.target
            end
        end
    end

    for _, alias in ipairs(util.sorted_keys(claims)) do
        local targets = claims[alias]
        local target = targets[1]
        if #targets > 1 then
            errors[#errors + 1] = ('shortcut %s is claimed by %s; shortcut disabled.')
                :format(alias, table.concat(targets, ', '))
        elseif namespace[alias] then
            errors[#errors + 1] = ('shortcut %s conflicts with %s; shortcut ignored.')
                :format(alias, namespace[alias])
        elseif (established_aliases or {})[alias] then
            errors[#errors + 1] = ('shortcut %s conflicts with an established '
                ..'profile alias; shortcut ignored.'):format(alias)
        elseif (manual_actions or {})[alias] then
            errors[#errors + 1] = ('shortcut %s conflicts with a profile manual '
                ..'action; shortcut ignored.'):format(alias)
        elseif not canonical_ids[target] then
            errors[#errors + 1] = ('shortcut %s target %s is not a canonical '
                ..'profile id; shortcut ignored.'):format(alias, target)
        elseif not profiles[target] or profiles[target].id ~= target then
            errors[#errors + 1] = ('shortcut %s target %s is unavailable or '
                ..'quarantined; shortcut ignored.'):format(alias, target)
        else
            result[alias] = target
        end
    end
    return result, errors
end

function M.apply(util, sidecars, profiles, established_aliases,
    identity_registry, manual_actions)
    local ok, result, errors = pcall(apply, util, sidecars, profiles,
        established_aliases, identity_registry, manual_actions)
    if not ok then
        return copy_map(established_aliases),
            {'shortcut application failed: '..tostring(result)
                ..'; shortcuts disabled.'}
    end
    return result, errors
end

return M
