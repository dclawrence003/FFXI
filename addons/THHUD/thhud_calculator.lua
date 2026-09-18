-- Calculate the Treasure Hunter value a local player can apply from job
-- traits, currently set BLU spells, equipped items, and decoded augments.

local Calculator = {}

local TH_BLUE_MAGIC = {
    [680] = 6, -- Charged Whisker
    [683] = 6, -- Evryone. Grudge
    [697] = 6, -- Amorphic Spikes
}

local function integer(value, fallback)
    value = tonumber(value)
    if not value then
        return fallback
    end
    return math.floor(value)
end

local function th_from_text(text)
    if type(text) ~= 'string' then
        return 0
    end

    local total = 0
    for amount in text:gmatch('[Tt]reasure%s+[Hh]unter["\']?%s*%+(%d+)') do
        total = total + (tonumber(amount) or 0)
    end
    return total
end

local function thf_trait(level)
    level = integer(level, 0)
    if level >= 90 then
        return 3
    elseif level >= 45 then
        return 2
    elseif level >= 15 then
        return 1
    end
    return 0
end

local function blue_trait(player, blue_data)
    if tostring(player.main_job or ''):upper() ~= 'BLU'
        or type(blue_data) ~= 'table' or type(blue_data.spells) ~= 'table' then
        return 0, 0
    end

    local points, spell_count = 0, 0
    local seen = {}
    for _, spell_id in pairs(blue_data.spells) do
        spell_id = tonumber(spell_id)
        if TH_BLUE_MAGIC[spell_id] and not seen[spell_id] then
            points = points + TH_BLUE_MAGIC[spell_id]
            spell_count = spell_count + 1
            seen[spell_id] = true
        end
    end
    -- These spells also participate in Gilfinder.  Two set spells grant that
    -- trait, not Treasure Hunter; the TH combination requires all three.
    if spell_count < 3 then
        return 0, points
    end

    local tier = 1
    local job_points = player.job_points or {}
    local blu = job_points.blu or job_points.BLU or {}
    local spent = integer(blu.jp_spent or blu.spent, 0)
    if spent >= 100 then
        tier = tier + 1
    end
    if spent >= 1200 then
        tier = tier + 1
    end
    return tier, points
end

local function description_for(item, resources)
    if not resources or not resources.item_descriptions then
        return nil
    end
    local entry = resources.item_descriptions[item.id]
    return entry and (entry.en or entry.english) or nil
end

local function augment_th(item, extdata)
    if not extdata or type(extdata.decode) ~= 'function' then
        return 0, {}
    end
    local ok, decoded = pcall(extdata.decode, item)
    if not ok or type(decoded) ~= 'table' or type(decoded.augments) ~= 'table' then
        return 0, {}
    end

    local total, matches = 0, {}
    for _, augment in pairs(decoded.augments) do
        local amount = th_from_text(augment)
        if amount > 0 then
            total = total + amount
            matches[#matches + 1] = tostring(augment)
        end
    end
    return total, matches
end

function Calculator.text_value(text)
    return th_from_text(text)
end

-- equipment is an array of raw get_items(bag, slot) records.
function Calculator.calculate(player, equipment, resources, extdata, options)
    player = player or {}
    equipment = equipment or {}
    options = options or {}

    local main_job = tostring(player.main_job or ''):upper()
    local main_trait = main_job == 'THF'
        and thf_trait(player.main_job_level) or 0
    local sub_trait = tostring(player.sub_job or ''):upper() == 'THF'
        and thf_trait(player.sub_job_level) or 0
    local blu_trait, blu_points = blue_trait(player, options.blue_data)
    local trait = math.max(main_trait, sub_trait, blu_trait)

    local gear_total, gear = 0, {}
    for _, item in pairs(equipment) do
        if type(item) == 'table' and tonumber(item.id) and tonumber(item.id) > 0 then
            local static = th_from_text(description_for(item, resources))
            local augmented, matches = augment_th(item, extdata)
            local amount = static + augmented
            if amount > 0 then
                gear_total = gear_total + amount
                gear[#gear + 1] = {
                    id = tonumber(item.id),
                    name = resources and resources.items
                        and resources.items[item.id]
                        and (resources.items[item.id].en
                            or resources.items[item.id].english) or nil,
                    static = static,
                    augmented = augmented,
                    augment_text = matches,
                    total = amount,
                }
            end
        end
    end

    local manual = math.max(0, integer(options.manual_equipment_bonus, 0))
    gear_total = gear_total + manual
    local cap = main_job == 'THF' and 8 or 4
    local before_hound = math.min(cap, trait + gear_total)
    local treasure_hound = options.treasure_hound == true and 1 or 0
    local value = before_hound + treasure_hound

    return value, {
        value = value,
        trait = trait,
        main_trait = main_trait,
        sub_trait = sub_trait,
        blue_trait = blu_trait,
        blue_trait_points = blu_points,
        gear_total = gear_total,
        manual_equipment_bonus = manual,
        equipment_cap = cap,
        treasure_hound = treasure_hound,
        gear = gear,
    }
end

return Calculator
