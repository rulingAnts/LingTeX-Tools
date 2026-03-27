# LingTeX Tools — TeXstudio Macros

Five TeXstudio script macros for linguistic fieldwork in LaTeX.
Each macro works **with or without** the [LingTeX template](https://github.com/sethjohnston/LingTeX) —
adjust the `CONFIGURATION` block at the top of each file to match your own preamble.

## Macros

| File | Name | Shortcut | What it does |
|---|---|---|---|
| `Macro_FLEx_Interlinear.txsMacro` | Paste FLEx Interlinear | Ctrl+Shift+I | Clipboard → `\gll` interlinear block |
| `Macro_PhonologyAssistant.txsMacro` | Paste from Phonology Assistant | Ctrl+Shift+P | Clipboard PA TSV → `\exampleentry` rows |
| `Macro_TagGloss.txsMacro` | Tag Gloss | Ctrl+Shift+G | Selection → `\gl{...}` |
| `Macro_TagLangData.txsMacro` | Tag LangData | Ctrl+Shift+L | Selection → `\langdata{...}` |
| `Macro_ExampleEmphasis.txsMacro` | Example Emphasis | Ctrl+Shift+E | Selection → `\exemph{...}` |

## Installation

1. In TeXstudio, open **Macros → Edit Macros…**
2. Click **Load** and select a `.txsMacro` file from this folder
3. Repeat for each macro you want
4. Click **OK**

The shortcuts (Ctrl+Shift+I, etc.) are set inside each macro file. If they conflict with existing
TeXstudio bindings, change them in the **Shortcut** field before clicking OK.

## Required LaTeX packages and commands

### Paste FLEx Interlinear
Requires a package that provides the `\gll` / `\glt` interlinear glossing commands:
- **[langsci-gb4e](https://ctan.org/pkg/langsci-gb4e)** (recommended — used by LingTeX template)
- **[gb4e](https://ctan.org/pkg/gb4e)** (classic alternative)
- **[linguex](https://ctan.org/pkg/linguex)** (adjust the output template in CONFIGURATION)

Optionally: `\gl{}` (small-caps gloss abbreviations) and `\txtref{}` (source text references).
Both are defined in the LingTeX template. Without them, set `GL_CMD = ""` and `TXTREF_CMD = ""`
or substitute `\textsc` / remove them.

### Paste from Phonology Assistant
Requires `\exampleentry` and `\phonrec` commands (defined in LingTeX template).
Without the template, set `ENTRY_CMD` and `PHONREC_CMD` to your own commands,
or set `PHONREC_CMD = ""` to omit source references.

### Tag Gloss / Tag LangData / Example Emphasis
Require `\gl{}`, `\langdata{}`, and `\exemph{}` respectively (LingTeX template),
or substitute any command of your choice in the CONFIGURATION block.

## Configuration

Each macro has a clearly marked `CONFIGURATION` block at the top where you can change:
- The LaTeX command names
- Case transforms (for Tag Gloss)
- Whether to include source references

No editing outside the CONFIGURATION block is needed for normal use.
