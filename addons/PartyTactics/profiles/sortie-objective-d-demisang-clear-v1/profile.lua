return {
    schema = 1,
    id = 'sortie-objective-d-demisang-clear-v1',
    version = '1.1.0',
    policy_id = 'pt-sortie-d-demisang',
    label = 'Sortie Sheet D canary: regular Demisang sweep',
    aliases = {'sortied','demisang','sheetd-clear'},

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
        primary_healer='Tackleberry', backup_healer='Kickpuncher',
        emergency_healer='Smalls', melee_support='Barneystinson',
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
            healbot='off',
        },
        rdm={
            preset='locusbats', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher',
                'Barneystinson','Smalls','Achoo'},
            refresh={'Smalls','Achoo','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes'},
            defense={},
            healbot='off',
        },
        geo={
            mode='leanmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Refresh', entrustee='Tackleberry',
            combat_entrust_only=false, healbot='off',
        },
        pld={preset='locusbats', leader='Dolomedes'},
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
        'This is the post-run v1.1 helper for the regular Demisang clear in sector D. ExpeditionGuide owns route display; this profile does not move, count enemies, interact with Bitzer D, or open the Sheet D chest.',
        'Loading is inert. No ACK, check, subjob, buff, equipment, or controller result authorizes combat. Setup differences are diagnostics and every compatible client continues best-effort.',
        'The profile has no Demisang-name filter. Select an exact regular Demisang manually on Dolo. Demisang Deleterious is not required for Sheet D; avoid it unless you deliberately choose to improvise.',
        'Use a controlled sweep. Position the party manually, let Tackle establish the pull, select one intended regular Demisang on Dolo, then press Ctrl-P or run //pt force. Stationary PartyCombat faces and engages but never translates a character.',
        'Linked enemies are a live operator problem, not a permission failure. Retarget and press Ctrl-P again, fight manually, reposition, or press Alt-P at any time. Nothing in this profile suppresses those choices.',
        'All six damage and support lanes are independent. A delayed or failed roll, song, buff, bubble, debuff, heal, engage, or weapon skill never pauses another lane.',
        'The first live run left Smalls at or below 20% MP for about half the instance despite five Converts. Routine HealBot cures are therefore consolidated onto Tackleberry\'s Majesty lane; Kickpuncher retains TP-funded emergency Waltzes and Smalls retains native emergency cures plus status removal.',
        'Barneystinson and Achoo no longer duplicate routine cures. Smalls drops the repeated six-person Protect/Shell cycle, keeps Haste II and high-value Refresh III, and uses bounded Distract/Dia so saved casting time and MP become melee damage.',
        'Tackleberry uses the sustained locusbats PLD policy for Provoke, Flash, Sentinel, Warcry, Chivalry, and Majesty healing. This improves opening and sustained enmity without preventing Dolomedes or any other character from acting manually.',
        'PartyTactics and GearSwap install no input filter for this profile. Manual targets, movement, attacks, ranged attacks, weapon skills, spells, abilities, items, heals, and emergency recovery remain available while automation is armed.',
        'Key B is already complete and this profile has no Key B phase. The next run goes directly to Device D for the full regular-Demisang sweep; if time or conditions force a change, stop, retarget, or improvise freely.',
    },
}
