# Bozzetto Bigwig / Qutrub — no-Cait cooperative variant

Research finalized 2026-09-03 and revised from live evidence 2026-09-16.
This is the design record for the isolated
`ambuscade-2026-09-v1-qutrub-bigwig-no-cait` profile. It is passive
documentation, not executable policy. It must never share mutable encounter
state, adapter state, or feature flags with the Cait Sith profile.

## Current v1.14.0 decision and confidence

The 2026-09-16 corrected-difficulty Normal run was a clean win: Bigwig was
present from 21:52:31 to 22:05:06 EDT and nobody died. All six PartyOps
clients captured this run. The first Normal wave spawned Tormentor,
Astrologer, Tormentor at 21:55:17, :22, and :27. The intended 6.25-second
quiet assembly kept Barney and the unassigned Dolo/Kick lane from committing
until about 21:55:34; that initial pause is a Triple Reversal safety measure,
not a movement failure. Thereafter the trace shows actual intermittent missed
engagement: when the Astrologer and one Tormentor died at 21:57:19 and :26,
Kick was briefly back on Bigwig and Dolo did not issue a combat request on the
last live Tormentor until 21:58:01. The second wave also left Barney and Achoo
without the next live add for roughly thirty seconds after the Astrologer
died. The old pursuit repair watched only characters who had *already*
reached an add, so it could not repair a dropped initial edge or a stale
nearby battle target. Version 1.14.0 grants one exact acquire repair after
4.5 seconds without progress or a completed attack on the assigned add. It
leaves a closing attacker alone and never creates a continuous snap loop.

Dolomedes completed 41 Eviscerations and no Last Stand in this win. The
profile still specified Last Stand, so this was an AutoWS2 state discrepancy,
not a tactical switch. Windower's XML loader lowercases setting keys while
AutoWS2 generated mixed-case player/job/weapon keys; the saved Dolo file
contains conflicting mixed-case and lowercase weapon entries. AutoWS2 0.3.7
now uses canonical lowercase keys. The profile pins only Dolo's *automatic*
Last Stand for the active session, independent of temporary main-weapon
changes. AutoWS2 off or a manual `//aws2 use` clears that pin, and manual
weapon skills were never intercepted. This run validates v1.13.0's inert
pre-pull staging on Normal; the acquisition and WS corrections require the
next live validation before any Difficult promotion.

## v1.13.0 basis

The 2026-09-15 Normal clear entered at 19:42:37 EDT and exited at 19:52:51,
with Bigwig active for roughly 9:42. Nobody died. The five captured local
streams recorded 104 completed weapon skills: 34 Last Stands, 36
Eviscerations, 24 Savage Blades from Barney, seven from Tackle, and three
Black Halos from Achoo. No weapon skill returned to Bigwig during either add
wave. Both waves behaved almost identically: the Astrologer died 53 and 56
seconds after its spawn, and the last Tormentor died 115 and 121 seconds after
its spawn. Achoo's own PartyOps client was not connected for this capture, so
his actions are visible through the other clients but his local HP, MP, and
position timeline is unavailable.

Shadow response was conclusive. Bigwig completed five Phantom Whorls in the
final phase and every target result was an avoidance message consistent with
a Copy Image absorb; no Phantom Whorl damage landed. Dia III and Light Shot
formed seven confirmed same-target ordered pairs. Focus-only Blank Gaze and
Dispel removed Fortifying/Animating Wail effects without an area-enmity lane.
There was no Triple Reversal. The direct-target ledger did observe one brief
wave-one convergence of Bigwig, the Astrologer, and a parked Tormentor on
Kickpuncher; his lane stopped in about four tenths of a second and resumed
after redistribution. That recovery is good Normal evidence but remains a
promotion risk for Difficult's larger add set.

Smalls converted once near 30% MP, immediately recovered himself, and ended
near 16% MP rather than becoming action-starved. The lowest captured party
HP was Dolomedes at 28.8% after Turn the Tables; Smalls began the first Cure
III about three seconds later and continued recovery. Tackle, Kick, and Barney
never fell below roughly 67-70%. This validates the profile-local cure and
post-Convert changes without justifying a further healing reduction. Only
Smalls showed captured Reraise; Achoo completed a Reraise cast, while the four
non-mages still need eligible items before their best-effort lanes can work.

The remaining defect happened before this successful combat sequence. The
direct profile alias armed against visible unclaimed Bigwig and immediately
assigned Dolo, Kick, and Barney while Protect and songs were still underway.
Version 1.13.0 introduces a profile-local preparation state. Arming may bind
the exact live boss and continue food, shadows, defensive buffs, Reraise, and
healing, but it cannot move, engage, enfeeble, or place geomancy on an enemy.
Dolo's first exact action against Bigwig, Bigwig's first action against the
party, or the corresponding party claim releases the existing combat state
machine. This adds no second command, diagnostic, readiness test, or result
gate. One more Normal clear should validate this boundary and restore Achoo's
local capture before a Difficult attempt.

## v1.12.0 basis

Version 1.12.0 removes the profile's dependency on an unversioned
`qutrubnocait` addition to the shared PartyStart RDM helper. The compiled plan
now selects the immutable `sortieacuex` preset for its generic Composure,
Haste/Refresh/Phalanx, Gain-MND, Aquaveil, Reraise, Convert, and bounded self
maintenance. All Qutrub-specific healing and opening defense remain inside the
profile's append-only adapter 1.10.0 and encounter runtime; no frozen helper or
unrelated profile changes behavior.

The adapter selects the exact lowest living, in-range party member through 74%
HP both before encounter bind and after finish. During a bound fight, the
runtime submits the same stable exact-target task; a local pending record
de-duplicates both paths. Cure choice matches the reviewed MP-efficient tiers,
and only actual spell MP/readiness can defer it. A completed Convert reserves
the next local automatic actions for self-Cure through 90% HP or twenty
seconds, while every manual GearSwap callback remains pass-through.
Both runtime and adapter require a living target with known geometry inside
20.5 yalms for Smalls' primary lane and Tackle's delayed 40% backup. While
primary healing preempts Smalls' tactics, repeated periodic requests coalesce
by semantic and exact subject; recovery therefore resumes a bounded current
queue rather than replaying every stale timestamped refresh.
Reactive Ice Spikes and Wail Dispels retain separate task identities because
one Dispel removes only one effect. A held Wail request does not consume its
bounded retry count until dispatch. Task subjects also carry an explicit
hostile/party domain, preventing an enemy focus change from deleting queued
Indi-Wilt, emergency Cure, or Curaga wake work aimed at a party member.

