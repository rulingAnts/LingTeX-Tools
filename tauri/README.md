# LingTeX Tools — Desktop App (Tauri)

A native desktop app that sits in the system tray (Windows) or menu bar (macOS) and
auto-converts your clipboard OS-wide — no browser required.

## How it works

The app runs a background clipboard monitor. When you copy interlinear text from
FLEx (or tab-separated rows from Phonology Assistant / Dekereke), the monitor
detects the change and — if **Auto re-copy** is toggled on — instantly converts
it using your active profile and writes the LaTeX result back to the clipboard.
Then you just paste (`Ctrl+V` / `Cmd+V`) wherever you need it.

- **System tray / menu bar icon** — click to show or hide the window
- **Close button** hides to tray (the app keeps running in the background)
- **Quit** from the tray menu to fully exit
- **Per-profile keyboard shortcuts** — configure in each tab's Configuration panel;
  shortcut fires OS-wide, converts the clipboard with that profile, and re-copies

## Prerequisites

1. **Rust** — install from [rustup.rs](https://rustup.rs)
2. **Tauri CLI** — after Rust is installed:
   ```bash
   cargo install tauri-cli --version "^2"
   ```
3. **Platform build tools**:
   - **macOS** — Xcode Command Line Tools (`xcode-select --install`)
   - **Windows** — Visual Studio C++ build tools or VS 2022
   - **Linux** — `libwebkit2gtk-4.1`, `libgtk-3`, `libayatana-appindicator3` (see [Tauri Linux deps](https://tauri.app/start/prerequisites/#linux))

## Running in development

```bash
cd tauri
./build.sh --dev
```

This syncs `docs/core.js` into `src/` and launches a live-reloading dev window.

## Building a release binary

```bash
cd tauri
./build.sh
```

Outputs to `tauri/src-tauri/target/release/bundle/`. Platform-specific:
- **macOS** → `.dmg` + `.app`
- **Windows** → `.msi` + `.exe`
- **Linux** → `.deb` + `.AppImage`

## Icons

All icon sizes are pre-generated in `src-tauri/icons/` from the 128 × 128 source PNG.
If you replace the icon, regenerate with:

```bash
cargo tauri icon path/to/new-icon.png
```

## Project layout

```
tauri/
├── src/
│   ├── index.html    # UI (based on browser extension popup)
│   ├── popup.js      # App logic (adapted popup.js with Tauri integration)
│   └── core.js       # Synced from docs/core.js by build.sh
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/
│   │   └── default.json
│   ├── icons/        # All icon sizes (PNG, ICNS, ICO)
│   └── src/
│       ├── lib.rs    # Rust backend: clipboard monitor, tray, commands
│       └── main.rs   # Entry point
└── build.sh          # Convenience build/dev script
```
