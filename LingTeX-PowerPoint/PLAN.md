# LingTeX-PowerPoint: plan

LingTeX-Word's Interlinear tab, for PowerPoint. The idea: paste from FLEx and get an aligned interlinear example that wraps inside its own frame and re-wraps when the frame changes.

Status (2026-09-28, evening): **the suite has run** -- 97 of 97 under CR LF and LF clipboards, once the Full Disk Access grant reached the right bundle ("Claude Code", not "Claude"; memory `claude-code-tcc-principal`). Two compile errors the rig could not see (the VBA editor is invisible to accessibility on macOS 27) led to `tools/check-names.py`, which runs before every import. Probe round 7 (clipboard save and restore) and round 8 (the undo count, measured by the rig with nobody at the keyboard) are done; round 8 overturned the per-write undo premise -- **one undo entry per macro run** -- so Insert and re-wrap now compose IN PLACE with no clipboard traffic (still 97/97). Step 3 (commands, settings, the resize guard) started 2026-09-29, below. Next: the ribbon, the `.ppam` build, the installer, the guide; then issues #8-#10 in the shared layer.

## Why it differs from Word

- **There is no text flow.** A PowerPoint object has its own frame on the slide, so an example's wrap width is its frame's width, not the page's.
- **A table can't be the frame.** A PowerPoint table is one grid: every row shares the same column widths (confirmed below). Word gives each wrap line its own cell widths, and that is what lets an example wrap. A table also can't be grouped with another shape.
- **Nothing to identify an example by.** There are no paragraph styles, so the example's structure and its settings go in `Shape.Tags` and `Presentation.Tags`. Tags survive copy and paste.

## Design

- **One text box is the frame.**
  - Each wrap line is one paragraph per tier (words, glosses and so on).
  - That line's columns are lined up with tab stops set for those paragraphs, at measured positions.
  - The number hangs in a left indent.
  - The free translation is a paragraph below.
  - The box's width is the wrap width.
- **Fallback:** grouped text boxes with an invisible frame rectangle. Nothing so far calls for it.
- **Re-wrap triggers:**
  - the ribbon, on leaving the example, and on save, as in Word;
  - also after the frame is resized, if PowerPoint's resize event (`AfterShapeSizeChange`) fires (probe 2).

## What carries over from LingTeX-Word

These modules never touch Word's objects: `modFlexParse`, `modIgtModel`, `modLeipzig` and `modWrap`, plus the algorithm tests in `modTests`. Both builds should import one copy of them, so a parser fix lands in both add-ins.

## Known limits

- **No custom keyboard shortcuts.** Assigning keys from a macro is Word-only (`KeyBindings`).
- **Undo: one entry per macro run, unnamed.** Probe round 8 (2026-09-28, measured by the rig): everything a macro run writes -- seven writes, or the dozens of an in-place composition -- is ONE undo entry, in a new and in an existing presentation; one Undo takes it all back and leaves "Can't Undo". PowerPoint labels it after the last write ("Undo Typing", "Undo Format Object"); there is no Word-style `UndoRecord` to name it "Undo Re-wrap". Round 4's per-write reading (a manual Cmd+Z on 2026-09-15) is superseded; confirm round 8 from the ribbon once the add-in exists.
- **Numbering is plain text**, renumbered by a command.
- **Installing on the Mac:** copy the add-in (`.ppam`) into Office's Startup folder for PowerPoint, as Word's template goes into Word's (confirmed below). On Windows, PowerPoint registers add-ins in the registry instead.
- **PowerPoint for Mac won't save an add-in from VBA** (below). The build saves a `.pptm` and changes its content type, as LingTeX-Word's build does for its template.
- **At most 32 tab stops per paragraph**, so at most 33 columns in one wrap line.

## Dev rig

`tools/modLingTeXDev.bas` is pasted once into `LingTeX-PowerPoint-Dev.pptm`. After that, `tools/run-in-powerpoint.sh` does the rest:

1. copies the modules into PowerPoint's own Documents folder, so there's no file-access prompt;
2. refreshes `build/shared` from LingTeX-Word (`tools/stage-shared.sh`) and imports everything in MODULES;
3. runs the probe (default), the tests (`--tests`) or named macros;
4. copies the reports into `LingTeX-PowerPoint-reports/`.

See the header of `modLingTeXDev.bas` for setup. First full run: 2026-09-15 (ping, import, probe).

Two fixes from that run:

- **Checking for the open presentation.** Reading `name of p` inside an AppleScript loop fails (-2763), so the runner asks for `name of every presentation` instead.
- **The clipboard sample.** `pbcopy` needs a UTF-8 locale, or "ñ" arrives as "√±".

## Where it is developed

- **Develop and test on the Mac first; smoke-test on Windows later.** Mac VBA is the less forgiving environment: constants missing from the type library, the sandbox, and save formats that don't exist there. Code that works on the Mac is more likely to work on both.
- **Nothing in the build or the dev rig should need Windows.** For example, the add-in is made by changing a `.pptm`'s content type, not by Windows PowerPoint's SaveAs.

## Steps

