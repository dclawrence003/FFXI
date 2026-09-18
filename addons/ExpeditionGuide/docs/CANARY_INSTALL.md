# Canary installation and reload

This procedure installs and tests ExpeditionGuide without adding an automatic
load, changing a key binding, selecting a PartyTactics profile, or automatically
spending a Sortie entry.

## 1. Copy only

Copy the complete source directory:

```text
C:\Users\DC03\Documents\FFXI\addons\ExpeditionGuide
```

to:

```text
C:\Program Files (x86)\Windower\addons\ExpeditionGuide
```

If a live ExpeditionGuide directory already exists, preserve it as a dated
backup before replacing it. Do not merge old `content/` or `lib/` files into a
new build; a whole-directory replacement prevents stale modules. Preserve the
live `data/` directory separately if its route state or calibrated landmarks
matter.

Do not edit Windower `init.txt`, character login scripts, Send startup scripts,
GearSwap files, or PartyTactics files. Copying is the complete installation
step; it does not load the addon.

## 2. Dolomedes-only canary

Be outside combat and outside Sortie. On Dolomedes:

```text
//lua load ExpeditionGuide
//exg status
//exg list
//exg start sortie-onboarding-core-live
//exg explain
```

Verify all of the following before loading another client:

- The HUD appears only on Dolomedes.
- The selected route says `LIVE`; the older `sortie-onboarding-core` route
  remains listed as `GUIDE ONLY`.
- `//exg status` says `leader`, route `sortie-onboarding-core-live`, and sensors
  `1/6` after a report cycle.
- No character moves, targets, engages, casts, interacts, or changes equipment.
- PartyTactics remains in its previous state; no profile is selected or armed.
- GearSwap, AutoWS2, FastFollow, EasyFarm, HealBot, and Roller2 are unchanged.
- `Ctrl-P` and `Alt-P` retain their existing behavior.

If any check fails, run `//lua unload ExpeditionGuide`, preserve the chat log,
and do not continue.

## 3. Sensor canary

Load one follower at a time, checking Dolomedes after each one:

```text
//send Tackleberry lua load ExpeditionGuide
//send Kickpuncher lua load ExpeditionGuide
//send Barneystinson lua load ExpeditionGuide
//send Smalls lua load ExpeditionGuide
//send Achoo lua load ExpeditionGuide
```

Wait at least two seconds between clients. A follower must not display a HUD.
Running `//exg status` directly on that client should identify it as a sensor.
Dolomedes' sensor count should rise to `6/6` within eight seconds after the last
load. The HUD must also show `PARTY 6/6` and `DOLO LEADER 1/1`; an alliance,
wrong member, missing member, or different leader must fail closed. If those
checks pass and all six already have a Shiny plate, the pre-entry step should
advance exactly once to `enter`; otherwise it must remain on `preentry`. After
advancing, deliberately changing any one prerequisite must show `ENTRY CHECK`
on `enter`, proving the prerequisite was not latched.

The files in `scripts/` contain the same explicit, staggered commands. They are
templates to copy into `Windower\scripts` and invoke manually; neither script
is an automatic startup hook.

## 4. Safe reload

Reload only while all six characters are outside combat. Pause the route first:

```text
//exg pause
```

Use `reload_expeditionguide_safe.txt` from Dolomedes after copying it into
`Windower\scripts`:

```text
//exec reload_expeditionguide_safe.txt
```

The script unloads and loads ExpeditionGuide one client at a time. It does not
touch PartyTactics or any service addon, and it does not start or resume a
route. The leader's persisted route should reload paused. Then verify:

```text
//exg status
//exg explain
```

Wait for sensors `6/6`. Resume only after the restored step is correct:

```text
//exg resume
```

When PartyTactics and the C profile changed in the same deployment, use the
combined `reload_sortie_onboarding_safe.txt` instead. It first stops combat,
pauses the guide, reloads PartyTactics and ExpeditionGuide on each client in a
staggered sequence, and finishes inert and paused. It never resumes a route or
forces combat:

```text
//exec reload_sortie_onboarding_safe.txt
```

## 5. Rollback

On Dolomedes, pause first. Then unload all six explicitly:

```text
//send Dolomedes lua unload ExpeditionGuide
//send Tackleberry lua unload ExpeditionGuide
//send Kickpuncher lua unload ExpeditionGuide
//send Barneystinson lua unload ExpeditionGuide
//send Smalls lua unload ExpeditionGuide
//send Achoo lua unload ExpeditionGuide
```

Unloading removes the HUD and sensor callbacks only. It does not stop, reload,
or reconfigure PartyTactics, GearSwap, or another addon. Restore the preserved
live directory if a code rollback is needed. Do not restore a newer state file
into an older route version unless that version is known to accept it.

## Phase 1 live-canary criterion

Offline tests establish that loading, sensing, persistence, the inert profile
transition, and operator controls are isolated. They do not claim that the map
geometry or Device C death radius is live-proven. The additive live route may be
run as a controlled canary with manual intervention available throughout; keep
the original guide routes and boss routes out of live combat scope. The
additive Sheet D canary is separately operator-started and never selected by
this installation procedure.
