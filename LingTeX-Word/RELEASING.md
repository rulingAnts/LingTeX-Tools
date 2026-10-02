# Releasing LingTeX-Word

The template is built in Word by hand, verified by scripts, committed, and
shipped by a GitHub Actions workflow. In that order, because the VBA project
inside a `.dotm` is a binary only Word writes, and no GitHub runner has Word.

## 1. Build the template in Word (Mac, the dev rig)

With the dev rig loaded and the runner green (`sh tools/run-in-word.sh`):

0. **Set the version.** `LINGTEX_VERSION` in `src/modLingTeX.bas` is the release
   being made (`0.1.0-beta.9` for the tag `word-v0.1.0-beta.9`); the first-run
   message and `LingTeXAbout` show it, and `check-dotm.sh` fails a tag that does
   not match it, or a version that did not move since the previous tag. Bump
   `SETUP_VERSION` too (below). Both are compiled in, so both come before the
   template build.
1. **Take the development shortcuts out of the engine**, or they ship inside
   the template and override the same keys on every user's machine: macro list
   → `LingTeXRemoveShortcuts`. (Users get their own set on first run, which
   respects whatever their Word already binds.)
2. Macro list → **`SaveAsTemplate`** (in the dev template). It unloads the
   engine, saves it as `LingTeX-Word/LingTeX-Word.dotm`, and loads the engine
   again.
3. Outside Word:

   ```bash
   sh LingTeX-Word/tools/build-dotm.sh      # ribbon, icons, manifest
   sh LingTeX-Word/tools/check-dotm.sh      # the drift guard; must say ALL PASS
   ```

4. Commit `LingTeX-Word/LingTeX-Word.dotm` and `src/MANIFEST.sha256` and push.

Any later change to `src/` means doing this again before the next release:
`check-dotm.sh` fails (in CI too) when the committed template and `src/`
disagree.

**`check-dotm.sh` also reads every compiled module out of the template and
compares it with `src/` line for line** (`tools/check-dotm-sources.py`), so the
template is proven to be the committed sources by construction — no word list.
It needs `python3` and `olefile`; run `pip install olefile` once locally, or the
step says SKIP and proves nothing. The release workflow requires it and cannot
skip. It also fails a class or form that went in double-spaced, and a template
built with the old `modImport` (2026-09-15). The step after it fails a
template whose own document body holds any text, or that carries document
variables, comments, notes, headers, footers or AutoText: the release
template is code and ribbon and nothing else. It names any variables it
finds; `LingTeX_DevRoot` means `SetDevRoot` was run against the engine
instead of the dev template — remove it from the engine and save again.

## 2. Publish

Push a tag from the commit that holds the template. The tag must be
`word-v<LINGTEX_VERSION>` of that commit: the local `.git/hooks/pre-push`
refuses a `word-v*` tag whose commit's `src/modLingTeX.bas` says another
version (recreate that check when recreating the hook on a new clone; it
sits beside the main-push and workflow guards), and `check-dotm.sh` in the
release workflow fails the same mismatch before anything is published.

```bash
git tag word-v0.1.0-beta.1 && git push origin word-v0.1.0-beta.1
```

(Or, once the workflow file is on the default branch, GitHub → Actions →
**LingTeX-Word pre-release** → Run workflow, with a label such as `beta.1`.) The workflow re-runs `check-dotm.sh`, builds
`LingTeX-Word-Setup-word-v0.1.0-<label>.exe` with NSIS (`install/installer.nsi`),
packs `LingTeX-Word-word-v0.1.0-<label>-windows.zip` (template, `install.bat`,
`install.ps1`, `INSTALL.md`, the guide), builds `-macos.dmg` on a macOS runner
(template, the **Install LingTeX-Word** and **Uninstall LingTeX-Word** script
documents compiled to `.scpt` from the `.applescript` sources in `install/`, the
guide), runs the Windows installer for real on a Windows
runner (`.github/workflows/lingtex-word-installer-test.yml`: silent install,
upgrade, refusal while Word runs or the old file is held open, uninstall), and
publishes them as a pre-release tagged `word-v0.1.0-<label>` only when that
test passes. The same test runs on any push that touches the installer or the
template. The installer is built and tested on GitHub's runners, not with a
local makensis.

## 3. Verify the release itself, on each platform

Not the dev rig: the files a user would download.

**Windows** (the VM): download the `.exe`, close Word, run it (SmartScreen:
More info → Run anyway), start Word. Expect the installed message with the shortcuts,
the Interlinear tab, and then, from Alt+F8: `RunAllTests` (140) and `RunDocTests`
(all green; it writes `RunDocTests.win.txt` beside the template in STARTUP,
which the Immediate window may cut short). Then the by-hand basics: insert
the sample, re-wrap after narrowing the margins, split and merge, check,
indent, Ctrl+Alt+Shift+I inserts. Then the upgrade path: open Word and run
the `.exe` again. It must refuse until Word is closed, then replace the file;
start Word and check with **Shortcuts** that the keys are still bound.

