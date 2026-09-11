Attribute VB_Name = "modProbe"
Option Explicit

'=============================================================================
' modProbe  --  LingTeX-Word
'
' ONE PASTE, ONE REPORT.  Probes the Word object model for the assumptions the
' add-in rests on, prints a report, and cleans up after itself.
'
' Nothing else in LingTeX-Word is needed: this module is completely
' self-contained.  Run it BEFORE importing the engine, so that if one of these
' assumptions is wrong we find out from a 20-line report rather than from a
' confusing full-system failure.
'
' ---------------------------------------------------------------------------
' HOW TO RUN
'
'   1. In Word:  Tools > Macro > Visual Basic Editor   (Mac)
'                Alt+F11                                (Windows)
'   2. Either  File > Import File...  and pick this file,
'      or      Insert > Module, then paste everything below
'              EXCEPT the first line ("Attribute VB_Name = ...") -- that line is
'              read by the importer and is a compile error if typed in by hand.
'   3. Run it, either way:
'        * Tools > Macro > Macros... (Mac) or Alt+F8 (Windows), pick ProbeWord,
'          then Run;  or
'        * open View > Immediate Window, type  ProbeWord  and press Return.
'   4. When it finishes it opens a NEW DOCUMENT containing the report, and shows
'      a dialog saying so.  Select all of that document, copy, and send it back.
'
' If you see no dialog and no new document, the module did not run at all -- check
' for a macro-security prompt, and that the module compiled (Debug > Compile).
'
' The report also goes to the VBA editor's Immediate window.  That window is the
' ONLY place Debug.Print output appears, and if it is closed the output is
' invisible, which looks just like nothing having happened -- which is why the
' report is delivered as a document too.
'
' It creates one hidden document and three temporary styles and deletes all of
' them before it finishes.  Your own documents are never touched; the report
' document is new and unsaved, and you can close it without saving.
' ---------------------------------------------------------------------------
'
' Pure ASCII on purpose: a .bas is imported in the system ANSI code page, not
' UTF-8, so a non-ASCII literal would arrive mangled -- differently on Mac and
' on Windows.
'=============================================================================

' Word reports a "mixed / not applicable" formatting value as this.
Private Const WD_UNDEFINED As Long = 9999999

Private mRpt As String
Private mDoc As Document


'=============================================================================
' -- ENTRY POINT ------------------------------------------------------------
'=============================================================================

Public Sub ProbeWord()
    mRpt = ""

    Say "==================================================================="
    Say " LingTeX-Word  --  Word object model probe"
    Say "==================================================================="

    ProbeEnvironment
    ProbeScratchDocument

    If mDoc Is Nothing Then
        Say ""
        Say "STOPPED: no scratch document, so the measurement probes cannot run."
        Say "This alone is a blocking finding -- please send the report."
    Else
        ProbeAutofitWidths
        ProbeColumnsWidthError
        ProbeInformationPosition
        ProbeRaggedRows
        ProbeSetWidth
        ProbeTablePadding
        ProbeStyles
        ProbeSmallCapsUndefined
        ProbeDocumentVariables
    End If

    ProbeUndoRecord
    ProbeFileIO
    ProbeVBProject
    ProbeFileDialog

    CleanUp

    Say "==================================================================="
    Say " End of report."
    Say "==================================================================="

    DeliverReport
End Sub

'-----------------------------------------------------------------------------
' Get the report in front of the user.
'
' Debug.Print writes ONLY to the Immediate window, and if that window is closed
' the output is invisible -- which looks exactly like the macro having done
' nothing at all.  So the report also goes into a new Word document, which cannot
' be missed and is trivial to select and copy, and a dialog confirms the run
' finished and says where to look.
'-----------------------------------------------------------------------------
Private Sub DeliverReport()
    Dim d As Document
    Dim placed As Boolean

    ' Still print it, for anyone who does have the Immediate window open.
    On Error Resume Next
    Debug.Print mRpt
    Err.Clear

    Set d = Documents.Add
    If Err.Number = 0 Then
        If Not d Is Nothing Then
            d.Content.Text = mRpt
            ' Monospaced so the columns in the report line up.
            d.Content.Font.Name = "Courier New"
            d.Content.Font.Size = 9
            d.Content.ParagraphFormat.SpaceAfter = 0
            placed = (Err.Number = 0)
        End If
    End If
    Err.Clear
    On Error GoTo 0

    If placed Then
        MsgBox "Probe finished." & vbCr & vbCr & _
               "The report is in the new document that just opened." & vbCr & _
               "Select all of it (Cmd+A, or Ctrl+A on Windows), copy, and send " & _
               "it back." & vbCr & vbCr & _
               "It is also in the VBA editor's Immediate window, if you have " & _
               "that open (View > Immediate Window).", _
               vbInformation, "LingTeX-Word probe"
    Else
        MsgBox "Probe finished, but a new document could not be created to hold " & _
               "the report." & vbCr & vbCr & _
               "Open the VBA editor's Immediate window instead " & _
               "(View > Immediate Window) -- the report is there." & vbCr & vbCr & _
               "That a document could not be created is itself a finding worth " & _
               "reporting.", _
               vbExclamation, "LingTeX-Word probe"
    End If
