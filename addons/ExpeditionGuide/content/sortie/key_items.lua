-- Key-item evidence catalog. The order is a protocol contract: append future
-- entries; never reorder or repurpose an existing slot.

local ordered = {
    {key='shiny_plate', id=3300, name="Shiny Ra'Kaznarian plate"},
    {key='ruspix_plate', id=3328, name="Ruspix's plate"},
    {key='dull_plate', id=3301, name="Dull Ra'Kaznarian plate"},
}

local by_key, by_id = {}, {}
for index, item in ipairs(ordered) do
    item.protocol_index = index
    by_key[item.key] = item
    by_id[item.id] = item
end

return {
    ordered=ordered,
    by_key=by_key,
    by_id=by_id,
    diagnostics={
        entry_plate={
            title='ENTRY PLATES',
            primary='shiny_plate',
            secondary='dull_plate',
            primary_label='Shiny',
            secondary_label='Dull',
            missing_label='missing',
            invalid_label='INVALID',
            unknown_label='unknown',
        },
    },
}
