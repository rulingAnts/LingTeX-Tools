# LingTeX-PowerPoint: plan

LingTeX-Word's Interlinear tab, for PowerPoint. The idea: paste from FLEx and get an aligned interlinear example that wraps inside its own frame and re-wraps when the frame changes.

Status (2026-09-15): three probe rounds have run, the second and third through the dev rig with no hand-pasting (results below). The design is settled: one text box is the frame. Measuring, reading the clipboard and the Startup folder all have answers. Next: confirm a `.ppam` loads from the Startup folder (needs a PowerPoint restart), then step 2.

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
- **Undo may take several presses.** PowerPoint has no custom undo record (`UndoRecord`); probe 2 measures how PowerPoint groups a macro's changes.
- **Numbering is plain text**, renumbered by a command.
- **The add-in (`.ppam`) has to be registered.** It isn't dropped into a Startup folder.
- **At most 32 tab stops per paragraph**, so at most 33 columns in one wrap line.

## Dev rig

`tools/modLingTeXDev.bas` is pasted once into `LingTeX-PowerPoint-Dev.pptm`. After that, `tools/run-in-powerpoint.sh` does the rest:

1. copies the modules into PowerPoint's own Documents folder, so there's no file-access prompt;
2. imports them;
3. runs the probe or the tests;
4. copies the reports into `LingTeX-PowerPoint-reports/`.

See the header of `modLingTeXDev.bas` for setup. First full run: 2026-09-15 (ping, import, probe).

Two fixes from that run:

- **Checking for the open presentation.** Reading `name of p` inside an AppleScript loop fails (-2763), so the runner asks for `name of every presentation` instead.
- **The clipboard sample.** `pbcopy` needs a UTF-8 locale, or "ñ" arrives as "√±".

## Steps

1. **Probe.** `tools/probe/modProbe.bas`: three rounds done (below). Still to probe:
   - events (resize, selection) and undo grouping, which need a class module;
   - whether a `.ppam` in the Startup folder loads (`MakeStartupProbeAddIn`, then restart PowerPoint).
2. **Core.** Insert, re-wrap and read back an example.
3. **Commands.** Events, settings, numbering, Check Glossing, Split and Merge Columns.
4. **Tests.** Tests that run inside PowerPoint, on the Mac and on Windows.
5. **Release.** The add-in build, installers, guide and site.

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
| Line breaks | Windows line breaks (CR LF) arrive doubled, as CR CR. Mac/Unix line breaks (LF) arrive as one CR. The reader must collapse doubled breaks when the text has no single ones, or the blank lines would split one example into several. |
| Letters beyond ASCII | Arrive intact ("ñ"). |
| `AppleScriptTask` | Exists (error 5 when no script is installed). A clipboard script is a fallback if ever needed. |
| `MacScript("the clipboard")` | Works on this Mac, giving the same text as the paste plus a trailing break. |
| Startup folder | PowerPoint on this Mac loads Adobe's `SaveAsAdobePDF.ppam` from Office's shared Startup folder for PowerPoint (loaded, autoload). It may also write to the user's own Startup folder. So an installer that drops the add-in there will very likely work; the load test will confirm it. |
