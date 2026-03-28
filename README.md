# LingTeX Tools

Linguistic fieldwork macro tools for LaTeX — available in four formats:

| Platform | Location | Notes |
|---|---|---|
| **Web app** | `docs/` · [rulingants.github.io/LingTeX-Tools](https://rulingants.github.io/LingTeX-Tools/) | Hosted on GitHub Pages; works offline via service worker |
| **Chrome / Edge extension** | `extension/chrome/` | MV3; auto-convert paste, per-profile keyboard shortcuts |
| **Firefox extension** | `extension/firefox/` | MV2; same features as Chrome |
| **Safari extension** | planned | Not yet available — Safari CI build currently failing |
| **Desktop app (Tauri)** | `tauri/` | Menu-bar / system-tray; OS-wide clipboard auto-convert |

## What it does

- **FLEx Interlinear** — converts copied FLEx interlinear text into a `\gll` block (langsci-gb4e / gb4e)
- **Phonology Assistant** — converts PA tab-separated clipboard rows into `\exampleentry` rows
- **Custom TSV profiles** — user-configurable row templates for any tab-separated source

Works with the [LingTeX template](https://github.com/rulingAnts/LingTeX) out of the box.
Every command name is configurable so the tools work with any LaTeX preamble.

---

## Repository layout

```
LingTeX-Tools/
│
├── docs/                        # Web app (GitHub Pages root)
│   ├── index.html               #   Single-page app — all UI + app logic inline
│   ├── core.js                  # ★ Conversion library — SINGLE SOURCE OF TRUTH
│   ├── sw.js                    #   Service worker for offline caching
│   └── manifest.json            #   Web app manifest (PWA)
│
├── extension/
│   ├── shared/                  # Source for all browser extension UI
│   │   ├── popup.html           #   Extension popup UI
│   │   ├── popup.js             #   Popup logic (chrome.storage.local, event delegation)
│   │   ├── content.js           #   Content script (paste intercept, keyboard shortcuts)
│   │   ├── background.js        #   Service worker / background script placeholder
│   │   └── icons/               #   Source icons (16 / 48 / 128 px PNG)
│   ├── chrome/
│   │   └── manifest.json        #   Chrome MV3 manifest (only tracked source file here)
│   ├── firefox/
│   │   └── manifest.json        #   Firefox MV2 manifest (only tracked source file here)
│   └── build.sh                 #   Syncs docs/core.js out to tauri/, chrome/, firefox/
│
├── tauri/
│   ├── src/                     # Tauri webview frontend
│   │   ├── index.html           #   Window HTML (based on extension popup)
│   │   └── popup.js             #   App logic (localStorage shim + Tauri API integration)
│   ├── src-tauri/               # Rust backend
│   │   ├── src/lib.rs           #   Clipboard monitor, system tray, Tauri commands
│   │   ├── tauri.conf.json      #   Tauri 2 configuration
│   │   ├── Cargo.toml           #   Rust dependencies
│   │   ├── capabilities/        #   Tauri permission declarations
│   │   └── icons/               #   App icons (PNG / ICNS / ICO)
│   ├── build.sh                 #   Syncs core.js, then runs cargo tauri build/dev
│   └── README.md                #   Tauri-specific setup instructions
│
├── .github/workflows/
│   ├── release.yml              # CI: builds all artifacts on version tag push
│   ├── build-macos.yml          # Manual pre-release build (macOS)
│   ├── build-windows.yml        # Manual pre-release build (Windows)
│   └── build-linux.yml          # Manual pre-release build (Linux)
├── .githooks/
│   └── pre-commit               # Blocks commits with files > 25 MB
├── .gitignore
├── INSTALL.md                   # End-user installation guide
└── README.md                    # This file
```

---

## Build system — how shared files flow

The conversion logic (`core.js`) and extension UI (`popup.html`, `popup.js`, etc.) are written
**once** and distributed into multiple targets by the build scripts. Nothing in
`extension/chrome/`, `extension/firefox/`, or `tauri/src/core.js` is a tracked source file —
they are all build outputs and are gitignored.

### Source of truth

```
docs/core.js
```

This is the **only** copy of the parsing and rendering library. It is a plain UMD script
that exposes `LingTeXCore.parseFLExBlock`, `LingTeXCore.renderFLEx`,
`LingTeXCore.parseTSVRow`, and `LingTeXCore.applyRowTemplate`. All platforms consume
this exact file — none of them have their own copy of the conversion logic.

`docs/core.js` is tracked in git and served directly by GitHub Pages to the web app.
**To edit the conversion logic, edit `docs/core.js`.**
Build scripts then distribute it to the other targets.

### How each platform gets core.js

| Platform | Mechanism |
|---|---|
| Web app | `docs/core.js` is tracked and served directly by GitHub Pages |
| Chrome extension | `extension/build.sh` copies `docs/core.js` → `extension/chrome/core.js` |
| Firefox extension | Same script, copied to `extension/firefox/core.js` |
| Safari extension | Built from the assembled Chrome directory, so it inherits the copy |
| Desktop app | `extension/build.sh` (or `tauri/build.sh`) copies `docs/core.js` → `tauri/src/core.js` |

### Extension assembly (`extension/build.sh`)

```
docs/core.js ────────────────────────────────────► tauri/src/core.js    (gitignored)
             ────────┬───────────────────────────► extension/chrome/
extension/shared/    │                             extension/firefox/
  popup.html ────────┤
  popup.js ──────────┤                                  (gitignored)
  content.js ────────┤
  background.js ─────┤
  icons/ ────────────┘
                         +
extension/chrome/manifest.json ──────────────────► extension/chrome/  (tracked)
extension/firefox/manifest.json ─────────────────► extension/firefox/ (tracked)
```

Running `extension/build.sh` syncs `docs/core.js` out to `tauri/src/` and copies every
file from `extension/shared/` into both `extension/chrome/` and `extension/firefox/`.
The only browser-specific tracked source files are the `manifest.json` files — these
differ in manifest version (MV3 vs MV2), action key names (`action` vs `browser_action`),
and background script format.

For distribution, `extension/build.sh --zip` additionally creates
`lingtex-tools-chrome.zip` and `lingtex-tools-firefox.zip`.

### Safari extension (CI only)

Safari is not assembled locally. The CI workflow (`release.yml`) converts the assembled
Chrome directory using `xcrun safari-web-extension-converter`, then builds the resulting
Xcode project with `xcodebuild` (unsigned). The `.app` bundle is zipped and attached to
the GitHub release. Local Safari development requires macOS + Xcode and is documented in
`INSTALL.md`.

### Desktop app (`tauri/build.sh`)

```
docs/core.js ───────────────────────────────────► tauri/src/core.js
                                                                 (gitignored)
tauri/src/index.html ─────────────────────────────────────┐
tauri/src/popup.js ───────────────────────────────────────┤──► Tauri webview
tauri/src/core.js (synced above) ─────────────────────────┘

tauri/src-tauri/src/lib.rs ───────────────────────────────►  Rust binary
  (clipboard monitor, system tray, write_clipboard command)     (gitignored in target/)
tauri/src-tauri/src/convert.rs  ◄── Rust port of docs/core.js
  (used by global shortcut handler)
```

#### Two conversion paths in the desktop app

The desktop app has two distinct conversion paths that use **different implementations**:

| Path | Where it runs | Source |
|---|---|---|
| Test area UI / auto re-copy | JavaScript (webview) | `tauri/src/core.js` (synced from `docs/core.js`) |
| Global keyboard shortcut | Rust (background thread) | `tauri/src-tauri/src/convert.rs` |

The keyboard shortcut runs from a background OS thread where the webview may be
hidden or throttled. Rust converts the clipboard directly without a JS round-trip,
which is more reliable. **`convert.rs` is a Rust port of `docs/core.js` and must be
kept in sync with it** — if you add or change conversion logic in `docs/core.js`,
make the same change in `convert.rs`.

---

`tauri/src/popup.js` is based on `extension/shared/popup.js` but is **not** a copy —
it has two key adaptations:

1. **`chrome.storage.local` shim** — `popup.js` references `chrome.storage.local`
   throughout. In the desktop app there is no extension runtime, so a thin shim backed
   by `localStorage` is prepended. The rest of the logic is unchanged.

2. **Tauri clipboard integration** — `copyOutput()` calls
   `window.__TAURI__.core.invoke('write_clipboard', { text })` instead of
   `navigator.clipboard.writeText()`. An `initTauri()` function listens for two Rust
   events:
   - `clipboard-changed` — emitted by the Rust background thread every time the OS
     clipboard changes; if Auto re-copy is enabled, the payload is converted and written
     back to the clipboard via `write_clipboard`
   - `profile-shortcut` — emitted when a registered global OS shortcut fires; carries
     the profile ID and the clipboard text at time of press

### CI release workflow (`.github/workflows/release.yml`)

Triggered by pushing a `v*` tag. Runs five parallel jobs, then publishes.

```
git tag v0.1.0 && git push origin v0.1.0
          │
          ▼
  create-release (ubuntu)
    └── softprops/action-gh-release → draft release (outputs release_id)
          │
          ├── extensions (macos-latest) ─────────────────────────────────┐
          │     ├── extension/build.sh --zip  → chrome.zip, firefox.zip  │
          │     ├── xcrun safari-web-extension-converter                  │
          │     │      └── xcodebuild (unsigned) → safari.zip            │
          │     └── gh release upload → attaches 3 extension zips        │
          │                                                               │
          ├── desktop-macos (macos-latest)                                │
          │     └── tauri-apps/tauri-action → .dmg + .app                │
          │                                                               │
          ├── desktop-windows (windows-latest)                            │
          │     └── tauri-apps/tauri-action → .msi + .exe                │
          │                                                               │
          └── desktop-linux (ubuntu-latest)                               │
                └── tauri-apps/tauri-action → .deb + .AppImage           │
                                                                          │
          publish-release (ubuntu) ◄────────────────────────────────────-┘
            └── gh release edit --draft=false → release goes live
```

---

## Development setup

### Clone and activate the pre-commit hook

```bash
git clone https://github.com/rulingAnts/LingTeX-Tools.git
cd LingTeX-Tools
git config core.hooksPath .githooks   # enables the 25 MB file-size guard
```

### Web app

Open `docs/index.html` in a browser, or run any local HTTP server:

```bash
python3 -m http.server 8080 --directory docs
```

### Browser extensions

```bash
cd extension
bash build.sh          # syncs shared/core.js → docs/, tauri/src/, chrome/, firefox/
```

Then load `extension/chrome/` (or `extension/firefox/`) as an unpacked extension.
See `INSTALL.md` for browser-specific steps.

### Desktop app (Tauri)

Requires Rust and the Tauri CLI — see `tauri/README.md` for full prerequisites.

```bash
cd tauri
bash build.sh --dev    # syncs core.js and launches cargo tauri dev
```

### Making changes to the conversion logic

Edit **`shared/core.js`** only — never edit the copies in `docs/`, `tauri/src/`,
`extension/chrome/`, or `extension/firefox/`. Then run the build script to propagate the
change to all targets:

```bash
cd extension && bash build.sh
```

This copies `shared/core.js` to `docs/core.js`, `tauri/src/core.js`, and both browser
extension directories in one step. Commit both `shared/core.js` and
`docs/core.js` — the `docs/` copy must be pushed so GitHub Pages serves the updated
web app.

---

## Coming in a future release

| Feature | Scope |
|---|---|
| **Multi-line FLEx group paste** — convert multiple interlinear line groups from one FLEx text in a single operation | Desktop &amp; extension |
| **FLEx corpus → LaTeX export** — export an entire FLEx corpus as a structured LaTeX document (full example appendix or corpus reference) | Extension |

---

## Related project

[LingTeX](https://github.com/rulingAnts/LingTeX) — a TeXstudio project template for
writing linguistic grammar descriptions, built on XeLaTeX, langsci-gb4e, and biblatex/biber.

## License

AGPL-3.0 — Copyright © Seth Johnston
