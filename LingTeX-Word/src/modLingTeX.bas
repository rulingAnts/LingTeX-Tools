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
' The label of an undo record BeginUndo has named but StartPendingUndo has
' not yet opened. See BeginUndo.
Private mPendingUndoLabel As String

' The ribbon, handed over by its onLoad callback, so the toggle buttons can be
' told to ask for their pressed state again when a setting or the active
' document changes (settings live in the document). Lost if the VBA project
' is reset -- an untrapped error, Run > Reset -- after which the toggles stop
' following changes until Word restarts; the known cost of this Office design.
Private mRibbon As Object

' Keyboard shortcuts, letter=command. Installed by LingTeXInstallShortcuts as
' Ctrl+Alt+letter on Windows, which is Cmd+Option+letter on Mac (the Control
' key code, 512, is the Command key there). Letters chosen to stay clear of Word's own
' Ctrl+Alt / Cmd+Option bindings and of macOS system shortcuts.
Private Const SHORTCUT_TABLE As String = _
    "I=LingTeXInsertInterlinear|R=LingTeXRewrapCurrent|A=LingTeXRewrapAll|" & _
    "S=LingTeXSplitColumn|M=LingTeXMergeColumns|K=LingTeXCheckExample|" & _
    "T=LingTeXConvertTableToIgt|W=LingTeXAlignByWord|P=LingTeXAlignByMorpheme|" & _
    "H=LingTeXShowSettings|L=LingTeXStart|N=LingTeXToggleExampleNumbers"

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
    ' Cleared here as well as set and unset around each command. gBusy wedged True
    ' -- by Ctrl+Break during a render, or a reset of the VBA project -- made every
    ' ribbon button do nothing at all, silently, for the rest of the Word session.
    ' Restarting Word fixed it, but only if you guessed that was the problem.
    gBusy = False
    Set mEvents = New clsAppEvents
    mEvents.Attach
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub AutoExit()
    On Error Resume Next
    If Not mEvents Is Nothing Then mEvents.Detach
    Set mEvents = Nothing
    ReleaseScratch
    On Error GoTo 0
End Sub

' Attach the application hooks if nothing has yet: re-wrap on save, re-wrap
' on leaving an example, AutoCorrect kept out of cells. AutoExec does this when
' Word loads the add-in from STARTUP, but while the code lives in a .docm
' nobody runs it -- and Word for Mac's Macros dialog does not even list it --
' so two by-hand checks that depend on the hooks failed for no other reason
' (2026-09-12). Every command calls this first; it does nothing once armed.
' Deliberately not AutoExec itself, which also clears gBusy.
Public Sub EnsureHooks()
    On Error Resume Next
    If mEvents Is Nothing Then
        Set mEvents = New clsAppEvents
        mEvents.Attach
    End If
    Err.Clear
    On Error GoTo 0
End Sub

' AutoExec by a name that appears in the macro list, on the ribbon and on a
' shortcut, and says what it did.
Public Sub LingTeXStart()
    AutoExec
    Report "LingTeX-Word is armed for this Word session: examples re-wrap " & _
           "when a document is saved (and, if turned on, when the cursor " & _
           "leaves one), and AutoCorrect stays out of interlinear cells." & _
           vbCr & vbCr & "Every command arms this on first use as well.", _
           vbInformation
End Sub


