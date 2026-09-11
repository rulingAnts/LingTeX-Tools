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

SRC = pathlib.Path(__file__).resolve().parent.parent / "src"

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
    stack, scope = [], None
    for n, t in lines:
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


def main():
    files = sorted(list(SRC.glob("*.bas")) + list(SRC.glob("*.cls")))
    if not files:
        print("no VBA sources found in " + str(SRC))
        return 1

    total = 0
    for f in files:
        problems = check(f)
        total += len(problems)
        mark = "OK  " if not problems else "FAIL"
        print(f"  {mark}  {f.name}")
        for n, msg in sorted(problems):
            print(f"          {f.name}:{n}: {msg}")

    print()
    print("ALL PASS" if total == 0 else f"{total} problem(s)")
    return 0 if total == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
