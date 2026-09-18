# Changelog

## Locus Signet COR dual-wield offense - 2026-09-17

- Revised only the Locus Signet profile to 1.8.0. Dolomedes now selects the
  existing `DualEvis` Tauret/Gleti's Knife pair and Evisceration at 1000 TP.
  /DNC or /NIN enables the offhand; subjobs remain recommendations rather than
  profile-application gates.
- Added an append-only, behavior-identical 1.8.0 adapter pin. The 1.7.0
  adapter and ordinary Locus profile remain unchanged.

## SignetKeeper reload containment and cycle recovery - 2026-09-16

- Updated SignetKeeper to 2.3.2 after a simultaneous remote reload caused five
  `pol.exe` AppHangB1 terminations under 2.3.0. The hang was a recursive
  cross-process disarm broadcast from inside each addon's unload callback.
- Raw addon unload is now strictly process-local: it restores owned weapon
  slots and conditionally resumes only its local adapter, but emits no IPC
  while Windower is destroying the Lua state.
- A received terminal disarm is consumed once and never rebroadcast from
  inside the IPC callback. Missed terminal delivery remains fail-closed and is
  repaired by the bounded controller-lease/roster-state expiry path.
- Added a five-client simultaneous-unload regression and a consume-only remote
  disarm regression.
- Revised only `locus-dire-bats-tomb-signet` to 1.7.0 and added its append-only
  adapter. Every loaded SignetKeeper presents a process-local monotonic nonce.
  A surviving adapter detects a changed nonce, applies the complete local OFF
  baseline, rebinds the fresh keeper to the exact old authority, and enters the
  existing leader-coalesced full-profile recovery path. Six simultaneous
  reload notices therefore produce one successor generation instead of six
  competing replacements.
- Recovery retries every three seconds inside one fixed twenty-second window,
  preserves the exact revisioned Ctrl-P/Alt-P state, rejects delayed or equal
  nonce replays, and remains terminally OFF if recovery cannot complete. The
  successor starts Signet maintenance again at cycle one without weakening
  stale-cycle validation. Historical adapters and shared combat code remain
  unchanged.

## Locus Signet fast-pull version repair - 2026-09-16

- Updated only LocusPuller to 2.1.8. The Signet profile advanced to 1.7.0,
  but the puller's fast-gate version allowlist stopped at 1.6.0. Consequently
  the active profile used the legacy three-second first-melee deadline and
  two-second failed-opener retry delay. Added 1.7.0 to that allowlist without
  changing its strategy or another profile.
- A focused 1.7 runtime regression now proves the twenty-second first-melee
  window and immediate retry; the old 1.3 behavior remains separately tested.

## Locus Signet physical weapon restoration - 2026-09-16

- Updated only the dedicated SignetKeeper companion to 2.3.0. PartyTactics,
  PartyCombat, GearSwap job files, the Locus profile, and every pinned adapter
  remain unchanged.
- The live trace proved Signet restoration could release combat after a single
  `gs c update` even while Dolo still physically held the Signet staff. The
  staff survived one complete five-hour Signet period and the next renewal
  until a manual F7 weapon cycle corrected it.
- Before staff ownership, each client now snapshots its raw main/sub item IDs.
  After Signet returns, SignetKeeper asks GearSwap to reapply its current
  Weapons mode, retries every two seconds, and requires one continuous second
  of exact raw main/sub restoration. Signet alone can no longer release the
  adapters or puller.
- Added a deterministic no-op GearSwap restore simulation proving retries,
  exact main/sub verification, and zero resume/puller release while the staff
  remains equipped. GearSwap remains the sole owner of all normal gear.
- Resume edges, teardown, reload handoffs, and same-generation reapplies now
  retain the same physical postcondition. Wrong-sub, unreadable-slot, no-op,
  delayed-successor, and raw-unload failure injections cannot reopen automatic
  lanes. An unexpected staff in an active monitor epoch immediately drains the
  puller, suspends the exact adapter, and begins the normal maintenance cycle.
- A replacement epoch arriving during a hard maintenance suspension now starts
  a fresh exact emergency cycle even when main/sub were already restored. The
  replacement adapter cannot advertise itself as running in the gap between
  reapply and replicated phase repair. Ordinary drain still lets the current
  fight finish. Terminal teardown also fences both an armed predecessor and
  its already-authorized successor companion.
- Idle SignetKeeper remains fully inert: a manually equipped Signet staff is
  untouched by prerender, emergency-off, zone, logout, or unload events.

## Sortie Leshonn common-denominator safety - 2026-09-15

- Revised the persistent Sortie profile and its append-only adapter to 1.2.0.
  Exact Leshonn selection now stages a fight-local safe mode without engaging,
  moving, stopping, or spending TP. Any configured member may still improvise
  a pull; the target actually attacked wins immediately.
- Leshonn now uses a dedicated five-WS lane: Savage Blade and Black Halo only.
  Kick continues melee and Box Step but holds automatic WS, preventing the
  Evisceration-to-Savage Fragmentation that would heal either hand form.
- The safe policy is shared across both random opening forms. BRD/RDM schedule
  no persistent debuffs, native PLD Flash/Sentinel automation is disabled,
  GEO bubbles and Box Step remain, and manual actions are never filtered.
  Confirmed TP-move families refine telemetry and optional `/DRK` Last Resort
  only; uncertain form transitions never relax the safety policy.
- Revised the explicit recovery Leshonn profile to 1.1.0 with the same
  no-debuff/no-native-tank contract. Shared PartyStart helpers, PartyTactics
  core, the GearSwap host, and every historical adapter remain unchanged.

## Qutrub inert pre-pull preparation and best-clear validation - 2026-09-15

- Revised only the no-Cait Qutrub profile to v1.13.0. The direct alias still
  selects and arms in one command, but a visible unclaimed Bigwig now binds
  into a non-hostile preparation state. Food, shadows, defensive buffs,
  Reraise, songs, and exact healing may continue; combat assignments,
  movement, debuffs, and enemy-targeted geomancy cannot begin until Dolo's
  exact manual action, the party claim, or Bigwig retaliation is observed.
  That observation releases combat automatically, with no second command,
  readiness check, ACK, buff requirement, or result gate.
- Reconstructed the 19:42-19:52 EDT Normal clear from PartyOps. It completed
  with zero deaths, 104 weapon skills, no weapon skill leaking from an add
  wave back to Bigwig, and all five Phantom Whorls absorbed by shadows. The
  two add waves were highly repeatable: Astrologers died 53-56 seconds after
  spawn and the final Tormentors at 115-121 seconds. Dia III preceded seven
  same-target Light Shots, and focus-only Blank Gaze/Dispel removed observed
  Wail defenses.
- One brief wave-one Bigwig + Astrologer + parked-Tormentor convergence on
  Kick triggered the intended lane stop within roughly four tenths of a
  second and cleared without Triple Reversal. Smalls converted once, healed
  himself immediately, and ended with MP remaining. Achoo's own PartyOps
  client was disconnected, so a further Normal validation with all six local
  streams and working non-mage Reraise items is recommended before Difficult.
- Added deterministic tests proving that arming alone emits no force/stop or
  enemy-targeted requests, a party claim releases combat, and Dolo's exact
  manual Bigwig action can release it before claim color catches up.

## Locus Signet unattended recovery hardening - 2026-09-15

- Updated only the dedicated SignetKeeper companion to 2.2.0 and LocusPuller
  to 2.1.7; revised the isolated Locus Signet profile and its append-only
  adapter to 1.6.0. No shared combat preset or historical adapter changed.
- The first staff command now waits 42.5 seconds of uninterrupted raw-equipped
  proof. This reflects the live cycle in which five clients' 30.5-second
  commands produced no action while each exact 12-second retry succeeded.
  Actual Signet remains the only success proof, retries continue indefinitely,
  equipment displacement restarts the timer, and decoded zero charges hold the
  transaction with rate-limited diagnostics.
- Renewal phase delivery, adapter suspension/restoration, reload handoff, and
  terminal cleanup now repair dropped messages. All six adapters must report
  restored before Tackle receives a repeated puller release, and pulling
  resumes only after LocusPuller acknowledges the exact cycle.
- PartyTactics' authenticated local operator reconciliation is the primary
  liveness lease. A stale controller or missing six-client report wakes any
  exact suspended lanes and retires automatic pulling instead of leaving
  weapons locked or helpers stranded OFF. Public LocusPuller controls cannot
  bypass a bound Signet transaction; local emergency OFF remains immediate.

## Locus Signet duplicate-resume delivery repair - 2026-09-15

- Revised only `locus-dire-bats-tomb-signet` to 1.6.0 and added its
  append-only adapter. Adapter 1.5.0 and every earlier version remain
  hash-frozen and unchanged.
- A duplicate exact Signet resume now reasserts the complete profile-owned
  automatic baseline: AutoWS2, COR Roller2 or RDM support when applicable, and
  the current ordered PartyCombat state. A partially delivered first resume
  can therefore be repaired without advancing the maintenance cycle.
- Suspend and resume return their exact proof to the local SignetKeeper through
  `sk __adapter`; they no longer rely on GearSwap addon-scoped IPC crossing an
  addon boundary. Every duplicate resume emits a fresh local acknowledgment.
- Added a full 1.6 adapter regression cloned from the 1.5 sustain suite, with
  explicit RDM/COR duplicate-repair and local-ACK coverage, and advanced the
  Locus profile/six-client activation expectations to 1.6.0.

## Signet drain bridge and acknowledgement retry - 2026-09-15

- Updated the dedicated SignetKeeper companion to 2.1.5 and LocusPuller to
  2.1.6. Windower IPC reaches remote instances of the same addon, so
  LocusPuller now hands completion to Tackle's local SignetKeeper first; that
  instance validates and relays the exact completion over SignetKeeper IPC.
  While a renewal
  remains in the exact `drain` phase, Tackle silently repeats the same
  generation/epoch/cycle drain request once per second. LocusPuller already
  treats that request idempotently and replays its cached completion, closing
  both a dropped local request and a dropped completion without stranding the
  party before any staff equips.
- No profile, PartyTactics core, PartyCombat, GearSwap adapter, combat action,
  buff policy, equipment policy, or other encounter changed.

## LocusPuller stationary facing - 2026-09-15

- Updated only the dedicated LocusPuller helper to 2.1.5. Tackle now turns
  toward the exact selected bat when the target is acquired and throughout
  the bounded post-Flash engage window, including pulls approaching from
  behind. The helper issues no movement or reposition command, and no shared
  PartyCombat, GearSwap helper, adapter, or other profile changed.

## Locus Signet profile-local PLD sustain - 2026-09-15

- Revised only `locus-dire-bats-tomb-signet` to 1.5.0 and added append-only
  adapter 1.5.0. Adapters through 1.4.0 and the shared/frozen `locusbats` PLD
  helper remain unchanged.
- Tackle now owns a profile-local Majesty cure lane while engaged: Cure III
  below 65% on the lowest in-range living member, Cure III when at least three
  members are below 70%, and Cure IV below 55% with Cure III fallback. Routine
  and cluster recovery hold below 30% MP; emergency recovery bypasses that
  reserve.
- The sustain lane yields completely to the bounded Flash opener and cannot
  issue a new cure while Tackle is idle between pulls. It uses party-slot
  targets, completion/target-aware pending leases, bounded retries, no Flash,
  no equipment control, and no manual-action filtering. The generic AutoTank
  loop and frozen PLD preset remain off, so LocusPuller retains sole ownership
  of Flash while native AutoBuff upkeep remains enabled.
