return {
    schema = 1,
    id = 'locus-dire-bats-tomb-signet',
    version = '1.8.1',
    policy_id = 'pt-locus-bats-signet',
    label = "Locus Dire Bats: sustained Signet and Jubilee Ring camp",
    aliases = {'locusbats-signet','locus-signet','signetbats'},

    -- This adapter owns the Signet/Jubilee/LocusPuller lifecycle, the bounded
    -- PLD first-hit lane, and this profile's low-frequency PLD sustain lane.
    -- Shared support helpers remain frozen and GearSwap remains the sole
    -- equipment owner.
    gearswap_adapter = {
        id='locus-dire-bats-tomb-signet', version='1.8.1',
        controller='locus-signet', protocol=2,
        lifecycle_authorization=true,
        -- PartyTactics invokes these exact local fences for a validated stop,
        -- local unload, or different-profile replacement. They do not depend
        -- on GearSwap being present and therefore cover its reload gap.
        lifecycle_stop_fences={
            ['*']='sk stoppt',
            Dolomedes='jk stoppt',
            Tackleberry='lp retirept',
        },
        actions={'operator','suspend','resume','opener-arm','opener-release',
            'companion-ready','keeper-instance'},
    },

    members = {
        Dolomedes={main_job='COR'},
        Tackleberry={main_job='PLD'},
        Kickpuncher={main_job='DNC'},
        Barneystinson={main_job='BRD'},
        Smalls={main_job='RDM'},
        Achoo={main_job='GEO'},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        primary_healer='Tackleberry', backup_healer='Smalls',
        emergency_healer='Kickpuncher',
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

    -- BRD/RDM/GEO/DNC retain the reviewed support policies used by ordinary
    -- `//pt locus`. PLD is off here because its profile-specific sustain lane
    -- lives only in the pinned adapter; no shared helper is changed.
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
        -- The pinned adapter owns this profile's 65/70/55 Majesty cure policy.
        -- Keep the frozen shared PLD helper off so ordinary Locus retains its
        -- historical thresholds. Native buffs stay active, while AutoTank is
        -- disabled so LocusPuller remains the sole Flash owner.
        pld={preset='off', leader='Dolomedes', native_tank=false},
        dnc={preset='locusbats', target_source='Tackleberry'},
    },

    offense = {
        -- DualEvis uses the reviewed Tauret/Gleti's Knife pair and its native
        -- Evisceration WS. /DNC or /NIN enables the offhand; /THF does not.
        Dolomedes={weapon_mode='DualEvis', ws='Evisceration', tp=1000},
        Tackleberry={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Kickpuncher={weapon_mode='Tauret', ws='Evisceration', tp=1000},
        Barneystinson={weapon_mode='Naegling', ws='Savage Blade', tp=1000},
        Smalls={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
        Achoo={weapon_mode='Maxentius', ws='Black Halo', tp=1000},
    },

    -- Diagnostics only. Missing items or a missing adapter are visible through
    -- `//pt check` but never prevent Ctrl-P, //pt arm, manual actions, or a
    -- current fight from continuing.
    preflight = {
        required_before_combat=false,
        zone=190,
        max_age_seconds=300,
        members = {
            Dolomedes={
                controller={name='locus-signet', protocol=2},
                items={
                    {name='Kgd. Signet Staff', minimum=1,
                        bag_group='equippable'},
                    {name='Jubilee Ring', minimum=1,
                        bag_group='equippable'},
                },
            },
            Tackleberry={
                controller={name='locus-signet', protocol=2},
                items={{name='Kgd. Signet Staff', minimum=1,
                    bag_group='equippable'}},
            },
            Kickpuncher={
                controller={name='locus-signet', protocol=2},
                items={{name='Kgd. Signet Staff', minimum=1,
                    bag_group='equippable'}},
            },
            Barneystinson={
                controller={name='locus-signet', protocol=2},
                items={{name='Kgd. Signet Staff', minimum=1,
                    bag_group='equippable'}},
            },
            Smalls={
                controller={name='locus-signet', protocol=2},
                items={{name='Kgd. Signet Staff', minimum=1,
                    bag_group='equippable'}},
            },
            Achoo={
                controller={name='locus-signet', protocol=2},
                items={{name='Kgd. Signet Staff', minimum=1,
                    bag_group='equippable'}},
            },
        },
    },

    safety = {reraise=false},

    advisories = {
        'Load with //pt locus-signet. LocusPuller is the only pull owner: no EasyFarm artifact belongs to this derivative. Ctrl-P or //pt arm enables pulls and synchronized combat; Alt-P or //pt disarm stops both without unloading the support profile.',
        "Recommended jobs/subjobs are Dolo COR/DNC or COR/NIN for DualEvis's Tauret/Gleti's Knife pair, Tackle PLD/WAR, Kick DNC/WAR, Barney BRD/WHM, Smalls RDM/WHM, and Achoo GEO/BLM. Only the six main jobs are declared in policy; subjobs are documentation, not validation requirements, so a different subjob never withholds profile application or controller authority. COR/THF remains accepted but cannot use the offhand; this profile selects Evisceration at 1000 TP.",
        'At the stationary camp, Tackle selects the nearest valid Locus Dire Bat within 20 yalms as soon as the prior fight ends, opens with Flash, and engages. LocusPuller exclusively owns Flash; generic PLD AutoTank stays off so Flash is never spent mid-fight. PartyOps measured Flash-to-first-melee travel as high as 16.462 seconds, so helper/adapter fail-open bounds are twenty/thirty seconds. Manual actions always pass.',
        'When any member is missing Signet, the current pull drains completely before maintenance begins; this also runs automatically on an initial all-missing profile load before the first XP pull. New pulls pause and all six must be idle. Already-buffed members count complete without using a staff; each missing member must keep an exact Kgd. Signet Staff visibly equipped through the empirically proven 42.5-second activation boundary, and only the observed Signet buff counts as success.',
        'Dolo keeps Jubilee Ring in the GearSwap right-ring slot for this profile; the left ring remains untouched. Signet renewal and bounded same-profile GearSwap recovery do not release the ring. Profile stop, different-profile replacement, zone departure, logout, PartyTactics unload, or expired recovery releases profile-local ownership.',
        'A standalone GearSwap reload is recovered through one exact controller request that starts one full PartyTactics reapply, so every weapon and support lane is restored rather than only the adapter.',
        'A raw SignetKeeper reload is detected by its process-local instance nonce. The adapter immediately holds every automatic lane OFF and requests one bounded full-profile recovery, preserving the ordered operator state while a fresh controller authority replaces the old one.',
        'Automatic lanes stay off during the GearSwap gap. Signet/Jubilee ownership is raw-reasserted, an interrupted staff timer and cycle restart safely at cycle 1, and the prior operator state becomes effective on each client only after its new adapter probe. Zone, logout, profile stop, and replacement remain terminal keep-off paths.',
        'Ctrl-P and Alt-P are serialized by Dolo into a revisioned operator state. Alt-P turns local PartyCombat off immediately; a delayed ON, old Signet resume, duplicate IPC packet, or recovering adapter can never overtake a newer OFF. ON remains recorded while the adapter is unavailable or Signet is suspended and becomes effective only after the current protocol-2 authority is ready.',
        'Periodic ordered-state repair is silent and local. It can restore a missed ON or OFF without replaying PartyCombat arm/disarm chat, broadcasting redundant authority, or interfering with manual combat after the profile is disarmed.',
        'A missing, depleted, or unusable staff pauses only the Signet maintenance cycle. It never installs a spell, weaponskill, item, target, or movement input filter; manual intervention remains available at every moment.',
        'The ordinary //pt locus profile is a separate immutable profile and retains its existing EasyFarm contract. Nothing in this derivative changes that profile, another fight, or a shared GearSwap helper.',
    },
}