Opening order is deliberately composed rather than claimed as byte-for-byte
parity with the removed helper preset. PartyStart's activation command invokes
one immediate generic action before the host tick wrapper; that action is
normally Composure. From the next automatic tick, the adapter reserves one
available Shellra with individual Shell fallback and Protect on five living
targets before subsequent frozen-helper upkeep resumes. It enforces a 35%
post-cast floor for its Protect casts and withholds ordinary shared ticks at
30-34% MPP. The frozen core keeps its own conservative 20% frontline Phalanx
floor rather than the removed preset's 15%. This prioritizes serialization and
isolation over reproducing an unreviewed shared mutation exactly.

## v1.11.0 basis

The 2026-09-14 Normal clear validated multi-wave pickup and shared-focus
offense, but isolated two remaining scheduler failures. Tackleberry never
received a Bigwig combat assignment during the second wave; instead, two of
his Savage Blades and four of Barneystinson's resolved through a transient
Bigwig `<bt>` while their direct melee packets continued to name a Tormentor.
AutoWS2 0.3.6 retains exact target-transition acknowledgement, adds completed
local melee/ranged target evidence, and sends automatic weapon skills to that
numeric entity ID. This changes no manual command or target.

Smalls used Convert during the same run, reached roughly 20% HP, and generated
three Cure IV requests that never became server casts. After Dolomedes
reraised at roughly 18-25%, the encounter runtime's final-phase threshold fell
from 55% to 12%; Smalls therefore selected Haste, Phalanx, Refresh, and
enfeebles while Dolo remained red. Version 1.11.0 gives the isolated
`qutrubnocait` PartyStart preset sole primary-heal ownership at 75%, evaluates
that lane before upkeep, and uses its existing guarded post-Convert recovery.
Coordinator-owned Smalls tactics wait while a living member is yellow, while
Tackle's delayed Cure IV remains a 40% backstop in every phase. The opening
buff plan is reduced from thirty casts to one Shellra, five Protects, five
Hastes, four Refreshes, and four frontline Phalanxes under a 35% routine MP
floor. Exact focus Dia also requires a landing packet and retries at most
three times before enabling its one Light Shot.

The run was a Normal win, so the established add ownership and threat-budget
state machine remains unchanged. Version 1.11.0 has deterministic coverage
for exact-ID automatic WS, direct-target recovery, healing-first scheduling,
post-Convert recovery, all-phase PLD backup, and bounded Dia retries.

## v1.10.0 basis

The PartyOps review of
`tools/ambuscade_normal_clear_20260913_1132_partyops.json` exposed a distinct
pickup-loop defect after the broader v1.9.0 improvements. Dolomedes attempted
nine Light Shots and all nine reported message 324. Kickpuncher completed no
Violent Flourish and produced 35 "not enough finishing moves" failures in
roughly three minutes. Reissuing either request every few seconds did not
prove or preserve the intended parked-add ownership and spent command
bandwidth that should have gone to movement and offense.

Version 1.10.0 separates a pickup attempt from pickup proof. Dolomedes gets
one exact Light Shot per ownership episode and Kickpuncher gets one exact Box
Step. The action packet is recorded only as the attempt; it never confirms
enmity. Known coordinates defer Light Shot until Dolomedes is within 22 yalms
and Box Step until Kickpuncher has reached melee, so neither one-shot episode
is consumed while PartyCombat is still closing distance. Unique anchors
remain through the fixed quiet assembly phase. Once it ends, an unconfirmed exact pickup remains for at most eight seconds and
releases early only when the add's own direct melee or primary TP target names
the assigned owner. A direct target on somebody else opens one bounded repair
episode. Sequential roster growth preserves already-confirmed assignments but
starts a fresh episode for a genuinely new or reassigned add.

Box Step is the routine DNC tag because it creates finishing stock instead of
requiring it. Adapter 1.9.0 verifies at least 100 TP and recast 220 before it
submits that exact step. Violent Flourish remains available for the reactive
Triple Reversal lane, but the adapter now checks finishing-move buff IDs
381-385/588 and recast 221 before issuing it. Missing stock or an active
recast becomes a local no-op, so the old failure cannot enter a retry loop.
If a stale buff snapshot still races a server message 524 rejection, that
result opens a ten-second local automatic backoff before the stock and recast
checks run again. These checks govern only automatic profile requests: manual abilities,
targets, movement, and disengagement remain unfiltered, and none of them can
gate activation.

Profile 1.10.0 and adapter 1.9.0 have focused deterministic coverage for
one-attempt pickup episodes, positive direct-target confirmation, bounded
fallback, drift repair, sequential add waves, TP/recast checks, and
finishing-move checks. They await live validation.

## v1.9.0 basis

The 2026-09-13 Normal clear in
`tools/ambuscade_normal_clear_20260913_1132_partyops.json` validated the
sequential-wave threat budget: nobody died and no observed member held three
direct hostile targets. It also isolated four throughput/recovery defects.
Target-to-target assignment changes were emitted as `/attack off` followed by
an exact force; a late stop packet could erase the newer target. During add
waves, 90 of 114 AutoWS2 request packets from Dolo, Tackle, Kick, and Barney
still named stale Bigwig, and 13 of 30 completed weapon skills landed there.
Version 1.9.0 makes every target-to-target transition one atomic exact edge;
only a genuinely unassigned lane is disengaged. AutoWS2 0.3.5 additionally
observes exact 0x01A combat-target changes and holds only its own automatic
weapon skill until `<bt>` acknowledges the same entity ID. Manual targets and
manual weapon skills remain unfiltered.

The same capture showed that free-running parked control was competing with
offense. All nine Light Shots returned message 324, including shots fired
before the target's Dia III. That visible miss is the separate Sleep component
on these sleep-immune Qutrub; it is not evidence that an already-present Dia
failed to receive its enhancement. Version 1.9.0 limits Dolo's parked Light
Shot to initial anchoring or a directly observed repair. On the common focus,
a completed Dia III starts a distinct same-target Light Shot transaction. Any
observed execution ends that cycle because the Dia enhancement caps after one
shot; only a submitted command that produces no action packet can retry. Every
later completed Dia refresh creates a fresh enhancement cycle.

