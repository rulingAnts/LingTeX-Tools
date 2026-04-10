# FLExToWord VBA Macro — Test Checklist

Each test gives sample FLEx clipboard text to paste into Word, the macro to run, and what to verify in the output.  
**Paste each sample as plain text** (Ctrl+Shift+V or Paste Special → Unformatted Text), select it, then run `FLExTextToWord`.

---

## 1. Basic 2-Tier (Word + WordGloss)

**Input** (select all 2 lines):
```
Word the dog bit him
WordGloss DEF.ART dog bite.PST 3SG.OBJ
```

**Expected output — one `<m:oMath>` per word (5 frames total):**
- [ ] Five inline equation matrices in one paragraph
- [ ] Row 1 (vernacular): *the*, *dog*, *bit*, *him* — **italic**, correct font
- [ ] Row 2 (gloss): `def.art`, `dog`, `bite.pst`, `3sg.obj` — stored lowercase, displayed as **small caps** (via `w:smallCaps`)
- [ ] `dog` and `bite.pst` portions: `dog` is lowercase → normal weight (not small caps); `.` and `pst` in `bite.pst` — `pst` should be small-capped since all caps; `.` is a delimiter
- [ ] Spaces between frames are ordinary Word spaces, not part of the equations
- [ ] No Cambria Math font anywhere — all cells use the surrounding paragraph font

---

## 2. Basic 2-Tier — Capitalization of First Word

**Input:**
```
Word the pig attacked suuh
WordGloss DEF pig attack.PST P.N.
```

**Expected:**
- [ ] First vernacular word capitalized: *The* (not *the*)
- [ ] All other words unchanged

---

## 3. Morpheme-Level: Simple Affixation

**Input:**
```
Morphemes kata -bi -di
LexGloss go DIST NFUT
```

**Expected:**
- [ ] Three frames: one per WORD GROUP (not per morpheme)
- [ ] Frame 1 vernacular row: *kata-bi-di* (morphemes collapsed, dividers kept) — **italic**
- [ ] Frame 1 gloss row: `go-dist-nfut` — `dist` and `nfut` in **small caps**, `-` delimiters in normal weight
- [ ] Frame 2 vernacular: *-bi* — italic (leading dash retained)
- [ ] Frame 2 gloss: `-dist` — dash normal, `dist` small caps

> **Note:** FLEx clipboard uses `Morphemes` for morpheme-break lines. Verify the ░-sentinel-based collapse is working correctly by checking that word groups are NOT split into per-morpheme matrices.

---

## 4. Morpheme-Level: Enclitics with `=`

**Input:**
```
Morphemes di =de deda =di
LexGloss pig =ERG attack.CMP =REL
```

**Expected:**
- [ ] Two frames (two word groups separated by space)
- [ ] Frame 1 vernacular: *di=de* — italic
- [ ] Frame 1 gloss: `pig=erg` — `pig` normal, `=` normal, `erg` **small caps**
- [ ] Frame 2 vernacular: *deda=di* — italic
- [ ] Frame 2 gloss: `attack.cmp=rel` — `attack` normal, `.` normal, `cmp` small caps, `=` normal, `rel` small caps

---

## 5. Morpheme-Level: Multi-Morpheme Word Group (Prefix + Root + Suffix)

**Input:**
```
Morphemes saud -o =ia -di
LexGloss bark INCMP =SIM CMP
```

**Expected:**
- [ ] One frame (all four morphemes form one word group)
- [ ] Vernacular row: *saud-o=ia-di* — italic
- [ ] Gloss row: `bark-incmp=sim-cmp` — `bark` normal; `incmp`, `sim`, `cmp` in **small caps**; `-` and `=` normal

---

## 6. Three-Tier: Word + Morphemes + LexGloss

**Input:**
```
Word kata-bi-di
Morphemes kata -bi -di
LexGloss go DIST NFUT
```

**Expected:**
- [ ] One frame with **three rows**
- [ ] Row 1 (Word): *kata-bi-di* — italic
- [ ] Row 2 (Morphemes): *kata-bi-di* — italic (also vernacular tier index > 0? No — Row 0 = first line, so this should also be italic since t=0 is `Word`, t=1 is `Morphemes`)