1. **Probe.** Six rounds done (below). Round 6 settled the last questions: PowerPoint has no `UndoRecord`, one paste leaves the example's box alone, and VBA on the Mac has no save format for a macro-enabled presentation or an add-in.
2. **Core.** Insert, re-wrap and read back an example.
3. **Commands.** Events, settings, numbering, Check Glossing, Split and Merge Columns.
4. **Tests.** Tests that run inside PowerPoint, on the Mac and on Windows.
5. **Release.** The add-in build, installers, guide and site.

## Step 2: core (started 2026-09-28)

What exists, in `src/`, all imported by the rig and none of it yet run in PowerPoint:

- **`modPptClipboard`** -- `ReadClipboardText` reads the clipboard the one way that works here (paste into a text box in a windowless scratch presentation, probe rounds 2 and 3) and returns the text RAW; `ReadClipboardForParser` is that plus one call to `NormalizeClipboardText`; `BreakCounts` and `EscapeBreaks` for reports.
- **`modPptFormat`** -- how one cell goes into a `TextRange2`: the forms tier italic; on meta-language tiers the grammatical segments (shared `SplitGlossSegments` + `IsGramGloss`) lowercased and set in small capitals, as `modRender.WriteCellText` does in Word. Used by drawing and by measuring, so the two can never disagree. `TierTakesSmallCaps` and `SmallCapsForm` are copies of modRender's five-liners until those move to a shared module.
- **`modPptMeasure`** -- `MeasureExample(ex, fonts(), widths())` fills `widths(tier, column)` for `modWrap.ColumnWidths`; `MeasureText` writes the cell into a wide, non-wrapping box in a windowless scratch presentation with `WriteCell` and reads `Characters(1, n).BoundWidth` (probe: "neighbor-F" at 20 pt = 88.4 pt); cached by font, size, italic, role and text; `ReleaseScratch` when the operation ends.
- **`modPptCompose`** -- `ComposeExample(box, ex, fonts, colWidths, lineStarts, numberText, lay)` draws the plan into a text box: one paragraph per interlinear tier per wrap line, stops at the cumulative column positions, the number hanging (`LeftIndent = hang`, `FirstLineIndent = -hang`, a stop at the hang), free lines quoted below; `LimitLineColumns` keeps every line within 32 stops. `PrepareExampleBox` sets the frame (wrap on as the safety net, AutoSize shape-to-fit-text, no side margins).
- **`modPptInsert`** -- the command. `InsertExamples(text, slide, x, y, width)` parses every example in the text and calls `InsertOne` for each: fonts and layout (defaults until settings live in `Presentation.Tags`), measure, plan, then compose IN PLACE into a new text box on the slide -- text, formatting, name, tags -- with no scratch presentation, no paste and no clipboard traffic (one macro run is one undo entry: round 8). Several examples in one copy: one box each, numbered (1a), (1b) -- the owner's one-number-with-sub-numbers rule in the form a single box allows. `LingTeXInsertInterlinear` is the ribbon-facing entry: clipboard onto the current slide.
- **`modPptRewrap`** -- `ReadBackExample` reads the TEXT (what the user typed), with the tags as the schema: cells split on tabs, the number dropped, wrap lines joined back into one row per tier, quotes stripped from free lines, capitals restored from the Smallcaps attribute; rows that disagree read back False. `RewrapExample` measures and plans for the box's current width, composes in a scratch box to see whether anything would change (`BoxSignature`), and only then composes again in place into the box: a re-wrap that changes nothing writes nothing -- no undo entry, no resize event of our own. `LingTeXRewrapSelected` is the command.
- **`modPptTests`** -- `PptTestsRun`, run with `run-in-powerpoint.sh --tests`, writes `Tests.<os>.txt`. Section 1: the shared modules answer. Section 2: Insert's road on the made-up sample (`LingTeX-Word/samples/checklist-sample.txt`, embedded as `Fixture(sep)`, generated from the file); the expected numbers -- one block, tiers Morphemes and Gloss, 15 word-aligned columns, 22 morpheme-aligned, one free line -- come from `reference.js`. Section 3: the fixture joined by every break sequence a paste can produce: LF, CR LF, CR, CR CR, LF CR (Mac VBA's `vbCrLf`), a vertical tab, and two examples with a blank line between in each form. Section 4: the live clipboard -- what the rig put there, its counts and run profile, then parsed. **These cases are the shared normaliser's acceptance test**; in JavaScript (the line-break session mirrored the algorithm into `reference.js` and the cases into `parity-test.js`) all of them pass; in VBA they are unexecuted until the rig runs.

