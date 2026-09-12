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

GitHub → Actions → **LingTeX-Word pre-release** → Run workflow, with a label
such as `beta.1`. The workflow re-runs `check-dotm.sh`, builds
`LingTeX-Word-Setup-word-v0.1.0-<label>.exe` with NSIS (`install/installer.nsi`),
packs `LingTeX-Word-word-v0.1.0-<label>-windows.zip` (template, `install.bat`,
`install.ps1`, `INSTALL.md`) and `-macos.zip` (template, `install.command`,
`install.sh`, `INSTALL.md`), and publishes them as a pre-release tagged
`word-v0.1.0-<label>`. Or from a terminal:

```bash
gh workflow run lingtex-word-release.yml -f label=beta.1
```

## 3. Verify the release itself, on each platform

Not the dev rig: the zip a user would download.

**Windows** (the VM): download the `.exe`, close Word, run it (SmartScreen:
More info → Run anyway), start Word. Expect the installed message with the shortcuts,
the LingTeX tab, and then, from Alt+F8: `RunAllTests` (79) and `RunDocTests`
(all green; it writes `RunDocTests.win.txt` beside the template in STARTUP,
which the Immediate window may cut short). Then the by-hand basics: insert
the sample, re-wrap after narrowing the margins, split and merge, check,
indent, Ctrl+Alt+Shift+I inserts.

**Mac**: move `LingTeX-Dev.dotm` out of the Startup folder first (the dev rig
would load a second copy of the code), quit Word, run `install.command` from
the macos zip, start Word, Enable Macros, and the same checks with
Cmd+Option+Shift. Put the dev template back afterwards.

## What the first run does

`AutoExec` in `modLingTeX` runs `FirstRunSetup` when the template is loaded
from Word's STARTUP folder (never from a clone): it installs the shortcuts,
records the setup version in the Normal template, and shows one message. Bump
`SETUP_VERSION` in `modLingTeX` to make every machine do it again at the next
start (for instance after the shortcut table changes).
