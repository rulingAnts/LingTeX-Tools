# Roadmap

Planned features for upcoming releases, roughly in priority order.

---

## Next release

### Rich-text copy for FLEx → Table
**Scope:** Web app, browser extensions

The Copy button on the FLEx → Table (TSV) output currently writes plain text to the
clipboard. The next release will write **both** `text/plain` (TSV) and `text/html`
(an `<table>` element) via `ClipboardItem`, so pasting into OneNote, Word, or Google
Docs produces a formatted table directly — no spreadsheet detour required.

```js
await navigator.clipboard.write([
    new ClipboardItem({
        'text/plain': new Blob([tsvText], { type: 'text/plain' }),
        'text/html':  new Blob([htmlTable], { type: 'text/html' }),
    })
]);
```

The `text/html` payload will be a minimal `<table>` with one row per interlinear
tier and one `<td>` per morpheme/word column, with no inline styling so the
receiving application's table styles apply cleanly.

---

## Future releases

### OS-native line endings in Rust output (desktop global shortcut)
**Scope:** Desktop (Rust backend)

Currently the Rust render functions output `\n` line separators, and `type_text`
in `lib.rs` splits on `\n` and presses `Key::Return` between segments to work
around enigo's inability to type newline characters via `text()` on macOS.

This approach works in most editors (Sublime Text, VS Code, Notepad++, plain
text) but **produces blank lines in TeX Workshop** (VS Code's LaTeX extension),
which is a known issue with the current release — see Known Issues below.

A cleaner approach: have the render functions emit OS-native line endings
(`\r` on macOS, `\r\n` on Windows, `\n` on Linux) using `cfg!` macros, then
call `enigo::text()` directly without the split-and-Return workaround. On macOS
`\r` (U+000D) is the Return character and should map correctly through
`CGEventCreateKeyboardEvent`. Needs testing on all three platforms before
committing to the change. If confirmed working, remove the line-splitting logic
from `type_text` and update the load-bearing divergence comments in `convert.rs`
and `docs/core.js`.

This also fixes a secondary UX problem with the current approach: because the
desktop app types output one line at a time via `Key::Return`, the editor's undo
history records each line as a separate action. The user must press Undo once per
line to reverse a paste, instead of once for the whole block.

### Text abbreviation prompt
**Scope:** All platforms

Optional setting to show a prompt on each conversion (keyboard shortcut and UI copy)
asking for the text/example abbreviation, so the `\txtref{}` value is filled in
correctly without manually editing each pasted block.

### FLEx corpus → LaTeX export
**Scope:** Extension

Export an entire FLEx corpus as a structured LaTeX document (full example appendix
or corpus reference).

### Figure insertion
**Scope:** Desktop, extension

Insert `\includegraphics` blocks from a file picker or clipboard image.

### Spreadsheet/Word table round-trip
**Scope:** Desktop, extension

Paste a table from Excel or Word as a LaTeX `tabular` environment; copy a LaTeX
`tabular` back out for editing in a spreadsheet.

### Safari extension
**Scope:** Safari

Currently failing in CI due to Xcode signing issues. Target: bring parity with
Chrome/Firefox for local install and App Store distribution.

---

## Known issues

### Blank lines inserted when pasting into TeX Workshop (macOS desktop)
**Affects:** Desktop app, macOS, global keyboard shortcut only

The desktop app delivers converted output by simulating `Key::Return` keypresses
between lines (via enigo). TeX Workshop (the LaTeX extension for VS Code)
interprets these as blank lines, resulting in extra empty lines in the pasted
output. Other editors (Sublime Text, VS Code without TeX Workshop, Notepad++,
plain text editors) are not affected.

A secondary issue with the current approach: because output is typed one line at
a time, the editor's undo history records each line separately — undoing a paste
requires pressing Undo once per line rather than once for the whole block.

**Workaround:** Use the in-app copy button and paste manually (`Cmd+V`) instead
of the global keyboard shortcut. This delivers output as a single clipboard paste,
which both avoids the TeX Workshop blank-line issue and creates a single undo step.

**Fix planned:** See "OS-native line endings" above.
