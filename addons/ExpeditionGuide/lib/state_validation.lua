-- Bounded, fail-closed validation for persisted leader state.  Saved Lua is
-- treated as untrusted input: only the small state shape emitted by this addon
-- is admitted, and navigation calibration is rebuilt from current route data.

local Validation = {}

local MAX_NODES = 8192
local MAX_DEPTH = 16
local MAX_STRING = 4096
local MAX_HISTORY = 512
local MAX_OVERRIDES = 1024
local MAX_TIME = 4102444800

local function finite(value, low, high)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
        and (low == nil or value >= low)
        and (high == nil or value <= high)
end

local function integer(value, low, high)
    return finite(value, low, high) and value == math.floor(value)
end

local function bounded_plain(value)
    local seen, nodes = {}, 0
    local function visit(item, depth)
        nodes = nodes + 1
        if nodes > MAX_NODES then return false, 'state node limit exceeded' end
        if depth > MAX_DEPTH then return false, 'state nesting limit exceeded' end
        local kind = type(item)
        if kind == 'nil' or kind == 'boolean' then return true end
        if kind == 'string' then
            return #item <= MAX_STRING, 'state string limit exceeded'
        end
        if kind == 'number' then
            return finite(item), 'state contains a non-finite number'
        end
        if kind ~= 'table' then return false, 'state contains ' .. kind end
        if getmetatable(item) ~= nil then return false, 'state contains a metatable' end
        if seen[item] then return false, 'state contains a cycle' end
        seen[item] = true
        for key, child in pairs(item) do
            local key_ok, key_error = visit(key, depth + 1)
            if not key_ok then return false, key_error end
            local child_ok, child_error = visit(child, depth + 1)
            if not child_ok then return false, child_error end
        end
        seen[item] = nil
        return true
    end
    return visit(value, 0)
end

local function short_string(value, limit)
    return type(value) == 'string' and #value <= (limit or 256)
end

local function time_or_nil(value)
    if value == nil then return nil, true end
    if not integer(value, 0, MAX_TIME) then return nil, false end
    return value, true
end

local function step_ids(route)
    local result = {}
    for _, step in ipairs(route.steps or {}) do result[step.id] = true end
    return result
end

local function durable_steps(route)
    local result = {}
    for _, step in ipairs(route.steps or {}) do
        local kind = step.completion and step.completion.kind
        if kind == 'all_key_item' or kind == 'all_temp_item'
            or kind == 'all_temp_items' then
            result[step.id] = true
        end
    end
    return result
end

local function sanitize_resolution(value)
    if type(value) ~= 'table' then return nil end
    local at, at_ok = time_or_nil(value.at)
    if not at_ok or at == nil or not short_string(value.resolution)
        or not short_string(value.confidence, 80) then return nil end
    return {
        at=at,
        resolution=value.resolution,
        confidence=value.confidence,
        durable=value.durable == true,
    }
end