Fortifying Wail cleanup is now focus-scoped and result-aware. Fortifying and
Animating Wail recipients are remembered, but no strip fires while they are
parked. When a protected add becomes the shared focus, Tackle attempts exact
Blank Gaze first and Smalls alternates exact Dispel only if removal is not
confirmed. This preserves the two-hostile budget and eliminates three-add
Geist Wall as well as off-focus target churn.

Smalls's native `magicboss-protect` healing was still active independently of
HealBot and produced the observed small Cure spam. The profile now uses the
non-healing `physical` PartyStart maintenance preset; the encounter runtime is
the only RDM cure scheduler. Smalls retains its exact lowest-member Cure IV at
55% or below. At 40% or below Tackle schedules an independent Cure IV 1.25
seconds later; adapter-side HP revalidation turns it into a no-op if Smalls
already recovered that exact member. Profile 1.9.0, adapter 1.8.0, and
AutoWS2 0.3.5 have deterministic coverage for these changes and await live
validation.

## v1.8.0 basis

The salvaged 2026-09-12 Normal clear is reconstructed from all six clients in
`tools/ambuscade_normal_clear_20260912_latest_partyops.json`. It validates the
v1.7.0 shared-focus idea but disproves its fixed 2.5-second pickup assumption.
The second wave assembled sequentially: the first Tormentor became live at
18:23:42.470 UTC, the Astrologer at 18:23:47.320, and the second Tormentor at
18:23:52.370. Releasing shared offense before the roster finished growing let
new hate overlap the intended assignments.

The fatal convergence is direct packet evidence, not an inference from spell
targets. Bigwig meleed Dolomedes at 18:23:55.791, the Astrologer had directly
meleed him at 18:23:52.045, and the newly spawned Tormentor meleed him at
18:23:57.756. Bigwig readied Triple Reversal at 18:23:58.197 and resolved it
for 33,298 at 18:23:59.097. Dolo had completed Utsusemi: Ni at 18:23:49.289
and Ichi at 18:23:55.798, so this was the documented unmitigable three-foe
mechanic—not a missing-shadow death. The Astrologer's intervening Bind target
was Barney, demonstrating why hostile spell targets cannot stand in for its
enmity owner.

The allocation itself remains sound once its order is made explicit. During
wave assembly, all Bigwig offense pauses and every visible enemy gets one
unique exact anchor: Tackle uses Flash/Blank Gaze on the first Tormentor,
Achoo /WHM uses Flash on the Astrologer, and the Dolo/Kick member not holding
Bigwig uses Light Shot or Violent Flourish on the second Tormentor. Each new
spawn restarts a 6.25-second quiet interval. Only after that bounded interval
do Dolo, Tackle, Kick, Barney, and Achoo collapse onto one Astrologer-first
focus. That preserves the intended budget: each anchor has its parked enemy
plus focus, the holder has Bigwig plus focus, and Barney has only focus.

This is safer than blanket PLD pickup. Sentinel, Palisade, Sheep Song, Geist
Wall, and Jettatura are suppressed while a Normal wave is still assembling.
Exact capture does not put Tackle on all three lists. A direct-target ledger is
also retained as a recovery layer: if Bigwig/add melee or primary TP packets
show three hostiles converged on one combat member, that member receives one
stop edge and unique anchors immediately recapture their assigned enemies. It
returns automatically once the direct targets redistribute. This reaction is
useful protection, but the preventive unique-anchor sequence remains primary
because Triple Reversal can resolve too quickly to promise a reactive save.

Smalls's MP loss was also deterministic. In this fight it completed 61 Cure
III and 52 Cure II casts. Seventy-seven of those 113 cures targeted Smalls;
48 restored zero HP. Even after two Converts, Smalls ended at 13/1727 MP.
Version 1.8.0 therefore leaves HealBot status removal enabled but disables its
free-running cure selector. The runtime requests one exact Cure IV for the
lowest living member only at 55% HP or below and no faster than every 3.5
seconds. With no adds and Bigwig at or below 30%, it instead permits only a
Cure II rescue at 12% HP or below. Adapter-side live-HP revalidation discards
stale cures and preserves a 15% MP floor unless the target is a true emergency.

Kickpuncher's death near 19% was not merely bad luck. Bigwig repeatedly meleed
Kick after his 18:29:50.529 Ni, consuming the stack. Phantom Whorl was readied
at 18:30:04.286; Ichi did not begin until 18:30:05.149, and Whorl resolved for
14,965 at 18:30:07.356 before the cast could complete. The old local watcher
asked only for Ni when the last image disappeared, even while Ni was on
recast. Append-only adapter 1.7.0 now reads both live spell recasts, immediately
chooses Ichi at zero images when Ni is unavailable, suppresses duplicate
submissions, and retries locally while the stack remains low.

Profile 1.8.0 and adapter 1.7.0 pass deterministic tests for ten-second
sequential assembly, later waves and recycled entity slots, unique anchors,
three-target detection and release, hostile-spell exclusion, exact healing,
and recast-aware shadow fallback. They remain live-unvalidated. None of these
fight-state reactions is an activation prerequisite: checks, supplies,
geometry, action results, and difficulty never block start, and manual target,
movement, spell, ability, and disengage controls always pass through.

## v1.7.0 basis

The 2026-09-12 Normal wipe is reconstructed in
`tools/ambuscade_normal_wipe_20260912_latest_partyops.json` from the exact
3:57:50-4:10:30 PM UTC battlefield window. The analyzer now preserves hostile
actor IDs and direct target IDs, which separates the two same-named
Tormentors instead of conflating them. Triple Reversal dealt 33,333 to
Tackleberry at 4:07:56, Kickpuncher at 4:09:03, and Smalls at 4:09:54 UTC.

Immediately before the first fatal result, the latest direct hostile targets
were Bigwig -> Dolomedes (3.9 seconds old), Tormentor `17526885` ->
Tackleberry (3.3 seconds), Astrologer `17526886` -> Tackleberry (1.9 seconds),
and Tormentor `17526887` -> Tackleberry (3.5 seconds). This is positive
evidence that the old blanket pickup converged all three adds on Tackle. It
also matches the documented rule: Triple Reversal becomes available when
three or more encounter foes target one player, and Bigwig counts as one of
those foes. The damage is 33,333 and is not a mitigation check.

