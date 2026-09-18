local Fingerprint = require('lib.fingerprint')

local PartyState = {}
PartyState.__index = PartyState

local function finite(value)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
end

function PartyState.new(roster, pack, expected_leader)
    assert(type(pack) == 'table' and type(pack.id) == 'string'
        and type(pack.catalog_id) == 'string', 'valid pack required')
    local allowed = {}
    for _, name in ipairs(roster or {}) do allowed[name:lower()] = name end
    local leader = allowed[tostring(expected_leader
        or (roster and roster[1]) or ''):lower()]
    assert(leader, 'expected leader must be in roster')
    return setmetatable({
        roster=roster or {}, allowed=allowed, pack=pack, reports={},
        retired_nonces={},
        expected_leader=leader,
    }, PartyState)
end

function PartyState:allowed_sender(name)
    return self.allowed[tostring(name or ''):lower()] ~= nil
end

function PartyState:update(report, received_at)
    if type(report) ~= 'table' or not self:allowed_sender(report.sender)
        or report.pack_id ~= self.pack.id
        or report.catalog_id ~= self.pack.catalog_id
        or type(report.items) ~= 'string'
        or #report.items ~= #self.pack.items.ordered
        or report.items:match('[^01]')
        or type(report.key_items) ~= 'string'
        or #report.key_items ~= #self.pack.key_items.ordered
        or report.key_items:match('[^01]')
        or type(report.entry_nonce) ~= 'string'
        or #report.entry_nonce > 96
        or (report.entry_nonce ~= ''
            and (report.entry_nonce:match('^[a-z0-9][a-z0-9_-]*$') == nil
                or self.pack.instance_zones[tonumber(report.zone)] ~= true)) then
        return false
    end
    local timestamp = tonumber(report.timestamp)
    local sequence = tonumber(report.sequence)
    received_at = tonumber(received_at ~= nil and received_at
        or report.received_at ~= nil and report.received_at or os.clock())
    if not timestamp or not sequence or not finite(received_at)
        or received_at < 0 then return false end
    report.timestamp, report.sequence = timestamp, sequence
    local canonical = self.allowed[report.sender:lower()]
    report.sender = canonical
    local previous = self.reports[canonical]
    if previous and finite(previous.received_at)
        and received_at < previous.received_at then return false end
    local nonce_changed = previous
        and previous.entry_nonce ~= report.entry_nonce
    if nonce_changed then
        local retired = self.retired_nonces[canonical]
        if not retired then
            retired = {set={}, order={}}
            self.retired_nonces[canonical] = retired
        end
        if report.entry_nonce ~= '' and retired.set[report.entry_nonce] then
            return false
        end
        local old_nonce = previous.entry_nonce
        if old_nonce ~= nil and old_nonce ~= '' then
            retired.set[old_nonce] = true
            retired.order[#retired.order + 1] = old_nonce
            if #retired.order > 32 then
                retired.set[table.remove(retired.order, 1)] = nil
            end
        end
    else
        if previous and (tonumber(previous.timestamp) or 0) > timestamp then
            return false
        end
        if previous and previous.timestamp == timestamp
            and (tonumber(previous.sequence) or 0) >= sequence then
            return false
        end
    end
    report.received_at = received_at
    self.reports[canonical] = report
    return true
end

local function bit(report, field, index)
    local value = report and report[field]
    return type(value) == 'string' and value:sub(index, index) == '1'
end

function PartyState:summary(now, max_age, leader_zone)
    now = tonumber(now) or os.time()
    max_age = tonumber(max_age) or 8
    leader_zone = tonumber(leader_zone)
    local summary = {
        pack_id=self.pack.id, catalog_id=self.pack.catalog_id,
        expected=#self.roster, fresh=0, ready=0, same_zone=0, in_pack=0,
        party_exact=0, leader_exact=0, leader_expected=1,
        sensor_quorum=true, party_quorum=true,
        leader_quorum=false, all_in_pack=true, all_clients_idle=true,
        all_items={}, missing={}, all_key_items={}, missing_key_items={},
        key_item_counts={}, key_item_presence={},
        stale_clients={}, unready_clients={},
        other_zone_clients={}, party_mismatch_clients={},
        leader_mismatch_clients={}, engaged_clients={},
        entry_nonces={}, missing_entry_nonce_clients={},
        entry_nonce_quorum=true, run_quorum=false,
        run_id=nil, run_zone=nil, run_cohort=nil,
        leader_entry_nonce=nil,
    }
    for _, item in ipairs(self.pack.items.ordered) do
        summary.all_items[item.key] = true
        summary.missing[item.key] = {}
    end
    for _, item in ipairs(self.pack.key_items.ordered) do
        summary.all_key_items[item.key] = true
        summary.missing_key_items[item.key] = {}
        summary.key_item_counts[item.key] = 0
    end
    local nonce_owners = {}
    for _, name in ipairs(self.roster) do
        local report = self.reports[name]
        local fresh = report and tonumber(report.timestamp)
            and report.timestamp >= now - max_age
            and report.timestamp <= now + 2
        if fresh then summary.fresh = summary.fresh + 1 end
        local ready = fresh and report.ready == true
        if ready then summary.ready = summary.ready + 1 end
        local same_zone = ready and tonumber(report.zone) == leader_zone
        if same_zone then summary.same_zone = summary.same_zone + 1 end
        local exact_party = same_zone and report.party_exact == true
        local is_expected_leader = name == self.expected_leader
        local exact_leader = is_expected_leader and exact_party
            and report.leader_exact == true
        if exact_party then summary.party_exact = summary.party_exact + 1 end
        if exact_leader then summary.leader_exact = summary.leader_exact + 1 end
        if not fresh then
            summary.stale_clients[#summary.stale_clients + 1] = name
        elseif not ready then
            summary.unready_clients[#summary.unready_clients + 1] = name
        elseif not same_zone then
            summary.other_zone_clients[#summary.other_zone_clients + 1] = name
        elseif not exact_party then
            summary.party_mismatch_clients[
                #summary.party_mismatch_clients + 1] = name
        elseif is_expected_leader and not exact_leader then
            summary.leader_mismatch_clients[
                #summary.leader_mismatch_clients + 1] = name
        elseif tonumber(report.status) ~= 0 then
            summary.engaged_clients[#summary.engaged_clients + 1] = name
        end
        if ready and self.pack.instance_zones[tonumber(report.zone)] then
            summary.in_pack = summary.in_pack + 1
        end
        if not same_zone then summary.sensor_quorum = false end
        if not exact_party then summary.party_quorum = false end
        if exact_leader then summary.leader_quorum = true end
        if exact_party then summary.key_item_presence[name] = {} end
        local entry_nonce = same_zone and report.entry_nonce or nil
        if type(entry_nonce) == 'string' and entry_nonce ~= '' then
            if nonce_owners[entry_nonce] then
                summary.entry_nonce_quorum = false
                summary.missing_entry_nonce_clients[
                    #summary.missing_entry_nonce_clients + 1] = name
            else
                nonce_owners[entry_nonce] = name
                summary.entry_nonces[name] = entry_nonce
                if is_expected_leader then
                    summary.leader_entry_nonce = entry_nonce
                end
            end
        else
            summary.entry_nonce_quorum = false
            summary.missing_entry_nonce_clients[
                #summary.missing_entry_nonce_clients + 1] = name
        end
        if not same_zone or not exact_party
            or not self.pack.instance_zones[tonumber(report.zone)] then
            summary.all_in_pack = false
        end
        if not same_zone or tonumber(report.status) ~= 0 then
            summary.all_clients_idle = false
        end
        for index, item in ipairs(self.pack.key_items.ordered) do
            local present = same_zone and bit(report, 'key_items', index)
            if exact_party then
                summary.key_item_presence[name][item.key] = present == true
            end
            if present then
                summary.key_item_counts[item.key] =
                    summary.key_item_counts[item.key] + 1
            else
                summary.all_key_items[item.key] = false
                local missing = summary.missing_key_items[item.key]
                missing[#missing + 1] = name
            end
        end
        for index, item in ipairs(self.pack.items.ordered) do
            if not same_zone or not bit(report, 'items', index) then
                summary.all_items[item.key] = false
                summary.missing[item.key][#summary.missing[item.key] + 1] = name
            end
        end
    end
    if not summary.leader_quorum then summary.all_in_pack = false end
    summary.run_quorum = summary.all_in_pack
        and summary.sensor_quorum and summary.party_quorum
        and summary.leader_quorum and summary.entry_nonce_quorum
        and summary.fresh == summary.expected and summary.ready == summary.expected
    if summary.run_quorum then
        local entries = {}
        for _, name in ipairs(self.roster) do
            entries[#entries + 1] = name:lower() .. '='
                .. summary.entry_nonces[name]
        end
        local reversed = {}
        for index = #entries, 1, -1 do
            reversed[#reversed + 1] = entries[index]
        end
        summary.run_zone = leader_zone
        summary.run_cohort = table.concat(entries, '|')
        local first = Fingerprint.value({
            catalog_id=self.pack.catalog_id,
            zone=leader_zone,
            entries=entries,
        })
        local second = Fingerprint.value({
            domain='expedition-run-v1',
            catalog_id=self.pack.catalog_id,
            zone=leader_zone,
            entries=reversed,
        })
        summary.run_id = self.pack.id:sub(1, 63) .. '-' .. first .. second
    end
    return summary
end

return PartyState
