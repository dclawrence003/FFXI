return {
    schema = 1,
    id = 'sortie-boss-ghatjot-v1',
    version = '1.2.0',
    policy_id = 'pt-sortie-ghatjot',
    label = 'Sortie training boss A: Ghatjot',
    aliases = {'ghatjot','sortie-ghatjot','boss-a'},
    runtime_owns_pull = true,
    -- Explicit recovery profile only. sortie-main-v1 owns automatic Sortie
    -- target routing so this profile can never replace it on a target packet.

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN','DRK'}},
        Tackleberry={main_job='PLD', sub_jobs={'SCH','WAR','BLU','WHM'}},
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
        leader='Dolomedes', puller='Tackleberry', movement='mobile',
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
            preset='sortiemelee', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls'},
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
        Kickpuncher={weapon_mode='Tauret', ws='Dancing Edge', tp=1000},
        Barneystinson={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'This is the first conservative Ghatjot training profile for the actual Dolomedes party. It requires none of Umbra\'s listed REMA or Prime weapons: every selected weapon mode and weapon skill was verified in the six current inventories and GearSwap files.',
        'A direct load remains inert unless "armed" is requested. The live route loads and arms automatically. There is no preflight, ACK, equipment, subjob, buff, controller, or mechanic gate; differences remain diagnostics only and Alt-P stops immediately.',
        'Bring Ra\'Kaznar Shard A and, for this learning run, Metal A. Metal A converts Taint to removable Poison. Smalls keeps status removal active and Kick retains TP-funded Healing Waltz backup; remove Poison promptly every time.',
        'DO NOT deal Water damage. Do not use Water spells, Water Shot, Leaden Salute, or a Distortion/Darkness skillchain. Ghatjot absorbs Water and the absorption can amplify its next TP move.',
        'The automatic weapon-skill mix is limited to Savage Blade, Dancing Edge, and Black Halo. Kick knows Dancing Edge, and its reviewed pairings avoid the forbidden Water-aligned Distortion and Darkness results while restoring his missing offense.',
        'Explicit recovery profile only; sortie-main-v1 owns automatic target handling. If deliberately loaded, Tackle takes first threat and all six close automatically. Keep Ghatjot facing away from the party.',
        'Tackleberry uses the sustained locusbats PLD policy for Provoke, Flash, Crusade, Sentinel, Warcry, Chivalry, and Majesty healing. PLD/WAR is preferred for this first proof, but an accepted fallback subjob never blocks activation or manual play.',
        'Smalls uses the trimmed sortiemelee rotation: four Hastes, three Refreshes, two Phalanxes, Dia, Aquaveil, and a 30% Convert threshold. Transitioning profiles preserves live timers instead of recasting the entire package.',
        'Umbra\'s Light Shot, Fire Shot, Hot Shot, and Dia III ideas remain useful expert context, but Hot Shot is deliberately not automated in version 1 because an unscheduled Transfixion into Scission can produce Water-aligned Distortion.',
        '//pt arm, Ctrl-P, and route-owned arming all defer to this same Tackle-first runtime. If positioning, poison recovery, hate, or damage goes wrong, reposition, retarget, fight manually, or stop. PartyTactics and GearSwap install no input filter; movement, targeting, spells, abilities, items, cures, and recovery always remain yours.',
    },
}
