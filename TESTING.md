# LingTeX Tools — Test Checklist

## ✅ Web app (`docs/index.html`)

**Mode bar**
- [x] Three output modes visible: *LaTeX (langsci-gb4e)*, *Table/Spreadsheet (tab-separated)*, *XLingPaper*
- [x] LaTeX mode active by default — inner tab bar visible with FLEx Interlinear, PA, Dekereke, +
- [x] Switching to Table/Spreadsheet mode — inner tab bar hidden, FLEx → Table panel shown
- [x] Switching to XLingPaper mode — inner tab bar hidden, placeholder message shown
- [x] Active mode persists across page reload (localStorage)

**LaTeX mode**
- [x] Normal PA rows convert correctly (auto-detect off and on)
- [x] Grouped PA rows (double leading tab) auto-correct with "Auto-detect grouped view" checked
- [x] Skip logic works correctly after trim fires
- [x] FLEx tab converts correctly
- [x] localStorage persists settings across reload
- [x] Add a custom tab — renders in the inner tab bar, not the mode bar
- [x] FLEx conversion to LaTeX still works (both list and individual, this version intially broke that).

**Table/Spreadsheet mode**
- [x] **FLEx → Table** — paste FLEx interlinear text → word-collapsed TSV output (one column per word)
- [ x **FLEx → Table** — segmented words (`di=de`, `deda-a`) collapse into a single cell with morphemes joined inline
- [x] **FLEx → Table** — glosses assembled inline per word (`pig=ERG`, `attack.CMP`) matching the morpheme structure
- [x] **FLEx → Table** — unsegmented words produce a single column
- [x] **FLEx → Table** — free translation appears as a final plain-text row
- [x] **FLEx → Table** — multiple blocks separated by blank line in output
- [x] **FLEx → Table** — no LaTeX commands in output (no `\gl{}`, `\gll`, `\begin{exe}`, etc.)
- [x] **FLEx → Table — clipboard paste test** — copy output, paste into OneNote (and any other target apps): does tab-separated plain text auto-convert to a table? If not, consider writing `text/html` table markup alongside `text/plain` via `ClipboardItem` (see note in code comments / issue tracker)

**Site page**
- [x Nav "Shortcuts" link scrolls to the keyboard shortcuts documentation section
- [x] Keyboard shortcuts section renders with all three cards (shortcuts fire regardless of mode; duplicates; OS conflicts)
- [x] Product card descriptions mention output modes and the mode-independent shortcut behavior

---

## ⬡ Browser extension (Chrome / Edge / Firefox)

**Setup:** `cd extension && bash build.sh`, then load unpacked from `extension/chrome/` or `extension/firefox/`

**Mode bar**
- [ ] Three output modes visible: *LaTeX (langsci-gb4e)*, *Table/Spreadsheet (tab-separated)*, *XLingPaper*
- [ ] LaTeX mode active by default — inner tab bar visible with FLEx Interlinear, PA, Dekereke, +
- [ ] Switching to Table/Spreadsheet mode — inner tab bar hidden, FLEx → Table panel shown
- [ ] Switching to XLingPaper mode — inner tab bar hidden, placeholder message shown
- [ ] Active mode persists after closing/reopening popup

**LaTeX mode**
- [ ] PA tab has "Auto-detect grouped view" **checked** by default
- [ ] Dekereke tab has "Auto-detect grouped view" **unchecked** by default
- [ ] Normal PA rows — copy to clipboard, trigger shortcut → correct LaTeX typed at cursor
- [ ] Grouped PA rows — same shortcut → correct LaTeX typed at cursor (auto-detected, no manual toggle needed)
- [ ] FLEx shortcut → correct `\gll` block typed at cursor
- [ ] Add a custom tab — "Auto-detect grouped view" unchecked by default
- [ ] Verify LaTeX output again (both individual example and xlist example). This version initially broke the LaTeX rendering. Let's make sure that's fixed.

**Table/Spreadsheet mode**
- [ ] **FLEx → Table** test area — paste FLEx interlinear → morpheme-aligned TSV output
- [ ] **FLEx → Table shortcut** → morpheme-aligned TSV typed at cursor
- [ ] After conversion — clipboard still contains original source text (not LaTeX)

**Shortcut duplicate detection**
- [ ] Assign the same combo to two different tabs → app shows "⚠ Removed from [X]" next to the new field, clears the old binding
- [ ] After dedup — only the newly assigned tab fires when the shortcut is pressed

**General**
- [ ] Settings persist after closing/reopening popup

---

## 🖥 Desktop app (Tauri)

**Setup:** `cd tauri && bash build.sh --dev`

**Mode bar**
- [ ] Three output modes visible: *LaTeX (langsci-gb4e)*, *Table/Spreadsheet (tab-separated)*, *XLingPaper*
- [ ] LaTeX mode active by default — inner tab bar visible with FLEx Interlinear, PA, Dekereke, +
- [ ] Switching to Table/Spreadsheet mode — inner tab bar hidden, FLEx → Table panel shown
- [ ] Switching to XLingPaper mode — inner tab bar hidden, placeholder message shown
- [ ] Active mode persists after quitting and relaunching

**LaTeX mode**
- [ ] App appears in menu bar / system tray
- [ ] PA tab has "Auto-detect grouped view" **checked** by default
- [ ] **Test area** — paste normal PA rows → correct output in UI
- [ ] **Test area** — paste grouped PA rows → correct output in UI
- [ ] **OS-wide shortcut** — with app window hidden, copy PA rows, trigger shortcut → correct LaTeX typed at cursor in any app (TextEdit, VS Code, Overleaf in browser, etc.)
- [ ] **OS-wide shortcut** — grouped PA rows → same result
- [ ] **OS-wide shortcut** — FLEx text → correct `\gll` block typed

**Table/Spreadsheet mode**
- [ ] **FLEx → Table** test area → morpheme-aligned TSV output
- [ ] **OS-wide shortcut** — FLEx → Table shortcut → morpheme-aligned TSV typed at cursor
- [ ] After shortcut fires — clipboard still contains original source text

**Shortcut duplicate detection**
- [ ] Assign the same combo to two different tabs → app shows "⚠ Removed from [X]" next to the new field, clears the old binding
- [ ] Assign a protected OS shortcut (e.g. Cmd+Space on macOS) → app shows "⚠ OS rejected this shortcut — try another combo" and leaves the field empty
- [ ] After dedup — only the newly assigned tab fires when the shortcut is pressed

**General**
- [ ] Accessibility permission granted (required for shortcut to work on macOS)
- [ ] Settings persist after quitting and relaunching
