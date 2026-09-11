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
2. Run `ProbeWord`, either from **Tools → Macro → Macros…** (Mac) / **Alt+F8**
   (Windows), or by typing `ProbeWord` into the Immediate window.
3. It opens a **new document containing the report** and shows a dialog saying so.
   Select all of that document, copy, and send it back.

**If nothing seems to happen:** `Debug.Print` output appears *only* in the VBA
editor's Immediate window (**View → Immediate Window**), so with that window
closed a run looks identical to no run at all. The probe now also delivers its
report as a new document and a dialog, so if you see neither of those, the module
genuinely did not run — check for a macro-security prompt, and use
**Debug → Compile** to confirm it compiled.

It creates one hidden document and three temporary styles and deletes all of them
before finishing. Your own documents are never touched.

The two findings that matter most:

- **"3. Autofit cell widths"** decides how every column is sized. It should say
  `USABLE — widths increase with the text`. If it says `UNUSABLE` or `SUSPECT`,
  stop and send the report: the fallback method has to become the default, and
  nothing downstream will look right until it does.
- **"14. VBProject access and Import"** decides how much manual work the rest of
  this costs. If it says `AVAILABLE`, one pasted bootstrap can import everything
  and build the template. If `BLOCKED`, it is fourteen File → Import File… picks
  instead — dull but completely reliable.

### Also worth 60 seconds: the AppleScript bridge

`tools/probe/Probe AppleScript Bridge.applescript` asks Word whether it exposes
VBA to AppleScript. Double-click it — it opens in Script Editor as plain text —
and press Run. It creates and changes nothing; it only asks.

If Word answers yes, two things get better: building the template becomes fully
scripted instead of fourteen manual imports, and the Mac installer can verify
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

Import the five `.bas` files with **File → Import File…**.

**Do not import `clsIgtWarning.cls`** — paste it instead. See
*Class modules are pasted, never imported* below. The same applies to
`clsAppEvents.cls` in step 2. This is not a preference; importing a `.cls`
silently produces a standard module often enough that it is not worth trying.

Then, in the Immediate window:

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

## Step 2 — the other eight, and the second gate

```
src/modStyles.bas         src/modReadBack.bas
src/modSettings.bas       src/modLingTeX.bas
src/modMeasure.bas        src/modDocTests.bas
src/modRender.bas         src/clsAppEvents.cls
```

`clsAppEvents.cls` is a **class module** — paste it, do not import it. See *Class
modules are pasted, never imported*.

### The gate: `RunDocTests`

```
RunDocTests
```

Around 95 checks against Word's actual behaviour — styles, settings, text
measurement, page geometry, and the scratch-document lifecycle. **Expect
`ALL PASS`.** It works only in blank documents it creates and closes without
saving, it touches nothing you have open, and it asserts at the end that it left
the document count where it found it.

Run this *before* the manual tests below. Almost every way the document layer can
be wrong produces a wrong layout **silently** rather than an error — a font
assignment that did not take, a style that was skipped, a measurement that
returned zeros — and all of them look exactly like "the wrap algorithm is broken",
which is the one part already proven. Looking at a rendered example cannot tell
those apart. These checks can.

Two of them are worth knowing by name:

- **`widths are strictly increasing for i < iii < WWW`** — if measurement has
  failed in any way, it returns zeros, and zeros are indistinguishable from empty
  cells. This one assertion makes that whole class visible at once.
- **`measured width of ERG matches the drawn width`** — measurement and drawing
  are separate code paths that must produce the same glyphs. Nothing in the design
  enforces that; only this comparison does.

If a section reports `CRASH`, the run continues to the next one — send me the
whole report. A crashed section is usually a VBA construct that compiles and then
will not execute, which is precisely what no amount of reading finds.

### Then arm the save hook

Run `AutoExec` once in the Immediate window (or just restart Word).

### Then, in a new document, the three tests worth doing before any others:

