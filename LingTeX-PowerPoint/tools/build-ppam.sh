#!/bin/sh
# build-ppam.sh  --  LingTeX-PowerPoint
#
# Makes the add-in, LingTeX-PowerPoint/LingTeX-PowerPoint.ppam, from the engine
# presentation the rig saved (build/LingTeX-PowerPoint-engine.pptm, written by
# modPptBuild.SaveAsAddInSource through run-in-powerpoint.sh --macro
# SaveAsAddInSource):
#
#   1. the main part's content type becomes the add-in's -- VBA on the Mac
#      has no save format for an add-in (PLAN.md, probe round 6), and a .ppam
#      is a .pptm with this one string changed (the Startup-folder probe
#      loaded and ran one made this way);
#   2. the ribbon (src/customUI14.xml) and its icons (LingTeX-Word's,
#      ../LingTeX-Word/src/icons) are injected, as build-dotm.sh does for the
#      Word template, and a button whose icon is missing fails the build.
#
# Needs only zip and unzip.  No PowerPoint, no Windows.
#
# Usage:  sh LingTeX-PowerPoint/tools/build-ppam.sh [engine.pptm] [out.ppam]
#         sh LingTeX-PowerPoint/tools/build-ppam.sh --ribbon-into file.pptm
#            (a copy of that presentation with the ribbon injected, beside it as
#            file.ribbon.pptm, to look at the tab in PowerPoint without an add-in)
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
ribbon="$root/src/customUI14.xml"
icons="$root/../LingTeX-Word/src/icons"
REL_TYPE="http://schemas.microsoft.com/office/2007/relationships/ui/extensibility"
REL_ID="rIdLingTeXCustomUI"
PART="customUI/customUI14.xml"
IMG_REL_TYPE="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
IMG_RELS="customUI/_rels/customUI14.xml.rels"
CT_PPTM="application/vnd.ms-powerpoint.presentation.macroEnabled.main+xml"
CT_PPAM="application/vnd.ms-powerpoint.addin.macroEnabled.main+xml"

die() { echo "build-ppam: $1" >&2; exit 1; }

mode=addin
if [ "$1" = "--ribbon-into" ]; then
    mode=ribbon; in="$2"; [ -n "$in" ] || die "--ribbon-into needs a .pptm"
    out="${in%.pptm}.ribbon.pptm"
else
    in="${1:-$root/build/LingTeX-PowerPoint-engine.pptm}"
    out="${2:-$root/LingTeX-PowerPoint.ppam}"
fi
[ -f "$ribbon" ] || die "missing $ribbon"
[ -f "$in" ] || die "missing $in
Save it from PowerPoint first:  sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh --macro SaveAsAddInSource"
grep -q 'xmlns="http://schemas.microsoft.com/office/2009/07/customui"' "$ribbon" || die "the ribbon is not a 2009/07 customUI part"
unzip -tq "$in" >/dev/null 2>&1 || die "$in is not a readable zip archive"

work=$(mktemp -d 2>/dev/null || mktemp -d -t lingtexppam)
trap 'rm -rf "$work"' EXIT HUP INT TERM
stage="$work/stage"
mkdir -p "$stage"
unzip -q "$in" -d "$stage"
[ -f "$stage/ppt/vbaProject.bin" ] || die "$in has no ppt/vbaProject.bin: it was saved without the macros"
[ -f "$stage/[Content_Types].xml" ] || die "$in has no [Content_Types].xml"
[ -f "$stage/_rels/.rels" ] || die "$in has no _rels/.rels"
ct="$stage/[Content_Types].xml"

#-- 1. the add-in content type ------------------------------------------------
if [ "$mode" = addin ]; then
    if grep -q "ContentType=\"$CT_PPTM\"" "$ct"; then
        sed "s|ContentType=\"$CT_PPTM\"|ContentType=\"$CT_PPAM\"|" "$ct" > "$ct.new" && mv "$ct.new" "$ct"
        echo "  main part: macro-enabled presentation -> add-in"
    fi
    grep -q "ContentType=\"$CT_PPAM\"" "$ct" || die "the main part of $in is neither a macro-enabled presentation nor an add-in"
fi

#-- 2. the ribbon and its icons -----------------------------------------------
mkdir -p "$stage/customUI/images" "$stage/customUI/_rels"
cp "$ribbon" "$stage/$PART"
nicons=0
{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    printf '%s' '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    for id in $(sed -n 's/.*[^A-Za-z]image="\([A-Za-z_][A-Za-z0-9_]*\)".*/\1/p' "$ribbon" | sort -u); do
        [ -f "$icons/$id.png" ] || die "the ribbon names image=\"$id\" but $icons/$id.png does not exist"
        cp "$icons/$id.png" "$stage/customUI/images/$id.png"
        printf '%s' "<Relationship Id=\"$id\" Type=\"$IMG_REL_TYPE\" Target=\"images/$id.png\"/>"
        nicons=$((nicons + 1))
    done
    printf '%s\n' '</Relationships>'
} > "$stage/$IMG_RELS"
nicons=$(ls "$stage/customUI/images" | wc -l | tr -d ' ')

rels="$stage/_rels/.rels"
sed -e 's|<Relationship[^>]*Target="customUI/customUI14\.xml"[^>]*/>||g' \
    -e 's|<Relationship[^>]*Target="/customUI/customUI14\.xml"[^>]*/>||g' "$rels" > "$rels.new" && mv "$rels.new" "$rels"
grep -q '</Relationships>' "$rels" || die "_rels/.rels has no </Relationships>"
sed "s|</Relationships>|<Relationship Id=\"$REL_ID\" Type=\"$REL_TYPE\" Target=\"$PART\"/></Relationships>|" "$rels" > "$rels.new" && mv "$rels.new" "$rels"
if ! grep -q 'Extension="xml"' "$ct"; then
    sed 's|<Types \([^>]*\)>|<Types \1><Default Extension="xml" ContentType="application/xml"/>|' "$ct" > "$ct.new" && mv "$ct.new" "$ct"
fi
if ! grep -q 'Extension="png"' "$ct"; then
    sed 's|<Types \([^>]*\)>|<Types \1><Default Extension="png" ContentType="image/png"/>|' "$ct" > "$ct.new" && mv "$ct.new" "$ct"
fi

#-- 3. pack, [Content_Types].xml first ----------------------------------------
tmp="$work/out.zip"
( cd "$stage" && zip -q -X "$tmp" "[Content_Types].xml" )
( cd "$stage" && find . -type f ! -name '[Content_Types].xml' -print | sed 's|^\./||' | sort | zip -q -X -@ "$tmp" )
unzip -tq "$tmp" >/dev/null 2>&1 || die "the rebuilt archive does not verify"
mkdir -p "$(dirname "$out")"
cp "$tmp" "$out"
echo "build-ppam: wrote $out (ribbon and $nicons icons injected)"
[ "$mode" = addin ] && echo "  install: copy it into PowerPoint's Startup folder (modLingTeXDev.StartupFolder), quit and start PowerPoint"
exit 0
