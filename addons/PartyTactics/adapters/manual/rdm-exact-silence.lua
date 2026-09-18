local M = {id='rdm-exact-silence'}

local function safe_label(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
        and value:match("^[A-Za-z0-9][A-Za-z0-9 ._'+-]*$") ~= nil
end

local function allowed_names(policy)
    if type(policy.target_names) ~= 'table' then return nil end
    local result = {}
    for _, name in ipairs(policy.target_names) do
        if not safe_label(name) then return nil end
        result[name:lower()] = true
    end
    return next(result) and result or nil
end

local function live_enemy(mob)
    return type(mob) == 'table' and mob.spawn_type == 16
        and mob.valid_target and (tonumber(mob.hpp) or 0) > 0
        and type(mob.id) == 'number' and mob.id >= 1
        and mob.id <= 4294967295 and mob.id == math.floor(mob.id)
        and type(mob.name) == 'string'
end

local function better(policy, candidate, current)
    if not current then return true end
    if policy.prefer_highest_hpp == true then
        local candidate_hpp = tonumber(candidate.hpp) or 0
        local current_hpp = tonumber(current.hpp) or 0
        if candidate_hpp ~= current_hpp then return candidate_hpp > current_hpp end
    end
    local candidate_distance = tonumber(candidate.distance) or math.huge
    local current_distance = tonumber(current.distance) or math.huge
    if candidate_distance ~= current_distance then
        return candidate_distance < current_distance
    end
    return candidate.id < current.id
end

function M.execute(ctx, policy)
    if type(ctx) ~= 'table' or type(ctx.actions) ~= 'table'
        or type(ctx.actions.controller) ~= 'function'
        or type(ctx.mob_array) ~= 'function'
        or type(ctx.party_claimed) ~= 'function'
        or type(policy) ~= 'table'
    then
        return false, 'invalid exact Silence policy'
    end
    local names = allowed_names(policy)
    if not names then return false, 'invalid exact Silence policy' end

    local selected
    for _, mob in pairs(ctx.mob_array() or {}) do
        if live_enemy(mob) and names[mob.name:lower()]
            and ctx.party_claimed(mob) and better(policy, mob, selected)
        then
            selected = mob
        end
    end
    if not selected then
        return false, 'no living party-claimed exact enemy is visible'
    end

    -- The adapter can request only this one typed controller operation. The
    -- RDM GearSwap controller revalidates the live ID and owns the queued cast,
    -- normal equipment path, bounded retries, and completion release.
    return ctx.actions.controller('rdm', 'silence', selected.id)
end

return M
