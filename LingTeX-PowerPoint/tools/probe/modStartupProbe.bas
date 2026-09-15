Attribute VB_Name = "modStartupProbe"
Option Explicit

'=============================================================================
' modStartupProbe  --  LingTeX-PowerPoint
'
' Does PowerPoint load an add-in from Office's Startup folder for PowerPoint,
' the way Word loads a template from Word's?  MakeStartupTestAddIn saves a
' one-module add-in there whose Auto_Open writes StartupAddIn.<platform>.txt
' into the reports folder.  Quit PowerPoint and start it again: that report
' says whether it loaded.  Take the test add-in out afterwards with
'     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh --remove-startup-probe
'
' It supersedes modLingTeXDev's MakeStartupProbeAddIn, whose
' SaveAs(path, 30) PowerPoint for Mac 16.112 refused with "Invalid enumeration
' value" (2026-09-15).  30 is ppSaveAsOpenXMLAddin on Windows; this tries each
' way of saving an add-in in turn and reports every attempt, and the runner
' then checks the saved file's content type, because a name ending in .ppam
' proves nothing (LingTeX-Word's beta.3 "template" was a document named .dotm).
'
' Runs in the dev presentation, beside modLingTeXDev (WriteDevReport,
' DevReportPath).  Pure ASCII, numbers instead of named constants.
'=============================================================================

Private mLog As String

Public Sub MakeStartupTestAddIn()
    Dim folder As String, path As String, attempt As Long, how As String
    mLog = ""
    Say "MakeStartupTestAddIn  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    folder = StartupFolderPath()
    If folder = "" Then
        Say "PROBLEM: no Startup folder on this platform (Windows registers add-ins instead)"
        GoTo Done
    End If
    path = folder & "/LingTeXStartupProbe.ppam"
    Say "  folder  " & folder
    For attempt = 1 To 6
        how = TrySave(path, attempt)
        If how <> "" Then
            Say "  saved   " & path & "  (" & how & ", " & FileLen(path) & " bytes)"
            Say "Quit PowerPoint and start it again. If StartupAddIn." & PlatformTag() & ".txt then appears"
            Say "in the reports folder, PowerPoint loads add-ins from its Startup folder."
            GoTo Done
        End If
    Next
    Say "PROBLEM: no way of saving an add-in worked (the attempts are above)"
Done:
    WriteDevReport "MakeStartupTestAddIn", mLog
End Sub

' A .ppam is a macro-enabled presentation whose package says "add-in" (the
' main part's content type in [Content_Types].xml).  PowerPoint for Mac 16.112
' will not save one from VBA (MakeStartupTestAddIn, above), so this saves the
' test module as an ordinary .pptm in PowerPoint's own Documents folder, and
' the runner rewrites that one content type and copies the result into the
' Startup folder -- the way LingTeX-Word's build makes its template a template.
Public Sub MakeStartupTestPptm()
    Dim app As Object, pres As Object, comp As Object
    Dim path As String, attempt As Long, size As Long, how As String
    Set app = Application
    mLog = ""
    Say "MakeStartupTestPptm  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    path = DevDocuments() & "/LingTeXStartupProbe.pptm"
    For attempt = 1 To 2
        On Error Resume Next
        Kill path
        Err.Clear
        If attempt = 1 Then how = "SaveAs FileFormat 25" Else how = "SaveAs, format from the .pptm name"
        Set pres = app.Presentations.Add(0)
        Set comp = pres.VBProject.VBComponents.Add(1)
        comp.Name = "modStartupTest"
        comp.CodeModule.AddFromString TestAddInCode()
        If attempt = 1 Then
            pres.SaveAs path, 25
        Else
            pres.SaveAs path
        End If
        If Err.Number <> 0 Then
            Say "  " & how & ": ERROR " & Err.Number & ": " & Err.Description
            Err.Clear
        End If
        size = 0
        size = FileLen(path)
        Err.Clear
        pres.Saved = -1
        pres.Close
        Err.Clear
        If size > 0 Then
            Say "  saved   " & path & "  (" & how & ", " & size & " bytes)"
            GoTo Done
        End If
        Say "  " & how & ": no file"
    Next
    Say "PROBLEM: the .pptm could not be saved"
