@echo off
rem TexModAutopilot - shortcut to run the script. Just double-click this file.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TexModAutopilot.ps1" %*
if errorlevel 1 (
    echo.
    echo Something went wrong - see TexModAutopilot.log above.
    pause
)
