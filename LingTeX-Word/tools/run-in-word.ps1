# run-in-word.ps1  --  LingTeX-Word
#
# The Windows twin of run-in-word.sh: pull, re-import, run both suites, print the
# reports.  Drives Word over COM, which has one advantage the Mac script cannot
# have: with the VBA editor hidden, a COMPILE error comes back to this script as an
# exception that names the module, instead of a modal dialog nobody can dismiss
# from outside.
#
#     powershell -ExecutionPolicy Bypass -File LingTeX-Word\tools\run-in-word.ps1 C:\path\to\LingTeX.docm
#
# Needs the same one-time setup as the Mac script: modImport pasted into the
# project with SRC_FOLDER set, and "Trust access to the VBA project object model"
# ticked.  Untested by the author -- written from the COM contract; report what it
# does.

param(
    [string]$Doc = "",
    [switch]$NoPull,
    [switch]$NoImport,
    [ValidateSet("both", "all", "doc")][string]$Tests = "both"
)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$conf = Join-Path $root "build\runner.conf"
if (-not $Doc -and (Test-Path $conf)) { $Doc = Get-Content $conf -Raw | ForEach-Object { $_.Trim() } }
if (-not $Doc) { Write-Error "give the path to the document that holds the VBA project"; exit 2 }
$Doc = (Resolve-Path $Doc).Path
New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
Set-Content -Path $conf -Value $Doc

$reports = Join-Path (Split-Path -Parent $Doc) "LingTeX-Word-reports"

if (-not $NoPull) { Write-Host "== git pull"; git -C $root pull --ff-only }
if (Test-Path $reports) { Remove-Item -Recurse -Force $reports }
New-Item -ItemType Directory -Force -Path $reports | Out-Null

$macros = @()
if (-not $NoImport) { $macros += "ImportLingTeXModulesQuiet" }
switch ($Tests) {
    "all"  { $macros += "RunAllTestsToFile" }
    "doc"  { $macros += "RunDocTestsToFile" }
    "both" { $macros += "RunAllTestsToFile", "RunDocTestsToFile" }
}

$word = New-Object -ComObject Word.Application
$word.Visible = $true
$status = 0
try {
    $null = $word.Documents.Open($Doc)
    foreach ($m in $macros) {
        Write-Host "   running $m ..."
        try {
            $word.Run($m)
        } catch {
            # This is the advantage over the Mac script: a module that does not
            # compile surfaces HERE, as text, naming the module.
            Write-Host ""
            Write-Host "   $m failed: $($_.Exception.Message)"
            $status = 1
            break
        }
    }
} finally {
    # Leave Word open with the document, so a failure can be looked at.
}

Write-Host ""
foreach ($f in "ImportModules.txt", "RunAllTests.txt", "RunDocTests.txt") {
    $p = Join-Path $reports $f
    if (-not (Test-Path $p)) { continue }
    Write-Host "==================== $f ===================="
    $text = Get-Content $p -Raw
    Write-Host $text
    if ($text -match "FAILURES|CRASH|PROBLEM|FAILED") { $status = 1 }
}
Write-Host "reports: $reports"
exit $status
