param(
    [switch]$NoBrowser,
    [switch]$Foreground,
    [switch]$SkipRefresh
)

$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeCommand = Get-Command node -ErrorAction SilentlyContinue

if (-not $NodeCommand) {
    $NodeCandidates = @(
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\nodejs\node.exe'),
        (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
    )
    $NodePath = $NodeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($NodePath) {
        $NodeCommand = Get-Item -LiteralPath $NodePath
    }
}

if (-not $NodeCommand) {
    throw 'Node.js was not found. Install Node.js 22.5 or newer, or run InventoryCore from Codex once its bundled runtime is available.'
}

$NodeExe = if ($NodeCommand.Source) { $NodeCommand.Source } else { $NodeCommand.FullName }
$VersionText = & $NodeExe --version
$Major = [int](($VersionText -replace '^v', '').Split('.')[0])
if ($Major -lt 22) {
    throw "InventoryCore requires Node.js 22.5 or newer; found $VersionText."
}

if (-not (Test-Path (Join-Path $Project 'config.json'))) {
    throw 'Missing config.json. Copy config.example.json to config.json and configure local paths first.'
}

if (-not $SkipRefresh) {
    & $NodeExe (Join-Path $Project 'src\refresh.js')
}
$Listening = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue

if ($Foreground) {
    if ($Listening) {
        Write-Output 'InventoryCore is already listening on 127.0.0.1:8787.'
        exit 0
    }
    & $NodeExe (Join-Path $Project 'src\server.js')
    exit $LASTEXITCODE
}

if (-not $Listening) {
    Start-Process -FilePath $NodeExe -ArgumentList 'src\server.js' -WorkingDirectory $Project -WindowStyle Hidden
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        try {
            Invoke-WebRequest 'http://127.0.0.1:8787/api/summary' -UseBasicParsing | Out-Null
            break
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
}
if (-not $NoBrowser) {
    Start-Process 'http://127.0.0.1:8787'
}
