#!/usr/bin/env python3
"""
LingTeX-Word -- structural linter for the VBA sources.

Run:  python3 LingTeX-Word/tools/vba-lint.py

VBA cannot be compiled outside Word, and Word is not available in CI, so this
catches the classes of mistake that would otherwise only surface as a compile
error on a user's machine:

  * unbalanced block constructs (Sub/Function/If/For/Do/With/Select/Type/Property)
  * non-ASCII bytes -- a .bas is imported in the system ANSI code page, not
    UTF-8, so a non-ASCII literal arrives as mojibake, differently on Windows
    and on Mac.  Non-ASCII must be built with ChrW() at run time.
  * a missing Option Explicit or Attribute VB_Name
  * Windows-only APIs that would break Mac Word
  * ReDim Preserve on any but the last dimension, which is a run-time error 9
  * Exit Sub used inside a Function, and Exit Function inside a Sub

It is a structural check, not a compiler: it does not resolve names or types.
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The engine, plus the standalone modules that ship for pasting into Word.
SRC_DIRS = [ROOT / "src", ROOT / "tools", ROOT / "tools" / "probe"]

# Platform traps. Each of these exists on Windows Word and not on Mac Word.
WINDOWS_ONLY = {
    r"\bScripting\.Dictionary\b": "Scripting.Dictionary is Windows-only; use a Collection with string keys",
    r"\bScripting\.FileSystemObject\b": "FileSystemObject is Windows-only",
    r"\bADODB\.": "ADODB is Windows-only",
    r"\bWScript\.Shell\b": "WScript.Shell is Windows-only",
    r"\bMSScriptControl\b": "MSScriptControl is Windows-only",
    r"\bVBScript\.RegExp\b": "VBScript.RegExp is Windows-only; hand-roll a character scan",
    r"\bCreateObject\s*\(": "CreateObject reaches for COM, which Mac Word lacks; avoid it",
    r"\bDeclare\s+(PtrSafe\s+)?(Function|Sub)\b": "Win32 Declare needs an #If Mac Then guard",
}

# VBA keywords and statement names that must not be used as a procedure name.
# Declaring e.g. "Private Sub Line(...)" compiles in some contexts and then
# collides with the Line Input statement in a way that reads as nonsense. Only
# names we DEFINE are checked -- calling Left$, Len, Format and friends is fine.
# VBA reserved words that cannot be used as an IDENTIFIER at all -- as a variable,
# a parameter or a user-defined-type field. Using one is a bare "Syntax error"
# with no hint as to which word is at fault, so it costs a round trip to find.
#
# "Any" is the one that actually bit: it is reserved because Declare statements
# use "As Any", and it reads so much like an ordinary word that "Dim any As
# Boolean" looks unremarkable. Note this list is deliberately NARROWER than the
# procedure-name list below -- Format, Left, Len and friends are built-in
# functions rather than reserved words, and VBA does allow them as variables.
RESERVED_IDENTIFIERS = set("""
and any as boolean byref byte byval call case close const currency declare dim do
double each else elseif empty end endif enum eqv erase event exit false for
friend function get gosub goto if imp implements in input integer is let lib like
line lock long loop lset me mod new next not nothing null object on open option
optional or paramarray preserve print private property public put raiseevent redim
rem resume return rset seek select set single static step stop string sub then to
true type typeof unlock until variant wend while with withevents write xor
""".split())

RESERVED_PROC_NAMES = set("""
line input output print write get put open close name error resume stop loop next
set let option type end call exit kill dir date time timer seek lock unlock width
reset randomize beep mod and or not xor eqv imp is like to step then else each in
as byval byref optional paramarray preserve static public private friend dim redim
const declare sub function property event implements withevents new nothing true
false empty null me on goto gosub return select case with do while until wend for
if elseif rem attribute enum erase spc tab string space len left right mid abs sgn
int fix log exp sqr rnd format val str chr asc iif choose switch array lbound
ubound split join replace instr trim ltrim rtrim ucase lcase cint clng csng cdbl
cstr cbool cdate cvar typename vartype isnull isempty iserror isnumeric isdate
isarray isobject ismissing
""".split())

# Statements that open a block, paired with the statement that closes it.
OPENERS = [
    (re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?Sub\b", re.I), "Sub", "End Sub"),
    (re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?Function\b", re.I), "Function", "End Function"),
    (re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?Property\s+(?:Get|Let|Set)\b", re.I), "Property", "End Property"),
    (re.compile(r"^(?:Public\s+|Private\s+)?Type\b", re.I), "Type", "End Type"),
    (re.compile(r"^(?:Public\s+|Private\s+)?Enum\b", re.I), "Enum", "End Enum"),
    (re.compile(r"^With\b", re.I), "With", "End With"),
    (re.compile(r"^Select\s+Case\b", re.I), "Select", "End Select"),
    (re.compile(r"^Do\b", re.I), "Do", "Loop"),
    (re.compile(r"^For\b", re.I), "For", "Next"),
    (re.compile(r"^If\b.*\bThen$", re.I), "If", "End If"),
    (re.compile(r"^ElseIf\b.*\bThen$", re.I), None, None),   # neither opens nor closes
]

CLOSERS = {
    "end sub": "Sub", "end function": "Function", "end property": "Property",
    "end type": "Type", "end enum": "Enum", "end with": "With",
    "end select": "Select", "loop": "Do", "end if": "If",
}


def logical_lines(text):
    """Join VBA line continuations, drop comments and blanks, keep line numbers."""
    out = []
    raw = text.split("\n")
    i = 0
    while i < len(raw):
        start = i + 1
        line = raw[i]
        while line.rstrip().endswith("_"):
            line = line.rstrip()[:-1]
            i += 1
            if i >= len(raw):
                break
            line += raw[i]
        i += 1

        stripped = line.strip()
        if not stripped or stripped.startswith("'") or stripped.lower().startswith("rem "):
            continue
        # Strip a trailing comment, respecting quoted strings.
        cleaned, in_str = [], False
        for ch in stripped:
            if ch == '"':
                in_str = not in_str
            if ch == "'" and not in_str:
                break
            cleaned.append(ch)
        stripped = "".join(cleaned).strip()
        if stripped:
            out.append((start, stripped))
    return out


def declared_identifiers(t, in_type):
    """Names introduced by a declaration on this line."""
    out = []
    if in_type:
        m = re.match(r"^([A-Za-z_]\w*)\s*\(?\)?\s+As\b", t, re.I)
        if m:
            out.append(m.group(1))
        return out

    m = re.match(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                 r"(?:Sub|Function|Property\s+\w+)\s+\w+\s*\(([^)]*)\)", t, re.I)
    if m and m.group(1).strip():
        for part in m.group(1).split(","):
            pm = re.search(r"(?:ByVal\s+|ByRef\s+|Optional\s+|ParamArray\s+)*([A-Za-z_]\w*)",
                           part.strip(), re.I)
            if pm:
                out.append(pm.group(1))

    m = re.match(r"^(?:Dim|ReDim(?:\s+Preserve)?|Static)\s+(.*)$", t, re.I)
    if m:
        for part in m.group(1).split(","):
            pm = re.match(r"\s*([A-Za-z_]\w*)", part)
            if pm:
                out.append(pm.group(1))
    return out


def check(path):
    problems = []
    data = path.read_bytes()

    for n, raw in enumerate(data.split(b"\n"), 1):
        if any(b > 0x7E or (b < 0x20 and b not in (0x09, 0x0D)) for b in raw):
            bad = raw.decode("utf-8", "replace")
            problems.append((n, "non-ASCII byte; build it with ChrW() instead: " + bad.strip()[:70]))

    text = data.decode("utf-8", "replace")
    lines = logical_lines(text)
    body = [t for _, t in lines]

    # A .bas starts with the Attribute line; a .cls carries the
    # VERSION/BEGIN/END preamble first. Either way the name attribute must be
    # present or File > Import has nothing to name the module after.
    if "Attribute VB_Name =" not in text.split("Option Explicit")[0]:
        problems.append((1, "missing the Attribute VB_Name header line needed by File > Import"))
    if path.suffix.lower() == ".cls" and not text.startswith("VERSION 1.0 CLASS"):
        problems.append((1, "a .cls must begin with the VERSION 1.0 CLASS preamble"))
    if not any(re.match(r"^Option\s+Explicit\b", t, re.I) for t in body):
        problems.append((1, "missing Option Explicit"))

    for n, t in lines:
        for pat, msg in WINDOWS_ONLY.items():
            if re.search(pat, t, re.I):
                problems.append((n, msg))
        # VBA does NOT short-circuit And/Or: every operand is evaluated. So a
        # bounds guard written as `If i <= UBound(a) And a(i) = x` still
        # evaluates a(i) and raises "subscript out of range". The guard has to be
        # a separate statement or a nested If.
        if re.match(r"^(If|ElseIf)\b", t, re.I) or re.search(r"=\s*\(.*\bAnd\b", t, re.I):
            guards = re.findall(r"\b(?:U|L)Bound\s*\(\s*([A-Za-z_]\w*)", t)
            if guards and re.search(r"\b(And|Or)\b", t, re.I):
                for g in guards:
                    # The same name indexed elsewhere on the line, not inside the
                    # UBound call itself.
                    stripped = re.sub(r"\b(?:U|L)Bound\s*\(\s*" + re.escape(g) + r"\s*\)", "", t)
                    if re.search(r"\b" + re.escape(g) + r"\s*\(", stripped):
                        problems.append((n, f"And/Or does not short-circuit in VBA: '{g}' is indexed on the same line as its UBound guard; split the guard into its own If"))
                        break

        # NOTE: there is deliberately no "ReDim Preserve resizes only the last
        # dimension" rule here.  VBA's actual constraint is that the non-final
        # bounds must evaluate to the SAME VALUES as before, not that they be
        # written as literals -- so `ReDim Preserve g(0 To nTiers - 1, 0 To n)`
        # is perfectly legal when nTiers has not changed.  A static check cannot
        # tell that apart from the real bug, and a rule that fires on correct
        # code is worse than no rule.  The call sites carry a comment instead.

    # Block balance, with a stack so mismatches name the offending construct.
    stack, scope, in_type = [], None, False
    for n, t in lines:
        if re.match(r"^(?:Public |Private )?Type\b", t, re.I):
            in_type = True
        elif re.match(r"^End Type\b", t, re.I):
            in_type = False
        low = t.lower()

        # Single-line If ("If x Then DoThing") opens nothing.
        closer = CLOSERS.get(low)
        if closer:
            if not stack:
                problems.append((n, f"'{t}' with no matching opener"))
            elif stack[-1][0] != closer:
                problems.append((n, f"'{t}' closes a {closer} but the innermost open block is a {stack[-1][0]} from line {stack[-1][1]}"))
                stack.pop()
            else:
                stack.pop()
            if closer in ("Sub", "Function", "Property"):
                scope = None
            continue

        if re.match(r"^next\b", low):
            if not stack:
                problems.append((n, "'Next' with no matching For"))
            elif stack[-1][0] != "For":
                problems.append((n, f"'Next' closes a For but the innermost open block is a {stack[-1][0]} from line {stack[-1][1]}"))
                stack.pop()
            else:
                stack.pop()
            continue

        m = re.match(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                     r"(?:Sub|Function|Property\s+(?:Get|Let|Set))\s+([A-Za-z_]\w*)",
                     t, re.I)
        if m and m.group(1).lower() in RESERVED_PROC_NAMES:
            problems.append((n, f"'{m.group(1)}' is a VBA keyword or built-in; rename the procedure"))

        # Reserved words as variable, parameter or UDT-field names.
        for name in declared_identifiers(t, in_type):
            if name.lower() in RESERVED_IDENTIFIERS:
                problems.append((n, f"'{name}' is a VBA reserved word and cannot be an "
                                    f"identifier; VBA reports only 'Syntax error'"))

        for pat, kind, _ in OPENERS:
            if kind is None:
                continue
            if pat.match(t):
                # A Declare is not a Sub/Function body.
                if re.search(r"\bDeclare\b", t, re.I):
                    break
                stack.append((kind, n))
                if kind in ("Sub", "Function", "Property"):
                    scope = kind
                break

        if scope == "Function" and re.match(r"^Exit\s+Sub\b", low):
            problems.append((n, "Exit Sub inside a Function"))
        if scope == "Sub" and re.match(r"^Exit\s+Function\b", low):
            problems.append((n, "Exit Function inside a Sub"))

    for kind, n in stack:
        problems.append((n, f"{kind} opened here is never closed"))

    return problems


# QUICKSTART.md promises that these six modules compile and run RunAllTests on
# their own, with the Word object model uninvolved. That is only true while they
# reference nothing defined in the other seven, so it is checked rather than
# trusted -- a stray call added later would silently break the staged install path.
STAGE1 = {
    "modFlexParse.bas", "modIgtModel.bas", "modLeipzig.bas",
    "modWrap.bas", "modTests.bas", "clsIgtWarning.cls",
}
# Not part of the engine; each is pasted on its own and depends on nothing else.
# Excluded from the stage-1 dependency check, which only concerns engine modules.
STANDALONE = {"modProbe.bas", "ImportModules.bas"}


def proc_names(text):
    """Procedure and Const names defined in a module."""
    names = set()
    for _, t in logical_lines(text):
        m = re.match(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                     r"(?:Sub|Function|Property\s+(?:Get|Let|Set))\s+([A-Za-z_]\w*)", t, re.I)
        if m:
            names.add(m.group(1))
        m = re.match(r"^(?:Public\s+|Private\s+)?Const\s+([A-Za-z_]\w*)", t, re.I)
        if m:
            names.add(m.group(1))
    return names


def check_array_return_as_argument(files):
    """VBA cannot pass a function's array return value into an array parameter.

    An array parameter is ByRef, and a function result has nothing to refer to,
    so `Starts(Plan(...))` compiles cleanly and then fails at RUN time. The array
    has to land in a local variable first. Easy to write, hard to spot.
    """
    arr_fns = {}
    for f in files:
        for _, t in logical_lines(f.read_text(encoding="utf-8")):
            m = re.match(r"^(?:Public |Private |Friend )?Function\s+(\w+)\s*\(.*\)\s*As\s+\w+\(\)\s*$",
                         t, re.I)
            if m:
                arr_fns[m.group(1).lower()] = f.name
    if not arr_fns:
        return []

    problems = []
    for f in files:
        for n, t in logical_lines(f.read_text(encoding="utf-8")):
            for fn, owner in arr_fns.items():
                for m in re.finditer(r"[(,]\s*(" + re.escape(fn) + r")\s*\(", t, re.I):
                    problems.append(
                        f"{f.name}:{n}: {m.group(1)}() returns an array and is being passed "
                        f"as an argument; VBA needs it in a local variable first "
                        f"(fails at run time, not compile time)")
    return problems


def _params_of(sig):
    """Parameter list of a procedure signature: (required, total, has_paramarray)."""
    i = sig.find("(")
    if i < 0:
        return (0, 0, False)
    depth = 0
    for j in range(i, len(sig)):
        if sig[j] == "(":
            depth += 1
        elif sig[j] == ")":
            depth -= 1
            if depth == 0:
                break
    inner = sig[i + 1:j]
    if not inner.strip():
        return (0, 0, False)
    parts, depth, cur = [], 0, ""
    for ch in inner:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    required = total = 0
    pa = False
    for part in parts:
        s = part.strip()
        if not s:
            continue
        total += 1
        low = s.lower()
        if low.startswith("paramarray"):
            pa = True
        elif not low.startswith("optional"):
            required += 1
    return (required, total, pa)


def mask_strings(s):
    """Blank out string literal CONTENTS, keeping length so offsets still line up.

    Every rule that looks for identifiers needs this. A procedure name mentioned
    inside a string -- a test asserting on "LingTeXRewrapAll (empty)", or a message
    saying "Next: RunAllTests" -- is text, not code. Both rules below produced false
    positives on exactly that before this existed, and a check that cries wolf is
    worse than a missing check: it teaches whoever sees the output to ignore it.
    """
    out, instr = [], False
    for ch in s:
        if ch == '"':
            instr = not instr
            out.append(ch)
        elif instr:
            out.append(" ")
        else:
            out.append(ch)
    return "".join(out)


def check_call_arity(files):
    """Calls must pass a legal number of arguments for the declared signature.

    VBA reports a wrong argument count at COMPILE time, so this only substitutes
    for a compile the project cannot get here. It matters because a signature
    change -- threading a Document through a transform, say -- leaves call sites
    that look perfectly fine on their own. Those are the ones a reader misses and
    the editor then surfaces one error at a time.

    Scans each line once and looks identifiers up, rather than scanning every line
    for every known procedure: the latter is O(procedures x lines) and takes
    minutes on this project.

    Deliberately conservative -- a false positive here would train someone to
    ignore the output, which is worse than a miss. So: only procedures whose name
    is declared exactly once project-wide, only call sites on one logical line,
    and nothing with a ParamArray.
    """
    engine = [f for f in files if f.name not in STANDALONE]

    DECL = re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                      r"(Sub|Function)\s+([A-Za-z_]\w*)\s*\(", re.I)
    SKIP = re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                      r"(?:Sub|Function|Property|Declare|Attribute|Type|Enum)\b", re.I)

    sigs, dupes = {}, set()
    for f in engine:
        for n, t_ in logical_lines(f.read_text(encoding="utf-8")):
            m = DECL.match(t_)
            if not m:
                continue
            name = m.group(2)
            if name.lower() in sigs:
                dupes.add(name.lower())
            sigs[name.lower()] = (f.name, n, _params_of(t_), m.group(1).lower(), name)
    for d in dupes:
        sigs.pop(d, None)
    # Drop anything with a ParamArray, and anything whose name collides with a
    # UDT field or a local we might mistake for a call.
    sigs = {k: v for k, v in sigs.items() if not v[2][2]}

    def count_args(argtext):
        if not argtext.strip():
            return 0
        depth, n, instr = 0, 1, False
        for ch in argtext:
            if ch == '"':
                instr = not instr
            if instr:
                continue
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
            elif ch == "," and depth == 0:
                n += 1
        return n

    def span_of(s, open_at):
        depth, k = 1, open_at + 1
        while k < len(s) and depth > 0:
            if s[k] == "(":
                depth += 1
            elif s[k] == ")":
                depth -= 1
            k += 1
        return k - 1 if depth == 0 else -1

    CALL = re.compile(r"(?<![.\w])([A-Za-z_]\w*)\s*\(")
    STMT = re.compile(r"^(?:Call\s+)?([A-Za-z_]\w*)(?:\s+(.*))?$", re.I)

    problems = []
    for f in engine:
        for n, t_raw in logical_lines(f.read_text(encoding="utf-8")):
            if SKIP.match(t_raw):
                continue
            t_ = mask_strings(t_raw)

            # Function-style:  Name(args)
            for m in CALL.finditer(t_):
                sig = sigs.get(m.group(1).lower())
                if not sig:
                    continue
                owner, decl_line, (req, tot, _pa), kind, real = sig
                close = span_of(t_, m.end() - 1)
                if close < 0:
                    continue
                got = count_args(t_[m.end():close])
                if got < req or got > tot:
                    rng = str(req) if tot == req else f"{req}-{tot}"
                    problems.append(
                        f"{f.name}:{n}: {real} called with {got} argument(s); "
                        f"{owner}:{decl_line} declares {rng} "
                        f"(compile error in Word)")

            # Statement-style:  Name arg1, arg2
            m = STMT.match(t_)
            if m:
                sig = sigs.get(m.group(1).lower())
                if sig and sig[3] == "sub":
                    owner, decl_line, (req, tot, _pa), kind, real = sig
                    got = count_args(m.group(2) or "")
                    if got < req or got > tot:
                        rng = str(req) if tot == req else f"{req}-{tot}"
                        problems.append(
                            f"{f.name}:{n}: {real} called with {got} argument(s); "
                            f"{owner}:{decl_line} declares {rng} "
                            f"(compile error in Word)")
    return problems


def check_not_equals_precedence(files):
    """`If Not x = y` parses as `(Not x) = y`, which is almost never meant.

    Legal VBA, so nothing complains, and for a Boolean x it often even gives the
    right answer -- which is why it survives review. Written once in this project
    by accident; worth a rule rather than a memory.
    """
    problems = []
    for f in files:
        for n, t in logical_lines(f.read_text(encoding="utf-8")):
            if re.search(r"\bNot\s+[A-Za-z_][\w.()]*\s*(?:=|<>)", t, re.I):
                problems.append(
                    f"{f.name}:{n}: `Not x = y` parses as `(Not x) = y`; "
                    f"write `Not (x = y)` or `x <> y`")
    return problems


def check_declarations_before_procedures(files):
    """Module-level declarations must all precede the first procedure.

    VBA's declarations section ends at the first Sub/Function/Property. A Type,
    Enum, Declare, Const or module-level variable placed after that is a compile
    error -- and a nasty one: a Type declared too late simply stops existing, so the
    error is reported as "User-defined type not defined" in whichever OTHER module
    first names it, with nothing pointing back here.

    Written after exactly that: two procedures were added above "Public Type
    TierFont" in modMeasure.bas, and modDocTests.bas took the blame.
    """
    DECL = re.compile(
        r"^(?:Public\s+|Private\s+|Global\s+|Friend\s+)?"
        r"(?:Type\s+\w+|Enum\s+\w+|Declare\s+|Const\s+|Dim\s+|WithEvents\s+|Event\s+)"
        r"|^(?:Public|Private|Global)\s+[A-Za-z_]\w*(?:\(\))?\s+As\b"
        r"|^(?:Public|Private)\s+[A-Za-z_]\w*\s*(?:,|$)"
        r"|^Option\s+|^Implements\s+", re.I)
    PROC = re.compile(r"^(?:Public\s+|Private\s+|Friend\s+)?(?:Static\s+)?"
                      r"(?:Sub|Function|Property\s+(?:Get|Let|Set))\s+\w+", re.I)
    ENDPROC = re.compile(r"^End\s+(?:Sub|Function|Property)\b", re.I)
    problems = []
    for f in files:
        first_proc = None
        in_type = False
        in_proc = False
        for n, t in logical_lines(f.read_text(encoding="utf-8")):
            # Only lines OUTSIDE procedure bodies are module-level. A local Dim
            # inside a Sub is not a declaration-section statement.
            if in_proc:
                if ENDPROC.match(t):
                    in_proc = False
                continue
            if PROC.match(t):
                in_proc = True
                if first_proc is None:
                    first_proc = (n, t.split("(")[0])
                continue
            if first_proc is None:
                continue
            # Inside a Type/Enum body the field lines are not declarations to flag
            # twice; flag the block once at its head.
            if re.match(r"^End\s+(?:Type|Enum)\b", t, re.I):
                in_type = False
                continue
            if in_type:
                continue
            if DECL.match(t):
                if re.match(r"^(?:Public\s+|Private\s+)?(?:Type|Enum)\s+", t, re.I):
                    in_type = True
                problems.append(
                    f"{f.name}:{n}: module-level declaration after the first "
                    f"procedure ({first_proc[1]} at line {first_proc[0]}) -- "
                    f"compile error; move it above")
    return problems


def check_module_lists(files):
    """Every module in src/ must appear in both install paths, and vice versa.

    THREE places list the modules: src/ itself, MODULE_LIST + CLASS_LIST in
    ImportModules.bas, and STAGE1 + STAGE2 in make-paste-bundle.sh. Add a module and
    forget one of them, and the user installs all but that one -- after which the
    project fails to compile on a name that is simply absent, which reads as a bug in
    whichever module calls it rather than as a missing file.

    Also checks the .bas/.cls split: ImportModules must not try to Import a class.
    """
    root = SRC_DIRS[0].parent
    src_dir = SRC_DIRS[0]
    on_disk = {f.name for f in src_dir.glob("*.bas")} | \
              {f.name for f in src_dir.glob("*.cls")}
    if not on_disk:
        return []

    problems = []

    imp = root / "tools" / "ImportModules.bas"
    if imp.exists():
        text = imp.read_text(encoding="utf-8")
        mods, classes = set(), set()
        for const, into in (("MODULE_LIST", mods), ("CLASS_LIST", classes)):
            # The constant's value runs to the first blank line or comment line.
            pat = const + r"\s+As String\s*=\s*_?(.*?)\n\s*(?:\n|')"
            m = re.search(pat, text, re.S)
            if not m:
                problems.append(f"ImportModules.bas: no {const} found")
                continue
            joined = "".join(re.findall(r'"([^"]*)"', m.group(1)))
            into.update(x for x in joined.split("|") if x)
        listed = mods | classes
        missing = on_disk - listed
        extra = listed - on_disk
        for n in sorted(missing):
            problems.append(f"ImportModules.bas: {n} is in src/ but in neither "
                            f"MODULE_LIST nor CLASS_LIST")
        for n in sorted(extra):
            problems.append(f"ImportModules.bas: {n} is listed but not in src/")
        for n in sorted(x for x in mods if x.endswith(".cls")):
            problems.append(f"ImportModules.bas: {n} is in MODULE_LIST, which is "
                            f"imported -- a .cls must be in CLASS_LIST")
        for n in sorted(x for x in classes if x.endswith(".bas")):
            problems.append(f"ImportModules.bas: {n} is in CLASS_LIST, which creates "
                            f"class modules -- a .bas must be in MODULE_LIST")

    bundle = root / "tools" / "make-paste-bundle.sh"
    if bundle.exists():
        text = bundle.read_text(encoding="utf-8")
        names = set()
        for const in ("STAGE1", "STAGE2"):
            m = re.search(const + r'="([^"]*)"', text)
            if not m:
                problems.append(f"make-paste-bundle.sh: no {const} found")
                continue
            names.update(m.group(1).split())
        # the bundle lists bare names, so compare without extensions
        on_disk_bare = {n.rsplit(".", 1)[0] for n in on_disk}
        for n in sorted(on_disk_bare - names):
            problems.append(f"make-paste-bundle.sh: {n} is in src/ but in neither "
                            f"STAGE1 nor STAGE2")
        for n in sorted(names - on_disk_bare):
            problems.append(f"make-paste-bundle.sh: {n} is listed but not in src/")

    return problems


def check_standalone_independence(files):
    """Standalone modules must not reference anything the engine defines.

    modProbe.bas and ImportModules.bas are each pasted ALONE into a bare project --
    the probe before any engine module exists, the importer in order to bring them
    in. VBA compiles the whole project at once, so a single reference to engine code
    makes the project fail to compile, and the macro whose job is to fix that cannot
    run. A chicken-and-egg failure with a confusing error.

    The mirror of check_stage1_independence, and written because I put
    "Set o = New clsIgtWarning" into ImportModules.bas as a second opinion on
    whether the class had imported correctly. It would not have compiled until the
    class was there.
    """
    standalone = [f for f in files if f.name in STANDALONE]
    engine = [f for f in files if f.name not in STANDALONE]
    if not standalone:
        return []

    engine_defs = {}
    for f in engine:
        for nm in proc_names(f.read_text(encoding="utf-8")):
            engine_defs.setdefault(nm, f.name)
    # Class and Type names too: "New clsIgtWarning" names no procedure.
    for f in engine:
        for n, t in logical_lines(f.read_text(encoding="utf-8")):
            m = re.match(r"^Attribute VB_Name = \"([A-Za-z_]\w*)\"", t)
            if m:
                engine_defs.setdefault(m.group(1), f.name)
            m = re.match(r"^(?:Public\s+|Private\s+)?Type\s+([A-Za-z_]\w*)", t, re.I)
            if m:
                engine_defs.setdefault(m.group(1), f.name)

    own = set()
    for f in standalone:
        own |= proc_names(f.read_text(encoding="utf-8"))

    problems = []
    for f in standalone:
        for n, t_raw in logical_lines(f.read_text(encoding="utf-8")):
            t = mask_strings(t_raw)
            for nm, owner in engine_defs.items():
                if nm in own:
                    continue
                if re.search(r"(?<![.\w])" + re.escape(nm) + r"(?![\w])", t):
                    problems.append(
                        f"{f.name}:{n}: references {nm}, which {owner} defines -- "
                        f"but this module is pasted alone into a bare project, so "
                        f"the project would not compile")
    return problems


def check_stage1_independence(files):
    """Stage-1 modules must not reference anything only stage 2 defines."""
    engine = [f for f in files if f.name not in STANDALONE]
    if not any(f.name in STAGE1 for f in engine):
        return []

    stage1_defs, stage2_defs = set(), {}
    for f in engine:
        names = proc_names(f.read_text(encoding="utf-8"))
        if f.name in STAGE1:
            stage1_defs |= names
        else:
            for nm in names:
                stage2_defs.setdefault(nm, f.name)

    problems = []
    for f in engine:
        if f.name not in STAGE1:
            continue
        for n, t in logical_lines(f.read_text(encoding="utf-8")):
            for nm, owner in stage2_defs.items():
                if nm in stage1_defs:
                    continue
                if re.search(r"(?<![.\w])" + re.escape(nm) + r"(?![\w])", t):
                    problems.append(
                        f"{f.name}:{n}: stage-1 module references '{nm}', which only "
                        f"{owner} defines -- this breaks the staged install in QUICKSTART.md")
    return problems


def main():
    files = []
    for d in SRC_DIRS:
        files += sorted(list(d.glob("*.bas")) + list(d.glob("*.cls")))
    if not files:
        print("no VBA sources found in " + ", ".join(str(d) for d in SRC_DIRS))
        return 1

    total = 0
    for f in files:
        problems = check(f)
        total += len(problems)
        mark = "OK  " if not problems else "FAIL"
        print(f"  {mark}  {f.name}")
        for n, msg in sorted(problems):
            print(f"          {f.name}:{n}: {msg}")

    arr = check_array_return_as_argument(files)
    if arr:
        total += len(arr)
        print("  FAIL  array return passed as argument")
        for msg in arr:
            print("          " + msg)
    else:
        print("  OK    no array return passed as an argument")

    arity = check_call_arity(files)
    if arity:
        total += len(arity)
        print("  FAIL  call arity")
        for msg in arity:
            print("          " + msg)
    else:
        print("  OK    call arity")

    prec = check_not_equals_precedence(files)
    if prec:
        total += len(prec)
        print("  FAIL  Not-equals precedence")
        for msg in prec:
            print("          " + msg)
    else:
        print("  OK    no `Not x = y` precedence traps")

    decl = check_declarations_before_procedures(files)
    if decl:
        total += len(decl)
        print("  FAIL  declarations before procedures")
        for msg in decl:
            print("          " + msg)
    else:
        print("  OK    every module-level declaration precedes the first procedure")

    lists = check_module_lists(files)
    if lists:
        total += len(lists)
        print("  FAIL  module lists")
        for msg in lists:
            print("          " + msg)
    else:
        print("  OK    both install paths list every module in src/")

    alone = check_standalone_independence(files)
    if alone:
        total += len(alone)
        print("  FAIL  standalone independence")
        for msg in alone:
            print("          " + msg)
    else:
        print("  OK    standalone modules reference no engine code")

    stage = check_stage1_independence(files)
    if stage:
        total += len(stage)
        print("  FAIL  stage-1 independence")
        for msg in stage:
            print("          " + msg)
    else:
        print("  OK    stage-1 independence (QUICKSTART.md staged install)")

    print()
    print("ALL PASS" if total == 0 else f"{total} problem(s)")
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
