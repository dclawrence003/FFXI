# Architecture and extension contract

## Responsibilities

ExpeditionGuide is a generic expedition route engine with a Sortie content pack.
It owns presentation, route state, navigation hints, and read-only party
evidence. It does not own combat, equipment, movement, or external service
configuration.

```text
ExpeditionGuide route/HUD
        |
        | semantic, allowlisted profile key (explicit operator request)
        v
PartyTactics combat profile
        |
        | typed adapter requests
        v
PartyCombat / AutoWS2 / HealBot / Roller2 / other services

GearSwap remains the independent and sole equipment owner.
```

There is no PartyStart dependency. The sensor IPC is report-only; no message
received from a follower can request an action.

## Isolation rules

1. Add new behavior as a new route or content module. Do not edit an existing
   route merely to reuse it for a different objective or party plan.
2. Treat `content/registry.lua` as the authoritative pack catalog. Add one
   declaration only when adding a new expedition pack; do not mutate an
   existing declaration to install a route or profile. Those files are
   directory-discovered. Existing pack IDs, route IDs, and aliases are stable
   public interfaces.
3. Keep both `items.ordered` and `key_items.ordered` append-only within a
   catalog revision. Their positions are pack-bound version-2 bitmap contracts;
   reordering breaks evidence interpretation.
4. A route may reference only declared landmark IDs, supported evidence kinds,
   and semantic combat keys in its content pack.
5. A route can never contain `command`, `raw_command`, `windower_command`, or
   `send_command`. Schema validation quarantines it if it tries.
6. Load and validate each route independently. A malformed new route is
   quarantined; valid previous routes remain available.
7. A planned combat descriptor stays `available=false` forever. After its
   canonical PartyTactics implementation passes the complete regression suite
   and encounter-specific tests, add a new versioned descriptor key and a new
   operational route that references it. Never turn an old guide route live by
   mutating the descriptor underneath it.
8. Never equip from the guide. Naked, weapon-mode, instrument, ranged/ammo, and
   defensive-set requirements belong to explicit GearSwap modes or existing
   job logic.
9. Never bind keys from the guide. `Ctrl-P` and `Alt-P` remain universal combat
   controls owned elsewhere.
10. Never infer the party's permanent progress from Dolo alone. Require the
    all-six intersection for progression routes. Entry additionally requires
    the exact configured p0-p5 party, no attached alliance, and authoritative
    Dolo-local party-leader proof until the instance transition completes.

## Content layout

Each expedition gets a separate pack:

```text
content/<pack>/
  items.lua             stable sensor item catalog
  key_items.lua         stable permanent key-item catalog
  landmarks.lua         named entities and navigation anchors
  objectives.lua        validated objective facts and reward contracts
  profiles/*.lua        one semantic -> canonical PartyTactics ID per file
  routes/*.lua          small, versioned route plans
```

The registry supplies each pack's ID, catalog modules, guide-zone set,
instance-zone subset, run duration, and stale-run duration. The loader rejects
duplicate pack IDs and computes an exact catalog ID from the ordered temporary
and key-item contracts. It then enumerates `profiles/*.lua` and `routes/*.lua`,
binds identity to the file path, and executes each declarative table in a
restricted, bounded sandbox
with no Windower, `require`, I/O, OS, debug, package, or mutable standard-library
access. It rejects non-plain data, validates each result, and quarantines
failures at file scope. A lexically earlier imposter cannot claim a prior route
or profile identity. Frozen seed declarations establish the original identities
and shortcuts; production additions never edit them.

A route may declare route-local landmarks. The loader merges those into a
private copy of the frozen pack landmarks for that route only; overrides are
rejected. A route must name its owning pack and may use only that pack's allowed
zones and evidence catalogs. Calibration state is also namespaced by route, so
adding a waypoint cannot alter another route's navigation. Published route
content and the pack dependencies it actually consumes are fingerprinted, and
saved state resumes only when ID, semantic version, and fingerprint all match.

Generic code under `lib/` must not know Sortie enemy names, objective rules, or
map layout. Odyssey should add `content/odyssey/...`, not conditionals scattered
through the Sortie pack or route engine. If a genuinely generic capability is
missing, add it to the schema and engine with backward-compatible tests before
using it in either pack.

Recommended Sortie route granularity:

- first-entry/core traversal unlocks;
- Sheet D/Demisang objective;
- one route per boss encounter and recovery path;
- bounded farming segments;
- full-run compositions that reference proven segments without copying their
  combat implementation.

## Evidence model

Route completion evidence must have an explicit source and confidence:

- `sensor_quorum`: all expected clients have fresh, ready, same-zone reports;
- `all_in_pack`: all expected clients have fresh reports from an actual
  instance zone for the active pack, with exact-party and Dolo-leader proof;
- `all_temp_item`: the required bit is present in all six fresh same-zone
  reports;