> **⚠ Check:** Rows 1 and 2 are both italic because t=0 is the first line. Rows beyond t=0 get the gloss treatment. Confirm whether the Morphemes row is italic (t=1 → gloss treatment) or not. Expected: Morphemes row gets small-caps treatment applied — since morphemes are typically displayed in the vernacular script, this may need adjustment in your template styles.

---

## 7. Four-Tier: Word + Morphemes + LexGloss + WordGloss

**Input:**
```
Word di deda bu
Morphemes di deda =di bu
LexGloss pig attack.CMP =REL FOC
WordGloss the.pig attacked-REL FOC
```

**Expected:**
- [ ] Three frames (one per word)
- [ ] Four rows per frame
- [ ] Row 0 (Word): italic
- [ ] Row 1 (Morphemes): gloss treatment (small caps on all-caps tokens)
- [ ] Row 2 (LexGloss): gloss treatment with assembled morpheme glosses
- [ ] Row 3 (WordGloss): gloss treatment

---

## 8. WordCat Line

**Input:**
```
Word the dog barked
WordGloss DEF dog bark.PST
WordCat DET N V
```

**Expected:**
- [ ] Three frames, three rows each
- [ ] WordCat row: `det` **small caps**, `n` **small caps**, `v` **small caps**

> **Note:** Single capital letters (N, V) — verify whether `IsGrammatical` correctly handles single-character glosses. By the LO macro rules, a single capital letter alone is NOT small-capped (it's excluded). Check: does `N` become small caps or stay normal? Per the LO regex exclusion, single capital letters should stay normal.

---

## 9. Free Translation Line

**Input:**
```
Word the pig attacked suuh
WordGloss DEF pig attack.PST P.N.
Free The pig attacked Suuh.
```

**Expected:**
- [ ] IGT paragraph: two-row frames for each word
- [ ] Free translation appears as a **separate paragraph** below, in the `Ex. Trans.` style (or whatever `STYLE_FREE_TRANS` is set to)
- [ ] Free translation text: *'The pig attacked Suuh.'* — wrapped in typographic single quotes (' ')
- [ ] Free translation: NOT italic, NOT small caps, correct font

---

## 10. Multiple Free Translation Lines

**Input:**
```
Word kata-bi-di
LexGloss go.DIST.NFUT
Free He went far away.
Free (lit. go-distributive-nonfuture)
```

**Expected:**
- [ ] Two separate free translation paragraphs below the IGT line
- [ ] Each wrapped in ' … '
- [ ] Both in `STYLE_FREE_TRANS` style

---

## 11. Small Caps — Boundary Cases

Test these gloss tokens individually (put them as the WordGloss line):

| Token | Expected |
|---|---|
| `FOC` | small caps (`foc`) |
| `3SG` | small caps (`3sg`) — digit-initial |
| `3sg` | **NOT** small caps (has lowercase) — normal |
| `bark` | NOT small caps |
| `P.N.` | NOT small caps — matches "A." exclusion pattern (single cap + period) |
| `N.` | NOT small caps |
| `A.` | NOT small caps |
| `DIST` | small caps |
| `attack.CMP` | `attack` normal, `.` normal, `CMP` small caps |
| `=ERG` | `=` normal, `erg` small caps |
| `1s.POSS` | `1s` small caps (digit-initial), `.` normal, `poss` small caps |

**Input to test all at once:**
```
Word a b c d e f g h i j k
WordGloss FOC 3SG 3sg bark P.N. N. A. DIST attack.CMP =ERG 1s.POSS
```

---

## 12. Punctuation Tucking

**Input:**
```
Word the dog , he said .
WordGloss DEF dog , 3SG say .
```

**Expected:**
- [ ] Commas and periods are tucked against the preceding word token (no space before them)
- [ ] `,` and `.` appear as their own frames OR are attached to the preceding word — verify this matches LO output

---

## 13. Font Detection

**Test A — Explicit font in surrounding context:**
1. Set your paragraph to use a specific font (e.g., Charis SIL)
2. Place cursor inside that paragraph
3. Select and run the macro
- [ ] All equation cells use Charis SIL, not Cambria Math or Times New Roman

**Test B — Theme font ("+Body"):**
1. Use the default paragraph style (which uses a theme font like "+Body")
2. Run the macro
- [ ] Macro falls back to document default font or `FALLBACK_FONT` constant
- [ ] No "+Body" or similar placeholder appears as a font name

**Test C — No font override:**
1. Set `FALLBACK_FONT = "Charis SIL"` in the module constants
2. Run in a document with no explicit font set
- [ ] Charis SIL is used throughout

---

## 14. LexEntries Line (alternative to Morphemes)

**Input:**
```
LexEntries di =de
LexGloss pig =ERG
```

**Expected:**
- [ ] Same behavior as `Morphemes` line — collapse and assemble
- [ ] One frame: vernacular *di=de*, gloss `pig=erg`

---

## 15. Error and Edge Cases

**Test A — Nothing selected:**
- Run macro with no text selected
- [ ] Dialog: "Please select the FLEx interlinear text first."

**Test B — Unrecognized line type:**
```
Word the dog
Gloss DEF dog
```
- [ ] Dialog: "Unrecognised line type: Gloss" with list of valid types

**Test C — LexGloss without morpheme line:**
```
Word the dog
LexGloss DEF dog
```
- [ ] Dialog: "The Lex. Gloss line requires a Morpheme or Lex. Entries line."

**Test D — First line is a gloss line:**
```
WordGloss DEF dog
Word the dog
```
- [ ] Dialog: "First line must be a Word, Morphemes, or Lex. Entries line."

**Test E — Leading paragraph number:**
```
1. Word the dog
1. WordGloss DEF dog
```
- [ ] Paragraph number stripped; macro runs normally

**Test F — Empty Free line:**
```
Word the dog
WordGloss DEF dog
Free
```
- [ ] LO macro would show an error for this. Check Word macro behavior — does it produce an empty quoted paragraph or error?

---

## 16. Undo

After running the macro:
- [ ] Ctrl+Z undoes the entire insertion in one step (or a small number of steps)
- [ ] Document returns to the original selected FLEx text

---

## 17. Cursor Position After Insertion

- [ ] After running, cursor is positioned after the last inserted paragraph (free translation or IGT line)
- [ ] Ready to continue typing without manual repositioning

---

## 18. Comparison with LibreOffice Output

For a definitive check, run the same FLEx clipboard text through both the LO macro and the Word macro, then compare:

- [ ] Same number of frames (one per word group)
- [ ] Same text content in each frame (vernacular and gloss rows)
- [ ] Vernacular rows are italic in both
- [ ] Same tokens are small-capped in both
- [ ] Morpheme dividers (-, =, ~) appear in the same positions in both
- [ ] Free translation text is identical (modulo quote style differences)

**Recommended comparison example** (uses morpheme splits, enclitics, and grammatical glosses):
```
Morphemes di =de deda =di bu
LexGloss pig =ERG attack.CMP =REL FOC
Free The pig attacked [him], you see.
```

---

## Known Limitations / Not Yet Implemented

- **`ReplaceGlossWord`**: Uses document-wide Find/Replace (not scoped to interlinear frames). Review results after each replacement.
- **`SmallCapsGlosses` bulk reformat**: Not implemented — formatting is applied at insertion time only.
- **`tabbedTextToFrames` equivalent**: No port of the tab-delimited input variant.
- **Floating punctuation handling**: The LO macro has special handling for punctuation-only tokens on the first line (e.g., dashes between words). This is not yet implemented in the Word version.
- **`sillyFreeTranslationBusiness`**: The LO macro detects "a." set-style examples and switches the free translation style. The Word macro always uses `STYLE_FREE_TRANS`.
- **`FixFrameBug`**: LO-specific, no Word equivalent needed.

---

## Next Steps: Packaging for Distribution

Once testing is complete, the macro can be packaged so users never need to open the VBA editor. The install process becomes: download two files, double-click one, restart Word.

### Step 1 — Create `FLExToWord.dotm`

In Word:
1. File → New → Blank Document
2. Define all required paragraph styles (`Ex.`, `Ex. Trans.`, etc.) to match your LO template
3. Alt+F11 → Insert → Module → paste the contents of `FLExToWord.bas`
4. File → Save As → **Word Macro-Enabled Template (`.dotm`)**

### Step 2 — Add a ribbon button (Custom UI Editor)

Download the free [Office RibbonX Editor](https://github.com/fernandreu/office-ribbonx-editor/releases) (no install required). This tool edits the hidden ribbon XML inside the `.dotm`:

1. Open `FLExToWord.dotm` in RibbonX Editor
2. Insert → Office 2010+ Custom UI Part
3. Paste this XML:

```xml
<customUI xmlns="http://schemas.microsoft.com/office/2009/07/customui">
  <ribbon>
    <tabs>
      <tab id="tabIGT" label="IGT">
        <group id="grpFLEx" label="FLEx Examples">
          <button id="btnFLExToWord"
                  label="Insert Interlinear"
                  screentip="Convert FLEx clipboard text to interlinear example"
                  supertip="Select FLEx-copied interlinear text, then click to convert it to aligned OMML frames."
                  size="large"
                  imageMso="InsertEquation"
                  onAction="FLExTextToWord"/>
          <button id="btnReplaceGloss"
                  label="Replace Gloss"
                  screentip="Replace a gloss throughout all interlinear examples"
                  size="normal"
                  imageMso="FindAndReplaceDialog"
                  onAction="ReplaceGlossWord"/>
        </group>
      </tab>
    </tabs>
  </ribbon>
</customUI>
```

4. Save. The "IGT" ribbon tab is now permanently embedded in the `.dotm`.

> The `onAction` values must exactly match the `Public Sub` names in `FLExToWord.bas`.

### Step 3 — Create `Install.vbs`

A ~30-line VBScript that:
- Copies `FLExToWord.dotm` into Word's STARTUP folder (`%AppData%\Microsoft\Word\STARTUP\`), where templates load automatically in every Word session
- Optionally writes one registry key to pre-approve the STARTUP folder as a Trusted Location, preventing Word's macro security warning
- Checks whether Word is currently open and prompts the user to close it first
- Shows a success message with next-step instructions

### Step 4 — Distribute

Ship a zip containing:
```
FLExToWord.dotm
Install.vbs
```

User steps:
1. Unzip both files to the same folder
2. Double-click `Install.vbs`
3. Restart Word
4. The "IGT" tab appears in the ribbon — done

### Step 5 — Macro security note

Word may show a yellow "Macros have been disabled" bar on first launch if the registry Trusted Location step in the installer doesn't match the user's Office version (the registry path contains `16.0`, which covers Office 2016, 2019, 2021, and Microsoft 365). If it appears, users click **Enable Content** once. After that it is remembered.

To eliminate this entirely, the `.dotm` can be **digitally signed** with a self-signed certificate (`makecert` or the Windows Certificate Manager), and users add it to their Trusted Publishers list — but this is more involved and probably unnecessary for a small, trusted-source distribution.

---

## Further Next Steps: Google Docs Port

Some target users use Google Docs. A Google Docs version is worth keeping as a planned second phase once the Word version is stable.

### Feasibility

Yes — Google Apps Script (JavaScript, runs in the browser) can manipulate Google Docs programmatically via the `DocumentApp` API and can add a custom menu to the Docs UI. The text parsing logic (the bulk of the work) is the same algorithm as `FLExToWord.bas` and ports directly to JavaScript.

### Architecture difference

Google Docs has no equation editor. The equivalent structure for IGT alignment is a **hidden-border table**: one column per word, one paragraph per tier within each cell. This is analogous to the shift from LO inline text frames to Word OMML matrices — a different frame mechanism, same logical layout. Formatting (italic, small caps) is applied via `setTextStyle()` calls on text ranges.

### Distribution advantage

A Google Workspace Add-on installs from a shareable link with one click and works on any OS including Chromebooks — no VBA editor, no STARTUP folder, no macro security prompts. This may matter for the target audience.

### Plan

- Complete and test the Word version first
- Port as `FLExToGoogleDocs.js` in a second phase, reusing the same parsing logic as a reference
- Publish as a Workspace Add-on for one-click install
