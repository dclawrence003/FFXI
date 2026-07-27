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
| [Roller2](addons/Roller2/) | Windower addon/fork | Iterates on Selindrile's Roller with safer Snake Eye sequencing | Prototype; live testing |
| [FFXI Core Manager](tools/FFXI-Core-Manager/) | Windows utility + Windower addon | Assigns characters to logical processors and restores multimonitor window layouts | Personal-system prototype |
| [InventoryCore + LootAdvisor](tools/InventoryCore/) | Local Node service + Windower addon | Indexes FindAll inventory and provides read-only keep/AH/vendor/upgrade guidance | Valefor prototype |
| [HealBot fixes](patches/HealBot/) | Patch | Guards an invalid queued action and cleans up orphaned text boxes | Applies to Lorand's HealBot |
| [MultiCtrl Warp II queue](patches/MultiCtrl/) | Patch | Replaces fire-and-forget `d2` behavior with confirmation, retries, status, and cancellation | Based on a customized MultiCtrl tree |

## Attribution

Original authors retain credit for all work used as a base:

- Roller2 derives from Roller 1.8 by **Selindrile**, with the original source
  also crediting **Balloon** and **Lorand**. Roller2 retains the complete
  copyright and redistribution notice from Roller.
- HealBot is by **Lorand**. This repository contains only a small patch against
  [lorand-ffxi/HealBot](https://github.com/lorand-ffxi/HealBot), not a
  redistributed copy.
- MultiCtrl identifies its author as **Kate** and is available in
  [Mary-Elizabeth/FFXI-Addons](https://github.com/Mary-Elizabeth/FFXI-Addons).
  This repository contains only our patch.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and each project README
for details.

## Safety and scope

- Nothing here is supported by Square Enix, Windower, or the original addon
  authors.
- InventoryCore and LootAdvisor are advisory and read-only. They do not lot,
  pass, sell, send, or drop items.
- EventGuard can inject recovery packets. Use its forced local recovery only as
  a last resort; relogging remains the authoritative recovery path.
- Core Manager changes process affinity, window placement, and taskbar state.
  Its supplied configuration is hardware-specific.

## Repository hygiene

Runtime databases, FindAll exports, generated LootAdvisor caches, logs,
character settings, backups, and authentication material are intentionally
excluded from source control.
