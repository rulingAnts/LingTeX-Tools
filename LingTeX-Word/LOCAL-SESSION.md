# LingTeX-Word — handoff for a local Claude Code session on the Mac

Paste everything below the line into a new Claude Code session started in
`/Users/Seth/GIT/LingTeX-Tools`. It has what the session needs to iterate on the
VBA without a person in the loop.

---

You are continuing **LingTeX-Word**, a Word add-in in VBA under `LingTeX-Word/`,
on branch `claude/gallant-feynman-6foihb`. Read `LingTeX-Word/QUICKSTART.md` first,
then `LingTeX-Word/README.md`. The state of play is at the end of this note.

## The loop you can run yourself

> **How it is actually run (2026-09-12):** Seth runs the runner, on the Mac and on
> the Windows VM, and it commits and pushes each platform's reports; you `git pull`
> and read `LingTeX-Word/LingTeX-Word-reports/*.mac.txt` / `*.win.txt`. Do not
> drive Word with screenshots or the desktop tools -- slower, and it heats the
> machine. The description below is still how the runner works.

Word for Mac is on this machine, with the project in
`/Users/Seth/GIT/LingTeX-Tools/LingTeX-Word/LingTeX.docm` (gitignored) and the
bootstrap module `modImport` already pasted into it (it reads `src/` beside the
document). So:

```
python3 LingTeX-Word/tools/vba-lint.py          # the substitute compiler; must be ALL PASS first
sh LingTeX-Word/tools/run-in-word.sh --no-pull  # import from src/, RunAllTests, RunDocTests
```

`--no-pull` because you are running on your own uncommitted edits. The runner
re-imports every module from `src/` into the document, runs both suites, prints
the reports (`LingTeX-Word/LingTeX-Word-reports/*.txt`), and exits non-zero on
any `FAIL`, `CRASH` or import problem. Dialogs Word raises — compile errors,
untrapped run-time errors, the macro-security prompt — are read through System
Events, printed, and dismissed, so a compile error arrives as text. Its line is
not in that text: the VBA editor highlights it, which you cannot see. To
localise one statically, use the analyses in `tools/vba-lint.py` as a starting
point; to localise one dynamically, add a temporary `Public Sub Touch(): End Sub`
to a suspect module and run it alone with `osascript -e 'tell application
"Microsoft Word" to run VB macro macro name "Touch"'` — a module that does not
compile fails there, which bisects to the module; then bisect inside it.

If dialogs are not being read, the terminal lacks Accessibility permission
(System Settings → Privacy & Security → Accessibility); say so and stop.

Edit → lint → run → read → fix. Commit on the branch when a run is better than
the last, push, and leave the report in the commit message. Do not create pull
requests.

## The rules, all of which were learned the hard way

- **Never change behaviour that `RunAllTests` proves.** The six stage-1 modules
  (`modFlexParse`, `modIgtModel`, `modLeipzig`, `modWrap`, `modTests`,
  `clsIgtWarning`) pass 79 checks on both platforms. If a fix needs them touched,
  re-run `RunAllTests` and keep 79/79. Prefer fixing the stage-2 side.
- **Every `Debug.Print` is followed by `SettleDebugPrint 0#`.** On this Mac build
  a `Debug.Print` arms run-time error 6 in the next floating-point assignment or
  comparison, in that procedure or its caller; any call in between clears it.
  The linter enforces the rule; `DebugPrintDiagnose` reproduces the fault.
- **No `Single` anywhere.** It was blamed for the above before the cause was
  found; `Double` stays because the JavaScript reference uses it. The linter
  checks this now.
- **Word enumeration constants must exist on Mac.** `wdStyleTableGrid` does not,
  and VBA compiles a procedure only when it is first reached, so a bad constant
  is a compile-error dialog half-way through a run. Prefer names to enums for
  built-in styles; the linter keeps an allowlist of the constants in use.
- **The VBA editor's dialogs are invisible to System Events.** The runner can
  only see the editor's `[break]` window title; a person reads the dialog and
  the highlighted line, clicks OK, then *Run → Reset*. Seth runs the runner and
  pastes its output; do not drive Word with screenshots — it is slower and hot.
- **Every module-level declaration precedes the first procedure.** A `Type`,
  `Const` or variable after a `Sub` silently does not exist and the error shows
  up in a different module. The linter checks this.
- **Pure ASCII, CRLF** (`.gitattributes` enforces CRLF; non-ASCII via `ChrW`).
- **Class modules are never imported with `Import`**; the bootstrap creates them
  explicitly. Do not touch `tools/ImportModules.bas` casually — it is pasted by
  hand into the document, so any change there means the user re-pastes it.
- Every user-facing message goes through `Report`/`Confirm` in `modLingTeX`, never
  `MsgBox` — that is what lets tests drive the commands.
- When you find one class of error, sweep every unproven module for the same class
  before handing anything back, rather than letting Word report them one at a time.
- Commit messages: say what broke, why, and what proves the fix. Attribution
  footer per this session's own instructions.

## State of play

- **Stage 2 is proven on both platforms**: `RunAllTests` 79/79 and `RunDocTests`
  224/224 on Mac Word 16.112 and on Word for Windows. The reports are committed
  per platform under `LingTeX-Word/LingTeX-Word-reports/` (`*.mac.txt`,
  `*.win.txt`); the runners commit and push their own platform's after a run.
- Three things the first runs taught, now rules in `vba-lint.py`: a `Debug.Print`
  poisons the next floating-point statement on Mac (every `Debug.Print` is
  followed by `SettleDebugPrint`); a `_` continuation in a `.cls` breaks when the
  bootstrap installs it on Mac (none allowed in class modules); and `wd*`
  constants must be on the allowlist, because Mac Word's type library lacks some
  (`wdStyleTableGrid` was one). VBA compiles a procedure when it is first
  *reached*, so an error in a late-called procedure surfaces mid-run; the linter
  is the only project-wide compile there is. `run-in-word.sh --macro NAME` runs
  one macro, for bisecting.
- The VBA editor's own dialogs are invisible to System Events; the runner
  watches the editor's window title for `[break]` instead, before and after
  every macro, and says what to do.
- **Next gate: `TESTING.md` section 3 by hand** — a real FLEx paste, the margin
  round trip (narrow → columns push down; widen → they come back), the seven
  ribbon buttons once the template exists. Then `SaveAsTemplate`,
  `tools/build-dotm.sh`, `tools/check-dotm.sh`; then packaging (NSIS, the
  uncompiled AppleScript installer, the `word-addin` CI job, the website card).
- Later, not now: a health/efficiency pass over the engine, keeping both suites
  green on both platforms.
