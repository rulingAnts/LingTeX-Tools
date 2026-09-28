#!/bin/sh
# run-in-powerpoint.sh  --  LingTeX-PowerPoint
#
# ONE COMMAND: copy the modules where PowerPoint may read them, import them
# into the dev presentation, run macros, print the reports.
#
#     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh ~/Documents/LingTeX-PowerPoint-Dev.pptm
#
# The presentation's path is remembered in build/runner.conf, so afterwards:
#
#     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh
#
# Options:  --macro NAME   run NAME after the import; repeatable. With none,
#                          the probe runs (ProbePowerPointQuiet).
#           --tests        run the test suite (PptTestsRun) instead of the probe
#           --no-import    run the macros without importing first
#           --no-stage     do not refresh build/shared from LingTeX-Word first
#           --undo-check   after the macros: read the Edit menu's first item,
#                          press Cmd+Z once in PowerPoint, read it again, and
#                          append both to the last report (the undo count, with
#                          nobody at the keyboard; needs Accessibility)
#           --commit       commit the reports afterwards (default: do not)
#           --remove-startup-probe
#                          delete the test add-in MakeStartupProbeAddIn put in
#                          PowerPoint's Startup folder, and stop
#
# Set up once: the header of tools/modLingTeXDev.bas.
#
# HOW IT WORKS
#
# PowerPoint's AppleScript has "run VB macro" (Contents/Resources/PowerPoint.sdef):
# it runs a macro that already exists, and nothing can be injected. So
# modLingTeXDev, pasted by hand once, is the one macro home, and it imports
# everything else. Modules and reports pass through PowerPoint's own Documents
# folder, because PowerPoint is sandboxed and a file-access prompt would block
# this script:
#
#     ~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/
#         LingTeX-PowerPoint-src/       the modules, and modules.txt naming them
#         LingTeX-PowerPoint-reports/   the reports, copied back into the clone
#
# A dialog -- a compile error, a run-time error, the macro prompt -- blocks
# "run VB macro". While each macro runs, this reads PowerPoint's windows
# through System Events and prints and dismisses any dialog, as run-in-word.sh
# does. That needs Accessibility permission for the terminal this runs in
# (System Settings > Privacy & Security > Accessibility).
#
# POSIX sh; osascript drives PowerPoint.

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
conf="$root/build/runner.conf"
box="$HOME/Library/Containers/com.microsoft.Powerpoint/Data/Documents"
stage="$box/LingTeX-PowerPoint-src"
boxreports="$box/LingTeX-PowerPoint-reports"
reports="$root/LingTeX-PowerPoint-reports"
startup_probe="$HOME/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint/LingTeXStartupProbe.ppam"

# What is imported, in order, relative to LingTeX-PowerPoint/. The five modules
# shared with LingTeX-Word come from build/shared, which tools/stage-shared.sh
# fills from one git revision of LingTeX-Word (see its header); src/ holds
# PowerPoint's own. The clipboard normaliser PowerPoint calls
# (NormalizeClipboardText, in modIgtModel since 2026-09-28) must be in the
# staged revision: the check below refuses to run without it.
MODULES="
tools/modLingTeXDevCore.bas
build/shared/modFlexParse.bas
build/shared/modIgtModel.bas
build/shared/clsIgtWarning.cls
build/shared/modLeipzig.bas
build/shared/modWrap.bas
src/modPptClipboard.bas
src/modPptFormat.bas
src/modPptMeasure.bas
src/modPptCompose.bas
src/modPptInsert.bas
src/modPptRewrap.bas
src/modPptTests.bas
tools/probe/modProbe.bas
tools/probe/modProbeEvents.bas
tools/probe/clsProbeEvents.cls
tools/probe/modProbePaste.bas
tools/probe/modProbeSave.bas
tools/probe/modProbeClipboard.bas
"

import=1; commit=0; pres=""; macros=""; want=""; stage_shared=1; undo_check=0
for a in "$@"; do
    if [ "$want" = macro ]; then macros="$macros $a"; want=""; continue; fi
    case "$a" in
        --macro)      want=macro ;;
        --tests)      macros="$macros PptTestsRun" ;;
        --no-import)  import=0 ;;
        --no-stage)   stage_shared=0 ;;
        --undo-check) undo_check=1 ;;
        --commit)     commit=1 ;;
        --remove-startup-probe)
            rm -f "$startup_probe" && echo "removed $startup_probe"; exit 0 ;;
        -h|--help)    sed -n '2,24p' "$0"; exit 0 ;;
        *)            pres=$a ;;
    esac
done
[ -z "$macros" ] && macros="ProbePowerPointQuiet"

if [ -z "$pres" ] && [ -f "$conf" ]; then pres=$(cat "$conf"); fi
if [ -z "$pres" ]; then
    echo "run-in-powerpoint: give the path to the dev presentation, e.g." >&2
    echo "    sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh ~/Documents/LingTeX-PowerPoint-Dev.pptm" >&2
    echo "(making it: the header of LingTeX-PowerPoint/tools/modLingTeXDev.bas)" >&2
    exit 2
