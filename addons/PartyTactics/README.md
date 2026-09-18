# PartyTactics

PartyTactics is the modular successor to PartyStart's fight-profile layer. It
coordinates the existing Windower tools on the six local clients while each
tool keeps its own responsibility:

- GearSwap owns equipment, sets, slot locks, precast/midcast, and native job
  callbacks.
- PartyCombat owns synchronized targeting, facing, movement, and engagement.
- AutoWS2 owns automatic weapon-skill execution.
- Roller2 owns rolls.
- HealBot is used only in the narrow modes selected by the profile.
- EasyFarm remains an external puller with its own reviewed configuration.
- FastFollow is always user-owned and is never read or changed.

PartyTactics selects *what policy or action is wanted*. It never equips an
item. Barney's instrument switching is one useful regression sentinel for
that universal boundary, not a special-case implementation.

## Supplied profiles

PartyTactics 0.13.3 declares this catalog:

| Command alias | Stable profile id | Profile version | Behavior |
|---|---|---:|---|
| `locus` / `locusbats` | `locus-dire-bats-tomb` | 1.3.0 | Stationary Locus Dire Bat camp; Protect-first, Shell-off, managed Fury/Frailty, and a profile-owned EasyFarm artifact |
| `locus-signet` / `locusbats-signet` | `locus-dire-bats-tomb-signet` | 1.8.0 | Isolated LocusPuller camp with exclusive Flash ownership, exact companion readiness, all-six Signet renewal, Jubilee ownership, profile-local Majesty sustain, duplicate-resume repair, and single-leader recovery after a raw SignetKeeper reload |
| `limbus` | `limbus-119-stationary` | 1.2.0 | Stationary Limbus 119 Flash pulls, explicit Elemental exclusion, managed support, a profile-owned EasyFarm artifact, and manual pack sleep |
| `v1-breadwinner` (`v1` / `breadwinner`) | `ambuscade-2026-08-v1-breadwinner` | 1.1.0 | August 2026 V1 Breadwinner mechanics with isolated Protect-first/managed support |
| `ddw1route` | `dynamis-divergence-wave1-route-corsair` | 1.2.0 | COR-only 1500-TP Leaden statue route |
| `ddw1boss` | `dynamis-divergence-wave1-boss-magic` | 1.2.1 | PLD/COR manual Darkness Wave 1 boss |
| `genmei` / `genbu` | `escha-ruaun-genbu-genmei` | 2.7.0 | Proven Light/dual-burst clear with completion-confirmed Presto/Box Step, opening Thunder Shot insurance, queued intended Savage Blade, and unconditional manual-action pass-through |
| `kammavaca` / `kamma` | `escha-ruaun-kammavaca` | 1.2.0 | Ordered physical clear with immediate exact CLMA priority and queued support |
| `v1-qutrub` (`qutrub` / `bigwig`) | `ambuscade-2026-09-v1-qutrub-bigwig` | 1.1.0 | September V1 exact-add priority, independent BRD/SMN + RDM/SMN Mew/Retreat lanes, uninterrupted GEO luopan, shadow safety, and packet-confirmed Light chains |
| `v1-qutrub-nocait` (`qutrub-nocait` / `bigwig-nocait`) | `ambuscade-2026-09-v1-qutrub-bigwig-no-cait` | 1.14.0 | Normal-validated cooperative alternate: inert armed preparation, ownership-confirmed anchors, atomic shared focus plus one bounded stalled-acquisition repair, Dolo's session-scoped automatic Last Stand, thresholded healing, recast-aware shadows, and manual-action pass-through |
| `v2-hydra` (`hydra` / `alluttu`) | `ambuscade-2026-09-v2-hydra-alluttu` | 1.0.0 | September V2 packet-confirmed Light/Thunder head pressure, shield-mode switching, stuns, and recovery holds |
| `rancibus` / `vagary-rancibus` | `vagary-direct-rancibus` | 1.1.0 | Cooperative direct Rancibus clear: inert load, immediate best-effort arm, independent melee/ranged/support lanes, and manual controls that always pass through |
| `sortie` / `sortierun` | `sortie-main-v1` | 1.2.0 | Persistent main-run owner: one load, any-member exact-target synchronization, internal C/B/A/boss recipes, safe travel support, and a dedicated no-debuff/no-Sentinel Leshonn mode |
| `sortiec` / `cdevice` | `sortie-objective-c-device-kill-v1` | 1.0.0 | Stationary all-six Device C objective: operator pulls and positions one normal Cachaemic, then forces best-effort combat with no readiness gate or input lock |
| `cmb` / `sortie-c-mb` | `sortie-objective-c-magic-burst-v1` | 1.3.0 | Exact Skeleton/Ghoul target selection, full-speed TP burn, packet-confirmed Fragmentation/Thunder burst, and automatic retry |
| `amk` / `sortie-a-magic` | `sortie-objective-a-magic-kill-v1` | 2.0.0 | Exact Acuex target selection; all-six TP burn, Flat Blade → Red Lotus Blade Liquefaction, protected Fire IV + Fire III, and automatic recovery |
| — | `sortie-objective-b-weapon-skill-v1` | 1.0.0 | Exact Biune target selection; full burn with a packet-confirmed weapon skill before every kill |
| `sortied` / `demisang` | `sortie-objective-d-demisang-clear-v1` | 1.1.0 | MP-efficient stationary Demisang sweep: Tackle owns Majesty healing and sustained enmity, Kick backs up with Waltzes, Smalls handles emergency/status work, and every manual override remains available |
| `skomora` / `boss-c` | `sortie-boss-skomora-v1` | 1.2.0 | Non-REMA Skomora profile: exact-target activation, Tackle-first threat, all-six melee, and persistent lean support |
| — | `sortie-boss-leshonn-v1` | 1.1.0 | Non-REMA Leshonn recovery profile with no routine debuffs, no automated Flash/Sentinel, Tackle-first threat, and Wind/Lightning-safe offense |
| `ghatjot` / `boss-a` | `sortie-boss-ghatjot-v1` | 1.2.0 | Non-REMA Ghatjot profile with no-Water offense and learned Evisceration for Kick |

The simple encounter-qualified commands are `//pt v1-breadwinner`,
`//pt v1-qutrub`, `//pt v1-qutrub-nocait`, and `//pt v2-hydra`. The explicit
forms (`//pt use v1-qutrub`, for example) work too. The historical `//pt v1`,
`//pt breadwinner`, `//pt qutrub`, `//pt qutrub-nocait`, and `//pt hydra`
commands remain unchanged.

Every profile lives in its own directory under `profiles/`. Optional encounter
code is loaded only for that profile. The coordinator and compiler contain no
fight-id branches. The profile version is an immutable behavior contract and is
independent of the PartyTactics add-on version.

Public profile ids, aliases, and PartyCombat policy ids also have append-only
ownership in `data/profile_registry.lua`. A new fight receives the next
ordinal and unused names. If it claims an established name, only the new entry
is quarantined; the existing profile and command keep working.

Encounter-qualified convenience names live in isolated per-profile sidecars
under `data/supplemental_aliases/`, not in immutable identity records or
profile alias arrays. They may point only to their filename's loaded canonical
profile id. A collision or unavailable/quarantined target disables only that
shortcut; a malformed sidecar cannot disable its valid siblings or change any
canonical id, established alias, or profile behavior signature.

GearSwap integration has five deliberately separate layers:

- `PartyTactics_Host.lua` is a stable, dormant host that must be included once
  at the true end of each character's job Lua. It owns callback chaining and raw event
  registration, but it does not contain a fight strategy or equip anything.
  Host 1.2.1 accepts only exact pinned protocol 1 and 2 adapters; every other
  adapter protocol is rejected before activation.
- A profile that needs fight-specific GearSwap behavior declares one exact
  `gearswap_adapter` id and semantic version. The host loads only that file,
  such as
  `Common/PartyTactics/adapters/escha-ruaun-genbu-genmei/2.7.0.lua`, while that
  profile is active. A behavioral revision gets a new versioned file; an old
  adapter is never edited in place for a different fight. The host itself is
  verified globally because its dormant wrapper is in every job's callback
  path; only the selected fight adapter is profile-local.
- The migrated Locus, Limbus, and V1 profiles still use the frozen generic
  `PartyStart_BRD.lua`, `PartyStart_RDM.lua`, `PartyStart_GEO.lua`,
  `PartyStart_PLD.lua`, and `PartyStart_DNC.lua` GearSwap compatibility
  helpers. Those historical filenames do not mean the PartyStart add-on is
  loaded, and new fight behavior must not be added to those helpers. An exact
  canonical snapshot lives under `gearswap/legacy/1.0.0/`. A missing or
  different Common copy is reported as a setup warning; it never disables an
  unrelated profile or blocks unaffected lanes.