'=============================================================================
' -- INSERTING --------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Insert an interlinear example from the selection, or from the clipboard when
' nothing is selected.
'-----------------------------------------------------------------------------
Public Sub LingTeXInsertInterlinear()
    Dim errNum As Long, errDesc As String
    Dim doc As Document
    Dim raw As String
    Dim ex As IgtExample
    Dim target As Range
    Dim tbl As Table
    Dim warnings As Collection
    Dim fromClipboard As Boolean

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks
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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Adopt a plain Word table as an interlinear example: style it, and wrap it.
' For tables typed by hand or pasted from a spreadsheet.
'-----------------------------------------------------------------------------
Public Sub LingTeXConvertTableToIgt()
    Dim errNum As Long, errDesc As String
    Dim warmed() As Double
    Dim tbl As Table
    Dim ex As IgtExample
    Dim doc As Document
    Dim r As Long, c As Long
    Dim tsv As String, rowText As String

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

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

    ' Styles and measurements BEFORE the undo record opens (see BeginUndo):
    ' creating a style and measuring both write outside the record's document.
    ' Then the record, then the delete -- which used to come first and sat in
    ' the undo list as two or three steps of its own.
    EnsureStyles doc
    MeasureExample ex, doc, warmed

    gBusy = True
    BeginUndo "Convert table to interlinear"
    Application.ScreenUpdating = False

    Dim anchor As Range
    Set anchor = doc.Range(tbl.Range.Start, tbl.Range.Start)
    StartPendingUndo
    tbl.Delete
    RenderExample ex, anchor

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    ' A row merged into a single cell is what the converter takes as a free
    ' translation (it reads the table as TSV, and an untabbed line is a
    ' translation). Say so when there was none, rather than leaving the user
    ' to wonder why the translation stayed inside the table (Seth, 2026-09-12).
    If ex.FreeCount = 0 Then
        Report "Converted. No free translation was found: a row whose cells " & _
               "are merged into ONE cell is taken as the translation, and every " & _
               "other row as a tier." & vbCr & vbCr & _
               "To add one now, type it in the paragraph under the example and " & _
               "give that paragraph the style LingTeX Free; it will be kept " & _
               "with the example from then on.", vbInformation
    End If
    ReportWarnings CheckExample(ex), False
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- RE-WRAPPING ------------------------------------------------------------
'=============================================================================

' Re-wrap the example containing the cursor.
Public Sub LingTeXRewrapCurrent()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Keep the selection through a re-wrap.
'
' A re-wrap deletes an example and draws it again, so the character count
' inside it changes, and the redraw inserts at the very position the old
' example occupied. Seth found what that does to a cursor parked on the empty
' paragraph right after the translation, the natural place to click to keep
' writing: the deletion pulls that position back to the anchor, the draw
' happens at it, and the cursor is now in the first cell of the new table.
' An absolute position cannot survive that. What does survive is the text
' before the first table redrawn and the text from the last table's end on
' (its translations are rewritten letter for letter, and after them nothing
' is touched). So the selection is remembered as an offset from the document's
' start when it lies before the span, from its end when it lies after; inside
' the span it is left to Word.
'
' firstStart and lastEnd are the first redrawn table's Range.Start and the
' last one's Range.End. mode comes back 0 = leave it, 1 = from the start,
' 2 = from the end.
'-----------------------------------------------------------------------------
Public Sub RememberSelection(doc As Document, ByVal firstStart As Long, _
        ByVal lastEnd As Long, ByRef mode As Long, ByRef pos As Long, _
        ByRef length As Long)
    Dim s As Long, e As Long
    mode = 0
    On Error Resume Next
    If Selection Is Nothing Then Exit Sub
    If Not (Selection.Document Is doc) Then Exit Sub
    s = Selection.Range.Start
    e = Selection.Range.End
    If Err.Number <> 0 Then
        Err.Clear
        Exit Sub
    End If
    On Error GoTo 0
    length = e - s
    If e <= firstStart Then
        mode = 1
        pos = s
    ElseIf s >= lastEnd Then
        mode = 2
        pos = doc.Content.End - s
    End If
End Sub

Public Sub RestoreSelection(doc As Document, ByVal mode As Long, _
        ByVal pos As Long, ByVal length As Long)
    Dim s As Long, e As Long
    If mode = 0 Then Exit Sub
    On Error Resume Next
    If mode = 1 Then
        s = pos
    Else
        s = doc.Content.End - pos
    End If
    If s < 0 Then s = 0
    e = s + length
    If e > doc.Content.End Then e = doc.Content.End
    If s > e Then s = e
    doc.Range(s, e).Select
    Err.Clear
    On Error GoTo 0
End Sub

' Re-wrap every example in the active document.
'
' ActiveDocument is evaluated behind a handler, unlike every other command here:
' with no document open it raises, and without this the user got a bare VBA error
' dialog with a line number in it.
Public Sub LingTeXRewrapAll()
    EnsureHooks
    Dim doc As Document

    On Error GoTo Fail
    Set doc = ActiveDocument
    On Error GoTo 0
    If doc Is Nothing Then
        Report "Open a document first.", vbInformation
        Exit Sub
    End If
    RewrapDocument doc, True
    Exit Sub

