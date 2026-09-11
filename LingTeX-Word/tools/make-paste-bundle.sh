#!/bin/sh
# make-paste-bundle.sh  --  LingTeX-Word
#
# Generates paste-ready copies of the VBA modules in build/paste/, as .txt files
# you open, select all, and paste into the VBA editor.
#
# Why this exists: pasting an exported .bas or .cls straight into the VBA editor
# does NOT work, and the reasons are not obvious.
#
#   * "Attribute VB_Name = ..." is read by the importer. Typed into the editor it
#     is a compile error.
#   * A .cls file carries a VERSION / BEGIN / MultiUse / END preamble and
#     VB_Creatable / VB_Exposed / VB_PredeclaredId attributes, none of which are
#     valid source.
#   * clsAppEvents has "Attribute mApp.VB_VarHelpID = -1" buried in the middle of
#     the file, which is easy to miss and also invalid when typed.
#
# This strips all of that and prepends a header saying the exact module name to
# set, whether to insert a standard module or a Class Module, and for a class, its
# Instancing setting.
#
# THE CLASS MODULES ARE THE RELIABLE USE FOR THIS SCRIPT. Importing a .cls is
# fragile -- the editor decides what kind of component to create by parsing the
# file header, and gets it wrong often enough that pasting into a hand-created
# Class Module is the path that always works. The eleven .bas files import
# cleanly; prefer File > Import File... for those.
#
# Output is CRLF, so the .txt files open correctly in any editor on either
# platform. Input may be either -- CR is stripped before processing, which the
# first version of this script did not do, and the leaked BEGIN/END lines looked
# exactly like a bug in the module.
#
# POSIX sh, and no sed -i, so it behaves identically on macOS and Linux.
#
# Usage:  sh LingTeX-Word/tools/make-paste-bundle.sh

set -e

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
src="$root/src"
probe="$root/tools/probe"
out="$root/build/paste"

# Stage 1 first: these six reference nothing defined in the other seven, so they
# compile and run RunAllTests on their own, with the Word object model entirely
# uninvolved. See QUICKSTART.md.
STAGE1="modFlexParse modIgtModel modLeipzig modWrap clsIgtWarning modTests"
STAGE2="modStyles modSettings modMeasure modRender modReadBack modLingTeX clsAppEvents"

rm -rf "$out"
mkdir -p "$out"

# Resolve a module name to its source file, whichever extension it uses.
find_source() {
    if [ -f "$src/$1.bas" ]; then
        echo "$src/$1.bas"
    elif [ -f "$src/$1.cls" ]; then
        echo "$src/$1.cls"
    elif [ -f "$probe/$1.bas" ]; then
        echo "$probe/$1.bas"
    else
        echo ""
    fi
}

is_class() {
    case "$1" in
        *.cls) return 0 ;;
        *)     return 1 ;;
    esac
}

# Read the Instancing setting back out of the .cls attributes rather than
# asserting it, so this can never drift from the file it describes.
#
#   VB_Exposed=False, VB_Creatable=False            -> 1 - Private
#   VB_Exposed=True,  VB_Creatable=False            -> 2 - PublicNotCreatable
#   VB_Exposed=True,  VB_Creatable=True             -> 5 - MultiUse
instancing_of() {
    exposed=$(tr -d '\r' < "$1" | awk '/^Attribute VB_Exposed/   { print $NF }')
    creatable=$(tr -d '\r' < "$1" | awk '/^Attribute VB_Creatable/ { print $NF }')
    if [ "$exposed" = "False" ]; then
        echo "1 - Private"
    elif [ "$creatable" = "True" ]; then
        echo "5 - MultiUse"
    else
        echo "2 - PublicNotCreatable"
    fi
}

# Strip everything that is metadata rather than source, and any leading blanks,
# so the output begins at Option Explicit.
#
# CR is removed FIRST. The .cls preamble lines are matched with end-of-line
# anchors, and a trailing CR defeats them -- which is how BEGIN / MultiUse / END
# ended up pasted in as code.
strip_metadata() {
    tr -d '\r' < "$1" | awk '
        /^VERSION [0-9]/           { next }
        /^BEGIN[ \t]*$/            { inpre = 1; next }
        /^END[ \t]*$/              { if (inpre) { inpre = 0; next } }
        inpre                      { next }
        /^Attribute[ \t]/          { next }
        !started && /^[ \t]*$/     { next }
        { started = 1; print }
    '
}

