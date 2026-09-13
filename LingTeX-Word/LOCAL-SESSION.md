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

- **Alignment is measured** (2026-09-14, Seth's idea): AlignRowsToFirst at
  the end of DrawExample asks Word (Information, page x) where every row's
  first content cell starts and nudges each row's LeftIndent by its error
  (later wrap lines allow for ContIndent), then moves the translation
  paragraphs to the first row's content. Bounded (skips unreadable
  positions, disbelieves > 72pt); row 1 never moves, so ExampleIndent is
  stable. Doc-test `rows` is now the check that it works, not a guess.
- **Spacing defaults, percentages, Restore Defaults, row geometry**
  (2026-09-14, Seth): every spacing is a document setting with a numeric
  default now (Before 0, After 3, Right 0, Above 6 = half a line, Between 0;
  only Left stays optional); the renderer always writes them, so the LingTeX
  styles' paragraph spacing is not what shows, and contextual spacing is off
  on translation paragraphs so Between is honoured. A box takes "50%" -- a
  percentage of the vernacular style's font size, resolved at draw time
  (SpacingFontSize). The dialog has Restore Defaults (fields only; OK/Apply
  store). The number-cell paragraph is single-spaced (style and paragraph):
  it inherited Normal's multiple and could make row 1 the tallest row.
  Doc-test section `rows` asks Word for the page position of every row's
  first content cell and of the translation (no hanging indent, with
  padding set) and for the row heights (row 1 = row 3) -- Seth saw both
  look wrong; if the section is green, what remains is font substitution
  (a glyph such as the IPA length mark from a fallback font grows its row).
- **The second import could not name the form** (2026-09-14, 06:55 run):
  ImportGroup removed the existing frmLingTeXSettings and ImportOne added a
  new UserForm, and `comp.Name = "frmLingTeXSettings"` raised 50132 -- the
  VBE keeps a removed FORM's name reserved until the file is saved and
  reopened. 14 of 15; modLingTeX and modDocTests (which name the form)
  then failed to compile whole: "Compile error in hidden module" on Settings,
  on every toggle, and in RunDocTests. modImport now REUSES a form that is
  already a form (only its code is replaced), and when a name is refused it
  removes the nameless form, saves the engine and tries once more;
  RemoveStrayForms clears any UserForm1 a failed attempt left. **Seth must
  re-paste modImport again** for this.
- **Left cell padding no longer reads as a hanging indent** (2026-09-14,
  Seth saw it): Word measures Rows.LeftIndent to the table's EDGE and sets
  the text in by the padding, so a padded table put its text a padding right
  of the translation. FillTable now sets the rows at indent - padL (Word's
  own tables do the same), and ExampleIndent adds tbl.LeftPadding back, so
  a re-wrap neither drifts nor doubles it. Assumes Word 2013+ table-indent
  semantics (compatibility mode 15), which every document made in current
  Word has. Continuation is the one spacing MEANT to indent later wrap
  lines; empty keeps them flush.
- **Re-wrap repairs spaces in cells** (2026-09-14, Seth): RewrapTable runs
  FixCellSpaces with the document's replacement character before redrawing,
  as Insert always has. Doc-test section `spacefix`.
- **The Settings dialog** (2026-09-14, Seth's call: a pop-up from Settings,
  not a ribbon tab; the styles just listed, with Modify in Word). It is
  `src/frmLingTeXSettings.frm`, the project's first UserForm: NO controls at
  design time and no .frx -- every control is built in code in
  UserForm_Initialize, the six buttons in WithEvents variables so their
  clicks fire. Show is modal; Modify in Word hides the form with Result =
  "modify" and `LingTeXSettings` opens Word's Style dialog (Dialogs(180)
  .Display) and shows the form again. modImport creates it with
  VBComponents.Add(3) and installs the code like a class's (`FORM_LIST`),
  and checks the MSForms reference. **Seth must re-paste modImport into
  LingTeX-Dev.dotm once** -- the old copy does not know the form, and
  without it TestDialog fails to compile and the engine will not load.
  Doc-test section `dialog` drives the form without showing it. The LingTeX
  Styles tab and its five icons are gone; the spacing settings and
  `SpacingText`/`SetSpacingText` stay as the dialog's back end.
  PROVEN on Mac (2026-09-14, first run): the bootstrap created the form,
  15/15 and Verify all ok, the MSForms reference was there, Settings opened
  the form centred with every control drawn and filled. Two findings from
  that run: (1) "Compile error in hidden module: modStyles" -- MY edit had
  eaten a comment banner and left half a sentence as code; vba-lint now has
  check_no_statements_at_module_level for exactly that. (2) Modify in Word
  opened Word's Style dialog on the paragraph's style, not the selected one
  (Dialogs(180).Name is ignored on Mac): ModifyStyleInWord now selects the
  first text in the style (Find by style) before Display, and restores the
  cursor. UNPROVEN: that selection trick on Mac; Apply behind the dialog;
  Variable.Delete. Stale engine copies in Word's Templates folder and in
  ~/Documents/Custom Office Templates are NOT the engine; do not compile
  those and conclude anything.
- Ribbon: the six settings buttons are toggleButtons (getPressed/onAction,
  onLoad keeps the IRibbonUI; DocumentChange and every setting command call
  RefreshRibbon). Silent on the ribbon; the macro-list commands still report.
  Unproven on Mac (whether getPressed/onLoad callbacks fire there).
- Later (Seth): shortcut tooltips on the ribbon buttons via getScreentip,
  reading the live binding, since the letter differs per machine.
