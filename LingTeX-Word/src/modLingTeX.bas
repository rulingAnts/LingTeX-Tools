Attribute VB_Name = "modLingTeX"
Option Explicit

'=============================================================================
' modLingTeX  --  LingTeX-Word
'
' The commands.  Everything the user can run from the ribbon, the Macros dialog
' (Alt+F8) or a keyboard shortcut lives here; the real work is in the modules
' below it.
'
' ---------------------------------------------------------------------------
' HOW TO INSERT AN EXAMPLE  (Phase 1)
'
' Either:
'   * Copy an interlinear selection in FLEx, put the cursor where it belongs, and
'     run LingTeXInsertInterlinear.  The clipboard is read and the example is
'     drawn at the cursor.
'   * Or paste the FLEx text into the document first, select it, and run the same
'     command.  The selection is replaced by the drawn example.
'
' Phase 2 adds a form with an editable data table in front of this; the engine
' below does not change when it arrives.  See ..\README.md.
' ---------------------------------------------------------------------------
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

' Re-entrancy guard.  Word has no Application.EnableEvents, so an event handler
' that edits the document would otherwise re-trigger itself.  clsAppEvents checks
' this before doing anything.
Public gBusy As Boolean

' Set by AutoExec.  Module-level so the events object outlives the procedure.
Private mEvents As clsAppEvents

'-----------------------------------------------------------------------------
' EVERY message to the user goes through Report or Confirm, never MsgBox.
'
' Not a style rule -- it is what makes the commands testable. A MsgBox blocks on a
' modal dialog, so a test that runs a command waits forever for a person to click
' OK, and modDocTests could not drive any of the seven commands at all. With this
' indirection a test sets gQuiet, runs the command, and asserts on gLastMessage:
' "the right thing was reported" becomes a comparison instead of a thing someone
' watched happen.
'
' gLastMessage is set whether or not a dialog is shown, so it is also the record
' of what the user was last told.
'-----------------------------------------------------------------------------
' The only two MsgBox calls in the module are in Report and Confirm below, and
' the title is a constant rather than a literal at each one: a bulk edit over this
' file can no longer silently take it off them.
Private Const DIALOG_TITLE As String = "LingTeX-Word"

Public gQuiet As Boolean            ' suppress dialogs (tests set this)
Public gQuietAnswer As Boolean      ' what Confirm returns while quiet
Public gLastMessage As String       ' the last thing reported, dialog or not

Public Sub Report(ByVal msg As String, ByVal kind As Long)
    gLastMessage = msg
    If gQuiet Then Exit Sub
    MsgBox msg, kind, DIALOG_TITLE
End Sub

' A yes/no question.  Same contract: while quiet it answers gQuietAnswer rather
' than asking, so a test can exercise both the accept and the decline path.
Public Function Confirm(ByVal msg As String) As Boolean
    gLastMessage = msg
    If gQuiet Then
        Confirm = gQuietAnswer
        Exit Function
    End If
    Confirm = (MsgBox(msg, vbYesNo + vbQuestion, DIALOG_TITLE) = vbYes)
End Function


'=============================================================================
' -- STARTUP ----------------------------------------------------------------
'=============================================================================

' Runs when Word loads the add-in from its STARTUP folder.
Public Sub AutoExec()
    On Error Resume Next
    Set mEvents = New clsAppEvents
    mEvents.Attach
    On Error GoTo 0
End Sub

Public Sub AutoExit()
    On Error Resume Next
    If Not mEvents Is Nothing Then mEvents.Detach
    Set mEvents = Nothing
    ReleaseScratch
    On Error GoTo 0
End Sub


