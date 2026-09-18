-- Version 0.3.0 is deliberately guide-only.  It obtains Keys/Plates A-D and
-- Sheets A-C for a party whose shared progression is zero.  Sheet D is split
-- into its own later combat route.
-- run_transactions only rewind the guide on a fresh entry when their durable
-- all-six reward is absent. They do not claim to sense gate order, Device
-- warps, kills, Materialize, or actor identity; those steps remain manual and
-- fail closed.

local zones = {
    [133]=true, [189]=true, [275]=true,
    [267]=true, [281]=true,
}
local objective_actor = 'Kickpuncher'

return {
    schema=1,
    id='sortie-onboarding-core',
    aliases={'onboarding','unlocks','core'},
    version='0.4.1',
    title='Sortie Onboarding: Core Unlocks',
    content='sortie',
    allowed_zones=zones,
    guide_only=true,
    run_transactions={
        {
            id='b_key_gate_sequence', rewind='b_gates_1_4',
            goal={kind='all_temp_item', item='key_b'},
        },
        {
            id='b_sheet_no_warp_walk', rewind='b_gates_1_4',
            goal={kind='all_temp_item', item='sheet_b'},
        },
        {
            id='c_sheet_actor_sequence', rewind='c_controlled_kill',
            goal={kind='all_temp_item', item='sheet_c'},
        },
    },
    steps={
        {
            id='preentry', area='OUTSIDE',
            completion={kind='all_key_item', item='shiny_plate', auto=true},
            instruction="Get a Shiny Ra'Kaznarian plate on all six, then gather at the Kamihr transposer.",
            warning='GUIDE ONLY: the required C combat profile is not built. Do not spend an entry yet.',
            detail={
                'The five first-timers must speak to Ruspix in Leafallia first.',
                'Bring Silent Oils, Prism Powders, Reraise, food, and inventory space.',
                'Dolo alone opens every spawned chest. Never double-open chests.',
                'Fixed objective actor: Kickpuncher touches Bitzers A, B, and C and performs Device C Materialize.',
                'Composition fact: at least one party member must be able to cast magic at Device A; a full six-person party cannot rely on summoning a trust.',
                'Composition fact: the future C profile must safely isolate and defeat one Cachaemic beside Device C. No job or subjob assignment is approved yet.',
            },
        },
        {
            id='enter', area='ENTRY', completion={kind='all_in_pack', auto=true},
            instruction='Dolo requests entry; move all six through the transposer and wait for them to load.',
            warning='Do not touch a chest while any client is disconnected or still zoning.',
        },
        {
            id='sensor_audit', area='START',
            completion={kind='sensor_quorum', auto=true}, waypoint='device_start',
            instruction='Hold at the starting Device while ExpeditionGuide audits all six temporary-item sets.',
            warning="Shared progression is the intersection across all six, never Dolo's inventory alone.",
        },
        {
            id='a_key', area='A', waypoint='gate_a1',
            objective='key_a', reward={scope='ground_floor',label='Key A chest'},
            completion={kind='all_temp_item', item='key_a', auto=true},
            instruction='From Start go north under Sneak. Open Gate A1, then Dolo opens the brown chest.',
            warning='A enemies detect sound. Do not let two characters open the chest together.',
            detail={'Gate A1 has entity index 865. Targeting it safely calibrates its arrow for later runs.'},
        },
        {
            id='a_plate', area='A', waypoint='device_a',
            objective='plate_a', reward={scope='ground_floor',label='Plate A chest'},
            completion={kind='all_temp_item', item='plate_a', auto=true},
            instruction='Continue through A toward Device A. Cast one harmless spell beside it; Dolo opens the chest.',
            warning='Keep Sneak while traveling. The landing anchor guides only; it does not prove arrival.',
        },
        {
            id='a_sheet', area='A', waypoint='bitzer_a',
            objective='sheet_a', reward={scope='ground_floor',label='Sheet A chest'},
            completion={kind='all_temp_item', item='sheet_a', auto=true},
            instruction=objective_actor .. ' goes down the Device A ramp, removes ALL actual equipment, touches Bitzer A, restores normal equipment, then Dolo opens the chest.',
            warning="Kick's actual equipment slots must be empty; visual lockstyle is not evidence either way. ExpeditionGuide never changes equipment.",
        },
        {
            id='b_gates_1_4', area='B',
            path={'gate_b1','gate_b2','gate_b3','gate_b4'},
            completion={kind='manual'},
            instruction='Walk east through Locked Gate A. Open B1, B2, backtrack to B3, then open B4.',
            warning='STAY ON FOOT for Sheet B. Elementals magic-aggro; apply Invisible away from them.',
            detail={'Keep Kickpuncher on foot from Start until Sheet B is confirmed. Keeping all six on foot is the simple formation rule.'},
        },
        {
            id='b_plate', area='B', waypoint='device_b',
            objective='plate_b', reward={scope='ground_floor',label='Plate B chest'},
            completion={kind='all_temp_item', item='plate_b', auto=true},
            instruction='At Device B, target it and use /hurray. Dolo opens the Plate B chest.',
            warning="Do not select a Device warp on Kickpuncher. Kick's Sheet B eligibility must remain intact.",
        },
        {
            id='b_sheet', area='B', waypoint='bitzer_b',
            objective='sheet_b', reward={scope='ground_floor',label='Sheet B chest'},
            completion={kind='all_temp_item', item='sheet_b', auto=true},
            instruction=objective_actor .. ' descends from Device B and touches Bitzer B after the uninterrupted walk from Start; Dolo opens the chest.',
            warning='If Kick used a Device warp, return Kick to Start and walk the full route again before Kick touches Bitzer B.',
        },
        {
            id='b_key', area='B', path={'gate_b5','gate_b6'},
            objective='key_b', reward={scope='ground_floor',label='Key B chest'},
            completion={kind='all_temp_item', item='key_b', auto=true},
            instruction='From Device B go south through B5, then east and follow the left wall to B6; open both and loot.',
            warning='The Key B chest appears only after B1 through B6 were opened in numerical order.',
        },
        {
            id='c_key', area='C', waypoint='gate_c1',
            objective='key_c', reward={scope='ground_floor',label='Key C chest'},
            completion={kind='all_temp_item', item='key_c', auto=true},
            instruction='From B6 go east then south through Locked Gate B. Open C1 BEFORE anything in C dies; loot.',
            warning="HARD HOLD DAMAGE. Use Sneak plus Invisible and keep everyone's HP white.",
            detail={'Opening C1 or C2 before the first C death awards Key C. Gate C1 index is 848.'},
        },
        {
            id='c_to_device', area='C', path={'gate_c2','gate_c3','device_c'},
            completion={kind='manual'},
            instruction='Open C2 and C3 on the outer route, apply Invisible before Corses, then gather at Device C.',
            warning='Undead detect low HP. Avoid extra pulls; the next objective needs exactly controlled combat.',
        },
        {
            id='c_controlled_kill', area='C', waypoint='device_c',
            objective='plate_c',
            profile='sortie_objective_c_device_kill',
            completion={kind='manual'},
            instruction='Use the planned safe pull: isolate one Cachaemic foe, bring it to Device C, and kill it beside the Device. Advance only after the current-run kill is visually confirmed.',
            warning='BLOCKED FOR LIVE USE until the isolated C-device combat profile passes testing.',
        },
        {
            id='c_plate', area='C', waypoint='device_c',
            objective='plate_c', reward={scope='ground_floor',label='Plate C chest'},
            completion={kind='all_temp_item', item='plate_c', auto=true},
            instruction='Dolo opens the Plate C chest and waits for all-six Plate C evidence.',
            warning='A preexisting Plate C never substitutes for the preceding current-run controlled kill.',
        },
        {
            id='c_materialize', area='C', waypoint='device_c',
            completion={kind='manual'},
            instruction=objective_actor .. ' interacts with Device C and selects Materialize foes. Kick must also touch Bitzer C.',
            warning='Materialize respawns defeated enemies and NMs. Only Kick performs this step.',
        },
        {
            id='c_sheet', area='C', waypoint='bitzer_c',
            objective='sheet_c', reward={scope='ground_floor',label='Sheet C chest'},
            completion={kind='all_temp_item', item='sheet_c', auto=true},
            instruction=objective_actor .. ' descends the ramp and touches Bitzer C; Dolo then opens the Sheet C chest.',
            warning='The same player who selected Materialize must interact with the Bitzer.',
        },
        {
            id='d_key', area='D', path={'gate_d1','gate_d2'},
            objective='key_d', reward={scope='ground_floor',label='Key D chest'},
            timer={kind='interaction_pair', key='d_gate_pair',
                label='D GATES', duration=120, max_distance=7,
                entity_indices={859,861}},
            completion={kind='all_temp_item', item='key_d', auto=true},
            instruction='Enter D under Sneak and Invisible. The planned route is D1 then D2: Dolo opens both within 120 seconds.',
            warning='Fomors detect and daisy-chain link. The HUD timer is attempt-based; only all-six Key D evidence proves success.',
            detail={
                'The objective permits either gate order; D1 then D2 is this route plan.',
                'If an interaction was rejected or the timer is wrong, use //exg timer reset before the valid first interaction.',
            },
        },
        {
            id='d_plate', area='D', waypoint='device_d',
            objective='plate_d', reward={scope='ground_floor',label='Plate D chest'},
            completion={kind='all_temp_item', item='plate_d', auto=true},
            instruction='At Device D, DROP the Obsidian Wing from temporary items; then Dolo opens the chest.',
            warning='DROP IT. DO NOT USE IT. Using the wing ejects that character from Sortie.',
        },
        {
            id='core_complete', area='FINISH',
            completion={kind='all_temp_items', auto=true, items={
                'key_a','key_b','key_c','key_d',
                'plate_a','plate_b','plate_c','plate_d',
                'sheet_a','sheet_b','sheet_c',
            }},
            instruction='After all-six evidence confirms the eleven core unlocks, exit without attempting Sheet D or entering H.',
            warning='Sheet D still requires a dedicated all-Demisang combat run. Do not enter H yet.',
            detail={
                "After leaving, start sortie-postflight-ruspix and take all six to Leafallia for Ruspix's plate.",
                'Sheet D will be its own route after the Demisang-clear profile is proven.',
            },
        },
    },
}
