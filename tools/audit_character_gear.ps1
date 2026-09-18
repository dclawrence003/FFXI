$dataRoot = 'C:\Program Files (x86)\Windower\addons\GearSwap\data'
$exportRoot = Join-Path $dataRoot 'export'
$resourceFile = 'C:\Program Files (x86)\Windower\res\items.lua'

$aliases = @{}
Get-Content $resourceFile | ForEach-Object {
    if ($_ -match '\[(\d+)\].*?en="([^"]+)".*?enl="([^"]+)"') {
        $id = [int]$matches[1]
        $aliases[$matches[2].ToLowerInvariant()] = $id
        $aliases[$matches[3].ToLowerInvariant()] = $id
    }
}

$pairs = @(
    @('Tackleberry', 'PLD'),
    @('Kickpuncher', 'DNC'),
    @('Barneystinson', 'BRD'),
    @('Smalls', 'RDM'),
    @('Achoo', 'GEO')
)
$slot = '(?:main|sub|range|ammo|head|body|hands|legs|feet|neck|waist|left_ear|right_ear|ear1|ear2|left_ring|right_ring|ring1|ring2|back)'
$quotedValue = '["'']([^"'']+)["'']'

foreach ($pair in $pairs) {
    $name = $pair[0]
    $job = $pair[1]
    $gearFile = Join-Path $dataRoot "$name\${name}_${job}_Gear.lua"
    $exportFile = Join-Path $exportRoot "${name}_codex_live.lua"

    $ownedIds = [System.Collections.Generic.HashSet[int]]::new()
    $ownedNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $exportText = Get-Content $exportFile -Raw
    $exportPattern = "(?i)$slot\s*=\s*(?:\{\s*name\s*=\s*)?$quotedValue"
    foreach ($match in [regex]::Matches($exportText, $exportPattern)) {
        $itemName = $match.Groups[1].Value
        [void]$ownedNames.Add($itemName)
        $key = $itemName.ToLowerInvariant()
        if ($aliases.ContainsKey($key)) {
            [void]$ownedIds.Add($aliases[$key])
        }
    }

    $references = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $gearText = Get-Content $gearFile -Raw
    $gearPattern = "(?i)(?:$slot\s*=\s*(?:\{\s*)?name\s*=|$slot\s*=|local\s+\w+\s*=\s*\{\s*name\s*=)\s*$quotedValue"
    foreach ($match in [regex]::Matches($gearText, $gearPattern)) {
        [void]$references.Add($match.Groups[1].Value)
    }

    $missing = @()
    foreach ($itemName in $references) {
        $isOwned = $ownedNames.Contains($itemName)
        $key = $itemName.ToLowerInvariant()
        if (-not $isOwned -and $aliases.ContainsKey($key)) {
            $isOwned = $ownedIds.Contains($aliases[$key])
        }
        if (-not $isOwned -and $itemName -ne 'empty') {
            $missing += $itemName
        }
    }

    Write-Output "$name/$job direct references=$($references.Count), missing=$($missing.Count)"
    $missing | Sort-Object | ForEach-Object { Write-Output "  $_" }
}
