$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempBase (
    'PartyTactics-scaffold-test-' + [guid]::NewGuid().ToString('N'))
$addonRoot = Join-Path $tempRoot 'PartyTactics'

try {
    $toolsRoot = Join-Path $addonRoot 'tools'
    $profileRoot = Join-Path $addonRoot 'profiles'
    $sourceRoot = Join-Path $profileRoot 'source-template'
    $identityRoot = Join-Path $addonRoot 'data\profile_identities'
    New-Item -ItemType Directory -Path $toolsRoot, $sourceRoot, $identityRoot |
        Out-Null

    $sourceScript = Join-Path (Split-Path -Parent $PSScriptRoot) `
        'tools\New-PartyTacticsProfile.ps1'
    $scaffold = Join-Path $toolsRoot 'New-PartyTacticsProfile.ps1'
    Copy-Item -LiteralPath $sourceScript -Destination $scaffold

    Set-Content -LiteralPath (Join-Path $addonRoot 'data\profile_registry.lua') `
        -Encoding UTF8 -Value @'
return {
    identities={
        {ordinal=1, id='source-template', policy_id='pt-source', aliases={}},
    },
}
'@
    Set-Content -LiteralPath (Join-Path $sourceRoot 'profile.lua') `
        -Encoding UTF8 -Value @'
return {
    schema = 1,
    id = 'source-template',
    version = '9.9.9',
    policy_id = 'pt-source',
    label = 'Source profile',
    aliases = {'source'},
    gearswap_adapter = {
        id='source-template', version='9.9.9',
        controller='private-controller', protocol=1,
        actions={
            'setup',
            'attack',
        },
    },
    preflight = {
        members = {
            First={
                controller={name='private-controller', protocol=1},
            },
            Second={
                controller = {
                    name='private-controller',
                    protocol=1,
                },
            },
        },
    },
}
'@

    & $scaffold -Id 'target-profile' -Label 'Target profile' `
        -From 'source-template' | Out-Null

    $targetRoot = Join-Path $profileRoot 'target-profile'
    $targetProfile = Join-Path $targetRoot 'profile.lua'
    Assert-True (Test-Path -LiteralPath $targetProfile) `
        'Scaffold did not create the target profile.'
    $targetText = Get-Content -Raw -LiteralPath $targetProfile
    Assert-True ($targetText -notmatch `
        '(?m)^\s*(?:gearswap_adapter|controller)\s*=') `
        'Scaffold retained a private adapter or controller declaration.'
    Assert-True ($targetText -match "id = 'target-profile'") `
        'Scaffold did not replace the profile id.'
    Assert-True ($targetText -match "version = '0\.1\.0'") `
        'Scaffold did not reset the profile version.'

    $targetIdentity = Join-Path $identityRoot 'target-profile.lua'
    Assert-True (Test-Path -LiteralPath $targetIdentity) `
        'Scaffold did not create an isolated identity sidecar.'
    $identityText = Get-Content -Raw -LiteralPath $targetIdentity
    Assert-True ($identityText -match 'ordinal=2') `
        'Scaffold did not append the next identity ordinal.'
    Assert-True ($identityText -match "id='target-profile'") `
        'Scaffold identity does not own the new profile id.'

    $collisionIdentity = Join-Path $identityRoot 'collision-profile.lua'
    Set-Content -LiteralPath $collisionIdentity -Encoding UTF8 -Value @'
return {
    ordinal=3,
    id='collision-profile',
    policy_id='pt-collision-profile',
    aliases={},
}
'@
    $collisionFailed = $false
    try {
        & $scaffold -Id 'collision-profile' -Label 'Collision profile' `
            -From 'source-template' *> $null
    } catch {
        $collisionFailed = $true
    }
    Assert-True $collisionFailed `
        'Scaffold overwrote an existing identity sidecar.'
    Assert-True (-not (Test-Path -LiteralPath `
        (Join-Path $profileRoot 'collision-profile'))) `
        'Identity collision created a partial profile directory.'

    Write-Output 'PartyTactics profile scaffold tests passed.'
} finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($tempBase,
        [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTempRoot)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
    }
}
