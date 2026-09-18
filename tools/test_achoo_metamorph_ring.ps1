param([Parameter(Mandatory=$true)][string]$NodeExe, [Parameter(Mandatory=$true)][string]$GearSwapRoot, [Parameter(Mandatory=$true)][string]$BaselineDirectory, [Parameter(Mandatory=$true)][string]$GearFile)

$ErrorActionPreference = 'Stop'
$previousGearSwapRoot = $env:GEARSWAP_TEST_ROOT
$fengari = Join-Path $PSScriptRoot 'OfflineTests/node_modules/fengari-node-cli/src/lua-cli.js'
if (-not (Test-Path -LiteralPath $fengari)) { throw 'Initialize tools/OfflineTests first.' }
$metamorphLive = $GearFile
$metamorphBaseline = Join-Path (Resolve-Path -LiteralPath $BaselineDirectory).Path 'Achoo_GEO_Gear.lua'

function Get-MetamorphGearSnapshot([string]$Path) {
    $output = & $NodeExe $fengari `
        (Join-Path $PSScriptRoot 'validate_gearswap_runtime.lua') $Path '-' '-' 'dump' 2>&1
    if (($output -join "`n") -notmatch 'runtime-ok:') { throw "Profile failed to load: $Path" }
    $snapshot = @{}
    foreach ($line in $output) {
        if ([string]$line -match '^set-item\t([^\t]+)\t(.+)$') {
            $snapshot[$Matches[1]] = $Matches[2]
        }
    }
    return $snapshot
}

$metamorphOriginalPath = $env:Path
try {
    $env:GEARSWAP_TEST_ROOT = (Resolve-Path -LiteralPath $GearSwapRoot).Path
    $before = Get-MetamorphGearSnapshot $metamorphBaseline
    $after = Get-MetamorphGearSnapshot $metamorphLive
    $expected = @{}
    $metamorphSetPaths = @('sets.precast.WS', 'sets.precast.WS.Black Halo',
        'sets.MagicBurst', 'sets.RecoverBurst', 'sets.defense.NukeLock',
        'sets.midcast.Elemental Magic', 'sets.midcast.Elemental Magic.Resistant',
        'sets.midcast.Elemental Magic.DT', 'sets.midcast.Elemental Magic.Proc',
        'sets.midcast.Elemental Magic.HighTierNuke', 'sets.midcast.Elemental Magic.HighTierNuke.Resistant',
        'sets.midcast.Elemental Magic.HighTierNuke.DT')
    foreach ($spell in @('Cure','LightWeatherCure','LightDayCure','Curaga','Dark Magic','Drain','Aspir','Impact','Dispelga')) {
        $metamorphSetPaths += "sets.midcast.$spell", "sets.midcast.$spell.DT"
    }
    foreach ($spell in @('Enfeebling Magic','ElementalEnfeeble','IntEnfeebles','MndEnfeebles','Dia','Dia II','Bio','Bio II','Divine Magic','Stun')) {
        $metamorphSetPaths += "sets.midcast.$spell", "sets.midcast.$spell.DT", "sets.midcast.$spell.Resistant"
    }
    foreach ($setPath in $metamorphSetPaths) { $expected["$setPath.right_ring"] = 'Metamor. Ring +1' }
    foreach ($spell in @('Cure','LightWeatherCure','LightDayCure','Curaga')) {
        $expected["sets.midcast.$spell.left_ring"] = 'Tamas Ring'
    }
    $expected['sets.midcast.Cursna.DT.right_ring'] = 'Tamas Ring'
    $expected['sets.RecoverBurst.left_ring'] = 'Mujin Band'

    $changed = 0
    $allPaths = @($before.Keys) + @($after.Keys) | Sort-Object -Unique
    foreach ($path in $allPaths) {
        if ($before[$path] -ne $after[$path]) {
            if (-not $expected.ContainsKey($path) -or $after[$path] -ne $expected[$path]) {
                throw "Unexpected gear change: $path : $($before[$path]) -> $($after[$path])"
            }
            $changed++
            Write-Output "$path : $($before[$path]) -> $($after[$path])"
        }
    }
    foreach ($path in $expected.Keys) {
        if ($after[$path] -ne $expected[$path]) { throw "Missing intended upgrade: $path" }
    }
    Write-Output "Verified $changed intended ring assignments; all other named gear unchanged."
    Write-Output "Metamor. Ring +1 reaches $($metamorphSetPaths.Count) loaded sets/overlays."
    & (Join-Path $PSScriptRoot 'test_gearswap_accessory_slots.ps1') -NodeExe $NodeExe -GearSwapRoot $GearSwapRoot
    Write-Output 'All Achoo Metamorph ring tests passed.'
}
finally {
    $env:GEARSWAP_TEST_ROOT = $previousGearSwapRoot
    $env:Path = $metamorphOriginalPath
}
