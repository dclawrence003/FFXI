[CmdletBinding()]
param(
    [ValidateRange(1, 120)]
    [int]$Minutes = 15,

    [switch]$Json
)

$statusScript = Join-Path $PSScriptRoot 'status.mjs'
$partyOpsRoot = Join-Path $env:USERPROFILE 'Documents\Tesseract\FFXI\projects\FFXI-Private'
$nodeExecutable = $null

$partyOpsNode = Get-Process node -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$partyOpsRoot\.tools\*\node.exe" } |
    Select-Object -First 1 -ExpandProperty Path
if ($partyOpsNode) {
    $nodeExecutable = $partyOpsNode
}

if (-not $nodeExecutable) {
    $installedNode = Get-Command node -ErrorAction SilentlyContinue
    if ($installedNode) {
        $nodeExecutable = $installedNode.Source
    }
}

if (-not $nodeExecutable) {
    $bundledNode = Get-ChildItem -LiteralPath (Join-Path $partyOpsRoot '.tools') `
        -Filter node.exe -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ($bundledNode) {
        $nodeExecutable = $bundledNode
    }
}

if (-not $nodeExecutable) {
    throw 'Node.js was not found. Start PartyOps or set node.exe on PATH.'
}

$nodeArguments = @($statusScript, '--minutes', $Minutes.ToString())
if ($Json) {
    $nodeArguments += '--json'
}

& $nodeExecutable @nodeArguments
exit $LASTEXITCODE
