# Releasing LingTeX-Word

The template is built in Word by hand, verified by scripts, committed, and
shipped by a GitHub Actions workflow. In that order, because the VBA project
inside a `.dotm` is a binary only Word writes, and no GitHub runner has Word.

## 1. Build the template in Word (Mac, the dev rig)

With the dev rig loaded and the runner green (`sh tools/run-in-word.sh`):

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

## 2. Publish

Push a tag from the commit that holds the template:

```bash
git tag word-v0.1.0-beta.1 && git push origin word-v0.1.0-beta.1
```

(Or, once the workflow file is on the default branch, GitHub → Actions →
**LingTeX-Word pre-release** → Run workflow, with a label such as `beta.1`.) The workflow re-runs `check-dotm.sh`, builds
`LingTeX-Word-Setup-word-v0.1.0-<label>.exe` with NSIS (`install/installer.nsi`),
packs `LingTeX-Word-word-v0.1.0-<label>-windows.zip` (template, `install.bat`,
`install.ps1`, `INSTALL.md`, the guide), builds `-macos.dmg` on a macOS runner
(template, the **Install LingTeX-Word** and **Uninstall LingTeX-Word** script
documents, the guide), and publishes them as a pre-release tagged
`word-v0.1.0-<label>`.

## 3. Verify the release itself, on each platform

Not the dev rig: the files a user would download.

**Windows** (the VM): download the `.exe`, close Word, run it (SmartScreen:
More info → Run anyway), start Word. Expect the installed message with the shortcuts,
the Interlinear tab, and then, from Alt+F8: `RunAllTests` (79) and `RunDocTests`
(all green; it writes `RunDocTests.win.txt` beside the template in STARTUP,
which the Immediate window may cut short). Then the by-hand basics: insert
the sample, re-wrap after narrowing the margins, split and merge, check,
indent, Ctrl+Alt+Shift+I inserts. Then the upgrade path: open Word and run
the `.exe` again. It must refuse until Word is closed, then replace the file;
start Word and check with **Shortcuts** that the keys are still bound.

**Mac**: move `LingTeX-Dev.dotm` out of the Startup folder first (the dev rig
would load a second copy of the code), quit Word, open the `-macos.dmg`,
double-click **Install LingTeX-Word** and press Run in Script Editor, start
Word, Enable Macros, and the same checks with Cmd+Option+Shift. Afterwards run
**Uninstall LingTeX-Word** the same way and put the dev template back.

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