'=============================================================================
' -- INSERTING --------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Insert an interlinear example from the selection, or from the clipboard when
' nothing is selected.
'-----------------------------------------------------------------------------
Public Sub LingTeXInsertInterlinear()
    Dim doc As Document
    Dim raw As String
    Dim ex As IgtExample
    Dim target As Range
    Dim tbl As Table
    Dim warnings As Collection
    Dim fromClipboard As Boolean

    If gBusy Then Exit Sub
    On Error GoTo Fail
    Set doc = ActiveDocument

    If Selection.Type = wdSelectionIP Then
        raw = ClipboardText()
        fromClipboard = True
        If Trim$(raw) = "" Then
            Report "Nothing to insert." & vbCr & vbCr & _
                   "Copy an interlinear selection in FLEx first, or paste the " & _
                   "text into the document and select it before running this.", _
                   vbInformation
            Exit Sub
        End If
        Set target = Selection.Range.Duplicate
    Else
        raw = Selection.Range.Text
        Set target = SelectedParagraphRange()
    End If

    ex = ModelFromText(raw, SettingGranularity(doc))
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        Report "That text could not be read as interlinear data." & vbCr & vbCr & _
               "Expected FLEx interlinear text (tab-separated, with tier labels " & _
               "such as Morphemes and Lex. Gloss), or a plain tab-separated " & _
               "table with one row per tier.", vbExclamation
        Exit Sub
    End If

    ' Repair what has only one right answer before drawing, so the example does
    ' not arrive already violating its own invariants.
    FixCellSpaces ex, SettingSpaceReplacement(doc)

    gBusy = True
    BeginUndo "Insert interlinear"
    Application.ScreenUpdating = False

    Set tbl = RenderExample(ex, target)

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If tbl Is Nothing Then
        Report "The example could not be drawn." & _
               IIf(gRenderError = "", "", vbCr & vbCr & gRenderError), _
               vbExclamation
        Exit Sub
    End If

    ' A table came back, but something in the drawing did not take -- a cell width
    ' Word refused, a row that could not be trimmed. The example is on the page and
    ' may well look wrong, so it is worth saying rather than leaving the user to
    ' wonder whether the wrap planner is broken.
    If gRenderError <> "" Then
        Report "The example was drawn, but not exactly as planned:" & vbCr & vbCr & _
               gRenderError & vbCr & vbCr & _
               "Re-wrapping it may fix the layout.", vbExclamation
    End If

    ' Report only what a person has to decide; the rest was already fixed.
    Set warnings = CheckExample(ex)
    ReportWarnings warnings, False
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Adopt a plain Word table as an interlinear example: style it, and wrap it.
' For tables typed by hand or pasted from a spreadsheet.
'-----------------------------------------------------------------------------
Public Sub LingTeXConvertTableToIgt()
    Dim tbl As Table
    Dim ex As IgtExample
    Dim doc As Document
    Dim r As Long, c As Long
    Dim tsv As String, rowText As String

    If gBusy Then Exit Sub
    On Error GoTo Fail

    If Not Selection.Information(wdWithInTable) Then
        Report "Put the cursor inside the table you want to convert.", _
               vbInformation
        Exit Sub
    End If

    Set tbl = Selection.Tables(1)
    Set doc = ActiveDocument

    If IsInterlinearTable(tbl) Then
        Report "That table is already an interlinear example.", _
               vbInformation
        Exit Sub
    End If

    ' Read it as TSV, which is the shape ModelFromTsv already understands.
    For r = 1 To tbl.Rows.Count
        rowText = ""
        For c = 1 To tbl.Rows(r).Cells.Count
            If c > 1 Then rowText = rowText & vbTab
            rowText = rowText & CleanedCellText(tbl, r, c)
        Next c
        If tsv <> "" Then tsv = tsv & vbLf
        tsv = tsv & rowText
    Next r

    ex = ModelFromTsv(tsv)
    If ex.TierCount = 0 Then
        Report "That table could not be read as interlinear data.", _
               vbExclamation
        Exit Sub
    End If

    gBusy = True
    BeginUndo "Convert table to interlinear"
    Application.ScreenUpdating = False

    Dim anchor As Range
    Set anchor = doc.Range(tbl.Range.Start, tbl.Range.Start)
    tbl.Delete
    RenderExample ex, anchor

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    ReportWarnings CheckExample(ex), False
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub


'=============================================================================
' -- RE-WRAPPING ------------------------------------------------------------
'=============================================================================

