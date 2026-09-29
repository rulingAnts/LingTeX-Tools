# LingTeX-Word User Guide

*Interlinear glossed text in Microsoft Word: aligned, numbered, and wrapped to the page for you.*

## What LingTeX-Word does

Linguists present example sentences as interlinear glossed text: the words of
the language on one line, a gloss under each word, and a free translation
underneath. In a word processor that alignment is fragile. A tab stop moves,
a font changes, the margins change, and every column slides.

LingTeX-Word draws each example as a **borderless Word table**, one column per
alignment slot and one row per tier, and takes care of the rest:

- It takes an example from a **FLEx copy**, from tab-separated rows, from an
  ordinary Word table, or from lines you typed (see Getting an example onto
  the page). From FLEx, every line it recognises that has text keeps its row, in FLEx's order, and the Free, Lit. and Note lines go under the table (see From FLEx). FLEx's Word line, when it is
  copied, decides where each word begins.
- The example **wraps to the page**. When it is too wide, columns move down
  onto a second line, each form still directly above its gloss; when there is
  room again they move back up.
- It **re-wraps by itself** when the cursor leaves an example you edited
  and when the document is saved, and on demand from the ribbon. Leaving an example you did not edit, or saving, redraws only an example whose layout would change, for instance after a margin moved, or that has a space typed in a cell. An automatic re-wrap that
  would change nothing writes nothing, so it adds nothing to the Undo list.
- Every command that changes the page is **one step in Word's Undo list**,
  including the LingTeX styles a first insert creates: one Undo takes it all
  back, and one Redo puts it back, numbered and styled. (Resetting styles,
  with Reset Styles or the Settings dialog's reset buttons, is not one step
  yet: see Known issues.)
- Grammatical glosses (`ERG`, `3SG`, `PST`) are set in **small capitals**. By
  default **First Capital** keeps the first letter full-size (`Erg`, `3Sg`);
  turn it off for uniform small capitals, the way the Leipzig Glossing Rules
  print them. Switching it re-wraps every example in the document at once.
- Examples are **numbered** with Word's own numbering, so they renumber when
  one is deleted or moved, and cross-references can point at them. Several
  examples from one FLEx copy share one number, with a letter each (see
  Numbering).
- The glossing is **checked** against the conventions, and what has one right
  answer is repaired for you.

Everything it draws is ordinary Word: tables, styles and list numbering. So
the document reads and prints the same on a machine without the add-in.
Besides that it keeps only a few document variables in the file, its
settings among them, which Word does not show.

### One idea to hold on to

A column is an **alignment slot**, not a word. A column can hold a whole word,
a single morpheme, or part of a word, and one example may mix all three: you
can split one clitic out into a column of its own and leave the rest of the
sentence word-aligned. Two rules follow, and the add-in keeps both for you:

1. **No spaces inside a cell.** A space would let Word wrap the text inside
   the cell and break the alignment. Use `.` or `_` instead; a space you type
   is replaced with the character the document is set to.
2. **Break characters agree down a column.** If a cell begins with `-` or
   `=`, every other cell in that column does too, so a split-off suffix
   reads `-xa` over `-DIST`, never `-xa` over `DIST`. The same holds at the
   end of a cell, so a proclitic reads `ze=` over `DAT=`. A wrap line never
   starts on a column that begins with a break character, which continues
   the one before it, nor on the column after a prefix or proclitic, which
   is its host.

The free translation is prose and is exempt from both. FLEx's Word line,
when it is copied with the Morphemes line, is the words as written: it keeps
its spaces, as no-break spaces that never wrap inside a cell. That line and
the Word Gloss and Word Cat. lines, which gloss whole words, take no part in
rule 2.

## Installing

LingTeX-Word is one file, `LingTeX-Word.dotm`, a Word template that lives in
Word's Startup folder and loads at every start. Once it is there, every
document has an **Interlinear** tab on the ribbon. **Close Word before you
install.**

### Windows

1. Run `LingTeX-Word-Setup-...exe`. It is unsigned, so SmartScreen says
   "unknown publisher": choose *More info*, then *Run anyway*. It copies the
   template into `%APPDATA%\Microsoft\Word\STARTUP` and registers an
   uninstaller under Settings > Apps.
2. Start Word. A few seconds later a message names the version and lists its
   keyboard shortcuts (**Ctrl+Alt+Shift** and a letter). The Interlinear tab
   is on the ribbon.

The `-windows.zip` holds the same template with `install.bat`, for anyone who
prefers to see what the installer does. To remove the add-in, go to
Settings > Apps > LingTeX-Word > Uninstall, or delete the file from the
STARTUP folder.

### Mac

macOS no longer opens an installer downloaded from the internet unless it is
signed with a paid Apple developer certificate, which LingTeX-Word is not. So
on a Mac it is installed with one command in Terminal. The command runs
`install.sh`, which is on the disk image beside the template; open it in
TextEdit to read every step. **How to install on a Mac.txt** on the disk
image gives the same steps.

1. Open the `-macos.dmg`. If an older LingTeX-Word disk image is still open,
   eject it first: otherwise the new one shows as "LingTeX-Word 1" and the
   command below finds the old one.
