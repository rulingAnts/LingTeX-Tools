#!/bin/sh
# install-dev-template.sh  --  LingTeX-Word
#
# Finish setting up the two-template dev loop, with Word QUIT:
#
#   the DEV template   LingTeX-Dev.dotm   in Word's startup folder, holding only
#                      modImport (made once in Word, see below), which loads the
#                      engine at Word start and re-imports it on demand;
#   the ENGINE template   LingTeX-Word/LingTeX.dotm   in the clone, the add-in
#                      itself, which this script gives the ribbon.
#
#     sh LingTeX-Word/tools/install-dev-template.sh
#
# What it does: moves an engine template still sitting in the startup folder
# (the earlier arrangement) into the clone; injects the ribbon into it; writes
# the clone's location into the dev template (the LingTeX_DevRoot variable, what
# SetDevRoot does from inside Word); points the test runner at the engine.
# Re-running is safe; run it again after any ribbon change.
#
# Making the dev template, once, in Word: new document; Tools > Macro > Visual
# Basic Editor; Insert > Module; paste tools/ImportModules.bas without its first
# line; name the module modImport; File > Save As > Word Macro-Enabled Template,
# LingTeX-Dev.dotm, into the startup folder. Quit Word, run this.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
die() { echo "install-dev-template: $1" >&2; exit 1; }

if pgrep -x "Microsoft Word" >/dev/null 2>&1; then
    die "quit Word first -- it holds the templates open."
fi

# Word's startup folder on this Mac (Word > Settings > File Locations > Startup).
for d in "$HOME/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word" \
         "$HOME/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word"; do
    [ -d "$d" ] && { startup=$d; break; }
done
[ -n "$startup" ] || die "cannot find Word's startup folder; Word > Settings > File Locations > Startup shows it"

engine="$root/LingTeX.dotm"
dev="$startup/LingTeX-Dev.dotm"

#-- the engine: into the clone if it is still in the startup folder ------------
if [ ! -f "$engine" ] && [ -f "$startup/LingTeX.dotm" ]; then
    mv "$startup/LingTeX.dotm" "$engine"
    rm -f "$startup/~\$ingTeX.dotm"
    echo "  moved LingTeX.dotm from the startup folder into $root"
fi
[ -f "$engine" ] || die "no engine template at $engine
Make it in Word: open the file that holds the modules, File > Save As > Word
Macro-Enabled Template, LingTeX.dotm, into $root"
if [ -f "$startup/LingTeX.dotm" ]; then
    # Left over from the one-template arrangement. Word would load it too, and
    # "run VB macro" would find ITS old modImport first, inside a protected
    # add-in -- which is exactly what happened on 2026-09-12. Word ignores
    # files in the startup folder that are not templates, so a rename disables it.
    mv "$startup/LingTeX.dotm" "$startup/LingTeX.dotm.old"
    rm -f "$startup/~\$ingTeX.dotm"
    rm -rf "$startup/LingTeX-Word-reports"
    echo "  disabled the stale LingTeX.dotm in the startup folder (renamed .old)"
fi
RIBBON_ONLY=1 sh "$here/build-dotm.sh" "$engine" || exit 1

#-- the dev template: where the clone is --------------------------------------
[ -f "$dev" ] || die "no dev template at $dev
Make it in Word (once): new document; Tools > Macro > Visual Basic Editor;
Insert > Module; paste $here/ImportModules.bas without its first line; name
the module modImport; File > Save As > Word Macro-Enabled Template,
LingTeX-Dev.dotm, into
  $startup
Quit Word and run this again."
python3 "$here/set-dev-root.py" "$dev" "$root" || exit 1

mkdir -p "$root/build"; printf '%s\n' "$engine" > "$root/build/runner.conf"
echo "  runner will address $engine"
echo "Now start Word (the dev template loads the engine), then:  sh LingTeX-Word/tools/run-in-word.sh"