emit() {
    name="$1"
    num="$2"
    stage="$3"
    file=$(find_source "$name")
    if [ -z "$file" ]; then
        echo "  MISSING: $name" >&2
        return 1
    fi
    target="$out/$num-$name.txt"

    {
        echo "'============================================================="
        if is_class "$file"; then
            echo "' THIS IS A CLASS MODULE. IT WILL NOT WORK AS A STANDARD MODULE."
            echo "'"
            echo "'   1. Insert > Class Module"
            echo "'   2. Paste this whole file into it"
            echo "'   3. Properties pane, (Name) row:   $name"
            echo "'   4. Properties pane, Instancing row:   $(instancing_of "$file")"
            echo "'      (that is the default for a new class module, so there is"
            echo "'       normally nothing to change -- check it, do not set it)"
            echo "'"
            echo "' On Mac: View > Properties Window if the pane is not showing."
        else
            echo "' PASTE THIS INTO:  Insert > Module"
            echo "'"
            echo "'   1. Insert > Module"
            echo "'   2. Paste this whole file into it"
            echo "'   3. Properties pane, (Name) row:   $name"
            echo "'"
            echo "' On Mac: View > Properties Window if the pane is not showing."
        fi
        echo "'"
        echo "' $stage"
        echo "'"
        echo "' Generated by tools/make-paste-bundle.sh from"
        echo "'   $(basename "$file")"
        echo "' Do not edit this file -- edit the original in src/ and re-run."
        echo "'============================================================="
        echo ""
        strip_metadata "$file"
    } | sed 's/$/\r/' > "$target"

    if is_class "$file"; then
        echo "  $num-$name.txt   (CLASS MODULE -- $(instancing_of "$file"))"
    else
        echo "  $num-$name.txt   (Module)"
    fi
}

echo "Generating paste bundle in $out"
echo ""

emit modProbe 00 "Standalone probe. Run ProbeWord first, before anything else."

n=1
for m in $STAGE1; do
    num=$(printf "%02d" "$n")
    emit "$m" "$num" "STAGE 1 of 2 -- these six run RunAllTests on their own."
    n=$((n + 1))
done
for m in $STAGE2; do
    num=$(printf "%02d" "$n")
    emit "$m" "$num" "STAGE 2 of 2 -- adds the document work."
    n=$((n + 1))
done

cat > "$out/00-README.txt" <<'TXT'
LingTeX-Word -- paste bundle
============================

These are the VBA modules with their metadata stripped so they can be pasted
directly into the VBA editor. For each file:

  1. Insert > Module   (or Insert > Class Module for the cls* files)
  2. Paste the whole file
  3. Set the module's name in the Properties pane to the name the header gives

The header of every file says which kind of module to insert, what to name it,
and for the two class modules, what Instancing should read.

WHICH PATH TO USE
-----------------

  The eleven .bas modules   File > Import File... on the files in src/ is
                            easier and sets the names for you.

  The two .cls modules      USE THESE PASTE FILES. Importing a .cls is
                            unreliable: the editor decides what kind of
                            component to create by parsing the file header, and
                            when it guesses wrong it creates a STANDARD module
                            with the preamble sitting in the code as syntax
                            errors. Insert > Class Module yourself and paste, and
                            that cannot happen.

A class pasted into a standard module does not compile at all: clsAppEvents
declares "Private WithEvents mApp As Word.Application", which is only legal in a
class module. If you see "Invalid use of New keyword" or complaints about
WithEvents, that is what happened -- delete the module and redo it as a class.

Order to add them
-----------------

  00-modProbe              Run ProbeWord FIRST and send the output back. It
                           checks the Word features everything else depends on.

  Stage 1 -- no Word document is touched. Proves the parsing, projection,
  invariant and wrap-planning logic inside real Word VBA.

  01-modFlexParse
  02-modIgtModel
  03-modLeipzig
  04-modWrap
  05-clsIgtWarning         CLASS MODULE
  06-modTests

  Then, in the Immediate window (View > Immediate Window):   RunAllTests
  Expect every line to read PASS and the last line to read ALL PASS.

  Stage 2 -- adds everything that touches a document.

  07-modStyles
  08-modSettings
  09-modMeasure
  10-modRender
  11-modReadBack
  12-modLingTeX
  13-clsAppEvents          CLASS MODULE

  Then run RunDocTests, and see QUICKSTART.md for what to test by hand.

VBA compiles the whole project at once, so stage 1 only works because those six
modules reference nothing defined in the other seven. That is checked
mechanically -- see the verification notes in QUICKSTART.md.
TXT
sed -i.bak 's/$/\r/' "$out/00-README.txt" && rm -f "$out/00-README.txt.bak"

echo ""
echo "  00-README.txt    (read this first)"
echo ""
echo "Done. $(ls -1 "$out" | wc -l | tr -d ' ') files in $out"
