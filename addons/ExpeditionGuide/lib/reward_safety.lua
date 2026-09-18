-- Memory-only, fail-closed safety proof for a local reward interaction.
-- This module never persists an authorization and never emits an action.  A
-- successful result describes only the most recent observe() call.

local Region = require('lib.region')

local RewardSafety = {}
RewardSafety.__index = RewardSafety

local EXPECTED_CLIENTS = 6
local MAX_RECEIPT_AGE = 2
local MAX_WALL_AGE = 2
local MIN_CYCLE_INTERVAL = 0.5

local CONTEXT_FIELDS = {
    pack_id=true, catalog_id=true, route_id=true, route_digest=true,
    step_id=true, scope_id=true, scope=true, roster=true,
    expected_leader=true, zone=true, run_id=true, run_cohort=true,
    session_run_id=true, session_cohort=true, engine_run_id=true,
    now_wall=true, entry_nonces=true,
}

local function finite(value)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
end

local function valid_id(value, limit)
    return type(value) == 'string' and #value >= 1
        and #value <= (limit or 120)
        and value:match('^[a-z0-9][a-z0-9_-]*$') ~= nil
end

local function valid_name(value)
    return type(value) == 'string' and #value >= 1 and #value <= 20
        and value:match('^[A-Za-z]+$') ~= nil
end

local function array(value)
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

local function copy_array(source)
    local result = {}
    for index, value in ipairs(source or {}) do result[index] = value end
    return result
end


local function copy_failures(source)
    local result = {}
    for index, failure in ipairs(source or {}) do
        result[index] = {
            reason=tostring(failure.reason or ''),
            names=copy_array(failure.names),
        }
    end
    return result
end

local function copy_status(status)
    return {
        safe=status.safe == true,
        reason=tostring(status.reason or ''),
        progress=tonumber(status.progress) or 0,
        expected=2,
        missing=copy_array(status.missing),
        failures=copy_failures(status.failures),
    }
end

local function empty_status(reason)
    return {safe=false, reason=reason or 'reset', progress=0,
        expected=2, missing={}, failures={}}
end