The same timeline exposed the wave-long holder latch as stale. Bigwig first
targeted Kickpuncher, then switched to Dolomedes at 4:01:38.955 UTC and spent
most of the remaining wave on Dolo. The old policy continued forcing Dolo to
chase adds because it never reconsidered the initial Kick assignment.

Version 1.7.0 replaces both behaviors with an explicit Normal threat budget.
Astrologer remains the one shared kill focus. Tackle briefly establishes one
off-focus Tormentor; the Dolo/Kick member not currently holding Bigwig briefly
establishes the other. After a 2.5-second pickup edge, Dolo, Tackle, Kick,
Barney, and Achoo all close on and damage the same focus. Tackle and the
nonholder therefore each have one parked add plus the focus; the holder has
Bigwig plus the focus; Barney and Achoo receive the focus only. No intended
lane exceeds two hostile targets.

Holding Bigwig no longer means standing in a corner. Dolo and Kick both join
the shared add focus. Bigwig is allowed to follow its hate holder into that
group because enemy proximity does not reduce damage. A five-second
Bars-equivalent direct-target review changes only ownership of the second
parked Tormentor; it never removes the current Bigwig holder from the kill
focus. If target evidence is stale, combat still continues and only that
second parked ownership waits for fresh evidence.

Normal no longer uses Tackle-wide Flash or area Blue Magic across all three
adds. Exact Flash and Blank Gaze stay on his one parked target; the nonholder
uses its exact Light Shot or Violent Flourish lane on the other. Fortifying
Wail with three adds uses Tackle's Blank Gaze only on his parked add and
Smalls's exact Dispel on the other recipients. Geist Wall remains available
only when at most two adds are alive, where it cannot itself converge three
adds on Tackle.

Both movement recovery layers are bounded. After an assigned attacker reaches
an add, separation beyond 4.5 yalms emits one exact return edge rather than a
polling target-snap loop. If a parked add is directly observed targeting the
wrong person, its owner gets one short recapture edge; that repair does not
rearm until the add is observed on its intended owner. Focus transitions also
stop broadcasting adapter `cancel`, preserving local Copy Image reactions.

All of these lanes remain cooperative and best effort. They impose no check,
ACK, buff, job, item, geometry, result, or difficulty gate and never filter
manual input. Version 1.7.0 has deterministic coverage for initial and later
waves, holder transfer, same-ID reuse, focus collapse, one-shot pursuit and
drift repair, three-add Wail cleanup, shadows, Reraise, and unconditional
disarm. The subsequent Normal clear above exposed the sequential-spawn,
free-running cure, and zero-image Ni-recast gaps that v1.8.0 supersedes.

## v1.6.0 basis

The 2:36-2:56 PM EDT run on 2026-09-11 cleared Normal in 19:48 from
battlefield entry and 17:33 from first Bigwig combat. The exact six-stream
reconstruction is
`tools/ambuscade_normal_clear_20260911_1436_partyops.json`. Wave one ran from
roughly 2:40:16 to 2:44:59; wave two reused the same three server entity slots
from roughly 2:48:05 to 2:54:10. The first Astrologer lived 2:49 and the second
4:02. That difference did not reveal proximity-based damage reduction: Dolo,
the party's second-largest damage source, correctly held Bigwig in wave two;
Tackle left the Astrologer for about two minutes; and Fortifying Wail applied
Protect to the pack.

The run also established that the v1.5.0 target acknowledgement, same-ID wave
reset, and local Copy Image logic worked. Initial pickup/grouping was clean,
both add generations completed, Phantom Whorl caused no death, and all six
survived. Remaining work is throughput/resource tuning rather than a new
safety gate.

There is no encounter damage-taken modifier based on Bigwig/add proximity.
Version 1.6.0 therefore replaces the earlier cross-room geometry with a compact
15-yalm center-to-center split. Tackle must actually arrive within 4.5 yalms of
the add focus before generic pack control: even in the worst straight-line
placement, that leaves 10.5 yalms to Bigwig, outside the nine-yalm Jettatura
cone and six-yalm Sheep Song/Geist Wall pulses. This also keeps the add focus
inside Dolo's 22-yalm Light Shot reach when he is positioned on the add-facing
side of Bigwig. The number is tactical clearance, not a damage or arm gate.

Version 1.6.0 makes Achoo a directed-only add attacker. He joins Tackle and
the two non-holders, carries Indi-Fury into their pack, places exact-subject
Geo-Frailty when he is in spell range, and spends TP with AutoWS2 Black Halo.
He and Tackle are both stopped on Bigwig. Once an assigned attacker first
reaches the shared add, a 1.25-second coordinate check reissues that exact
assignment only after separation exceeds 4.5 yalms. This repairs a lost chase
without continuously snapping targets inside the pack.

Smalls now owns routine HealBot cures/status removal alone. Achoo cast 43 Cure
III, 57 Cure II starts, nine Curaga II, two Curaga III, and four Cure IV starts
in the clear, then spent most of combat at 1-3% MP. Smalls reached zero twice
despite three Converts; many of his 38 Cure II and 58 Cure III casts raced
Achoo for already-recovered targets. Achoo's ordinary cure lane is therefore
off, while the encounter's bounded Curaga II Sleepga wake remains intact.

Every new damage focus now receives exact Dia III. A completed Dia III enables
one exact Light Shot if Dolo is within its 22-yalm range. Modern Quick Draw
testing places the added Defense Down at 28/1024 (about 2.73 percentage points)
and caps Dia enhancement after one shot. The clear contained five Light Shots
but no completed Dia III, so they supplied no group Defense Down. Fortifying
Wail now independently triggers caster-centered Geist Wall first, then queues
exact Blank Gaze cleanup for every live add recipient after the three-second
cast window. This preserves coverage when Geist is on its 30-second recast,
resists, or misses an add outside Tackle's six-yalm pulse.

### v1.5.0 basis

The 1:16-1:39 PM EDT Normal attempt on 2026-09-11 reached Bigwig's final
phase but wiped. The PartyOps reconstruction is
`tools/ambuscade_normal_20260911_1316_partyops.json`. It established three
implementation failures rather than a need for another difficulty gate:

