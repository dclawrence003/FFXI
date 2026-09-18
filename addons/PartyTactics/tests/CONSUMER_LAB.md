# Coordinator and combat-consumer lab

Purpose: catch cross-profile control failures outside the game by executing
commands in their real consumer, rather than merely recording command strings.

`test_profile_consumer_lab.lua` runs six production PartyTactics coordinators
and six production PartyCombat instances. Real stable hosts and five PartyStart
job helpers answer readiness probes through `readiness_clients.lua`; their
synthetic host/helper responses are disabled. It reuses the existing coordinator
fixture through an explicit test-only export. No production addon is changed.

The reconstructed scenario activates the explicit Skomora Sortie profile,
models Tackle's opening attack and confirms all six combat consumers engage.
It captures real coordinator stop messages, activates the ordinary Locus
profile, then delivers the old Sortie messages. It checks all six consumers'
actual attack state, emitted stop effects and reported policy after advancing
time. A fresh operator stop must still disengage all six.

The `--persistent-sortie` variant loads the actual `sortie-main-v1/1.2.0`
adapter through each real host. Actual controller replies replace synthetic
replies. Host ticks and typed actions execute against the same battle targets
maintained by PartyCombat. Adapters must stay active and emit combat actions,
then unload when ordinary Locus takes over. Retired adapters cannot emit more
actions during replacement combat. This variant runs both normally and with
the injected stale-stop control in the standard suite.

The `--inject-stale-stop` control deliberately leaks an unfenced old-owner OFF
command at the consumer boundary. Actual PartyCombat executes it. The same
isolation assertion must fail with `STALE_SORTIE_DISRUPTED_REPLACEMENT`.
This demonstrates sensitivity to a real consumer effect, not the cause of the
historical Sortie failure. It is not a comparison against a known-bad historical
build and does not prove arbitrary delayed command strings are fenced.

## Boundary map

| Executes production code | Simulated or omitted |
|---|---|
| Six PartyTactics coordinators, compiler/profile handling and explicit or persistent Sortie runtime | Selected Skomora encounter only; no dungeon route |
| Persistent variant: actual hosts, versioned adapter, controller replies, action handling and ticks | Fixed MP/TP, available recasts and job eligibility; cast commands recorded without server completion |
| Six stable hosts and five PartyStart job helper probe handlers | Full job ticks, helper profile setup/casting and GEO delayed boot-idle command are not executed; startup commands are recorded |
| Six PartyCombat command, IPC and combat handlers | Windower clock, command delivery and IPC transport |
| Policy changes, emitted target packets and stop commands | Immediate simulated server acknowledgement of attack packets; no retail packets sent |
| Actual ordinary Locus profile configuration | Job-file casts, equipment changes, AutoWS2, SignetKeeper, ExpeditionGuide and movement physics are not executed |

This slice proves the captured coordinator stop traffic cannot disrupt the
replacement consumers in this modeled sequence. It does not prove the full
Sortie route, persistent Sortie-to-Locus Signet integration, historical cause,
combat success, movement, live timing or loaded client versions.

An early setup assertion failed because the fixture claimed the boss before
the tank had attacked. The real runtime then correctly released only the five
damage members. The scenario now models an unclaimed target, Tackle's opening
attack, then party release. The all-six engagement assertion was retained.

The persistent integration exposed another fixture error: its target lookup
accepted selected target (`t`) but omitted battle target (`bt`). The adapter
deactivated while engagement still appeared healthy. Battle-target reads now
use PartyCombat's simulated packet state. The active-adapter and action-output
assertions remain mandatory. Command transport is modeled; native GearSwap
wait scheduling and full job support loops are not executed.

## Run

From the repository root with the locked tools installed:

```powershell
./tools/OfflineTests/Invoke-Checks.ps1 -Suite PartyTactics
```

The runner requires the normal scenario's success marker and the fault run's
specific injection and failure markers. An arbitrary Lua error does not count
as a successful fault control. Fengari can return zero on Lua assertion errors,
so exit code alone is not enough.

An additional `--drop-helper-ack` control drops the actual GEO helper's reply.
The ordinary Locus full-readiness assertion must fail specifically. Readiness
remains advisory; this does not introduce or prove a combat startup gate.

The next boundary to replace must follow evidence of a missing behavior. Do
not call this a complete game simulator or add unrelated profile fixes here.