- Shortcuts (2026-09-12, late): MAC WORD'S MODIFIER BITS ARE NOT WINDOWS'S --
  Command 256, Shift 512, Option 2048, Control 4096 (found by a probe macro
  that asked Word to name what it had bound; the probe is deleted, see git
  history around 72a95ef). The set is Command+Option+Shift+letter on Mac,
  Ctrl+Alt+Shift on Windows (unproven there); the installer never takes a
  bound key, and saves the template so the bindings persist. 13/13 on Mac.
- Icons: our own PNGs in src/icons (tools/make-icons.py, Pillow + macOS
  fonts), embedded by build-dotm.sh with a part-level .rels; check-dotm.sh
  guards them. Unproven on Mac (embedded ribbon images from STARTUP).
- **The number is a first column now** (2026-09-12, late): Seth wanted it on
  the vernacular line, not on a line above the table. Every row of a numbered
  example has a number cell as wide as NumberHang; row 1's paragraph is in
  LingTeX Example (linked to the list style); modReadBack.NumberColumns is
  what every reader offsets by. The example's indent is its rows' LeftIndent
  (ExampleIndent), kept by re-wrap; a fresh example takes its paragraph's.
  Legacy number lines migrate on re-wrap (LegacyNumberLineOf). Unproven in
  Word: the numbering doc-test section was rewritten for it (expect a few
  more than 280).
- **The two-template loop works end to end** (2026-09-12 evening): import
  14/14 into the engine as a document, saved, loaded as a global add-in, 79
  and 271/272 -- every numbering check green.
- **FOUND IT (Debug > Compile in the open): both class modules were EMPTY.**
  ReadTextFile ends lines with vbNewLine (CR on Mac) since the double-spacing
  fix; StripVbaMetadata still split on vbCrLf, so a Mac class file was one
  line starting VERSION 1.0 CLASS and was skipped whole. Classes were created
  empty and reported ok, and modLingTeX's mEvents.Attach then failed to
  compile -- as "Compile error in hidden module" in the add-in. Stripper
  normalises newlines now; ImportOne and Verify report an empty class.
  Needs the dev template re-pasted (modImport). The chain of dialogs today
  was all this one bug plus the stale startup copy.
- **The engine loads at Word start only when marked good** (build/engine-ok,
  removed by the runner before a run, written after a clean one; dev
  AutoExec checks it). A broken import can no longer be loaded twice, and
  the repair path (import into the engine opened as a document) never runs
  stale engine code. Needs the dev template re-pasted once (its AutoExec).
- **Fourth run: "Compile error in hidden module: modLingTeX", endlessly.** The
  two-template import WORKED (it wrote modules into the engine and reloaded
  it), and what it imported had never been compiled by Word: the shortcuts
  code (KeyBindings, FindKey, BuildKeyCode, CustomizationContext,
  NormalTemplate, the WdKey constants) or StatusBar -- one of them is not in
  Mac Word's type library. All late-bound now, constants numeric, so the
  worst case is a run-time error in the shortcut command. RULE: anything not
  already proven on Mac goes through an Object, because an add-in's module
  compiles whole at load and a compile error there repeats on every event.
- **Third template run: 50289 again -- from the STALE copy.** The old
  LingTeX.dotm was still in the startup folder beside LingTeX-Dev.dotm, so
  Word loaded both and `run VB macro` found the old modImport first. Renamed
  to .old; install-dev-template.sh now does that itself. The two-template
  sequence is still unproven; next run answers it.
- **A loaded global template's project is protected** (error 50289 on every
  import, 2026-09-12 second template run; it did save itself). So: TWO
  templates. LingTeX-Dev.dotm in the startup folder holds only modImport,
  loads the engine (LingTeX-Word/LingTeX.dotm, in the clone, gitignored) as
  an add-in at Word start, and re-imports it by unloading, opening as a
  document, importing, saving, closing, loading. install-dev-template.sh
  does the file-side setup; Seth makes the dev template in Word once.
  Unproven: AddIns.Add / Installed=False / Documents.Open on Mac in that
  sequence, and whether the ribbon part survives the engine's Save.
- **First template run wrote nothing to the repo** (2026-09-12 17:00): SetDevRoot
  had not been run, so the bootstrap looked for src beside the template,
  imported 0 of 14, and the (old) tests wrote their reports beside the template;
  the runner then committed the deletion of the old Mac reports (guarded now:
  no report, no commit). tools/install-dev-template.sh sets the variable in
  settings.xml with Word quit, injects the ribbon and points the runner --
  the whole step is one command; Seth has still to run it.
- **The ribbon loads on Mac** (2026-09-12, screenshot): LingTeX.dotm in the
  startup folder, injected with add-ribbon.sh, shows the full LingTeX tab over
  a new document -- Interlinear, Layout, Alignment, Settings, Setup, Keys,
  Check, icons and all. Seth stopped there (appointment); next: the runner
  against the template (does the loaded template save itself after the
  import?), Install Shortcuts, then the page from `numbered` onward.
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
- ~~Later, wanted by Seth: a settings interface (gaps, styles) -- Phase 2 form.~~
  Done as the LingTeX Styles tab (2026-09-13), above.
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
- ~~Later, wanted by Seth: every spacing a user might set (before/after an
  example, between tiers, rows-to-translation, plus the three existing gaps)
  behind one interface~~ -- the LingTeX Styles tab (2026-09-13). Still later:
  inserting every example of a multi-block FLEx paste (the parser already
  returns them all; the insert takes the first). README, *Later*.
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
