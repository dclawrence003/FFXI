return {
    schema = 1,
    id = 'limbus-119-stationary',
    version = '1.2.0',
    policy_id = 'pt-limbus119',
    label = 'Limbus 119: stationary Flash-pull floor clearing',
    aliases = {'limbus','lim','limbus119','limbus-stationary'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR','BLU'}},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD'},
        Smalls={main_job='RDM'},
        Achoo={main_job='GEO'},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        primary_healer='Tackleberry', backup_healer='Smalls',
        emergency_healer='Kickpuncher', manual_crowd_control='Barneystinson',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        attackers={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},
        target_exclusions={'elemental'},
    },

    support = {
        cor={rolls={'chaos','samurai'}},
        brd={preset='limbus', target_source='Tackleberry'},
        rdm={
            preset='limbus-protect', target_source='Tackleberry',
            haste={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            refresh={'Smalls','Tackleberry','Achoo','Barneystinson'},
            phalanx={'Tackleberry'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
        },
        geo={
            mode='leanmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Refresh', entrustee='Tackleberry',
            combat_entrust_only=false,
        },
        pld={preset='limbus', leader='Dolomedes'},
        dnc={preset='limbus', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
        Tackleberry={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Kickpuncher={weapon_mode='Tauret', ws='Evisceration', tp=1000},
        Barneystinson={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    manual_actions = {
        sleep={character='Barneystinson', adapter='brd-pack-sleep'},
    },

    easyfarm = {
        character='Tackleberry',
        artifact='easyfarm/Tackleberry-Limbus-119-Stationary.eup',
        detection_distance=18, pull_action='Flash', pull_distance=20,
        note='Load the profile-owned Limbus artifact. It contains only the reviewed Apollyon/Temenos allowlist, retains the whole-word Elemental ignore rule, and never shares Locus or XP-camp targets.',
    },

    advisories = {
        'The entire party is planted. Tackleberry is the Flash puller and target source.',
        'Smalls selectively Silences observed casters and one stalled pull through the reviewed Limbus RDM controller.',
        'Use //pt sleep for one CC-priority Lullaby from Barney; repeated presses do not queue duplicates.',
        'Kickpuncher begins Samba, Steps, and Flourishes only after PartyCombat is armed and she is engaged.',
        'Load Tackleberry-Limbus-119-Stationary.eup rather than a shared XP-camp file. Pause EasyFarm before changing floors; if another route needs more names, clone a new profile-owned artifact and review that allowlist explicitly.',
    },
}
