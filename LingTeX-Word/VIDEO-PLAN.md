# LingTeX-Word on the website: the loop video and three screenshots

The website's LingTeX-Word page and the landing page's Word card have four
media slots. Until a file exists, each shows an animated mock; once the file is
in `docs/word/media/` under the name below, the page shows it -- no page edit.
On a local preview (or with `?media-hints` in the address) each slot names its
shot and file.

| Slot | File | Where it shows |
|---|---|---|
| Loop video | `word-loop.mp4`, `word-loop.webm`, poster `word-loop.jpg` | Word page hero, landing page Word card |
| Screenshot 1 | `word-insert.webp` | Word page, step 1 |
| Screenshot 2 | `word-rewrap.webp` | Word page, step 2 |
| Screenshot 3 | `word-check.webp` | Word page, step 3 |

**What to send:** the raw screen recording (`.mov`) and the screenshots as
PNGs, in any folder. I produce the web files: small, sharp, silent, and
checked in a browser before they go up.

## The loop video: about 24 seconds, silent, seamless

It plays muted and on repeat beside the headline, so it has to explain itself
without sound and read at a glance: one document, five things LingTeX-Word
does, back to the start.

### Set up once

- **Region: 16:9.** macOS Screenshot (Cmd+Shift+5) > *Record Selected Portion*,
  a selection of **1600 x 900**. Options: *Show Mouse Clicks* on, microphone
  off. Size Word's window to fill the selection exactly.
- **Word:** light appearance (the website is light), the **Interlinear** tab
  selected, zoom about **140%** so the text stays legible when scaled down,
  navigation pane and comments closed, no account name or avatar in view.
- **The document:** titled something real, e.g. *Fayu grammar -- Chapter 3*.
  A heading ("3.2 Serial verb constructions"), one sentence of prose, then
  empty space. Below the empty space, out of view at first, three typed lines
  for shot 4: words, glosses, translation.
- **Clipboard:** copy the FLEx example before you start recording, so the
  recording can open inside Word.
- **Settings:** the add-in's defaults (numbering on, By Word, Re-wrap on Leave
  on), so what the video shows is what a new user gets.
- **Cursor:** move deliberately, pause half a second before each click, never
  hunt. Record each shot as its own take if that is easier; I cut them together.

### Shots

| # | Time | On screen | Caption I overlay |
|---|---|---|---|
| 0 | 0:00-0:02 | The clean page: heading, prose, cursor on the empty line. This is also the loop's last frame. | -- |
| 1 | 0:02-0:06 | Click **Insert Interlinear**. Example (1) appears: aligned columns, small-capital glosses, the translation in quotes. Hold a beat. | Paste from FLEx |
| 2 | 0:06-0:11 | Click in a gloss cell and type a longer gloss (e.g. *take* to *take.hunting*); click below the example. Columns flow onto the next line. | Re-wraps as you edit |
| 3 | 0:11-0:15 | Cursor in a cell with a clitic (*kada=te*). Click **Split Column**: *kada* and *=te* become two columns on both tiers. | Split at morpheme breaks |
| 4 | 0:15-0:20 | Scroll a little. Select the three typed lines, click **Text to Interlinear**, answer 1. Example (2) appears under (1). | Typed lines, too |
| 5 | 0:20-0:23 | Hold on the page with (1) and (2). | Numbered by Word |
| -- | 0:23-0:24 | I cross-fade back to shot 0 for a seamless loop. | -- |

If a step takes longer live, record it at its real speed: I speed up typing
and waiting (up to 2x) and trim, never the moments something changes.

**Leave out:** error dialogs, the Settings dialog (a screenshot shows it
better), anything personal in the title bar, and FLEx itself -- switching
windows breaks the loop, and the caption says where the text came from.

### What I do with it

```bash
# 1280x720, H.264, no audio, streams while downloading; aim for under 3 MB
ffmpeg -i take.mov -vf "fps=30,scale=1280:-2:flags=lanczos" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an word-loop.mp4
```

```bash
# the same in WebM (VP9) for browsers that prefer it, usually smaller
ffmpeg -i take.mov -vf "fps=30,scale=1280:-2:flags=lanczos" -c:v libvpx-vp9 -b:v 0 -crf 38 -row-mt 1 -an word-loop.webm
```

```bash
# the poster: the first frame, shown before the video plays
ffmpeg -i word-loop.mp4 -frames:v 1 -q:v 3 word-loop.jpg
```

Captions are drawn in during the cut, and the cross-fade makes the seam. If
text looks soft at 1280 wide, I raise quality (lower CRF) before raising size.

## The three screenshots: 16:10, PNG

Same Word setup, a **1600 x 1000** selection (Cmd+Shift+4, then drag, or
Cmd+Shift+5 > *Capture Selected Portion*). I convert them to WebP.

1. **`word-insert`** -- the Interlinear tab in full, with a freshly inserted
   numbered example below it. The ribbon is the point: every group visible.
2. **`word-rewrap`** -- one longer example wrapped onto two or three lines on
   a page with narrower margins, with the translation under it.
3. **`word-check`** -- an example with one mismatched break, and the Check
   Glossing message open beside it.
