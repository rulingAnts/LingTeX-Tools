Attribute VB_Name = "modLingTeXDevCore"
Option Explicit

'=============================================================================
' modLingTeXDevCore  --  LingTeX-PowerPoint
'
' THE IMPORTER, AS A MODULE THAT CAN ITSELF BE IMPORTED, so a fix to the
' importer never needs pasting by hand again.  The hand-pasted modLingTeXDev
' stays as the bootstrap: run-in-powerpoint.sh first has it import only this
' module, then runs LingTeXDevImport, here, to import everything else.
'
' WHY IT EXISTS.  CodeModule.AddFromString on the Mac counts CR and LF as two
' line breaks, so a class filled with CRLF text came out with every line
' doubled (clsProbeEvents: 121 lines for 55, 2026-09-15).  Doubled blank lines
' are harmless, but a line continuation followed by a blank line is a syntax
' error.  So this asks AddFromString, once per run, which separator it counts
' as ONE break on this platform, builds classes with that, and checks every
' module's line count against its source.
'
' Uses modLingTeXDev's DevDocuments and WriteDevReport.  Never imports or
' removes itself or the bootstrap.  Pure ASCII, numbers instead of named
' constants.
'=============================================================================

Private Const SELF_NAME As String = "modLingTeXDevCore"
Private Const BOOT_NAME As String = "modLingTeXDev"
Private Const SRC_DIR As String = "LingTeX-PowerPoint-src"
Private Const LIST_FILE As String = "modules.txt"

Private mLog As String
Private mSep As String

'-----------------------------------------------------------------------------
' Import every module named in modules.txt into the presentation that holds
' this module, save it, and write ImportModules.<platform>.txt.
'-----------------------------------------------------------------------------
Public Sub LingTeXDevImport()
    Dim pres As Object, vbp As Object, folder As String
    Dim files As Collection, f As Variant
    Dim okCount As Long, failCount As Long

    mLog = ""
    Note "LingTeXDevImport  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    Set pres = HostPresentation()
    If pres Is Nothing Then
        Note "PROBLEM: no open presentation's VBA project shows " & SELF_NAME
        GoTo Done
    End If
    Set vbp = pres.VBProject
    folder = DevDocuments() & PathSep() & SRC_DIR
    Note "  from  " & folder
    Note "  into  " & pres.FullName

    mSep = AddFromStringSeparator(vbp)
    If mSep = "" Then
        Note "PROBLEM: AddFromString counted no separator (LF, CR, CRLF) as one line break"
        GoTo Done
    End If
    Note "  AddFromString takes " & SepName(mSep) & " as one line break here"
    Note "  here vbCrLf is " & CharCodes(vbCrLf) & ", vbNewLine is " & CharCodes(vbNewLine) & ", vbLf is " & CharCodes(vbLf)

    Set files = ReadList(folder & PathSep() & LIST_FILE)
    If files.Count = 0 Then
        Note "PROBLEM: nothing to import: " & LIST_FILE & " is missing or empty"
        GoTo Done
    End If
    For Each f In files
        If ImportOne(vbp, folder & PathSep() & CStr(f)) Then
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
' One file in.  A standard module goes through Import, which names it from its
' Attribute VB_Name line.  A class is NEVER imported (Import can misread the
' class preamble and make a standard module full of syntax errors): it is
' created, named, and filled, one separator between lines.  Either way the
' result's line count is checked against the source.
'-----------------------------------------------------------------------------
Private Function ImportOne(ByVal vbp As Object, ByVal path As String) As Boolean
    Dim text As String, compName As String, leaf As String
    Dim isClass As Boolean, code As String, expected As Long, got As Long
    Dim comp As Object, stray As Object

    leaf = Mid$(path, InStrRev(path, PathSep()) + 1)
    text = ReadText(path)
    If text = "" Then
        Note "  MISSING  " & leaf & " (not found, or empty)"
        Exit Function
    End If
    compName = VbName(text)
    If compName = "" Then
        Note "  FAILED   " & leaf & " (no Attribute VB_Name line)"
        Exit Function
    End If
    If compName = SELF_NAME Or compName = BOOT_NAME Then
        Note "  skipped  " & leaf & " (the importer never replaces itself)"
        ImportOne = True
        Exit Function
    End If
    isClass = (LCase$(Right$(leaf, 4)) = ".cls")
    code = CodeOnly(text, isClass)
    expected = LineCount(code)

    On Error Resume Next
    RemoveComponent vbp, compName
    If isClass Then
        Set comp = vbp.VBComponents.Add(2)
        If Err.Number = 0 Then comp.Name = compName
        If Err.Number = 0 Then
            With comp.CodeModule
                If .CountOfLines > 0 Then .DeleteLines 1, .CountOfLines
                .AddFromString Replace(code, ChLF(), mSep)
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
    ' <name>1 beside the old one, whose name is held until the file is saved.
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

    ' An editor set to "Require Variable Declaration" adds its own Option
    ' Explicit to a new component; that one extra line is not a doubling.
    got = comp.CodeModule.CountOfLines
    If got < expected Or got > expected + 1 Then
        Note "  FAILED   " & leaf & "  " & compName & ": " & got & " lines, but the source has " & expected & _
             "  (file: CR " & CountOf(text, ChCR()) & ", LF " & CountOf(text, ChLF()) & ", CRLF " & CountOf(text, ChCRLF()) & ")"
        Exit Function
    End If
    Note "  ok       " & leaf & "  " & compName & ", " & got & " lines" & IIf(isClass, ", class", "")
    ImportOne = True
