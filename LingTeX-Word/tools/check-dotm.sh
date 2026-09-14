#!/bin/sh
# check-dotm.sh  --  LingTeX-Word
#
# THE DRIFT GUARD. Runs in CI, with no Word anywhere, because a .dotm is a zip.
#
# The template is a committed binary built by hand in Word, which means the usual
# guarantee -- that what ships is what is in the repository -- does not hold for
# free. There are two ways it can quietly stop holding:
#
#   * someone fixes a module in the VBA editor and never exports it back to src/,
#     so the shipped template contains code that is nowhere in the repository;
#   * someone edits src/customUI14.xml, or redraws an icon in src/icons/, and
#     does not re-run build-dotm.sh, so the reviewable ribbon is not the ribbon
#     that ships.
#
# Neither shows up in a diff. Both show up here.
#
# Usage:  sh LingTeX-Word/tools/check-dotm.sh [path/to/file.dotm]
# Exit:   0 all checks pass, 1 otherwise.

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/src"

dotm=${1:-$root/LingTeX-Word.dotm}
ribbon="$src/customUI14.xml"
manifest="$src/MANIFEST.sha256"
PART="customUI/customUI14.xml"
IMG_RELS="customUI/_rels/customUI14.xml.rels"
icons="$src/icons"

fails=0

pass() { echo "  OK    $1"; }
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

echo "check-dotm: $dotm"

#-- 0. it exists and is a zip -------------------------------------------------
if [ ! -f "$dotm" ]; then
    fail "the template does not exist (build it in Word, then run build-dotm.sh)"
    echo ""
    echo "1 problem(s)"
    exit 1
fi
if unzip -tq "$dotm" >/dev/null 2>&1; then
    pass "the template is a readable zip archive"
else
    fail "the template is not a readable zip archive"
    echo ""
    echo "$fails problem(s)"
    exit 1
fi

work=$(mktemp -d 2>/dev/null || mktemp -d -t lingtexcheck)
trap 'rm -rf "$work"' EXIT HUP INT TERM
unzip -q "$dotm" -d "$work"

#-- 1. the VBA project is in there, and is not a stub -------------------------
# A .dotx saved by accident, or a template saved before the modules were imported,
# both produce a file that looks fine and does nothing.
if [ -f "$work/word/vbaProject.bin" ]; then
    size=$(wc -c < "$work/word/vbaProject.bin" | tr -d ' ')
    if [ "$size" -gt 8192 ]; then
        pass "word/vbaProject.bin is present ($size bytes)"
    else
        fail "word/vbaProject.bin is only $size bytes -- too small to hold the modules"
    fi
else
    fail "word/vbaProject.bin is missing -- saved as .dotx, or before importing?"
fi

#-- 2. the ribbon part matches src/ BYTE FOR BYTE ----------------------------
if [ ! -f "$work/$PART" ]; then
    fail "$PART is missing -- build-dotm.sh was not run after the last save"
elif cmp -s "$work/$PART" "$ribbon"; then
    pass "$PART is byte-identical to src/customUI14.xml"
else
    fail "$PART differs from src/customUI14.xml -- re-run build-dotm.sh"
    echo "        embedded: $(sha_of "$work/$PART")"
    echo "        src/:     $(sha_of "$ribbon")"
fi

#-- 2b. every icon the ribbon names is in there, byte for byte, and related --
# image="X" is the Id of an image relationship of the ribbon PART, so three
# things must agree: src/icons/X.png, customUI/images/X.png, and an Id="X" in
# customUI/_rels/customUI14.xml.rels. A miss anywhere is a blank button.
named=$(sed -n 's/.*[^A-Za-z]image="\([A-Za-z_][A-Za-z0-9_]*\)".*/\1/p' "$ribbon" | sort -u)
if [ -n "$named" ]; then
    bad=""
    n=0
    for id in $named; do
        n=$((n + 1))
        if [ ! -f "$icons/$id.png" ]; then
            bad="$bad
        $id: no src/icons/$id.png"
        elif [ ! -f "$work/customUI/images/$id.png" ]; then
            bad="$bad
        $id: not embedded"
        elif ! cmp -s "$work/customUI/images/$id.png" "$icons/$id.png"; then
            bad="$bad
        $id: the embedded icon differs from src/icons/$id.png"
        fi
        if ! grep -q "Id=\"$id\"" "$work/$IMG_RELS" 2>/dev/null; then
            bad="$bad
        $id: no relationship in $IMG_RELS"
        fi
    done
    if [ -z "$bad" ]; then
        pass "all $n icons the ribbon names are embedded, related and identical to src/icons/"
    else
        fail "icons out of step with the ribbon -- re-run build-dotm.sh:$bad"
    fi
    if grep -q 'Extension="png"' "$work/[Content_Types].xml" 2>/dev/null; then
        pass "[Content_Types].xml covers the icons"
    else
        fail "[Content_Types].xml has no Default for png -- the icons will not load"
    fi
