return {
    id='brd-pack-sleep',
    execute=function(ctx)
        return ctx.actions.controller('brd', 'sleep')
    end,
}
