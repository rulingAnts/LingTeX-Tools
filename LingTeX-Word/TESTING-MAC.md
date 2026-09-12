# Walking `TESTING.md` section 3 on a Mac

The checks themselves are in `TESTING.md`. This is how to run them on Mac Word
without stopping to work out the mechanics each time: the setup once, the way a
command is run, and then six passes in an order where each one leaves the
document ready for the next.

Sections 1 and 2 are already green on both platforms — `RunAllTests` 79/79 and
`RunDocTests` 224/224, reports in `LingTeX-Word-reports/`. Section 3 is the part
no automated suite can reach: what the thing actually looks like on the page.

---

## Setup, once

1. **The two templates.** A template loaded as a global add-in has its VBA
   project protected (nothing may import into it, error 50289), so the code
   is split: a tiny **dev template** in Word's startup folder holds only the
   bootstrap and loads the **engine template** from the clone at Word start;
   the engine is the add-in itself, and it gets refreshed by the dev template
   unloading it, importing into it as a document, saving, and loading it
   again. Once:
   - In Word: a new document, Tools → Macro → Visual Basic Editor,
     Insert → Module, paste `tools/ImportModules.bas` without its first line,
     name the module `modImport`. File → Save As → **Word Macro-Enabled
     Template**, `LingTeX-Dev.dotm`, into the startup folder
     (`~/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word`).
   - The engine: `LingTeX-Word/LingTeX.dotm` in the clone. If you already have
     one in the startup folder from the earlier arrangement, the next step
     moves it. Otherwise make it once the same way from the file that holds
     the modules (Save As template into the clone's `LingTeX-Word` folder).
   - Quit Word, then:
     `sh LingTeX-Word/tools/install-dev-template.sh`
     (ribbon into the engine, clone location into the dev template, runner
     pointed at the engine).
   - Start Word and run `sh LingTeX-Word/tools/run-in-word.sh`. The import
     log's `from` and `into` lines name the clone's `src` and the engine; the
     suites run; the hooks are armed; and if everything passed the engine is
     marked good (`build/engine-ok`), so from the *next* Word start the dev
     template loads it by itself and every document has a **LingTeX** tab.
     An engine whose last run was not green is never loaded at Word start:
     the runner repairs it by importing into it as a document, where nothing
     compiles until it has been replaced. (That rule exists because a loaded
     add-in with a module that does not compile raises the same dialog at
     every load, unload and command, and Word cannot be got past it.)

2. **Make the test document.** ⌘N for a blank one, then save it somewhere
   ordinary — `~/Desktop/lingtex-test.docx`. It has to be saved before the
   save-hook checks in pass 5 mean anything.

3. **Arm the hooks.** Run **`LingTeXStart`** (Word for Mac's Macros dialog
   does not list `AutoExec`, which is what it calls). That attaches the save
   and selection handlers and keeps AutoCorrect out of cells. Every command
   arms them on first use as well, and the test runner arms them at the end
   of every run, so this is only needed after restarting Word if the first
   thing you do is save.

4. **Put the sample somewhere you can copy it from.** Open
   `LingTeX-Word/samples/checklist-sample.txt` in TextEdit — the three-line FLEx
   block from `TESTING.md`, in a plain file so the tabs survive. ⌘A, ⌘C.

```bash
open -a TextEdit LingTeX-Word/samples/checklist-sample.txt
```

### Running a command

**The frontmost Word document is the one every command acts on.** So: click into
the test document, then Tools → Macro → Macros…, pick the command, Run. If the
example lands in `LingTeX.docm` instead, that is the mistake — the code document
was in front.

The seven commands, as they appear in the list:

```
LingTeXInsertInterlinear     LingTeXSplitColumn
LingTeXRewrapCurrent         LingTeXMergeColumns
LingTeXRewrapAll             LingTeXCheckExample
LingTeXConvertTableToIgt
```

### The commands, and what each says outside an example

| Command | What it does | With the cursor outside any example |
|---|---|---|
| `LingTeXInsertInterlinear` | Draws an example from the selection, or from the clipboard when nothing is selected | Not an "outside" case: with nothing selected it reads the clipboard and inserts, or says *Nothing to insert.* |
| `LingTeXRewrapCurrent` | Re-plans and redraws the example at the cursor | *Put the cursor inside an interlinear example first.* |
| `LingTeXRewrapAll` | Re-plans and redraws every example in the document | Works from anywhere: *Re-wrapped N interlinear examples.*, or *This document contains no interlinear examples.* |
| `LingTeXSplitColumn` | Splits the column at the cursor at its first morpheme boundary, on every tier | *Put the cursor in the column you want to split.* |
| `LingTeXMergeColumns` | Merges the selected columns, or the cursor's column with the one to its right | *Select the columns you want to merge.* |
| `LingTeXCheckExample` | Runs the Leipzig checks on the example at the cursor and offers the fixes | *Put the cursor inside an interlinear example first.* |
| `LingTeXConvertTableToIgt` | Adopts a plain Word table as an example: styles it and wraps it | *Put the cursor inside the table you want to convert.* |

So the "outside any example" check is five commands and five messages; the
other two behave the same inside or out. Every message is a dialog titled
LingTeX-Word, never a VBA error dialog, and the document is unchanged
afterwards. The six settings commands (`LingTeXAlignByWord` and the rest)
act on the document, not on an example, so the cursor's position never
matters to them.

**Two faster ways than the Macros dialog**, both worth setting up once:

- **Shortcuts.** Run `LingTeXInstallShortcuts` (from the Macros dialog, one
  last time). It binds every command to ⌘⌥ + a letter in the Normal template,
  so they work in every document: ⌘⌥I insert, ⌘⌥R re-wrap this, ⌘⌥A re-wrap
  all, ⌘⌥S split, ⌘⌥M merge, ⌘⌥K check, ⌘⌥T convert table, ⌘⌥W by word,
  ⌘⌥P by morpheme, ⌘⌥H settings. `LingTeXShowShortcuts` lists them;
  `LingTeXRemoveShortcuts` takes them out.
- **The ribbon.** With Word quit:

```bash
sh LingTeX-Word/tools/add-ribbon.sh "<startup folder>/LingTeX.dotm"
```

  With the code in a template loaded from STARTUP (setup step 1), the tab is
  on every document's ribbon, with every command and setting as a button.
  This is the same ribbon the packaged template will carry, so if a button
  comes through blank or does nothing on Mac, that is a finding for the
  packaging step as well. The icons are embedded PNGs (`src/icons/`), a path
  unproven on Mac: every button blank means Mac Word ignores embedded images
  from a startup template, and the fallback is built-in `imageMso` names.

### Settings are commands too

They are in the same macro list, act on the frontmost document, store the value
in it, and say what they did:

```
LingTeXAlignByWord                  LingTeXToggleRewrapOnSave
LingTeXAlignByMorpheme              LingTeXToggleRewrapOnSelectionChange
LingTeXToggleGramGlossInitialCap    LingTeXShowSettings
```

`LingTeXShowSettings` lists everything the document currently holds. Only the
three measurements (gap, line gap, continuation indent) still need the Immediate
window — click the test document first, then Tools → Macro → Visual Basic
Editor, View → Immediate Window: `SetSettingLineGap ActiveDocument, 8`. A
settings dialog is the Phase 2 form's job.

### What a "clear message" means

Every message goes through `Report`, which is a dialog with a title. A command
that does nothing and says nothing is a failure even when nothing looks wrong.

---

## Pass 1 — inserting (`TESTING.md` 3a)

Both input paths, in one pass.

1. **Clipboard path.** Sample copied from TextEdit, cursor in the empty test
   document with *nothing selected*, run `LingTeXInsertInterlinear`. This is the
   FLEx path: with an insertion point and no selection the command reads the
   clipboard.
2. Now the appearance checks, all on that one example: columns aligned, no
   borders, small capitals on `SEQ ERG FOC 3SG` — each with a full-size first letter, `Erg`,
   `3Sg` — and none on `yam pick stack`, the
   object-language row italic and *not* small-capped even at `Ozivela` and `Vo`,
   `zeː` keeping its length mark, `zuvo=ve=zi` in one column glossed `dream=ABL=REL`.
3. **The free translation** is a paragraph *below* the table, in style
   `LingTeX Free`, wrapped in curly single quotes: `'(When) she picked her yams
   early.'` If it is missing, stop and say so — that is the one you flagged
   earlier, and it would be a real bug.
4. **The number.** `(1)` sits in a first column of the table, on the
   vernacular line: that cell's paragraph is in the `LingTeX Example` style
   and carries Word list numbering; the translation is indented past the
   column; no word cell has a number. Insert the sample again below → `(2)`.
   Delete the first example (select its table and translation, Delete) → the
   remaining one reads `(1)`. Drag the table's left edge wider on the ruler
   and re-wrap → the indent is kept and the translation follows it.
   `LingTeXToggleExampleNumbers` → the next insert has no number column. An
   example from an earlier build, with its number on a line above the table,
   gets the number moved into the table by its next re-wrap. Per-chapter
   restarts are a list-style setting: `TESTING.md`.
5. **Fonts.** Cursor in a cell, look at the font name box. It must be the
   document's body font, not Cambria Math and not Times New Roman.
6. **Selection path.** ⌘Z back to nothing. Paste the sample as plain text —
   Edit → Paste Special… (⌃⌘V) → Unformatted Text — select those three
   paragraphs, run Insert. The selection is *replaced*: no stray empty paragraph
   left above or below.
7. **The two refusals.** Insert with an empty clipboard and nothing selected → a
   dialog saying there is nothing to insert. Insert with an ordinary sentence of
   prose selected → a dialog explaining what was expected. Neither may be a VBA
   error dialog.
8. **No file written.** Nothing in this pass should touch the disk. If you want
   it checked rather than assumed, run this in Terminal straight afterwards:

```bash
find ~/Library/Containers/com.microsoft.Word -newermt '-10 minutes' -type f 2>/dev/null | head
```

Keep the example from step 6. Pass 2 needs it.

---

## Pass 2 — wrapping (3b)

The engine's reason for existing. Every step here is: change the page, then put
the cursor in the example and run `LingTeXRewrapCurrent`.

1. As inserted, the long sample should already be **two or more row groups
   inside one table**, nothing past the right margin.
2. **The gap between groups** is `LingTeX_LineGap`, 6 pt by default. To check it
   rather than eyeball it: cursor in the **last row of a wrap group**,
   Format → Paragraph…, *Spacing After* should read 6 pt. Rows that are not the
   last in their group read 0.
3. **Narrow the margins** — Layout → Margins → Custom Margins, set left and
   right to 0.5" — re-wrap → columns push down onto another group. **Widen them
   back** to 1", re-wrap → the extra group disappears and the columns are pulled
   back up. That pull-back-up is the check that matters most; a planner that
   only ever adds lines passes everything else and fails this.
4. **Font size**: change the **Normal style** to 16 pt (Format → Style… →
   Normal → Modify) and re-wrap → more groups. Back to 12 pt, re-wrap → fewer.
   The LingTeX styles inherit their size from Normal. Selecting the cells and
   sizing them directly does *not* count: direct formatting is not part of the
   example and is discarded by a re-wrap, on purpose — the styles are the
   description.
   **A document whose LingTeX styles were created before 2026-09-12 keeps their
   pinned size** (a style is never clobbered once it exists): run
   `LingTeXResetStyles` once, which makes the six follow Normal again and
   re-wraps.
5. **Landscape** (Layout → Orientation) → re-wrap reflows wider. Back to
   portrait → reflows back.
6. **Two text columns** (Layout → Columns → Two) → re-wrap fits the *column*
   width, not the page width. This one has caught a real bug before.
7. **Idempotent**: re-wrap an example that is already correct → nothing visibly
   changes. Re-wrap twice in a row → identical.
8. **Page break**: add paragraphs above until the example straddles a page
   boundary → no stack of aligned cells is split across the break.
9. **An over-wide column**: type a 60-character run into one form cell, re-wrap
   → that column gets a group to itself and wraps inside its cell rather than
   running off the page.

---

## Pass 3 — morpheme alignment and the column invariant (3c)

1. Run `LingTeXAlignByMorpheme`, then insert the sample again into a fresh
   paragraph → one column per morpheme, 22 of them against 15.
2. **The invariant**: no wrap group may begin with `=xo`, `=vexu`, `=ve` or
   `=zi`, and every enclitic column carries the `=` on *both* the form row and
   the gloss row. Read along the left edge of each group.
3. `LingTeXAlignByWord`, and insert once more for the split and merge checks.
4. **Split**: cursor in the `rixu=xo` cell, `LingTeXSplitColumn` → two columns,
   `rixu` / `stack.CMP` and `=xo` / `=SEQ`, with the `=` leading the cell on
   every interlinear tier. The free translation is untouched. Re-wrap still
   works afterwards.
5. **Merge**: cursor in `rixu`, `LingTeXMergeColumns` → back to `rixu=xo` /
   `stack.CMP=SEQ`. With one cell selected it merges with the column to its
   right; select across three cells and exactly those three become one.
6. **The refusal that matters.** A split happens at the *first* boundary of the
   column, on every tier at once — so `zuvo=ve=zi` over `dream=ABL=REL` gives
   `zuvo` | `=ve=zi`, and a second split on the right half gives three. The
   refusal is for a column whose tiers *disagree*: edit one column of the
   example so the form reads `zomu-xa` and its gloss reads `gone` (no break
   anywhere in the gloss), put the cursor in `zomu-xa`, split. A dialog must
   name the Gloss tier, `gone` must stay whole in the left cell, and the new
   right cell must be *empty* on that tier. Nothing is guessed.

---

## Pass 4 — checking and fixing (3d)

`LingTeXCheckExample` with the cursor anywhere in the example.

1. Type a space into an interlinear cell → reported, and the fix replaces it
   with `.` (the `LingTeX_SpaceReplacement` setting).
2. A space in the **free translation** → not reported. Prose is allowed spaces.
3. Delete the `-` from one tier's cell of a split column → break-char agreement
   reported, and the fix restores it.
4. Make two tiers claim *different* break characters — `-xa` over `=DIST` → a
   conflict, reported and **not** silently resolved.
5. `rixu=xo` over `stack.CMP=SEQ` → no rule-2 warning; `.` and `:` are not
   morpheme breaks. Change it to `stack-CMP=SEQ` → a rule-2 warning.
6. Type `SUPEREL` into a gloss cell → small capitals, and *not* flagged as an
   unknown abbreviation. There is no allow-list, by design.
7. A clean example → "No problems found."
8. **AutoCorrect stays out of the cells**: click into an interlinear cell and
   type `erg` at its start → it stays `erg`. Word's "capitalize first letter of
   sentences / of table cells" are switched off while the cursor is inside an
   example and restored outside it (needs `AutoExec`, which arms the selection
   handler).

---

## Pass 5 — round trip and persistence (3e)

1. **Save** (⌘S) → every example re-wraps automatically, no visible flicker, and
   the cursor stays where it was. This is `AutoExec`'s save hook; if nothing
   happens, it was not run.
2. `LingTeXToggleRewrapOnSave` → saving no longer re-wraps. Run it again to
   turn it back on.
3. **Close and reopen** the document, run `LingTeXRewrapAll` → the examples are
   still recognised, which proves the style tagging survived the file format.
4. **Small caps survive**: after that re-wrap, read back a gloss — `ERG` must
   still be `ERG`, not `erg`. The lowercasing is reversible, and this is what
   proves it.
5. **Copy an example** (table *and* its free translation paragraph) and paste it
   elsewhere in the document → both re-wrap independently.
6. **Paste into a brand new document** → the styles are recreated there and it
   re-wraps.
7. **The escape hatch**: change a table's style away from `LingTeX Interlinear`
   (Table Design → a plain style) → `LingTeXRewrapAll` leaves it alone from then
   on.
8. **Restyle `LingTeX Gloss`** — Format → Style…, change its size — and *every*
   example in the document follows. The styles are yours; that is the point.
9. **Two examples close together.** Insert one, press Enter after its
   translation, insert another (one empty paragraph between); and elsewhere
   insert two back to back (nothing but the translation between).
   `LingTeXRewrapAll` → both pairs re-wrap and nothing is deleted. The first
   pass lost the second example here.
10. `LingTeXConvertTableToIgt` on a plain two-row table you type by hand →
   becomes an auto-wrapping example. **A row whose cells are merged into one
   cell is taken as the free translation**; every other row is a tier. With no
   such row the command says so and tells you how to add one.
11. Copy a rendered example, paste it into TextEdit → tab-separated text. Paste
    that back into Word and insert → the same grid.

---

## Pass 6 — undo and robustness (3f)

1. **One ⌘Z undoes a whole insert.** The first pass found it did not: Word
   listed every drawing step separately after the record's own label. The undo
   record now opens only after all measuring is done (the hidden measuring
   document was, on the evidence, closing it). If it still takes several
   presses, say how many and what the undo list shows — the fallback design is
   to draw the example off-page and drop it in with one assignment.
2. ⌘Z after a re-wrap restores the previous layout.
3. **Twenty examples**: select your example, copy, paste it twenty times, then
   `LingTeXRewrapAll` → a few seconds, not a minute.
4. `LingTeXRewrapAll` on a document with **no** examples → a clear message.
5. Each of the seven commands with the cursor **outside** any example → a clear
   message, no error dialog.
6. After every command the screen is live, not frozen (`ScreenUpdating` back on).
7. **No scratch document left open** — check the Window menu. The measuring
   document is hidden but it would still be listed.
8. `LingTeXToggleRewrapOnSelectionChange`, then click in and out of an example
   → it re-wraps on leaving, does not recurse, and typing stays responsive. Run
   it again to turn it off; it is off by default for a reason.

---

## After a ribbon change

The ribbon lives in the engine file, injected from `src/customUI14.xml` with
its icons from `src/icons/`, so a change to either reaches Word only by
re-injection with Word quit:

```bash
sh LingTeX-Word/tools/install-dev-template.sh
```

then start Word and run the runner. The six settings buttons are toggles
that show their state; the state is the active document's, refreshed
whenever a setting or the active document changes. If they stop following
changes, the VBA project was reset (an untrapped error, Run → Reset) and the
ribbon handle with it: restart Word.

## If the engine will not compile at Word start

"Compile error in hidden module: modLingTeX" (or another module) at every
Word start, load, unload and command means the engine on disk holds a module
Word cannot compile, and Word cannot be got past the dialog to repair it.
Save your documents, then:

```bash
sh LingTeX-Word/tools/run-in-word.sh --fresh
```

It quits Word, hides the engine while Word starts so nothing loads, puts it
back, and imports the current `src/` into it as a document, where nothing
compiles until it has been replaced; then loads it and runs the suites. With
the dev template's current `AutoExec` this cannot recur: the engine is only
loaded at Word start when the last run was green (`build/engine-ok`).

## Known, and accepted for now

- **Re-wrap All over twenty examples takes a few seconds with the busy
  cursor.** VBA has no thread to keep the window live; the status bar shows
  "re-wrapping example n of N" meanwhile. A progress dialog is a later
  refinement; the wait itself is measurement, and is what the width cache is
  for.
- **Split happens at the first boundary only**, on every tier at once. Split
  the right half again for three columns.

## If something fails

Give the check's own wording and what you saw instead. If a dialog appeared,
its exact text. If it is a layout problem, a screenshot of the example is worth
more than a description.

If a VBA error dialog appears, the editor will be sitting on the offending line
with the window title reading `[break]`; the line and the message together are
usually enough. Click OK, then **Run → Reset** before running anything else —
while it is in break mode no macro can run at all, including the test runner.
