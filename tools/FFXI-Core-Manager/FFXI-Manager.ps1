[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$Once,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class FFXITaskbarControl
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(
        IntPtr parent, IntPtr childAfter, string className, string windowName);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    [DllImport("shell32.dll")]
    private static extern UIntPtr SHAppBarMessage(
        uint message, ref APPBARDATA data);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    public static void SetAutoHide(bool enabled)
    {
        IntPtr primary = FindWindow("Shell_TrayWnd", null);
        if (primary == IntPtr.Zero)
        {
            return;
        }

        APPBARDATA data = new APPBARDATA();
        data.cbSize = Marshal.SizeOf(typeof(APPBARDATA));
        data.hWnd = primary;
        data.lParam = (IntPtr)(enabled ? 1 : 2); // ABS_AUTOHIDE / ABS_ALWAYSONTOP
        SHAppBarMessage(0x0000000A, ref data); // ABM_SETSTATE
    }

    public static int SetPrimaryVisible(bool visible)
    {
        int command = visible ? 5 : 0; // SW_SHOW / SW_HIDE
        IntPtr primary = FindWindow("Shell_TrayWnd", null);
        if (primary != IntPtr.Zero)
        {
            ShowWindow(primary, command);
            return 1;
        }
        return 0;
    }

    public static int SetSecondaryVisible(bool visible)
    {
        int command = visible ? 5 : 0; // SW_SHOW / SW_HIDE
        int count = 0;
        IntPtr current = IntPtr.Zero;
        while ((current = FindWindowEx(
            IntPtr.Zero, current, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero)
        {
            ShowWindow(current, command);
            count++;
        }
        return count;
    }
}
'@

$managerRoot = if ($DryRun) {
    Join-Path ([IO.Path]::GetTempPath()) "FFXIManager-DryRun-$PID"
}
else {
    Join-Path $env:LOCALAPPDATA 'FFXIManager'
}
$requestRoot = Join-Path $managerRoot 'requests'
$statusRoot = Join-Path $managerRoot 'status'
$layoutRoot = Join-Path $managerRoot 'layouts'
$logPath = Join-Path $managerRoot 'manager.log'
$pidPath = Join-Path $managerRoot 'manager.pid'

foreach ($directory in @($managerRoot, $requestRoot, $statusRoot, $layoutRoot)) {
    [void](New-Item -ItemType Directory -Path $directory -Force)
}

$PID | Set-Content -LiteralPath $pidPath -Encoding ascii

function Write-ManagerLog {
    param([string]$Message)

    $line = '{0:yyyy-MM-dd HH:mm:ss} | {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    if ($Once -or $DryRun) {
        Write-Output $line
    }
}

function ConvertTo-AffinityMask {
    param([object[]]$LogicalProcessors)

    [uint64]$mask = 0
    foreach ($logicalProcessor in $LogicalProcessors) {
        $cpu = [int]$logicalProcessor
        if ($cpu -lt 0 -or $cpu -gt 63) {
            throw "Logical CPU $cpu is outside the supported range 0-63."
        }
        $mask = $mask -bor ([uint64]1 -shl $cpu)
    }
    return $mask
}

function Write-CharacterStatus {
    param(
        [string]$Character,
        [string]$Message
    )

    $safeName = $Character -replace '[^A-Za-z0-9_-]', '_'
    $path = Join-Path $statusRoot "$safeName.txt"
    $tempPath = "$path.tmp"
    $Message | Set-Content -LiteralPath $tempPath -Encoding utf8
    Move-Item -LiteralPath $tempPath -Destination $path -Force
}

function Get-RequestedAction {
    param([string]$Character)

    $safeName = $Character -replace '[^A-Za-z0-9_-]', '_'
    $path = Join-Path $requestRoot "$safeName.request"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    try {
        $action = (Get-Content -LiteralPath $path -Raw).Trim().ToLowerInvariant()
        Remove-Item -LiteralPath $path -Force
        return $action
    }
    catch {
        Write-ManagerLog "Could not consume request for $Character`: $($_.Exception.Message)"
        return $null
    }
}

function Write-CharacterLayout {
    param(
        [string]$Character,
        [object]$WindowRule,
        [long]$SignatureTicks = 0
    )

    $safeName = $Character -replace '[^A-Za-z0-9_-]', '_'
    $path = Join-Path $layoutRoot "$safeName.txt"
    $tempPath = "$path.tmp"
    if ($SignatureTicks -eq 0) {
        $SignatureTicks = $lastConfigWrite.Ticks
    }
    $layout = '{0}|{1}|{2}|{3}|{4}' -f
        [int]$WindowRule.x,
        [int]$WindowRule.y,
        [int]$WindowRule.width,
        [int]$WindowRule.height,
        $SignatureTicks
    $layout | Set-Content -LiteralPath $tempPath -Encoding ascii
    Move-Item -LiteralPath $tempPath -Destination $path -Force
}

$appliedSignatures = @{}
$lastConfigWrite = [datetime]::MinValue
$config = $null
$recoveryMonitorWasActive = $null
$recoveryStablePolls = 0
$recoveryPending = $false

try {
    Write-ManagerLog "Manager started. Config: $ConfigPath"

    while ($true) {
        try {
            $configItem = Get-Item -LiteralPath $ConfigPath
            if ($null -eq $config -or $configItem.LastWriteTimeUtc -ne $lastConfigWrite) {
                $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
                $lastConfigWrite = $configItem.LastWriteTimeUtc
                $appliedSignatures.Clear()
                if ($null -ne $config.keepSecondaryTaskbarsVisible -and
                    [bool]$config.keepSecondaryTaskbarsVisible) {
                    [FFXITaskbarControl]::SetAutoHide($false)
                    [void][FFXITaskbarControl]::SetSecondaryVisible($true)
                }
                Write-ManagerLog "Loaded preset '$($config.presetName)'."
            }

            $rules = @{}
            foreach ($property in $config.characters.PSObject.Properties) {
                $rules[$property.Name.ToLowerInvariant()] = $property.Value
            }

            $allPolProcesses = @(Get-Process -Name pol -ErrorAction SilentlyContinue)
            if ([bool]$config.hidePrimaryTaskbarWhileFfxiRunning) {
                [void][FFXITaskbarControl]::SetPrimaryVisible($allPolProcesses.Count -eq 0)
                [void][FFXITaskbarControl]::SetSecondaryVisible($true)
            }

            if ($null -ne $config.monitorRecovery -and
                [bool]$config.monitorRecovery.enabled) {
                $monitorPattern = [string]$config.monitorRecovery.monitorInstancePattern
                $activeMonitor = Get-CimInstance `
                    -Namespace root\wmi `
                    -ClassName WmiMonitorID `
                    -ErrorAction Stop |
                    Where-Object {
                        $_.Active -and $_.InstanceName -match $monitorPattern
                    } |
                    Select-Object -First 1
                $monitorIsActive = $null -ne $activeMonitor

                if ($null -eq $recoveryMonitorWasActive) {
                    $recoveryMonitorWasActive = $monitorIsActive
                }
                elseif (-not $monitorIsActive) {
                    if ($recoveryMonitorWasActive) {
                        Write-ManagerLog 'Recovery monitor disconnected.'
                    }
                    $recoveryStablePolls = 0
                    $recoveryPending = $false
                    $recoveryMonitorWasActive = $false
                }
                else {
                    if (-not $recoveryMonitorWasActive) {
                        Write-ManagerLog 'Recovery monitor reconnected; waiting for a stable topology.'
                        $recoveryPending = $true
                        $recoveryStablePolls = 1
                    }
                    elseif ($recoveryPending) {
                        $recoveryStablePolls++
                    }
                    $recoveryMonitorWasActive = $true

                    $requiredStablePolls = [math]::Max(
                        2, [int]$config.monitorRecovery.stablePolls)
                    if ($recoveryPending -and
                        $recoveryStablePolls -ge $requiredStablePolls) {
                        $recoveryCharacters = @(
                            $config.monitorRecovery.characters |
                            ForEach-Object { ([string]$_).ToLowerInvariant() })
                        $liveCharacters = @{}
                        foreach ($liveProcess in $allPolProcesses) {
                            $liveName = $liveProcess.MainWindowTitle.Trim()
                            if (-not [string]::IsNullOrWhiteSpace($liveName)) {
                                $liveCharacters[$liveName.ToLowerInvariant()] = $true
                            }
                        }

                        $recoveryTicks = [datetime]::UtcNow.Ticks
                        foreach ($recoveryCharacter in $recoveryCharacters) {
                            if ($rules.ContainsKey($recoveryCharacter) -and
                                $liveCharacters.ContainsKey($recoveryCharacter)) {
                                $recoveryRule = $rules[$recoveryCharacter]
                                if ($null -ne $recoveryRule.window -and
                                    $recoveryRule.window.enabled) {
                                    Write-CharacterLayout `
                                        -Character $recoveryCharacter `
                                        -WindowRule $recoveryRule.window `
                                        -SignatureTicks $recoveryTicks
                                    Write-ManagerLog (
                                        'Published reconnect recovery layout for {0}: {1},{2} {3}x{4}' -f
                                        $recoveryCharacter,
                                        $recoveryRule.window.x,
                                        $recoveryRule.window.y,
                                        $recoveryRule.window.width,
                                        $recoveryRule.window.height)
                                }
                            }
                        }
                        $recoveryPending = $false
                        $recoveryStablePolls = 0
                    }
                }
            }

            $liveProcessIds = @{}
            foreach ($process in $allPolProcesses) {
                $character = $process.MainWindowTitle.Trim()
                if ([string]::IsNullOrWhiteSpace($character)) {
                    continue
                }

                $key = $character.ToLowerInvariant()
                if (-not $rules.ContainsKey($key)) {
                    continue
                }

                $liveProcessIds[$process.Id] = $true
                $rule = $rules[$key]
                $requestedAction = Get-RequestedAction -Character $character
                [uint64]$mask = ConvertTo-AffinityMask -LogicalProcessors @($rule.logicalProcessors)
                $signature = '{0}:{1:X}:{2}' -f $process.Id, $mask, $lastConfigWrite.Ticks
                $needsAffinity = $requestedAction -eq 'apply' -or
                    $requestedAction -eq 'layout' -or
                    -not $appliedSignatures.ContainsKey($process.Id) -or
                    $appliedSignatures[$process.Id] -ne $signature

                $actions = [System.Collections.Generic.List[string]]::new()

                if ($needsAffinity) {
                    if ($DryRun) {
                        $actions.Add(('would set CPUs [{0}] / mask 0x{1:X}' -f
                            (@($rule.logicalProcessors) -join ','), $mask))
                    }
                    else {
                        $process.ProcessorAffinity = [IntPtr][int64]$mask
                        $actions.Add(('CPUs [{0}] / mask 0x{1:X}' -f
                            (@($rule.logicalProcessors) -join ','), $mask))
                    }
                }

                $shouldPlaceWindow = $false
                if ($null -ne $rule.window -and $rule.window.enabled) {
                    $shouldPlaceWindow = [bool]$config.windowManagementEnabled -and $needsAffinity
                    if ($requestedAction -eq 'layout') {
                        $shouldPlaceWindow = $true
                    }
                }

                if ($shouldPlaceWindow) {
                    if ($DryRun) {
                        $actions.Add(('would publish WinControl layout {0},{1} size {2}x{3}' -f
                            $rule.window.x, $rule.window.y,
                            $rule.window.width, $rule.window.height))
                    }
                    else {
                        Write-CharacterLayout -Character $character -WindowRule $rule.window
                        $actions.Add(('WinControl layout {0},{1} {2}x{3}' -f
                            $rule.window.x, $rule.window.y,
                            $rule.window.width, $rule.window.height))
                    }
                }

                if ($needsAffinity -and -not $DryRun) {
                    $appliedSignatures[$process.Id] = $signature
                }

                if ($actions.Count -gt 0) {
                    $message = 'PID {0} | {1} | {2}' -f
                        $process.Id, $character, ($actions -join ' | ')
                    Write-ManagerLog $message
                    Write-CharacterStatus -Character $character -Message (
                        '{0:yyyy-MM-dd HH:mm:ss} | OK | {1}' -f (Get-Date), $message)
                }
            }

            foreach ($knownPid in @($appliedSignatures.Keys)) {
                if (-not $liveProcessIds.ContainsKey($knownPid)) {
                    $appliedSignatures.Remove($knownPid)
                }
            }
        }
        catch {
            $message = "Manager cycle failed: $($_.Exception.Message)"
            Write-ManagerLog $message
        }

        if ($Once) {
            break
        }

        $pollSeconds = if ($null -ne $config -and $null -ne $config.pollIntervalSeconds) {
            [math]::Max(1, [int]$config.pollIntervalSeconds)
        }
        else {
            2
        }
        Start-Sleep -Seconds $pollSeconds
    }
}
finally {
    if ($null -ne $config -and [bool]$config.hidePrimaryTaskbarWhileFfxiRunning) {
        [void][FFXITaskbarControl]::SetPrimaryVisible($true)
        [void][FFXITaskbarControl]::SetSecondaryVisible($true)
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Write-ManagerLog 'Manager stopped.'
    if ($DryRun -and (Test-Path -LiteralPath $managerRoot)) {
        Remove-Item -LiteralPath $managerRoot -Recurse -Force
    }
}
