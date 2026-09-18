return {
    id='clarion-extra-song',
    execute=function(ctx, policy)
        if not ctx.has_buff('Clarion Call') then
            return false, 'Clarion Call effect is not active'
        end
        return ctx.actions.cast(policy.name, policy.target)
    end,
}
