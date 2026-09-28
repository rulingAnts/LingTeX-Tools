# FLEx Parsing Fix — Context Prompt

**Project:** LingTeX Tools (`/Users/Seth/GIT/LingTeX-Tools`) — a JS web app / browser extension / Tauri desktop app that converts FLEx (FieldWorks Language Explorer) interlinear data to LaTeX (`\gll` blocks) and to word-collapsed TSV.

**Task:** Fix the FLEx parsing and rendering pipeline. Both LaTeX and TSV output are currently broken for real-world FLEx clipboard data. The bug is architectural — the parsing approach is wrong — not cosmetic. This prompt contains everything needed to implement the correct fix.

---

## The actual FLEx clipboard format

When FLEx copies interlinear text to the clipboard it produces **tab-separated columns**. Each non-empty column holds one morpheme form (or its gloss, depending on the tier). The key rules:

1. **Each column = one morpheme slot.** Columns are aligned across tiers: Morphemes[col N] corresponds to LexGloss[col N].
2. **Empty morpheme columns are either:**
   - A "gloss-continuation" slot — when the preceding non-empty morpheme's *own* gloss column is empty. The gloss from this slot belongs to the preceding morpheme's word.
   - A "zero-morpheme" standalone word slot — when the preceding morpheme's own gloss column is *non-empty*. This slot gets its own cell in the output (empty form, non-empty gloss).
3. **Morpheme boundary markers are embedded as *prefixes* on the morpheme text**, not standalone columns. Examples: `=ve` (the `=` is the boundary, `ve` is the morpheme), `=zi`, `=xo`. There is no format like `levo | = | zi` — the actual format is `levo | =zi` (boundary attached to the enclitic).
4. **Tier labels:** The `Morphemes` row label may appear at absolute column 0. The `Lex. Gloss` row may have a leading tab (label at absolute column 1). When aligning columns across tiers, strip the label and treat the *data* columns 0-indexed.
5. **Free translation:** Lines starting with `Free` (or a language tag after `Free`) are free-translation text, not interlinear tiers.
6. **Blocks:** Multiple examples are separated by blank lines, or by a line that starts with a new example number: a FLEx Print View copy of consecutive lines has no blank line between them. Each block starts with an optional example number (digits, `1.1` style allowed).
8. **Prefixes and proclitics:** a morpheme whose form ENDS with a boundary character (`ka=`, `un-`) is joined to the morpheme after it, its host, as a leading boundary joins a morpheme to the one before it. The boundary stays on the clitic's side on both tiers in a morpheme-aligned table (`ka=` over `DAT=`), and a boundary present on both sides of a seam is written once in a word-aligned cell (`ka=` + `=be` is `ka=be`, not `ka==be`).
10. **Free, Lit. and Note lines:** FLEx writes `MARK Free SPACE MARK MARK text` for one writing system and `MARK Free SPACE MARK Eng MARK SPACE MARK MARK text` for the first of several, a further one being `MARK SPACE MARK Ind MARK SPACE MARK MARK text` (MARK is U+200E, or U+200F right-to-left). The text is what follows the last pair of adjacent marks. Without marks (Graphite on), a code follows the label only when a further-language line follows, starting with a space; the first word of the text is never taken for a code by its shape.
11. **Tier labels with a writing-system code, and every line type:** the label cell may read `Lex. Gloss Eng` or `Morphemes xyz-ort`, base label and code separated by a space. Every row is kept, in FLEx's order. The first Morphemes row gives the segments and so the columns; a further Morphemes row, a further Lex. Gloss row and `Lex. Gram. Info.` are laid out on those segments (a gloss-like row takes the segments' boundary characters where it has a piece, a form row carries its own); `Word`, `Word Gloss` and `Word Cat.` are laid out per word span; glossing the words as written, they carry no morpheme boundary and take no part in the break-character agreement, its repair, or a split's precondition (they stay whole on the left). A partly filled column is judged on the segmented form row and the first gloss row only: a further gloss row may be sparse.
12. **A copied baseline establishes the columns:** when a `Word` line is present, its non-empty cells start the word spans and its empty cells continue them; every row is laid out on those spans. The baseline itself is not segmented: it takes no part in the break-character checks, keeps any space it has, and a split leaves it whole in the left-hand column.
9. **Ownership of a boundary across a fold and a split:** folding two cells into one word-aligned cell writes U+2060 WORD JOINER right after a boundary the left morpheme owns (`be=⁠dai`), and on both sides of one that both own (`ka⁠=⁠be`); a split reads it, hands the boundary back to its owner, and consumes it, so By Word and By Morpheme round-trip losslessly. Exports strip the mark, and LingTeX-Word never writes it to the page: there the boundary glyph carries a character style (`LingTeX Left Boundary`, `LingTeX Shared Boundary`) and read-back restores the mark from it, so Find matches the plain spelling. A boundary with no mark stays the right-hand morpheme's.
7. **Trailing cells and the section sign:** trailing tabs are columns and are never stripped (only trailing spaces are). A cell that is exactly `§`, FLEx's end-of-segment sign, is dropped, and a column that is empty on every tier is dropped with it.

