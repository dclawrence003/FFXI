# Locus Dire Bats: PartyTactics Signet sustain derivative

## Scope

This profile is an isolated derivative of `locus-dire-bats-tomb` 1.3.0. It
keeps that profile's already-proven stationary combat, support, and offense,
then adds three narrowly owned services:

1. generation-bound LocusPuller control with a bounded PLD Flash/first-hit
   window;
2. all-six Signet renewal with an explicit drain and fresh-report barrier;
3. Dolomedes's Jubilee Ring right-slot guard.

The ordinary Locus profile remains the EasyFarm version. This derivative has
no `easyfarm` declaration and never starts, stops, rewrites, or reads
EasyFarm. LocusPuller is its sole pull owner.

## Proven combat policy reused without shared edits

The base fight has not changed. The target is the exact `Locus Dire Bat` in
King Ranperre's Tomb, the camp is stationary, and all six characters attack
the common target. The derivative therefore selects the same frozen policy
surfaces as the ordinary profile:

- Corsair's Roll plus Samurai Roll;
- the `locusbats` BRD preset: Victory March, Mage's Ballad III, Blade
  Madrigal, Barblizzara, and an Elegy lane;
- the `locusbats-protect` RDM preset: party Protect, intentionally no Shell,
  Haste/Refresh/Phalanx maintenance, and Distract before Dia;
- lean managed Indi-Fury, Geo-Frailty, and entrusted Refresh;
- the established `locusbats` PLD and DNC policies;
- the same five non-COR 1000-TP offense declarations, with Dolomedes on the
  existing `DualEvis` Tauret/Gleti's Knife pair and 1000-TP Evisceration.
  COR/DNC or COR/NIN enables that offhand; COR/THF remains accepted by the
  main-job-only policy but cannot dual-wield.

The frozen compatibility helpers are selected by name only. No Signet,
Jubilee, or first-hit branch is added to a shared helper, so this profile
cannot alter the behavior of ordinary Locus or another fight.

## Pull and maintenance transaction

The puller starts inert when the profile commits. A fresh, signed, revisioned
PartyTactics state controls it: Ctrl-P/`//pt arm` requests pulling and Alt-P/
`//pt disarm` stops it. Loading the profile alone cannot acquire a target.
Each source request carries a monotonic sequence; Dolomedes alone serializes
accepted requests into the authoritative revision. A lower revision is stale,
an equal/same tuple is an idempotent repair, and an equal/conflicting bit is
invalid. OFF is immediate even during a controller gap. ON remains desired
state while GearSwap, the adapter, or Signet maintenance is unavailable and
cannot become effective until the exact current controller proves ready.

For an ordinary pull, Tackle selects only the nearest live, unclaimed or
party-claimed Locus Dire Bat within 20 yalms. The pinned adapter suppresses
only Tackle's automatic GearSwap tick and AutoWS2 while Flash establishes the
pull. The reservation is independently bounded to thirty seconds, which
outlives LocusPuller's legal eight-second Flash confirmation plus twenty-second
first-melee window. Command submission is not cast evidence: the puller
requires an unblocked outgoing `0x01A` packet with magic category 3, Flash ID
112, and the exact opening target. If the local command is swallowed, it is
silently retried every half-second only during the first five seconds; an exact
packet stops retries immediately. Manual
movement, target changes, spells, abilities, items, attacks, and weapon skills
always pass through. LocusPuller never toggles AutoWS2 itself: normal release
asks the adapter to restore that lane once, while terminal `keepoff` release
cannot race a profile stop or replacement by turning it back on.

When any fresh report says Signet is absent for two seconds, the leader asks
LocusPuller to drain. This includes an initial all-missing profile load, so
renewal completes before the operator starts the first XP pull. A pending
Flash/engage and an already active fight may finish, but another target cannot
be acquired. Staff preparation requires both the generation/epoch-specific
`pullerdrained` acknowledgment and two continuous seconds with all six
characters idle.

The staff transaction is local to each character:

1. suspend automatic PartyCombat, AutoWS2, roll/support, and HealBot lanes;
2. if Signet is already present, report complete without touching the staff;
3. otherwise disable GearSwap's main/sub slots;
4. equip and raw-verify item 17583, Kgd. Signet Staff;
5. start a fresh 42.5-second timer only while that exact staff remains in main;
6. reset the timer and repair the item if anything displaces it;
7. retry `/item` at a bounded interval when needed;
8. accept only actual Signet buff 253 as success;
9. resume the prior operator state only after all six fresh reports confirm
   Signet.

The companion decodes the staff's enchantment metadata before use. A decoded
zero-charge staff leaves the maintenance transaction paused with a
rate-limited diagnostic instead of sending an endless item-command loop or
pretending success. If metadata cannot be decoded, actual Signet remains the
only success proof and the ordinary bounded retry path remains in force. That
fail-closed behavior affects the renewal transaction only; it is not an input
or combat authorization gate.

