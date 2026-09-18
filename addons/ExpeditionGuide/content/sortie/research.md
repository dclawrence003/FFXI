# Sortie content provenance and confidence

The canonical objective definitions come from the local BGWiki mirror:

`C:\Users\DC03\Documents\Tesseract\FFXI\reference\bg-wiki\categories\category-sortie.md`

Temporary-item IDs are cross-checked against the installed Windower resources
in `res\items.lua`. Device, Gadget, Bitzer, and gate indices plus the warp
landing anchors are cross-checked against the locally installed Superwarp
Sortie map and LandSandBoat's cached NPC list. Superwarp code is not copied.
Entry key-item IDs are cross-checked against installed `res\key_items.lua`:
Shiny plate 3300, Dull plate 3301, and Ruspix's plate 3328. Leafallia is zone
281 in installed `res\zones.lua`.

The Phase-1 walking order is informed by the public beginner walkthrough:

https://www.ffxivpro.com/forum/topic/57533/ffxi-sortie-a-beginners-guide-to-locating-gems

Reference images used while authoring the route:

- A: https://i.imgur.com/8OPu9l0.jpeg
- B1-B2: https://i.imgur.com/iRQ0PQV.jpeg
- B3-B6: https://i.imgur.com/GGYo5Rf.jpeg
- C: https://i.imgur.com/8BihIQ5.jpeg
- C to D1: https://i.imgur.com/Ts6IUpB.jpeg
- D1 to D2: https://i.imgur.com/bwIjV3Y.jpeg

The 2026-09-09 six-client canary produced exact-index live-entity captures for
Gates A1, B1-B6, C1-C3, and D1-D2. Those coordinates are promoted into
`landmarks.lua` so the next route can point to B1 before it is in local entity
range. The same run proved that the original abbreviated B instruction was
unsafe: entering B can expose nearby B3 before the long outer route reaches
B1. B3 was opened first, and no Key B chest appeared after B6. The operational
route therefore requires target-name confirmation and explicitly says not to
open B3 first; the frozen guide-only route remains historical.

The same canary confirmed every other core objective for all six clients.
`sortie-key-b-recovery-live` is the additive follow-up route: it reuses the
captured gate coordinates and limits the next charged entry to the remaining
Key B sequence, while leaving all other activity to the operator.

The combined successor `sortie-key-b-sheet-d-canary-live` keeps that exact Key
B sequence first, then enters D from the Device C/H-9 boundary for a systematic
regular-Demisang sweep. BGWiki and the FFXIAH early guide agree that Sheet D
requires a full regular-Demisang clear followed by Bitzer D and that Demisang
Deleterious is not required. The opening six-job party can also satisfy the D1
and D2 blue-casket objectives when killed WAR, MNK, WHM, BLM, RDM, THF. The
route treats this order as an opportunity rather than a gate because Demisang
cannot be slept and linked-pack survival takes priority.

The 2026-09-10 follow-up successfully awarded Key B to all six. The next route
is therefore the additive `sortie-sheet-d-demisang-live` (`dclear`), which
contains no B objective: it enters, teleports directly to Device D, sweeps the
regular-Demisang rooms, and returns to Bitzer D. Its initial corridor points
come from Dolomedes' captured movement trace; unvisited far-west and Device-D
room centers are explicitly marked provisional so the operator can use
`//exg wp` and refine them after the next run.

