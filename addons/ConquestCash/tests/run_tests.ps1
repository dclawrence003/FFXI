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
        'addons/ConquestCash/tests/test_model.lua',
        'addons/ConquestCash/tests/test_runtime.lua'
    )) {
        $output = & $nodeExe $fengariCli $test 2>&1
        $output | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'stack traceback:') {
            throw "ConquestCash isolated test failed: $test"
        }
    }
} finally {
    Pop-Location
}

$python = Get-Command $PythonExe -ErrorAction Stop
if ($python) {
    & $python.Source -B (Join-Path $PSScriptRoot 'test_source_guards.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'ConquestCash source-guard tests failed.'
    }
} else {
    Write-Output 'Python unavailable; source-guard tests skipped.'
}

Write-Output 'ConquestCash isolated test suite: PASS'
