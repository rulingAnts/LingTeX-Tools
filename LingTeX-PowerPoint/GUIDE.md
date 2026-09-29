# LingTeX-PowerPoint User Guide

*Interlinear glossed text on a slide: aligned with tab stops, wrapped to the box, re-wrapped when you resize it.*

## What LingTeX-PowerPoint does

Copy an interlinear example in FieldWorks Language Explorer (FLEx), click
**Insert Interlinear**, and the example is drawn into a text box on the current
slide: one paragraph per line (the words, the morphemes, the glosses...), each
column lined up with a tab stop at the measured width, the free translation
in single quotes below, the example number hanging in the margin. Widen or
narrow the box and the example re-wraps to fit, columns moving down to a new
line when space runs out and back up when it is freed.

Everything the add-in knows about an example is on the shape itself, in tags
that survive copy and paste, so the box is an ordinary text box to PowerPoint.
What you type into it counts: a re-wrap reads the text back, not a hidden
copy, so you can correct a gloss on the slide and re-wrap.

### One idea to hold on to

Every command works on the **model** of the example and draws it again. A
command is one undo entry, whatever it wrote: one Undo (Cmd+Z, Ctrl+Z) takes
the whole insert, re-wrap or split back.

## Installing

**Mac:** quit PowerPoint, double-click **Install LingTeX-PowerPoint** (a script
document) and press **Run**. It copies `LingTeX-PowerPoint.ppam` into
PowerPoint's Startup folder. Start PowerPoint and choose **Enable Macros** if
asked; the **Interlinear** tab is on the ribbon. **Uninstall LingTeX-PowerPoint**
removes it. Upgrading is installing again.

**Windows:** not yet packaged. File > Options > Add-ins > Manage: PowerPoint
Add-ins > Go > Add New, and choose the `.ppam`.

## The Interlinear tab

| Button | What it does |
|---|---|
| **Insert Interlinear** | Reads the clipboard and draws every example in it onto the current slide, one box under another. FLEx text is recognised by its labels (Word, Morphemes, Lex. Gloss, Lex. Gram. Info., Word Gloss, Word Cat., Free, Lit.), in one writing system or several. Several examples in one copy are numbered (3a), (3b)... |
| **Re-wrap This** | Re-wraps the selected examples to their boxes' width, reading the text back first. A re-wrap that changes nothing writes nothing. |
| **Re-wrap All** | Every example in the presentation. |
| **Renumber** | Numbers every example in order, slide by slide, top to bottom. Numbers here are text, so they do not renumber themselves; a group from one copy keeps its letters. |
| **Split Column** | Click into a cell first. Splits that column at its first morpheme boundary on every line, the break character going onto the new column. |
| **Merge Columns** | Select across cells to merge exactly those; with the cursor in one cell, that column and the next. |
| **By Word** / **By Morpheme** | Re-projects the selected examples (one column per word, enclitics with their host; or one column per morpheme) and sets how new examples are aligned, stored in this presentation. |
| **Numbers** | Whether new examples get a number. |
| **First Capital** | Grammatical glosses as Erg / 3Sg; off, uniform small capitals. |
| **Re-wrap on Resize** | Re-wrap an example when its box is resized (on by default; fires when the handle is let go). |
| **Check Glossing** | The Leipzig checks on the selected example: columns whose cells disagree about a break character, spaces inside cells, form and gloss with a different number of breaks, unmatched infix brackets. Offers to fix the ones with a single right answer. |

## Getting an example onto the page

In FLEx, select the interlinear text you want and copy it. Which lines are
copied is decided in FLEx, under Tools > Configure > Interlinear, before you
copy; the add-in draws whatever lines it gets, in FLEx's order. Click on the
slide the example should go on and click **Insert Interlinear**. The box is
drawn across the middle of the slide; drag it where you want it and resize
it, and it re-wraps.

When the copy includes FLEx's Word line, its words are the columns: a clitic
FLEx writes as a word of its own stays one. Without it, the boundary
characters decide: an enclitic (`=xo`) or suffix (`-a`) joins the word before
it, a proclitic (`be=`) the word after.

## Working with an example

**Editing.** Click into the box and type. Then **Re-wrap This**, or resize the
box a little and let go: the example is read back and drawn again. A cell is
the text between two tabs; type or delete a tab and the lines no longer have
the same number of columns, and the command says so instead of guessing.

**Splitting and merging.** Click into a cell and **Split Column** pulls an
affix, clitic or reduplicant out into a column of its own, on every line at
once, with the break character on the new column; **Merge Columns** puts
columns back together.

**Moving.** Drag the box. Its width is the wrap width; its height follows the
text.

**Undo.** One Undo takes back a whole command.

**Deleting.** Delete the box. **Renumber** then closes the gap.

**Letting go of an example.** The add-in knows a box by its tags. Copy the
text out into another box and it is ordinary text.

## Numbering

A new example carries its number, `(1)`, `(2)`..., hanging in the first line's
indent, as text. The next number is one past the largest in the presentation;
**Renumber** puts every example in order, slide by slide, top to bottom, and a
group from one copy keeps its letters: `(2a)`, `(2b)`. **Numbers** on the
ribbon decides whether new examples are numbered at all.

## Settings

Font and size, the gap between columns, the number hang, the space between
the examples of one copy, numbering, gloss casing, the alignment of new
examples, what replaces a space typed into a cell, and re-wrap on resize are
stored in the presentation itself, in its tags, so a presentation carries
them along. The ribbon's toggles change the ones a person changes most;
the rest keep their defaults (Times New Roman 24 pt, a gap of 6 pt, a hang of
36 pt, 12 pt between examples, `.` for a space) until a settings dialog
exists.

## Glossing conventions and Check Glossing

The checks are the Leipzig Glossing Rules' invariants, the same as
LingTeX-Word's: every cell in a column agrees about the break character at its
start and end; no space inside an interlinear cell; form and gloss show the
same number of morpheme breaks; infix brackets pair. Grammatical glosses are
recognised by their shape (capitals, digits), so your own abbreviations are
never flagged as unknown. The lines that gloss words as written (the Word
line, Word Gloss, Word Cat.) take no part in the break-character checks.

## Known limits

- **At most 33 columns on one wrap line** (32 tab stops a paragraph); a wider
  line is cut into pieces.
- **No keyboard shortcuts:** PowerPoint's VBA cannot bind keys.
- **Numbers are text**, renumbered by a command, not by PowerPoint.
- **Resizing by code fires the resize event after the fact**, so a re-wrap
  hears its own resize; the add-in tells it apart by the size it left and
  ignores it. If a box ever re-wraps twice, turn **Re-wrap on Resize** off and
  say so.

## When something goes wrong

**"None of the selected shapes is a LingTeX example."** Click on or into the
example's box first; a box the add-in did not draw has no tags.

**"Could not read back: the tiers no longer have the same number of columns."**
A tab was typed or deleted inside the box. Put it back, or take the extra
one out, and try again.

**The tab is missing after installing.** PowerPoint loads add-ins from its
Startup folder at start; quit and start it again, and choose Enable Macros.
