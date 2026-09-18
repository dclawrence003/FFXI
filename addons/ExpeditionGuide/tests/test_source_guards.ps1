$ErrorActionPreference = 'Stop'

$testsRoot = $PSScriptRoot
$addonRoot = Split-Path -Parent $testsRoot
$production = Get-ChildItem -LiteralPath $addonRoot -Recurse -File -Filter '*.lua' |
    Where-Object { $_.FullName -notlike "$testsRoot*" }

$violations = [System.Collections.Generic.List[string]]::new()

function Add-Violation([string]$Path, [int]$Line, [string]$Reason) {
    $relative = [System.IO.Path]::GetRelativePath($addonRoot, $Path)
    $violations.Add("${relative}:${Line}: $Reason")
}

$forbidden = [ordered]@{
    '\binject_outgoing\b' = 'outgoing packet injection is forbidden'
    '\bpackets\s*\.\s*inject\b' = 'packet injection is forbidden'
    '\bwindower\s*\.\s*ffxi\s*\.\s*(run|turn|set_mob|set_target)\b' = 'movement or target control is forbidden'
    '\bwindower\s*\.\s*ffxi\s*\.\s*set_key\b' = 'key control is forbidden'
    '\bequip\s*\(' = 'equipment ownership is forbidden'
    '[''"](?:input\s+)?/(attack|a|ma|ja|ws|ra|range|heal|follow|lockon|target)\b' = 'direct combat/target command is forbidden'
    '[''"](?:bind|unbind)\s+' = 'key rebinding is forbidden'
    '\bgearswap\s+c\b' = 'GearSwap command dispatch is forbidden'
    '\bautows2\b' = 'AutoWS2 control is forbidden'
    '\broller2?\b' = 'Roller control is forbidden'
    '\bhealbot\b' = 'HealBot control is forbidden'
    '\bparty(start|combat)\b' = 'legacy controller dependency is forbidden'
}

foreach ($file in $production) {
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        $lineNumber++
        foreach ($entry in $forbidden.GetEnumerator()) {
            if ($line -match $entry.Key) {
                Add-Violation $file.FullName $lineNumber $entry.Value
            }
        }
    }
}

# There is one intentionally narrow command aperture: main passes commands
# emitted by the two allowlisted lifecycle bridges to Windower. Route content
# can name only a canonical PartyTactics profile or one of three fixed Sortie
# Superwarp operations; it can never supply a raw command.
$sendCommandHits = @()
foreach ($file in $production) {
    $matches = Select-String -LiteralPath $file.FullName -Pattern 'windower\.send_command' -AllMatches
    foreach ($match in $matches) { $sendCommandHits += $match }
}
if ($sendCommandHits.Count -ne 1) {
    $violations.Add("Expected exactly one windower.send_command aperture; found $($sendCommandHits.Count).")
} elseif ($sendCommandHits[0].Path -ne (Join-Path $addonRoot 'ExpeditionGuide.lua') -or
        $sendCommandHits[0].Line.Trim() -ne 'windower.send_command(command)') {
    Add-Violation $sendCommandHits[0].Path $sendCommandHits[0].LineNumber `
        'unexpected send_command aperture'
}

$bridgePath = Join-Path $addonRoot 'lib\profile_bridge.lua'
$dispatchLines = @(Select-String -LiteralPath $bridgePath -Pattern '(?:self|bridge)\.dispatch\(')
if ($dispatchLines.Count -ne 3) {
    $violations.Add("Expected exactly three profile bridge dispatch calls; found $($dispatchLines.Count).")
} else {
    $actual = @($dispatchLines | ForEach-Object { $_.Line.Trim() })
    $expected = @(
        'bridge.dispatch(use_command(canonical_id,armed))',
        "self.dispatch('lua i PartyTactics disarm')",
        "self.dispatch('lua i PartyTactics off')"
    )
    for ($index = 0; $index -lt $expected.Count; $index++) {
        if ($actual[$index] -ne $expected[$index]) {
            Add-Violation $bridgePath $dispatchLines[$index].LineNumber `
                "unexpected bridge dispatch: $($actual[$index])"
        }
    }
}

