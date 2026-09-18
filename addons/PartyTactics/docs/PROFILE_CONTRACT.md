# PartyTactics profile contract

The unit of change is one directory:

```text
profiles/<stable-profile-id>/
  profile.lua       required declarative policy
  research.md       required evidence and strategy notes
  runtime.lua       optional encounter-only event logic
  analysis_spec.json optional passive post-fight reduction metadata
  easyfarm/*.eup    optional reviewed, profile-owned external-puller artifact
```

Creating a profile must not require editing another profile. Shared code may
change only for a genuinely new reusable capability, never for a fight-id
conditional.

`analysis_spec.json` is governed by `POSTFIGHT_ANALYSIS.md`. It is never loaded
by PartyTactics and cannot affect a combat fingerprint or live behavior.

## Declarative profile

`profile.lua` returns schema version 1 with these sections:

- identity: `id`, semantic `version`, `policy_id`, `label`, and aliases;
- `members`: exactly six character-to-main-job assignments plus tested or
  required subjobs;
- `roles`: named tactical responsibilities assigned to those members;
- `combat`: leader, puller, mobile/stationary mode, targeters, attackers,
  optional priority target/attackers, and an explicit `target_exclusions`
  array (use `{}` when none apply);
- `support`: complete COR, BRD, RDM, GEO, PLD, and DNC policies;
- `offense`: GearSwap weapon-mode request, WS, TP threshold, and optional HP
  bounds for every attacker, plus loadout-only entries for non-attackers;
- optional exact `gearswap_adapter`, `manual_actions`, read-only `preflight`,
  declarative `easyfarm`, and `safety` policy;
- `advisories`: concise operational instructions shown to the leader.

Profiles may not supply raw commands, setup functions, or teardown functions.
The schema rejects command delimiters in command-bearing values and validates
all character references against the profile roster.

`combat.targeters` is the broad synchronized-target set. An attacker may be
deliberately omitted from it to create a directed-only lane: that member
ignores ordinary boss broadcasts and can engage only through a validated,
exact-ID `combat_force_members` transition. This supports isolated add tanks
without enrolling them in the shared boss target.

## GearSwap host and profile adapters

`Common/PartyTactics/PartyTactics_Host.lua` must be included once at the true
end of each character's GearSwap job Lua. The host is stable infrastructure: it chains
the callbacks that already exist, registers raw events once, stays dormant when
no adapter is selected, never equips, and accepts no arbitrary action name.
Its distributed/live digest pair is verified for every profile because the
dormant wrapper is still in every callback path. PartyStart is not a host
dependency and its add-on must remain unloaded.

Host revision 1.2.0 accepts exact pinned adapter protocols 1 and 2 while
rejecting every other value. Protocol 1 remains the legacy route; protocol 2
adds no arbitrary host surface and is interpreted only by its pinned adapter.
The backward-compatible optional `user_job_self_command` consumer introduced
in host 1.1.0 remains unchanged. An adapter may return exactly `true` to own one
narrowly identified automatic helper command; inactive hosts, adapters without
the callback, and non-consumed commands still call the captured job callback
with its original arguments and return values. A host revision change requires
a full GearSwap add-on reload, not only `gs reload`, so the prior host wrapper
cannot remain cached.

Digest comparisons are diagnostics, not combat authorization. A missing or
different live host/adapter/helper produces a visible setup warning while the
profile remains selectable and every unaffected lane can run.

A profile that needs fight-specific GearSwap behavior declares one immutable
adapter pin:

```lua
gearswap_adapter = {
    id='stable-fight-id',
    version='1.0.0',
    controller='fight-controller',
    protocol=1,
    actions={'setup','lead','close','cancel'},
}
```

The id, semantic version, controller, integer protocol, and non-empty unique
semantic-action allowlist are schema-validated. `probe` is reserved for the
host capability handshake and cannot appear in `actions`. Any member preflight
`controller` requirement must match this same controller and protocol.

The adapter lives at
`gearswap/adapters/<id>/<version>.lua` in the PartyTactics source tree and at
the corresponding `Common/PartyTactics/adapters/<id>/<version>.lua` live
GearSwap path. The compiler activates only that exact id/version with the
stable host and emits `gs c ptgs off` during teardown. An adapter-free profile
also emits `gs c ptgs off` before applying support state, so it cannot inherit
a fight adapter left active by a coordinator crash or reload. A changed
behavior gets a new adapter version and a profile version bump. Never edit an
older adapter to serve a new fight, add fight branches to the host, or extend a
frozen legacy helper.

