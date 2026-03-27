# Installation Guide — LingTeX Tools

All downloadable files are attached to each [GitHub Release](https://github.com/rulingAnts/LingTeX-Tools/releases/latest).

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

---

## TeXstudio Macros

> These macros run directly inside TeXstudio. They do **not** require Overleaf
> or a browser extension, and they work with or without the LingTeX template.

### Download and import

1. Download **`lingtex-tools-texstudio-macros.zip`** from the
   [latest release](https://github.com/rulingAnts/LingTeX-Tools/releases/latest)
   and unzip it
2. In TeXstudio: **Macros → Edit Macros…**
3. In the macro editor, click **Import** (folder icon or File menu inside the editor)
4. Select all five **`.txsMacro`** files from the unzipped folder and import them
5. Click **OK** — the macros are now available under the **Macros** menu and
   via their keyboard shortcuts

### Customize the CONFIGURATION block

Each macro has a clearly marked `CONFIGURATION` block near the top of its script.
Open the macro editor (**Macros → Edit Macros…**), select a macro, and edit the
variables to match the LaTeX commands in your preamble.

#### Paste FLEx Interlinear  `Ctrl+Shift+I`

Reads FLEx interlinear text from the clipboard and inserts a `\gll…\glt` block.

```javascript
var GL_CMD       = "\\gl";      // wraps gloss abbreviations: \gl{pst}
                                // Use "\\textsc" for plain small-caps,
                                // or "" to disable wrapping entirely
var TXTREF_CMD   = "\\txtref";  // source reference command, e.g. \txtref{TXT:8}
                                // Set to "" to omit source references
var TXTREF_PREFIX = "TXT:";     // prefix inside \txtref — set to "" for bare number
```

#### Paste from Phonology Assistant  `Ctrl+Shift+P`

Reads tab-separated rows copied from Phonology Assistant and inserts LaTeX entries.

```javascript
var ENTRY_CMD   = "\\exampleentry"; // command for each row
                                    // arguments: {category}{word}{gloss}{source-ref}
                                    // Use "\\item" inside itemize as a generic fallback
var PHONREC_CMD = "\\phonrec";      // wraps the phonology record ID (source reference)
                                    // Set to "" to omit source references entirely
```

#### Tag Gloss  `Ctrl+Shift+G`

Wraps the selected text in a grammatical gloss command (select the abbreviation first).

```javascript
var OUTPUT    = "\\gl{$TEXT}";   // e.g. select "PST" → \gl{pst}
                                  // Use "\\textsc{$TEXT}" for plain small-caps
var TRANSFORM = "lowercase";      // "lowercase", "uppercase", or "none"
```

#### Tag LangData  `Ctrl+Shift+L`

Wraps selected vernacular/object-language text in a styling command.

```javascript
var OUTPUT = "\\langdata{$TEXT}"; // e.g. select a word → \langdata{word}
                                   // Use "\\textit{$TEXT}" as a plain italic fallback
```

#### Example Emphasis  `Ctrl+Shift+E`

Wraps selected text in an in-example emphasis command.

```javascript
var OUTPUT = "\\exemph{$TEXT}";   // e.g. select a word → \exemph{word}
                                   // Use "\\textbf{$TEXT}" as a plain bold fallback
```

### Using without the LingTeX template

All macros include plain LaTeX fallback values in comments. If you are not using
the LingTeX template, substitute the fallback values shown — `\textsc`, `\textit`,
`\textbf`, `\item`, etc. — so the macros work with any standard LaTeX preamble.
