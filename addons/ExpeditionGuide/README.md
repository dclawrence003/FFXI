# ExpeditionGuide

ExpeditionGuide is the route and evidence layer for six-character expedition
content. Sortie is the first content pack. The addon shows Dolomedes a
step-by-step HUD, points toward known landmarks, and gathers read-only state
from all six Windower clients.

## Current status: the evolving main run

The production route is `sortie-main-run` (aliases `run`, `mainrun`, and
`therun`). It is the default and auto-starts: C burst objectives and Skomora,
then B weapon-skill credit and Leshonn, then A magic kills and Ghatjot. The old
two-boss route remains available only as a historical fallback.

After entry, ExpeditionGuide loads and arms `sortie-main-v1` once. That one
profile remains active through travel, objectives, bosses, and improvised
trash; changing targets selects only an internal fight recipe and never loads,
reapplies, disarms, or replaces a profile. Any configured party member's
hostile action can bind the exact target and emits one party synchronization
edge. Tackleberry remains the preferred first-threat puller, but is never a
permission gate. Normal play requires no `//pt`, `//pc`, `//exg profile`, arm,
force, or Ctrl-P command.

The C camp is the Skeleton/Ghoul pack beside Gadget C, not the Corse room. B
uses five nearby Biune elementals, guaranteeing at least one packet-confirmed
weapon skill before each kill. A uses the northwest Acuex pack: all six burn
for TP, Tackleberry uses Flat Blade, Smalls closes Red Lotus Blade for
Liquefaction, then Smalls casts Fire IV plus Fire III under maintained
Aquaveil. Misses, broken chains, and low-HP holds recover automatically.

Leshonn uses a common-denominator safe mode for either random hand form.
Selecting him stages no-debuff BRD/RDM support and disables automated PLD
Flash/Sentinel without starting combat. Put Tackleberry alone in front and the
other five behind or on a rear flank, then engage with Tackleberry. Kick keeps
melee and Box Step but holds WS; Savage Blade and Black Halo are the automatic
lanes. Positioning is an instruction, never an automation gate.

Device C/B/A transfers and Gadget entries/exits wait until the correct object
family is actually within interaction range, then issue the allowlisted party
warp. A failed request retries every 12 seconds while the step remains current;
Gadget steps advance only after a real large relocation. The RestedXP-style instruction window explains objective, reason,
success evidence, automation, and next action on five short lines. A separate
32-direction gold arrow follows corridor points instead of aiming through
walls. It is currently disabled at the restored 180-pixel size while the
provisional B corridor trace is calibrated; `//exg arrow on` explicitly enables
it when wanted.

ExpeditionGuide cannot safely confirm Sortie entry, choose the next monster,
steer Dolo through the world, open doors, or open reward chests. Those remain
the current human actions. Every warning is advisory, manual input always
passes through, and `//exg next`, `//exg skip`, and Alt-P remain immediate
overrides. See [Sortie main-run workflow](docs/SORTIE_MAIN_RUN.md).

Progression is always evaluated from the all-six intersection. A current route
item or unlock is never inferred from Dolomedes alone.

## Ownership boundaries

ExpeditionGuide has one job: guide the route and evaluate evidence.

- GearSwap remains the sole equipment owner. ExpeditionGuide never equips,
  locks, or swaps anything, including the naked Bitzer A requirement.
- PartyTactics remains the combat orchestrator. ExpeditionGuide contains no
  fight implementation and does not use PartyStart.
- The main route names one persistent combat profile on every post-entry step.
  ExpeditionGuide emits that desired state once. Route advancement cannot
  stop, reload, reapply, or replace it; target identity selects only an
  internal recipe.
- Automatic route actions are limited to typed Superwarp operations declared
  by the route. The main run permits only Device C, Device B, Device A, and the
  current Gadget port; Superwarp retains proximity and party validation.
- The separate outbound safety action is `//exg stop`, which sends
  `PartyTactics off` and pauses the route.
- Existing controls are not rebound or intercepted. Alt-P remains the universal
  emergency stop; Ctrl-P is a recovery control, not part of the normal run.
