#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$NodeExe, [string]$PythonExe = 'python')
$ErrorActionPreference = 'Stop'
$addonRoot = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent (Split-Path -Parent $addonRoot)
$tools = & (Join-Path $workspace 'tools/OfflineTests/Resolve-TestTools.ps1') -NodeExe $NodeExe -PythonExe $PythonExe
$nodeExe = $tools.Node
$PythonExe = $tools.Python
$fengariCli = $tools.Fengari
& $nodeExe $tools.Parser $addonRoot
if ($LASTEXITCODE -ne 0) { throw 'Lua syntax validation failed.' }

Push-Location $workspace
try {
    $output = & $nodeExe $fengariCli `
        'addons/JubileeKeeper/tests/test_runtime.lua' 2>&1
    $output | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'stack traceback:') {
        throw 'JubileeKeeper isolated Lua runtime test failed.'
    }
} finally {
    Pop-Location
}

& $PythonExe -B (Join-Path $PSScriptRoot 'test_source_guards.py')
if ($LASTEXITCODE -ne 0) { throw 'JubileeKeeper source guards failed.' }