- Small generic manual-action adapters remain narrow, typed compatibility
  surfaces: `brd-pack-sleep`, `clarion-extra-song`, `exact-enemy-action`,
  `rdm-exact-silence`, and the legacy `typed-action`. A profile fingerprints the
  manual adapters it declares; the universal fixed-roster `brd-pack-sleep`
  fallback is intentionally present in every engine signature. A profile-owned
  GearSwap adapter adds its exact pinned id/version to the globally verified
  stable host, not any sibling adapter or newer version.
- The recurring 0.75-second role-maintenance clock stays in PartyTactics so
  activation, reapply, and teardown semantics are unchanged. The local
  GearSwap CPU patch gives that clock a narrow callback path which refreshes
  globals and calls only the reviewed role helper, without a generic equipment
  pass. If an official GearSwap update replaces that entry point, PartyTactics
  warns once and falls back to the established `gs c` path rather than losing
  maintenance behavior.

PartyTactics delegates persistent equipment ownership to GearSwap. Profiles
select a named weapon mode but never equip individual slots. Dolomedes's single
`DualSavage` mode equips Naegling/Gleti's Knife and intentionally leaves range
empty so its normal TP, idle, and Savage Blade sets can use their reviewed stat
ammo. Genmei selects the native `DeathPenalty` shield mode, which owns Death
Penalty and compatible bullets, because its recommended COR/THF has no Dual
Wield.

## First use

Load PartyCombat and then PartyTactics on all six clients, and leave the
PartyStart add-on unloaded. The supported `init.txt` and safe reload scripts
provide that dependency order explicitly. PartyTactics does not issue blind
PartyCombat load requests at startup or profile commit, avoiding Windower's
`Addon PartyCombat already loaded` error while still applying an inert,
validated policy before ordered operator ON can become effective. The frozen
`PartyStart_*` GearSwap compatibility helpers are libraries inside the job-Lua
environment, not a second orchestrator and not a reason to load PartyStart.

Every COR plan also sets Roller2's policy, engaged requirement, both rolls,
and `randomdeal off`, so a saved opt-in from unrelated play cannot leak into a
profile.

From Dolomedes:

```text
//pt preview locus
//pt use locus inert
//pt status
//pt arm
```

Direct aliases and `//pt use <profile>` now load and arm by default. Add the
explicit `inert` argument when setup must remain stopped, then use `//pt arm`
after positioning, EasyFarm, and the pull target list are ready. The Sortie
main run below is loaded and armed once by ExpeditionGuide and needs neither
operator command.

An automation owner may atomically request `//pt use <canonical-id>`.
For profiles with a fight-local tank-first runtime, `//pt arm`, Ctrl-P's
`//pt force`, and route-owned armed activation start that runtime instead of
broadcasting `pc force`. Tackleberry alone receives the initial target; his
first hostile action or party claim releases the remaining attackers, with a
two-second safety release so packet loss cannot stall the pull. Alt-P remains
immediate and authoritative.

Automatic target selection is bootstrap-only: it never replaces an active
profile or supersedes a pending commit. The Sortie main route therefore loads
one profile after entry; later hostile actions select internal recipes only.

### Sortie main-run normal workflow

Do not load or switch a combat profile during the run. ExpeditionGuide loads
and arms `sortie-main-v1` once after entry. Engage the mob named by the guide
with Tackleberry when practical; any configured member's hostile action binds
the exact target and emits one synchronization edge for all six. Target names
select C, B, A, boss, or general combat recipes inside that profile. No
character is an activation gate, and manual commands are recovery tools only.

For Locus, pre-combat spell support begins as soon as activation commits:
Smalls starts the party Protect pass and Achoo starts Indi-Fury plus available
Entrust Refresh. Geo-Frailty requires a valid enemy battle target. Dancer
support has no pre-combat equivalent: Haste Samba, Box Step, and Flourishes
begin only after `//pt arm` causes Kickpuncher to engage.

The Signet derivative uses the same support timing but a different pull owner:

```text
//pt locus-signet
//pt check                  (optional item/controller diagnostics only)
//pt arm                    (or Ctrl-P: enable LocusPuller and combat)
//pt disarm                 (or Alt-P: stop pulls and combat)
//send @all sk status       (Signet transaction diagnostics)
```

