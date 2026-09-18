# FastFollow safe-zone candidate

This directory contains an **undeployed** candidate fix for the installed
FastFollow addon. It is based on DiscipleOfEris's FastFollow 1.2.3 and retains
the local PartyOps observer and September 2026 render/IPC optimizations.

## Problem

FastFollow 1.2.2 replaced its earlier movement-based zoneline handling with
outgoing `0x05E` packet replication. The leader broadcasts the zone-line ID
and type from its own request. Every follower waits for proximity and then
injects a new request containing those fields.

A zone-line ID is specific to the source zone. The installed implementation
does not attach a source-zone generation to the request, does not cancel its
scheduled coroutine on zone change, and reads the leader position from a
separate IPC stream. Under delayed scheduling, a follower can therefore
process the old request after it has entered a different zone. At that point
the copied ID can describe another entrance. The upstream project has an open
February 2023 report of the same wrong-location behavior.

## Candidate behavior

`candidate/FastFollow.lua` never blocks, constructs, copies, or injects an
outgoing zone request. The game client remains the sole authority for choosing
the destination.

For normal physical zonelines, the leader instead sends a short-lived signal
containing:

- the source zone and exact source coordinates;
- the leader's latest movement vector;
- a wall-clock issuance time; and
- a per-load unique transition token.

A follower accepts the signal only when it follows that leader, remains in the
same source zone, is within FastFollow's normal maximum range, and receives a
fresh, non-duplicate token. It approaches the recorded point for at most three
seconds and then continues in the leader's direction for at most one second.
The follower's own natural zone request, a zone-change event, a stop/follow
command, expiry, or a newer signal cancels the nudge immediately.

This is deliberately fail-safe: a difficult door or nonphysical transition
may leave a follower at the zoneline, but FastFollow cannot choose a wrong
entrance for it.

Each client writes only transition events (not frame-loop events) to:

```text
Windower\addons\FastFollow\data\zone_trace_<character>.log
```

The trace records accept/reject/cancel reasons and should make any remaining
failure attributable without a high-frequency performance cost.

## Deployment status

Do not copy or reload this candidate while clients are actively zoning. The
planned deployment is:

1. stop FastFollow on all clients;
2. back up the exact installed source and settings;
3. copy the reviewed candidate over the installed `FastFollow.lua`;
4. reload FastFollow on all six clients together; and
5. test repeated two-way zonelines before enabling unattended following.

The current emergency mitigation is `//ffo stopall` before zonelines.

## Validation

Run:

```powershell
python -m unittest patches/FastFollow/tests/test_safe_zone.py -v
```

The test parses the candidate as Lua, proves the `0x05E` branch contains no
packet construction/injection/blocking, and checks the source-zone, age,
duplicate, injected-packet, natural-request, and zone-change guards.

## Upstream

- Source: <https://github.com/DiscipleOfEris/FastFollow>
- Current monorepo: <https://github.com/DiscipleOfEris/Windower4Addons>
- Matching open issue: <https://github.com/DiscipleOfEris/Windower4Addons/issues/5>

FastFollow is MIT licensed. The upstream license is reproduced in `LICENSE`.
