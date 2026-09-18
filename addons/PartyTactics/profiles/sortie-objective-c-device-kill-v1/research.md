# Sortie onboarding: C-Device controlled kill v1

Retrieved and reviewed 2026-09-09. This profile covers only the first-party
onboarding objective that awards Ra'Kaznar Plate C. It is deliberately not a
Sector C farm, Cachaemic Bhoot profile, boss profile, or automatic puller.

## Evidence

- The locally cached and live [BG Wiki Sortie category](https://www.bg-wiki.com/ffxi/Category%3ASortie)
  defines Chest C2 as defeating a Cachaemic foe beside Diaphanous Device C.
  It separately defines the Materialize/Bitzer sequence for Sheet C, so the
  combat profile must not interact with either object.
- The current [FFXIAH beginner route](https://www.ffxiah.com/forum/topic/57533/ffxi-sortie-a-beginners-guide-to-locating-gems/)
  confirms that the enemy must die directly next to Device C. It describes a
  nearby Corse pull and warns that Corses can Charm at low HP.
- The current [Japanese FFXI Wiki Sortie page](https://wikiwiki.jp/ffxi/%E3%82%BD%E3%83%BC%E3%83%86%E3%82%A3)
  lists Cachaemic Skeleton, Ghoul, Corse, and Ghost as level 127-129 normal
  Sector C enemies and marks each as non-linking. It independently states the
  Device C proximity objective.
- Installed ExpeditionGuide content supplies the three actual Sortie instance
  zone IDs: 133, 189, and 275. Existing reviewed PartyTactics profiles prove
  the fixed COR/PLD/DNC/BRD/RDM/GEO controllers and weapon modes used here.

## Cooperative strategy

1. Load the profile while the whole party is gathered at Device C. Loading
   selects support and weapon modes but leaves PartyCombat inert.
2. Tackleberry manually Flash-pulls a single normal Cachaemic to the Device.
   The default recommendation is a Ghost so the first attempt avoids Corse
   Charm. The operator may choose another normal Cachaemic if positioning or
   live conditions make that better.
3. Once the enemy is visibly beside the Device, Dolomedes selects that exact
   target and uses `Ctrl-P` or `//pt force`. PartyCombat is stationary: it may
   synchronize targeting, facing, and engagement, but it cannot walk anyone
   toward or away from the objective location.
4. All six use independent physical weapon-skill lanes with Chaos/Samurai,
   physical songs, Haste/Refresh/Phalanx/defense support, Fury/Frailty, and
   distributed cures/status recovery.
5. Ordinary PartyCombat target-end handling stops each client when the foe
   disappears. The operator presses `Alt-P` for an explicit party-wide disarm,
   visually confirms the Plate C chest, then advances ExpeditionGuide.

There is no ordered opener, skillchain transaction, ACK requirement,
preflight requirement, support-result requirement, target-name gate, or
fight-specific GearSwap adapter. A manual retarget, spell, ability, weapon
skill, ranged attack, movement correction, cure, crowd-control action, or
emergency stop remains available throughout. If the pull is bad, the operator
may disarm and improvise without fighting an automation lock.

## First-run observations still needed

- Calibrate the final corridor turns and Device C coordinate on the live map.
- Observe how close the selected foe must be when it dies for Chest C2.
- Confirm the most convenient non-linking pull from this party's actual route;
  Ghost is conservative, while Corse is closer but carries Charm risk.
- Confirm that all six stationary attackers are in melee range before forcing;
  a client outside range is expected to remain planted rather than approach.
- Preserve the Windower chat log and ExpeditionGuide step history if the chest
  does not appear. Do not hide a failed live condition behind `//exg skip`.