- LocusPuller 2.1.4 applies the proven 1.4.0 exact Flash-confirmation and
  twenty-second first-melee path to 1.5.0 as well. The prior 1.4.0 path remains
  available unchanged for rollback.

## Qutrub profile-local RDM ownership - 2026-09-15

- Revised only the no-Cait profile to v1.12.0 and added append-only adapter
  1.10.0. The profile now pins the immutable `sortieacuex` RDM preset instead
  of depending on the unversioned `qutrubnocait` behavior in the shared
  PartyStart helper. Adapter 1.9.0 and every unrelated profile remain frozen.
- Smalls' exact cure lane is now profile-local and active anywhere in the two
  Ambuscade zones while this exact adapter is active, including before arm and
  after a fight finishes. It selects the lowest living in-range party member
  through 74% HP, chooses a ready Cure tier at dispatch, uses no arbitrary MPP
  reserve, and de-duplicates the encounter runtime's exact cure request. Both
  Smalls and Tackle skip dead, missing-geometry, and known out-of-range cure
  targets; deferred Smalls tactics coalesce by semantic and subject so a long
  healing interval cannot build a stale post-recovery action queue.
- The adapter owns one opening Shellra with individual Shell fallback, five
  living-target Protect casts, and the post-Convert self-recovery reservation.
  The immutable helper still owns Composure, Haste/Refresh/Phalanx, Gain-MND,
  Aquaveil, Reraise, and guarded Convert. PartyStart may spend one immediate
  activation action, normally Composure; from the next automatic tick the
  adapter completes Shell/Protect before subsequent routine helper upkeep.
  Shared routine ticks are withheld at 30-34% MPP, while the frozen helper's
  conservative 20% frontline Phalanx floor remains deliberately unchanged.
- Automatic scheduling consumes only its own GearSwap tick. Manual spells,
  abilities, items, targets, movement, attacks, and weapon skills remain
  unfiltered. Focused tests cover pre-bind cures, exact-lowest revalidation,
  cure-tier choice, duplicate suppression, range/death skips, Shell fallback,
  Protect reserve, Convert recovery, and the full runtime healing lane.
- Runtime tasks now carry an explicit hostile/party target domain, so an enemy
  focus transition retires only stale hostile work and cannot erase delayed
  Indi-Wilt, emergency Cure, or Curaga wake actions aimed at party members.
  Only timestamped periodic RDM work coalesces during healing; independent Ice
  Spikes and Wail Dispels remain separate, and a Wail retry is counted only
  when it actually leaves the coordinator.

## 0.13.3

- Revised only the isolated Locus Signet profile and its append-only adapter to
  1.4.0. Its PLD policy disables the generic native AutoTank loop while
  retaining native buff upkeep and the profile-local Majesty healing/cooldown
  controller. LocusPuller is therefore the sole Flash owner: Flash cannot be
  spent mid-combat and is ready for immediate post-kill acquisition. Adapter
  1.3.0 remains byte-identical and hash-guarded.
- PartyOps recorded 20 completed Flash-pull cycles: all 20 exceeded the old
  three-second first-melee window and the observed maximum was 16.462 seconds.
  LocusPuller 2.1.3 therefore uses a twenty-second first-melee bound and the
  isolated 1.4.0 adapter uses a thirty-second independent outer bound. These
  bounds reserve only automatic routines; manual actions remain unconditional.
- PartyOps also proved that some selected, adapter-acknowledged pulls submitted
  `/ma Flash` without producing an outgoing action packet. LocusPuller 2.1.3
  now confirms exact target/category/spell dispatch from outgoing `0x01A` and
  silently retries only the swallowed command during a bounded five-second
  window. A real Flash packet terminates retries immediately, and a fully
  expired attempt can reacquire on the next polling edge without an extra
  two-second reset delay.
- Rejected a delayed opener-reservation command if it arrives after a newer
  operator OFF. It can no longer suppress Tackleberry's automatic weapon
  skills after Alt-P or acknowledge an opener that LocusPuller has retired.
- Fixed the common command lifecycle: direct profile aliases now select and
  arm in one transaction, `//pt on` actually arms the selected/active profile,
  and `//pt reapply` preserves the existing operator arm state.
- Exact-target auto-selection no longer re-arms a profile after Alt-P or
  `//pt disarm`; an operator stop now remains authoritative.
- Revised only the isolated Locus Signet profile and its append-only adapter to
  1.3.0. The adapter no longer treats GearSwap activation as proof that its
  standalone companions accepted the lifecycle: every client must return an
  exact generation/epoch SignetKeeper binding, Tackle must also return
  LocusPuller, and Dolo must also return JubileeKeeper before controller ready.
- Pending startup silently retries the same authorization, binding, and proof
  query while retaining the newest Ctrl-P/Alt-P operator tuple. Helper load
  requests are capped at an initial attempt plus one repair, so recovery cannot
  create unbounded `already loaded` console churn. A stop that overtakes startup
  tombstones the authority and delayed companion acknowledgments cannot revive
  it.
- LocusPuller 2.1.2, SignetKeeper 2.1.3, and JubileeKeeper 2.1.2 expose only an
  exact private binding-proof query. They report the metadata they actually
  accepted, so adapter 1.2.0 remains frozen and future versioned adapters need
  no new helper-specific branch. Locus target validation now consistently
  accepts an otherwise valid target unless Windower explicitly marks it false
  and prefers current coordinate distance over a stale squared-distance field.
- Extended only adapter 1.3.0's outer Flash reservation to twelve seconds so it
  safely contains LocusPuller's legal eight-second Flash confirmation and
  three-second first-melee windows. Manual actions remain unconditional.

## Protocol-2 Ctrl-P pull ownership - 2026-09-14

- Kept the universal Ctrl-P binding on `pt force`, but made protocol-2
  lifecycle profiles consume that edge through their ordered operator path.
  LocusPuller may therefore start without Dolo selecting a target, and a
  trailing raw `pc force` can no longer bypass Signet maintenance when Dolo
  happens to have an enemy selected. All legacy and protocol-1 profiles retain
  their existing force-current-target behavior.
- Simplified the arm response to `Profile ON requested` so a successful request
  is not presented as a current controller or suspension failure.
- SignetKeeper 2.1.1 now holds PartyCombat with silent local
  `pc reconcile off`. Equal state repair remains fail-closed during staff work
  without printing or broadcasting repeated disarm commands.

## Silent Locus combat-state convergence - 2026-09-14

- Removed PartyTactics' blind PartyCombat load requests at addon startup and
  profile commit. The supported init and safe reload paths already load that
  dependency first, so activation no longer produces false `already loaded`
  errors while policy invalidation and ordered combat convergence are unchanged.
- Revised the isolated Locus Signet profile and append-only adapter to v1.2.0;
  adapter v1.1.0 remains frozen. The strategy, aliases, support policy, Signet
  transaction, Jubilee ownership, and PLD opener are unchanged.
- PartyCombat 0.6.18 adds an internal, silent, local-only `reconcile on|off`
  surface. PartyTactics protocol-2 heartbeat and recovery traffic uses that
  surface, while an explicit Alt-P or `//pt disarm` still performs one
  immediate visible distributed stop from the requesting client.
- Equal revision heartbeats remain repair carriers for missed ON/OFF state,
  but no longer emit repeated PartyCombat arm/disarm lines or redundant IPC.
  Repeated OFF repair also leaves later manual combat untouched once the local
  automation state is already inert.

## Ordered Locus Signet operator protocol - 2026-09-14

- Revised the isolated Locus Signet profile and append-only adapter to v1.1.0
  with controller protocol 2; adapter 1.0.0 remains byte-identical and
  hash-guarded. PartyTactics is now 0.13.2 because prepare, commit, periodic
  state, and operator IPC carry a revisioned operator tuple.
- Revised the stable GearSwap host to 1.2.0 so its exact adapter metadata
  validator accepts pinned protocol 1 or 2 modules. Legacy protocol-1 adapters
  retain the same route; unsupported protocol values remain inert.
- Every named client contributes a monotonic source sequence, while Dolomedes
  alone allocates the authoritative party revision. Lower revisions are stale,
  equal/same tuples repair dropped local effects, and equal/conflicting bits are
  rejected. Periodic state and commit retries are valid recovery carriers.
- OFF applies locally immediately. ON received during controller loss, reapply,
  reload handoff, or Signet suspension remains intent only until the exact
  current controller proves ready. Reapply preserves the latest tuple instead
  of inventing an OFF transition, and recovery cannot restore an older ON.
- The adapter now pins revision/bit into strict SignetKeeper and LocusPuller
  bootstrap commands. Only SignetKeeper relays operator state to LocusPuller,
  after a fresh six-client census; the adapter never bypasses that startup
  hold. Stale maintenance resumes complete mechanically using the adapter's
  newer operator high-water without replaying an obsolete ON.
- Added focused adapter tests and six-client failure injection for delayed
  source requests, reordered leader broadcasts, dropped operator state repaired
  by periodic state, pending-commit carriers, stale prepares joining a higher
  epoch, reapply/controller gaps, conflicting equal revisions, and stale resume.

## Qutrub healing and exact-WS smoothing - 2026-09-14

- Revised the no-Cait profile to v1.11.0 after a successful Normal run exposed
  two remaining cross-scheduler races. Tackle and Barney were still attacking
  their assigned add, but transient `<bt>` resolution sent six automatic
  Savage Blades back to Bigwig. AutoWS2 0.3.6 now combines exact target-change
  packets with completed local melee/ranged evidence and submits automatic
  weapon skills to the resulting numeric server ID. Manual weapon skills are
  unchanged.
- Added the isolated `qutrubnocait` PartyStart RDM preset. Smalls is now the
  serialized primary healer at 75%, healing precedes all routine upkeep, and
  post-Convert recovery uses the same local scheduler. The fight coordinator
  defers only its own Smalls tactical work while a living member is yellow;
  manual input remains unrestricted. Tackle supplies the sole delayed 40%
  emergency backstop in every boss phase, removing the erroneous 12% final
  threshold.
- Replaced the physical preset's thirty-cast opening carousel with one
  Shellra, five Protects, five Hastes, four Refreshes, four frontline
  Phalanxes, and bounded self maintenance under a 35% routine MP floor.
  Exact Dia is now result-confirmed and retries up to three times before its
  one same-target Light Shot transaction can begin.

## Isolated Locus Signet sustain profile - 2026-09-14

- Added append-only profile identity 20,
  `locus-dire-bats-tomb-signet` 1.0.0, with the aliases `locus-signet`,
  `locusbats-signet`, and `signetbats`. The ordinary Locus profile remains
  byte-identical and retains its separate EasyFarm contract.
- Reused only the frozen Locus support presets and established offense. The
  derivative has no EasyFarm declaration: a generation/epoch-bound
  LocusPuller is its sole pull owner and follows the same Ctrl-P/Alt-P
  PartyTactics operator state as synchronized combat.
- Added pinned adapter 1.0.0 for companion lifecycle, Signet automatic-lane
  suspension, and a six-second fail-open Tackle Flash/first-hit reservation.
  It is the sole AutoWS2 owner for that reservation and honors terminal
  `keepoff` release without reviving the lane. The adapter consumes only
  automatic helper ticks (including a delayed PLD `subjobenmity` token), never
  filters manual actions, and never blindly re-arms PartyCombat.