---

## Concrete example — Example 1

**Raw input (tabs shown as `→`):**
```
Morphemes→z→zuvo→ixo→→vu→=ve→levo→→→=zi→zo→z→zuvo
→Lex. Gloss→1SG→dream→DEM→***→fox→ERG→→follow→.CMP→REL→FOC→1SG→dream
Free Concerning what I'm dreaming about, Voxi getting followed by a fox is what I'm dreaming about.
```

**Data columns (0-indexed, after stripping labels):**

| Col | Morpheme | LexGloss |
|-----|----------|---------|
| 0 | `z` | `1SG` |
| 1 | `zuvo` | `dream` |
| 2 | `ixo` | `DEM` |
| 3 | *(empty)* | `***` |
| 4 | `vu` | `fox` |
| 5 | `=ve` | `ERG` |
| 6 | `levo` | *(empty)* |
| 7 | *(empty)* | `follow` |
| 8 | *(empty)* | `.CMP` |
| 9 | `=zi` | `REL` |
| 10 | `zo` | `FOC` |
| 11 | `z` | `1SG` |
| 12 | `zuvo` | `dream` |

**Expected TSV output:**
```
z	zuvo	ixo		vu=ve	levo=zi	zo	z	zuvo
1SG	dream	DEM	***	fox=ERG	follow.CMP=REL	FOC	1SG	dream
Concerning what I'm dreaming about, Voxi getting followed by a fox is what I'm dreaming about.
```

**Expected LaTeX output** (tokens matter; exact wrapping is secondary):
```
\gll z zuvo ixo {} vu=ve levo=zi zo z zuvo \\
     1SG dream DEM *** fox=\gl{erg} follow.CMP=\gl{rel} \gl{foc} 1SG dream \\
\glt '...'
```

---

## The word-grouping algorithm

Process **data columns** (0 to N-1) left to right. Maintain a `currentWord = {form, glossParts[]}`.

```
MORPH_DIVS = '-=~<>'

for col = 0..N-1:
  m = morpheme[col]        // may be empty string
  g = lexGloss[col]        // may be empty string

  if m is non-empty:
    boundary = m[0] if m[0] in MORPH_DIVS else ''
    suffix   = m[1:] if boundary else m

    if boundary != '':
      # Attach to current word (enclitic/suffix boundary)
      currentWord.form += boundary + suffix
      if g != '': currentWord.glossParts.push(boundary + g)
      else:       currentWord.glossParts.push(boundary)

    else:
      # Start a new word (regular morpheme)
      emit(currentWord)   # flush previous word if any
      currentWord = { form: m, glossParts: [g] if g != '' else [] }

      # If direct gloss is empty, collect gloss from following empty-morpheme columns
      if g == '':
        while (col+1 < N) and morpheme[col+1] == '':
          col++
          if lexGloss[col] != '': currentWord.glossParts.push(lexGloss[col])
        # Loop stops at the next non-empty morpheme column
        # (processed normally in the outer loop — either attach or new word)

  else:  # m is empty
    # Zero-morpheme standalone word slot
    emit(currentWord)
    emit({ form: '', gloss: g })
    currentWord = null

emit(currentWord)   # flush last word
```

**Key rules from the algorithm:**

- Col 3 (`ixo` has direct gloss `DEM` = *non-empty*): the following empty col 3 is a standalone zero-morpheme slot → form=`""`, gloss=`***` ✓
- Col 6 (`levo` has direct gloss *empty*): collect cols 7,8 → gloss parts = `["follow", ".CMP"]` → then col 9 `=zi` attaches → form=`levo=zi`, gloss=`follow.CMP=REL` ✓
- Col 1 in Ex. 2 (`vimo` has direct gloss *empty*): collect cols 2,3 (`pick`, `.CMP`) → gloss=`pick.CMP` ✓

**Standalone punctuation:** A morpheme that is a single punctuation character (`:`, `,`, etc.) with an empty gloss should be appended to the preceding word's *form only* (no gloss contribution). E.g. `ze` + `:` → form=`ze:`, gloss unchanged (`ACMP`).

---

## Gloss assembly

The `glossParts` array is joined as a plain string: `glossParts.join('')`. For LaTeX output, run `wrapGlosses()` on each non-boundary part. For TSV output, no LaTeX wrapping.

