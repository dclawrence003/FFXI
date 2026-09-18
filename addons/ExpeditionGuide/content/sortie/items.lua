-- Temporary-item catalog.  The order is a protocol contract: append future
-- entries; never reorder existing ones.

local ordered = {
    {key='key_a', id=9894, name="Ra'Kaznar Key #A", permanent=true},
    {key='key_b', id=9895, name="Ra'Kaznar Key #B", permanent=true},
    {key='key_c', id=9896, name="Ra'Kaznar Key #C", permanent=true},
    {key='key_d', id=9897, name="Ra'Kaznar Key #D", permanent=true},
    {key='plate_a', id=9898, name="Ra'Kaznar Plate #A", permanent=true},
    {key='plate_b', id=9899, name="Ra'Kaznar Plate #B", permanent=true},
    {key='plate_c', id=9900, name="Ra'Kaznar Plate #C", permanent=true},
    {key='plate_d', id=9901, name="Ra'Kaznar Plate #D", permanent=true},
    {key='sheet_a', id=9902, name="Ra'Kaznar Sheet #A", permanent=true},
    {key='sheet_b', id=9903, name="Ra'Kaznar Sheet #B", permanent=true},
    {key='sheet_c', id=9904, name="Ra'Kaznar Sheet #C", permanent=true},
    {key='sheet_d', id=9905, name="Ra'Kaznar Sheet #D", permanent=true},
    {key='shard_a', id=9906, name="Ra'Kaznar Shard #A"},
    {key='shard_b', id=9907, name="Ra'Kaznar Shard #B"},
    {key='shard_c', id=9908, name="Ra'Kaznar Shard #C"},
    {key='shard_d', id=9909, name="Ra'Kaznar Shard #D"},
    {key='shard_e', id=9910, name="Ra'Kaznar Shard #E"},
    {key='shard_f', id=9911, name="Ra'Kaznar Shard #F"},
    {key='shard_g', id=9912, name="Ra'Kaznar Shard #G"},
    {key='shard_h', id=9913, name="Ra'Kaznar Shard #H"},
    {key='fragment_1', id=9914, name="Ra'Kaznar Fragment #1"},
    {key='fragment_2', id=9915, name="Ra'Kaznar Fragment #2"},
    {key='fragment_3', id=9916, name="Ra'Kaznar Fragment #3"},
    {key='fragment_4', id=9917, name="Ra'Kaznar Fragment #4"},
    {key='metal_a', id=9918, name="Ra'Kaznar Metal #A"},
    {key='metal_b', id=9919, name="Ra'Kaznar Metal #B"},
    {key='metal_c', id=9920, name="Ra'Kaznar Metal #C"},
    {key='metal_d', id=9921, name="Ra'Kaznar Metal #D"},
    {key='metal_e', id=9922, name="Ra'Kaznar Metal #E"},
    {key='metal_f', id=9923, name="Ra'Kaznar Metal #F"},
    {key='metal_g', id=9924, name="Ra'Kaznar Metal #G"},
    {key='metal_h', id=9925, name="Ra'Kaznar Metal #H"},
    {key='seal', id=9926, name="Ra'Kaznar Seal"},
    {key='obsidian_wing', id=6685, name='Obsidian Wing'},
}

local by_key, by_id = {}, {}
for index, item in ipairs(ordered) do
    item.protocol_index = index
    by_key[item.key] = item
    by_id[item.id] = item
end

return {ordered=ordered, by_key=by_key, by_id=by_id}
