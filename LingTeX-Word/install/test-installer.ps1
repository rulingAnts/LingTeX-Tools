# test-installer.ps1 -- LingTeX-Word: runs the Windows installer for real.
#
# A silent (/S) install, an upgrade, the two things that can defeat an upgrade
# (Word running, the installed template held open) and an uninstall, each
# checked on the file system and in the registry. Run by
# .github/workflows/lingtex-word-installer-test.yml on a Windows runner.
# Runnable on any Windows machine with Word closed, but it installs and removes
# LingTeX-Word for the current user, so not on one where it is in use.
#
#   pwsh test-installer.ps1 -Old Setup-0.0.1-test.exe -New Setup-0.0.2-test.exe -Template LingTeX-Word.dotm
#
# Exit 0 when every check passes, 1 otherwise.

param(
    [Parameter(Mandatory)] [string] $Old,
    [Parameter(Mandatory)] [string] $New,
    [Parameter(Mandatory)] [string] $Template,
    [string] $OldVersion = '0.0.1-test',
    [string] $NewVersion = '0.0.2-test'
)

$ErrorActionPreference = 'Stop'
foreach ($p in @($Old, $New, $Template)) { if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" } }
$Old = (Resolve-Path -LiteralPath $Old).Path
$New = (Resolve-Path -LiteralPath $New).Path
$Template = (Resolve-Path -LiteralPath $Template).Path

$startup = Join-Path $env:APPDATA 'Microsoft\Word\STARTUP'
$dst     = Join-Path $startup 'LingTeX-Word.dotm'
$appHome = Join-Path $env:APPDATA 'LingTeX-Word'
$uninst  = Join-Path $appHome 'Uninstall.exe'
$key     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LingTeX-Word'
$older   = 'an older LingTeX-Word.dotm'
$script:fails = 0

function Check([string] $name, [bool] $ok) {
    if ($ok) { Write-Host "  OK    $name" } else { Write-Host "  FAIL  $name"; $script:fails++ }
}
# NSIS exit codes: 0 done, 1 cancelled by the user, 2 stopped by the script.
function Invoke-Setup([string] $exe, [string[]] $argList) {
    (Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru).ExitCode
}
# An uninstaller copies itself to TEMP and returns at once; _?= runs it in
# place and waits (it then cannot delete itself, which does not matter here).
function Invoke-Uninstall { Invoke-Setup $uninst @('/S', "_?=$appHome") }
function Get-Hash([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Get-RegisteredVersion { (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).DisplayVersion }
function Set-Older { [System.IO.File]::WriteAllText($dst, $older) }
function Test-Older { (Test-Path -LiteralPath $dst) -and ([System.IO.File]::ReadAllText($dst) -eq $older) }
function Test-Current { (Test-Path -LiteralPath $dst) -and ((Get-Hash $dst) -eq (Get-Hash $Template)) }

Write-Host "`n-- fresh install --"
Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
$rc = Invoke-Setup $Old @('/S')
Check "exits 0 (got $rc)" ($rc -eq 0)
Check "the template is in STARTUP, identical to the one built in" (Test-Current)
Check "Settings > Apps lists it at $OldVersion" ((Get-RegisteredVersion) -eq $OldVersion)
Check "the uninstaller is in its own folder, not in STARTUP" ((Test-Path -LiteralPath $uninst) -and -not (Test-Path -LiteralPath (Join-Path $startup 'Uninstall.exe')))

Write-Host "`n-- upgrade over an older copy that carries a mark of the web --"
Set-Older
Set-Content -LiteralPath $dst -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
$rc = Invoke-Setup $New @('/S')
Check "exits 0 (got $rc)" ($rc -eq 0)
Check "the older copy is replaced" (Test-Current)
Check "no mark of the web is left on it" (-not (Get-Item -LiteralPath $dst -Stream * | Where-Object Stream -eq 'Zone.Identifier'))
Check "Settings > Apps now says $NewVersion" ((Get-RegisteredVersion) -eq $NewVersion)

Write-Host "`n-- Word running with no window (a WINWORD.EXE process) --"
$fake = Join-Path ([System.IO.Path]::GetTempPath()) 'WINWORD.EXE'
Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\PING.EXE') -Destination $fake -Force
$word = Start-Process -FilePath $fake -ArgumentList '-n', '300', '127.0.0.1' -PassThru -WindowStyle Hidden
try {
    Start-Sleep -Seconds 2
    Set-Older
    $rc = Invoke-Setup $New @('/S')
    Check "the installer stops (exit $rc)" ($rc -ne 0)
    Check "and leaves the installed copy alone" (Test-Older)
    $rc = Invoke-Uninstall
    Check "the uninstaller stops too (exit $rc)" ($rc -ne 0)
    Check "and leaves the file in place" (Test-Path -LiteralPath $dst)
} finally {
    Stop-Process -Id $word.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
$rc = Invoke-Setup $New @('/S')
Check "with Word gone, the installer replaces the file (exit $rc)" (($rc -eq 0) -and (Test-Current))

Write-Host "`n-- the installed copy held open by something else --"
Set-Older
$held = [System.IO.File]::Open($dst, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
try {
    $rc = Invoke-Setup $New @('/S')
    Check "the installer stops rather than report success (exit $rc)" ($rc -ne 0)
    $rc = Invoke-Uninstall
    Check "the uninstaller stops too (exit $rc)" ($rc -ne 0)
} finally {
    $held.Close()
}
Check "the copy is untouched" (Test-Older)
$rc = Invoke-Setup $New @('/S')
Check "once released, the installer replaces it (exit $rc)" (($rc -eq 0) -and (Test-Current))

Write-Host "`n-- uninstall --"
$rc = Invoke-Uninstall
Check "exits 0 (got $rc)" ($rc -eq 0)
Check "the template is gone from STARTUP" (-not (Test-Path -LiteralPath $dst))
Check "Settings > Apps no longer lists it" (-not (Test-Path -Path $key))

Write-Host ""
if ($script:fails -eq 0) { Write-Host "ALL PASS"; exit 0 }
Write-Host "$($script:fails) problem(s)"
exit 1
