# SignetKeeper

Current version: **2.3.4**. The complete renewal transaction is replicated and
self-healing: phase edges, adapter suspend/resume, puller drain/release, census,
and reload request/start all have retries. Terminal aborts are one-way
broadcasts; receivers never rebroadcast teardown traffic.
No automatic lane is assumed restored from command submission. Every local
adapter acknowledges resume, all six current-cycle reports must show running,
and only then does Tackle receive and acknowledge the final puller release.
Internal combat holds use PartyCombat's silent local reconciliation path, so
repair traffic does not print or broadcast repeated disarm commands.

`SignetKeeper` is an inert-by-default companion for PartyTactics' isolated
Locus Dire Bat Signet profile. It has no PartyStart dependency. The pinned
profile adapter supplies the exact PartyTactics generation, apply epoch,
profile identity, version, leader, and six-name roster.
The binding also pins the requesting PartyTactics engine, controller protocol
`2`, and compiled profile signature, so a stop or recovery packet cannot be
borrowed from another plan. The private `__ackpt` query answers only for that
exact live generation/epoch and reports the binding metadata actually accepted;
it does not hardcode or infer a profile, adapter, or engine version.

Renewal is a cycle-tokened maintenance transaction, not a general combat
permission gate. On profile load, LocusPuller remains OFF until the first fresh
six-client census; PartyCombat, AutoWS2, support lanes, and manual actions are
not disabled by that startup hold.

1. If any member lacks Signet for two seconds, renewal begins. A member whose
   longer timer is still active participates in the barriers but never equips
   or uses the staff.
2. Tackleberry's bound LocusPuller stops acquiring targets, finishes any live
   fight, explicitly acknowledges the drain, and all six remain idle for two
   seconds.
3. Each pinned GearSwap adapter suspends only profile-owned automatic actions.
   Staff work cannot begin until fresh acknowledgments and reports prove all
   six adapters are suspended. Manual GearSwap actions remain available.
4. Each missing client disables main/sub, raw-verifies item ID `17583`, waits 42.5
   seconds from the latest uninterrupted equipped observation, and retries the
   item every 12 seconds until buff ID `253` is actually present. Main/sub
   ownership is reasserted every two seconds so a GearSwap reload cannot
   silently remove the lock. Decoded zero-charge staffs produce a rate-limited
   blocker instead of an endless item-command loop.
5. On each missing client, SignetKeeper asks GearSwap to reapply—not cycle—its
   current Weapons mode after Signet returns. It retries every two seconds and
   raw-verifies the main/sub item IDs for one continuous second. The captured
   pre-staff pair is the normal proof. If the selected mode changed during the
   Locus renewal, a different pair is accepted only after at least two GearSwap
   reapplies and a stable, occupied main and sub; an empty or unreadable sub
   remains unsafe. This exception is limited to the Locus profile. The keeper
   never names or equips the combat weapon itself. `//sk status` shows raw and
   expected main/sub IDs when investigating a paused restore.
6. Only after six fresh reports prove Signet and physical weapon restoration
   does every adapter restore and acknowledge its complete automatic baseline.
   The leader then repeatedly releases Tackle's puller. Tackle acknowledges the
   exact cycle, and the replicated census releases XP. The newest PartyTactics
   operator revision always wins; SignetKeeper itself never blindly sends
   `pc on`.

Every operator request is serialized by the PartyTactics leader. SignetKeeper
accepts only a newer authoritative revision, treats equal/same as an
idempotent replay, and rejects lower or equal/conflicting tuples. Periodic
PartyTactics state reapplies the local puller/hold side effect, so a dropped
transition converges without allowing an older ON to defeat a newer OFF.

Ctrl-P during drain only updates the desired operator state so the current
fight can finish normally. During the later full suspend/apply window, an ON
request is still remembered, but each client silently reconciles PartyCombat
OFF so the maintenance pause cannot be pierced; final resume honors the
remembered bit. Equal state repair produces no visible disarm line or stop IPC.

Every phase, report, puller-drain acknowledgment, adapter suspend
acknowledgment, and final resume carries the current renewal-cycle integer.
Delayed evidence from a prior renewal therefore cannot advance a later cycle
inside the same PartyTactics generation and apply epoch.

