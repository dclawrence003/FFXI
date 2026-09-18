# FFXIStatus

`FFXIStatus` is a read-only, repeatable health snapshot for the six-character
party. It combines:

- Windows `pol.exe` process presence and responsiveness
- PartyOps connection, login, zone, HP, target, and telemetry freshness
- Rolling exemplar-point rewards and EP/hour
- Live Signet buff ID `253` on every character
- InventoryCore San d'Oria conquest-point totals and freshness
- Currently equipped main weapon and equipment-telemetry freshness

Run from PowerShell:

```powershell
.\tools\FFXIStatus\Get-FFXIStatus.ps1
```

Machine-readable output is available for a future dashboard:

```powershell
.\tools\FFXIStatus\Get-FFXIStatus.ps1 -Json
```

The default rate window is 15 minutes. Override it with `-Minutes`, for
example `-Minutes 5`. The command reads existing local state only; it does not
send commands to Windower or modify PartyOps/InventoryCore. The hot PartyOps
status file is opened with Windows delete-sharing enabled so a status read does
not interfere with PartyOps' atomic status updates. A hub that is already
restarting gets a short reconnection grace period before being reported down.
