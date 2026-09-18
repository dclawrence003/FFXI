# Migration matrix

This matrix is the current regression checklist for PartyTactics 0.11.2. It
records profile boundaries and controller ownership; encounter evidence remains
in each profile's `research.md`.

## Current profile contracts

| Alias | Stable profile id | Version | Origin |
|---|---|---:|---|
| `locus` | `locus-dire-bats-tomb` | 1.3.0 | PartyStart migration, then isolated safety/support revisions |
| `limbus` | `limbus-119-stationary` | 1.2.0 | PartyStart migration, then explicit exclusion/support/artifact revisions |
| `v1` | `ambuscade-2026-08-v1-breadwinner` | 1.1.0 | August 2026 PartyStart encounter migration, then support revision |
| `ddw1route` | `dynamis-divergence-wave1-route-corsair` | 1.2.0 | Native PartyTactics strategy |
| `ddw1boss` | `dynamis-divergence-wave1-boss-magic` | 1.2.1 | Native PartyTactics strategy |
| `genmei` | `escha-ruaun-genbu-genmei` | 2.7.0 | Successful-run refinement with completion-confirmed Presto/Box Step, an opening Thunder Shot insurance request, queued intended Savage Blade, and bounded Lightning reactions |
| `kammavaca` | `escha-ruaun-kammavaca` | 1.2.0 | Native PartyTactics strategy, then live-driven non-blocking automation revision |
| `qutrub` | `ambuscade-2026-09-v1-qutrub-bigwig` | 1.1.0 | Native PartyTactics September V1 strategy; v1.1 moves Cait Sith off GEO's luopan slot using a new pinned adapter |
| `qutrub-nocait` | `ambuscade-2026-09-v1-qutrub-bigwig-no-cait` | 1.13.0 | Normal-validated alternate; arming prepares in place until the manual pull, then sequential spawns receive ownership-confirmed unique anchors before atomic Astrologer-first handoffs, with ordered Dia/Light Shot, focus-only Wail stripping, profile-local exact healing, and recast-aware shadows |
| `hydra` | `ambuscade-2026-09-v2-hydra-alluttu` | 1.0.0 | Native PartyTactics September V2 strategy with packet-confirmed shield/head-pressure loop |
| `rancibus` | `vagary-direct-rancibus` | 1.1.0 | Cooperative direct-Vagary strategy with hidden-HPP-safe identity, independent lanes, and unfiltered manual control |
| `sortiec` | `sortie-objective-c-device-kill-v1` | 1.0.0 | Cooperative single-objective Sortie policy: manual pull/positioning, inert load, stationary all-six force, and unrestricted operator control |

## Migrated strategies

| Concern | Locus Dire Bats 1.3.0 | Limbus 119 1.2.0 | Ambuscade V1 Breadwinner 1.1.0 |
|---|---|---|---|
| Movement | Stationary | Stationary | Mobile |
| Puller/target source | Tackleberry | Tackleberry | Tackleberry |
| Attackers | All six | All six | Everyone except Barney |
| Target-only clients | None | None | None; Barney is free-look and not a targeter |
| Target exclusions | Explicitly none | Whole-word `elemental` | Explicitly none |
| COR | Corsair + Samurai | Chaos + Samurai | Chaos + Samurai |
| BRD preset | `locusbats` | `limbus` | `ambuscade-v1` |
| RDM preset | `locusbats-protect`; Protect first, Shell Off | `limbus-protect` | `ambuscade-v1-protect` |
| GEO | `leanmanaged`; Fury/Frailty, Refresh -> Tackle | `leanmanaged`; Fury/Frailty, Refresh -> Tackle | `leanrrmanaged`; Fury/Frailty, Wilt -> Tackle, Reraise mode |
| PLD/DNC presets | `locusbats` / `locusbats` | `limbus` / `limbus` | `ambuscade-v1` / `ambuscade-v1` |
| Manual action | None | One pack sleep to Barney | None |
| Runtime mechanics | None | None | Warbles, Housemaker movement/Earthshaker, Drill Claw, Hundred Fists |
| EasyFarm | Profile-owned one-target `.eup`; manually loaded | Profile-owned reviewed 14-target `.eup`; manually loaded | None |
| Reraise guard | No | No | Yes |