Fail:
    Report "Open a document first.", vbInformation
End Sub

'-----------------------------------------------------------------------------
' Re-wrap every example in a document.
'
' Tables are collected first and then walked in REVERSE document order.  Each
' re-wrap deletes and redraws a table, which shifts every position after it, so
' working backwards keeps the remaining references valid.
'-----------------------------------------------------------------------------
Public Sub RewrapDocument(doc As Document, ByVal showResult As Boolean)
    Dim errNum As Long, errDesc As String
    Dim tables As Collection
    Dim i As Long, n As Long, nFailed As Long, nDegraded As Long
    Dim done As Table
    Dim firstWhy As String
    Dim selMode As Long, selPos As Long, selLen As Long
    Dim firstStart As Long, lastEnd As Long

    If doc Is Nothing Then Exit Sub
    If gBusy Then
        ' Reported only when the user asked for this. RewrapDocument is ALSO the
        ' re-entrancy path -- clsAppEvents calls it on save with showResult False,
        ' and putting a dialog in front of someone saving a document would be worse
        ' than the silence it replaces. The seven commands report; this does not.
        If showResult Then
            Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
                   "If this keeps happening, run AutoExec in the Immediate " & _
                   "window (or restart Word) to clear it.", vbInformation
        End If
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tables = AllInterlinearTables(doc)
    If tables.Count = 0 Then
        If showResult Then
            Report "This document contains no interlinear examples.", _
                   vbInformation
        End If
        Exit Sub
    End If

    ' Remember where the user was, so an automatic re-wrap does not move them
    ' (see RememberSelection). The tables come in document order.
    firstStart = tables(1).Range.Start
    lastEnd = tables(tables.Count).Range.End
    RememberSelection doc, firstStart, lastEnd, selMode, selPos, selLen

    gBusy = True
    ' Measure everything BEFORE the undo record opens (see BeginUndo): with the
    ' cache warm, the re-wraps below touch the scratch document only for text
    ' the cache has never seen, so the record stays in one piece.
    For i = 1 To tables.Count
        WarmMeasureCache tables(i)
    Next i
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
        ' A document of twenty examples takes a few seconds and shows the busy
        ' cursor meanwhile; VBA has no thread to keep the window live, so the
        ' status bar says how far along it is.
        StatusLine "LingTeX: re-wrapping example " & _
                   CStr(tables.Count - i + 1) & " of " & CStr(tables.Count)
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

    StatusLine ""

    RestoreSelection doc, selMode, selPos, selLen

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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    If showResult Then
        Report "Error " & errNum & ": " & errDesc, vbCritical
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
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim flatCol As Long
    Dim shortTiers As String
    Dim okAll As Boolean

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

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
    If Not ExampleWasRead(ex) Then Exit Sub
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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Merge columns back together.
' Select across several cells to merge exactly those; with the cursor in a single
' cell, that column is merged with the one after it.
'-----------------------------------------------------------------------------
Public Sub LingTeXMergeColumns()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim firstCol As Long, lastCol As Long
    Dim nCells As Long

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

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
    If Not ExampleWasRead(ex) Then Exit Sub
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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- CHECKING ---------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Check the example at the cursor against the column invariants and the Leipzig
' conventions, and offer to repair what has only one right answer.
'-----------------------------------------------------------------------------
Public Sub LingTeXCheckExample()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim warnings As Collection
    Dim nFixable As Long

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run AutoExec in the Immediate window " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    If Not ExampleWasRead(ex) Then Exit Sub
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
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- SHARED HELPERS ---------------------------------------------------------
'=============================================================================

' Draw a model over the top of an existing table, keeping its position.
Private Sub ReplaceTableWith(tbl As Table, ex As IgtExample)

    ' modRender owns "how much of the document is this example" and the order
    ' that keeps the undo record whole (plan, open the record, delete, draw), so
    ' there is only one definition of it. Deleting here first, as this used to,
    ' put the delete outside the record: two or three stray undo steps.
    RedrawExampleAt tbl, ex
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

