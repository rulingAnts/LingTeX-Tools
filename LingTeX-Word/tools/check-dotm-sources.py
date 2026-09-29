#!/usr/bin/env python3
"""check-dotm-sources.py -- LingTeX-Word

Fails unless every VBA module inside the template IS its committed source.

WHY. The template is built in Word by hand, so nothing guarantees that what ships
is what is in the repository. The manifest check in check-dotm.sh proves src/ has
not changed since build-dotm.sh ran; it does not prove the compiled modules equal
src/ -- a fix typed into the VBA editor and never exported passes it, and so did
the classes that the importer installed double-spaced for a week (2026-09-15).
And on 2026-09-16 the tracked template turned out to carry language data that a
text scrub of the repository could not reach, because a .dotm is a zip holding
an OLE file holding compressed module text: nothing greps it.

This check reads that text out. There is deliberately NO list of sensitive words
here -- such a list, in a public repository, would itself be the leak. Instead the
template is clean BY CONSTRUCTION: it passes only if every module's code is
exactly the committed source it was imported from, and the sources are text in
git, reviewed and scanned. Fail on any module that differs, any module with no
source, any source with no module.

"EXACTLY" allows for the one rewrite Word makes on import: identifier CASING
follows the first declaration the editor sees, so `.path` may come back as
`.Path`. Measured against real output (the 2026-09-15 engine versus the sources
it was imported from, about 12,000 lines): 1,009 lines differ in case only, none
in whitespace, none otherwise. So lines are compared case-insensitively and no
more loosely than that. Attribute lines and the class/form header block are
dropped from both sides, since the editor keeps them out of the code text.

A second, independent signal: at least four of the made-up example words that
the scrubbed fixtures use (zel, vimo, rixu, Ozivela, zuvo, levo -- all already
public in src/modTests.bas) must occur as whole words inside the compiled text.
If the comparison above were ever too lenient, this still says the fixtures
inside are the scrubbed ones.

NEVER PRINTS MODULE CONTENT. A dirty template found in the release job must not
have its differing line copied into a public CI log: reports name the module,
the line number and the two line lengths, nothing else.

    python3 check-dotm-sources.py path/to/LingTeX-Word.dotm [path/to/src]

Exit 0 all agree, 1 otherwise. Needs olefile: without it, SKIP with exit 0, or
FAIL if LINGTEX_REQUIRE_OLEFILE is set (the release workflow sets it).
LINGTEX_VBA_STANDIN=1 (set only by test-dotm-scripts.sh, whose synthetic package
carries a stand-in vbaProject.bin that is not an OLE file) makes a non-OLE
project a SKIP instead of a failure. Runs wherever check-dotm.sh runs: Linux,
python3, no Word.
"""
import importlib.util
import io
import os
import pathlib
import re
import struct
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
STANDIN = os.environ.get("LINGTEX_VBA_STANDIN") == "1"

try:
    import olefile
except ImportError:
    if os.environ.get("LINGTEX_REQUIRE_OLEFILE"):
        print("  FAIL  olefile is not installed, and this run requires the module-source check")
        sys.exit(1)
    print("  SKIP  olefile is not installed (pip install olefile); VBA modules not compared with src/")
    sys.exit(0)

# The MS-OVBA decompressor lives in check-vba-refs.py; one copy, not two.
_spec = importlib.util.spec_from_file_location("check_vba_refs", HERE / "check-vba-refs.py")
_cvr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cvr)
decompress = _cvr.decompress

# Made-up vocabulary of the scrubbed fixtures (src/modTests.bas). Public already.
SCRUBBED_WORDS = ("zel", "vimo", "rixu", "Ozivela", "zuvo", "levo")
SCRUBBED_MIN = 4

# Components Word puts in a template that have no file in src/. ThisDocument must
# also hold no code: code there would be shipped code that is in no source file.
CODELESS_ALLOWED = {"ThisDocument"}

fails = 0


def ok(msg):
    print("  OK    " + msg)


def fail(msg):
    global fails
    fails += 1
    print("  FAIL  " + msg)


def modules(dotm):
    """{name: module text} out of word/vbaProject.bin, or None for a stand-in."""
    with zipfile.ZipFile(dotm) as z:
        names = z.namelist()
        if "word/vbaProject.bin" not in names:
            fail("word/vbaProject.bin is missing -- saved as .dotx, or before importing?")
            return {}
        vba = z.read("word/vbaProject.bin")
    try:
        ole = olefile.OleFileIO(io.BytesIO(vba))
    except Exception as e:                      # olefile.NotOleFileError, mostly
        if STANDIN:
            print("  SKIP  word/vbaProject.bin is a test stand-in (LINGTEX_VBA_STANDIN); "
                  "VBA modules not compared with src/")
            return None
        fail("word/vbaProject.bin is not an OLE file, so it holds no VBA project (%s)"
             % type(e).__name__)
        return {}
    d = decompress(ole.openstream("VBA/dir").read())
    i, cur, found = 0, {}, []
    while i + 6 <= len(d):
        rid, size = struct.unpack_from("<HI", d, i)
        i += 6
        if rid == 0x0009:        # PROJECTVERSION: its Size field says 4, the record is 6
            i += 6
            continue
        data = d[i:i + size]
        i += size
        if rid == 0x0019:        # MODULENAME
            cur = {"name": data.decode("latin-1")}
        elif rid == 0x001A:      # MODULESTREAMNAME
            cur["stream"] = data.decode("latin-1")
        elif rid == 0x0031:      # MODULEOFFSET: where the compressed source starts
            cur["offset"] = struct.unpack_from("<I", data)[0]
        elif rid == 0x002B:      # MODULE terminator
            found.append(cur)
    out = {}
    for m in found:
        raw = ole.openstream("VBA/" + m["stream"]).read()
        text = decompress(raw[m["offset"]:]).decode("latin-1")
        # Belt and braces: the walk gives the offset, the anchor confirms it.
        if not text.startswith("Attribute VB_Name"):
            fail("%s: no source text at the recorded offset (the project is not readable)" % m["name"])
            continue
        out[m["name"]] = text
    return out


