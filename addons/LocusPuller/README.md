# LocusPuller

Current version: **2.1.9**. It retains the Lua 5.1-safe split dispatcher,
exact read-only PartyTactics binding proof, and PartyOps-calibrated distant
pull timing. Drain and final resume completion cross into the local
SignetKeeper command surface before SignetKeeper relays them to its matching
remote instances. Duplicate exact-cycle resume requests reapply the current
operator high-water and return a fresh acknowledgment.

Stationary Tackleberry-only pull helper for Locus Dire Bats. It never moves a
character. `standard` mode preserves the original standalone behavior: select
the nearest valid unclaimed/party-claimed Locus Dire Bat within 20 yalms, cast
Flash, then request engagement one second later.

PartyTactics' Signet profile uses an exact generation-and-epoch-bound
`firsthit` mode. It starts OFF. When the PartyTactics operator arms combat, the
puller asks the pinned `locus-signet` GearSwap adapter to establish its bounded
PLD routine gate before exposing the target. After the exact adapter
acknowledgment it selects the bat and casts Flash. Only a matching, non-failure
Flash result starts immediate `/attack on` retries. The gate and AutoWS2 are
released on the first melee packet or after a twenty-second fail-open timeout.
Target selection and every bounded engage retry turn Tackle toward the exact
bat, including one approaching from behind. Turning never invokes movement;
the helper contains no run or reposition command.
Command submission alone is not treated as a cast: LocusPuller observes the
exact outgoing `0x01A` magic packet for Flash on the selected bat and silently
reissues a swallowed local command every half-second for at most the first five
seconds. A blocked, wrong-target, or different action cannot confirm dispatch,
and the first matching packet stops every retry immediately. If the complete
eight-second attempt still expires, the 1.4/1.5/1.6/1.7 path reacquires on the next
polling edge instead of adding the standalone helper's historical two-second
reset delay.
The kill reward packet briefly excludes that exact dead bat ID/index from
target selection while its cached HP is still positive. A different live bat
can be pulled immediately; the exclusion expires after five seconds so a
later respawn is never permanently blacklisted.
PartyOps observed distant pulls taking as long as 16.462 seconds between Flash
completion and Tackleberry's first melee. The adapter's independent outer
reservation is thirty seconds, safely beyond the legal eight-second
Flash-confirmation plus twenty-second first-melee window.

Every failure, timeout, manual off/pause, and ordinary recovery unbind releases
the adapter gate and restores AutoWS2. Normal PartyTactics teardown, zone,
logout, and terminal reset use `keepoff`: they release ownership without
undoing the compiler's final AutoWS2-OFF policy. No first-hit path can suppress
routine PLD actions indefinitely.

SignetKeeper sends an exact `drain` request. LocusPuller stops new acquisitions,
allows the current fight to finish, and invokes the generation-bound local
`sk __pullerdrained GEN EPOCH CYCLE` bridge only when no opener remains and
Tackleberry is idle. Tackle's SignetKeeper validates that handoff and relays it
over SignetKeeper's same-addon IPC channel. If Flash has already been requested when drain
or Alt-P arrives, the opener is retained until its action result/timeout and any
resulting fight has ended; an idle ACK can never race a queued Flash. If Alt-P
arrives during a drain, pulling is disabled and the exact drain remains alive
until the idle acknowledgment; later resume does not re-enable pulling unless
the PartyTactics operator is still armed.
Operator transitions carry the leader-authored monotonic revision. Lower
revisions and equal/conflicting bits are rejected; equal/same replays safely
heal only the local enabled effect without resetting an opener, drain, pause,
or retry cadence. This makes a delayed ON harmless after a newer OFF.
Operator transitions observed during the transaction update the desired state
without cancelling the drain. Only SignetKeeper's exact final `resume` marker
finishes the mechanical pause after all six Signet confirmations. It applies
the puller's current high-water operator state: an older captured resume can
therefore complete the cycle, but can never defeat a newer Ctrl-P or Alt-P.
Each drain must be exactly the next cycle; jumps are rejected. A final resume
consumes its cycle. An exact duplicate repairs/acknowledges the already-current
state, while its stale operator snapshot can never change later state.

Standalone commands remain:

```text
//lp on
//lp off
//lp status
//lp now
//lp mode standard
```

While an exact PartyTactics profile is bound, `on`, `mode`, `resume`, and
`now` cannot bypass its Signet transaction. `off` remains an immediate local
emergency stop, and all ordinary FFXI spells, abilities, items, attacks, weapon
skills, targets, and movement remain manual and unfiltered. A rapid
authoritative OFF -> ON also preserves a Flash already submitted until its
action result or bounded timeout, preventing a duplicate pull.

`bindpt`, `operator`, `drain`, `unbindpt`, and the private gate acknowledgment
are adapter/coordinator commands and are rejected unless their generation and
epoch match the current PartyTactics binding. Drain and final resume also
require the exact positive renewal-cycle token. Same-authority `bindpt` and
`gsreload` are idempotent and preserve operator, drain, and opener state.
The private `__ackpt` query is also idempotent: it reports the profile, version,
engine, signature, name, and job actually bound only when its generation and
epoch match, without resetting any of those states.
Generation nonces are opaque. While bound, a different generation is accepted
only once after `gsreload` plus an explicit exact successor authorization at
epoch zero; the reload marker alone admits nothing. After normal unbind, any
non-retired future nonce may bind. Same-generation higher epochs
are accepted, while lower epochs and exact retired tuples are ignored without
resetting the current drain-cycle high-water mark. A still-live initial
authorization cannot be replaced by a conflicting reordered authorization.
Normal profile teardown uses the
exact `unbindpt GEN EPOCH keepoff` form: it releases any adapter gate but leaves
AutoWS2 OFF for the PartyTactics compiler's final teardown policy. Every
abnormal or fail-open exit still restores AutoWS2.

The private lifecycle wire is exact and metadata-pinned: `authorize` carries
`GEN EPOCH PROFILE_ID PROFILE_VERSION ENGINE SIGNATURE LEADER SIX_NAME_CSV`;
`bindpt` appends `OPERATOR_REVISION OPERATOR_BIT`; `operator` carries
`BIT GEN EPOCH REVISION`, with final maintenance resume appending
`resume CYCLE`; `retirept` carries `TARGET_GEN ENGINE PROFILE_ID
PROFILE_VERSION SIGNATURE SOURCE`. Surplus fields, a source outside the
pinned roster, and delayed stopped generations are ignored.

A raw LocusPuller addon unload is treated as recoverable helper loss: any
active opener is released normally and the exact SignetKeeper coordinator is
notified to abort/resume a drain or suspension. Zone and logout retain the
terminal `keepoff` behavior.


## Project credit and license

Designed and directed by Don Lawrence.  Code developed with OpenAI Codex.

This project's original contributions use the BSD 3-Clause terms in `LICENSE`.
Existing upstream credits and third-party license notices remain applicable.
AI assistance is documented separately from ownership and upstream authorship.
