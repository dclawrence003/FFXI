return {
    schema = 1,
    id = 'ambuscade-2026-09-v2-hydra-alluttu',
    version = '1.0.0',
    policy_id = 'pt-ambu2609v2-hydra',
    label = 'Ambuscade September 2026 V2: Alluttu Hydra',
    aliases = {'hydra','alluttu','sep-v2','ambu2609v2'},

    gearswap_adapter = {
        id='ambuscade-2026-09-v2-hydra-alluttu', version='1.0.0',
        controller='hydra', protocol=1,
        actions={'food','clarion','fourth-song','barparalyzra','setup',
            'crusade','divine-emblem','sentinel','pull-flash','flash',
            'provoke','box-step','stun','shield-bash','lead','middle',
            'close','burst','nuke','cancel'},
    },

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR'}},
        Kickpuncher={main_job='DNC', sub_jobs={'WAR'}},
        Barneystinson={main_job='BRD', sub_jobs={'WHM'}},
        Smalls={main_job='RDM', sub_jobs={'WHM'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        skillchain_starter='Kickpuncher',
        skillchain_middle='Tackleberry',
        skillchain_closer='Dolomedes',
        primary_stunner='Kickpuncher', backup_stunner='Tackleberry',
        primary_healer='Smalls', backup_healer='Barneystinson',
        magic_burster='Achoo',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        attackers={'Dolomedes','Tackleberry','Kickpuncher'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={}, target_exclusions={},
    },

    support = {
        cor={rolls={'chaos','samurai'}},
        brd={
            preset='physical', target_source='Tackleberry',
            healbot='cure-na',
        },
        rdm={
            preset='magicboss-protect', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls','Achoo'},
            refresh={'Smalls','Achoo','Barneystinson','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes','Kickpuncher'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
        },
        geo={
            mode='leanrrmanaged', zerg=false,
            indi='Fury', geo='Frailty',
            entrust='Precision', entrustee='Tackleberry',
            combat_entrust_only=false, healbot='cure-na',
        },
        pld={
            preset='manualsc', leader='Dolomedes',
            native_buffs=false, native_tank=false,
        },
        dnc={preset='tankheal', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={
            weapon_mode='DualLastStandRanged', ws='Last Stand', tp=1000,
            automatic=false, disable_native_autows=true,
        },
        Tackleberry={
            weapon_mode='Naegling', ws='Savage Blade', tp=1000,
            automatic=false, disable_native_autows=true,
        },
        Kickpuncher={
            weapon_mode='Tauret', ws='Evisceration', tp=1000,
            automatic=false, disable_native_autows=true,
        },
        Achoo={
            weapon_mode='Maxentius', ws='Black Halo', tp=1000,
            automatic=false, disable_native_autows=true,
        },
    },

    preflight = {
        required_before_combat=true,
        auto_after_apply=30,
        auto_retry_seconds=10,
        max_age_seconds=300,
        members = {
            Dolomedes={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    'Chaos Roll','Samurai Roll',{id=33, label='Haste'},
                    'Phalanx'},
                equipment={
                    main='Rostam', sub='Tauret', range='Death Penalty',
                    ammo='Living Bullet',
                },
                items={{name='Grape Daifuku', minimum=1,
                    bag_group='inventory'}},
                actions={{kind='weaponskill', name='Last Stand'}},
            },
            Tackleberry={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    'Chaos Roll','Samurai Roll',{id=33, label='Haste'},
                    'Phalanx'},
                equipment={main='Naegling', sub='Diamond Aspis'},
                items={{name='Grape Daifuku', minimum=1,
                    bag_group='inventory'}},
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Crusade'},
                    {kind='spell', name='Flash'},
                    {kind='ability', name='Divine Emblem'},
                    {kind='ability', name='Sentinel'},
                    {kind='ability', name='Provoke'},
                    {kind='ability', name='Shield Bash'},
                },
            },
            Kickpuncher={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    'Chaos Roll','Samurai Roll',{id=33, label='Haste'},
                    'Phalanx'},
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                items={{name='Grape Daifuku', minimum=1,
                    bag_group='inventory'}},
                actions={
                    {kind='weaponskill', name='Evisceration'},
                    {kind='ability', name='Box Step'},
                    {kind='ability', name='Violent Flourish'},
                    {kind='ability', name='Curing Waltz V'},
                },
            },
            Barneystinson={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal'},
                actions={
                    {kind='spell', name='Barparalyzra'},
                    {kind='spell', name='Cursna'},
                    {kind='spell', name='Poisona'},
                },
            },
            Smalls={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Thunder IV'},
                    {kind='spell', name='Haste II'},
                    {kind='spell', name='Refresh III'},
                    {kind='spell', name='Phalanx II'},
                    {kind='spell', name='Protect V'},
                    {kind='spell', name='Shell V'},
                    {kind='spell', name='Cursna'},
                    {kind='spell', name='Poisona'},
                },
            },
            Achoo={
                controller={name='hydra', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    {id=549, label='Indi-Fury'},{id=43, label='Refresh'}},
                equipment={
                    main='Maxentius', sub='Sors Shield', range='Dunna',
                },
                actions={
                    {kind='spell', name='Indi-Fury'},
                    {kind='spell', name='Geo-Frailty'},
                    {kind='spell', name='Indi-Precision'},
                    {kind='ability', name='Entrust'},
                    {kind='spell', name='Thunder IV'},
                    {kind='spell', name='Cursna'},
                    {kind='spell', name='Poisona'},
                },
            },
        },
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'Apply //pt use hydra and wait for ACK/PREFLIGHT, position Tackle in front, and put both Kick and Dolo in melee range on safe flanks so stationary PartyCombat can build their TP; nobody may stand in the rear Serpentine Tail arc. Keep all six within Barney song/barspell range for setup coverage, then issue one //pt arm. Movement remains operator-owned and every combat action after arming is automatic.',
        'Use Dolo COR/DNC (or COR/NIN for shadows), Tackle PLD/WAR, Kick DNC/WAR, and Barney, Smalls, and Achoo /WHM. AutoWS2 and native AutoWS stay Off for every coordinated actor.',
        'A fresh six-client ACK and preflight are mandatory. Each attacker must have one Grape Daifuku in Inventory; after //pt arm a persistent bounded heartbeat consumes one only when that character lacks Food, and every physical offense reservation waits for confirmed local Food.',
        'When Clarion Call is ready, Barney opportunistically adds Valor Minuet IV after the generic March, Minuet V, and Madrigal core. Valor Minuet IV and Barparalyzra require successful action results for all six intended recipients; omissions retry finitely and never block the safe three-song plan. GearSwap remains the sole instrument and equipment owner.',
        'Tackle automatically attempts Crusade, Divine Emblem, and Sentinel through bounded nonblocking setup windows, then must produce an exact-ID successful Flash before PartyCombat engages Dolo, Tackle, and Kick. Geo-Frailty, Box Step, Flash, and Provoke are maintained without operator commands.',
        'The packet-confirmed damage loop is Kick Evisceration, Tackle Savage Blade Fragmentation, Dolo Last Stand Light, then Smalls and Achoo Thunder IV. Polar Bulwark switches to magic-only fallback for about 65 seconds and cancels pending fallback nukes before physical combat resumes; Pyric Bulwark suppresses magic and immediately restores physical chains.',
        'Nerve Gas and Polar Bulwark ready packets automatically queue Violent Flourish, with Shield Bash as a timed fallback. Coordinated offense pauses below 85% party HP and yields to cures, Waltzes, Cursna, Poisona, Paralyna, and bounded rebuffing after Trembling or confirmed refresh deadlines.',
        'Victory, claim loss, profile replacement, zone change, any party death, or //pt off cancels all six client queues, stops PartyCombat, releases exact encounter authority, and requires a fresh //pt arm before another attempt.',
    },
}
