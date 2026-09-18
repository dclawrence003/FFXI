local Loader = {}

local function protected_load(require_fn, declaration, options)
    local loader = options and options.load_data
    local ok, value
    if type(loader) == 'function' and declaration.path then
        ok, value = pcall(loader, declaration)
    else
        ok, value = pcall(require_fn, declaration.module)
    end
    if not ok then return nil, tostring(value) end
    if type(value) ~= 'table' then
        return nil, tostring(declaration.module) .. ' did not return data'
    end
    return value
end

local function merged_declarations(explicit, discovered)
    local result, seen = {}, {}
    local sources = {explicit or {}, discovered or {}}
    table.sort(sources[2], function(left, right)
        local left_name = type(left) == 'table' and left.module or left
        local right_name = type(right) == 'table' and right.module or right
        return tostring(left_name):lower() < tostring(right_name):lower()
    end)
    for _, source in ipairs(sources) do
        if type(source) == 'table' then for _, declaration in ipairs(source) do
            local normalized = type(declaration) == 'string'
                and {module=declaration} or declaration
            if type(normalized) == 'table' and type(normalized.module) == 'string'
                and not seen[normalized.module] then
                seen[normalized.module] = true
                result[#result + 1] = normalized
            end
        end end
    end
    return result
end

local function discover(options, declaration, kind, errors)
    if type(options) ~= 'table' or type(options.discover) ~= 'function' then
        return {}
    end
    local ok, value = pcall(options.discover, declaration, kind)
    if not ok or type(value) ~= 'table' then
        errors[#errors + 1] = ('pack %s %s discovery failed: %s'):format(
            tostring(declaration.id), kind, ok and 'invalid result' or tostring(value))
        return {}
    end
    return value
end

local function route_dependencies(route, landmarks, profiles, objectives, items,
    key_items, pack, reward_scopes)
    local route_contract = {}
    for key, value in pairs(route or {}) do
        if key ~= 'reward_scopes' then route_contract[key] = value end
    end
    local result = {
        route=route_contract, pack={id=pack.id, catalog_id=pack.catalog_id,
            run_seconds=pack.run_seconds,
            stale_run_seconds=pack.stale_run_seconds,
            allowed_zones=pack.allowed_zones,
            instance_zones=pack.instance_zones},
        landmarks={}, profiles={}, objectives={}, items={}, key_items={},
        reward_scopes={},
    }
    local function retain(destination, source, key)
        if key ~= nil and type(source) == 'table' and source[key] ~= nil then
            destination[key] = source[key]
        end
    end
    for _, step in ipairs(route.steps or {}) do
        retain(result.landmarks, landmarks, step.waypoint)
        for _, landmark_id in ipairs(step.path or {}) do
            retain(result.landmarks, landmarks, landmark_id)
        end
        retain(result.profiles, profiles, step.profile)
        retain(result.objectives, objectives, step.objective)
        retain(result.reward_scopes, reward_scopes,
            type(step.reward) == 'table' and step.reward.scope or nil)
        local completion = type(step.completion) == 'table'
            and step.completion or {}
        if completion.kind == 'all_key_item' then
            retain(result.key_items, key_items and key_items.by_key,
                completion.item)
        else
            retain(result.items, items and items.by_key, completion.item)
            for _, item_key in ipairs(completion.items or {}) do
                retain(result.items, items and items.by_key, item_key)
            end
        end
    end
    return result
end

local function catalog_contract(catalog)
    local result = {}
    for index, item in ipairs(catalog and catalog.ordered or {}) do
        result[index] = {key=item.key, id=item.id}
    end
    return result
end

local function copy_set(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function load_profiles(declaration, schema, require_fn, options, errors)
    local profiles = {}
    local declarations = merged_declarations(declaration.profile_modules,
        discover(options, declaration, 'profiles', errors))
    for _, profile_declaration in ipairs(declarations) do
        local profile, profile_error = protected_load(require_fn,
            profile_declaration, options)
        if not profile then
            errors[#errors + 1] = ('profile module %s quarantined: %s')
                :format(tostring(profile_declaration.module), profile_error)
        else
            local valid, validation = schema.validate_profile(profile)
            local expected_key = profile_declaration.identity
            local expected_canonical = expected_key
                and expected_key:gsub('_', '-') or nil
            if valid and expected_key and profile.key ~= expected_key then
                valid = false
                validation[#validation + 1] = ('identity must be %s (derived from path)')
                    :format(expected_key)
            end
            if valid and expected_canonical
                and profile.canonical_id ~= expected_canonical then
                valid = false
                validation[#validation + 1] = ('canonical id must be %s (derived from path)')
                    :format(expected_canonical)
            end
            if not valid then
                errors[#errors + 1] = ('profile descriptor %s quarantined: %s')
                    :format(tostring(profile.key), table.concat(validation, '; '))
            elseif profiles[profile.key] then
                errors[#errors + 1] = ('duplicate profile descriptor %s quarantined')
                    :format(profile.key)
            else
                profiles[profile.key] = profile
            end
        end
    end
    return profiles
end

function Loader.load(registry, schema, require_fn, options)
    require_fn = require_fn or require
    local result = {packs={}, routes={}, aliases={}, errors={},
        route_landmarks={}, route_reward_scopes={},
        route_digests={}, route_packs={}}
    if type(registry) ~= 'table' or registry.schema ~= 1
        or type(registry.packs) ~= 'table' then
        return result, {'invalid content registry'}
    end

    local seen_pack_ids = {}
    for _, declaration in ipairs(registry.packs) do
        local declaration_id = type(declaration) == 'table'
            and declaration.id or nil
        local duplicate = type(declaration_id) == 'string'
            and seen_pack_ids[declaration_id] == true
        if type(declaration) ~= 'table' then
            result.errors[#result.errors + 1] = 'invalid pack declaration quarantined'
        elseif duplicate then
            result.errors[#result.errors + 1] = ('duplicate pack %s quarantined')
                :format(declaration_id)
        else
        if type(declaration_id) == 'string' then
            seen_pack_ids[declaration_id] = true
        end
        local items, items_error = protected_load(require_fn,
            {module=declaration.items}, options)
        local key_items, key_items_error = protected_load(require_fn,
            {module=declaration.key_items}, options)
        local landmarks, landmark_error = protected_load(require_fn,
            {module=declaration.landmarks}, options)
        local objectives, objective_error = {}, nil
        if declaration.objectives then
            objectives, objective_error = protected_load(require_fn,
                {module=declaration.objectives}, options)
        end
        local reward_scopes, reward_scope_error = {}, nil
        if declaration.reward_scopes then
            reward_scopes, reward_scope_error = protected_load(require_fn,
                {module=declaration.reward_scopes}, options)
            if not reward_scopes then reward_scopes = {} end
        end
        local pack_valid, pack_validation = schema.validate_pack(
            declaration, items, key_items)
        local landmark_valid, landmark_validation = false, {}
        if landmarks then
            landmark_valid, landmark_validation = schema.validate_landmarks(landmarks)
        end
        local objective_valid, objective_validation = false, {}
        if objectives then
            objective_valid, objective_validation =
                schema.validate_objectives(objectives, items)
        end
        local fingerprint = options and options.fingerprint
        local catalog_digest = pack_valid and type(fingerprint) == 'function'
            and fingerprint({pack_id=declaration.id,
                revision=declaration.catalog_revision,
                temporary=catalog_contract(items),
                key_items=catalog_contract(key_items)}) or nil
        if not items or not key_items or not landmarks or not landmark_valid
            or not objectives or not objective_valid or not pack_valid
            or type(catalog_digest) ~= 'string' then
            result.errors[#result.errors + 1] = ('pack %s quarantined: %s%s%s%s%s%s%s')
                :format(tostring(declaration.id), items_error or '',
                    key_items_error or '', table.concat(pack_validation, '; '),
                    landmark_error or table.concat(landmark_validation, '; '),
                    objective_error or '', table.concat(objective_validation, '; '),
                    type(catalog_digest) == 'string' and ''
                        or 'catalog fingerprint unavailable')
        else
            local pack = {id=declaration.id, routes={}, route_digests={},
                allowed_zones=copy_set(declaration.allowed_zones),
                instance_zones=copy_set(declaration.instance_zones),
                run_seconds=declaration.run_seconds,
                stale_run_seconds=declaration.stale_run_seconds
                    or declaration.run_seconds * 2,
                catalog_revision=declaration.catalog_revision,
                catalog_id=('%s-r%d-%s'):format(declaration.id,
                    declaration.catalog_revision, catalog_digest)}
            local profiles = load_profiles(declaration, schema, require_fn,
                options, result.errors)
            pack.items, pack.key_items = items, key_items
            pack.landmarks, pack.profiles = landmarks, profiles
            pack.objectives = objectives
            pack.reward_scopes = reward_scopes
            pack.route_landmarks, pack.route_reward_scopes = {}, {}
            if reward_scope_error then
                result.errors[#result.errors + 1] = ('pack %s reward scopes unavailable: %s')
                    :format(declaration.id, reward_scope_error)
            end
            result.packs[declaration.id] = pack
            local route_declarations = merged_declarations(declaration.routes,
                discover(options, declaration, 'routes', result.errors))
            for _, route_declaration in ipairs(route_declarations) do
                local route, route_error = protected_load(require_fn,
                    route_declaration, options)
                if not route then
                    result.errors[#result.errors + 1] = ('route module %s quarantined: %s')
                        :format(tostring(route_declaration.module), route_error)
                else
                    local private_landmarks, local_landmark_errors =
                        schema.compose_landmarks(route, landmarks)
                    local private_reward_scopes, local_reward_scope_errors =
                        schema.compose_reward_scopes(route, reward_scopes)
                    local valid, validation = schema.validate_route(
                        route, private_landmarks, profiles, objectives, items,
                        key_items, pack, private_reward_scopes)
                    for _, message in ipairs(local_landmark_errors) do
                        validation[#validation + 1] = message
                        valid = false
                    end
                    for _, message in ipairs(local_reward_scope_errors) do
                        validation[#validation + 1] = message
                        valid = false
                    end
                    if valid and route_declaration.identity
                        and route.id ~= route_declaration.identity then
                        valid = false
                        validation[#validation + 1] = ('identity must be %s (derived from path)')
                            :format(route_declaration.identity)
                    end
                    if not valid then
                        result.errors[#result.errors + 1] = ('route %s quarantined: %s')
                            :format(tostring(route.id), table.concat(validation, '; '))
                    elseif result.routes[route.id] then
                        result.errors[#result.errors + 1] = ('duplicate route %s quarantined')
                            :format(route.id)
                    else
                        result.routes[route.id] = route
                        pack.routes[route.id] = route
                        pack.route_landmarks[route.id] = private_landmarks
                        pack.route_reward_scopes[route.id] = private_reward_scopes
                        pack.route_digests[route.id] = options
                            and type(options.fingerprint) == 'function'
                            and options.fingerprint(route_dependencies(route,
                                private_landmarks, profiles, objectives, items,
                                key_items, pack, private_reward_scopes))
                            or route.version
                        result.route_landmarks[route.id] = private_landmarks
                        result.route_reward_scopes[route.id] =
                            private_reward_scopes
                        result.route_digests[route.id] = pack.route_digests[route.id]
                        result.route_packs[route.id] = pack.id
                        local aliases, alias_seen = {}, {}
                        if type(route_declaration.aliases) == 'table' then
                            for _, alias in ipairs(route_declaration.aliases) do
                                if not alias_seen[alias] then
                                    alias_seen[alias] = true
                                    aliases[#aliases + 1] = alias
                                end
                            end
                        end
                        for _, alias in ipairs(route.aliases or {}) do
                            if not alias_seen[alias] then
                                alias_seen[alias] = true
                                aliases[#aliases + 1] = alias
                            end
                        end
                        for _, alias in ipairs(aliases) do
                            local reserved_owner = registry.reserved_aliases
                                and registry.reserved_aliases[alias] or nil
                            if reserved_owner and reserved_owner ~= route.id then
                                result.errors[#result.errors + 1] =
                                    ('alias %s is reserved for %s; claim by %s ignored')
                                        :format(tostring(alias), reserved_owner,
                                            route.id)
                            elseif not reserved_owner then
                                result.errors[#result.errors + 1] =
                                    ('unregistered alias %s for %s ignored')
                                        :format(tostring(alias), route.id)
                            elseif not schema.valid_id(alias) or result.aliases[alias]
                                or result.routes[alias] then
                                result.errors[#result.errors + 1] =
                                    ('alias %s for %s quarantined'):format(
                                        tostring(alias), route.id)
                            else
                                result.aliases[alias] = route.id
                            end
                        end
                    end
                end
            end
        end
        end
    end
    return result, result.errors
end

return Loader