- FastFollow, EasyFarm, HealBot, Roller2, AutoWS2, GearSwap, and character job
  files are not configured or controlled by this addon.

Combat and route integration are one way and allowlisted. ExpeditionGuide owns
route evidence and typed warps; PartyTactics owns exact-target combat. Neither
turns a diagnostic result into a permission gate.

## First-entry prerequisite for this party

Before any live onboarding attempt, check every character individually:

1. Complete the Seekers of Adoulin mission **The Light Within**.
2. Possess **Scintillating Rhapsody**, obtained by completing the Rhapsodies of
   Vana'diel mission **The Orb's Radiance**.
3. Speak to Ruspix in Leafallia and obtain a **Shiny Ra'Kaznarian plate**.
   Tackleberry, Kickpuncher, Barneystinson, Smalls, and Achoo must do this for
   the first time; verify Dolomedes has a charged Shiny plate as well.
4. Gather all six at the Diaphanous Transposer near Kamihr Drifts Bivouac #4.
   Every party member needs a Shiny plate for the party to enter.
5. Bring Silent Oils, Prism Powders, Reraise, food, and inventory space.

After the first completed foray, check `//exg status`. If it already reports
`Ruspix's plate 6/6`, skip the postflight route: there is nothing to reclaim.
Otherwise, keep the exact party together, start `sortie-postflight-ruspix`,
and take all six to Leafallia. Tackleberry,
Kickpuncher, Barneystinson, Smalls, and Achoo each speak to Ruspix for
**Ruspix's plate**; Dolomedes also speaks unless his own key-item list confirms
that he already holds it. This is not an entry prerequisite for that first run.
A Sortie entry converts each Shiny
plate to a Dull plate and starts its 20-hour recharge.

`//exg status` classifies each fresh, same-zone party member as `Shiny`, `Dull`,
or `missing`. Contradictory possession is `INVALID`; a client without trusted
current evidence is `unknown`. Dull is diagnostic only: it does not reveal the
remaining recharge time, and even a fully charged plate remains Dull until the
character approaches the transposer.

## Client model

Load ExpeditionGuide on all six clients when testing party sensing:

| Character | Role in ExpeditionGuide |
| --- | --- |
| Dolomedes | Route leader, HUD, state writer, local sensor |
| Tackleberry | Read-only sensor |
| Kickpuncher | Read-only sensor |
| Barneystinson | Read-only sensor |
| Smalls | Read-only sensor |
| Achoo | Read-only sensor |

Only Dolomedes draws the HUD or accepts route-changing commands. Every client
takes one neutral snapshot, then emits a deterministic read-only report for
each installed expedition pack. The version-2 envelope includes the exact pack
and catalog identity, current jobs, zone, position, idle/combat status,
exact-party evidence, key items, and that pack's temporary items. A Sortie
bitmap therefore cannot be decoded as Odyssey evidence. No follower command is
encoded in the protocol.

A report is fresh for eight seconds by default. All six reports must prove the
exact configured p0-p5 party with no attached alliance. Only Dolo's own report
authoritatively compares his player ID with `party1_leader`; followers do not
need a distant Dolo mob record. While inside Sortie, reward steps use a
stricter, memory-only proof. The HUD shows `CHEST READY: 6/6 stable 2/2` only
after two distinct full-party sensor cycles at least 0.5 seconds apart prove
the exact route, step, run identity, party, Dolo leadership, current entry
nonces, fresh timestamps, and an approved reward region. Any failed invariant
changes that advisory line to `CHEST RISK` or `CHEST CHECK` and names affected
characters when available. On an in-instance step with no declared reward it
says no route reward is declared; outside the instance the check is not applicable. Dolo
alone opens spawned chests; simultaneous chest interactions can cause a
character to miss a temporary-item reward.

This indicator is advisory. ExpeditionGuide does not target or open a chest,
block an interaction or packet, or retain an authorization in saved state.
Every route, step, pause/resume, resync, relocation, zone, and run-context
change clears the in-memory proof. Dolo still makes the final decision after
visually confirming the named reward and party position.