' Re-wrap the example containing the cursor.
Public Sub LingTeXRewrapCurrent()
    Dim tbl As Table
    If gBusy Then Exit Sub
    On Error GoTo Fail

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    gBusy = True
    BeginUndo "Re-wrap interlinear"
    Application.ScreenUpdating = False
    RewrapTable tbl
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub

' Re-wrap every example in the active document.
Public Sub LingTeXRewrapAll()
    RewrapDocument ActiveDocument, True
End Sub

'-----------------------------------------------------------------------------
' Re-wrap every example in a document.
'
' Tables are collected first and then walked in REVERSE document order.  Each
' re-wrap deletes and redraws a table, which shifts every position after it, so
' working backwards keeps the remaining references valid.
'-----------------------------------------------------------------------------
Public Sub RewrapDocument(doc As Document, ByVal showResult As Boolean)
    Dim tables As Collection
    Dim i As Long, n As Long, nFailed As Long, nDegraded As Long
    Dim done As Table
    Dim firstWhy As String
    Dim savedStart As Long, savedEnd As Long
    Dim restore As Boolean

    If doc Is Nothing Then Exit Sub
    If gBusy Then Exit Sub
    On Error GoTo Fail

    Set tables = AllInterlinearTables(doc)
    If tables.Count = 0 Then
        If showResult Then
            Report "This document contains no interlinear examples.", _
                   vbInformation
        End If
        Exit Sub
    End If

    ' Remember where the user was, so an automatic re-wrap does not move them.
    On Error Resume Next
    If Not Selection Is Nothing Then
        savedStart = Selection.Range.Start
        savedEnd = Selection.Range.End
        restore = True
    End If
    On Error GoTo Fail

    gBusy = True
    BeginUndo "Re-wrap all interlinear examples"
    Application.ScreenUpdating = False

    ' Count what actually came back, not what Err happens to hold.
    '
    ' This used to read "If Err.Number = 0 Then n = n + 1", which is wrong twice
    ' over. On Error Resume Next leaves Err set by anything that raised and was
    ' swallowed anywhere inside the render -- and EnsureTableStyle raises 4198 on
    ' Mac by design, on its six Style.Table.Borders lines, the first time an
    ' example is drawn in a fresh document. On Error GoTo 0 does not clear Err. So
    ' the first successful re-wrap in a new document reported as a failure, and
    ' "Re-wrapped 0 interlinear examples" was the message for a run that had just
    ' worked.
    n = 0
    nFailed = 0
    For i = tables.Count To 1 Step -1
        On Error Resume Next
        Set done = RewrapTable(tables(i))
        If done Is Nothing Then
            nFailed = nFailed + 1
            If firstWhy = "" Then firstWhy = gRenderError
        Else
            n = n + 1
            ' Drawn, but not exactly as planned. Counted as a success because the
            ' example is on the page, and still reported, because a layout that is
            ' quietly wrong is the thing this whole suite of changes is about.
            If gRenderError <> "" Then
                nDegraded = nDegraded + 1
                If firstWhy = "" Then firstWhy = gRenderError
            End If
        End If
        Err.Clear
        On Error GoTo Fail
    Next i

    If restore Then
        On Error Resume Next
        If savedEnd > doc.Content.End Then savedEnd = doc.Content.End
        If savedStart > savedEnd Then savedStart = savedEnd
        doc.Range(savedStart, savedEnd).Select
        Err.Clear
        On Error GoTo Fail
    End If

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If showResult Or nFailed > 0 Or nDegraded > 0 Then
        If nFailed = 0 And nDegraded = 0 Then
            Report "Re-wrapped " & CStr(n) & " interlinear example" & _
                   IIf(n = 1, "", "s") & ".", vbInformation
        Else
            ' Reported even when showResult is False -- an automatic re-wrap that
            ' skipped an example must not do so silently.
            Report "Re-wrapped " & CStr(n) & " interlinear example" & _
                   IIf(n = 1, "", "s") & ", and could not re-wrap " & _
                   CStr(nFailed) & "." & _
                   IIf(nDegraded = 0, "", vbCr & CStr(nDegraded) & _
                       " were drawn but not exactly as planned.") & _
                   IIf(firstWhy = "", "", vbCr & vbCr & "First problem: " & firstWhy) & _
                   vbCr & vbCr & "The examples that could not be re-wrapped were " & _
                   "left exactly as they were.", vbExclamation
        End If
    End If
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    If showResult Then
        Report "Error " & Err.Number & ": " & Err.Description, vbCritical
    End If
