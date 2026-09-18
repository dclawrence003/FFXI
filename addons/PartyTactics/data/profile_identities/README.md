# Isolated profile identities

The first seven migrated identities are frozen in `../profile_registry.lua`.
Each later profile adds one `<profile-id>.lua` file here with the next ordinal,
its PartyCombat policy id, and its aliases. Do not edit or renumber an existing
identity. A malformed new file is quarantined without affecting older profiles.