The migrated Locus, Limbus, and V1 profiles continue to use the frozen generic
`PartyStart_BRD.lua`, `PartyStart_RDM.lua`, `PartyStart_GEO.lua`,
`PartyStart_PLD.lua`, and `PartyStart_DNC.lua` GearSwap compatibility helpers.
Those filenames are historical library names only; they do not load or
communicate with the PartyStart add-on. Their canonical, immutable v1 source is
under `gearswap/legacy/1.0.0/`; startup compares each source digest with the
actually loaded Common copy and reports a warning on a missing or mismatched
helper. New fights use the host plus an exact versioned adapter
whenever they need new GearSwap-side queuing or callback behavior.

Generic manual-action adapters are a separate narrow layer:
`brd-pack-sleep`, `clarion-extra-song`, `exact-enemy-action`,
`rdm-exact-silence`, and legacy `typed-action`. They remain fingerprinted when
a profile declares them. The universal fixed-roster `brd-pack-sleep` fallback
is the deliberate exception and belongs to every engine signature.

Reusable optional controls are additive:

- any support role may set `enabled=false`; the compiler explicitly stops that
  job's controller, HealBot combat surfaces, and AutoWS2;
- BRD and GEO may set `healbot='cure-na'` for cure/status-removal only. Buff,
  debuff, assist, attack, and follow behavior remain disabled;
- GEO may explicitly set `combat_entrust_only=false` when its selected
  controller mode must establish Entrust before combat. The compiler restores
  the native `true` default during GEO teardown, so the choice cannot leak into
  a later profile. `leanmanaged` is the opt-in controller mode for a guarded
  coordinator-driven native colure heartbeat;
- an attacker may set `automatic=false`. GearSwap still selects its reviewed
  weapon mode, but AutoWS2 is kept Off and the WS/TP fields become documented
  intent for typed manual actions;
- any non-attacker may have an offense entry only with `automatic=false`.
  This is a loadout request: it selects a reviewed weapon mode while AutoWS2
  remains Off. It does not add that member to PartyCombat targeting, facing,
  movement, or engagement;
- PLD may set the additive `native_buffs=false` and/or `native_tank=false`
  controls. They disable only Selindrile's native buff/tank loops for that
  profile while leaving the selected frozen GearSwap healing helper active;
- `manual_actions` using `typed-action` declare `kind`, action `name`, and safe
  target. `clarion-extra-song` has the same spell shape but refuses the cast
  unless Clarion Call is locally active.

The command name `sleep` has a fixed-roster safety contract. A profile may
declare it only as
`{character='Barneystinson', adapter='brd-pack-sleep'}`. When omitted,
PartyTactics supplies that same reviewed fallback automatically. The request
is leader-only and requires an active profile, but has no ACK or check
prerequisite. It always operates on Barney's current target and never selects,
engages, moves, or equips. Failure affects only that request.

The compiler applies every declared weapon mode through GearSwap's direct
`gs c weapons <mode>` command. This both updates the mode and immediately asks
GearSwap to equip its reviewed set before AutoWS2 is configured. COR setup also
forces `CompensatorMode` to `Never` and `UnlockWeapons` Off before Roller2 is
enabled, so rolls cannot replace the profile-owned ranged weapon.

An optional `preflight` declaration describes a read-only diagnostic check.
`required_before_combat` and `auto_after_apply` are retained only so older
manifests still parse; PartyTactics 0.11 does not use them to authorize,
schedule, retry, or block combat. `max_age_seconds` controls only how long a
passing observation is displayed. `//pt check` must be requested explicitly.
An `all` policy and case-insensitive `members` policies may declare:

- actual equipped slots (`equipment`), by item name or `any_of` names;
- accessible `items`, with minimum counts, optional low-stock warnings, and
  either the Inventory-only or Inventory/Wardrobe 1-8 bag group;
- required or optional `key_items`, by one resource id or alternative ids;
- required or optional learned/currently available spells, job abilities, and
  weapon skills in `actions`;
- a required pinned-adapter `controller` name and protocol for a per-client
  current-generation/current-epoch capability probe.

