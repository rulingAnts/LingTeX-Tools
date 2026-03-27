# LingTeX Tools

Linguistic fieldwork macro tools for LaTeX — available in multiple formats:

| Platform | Folder | Status |
|---|---|---|
| TeXstudio script macros | `texstudio/` | ✅ Ready |
| Single-page web app | `webapp/` | 🚧 Coming soon |
| Chrome extension | `extension/chrome/` | 🚧 Coming soon |
| Firefox extension | `extension/firefox/` | 🚧 Coming soon |
| Safari extension | `extension/safari/` | 🚧 Coming soon |

All platforms share the same core parsing and rendering logic (`docs/core.js`), served by GitHub Pages and bundled into browser extension packages at release time.

## What's included

- **Paste FLEx Interlinear** — converts copied FLEx interlinear text into a `\gll` block (langsci-gb4e / gb4e)
- **Paste from Phonology Assistant** — converts PA TSV clipboard rows into `\exampleentry` LaTeX rows
- **Tag Gloss** — wraps selected text in `\gl{...}` (or any configurable command)
- **Tag LangData** — wraps selected text in `\langdata{...}`
- **Example Emphasis** — wraps selected text in `\exemph{...}`

## Works with or without LingTeX

These tools are designed to work with the [LingTeX template](https://github.com/rulingAnts/LingTeX),
but every macro and the web app can be configured to use your own LaTeX commands instead.
See the `CONFIGURATION` block at the top of each macro file, or the settings panel in the web app.

## Related project

[LingTeX](https://github.com/rulingAnts/LingTeX) — a TeXstudio project template for writing
linguistic grammar descriptions, built on XeLaTeX, langsci-gb4e, and biblatex/biber.

## License

AGPL-3.0 — Copyright © Seth Johnston
