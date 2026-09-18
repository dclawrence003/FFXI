#Requires -Version 7.0
param([Parameter(Mandatory)][string]$NodeExe, [string]$PythonExe = 'python',
    [Parameter(Mandatory)][ValidateSet('InventoryCore','CoreManager','ReleasePackage','FastFollow')][string]$Suite)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tools = & "$PSScriptRoot/Resolve-TestTools.ps1" -NodeExe $NodeExe -PythonExe $PythonExe
$previousNode = $env:FFXI_TEST_NODE_EXE
Push-Location $workspace
try {
    $env:FFXI_TEST_NODE_EXE = $tools.Node
    switch ($Suite) {
        'InventoryCore' { & $tools.Node --test 'tools/InventoryCore/test/*.test.js' }
        'CoreManager' { & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File 'tools/FFXI-Core-Manager/Test-LocalConfiguration.ps1' }
        'ReleasePackage' { & $tools.Python -B -m unittest discover -s tools/OfflineTests -p test_release_package.py }
        'FastFollow' { & $tools.Python -B -m unittest discover -s patches/FastFollow/tests -p test_safe_zone.py }
    }
    if ($LASTEXITCODE -ne 0) { throw "$Suite checks failed." }
} finally {
    $env:FFXI_TEST_NODE_EXE = $previousNode
    Pop-Location
}