**Mac**: quit Word and run `sh LingTeX-Word/tools/word-clean-slate.sh park`.
It moves every LingTeX file out of Word into `build/`: the dev rig (which would
otherwise load the engine from the clone and show its own Interlinear tab), any
installed or stale copy, and a saved copy of Normal.dotm. `status` shows what
Word can see. Then open the `-macos.dmg`, double-click **Install LingTeX-Word**
and press Run in Script Editor, start Word, Enable Macros, and the same checks
with Cmd+Option+Shift. Quit Word and run `... word-clean-slate.sh restore`,
which sets the test's install and its Normal aside and puts everything back.
Don't drag the dev template out in Finder instead: on 2026-09-14 that made a
copy, the original kept loading, and the test measured the dev rig.

## 4. Site

The site is `docs/`, served by GitHub Pages from the **`webProduction`**
branch. Its LingTeX-Word links are written for one release, and
`docs/assets/word-release.js` moves them, in the visitor's browser, to the
newest release that carries the installer, the Windows zip and the Mac file.
The written links are what everyone gets whom the script misses: JavaScript
off, `api.github.com` blocked by a filter, GitHub's hourly API limit used up on
a shared network, a click before the reply arrives. So after a release is
published:

1. In `docs/index.html` and `docs/word/index.html`, move every
   `word-v0.1.0-<label>` in the download links, and the version beside
   "LingTeX-Word" (`<span data-word="version">`), to the new tag. The asset
   names are on the release page (`gh release view <tag> --json assets`).
2. Check them:

   ```bash
   sh LingTeX-Word/tools/check-site-links.sh       # every release link on the site; must say ALL PASS
   node LingTeX-Word/tools/word-release.test.mjs   # the script's choice, and one release per page
   ```

3. Commit, and deploy: the site changes only when `webProduction` has the
   commit. That is Seth's step: bring the commit onto `webProduction` (a
   fast-forward where it can be one, otherwise a cherry-pick) and push it.

**If a release's files are ever withdrawn** (deleted, or the release emptied),
do the same at once with a release that still has all of them, and deploy it:
the script skips a release without its files, but nothing repairs the written
links. beta.6's files were deleted after the links were written for it, and
while beta.6 was the newest release the script of the day chose it too, so
every download said "Not Found" (#7, 2026-09-21). `check-site-links.sh` lists
any link that stopped answering 200, with the lines that use it.

## What the first run does

`AutoExec` in `modLingTeX` books `LingTeXFirstRun` for three seconds after
startup (`Application.OnTime`) when the template is loaded from Word's STARTUP
folder (never from a clone): it installs the shortcuts, records the setup
version in the Normal template, and shows one message. Not from `AutoExec`
itself: Word times each STARTUP template's load, a modal message counts for
as long as it is on screen, and the result was an add-in alert on Windows
offering to disable the add-in. **Bump
`SETUP_VERSION` in `modLingTeX` for every release**, not only when the
shortcut table changes: where Word lets the add-in store its bindings in
the template itself (Windows does), the installer's replacement of
`LingTeX-Word.dotm` throws them away, and only a moved `SETUP_VERSION`
makes the first run put them back at the next start. beta.2 → beta.3 kept
"2" and would have lost them; beta.4 moved to "3". `check-dotm.sh` now fails
when SETUP_VERSION equals the previous `word-v*` tag's, locally and in CI, so a
release cannot ship without the bump. It is compiled into the template, so a
release whose only change is packaging still needs a template rebuild in Word.

**Read the template's VBA references before tagging.** `check-dotm.sh` now
runs `tools/check-vba-refs.py`, which fails when the VBA project references
another VBA project. beta.3, beta.4 and beta.5 carried a reference to the
builder's own Normal template (`/Users/Seth/Library/Containers/.../Normal`),
added because SaveAsTemplate saved a macro-enabled *document*, and a document
references its attached template. As a document, Windows Word ignored it; once
beta.5 declared the package a template, Windows reported "Compile error in
hidden module: modLingTeX" and "Can't find project or library" (MISSING:
Normal), and any Mac but the builder's would too. SaveAsTemplate now saves
FileFormat 15. **After any change to `tools/ImportModules.bas`, re-paste
modImport into LingTeX-Dev.dotm before running SaveAsTemplate**, or the old
code does the saving. Before a tag, also load the release template in Windows
Word once: nothing on the Mac or in CI compiles it there.