The same full guard remains live after the pre-entry step advances. If a member
leaves, an alliance is attached, leadership changes, a report goes stale, or a
Shiny plate disappears before the zone transition, the `enter` step displays
an `ENTRY CHECK` with the affected evidence instead of trusting the earlier
observation. It never intercepts the operator's entry action.

## Safe installation and canary

The source directory is:

```text
C:\Users\DC03\Documents\FFXI\addons\ExpeditionGuide
```

The live Windower directory is normally:

```text
C:\Program Files (x86)\Windower\addons\ExpeditionGuide
```

Copy the complete addon directory to the live location. Do **not** add it to
`init.txt`, an automatic load list, or a character login script during the
canary. Installation alone must not issue a Windower command. ExpeditionGuide
also requires no key bind.

Test Dolomedes first, while outside combat and outside Sortie:

```text
//lua load ExpeditionGuide
//exg status
//exg list
//exg start mainrun
//exg explain
```

Expected result: Dolomedes gets the HUD, `status` says `leader`, the new route
says `LIVE`, and sensors remain `1/6`. Outside Sortie, starting the route does
not dispatch its combat or warp lifecycle. Once the active leader enters an
allowed Sortie zone, the persistent profile and proximity-aware route requests begin. No request
changes FastFollow, selects a target, moves a character, or equips an item.

If the canary is clean, load the five follower clients one at a time. After the
sixth fresh report, Dolomedes should show `SENSORS 6/6`. The supplied scripts
in `scripts/` are optional operator-invoked command files; nothing runs them
automatically. See [Canary installation](docs/CANARY_INSTALL.md) for the exact
staged procedure and rollback.

After deploying a main-run update, reload the addons only while out of combat:

```text
//exec sortie_reload.txt
```

It reloads only ExpeditionGuide and PartyTactics across all six clients, in
dependency order. It does not issue a global combat stop and does not reload
GearSwap or PartyCombat. The saved route migrates to `mainrun`; `//exg start
mainrun` is available when an explicit fresh start is wanted. Target-owned
combat and route warps begin automatically after entry.

## Guide window and floating arrow

Only Dolo renders two separate overlays. The instruction window shows:

- a large route header, progress bar, area, run timer, and route state;
- a prominent `DO THIS NOW` instruction with detailed step notes;
- current corridor point, distance, turn cue, warnings, combat state, observed
  evidence, next instruction, and sensor status.

The separate 32-direction gold arrow rotates relative to Dolo's facing when
explicitly enabled. A route advances it through captured corridor turns and room centers,
so it points along the walked route rather than straight through several walls.
It is still a display—not movement or navmesh automation. Use the real corridor
when geometry disagrees and `//exg wp` to skip one bad point. Static
Device/Bitzer locations begin as medium-confidence landing anchors; matching
live entities replace them with current coordinates.

## Commands

Commands may use `//exg` or `//expeditionguide`. The former `//eg` alias is
intentionally unsupported because it conflicts with EventGuard.