1. PartyTactics emitted the correct exact Tormentor and then Astrologer edges,
   but PartyCombat yielded when the old battle target remained visible longer
   than two seconds. Kick never left Bigwig during the first wave, and later
   add transitions were manual.
2. Stopping all intentional Bigwig damage briefly turned the bound boss
   yellow. The runtime treated that claim-color gap as encounter completion,
   released authority at roughly 1:21:34 PM, and silently stopped second-wave,
   debuff, and shadow work.
3. Copy Image disappeared from Dolo, Kick, and Barney around 1:21-1:22 PM and
   was not restored before the final phase. Phantom Whorl then dealt lethal
   one-hit damage to Kick, Dolo, Barney, Tackle, Achoo, and Smalls in sequence.

PartyCombat 0.6.17 makes directed cross-arena delivery acknowledgement-driven:
it retries for at most 15 seconds only while the battle target remains the
exact known pre-transition target. Seeing the requested target clears the
allowance immediately; a third target or `//pc localstop` still yields at once.
AutoWS2 0.3.4 validates and fires on `<bt>`, so exact off-focus Flash or Gaze
cursor changes cannot spend TP on the wrong target.

The v1.5.0 wave split follows the target evidence already displayed by Bars.
Bars does not read a hidden enmity table: it records the primary party target
of a monster's latest direct action, treats a known AoE-primary result
separately from incidental victims, and marks confidence after six seconds.
At every add generation Dolo, Kick, and Barney first disengage. The eligible
member Bigwig most recently targeted stays parked; Tackle and the other two
run to a shared Astrologer-first focus. The choice is latched for the whole
wave. If no confident eligible target exists at the spawn frame, Tackle begins
capture alone and the other three stay disengaged until Bigwig's next direct
action resolves the split. When the visible pack dies, Tackle stops and all
three boss attackers automatically return.

Utsusemi is now locally loss-reactive. Each `/NIN` adapter observes its own
Copy Image count and requests Ni immediately below three copies; Ichi is legal
only at zero. The controller's ten-second pass is a recovery watchdog rather
than the primary trigger, and Phantom Whorl readiness independently requests
an immediate top-up. Temporary Bigwig claim-color changes no longer release a
live exact ID/index encounter.

All preparation and mechanic reactions remain independent best-effort lanes.
No check, acknowledgement, buff, geometry, action result, capture proof,
shadow state, Wilt result, health band, Reraise source, or difficulty policy
can authorize or block combat. The GearSwap adapter never filters manual
input; Ctrl-P starts encounter combat immediately and Alt-P stops encounter
combat. The v1.12.0 profile-local RDM support lane remains active until
`//pt off` or profile replacement.

## Prior Easy evidence

The 11:26-11:33 PM EDT Easy attempt on 2026-09-10 was a seven-minute clear
under v1.4.0. It validated the alternating boss/add assignments, repeated
generation handling, AutoWS2 damage, Tackle's PLD/BLU actions, `/NIN` shadows,
mage Reraise, recovery, and BRD song maintenance. March, Minuet, and Madrigal
refreshed on an approximately 3:40 cadence; Madrigal completed during the
second add wave. No party member died.

The clear also isolated a target-delivery defect. Windower could still report
the prior battle target on the frame after PartyCombat injected the new exact
target. PartyCombat interpreted that stale value as a manual override and
yielded before it approached. Kick and Barney therefore remained at Bigwig
until the operator moved them, Tackle did not complete the second-wave
Tormentor-to-Astrologer handoff, and the operator also supplied the return
movement. PartyCombat 0.6.16 attempted to address that with a two-second
delivery window; the Normal attempt proved the window was too short.
v1.4.1 also kept
Tackle's exact Flash/Blank Gaze tasks for every live secondary add when the
shared focus changes.

The first live run exposed compact resource names (`BozzettoBigwig` and
`BozzettoTormen`), an inactive weaponskill lane, and a target-selection loop
that reclaimed manual target changes. v1.2.0 corrected those issues. The same
capture also showed Bigwig near `(137,-137)` after the pull while the Tormentor
appeared around `(164,-156)`, about 33 yalms from the moved boss but only about
5.7 yalms from Bigwig's original `(160,-160)` spawn. v1.3.0 gave exact add
Flash first priority and a one-character add damage lane. The Easy wipe showed
that this did not provide enough automatic kill pressure or cover repeated add
generations. v1.4.0 instead directs Tackle, Kick, and Barney together, stops
Dolo during every add generation, and keeps every transition one-shot so
manual overrides stick.

PartyOps recorded Astrologer Sleep-family casts with delayed or absent wake
responses, no Utsusemi casts from the three `/NIN` attackers, and no Reraise on
four characters. At the final collapse an Astrologer and Tormentor completed
Triple Reversal within roughly one second while Bigwig was also converged on
the support side. v1.4.0 therefore adds loss-driven Ni/Ichi refresh, automatic
Curaga II wake attempts from both healers, best-owned-item/spell Reraise
maintenance, and the repeated add-first boss-damage freeze.

The remaining sections preserve the encounter evidence and the original v1.0
controlled-capture analysis. Where those historical sections describe a hold,
gate, forbidden manual action, promotion requirement, or six-second roster
wait, v1.7.0 supersedes it with the cooperative contract above. The Cait build
remains an independent option after Cait Sith is unlocked.

## Evidence

- Local BG Wiki vault:
  `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/ambuscade/ambuscade-archive.md`,
  Qutrub section around lines 4429-4567. It records the 80% first wave, 30%
  replacement wave, difficulty-dependent counts, Astrologer Silence,
  shadow-dependent finish, Triple Reversal danger, and the relative tradeoffs
  of killing, kiting, and Mewing the adds.
