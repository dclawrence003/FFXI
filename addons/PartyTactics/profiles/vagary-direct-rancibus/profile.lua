return {
    schema = 1,
    id = 'vagary-direct-rancibus',
    version = '1.1.0',
    policy_id = 'pt-vagary-rancibus',
    label = 'Alternative Vagary: direct Rancibus clear',
    aliases = {'rancibus','vagary-rancibus','direct-rancibus'},

    -- Cooperative adapter: short exact-ID requests only. It never filters or
    -- cancels player input, and no request is a prerequisite for another.
    gearswap_adapter = {
        id='vagary-direct-rancibus', version='1.1.0',
        controller='rancibus', protocol=1,
        actions={'barwatera-prepare','barsilencera-prepare','crusade',
            'barwatera-recover','barsilencera-recover','sentinel',
            'rampart','flash','provoke','shoot','stun',
            'shield-bash','no-foot-rise','box-step','lead','middle','close',
            'dia3','addle2','slow2',
            'paralyze2','geo-frailty','cancel'},
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
        ranged_damage='Dolomedes', melee_damage='Kickpuncher',
        primary_stunner='Kickpuncher', backup_stunner='Tackleberry',
        primary_healer='Smalls', backup_healer='Barneystinson',
        emergency_healer='Achoo',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        -- PartyCombat may maintain only the two frontline melee characters.
        -- Dolo gets one local engage request from the runtime, and support
        -- characters are never target-synced.
        attackers={'Tackleberry','Kickpuncher'},
        targeters={'Tackleberry','Kickpuncher'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        -- Magus replaces the faster Samurai roll for the first clear. The
        -- direct battlefield costs six pearls and Rancibus's principal threat
        -- is repeated Water magic, not a damage check.
        cor={rolls={'chaos','magus'}},
        brd={
            preset='magicboss', target_source='Tackleberry',
            healbot='cure-na',
        },
        rdm={
            preset='magicboss-protect', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls','Achoo'},
            refresh={'Smalls','Achoo','Barneystinson','Tackleberry'},
            phalanx={'Tackleberry','Kickpuncher'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            healbot='cure-na',
        },
        geo={
            mode='leanrrmanaged', zerg=false,
            indi='Refresh', geo='Frailty',
            entrust='Fend', entrustee='Kickpuncher',
            combat_entrust_only=false, healbot='cure-na',
        },
        pld={preset='manualsc', leader='Dolomedes'},
        -- Heal-only prevents the frozen DNC helper from ever owning AutoWS2,
        -- Steps, or Flourishes. The private adapter owns exact Box Step,
        -- Violent Flourish, and every chain WS for this encounter.
        dnc={preset='tankheal', target_source='Tackleberry'},
    },

    -- These settings choose weapons and keep legacy automatic WS engines from
    -- competing. They do not block manual weaponskills or abilities.
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
        required_before_combat=false,
        zone=277,
        max_age_seconds=300,
        all = {
            items={{name='Echo Drops', minimum=12,
                bag_group='inventory'}},
        },
        members = {
            Dolomedes={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','March',
                    'Minne','Ballad','Chaos Roll',"Magus's Roll",
                    {id=33, label='Haste'}},
                equipment={
                    main='Rostam', sub='Tauret', range='Death Penalty',
                    ammo='Living Bullet',
                },
                items={
                    {name='Living Bullet', minimum=48, warn_below=99,
                        bag_group='equippable'},
                },
                actions={{kind='weaponskill', name='Last Stand'}},
            },
            Tackleberry={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','March',
                    'Minne','Chaos Roll',"Magus's Roll",
                    {id=33, label='Haste'},'Phalanx'},
                equipment={main='Naegling', sub='Diamond Aspis'},
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Crusade'},
                    {kind='spell', name='Flash'},
                    {kind='ability', name='Sentinel'},
                    {kind='ability', name='Rampart'},
                    {kind='ability', name='Shield Bash'},
                    {kind='ability', name='Provoke'},
                },
            },
            Kickpuncher={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','March',
                    'Minne','Chaos Roll',"Magus's Roll",
                    {id=33, label='Haste'},'Phalanx'},
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                actions={
                    {kind='weaponskill', name='Evisceration'},
                    {kind='ability', name='Violent Flourish'},
                    {kind='ability', name='No Foot Rise'},
                    {kind='ability', name='Box Step'},
                    {kind='ability', name='Curing Waltz V'},
                    {kind='ability', name='Healing Waltz'},
                },
            },
            Barneystinson={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','March',
                    'Minne','Ballad'},
                actions={
                    {kind='spell', name='Victory March'},
                    {kind='spell', name="Knight's Minne V"},
                    {kind='spell', name="Mage's Ballad III"},
                    {kind='spell', name='Barwatera'},
                    {kind='spell', name='Barsilencera'},
                    {kind='spell', name='Poisona'},
                    {kind='spell', name='Silena'},
                    {kind='spell', name='Viruna'},
                    {kind='spell', name='Erase'},
                    {kind='spell', name='Reraise'},
                },
            },
            Smalls={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','Ballad',
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Haste II'},
                    {kind='spell', name='Refresh III'},
                    {kind='spell', name='Phalanx II'},
                    {kind='spell', name='Protect V'},
                    {kind='spell', name='Shell V'},
                    {kind='spell', name='Dia III'},
                    {kind='spell', name='Addle II'},
                    {kind='spell', name='Slow II'},
                    {kind='spell', name='Paralyze II'},
                    {kind='spell', name='Poisona'},
                    {kind='spell', name='Silena'},
                    {kind='spell', name='Viruna'},
                    {kind='spell', name='Erase'},
                },
            },
            Achoo={
                controller={name='rancibus', protocol=1},
                buffs={'Protect','Shell','Barwater','Barsilence','Ballad',
                    {id=541, label='Indi-Refresh'},
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                equipment={
                    main='Maxentius', sub='Sors Shield', range='Dunna',
                },
                actions={
                    {kind='spell', name='Indi-Refresh'},
                    {kind='spell', name='Geo-Frailty'},
                    {kind='spell', name='Indi-Fend'},
                    {kind='ability', name='Entrust'},
                    {kind='spell', name='Poisona'},
                    {kind='spell', name='Silena'},
                    {kind='spell', name='Viruna'},
                    {kind='spell', name='Erase'},
                    {kind='spell', name='Reraise'},
                },
            },
        },
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'This is only the 1-6 player, 30-minute Vagary: Rancibus battlefield in Ra\'Kaznar Turris. Every member must complete Watery Grave and obtain a Prototype sigil pearl before entry; all six pearls are consumed when the party enters. The profile intentionally contains no Brash Gate columns, waves, adds, or proc logic.',
        'Use Dolo COR/DNC or COR/NIN, Tackle PLD/WAR, Kick DNC/WAR, and Barney, Smalls, and Achoo /WHM. Every character needs 12 Echo Drops in Inventory. Dolo also needs Death Penalty and at least 48 Living Bullets accessible to GearSwap.',
        'Loading the profile is inert. Position everyone first, then use //pt arm. Arm starts immediately: preflight and controller checks are advisory and there is no PASS, ACK, Flash, buff, or setup prerequisite.',
        'Arm sends one best-effort Flash pull while preparation proceeds independently. A missed Flash is not retried as a gate and never stops melee, ranged attacks, weaponskills, debuffs, Geo-Frailty, Barspells, or manual input.',
        'PartyCombat controls only Tackle and Kick. Dolo receives one local exact-ID engage request and then independently alternates ranged attacks with Last Stand based on TP. Barney, Smalls, and Achoo are never target-synced.',
        'All three weaponskill lanes are independent: Kick uses Evisceration, Tackle uses Savage Blade, and Dolo uses Last Stand whenever each is ready. There is no ordered skillchain transaction, party-HP hold, recovery hold, or packet-confirmation gate.',
        'The adapter never installs pretarget or precast filters. Manual target changes, weaponskills, abilities, spells, ranged attacks, and emergency reactions always pass through even while automation is armed.',
        'Use //pt disarm to stop PartyTactics requests and PartyCombat without disabling manual controls. Re-arm whenever you want best-effort automation to resume.',
        'Do not use Leaden Salute, Water damage, or Dark damage. Rancibus takes full physical/ranged damage, but only 15% Water and 5% Dark. Its visible HP gauge is not trusted, so the runtime uses no HP-percentage phase or kill assumption.',
    },
}