**The clipboard normaliser is shared, and landed 2026-09-28** (`claude/lingtex-word-crlf` 790d140, the line-break session's). Not a change to `NormalizeLineBreaks`: that one is a lossless map of conventions to LF, runs twice per parse, and halving is not idempotent (all-4 halves to all-2, which halves again, and a blank line between two examples is gone). Where it lives:

```
modIgtModel   NormalizeClipboardText(s)     the one call a reader makes. For FLEx text (LooksLikeFlex): vertical
                                            tabs to LF, NormalizeLineBreaks, then the collapse. For anything else:
                                            NormalizeLineBreaks and nothing more -- in a Word document a Chr$(11) is
                                            a soft break and CleanTextLine makes it a space, so it is left alone.
modFlexParse  VerticalTabsToLineBreaks(s)   Chr$(11) -> Chr$(10): a Shift+Return is a ROW separator in a FLEx copy
              DoublingFactor(s)             m: the shortest run of break CHARACTERS, if even and every run is a
                                            multiple of it; else 1
              CollapseDoubledLineBreaks(s)  divide every run by m; when the test says no, leave the text alone --
                                            an over-split example is visible and recoverable, a silently merged
                                            one is neither
              LineBreakRunProfile(s)        diagnostics, e.g. "2x5,4x1"
```

Runs are counted in break characters, BEFORE CR LF is paired into one break. PowerPoint's "two examples, LF CR" vector forced that: two adjacent LF CR breaks spell LF CR LF CR, the pairing rule merges the inner pair, the blank line measures three breaks not four, the odd run disproves doubling, nothing collapses, and the two examples come back as four blocks. Counting characters, a run of two means one break whether it is a real CR LF or a doubled single break, and every vector passes. (It is in `modIgtModel`, not `modFlexParse`, because it guards on `LooksLikeFlex`, and `modIgtModel` is what depends on `modFlexParse`.)

Applied ONCE, at the clipboard boundary. Expected in the Word rig when it runs: `RunAllTests` 140 (a hand count by the line-break session, not a measurement). Word's `ClipboardText` should call `NormalizeClipboardText` too; a FLEx copy made with Shift+Return probably arrives as one line in Word today (untested: the Word rig is blocked on the same paste it has waited on since 2026-09-16).

**Does a CR LF paste double?** Rounds 2 and 3 said yes (CR CR); the `Probe.mac.txt` in the repo shows two breaks arriving as two CRs, and does not record which setting produced them. Section 4 of the tests reports the counts and run profile that arrive; run it with `LINGTEX_CLIP_EOL=lf` and without, and record both here.

**The rig is blocked (2026-09-28).** The Claude desktop app's processes can no longer read or write PowerPoint's container (`~/Library/Containers/com.microsoft.Powerpoint/Data`, "Operation not permitted"), which the rig uses to hand modules to the sandboxed PowerPoint; it worked on 2026-09-16, and the macOS upgrade since has evidently reset a privacy grant. A grant in System Settings > Privacy & Security (Full Disk Access, or the container under Files and Folders, for the Claude app) is Seth's to make. Accessibility, which the dialog-catcher needs, may have been reset too.

**Dependency to track:** the shared modules come from `claude/lingtex-word-crlf` (6b55471) through `stage-shared.sh`, and that branch is merged nowhere -- not `main`, not this branch. The merge order is Seth's decision; until then the two can drift.

**Undo, settled from the type library (2026-09-28).** `Microsoft PowerPoint.tlb` (in `Contents/SharedSupport/Type Libraries`) has no `UndoRecord`, `StartCustomRecord`, `EndCustomRecord` or `StartNewUndoEntry` identifier; its only undo members are `NumUndoLevels`, `Undo` and a hidden `rSetUndoText`. Word's library, read the same way as the control, has the first three. So round 6's error 438 means "not in the object model", not a Mac quirk with a workaround to find, and round 5's one paste is the design. (Method: `strings` on the `.tlb` with substring matching; MSFT name tables pad identifiers, e.g. `UndoRecordWW0$`, so an exact match finds nothing.)

**Undo and the clipboard, measured (probe round 8, 2026-09-28).** The rig's `--undo-check` had never run: `before`, `after` and `whose` are AppleScript reserved words, so its script never compiled, and round 5's "Undo Paste" was a label read by eye. Fixed, the check presses Edit's first item through accessibility -- never opening the menu, because PowerPoint answers no Apple event while a menu is open, until a human closes it -- and `--after-undo` runs a macro that counts what is left (`tools/probe/modProbeUndo.bas`; reports `InsertUndo`, `ManyWritesUndo`, `ManyWritesExisting`, `InsertUndoAfter`). Measured four ways: a real `LingTeXInsertInterlinear` (paste-based, then in-place); `Slides.Add` plus three `AddShape` with texts in a new presentation; three `AddShape` with texts on the dev presentation's existing slide (5 shapes back to 2). Every time: the Edit menu offered ONE entry, pressing it left "Can't Undo", and every write of the run was gone. **So the scratch-and-paste construction, and the clipboard save/restore around it, were built for a per-write undo that does not exist here; both are removed.** Insert composes into a new box on the slide; re-wrap composes into the existing box; the user's clipboard is never touched; the deferral policy for automatic re-wrap is moot. Still open: whether the hidden `rSetUndoText` can name the entry, and confirming the one-entry rule from the ribbon (every measurement ran the macro through `run VB macro`).

**Probe round 7 (clipboard save and restore), for the record:** `Clipboard.mac.txt`. Rich text with italics, small capitals and tab stops saves whole into a scratch text box and restores whole with a `Copy`; a shape on the clipboard cannot be saved that way (`TextRange2.Paste` refuses it, -2147024809) but `Shapes.Paste` takes it; from VBA, AppleScript's `clipboard info` and `set the clipboard to (the clipboard)` both fail (438). None of it is needed now that nothing pastes.

**The clipboard reader, measured (section 4 of the suite, 2026-09-28):** a CR LF copy arrives in the scratch box with every internal break doubled (CR CR) and ONE trailing CR, because the box's last paragraph has no terminator; an LF copy arrives as one CR per break. The single trailing run vetoed the shared collapse on the first live run (two blocks from one example); `DoublingFactor` and its port in `reference.js` now leave a run at either end of the payload out of the test (crlf `ece9479`, `03c1571`; cases in `modTests`, `parity-test.js` and `SectionLineBreaks`).

**Next, in order:** the rig; the suite (sections 1-7, all unexecuted); whether `Shapes.Paste` of a box copied from a windowless scratch presentation lands (round 7 B tests the shape case -- if it refuses, Insert falls back to AddTextbox plus one TextRange2.Paste, two entries, and the plan says so); then read-back and re-wrap, which reuse compose with a `TextRange2.Paste` into the existing box; then the ribbon.

**Was:** the rig; the suite under both settings; then Insert -- measure with a scratch box and `Characters(1, n).BoundWidth`, cached by font and text as Word's `MeasureKey` does; plan with `modWrap` unchanged (it is pure arithmetic: `ColumnWidths`, `NoBreakFlags`, `ComputeWrapLines`); compose in a scratch presentation; one `TextRange2.Paste`. Guard `AfterShapeSizeChange` with a busy flag set around every redraw and cleared at load (Word's `gBusy`), because a re-wrap changes the box's height and would hear its own event. Whether the example box keeps AutoSize (round 6 relied on it) or turns it and WordWrap off so that the planner's breaks are the only breaks is to settle with the first drawing.