| Command | Effect |
| --- | --- |
| `//exg status` | Show version, leader/sensor role, route, step, sensor count, zone, key-item counts, and named Shiny/Dull/missing diagnostics. |
| `//exg list` | List independently validated routes and their guide-only status. |
| `//exg start onboarding` | Reset and start the core onboarding guide. Aliases: `unlocks`, `core`. |
| `//exg start sortie-onboarding-core-live` | Reset and start the corrected additive live-canary core route. Use this exact ID rather than resuming the preserved guide-only route; it does not load or arm combat. |
| `//exg start sortie-key-b-recovery-live` | Start the focused seven-step recovery route when Key B alone was missed; it guides the corrected B1-B6 sequence without replaying C/D. |
| `//exg start dclear` | Historical direct Device-D / full-Demisang / Sheet-D route. Full ID: `sortie-sheet-d-demisang-live`. The current party has completed this unlock. |
| `//exg start mainrun` | Reset to the evolving C > B > A run: Skomora, Leshonn, and Ghatjot. This is normally unnecessary because the route is the default and auto-starts. Full ID: `sortie-main-run`; aliases: `run`, `mainrun`, `therun`. |
| `//exg start boss2` | Historical C > A two-boss fallback. Full ID: `sortie-two-boss-c-a-training`; aliases: `twoboss`, `ca`. |
| `//exg start sortie-key-b-sheet-d-canary-live` | Historical combined recovery route, now repaired with turn-by-turn B navigation and exact gate-click advancement. |
| `//exg start sheetd` | Reset and start the preserved historical Sheet D dry guide. |
| `//exg start sortie-postflight-ruspix` | Start the separate all-six Ruspix's plate claim guide in Leafallia. |
| `//exg steps` | List every step ID without changing route state. Alias: `outline`. |
| `//exg explain [number\|id]` | Print any step's full instruction, warning, details, and required evidence without moving the route. With no argument, explain the current step. Alias: `why`. |
| `//exg next` | Advance the current step immediately by operator decision. When sensor evidence is absent it records an override rather than refusing. |
| `//exg back` | Return one step and clear that step's completion. |
| `//exg skip` | Deliberately override the current step and record a manual skip. Use only when the HUD evidence is wrong and the operator has verified reality. |
| `//exg wp` | Advance only the floating arrow to the next corridor/room point without changing the guide step. Alias: `waypoint`. |
| `//exg pause` | Pause route advancement. |
| `//exg resume` | Resume the active route and clear recovery-required state. |
| `//exg resync` | Discard cached peer reports and wait for fresh sensor reports. It does not change any game item. |
| `//exg time MM:SS` | Correct the displayed one-hour run timer, from `00:00` through `60:00`. |
| `//exg timer reset` | Clear the current step's attempt-based interaction timer so its next valid interaction can restart it. |
| `//exg mark [landmark]` | Calibrate the current or named landmark to Dolo's present position. Alias: `calibrate`. |
| `//exg profile` | Explicit recovery only: repeat the current step's exact canonical PartyTactics request. The main run should never require this. Alias: `combat`. |
| `//exg show` / `//exg hide` | Show or hide Dolo's HUD. |
| `//exg pos X Y` | Move the HUD and save its position. The HUD is also draggable. |
| `//exg arrow on\|off` | Show or hide Dolo's separate navigation arrow. |
| `//exg arrowpos X Y` | Disable auto-centering and move the navigation arrow to a saved screen position. |
| `//exg stop` | Send `PartyTactics off` and pause the route. Alias: `panic`. |
| `//exg reset confirm` | Reset the current route to step 1. The confirmation word is required. |
| `//exg debug [on|off]` | Toggle diagnostic chat output. |

Route-changing commands are leader-only. Running them on a follower prints a
sensor-role warning and changes nothing.

## Evidence and confidence

The guide distinguishes proof from navigation hints:

- **Confirmed party evidence:** all six fresh sensor clients form the exact
  configured, alliance-free party in one zone; Dolo locally proves leadership;
  and all six report the required key or temporary item when applicable.
- **Observed evidence:** Dolo reaches a waypoint or the addon sees a relevant
  menu. This can support navigation but does not prove a hidden objective.
- **Manual evidence:** the operator explicitly advances or skips a step after
  checking the game state.
- **Static navigation:** cached source coordinates or warp landing anchors.
- **Live calibration:** a matching current-zone entity or Dolo's explicit
  `//exg mark`; this is stronger for bearing but still not proof of an objective.

Automatic item steps advance after all-six confirmation, and the B repair
advances after Dolo interacts with the exact gate for the current step. Manual
steps never advance merely because the arrow says Dolo arrived. `//exg next`
and `//exg skip` always remain operator overrides and never manufacture sensor
proof for a missing party reward.

