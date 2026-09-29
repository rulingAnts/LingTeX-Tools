Attribute VB_Name = "modPptBuild"
Option Explicit
'=============================================================================
' modPptBuild  --  LingTeX-PowerPoint (dev rig)
'
' SaveAsAddInSource: the ENGINE PRESENTATION the add-in is built from.  A new
' presentation with no window gets exactly the release modules -- the list
' run-in-powerpoint.sh stages as release.txt: the shared modules and src/,
' without the tests, the probes or the dev rig -- and is saved as
' LingTeX-PowerPoint-engine.pptm in PowerPoint's Documents folder, where the
' runner collects it into build/.  tools/build-ppam.sh then makes the .ppam:
' the add-in content type on the main part, the ribbon and its icons
' injected.  (VBA on the Mac has no save format for an add-in: PLAN.md,
' probe round 6; a .ppam is a .pptm with one content type changed.)
'
' Run through the rig:  sh tools/run-in-powerpoint.sh --macro SaveAsAddInSource
' Pure ASCII.  16 = ppSaveAsOpenXMLPresentationMacroEnabled on the Mac.
'=============================================================================

Private Const ENGINE_NAME As String = "LingTeX-PowerPoint-engine.pptm"
Private Const SRC_DIR As String = "LingTeX-PowerPoint-src"
Private Const RELEASE_LIST As String = "release.txt"

Public Sub SaveAsAddInSource()
    Dim app As Object, pres As Object, path As String, listPath As String
    Dim log As String, failed As Long, comp As Object, n As Long
    Set app = Application
    log = "SaveAsAddInSource  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    listPath = DevDocuments() & Sep() & SRC_DIR & Sep() & RELEASE_LIST
    path = DevDocuments() & Sep() & ENGINE_NAME
    On Error GoTo Fail
    Set pres = app.Presentations.Add(0)
    failed = DevImportList(pres, listPath, log)
    For Each comp In pres.VBProject.VBComponents
        n = n + 1
    Next comp
    log = log & "  components: " & CStr(n) & Chr$(10)
    If failed > 0 Then
        log = log & "PROBLEM: " & CStr(failed) & " module(s) failed to import; nothing saved" & Chr$(10)
        GoTo Tidy
    End If
    On Error Resume Next
    Kill path
    Err.Clear
    On Error GoTo Fail
    pres.SaveAs path, 16
    log = log & "  saved  " & path & Chr$(10)
    log = log & "Next: sh LingTeX-PowerPoint/tools/build-ppam.sh" & Chr$(10)
Tidy:
    On Error Resume Next
    If Not pres Is Nothing Then
        pres.Saved = -1
        pres.Close
    End If
    WriteDevReport "SaveAsAddInSource", log
    Exit Sub
Fail:
    log = log & "PROBLEM: " & Err.Number & ": " & Err.Description & Chr$(10)
    Resume Tidy
End Sub

Private Function Sep() As String
#If Mac Then
    Sep = "/"
#Else
    Sep = "\"
#End If
End Function
