# Supplemental profile aliases

Each Lua sidecar adds optional operator-friendly names for exactly one profile.
Its filename (without `.lua`) and `target` must both equal that profile's
canonical id. These names do not modify `profile.lua` alias arrays or immutable
identity records.

Sidecars are sandboxed and quarantined independently. A shortcut is accepted
only when it is unique, does not collide with a PartyTactics command, canonical
id, immutable alias, established loaded alias, or any loaded profile's manual
action, and its canonical target survived all profile checks. Targets cannot be
other aliases.

Supplemental names are leader-local input conveniences. PartyTactics sends the
canonical id over IPC, so sidecar contents are intentionally excluded from
profile behavior signatures; a missing or malformed sidecar cannot disable an
established profile on another client.
