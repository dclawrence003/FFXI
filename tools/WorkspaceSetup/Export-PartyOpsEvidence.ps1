[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][DateTimeOffset]$StartedAt,
    [Parameter(Mandatory=$true)][DateTimeOffset]$EndedAt,
    [string]$PartyOpsRoot = (Join-Path $env:USERPROFILE 'Documents\Tesseract\FFXI\projects\FFXI-Private'),
    [string]$OutputRoot,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
if ($EndedAt -le $StartedAt) { throw 'EndedAt must be later than StartedAt.' }
if (($EndedAt - $StartedAt).TotalMinutes -lt 1) { throw 'The existing PartyOps exporter requires at least one minute.' }
if (($EndedAt - $StartedAt).TotalMinutes -gt 90) { throw 'Choose one incident window of at most 90 minutes. Split longer investigations into bounded windows.' }
$toolchain = Get-Content -Raw -LiteralPath (Join-Path $PartyOpsRoot 'toolchain.json') | ConvertFrom-Json
$node = Join-Path $PartyOpsRoot ".tools\node-v$($toolchain.node.version)-win-x64\node.exe"
$entry = Join-Path $PartyOpsRoot 'apps\hub\dist\p12\long-session-export-entry.js'
$exporter = Join-Path $PartyOpsRoot 'scripts\export-p12-long-session.ps1'
foreach ($path in @($node,$entry,$exporter)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing prerequisite: $path. Build PartyOps using its documented pinned toolchain first." }
}
$actual = (& $node --version).Trim()
if ($LASTEXITCODE -ne 0 -or $actual -ne "v$($toolchain.node.version)") { throw 'PartyOps pinned Node version mismatch.' }
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $PSScriptRoot ('reports\evidence-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$arguments = @{
    OutputRoot=[IO.Path]::GetFullPath($OutputRoot); ShardMinutes=30; SkipBuild=$true
    WindowStartedAt=$StartedAt.ToUniversalTime().ToString('o')
    WindowEndedAt=$EndedAt.ToUniversalTime().ToString('o')
}
Write-Output 'Uses the existing PartyOps parser/exporter; no new parser, build, Hub restart, or client commands.'
$arguments | ConvertTo-Json
if (-not $Run) { Write-Output 'Dependency preflight only; coverage NOT checked. -Run requires all current Agents and a window fully inside their shared current sessions. Historical sessions after reconnect are not supported here.'; return }
$statusPath = Join-Path $env:LOCALAPPDATA 'PartyOps\run\p4-attribution-status.json'
$stream = [IO.File]::Open($statusPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
try {
    $reader = [IO.StreamReader]::new($stream)
    try { $status = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
} finally { $stream.Dispose() }
$agents = @($status.current_session_health.agents)
if (-not $status.current_session_health) {
    $agents = @($status.agents | ForEach-Object { [pscustomobject]@{connected=$_.connected;session_id=$_.agent_session_id;started_at=$status.started_at} })
}
if (-not $status.fully_connected -or $agents.Count -lt 3 -or @($agents | Where-Object { -not $_.connected -or -not $_.session_id -or -not $_.started_at }).Count) {
    throw 'Existing exporter needs all current Agent sessions connected (at least three). Do not substitute missing capture with guessed evidence.'
}
$commonStart = @($agents | ForEach-Object { [DateTimeOffset]$_.started_at } | Sort-Object)[-1]
$availableEnd = [DateTimeOffset]$status.updated_at
if ($StartedAt -lt $commonStart -or $EndedAt -gt $availableEnd) {
    throw "Requested window is outside shared current-session coverage ($commonStart through $availableEnd). Historical-session selection must be implemented in PartyOps; silently clipping would misrepresent this incident."
}
& $exporter @arguments
if (-not $?) { throw 'PartyOps evidence export failed.' }
Write-Output 'Treat the export as private evidence. Recheck exported window/coverage/gaps: clients can reconnect during export. Success alone does not establish the requested incident was captured.'
