# LingTeX-Word — first run, on a Mac

The engine is written and its algorithms are covered by 78 automated assertions,
but **it has never run inside Word.** This is the path to changing that, in
stages, so that when something breaks you know which thing broke.

Throughout: the VBA editor is **Tools → Macro → Visual Basic Editor** on Mac,
**Alt+F11** on Windows. The Immediate window is **View → Immediate Window**; it is
where you type commands and where all output appears.

---

## Step 0 — run the probe first (5 minutes)

**Do this before anything else.** Five things the add-in does with Word's object
model are assumptions I could not verify without Word. If one of them is wrong,
the engine fails in a way that looks like a logic bug and we waste a round trip
chasing it. The probe answers them all in one run.

1. VBA editor → **File → Import File…** → `tools/probe/modProbe.bas`
   (If your editor has no Import, use `build/paste/00-modProbe.txt` instead —
   see *If you have to paste* below.)
2. In the Immediate window, type `ProbeWord` and press Return.
3. Select the whole report, copy it, and send it back to me.

It creates one hidden document and three temporary styles and deletes all of them
before finishing. Your own documents are never touched.

The two findings that matter most:

- **"3. Autofit cell widths"** decides how every column is sized. It should say
  `USABLE — widths increase with the text`. If it says `UNUSABLE` or `SUSPECT`,
  stop and send the report: the fallback method has to become the default, and
  nothing downstream will look right until it does.
- **"14. VBProject access and Import"** decides how much manual work the rest of
  this costs. If it says `AVAILABLE`, one pasted bootstrap can import everything
  and build the template. If `BLOCKED`, it is thirteen File → Import File… picks
  instead — dull but completely reliable.

### Also worth 60 seconds: the AppleScript bridge

`tools/probe/Probe AppleScript Bridge.applescript` asks Word whether it exposes
VBA to AppleScript. Double-click it — it opens in Script Editor as plain text —
and press Run. It creates and changes nothing; it only asks.

If Word answers yes, two things get better: building the template becomes fully
scripted instead of thirteen manual imports, and the Mac installer can verify
itself by running a macro after installing rather than copying a file and hoping.
That second one matters, because the known silent failure is macOS quarantining a
`.dotm` that arrived inside a downloaded zip — Word then refuses to load it and
you see a successful install with no ribbon.

Each candidate term is wrapped in `run script` so the file still compiles even
when Word has never heard of the term; otherwise an unknown term would stop the
script compiling and we would learn nothing.

---

## Step 1 — six modules, no document touched

These six compile and run entirely on their own, and they exercise every
parsing, projection, invariant and wrap-planning path **without Word's object
model being involved at all**:

```
src/modFlexParse.bas      src/modWrap.bas
src/modIgtModel.bas       src/clsIgtWarning.cls
src/modLeipzig.bas        src/modTests.bas
```

Import all six, then in the Immediate window:

```
RunAllTests
```

**Expect every line to read `PASS`, and the last line to begin `ALL PASS`.**

This is the gate. Passing it means the VBA port compiles and computes correctly —
no dialect problem, no typo, no bad `ReDim`. Anything that breaks later is then
unambiguously Word's object model, not the logic.

If a line reads `FAIL`, it prints the actual and expected values. Send me those
two lines; that is usually enough.

---

## Step 2 — the other seven, and the real thing

```
src/modStyles.bas         src/modReadBack.bas
src/modSettings.bas       src/modLingTeX.bas
src/modMeasure.bas        src/clsAppEvents.cls
src/modRender.bas
```

Run `AutoExec` once in the Immediate window to arm the save hook (or just restart
Word).

Then, in a new document, the three tests worth doing before any others:

### 2a. Does an example appear at all?

Paste this into the document as **plain text** (⌘⇧V, or Edit → Paste Special →
Unformatted Text) so the tabs survive — or copy a real interlinear selection out
of FLEx:

```
Morphemes	zel	vimo			rixu			=xo	xu	=zevi	Ozivela	ze	:	zel	vimo			rixu			=xo	Vo	vu	=ve	levo			=zi	zo	z	zuvo	=ve	=zi
	Lex. Gloss	yam		pick	.CMP		stack	.CMP	SEQ	3SG	all	P.N.	ACMP		yam		pick	.CMP		stack	.CMP	SEQ	P.N.	fox	ERG		follow	.CMP	REL	FOC	1SG	dream	ABL	REL
Free Eng (When) she picked her yams early.
```

