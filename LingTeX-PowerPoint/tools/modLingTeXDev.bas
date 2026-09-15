Attribute VB_Name = "modLingTeXDev"
Option Explicit

'=============================================================================
' modLingTeXDev  --  LingTeX-PowerPoint
'
' ONE PASTE, THEN A SCRIPT DOES THE REST.  The PowerPoint counterpart of
' LingTeX-Word's modImport.  Pasted once into a presentation of its own, it
' imports the other modules into that presentation, so that
'
'     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh
'
' copies the sources over, imports them, runs the probe or the tests and
' prints the reports, and nothing is pasted by hand again.
'
' ---------------------------------------------------------------------------
' SET UP, ONCE
'
'   1. In PowerPoint, make a new blank presentation.
'   2. Tools > Macro > Visual Basic Editor.
'   3. Insert > Module, and paste this file WITHOUT its first line.
'   4. View > Properties Window, and set (Name) to  modLingTeXDev.
'   5. File > Save As..., File Format "PowerPoint Macro-Enabled Presentation
'      (.pptm)", name  LingTeX-PowerPoint-Dev, in your Documents folder.
'      Anywhere outside the clone will do; the script is told where once.
'   6. From the clone:
'        sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh ~/Documents/LingTeX-PowerPoint-Dev.pptm
'
' Reading or writing a VBA project from VBA needs PowerPoint to trust it.  The
' probe (section 13) found that AVAILABLE on Seth's Mac, 2026-09-15.  If an
' import reports error 6068, look for "Trust access to the VBA project object
' model" in PowerPoint's security settings.
'
' ---------------------------------------------------------------------------
' WHERE THE SCRIPT AND THIS MODULE MEET: A FOLDER POWERPOINT OWNS
'
' PowerPoint on the Mac is sandboxed.  Reading the clone, or writing a report
' into it, would bring up a "Grant File Access" prompt, and a prompt blocks a
' script.  So both directions go through PowerPoint's own Documents folder,
' which it may always use.  On the Mac that is
'     ~/Library/Containers/com.microsoft.Powerpoint/Data/Documents
' and Environ("HOME") inside PowerPoint is the container, so one path serves:
'
'     LingTeX-PowerPoint-src/       the script copies the modules here, and
'         modules.txt               names them, one file a line, in order
'     LingTeX-PowerPoint-reports/   the import and the suites write here, and
'                                   the script copies the reports to the clone
'
' The script runs only macros that show no dialog, since a dialog would block
' it: LingTeXDevPing and ImportLingTeXModulesQuiet here, ProbePowerPointQuiet,
' and the suites' ...ToFile macros once they exist.
'
' This module never imports or removes itself, and the add-in never ships it.
' Pure ASCII, and numbers instead of named constants (see modProbe).
'=============================================================================

Private Const SELF_NAME As String = "modLingTeXDev"
Private Const SRC_DIR As String = "LingTeX-PowerPoint-src"
Private Const REPORT_DIR As String = "LingTeX-PowerPoint-reports"
Private Const LIST_FILE As String = "modules.txt"

Private mLog As String

'-----------------------------------------------------------------------------
' Paths and reports
'-----------------------------------------------------------------------------
Private Function Sep() As String
#If Mac Then
    Sep = "/"
#Else
    Sep = "\"
#End If
End Function

Public Function PlatformTag() As String
#If Mac Then
    PlatformTag = "mac"
#Else
    PlatformTag = "win"
#End If
End Function

' PowerPoint's own Documents folder: inside its sandbox, on the Mac.
Public Function DevDocuments() As String
    Dim home As String
    home = Environ$("HOME")
    If home = "" Then home = Environ$("USERPROFILE")
    DevDocuments = home & Sep() & "Documents"
End Function

' <Documents>/LingTeX-PowerPoint-reports/<name>.<mac|win>.txt
Public Function DevReportPath(ByVal baseName As String) As String
    Dim folder As String
    folder = DevDocuments() & Sep() & REPORT_DIR
    On Error Resume Next
    MkDir folder
    Err.Clear
    DevReportPath = folder & Sep() & baseName & "." & PlatformTag() & ".txt"
