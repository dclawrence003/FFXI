# HealBot fixes

This directory contains a small generated patch for
[Lorand's HealBot](https://github.com/lorand-ffxi/HealBot). HealBot remains
Lorand's work; the complete addon is deliberately not redistributed here.

## Changes

The patch contains three focused corrections:

1. `HB_Actions.lua` ignores a queued buff entry whose resolved `action` is nil.
   This prevents the repeated `attempt to index field 'action'` runtime error.
2. `HealBot.lua` destroys active text objects when the addon unloads.
3. `HealBot_utils.lua` removes orphaned HealBot-generated text objects after a
   text-box refresh.

The latter two changes address old monitored-character/status boxes remaining
visible after refreshes or unloads.

## Tested base

All three original files used to generate this patch exactly matched the
corresponding files on the `master` branch of `lorand-ffxi/HealBot` when checked
on July 26, 2026.

## Apply

Back up HealBot first. From the root of a HealBot checkout:

```powershell
git apply --check C:\path\to\codex-ffxi\patches\HealBot\codex-fixes.patch
git apply C:\path\to\codex-ffxi\patches\HealBot\codex-fixes.patch
```

Then copy the patched HealBot directory into Windower and reload it:

```text
//lua reload HealBot
```

## Revert

From a clean Git checkout:

```powershell
git apply -R C:\path\to\codex-ffxi\patches\HealBot\codex-fixes.patch
```

## Attribution

HealBot is authored by Lorand. The three changes in this patch were generated
by OpenAI Codex while diagnosing runtime spam and orphaned UI boxes.