'-----------------------------------------------------------------------------
' Did the read actually produce a model?
'
' AbsorbFreeParagraphs calls AddFreeLine, which does UBound(ex.FreeLines) -- and on
' a model that never went through NewExample that array is unallocated and UBound
' raises error 9. ReadExampleFromTable returns exactly such a model when it bails
' out early. RewrapTable always checked first; the three column commands did not,
' so each of them could die with a bare VBA error on a table it could not read.
'-----------------------------------------------------------------------------
Private Function ExampleWasRead(ex As IgtExample) As Boolean
    If ex.TierCount > 0 And ex.ColCount > 0 Then
        ExampleWasRead = True
        Exit Function
    End If
    Report "That example could not be read." & _
           IIf(gReadBackError = "", "", vbCr & vbCr & gReadBackError), _
           vbExclamation
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

' Public so clsAppEvents can collapse an automatic re-wrap into one undo step too.
' Without that, reversing a re-wrap nobody asked for -- it fires on a cursor move --
' takes an unknown number of Ctrl+Z presses.
Public Sub BeginUndo(ByVal label As String)
    ' The record is NOT opened here, only named. Measuring text writes to a
    ' hidden scratch document, and a custom undo record that sees a change in
    ' another document is closed by it -- on Mac every drawing step then lists
    ' separately in the undo menu after the record's own label, so one insert
    ' took dozens of Cmd+Z (Seth's screenshot, 2026-09-12). StartPendingUndo
    ' opens the record at the first change to the user's document -- DrawExample,
    ' or RewrapTable just before it deletes -- after every measurement is done,
    ' and RewrapDocument warms the measurement cache before it starts.
    mPendingUndoLabel = label
End Sub

' Open the record BeginUndo named, if it has not been opened yet. Called by the
' renderer immediately before its first change to the document.
Public Sub StartPendingUndo()
    Dim ur As Object
    If mPendingUndoLabel = "" Then Exit Sub
    On Error Resume Next
    Set ur = Application.UndoRecord
    If Not ur Is Nothing Then
        If Not ur.IsRecordingCustomRecord Then ur.StartCustomRecord mPendingUndoLabel
    End If
    Err.Clear
    On Error GoTo 0
    mPendingUndoLabel = ""
End Sub

Public Sub EndUndo()
    Dim ur As Object
    mPendingUndoLabel = ""
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
'=============================================================================
' -- SETTINGS COMMANDS ------------------------------------------------------
'=============================================================================
' Zero-argument, so they appear in Tools > Macro > Macros and can sit on the
' ribbon; the typed setters in modSettings take arguments and cannot. Each one
' acts on the active document, stores the value in it, and says what it did.
' Added because "type this in the Immediate window" turned out to be the one
' step of the by-hand checklist nobody could follow (2026-09-12).

Private Function DocForSetting() As Document
    On Error Resume Next
    Set DocForSetting = ActiveDocument
    On Error GoTo 0
    If DocForSetting Is Nothing Then
        Report "Open a document first: settings are stored in the document.", vbInformation
    End If
End Function

Public Sub LingTeXAlignByWord()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    SetSettingGranularity doc, igtWordAligned
    RefreshRibbon
    Report "New examples in this document will be WORD-aligned: one column per " & _
           "word, with enclitics kept in their host's column." & vbCr & vbCr & _
           "Examples already on the page are unchanged until inserted again.", _
           vbInformation
End Sub

Public Sub LingTeXAlignByMorpheme()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    SetSettingGranularity doc, igtMorphemeAligned
    RefreshRibbon
    Report "New examples in this document will be MORPHEME-aligned: one column " & _
           "per morpheme, with enclitic columns never starting a wrap line." & _
           vbCr & vbCr & _
           "Examples already on the page are unchanged until inserted again.", _
           vbInformation
End Sub

Public Sub LingTeXToggleRewrapOnSave()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingRewrapOnSave(doc)
    SetSettingRewrapOnSave doc, v
    RefreshRibbon
    Report "Re-wrap every example when this document is saved: now " & _
           IIf(v, "ON", "OFF") & ".", vbInformation
End Sub

Public Sub LingTeXToggleRewrapOnSelectionChange()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingRewrapOnSelectionChange(doc)
    SetSettingRewrapOnSelectionChange doc, v
    RefreshRibbon
    Report "Re-wrap an example as soon as the cursor leaves it: now " & _
           IIf(v, "ON", "OFF") & " for this document." & vbCr & vbCr & _
           IIf(v, "Off is the default, because this repaints while you type.", _
                  ""), vbInformation
