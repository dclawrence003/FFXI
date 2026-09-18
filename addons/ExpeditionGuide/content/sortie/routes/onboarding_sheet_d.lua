-- The run transaction below is a fresh-entry rewind guard only. ExpeditionGuide
-- does not claim to sense or prove the full Demisang clear; that step remains
-- manual and blocked pending its isolated combat profile.
return {
    schema=1,
    id='sortie-onboarding-sheet-d',
    aliases={'sheetd'},
    version='0.4.0',
    title='Sortie Onboarding: Sheet D',
    content='sortie',
    allowed_zones={
        [133]=true, [189]=true, [275]=true,
        [267]=true,
    },
    guide_only=true,
    run_transactions={
        {
            id='d_full_demisang_clear', rewind='clear_demisang',
            goal={kind='all_temp_item', item='sheet_d'},
        },
    },
    steps={
        {
            id='preentry', area='OUTSIDE',
            completion={kind='all_key_item', item='shiny_plate', auto=true},
            instruction="Confirm all six have a Shiny Ra'Kaznarian plate, then gather at the Kamihr transposer.",
            warning='GUIDE ONLY: do not spend an entry until the isolated D-clear combat profile is ready.',
            detail={
                'Composition fact: the future D profile must defeat every regular Demisang; Demisang Deleterious is excluded.',
                'No job or subjob assignment is approved until the isolated combat profile is tested.',
            },
        },
        {
            id='enter', area='ENTRY', completion={kind='all_in_pack', auto=true},
            instruction='Enter Sortie with all six and wait at Start for fresh sensor reports.',
            warning='Dolo alone opens the reward chest.',
        },
        {
            id='audit', area='START',
            completion={kind='all_temp_items', auto=true, items={
                'key_a','key_b','key_c','key_d',
                'plate_a','plate_b','plate_c','plate_d',
                'sheet_a','sheet_b','sheet_c',
            }},
            waypoint='device_start',
            instruction='Hold at Start while all eleven prerequisite traversal items are checked on every client.',
            warning='This step cannot advance unless all six prove Keys A-D, Plates A-D, and Sheets A-C. Any missing unlock means return to the core onboarding route.',
        },
        {
            id='warp_d', area='START', completion={kind='manual'},
            waypoint='device_start',
            instruction='At the starting Device, teleport each character to Diaphanous Device #D and gather all six on its platform.',
            warning='Operate each client deliberately. Do not select a Bitzer or boss Gadget destination.',
            detail={
                'Plate D unlocks Device travel to D.',
                'Advance only after visually confirming all six arrived at Device D.',
            },
        },
        {
            id='clear_demisang', area='D',
            profile='sortie_objective_d_demisang_clear',
            completion={kind='manual'}, waypoint='device_d',
            instruction='From Device D, follow the future calibrated room sweep while the dedicated profile defeats every regular Demisang.',
            warning='BLOCKED: the combat profile and room-by-room sweep path are not yet live-proven. Demisang Deleterious is not required.',
        },
        {
            id='sheet_d', area='D', waypoint='bitzer_d',
            objective='sheet_d', reward={scope='ground_floor',label='Sheet D chest'},
            completion={kind='all_temp_item', item='sheet_d', auto=true},
            instruction='After every regular Demisang is confirmed dead, Dolo touches Bitzer D and opens the chest.',
            warning='Do not descend to H until all six report Sheet D.',
        },
        {
            id='complete', area='FINISH',
            completion={kind='all_temp_items', auto=true, items={
                'key_a','key_b','key_c','key_d',
                'plate_a','plate_b','plate_c','plate_d',
                'sheet_a','sheet_b','sheet_c','sheet_d',
            }},
            instruction='After all-six evidence confirms all twelve ground-floor traversal unlocks, all six may exit.',
            warning='Future routes can safely use Devices A-D and Bitzers A-D.',
        },
    },
}