### 2a. Does an example appear at all?

Paste this into the document as **plain text** (⌘⇧V, or Edit → Paste Special →
Unformatted Text) so the tabs survive — or copy a real interlinear selection out
of FLEx:

```
Morphemes	dae	kudi			kada			=te	bo	=taha	Edefina	bi	:	dae	kudi			kada			=te	Su	di	=de	deda			=di	bu	a	bujo	=de	=di
	Lex. Gloss	dog		take	.CMP		carry	.CMP	SEQ	3SG	two	P.N.	ACMP		dog		take	.CMP		carry	.CMP	SEQ	P.N.	pig	ERG		attack	.CMP	REL	FOC	1SG	speak	ABL	REL
Free Eng (When) she took her dogs hunting.
```

Select it and run `LingTeXInsertInterlinear`.

You should get a borderless table: each form sitting directly above its gloss,
`SEQ` `ERG` `FOC` `3SG` in small capitals, `dog` `take` `carry` not, the object
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

Put the cursor in the `kada=te` column and run `LingTeXSplitColumn`. You should
get two columns — `kada` / `carry.CMP` and `=te` / `=SEQ` — with the `=` leading
the cell on **both** rows, and the free translation untouched.
`LingTeXMergeColumns` with the cursor in `kada` should put it back.

Then `TESTING.md` section 3 at whatever depth is useful.

---

## When something goes wrong

**Columns are obviously the wrong width, or all the same width.**
This was the known risk, and the probe settled it. Measurement reads
`Range.Information` positions, verified working on Word 16.112 for Mac. The
autofit method it used to prefer has been **deleted**: on that build
`AutoFitBehavior wdAutoFitContent` returned four identical widths that summed to
the page width — it had divided the page equally and never consulted the content.

So there is no constant to flip any more. If widths still come out wrong, run
`ProbeWord` again and send me section 5, which is the measurement everything now
depends on.

**"Compile error: User-defined type not defined"**
A module is missing. VBA compiles the whole project at once, so stage 1 works only
because those six reference nothing in the other seven — but within a stage,
everything has to be present.

**"Invalid attribute in Sub or Function" or an error on the very first line**
You pasted a file that still has its `Attribute VB_Name` line. Use the
`build/paste/` copies, which have it stripped, or import the `src/` files instead.

**`clsAppEvents` or `clsIgtWarning` will not compile**
**This is the most likely thing to go wrong, and it is always the same cause.**
It has to be a **Class Module**, not a standard module — `clsAppEvents` declares
`Private WithEvents mApp As Word.Application`, which is only legal in a class.
If you see `VERSION 1.0 CLASS` / `BEGIN` / `END` sitting in the code, or
complaints about `WithEvents` or `New`, it came in as a standard module: delete it
and redo it with Insert → Class Module and the paste file. See *Class modules are
pasted, never imported*.

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

## Shortcut if you are on Windows: import them automatically

On Windows, VBA is allowed to rewrite its own project once one setting is on, and
then a single pasted macro can import all fourteen modules and save the template.

1. **File → Options → Trust Center → Trust Center Settings… → Macro Settings**,
   tick **"Trust access to the VBA project object model"**, restart Word.
2. Paste `tools/ImportModules.bas` into a new module named `modImport`, and set
   `SRC_FOLDER` at the top to your clone's `LingTeX-Word/src` path.
3. Run `ImportLingTeXModules`. Re-running is safe — it replaces modules rather
   than duplicating them, so it is also how to pick up later edits to `src/`.
4. Optionally run `SaveAsTemplate` to write `LingTeX-Word.dotm`.

**This does not work on Mac.** There is no equivalent setting in Word's interface,
and the probe found the access blocked on Word 16.112 with no way to grant it
(error 6068). On Mac, import by hand.

The template it produces is cross-platform, so building on Windows and testing on
Mac is a perfectly good split — nothing about the `.dotm` is Windows-specific.

