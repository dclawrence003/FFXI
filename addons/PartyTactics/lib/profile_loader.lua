local M = {}

-- These public controls and already-published direct shorthands predate every
-- profile identity in the v1 registry. They are immutable namespace owners.
-- A future shorthand is processed only after all append-only identities, so
-- adding it can never quarantine an older profile that already owns the name.
local IMMUTABLE_COMMANDS = {
    'use','preview','reapply','on','start','off','stop','arm','disarm',
    'force','action','status','check','preflight','version','list','show',
    'errors','audit','sleep',
    'acumen','clarion','ballad2','crusade','emblem','sentinel','flash',
    'provoke','cdc','leaden','wildfire','rudra','blizzard','silence',
}

local function normalize_entry(entry)
    if type(entry) ~= 'string' then return nil end
    entry = entry:gsub('[\\/]+$', '')
    return entry:match('([^\\/]+)$')
end

local function same_aliases(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table'
        or #left ~= #right
    then
        return false
    end
    local expected = {}
    for _, alias in ipairs(left) do
        if expected[alias] then return false end
        expected[alias] = true
    end
    for _, alias in ipairs(right) do
        if not expected[alias] then return false end
        expected[alias] = nil
    end
    return next(expected) == nil
end

local function prepare_registry(util, registry)
    if registry == nil then return nil, {} end
    local state = {by_id={}, policy_owner={}, command_owner={}}
    local errors = {}
    if type(registry) ~= 'table' or registry.schema ~= 1
        or type(registry.reserved_commands) ~= 'table'
        or type(registry.identities) ~= 'table'
    then
        errors[#errors + 1] = 'Profile identity registry is invalid.'
        return state, errors
    end
    local immutable, seen_reserved, later_commands = {}, {}, {}
    for _, command in ipairs(IMMUTABLE_COMMANDS) do
        immutable[command] = true
        state.command_owner[command] = 'PartyTactics command'
    end
    for _, command in ipairs(registry.reserved_commands) do
        if not util.valid_id(command, 64) or seen_reserved[command] then
            errors[#errors + 1] = ('Profile identity registry reserved command '
                ..'%s is invalid or duplicated.'):format(tostring(command))
        elseif immutable[command] then
            seen_reserved[command] = true
        else
            seen_reserved[command] = true
            later_commands[#later_commands + 1] = command
        end
    end
    for index, identity in ipairs(registry.identities) do
        local valid = type(identity) == 'table'
            and identity.ordinal == index
            and util.valid_id(identity.id, 64)
            and util.valid_id(identity.policy_id, 64)
            and type(identity.aliases) == 'table'
        local claims, seen = {}, {}
        if valid then
            claims[#claims + 1] = identity.id
            seen[identity.id] = true
            for _, alias in ipairs(identity.aliases) do
                if not util.valid_id(alias, 64) or seen[alias] then
                    valid = false
                    break
                end
                seen[alias] = true
                claims[#claims + 1] = alias
            end
        end
        if not valid then
            errors[#errors + 1] = ('Profile identity registry entry %d is '
                ..'invalid; that entry was ignored.'):format(index)
        elseif state.by_id[identity.id]
            or state.policy_owner[identity.policy_id]
        then
            errors[#errors + 1] = ('Profile identity registry entry %s '
                ..'reuses an established id or policy_id; later entry '
                ..'ignored.'):format(identity.id)
        else
            local collision
            for _, command in ipairs(claims) do
                if state.command_owner[command] then
                    collision = command
                    break
                end
            end
            if collision then
                errors[#errors + 1] = ('Profile identity registry entry %s '
                    ..'reuses established command %s; later entry ignored.')
                    :format(identity.id, collision)
            else
                state.by_id[identity.id] = identity
                state.policy_owner[identity.policy_id] = identity.id
                for _, command in ipairs(claims) do
                    state.command_owner[command] = identity.id
                end
            end
        end
    end
    for _, command in ipairs(later_commands) do
        if state.command_owner[command] then
            errors[#errors + 1] = ('Profile identity registry reserved '
                ..'command %s conflicts with established owner %s; later '
                ..'command ignored.'):format(command,
                    tostring(state.command_owner[command]))
        else
            state.command_owner[command] = 'PartyTactics command'
        end
    end
    return state, errors
end

local function identity_matches(profile, identity)
    return identity and profile.policy_id == identity.policy_id
        and same_aliases(profile.aliases or {}, identity.aliases or {})
end

function M.discover(util, schema, root, get_dir, file_exists, load_file,
    source_digest, identity_registry)
    local profiles, aliases, errors = {}, {}, {}
    local registry, registry_errors = prepare_registry(util, identity_registry)
    for _, message in ipairs(registry_errors) do errors[#errors + 1] = message end
    local entries = {}
    for _, entry in pairs(get_dir(root) or {}) do
        entries[#entries + 1] = entry
    end
    table.sort(entries, function(left, right)
        return tostring(left):lower() < tostring(right):lower()
    end)

    for _, entry in ipairs(entries) do
        local directory_id = normalize_entry(entry)
        if util.valid_id(directory_id, 64) then
            local path = root..directory_id..'/profile.lua'
            if file_exists(path) then
                local loader, load_error = load_file(path)
                if not loader then
                    errors[#errors + 1] = directory_id..': '..tostring(load_error)
                else
                    local ok, profile = pcall(loader)
                    if not ok then
                        errors[#errors + 1] = directory_id..': '..tostring(profile)
                    else
                        local validation_ok, validation = pcall(
                            schema.validate, util, profile, directory_id)
                        if not validation_ok then
                            errors[#errors + 1] = directory_id
                                ..': schema validation failed: '
                                ..tostring(validation)
                        elseif #validation > 0 then
                            errors[#errors + 1] = directory_id..': '
                                ..table.concat(validation, ' ')
                        elseif registry and not registry.by_id[profile.id] then
                            errors[#errors + 1] = directory_id
                                ..': missing immutable profile identity '
                                ..'registry entry.'
                        elseif registry and not identity_matches(
                            profile, registry.by_id[profile.id])
                        then
                            errors[#errors + 1] = directory_id
                                ..': profile policy_id or aliases differ '
                                ..'from its immutable identity registry entry.'
                        elseif profiles[profile.id] then
                            errors[#errors + 1] = 'Duplicate profile '..profile.id..'.'
                        else
                            profile.__profile_source_digest = source_digest
                                and source_digest(path) or 'unavailable'
                            local valid_assets = true
                            local artifact = profile.easyfarm
                                and profile.easyfarm.artifact or nil
                            if artifact then
                                local artifact_path = root..directory_id..'/'
                                    ..artifact
                                if not file_exists(artifact_path) then
                                    errors[#errors + 1] = directory_id
                                        ..' EasyFarm artifact is missing: '
                                        ..artifact
                                    valid_assets = false
                                else
                                    profile.__easyfarm_source_digest =
                                        source_digest
                                            and source_digest(artifact_path)
                                            or 'unavailable'
                                end
                            else
                                profile.__easyfarm_source_digest = 'none'
                            end
                            local valid_runtime = true
                            local runtime_path = root..directory_id..'/runtime.lua'
                            if file_exists(runtime_path) then
                                local runtime_loader, runtime_error = load_file(runtime_path)
                                if not runtime_loader then
                                    errors[#errors + 1] = directory_id
                                        ..' runtime: '..tostring(runtime_error)
                                    valid_runtime = false
                                else
                                    local runtime_ok, runtime = pcall(runtime_loader)
                                    if not runtime_ok or type(runtime) ~= 'table'
                                        or type(runtime.create) ~= 'function'
                                    then
                                        errors[#errors + 1] = directory_id
                                            ..' runtime is invalid: '..tostring(runtime)
                                        valid_runtime = false
                                    else
                                        profile.runtime = runtime
                                        profile.__runtime_source_digest =
                                            source_digest
                                                and source_digest(runtime_path)
                                                or 'unavailable'
                                    end
                                end
                            else
                                profile.__runtime_source_digest = 'none'
                            end
                            -- A broken optional module quarantines only its own
                            -- profile. Previously loaded profiles remain usable.
                            if valid_runtime and valid_assets then
                                profiles[profile.id] = profile
                            end
                        end
                    end
                end
            end
        end
    end

    -- Policy names are part of PartyCombat authority. A duplicate is never
    -- allowed to depend on directory enumeration order.
    local policy_owners = {}
    for _, id in ipairs(util.sorted_keys(profiles)) do
        local policy_id = profiles[id].policy_id
        if policy_owners[policy_id] then
            errors[#errors + 1] = ('Duplicate policy_id %s in %s and %s; '
                ..'%s quarantined.')
                :format(policy_id, policy_owners[policy_id], id, id)
            profiles[id] = nil
        else
            policy_owners[policy_id] = id
        end
    end

    -- Canonical ids always win. Alias collisions never overwrite an earlier
    -- mapping, so adding a profile cannot silently redirect an old command.
    for _, id in ipairs(util.sorted_keys(profiles)) do aliases[id] = id end
    local alias_claims = {}
    for _, id in ipairs(util.sorted_keys(profiles)) do
        for _, alias in ipairs(profiles[id].aliases or {}) do
            if profiles[alias] and alias ~= id then
                errors[#errors + 1] = ('Alias %s from %s conflicts with '
                    ..'canonical profile %s; alias ignored.')
                    :format(alias, id, alias)
            else
                alias_claims[alias] = alias_claims[alias] or {}
                alias_claims[alias][#alias_claims[alias] + 1] = id
            end
        end
    end
    for _, alias in ipairs(util.sorted_keys(alias_claims)) do
        local owners = alias_claims[alias]
        if #owners == 1 then
            aliases[alias] = owners[1]
        else
            -- Never let directory sort order redirect an established command
            -- to a newly added fight. Ambiguous aliases fail closed.
            errors[#errors + 1] = ('Alias %s is claimed by %s; alias disabled.')
                :format(alias, table.concat(owners, ', '))
        end
    end
    return profiles, aliases, errors
end

return M
