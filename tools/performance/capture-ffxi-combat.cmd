@echo off
setlocal

set "duration=180"
if not "%~1"=="" set "duration=%~1"

fltmc >nul 2>&1
if errorlevel 1 (
    echo The combat capture needs administrator rights for PresentMon.
    echo Requesting elevation now...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%duration%' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture-ffxi-combat.ps1" -DurationSeconds %duration%

echo.
pause
endlocal
