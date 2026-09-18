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
    $luaOutput = & $nodeExe $fengariCli `
        'addons/ExpeditionGuide/tests/test_expeditionguide.lua' 2>&1
    $luaOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($luaOutput -join "`n") -match 'stack traceback:') {
        throw 'ExpeditionGuide isolated Lua tests failed.'
    }

    $bossRouteOutput = & $nodeExe $fengariCli `
        'addons/ExpeditionGuide/tests/test_sortie_two_boss_route.lua' 2>&1
    $bossRouteOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or
        ($bossRouteOutput -join "`n") -match 'stack traceback:') {
        throw 'ExpeditionGuide Sortie two-boss route tests failed.'
    }

    $mainRouteOutput = & $nodeExe $fengariCli `
        'addons/ExpeditionGuide/tests/test_sortie_main_run.lua' 2>&1
    $mainRouteOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or
        ($mainRouteOutput -join "`n") -match 'stack traceback:') {
        throw 'ExpeditionGuide Sortie main-route tests failed.'
    }

    foreach ($scenario in @('leader', 'follower', 'no-player')) {
        $runtimeOutput = & $nodeExe $fengariCli `
            'addons/ExpeditionGuide/tests/test_main_runtime.lua' $scenario 2>&1
        $runtimeOutput | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or
            ($runtimeOutput -join "`n") -match 'stack traceback:') {
            throw "ExpeditionGuide mocked main runtime ($scenario) failed."
        }
    }

    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -ExecutionPolicy Bypass -File `
        'addons/ExpeditionGuide/tests/test_source_guards.ps1'
    if ($LASTEXITCODE -ne 0) {
        throw 'ExpeditionGuide source guards failed.'
    }
} finally {
    Pop-Location
}

Write-Output 'ExpeditionGuide isolated test suite: PASS'
