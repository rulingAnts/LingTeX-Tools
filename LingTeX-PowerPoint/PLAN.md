# LingTeX-PowerPoint: plan

LingTeX-Word's Interlinear tab, for PowerPoint. The idea: paste from FLEx and get an aligned interlinear example that wraps inside its own frame and re-wraps when the frame changes.

Status (2026-09-15): step 1, the probe.

## Why it differs from Word

- **There is no text flow.** A PowerPoint object has its own frame on the slide, so an example's wrap width is its frame's width, not the page's.
- **A table can't be the frame.** A PowerPoint table is one grid: every row shares the same column widths. Word gives each wrap line its own cell widths, and that is what lets an example wrap. In a PowerPoint table, the second line's columns would have to line up with the first line's.
- **Nothing to identify an example by.** There are no paragraph styles, so the example's structure and its settings go in `Shape.Tags` and `Presentation.Tags`.

## Proposed design (the probe decides)

- **One text box is the frame.**
  - Each wrap line is one paragraph per tier (words, glosses and so on).
  - That line's columns are lined up with tab stops set for those paragraphs, at measured positions.
  - The free translation is a paragraph below.
  - The box's width is the wrap width.
- **Fallback:** a group of text boxes, with an invisible rectangle that sets the frame width.
- **Re-wrap triggers:**
  - the ribbon, on leaving the example, and on save, as in Word;
  - also after the frame is resized, if PowerPoint's resize event (`AfterShapeSizeChange`) fires on both platforms.

## What carries over from LingTeX-Word

These modules never touch Word's objects: `modFlexParse`, `modIgtModel`, `modLeipzig` and `modWrap`, plus the algorithm tests in `modTests`. Both builds should import one copy of them, so a parser fix lands in both add-ins.

## Known limits

- **No custom keyboard shortcuts.** Assigning keys from a macro is Word-only (`KeyBindings`).
- **Undo may take several presses.** PowerPoint has no custom undo record (`UndoRecord`), so one command may be several Undo steps. How PowerPoint groups a macro's changes is still to be measured.
- **Numbering is plain text**, renumbered by a command.
- **The add-in (`.ppam`) has to be registered.** It isn't dropped into a Startup folder.

## Steps

1. **Probe.** `tools/probe/modProbe.bas` is pasted once and run. A later probe covers events, which need a class module.
2. **Core.** Insert, re-wrap and read back an example.
3. **Commands.** Events, settings, numbering, Check Glossing, Split and Merge Columns.
4. **Tests.** Tests that run inside PowerPoint, on the Mac and on Windows.
5. **Release.** The add-in build, installers, guide and site.

## Probe results

(To fill in.)