- [BG Wiki Ambuscade Archive](https://www.bg-wiki.com/ffxi/Ambuscade_Archive),
  the public counterpart to the cached encounter record.
- [BG Wiki Quick Draw](https://www.bg-wiki.com/ffxi/Quick_Draw), which records
  one Light Shot as +28/1024 Defense Down on an active Dia effect and states
  that the Dia enhancement caps after one shot.
- [FFXIclopedia Bigwig archive](https://ffxiclopedia.fandom.com/wiki/Ambuscade/Battlefield_Archive/Bozzetto_Bigwig),
  which explicitly lists every foe as immune to Sleep, Petrification, Weight,
  and Bind, documents the three-or-more-foes Triple Reversal trigger, says
  Bigwig counts, and lists the 33,333 damage. This rules out both Indi-Gravity
  and mitigation as answers to the fatal mechanic.
- [FF11 Japanese dictionary](https://wiki.ffo.jp/html/36752.html), which
  independently corroborates that Bigwig or its adds can use Triple Reversal
  when at least three encounter enemies target the same player.
- [Square Enix September 2024 version-update notes](https://forum.square-enix.com/ffxi/threads/62041-September-Version-Update),
  which warn that the boss's low-HP attacks gain an instant-death effect whose
  frequency rises while minions remain and advise defeating the minions first.
- [FFXIAH Qutrub discussion, page 7](https://www.ffxiah.com/forum/topic/55571/qutrub-ambuscade-v1/7/),
  which supplies the most relevant capture warnings: keep the PLD more than
  25 yalms from Bigwig, avoid post-claim cures and party-wide PLD job
  abilities, tag adds with Flash/Blank Gaze, and expect later sequential adds
  sometimes to inherit hate but also to be diverted by another actor's
  Utsusemi or Warcry. It says the adds appear in the middle; it does not prove
  a fixed coordinate suitable for unattended prepositioning.
- The 2026-09-10 PartyOps capture from the first Very Easy attempt supplies the
  local geometry used by v1.3.0: original Bigwig near `(160,-160)`, moved
  Bigwig near `(137,-137)`, and Tormentor near `(164,-156)`. This is one-run
  evidence, not a claim that every wave uses an identical coordinate.
- [FFXIAH Qutrub discussion, page 8](https://www.ffxiah.com/forum/topic/55571/qutrub-ambuscade-v1/8/),
  which compares split-and-kill, full kite, and Mew strategies. It describes
  one-PLD kiting as workable but vulnerable to erratic pathing, and advises
  against Sentinel/Rampart on add holders because party-wide enmity can pull
  Bigwig.
- [FFXIAH December 2018 Qutrub discussion](https://www.ffxiah.com/forum/topic/53082/ambuscade-volume-1-december-2018/5/),
  older corroboration that kiting can clear but pathing varies.
- [Japanese VD guide and video](https://www.kagurazakac.com/entry/2021/01/07/000000),
  community evidence for separating Bigwig at the start-side corner from the
  PLD's add-hold corner and for using Indi-Wilt against the physical add pack.
- Cached BG pages for `blank-gaze.md`, `sheep-song.md`, `geist-wall.md`,
  `jettatura.md`, `entrust.md`, and `indi-wilt.md`, plus the live
  [community RUN guide](https://www.bg-wiki.com/ffxi/Community_Rune_Fencer_Guide),
  [Blank Gaze](https://www.bg-wiki.com/ffxi/Blank_Gaze),
  [Sheep Song](https://www.bg-wiki.com/ffxi/Sheep_Song),
  [Geist Wall](https://www.bg-wiki.com/ffxi/Geist_Wall),
  [Jettatura](https://www.bg-wiki.com/ffxi/Jettatura),
  [Entrust](https://www.bg-wiki.com/ffxi/Entrust), and
  [Indi-Wilt](https://www.bg-wiki.com/ffxi/Indi-Wilt) pages. Sheep Song and Geist
  Wall are caster-centered 6-yalm AoEs; Jettatura is a caster-origin 9-yalm,
  roughly 30-45 degree cone; Blank Gaze is a 14-yalm single-target spell.
- Cached BG
  `misc/compendium-of-colure-the-art-of-geomancy.md` around lines 112-129
  and the live
  [Compendium of Colure](https://www.bg-wiki.com/ffxi/Compendium_of_Colure%3A_The_Art_of_Geomancy)
  document the special eligibility rule for enemy-targeting Indicolure: both
  the GEO and an Entrusted aura's bearer must be on an enemy's enmity list for
  that enemy to receive the debuff.
- Installed Windower resources under
  `C:/Program Files (x86)/Windower/res`, used to pin the action IDs and confirm
  `/BLU` level access. Resource presence does not prove that Tackle has learned
  or actively set a Blue Magic spell.

Community posts establish feasibility, not deterministic reliability for this
party, equipment, controller, or route. The exact add spawn coordinate is not
documented strongly enough to park Tackle unattended and assume every add will
be in a 6-yalm AoE. The historical controlled-capture design treated stable
roster discovery and result-confirmed tagging as mandatory; v1.7.0 records
those observations but never gates targeting or damage on them.

## Encounter facts that control the design

Bigwig starts alone. The first adds appear sequentially around 80% HP; defeated
adds return sequentially around 30%. Normal has one Astrologer and two
Tormentors, Difficult has two and two, and Very Difficult has two and three.
The runtime therefore evaluates the live roster continuously instead of
assuming all entities exist in the first frame. It reacts to each visible add
immediately and does not wait for a stable-roster timer; a newly appearing
later add produces the same add-focus transition.

The adds are immune to Sleep and Weight. Sheep Song is only an enmity tag;
Indi-Gravity would be a successful cast with no useful control effect. The
replacement is a fresh Entrusted Indi-Wilt on Tackle. Wilt does not slow or
bind anything; it reduces physical damage dealt by enemies inside the aura.
Both the exact status transaction and observed physical mitigation belong in
post-fight evidence.

At or below 30%, adds gain Triple Reversal when three or more encounter foes,
including Bigwig, converge on one target. Community reports include drains
above 30,000 HP. An out-of-range or interrupted attempt is useful evidence,
but no stun is treated as guaranteed. The finish also requires attacker
shadows and guarded healing because Bigwig gains dangerous physical/drain
behavior at low HP. Those safeguards are automatic best-effort work, not
progression gates.

## Exact party and subjobs

- **Dolomedes — COR/NIN:** Bigwig puller and independent AutoWS2 Last Stand
  user. During an add wave Dolo always joins the shared kill focus. When Kick
  holds Bigwig, Dolo also performs the brief second parked-add pickup and its
  exact Light Shot maintenance.
- **Tackleberry — PLD/BLU:** briefly establishes one parked off-focus add,
  then returns to the shared kill focus with AutoWS2 Savage Blade. On Normal
  he uses Flash and Blank Gaze only on that parked add; no three-add area
  enmity action is permitted.
- **Kickpuncher — DNC/NIN:** mobile attacker and independent AutoWS2
  Evisceration user. During an add wave Kick always joins the shared focus.
  When Dolo holds Bigwig, Kick also performs the brief second parked-add
  pickup and its bounded Violent Flourish maintenance. Native DNC automation
  remains disabled.
- **Barneystinson — BRD/NIN:** songs and independent AutoWS2 Savage Blade.
  Barney joins every shared add focus but owns no parked off-focus add; song
  upkeep continues throughout. GearSwap alone owns instruments, weapons,
  ranged equipment, ammo, and action sets.
- **Smalls — RDM/WHM:** exact Astrologer Silence, Ice Spikes Dispel, Bigwig
  debuffs/shadow strip, owner-safe Fortifying Wail Dispel, cures/status
  removal, Reraise, and the first Curaga II wake attempt after an Astrologer
  Sleep-family cast.
- **Achoo — GEO/WHM:** joins the shared add focus with Fury/Frailty and
  AutoWS2 Black Halo but owns no parked add. He preserves MP by leaving routine
  HealBot off, while retaining Entrust/Indi-Wilt, Reraise, and the backup
  Curaga II wake attempt.

Tackle's mandatory active `/BLU` set is exactly five spells and 12 points:

| Spell | Points | Role |
|---|---:|---|
| Cocoon | 1 | Self-defense |
| Blank Gaze | 2 | Fast, single-target add capture |
| Sheep Song | 2 | Caster-centered 6-yalm enmity tag; Sleep is irrelevant |
| Geist Wall | 3 | Caster-centered 6-yalm enmity tag |
| Jettatura | 4 | 9-yalm frontal-cone enmity tag |

Flash is a native PLD spell, not part of the Blue set. Preflight reports missing
spells, tools, equipment, or integration pieces as advisory diagnostics; it
never blocks profile start, targeting, damage, or manual action.

## Historical v1.0 enmity and capture safety analysis

Dolo's exact-ID Light Shot is the only pull. After its result confirms party
claim, the user drags Bigwig at least 10 yalms to the start-side corner. Tackle
remains near the recorded middle (within 15 yalms of the original origin) and
must be more than 25 yalms from Bigwig. The mobile attacker trio stays with
Bigwig until a stable wave is ready.

After claim, Tackle uses no party-wide PLD job ability and no Shield Bash.
Sentinel, Rampart, Divine Emblem, Palisade, and similar job abilities are not
part of the capture lane. Tackle also does not cure itself. This follows the
community warning that zone-wide party enmity can put PLD on Bigwig's hate
list. Capture uses only exact add-targeted Flash/Blank Gaze and geometry-bounded
Sheep Song, Geist Wall, and Jettatura. Kick's bounded Violent Flourish is the
only encounter-owned post-claim party job ability response.

There is no trustworthy positive `target_index` proof in the available packet
surface. A successful exact-subject Blue Magic or Flash result proves that the
named add was tagged; it does not prove that Tackle owns that add forever. In
the other direction, an exact action by an add against anyone other than
Tackle is valid negative evidence: the runtime revokes that add's tag, stops
offense, and reacquires it. This asymmetry must remain explicit in telemetry.

The capture guard is active while a threshold wave is settling, while the
stable roster has an untagged member, and during any revocation/reacquisition.
It freezes non-emergency legacy actions that might steal a fresh add or create
Bigwig hate. Exact emergency cures, status recovery, and permitted items may
continue. Native DNC automation remains off even outside the guard.

## Historical v1.0 phase policy

### Pull and first-wave capture

1. Dolo lands exact-ID Light Shot on Bigwig.
2. The user drags Bigwig to the start-side corner while Tackle stays in the
   middle. Automation waits for: Bigwig moved at least 10 yalms from its origin,
   Tackle within 15 yalms of that origin, Tackle more than 25 yalms from Bigwig,
   and the three attackers within 8 yalms of Bigwig.
3. Boss offense stops before the 80% threshold can be overrun. The runtime
   collects the sequential spawn roster and declares it stable only after six
   seconds with no new add.
4. Tackle captures each stable-roster entity using Blank Gaze/Flash and the
   bounded Blue AoEs/cone. Every successful exact Blue/Flash result tags only
   the result subject. Bigwig in a Tackle result is an immediate abort.
5. Smalls queues exact-ID Silence for each Astrologer and Dispel for confirmed
   Ice Spikes.
6. Once every stable-roster entity is tagged, the user moves Tackle and the
   pack to the kill corner. The mobile Dolo/Kick/Barney trio automatically
   leaves Bigwig, kills Astrologers first in stable entity order, then the
   Tormentors/Tormenters in stable entity order, and returns to Bigwig only
   after the roster is empty.

Stationary attackers cannot safely execute this geometry: they would remain at
the separated boss corner while wave-one adds are held elsewhere. Mobile mode
is therefore a required part of the no-Cait strategy, not an optimization.

### Second-wave capture, Wilt, and kite

1. Boss offense stops before 30%, attacker shadows refresh, and the runtime
   discovers the complete sequential second-wave roster with the same stable
   timer.
2. Tackle tags every stable-roster add while preserving the more-than-25-yalm
   Bigwig separation. Any exact off-target add action revokes the relevant tag
   and forces reacquisition before progression.
3. Only after all stable-roster tags exist, Achoo sends a **fresh** Entrust
   (job ability ID 386) and exact-target Indi-Wilt (spell ID 787) to Tackle.
   The transaction must finish with the exact Indi-Wilt action result targeting
   Tackle followed by a fresh remote `Colure Active` buff-612 proof on that
   exact Tackle entity. A stale, wrong-subject, or pre-wave aura cannot pass.
   Spell resource status 557 is the Attack Down effect applied to enemies
   inside Wilt; it is not the player-side aura buff and cannot prove the
   Entrusted spell landed on Tackle.
   Tackle's result-confirmed tags establish the anchor side of the Indicolure
   enmity requirement. Achoo's earlier exact Geo-Frailty puts the GEO on
   Bigwig's enmity list, and community reports that later adds can inherit boss
   hate make Achoo's add-side eligibility plausible. That second part is an
   inference, not exact proof. The profile does not add a GEO Diaga lane because
   the extra cross-hate action would undermine the capture boundary; instead,
   the Normal attempt must demonstrate real, survivable physical mitigation.
4. The user moves Tackle along walls and through corners, keeping the add pack
   away from Bigwig and the party and avoiding pillars. Pillars are treated as
   unsafe because erratic splitting/crossing can return an add to Triple
   Reversal range.
5. Dolo, Kick, and Barney stay on Bigwig and finish the automated chain while
   Smalls controls Astrologers/Bigwig and both supports maintain the guarded
   recovery policy.

There is no Weight cast, status, metric, or promotion dependency anywhere in
this variant. Wilt coverage is a damage-mitigation aid, not capture proof and
not a substitute for safe routing.

## Offense and mechanic reactions

AutoWS2 owns five independent TP lanes: Dolo Last Stand, Tackle Savage Blade,
Kick Evisceration, Barney Savage Blade, and add-only Achoo Black Halo.
PartyTactics does not submit or serialize weapon skills and does not require a
skillchain result. The current acknowledged PartyCombat battle target (`<bt>`)
determines where each attacker spends TP even when a capture spell temporarily
changes the cursor. Perfect Dodge, Utsusemi: San, missing shadows, failed
actions, and telemetry ambiguity may reduce effectiveness but do not hold
targeting, support, or manual input.

Triple Reversal preparation and result are always recorded. Kick may issue one
bounded Violent Flourish attempt when the exact reaction gate permits it, but
the profile assumes it can miss, resist, be out of range, or be interrupted.
The outcome—not the request—is what matters. GearSwap retains exclusive
equipment authority throughout.

## Difficulty validation

The next instrumented run validates v1.6.0 tuning rather than authorizing a
difficulty. The profile accepts any declared battlefield difficulty and
`//pt arm` never consults a promotion state. The next log should demonstrate:

- PartyTactics 0.11.2, PartyCombat 0.6.17, AutoWS2 0.3.4, adapter 1.5.0, and
  profile 1.6.0 were actually active.
- At each wave, the Bars-equivalent latest Bigwig target was parked and the
  other two boss attackers joined Tackle and Achoo on Astrologer then
  Tormentor. Each directed lane acknowledged `<bt>`, closed melee distance,
  stuck after arrival, and returned to its correct post-wave state.
- Tackle used exact Flash on every add, then one geometry-safe pack sequence
  of Jettatura, Sheep Song, and Geist Wall without splitting weapon skills.
- Copy Image loss caused an immediate local Ni attempt, Whorl preparation
  caused proactive top-ups, and the ten-second watchdog recovered any rejected
  cast without accumulating queued work.
- A yellow Bigwig remained bound and automated work continued through both
  add generations and the final phase.
- Achoo retained enough MP to maintain Indi-Fury/Frailty and used Black Halo;
  Smalls sustained solo routine healing with fewer cure races.
- Each focus received Dia III and, when Dolo was in range, exactly one useful
  Light Shot; Fortifying Wail recipients received prompt Blank Gaze attempts.

Normal cleared under v1.5.0. Difficult and Very Difficult remain unproven for
v1.6.0. Higher add counts, physical pressure, support range, and a post-spawn
hate bobble remain the major risks.

## Required post-fight evidence

`analysis_spec.json` defines the passive reducer contract. At minimum preserve:

- pull/origin geometry and all unknown-distance intervals;
- per-wave entity discovery order, last-spawn time, stable time, late roster
  mutation, first-seen-to-tag latency, tag action/result, revocation reason,
  exact off-target action, and reacquisition latency;
- active addon/profile versions, active PartyCombat policy/roles, and AutoWS2
  status by attacker;
- every directed target/stop transition, arrival-aware pursuit reassertion,
  manual override, and any unintended reacquisition;
- Bigwig's latest primary action target, evidence age at each wave, latched
  holder, Achoo plus the two chosen damage peelers, and time from spawn to
  split resolution;
- per-generation kill order, time, and Bigwig damage while adds live;
- Entrust/Indi-Wilt request/results, exact subject, Colure Active buff-612
  freshness and duration, any observable enemy Attack Down status-557 evidence,
  plus Tackle physical damage before and during Wilt;
- boss/add/support geometry, pack split/crossing, and party proximity;
- Triple Reversal readiness, bounded Violent Flourish attempt/result,
  interrupted/out-of-range/unresolved outcome, drain, target, and KO linkage;
- Utsusemi/Copy Image count changes, loss-to-Ni latency, Phantom Whorl
  ready-to-top-up latency, Reraise state/source, Sleep-family completion,
  Curaga II wake latency, and every packet-confirmed weapon skill;
- nominal cure amount, effective recovery, overheal amount/rate, filtered cure
  count, result latency, minimum HP/MP, Refresh uptime, and deaths;
- clear, wipe, timeout, abort, manual intervention, and total duration.

Telemetry is observational. It may recommend a new isolated profile version;
it may never silently alter this or any other live combat profile.

## Open risks

- Community evidence says adds appear in the middle, but there is no positive
  proof of a deterministic point that places every sequential spawn within a
  6-yalm Blue Magic radius. Exact Flash/Gaze attempts repeat independently;
  roster and result evidence are telemetry, never prerequisites.
- A tag proves that Tackle acted on an add, not permanent hate ownership. Only
  observed off-target action is authoritative negative evidence on the current
  packet surface.
- Tackle's shield, damage-taken set, and route have not yet been demonstrated
  against the full VD five-add physical pack. Indi-Wilt must be evaluated by
  observed mitigation, not merely status presence.
- Wilt's enemy-side enmity eligibility is only partly proven. Tackle's exact
  tags establish the entrusted-anchor requirement, but Achoo being on every
  spawned add's enmity list is inferred from earlier Geo-Frailty plus reported
  inherited spawn hate. A Normal run without observable physical mitigation
  does not promote.
- Add inheritance can help initial capture, but Utsusemi and other party
  actions can redirect a spawn before capture. Immediate exact tagging reduces
  this window but cannot make server ordering deterministic.
- Installed resources do not identify Turn the Tables, Spin the Tables, or
  Triple Reversal by a stable numeric monster-ability ID, so name-based
  enrichment remains necessary until retail packets supply authoritative IDs.