local function sanitize_route_state(value, route, digest)
    if value == nil then return nil end
    if type(value) ~= 'table' then return nil, 'route_state must be a table' end
    local legacy = value.schema == 1
    if (value.schema ~= 1 and value.schema ~= 2) or value.route_id ~= route.id
        or value.route_version ~= route.version or value.route_digest ~= digest then
        -- Identity changes deliberately invalidate progress without invalidating
        -- the selected route or otherwise trusting an old layout.
        return nil, nil, true
    end
    local index = value.current_index
    if not integer(index, 1, #route.steps) then
        return nil, 'route_state has an invalid current step'
    end
    local step = route.steps[index]
    local waypoint_limit = type(step.path) == 'table' and #step.path or 1
    local waypoint_index = value.waypoint_index
    if not integer(waypoint_index, 1, math.max(1, waypoint_limit)) then
        return nil, 'route_state has an invalid waypoint step'
    end
    local started_at, started_ok = time_or_nil(value.started_at)
    local run_started_at, run_started_ok = time_or_nil(value.run_started_at)
    local last_seen_at, seen_ok = time_or_nil(value.last_seen_at)
    local last_transition_at, transition_ok = time_or_nil(value.last_transition_at)
    if not started_ok or not run_started_ok or not seen_ok or not transition_ok
        or (value.active == true and (started_at == nil or last_seen_at == nil)) then
        return nil, 'route_state has invalid timestamps'
    end

    local result = {
        schema=2,
        route_id=route.id,
        route_version=route.version,
        route_digest=digest,
        active=value.active == true,
        -- A disk restore never proves continuity of an ephemeral entry nonce.
        paused=value.active == true,
        complete=value.complete == true and index == #route.steps,
        current_index=index,
        waypoint_index=waypoint_index,
        started_at=started_at,
        active_run_id=nil,
        run_started_at=nil,
        last_seen_at=last_seen_at,
        last_transition_at=last_transition_at,
        completion_ready_for=nil,
        completed={}, history={}, timers={},
    }

    local known_steps = step_ids(route)
    local known_durable = durable_steps(route)
    if type(value.completed) == 'table' then
        for step_id, resolution in pairs(value.completed) do
            if known_steps[step_id] and known_durable[step_id] then
                local clean = sanitize_resolution(resolution)
                local proved = clean and ((not legacy and clean.durable)
                    or (legacy and clean.confidence == 'confirmed'))
                if proved then
                    clean.durable = true
                    result.completed[step_id] = clean
                end
            end
        end
    end
    if type(value.history) == 'table' then
        for history_index = 1, math.min(#value.history, MAX_HISTORY) do
            local entry = value.history[history_index]
            local resolution = sanitize_resolution(entry)
            if resolution and type(entry) == 'table'
                and known_steps[entry.step_id] then
                resolution.step_id = entry.step_id
                result.history[#result.history + 1] = resolution
            end
        end
    end
    return result, nil, false, true
end

local function sanitize_overrides(value, routes, landmarks_by_route)
    local result, discarded, accepted = {}, 0, 0
    if value == nil then return result, discarded end
    if type(value) ~= 'table' then return result, 1 end
    for route_id, overrides in pairs(value) do
        local route_landmarks = type(route_id) == 'string'
            and routes[route_id] and landmarks_by_route[route_id] or nil
        if type(overrides) ~= 'table' or type(route_landmarks) ~= 'table' then
            discarded = discarded + 1
        else
            local clean_route = {}
            for landmark_id, override in pairs(overrides) do
                local landmark = type(landmark_id) == 'string'
                    and route_landmarks[landmark_id] or nil
                if accepted >= MAX_OVERRIDES or type(landmark) ~= 'table'
                    or type(override) ~= 'table'
                    or not finite(override.x, -10000, 10000)
                    or not finite(override.y, -10000, 10000)
                    or (override.z ~= nil and not finite(override.z, -10000, 10000)) then
                    discarded = discarded + 1
                else
                    accepted = accepted + 1
                    clean_route[landmark_id] = {
                        name=landmark.name,
                        x=override.x, y=override.y, z=override.z,
                        radius=landmark.radius or 5,
                        z_tolerance=landmark.z_tolerance or 12,
                        confidence=short_string(override.confidence, 80)
                            and override.confidence or 'saved_calibration',
                        captured_at=integer(override.captured_at, 0, MAX_TIME)
                            and override.captured_at or nil,
                    }
                end
            end
            result[route_id] = clean_route
        end
    end
    return result, discarded
end

function Validation.sanitize(value, options)
    options = options or {}
    local plain, plain_error = bounded_plain(value)
    if not plain then return nil, plain_error end
    if type(value) ~= 'table' or (value.schema ~= 2 and value.schema ~= 3)
        or value.character ~= options.character then
        return nil, 'state wrapper identity is incompatible'
    end
    local routes = options.routes or {}
    local route = type(value.active_route_id) == 'string'
        and routes[value.active_route_id] or nil
    if not route then return nil, 'saved route is unavailable' end
    local digest = options.route_digests
        and options.route_digests[route.id] or route.version
    local route_state, route_error, identity_reset, foray_reset = sanitize_route_state(
        value.route_state, route, digest)
    if route_error then return nil, route_error end
    local overrides, discarded = sanitize_overrides(value.navigation_overrides,
        routes, options.route_landmarks or {})
    local saved_at = integer(value.saved_at, 0, MAX_TIME) and value.saved_at or nil
    return {
        schema=3,
        addon_version=short_string(value.addon_version, 40)
            and value.addon_version or nil,
        character=options.character,
        active_route_id=route.id,
        route_state=route_state,
        navigation_overrides=overrides,
        recovery_required=route_state ~= nil and route_state.active == true,
        saved_at=saved_at,
    }, nil, {discarded_overrides=discarded,
        route_identity_reset=identity_reset == true,
        foray_reset=foray_reset == true,
        wrapper_migrated=value.schema == 2}
end

return Validation
