#!/bin/sh
# install.sh -- LingTeX-Word for Mac
#
# TO INSTALL: open Terminal (Applications > Utilities > Terminal), drag this file
# onto the Terminal window, and press Return. (Or type  sh  and a space first,
# then drag it in, then Return.) To remove LingTeX-Word, do the same with
#     --uninstall
# typed after the file's path.
#
# WHY A TERMINAL SCRIPT: macOS 27 will not open an unsigned installer or script
# document downloaded from the internet (Gatekeeper), and LingTeX-Word is not
# signed with a paid Apple developer certificate. A shell script run in Terminal
# is not checked by Gatekeeper, and everything it does is written out below.
#
# WHAT IT DOES: puts LingTeX-Word.dotm into Word's Startup folder, where Word
# loads it at every start, so the Interlinear tab is on every document:
#
#     ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word
#
#   - The template: the LingTeX-Word.dotm beside this script, or on a mounted
#     LingTeX-Word disk image; failing both, the newest LingTeX-Word release's
#     template is downloaded from GitHub. (A path given as an argument wins;
#     --download forces the download.)
#   - Word must be closed: the script waits, or quits Word for you if you type q
#     (Word then asks about any unsaved documents, as it always does).
#   - It copies the template in under a temporary name, removes the "downloaded
#     from the internet" mark (Word will not load a marked template from its
#     Startup folder), checks the copy is identical, and only then puts it in
#     place: a failed copy leaves the installed version as it was.
#   - Upgrading is running it again. Nothing else on the Mac is changed, and no
#     administrator password is needed.
#
# macOS may ask whether Terminal may access data from other apps (Word's folder)
# or control Microsoft Word (only if you type q). Allow it.

set -u

name="LingTeX-Word.dotm"
repo="rulingAnts/LingTeX-Tools"
here=$(cd "$(dirname "$0")" && pwd)
gc="${LINGTEX_OFFICE_GC:-$HOME/Library/Group Containers/UBF8T346G9.Office}"

die() { echo ""; echo "LingTeX-Word was not installed: $1"; exit 1; }

# Word's Startup folder: the .localized layout Word 2016 and later use, or an
# older plain one; whichever holds a Word folder, else the usual one is created.
startup="$gc/User Content.localized/Startup.localized/Word"
if [ ! -d "$startup" ] && [ -d "$gc/User Content/Startup/Word" ]; then
    startup="$gc/User Content/Startup/Word"
fi
dst="$startup/$name"

mode=install
src=""
for a in "$@"; do
    case "$a" in
        --uninstall) mode=uninstall ;;
        --download)  mode=download ;;
        *)           [ -f "$a" ] && src=$a ;;
    esac
done

# Word holds its Startup templates open while it runs.
if [ "${LINGTEX_IGNORE_WORD:-0}" != 1 ]; then
    while pgrep -xq "Microsoft Word"; do
        printf '%s' "Microsoft Word is open. Quit it, then press Return (or type q and Return to have Word quit now; Ctrl-C stops): "
        read -r ans || exit 1
        if [ "$ans" = q ] || [ "$ans" = Q ]; then
            osascript -e 'tell application "Microsoft Word" to quit saving ask' >/dev/null 2>&1
            i=0
            while pgrep -xq "Microsoft Word" && [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done
        fi
    done
fi

if [ "$mode" = uninstall ]; then
    if [ -f "$dst" ]; then
        rm -f "$dst" || die "could not remove $dst"
        echo "LingTeX-Word is removed. From the next start of Word, the Interlinear tab is gone."
    else
        echo "Nothing to remove: $name is not in Word's Startup folder."
    fi
    exit 0
fi

# The template to install.
tmpdl=""
if [ -z "$src" ] && [ "$mode" != download ]; then
    if [ -f "$here/$name" ]; then
        src="$here/$name"
    else
        for v in /Volumes/LingTeX-Word*; do
            if [ -f "$v/$name" ]; then src="$v/$name"; break; fi
        done
    fi
fi
if [ -z "$src" ]; then
    echo "Downloading the newest LingTeX-Word template from GitHub ..."
    # The LingTeX-Word release published last. Not the first one listed: GitHub
    # lists "word-v0.1.0-beta.9" before "word-v0.1.0-beta.10" (seen 2026-09-29).
    tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100" 2>/dev/null |
          grep -oE '"(tag_name|published_at)": *"[^"]*"' |
          awk -F'"' '$2 == "tag_name" { t = $4; next }
                     $2 == "published_at" && t ~ /^word-v/ { if ($4 > best) { best = $4; bt = t }; t = "" }
                     END { print bt }')
    [ -n "$tag" ] || die "no LingTeX-Word release was found on GitHub (is the Mac online?)."
    url="https://github.com/$repo/releases/download/$tag/$name"
    tmpdl=$(mktemp -t lingtexword) || die "no temporary file"
    curl -fsSL -o "$tmpdl" "$url" || { rm -f "$tmpdl"; die "the download failed: $url"; }
    echo "  from $url"
    src=$tmpdl
fi
cleanup() { if [ -n "$tmpdl" ]; then rm -f "$tmpdl"; fi; }

# A .dotm is a zip: it starts with "PK".
[ "$(head -c 2 "$src" 2>/dev/null)" = "PK" ] || { cleanup; die "$src is not a Word template."; }

upgrading=no
[ -f "$dst" ] && upgrading=yes

mkdir -p "$startup" 2>/dev/null || { cleanup; die "could not create Word's Startup folder. If macOS asked whether Terminal may access data from other apps, allow it and run this again."; }
stage="$startup/LingTeX-Word.installing"
cp "$src" "$stage" 2>/dev/null || { cleanup; die "could not copy into Word's Startup folder. If macOS asked whether Terminal may access data from other apps, allow it and run this again."; }
xattr -d com.apple.quarantine "$stage" 2>/dev/null
if ! cmp -s "$src" "$stage"; then
    rm -f "$stage"
    cleanup
    die "the copy is not identical to the original."
fi
mv -f "$stage" "$dst" || { rm -f "$stage"; cleanup; die "could not put the template in place."; }
cleanup

echo ""
if [ "$upgrading" = yes ]; then
    echo "LingTeX-Word is upgraded."
else
    echo "LingTeX-Word is installed."
fi
echo "  $dst"
if [ -f "$startup/LingTeX-Dev.dotm" ]; then
    echo ""
    echo "NOTE: LingTeX-Dev.dotm is in the same folder. That is the development rig,"
    echo "which loads its own copy of the code; with both, every command exists twice."
    echo "Move it out of the Startup folder while you use this one."
fi
echo ""
echo "Start Word. If it asks whether to enable macros in $name, choose Enable"
echo "Macros. A message then says LingTeX-Word is installed, and the Interlinear tab"
echo "is on the ribbon of every document."
