# Dynamis-D Wave 1 route research

Retrieved 2026-09-01. This profile is paired with
`dynamis-divergence-wave1-boss-magic`, but is independently loadable and owns
only the route-to-boss behavior.

Umbra's operator-supplied baseline is the strategy authority: Dolo alone uses
Death Penalty, Crooked Tactician's Roll, Wizard's Roll, and roughly 1500-TP
Leaden Salute on the minimum required statues while the other five characters
do nothing. Indi-Acumen is optional.

## Evidence

- BG Wiki's [Dynamis - Divergence category](https://www.bg-wiki.com/ffxi/Category%3ADynamis_-_Divergence)
  states that Wave 1 statues are true sight, link with other statues, and can
  spawn one to six monsters. It specifically identifies one-shot Leaden Salute
  kills by a well-geared COR as a way to prevent the adds from spawning.
- The same page records party/alliance proximity hate and warns that unintended
  aggro can transfer immediately. That supports keeping the five inactive
  characters back rather than allowing target, follow, or support loops to run.
- [Leaden Salute](https://www.bg-wiki.com/ffxi/Leaden_Salute) is dark magical
  marksmanship damage with strongly rising TP scaling and Gravitation /
  Transfixion properties. The supplied operator strategy recommends about
  1500 TP for route statues.
- Local GearSwap inspection on 2026-09-01 confirmed Dolomedes has a reviewed
  `DualLeaden` weapon mode using Death Penalty and a dedicated Leaden Salute
  precast set. Roller2's conservative policy applies Crooked Cards to the first
  missing configured roll, so Tactician's Roll is deliberately roll 1.
- No local offline BG Wiki mirror was present in the FFXI workspace or Windower
  tree. Local evidence therefore consists of installed Windower/GearSwap data;
  encounter facts above come from the linked web BG Wiki pages.

## Encoded strategy

1. Only Dolomedes targets, faces, engages, rolls, or weapon-skills. The operator
   moves him between statues; PartyCombat's stationary policy never translates
   him toward melee range.
2. Tactician's Roll is first and Wizard's Roll second; automatic Leaden Salute
   waits for 1500 TP.
3. BRD, RDM, GEO, PLD, and DNC controllers plus AutoWS2 are explicitly stopped.
4. `acumen` is an optional, one-shot typed spell request to Achoo. It does not
   enable persistent GEO behavior.
5. With Dolo manually positioned outside melee and the intended statue selected,
   `force` arms and establishes that one target without approach movement.
   Combat is disarmed between statues. Transition to the boss is a separate
   six-client profile commit.
6. EasyFarm and FastFollow remain outside PartyTactics ownership. EasyFarm must
   be paused and follower placement/follow state must be managed deliberately
   so an external controller cannot defeat the five-client inactivity boundary.

## Uncertainties and live checks

- Exact required statue count and safest line vary by zone and current pulls;
  no route geometry is automated.
- Confirm the first Leaden kill, valid ranged engagement distance, and TP
  threshold in live combat. Raise only this profile's threshold/version if a
  particular statue survives.
- The profile never selects statues by name. The operator remains responsible
  for eye/icon choice, line of sight, and avoiding links.