## Step 3: commands (started 2026-09-29)

On the shared modules from `main` c34fe49 (LingTeX-Word beta.8): a copied baseline gives the columns, every line type keeps its row, free-line marks read, a boundary's owner as U+2060 in the model.

- **`modPptSettings`** -- the presentation's settings in `Presentation.Tags` (`LINGTEX_SET_*`): font and size, gap, number hang, the space between the examples of one copy, numbering on or off, grammatical-gloss casing, the alignment new examples take, the space replacement, re-wrap on resize. A missing tag reads as its default. Also the derived `TierFontsFor` (forms italic) and `LayoutFor` (the hang is the setting or the measured number, whichever is wider); Insert, re-wrap and every command take fonts and layout from here, so nothing can disagree.
- **`modPptCommands`** -- the commands on an example already on a slide, each: read the box back (`ReadBackExample`), change the model with the shared operations, compose back in place (`RecomposeExample`; one run, one undo entry). `LingTeXCheckGlossing` (CheckExample; the fixable ones on request: `FixColumnBreakChars` per column, `FixCellSpaces`), `LingTeXSplitColumn` and `LingTeXMergeColumns` (the column from the text cursor: `ColumnAtChar` reads the paragraph as wrap line and tier, the tabs before the cursor as the cell, the earlier wrap lines' cells counted in, the number's tab not a cell), `LingTeXAlignByMorpheme` / `LingTeXAlignByWord` (the selected examples re-projected -- `ProjectToMorphemes`, or continuation columns folded back into their heads by `NoBreakFlags` -- and the presentation's setting for new ones), `LingTeXRenumber` (every box, slide by slide, top to bottom; a group from one copy keeps its letters, `TAG_SUB`, the first taking the next number), `NextExampleNumber` (Insert numbers from it). `LingTeXStart` hooks the events.
- **`clsPptEvents`** -- `AfterShapeSizeChange` re-wraps an example the user resized. Every composition records the size it left in `TAG_SIZE`; a resize to exactly that size is the composition's own event, heard after the macro returned (round 4), and is ignored. `gPptBusy` guards a command's own writes. Off with the setting `RewrapOnResize`.
- **Tests** sections 9 (settings round trip), 10 (the cursor's column at known character positions; split at the first column with a break and merge back to the same model; by morpheme and back by word; Check on the read-back model), 11 (renumber: (5), (9a), (9b) become (1), (2a), (2b); the next free number).

Untested by the rig, by design: the wrappers that read the live selection (`SelectedExampleBox`, `ColumnAtSelection`), since the scratch presentation has no window. To exercise by hand from the macro list, then from the ribbon.

## Step 5, begun: the ribbon and the add-in build (2026-09-29)

- **`src/customUI14.xml`** -- the Interlinear tab: Insert; Re-wrap This, Re-wrap All, Renumber; Split Column, Merge Columns, By Word, By Morpheme; the toggles Numbers, First Capital, Re-wrap on Resize; Check Glossing. LingTeX-Word's icons, reused. Left out on purpose, with the reason in the file's comment: Convert Table, Text to Interlinear, Indent/Outdent, Re-wrap on Save/Leave, the Settings dialog, Reset Styles, the shortcuts.
- **`src/modPptRibbon`** -- the `Rbn*` callbacks (controls As Variant), `RbnGetPressed`/`RbnToggle` on the active presentation's settings, `Auto_Open` -> `LingTeXStart` (the events), `Auto_Close` -> `LingTeXStop`.
- **`tools/modPptBuild.SaveAsAddInSource`** (dev rig) -- a new presentation with no window gets exactly the release modules (the rig stages `release.txt`: `$MODULES` less `tools/` and the tests; `modLingTeXDevCore.DevImportList` imports them the one way that works here) and is saved as `LingTeX-PowerPoint-engine.pptm` (format 16) in PowerPoint's Documents folder; the runner moves it to `build/`.
- **`tools/build-ppam.sh`** -- from that engine: the main part's content type becomes the add-in's, the ribbon and icons are injected (as build-dotm.sh does), packed with `[Content_Types].xml` first -> `LingTeX-PowerPoint/LingTeX-PowerPoint.ppam`. `--ribbon-into file.pptm` writes a copy of any presentation with the ribbon in it, to look at the tab without installing.
- **Install (Mac):** copy the `.ppam` into the Startup folder (`modLingTeXDev.StartupFolder`), quit and start PowerPoint; `Auto_Open` hooks the events. To confirm by hand: the tab shows, Insert draws from a FLEx copy, a resized box re-wraps, one Cmd+Z takes a command back.

- **`tools/check-ppam.sh`** (+ `check-ppam-sources.py`) -- the drift guard, the mirror of check-dotm.sh: the VBA part, the ribbon byte-identical to `src/customUI14.xml` and its icons, the relationship and content types, the main part an add-in, no slides, every ribbon handler a Public Sub in `src/`, and every compiled module its source line for line (build/shared + src less the tests; borrows LingTeX-Word's decompressor and comparison, so `main` had to be merged into this branch -- done 2026-09-29). ALL PASS on the first build.
- **`install/`** -- `Install LingTeX-PowerPoint.applescript` and `Uninstall LingTeX-PowerPoint.applescript`, LingTeX-Word's scripts for the PowerPoint Startup folder (quit-and-wait, staging copy, quarantine cleared, byte-compared, moved into place); `INSTALL.md`. Both compile (osacompile).
- The `.ppam` stays untracked (*.ppam in .gitignore) until the release shape is decided: tracking it as Word tracks its template, with the guard in CI, is the pattern; a release workflow is Seth's to approve (GitHub spending rules).

**Next, in order:** the by-hand confirmation of the add-in from the Startup folder (ribbon, events, undo from the ribbon); the guide; a release shape (dmg with the scripts, as Word's; Windows: a `.ppam` registered by hand or an installer); a Windows smoke test; then issues #8-#10 in the shared layer, and Word-side parity items (the Lex. Gram. Info. role).

## Probe 1 results (Mac, PowerPoint 16.112.4, 2026-09-15)

Full report: `LingTeX-PowerPoint-reports/Probe.mac.txt`.

| Question | Result |
|---|---|
| Measuring out of sight | Works: a presentation with no window lays text out. |
| Measuring text | A whole range's `BoundWidth` adds about a quarter em (5 pt at 20 pt). A substring's `Characters(i, n).BoundWidth` and a fitted box's width don't, so measure those. 200 measurements take 0.05 s. |
| Small capitals | Render and measure, between lower case and capitals. |
| Tab stops per paragraph | Exact. Paragraphs with the same stops line up to the point, and each paragraph keeps its own stops. Text wider than its stop pushes the tab on to the next stop. |
| Tab stop limit | 32 per paragraph. |
| A tab line wider than the box | It breaks at the tabs, each piece starting at the left. A narrowed frame looks scrambled until it is re-wrapped. |
| Hanging number | Works: a left indent, a negative first-line indent, and a stop at the indent. |
| Clipboard as text | `Shapes.PasteSpecial` isn't supported (error 438). What works is in rounds 2 and 3, below. |
| Tags | Survive Duplicate and Copy + Paste. 20,000 characters read back whole. |
| Grouped boxes | Group, tag and edit work. Resizing the group stretches the boxes but not the font. |
| Tables | One grid, confirmed: a cell's width can't be set apart from its column. A table can't be grouped. |
| VBA project | Available, so a macro can import modules. |

## Probe rounds 2 and 3 (Mac, PowerPoint 16.112.4, 2026-09-15, through the dev rig)

Full report: `LingTeX-PowerPoint-reports/Probe.mac.txt`.

| Question | Result |
|---|---|
| Which width is the text's own | `Characters(1, n).BoundWidth`. For "neighbor-F" at 20 pt it gives 88.4 pt, the same as the last character's right edge. A whole range's `BoundWidth` gives 93.4 pt (a quarter em more), and a box fitted to the text is 89.2 pt. |
| Reading clipboard text | Paste it into an empty text box's text: `TextRange2.Paste` works with no window, tabs intact (so do `TextRange2.PasteSpecial` as plain text and `TextRange.Paste`). `Shapes.Paste` refuses text copied in another application, and `TextRange.PasteSpecial` and `View.PasteSpecial` aren't supported. |
| Line breaks | On this Mac, from `pbcopy`: Windows line breaks (CR LF) arrived doubled, as CR CR; Mac/Unix line breaks (LF) arrived as one CR. This may well differ by platform and by where the text comes from, so the reader must detect doubling rather than assume it. See "Clipboard tests to run" below. | **Measured again 2026-09-28 through the reader itself: CR LF doubles plus a single trailing CR; LF gives one CR per break.**
| Letters beyond ASCII | Arrive intact ("ñ"). |
| `AppleScriptTask` | Exists (error 5 when no script is installed). A clipboard script is a fallback if ever needed. |
| `MacScript("the clipboard")` | Works on this Mac, giving the same text as the paste plus a trailing break. |
| Startup folder | PowerPoint on this Mac loads Adobe's `SaveAsAdobePDF.ppam` from Office's shared Startup folder for PowerPoint (loaded, autoload). It may also write to the user's own Startup folder. So an installer that drops the add-in there will very likely work; the load test will confirm it. |

## vbCrLf is not CR LF here (Mac, PowerPoint 16.112, 2026-09-15)

In PowerPoint for Mac's VBA, `vbCrLf` is the two characters LF, CR (codes 10, 13), in that order, and `vbNewLine` is LF alone (`ImportModules.mac.txt` logs both). So:

- **`Replace(text, vbCrLf, vbLf)` never matches a real CR LF.** Replacing CR on its own afterwards then turns every line break into two. That is what doubled every line of the first class module the rig imported.
- **Text built with `vbCrLf` puts LF CR between lines.**

**Rule for this project:** never use `vbCrLf` or `vbNewLine` to find, split or normalise line breaks. Use `Chr$(13)` and `Chr$(10)`, as `modLingTeXDevCore` does. Audit every module shared with LingTeX-Word for the same thing before it runs here.

The importer is now `tools/modLingTeXDevCore.bas`, which can itself be re-imported. The pasted `modLingTeXDev` only bootstraps it, so fixes to the importer never need pasting again. The core checks every module's line count against its source.

## Clipboard tests to run once Insert works

Line breaks (and possibly other details) may arrive differently depending on the platform and on where the text was copied. Run all of these with a real FLEx copy, and with plain tab-separated text, before trusting the reader:

1. FLEx on Windows, pasted into PowerPoint on Windows.
2. FLEx in the Parallels Windows VM, pasted through the shared clipboard into PowerPoint on the Mac.
3. Text with CR LF and with LF line breaks, from a text editor, into PowerPoint on the Mac and on Windows.
4. An example with a blank line between two examples, so that collapsing doubled breaks is shown not to merge two examples into one, or split one into two.

For each, record the tab, CR, LF and vertical-tab counts the paste produced (probe section 9 already prints them), and keep them in the doc tests.

## The Startup folder and saving an add-in (Mac, 2026-09-15)

Reports: `LingTeX-PowerPoint-reports/StartupAddIn.mac.txt` and `MakeStartupTestAddIn.mac.txt`.

- **A `.ppam` in the Startup folder loads when PowerPoint starts.** A test add-in in `~/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint` ran its `Auto_Open` one second after PowerPoint started. PowerPoint listed it as loaded, set to load automatically, and ticked in Tools > PowerPoint Add-ins. So the Mac installer copies the add-in there.
- **VBA can't save an add-in here.**
  - `SaveAs` and `SaveCopyAs` with format 30 (`ppSaveAsOpenXMLAddin` on Windows) give "Invalid enumeration value", with or without a window.
  - `SaveAs` with no format writes the old binary format under a doubled name ("LingTeXStartupProbe.ppam.ppt").
  - `SaveAs` with format 25 (a macro-enabled presentation on Windows) gives "Failed".
- **What works:** a `.ppam` is a `.pptm` whose main part has the add-in content type (`application/vnd.ms-powerpoint.addin.macroEnabled.main+xml` in place of `...presentation.macroEnabled.main+xml`). The test add-in was the dev presentation, saved by the importer's ordinary `Save`, with that one string changed. The build can make the real add-in the same way on any machine. It still needs a `.pptm` holding only the add-in's modules (an engine presentation, as LingTeX-Word has an engine template), either saved once by hand or saved by VBA once the Mac's format numbers are known.
- Test modules: `tools/probe/modStartupProbe.bas` (the save attempts) and `tools/probe/modStartupAutoOpen.bas` (the `Auto_Open` that reported). Neither is imported by default.

## Probe round 4: events and undo (Mac, PowerPoint 16.112, 2026-09-15, with Seth at the keyboard)

Reports: `LingTeX-PowerPoint-reports/Events.mac.txt` and `Undo.mac.txt`. The probe: `tools/probe/modProbeEvents.bas` and `clsProbeEvents.cls`.

| Question | Result |
|---|---|
| Resizing by hand | `AfterShapeSizeChange` fires once, when the handle is let go (not during the drag), with the new size (254 x 124 pt; the box grew taller as its text wrapped). So re-wrapping when the frame is resized is possible. |
| Resizing by code | Also fires `AfterShapeSizeChange`, but only after the macro has returned, and only once for several size changes to one shape in a run. A re-wrap that changes a box's size hears its own event after its busy flag is already cleared, so the guard has to be something else. For example: ignore a resize to exactly the size the re-wrap just set. |
| Selection | `WindowSelectionChange` fires on clicking into a box's text (type 3), on selecting the box (type 2) and on clicking away (type 0), and `SlideSelectionChanged` fires too. So re-wrapping when the cursor leaves an example is possible. |
| Undo | One Cmd+Z took back only the last of six changes one macro made (the text). The shape, its fill, position, width and tag all stayed. Each change a macro makes is its own undo step, so a re-wrap made of many changes would need many Cmd+Z. | **Superseded by round 8 (2026-09-28): the rig measured one Undo taking back all seven writes of a run, in a new presentation and in this one.**

Next probe: can a re-wrap be one undo step? Compose the example's formatted text in a scratch presentation, then put it into the real box with one `TextRange2.Paste`. Check that one Cmd+Z restores the old example whole, and that per-paragraph tab stops, small capitals and italics survive the paste. *(Superseded: round 8 -- a run is one entry whatever it writes.)*

## Probe round 5: a re-wrap as one undo step (Mac, PowerPoint 16.112, 2026-09-15, with Seth at the keyboard)

Report: `LingTeX-PowerPoint-reports/Paste.mac.txt`. The probe: `tools/probe/modProbePaste.bas`.

1. A box held an OLD example: two paragraphs with tab stops at 100 and 220 pt, italic forms, small-capital glosses.
2. One macro composed a NEW example in a scratch presentation (three paragraphs, stops at 80, 190 and 260, a free translation), copied it, and replaced the old text with one `TextRange2.Paste`.
   - The box then held the NEW example whole: text, per-paragraph tab stops, italics and small capitals all came through the paste.
   - PowerPoint's Edit menu read "Undo Paste".
3. One Cmd+Z restored the OLD example whole: text, stops, italics and small capitals (Seth's screenshot and the report agree).

**So every re-wrap and insert is: plan and measure, compose in a scratch presentation, copy, one paste into the example's box.** That keeps undo to one step, as `UndoRecord` does in Word, and leaves the box itself, its position, size and Tags, untouched. *(Superseded 2026-09-28 by round 8: one entry per macro run, so both compose in place with no paste.)*

## Probe round 6: undo entries, what a paste leaves alone, save formats (Mac, PowerPoint 16.112.4, 2026-09-15)

Reports: `LingTeX-PowerPoint-reports/Round6.mac.txt` and `SaveScan2.mac.txt`. The probe: `tools/probe/modProbeSave.bas` (`ProbeRound6Quiet`, `ProbeSaveScan2Quiet`), run through the rig with nobody at the keyboard.

| Question | Result |
|---|---|
| Named undo | `Application.UndoRecord` and `Application.StartNewUndoEntry` both give error 438. VBA cannot name or group undo steps here, so composing in a scratch presentation and pasting once (round 5) is the only way to make an insert or re-wrap one undo step. | *(Round 8: not needed -- a run is one entry anyway.)*
| What one paste leaves alone | After one `TextRange2.Paste` into an example's box, its name, Id, left, top, width, Tags, AutoSize, word wrap, margins and z-order were all unchanged. Only the height changed, because AutoSize fitted the new text. |
| `SaveCopyAs` format numbers | Wrote a file: 1 (.ppt), 5 (.pot), 6 (.rtf), 7 (.pps), 10 (.pptx), 12 (.mov); with no format, .pptx. No error but no file anywhere: 8 and 14 to 21. "Not supported in this version": 2, 3, 4 and 9 (PowerPoint 3, 4 and 95) and 11 (HTML). "Invalid enumeration value": 0, 13, 22 to 36, and every number from 37 to 120. |

- **The Mac has its own `PpSaveAsFileType`.** Seth checked it in the Object Browser (16, 20 and 25), and `tools/typelib/msft_enums.py` read all of it from `Contents/SharedSupport/Type Libraries/Microsoft PowerPoint.tlb`: 1 Presentation, 2 PowerPoint7, 3 PowerPoint4, 4 PowerPoint3, 5 Template, 6 RTF, 7 Show, 8 Wizard, 9 PowerPoint4FarEast, 10 Default, 11 HTML, 12 Movie, 13 Package, 14 PDF, 15 OpenXMLPresentation (`.pptx`), 16 OpenXMLPresentationMacroEnabled (`.pptm`), 17 OpenXMLShow, 18 OpenXMLShowMacroEnabled, 19 OpenXMLTemplate (`.potx`), 20 OpenXMLTemplateMacroEnabled (`.potm`), 21 OpenXMLTheme, 22 GIF, 23 JPG, 24 PNG, 25 BMP, 26 TIF. The Object Browser hides Movie, Package, Wizard and the old formats. PowerPoint's AppleScript `save` uses the same numbers (`PowerPoint.sdef`, `EPPSaveAsFileType`). There is no Open XML add-in (`.ppam`, 30 on Windows). `SaveCopyAs` refused the pictures (22 to 26) with "Invalid enumeration value".
- **14 to 21 most likely save in the background.** They reported no error and left no file, probably because PowerPoint crashed (below) before they finished. So `SaveCopyAs ..., 16` should write a `.pptm`; that has not been seen working, and the build does not need it.
- **Look values up; don't scan.** `tools/typelib/ppt-enums.mac.json` and `mso-enums.mac.json` hold every enum in `Microsoft PowerPoint.tlb` and `mso.tlb`. The plain numbers the probes use all match them: 12 blank layout, 1 left tab stop, 1 shape-to-fit-text AutoSize, -1 msoTrue, 1 horizontal text box.
- **Making the add-in.** Seth saves the engine as `.pptm` or `.potm` with File > Save As (the importer's ordinary `Save` keeps it that way), and the build makes the `.ppam` from it by changing the main part's content type, as the startup test did. Nothing on the Mac writes a `.ppam` directly.
- **PowerPoint crashed three seconds after round 6 finished.** Microsoft Error Reporting (log from Seth): `EXC_BAD_ACCESS` on the main thread, inside a background job, 1.7 s after the last VBA call. The likely cause is a save still running in the background when the probe closed the presentation: the movie (12), and perhaps 14 to 21. PowerPoint restarted and recovered its open presentations; the second scan (37 to 120) then ran without trouble. The probe now always skips 12 and 14 to 21.
- **Rule:** never close a presentation in the same macro run as a `SaveCopyAs` in format 12 or 14 to 21. A macro that ever saves a `.pptm` (16) must wait until the file is complete before closing anything.

## Smoke test: the shared LingTeX-Word modules in PowerPoint (Mac, PowerPoint 16.112.4, 2026-09-16)

Setup: `tools/stage-shared.sh` stages `modFlexParse`, `modIgtModel`, `clsIgtWarning`, `modLeipzig` and `modWrap` from `origin/claude/lingtex-word-crlf` (82fefb8, the line-break fix) into `build/shared/`. The rig imports them with `build/smoke/modPptSmoke.bas` and runs `PptSmokeRun`; the probes are left out of MODULES. The smoke module and its report stay out of git for now, because they contain the owner's FLEx copies (field data), pending his decision on publishing them.

| Question | Result |
|---|---|
| Do the shared modules compile in PowerPoint? | Yes: all five, unchanged, with no stand-in module. One call into each ran (`NormalizeLineBreaks`, `NewExample`, `CheckExample` and `FixCellSpaces`, `ComputeWrapLines`). |
| Does Insert's road run? | Yes, up to where Word would start drawing: `LooksLikeFlex`, `ParseFlexBlocks`, `ModelsFromText`, `FixCellSpaces`, `CheckExample`, `ModelFromText`, and the wrap planner on made-up widths. No run-time error anywhere. |
| The owner's real FLEx copies | The typical two-line copy parses as it does in Word: example 1 is 1 column word-aligned and 3 morpheme-aligned, example 2 is 9 columns. The known parser defects show up as expected: the second example's free translation loses its first word, Insert would draw only the first example, "§" becomes a word with an empty gloss, and a copy with several writing systems gives no example. They belong to the LingTeX-Word parser issue, not to PowerPoint. |
| Line breaks | CR LF, CR, and CR with no final break give the same result as LF. CR CR and LF CR split every row into its own block; vertical tabs (Shift+Return, Chr 11) join rows into one line. |

- **PowerPoint's clipboard reader must therefore, before calling `ParseFlexBlocks`,** collapse doubled breaks (CR CR, LF CR) without merging two examples that a real blank line separates, and decide what a vertical tab means. The smoke test's "blank line between two examples" input is the baseline for that.
- The rig's probe sample (`run-in-powerpoint.sh`, "Free" followed by a tab) is not FLEx's shape: its free line keeps a leading tab. Use a real FLEx line shape in future samples.


## The rig on macOS 27 (2026-09-28)

- **Permissions go to "Claude Code"**, the nested bundle `com.anthropic.claude-code` that the desktop app launches through its `disclaimer` helper, not to `Claude.app`: Full Disk Access (the container), Accessibility (System Events), Automation (PowerPoint and System Events).
- **The VBA editor is invisible to accessibility**: `name of every window` of the process lists only presentation windows, so the rig cannot read a compile or run-time error dialog or see break mode. `tools/check-names.py` resolves every call before the import; it caught both compile errors of the day (a local named `note` shadowing the `Note` helper; `SplitGlossSegments` living in Word's `modRender`, now in the shared `modFlexParse`). `run VB macro` failing with -18 means a compile error only the editor shows. Break mode does not stop the next run.
- **Never open a menu from a script**: PowerPoint answers no Apple event while a menu is open, and only a click on the screen closes it. `--undo-check` presses the item without opening; `--after-undo NAME` runs the count.
- **AppleScript reserved words** that silently broke the rig: `before`, `after`, `whose`.
- `Presentation.Tags(name)` reads back "" in the probes (shape Tags are fine); the probes use counts.
- `Application.VBE.MainWindow.Visible` reports False while the editor window is open on another Space.