End Sub

Public Sub LingTeXToggleExampleNumbers()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingNumberExamples(doc)
    SetSettingNumberExamples doc, v
    RefreshRibbon
    Report "New examples in this document are " & IIf(v, "NUMBERED: (1), (2)... " & _
           "with Word's own list numbering, continuing through the document.", _
           "NOT numbered.") & vbCr & vbCr & _
           "Examples already on the page keep whatever they have; a re-wrap " & _
           "keeps a number an example carries.", vbInformation
End Sub

Public Sub LingTeXToggleGramGlossInitialCap()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingGramGlossInitialCap(doc)
    SetSettingGramGlossInitialCap doc, v
    RefreshRibbon
    Report "Grammatical glosses in small capitals now " & _
           IIf(v, "begin with a full-size capital (Erg, 3Sg)", _
                  "are uniform small capitals throughout (erg, 3sg), as the " & _
                  "Leipzig Glossing Rules print them") & "." & vbCr & vbCr & _
           "Re-wrap the examples to apply it.", vbInformation
End Sub

' The LingTeX paragraph styles follow the document's Normal style -- size
' inherited, font pinned from the body font -- but only from when they are
' created; a style is never clobbered once it exists. A document whose styles
' were made before that rule keeps their pinned size, so making Normal bigger
' changes nothing (Seth, 2026-09-12). This resets the six to follow Normal
' again, then re-wraps. It IS a clobber, of any tuning too, and says so.
Public Sub LingTeXResetStyles()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    If Not Confirm("Reset the LingTeX paragraph styles to follow this " & _
                   "document's Normal style (its font and size), and re-wrap " & _
                   "every example?" & vbCr & vbCr & "Any size or font you set " & _
                   "on a LingTeX style yourself is replaced.") Then Exit Sub
    ResetParaStylesToBody doc
    RewrapDocument doc, True
End Sub

Public Sub LingTeXShowSettings()
    Dim doc As Document
    Dim msg As String
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    msg = "LingTeX-Word settings stored in " & doc.Name & ":" & vbCr & vbCr
    msg = msg & "Alignment: " & IIf(SettingGranularity(doc) = igtMorphemeAligned, _
                                    "by morpheme", "by word") & vbCr
    msg = msg & "Gap between columns: " & CStr(SettingGap(doc)) & " pt" & vbCr
    msg = msg & "Gap between wrap lines: " & CStr(SettingLineGap(doc)) & " pt" & vbCr
    msg = msg & "Continuation indent: " & CStr(SettingContIndent(doc)) & " pt" & vbCr
    msg = msg & "Space inside a cell becomes: " & SettingSpaceReplacement(doc) & vbCr
    msg = msg & "Small capitals for grammatical glosses: " & _
                IIf(SettingLowercaseGramGloss(doc), "on", "off") & vbCr
    msg = msg & "  with a full-size first capital: " & _
                IIf(SettingGramGlossInitialCap(doc), "on", "off") & vbCr
    msg = msg & "Number new examples: " & IIf(SettingNumberExamples(doc), "on", "off") & _
                " (hang " & CStr(SettingNumberHang(doc)) & " pt, list level " & _
                CStr(SettingNumberLevel(doc)) & ")" & vbCr
    msg = msg & "Re-wrap on save: " & IIf(SettingRewrapOnSave(doc), "on", "off") & vbCr
    msg = msg & "Re-wrap when the cursor leaves an example: " & _
                IIf(SettingRewrapOnSelectionChange(doc), "on", "off") & vbCr & vbCr
    msg = msg & "Commands: LingTeXAlignByWord, LingTeXAlignByMorpheme, " & _
                "LingTeXToggleRewrapOnSave, LingTeXToggleRewrapOnSelectionChange, " & _
                "LingTeXToggleGramGlossInitialCap, LingTeXToggleExampleNumbers. " & _
                "The gaps, the indent, the number hang and level are set from " & _
                "the Immediate window for now: SetSettingLineGap ActiveDocument, 8"
    Report msg, vbInformation
End Sub


