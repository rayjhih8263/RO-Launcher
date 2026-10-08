@echo off
setlocal
title RO Client Check and Launcher
cd /d "%~dp0"
if not exist "Test-RepairClient.ps1" goto missing
if not exist "RO-Launcher.exe" goto missing
echo Checking Client files. Please wait...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RepairClient.ps1" -ClientRoot "." -Repair
if errorlevel 1 goto failed
echo Check and repair completed. Opening launcher...
start "" /D "%~dp0" "%~dp0RO-Launcher.exe"
if errorlevel 1 goto failed
exit /b 0
:missing
echo Required files missing: Test-RepairClient.ps1 or RO-Launcher.exe.
pause
exit /b 1
:failed
echo Check, repair or launcher startup failed. Please save the error shown above.
echo The launcher was not opened by this script.
pause
exit /b 1
