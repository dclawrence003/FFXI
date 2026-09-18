#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$NodeExe,
    [string]$PythonExe = 'python',
    [switch]$IncludeInstalledChecks
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent (Split-Path -Parent $root)
$NodeExe = (Resolve-Path -LiteralPath $NodeExe).Path
if ((& $NodeExe --version) -ne 'v24.18.0') { throw 'Use Node 24.18.0, matching PartyOps.' }
$dependencies = Join-Path $workspace 'tools/OfflineTests/node_modules'
$fengariCli = Join-Path $dependencies 'fengari-node-cli/src/lua-cli.js'
$luaParseCli = Join-Path $dependencies 'luaparse/bin/luaparse'
if (-not (Test-Path -LiteralPath $fengariCli) -or -not (Test-Path -LiteralPath $luaParseCli)) {
    throw 'Run tools/OfflineTests/Initialize.ps1 with the same NodeExe first.'
}
& $PythonExe -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11 or newer required"; print(sys.version)'
if ($LASTEXITCODE -ne 0) { throw 'Python preflight failed.' }
Write-Output "Installed-file checks: $($IncludeInstalledChecks.IsPresent). Node: $(& $NodeExe --version)"

& $NodeExe (Join-Path $workspace 'tools/OfflineTests/parse-lua.cjs') $root
if ($LASTEXITCODE -ne 0) { throw 'Lua syntax validation failed.' }
Push-Location $workspace
$previousInstalledChecks = $env:FFXI_TEST_INSTALLED
try {
    $env:FFXI_TEST_INSTALLED = if ($IncludeInstalledChecks) { '1' } else { '0' }
    function Invoke-LuaTest($path, $label) {
        $output = & $nodeExe $fengariCli $path 2>&1
        $output | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -match 'stack traceback:') {
            throw "$label failed."
        }
    }
    Invoke-LuaTest 'addons/PartyTactics/tests/test_profiles.lua' 'Profile/compiler Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_profile.lua' 'Locus Signet profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter.lua' 'Locus Signet adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v2.lua' 'Locus Signet protocol-2 adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v3.lua' 'Locus Signet companion-ready adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v4.lua' 'Locus Signet Flash-reservation adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v5.lua' 'Locus Signet profile-local PLD sustain adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v6.lua' 'Locus Signet duplicate-resume repair adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v7.lua' 'Locus Signet raw-keeper recovery adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v8.lua' 'Locus Signet DualEvis adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_adapter_v9.lua' 'Locus Signet exact-probe adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_signet_opener_e2e.lua' 'Locus Signet first-hit end-to-end Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_locus_host_puller_integration.lua' 'Real host/LocusPuller integration'
    $faultOutput = & $NodeExe $fengariCli 'addons/PartyTactics/tests/test_locus_host_puller_integration.lua' --drop-lp-ack 2>&1
    $faultText = $faultOutput -join "`n"
    if ($faultText -notmatch 'INJECTED FAULT: dropped real LP readiness ACK at transport' -or
        $faultText -notmatch 'READINESS FAILURE: real LP ACK did not reach actual GearSwap host/adapter' -or
        $faultText -match 'integration and stopped-late-ACK checks passed') {
        throw 'The dropped-ACK control did not fail at the expected readiness assertion.'
    }
    Write-Output 'Dropped-ACK negative control failed at the expected readiness assertion.'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_c_profile.lua' 'Sortie C profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_c_magic_burst_profile.lua' 'Sortie C Magic Burst profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_c_magic_burst_runtime.lua' 'Sortie C Magic Burst runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_c_magic_burst_adapter.lua' 'Sortie C Magic Burst adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_a_magic_kill_profile.lua' 'Sortie A Magic Kill profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_a_magic_kill_runtime.lua' 'Sortie A Magic Kill runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_a_magic_kill_adapter.lua' 'Sortie A Magic Kill adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_b_weapon_skill_profile.lua' 'Sortie B weapon-skill profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_b_weapon_skill_runtime.lua' 'Sortie B weapon-skill runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_b_weapon_skill_adapter.lua' 'Sortie B weapon-skill adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_d_profile.lua' 'Sortie D profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_boss_profiles.lua' 'Sortie boss profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_boss_tank_pull_runtime.lua' 'Sortie boss tank-first runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_main_profile.lua' 'Persistent Sortie main profile Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_main_runtime.lua' 'Persistent Sortie main runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_sortie_main_adapter.lua' 'Persistent Sortie main adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_identity_extensions.lua' 'Identity extension Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_supplemental_aliases.lua' 'Supplemental alias Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_action_api.lua' 'Typed action API Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_six_client_activation.lua' 'Six-client Lua tests'
    $consumerOutput = & $NodeExe $fengariCli 'addons/PartyTactics/tests/test_profile_consumer_lab.lua' 2>&1
    $consumerText = $consumerOutput -join "`n"
    $consumerOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or $consumerText -match 'stack traceback:' -or
        $consumerText -notmatch 'PASS - real coordinator/consumer stale Sortie stop isolation and explicit stop') {
        throw 'Coordinator/consumer integration failed.'
    }
    $consumerFault = & $NodeExe $fengariCli 'addons/PartyTactics/tests/test_profile_consumer_lab.lua' --inject-stale-stop 2>&1
    $consumerFaultText = $consumerFault -join "`n"
    if ($consumerFaultText -notmatch 'INJECTED FAULT: leaked old-owner OFF reaches real PartyCombat' -or
        $consumerFaultText -notmatch 'STALE_SORTIE_DISRUPTED_REPLACEMENT:' -or
        $consumerFaultText -match 'PASS - real coordinator/consumer') {
        throw 'Consumer fault control did not detect a real combat stop.'
    }
    Write-Output 'Consumer fault control detected the injected stop in actual PartyCombat.'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_preflight.lua' 'Preflight evaluator Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_v1_runtime.lua' 'V1 runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_genmei_runtime.lua' 'Genmei runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_gearswap_host.lua' 'GearSwap host Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_genmei_adapter.lua' 'Genmei GearSwap adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_kammavaca_runtime.lua' 'Kammavaca runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_qutrub_runtime.lua' 'September Qutrub runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_qutrub_adapter.lua' 'September Qutrub GearSwap adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_qutrub_no_cait_runtime.lua' 'September Qutrub no-Cait runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_qutrub_no_cait_adapter.lua' 'September Qutrub no-Cait GearSwap adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_hydra_runtime.lua' 'September Hydra runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_september_hydra_adapter.lua' 'September Hydra GearSwap adapter Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_rancibus_runtime.lua' 'Rancibus runtime Lua tests'
    Invoke-LuaTest 'addons/PartyTactics/tests/test_rancibus_adapter.lua' 'Rancibus GearSwap adapter Lua tests'
    & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -ExecutionPolicy Bypass -File `
        'addons/PartyTactics/tests/test_profile_scaffold.ps1'
    if ($LASTEXITCODE -ne 0) { throw 'Profile scaffold tests failed.' }
    & $PythonExe -B -m unittest discover -s 'addons/PartyTactics/tests' -p 'test_source_guards.py'
    if ($LASTEXITCODE -ne 0) { throw 'Python source-guard tests failed.' }
    & $PythonExe -B -m unittest discover -s 'addons/PartyTactics/tests' -p 'test_sortie_main_source.py'
    if ($LASTEXITCODE -ne 0) { throw 'Persistent Sortie source-isolation tests failed.' }
    & $PythonExe -B -m unittest discover -s 'addons/PartyTactics/tests' -p 'test_analysis_specs.py'
    if ($LASTEXITCODE -ne 0) { throw 'Analysis sidecar tests failed.' }
} finally {
    $env:FFXI_TEST_INSTALLED = $previousInstalledChecks
    Pop-Location
}
