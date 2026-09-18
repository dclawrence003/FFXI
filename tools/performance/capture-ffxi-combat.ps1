[CmdletBinding()]
param(
    [ValidateRange(30, 900)]
    [int]$DurationSeconds = 180,
    [switch]$ValidateOnly,
    [string]$PresentMonPath = (Join-Path $PSScriptRoot 'PresentMon-2.5.1-x64.exe')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $presentMonPath)) {
    throw "PresentMon was not found at: $presentMonPath"
}

$clients = @(Get-Process -Name pol -ErrorAction SilentlyContinue)
if ($clients.Count -eq 0) {
    throw 'No pol.exe clients are running.'
}

if ($ValidateOnly) {
    Write-Host "Validation passed: found $($clients.Count) clients and PresentMon."
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$presentPath = Join-Path $PSScriptRoot "ffxi-presentmon-combat-$stamp.csv"
$mapPath = Join-Path $PSScriptRoot "ffxi-process-map-combat-$stamp.csv"
$processPath = Join-Path $PSScriptRoot "ffxi-process-telemetry-$stamp.csv"
$systemPath = Join-Path $PSScriptRoot "ffxi-system-telemetry-$stamp.csv"
$gpuPath = Join-Path $PSScriptRoot "ffxi-gpu-telemetry-$stamp.csv"
$backgroundPath = Join-Path $PSScriptRoot "ffxi-background-telemetry-$stamp.csv"

$clientNames = @{}
$mapRows = foreach ($client in $clients) {
    $affinity = $null
    $priority = $null
    try {
        $affinity = '0x{0:X}' -f $client.ProcessorAffinity.ToInt64()
        $priority = $client.PriorityClass.ToString()
    }
    catch {
        # PresentMon can still map the process when Windows withholds scheduling details.
    }
    [pscustomobject]@{
        Id = $client.Id
        MainWindowTitle = $client.MainWindowTitle
        StartTime = $client.StartTime
        ProcessorAffinityHex = $affinity
        PriorityClass = $priority
    }
}
$mapRows | Export-Csv -NoTypeInformation -LiteralPath $mapPath
foreach ($client in $clients) {
    $clientNames[$client.Id] = $client.MainWindowTitle
}

$presentArguments = @(
    '--process_name', 'pol.exe',
    '--timed', [string]$DurationSeconds,
    '--terminate_after_timed',
    '--output_file', $presentPath,
    '--no_console_stats',
    '--no_track_input',
    '--v2_metrics'
)

Write-Host 'Preparing total and per-logical-CPU counters...'
$cpuCounter = [Diagnostics.PerformanceCounter]::new(
    'Processor', '% Processor Time', '_Total')
$dpcCounter = [Diagnostics.PerformanceCounter]::new(
    'Processor', '% DPC Time', '_Total')
$interruptCounter = [Diagnostics.PerformanceCounter]::new(
    'Processor', '% Interrupt Time', '_Total')
$contextCounter = [Diagnostics.PerformanceCounter]::new(
    'System', 'Context Switches/sec')
$memoryCounter = [Diagnostics.PerformanceCounter]::new(
    'Memory', 'Available MBytes')
$processorPerformanceCounter = [Diagnostics.PerformanceCounter]::new(
    'Processor Information', '% Processor Performance', '_Total')
$logicalProcessorCount = [Environment]::ProcessorCount
$logicalCpuCounters = @(
    for ($index = 0; $index -lt $logicalProcessorCount; $index++) {
        [Diagnostics.PerformanceCounter]::new(
            'Processor', '% Processor Time', [string]$index)
    }
)
foreach ($counter in @(
        $cpuCounter, $dpcCounter, $interruptCounter, $contextCounter,
        $memoryCounter, $processorPerformanceCounter) + $logicalCpuCounters) {
    [void]$counter.NextValue()
}

Write-Host "Capturing six-client combat for $DurationSeconds seconds."
Write-Host 'Fight normally for the whole capture; do not tab through clients.'
$presentProcess = Start-Process -FilePath $presentMonPath `
    -ArgumentList $presentArguments -NoNewWindow -PassThru

$nvidiaProcess = $null
$nvidiaPath = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
if (Test-Path -LiteralPath $nvidiaPath) {
    $nvidiaArguments = @(
        '--query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,power.draw,temperature.gpu,clocks.current.graphics,clocks.current.memory',
        '--format=csv,noheader,nounits',
        '--loop-ms=1000'
    )
    $nvidiaProcess = Start-Process -FilePath $nvidiaPath `
        -ArgumentList $nvidiaArguments `
        -RedirectStandardOutput $gpuPath `
        -WindowStyle Hidden -PassThru
}

$processCpuStart = @{}
foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
    try {
        $key = '{0}:{1}' -f $process.Id,
            $process.StartTime.ToUniversalTime().Ticks
        $processCpuStart[$key] = [pscustomobject]@{
            ProcessId = $process.Id
            ProcessName = $process.ProcessName
            MainWindowTitle = $process.MainWindowTitle
            TotalProcessorSeconds = [double]$process.CPU
        }
    }
    catch {
        # Some protected processes do not expose start time or CPU usage.
    }
}

$processRows = [Collections.Generic.List[object]]::new()
$systemRows = [Collections.Generic.List[object]]::new()
$timer = [Diagnostics.Stopwatch]::StartNew()
$nextProgress = 15

