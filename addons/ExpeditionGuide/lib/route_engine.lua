-- Pure, deterministic route state machine.  It never reads Windower state and
-- never dispatches actions.  Runtime evidence must be supplied explicitly.

local Engine = {}
Engine.__index = Engine

local function shallow_copy(source)
    local result = {}
    if type(source) ~= 'table' then return result end
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function copy_array(source)
    local result = {}
    if type(source) ~= 'table' then return result end
    for index, value in ipairs(source) do result[index] = value end
    return result
end

local function safe_index(route, value)
    value = tonumber(value)
    if not value then return 1 end
    value = math.floor(value)
    return math.max(1, math.min(#route.steps, value))
end

local function new_state(route, now, route_digest)
    return {
        schema = 2,
        route_id = route.id,
        route_version = route.version,
        route_digest = route_digest,
        active = false,
        paused = false,
        complete = false,
        current_index = 1,
        waypoint_index = 1,
        started_at = nil,
        active_run_id = nil,
        run_started_at = nil,
        last_seen_at = now,
        last_transition_at = now,
        observed = nil,
        completion_ready_for = nil,
        completion_ready_run_id = nil,
        completed = {},
        history = {},
        timers = {},
    }
end

local function restorable(route, saved, route_digest)
    return type(saved) == 'table'
        and saved.schema == 2
        and saved.route_id == route.id
        and saved.route_version == route.version
        and (route_digest == nil or saved.route_digest == route_digest)
end

function Engine.new(route, saved, now, route_digest)
    assert(type(route) == 'table' and type(route.steps) == 'table',
        'valid route required')
    now = tonumber(now) or os.time()
    local state = restorable(route, saved, route_digest) and shallow_copy(saved)
        or new_state(route, now, route_digest)
    state.current_index = safe_index(route, state.current_index)
    state.waypoint_index = math.max(1,
        math.floor(tonumber(state.waypoint_index) or 1))
    state.schema = 2
    state.route_id = route.id
    state.route_version = route.version
    state.route_digest = route_digest
    state.active = state.active == true
    state.paused = state.active and state.paused == true or false
    state.complete = state.complete == true
        and state.current_index == #route.steps
    state.started_at = tonumber(state.started_at)
    state.active_run_id = type(state.active_run_id) == 'string'
        and state.active_run_id:match('^[a-z0-9][a-z0-9_-]*$')
        and state.active_run_id or nil
    state.run_started_at = tonumber(state.run_started_at)
    state.last_transition_at = tonumber(state.last_transition_at) or now
    state.observed = type(state.observed) == 'table'
        and shallow_copy(state.observed) or nil
    state.completed = shallow_copy(state.completed)
    state.history = copy_array(state.history)
    while #state.history > 512 do table.remove(state.history, 1) end
    state.timers = shallow_copy(state.timers)
    for key, timer in pairs(state.timers) do
        if type(key) ~= 'string' or type(timer) ~= 'table'
            or timer.step_id ~= route.steps[state.current_index].id
            or not state.active_run_id or timer.run_id ~= state.active_run_id
            or not tonumber(timer.deadline_at) then
            state.timers[key] = nil
        else
            state.timers[key] = shallow_copy(timer)
        end
    end
    if state.completion_ready_for ~= route.steps[state.current_index].id then
        state.completion_ready_for = nil
    end
    if state.completion_ready_run_id ~= state.active_run_id then
        state.completion_ready_for = nil
        state.completion_ready_run_id = nil
    end
    if not state.active_run_id then
        state.run_started_at = nil
        state.timers = {}
        state.completion_ready_for = nil
        state.completion_ready_run_id = nil
        if state.observed and state.observed.run_id ~= nil then
            state.observed = nil
        end
    end
    state.last_seen_at = now
    return setmetatable({route = route, state = state}, Engine)
end

function Engine:start(now, run_started_at)
    now = tonumber(now) or os.time()
    self.state.active = true
    self.state.paused = false
    self.state.complete = false
    self.state.started_at = self.state.started_at or now
    if run_started_at and self.state.active_run_id then
        self.state.run_started_at = tonumber(run_started_at)
    end
    self.state.last_seen_at = now
    self.state.last_transition_at = now
    return true
end

function Engine:reset(now)
    self.state = new_state(self.route, tonumber(now) or os.time(),
        self.state.route_digest)
    return true
end

function Engine:current()
    return self.route.steps[self.state.current_index]
end

function Engine:next_step()
    return self.route.steps[self.state.current_index + 1]
end

function Engine:set_run_started_at(value)
    if not self.state.active_run_id then return false, 'no active run binding' end
    value = tonumber(value)
    if not value then return false, 'invalid run start' end
    self.state.run_started_at = math.floor(value)
    return true
end

local function durable_completion(step)
    local kind = step and step.completion and step.completion.kind
    return kind == 'all_key_item' or kind == 'all_temp_item'
        or kind == 'all_temp_items'
end

local function goal_satisfied(goal, evidence)
    local all_items = type(evidence) == 'table' and evidence.all_items or {}
    if type(goal) ~= 'table' then return false end
    if goal.kind == 'all_temp_item' then
        return all_items[goal.item] == true
    elseif goal.kind == 'all_temp_items' then
        for _, item in ipairs(goal.items or {}) do
            if all_items[item] ~= true then return false end
        end
        return #(goal.items or {}) > 0
    end
    return false
end

local function step_indices(route)
    local result = {}
    for index, step in ipairs(route.steps or {}) do result[step.id] = index end
    return result
end

function Engine:bind_run(run_id, evidence, now)
    if type(run_id) ~= 'string' or #run_id > 96
        or run_id:match('^[a-z0-9][a-z0-9_-]*$') == nil then
        return false, 'invalid run binding'
    end
    if type(evidence) ~= 'table' or evidence.run_quorum ~= true
        or evidence.run_id ~= run_id then
        return false, 'run binding lacks exact six-client evidence'
    end
    if self.state.active_run_id == run_id then return false, 'run already bound' end
    now = tonumber(now) or os.time()
    local old_index = self.state.current_index
    self.state.active_run_id = run_id
    self.state.run_started_at = now
    self.state.observed = nil
    self.state.completion_ready_for = nil
    self.state.completion_ready_run_id = nil
    self.state.timers = {}
    self.state.waypoint_index = 1
    self.state.paused = false

    local retained = {}
    for step_id, resolution in pairs(self.state.completed or {}) do
        if type(resolution) == 'table' and resolution.durable == true then
            retained[step_id] = resolution
        end
    end
    self.state.completed = retained

    local indices = step_indices(self.route)
    local rewind_index = nil
    for _, transaction in ipairs(self.route.run_transactions or {}) do
        local candidate = indices[transaction.rewind]
        if candidate and old_index > candidate
            and not goal_satisfied(transaction.goal, evidence)
            and (not rewind_index or candidate < rewind_index) then
            rewind_index = candidate
        end
    end
    if rewind_index then
        self.state.current_index = rewind_index
        self.state.complete = false
    end
    self.state.last_seen_at = now
    self.state.last_transition_at = now
    return true, rewind_index and 'run bound and route rewound' or 'run bound',
        rewind_index
end

function Engine:unbind_run(now, pause)
    local changed = self.state.active_run_id ~= nil
        or self.state.completion_ready_for ~= nil
        or next(self.state.timers or {}) ~= nil
    self.state.active_run_id = nil
    self.state.run_started_at = nil
    self.state.observed = nil
    self.state.completion_ready_for = nil
    self.state.completion_ready_run_id = nil
    self.state.timers = {}
    self.state.waypoint_index = 1
    if pause == true and self.state.active then self.state.paused = true end
    self.state.last_seen_at = tonumber(now) or os.time()
    return changed
end

function Engine:set_paused(value, now)
    if not self.state.active then return false, 'route is not active' end
    self.state.paused = value == true
    self.state.last_seen_at = tonumber(now) or os.time()
    return true
end

function Engine:advance(resolution, confidence, now)
    if not self.state.active then return false, 'route is not active' end
    if self.state.paused then return false, 'route is paused' end
    if self.state.complete then return false, 'route is complete' end
    now = tonumber(now) or os.time()
    local step = self:current()
    local evidence_confirmed = self.state.completion_ready_for == step.id
        and self.state.completion_ready_run_id == self.state.active_run_id
    self.state.completed[step.id] = {
        at = now,
        resolution = tostring(resolution or 'manual'),
        confidence = tostring(confidence or 'manual'),
        durable = durable_completion(step) and evidence_confirmed or false,
        run_id = self.state.active_run_id,
    }
    self.state.history[#self.state.history + 1] = {
        step_id = step.id,
        at = now,
        resolution = tostring(resolution or 'manual'),
        confidence = tostring(confidence or 'manual'),
    }
    while #self.state.history > 512 do table.remove(self.state.history, 1) end
    self.state.observed = nil
    self.state.completion_ready_for = nil
    self.state.completion_ready_run_id = nil
    self.state.waypoint_index = 1
    self.state.timers = {}
    self.state.last_transition_at = now
    self.state.last_seen_at = now
    if self.state.current_index >= #self.route.steps then
        self.state.complete = true
    else
        self.state.current_index = self.state.current_index + 1
    end
    return true
end

function Engine:back(now)
    if not self.state.active then return false, 'route is not active' end
    if self.state.complete then
        self.state.complete = false
    elseif self.state.current_index <= 1 then
        return false, 'already at first step'
    else
        self.state.current_index = self.state.current_index - 1
    end
    local step = self:current()
    self.state.completed[step.id] = nil
    self.state.complete = false
    self.state.paused = false
    self.state.observed = nil
    self.state.completion_ready_for = nil
    self.state.completion_ready_run_id = nil
    self.state.waypoint_index = 1
    self.state.timers = {}
    self.state.last_transition_at = tonumber(now) or os.time()
    self.state.last_seen_at = self.state.last_transition_at
    return true
end

function Engine:skip(now)
    return self:advance('skipped by operator', 'manual', now)
end

function Engine:mark_observed(kind, note, now, satisfies_completion)
    self.state.observed = {
        kind = tostring(kind or 'observation'),
        note = tostring(note or ''),
        at = tonumber(now) or os.time(),
        satisfies_completion = satisfies_completion == true,
        run_id = self.state.active_run_id,
    }
    if satisfies_completion == true then
        self.state.completion_ready_for = self:current() and self:current().id or nil
        self.state.completion_ready_run_id = self.state.active_run_id
    end
    self.state.last_seen_at = self.state.observed.at
    return true
end

function Engine:can_advance()
    local step = self:current()
    local completion = step and step.completion or {kind='manual'}
    return completion.kind == 'manual'
        or (self.state.completion_ready_for == (step and step.id or nil)
            and self.state.completion_ready_run_id == self.state.active_run_id)
end

local function completion_matches(completion, evidence)
    if completion.kind == 'sensor_quorum' then
        return evidence.sensor_quorum == true, 'fresh reports from all clients'
    elseif completion.kind == 'all_in_pack' then
        return evidence.all_in_pack == true,
            'all six clients in the active expedition pack'
    elseif completion.kind == 'all_in_sortie' then
        -- Frozen route compatibility. New packs and routes use all_in_pack.
        return evidence.all_in_pack == true or evidence.all_in_sortie == true,
            'all six clients in Sortie'
    elseif completion.kind == 'all_key_item' then
        local all_key_items = evidence.all_key_items or {}
        return all_key_items[completion.item] == true,
            'all six reported ' .. tostring(completion.item)
    elseif completion.kind == 'all_temp_item' then
        local all_items = evidence.all_items or {}
        return all_items[completion.item] == true,
            'all six reported ' .. tostring(completion.item)
    elseif completion.kind == 'all_temp_items' then
        local all_items = evidence.all_items or {}
        local missing = {}
        for _, item in ipairs(completion.items or {}) do
            if all_items[item] ~= true then missing[#missing + 1] = item end
        end
        return #missing == 0, #missing == 0
            and ('all six reported ' .. table.concat(completion.items, ', '))
            or ('waiting for all-six ' .. table.concat(missing, ', '))
    elseif completion.kind == 'interaction' then
        return tonumber(evidence.menu_id) == tonumber(completion.menu_id),
            'observed menu ' .. tostring(completion.menu_id)
    elseif completion.kind == 'target_interaction' then
        return evidence.interaction_landmark == completion.landmark,
            'operator interacted with ' .. tostring(completion.landmark)
    elseif completion.kind == 'landmark' then
        return evidence.landmark == completion.landmark,
            'arrived at ' .. tostring(completion.landmark)
    elseif completion.kind == 'relocation' then
        return evidence.relocation == true,
            'observed the requested large relocation'
    end
    return false, nil
end

-- Catch a route up when durable all-six evidence proves the party has already
-- reached the next irreversible milestone. Only non-durable steps may be
-- inferred: an unsatisfied key/temp-item step is a hard reconciliation wall.
function Engine:reconcile_forward(evidence, now)
    if not self.state.active or self.state.paused or self.state.complete then
        return false, 0
    end
    evidence = evidence or {}
    now = tonumber(now) or os.time()
    local advanced = 0
    while not self.state.complete do
        local current = self:current()
        local completion = current and current.completion or {kind='manual'}
        local matched = completion_matches(completion, evidence)
        if matched and completion.auto == true then
            self:mark_observed(completion.kind,
                'current durable evidence reconciled', now, true)
            if not self:advance('current durable evidence reconciled',
                'confirmed', now) then break end
            advanced = advanced + 1
        else
            if durable_completion(current) then break end
            local target_index, target_completion
            for index = self.state.current_index + 1, #self.route.steps do
                local candidate = self.route.steps[index]
                if durable_completion(candidate) then
                    target_index = index
                    target_completion = candidate.completion
                    break
                end
            end
            if not target_index then break end
            local future_matches = completion_matches(target_completion, evidence)
            if not future_matches then break end
            while self.state.current_index < target_index do
                if not self:advance('inferred from later all-six evidence',
                    'reconciled', now) then break end
                advanced = advanced + 1
            end
            if self.state.current_index ~= target_index then break end
            self:mark_observed(target_completion.kind,
                'later durable evidence reconciled', now, true)
            if not self:advance('later durable evidence reconciled',
                'confirmed', now) then break end
            advanced = advanced + 1
        end
    end
    return advanced > 0, advanced
end

function Engine:observe(evidence, now)
    if not self.state.active or self.state.paused or self.state.complete then
        return false, 'inactive'
    end
    evidence = evidence or {}
    local step = self:current()
    local completion = step.completion or {kind = 'manual'}
    local matched, note = completion_matches(completion, evidence)
    if not matched then return false, 'no match' end
    self:mark_observed(completion.kind, note, now, true)
    if completion.auto == true then
        local advanced, reason = self:advance(note, 'confirmed', now)
        return advanced, reason, advanced
    end
    return true, 'observed', false
end

function Engine:set_waypoint_index(value)
    value = tonumber(value)
    if not value then return false end
    self.state.waypoint_index = math.max(1, math.floor(value))
    return true
end

function Engine:start_timer(key, duration, now)
    if type(key) ~= 'string' or key == '' then return false, 'invalid timer key' end
    if not self.state.active_run_id then return false, 'no active run binding' end
    duration = tonumber(duration)
    now = tonumber(now) or os.time()
    if not duration or duration <= 0 then return false, 'invalid timer duration' end
    self.state.timers[key] = {
        started_at=now,
        deadline_at=now + duration,
        duration=duration,
        step_id=self:current() and self:current().id or nil,
        run_id=self.state.active_run_id,
    }
    self.state.last_seen_at = now
    return true
end

function Engine:timer(key)
    return self.state.timers and self.state.timers[key] or nil
end

function Engine:timer_remaining(key, now)
    local timer = self:timer(key)
    if not timer then return nil end
    now = tonumber(now) or os.time()
    return math.max(0, (tonumber(timer.deadline_at) or now) - now)
end

function Engine:clear_timer(key)
    if not self.state.timers or self.state.timers[key] == nil then return false end
    self.state.timers[key] = nil
    return true
end

function Engine:snapshot(now)
    self.state.last_seen_at = tonumber(now) or self.state.last_seen_at
    return shallow_copy(self.state)
end

return Engine