'=============================================================================
' -- KEYBOARD SHORTCUTS -----------------------------------------------------
'=============================================================================
' Installed into this template (or Normal), so they work in every document,
' and removable the same way. Word resolves a macro key binding by name when
' the key is pressed. Added because Tools > Macro > Macros... for every one of
' sixty-six checks was making the by-hand pass take far longer than it needed
' to (Seth, 2026-09-12).
'
' EVERYTHING HERE IS LATE-BOUND. KeyBindings, FindKey, BuildKeyCode,
' CustomizationContext and NormalTemplate are reached through an Object, and
' the key constants are their numbers (macro category 2, Control 512, Alt
' 1024), because a member missing from Mac Word's type library is a COMPILE
' error for this whole module -- and in a template loaded as an add-in that
' means every load, unload and command raises "Compile error in hidden
' module: modLingTeX", endlessly (2026-09-12). Late-bound, a missing member
' is a run-time error inside the trap below, and nothing else suffers.

Public Sub LingTeXInstallShortcuts()
    Dim pairs() As String, kv() As String
    Dim i As Long, n As Long
    Dim errNum As Long, errDesc As String

    Dim app As Object
    On Error GoTo Fail
    Set app = Application
    app.CustomizationContext = ShortcutHome()
    pairs = Split(SHORTCUT_TABLE, "|")
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        app.KeyBindings.Add 2, kv(1), app.BuildKeyCode(512, 1024, Asc(kv(0)))
        n = n + 1
    Next i
    Report CStr(n) & " keyboard shortcuts installed in " & ShortcutHomeName() & ":" & _
           vbCr & vbCr & ShortcutList() & vbCr & _
           "LingTeXRemoveShortcuts takes them out again.", vbInformation
    Exit Sub
Fail:
    errNum = Err.Number: errDesc = Err.Description
    Report "Could not install the shortcuts (" & CStr(errNum) & ": " & errDesc & _
           ")." & vbCr & vbCr & "They can be set by hand: Tools > Customize " & _
           "Keyboard..., category Macros.", vbExclamation
End Sub

Public Sub LingTeXRemoveShortcuts()
    Dim pairs() As String, kv() As String
    Dim i As Long, n As Long
    Dim kb As Object
    Dim app As Object

    On Error Resume Next
    Set app = Application
    app.CustomizationContext = ShortcutHome()
    pairs = Split(SHORTCUT_TABLE, "|")
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        Set kb = app.FindKey(app.BuildKeyCode(512, 1024, Asc(kv(0))))
        If Not kb Is Nothing Then
            If kb.Command = kv(1) Then
                kb.Clear
                n = n + 1
            End If
        End If
    Next i
    Err.Clear
    On Error GoTo 0
    Report CStr(n) & " LingTeX shortcuts removed from " & ShortcutHomeName() & ".", _
           vbInformation
End Sub

' Where the shortcuts are stored: in this template when the code lives in one
' (so they ship with it and apply everywhere it is loaded), else in Normal.
Private Function ShortcutHome() As Object
    Dim app As Object
    On Error Resume Next
    Set app = Application
    If ThisDocument.Type = 1 Then          ' 1 = a template
        Set ShortcutHome = ThisDocument
    Else
        Set ShortcutHome = app.NormalTemplate
    End If
    Err.Clear
    On Error GoTo 0
End Function

Private Function ShortcutHomeName() As String
    On Error Resume Next
    If ThisDocument.Type = 1 Then          ' 1 = a template
        ShortcutHomeName = "the template " & ThisDocument.Name
    Else
        ShortcutHomeName = "the Normal template"
    End If
    Err.Clear
    On Error GoTo 0
End Function

' The status bar, late-bound: a progress line while a long command runs.
Private Sub StatusLine(ByVal s As String)
    Dim app As Object
    On Error Resume Next
    Set app = Application
    app.StatusBar = s
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub LingTeXShowShortcuts()
    Report "LingTeX-Word keyboard shortcuts (once LingTeXInstallShortcuts has " & _
           "been run):" & vbCr & vbCr & ShortcutList(), vbInformation
End Sub

Private Function ShortcutList() As String
    Dim pairs() As String, kv() As String
    Dim i As Long
    Dim prefix As String, s As String

    If Application.PathSeparator = "/" Then
        prefix = "Cmd+Option+"
    Else
        prefix = "Ctrl+Alt+"
    End If
    pairs = Split(SHORTCUT_TABLE, "|")
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        s = s & prefix & kv(0) & "   " & kv(1) & vbCr
    Next i
    ShortcutList = s
