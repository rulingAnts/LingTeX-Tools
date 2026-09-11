#!/bin/sh
# build-dotm.sh  --  LingTeX-Word
#
# Injects the ribbon into LingTeX-Word.dotm and writes the source manifest.
#
# WHAT THIS IS FOR
#
# A .dotm is a zip. Word can put the VBA project in it (Save As > Word
# Macro-Enabled Template) but it cannot put a custom ribbon in it -- the ribbon
# lives in a plain-XML part that Word's own interface does not expose. So the build
# is two steps, in this order:
#
#   1. In Word: import the modules, then Save As > Word Macro-Enabled Template to
#      LingTeX-Word/LingTeX-Word.dotm.  (tools/ImportModules.bas does both.)
#   2. Here: sh tools/build-dotm.sh
#
# Save from Word FIRST and inject LAST. Saving again from Word discards the
# injected part, so a re-save means re-running this.
#
# Needs only zip, unzip and a sha256 tool -- no Word, no PowerShell, no Python --
# so it runs on macOS, on Linux, and in CI.
#
# Usage:  sh LingTeX-Word/tools/build-dotm.sh [path/to/file.dotm]

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/src"

dotm=${1:-$root/LingTeX-Word.dotm}
ribbon="$src/customUI14.xml"
manifest="$src/MANIFEST.sha256"

# The relationship type is decided by the ribbon's XML NAMESPACE, not by the file
# name, and getting it wrong means Word loads the template and shows no ribbon with
# no error anywhere:
#
#   xmlns .../2006/customui      -> .../2006/relationships/ui/extensibility
#   xmlns .../2009/07/customui   -> .../2007/relationships/ui/extensibility
#
# src/customUI14.xml uses the 2009/07 namespace, so it needs the 2007 relationship.
# Checked below rather than assumed.
REL_TYPE_2007="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility"
REL_TYPE_2006="http://schemas.microsoft.com/office/2006/relationships/ui/extensibility"
REL_ID="rIdLingTeXCustomUI"
PART="customUI/customUI14.xml"

die() { echo "build-dotm: $1" >&2; exit 1; }

sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "no sha256sum and no shasum; cannot write the manifest"
    fi
}

[ -f "$ribbon" ] || die "missing $ribbon"
[ -f "$dotm" ]   || die "missing $dotm

Save it from Word first:
  File > Save As > Word Macro-Enabled Template (.dotm)
  to  $dotm
or run SaveAsTemplate from tools/ImportModules.bas."

# Pick the relationship type from what the ribbon actually declares.
if grep -q 'xmlns="http://schemas.microsoft.com/office/2009/07/customui"' "$ribbon"; then
    rel_type="$REL_TYPE_2007"
elif grep -q 'xmlns="http://schemas.microsoft.com/office/2006/customui"' "$ribbon"; then
    rel_type="$REL_TYPE_2006"
else
    die "cannot find a customUI namespace in $ribbon"
fi

unzip -tq "$dotm" >/dev/null 2>&1 || die "$dotm is not a readable zip archive"

work=$(mktemp -d 2>/dev/null || mktemp -d -t lingtexdotm)
trap 'rm -rf "$work"' EXIT HUP INT TERM
stage="$work/stage"
mkdir -p "$stage"

unzip -q "$dotm" -d "$stage"

[ -f "$stage/word/vbaProject.bin" ] || die "$dotm has no word/vbaProject.bin

That means it was saved without the macros. In Word, check the modules are present
in the VBA editor and Save As > Word Macro-Enabled Template (not .dotx)."
[ -f "$stage/[Content_Types].xml" ] || die "$dotm has no [Content_Types].xml"
[ -f "$stage/_rels/.rels" ]         || die "$dotm has no _rels/.rels"

#-- 1. the ribbon part, verbatim so check-dotm.sh can compare bytes -----------
mkdir -p "$stage/customUI"
cp "$ribbon" "$stage/$PART"

#-- 2. the root relationship --------------------------------------------------
# Any existing relationship pointing at this part is removed first, so re-running
# replaces rather than duplicates. Relationship elements in .rels are always
# self-closing, which is what makes this safe to do with sed.
rels="$stage/_rels/.rels"
sed -e 's|<Relationship[^>]*Target="customUI/customUI14\.xml"[^>]*/>||g' \
    -e 's|<Relationship[^>]*Target="/customUI/customUI14\.xml"[^>]*/>||g' \
    "$rels" > "$rels.new"
mv "$rels.new" "$rels"

grep -q '</Relationships>' "$rels" || die "_rels/.rels has no </Relationships>"
sed "s|</Relationships>|<Relationship Id=\"$REL_ID\" Type=\"$rel_type\" Target=\"$PART\"/></Relationships>|" \
    "$rels" > "$rels.new"
mv "$rels.new" "$rels"

#-- 3. a content type for the part --------------------------------------------
# Word files already carry <Default Extension="xml" ContentType="application/xml"/>
# which covers customUI14.xml. Added only if it is somehow absent, because without
# it the package is invalid and Word refuses the whole file.
ct="$stage/[Content_Types].xml"
if ! grep -q 'Extension="xml"' "$ct"; then
    sed 's|<Types |<Types |; s|>|>\n<Default Extension="xml" ContentType="application/xml"/>|' \
        "$ct" > "$ct.new"
    # Only the FIRST > (end of the <Types ...> tag) should have been touched.
    head -2 "$ct.new" > /dev/null
    mv "$ct.new" "$ct"
    echo "  added a Default content type for .xml"
fi

#-- 4. repack, [Content_Types].xml first --------------------------------------
# -X drops platform extra fields, so the same inputs give the same bytes.
out="$work/out.dotm"
( cd "$stage" && zip -q -X "$out" "[Content_Types].xml" )
( cd "$stage" && find . -type f ! -name '[Content_Types].xml' -print \
    | sed 's|^\./||' | sort | zip -q -X -@ "$out" )

unzip -tq "$out" >/dev/null 2>&1 || die "the rebuilt archive does not verify"
cp "$out" "$dotm"

#-- 5. the manifest -----------------------------------------------------------
# What source the committed binary was built from. check-dotm.sh compares this to
# the working tree, which is the only way to notice that someone fixed a module in
# the VBA editor and never exported it back out -- the failure mode where src/ and
# the shipped template quietly disagree.
{
    echo "# LingTeX-Word source manifest"
    echo "# SHA-256 of every VBA source and the ribbon, as built into"
    echo "# LingTeX-Word.dotm. Regenerated by tools/build-dotm.sh."
    echo "# Checked by tools/check-dotm.sh, which CI runs."
    for f in $(ls "$src" | sort); do
        case "$f" in
            *.bas|*.cls|customUI14.xml) ;;
            *) continue ;;
        esac
        echo "$(sha_of "$src/$f")  $f"
    done
} > "$manifest"

echo "build-dotm: injected $PART into $(basename "$dotm")"
echo "            relationship $REL_ID -> $rel_type"
echo "            wrote $(basename "$manifest") ($(grep -c '^[0-9a-f]' "$manifest") sources)"
echo ""
echo "Next: sh tools/check-dotm.sh   (the same check CI runs)"