A standalone GearSwap job reload is treated as a full-policy recovery, because
loading only the adapter would omit the compiler's job modes, weapons, and
support setup. The affected helper sends an exact reload notice; the leader
coalesces simultaneous notices for 1.5 seconds and asks PartyTactics to recover
the exact old controller authority. PartyTactics creates and explicitly
authorizes one successor before its adapter may bind. A bare different-
generation/epoch-zero probe is never sufficient. PartyTactics itself carries
the live operator bit through recovery and honors later Ctrl-P/Alt-P changes;
SignetKeeper never schedules `pt arm` or a generic `pt reapply`. An active
staff timer safely restarts under the new authority.
The exact reload request and start are each relayed once by first receivers,
repairing a copy dropped at the leader or one follower without timers or a
second recovery authority. Expiry wakes a suspended adapter before cleanup.
The recovery request, reload relays, successor bootstrap, and final resume all
carry the same revision and bit and merge them monotonically. The same
authorization hook precedes an initial adapter arm; it is retained as
a short exact pending fence, so a stop that arrives before `armpt` still
tombstones that lifecycle generation instead of allowing a queued arm later.
If a reapply or delayed aftercast exposes the Signet staff in monitor state,
the keeper immediately starts an exact-cycle maintenance recovery: Tackle's
puller drains, the local profile adapter suspends AutoWS/support lanes, and
PartyCombat is held before GearSwap restoration retries. A replacement epoch
inherits the unfinished physical restoration instead of forgetting it. If the
raw pair was already restored but the predecessor adapter was still suspended,
the replacement epoch begins a fresh exact emergency cycle and proves its own
suspend/restore state before it may run. An ordinary drain remains distinct so
the current fight can still finish before the normal suspension barrier.

The staff may be in Inventory or any enabled Mog Wardrobe. A missing/depleted
staff, failed item use, or missing suspend/resume acknowledgment leaves only
the maintenance cycle paused and continues exact repair. If a required client
stops reporting for 30 seconds, the system instead wakes any suspended lanes
and retires automatic pulling. Neither path filters manual actions.

Windower IPC does not guarantee loopback to its sender. Therefore the exact
local `armpt` command is authoritative. PartyTactics' five-second local
adapter reconciliation supplies the authenticated `sk operator` control
lease on every client; matching `PARTYTACTICS1|state` messages remain a
secondary operator-state repair channel where loopback occurs. Generation
nonces are opaque: while bound, a different generation is
accepted only through the bounded full-reapply handoff at epoch zero; normal
detach admits any non-retired future nonce. Matching-identity higher epochs
are valid, while lower/conflicting epochs and exact retired tuples are ignored.
The GearSwap adapter returns suspend/resume proof through the exact local
`sk __adapter` bridge; SignetKeeper's own reports replicate that state across
its same-addon IPC channel.
The strict PartyTactics `stop` wire is validated against engine, profile,
version, signature, roster source, and its field-10 target generation; its
field-3 request nonce is never mistaken for the target.

Diagnostics and emergency release:

```text
//sk status
//send @all sk status
//sk off
```

`//sk status` retains the last terminal disarm/stop reason (including the
validated PartyTactics stop packet's reason field) and its exact local
generation/epoch after live state resets. A stop targeting an authorized
successor shows that target rather than the predecessor; if a validated stop
has no locally known epoch, the diagnostic displays `-` for the epoch. This is
in-memory diagnostic history, not a persisted recovery authority.

`//sk off` restores main/sub control through GearSwap, raw-confirms the physical
pair, then resumes an exact suspended adapter and broadcasts an authority-bound
emergency detach. A no-op restore remains a gear-only retry and never reopens
automation. Normal users do not run `armpt` or `detach`; PartyTactics owns both
commands.

Coordinator lease expiry, isolated client loss, zone, and logout wake an exact
suspended adapter only after physical restoration. A raw unload has no future
frame on which to verify an asynchronous gear change, so it wakes the adapter
only when the raw pair is already safe; otherwise it queues GearSwap recovery
and remains fail-closed. Raw addon unload performs only local restoration and
adapter cleanup; it emits no cross-client IPC while the Lua state is being
destroyed. A surviving client that misses a terminal packet remains suspended
until the bounded controller-lease/roster-state expiry retires it locally.
Each loaded keeper also presents a process-local monotonic instance token to
the pinned GearSwap adapter. If the adapter survived a keeper reload after any
renewal cycle, adapter 1.7 requests the existing full-profile recovery path;
that successor authority atomically rebases every client's cycle state instead
of weakening stale-cycle validation.
Exact profile stop or replacement remains terminal-off under the PartyTactics
lifecycle. While idle and unbound, SignetKeeper never claims or changes a staff
the user equipped manually.


## Project credit and license

Designed and directed by Don Lawrence.  Code developed with OpenAI Codex.

This project's original contributions use the BSD 3-Clause terms in `LICENSE`.
Existing upstream credits and third-party license notices remain applicable.
AI assistance is documented separately from ownership and upstream authorship.
