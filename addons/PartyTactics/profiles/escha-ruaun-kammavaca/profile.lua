return {
    schema = 1,
    id = 'escha-ruaun-kammavaca',
    version = '1.2.0',
    policy_id = 'pt-ruaun-kammavaca',
    label = 'Escha - Ru\'Aun Kammavaca: ordered-add party clear',
    aliases = {'kammavaca','kamma','ruaun-kammavaca'},

    members = {
        Dolomedes={main_job='COR', sub_jobs={'DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR'}},
        Kickpuncher={main_job='DNC', sub_jobs={'WAR'}},
        Barneystinson={main_job='BRD', sub_jobs={'WHM'}},
        Smalls={main_job='RDM', sub_jobs={'WHM','BLM'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        popper='Dolomedes', tank='Tackleberry', puller='Tackleberry',
        ordered_target_caller='Dolomedes',
        crowd_control='Barneystinson', silencer='Smalls',
        primary_healer='Smalls', backup_healer='Barneystinson',
        emergency_healer='Achoo', bubble_support='Achoo',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='mobile',
        attackers={'Dolomedes','Tackleberry','Kickpuncher','Achoo'},
        targeters={'Dolomedes','Tackleberry','Kickpuncher',
            'Barneystinson','Smalls','Achoo'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'chaos','samurai'}},
        brd={
            -- The universal reviewed sleep reservation is available under
            -- this fight's ordinary physical song preset. GearSwap remains
            -- the only owner of song dispatch, instruments, and equipment.
            preset='physical', target_source='Tackleberry',
            healbot='cure-na',
        },
        rdm={
            -- Reuse the generic protected magic-boss core. The profile
            -- runtime submits one best-effort exact-ID Silence reservation
            -- to the GearSwap-owned RDM queue.
            preset='magicboss-protect', target_source='Tackleberry',
            haste={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            refresh={'Smalls','Achoo','Barneystinson','Tackleberry'},
            phalanx={'Dolomedes','Tackleberry','Kickpuncher','Achoo'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
        },
        geo={
            mode='leanrrmanaged', zerg=false, indi='Fury', geo='Frailty',
            entrust='Fend', entrustee='Tackleberry', healbot='cure-na',
            combat_entrust_only=true,
        },
        pld={preset='manualsc', leader='Dolomedes'},
        dnc={preset='physical', target_source='Tackleberry'},
    },

    offense = {
        Dolomedes={
            weapon_mode='DualSavage', ws='Savage Blade', tp=1000,
        },
        Tackleberry={
            -- Tackle is an attacker so mobile PartyCombat keeps the tank on
            -- the exact forced add, but AutoWS remains off to prioritize hate
            -- and Majesty recovery over damage.
            weapon_mode='Naegling', ws='Savage Blade', tp=1000,
            automatic=false,
        },
        Kickpuncher={
            weapon_mode='Tauret', ws='Evisceration', tp=1000,
        },
        Achoo={
            -- Native GEO needs an engaged target to place Geo-Frailty. Achoo
            -- follows only the forced target and never spends a weapon skill.
            -- The opt-in native switch prevents a prior GearSwap AutoWSMode
            -- from leaking into this exact-order encounter.
            weapon_mode='Maxentius', ws='Black Halo', tp=1000,
            automatic=false, disable_native_autows=true,
        },
    },

    preflight = {
        required_before_combat=true,
        auto_after_apply=3,
        all = {
            items={
                {name='Echo Drops', minimum=12, bag_group='inventory'},
            },
            key_items={
                {ids={2894,3031}, label='Tribulens or Radialens'},
            },
        },
        members = {
            Dolomedes={
                equipment={
                    main='Naegling', sub="Gleti's Knife", range='empty',
                },
                key_items={{id=2944, label="Kammavaca's binding"}},
                actions={{kind='weaponskill', name='Savage Blade'}},
            },
            Tackleberry={
                equipment={main='Naegling', sub='Diamond Aspis'},
                actions={
                    {kind='spell', name='Flash'},
                    {kind='ability', name='Provoke'},
                    {kind='ability', name='Sentinel'},
                },
            },
            Kickpuncher={
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                actions={{kind='weaponskill', name='Evisceration'}},
            },
            Barneystinson={
                actions={
                    {kind='spell', name='Horde Lullaby II'},
                    {kind='spell', name='Barsilencera'},
                    {kind='spell', name='Erase'},
                },
            },
            Smalls={
                actions={
                    {kind='spell', name='Silence'},
                    {kind='spell', name='Cure IV'},
                    {kind='ability', name='Elemental Seal', optional=true},
                    {kind='spell', name='Sleepga', optional=true},
                    {kind='spell', name='Stun', optional=true},
                },
            },
            Achoo={
                equipment={main='Maxentius', sub='Sors Shield'},
                actions={
                    {kind='spell', name='Indi-Fury'},
                    {kind='spell', name='Geo-Frailty'},
                    {kind='spell', name='Indi-Fend'},
                    {kind='spell', name='Cure III'},
                },
            },
        },
    },

    manual_actions = {
        sleep={
            character='Barneystinson', adapter='brd-pack-sleep',
        },
        silence={
            character='Smalls', adapter='rdm-exact-silence',
            target_names={'Kammavaca'},
        },
    },

    safety = {reraise=true},

    advisories = {
        'Recommended jobs: Dolo COR/DNC or /NIN, Tackle PLD/WAR, Kick DNC/WAR, Barney BRD/WHM, Smalls RDM/WHM, and Achoo GEO/WHM. Smalls /BLM remains optional for emergency Sleepga or Stun, but the fast normal clear favors /WHM recovery.',
        'Apply the profile and wait for ACK 6/6 plus PREFLIGHT PASS 6/6 before popping. Every member must carry 12 Echo Drops in Inventory. The runtime disables native auto-target while this profile is active and restores it when the profile stops.',
        'Barney maintains Barsilencera before the encounter. After party-claimed exact-name Kammavaca appears, Smalls sends one exact-ID Silence reservation to his GearSwap-owned priority queue. Silence is best-effort support and never delays engagement; Stymie and Saboteur are not spent automatically.',
        'An add is eligible only when party-claimed, or when unclaimed with valid coordinates within 20 yalms of the active claimed Kammavaca. A nonzero foreign claim is always rejected. Automatic damage also waits for the current 6/6 ACK and required preflight barrier.',
        'Any eligible add immediately supersedes an existing boss lock. Dolo asks PartyCombat to force the exact first living CLMA ID and reasserts it under a bounded rolling throttle if Dolo drifts back to Kammavaca. Correct local targeting quiets the reassertion.',
        'Barney observes that same exact first add without engaging. Once his current target is verified, his reviewed GearSwap queue attempts Horde Lullaby II as the next action. Sleep is useful control but is not a damage gate, and a numeric-ID Bard song command is never used.',
        'Dolo automatically advances through Kammavaca\'s Clionid, Kammavaca\'s Limule, Kammavaca\'s Murex, Kammavaca\'s Amoeban, then Kammavaca. When no eligible add is visible, only a short 0.75-second entity-settle window precedes the boss; any later add immediately takes priority. Never use AoE damage.',
        'Horde Lullaby II is centered on Barney, so keep the pack within roughly eight yalms of him. PartyCombat selects his exact current target only as the legal anchor GearSwap needs; that target does not determine the center of the sleep radius.',
        'Tackle is deliberately an attacker but has AutoWS2 Off: mobile PartyCombat keeps the tank on the exact forced target for melee hate without spending TP or choosing another target. Dolo and Kick are the only automatic weapon-skill users.',
        'Achoo is also engaged with AutoWS2 Off because the native GEO controller otherwise cannot place offensive Geo-Frailty. After Confrontation clears pre-existing geomancy, confirm fresh Indi-Fury, Geo-Frailty, entrusted Indi-Fend, and Achoo\'s restored self-Reraise before judging damage or survival.',
        'Only queue-safe manual recovery remains: //pt sleep uses Barney\'s current-target GearSwap queue, while //pt silence resolves party-claimed Kammavaca and submits the same exact-ID RDM queue request. //pt force is a deliberate controller override and bypasses profile target selection.',
        'Unconfirmed Silence or Sleep may produce a support note, but never pauses the exact ordered clear. Target observation, sleep queuing, and add-force correction all use bounded rolling retries so a transient startup or distance miss does not require button-spam.',
        'Use //pt off immediately on loss of control; //pt disarm alone leaves this automatic runtime active. Stopping the profile restores native auto-target. If the group wipes, recover with Reraise, let Confrontation end, restore support and lenses/pop item as required, then run a fresh preflight rather than forcing stale state.',
    },
}
