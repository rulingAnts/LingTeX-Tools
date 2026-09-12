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
# project (it reads src beside the document), and "Trust access to the VBA project object model"
# ticked.  Untested by the author -- written from the COM contract; report what it
# does.

param(
    [string]$Doc = "",
    [switch]$NoPull,
    [switch]$NoImport,
    [switch]$NoCommit,
    [ValidateSet("both", "all", "doc")][string]$Tests = "both"
)

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$conf = Join-Path $root "build\runner.conf"
if (-not $Doc -and (Test-Path $conf)) { $Doc = Get-Content $conf -Raw | ForEach-Object { $_.Trim() } }
if (-not $Doc) { Write-Error "give the path to the document that holds the VBA project"; exit 2 }
$Doc = (Resolve-Path $Doc).Path
New-Item -ItemType Directory -Force -Path (Join-Path $root "build") | Out-Null
Set-Content -Path $conf -Value $Doc

$reports = Join-Path $root "LingTeX-Word-reports"

if (-not $NoPull) { Write-Host "== git pull"; git -C $root pull --ff-only }
New-Item -ItemType Directory -Force -Path $reports | Out-Null
# Only this platform's reports are replaced; the Mac ones sit beside them.
Get-ChildItem -Path $reports -Filter *.win.txt | Remove-Item -Force
$imp = Join-Path $reports "ImportModules.txt"; if (Test-Path $imp) { Remove-Item -Force $imp }

$macros = @()
if (-not $NoImport) { $macros += "ImportLingTeXModulesQuiet" }
switch ($Tests) {
    "all"  { $macros += "RunAllTestsToFile", "AutoExec" }
    "doc"  { $macros += "RunDocTestsToFile", "AutoExec" }
    "both" { $macros += "RunAllTestsToFile", "RunDocTestsToFile", "AutoExec" }
}

$word = New-Object -ComObject Word.Application
$word.Visible = $true
$status = 0
try {
    # A .dotm is expected to be loaded from Word's STARTUP folder as a global
    # add-in, not opened as a document (see run-in-word.sh). A .docm is opened.
    if ($Doc -notmatch '\.dotm$') { $null = $word.Documents.Open($Doc) }
    if ($word.Documents.Count -eq 0) { $null = $word.Documents.Add() }
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
$summary = ""
$files = @(Join-Path $reports "ImportModules.txt") + @(Get-ChildItem -Path $reports -Filter *.win.txt | Sort-Object Name | ForEach-Object { $_.FullName })
foreach ($p in $files) {
    if (-not (Test-Path $p)) { continue }
    $f = Split-Path -Leaf $p
    Write-Host "==================== $f ===================="
    $text = Get-Content $p -Raw
    Write-Host $text
    if ($text -match "FAILURES|CRASH|PROBLEM|FAILED") { $status = 1 }
    if ($text -match "(ALL PASS -- \d+ passed|FAILURES -- .*FAILED)") { $summary += " " + ($f -replace "\.win\.txt$", "") + ": " + $Matches[1] + ";" }
}
foreach ($stale in "RunAllTests.txt", "RunDocTests.txt") {
    $sp = Join-Path $reports $stale
    if (Test-Path $sp) {
        Write-Host "   STALE MODULES: the run wrote $stale (no platform tag), so the modules Word"
        Write-Host "   imported are older than $root\src. ImportModules.txt says where it read"
        Write-Host "   from (the 'from' line); the document must sit in LingTeX-Word beside src."
        Remove-Item -Force $sp
        $status = 1
    }
}
if (-not $NoCommit -and $status -eq 0 -and $summary -ne "") {
    # Commit and push this platform's reports, and nothing else, so a session on
    # the Mac can pull and read them. See the Mac script for the convention.
    $mine = @(Get-ChildItem -Path $reports -Filter *.win.txt | ForEach-Object { $_.FullName })
    git -C $root add -- $mine 2>$null | Out-Null
    git -C $root commit -q -m "LingTeX-Word reports (win):$summary" -- $mine 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "== reports committed: $(git -C $root log --oneline -1)"
        git -C $root push -q 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "   and pushed" } else { Write-Host "   (push failed; the commit is local -- push by hand)" }
    } else {
        Write-Host "== reports unchanged; nothing committed"
    }
}
Write-Host "reports: $reports"
exit $status
