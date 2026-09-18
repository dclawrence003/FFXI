# FFXI Character Core Manager

FFXI Core Manager gives Windower multibox clients persistent, character-aware
CPU affinity and optional multimonitor window placement. Assignments are based
on character window titles, so they survive changing `pol.exe` process IDs.

The package has two parts:

- An elevated PowerShell companion that watches FFXI processes and performs
  Windows-level affinity, placement, taskbar, and monitor-recovery work.
- An optional Windower addon that requests reapplication, consumes saved
  layouts, uses WinControl for resizing, and corrects each client's aspect
  ratio.

It does not automate gameplay and does not use the network.

The optional Windower addon requires the official WinControl plugin. Enable
WinControl in the Windower launcher so the generated autoload script loads it
once. CoreManager deliberately does not issue a second `load WinControl`
command, avoiding a harmless but noisy “Plugin already loaded” warning.

## Local configuration

Committed configuration and presets start unconfigured: no characters, CPU
assignments, window placement, taskbar changes or monitor recovery.  Copy
config.json and the presets folder into an ignored local/ folder, then enter
your character and hardware settings there.  The manager and installer prefer
local/config.json when present.  Keep both preset files alongside it.

The installer preserves an existing installed config.json.  Selecting a
preset uses a local preset when available and writes the installed config, or
local/config.json when the manager is not installed.  CPU numbers and monitor
coordinates are specific to your computer.  A configuration generator is not
yet provided.

## Features

- Reapplies logical-processor affinity after every launch.
- Gives each configured character an independent processor set.
- Optionally places and sizes each borderless FFXI client.
- Uses WinControl so resizing rebuilds FFXI's render surface instead of
  stretching an old one.
- Sets Windower's aspect ratio from the actual configured render dimensions.
- Hides the primary taskbar while FFXI is running while keeping secondary
  taskbars visible.
- Detects a configured monitor disappearing/reappearing and reapplies affected
  layouts after the monitor is stable.
- Coordinates the native Timers plugin's single global settings file so each
  character can load a different vertical timer position without changing X.
- Recovers Timers placement after staggered character logins, zoning, and an
  actual WinControl layout reapplication without unloading every client at
  once.
- Reloads `config.json` automatically after it changes.

## Configuration

Each character is one property under `characters`:

```json
"ExampleCharacter": {
  "logicalProcessors": [2, 3],
  "window": {
    "enabled": true,
    "x": 0,
    "y": 0,
    "width": 1280,
    "height": 720
  }
}
```

Important top-level settings:

| Setting | Meaning |
| --- | --- |
| `pollIntervalSeconds` | Process/configuration polling interval |
| `hidePrimaryTaskbarWhileFfxiRunning` | Hide only the primary taskbar while any `pol.exe` exists |
| `keepSecondaryTaskbarsVisible` | Disable Windows auto-hide and keep secondary taskbars visible |
| `windowManagementEnabled` | Master switch for automatic placement |
| `monitorRecovery.enabled` | Watch for a specific monitor disconnect/reconnect |
| `monitorRecovery.monitorInstancePattern` | WMI monitor instance substring |
| `monitorRecovery.stablePolls` | Stable detections required before recovery |
| `monitorRecovery.characters` | Characters whose layouts should be restored |

Windows monitor coordinates can be negative for displays left of the primary
monitor. Processor indexes are zero-based logical processors.

## Safe dry run

Before installation:

```powershell
.\FFXI-Manager.ps1 -Once -DryRun
```

Confirm every character, affinity mask, and window rectangle in the output.

## Install

1. Edit `config.json` and both presets for the target computer.
2. Double-click `Install.cmd`.
3. Approve the UAC prompt.
4. Select the active Windower folder when prompted, or cancel that selection if
   only the Windows companion is wanted.
5. Load the addon:

```text
//lua load CoreManager
```

The installer creates the scheduled task `FFXI Character Core Manager`. It
runs elevated at sign-in, waits for FFXI clients, and has no execution-time
limit so Windows does not terminate monitor recovery after 72 hours.

For persistent Windower loading, add:

```text
lua load CoreManager
```

to `Windower\scripts\init.txt`.

## In-game commands

```text
//core status
//core apply
//core layout
//core aspect
//core timers
//core timers me
//core timers status
```

- `status` shows the companion's latest result for the current character.
- `apply` requests an affinity reapply.
- `layout` requests and consumes the saved window rectangle.
- `aspect` recalculates aspect ratio from the saved dimensions.
- `timers` queues all configured characters, briefly reloads Timers on one
  client at a time, and writes that character's Y before advancing. This
  avoids shared-file races and is forwarded to Dolomedes when invoked from
  another client.
- `timers me` recovers only the current client's Timers position.
- `timers status` shows the current client's expected position and recent
  recovery state.

Each client requests its own Timers recovery after login, zoning, and a saved
window-layout reapplication. Dolomedes serializes those requests because the
native plugin has only one shared `timers.xml`. Dolomedes also queues a full
catch-up pass after his own login or zone change, covering both login orders:
Dolomedes first or Dolomedes last. Automatic requests are deduplicated and do
not print routine chat messages.

The current personal layout uses Y 300 for Dolomedes, Y 149 for Tackleberry,
Kickpuncher, and Barneystinson, and Y 125 for Smalls and Achoo. The native
Timers plugin does not retain per-character sections in `timers.xml`, which is
why a coordinator is required.

Only `lua load CoreManager` belongs in the shared `init.txt`. Do not add
`core timers` there: every client executes the shared file, while CoreManager's
login recovery already handles startup in a controlled queue.

The Windows companion applies affinity even when the Windower addon is not
loaded.

## Presets

`Choose Layout.cmd` invokes `Set-Preset.ps1` to copy a selected preset into the
live `%LOCALAPPDATA%\FFXIManager\config.json`. The included `Cockpit` and
`FullMain` presets are personal examples, not universal layouts.

Use **Borderless Window** for tiled clients. Be mindful of Windows display
scaling: WinControl operates on FFXI render dimensions, while desktop layout
tools may report scaled logical coordinates.

## Runtime files

After installation:

- Configuration: `%LOCALAPPDATA%\FFXIManager\config.json`
- Log: `%LOCALAPPDATA%\FFXIManager\manager.log`
- Per-character status: `%LOCALAPPDATA%\FFXIManager\status`
- Per-character layout handoff: `%LOCALAPPDATA%\FFXIManager\layouts`
- Addon requests: `%LOCALAPPDATA%\FFXIManager\requests`
- Per-character Timers recovery diagnostics:
  `%LOCALAPPDATA%\FFXIManager\timers-<character>.log`

These runtime files are not part of the repository.

## Conflicts and recovery

- Do not also configure Process Lasso to manage `pol.exe` affinity. Let one
  program own affinity.
- If a window moves by the height of a taskbar after changing Windows taskbar
  behavior, run `//core layout` in that character's own client.
- If the ultrawide disappears when powered off, disable the monitor's Deep
  Sleep option when available and configure `monitorRecovery`.

## Remove

Run `Uninstall.cmd`. It removes the scheduled task, companion files, and the
installed CoreManager addon. It does not remove FFXI or unrelated Windower
files.

## Why a companion is required

Windower Lua does not expose Windows' `SetProcessAffinityMask` API. The
companion performs the Windows operation with the required privileges; the Lua
addon communicates through small local request/status files.

## Authorship

FFXI Core Manager was generated by OpenAI Codex at the direction of the
repository owner and refined through live six-client testing. It uses
documented Windows and Windower interfaces; no third-party addon source was
used as a base or redistributed.