- Added cycle-bound renewal messages and ACKs, hard zone-190 ownership checks,
  lifecycle-fenced generation/equal-or-higher-epoch probes, nil-player terminal
  teardown from cached probe identity, and state-aware opener release.
  Generation nonces remain opaque across processes; a different generation
  cannot replace bound authority outside the explicit reload handoff. Delayed
  probes, cycles, and opener traffic cannot replace current authority or revive
  automatic lanes.
- Outside-zone activation now remains host-visible only as an inert owner of
  one two-second terminal-OFF reassertion. It loads no companions, and a valid
  probe or profile deactivation cancels the adapter timer, preventing a delayed
  OFF command from leaking into a subsequently loaded profile.
- A standalone GearSwap reload now freezes persistent automatic lanes while
  the standalone keepers retain raw equipment ownership. Concurrent notices are
  coalesced into one exact controller-recovery request that starts a complete
  distributed PartyTactics reapply. An interrupted staff timer and renewal
  cycle restart safely at cycle 1. The live-updatable saved operator state is
  carried by core--never by a delayed raw `pt arm`--and becomes effective on
  each client only after an epoch-zero adapter probe in a fresh, different
  generation with the exact prior profile, leader, and roster. Stop,
  replacement, zone, and logout remain terminal keep-off paths.
- Made `//pt off` tombstone every exact active, pending, and undecided
  replacement/reapply generation already known to its caller. A stop delivered
  before a matching prepare or commit now prevents that delayed packet from
  resurrecting the profile, while an unrelated later load remains valid.
  PartyTactics is now 0.13.1 because this exact-target stop packet is not wire
  compatible with 0.13.0; mixed-version clients reject the activation barrier.
- Added schema-restricted, profile-declared local stop fences for lifecycle
  companions. PartyTactics appends the already-validated six-field lifecycle
  tuple directly, so `//pt off` tombstones SignetKeeper, JubileeKeeper, and
  LocusPuller even while GearSwap is absent or sender IPC does not loop back;
  the generic core contains no companion-specific command. A live adapter also
  receives the same generation tombstone before any delayed authorize/probe.
  PartyTactics unload and replacement by a different profile use the same
  direct fence. Same-profile controller recovery does not, preserving the
  equipment guards until its exact authorized successor takes ownership.
  Stop, operator, and state IPC now reject surplus fields; state also rejects
  noncanonical or out-of-range epochs. Local lifecycle callbacks require exact
  argument counts, preventing strict companion state from splitting from core.
- Declared all-six equippable Kgd. Signet Staff diagnostics and Dolo's Jubilee
  Ring diagnostic as advisory-only preflight checks. The companion transaction
  requires the actual Signet buff, while the right-ring guard leaves the left
  ring untouched and survives the staff phase.
- Selected Dolo's existing single-wield `Naegling` mode so recommended
  COR/THF is coherent; COR/DNC and COR/NIN remain supported. Subjobs are
  documented recommendations only and are omitted from `members`, so they
  cannot become profile-application or adapter-authority gates. Added focused
  profile/adapter simulations and an inert staggered reload script.

## Qutrub ownership-confirmed pickup refinement - 2026-09-13

- Revised the no-Cait profile to v1.10.0 and added append-only adapter 1.9.0
  after PartyOps isolated nine ineffective Light Shots and 35 repeated
  Violent Flourish failures from missing finishing moves. Adapter 1.8.0
  remains byte-identical.
- An action attempt is no longer treated as an add pickup. Only the add's own
  direct melee or primary TP target confirms its assigned owner. Unique
  anchors remain through fixed quiet assembly; afterward, confirmation
  releases the owner immediately while unconfirmed close-and-engage pursuit
  is bounded to eight seconds. A later wrong target opens only one repair
  episode.
- Dolo receives one exact Light Shot per pickup episode instead of a blind
  retry loop. Kick's routine pickup is now one exact Box Step, which supplies
  enmity and can create finishing stock. Known coordinates defer each
  one-shot request until Dolo is in Quick Draw range or Kick reaches melee.
  Violent Flourish is reserved for
  reactions and the local adapter submits it only with a finishing-move buff
  and a ready ability recast; no-stock/recast cases are immediate no-ops. A
  server no-stock result also opens a ten-second automatic backoff to cover a
  stale local buff snapshot.
- Added deterministic coverage for range-aware one-shot ranged/DNC pickup,
  direct-target confirmation, early release, eight-second fallback, finishing-move/TP/
  recast guards, later waves, and unconditional manual pass-through.

## Genbu Harden Shell offense refinement - 2026-09-13

- Revised only `escha-ruaun-genbu-genmei` to v2.7.0 and added append-only
  adapter 2.7.0. The proven 2.6.0 adapter remains byte-identical; the complete
  pre-change profile/runtime/adapter/reload set is preserved under
  `.codex-backups/PartyTactics/genmei-v2.6.0-pre-v2.7.0-20260913/`.
- Kick now uses completion-confirmed Presto before a due Box Step. Presto gets
  at most two requests two seconds apart inside five seconds, then Box Step
  proceeds unenhanced. A landed Step clears Presto and begins its 45-second
  timer; a miss retains the documented 30-second Presto effect for the retry.
  Invincible clears the local observation, and the Light-chain/Evisceration
  lane continues to run before Step work.
- Dolo receives one best-effort Thunder Shot at encounter bind to cover an
  opening Invincible completed before arm. A same-edge observed Invincible
  merges with that request. Triple Shot remains lower priority and retries on
  its existing bounded cadence, so the insurance request cannot suppress it
  permanently. No result authorizes or blocks combat.
- Harden Shell and Shell V still receive no Dispel/Finale lane after every
  observed attempt resisted. Dia III plus accelerated level-10 Sluggish Daze
  supplies up to 43.31% Defense Down, while the Light magic bursts ignore
  Defense. Shield Bash dispel remains dormant because InventoryCore confirms
  Tackle lacks Caballarius Gauntlets +2 or better.
- Added deterministic coverage for bind-edge proc, Invincible merge, Presto
  completion, bounded fail-open, Step miss/success state, Invincible reset,
  chain priority, unconditional manual pass-through, and source/live parity.

## Qutrub Normal clear refinement - 2026-09-13

- Revised the no-Cait Bigwig profile to v1.9.0 after the six-client Normal
  clear. The staged two-target threat budget held with no deaths, while the
  capture isolated stale Bigwig weapon skills, unordered Light Shots,
  off-focus Wail cleanup, and native RDM cure spam as the remaining defects.
- Target-to-target assignments now use one atomic exact edge; `/attack off`
  is emitted only for a truly unassigned lane. AutoWS2 0.3.5 observes exact
  combat-target packets and holds only its automatic WS until `<bt>`
  acknowledges that ID. Manual target and WS input remain unrestricted.
- Dolo uses parked Light Shot only for initial anchor or confirmed repair.
  Each completed active-focus Dia III now starts its own same-target Light
  Shot transaction. An executed shot completes the cycle even when its
  separate Sleep component returns message 324; Dia enhancement caps after
  one shot. Only a submitted command with no observed action packet can retry.
- Fortifying and Animating Wail are remembered per recipient and stripped
  only when that add becomes the common focus. Tackle uses exact Blank Gaze
  first and Smalls alternates exact Dispel until status removal is observed;
  no three-add area dispel or parked-target cursor churn remains.
- Removed Smalls's native 85%-HP PartyStart cure loop by selecting a
  non-healing maintenance preset. Runtime Cure IV remains at 55%; append-only
  adapter 1.8.0 adds Tackle's stale-revalidated Cure IV backup at 40% after a
  short delay.
- Added deterministic coverage for atomic handoffs, stale-capture retirement,
  Dia-before-Light-Shot ordering and miss retry, focus-only result-aware Wail
  cleanup, Tackle emergency healing, and AutoWS2 battle-target acknowledgement.

## Genbu successful-clear refinement - 2026-09-13

- Reconstructed the immutable six-client successful capture at
  `.codex-tmp/genbu-win-20260912-2255-2325.partyopslog` (SHA-256
  `c0494f8f93d68db2cf689f3bb413e030768ef3a7f8767cae70c5777ee4caa73a`).
  The profile observed an 11:33.586 clear, 411,313 damage (about 593.6 DPS),
  and zero deaths. Thirteen Lights plus six Fragmentations and 25 completed
  high-tier magic bursts produced 142,343 damage, 34.6% of the total.
- Revised only `escha-ruaun-genbu-genmei` to v2.6.0 and added its append-only
  GearSwap adapter; v2.5.0 remains byte-frozen. Tackle's intended coordinated
  Savage Blade now waits in one bounded next-legal slot when a Majesty cure is
  already active. Low TP, range, disengagement, recast, and backoff never
  suppress healing; only actual dispatch, in-flight state, or current action
  ownership yields the PLD helper tick.
- A completed local Invincible packet and the runtime's scoped cancel both
  retire any Cure-delayed Savage Blade immediately. Combat-end cleanup accepts
  that already-released state without error, and a later intended chain can
  bind normally. No post-burst or unconditional Savage lane was added: the one
  apparently unmatched winning-run Savage was a normal chain opener interrupted
  by Invincible, and the proven Light/dual-burst loop retains priority.
- Disabled only Genbu's generic DNC healing helper after Kick spent seven
  overlapping Waltzes, including follow-up Curing Waltz V recoveries of zero
  and 36. Profile-local Haste Samba, Box Step, and Evisceration remain; Tackle
  retains routine Majesty healing and Smalls remains the backup.
- Made Triple Shot completion-driven. A successful completion starts the real
  300-second cadence, while a due but unconfirmed use gets another bounded
  request every 12 seconds. This replaces the blind 180-second request cadence
  that produced only 03:01:07.390 and 03:07:11.211 completions in the win.
- Invincible now holds only Dolo's ordinary ranged-attack cadence for eight
  seconds so the queued Thunder Shot has an action window. Four winning-run
  cycles had ready Quick Draw but no completed shot while `/ra` continued every
  3.1 seconds; the six successful Thunder Shots averaged 5,294 damage. Normal
  ranged fire resumes automatically and no other lane waits.
- Removed only Barney from Smalls's Refresh III recipients; Smalls, Achoo, and
  Tackle remain. Barney retained ample MP under Ballad and ended full, while
  Tackle spent about 2,100 MP on 43 cures. Added one bounded two-attempt
  Barwatera refresh near seven minutes because the opening Barwater expired
  about three minutes before victory. Neither maintenance result gates combat.
- Added deterministic adapter/runtime/profile coverage for PLD queue readiness,
  healing-tick preservation, Invincible cancellation and lifecycle cleanup,
  Triple Shot retry/completion cadence, the ranged proc window, Barwatera
  renewal, DNC helper ownership, Refresh recipients, and frozen-v2.5 integrity.

## Sortie full-run automation and tank-first pull ownership - 2026-09-12

- Reconstructed the complete 52-minute Skomora/A-objective run across all six
  PartyOps streams. The C phase spent roughly fifteen extra minutes after its
  objectives, return travel cost about five minutes, and the A phase lost six
  Abject Acuex to melee killing blows while Smalls was trapped in a routine
  buff carousel and spent roughly 34 minutes at or below half MP.
- Revised C Magic Burst to v1.2.0 and added A Magic Kill v1.1.0. Both remain
  armed between exact same-stage targets, suppress Smalls's free-running RDM
  support only for the objective, and automate their special kill transaction.
  A now uses a five-person speed burn, thresholded melee peel, and durable
  Smalls/Achoo single-target Fire finish queues rather than a slow Dolo-only
  workflow.
- Revised Skomora and Ghatjot to v1.1.0 without changing their damage/support
  plans. All four Sortie runtimes now direct Tackleberry alone first, release
  damage on his hostile action or party claim, and use a two-second safety
  release to prevent a timer-costly stall.