fi

#-- 2c. no keyboard customizations ship ----------------------------------------
# A key map in the template is the developer's shortcuts, and Mac key codes
# would land on random keys in every user's Word. build-dotm.sh strips it.
if [ -f "$work/word/customizations.xml" ]; then
    fail "word/customizations.xml is in the template: keyboard customizations would ship -- re-run build-dotm.sh"
else
    pass "no keyboard customizations in the template"
fi

#-- 3. the root relationship points at it, with the type the namespace needs --
rels="$work/_rels/.rels"
if [ ! -f "$rels" ]; then
    fail "_rels/.rels is missing"
else
    if grep -q 'Target="customUI/customUI14.xml"' "$rels"; then
        pass "_rels/.rels points at the ribbon part"
    else
        fail "_rels/.rels has no relationship to $PART -- Word will show no ribbon"
    fi
    # The namespace decides the type. A mismatch loads silently with no ribbon,
    # which is the single most confusing way for this to be wrong.
    if grep -q 'xmlns="http://schemas.microsoft.com/office/2009/07/customui"' "$ribbon"; then
        want="2007/relationships/ui/extensibility"
    else
        want="2006/relationships/ui/extensibility"
    fi
    if grep -q "$want" "$rels"; then
        pass "the relationship type matches the ribbon's namespace ($want)"
    else
        fail "the relationship type does not match the ribbon's namespace"
        echo "        the ribbon needs: $want"
    fi
fi

#-- 4. a content type covers the part ----------------------------------------
ct="$work/[Content_Types].xml"
if [ ! -f "$ct" ]; then
    fail "[Content_Types].xml is missing -- the package is invalid"
elif grep -q 'Extension="xml"' "$ct" || grep -q 'PartName="/customUI/customUI14.xml"' "$ct"; then
    pass "[Content_Types].xml covers the ribbon part"
else
    fail "[Content_Types].xml does not cover $PART -- Word will reject the file"
fi

#-- 4b. the package is a TEMPLATE, not a document named .dotm ----------------
# SaveAsTemplate saved with FileFormat 13 until 2026-09-14, which is
# wdFormatXMLDocumentMacroEnabled: a .docm under a .dotm name. Windows Word
# loaded it from STARTUP anyway; Word for Mac said "Word cannot open this
# document template", so the Mac install never worked. The type lives in one
# Override in [Content_Types].xml.
if [ -f "$ct" ]; then
    main=$(tr -d '\r\n' < "$ct" | grep -o '<Override PartName="/word/document.xml" ContentType="[^"]*"' | sed 's/.*ContentType="//; s/"$//')
    case "$main" in
        application/vnd.ms-word.template.macroEnabledTemplate.main+xml)
            pass "the package is a macro-enabled template, not a document" ;;
        *)
            fail "the main part is \"$main\", not a macro-enabled template -- Word for Mac will not open it from Startup; re-run build-dotm.sh" ;;
    esac
fi

#-- 5. the ribbon is well-formed, and every onAction resolves ----------------
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$ribbon" 2>/dev/null; then
        pass "src/customUI14.xml is well-formed XML"
    else
        fail "src/customUI14.xml is not well-formed XML"
    fi
else
    echo "  SKIP  xmllint not available; cannot check the ribbon is well-formed"
fi