- `all_temp_items`: every listed bit is present in all six fresh same-zone
  reports;
- `interaction` or `landmark`: useful observations, not universal proof of a
  hidden objective;
- `manual`: operator-confirmed condition that the safe client API cannot prove.

The engine persists resolution and confidence in step history. Route authors
must not label position, target proximity, or a menu opening as proof that a
hidden objective succeeded. Where proof is unavailable, show the uncertainty
and require an explicit operator decision.

## Sensor protocol and pack isolation

Every client reads the Windower APIs once per sensor interval into a neutral
snapshot. The runtime then projects that immutable snapshot into one report per
installed pack, using only that pack's temporary-item and key-item catalogs.
The production protocol accepts only the action-free `EG|2|STATE` envelope. It
contains pack ID, catalog ID, sender, main/subjob facts, location/status,
readiness, exact-party proof, Dolo-local leadership proof, and both bitmaps.

The receiver validates the pack and exact catalog before dispatching the report
to that pack's independent `PartyState`. Same-length catalogs cannot collide,
and a report for an inactive pack remains passive evidence only. Jobs are
reported as strict FFXI tokens but generic sensor/state code applies no job
policy; a route-local composition contract may consume those facts later.

`allowed_zones` can include guide/preflight/postflight areas. Only
`instance_zones` may satisfy `all_in_pack`, start or preserve a run timer,
enable interaction evidence, calibrate a live waypoint, or drive live
navigation. For Sortie the instance layers are Outer Ra'Kaznar [U1], [U2], and
[U3] (zones 275, 133, and 189); Kamihr and Leafallia are guide zones only.

## Combat and route-action bridges

Live routes refer to installed profile descriptors by semantic key. The
combat bridge permits only:

```text
lua i PartyTactics use <canonical-id> [armed]
```

where `<canonical-id>` passes a strict identifier check and came from the static
catalog. Raw commands in route data are rejected. Automatic reconciliation has
only three structural conditions: Dolo is the guide leader, the live route is
active, and Dolo is in an allowed instance zone. It deliberately does not
treat idle state, sensor quorum, encounter state, ACKs, checks, buffs, or
controller status as permission gates. Each desired profile/arm state is sent
once, so a later Alt-P/manual disarm is not fought by a polling loop.

`//exg profile` is recovery-only. It validates the same allowlist, repeats the
current desired canonical operation, and prints that operation to the user.

Route actions use a second typed bridge. Sortie content can declare only the
semantic operations `device_a`, `device_c`, and `port`, which map to the exact
Superwarp commands `sw so p a`, `sw so p c`, and `sw so p port`. The bridge
uses the same leader/route/zone structural conditions and one-shot token
semantics. Superwarp—not ExpeditionGuide—owns proximity validation, party
confirmation, and its bounded retry behavior. Route data cannot supply a raw
service-addon command.

Emergency stop is intentionally separate and unconditional:

```text
lua i PartyTactics off
```

The guide must never send `pc on`, `pc force`, direct GearSwap commands, weapon
skills, spells, movements, target changes, or arbitrary service-addon commands.

## State and migrations

Leader state records the route ID, route version, and dependency fingerprint. A
changed route, referenced landmark, objective, item, or combat descriptor is not
blindly restored into an incompatible step layout. Runtime state writes use a
temporary file and a backup, and only the leader writes route progress. Sensor
clients maintain only their normal per-character settings. Primary, transient
recovery, and backup state are all bounded and semantically validated before
route state or waypoint calibration can be restored.

Any future schema migration must be explicit, deterministic, and covered by a
fixture for the prior version. Never make a new route depend on editing another
route's saved state.

## Verification gate for every addition

Before a route or profile is exposed as operational:

1. Parse every Lua module.
2. Validate every route independently and verify a bad new fixture is
   quarantined without hiding prior routes.
3. Run route-engine, sensor-protocol, navigation, persistence, and bridge tests.
4. Re-run the complete PartyTactics regression suite when a combat profile or
   bridge-visible status changes.
5. Verify the PartyTactics tree hash when the change was intended to be guide
   only.
6. Dry-load on Dolo outside combat; confirm no target, equipment, key, or
   external-addon change.
7. Add followers one at a time and verify the six-client quorum.
8. Live-test the smallest safe objective before composing it into a larger run.
9. Review PartyOps output and update only the isolated route/profile that owns
   the observed problem.

## Odyssey reuse

Odyssey should reuse the generic HUD, state machine, version-2 sensor envelope,
passive multi-pack projection, and confidence semantics. It will define its own
pack declaration, catalogs, zone sets, duration, map graph, objectives,
encounter catalog, and routes. Sortie route IDs, item bits, timers, and
hidden-objective assumptions must not be used as Odyssey defaults.

The expected progression is the same: guide-only pack first, live-calibrated
navigation second, isolated automated encounters third, and optimized composite
runs only after the pieces are individually proven.
