# Sortie live-canary operator runbook

## Operating contract

The party has completed ground-floor travel unlocks, Sheet D, and all six
main-job soul-item checks. The current live route is `sortie-main-run` (alias
`mainrun`): earn Shard/Metal C and defeat Skomora, earn Shard B and defeat
Leshonn, then earn Shard/Metal A and defeat Ghatjot. The old two-boss,
onboarding, and recovery routes remain available as history, not as the normal
run.

Nothing here is a permission gate. ExpeditionGuide gives instructions and
evidence, loads one persistent Sortie profile after entry, and issues only
allowlisted warp requests after the correct Device or Gadget is nearby. Warp
requests retry while their step remains current; they never intercept input.
Move, retarget, attack, cast, weapon skill, use abilities, heal, recover, warp
another way, or change the plan whenever live conditions require it.

## Party baseline

All six have completed the core onboarding, Key B recovery, Sheet D, and their
main-job soul-item checks. The next phase is repeatable boss qualification and
boss-profile proof. A reward is treated as shared only when all six fresh
reports contain it; any mismatch remains visible but never blocks an operator
override.

## Pre-entry audit

Perform this once per character before scheduling the first live entry:

- Seekers of Adoulin: **The Light Within** complete.
- Rhapsodies of Vana'diel: **The Orb's Radiance** complete and Scintillating
  Rhapsody held.
- Speak to Ruspix in Leafallia for a Shiny Ra'Kaznarian plate.
- Verify inventory space and obtain Silent Oils, Prism Powders, Reraise, and
  food.

On the planned run day, bring all six to the Diaphanous Transposer at Kamihr
Drifts Bivouac #4. Load ExpeditionGuide on all six, then use `//exg status` on
Dolo. Do not request entry unless the HUD shows `SENSORS 6/6`, `PARTY 6/6`, and
`DOLO LEADER 1/1`, while the `//exg status` entry-plate diagnostic shows all six
`Shiny`, with no `Dull`, `missing`, `INVALID`, or `unknown` member. The same
checks remain live on the `enter` step; a regression displays `ENTRY CHECK`
with named plate diagnostics when applicable. This is advice, not an input
block—the operator still owns the entry decision.

After the first completed foray, first run `//exg status`. If it already reports
`Ruspix's plate 6/6`, the party has nothing to claim and this postflight route
should be skipped. Otherwise, keep the party together and run:

```text
//exg start sortie-postflight-ruspix
```

Take all six to Leafallia. Tackleberry, Kickpuncher, Barneystinson, Smalls, and
Achoo each speak to Ruspix for Ruspix's plate. Dolomedes also speaks if status
does not confirm that he holds it. Only fresh all-six Ruspix's plate evidence
completes this postflight route. Dull plates are expected immediately after the
run but are diagnostic only; they do not prove Ruspix reward eligibility or
show remaining recharge time.

## Start the main run

On Dolo, outside Sortie:

```text
//exg start mainrun
//exg status
//exg explain
```

Starting outside Sortie is safe: lifecycle requests begin only after the
leader is inside an allowed zone with this live route active. Prefer `LIVE`,
`SENSORS 6/6`, `PARTY 6/6`, and `DOLO LEADER 1/1`, then enter manually. At the
starting Device the route detects proximity and requests Device C
automatically. The HUD shows the current step number and exact step id. Useful
read-only or recovery controls are:

```text
//exg pos 2200 300
//exg steps
//exg explain
//exg pause
```

The 3D arrow is disabled while route coordinates are recalibrated. `//exg arrow
on` is optional diagnostic tooling, not part of the run workflow.

`steps` and `explain <step>` never alter progress. `next` always advances by
operator decision; when sensor evidence is missing it records an override
instead of refusing. `wp` skips one corridor point without changing the step.
The guide never locks you in place.

## Historical core onboarding sequence

The `sortie-onboarding-core-live` route is designed to obtain Keys and Plates
A-D plus Sheets A-C for all six. Its canary order is:

