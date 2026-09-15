#!/bin/sh
# stage-shared.sh  --  LingTeX-PowerPoint
#
# Put the LingTeX-Word modules that LingTeX-PowerPoint shares into
# LingTeX-PowerPoint/build/shared/, taken from one git revision, without
# touching LingTeX-Word/.  run-in-powerpoint.sh then lists them as
# build/shared/<name> in MODULES.
#
#     sh LingTeX-PowerPoint/tools/stage-shared.sh [REV] [OUTDIR]
#
# REV defaults to origin/claude/lingtex-word-crlf (the line-break fix; this
# branch's own LingTeX-Word/src still has the old modFlexParse and
# modIgtModel, which double every CR LF on the Mac).  All five come from the
# SAME revision: the crlf modIgtModel calls NormalizeLineBreaks and LINE_LF,
# which only the crlf modFlexParse defines.
#
# build/ is ignored (LingTeX-PowerPoint/.gitignore), so nothing staged here can
# be committed by accident and drift from LingTeX-Word.  Once the fix is on
# main and main is merged into this branch, MODULES can name
# ../LingTeX-Word/src/<name> directly and this script can go.
#
# Line endings: git stores these files with LF; a checkout gives CRLF
# (.gitattributes *.bas / *.cls eol=crlf), which is what the dev rig has always
# imported.  "git show" gives the stored LF, and "git cat-file --filters" does
# not convert in every setup, so the CRLF is made here, explicitly.

set -e
rev=${1:-origin/claude/lingtex-word-crlf}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
out=${2:-"$root/build/shared"}

git -C "$root" rev-parse --verify --quiet "$rev^{commit}" > /dev/null || {
    echo "stage-shared: no such revision: $rev (git fetch first?)" >&2; exit 2; }
mkdir -p "$out"
for f in modFlexParse.bas modIgtModel.bas clsIgtWarning.cls modLeipzig.bas modWrap.bas; do
    git -C "$root" show "$rev:LingTeX-Word/src/$f" \
        | awk 'BEGIN { ORS = "\r\n" } { sub(/\r$/, ""); print }' > "$out/$f.tmp"
    [ -s "$out/$f.tmp" ] || { echo "stage-shared: $f is empty at $rev" >&2; exit 2; }
    mv "$out/$f.tmp" "$out/$f"
done
git -C "$root" rev-parse --short "$rev" > "$out/REVISION"
echo "== staged the shared modules from $rev ($(cat "$out/REVISION")) into $out"