Read-only PartyOps analysis bounded the run from 00:43:10Z to 01:43:17Z. Smalls
spent about 1,807 seconds at or below 20% MP and used five Converts, but returned
below 20% only 117-161 seconds after each one. Overlapping routine healing was
substantial: Tackleberry produced 153,462 effective Cure III/IV healing with
Majesty while Smalls, Barneystinson, and Achoo also cast repeated Cure/Curaga.
Incoming hostile events still favored Tackleberry (598 single-target events to
Dolomedes' 248), but Dolomedes dealt 4.34M damage versus Tackleberry's 1.25M and
peeled a meaningful minority of attacks. These observations justify only an
isolated v1.1 profile change: Tackle owns routine Majesty healing and sustained
enmity; Kick retains emergency Waltzes; Smalls retains emergency/status work;
BRD/GEO routine curing and RDM's repeated party defense cycle are removed.

- https://www.bg-wiki.com/ffxi/Sortie_Strategies
- https://www.ffxiah.com/node/469
- D path reference: https://i.imgur.com/P50I8Vm.png

Confidence:

- High: canonical objectives, item IDs, menu IDs, entity indices, and zone
  variants.
- Medium: community walking order and warp landing anchors.
- Live calibration required: corridor turns, gate coordinates, exact Device C
  kill radius, and mixed-progression reward edge cases.

Safety corrections retained in content:

- Device D awards **Plate D**, not Sheet D.
- The Obsidian Wing must be **dropped**, never used.
- Sheet D remains a separate objective because it requires defeating every
  regular Demisang; the combined recovery canary attempts it only after Key B.
- The D-gate objective permits either order within two minutes; D1 then D2 is
  this guide's selected walking order.
- Kickpuncher is the fixed first-timer actor for Bitzers A, B, and C and for
  Device C Materialize. The same Materialize actor must touch Bitzer C. Dolo
  remains the sole reward-chest opener.
- Sheet B's no-warp condition is tracked against Kickpuncher, the character who
  touches Bitzer B. Keeping the whole party on foot remains the simple route
  rule.
- Dolo's partial progress is never treated as party progress. Every permanent
  reward waits until all six sensor clients report it.
- Dull plate possession is diagnostic only. It is not progression evidence,
  does not report remaining recharge time, and does not prove Ruspix eligibility.

## First two boss training route - 2026-09-12

Fresh FindAll key-item snapshots confirm the main-job soul item on all six:
Dolomedes COR (3321), Tackleberry PLD (3311), Kickpuncher DNC (3323),
Barneystinson BRD (3314), Smalls RDM (3309), and Achoo GEO (3325). Soul-object
touches are therefore not part of the boss route.

Umbra's supplied workbook is the cornerstone party-specific source:

- `C:\Users\DC03\Downloads\Sortie Melee Checklist.xlsx`
- `Sortie - Melee Comp!A8:H8`: Skomora assignments
- `Sortie - Melee Comp!A10:H10`: Ghatjot assignments
- `Jobs and Reqs!A1:D7`: advanced equipment assumptions audited but not adopted

The operational route retains the C-before-A order and the workbook's core
roles: Samurai-oriented COR support, physical Bard songs, DNC Box Step and
Waltz backup, Fury/Frailty, straight PLD tanking, and RDM Dia/status support.
It does not treat REMA/Prime equipment, five songs, Honor March, Aria, Idris,
or speedrun timestamps as requirements. Fresh FindAll snapshots and installed
GearSwap definitions instead establish an executable Naegling/Tauret/
Maxentius/DualSavage baseline.

Current local BG Wiki boss pages and the public beginner guide agree on the
training safety items. Three qualifying sector-C bursts award Shard C and
three more award Metal C; Metal C converts Skomora's Haunted to removable
Curse. Skomora's Setting the Stage is a roughly 30,000-damage party stack check
around three minutes after engagement. Three sector-A single-target magic
killing blows award Shard A and three more award Metal A; Metal A converts
Ghatjot's Taint to removable Poison. Ghatjot absorbs Water, and Water-aligned
Distortion/Darkness can amplify its next TP move.

- Local mirror: `sortie/skomora.md`, `sortie/ghatjot.md`, and
  `categories/category-sortie.md`
- https://www.bg-wiki.com/ffxi/Ghatjot
- https://www.ffxiah.com/forum/topic/57533/ffxi-sortie-a-beginners-guide-to-locating-gems/3/
- https://www.ffxiah.com/forum/topic/56929/sortie-party-route/

## Later boss bookmark - Degei

Umbra's field note: build a dedicated React file for Degei; he considers the
boss straightforward once those reactions are handled. Research the exact
triggers and responses before authoring Degei's PartyTactics profile, then test
the React file independently. This is future-boss work only and does not change
the current Skomora/Ghatjot training route. Any eventual automation must remain
operator-overridable and must not gate manual play.

The C and A corridor centers are derived from the beginner guide's public map
and are explicitly provisional. Their purpose is to provide the requested
point-to-point floating arrow on the first proof run. The operator may advance
one disagreeing point with `//exg wp` or replace it from Dolo's exact live
position with `//exg mark`; neither action gates combat or route improvisation.

## Sector C burst transaction - 2026-09-12

The two-boss route v1.1 replaces its manual-only Shard/Metal C instructions
with the allowlisted `sortie-objective-c-magic-burst-v1` profile. It remains an
explicit operator load and per-target arm: the guide does not target, pull,
move, or start combat. The isolated combat runtime recognizes only Cachaemic
Skeleton, Ghoul, Corse, and Ghost and rejects the Cachaemic Bhoot NM.

Installed Windower resources establish Evisceration ID 25, Savage Blade ID 42,
Thunder ID 164, Fragmentation action message 291, and Magic Burst damage
messages 252/265. The runtime waits for those observed results in order and
releases the two directed-only finishers after actual burst evidence. Bounded
timeouts return to acquisition; manual correct steps count and no input is
filtered. ExpeditionGuide continues to trust only the Shard/Metal temporary
items reported by all six sensors for route completion.
