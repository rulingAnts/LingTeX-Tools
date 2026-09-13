# LingTeX-Word

A Microsoft Word add-in for pasting FLEx interlinear glossed text and keeping it
aligned — **cross-platform**, Windows Word and Mac Word 2016 or later.

Part of [LingTeX Tools](../README.md), but a self-contained sub-project: it
shares no build step with the web app, the browser extensions or the desktop app,
and ships as its own two downloads.

> **Setting it up for the first time? Start with
> [`QUICKSTART.md`](QUICKSTART.md).** It runs the probe, then the modules in two
> stages, and lists what to do for each way it can fail.

---

## Installing

Releases are on the [releases page](https://github.com/rulingAnts/LingTeX-Tools/releases)
(pre-releases tagged `word-v…`): a Windows installer (`LingTeX-Word-Setup-….exe`),
a Windows zip with the template and `install.bat`, and a Mac zip with the
template and `install.command`. Each puts one file, `LingTeX-Word.dotm`, into
Word's STARTUP folder, where Word loads it at every start; the first time Word
loads it, the add-in installs its keyboard shortcuts and says so. Details and
removal: [install/INSTALL.md](install/INSTALL.md). How a release is made:
[RELEASING.md](RELEASING.md).

## What it does

Copy an interlinear selection in FLEx, click **Insert Interlinear**, and the
example is drawn as a **borderless Word table** — one table column per alignment
slot, one row per tier — wrapped to the page width, with grammatical glosses in
small capitals and the free translation underneath.

When the margins, the font, the page size or the content later change, the
example **re-wraps**: columns move down onto another wrap line when space runs
out, and back up when it is freed. That happens on demand from the ribbon and
automatically when the document is saved.

### A column is an alignment slot, not a word

This is the central idea. A column may hold a whole word, a single morpheme, or
part of a word, and one example may mix all three — split one clitic out into its
own column and leave the rest word-aligned. Nothing in the model, the renderer,
the measurement pass or the wrap planner knows what a word is.

Two invariants hold over **interlinear** cells. Free-translation rows are exempt
from both, because a translation is prose rather than an aligned slot.

1. **Column break-character agreement.** If any cell in a column carries a
   morpheme break character (`-` `=` `~` `<` `>`) at an end, every other
   interlinear cell in that column carries the same character at the same end. A
   split-out suffix column reads `-xa` over `-DIST`, never `-xa` over `DIST`.
   **Split Column** maintains this by construction, and **Check Glossing**
   repairs it where there is a single right answer.
2. **No spaces inside an interlinear cell.** Use `.` or `_`. A space would break
   the column alignment the whole layout rests on.

The wrap planner reads invariant 1 to do its job: a column whose cells begin with
a break character is a continuation of the column before it, so a wrap line never
starts there. That is why a morpheme-aligned example still wraps at word
boundaries — the knowledge lives in the data as a leading `-` or `=`, not in the
code.

### Leipzig Glossing Rules: conventions, not vocabulary

Grammatical glosses are recognised **structurally** — all capitals, or
digit-initial. There is **no list of approved abbreviations** anywhere in the
add-in, so an abbreviation nobody has ever published is still recognised and
still gets small capitals. The published Leipzig list is examples, not a
vocabulary, and linguists coin their own constantly.

`Check Glossing` reports what can be decided mechanically and repairs only what
has one right answer:

| Finding | Repaired? |
|---|---|
| A column where only some interlinear cells carry the break character | Yes |
| A space inside an interlinear cell | Yes, to `.` or `_` |
| Two cells in a column claiming **different** break characters | No — only the linguist knows which |
| Form and gloss showing a different number of morpheme breaks (rule 2) | No — reported |
| An unmatched infix bracket (rule 8) | No — reported |
| A column filled on some interlinear tiers and not others | No — legal, but usually a slip |

Rule 4's `.` and `:` are never counted as morpheme breaks and never split on:
they mark one morpheme glossed with several meta-language words, so they need no
counterpart in the object-language form. `stack.CMP=SEQ` against `rixu=xo` is
correct and is not flagged.

---

## Installing

Not packaged yet — see *Status*. **Start with [`QUICKSTART.md`](QUICKSTART.md)**,
which walks the first run in order and says what to do when something breaks.
The short version:

### Step 0 — run the probe

Five things this add-in does with Word's object model are assumptions that have
never been observed on a real install. `tools/probe/modProbe.bas` is a
self-contained module that checks all of them, prints a report, and cleans up
after itself. Import it, run `ProbeWord` in the Immediate window, and read the two
verdicts that matter: *autofit cell widths* decides how columns are sized, and
*VBProject access* decides whether the rest can be automated.

### Step 1 — six modules, no document touched

`modFlexParse`, `modIgtModel`, `modLeipzig`, `modWrap`, `clsIgtWarning`,
`modTests` reference nothing defined in the other seven, so they compile and run
alone. Import them and run `RunAllTests` in the Immediate window — every line must
read `PASS`.

That isolates the two risks that would otherwise be tangled: whether the VBA port
computes correctly, and whether Word's object model behaves as assumed. Pass this
and anything later is the second, not the first.

### Step 2 — the remaining seven

`modStyles`, `modSettings`, `modMeasure`, `modRender`, `modReadBack`,
`modLingTeX`, `clsAppEvents`. Then run `AutoExec` once, or restart Word, to arm the
save hook.

Import the `.bas` and `.cls` files via **File → Import File…** — do **not** paste
them, because the `Attribute VB_Name` line at the top of each is read by the
importer and is a compile error if typed in. If your editor has no Import, run
`sh tools/make-paste-bundle.sh` to generate stripped, paste-ready copies in
`build/paste/`, each headed with the module name to set and whether it is a
standard module or a *Class Module*.

Commands run from **Alt+F8** (Windows) or **Tools → Macro → Macros** (Mac):
`LingTeXInsertInterlinear`, `LingTeXRewrapCurrent`, `LingTeXRewrapAll`,
`LingTeXSplitColumn`, `LingTeXMergeColumns`, `LingTeXCheckExample`,
`LingTeXConvertTableToIgt`, `LingTeXIndentExample`, `LingTeXOutdentExample`.

`src/customUI14.xml` is the ribbon; it only takes effect once the modules are
packaged into `LingTeX-Word.dotm`. Its icons are our own, `src/icons/*.png`,
drawn by `tools/make-icons.py`: a small page carrying an interlinear example,
with a badge for what the button does. Nothing in them is a grid, because the
examples are tables to Word but not to the user.

---

## Using it

| Command | What it does |
|---|---|
| **Insert Interlinear** | With nothing selected, reads the clipboard; with text selected, replaces it. Accepts FLEx interlinear text (tab-separated, with tier labels) or plain tab-separated rows. |
| **Convert Table** | Adopts an ordinary Word table as an auto-wrapping example. |
| **Re-wrap This** / **Re-wrap All** | Recompute the wrap. Also runs on save. A space typed into an interlinear cell becomes the document's replacement character (`.` or `_`), as on insert; a space would let Word wrap the text inside the cell. |
| **Split Column** | Pulls an affix, clitic or reduplicant into its own column, carrying the break character onto every interlinear tier. |
| **Merge Columns** | Select across cells to merge those; with one cell selected, merges it with the next column. |
| **Check Glossing** | Reports and optionally repairs, as above. |

### The ribbon's toggles

By Word / By Morpheme, Re-wrap on Save, Re-wrap on Leave, Numbers and First
Capital are toggle buttons: they show the active document's setting and flip it
silently. The same settings are also commands in the macro list, which report
what they did. If the toggles stop following changes, the VBA project was reset
and Word must be restarted for the ribbon to reconnect.

### Numbering

Every new example carries its number in a **first column**: a cell as wide as
the `NumberHang` setting (36 pt) at the start of every row, whose first-row
paragraph is in the `LingTeX Example` style and so is numbered `(1)`, `(2)`… by
Word's own list numbering (a list style called `LingTeX Example Number`,
continuing from the previous example). The number therefore sits on the
vernacular line, where a linguist expects it, and travels with the example
when the example is moved or copied; the translation is indented past it.
Because it is an ordinary numbered paragraph, everything Word does with
numbering applies: deleting or moving an example renumbers the rest, a
cross-reference can point at it, and the list style decides its format. The
number cell is not content: the read-back skips it, split and merge refuse the
cursor in it, and a re-wrap rebuilds it from the setting, so changing
`NumberHang` reaches every example on its next re-wrap. `LingTeXToggleExampleNumbers`
decides only whether *new* examples get a number; an example keeps its number
through every re-wrap. An example drawn by an earlier build, with its number on
a line above the table, is migrated by its next re-wrap: the number moves into
the table and the line goes.