End Function

' Which separator AddFromString counts as one line break here: LF, CR or CRLF,
' tried in that order in a scratch module that is removed again.
Private Function AddFromStringSeparator(ByVal vbp As Object) As String
    Dim comp As Object, i As Long, sep As String
    On Error Resume Next
    Set comp = vbp.VBComponents.Add(1)
    If Err.Number <> 0 Or comp Is Nothing Then Exit Function
    For i = 1 To 3
        Select Case i
            Case 1: sep = ChLF()
            Case 2: sep = ChCR()
            Case 3: sep = ChCRLF()
        End Select
        With comp.CodeModule
            If .CountOfLines > 0 Then .DeleteLines 1, .CountOfLines
            .AddFromString "' one" & sep & "' two" & sep & "' three"
            If .CountOfLines = 3 Then
                AddFromStringSeparator = sep
                Exit For
            End If
        End With
    Next
    vbp.VBComponents.Remove comp
    Err.Clear
End Function

Private Function SepName(ByVal sep As String) As String
    Select Case sep
        Case ChLF(): SepName = "LF"
        Case ChCR(): SepName = "CR"
        Case ChCRLF(): SepName = "CRLF"
        Case Else: SepName = "(none)"
    End Select
End Function

' The code a component should end up holding, lines joined by LF: the source
' without its Attribute lines and, for a class, without the VERSION / BEGIN ...
' END preamble.  No trailing line break.
Private Function CodeOnly(ByVal text As String, ByVal isClass As Boolean) As String
    Dim lines() As String, i As Long, t As String, s As String, inBegin As Boolean, first As Boolean
    lines = Split(Replace(Replace(text, ChCRLF(), ChLF()), ChCR(), ChLF()), ChLF())
    first = True
    For i = 0 To UBound(lines)
        t = Trim$(lines(i))
        If isClass And inBegin Then
            If t = "END" Then inBegin = False
        ElseIf isClass And t = "BEGIN" Then
            inBegin = True
        ElseIf isClass And Left$(t, 8) = "VERSION " Then
            ' preamble
        ElseIf Left$(lines(i), 10) = "Attribute " Then
            ' file syntax, not code
        Else
            If first Then
                s = lines(i)
                first = False
            Else
                s = s & ChLF() & lines(i)
            End If
        End If
    Next
    ' The file's final line break leaves an empty last element.
    Do While Right$(s, 1) = ChLF()
        s = Left$(s, Len(s) - 1)
    Loop
    CodeOnly = s
End Function

Private Function LineCount(ByVal code As String) As Long
    If code = "" Then Exit Function
    LineCount = Len(code) - Len(Replace(code, ChLF(), "")) + 1
End Function

' The open presentation whose project holds this module.
Private Function HostPresentation() As Object
    Dim app As Object, p As Object, comp As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        Set comp = Nothing
        Set comp = p.VBProject.VBComponents(SELF_NAME)
        Err.Clear
        If Not comp Is Nothing Then
            Set HostPresentation = p
            Exit Function
        End If
    Next
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

Private Function PathSep() As String
#If Mac Then
    PathSep = "/"
#Else
    PathSep = "\"
#End If
End Function

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
    t = Replace(Replace(ReadText(path), ChCRLF(), ChLF()), ChCR(), ChLF())
    If t = "" Then Exit Function
    lines = Split(t, ChLF())
    For i = 0 To UBound(lines)
        s = Trim$(lines(i))
        If s <> "" And Left$(s, 1) <> "#" Then ReadList.Add s
    Next
End Function

Private Function VbName(ByVal text As String) As String
    Dim p As Long, q As Long
    Const KEY As String = "Attribute VB_Name = """
    p = InStr(1, text, KEY, vbTextCompare)
    If p = 0 Then Exit Function
    p = p + Len(KEY)
    q = InStr(p, text, """")
    If q > p Then VbName = Mid$(text, p, q - p)
End Function

' Line-break characters by code, not by the vbCr / vbLf / vbCrLf constants:
' normalising CRLF with vbCrLf turned every break into two here (2026-09-15),
' so the constants are only logged, never relied on.
Private Function ChCR() As String
    ChCR = Chr$(13)
End Function

Private Function ChLF() As String
    ChLF = Chr$(10)
End Function

Private Function ChCRLF() As String
    ChCRLF = Chr$(13) & Chr$(10)
End Function

Private Function CharCodes(ByVal s As String) As String
    Dim i As Long, out As String
    For i = 1 To Len(s)
        If i > 1 Then out = out & "+"
        out = out & AscW(Mid$(s, i, 1))
    Next
    CharCodes = "[" & out & "]"
End Function

Private Function CountOf(ByVal s As String, ByVal what As String) As Long
    If Len(what) = 0 Then Exit Function
    CountOf = (Len(s) - Len(Replace(s, what, ""))) \ Len(what)
End Function

Private Sub Note(ByVal s As String)
    mLog = mLog & s & ChLF()
End Sub
