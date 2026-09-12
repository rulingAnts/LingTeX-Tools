; installer.nsi -- LingTeX-Word for Windows, the .exe most users get.
;
; Everything it does: copy LingTeX-Word.dotm into Word's STARTUP folder, where
; Word loads it at every start, so the LingTeX tab is on every document; and
; register an uninstaller that takes it out again. Nothing needs administrator
; rights -- STARTUP is per user -- and the file NSIS extracts carries no
; "downloaded from the internet" mark, so Word does not block its macros.
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

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "LingTeX-Word ${VERSION}"
!define MUI_WELCOMEPAGE_TEXT "This installs LingTeX-Word, a Word add-in for interlinear glossed text: paste an example from FLEx and it becomes a table that wraps to the page.$\r$\n$\r$\nIt puts one file, LingTeX-Word.dotm, into Word's STARTUP folder for your user account. No administrator rights are needed.$\r$\n$\r$\nClose Word before continuing."
!define MUI_FINISHPAGE_TITLE "Installed"
!define MUI_FINISHPAGE_TEXT "Start Word. A message will say LingTeX-Word is installed and list its keyboard shortcuts (Ctrl+Alt+Shift + a letter), and the LingTeX tab will be on the ribbon of every document.$\r$\n$\r$\nTo remove it later: Settings > Apps > LingTeX-Word > Uninstall."
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ; Word holds the STARTUP templates open; a copy over a loaded one fails or
  ; takes effect only at the next start, and the first-run message would be
  ; missed. OpusApp is Word's window class.
  FindWindow $0 "OpusApp"
  StrCmp $0 0 done
    MessageBox MB_ICONSTOP|MB_OK "Word is running. Close Word, then run this installer again."
    Abort
  done:
FunctionEnd

Section "LingTeX-Word"
  SetOutPath "$INSTDIR"
  File "/oname=LingTeX-Word.dotm" "${DOTM}"

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
  FindWindow $0 "OpusApp"
  StrCmp $0 0 +3
    MessageBox MB_ICONSTOP|MB_OK "Word is running. Close Word, then uninstall again."
    Abort
  Delete "$APPDATA\Microsoft\Word\STARTUP\LingTeX-Word.dotm"
  Delete "${HOME}\Uninstall.exe"
  RMDir "${HOME}"
  DeleteRegKey HKCU "${UNINST_KEY}"
SectionEnd