Done:
    WriteDevReport "MakeStartupTestPptm", mLog
End Sub

' One attempt: a new presentation holding the test module, saved one way.
' Returns a description of the way when a file exists afterwards, else "".
Private Function TrySave(ByVal path As String, ByVal attempt As Long) As String
    Dim app As Object, pres As Object, comp As Object, how As String, size As Long
    Set app = Application
    On Error Resume Next
    Kill path
    Err.Clear
    Select Case attempt
        Case 1: how = "no window, SaveAs FileFormat 30"
        Case 2: how = "no window, SaveAs, format from the .ppam name"
        Case 3: how = "no window, SaveCopyAs FileFormat 30"
        Case 4: how = "window, SaveAs FileFormat 30"
        Case 5: how = "window, SaveAs, format from the .ppam name"
        Case 6: how = "window, SaveCopyAs FileFormat 30"
    End Select
    If attempt <= 3 Then
        Set pres = app.Presentations.Add(0)
    Else
        Set pres = app.Presentations.Add(-1)
    End If
    If Err.Number <> 0 Or pres Is Nothing Then
        Say "  " & how & ": ERROR making the presentation " & Err.Number & ": " & Err.Description
        Exit Function
    End If
    Set comp = pres.VBProject.VBComponents.Add(1)
    comp.Name = "modStartupTest"
    comp.CodeModule.AddFromString TestAddInCode()
    If Err.Number <> 0 Then
        Say "  " & how & ": ERROR adding the module " & Err.Number & ": " & Err.Description
        Err.Clear
    Else
        Select Case attempt
            Case 1, 4: pres.SaveAs path, 30
            Case 2, 5: pres.SaveAs path
            Case 3, 6: pres.SaveCopyAs path, 30
        End Select
        If Err.Number <> 0 Then
            Say "  " & how & ": ERROR " & Err.Number & ": " & Err.Description
            Err.Clear
        Else
            size = 0
            size = FileLen(path)
            Err.Clear
            If size > 0 Then
                TrySave = how
            Else
                Say "  " & how & ": no error, but no file"
            End If
        End If
    End If
    pres.Saved = -1
    pres.Close
    Err.Clear
End Function

' Office's Startup folder for PowerPoint.  On the Mac it is in the Office group
' container; Environ("HOME") is PowerPoint's own container, so the real home
' folder is cut out of it.
Private Function StartupFolderPath() As String
#If Mac Then
    Dim home As String, p As Long
    home = Environ$("HOME")
    p = InStr(home, "/Library/Containers/")
    If p > 0 Then home = Left$(home, p - 1)
    StartupFolderPath = home & "/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint"
#Else
    StartupFolderPath = ""
#End If
End Function

' The test add-in's one macro: say, in a report, that it ran.
Private Function TestAddInCode() As String
    Dim q As String, s As String
    q = Chr$(34)
    s = "Public Sub Auto_Open()" & vbCrLf
    s = s & "    Dim fn As Integer" & vbCrLf
    s = s & "    On Error Resume Next" & vbCrLf
    s = s & "    fn = FreeFile" & vbCrLf
    s = s & "    Open " & q & DevReportPath("StartupAddIn") & q & " For Output As #fn" & vbCrLf
    s = s & "    Print #fn, " & q & "Auto_Open ran, from the Startup folder, at " & q & _
            " & Format$(Now, " & q & "yyyy-mm-dd hh:nn:ss" & q & ")" & vbCrLf
    s = s & "    Close #fn" & vbCrLf
    s = s & "End Sub" & vbCrLf
    TestAddInCode = s
End Function

Private Sub Say(ByVal s As String)
    mLog = mLog & s & vbLf
End Sub
