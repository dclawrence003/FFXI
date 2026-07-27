[CmdletBinding()]
param(
    [ValidateSet('Cockpit', 'FullMain')]
    [string]$Name
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Host ''
    Write-Host '1. Cockpit  - Dolo 3072x1728 plus three 1024x576 clients on the LG'
    Write-Host '2. FullMain - Dolo fills the LG; side clients use both portrait monitors'
    Write-Host ''
    $selection = Read-Host 'Choose 1 or 2'
    $Name = if ($selection -eq '2') { 'FullMain' } else { 'Cockpit' }
}

$source = Join-Path $PSScriptRoot "presets\$Name.json"
$installedRoot = Join-Path $env:LOCALAPPDATA 'FFXIManager'
$destination = if (Test-Path -LiteralPath $installedRoot) {
    Join-Path $installedRoot 'config.json'
}
else {
    Join-Path $PSScriptRoot 'config.json'
}

Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Host "Selected preset '$Name'."
Write-Host "Configuration written to: $destination"
Write-Host 'The running manager will notice the change within two seconds.'
