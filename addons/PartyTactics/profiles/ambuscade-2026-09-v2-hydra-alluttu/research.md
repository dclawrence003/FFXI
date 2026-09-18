# Ambuscade September 2026 V2: Alluttu (Hydra)

Retrieved and reviewed 2026-09-03. This profile is designed from Very
Difficult downward, but its first live run should be a lower-difficulty
instrumented rehearsal. Difficulty is operator-declared in post-fight data;
the runtime never guesses it.

## Evidence

- Square Enix's September 2024 preview identifies Hydra as Volume 2 and says
  the intended mechanic is to remove its heads quickly.
- The local BG Wiki vault entry confirms the exact enemy name `Alluttu` on all
  five difficulties. Its cached strategy section is otherwise sparse:
  `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/ambuscade/ambuscade-archive.md`
  (Hydra section near lines 8371-8444).
- The Japanese encounter archive records the complete move set and says
  skillchain completion can sever heads. It reports increased damage taken at
  fewer heads, head regrowth, a roughly one-minute magic barrier from Pyric
  Bulwark, a roughly one-minute physical barrier from Polar Bulwark, and that
  the two barriers overwrite rather than coexist.
- That archive also records Nerve Gas only with all three heads, Pyric moves
  while the fire head remains, Polar moves while the ice head remains,
  Trembling as physical damage plus dispel, Serpentine Tail as a dangerous
  rear counter, and high resistance to fire, wind, ice, and dark.
- A community report based on more than 150 Difficult runs corroborates the
  value of long skillchains, Stun, a front-facing tank, avoiding the rear, and
  ending Polar Bulwark before it turns a short run into a long one. It instead
  attributes severing to accumulated damage. The controller therefore uses a
  strategy effective under either model and records the uncertainty rather
  than encoding either claim as fact.

Sources:

- [Square Enix September Version Update](https://forum.square-enix.com/ffxi/threads/62041-September-Version-Update?mode=threaded&p=662184&s=a56445d2375d0ea04f095f8559453fb2)
- [BG Wiki Ambuscade Archive](https://www.bg-wiki.com/ffxi/Ambuscade_Archive)
- [Japanese FFXI Wiki, September 2022 Ambuscade](https://wikiwiki.jp/ffxi/%E3%82%A2%E3%83%B3%E3%83%90%E3%82%B9%E3%82%B1%E3%83%BC%E3%83%89/%E6%88%A6%E9%97%98/220912)
- [Hydra Ambuscade physical strategy report](https://www.reddit.com/r/ffxi/comments/1flwcfo/hydra_ambuscade_guide_physical_dd_sub_2minute_runs/)

## Automated strategy

The operator applies the profile and waits for its fresh six-client
ACK/preflight barrier, then positions Tackleberry in front of Alluttu and both
Kickpuncher and Dolo in melee range on safe flanks. Stationary PartyCombat
needs Dolo to melee for autonomous TP; 15--19-yalm ranged placement would
stall Last Stand after prebuilt TP is spent. The three support characters must
also remain away from the rear counter arc. One `//pt arm` then gives the
runtime permission to perform everything below:

1. After one explicit `//pt arm`, bind the exact live `Alluttu` ID and entity
   index in either Ambuscade battlefield zone (LegionA 183 or LegionB 287).
2. Maintain a bounded Grape Daifuku heartbeat on Dolo, Tackle, and Kick.
   Their adapters consume one only when local Food is absent, and refuse every
   physical offense dispatch until buff 251 is locally confirmed. Movement,
   expiry, or a busy action therefore delays damage instead of silently
   producing an unfooded run.
3. Let Barney's generic physical scheduler establish March, Minuet V, and
   Madrigal, then opportunistically queue Clarion Call and fixed Valor Minuet
   IV through his pinned adapter. A cooldown or unavailable fourth song never
   blocks the three-song baseline. Keep all six characters within Barney's
   song/barspell radius during setup: Valor Minuet IV and Barparalyzra are not
   accepted until their action packets cover all six intended recipients.
   Missing recipients retry finitely with an advisory. GearSwap alone chooses
   song instruments.
4. Queue Crusade, Divine Emblem, and Sentinel on Tackle through finite setup
   windows. A cooldown or rejected optional mitigation step is reported and
   skipped so repeat runs cannot deadlock. Flash against the exact unclaimed
   Alluttu remains mandatory and packet-confirmed. After party claim, force
   Dolo, Tackle, and Kick to engage, establish Geo-Frailty, use Box Step, and
   keep Flash/Provoke hate cycling. Both opening and periodic Box Step attempts
   have finite retry windows and backoff, so a missed step cannot stall chains.
5. Repeatedly execute packet-confirmed Evisceration -> Savage Blade
   (Fragmentation message 291) -> Last Stand (Light message 288), followed by
   simultaneous Thunder IV bursts from Smalls and Achoo.
6. On Nerve Gas or Polar Bulwark ready packets, give Kick's Violent Flourish
   first refusal, then use Tackle's Shield Bash after the fixed fallback delay.
   A successful job-ability packet proves execution but not that Stun landed,
   so it never suppresses the fallback. Both reaction lanes are explicitly
   cancelled when the observed move completes or the three-second response
   window expires, preventing a delayed Bash or Flourish from leaking into the
   next monster action.
7. If Polar Bulwark completes, cancel physical work for 65 seconds and rotate
   exact-target Thunder IV casts. If Pyric Bulwark completes, cancel magic work
   for 65 seconds and resume physical Light chains. Because the barriers
   overwrite, the later observed Bulwark immediately becomes authoritative.
   Outstanding fallback nukes are cancelled before the natural Polar timer
   releases PartyCombat back to physical mode.
8. Nerve Gas, blasts, Barofield, Trembling, and party HP below 85% suspend
   coordinated offense so the existing `/WHM`, PLD, and DNC cure/status
   surfaces can act. Trembling and confirmed refresh deadlines rearm the
   repeatable Geo-Frailty, Barparalyzra, and Crusade work through finite
   maintenance windows. Entering a blocking maintenance transaction cancels
   any partial skillchain first. An initial Barparalyzra coverage miss instead
   retries through a nonblocking bounded cycle until all six are confirmed.
   The generic BRD/GEO support schedulers retain their normal responsibility
   for the three-song and Indi-Fury baselines.
9. A zero-HP party member cancels all six semantic queues, sends `pc off`,
   releases encounter authority, and consumes the arm. Positioning and a fresh
   `//pt arm` are required before another attempt.

No head count is guessed. Repeated skillchains plus Thunder damage are useful
whether severing is probabilistic on chains, damage-threshold based, or both.

## Composition and subjobs

- Dolo: COR/DNC normally; COR/NIN is accepted when shadows are preferred.
- Tackle: PLD/WAR for Provoke and the fixed hate sequence.
- Kick: DNC/WAR for melee output, Box Step, Violent Flourish, and Waltz backup.
- Barney, Smalls, and Achoo: `/WHM`. Their native cure and status-removal
  controllers remain available even while a fight action is reserved.

## Known uncertainties and first-run gates

- Very Difficult head sever thresholds and regrowth timing need live evidence.
- Whether a successful Violent Flourish action packet always means the readied
  Hydra move was interrupted needs action-log correlation; Shield Bash remains
  a timed fallback.
- Start on Normal, inspect the passive metrics, then advance N -> D -> VD only
  after clean setup, chain, Bulwark, and Nerve Gas observations. Any tuning is
  a new version of this profile and adapter; no established profile is edited.
