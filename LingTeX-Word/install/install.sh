#!/bin/sh
# install.sh -- LingTeX-Word for Mac
#
# TO INSTALL: open Terminal (Applications > Utilities > Terminal), drag this file
# onto the Terminal window, and press Return. (Or type  sh  and a space first,
# then drag it in, then Return.) To remove LingTeX-Word, do the same with
#     --uninstall
# typed after the file's path (two ordinary hyphens).
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
#   - The template: a LingTeX-Word.dotm given as an argument; else the one
#     beside this script; else the one on a mounted LingTeX-Word disk image;
#     else the newest LingTeX-Word release's template, downloaded from GitHub.
#     --download forces the download. It always says which one it installs.
#   - Word must be closed: the script waits, or quits your Word if you type q
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
vols="${LINGTEX_VOLUMES:-/Volumes}"
access="If macOS asked whether Terminal may access data from other apps, allow it and run this again. (System Settings > Privacy & Security can allow it later.)"

mode=install
verb="installed"
die() { echo ""; echo "LingTeX-Word was not $verb: $1"; exit 1; }

# Word's Startup folder: the .localized layout Word 2016 and later use, or an
# older plain one; whichever holds a Word folder, else the usual one is created.
startup="$gc/User Content.localized/Startup.localized/Word"
if [ ! -d "$startup" ] && [ -d "$gc/User Content/Startup/Word" ]; then
    startup="$gc/User Content/Startup/Word"
fi
dst="$startup/$name"

# Arguments: --uninstall, --download, or the path of a template. Anything else
# stops here, so a mistyped --uninstall never installs instead.
src=""
for a in "$@"; do
    case "$a" in
        --uninstall) [ "$mode" = install ] || die "give either --uninstall or --download, not both."
                     mode=uninstall; verb="removed" ;;
        --download)  [ "$mode" = install ] || die "give either --uninstall or --download, not both."
                     mode=download ;;
        -*)          die "unknown option: $a (the options are --uninstall and --download, with two hyphens)." ;;
        *)           [ -f "$a" ] || die "no such file: $a"
                     [ -z "$src" ] || die "give one template, not two."
                     src=$a ;;
    esac
done
[ "$mode" = uninstall ] && [ -n "$src" ] && die "--uninstall takes no file."

# Word holds its Startup templates open while it runs. Only this user's Word
# counts: another account's Word on the same Mac holds nothing here.
me=$(id -u)
if [ "${LINGTEX_IGNORE_WORD:-0}" != 1 ]; then
    while pgrep -xq -U "$me" "Microsoft Word"; do
        printf '%s' "Microsoft Word is open. Quit it, then press Return (or type q and Return to have Word quit now; Ctrl-C stops): "
        read -r ans || exit 1
        if [ "$ans" = q ] || [ "$ans" = Q ]; then
            if ! out=$(osascript -e 'tell application "Microsoft Word" to quit saving ask' 2>&1); then
                echo "Could not ask Word to quit ($out). Quit Word yourself (Word menu > Quit Word)."
            fi
            i=0
            while pgrep -xq -U "$me" "Microsoft Word" && [ $i -lt 60 ]; do sleep 1; i=$((i + 1)); done
        fi
    done
fi

if [ "$mode" = uninstall ]; then
    if [ -f "$dst" ]; then
        rm -f "$dst" || die "could not remove $dst. $access"
        echo "LingTeX-Word is removed. From the next start of Word, the Interlinear tab is gone."
        exit 0
    fi
    # Not there, or not visible? A folder macOS will not let Terminal read
    # looks exactly like an empty one to a file test.
    if [ -e "$gc" ] && ! ls "$gc" >/dev/null 2>&1; then
        die "could not look into Word's folder. $access"
    fi
    echo "Nothing to remove: $name is not in Word's Startup folder."
    exit 0
fi

# The template to install.
tmpdl=""
from=""
if [ -n "$src" ]; then
    from="the file you gave"
elif [ "$mode" != download ]; then
    if [ -f "$here/$name" ]; then
        src="$here/$name"
        from="beside this script"
    else
        found=""
        n=0
        for v in "$vols"/LingTeX-Word*; do
            if [ -f "$v/$name" ]; then found="$v/$name"; n=$((n + 1)); fi
        done
        if [ $n -gt 1 ]; then
            die "more than one LingTeX-Word disk image is mounted, so which one is newest is unclear. Eject the older ones in Finder and run this again."
        fi
        if [ $n -eq 1 ]; then
            src=$found
            from="on the mounted disk image"
        fi
    fi
fi
if [ -z "$src" ]; then
    echo "Downloading the newest LingTeX-Word template from GitHub ..."
    # The whole list first: a list cut off part way, or an error page, must stop
    # here rather than yield an older release. And the LingTeX-Word release
    # published last, not the first one listed: GitHub lists
    # "word-v0.1.0-beta.9" before "word-v0.1.0-beta.10" (seen 2026-09-29).
    json=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=100") ||
        die "could not read the list of releases from GitHub: the Mac is offline, or GitHub's hourly limit for this network was reached (try again in an hour)."
    tag=$(printf '%s\n' "$json" |
          grep -oE '"(tag_name|published_at)": *"[^"]*"' |
          awk -F'"' '$2 == "tag_name" { t = $4; next }
                     $2 == "published_at" && t ~ /^word-v/ { if ($4 > best) { best = $4; bt = t }; t = "" }
                     END { print bt }')
    [ -n "$tag" ] || die "no LingTeX-Word release was found on GitHub."
    url="https://github.com/$repo/releases/download/$tag/$name"
    tmpdl=$(mktemp -t lingtexword) || die "no temporary file"
    curl -fsSL -o "$tmpdl" "$url" || { rm -f "$tmpdl"; die "the download failed: $url"; }
    src=$tmpdl
    from="downloaded, release $tag"
fi
cleanup() { if [ -n "$tmpdl" ]; then rm -f "$tmpdl"; fi; }

# A LingTeX template: a zip ("PK") holding a Word VBA project.
if [ "$(head -c 2 "$src" 2>/dev/null)" != "PK" ] || ! unzip -l "$src" 2>/dev/null | grep -q "word/vbaProject.bin"; then
    cleanup
    die "$src is not a macro-enabled Word template."
fi
echo "Installing $name ($from):"
echo "  $src"

replacing=no
[ -f "$dst" ] && replacing=yes

mkdir -p "$startup" 2>/dev/null || { cleanup; die "could not create Word's Startup folder. $access"; }
stage="$startup/LingTeX-Word.installing"
cp "$src" "$stage" 2>/dev/null || { cleanup; die "could not copy into Word's Startup folder. $access"; }
xattr -d com.apple.quarantine "$stage" 2>/dev/null
if ! cmp -s "$src" "$stage"; then
    rm -f "$stage"
    cleanup
    die "the copy is not identical to the original."
fi
mv -f "$stage" "$dst" || { rm -f "$stage"; cleanup; die "could not put the template in place."; }
cleanup

echo ""
if [ "$replacing" = yes ]; then
    echo "LingTeX-Word is installed, replacing the copy that was there."
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
