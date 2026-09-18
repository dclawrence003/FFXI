-- Pack-owned reward regions. A route may reference these definitions but may
-- never override them. Geometry is advisory only: it cannot target, open, or
-- block a chest.

return {
    ground_floor={
        label='Sortie ground floor',
        regions={
            {
                kind='z_band',
                zones={[133]=true,[189]=true,[275]=true},
                min=-240,
                max=-110,
            },
        },
    },
}
