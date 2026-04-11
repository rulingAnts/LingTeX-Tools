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
3. **Morpheme boundary markers are embedded as *prefixes* on the morpheme text**, not standalone columns. Examples: `=de` (the `=` is the boundary, `de` is the morpheme), `=di`, `=te`. There is no format like `deda | = | di` — the actual format is `deda | =di` (boundary attached to the enclitic).
4. **Tier labels:** The `Morphemes` row label may appear at absolute column 0. The `Lex. Gloss` row may have a leading tab (label at absolute column 1). When aligning columns across tiers, strip the label and treat the *data* columns 0-indexed.
5. **Free translation:** Lines starting with `Free` (or a language tag after `Free`) are free-translation text, not interlinear tiers.
6. **Blocks:** Multiple examples are separated by blank lines. Each block starts with an optional example number (digits).

---

## Concrete example — Example 1

**Raw input (tabs shown as `→`):**
```
Morphemes→a→bujo→edi→→di→=de→deda→→→=di→bu→a→bujo
→Lex. Gloss→1SG→speak→DEM→***→pig→ERG→→attack→.CMP→REL→FOC→1SG→speak
Free Eng Concerning what I'm talking about, Suuh getting attacked by a pig is what I'm talking about.
```

**Data columns (0-indexed, after stripping labels):**

| Col | Morpheme | LexGloss |
|-----|----------|---------|
| 0 | `a` | `1SG` |
| 1 | `bujo` | `speak` |
| 2 | `edi` | `DEM` |
| 3 | *(empty)* | `***` |
| 4 | `di` | `pig` |
| 5 | `=de` | `ERG` |
| 6 | `deda` | *(empty)* |
| 7 | *(empty)* | `attack` |
| 8 | *(empty)* | `.CMP` |
| 9 | `=di` | `REL` |
| 10 | `bu` | `FOC` |
| 11 | `a` | `1SG` |
| 12 | `bujo` | `speak` |

**Expected TSV output:**
```
a	bujo	edi		di=de	deda=di	bu	a	bujo
1SG	speak	DEM	***	pig=ERG	attack.CMP=REL	FOC	1SG	speak
Concerning what I'm talking about, Suuh getting attacked by a pig is what I'm talking about.
```

**Expected LaTeX output** (tokens matter; exact wrapping is secondary):
```
\gll a bujo edi {} di=de deda=di bu a bujo \\
     1SG speak DEM *** pig=\gl{erg} attack.CMP=\gl{rel} \gl{foc} 1SG speak \\
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

- Col 3 (`edi` has direct gloss `DEM` = *non-empty*): the following empty col 3 is a standalone zero-morpheme slot → form=`""`, gloss=`***` ✓
- Col 6 (`deda` has direct gloss *empty*): collect cols 7,8 → gloss parts = `["attack", ".CMP"]` → then col 9 `=di` attaches → form=`deda=di`, gloss=`attack.CMP=REL` ✓
- Col 1 in Ex. 2 (`kudi` has direct gloss *empty*): collect cols 2,3 (`take`, `.CMP`) → gloss=`take.CMP` ✓

**Standalone punctuation:** A morpheme that is a single punctuation character (`:`, `,`, etc.) with an empty gloss should be appended to the preceding word's *form only* (no gloss contribution). E.g. `bi` + `:` → form=`bi:`, gloss unchanged (`ACMP`).

---

## Gloss assembly

The `glossParts` array is joined as a plain string: `glossParts.join('')`. For LaTeX output, run `wrapGlosses()` on each non-boundary part. For TSV output, no LaTeX wrapping.

Examples:
- `["pig", "=", "ERG"]` → `pig=ERG` (TSV), `pig=\gl{erg}` (LaTeX)
- `["attack", ".CMP", "=", "REL"]` → `attack.CMP=REL` (TSV), `attack.CMP=\gl{rel}` (LaTeX)
- `["1SG"]` → `1SG` (TSV), `\gl{1sg}` (LaTeX)

---

## Architecture: what needs to change

**Current (broken) architecture:**
- `parseFLExBlock()` in `docs/core.js` converts `\t→space`, then uses `massageLine()` (a regex-based sentinel injector) to produce space-separated token arrays for each tier. This destroys the column alignment information and misidentifies boundary characters.
- `renderFLEx()` and `renderFLExTSV()` work from these token arrays and use a `lexGlossOffset` counter to re-align glosses. This approach cannot work correctly with the actual FLEx format.

**What was most recently attempted (also broken):** A `flexTabLineToks()` function was added to `parseFLExBlock` that detects tabs and tries to parse per-line with a run-based grouping algorithm. This is wrong because it assumes boundary markers are in *standalone* columns (`deda | = | di`), whereas the actual format has them *prefix-attached* to morphemes (`deda | =di`). The function exists in the file as of the latest commit but must be replaced entirely.

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
Morphemes→dae→kudi→→→kada→→→=te→bo→=taha→Edefina→bi→:→dae→kudi→→→kada→→→=te→Su→di→=de→deda→→→=di→bu→a→bujo→=de→=di
→Lex. Gloss→dog→→take→.CMP→→carry→.CMP→SEQ→3SG→two→P.N.→ACMP→→dog→→take→.CMP→→carry→.CMP→SEQ→P.N.→pig→ERG→→attack→.CMP→REL→FOC→1SG→speak→ABL→REL
Free Eng (When) she took her dogs (hunting)--that is, the two of them--her with Ervina, when they took the dogs and then Suuh was attacked by a pig is what I'm talking about.
```

**Expected TSV output:**
```
dae	kudi	kada=te	bo=taha	Edefina	bi:	dae	kudi	kada=te	Su	di=de	deda=di	bu	a	bujo=de=di
dog	take.CMP	carry.CMP=SEQ	3SG=two	P.N.	ACMP	dog	take.CMP	carry.CMP=SEQ	P.N.	pig=ERG	attack.CMP=REL	FOC	1SG	speak=ABL=REL
(When) she took her dogs (hunting)--that is, the two of them...
```

---

## What to verify after implementing

1. Both examples above produce the expected TSV output exactly.
2. The LaTeX output for Example 1 has correct word tokens and gloss tokens (with `\gl{}` wrapping on abbreviations).
3. `parseFLExBlocks` (multi-block parser) still works — it calls `parseFLExBlock` repeatedly on chunks split by blank lines.
4. The Rust port (`convert.rs`) produces identical results.
5. `docs/core.js` exports still include `parseFLExBlock`, `renderFLEx`, `renderFLExTSV`, and the other public API functions.
6. After the fix, run `git push origin main:webProduction` to update the live site.