$automationBridgePath = Join-Path $addonRoot 'lib\automation_bridge.lua'
$automationDispatchLines = @(Select-String -LiteralPath $automationBridgePath `
    -Pattern '(?:self|bridge)\.dispatch\(')
if ($automationDispatchLines.Count -ne 1 -or
    $automationDispatchLines[0].Line.Trim() -ne 'self.dispatch(command)') {
    $violations.Add('Automation bridge must have exactly one validated dispatch call.')
}
$automationText = [System.IO.File]::ReadAllText($automationBridgePath)
foreach ($exactCommand in @(
    "device_a='sw so p a'",
    "device_c='sw so p c'",
    "port='sw so p port'"
)) {
    if (-not $automationText.Contains($exactCommand)) {
        $violations.Add("lib/automation_bridge.lua: missing exact allowlisted command $exactCommand.")
    }
}
if ($automationText -notmatch "action\.kind\s*~=\s*'sortie_superwarp'" -or
    $automationText -notmatch 'local\s+command\s*=\s*COMMANDS\[action\.operation\]') {
    $violations.Add('lib/automation_bridge.lua: route actions are not restricted to the typed allowlist.')
}

$mainPath = Join-Path $addonRoot 'ExpeditionGuide.lua'
$mainText = [System.IO.File]::ReadAllText($mainPath)
if ($mainText -notmatch "path\s*\.\.\s*'\.bak'" -or
    $mainText -notmatch 'StateStore\.load\(candidate\.path\)') {
    $violations.Add('ExpeditionGuide.lua: persistence has no backup recovery path.')
}
if ($mainText -notmatch 'local\s+wire\s*=\s*Protocol\.state\(report\)' -or
    $mainText -notmatch 'windower\.send_ipc_message\(wire\)') {
    $violations.Add('ExpeditionGuide.lua: sensor IPC is not constrained to Protocol.state.')
}
if ($mainText -notmatch "local\s+Sandbox\s*=\s*require\('lib\.sandbox'\)") {
    $violations.Add('ExpeditionGuide.lua: restricted content sandbox is not loaded.')
}
if ($mainText -notmatch 'Sandbox\.load\(\s*windower\.addon_path\s*\.\.\s*declaration\.path\s*,\s*loadfile\s*\)') {
    $violations.Add('ExpeditionGuide.lua: discovered content is not loaded through Sandbox.load.')
}
if ($mainText -notmatch 'local\s+registry_error\s*=\s*nil' -or
    $mainText -notmatch 'if\s+not\s+registry_ok\s+then\s+registry_error\s*=') {
    $violations.Add('ExpeditionGuide.lua: successful registry loads must not report a false error.')
}
if ($mainText -notmatch 'load_data\s*=\s*load_discovered_content') {
    $violations.Add('ExpeditionGuide.lua: ContentLoader is not wired to the production sandbox loader.')
}
if ($mainText -notmatch "_addon\.commands\s*=\s*\{'exg',\s*'expeditionguide'\}" -or
    $mainText -match '_addon\.commands\s*=.*[''"]eg[''"]') {
    $violations.Add('ExpeditionGuide.lua: command aliases must be exg and expeditionguide; eg conflicts with EventGuard.')
}
$readinessGates = [regex]::Matches($mainText,
    '(?:report|local_report)\.ready\s*~=\s*true').Count
if ($readinessGates -lt 2) {
    $violations.Add("ExpeditionGuide.lua: navigation/readout readiness gates are incomplete; found $readinessGates.")
}
if ($mainText -notmatch 'catalogs\s*=\s*content\.packs' -or
    $mainText -notmatch 'party_states\[report\.pack_id\]') {
    $violations.Add('ExpeditionGuide.lua: IPC is not dispatched through exact pack/catalog state.')
}
if ($mainText -notmatch 'for\s+_,\s*id\s+in\s+ipairs\(pack_ids\)' -or
    $mainText -notmatch 'Sensors\.report\(snapshot,\s*content\.packs\[id\]' -or
    $mainText -notmatch 'local\s+accepted,\s*reason\s*=\s*Protocol\.validate\(wire') {
    $violations.Add('ExpeditionGuide.lua: passive reports are not projected for every installed pack.')
}
if ($mainText -notmatch 'pack\.instance_zones\[zone\]\s*~=\s*true') {
    $violations.Add('ExpeditionGuide.lua: live route evidence is not instance-zone gated.')
}
if ($mainText -notmatch "local\s+RewardSafety\s*=\s*require\('lib\.reward_safety'\)" -or
    $mainText -notmatch 'reward_gate:observe\(' -or
    $mainText -notmatch 'reward=reward' -or
    $mainText -notmatch "reward_gate:reset\('large relocation'\)" -or
    $mainText -notmatch "reward_gate:reset\('sensor resync'\)") {
    $violations.Add('ExpeditionGuide.lua: memory-only reward safety lifecycle wiring is incomplete.')
}
$stateWrapperMatch = [regex]::Match($mainText,
    '(?s)local\s+function\s+state_wrapper\(\).*?\nend\s*\n\s*local\s+function\s+persist')
if (-not $stateWrapperMatch.Success -or
    $stateWrapperMatch.Value -match 'reward(_gate|_safe|_status|_proof)') {
    $violations.Add('ExpeditionGuide.lua: reward authorization must never enter persisted state.')
}

$regionPath = Join-Path $addonRoot 'lib\region.lua'
$rewardSafetyPath = Join-Path $addonRoot 'lib\reward_safety.lua'
$regionText = [System.IO.File]::ReadAllText($regionPath)
$rewardSafetyText = [System.IO.File]::ReadAllText($rewardSafetyPath)
foreach ($entry in @(
    @{ Path=$regionPath; Text=$regionText },
    @{ Path=$rewardSafetyPath; Text=$rewardSafetyText }
)) {
    if ($entry.Text -match '(?i)\b(sortie|odyssey)\b') {
        $violations.Add("$([System.IO.Path]::GetFileName($entry.Path)): generic library contains expedition-specific strings.")
    }
    if ($entry.Text -match '\b(windower|send_command|send_ipc_message|StateStore|io\.)\b') {
        $violations.Add("$([System.IO.Path]::GetFileName($entry.Path)): pure reward library can perform host I/O.")
    }
}
if ($regionText -notmatch 'function\s+Region\.validate_scope' -or
    $regionText -notmatch 'function\s+Region\.contains_scope' -or
    $rewardSafetyText -notmatch 'MAX_RECEIPT_AGE\s*=\s*2' -or
    $rewardSafetyText -notmatch 'MAX_WALL_AGE\s*=\s*2' -or
    $rewardSafetyText -notmatch 'MIN_CYCLE_INTERVAL\s*=\s*0\.5') {
    $violations.Add('Generic reward geometry or bounded temporal proof constants are missing.')
}

$protocolPath = Join-Path $addonRoot 'lib\protocol.lua'
$protocolText = [System.IO.File]::ReadAllText($protocolPath)
if ($protocolText -notmatch "PREFIX\s*=\s*'EG\|2\|'" -or
    $protocolText -match "fields\[2\]\s*~=\s*'1'" -or
    $protocolText -notmatch 'catalog\.catalog_id\s*~=\s*catalog_id' -or
    $protocolText -notmatch 'main_job' -or $protocolText -notmatch 'sub_job') {
    $violations.Add('lib/protocol.lua: pack-bound EG v2 production validation is missing.')
}

$sensorsPath = Join-Path $addonRoot 'lib\sensors.lua'
$sensorsText = [System.IO.File]::ReadAllText($sensorsPath)
if ($sensorsText -notmatch 'party2_count' -or
    $sensorsText -notmatch 'party3_count' -or
    $sensorsText -notmatch "party\['a'\s*\.\.\s*tostring\(index\)\]" -or
    $sensorsText -notmatch 'tonumber\(player\.id\)\s*==\s*tonumber\(party\.party1_leader\)') {
    $violations.Add('lib/sensors.lua: exact party/no-alliance or Dolo-local leadership proof is missing.')
}

$partyStatePath = Join-Path $addonRoot 'lib\party_state.lua'
$partyStateText = [System.IO.File]::ReadAllText($partyStatePath)
if ($partyStateText -notmatch 'is_expected_leader' -or
    $partyStateText -notmatch 'leader_expected\s*=\s*1' -or
    $partyStateText -notmatch 'if\s+not\s+summary\.leader_quorum\s+then\s+summary\.all_in_pack\s*=\s*false') {
    $violations.Add('lib/party_state.lua: authoritative one-client leader quorum is missing.')
}

if ($violations.Count -gt 0) {
    Write-Output 'ExpeditionGuide source guards FAILED:'
    $violations | ForEach-Object { Write-Output "  $_" }
    exit 1
}

Write-Output "ExpeditionGuide source guards: PASS ($($production.Count) production Lua files scanned)"