fi
case "$pres" in /*) ;; *) pres="$(pwd)/$pres" ;; esac
[ -f "$pres" ] || { echo "run-in-powerpoint: no such presentation: $pres" >&2; exit 2; }
mkdir -p "$root/build"; printf '%s\n' "$pres" > "$conf"
presname=$(basename "$pres")
[ -d "$box" ] || { echo "run-in-powerpoint: $box is missing; start PowerPoint once first" >&2; exit 2; }

#-- Stage the modules -------------------------------------------------------
# Copies the named modules (relative to LingTeX-PowerPoint/) into the folder
# PowerPoint reads, with modules.txt naming them in order.
stage_modules() {
    rm -rf "$stage"; mkdir -p "$stage"
    : > "$stage/modules.txt"
    for m in "$@"; do
        [ -f "$root/$m" ] || { echo "run-in-powerpoint: missing module $m" >&2; exit 2; }
        cp "$root/$m" "$stage/"
        basename "$m" >> "$stage/modules.txt"
    done
}
# The shared modules, fresh from LingTeX-Word; PowerPoint's own modules call the
# shared clipboard normaliser, so a revision without it cannot be imported.
if [ "$stage_shared" = 1 ]; then
    sh "$here/stage-shared.sh" || exit 2
fi
grep -q 'Function NormalizeClipboardText' "$root/build/shared/modIgtModel.bas" "$root/build/shared/modFlexParse.bas" 2>/dev/null || {
    echo "run-in-powerpoint: build/shared has no NormalizeClipboardText; stage from claude/lingtex-word-crlf 790d140 or later (tools/stage-shared.sh [REV])" >&2; exit 2; }
for m in $MODULES; do
    [ -f "$root/$m" ] || { echo "run-in-powerpoint: missing module $m" >&2; exit 2; }
done
mkdir -p "$boxreports" "$reports"
rm -f "$boxreports"/*.mac.txt

# The probe's clipboard section and the tests read what is on the clipboard:
# put the made-up FLEx copy there, the same one the tests hold as Fixture()
# (LingTeX-Word/samples/checklist-sample.txt: real FLEx shape, a free line
# with no leading tab, a non-ASCII length mark). LINGTEX_CLIP_EOL=lf for
# Mac/Unix line breaks; Windows (CR LF) otherwise, as FLEx on Windows copies.
# pbcopy reads its input in the locale's encoding: without a UTF-8 locale a
# non-ASCII letter arrived as two MacRoman characters (2026-09-15).
sample="$root/../LingTeX-Word/samples/checklist-sample.txt"
case "$macros" in
    *Probe*|*PptTests*)
        [ -f "$sample" ] || { echo "run-in-powerpoint: missing $sample" >&2; exit 2; }
        if [ "${LINGTEX_CLIP_EOL:-crlf}" = lf ]; then
            LC_ALL=en_US.UTF-8 pbcopy < "$sample"
        else
            awk '{ printf "%s\r\n", $0 }' "$sample" | LC_ALL=en_US.UTF-8 pbcopy
        fi
        echo "== the clipboard now holds the made-up FLEx copy, ${LINGTEX_CLIP_EOL:-crlf} line breaks" ;;
esac

#-- Dialogs ------------------------------------------------------------------
catch_dialog() {
    osascript 2>/dev/null <<'AS'
tell application "System Events"
    if not (exists process "Microsoft PowerPoint") then return ""
    tell process "Microsoft PowerPoint"
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
                repeat with bname in {"OK", "End", "Enable Macros", "Enable", "Run Anyway", "Open", "Yes", "Continue", "Trust"}
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

vbe_in_break() {
    osascript -e 'tell application "System Events" to tell process "Microsoft PowerPoint" to get name of every window' 2>/dev/null \
        | grep -q "Visual Basic.*\[break\]"
}

if vbe_in_break; then
    echo "   PowerPoint's VBA editor is in break mode from an earlier error, so no macro"
    echo "   can run. In the editor: OK on any dialog, then Run > Reset. Then run this again."
    exit 1
fi

# Run one macro in the background, reading and dismissing dialogs meanwhile.
# $2: the name as PowerPoint should be given it.
run_macro() {
    label=$1; name=$2
    osascript - "$pres" "$name" "$presname" > "$root/build/.osascript" 2>&1 <<'AS' &
on run argv
    set presPath to item 1 of argv
    set macroName to item 2 of argv
    set presName to item 3 of argv
    tell application "Microsoft PowerPoint"
        -- "name of every presentation", not a loop over presentations: reading
        -- "name of p" inside a repeat fails here (-2763, 2026-09-15).
        set isOpen to false
        try
            if (name of every presentation) contains presName then set isOpen to true
        end try
        if not isOpen then open (POSIX file presPath)
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
    if [ -s "$root/build/.osascript" ]; then sed 's/^/   /' "$root/build/.osascript"; fi
    rm -f "$root/build/.osascript"
    if vbe_in_break; then
        echo "   PowerPoint's VBA editor is in BREAK mode after $label: read the dialog and"
        echo "   the highlighted line there, click OK, then Run > Reset. Nothing after it ran."
        exit 1
    fi
    case "$caught" in
        *"Compile error"*|*"Run-time error"*)
            echo "   $label stopped on the dialog above. Nothing after it ran."; exit 1 ;;
    esac
    return $rc
}

echo "== PowerPoint: $presname"

# The first macro settles how PowerPoint wants a name: bare, or with the file.
echo "   running LingTeXDevPing ..."
qualify=""
run_macro LingTeXDevPing LingTeXDevPing || true
if [ ! -f "$boxreports/Ping.mac.txt" ]; then
    echo "   (no answer to the bare name; trying $presname!LingTeXDevPing)"
    run_macro LingTeXDevPing "$presname!LingTeXDevPing" || true
    if [ -f "$boxreports/Ping.mac.txt" ]; then
        qualify="$presname!"
    else
        echo ""
        echo "   LingTeXDevPing did not run. Is modLingTeXDev in $presname, and are macros"
        echo "   enabled for it? (the header of tools/modLingTeXDev.bas)"
        exit 1
    fi
fi

# The import, in two phases. The hand-pasted modLingTeXDev is only the
# bootstrap: it imports modLingTeXDevCore, the importer proper, which can
# itself be fixed and re-imported without pasting anything. Its AddFromString
# on the Mac doubled every line of a class (CR and LF counted as two breaks);
# the core finds the separator that counts as one, and checks line counts.
if [ "$import" = 1 ]; then
    stage_modules tools/modLingTeXDevCore.bas
    echo "   running ImportLingTeXModulesQuiet (the bootstrap: modLingTeXDevCore only) ..."
    if ! run_macro ImportLingTeXModulesQuiet "${qualify}ImportLingTeXModulesQuiet" || \
       ! grep -q "ALL IMPORTED" "$boxreports/ImportModules.mac.txt" 2>/dev/null; then
        cat "$boxreports/ImportModules.mac.txt" 2>/dev/null
        echo "   the bootstrap could not import modLingTeXDevCore (see above)."
        exit 1
    fi
    stage_modules $MODULES
    rm -f "$boxreports/ImportModules.mac.txt"
    echo "   running LingTeXDevImport ..."
    if ! run_macro LingTeXDevImport "${qualify}LingTeXDevImport"; then
        echo "   LingTeXDevImport did not return cleanly (see above)."
        exit 1
    fi
    # A module that failed to import leaves the project unable to compile what
    # depends on it: stop before any macro runs into that as a dialog.
    if grep -q "FAILED\|PROBLEM" "$boxreports/ImportModules.mac.txt" 2>/dev/null; then
        cat "$boxreports/ImportModules.mac.txt"
        echo "   the import reported a problem (above), so nothing else was run."
        exit 1
    fi
fi
all="$macros"
for m in $all; do
    echo "   running $m ..."
    if ! run_macro "$m" "$qualify$m"; then
        echo "   $m did not return cleanly (see above)."
        exit 1
    fi
done

#-- The undo count, mechanically ------------------------------------------------
# What the Edit menu offers to undo, before and after one Cmd+Z in PowerPoint.
# The frontmost presentation is the probe's (it has a window); the label is
# what the user would read, "Undo Paste" after round 5's one paste.
if [ "$undo_check" = 1 ]; then
    u=$(osascript 2>&1 <<'AS'
tell application "Microsoft PowerPoint" to activate
delay 1
tell application "System Events" to tell process "Microsoft PowerPoint"
    set before to name of menu item 1 of menu "Edit" of menu bar 1
    keystroke "z" using command down
    delay 1
    set after to name of menu item 1 of menu "Edit" of menu bar 1
    return "Edit menu offered: '" & before & "'; after one Cmd+Z it offers: '" & after & "'"
end tell
AS
)
    echo "== undo check: $u"
    last=$(ls -t "$boxreports"/*.mac.txt 2>/dev/null | grep -v Ping | head -1)
    [ -n "$last" ] && printf '\n== undo check (run-in-powerpoint.sh --undo-check)\n%s\n' "$u" >> "$last"
fi

#-- Reports ------------------------------------------------------------------
echo ""
status=0
for p in "$boxreports"/*.mac.txt; do
    [ -f "$p" ] || continue
    f=$(basename "$p")
    cp "$p" "$reports/$f"
    [ "$f" = Ping.mac.txt ] && continue
    echo "==================== $f ===================="
    cat "$p"
    echo ""
    if grep -q "PROBLEM\|FAILED\|CRASH" "$p"; then status=1; fi
done
if [ "$import" = 1 ] && [ ! -f "$boxreports/ImportModules.mac.txt" ]; then
    echo "no ImportModules.mac.txt: the import wrote nothing"; status=1
fi

if [ "$commit" = 1 ]; then
    if git -C "$root" add -- "$reports"/*.mac.txt 2>/dev/null && \
       git -C "$root" commit -q -m "LingTeX-PowerPoint reports (mac)" -- "$reports"/*.mac.txt 2>/dev/null; then
        echo "== reports committed: $(git -C "$root" log --oneline -1)"
    else
        echo "== reports unchanged; nothing committed"
    fi
fi
echo "reports: $reports"
exit $status
