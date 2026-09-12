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
#           --macro NAME  run only that macro (after the import), for bisecting;
#                         every *.txt it leaves in the reports folder is printed
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
# The hole: a COMPILE error, or a run-time error outside every trap, is a modal
# dialog inside the VBA editor. It is invisible to System Events (the editor's
# dialogs expose no accessibility elements at all -- probed 2026-09-12), so this
# script cannot read or dismiss it. What it CAN see is the editor's window title,
# which gains "[break]" while that dialog is up and stays that way after OK until
# Run > Reset. So after every macro this checks for "[break]": if found, it says
# so and stops, and the person at the keyboard reads the dialog and the
# highlighted line. Two consequences learned the hard way:
#   * VBA compiles a procedure when it is first REACHED, so an undefined name in a
#     procedure the tests call late shows up as a compile error half-way through
#     RunDocTests, after a hundred PASS lines. The static substitute is
#     tools/vba-lint.py; there is no project-wide compile a macro can trigger on
#     Mac (the VBE command-bar trick, FindControl 578, raises error 445 here).
#   * While the editor is in break mode NO macro can run: "run VB macro" fails
#     with "Can't continue run VB macro" (-1708). Run > Reset in the editor first.
# The Windows twin, run-in-word.ps1, does better: over COM with the editor hidden,
# a compile error comes back as an exception naming the module.
#
# POSIX sh; osascript does the Word driving.

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
conf="$root/build/runner.conf"

pull=1; import=1; tests=both; doc=""; extra=""; want=""
for a in "$@"; do
    if [ "$want" = macro ]; then extra="$extra $a"; want=""; continue; fi
    case "$a" in
        --macro)     want=macro; tests=none ;;
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
macros="$macros$extra"

#-- Dialogs -----------------------------------------------------------------
# A compile error, a run-time error outside every trap, or the macro-security
# prompt all appear as a modal dialog in Word, and "run VB macro" blocks until it
# is dismissed. So each macro runs in the background while this polls Word's
# windows through System Events: any dialog is READ (its text is the error), then
# DISMISSED with whichever button it has. That turns the one thing no macro can
# suppress into text on this terminal -- and lets a script, or a local Claude
# Code session, iterate without a person in the loop.
#
# Needs Accessibility permission for the terminal you run this from
# (System Settings > Privacy & Security > Accessibility). Without it dialogs are
# neither read nor dismissed, and the script says so once.
catch_dialog() {
    osascript 2>/dev/null <<'AS'
tell application "System Events"
    if not (exists process "Microsoft Word") then return ""
    tell process "Microsoft Word"
        repeat with w in windows
            set txt to ""
            try
                repeat with st in (every static text of w)
                    try
                        set txt to txt & (value of st) & linefeed
                    end try
                end repeat
            end try
            if txt contains "Compile error" or txt contains "Run-time error" or txt contains "Microsoft Visual Basic" or txt contains "macro" or txt contains "Macro" then
                set pressed to ""
                repeat with bname in {"OK", "End", "Enable Macros", "Run Anyway", "Open", "Yes", "Continue", "Trust"}
                    try
                        click button bname of w
                        set pressed to bname
                        exit repeat
                    end try
                end repeat
                return "[dialog] " & txt & "(dismissed with: " & pressed & ")"
            end if
        end repeat
    end tell
end tell
return ""
AS
}

# The VBA editor's window title carries "[break]" while it is stopped on an error.
vbe_in_break() {
    osascript -e 'tell application "System Events" to tell process "Microsoft Word" to get name of every window' 2>/dev/null \
        | grep -q "Visual Basic.*\[break\]"
}

if vbe_in_break; then
    echo "   The VBA editor is in break mode from an earlier error, so no macro can run."
    echo "   In the editor: click OK on any dialog, then Run > Reset. Then run this again."
    exit 1
fi

if ! osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1; then
    echo "   note: System Events is not reachable, so dialogs will not be read or"
    echo "         dismissed. Grant Accessibility permission to this terminal in"
    echo "         System Settings > Privacy & Security > Accessibility."
fi

echo "== Word: $(basename "$doc")"
for m in $macros; do
    echo "   running $m ..."
    osascript - "$doc" "$m" <<'AS' > "$reports/.osascript.$m" 2>&1 &
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
    pid=$!
    caught=""
    while kill -0 "$pid" 2>/dev/null; do
        sleep 2
        d=$(catch_dialog) || d=""
        if [ -n "$d" ]; then
            caught="$caught$d
"
            echo "$d" | sed 's/^/   /'
        fi
    done
    rc=0; wait "$pid" || rc=$?
    if [ -s "$reports/.osascript.$m" ]; then sed 's/^/   /' "$reports/.osascript.$m"; fi
    rm -f "$reports/.osascript.$m"

    if vbe_in_break; then
        echo ""
        echo "   Word's VBA editor is in BREAK mode after $m: a compile error or an"
        echo "   untrapped run-time error stopped it, and its dialog cannot be read from"
        echo "   here. Read the dialog and the highlighted line in the editor, click OK,"
        echo "   then Run > Reset before running anything again. Nothing after this"
        echo "   macro was run."
        exit 1
    fi
    case "$caught" in
        *"Compile error"*|*"Run-time error"*)
            echo ""
            echo "   $m stopped on the dialog above. Word has left the VBA editor on the"
            echo "   offending statement; the message text is the error, the highlighted"
            echo "   line is where. Nothing after this macro was run."
            exit 1 ;;
    esac
    if [ "$rc" -ne 0 ]; then
        echo ""
        echo "   $m did not return cleanly (see the osascript output above)."
        echo "   \"Can't continue run VB macro\" means the VBA editor is in break mode:"
        echo "   click OK on its dialog, then Run > Reset, and run this again."
        exit 1
    fi
done

echo ""
status=0
for p in "$reports"/*.txt; do
    [ -f "$p" ] || continue
    f=$(basename "$p")
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
