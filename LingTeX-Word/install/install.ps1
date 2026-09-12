# install.ps1 -- LingTeX-Word for Windows
#
# Puts LingTeX-Word.dotm into Word's STARTUP folder, where Word loads it as a
# global template at every start: the LingTeX tab and its commands are then on
# every document. The first time Word loads it, the add-in installs its keyboard
# shortcuts and says so.
#
#   Double-click install.bat, or from PowerShell:
#     powershell -ExecutionPolicy Bypass -File install.ps1
#     powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall
#
# Word must be closed while this runs.

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$name = "LingTeX-Word.dotm"
$src = Join-Path $here $name
$startup = Join-Path $env:APPDATA "Microsoft\Word\STARTUP"
$dst = Join-Path $startup $name

if (Get-Process WINWORD -ErrorAction SilentlyContinue) {
    Write-Host "Word is running. Close Word, then run this again."
    exit 1
}

if ($Uninstall) {
    if (Test-Path $dst) { Remove-Item -Force $dst; Write-Host "Removed $dst" }
    else { Write-Host "Nothing to remove: $dst is not there." }
    Write-Host "The keyboard shortcuts stayed in your Normal template only if you had"
    Write-Host "moved them there; the add-in kept its own in itself, so they are gone too."
    exit 0
}

if (-not (Test-Path $src)) {
    Write-Host "Cannot find $name beside this script ($src)."
    exit 1
}

New-Item -ItemType Directory -Force -Path $startup | Out-Null
# A file downloaded from the internet carries a mark that makes Word block its
# macros outright. Cleared on the copy and on the source.
Unblock-File -Path $src -ErrorAction SilentlyContinue
Copy-Item -Force $src $dst
Unblock-File -Path $dst -ErrorAction SilentlyContinue

Write-Host "Installed $dst"
Write-Host ""
Write-Host "Start Word. A message says LingTeX-Word is installed and lists its keyboard"
Write-Host "shortcuts (Ctrl+Alt+Shift + a letter); the LingTeX tab is on the ribbon of"
Write-Host "every document. Word's STARTUP folder is a trusted location, so no macro"
Write-Host "warning should appear; if one does, choose Enable."