End Function

' -- RIBBON CALLBACKS -------------------------------------------------------
'=============================================================================
' The ribbon passes an IRibbonControl.  These are typed as Variant rather than
' IRibbonControl so the project needs no reference to the Office object library,
' which keeps the module importable into a bare VBA project on either platform.

' -- the toggles: state shown on the button, no message ----------------------
' getPressed: Word asks what to show; onAction: the user clicked. Both look at
' the ACTIVE document, because that is where the settings live. The two
' alignment buttons behave as a pair: pressing either sets that alignment and
' both are refreshed.

Public Sub RbnOnLoad(ribbon As Variant)
    On Error Resume Next
    Set mRibbon = ribbon
    Err.Clear
    On Error GoTo 0
End Sub

' Ask every ribbon control to refresh. Called after any setting changes and
' when the active document changes (clsAppEvents).
Public Sub RefreshRibbon()
    On Error Resume Next
    If Not mRibbon Is Nothing Then mRibbon.Invalidate
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub RbnGetPressed(control As Variant, ByRef returnedVal As Variant)
    Dim doc As Document
    returnedVal = False
    On Error Resume Next
    Set doc = ActiveDocument
    If doc Is Nothing Then Exit Sub
    Select Case control.Id
        Case "LingTeXAlignWord"
            returnedVal = (SettingGranularity(doc) = igtWordAligned)
        Case "LingTeXAlignMorpheme"
            returnedVal = (SettingGranularity(doc) = igtMorphemeAligned)
        Case "LingTeXRewrapOnSaveToggle"
            returnedVal = SettingRewrapOnSave(doc)
        Case "LingTeXRewrapOnLeaveToggle"
            returnedVal = SettingRewrapOnSelectionChange(doc)
        Case "LingTeXInitialCapToggle"
            returnedVal = SettingGramGlossInitialCap(doc)
        Case "LingTeXNumbersToggle"
            returnedVal = SettingNumberExamples(doc)
    End Select
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub RbnToggle(control As Variant, pressed As Boolean)
    Dim doc As Document
    On Error Resume Next
    Set doc = ActiveDocument
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    Select Case control.Id
        Case "LingTeXAlignWord"
            SetSettingGranularity doc, igtWordAligned
        Case "LingTeXAlignMorpheme"
            SetSettingGranularity doc, igtMorphemeAligned
        Case "LingTeXRewrapOnSaveToggle"
            SetSettingRewrapOnSave doc, pressed
        Case "LingTeXRewrapOnLeaveToggle"
            SetSettingRewrapOnSelectionChange doc, pressed
        Case "LingTeXInitialCapToggle"
            SetSettingGramGlossInitialCap doc, pressed
        Case "LingTeXNumbersToggle"
            SetSettingNumberExamples doc, pressed
    End Select
    Err.Clear
    On Error GoTo 0
    RefreshRibbon
End Sub

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

Public Sub RbnAlignByWord(control As Variant)
    LingTeXAlignByWord
End Sub

Public Sub RbnAlignByMorpheme(control As Variant)
    LingTeXAlignByMorpheme
End Sub

Public Sub RbnToggleRewrapOnSave(control As Variant)
    LingTeXToggleRewrapOnSave
End Sub

Public Sub RbnToggleRewrapOnSelectionChange(control As Variant)
    LingTeXToggleRewrapOnSelectionChange
End Sub

Public Sub RbnToggleGramGlossInitialCap(control As Variant)
    LingTeXToggleGramGlossInitialCap
End Sub

Public Sub RbnShowSettings(control As Variant)
    LingTeXShowSettings
End Sub

Public Sub RbnInstallShortcuts(control As Variant)
    LingTeXInstallShortcuts
End Sub

Public Sub RbnShowShortcuts(control As Variant)
    LingTeXShowShortcuts
End Sub

Public Sub RbnToggleExampleNumbers(control As Variant)
    LingTeXToggleExampleNumbers
End Sub

Public Sub RbnStart(control As Variant)
    LingTeXStart
End Sub

Public Sub RbnResetStyles(control As Variant)
    LingTeXResetStyles
End Sub
