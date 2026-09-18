-- Normalize relevant fields from Windower's parsed 0x028 action structure.

local Actions = {}
local MAX_TH = 14

local QUALIFYING_CATEGORIES = {
    [1] = true,  -- melee
    [2] = true,  -- ranged attack
    [3] = true,  -- weapon skill
    [4] = true,  -- completed spell
    [6] = true,  -- job ability
    [14] = true, -- unblinkable job ability
}

local DEATH_MESSAGES = {[6] = true, [20] = true}

local function integer(value)
    value = tonumber(value)
    if value and value == math.floor(value) then
        return value
    end
    return nil
end

function Actions.is_qualifying_category(category)
    return QUALIFYING_CATEGORIES[tonumber(category)] == true
end

-- Returns ordered observations.  A confirmed proc suppresses an inferred
-- value for the same target; a death/reset always follows any observation.
function Actions.inspect(action, local_actor_id, inferred_value)
    local events = {}
    if type(action) ~= 'table' or type(action.targets) ~= 'table' then
        return events
    end

    local local_action = tonumber(action.actor_id) == tonumber(local_actor_id)
        and Actions.is_qualifying_category(action.category)
    inferred_value = integer(inferred_value)

    for _, target in pairs(action.targets) do
        local mob_id = integer(target and target.id)
        if mob_id and type(target.actions) == 'table' then
            local confirmed = nil
            local dead = false

            for _, result in pairs(target.actions) do
                local message = integer(result and result.message)
                local add_message = integer(result and result.add_effect_message)

                if message == 608 then
                    local value = integer(result.param)
                    if value then
                        confirmed = math.max(confirmed or 0, value)
                    end
                end
                if add_message == 603 then
                    local value = integer(result.add_effect_param)
                    if value then
                        confirmed = math.max(confirmed or 0, value)
                    end
                end
                if message and DEATH_MESSAGES[message] then
                    dead = true
                end
            end

            if confirmed and confirmed >= 1 and confirmed <= MAX_TH then
                events[#events + 1] = {
                    kind = 'confirmed', mob_id = mob_id, value = confirmed,
                }
            elseif local_action and inferred_value and inferred_value > 0 then
                events[#events + 1] = {
                    kind = 'inferred', mob_id = mob_id, value = inferred_value,
                }
            end

            if dead then
                events[#events + 1] = {kind = 'clear', mob_id = mob_id}
            end
        end
    end

    return events
end

return Actions
