# LingTeX-Word

A Microsoft Word add-in for pasting FLEx interlinear glossed text and keeping it
aligned — **cross-platform**, Windows Word and Mac Word 2016 or later.

Part of [LingTeX Tools](../README.md), but a self-contained sub-project: it
shares no build step with the web app, the browser extensions or the desktop app,
and ships as its own two downloads.

---

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

### Phase 1 — import the modules

Packaging is Phase 3 (see *Status* below). For now:

1. In Word, open the VBA editor: **Alt+F11** (Windows) or **Tools → Macro →
   Visual Basic Editor** (Mac).
2. **File → Import File…** and import every file in `src/`:
   `modFlexParse.bas`, `modIgtModel.bas`, `modLeipzig.bas`, `modWrap.bas`,
   `modMeasure.bas`, `modStyles.bas`, `modRender.bas`, `modReadBack.bas`,
   `modSettings.bas`, `modLingTeX.bas`, `modTests.bas`, `clsIgtWarning.cls`,
   `clsAppEvents.cls`.
   Import the `.bas` and `.cls` files — do **not** paste their contents into a new
   module, because the `Attribute VB_Name` line at the top of each is read by the
   importer and is a compile error if typed into the editor.
3. Run `AutoExec` once (or restart Word) to arm the save hook.
4. Run the commands from **Alt+F8**: `LingTeXInsertInterlinear`,
   `LingTeXRewrapCurrent`, `LingTeXRewrapAll`, `LingTeXSplitColumn`,
   `LingTeXMergeColumns`, `LingTeXCheckExample`, `LingTeXConvertTableToIgt`.

`src/customUI14.xml` is the ribbon; it only takes effect once the modules are
packaged into `LingTeX-Word.dotm`, which is Phase 3.

### Verify the install

In the VBA editor, open the Immediate window (**Ctrl+G**) and run:

```
RunAllTests
```

Every line must read `PASS`. This runs identically on Windows and Mac and is the
gate before trying anything in a real document.

---

## Using it

| Command | What it does |
|---|---|
| **Insert Interlinear** | With nothing selected, reads the clipboard; with text selected, replaces it. Accepts FLEx interlinear text (tab-separated, with tier labels) or plain tab-separated rows. |
| **Convert Table** | Adopts an ordinary Word table as an auto-wrapping example. |
| **Re-wrap This** / **Re-wrap All** | Recompute the wrap. Also runs on save. |
| **Split Column** | Pulls an affix, clitic or reduplicant into its own column, carrying the break character onto every interlinear tier. |
| **Merge Columns** | Select across cells to merge those; with one cell selected, merges it with the next column. |
| **Check Glossing** | Reports and optionally repairs, as above. |

### Settings

Stored as **document variables**, so they travel inside the `.docx` and a
colleague re-wrapping the file gets the same layout. Set them from the Immediate
window:

```vba
SetSettingGap ActiveDocument, 8              ' points between columns (default 6)
SetSettingLineGap ActiveDocument, 8          ' points between wrap lines (default 6)
SetSettingContIndent ActiveDocument, 18      ' indent of later wrap lines (default 0)
SetSettingSpaceReplacement ActiveDocument, "_"   ' "." or "_" (default ".")
SetSettingGranularity ActiveDocument, igtMorphemeAligned   ' default igtWordAligned
SetSettingLowercaseGramGloss ActiveDocument, False   ' keep capitals as typed
SetSettingRewrapOnSave ActiveDocument, False
SetSettingRewrapOnSelectionChange ActiveDocument, True   ' off by default
```

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

### To verify on real Word during implementation

Each of these has a documented fallback already in the code, but none has been
confirmed on a Mac:

- Does `Cell(r, c).Width` read back correctly after
  `AutoFitBehavior wdAutoFitContent`? (Fallback: set `USE_AUTOFIT = False` in
  `modMeasure.bas` to use `Range.Information` instead.)
- Is `Information(wdHorizontalPositionRelativeToTextBoundary)` available?
- Do `Table.LeftPadding` / `RightPadding` / `Spacing` exist? (If not, both the
  measurement table and the rendered table keep Word's default padding, so the
  measurement stays consistent with the drawing.)
- Does custom ribbon XML in a STARTUP `.dotm` load?
- Is `Documents.Add(Visible:=False)` genuinely invisible?

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
commands. Driven from the document selection or the clipboard.

**Phase 2 — the form.** A dialog with an editable data table: paste FLEx or TSV,
fix it up in a grid, split and merge columns from column headers, see the check
findings per cell, and type free translations into their own boxes.

No `.frm` ships in Phase 1, deliberately. A Word UserForm exports as a `.frm`
*plus* a binary `.frx`, and a `.frm` written by hand without its companion does
not reliably import — it is not something that can be authored or tested outside
Word. The form will be built in the VBA editor and exported from there. Because
no grid control exists on Mac, it will be a **virtualised pool** of `TextBox`
controls (around 14 columns by 8 rows, created once, with a scrollbar rebinding
which data columns they show, so the control count stays bounded however long the
example), each wrapped in a class using `Private WithEvents` — dynamically added
controls raise no events in the form's own module. The engine does not change
when it arrives: the form will build an `IgtExample` and hand it to
`RenderExample`.

**Phase 3 — packaging**, as two downloads:

- **Windows** — `installer/LingTeX-Word.nsi`, an NSIS installer that drops
  `LingTeX-Word.dotm` into Word's STARTUP folder, registers that folder as a
  Trusted Location, and never needs the VBA editor. Per-user, so no admin rights.
- **Mac** — `installer/Install LingTeX-Word.applescript`, shipped
  **uncompiled** so double-clicking opens it in Script Editor as readable text:
  the user reads the "what this does" notes at the top and presses Run. That gets
  past Gatekeeper with no Developer ID and no notarisation.

A VBA project is a binary stream that cannot be authored without Word, and
GitHub's runners have no Word installed, so CI cannot build the `.dotm`.
`src/*.bas` stays the source of truth; `tools/build-dotm.ps1` builds the template
on a Windows machine with Word, `tools/export-modules.ps1` exports back out so
the binary cannot silently drift, and CI builds only the installers.

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
