return {
    schema = 1,
    id = 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait',
    version = '1.14.0',
    policy_id = 'pt-ambu2609v1-qutrub-nocait',
    label = 'Ambuscade September 2026 V1: Bigwig no-Cait cooperative',
    aliases = {'qutrub-nocait','bigwig-nocait','sep-v1-nocait',
        'ambu2609v1-nocait'},

    gearswap_adapter = {
        id='ambuscade-2026-09-v1-qutrub-bigwig-no-cait', version='1.10.0',
        controller='qutrub-bigwig-no-cait', protocol=1,
        actions={'setup','food','pull','light-shot-target','frailty-target',
            'cocoon','blank-gaze-add','flash-add',
            'sheep-song-add','geist-wall-add','jettatura-add','box-step-add',
            'stun-add',
            'entrust','indi-wilt','clarion','fourth-song',
            'shadow-ni','shadow-ichi','reraise','wake-pack',
            'crusade','reprisal','sentinel-add','palisade-add',
            'silence-add','dispel-ice-spikes','diaga','silence-boss',
            'slow-ii','paralyze-ii','dia-iii','cure-iv','poisona','paralyna',
            'silena','cursna','erase','lowhp-on','lowhp-off','lowhp-cure',
            'support-cure','emergency-cure',
            'capture-on','capture-off','cancel'},
    },

    members = {
        Dolomedes={main_job='COR', sub_jobs={'NIN'}},
        Tackleberry={main_job='PLD', sub_jobs={'BLU'}},
        Kickpuncher={main_job='DNC', sub_jobs={'NIN'}},
        Barneystinson={main_job='BRD', sub_jobs={'NIN'}},
        Smalls={main_job='RDM', sub_jobs={'WHM'}},
        Achoo={main_job='GEO', sub_jobs={'WHM'}},
    },

    roles = {
        -- Role metadata requires concrete members. These are the nominal
        -- opening assignments. During a Normal add wave runtime.lua anchors
        -- the Astrologer on Achoo and one Tormentor each on Tackle and the
        -- Dolo/Kick nonholder, then returns all five combat members to the
        -- shared Astrologer-first focus after bounded roster assembly.
        boss_anchor='Dolomedes',
        boss_side_damage='Kickpuncher',
        add_tank='Tackleberry',
        add_damage_one='Kickpuncher',
        add_damage_two='Barneystinson',
        puller='Dolomedes',
        evisceration_user='Kickpuncher', savage_blade_user='Barneystinson',
        last_stand_user='Dolomedes', primary_healer='Smalls',
        wake_healer='Achoo', emergency_healer='Tackleberry',
        add_handler='Tackleberry', kite_defense='Achoo',
        add_support='Achoo',
        add_silence='Smalls', add_spike_strip='Smalls', shadow_strip='Smalls',
    },

    combat = {
        leader='Dolomedes', puller='Dolomedes', movement='mobile',
        attackers={'Dolomedes','Tackleberry','Kickpuncher','Barneystinson',
            'Achoo'},
        targeters={'Dolomedes','Kickpuncher','Barneystinson'},
        priority_attackers={},
        target_exclusions={},
    },

    support = {
        cor={rolls={'chaos','hunter'}},
        brd={
            preset='physical', target_source='Dolomedes',
            healbot='off',
        },
        rdm={
            -- Reuse only the immutable generic Sortie/Acuex maintenance core.
            -- This profile's runtime and pinned adapter own the exact Qutrub
            -- cure, opening defense, and post-Convert recovery lanes.
            preset='sortieacuex', target_source='Dolomedes',
            healbot='off',
            haste={'Tackleberry','Dolomedes','Kickpuncher','Barneystinson',
                'Achoo'},
            refresh={'Smalls','Achoo','Barneystinson','Tackleberry'},
            phalanx={'Tackleberry','Dolomedes','Kickpuncher','Barneystinson'},
            defense={'Achoo','Barneystinson','Dolomedes','Kickpuncher',
                'Tackleberry'},
        },
        geo={
            mode='leanrrmanaged', zerg=false,
            indi='Fury', geo='Frailty',
            -- The pinned controller, not native GEO automation, makes an
            -- independent Entrust/Indi-Wilt attempt at each visible add wave.
            entrust='None', entrustee='Tackleberry',
            combat_entrust_only=true,
            -- Smalls owns thresholded cures/status removal. Achoo preserves
            -- MP for mobile Indi-Fury, exact Frailty, and add-side offense;
            -- the encounter wake-pack action remains independently available.
            healbot='off',
        },
        pld={
            -- Keep the legacy PLD helper off so it cannot duplicate the
            -- controller's exact-add actions. Manual PLD controls pass through.
            preset='off', leader='Dolomedes',
            weapon_mode='Naegling',
            native_buffs=false, native_tank=false,
        },
        -- Native DNC automation is disabled to avoid a second scheduler;
        -- Kick's manual controls and the bounded controller lane remain live.
        dnc={enabled=false},
    },

    -- AutoWS2 is the sole automatic weaponskill owner. The fight runtime and
    -- its adapter never submit a weaponskill, so manual WS input remains free.
    offense = {
        Dolomedes={
            weapon_mode='DualLastStandRanged', ws='Last Stand', tp=1000,
            automatic=true, disable_native_autows=true, session_ws=true,
        },
        Tackleberry={
            weapon_mode='Naegling', ws='Savage Blade', tp=1000,
            automatic=true, disable_native_autows=true,
        },
        Barneystinson={
            weapon_mode='DualSavage', ws='Savage Blade', tp=1000,
            automatic=true, disable_native_autows=true,
        },
        Kickpuncher={
            weapon_mode='Tauret', ws='Evisceration', tp=1000,
            automatic=true, disable_native_autows=true,
        },
        Achoo={
            weapon_mode='Maxentius', ws='Black Halo', tp=1000,
            automatic=true, disable_native_autows=true,
        },
    },

    preflight = {
        -- Checks are operator-requested diagnostics only. They report the
        -- intended jobs, actions, and supplies but never authorize combat.
        required_before_combat=false,
        max_age_seconds=120,
        members = {
            Dolomedes={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
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
                        bag_group='inventory'},
                    {name='Living Bullet', minimum=24, warn_below=99,
                        bag_group='equippable'},
                    {any_of={'Trump Card','Light Card'}, minimum=6,
                        warn_below=12, bag_group='equippable'},
                    {any_of={'Instant Reraise III','Super Reraiser',
                        'Hi-Reraiser','Instant Reraise','Reraiser'}, minimum=1,
                        warn_below=2, bag_group='inventory'},
                },
                actions={
                    {kind='weaponskill', name='Last Stand'},
                    {kind='ability', name='Light Shot'},
                    {kind='spell', name='Utsusemi: Ni'},
                    {kind='spell', name='Utsusemi: Ichi'},
                },
            },
            Tackleberry={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal','Hunter\'s Roll',
                    'Chaos Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={main='Naegling', sub='Diamond Aspis'},
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {any_of={'Instant Reraise III','Super Reraiser',
                        'Hi-Reraiser','Instant Reraise','Reraiser'}, minimum=1,
                        warn_below=2, bag_group='inventory'},
                },
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Crusade'},
                    {kind='spell', name='Reprisal'},
                    {kind='spell', name='Cocoon'},
                    {kind='spell', name='Blank Gaze'},
                    {kind='spell', name='Sheep Song'},
                    {kind='spell', name='Geist Wall'},
                    {kind='spell', name='Jettatura'},
                    {kind='spell', name='Flash'},
                    {kind='spell', name='Cure IV'},
                },
            },
            Kickpuncher={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal','Hunter\'s Roll',
                    'Chaos Roll',{id=33, label='Haste'},'Phalanx'},
                equipment={main='Tauret', sub='Ternion Dagger +1'},
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {name='Shihei', minimum=24, warn_below=99,
                        bag_group='inventory'},
                    {any_of={'Instant Reraise III','Super Reraiser',
                        'Hi-Reraiser','Instant Reraise','Reraiser'}, minimum=1,
                        warn_below=2, bag_group='inventory'},
                },
                actions={
                    {kind='weaponskill', name='Evisceration'},
                    {kind='ability', name='Box Step'},
                    {kind='ability', name='Violent Flourish'},
                    {kind='spell', name='Utsusemi: Ni'},
                    {kind='spell', name='Utsusemi: Ichi'},
                },
            },
            Barneystinson={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
                buffs={'Protect','Shell','March','Minuet','Madrigal',
                    'Hunter\'s Roll','Chaos Roll',{id=33, label='Haste'},
                    {id=43, label='Refresh'},'Phalanx'},
                equipment={main='Naegling', sub='Kaja Knife'},
                items={
                    {name='Grape Daifuku', minimum=1, warn_below=6,
                        bag_group='inventory'},
                    {name='Shihei', minimum=24, warn_below=99,
                        bag_group='inventory'},
                    {any_of={'Instant Reraise III','Super Reraiser',
                        'Hi-Reraiser','Instant Reraise','Reraiser'}, minimum=1,
                        warn_below=2, bag_group='inventory'},
                },
                actions={
                    {kind='weaponskill', name='Savage Blade'},
                    {kind='spell', name='Utsusemi: Ni'},
                    {kind='spell', name='Utsusemi: Ichi'},
                },
            },
            Smalls={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
                buffs={'Shell','March',{id=43, label='Refresh'}},
                actions={
                    {kind='spell', name='Silence'},
                    {kind='spell', name='Dispel'},
                    {kind='spell', name='Diaga'},
                    {kind='spell', name='Slow II'},
                    {kind='spell', name='Paralyze II'},
                    {kind='spell', name='Dia III'},
                    {kind='spell', name='Cure II'},
                    {kind='spell', name='Curaga II'},
                    {kind='spell', name='Cure IV'},
                    {kind='spell', name='Haste II'},
                    {kind='spell', name='Refresh III'},
                    {kind='spell', name='Phalanx II'},
                    {kind='spell', name='Protect V'},
                    {kind='spell', name='Shell V'},
                    {kind='spell', name='Erase'},
                    {kind='spell', name='Poisona'},
                    {kind='spell', name='Paralyna'},
                    {kind='spell', name='Reraise'},
                },
            },
            Achoo={
                controller={name='qutrub-bigwig-no-cait', protocol=1},
                buffs={'Protect','Shell','March',
                    {id=549, label='Indi-Fury'},
                    {id=33, label='Haste'},{id=43, label='Refresh'}},
                equipment={
                    main='Maxentius', sub='Sors Shield', range='Dunna',
                },
                actions={
                    {kind='weaponskill', name='Black Halo'},
                    {kind='spell', name='Indi-Fury'},
                    {kind='spell', name='Geo-Frailty'},
                    {kind='spell', name='Flash'},
                    {kind='spell', name='Indi-Wilt'},
                    {kind='ability', name='Entrust'},
                    {kind='spell', name='Curaga II'},
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
        'This is an isolated no-Cait variant; it does not modify the separate Cait profile. Intended jobs are Dolo COR/NIN, Tackle PLD/BLU, Kick DNC/NIN, Barney BRD/NIN, Smalls RDM/WHM, and Achoo GEO/WHM.',
        'For Tackle /BLU, set Cocoon (1 point), Blank Gaze (2), Sheep Song (2), Geist Wall (3), and Jettatura (4): five spells using 12 Blue Magic points. Flash is native PLD magic. //pt check reports missing pieces but never blocks start or any action.',
        'Run //pt v1-qutrub-nocait on Dolo to select, arm, and begin non-hostile preparation automatically. Nobody receives a combat assignment until Dolo manually claims or acts on Bigwig. Pull it roughly 10-15 yalms toward the party-start side when buffs are ready; that observed pull releases combat without a second command. Ctrl-P or //pt arm only reasserts or rebinds after an operator stop or missed target.',
        'Positioning is an operator choice, not a software gate. No ACK, check, buff, spell-set, equipment, controller, coordinate, difficulty, or action-result proof can block start.',
        'Dolo is the configured puller, not Tackle. There is no proximity-based enemy defense mechanic and no reason to drag either group halfway across the arena. Once adds are up, Bigwig may follow its current Dolo/Kick holder into the shared add focus; that is intentional. Smalls remains ranged.',
        'FastFollow remains entirely operator-owned. PartyTactics will not change it or gate start on it; pause or redirect any existing follow state that would undo a directed combat move or drag Smalls into either enemy pack.',
        'The armed preparation state independently requests food, Utsusemi: Ni with an Ichi fallback, Cocoon, Crusade, Reprisal, Reraise, Clarion Call, and an extra Minne while everyone remains in place. Exact-subject Geo-Frailty, RDM debuffs, movement, and attack assignments begin only after the observed manual pull. No setup result can delay or prevent that transition.',
        'On every active focus, packet-confirmed Dia III enables only then one same-target Light Shot. An issued Dia command is not treated as success and retries up to three times when no landing packet arrives. The Dia enhancement caps after one shot, so an executed Light Shot ends that cycle even when its separate Sleep component reports a miss; only a submitted shot with no observed action packet may retry.',
        'On a Normal three-add wave, each sequential spawn receives one exact anchor immediately: Tackle takes the first Tormentor, Achoo /WHM Flashes the Astrologer, and the Dolo/Kick member not holding Bigwig takes the second Tormentor. After 6.25 seconds without another spawn, every released lane closes on the same Astrologer-first focus; an unconfirmed parked owner may remain on its add for its bounded pickup window.',
        'Pickup is ownership-driven. Dolo gets one in-range Light Shot per episode; Kick gets one Box Step after known melee arrival, which can create finishing stock. Neither attempt proves hate. Unique anchors remain through fixed quiet assembly; afterward, direct add-target evidence releases its owner and an unconfirmed exact pickup expires after eight seconds. Violent Flourish is reactive only, and the local adapter submits it only with a finishing move and ready recast.',
        'The current Bigwig holder is inferred only from melee/TP-action target evidence and reviewed every five seconds. A holder change transfers only the second parked Tormentor between Dolo and Kick. During that transfer, the incoming holder gets one disengage edge until a direct melee packet shows the parked add on its new owner; this prevents a transient Bigwig + parked + focus count of three. It never filters a manual override.',
        'The threat budget includes the shared focus. Tackle and the nonholder each own one parked add plus the focus; the holder owns Bigwig plus the focus; Barney and Achoo receive only the focus. This keeps every intended lane at no more than two hostile targets, because Bigwig counts toward Triple Reversal.',
        'If fresh Bigwig-target evidence is unavailable, Tackle and Achoo still establish their exact anchors while Dolo, Kick, and Barney receive one disengage edge. The second Tormentor waits for fresh Dolo/Kick ownership evidence, but no polling loop blocks manual target, movement, spell, ability, weapon-skill, //pc localstop, or //pt disarm input.',
        'During sequential wave assembly, Tackle uses exact Flash/Blank Gaze only and no area-enmity spell or high-enmity Sentinel/Palisade. After a stable one- or two-add roster, the compact Blue Magic sequence remains available when geometry is safe. Fortifying or Animating Wail is stripped only when its recipient becomes the common kill focus: Tackle uses exact Blank Gaze first and Smalls alternates exact Dispel on a failed attempt. No three-add area dispel is used.',
        'Crusade, Reprisal, Smalls\' Astrologer Silence/Dia III, and Achoo\'s Flash/Frailty/Entrust/Indi-Wilt remain independent best-effort lanes. No result, buff, readiness, or geometry proof gates start or manual control.',
        'Very Easy, Easy, Normal, and every later add generation repeat the same staged-pickup then shared-focus state machine. When the current add set is dead, Tackle and Achoo stop and Dolo/Kick/Barney automatically resume Bigwig.',
        'A stalled initial add acquisition receives one exact repair after 4.5 seconds without movement progress or exact attack proof, including when a member is near but not engaging. A member already closing or attacking the right add is left alone. After first arrival, a separate one-edge drift repair applies beyond 4.5 yalms. No still-separated character is snapped every poll.',
        'Parked-add ownership gets only one bounded recapture per drift episode. Target-to-target handoffs never send a late /attack off packet; Barney keeps singing.',
        'AutoWS2 independently spends TP with Dolo Last Stand, Tackle and Barney Savage Blade, Kick Evisceration, and add-only Achoo Black Halo. Dolo\'s automatic Last Stand is fight-scoped across equipment changes and clears on AutoWS2 off or a manual //aws2 use command. Automatic WS observes exact target packets plus completed melee/ranged target and submits to that numeric server ID; a transient <bt> cannot leak a shot back to Bigwig.',
        'Only automatic WS waits for exact target evidence. Manual weapon skills remain unrestricted, the runtime and adapter do not submit weapon skills, and Smalls is explicitly AutoWS2 Off.',
        'Utsusemi is locally loss-reactive rather than timer-driven: each Dolo/Kick/Barney adapter watches its exact Copy Image count, uses live spell recasts to choose Ni, and immediately falls back to Ichi at zero when Ni is unavailable. It retries an exhausted stack locally instead of waiting ten seconds. Phantom Whorl readiness triggers the same independent restore request. Tackle is PLD/BLU and does not cast Utsusemi.',
        'Astrologer Sleep, Sleep II, Sleepga, and Sleepga II automatically request immediate Curaga II wake casts from both Smalls and Achoo around the affected melee pack. Enemy adds themselves are not treated as sleepable.',
        'Reraise is maintained best-effort without gating combat. Smalls and Achoo cast Reraise; Dolo, Tackle, Kick, and Barney automatically use the first available Instant Reraise III, Super Reraiser, Hi-Reraiser, Instant Reraise, or Reraiser from Inventory. Current inventory diagnostics found none for those four, so give each one usable item before expecting that lane to succeed.',
        'GearSwap remains the sole equipment and instrument owner. The adapter has explicit pass-through hooks: manual target changes, attacks, ranged attacks, weapon skills, spells, abilities, items, and emergency intervention always remain available while the profile runs.',
        'PartyTactics emits exact directed transitions when an assignment changes, for one stalled-acquisition or arrival-drift repair, or during a short parked-add pickup. It does not broadcast adapter cancel during add deaths, so local reactive Utsusemi remains live. PartyCombat retries only against the known pre-transition battle target for its bounded handoff and yields to unrelated manual targets.',
        '//pc localstop cancels one client instantly. //pt arm and //pt disarm work from any named profile member; direct profile aliases arm automatically, and //pt arm reasserts that state after a stop or missed bind. Use these controls instead of direct //pc on. A deliberate broad //pt force remains available only on Dolo.',
        'Smalls has one serialized Qutrub-only exact cure lane through 74% HP. The runtime selects the lowest living member within known 20.5-yalm range and the pinned adapter revalidates that target before choosing a ready Cure tier. While an eligible member is yellow or worse, shared RDM upkeep and coordinator tactics yield instead of colliding with that cast.',
        'Repeated Smalls tactical refreshes coalesce by action and subject while healing, so a prolonged recovery cannot create a stale post-recovery queue.',
        'PartyStart may spend one immediate generic activation action, normally Composure. Thereafter the pinned adapter reserves automatic ticks for one Shellra (or five individual Shell fallbacks) and five Protects before the immutable Sortie/Acuex helper resumes five Hastes, four Refreshes, four frontline Phalanxes, Gain-MND, Aquaveil, Reraise, and guarded Convert. Adapter-owned Protect preserves a 35% post-cast MP floor.',
        'After a completed Convert, the pinned adapter reserves Smalls\' next automatic actions for self-Cure until at least 90% HP or for at most twenty seconds. This profile-local recovery never filters a manual spell, ability, item, target, movement, or weapon skill.',
        'At 40% or lower Tackle independently queues a delayed Cure IV backup for the exact lowest member within known 20.5-yalm casting range in every phase. Its adapter cancels that request if the member recovered, died, left range, or lacks target geometry. Achoo does not duplicate routine cures and retains the independent Curaga II wake response.',
        'A temporary yellow/unclaimed Bigwig no longer ends the bound encounter. Bigwig death, zone departure, Alt-P, or //pt disarm clears encounter tasks and PartyCombat state; the profile-local RDM cure/defense lane deliberately remains available before and after combat. //pt off or profile replacement deactivates that support too. Re-arm whenever you want; no reload or diagnostic pass is required.',
    },
}
