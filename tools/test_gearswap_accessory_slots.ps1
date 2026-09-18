param([Parameter(Mandatory=$true)][string]$NodeExe, [Parameter(Mandatory=$true)][string]$GearSwapRoot, [string]$BaselineDirectory)

$ErrorActionPreference = 'Stop'
$previousGearSwapRoot = $env:GEARSWAP_TEST_ROOT
$fengari = Join-Path $PSScriptRoot 'OfflineTests/node_modules/fengari-node-cli/src/lua-cli.js'
if (-not (Test-Path -LiteralPath $fengari)) { throw 'Initialize tools/OfflineTests first.' }
$accessoryGsRoot = $GearSwapRoot

function Get-AccessoryTestSource([string]$Path, [string]$First, [string]$Next) {
    $source = Get-Content -Raw -LiteralPath $Path
    $start = $source.IndexOf($First, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Missing source boundary: $First" }
    $end = $source.IndexOf($Next, $start + $First.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) { throw "Missing source boundary: $Next" }
    return $source.Substring($start, $end - $start)
}

$accessoryOriginalPath = $env:Path
$accessoryOriginalSource = $env:GEARSWAP_ACCESSORY_CORE
try {
    $env:GEARSWAP_TEST_ROOT = (Resolve-Path -LiteralPath $GearSwapRoot).Path
    $env:GEARSWAP_ACCESSORY_CORE = (
        (Get-AccessoryTestSource (Join-Path $accessoryGsRoot 'helper_functions.lua') `
            'function prioritize(' 'function toslotname('),
        (Get-AccessoryTestSource (Join-Path $accessoryGsRoot 'equip_processing.lua') `
            'function expand_entry(' 'function unpack_equip_list(')
    ) -join "`n"
    $testArgs = @((Join-Path $PSScriptRoot 'test_gearswap_accessory_slots.lua'))
    if ($BaselineDirectory) {
        $testArgs += (Resolve-Path -LiteralPath $BaselineDirectory).Path
    }
    $result = & $NodeExe $fengari @testArgs 2>&1
    $result | ForEach-Object { Write-Output $_ }
    # Fengari may exit zero even when Lua raises an error: require the final marker.
    if (($result -join "`n") -notmatch 'All accessory-slot regression tests passed\.') {
        throw 'Accessory-slot regression tests failed.'
    }
}
finally {
    $env:GEARSWAP_TEST_ROOT = $previousGearSwapRoot
    $env:Path = $accessoryOriginalPath
    $env:GEARSWAP_ACCESSORY_CORE = $accessoryOriginalSource
}