End Sub


'=============================================================================
' -- ADJUSTING ALIGNMENT ----------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Split the column at the cursor at its first morpheme boundary.
'
' This is how an otherwise word-aligned example gets one affix, clitic or
' reduplicant pulled out into a column of its own.  The boundary character is
' carried onto the start of the new column on EVERY interlinear tier, so the
' column invariant holds without the user having to tidy up after it.
'-----------------------------------------------------------------------------
Public Sub LingTeXSplitColumn()
    Dim tbl As Table
    Dim ex As IgtExample
    Dim flatCol As Long
    Dim shortTiers As String
    Dim okAll As Boolean

    If gBusy Then Exit Sub
    On Error GoTo Fail

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor in the column you want to split.", _
               vbInformation
        Exit Sub
    End If

    flatCol = FlatColumnAt(tbl, Selection.Cells(1).RowIndex, _
                                Selection.Cells(1).ColumnIndex)
    If flatCol < 0 Then
        Report "That column could not be located.", vbExclamation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    AbsorbFreeParagraphs ex, tbl
    okAll = SplitColumn(ex, flatCol, 1, shortTiers)

    gBusy = True
    BeginUndo "Split interlinear column"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If Not okAll Then
        ' Exactly the Leipzig rule 2 problem: the form has a morpheme break its
        ' gloss does not.  Guessing would rewrite the analysis, so say so instead.
        Report "No morpheme break was found in: " & shortTiers & vbCr & vbCr & _
               "Those cells were left whole and the new column is empty for " & _
               "them. Add the matching break, or undo with Ctrl+Z.", _
               vbExclamation
    End If
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Merge columns back together.
' Select across several cells to merge exactly those; with the cursor in a single
' cell, that column is merged with the one after it.
'-----------------------------------------------------------------------------
Public Sub LingTeXMergeColumns()
    Dim tbl As Table
    Dim ex As IgtExample
    Dim firstCol As Long, lastCol As Long
    Dim nCells As Long

    If gBusy Then Exit Sub
    On Error GoTo Fail

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Select the columns you want to merge.", vbInformation
        Exit Sub
    End If

    nCells = Selection.Cells.Count
    firstCol = FlatColumnAt(tbl, Selection.Cells(1).RowIndex, _
                                 Selection.Cells(1).ColumnIndex)
    If firstCol < 0 Then
        Report "Those columns could not be located.", vbExclamation
        Exit Sub
    End If

    If nCells > 1 Then
        lastCol = FlatColumnAt(tbl, Selection.Cells(nCells).RowIndex, _
                                     Selection.Cells(nCells).ColumnIndex)
    Else
        lastCol = firstCol + 1
    End If
    If lastCol <= firstCol Then
        Report "There is no following column to merge with.", _
               vbInformation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    AbsorbFreeParagraphs ex, tbl
    If lastCol > ex.ColCount - 1 Then lastCol = ex.ColCount - 1
    If Not MergeColumns(ex, firstCol, lastCol) Then
        Report "Those columns could not be merged.", vbExclamation
        Exit Sub
    End If

    gBusy = True
    BeginUndo "Merge interlinear columns"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub


