#!/bin/sh
# word-clean-slate.sh -- LingTeX-Word, Mac
#
# Takes every trace of LingTeX out of Word for this user, so the installer can
# be tested the way a new user meets it, and puts it all back afterwards.
#
#   sh LingTeX-Word/tools/word-clean-slate.sh status
#   sh LingTeX-Word/tools/word-clean-slate.sh park       (Word quit)
#       ... install from the disk image, start Word, test ...
#   sh LingTeX-Word/tools/word-clean-slate.sh restore    (Word quit)
#
# What LingTeX in Word is, on a Mac:
#   Startup folder    LingTeX-Dev.dotm, the dev rig, which loads the engine from
#                     the clone at every Word start -- so an Interlinear tab
#                     appears with no LingTeX-Word.dotm installed at all; an
#                     installed LingTeX-Word.dotm; a stale LingTeX.dotm or .old;
#                     Word's owner files for them (~$ngTeX...); an installer's
#                     LingTeX-Word.installing left behind.
#   Templates folder  LingTeX*.dotm copies: not loaded at start, but templates
#                     Word can still attach.
#   Normal.dotm       where a first run records itself (LingTeX_Setup) and may
#                     bind shortcuts. park saves a copy; restore puts that copy
#                     back, so a test's first run leaves nothing behind.
#
# Nothing is deleted. park MOVES the files into build/word-clean-slate/ in the
# clone (git-ignored), with a manifest of where each came from; restore moves
# them back. Whatever LingTeX the test left -- the installed template, Normal
# as the test left it -- goes to build/word-clean-slate-after/<time>/.
#
# Why a script: dragging LingTeX-Dev.dotm out of the Startup folder in Finder
# COPIED it (2026-09-14), the original kept loading the engine, and the
# installer test measured the dev rig instead of the installer.
#
# Word must be quit: it holds its templates open and rewrites Normal at quit.
# For the sandbox test: LINGTEX_OFFICE_GC, LINGTEX_PARK_DIR, LINGTEX_AFTER_DIR,
# LINGTEX_IGNORE_WORD=1.

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
gc=${LINGTEX_OFFICE_GC:-"$HOME/Library/Group Containers/UBF8T346G9.Office"}
park=${LINGTEX_PARK_DIR:-"$root/build/word-clean-slate"}
after_base=${LINGTEX_AFTER_DIR:-"$root/build/word-clean-slate-after"}
manifest="$park/MANIFEST.tsv"
tab=$(printf '\t')

die() { echo "word-clean-slate: $1" >&2; exit 1; }

# The folder Word uses: the .localized layout, or an older plain one.
pick() { for d in "$@"; do [ -d "$d" ] && { printf '%s\n' "$d"; return; }; done; printf '%s\n' "$1"; }
startup=$(pick "$gc/User Content.localized/Startup.localized/Word" "$gc/User Content/Startup/Word")
templates=$(pick "$gc/User Content.localized/Templates.localized" "$gc/User Content/Templates")
normal="$templates/Normal.dotm"

word_running() {
    [ -n "$LINGTEX_IGNORE_WORD" ] && return 1
    pgrep -xq "Microsoft Word"
}

# Every LingTeX file Word could see, one path per line.
lingtex_items() {
    for f in "$startup"/LingTeX* "$startup"/'~$'ngTeX* "$templates"/LingTeX* "$templates"/'~$'ngTeX*; do
        [ -e "$f" ] && printf '%s\n' "$f"
    done
}

# The parts of Normal.dotm that mention LingTeX, one per line.
normal_traces() {
    [ -f "$normal" ] || return 0
    for p in $(unzip -Z1 "$normal" 2>/dev/null); do
        unzip -p "$normal" "$p" 2>/dev/null | LC_ALL=C grep -a -i -q lingtex && printf '%s\n' "$p"
    done
}

# Moves each path on stdin into $1, numbered so equal names cannot collide,
# and (when $2 is a file) appends "number-name<TAB>original path" to it.
move_into() {
    dest=$1; record=$2; n=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n=$((n + 1))
        name="$n-$(basename "$f")"
        mv "$f" "$dest/$name" || exit 1
        [ -n "$record" ] && printf '%s\t%s\n' "$name" "$f" >> "$record"
        echo "  moved  $f"
    done
}

