# LingTeX Tools — Test Checklist

## ✅ Web app (`docs/index.html`)
- [x] Normal PA rows convert correctly (auto-detect off and on)
- [x] Grouped PA rows (double leading tab) auto-correct with "Auto-detect grouped view" checked
- [x] Skip logic works correctly after trim fires
- [x] FLEx tab converts correctly
- [x] localStorage persists settings across reload

---

## ⬡ Browser extension (Chrome / Edge / Firefox)

**Setup:** `cd extension && bash build.sh`, then load unpacked from `extension/chrome/` or `extension/firefox/`

- [ ] Popup opens — no "Auto-convert paste" toggle visible in header
- [ ] PA tab has "Auto-detect grouped view" **checked** by default
- [ ] Dekereke tab has "Auto-detect grouped view" **unchecked** by default
- [ ] Normal PA rows — copy to clipboard, trigger shortcut → correct LaTeX typed at cursor
- [ ] Grouped PA rows — same shortcut → correct LaTeX typed at cursor (auto-detected, no manual toggle needed)
- [ ] FLEx shortcut → correct `\gll` block typed at cursor
- [ ] After conversion — clipboard still contains original source text (not LaTeX)
- [ ] Add a custom tab — "Auto-detect grouped view" unchecked by default
- [ ] Settings persist after closing/reopening popup

---

## 🖥 Desktop app (Tauri)

**Setup:** `cd tauri && bash build.sh --dev`

- [ ] App appears in menu bar / system tray
- [ ] Popup opens — no "Auto re-copy" toggle visible in header
- [ ] PA tab has "Auto-detect grouped view" **checked** by default
- [ ] **Test area** — paste normal PA rows → correct output in UI
- [ ] **Test area** — paste grouped PA rows → correct output in UI
- [ ] **OS-wide shortcut** — with app window hidden, copy PA rows, trigger shortcut → correct LaTeX typed at cursor in any app (TextEdit, VS Code, Overleaf in browser, etc.)
- [ ] **OS-wide shortcut** — grouped PA rows → same result
- [ ] **OS-wide shortcut** — FLEx text → correct `\gll` block typed
- [ ] After shortcut fires — clipboard still contains original source text
- [ ] Accessibility permission granted (required for shortcut to work on macOS)
- [ ] Settings persist after quitting and relaunching