missing=""
for h in $(sed -n 's/.*onAction="\([A-Za-z_][A-Za-z0-9_]*\)".*/\1/p' "$ribbon" | sort -u); do
    if ! grep -q "^\(Public \|Private \)\?Sub $h\b" "$src"/*.bas 2>/dev/null; then
        missing="$missing $h"
    fi
done
if [ -z "$missing" ]; then
    pass "every ribbon onAction resolves to a Sub in src/"
else
    fail "ribbon onAction handlers with no Sub in src/:$missing"
fi

#-- 6. src/ matches what the template was built from -------------------------
# The check that catches a fix made in the VBA editor and never exported.
if [ ! -f "$manifest" ]; then
    fail "src/MANIFEST.sha256 is missing -- run build-dotm.sh"
else
    drift=""
    listed=0
    while read -r want name; do
        case "$want" in '#'*|'') continue ;; esac
        listed=$((listed + 1))
        if [ ! -f "$src/$name" ]; then
            drift="$drift
        $name is in the manifest but not in src/"
            continue
        fi
        got=$(sha_of "$src/$name")
        if [ "$got" != "$want" ]; then
            drift="$drift
        $name has changed since the template was built"
        fi
    done < "$manifest"

    # And the other direction: a source added to src/ and never built in.
    for f in $(ls "$src" | sort) $(ls "$icons" 2>/dev/null | sed 's|^|icons/|' | sort); do
        case "$f" in *.bas|*.cls|*.frm|customUI14.xml|icons/*.png) ;; *) continue ;; esac
        if ! grep -q "  $f\$" "$manifest"; then
            drift="$drift
        $f is in src/ but not in the manifest"
        fi
    done

    if [ -z "$drift" ]; then
        pass "all $listed sources match the manifest"
    else
        fail "src/ has drifted from the built template:$drift"
        echo "        Export the modules out of Word (File > Export File) and"
        echo "        re-run build-dotm.sh, so src/ and the template agree again."
    fi
fi

#-- 7. an upgrade gets its shortcuts back -------------------------------------
# The first run saves the shortcuts it installs into the installed template
# itself, and records in Normal that it ran. An upgrade replaces that template,
# so the shortcuts go, and the first run puts them back only when SETUP_VERSION
# differs from the one recorded. So every release must move it (RELEASING.md);
# beta.3 did not, and upgraders from beta.2 would have lost their shortcuts.
# Compared with the newest word-v* tag behind this commit; skipped outside a
# git clone, or in one with no such tag (CI fetches the history for this).
setup_of() { tr -d '\r' | sed -n 's/.*SETUP_VERSION As String = "\([^"]*\)".*/\1/p' | head -1; }
cur=$(setup_of < "$src/modLingTeX.bas")
prev=""
if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    prev=$(git -C "$root" tag --list 'word-v*' --merged HEAD --no-contains HEAD --sort=-creatordate 2>/dev/null | head -1)
fi
if [ -z "$cur" ]; then
    fail "no SETUP_VERSION found in src/modLingTeX.bas"
elif [ -z "$prev" ]; then
    echo "  SKIP  no earlier word-v* tag in this clone, so SETUP_VERSION ($cur) is not compared"
else
    was=$(git -C "$root" show "$prev:./src/modLingTeX.bas" 2>/dev/null | setup_of)
    # The release being checked: the tag CI runs for, or a tag already on HEAD.
    this=${GITHUB_REF_NAME:-$(git -C "$root" tag --points-at HEAD --list 'word-v*' 2>/dev/null | head -1)}
    if [ "$cur" != "$was" ]; then
        pass "SETUP_VERSION moved since $prev ($was to $cur), so upgraders get their shortcuts back"
    elif [ "$this" = "word-v0.1.0-beta.5" ]; then
        # The one exemption (Seth, 2026-09-14). beta.5 ships the beta.4 template
        # with only its package type corrected -- the file that worked on the
        # Mac -- rather than a rebuild in Word. Windows users upgrading from
        # beta.4 click Install Shortcuts once; the release notes and the guide
        # say so. The release after beta.5 must move SETUP_VERSION again.
        pass "SETUP_VERSION is still $cur, as in $prev: allowed for $this only (the template was not rebuilt)"
    else
        fail "SETUP_VERSION is still $cur, as in $prev: an upgrade would lose the shortcuts"
        echo "        Bump SETUP_VERSION in src/modLingTeX.bas, then rebuild the template"
        echo "        (RELEASING.md): it is compiled into the template, so this needs Word."
    fi
fi

echo ""
if [ "$fails" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
fi
echo "$fails problem(s)"
exit 1