**The example's indent** is its rows' left indent. Indent and Outdent on the
ribbon (`LingTeXIndentExample`, `LingTeXOutdentExample`) step it half an inch,
re-wrapping the example to the new line with the number and the translation
moving with it; dragging the table's left edge on the ruler works too, and a
re-wrap keeps whatever it finds. A fresh example takes the indent of the
paragraph it is inserted into.

**Per-chapter numbering.** Modify the list style (Format → Style →
`LingTeX Example Number`): link its level 1 to Heading 1 with no number text,
put `(%2)` on level 2 with no trailing character and a text position of 0 (the
number sits alone in its cell), then `SetSettingNumberLevel ActiveDocument, 2`.
New examples then sit on level 2, which Word restarts after every Heading 1.
Any multilevel scheme Word can express works the same way.

### Settings

Stored as **document variables**, so they travel inside the `.docx` and a
colleague re-wrapping the file gets the same layout. The toggles are on the
LingTeX tab; **Settings** opens a dialog over all of them (below). The typed
setters still work from the Immediate window:

```vba
SetSettingGap ActiveDocument, 8              ' points between columns (default 6)
SetSettingLineGap ActiveDocument, 8          ' points between wrap lines (default 6)
SetSettingContIndent ActiveDocument, 18      ' indent of later wrap lines (default 0)
SetSettingSpaceReplacement ActiveDocument, "_"   ' "." or "_" (default ".")
SetSettingGranularity ActiveDocument, igtMorphemeAligned   ' default igtWordAligned
SetSettingLowercaseGramGloss ActiveDocument, False   ' keep capitals as typed
SetSettingRewrapOnSave ActiveDocument, False
SetSettingRewrapOnSelectionChange ActiveDocument, False  ' on by default
SetSpacingText ActiveDocument, "TierGap", "2"     ' any spacing of the dialog; "" unsets
```