Loading it leaves LocusPuller inert. PartyTactics' synchronized operator state
starts and stops the puller; there is no EasyFarm artifact in this derivative.
Every Ctrl-P/Alt-P request has a per-character sequence, and Dolomedes assigns
one authoritative party-wide revision. A lower revision is stale, an equal
revision with the same bit is a harmless repair, and an equal revision with a
different bit is rejected. Alt-P applies PartyCombat OFF immediately. Ctrl-P
records ON while a controller reload, zone reapply, or Signet transaction is
holding automation, then replays that intent only after the exact replacement
controller is ready. On a fresh all-missing load, SignetKeeper also withholds
LocusPuller ON until its current six-client census completes.
Controller readiness is not inferred from GearSwap alone: all six local
SignetKeepers must prove the exact generation/epoch binding, Tackle must also
prove LocusPuller, and Dolo must also prove JubileeKeeper. PartyTactics retries
that same authorization and proof exchange silently while startup is pending;
helper load requests are bounded so a loaded-but-unavailable helper cannot
produce endless `already loaded` console lines.
Each pull is confirmed from Tackle's exact outgoing Flash packet, not from the
local command string. A swallowed `/ma` is retried silently for up to five
seconds; a real Flash on the selected bat ends dispatch retries immediately.
Recommended subjobs are Dolo /DNC or /NIN (for `DualEvis` with Tauret and
Gleti's Knife), Tackle /WAR, Kick /WAR, Barney /WHM, Smalls /WHM, and Achoo
/BLM. Dolo uses Evisceration at 1000 TP. These are documentation, not
`members` requirements, so a different subjob never blocks profile
application or the controller handshake; /THF remains accepted but cannot
equip the offhand weapon.
When any fresh client report lacks Signet, including the initial all-missing
load, the current Flash/fight drains and all six become idle. Already-buffed
clients count complete without using their staff; each missing client performs
the generation-bound staff transaction. Its exact staff must remain visibly
equipped for the empirically proven 42.5-second boundary, and only an observed Signet buff counts as
success. A missing or depleted staff pauses that maintenance transaction
without filtering any manual action. Dolo's Jubilee Ring remains GearSwap-owned
in the right ring throughout; the left ring is untouched. Profile departure
releases both keepers and the puller binding.

A standalone GearSwap reload is different from profile departure. The pinned
adapter first turns persistent automatic lanes off, then the standalone
keepers retain and raw-reassert their exact equipment ownership during the
gap. One or more concurrent client notices are coalesced into one exact
controller-recovery request. PartyTactics validates the old lifecycle, starts
one full distributed reapply, and reruns the complete compiled weapon/support
policy. The desired operator bit is carried as state, but PartyCombat remains
off on each client until that client's newly authorized adapter reports ready.
Generation nonces are opaque rather than numerically
ordered: recovery accepts only an epoch-zero probe for a fresh, different
generation with the same profile, leader, and roster. Any interrupted
staff delay and renewal cycle restart safely at cycle 1 with a fresh 42.5
seconds. Reload recovery is bounded;
zone, logout, profile stop, and profile replacement remain terminal keep-off
operations. An outside-Tomb activation is retained only as an inert timer
owner: it binds no helper, applies a complete local OFF baseline immediately,
and reasserts it once after two seconds. A successful profile probe or any
profile replacement cancels that local retry, so it cannot affect the next
profile.

Version 1.6 makes every exact duplicate Signet resume a complete repair edge.
It reasserts AutoWS2, the job-specific Roller2 or RDM support baseline, and the
current ordered PartyCombat state before returning another exact local
SignetKeeper acknowledgment. This repairs a partially delivered first resume
without creating a new cycle or trusting GearSwap's addon-scoped IPC to reach
SignetKeeper.

`//pt off`, PartyTactics unload, and replacement by a different profile also
work during the GearSwap gap. The profile declares only the safe local
companion command prefixes; PartyTactics appends the validated generation/
engine/profile/signature/source tuple and tombstones SignetKeeper,
JubileeKeeper, and LocusPuller without depending on GearSwap or IPC loopback.
Same-profile recovery deliberately does not issue that terminal fence, so the
Jubilee and Signet equipment guards survive until the authorized successor
takes ownership. The live adapter receives the same exact tombstone when
available. Stop, operator-request, operator-state, and periodic state IPC use
fixed 10-, 11-, 11-, and 15-field messages. Prepare and commit use fixed
14-field carriers containing the same revision/bit snapshot and an explicit
terminal-replacement bit. Surplus fields,
malformed epochs/revisions, stale lower revisions, and equal-revision bit
conflicts are rejected. Local
controller ready/lost/terminal/recovery callbacks likewise require their exact
argument counts.

Useful commands:

```text
//pt list
//pt show limbus
//pt preview v1-breadwinner
//pt v1-breadwinner
//pt use v1-qutrub
//pt reapply
//pt check
//pt arm
//pt disarm
//pt force
//pt sleep              (universal current-target pack sleep; Alt-L)
//pt off
//pt errors
//pt version
```

Any configured profile participant can activate, tear down, arm, disarm,
force, or request a declared manual encounter action. PartyTactics validates
and signs that request and synchronizes the profile-wide latch. On a
latch-aware automatic profile such as
September Qutrub or Hydra, `//pt disarm` stops PartyCombat and the encounter
runtime while leaving the selected support policy active. `//pt off` tears the
complete profile down from any configured participant. `//pt status` reports
the synchronized arm state on every member.

`//pt arm`, `//pt force`, and manual profile actions never consult an ACK,
check, equipment, buff, or controller-readiness result. They run immediately
against whichever clients are available. `//pt status` still reports ACKs so a
missing client is visible, but that number is diagnostic only.

`//pt sleep` is the one fixed-roster emergency exception to profile-declared
manual actions. In every active profile it asks Barneystinson's existing
GearSwap BRD controller to sleep Barney's current target. It requires an
active configured participant, with no ACK or check prerequisite. If Barney or
his controller is unavailable, that request fails by itself; nothing else is
stopped.

Profiles may declare read-only checks for equipped slots, inventory, key
items, buffs, and available actions. Run `//pt check` when that information is
useful. A warning never equips, casts, engages, retries automatically, or
blocks `arm`, `force`, adapters, combat, or manual actions.

## Sortie Device C onboarding objective

`//pt use sortiec` loads the reviewed support, weapon, and stationary combat
policy but leaves combat inert. At Device C, Tackleberry manually Flash-pulls
one normal Cachaemic; a Ghost is the conservative first choice because a
Corse can Charm at low HP. Once the chosen foe is visibly beside the Device,
select that exact foe on Dolomedes and press Ctrl-P or run `//pt force`.

The profile has no target-name check, ACK gate, setup gate, navigation,
interaction automation, or input filter. Manual movement, retargeting,
attacks, weapon skills, spells, abilities, ranged attacks, cures, and recovery
remain available. Stationary PartyCombat does not walk a character into range.
Press Alt-P after the kill for a party-wide disarm; on a bad pull, disarm and
recover or improvise manually without reloading the profile.

## Sortie C Shard/Metal Magic Burst objectives

At the main-run camp, engage an exact Cachaemic Skeleton or Cachaemic Ghoul.
That party action selects the C recipe inside the persistent profile. Corses,
Ghosts, the Bhoot, and arbitrary nearby mobs instead receive ordinary general
combat. Tackle is the preferred first-threat puller, but any configured member
can establish the shared exact target. The profile stays armed for the run.

Tactician/Samurai rolls help precharge TP. After Tackle establishes the pull,
Dolo and Kick receive the chain target: Kick's packet-confirmed Evisceration
opens, Dolo's
packet-confirmed Savage Blade follows after 3.1 seconds, and only a real
Fragmentation additional effect requests Thunder from both Smalls and Achoo.
Only a real party Magic Burst damage message switches all six to normal
physical finishers.
Chest appearance and all-six temporary-item evidence—not an internal counter—
remain the objective authority.

Commands are requests, never evidence. A missed action times out and the chain
rebuilds. A manually issued correct Evisceration, Fragmentation-producing Dolo
Savage Blade, or any real party spell Magic Burst can advance the same runtime.
The adapter's pretarget and precast hooks explicitly pass through. You can
move, retarget, disengage, attack, WS, cast, use an ability/item, cure, Alt-P,
or improvise at any moment; low target HP produces a warning rather than a
software lock.

## Sortie B weapon-skill-credit objective

Engaging any exact Biune elemental selects the B recipe. All six close and
burn continuously, and every learned lane spends TP promptly; the runtime does
not pause or disengage the party. Five targets that each receive at least one
weapon skill before death produce Shard B. The weapon skill does not need to
be the killing blow.

## Sortie A Shard/Metal magic-kill objectives

Engaging an exact Abject Acuex selects the A recipe. All six close and burn
until Tackle and Smalls have 1000 TP. The runtime pauses the other four,
executes Tackle Flat Blade > Smalls Red Lotus Blade, confirms Liquefaction,
then queues Smalls Fire IV plus Fire III. Smalls maintains Aquaveil, a lean
buff set, and automatic Convert support. A miss or broken chain emits one
exact-target resume edge before rebuilding; a low-HP target enters automatic
Fire-only hold instead of an autoattack race.

The profile remains armed between Acuex. Three magic kills produce Shard A;
three more produce Metal A. Chest and all-six temporary-item evidence remain
the reward authority. Alt-P and every manual action always remain available.

## Sortie Skomora, Leshonn, and Ghatjot bosses

Each exact boss selects its non-REMA recipe inside `sortie-main-v1`; no profile
change occurs. Tackle gets the preferred opening threat, but a hostile action
from any configured member remains an immediate, non-gating synchronization
edge.

Skomora keeps the proven stacked melee plan. Selecting Leshonn stages a safe
support mode without engaging: BRD/RDM schedule no routine debuffs, automated
PLD Flash/Sentinel are disabled, GEO bubbles and Box Step remain active, and
Kick's automatic WS is held. Put Tackle alone in front and the other five
behind or on a rear flank before Tackle engages; positioning never gates
combat. Ghatjot excludes Water, Water Shot, Leaden Salute,
Distortion, and Darkness; Kick uses learned Evisceration. Movement,
positioning, target selection, chest interaction, and
emergency improvisation remain unrestricted.

## Sortie Sheet D Demisang clear

On Dolo, `//pt use sortied` (or ExpeditionGuide's `//exg profile`) loads v1.1
inert. Position the six manually, select a regular Demisang on Dolo, and press
Ctrl-P or run `//pt force`. All six attack from their current positions;
PartyCombat faces and engages but never walks anyone. Retarget and press Ctrl-P
again for the next foe or linked pack. Alt-P stops immediately, and every
manual action remains available throughout.

The first run showed severe cure duplication and Smalls MP starvation. In v1.1
Tackleberry's Majesty controller is the routine healer and sustained enmity
lane; Kickpuncher provides emergency Waltzes; Smalls keeps emergency cures and
status removal. Barney and Achoo no longer run routine HealBot cures. Smalls
keeps Haste II, Refresh III, narrowed Phalanx II, and bounded Distract/Dia but
drops the repeated party Protect/Shell cycle. This preserves MP and gives BRD,
RDM, and GEO more time to swing and weapon skill.

The profile does not count mobs or require a kill order. Kill every regular
Demisang for Sheet D. Demisang Deleterious is optional. The opening six-job
party may be killed WAR > MNK > WHM > BLM > RDM > THF for bonus blue caskets,
but survival and live improvisation always take priority.

## Genmei Shield farm

Genmei 2.7.0 uses the same simple control contract as the other cooperative
profiles. `//pt genmei` loads the configuration and remains inert. Prebuff with
the party clustered, target Genbu, then press Ctrl-P or run `//pt arm`. That one switch starts
the timed plan immediately. It does not wait for ACKs, a preflight pass, a
controller proof, a buff, or an earlier setup result. Alt-P or `//pt disarm`
stops encounter automation and synchronized combat while leaving support
loaded.

The exact 2.7.0 adapter keeps fixed actions immediate and adds one deliberately
narrow reservation slot per client: Thunder Shot/Thunder answer Invincible,
Thunder IV answers Light, and Tackle's intended coordinated Savage Blade waits
for his next legal action rather than disappearing behind a Majesty cure. The
Lightning reservations expire within six or eight seconds; Savage expires
within seven. Only an RDM/GEO mage's routine automatic helper pauses for its
own request. Tackle's helper yields only when Savage actually dispatches, is in
flight, or he is busy; low TP, range, disengagement, recast, and backoff leave
Majesty healing live. Invincible immediately cancels a delayed Savage locally
and through the runtime. COR's native tick is never consumed. Both GearSwap
filter hooks always pass manual actions, and normal FFXI input keeps the
character GearSwap file the sole owner of equipment and Bard instruments. The
older 2.1.0 through 2.6.0 adapters remain unchanged beside it.

On arm, the runtime binds only an exact live Genbu. Ctrl-P is the immediate
group-engage edge. Barney attempts Barwatera while the group is still
clustered; Tackle independently tries Sentinel, profile-local Crusade, Divine
Emblem, Flash, and Provoke on a spaced timeline. At bind and once more 1.5
seconds later, bounded exact-target edges cover Tackle and Kick plus
target-only Smalls. Geo-Malaise is submitted only after combat is established,
so it is not a prerequisite or planned pull action. Dolo also gets one immediate
best-effort Thunder Shot request so an Invincible used just before arm is not
missed. A same-edge observed Invincible merges with that request, and Triple
Shot follows on Dolo's next legal action; neither action waits on a result.

PartyCombat never owns Dolomedes in this profile. Dolo receives only the two
bounded startup engage edges, then exact-ID ranged attacks; PartyCombat does
not persistently face, move, retarget, or re-engage him. AutoWS2 is Off for all
three physical actors. When Tackle and Dolo have TP, the runtime requests
Kick's Evisceration if ready, observes a successful completed action packet,
queues Tackle's Savage Blade for his next legal action, then observes its successful result and
requests Dolo's Last Stand for Light. If Kick is not ready, Savage Blade ->
Last Stand still makes Light. A completed step is spaced by 3.1 seconds. A
missing, missed, or failed step expires after a short local timeout, temporarily
bypasses the optional Kick opener, and never stops
attacks, shots, healing, support, or manual input. If Tackle cannot open within
ten seconds, Dolo uses standalone Last Stand instead of holding TP forever.
Triple Shot receives a lower-priority bounded next-legal request at the pull.
Only a successful completion starts the real 300-second cadence; while it is
due but not confirmed, a bounded request retries every 12 seconds. A chain or
waiting Thunder Shot supersedes it without consuming COR's native automatic
tick.
Kick's generic DNC helper is disabled for Genbu, removing overlapping emergency
Waltzes without changing any other profile. The runtime still requests Haste
Samba and Box Step only after live TP reaches their actual costs. When Box Step
is due, it first gives Presto two completion-driven chances inside five seconds.
A confirmed Presto raises the next landed Step by up to five Daze levels and
adds Step accuracy; if confirmation never arrives, ordinary Box Step proceeds
anyway. A missed or rejected Box Step keeps a still-live Presto for the retry,
and only a successful Box Step starts the 45-second refresh. The skillchain lane
always has priority over Step preparation.

Invincible schedules bounded next-legal Thunder Shot and low-MP Thunder follow-ups.
It pauses only Dolo's ordinary ranged cadence for eight seconds, giving the
queued Thunder Shot an action window before `/ra` resumes automatically.
Earlier evidence suggested a successful Thunder stagger might end Genbu's
physical immunity early, but the successful c049 capture returned positive
physical damage around the normal 30-second boundary. The runtime therefore
holds physical WS for 30 seconds but safely resumes sooner only if an actual
positive physical result proves it possible. Ordinary melee continues; `/ra`
resumes after its eight-second proc window. Harden Shell and Shell V are not chased: all
seven observed Dispel/Finale attempts resisted and only displaced useful work.
Dia III plus accelerated Sluggish Daze provide up to 43.31% Defense Down, and
the Light bursts ignore Defense. Shield Bash dispel stays dormant because
Tackle does not own Caballarius Gauntlets +2 or better.
Tortoise Song issues
an event-unique song/roll rebuild request that remains unique across a profile
reapply. Warlock's Roll is roll1, so Roller2 restores the burst/proc accuracy
roll before Samurai Roll when its two rolls share a recast. A detected Light
schedules one bounded next-legal Thunder IV request
on Smalls and Achoo. No miss, resist, recast,
interruption, unavailable action, or missing reply holds another lane or manual
intervention.

The Genbu adapter tells HealBot to ignore only the unerasable Weight aura while
this profile is active; Poison, Accuracy Down, and other real ailments keep
their normal NA lane. Early physical recovery also cancels any undelivered
backup Thunder requests. Tackle owns routine Majesty healing; Smalls uses the
frozen `limbus-protect` controller's 50% backup threshold. Barney and Achoo do
not free-run HealBot cures.
This also preserves Achoo's MP for Malaise, Acumen, Entrust Languor, and
Thunder. Smalls performs one intentional six-target Protect/Shell pass; the
live run did not contain a reactive Shell loop. The frozen RDM helper may also
make up to three best-effort Silence attempts per detected coverage cycle and
can rearm after confirmed wear-off or fresh casting through prior coverage;
Silence never gates combat.

Smalls maintains Refresh III on himself, Achoo, and Tackle. Barney is omitted:
the successful capture retained ample BRD MP under Ballad and ended at full MP.
One bounded two-attempt Barwatera maintenance request runs near seven minutes;
it is best effort and its result never authorizes or blocks another action.

`//pt check` remains available as read-only advice about lenses, Genbu's Honor,
ammunition, equipment, learned actions, buffs, and adapter replies. It never
authorizes or blocks arm or combat, and Genmei has no automatic preflight or
retry loop.

Use these subjobs for the baseline strategy:

- Dolomedes: COR/THF. Level-49 THF supplies Treasure Hunter II, which Dolo's
  first ranged aggressive action applies without any TH-ammo or weapon swap.
  Use the native `DeathPenalty` GearSwap mode: Rostam A, Nusku Shield, Death
  Penalty, and the normal reviewed bullet handling.
- Tackleberry: PLD/WAR for Provoke in the automatic hate setup.
- Kickpuncher: DNC/WAR; Kick is the engaged, rear-positioned skillchain starter
  with profile-local Samba and Step. The generic emergency-Waltz lane is Off
  for Genbu because Tackle owns routine healing and Smalls backs it up.
- Barneystinson: BRD/WHM for Barwatera and emergency manual recovery; automatic
  MP is reserved for songs.
- Smalls: RDM/WHM for low-threshold backup healing, real removable statuses,
  core buffs, Dia, and queued Thunder/Thunder IV.
- Achoo: GEO/BLM. The useful gain is the damage/MP support for main-job Thunder
  IV while Achoo stays out of the redundant healing lane.

The Reraise safety check is warning-only: it never casts a spell or uses an
item. Barney's BRD preset maintains Reraise. Dolomedes, Tackleberry,
Kickpuncher, Smalls, and Achoo need a manual spell or Reraise item; Smalls's
frozen `limbus-protect` preset does not maintain it automatically.

All six characters need Tribulens or Radialens, and Dolomedes needs Genbu's
Honor. The complete operator procedure is:

1. Run `//pt preview genmei`, then gather all six at the `???` inside Barney's
   song range and Dolo's roll range.
2. Run `//pt genmei`. Let the ordinary support helpers prebuff and keep all six
   clustered around Barney. `//pt check` is optional information only.
3. Pop and target Genbu while still clustered, then press Ctrl-P or run
   `//pt arm`; combat starts immediately while Barney and Tackle begin their
   independent opening actions. If you arm before
   the pop, the profile waits quietly for an exact current or party-claimed
   Genbu; loading the profile alone never pulls.
4. Once combat starts, move Tackle to Genbu's front-side edge and face it away.
   Put Kick at Genbu's rear within 4.5 yalms. Keep Dolo, Barney, Smalls, and
   Achoo together roughly 11-14 yalms from Genbu: this remains inside the
   observed song/roll/spell geometry and outside the target-centered 10-yalm
   Waterga radius. PartyTactics performs no movement.
5. Manual targeting, attack, disengage, ranged attacks, weapon skills, spells,
   abilities, items, and emergency recovery always remain available. Press
   Alt-P or run `//pt disarm` whenever you want the automation to stop.

The baseline deliberately uses three continuously maintainable songs rather
than Clarion Call. The current native scheduler cannot prove two simultaneous
Ballads independently, so a fourth song would introduce a fragile second song
owner. It is not required for the conservative farm.

### No-pop validation

The source-tree safe reload script reloads the six job files so each installs
the stable host, then reloads PartyTactics; it neither selects nor arms a
profile. `//pt preview genmei`, `//pt genmei`, `//pt check`, and `gs c ptgs
status` can inspect the configuration and routing without consuming a pop.
The runtime deliberately cannot rehearse hostile actions against an ordinary
mob because it accepts only Genbu. Timing, bounded retries, deduplication,
claim loss, disarm, Invincible, intentional Harden Shell non-response,
Warlock-first Tortoise Song recovery, and Light reactions
are covered by deterministic runtime and adapter tests.

## Direct Vagary: Rancibus clear

`//pt rancibus` is only for the one-boss, 30-minute Ra'Kaznar Turris
alternative battlefield. It contains no Brash Gate route, columns, adds,
waves, or proc logic. Every character must already have completed Watery Grave
and must carry a prototype sigil pearl; all six pearls are consumed on entry.

Use Dolo COR/DNC or COR/NIN, Tackle PLD/WAR, Kick DNC/WAR, and Barney, Smalls,
and Achoo `/WHM`. Give every character at least twelve Echo Drops. Dolo needs
the `DualLastStandRanged` loadout to resolve to Rostam, Tauret, Death Penalty,
and Living Bullet, plus at least 48 Living Bullets in an equippable bag.

Load the profile before positioning; loading is inert. Put Tackle against a wall
with Rancibus faced into it, Kick at the rear, Dolo at ranged distance in the
rear arc, Barney within ten yalms of the frontline, and Smalls/Achoo 15-20
yalms behind. Preflight and controller output is advisory. Do not wait for an
ACK or PASS. When ready, use `//pt arm`; the runtime starts immediately and
sends one best-effort Flash pull while all other preparation remains
independent. A failed Flash does not retry as a gate or pause anything else.

PartyCombat owns only Tackle and Kick. Dolo receives one exact-ID local engage
request, without persistent target/facing/movement control, then independently
shoots or uses Last Stand according to his TP. Kick's Evisceration, Tackle's
Savage Blade, and Dolo's Last Stand are independent lanes; there is no ordered
skillchain, party-HP hold, support hold, or packet-confirmation transaction.
Smalls's debuffs, Achoo's Geo-Frailty, Barspells, enmity, and stuns are also
best-effort lanes and cannot authorize or block offense. Support characters are
never PartyCombat targeters.

The 1.1 adapter has no pretarget or precast filters. Manual target changes,
weaponskills, abilities, spells, ranged attacks, and emergency reactions always
remain available while armed. Use `//pt disarm` to stop automated requests and
PartyCombat while keeping the support profile and manual input live; `//pt arm`
resumes best-effort automation. The user still owns movement out of Noyade or
Fetid Eddies poison spheres and knockback correction. Rancibus's hidden HP
display is never used.

## Kammavaca party farm

The `kammavaca` profile is a regular six-character physical strategy, not a
copy of the linked BLU-solo testimonial. It deliberately reuses only reviewed
controller surfaces: Dolo's `DualSavage`, Tackle's `Naegling`, Kick's `Tauret`,
the generic BRD physical song preset, the generic protected magic-boss RDM core,
and the generic DNC/GEO support modes. The fight logic lives only in this
profile's runtime. GearSwap remains the sole owner of all equipment and of
Barney's instrument selection.

Use these subjobs:

- Barneystinson: BRD/WHM for Barsilencera, Erase, and backup cures.
- Smalls: RDM/WHM is preferred for recovery. RDM/BLM remains optional only
  when emergency Sleepga or Stun matters more.
- Achoo: GEO/WHM for a second cure/NA surface.
- Dolomedes: COR/DNC preferred; COR/NIN remains accepted.
- Tackleberry: PLD/WAR. Kickpuncher: DNC/WAR.

The required order is **Clionid -> Limule -> Murex -> Amoeban ->
Kammavaca**. Version 1.2 implements that order as a bounded, fight-local state
machine rather than a shared PartyCombat priority. Dolo and Kick use automatic
single-target weapon skills. Tackle and Achoo engage each exact forced target
with AutoWS2 Off so tank and offensive-Geomancy behavior work without choosing
a weapon skill. Barney and Smalls are target-only observers.

A normal pull is automatic after setup:

1. Run `//pt preview kammavaca`, then `//pt use kammavaca`. `//pt check` can
   report lenses, Kammavaca's binding on Dolo, Echo Drops, reviewed melee
   weapons, Dolo's ranged slot, and the fight's spell/ability toolkit, but its
   result and the ACK count are advisory only. Activation turns native
   auto-target Off on responding clients. Do not use `//pt arm` for the normal
   opener.
2. Stack the pack within Barney's Horde Lullaby radius and pop. Before a
   claimed encounter, Barney maintains Barsilencera. Once exact-name
   Kammavaca is party-claimed, Smalls submits one exact-ID Silence reservation
   to his GearSwap priority queue. Silence is best-effort and never delays
   combat. Stymie and Saboteur are not spent automatically.
3. The runtime accepts an exact add only when party-claimed, or when unclaimed
   with valid coordinates within 20 yalms of the active claimed Kammavaca. A
   foreign nonzero claim is always rejected. Target identity, claim, and the
   CLMA order drive automatic damage; ACKs, checks, Silence, and Sleep do not
   authorize it.
4. Any eligible add immediately supersedes a Kammavaca boss lock. Dolo forces
   the first living CLMA ID, then Limule, Murex, Amoeban, and finally the boss
   as each prior target dies. If Dolo drifts back to Kammavaca while an add is
   alive, the runtime reasserts that add under a bounded rolling throttle until
   Dolo's current target agrees. Never use AoE damage.
5. In parallel, PartyCombat selects the same first add on target-only Barney.
   After verifying Barney's current target, his normal GearSwap controller
   queues Horde Lullaby II against `<t>` as its next action. Sleep helps control
   the pack but is not a damage gate, and the runtime never sends a numeric
   target to a Bard song. Selection and queue attempts cool down and rearm, so
   a transient startup or distance miss does not require button-spam.
6. When no eligible add is visible, the initial boss-only path waits just 0.75
   seconds for entities to settle before forcing Kammavaca. Any add that appears
   later immediately takes priority. `//pt sleep` (or Barney's equivalent Alt-L)
   and `//pt silence` are the two queue-safe manual support fallbacks. The
   `//pt force` command deliberately bypasses the profile's target choice, so
   use it only after verifying the legal target.
7. Use `//pt off` on victory or immediately on loss of control. That stops the
   fight runtime and restores native auto-target On. `//pt disarm` alone leaves
   the profile active and is not the full emergency stop for this automatic
   encounter.

Confrontation clears pre-existing geomancy. Judge Fury, Frailty, and entrusted
Fend only after Achoo has re-established them post-pop. Horde Lullaby is
centered on Barney, so the opening stack must keep the adds within his effective
String-instrument radius.

All automatic spells and abilities still use ordinary game commands and pass
through normal GearSwap. The runtime has no equip, slot-lock, raw movement, or
instrument API. PartyCombat alone selects, approaches, and engages. Kammavaca
also explicitly turns off Achoo's native GearSwap AutoWS mode so an old local
toggle cannot leak Black Halo into the ordered add phase.

## September Ambuscade runbook

The September profiles are designed as one-attempt, hands-off combat policies.
They prebuff while inert and begin their exact-boss strategy when any named
profile member supplies one `//pt arm`; ACK and check output remains advisory.
After that edge, the profile owns the pull, food, engagement, target changes,
fight actions, skillchains, mechanic reactions, recovery holds, and shutdown.
The operator still owns entry and positioning.

Use these subjobs for the Cait Qutrub V1 profile:

- Dolomedes COR/NIN, Tackleberry PLD/NIN, Kickpuncher DNC/NIN,
  Barneystinson BRD/SMN, Smalls RDM/SMN, and Achoo GEO/WHM.
- Put Tackle at Bigwig's front and choose the pack's stationary hold point
  before arming. Keep Kick and Dolo in melee range on safe flanks—stationary
  PartyCombat will not walk Dolo in or generate ranged attacks for his TP—and
  Barney and Smalls plus both Cait Sith pets and every add inside Mewing
  Lullaby's effective area. Achoo remains free to maintain his luopan.
  Keep the support line inside song, roll, and cure range.
- Run `//pt v1-qutrub`, finish positioning, and run `//pt arm` once. Use
  `//pt check` beforehand only when its setup report is useful; do not wait for
  an ACK or PASS. Do not manually assist, switch targets,
  weaponskill, Silence, Dispel, Diaga, summon, Mew, or recast shadows.
- The automatic order is every Astrologer, every Tormentor/Tormenter, then
  Bigwig, repeated for the second wave. Astrologers receive exact-ID Silence
  and observed Ice Spikes receive exact-ID Dispel. Dolo, Tackle, and Kick
  maintain shadows; Barney and Smalls alternate packet-confirmed Mewing
  Lullaby every 31 seconds only while an add pack is alive, then the exact
  successful lane issues bounded Retreat while keeping Cait summoned. A
  missing Retreat result never holds the fight, and Release is not used. The
  adds are sleep immune; the intended effect is the documented TP reset.
  Achoo /WHM supplies an independent cure/status-removal lane while
  continuously maintaining Fury/Frailty. Boss damage pauses at the 80% and 30% spawn
  edges, during Perfect Dodge, and while Utsusemi: San still needs Diaga.
- After the second add wave dies and Bigwig reaches 30%, move Barney, Smalls,
  and Achoo beyond 16 yalms from Bigwig while keeping Smalls within 20 yalms of
  all three attackers. The profile announces this transition and holds combat
  until live coordinates prove it. It then lowers Dolo, Tackle, and Kick into
  a controlled 13-25% HP band, blocks unsafe legacy healing, uses exact Cure II
  rescues below 13%, and requires all three attackers' shadows before every
  final-phase skillchain. This movement is the only in-fight operator action.

Use this separate cooperative alternate when Cait Sith is unavailable:

- Dolomedes COR/NIN, Tackleberry PLD/BLU, Kickpuncher DNC/NIN,
  Barneystinson BRD/NIN, Smalls RDM/WHM, and Achoo GEO/WHM.
- Tackle's strategy Blue Magic set is Cocoon (1 point), Blank Gaze
  (2), Sheep Song (2), Geist Wall (3), and Jettatura (4): five spell slots and
  12 set points. Flash is a native PLD spell. The profile does not gate its
  start on this set, Cocoon, shadows, food, positioning, an ACK, or a diagnostic
  result; `//pt check` merely reports useful differences.
- Run `//pt v1-qutrub-nocait` while out of combat. The direct alias selects,
  arms, and starts non-hostile preparation automatically. It may bind the
  exact visible Bigwig, but it cannot assign combat, move an attacker, cast an
  enemy-targeted action, or place enemy-targeted geomancy before the pull.
  When buffs are ready, use Dolo to pull Bigwig roughly 10-15 yalms from its
  middle spawn toward the party-start side. The observed exact action, party
  claim, or Bigwig retaliation releases combat automatically. Ctrl-P or
  `//pt arm` from any member is only a reassert/rebind after Alt-P, `//pt
  disarm`, or a missed target. Alt-P stops encounter combat while the
  profile-local RDM support lane remains available; `//pt off` also deactivates
  that support. These are manual positioning choices rather than software
  prerequisites. Tackle does not pull Bigwig and is never included in broad
  boss synchronization.
- Keep Smalls ranged, ideally between the corner and middle so he can reach the
  current group. Achoo starts stopped but automatically joins each
  add focus, carrying Indi-Fury with him. PartyTactics never changes
  FastFollow; pause or redirect any existing follow state that would undo
  positioning. This is operator geometry, not an arm gate.
- There is no proximity-based enemy damage reduction. Bigwig may follow its
  current Dolo/Kick holder into the add focus; the holder attacks that focus
  with everyone else and is never assigned to stand in a corner. The initial
  10-15-yalm pull is convenience, not a required persistent split or a gate.
- Preparation is opportunistic and independent. Before the pull it includes
  food, shadows, defensive buffs, Reraise, and healing while everyone remains
  in place. After the pull, Smalls applies exact-subject Dia III before Dolo's
  one useful in-range Light Shot per focus; Tackle uses Cocoon, Crusade,
  Reprisal, and the exact-add PLD/BLU toolbox; Barney applies the fourth Minne
  when Clarion is available; and Achoo applies exact Frailty plus
  per-generation Entrust Indi-Wilt. On a three-add wave,
  Fortifying Wail triggers exact Blank Gaze only on Tackle's parked target and
  exact Smalls Dispel on the others; Geist Wall is reserved for one- or two-add
  packs. Failure or delay in one
  lane never holds another lane or party damage.
- With no adds, Dolo, Kick, and Barney attack Bigwig while Tackle and Achoo are
  explicitly stopped. On Normal, every boss attacker disengages when the first
  add appears. Tackle immediately anchors the first Tormentor, Achoo /WHM
  Flashes the Astrologer, and the Dolo/Kick nonholder anchors the second
  Tormentor. Every newly visible spawn restarts a 6.25-second encounter quiet
  interval; only after that interval do Dolo, Tackle, Kick, Barney, and Achoo
  all close on the same Astrologer-first focus. When no add remains, Tackle and
  Achoo stop and the boss trio resumes Bigwig. This repeats for recycled slots
  and later waves. It is bounded fight timing, never a readiness, result,
  geometry, or difficulty gate.
- The shared focus is part of the threat budget. Tackle and the Dolo/Kick
  nonholder each own one parked add plus the focus; the holder owns Bigwig plus
  the focus; Barney and Achoo receive only the focus. Bigwig counts toward
  Triple Reversal, so nobody is intentionally assigned more than two hostile
  targets. Bigwig's direct target is reviewed every five seconds, and a change
  transfers only the second parked add—not the common kill assignment. Direct
  melee/TP packets also maintain a live threat ledger: an observed three-foe
  convergence stops only that endangered combat lane while exact anchors
  recapture, then returns it to focus as soon as targets redistribute.
- AutoWS2 is the only automatic weaponskill owner: Dolo uses Last Stand,
  Tackle and Barney use Savage Blade, Kick uses Evisceration, and Achoo uses
  Black Halo only while directed to adds. Dolo, Kick, and Barney maintain
  Utsusemi from observed Copy Image count. On Normal, Tackle uses Flash and
  Blank Gaze on only his parked add; three-target Sheep Song, Geist Wall, and
  Jettatura are suppressed. Sentinel and Palisade are also suppressed during
  wave assembly so they cannot create pack-wide enmity. Triple Reversal from
  either Bigwig or an add adds a bounded Violent Flourish attempt without
  freezing other independent work. If the last Copy Image drops while Ni is
  unavailable, the local adapter immediately tries Ichi and keeps checking
  live recasts instead of waiting for the controller watchdog.
- Every Qutrub enemy is Sleep immune; Sheep Song is an enmity tool, not crowd
  control. A completed Astrologer Sleep/Sleepga cast instead schedules Curaga
  II from Smalls and then Achoo to wake slept party members. Smalls keeps
  HealBot status removal, but its free-running HealBot cure selector is off.
  The pinned adapter selects the exact lowest living in-range member through
  74% HP, chooses Cure III for ordinary yellow HP and Cure IV below 25%, and
  keeps that lane live before arm and after encounter finish. During combat,
  the runtime emits the same exact request and the adapter de-duplicates it;
  dead, missing, and known out-of-range targets are skipped. Timestamped RDM
  tactics coalesce while healing, preventing a stale post-recovery queue.
  Tackle provides a delayed, range-checked Cure IV backup only at 40% or below. A completed
  Convert reserves Smalls' next automatic casts for self-recovery through 90%
  HP; manual input is never filtered. Achoo's routine curing stays off so MP
  remains available for colures and offense.
- PartyStart may spend one immediate activation action, normally Composure.
  From the next automatic tick, Smalls uses one learned Shellra—or individual
  Shell if /WHM has no Shellra—then Protect on the five other living members
  before subsequent generic upkeep resumes. The immutable `sortieacuex`
  support core owns five Hastes, four Refreshes, four frontline Phalanxes,
  Gain-MND, Aquaveil, Reraise, and guarded Convert. Shared routine ticks wait
  at 30-34% MPP, while the core retains its conservative 20% Phalanx reserve.
  Both mages maintain spell Reraise. Dolo, Tackle, Kick, and Barney use the
  best eligible Reraise item found in Inventory, if any; missing items never
  block arming or fighting.
- Manual targeting, movement, melee, ranged attacks, weaponskills, spells, job
  abilities, cures, and recovery remain available throughout. The controller
  reasserts only an attacker who reached an assigned add and later separates
  by more than 4.5 yalms, and only once per separation episode. A parked add
  observed on the wrong target likewise gets one bounded owner recapture; no
  polling target-snap loop is created. GearSwap alone owns equipment and
  instruments.

Use these subjobs for Hydra V2:

- Dolomedes COR/DNC or COR/NIN, Tackleberry PLD/WAR, Kickpuncher DNC/WAR,
  and Barneystinson, Smalls, and Achoo /WHM.
- Put Tackle in front, with Kick and Dolo in melee range on safe flanks rather
  than behind. Dolo needs melee swings to generate Last Stand TP; this profile
  does not automate ranged attacks. Keep every support outside the rear
  Serpentine Tail line while
  remaining in cure/song/roll range.
- Run `//pt v2-hydra`, finish positioning, then run `//pt arm` once. An
  optional `//pt check` can expose setup differences but cannot stop the pull.
  The profile handles the PLD pull,
  Evisceration -> Savage Blade -> Last Stand Light transactions, Thunder IV
  bursts, stuns, Bulwark mode changes, cures/status-removal priority, hate
  refresh, and victory/wipe shutdown.

All September profiles use Grape Daifuku only when the local attacker has no
Food; the no-Cait add-only PLD is deliberately not food-gated.
Clarion Call is automatic and opportunistic: when ready it adds the profile's
fourth song, but cooldown or a failed extra song can never block the pull or a
repeat attempt. The no-Cait profile enables exact-target AutoWS2 for its five
attackers; the Cait and Hydra profiles retain their own compiled offense
policies. No pinned adapter has an equipment surface: normal GearSwap remains
the only owner of weapons, ammunition, action sets, and Barney's instruments.

The cooperative no-Cait profile may begin on Very Easy as a live smoke test;
the other September profiles retain their own progression notes. Promote only
after a run confirms correct targeting/mechanic responses, stable survival and
MP, and adequate clear pace. Each profile observes live entities and uses the
same logic at every tier; difficulty does not select a different
code path. Use `//pt off` for a universal emergency stop. A completed, aborted,
or disarmed attempt consumes its arm edge, so the next pull always requires a
fresh `//pt arm` after positioning.

Passive post-fight work is specified in
[POSTFIGHT_ANALYSIS.md](docs/POSTFIGHT_ANALYSIS.md). Phase 0 deliberately does
not put file I/O or a log parser in the combat controller. Capture one PartyOps
session per attempt, preserve losses as well as clears, and record the selected
profile plus VE/E/N/D/VD. Existing BattleLab can inspect the exported session;
the checked-in `analysis_spec.json` sidecars define encounter signals and
metrics for the future profile-aware reducer. Until that reducer is connected, these
sidecars are an analysis contract, not a claim that a finished automated report
already exists.

## EasyFarm ownership

PartyTactics never starts, stops, or rewrites EasyFarm. Locus and Limbus each
own a separate reviewed artifact beside their own `profile.lua`, with matching
declarative metadata. Load the selected fight's artifact manually on
Tackleberry:

- Locus uses
  `profiles/locus-dire-bats-tomb/easyfarm/Tackleberry-Locus-Dire-Bats-Stationary.eup`.
  It has one exact target, `Locus Dire Bat`, an 18-yalm detection radius, a
  20-yalm Flash pull, and approach disabled.
- Limbus uses
  `profiles/limbus-119-stationary/easyfarm/Tackleberry-Limbus-119-Stationary.eup`.
  It has the reviewed 14-name Limbus allowlist (Om', Uptala, and Apollyon), the
  whole-word Elemental ignore rule, the same 18/20-yalm detection/Flash
  boundaries, and approach disabled. It contains no Apex or Locus XP-camp
  target.

These fight-local allowlists are a separate safety boundary from PartyCombat's
target exclusions. If a route needs another enemy, clone a new profile-owned
artifact and review it instead of broadening a file shared by two fights.

The `locus-dire-bats-tomb-signet` derivative is intentionally outside this
EasyFarm list. It uses LocusPuller exclusively; do not run the ordinary Locus
EasyFarm artifact at the same time.

## Dynamis-D Wave 1 paired workflow

The route and boss are deliberately separate profiles. This gives the route a
hard five-client inactivity boundary and gives the boss a fresh six-client
commit with manual weapon-skill ownership:

```text
//pt use ddw1route
//pt force                  (Dolo manually at range, intended statue selected)
//pt disarm                 (after each statue)
//pt use ddw1boss
```

The route policy is stationary: `force` engages and faces Dolo at his manually
chosen ranged position, but PartyCombat cannot walk him into melee before
Leaden Salute. The boss activation maintains Samurai/Wizard rolls,
March/Minne/Ballad III,
RDM defensive magic and healing, Acumen/Malaise, PLD healing/hate, and DNC
emergency Waltzes. It leaves PartyCombat and both attacker AutoWS2 instances
off. The fourth song is explicit and guarded:

```text
//pt clarion
//pt ballad2                (refused unless Clarion Call is active)
```

The pull and chain are likewise explicit; native PLD buff/tank automation is
off in this profile so it cannot reorder them. Use `crusade`, `emblem`, manually
move Tackle in for one autoattack, and use `sentinel`; then `arm`, allow the
puller authority message to arrive, and use `flash`. That post-arm Flash is
what synchronizes the boss. Thereafter use `flash` and, on PLD/WAR, `provoke`
for manual hate. The chain is `cdc`, `leaden`, and `wildfire`.
`rudra` is the documented fallback opener and `blizzard` is an optional
magic-burst request. See the profile's `research.md` before entry; local files
do not prove that Tackle has CDC or Kick has Rudra's Storm unlocked.

After installing this version, run the supplied staggered reload only while out
of combat. It reloads the four changed GearSwap clients one at a time and then
PartyTactics on all six; it does not activate or arm a profile:

```text
//exec reload_dynamis_w1_safe.txt
```

## Activation isolation and diagnostics

An activation uses a bounded prepare/commit exchange so one profile cannot
silently replace another profile's code or identity. Responding clients compare:

- PartyTactics engine version;
- profile id, semantic version, and complete behavior fingerprint;
- the declared six-character party roster;
- each local main job and any recommended/declared subjob;
- required manual-action adapters; and
- when declared, the exact GearSwap adapter id, version, controller, protocol,
  and finite semantic-action allowlist.

Version, signature, identity, or leader conflicts reject only the incompatible
response. Missing clients, job/setup differences, controller probes, inventory,
equipment, and buffs are reported as observations. After the bounded window,
compatible available clients apply their own assignments; there is no six-client
permission barrier.

The behavior fingerprint is broader than the version string. It hashes the
canonical declarative manifest, `profile.lua` source, optional `runtime.lua`
source, any declared profile-owned EasyFarm artifact, the complete compiled
six-member command plan, each manual adapter the profile actually uses,
PartyTactics and its libraries, PartyCombat, AutoWS2, Roller2, HealBot, and the
frozen common GearSwap compatibility surfaces. The distributed/live
`PartyTactics_Host.lua` pair is in every profile closure because its dormant
wrapper is in every job's callback path. For a profile that declares a
`gearswap_adapter`, its closure additionally contains that exact adapter
id/version on both sides. Unselected adapter ids and sibling versions are not
part of that profile's fight behavior. A missing declared EasyFarm artifact
remains a profile-local catalog error. Missing or different live hosts,
adapters, and frozen helpers are visible setup warnings: they do not quarantine
a valid profile or block unaffected lanes. A client with different executable
behavior or fight-local pull data can be skipped without changing a healthy
peer or the previously selected profile on that client.

A rejected client keeps its current local state. After the bounded exchange,
each compatible client removes its prior PartyTactics-owned state and applies
only its own compiled assignment. PartyCombat remains unarmed. PartyStart is
not consulted and should remain unloaded.

Application ACKs are status reports, not permissions. A client ACKs after
applying its local assignment; zone or Level Sync reapply advances the epoch so
the display distinguishes old reports from current ones. `//pt arm`, `//pt
force`, and manual actions never wait for an ACK. A leader state beacon lets a
reloaded client rejoin without restarting a healthy peer.

A job change pauses that local runtime; a runtime callback failure pauses only
that callback method. Neither stops healthy peers. Runtime deactivation is
idempotent and runs during replacement, stop, job change, reapply, and add-on
unload so a profile can restore a narrow client preference exactly once. Zoning
and Level Sync stop local combat and reapply the local assignment after the
party table settles. The leader publishes an idempotent state beacon so a
single reloaded client can safely rejoin the current generation.

Target exclusions are also complete profile state, never a sticky global
default. Every profile must explicitly declare `combat.target_exclusions`,
including `{}` for none. Limbus alone currently declares `elemental`; the
compiler sends that policy to both PartyCombat and AutoWS2 on all six clients.
Every other profile explicitly sends an empty PartyCombat exclusion policy and
`aws2 exclude none`, so the Limbus filter cannot leak into another fight. The
Elemental match is a living-enemy, whole-word match and does not reject names
such as `Elementalist`.

## GearSwap ownership contract

Profile files cannot contain raw setup/teardown commands. Encounter runtimes
do not receive `send_command`, `equip`, or slot-control access. Their API is
limited to typed spell/ability/item/WS requests and calls to narrow reviewed
GearSwap controller surfaces. A runtime may also request an exact validated
PartyCombat force, target-only observation, or local one-shot engagement by
numeric server ID, toggle only the local native auto-target preference, and
read the current target and local six-member party's claim ownership. The
one-shot engage creates battle state without persistent target, facing,
movement, retry, or re-engagement ownership. Those narrow operations expose no
raw command surface. Profile, runtime, and manual-adapter chunks also
run in a restricted environment without Windower, file, module-loader, debug,
or mutable standard-library access. For example, V1 may request:

```lua
ctx.actions.controller('brd', 'warble', ability.id)
```

New fight-specific GearSwap behavior uses the stable host instead of extending
a shared callback wrapper. The profile pins the host-facing adapter metadata,
and its runtime can request only one of that declaration's finite semantic
actions through `ctx.actions.party_adapter(character, semantic, target_id)`.
An action may optionally name a distinct exact add/mechanic target as the fifth
argument: `party_adapter(character, semantic, encounter_id, token, subject_id)`.
The original encounter ID remains the authority boundary; the pinned adapter
must independently validate the subject and its relationship to that encounter.
The compiler activates only the pinned id/version and tears it down with
`gs c ptgs off`. Every adapter-free plan also sends `gs c ptgs off` before
starting its support presets, recovering safely from an adapter left active by
an earlier coordinator crash or reload. The host remains dormant before
activation and after teardown,
chains the pre-existing native callbacks exactly once, and reports a missing,
malformed, mismatched, or faulting adapter as a local setup problem. That lane
may fail, but it does not disable the profile or another client. The adapter
cannot load a different fight or change another profile's helper.

A new or rebuilt cooperative adapter is a fixed, bounded action dispatcher. Its
pretarget and precast hooks do not consume manual input, and one delayed,
unavailable, interrupted, resisted, or failed automated request cannot suspend
another lane. Older adapter versions remain untouched as historical behavior;
improving one profile means adding a new version and changing only that
profile's pin.

An encounter may similarly request
`ctx.actions.controller('rdm', 'silence', enemy.id)`. The action API accepts
only a uint32 ID and exposes no arbitrary RDM command. Smalls's controller
revalidates that exact live, party-claimed enemy, reserves the next legal action
even if routine upkeep is disabled, and owns bounded retry/completion handling
through the normal GearSwap cast path. The `rdm-exact-silence` manual adapter
adds an exact-name whitelist and party-claim check before issuing this request.

GearSwap still decides which instrument and every other item to use. The
regression suite rejects equipment APIs and checks every compiled Barney plan
for range/ammo, direct-equip, and slot-lock leakage. The Dynamis fourth-song
request is allowed only while the Clarion Call buff is locally confirmed.

Protect-first RDM behavior and the coordinator-managed GEO heartbeat are
isolated opt-ins. PartyTactics selects `locusbats-protect`, `limbus-protect`,
`ambuscade-v1-protect`, or `magicboss-protect` without changing the legacy
preset with the unsuffixed name. `leanmanaged` and `leanrrmanaged` add guarded
colure maintenance only for profiles that select them; teardown restores the
safe `CombatEntrustOnly` default. Genmei selects reviewed generic presets;
every Genmei-only BRD/RDM/PLD action remains inside its pinned adapter. These
boundaries keep an improvement for one fight from silently changing an old
profile or Barney's native instrument path. The migrated profiles' historical
`PartyStart_*` GearSwap helpers are frozen compatibility dependencies; they do
not require the PartyStart add-on and must not receive new fight logic. Genmei
2.7.0's coordinated actions live only in its pinned versioned adapter; 2.1.0
through 2.6.0 remain unchanged historical files.

Attack authorization and offense declaration are deliberately independent. A
member outside PartyCombat's attacker list may declare an offense entry only
with `automatic=false`. If that member is also outside the targeter list, the
entry is loadout-only: it selects the reviewed GearSwap weapon mode and keeps
AutoWS2 Off without making PartyCombat move, face, target, or engage the member.
Genmei uses this for Dolo before its runtime issues two bounded startup engage
edges and exact-ID ranged actions. A target-only member may instead receive a later typed
action while PartyCombat still leaves engagement to the operator.

## Adding a fight

Read [PROFILE_CONTRACT.md](docs/PROFILE_CONTRACT.md), then copy the closest
existing profile into a new uniquely named directory. The optional scaffold
script creates a copy without modifying its source profile:

```powershell
.\tools\New-PartyTacticsProfile.ps1 `
  -Id 'new-stable-fight-id' `
  -Label 'Readable fight name' `
  -From 'limbus-119-stationary'
```

Research belongs beside the code in `research.md`. Profile-specific event
logic belongs in that directory's optional `runtime.lua`; it must use the
typed context API. Reusing a reviewed controller preset needs no shared-code
change. If a new fight needs GearSwap-side reservation or callback behavior,
declare a unique `gearswap_adapter` id/version and create that exact adapter
under `gearswap/adapters/<id>/<version>.lua`; do not add the fight to a frozen
compatibility helper or another profile's adapter.

Append the new profile's canonical id, public aliases, and PartyCombat policy
id to `data/profile_registry.lua` using the next ordinal. Existing registry
entries are immutable and must never be edited or reordered.

Declare `combat.target_exclusions` even when it is empty. If a target-only
observer needs a manual weapon skill, give that observer an offense policy with
`automatic=false`; never add the observer to `attackers` merely to make the
schema pass. If a fight needs EasyFarm, keep the reviewed `.eup` under that
profile's `easyfarm/` directory, declare its operator/target/range metadata,
and load it manually. PartyTactics validates the declaration but does not own
the external add-on's running state.

Run the complete regression suite after any profile or shared-adapter change:

```powershell
.\tests\run_tests.ps1
```

The suite parses every Lua file, compiles all profiles independently, checks
the equipment boundary, simulates the six-client activation protocol, and
verifies that a rejected new activation leaves the active fight untouched. Its
IPC simulation deliberately provides no sender loopback, matching Windower's
inter-process behavior.

## Safe reload

Run the supplied staggered reload only while all six characters are out of
combat:

```text
//exec reload_partytactics_safe.txt
```

The script first stops the active tactic, then reloads PartyCombat and AutoWS2
in their inert states on all six clients, reloads all six GearSwap clients one
at a time, and finally reloads PartyTactics on all six.
It contains no `pt use`, `pt arm`, `pc on`, or `pc force`, so it cannot select
a fight or begin combat. Afterward, run `//pt preview`, `//pt use`, position,
and arm manually. ACK output is available for diagnosis but is never a wait
condition.

For the Genmei automation revision, the scoped inert reload repairs
PartyCombat on all six, reloads all six GearSwap job files containing the
stable host include, and then reloads PartyTactics on all six:

```text
//exec reload_genmei_preflight_safe.txt
```

That legacy filename describes the original reload use, not a Genmei 2.3 gate.
The reload returns inert. Then use `//pt genmei`, position and target, and press
Ctrl-P or run `//pt arm`; no ACK or preflight wait is required.

The Kammavaca v1.2 integration reload stops the active tactic, reloads
PartyCombat's typed ID surfaces on all six clients, reloads Barney's universal
current-target sleep queue and Smalls's exact-ID RDM priority queue, then
reloads PartyTactics on all six. Every component returns inert; the script does
not select a profile or arm combat:

```text
//exec reload_kammavaca_safe.txt
```

The paired auto-target helpers remain only as inert standalone repair tools when
no profile is active:

```text
//exec kammavaca_autotarget_off.txt
//exec kammavaca_autotarget_on.txt
```

They change only FFXI's native auto-target preference on the named six clients.
Do not run either during an active Kammavaca profile. The v1.2 runtime turns
auto-target Off at activation and restores it On at deactivation; its lifecycle
is the authoritative normal path.

## Attribution and dependencies

PartyTactics includes versioned copies of the PartyStart GearSwap helpers.
Their headers identify integration with **Selindrile's GearSwap framework**
and credit **Motenten's** base files as that framework's foundation.  Those
headers state that upstream GearSwap source is not redistributed in the
controllers.  The framework remains a user-supplied dependency.

PartyCombat and the companion addons remain separate components with their
own authorship and license notices.  PartyTactics coordination does not
transfer ownership of those projects.  The addon license is in `LICENSE`;
retain any component-specific notices alongside it.

Framework: <https://github.com/Selindrile/GearSwap>

## Stopping and recovery

`//pt off` shuts down the active PartyTactics generation, pending local commit,
and every exact undecided replacement/reapply generation the caller has
observed, then stops PartyCombat. Stop packets tombstone those exact nonces, so
even a delayed prepare or commit cannot resurrect automation; they do not
numerically fence an unrelated future load. It does not change FastFollow or rewrite
EasyFarm settings. It deactivates the selected GearSwap adapter through the
stable host; it never loads or hands control to PartyStart.

For a lifecycle-authorized profile such as Locus Signet, an explicit fresh
load or `//pt reapply` first retires any different same-profile generation
still held by each local client, then authorizes its successor. This repairs a
peer that missed an earlier stop. Automatic recovery after a raw GearSwap or
SignetKeeper reload remains a separate bounded handoff and does not retire its
predecessor before the successor is authorized. Missing controller proof is
reported once after ten attempts; automatic lanes stay OFF while low-rate
retries continue, so a slow but valid helper can still recover unattended.
