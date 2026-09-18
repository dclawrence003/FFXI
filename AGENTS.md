# FFXI project instructions

## Operator knowledge

For the owner's environment, locate the local FFXI knowledge folder before
substantive work.  Use an explicitly configured FFXI_KNOWLEDGE_ROOT, an
ancestor containing operations/current-state.md, or the sibling vault
../Tesseract/FFXI relative to the repository root.  Read these entry notes
and only relevant links:

- operations/current-state.md
- operations/codex-workflow.md

Read the vault parent's writing-style.md for documentation and commit
descriptions.  Record dated, confirmed operational changes in the existing
vault.  Do not reorganize shared Claude/OpenClaw policies or memory folders.
If the operator vault is unavailable, report that limitation; use repository
documentation for source-only work and do not invent current deployment state.

## Source and evidence

Work in this task's source folder.  The current-state note identifies the
active working folders; a folder name or old migration note is not authority
to overwrite another copy.  Preserve concurrent edits and untracked work.

PartyOps is the owner's separate private parser, journal, replay and evidence
platform.  Reuse it rather than creating a competing parser.  Keep private
journals, captures, credentials and operational records out of public commits.

Reproduce failures with actual affected components where possible.  Distinguish
simulated tests, installed files, loaded clients and observed game behavior.
The offline test entry is tools/OfflineTests/Invoke-Checks.ps1; its README
describes dependencies and limits.  Source work does not authorize live game
commands or deployment.

## Attribution

Describe project work as designed and directed by Don Lawrence, with code
developed using OpenAI Codex where that is accurate.  Preserve original
authors, copyright notices and licenses.  Distinguish original integration,
adaptation, patch and behavioral reference.  Check redistribution rights and
update THIRD_PARTY_NOTICES.md when publishing new inherited work.