### The Settings dialog

**Settings** on the ribbon opens one dialog over every setting the document
holds, in three parts.

**New examples**: one column per word or per morpheme; whether they are
numbered, and on which list level; grammatical glosses in small capitals, and
whether with a full-size first capital; the two re-wrap triggers; and what a
space inside a cell becomes.

**Spacing**, one box per spacing, in points, by level. **An empty box is a
state**: the spacing is not set, and the default (shown in brackets) or the
style applies. OK and Apply store the values and re-wrap every example in the
document at once, so the page shows the change; Cancel stores nothing. A box
that is not a number is refused by name before anything is stored.

| Row | Box | What it sets | Empty means |
|---|---|---|---|
| Example | Before | Space above the example, on its first row | none |
| | After | Space after the translation, or after the last row when there is none | the translation style's own 3 pt |
| | Left | Left indent of every *new* example | the indent of the paragraph it is inserted into |
| | Right | Right indent: the wrap lines and translation stop this far short of the margin | none |
| Wrap lines | Line gap | Space between the wrap lines of an example | 6 |
| | Continuation | Extra indent of every wrap line after the first | 0 |
| | Tier gap | Space between the tiers of one wrap line | 0 |
| Columns | Column gap | Space to the right of every column's widest cell | 6 |
| | Number column | Width of the number column | 36 |
| Cell padding | Left, Right | Padding inside every cell; the columns are widened to match, and the table's edge moves left by the left padding so the text stays at the example's indent, level with the translation | 0 |
| | Top, Bottom | Padding inside every cell of every row | 0 |
| Translation | Above | Space between the last row and the first translation | none |
| | Between | Space between two translations | the style's own 3 pt |

**Styles**: the add-in's eight styles listed (Vernacular, Morphemes, Gloss,
Word Gloss, Category, Free Translation, Grammatical Gloss, Example Number),
and **Modify in Word**, which opens Word's own style dialog on the selected
one for everything a style can hold: font, size, colour, borders, the
paragraph format. (It first selects the first text in that style, because
the dialog opens on the selection's style; with no example on the page yet it
says which style to pick.) Nothing of ours sits between you and the style, so Format →
Style shows the same thing. **Reset This Style** puts one style back to what a
fresh document gets, following the Normal style; **Reset the Six Tier Styles**
does the tier styles together (also **Reset Styles** on the ribbon).

Where a spacing lives follows from what it depends on. Everything that depends
on the layout, and so has to be written per row or per paragraph when the
example is drawn (which row is first, which is the last of a wrap line, where
the translation starts), is a document setting written by the renderer. The
appearance of the text is style-borne, because that is what a Word style is
for, and because it keeps the escape hatch: a document restyled by hand and
one set from the dialog are the same document.

The dialog is a UserForm with **no controls at design time**: every control is
built in code when it opens, so its only source is `src/frmLingTeXSettings.frm`,
a text file with no `.frx`, which the bootstrap installs the way it installs
the two class modules. The doc tests drive it without showing it.

