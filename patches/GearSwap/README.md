# GearSwap opt-in performance profiler

This patch adds measurement only to the installed GearSwap 0.940 code. It does
not change gear selection, packet construction, action timing, or user-file
logic. Profiling is disabled by default.

When enabled, it accumulates timing in memory for three layers:

- `pipeline`: the complete GearSwap equipment pipeline by event type;
- `callbacks`: named user callbacks such as `precast`, `midcast`, and
  `aftercast`; and
- `events`: normal and raw Windower events registered from GearSwap user files
  and includes, including `prerender` and `action` handlers.

No per-event file I/O occurs. One CSV per character is written only by
`report` or `stop` under:

```text
C:\Program Files (x86)\Windower\addons\GearSwap\data\performance
```

## One-time activation

Pause combat, then run this once so every client loads the modified files:

```text
//exec gearswap_perf_reload_all.txt
```

## Capture

Immediately before a representative combat capture:

```text
//exec gearswap_perf_start_all.txt
```

Run the existing 180-second frame capture and fight normally. Immediately
after it finishes:

```text
//exec gearswap_perf_stop_all.txt
```

The start timestamp in each GearSwap filename ties all six reports to the same
run. `pipeline` timings are inclusive of user callbacks; compare them with the
matching `callbacks` rows to distinguish GearSwap core work from user-file
work. Nested GearSwap events can overlap, so totals are attribution signals,
not six-client wall-clock utilization percentages.

Commands on one client are also available directly:

```text
//gs perf start
//gs perf stop
//gs perf report
//gs perf reset
//gs perf status
```

## Validation and backup

The profiler is stored in `perf-profiler.patch`. It dry-applies to the exact
backed-up GearSwap files, the applied result parses as Lua, and that result
matches the live installed files after newline normalization.

Exact pre-change files are under:

```text
C:\Users\DC03\Documents\FFXI\.codex-backups\addon-optimization-20260908\GearSwap
```

## CPU hot paths

`cpu-hot-paths.patch` contains one behavior-preserving CPU reduction measured
from the six-client GearSwap profile:

- PartyTactics maintenance uses a narrow GearSwap entry point that refreshes
  globals and invokes only the appropriate PartyStart helper. It does not run
  the generic self-command/equipment pipeline.

An attempted actor-first `0x028` filter was removed on 2026-09-09 after a live
one-spell profile proved that it suppressed `aftercast`. GearSwap's original
decoded-action and pet-resolution path remains in place.

The patch is layered on top of the locally installed GearSwap 0.940 profiler
build. Profiling remains opt-in and disabled by default.

The exact pre-hot-path GearSwap core files are backed up under
`C:\Users\DC03\Documents\FFXI\.codex-backups\performance-hotpaths-20260909\GearSwap`.
