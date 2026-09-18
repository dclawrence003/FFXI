-- Focused live recovery route for a party that completed core onboarding but
-- missed Key B by opening a B gate out of order.  It remains entirely
-- operator-driven and never moves, interacts, or arms combat.

local zones = {
    [133]=true, [189]=true, [275]=true,
    [267]=true, [281]=true,
}

return {
    schema=1,
    id='sortie-key-b-recovery-live',
    aliases={},
    version='1.0.0',
    title='Sortie Recovery: Key B',
    content='sortie',
    allowed_zones=zones,
    guide_only=false,
    run_transactions={
        {
            id='key_b_gate_sequence', rewind='b_gates_1_4',
            goal={kind='all_temp_item', item='key_b'},
        },
    },
    steps={
        {
            id='preentry', area='OUTSIDE',
            completion={kind='all_key_item', item='shiny_plate', auto=true},
            instruction='Wait for a Shiny Ra\'Kaznarian plate on all six, then gather at the Kamihr transposer.',
            warning='This focused entry is only for recovering the missing all-six Key B unlock. Starting the guide never requests entry.',
        },
        {
            id='enter', area='ENTRY', completion={kind='all_in_pack', auto=true},
            instruction='Dolo requests entry manually; move all six through the transposer and wait for them to load.',
            warning='Do not touch a chest while any client is disconnected or zoning.',
        },
        {
            id='sensor_audit', area='START', waypoint='device_start',
            completion={kind='sensor_quorum', auto=true},
            instruction='Hold at the starting Device while ExpeditionGuide audits all six clients.',
            warning='The route observes evidence only; move and improvise manually whenever needed.',
        },
        {
            id='key_a_access', area='A',
            completion={kind='all_temp_item', item='key_a', auto=true},
            instruction='Confirm all six have Key A access, then travel on foot through A to Locked Gate A and enter B.',
            warning='If Key A evidence is unexpectedly missing, investigate or use //exg skip after verifying that Dolo can open Locked Gate A.',
        },
        {
            id='b_gates_1_4', area='B',
            path={'gate_b1','gate_b2','gate_b3','gate_b4'},
            completion={kind='manual'},
            instruction='Follow the HUD gate arrow in exact order B1 > B2 > B3 > B4. DO NOT open nearby B3 first: take the long outer route to far-east B1, continue to B2, backtrack to B3, then return to B4 by Device B. Use //exg next only after B4.',
            warning='Confirm the target name matches the current HUD point before interacting. One out-of-order gate forfeits Key B for the entire run.',
            detail={'The arrow is a direct bearing, not a collision-free path. Follow corridors without interacting with any other numbered B gate.'},
        },
        {
            id='b_key', area='B', path={'gate_b5','gate_b6'},
            objective='key_b', reward={scope='ground_floor',label='Key B chest'},
            completion={kind='all_temp_item', item='key_b', auto=true},
            instruction='From B4 go south to B5, then follow the HUD arrow and left-wall corridor to B6. Confirm each target number before opening it. Dolo opens the Key B chest after B6.',
            warning='Required full order: B1 > B2 > B3 > B4 > B5 > B6. If no chest appears after B6, do not wait; use //exg skip and salvage the run freely.',
        },
        {
            id='complete', area='FINISH',
            completion={kind='all_temp_item', item='key_b', auto=true},
            instruction='All-six Key B evidence is confirmed. Exit now or continue with any manually chosen Sortie objectives.',
            warning='The recovery route is complete and imposes no restriction on the rest of the run.',
        },
    },
}
