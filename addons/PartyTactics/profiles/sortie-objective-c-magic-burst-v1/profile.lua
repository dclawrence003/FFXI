return {
    schema = 1,
    id = 'sortie-objective-c-magic-burst-v1',
    version = '1.3.0',
    policy_id = 'pt-sortie-c-mb',
    label = 'Sortie C: automatic Cachaemic Magic Burst credit',
    aliases = {'cmb','sortie-c-mb','cachaemic-mb'},
    runtime_owns_pull = true,
    -- Explicit recovery profile only. sortie-main-v1 owns automatic Sortie
    -- target routing so this profile can never replace it on a target packet.

    -- This adapter accepts short-lived, exact-target action requests. It never
    -- cancels or filters an operator action and is never a combat prerequisite.
    gearswap_adapter = {
        id='sortie-objective-c-magic-burst-v1', version='1.0.0',
        controller='sortie-c-mb', protocol=1,
        actions={'evisceration','savage-blade','thunder','cancel'},
    },

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN','DRK'}},
        Tackleberry={main_job='PLD', sub_jobs={'SCH','WAR','BLU','WHM'}},
        Kickpuncher={main_job='DNC', sub_jobs={'WAR','NIN','DRG'}},
        Barneystinson={main_job='BRD', sub_jobs={'WHM','NIN','DRK'}},
        Smalls={main_job='RDM', sub_jobs={'WHM','BLM','DRK'}},
        Achoo={main_job='GEO', sub_jobs={'WHM','BLM','DRK'}},
    },

    roles = {
        route_leader='Dolomedes', target_caller='Dolomedes',
        manual_puller='Tackleberry',
        chain_opener='Kickpuncher', chain_closer='Dolomedes',
        primary_burster='Achoo', backup_burster='Smalls',
        tank='Tackleberry', primary_healer='Tackleberry',
        backup_healer='Kickpuncher', emergency_healer='Smalls',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='mobile',
        -- Tackle and Barney are configured attackers but deliberately omitted
        -- from broad target synchronization. The runtime directs Tackle first
        -- for the pull; Barney joins only after a real Magic Burst packet.
        attackers={'Dolomedes','Tackleberry','Kickpuncher','Barneystinson'},
        targeters={'Dolomedes','Kickpuncher'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        -- Regain plus Store TP precharges the next exact chain without asking
        -- extra melee swings to consume the objective target's HP.
        cor={rolls={'tactician','samurai'}},
        brd={
            preset='magicboss', target_source='Tackleberry',
            healbot='off',
        },
        -- C credit needs one bounded fallback Thunder, not a two-minute RDM
        -- maintenance carousel. The pinned adapter can still ask Smalls for
        -- that exact spell while routine PartyStart maintenance is suspended.
        rdm={enabled=false},
        geo={
            mode='leanmanaged', zerg=false,
            indi='Refresh', geo='Haste',
            entrust='Refresh', entrustee='Tackleberry',
            combat_entrust_only=false, healbot='off',
        },
        pld={preset='locusbats', leader='Dolomedes'},
        -- Heal-only prevents native Steps, Sambas, Flourishes, and AutoWS from
        -- competing with the exact Evisceration request below.
        dnc={preset='tankheal', target_source='Tackleberry'},
    },

    -- Weapon selection is declarative; this profile's runtime is the only
    -- automatic WS owner. Manual WS commands continue to pass through.
    offense = {
        Dolomedes={
            weapon_mode='DualSavage', ws='Savage Blade', tp=1000,
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
        Barneystinson={
            weapon_mode='Naegling', ws='Savage Blade', tp=1000,
            automatic=false, disable_native_autows=true,
        },
        Smalls={
            weapon_mode='Maxentius', ws='Black Halo', tp=1000,
            automatic=false, disable_native_autows=true,
        },
        Achoo={
            weapon_mode='Maxentius', ws='Black Halo', tp=1000,
            automatic=false, disable_native_autows=true,
        },
    },

    -- Diagnostics only. A missing controller, spell, WS, buff, item, job, or
    -- equipment observation is reported but can never prevent Ctrl-P.
    preflight = {
        required_before_combat=false,
        max_age_seconds=300,
        members = {
            Dolomedes={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='weaponskill',name='Savage Blade'}},
            },
            Tackleberry={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='weaponskill',name='Savage Blade'}},
            },
            Kickpuncher={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='weaponskill',name='Evisceration'}},
            },
            Barneystinson={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='weaponskill',name='Savage Blade'}},
            },
            Smalls={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='spell',name='Thunder'}},
            },
            Achoo={
                controller={name='sortie-c-mb', protocol=1},
                actions={{kind='spell',name='Thunder'}},
            },
        },
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'This profile owns only the Shard C and Metal C condition on normal Cachaemic Skeletons, Ghouls, Corses, and Ghosts. It refuses the Cachaemic Bhoot and every other target.',
        'Explicit recovery profile only; sortie-main-v1 owns automatic target handling. If deliberately loaded, Tackle is preferred for the first hostile action, but any party member may establish the target.',
        'Tactician and Samurai rolls help precharge the exact chain. Dolo and Kick build any remaining TP while Tackle and Barney remain outside automatic target synchronization. At 1000 TP each, Kick opens with Evisceration and Dolo follows after the skillchain delay with Savage Blade for Fragmentation.',
        'Only an observed Fragmentation packet requests Thunder: Achoo is first and Smalls is a bounded fallback. Only an observed party Magic Burst packet releases Tackle and Barney plus the four automatic finisher lanes.',
        'A submitted command is never treated as success. Missing, failed, wrong-actor, wrong-target, or non-Fragmentation results expire and the profile rebuilds the chain. A manual correct Evisceration, Savage Blade, or party Magic Burst is accepted as live evidence.',
        'The sequencing controls only this profile\'s automatic requests. PartyTactics and its GearSwap adapter never filter or cancel manual movement, targeting, attacks, weapon skills, spells, abilities, items, cures, or an improvised recovery.',
        'If the enemy is getting low before credit appears, intervene immediately: stop attacking, cast a manual burst, change tactics, or press Alt-P. The profile warns but does not lock controls or forcibly stop your characters.',
        '//pt arm and Ctrl-P defer to the same Tackle-first runtime. A two-second bounded fallback releases the chain pair if no claim packet arrives, so tank-first behavior cannot deadlock the timer or prevent a manual pull.',
        'A target ending or claim loss cancels only its short-lived work and keeps the route-owned profile armed for the next exact Cachaemic. Alt-P still disarms immediately, and ExpeditionGuide does not fight that manual override. Chest and temporary-item evidence remain authoritative.',
    },
}
