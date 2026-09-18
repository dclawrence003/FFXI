-- Pure validation for ExpeditionGuide content.  Content files are data only;
-- they cannot contain executable commands or reach another addon directly.

local Region = require('lib.region')

local Schema = {}

local function valid_id(value)
    return type(value) == 'string'
        and #value >= 1 and #value <= 80
        and value:match('^[a-z0-9][a-z0-9_-]*$') ~= nil
end

local function append(errors, message)
    errors[#errors + 1] = message
end

local function is_nonempty_string(value)
    return type(value) == 'string' and value ~= ''
end

local function valid_reward_label(value)
    if type(value) ~= 'string' or #value < 1 or #value > 120
        or value:match('[%z\1-\31\127]') ~= nil
        or value:match('^%s') or value:match('%s$') then return false end
    local lower = value:lower()
    return lower:find('reward safe', 1, true) == nil
        and lower:find('freeze chest', 1, true) == nil
        and lower:find('stable 2/2', 1, true) == nil
end

local function is_array(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function finite_number(value)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
end

local function integer(value, low, high)
    return finite_number(value) and value == math.floor(value)
        and (low == nil or value >= low) and (high == nil or value <= high)
end

local function validate_catalog(catalog, label, errors)
    label = label or 'item catalog'
    if type(catalog) ~= 'table' or not is_array(catalog.ordered)
        or type(catalog.by_key) ~= 'table'
        or type(catalog.by_id) ~= 'table' then
        append(errors, label .. ' has an invalid shape')
        return
    end
    if #catalog.ordered > 256 then
        append(errors, label .. ' must contain at most 256 ordered entries')
        return
    end
    local keys, ids = {}, {}
    for index, item in ipairs(catalog.ordered) do
        if type(item) ~= 'table' or not valid_id(item.key)
            or not integer(item.id, 1, 65535)
            or type(item.name) ~= 'string' or item.name == ''
            or item.protocol_index ~= index or keys[item.key] or ids[item.id]
            or catalog.by_key[item.key] ~= item
            or catalog.by_id[item.id] ~= item then
            append(errors, ('%s entry %d is invalid, duplicated, or incoherent')
                :format(label, index))
            return
        end
        keys[item.key], ids[item.id] = true, true
    end
    for key, item in pairs(catalog.by_key) do
        if not keys[key] or type(item) ~= 'table' then
            append(errors, label .. ' has an unexpected by_key entry')
            return
        end
    end
    for id, item in pairs(catalog.by_id) do
        if not ids[id] or type(item) ~= 'table' then
            append(errors, label .. ' has an unexpected by_id entry')
            return
        end
    end
end

function Schema.validate_pack(declaration, item_catalog, key_item_catalog)
    local errors = {}
    if type(declaration) ~= 'table' then
        return false, {'pack declaration must be a table'}
    end
    if not valid_id(declaration.id) then append(errors, 'pack id is invalid') end
    local function validate_zones(field, label)
        local zones, count = declaration[field], 0
        if type(zones) ~= 'table' then
            append(errors, label .. ' must be a set')
            return
        end
        for zone, enabled in pairs(zones) do
            count = count + 1
            if not integer(zone, 1, 1024) or enabled ~= true then
                append(errors, label .. ' contains an invalid entry')
                return
            end
        end
        if count == 0 then append(errors, label .. ' cannot be empty') end
    end
    validate_zones('allowed_zones', 'pack allowed_zones')
    validate_zones('instance_zones', 'pack instance_zones')
    if type(declaration.instance_zones) == 'table'
        and type(declaration.allowed_zones) == 'table' then
        for zone in pairs(declaration.instance_zones) do
            if declaration.allowed_zones[zone] ~= true then
                append(errors, 'instance_zones must be inside allowed_zones')
                break
            end
        end
    end
    if not integer(declaration.run_seconds, 60, 86400) then
        append(errors, 'pack run_seconds is invalid')
    end
    if declaration.stale_run_seconds ~= nil
        and (not integer(declaration.stale_run_seconds,
                declaration.run_seconds or 60, 604800)) then
        append(errors, 'pack stale_run_seconds is invalid')
    end
    if not integer(declaration.catalog_revision, 1, 999999) then
        append(errors, 'pack catalog_revision is invalid')
    end
    validate_catalog(item_catalog, 'temporary-item catalog', errors)
    validate_catalog(key_item_catalog, 'key-item catalog', errors)
    return #errors == 0, errors
end

local function validate_landmark(id, landmark, errors, label)
    label = label or 'landmark'
    if not valid_id(id) or type(landmark) ~= 'table' then
        append(errors, ('%s %s is invalid'):format(label, tostring(id)))
        return
    end
    local fields = {
        name=true, entity_index=true, menu_id=true, x=true, y=true, z=true,
        radius=true, z_tolerance=true, coordinate_semantics=true, confidence=true,
        entity_family=true, target_names=true, map_grid=true, cue=true,
    }
    for key in pairs(landmark) do
        if not fields[key] then
            append(errors, ('%s %s has unsupported field %s'):format(
                label, id, tostring(key)))
        end
    end
    if not is_nonempty_string(landmark.name) then
        append(errors, ('%s %s requires a name'):format(label, id))
    end
    for _, field in ipairs({'x','y','z'}) do
        if landmark[field] ~= nil and not finite_number(landmark[field]) then
            append(errors, ('%s %s has invalid %s'):format(label, id, field))
        end
    end
    if (landmark.x == nil) ~= (landmark.y == nil) then
        append(errors, ('%s %s requires both x and y'):format(label, id))
    end
    if landmark.radius ~= nil and (not finite_number(landmark.radius)
        or landmark.radius <= 0 or landmark.radius > 100) then
        append(errors, ('%s %s has invalid radius'):format(label, id))
    end
    if landmark.z_tolerance ~= nil and (not finite_number(landmark.z_tolerance)
        or landmark.z_tolerance <= 0 or landmark.z_tolerance > 100) then
        append(errors, ('%s %s has invalid z_tolerance'):format(label, id))
    end
    for _, field in ipairs({'entity_index','menu_id'}) do
        local value = landmark[field]
        if value ~= nil and (not finite_number(value)
            or value ~= math.floor(value) or value < 0) then
            append(errors, ('%s %s has invalid %s'):format(label, id, field))
        end
    end
    for _, field in ipairs({'coordinate_semantics','confidence',
        'entity_family','map_grid','cue'}) do
        if landmark[field] ~= nil and type(landmark[field]) ~= 'string' then
            append(errors, ('%s %s has invalid %s'):format(label, id, field))
        end
    end
    if landmark.target_names ~= nil then
        if not is_array(landmark.target_names) then
            append(errors, ('%s %s target_names must be an array'):format(label, id))
        else
            for _, name in ipairs(landmark.target_names) do
                if not is_nonempty_string(name) then
                    append(errors, ('%s %s has an invalid target name')
                        :format(label, id))
                    break
                end
            end
        end
    end
end

function Schema.validate_landmarks(landmarks)
    local errors = {}
    if type(landmarks) ~= 'table' then return false, {'landmarks must be a table'} end
    for id, landmark in pairs(landmarks) do
        validate_landmark(id, landmark, errors, 'landmark')
    end
    return #errors == 0, errors
end

function Schema.compose_landmarks(route, base)
    local result, errors = {}, {}
    for id, landmark in pairs(base or {}) do result[id] = landmark end
    if route.landmarks == nil then return result, errors end
    if type(route.landmarks) ~= 'table' then
        return result, {'route landmarks must be a table'}
    end
    for id, landmark in pairs(route.landmarks) do
        validate_landmark(id, landmark, errors, 'route landmark')
        if result[id] ~= nil then
            append(errors, ('route landmark %s cannot override pack data')
                :format(tostring(id)))
        else
            result[id] = landmark
        end
    end
    return result, errors
end

local function compile_reward_scope(definition)
    return Region.compile_scope(definition)
end

function Schema.compose_reward_scopes(route, base)
    local result, errors, local_compiled = {}, {}, {}
    base = type(base) == 'table' and base or {}
    if type(route) ~= 'table' then
        return result, {'route reward scopes require a route table'}
    end
    if route.reward_scopes ~= nil and type(route.reward_scopes) ~= 'table' then
        return result, {'route reward_scopes must be a table'}
    end
    for id, definition in pairs(type(route.reward_scopes) == 'table'
        and route.reward_scopes or {}) do
        if not valid_id(id) then
            append(errors, 'route reward scope id is invalid: ' .. tostring(id))
        elseif base[id] ~= nil then
            append(errors, ('route reward scope %s cannot override pack data')
                :format(id))
        else
            local compiled, reason = compile_reward_scope(definition)
            if not compiled then
                append(errors, ('route reward scope %s is invalid: %s')
                    :format(id, tostring(reason)))
            else
                local_compiled[id] = compiled
            end
        end
    end
    local referenced = {}
    for _, step in ipairs(type(route.steps) == 'table' and route.steps or {}) do
        local id = type(step) == 'table' and type(step.reward) == 'table'
            and step.reward.scope or nil
        if type(id) == 'string' then referenced[id] = true end
    end
    for id in pairs(referenced) do
        local compiled, reason = local_compiled[id], nil
        if not compiled and base[id] ~= nil then
            compiled, reason = compile_reward_scope(base[id])
        end
        if not compiled then
            append(errors, ('reward scope %s is unavailable or invalid: %s')
                :format(id, tostring(reason or 'unknown scope')))
        else
            result[id] = compiled
        end
    end
    return result, errors
end

local function known_item(item_catalog, key)
    return type(item_catalog) == 'table'
        and type(item_catalog.by_key) == 'table'
        and item_catalog.by_key[key] ~= nil
end

local function validate_completion(step, index, errors, item_catalog,
    key_item_catalog)
    local completion = step.completion
    if type(completion) ~= 'table' then
        append(errors, ('step %d lacks completion data'):format(index))
        return
    end
    local completion_fields = {
        kind=true, auto=true, item=true, items=true,
        menu_id=true, landmark=true,
    }
    for key in pairs(completion) do
        if not completion_fields[key] then
            append(errors, ('step %d completion has unsupported field %s')
                :format(index, tostring(key)))
        end
    end
    local allowed = {
        manual = true,
        sensor_quorum = true,
        all_in_pack = true,
        all_in_sortie = true,
        all_key_item = true,
        all_temp_item = true,
        all_temp_items = true,
        interaction = true,
        target_interaction = true,
        landmark = true,
        relocation = true,
    }
    if not allowed[completion.kind] then
        append(errors, ('step %d has invalid completion kind'):format(index))
    end
    if completion.kind == 'all_temp_item' and not valid_id(completion.item) then
        append(errors, ('step %d has invalid completion item'):format(index))
    elseif completion.kind == 'all_temp_item'
        and not known_item(item_catalog, completion.item) then
        append(errors, ('step %d references unknown completion item %s')
            :format(index, tostring(completion.item)))
    end
    if completion.kind == 'all_temp_items' then
        if not is_array(completion.items) or #completion.items == 0 then
            append(errors, ('step %d completion.items must be a non-empty array')
                :format(index))
        else
            local seen = {}
            for _, item in ipairs(completion.items) do
                if not valid_id(item) or seen[item]
                    or not known_item(item_catalog, item) then
                    append(errors, ('step %d has invalid, duplicate, or unknown completion item %s')
                        :format(index, tostring(item)))
                    break
                end
                seen[item] = true
            end
        end
    end
    if completion.kind == 'all_key_item' then
        if not valid_id(completion.item) then
            append(errors, ('step %d has invalid completion key item'):format(index))
        elseif not known_item(key_item_catalog, completion.item) then
            append(errors, ('step %d references unknown key item %s')
                :format(index, tostring(completion.item)))
        end
    end
    if completion.kind == 'interaction'
        and (type(completion.menu_id) ~= 'number'
            or completion.menu_id ~= math.floor(completion.menu_id)) then
        append(errors, ('step %d has invalid interaction menu id'):format(index))
    end
    if (completion.kind == 'landmark'
            or completion.kind == 'target_interaction')
        and not valid_id(completion.landmark) then
        append(errors, ('step %d has invalid completion landmark'):format(index))
    end
    if completion.auto ~= nil and type(completion.auto) ~= 'boolean' then
        append(errors, ('step %d completion.auto must be boolean'):format(index))
    end
end

function Schema.validate_objectives(objectives, item_catalog)
    local errors = {}
    if type(objectives) ~= 'table' then
        return false, {'objectives must be a table'}
    end
    for id, objective in pairs(objectives) do
        if not valid_id(id) or type(objective) ~= 'table' then
            append(errors, 'objective ' .. tostring(id) .. ' is invalid')
        else
            local fields = {sector=true, reward=true, objective=true}
            for key in pairs(objective) do
                if not fields[key] then
                    append(errors, ('objective %s has unsupported field %s')
                        :format(id, tostring(key)))
                end
            end
            if not is_nonempty_string(objective.sector)
                or not is_nonempty_string(objective.objective)
                or not valid_id(objective.reward)
                or not known_item(item_catalog, objective.reward) then
                append(errors, 'objective ' .. id .. ' has invalid content')
            end
        end
    end
    return #errors == 0, errors
end

local function validate_timer(step, index, errors)
    local timer = step.timer
    if timer == nil then return end
    if type(timer) ~= 'table' then
        append(errors, ('step %d timer must be a table'):format(index))
        return
    end
    local fields = {
        kind=true, key=true, label=true, duration=true,
        entity_indices=true, max_distance=true,
    }
    for key in pairs(timer) do
        if not fields[key] then
            append(errors, ('step %d timer has unsupported field %s')
                :format(index, tostring(key)))
        end
    end
    if timer.kind ~= 'interaction_pair' or not valid_id(timer.key)
        or not is_nonempty_string(timer.label) then
        append(errors, ('step %d timer identity is invalid'):format(index))
    end
    if not finite_number(timer.duration) or timer.duration < 1
        or timer.duration > 3600 then
        append(errors, ('step %d timer duration is invalid'):format(index))
    end
    if not finite_number(timer.max_distance) or timer.max_distance <= 0
        or timer.max_distance > 25 then
        append(errors, ('step %d timer distance is invalid'):format(index))
    end
    if not is_array(timer.entity_indices) or #timer.entity_indices ~= 2 then
        append(errors, ('step %d timer requires two entity indices'):format(index))
    else
        local seen = {}
        for _, entity_index in ipairs(timer.entity_indices) do
            if not finite_number(entity_index)
                or entity_index ~= math.floor(entity_index)
                or entity_index < 1 or seen[entity_index] then
                append(errors, ('step %d timer entity indices are invalid')
                    :format(index))
                break
            end
            seen[entity_index] = true
        end
    end
end

local function same_item_set(left, right)
    if not is_array(left) or not is_array(right) or #left ~= #right then
        return false
    end
    local expected = {}
    for _, value in ipairs(left) do expected[value] = true end
    for _, value in ipairs(right) do
        if not expected[value] then return false end
    end
    return true
end

local function goal_identity(goal)
    if type(goal) ~= 'table' then return nil end
    if goal.kind == 'all_temp_item' then
        return goal.kind .. ':' .. tostring(goal.item)
    elseif goal.kind == 'all_temp_items' and is_array(goal.items) then
        local items = {}
        for index, item in ipairs(goal.items) do items[index] = tostring(item) end
        table.sort(items)
        return goal.kind .. ':' .. table.concat(items, ',')
    end
    return nil
end

local function validate_run_transactions(route, step_index, errors, item_catalog)
    local transactions = route.run_transactions
    if transactions == nil then return end
    if not is_array(transactions) or #transactions == 0
        or #transactions > 32 then
        append(errors, 'run_transactions must be a non-empty array of at most 32 entries')
        return
    end
    local seen, seen_goals = {}, {}
    for index, transaction in ipairs(transactions) do
        local label = ('run transaction %d'):format(index)
        if type(transaction) ~= 'table' then
            append(errors, label .. ' must be a table')
        else
            local fields = {id=true, rewind=true, goal=true}
            for key in pairs(transaction) do
                if not fields[key] then
                    append(errors, label .. ' has unsupported field ' .. tostring(key))
                end
            end
            if not valid_id(transaction.id) or seen[transaction.id] then
                append(errors, label .. ' id is invalid or duplicated')
            else
                seen[transaction.id] = true
            end
            local rewind_index = step_index[transaction.rewind]
            if not valid_id(transaction.rewind) or not rewind_index then
                append(errors, label .. ' references an unknown rewind step')
            end
            local goal = transaction.goal
            if type(goal) ~= 'table' then
                append(errors, label .. ' goal must be a table')
            else
                local goal_fields = {kind=true,item=true,items=true}
                for key in pairs(goal) do
                    if not goal_fields[key] then
                        append(errors, label .. ' goal has unsupported field '
                            .. tostring(key))
                    end
                end
                local valid_goal = false
                if goal.kind == 'all_temp_item' then
                    valid_goal = valid_id(goal.item)
                        and known_item(item_catalog, goal.item)
                elseif goal.kind == 'all_temp_items' then
                    valid_goal = is_array(goal.items) and #goal.items > 0
                    local goal_seen = {}
                    for _, item in ipairs(goal.items or {}) do
                        if not valid_id(item) or goal_seen[item]
                            or not known_item(item_catalog, item) then
                            valid_goal = false
                            break
                        end
                        goal_seen[item] = true
                    end
                end
                if not valid_goal then
                    append(errors, label .. ' has an invalid durable all-six goal')
                else
                    local identity = goal_identity(goal)
                    if seen_goals[identity] then
                        append(errors, label .. ' duplicates a run transaction goal')
                    else
                        seen_goals[identity] = true
                    end
                    local goal_index = nil
                    for step_number, step in ipairs(route.steps or {}) do
                        local completion = type(step) == 'table'
                            and step.completion or nil
                        if type(completion) == 'table'
                            and completion.kind == goal.kind
                            and ((goal.kind == 'all_temp_item'
                                    and completion.item == goal.item)
                                or (goal.kind == 'all_temp_items'
                                    and same_item_set(completion.items,
                                        goal.items))) then
                            goal_index = step_number
                            break
                        end
                    end
                    if not goal_index then
                        append(errors, label .. ' goal is not proven by any route step')
                    elseif rewind_index and rewind_index >= goal_index then
                        append(errors, label .. ' rewind must precede its durable goal step')
                    end
                end
            end
        end
    end
end

function Schema.validate_route(route, landmarks, profiles, objectives, item_catalog,
    key_item_catalog, pack, reward_scopes)
    local errors = {}
    if type(route) ~= 'table' then return false, {'route must be a table'} end
    local route_fields = {
        schema=true, id=true, aliases=true, version=true, title=true,
        content=true, allowed_zones=true, guide_only=true, landmarks=true,
        steps=true, run_transactions=true, reward_scopes=true,
        auto_start=true, target_selected_combat=true,
    }
    for key in pairs(route) do
        if not route_fields[key] then
            append(errors, 'route has unsupported field ' .. tostring(key))
        end
    end
    if route.schema ~= 1 then append(errors, 'route schema must be 1') end
    if not valid_id(route.id) then append(errors, 'route id is invalid') end
    if not is_nonempty_string(route.version)
        or not route.version:match('^%d+%.%d+%.%d+$') then
        append(errors, 'route version must be semantic')
    end
    if not is_nonempty_string(route.title) then
        append(errors, 'route title is required')
    end
    if not is_nonempty_string(route.content) then
        append(errors, 'route content is required')
    elseif type(pack) == 'table' and route.content ~= pack.id then
        append(errors, ('route content must be owning pack %s'):format(pack.id))
    end
    if type(route.allowed_zones) ~= 'table' then
        append(errors, 'allowed_zones must be a set')
    else
        for zone, enabled in pairs(route.allowed_zones) do
            if type(zone) ~= 'number' or zone ~= math.floor(zone)
                or zone < 1 or zone > 1024 or enabled ~= true then
                append(errors, 'allowed_zones contains an invalid entry')
                break
            elseif type(pack) == 'table'
                and (type(pack.allowed_zones) ~= 'table'
                    or pack.allowed_zones[zone] ~= true) then
                append(errors, 'allowed_zones contains a zone outside its pack')
                break
            end
        end
    end
    if route.guide_only ~= true and route.guide_only ~= false then
        append(errors, 'guide_only must be boolean')
    end
    if route.auto_start ~= nil and type(route.auto_start) ~= 'boolean' then
        append(errors, 'auto_start must be boolean')
    end
    if route.target_selected_combat ~= nil
        and type(route.target_selected_combat) ~= 'boolean' then
        append(errors, 'target_selected_combat must be boolean')
    end
    if route.aliases ~= nil then
        if not is_array(route.aliases) then
            append(errors, 'aliases must be an array')
        else
            local aliases = {}
            for _, alias in ipairs(route.aliases) do
                if not valid_id(alias) or aliases[alias] then
                    append(errors, 'route alias is invalid or duplicated')
                end
                aliases[alias] = true
            end
        end
    end
    if not is_array(route.steps) or #route.steps == 0 then
        append(errors, 'route steps must be a non-empty array')
        return false, errors
    end

    local seen, step_index = {}, {}
    for index, step in ipairs(route.steps) do
        if type(step) ~= 'table' then
            append(errors, ('step %d must be a table'):format(index))
        else
            local step_fields = {
                id=true, area=true, instruction=true, warning=true,
                detail=true, completion=true, waypoint=true, path=true,
                profile=true, profile_arm=true, automation=true,
                timer=true, objective=true, reward=true,
            }
            for key in pairs(step) do
                if not step_fields[key] then
                    append(errors, ('step %d has unsupported field %s')
                        :format(index, tostring(key)))
                end
            end
            if not valid_id(step.id) then
                append(errors, ('step %d id is invalid'):format(index))
            elseif seen[step.id] then
                append(errors, ('duplicate step id %s'):format(step.id))
            else
                seen[step.id] = true
                step_index[step.id] = index
            end
            if not is_nonempty_string(step.instruction) then
                append(errors, ('step %d instruction is required'):format(index))
            end
            if not is_nonempty_string(step.area) then
                append(errors, ('step %d area is required'):format(index))
            end
            if step.warning ~= nil and type(step.warning) ~= 'string' then
                append(errors, ('step %d warning must be a string'):format(index))
            end
            if step.detail ~= nil then
                if not is_array(step.detail) then
                    append(errors, ('step %d detail must be an array'):format(index))
                else
                    for _, line in ipairs(step.detail) do
                        if not is_nonempty_string(line) then
                            append(errors, ('step %d detail contains invalid text')
                                :format(index))
                            break
                        end
                    end
                end
            end
        validate_completion(step, index, errors, item_catalog, key_item_catalog)
            validate_timer(step, index, errors)
            if step.objective ~= nil then
                local objective = type(objectives) == 'table'
                    and objectives[step.objective] or nil
                local completion = type(step.completion) == 'table'
                    and step.completion or {}
                if not valid_id(step.objective) or type(objective) ~= 'table' then
                    append(errors, ('step %d references unknown objective %s')
                        :format(index, tostring(step.objective)))
                elseif completion.kind == 'all_temp_item'
                    and objective.reward ~= completion.item then
                    append(errors, ('step %d objective reward does not match completion item')
                        :format(index))
                elseif completion.kind == 'all_temp_items' then
                    local found = false
                    for _, item in ipairs(completion.items or {}) do
                        if item == objective.reward then found = true; break end
                    end
                    if not found then
                        append(errors, ('step %d objective reward is absent from completion items')
                            :format(index))
                    end
                end
            end
            local completion = type(step.completion) == 'table'
                and step.completion or {}
            local reward = step.reward
            local receipt_completion = completion.kind == 'all_temp_item'
                or completion.kind == 'all_temp_items'
            if step.objective ~= nil and receipt_completion
                and reward == nil then
                append(errors, ('step %d objective reward requires reward scope data')
                    :format(index))
            end
            if reward ~= nil then
                if type(reward) ~= 'table' then
                    append(errors, ('step %d reward must be a table'):format(index))
                else
                    local reward_fields = {scope=true,label=true}
                    for key in pairs(reward) do
                        if not reward_fields[key] then
                            append(errors, ('step %d reward has unsupported field %s')
                                :format(index, tostring(key)))
                        end
                    end
                    local scope = valid_id(reward.scope)
                        and type(reward_scopes) == 'table'
                        and reward_scopes[reward.scope] or nil
                    if not scope then
                        append(errors, ('step %d references unknown reward scope %s')
                            :format(index, tostring(reward.scope)))
                    else
                        for zone in pairs(scope.zones or {}) do
                            if type(route.allowed_zones) ~= 'table'
                                or route.allowed_zones[zone] ~= true
                                or type(pack) ~= 'table'
                                or type(pack.instance_zones) ~= 'table'
                                or pack.instance_zones[zone] ~= true then
                                append(errors, ('step %d reward scope contains a zone outside the route instance')
                                    :format(index))
                                break
                            end
                        end
                    end
                    if not valid_reward_label(reward.label) then
                        append(errors, ('step %d reward label is invalid')
                            :format(index))
                    end
                    if not receipt_completion then
                        append(errors, ('step %d reward requires all-temp-item receipt evidence')
                            :format(index))
                    end
                end
            end
            if step.waypoint ~= nil then
                if not valid_id(step.waypoint)
                    or type(landmarks) ~= 'table'
                    or type(landmarks[step.waypoint]) ~= 'table' then
                    append(errors, ('step %d references unknown waypoint %s')
                        :format(index, tostring(step.waypoint)))
                end
            end
            if step.path ~= nil then
                if not is_array(step.path) or #step.path == 0 then
                    append(errors, ('step %d path must be a non-empty array')
                        :format(index))
                else
                    for _, landmark_id in ipairs(step.path) do
                        if not valid_id(landmark_id)
                            or type(landmarks) ~= 'table'
                            or type(landmarks[landmark_id]) ~= 'table' then
                            append(errors, ('step %d path references %s')
                                :format(index, tostring(landmark_id)))
                        end
                    end
                end
            end
            if (completion.kind == 'landmark'
                    or completion.kind == 'target_interaction')
                and (type(landmarks) ~= 'table'
                    or type(landmarks[completion.landmark]) ~= 'table') then
                append(errors, ('step %d completion references unknown landmark %s')
                    :format(index, tostring(completion.landmark)))
            end
            if step.profile ~= nil then
                if not valid_id(step.profile)
                    or type(profiles) ~= 'table'
                    or type(profiles[step.profile]) ~= 'table' then
                    append(errors, ('step %d references unknown profile %s')
                        :format(index, tostring(step.profile)))
                end
            end
            if step.profile_arm ~= nil then
                if type(step.profile_arm) ~= 'boolean' then
                    append(errors, ('step %d profile_arm must be boolean')
                        :format(index))
                elseif step.profile == nil then
                    append(errors, ('step %d cannot arm without a profile')
                        :format(index))
                end
            end
            if step.automation ~= nil then
                local action = step.automation
                local allowed_operations = {
                    device_a=true, device_b=true, device_c=true, port=true,
                }
                if type(action) ~= 'table'
                    or action.kind ~= 'sortie_superwarp'
                    or allowed_operations[action.operation] ~= true
                then
                    append(errors, ('step %d has invalid route automation')
                        :format(index))
                else
                    for key in pairs(action) do
                        if key ~= 'kind' and key ~= 'operation' then
                            append(errors, ('step %d automation has unsupported field %s')
                                :format(index, tostring(key)))
                        end
                    end
                end
            end
        end
    end

    validate_run_transactions(route, step_index, errors, item_catalog)

    return #errors == 0, errors
end

function Schema.validate_profile(profile)
    local errors = {}
    if type(profile) ~= 'table' then return false, {'profile must be a table'} end
    local profile_fields = {
        schema=true, key=true, canonical_id=true, version=true,
        available=true, note=true,
    }
    for key in pairs(profile) do
        if not profile_fields[key] then
            append(errors, 'profile has unsupported field ' .. tostring(key))
        end
    end
    if profile.schema ~= 1 then append(errors, 'profile schema must be 1') end
    if not valid_id(profile.key) then append(errors, 'profile key is invalid') end
    if not valid_id(profile.canonical_id) then
        append(errors, 'canonical PartyTactics id is invalid')
    end
    if profile.available ~= true and profile.available ~= false then
        append(errors, 'profile availability must be boolean')
    end
    if not is_nonempty_string(profile.version)
        or not profile.version:match('^%d+%.%d+%.%d+$') then
        append(errors, 'profile descriptor version must be semantic')
    end
    if profile.note ~= nil and type(profile.note) ~= 'string' then
        append(errors, 'profile note must be a string')
    end
    return #errors == 0, errors
end

function Schema.valid_id(value)
    return valid_id(value)
end

return Schema