End Function

Public Sub WriteDevReport(ByVal baseName As String, ByVal text As String)
    Dim fn As Integer
    On Error Resume Next
    fn = FreeFile
    Open DevReportPath(baseName) For Output As #fn
    Print #fn, text;
    Close #fn
End Sub

Private Sub Note(ByVal s As String)
    mLog = mLog & s & vbLf
End Sub

'-----------------------------------------------------------------------------
' The script's first call: proves it can run a macro here, and where the
' reports go.
'-----------------------------------------------------------------------------
Public Sub LingTeXDevPing()
    Dim pres As Object
    mLog = ""
    Note "LingTeXDevPing  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    Set pres = DevPresentation()
    If pres Is Nothing Then
        Note "PROBLEM: no open presentation's VBA project shows " & SELF_NAME & _
             " (or the project cannot be read: error 6068)"
    Else
        Note "  presentation  " & pres.FullName
    End If
    Note "  reports       " & DevDocuments() & Sep() & REPORT_DIR
    WriteDevReport "Ping", mLog
End Sub

'-----------------------------------------------------------------------------
' Import every module named in modules.txt into the presentation that holds
' this module, save it, and write ImportModules.<platform>.txt.
'-----------------------------------------------------------------------------
Public Sub ImportLingTeXModulesQuiet()
    Dim pres As Object, vbp As Object, folder As String
    Dim files As Collection, f As Variant
    Dim okCount As Long, failCount As Long

    mLog = ""
    Note "ImportLingTeXModules  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    Set pres = DevPresentation()
    If pres Is Nothing Then
        Note "PROBLEM: no open presentation's VBA project shows " & SELF_NAME & _
             " (or the project cannot be read: error 6068)"
        GoTo Done
    End If
    Set vbp = pres.VBProject
    folder = DevDocuments() & Sep() & SRC_DIR
    Note "  from  " & folder
    Note "  into  " & pres.FullName

    Set files = ReadList(folder & Sep() & LIST_FILE)
    If files.Count = 0 Then
        Note "PROBLEM: nothing to import: " & LIST_FILE & " is missing or empty"
        GoTo Done
    End If
    For Each f In files
        If ImportOne(vbp, folder & Sep() & CStr(f)) Then
            okCount = okCount + 1
        Else
            failCount = failCount + 1
        End If
    Next

    On Error Resume Next
    pres.Save
    If Err.Number <> 0 Then
        Note "PROBLEM: the presentation could not be saved (" & Err.Number & ": " & Err.Description & ")"
        failCount = failCount + 1
    End If
    Err.Clear
    On Error GoTo 0

    Note ""
    Note "components now:"
    ListComponents vbp
    Note ""
    If failCount = 0 Then
        Note "ALL IMPORTED -- " & okCount & " module(s)"
    Else
        Note "IMPORT FAILED -- " & failCount & " of " & (okCount + failCount)
    End If
Done:
    WriteDevReport "ImportModules", mLog
End Sub

'-----------------------------------------------------------------------------
' Does PowerPoint load an add-in from its Startup folder, the way Word loads a
' template from Word's?  This saves a one-module .ppam there whose Auto_Open
' writes StartupAddIn.<platform>.txt into the reports folder.  Quit PowerPoint
' and start it again: if that report appears, it does.  Afterwards,
'     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh --remove-startup-probe
' takes the test add-in out again.  (PowerPoint's global macro file is an
' add-in, .ppam; a macro-enabled template, .potm, holds macros for
' presentations made from it, not for PowerPoint.)
'-----------------------------------------------------------------------------
Public Sub MakeStartupProbeAddIn()
    Dim app As Object, pres As Object, comp As Object, path As String
    Set app = Application
    mLog = ""
    Note "MakeStartupProbeAddIn  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    If StartupFolder() = "" Then
        Note "PROBLEM: no Startup folder on this platform (Windows registers add-ins instead)"
        GoTo Done
    End If
    path = StartupFolder() & Sep() & "LingTeXStartupProbe.ppam"
    On Error GoTo Fail
    Set pres = app.Presentations.Add(0)
    Set comp = pres.VBProject.VBComponents.Add(1)
    comp.Name = "modStartupProbe"
    comp.CodeModule.AddFromString StartupProbeCode()
    pres.SaveAs path, 30
    Note "  saved  " & path
    Note "Quit PowerPoint and start it again. If StartupAddIn." & PlatformTag() & ".txt then appears in"
    Note DevDocuments() & Sep() & REPORT_DIR & ", PowerPoint loads add-ins from its Startup folder."
