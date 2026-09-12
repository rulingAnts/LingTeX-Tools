#!/bin/sh
# add-ribbon.sh  --  LingTeX-Word
#
# Inject the ribbon (src/customUI14.xml) into the developer's working document,
# so the LingTeX tab is there during the by-hand pass instead of only in the
# packaged template. Same injection as build-dotm.sh, without the manifest.
#
#     sh LingTeX-Word/tools/add-ribbon.sh LingTeX-Word/LingTeX.docm
#
# Do it with the document CLOSED in Word: Word reads the ribbon when it opens
# the file, and a save from Word may or may not keep the part (re-run this if
# the tab disappears). The modules inside the document are whatever was last
# saved there, so after reopening run the test runner (or ImportLingTeXModules)
# once to bring them up to src/.
here=$(cd "$(dirname "$0")" && pwd)
[ -n "$1" ] || { echo "add-ribbon: give the path to LingTeX.docm" >&2; exit 2; }
RIBBON_ONLY=1 exec sh "$here/build-dotm.sh" "$1"