2. Open Terminal (Applications > Utilities > Terminal). Type
   `cd /Volumes/LingTeX-Word` and press Return, then type `sh install.sh`
   and press Return. (Or type `sh` and a space, drag `install.sh` from the
   disk image's window onto the Terminal window, and press Return.)
3. Follow the messages. The script says which template it installs. If Word
   is open, it waits: quit Word and press Return, or type `q` and Return to
   have Word quit (Word asks about unsaved documents as usual). It copies the
   template into Word's Startup folder for your account, replacing an earlier
   version, clears the download quarantine, and checks the copy before
   putting it in place. No administrator password is needed. If macOS asks
   whether Terminal may access data from other apps, click **Allow**: that
   is the copy into Word's folder. (After `q` it may also ask whether
   Terminal may control Microsoft Word.)
4. Start Word. If Word asks whether to enable macros in `LingTeX-Word.dotm`,
   choose **Enable Macros**. A few seconds later a message names the version
   and lists its keyboard shortcuts (**Cmd+Option+Shift** and a letter). The
   Interlinear tab is on the ribbon.

To remove the add-in, open a LingTeX-Word disk image and do steps 2 and 3 with `sh install.sh --uninstall` (two ordinary hyphens) in place of `sh install.sh`. From the next start of Word,
the Interlinear tab is gone. Or delete `LingTeX-Word.dotm` from Word's
Startup folder,
`~/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word`
(in the Finder: User Content > Startup > Word).

### Upgrading

Close Word and install the new version the same way. On Windows, run the new
`LingTeX-Word-Setup-...exe`. On the Mac, eject the old disk image, open the
new one and run its `install.sh` as above. Either way the old file is
replaced.

The next time Word starts, the add-in binds the keyboard shortcuts again, and
its message names the new version. `LingTeXAbout` in the macro list names the
running version at any time. Documents made with an earlier version keep
working and re-wrap with the new one. A LingTeX style they lack is added the
next time an example in them is inserted or redrawn, inside that command's
Undo entry. If your keyboard shortcuts stop working after an upgrade, click
**Install Shortcuts** on the Interlinear tab once.

## The Interlinear tab

Every command you need day to day is on one tab. The same commands are in
Word's macro list (Alt+F8 on Windows, Tools > Macro > Macros on Mac) under
the names in the right-hand column, for anyone who prefers that. A few are
only in the macro list:

- `LingTeXAbout` names the release installed.
- `LingTeXUndoDiagnostics` says what the last command's Undo entry did, for a
  bug report.
- `LingTeXShowSettings` lists every setting the document holds.
- `LingTeXStart` clears the busy flag an interrupted command left behind.
- `LingTeXRemoveShortcuts` takes the keyboard shortcuts out.

### Interlinear

| Button | What it does | Macro name |
|---|---|---|
| ![Insert Interlinear](src/icons/igtInsert.png) **Insert Interlinear** | With nothing selected, reads the clipboard (FLEx interlinear text or plain tab-separated rows); with text selected, reads and replaces the whole paragraphs the selection touches, and selected lines you typed take the Text to Interlinear road. | `LingTeXInsertInterlinear` |
| ![Convert Table](src/icons/igtConvert.png) **Convert Table** | Adopts an ordinary Word table as an auto-wrapping example: one row per tier, a row merged into one cell as the translation. | `LingTeXConvertTableToIgt` |
| ![Text to Interlinear](src/icons/igtFromText.png) **Text to Interlinear** | Turns selected lines of text into an example: the words on one line, their glosses on the next, the translation under them. | `LingTeXTextToInterlinear` |

### Layout

| Button | What it does | Macro name |
|---|---|---|
| ![Re-wrap All](src/icons/igtRewrapAll.png) **Re-wrap All** | Re-wraps every example in the document, redrawing each one. Re-wraps every example in the document, redrawing each one. When the document is saved (Re-wrap on Save), the same pass runs but redraws only the examples whose layout would change or that have a space typed in a cell. | `LingTeXRewrapAll` |
| ![Re-wrap This](src/icons/igtRewrapThis.png) **Re-wrap This** | Re-wraps the example at the cursor, from scratch: columns move down when space has run out and back up when it has been freed. | `LingTeXRewrapCurrent` |
| ![Indent](src/icons/igtIndent.png) **Indent** | Moves the example half an inch to the right, number and translation with it, and re-wraps it to the narrower line. In a group of lettered examples it moves only the one the cursor is in (see Known issues). | `LingTeXIndentExample` |
| ![Outdent](src/icons/igtOutdent.png) **Outdent** | Moves it half an inch back. Stops at the margin. | `LingTeXOutdentExample` |

### Alignment

