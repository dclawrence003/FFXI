# Locus Dire Bats EasyFarm artifact

Load `Tackleberry-Locus-Dire-Bats-Stationary.eup` manually in EasyFarm before
arming the PartyTactics Locus profile. It is a copy of the reviewed stationary
PLD/PartyCombat setup with three encounter-local changes:

- the only target is `Locus Dire Bat`;
- detection is 18 yalms and the Flash action boundary is 20 yalms;
- approach remains Off, so EasyFarm never navigates the planted puller.

The artifact deliberately has its own descriptive `.eup` filename, and
PartyTactics never overwrites EasyFarm's active file. Loading it is an explicit
operator action. Keep a different `.eup` file for every other camp or
encounter.