### Spelling

The interlinear tier styles are marked *do not check spelling or grammar*, and
every drawn cell is marked the same way directly, so the checker never
underlines a vernacular form or a gloss; the free translation, outside the
table, is checked as ordinary text.

### The styles are yours

The add-in creates these on first use and then **never overwrites them**, so
anything you tune is kept. Restyle `LingTeX Gloss` once and every example in the
document follows.

| Style | Kind | Role |
|---|---|---|
| `LingTeX Interlinear` | table | The tag. A table with this style is an auto-wrapping example; change it and the add-in leaves the table alone. |
| `LingTeX Vernacular` | paragraph | Object language (italic by default) |
| `LingTeX Morphemes` | paragraph | Morpheme breakdown |
| `LingTeX Gloss` | paragraph | Morpheme gloss |
| `LingTeX Word Gloss` | paragraph | Word gloss |
| `LingTeX Category` | paragraph | Category / part of speech |
| `LingTeX Free` | paragraph | Free translation, outside the table |
| `LingTeX Gram Gloss` | character | Small capitals on a grammatical gloss run |

---

## How it works

### The document describes itself

Re-wrapping means reading an example back out of the document. Nothing is stored
on the side — no document variables holding source text, no bookmarks, no custom
XML — because every side channel can be lost to a copy-paste or a round trip
through another editor, leaving a table the add-in no longer recognises.

Instead the table is read the way a person reads it: the **table style** says it
is ours; the **paragraph style of each row's first cell** is that row's tier
role; a new wrap line begins wherever the first tier role comes round again, so
concatenating the row groups in order recovers the flat column list exactly; and
a run carrying the **character style** was lowercased when it was drawn, so it is
uppercased on the way back. Small caps is therefore reversible, not destructive.

If the styles are ever stripped, roles are inferred positionally instead, so the
table is still recoverable — just with generic tier names.

### Why the wrap is recomputed, never patched

`modWrap.ComputeWrapLines` plans from the **full column list** every time, and is
never diffed against what is already on the page. That one decision is why
pulling columns back up needs no separate code path, why any number of wrap lines
works, and why re-wrapping is idempotent. Do not turn it into an incremental
differ; the symmetry is the feature.

### Measuring text

