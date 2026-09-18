return {
    schema=1,
    id='sortie-main-v1',
    version='1.2.0',
    policy_id='pt-sortie-main',
    label='Sortie main run: one profile, target-selected recipes',
    aliases={'sortie','sortierun','sortie-main'},

    -- This is a recovery path when ExpeditionGuide was not running at entry.
    -- Once selected, the same profile stays loaded for travel, objectives,
    -- ordinary trash, and bosses; target changes never reload support.
    auto_select={
        zones={[133]=true,[189]=true,[275]=true},
        targets={
            'Cachaemic Skeleton','Cachaemic Ghoul','Cachaemic Corse',
            'Cachaemic Ghost','Cachaemic Bhoot','Skomora',
            'Biune Fire Elemental','Biune Ice Elemental',
            'Biune Air Elemental','Biune Earth Elemental',
            'Biune Thunder Elemental','Biune Water Elemental',
            'Biune Light Elemental','Biune Dark Elemental',
            'Biune Porxie','Biune Umbril','Leshonn',
            'Abject Acuex','Abject Obdella','Ghatjot',
        },
    },

    gearswap_adapter={
        id='sortie-main-v1',version='1.2.0',
        controller='sortie-main',protocol=1,
        actions={
            'savage-blade','evisceration','black-halo',
            'flat-blade','red-lotus-blade','thunder',
            'fire-iv','fire-iii',
            'movement-mode','combat-mode','leshonn-mode',
            'leshonn-wind-mode','leshonn-thunder-mode',
            'acuex-mode','normal-mode','cancel',
        },
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
        route_leader='Dolomedes',tank='Tackleberry',
        manual_puller='Tackleberry',target_caller='Dolomedes',
        primary_healer='Tackleberry',backup_healer='Kickpuncher',
        emergency_healer='Smalls',melee_support='Barneystinson',
    },

    combat={
        leader='Dolomedes',puller='Tackleberry',movement='mobile',
        attackers={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},target_exclusions={},
    },

    -- The initial package is travel-biased. The runtime changes Bolter to
    -- Chaos and removes Mazurka at the first hostile action, then restores
    -- movement support after the encounter truly ends. The RDM/GEO/PLD/DNC
    -- controllers stay loaded for the entire run, so target changes do not
    -- restart their buff rotations.
    support={
        cor={rolls={'bolter','tactician'}},
        -- Travel defaults are also safe before Leshonn's first action. The
        -- runtime changes ordinary encounters to physical/locusbats before it
        -- releases the shared target, while Leshonn retains this no-debuff
        -- BRD package and the defensive PLD helper.
        brd={preset='magicboss',target_source='Tackleberry',healbot='off'},
        rdm={
            -- The persistent Acuex-safe preset retains Aquaveil, Haste,
            -- Refresh, Phalanx, Temper, Convert, and healing while omitting
            -- Dia. A lingering damage-over-time tick therefore cannot steal
            -- an Acuex magic killing blow later in the route.
            preset='sortieacuex',target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls','Achoo'},
            refresh={'Smalls','Achoo','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes'},defense={},healbot='off',
        },
        geo={
            mode='leanmanaged',zerg=false,indi='Fury',geo='Frailty',
            entrust='Refresh',entrustee='Smalls',
            combat_entrust_only=false,healbot='off',
        },
        pld={preset='manualsc',leader='Dolomedes',
            native_buffs=false,native_tank=false},
        dnc={preset='physical',target_source='Tackleberry'},
    },

    -- One runtime owns every automatic WS so an objective recipe cannot race
    -- a leftover AutoWS2 setting from another fight. Autoattacks, targeting,
    -- movement, and every manual action remain ordinary game controls.
    offense={
        Dolomedes={weapon_mode='DualSavage',ws='Savage Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Tackleberry={weapon_mode='Naegling',ws='Savage Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Kickpuncher={weapon_mode='Tauret',ws='Evisceration',tp=1000,
            automatic=false,disable_native_autows=true},
        Barneystinson={weapon_mode='Naegling',ws='Savage Blade',tp=1000,
            automatic=false,disable_native_autows=true},
        Smalls={weapon_mode='Maxentius',ws='Black Halo',tp=1000,
            automatic=false,disable_native_autows=true},
        Achoo={weapon_mode='Maxentius',ws='Black Halo',tp=1000,
            automatic=false,disable_native_autows=true},
    },

    preflight={
        required_before_combat=false,max_age_seconds=300,
        members={
            Dolomedes={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Savage Blade'}}},
            Tackleberry={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Savage Blade'},
                {kind='weaponskill',name='Flat Blade'}}},
            Kickpuncher={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Evisceration'}}},
            Barneystinson={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Savage Blade'},
                {kind='spell',name='Chocobo Mazurka'}}},
            Smalls={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Black Halo'},
                {kind='weaponskill',name='Red Lotus Blade'},
                {kind='spell',name='Thunder'},
                {kind='spell',name='Fire IV'},
                {kind='spell',name='Fire III'}}},
            Achoo={controller={name='sortie-main',protocol=1},actions={
                {kind='weaponskill',name='Black Halo'},
                {kind='spell',name='Thunder'}}},
        },
    },

    manual_actions={},safety={reraise=true},
    advisories={
        'Normal operation is one command surface: ExpeditionGuide loads sortie-main-v1 once after entry. Engaging another target changes only the fight recipe; it never reloads the profile or restarts the support package.',
        'Tackleberry is the preferred puller. His Flash or first hostile action becomes the shared target immediately, but a hostile action by any configured party member is accepted the same way. No character is a gate.',
        'Ordinary targets and bosses use full-party mobile melee. Only Cachaemic Skeletons and Ghouls repeat Evisceration > Savage Blade > Thunder until one Magic Burst is observed, then all six spend TP. Bhoot and other interruptions use ordinary damage. Biunes simply burn and spend TP; no melee pause is used.',
        'Acuex use one bounded finish: all six build TP, four attackers stop for Flat Blade > Red Lotus Blade, the remaining two stop after Liquefaction, and Smalls uses Fire IV/III for the magic killing blow. A failed chain resumes the exact stopped members once before retrying; no continuous stop/release loop exists.',
        'Between encounters the same profile restores Bolter plus Tactician and requests Chocobo Mazurka. Combat restores Chaos plus Samurai and removes Mazurka without restarting RDM, GEO, PLD, or DNC support.',
        'Leshonn is a dedicated internal recipe, not generic burn: BRD uses a zero-debuff preset, PLD native buffs/tank automation are off so Flash and Sentinel cannot fire automatically, GEO keeps Fury/Frailty, and DNC keeps Box Step. Manual actions are never filtered.',
        'Only Tackle faces Leshonn from the front. Dolo, Kick, Barney, Smalls, and Achoo must be placed behind or on a rear flank before Tackle engages; this is an operator positioning instruction and never a combat gate.',
        'Kick melees and uses Box Step but holds automatic WS on Leshonn. Savage Blade and Black Halo are the only automatic boss lanes, preventing Wind/Lightning-aligned skillchain damage. Confirmed Wind TP moves permit conditional Last Resort only for a character actually on /DRK.',
        'Alt-P or //pt disarm remains an operator override. Automatic target observation records the target but never re-arms a profile you deliberately disarmed.',
    },
}
