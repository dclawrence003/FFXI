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
    foreach ($test in @(
        'addons/LocusPuller/tests/test_runtime.lua',
        'addons/LocusPuller/tests/test_unload_runtime.lua'
    )) {
        $output = & $nodeExe $fengariCli $test 2>&1
        $output | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'stack traceback:') {
            throw "LocusPuller isolated Lua runtime test failed: $test"
        }
    }
} finally {
    Pop-Location
}

& $PythonExe -B (Join-Path $PSScriptRoot 'test_source_guards.py')
if ($LASTEXITCODE -ne 0) { throw 'LocusPuller source guards failed.' }
