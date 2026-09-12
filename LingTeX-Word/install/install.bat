@echo off
rem install.bat -- LingTeX-Word for Windows: double-click to install.
rem Runs install.ps1 beside it; Word must be closed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
