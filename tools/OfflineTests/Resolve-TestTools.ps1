#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$NodeExe, [string]$PythonExe = 'python')
$ErrorActionPreference = 'Stop'
$node = (Resolve-Path -LiteralPath $NodeExe).Path
if ((& $node --version) -ne 'v24.18.0') { throw 'Node 24.18.0 is required, matching PartyOps.' }
$python = (Get-Command $PythonExe -ErrorAction Stop).Source
& $python -c 'import sys; assert sys.version_info >= (3, 11)'
if ($LASTEXITCODE -ne 0) { throw 'Python 3.11 or newer is required.' }
$fengari = Join-Path $PSScriptRoot 'node_modules/fengari-node-cli/src/lua-cli.js'
$parser = Join-Path $PSScriptRoot 'parse-lua.cjs'
foreach ($required in @($fengari, $parser)) {
    if (-not (Test-Path -LiteralPath $required)) { throw 'Run tools/OfflineTests/Initialize.ps1 first.' }
}
[pscustomobject]@{ Node = $node; Python = $python; Fengari = $fengari; Parser = $parser }