- Added atomic `//pt use <profile> armed` activation and route-owned arm
  preservation between mobs. On a runtime-owned pull profile, Ctrl-P/`//pt
  force` arms the runtime without issuing a six-client `pc force` dogpile.
  Alt-P remains immediate; no background poll re-arms the same desired state.
- Added deterministic runtime, bridge, route, and six-client activation tests.
  No ACK, sensor, buff, preflight, setup, or readiness result became a combat
  permission gate, and manual input remains unconditional.

## Genbu live-log action ownership correction - 2026-09-12

- Revised only `escha-ruaun-genbu-genmei` to v2.5.0 and added its append-only
  GearSwap adapter. Live logs showed ten Thunder IV requests each for Smalls
  and Achoo but only one completed cast each, while five of fifteen one-shot
  Thunder Shot requests were lost to Dolo's ranged-action cadence.
- Thunder Shot, low-MP Invincible Thunder, and Light's Thunder IV now use one
  short exact-target next-legal slot on the intended client. RDM/GEO suppress
  only their own automatic helper while that request exists, including the
  coordinator's private 0.75-second maintenance tick; COR is polled without
  tick ownership. Manual pretarget and precast hooks remain unconditional
  pass-through.
- Added bounded Triple Shot at pull and every 180 seconds below proc priority.
  Removed the runtime's periodic Geo-Malaise request so native AutoGeo is the
  sole renewal owner after the one opening nudge.
- Corrected the queued COR readiness check: Selindrile's `silent_can_use`
  accepts spell IDs, not job-ability IDs. Thunder Shot and Triple Shot now use
  their job-ability resources and actual ability recasts, with a regression
  that fails if either ability is passed to the spell-only predicate.
- Added one bounded deferred slot for a higher-priority request arriving behind
  an in-flight lower-priority action. The original TTL is preserved; cleanup,
  authority loss, and expiry clear both slots without gating manual input.
- Extended the backward-compatible stable GearSwap host contract with an
  optional self-command consumer. Only Genbu implements it, and only for the
  exact `pstartrdm tick`/`pstartgeo tick` maintenance commands while that
  client's Thunder queue is live; other profiles and unrelated commands retain
  their captured behavior. The host revision is now 1.1.0; the Genbu reload
  script performs a full GearSwap addon reload on every client so the old
  in-memory 1.0.0 wrapper cannot survive the upgrade.
- Live packet evidence showed successful Thunder staggers end physical
  immunity before the nominal Invincible timer. Automatic physical work now
  resumes on the first positive party physical result; 30 seconds remains the
  failure/packet-loss fallback.
- HealBot now ignores only Genbu's unerasable Weight aura while the Genbu
  adapter is active instead of disabling Smalls's entire NA lane. Poison,
  Accuracy Down, and other removable ailments remain serviced. The first
  positive physical result also cancels undelivered backup Thunder requests.
  Profile teardown deliberately returns Weight to PartyTactics' normal
  unignored baseline; it does not claim to reconstruct a user-customized
  pre-profile HealBot exception table.
  The observed Shell V traffic was one intentional six-target opening pass,
  not a reactive Shell loop; Tortoise Song removes songs and rolls, not Shell.
- Reassigned routine healing to Tackle's proven Majesty lane. Barney and Achoo
  now run with HealBot off; Smalls uses the already-frozen `limbus-protect`
  preset for one Protect/Shell pass, core buffs, Dia, a 50% backup-heal
  threshold, and NA support outside the Weight hold. No frozen helper changed.
- Removed Genbu runtime requests for Dispel/Finale: the live run resisted all
  seven attempts. Dolo now selects the existing native `DeathPenalty` mode and
  recommends COR/THF for native TH2; Achoo recommends GEO/BLM. The proven-safe
  formation remains Tackle/Kick in melee with the four-person support cluster
  at roughly 11-14 yalms.
- Made Warlock's Roll roll1 and Samurai Roll roll2. Roller2 services roll1
  first after Tortoise Song, preventing the observed minute-long magic-accuracy
  gap while the two rolls share an ability recast.
- Added deterministic coverage for busy-client request retention and retry,
  RDM/GEO helper-tick isolation, COR non-ownership, manual pass-through,
  priority replacement, Triple Shot cadence, NA cleanup, early stagger release,
  and the absence of periodic runtime Geo-Malaise.

## Qutrub sequential-wave, healing, and shadow correction - 2026-09-12

- Reconstructed the salvaged Normal clear from all six PartyOps streams. The
  second wave did not spawn as one roster: Tormentor, Astrologer, and the
  second Tormentor appeared across roughly ten seconds. Bigwig, the Astrologer,
  and that second Tormentor then converged on Dolomedes; Bigwig's Triple
  Reversal dealt 33,298 despite a freshly completed Utsusemi: Ichi.
- Revised the no-Cait profile to 1.8.0. Every new wave now pauses boss damage,
  gives each sequential spawn an immediate unique anchor (Tackle first
  Tormentor, Achoo Astrologer, Dolo/Kick nonholder second Tormentor), and
  restarts a 6.25-second quiet interval. All five attackers collapse onto the
  Astrologer only after the wave stops growing. Every later wave and recycled
  mob slot begins a fresh assembly generation.
- Added a direct hostile-target ledger. If direct melee/TP evidence shows any
  combat member targeted by three encounter foes, only that lane receives a
  stop edge while all unique anchors receive immediate exact recapture; the
  member automatically returns to the common focus when targets redistribute.
  Hostile spell targets are excluded because the live Astrologer Bind target
  was not its enmity owner.
- Removed Sentinel, Palisade, and area Blue Magic from sequential assembly.
  Compact area control remains best effort only after a stable one- or two-add
  roster; three-add Fortifying Wail continues to use exact Gaze/Dispel.
- Disabled Smalls's free-running HealBot cure selector while retaining status
  removal. The runtime now requests exact Cure IV only for the lowest member at
  55% HP or below, no faster than every 3.5 seconds; the no-add final phase
  permits only a Cure II rescue at 12% or below. The adapter rechecks live HP,
  rejects stale requests, and preserves a 15% MP floor outside emergencies.
  This addresses 113 logged Cure II/III completions, including 77 self-cures
  and 48 zero-recovery casts, that left Smalls at 13/1727 MP.
- Added append-only no-Cait GearSwap adapter 1.7.0. Its local Copy Image
  observer reads both Utsusemi recasts, immediately falls back to Ichi at zero
  images when Ni is unavailable, suppresses duplicate submissions, and keeps a
  bounded local retry. Kick's logged death was a reproducible timing gap:
  Phantom Whorl resolved for 14,965 before the late Ichi could complete.
- Extended deterministic coverage for ten-second sequential spawn assembly,
  live threat convergence and release, hostile-spell exclusion, exact cure
  thresholds, recycled later waves, Bigwig-side Triple Reversal stun, and
  recast-aware Ichi fallback. These are bounded encounter reactions, not
  activation or readiness gates; manual controls remain unconditional.

## Qutrub Triple Reversal allocation correction - 2026-09-12

- Reconstructed the latest Normal wipe from the exact six-client PartyOps
  window and extended the analyzer to retain hostile actor IDs and direct
  target IDs. Immediately before the first 33,333 Triple Reversal, both
  Tormentors and the Astrologer were independently observed targeting
  Tackleberry; the prior runtime had also kept its spawn-time Kick holder
  latched after Bigwig moved to Dolomedes.
- Revised the no-Cait profile to 1.7.0 without changing its immutable 1.6.0
  GearSwap adapter. On Normal, Tackle briefly establishes one off-focus
  Tormentor and the Dolo/Kick nonholder establishes the other. After those
  pickups, Dolo, Tackle, Kick, Barney, and Achoo all attack the same
  Astrologer-first focus.
- Added an explicit two-hostile-target budget: Tackle and the nonholder each
  own parked add plus focus; the holder owns Bigwig plus focus; Barney and
  Achoo own focus only. The Bigwig holder is no longer parked in a corner and
  Bigwig may follow that character into the common add group.
- Replaced the wave-long holder latch with a five-second Bars-equivalent
  direct-target review. A holder change transfers only the second parked add
  between Dolo and Kick, then both return to the shared focus.
- Removed three-add blanket Flash and area Blue Magic from Tackle. Fortifying
  Wail with three live adds now uses Tackle's exact Blank Gaze only on his
  parked target and Smalls's exact Dispel on the rest; Geist Wall remains
  available with at most two adds.
- Made shared-focus pursuit and parked-add drift recovery one-shot per episode,
  and stopped broadcasting adapter `cancel` on focus transitions so local
  Copy Image reactions remain active. Added deterministic coverage for holder
  transfer, drift repair, later waves, recycled IDs, all-five focus, and
  three-add Wail behavior. No check, setup result, geometry, or difficulty gate
  was introduced, and manual controls remain unconditional.

## Sortie C packet-confirmed Magic Burst objective - 2026-09-12

- Added append-only profile identity 16,
  `sortie-objective-c-magic-burst-v1` v1.0.0, with the short `//pt cmb`
  command. It accepts only the four normal Cachaemic families in Sortie's
  three instance zone variants and explicitly rejects Cachaemic Bhoot.
- Added a profile-local state machine for automatic Evisceration into Savage
  Blade, observed Fragmentation, primary Achoo Thunder, bounded Smalls fallback,
  observed Magic Burst credit, and only-then automatic finisher release.
- Disabled AutoWS2 and native automatic WS for every member in this profile.
  Dolo and Kick alone receive the pre-credit target; Tackle and Barney are
  exact-target directed attackers only after the burst is observed.
- Added a pinned cooperative GearSwap adapter with exact resource, target,
  claim, zone, range, TP, MP, recast, movement, and engagement checks. Its
  explicit pretarget/precast hooks pass through and no request filters manual
  input or serves as evidence of success.
- Added bounded retries, manual packet recovery, low-HP advisory warning,
  exact-target retirement, PartyOps analysis metadata, and focused compiler,
  runtime, adapter, Bhoot-exclusion, timing, and nonblocking-control tests.

## Sortie Skomora and Ghatjot training profiles - 2026-09-12

- Added isolated, adapter-free Skomora and Ghatjot v1.0.0 profiles for the
  fixed COR/PLD/DNC/BRD/RDM/GEO party. Both load inert, run best-effort without
  preflight or readiness gates, and preserve unconditional manual control.
- Translated Umbra's melee workbook into the party's real equipment boundary.
  The profiles use verified Naegling, Tauret, Maxentius, and Dolo DualSavage
  modes and Barney's actual three-song Blurred Harp +1 setup; no REMA, Prime,
  Honor March, Aria, Idris, Burtgang, Aegis, or Duban is required.
- Consolidated routine healing on Tackle's Majesty policy, retained Kick's
  TP-funded backup and Smalls's status/emergency lane, and removed competing
  routine cures from BRD and GEO to preserve MP and support uptime.
- Made Ghatjot's automatic offense Water-safe: Savage Blade, Exenterator, and
  Black Halo cannot produce Distortion or Darkness among themselves. Hot
  Shot, Leaden Salute, Water damage, and automated expert openers are omitted.
- Added focused compilation, immutable-identity, support-command, equipment-
  ownership, manual-control, Skomora mechanic, and Ghatjot damage-safety tests.

## Qutrub Normal clear resource/add-pressure tuning - 2026-09-11

