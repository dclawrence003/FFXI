param(
    [string]$TaskName = 'FFXI InventoryCore'
)

$ErrorActionPreference = 'Stop'
$HiddenLauncher = Join-Path $PSScriptRoot 'Start-InventoryCore-Hidden.vbs'
if (-not (Test-Path -LiteralPath $HiddenLauncher)) {
    throw "InventoryCore hidden launcher not found: $HiddenLauncher"
}

$WScriptExe = Join-Path $env:WINDIR 'System32\wscript.exe'
if (-not (Test-Path -LiteralPath $WScriptExe)) {
    throw "Windows Script Host was not found: $WScriptExe"
}
$Arguments = "//B //Nologo `"$HiddenLauncher`""
$Action = New-ScheduledTaskAction -Execute $WScriptExe -Argument $Arguments -WorkingDirectory $PSScriptRoot
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
    -Force `
    -ErrorAction Stop | Out-Null

Start-ScheduledTask -TaskName $TaskName
Write-Output "Installed and started scheduled task: $TaskName"
