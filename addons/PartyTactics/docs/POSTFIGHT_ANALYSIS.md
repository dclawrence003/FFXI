# PartyTactics post-fight analysis contract

PartyTactics is the combat control plane. It must remain deterministic,
bounded, and free of combat-log file I/O. Passive observation, durable capture,
and offline reduction belong to PartyOps/BattleLab so a slow disk, malformed
packet, or failed exporter can never delay a cure, target switch, skillchain,
or mechanic response.

Each instrumented fight owns an `analysis_spec.json` beside its `profile.lua`.
PartyTactics deliberately does not load that file and does not include it in
the profile behavior fingerprint. The sidecar tells an offline reducer which
exact encounter identities and action IDs matter without coupling analysis to
live control behavior.

## Sidecar envelope

```json
{
  "schema": 1,
  "profile": {"id": "stable-profile-id", "version": "1.0.0"},
  "encounter": {
    "volume": 1,
    "boss_names": ["Exact Boss Name"],
    "add_names": ["Exact Add Name"]
  },
  "difficulty": {
    "operator_declared": true,
    "allowed": ["VE", "E", "N", "D", "VD"]
  },
  "signals": {
    "monster_ability_ids": [],
    "weapon_skill_ids": [],
    "spell_ids": [],
    "job_ability_ids": []
  },
  "metrics": ["clear_time"],
  "outcomes": ["clear", "wipe", "timeout", "abort"],
  "uncertainties": []
}
```

Names are exact English resource names. IDs are decimal integers from the
installed Windower resources or a recorded packet. An uncertainty is retained
until live evidence resolves it; combat safety must never depend on an
analysis-only inference such as Hydra head count.

## Initial capture procedure

Until PartyOps gains same-zone repeated-attempt segmentation, use one passive
capture and one export per Ambuscade attempt. Before entry, record the selected
profile, the operator-selected difficulty, and any deliberate manual deviation.
Export losses as well as clears. Never infer difficulty from enemy HP, damage,
or elapsed time.

The first progression sequence is Normal, Difficult, then Very Difficult.
Promotion is evidence-based: correct automation targets, required mechanic
responses, stable survival/MP, and adequate clear pace must all pass at the
current tier. The same profile handles every tier; add count and timing are
observed from live entities rather than copied into difficulty-specific code.

## Required correlations

The reducer should correlate three independent records:

1. PartyTactics intent: profile commit, application/preflight barriers,
   encounter authority, semantic queue request, stop, and fault.
2. Client execution: outgoing action request and incoming action/result packet.
3. Encounter result: spawn/claim/target transitions, damage, status, death,
   timeout, wipe, or abort.

A semantic request is intent, not proof. A response is counted successful only
when the corresponding server result is present. Every report should include
data-quality gaps, missing observers, dropped/decode-failed events, and any
interval in which a client was not represented.

## Core review metrics

- outcome, declared difficulty, clear time, phase/add-wave time, and downtime;
- target-switch latency, wrong-target actions, unengaged/out-of-range time;
- WS cadence/damage, skillchain confirmation and damage, magic bursts, hit rate;
- mechanic-ready to queued-action to server-result latency and success rate;
- shield/invulnerability waste, add spawn-to-control time, debuff landing time;
- cures, status-removal latency, lowest HP/MP, deaths, and recovery duration;
- required song, roll, geomancy, Protect, Shell, Haste, Refresh, and Reraise
  coverage; and
- queue retries/expiry, PartyTactics faults, and capture integrity.

The quarantined CombatRecorder is not part of this workflow and must not be
loaded on the six clients.
