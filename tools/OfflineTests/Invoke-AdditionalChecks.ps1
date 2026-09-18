#Requires -Version 7.0
param([Parameter(Mandatory)][string]$NodeExe, [string]$PythonExe='python',
    [Parameter(Mandatory)][string]$Suite)
$ErrorActionPreference='Stop'
& $PythonExe -B "$PSScriptRoot/additional_suites.py" --suite $Suite --node $NodeExe
if ($LASTEXITCODE -ne 0) { throw "$Suite additional checks failed." }
