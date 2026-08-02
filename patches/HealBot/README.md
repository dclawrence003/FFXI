# HealBot fixes

This directory contains a small generated patch for
[Lorand's HealBot](https://github.com/lorand-ffxi/HealBot). HealBot remains
Lorand's work; the complete addon is deliberately not redistributed here.

## Changes

The patch contains five focused corrections:

1. `HB_Actions.lua` ignores a queued buff entry whose resolved `action` is nil.
   This prevents the repeated `attempt to index field 'action'` runtime error.
2. `HealBot.lua` destroys active text objects when the addon unloads.
3. `HealBot_utils.lua` removes orphaned HealBot-generated text objects after a
   text-box refresh.
4. `HealBot_buffHandling.lua` reconciles the stored debuff table against each
   authoritative IPC buff snapshot. This clears effects that have worn off and
   prevents every HealBot client from repeatedly casting Erase for a stale
   remote debuff.
5. A status-removal spell returning `No effect` quarantines the corresponding
   status until a live buff snapshot confirms that it disappeared. This stops
   Erase/na-spell retry storms caused by an active status being incorrectly
   classified as removable, while allowing it to be reconsidered if it returns.

The second and third changes address old monitored-character/status boxes
remaining visible after refreshes or unloads. The fourth and fifth address
synchronized Erase/na-spell spam that continues with `No effect`.

## Tested base

All five original files used to generate this patch exactly matched the
corresponding files on the `master` branch of `lorand-ffxi/HealBot` when checked
on July 26 or August 1, 2026.

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

HealBot is authored by Lorand. The five changes in this patch were generated
by OpenAI Codex while diagnosing runtime spam and orphaned UI boxes.
