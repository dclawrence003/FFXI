return {
    schema = 1,
    id = 'escha-ruaun-genbu-genmei',
    version = '2.7.0',
    policy_id = 'pt-genbu-genmei',
    label = 'Escha - Ru\'Aun Genbu: automatic Genmei Shield farm',
    aliases = {'genmei','genbu','eschagenbu','genmeishield'},

    -- Loaded by the stable PartyTactics GearSwap host. This exact adapter
    -- version is part of this profile's fingerprint; no other fight loads it.
    gearswap_adapter = {
        id='escha-ruaun-genbu-genmei', version='2.7.0',
        controller='genmei', protocol=1,
        actions={'barwatera','setup','crusade','divine-emblem','sentinel','flash',
            'provoke','haste-samba','presto','box-step','evisceration',
            'savage-blade','disengage','shoot',
            'last-stand','triple-shot','proc','burst',
            'recover-songs','recover-rolls','combat-start','combat-end',
            'cancel'},
    },

    members = {
        Dolomedes={main_job='COR', sub_jobs={'THF','DNC','NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'WAR'}},
        Kickpuncher={main_job='DNC', sub_jobs={'WAR'}},
        Barneystinson={main_job='BRD', sub_jobs={'WHM'}},
        Smalls={main_job='RDM', sub_jobs={'WHM'}},
        Achoo={main_job='GEO', sub_jobs={'BLM','WHM'}},
    },

    roles = {
        tank='Tackleberry', puller='Tackleberry',
        skillchain_starter='Kickpuncher', skillchain_opener='Tackleberry',
        skillchain_closer='Dolomedes',
        thunder_proc='Dolomedes', primary_healer='Tackleberry',
        backup_healer='Smalls', status_support='Smalls',
        magic_burster='Achoo', secondary_magic_burster='Smalls',
    },

    combat = {
        leader='Dolomedes', puller='Tackleberry', movement='stationary',
        -- PartyCombat owns only the two melee clients. Dolo receives one
        -- engage request and exact-ID ranged/WS actions, so PartyCombat never
        -- repeatedly faces him or snaps his visible target.
        attackers={'Tackleberry','Kickpuncher'},
        -- Smalls is a target-only observer: the generic RDM helper requires a
        -- matching local <t> for Dia, but observer mode never
        -- faces, engages, or moves him.
        targeters={'Tackleberry','Kickpuncher','Smalls'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        -- Roller2 services roll1 first after Tortoise Song. Restore the magic
        -- accuracy roll before the TP roll so queued procs and bursts are not
        -- left without Warlock's Roll during the shared ability recast.
        cor={rolls={'warlock','samurai'}},
        brd={
            preset='magicboss', target_source='Tackleberry',
            -- Barney retained ample MP under Ballad in the successful run.
            -- Preserve the native song lane and leave cure/status work to
            -- the assigned owners.
            healbot='off',
        },
        rdm={
            -- Reuse the already-frozen lower-healing controller: one party
            -- Protect/Shell pass, 50% backup cures, and core buffs/Dia.
            -- Its inherited bounded caster-Silence observation can try up to
            -- three times per coverage cycle and rearm after observed loss;
            -- it remains best effort and is never a combat prerequisite.
            -- This changes no shared helper and cannot affect another fight.
            preset='limbus-protect', target_source='Tackleberry',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Smalls','Achoo'},
            -- Self first, then the sustained GEO and Majesty-healing lanes.
            -- Ballad covers Barney, so he does not consume RDM maintenance.
            refresh={'Smalls','Achoo','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes','Kickpuncher'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Smalls','Tackleberry'},
            -- RDM `off` intentionally retains only HealBot's NA lane. The
            -- versioned Genbu adapter ignores Weight alone while this profile
            -- is active, preserving Poison and other valid status removal.
            healbot='off',
        },
        geo={
            mode='leanmanaged', zerg=false,
            indi='Acumen', geo='Malaise',
            entrust='Languor', entrustee='Tackleberry',
            combat_entrust_only=false,
            -- Preserve MP for Malaise, Acumen, Entrust Languor, and Thunder.
            -- The PLD/RDM lanes already cover the observed damage comfortably.
            healbot='off',
        },
        pld={
            preset='manualsc', leader='Dolomedes',
            -- Broad native AutoBuff also invokes generic /WAR Aggressor and
            -- Berserk. Keep it off; the encounter runtime requests only the
            -- defensive actions this fight actually needs.
            native_buffs=false, native_tank=false,
        },
        -- Genbu's generic DNC helper is fully disabled. Haste Samba,
        -- completion-driven Presto/Box Step, and Evisceration remain fixed
        -- profile-local encounter actions; overlapping Waltzes do not.
        dnc={enabled=false},
    },

    offense = {
        Dolomedes={
            weapon_mode='DeathPenalty', ws='Last Stand', tp=1500,
            automatic=false, disable_native_autows=true,
        },
        Tackleberry={
            weapon_mode='Naegling', ws='Savage Blade', tp=1250,
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

    -- This contract is evaluated from each live client after GearSwap has had
    -- time to apply the profile. It is deliberately read-only: PartyTactics
    -- verifies the server-equipped slots and available resources, while
    -- GearSwap remains the only equipment owner.
    preflight = {
        -- Manual checks report useful state but never authorize or block.
        required_before_combat=false,
        zone=289,
        all = {
            key_items={
                {ids={2894,3031}, label='Tribulens or Radialens'},
            },
        },
        members = {
            Dolomedes={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','March','Samurai Roll',
                    "Warlock's Roll",{id=33, label='Haste'},'Phalanx'},
                equipment={
                    main='Rostam', sub='Nusku Shield', range='Death Penalty',
                    ammo='Living Bullet',
                },
                items={
                    {name='Animikii Bullet', minimum=1,
                        bag_group='equippable'},
                    {name='Living Bullet', minimum=24, warn_below=99,
                        bag_group='equippable'},
                    {any_of={'Trump Card','Thunder Card'}, minimum=6,
                        warn_below=12, bag_group='inventory'},
                },
                key_items={{id=2949, label="Genbu's Honor"}},
                actions={
                    {kind='weaponskill', name='Last Stand'},
                    {kind='ability', name='Thunder Shot'},
                    {kind='ability', name='Triple Shot'},
                },
            },
            Tackleberry={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','March','Minne',
                    'Samurai Roll',{id=33, label='Haste'},
                    {id=43, label='Refresh'},'Phalanx'},
                equipment={main='Naegling', sub='Diamond Aspis'},
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Crusade'},
                    {kind='ability', name='Divine Emblem'},
                    {kind='spell', name='Flash'},
                    {kind='ability', name='Provoke'},
                    {kind='ability', name='Sentinel'},
                },
            },
            Kickpuncher={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','March','Minne',
                    'Samurai Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                actions={
                    {kind='weaponskill', name='Evisceration'},
                    {kind='ability', name='Haste Samba'},
                    {kind='ability', name='Presto'},
                    {kind='ability', name='Box Step'},
                },
            },
            Barneystinson={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','Ballad'},
                actions={
                    {kind='spell', name='Victory March'},
                    {kind='spell', name="Knight's Minne V"},
                    {kind='spell', name="Mage's Ballad III"},
                    {kind='spell', name='Barwatera'},
                    {kind='spell', name='Reraise'},
                },
            },
            Smalls={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','Ballad',
                    "Warlock's Roll",{id=33, label='Haste'},
                    {id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Thunder'},
                    {kind='spell', name='Thunder IV'},
                    {kind='spell', name='Haste II'},
                    {kind='spell', name='Refresh III'},
                    {kind='spell', name='Phalanx II'},
                    {kind='spell', name='Protect V'},
                    {kind='spell', name='Shell V'},
                },
            },
            Achoo={
                controller={name='genmei', protocol=1},
                buffs={'Protect','Shell','Barwater','Ballad',
                    {id=551, label='Indi-Acumen'},
                    "Warlock's Roll",{id=33, label='Haste'},
                    {id=43, label='Refresh'}},
                equipment={
                    main='Maxentius', sub='Sors Shield', range='Dunna',
                },
                actions={
                    {kind='spell', name='Indi-Acumen'},
                    {kind='spell', name='Geo-Malaise'},
                    {kind='spell', name='Indi-Languor'},
                    {kind='ability', name='Entrust'},
                    {kind='spell', name='Thunder'},
                    {kind='spell', name='Thunder IV'},
                },
            },
        },
    },

    -- The adapter adds bounded next-legal requests for Tackle's coordinated
    -- Savage Blade and the existing Lightning reactions. Only that client's
    -- automatic helper tick pauses; operator actions always pass through.
    manual_actions = {},

    safety = {reraise=true},

    advisories = {
        'Load with //pt genmei and let normal support prebuff while everyone is clustered around Barney. Pop and target Genbu, then Ctrl-P (the same simple start toggle as //pt arm) starts the timed plan immediately with zero ACK, check, controller, buff, or setup prerequisites. Alt-P or //pt disarm stops it.',
        'Recommended jobs are Dolo COR/THF, Tackle PLD/WAR, Kick DNC/WAR, Barney BRD/WHM, Smalls RDM/WHM, and Achoo GEO/BLM. COR/THF applies native Treasure Hunter II with Dolo\'s first aggressive ranged action; do not swap a TH ammo item over Death Penalty ammunition.',
        'Stay clustered through Barney\'s opening Barwatera. Once Ctrl-P starts combat, position only: Tackle faces Genbu away, Kick moves to its rear within 4.5 yalms, and Dolo plus Barney, Smalls, and Achoo form a support cluster roughly 11-14 yalms from Genbu. This keeps songs, rolls, spells, and Indi-Acumen together while remaining outside the target-centered 10-yalm Waterga radius. Stationary combat never moves a character.',
        'All three physical weapon skills are profile-local and automatic with AutoWS2 off: when Tackle and Dolo have TP, Kick adds Evisceration if ready, Tackle follows with Savage Blade, and Dolo closes Last Stand for Light. If Kick is not ready, Savage Blade > Last Stand still makes Light. Each successfully observed step has a short fail-open timeout; no missing, missed, or failed step can stop melee, ranged attacks, support, or manual control.',
        'Tackle\'s intended Savage Blade is a bounded next-legal request, so a Majesty cure already in progress cannot discard that chain step. Invincible cancels any queued physical action immediately.',
        'Dolo receives a bounded next-legal Triple Shot request at the pull. Only an observed successful use starts its 300-second recast cadence; while due but unconfirmed, the runtime retries a bounded request every 12 seconds. It yields to the coordinated chain and a waiting Thunder Shot, never consumes COR\'s native automatic tick, and never filters manual actions.',
        'Ctrl-P is the immediate group-engage edge. The profile independently attempts Barwatera, Sentinel, Crusade, Divine Emblem, Flash, Provoke, and Geo-Malaise on a collision-safe best-effort timeline after that edge; none is a prerequisite for anything else. Two bounded exact-target broadcasts also make //pt arm reach the same result without creating a persistent target lock.',
        'Kick\'s generic DNC helper is Off, removing the redundant emergency-Waltz lane observed in the successful run. This profile alone maintains Haste Samba and uses completion-confirmed Presto before Box Step so Sluggish Daze reaches its full defense reduction quickly. Presto gets only two chances inside five seconds before Box Step proceeds unenhanced; a rejected or missing action never gates combat. Long refreshes still begin only from completed action packets.',
        'Barney receives one bounded best-effort Barwatera maintenance refresh near seven minutes, with no result used as a prerequisite. Smalls maintains Refresh III on himself, Achoo, and Tackle; Barney retained ample MP under Ballad in the successful run and is intentionally omitted.',
        'Invincible gives Dolo a bounded next-legal Thunder Shot and gives Smalls and Achoo separate bounded next-legal Thunder requests. Dolo\'s ordinary ranged cadence pauses for eight seconds so the queued Thunder Shot gets an action window, then resumes automatically. The first observed positive party physical result resumes automatic physical work early; 30 seconds remains the fail-open immunity fallback.',
        'While this profile is active, Smalls keeps his HealBot NA lane but ignores only Genbu\'s unerasable Weight aura. Poison, Accuracy Down, and other valid status removal remain available. The first positive party physical result also cancels any undelivered Smalls/Achoo backup Thunder requests.',
        'Tackle owns routine Majesty healing. Smalls uses the frozen lower-threshold backup-healing preset and the NA lane; Barney and Achoo do not free-run cures. Tortoise Song prompts the existing song and roll helpers to rebuild their normal sets; it removes songs and rolls, not Protect or Shell. Warlock\'s Roll is roll1 so Roller2 restores magic accuracy before Samurai Roll after a wipe.',
        'Harden Shell and Shell V are not chased with removal spells that failed every observed attempt. Smalls keeps Dia III; Kick\'s accelerated Presto/Box Step reaches Sluggish Daze level 10 in as few as two landed Steps. Together they provide up to 43.31% Defense Down, while magic bursts ignore Defense. Shield Bash dispel stays disabled because Tackle lacks Cab. Gauntlets +2 or better. RDM Silence remains best effort and never gates combat.',
        'A detected Light gives Smalls and Achoo separate bounded next-legal Thunder IV reservations. Each mage pauses only their own routine automatic helper until that request casts or the eight-second burst window expires; the other mage, every other helper, and all manual actions remain independent.',
        'GearSwap remains the only equipment and instrument owner. PartyTactics never filters manual actions in this profile: targeting, attacks, ranged attacks, weapon skills, spells, abilities, and emergency intervention always remain available.',
        'Alt-P, //pt disarm, claim loss, victory, profile replacement, zone change, or //pt off clears only this profile\'s pending best-effort work. It never starts an automatic preflight loop.',
    },
}
