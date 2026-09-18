# Coordinator and combat-consumer lab

Purpose: catch cross-profile control failures outside the game by executing
commands in their real consumer, rather than merely recording command strings.

`test_profile_consumer_lab.lua` runs six production PartyTactics coordinators
and six production PartyCombat instances. It reuses the existing coordinator
fixture through an explicit test-only export. No production addon is changed.

The reconstructed scenario activates the explicit Skomora Sortie profile,
models Tackle's opening attack and confirms all six combat consumers engage.
It captures real coordinator stop messages, activates the ordinary Locus
profile, then delivers the old Sortie messages. It checks all six consumers'
actual attack state, emitted stop effects and reported policy after advancing
time. A fresh operator stop must still disengage all six.

The `--inject-stale-stop` control deliberately leaks an unfenced old-owner OFF
command at the consumer boundary. Actual PartyCombat executes it. The same
isolation assertion must fail with `STALE_SORTIE_DISRUPTED_REPLACEMENT`.
This demonstrates sensitivity to a real consumer effect, not the cause of the
historical Sortie failure. It is not a comparison against a known-bad historical
build and does not prove arbitrary delayed command strings are fenced.

## Boundary map

| Executes production code | Simulated or omitted |
|---|---|
| Six PartyTactics coordinators, compiler/profile handling and Skomora runtime | GearSwap host, legacy helpers and controller readiness responses inherited from the coordinator fixture |
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

## Run

From the repository root with the locked tools installed:

```powershell
./tools/OfflineTests/Invoke-Checks.ps1 -Suite PartyTactics
```

The runner requires the normal scenario's success marker and the fault run's
specific injection and failure markers. An arbitrary Lua error does not count
as a successful fault control. Fengari can return zero on Lua assertion errors,
so exit code alone is not enough.

The next boundary to replace must follow evidence of a missing behavior. Do
not call this a complete game simulator or add unrelated profile fixes here.
