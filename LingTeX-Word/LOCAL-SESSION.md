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

- **Stage 1 and stage 2 pass on both platforms** (2026-09-12): `RunAllTests`
  79/79 and `RunDocTests` 224/224 on Mac Word 16.112 and on Word for Windows.
  Reports in `LingTeX-Word-reports/*.mac.txt` and `*.win.txt`.
- **The by-hand pass (`TESTING.md` section 3, Mac) is under way**, driven from
  the checklist artifact (marks readable with `read_db`, collection `checks`).
  First pass: 3a, 3b, 3d green; 3c mostly. Findings, all addressed in the
  commit after a8bcd69 and awaiting a Word run on both platforms:
  - **Undo was not single-step**: every drawing step listed separately after
    the custom record's label. Hypothesis: the hidden measuring document's
    changes close the record. `BeginUndo` now only names the record;
    `StartPendingUndo` opens it at the first change to the user's document,
    after all measuring; `RewrapDocument` warms the cache first. If Seth still
    sees several steps, plan B is to draw in the scratch document and transplant
    with one `FormattedText` assignment.
  - An over-wide form ran off the page: `CapColumnWidths` in `modRender`.
  - Direct font sizing was lost on re-wrap (by design); the LingTeX paragraph
    styles now inherit their SIZE from Normal (name still pinned).
  - Grammatical glosses get a full-size first letter (`Erg`, `3Sg`) -- Seth's
    preference; setting `GramGlossInitialCap`, default True.
  - Settings are zero-argument commands now (`LingTeXAlignByWord` etc.).
  - AutoCorrect's sentence/table-cell capitalisation is suppressed while the
    selection is inside an example (`clsAppEvents`).
  - The sample's `:` is the IPA length mark `ː`; `AttachPunct` includes it.
  - **Re-wrap-all deleted the second of two examples** separated by one
    empty paragraph: the paragraph inherited LingTeX Free, was absorbed as a
    translation and deleted, the tables merged, `tbl.Delete` took both. Now an
    empty paragraph ends an example (`IsTranslationParagraph`), no deletion
    removes a paragraph mark that precedes a table, and LingTeX Free's next
    paragraph style is Normal. Doc-test section `adjacent` proves both layouts.
- **Numbering is built** (2026-09-12, reworked to Seth's second call): the
  example is the body of a numbered paragraph ABOVE the table -- an empty line
  in the LingTeX Example style, numbered by the LingTeX Example Number list
  style (Word's own numbering, never in a cell). Table and translation are
  indented to that line's text position; re-wrap leaves the line alone and
  lays the example out to its current indent, bullets and outline levels
  included; DeleteExample removes all three parts. Doc-test section
  `numbering`. Unproven in Word until the next run.
- Next: Seth re-runs both runners (expect 79 and about 231), then continues the
  by-hand pass from 3c/3e/3f. Then `SaveAsTemplate` + `tools/build-dotm.sh` +
  `tools/check-dotm.sh`, then packaging.
- Later, wanted by Seth: a settings interface (gaps, styles) -- Phase 2 form.
- Seth wants the ribbon and macros non-template-specific in the end: that is
  what the startup-folder .dotm already is (a global add-in, applying to every
  document regardless of its own template); packaging installs it there.
  README, Phase 3.
- Later, per Seth: convert-table lets the user mark bottom rows as free
  translations (today: a row merged to one cell is the translation, and the
  command now says so when none is found), and a table-from-text step before
  it (space-separated lines, one per tier) -- possibly instead of the
  data-sheet form. README, *Later*.
- Later, per Seth: toggle an existing example between word- and
  morpheme-aligned in place -- split every boundary / merge every continuation
  column, then redraw; and in bulk over a selection (Outline view selects a
  section) or the whole document (README, *Later*).
- Later, per Seth: example numbers, headings before, captions after, list
  numbering around, sub-numbering across a multi-block paste; and keep the
  language tag on a second free translation (dropped today). README, *Later*.
- Later, per Seth: revisit the source-agnostic input model for Toolbox/SFM,
  Excel/Numbers pastes and the Phase 2 hand-typed data sheet -- the FLEx-shaped
  assumptions are listed in README, *Later*. FieldWorks data first.
- Later, wanted by Seth: every spacing a user might set (before/after an
  example, between tiers, rows-to-translation, plus the three existing gaps)
  behind one interface; and inserting every example of a multi-block FLEx
  paste (the parser already returns them all; the insert takes the first).
  Both in README, *Later*.
- Later, wanted by Seth: re-wrap an example automatically when it is edited.
  Plan (README, *Later*): make the selection-change hook change-aware via a
  text fingerprint taken on entering, so it fires once on leaving an edited
  example and never otherwise; then it can default to on.
- **The code lives in a template in Word's STARTUP folder** (2026-09-12, Seth's
  call): loaded as a global add-in, so every document has the commands, the
  ribbon, the shortcuts and AutoExec. `SetDevRoot` (modImport) stores the
  clone's LingTeX-Word folder in the template as a document variable;
  `SrcFolder` and both report folders read it. The runners do not open a
  `.dotm`, they run the macros in the loaded template (and make a document if
  none is open). Neither the `.docm` nor `LingTeX.dotm` is committed.
- Reports are committed, one file per platform, by the runners themselves.
