#!/usr/bin/env python3
"""check-names.py -- LingTeX-PowerPoint

Names every procedure the PowerPoint modules call that no staged module
defines. In PowerPoint such a call is a compile error, and the rig cannot
read that dialog: on macOS 27 the VBA editor's window is not exposed to
accessibility at all (measured 2026-09-28), so run-in-powerpoint.sh only
sees "run VB macro" fail with -18. This runs before every import instead.

    python3 LingTeX-PowerPoint/tools/check-names.py             the rig's modules
    python3 LingTeX-PowerPoint/tools/check-names.py a.bas ...   these, against the same project

Exit 0 when every call resolves, 1 otherwise.

A heuristic, not a compiler. It resolves three shapes of reference:
  Name(...)            a call with an argument list, not after a dot
  Name arg, ...        a statement that starts with a name, not after a dot
  Name                 a bare CamelCase name used as a value (a Function
                       called without parentheses, or a Const)
against the procedures, Public Consts and Enum members of every module the
rig stages, plus VBA's own functions, plus anything the same module declares
(Dim, Const, ReDim, parameters, labels, Type and Enum members). Anything
after a dot is a member and is not checked. Names starting in lower case
are not checked as bare values, so host constants (msoTrue, ppLayoutBlank,
vbTab) pass without a list of them.
"""
import re
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

STAGED = ("build/shared/*.bas", "build/shared/*.cls", "src/*.bas",
          "tools/*.bas", "tools/probe/*.bas")

KEYWORDS = set("""
and as byref byval call case const declare dim do each else elseif end enum erase error
event exit false for friend function get global gosub goto if implements in input is let
like loop lset me mod new next not nothing null on option optional or paramarray preserve
print private property public put raiseevent redim rem resume return rset seek select set
static step stop sub then to true type typeof until wend while with withevents xor
attribute debug open close write line lock unlock width name kill mkdir rmdir chdir setattr
filecopy randomize beep appactivate sendkeys mid load unload doevents output append binary
random access shared read ptrsafe lib alias explicit base compare text
long double boolean integer variant object byte currency single string collection date
""".split())

BUILTINS = set("""
abs array asc ascb ascw atn callbyname cbool cbyte ccur cdate cdbl cdec chr chrb chrw
cint clng clnglng clngptr command cos createobject csng cstr curdir cvar cvdate cverr
date dateadd datediff datepart dateserial datevalue day dir doevents environ eof erl
error exp fileattr filedatetime filelen filter fix format formatcurrency formatdatetime
formatnumber formatpercent freefile getattr getobject hex hour iif inputbox instr instrb
instrrev int isarray isdate isempty iserror ismissing isnull isnumeric isobject join
lbound lcase left leftb len lenb loc lof log ltrim macid macscript applescripttask
midb minute month monthname msgbox now oct partition qbcolor rgb replace right rightb
rnd round rtrim second sgn shell sin space spc split sqr str strcomp strconv strreverse
switch tab tan time timer timeserial timevalue trim typename ubound ucase val vartype
weekday weekdayname year err vba
application activepresentation activewindow presentations slideshowwindows commandbars
selection activedocument documents thisdocument
""".split())

WORD_RE = re.compile(r"[A-Za-z_]\w*")


def logical_lines(text):
    """Join VBA continuation lines; strip string literals and comments."""
    out = []
    buf = ""
    for raw in text.splitlines():
        line = raw.rstrip("\r\n")
        if buf:
            line = buf + " " + line.lstrip()
            buf = ""
        stripped = line.rstrip()
        if stripped.endswith(" _"):
            buf = stripped[:-2]
            continue
        out.append(line)
    if buf:
        out.append(buf)
    cleaned = []
    for line in out:
        line = re.sub(r'"(?:[^"]|"")*"', '""', line)
        i = line.find("'")
        if i >= 0:
            line = line[:i]
        cleaned.append(line)
    return cleaned


DEF_RE = re.compile(
    r"^\s*(?:(Public|Private|Friend)\s+)?(?:Static\s+)?"
    r"(Sub|Function|Property\s+(?:Get|Let|Set))\s+([A-Za-z_]\w*)\s*(\((.*)\))?", re.I)
DECL_RE = re.compile(r"^\s*(?:(Public|Private|Global)\s+)?(?:(Dim|Static|Const|ReDim(?:\s+Preserve)?|WithEvents)\s+)?(.*)$", re.I)
LABEL_RE = re.compile(r"^\s*([A-Za-z_]\w*):\s*$")
TYPE_RE = re.compile(r"^\s*(?:(Public|Private)\s+)?(Type|Enum)\s+([A-Za-z_]\w*)", re.I)
END_TYPE_RE = re.compile(r"^\s*End\s+(Type|Enum)\b", re.I)


def split_top(s):
    parts, depth, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    return parts


def lead_ident(s):
    s = re.sub(r"^\s*(?:Optional|ByVal|ByRef|ParamArray)\s+", "", s, flags=re.I)
    s = re.sub(r"^\s*(?:Optional|ByVal|ByRef|ParamArray)\s+", "", s, flags=re.I)
    m = WORD_RE.match(s.lstrip())
    return m.group(0) if m else None