def code_lines(text):
    """The code the editor shows: no VERSION line, no BEGIN..END header block of
    a class or form, no Attribute lines, no leading or trailing blank lines.
    The same stripping as StripVbaMetadata in tools/ImportModules.bas."""
    out, in_header, started = [], False, False
    for ln in re.split(r"\r\n|\r|\n", text):
        t = ln.strip(" ")
        if t[:8] == "VERSION ":
            continue
        if not started and (t.upper() == "BEGIN" or t.upper()[:6] == "BEGIN "):
            in_header = True
            continue
        if in_header:
            if t.upper() == "END":
                in_header = False
            continue
        if t[:10] == "Attribute ":
            continue
        if not started and t == "":
            continue
        started = True
        out.append(ln)
    while out and out[-1].strip(" ") == "":
        out.pop()
    return out


def compare(name, module_text, source_text):
    """OK when every line agrees case-insensitively; otherwise a FAIL naming the
    module, the first differing line and the two lengths. Never the content."""
    a, b = code_lines(module_text), code_lines(source_text)
    diff = [i for i, (x, y) in enumerate(zip(a, b)) if x.lower() != y.lower()]
    if len(a) == len(b) and not diff:
        cased = sum(1 for x, y in zip(a, b) if x != y)
        ok("%-20s %5d lines, identical to its source%s"
           % (name, len(a), " (%d differ in identifier case only)" % cased if cased else ""))
        return
    if diff:
        i = diff[0]
        detail = ("first difference at line %d of %d (template line is %d characters, "
                  "source line %d), %d line(s) differ" % (i + 1, len(a), len(a[i]), len(b[i]), len(diff)))
    else:
        detail = "same text for %d lines, then the lengths differ" % min(len(a), len(b))
    if len(a) != len(b):
        detail += "; the template holds %d lines and the source %d" % (len(a), len(b))
    fail("%-20s is NOT its source: %s" % (name, detail))


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: check-dotm-sources.py path/to/file.dotm [path/to/src]")
    dotm = pathlib.Path(sys.argv[1])
    src = pathlib.Path(sys.argv[2]) if len(sys.argv) == 3 else HERE.parent / "src"

    # Loud, not silent: an absent template is the failure that hid for a week.
    if not dotm.is_file():
        fail("the template does not exist: %s" % dotm)
        sys.exit(1)
    if not src.is_dir():
        fail("no src/ folder at %s" % src)
        sys.exit(1)

    mods = modules(dotm)
    if mods is None:                 # a declared stand-in: SKIP already printed
        sys.exit(0)

    sources = {}
    for p in sorted(src.iterdir()):
        if p.suffix.lower() in (".bas", ".cls", ".frm"):
            sources[p.stem] = p.read_bytes().decode("latin-1")

    if mods:
        for name in sorted(mods):
            if name in sources:
                compare(name, mods[name], sources[name])
            elif name in CODELESS_ALLOWED:
                n = len(code_lines(mods[name]))
                if n == 0:
                    ok("%-20s holds no code (as it should)" % name)
                else:
                    fail("%-20s holds %d lines of code, which are in no source file" % (name, n))
            else:
                fail("%-20s is in the template but has no file in src/ -- shipped code "
                     "that is in no source" % name)
        for name in sorted(sources):
            if name not in mods:
                fail("%-20s is in src/ but not in the template -- import it and rebuild" % name)

        # The independent signal: the compiled fixtures are the scrubbed ones.
        text = "\n".join(mods.values())
        present = [w for w in SCRUBBED_WORDS if re.search(r"(?<![A-Za-z])%s(?![A-Za-z])" % w, text)]
        if len(present) >= SCRUBBED_MIN:
            ok("%d of %d made-up fixture words are present in the compiled text"
               % (len(present), len(SCRUBBED_WORDS)))
        else:
            fail("only %d of %d made-up fixture words are present in the compiled text -- "
                 "these are not the scrubbed fixtures" % (len(present), len(SCRUBBED_WORDS)))

    # Summarise in check-dotm.sh's own voice: it counts this script as one of its
    # checks, so no second "ALL PASS" line of our own.
    if fails:
        print("        The template is not the committed sources: re-import src/ in "
              "Word, save, and re-run build-dotm.sh.")
        sys.exit(1)
    if mods:
        ok("all %d modules in the template are their committed sources" % len(mods))


if __name__ == "__main__":
    main()


if __name__ == "__main__":
    main()
