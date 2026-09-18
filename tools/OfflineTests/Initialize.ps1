[CmdletBinding()]
param([Parameter(Mandatory)][string]$NodeExe)
$ErrorActionPreference = 'Stop'
$NodeExe = (Resolve-Path -LiteralPath $NodeExe).Path
if ((& $NodeExe --version) -ne 'v24.18.0') {
    throw 'Use Node 24.18.0, matching PartyOps toolchain.json.'
}
$npm = Join-Path (Split-Path -Parent $NodeExe) 'node_modules/npm/bin/npm-cli.js'
if (-not (Test-Path -LiteralPath $npm)) { throw 'Bundled npm was not found beside Node.' }
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package-lock.json'))) {
    throw 'Missing package-lock.json. Restore the reviewed dependency lock before setup.'
}
$previousPath = $env:PATH
Push-Location $PSScriptRoot
try {
    $env:PATH = (Split-Path -Parent $NodeExe) + [IO.Path]::PathSeparator + $previousPath
    & $NodeExe $npm ci --ignore-scripts --no-audit --no-fund --fetch-retries=0 --fetch-timeout=15000 --cache (Join-Path $PSScriptRoot '.npm-cache')
    if ($LASTEXITCODE -ne 0) { throw 'Offline test dependency installation failed.' }
} finally {
    $env:PATH = $previousPath
    Pop-Location
}