| Button | What it does | Macro name |
|---|---|---|
| ![Split Column](src/icons/igtSplit.png) **Split Column** | Splits the column at the cursor at its first morpheme boundary, on every row that can be split, all at once. The break character goes with the morpheme that owns it, as the add-in recorded when it joined them (see *Prefixes and proclitics*): onto the new column for a suffix or enclitic, or when there is no record; at the end of the left-hand column for a prefix or proclitic; on both sides for a boundary both share. Some rows stay whole in the left-hand column: those that gloss whole words (FLEx's Word line when there is also a Morphemes line, Word Gloss, Word Cat.) and, for now, Lex. Gram. Info., which shares Word Cat.'s style. A cell with no break is left whole, and a message names its tier. | `LingTeXSplitColumn` |
| ![Merge Columns](src/icons/igtMerge.png) **Merge Columns** | Select across several cells to merge exactly those; with the cursor in one cell, merges that column with the next. | `LingTeXMergeColumns` |

### Settings (toggles)

These show the active document's setting. Numbers, Re-wrap on Save, Re-wrap on Leave and First Capital turn it on or off; By Word and By Morpheme are a pair, and clicking one chooses that alignment. By Word, By Morpheme
and Numbers apply to **new** examples; an example already on the page is
unchanged until it is inserted again. By Word and By Morpheme shape an
example copied from FLEx or typed as lines (Text to Interlinear); a table
(Convert Table) or tab-separated rows keep the columns they have. First
Capital re-wraps every example in the document as soon as it is clicked.

| Button | What it sets | Macro name |
|---|---|---|
| ![By Word](src/icons/igtByWord.png) **By Word** | One column per word, the default. In a copy from FLEx, a suffix or enclitic stays in the column of the word before it, and a prefix or proclitic in the column of the word after it; when the copy includes FLEx's Word line, its words decide. | `LingTeXAlignByWord` |
| ![By Morpheme](src/icons/igtByMorpheme.png) **By Morpheme** | One column per morpheme. A column that continues a word never starts a wrap line. | `LingTeXAlignByMorpheme` |
| ![Re-wrap on Save](src/icons/igtRewrapOnSave.png) **Re-wrap on Save** | When the document is saved, re-wrap every example whose layout would change (a margin moved, a font changed, an edit made a column wider or narrower) or that has a space typed in a cell. An example that would come out the same is left alone, so a save that changes nothing adds nothing to the Undo list. On by default. An edit that changes no column's width (a gloss typed in capitals, say) is not redrawn by the save: it is redrawn when the cursor leaves the example (with **Re-wrap on Leave** on) or with **Re-wrap This** (issue #17). | `LingTeXToggleRewrapOnSave` |
| ![Re-wrap on Leave](src/icons/igtRewrapOnLeave.png) **Re-wrap on Leave** | Re-wrap an example as soon as the cursor leaves it, if you edited it or its layout would change. One you only clicked through, whose layout would come out the same, is left alone and adds nothing to the Undo list. The cursor stays where you clicked. On by default; it never fires while you type inside one. | `LingTeXToggleRewrapOnSelectionChange` |
| ![Numbers](src/icons/igtNumbers.png) **Numbers** | Number new examples (1), (2)... in a first column; several examples from one copy get one number and a letter each. On by default. | `LingTeXToggleExampleNumbers` |
| ![First Capital](src/icons/igtInitialCap.png) **First Capital** | Grammatical glosses as `Erg`, `3Sg`, with a full-size first capital; off, uniform small capitals as the Leipzig rules print them. On by default; a click re-wraps every example at once. | `LingTeXToggleGramGlossInitialCap` |

### Setup, Keys and Check

| Button | What it does | Macro name |
|---|---|---|
| ![Settings](src/icons/igtSettings.png) **Settings** | Opens the Settings dialog: alignment, numbering, small capitals, the re-wrap triggers, every spacing, and the LingTeX styles. | `LingTeXSettings` |
| ![Reset Styles](src/icons/igtResetStyles.png) **Reset Styles** | Makes the six tier styles follow the document's Normal style again, and re-wraps. Asks first. It is not yet one Undo entry: one Undo takes back the re-wrap but leaves the reset styles in place, so the columns no longer fit their fonts. Click **Re-wrap All** then (issue #17). | `LingTeXResetStyles` |
| ![Install Shortcuts](src/icons/igtInstallKeys.png) **Install Shortcuts** | Binds fourteen commands to keys (the list is under Keyboard shortcuts); done on the first start after installing or upgrading, and again here if the bindings are lost. | `LingTeXInstallShortcuts` |
| ![Shortcuts](src/icons/igtShowKeys.png) **Shortcuts** | Lists the shortcuts actually bound on this machine. | `LingTeXShowShortcuts` |
| ![Check Glossing](src/icons/igtCheck.png) **Check Glossing** | Checks the example at the cursor against the glossing conventions and offers to repair what has one right answer. | `LingTeXCheckExample` |

## Getting an example onto the page

### From FLEx

In FieldWorks Language Explorer, open the text under Texts & Words >
Interlinear Texts and click the **Print View** tab: the copy comes from that
view. Select the part of the text you want, choose Edit > Copy, click in your
Word document where the example should go, and click **Insert Interlinear**.

The lines FLEx copies (Word, Morphemes, Lex. Entries, Lex. Gloss, Lex. Gram.
Info., Word Gloss, Word Cat.) are recognised by their labels, in either
spelling, and each keeps its row, in FLEx's order, so a line shown in two
writing systems or two analysis languages gives two rows; Lex. Entries is
drawn as a Morphemes row. Free, Lit. and Note lines go under the example,
each in quotes and without its label, so for now a literal translation or a
note reads as one more translation (issue #5). A line with no text at all is
left out, and so is a line with any other label.

Which lines are copied is decided in FLEx, with Print View showing, under
Tools > Configure > Interlinear, before you copy. A line that arrives nearly
empty usually has no data of its own in that writing system: untick it there
and copy again, rather than deleting cells in Word.

By default the example is aligned by word: a suffix or enclitic stays with
the word before it, a prefix or proclitic with the word after it; **By
Morpheme** gives one column per morpheme instead.

When the copy includes FLEx's Word line, its words are the columns: a clitic
FLEx writes as a word of its own stays one. Without it, the boundary
characters decide, as above. That line is the words as written, so it keeps
its spaces and takes no part in Check Glossing.

If FLEx copied several examples at once, every one is inserted, one under
another, under one number with a letter each (see Numbering); with
**Numbers** off they get neither number nor letter. The whole insert is one
Undo entry. What the glossing check finds in them is reported afterwards,
example by example.

A copy from a Scripture text, whose segments are numbered by chapter and
verse (`3:16`) rather than `1.2`, may not be read yet (issue #5).

### From a table

An ordinary Word table, typed by hand or pasted from a spreadsheet, becomes an
example with **Convert Table**: click anywhere in it. One row per tier, in
order: the words, then their glosses, then word glosses, then word
categories, each in its LingTeX style; a row that has been merged into a
single cell is taken as the free translation. The columns stay as the table
has them, whatever By Word or By Morpheme says. If there is no merged row,
the add-in says so: type the translation in the paragraph under the example
and give it the style LingTeX Free, and it belongs to the example from then
on. A space in a cell becomes `.` or `_` at the example's next re-wrap rather
than at once (issue #17).

Tab-separated rows on the clipboard go straight to **Insert Interlinear** and
are read the same way, a line with no tab in it being a translation.

### From lines you typed

For an example that exists only as text, select the lines and click **Text to
Interlinear**:

```
(1) Uwzob zu. [...] Ozwum-vex zu vuz-mo ov vrezo, zovemi vexu muvuze.

Lantern DET [...] Cord-3.POSS DET thin.SG-and can make.thin, what-PP touches.something if

Yesterday my neighbor's children bought bread at the market.
```

The words of each tier line become the columns. Any run of spaces separates
them, a manual line break inside a line is just a space, and blank lines are
skipped. A leading example number such as `(1)`, `(12a)` or `1.` is dropped,
because the document numbers its examples itself.

The tier lines are read by position: the first is the words, the second
their glosses, a third word glosses and any further line word categories,
each in its LingTeX style. A third or later line glosses whole words: it is
never split, and takes no part in the break-character checks. A separate
morpheme line is best copied from FLEx, whose Morphemes line is recognised by
its label.

The one thing the text cannot say is which of its last lines are free
translations, so you are asked. The question lists every line with its word
count and offers a guess: the trailing lines whose word count differs from
the first line's. Accept it or type the number, or Cancel to draw nothing.

Leave the quotation marks off the translation, and take them off if the text
has them: the add-in sets every translation in single quotes itself, so
quotes around it would show twice, and stay doubled through every re-wrap.
The same goes for a translation row in a table.

With the document set to **By Morpheme**, every column in which each filled
cell of the first two lines carries a morpheme boundary is split at its
boundaries, so `Ozwum-vex` over `Cord-3.POSS` becomes two columns while
`zovemi` over `what-PP` stays one (an empty cell does not stand in the way).
Check Glossing reports that mismatch afterwards.

**Insert Interlinear** takes the same road when its *selection* is plain
lines rather than FLEx text or tab-separated rows; from the clipboard it
expects FLEx text or tab-separated rows.

## Working with an example

**Editing cells.** Click in a cell and type. With the defaults, an example
you edited re-wraps when the cursor leaves it, so a longer form pushes
columns down and a shorter one pulls them back up. A save re-wraps every
example whose layout would change or that holds a space typed in a cell. An
example you only clicked through is redrawn only if its layout would
change, and a save that would change nothing writes nothing: neither adds
an entry to the Undo list. One gap remains (issue #17): a save made while
the cursor is still in an example you edited skips it when its layout would
not change, so a gloss typed as `PST` gets its small capitals only when the
cursor leaves the example, or with **Re-wrap This** or **Re-wrap All**.

If you type a space inside a cell it becomes `.` or `_`, whichever the
document is set to, at the next re-wrap: a space would break the alignment.
FLEx's Word line is the exception when the example also has a Morphemes
line: it is the words as written, and it keeps its spaces. While the cursor
is in an example, Word's AutoCorrect does not capitalise the first letter
of a cell or of a sentence, so a form typed in lower case stays that way.
Your own AutoCorrect settings return when the cursor leaves the example.

**Translations.** The translation is the paragraph under the table, in the
style LingTeX Free; a Lit. or Note line copied from FLEx is one too. Edit it
as ordinary text. To give an example a translation it lacks, type it in the
paragraph under the table and give that paragraph the style LingTeX Free.
Every non-empty LingTeX Free paragraph directly under the table belongs to
the example, and an empty paragraph ends it. Enter after a translation
starts an ordinary paragraph.

**Splitting and merging.** Put the cursor in a cell and click **Split
Column** to pull an affix, a clitic or a reduplicant out into a column of
its own. It splits at the column's first morpheme boundary, on every
morpheme-level row at once. The break character stays with the morpheme that owns it, as the add-in recorded when it joined them: at the start of the new column for a suffix or enclitic, or when there is no record (a cell from a table or typed lines, or one retyped); at the end of the left column for a prefix or proclitic; and on both sides when both own it (see *Prefixes and proclitics* under When something goes wrong). Rows that gloss whole words (FLEx's Word line when the example also
has a Morphemes line, Word Gloss, Word Cat.) are not split and stay in the
left column; for now, neither is Lex. Gram. Info., which shares Word Cat.'s
style. A row with no break in that cell keeps the cell whole on the left,
and a message names it; Undo takes the split back. **Merge Columns** puts
columns back together. You can leave one word morpheme-aligned in an
otherwise word-aligned example.

**Moving it.** **Indent** and **Outdent** step the example, number and
translation included, by half an inch. Dragging the table's left edge on
the ruler works too; the translation follows at the next re-wrap. A re-wrap
keeps whatever indent it finds. A new example takes the indent of the
paragraph it is inserted into, unless the **Left** box in the Example row
of the Settings dialog sets one for every new example. In a lettered group
each example is its own table and moves on its own (issue #12).

**Undo.** Each command that changes the page is one entry in the Undo
list, and one Undo takes it back whole: an insert with the LingTeX styles
its first use creates (any text it replaced comes back), a re-wrap, a split
or merge, a Check Glossing repair, an indent. One Redo puts an insert back,
numbered and styled. An automatic re-wrap adds an entry only when it redraws: on leaving an example you edited, or when an example's layout would change or one of its cells holds a typed space. Two gaps remain (issue #17, under Known issues): **Reset
Styles** and the Settings dialog's Reset buttons change the styles outside
the re-wrap's entry, and a space typed in a table before **Convert Table**
is replaced by the next automatic re-wrap, in an entry of its own. If one
command ever leaves many steps in the Undo list, run
`LingTeXUndoDiagnostics` from the macro list straight away and send its
message with your report.

**Deleting an example.** Select the table and the translation under it and
delete them as you would any table. The next example renumbers.

**Letting go of an example.** Every example carries the table style `LingTeX
Interlinear`; that style is how the add-in knows a table is its own. Apply any
other table style and the add-in leaves that table alone from then on.

## Numbering

A new example carries its number in a first column, `(1)`, `(2)`..., set by
Word's own list numbering (the list style *LingTeX Example Number*). Because
it is an ordinary numbered paragraph, everything Word does with numbering
applies: delete or move an example and the rest renumber; a cross-reference
can point at it; the list style decides its format.

**Numbers** on the ribbon decides only whether *new* examples get a number;
an example keeps its number through every re-wrap. The width of the number
column is a setting (36 pt by default).

**Several examples from one copy** share one number: the first carries
`(3)` and `a.`, the next only `b.`, `c.`..., each letter in a second number
cell, six tenths as wide as the first, so the group reads as one example
with sub-examples, the way a LaTeX xlist does. The letters are the level
below the number's in the same list style (level 2, or level 3 with
per-chapter numbering), so they restart after every number and renumber
when a sub-example goes. Their format is the add-in's: whenever it draws a
lettered example and finds another number format on that level, it sets it
back to `a.`, `b.`, `c.`, so a different letter format set in the list
style does not last. Delete the first of a group and the number moves to
the next example, not to the group: give that one the number by hand if you
need to. With Numbers off, the examples of one copy are drawn one under
another with neither a number nor a letter.

**Per chapter.** Modify the list style *LingTeX Example Number* in Word's own style dialog: on the Mac, Format > Style with its List set to *All styles*; on Windows, Home > Multilevel List, where it is listed under List Styles (right-click it and choose Modify). Link its level 1 to Heading 1 with no
number text. On level 2, choose the number style 1, 2, 3 and type a parenthesis on each side of the shaded number so that it reads (1), with no trailing character and a text position of 0;; the add-in creates level 2 as
the letters of a group, so the number style has to be changed as well.
Last, set the list level to 2 in the Settings dialog. New examples then sit
on level 2, which Word restarts after every Heading 1; the letters of a
group move to level 3, which the add-in formats itself. An example already on the page keeps the level it was drawn on, so set this up before inserting examples. In a document that already has a lettered group, delete those examples first, then set this up and insert them again: redrawing a group numbered on level 1 sets level 2 back to letters, and OK in the Settings dialog redraws every example. (The *Example Number*
entry in the Settings dialog's Styles list is the paragraph style of the
number cell, not this list style.)

## The Settings dialog

**Settings** opens one dialog over every setting the document holds. Settings
are stored **in the document**, so a colleague who opens the file with the
add-in gets the same layout, and a document keeps its choices when it moves
between machines.

**New examples:** one column per word or per morpheme; whether they are
numbered, and on which list level; grammatical glosses in small capitals,
and whether with a full-size first capital; the two re-wrap triggers; and
what a space typed inside a cell becomes.

**Spacing,** one box per spacing, by level. A box takes points (`6`) or a
percentage of the example's font size (`50%` is half a line, and grows with
the text). **An empty box means the default**, shown in brackets after the box's name; an empty **Left** box means the indent of the paragraph a new example is inserted into.

| Row | Box | What it sets | Default |
|---|---|---|---|
| Example | Before | Space above the example, on its first row | 0 |
| | After | Space after the translation, or after the last row when there is none | 3 |
| | Left | Left indent of every new example | the indent of the paragraph it is inserted into |
| | Right | How far short of the right margin the wrap lines and translation stop | 0 |
| Wrap lines | Line gap | Space between the wrap lines of an example | 6 |
| | Continuation | Extra indent of every wrap line after the first | 0 |
| | Tier gap | Space between the tiers of one wrap line | 0 |
| Columns | Column gap | Space to the right of every column's widest cell | 6 |
| | Number column | Width of the number column | 36 |
| Cell padding | Left, Right, Top, Bottom | Padding inside every cell; the columns widen to match, and the text stays at the example's indent | 0 |
| Translation | Above | Space between the last row and the first translation | 6 |
| | Between | Space between two translations | 0 |

**OK** stores the settings and re-wraps every example in the document so the
page shows the change; **Apply** does the same and leaves the dialog open.
**Cancel** closes the dialog without storing what is in the boxes. What
**Apply** already stored stays, and so does anything done with the style
buttons below, which act at once. **Restore Defaults** puts every box and
tick back to what a fresh document gets, stored only when you then press OK
or Apply. A box that is not a number is refused by name before anything is
stored.

**Styles** lists eight of the add-in's styles: the six tier styles, LingTeX Gram Gloss and LingTeX Example. Select one and click **Modify in
Word** to open Word's own style dialog on it, for everything a style can
hold: font, size, colour, borders, the paragraph format. Make the change with
that dialog's **Modify** button. When Word's dialog closes, every example is
re-wrapped to the changed style, and the Settings dialog comes back. If
nothing in the document uses the style yet, Word cannot open its dialog on
it: a message says so, and in Word's dialog you set List to All styles and
pick the style yourself.

**Reset This Style** gives the selected style back the add-in's own format:
the body font, the Normal style's size, the add-in's bold, italic and small
capitals, and, for a paragraph style, its paragraph format. **Reset the Six
Tier Styles** only bases the six tier styles on Normal again, with the body
font and Normal's size, and keeps their italic, bold and paragraph format,
as **Reset Styles** on the ribbon does. Both ask first, act at once, and
re-wrap every example. Neither is yet one Undo entry: one Undo takes back
only the re-wrap, and **Re-wrap All** then fits the columns to the styles
again (issue #17).

## Styles

Every example is described by ordinary Word styles, which is what makes it
survive a copy, a paste and a round trip through another editor. Restyle one
and every example in the document follows on its next re-wrap.

| Style | What it formats |
|---|---|
| LingTeX Vernacular | The word line: the object language, italic by default |
| LingTeX Morphemes | The morpheme line, when FLEx supplies one; italic by default |
| LingTeX Gloss | The morpheme glosses |
| LingTeX Word Gloss | The word glosses |
| LingTeX Category | The word categories, and Lex. Gram. Info. until it has a style of its own |
| LingTeX Free | The free translation, and a Lit. or Note line copied from FLEx: the paragraphs under the table, in single quotes |
| LingTeX Gram Gloss | A character style: the grammatical abbreviations, in small capitals |
| LingTeX Left Boundary, LingTeX Shared Boundary | Character styles with no formatting of their own, on a boundary character that belongs to the morpheme on its left, or to both (see *Prefixes and proclitics* under When something goes wrong) |
| LingTeX Example | The number cell, and the letter cell of a group (`a.`, `b.`); a paragraph style linked to the list style LingTeX Example Number, which does the numbering |
| LingTeX Example Number | The list style that numbers the examples, `(1)`, `(2)`..., and letters a group, `a.`, `b.` (see Numbering) |
| LingTeX Interlinear | The table style that marks a table as an example |

The tier styles are based on the document's Normal style and inherit its
size, so making the body text bigger makes the examples bigger on their next
re-wrap. Their font is pinned from the body font when they are created. To
change the font of the examples, change it on the styles, through Modify in
Word; a font with full phonetic coverage, such as Charis SIL or Doulos SIL,
keeps a row from growing when a symbol has to be borrowed from another font.

The interlinear tier styles (all but LingTeX Free), and every cell of an
example, are marked not to be checked for spelling or grammar, so forms and
glosses carry no red underlines; the translation is checked like any other
text.

The add-in creates a style only when the document lacks it, and never
overwrites one you have changed; only the Reset buttons put a style back. The
one exception is the letters' level of the list style LingTeX Example Number,
which the add-in sets back to `a.`, `b.` when it draws a lettered example (see
Numbering).

## Glossing conventions and Check Glossing

Grammatical glosses are recognised by their **shape**: all capitals, or
beginning with a digit. There is no list of approved abbreviations, so an
abbreviation nobody has published is still a grammatical gloss and still gets
small capitals. The Leipzig list is examples, not a vocabulary.

Only the gloss lines take small capitals: Lex. Gloss, Word Gloss, Word Cat.
and Lex. Gram. Info. from FLEx, and every row after the first in an example
made from a table, from tab-separated rows or from typed lines. A word in
capitals on the Word, Morphemes or Lex. Entries line, or in the free
translation, is left as typed. Within a gloss only the grammatical part takes
them, so in `stack.CMP` only `CMP` does. A capital letter on its own (`A`,
`S`) or followed by a period (`N.`) is not taken for a gloss.

Word's small capitals only affect lower-case letters, so the add-in stores
`ERG` as `erg` in the Gram Gloss style and lets the style draw it as small
capitals. Nothing is lost: the style marks exactly which runs were
transformed, and the add-in reads them back as `ERG`. **First Capital**, on
by default, keeps the first letter full-size (stored as `Erg`, `3Sg`); off,
the glosses are uniform small capitals, as the Leipzig rules print them.
Clicking it re-wraps every example in the document at once. To keep glosses
in full capitals as typed, untick *Grammatical glosses in small capitals* in
the Settings dialog.

**Check Glossing** reports what can be decided mechanically and repairs only
what has one right answer. It lists what it found and asks before it repairs
anything; the repair is one Undo entry.

| Finding | Repaired? |
|---|---|
| A column where only some cells carry the break character | Yes |
| A space inside an interlinear cell | Yes, with `.` or `_` |
| Two cells in a column claiming different break characters | No: only the linguist knows which |
| Form and gloss showing a different number of morpheme breaks | No: reported |
| An unmatched infix bracket | No: reported |
| A column with a form but no gloss, or a gloss but no form (judged on the Morphemes line, or the first line when there is none, and the first gloss line; other lines may be sparse) | No: legal, but usually a slip |

The break characters are `-`, `=`, `~` and the infix brackets `<` `>`. `.`
and `:` are never counted as morpheme breaks: they mark one morpheme glossed
with several words, so `stack.CMP=SEQ` against `rixu=xo` is correct and is
not flagged.

Lines that gloss whole words carry no morpheme breaks, so the check that break characters agree down a column, and its repair, leave them alone (an unmatched infix bracket is still reported on them, except on the Word line below). From FLEx, those are
Word Gloss, Word Cat., and, for now, Lex. Gram. Info., which shares Word
Cat.'s style; and the Word line when the copy also has a Morphemes line.
That Word line also keeps its spaces. In an example from a table,
tab-separated rows or typed lines, they are the third row and every row
after it. Without a Morphemes line, FLEx's Word line is the one the breaks
are read from, and it is checked like any other.

Insert Interlinear, Text to Interlinear and Convert Table run the same check
on what they draw and list what they find. To repair what has one right
answer, click in the example and use Check Glossing.

## Keyboard shortcuts

On the first start after installing or upgrading, the add-in binds the
fourteen commands below to **Ctrl+Alt+Shift** and a letter (Windows) or
**Cmd+Option+Shift** and a letter (Mac). Re-wrap on Save, Re-wrap on Leave,
First Capital, Reset Styles, Install Shortcuts and Shortcuts have no key. It
never takes a key that already does something in Word, so a command may land
on an alternate letter, or on none when every letter it tries is taken (the
message says which). **Shortcuts** lists what is actually bound on your
machine, and **Install Shortcuts** runs the installation again if the
bindings are lost.

| Command | Letters tried, in order |
|---|---|
| Insert Interlinear | I, E, J |
| Re-wrap This | R |
| Re-wrap All | A |
| Split Column | S, X, D |
| Merge Columns | M |
| Check Glossing | K |
| Convert Table | T |
| By Word | W |
| By Morpheme | P |
| Settings | H |
| Numbers | N |
| Indent | G |
| Outdent | L, O, U, Y, Q |
| Text to Interlinear | F, B, V |

On the Mac, Word already uses Cmd+Option+Shift with I, S, L, O and U, so
Insert Interlinear usually lands on E, and Split Column and Outdent on later
letters of their lists.

The shortcuts are kept in the LingTeX-Word template itself where Word allows
it, otherwise in the Normal template. To change one, use Word's Customize
Keyboard dialog, category Macros (Tools > Customize Keyboard on the Mac;
File > Options > Customize Ribbon, then Keyboard shortcuts: Customize, on
Windows). The macro `LingTeXRemoveShortcuts` takes every LingTeX-Word shortcut out; save LingTeX-Word.dotm when Word asks at quit, or they are back at the next start. The first start after the next upgrade installs them again.

## Known issues

**Cramped line spacing after an insert (Windows).** On Word for Windows an
example sometimes came out with its rows too close together right after it
was inserted. The insert now re-wraps what it drew, inside the same Undo entry, which should cure it. If you still see it, **Re-wrap This**
(or **Re-wrap All**) draws it with the right spacing; please say so on the
issue. Tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/15](https://github.com/rulingAnts/LingTeX-Tools/issues/15).

**A few gaps in Undo and re-wrapping remain.**

- **Reset Styles** (and Reset This Style or Reset the Six Tier Styles in the
  Settings dialog) changes the styles outside its Undo entry. One Undo takes
  back only the re-wrap and leaves the styles reset, with the columns sized
  for the old fonts. Click **Re-wrap All** after such an Undo.
- **Convert Table** leaves a space typed in the table for the next re-wrap,
  which is then an Undo entry of its own.
- Saving while the cursor is still in an example you have just edited can
  leave what you typed there unformatted until the cursor leaves the example
  (a gloss typed as `PST` not yet in small capitals).

Tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/17](https://github.com/rulingAnts/LingTeX-Tools/issues/17).

**By Word and By Morpheme do not switch an example already on the page.**
They set how *new* examples are aligned in the document; an example keeps the
alignment it was inserted with. To change one, use **Split Column** and
**Merge Columns** column by column, or set the alignment first and insert
the example again. Tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/14](https://github.com/rulingAnts/LingTeX-Tools/issues/14).

**Indent and Outdent move one table at a time.** A copy of several examples
is drawn as one numbered group, each example its own table. Indent and
Outdent step the table the cursor is in, so on a group each sub-example has
to be indented or outdented on its own; indenting the first, the one with
the group number, moves only that one. Tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/12](https://github.com/rulingAnts/LingTeX-Tools/issues/12).

**Undo after editing an ordinary table takes two presses (Mac).** After you
delete a cell in a table that is not an interlinear example, the first
Cmd+Z makes the whole table seem to vanish and disturbs the layout around
it. Press Cmd+Z once more: the table comes back exactly as it was, and
nothing is lost. Seen in Word for Mac; not yet checked on Windows. It is
tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/3](https://github.com/rulingAnts/LingTeX-Tools/issues/3).

**A copy from a Scripture text may not be read correctly.** FLEx starts each
segment of a Scripture text with its chapter and verse (`3:16`), where other
texts have a number such as `1.2`. The add-in does not yet recognise such a
reference, so a copy that carries one is misread or refused. Tracked at
[github.com/rulingAnts/LingTeX-Tools/issues/5](https://github.com/rulingAnts/LingTeX-Tools/issues/5).

## When something goes wrong

**Which version is installed.** Run `LingTeXAbout` from the macro list
(Tools > Macro > Macros on Mac, Alt+F8 on Windows). It names the release,
the setup version and the file Word loaded the add-in from. The message
shown at the first start after installing or upgrading names the release
too.

**"LingTeX-Word is busy with another operation."** A command was interrupted
and left a flag set. Run `LingTeXStart` from the macro list, or restart Word.

**"That text could not be read as interlinear data."** From the clipboard,
Insert Interlinear reads FLEx text or tab-separated rows only. Lines of
plain text have to be in the document. Paste them, select at least two lines
(not inside a table), and click Insert Interlinear or Text to Interlinear,
which asks which lines are translations. A table already in the document is
Convert Table's job.

**Prefixes and proclitics.** A boundary mark belongs to the affix or clitic,
never to the word it attaches to: in `ze=zuvo` the `=` is the proclitic's. When
two morphemes are folded into one By Word cell, the add-in records whose
boundary it is as a character style on that one character, *LingTeX Left
Boundary* or *LingTeX Shared Boundary*, with no formatting of its own. So
Split Column gives the boundary back to its owner, the cell's text stays
plain and Find matches it as typed. Retyping a cell drops the style; a
boundary with no record is treated as the right-hand morpheme's, as a suffix
or enclitic is.

**Several examples in one copy.** Select several lines in FLEx's Print View
and copy: Insert Interlinear draws every example, one under another, as one
numbered group with a letter each (see Numbering). FLEx's end-of-segment
sign, `§`, is dropped, and a gloss FLEx spreads over the cells after its
morpheme's, at the end of a row too, is read whole.

**A free translation lost its first word.** FLEx marks where the text of a
Free or Lit. line starts with invisible direction marks, and the add-in reads
them; when they are absent (a writing system with Graphite on) it reads the
next line instead, so a line that starts with a space, a further language,
tells it the line before carried a language code. A word is never taken for
a code by its shape.

**One copy became two examples, or came out as one long line.** The line
breaks of a copy are read before the text is parsed: a copy from FLEx on
Windows arrives with CR LF endings, some routes between applications double
every break, and rows ended with Shift+Return arrive as vertical tabs. All
of these are read as the plain lines they were, so one example stays one
example and two examples separated by a blank line stay two. Plain
tab-separated text that is not FLEx output is left exactly as typed, blank
lines included. If a copy still misreads, paste it into a plain-text editor
and send what you see there with the report.

**A style of the wrong kind.** If the document already has a style called, say, *LingTeX Gloss* that is not a paragraph style, the add-in says so and draws nothing until it is renamed or deleted: it would otherwise draw examples it could not read back. (A *LingTeX Example Number* that is not a list style does not stop it: the examples are drawn unnumbered, and a message says they could not be numbered.): it would otherwise draw
examples it could not read back.

**Re-wrap All takes a few seconds** on a document with many examples. The
status bar reports progress; a second run in the same Word session is
faster, because measured widths are remembered until Word quits or a setting
or LingTeX style is changed.

**An example could not be re-wrapped.** A re-wrap plans the new layout
before it touches an example, so one it cannot re-wrap is left exactly as it
was, and a message gives the first reason. The re-wrap on leaving an example
says so once per document; **Re-wrap on Leave** turns it off.

**The Undo list shows many steps after one command.** Each command that
draws or re-wraps is one entry in the Undo list, named for it (*Insert
interlinear*, *Re-wrap all interlinear examples*); the first insert into a
document includes the LingTeX styles it creates. One Undo takes it all back
and one Redo brings it all back. If a command leaves a long list instead
(Style, ParagraphFormat, ListLevel...), run `LingTeXUndoDiagnostics` from
the macro list straight away, and send its message, with a screenshot of the
list, in your report. Reset Styles is a known exception (see Known issues).

**macOS will not open Install LingTeX-Word.** Older disk images install with a Script Editor document, which macOS 27 no longer opens from a download because it is not signed; their Uninstall LingTeX-Word is blocked the same way. Use the current release: its disk image installs with `install.sh`
in Terminal, which macOS does not block, and `sh install.sh --uninstall`
removes the add-in (see Installing). `install.sh` does not need its own disk
image: with no template beside it, it installs the one on an open
LingTeX-Word disk image, an older one included, or else downloads the newest
release's template.

**The Interlinear tab is missing.** The template is not loaded. Check that
`LingTeX-Word.dotm` is in Word's Startup folder and that macros are enabled
for it. A copy put there by hand from a download keeps the "downloaded from
the internet" mark. On the Mac, Word will not load a marked template; on
Windows, the mark blocks its macros. Install with the installer, which
clears the mark (on the Mac, `install.sh`). On Windows, also check that
Word's Trust Center allows macros in templates from the Startup folder.

**Reporting a problem.** LingTeX-Word is part of LingTeX Tools, at
[github.com/rulingAnts/LingTeX-Tools](https://github.com/rulingAnts/LingTeX-Tools).
Open an issue there with the version `LingTeXAbout` names, your platform,
and, where you can, the text of the example; for a problem with Undo, add
what `LingTeXUndoDiagnostics` says.