End Sub


'=============================================================================
' -- PROBES -----------------------------------------------------------------
'=============================================================================

Private Sub ProbeEnvironment()
    Head "1. Environment"

    On Error Resume Next
    Note "Application.Name", Application.Name
    Note "Application.Version", Application.Version
    Note "Application.Build", Application.Build
    Note "System.OperatingSystem", Application.System.OperatingSystem
    Note "System.Version", Application.System.Version
    ClearErr

    #If Mac Then
        Note "Compiled branch", "Mac  (#If Mac Then is TRUE)"
    #Else
        Note "Compiled branch", "Windows"
    #End If
    #If VBA7 Then
        Note "VBA7", "yes"
    #Else
        Note "VBA7", "no"
    #End If
    #If Win64 Then
        Note "Win64", "yes"
    #Else
        Note "Win64", "no"
    #End If
End Sub

'-----------------------------------------------------------------------------
' The whole measurement approach runs in a hidden document with a 22-inch page
' (Word's maximum), because autofit CLAMPS to the page width and a clamped
' measurement is silently wrong.
'-----------------------------------------------------------------------------
Private Sub ProbeScratchDocument()
    Head "2. Hidden scratch document"

    On Error Resume Next
    Set mDoc = Documents.Add(Visible:=False)
    If Err.Number <> 0 Then
        Note "Documents.Add(Visible:=False)", ErrText()
        ClearErr
        Set mDoc = Documents.Add
        If Err.Number <> 0 Then
            Note "Documents.Add (fallback)", ErrText()
            ClearErr
            Exit Sub
        End If
        Note "Documents.Add (fallback)", "ok"
    Else
        Note "Documents.Add(Visible:=False)", "ok"
    End If
    ClearErr

    Note "Windows.Count (0 means hidden)", CStr(mDoc.Windows.Count)
    ClearErr

    With mDoc.PageSetup
        .TopMargin = 0
        .BottomMargin = 0
        .LeftMargin = 0
        .RightMargin = 0
        Note "Margins to 0", ErrOrOk()
        .Gutter = 0
        Note "Gutter to 0", ErrOrOk()
        .PageWidth = InchesToPoints(22)
        Note "PageWidth to 22in", ErrOrOk()
        Note "PageWidth reads back (pt)", Num(.PageWidth) & "   (1584 expected)"
        .TextColumns.SetCount NumColumns:=1
        Note "TextColumns.SetCount 1", ErrOrOk()
    End With
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' THE CRITICAL PROBE.
'
' modMeasure sizes every column by putting one word per cell in a single-row
' table, autofitting to contents, and reading Cell(1, c).Width back.  If those
' widths come back zero, all equal, or not increasing with the width of the
' text, the primary measurement method is unusable and the add-in must ship
' with USE_AUTOFIT = False.
'-----------------------------------------------------------------------------
Private Sub ProbeAutofitWidths()
    Dim t As Table
    Dim r As Range
    Dim w(1 To 4) As Single
    Dim i As Long
    Dim samples(1 To 4) As String
    Dim okAll As Boolean

    Head "3. Autofit cell widths  <-- THE CRITICAL ONE"

    samples(1) = "i"
    samples(2) = "iii"
    samples(3) = "WWW"
    samples(4) = "Edefina"

    On Error Resume Next
    mDoc.Content.Delete
    Set t = mDoc.Tables.Add(Range:=mDoc.Content, NumRows:=1, NumColumns:=4)
    If Err.Number <> 0 Then
        Note "Tables.Add", ErrText()
        ClearErr
        Exit Sub
    End If

    For i = 1 To 4
        Set r = t.Cell(1, i).Range
        r.End = r.End - 1                  ' exclude the end-of-cell marker
        r.Text = samples(i)
    Next i
    Note "Filling cells", ErrOrOk()

    t.AllowAutoFit = True
    t.PreferredWidthType = wdPreferredWidthAuto
    t.AutoFitBehavior wdAutoFitContent
    Note "AutoFitBehavior wdAutoFitContent", ErrOrOk()

    okAll = True
    For i = 1 To 4
        w(i) = -1
        w(i) = t.Cell(1, i).Width
        If Err.Number <> 0 Then
            Note "Cell(1," & CStr(i) & ").Width", ErrText()
            ClearErr
            okAll = False
        Else
            Note "width of " & Quoted(samples(i)), Num(w(i)) & " pt"
        End If
    Next i

    If okAll Then
        If w(1) <= 0 Or w(2) <= 0 Or w(3) <= 0 Then
            Verdict "UNUSABLE -- a width came back zero or negative"
        ElseIf w(1) = w(2) And w(2) = w(3) Then
            Verdict "UNUSABLE -- all widths identical, so autofit did not size to content"
        ElseIf w(1) < w(2) And w(2) < w(3) Then
            Verdict "USABLE -- widths increase with the text, as required"
        Else
            Verdict "SUSPECT -- widths not increasing with the text; expected i < iii < WWW"
        End If
    Else
        Verdict "UNUSABLE -- could not read cell widths"
    End If
    ClearErr
