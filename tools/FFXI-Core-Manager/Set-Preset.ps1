[CmdletBinding()]
param(
    [ValidateSet('Cockpit', 'FullMain')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host ''
    Write-Host '1. Cockpit  - your saved cockpit layout'
    Write-Host '2. FullMain - your saved main-screen layout'
    Write-Host ''
    $selection = Read-Host 'Choose 1 or 2'
    $Name = if ($selection -eq '2') { 'FullMain' } else { 'Cockpit' }
}

$source = Join-Path $PSScriptRoot "presets\$Name.json"
$localSource = Join-Path $PSScriptRoot "local\presets\$Name.json"
if (Test-Path -LiteralPath $localSource) { $source = $localSource }
$installedRoot = Join-Path $env:LOCALAPPDATA 'FFXIManager'
$destination = if (Test-Path -LiteralPath $installedRoot) {
    Join-Path $installedRoot 'config.json'
}
else {
    $localRoot = Join-Path $PSScriptRoot 'local'
    [void](New-Item -ItemType Directory -Path $localRoot -Force)
    Join-Path $localRoot 'config.json'
}

Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Host "Selected preset '$Name'."
Write-Host "Configuration written to: $destination"
Write-Host 'The running manager will notice the change within two seconds.'