- Added append-only no-Cait adapter 1.6.0 and replaced the unnecessary
  20-yalm cross-room area-control threshold with a compact 15-yalm split plus
  verified Tackle arrival inside 4.5 yalms. This still clears Tackle's widest
  nine-yalm pack control while keeping Dolo's 22-yalm Light Shot practical;
  it is not an encounter damage or combat-start gate.
- Corrected the no-Cait 1.6.0 Fortifying Wail reaction before live validation:
  Tackle now answers first with caster-centered Geist Wall across the grouped
  pack, then uses delayed exact Blank Gaze cleanup if Geist is unavailable,
  resisted, or misses a recipient at the edge.
- Reconstructed the 2:36-2:56 PM EDT run from all six PartyOps journals. It
  cleared Normal in 19:48 from entry (17:33 of combat). Wave one lasted 4:43;
  wave two reused the same three server mob slots and lasted 6:05. The second
  Astrologer lived longer because Dolo correctly held Bigwig while Tackle left
  the focus for roughly two minutes, and Fortifying Wail repeatedly applied
  Protect—not because of a demonstrated proximity-based damage reduction.
- Revised only the no-Cait profile to 1.6.0. Achoo is now a directed-only
  add attacker: Tackle, Achoo, and the two non-holders peel together, while
  Achoo carries Indi-Fury, places exact-subject Frailty when in range, and
  spends TP with AutoWS2 Black Halo. Tackle and Achoo both stop when the pack
  ends and never join the ordinary Bigwig broadcast.
- Added arrival-aware sticky pursuit. PartyCombat still owns the initial exact
  transition; after a member has reached the shared add, the runtime reissues
  that member's assignment only when coordinate separation exceeds 4.5 yalms.
  It does not continuously seize targets inside the pack, and disarm/manual
  action paths remain unconditional.
- Smalls remains the sole routine HealBot cure/status-removal owner. Achoo's
  routine HealBot lane is off after the log showed roughly five thousand MP
  of Cure/Curaga expenditure and sustained 1-3% MP; his bounded Curaga II
  Sleepga wake remains available. Smalls hit zero despite three Converts, so
  removing the competing healer also eliminates most cure races and preserves
  GEO MP for colures.
- Added append-only adapter 1.5.0. Every newly selected focus receives an
  exact Dia III attempt, and a completed Dia III enables one in-range Light
  Shot for its additional Defense Down. Fortifying Wail immediately triggers
  AoE Geist Wall, followed by exact Blank Gaze cleanup for every live add
  recipient. None of these support
  results gates pursuit, targeting, damage, or manual input.

## Qutrub Normal target/handoff correction - 2026-09-11

- Reconstructed the 1:16-1:39 PM EDT Normal wipe from all six PartyOps
  journals. The runtime selected Astrologer first, but two-second target
  delivery yielded before clients acknowledged the new battle target; a later
  yellow Bigwig claim gap then released encounter authority, and missing Copy
  Image maintenance let Phantom Whorl kill the party in sequence.
- Revised only the no-Cait profile to 1.5.0. At every add wave Dolo, Kick, and
  Barney first disengage. A Bars-equivalent latest-direct-action target signal
  parks Bigwig's current hate holder, while Tackle and the other two run to one
  shared Astrologer-first focus. The split latches for the wave; if the signal
  is stale, Tackle captures immediately and the next direct Bigwig action
  completes the split without blocking manual intervention.
- Added append-only adapter 1.4.0. Each `/NIN` client reacts locally when its
  Copy Image count drops, tops with Ni below three, reserves Ichi for zero,
  and retains a slow recovery watchdog. Phantom Whorl readiness independently
  requests immediate top-ups. Temporary yellow claim state no longer ends a
  live exact Bigwig encounter.
- Tackle now Flash-tags each live add and performs one geometry-safe AoE pack
  sequence rather than redundant per-add sequences. PartyCombat 0.6.17 keeps
  a directed handoff alive for a bounded 15-second acknowledgement window.
  AutoWS2 0.3.4 validates and fires on `<bt>` so off-focus capture cursors do
  not redirect weapon skills.

## Qutrub Easy clear pursuit correction - 2026-09-10

- Recorded the 11:26-11:33 PM EDT Easy attempt as a seven-minute clear. The
  intended two-wave target order ran, Tackle's PLD/BLU actions and the `/NIN`
  shadow lanes fired, mage Reraise was present, and Barney refreshed March,
  Minuet, and Madrigal through the fight. No party member died.
- PartyOps and operator movement showed that a new exact target packet could
  race Windower's previous battle-target view. PartyCombat 0.6.16 now gives
  only that exact prior target a two-second delivery window, permits an
  immediate new edge plus bounded retry, and clears the grace as soon as the
  requested battle target is observed. A third or later manual battle target
  still yields immediately, so no persistent snap-back rule was added.
- Revised only the no-Cait profile to 1.4.1. Tackle, Kick, and Barney retain
  one shared Astrologer-first damage focus and now close automatically on each
  exact transition and return to Bigwig afterward. Tackle's exact Flash and
  Blank Gaze tasks for other live adds survive a focus transition so every
  sequential or higher-difficulty add can be tagged without gating damage.
- Bigwig did follow Kick during the final wave. The clear does not establish a
  reliable current-hate signal, so v1.4.1 records that containment risk without
  inventing a target gate or splitting the add damage group on ambiguous data.

## Qutrub Easy wipe correction - 2026-09-10

- Recorded the 10:11-10:20 Easy attempt as a wipe. PartyOps showed Dolo and
  Barney dying first, Kick later, and the remaining party collapsing when
  Bigwig, an Astrologer, and a Tormentor converged; the Astrologer and
  Tormentor completed Triple Reversal within roughly one second. The final add
  generation is now a mandatory strategy case, not an operator surprise.
- Revised only the no-Cait profile to 1.4.0. With no adds, Dolo, Kick, and
  Barney attack Bigwig while directed-only Tackle is stopped. On every visible
  add generation, Dolo stops to freeze boss thresholds and Tackle, Kick, and
  Barney focus one Astrologer then one Tormentor. The same state transition
  repeats for later generations and uses one-shot target/stop edges so manual
  improvisation remains sticky.
- Added Tackle's automatic AutoWS2 Savage Blade lane and PLD/BLU maintenance:
  Cocoon, Crusade, Reprisal, Sentinel, Palisade, Flash, Blank Gaze, Sheep Song,
  Geist Wall, and Jettatura. Dolo, Kick, and Barney now refresh Utsusemi only
  after Copy Images are absent, with Ni then an Ichi fallback.
- Added automatic party wake attempts after completed Astrologer Sleep-family
  casts: Smalls casts Curaga II immediately and Achoo follows. Enemy Sleep was
  not added because every battlefield Qutrub is documented immune.
- Added non-gating Reraise maintenance. Smalls and Achoo cast Reraise; Dolo,
  Tackle, Kick, and Barney select the best eligible Reraise item present in
  Inventory. Missing items remain diagnostic and never prevent arming.
- PartyCombat 0.6.15 now supports directed-only attackers and exact one-shot
  `stopto` subsets. PartyTactics 0.11.2 accepts a signed `//pt arm` or
  `//pt disarm` request from any of the active profile's six members while the
  configured profile leader remains the sole PartyCombat command issuer.

## Sortie Sheet D post-run tuning - 2026-09-10

- Revised only `sortie-objective-d-demisang-clear-v1` to 1.1.0 from the first
  complete PartyOps capture. Smalls spent roughly half the instance at or below
  20% MP and fell back below that threshold within 117-161 seconds after each
  of five Converts while RDM, BRD, GEO, and PLD all duplicated cures.
- Consolidated routine healing onto Tackleberry's MP-efficient Majesty cures.
  Kickpuncher retains automatic emergency Waltzes; Smalls retains native
  emergency cures and HealBot status removal. Barneystinson and Achoo no longer
  spend actions or MP on routine Cure/Curaga overlap.
- Changed Smalls from the six-person Protect/Shell profile to the sustained
  `locusbats` support policy, retained Haste II and high-value Refresh III,
  narrowed Phalanx II, and kept bounded Distract/Dia. The saved casts become
  additional melee/weapon-skill time on BRD, RDM, and GEO.
- Changed Tackleberry from defensive `manualsc` to sustained `locusbats` PLD
  behavior so Flash/Provoke gain Sentinel and WAR-subjob enmity support, while
  Chivalry sustains the Majesty healing lane. No shared GearSwap helper or
  manual-input path changed.

## Qutrub no-Cait split correction - 2026-09-10

- Revised the isolated no-Cait Qutrub profile to 1.3.0 after the first Very
  Easy PartyOps capture established the arena geometry: the Tormentor appeared
  near Bigwig's original middle spawn after Bigwig had moved roughly 33 yalms
  to the party-start corner.
- Replaced the all-attacker add switch with exact, one-shot recipient lanes.
  Dolo and Kick remain on Bigwig; Barney stays off Bigwig before the add and is
  the only automatic add killer beside Tackle. Directed controller swings do
  not leak their target to the other lane, and manual overrides never trigger
  a scan or reacquisition loop.
- Kept the cooperative contract free of readiness and promotion gates. Flash,
  Blue Magic, Wilt, coordinates, packets, equipment, buffs, and diagnostics
  remain independent best-effort evidence or actions.

## Sortie Sheet D canary - 2026-09-09

- Added the isolated `sortie-objective-d-demisang-clear-v1` 1.0.0 profile and
  append-only public identity ordinal 13. It loads inert and supplies the
  existing stationary all-six physical/support policy for an operator-led
  regular-Demisang sweep.
- Added no runtime, GearSwap adapter, navigation, target selection, mob counter,
  readiness gate, or input filter. The operator positions and pulls, chooses an
  exact regular Demisang, presses Ctrl-P or `//pt force`, and can retarget,
  move, fight manually, or press Alt-P at any time.
- Kept Demisang Deleterious advisory-only. The generic exclusion vocabulary
  cannot express that one named exception safely, so v1 reports the boundary
  instead of changing shared combat code or pretending to enforce it.

## 0.11.3 - 2026-09-09

- Rebuilt the isolated Genmei profile and adapter as 2.3.0 without changing
  either historical adapter. Ctrl-P is the immediate engage edge; Barwatera,
  PLD defense/enmity, geomancy, ranged fire, DNC support, skillchains, and boss
  reactions are independent best-effort lanes rather than prerequisites.
- Kept broad native PLD buffing and DNC weapon-skill ownership off for this
  profile. The runtime requests only Crusade/Sentinel/Flash/Provoke plus
  TP-aware Haste Samba and Box Step, preventing generic Berserk/Aggressor or an
  AutoWS2 re-enable from competing with the fight plan.
- Haste Samba and Box Step now enter their long refresh windows only after a
  successful Kick action packet. Busy, moving, out-of-range, or missed requests
  retry after five seconds without holding combat, skillchains, or manual input.
- Added actor-checked, packet-observed Evisceration -> Savage Blade -> Last
  Stand timing, a two-step fallback, missed-step bypass, and standalone Last
  Stand fallback. Known miss/failure result messages no longer advance the
  chain. Manual actions remain unfiltered and can recover it.
- Corrected completed-versus-readying monster-action handling for Invincible,
  Harden Shell, and Tortoise Song. Invincible holds only automatic physical
  weapon skills for its 30-second duration; every other lane stays live.
- Made Tortoise Song recovery tokens unique to the live boss and event time, so
  an addon/profile reapply cannot collide with an adapter-cached earlier event.

## Sortie profile addition - 2026-09-09

- Added the isolated `sortie-objective-c-device-kill-v1` 1.0.0 profile and
  append-only public identity ordinal 12. It loads inert and supplies a
  stationary all-six physical policy for one operator-pulled normal Cachaemic
  beside Device C.
