# Locus Dire Bats: King Ranperre's Tomb

This tactic began as a behavior-preserving migration of PartyStart's
`locusbats` profile for the fixed progression party. Version 1.3.0 records the
live-verified support policy, adds result-confirmed Locus enfeebles, and ships a
fight-local EasyFarm artifact without changing the legacy PartyStart preset or
any other PartyTactics fight.

- Tackleberry owns stationary Flash pulling and primary Majesty recovery.
- Every member is a PartyCombat attacker and synchronized targeter.
- PartyCombat movement is stationary; EasyFarm owns pull acquisition.
- Barney uses March, Ballad III, Madrigal, Barblizzara, and Elegy through the
  existing reviewed GearSwap controller.
- Smalls establishes Protect on the party first, then prioritizes Distract and
  Dia while respecting the established MP and target-HP reserves. Shell remains
  intentionally off because the relevant bat threat is physical/status based.
- Achoo's opt-in managed heartbeat establishes Indi-Fury immediately, can
  Entrust Indi-Refresh to Tackleberry before combat, and places Geo-Frailty
  after Achoo has a valid battle target and is in combat.
- Kickpuncher's Haste Samba, Box Step, No Foot Rise, and Reverse Flourish are
  combat actions. They begin only after `//pt arm` and after PartyCombat has
  engaged the DNC on the synchronized target.

Manual dependency: load
`easyfarm/Tackleberry-Locus-Dire-Bats-Stationary.eup` before arming combat. It
contains only `Locus Dire Bat`, detects at 18 yalms, requests Flash at 20, and
keeps approach disabled. PartyTactics does not start or rewrite EasyFarm.

## Live validation: 2026-09-01

The native FFXI rolling logs showed roughly 19 kills in 10.5 minutes (about 33
seconds per bat), no deaths, no MP-shortage messages, and healthy weapon-skill
output from all six characters. Barney landed one Carnage Elegy per target and
maintained March/Ballad/Madrigal/Barblizzara with no instrument error. Achoo
maintained Fury/Frailty and entrusted Refresh. Kick used Presto plus level-5
Box Step on essentially every target, Reverse Flourish, and Haste Samba. Smalls
maintained Protect, Haste, Refresh, Phalanx, Distract, and Dia; Shell remained
intentionally absent.

The logs also exposed command contention on Tackle and out-of-range pulls from
the shared 22-target EasyFarm file. The shared PLD controller now gives every
issued action one bounded lease across both of its tick entry points. The
profile-owned EasyFarm artifact removes the cross-fight target list and keeps
detection inside reliable Flash range. No BRD instrument, DNC action, GEO spell,
COR roll, or Locus buff choice was changed from that successful run.

## Evidence and provenance

Reviewed 2026-08-31.

- [BG Wiki: Locus Dire Bat](https://www.bg-wiki.com/ffxi/Locus_Dire_Bat)
  confirms the King Ranperre's Tomb listing, level 133-135 range, passive
  behavior, Ultrasonics, and Blood Drain.
- [BG Wiki: Apex/Locus Monsters](https://www.bg-wiki.com/ffxi/Category%3AApex_Monster)
  lists the 1,264 accuracy target for Locus Dire Bats.
- [BG Wiki: Evasion Down](https://www.bg-wiki.com/ffxi/Evasion_Down) identifies
  Evasion Down as Ice-aligned and Ultrasonics as a source; the reviewed Barney
  controller's Barblizzara policy is intended to improve resistance to it.
- Local parity authority: `PartyStart.lua`, `data/compositions.lua`, and the
  reviewed BRD/RDM/PLD/DNC/GEO GearSwap controllers under
  `addons/PartyStart/gearswap/`. The new RDM and GEO modes are additive and are
  selected only by this profile; the old modes remain unchanged.

EasyFarm acquisition, camp placement, and observed MP/accuracy performance are
local operational choices, not claims made by the wiki pages.