All three profiles install a complete PartyCombat policy but never arm it.
Every profile explicitly emits its target-exclusion state to PartyCombat and
AutoWS2, so Limbus's Elemental rule cannot leak into Locus or V1. The protected
RDM and managed GEO names are isolated opt-ins: the legacy unsuffixed controller
presets retain their prior behavior.

The Locus and Limbus EasyFarm artifacts are stored under their respective
profile directories. Locus allows only `Locus Dire Bat`. Limbus allows the 14
reviewed Limbus enemies (Om', Uptala, and Apollyon), retains a whole-word
Elemental ignore rule, and contains no Apex or Locus XP-camp name. Both use
18-yalm detection, one Flash pull action at 20 yalms, and no approach.
PartyTactics declares and tests these artifacts but never loads, starts, stops,
or rewrites EasyFarm.

## Dynamis-D Wave 1 strategies

| Concern | Route 1.2.0 | Boss 1.2.1 |
|---|---|---|
| Movement | Manually positioned; stationary ranged COR | Mobile PLD + COR |
| Puller/target source | Dolomedes | Tackleberry |
| Attackers | Dolomedes | Dolomedes, Tackleberry |
| Target-only clients | None | Kickpuncher, Smalls, Achoo |
| Target exclusions | Explicitly none | Explicitly none |
| COR | Tactician + Wizard, automatic 1500-TP Leaden | Samurai + Wizard, manual Leaden/Wildfire |
| BRD | Explicitly Off | `magicboss`, cure/NA-only HealBot, guarded fourth Ballad |
| RDM | Explicitly Off | `magicboss-protect`: Protect/Shell/Haste/Refresh/Phalanx, cures, bounded debuffs |
| GEO | Explicitly Off; optional one-shot Acumen | `leanrrmanaged`: Acumen/Malaise, Refresh -> Tackle, cure/NA-only HealBot |
| PLD/DNC | Explicitly Off | `manualsc` with native buff/tank loops Off / `tankheal` |
| Combat arming | One selected statue at a time | After the manual PLD pull |
| AutoWS2 | Dolo only | Off on both attackers and the manual fallback |
| Target-only manual offense | None | Kick's Tauret/Rudra intent; operator must move and engage her manually |
| Kill boundary | Disarm between targets | Disarm before Wave 2 acquisition |

The boss fallback demonstrates the target-only manual-offense contract. Kick's
`automatic=false` offense selects a reviewed weapon and permits a typed Rudra's
Storm request, but it does not make her a PartyCombat attacker. No movement,
facing, engagement, or automatic WS permission follows from that declaration.

## Escha - Ru'Aun Genbu / Genmei Shield 2.7.0

| Concern | Genmei policy |
|---|---|
| Movement | Stationary; begin clustered for Barwatera, then face Tackle away, put Kick at the rear, and keep Dolo/Barney/Smalls/Achoo together roughly 11-14 yalms from Genbu—inside support range but beyond target-centered Waterga |
| Puller/target source | `//pt arm`/Ctrl-P engages immediately after binding one exact live Genbu ID; Tackle's independent Sentinel/Crusade/Divine Emblem/Flash/Provoke lane and GEO work are best-effort, never prerequisites |
| PartyCombat attackers/targeters | Tackleberry and Kickpuncher attack; Smalls is an additional target-only observer for native RDM debuffs |
| Cooperative ranged client | Dolomedes receives two bounded local startup engage edges, then one best-effort opening Thunder Shot, independent ranged attacks, and packet-coordinated Last Stand; an observed same-edge Invincible merges with that opening request; Triple Shot follows on the next legal action and advances only from a successful completion; Invincible holds ordinary `/ra` for eight seconds so queued Thunder Shot has an action window; PartyCombat never persistently moves, faces, targets, or re-engages him |
| Support clients | Smalls receives selection only; Barneystinson and Achoo remain outside PartyCombat targeting |
| Target exclusions | Explicitly none |
| COR | Warlock (roll1, restored first after Tortoise Song) + Samurai |
| BRD | Frozen generic `magicboss` songs with HealBot off; the pinned Genmei adapter privately prepares Barwatera and makes one bounded renewal near seven minutes, leaving Barney's MP and action lane for song recovery |
| RDM | Frozen generic `limbus-protect`: one Protect/Shell pass, Haste/Phalanx, Refresh on Smalls/Achoo/Tackle only, 50% backup healing, Dia maintenance, and up to three inherited best-effort Silence attempts per detected coverage cycle; HealBot keeps NA enabled while the Genbu adapter ignores only unerasable Weight |
| GEO | `leanmanaged`: Indi-Acumen, Geo-Malaise, Languor -> Tackle; precombat Entrust permitted; HealBot off; runtime nudges Malaise once and leaves renewal to native AutoGeo |
| PLD/DNC | Frozen generic `manualsc` loadout with broad native PLD buff/tank loops Off; coordinated Savage Blade queues through a current Majesty cure but never suppresses healing for low TP/range/disengagement/backoff; Genbu's generic DNC helper is Off while profile-local TP-aware Samba and completion-confirmed Presto/Box Step remain. Presto gets two attempts inside five seconds, then Box Step fails open; a miss retains live Presto and the skillchain always has priority |
| Subjobs | Dolo COR/THF for native TH2, Tackle PLD/WAR, Kick DNC/WAR, Barney BRD/WHM, Smalls RDM/WHM, Achoo GEO/BLM |
| AutoWS2 | Off for Dolo, Tackle, and Kick; the Genbu-only runtime owns bounded exact-ID WS requests so unrelated AutoWS2 profiles are unchanged |
| Check | Optional read-only gear, item, key-item, buff, action, and controller report; no automatic check and no result authorizes or blocks combat |
| Skillchain/burst | Actor-checked, successful-result-observed Evisceration -> queued Savage Blade -> Last Stand, or Savage Blade -> Last Stand when Kick is not ready; 3.1-second steps, local fail-open timeouts for missing/missed/failed steps, standalone Dolo fallback, and observed Light schedules dual bounded next-legal Thunder IV; no extra post-burst Savage lane |
| Reactions | Invincible cancels a queued physical WS, clears pending Presto state, schedules next-legal Thunder Shot plus dual low-MP Thunder, and gives Quick Draw an eight-second `/ra` window; physical WS normally holds 30 seconds, but an actually observed positive physical result may safely release it sooner. Proven-resistant Harden Shell/Shell V removal is omitted; Dia III plus accelerated Sluggish Daze supply up to 43.31% Defense Down, while Shield Bash dispel stays dormant until Tackle owns Caballarius Gauntlets +2 or better. Tortoise Song gets encounter-unique song/roll recovery |
| Runtime | `//pt arm` starts immediately. No readiness result or action result authorizes combat; only the small WS lane observes prior WS packets, and its timeout cannot stop another lane or manual input |
| Manual boundary | Adapter pretarget/precast hooks never consume input; targeting, attacks, ranged attacks, weapon skills, spells, abilities, items, and emergency recovery stay available |
| Kill boundary | Disarm, claim loss, victory, replacement, or zone change clears only this profile's pending work |

## Direct Vagary: Rancibus 1.1.0

| Concern | Rancibus policy |
|---|---|
| Scope | Single direct Ra'Kaznar Turris Rancibus; no Brash Gate route, waves, adds, columns, or proc logic |
| Movement | Stationary; user wall-tanks/faces with Tackle, places Kick at rear, keeps Dolo/Barney in support range, and moves characters out of poison fields/knockback |
| PartyCombat attackers/targeters | Tackleberry and Kickpuncher only |
| Cooperative ranged client | Dolomedes receives one exact local engage request, then independent ranged attacks and Last Stand without a persistent PartyCombat target lock |
| Support clients | Barneystinson, Smalls, and Achoo are never PartyCombat targeters |
| COR | Chaos + Magus; Death Penalty ranged attacks and Last Stand |
| BRD/RDM/GEO | `magicboss`, `magicboss-protect`, and `leanrrmanaged`; cure/NA support continues while independent fixed requests cover Barwatera/Barsilencera, recurring RDM debuffs, and Geo-Frailty |
| DNC | Frozen helper runs heal-only `tankheal`; independent fixed requests cover No Foot Rise, Box Step, Violent Flourish, and Evisceration without filtering manual DNC actions |
| Subjobs | Dolo COR/DNC or COR/NIN; Tackle PLD/WAR; Kick DNC/WAR; Barney BRD/WHM; Smalls RDM/WHM; Achoo GEO/WHM |
| Check | Optional report for zone, Echo Drops, buffs/actions/controller, and Dolo's gun/bullets; no ACK, PASS, check, or controller reply authorizes combat |
| Pull | Fresh `//pt arm` starts immediately and sends one best-effort Flash while every other preparation and damage lane advances independently |
| Damage | Independent `/ra`/Last Stand, Evisceration, and Savage Blade lanes; no ordered skillchain, party-HP hold, support hold, or packet-confirmation transaction |
| Action ownership | Profile automation uses fixed bounded requests; the 1.1 adapter installs no pretarget/precast filter and never rejects manual fight actions |
| Reactions | Best-effort stuns, Rampart, debuffs, bars, Geo-Frailty, and recovery are independent lanes; failure in one never pauses offense or another response |
| HPP | Enemy HPP is never read for binding, phases, victory, or shutdown; the exact name/ID/party-claim route handles the hidden gauge |
| Isolation | Own profile/runtime/research/new adapter version; all 1.0.x adapters remain unchanged, and no character GearSwap or instrument logic is touched |

The stable `PartyTactics_Host.lua` must be present once at the end of every
character's job Lua. Genmei loads only its 2.7.0 adapter and Rancibus loads only
its 1.1.0 adapter; older siblings remain immutable. Each semantic request stays
bound to one exact encounter ID and passes through normal GearSwap handling.
The host, adapters, and runtimes expose no equipment API. Missing or different
live copies are reported as setup warnings and do not create a permission gate
for working clients or unrelated lanes.

## Escha - Ru'Aun Kammavaca 1.2.0

| Concern | Kammavaca policy |
|---|---|
| Movement | Mobile only after an explicit Dolo target handoff |
| Puller/target source | Tackleberry tanks; Dolomedes calls each ordered target |
| Attackers | Dolomedes and Kickpuncher automatic; Tackleberry and Achoo engaged with AutoWS2 Off |
| Target-only clients | Barneystinson and Smalls |
| Target exclusions | Explicitly none; safety comes from single-target actions and explicit handoffs |
| Required order | `Kammavaca's Clionid` -> `Kammavaca's Limule` -> `Kammavaca's Murex` -> `Kammavaca's Amoeban` -> Kammavaca |
| COR | Chaos + Samurai; DualSavage/Savage Blade |
| BRD | Generic `physical` March/Minuet/Madrigal controller; exact-live-ID Horde Lullaby II before engagement; cure/NA-only HealBot |
| RDM | Generic `magicboss-protect` Protect/Shell/Haste/Refresh/Phalanx/healing core; typed Stymie/Saboteur/Elemental Seal/Sleepga plus exact-live-ID Silence/Stun |
| GEO | `leanrrmanaged`: Fury/Frailty, Fend -> Tackle, cure/NA-only HealBot, profile-opt-in native AutoWS disable |
| PLD/DNC | `manualsc` defensive tank / generic `physical` support |
| Subjobs | Barney BRD/WHM; Smalls RDM/BLM preferred or /WHM fallback; Achoo GEO/WHM |
| Check | Optional lens, binding, Echo Drops, Dolo range-slot, equipment, and action report; never a combat gate |
| Runtime | Automatic exact-ID CLMA progression plus Chainspell and Exponential Burst alerts |
| Kill boundary | Native auto-target Off for the fight; disarm after every invalid/lost target and immediately on victory; restore auto-target On afterward |

Kammavaca does not add an ordered-target feature to PartyCombat. Its profile
runtime owns the fight-local CLMA order and supplies each exact eligible target.
The exact-enemy action resolves only the whitelisted live server ID, then
submits the spell through GearSwap so Barney retains sole instrument ownership.
Sleep and Silence are best-effort support lanes, not prerequisites for force or
damage.

## September 2026 Ambuscade

| Concern | V1 Qutrub / Bigwig 1.1.0 | V2 Hydra / Alluttu 1.0.0 |
|---|---|---|
| Arm boundary | Direct profile alias selects and arms automatically; Ctrl-P / `//pt arm` reasserts after a stop or missed bind | Direct profile alias selects and arms automatically; Ctrl-P / `//pt arm` reasserts after a stop or missed bind |
| Pull | Tackle's ordered self-buffs and packet-confirmed exact Bigwig Flash | Tackle's Crusade/Divine Emblem/Sentinel and packet-confirmed exact Alluttu Flash |
| Attackers | Dolo, Tackle, Kick | Dolo, Tackle, Kick |
| Target policy | Every Astrologer, then either exact Tormentor spelling, then Bigwig | Exact Alluttu only |
| COR / BRD / GEO | Chaos + Hunter / three physical songs plus opportunistic Clarion Minne / Fury + Frailty | Chaos + Samurai / three physical songs plus opportunistic Clarion Minuet / Fury + Frailty |
| Subjobs | COR/NIN, PLD/NIN, DNC/NIN, BRD/SMN, RDM/SMN, GEO/WHM | COR/DNC or /NIN, PLD/WAR, DNC/WAR, BRD/WHM, RDM/WHM, GEO/WHM |
| Skillchain | Exact-subject Evisceration -> Savage Blade/Fragmentation -> Last Stand/Light | Evisceration -> Savage Blade/Fragmentation -> Last Stand/Light -> dual Thunder IV |
| Primary mechanics | Kill all adds first, Silence Astrologers, BRD/SMN + RDM/SMN confirmed Mewing TP suppression plus non-blocking Retreat during add packs without displacing GEO's luopan, three shadowed attackers, Diaga after Utsusemi: San, then guarded 13-25% attacker HP and enforced support geometry below 30% | Numeric ready/completion reactions, Violent Flourish/Shield Bash, Polar magic fallback, Pyric physical-only hold, recovery priority |
| AutoWS2 | Off; pinned adapter owns each bounded transaction | Off; pinned adapter owns each bounded transaction |
| End boundary | Cancel all queues, stop PartyCombat, release authority, consume arm | Cancel all queues, stop PartyCombat, release authority, consume arm |

`v1` remains the immutable August Breadwinner alias. September V1 is selected
with `qutrub`, its independent no-Cait alternate with `qutrub-nocait`, and
September V2 with `hydra`. All accept the exact boss only in Ambuscade zones
183 or 287. GearSwap remains the sole owner of weapons, ammunition, instruments,
and action sets.

The no-Cait Qutrub contract is deliberately separate rather than a weaker mode
inside `qutrub`:

| Concern | V1 Qutrub / Bigwig no-Cait 1.13.0 |
|---|---|
| Subjobs | COR/NIN, PLD/BLU, DNC/NIN, BRD/NIN, RDM/WHM, GEO/WHM |
| Strategy PLD/BLU set | Cocoon (1), Blank Gaze (2), Sheep Song (2), Geist Wall (3), Jettatura (4): five slots and 12 set points; Flash is native and `//pt check` reports missing spells without locking controls |
| Pull and attackers | Direct `//pt v1-qutrub-nocait` selects, arms, and starts non-hostile preparation automatically. No combat assignment, movement, enemy-targeted spell, or enemy-targeted geomancy is issued until Dolo's exact manual Bigwig action, the party claim, or Bigwig retaliation is observed; that edge releases combat without another command. With no adds, PartyCombat sends Dolo/Kick/Barney to Bigwig and stops directed-only Tackle/Achoo. On a wave, all boss damage pauses while sequential spawns receive unique anchors; Dolo/Tackle/Kick/Barney/Achoo then attack one Astrologer-first focus—including the current Bigwig holder |
| Pull geometry | There is no proximity-based enemy defense. Bigwig may follow its Dolo/Kick holder into the add focus; 10-15 yalms is an initial convenience, not a persistent split or software condition. Three-add area enmity is suppressed rather than enforced through cross-room placement |
| Tackle boundary | Directed-only PartyCombat attacker with Naegling/Diamond Aspis and AutoWS2 Savage Blade; never a broad Bigwig actor. On Normal he briefly establishes one parked Tormentor, then joins the focus and uses exact Flash/Gaze only on that parked target |
| Capture proof | An attempted Flash, Light Shot, Step, or Flourish never proves hate. Only the add's own direct melee/primary-TP target confirms its assigned owner. Unique anchors remain through fixed quiet assembly; afterward, that evidence releases the owner early while an absent result can extend only that owner's exact pickup to the eight-second bound. Neither state gates activation or manual input |
| Every add generation | Tackle anchors the first Tormentor, Achoo /WHM Flashes the Astrologer, and the Dolo/Kick nonholder anchors the second Tormentor. Every newly visible spawn restarts a 6.25-second quiet interval. Released lanes then focus together; an unconfirmed parked owner remains only through its bounded pickup. Dolo uses one Light Shot and Kick one Box Step per pickup episode instead of an ability retry loop. Recycled slots begin a fresh generation. Bigwig target evidence is reviewed every five seconds and transfers only the second parked owner |
| Triple budget | Tackle and the nonholder each receive parked add + focus; the holder receives Bigwig + focus; Barney and Achoo receive focus only. No intended actor exceeds two hostile targets, and Bigwig counts toward Triple Reversal. A direct-target ledger temporarily stops an observed three-foe victim until exact anchors redistribute hate |
| Damage support | Packet-confirmed Dia III on the active focus enables only then one same-target Light Shot; missing/failure results retry Dia at most three times. An executed shot ends the nonstacking enhancement cycle even when its separate Sleep component misses; only no-action-packet shot submissions may retry. Achoo carries Indi-Fury, places exact Frailty, and uses Black Halo. Fortifying and Animating Wail wait until their recipient is the common focus, then Tackle exact Blank Gaze and Smalls exact Dispel alternate until removal is confirmed; no three-add area strip is used |
| Healing, wake, shadows, Reraise | Smalls' profile-local adapter selects the exact lowest living member within known 20.5-yalm range through 74%, before bind through post-fight, and de-duplicates the bound runtime request. It chooses a ready Cure tier with no arbitrary MPP reserve and reserves post-Convert automatic actions for self-recovery. Timestamped Smalls tactics coalesce by semantic/subject while healing, preventing a stale recovery queue. PartyStart may spend one immediate activation action, normally Composure; from the next automatic tick, one Shellra or individual Shell fallback and five living-target Protects complete before subsequent immutable `sortieacuex` upkeep. Ordinary shared ticks wait at 30-34% MPP and frontline Phalanx retains its conservative 20% floor. Tackle independently backs the exact lowest member at 40% or below after 1.25 seconds in every phase; dead, recovered, missing-geometry, and known out-of-range targets are skipped. Achoo preserves MP for colures/offense but retains bounded Curaga II wake. Local adapters inspect Utsusemi recasts and fall back immediately to Ichi at zero images; both mages cast Reraise and the other four use the best owned item without a gate |
| Wilt caveat | Qutrub are Weight immune. Enemy-targeting Indicolure requires GEO and anchor on enemy hate; Achoo eligibility on adds is inferred from earlier Frailty and inherited spawn hate, so observed physical mitigation remains evidence—never an arm or damage gate, and no GEO Diaga is added |
| DNC/response boundary | Native DNC automation off. Routine exact pickup waits for known melee arrival, then uses one Box Step to tag and create finishing stock. Violent Flourish is reactive only; the local adapter verifies at least one finishing-move buff and recast 221 before submitting it. Missing resources are immediate no-ops, and a server no-stock result opens a ten-second automatic backoff without filtering manual actions |
| Weapon skills | AutoWS2 alone owns Dolo Last Stand, Tackle/Barney Savage Blade, Kick Evisceration, and add-only Achoo Black Halo. Exact target-change plus completed direct-attack evidence resolves a numeric server ID, avoiding transient `<bt>` leakage; the runtime submits no WS or skillchain |
| Validation | No software lock. A 2026-09-15 v1.12.0 Normal clear had zero deaths, 104 completed weapon skills, zero add-wave weapon skills on Bigwig, and five of five Phantom Whorls absorbed by shadows. Add waves were highly repeatable, though one transient three-target convergence on Kick required the intended safety stop. v1.13.0 changes only the pre-pull boundary so the direct alias prepares in place until the manual pull; one more Normal validation and a restored Achoo capture are recommended before Difficult |

## Cross-profile invariants

- Direct aliases and `//pt use <profile>` select and arm by default. An explicit
  `//pt use <profile> inert` keeps setup stopped when a profile requires it;
  `//pt arm`/`//pt disarm` are signed immediate controls accepted from any
  active profile member, while `//pt force` remains leader-only. None consults
  an ACK, check, item, equipment, buff, or controller result.
- Automatic boss profiles may use the operator arm state as a simple start/stop
  switch. Disarm, encounter release, zone reapply, and replacement clear it so
  a later target does not start accidentally.
- Prepare compares engine/profile identity and the complete behavior
  fingerprint. Compatible available clients proceed after the bounded window;
  unavailable or incompatible clients are reported and skipped.
- Application ACKs describe which clients applied the current epoch. They are
  diagnostics only and never authorize arm, force, adapter requests, or manual
  actions.
- `//pt check` is an explicit read-only diagnostic. It issues no setup command,
  schedules no retry, and cannot block combat or manual input.
- A runtime or job failure pauses only the affected local lane; healthy clients
  and independent strategy lanes continue.
- Every target-exclusion array is explicit, including empty arrays that reset
  PartyCombat to no exclusions and AutoWS2 to `none`.
- All GearSwap controllers are invoked through reviewed public command
  surfaces. No profile, runtime, or manual adapter performs an equipment
  operation. Barney's native GearSwap remains the only instrument owner.
- The PartyStart add-on remains unloaded. Locus, Limbus, and V1 use only their
  frozen generic `PartyStart_*` GearSwap compatibility helpers; those
  historical library names are not an orchestrator dependency.
- New fight-specific GearSwap behavior is pinned by adapter id and version.
  The stable host joins every profile fingerprint because it wraps every job
  callback; only the exact selected fight adapter joins its owning profile, so
  adding a sibling adapter cannot change another fight's closure.
- A new or rebuilt cooperative adapter never filters pretarget/precast input.
  Automated requests are bounded and independent; a failed, delayed, resisted,
  or unavailable request cannot suspend another lane or manual intervention.
- Adapter-free profiles explicitly deactivate the stable host before applying
  support state, preventing a stale fight adapter from surviving a coordinator
  crash or reload into an older profile.
- Public ids, aliases, and PartyCombat policy ids have append-only ownership.
  A later conflicting registry entry is quarantined without disabling the
  established profile or shortcut.
- EasyFarm and FastFollow remain user-owned. A profile may carry a reviewed
  EasyFarm artifact and metadata, but PartyTactics does not mutate or start the
  external add-on.
- A new profile or runtime is contained in its own directory. Shared behavior
  is extended only through additive capabilities or isolated preset names;
  existing profile contracts never acquire a fight-id branch.