Every renewal carries a positive, monotonically increasing cycle token through
phase reports, puller drain, adapter suspend/resume, and adapter ACKs. A proof
from an earlier cycle in the same PartyTactics generation cannot suspend,
resume, or complete a later cycle. A truly fresh generation must begin with
cycle 1. Full GearSwap recovery deliberately restarts an interrupted renewal
under its successor generation, so it also begins again at cycle 1 rather than
carrying an unverifiable partial timer or later-cycle token across the reset.
The cycle token orders the mechanical maintenance phase; it does not supersede
the operator revision. Resume therefore applies the adapter's current operator
high-water, not an older ON bit captured before Alt-P. Even a delayed stale
resume finishes the mechanical suspension using the newer current bit, so it
can neither re-arm combat nor strand the adapter permanently suspended.

Controller probes use a lifecycle fence rather than numerically comparing
generation nonces (whose player and clock components belong to different
processes). An exact generation/epoch retry is idempotent, and the same bound
generation may advance only to an equal or higher epoch. While authority is
bound, every different generation is rejected. Normal PartyTactics teardown
first leaves the adapter unbound; the one bounded GearSwap-reload handoff is
the sole exception and admits one different generation at epoch zero. Retired
exact tuples and lower epochs remain fenced, so delayed predecessor probes
cannot detach current companions or reclaim a released lifecycle.

## GearSwap reload boundary

A standalone GearSwap reload is a short recovery handoff, not a profile
departure. Before its adapter instance disappears, each client turns
PartyCombat, AutoWS2, HealBot, and applicable RollTracker automation off and
marks its exact generation/epoch in the standalone keepers. JubileeKeeper and
SignetKeeper retain and raw-reassert their owned slots while GearSwap is down;
LocusPuller retains its exact operator/drain state without acquiring through a
missing opener gate.

The leader keeper coalesces simultaneous client notices into one exact
`pt __recover_controller` request. PartyTactics accepts it only for the exact
still-active lifecycle with no competing transition, then starts one full
distributed reapply. This reruns the complete compiler plan--weapon modes and
every BRD/RDM/GEO/PLD/DNC/COR lane--instead of merely reloading the adapter into
a half-configured job file. The prior desired operator state is carried as
successor state and remains live-updatable by Ctrl-P/Alt-P; it is not a raw
delayed `pt arm`. PartyCombat becomes effective on each client only after that
client proves its newly authorized controller. Recovery accepts only an
epoch-zero probe for a fresh, different PartyTactics generation with the exact
same profile, version, leader, and roster. A same-generation recovery, altered
authority, or delayed predecessor message cannot inherit it. An interrupted
staff transaction restarts at cycle 1 with a raw-verified 42.5-second timer;
safety is preferred to crediting time that crossed a GearSwap reset.

The reload handoff is bounded. Expiry, profile stop/replacement, zone
departure, logout, or conflicting PartyTactics authority performs ordinary
terminal teardown and never restarts the profile. Those paths release the
puller with `keepoff`, so nested cleanup cannot turn AutoWS2 back on.
Profile stop, PartyTactics unload, and replacement by a different profile
additionally invoke declarative local companion fences directly from
PartyTactics. Each receives the exact stopped generation plus validated
engine/profile/version/signature/source tuple, so these terminal transitions
remain effective during a GearSwap host gap and on the initiating client
without IPC loopback. Same-profile recovery does not issue a stop fence and
therefore preserves Jubilee/Signet ownership through its authorized handoff.
The command prefixes live only in this profile and are schema-restricted to two
lower-case tokens; the shared core contains no Signet-specific add-on name.
Stop, operator-request, operator-state, and periodic state IPC are exact 10-,
11-, 11-, and 15-field protocols; prepare/commit are exact 13-field carriers.
Surplus data, malformed epochs/revisions, stale lower revisions, and equal-
revision bit conflicts are rejected rather than interpreted differently by
core and companions. Local controller ready/lost/terminal/
recovery callbacks also reject surplus arguments.
An outside-Tomb activation remains installed only as an inert local timer
owner: it grants no controller or companion authority. It applies the complete
OFF baseline immediately and once more after two seconds so older queued
compiler commands cannot win. A successful probe or any profile deactivation
cancels that adapter-owned retry, so it cannot fire into the next profile.

## Equipment boundary

PartyTactics itself never equips an item. The pinned adapter supplies scoped
lifecycle authority to the companion keepers, and GearSwap continues to own
the actual slots.

Jubilee Ring item 27593 is guarded only on Dolomedes and only in `ring2` /
`right_ring`. The left ring is neither selected nor locked. The ring guard
remains active during staff renewal and through a bounded standalone GearSwap
reload. It releases on matching profile teardown, replacement, zone departure,
logout, PartyTactics unload, or failed/expired recovery.