1. Confirm all entry prerequisites and sensors.
2. Enter with all six and audit shared temporary items at the Start Device.
3. Sector A: Gate A1 for Key A; harmless spell at Device A for Plate A;
   Kickpuncher removes all actual equipment, touches Bitzer A for Sheet A, and
   restores normal equipment. Visual lockstyle does not prove naked status.
4. Sector B: remain on foot from Start. After Locked Gate A, do not open the
   nearby B3 gate. Follow the HUD's calibrated gate arrow and take the long
   outer route to far-east B1, continue to B2, backtrack to B3, then return to
   B4 by Device B. Confirm each target name before interacting. `/hurray` at
   Device B for Plate B; Kickpuncher, who has remained on foot from Start,
   touches Bitzer B for Sheet B; then open B5 and B6. Key B requires the exact
   uninterrupted order B1-B6. An out-of-order gate cannot be repaired during
   that run because opened gates remain open.
5. Sector C: open C1 or C2 before the first C enemy dies for Key C; continue to
   Device C; use the safe strategy of isolating one Cachaemic and defeating it
   beside the Device for Plate C; Kickpuncher selects Materialize and then
   touches Bitzer C for Sheet C.
6. Sector D: follow this route's D1-then-D2 plan and open both within 120 seconds
   for Key D (the objective itself allows either order); at Device D,
   **drop** the Obsidian Wing and open the Plate D chest.
7. Exit without attempting Sheet D or entering H. Sheet D is a separate route
   because it requires defeating all regular Demisang.

Critical operating rules:

- Dolo alone opens every reward chest.
- Freeze chest interactions whenever sensors are not `6/6`, a client is
  disconnected, or a character is still zoning.
- Never use the Obsidian Wing during the D objective. Using it ejects that
  character; the objective requires dropping it.
- ExpeditionGuide does not remove gear for Bitzer A.
- The floating arrow follows captured corridor turns. It still cannot steer,
  understand collision, or overrule the live corridor; use `//exg wp` freely.
- At the B sequence, never interact with a numbered gate unless its name
  matches the current HUD point. The first nearby gate is B3, not B1.
- Avoid all C damage until the Key C condition is complete.
- Kickpuncher must not use a Device warp before Sheet B is confirmed. Keeping
  all six on foot is the simple formation rule.
- Warnings and reward evidence are advisory. They never suppress an interaction
  or manual action; use verified live reality when you must improvise.

## Current `mainrun` workflow

No routine `//exg profile`, `//pt`, `//pc`, Ctrl-P, or manual Superwarp command
is expected on this route. ExpeditionGuide loads and arms `sortie-main-v1`
once after entry; target names choose internal recipes without ever replacing,
reapplying, disarming, or stopping the profile.

1. Enter manually. Near the starting Device, ExpeditionGuide requests Device C
   and retries every 12 seconds until relocation is observed.
2. Go through C3, C2, and C1 to the Skeleton/Ghoul camp near Gadget C. Tackle is
   the preferred puller, but any configured member's hostile action binds that
   exact target and synchronizes all six. On Skeletons and Ghouls, Kick
   Evisceration > Dolo Savage Blade makes Fragmentation; Smalls and Achoo burst
   Thunder, then all six finish. Open Shard C after three credits and Metal C
   after three more. Corses, Ghosts, and the Bhoot use ordinary fast combat and
   do not select the C objective recipe.
3. Take the nearby branch to Gadget C. The port waits for Gadget proximity and
   retries until arena relocation. Tackle engages Skomora for preferred initial
   threat; all six close and execute the internal non-REMA boss recipe. Open
   the reward chest, then use the arena Gadget to return.
4. Backtrack through C1-C3 to Device C and warp to Device B. Go north of Bitzer
   B into the large Fire room. Kill five Biune Fire Elementals; every target
   must receive at least one weapon skill before death. All six attack and
   spend TP continuously—there is no pause or disengage phase. Open Shard B.
