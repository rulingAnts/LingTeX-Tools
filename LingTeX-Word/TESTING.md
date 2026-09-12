# LingTeX-Word — test checklist

Three layers. The first two run here; the third needs real Word, on both
platforms, and is the only way to confirm the parts that touch the Word object
model.

Record results in the Windows and Mac columns as you go.

---

## 1. Automated — runs in this repository

```bash
node LingTeX-Word/tools/parity-test.js
python3 LingTeX-Word/tools/vba-lint.py
```

- [x] `parity-test.js` — 78 assertions pass. Golden vectors derived from
      `PROMPT.md` at run time, checked against both the expected output written
      in the spec **and** the live output of `docs/core.js`.
- [x] `vba-lint.py` — all 14 VBA sources pass: block balance, pure ASCII,
      `Option Explicit`, `Attribute VB_Name`, no Windows-only APIs, no
      non-short-circuit `And`/`Or` bounds guards.

---

## 2. VBA self-tests — run inside Word, both platforms

Import everything in `src/`, then in the Immediate window (**Ctrl+G**):

```
RunAllTests
```

| Group | Windows | Mac |
|---|---|---|
| Golden vectors — both `PROMPT.md` examples, word-aligned forms, glosses and free translation | ☐ | ☐ |
| Projections — morpheme-aligned satisfies break-char agreement; merging continuations reproduces word-alignment | ☐ | ☐ |
| Input routing — FLEx vs plain TSV; TSV round trip keeps its first column | ☐ | ☐ |
| Column split and merge — including the no-boundary case and the leading-boundary case | ☐ | ☐ |
| Leipzig checks — all six findings and both repairs | ☐ | ☐ |
| Grammatical-gloss detection — the boundary table, plus an unpublished abbreviation | ☐ | ☐ |
| Wrap planner — fit, overflow, over-wide column, pull-back-up, continuation columns | ☐ | ☐ |
| **Summary line reads `ALL PASS`** | ☐ | ☐ |

If anything fails here, stop — do not go on to section 3.

---

## 3. End to end in Word

Sample input for the whole of this section. Paste it into a document as **plain
text** (Ctrl+Shift+V / Paste Special → Unformatted Text) so the tabs survive,
or copy the equivalent selection out of FLEx.

```
Morphemes	zel	vimo			rixu			=xo	xu	=zevi	Ozivela	ze	ː	zel	vimo			rixu			=xo	Vo	vu	=ve	levo			=zi	zo	z	zuvo	=ve	=zi
	Lex. Gloss	yam		pick	.CMP		stack	.CMP	SEQ	3SG	all	P.N.	ACMP		yam		pick	.CMP		stack	.CMP	SEQ	P.N.	fox	ERG		follow	.CMP	REL	FOC	1SG	dream	ABL	REL
Free Eng (When) she picked her yams early.
```

### 3a. Inserting

| Check | Windows | Mac |
|---|---|---|
| Copy from FLEx, put the cursor in the document, run `LingTeXInsertInterlinear` → example appears at the cursor | ☐ | ☐ |
| Paste the text in, select it, run the same command → the selection is **replaced**, no stray paragraph left behind | ☐ | ☐ |
| Columns line up: each form sits directly above its gloss | ☐ | ☐ |
| No table borders visible | ☐ | ☐ |
| Grammatical glosses (`SEQ`, `ERG`, `FOC`, `3SG`) render as **small capitals**, each with a full-size first letter (`Erg`, `3Sg`; `LingTeXToggleGramGlossInitialCap` switches to uniform small caps); lexical glosses (`yam`, `pick`, `stack`) do not | ☐ | ☐ |
| The object-language row is italic and is **not** small-capped, even where a form is capitalised (`Ozivela`, `Vo`) | ☐ | ☐ |
| Free translation appears below the table in `LingTeX Free`, in single quotes, upright | ☐ | ☐ |
| `zeː` — the length mark is attached to the preceding form, not given its own column | ☐ | ☐ |
| `zuvo=ve=zi` — double enclitics stay in one column, gloss `dream=ABL=REL` | ☐ | ☐ |
| Run it with nothing on the clipboard and nothing selected → a clear message, no error dialog | ☐ | ☐ |
| Run it on prose that is not interlinear → a clear message explaining what was expected | ☐ | ☐ |
| The example is numbered `(1)` in the left margin of its first line, with the rest of the example and the translation indented to the text position; a second example is `(2)`; deleting the first renumbers the second to `(1)` | ☐ | ☐ |
| `LingTeXToggleExampleNumbers` → the next example inserted carries no number and no indent; existing ones keep theirs | ☐ | ☐ |
| Fonts come from the document, not Cambria Math or Times New Roman | ☐ | ☐ |
| **No file is written to disk at any point** (the Mac sandbox check) | ☐ | ☐ |