- Preserved the cooperative control contract: `//pt force` starts immediately,
  Alt-P disarms immediately, setup differences remain diagnostic, lane failures
  remain local, and manual targeting, movement, attacks, weapon skills, spells,
  abilities, ranged attacks, and recovery remain available.
- Added no fight runtime or GearSwap adapter. The profile cannot navigate,
  choose a target, pull, interact with Device C, Materialize, open a chest, or
  block an operator improvisation.

## 0.11.1 - 2026-09-09

- Routed the recurring 0.75-second role-maintenance tick through a narrow
  GearSwap callback instead of the complete generic self-command/equipment
  pipeline. The existing activation, pending-reapply pause, cadence, role
  helpers, and action leases are unchanged. A startup capability check retains
  the established `gs c` path as a behavior-preserving fallback after an
  official GearSwap update and reports that slower state as a catalog warning.

## 0.11.0 - 2026-09-08

- Removed the engine's permission-gate model. `//pt arm`, `//pt force`, and
  manual profile actions now execute immediately for the active leader and
  never consult application ACKs, `//pt check`, equipment, inventory, buffs,
  subjobs, or GearSwap controller replies. Checks are explicit read-only
  diagnostics; PartyTactics does not auto-schedule, retry, or consume them.
- Made profile application best-effort per client. Compatible responding
  clients apply after the bounded prepare window; unavailable clients and
  job/setup differences are reported instead of withholding the entire party.
  A local GearSwap host loss, job change, runtime callback exception, adapter
  fault, or reapply failure pauses only that local work and does not shut down
  healthy peers.
- Added PartyCombat local-only stop and policy-clear paths for job changes and
  a single PartyTactics unload. Explicit operator disarm remains party-wide.
  Runtime callback faults are isolated per method, so an `on_action` exception
  cannot suppress `on_tick`, `on_status`, deactivation, peers, or manual input.
- Changed live GearSwap host/adapter/frozen-helper digest differences from
  catalog quarantine to setup warnings. Profile identity conflicts and actual
  compile errors remain profile-local errors. Existing profile ids, aliases,
  versions, adapters, and sibling behavior remain isolated.
- Added PartyCombat 0.6.12's exact local `engageonceid` surface to the typed
  runtime API. It supplies one battle-state packet for a ranged attacker without
  persistent target synchronization, facing, movement, retry, or re-engagement.
- Rebuilt Genmei as profile/adapter 2.2.0. Loading remains inert; `//pt arm`
  starts independent Tackle/Kick melee, Dolo ranged, support, setup, and mechanic
  reaction lanes immediately. A missed Flash, unavailable, resisted, or delayed action
  cannot pause another lane, and the adapter never filters operator input.
- Rebuilt direct Rancibus as profile/adapter 1.1.0. PartyCombat owns only Tackle
  and Kick, Dolo uses one-shot local engagement plus independent ranged/Last
  Stand requests, support is never target-synchronized, and no Flash, buff,
  controller, HP, skillchain, setup, or result condition authorizes damage.
  The adapter has no pretarget/precast ownership filter, so manual emergency
  actions remain available while automation is armed.
- Corrected Rancibus and Genbu claim-loss tracking: an unclaimed spawned boss
  may wait indefinitely before the pull, but a post-claim gap now expires after
  the bounded grace period instead of refreshing itself forever.

## Superseded pre-0.11 Rancibus development record

The entries below document the earlier 1.0.x implementation. They remain for
history but do not describe the active 1.1.0 profile or PartyTactics 0.11.1.

- Added the isolated `rancibus` 1.0.2 profile for only the direct Ra'Kaznar
  Turris alternative battlefield. It binds an exact Rancibus without reading
  hidden enemy HPP, requires the six-client preflight and a fresh arm edge,
  performs the PLD Flash pull, ranged TP building, and packet-confirmed
  Evisceration -> Savage Blade -> Last Stand Light transaction automatically.
- Froze the initial 1.0.0 and 1.0.1 adapters, then added the audited 1.0.2 adapter with
  exact-HPP-independent PLD enmity, DNC Box Step, exact pet-plus-last-Geo
  luopan-aware GEO-Frailty maintenance, and recurring RDM debuff queues; ordered
  Barwatera/Barsilencera preparation, pre-pull No Foot Rise, bounded
  exact actions, best-effort Violent Flourish/Shield Bash interrupts including
  Bindga, Manafont defense, native song/Chaos+Magus recovery,
  and local Echo Drops. No Foot Rise is a hard pull gate (with exact no-effect
  results accepted when finishing moves are already full), a resisted/no-effect
  opening Flash still resolves the hostile pull, Rampart remains ready for the
  first Manafont instead of being consumed pre-pull, confirmed Violent Flourish
  immediately schedules Box Step replenishment, and Echo Drops have an
  unconditional three-attempt cap. Its authority-wide fence rejects every unreserved
  profile-owned fight action, including chain weapon skills, COR ranged
  attacks, native-helper races, and a delayed cast left after cancellation. Kick uses
  the frozen helper's heal-only `tankheal` mode as an additional ownership
  boundary, and Reverse Flourish is blocked only under this exact authority.
  The adapter never equips gear or chooses an instrument.
- Added direct-fight research, an append-only identity, an independent
  compiled-plan sentinel, deterministic runtime/adapter tests, and source-hash
  guards. PartyCombat 0.6.11 adds one opt-in, exact-name, exact-ID,
  party-claimed force path for enemies whose HPP is hidden; ordinary target
  validation and every established profile/adapter remain unchanged. Exact
  validation precedes follower authorization, and unload/logout now fully
  revoke and disengage the exact path. No
  character GearSwap file, equipment set, or instrument selector was changed.

## 0.10.5 - 2026-09-05

- Added encounter-qualified convenience commands: `//pt v1-breadwinner`,
  `//pt v1-qutrub`, `//pt v1-qutrub-nocait`, and `//pt v2-hydra`. Existing
  canonical ids and aliases, including the August-owned `//pt v1`, are
  unchanged, and the same names also work with `//pt use`.
- Kept convenience aliases in independently sandboxed, fail-closed per-profile
  sidecars. Names that collide with a command, canonical id, established alias,
  or loaded fight's manual action are ignored; malformed siblings and missing
  or quarantined targets cannot alter established profile selection.
- Fixed both September Qutrub profile runtimes for Windower's Lua 5.1
  60-upvalue limit. Runtime callbacks now live at module scope and are assigned
  by each profile factory; behavior and all shared controllers remain unchanged.
- Added a regression guard against nesting these large callbacks inside
  `M.create()` and an optional real-Lua-5.1 compilation check.

## 0.10.4 - 2026-09-04

- Removed the Salvage duo helper from PartyTactics. A two-character farming
  assist does not belong behind the fixed six-client fight-profile barrier.
- Removed the unused `ANY` job capability with that profile; established fight
  profiles, adapters, and compiled-plan fingerprints remain unchanged.
- Salvage duo control now lives as an independent PartyCombat script with no
  PartyTactics activation, ACK, preflight, job, or six-character requirement.

## 0.10.3 - 2026-09-04

- Corrected `salvage` to 1.1.0 by making manual driver Dolomedes job-agnostic;
  BLU/any subjob now passes just as COR or another main job would.
- Added the narrowly restricted `main_job='ANY'` contract only for members
  outside both PartyCombat targeter and attacker rosters. Existing fight job
  requirements and compiled plans remain unchanged.
- Added a job-neutral inert baseline for such members: no weapon selection or
  job-specific support helper, with Roller2, native AutoWS, HealBot combat
  surfaces, and AutoWS2 explicitly Off.

## 0.10.2 - 2026-09-04

- Added the isolated `salvage` 1.0.0 profile. Dolomedes remains a completely
  manual command authority, while Kickpuncher alone receives his physical
  combat target and uses PartyCombat's bounded mobile approach and engagement.
- Kept Kick's AutoWS2 and DNC support controller Off. Every support controller,
  Roller2, HealBot combat surface, and profile GearSwap adapter is explicitly
  disabled; the profile contains no runtime and changes no older profile.
- Added an append-only ordinal-11 identity, independent compiled-plan sentinel,
  and regression assertions for the one-attacker policy and inert automation.

## 0.10.1 - 2026-09-03

- Added the independent `qutrub-nocait` 1.0.0 profile and pinned adapter
  without changing either Cait adapter. Dolo COR/NIN pulls and closes, Tackle
  PLD/BLU owns only the add pack, Kick DNC/NIN leads, Barney BRD/NIN supplies
  the middle Savage Blade, and Smalls/Achoo retain `/WHM` recovery lanes.
- Made Tackle's five-spell active Blue Magic set a fail-closed capability:
  Cocoon, Blank Gaze, Sheep Song, Geist Wall, and Jettatura require five slots
  and 12 set points; Flash remains native. Tackle is absent from PartyCombat,
  receives only a GearSwap-owned Naegling/Diamond Aspis loadout, and must remain
  more than 25 yalms from the cornered Bigwig during center capture.
- Automated stable sequential-roster discovery, result-confirmed Blue/Flash
  tags, negative off-target revocation/reacquisition, guarded Astrologer-first
  mobile wave-one kills, and one-tank wave-two wall/corner kiting. Tackle sends
  no post-claim party-wide PLD job ability or Shield Bash; native DNC automation
  is off and only Kick's bounded Violent Flourish reaction remains.
- Replaced ineffective Indi-Gravity because the Qutrub are Weight immune.
  Achoo now saves a fresh exact-target Entrust plus Indi-Wilt 787 for wave two;
  Tackle's subsequent Colure Active buff 612 proves aura receipt, while enemy
  status 557 is only Attack Down. Because enemy-targeting Indicolure also has an
  enmity-list condition, Normal promotion requires observed survivable physical
  mitigation and does not add a risky GEO Diaga lane.
- Kept Utsusemi maintenance, RDM control, fixed packet-confirmed Light
  transactions, low-HP safety, and terminal cleanup. Normal advances directly
  to Difficult only after a clean evidence pass. Very Difficult remains
  experimental with medium-low confidence; neither Cait variant is claimed
  retail-proven for this exact group.
- Added a generic generation/epoch/encounter/entity/token-authenticated adapter
  status relay so a controller's already-active Cocoon, shadows, Entrust, or
  Indi-Wilt/Colure Active fast path can advance its owning runtime without
  inventing an action packet. Replays are deduplicated, and stale or mismatched
  proofs fail closed; the relay contains no fight identifier or strategy branch.
- Added backward-compatible RDM `healbot='cure-na'` and PLD `weapon_mode`
  compiler/schema fields. Profiles that omit them retain their prior compiled
  commands byte for byte; the weapon field selects GearSwap loadout only and
  grants no combat or targeting authority.
- Added dedicated no-Cait profile, runtime, adapter, analysis-contract, identity,
  status-relay, and source-hash regressions plus the separate runbook and
  migration contract.
- Revised only the September Qutrub profile to 1.1.0 after identifying that a
  GEO luopan and Cait Sith contend for Achoo's single pet slot. The immutable
  1.0.0 adapter remains present and hash-guarded; the profile now pins a new
  append-only 1.1.0 adapter.
- Kept all three attackers `/NIN`, moved the two independent Mewing Lullaby
  lanes to Barney BRD/SMN and Smalls RDM/SMN, and changed Achoo to GEO/WHM so
  Fury/Frailty can remain uninterrupted alongside a separate cure/NA lane.