## Recommended jobs

- Dolomedes: COR/DNC or COR/NIN for `DualEvis` with Tauret and Gleti's Knife.
  COR/THF remains accepted by the main-job-only policy but cannot equip its
  offhand weapon.
- Tackleberry: PLD/WAR.
- Kickpuncher: DNC/WAR.
- Barneystinson: BRD/WHM.
- Smalls: RDM/WHM.
- Achoo: GEO/BLM.

These subjobs are recommendations, not validation requirements. The profile
deliberately declares only each main job in `members`, and the pinned adapter
establishes authority from the exact roster name and main job alone. A
different subjob never withholds profile application, controller authority,
or manual control.

## Local evidence and migration boundary

The implementation requirements came from the supplied transcript of the
misplaced PartyStart experiment and from the established PartyTactics Locus
profile/research. The experiment proved the staff displacement/reset rules,
the explicit pull-drain race fix, and the right-ring requirement. This
migration retains those requirements but rejects its orchestration boundary:
PartyStart is neither loaded nor called.

The current behavioral contract is pinned to profile/adapter version 1.6.0 and
controller protocol 2. Adapters 1.0.0 through 1.5.0 remain present and
hash-frozen historical artifacts; none was edited in place. Version 1.6.0
retains 1.5.0's exact, generation/epoch-scoped binding proof from every local
SignetKeeper, plus LocusPuller on Tackle and JubileeKeeper on Dolo, before the
adapter reports controller readiness. It keeps native AutoTank and the frozen
shared PLD preset off, leaving LocusPuller as the sole owner of Flash while the
compiler retains native AutoBuff upkeep. A future behavior change must create
another adapter version and must not repurpose an immutable adapter for another
profile.

Version 1.6.0 changes only the maintenance-resume delivery edge. GearSwap's
addon-scoped IPC cannot deliver a proof to the separate SignetKeeper addon, so
suspend and resume acknowledge the local keeper through its exact `sk
__adapter` command. An exact duplicate resume now reasserts the complete
profile-owned running baseline--AutoWS2, COR Roller2 or RDM support where
applicable, and the current ordered PartyCombat bit--before returning another
local acknowledgment. If the first resume batch was only partly delivered,
the retry reissues every lane without advancing the cycle or weakening
operator revision ordering. The acknowledgment proves that the adapter
accepted and queued the complete exact-cycle repair; subsequent PartyTactics
operator heartbeats continue reconciling the combat bit.

The first complete live renewal on 2026-09-15 supplied the staff timing
boundary. Tackleberry, Kickpuncher, Barneystinson, Smalls, and Achoo all sent a
first item command at 30.5 seconds with no native item action or error, then
all five succeeded on the exact 12-second retry. The production delay is
therefore 42.5 seconds from the latest uninterrupted raw staff verification.
The retry remains indefinite at 12-second intervals, and only buff 253 can
complete the transaction. Dolomedes already had Signet and correctly crossed
the same barriers without equipping or using his staff.

The same PartyOps sample found 283 Cure III completions restoring 402,136 HP,
versus only 34,203 HP of measured party damage. Version 1.5.0 therefore owns a
Tackle-only sustain lane in this adapter rather than changing the shared PLD
helper used by other profiles. While Tackle is engaged, it uses Cure III when
the lowest in-range living member is below 65%, or when at least three are
below 70%; below 55% it uses Cure IV with Cure III fallback. Routine and cluster
healing hold below 30% MP, while emergency healing does not. Majesty is used
when ready, every dispatch has a bounded pending/retry lease, and an opener
reservation or post-kill idle state always wins so healing cannot spend the
next pull's Flash window. The adapter issues no Flash and filters no manual
action.

## PartyOps baseline before 1.5.0 reload

The 2026-09-15 capture contained 118 completed bat cycles over about 117
minutes. Duplicate Flash, not damage or MP, was the dominant throughput loss:
98 cycles had more than one completed Flash, for 248 Flash completions and 120
Provokes against 118 kills. Median kill-to-next-opener time was 18.2 seconds
(90th percentile 43.5 seconds), while median combat time was 29.7 seconds.
This is the comparison baseline for the first live 1.5.0 sample.

All six attackers made useful contributions. Observed damage shares were
Kickpuncher 30.9%, Dolomedes 19.3%, Barneystinson 16.7%, Smalls 16.0%,
Tackleberry 11.2%, and Achoo 6.0%; Achoo's feed ended early, so his result is
undercounted. Median weapon skills ranged from 12,902 to 19,410. No normalized
action failed, and all characters retained healthy MP reserves. Dia III,
Distract III, and Carnage Elegy were approximately one successful cast per
pull. Preserve the current non-PLD offense and support policy until 20--30
post-reload kills establish the new pull-cadence baseline.
