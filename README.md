# FFXI Multibox Tools

Experimental Windower addons, Windows utilities, and patches developed for a
six-character Final Fantasy XI multibox setup.

## AI-generated software

Every new tool and every modification in this repository was generated with
AI, directed and tested by the repository owner. The code is published openly
so other players can inspect it, test it, improve it, or ignore it.

If AI-generated software is a deal-breaker for you, that is completely fine.
This is not the repository for you.

## Current status

These projects are working prototypes, not polished general-purpose releases.
They currently reflect one Windows computer, one Valefor roster, and one
Windower configuration. The long-term goal is to make each useful project
configurable for any number of characters without embedding a particular
roster or monitor layout.

Back up your existing addon and configuration files before testing anything.
FFXI packet behavior and third-party addons can change. Read each project's
limitations before use.

## Projects

| Project | Type | Purpose | Status |
| --- | --- | --- | --- |
| [EventGuard](addons/EventGuard/) | Windower addon | Records NPC event state and offers cautious recovery commands for a client stuck in an interaction | Prototype |
| [AutoWS2](addons/AutoWS2/) | Windower addon | Adds shadow-tested, TP-rate-aware AM3 reserve and hard 3000-TP reapplication safety | Prototype; Tizona validation |
| [Roller2](addons/Roller2/) | Windower addon/fork | Iterates on Selindrile's Roller with safer Snake Eye sequencing | Prototype; live testing |
| [PartyStart](addons/PartyStart/) | Windower addon | Discovers current party jobs and configures non-combat support profiles from one command | Six-character prototype |
| [PartyCombat](addons/PartyCombat/) | Windower addon | Gives selected followers action-driven targeting, distance-limited pursuit, and explicit combat authorization | Tackleberry prototype |
| [FFXI Core Manager](tools/FFXI-Core-Manager/) | Windows utility + Windower addon | Assigns characters to logical processors and restores multimonitor window layouts | Personal-system prototype |
| [InventoryCore + LootAdvisor](tools/InventoryCore/) | Local Node service + Windower addon | Indexes FindAll inventory and provides read-only keep/AH/vendor/upgrade guidance | Valefor prototype |
| [HealBot fixes](patches/HealBot/) | Patch | Guards an invalid queued action and cleans up orphaned text boxes | Applies to Lorand's HealBot |
| [MultiCtrl Warp II queue](patches/MultiCtrl/) | Patch | Replaces fire-and-forget `d2` behavior with confirmation, retries, status, and cancellation | Based on a customized MultiCtrl tree |

## Attribution

AI generation does not erase upstream authorship. Original authors retain
credit for all work used as a base:

- Roller2 derives from Roller 1.8 by **Selindrile**, with the original source
  also crediting **Balloon** and **Lorand**. Roller2 retains the complete
  copyright and redistribution notice from Roller.
- AutoWS2 is a clean implementation inspired by AutoWS 0.3.1 by **Lorand**.
  The original was inspected for behavior and command vocabulary, but its
  source and `lor_libs` are not redistributed.
- EventGuard adapts the menu-release packet sequence from **Akaden's
  Superwarp**, whose notice credits **Ivaar** for menu-lock reset functions.
  The complete applicable BSD notice is retained in EventGuard's source.
  **DiscipleOfEris's NpcInteract** also supplied behavioral context.
- PartyCombat is an independent implementation informed by the targeting
  concept demonstrated by **Selindrile's SendAllTarget**, which itself thanks
  **Arcon**. SAT is not bundled, modified, or required.
- PartyStart's optional controllers integrate with **Selindrile's GearSwap
  framework**, whose shared include credits **Motenten** as an earlier base.
  Those upstream GearSwap files are required from the user's own installation
  and are not redistributed here.
- HealBot is by **Lorand**. This repository contains only a small patch against
  [lorand-ffxi/HealBot](https://github.com/lorand-ffxi/HealBot), not a
  redistributed copy.
- MultiCtrl identifies its author as **Kate** and is available in
  [Mary-Elizabeth/FFXI-Addons](https://github.com/Mary-Elizabeth/FFXI-Addons).
  This repository contains only our patch.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and each project README
for details.

This repository has no single blanket license. Each project or inherited
source notice governs its own files. Where upstream code has no clear
redistribution license, this repository publishes an original integration or
a patch instead of republishing the upstream addon.

## Safety and scope

- Nothing here is supported by Square Enix, Windower, or the original addon
  authors.
- InventoryCore and LootAdvisor are advisory and read-only. They do not lot,
  pass, sell, send, or drop items.
- EventGuard can inject recovery packets. Use its forced local recovery only as
  a last resort; relogging remains the authoritative recovery path.
- Core Manager changes process affinity, window placement, and taskbar state.
  Its supplied configuration is hardware-specific.
- PartyCombat injects target/engage packets and can move authorized followers
  in a straight line. Its distance limits are safety rails, not pathfinding.

## Repository hygiene

Runtime databases, FindAll exports, generated LootAdvisor caches, logs,
character settings, backups, and authentication material are intentionally
excluded from source control.
