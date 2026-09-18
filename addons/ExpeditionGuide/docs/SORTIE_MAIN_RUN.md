# Sortie main-run workflow

## Jobs before entry

| Character | Job |
| --- | --- |
| Dolomedes | COR/DNC |
| Tackleberry | PLD/SCH |
| Kickpuncher | DNC/WAR |
| Barneystinson | BRD/WHM |
| Smalls | RDM/WHM |
| Achoo | GEO/WHM |

Load ExpeditionGuide and PartyTactics on all six clients. Only Dolo renders
the guide; the other five ExpeditionGuide instances are passive sensors. Keep
Superwarp available on Dolo. The arrow is intentionally off during calibration.
The route is already selected and does not need a profile, arm, or force
command.

After installing a new build into a running six-box session, run this once
while everyone is out of combat:

```text
//exec sortie_reload.txt
```

This is a deployment reload, not part of the normal Sortie workflow.

## What the operator does

1. Confirm Sortie entry at the transposer.
2. Follow the detailed HUD directions and open doors encountered on the real
   hallway route. Use `//exg arrow on` only when testing the provisional arrow.
3. Choose the exact target named by the guide and engage it with Tackleberry.
   If Dolo or another party member gets the first action instead, keep playing:
   the same exact-target synchronization and no-gate release still apply.
4. Gather all six at each chest and open it once.
5. Improvise whenever reality beats the route. `//exg next`, `//exg skip`, and
   `//exg wp` correct guide state without changing game state. Alt-P stops
   combat immediately.

## What happens automatically

| Segment | Automatic result |
| --- | --- |
| Startup | On the first post-entry step, `sortie-main-v1` loads and arms once; it stays active for the run. |
| Device/Gadget | The guide waits for an in-range source, requests the party warp, retries every 12 seconds if needed, and confirms relocation before advancing. |
| C Skeleton/Ghoul | The internal C recipe takes over; Tackle pulls, Kick > Dolo makes Fragmentation, both Smalls and Achoo burst Thunder, and failures retry. |
| Ordinary trash | All six close and spend TP; a Bhoot or other interruption never invokes the C objective recipe. |
| Skomora | The internal non-REMA boss recipe runs; all six close after Tackle's opening threat. |
| B Biune elemental | All six burn continuously and spend ready TP. Nobody pauses or disengages for the objective. |
| Leshonn | Selecting the boss stages no-debuff/no-Sentinel support without engaging. Put Tackle alone in front and the other five behind/rear-flank; Tackle then starts the Savage Blade/Black Halo plan while Kick holds WS. |
| A Acuex | All six build TP; Tackle Flat Blade > Smalls Red Lotus Blade makes Liquefaction; Smalls uses Fire IV and Fire III under Aquaveil. A failed chain automatically resumes stopped builders and retries. |
| Ghatjot | The internal no-Water recipe uses Savage Blade, Evisceration, and Black Halo. |

## Route spine

1. Device C → easy Skeleton/Ghoul camp beside Gadget C → Shard/Metal C →
   Skomora.
2. Device B → five Biune elementals → Shard B → Leshonn. Metal B is skipped
   initially to test whether ten extra elemental kills are worth the safety.
3. Device A → northwest Acuex camp beside the Ghatjot line → Shard/Metal A →
   Ghatjot.

The B walking points are the new live-calibration segment. Follow the actual
hallway if an arrow point is wrong, use `//exg wp` to advance that point, and
record the correction with `//exg mark` when standing at the intended turn.