status() {
    if word_running; then echo "Word:       running"; else echo "Word:       not running"; fi
    echo "Startup:    $startup"
    items=$(lingtex_items)
    if [ -n "$items" ]; then
        echo "LingTeX files Word can see:"
        printf '%s\n' "$items" | sed 's/^/  /'
    else
        echo "LingTeX files Word can see: none"
    fi
    [ -e "$startup/LingTeX-Dev.dotm" ] && echo "  (the dev rig is active: Word loads the engine from the clone at every start)"
    traces=$(normal_traces)
    if [ -n "$traces" ]; then
        echo "Normal.dotm mentions LingTeX in: $(printf '%s ' $traces)"
    else
        echo "Normal.dotm: no LingTeX traces"
    fi
    if [ -f "$manifest" ]; then
        echo "Parked:     yes, $(grep -vc '^NORMAL' "$manifest") file(s) in $park -- run restore to put them back"
    else
        echo "Parked:     no"
    fi
}

park_all() {
    [ -f "$manifest" ] && die "LingTeX is already parked in $park. Run restore first."
    word_running && die "quit Word first: it holds its templates open and rewrites Normal at quit."
    mkdir -p "$park/files" || die "cannot create $park"
    : > "$manifest"
    if [ -f "$normal" ]; then
        cp -p "$normal" "$park/Normal.dotm" || die "cannot save a copy of Normal.dotm"
        printf 'NORMAL\t%s\n' "$normal" >> "$manifest"
        echo "  saved a copy of Normal.dotm"
        traces=$(normal_traces)
        [ -n "$traces" ] && echo "  NOTE: Normal.dotm already mentions LingTeX ($(printf '%s ' $traces)). A first-run test will not be clean; restore puts this same copy back."
    fi
    lingtex_items | move_into "$park/files" "$manifest" || die "a move failed; what did move is recorded, and restore puts it back"
    left=$(lingtex_items)
    [ -z "$left" ] || die "still there after parking:
$left"
    echo ""
    echo "Word is LingTeX-free. Test the installer now: open the disk image, run"
    echo "Install LingTeX-Word, start Word. Afterwards, with Word quit:"
    echo "  sh $0 restore"
}

restore_all() {
    [ -f "$manifest" ] || die "nothing is parked (no $manifest)."
    word_running && die "quit Word first: it holds its templates open and rewrites Normal at quit."
    after="$after_base/$(date +%Y%m%d-%H%M%S)"

    # 1. What the test left: the installed template and anything else LingTeX.
    items=$(lingtex_items)
    if [ -n "$items" ]; then
        mkdir -p "$after" || die "cannot create $after"
        echo "Set aside what the test left, in $after:"
        printf '%s\n' "$items" | move_into "$after" "" || die "could not set aside what the test left"
    fi

    # 2. Normal.dotm as it was before the test.
    saved=$(grep "^NORMAL$tab" "$manifest" | cut -f2)
    if [ -n "$saved" ] && [ -f "$park/Normal.dotm" ]; then
        if cmp -s "$saved" "$park/Normal.dotm"; then
            echo "Normal.dotm: unchanged by the test"
        else
            mkdir -p "$after" || die "cannot create $after"
            [ -f "$saved" ] && cp -p "$saved" "$after/Normal-after-test.dotm"
            cp -p "$park/Normal.dotm" "$saved" || die "could not put Normal.dotm back; the copy is $park/Normal.dotm"
            echo "Normal.dotm: put back as it was before the test (the test's copy is in $after)"
        fi
    fi

    # 3. The parked files, back where they came from.
    echo "Put back:"
    while IFS="$tab" read -r name orig; do
        [ "$name" = NORMAL ] && continue
        [ -e "$park/files/$name" ] || { echo "  MISSING $park/files/$name (for $orig)"; continue; }
        mkdir -p "$(dirname "$orig")"
        if [ -e "$orig" ]; then
            mkdir -p "$after"; mv "$orig" "$after/in-the-way-$(basename "$orig")"
        fi
        mv "$park/files/$name" "$orig" || die "could not put back $orig; it is still at $park/files/$name"
        echo "  $orig"
    done < "$manifest"

    left=$(ls -A "$park/files" 2>/dev/null)
    [ -z "$left" ] || die "files were left in $park/files: $left"
    rm -f "$manifest" "$park/Normal.dotm"
    rmdir "$park/files" "$park" 2>/dev/null
    echo ""
    echo "LingTeX is back as it was. Start Word; the dev rig loads the engine again."
}

case "$1" in
    status)  status ;;
    park)    park_all ;;
    restore) restore_all ;;
    *) echo "usage: sh $0 status | park | restore" >&2; exit 2 ;;
esac
