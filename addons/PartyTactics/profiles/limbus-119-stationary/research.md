# Limbus 119: stationary floor clearing

This tactic preserves the current PartyStart Limbus behavior while moving its
orchestration into an isolated PartyTactics module. Version 1.2.0 also closes
the shared EasyFarm-state gap found during live Locus validation.

- Tackleberry Flash-pulls and establishes the synchronized target.
- Every attacker remains planted; PartyCombat may face and engage but cannot
  translate any member.
- Smalls maintains broad Haste/Refresh/Phalanx/Shell support, backup cures,
  inexpensive Dia, and bounded pull Silence based on server-ID evidence.
- Barney maintains March, Minuet, and Madrigal. `//pt sleep` reserves one
  best-learned Lullaby as his next action through the reviewed GearSwap path.
- Achoo supplies Fury/Frailty and entrusted Refresh.

Load
`easyfarm/Tackleberry-Limbus-119-Stationary.eup` before arming. It is a
stationary, 18-yalm detection/20-yalm Flash artifact whose allowlist contains
only the reviewed Om' and Apollyon targets from the existing Limbus route. It
keeps the whole-word `Elemental` ignore rule and contains no Apex or Locus XP
targets. PartyTactics never starts EasyFarm or overwrites its active file.

The artifact is deliberately route-scoped, not a claim that it enumerates
every enemy on every Limbus floor. If a different route needs another target,
clone this into a newly named profile-owned artifact and review the allowlist;
do not expand a shared camp file. No configuration can guarantee that an
immune, ranged, or path-blocked enemy will enter the camp.

## Evidence and provenance

Reviewed 2026-08-31.

- [BG Wiki: Category Limbus](https://www.bg-wiki.com/ffxi/Category%3ALimbus)
  documents the post-June-2025 item-level 119 open-battlefield system and its
  Apollyon/Temenos structure.
- [BG Wiki: Temenos West (119)](https://www.bg-wiki.com/ffxi/Temenos_West_%28119%29)
  documents floor transport and the practical need to sleep, bind, or break
  an enemy before using a Matter Diffusion Module.
- Local parity authority: PartyStart's `limbus` profile, fixed progression
  composition, the reviewed Limbus GearSwap controller tests, and actual
  server-ID pull observations. Those local sources define the stationary
  Flash-pull, bounded Silence, healing, and one-shot Lullaby policy.

This is a floor-clearing policy, not a claim that every Limbus floor has
identical enemies or sleep susceptibility. Use manual judgment between floors
and keep any alternate EasyFarm target list in its own named artifact.