5. Leave east through Gate B3, then go north and east to Gadget B. Port into
   Leshonn and select him on Dolo to stage safe support without engaging. Put
   Tackle alone directly in front and all five others behind or on a rear
   flank, then engage with Tackle. Automation schedules no Dia, Elegy, Flash,
   Sentinel, or Wind/Lightning skillchain; GEO bubbles and Box Step remain,
   and Kick holds WS. Open the reward chest and return through the arena Gadget.
6. Backtrack through B3 and the Fire room to Device B, then warp to Device A.
   Follow the HUD route cues to the northwest Abject Acuex camp beside the
   Ghatjot route. The party burns TP, then automatically pauses only the needed
   lanes for Tackle Flat Blade > Smalls Red Lotus Blade Liquefaction and Smalls
   Fire IV + Fire III. A failed chain resumes the stopped members and retries.
   Open Shard A after three magic kills and Metal A after three more.
7. Go west around the northwest bend to Gadget A. Port into Ghatjot, let Tackle
   establish preferred initial threat, remove Poison promptly, and use the
   no-Water internal recipe. Open the reward chest.

Entry, physical movement, exact target selection, doors, and chests remain
operator-owned. Any member can pull or improvise; there is no leader-only combat
gate. `//exg profile` is a recovery-only way to repeat the current canonical
profile request, and it prints the exact `//pt use ...` command it sent.

## Manual and automatic advancement

An item step advances automatically only when every fresh, same-zone client
reports the required temporary item. Entry and sensor-audit steps likewise wait
for all-six evidence. Core onboarding closes automatically only when all six
report the eleven Keys/Plates A-D and Sheets A-C; Sheet D onboarding closes only
when all six report all twelve ground-floor traversal items.

The persistent main profile uses the reviewed COR/PLD/DNC/BRD/RDM/GEO
composition. The live Sheet D recovery route still uses the isolated v1.1
Demisang profile. It guides room centers but cannot count enemies; Demisang
Deleterious is excluded.

Instructions whose hidden condition cannot be proven from safe client state are
manual. Complete the game action, verify its result, and use `//exg next`.
Reaching the waypoint records an observation but does not prove the hidden
condition. `//exg wp`, `next`, and `skip` remain available whenever the route
or sensor view differs from live reality.

## Chest protocol

Before Dolo opens any spawned chest:

1. Stop movement and let every client finish zoning/loading.
2. Confirm the HUD names the expected chest and preferably reads
   `CHEST READY: 6/6 stable 2/2`.
3. Confirm `SENSORS 6/6`, `PARTY 6/6`, and `DOLO LEADER 1/1` on the HUD.
4. Confirm the expected characters are in the same Sortie instance layer.
5. Confirm no alliance is attached.
6. Interact on Dolo only.
7. Wait for the route's all-six item evidence before moving on.

If the count falls below `6/6`, use live judgment. `//exg resync` can request
fresh reports, but it does not prevent a time-critical interaction. If one
character does not receive the item, preserve the log and revise the run plan.

`CHEST READY` is an advisory observation, not an interaction guard. The addon
does not target or open chests, and it does not intercept or block packets or
player input. `CHEST RISK` and `CHEST CHECK` explain uncertain evidence; they do
not revoke operator control. The proof exists only in memory and is discarded
on every relevant lifecycle or context change.

## Recovery and emergency actions

- Combat emergency: press the existing `Alt-P`. ExpeditionGuide does not own
  that binding.
- Guide plus combat emergency: `//exg stop` sends `PartyTactics off` and pauses
  route progression.
- Suspect sensor cache: `//exg resync`, then wait for `6/6`.
- Wrong step: `//exg back`, inspect with `//exg explain`, then continue.
- Uncertain restored run: keep it paused, correct the timer with
  `//exg time MM:SS`, and resume only after visually confirming the location and
  step.
- Untrustworthy route history: `//exg reset confirm`.

