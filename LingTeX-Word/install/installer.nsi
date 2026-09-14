; installer.nsi -- LingTeX-Word for Windows, the .exe most users get.
;
; Everything it does: copy LingTeX-Word.dotm into Word's STARTUP folder, where
; Word loads it at every start, so the Interlinear tab is on every document; and
; register an uninstaller that takes it out again. Nothing needs administrator
; rights -- STARTUP is per user -- and the file NSIS extracts carries no
; "downloaded from the internet" mark, so Word does not block its macros.
;
; UPGRADING is the same run: the file is overwritten and the uninstaller entry
; is rewritten with the new version. Two things can defeat an overwrite, and
; both are checked before anything is written: Word still running -- a window,
; or a WINWORD.EXE with none, which Outlook's editor and preview panes leave
; behind -- and the old file held open by something else (a sync client, a
; virus scan). Without the second check NSIS would offer Ignore, which keeps
; the old file and reports success. The add-in redoes its shortcuts at the
; next Word start when SETUP_VERSION has moved (RELEASING.md).
;
; Built in CI with makensis (.github/workflows/lingtex-word-release.yml):
;   makensis -DVERSION=0.1.0-beta.1 -DDOTM=/path/to/LingTeX-Word.dotm -DOUT=/path/to/Setup.exe installer.nsi

!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef DOTM
  !define DOTM "..\LingTeX-Word.dotm"
!endif
!ifndef OUT
  !define OUT "LingTeX-Word-Setup.exe"
!endif

!include "MUI2.nsh"

Name "LingTeX-Word"
OutFile "${OUT}"
Unicode true
RequestExecutionLevel user
InstallDir "$APPDATA\Microsoft\Word\STARTUP"
SetCompressor /SOLID lzma

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\LingTeX-Word"
!define HOME "$APPDATA\LingTeX-Word"
!define TEMPLATE "LingTeX-Word.dotm"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "LingTeX-Word ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "This installs LingTeX-Word, a Word add-in for interlinear glossed text: paste an example from FLEx and it becomes a table that wraps to the page.$\r$\n$\r$\nIt puts one file, LingTeX-Word.dotm, into Word's STARTUP folder for your user account. An earlier version there is replaced. No administrator rights are needed.$\r$\n$\r$\nClose Word before continuing."
!define MUI_FINISHPAGE_TITLE "Installed"
!define MUI_FINISHPAGE_TEXT "Start Word. A message will say LingTeX-Word is installed and list its keyboard shortcuts (Ctrl+Alt+Shift + a letter), and the Interlinear tab will be on the ribbon of every document.$\r$\n$\r$\nTo remove it later: Settings > Apps > LingTeX-Word > Uninstall."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; Is Word running? Leaves "1" or "0" on the stack. OpusApp is the class of
; Word's main window; tasklist also catches a WINWORD.EXE that has no window.
; tasklist's words are localized, the image name is not, so find looks for it.
!macro WORD_FUNCTIONS un
Function ${un}WordIsRunning
  FindWindow $0 "OpusApp"
  StrCmp $0 0 0 running
  nsExec::ExecToStack '"$SYSDIR\cmd.exe" /c tasklist /FI "IMAGENAME eq WINWORD.EXE" /NH | find /I "WINWORD.EXE"'
  Pop $0          ; exit code: 0 when find saw WINWORD.EXE
  Pop $1          ; the output, not needed
  StrCmp $0 "0" running
  Push "0"
  Return
  running:
  Push "1"
FunctionEnd

; Asks until Word is closed. Leaves "ok" or "cancel" on the stack; the caller
; aborts, since an Abort inside a called function does not reach the callback.
; Every Retry/Cancel box carries /SD IDCANCEL: a silent run (/S, as an admin's
; deployment or the CI test uses) cannot ask, so it stops with exit code 2
; instead of hanging on a box nobody sees.
Function ${un}WaitForWord
  check:
    Call ${un}WordIsRunning
    Pop $0
    StrCmp $0 "0" closed
    MessageBox MB_ICONEXCLAMATION|MB_RETRYCANCEL "Word is running. Close every Word window (check the taskbar too), then click Retry." /SD IDCANCEL IDRETRY check
    Push "cancel"
    Return
  closed:
    Push "ok"
FunctionEnd
!macroend
!insertmacro WORD_FUNCTIONS ""
!insertmacro WORD_FUNCTIONS "un."

Function .onInit
  Call WaitForWord
  Pop $0
  StrCmp $0 "cancel" 0 +2
    Abort
FunctionEnd

Function un.onInit
  Call un.WaitForWord
  Pop $0
  StrCmp $0 "cancel" 0 +2
    Abort
FunctionEnd

Section "LingTeX-Word"
  SetOutPath "$INSTDIR"

  ; The old copy must be writable before it is replaced: opened for append,
  ; which changes nothing, it fails while anything holds the file.
  IfFileExists "$INSTDIR\${TEMPLATE}" 0 write
  probe:
    ClearErrors
    FileOpen $0 "$INSTDIR\${TEMPLATE}" a
    IfErrors 0 free
    MessageBox MB_ICONEXCLAMATION|MB_RETRYCANCEL "The installed ${TEMPLATE} is in use, so it cannot be replaced. Close Word, then click Retry." /SD IDCANCEL IDRETRY probe
    Abort "${TEMPLATE} was in use; nothing was changed."
  free:
    FileClose $0
  write:
    SetOverwrite on
    File "/oname=${TEMPLATE}" "${DOTM}"
    ; A mark of the web left on an earlier copy lives in a separate stream that
    ; an overwrite may keep, and Word would block the new file's macros for it.
    System::Call 'kernel32::DeleteFileW(w "$INSTDIR\${TEMPLATE}:Zone.Identifier")'

  ; The uninstaller lives in its own folder, so STARTUP holds only the template.
  CreateDirectory "${HOME}"
  WriteUninstaller "${HOME}\Uninstall.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "LingTeX-Word"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "Seth Johnston"
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "https://github.com/rulingAnts/LingTeX-Tools"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"${HOME}\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  ; Delete sets the error flag only when the file is there and cannot go.
  remove:
    ClearErrors
    Delete "$APPDATA\Microsoft\Word\STARTUP\${TEMPLATE}"
    IfErrors 0 removed
    MessageBox MB_ICONEXCLAMATION|MB_RETRYCANCEL "${TEMPLATE} is in use, so it cannot be removed. Close Word, then click Retry." /SD IDCANCEL IDRETRY remove
    Abort "${TEMPLATE} was in use; nothing was removed."
  removed:
  Delete "${HOME}\Uninstall.exe"
  RMDir "${HOME}"
  DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
