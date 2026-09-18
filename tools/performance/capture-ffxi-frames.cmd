@echo off
setlocal

fltmc >nul 2>&1
if errorlevel 1 (
    echo PresentMon needs administrator rights to read the FFXI processes.
    echo Requesting elevation now...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Capturing all pol.exe clients for 20 seconds.
echo Keep playing normally during the capture...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $capturePath = Join-Path '%~dp0' ('ffxi-presentmon-' + $stamp + '.csv'); $mapPath = Join-Path '%~dp0' ('ffxi-process-map-' + $stamp + '.csv'); Get-Process -Name pol -ErrorAction SilentlyContinue | Select-Object Id, MainWindowTitle, StartTime | Export-Csv -NoTypeInformation -LiteralPath $mapPath; & '%~dp0PresentMon-2.5.1-x64.exe' --process_name pol.exe --timed 20 --terminate_after_timed --output_file $capturePath --no_console_stats --no_track_input --v2_metrics; if ($LASTEXITCODE -eq 0) { Write-Host ''; Write-Host ('Saved capture to: ' + $capturePath) -ForegroundColor Green; Write-Host ('Saved client map to: ' + $mapPath) -ForegroundColor Green } else { Write-Host ''; Write-Host ('PresentMon failed with exit code ' + $LASTEXITCODE) -ForegroundColor Red }"

echo.
pause
endlocal
