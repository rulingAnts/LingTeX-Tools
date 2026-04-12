@echo off
:: ── LingTeX Tools — Windows dev runner ────────────────────────────────────────
:: Loads the VS 2022 ARM64 build environment, then launches cargo tauri dev.
:: Run this from anywhere — it changes to src-tauri automatically.
:: Double-click it, or run from any cmd/PowerShell window (no admin needed).

set VSCMD="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"

if not exist %VSCMD% (
    echo [ERROR] VS 2022 Build Tools not found at expected path:
    echo         %VSCMD%
    echo         Please install VS 2022 Build Tools with the C++ workload.
    pause
    exit /b 1
)

:: Move to src-tauri relative to this batch file's location
cd /d "%~dp0src-tauri"

:: Load VS environment for ARM64, then run dev
call %VSCMD% -arch=arm64
cargo tauri dev
