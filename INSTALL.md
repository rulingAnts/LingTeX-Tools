# Installation Guide — LingTeX Tools

All downloadable files are attached to each [GitHub Release](https://github.com/rulingAnts/LingTeX-Tools/releases/latest).

---

## Desktop App (macOS, Windows, Linux)

Download the installer for your platform from the [latest release](https://github.com/rulingAnts/LingTeX-Tools/releases/latest):

| Platform | File | Notes |
|---|---|---|
| **macOS** | `.dmg` | Unsigned — see steps below |
| **Windows** | `.msi` or `.exe` | Standard installer |
| **Linux** | `.deb` (Debian/Ubuntu) or `.AppImage` | See note below |

### macOS — first-launch steps

The app is currently **unsigned** (code-signing requires an Apple Developer Program membership).
macOS Gatekeeper will block it on first launch. Two things to do:

**Step 1 — Bypass Gatekeeper**

After installing the `.dmg`, right-click `LingTeX Tools.app` in your Applications folder and
choose **Open**, then click **Open** again in the security dialog.

Alternatively, run this once in Terminal:

```bash
xattr -cr "/Applications/LingTeX Tools.app"
```

**Step 2 — Grant Accessibility access**

When you first launch the app, macOS will prompt you to grant
**Accessibility** permission. Click **Open System Settings** and toggle LingTeX Tools on in
**Privacy & Security → Accessibility**.

This permission is required for global keyboard shortcuts and Auto re-copy to work.
If you accidentally dismiss the prompt, you can grant it manually in System Settings.

### Linux — community-maintained

The Linux build has **not been tested by the developer** — there is no Linux test machine.
In principle it should work: Tauri supports Linux, global shortcuts use X11/XWayland, and
the system tray requires `libappindicator` (available in most GNOME/KDE environments).

If you try it and run into issues — or get it working — please
[open an issue or PR](https://github.com/rulingAnts/LingTeX-Tools/issues). Contributions welcome.

---

## Web App

No installation needed. Open in any browser:

**[https://rulingants.github.io/LingTeX-Tools/](https://rulingants.github.io/LingTeX-Tools/)**

The web app works offline after your first visit (cached by a service worker).
It is the easiest way to get started, and is functionally identical to the
browser extensions — the difference is that the extension can intercept your
paste in Overleaf directly, while the web app requires a manual copy step.

---

## Browser Extensions

Download the appropriate zip from the [latest release](https://github.com/rulingAnts/LingTeX-Tools/releases/latest)
and follow the steps for your browser.

### Chrome / Edge / Chromium

1. Download **`lingtex-tools-chrome.zip`** and unzip it anywhere permanent
   (the folder must stay in place — Chrome loads from it directly)
2. Open **`chrome://extensions`** in Chrome (or `edge://extensions` in Edge)
3. Enable **Developer mode** (toggle in the top-right corner)
4. Click **Load unpacked** and select the unzipped `chrome/` folder
5. The LingTeX Tools icon appears in your toolbar
   — if it's hidden, click the puzzle-piece menu and pin it

> **Note:** Chrome will periodically warn you that you are running a developer
> extension. This is expected for extensions installed outside the Chrome Web Store.
> Click "Keep" to dismiss.

### Firefox

1. Download **`lingtex-tools-firefox.zip`** and unzip it
2. Open **`about:debugging#/runtime/this-firefox`** in Firefox
3. Click **Load Temporary Add-on…**
4. Navigate into the unzipped `firefox/` folder and select **`manifest.json`**

> **Note:** Firefox unloads temporary add-ons when it quits. To reload after
> restarting Firefox, repeat steps 2–4. For a persistent install, the extension
> would need to be signed through Mozilla's Add-on Developer Hub — see the
> [extension README](extension/README.md) for details.

### Safari (unsigned — macOS only)

The Safari extension is **unsigned** (signing requires an Apple Developer Program
membership). This means a couple of extra steps each session.

1. Download **`lingtex-tools-safari.zip`** and unzip it
2. Move **LingTeX Tools.app** to your `/Applications` folder
3. Run **LingTeX Tools.app** once — a small window appears confirming the
   extension was registered with Safari; you can close it after
4. Open **Safari → Settings → Extensions** and toggle **LingTeX Tools** on
5. Enable unsigned extensions — you need to do this every time Safari relaunches:
   - If you don't see a **Develop** menu:
     **Safari → Settings → Advanced → ✓ Show features for web developers**
   - Then: **Develop → Allow Unsigned Extensions** (enter your password)

> **Why the Develop menu toggle resets:** Apple requires this as a security
> measure for unsigned extensions. If you find it too cumbersome, Chrome or
> Firefox have no such limitation and are recommended for daily use.

> **Want a signed version?** If you have an Apple Developer account, you're
> welcome to fork this repository and add your own signing credentials to the
> GitHub Actions workflow. See [extension/README.md](extension/README.md).

### Using the extension

Once installed in any browser:

| Method | Steps |
|--------|-------|
| **Profile shortcut** | In the popup, open any profile's Configuration and click the **Keyboard shortcut** field, then press your chosen key combo (e.g. Ctrl+Shift+1). From then on, pressing that shortcut anywhere reads the clipboard, converts using that profile, and inserts at the cursor — no tab-switching needed. |
| **Auto-convert paste** | Click the extension icon → toggle **Auto-convert paste** ON. Now regular **Ctrl+V** in Overleaf automatically converts before inserting. |
| **Test / configure** | Click the extension icon to open the popup. Paste sample data into the test area to verify your template before using it in a document. |

The popup lets you configure LaTeX command names, row templates, and create
custom TSV converter tabs. Settings persist across sessions.