local function parse_cohort(value, roster)
    if type(value) ~= 'string' or value == '' or #value > 1024 then
        return nil, 'invalid run cohort'
    end
    local parts = {}
    for part in (value .. '|'):gmatch('(.-)|') do
        parts[#parts + 1] = part
    end
    if #parts ~= EXPECTED_CLIENTS then return nil, 'invalid run cohort' end
    local result, used_nonces = {}, {}
    for index, name in ipairs(roster) do
        local expected_name = name:lower()
        local cohort_name, nonce = parts[index]:match('^([^=]+)=([^=]+)$')
        if cohort_name ~= expected_name or not valid_id(nonce, 96)
            or used_nonces[nonce] then
            return nil, 'run cohort does not match the exact roster'
        end
        result[name] = nonce
        used_nonces[nonce] = true
    end
    return result
end

local function exact_nonce_map(value, roster, parsed)
    if type(value) ~= 'table' then return false end
    local expected = {}
    for _, name in ipairs(roster) do expected[name] = true end
    local count = 0
    for name, nonce in pairs(value) do
        if not expected[name] or nonce ~= parsed[name] then return false end
        count = count + 1
    end
    if count ~= EXPECTED_CLIENTS then return false end
    for _, name in ipairs(roster) do
        if value[name] ~= parsed[name] then return false end
    end
    return true
end

local function sorted_zones(zones)
    local result = {}
    for zone in pairs(zones) do result[#result + 1] = zone end
    table.sort(result)
    return result
end

local function region_identity(region)
    local parts = {region.kind, 'zones'}
    for _, zone in ipairs(sorted_zones(region.zones)) do
        parts[#parts + 1] = tostring(zone)
    end
    if region.kind == 'z_band' then
        parts[#parts + 1], parts[#parts + 2] =
            tostring(region.min), tostring(region.max)
    elseif region.kind == 'aabb' then
        for _, key in ipairs({'min_x','max_x','min_y','max_y','min_z','max_z'}) do
            parts[#parts + 1] = tostring(region[key])
        end
    elseif region.kind == 'cylinder' then
        for _, key in ipairs({'x','y','radius','min_z','max_z'}) do
            parts[#parts + 1] = tostring(region[key])
        end
    else
        parts[#parts + 1], parts[#parts + 2] =
            tostring(region.min_z), tostring(region.max_z)
        for _, point in ipairs(region.points) do
            parts[#parts + 1] = tostring(point.x) .. ',' .. tostring(point.y)
        end
    end
    return table.concat(parts, '|')
end

local function scope_identity(scope)
    local compiled, reason = Region.compile_scope(scope)
    if not compiled then return nil, nil, reason end
    local parts = {'label', compiled.label}
    for _, region in ipairs(compiled.regions) do
        parts[#parts + 1] = region_identity(region)
    end
    return table.concat(parts, '\30'), compiled
end

local function validate_context(context)
    if type(context) ~= 'table' then return nil, 'invalid context' end
    for key in pairs(context) do
        if not CONTEXT_FIELDS[key] then
            return nil, 'unsupported context field ' .. tostring(key)
        end
    end
    for _, key in ipairs({'pack_id','catalog_id','route_id','route_digest',
        'step_id','scope_id','run_id','session_run_id','engine_run_id'}) do
        if not valid_id(context[key], key == 'catalog_id' and 120 or 96) then
            return nil, 'invalid context ' .. key
        end
    end
    if not array(context.roster) or #context.roster ~= EXPECTED_CLIENTS then
        return nil, 'context requires an exact six-client roster'
    end
    local names = {}
    for _, name in ipairs(context.roster) do
        local normalized = type(name) == 'string' and name:lower() or nil
        if not valid_name(name) or names[normalized] then
            return nil, 'context roster is invalid or duplicated'
        end
        names[normalized] = true
    end
    if not valid_name(context.expected_leader)
        or context.expected_leader ~= context.roster[1] then
        return nil, 'context expected leader must be the first roster member'
    end
    if type(context.zone) ~= 'number' or context.zone ~= math.floor(context.zone)
        or context.zone < 1 or context.zone > 1024 then
        return nil, 'invalid context zone'
    end
    if not finite(context.now_wall) or context.now_wall < 1
        or context.now_wall > 4102444800 then
        return nil, 'invalid context wall clock'
    end
    if context.run_id ~= context.session_run_id
        or context.run_id ~= context.engine_run_id then
        return nil, 'run identity invariant failed'
    end
    if type(context.run_cohort) ~= 'string' or context.run_cohort == ''
        or context.run_cohort ~= context.session_cohort then
        return nil, 'run cohort invariant failed'
    end
    local nonces, reason = parse_cohort(context.run_cohort, context.roster)
    if not nonces then return nil, reason end
    if not exact_nonce_map(context.entry_nonces, context.roster, nonces) then
        return nil, 'entry nonce map does not match run cohort'
    end
    local scope_key, compiled_scope
    scope_key, compiled_scope, reason = scope_identity(context.scope)
    if not scope_key then return nil, reason end
    if compiled_scope.zones[context.zone] ~= true then
        return nil, 'context zone is outside reward scope'
    end
    local identity_parts = {
        context.pack_id, context.catalog_id, context.route_id,
        context.route_digest, context.step_id, context.scope_id,
        tostring(context.zone), context.run_id, context.run_cohort,
        context.expected_leader, scope_key,
    }
    for _, name in ipairs(context.roster) do
        identity_parts[#identity_parts + 1] = name
    end
    return {
        key=table.concat(identity_parts, '\31'),
        nonces=nonces,
        scope=compiled_scope,
        roster=context.roster,
    }
end

local function validate_reports(context, normalized, reports, now)
    if type(reports) ~= 'table' then
        local names = copy_array(normalized.roster)
        return nil, names, 'reports_invalid_shape',
            {{reason='reports_invalid_shape',names=names}}
    end
    local expected, missing, unexpected = {}, {}, false
    for _, name in ipairs(normalized.roster) do expected[name] = true end
    for name in pairs(reports) do
        if not expected[name] then unexpected = true end
    end
    for _, name in ipairs(normalized.roster) do
        if reports[name] == nil then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return nil, missing, 'reports_missing',
            {{reason='reports_missing',names=copy_array(missing)}}
    end
    if unexpected then
        return nil, {}, 'reports_unexpected_client',
            {{reason='reports_unexpected_client',names={}}}
    end

    local priority = {
        'report_sender_mismatch',
        'report_context_mismatch',
        'report_not_ready',
        'report_leader_mismatch',
        'report_nonce_mismatch',
        'report_wall_clock_invalid',
        'report_wall_clock_stale',
        'report_receipt_invalid',
        'report_receipt_stale',
        'report_sequence_invalid',
        'report_out_of_scope',
    }
    local failures, sequences, receipts, positions = {}, {}, {}, {}
    for _, reason in ipairs(priority) do failures[reason] = {} end
    for _, name in ipairs(normalized.roster) do
        local report = reports[name]
        local failure = nil
        if type(report) ~= 'table' or report.sender ~= name then
            failure = 'report_sender_mismatch'
        elseif report.pack_id ~= context.pack_id
            or report.catalog_id ~= context.catalog_id
            or report.zone ~= context.zone then
            failure = 'report_context_mismatch'
        elseif report.ready ~= true or report.party_exact ~= true then
            failure = 'report_not_ready'
        elseif report.leader_exact ~= (name == context.expected_leader) then
            failure = 'report_leader_mismatch'
        elseif type(report.entry_nonce) ~= 'string' or report.entry_nonce == ''
            or report.entry_nonce ~= normalized.nonces[name] then
            failure = 'report_nonce_mismatch'
        elseif not finite(report.timestamp) then
            failure = 'report_wall_clock_invalid'
        elseif math.abs(context.now_wall - report.timestamp) > MAX_WALL_AGE then
            failure = 'report_wall_clock_stale'
        elseif not finite(report.received_at) then
            failure = 'report_receipt_invalid'
        elseif now - report.received_at < 0
            or now - report.received_at > MAX_RECEIPT_AGE then
            failure = 'report_receipt_stale'
        elseif type(report.sequence) ~= 'number'
            or report.sequence ~= math.floor(report.sequence)
            or report.sequence < 0 or report.sequence > 2147483647 then
            failure = 'report_sequence_invalid'
        elseif Region.contains_scope(normalized.scope, {
                zone=report.zone, x=report.x, y=report.y, z=report.z,
            }) ~= true then
            failure = 'report_out_of_scope'
        end
        if failure then
            failures[failure][#failures[failure] + 1] = name
        else
            sequences[name] = report.sequence
            receipts[name] = report.received_at
            positions[name] = {x=report.x,y=report.y,z=report.z}
        end
    end
    local primary, details, failed_names, failed_set = nil, {}, {}, {}
    for _, reason in ipairs(priority) do
        if #failures[reason] > 0 then
            primary = primary or reason
            details[#details + 1] = {
                reason=reason,names=copy_array(failures[reason]),
            }
            for _, name in ipairs(failures[reason]) do failed_set[name] = true end
        end
    end
    if primary then
        for _, name in ipairs(normalized.roster) do
            if failed_set[name] then failed_names[#failed_names + 1] = name end
        end
        return nil, failed_names, primary, details
    end
    return {sequences=sequences, receipts=receipts, positions=positions}
end

local function latest_receipt(receipts, roster)
    local latest = -math.huge
    for _, name in ipairs(roster) do
        if receipts[name] > latest then latest = receipts[name] end
    end
    return latest
end

function RewardSafety.new()
    return setmetatable({
        context_key=nil,
        first_sequences=nil,
        first_receipts=nil,
        latest_sequences=nil,
        latest_receipts=nil,
        latest_positions=nil,
        first_cycle_at=nil,
        last_status=empty_status('not_observed'),
    }, RewardSafety)
end

function RewardSafety:reset(reason)
    self.context_key = nil
    self.first_sequences = nil
    self.first_receipts = nil
    self.latest_sequences = nil
    self.latest_receipts = nil
    self.latest_positions = nil
    self.first_cycle_at = nil
    self.last_status = empty_status(reason or 'reset')
    return self:status()
end

function RewardSafety:status()
    return copy_status(self.last_status or empty_status('not_observed'))
end

function RewardSafety:is_open()
    return self.last_status ~= nil and self.last_status.safe == true
end

local function begin_cycle(self, normalized, evidence, reason)
    self.context_key = normalized.key
    self.first_sequences = {}
    self.first_receipts = {}
    self.latest_sequences = {}
    self.latest_receipts = {}
    self.latest_positions = {}
    for name, sequence in pairs(evidence.sequences) do
        self.first_sequences[name] = sequence
        self.first_receipts[name] = evidence.receipts[name]
        self.latest_sequences[name] = sequence
        self.latest_receipts[name] = evidence.receipts[name]
        self.latest_positions[name] = {
            x=evidence.positions[name].x,
            y=evidence.positions[name].y,
            z=evidence.positions[name].z,
        }
    end
    self.first_cycle_at = latest_receipt(evidence.receipts,
        normalized.roster)
    self.last_status = {safe=false, reason=reason or 'first_cycle',
        progress=1, expected=2, missing={}}
    return self:status()
end

function RewardSafety:observe(context, reports, now_monotonic)
    -- A prior success is re-proven against the complete current observation
    -- below.  It is never trusted across a failed observation or reset.
    if not finite(now_monotonic) or now_monotonic < 0 then
        self:reset('invalid monotonic clock')
        return self:status()
    end
    local normalized, reason = validate_context(context)
    if not normalized then
        self:reset(reason)
        return self:status()
    end
    local context_changed = self.context_key ~= nil
        and self.context_key ~= normalized.key
    if context_changed then self:reset('context_changed') end

    local evidence, missing, failure_details
    evidence, missing, reason, failure_details = validate_reports(context, normalized,
        reports, now_monotonic)
    if not evidence then
        self:reset(reason)
        self.last_status.missing = copy_array(missing)
        self.last_status.failures = copy_failures(failure_details)
        return self:status()
    end
    if not self.first_sequences or self.context_key ~= normalized.key then
        return begin_cycle(self, normalized, evidence,
            context_changed and 'context_changed' or 'first_cycle')
    end

    local receipt_inconsistent = {}
    for _, name in ipairs(normalized.roster) do
        local latest_sequence = self.latest_sequences[name]
        local sequence = evidence.sequences[name]
        local receipt = evidence.receipts[name]
        if sequence < latest_sequence
            or (sequence == latest_sequence
                and receipt ~= self.latest_receipts[name])
            or (sequence > latest_sequence
                and receipt <= self.latest_receipts[name]) then
            receipt_inconsistent[#receipt_inconsistent + 1] = name
        end
    end
    if #receipt_inconsistent > 0 then
        self:reset('report receipt/sequence continuity failed')
        self.last_status.missing = receipt_inconsistent
        return self:status()
    end
    local relocated = {}
    for _, name in ipairs(normalized.roster) do
        local previous = self.latest_positions[name]
        local current = evidence.positions[name]
        if previous and current then
            local dx, dy = current.x - previous.x, current.y - previous.y
            if math.sqrt(dx * dx + dy * dy) >= 45
                or math.abs(current.z - previous.z) >= 45 then
                relocated[#relocated + 1] = name
            end
        end
    end
    if #relocated > 0 then
        self:reset('report_large_relocation')
        local status = begin_cycle(self, normalized, evidence,
            'report_large_relocation')
        self.last_status.missing = copy_array(relocated)
        return self:status()
    end
    for _, name in ipairs(normalized.roster) do
        if evidence.sequences[name] > self.latest_sequences[name] then
            self.latest_sequences[name] = evidence.sequences[name]
            self.latest_receipts[name] = evidence.receipts[name]
            self.latest_positions[name] = {
                x=evidence.positions[name].x,
                y=evidence.positions[name].y,
                z=evidence.positions[name].z,
            }
        end
    end

    local waiting, regressed = {}, {}
    for _, name in ipairs(normalized.roster) do
        local previous = self.first_sequences[name]
        local current = evidence.sequences[name]
        if current < previous then
            regressed[#regressed + 1] = name
        elseif current == previous then
            waiting[#waiting + 1] = name
        elseif evidence.receipts[name] <= self.first_receipts[name] then
            regressed[#regressed + 1] = name
        end
    end
    if #regressed > 0 then
        self:reset('report sequence regressed')
        self.last_status.missing = regressed
        return self:status()
    end
    if self.last_status.safe == true then
        -- Keep a proven gate open only while this exact context and all six
        -- current reports continue to pass every invariant.  When a complete
        -- newer cycle arrives, roll the comparison baseline forward so fresh
        -- cycles continuously renew (but never persist) the proof.
        if #waiting == 0 then
            local cycle_at = latest_receipt(evidence.receipts,
                normalized.roster)
            if cycle_at - self.first_cycle_at >= MIN_CYCLE_INTERVAL then
                for name, sequence in pairs(evidence.sequences) do
                    self.first_sequences[name] = sequence
                    self.first_receipts[name] = evidence.receipts[name]
                end
                self.first_cycle_at = cycle_at
            end
        end
        self.last_status = {safe=true, reason='safe', progress=2,
            expected=2, missing={}}
        return self:status()
    end
    if #waiting > 0 then
        self.last_status = {safe=false, reason='awaiting_distinct_cycle',
            progress=1, expected=2, missing=waiting}
        return self:status()
    end
    local second_at = latest_receipt(evidence.receipts, normalized.roster)
    if second_at - self.first_cycle_at < MIN_CYCLE_INTERVAL then
        self.last_status = {safe=false, reason='cycle_interval',
            progress=1, expected=2, missing={}}
        return self:status()
    end

    -- Retain only the in-memory rolling proof. Every later observation fully
    -- revalidates it, and any failure/context change/reset closes it at once.
    for name, sequence in pairs(evidence.sequences) do
        self.first_sequences[name] = sequence
        self.first_receipts[name] = evidence.receipts[name]
    end
    self.first_cycle_at = second_at
    self.last_status = {safe=true, reason='safe', progress=2,
        expected=2, missing={}}
    return self:status()
end

return RewardSafety
