# Sortie A magic-kill profile v2

Purpose: earn the Shard A and Metal A chests from six Abject Acuex while
preserving a fast party clear and making the final single-target magic damage
automatic.

## Evidence used

- The bounded 2026-09-13 PartyOps run spent roughly fourteen minutes on eight
  Abject Acuex, yet only three endings were likely Smalls Fire finishes. The
  manual stop-and-cast race was the dominant failure, not party damage.
- Smalls started at 1,807/1,811 MP, ended at 658, reached 335, spent 1,583
  seconds at or below 50%, and never converted. His longest low-MP stretch was
  918 seconds. Full support resets on every profile change amplified the loss.
- Umbra's team uses an RDM-centered Liquefaction method: Flat Blade or
  Requiescat > Red Lotus Blade, then two Fire bursts (Fire V plus Fire III/IV),
  with Aquaveil maintained to prevent Acuex hits from interrupting the burst.
- Local BGWiki data confirms Flat Blade has Impaction, Red Lotus Blade has
  Liquefaction/Detonation, and Impaction > Liquefaction produces Liquefaction.
  Windower action message 295 is the exact Liquefaction damage packet.
- The adaptation for this party lets all six build TP at full speed, then uses
  Tackleberry's Flat Blade and Smalls's Red Lotus Blade. Smalls alone owns the
  Fire finish so the qualifying damage source is deterministic.

## v2.0 control model

1. The first party action on exact `Abject Acuex` loads and arms the profile.
2. Tackleberry gets the preferred first engagement; an existing party claim or
   1.25-second fallback releases all six without an operator or leader gate.
3. All six burn until Tackleberry and Smalls each have 1,000 TP.
4. The other four stop. Tackleberry uses Flat Blade; after its confirmed packet
   Smalls uses Red Lotus Blade inside the chain window.
5. Only action message 295 starts the burst. Smalls queues Fire V, Fire IV, and
   Fire III; the legal-action adapter sends the strongest available spell at
   each free cast slot.
6. A missed WS, missing Liquefaction, or expired burst rebuilds automatically.
   At 35% HP the runtime stops every physical lane and maintains a Fire-only
   finish rather than risking another melee killing blow.
7. The encounter retires while retaining the arm state for the next Acuex.
   Alt-P and all manual input remain authoritative.

Combat packets provide a useful last-damage diagnostic, not chest proof. The
route advances only from the resulting all-six Shard/Metal temporary items.

## Promotion measurements

- Confirm every Flat Blade, Red Lotus Blade, Liquefaction, Fire cast, burst, and
  final damage packet against the next PartyOps capture.
- Measure bind-to-first-hit time, time to both 1,000-TP thresholds, chain retry
  rate, two-burst rate, and total seconds per credited target.
- Verify Aquaveil uptime and record any burst interruption.
- Confirm six qualifying kills across at least two runs before lowering the
  35% Fire-only margin.
- Compare Smalls's MP curve, Convert count, and maintenance casts against the
  2026-09-13 baseline.