The local cached BGWiki Sortie category is the canonical objective source.
Temporary-item IDs and entity/menu metadata were cross-checked against local
Windower resources and installed map data. Canonical objectives and IDs are
treated as high confidence; community walking order and static landing anchors
are medium confidence; corridor turns, exact kill radii, and mixed-progression
edge cases require live calibration. The complete source record and map links
are in [Sortie content provenance](content/sortie/research.md).

## Persistence and recovery

Dolomedes stores route state and calibrated waypoints in:

```text
Windower\addons\ExpeditionGuide\data\state_Dolomedes.lua
```

Writes use a temporary file and retain `state_Dolomedes.lua.bak`; a transient
`.previous` copy protects recovery if replacement is interrupted. Startup
validates primary, `.previous`, and backup data before accepting any of them.
Per-character settings are stored in `data/settings_<Character>.xml`. Runtime
`data/` files must not be copied back into source control as route definitions.

Leaving or changing the Sortie instance clears its run binding and marks
recovery required; the visual route and manual controls remain usable. A saved
run older than two hours reloads paused. Review the current step with
`//exg explain`, use `//exg back` if necessary, then `//exg resume`. If peer state
looks stale, use `//exg resync` and wait for `6/6`. If route state itself is no
longer trustworthy, use `//exg reset confirm` and begin from the pre-entry audit.

For any immediate combat problem, use the existing `Alt-P` universal stop.
`//exg stop` is a second explicit path that also pauses the guide. Unloading
ExpeditionGuide removes only its HUD and sensors; it does not unload or
reconfigure any combat or equipment addon.

## Route packs and future work

The content model is additive:

```text
content/
  registry.lua
  sortie/
    items.lua
    key_items.lua
    landmarks.lua
    objectives.lua
    profiles/
      one_immutable_descriptor_per_profile.lua
    routes/
      onboarding_core.lua
      onboarding_sheet_d.lua
      sheet_d_demisang_live.lua
      postflight_ruspix.lua
```

The registry is authoritative only for pack metadata: pack ID, catalog modules,
allowed guide zones, actual instance zones, and run durations. Adding a new
pack requires one new declaration; existing pack declarations are stable.
Routes and profiles inside a pack are directory-discovered, then loaded and
validated independently, so adding either never edits the registry. Duplicate
pack or route IDs, a route claiming another pack, and invalid new modules are
quarantined instead of hiding or mutating established content.

Both `items.ordered` and `key_items.ordered` are catalog contracts. Their
pack-specific digest is carried in every IPC report and in route dependency
fingerprints. Extend an existing catalog append-only and deliberately revise
its catalog revision when changing its meaning; never silently reorder it.
Route IDs, step IDs, aliases, profile keys, and canonical IDs are likewise
stable contracts.

Sortie work is split into small modules: onboarding objectives, individual
ground-floor and basement bosses, traversal/farm segments, and then optimized
full-run plans. The C-Device, Cachaemic-burst, and regular-Demisang profiles are isolated
offline-tested live canaries; their observations revise only their v1 profiles
or additive route successors.
Main-run combat is target-started and movement remains the operator's job. The
new B corridor trace and any disputed multi-location camp should be refined
from live evidence without making the guide a blocker.

Odyssey will be a separate content pack using the same engine, with its own
catalogs, zones, duration, landmarks, objectives, routes, and PartyTactics
allowlist. The version-2 pack/catalog boundary and passive multi-pack sensing
are already in place; adding Odyssey content must not require a Sortie branch
in the generic route engine or active-route runtime.
The read-only `tools/analyze_sortie_run.mjs` post-run analyzer correlates the
last Sortie window with actions, healing, MP pressure, incoming targets, and
Dolo's simplified movement trace. It never writes to or stops PartyOps.

## Attribution and license

The addon carries the BSD 3-Clause terms in `LICENSE`.  Its game-mechanics
references and research remain credited in the content documentation.
Windower, PartyTactics and PartyOps are separate dependencies; their authors
retain their own work and have not endorsed this addon.

For the full operator sequence, see [Sortie operator runbook](docs/OPERATOR_RUNBOOK.md).
For engineering boundaries and extension rules, see
[Architecture](docs/ARCHITECTURE.md).
