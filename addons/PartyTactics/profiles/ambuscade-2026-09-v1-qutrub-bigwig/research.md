# Bozzetto Bigwig / Qutrub (September 2026 V1)

Research retrieved 2026-09-03. This file records fight evidence and the
reasoning for profile version 1.1.0; it is not loaded as executable policy.

## Sources

- Local BG Wiki vault: `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/ambuscade/ambuscade-archive.md`, Qutrub section. This is the primary offline encounter reference used for implementation.
- [BG Wiki Ambuscade Archive](https://www.bg-wiki.com/ffxi/Ambuscade_Archive), live corroboration for the returning Qutrub encounter.
- [September Version Update announcement](https://forum.square-enix.com/ffxi/threads/62041-September-Version-Update?mode=threaded&p=662184&s=a56445d2375d0ea04f095f8559453fb2), official high-level warning that the low-HP dagger grants an en-death effect whose frequency rises with surviving minions, and that the minions should be defeated first.
- [FFXIAH Qutrub Ambuscade V1 discussion](https://www.ffxiah.com/forum/topic/55571/qutrub-ambuscade-v1/), community corroboration for Mewing Lullaby TP suppression, shadow jobs, Astrologer Silence, add-first and kiting strategies. Community claims are treated as tactical evidence rather than authoritative mechanics.
- Local BG Wiki vault pages `misc/mewing-lullaby.md`, `jobs/abilities/blood-pact-ward.md`, and `mechanics/avatar-perpetuation-cost.md`, used to verify that Mew is level-25 and subjob-accessible, its TP reset is reported not to miss even when sleep does, Blood Pact: Ward has a base 60-second recast, and Cait Sith costs 6 MP/tick at a level-49 SMN subjob.
- Installed Windower resource tables under `C:/Program Files (x86)/Windower/res`, used only to pin reviewed spell, weapon-skill, job-ability, and known monster-ability IDs.
- The locally cached LandSandBoat server reference, especially
  `server/src/map/ai/states/petskill_state.cpp`, corroborates that an avatar
  re-engages its target after a Blood Pact. Windower resources identify the
  normal Retreat pet command as job-ability ID 89 with recast group 171.

## Encounter model

Bigwig is THF/NIN and has Draw-In. At 80% its first add wave appears. The
published counts are: VD two Astrologers plus three Tormentors; D two plus two;
N one plus two; E one plus one; VE one Tormentor. Defeated adds return at 30%,
except the archive notes only one wave on VE. The adapter accepts the observed
`Tormentor` spelling and a defensive `Tormenter` variant, but no other name.

At 60-30%, Bigwig's secondary dagger grants en-death while adds survive. The
rate is reported to worsen when players continue damaging Bigwig. At 50% it
uses Perfect Dodge. Below 30% it frequently casts Utsusemi: San and gains its
most dangerous physical/drain moves. Astrologers cast tier-IV magic, Sleep II,
Poisonga, and Ice Spikes and are susceptible to Silence. Adds are immune to
sleep. Triple Reversal is available to adds below 30% and is associated with
three or more enemies attacking one target.

The archive identifies two finish hazards. Genku Bakken / Phantom Whorl is a
roughly 10-yalm, very-high physical single hit that is absorbed by shadows.
Turn the Tables drains from one target's current HP; VD's Spin the Tables is a
roughly 15-yalm AoE. Bigwig recovers more HP than it drains, while a target
below 10% HP dies instantly. Intentional low-but-safe HP and live shadows are
therefore release conditions, not optional optimizations.

The cached archive calls killing both add waves the slowest but most reliable
VD strategy because it removes the en-death and Triple Reversal sources. That
reliability is the profile's controlling choice. Mewing Lullaby is used only
as TP suppression while the kill order is being executed; it is never modeled
as crowd-control sleep.

## Fully automatic strategy

The operator applies the profile in exact Ambuscade zone 183 or 287, waits for
the six-client preflight, finishes stationary positioning, and sends one
`//pt arm`. No enemy may be authorized or pulled before that explicit arm edge.
Tackle then performs a packet-confirmed
main-job PLD hate opener ending in exact-ID Flash. Crusade, Divine Emblem, and
Sentinel are opportunistic; no long recast can block the pull. PartyCombat is
not forced until Flash succeeds and party claim is visible. Rampart and
Palisade are instead rearmed as bounded, opportunistic actions at the start of
each observed add wave, when their pack mitigation is most useful.

Dolo, Tackle, and Kick are always one transaction group. The current subject
is the lowest-ID live Astrologer, otherwise the lowest-ID live
Tormentor/Tormenter, otherwise Bigwig. A subject change cancels every stale
reservation before the next exact ID is forced. Each subject receives
Evisceration -> packet-confirmed Fragmentation from Savage Blade -> Last Stand;
Last Stand is never sent after a failed/missing Fragmentation result.

At the 80% and 30% boundaries, boss weapon skills are suppressed before the
threshold, PartyCombat is stopped while the spawn set settles, and boss damage
cannot resume until the observed wave is empty. Perfect Dodge cancels the
chain and stops physical combat for a conservative 32-second hold. Dolo,
Tackle, and Kick use local Copy Image proof: Ni is requested first, Ichi is a
bounded fallback, and every attacker adapter refuses a weapon skill when no
shadow exists. This requires Tackle PLD/NIN; the second Cait lane moves to
a separate support instead of Achoo.

Version 1.0.0 incorrectly assigned the second Cait lane to Achoo GEO/SMN. A
luopan and avatar occupy the same character pet slot and cannot coexist, so
that arrangement could provide either Geo-Frailty or Mewing Lullaby but never
both. Version 1.1.0 leaves Achoo GEO/WHM's luopan uninterrupted and assigns
Cait Sith to Barney BRD/SMN and Smalls RDM/SMN. They alternate Mewing Lullaby
every 31 seconds while three or more live encounter enemies exist. That gives
each unmodified /SMN Blood Pact: Ward lane 62 seconds before it is requested
again. The sleep component is not expected to land on sleep-immune adds; the
documented unresistable TP reset is the only intended effect. Every result
must still be present in the exact boss-and-add packet before the baton moves.
That exact full-pack result schedules a short, low-priority Retreat transaction
on only the successful lane. Retreat is packet-confirmed when possible but is
never a damage, target, or healing gate; a rejection or missing result expires
locally. Cait remains summoned for the lane's next turn. Release is never used
during the encounter because resummoning adds avoidable cast, recast, MP, and
queue failure surfaces.

Smalls queues exact-ID Silence independently for each Astrologer and renews it
on a conservative duration or failed-cycle backoff. His exact Cure II/Cure IV,
Diaga, Dispel, and Silence reservations all outrank his supplemental Mew lane;
ordinary emergency Cure and status removal can also bypass queued adapter
work. Achoo /WHM supplies a separate cure/status-removal HealBot lane while
retaining the persistent Indi-Fury and Geo-Frailty responsibilities. An
observed successful Ice Spikes cast arms a higher-priority, exact-subject
Dispel response; the brief weaponskill hold is bounded so an unavailable
Dispel cannot deadlock the kill.
Bigwig's Utsusemi: San arms recurring exact-ID Diaga cycles once adds are gone
and blocks coordinated weapon skills until a strip is packet-confirmed. Below
30%, Smalls makes a small finite number of ordinary Silence attempts; the
profile does not spend Stymie, Saboteur, Chainspell, or any other RDM SP
ability.

Grape Daifuku is fixed preparation for all three attackers and is used only
when Food is absent. The preflight proves one item exists; after the explicit
arm, the adapter consumes it through a bounded normal item action and runtime
waits for confirmed Food state before allowing offense. Barney uses the native
three-song physical baseline and opportunistically adds Knight's Minne V
through Clarion Call when that ability is ready. Neither Clarion nor the extra
song is a readiness or pull dependency; both are bounded and may be skipped
without stalling a repeat farm.
GearSwap alone chooses weapons, ammo, precast/midcast sets, and instruments.

Once wave two is dead and Bigwig reaches 30%, a one-way low-HP latch activates
on all clients. Targeted legacy heals against Dolo, Tackle, or Kick are
filtered; AoE HP restoration and Majesty are filtered because they cannot
exclude them. Ordinary swings bring all three into a 13-25% band. Final-phase
weapon skills require that band and local shadows. Below 13%, combat stops
before Smalls receives an exact, bounded Cure II request; support below 60%
receives exact Cure IV. Recovery reservations require the live guard and
cannot outlive heartbeat expiry or teardown. The latch remains if Bigwig heals
above 30%.

## Positioning and recovery

Stationary mode deliberately provides no movement. Put Tackle, Kick, and Dolo
in melee range before arming because no ranged-attack TP loop is automated.
During add waves, keep Barney, Smalls, and both pets within roughly 10 yalms of
the entire pack for Mew coverage.
The runtime cannot kite around pillars and makes no claim that automation can
replace that geometry. If VD proves too dangerous without kiting, step down
difficulty rather than silently changing this profile's contract.

After wave two, move Barney, Smalls, and Achoo beyond 16 yalms from Bigwig
while keeping Smalls within 20 yalms of every attacker. Live coordinates prove
both conditions; missing or unsafe geometry stops target control and weapon
skills. Smalls RDM/SMN remains the primary RDM healer; main-job RDM supplies
the exact Cure II/Cure IV finish actions. Achoo GEO/WHM owns the independent
cure/status-removal lane, with Tackle's single-target PLD cures and Kick's
Waltzes retained as filtered backup surfaces. Low party health,
missing shadows, claim loss, foreign claim, entity reuse, death, zone
departure, or profile deactivation fails closed.
After any encounter release the current arm edge is consumed; another pull
requires an observed disarm followed by a fresh `//pt arm`.

## Known uncertainties to measure

- Installed resources lack IDs for Turn the Tables, Spin the Tables, and Triple Reversal. Name-based post-fight enrichment is required until packet IDs are captured.
- Mewing Lullaby may report the player-side ability ID 522, pet-side monster ability ID 2449, or both; the adapter accepts only this fixed pair for result confirmation.
- Bigwig Silence requires immunobreak according to the archive. The finite ordinary attempts may not land, which is why Diaga remains the deterministic shadow-strip response.
- Accuracy and survivability on VD must decide whether Entrust Wilt remains preferable to Precision. Version 1.1.0 uses Hunter's Roll plus Wilt and records miss and damage evidence for a later isolated version.
- Live results must confirm that both Barney and Smalls have Cait Sith unlocked and that their level-49 /SMN Mew packets include every associated add. The deterministic preflight rejects either missing spell/ability before a pull.
- Retail capture must confirm whether Retreat's result targets the master or
  avatar. The adapter accepts only the current master/current Cait pair and
  abandons an unconfirmed follow-up after a bounded window without blocking
  encounter work.
- Entity appearance timing after 80%/30% is not published. The initial settle/hysteresis constants are conservative and must be tuned from passive PartyOps/BattleLab traces, never by importing telemetry into combat control.
- The initial 13-25% band must be calibrated from VD drain, minimum-HP, Cure II, Tables-healing, and band-time evidence while remaining above the documented instant-death boundary.
- Live coordinates must prove both support evacuation and Cure II reach. Missing coordinates fail closed rather than being estimated.

`analysis_spec.json` is passive metadata for that post-fight reducer. The
operator must declare VE/E/N/D/VD for every attempt; difficulty is never
inferred from observed add count.
