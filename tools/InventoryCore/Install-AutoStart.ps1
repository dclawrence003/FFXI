param(
    [string]$TaskName = 'FFXI InventoryCore'
)

$ErrorActionPreference = 'Stop'
$Launcher = Join-Path $PSScriptRoot 'Start-InventoryCore.ps1'
if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "InventoryCore launcher not found: $Launcher"
}

$PowerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Launcher`" -NoBrowser -Foreground -SkipRefresh"
$Action = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $Arguments -WorkingDirectory $PSScriptRoot
$LogonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# A manually terminated task is not always covered by Task Scheduler's
# process-failure restart policy. Reassert the task every five minutes; with
# MultipleInstances=IgnoreNew these triggers are no-ops while the foreground
# server is healthy, but recover a task that was stopped unexpectedly.
$WatchdogTrigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -MultipleInstances IgnoreNew `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger @($LogonTrigger, $WatchdogTrigger) `
    -Settings $Settings `
    -Description 'Keeps the local FFXI InventoryCore and LootAdvisor recommendation service available.' `
    -Force | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Output "Installed and started scheduled task: $TaskName"
