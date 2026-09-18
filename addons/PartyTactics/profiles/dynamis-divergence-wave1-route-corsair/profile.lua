return {
    schema = 1,
    id = 'dynamis-divergence-wave1-route-corsair',
    version = '1.2.0',
    policy_id = 'pt-ddw1-route',
    label = 'Dynamis-D Wave 1 route: COR statue plinking only',
    aliases = {'ddw1route','dyna-w1-route','dynamis-w1-route'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR','BLU'}},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD'},
        Smalls={main_job='RDM'},
        Achoo={main_job='GEO'},
    },

    roles = {
        route_leader='Dolomedes', statue_puller='Dolomedes',
        statue_finisher='Dolomedes', optional_acumen='Achoo',
    },

    combat = {
        -- Engage/face at the operator's ranged position; never run Dolo into
        -- melee and risk a physical hit before the one-shot Leaden Salute.
        leader='Dolomedes', puller='Dolomedes', movement='stationary',
        attackers={'Dolomedes'},
        targeters={'Dolomedes'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'tactician','wizard'}},
        brd={enabled=false},
        rdm={enabled=false},
        geo={enabled=false},
        pld={enabled=false},
        dnc={enabled=false},
    },

    offense = {
        Dolomedes={
            weapon_mode='DualLeaden', ws='Leaden Salute', tp=1500,
        },
    },

    manual_actions = {
        acumen={
            character='Achoo', adapter='typed-action',
            kind='cast', name='Indi-Acumen', target='<me>',
        },
    },

    advisories = {
        'This route profile makes Dolo the only targeter and attacker; every other support and AutoWS controller is explicitly Off.',
        'Pause EasyFarm before entry and manage FastFollow/positions manually; both tools remain user-owned. Keep the five followers clear of statue proximity aggro.',
        'Manually position Dolo outside melee but inside Leaden range with the intended statue selected. At about 1500 TP use //pt force; it arms, faces, and engages without translating, then AutoWS2 fires Leaden Salute.',
        'Optional: use //pt acumen while Achoo is positioned on Dolo. It is a one-shot GearSwap spell request and does not enable GEO automation.',
        'Use //pt disarm after each statue and before moving or selecting another target.',
        'At the Wave 1 boss camp, switch with //pt use ddw1boss. The six-client barrier leaves the boss profile unarmed.',
    },
}
