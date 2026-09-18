# JubileeKeeper

Current version: **2.1.3**.

`JubileeKeeper` is an inert-by-default, Dolomedes-only companion for the
PartyTactics Locus Dire Bat Signet profile. It has no PartyStart dependency.

The pinned profile adapter binds it to an exact PartyTactics generation, apply
epoch, profile ID/version/signature, engine, leader, and six-name roster. While
bound, it finds `Jubilee Ring` (item ID `27593`) in Inventory or an enabled Mog Wardrobe, equips it in Dolo's
right ring slot, locks only `ring2`, verifies the raw equipped item, and
reasserts the lock once after an observed GearSwap reload or accepted profile
bind. Ordinary polling is silent once the verified lock is in place. The left ring is
never touched. The right slot remains owned through Signet staff maintenance.
An exact `gsreload` marker preserves and reasserts the raw guard during the
bounded full PartyTactics recovery. The marker alone authorizes nothing: the
new adapter must name the exact successor before its arm can replace the old
authority, and that accepted arm clears the grace.
Initial adapter authorization is likewise kept as a short exact pending fence,
so an authenticated stop can retire a queued generation before its arm arrives.

An exact adapter detach, a current/newer conflicting PartyTactics state,
zoning, logout, manual `//jk off`, or unloading JubileeKeeper releases ring2
and requests a normal GearSwap update. A stale previously observed PartyTactics
state also releases ring2, but retains the exact binding in a fail-closed hold;
it reacquires only after a fresh matching PartyTactics state and a matching
adapter `armpt` reassertion. Explicit stop and replacement still retire the
old binding.
Because Windower IPC does not guarantee sender loopback, the exact local
`armpt` command is sufficient to begin guarding; state liveness is enforced
only after this client actually observes a matching leader state.
Generation values are opaque nonces, so they are never numerically ordered.
While bound, only a matching-identity higher epoch or one different-generation
epoch-zero arm covered by an exact bounded successor authorization may replace the
guard. Normal detach leaves it unbound for any non-retired future nonce. Exact
retired tuples and lower/conflicting epochs are ignored. Every accepted arm
clears the superseded reload deadline.
PartyTactics `stop` is accepted only in the strict ten-field form, with the
pinned engine/metadata and roster source matching and field 10 targeting either
the currently owned generation or its explicitly authorized pending successor.
The private `__ackpt` query answers only for an exact live generation/epoch and
reports the binding metadata actually accepted; it never assumes a current
profile or engine version.

If Jubilee Ring is inaccessible, the slot remains under normal GearSwap
control and a throttled warning identifies the blocker.

Diagnostic:

```text
//send Dolomedes jk status
```

Users do not normally run `armpt` or `detach`; PartyTactics owns them.


## Project credit and license

Designed and directed by Don Lawrence.  Code developed with OpenAI Codex.

This project's original contributions use the BSD 3-Clause terms in `LICENSE`.
Existing upstream credits and third-party license notices remain applicable.
AI assistance is documented separately from ownership and upstream authorship.
