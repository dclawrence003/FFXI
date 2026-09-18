-- Read-only Windower sensing. The neutral snapshot is projected into one
-- independently identified evidence report per installed content pack.

local Sensors = {}

local function finite(value)
    return type(value) == 'number' and value == value
        and value > -math.huge and value < math.huge
end

local function id_set(values)
    local result = {}
    for key, value in pairs(values or {}) do
        local id = type(value) == 'table' and value.id or value
        if tonumber(id) then result[tonumber(id)] = true end
        if tonumber(key) and type(value) == 'boolean' and value then
            result[tonumber(key)] = true
        end
    end
    return result
end

local function party_evidence(ffxi, roster, expected_leader, player)
    local party = ffxi.get_party and ffxi.get_party() or nil
    if type(party) ~= 'table' or type(roster) ~= 'table' then
        return false, false
    end
    local expected, expected_count = {}, 0
    for _, name in ipairs(roster) do
        local normalized = tostring(name):lower()
        if normalized == '' or expected[normalized] then return false, false end
        expected[normalized], expected_count = true, expected_count + 1
    end
    local seen, member_count = {}, 0
    for index = 0, 5 do
        local member = party['p' .. tostring(index)]
        local name = member and type(member.name) == 'string'
            and member.name:lower() or nil
        if name then
            member_count = member_count + 1
            if seen[name] or not expected[name] then return false, false end
            seen[name] = true
        end
    end
    local exact = expected_count == 6 and member_count == expected_count
        and tonumber(party.party1_count) == expected_count
        and (tonumber(party.party2_count) or 0) == 0
        and (tonumber(party.party3_count) or 0) == 0
    if exact then
        for index = 10, 25 do
            local alliance_member = party['a' .. tostring(index)]
            if alliance_member and type(alliance_member.name) == 'string'
                and alliance_member.name ~= '' then
                exact = false
                break
            end
        end
    end
    if exact then
        for name in pairs(expected) do
            if not seen[name] then exact = false; break end
        end
    end
    -- party1_leader is authoritative only when compared with this client's
    -- own player ID. Followers may not have an ID/mob table for a distant
    -- Dolomedes, so they report no leadership claim instead of false failure.
    local leader_exact = exact and type(player) == 'table'
        and tostring(player.name or ''):lower()
            == tostring(expected_leader or ''):lower()
        and tonumber(player.id) ~= nil
        and tonumber(player.id) == tonumber(party.party1_leader)
    return exact, leader_exact
end

function Sensors.snapshot(windower_api, now, roster, expected_leader)
    local ffxi = assert(windower_api and windower_api.ffxi,
        'Windower FFXI API required')
    local player = ffxi.get_player and ffxi.get_player() or nil
    local info = ffxi.get_info and ffxi.get_info() or nil
    if not player or not player.name or not info then return nil end
    local me = ffxi.get_mob_by_target and ffxi.get_mob_by_target('me') or nil
    if not me and ffxi.get_mob_by_id and player.id then
        me = ffxi.get_mob_by_id(player.id)
    end
    local temporary = ffxi.get_items and ffxi.get_items(3) or nil
    local key_items = ffxi.get_key_items and ffxi.get_key_items() or nil
    local party_exact, leader_exact = party_evidence(
        ffxi, roster, expected_leader, player)
    local x, y, z = me and me.x, me and me.y, me and me.z
    local position_ready = finite(x) and finite(y) and finite(z)
    return {
        sender=player.name,
        main_job=tostring(player.main_job or ''):upper(),
        sub_job=tostring(player.sub_job or ''):upper(),
        zone=tonumber(info.zone) or 0,
        timestamp=tonumber(now) or os.time(),
        x=position_ready and x or 0,
        y=position_ready and y or 0,
        z=position_ready and z or 0,
        facing=tonumber(me and me.facing) or 0,
        status=tonumber(player.status or (me and me.status)) or 0,
        ready=me ~= nil and position_ready and type(temporary) == 'table'
            and type(key_items) == 'table' and tonumber(info.zone) ~= nil,
        party_exact=party_exact,
        leader_exact=leader_exact,
        temporary_ids=id_set(temporary),
        key_item_ids=id_set(key_items),
    }
end

function Sensors.report(snapshot, pack, sequence, entry_nonce)
    assert(type(snapshot) == 'table', 'sensor snapshot required')
    assert(type(pack) == 'table' and type(pack.id) == 'string'
        and type(pack.catalog_id) == 'string', 'sensor pack required')
    local item_bits, key_bits = {}, {}
    for index, item in ipairs(pack.items.ordered) do
        item_bits[index] = snapshot.temporary_ids[item.id] and '1' or '0'
    end
    for index, item in ipairs(pack.key_items.ordered) do
        key_bits[index] = snapshot.key_item_ids[item.id] and '1' or '0'
    end
    return {
        pack_id=pack.id, catalog_id=pack.catalog_id,
        sender=snapshot.sender, main_job=snapshot.main_job,
        sub_job=snapshot.sub_job, zone=snapshot.zone,
        timestamp=snapshot.timestamp, sequence=tonumber(sequence) or 0,
        x=snapshot.x, y=snapshot.y, z=snapshot.z, facing=snapshot.facing,
        status=snapshot.status, ready=snapshot.ready == true,
        party_exact=snapshot.party_exact == true,
        leader_exact=snapshot.leader_exact == true,
        entry_nonce=tostring(entry_nonce or ''),
        items=table.concat(item_bits), key_items=table.concat(key_bits),
    }
end

local function name_matches(mob, landmark)
    if not mob or not landmark then return false end
    local wanted = tostring(landmark.name or ''):lower()
    if tostring(mob.name or ''):lower() == wanted then return true end
    for _, name in ipairs(landmark.target_names or {}) do
        if tostring(mob.name or ''):lower() == tostring(name):lower() then
            return true
        end
    end
    -- Numbered gates/devices must match exactly. A broad family match could
    -- otherwise turn a shifted entity index into a confidently wrong arrow.
    if wanted:find('#', 1, true) then return false end
    local family = tostring(landmark.entity_family or ''):lower()
    if family ~= '' and tostring(mob.name or ''):lower():sub(1, #family)
        == family then return true end
    return false
end

function Sensors.matches_landmark(mob, landmark)
    return name_matches(mob, landmark)
end

function Sensors.live_landmark(windower_api, landmark_id, landmark)
    if not windower_api or not windower_api.ffxi or not landmark then return nil end
    local mob = landmark.entity_index and windower_api.ffxi.get_mob_by_index
        and windower_api.ffxi.get_mob_by_index(landmark.entity_index) or nil
    if mob and name_matches(mob, landmark) then
        return {id=landmark_id, name=mob.name, x=mob.x, y=mob.y, z=mob.z,
            radius=landmark.radius or 5,
            z_tolerance=landmark.z_tolerance or 12,
            confidence='live_entity'}
    end
    local target = windower_api.ffxi.get_mob_by_target
        and windower_api.ffxi.get_mob_by_target('t') or nil
    if target and (not landmark.entity_index
        or tonumber(target.index) == tonumber(landmark.entity_index))
        and name_matches(target, landmark) then
        return {id=landmark_id, name=target.name, x=target.x, y=target.y,
            z=target.z, radius=landmark.radius or 5,
            z_tolerance=landmark.z_tolerance or 12,
            confidence='live_target'}
    end
    return nil
end

return Sensors