- Changed the alternating Mew interval to 31 seconds, giving each unmodified
  `/SMN` Blood Pact: Ward lane at least 62 seconds between requests. Smalls's
  pet requests rank below exact cures, Diaga, Dispel, and Silence.
- Corrected preflight ownership: Cait Sith/Mew are proven on Barney and Smalls,
  while Achoo proves `/WHM` recovery and Reraise. The impossible BRD/SMN
  Reraise-spell requirement was removed.
- Added a short, low-priority, packet-confirmed Retreat follow-up on only the
  Cait lane whose full-pack Mew succeeded. Retreat is preemptible even after
  dispatch and expires without blocking targets, recovery, or chains. Cait
  stays summoned; the profile never uses Release during combat.

## 0.10.0 - 2026-09-03

- Added isolated September Ambuscade profiles for V1 Qutrub / Bozzetto Bigwig
  and V2 Hydra / Alluttu. They use new append-only profile identities, unique
  aliases (`qutrub` and `hydra`), and separately pinned 1.0.0 GearSwap adapters;
  the established August `v1` alias and every older adapter remain unchanged.
- Added a leader-local, post-positioning operator arm latch. The two September
  runtimes may prebuff while inert but cannot bind, pull, or force an unclaimed
  boss until a fresh `//pt arm`; release, disarm, reapply, zone change, and
  profile replacement consume that edge.
- Extended the pinned-adapter action API with an optional exact subject ID for
  adds and mechanic targets. The original encounter ID remains the authority
  boundary, both IDs are independently uint32-validated, receivers revalidate
  the live relationship, and calls without a subject preserve their original
  command bytes.
- Automated Qutrub's exact add-first order, Astrologer control, two-lane
  Mewing Lullaby TP suppression, Utsusemi maintenance, Diaga response,
  long-recast-safe PLD pull, phase holds, packet-confirmed Light transactions,
  food, engagement, and terminal cleanup. Tormentor and Tormenter are accepted
  only as the two reviewed exact spellings.
- Added a latched Qutrub finish controller after the second add wave: all three
  `/NIN` attackers are held in a guarded 13-25% HP band with live-shadow proof,
  exact-member Cure II rescue, filtered legacy healing, and fail-closed support
  distance checks. Barney and Achoo provide the two `/SMN` Mew lanes only while
  an add pack remains alive.
- Automated Hydra's PLD pull, hate maintenance, Box Step, packet-confirmed
  Light plus Thunder IV bursts, Nerve Gas/Polar stun attempts, Shield Bash
  fallback, physical/magical Bulwark switching, recovery priority, food,
  engagement, and terminal cleanup. Head count is never inferred from an
  undocumented packet field.
- Hydra's fixed Violent Flourish and Shield Bash mechanic reactions outrank
  routine low-HP/status recovery during their three-second interrupt window;
  all death, authority, target, range, recast, movement, incapacitation, and
  bounded-queue gates still apply.
- Kept Clarion Call opportunistic and non-blocking in both fights. A ready
  ability may add the profile's fourth song, but cooldown or failure cannot
  prevent a pull or deadlock a repeat attempt. GearSwap remains the sole owner
  of instruments, weapons, ammunition, and action gear.
- Added passive `analysis_spec.json` sidecars and a post-fight analysis
  contract. Combat control never loads the sidecars or performs log I/O;
  PartyOps/BattleLab capture and a future offline profile-aware reducer remain
  outside the real-time action path.
- Added deterministic September runtime/adapter tests, source guards, resource
  and profile-plan sentinels, and an inert staggered reload script. Existing
  profile compiler/runtime regression sentinels remain unchanged.

## 0.9.0 - 2026-09-03

- Added the stable, dormant `PartyTactics_Host.lua` GearSwap integration layer.
  It is included once at the true end of each character job Lua, owns callback
  chaining and raw-event registration, exposes no equipment surface, and loads
  no fight code until PartyTactics activates an exact adapter id/version.
- Added schema, compiler, action-API, preflight, and fingerprint support for a
  profile-pinned `gearswap_adapter`. The stable host joins every profile's
  dependency closure because it wraps every job callback; only the selected
  exact fight-adapter version joins the owning profile. Sibling fights and
  future adapter versions cannot change it.
- Added an append-only identity registry for canonical ids, public aliases,
  and PartyCombat policy ids. A later profile that reuses an established name
  is quarantined without redirecting or disabling the older profile.
- Froze the original seven identities as a bootstrap and moved all future
  identities to isolated, sandboxed sidecars. A malformed, duplicate, or
  gapped future sidecar is quarantined without stopping the established
  catalog. Established aliases now resolve before active-profile shorthands.
- Adapter-free profiles now issue `gs c ptgs off` as an application baseline,
  so a stale fight adapter left behind by an earlier PartyTactics crash/reload
  cannot enter Locus, Limbus, V1, Dynamis, or Kammavaca callbacks.
- Removed Genmei's shared `PartyStart_Genmei.lua` callback wrapper and all
  PartyStart add-on lifecycle coupling. PartyStart remains unloaded. The
  migrated Locus, Limbus, and V1 profiles continue to use only their frozen
  generic `PartyStart_*` GearSwap compatibility helpers; those historical file
  names are libraries, not an orchestrator dependency.
- Snapshotted those five compatibility helpers under immutable
  `gearswap/legacy/1.0.0` source paths and made startup quarantine all profiles
  unless each loaded Common copy matches its canonical digest.
- Application acknowledgements now wait for an executed stable-host proof and
  an executed versioned helper proof from each applicable live GearSwap job;
  issuing an include or command is no longer treated as execution evidence.
- Every COR plan now explicitly turns Roller2 automatic Random Deal off, so a
  persistent opt-in cannot leak across profiles.
- Revised `escha-ruaun-genbu-genmei` to v2.1.0. Kickpuncher is now an engaged
  DNC/WAR attacker and the controlled starter: Evisceration must land before
  Tackleberry's PLD/WAR Savage Blade confirms Fragmentation, then Dolomedes's
  Last Stand must confirm Light before the automatic Smalls/Achoo Thunder IV
  bursts. Barney, Smalls, and Achoo remain target-only.
- Routed the ordered Crusade -> Divine Emblem -> Sentinel -> Flash -> Provoke
  tank opener, setup, lead, middle, close, Harden Shell Dispel, Invincible Thunder
  proc, Light bursts, and cancellation through the exact
  `escha-ruaun-genbu-genmei/2.1.0.lua` semantic adapter. All six clients must
  prove protocol 1 for the current generation and epoch; no operator fight
  action is required after positioning and the pop.
- Removed the Genmei-named BRD/RDM/PLD branches from the shared helpers. The
  profile now selects frozen generic `magicboss`, `magicboss-protect`, and
  `manualsc` presets; Barwatera preparation and every fight-only action remain
  inside the pinned adapter, so no Genmei change can alter Barney's instrument
  scheduler or another profile's shared behavior.
- Added fixed Tortoise Song recovery semantics. They can cancel only the three
  reviewed song statuses on Barney and the two reviewed roll statuses on Dolo,
  allowing the established schedulers to republish a complete set before the
  runtime releases its packet-proven recovery hold. Each event uses one
  idempotency token across five bounded IPC attempts, so delivery can be retried
  without a duplicate request removing freshly restored effects.
- Made expensive-pop readiness bounded and single-use. A Genmei preflight pass
  expires after 90 seconds, is bound to one exact party-claimed Genbu life, and
  is revoked on release so a later pop cannot inherit Honor, lens, equipment,
  buff, action, or adapter proof.
- Synchronized the bounded preflight age as well as its epoch, so follower
  clients enforce the same expiration deadline instead of displaying a pass
  they could not use.
- Set the conservative support baseline to BRD/WHM, RDM/WHM, and GEO/WHM, with
  Kick DNC/WAR and Tackle PLD/WAR. Preflight now verifies Kick's
  Tauret/Ternion Dagger +1, Achoo's Dunna, every chain participant, and every
  required recipient after Tortoise Song.

## 0.8.0 - 2026-09-02

- Rebuilt `escha-ruaun-genbu-genmei` as v2.0.0: the exact party-claimed
  Genbu now drives automatic combat acquisition, post-Confrontation geomancy
  gating, Savage Blade -> Last Stand Light chains, dual Thunder IV bursts,
  Invincible/white-proc handling, Tortoise Song recovery holds, and automatic
  combat shutdown.
- Added a fixed four-verb Genmei semantic controller surface and a bounded
  GearSwap-side queue. Requests snapshot server ID, entity index, zone, life,
  and party claim, then revalidate resources/recast/range before ordinary
  GearSwap action dispatch. The queue has no equipment or slot surface and is
  completely inert without a request.
- Removed Genmei's nineteen immediate manual fight actions. AutoWS2 remains
  Off, GearSwap retains all Death Penalty/ammo and instrument ownership, and
  every older compiled profile-plan fingerprint remains unchanged.
- Corrected the impossible GEO Thunder V assumption to Thunder IV, changed
  the active roll pair to Samurai/Warlock, strengthened preflight quantities
  and action coverage, and added a no-pop queue-handler/readiness validation.
- Synchronized preflight PASS and revocation across all six runtimes, added a
  35-second packet-loss-safe Invincible release plus ready-only Thunder
  fallback, and made missing party vitals/healing below 70% outrank damage.
- Enabled automatic GEO/WHM Cure/status support for the conservative baseline;
  GEO/BLM remains an accepted later optimization.
- Added a generation/epoch-specific GearSwap capability handshake for every
  Genmei action job. Required queues acknowledge only protocol 1, revoke on
  both GearSwap job-file reload and addon unload, and block preflight when
  absent or stale.
- Expanded the expensive-pop preflight to verify live Protect, Shell,
  Barwater, song, and roll effects on the required recipients, with a bounded
  automatic retry while support finishes. Tortoise Song recovery now proves
  recipient coverage from successful post-strip packets rather than caster
  self-results.
- Classified out-of-range, paralysis, outside-AoE, and no-effect action
  packets as failures so they cannot satisfy setup, queue completion, burst,
  or rebuff evidence.

## 0.7.0 - 2026-09-02

- Revised `escha-ruaun-kammavaca` to v1.2.0 from live feedback. Silence and
  Horde Lullaby II are now non-blocking support; neither can delay the fast
  physical clear. The runtime no longer spends Stymie, Saboteur, or Rampart.
- Any associated living add immediately supersedes a Kammavaca boss lock and
  is forced in exact Clionid -> Limule -> Murex -> Amoeban order. A stale boss
  selection triggers bounded rolling add-force reassertion until Dolo's current
  target agrees; a new desired ID bypasses the old target's throttle.
- Added encounter association safety. Exact adds are accepted when
  party-claimed, or when unclaimed with valid x/y/z coordinates within 20
  yalms of the active party-claimed boss. Nonzero foreign claims, missing
  coordinates, and distant white copies are rejected.
- Added a read-only combat-readiness runtime signal. Kammavaca can queue
  non-damaging support early, but cannot submit PartyCombat force requests
  before the current six-client ACK and required preflight barriers pass.
- Routed automatic and manual exact-ID Silence through the GearSwap-owned RDM
  priority queue. The profile submits one semantic request per cycle; the
  controller owns busy-state deferral, priority, coalescing, bounded retry, and
  completion, while the fight runtime owns encounter-level rearm and its
  40-second refresh cycle. RDM/WHM is preferred for the low-threat fast clear.
- Made Barney's observer selection and queued sleep retry in bounded rolling
  cycles, so a transient startup, target, or distance miss cannot permanently
  exhaust automation. Boss-only engagement has a short 0.75-second settle;
  any later add still takes priority immediately.