End Sub

' modMeasure reads CELLS, never Columns(i).Width, because the latter raises
' error 5991 the moment a table has mixed cell widths -- which this one now has.
' Confirming the error justifies the workaround instead of leaving it folklore.
Private Sub ProbeColumnsWidthError()
    Dim dummy As Single
    Head "4. Columns(i).Width on mixed widths"

    On Error Resume Next
    If mDoc.Tables.Count = 0 Then
        Note "no table present", "skipped"
        Exit Sub
    End If
    dummy = mDoc.Tables(1).Columns(1).Width
    If Err.Number = 0 Then
        Note "Columns(1).Width", "returned " & Num(dummy) & " (no error raised)"
    Else
        Note "Columns(1).Width", ErrText() & "   (5991 expected)"
    End If
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' The implemented fallback: the horizontal position at the end of a
' non-wrapping paragraph is the width of the text on it.  Must be known to work
' BEFORE it is needed.
'-----------------------------------------------------------------------------
Private Sub ProbeInformationPosition()
    Dim pNarrow As Single, pWide As Single
    Head "5. Range.Information position (the fallback method)"

    On Error Resume Next
    pNarrow = MeasureByPosition("i")
    Note "end position after " & Quoted("i"), Num(pNarrow) & " pt"
    pWide = MeasureByPosition("WWWWW")
    Note "end position after " & Quoted("WWWWW"), Num(pWide) & " pt"

    If Err.Number <> 0 Then
        Verdict "UNUSABLE -- " & ErrText()
    ElseIf pNarrow <= 0 Or pWide <= 0 Then
        Verdict "UNUSABLE -- a position came back zero or negative"
    ElseIf pWide > pNarrow Then
        Verdict "USABLE -- wider text reports a larger position"
    Else
        Verdict "SUSPECT -- wider text did not report a larger position"
    End If
    ClearErr
End Sub

Private Function MeasureByPosition(ByVal s As String) As Single
    Dim r As Range
    mDoc.Content.Delete
    Set r = mDoc.Content
    r.ParagraphFormat.LeftIndent = 0
    r.ParagraphFormat.RightIndent = 0
    r.ParagraphFormat.FirstLineIndent = 0
    r.Text = s
    Set r = mDoc.Content
    r.Collapse wdCollapseEnd
    MeasureByPosition = r.Information(wdHorizontalPositionRelativeToTextBoundary)
End Function

'-----------------------------------------------------------------------------
' One table holds every wrap line as a group of rows, and rows on shorter wrap
' lines have surplus cells deleted.  That only works if Word lets rows in one
' table have different cell counts.
'-----------------------------------------------------------------------------
Private Sub ProbeRaggedRows()
    Dim t As Table
    Dim c1 As Long, c2 As Long
    Head "6. Ragged rows (different cell counts in one table)"

    On Error Resume Next
    mDoc.Content.Delete
    Set t = mDoc.Tables.Add(Range:=mDoc.Content, NumRows:=2, NumColumns:=3)
    If Err.Number <> 0 Then
        Note "Tables.Add", ErrText()
        ClearErr
        Exit Sub
    End If

    t.Rows(1).Cells(3).Delete
    Note "Rows(1).Cells(3).Delete", ErrOrOk()

    c1 = t.Rows(1).Cells.Count
    c2 = t.Rows(2).Cells.Count
    Note "Rows(1).Cells.Count", CStr(c1) & "   (2 expected)"
    Note "Rows(2).Cells.Count", CStr(c2) & "   (3 expected)"

    If c1 = 2 And c2 = 3 Then
        Verdict "USABLE -- rows may hold different cell counts"
    Else
        Verdict "UNUSABLE -- the one-table-per-example layout will not work"
    End If
    ClearErr
