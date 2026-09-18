-- Sortie landmark facts.  Device/Gadget/Bitzer coordinates below are warp
-- landing anchors, not claimed NPC coordinates.  Live indexed entities take
-- precedence at runtime.  Gate coordinates were promoted from exact-index
-- live-entity captures made during the six-client 2026-09-09 canary run.

local function anchor(name, index, menu_id, x, y, z, extra)
    local value = {
        name=name, entity_index=index, menu_id=menu_id,
        x=x, y=y, z=z, radius=7,
        coordinate_semantics='landing_anchor', confidence='medium',
        entity_family=name:match('^(.-) #') or name,
    }
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end

local function gate(name, index, grid, position, target_names)
    local value = {
        name=name, entity_index=index, map_grid=grid,
        target_names=target_names or {name},
        coordinate_semantics=position and 'live_entity_capture'
            or 'live_calibration_required',
        confidence=position and 'high_live_capture'
            or 'high_identity_unknown_coordinate', radius=5,
        entity_family='Gate',
    }
    if position then
        value.x, value.y, value.z = position.x, position.y, position.z
        value.z_tolerance = 12
    end
    return value
end

return {
    device_start = anchor('Diaphanous Device', 817, 1000,
        -836.000061, -20, -178.000015),
    device_a = anchor('Diaphanous Device #A', 818, 1001,
        -460.000031, 96.000008, -150),
    device_b = anchor('Diaphanous Device #B', 819, 1002,
        -344.000031, -20, -150),
    device_c = anchor('Diaphanous Device #C', 820, 1003,
        -460.000031, -136, -150),
    device_d = anchor('Diaphanous Device #D', 821, 1004,
        -576, -20, -150),

    gadget_a = anchor('Diaphanous Gadget #A', 822, 1005,
        -900.000061, 416.000031, -200.000015),
    gadget_b = anchor('Diaphanous Gadget #B', 823, 1006,
        -24.000002, 420.000031, -200.000015),
    gadget_c = anchor('Diaphanous Gadget #C', 824, 1007,
        -20, -456.000031, -200.000015),
    gadget_d = anchor('Diaphanous Gadget #D', 825, 1008,
        -896.000061, -460.000031, -200.000015),
    gadget_shared = anchor('Diaphanous Gadget', 826, 1009,
        624, -620, 100.000008),
    gadget_e = anchor('Diaphanous Gadget #E', 827, 1018, 280, 276, 70),
    gadget_f = anchor('Diaphanous Gadget #F', 828, 1019,
        876.000061, 280, 70),
    gadget_g = anchor('Diaphanous Gadget #G', 829, 1020, 880, -316, 70),
    gadget_h = anchor('Diaphanous Gadget #H', 830, 1021, 284, -320, 70),
    gadget_unknown = anchor('Diaphanous Gadget #?', 831, 1022,
        186.500015, -20, 60.000004),
    aminon_arena = anchor('Aminon arena', 832, 1023,
        184.000015, -660.000061, 100.000008),

    bitzer_a = anchor('Diaphanous Bitzer #A', 833, 1010,
        -460.000031, 35.5, -140),
    bitzer_b = anchor('Diaphanous Bitzer #B', 834, 1011,
        -404.500031, -20, -140),
    bitzer_c = anchor('Diaphanous Bitzer #C', 835, 1012,
        -460.000031, -75.5, -140),
    bitzer_d = anchor('Diaphanous Bitzer #D', 836, 1013,
        -515.5, -20, -140),
    bitzer_e = anchor('Diaphanous Bitzer #E', 837, 1014,
        580, 31.500002, 100.000008),
    bitzer_f = anchor('Diaphanous Bitzer #F', 838, 1015,
        631.5, -20, 100.000008),
    bitzer_g = anchor('Diaphanous Bitzer #G', 839, 1016,
        580, -71.5, 100.000008),
    bitzer_h = anchor('Diaphanous Bitzer #H', 840, 1017,
        528.5, -20, 100.000008),

    gate_a1 = gate('Gate #A1', 865, 'D-4',
        {x=-820, y=203, z=-172}),
    gate_a2 = gate('Gate #A2', 866, 'F-2'),
    gate_a3 = gate('Gate #A3', 882, 'H-2'),
    gate_b1 = gate('Gate #B1', 846, nil,
        {x=-60, y=35, z=-182}),
    gate_b2 = gate('Gate #B2', 847, nil,
        {x=-155, y=-60, z=-172}),
    gate_b3 = gate('Gate #B3', 850, nil,
        {x=-100, y=197, z=-172}),
    gate_b4 = gate('Gate #B4', 854, nil,
        {x=-315, y=20, z=-162}),
    gate_b5 = gate('Gate #B5', 855, nil,
        {x=-315, y=-60, z=-162}),
    gate_b6 = gate('Gate #B6', 877, nil,
        {x=-220, y=5, z=-172}),
    gate_c1 = gate('Gate #C1', 848, nil,
        {x=-60, y=-325, z=-192}),
    gate_c2 = gate('Gate #C2', 849, nil,
        {x=-220, y=-403, z=-182}),
    gate_c3 = gate('Gate #C3', 880, nil,
        {x=-340, y=-283, z=-162}),
    gate_d1 = gate('Gate #D1', 859, nil,
        {x=-683, y=-380, z=-172}),
    gate_d2 = gate('Gate #D2', 861, nil,
        {x=-605, y=-60, z=-162}),
}
