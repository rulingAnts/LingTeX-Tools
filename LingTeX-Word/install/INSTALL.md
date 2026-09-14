# Installing LingTeX-Word

LingTeX-Word is one file, `LingTeX-Word.dotm`, a Word template that lives in
Word's STARTUP folder and loads at every start. Once it is there, every
document has an **Interlinear** tab on the ribbon: insert an interlinear
example from FLEx or from text, re-wrap it to the page, split and merge
columns, check the glossing, indent, number. `LingTeX-Word-Guide.pdf`, beside
this file, is the user guide.

**Word must be closed while you install.**

## Windows

1. Run `LingTeX-Word-Setup-….exe`. It is unsigned, so SmartScreen says
   "unknown publisher": More info → Run anyway. It copies the template into
   `%APPDATA%\Microsoft\Word\STARTUP` and registers an uninstaller under
   Settings → Apps. (Or unzip the `-windows.zip` and double-click
   `install.bat`, which does the same copy and clears the "downloaded from
   the internet" mark that would otherwise make Word block the macros.)
2. Start Word. A message says LingTeX-Word is installed and lists its keyboard
   shortcuts (**Ctrl+Alt+Shift** + a letter). The Interlinear tab is on the ribbon.

To remove it: Settings → Apps → LingTeX-Word → Uninstall (or `install.bat
-Uninstall`, or delete the file from the STARTUP folder).

## Mac

1. Unzip the download.
2. Double-click `install.command` (if macOS refuses, right-click it and choose
   **Open**). It copies the template into Word's Startup folder and clears the
   download quarantine.
3. Start Word. If Word asks whether to enable macros in `LingTeX-Word.dotm`,
   choose **Enable Macros** (Word → Preferences → Security can make that
   permanent). A message then says LingTeX-Word is installed and lists its
   keyboard shortcuts (**Cmd+Option+Shift** + a letter). The Interlinear tab is on
   the ribbon.

To remove it: `sh install.sh --uninstall`, or delete the file from
`~/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word`.

## Shortcuts

The add-in never takes a key that already does something in Word, so a
shortcut may land on an alternate letter (on Mac, Insert is usually
Cmd+Option+Shift+**E**, because +I is Mark Citation). **Shortcuts** on the
Interlinear tab lists what is actually bound on your machine; **Install
Shortcuts** runs the installation again.

## Upgrading

Close Word, run the installer from the new download; it replaces the file.
