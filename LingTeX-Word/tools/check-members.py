#!/usr/bin/env python3
"""Every .Member the VBA sources use exists somewhere Word for Mac can see it:
in one of the type libraries inside the Word bundle (Word, Office, VBA, OLE),
or declared in the project itself (a Sub, Function, Property, Type field, Enum
member, public variable).

Why: VBA on the Mac compiles a module when it is first reached, and an
unknown member ("Method or data member not found") then shows a MODAL
"Compile error in hidden module" dialog that stops Word answering the rig at
all (2026-09-29: ParagraphFormat.ContextualSpacing, absent from Word for Mac's
library, froze the run until Seth clicked OK). vba-lint.py checks names and
arity but cannot know the object model; the type libraries can.

Names in a type library's name table are padded (e.g. "LineSpacingRuleW"), so
a member counts as present when its name occurs as a substring of the library
bytes, case-insensitively (memory: reference-office-mac-type-libraries). That
never flags a real member; it can miss a misspelling that happens to be a
substring of another name, which is the safe direction.

    python3 check-members.py [src-folder]
Exit 0 when every member is found (or SKIP when the libraries are absent, as
on a CI runner), 1 otherwise.
"""
import pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "src"
LIBDIR = pathlib.Path("/Applications/Microsoft Word.app/Contents/SharedSupport/Type Libraries")
LIBS = ["Microsoft Word.tlb", "mso.tlb", "VbaEN6.tlb", "vbapp.tlb", "vbappmt.tlb", "fm20.tlb", "oles.tlb"]
OLE = pathlib.Path("/Applications/Microsoft Word.app/Contents/Frameworks/OLEAutomation.framework/Versions/A/Resources/stdole2.tlb")

libs = [LIBDIR / n for n in LIBS if (LIBDIR / n).is_file()] + ([OLE] if OLE.is_file() else [])
if not any(p.name == "Microsoft Word.tlb" for p in libs):
    print("  SKIP  Word for Mac's type libraries are not here; object-model members not checked")
    sys.exit(0)
blob = b"".join(p.read_bytes() for p in libs).lower()


def code_of(text):
    """The code with strings and comments blanked, line by line."""
    out = []
    for ln in re.split(r"\r\n|\r|\n", text):
        s, i, inq = [], 0, False
        while i < len(ln):
            ch = ln[i]
            if inq:
                if ch == '"':
                    if i + 1 < len(ln) and ln[i + 1] == '"':
                        i += 2
                        continue
                    inq = False
                s.append(" ")
            elif ch == '"':
                inq = True
                s.append(" ")
            elif ch == "'":
                break
            else:
                s.append(ch)
            i += 1
        line = "".join(s)
        if re.match(r"\s*Rem\b", line):
            line = ""
        if re.match(r"\s*Attribute\s", line):
            line = ""
        out.append(line)
    return out


files = sorted(p for p in SRC.iterdir() if p.suffix.lower() in (".bas", ".cls", ".frm"))
declared = set()
uses = []
for f in files:
    lines = code_of(f.read_bytes().decode("latin-1"))
    block = None
    for n, ln in enumerate(lines, 1):
        for m in re.finditer(r"\b(?:Sub|Function|Property\s+(?:Get|Let|Set))\s+([A-Za-z_]\w*)", ln):
            declared.add(m.group(1).lower())
        m = re.match(r"\s*(?:Public|Private)?\s*(Type|Enum)\s+([A-Za-z_]\w*)", ln)
        if m:
            block = m.group(1)
            declared.add(m.group(2).lower())
            continue
        if block and re.match(r"\s*End\s+(Type|Enum)\b", ln):
            block = None
            continue
        if block:
            m = re.match(r"\s*([A-Za-z_]\w*)", ln)
            if m:
                declared.add(m.group(1).lower())
            continue
        for m in re.finditer(r"\b(?:Public|Global|Dim|Private|Const|WithEvents)\s+(?:WithEvents\s+)?([A-Za-z_]\w*)", ln):
            declared.add(m.group(1).lower())
        # Every ".Name", chained ones too (a pattern that consumed the character
        # before the dot missed the last member of p.Format.ContextualSpacing).
        for m in re.finditer(r"\.([A-Za-z_]\w*)", ln):
            if m.start() > 0 and ln[m.start() - 1].isdigit():
                continue
            if f.suffix.lower() == ".frm" and ln[max(0, m.start() - 2):m.start()].lower() == "me":
                continue        # a form's own members (Me.StartUpPosition) resolve at run time
            uses.append((f.name, n, m.group(1)))

bad = {}
for fname, n, name in uses:
    low = name.lower()
    if low in declared or low.encode("latin-1") in blob:
        continue
    bad.setdefault(name, []).append("%s:%d" % (fname, n))

if bad:
    for name in sorted(bad):
        where = bad[name]
        print("  FAIL  .%s is in no type library Word for Mac has and is declared nowhere in src/ (%s%s)"
              % (name, ", ".join(where[:3]), " ..." if len(where) > 3 else ""))
    print("        A member Word for Mac lacks is a compile error there, shown as a modal dialog")
    print("        that stops the rig. Look it up in the .tlb (substring) before using it.")
    sys.exit(1)
print("  OK    every .Member in %d module(s) exists in Word for Mac's type libraries or in src/ (%d uses)"
      % (len(files), len(uses)))