### 3b. Wrapping — the core behaviour

| Check | Windows | Mac |
|---|---|---|
| The long example above wraps onto two or more row groups **inside one table** | ☐ | ☐ |
| Nothing extends past the right margin | ☐ | ☐ |
| Vertical gap between wrap lines matches `LingTeX_LineGap` (default 6 pt) | ☐ | ☐ |
| **Narrow the margins**, run `LingTeXRewrapCurrent` → columns push down onto an extra wrap line | ☐ | ☐ |
| **Widen them back**, re-wrap → columns are **pulled back up** and the extra line disappears | ☐ | ☐ |
| Increase the **Normal style's** font size (the LingTeX styles inherit it) → re-wrap adds lines; decrease → re-wrap removes them. Direct formatting on cells is not part of the example and does not survive a re-wrap | ☐ | ☐ |
| Flip the page to landscape → re-wrap reflows; back to portrait → reflows back | ☐ | ☐ |
| Set the section to two text columns → re-wrap fits the column, not the page | ☐ | ☐ |
| Delete several columns, re-wrap → lines collapse correctly | ☐ | ☐ |
| Re-wrap an example that is already correct → **nothing visibly changes** (idempotent) | ☐ | ☐ |
| Re-wrap twice in a row → identical result | ☐ | ☐ |
| An example positioned across a page break does not split inside a stack of aligned cells | ☐ | ☐ |
| A single column wider than the whole text width gets its own line and wraps inside its cell rather than overflowing off the page | ☐ | ☐ |

### 3c. Morpheme alignment and the column invariant

| Check | Windows | Mac |
|---|---|---|
| Run `LingTeXAlignByMorpheme`, insert again → one column per morpheme | ☐ | ☐ |
| The morpheme-aligned version **wraps at word boundaries**: no wrap line begins with `=xo`, `=zevi`, `=ve` or `=zi` | ☐ | ☐ |
| Every enclitic column carries the `=` on **both** the form and the gloss row | ☐ | ☐ |
| On a word-aligned example, put the cursor in `rixu=xo` and run `LingTeXSplitColumn` → two columns, `rixu` / `stack.CMP` and `=xo` / `=SEQ` | ☐ | ☐ |
| After that split, the `=` leads the cell on **every** interlinear tier | ☐ | ☐ |
| The free translation is untouched by the split | ☐ | ☐ |
| The example still wraps correctly after the split | ☐ | ☐ |
| `LingTeXMergeColumns` with the cursor in `rixu` → merged back to `rixu=xo` / `stack.CMP=SEQ` | ☐ | ☐ |
| Select across three cells and merge → exactly those three become one | ☐ | ☐ |
| Split a column whose gloss has no matching break (e.g. form `zomu-xa`, gloss `gone`) → a message naming the tier; the gloss cell stays whole and the new column is empty for it; **nothing is guessed** | ☐ | ☐ |

### 3d. Checking and fixing

