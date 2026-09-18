-- Read-only, profile-owned readiness checks for PartyTactics.
--
-- This module never sends a command and never equips an item.  Callers inject
-- the Windower FFXI API and resources table so the evaluator is deterministic
-- and can be exercised without a game client.

local M = {}

local EQUIPMENT_SLOTS = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring',
    'right_ring', 'back',
}

local EQUIPPABLE_BAGS = {
    'Inventory', 'Wardrobe', 'Wardrobe2', 'Wardrobe3', 'Wardrobe4',
    'Wardrobe5', 'Wardrobe6', 'Wardrobe7', 'Wardrobe8',
}

local function clean(value)
    local text = tostring(value or '')
        :gsub('[|\r\n]', ' ')
        :gsub('%s+', ' ')
        :match('^%s*(.-)%s*$')
    if #text > 180 then text = text:sub(1, 177)..'...' end
    return text
end

local function same_text(left, right)
    return type(left) == 'string' and type(right) == 'string'
        and left:lower() == right:lower()
end

local function add(result, bucket, message)
    result[bucket][#result[bucket] + 1] = clean(message)
end

local function find_named(collection, name)
    if type(collection) ~= 'table' or type(name) ~= 'string' then return nil end
    if type(collection.with) == 'function' then
        local ok, value = pcall(collection.with, collection, 'en', name)
        if ok and value then return value end
    end
    for _, value in pairs(collection) do
        if type(value) == 'table' and same_text(value.en, name) then
            return value
        end
    end
    return nil
end

local function collection_has_id(collection, wanted)
    wanted = tonumber(wanted)
    if type(collection) ~= 'table' or not wanted then return false end
    if collection[wanted] == true or tonumber(collection[wanted]) == wanted then
        return true
    end
    for key, value in pairs(collection) do
        if tonumber(value) == wanted
            or value == true and tonumber(key) == wanted
        then
            return true
        end
    end
    return false
end

local function item_name(resources, item)
    local id = type(item) == 'table' and tonumber(item.id) or nil
    local resource = id and resources and resources.items
        and resources.items[id] or nil
    return resource and resource.en or (id and ('item '..id) or 'empty')
end

local function get_items(ffxi, ...)
    if not ffxi or type(ffxi.get_items) ~= 'function' then return nil end
    local ok, value = pcall(ffxi.get_items, ...)
    return ok and value or nil
end

local function equipped_name(ffxi, resources, slot)
    local all = get_items(ffxi)
    local equipment = all and all.equipment or nil
    if type(equipment) ~= 'table' then return nil, 'equipment unavailable' end
    local index = tonumber(equipment[slot])
    local bag = tonumber(equipment[slot..'_bag'])
    if not index or index == 0 or bag == nil then return 'empty' end
    local item = get_items(ffxi, bag, index)
    if not item or not item.id then return nil, 'equipped item unavailable' end
    return item_name(resources, item)
end

local function find_member(members, player_name)
    if type(members) ~= 'table' then return nil end
    for name, policy in pairs(members) do
        if same_text(name, player_name) then return policy end
    end
    return nil
end

local function expected_names(expected)
    if type(expected) == 'string' then return {expected} end
    if type(expected) == 'table' and type(expected.any_of) == 'table' then
        return expected.any_of
    end
    return {}
end

local function expected_label(expected)
    local names = expected_names(expected)
    return clean(table.concat(names, ' or '))
end

local function check_equipment(result, policies, ffxi, resources)
    local merged = {}
    for _, policy in ipairs(policies) do
        for slot, expected in pairs(
            type(policy.equipment) == 'table' and policy.equipment or {})
        do
            merged[slot] = expected
        end
    end
    local seen = {}
    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local expected = merged[slot]
        if expected ~= nil then
            seen[slot] = true
            local names = expected_names(expected)
            if #names == 0 then
                add(result, 'errors', 'equipment '..slot..' has invalid expectation')
            else
                local actual, reason = equipped_name(ffxi, resources, slot)
                local matches = false
                for _, name in ipairs(names) do
                    if same_text(actual, name) then matches = true; break end
                end
                if matches then
                    add(result, 'details', 'equipment '..slot..' '..actual)
                else
                    add(result, 'errors', ('equipment %s expected %s found %s')
                        :format(slot, expected_label(expected),
                            clean(actual or reason or 'unknown')))
                end
            end
        end
    end
    local extras = {}
    for slot, _ in pairs(merged) do
        if not seen[slot] then extras[#extras + 1] = tostring(slot) end
    end
    table.sort(extras)
    for _, slot in ipairs(extras) do
        add(result, 'errors', 'unsupported equipment slot '..slot)
    end
end

local function bags_for(requirement)
    if type(requirement.bags) == 'table' then return requirement.bags end
    if requirement.bag_group == nil or requirement.bag_group == 'equippable' then
        return EQUIPPABLE_BAGS
    end
    if requirement.bag_group == 'inventory' then return {'Inventory'} end
    return nil
end

local function count_named_items(ffxi, resources, names, bags)
    local wanted = {}
    for _, name in ipairs(names) do
        if type(name) == 'string' then wanted[name:lower()] = true end
    end
    local total = 0
    for _, bag_name in ipairs(bags or {}) do
        local bag = get_items(ffxi, bag_name)
        if type(bag) == 'table' and bag.enabled ~= false then
            for _, item in ipairs(bag) do
                local name = item_name(resources, item)
                if wanted[name:lower()] then
                    total = total + (tonumber(item.count) or 0)
                end
            end
        end
    end
    return total
end

local function item_requirement_names(requirement)
    if type(requirement.name) == 'string' then return {requirement.name} end
    if type(requirement.any_of) == 'table' then return requirement.any_of end
    return {}
end

local function item_requirement_label(requirement)
    return clean(requirement.label
        or table.concat(item_requirement_names(requirement), ' or '))
end

local function check_items(result, policies, ffxi, resources)
    for _, policy in ipairs(policies) do
        for _, requirement in ipairs(
            type(policy.items) == 'table' and policy.items or {})
        do
            local names = item_requirement_names(requirement)
            local bags = bags_for(requirement)
            local label = item_requirement_label(requirement)
            local minimum = tonumber(requirement.minimum) or 1
            if #names == 0 or not bags or minimum < 0 then
                add(result, 'errors', 'invalid item requirement '..label)
            else
                local count = count_named_items(ffxi, resources, names, bags)
                if count < minimum then
                    add(result, requirement.optional and 'warnings' or 'errors',
                        ('item %s %d found need %d'):format(
                            label, count, minimum))
                else
                    add(result, 'details', ('item %s %d'):format(label, count))
                    local warn_below = tonumber(requirement.warn_below)
                    if warn_below and count < warn_below then
                        add(result, 'warnings', ('item %s low %d recommend %d')
                            :format(label, count, warn_below))
                    end
                end
            end
        end
    end
end

local function key_item_set(ffxi)
    if not ffxi or type(ffxi.get_key_items) ~= 'function' then return nil end
    local ok, values = pcall(ffxi.get_key_items)
    if not ok or type(values) ~= 'table' then return nil end
    local result = {}
    for key, value in pairs(values) do
        local id = tonumber(value) or (value == true and tonumber(key) or nil)
        if id then result[id] = true end
    end
    return result
end

local function key_item_ids(requirement)
    if tonumber(requirement.id) then return {tonumber(requirement.id)} end
    return type(requirement.ids) == 'table' and requirement.ids or {}
end

local function check_key_items(result, policies, ffxi, resources)
    local owned = key_item_set(ffxi)
    for _, policy in ipairs(policies) do
        for _, requirement in ipairs(
            type(policy.key_items) == 'table' and policy.key_items or {})
        do
            local ids = key_item_ids(requirement)
            local label = requirement.label
            if not label and #ids == 1 and resources and resources.key_items then
                local resource = resources.key_items[tonumber(ids[1])]
                label = resource and resource.en or nil
            end
            label = clean(label or 'key item')
            local present = false
            for _, id in ipairs(ids) do
                if owned and owned[tonumber(id)] then present = true; break end
            end
            if #ids == 0 then
                add(result, 'errors', 'invalid key item requirement '..label)
            elseif present then
                add(result, 'details', 'key item '..label)
            else
                local reason = owned and 'missing' or 'unavailable'
                add(result, requirement.optional and 'warnings' or 'errors',
                    'key item '..label..' '..reason)
            end
        end
    end
end

local function check_buffs(result, policies, player, resources)
    local active = {}
    for _, id in ipairs(type(player.buffs) == 'table' and player.buffs or {}) do
        active[tonumber(id)] = true
    end
    for _, policy in ipairs(policies) do
        for _, requirement in ipairs(
            type(policy.buffs) == 'table' and policy.buffs or {})
        do
            local exact_id = type(requirement) == 'table'
                and tonumber(requirement.id) or nil
            local label = type(requirement) == 'table'
                and requirement.label or requirement
            local resource = exact_id and resources and resources.buffs
                and resources.buffs[exact_id]
                or find_named(resources and resources.buffs, requirement)
            if not resource then
                add(result, 'errors', 'buff '..clean(label)..' unknown')
            elseif active[exact_id or tonumber(resource.id)] then
                add(result, 'details', 'buff '..clean(label)..' active')
            else
                add(result, 'errors', 'buff '..clean(label)..' missing')
            end
        end
    end
end

local function check_zone(result, policy, ffxi, resources)
    local expected = tonumber(policy and policy.zone)
    if not expected then return end
    local info = ffxi and type(ffxi.get_info) == 'function'
        and ffxi.get_info() or nil
    local actual = info and tonumber(info.zone) or nil
    local zone = resources and resources.zones and resources.zones[expected]
    local label = zone and zone.en or tostring(expected)
    if actual == expected then
        add(result, 'details', 'zone '..clean(label))
    else
        add(result, 'errors', ('zone expected %s found %s'):format(
            clean(label), clean(actual or 'unavailable')))
    end
end

local function player_can_cast(player, spell, learned)
    if not spell or not collection_has_id(learned, spell.id) then return false end
    if type(spell.levels) ~= 'table' then return true end
    local main_id = tonumber(player and player.main_job_id)
    local sub_id = tonumber(player and player.sub_job_id)
    local main_requirement = main_id and tonumber(spell.levels[main_id]) or nil
    local sub_requirement = sub_id and tonumber(spell.levels[sub_id]) or nil
    local main_level = tonumber(player and player.main_job_level) or 0
    local sub_level = tonumber(player and player.sub_job_level) or 0
    local main_job = player and type(player.main_job) == 'string'
        and player.main_job:lower() or ''
    local jp = player and player.job_points and player.job_points[main_job]
    local jp_spent = tonumber(jp and jp.jp_spent) or 0
    return main_requirement ~= nil
            and (main_requirement <= main_level or main_requirement <= jp_spent)
        or sub_requirement ~= nil and sub_requirement <= sub_level
end

local function check_actions(result, policies, player, ffxi, resources)
    local abilities = ffxi and type(ffxi.get_abilities) == 'function'
        and ffxi.get_abilities() or {}
    local learned = ffxi and type(ffxi.get_spells) == 'function'
        and ffxi.get_spells() or {}
    for _, policy in ipairs(policies) do
        for _, requirement in ipairs(
            type(policy.actions) == 'table' and policy.actions or {})
        do
            local kind, name = requirement.kind, requirement.name
            local resource, available
            if kind == 'weaponskill' then
                resource = find_named(resources and resources.weapon_skills, name)
                available = resource and collection_has_id(
                    abilities and abilities.weapon_skills, resource.id)
            elseif kind == 'ability' then
                resource = find_named(resources and resources.job_abilities, name)
                available = resource and collection_has_id(
                    abilities and abilities.job_abilities, resource.id)
            elseif kind == 'spell' then
                resource = find_named(resources and resources.spells, name)
                available = resource and player_can_cast(player, resource, learned)
            else
                add(result, 'errors', 'invalid action kind '..clean(kind))
            end
            if kind == 'weaponskill' or kind == 'ability' or kind == 'spell' then
                local label = clean(name or 'unnamed')
                if available then
                    add(result, 'details', 'action '..label..' available')
                else
                    local reason = resource and 'unavailable' or 'unknown'
                    add(result, requirement.optional and 'warnings' or 'errors',
                        'action '..label..' '..reason)
                end
            end
        end
    end
end

local function sorted(values)
    table.sort(values)
    return values
end

-- Contract:
--   evaluate(profile.preflight, player.name, windower.ffxi, res)
--
-- profile.preflight may contain an `all` policy and a case-insensitive
-- `members` table.  Each policy supports:
--   zone = 289
--   equipment = {range='Death Penalty', ...}
--   items = {{name='Living Bullet', minimum=1, warn_below=12,
--             bag_group='equippable'}, ...}
--   key_items = {{id=2949, label="Genbu's Honor"},
--                {ids={2894,3031}, label='Tribulens or Radialens'}, ...}
--   buffs = {'March', {id=551, label='Indi-Acumen'}, ...}
--   actions = {{kind='weaponskill|ability|spell', name='...',
--               optional=true|false}, ...}
function M.evaluate(policy, player_name, ffxi, resources)
    local result = {passed=false, errors={}, warnings={}, details={}}
    local player = ffxi and type(ffxi.get_player) == 'function'
        and ffxi.get_player() or nil
    if type(policy) ~= 'table' then
        add(result, 'errors', 'preflight policy unavailable')
    elseif not player or type(player.name) ~= 'string' then
        add(result, 'errors', 'local player unavailable')
    elseif not same_text(player.name, player_name) then
        add(result, 'errors', ('local player expected %s found %s')
            :format(clean(player_name), clean(player.name)))
    else
        check_zone(result, policy, ffxi, resources or {})
        local policies = {}
        if type(policy.all) == 'table' then policies[#policies + 1] = policy.all end
        local member = find_member(policy.members, player_name)
        if member then policies[#policies + 1] = member end
        if #policies == 0 then
            add(result, 'errors', 'no preflight policy for '..clean(player_name))
        else
            check_equipment(result, policies, ffxi, resources or {})
            check_items(result, policies, ffxi, resources or {})
            check_key_items(result, policies, ffxi, resources or {})
            check_buffs(result, policies, player, resources or {})
            check_actions(result, policies, player, ffxi, resources or {})
        end
    end
    sorted(result.errors)
    sorted(result.warnings)
    sorted(result.details)
    result.passed = #result.errors == 0
    return result
end

function M.summary(result)
    result = type(result) == 'table' and result or {}
    return ('%s errors=%d warnings=%d details=%d'):format(
        result.passed and 'PASS' or 'FAIL',
        #(result.errors or {}), #(result.warnings or {}),
        #(result.details or {}))
end

return M
