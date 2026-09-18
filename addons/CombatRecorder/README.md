# CombatRecorder

Standalone, passive Windower combat history for diagnosing an unattended wipe
after the in-game log has scrolled away. It does not recover already-lost history.
No InventoryCore service, PartyOps service, or leader character is required.

> **Quarantined:** Version 0.1.0 caused all six FFXI clients to hang during its
> first live load on August 31, 2026. Automatic startup was removed and the live
> addon was quarantined. Version 0.1.1 is an undeployed candidate only. Do not
> use the all-client or init instructions below until it passes a one-client
> canary; see [INCIDENT-20260831.md](INCIDENT-20260831.md).

## Use

After a successful one-client canary, install this directory as
`Windower/addons/CombatRecorder` and add
`lua load CombatRecorder` to `Windower/scripts/init.txt` once. For clients already
running, execute from any character with Send loaded:

```text
//send @all lua load CombatRecorder
```

This loads only the recorder. Do not reload GearSwap, PartyStart, or PartyCombat.
If Send is unavailable, run `//lua load CombatRecorder` on each client.

```text
//cr status
//cr mark optional-note
```

`status` reports the last successful disk write, backlog, lost records, and
callback/storage errors. `mark` preserves a manual incident without doing
anything in the game. No death needs to be simulated to test recording.

The installer must pre-create one directory per character under
`Windower/addons/CombatRecorder/data/<Character>/`. The addon deliberately will
not create directories inside the game process; if one is missing it stays inert
and reports an error. Files are then stored there:

- `combat-*.jsonl`: continuously rotated structured history.
- `incident-*.jsonl`: pre-death history and aftermath, retained separately.
- `health.json`: a ten-second heartbeat, including the last successful data
  write. A loaded addon or a heartbeat alone is not proof of healthy capture.

From the repository root:

```powershell
py -3.12 tools/combat_report.py --status
py -3.12 tools/combat_report.py
py -3.12 tools/combat_report.py --at 2026-09-01T03:10:00 --timeline
py -3.12 tools/combat_report.py --output incident-review.txt
```

The default report locates the newest preserved incident across the six clients.
It shows death order, last living HP/MP/target/buffs, spell requests versus result
packets, and recent non-melee combat/diagnostics. Records duplicated into an
incident are deduplicated. Missing clients, incomplete lines, and capture gaps
are called out. The report does not invent a cause of death.

## Evidence captured

- Original, non-injected incoming action packets (`0x028`), including packets
  marked blocked by a display filter. Captures the local character's actions,
  incoming effects, current/puller-target activity, and party death messages.
  The six independent files together provide party coverage.
- Original action messages (`0x029`), with raw message IDs and parameters.
- Outgoing action requests (`0x01A`), distinguishing modified, injected, and
  blocked requests. A request is not evidence of completion or success.
- HP/MP changes, maximum-HP/MP changes, buffs, status, zoning and target changes.
- One-second combat/recent-combat snapshots; ten-second idle snapshots. Includes
  local HP/MP/TP, job/subjob, buffs, selected/battle target, positions, party
  vitals, and Tackleberry's target when the client exposes it.
- Selected healing, recovery and crowd-control recasts. Spell recasts are
  converted from frames to seconds; ability recasts are already seconds.
- Narrow PartyStart/PartyCombat/HealBot/GearSwap diagnostic messages when exposed
  through incoming-text callbacks, and known PartyStart/PartyCombat IPC.

There is no private-chat, tell, party-chat, linkshell-chat, or outgoing-text
recorder. Names, positions, combat activity, and a manually supplied marker note
are local data. No network requests are made.

Native event/packet behavior follows the
[Windower event API](https://github.com/Windower/Lua/wiki/Events), with packet
layouts checked against the installed Windower packet definitions. This addon
uses the native parser directly, not another addon's rewritten action event.

## Retention and overhead

- Routine history: 8 MiB segments, retention target of 32 segments / seven days,
  whichever is reached first. Protected active/pending segments may temporarily
  exceed the completed-file count until the next pruning pass.
- Pre-death ring: up to five minutes, capped at 2 MiB in memory. The incident
  marks when high event volume shortened the available prehistory.
- A confirmed party death saves the ring and the following two minutes. More
  deaths in that window extend the aftermath, with a ten-minute incident limit.
  Each archive is capped at 8 MiB; the newest 16 archives are retained. Routine
  age expiry does not delete those archives.
- Normal on-disk retention is about 384 MiB per character (about 2.25 GiB for
  six), plus a small amount for currently queued/active files and health data.
- At most 4 MiB of queued output per client; disk writes are batched once a
  second with a 128 KiB budget. Disk outages back off for 30 seconds and expose
  errors/lost records instead of accumulating an unbounded backlog.
- No per-frame mob-array scans, inventory scans, HTTP calls, runtime directory
  creation, or persistent
  external process. File pruning only targets this addon's exact generated
  filenames inside its character directory.

Loading while already dead establishes a baseline, not a new death incident.
Transient zero HP alone (such as during zoning) is not considered proof of death.
Unloading closes the session; a fresh process/reload starts a new unique session.
An abrupt game/process/power failure can lose buffered data; the heartbeat and
session boundary help distinguish this from normal death capture.

## Non-interference and limits

This addon does **not** issue input, cast, equip, select targets, move, follow,
inject packets, send IPC, or return a packet/text modification. Exceptions in
capture callbacks are contained. Existing combat controllers and GearSwap files
do not need modifications.

It records what each client can observe, not server-internal hate tables, exact
enemy AI, or commands that GearSwap canceled before sending a packet. HP changes
are not automatically classified as damage: equipment can change maximum HP.
Epoch seconds and per-session sequence numbers preserve local order; exact
sub-second order across clients is unknown. English resource names are used;
non-UTF8 bytes are escaped to keep JSON valid.

## Tests

```text
lua addons/CombatRecorder/tests/test_recorder.lua
lua addons/CombatRecorder/tests/test_addon.lua
py -3.12 -m unittest discover -s tests -p test_combat_report.py
```

Tests cover raw-before-filter capture, death and zoning behavior, no action APIs,
privacy filtering, storage failures/backoff, bounds/retention, reload collisions,
partial records, and cross-file incident reports. A live `--status` check is still
required after loading; simulated tests are not a claim of live recording.

License: MIT; see [LICENSE](LICENSE).