'=============================================================================
' -- CHECKING ---------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Check the example at the cursor against the column invariants and the Leipzig
' conventions, and offer to repair what has only one right answer.
'-----------------------------------------------------------------------------
Public Sub LingTeXCheckExample()
    Dim tbl As Table
    Dim ex As IgtExample
    Dim warnings As Collection
    Dim nFixable As Long

    If gBusy Then Exit Sub
    On Error GoTo Fail

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    AbsorbFreeParagraphs ex, tbl
    Set warnings = CheckExample(ex)

    If warnings.Count = 0 Then
        Report "No problems found.", vbInformation
        Exit Sub
    End If

    nFixable = FixableCount(warnings)
    If nFixable = 0 Then
        ReportWarnings warnings, True
        Exit Sub
    End If

    If Not Confirm(WarningText(warnings) & vbCr & vbCr & _
              CStr(nFixable) & " of these can be fixed automatically. " & _
              "Fix them now?") Then Exit Sub

    FixWhatWeCan ex, SettingSpaceReplacement(ActiveDocument)

    gBusy = True
    BeginUndo "Fix interlinear example"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    ' Anything still standing needs a human decision.
    ReportWarnings CheckExample(ex), False
    Exit Sub

Fail:
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & Err.Number & ": " & Err.Description, vbCritical
End Sub


'=============================================================================
' -- SHARED HELPERS ---------------------------------------------------------
'=============================================================================

' Draw a model over the top of an existing table, keeping its position.
Private Sub ReplaceTableWith(tbl As Table, ex As IgtExample)
    Dim doc As Document
    Dim anchor As Range
    Dim startPos As Long

    Set doc = tbl.Range.Document
    startPos = tbl.Range.Start
    ' modRender owns "how much of the document is this example", so there is only
    ' one definition of it.
    DeleteTableAndFreeLines tbl
    Set anchor = doc.Range(startPos, startPos)
    RenderExample ex, anchor
End Sub

'-----------------------------------------------------------------------------
' Whole paragraphs covered by the selection.
' The pasted FLEx text occupies entire paragraphs, so the replacement has to
' cover them entirely or a stray paragraph mark is left behind.
'-----------------------------------------------------------------------------
Private Function SelectedParagraphRange() As Range
    Dim r As Range
    Set r = Selection.Range.Duplicate
    r.Start = r.Paragraphs(1).Range.Start
    r.End = r.Paragraphs(r.Paragraphs.Count).Range.End
    ' Keep the final paragraph mark so the document structure survives.
    If r.End > r.Start Then r.End = r.End - 1
    Set SelectedParagraphRange = r
End Function

'-----------------------------------------------------------------------------
' Read the clipboard as plain text.
'
' Deliberately NOT via MSForms.DataObject, which is unreliable or absent on Mac
' Word.  Instead a hidden document is used as the landing pad: Word's own paste
' works identically on both platforms, and wdPasteText asks for the text/plain
' flavour, which for FLEx is the tab-separated form this add-in wants.
'-----------------------------------------------------------------------------
Public Function ClipboardText() As String
    Dim tmp As Document
    Dim s As String

    On Error Resume Next
    Set tmp = Documents.Add(Visible:=False)
    If tmp Is Nothing Then
        Set tmp = Documents.Add
        If Not tmp Is Nothing Then
            If tmp.Windows.Count > 0 Then tmp.Windows(1).Visible = False
        End If
    End If
    If tmp Is Nothing Then
        Err.Clear
        Exit Function
    End If

    tmp.Content.PasteSpecial DataType:=wdPasteText
    s = tmp.Content.Text
    tmp.Close SaveChanges:=wdDoNotSaveChanges
    Err.Clear
    On Error GoTo 0

    ClipboardText = s
End Function

Private Function CleanedCellText(tbl As Table, ByVal r As Long, ByVal c As Long) As String
    Dim s As String
    On Error Resume Next
    s = tbl.Cell(r, c).Range.Text
    Err.Clear
    On Error GoTo 0
    s = Replace(s, Chr$(7), "")
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    CleanedCellText = Trim$(s)
End Function


'=============================================================================
' -- WARNING PRESENTATION ---------------------------------------------------
'=============================================================================

Private Function WarningText(warnings As Collection) As String
    Dim w As Variant, s As String, n As Long
    If warnings Is Nothing Then Exit Function
    For Each w In warnings
        n = n + 1
        If n > 12 Then
            s = s & vbCr & "... and " & CStr(warnings.Count - 12) & " more."
            Exit For
        End If
        If s <> "" Then s = s & vbCr
        s = s & "- " & w.Describe
    Next w
    WarningText = s
