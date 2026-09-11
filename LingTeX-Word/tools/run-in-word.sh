#!/bin/sh
# run-in-word.sh  --  LingTeX-Word
#
# ONE COMMAND: pull, re-import the modules into Word, run both test suites, print
# the reports. Replaces paste / run / screenshot with:
#
#     sh LingTeX-Word/tools/run-in-word.sh ~/path/to/LingTeX.docm
#
# The document path is remembered in build/runner.conf, so after the first time:
#
#     sh LingTeX-Word/tools/run-in-word.sh
#
# Options:  --no-pull     do not git pull first
#           --no-import   do not re-import the modules (sources unchanged)
#           --tests all   run RunAllTests only;   --tests doc   RunDocTests only
#
# HOW IT WORKS, AND ITS ONE HOLE
#
# Word for Mac exposes "run VB macro" to AppleScript (verified by
# tools/probe/Probe AppleScript Bridge.applescript) but not "do Visual Basic", so a
# script can run a macro that already exists and cannot inject one. Every macro this
# drives therefore already lives in the project: ImportLingTeXModulesQuiet in
# modImport (pasted by hand once, with SRC_FOLDER set), and RunAllTestsToFile /
# RunDocTestsToFile in the suites. Each writes its report to a file in
#
#     <folder of the document>/LingTeX-Word-reports/
#
# and shows no dialog -- a dialog would block "run VB macro" until someone clicked
# OK, which is the whole reason the quiet entry points exist.
#
# The hole: a COMPILE error is a modal dialog inside the VBA editor that no macro
# can suppress, so if a module does not compile this script waits and Word sits
# there with the dialog open. That is what the timeout and the message below are
# for. The Windows twin, run-in-word.ps1, does better: over COM with the editor
# hidden, a compile error comes back as an exception naming the module.
#
# POSIX sh; osascript does the Word driving.

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
conf="$root/build/runner.conf"

pull=1; import=1; tests=both; doc=""
for a in "$@"; do
    case "$a" in
        --no-pull)   pull=0 ;;
        --no-import) import=0 ;;
        --tests)     tests=NEXT ;;
        all|doc|both) if [ "$tests" = NEXT ] || [ "$tests" = both ]; then tests=$a; fi ;;
        -h|--help)   sed -n '2,30p' "$0"; exit 0 ;;
        *)           doc=$a ;;
    esac
done
[ "$tests" = NEXT ] && tests=both

# Remember the document path.
if [ -z "$doc" ] && [ -f "$conf" ]; then doc=$(cat "$conf"); fi
if [ -z "$doc" ]; then
    echo "run-in-word: give the path to the Word document that holds the VBA project," >&2
    echo "             e.g.  sh tools/run-in-word.sh ~/Documents/LingTeX.docm" >&2
    exit 2
fi
case "$doc" in /*) ;; *) doc="$(pwd)/$doc" ;; esac
[ -f "$doc" ] || { echo "run-in-word: no such document: $doc" >&2; exit 2; }
mkdir -p "$root/build"; printf '%s\n' "$doc" > "$conf"

reports="$(dirname "$doc")/LingTeX-Word-reports"

if [ "$pull" = 1 ]; then
    echo "== git pull"
    git -C "$root" pull --ff-only || echo "   (pull failed; running on what is checked out)"
fi

rm -rf "$reports"; mkdir -p "$reports"

macros=""
[ "$import" = 1 ] && macros="$macros ImportLingTeXModulesQuiet"
case "$tests" in
    all)  macros="$macros RunAllTestsToFile" ;;
    doc)  macros="$macros RunDocTestsToFile" ;;
    both) macros="$macros RunAllTestsToFile RunDocTestsToFile" ;;
esac

echo "== Word: $(basename "$doc")"
for m in $macros; do
    echo "   running $m ..."
    if ! osascript - "$doc" "$m" <<'AS' 2>&1; then
on run argv
    set docPath to item 1 of argv
    set macroName to item 2 of argv
    tell application "Microsoft Word"
        activate
        open (POSIX file docPath)
        with timeout of 3600 seconds
            run VB macro macro name macroName
        end timeout
    end tell
end run
AS
        echo ""
        echo "   $m did not return cleanly. If Word is showing a dialog, that is why:"
        echo "   a COMPILE error (the one thing no macro can suppress), or the"
        echo "   macro-security prompt. Switch to Word, read it, dismiss it."
        exit 1
    fi
done

echo ""
status=0
for f in ImportModules.txt RunAllTests.txt RunDocTests.txt; do
    [ -f "$reports/$f" ] || continue
    echo "==================== $f ===================="
    cat "$reports/$f"
    echo ""
    if grep -q "FAILURES\|CRASH\|PROBLEM\|FAILED" "$reports/$f"; then status=1; fi
done

case "$macros" in
    *RunAllTestsToFile*) [ -f "$reports/RunAllTests.txt" ] || { echo "no RunAllTests.txt -- the macro ran but wrote nothing; if Word could not write beside the document, the report opened as a document in Word instead"; status=1; } ;;
esac
case "$macros" in
    *RunDocTestsToFile*) [ -f "$reports/RunDocTests.txt" ] || { echo "no RunDocTests.txt -- see above"; status=1; } ;;
esac

echo "reports: $reports"
exit $status