Tidy:
    On Error Resume Next
    If Not pres Is Nothing Then
        pres.Saved = -1
        pres.Close
    End If
Done:
    WriteDevReport "MakeStartupProbeAddIn", mLog
    Exit Sub
Fail:
    Note "PROBLEM: " & Err.Number & ": " & Err.Description
    Resume Tidy
End Sub

' Office's Startup folder for PowerPoint.  On the Mac it is in the Office group
' container, which every Office application may write to; Environ("HOME") is
' PowerPoint's own container, so the real home folder is cut out of it.
Public Function StartupFolder() As String
#If Mac Then
    Dim home As String, p As Long
    home = Environ$("HOME")
    p = InStr(home, "/Library/Containers/")
    If p > 0 Then home = Left$(home, p - 1)
    StartupFolder = home & "/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint"
#Else
    StartupFolder = ""
#End If
End Function

' The test add-in's one macro: say, in a report, that it ran.
Private Function StartupProbeCode() As String
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
    StartupProbeCode = s
End Function

' The open presentation whose project holds this module.
Private Function DevPresentation() As Object
    Dim app As Object, p As Object, comp As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        Set comp = Nothing
        Set comp = p.VBProject.VBComponents(SELF_NAME)
        Err.Clear
        If Not comp Is Nothing Then
            Set DevPresentation = p
            Exit Function
        End If
    Next
End Function

'-----------------------------------------------------------------------------
' One file in.
'
' A standard module goes through Import, which names it from its Attribute
' VB_Name line.  A CLASS IS NEVER IMPORTED: Import can misread the class
' preamble and make a standard module full of syntax errors (LingTeX-Word's
' ImportModules.bas tells that story), so a class is created, named and
' filled instead.
'-----------------------------------------------------------------------------
Private Function ImportOne(ByVal vbp As Object, ByVal path As String) As Boolean
    Dim code As String, compName As String, leaf As String
    Dim isClass As Boolean
    Dim comp As Object, stray As Object

    leaf = Mid$(path, InStrRev(path, Sep()) + 1)
    code = ReadText(path)
    If code = "" Then
        Note "  MISSING  " & leaf & " (not found, or empty)"
        Exit Function
    End If
    compName = VbName(code)
    If compName = "" Then
        Note "  FAILED   " & leaf & " (no Attribute VB_Name line)"
        Exit Function
    End If
    If compName = SELF_NAME Then
        Note "  skipped  " & leaf & " (this module never replaces itself)"
        ImportOne = True
        Exit Function
    End If
    isClass = (LCase$(Right$(leaf, 4)) = ".cls")

    On Error Resume Next
    RemoveComponent vbp, compName
    If isClass Then
        Set comp = vbp.VBComponents.Add(2)
        If Err.Number = 0 Then comp.Name = compName
        If Err.Number = 0 Then
            With comp.CodeModule
                If .CountOfLines > 0 Then .DeleteLines 1, .CountOfLines
                .AddFromString StripPreamble(code)
            End With
        End If
    Else
        vbp.VBComponents.Import path
    End If
    If Err.Number <> 0 Then
        Note "  FAILED   " & leaf & " (" & Err.Number & ": " & Err.Description & ")"
        Err.Clear
        Exit Function
    End If

    ' Removed and imported again in one run, a module can come back as
    ' modProbe1 beside the old one, whose name is still held until the
    ' presentation is saved.
    Set comp = Nothing
    Set comp = vbp.VBComponents(compName)
    Err.Clear
    Set stray = Nothing
    Set stray = vbp.VBComponents(compName & "1")
    Err.Clear
    If Not stray Is Nothing Then
        If comp Is Nothing Then
            stray.Name = compName
            If Err.Number <> 0 Then
                Note "  FAILED   " & leaf & " (it came in as " & compName & "1 and could not be renamed: " & Err.Description & ")"
                Err.Clear
                Exit Function
            End If
            Set comp = stray
        Else
            vbp.VBComponents.Remove stray
            Err.Clear
            Note "  FAILED   " & leaf & " (the old " & compName & " was still there, so it came in as " & _
                 compName & "1; that was removed: run the import again)"
            Exit Function
        End If
    End If
    If comp Is Nothing Then
        Note "  FAILED   " & leaf & " (no " & compName & " after the import)"
        Exit Function
    End If
    Note "  ok       " & leaf & "  " & compName & ", " & comp.CodeModule.CountOfLines & " lines" & _
         IIf(isClass, ", class", "")
    ImportOne = True