A note on that setting: it exists because it lets code rewrite code, and it is
worth respecting. This add-in never asks an *end user* to enable it, and its
installer does not touch it. It is for whoever builds the template, on their own
machine, and turning it back off afterwards costs nothing.

---

## Building `LingTeX-Word.dotm`

Two steps, and the order matters. Word can save the VBA project into a template,
but it has no way to put a **custom ribbon** in one — the ribbon is a plain-XML
part its interface does not expose. So Word does the macros and a script does the
ribbon.

**1. In Word** — with all fourteen modules imported:

```
File → Save As → Word Macro-Enabled Template (.dotm)
  to  LingTeX-Word/LingTeX-Word.dotm
```

Not `.dotx`, which silently drops the macros. Not under any `dist/`, which
`.gitignore` matches at any depth. `SaveAsTemplate` in `tools/ImportModules.bas`
does the same thing without the dialog.

**2. Outside Word** — inject the ribbon and record what it was built from:

```bash
sh LingTeX-Word/tools/build-dotm.sh
sh LingTeX-Word/tools/check-dotm.sh      # the same check CI runs
```

`build-dotm.sh` needs only `zip`, `unzip` and a SHA-256 tool — no Word, no
PowerShell, no Python — so it runs on macOS, on Linux, and in CI. If you have no
shell handy, push the `.dotm` and it can be injected for you; the macros work from
the VBE either way, and only the seven ribbon buttons need this step.

**Save from Word first, inject last.** Saving again from Word discards the injected
part, so every re-save means re-running `build-dotm.sh`.

### What the drift guard is for

The template is a committed binary built by hand, so the usual guarantee — that
what ships is what is in the repository — does not hold for free. Two ways it can
quietly stop holding, neither of which shows up in a diff:

- someone fixes a module in the VBA editor and never exports it back to `src/`, so
  the shipped template contains code that is nowhere in the repository;
- someone edits `src/customUI14.xml` and does not re-run `build-dotm.sh`, so the
  reviewable ribbon is not the ribbon that ships.

`check-dotm.sh` catches both, along with a `.dotx` saved by mistake, a template
saved before the modules were imported, a missing ribbon relationship, and a
relationship whose *type* does not match the ribbon's XML namespace — which is the
most confusing failure of the lot, because Word then loads the template and shows
no ribbon, with no error anywhere.

Keep `src/` authoritative: any fix made in the VBA editor goes back out with
**File → Export File** before `build-dotm.sh` runs.

---

## Class modules are pasted, never imported

`clsIgtWarning.cls` and `clsAppEvents.cls` are the two class modules, and they are
the one part of this that does **not** go through File → Import File…

The VBA editor decides what kind of component an imported file becomes by parsing
its header. When it misreads the `.cls` preamble it creates a **standard module**
instead, leaving

```
VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
```

in the code as syntax errors. The module then cannot compile at all — `clsAppEvents`
declares `Private WithEvents mApp As Word.Application`, which is legal only in a
class — and it reads as a bug in the module rather than as a bad import.

Bare-LF line endings are one way to trigger it, which is why `.gitattributes` now
pins `*.bas` and `*.cls` to CRLF in the working tree. But rather than depend on
that holding on every clone, do it the way that cannot go wrong:

```bash
sh LingTeX-Word/tools/make-paste-bundle.sh
```

Then for each of `build/paste/05-clsIgtWarning.txt` and
`build/paste/13-clsAppEvents.txt`:

1. **Insert → Class Module**
2. Paste the whole file
3. Properties pane → `(Name)` → the name the file's header gives
4. Properties pane → `Instancing` → `1 - Private`

Step 4 is the default for a new class module, so there is normally nothing to
change — check it rather than set it. The header of each generated file repeats all
four steps, and derives the Instancing value from the source file's own attributes
so it cannot drift.

Confirm it worked, in the Immediate window:

