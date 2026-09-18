$ErrorActionPreference = 'Stop'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('ffxi-config-test-' + [guid]::NewGuid())
$oldLocalAppData = $env:LOCALAPPDATA
try {
    [void](New-Item -ItemType Directory -Path "$sandbox/package/local/presets" -Force)
    [void](New-Item -ItemType Directory -Path "$sandbox/package/presets" -Force)
    Copy-Item -LiteralPath "$PSScriptRoot/Set-Preset.ps1" -Destination "$sandbox/package"
    foreach ($name in @('Cockpit', 'FullMain')) {
        Copy-Item -LiteralPath "$PSScriptRoot/presets/$name.json" -Destination "$sandbox/package/presets"
        $template = Get-Content -Raw "$PSScriptRoot/presets/$name.json" | ConvertFrom-Json
        if (@($template.characters.PSObject.Properties).Count -ne 0 -or
            $template.windowManagementEnabled -or $template.hidePrimaryTaskbarWhileFfxiRunning -or
            $template.keepSecondaryTaskbarsVisible -or $template.monitorRecovery.enabled) {
            throw 'Portable presets must have no machine actions configured.'
        }
        $template.presetName = "Local-$name"
        $template | ConvertTo-Json -Depth 8 | Set-Content "$sandbox/package/local/presets/$name.json"
    }
    $env:LOCALAPPDATA = "$sandbox/appdata"
    & "$sandbox/package/Set-Preset.ps1" -Name Cockpit
    if ((Get-Content -Raw "$sandbox/package/local/config.json" | ConvertFrom-Json).presetName -ne 'Local-Cockpit') {
        throw 'Local preset was not selected.'
    }
    [void](New-Item -ItemType Directory -Path "$sandbox/appdata/FFXIManager" -Force)
    & "$sandbox/package/Set-Preset.ps1" -Name FullMain
    if ((Get-Content -Raw "$sandbox/appdata/FFXIManager/config.json" | ConvertFrom-Json).presetName -ne 'Local-FullMain') {
        throw 'Installed destination was not selected.'
    }
    foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw "PowerShell parse errors: $($script.Name)" }
    }
    Write-Output 'Local configuration selection and portable defaults passed. No manager was started.'
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolved)).StartsWith('ffxi-config-test-')) { throw 'Unsafe cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
