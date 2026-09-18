# FFXI addon hot-path profiler

This diagnostic layer measures BattleMod, HealBot, PartyTactics, React, and the
existing GearSwap profiler during the same six-client combat capture. It does
not change addon decisions, filtering, rendering, graphics, or game quality.

The new hooks are dormant unless `perf start` is issued. While running, each
addon keeps aggregate counters, synchronized one-second buckets for up to 15
minutes, and at most 256 slow samples in memory. `perf stop` disables timing
before writing CSV files beneath that addon's `data/performance` directory.

## One-time activation after installing or changing hooks

Pause combat, then run this in the Windower console:

```text
exec reload_addon_hotpath_profilers_safe
```

The script stops PartyTactics and reloads BattleMod, HealBot, React, and
PartyTactics one client at a time. It deliberately leaves PartyTactics inert;
select and arm the desired profile normally afterward.

## Capture order

1. Start normal combat and verify all six characters are participating.
2. In the Windower console, run `exec addon_hotpath_perf_start_all`.
3. Immediately run `capture-ffxi-combat.cmd` from
   `C:\Users\DC03\Documents\FFXI\tools\performance`.
4. Fight normally for the full 180 seconds without tabbing through clients.
5. After the capture window reports completion, run
   `exec addon_hotpath_perf_stop_all` in the Windower console.

The absolute timestamps in the addon reports allow their slow callbacks to be
matched against the PresentMon and system-telemetry seconds even though the
profilers start a few seconds before the external capture.

To summarize the newest addon report set:

```powershell
python C:\Users\DC03\Documents\FFXI\tools\performance\analyze_addon_hotpaths.py
```

GearSwap retains its separate report format and can still be summarized with
`analyze_gearswap_perf.py`.