Select it and run `LingTeXInsertInterlinear`.

You should get a borderless table: each form sitting directly above its gloss,
`SEQ` `ERG` `FOC` `3SG` in small capitals, `yam` `pick` `stack` not, the object
language italic, and the free translation below in single quotes.

### 2b. Does it wrap — and unwrap?

This round trip is the entire thesis of the design, so it is the test that matters
most:

1. Narrow the page margins. Run `LingTeXRewrapCurrent`. Columns should **push
   down** onto another wrap line.
2. Widen them again. Run `LingTeXRewrapCurrent`. Columns should be **pulled back
   up** and the extra line should disappear.
3. Run it a third time without changing anything. **Nothing should move.**

### 2c. Does the alignment stay honest?

Put the cursor in the `rixu=xo` column and run `LingTeXSplitColumn`. You should
get two columns — `rixu` / `stack.CMP` and `=xo` / `=SEQ` — with the `=` leading
the cell on **both** rows, and the free translation untouched.
`LingTeXMergeColumns` with the cursor in `rixu` should put it back.

Then `TESTING.md` section 3 at whatever depth is useful.

---

## When something goes wrong

**Columns are obviously the wrong width, or all the same width.**
This is the known risk. Open `modMeasure.bas` and change

```vba
Private Const USE_AUTOFIT As Boolean = True
```

to `False`. That switches from reading autofitted cell widths to reading
`Range.Information` positions — a second method that is already written and
tested in the same code path. Re-run. **Try this before debugging anything
else**, and tell me which setting worked, because it decides the shipped default.

**"Compile error: User-defined type not defined"**
A module is missing. VBA compiles the whole project at once, so stage 1 works only
because those six reference nothing in the other seven — but within a stage,
everything has to be present.

**"Invalid attribute in Sub or Function" or an error on the very first line**
You pasted a file that still has its `Attribute VB_Name` line. Use the
`build/paste/` copies, which have it stripped, or import the `src/` files instead.

**`clsAppEvents` will not compile**
It has to be a **Class Module**, not a standard module — it declares
`Private WithEvents mApp As Word.Application`, which is only legal in a class.
Delete it and re-insert via Insert → Class Module.

**Nothing happens, no error**
Check `Application.ScreenUpdating` got turned back on: type
`Application.ScreenUpdating = True` in the Immediate window. Every command
restores it, including on error, but if a command was interrupted mid-flight the
screen can be left frozen.

**A hidden document is left open**
`ReleaseScratch` closes the measurement document; every command calls it, error
path included. If the Window menu shows a stray blank document, type
`ReleaseScratch` in the Immediate window.

---

## If you have to paste

Only needed if your VBA editor has no **File → Import File…**. Generate the
stripped, paste-ready copies:

```bash
sh LingTeX-Word/tools/make-paste-bundle.sh
```

That writes `build/paste/` with one file per module, numbered in the order above,
each headed with the exact module name to set and whether to insert a *Module* or
a *Class Module*. Read `build/paste/00-README.txt` first. The directory is
generated and gitignored — re-run the script after any change to `src/`.

Pasting an exported `.bas` or `.cls` **directly** does not work: the
`Attribute VB_Name` line is a compile error when typed, the `.cls` files carry a
`VERSION`/`BEGIN`/`END` preamble, and `clsAppEvents` has an
`Attribute mApp.VB_VarHelpID` line buried mid-file. The generator removes all of
it.

---

## What this does and does not prove

Mac Word is the stricter target — no ActiveX, no `Scripting.Dictionary`, no
`Application.UndoRecord`, sandboxed file I/O — so passing here means Windows Word
is very likely fine. Two things it cannot cover, for one pass on Windows later:

- The **NSIS installer**, which does not exist yet and is Windows-only.
- The **single-step undo** path. `Application.UndoRecord` is Windows-only and
  compiled out by `#If Mac Then`, so on Mac undo is multi-step by design. Repeated
  ⌘Z undoing an insert is correct behaviour here, not a bug.
