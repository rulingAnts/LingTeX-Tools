#!/usr/bin/env python3
"""check-vba-refs.py -- LingTeX-Word

Fails when the template's VBA project references another VBA project.

A project reference names a file by its path on the machine that saved it, so
on every other machine it is MISSING -- and a MISSING reference breaks every
built-in function in every module: "Compile error in hidden module:
modLingTeX", "Can't find project or library". beta.3 to beta.5 carried one to
/Users/Seth/Library/Containers/com.microsoft.Word/Data/Normal, added because
SaveAsTemplate saved a macro-enabled DOCUMENT (a document references its
attached template); beta.5 declared the package a template, and Windows Word
then failed to compile it (Seth, 2026-09-14). Libraries (VBA, Word, Office)
and controls (MSForms) are found by their registered IDs and are fine.

Reads word/vbaProject.bin with olefile and the MS-OVBA decompression below.

    python3 check-vba-refs.py path/to/LingTeX-Word.dotm      exit 0 ok, 1 not
"""
import io
import struct
import sys
import zipfile

try:
    import olefile
except ImportError:
    import os
    if os.environ.get("LINGTEX_REQUIRE_OLEFILE"):
        print("  FAIL  olefile is not installed, and this run requires the VBA reference check")
        sys.exit(1)
    print("  SKIP  olefile is not installed (pip install olefile); VBA references not checked")
    sys.exit(0)


def decompress(data):
    """MS-OVBA 2.4.1: a signature byte, then chunks of compressed tokens."""
    if not data or data[0] != 1:
        raise ValueError("not an MS-OVBA compressed container")
    out = bytearray()
    pos = 1
    while pos < len(data):
        header = struct.unpack_from("<H", data, pos)[0]
        size = (header & 0x0FFF) + 3
        compressed = header & 0x8000
        chunk_end = min(pos + size, len(data))
        pos += 2
        start = len(out)
        if not compressed:
            out += data[pos:pos + 4096]
            pos += 4096
            continue
        while pos < chunk_end:
            flags = data[pos]
            pos += 1
            for bit in range(8):
                if pos >= chunk_end:
                    break
                if not flags & (1 << bit):
                    out.append(data[pos])
                    pos += 1
                    continue
                token = struct.unpack_from("<H", data, pos)[0]
                pos += 2
                done = len(out) - start
                bits = max((done - 1).bit_length(), 4)
                length_mask = 0xFFFF >> bits
                offset = (token >> (16 - bits)) + 1
                length = (token & length_mask) + 3
                for _ in range(length):
                    out.append(out[-offset])
    return bytes(out)


def references(dotm):
    with zipfile.ZipFile(dotm) as z:
        vba = z.read("word/vbaProject.bin")
    ole = olefile.OleFileIO(io.BytesIO(vba))
    d = decompress(ole.openstream("VBA/dir").read())
    i, name, found = 0, None, []
    while i + 6 <= len(d):
        rid, size = struct.unpack_from("<HI", d, i)
        i += 6
        if rid == 0x0009:        # PROJECTVERSION: its Size field says 4, the record is 6
            i += 6
            continue
        data = d[i:i + size]
        i += size
        if rid == 0x0016:        # REFERENCENAME
            name = data.decode("latin-1")
        elif rid == 0x000D:      # REFERENCEREGISTERED: a library, by registered ID
            found.append(("library", name, ""))
        elif rid == 0x002F:      # REFERENCECONTROL
            found.append(("control", name, ""))
        elif rid == 0x000E:      # REFERENCEPROJECT: another VBA project, by path
            n = struct.unpack_from("<I", data, 0)[0]
            found.append(("project", name, data[4:4 + n].decode("latin-1")))
        elif rid == 0x000F:      # PROJECTMODULES: the references are over
            break
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check-vba-refs.py path/to/file.dotm")
    refs = references(sys.argv[1])
    projects = [r for r in refs if r[0] == "project"]
    if projects:
        for _, name, path in projects:
            print(f"  FAIL  the VBA project references the project \"{name}\" at {path}: "
                  "MISSING on every other machine, so nothing compiles there. "
                  "Save the template again from Word with SaveAsTemplate (FileFormat 15).")
        sys.exit(1)
    kinds = ", ".join(f"{k} {n}" for k, n, _ in refs)
    print(f"  OK    the VBA project references no other project ({kinds})")


if __name__ == "__main__":
    main()
