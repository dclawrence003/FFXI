# HealBot fixes

This directory contains a small generated patch for
[Lorand's HealBot](https://github.com/lorand-ffxi/HealBot). HealBot remains
Lorand's work; the complete addon is deliberately not redistributed here.

## Changes

The patch contains seven focused corrections:

1. `HealBot_packetHandling.lua` ignores login packets received before
   HealBot's load callback has initialized its Actor and text boxes. This
   prevents startup errors involving `healer.indi` and `montoredBox`.
2. `HB_Actions.lua` ignores a queued buff entry whose resolved `action` is nil.
   This prevents the repeated `attempt to index field 'action'` runtime error.
3. `HealBot.lua` destroys active text objects when the addon unloads.
4. `HealBot_utils.lua` removes orphaned HealBot-generated text objects after a
   text-box refresh.
5. `HealBot_buffHandling.lua` reconciles the stored debuff table against each
   authoritative IPC buff snapshot. This clears effects that have worn off and
   prevents every HealBot client from repeatedly casting Erase for a stale
   remote debuff.
6. A status-removal spell returning `No effect` quarantines the corresponding
   status until a live buff snapshot confirms that it disappeared. This stops
   Erase/na-spell retry storms caused by an active status being incorrectly
   classified as removable, while allowing it to be reconsidered if it returns.
7. `HealBot_packetHandling.lua` safely ignores an individual action effect when
   Windower has not yet resolved its target entity, and uses ID fallbacks in
   packet-debug output. This prevents nil-target error storms during zoning and
   entity-table updates without disabling later action processing.

The third and fourth changes address old monitored-character/status boxes
remaining visible after refreshes or unloads. The fifth and sixth address
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

[HealBot is authored by Lorand](https://github.com/lorand-ffxi/HealBot).
The upstream repository does not advertise a repository-level license through
GitHub, so this directory contains only a focused patch and does not
redistribute the complete addon. The seven changes in this patch were generated
by OpenAI Codex while diagnosing runtime spam and orphaned UI boxes. Lorand
has not endorsed or reviewed the patch.