End Sub

' Explicit per-cell widths are the entire layout.  wdAdjustNone matters: without
' it Word redistributes width across neighbouring rows.
Private Sub ProbeSetWidth()
    Dim t As Table
    Dim got As Single
    Head "7. Cell.SetWidth with RulerStyle wdAdjustNone"

    On Error Resume Next
    If mDoc.Tables.Count = 0 Then
        Note "no table present", "skipped"
        Exit Sub
    End If
    Set t = mDoc.Tables(1)
    t.AllowAutoFit = False
    t.Cell(2, 1).SetWidth ColumnWidth:=72, RulerStyle:=wdAdjustNone
    Note "SetWidth 72pt", ErrOrOk()
    got = t.Cell(2, 1).Width
    Note "width reads back", Num(got) & " pt   (72 expected)"
    If Abs(got - 72) < 1 Then
        Verdict "USABLE"
    Else
        Verdict "SUSPECT -- the width did not stick"
    End If
    ClearErr
End Sub

' Padding is zeroed on the measurement table and the real table alike, so the
' measured number is pure content width.  If these properties are missing, both
' keep Word's default padding and measurement stays consistent -- so this is
' informational, not blocking.
Private Sub ProbeTablePadding()
    Dim t As Table
    Head "8. Table padding and spacing"

    On Error Resume Next
    If mDoc.Tables.Count = 0 Then
        Note "no table present", "skipped"
        Exit Sub
    End If
    Set t = mDoc.Tables(1)

    t.LeftPadding = 0
    Note "LeftPadding = 0", ErrOrOk()
    t.RightPadding = 0
    Note "RightPadding = 0", ErrOrOk()
    t.TopPadding = 0
    Note "TopPadding = 0", ErrOrOk()
    t.BottomPadding = 0
    Note "BottomPadding = 0", ErrOrOk()
    t.Spacing = 0
    Note "Spacing = 0", ErrOrOk()
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' The rendered table is self-describing: a TABLE style is the tag that marks an
' example as ours, and a CHARACTER style marks small-capped grammatical glosses
' so read-back can restore their capitals.  Both must be creatable.
'-----------------------------------------------------------------------------
Private Sub ProbeStyles()
    Dim st As Style
    Head "9. Creating styles"

    On Error Resume Next

    Set st = Nothing
    Set st = mDoc.Styles.Add(Name:="ProbeTableStyle", Type:=wdStyleTypeTable)
    If Err.Number <> 0 Then
        Note "Styles.Add wdStyleTypeTable", ErrText()
        ClearErr
    Else
        Note "Styles.Add wdStyleTypeTable", "ok"
        st.Table.Borders(wdBorderTop).LineStyle = wdLineStyleNone
        Note "  table style borders off", ErrOrOk()
    End If

    Set st = Nothing
    Set st = mDoc.Styles.Add(Name:="ProbeCharStyle", Type:=wdStyleTypeCharacter)
    If Err.Number <> 0 Then
        Note "Styles.Add wdStyleTypeCharacter", ErrText()
        ClearErr
    Else
        Note "Styles.Add wdStyleTypeCharacter", "ok"
        st.Font.SmallCaps = True
        Note "  character style SmallCaps", ErrOrOk()
    End If

    Set st = Nothing
    Set st = mDoc.Styles.Add(Name:="ProbeParaStyle", Type:=wdStyleTypeParagraph)
    Note "Styles.Add wdStyleTypeParagraph", ErrOrOk()
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' modReadBack takes a three-way fast path on Font.SmallCaps: False means nothing
' was transformed, True means the whole cell was, and wdUndefined means mixed
' and it must walk the cell character by character.  That middle case only works
' if Word really does report wdUndefined for a mixed range.
'-----------------------------------------------------------------------------
Private Sub ProbeSmallCapsUndefined()
    Dim r As Range, part As Range
    Dim v As Long
    Head "10. Font.SmallCaps on a mixed range"

    On Error Resume Next
    mDoc.Content.Delete
    Set r = mDoc.Content
    r.Text = "attackcmp"

    Set part = mDoc.Range(mDoc.Content.Start + 6, mDoc.Content.Start + 9)
    part.Font.SmallCaps = True
    Note "set SmallCaps on part of the text", ErrOrOk()

    v = -1
    v = mDoc.Content.Font.SmallCaps
    If Err.Number <> 0 Then
        Note "whole-range SmallCaps", ErrText()
        ClearErr
        Exit Sub
    End If

    Note "whole-range SmallCaps value", CStr(v)
    If v = WD_UNDEFINED Then
        Verdict "USABLE -- mixed reports wdUndefined (9999999) as assumed"
    Else
        Verdict "DIFFERENT -- mixed reports " & CStr(v) & "; modReadBack needs this value"
    End If
    ClearErr
