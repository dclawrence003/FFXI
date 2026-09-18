$dataRoot = 'C:\Program Files (x86)\Windower\addons\GearSwap\data'
$exportRoot = Join-Path $dataRoot 'export'
$findAllRoot = 'C:\Program Files (x86)\Windower\addons\findAll\data'
$resourceFile = 'C:\Program Files (x86)\Windower\res\items.lua'
$runtime = Join-Path $PSScriptRoot 'validate_gearswap_runtime.lua'
$nodeBin = 'C:\Users\DC03\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin'
$pnpm = 'C:\Users\DC03\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd'
$env:Path = "$nodeBin;$env:Path"

$aliases = @{}
$idToName = @{}
$itemJobs = @{}
$itemSlots = @{}
Get-Content $resourceFile | ForEach-Object {
    if ($_ -match '\[(\d+)\].*?en="([^"]+)".*?enl="([^"]+)"') {
        $id = [int]$matches[1]
        $idToName[$id] = $matches[2]
        $aliases[$matches[2].ToLowerInvariant()] = $id
        $aliases[$matches[3].ToLowerInvariant()] = $id
        if ($_ -match 'jobs=(\d+)') { $itemJobs[$id] = [int64]$matches[1] }
        if ($_ -match 'slots=(\d+)') { $itemSlots[$id] = [int]$matches[1] }
    }
}

$pairs = @(
    @('Tackleberry', 'PLD', 7),
    @('Kickpuncher', 'DNC', 19),
    @('Barneystinson', 'BRD', 10),
    @('Smalls', 'RDM', 5),
    @('Achoo', 'GEO', 21),
    @('Dolomedes', 'COR', 17)
)
$slot = '(?:main|sub|range|ammo|head|body|hands|legs|feet|neck|waist|left_ear|right_ear|ear1|ear2|left_ring|right_ring|ring1|ring2|back)'
$quotedValue = '"([^"]+)"'

foreach ($pair in $pairs) {
    $name = $pair[0]
    $job = $pair[1]
    $jobId = [int]$pair[2]
    $gearFile = Join-Path $dataRoot "$name\${name}_${job}_Gear.lua"
    $profileFile = Join-Path $dataRoot "$name\$name-FollowerProfiles.lua"
    $profileArg = if (Test-Path -LiteralPath $profileFile) { $profileFile } else { '-' }
    $followerFile = Join-Path $dataRoot 'common\FollowerGear.lua'
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

    # FindAll is authoritative for current active bags.  GearSwap can equip
    # from Inventory and Wardrobes, but not Mog Safe/Storage/Satchel/etc.
    $findAllFile = Join-Path $findAllRoot "$name.lua"
    $section = ''
    foreach ($line in Get-Content $findAllFile) {
        if ($line -match '^\["([^"]+)"\] = \{$') {
            $section = $matches[1]
            continue
        }
        if ($section -notmatch '^inventory$|^wardrobe\d*$') { continue }
        if ($line -match '^\s+\["(\d+)"\] = ') {
            $id = [int]$matches[1]
            if ($idToName.ContainsKey($id)) {
                [void]$ownedIds.Add($id)
                [void]$ownedNames.Add($idToName[$id])
            }
        }
    }

    $env:GEARSWAP_OWNED = [string]::Join('|', $ownedNames)
    $runtimeOutput = & $pnpm --package=fengari-node-cli dlx fengari `
        $runtime $gearFile $followerFile $profileArg dump 2>&1
    if (($runtimeOutput -join "`n") -notmatch 'runtime-ok:') {
        Write-Output "$name/$job runtime failed"
        $runtimeOutput
        continue
    }

    $missingByName = @{}
    $wrongJob = @{}
    $wrongSlot = @{}
    $slotBits = @{
        main=1; sub=2; range=4; ranged=4; ammo=8; head=16; body=32;
        hands=64; legs=128; feet=256; neck=512; waist=1024;
        left_ear=6144; right_ear=6144; ear1=6144; ear2=6144;
        left_ring=24576; right_ring=24576; ring1=24576; ring2=24576;
        back=32768
    }
    foreach ($line in $runtimeOutput) {
        if ($line -notmatch '^set-item\t([^\t]+)\t(.+)$') { continue }
        $path = $matches[1]
        $itemName = $matches[2]
        $isOwned = $ownedNames.Contains($itemName)
        $key = $itemName.ToLowerInvariant()
        if (-not $isOwned -and $aliases.ContainsKey($key)) {
            $isOwned = $ownedIds.Contains($aliases[$key])
        }
        if (-not $isOwned) {
            if (-not $missingByName.ContainsKey($itemName)) {
                $missingByName[$itemName] = [System.Collections.Generic.List[string]]::new()
            }
            $missingByName[$itemName].Add($path)
        }

        if ($aliases.ContainsKey($key)) {
            $id = $aliases[$key]
            if ($itemJobs.ContainsKey($id) -and
                (($itemJobs[$id] -band (1L -shl $jobId)) -eq 0)) {
                if (-not $wrongJob.ContainsKey($itemName)) { $wrongJob[$itemName] = @() }
                $wrongJob[$itemName] += $path
            }
            $slotKey = ($path -split '\.')[-1]
            if ($slotBits.ContainsKey($slotKey) -and $itemSlots.ContainsKey($id) -and
                (($itemSlots[$id] -band $slotBits[$slotKey]) -eq 0)) {
                if (-not $wrongSlot.ContainsKey($itemName)) { $wrongSlot[$itemName] = @() }
                $wrongSlot[$itemName] += $path
            }
        }
    }

    Write-Output "$name/$job final-set unowned=$($missingByName.Count) wrong-job=$($wrongJob.Count) wrong-slot=$($wrongSlot.Count)"
    foreach ($itemName in ($missingByName.Keys | Sort-Object)) {
        $paths = $missingByName[$itemName]
        Write-Output "  $itemName :: $([string]::Join(', ', $paths))"
    }
    foreach ($itemName in ($wrongJob.Keys | Sort-Object)) {
        Write-Output "  WRONG JOB $itemName :: $([string]::Join(', ', $wrongJob[$itemName]))"
    }
    foreach ($itemName in ($wrongSlot.Keys | Sort-Object)) {
        Write-Output "  WRONG SLOT $itemName :: $([string]::Join(', ', $wrongSlot[$itemName]))"
    }
}

Remove-Item Env:GEARSWAP_OWNED -ErrorAction SilentlyContinue