Examples:
- `["fox", "=", "ERG"]` → `fox=ERG` (TSV), `fox=\gl{erg}` (LaTeX)
- `["follow", ".CMP", "=", "REL"]` → `follow.CMP=REL` (TSV), `follow.CMP=\gl{rel}` (LaTeX)
- `["1SG"]` → `1SG` (TSV), `\gl{1sg}` (LaTeX)

---

## Architecture: what needs to change

**Current (broken) architecture:**
- `parseFLExBlock()` in `docs/core.js` converts `\t→space`, then uses `massageLine()` (a regex-based sentinel injector) to produce space-separated token arrays for each tier. This destroys the column alignment information and misidentifies boundary characters.
- `renderFLEx()` and `renderFLExTSV()` work from these token arrays and use a `lexGlossOffset` counter to re-align glosses. This approach cannot work correctly with the actual FLEx format.

**What was most recently attempted (also broken):** A `flexTabLineToks()` function was added to `parseFLExBlock` that detects tabs and tries to parse per-line with a run-based grouping algorithm. This is wrong because it assumes boundary markers are in *standalone* columns (`levo | = | zi`), whereas the actual format has them *prefix-attached* to morphemes (`levo | =zi`). The function exists in the file as of the latest commit but must be replaced entirely.

**Correct approach — replace `parseFLExBlock` and both renderers.**

Make `parseFLExBlock` return **raw column arrays** (not token arrays), then rewrite the renderers to run the word-grouping algorithm:

```js
// New parseFLExBlock return structure:
{
  lineTypes:  string[],     // tier labels: ['Morphemes', 'LexGloss', ...]
  colArrays:  string[][],   // colArrays[tierIdx][colIdx] = cell value ('' if empty)
  freeLines:  string[],
  lineNum:    string | null
}
```

The renderers then:
1. Find `morphIdx` and `lexGlossIdx` from `lineTypes`
2. Run the word-grouping algorithm over `colArrays[morphIdx]` and `colArrays[lexGlossIdx]` simultaneously
3. Produce the output from the resulting word slots

---

## Files to change

| File | Change needed |
|------|---------------|
| `docs/core.js` | Replace `parseFLExBlock` (remove tab→space, remove `massageLine` for tab input, return column arrays). Replace `renderFLEx` and `renderFLExTSV` with column-aware renderers. Remove `flexTabLineToks` (it is wrong). The `massageLine` function can remain for the space-separated fallback path. Remove `_flexTabLineToks` from the exports at the bottom of the file. |
| `tauri/src-tauri/src/convert.rs` | Port the same changes. The `flex_tab_line_toks` function added recently should also be removed/replaced. |

`renderFLExXlist`, `renderFLExAuto`, `renderFLExTSVAuto`, `parseFLExBlocks` are higher-level wrappers and should need minimal changes once the core functions work correctly.

---

## Example 2 for verification

**Input:**
```
Morphemes→zel→vimo→→→rixu→→→=xo→xu→=zevi→Ozivela→ze→:→zel→vimo→→→rixu→→→=xo→Vo→vu→=ve→levo→→→=zi→zo→z→zuvo→=ve→=zi
→Lex. Gloss→yam→→pick→.CMP→→stack→.CMP→SEQ→3SG→all→P.N.→ACMP→→yam→→pick→.CMP→→stack→.CMP→SEQ→P.N.→fox→ERG→→follow→.CMP→REL→FOC→1SG→dream→ABL→REL
Free (When) she picked her yams (early)--that is, all of them--her with Xelvio, when they picked the yams and then Voxi was followed by a fox is what I'm dreaming about.
```

**Expected TSV output:**
```
zel	vimo	rixu=xo	xu=zevi	Ozivela	ze:	zel	vimo	rixu=xo	Vo	vu=ve	levo=zi	zo	z	zuvo=ve=zi
yam	pick.CMP	stack.CMP=SEQ	3SG=all	P.N.	ACMP	yam	pick.CMP	stack.CMP=SEQ	P.N.	fox=ERG	follow.CMP=REL	FOC	1SG	dream=ABL=REL
(When) she picked her yams (early)--that is, all of them...
```

---

## Example 3 for verification

A gloss spread over the cells AFTER its morpheme's, at the END of the row: the
morpheme's own gloss cell is empty, the pieces follow under empty morpheme
cells, and the morpheme row ends in those empty cells. FLEx copies this shape
for the last morpheme of a line (seen live 2026-09-28). The trailing tabs are
columns; stripping them loses the gloss.

**Input:**
```
Morphemes→vu→=ve→zo→zuvo→→
→Lex. Gloss→fox→ERG→dream→→follow→.CMP
Free The fox's dream was followed.
```