The evaluator receives only read-only Windower state. It never sends a
command, equips, casts, moves, targets, or toggles another add-on. A failed
check changes only diagnostic output. ACKs, checks, equipment, inventory,
buffs, and controller probes never block `arm`, `force`, profile actions, or
manual input.

Target exclusions are profile-owned runtime policy, not a persistent user
default. The currently supported value is `elemental`. It is sent to both
PartyCombat and AutoWS2 for every member; an empty array compiles to an explicit
no-exclusion PartyCombat field and `aws2 exclude none`. This is why a filter
selected by Limbus cannot survive a later profile transition.

An `easyfarm` declaration may name the operator, exact expected target,
profile-relative `.eup` artifact, detection distance, pull action, and pull
distance. Store an artifact only under that profile's `easyfarm/` directory and
give it the narrowest exact target allowlist. The regression suite must verify
the file matches the declaration. A declared artifact must exist; otherwise
only that profile is quarantined during catalog load. PartyTactics does not
load, start, stop, or rewrite EasyFarm; the operator remains responsible for
those external actions.

Protect-first and managed-controller behavior must use isolated opt-in names.
The current protected RDM variants are `locusbats-protect`, `limbus-protect`,
`ambuscade-v1-protect`, and `magicboss-protect`; they do not change the legacy
unsuffixed presets. GEO profiles may select `leanmanaged` or `leanrrmanaged`
for the guarded native-colure heartbeat. Teardown restores
`CombatEntrustOnly`, so an out-of-combat Entrust choice cannot leak to the next
profile. Fight-specific behavior must live in the owning profile runtime or a
unique versioned fight adapter; do not add a fight name to these frozen shared
helper presets.

Exact enemy actions must not put a spawn-type-16 monster name directly into an
FFXI input command: installed GearSwap intentionally rejects ordinary NPC names
during textual target resolution. Use the reviewed `exact-enemy-action` adapter
with a finite `target_names` allowlist. It resolves a currently live exact-name
enemy to a bounded numeric server ID and submits only the typed action through
GearSwap; it has no selection, movement, raw-command, or equipment surface.

If a support job is target-synchronized only to drive a native controller,
`automatic=false` disables AutoWS2 but does not necessarily disable that job's
GearSwap-native AutoWS state. Such a profile may opt into
`disable_native_autows=true` for that member. The compiler emits the additional
off command only when declared, so existing profiles retain identical plans.

Treat a profile version as an immutable contract. Increment it whenever a
policy, assignment, or runtime changes. Use a new stable id for a different
encounter or materially different strategy; use a version bump for improving
the same strategy.

Canonical ids, public aliases, and PartyCombat `policy_id` values are owned by
the append-only `data/profile_registry.lua`. Add a new final entry with the
next ordinal for a new fight. Never edit or reorder an established entry. The
loader quarantines a later conflicting entry while preserving the earlier
profile and all of its commands.

## Behavior fingerprint and application reporting

Semantic versioning is necessary but is not the only identity check. Each
compiled plan receives a canonical behavior fingerprint containing:

- the complete declarative manifest and its `profile.lua` source digest;
- the optional `runtime.lua` source digest;
- the declared profile-owned EasyFarm artifact source digest, when present;
- the complete compiled six-member plan;
- the source digest of every manual adapter that profile actually uses;
- PartyTactics core/library source and the reviewed PartyCombat, AutoWS2,
  Roller2, HealBot, distributed controller, and live common GearSwap
  compatibility surfaces; and
- the distributed and live `PartyTactics_Host.lua`, because its dormant
  wrapper is in every job callback path; and
- for a declared `gearswap_adapter`, the distributed and live copy of only
  that exact adapter id/version.

All responding clients agree on add-on version, profile id/version, and this
fingerprint during prepare. A compatible client applies its own assignment;
an unavailable or incompatible client is reported and skipped. After the
bounded prepare window, the available clients proceed. Missing live
dependencies and source/Common differences are included in diagnostics and
the fingerprint, but do not make a valid profile unselectable.

Application ACKs report which clients executed the local plan for the current
epoch. They never authorize `arm`, `force`, adapter requests, or manual
actions. Zone and Level Sync reapply remain local best-effort lifecycle work;
a client that cannot reapply reports the problem without stopping its peers.
`off` tears down the complete selected profile, while `disarm` clears the
leader's encounter latch and stops PartyCombat but leaves support loaded.