Word exposes no text-measurement function, and a table wider than the page gets
silently clamped by autofit — which would corrupt the measurement. So measurement
happens in a hidden scratch document with a **22-inch page** (Word's maximum) and
zero margins, where nothing can clamp. One autofitted row per tier is measured
and read back cell by cell, which is one round trip per tier rather than one per
cell; that matters on Mac, where each call into the object model is slow. Results
are cached, so re-wrapping unedited text touches Word not at all.

Cells are measured with the **same runs the renderer draws**, small caps
included, by calling the renderer's own `WriteCellText`. Measuring the raw source
text would over-estimate, because full capitals are wider than small capitals.

### Module layout

| File | Responsibility |
|---|---|
| `modFlexParse.bas` | FLEx clipboard parsing; groups morpheme columns into words **keeping the per-morpheme segments** |
| `modIgtModel.bas` | The tier × column grid; projections, split, merge, insert, delete; TSV round trip |
| `modLeipzig.bas` | The invariant and convention checks, and the repairs. No Word objects |
| `modWrap.bas` | The wrap planner. **No Word objects** — arrays in, plan out |
| `modMeasure.bas` | Text width, via the scratch document, with a cache |
| `modStyles.bas` | Creates the styles; maps role ↔ style name |
| `modRender.bas` | Draws the table; small-caps runs; free translations |
| `modReadBack.bas` | Rendered table → model; locates a column from a cell |
| `modSettings.bas` | Settings in document variables |
| `modLingTeX.bas` | The commands, the ribbon callbacks, undo, clipboard |
| `frmLingTeXSettings.frm` | The Settings dialog; a form with no `.frx`, its controls built in code |
| `clsAppEvents.cls` | `DocumentBeforeSave` and optional selection-change hooks |
| `clsIgtWarning.cls` | One finding from a check |
| `modTests.bas` | Self-tests — run `RunAllTests` |

---

## Writing Word VBA that runs on a Mac

These are hard constraints, not preferences. Each one breaks Mac Word silently or
at compile time, and `tools/vba-lint.py` enforces the ones that can be checked.

| Not available on Mac Word | Use instead |
|---|---|
| ActiveX controls — there is **no grid control** | Built-in MSForms only; a grid has to be built from `TextBox` controls |
| `Scripting.Dictionary`, `FileSystemObject` | `Collection` with string keys |
| `ADODB.Stream`, `WScript.Shell`, `MSScriptControl` | Native VBA |
| `VBScript.RegExp` | Hand-rolled character scans (see `IsGramGloss`) |
| `CreateObject` / COM generally | Nothing; design around it |
| `MSForms.DataObject` for the clipboard | Paste into a hidden `Document` with `PasteSpecial wdPasteText` — Word's own paste works everywhere |
| `Application.UndoRecord` | Guard with `#If Mac Then`; Mac gets multi-step undo |
| `Application.MacScript` (removed in 2016) | Avoid |
| `Environ("TEMP")` | `Environ("TMPDIR")`; `Application.PathSeparator` |
| Unsandboxed file I/O | **Avoid entirely** — this design needs none |
| `Application.EnableEvents` (never existed in Word) | A module-level `gBusy` flag |

Two more that bite:

- **`.bas` files are imported in the system ANSI code page, not UTF-8.** A
  non-ASCII literal in the source arrives as mojibake, and differently on each
  platform. Every source file here is **pure ASCII** and builds non-ASCII
  characters with `ChrW()` at run time. `vba-lint.py` fails the build on a
  non-ASCII byte. (VBA's `Const` cannot hold a `ChrW()` call, which is why those
  are `Property Get` or `Function`.)
- **VBA does not short-circuit `And` / `Or`.** `If i <= UBound(a) And a(i) = x`
  still evaluates `a(i)` and raises *subscript out of range*. The guard must be a
  separate, nested `If`. `vba-lint.py` checks for this.

### Verified on real Word

These were assumptions until `tools/probe/modProbe.bas` was run on **Word 16.112
for Mac**. Two of them were wrong.

**Read every verdict as a fact about the machine that ran it, in the state it was
in — not about the platform.** This table once said the VBA project was "blocked on
Mac, with no setting to grant it": the probe had reported `BLOCKED` accurately on a
Mac where the trust setting was not yet ticked, and that one measurement got written
up as a capability. It cost a Mac user fourteen manual imports before anyone
checked. A `BLOCKED` is a reason to look at the machine's settings; it is never a
reason to write "cannot".

| Assumption | Result |
|---|---|
| Hidden `Documents.Add(Visible:=False)`, 22-inch page | **Works.** `Windows.Count` 0, page reads back 1584 pt |
| Autofit cell widths size to content | **FAILS.** Four different strings all returned 394.7 pt, which sums to the page width — it divided the page equally and never consulted the content. The autofit path is deleted; the header of `modMeasure.bas` records the numbers so nobody reinvents it |
| `Range.Information` position as a width | **Works**, and is now the only method: `i` 3.0 pt, `WWWWW` 53.3 pt |
| Rows may hold different cell counts | **Works** — 2 and 3 cells in one table, so one table per example is sound |
| `Cell.SetWidth RulerStyle:=wdAdjustNone` | **Works** — 72 pt set, 72 pt read back |
| `Table.LeftPadding` / `RightPadding` / `Spacing` | **All settable** |
| `Styles.Add` for table and character styles | **Works** — the tagging scheme holds |
| Borders on a *table style* | **FAILS** on Mac, error 4198. `modRender` switches borders off per table, which on Mac is the only thing doing it |
| `Font.SmallCaps` reports `wdUndefined` on a mixed range | **Works** — 9999999, as `modReadBack` assumes |
| `Document.Variables` round trip | **Works** |
| `Application.UndoRecord` | **Present on Mac.** The `#If Mac Then` guard was needless and is gone, so Mac gets single-step undo too |
| VBA file write and read | **Works**, but redirected into Word's sandbox container rather than the real temp directory |
| `VBProject.VBComponents.Import` | **Available on both platforms** once "Trust access to the VBA project object model" is ticked — Trust Center on Windows, Word → Preferences → Security & Privacy on Mac; the label is identical. Until it is, both raise error 6068. After it, `tools/ImportModules.bas` imports all fourteen modules from one paste, and `VerifyLingTeXModules` confirms them. **This row used to say "blocked on Mac, with no setting to grant it."** The probe reported `BLOCKED` accurately, on a Mac where the setting had not been ticked yet, and that one measurement was written up here as a platform fact — see the note above this table. Confirmed working on Mac Word 16.112 |
| `Application.FileDialog` | **Absent** on Mac, error 5948. No folder picker for the add-in or any bootstrap — relevant to the Phase 2 form |

A second probe, `tools/probe/Probe AppleScript Bridge.applescript`, asked what
Word exposes to AppleScript on the same build:

| Term | Result |
|---|---|
| Word is scriptable | **Yes**, version 16.112.4 |
| `do Visual Basic` | **Absent.** No arbitrary-VBA bridge, so a script cannot inject code |
| `run VB macro` | **Present.** A script can invoke a macro that already exists |

Together with `VBProject.Import` being blocked, that settles the build: nothing can
*inject* modules, so the `.dotm` is assembled by hand in the VBA editor. But
`run VB macro` is enough for the Mac installer to **verify its own work** — after
copying the template it can relaunch Word and call `LingTeXPing`, which
distinguishes "installed and loaded" from "installed and silently ignored". That
matters because the known silent failure is macOS quarantining a `.dotm` that
arrived inside a downloaded zip.

Still unverified, for one pass on Windows: the NSIS installer. Custom ribbon XML
in a startup `.dotm` **does** load on Mac — verified 2026-09-12 on Word 16.112,
the full LingTeX tab over a new document, every group and icon present.

**And one finding that changed the testing policy, then changed again.** `MicroDiagnose`
produced run-time error 6, *Overflow*, on `s1 = 10` where `s1` is `As Single`, and
for a while the type was blamed. The cause is `Debug.Print`: on Mac Word 16.112 it
arms an Overflow in the next floating-point statement, in that procedure or its
caller, and any call in between clears it (bisected 2026-09-12; see
`SettleDebugPrint` in `modTests` and QUICKSTART.md). Every `Debug.Print` is now
followed by that call and the linter enforces it. The policy stands regardless:
**stage 1 must return `ALL PASS` on both platforms** before document-rendering
work is built on top — cross-platform VBA differences are real, and this was one.

---

## Development

### Tests

```bash
node LingTeX-Word/tools/parity-test.js     # algorithms, against PROMPT.md + docs/core.js
python3 LingTeX-Word/tools/vba-lint.py     # VBA structure, ASCII, Mac-API traps
```

And in Word: `RunAllTests` from the Immediate window.

### `tools/reference.js` is the executable specification

VBA cannot be run in CI. So the algorithms that have no counterpart in
`docs/core.js` — the segment projections, the column invariants, the wrap planner
— are written **first** in `tools/reference.js`, proven by
`tools/parity-test.js`, and only then hand-ported to VBA. `modTests.bas` mirrors
the same cases so the port is held to the same behaviour inside Word.

**If you change an algorithm, change it in both places.** Every affected VBA
procedure carries a comment naming its counterpart. This mirrors the existing
`docs/core.js` ↔ `tauri/src-tauri/src/convert.rs` convention in this repository.

The golden vectors are **derived from `PROMPT.md` at run time** by substituting
tabs for its `→` markers, never copied — hand-transcribing the empty-column runs
in example 2 got them wrong on the first attempt, and reading the spec means the
vectors cannot drift from it.

### Relationship to `docs/core.js`

`reference.js` delegates FLEx parsing to `docs/core.js`, the repository's single
source of truth, and adds only the new layer on top. The VBA port is a superset
in one respect: `groupWordsFromColumns` in `core.js` joins each word's form into
one string and so discards the per-morpheme segments, while
`GroupSegmentsFromColumns` keeps them. That is what makes morpheme-aligned and
word-aligned output two *projections* of one segment list rather than two
algorithms. The word-aligned projection still reproduces `core.js`'s TSV
byte-for-byte, which the tests assert.

---

## Status

**Phase 1 — the engine — is what is here.** Parsing, the column model, the
invariant checks, measurement, the wrap planner, the renderer, read-back, and the
commands. Driven from the document selection or the clipboard. Proven inside Word on
both platforms on 2026-09-12: `RunAllTests` 79/79 and `RunDocTests` 224/224, on
Mac and on Windows, by the one-command runners (QUICKSTART.md, *Status*).

**Phase 2 — the form.** A dialog with an editable data table: paste FLEx or TSV,
fix it up in a grid, split and merge columns from column headers, see the check
findings per cell, and type free translations into their own boxes. It is also
where the settings get an interface — column gap, line gap, continuation indent,
the small-caps convention, the styles themselves — instead of a macro list and
the Immediate window.

One `.frm` ships — the Settings dialog — and it shows the rule the data-sheet
form will follow. A Word UserForm designed in the VBA editor exports as a
`.frm` *plus* a binary `.frx` that nothing outside Word can author, review or
diff. So `frmLingTeXSettings.frm` has **no controls at design time and no
`.frx`**: every control is built in code when the form opens, the buttons held
in `WithEvents` variables so their clicks fire (a control added at run time
raises no events into the form module by name), and the bootstrap installs the
code the way it installs a class. The data sheet will be built the same way,
as a **virtualised pool** of `TextBox` controls (around 14 columns by 8 rows,
created once, with a scrollbar rebinding which data columns they show, so the
control count stays bounded however long the example), each wrapped in a class
using `Private WithEvents`. The engine does not change when it arrives: the
form will build an `IgtExample` and hand it to `RenderExample`.

**Phase 3 — packaging**, as two downloads. Both install `LingTeX-Word.dotm` into
Word's startup folder, where it is loaded as a **global add-in**: its commands,
ribbon tab, shortcuts and `AutoExec` apply to every document, whatever
template that document is based on, and no document is ever attached to it.
That is the sense in which the ribbon and the macros are not template-specific
(Seth, 2026-09-12); the file is a `.dotm` only because that is the container
Word loads from that folder.

- **Windows** — `installer/LingTeX-Word.nsi`, an NSIS installer that drops
  `LingTeX-Word.dotm` into Word's STARTUP folder, registers that folder as a
  Trusted Location, and never needs the VBA editor. Per-user, so no admin rights.
- **Mac** — `installer/Install LingTeX-Word.applescript`, shipped
  **uncompiled** so double-clicking opens it in Script Editor as readable text:
  the user reads the "what this does" notes at the top and presses Run. That gets
  past Gatekeeper with no Developer ID and no notarisation.

A VBA project is a binary stream that cannot be authored without Word, and
GitHub's runners have no Word installed, so **CI can never build the `.dotm`**.
`src/` stays the source of truth: the template is built once in Mac Word (import
the modules, Save As a macro-enabled template), then `tools/build-dotm.sh` — bash,
no Word — injects the ribbon XML and its icons and writes a SHA-256 manifest of
every source file. CI verifies rather than builds: it unzips the `.dotm`, diffs
the embedded ribbon against `src/customUI14.xml` and the embedded icons against
`src/icons/`, and checks the manifest, so a template that has drifted from the
sources fails the release.

**Later — convert-table, finished.** `LingTeXConvertTableToIgt` adopts a hand-made
or pasted table: one row per tier, and **a row whose cells are merged into a
single cell is taken as the free translation** (it reads the table as TSV, and
an untabbed line is a translation); with no such row it says so and how to add
one. Two additions would make it the way most non-FieldWorks examples come in,
and might make the Phase 2 data-sheet form unnecessary. First, let the user say
which of the bottom rows are free translations (one or more, by language)
rather than rely on the merged-row convention. Second, a step before it:
**table from text** — the user types or pastes the example as ordinary lines,
words separated by spaces, one line per tier, corresponding word for word but
not aligned; the step splits each line on whitespace into a table (a longer
line padding the shorter), and convert-table takes it from there.

**Later — switch an example's alignment in place.** Today the alignment
(by word or by morpheme) is chosen when an example is inserted; changing it
means inserting again. The data supports switching without that: a
word-aligned cell still holds its boundaries (`rixu=xo` / `stack.CMP=SEQ`), so
word to morpheme is the split at every boundary, on every tier, column by
column; and morpheme to word is merging every continuation column (the ones
`NoBreakFlags` marks) into the one before it. Both are the proven split and
merge primitives, applied to the whole example, followed by the ordinary
delete-and-redraw. One command, `LingTeXToggleExampleAlignment`, on the
example at the cursor; its only new logic is the loop. And its bulk form: the
same over every example whose table lies within the selection — or the whole
document when nothing is selected — as `LingTeXAlignSelectionByWord` /
`…ByMorpheme`. Selecting a heading in Outline view selects its whole section,
so a chapter's examples can be switched in one go with nothing new to write.

**Later — numbering, headings, captions.** What an example carries in a
FieldWorks text, and what a paper puts around it. Already handled: any number
of interlinear tiers per wrap line, and several free translations (one
paragraph each). One gap in that: a second translation's language tag (`Free
Ind`) is dropped on the way in, so two translations render alike — keep the
tag, and give each language a way to be styled (a per-language style, or the
tag as a prefix). Example numbers are done (see *Numbering* under *Using it*). Not handled yet:
a heading before, a caption after with a figure number, list bullets or
numbering around the example, and sub-numbering (`a.`, `b.`) across the
examples of one multi-block paste — the natural home for which is a second
level of the same list style. Two constraints for whoever designs it:
numbers must be Word's own — a `SEQ` field or a list level — so that
cross-references and renumbering keep working, and whatever carries the number
(a paragraph before, or an indent on the table) must be something
`AvailableTextWidth` already sees, so the planner's budget stays right; a left
indent on the table is already subtracted.

**Later — input that is not from FieldWorks.** The engine was specified as
source-agnostic, and for its two inputs it is: FLEx interlinear text (tier
labels, tab-separated) and plain TSV with one row per tier. What is still
FLEx-shaped is the routing and the conventions underneath — recognising a
block by its tier labels, `Free` / `Free Eng` introducing a translation,
a morpheme-break character split across tokens, a standalone punctuation
token belonging to the word before it. The sources still to come will each
test a different one of those: Toolbox / SFM (`\tx` `\mb` `\ge` `\ft`
lines, where the label is a backslash code and alignment is by whitespace
column, not tab), a table pasted from Excel or Numbers (which arrives in Word
as a table, so `LingTeXConvertTableToIgt` is the door, or as TSV), and the
Phase 2 data sheet, where a linguist types the example by hand and the only
rule is what she typed. FieldWorks data working correctly comes first, and it
is most of the way there; this is the question to reopen once it is done.

**Done — every space a user might want to set** is in the Settings dialog
(*Using it*, above), with the styles opened in Word's own dialog rather than
edited by us. Still to prove: that a UserForm whose controls are built in code
opens and lays out on Mac Word. The doc tests prove it headless — New builds
the controls, LoadFrom and ApplyNow round-trip — but not the pixels.

**Later — several examples in one paste.** A FLEx text copied whole arrives as
several interlinear blocks and the parser already returns all of them
(`ModelsFromText`); `LingTeXInsertInterlinear` takes the first. The finishing
step is to draw them all, one after another with a paragraph between, in one
undo record.

**Later — re-wrap on edit.** Word has no "content changed" event, so this is
built on the selection-change hook that already exists (`clsAppEvents`,
`LingTeXToggleRewrapOnSelectionChange`), made change-aware: fingerprint the
example's text when the cursor enters it, and on leaving re-wrap only if the
fingerprint differs. It then never fires while typing inside an example, never
on a click-through, and exactly once on leaving an example that was edited —
which is what would let it be on by default. A polling timer could catch edits
sooner but would re-wrap under the cursor mid-keystroke, which is worse than
nothing.

**Later — PowerPoint.** The same problem exists in slides, and the architecture
already anticipates it. Four modules are pure computation with no Word objects at
all — `modFlexParse`, `modIgtModel`, `modLeipzig`, `modWrap` — and port verbatim.
Four are platform-specific and would need PowerPoint counterparts: `modMeasure`,
`modRender`, `modReadBack`, `modStyles`.

Two differences to design around when that happens. PowerPoint has **no named
styles**, so the self-describing-document trick does not carry over — but shapes
have a `Tags` collection, which is a better tag than a style name ever was.
And measuring text is *easier* there, not harder: `TextFrame2.TextRange.BoundWidth`
reports rendered width directly, with none of the hidden-scratch-document
machinery `modMeasure` needs to work around Word. Word is the priority; this is
recorded so the module boundaries are not lost.

---

## Known issues

- **Re-wrap All over many examples shows the busy cursor for a few seconds.**
  VBA is single-threaded; the status bar reports progress meanwhile. The time
  is text measurement, which the width cache reduces on repeat runs.
- **A document whose LingTeX styles were created before the styles followed
  Normal keeps their pinned size**; `LingTeXResetStyles` fixes it once.
- **A template loaded as a global add-in has a protected VBA project**
  (error 50289): its macros run, it can save itself, but nothing may import
  into it. The dev loop therefore uses two templates (TESTING-MAC.md, setup
  step 1); the shipped template is unaffected.

---

## Superseded work

`../word_processing_tools/FLExToWord.bas` renders each word as an OMML
(equation-editor) matrix, injected through a FlatOPC temp-file round trip. It is
kept as a record of a dead end: equation frames are opaque to the clipboard and
to any later macro transformation, the alignment is poor, and the temp-file
round trip fights Mac Word's sandbox. Its `IsGrammatical` and `SplitPunctuation`
logic is what `modFlexParse` is ported from.

## License

AGPL-3.0 — Copyright © Seth Johnston. FLEx interlinear conversion logic based on
original TeXstudio macro code by **Moss Doerksen (SIL PNG)**, used by permission.
