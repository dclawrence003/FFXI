#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$NodeExe,
    [string]$PythonExe = 'python',
    [ValidateSet('All','PartyTactics','ConquestCash','ExpeditionGuide','JubileeKeeper','LocusPuller','SignetKeeper','InventoryCore','CoreManager','ReleasePackage','FastFollow','IncidentMemory')]
    [string]$Suite = 'All'
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$settingsPath = Join-Path $PSScriptRoot 'local.settings.json'
if (-not $NodeExe -and (Test-Path -LiteralPath $settingsPath)) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $NodeExe = [string]$settings.node_executable
    if (-not $PSBoundParameters.ContainsKey('PythonExe') -and $settings.python_executable) {
        $PythonExe = [string]$settings.python_executable
    }
}
if (-not $NodeExe) { throw 'Supply -NodeExe pointing to Node 24.18.0, or configure local.settings.json.' }
$tools = & (Join-Path $PSScriptRoot 'Resolve-TestTools.ps1') -NodeExe $NodeExe -PythonExe $PythonExe
$suites = if ($Suite -eq 'All') {
    @('PartyTactics','ConquestCash','ExpeditionGuide','JubileeKeeper','LocusPuller','SignetKeeper','InventoryCore','CoreManager','ReleasePackage','FastFollow','IncidentMemory')
} else { @($Suite) }
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$reportRoot = Join-Path $PSScriptRoot "reports/$runId"
New-Item -ItemType Directory -Path $reportRoot | Out-Null
$results = @()
foreach ($name in $suites) {
    $runner = Join-Path $workspace "addons/$name/tests/run_tests.ps1"
    $extraArguments = @()
    if ($name -in @('InventoryCore','CoreManager','ReleasePackage','FastFollow','IncidentMemory')) {
        $runner = Join-Path $PSScriptRoot 'Invoke-AuxiliaryChecks.ps1'
        $extraArguments = @('-Suite', $name)
    }
    $log = Join-Path $reportRoot "$name.log"
    Write-Output "Running $name offline checks..."
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $runner -NodeExe $tools.Node -PythonExe $tools.Python @extraArguments *> $log
    $code = $LASTEXITCODE
    $timer.Stop()
    $record = [ordered]@{
        suite = $name
        exit_code = $code
        seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
        runner_sha256 = (Get-FileHash -LiteralPath $runner).Hash.ToLowerInvariant()
        log = $log
        log_sha256 = (Get-FileHash -LiteralPath $log).Hash.ToLowerInvariant()
    }
    $results += $record
    Write-Output "$name finished: exit $code, $($record.seconds) seconds."
}
[ordered]@{
    recorded_at = (Get-Date).ToString('o')
    workspace = $workspace
    node = (& $tools.Node --version)
    python = (& $tools.Python --version)
    lock_sha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'package-lock.json')).Hash.ToLowerInvariant()
    installed_file_checks = $false
    live_commands = $false
    suites = $results
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportRoot 'result.json') -Encoding utf8
Write-Output "Report: $reportRoot"
if (@($results | Where-Object { $_.exit_code -ne 0 }).Count) { throw 'One or more suites failed. See the named suite logs.' }