try {
    while (-not $presentProcess.HasExited -and
            $timer.Elapsed.TotalSeconds -lt ($DurationSeconds + 15)) {
        $now = Get-Date
        $elapsed = [math]::Round($timer.Elapsed.TotalSeconds, 3)
        foreach ($client in @(Get-Process -Name pol -ErrorAction SilentlyContinue)) {
            try {
                $processRows.Add([pscustomobject]@{
                    Timestamp = $now.ToString('o')
                    ElapsedSeconds = $elapsed
                    ProcessId = $client.Id
                    Character = $clientNames[$client.Id]
                    TotalProcessorSeconds = $client.CPU
                    WorkingSetBytes = $client.WorkingSet64
                    PrivateBytes = $client.PrivateMemorySize64
                    PagedBytes = $client.PagedMemorySize64
                    Handles = $client.HandleCount
                    Threads = $client.Threads.Count
                    Responding = $client.Responding
                })
            }
            catch {
                # A client may be between zone processes or exiting.
            }
        }
        $systemRow = [ordered]@{
            Timestamp = $now.ToString('o')
            ElapsedSeconds = $elapsed
            CpuPercent = [math]::Round($cpuCounter.NextValue(), 3)
            DpcPercent = [math]::Round($dpcCounter.NextValue(), 3)
            InterruptPercent = [math]::Round($interruptCounter.NextValue(), 3)
            ContextSwitchesPerSecond = [math]::Round(
                $contextCounter.NextValue(), 3)
            AvailableMemoryMB = [math]::Round($memoryCounter.NextValue(), 3)
            ProcessorPerformancePercent = [math]::Round(
                $processorPerformanceCounter.NextValue(), 3)
        }
        for ($index = 0; $index -lt $logicalProcessorCount; $index++) {
            $systemRow["Cpu${index}Percent"] = [math]::Round(
                $logicalCpuCounters[$index].NextValue(), 3)
        }
        $systemRows.Add([pscustomobject]$systemRow)

        if ($timer.Elapsed.TotalSeconds -ge $nextProgress) {
            Write-Host ("  {0}/{1} seconds captured..." -f
                [int]$timer.Elapsed.TotalSeconds, $DurationSeconds)
            $nextProgress += 15
        }
        Start-Sleep -Milliseconds 1000
        $presentProcess.Refresh()
    }
    $presentProcess.WaitForExit()
    $presentProcess.Refresh()
}
finally {
    if ($null -ne $nvidiaProcess -and -not $nvidiaProcess.HasExited) {
        Stop-Process -Id $nvidiaProcess.Id -Force -ErrorAction SilentlyContinue
        [void]$nvidiaProcess.WaitForExit(3000)
    }
    foreach ($counter in @(
            $cpuCounter, $dpcCounter, $interruptCounter,
            $contextCounter, $memoryCounter, $processorPerformanceCounter) +
            $logicalCpuCounters) {
        $counter.Dispose()
    }
}

$timer.Stop()
$processRows | Export-Csv -NoTypeInformation -LiteralPath $processPath
$systemRows | Export-Csv -NoTypeInformation -LiteralPath $systemPath

$measuredSeconds = [math]::Max($timer.Elapsed.TotalSeconds, 0.001)
$backgroundRows = foreach ($process in @(
        Get-Process -ErrorAction SilentlyContinue)) {
    try {
        $key = '{0}:{1}' -f $process.Id,
            $process.StartTime.ToUniversalTime().Ticks
        $start = $processCpuStart[$key]
        if ($null -eq $start) {
            continue
        }
        $cpuDelta = [math]::Max(
            [double]$process.CPU -
                [double]$start.TotalProcessorSeconds,
            0)
        [pscustomobject]@{
            ProcessId = $process.Id
            ProcessName = $process.ProcessName
            MainWindowTitle = if ($process.MainWindowTitle) {
                $process.MainWindowTitle
            }
            else {
                $start.MainWindowTitle
            }
            CpuSecondsDelta = [math]::Round($cpuDelta, 6)
            AverageCpuPercentOneCore = [math]::Round(
                100 * $cpuDelta / $measuredSeconds, 3)
            WorkingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
            PrivateMB = [math]::Round(
                $process.PrivateMemorySize64 / 1MB, 1)
        }
    }
    catch {
        # A process may exit while the ending snapshot is collected.
    }
}
$backgroundRows |
    Sort-Object AverageCpuPercentOneCore -Descending |
    Export-Csv -NoTypeInformation -LiteralPath $backgroundPath

$presentExitCode = $presentProcess.ExitCode
if ($null -ne $presentExitCode -and $presentExitCode -ne 0) {
    throw "PresentMon failed with exit code $presentExitCode."
}
if (-not (Test-Path -LiteralPath $presentPath) -or
        (Get-Item -LiteralPath $presentPath).Length -eq 0) {
    throw 'PresentMon did not produce a frame capture.'
}

Write-Host ''
Write-Host 'Combat capture complete.' -ForegroundColor Green
Write-Host "Frames:  $presentPath"
Write-Host "Map:     $mapPath"
Write-Host "Process: $processPath"
Write-Host "System:  $systemPath"
Write-Host "Background: $backgroundPath"
if (Test-Path -LiteralPath $gpuPath) {
    Write-Host "GPU:     $gpuPath"
}
