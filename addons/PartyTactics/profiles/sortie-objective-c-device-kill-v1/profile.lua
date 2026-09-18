return {
    schema = 1,
    id = 'sortie-objective-c-device-kill-v1',
    version = '1.0.0',
    policy_id = 'pt-sortie-c-device',
    label = 'Sortie onboarding: one Cachaemic at Device C',
    aliases = {'sortiec','cdevice','sortie-c'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN','DRK'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR','BLU','WHM'}},
        Kickpuncher={main_job='DNC', sub_jobs={'WAR','NIN','DRG'}},
        Barneystinson={main_job='BRD', sub_jobs={'WHM','NIN','DRK'}},
        Smalls={main_job='RDM', sub_jobs={'WHM','BLM','DRK'}},
        Achoo={main_job='GEO', sub_jobs={'WHM','BLM','DRK'}},
    },

    roles = {
        route_leader='Dolomedes', tank='Tackleberry',
        manual_puller='Tackleberry', target_caller='Dolomedes',
        primary_healer='Smalls', backup_healer='Barneystinson',
        emergency_healer='Achoo', melee_support='Kickpuncher',
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
        cor={rolls={'chaos','samurai'}},
        brd={
            preset='physical', target_source='Tackleberry',
            healbot='cure-na',
        },
        rdm={
            preset='magicboss-protect', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher',
                'Barneystinson','Smalls','Achoo'},
            refresh={'Smalls','Achoo','Barneystinson','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes','Kickpuncher'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            healbot='cure-na',
        },
        geo={
            mode='leanmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Refresh', entrustee='Tackleberry',
            combat_entrust_only=false, healbot='cure-na',
        },
        pld={preset='manualsc', leader='Dolomedes'},
        dnc={preset='physical', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
        Tackleberry={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Kickpuncher={weapon_mode='Tauret', ws='Evisceration', tp=1000},
        Barneystinson={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'This profile owns only the one normal Cachaemic kill beside Diaphanous Device C. It has no boss, Bhoot, Materialize, chest, navigation, or interaction automation.',
        'Loading is inert. No ACK, check, subjob, buff, equipment, or controller result authorizes combat. Setup differences are diagnostics and every compatible client continues best-effort.',
        'Gather the party at Device C. Tackle manually Flash-pulls one normal Cachaemic to the Device. A Ghost is the preferred low-drama target; a nearby Corse can Charm at low HP. Any normal Cachaemic remains an operator option.',
        'After the foe is physically beside Device C, select that exact foe on Dolo and press Ctrl-P or run //pt force. Stationary PartyCombat faces and engages but never translates a character.',
        'All six damage and support lanes are independent. A delayed or failed roll, song, buff, bubble, debuff, heal, engage, or weapon skill never pauses another lane.',
        'PartyTactics and GearSwap install no input filter for this profile. Manual targets, movement, attacks, ranged attacks, weapon skills, spells, abilities, items, and emergency improvisation remain available while automation is armed.',
        'PartyCombat stops each client when the selected target ends. Press Alt-P after the kill for an explicit party-wide disarm; use //pt off only if you also want the support profile removed.',
        'If the pull links or the target is not positioned correctly, press Alt-P and handle it manually or reset the pull. The profile does not disengage, retarget, or forbid actions on your behalf.',
    },
}
