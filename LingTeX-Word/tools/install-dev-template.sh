#!/bin/sh
# install-dev-template.sh  --  LingTeX-Word
#
# Finish setting up the working template in Word's startup folder, with Word
# QUIT: put the ribbon in it, tell it where the clone is (the LingTeX_DevRoot
# variable that SetDevRoot would set from inside Word), and point the test
# runner at it. After this: start Word, then  sh LingTeX-Word/tools/run-in-word.sh
#
#     sh LingTeX-Word/tools/install-dev-template.sh "<startup folder>/LingTeX.dotm"
#
# The template itself is made in Word: open the file that holds modImport,
# File > Save As > Word Macro-Enabled Template, into the startup folder.
# Re-running this is safe; do it again after any ribbon change.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
dotm=$1
[ -n "$dotm" ] || { echo "install-dev-template: give the path to LingTeX.dotm in Word's startup folder" >&2; exit 2; }
[ -f "$dotm" ] || { echo "install-dev-template: no such file: $dotm" >&2; exit 2; }
if pgrep -x "Microsoft Word" >/dev/null 2>&1; then
    echo "install-dev-template: quit Word first -- it holds the template open." >&2
    exit 1
fi
RIBBON_ONLY=1 sh "$here/build-dotm.sh" "$dotm" || exit 1
python3 "$here/set-dev-root.py" "$dotm" "$root" || exit 1
mkdir -p "$root/build"; printf '%s\n' "$dotm" > "$root/build/runner.conf"
echo "  runner will use $dotm"
echo "Now start Word, then:  sh LingTeX-Word/tools/run-in-word.sh"
