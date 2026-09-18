return {
    schema = 1,
    id = 'ambuscade-2026-08-v1-breadwinner',
    version = '1.1.0',
    policy_id = 'pt-ambu2608v1',
    label = 'Ambuscade August 2026 V1: Bozzetto Breadwinner',
    aliases = {'v1','ambuv1','breadwinner','ambuscade-v1'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR','BLU'}},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD', sub_jobs={'WHM'}},
        Smalls={main_job='RDM', sub_jobs={'WHM'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        tank='Tackleberry', primary_healer='Tackleberry',
        backup_healer='Smalls', emergency_healer='Kickpuncher',
        mechanic_duty='Barneystinson', free_look='Barneystinson',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='mobile',
        attackers={'Dolomedes','Tackleberry','Kickpuncher','Smalls','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher','Smalls','Achoo'},
        priority_target='Bozzetto Urchin',
        priority_attackers={'Dolomedes','Kickpuncher'},
        target_exclusions={},
    },

    support = {
        cor={rolls={'chaos','samurai'}},
        brd={preset='ambuscade-v1', target_source='Tackleberry'},
        rdm={
            preset='ambuscade-v1-protect', target_source='Tackleberry',
            haste={'Achoo','Dolomedes','Kickpuncher','Smalls','Tackleberry'},
            refresh={'Smalls','Tackleberry','Achoo','Barneystinson'},
            phalanx={'Tackleberry'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
        },
        geo={
            mode='leanrrmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Wilt', entrustee='Tackleberry',
            combat_entrust_only=false,
        },
        pld={preset='ambuscade-v1', leader='Dolomedes'},
        dnc={preset='ambuscade-v1', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
        Tackleberry={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Kickpuncher={weapon_mode='Tauret', ws='Evisceration', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    safety = {reraise=true},

    advisories = {
        'Tackleberry tanks Breadwinner in the starting corner facing the wall; the damage group attacks from behind.',
        'Barney remains a free-look observer: opening songs, reactive Barspells, Urchin Lullaby, and Housemaker isolation are his priorities.',
        'Smalls opens Stymie + Saboteur + Silence, confirms the result, then applies Paralyze, Dia, and Distract to Breadwinner only.',
        'Dolomedes and Kickpuncher split to Bozzetto Urchins and return to Breadwinner automatically.',
        'Barney, Smalls, and Achoo require /WHM and self-Reraise; Dolo, Tackleberry, and Kickpuncher require Reraise items.',
    },
}