class Module:
    def __init__(self, path):
        self.path = path
        self.name = path.stem
        self.is_class = path.suffix.lower() == ".cls"
        self.lines = logical_lines(path.read_text(encoding="latin-1"))
        self.procs = {}        # name.lower() -> "public"/"private"
        self.declared = set()  # lower-case names declared in this module
        self.public_names = set()
        self.calls = []        # (lineno, name)
        self._scan()

    def _declare(self, name, public=False):
        if not name:
            return
        self.declared.add(name.lower())
        if public:
            self.public_names.add(name.lower())

    def _scan(self):
        in_block = None
        block_public = False
        header = self.is_class   # a .cls starts with VERSION/BEGIN/END before its Attributes
        for n, line in enumerate(self.lines, 1):
            if not line.strip():
                continue
            if re.match(r"^\s*Attribute\b", line, re.I):
                header = False
                continue
            if header or re.match(r"^\s*Option\b", line, re.I):
                continue
            if line.lstrip().startswith("#"):   # #If Mac Then ... #End If
                continue
            m = TYPE_RE.match(line)
            if m:
                in_block = m.group(2).lower()
                block_public = (m.group(1) or "Public").lower() == "public"
                self._declare(m.group(3), block_public)
                continue
            if in_block:
                if END_TYPE_RE.match(line):
                    in_block = None
                    continue
                if in_block == "enum":
                    self._declare(lead_ident(line), block_public)
                else:
                    self._declare(lead_ident(line), False)
                continue
            m = LABEL_RE.match(line)
            if m:
                self._declare(m.group(1))
                continue
            m = DEF_RE.match(line)
            if m:
                scope = (m.group(1) or "Public").lower()
                pname = m.group(3)
                self.procs[pname.lower()] = "private" if scope == "private" else "public"
                self._declare(pname, scope != "private" and not self.is_class)
                if m.group(5):
                    for p in split_top(m.group(5)):
                        self._declare(lead_ident(p))
                self._collect_calls(n, line, skip_lead=True)
                continue
            m = DECL_RE.match(line)
            if m and (m.group(2) or (m.group(1) and not re.match(
                    r"^\s*(Sub|Function|Property|Declare)\b", m.group(3), re.I))):
                public = (m.group(1) or "").lower() in ("public", "global")
                kind = (m.group(2) or "").lower()
                for p in split_top(m.group(3)):
                    self._declare(lead_ident(p), public and kind != "dim")
                self._collect_calls(n, line, skip_lead=True)
                continue
            if re.match(r"^\s*Declare\b", line, re.I) or re.match(r"^\s*(Public|Private)\s+Declare\b", line, re.I):
                dm = re.search(r"\b(Sub|Function)\s+([A-Za-z_]\w*)", line, re.I)
                if dm:
                    self.procs[dm.group(2).lower()] = "public"
                    self._declare(dm.group(2), True)
                continue
            self._collect_calls(n, line, skip_lead=False)

    def _collect_calls(self, n, line, skip_lead):
        # Name(...)  not after a dot, a bang, or another word character
        for m in re.finditer(r"(?<![.!\w])([A-Za-z_]\w*)\$?\s*\(", line):
            self.calls.append((n, m.group(1)))
        # bare CamelCase value: starts upper case, has a lower-case letter, is
        # not followed by ( . $ or a word character, and does not follow a dot
        # or one of the words that introduce a type or a definition
        for m in re.finditer(r"(?<![.!\w])([A-Z]\w*[a-z]\w*)(?![\w(.$])", line):
            before = line[:m.start()].rstrip().split(" ")[-1].lower() if line[:m.start()].strip() else ""
            if before in ("as", "new", "typeof", "is", "function", "sub", "property", "get", "let",
                          "goto", "gosub", "type", "enum", "next", "for", "each", "dim", "const",
                          "static", "public", "private", "global", "exit", "end", "with", "call",
                          "implements", "lib", "alias", "declare", "preserve", "redim", "erase"):
                continue
            self.calls.append((n, m.group(1)))
        if skip_lead:
            return
        # a statement that starts with a name: "Note arg" / "ReleaseScratch"
        for seg in re.split(r"(?<!\w):(?!=)", line):
            for stmt in re.split(r"\b(?:Then|Else)\b", seg, flags=re.I):
                m = re.match(r"^\s*([A-Za-z_]\w*)\s*(.*)$", stmt)
                if not m:
                    continue
                rest = m.group(2)
                if rest.startswith(("=", "(", ".", ":")):
                    continue
                self.calls.append((m.start(1) and n or n, m.group(1)))


def main(argv):
    files = []
    for pat in STAGED:
        files += sorted(ROOT.glob(pat))
    mods = [Module(p) for p in files]
    by_path = {m.path.resolve(): m for m in mods}
    public = set(BUILTINS) | set(KEYWORDS)
    for m in mods:
        public |= {k for k, v in m.procs.items() if v == "public" and not m.is_class}
        public |= m.public_names
    targets = mods if not argv else [by_path.get(pathlib.Path(a).resolve()) or Module(pathlib.Path(a)) for a in argv]
    problems = 0
    for m in targets:
        seen = set()
        for n, name in m.calls:
            key = name.lower()
            if key in KEYWORDS or key in BUILTINS:
                continue
            if key in m.declared or key in m.procs or key in public:
                continue
            if (key, n) in seen:
                continue
            seen.add((key, n))
            problems += 1
            where = [o.name for o in mods if o.procs.get(key) == "private" or (o.is_class and key in o.procs)]
            hint = f"  (Private in {', '.join(where)})" if where else ""
            print(f"{m.path.relative_to(ROOT) if m.path.is_relative_to(ROOT) else m.path}:{n}: {name} is not defined in any staged module{hint}")
    if problems:
        print(f"check-names: {problems} unresolved name(s)")
        return 1
    print(f"check-names: every name resolves ({len(targets)} module(s), {len(mods)} in the project)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