**Expected TSV output:**
```
vu=ve	zo	zuvo
fox=ERG	dream	follow.CMP
The fox's dream was followed.
```

---

## Example 4 for verification

The same spread, after a CLITIC: the enclitic's own gloss cell is empty and
its gloss pieces follow under empty morpheme cells that end the row. They
belong to the clitic, joined behind its boundary character, not to standalone
zero-morpheme slots (seen live 2026-09-28: one column, `hi=di` over
`come.CMP=BNDRY.CMP`, in a real copy of that shape).

**Input:**
```
Morphemes→vu→=ve→zo→=zi→→
→Lex. Gloss→fox→ERG→dream→→follow→.CMP
Free The fox dreamt of following.
```

**Expected TSV output:**
```
vu=ve	zo=zi
fox=ERG	dream=follow.CMP
The fox dreamt of following.
```

---

## Example 5 for verification

A proclitic before an enclitic, a proclitic before a stem whose gloss is spread,
then a suffix and an enclitic. The trailing boundary of `xu=` and `ze=` joins the
next morpheme; the seam between `xu=` and `=ve` carries one boundary.

**Input:**
```
Morphemes→xu=→=ve→zo→ze=→zuvo→→→-a→=zi
→Lex. Gloss→3SG→ERG→dream→DAT→→follow→.CMP→lnk→REL
Free She dreamt of following him.
```

**Expected TSV output:**
```
xu=ve	zo	ze=zuvo-a=zi
3SG=ERG	dream	DAT=follow.CMP-lnk=REL
She dreamt of following him.
```

---

## Example 6 for verification

A copied baseline (`Word`), one writing system. The baseline's words are the
columns: `ve` and `te` are words of their own, `zuvoa` spans a morpheme and its
spread gloss and a suffix. A number cell, and the end-of-segment sign.

**Input:**
```
1.1→Word→vu→ve→zo→zuvoa→→→→te→§
→Morphemes→vu→=ve→zo→zuvo→→→-a→=te→
→Lex. Gloss→fox→ERG→dream→→follow→.CMP→lnk→SEQ→
Free The fox dreamt of following and then
```

**Expected TSV output:**
```
vu	ve	zo	zuvoa	te
vu	=ve	zo	zuvo-a	=te
fox	=ERG	dream	follow.CMP-lnk	=SEQ
The fox dreamt of following and then
```

## Example 7 for verification

Everything a copy may hold: two writing systems on the Morphemes line, two
analysis languages on the Lex. Gloss line, Lex. Gram. Info., Word Gloss in
two languages, Word Cat., and two free translations, without marks (the
further-language line starts with a space). The second gloss row is sparse.

**Input:**
```
1.1→Word→vu→ve→zo→zuvoa→→→→te→§
→Morphemes xyz→wu→=we→so→suwo→→→-a→=tee→
→Morphemes xyz-ort→vu→=ve→zo→zuvo→→→-a→=te→
→Lex. Gloss Eng→fox→ERG→dream→→follow→.CMP→lnk→SEQ→
→Lex. Gloss Ind→→→mimpi→→→.CMP→→→
→Lex. Gram. Info. Eng→n→adp→n→v→→→v:(lnk)→cosub→
→Word Gloss Eng→fox→by→dream→followed→→→→then→
→Word Gloss Ind→rubah→oleh→mimpi→diikuti→→→→lalu→
→Word Cat. Eng→n→adp→n→v→→→→cosub→
Free Eng The fox dreamt of following and then
 Ind rubah mimpi ikut lalu
```

**Expected TSV output:**
```
vu	ve	zo	zuvoa	te
wu	=we	so	suwo-a	=tee
vu	=ve	zo	zuvo-a	=te
fox	=ERG	dream	follow.CMP-lnk	=SEQ
		mimpi	.CMP	
n	=adp	n	v-v:(lnk)	=cosub
fox	by	dream	followed	then
rubah	oleh	mimpi	diikuti	lalu
n	adp	n	v	cosub
The fox dreamt of following and then / rubah mimpi ikut lalu
```

---

## What to verify after implementing

1. Both examples above produce the expected TSV output exactly.
2. The LaTeX output for Example 1 has correct word tokens and gloss tokens (with `\gl{}` wrapping on abbreviations).
3. `parseFLExBlocks` (multi-block parser) still works — it calls `parseFLExBlock` repeatedly on chunks split by blank lines.
4. The Rust port (`convert.rs`) produces identical results.
5. `docs/core.js` exports still include `parseFLExBlock`, `renderFLEx`, `renderFLExTSV`, and the other public API functions.
6. After the fix, run `git push origin main:webProduction` to update the live site.