End Sub

' Every setting lives in a document variable, so they travel inside the .docx.
Private Sub ProbeDocumentVariables()
    Dim got As String
    Head "11. Document variables"

    On Error Resume Next
    mDoc.Variables.Add Name:="LingTeXProbe", Value:="roundtrip"
    Note "Variables.Add", ErrOrOk()
    got = mDoc.Variables("LingTeXProbe").Value
    Note "reads back", Quoted(got) & ErrSuffix()
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' Application.UndoRecord collapses an operation into one undo step.  The add-in
' guards it with #If Mac Then; this checks whether that guard is actually needed
' by reaching for it late-bound, which compiles on both platforms.
'-----------------------------------------------------------------------------
Private Sub ProbeUndoRecord()
    Dim o As Object
    Head "12. Application.UndoRecord (late-bound)"

    On Error Resume Next
    Set o = CallByName(Application, "UndoRecord", VbGet)
    If Err.Number <> 0 Then
        Note "UndoRecord", ErrText() & "   (absent is expected on Mac)"
    ElseIf o Is Nothing Then
        Note "UndoRecord", "returned Nothing"
    Else
        Note "UndoRecord", "present -- single-step undo is available here"
    End If
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' A one-paste bootstrap would have to read the .bas files off disk.  Mac Word is
' sandboxed, so this checks whether plain VBA file I/O works in the temp folder.
'-----------------------------------------------------------------------------
Private Sub ProbeFileIO()
    Dim p As String, fn As Integer, lineIn As String
    Head "13. VBA file write and read"

    p = TempPath("lingtex_probe.txt")
    Note "temp path", p

    On Error Resume Next
    fn = FreeFile
    Open p For Output As #fn
    Print #fn, "hello"
    Close #fn
    Note "write", ErrOrOk()

    fn = FreeFile
    Open p For Input As #fn
    Line Input #fn, lineIn
    Close #fn
    Note "read back", Quoted(lineIn) & ErrSuffix()
    ClearErr
End Sub

'-----------------------------------------------------------------------------
' THE OTHER DECISIVE PROBE.
'
' If VBProject.VBComponents.Import is reachable from VBA here, then ONE pasted
' bootstrap can import all thirteen modules and save the .dotm itself.  If it is
' blocked, the fallback is thirteen File > Import File... picks.  Knowing which
' decides how much manual work the build costs.
'-----------------------------------------------------------------------------
Private Sub ProbeVBProject()
    Dim vbp As Object
    Dim comp As Object
    Dim p As String, fn As Integer
    Head "14. VBProject access and Import  <-- DECIDES THE BUILD PATH"

    On Error Resume Next
    Set vbp = ActiveDocument.VBProject
    If Err.Number <> 0 Then
        Note "ActiveDocument.VBProject", ErrText()
        ClearErr
        Set vbp = Application.VBE.ActiveVBProject
        If Err.Number <> 0 Then
            Note "Application.VBE.ActiveVBProject", ErrText()
            Verdict "BLOCKED -- fall back to manual File > Import File..."
            ClearErr
            Exit Sub
        End If
        Note "Application.VBE.ActiveVBProject", "ok"
    Else
        Note "ActiveDocument.VBProject", "ok"
    End If

    Note "VBComponents.Count", CStr(vbp.VBComponents.Count) & ErrSuffix()
    ClearErr

    ' Write a one-line throwaway module and try to import it.
    p = TempPath("modLingTeXProbeImport.bas")
    fn = FreeFile
    Open p For Output As #fn
    Print #fn, "Attribute VB_Name = ""modLingTeXProbeImport"""
    Print #fn, "Option Explicit"
    Print #fn, "Public Function ProbeImported() As String"
    Print #fn, "    ProbeImported = ""imported"""
    Print #fn, "End Function"
    Close #fn
    Note "wrote a test module to temp", ErrOrOk()

    Set comp = Nothing
    Set comp = vbp.VBComponents.Import(p)
    If Err.Number <> 0 Then
        Note "VBComponents.Import", ErrText()
        Verdict "BLOCKED -- fall back to manual File > Import File..."
        ClearErr
    Else
        Note "VBComponents.Import", "ok, created " & comp.Name
        Verdict "AVAILABLE -- one pasted bootstrap can import everything"
        ' Remove it again so nothing is left behind.
        vbp.VBComponents.Remove comp
        ClearErr
    End If

    Kill p
    ClearErr