`ctx.authorize_encounter(id)` binds one exact enemy ID for typed adapter
routing. It validates identity; it is not an ACK, equipment, buff, controller,
or preflight gate. `ctx.release_encounter(id)` retires that routing identity
and pending fight work without scheduling a new check.

## Runtime module

An optional `runtime.lua` returns:

```lua
return {
    create=function()
        local instance = {}
        function instance:on_activate(ctx) end
        function instance:on_action(ctx, action) end
        function instance:on_tick(ctx, now) end
        function instance:on_deactivate(ctx) end
        return instance
    end,
}
```

Each activation receives a fresh instance. No state is shared with another
profile. Supported context capabilities are:

- `ctx.actions.cast(spell, target)`
- `ctx.actions.ability(ability, target)`
- `ctx.actions.weaponskill(ws, target)`
- `ctx.actions.item(item, target)`
- `ctx.actions.controller(job, ...)`; reviewed forms currently include
  `('brd', 'sleep')` and `('rdm', 'silence', uint32_target_id)`. These are
  frozen GearSwap-owned, bounded next-action reservations rather than raw casts;
  no profile can supply an arbitrary action name through the controller
  surface.
- `ctx.actions.party_adapter(character, semantic, uint32_encounter_id,
  optional_request_token, optional_uint32_subject_id)`, which is available
  only when the active profile declares a matching
  `gearswap_adapter`, the recipient's manifest declares the same controller
  name/protocol, `semantic` appears in the finite allowlist, and the leader has
  bound that exact encounter ID for routing. No live probe reply is consulted.
  The optional subject is a separate exact
  add/mechanic target; it never replaces or expands encounter authority. Both
  IDs are independently uint32-validated by the leader and receiver, and the
  pinned adapter must revalidate the subject's live identity, life, zone, and
  encounter relationship before reserving an action. PartyTactics signs and
  relays the request to the named client; the stable host adds the active
  generation/epoch before the adapter may reserve it. On that host boundary,
  subject follows the request token; `-` is the positional no-token sentinel
  only when a subject is present. Calls without a subject retain the original
  command bytes.
- `ctx.actions.combat_force(id, optional_exact_hidden_hpp_name)`, which accepts
  only a uint32 server ID. Without the optional name it requests
  PartyCombat's normal bounded force path with byte-for-byte legacy command
  behavior. With a validated exact name it requests the opt-in hidden-HPP
  path, which PartyCombat accepts only for that live ID/name/index and a
  current party claim under an installed runtime role policy
- `ctx.actions.combat_force_members(id, members)`, which performs one exact-ID
  transition only for the named configured attackers, including a
  directed-only attacker. It does not install a persistent target rule
- `ctx.actions.combat_stop_members(members)`, which performs one exact stop only
  for the named configured attackers. It preserves the profile policy,
  controller arm state, and every unlisted combat lane, so a later directed
  edge can resume those members
- `ctx.actions.combat_observe(id)`, which accepts only a uint32 server ID and
  requests PartyCombat's local target-only observer path without arming combat
- `ctx.actions.combat_stop()`, which requests PartyCombat's ordinary inert
  state after a bound encounter ends; it exposes no target or raw command
- `ctx.client.engage_once(id)`, which emits PartyCombat's exact local one-shot
  engage request. It creates only the initial battle state needed by a ranged
  attacker; it does not enroll that client in synchronized targeting, movement,
  facing, retry, or re-engagement
- `ctx.combat_ready()`, a compatibility predicate that means a profile is active
  and not currently being reapplied. It does not inspect ACKs, checks,
  equipment, buffs, inventory, or controller replies
