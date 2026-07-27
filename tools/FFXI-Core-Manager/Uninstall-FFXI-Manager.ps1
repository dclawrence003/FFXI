[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'FFXIManager'
$statePath = Join-Path $installRoot 'install-state.json'
$state = if (Test-Path -LiteralPath $statePath) {
    Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}
else {
    $null
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit
}

$taskName = if ($null -ne $state -and $state.taskName) {
    $state.taskName
}
else {
    'FFXI Character Core Manager'
}

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false `
    -ErrorAction SilentlyContinue

$pidPath = Join-Path $installRoot 'manager.pid'
if (Test-Path -LiteralPath $pidPath) {
    $managerPid = [int](Get-Content -LiteralPath $pidPath -Raw)
    Stop-Process -Id $managerPid -Force -ErrorAction SilentlyContinue
}

if ($null -ne $state -and $state.windowerRoot) {
    $addonPath = Join-Path $state.windowerRoot 'addons\CoreManager'
    if (Test-Path -LiteralPath $addonPath) {
        Remove-Item -LiteralPath $addonPath -Recurse -Force
    }
}

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host 'FFXI Character Core Manager has been removed.'
Read-Host 'Press Enter to close'
