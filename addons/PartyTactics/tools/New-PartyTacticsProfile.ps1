param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')]
    [string]$Id,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{2,63}$')]
    [string]$From,

    [switch]$IncludeRuntime
)

$ErrorActionPreference = 'Stop'
if ($Label -match '[\r\n|]') {
    throw 'Label may not contain a newline or IPC delimiter.'
}
$addonRoot = Split-Path -Parent $PSScriptRoot
$profileRoot = Join-Path $addonRoot 'profiles'
$source = Join-Path $profileRoot $From
$destination = Join-Path $profileRoot $Id
$identityRoot = Join-Path $addonRoot 'data\profile_identities'
$identityPath = Join-Path $identityRoot ($Id + '.lua')
$sourceProfilePath = Join-Path $source 'profile.lua'

if (-not (Test-Path -LiteralPath $sourceProfilePath)) {
    throw "Source profile does not exist: $From"
}
if (Test-Path -LiteralPath $destination) {
    throw "Destination already exists: $destination"
}
if (Test-Path -LiteralPath $identityPath) {
    throw "Identity sidecar already exists: $identityPath"
}

$resolvedRoot = [IO.Path]::GetFullPath($profileRoot)
$resolvedDestination = [IO.Path]::GetFullPath($destination)
if (-not $resolvedDestination.StartsWith(
    $resolvedRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Resolved destination is outside the PartyTactics profile directory.'
}

$policyId = ('pt-' + ($Id -replace '[^a-z0-9]', '-'))
if ($policyId.Length -gt 28) { $policyId = $policyId.Substring(0, 28) }
$profilePath = Join-Path $resolvedDestination 'profile.lua'
$profileText = Get-Content -Raw -LiteralPath $sourceProfilePath
$profileText = $profileText.Replace("id = '$From'", "id = '$Id'")
$profileText = [regex]::Replace(
    $profileText, "version = '[0-9]+\.[0-9]+\.[0-9]+'", "version = '0.1.0'", 1)
$profileText = [regex]::Replace(
    $profileText, "policy_id = '[a-z0-9_-]+'", "policy_id = '$policyId'", 1)
$escapedLabel = $Label.Replace('\', '\\').Replace('"', '\"')
$profileText = [regex]::Replace(
    $profileText, '(?m)^(\s*label\s*=\s*).*$',
    ('$1"' + $escapedLabel + '",'), 1)
$profileText = [regex]::Replace(
    $profileText, 'aliases = \{[^\r\n]*\}', 'aliases = {}', 1)

# A copied fight must never retain another profile's private GearSwap adapter.
# Remove both the pin and its per-member capability probes. The new profile is
# safe and adapter-free until its author deliberately creates and declares an
# adapter whose id matches $Id.
$profileText = [regex]::Replace(
    $profileText,
    '(?ms)^\s{4}gearswap_adapter\s*=\s*\{.*?^\s{4}\},\r?\n',
    '')
# Controller declarations are normally compact, but accepting a multiline
# source form here must not let a copied private capability proof survive.
$profileText = [regex]::Replace(
    $profileText,
    '(?m)^\s*controller\s*=\s*\{[^\r\n]*\},[^\r\n]*(?:\r?\n|$)',
    '')
$profileText = [regex]::Replace(
    $profileText,
    '(?ms)^(?<indent>[ \t]+)controller\s*=\s*\{\s*\r?\n.*?^\k<indent>\},[^\r\n]*(?:\r?\n|$)',
    '')
if ($profileText -match '(?m)^\s*(?:gearswap_adapter|controller)\s*=') {
    throw 'Copied profile still contains a private GearSwap adapter or controller declaration.'
}

# Do all adapter stripping and validation in memory before creating the
# destination. A failed transform therefore cannot leave a copied adapter in
# a partially-created profile directory.
New-Item -ItemType Directory -Path $resolvedDestination | Out-Null
Set-Content -LiteralPath $profilePath -Value $profileText -Encoding UTF8

$researchSource = Join-Path $source 'research.md'
if (Test-Path -LiteralPath $researchSource) {
    Copy-Item -LiteralPath $researchSource `
        -Destination (Join-Path $resolvedDestination 'research.md')
}
if ($IncludeRuntime -and (Test-Path -LiteralPath (Join-Path $source 'runtime.lua'))) {
    Copy-Item -LiteralPath (Join-Path $source 'runtime.lua') `
        -Destination (Join-Path $resolvedDestination 'runtime.lua')
}

# A copied profile must never keep a pointer into another fight's mutable
# EasyFarm state. Copy the source artifact directory into the new profile so
# any inherited reference remains local until its allowlist and filename are
# deliberately reviewed for the new encounter.
$easyFarmSource = Join-Path $source 'easyfarm'
if (Test-Path -LiteralPath $easyFarmSource -PathType Container) {
    Copy-Item -LiteralPath $easyFarmSource -Destination $resolvedDestination `
        -Recurse
}

New-Item -ItemType Directory -Path $identityRoot -Force | Out-Null
$ordinals = Select-String -Path `
    (Join-Path $addonRoot 'data\profile_registry.lua'), `
    (Join-Path $identityRoot '*.lua') -Pattern 'ordinal\s*=\s*(\d+)' `
    -ErrorAction SilentlyContinue | ForEach-Object {
        [int]$_.Matches[0].Groups[1].Value
    }
$nextOrdinal = (($ordinals | Measure-Object -Maximum).Maximum) + 1
$identityText = @"
-- Isolated append-only identity for $Id.
return {
    ordinal=$nextOrdinal,
    id='$Id',
    policy_id='$policyId',
    aliases={},
}
"@
Set-Content -LiteralPath $identityPath -Value $identityText -Encoding UTF8

Write-Host "Created $Id from $From with an isolated identity sidecar. Any copied fight adapter pin was removed; create gearswap/adapters/$Id/<version>.lua before declaring a new one. Review every copied policy, EasyFarm allowlist, runtime, and research note; then run tests before activation."
