# Bars combat hot-path patch

This directory contains a focused performance patch for Bars 4.11.2 by Key.
It is installed on the live Windower copy and is also kept here so a future
Bars update cannot silently erase the work.

## What changed

- Incoming packets are rejected by ID before `packets.parse` runs. Action,
  action-message, and zone packets use their existing specialized paths.
- Ordinary melee and ranged actions return before Bars builds display strings,
  resolves action resources, and formats colors.
- Immutable action, roll, skillchain, debuff, Corsair-shot, Treasure Hunter,
  and message lookup tables are built once at load instead of inside combat
  handlers.
- The per-action `calculateInfo` closure and AoE-facing helper are now stable
  addon-scope functions.
- AoE distance filtering compares the already-squared distance directly and
  avoids a square root for every nearby entity.
- Defensive checks ignore incomplete action packets during login/zoning.

No visual feature, texture, icon, animation, bar size, debuff timer, filtering
choice, or quality setting was disabled.

## Apply or verify

From an unmodified Bars 4.11.2 directory:

```powershell
git apply --check C:\Users\DC03\Documents\FFXI\patches\Bars\performance-hot-path.patch
git apply C:\Users\DC03\Documents\FFXI\patches\Bars\performance-hot-path.patch
```

Activate the already-installed copy on Dolomedes when convenient:

```text
//lua reload Bars
```

## Validation

The patch was dry-applied and then applied to an exact backup of the installed
4.11.2 source. The resulting combat/packet prefix parses as Lua and exactly
matches the live installed file after newline normalization. The full file
uses Windower string-method syntax that the standalone `luaparser` package
does not understand; its first full-file parser rejection is unchanged from
the original source and remains after all modified sections.

## Backup

The exact pre-change source is stored at:

```text
C:\Users\DC03\Documents\FFXI\.codex-backups\addon-optimization-20260908\Bars\Bars.lua.before
```

