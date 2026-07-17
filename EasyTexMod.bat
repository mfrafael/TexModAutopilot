@echo off
rem EasyTexMod - shortcut to run the script. Just double-click this file.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0EasyTexMod.ps1" %*
if errorlevel 1 (
    echo.
    echo Something went wrong - see EasyTexMod.log above.
    pause
)