| Check | Windows | Mac |
|---|---|---|
| Type a space into an interlinear cell, run `LingTeXCheckExample` → reported, and the fix replaces it with `.` | ☐ | ☐ |
| A space in the **free translation** is not reported | ☐ | ☐ |
| Delete the `-` from one tier's cell in a split column → break-char agreement reported, and the fix restores it | ☐ | ☐ |
| Make two tiers claim different break characters (`-xa` over `=DIST`) → reported as a conflict and **not** silently changed | ☐ | ☐ |
| `rixu=xo` over `stack.CMP=SEQ` → **no** rule-2 warning (`.` and `:` are not morpheme breaks) | ☐ | ☐ |
| `rixu=xo` over `stack-CMP=SEQ` → rule-2 warning | ☐ | ☐ |
| An invented abbreviation such as `SUPEREL` gets small capitals and is **not** flagged as unknown | ☐ | ☐ |
| A clean example reports "No problems found." | ☐ | ☐ |
| Click into an interlinear cell and type `erg` at its start → Word does **not** capitalise it (AutoCorrect's sentence and table-cell capitalisation are off while the cursor is inside an example, and back on outside) | ☐ | ☐ |

### 3e. Round trip and persistence

| Check | Windows | Mac |
|---|---|---|
| **Save** the document → every example re-wraps automatically, with no visible cursor jump or flicker | ☐ | ☐ |
| The cursor is where it was before the save | ☐ | ☐ |
| Run `LingTeXToggleRewrapOnSave` → saving no longer re-wraps; run it again to turn it back on | ☐ | ☐ |
| Close and reopen the document, run `LingTeXRewrapAll` → examples are still recognised (the style tagging survived) | ☐ | ☐ |
| Small caps round-trip: re-wrap an example and confirm `ERG` is still `ERG`, not `erg` | ☐ | ☐ |
| Copy an example, paste it elsewhere in the document, re-wrap → both work independently | ☐ | ☐ |
| Paste an example into a **new** document → styles are recreated and it re-wraps | ☐ | ☐ |
| Change a table's style away from `LingTeX Interlinear` → `LingTeXRewrapAll` leaves it alone (the escape hatch) | ☐ | ☐ |
| Restyle the `LingTeX Gloss` paragraph style → **every** example in the document updates | ☐ | ☐ |
| Two examples with one empty paragraph between them, and two with only the translation between → `LingTeXRewrapAll` re-wraps both and deletes nothing | ☐ | ☐ |
| Re-wrap keeps an example's number; in a document with outline-numbered headings the example numbers are unaffected by the heading numbering and vice versa | ☐ | ☐ |
| Per-chapter restart: Format → Style → `LingTeX Example Number` → Modify, link level 1 to Heading 1 with no number text, put `(%2)` on level 2; `SetSettingNumberLevel ActiveDocument, 2`; new examples restart at each Heading 1 | ☐ | ☐ |
| `LingTeXConvertTableToIgt` on a plain two-row table → becomes an auto-wrapping example. A row merged into a single cell is taken as the free translation; with none, the command says so and how to add one | ☐ | ☐ |
| Our own TSV, copied out of a rendered example and pasted back in, reproduces the same grid | ☐ | ☐ |

### 3f. Undo and robustness

| Check | Windows | Mac |
|---|---|---|
| **Windows:** one Ctrl+Z undoes a whole insert | ☐ | n/a |
| **Mac:** one Cmd+Z undoes a whole insert — `Application.UndoRecord` **is** present on Mac Word 16.112 (probe section 12), so undo is single-step on both platforms | n/a | ☐ |
| Undo after a re-wrap restores the previous layout | ☐ | ☐ |
| A document with 20+ examples: `LingTeXRewrapAll` completes in a few seconds | ☐ | ☐ |
| `LingTeXRewrapAll` on a document with no examples → a clear message, no error | ☐ | ☐ |
| Each command run with the cursor **outside** any example → a clear message, no error | ☐ | ☐ |
| After any command, `Application.ScreenUpdating` is back on (the screen is not frozen) | ☐ | ☐ |
| No hidden scratch document is left open — check the Window menu | ☐ | ☐ |
| Run `LingTeXToggleRewrapOnSelectionChange`, then click in and out of an example → it re-wraps, does not recurse, and typing stays responsive | ☐ | ☐ |

---

## Known gaps in Phase 1

- No UserForm: input comes from the selection or the clipboard. See *Status* in
  `README.md` for why, and what Phase 2 adds.
- No ribbon until the `.dotm` is built; commands run from Alt+F8.
- The Word object model calls listed under *To verify on real Word* in
  `README.md` have documented fallbacks but have not been confirmed on a Mac.
