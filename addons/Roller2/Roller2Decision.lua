-- Roller2 safety-decision module.
-- Roller2 is derived from Roller by Selindrile, which also credits Balloon
-- and Lorand. The upstream notice is retained in Roller2.lua and applies to
-- inherited Roller code; see README.md for the complete relationship.

local decision = {}

local valid_policies = {
    conservative = true,
    balanced = true,
    aggressive = true,
}

function decision.normalize_policy(value)
    value = tostring(value or 'conservative'):lower()
    if not valid_policies[value] then
        return 'conservative'
    end
    return value
end

function decision.allows_snake_eye_reuse(policy, total, already_used)
    if not already_used then
        return true
    end
    policy = decision.normalize_policy(policy)
    if policy == 'aggressive' then
        return true
    end
    return policy == 'balanced' and tonumber(total) == 10
end

function decision.decide(context)
    local total = tonumber(context.total) or 0
    local lucky = tonumber(context.lucky)
    local unlucky = tonumber(context.unlucky)
    local policy = decision.normalize_policy(context.policy)

    if total < 1 then
        return 'stop', 'invalid roll total'
    end
    if total > 11 then
        return 'stop', 'bust result'
    end
    if total == 11 then
        return 'stop', 'XI'
    end
    if lucky and total == lucky then
        return 'stop', 'lucky number'
    end
    if context.crooked then
        return 'stop', 'Crooked Cards roll is protected'
    end

    if context.snake_eye_ready then
        if total == 10 then
            return 'snake_eye', 'Snake Eye guarantees XI'
        end
        if lucky and total == lucky - 1 then
            return 'snake_eye', 'Snake Eye guarantees the lucky number'
        end
        if unlucky and total > 6 and total == unlucky then
            return 'snake_eye', 'Snake Eye moves off the unlucky number'
        end
    end

    local ceiling = 5
    if context.fold_ready and policy == 'balanced' then
        ceiling = 7
    elseif context.fold_ready and policy == 'aggressive' then
        ceiling = 8
    end

    if total <= ceiling then
        if ceiling > 5 then
            return 'double_up', ('%s policy with Fold ready'):format(policy)
        end
        return 'double_up', 'cannot bust from this total'
    end

    if total == 9 then
        return 'stop', 'raw Double-Up on 9 is prohibited'
    end
    if total == 10 then
        return 'stop', 'Snake Eye unavailable; raw Double-Up on 10 is prohibited'
    end
    return 'stop', ('%s ceiling is %d'):format(policy, ceiling)
end

return decision
