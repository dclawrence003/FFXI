# Offline coverage

All 15 public addon folders have a central entry through `Invoke-Checks.ps1`.
This means repeatable execution of the listed checks, not complete addon or
gameplay coverage. Use `-Suite <name>` while editing. The default runs every
configured suite; GitHub uses the same entry.

| Suite | Executed behavior | Important boundary |
|---|---|---|
| PartyTactics | Profiles/runtimes, host/puller, six coordinator/consumer transition, real host and helper probes | Controller readiness and server responses still simulated; full job behavior omitted |
| PartyCombat | Existing real combat runtime and source guards | Simulated targets, packets and client |
| PartyStart | BRD reaction and RDM target/silence runtimes, source guards | Installed GearSwap parser test excluded; full job files omitted |
| AutoWS2 | Real addon smoke/aftermath behavior, reserve model and source guards | Model and mock client cannot establish real timing; no PartyOps hook in this source |
| LocusPuller | Runtime, unload and source guards | Simulated targeting and resources |
| SignetKeeper | Runtime and source guards | Simulated status/recasts; not connected to six-client consumer lab |
| JubileeKeeper | Runtime and source guards | Simulated game responses |
| ExpeditionGuide | Main runtime, Sortie route scenarios and guards | Actual movement and battlefield behavior absent |
| CombatRecorder | Storage failure/rotation and passive addon runtime | In-memory storage/client; does not replace PartyOps |
| LimbusTracker | Acquisition, duplicate/balance ordering, persistence and sync | In-memory files, packets and HTTP |
| THHUD | State/protocol cases and addon runtime | Mock display, resources and packets |
| Roller2 | Decision module | Full addon, casts and PartyOps hook not exercised |
| SalvageCells | Eleven source guards | No actual runtime fixture yet |
| EventGuard | Actual menu observation, stale-zone refusal, exact cancellation | Packet encoding/injection simulated; local-status repair only checks confirmation guard |

FastFollow executes the candidate movement boundary and a dropped-stop control.
InventoryCore, CoreManager, ReleasePackage and IncidentMemory retain their
existing separate checks. Other patch directories do not yet have full runtime
tests against an exact upstream version. They are not silently counted as covered.

`additional_suites.py` runs existing Lua tests in separate processes and requires
a completion marker after normal return, since Fengari may exit zero on an
assertion error. Python collection includes unittest classes and plain test
functions and rejects zero collected cases. No new Python dependency is needed.
The two older recorder/tracker fixtures support both Lua 5.1 environment loading
and Fengari's Lua 5.3 environment argument; production addons are unchanged.

Designed and directed by Don Lawrence, with integration code developed using
OpenAI Codex. Original addon author and license notices remain authoritative.
