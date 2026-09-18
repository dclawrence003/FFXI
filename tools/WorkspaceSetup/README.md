# FFXI workspace setup tools

These helpers connect existing work; they do not replace PartyOps.

- `Get-WorkspaceAudit.ps1`: read-only repository metadata and selected source/deployed file hashes. Writes a local JSON report. No fetch, staging, commit, push, reload, or game commands.
- `Export-PartyOpsEvidence.ps1`: preflight or invoke the existing PartyOps long-session exporter for one explicit UTC/offset-bounded incident in shared current sessions. Uses its pinned runtime and existing build. Does not rebuild or control clients. All current Agents must be connected (at least three); this does not support historical sessions after reconnect.
- `reports/`: ignored local output. Do not publish raw logs, session exports, or local machine audit files.

From the public source checkout:

```powershell
.\tools\WorkspaceSetup\Get-WorkspaceAudit.ps1
.\tools\WorkspaceSetup\Export-PartyOpsEvidence.ps1 -StartedAt '2026-09-17T13:00:00-04:00' -EndedAt '2026-09-17T13:10:00-04:00'
```

The second command only checks dependencies and prints the request, not capture availability. Replace the example dates with a relevant interval of 1-90 minutes. Add `-Run` to validate current-session coverage and export. A successful export is not proof of complete capture: inspect the actual exported windows and gap evidence, especially if a client reconnected during export. Disk hashes likewise do not establish loaded client versions.

Canonical operational guidance is in the local Tesseract `FFXI/operations/` folder. Current source still lives in `Documents/FFXI`; migration to the older Tesseract public checkout is pending reconciliation. Never delete either copy based on an old migration note.
