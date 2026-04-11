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
