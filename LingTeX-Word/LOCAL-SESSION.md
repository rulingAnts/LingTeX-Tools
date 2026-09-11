# LingTeX-Word — handoff for a local Claude Code session on the Mac

Paste everything below the line into a new Claude Code session started in
`/Users/Seth/GIT/LingTeX-Tools`. It has what the session needs to iterate on the
VBA without a person in the loop.

---

You are continuing **LingTeX-Word**, a Word add-in in VBA under `LingTeX-Word/`,
on branch `claude/gallant-feynman-6foihb`. Read `LingTeX-Word/QUICKSTART.md` first,
then `LingTeX-Word/README.md`. The state of play is at the end of this note.

## The loop you can run yourself

Word for Mac is on this machine, with the project in
`/Users/Seth/GIT/LingTeX-Tools/LingTeX-Word/LingTeX.docm` (gitignored) and the
bootstrap module `modImport` already pasted into it with `SRC_FOLDER` set. So:

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
- **No `Single` anywhere.** Converting an integer to a `Single` raises run-time
  error 6 on this Mac build, depending on the stack frame. Everything is
  `Double`. The linter does not check this yet; add the rule if you touch it.
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

- `RunAllTests`: **79/79** on Mac Word 16.112 with the `Double` build (`0e7074d`).
- `RunDocTests`: does not compile — **"Compile error: Sub or Function not
  defined"**, surfaced when the runner ran `RunDocTestsToFile`. Five static
  scans (undefined bare calls, cross-module `Private` calls, every name in
  `modLingTeX` and `clsAppEvents` against every definition, rare built-ins) found
  nothing, so the offending statement has a shape those scans miss. The user may
  have sent the highlighted line; if not, bisect as above. Find it, add the
  linter rule for its class, sweep for more of the same class, then run.
- Before the `Double` change, `RunDocTests` did run and crashed with Overflow in
  three sections (styles, settings, measure) — every crash a `Single`
  conversion. Those should now pass; anything else that fails is new information.
- A background sweep for further compile errors was running in the remote
  session; its results, if any, will arrive as a commit on the branch.
- Then: the by-hand checks in `TESTING.md`, `SaveAsTemplate` +
  `tools/build-dotm.sh` + `tools/check-dotm.sh`, then packaging (see
  `/root/.claude/plans/` is not on this machine — the plan is summarised in
  QUICKSTART's *Status* and README's *Roadmap*).
- Task for later, not now: remove the stage-1 `Single` diagnostics from
  `modTests` (`TypeCheck`, `DiagnoseWrap`; keep `MicroDiagnose` as the
  reproduction) and do a health pass — only once `RunDocTests` is green.
