[CmdletBinding()]
param(
    [string]$VaultRoot = (Join-Path $env:USERPROFILE 'Documents\Tesseract\FFXI'),
    [string]$WindowerRoot = 'C:\Program Files (x86)\Windower',
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$publicRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot ('reports\audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
}
function Read-Git([string]$Root, [string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = @(& git -c "safe.directory=$Root" -C $Root @Arguments 2>&1)
        $gitExitCode = $LASTEXITCODE
    } catch { return $null }
    finally { $ErrorActionPreference = $previousPreference }
    $diagnostics = @($result | Where-Object { $_ -is [Management.Automation.ErrorRecord] -or "$_" -match '^(warning|fatal|error):' })
    foreach ($diagnostic in $diagnostics) { $script:gitWarnings.Add("$diagnostic") }
    if ($gitExitCode -ne 0) { return $null }
    return (@($result | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] -and "$_" -notmatch '^(warning|fatal|error):' }) -join "`n")
}
function Get-HashOrNull([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    return $null
}
$repositories = foreach ($root in @($publicRoot, (Join-Path $VaultRoot 'projects\FFXI-Public'), (Join-Path $VaultRoot 'projects\FFXI-Private'))) {
    $script:gitWarnings = [Collections.Generic.List[string]]::new()
    $head = Read-Git $root @('rev-parse','HEAD')
    $status = Read-Git $root @('status','--porcelain=v1','--untracked-files=normal')
    $entries = @($status -split "`n" | Where-Object { $_ })
    [ordered]@{
        path=$root; head=$head; branch=(Read-Git $root @('branch','--show-current'))
        last_commit=(Read-Git $root @('log','-1','--format=%cI %s'))
        status_available=($null -ne $status)
        changed_entries=$(if ($null -ne $status) { $entries.Count } else { $null })
        untracked_entries=$(if ($null -ne $status) { @($entries | Where-Object { $_.StartsWith('??') }).Count } else { $null })
        agents_present=(Test-Path -LiteralPath (Join-Path $root 'AGENTS.md'))
        project_config_present=(Test-Path -LiteralPath (Join-Path $root '.codex\config.toml'))
        git_warnings=@($script:gitWarnings.ToArray())
    }
}
$parity = foreach ($name in @('PartyTactics','PartyCombat','PartyStart','AutoWS2','Roller2','SignetKeeper','LocusPuller','JubileeKeeper','ExpeditionGuide','ConquestCash','SalvageCells')) {
    $relative = 'addons\' + $name + '\' + $name + '.lua'
    $sourceHash = Get-HashOrNull (Join-Path $publicRoot $relative)
    $liveHash = Get-HashOrNull (Join-Path $WindowerRoot $relative)
    [ordered]@{ component=$name; source_sha256=$sourceHash; deployed_sha256=$liveHash
        disk_match=($null -ne $sourceHash -and $sourceHash -eq $liveHash); loaded_version='not observed' }
}
$privateRoot = Join-Path $VaultRoot 'projects\FFXI-Private'
$toolchainPath = Join-Path $privateRoot 'toolchain.json'
$toolchain = $null
if (Test-Path -LiteralPath $toolchainPath) { $toolchain = Get-Content -Raw -LiteralPath $toolchainPath | ConvertFrom-Json }
$report = [ordered]@{
    schema_version=1; observed_at_utc=(Get-Date).ToUniversalTime().ToString('o')
    scope='Read-only disk audit. Not an atomic snapshot; no loaded-client or gameplay verification.'
    repositories=@($repositories); addon_disk_parity=@($parity)
    partyops=[ordered]@{
        root=$privateRoot; pinned_node=$toolchain.node.version
        pinned_runtime_present=(Test-Path -LiteralPath (Join-Path $privateRoot ".tools\node-v$($toolchain.node.version)-win-x64\node.exe"))
        exporter_built=(Test-Path -LiteralPath (Join-Path $privateRoot 'apps\hub\dist\p12\long-session-export-entry.js'))
        current_state_note=(Test-Path -LiteralPath (Join-Path $VaultRoot 'operations\current-state.md'))
    }
}
$destination = [IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination -Encoding utf8
Write-Output "Audit: $destination"
$repositories | ForEach-Object {
    if ($_.status_available) { Write-Output "$($_.path): $($_.changed_entries) changed entries; $($_.untracked_entries) untracked entries" }
    else { Write-Output "$($_.path): Git status unavailable; do not treat as clean." }
}
Write-Output 'Disk parity is not proof that running clients loaded these files.'
