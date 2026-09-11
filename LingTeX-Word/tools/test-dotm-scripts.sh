#!/bin/sh
# test-dotm-scripts.sh  --  LingTeX-Word
#
# Tests build-dotm.sh and check-dotm.sh WITHOUT Word, by building a synthetic
# .dotm -- which is possible because a .dotm is just a zip with an OPC package in
# it. Word is needed to put a real VBA project in one; it is not needed to test
# whether the ribbon injection and the drift guard work.
#
# The point of the negative cases: a drift guard that cannot fail is not a guard.
# Each one breaks the package in a specific way and asserts that check-dotm.sh
# says so.
#
# Usage:  sh LingTeX-Word/tools/test-dotm-scripts.sh

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

fails=0
pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

work=$(mktemp -d 2>/dev/null || mktemp -d -t lingtextest)

# Two of the negative cases deliberately mutate the repository -- a stale manifest
# and a source that is not in it -- so cleanup has to undo those too, or an
# interrupted run leaves a file behind that makes every later check-dotm fail.
cleanup() {
    rm -f "$root/src/zzTestOnly.bas"
    if [ -f "$work/manifest.bak" ]; then
        cp "$work/manifest.bak" "$root/src/MANIFEST.sha256"
    elif [ -f "$work/no-manifest-before" ]; then
        # There was none before this run, so build-dotm.sh created it against a
        # SYNTHETIC template. Leaving it would be a record of a template that does
        # not exist, and check-dotm.sh would then be comparing src/ to nothing.
        rm -f "$root/src/MANIFEST.sha256"
    fi
    rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

# A minimal but valid Word package, with a stand-in vbaProject.bin big enough to
# pass the "not a stub" check.
make_dotm() {
    out=$1
    d="$work/pkg"
    rm -rf "$d"
    mkdir -p "$d/_rels" "$d/word/_rels"

    cat > "$d/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="bin" ContentType="application/vnd.ms-office.vbaProject"/><Override PartName="/word/document.xml" ContentType="application/vnd.ms-word.template.macroEnabledTemplate.main+xml"/></Types>
XML

    cat > "$d/_rels/.rels" <<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
XML

    cat > "$d/word/document.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/></w:body></w:document>
XML

    cat > "$d/word/_rels/document.xml.rels" <<'XML'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/></Relationships>
XML

    # ~16KB of bytes standing in for a compiled VBA project.
    i=0
    : > "$d/word/vbaProject.bin"
    while [ $i -lt 256 ]; do
        printf 'vbaProjectStandInBytesForTestingOnlyNotARealCompiledProject----\n' \
            >> "$d/word/vbaProject.bin"
        i=$((i + 1))
    done

    rm -f "$out"
    ( cd "$d" && zip -q -X "$out" "[Content_Types].xml" )
    ( cd "$d" && find . -type f ! -name '[Content_Types].xml' -print \
        | sed 's|^\./||' | sort | zip -q -X -@ "$out" )
}

dotm="$work/Test.dotm"

# Taken up front so the trap can always restore it.
if [ -f "$root/src/MANIFEST.sha256" ]; then
    cp "$root/src/MANIFEST.sha256" "$work/manifest.bak"
else
    : > "$work/no-manifest-before"
fi

echo "test-dotm-scripts: building a synthetic package"
make_dotm "$dotm"
if unzip -tq "$dotm" >/dev/null 2>&1; then
    pass "the synthetic .dotm is a valid zip"
else
    fail "could not build a synthetic .dotm"
    echo ""; echo "$fails problem(s)"; exit 1
fi

#-- the guard must FAIL on a package with no ribbon yet ------------------------
if sh "$here/check-dotm.sh" "$dotm" >"$work/out0" 2>&1; then
    fail "check-dotm passed a package with no ribbon injected"
    sed 's/^/        /' "$work/out0"
else
    pass "check-dotm fails before the ribbon is injected"
fi

#-- build ---------------------------------------------------------------------
if sh "$here/build-dotm.sh" "$dotm" >"$work/out1" 2>&1; then
    pass "build-dotm ran"
else
    fail "build-dotm failed"
    sed 's/^/        /' "$work/out1"
fi

if unzip -l "$dotm" 2>/dev/null | grep -q 'customUI/customUI14.xml'; then
    pass "the ribbon part is in the archive"
else
    fail "the ribbon part is not in the archive"
fi

# [Content_Types].xml must still be the first entry, as OPC expects.
first=$(unzip -l "$dotm" | awk 'NR>3 && NF>=4 {print $4; exit}')
if [ "$first" = "[Content_Types].xml" ]; then
    pass "[Content_Types].xml is the first entry"
else
    fail "the first entry is $first, not [Content_Types].xml"
fi

if unzip -p "$dotm" '_rels/.rels' | grep -q '2007/relationships/ui/extensibility'; then
    pass "the 2007 relationship type was used for the 2009/07 namespace"
else
    fail "wrong or missing relationship type"
    unzip -p "$dotm" '_rels/.rels' | sed 's/^/        /'
fi

if [ -f "$root/src/MANIFEST.sha256" ]; then
    pass "the manifest was written"
else
    fail "no manifest was written"
fi

#-- and now the guard must PASS ------------------------------------------------
if sh "$here/check-dotm.sh" "$dotm" >"$work/out2" 2>&1; then
    pass "check-dotm passes the built package"
else
    fail "check-dotm rejected the package it was just built from"
    sed 's/^/        /' "$work/out2"
fi

#-- idempotence: building twice must not duplicate the relationship ------------
sh "$here/build-dotm.sh" "$dotm" >/dev/null 2>&1
n=$(unzip -p "$dotm" '_rels/.rels' | grep -o 'customUI/customUI14.xml' | wc -l | tr -d ' ')
if [ "$n" = "1" ]; then
    pass "building twice leaves exactly one ribbon relationship"
else
    fail "building twice left $n ribbon relationships"
fi
if sh "$here/check-dotm.sh" "$dotm" >/dev/null 2>&1; then
    pass "check-dotm still passes after a second build"
else
    fail "a second build broke the package"
fi

#=============================================================================
# NEGATIVE CASES -- each breaks one thing and asserts the guard notices
#=============================================================================

expect_fail() {
    what=$1
    if sh "$here/check-dotm.sh" "$dotm" >"$work/neg" 2>&1; then
        fail "check-dotm PASSED with $what"
    else
        if grep -q "$2" "$work/neg"; then
            pass "check-dotm catches $what"
        else
            fail "check-dotm failed with $what, but not for the right reason"
            sed 's/^/        /' "$work/neg"
        fi
    fi
}

#-- a ribbon inside the package that no longer matches src/ -------------------
cp "$dotm" "$work/keep.dotm"
mkdir -p "$work/mut"
rm -rf "$work/mut"; mkdir -p "$work/mut"
unzip -q "$dotm" -d "$work/mut"
printf '\n<!-- drifted -->\n' >> "$work/mut/customUI/customUI14.xml"
rm -f "$dotm"
( cd "$work/mut" && zip -q -X "$dotm" "[Content_Types].xml" )
( cd "$work/mut" && find . -type f ! -name '[Content_Types].xml' -print \
    | sed 's|^\./||' | sort | zip -q -X -@ "$dotm" )
expect_fail "a ribbon that drifted from src/" "differs from src/customUI14.xml"
cp "$work/keep.dotm" "$dotm"

#-- a missing relationship ----------------------------------------------------
rm -rf "$work/mut"; mkdir -p "$work/mut"
unzip -q "$dotm" -d "$work/mut"
sed 's|<Relationship Id="rIdLingTeXCustomUI"[^>]*/>||' "$work/mut/_rels/.rels" > "$work/mut/_rels/.rels.new"
mv "$work/mut/_rels/.rels.new" "$work/mut/_rels/.rels"
rm -f "$dotm"
( cd "$work/mut" && zip -q -X "$dotm" "[Content_Types].xml" )
( cd "$work/mut" && find . -type f ! -name '[Content_Types].xml' -print \
    | sed 's|^\./||' | sort | zip -q -X -@ "$dotm" )
expect_fail "a missing ribbon relationship" "no relationship to"
cp "$work/keep.dotm" "$dotm"

#-- a vbaProject.bin too small to hold the modules ---------------------------
rm -rf "$work/mut"; mkdir -p "$work/mut"
unzip -q "$dotm" -d "$work/mut"
printf 'stub' > "$work/mut/word/vbaProject.bin"
rm -f "$dotm"
( cd "$work/mut" && zip -q -X "$dotm" "[Content_Types].xml" )
( cd "$work/mut" && find . -type f ! -name '[Content_Types].xml' -print \
    | sed 's|^\./||' | sort | zip -q -X -@ "$dotm" )
expect_fail "a stub vbaProject.bin" "too small to hold the modules"
cp "$work/keep.dotm" "$dotm"

#-- a stale manifest, i.e. a module fixed in Word and never exported ---------
cp "$root/src/MANIFEST.sha256" "$work/manifest.cur"
sed 's/^[0-9a-f]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' \
    "$work/manifest.cur" > "$root/src/MANIFEST.sha256"
expect_fail "a stale manifest" "drifted from the built template"
cp "$work/manifest.cur" "$root/src/MANIFEST.sha256"

#-- a source in src/ that was never built in ---------------------------------
cp "$root/src/modWrap.bas" "$root/src/zzTestOnly.bas"
expect_fail "a source missing from the manifest" "not in the manifest"
rm -f "$root/src/zzTestOnly.bas"

#-- and clean again -----------------------------------------------------------
if sh "$here/check-dotm.sh" "$dotm" >/dev/null 2>&1; then
    pass "check-dotm passes again once everything is restored"
else
    fail "the package did not come back clean"
    sh "$here/check-dotm.sh" "$dotm" 2>&1 | sed 's/^/        /'
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
fi
echo "$fails problem(s)"
exit 1
