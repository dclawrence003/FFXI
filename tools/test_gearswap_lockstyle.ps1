param([Parameter(Mandatory=$true)][string]$NodeExe, [Parameter(Mandatory=$true)][string]$GearSwapRoot, [string]$BaselineDirectory)
$ErrorActionPreference = 'Stop'
$previousGearSwapRoot = $env:GEARSWAP_TEST_ROOT
$fengari = Join-Path $PSScriptRoot 'OfflineTests/node_modules/fengari-node-cli/src/lua-cli.js'
if (-not (Test-Path -LiteralPath $fengari)) { throw 'Initialize tools/OfflineTests first.' }
$lockstyleLibs = Join-Path $GearSwapRoot 'libs'

function Get-LockstyleTestFunction([string]$Path, [string]$First, [string]$Next) {
    $source = Get-Content -Raw -LiteralPath $Path
    $start = $source.IndexOf($First, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing function: $First" }
    $end = $source.IndexOf($Next, $start + $First.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Missing boundary: $Next" }
    return $source.Substring($start, $end - $start)
}

$lockstyleOriginalPath = $env:Path
$lockstyleOriginalSource = $env:GEARSWAP_TEST_LOCKSTYLE_SOURCE
$lockstyleOriginalSubjob = $env:GEARSWAP_TEST_SUBJOB_SOURCE
try {
    $env:GEARSWAP_TEST_ROOT = (Resolve-Path -LiteralPath $GearSwapRoot).Path
    $env:GEARSWAP_TEST_LOCKSTYLE_SOURCE = Get-LockstyleTestFunction `
        (Join-Path $lockstyleLibs 'Sel-Utility.lua') `
        'function check_lockstyle()' 'function check_food()'
    $env:GEARSWAP_TEST_SUBJOB_SOURCE = Get-LockstyleTestFunction `
        (Join-Path $lockstyleLibs 'Sel-Include.lua') `
        'function sub_job_change(newSubjob, oldSubjob)' 'function status_change('

    $result = & $NodeExe $fengari `
        (Join-Path $PSScriptRoot 'test_gearswap_lockstyle.lua') 2>&1
    $result | ForEach-Object { Write-Output $_ }
    # Fengari can return exit code zero even when Lua raises an error.
    if (($result -join "`n") -notmatch 'All lockstyle regression tests passed\.') {
        throw 'Lockstyle regression tests failed.'
    }
}
finally {
    $env:GEARSWAP_TEST_ROOT = $previousGearSwapRoot
    $env:Path = $lockstyleOriginalPath
    $env:GEARSWAP_TEST_LOCKSTYLE_SOURCE = $lockstyleOriginalSource
    $env:GEARSWAP_TEST_SUBJOB_SOURCE = $lockstyleOriginalSubjob
}