End Function

' Show the findings.  Silent when there are none, so it is safe to call after
' every operation.
Private Sub ReportWarnings(warnings As Collection, ByVal alsoWhenEmpty As Boolean)
    If warnings Is Nothing Then Exit Sub
    If warnings.Count = 0 Then
        If alsoWhenEmpty Then
            Report "No problems found.", vbInformation
        End If
        Exit Sub
    End If
    Report WarningText(warnings), vbExclamation
End Sub


'=============================================================================
' -- UNDO -------------------------------------------------------------------
'=============================================================================
' Application.UndoRecord collapses a whole operation into ONE undo step, which
' matters because re-wrapping deletes and rebuilds a table: without it, undoing
' one re-wrap takes an unknown number of presses.
'
' There is deliberately NO "#If Mac Then" guard here.  An earlier version assumed
' UndoRecord was Windows-only and compiled it out on Mac, which silently gave Mac
' users multi-step undo for no reason -- the probe
' (tools/probe/modProbe.bas section 12) found it present on Word 16.112 for Mac.
'
' It is reached late-bound through Object and every call is error-guarded, so a
' build that genuinely lacks it degrades to Word's own undo stack instead of
' failing to compile.  That is what makes the guard unnecessary: there is nothing
' to compile out.

Private Sub BeginUndo(ByVal label As String)
    Dim ur As Object
    On Error Resume Next
    Set ur = Application.UndoRecord
    If Not ur Is Nothing Then
        If ur.IsRecordingCustomRecord Then ur.EndCustomRecord
        ur.StartCustomRecord label
    End If
    Err.Clear
    On Error GoTo 0
End Sub

Private Sub EndUndo()
    Dim ur As Object
    On Error Resume Next
    Set ur = Application.UndoRecord
    If Not ur Is Nothing Then
        If ur.IsRecordingCustomRecord Then ur.EndCustomRecord
    End If
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- INSTALL VERIFICATION ---------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Returns an identifying string, and exists to be called from outside Word.
'
' Mac Word's AppleScript dictionary has no `do Visual Basic`, so a script cannot
' execute arbitrary VBA -- but it does have `run VB macro`, which runs a macro that
' already exists (confirmed by tools/probe/Probe AppleScript Bridge.applescript).
'
' That is exactly enough for the Mac installer to CHECK ITS OWN WORK. After
' copying the template into Word's startup folder it can relaunch Word and run
' this; a result means the add-in genuinely loaded, an error means it did not.
'
' Worth having because the known silent failure is macOS quarantining a .dotm that
' arrived inside a downloaded zip: Word then refuses to load it and the user sees
' a successful install and no ribbon. Without a callable hook there is no way for
' the installer to tell those apart.
'
' Keep it trivial, dependency-free and never-throwing: it is a heartbeat, and
' anything it touched could become a reason for it to fail misleadingly.
'-----------------------------------------------------------------------------
Public Function LingTeXPing() As String
    LingTeXPing = "LingTeX-Word loaded"
End Function


'=============================================================================
' -- RIBBON CALLBACKS -------------------------------------------------------
'=============================================================================
' The ribbon passes an IRibbonControl.  These are typed as Variant rather than
' IRibbonControl so the project needs no reference to the Office object library,
' which keeps the module importable into a bare VBA project on either platform.

Public Sub RbnInsert(control As Variant)
    LingTeXInsertInterlinear
End Sub

Public Sub RbnRewrapCurrent(control As Variant)
    LingTeXRewrapCurrent
End Sub

Public Sub RbnRewrapAll(control As Variant)
    LingTeXRewrapAll
End Sub

Public Sub RbnSplitColumn(control As Variant)
    LingTeXSplitColumn
End Sub

Public Sub RbnMergeColumns(control As Variant)
    LingTeXMergeColumns
End Sub

Public Sub RbnCheck(control As Variant)
    LingTeXCheckExample
End Sub

Public Sub RbnConvertTable(control As Variant)
    LingTeXConvertTableToIgt
End Sub
