#!/bin/sh
# check-ppam.sh  --  LingTeX-PowerPoint
#
# THE DRIFT GUARD for the add-in, the mirror of LingTeX-Word's check-dotm.sh:
# the .ppam is a zip, so this runs anywhere, with no PowerPoint.
#
#   1  the file, the zip, the VBA project part
#   2  the ribbon part is byte-identical to src/customUI14.xml; its icons match
#   3  the package: the relationship to the ribbon, the content types, the
#      main part IS an add-in, no slides (an add-in is code and ribbon only)
#   4  every onAction and getPressed in the ribbon has its Sub in src/
#   5  every compiled module is its source, line for line (check-ppam-sources.py;
#      python3 + olefile, or SKIP unless LINGTEX_REQUIRE_OLEFILE=1)
#
# Usage:  sh LingTeX-PowerPoint/tools/check-ppam.sh [path/to/file.ppam]
# Exit:   0 all checks pass, 1 otherwise.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
ppam="${1:-$root/LingTeX-PowerPoint.ppam}"
ribbon="$root/src/customUI14.xml"
icons="$root/../LingTeX-Word/src/icons"
PART="customUI/customUI14.xml"
CT_PPAM="application/vnd.ms-powerpoint.addin.macroEnabled.main+xml"
fails=0
ok()   { echo "  OK    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

echo "check-ppam: $ppam"
[ -f "$ppam" ] || { fail "the add-in does not exist (run the rig with --macro SaveAsAddInSource, then build-ppam.sh)"; echo "$fails problem(s)"; exit 1; }
unzip -tq "$ppam" >/dev/null 2>&1 || { fail "the add-in is not a readable zip archive"; echo "$fails problem(s)"; exit 1; }
ok "the add-in exists and is a zip archive"
work=$(mktemp -d 2>/dev/null || mktemp -d -t lingtexppamchk)
trap 'rm -rf "$work"' EXIT HUP INT TERM
unzip -q "$ppam" -d "$work"

#-- 1 the VBA project ----------------------------------------------------------
if [ -f "$work/ppt/vbaProject.bin" ]; then
    size=$(wc -c < "$work/ppt/vbaProject.bin" | tr -d ' ')
    if [ "$size" -gt 20000 ]; then ok "ppt/vbaProject.bin is present ($size bytes)"; else fail "ppt/vbaProject.bin is only $size bytes -- too small to hold the modules"; fi
else
    fail "ppt/vbaProject.bin is missing -- saved without the macros?"
fi

#-- 2 the ribbon and icons -------------------------------------------------------
if [ -f "$work/$PART" ]; then
    if cmp -s "$work/$PART" "$ribbon"; then ok "$PART is byte-identical to src/customUI14.xml"; else fail "$PART differs from src/customUI14.xml -- re-run build-ppam.sh"; fi
else
    fail "$PART is missing -- build-ppam.sh was not run"
fi
bad=""
for id in $(sed -n 's/.*[^A-Za-z]image="\([A-Za-z_][A-Za-z0-9_]*\)".*/\1/p' "$ribbon" | sort -u); do
    [ -f "$work/customUI/images/$id.png" ] || bad="$bad $id"
    [ -f "$icons/$id.png" ] || bad="$bad $id(no-source)"
    grep -q "Id=\"$id\"" "$work/customUI/_rels/customUI14.xml.rels" 2>/dev/null || bad="$bad $id(no-rel)"
done
if [ -z "$bad" ]; then ok "every icon the ribbon names is in the package with its relationship"; else fail "icons out of step with the ribbon -- re-run build-ppam.sh:$bad"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$ribbon" 2>/dev/null; then ok "src/customUI14.xml is well-formed XML"; else fail "src/customUI14.xml is not well-formed XML"; fi
fi

#-- 3 the package ----------------------------------------------------------------
rels="$work/_rels/.rels"; ct="$work/[Content_Types].xml"
if [ -f "$rels" ] && grep -q "Target=\"$PART\"" "$rels"; then ok "_rels/.rels points at the ribbon"; else fail "_rels/.rels has no relationship to $PART -- PowerPoint will show no ribbon"; fi
if [ -f "$ct" ]; then
    if grep -q "ContentType=\"$CT_PPAM\"" "$ct"; then ok "the main part is a PowerPoint add-in"; else fail "the main part is not the add-in content type -- re-run build-ppam.sh"; fi
    if grep -q 'Extension="png"' "$ct"; then ok "[Content_Types].xml has a Default for png"; else fail "[Content_Types].xml has no Default for png -- the icons will not load"; fi
    if grep -q 'Extension="xml"' "$ct" || grep -q "PartName=\"/$PART\"" "$ct"; then ok "[Content_Types].xml covers the ribbon part"; else fail "[Content_Types].xml does not cover $PART"; fi
else
    fail "[Content_Types].xml is missing -- the package is invalid"
fi
nslides=$(ls "$work/ppt/slides" 2>/dev/null | grep -c '\.xml$')
if [ "$nslides" = 0 ]; then ok "no slides: the add-in is code and ribbon only"; else fail "the add-in carries $nslides slide(s) -- SaveAsAddInSource must start from an empty presentation"; fi

#-- 4 the handlers -------------------------------------------------------------------
missing=""
for h in $(sed -n 's/.*\(onAction\|getPressed\|onLoad\)="\([A-Za-z_][A-Za-z0-9_]*\)".*/\2/p' "$ribbon" | sort -u); do
    grep -q "^Public Sub $h(" "$root/src/"*.bas || missing="$missing $h"
done
if [ -z "$missing" ]; then ok "every ribbon handler has its Public Sub in src/"; else fail "ribbon handlers with no Sub in src/:$missing"; fi

#-- 5 the modules are their sources ----------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
    if python3 "$here/check-ppam-sources.py" "$ppam"; then :; else fails=$((fails + 1)); fi
else
    if [ "${LINGTEX_REQUIRE_OLEFILE:-0}" = 1 ]; then fail "python3 is missing, and this run requires the module-source check"; else echo "  SKIP  python3 is missing; VBA modules not compared with the sources"; fi
fi

echo ""
if [ "$fails" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "$fails problem(s)"
exit 1
