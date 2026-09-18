return {
    schema=1,
    id='sortie-objective-a-magic-kill-v1',
    version='2.0.0',
    policy_id='pt-sortie-a-magic',
    label='Sortie A: automatic Acuex Liquefaction and Fire kills',
    aliases={'amk','sortie-a-magic','abject-magic'},
    runtime_owns_pull=true,
    -- Explicit recovery profile only. sortie-main-v1 owns automatic Sortie
    -- target routing so this profile can never replace it on a target packet.

    gearswap_adapter={
        id='sortie-objective-a-magic-kill-v1',version='1.1.0',
        controller='sortie-a-magic',protocol=1,
        actions={'flat-blade','red-lotus-blade','fire-v','fire-iv',
            'fire-iii','cancel'},
    },

    members={
        Dolomedes={main_job='COR',sub_jobs={'DNC','NIN','DRK'}},
        Tackleberry={main_job='PLD',sub_jobs={'SCH','WAR','BLU','WHM'}},
        Kickpuncher={main_job='DNC',sub_jobs={'WAR','NIN','DRG'}},
        Barneystinson={main_job='BRD',sub_jobs={'WHM','NIN','DRK'}},
        Smalls={main_job='RDM',sub_jobs={'WHM','BLM','DRK'}},
        Achoo={main_job='GEO',sub_jobs={'WHM','BLM','DRK'}},
    },

    roles={
        route_leader='Dolomedes',target_caller='Dolomedes',
        tank='Tackleberry',manual_puller='Tackleberry',
        chain_opener='Tackleberry',chain_closer='Smalls',
        primary_burster='Smalls',backup_healer='Kickpuncher',
        melee_support='Barneystinson',
    },

    combat={
        leader='Dolomedes',puller='Tackleberry',movement='mobile',
        attackers={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},target_exclusions={},
    },

    support={
        cor={rolls={'chaos','samurai'}},
        brd={preset='physical',target_source='Tackleberry',healbot='off'},
        rdm={
            preset='sortieacuex',target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls'},
            refresh={'Smalls','Achoo','Tackleberry'},
            phalanx={'Tackleberry'},defense={},healbot='off',
        },
        geo={
            mode='leanmanaged',zerg=false,indi='Fury',geo='Frailty',
            entrust='Refresh',entrustee='Smalls',
            combat_entrust_only=false,healbot='off',
        },
        pld={preset='locusbats',leader='Dolomedes'},
        dnc={preset='physical',target_source='Tackleberry'},
    },

    -- The runtime is the only automatic WS owner. Manual actions remain
    -- untouched, but native/AutoWS2 cannot accidentally break the chain.
    offense={
        Dolomedes={weapon_mode='DualSavage',ws='Savage Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Tackleberry={weapon_mode='Naegling',ws='Flat Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Kickpuncher={weapon_mode='Tauret',ws='Evisceration',tp=1000,
            automatic=false,disable_native_autows=true},
        Barneystinson={weapon_mode='Naegling',ws='Savage Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Smalls={weapon_mode='KajaSword',ws='Red Lotus Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Achoo={weapon_mode='Maxentius',ws='Black Halo',tp=1000,
            automatic=false,disable_native_autows=true},
    },

    preflight={
        required_before_combat=false,max_age_seconds=300,
        members={
            Dolomedes={controller={name='sortie-a-magic',protocol=1},actions={}},
            Tackleberry={controller={name='sortie-a-magic',protocol=1},actions={
                {kind='weaponskill',name='Flat Blade'}}},
            Kickpuncher={controller={name='sortie-a-magic',protocol=1},actions={}},
            Barneystinson={controller={name='sortie-a-magic',protocol=1},actions={}},
            Smalls={controller={name='sortie-a-magic',protocol=1},actions={
                {kind='weaponskill',name='Red Lotus Blade'},
                {kind='spell',name='Fire V'},{kind='spell',name='Fire IV'},
                {kind='spell',name='Fire III'}}},
            Achoo={controller={name='sortie-a-magic',protocol=1},actions={}},
        },
    },

    manual_actions={},safety={reraise=true},
    advisories={
        'Explicit recovery profile only; sortie-main-v1 owns automatic target handling. If deliberately loaded, Tackle is the preferred first threat source, but an improvised pull by anyone is accepted immediately.',
        'All six close and burn while Tackle and Smalls build 1000 TP. The runtime then pauses the other four, executes Flat Blade > Red Lotus Blade for Liquefaction, and queues Fire V plus Fire IV/III on Smalls.',
        'Aquaveil is maintained on Smalls so Acuex attacks do not interrupt the burst. Refresh targets and Convert policy are intentionally trimmed to protect his MP and casting time.',
        'Only packet-confirmed WS, Liquefaction, spell damage, and Magic Burst results advance the sequence. A miss or broken chain retries automatically; a low-HP target is held for automatic Fire rather than left in an autoattack deadlock.',
        'A completed target leaves the profile armed for the next Acuex. Manual movement, target changes, actions, and emergency improvisation are never filtered; //pt is recovery only.',
    },
}