- Removed unused direct manual combat actions from Kammavaca. Only queued
  `//pt sleep` and queued exact-ID `//pt silence` remain as profile actions;
  built-in `//pt force` and `//pt off` retain explicit controller/recovery use.
- Established the operator-action contract for future profiles: a character
  action named in a runbook must be a bounded GearSwap reservation, not a
  timing-sensitive one-shot command. A regression guard preserves the few
  explicitly identified legacy profiles without allowing new copies of that
  pattern.

## 0.6.0 - 2026-09-02

- Upgraded `escha-ruaun-kammavaca` to v1.1.0 with a bounded, profile-local
  encounter state machine. It waits for a party-claimed exact Kammavaca,
  spaces Smalls's Stymie -> Saboteur -> exact-ID Silence opener, requests one
  opening Rampart from Tackle, and fails closed until a positive Silence
  result is observed.
- Added automatic Barney observer selection through PartyCombat followed by
  the normal GearSwap-owned current-target Horde Lullaby II queue. Numeric-ID
  Bard casts are prohibited. Positive per-add Sleep results may accumulate
  across bounded retries; no-effect can preserve unexpired proof but cannot
  create or extend it.
- Added automatic exact-ID Clionid -> Limule -> Murex -> Amoeban -> Kammavaca
  handoffs. A new or respawned add revokes the sleep gate, and an add-free
  opening requires confirmed Silence plus a four-second entity-settle window.
- Made Kammavaca activation disable native auto-target on every client and
  deactivation restore it. Manual fight actions and Alt-L remain recovery
  controls, while GearSwap stays the sole equipment and instrument owner.
- PartyTactics now requests PartyCombat inert at load and commit. PartyCombat's
  generic typed force-by-ID and target-only observe-by-ID surfaces contain no
  fight names or profile branches. The Bard sleep reservation is available in
  every reviewed preset and still casts only against Barney's current target.
- Updated the Kammavaca safe reload, operator procedure, profile sentinels, and
  focused runtime tests for claim loss, action-lock spacing, partial/no-effect
  results, same-ID respawns, and automatic ordered engagement. Existing
  profiles retain their independently frozen compiled behavior.

## 0.5.0 - 2026-09-02

- Added the isolated `escha-ruaun-kammavaca` v1.0.0 profile for the regular
  six-character party. It sleeps the pack before engagement, uses a
  Silence-first opening, explicit Clionid -> Limule -> Murex -> Amoeban target
  handoffs, single-target physical damage, layered healing, and profile-local
  Chainspell/Exponential Burst guidance.
- Added a required six-client preflight for lenses, Kammavaca's binding, Echo
  Drops, reviewed melee weapons, Dolo's empty ranged-weapon slot, and the
  required sleep/Silence/tank/Geomancy actions. This prevents the prior Genmei
  gun mode from leaking into the Kammavaca melee setup without taking equipment
  ownership away from GearSwap.
- Added a bounded exact-enemy action adapter that resolves only profile-listed
  live enemies to numeric server IDs, then casts through normal GearSwap. This
  avoids GearSwap's intentional rejection of typed spawn-type-16 monster names
  without exposing raw commands, selection, movement, or equipment control.
- Added explicit Kammavaca auto-target Off/On helper scripts and a profile-only
  native AutoWS disable for Achoo, preventing wrong-add handoffs and stale GEO
  weapon-skill state without changing another profile's compiled plan.
- Reused existing GearSwap controller presets. No
  PartyCombat, AutoWS2, Roller2, HealBot, PartyStart controller, or existing
  profile behavior was changed. Existing compiled-plan fingerprints remain
  frozen and independently tested.
- Made the local BG Wiki vault the documented first research source for future
  profiles, with live/primary sources used to refresh or fill its gaps.
- Added an inert Kammavaca-only reload script and profile/runtime/transition
  regressions.

## 0.4.0 - 2026-09-01

- Added an optional profile-owned, six-client read-only preflight. Required
  profiles block combat until the current generation/epoch verifies actual
  equipped slots, inventory counts, key items, and available actions.
- Updated Genmei to v1.1.0 with an automatic delayed preflight. It verifies the
  required Death Penalty ranged slot, Animikii/Living Bullets and cards, all six
  lenses, the Honor, and the planned WS/Thunder toolkit.
- Made GearSwap weapon selection deterministic with `gs c weapons <mode>`.
  COR setup also pins CompensatorMode to Never and locks the selected weapons
  before Roller2 starts.
- Corrected Sel-Include's augmented-weapon comparison so table-form augmented
  definitions compare by item name instead of causing perpetual re-equips.
- Backported Selindrile's movement-edge guard so kiting refreshes happen once
  on movement start and once on stop instead of on every position packet.
- Restored the reference GearSwap ownership boundary for Dolomedes's existing
  `DualSavage` mode. It now owns Naegling/Gleti's Knife with an explicitly empty
  ranged slot, while normal TP, idle, and Savage Blade sets retain their reviewed
  stat ammo. Locus, Limbus, V1, PartyStart, and manual use share this one coherent
  mode; Genmei's ranged mode remains Death Penalty/Living Bullet, and Quick Draw
  remains Animikii Bullet. GearSwap now derives steady-state and non-ranged-action
  ammo compatibility from the selected weapon mode, preventing every gun-bearing
  mode from reproducing the same range/ammo loop.
- Removed the unsupported promise of a visible white proc from Genbu guidance;
  the sourced mechanic is that successful Thunder damage removes the
  post-Invincible gravity aura.
- Added a no-pop Ru'Aun rehearsal workflow and regression coverage proving a
  wrong ranged weapon fails preflight, revokes readiness, sends no commands,
  and blocks force/actions until repaired.

## 0.3.0 - 2026-09-01

- Added the isolated `escha-ruaun-genbu-genmei` v1.0.0 profile for repeatable
  Genmei Shield farming. It uses the fixed six-character composition,
  Tactician/Warlock, MagicTank songs plus Barwatera, Acumen/Malaise/Languor,
  a Genbu-specific RDM/PLD policy, alert-only encounter runtime, and explicit
  Last Stand -> Savage Blade Light/Thunder actions.
- Made Genmei offense manual-first. Dolomedes, Tackleberry, and Achoo receive
  reviewed weapon modes with AutoWS2 kept Off; Invincible Thunder procs,
  skillchain weapon skills, bursts, and removal fallbacks remain leader-issued
  typed actions. The baseline support subjobs are BRD/WHM, RDM/WHM, and
  GEO/BLM, with GEO/WHM retained as the healing-heavy fallback.
- Expanded the six-client signature into a complete behavior fingerprint: the
  canonical manifest, profile/runtime source, any declared profile-owned
  EasyFarm artifact, compiled member plans, each used manual adapter,
  PartyTactics core, integration add-ons, and both distributed and live common
  GearSwap controller surfaces must agree before commit. A missing artifact
  quarantines only its owning profile.
- Added an application barrier distinct from prepare voting. ACKs are scoped
  to an application epoch; zoning and Level Sync advance the epoch, discard old
  ACKs, and block arm, force, and manual actions until all six clients have
  applied and acknowledged the current policy.
- Made `combat.target_exclusions` mandatory for every profile. Limbus v1.2.0
  explicitly excludes whole-word Elemental enemies in both PartyCombat and
  AutoWS2; every other profile explicitly clears that session policy so it
  cannot leak across fights.
- Added manual-only offense for target-synchronized non-attackers. Such a
  member may select a reviewed weapon with `automatic=false`, but AutoWS2 stays
  Off and PartyCombat still never approaches or engages the member. The
  Dynamis boss Rudra fallback uses this boundary.
- Added separate profile-owned EasyFarm artifacts and matching declarative
  metadata for Locus and Limbus. Locus allows only `Locus Dire Bat`; Limbus
  carries the reviewed 14-name Limbus list, a whole-word Elemental ignore rule,
  and no XP-camp targets. Both use an 18-yalm detection radius, a 20-yalm Flash
  pull, and approach disabled. PartyTactics never starts or rewrites EasyFarm.
- Added isolated Protect-first RDM variants for Limbus, V1, and the Dynamis
  magic boss, plus opt-in managed GEO modes for the profiles that require
  guaranteed colure maintenance. Legacy unsuffixed presets remain unchanged,
  and GEO teardown restores `CombatEntrustOnly`.
- Current profile contracts are Locus 1.3.0, Limbus 1.2.0, V1 Breadwinner
  1.1.0, Dynamis-D route 1.2.0, Dynamis-D boss 1.2.1, and Genmei 1.0.0.
- Made the full staggered safe reload cover PartyCombat, AutoWS2, the five
  changed GearSwap controller clients, and PartyTactics. It is out-of-combat
  and inert: it never selects a profile or issues arm/force commands.

## 0.2.2 - 2026-09-01

- Added an isolated `locusbats-protect` RDM controller preset for the
  PartyTactics Locus profile. It establishes Protect first but intentionally
  leaves Shell off; the legacy PartyStart `locusbats` preset is unchanged.
- Added an opt-in guarded GEO colure heartbeat and pre-combat Entrust setting.
  Only Locus selects them; Limbus, V1, and the other profiles retain their
  frozen compiled plans. GEO teardown restores `CombatEntrustOnly`, preventing
  that Locus choice from leaking into the next profile.
- Documented that DNC Samba, Steps, and Flourishes begin only after the inert
  PartyCombat policy is armed and Kickpuncher is actually engaged.
- Hardened the PowerShell test launcher so a Lua assertion traceback fails the
  suite even when the Fengari CLI incorrectly exits with status zero.

## 0.2.1 - 2026-09-01

- Record the initiating client's prepare vote and application acknowledgement
  locally instead of assuming Windower IPC loops back to its sender.
- Run the six-client activation regression with sender loopback disabled and
  assert that the leader reaches six votes and six acknowledgements.

## 0.2.0 - 2026-09-01

- Added paired, isolated Dynamis-D Wave 1 route and boss profiles.
- Added reusable disabled-support, cure/status-only HealBot, and manual-offense
  compiler capabilities without changing any 0.1.0 profile plan.
- Added sandboxed typed manual actions plus a Clarion-guarded extra-song action.
- Added `//pt disarm` to stop PartyCombat while retaining support policy.
- Added generic BRD/RDM `magicboss`, PLD `manualsc`, and DNC `tankheal`
  GearSwap controller presets.
- Added frozen legacy-plan fingerprints and six-client route/boss transition,
  manual-action, AutoWS ownership, song-equipment-boundary, and kill-disarm
  regressions.
- Corrected the boss pull handoff so PartyCombat is armed before the puller's
  Flash establishes the synchronized target.
- Made the statue route stationary and force-driven so PartyCombat cannot run
  Dolo into melee before the automatic 1500-TP Leaden Salute.
- Added additive PLD native-buff/native-tank switches; the boss uses them so
  GearSwap cannot cast an early Flash or consume Divine Emblem, while PLD
  healing and explicit Flash/Provoke requests remain available.

## 0.1.0 - 2026-08-31

- Added isolated directory-based profile loading and schema validation.
- Added six-client prepare/commit activation with profile signatures,
  acknowledgements, fail-closed job/runtime handling, and state rejoin.
- Added sandboxed profile-owned chunks and a typed runtime action API with no
  equipment or raw-command surface.
- Migrated Locus Dire Bats, Limbus 119, and August 2026 V1 Breadwinner.
- Added modular Limbus manual sleep and V1 encounter runtime.
- Added compiler, source-boundary, isolation, and six-client protocol tests.
