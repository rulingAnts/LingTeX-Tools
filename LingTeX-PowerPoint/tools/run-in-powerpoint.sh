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
#           --no-import    run the macros without importing first
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

# What is imported, in order, relative to LingTeX-PowerPoint/. The modules
# shared with Word will be listed here as ../LingTeX-Word/src/<name>.bas.
MODULES="
tools/probe/modProbe.bas
"

import=1; commit=0; pres=""; macros=""; want=""
for a in "$@"; do
    if [ "$want" = macro ]; then macros="$macros $a"; want=""; continue; fi
    case "$a" in
        --macro)      want=macro ;;
        --no-import)  import=0 ;;
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
rm -rf "$stage"; mkdir -p "$stage" "$boxreports" "$reports"
: > "$stage/modules.txt"
for m in $MODULES; do
    [ -f "$root/$m" ] || { echo "run-in-powerpoint: missing module $m" >&2; exit 2; }
    cp "$root/$m" "$stage/"
    basename "$m" >> "$stage/modules.txt"
done
rm -f "$boxreports"/*.mac.txt

# The probe's clipboard section reads what is on the clipboard: make that a
# FLEx-shaped sample, with tabs, Windows line breaks and a non-ASCII letter.
case "$macros" in
    *Probe*) printf 'Word\tLos\tni\303\261os\r\nMorphemes\tLos\tni\303\261\t-o\t-s\r\nFree\tThe children.\r\n' | pbcopy
             echo "== the clipboard now holds a FLEx-shaped sample (for the probe)" ;;
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
        set isOpen to false
        repeat with p in presentations
            if (name of p) is presName then set isOpen to true
        end repeat
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

all=""
[ "$import" = 1 ] && all="ImportLingTeXModulesQuiet"
all="$all $macros"
for m in $all; do
    echo "   running $m ..."
    if ! run_macro "$m" "$qualify$m"; then
        echo "   $m did not return cleanly (see above)."
        exit 1
    fi
done

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
case "$all" in
    *ImportLingTeXModulesQuiet*) [ -f "$boxreports/ImportModules.mac.txt" ] || { echo "no ImportModules.mac.txt: the import wrote nothing"; status=1; } ;;
esac

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
