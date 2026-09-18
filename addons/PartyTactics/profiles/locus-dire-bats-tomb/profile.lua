return {
    schema = 1,
    id = 'locus-dire-bats-tomb',
    version = '1.3.0',
    policy_id = 'pt-locus-bats',
    label = "Locus Dire Bats: King Ranperre's Tomb stationary camp",
    aliases = {'locus','locusbats','direbats','tombbats','ranperre'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR','BLU'}},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD'},
        Smalls={main_job='RDM'},
        Achoo={main_job='GEO'},
    },

    roles = {
        tank='Tackleberry', primary_healer='Tackleberry',
        backup_healer='Smalls', emergency_healer='Kickpuncher',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        attackers={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'corsair','samurai'}},
        brd={preset='locusbats', target_source='Tackleberry'},
        rdm={
            preset='locusbats-protect', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher',
                'Barneystinson','Smalls','Achoo'},
            refresh={'Smalls','Tackleberry'},
            phalanx={'Tackleberry'},
            defense={'Tackleberry','Dolomedes','Kickpuncher',
                'Barneystinson','Smalls','Achoo'},
        },
        geo={
            mode='leanmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Refresh', entrustee='Tackleberry',
            combat_entrust_only=false,
        },
        pld={preset='locusbats', leader='Dolomedes'},
        dnc={preset='locusbats', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
        Tackleberry={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Kickpuncher={weapon_mode='Tauret', ws='Evisceration', tp=1000},
        Barneystinson={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    easyfarm = {
        character='Tackleberry', expected_target='Locus Dire Bat',
        artifact='easyfarm/Tackleberry-Locus-Dire-Bats-Stationary.eup',
        detection_distance=18, pull_action='Flash', pull_distance=20,
        note='Load the profile-owned EasyFarm artifact. PartyTactics validates its declaration but never rewrites or starts EasyFarm.',
    },

    advisories = {
        'Stationary combat is strict: PartyCombat engages and faces but never approaches.',
        "Load Tackleberry-Locus-Dire-Bats-Stationary.eup in EasyFarm: exact target Locus Dire Bat, 18-yalm detection, 20-yalm Flash action, approach Off.",
        'Corsair and Samurai rolls prioritize exemplar points and 1000-TP weapon skills.',
        'Barney uses the reviewed Sustain preset: March, Ballad III, Madrigal, Barblizzara, and Elegy.',
        'Smalls opens with party Protect, intentionally omits Shell, then applies MP-reserved Distract before Dia.',
        'Achoo maintains Indi-Fury immediately, entrusted Indi-Refresh out of combat, and Geo-Frailty after engagement.',
        'Kickpuncher uses Haste Samba, Box Step, and Flourishes only after PartyCombat is armed and DNC is engaged.',
    },
}
