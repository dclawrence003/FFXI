[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

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

$installRoot = Join-Path $env:LOCALAPPDATA 'FFXIManager'
[void](New-Item -ItemType Directory -Path $installRoot -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $installRoot 'presets') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $installRoot 'requests') -Force)
[void](New-Item -ItemType Directory -Path (Join-Path $installRoot 'status') -Force)

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'FFXI-Manager.ps1') `
    -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Set-Preset.ps1') `
    -Destination $installRoot -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets\Cockpit.json') `
    -Destination (Join-Path $installRoot 'presets') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'presets\FullMain.json') `
    -Destination (Join-Path $installRoot 'presets') -Force

$installedConfig = Join-Path $installRoot 'config.json'
if (-not (Test-Path -LiteralPath $installedConfig)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.json') `
        -Destination $installedConfig
}

$taskName = 'FFXI Character Core Manager'
$managerScript = Join-Path $installRoot 'FFXI-Manager.ps1'
$taskArguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -ConfigPath "{1}"' -f `
    $managerScript, $installedConfig
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArguments
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $identity.Name `
    -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $taskPrincipal -Settings $settings -Force | Out-Null

$state = [ordered]@{
    installedAt = (Get-Date).ToString('o')
    taskName = $taskName
    windowerRoot = $null
}

Add-Type -AssemblyName System.Windows.Forms
$dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
$dialog.Description = 'Select your active Windower folder to install the CoreManager addon. Cancel to skip the addon.'
$dialog.ShowNewFolderButton = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $windowerRoot = $dialog.SelectedPath
    if (-not (Test-Path -LiteralPath (Join-Path $windowerRoot 'Windower.exe'))) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'Windower.exe was not found in that folder. Install the addon there anyway?',
            'FFXI Core Manager',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $windowerRoot = $null
        }
    }

    if ($null -ne $windowerRoot) {
        $addonDestination = Join-Path $windowerRoot 'addons\CoreManager'
        [void](New-Item -ItemType Directory -Path $addonDestination -Force)
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Windower\CoreManager\CoreManager.lua') `
            -Destination $addonDestination -Force
        $state.windowerRoot = $windowerRoot
    }
}

$state | ConvertTo-Json | Set-Content `
    -LiteralPath (Join-Path $installRoot 'install-state.json') -Encoding utf8

Start-ScheduledTask -TaskName $taskName

Write-Host ''
Write-Host 'FFXI Character Core Manager installed.'
Write-Host "Scheduled task: $taskName"
Write-Host "Install folder: $installRoot"
if ($null -ne $state.windowerRoot) {
    Write-Host "Windower addon: $($state.windowerRoot)\addons\CoreManager"
    Write-Host 'Enable it with: //lua load CoreManager'
}
Write-Host ''
Write-Host 'Affinity management is active. Window movement remains disabled until'
Write-Host 'you intentionally select a layout preset.'
Read-Host 'Press Enter to close'
