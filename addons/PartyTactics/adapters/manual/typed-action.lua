return {
    id='typed-action',
    execute=function(ctx, policy)
        local action = ctx.actions[policy.kind]
        if type(action) ~= 'function' then
            return false, 'unsupported typed action'
        end
        return action(policy.name, policy.target)
    end,
}
