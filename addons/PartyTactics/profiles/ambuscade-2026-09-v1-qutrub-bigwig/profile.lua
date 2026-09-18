return {
    schema = 1,
    id = 'ambuscade-2026-09-v1-qutrub-bigwig',
    version = '1.1.0',
    policy_id = 'pt-ambu2609v1-qutrub',
    label = 'Ambuscade September 2026 V1: Bozzetto Bigwig',
    aliases = {'qutrub','bigwig','sep-v1','ambu2609v1'},

    gearswap_adapter = {
        id='ambuscade-2026-09-v1-qutrub-bigwig', version='1.1.0',
        controller='qutrub-bigwig', protocol=1,
        actions={'setup','food','crusade','divine-emblem','sentinel','rampart',
            'palisade','flash','flash-add','summon','mew','retreat','clarion',
            'fourth-song',
            'shadow-ni','shadow-ichi','lead','middle','close',
            'silence-add','dispel-ice-spikes','diaga','silence-boss',
            'lowhp-on','lowhp-off','lowhp-cure','support-cure','cancel'},
    },

    members = {
        Dolomedes={main_job='COR', sub_jobs={'NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'NIN'}},
        Kickpuncher={main_job='DNC', sub_jobs={'NIN'}},
        Barneystinson={main_job='BRD', sub_jobs={'SMN'}},
        Smalls={main_job='RDM', sub_jobs={'SMN'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        skillchain_starter='Kickpuncher', skillchain_opener='Tackleberry',
        skillchain_closer='Dolomedes', primary_healer='Smalls',
        backup_healer='Tackleberry', emergency_healer='Kickpuncher',
        primary_mew='Barneystinson', secondary_mew='Smalls',
        add_silence='Smalls', add_spike_strip='Smalls', shadow_strip='Smalls',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        attackers={'Dolomedes','Tackleberry','Kickpuncher'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'chaos','hunter'}},
        brd={
            preset='physical', target_source='Tackleberry',
            healbot='off',
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
            entrust='Wilt', entrustee='Tackleberry',
            combat_entrust_only=false,
            healbot='cure-na',
        },
        pld={
            preset='manualsc', leader='Dolomedes',
            native_buffs=false, native_tank=false,
        },
        dnc={preset='tankheal', target_source='Tackleberry'},
    },

    -- The profile adapter is the only weaponskill scheduler. AutoWS2 and the
    -- native DNC/COR skill spenders remain off, so an add transition, missing
    -- shadow, or Perfect Dodge hold cannot leak an unrelated weaponskill.
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
    },

    preflight = {
        required_before_combat=true,
        auto_after_apply=30,
        auto_retry_seconds=10,
        max_age_seconds=120,
        members = {
            Dolomedes={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal','Hunter\'s Roll',
                    'Chaos Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={
                    main='Rostam', sub='Tauret', range='Death Penalty',
                    ammo='Living Bullet',
                },
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {name='Shihei', minimum=24, warn_below=99,
                        bag_group='equippable'},
                    {name='Living Bullet', minimum=24, warn_below=99,
                        bag_group='equippable'},
                },
                actions={
                    {kind='weaponskill', name='Last Stand'},
                },
            },
            Tackleberry={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal','Hunter\'s Roll',
                    'Chaos Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={main='Naegling', sub='Diamond Aspis'},
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {name='Shihei', minimum=24, warn_below=99,
                        bag_group='equippable'},
                },
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Crusade'},
                    {kind='ability', name='Divine Emblem'},
                    {kind='ability', name='Sentinel'},
                    {kind='ability', name='Rampart'},
                    {kind='ability', name='Palisade'},
                    {kind='spell', name='Flash'},
                },
            },
            Kickpuncher={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal','Hunter\'s Roll',
                    'Chaos Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {name='Shihei', minimum=24, warn_below=99,
                        bag_group='equippable'},
                },
                actions={
                    {kind='weaponskill', name='Evisceration'},
                    {kind='ability', name='Curing Waltz III'},
                    {kind='ability', name='Curing Waltz IV'},
                    {kind='ability', name='Curing Waltz V'},
                    {kind='ability', name='Healing Waltz'},
                },
            },
            Barneystinson={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March',
                    {id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Cait Sith'},
                    {kind='ability', name='Mewing Lullaby'},
                    {kind='ability', name='Retreat'},
                },
            },
            Smalls={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March',
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Silence'},
                    {kind='spell', name='Dispel'},
                    {kind='spell', name='Diaga'},
                    {kind='spell', name='Cure II'},
                    {kind='spell', name='Cure IV'},
                    {kind='spell', name='Haste II'},
                    {kind='spell', name='Refresh III'},
                    {kind='spell', name='Phalanx II'},
                    {kind='spell', name='Protect V'},
                    {kind='spell', name='Shell V'},
                    {kind='spell', name='Cait Sith'},
                    {kind='ability', name='Mewing Lullaby'},
                    {kind='ability', name='Retreat'},
                },
            },
            Achoo={
                controller={name='qutrub-bigwig', protocol=1},
                buffs={'Protect','Shell','March',
                    {id=549, label='Indi-Fury'},
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                equipment={
                    main='Maxentius', sub='Sors Shield', range='Dunna',
                },
                actions={
                    {kind='spell', name='Indi-Fury'},
                    {kind='spell', name='Geo-Frailty'},
                    {kind='spell', name='Indi-Wilt'},
                    {kind='ability', name='Entrust'},
                    {kind='spell', name='Cure IV'},
                    {kind='spell', name='Erase'},
                    {kind='spell', name='Poisona'},
                    {kind='spell', name='Paralyna'},
                    {kind='spell', name='Reraise'},
                },
            },
        },
    },

    manual_actions = {},
    safety = {reraise=true},

    advisories = {
        'Required jobs: Dolo COR/NIN, Tackle PLD/NIN, Kick DNC/NIN, Barney BRD/SMN, Smalls RDM/SMN, and Achoo GEO/WHM. The preflight fails closed on a wrong subjob, missing controller, required buff, weapon, ammunition, ninja tools, Cait Sith/Mew access, /WHM recovery spell, or owned Grape Daifuku.',
        'Apply the profile inside either Maquette Abdhaljs-Legion battlefield (zone 183 or 287) and wait for ACK 6/6 plus PREFLIGHT PASS 6/6. GearSwap owns every weapon, ammo, song instrument, and action set; this adapter has no equipment surface.',
        'Before arming, put Tackle, Kick, and Dolo in melee range. Stationary PartyCombat neither walks Dolo in nor automates ranged attacks, so melee swings supply his Last Stand TP. One //pt arm is the only pull trigger. Tackle opportunistically uses ready Crusade, Divine Emblem, and Sentinel, then must packet-confirm an exact-ID Flash before PartyCombat can force engagement. Cooldown mitigation never stalls a repeat.',
        'After the pull, do not issue target, assist, weaponskill, Silence, Diaga, shadow, summon, Mewing, or song commands. Dolo centrally drives all three attackers and the other clients consume only bounded exact-ID semantic reservations.',
        'Every add wave preempts boss damage. All three attackers kill every living Bozzetto Astrologer first, then every Bozzetto Tormentor or Tormenter, one exact entity at a time. Tackle opens and periodically refreshes exact-subject Flash on each add, and opportunistically reserves Rampart and Palisade for each newly observed wave. The boss cannot resume until the wave is observably empty and the entity-settle hold has elapsed.',
        'During either add wave, keep Barney, Smalls, and both Cait Sith pets within roughly 10 yalms of Bigwig and the add pack; ordinary spell or song range is not sufficient for reliable Mew coverage. Barney and Smalls summon Cait Sith automatically and alternate Mewing Lullaby every 31 seconds only while the pack is live. A full-pack Mew result queues bounded Retreat on that exact lane so Cait returns without being released or feeding TP. This is TP suppression, not sleep; the adds are sleep immune.',
        'Smalls repeatedly Silences each live Astrologer and uses a bounded exact-subject Dispel response when an Astrologer is observed completing Ice Spikes.',
        'Dolo, Tackle, and Kick maintain Utsusemi with Ni and bounded Ichi fallback. Every local adapter refuses coordinated weaponskills without a live Copy Image status. Perfect Dodge, phase thresholds, adds, missing shadows, low party health, lost claim, and a changed entity all hold or cancel damage.',
        'The fixed chain is Kick Evisceration, Tackle Savage Blade only after the lead result, and Dolo Last Stand only after packet-confirmed Fragmentation (message 291). The Light result (message 288) closes the transaction. AutoWS2 stays Off.',
        'After the second add wave is dead and Bigwig is at or below 30%, the profile latches VD low-HP control and Mew stops. Immediately move Barney, Smalls, and Achoo beyond 16 yalms from Bigwig while keeping Smalls within 20 yalms of all three attackers. The runtime uses live coordinates and fails closed if any required distance is missing or unsafe.',
        'Legacy Cure, Regen, Curaga, Cura, Curing Waltz, Divine Waltz, and Majesty top-ups are suppressed as needed to protect Dolo, Tackle, and Kick. Auto-attacks lower them into a deliberate 13-25% band. Below 13%, PartyCombat stops and Smalls uses bounded exact-member Cure II; support members below 60% receive exact-member Cure IV backup.',
        'All three attackers must have locally confirmed shadows before final-phase weaponskills. Low-HP control stays latched if Bigwig heals above 30%, is heartbeat-bound on every client, and is cleared on teardown.',
        'Smalls remains the primary RDM recovery owner while /SMN; his main job still supplies the exact Cure II/Cure IV finish controller and routine single-target cures. Achoo /WHM supplies the independent cure/status-removal HealBot lane while retaining uninterrupted Indi-Fury and Geo-Frailty. The low-HP guard prevents every legacy surface from accidentally topping up an attacker during the finish; support healing remains available.',
        'Below 30%, known Utsusemi: San blocks coordinated weapon skills until Smalls packet-confirms an exact-ID Diaga strip; bounded retry cycles prevent one rejected cast from becoming a permanent stall. Smalls makes only a finite, non-SP Silence attempt against Bigwig. No Stymie, Saboteur, Chainspell, Invincible, or other RDM/PLD SP response exists. Barney opportunistically uses Clarion Call and a fourth Minne when ready, but neither can block the reliable native three-song baseline or the pull.',
        'Victory, any party-member knockout, foreign claim, missing/reused entity, zone departure, profile replacement, or //pt off cancels all six queues, stops PartyCombat, releases the exact encounter, and consumes the arm edge. A later pull requires a fresh //pt arm.',
    },
}
