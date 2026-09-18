# SalvageCells

`SalvageCells` is a Windower 4 addon for the 20 imbued cells used in original
Salvage. On each character it:

- lots one copy of a cell while that character still needs its unlock;
- uses acquired cells on that character, one at a time;
- confirms use by observing that the inventory count decreased;
- passes duplicates after the character owns one or has confirmed the unlock;
- drops remaining copies after the unlock or after leaving Remnants.

In a multibox party, Dolomedes is the default authoritative coordinator. The
first copy of every distinct cell type is assigned to Dolomedes, powering him
first. Later copies rotate through the configured roster: Tackleberry,
Kickpuncher, Barneystinson, Smalls, Achoo, and back around. A duplicate cell
skips a character who was already assigned that cell.

Only configured characters in the coordinator's six-person party whose
reported zone matches the coordinator's current Remnants zone are eligible.
Characters left in the party outside the dungeon are skipped. All clients
receive the coordinator's assignment over Windower IPC, so only the assigned
character lots and the others pass. A client that has not received an
assignment waits instead of guessing or passing. The coordinator republishes
each assignment until that treasure-pool entry resolves, so a client cannot get
stuck merely because it was still loading or resetting when the first IPC
message was sent.

All clients must load or reload the same addon version before entering. Keep
the addon loaded outside Remnants so every client observes zone entry and
starts the same run state.

Salvage II does not use cells. It uses Runic Lamps and automatic unlocks from
defeated enemies, so this addon has nothing to do there.

## Why this instead of existing addons?

Windower's official `CellHelp` is a useful historical lot-order display, but its
published source is from 2013. It generates profiles for the old LightLuggage
plugin, supports four configured players, lists pass bugs, and does not use or
clean up cells. `Treasury` can lot/pass/drop fixed item lists but cannot decide
from per-run cell state or use the cells. Neither provides the complete workflow
implemented here.

Do not configure these same cells in Treasury, CellHelp, or LightLuggage at the
same time; two addons issuing conflicting treasure-pool actions cannot coordinate.
The stock `Lottery` addon also needs a compatibility exclusion for item IDs
5365-5384. Otherwise each automated lot tells every other Windower client to
pass that cell's pool slot, and a multibox party can make every cell disappear.

## Install and load

Copy the `SalvageCells` directory to `Windower/addons/`, then load it before
entering original Salvage:

```text
//lua load SalvageCells
```

Entering one of the four Remnants zones starts a fresh 20-cell state. Each
Windower client decides independently, making it suitable for multibox parties.

## Safety behavior

Windower exposes the aggregate Pathos status icons but not a trustworthy
per-cell history after the fact. Therefore, loading or logging in while already
inside Remnants enters **safe/unknown mode**: the addon will not lot, pass, use,
or drop cells based on guesses. If it really is the beginning of an original
Salvage run, initialize it explicitly:

```text
//scells begin
//scells turn Tackleberry
```

Do not use `begin` in the middle of a run; it deliberately assumes all 20
restrictions are still locked.

When inventory is full, a needed pool item is left untouched instead of being
passed. Item-use failures (movement, menus, another action) time out and retry.
After three failures on the same cell, the addon assumes that restriction was
already unlocked before a mid-run reload, marks it complete, drops the stale
copy, and moves on. Use `//scells need <cell>` to reverse that assumption.

## Commands

```text
//scells status
//scells on
//scells off
//scells begin
//scells need incus
//scells done incus
//scells need all
//scells done all
//scells help
```

`need` and `done` are recovery/override commands. Cell names work with or
without the word `Cell`.

`turn <name>` changes where duplicate-cell rotation resumes. Coordinator-first
assignment still applies to any cell type Dolomedes has not yet received. The
command only needs to reach the coordinator.

## Settings

After first load, Windower creates the normal per-character settings file.
Defaults enable lot, pass, use, and drop automation. Available values are:

- `Enabled`, `AutoLot`, `AutoPass`, `AutoUse`, `AutoDrop`
- `ActionDelay` (default `3.0` seconds between use attempts)
- `UseTimeout` (default `8.0` seconds before a failed use is retried)
- `MaxUseFailures` (default `3` before assuming a pre-reload unlock)
- `LotRetryDelay` (default `12.0` seconds)
- `AssignmentRebroadcastDelay` (default `1.0` second)
- `Verbose`
- `Roster` (comma-separated distribution order)
- `Coordinator` (default `Dolomedes`)
- `PrioritizeCoordinator` (default `true`; first copy of each cell type goes to
  the coordinator)

This is third-party automation and is not supported by Square Enix or Windower.
Test it with visible inventory and treasure pools before relying on it unattended.


## Project credit and license

Designed and directed by Don Lawrence.  Code developed with OpenAI Codex.

This project's original contributions use the BSD 3-Clause terms in `LICENSE`.
Existing upstream credits and third-party license notices remain applicable.
AI assistance is documented separately from ownership and upstream authorship.
