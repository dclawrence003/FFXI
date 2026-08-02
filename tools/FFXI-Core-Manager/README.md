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

## Prototype warning

The committed configuration and presets are the tested settings for one
computer:

- Intel Core i7-11700K, 8 physical cores / 16 logical processors
- One 5120x2160 ultrawide and two portrait side monitors
- Six named characters

Do not install the supplied configuration unchanged on another machine. CPU
numbers and monitor coordinates are hardware-specific. The manager's character
map can contain any number of characters, but a friendlier configuration
generator has not been built yet.

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
```

- `status` shows the companion's latest result for the current character.
- `apply` requests an affinity reapply.
- `layout` requests and consumes the saved window rectangle.
- `aspect` recalculates aspect ratio from the saved dimensions.

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
