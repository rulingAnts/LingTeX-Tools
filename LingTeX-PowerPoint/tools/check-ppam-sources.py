#!/usr/bin/env python3
"""Every VBA module compiled into LingTeX-PowerPoint.ppam is its source, line for
line: the shared modules in build/shared/ (staged from LingTeX-Word by
stage-shared.sh) and the add-in's own in src/, less the tests. The mirror of
LingTeX-Word's check-dotm-sources.py, whose decompressor, line normaliser and
comparison it borrows, so there is one copy of each.

    python3 check-ppam-sources.py path/to/LingTeX-PowerPoint.ppam

Exit 0 when every module agrees, 1 otherwise; SKIP (exit 0) without olefile
unless LINGTEX_REQUIRE_OLEFILE is set.
"""
import importlib.util, io, os, pathlib, struct, sys, zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
WORD_TOOLS = ROOT.parent / "LingTeX-Word" / "tools"
NOT_SHIPPED = {"modPptTests"}

try:
    import olefile
except ImportError:
    if os.environ.get("LINGTEX_REQUIRE_OLEFILE"):
        print("  FAIL  olefile is not installed, and this run requires the module-source check")
        sys.exit(1)
    print("  SKIP  olefile is not installed (pip install olefile); VBA modules not compared with the sources")
    sys.exit(0)

_spec = importlib.util.spec_from_file_location("check_dotm_sources", WORD_TOOLS / "check-dotm-sources.py")
_cds = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_cds)
decompress, code_lines, compare = _cds.decompress, _cds.code_lines, _cds.compare

fails = 0


def ok(msg):
    print("  OK    " + msg)


def fail(msg):
    global fails
    fails += 1
    print("  FAIL  " + msg)


def modules(ppam):
    """{name: module text} out of ppt/vbaProject.bin."""
    with zipfile.ZipFile(ppam) as z:
        if "ppt/vbaProject.bin" not in z.namelist():
            fail("ppt/vbaProject.bin is missing -- saved without the macros?")
            return {}
        vba = z.read("ppt/vbaProject.bin")
    try:
        ole = olefile.OleFileIO(io.BytesIO(vba))
    except Exception as e:
        fail("ppt/vbaProject.bin is not an OLE file, so it holds no VBA project (%s)" % type(e).__name__)
        return {}
    d = decompress(ole.openstream("VBA/dir").read())
    i, cur, found = 0, {}, []
    while i + 6 <= len(d):
        rid, size = struct.unpack_from("<HI", d, i)
        i += 6
        if rid == 0x0009:
            i += 6
            continue
        data = d[i:i + size]
        i += size
        if rid == 0x0019:
            cur = {"name": data.decode("latin-1")}
        elif rid == 0x001A:
            cur["stream"] = data.decode("latin-1")
        elif rid == 0x0031:
            cur["offset"] = struct.unpack_from("<I", data)[0]
        elif rid == 0x002B:
            found.append(cur)
    out = {}
    for m in found:
        raw = ole.openstream("VBA/" + m["stream"]).read()
        text = decompress(raw[m["offset"]:]).decode("latin-1")
        if not text.startswith("Attribute VB_Name"):
            fail("%s: no source text at the recorded offset (the project is not readable)" % m["name"])
            continue
        out[m["name"]] = text
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check-ppam-sources.py path/to/LingTeX-PowerPoint.ppam")
    ppam = pathlib.Path(sys.argv[1])
    if not ppam.is_file():
        fail("the add-in does not exist: %s" % ppam)
        sys.exit(1)
    sources = {}
    for folder in (ROOT / "build" / "shared", ROOT / "src"):
        if not folder.is_dir():
            fail("no folder at %s%s" % (folder, " (run tools/stage-shared.sh)" if folder.name == "shared" else ""))
            sys.exit(1)
        for p in sorted(folder.iterdir()):
            if p.suffix.lower() in (".bas", ".cls") and p.stem not in NOT_SHIPPED:
                sources[p.stem] = p.read_bytes().decode("latin-1")
    mods = modules(ppam)
    if not mods:
        sys.exit(1)
    for name in sorted(mods):
        if name in sources:
            compare(name, mods[name], sources[name])
        else:
            fail("%-20s is in the add-in but has no file in build/shared/ or src/ -- shipped code that is in no source" % name)
    for name in sorted(sources):
        if name not in mods:
            fail("%-20s is a source but not in the add-in -- re-run SaveAsAddInSource and build-ppam.sh" % name)
    if fails:
        print("        The add-in is not the sources: run the rig with --macro SaveAsAddInSource, then build-ppam.sh.")
        sys.exit(1)
    ok("all %d modules in the add-in are their sources" % len(mods))


if __name__ == "__main__":
    main()