End Sub

' A bootstrap would use a folder picker to locate src/. Presence only; not shown.
Private Sub ProbeFileDialog()
    Dim fd As Object
    Head "15. Application.FileDialog (folder picker)"

    On Error Resume Next
    Set fd = Application.FileDialog(4)       ' msoFileDialogFolderPicker
    If Err.Number <> 0 Then
        Note "FileDialog(FolderPicker)", ErrText()
    ElseIf fd Is Nothing Then
        Note "FileDialog(FolderPicker)", "returned Nothing"
    Else
        Note "FileDialog(FolderPicker)", "present"
    End If
    ClearErr
End Sub


'=============================================================================
' -- CLEAN UP ---------------------------------------------------------------
'=============================================================================

Private Sub CleanUp()
    Head "16. Clean up"

    On Error Resume Next
    If Not mDoc Is Nothing Then
        mDoc.Styles("ProbeTableStyle").Delete
        mDoc.Styles("ProbeCharStyle").Delete
        mDoc.Styles("ProbeParaStyle").Delete
        ClearErr
        mDoc.Close SaveChanges:=wdDoNotSaveChanges
        Note "closed the scratch document", ErrOrOk()
    End If
    Set mDoc = Nothing

    Kill TempPath("lingtex_probe.txt")
    ClearErr
    Note "removed temp files", "done"
End Sub


'=============================================================================
' -- REPORT HELPERS ---------------------------------------------------------
'=============================================================================

Private Sub Say(ByVal s As String)
    mRpt = mRpt & s & vbCr
End Sub

Private Sub Head(ByVal s As String)
    Say ""
    Say s
    Say String(Len(s), "-")
End Sub

Private Sub Note(ByVal label As String, ByVal result As String)
    Say "  " & Pad(label, 34) & result
End Sub

Private Sub Verdict(ByVal s As String)
    Say "  => " & s
End Sub

Private Function Pad(ByVal s As String, ByVal n As Long) As String
    If Len(s) >= n Then
        Pad = s & " "
    Else
        Pad = s & Space(n - Len(s))
    End If
End Function

Private Function Quoted(ByVal s As String) As String
    Quoted = """" & s & """"
End Function

' Trimmed fixed-point, so the report does not depend on the locale's decimal
' separator being a period.
Private Function Num(ByVal v As Single) As String
    Num = Format(v, "0.0")
End Function

Private Function ErrText() As String
    ErrText = "ERROR " & CStr(Err.Number) & ": " & Err.Description
End Function

' Reports the pending error, if any, then clears it.
Private Function ErrOrOk() As String
    If Err.Number = 0 Then
        ErrOrOk = "ok"
    Else
        ErrOrOk = ErrText()
        Err.Clear
    End If
End Function

Private Function ErrSuffix() As String
    If Err.Number <> 0 Then
        ErrSuffix = "   " & ErrText()
        Err.Clear
    End If
End Function

Private Sub ClearErr()
    Err.Clear
End Sub

' Mac has no TEMP; Windows has no TMPDIR.  Application.PathSeparator differs too.
Private Function TempPath(ByVal leafName As String) As String
    Dim d As String, sep As String

    sep = Application.PathSeparator
    #If Mac Then
        d = Environ("TMPDIR")
        If d = "" Then d = "/tmp/"
    #Else
        d = Environ("TEMP")
        If d = "" Then d = Environ("TMP")
        If d = "" Then d = "C:\Temp"
    #End If

    If Right$(d, 1) <> sep Then d = d & sep
    TempPath = d & leafName
End Function
