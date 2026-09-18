# THHUD

THHUD is a passive, packet-native Treasure Hunter display for Windower 4. It
shows the best known TH value on the currently selected enemy as a tiny two-line
HUD. During normal play the entire HUD is absent unless that enemy has a known,
actively tracked TH value:

```text
TH
8
```

It is job-agnostic. Main THF, `/THF`, Treasure Hunter equipment worn on any
job, decoded TH augments, Bounty Shot upgrades, and any other server-confirmed
603/608 proc all feed the same per-enemy state.

This repository copy is self-contained under `addons/THHUD`. It has **not** been
installed into the live Windower directory.

## Accuracy model

FFXI does not announce initial Treasure Hunter application. THHUD therefore
uses two confidence levels:

- **Bright gold** — the server explicitly reported the value in action message
  603 or 608.
- **Cyan/blue-white** — inferred from a monitored local character's traits and
  equipment at the qualifying hostile action.
- **No HUD** — no defensible TH observation exists for the selected enemy.

The inferred calculation reads the acting client's current main/sub jobs, all
16 equipped slots, static `Treasure Hunter +N` item descriptions, and extdata
augments. It applies the retail base caps: TH8 for main THF and TH4 for other
main jobs. BLU's full three-spell TH trait combination is included when actually
set, but BLU is only one optional evidence source and is never a prerequisite
or mode.

Weapon skills and job abilities use the equipment snapshot committed with the
outgoing action. Spells and ranged attacks use a short equipment timeline so
midcast/midshot TH gear is captured instead of precast/preshot or restored
aftercast gear. Melee rounds use the set immediately preceding their result.
Outgoing equipment packets account for GearSwap changes that have not yet
appeared in local inventory memory.

Higher inferred applications raise the displayed value; lower applications
never reduce it. A server-confirmed value corrects an inferred estimate. Once a
value is server-confirmed, duplicate/lower confirmed messages cannot lower it.

## Multi-client behavior

Every monitored client broadcasts its own local inferred applications through
a `THHUD|1|...` IPC namespace. Receivers validate:

- the configured sender roster;
- current zone;
- timestamp freshness;
- field types and bounds;
- the live enemy's server ID, index, name hash, and spawn type signature.

State is keyed by server ID, not name, so same-name enemies remain independent.
Switching targets preserves each live enemy's value. A new client sends a
handshake and loaded peers reply with still-live observations, which normally
restores state after an addon reload.

THHUD clears state on death messages, despawn animation packets, passive HP
regeneration/full reset, logout, and zone change. It never injects gameplay
packets, never performs actions, and does not read the chat log or depend on
Battlemod.

## Commands

```text
//thhud show
//thhud hide
//thhud config [on|off]
//thhud pos <x> <y>
//thhud scale <0.5-3.0>
//thhud opacity <0-255>
//thhud reset
//thhud debug [on|off]
```

Settings are isolated per character as `data/settings_<Character>.xml`, so all
six clients can use different positions, scale, and opacity without overwriting
one another. `settings_example.xml` documents the generated structure; runtime
files under `data/` remain intentionally ignored by source control.

`//thhud config on` temporarily shows a gold `TH 8` preview even when no target
has tracked TH. Drag the frame to the desired position, then run
`//thhud config off` to save that character's position and restore normal
TH-only visibility. `//thhud config` by itself toggles the mode; `place` and
`placement` are aliases.

`debug` is session-only. It prints the local calculated value, trait/gear
breakdown, packet transitions, and rejected THHUD IPC messages. Normal operation
is silent.

## Treasure Hound and resource overrides

Windower exposes Signet but not whether the Treasure Hound Super Kupower is
currently active. THHUD will not silently guess it. When it is known to apply,
set this in that character's generated settings file and reload the addon:

```xml
<treasure_hound>true</treasure_hound>
```

This adds TH1 after the normal base cap, allowing an opening TH9 on a capped
main THF. `manual_equipment_bonus` is also available for a newly introduced
item whose description/augment is not yet present in local Windower resources;
it defaults to zero and is subject to the normal base cap.

## Honest unknown cases

- If THHUD loads halfway through a fight and no loaded peer has tracked state,
  it stays hidden until a monitored application or authoritative upgrade is
  observed. Guessing from the current target would be misleading.
- If an unmonitored outsider applied a higher initial TH value, clients cannot
  infer that person's equipment. THHUD remains at the best defensible value
  until a 603/608 packet establishes the server value.
- A same-zone, same-index, same-name respawn is inherently indistinguishable
  from its prior instance if a client somehow misses *all* death, despawn, and
  reset packets. Fresh IPC windows plus three independent lifecycle paths make
  that failure narrow, but a passive client cannot manufacture a server spawn
  serial that Windower does not expose.
- TH procs on weapon skills can occur without a displayed server message in
  retail FFXI. THHUD cannot label those hidden increases as confirmed.

## Tests

The pure transition harness covers target changes, duplicate names, initial
applications, higher and lower peer applications, both authoritative proc
messages, deaths, passive resets, despawns, zoning, recycled IDs, and reload
recovery:

```text
lua addons/THHUD/tests/run.lua
```

The runtime harness executes the actual addon against mocked Windower packet,
IPC, HUD, inventory, and target APIs:

```text
lua addons/THHUD/tests/runtime_harness.lua
```

Both harnesses are read-only and do not touch a live client.

## Visual asset

`assets/thhud_frame.png` is the native 112×82 runtime texture.
`assets/thhud_frame@2x.png` is the 224×164 source-sized derivative. The frame
was generated specifically for this addon as an original transparent raster,
then alpha-cropped and Lanczos-downsampled for crisp native-size use. It
contains no text and no borrowed FFXI or FFXIV assets; `TH` and the value are
rendered by Windower's `texts` library.

## Sources used for behavior

- Local BG Wiki mirror: `Treasure Hunter` mechanics, trait levels, initial
  caps, aggressive application, reset behavior, BLU spell trait, Treasure
  Hound, and hidden weapon-skill procs.
- Local Windower resources: action messages 603/608, item descriptions,
  augment decoding data, spell IDs, and packet field definitions.
- Windower's official `thtracker` implementation by **Krizz**: raw packet families for
  proc, despawn, and passive/full-HP reset observations.

THTracker was a behavioral reference.  THHUD does not redistribute its source.
