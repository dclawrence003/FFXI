$ErrorActionPreference = 'Stop'
$Project = Split-Path -Parent $MyInvocation.MyCommand.Path
$NodeCommand = Get-Command node -ErrorAction SilentlyContinue

if (-not $NodeCommand) {
    throw 'Node.js was not found on PATH. Install Node.js 22.5 or newer and reopen PowerShell.'
}

$NodeExe = $NodeCommand.Source
$VersionText = & $NodeExe --version
$Major = [int](($VersionText -replace '^v', '').Split('.')[0])
if ($Major -lt 22) {
    throw "InventoryCore requires Node.js 22.5 or newer; found $VersionText."
}

if (-not (Test-Path (Join-Path $Project 'config.json'))) {
    throw 'Missing config.json. Copy config.example.json to config.json and configure local paths first.'
}

& $NodeExe (Join-Path $Project 'src\refresh.js')
$Listening = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
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
Start-Process 'http://127.0.0.1:8787'