End Function

Private Sub RemoveComponent(ByVal vbp As Object, ByVal compName As String)
    Dim comp As Object
    On Error Resume Next
    Set comp = vbp.VBComponents(compName)
    If Not comp Is Nothing Then vbp.VBComponents.Remove comp
    Err.Clear
End Sub

Private Sub ListComponents(ByVal vbp As Object)
    Dim c As Object
    On Error Resume Next
    For Each c In vbp.VBComponents
        Note "  " & c.Name & "  (" & c.CodeModule.CountOfLines & " lines, type " & c.Type & ")"
    Next
End Sub

'-----------------------------------------------------------------------------
' Text files
'-----------------------------------------------------------------------------
Private Function ReadText(ByVal path As String) As String
    Dim fn As Integer, n As Long
    On Error GoTo Fail
    fn = FreeFile
    Open path For Binary Access Read As #fn
    n = LOF(fn)
    If n > 0 Then
        ReadText = Space$(n)
        Get #fn, , ReadText
    End If
    Close #fn
    Exit Function
Fail:
    ReadText = ""
End Function

' One entry a line; blank lines and lines starting with # are skipped.
Private Function ReadList(ByVal path As String) As Collection
    Dim t As String, lines() As String, i As Long, s As String
    Set ReadList = New Collection
    t = Replace(Replace(ReadText(path), vbCrLf, vbLf), vbCr, vbLf)
    If t = "" Then Exit Function
    lines = Split(t, vbLf)
    For i = 0 To UBound(lines)
        s = Trim$(lines(i))
        If s <> "" And Left$(s, 1) <> "#" Then ReadList.Add s
    Next
End Function

Private Function VbName(ByVal code As String) As String
    Dim p As Long, q As Long
    Const KEY As String = "Attribute VB_Name = """
    p = InStr(1, code, KEY, vbTextCompare)
    If p = 0 Then Exit Function
    p = p + Len(KEY)
    q = InStr(p, code, """")
    If q > p Then VbName = Mid$(code, p, q - p)
End Function

' A .cls file's code without its VERSION / BEGIN ... END preamble and its
' Attribute lines, which are file syntax, not code.
Private Function StripPreamble(ByVal code As String) As String
    Dim lines() As String, i As Long, t As String, s As String
    Dim inBegin As Boolean
    lines = Split(Replace(Replace(code, vbCrLf, vbLf), vbCr, vbLf), vbLf)
    For i = 0 To UBound(lines)
        t = Trim$(lines(i))
        If inBegin Then
            If t = "END" Then inBegin = False
        ElseIf t = "BEGIN" Then
            inBegin = True
        ElseIf Left$(t, 8) <> "VERSION " And Left$(t, 10) <> "Attribute " Then
            s = s & lines(i) & vbCrLf
        End If
    Next
    StripPreamble = s
End Function
