#!/bin/sh
# install.sh -- LingTeX-Word for Mac
#
# Puts LingTeX-Word.dotm into Word's Startup folder, where Word loads it as a
# global template at every start: the Interlinear tab and its commands are then on
# every document. The first time Word loads it, the add-in installs its keyboard
# shortcuts and says so.
#
# For Terminal and the dev rig. The release ships the Script Editor documents
# "Install LingTeX-Word" and "Uninstall LingTeX-Word" in its disk image
# instead, which do the same copy. In Terminal:
#     sh install.sh
#     sh install.sh --uninstall
#
# Word must be quit while this runs.

here=$(cd "$(dirname "$0")" && pwd)
name="LingTeX-Word.dotm"
src="$here/$name"
startup="$HOME/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word"
dst="$startup/$name"

if pgrep -xq "Microsoft Word"; then
    echo "Word is running. Quit Word, then run this again."
    exit 1
fi

if [ "$1" = "--uninstall" ]; then
    if [ -f "$dst" ]; then rm -f "$dst"; echo "Removed $dst"; else echo "Nothing to remove: $dst is not there."; fi
    exit 0
fi

[ -f "$src" ] || { echo "Cannot find $name beside this script ($src)."; exit 1; }

mkdir -p "$startup"
# A file downloaded from the internet is quarantined, and Word refuses to load
# a quarantined template from Startup. Cleared on the copy.
cp -f "$src" "$dst"
xattr -d com.apple.quarantine "$dst" 2>/dev/null

echo "Installed $dst"
if [ -f "$startup/LingTeX-Dev.dotm" ]; then
    echo ""
    echo "NOTE: LingTeX-Dev.dotm is in the same folder. That is the development rig,"
    echo "which loads its own copy of the code; with both, every command exists twice."
    echo "Move LingTeX-Dev.dotm out of the Startup folder to test this install."
fi
echo ""
echo "Start Word. If it asks whether to enable macros in LingTeX-Word.dotm, choose"
echo "Enable Macros (Word > Preferences > Security can make that permanent). A"
echo "message then says LingTeX-Word is installed and lists its keyboard shortcuts"
echo "(Cmd+Option+Shift + a letter); the Interlinear tab is on the ribbon of every"
echo "document."