```
?TypeName(New clsIgtWarning)
```

That prints `clsIgtWarning`. If it errors, the module is still a standard module.

`tools/ImportModules.bas` handles this correctly on its own — it creates class
components explicitly with `VBComponents.Add` and never calls `Import` on a
`.cls`. So if the Windows shortcut below is available to you, it is the path with
the fewest steps *and* the fewest ways to go wrong.

---

## If you have to paste

Needed for the two class modules always, and for everything else only if your VBA
editor has no **File → Import File…**. Generate the stripped, paste-ready copies:

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

## Status

**Stage 1 passes on Word 16.112 for Mac: `ALL PASS -- 79 passed`.** Every
parsing, projection, routing, column-editing, Leipzig-check, gloss-detection and
wrap-planning assertion, inside real Word VBA. Windows is still to do — see below.

Getting there found four real bugs that the JavaScript harness structurally could
not: `any` used as a variable name (reserved in VBA), `IsGramGloss` accepting
`P.N.`, a function's array return passed into a `ByRef` array parameter, and a
run-time Overflow whose cause is still not understood (see *An unexplained
failure* below).

---

## Stage 1 must pass on BOTH platforms before stage 2

Originally this said Mac was the stricter target, so passing there implied Windows
was fine. That is no longer a safe assumption.

`MicroDiagnose` on Word 16.112 for Mac produced run-time error 6, *Overflow*, on
`s1 = 10` where `s1` is declared `As Single` — a primitive that cannot fail on a
correct implementation. Whatever the explanation turns out to be, it is a
**numeric type behaving differently**, not a logic error. And the wrap planner is
nothing but arithmetic over two arrays: if `Single` and `Double` differ between
builds, the same example could be measured into different column widths on each
platform, and the failure would look like a layout bug rather than a type bug.

So: run `RunAllTests` on Windows Word as well, and get `ALL PASS` on both, before
any of the document-rendering work is built on top. A discrepancy found now is a
type declaration; found later it is a mis-rendered table with no obvious cause.

`tools/ImportModules.bas` makes the Windows side cheap — one paste imports all
fourteen modules, and re-running re-syncs them after any pull.

---

## An unexplained failure, worth knowing about

During stage 1 a `Dim s1 As Single` / `s1 = 10` assignment raised run-time error
6, *Overflow* — in one procedure, while the identical assignment in a smaller
procedure in the same module worked, and `TypeCheck` confirmed every numeric type
including `Single` behaves correctly on this build.

Restructuring the failing code into smaller procedures resolved it. **But that is
not a diagnosis.** The obvious theory — "large procedures with many array locals
fail" — does not survive contact with the evidence: `ModelFromBlock` is one of the
largest procedures in the project, declares several arrays, and passes. The
modules had also been removed and re-imported many times by that point, so a
corrupted project state is at least as plausible an explanation as anything in the
code.

Why it matters for stage 2: several engine procedures are large and declare
multiple array locals — `RenderExample`, `MeasureExample`, `MeasureTexts`,
`FillTable`. If one of them fails with an inexplicable run-time error, **try
splitting it into smaller procedures before assuming the logic is wrong**, and
try a clean re-import of the module first. Do not spend an afternoon on the
arithmetic.

---

## What this does and does not prove

Mac Word is the stricter target — no ActiveX, no `Scripting.Dictionary`, no
folder picker, no programmatic VBA-project access, sandboxed file I/O — so passing
here means Windows Word is very likely fine. Two things it cannot cover, for one
pass on Windows later:

- The **NSIS installer**, which does not exist yet and is Windows-only.
- Whether custom **ribbon XML** in a STARTUP `.dotm` loads.

Single-step undo is no longer on that list. An earlier version assumed
`Application.UndoRecord` was Windows-only and compiled it out on Mac; the probe
found it present, so one ⌘Z should now undo a whole insert or re-wrap on either
platform. If it takes several presses, that is worth reporting.