Leaving or changing the Sortie instance clears the run binding and requests
reconciliation while leaving the route display and manual controls useful.
State older than two hours reloads paused so a new foray does not silently
inherit an old route position.

If a temporary-item objective was missed and deliberately skipped, the final
all-item step cannot auto-complete. Do not wait there after exiting. Use
`//exg stop`, then start the corrected route by its exact ID on the next entry;
do not resume the old `sortie-onboarding-core` guide-only route.

Key B was recovered successfully on the 2026-09-10 follow-up, and Sheet D was
subsequently completed. The historical direct Sheet D route remains:

```text
//exg start dclear
```

It verifies entry and guides the direct Device D / regular-Demisang clear.
Follow the detailed room steps and separate floating arrow. Kill every regular
Demisang; there is no global kill order. The H-9 six-job party may be killed
WAR > MNK > WHM > BLM > RDM > THF for two bonus blue caskets, but that order
never outranks survival. Demisang Deleterious is not required.

This objective is large and may consume the run. Press Alt-P, retarget,
reposition, skip a wrong arrow point, improvise, salvage, or exit whenever live
conditions call for it. The already-earned Key B remains valid.

## Live-run observations

The 2026-09-09 six-client run validated A, Plate/Sheet B, C, and D objectives,
the isolated C profile workflow, and all gate/device/Bitzer landmark captures.
It also exposed an incomplete B instruction: the party encountered and opened
B3 before taking the outer route to B1, so Key B did not appear after B6. The
live route now explicitly warns against nearby B3, gives the full gate order,
and uses the captured gate coordinates for HUD bearings.

The 2026-09-10 follow-up recovered Key B for all six and spent the remaining
time on the first Demisang attempt. Its trace captured every successful B
corridor turn and the southern D sweep. Combat telemetry showed Smalls at or
below 20% MP for roughly half the instance despite five Converts, with routine
cures duplicated by RDM, BRD, and GEO. Tackle still received most hostile
actions, but Dolo peeled substantial hate while dealing about 3.5 times
Tackle's damage. The v1.1 profile therefore moves routine healing to Tackle's
Majesty lane, leaves Kick on emergency Waltzes and Smalls on emergency/status
work, removes BRD/GEO routine curing and RDM's repeated Protect/Shell cycle,
and selects Tackle's sustained enmity/Chivalry policy.

The 2026-09-12 first boss-training run lasted 52:22 and defeated Skomora in
78.3 seconds. Tackle received the plurality of full-run hostile actions and
held the boss's direct attention; Dolo's visible trash hate was a pull-order
problem, not evidence that the Skomora damage plan failed. C objectives were
complete near minute five, but travel and handoff kept the party in C combat
until roughly minute twenty, and the return transition cost about five more
minutes. Route v2.1 therefore owns the profile transitions and supported
Device/Gadget operations.

The same trace recorded six failed Acuex qualifications: full-party kills took
only 16-67 seconds and melee delivered every killing blow before Smalls could
finish. Smalls spent roughly 34 minutes at or below half MP while attempting
62 Haste II and 52 Refresh III casts plus the rest of the buff carousel. The A
v1.1 profile now disables that routine lane for the objective, keeps a
five-person speed burn, peels melee by HP threshold, and reserves the finish
for repeated Smalls/Achoo Fire. C, A, Skomora, and Ghatjot now all use the same
Tackle-first claim-and-release contract.

Further entries continue to calibrate rather than lock down:

- the explicitly labelled provisional far-west and Device-D room centers;
- the practical enemy-death radius for the Plate C chest;
- Ghost versus Corse pull convenience for this party;
- whether the two-second tank-first safety release needs tuning;
- whether A's 45%/32% damage-peel thresholds reliably preserve speed and Fire
  credit;
- recovery behavior after a bad pull, missed reward, or disconnect.

Preserve the Windower chat log if reality differs. Adapt manually during the
run, then revise the isolated v1 module or add a successor after the evidence is
understood.
