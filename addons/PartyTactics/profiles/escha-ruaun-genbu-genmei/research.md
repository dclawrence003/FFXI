# Escha - Ru'Aun Genbu / Genmei Shield research

Reviewed 2026-09-13 for profile `escha-ruaun-genbu-genmei` v2.7.0. This
profile is isolated from every other fight. Its v2.7.0 GearSwap adapter adds
only immediate Presto plus the bounded next-legal Lightning reservations and
intended coordinated Tackleberry Savage Blade, with unconditional manual-action
pass-through. The older v2.1.0-v2.6.0 adapters remain unchanged beside it.

## Encounter evidence

- [BG Wiki: Genbu](https://www.bg-wiki.com/ffxi/Genbu) says the Escha version
  repeatedly uses Invincible, gains a gravity aura, and spams Adamantoise
  moves. Thunder damage removes that aura. It casts Water VI, Waterga V, and
  Flood II, absorbs Water, and favors high-magic-accuracy Thunder damage and
  Thunder magic bursts.
- [BG Wiki: Invincible](https://www.bg-wiki.com/ffxi/Invincible) documents the
  standard physical-immunity effect. Earlier Genbu evidence suggested a
  successful Thunder stagger might end immunity early, so the runtime safely
  observes the first positive party physical result and may resume then. The
  immutable winning capture did not prove early release: Thunder landed about
  2.1-4.4 seconds after Invincible, but positive physical damage returned about
  29.9-31.8 seconds after it. The 30-second hold therefore remains the normal
  path and the positive-result observer is only a safe opportunistic release.
- [BG Wiki: Quick Draw](https://www.bg-wiki.com/ffxi/Quick_Draw) identifies
  Thunder Shot as ranged Lightning magic damage. Dolo tries it first;
  Achoo and Smalls receive independent bounded low-MP Thunder reservations.
- [BG Wiki: Adamantoise](https://www.bg-wiki.com/ffxi/Category:Adamantoise)
  documents Harden Shell and Tortoise Song's removal of Bard songs and
  Corsair rolls. The live run resisted all three RDM Dispels and all four BRD
  Finales, so this isolated revision does not spend more actions chasing
  Harden Shell or Shell V.
  Tortoise Song asks the already-installed BRD and COR helpers to rebuild
  their normal song and roll sets; it does not remove Protect or Shell.
- [BG Wiki: Presto](https://www.bg-wiki.com/ffxi/Presto) documents a 30-second
  self effect that raises the next Step's Daze by up to five levels, adds 50
  Step Accuracy, and is not consumed when the enhanced Step misses.
  [BG Wiki: Box Step](https://www.bg-wiki.com/ffxi/Box_Step) documents 100 TP,
  a five-second shared Step recast, Sluggish Daze through level 10, and Defense
  Down of 5% at level 1 plus 2% per later level. Kick can therefore reach the
  full 23% Step reduction in two landed Presto-enhanced Steps instead of ten.
  [BG Wiki: Dia spells](https://www.bg-wiki.com/ffxi/Category:Dia_Spell)
  lists Dia III at 20.31% Defense Down, so the two additive effects total up to
  43.31%; magic bursts remain unaffected by Defense either way.
- [BG Wiki: Evisceration](https://www.bg-wiki.com/ffxi/Evisceration),
  [Savage Blade](https://www.bg-wiki.com/ffxi/Savage_Blade),
  [Last Stand](https://www.bg-wiki.com/ffxi/Last_Stand),
  [Fragmentation](https://www.bg-wiki.com/ffxi/Category:Fragmentation), and
  [Light](https://www.bg-wiki.com/ffxi/Category:Light) support the desired
  Evisceration -> Savage Blade -> Last Stand Light pattern. Savage Blade ->
  Last Stand also makes Light when Kick is not ready. The runtime observes
  each completed weapon skill, spaces the next request inside the skillchain
  window, and abandons a missed step after a short local timeout. A detected
  Light triggers best-effort Thunder IV bursts.
- [BG Wiki: Genmei Shield](https://www.bg-wiki.com/ffxi/Genmei_Shield) identifies
  this Genbu as the shield source.
- [BG Wiki: Thief](https://www.bg-wiki.com/ffxi/Thief) and
  [Treasure Hunter](https://www.bg-wiki.com/ffxi/Treasure_Hunter) document
  Treasure Hunter II at THF level 45 and application by an aggressive action.
  COR/THF therefore supplies TH2 automatically with the opening shot without
  placing a TH item in Death Penalty's ammunition slot.

## Successful baseline capture

The immutable six-client checkpoint
`.codex-tmp/genbu-win-20260912-2255-2325.partyopslog` has SHA-256
`c0494f8f93d68db2cf689f3bb413e030768ef3a7f8767cae70c5777ee4caa73a`.
Profile-observed combat lasted 693.586 seconds (11:33.586), dealt 411,313
damage (about 593.6 DPS), defeated Genbu, and had zero deaths. Damage shares
were Kick 109,471; Dolo 102,137; Tackle 79,922; Smalls 77,800; and Achoo
41,983.

The proven Light loop produced 13 Light skillchains for 19,950 damage and six
Fragmentations for 6,050. Smalls completed 13 of 13 Thunder IV magic bursts
for 75,682, and Achoo completed 12 high-tier bursts for 40,661. Skillchain plus
high-tier burst damage was 142,343, or 34.6% of all damage. Tackle completed 14
Savage Blades for 60,292 damage including skillchain damage; Dolo completed 13
Last Stands for 59,497; and Kick completed 11 Eviscerations for 58,308. One
apparently unmatched Savage Blade was an ordinary coordinated opener whose
continuation was cancelled by a newly observed Invincible. It is not evidence
for an extra post-burst weapon-skill lane. v2.6 therefore preserves the proven
chain rather than adding an unconditional or overflow Savage Blade.

Tackle supplied 56,283 healing, never fell below 83% MP, and ended at 92%.
Smalls reached 19% and ended at 33%; Achoo reached 77% and ended at 91%.
Barney's apparent low samples were maximum-MP gear fluctuations and he ended
at 100% under Ballad. Smalls completed 15 Refresh III casts: five each on
Achoo, Barney, and Tackle. v2.6 removes only Barney from that maintenance list
and keeps Tackle's proven Ballad-plus-Refresh healing reserve.

Kick spent seven Waltzes for 5,389 recovery, including follow-up Curing Waltz
V results of zero and 36. The PLD lane remained MP-safe, so Genbu alone turns
off the generic DNC tank-heal helper while retaining its profile-local Samba,
Step, and Evisceration work. Triple Shot completed only at 03:01:07.390 and
03:07:11.211; completion-driven five-minute cadence replaces the old blind
schedule. Barwater expired around 03:09:06, about three minutes before defeat,
so one bounded seven-minute renewal is added. Six successful Thunder Shots
averaged 5,294 damage, while four Invincible cycles with ready Quick Draw were
starved by Dolo's 3.1-second ranged cadence; the new eight-second `/ra` hold
creates a proc action window without gating any other lane.

The win contained 11 completed Invincibles including the opening use. Physical
damage resumed around the normal 30-second boundary. Two late uses stretched
the final roughly 5% over 77 seconds, which makes preserving the proven
Thunder/Light damage lanes more valuable than adding an opportunistic physical
weapon skill between bursts.

## Control contract

`//pt genmei` loads configuration and is inert. `//pt arm` is only an
immediate start switch; it does not request or consume permission from an ACK,
preflight result, controller proof, buff, setup action, or earlier step.
`//pt disarm` stops synchronized combat and clears pending best-effort work.

`//pt check` is optional diagnostic output. It can report lenses, Genbu's
Honor, ammunition, equipment, actions, buffs, or adapter replies, but its
result cannot disable the profile or any player control. There is no automatic
preflight or retry loop.

The runtime binds one exact Genbu ID for action routing once per encounter.
That identity call is not polled as readiness: if one adapter request is
unavailable, PartyCombat, normal attacks, ranged fire, and support helpers
continue. A missed action does not prevent the next action or another lane.

The v2.7.0 adapter maps semantic words only to fixed actions. Most remain
immediate best-effort input. Thunder Shot, Thunder, Thunder IV, and Tackle's
coordinated Savage Blade receive a short exact-target next-legal queue. While
an RDM/GEO request is pending or in flight, only that client's native automatic
job tick pauses; COR is polled without consuming its tick. Tackle's Majesty
helper yields only while Savage Blade actually dispatches, is in flight, or he
is currently busy. Low TP, range, disengagement, recast, and backoff leave
healing live. A local completed Invincible packet and the runtime's scoped
cancel both retire a delayed Savage immediately; encounter-end cleanup is
idempotent after that cancellation. The adapter uses the normal FFXI input
path, so each character's GearSwap file remains the sole owner of equipment
and Bard instruments. Both manual filter hooks always return false.

## Automatic plan

Target the spawned Genbu while still clustered, then use `//pt arm` (or
Ctrl-P). The runtime begins
a timed, non-sequential opening immediately. If armed before the pop, it stays
quiet until an exact current or party-claimed Genbu appears:

1. Ctrl-P is the immediate group-engage edge. With the group still clustered,
   Barney attempts Barwatera while Tackle independently attempts Sentinel,
   profile-local Crusade, Divine Emblem, Flash, and Provoke on a spaced
   timeline. Achoo's Geo-Malaise begins after combat has been established. No
   action result authorizes a later action.
2. At bind and once more 1.5 seconds later, PartyCombat receives bounded
   exact-target edges for Tackle, Kick, and target-only Smalls. Dolo is absent
   from PartyCombat's attacker/targeter lists and receives matching local
    one-shot engage edges only during startup. Nothing persistently faces,
    moves, retargets, or re-engages him.
3. Dolo receives one immediate best-effort Thunder Shot on bind. This covers
   an opening Invincible that completed just before the runtime could observe
   it. An Invincible observed on the same edge merges with the pending request;
   if the opening request already crossed IPC, a two-second merge window avoids
   a duplicate. Triple Shot follows on Dolo's next legal action, and its normal
   bounded retry remains available if that opening request is busy or delayed.
   No result is a combat prerequisite.
4. AutoWS2 is Off for all three physical actors. Dolo automatically makes
   exact-ID ranged attacks until 1500 TP. Triple Shot receives a bounded
   next-legal request at the pull. Only a completed use starts its 300-second
   cadence; while due but unconfirmed, a bounded request retries every 12
   seconds. A chain or queued Thunder Shot supersedes it. When Dolo and Tackle
   are ready, the
   runtime requests Evisceration from Kick if available, observes its successful
   action packet, queues Savage Blade for Tackle's next legal action, observes a
   successful result, and
   requests Last Stand. The completed-action cadence is 3.1 seconds between
   weapon skills. Without Kick TP it begins at Savage Blade. A missing, missed,
   or failed action packet expires only that chain attempt and temporarily
   bypasses Kick; if Tackle cannot
   open within ten seconds, Dolo spends ready TP on standalone Last Stand.
   Attacks, shots, healing, support, and all manual controls continue.
5. Invincible schedules bounded, independent Thunder Shot/Thunder attempts
   and holds only automatic physical weapon skills until the first observed
   positive party physical result, with 30 seconds as the fail-open fallback.
   It also pauses only Dolo's normal ranged-attack cadence for eight seconds so
   the queued Thunder Shot can use an action window; ranged fire resumes on
   time whether the proc succeeds or fails.
   Smalls's HealBot ignores only the intended, unerasable Weight aura while
   this profile is active, leaving Poison, Accuracy Down, and other valid NA
   work enabled. Early physical recovery cancels any undelivered mage fallback
   requests instead of spending actions on redundant Thunder casts.
   Tortoise Song triggers an event-unique song/roll rebuild request whose token
   remains unique across a profile reapply. Warlock's Roll is roll1, so it is
   restored before Samurai Roll when Roller2 is constrained by the shared
   ability recast. Light
   schedules one next-legal Thunder IV reservation on each magic burster. None of
   these reactions holds healing, support, normal attacks, shots, or manual
   intervention.
6. Flash and Provoke receive periodic best-effort maintenance. One bounded
   two-attempt Barwatera refresh is requested near seven minutes; it is not a
   prerequisite and its result controls nothing. The runtime
   nudges Geo-Malaise only once in the opener; native AutoGeo is the sole
   renewal owner, avoiding a timed request collision with Full Circle. Genbu
   disables Kick's generic DNC helper, removing overlapping emergency Waltzes;
    the profile still requests Haste Samba at 350 TP and Box Step at 100 TP.
    Before a due Box Step, Presto gets at most two requests two seconds apart
    inside a five-second confirmation window. A completed Presto releases Box
    Step; if no completion arrives, ordinary Box Step proceeds. A missed Box Step
    retains the observed 30-second Presto effect for the retry, while a landed
    Box Step clears it and starts the 45-second maintenance timer. Invincible
    clears the local Presto observation, and ready Evisceration/chain work always
    runs first. Busy, rejected, missing, or failed actions never gate combat.
   Existing BRD, RDM, GEO, COR, HealBot, Roller2, and GearSwap schedulers
   continue independently.
7. Disarm, profile replacement, zone change, claim loss, or victory clears
   this profile's work. There are no repeated audible alarms.

## Formation and jobs

Begin clustered around Barney so the opening Barwatera covers all six. After
Ctrl-P starts combat, face Genbu away from the group and move Kick to the rear
within melee range. Keep Dolo, Barney, Smalls, and Achoo together roughly
11-14 yalms from Genbu. The recorded run showed full song/roll coverage at
that geometry, while the support line stays beyond target-centered Waterga.
PartyTactics performs no movement.

- Dolomedes: **COR/THF**. Support-job THF supplies native Treasure Hunter II;
  the first aggressive ranged action applies it. The existing `DeathPenalty`
  GearSwap mode uses Rostam A, Nusku Shield, Death Penalty, and reviewed ammo,
  avoiding any TH-ammo swap or dual-wield requirement.
- Tackleberry: **PLD/WAR**, providing Provoke alongside Flash.
- Kickpuncher: **DNC/WAR**, using profile-local Haste Samba, Presto/Box Step, and
  automatic Evisceration. Generic emergency Waltzes are disabled for Genbu;
  Tackle owns routine Majesty healing and Smalls remains the backup.
- Barneystinson: **BRD/WHM**, providing Barwatera and song recovery with
  routine HealBot cures disabled.
- Smalls: **RDM/WHM**, providing one Protect/Shell pass, core buffs, Dia,
  real status removal, 50%-threshold backup healing, Thunder, and Thunder IV.
  The frozen `limbus-protect` helper also retains up to three bounded
  best-effort Silence attempts per detected coverage cycle. It can rearm after
  confirmed wear-off or newly observed casting through prior coverage, but it
  is never an encounter gate.
- Achoo: **GEO/BLM**, preserving MP and actions for Malaise, Acumen, Entrust
  Languor, Thunder procs, and Thunder IV bursts instead of duplicate cures.

The earlier recorded 15-minute timeout dealt 386,373 damage with no deaths and left
Genbu at 5%. Tackle supplied 63,034 healing while never falling below 73% MP.
In contrast, Smalls cast 65 Cure III at the old 85% threshold, Achoo completed
106 cures/curagas, and Barney completed 39; Achoo and Barney finished near 1%
and 2% MP. Sixty-two of 64 Erases had no effect because Weight is an aura, and
Malaise disappeared for the final 6:44. Ten Lights generated ten Thunder IV
requests per mage, but only one cast from each reached the server. The v2.4
ownership and queue changes directly address those measured losses.

The later immutable successful capture described above cleared in 11:33.586
with the same basic Light-plus-dual-burst design. v2.6 was a narrow
completion/ownership refinement of that proven strategy. v2.7 keeps that plan
and adds only faster Sluggish Daze buildup plus opening-Invincible insurance.

The support baseline is Victory March, Knight's Minne V, Mage's Ballad III,
Warlock's Roll, Samurai Roll, Indi-Acumen, Geo-Malaise, and Entrust
Indi-Languor. It does not require Clarion Call.

## Next-run evidence to capture

1. Confirm Cure-delayed intended Savage Blade requests complete at their next
   legal moment without suppressing Tackle's healing while TP/range/engagement
   is invalid, and that Invincible cancels them immediately.
2. Confirm the eight-second ranged hold improves Thunder Shot completion and
   measure proc-to-positive-physical latency without delaying other lanes.
3. Confirm Triple Shot's next observed completion is about five minutes after
   the prior completion and that an unavailable request retries promptly.
4. Confirm the seven-minute Barwatera request completes without displacing
   song recovery, and compare Smalls/Barney MP after removing Barney Refresh.
5. Record missed or resisted actions and adjust only their local timing or
   bounded attempt count; do not add a global readiness barrier.
6. Measure Presto completion, Box Step landing, inferred Sluggish Daze level,
   fail-open use, and whether opening Thunder Shot merges cleanly with the first
   observed Invincible without delaying Triple Shot permanently.