- `ctx.operator_armed()`, the signed, profile-wide start/stop toggle set by
  `//pt arm`/`//pt disarm` from any of the six active profile members (or by the
  leader's `//pt force`). Runtimes may use it to distinguish inert profile
  loading from running the strategy; it is not a setup, capability, or result
  gate. Only the active profile leader issues the resulting PartyCombat
  command. Encounter release, disarm, replacement, and reapply clear the
  toggle
- `ctx.authorize_encounter(id)`, `ctx.encounter_ready(id)`, and
  `ctx.release_encounter(id)` for one leader-bound exact-ID routing lifecycle.
  These calls keep adapter traffic attached to the intended enemy; they do not
  approve combat or consume a preflight proof
- `ctx.client.auto_target(boolean)`, the sole native-client preference toggle
- read-only time, player, mob, current-target, spell, job-ability,
  weapon-skill, and monster-ability lookups
- `ctx.party_tp(name)` and `ctx.party_hpp_floor()` as read-only observations for
  strategy timing. They must not authorize `arm`/`force`, reject manual input,
  or suspend unrelated automation lanes
- `ctx.party_claimed(mob)`, which accepts a mob snapshot and compares its
  claim ID only with the local player and `p0` through `p5` party-member IDs
- read-only `ctx.has_buff(name)` lookup
- `ctx.alert(message, audible)`; audible alerts play once on the leader

There is intentionally no raw-command or equipment API. A runtime exception
pauses that local runtime callback and reports it; it does not revoke the
generation or stop healthy peers. Profile-owned chunks run in
a restricted Lua environment: they cannot access Windower, `require`, file
I/O, debug facilities, or mutable standard-library tables. `on_deactivate` is
idempotently invoked once for each live runtime during replacement, stop,
job change, reapply, or PartyTactics unload so a runtime can safely restore
a client preference changed by `on_activate`.

## Cooperative action rule

Every profile-generated action must be bounded and independent. It may use a
GearSwap-owned reservation queue when the character is busy, but its waiting,
failure, expiry, missing reply, or result must affect only that request. It must
not authorize combat, block another job's lane, consume unrelated input, or
require the operator to repeat a key until a queue happens to clear.

A new or materially revised adapter must leave `pretarget` and `precast`
manual input unfiltered. The adapter may submit only the finite semantic
actions declared by its profile and must continue to let the character's
ordinary GearSwap own equipment and action sets.

For any delayed or retried hostile spell, ability, or weapon skill, the request
must snapshot and revalidate the exact server ID, entity index, zone, life
state, party claim, and an action-appropriate expiry before every attempt.
Never delay a raw `<t>` action and hope that the same enemy is still selected.
Self-only actions may use a simpler bounded per-job queue. Existing direct
`typed-action` adapters remain available for compatibility with older profiles,
but they are not an acceptable operator path for a newly built or materially
revised fight.

PartyCombat target control (`force`/`forceid`) is not a character spell or
ability and is therefore outside this queue rule. Exact-target validation and
profile target exclusions still apply, but ACKs, checks, buffs, equipment, and
controller replies do not authorize it.

## Definition of done for a new fight

1. Start with the locally cached BG Wiki vault at
   `C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki`, then check the
   live page and other primary/corroborating sources for newer or missing
   details. Record sources, uncertainties, and the retrieval date in
   `research.md`.
2. Define positioning, target order, pull authority, support coverage,
   healing/status ownership, mechanic reactions, explicit target exclusions,
   and wipe/recovery behavior.
3. Choose the nearest reviewed GearSwap controller presets; add isolated
   runtime logic only for mechanics those presets cannot express. If the fight
   needs new GearSwap-side reservation or callback behavior, create a unique
   versioned adapter and pin it in the profile; never modify the stable host or
   a frozen legacy helper for that fight.
4. Append a unique identity entry with the next ordinal to
   `data/profile_registry.lua`; never edit or reorder an old entry.
5. Increment the profile version for every behavioral revision.
6. Run `tests/run_tests.ps1` and keep every prior profile green.
7. Use `//pt preview <id>` in game, then activate without arming combat.
8. Verify GearSwap equipment behavior, support rotations, and target roles.
   `//pt check` and the ACK count are optional diagnostics, not prerequisites
   for `//pt arm`. Remember that DNC Samba, Steps, and Flourishes cannot appear
   until that DNC is actually engaged.
9. Record live observations and adjust only the selected profile/module.

When EasyFarm is part of the plan, also verify its checked-in artifact against
the declaration and load it manually while out of combat. When a target-only
member has manual offense, test that AutoWS2 remains Off and PartyCombat leaves
the member unengaged.

If a shared adapter must change, its old behavior is a compatibility contract.
For a profile adapter, add a new versioned file and update only the owning
profile's pin. For a truly generic manual adapter, add a new option or adapter
instead of changing existing semantics. Then run all profile tests—not only the
new fight.
