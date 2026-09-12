VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsAppEvents"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'=============================================================================
' clsAppEvents  --  LingTeX-Word
'
' Word application events, so examples re-wrap themselves at the right moments.
'
' Instantiated once by modLingTeX.AutoExec and held in a module-level variable
' there; an events object that goes out of scope stops receiving events silently,
' which is the classic way this kind of hook appears to "randomly stop working".
'
' ---------------------------------------------------------------------------
' WHEN A RE-WRAP HAPPENS
'
'   On save        DocumentBeforeSave, by default.  The point at which the
'                  document has to be right, and a moment the user already
'                  expects to pause.
'
'   On selection   WindowSelectionChange, OFF by default.  Re-wrapping the
'                  moment the cursor leaves an example is correct and feels
'                  automatic, but it repaints and moves the insertion point while
'                  someone may still be typing.  Turn it on per document with
'                  modSettings.SetSettingRewrapOnSelectionChange.
'
' Both are in addition to the ribbon commands, which are always available.
'
' RE-ENTRANCY.  Word has no Application.EnableEvents, so an event handler that
' edits the document would re-trigger itself.  Every handler checks
' modLingTeX.gBusy first, and every command sets it.  Without that guard a
' re-wrap on selection change would recurse until the stack gave out.
' ---------------------------------------------------------------------------
'=============================================================================

Private WithEvents mApp As Word.Application
Attribute mApp.VB_VarHelpID = -1

' The table the selection was last inside, so leaving it can be detected.
Private mLastTableStart As Long
Private mLastDocName    As String

' Automatic re-wrapping fires on every cursor move out of an example, so a failure
' must be said ONCE rather than on every keystroke afterwards.
Private mWarnedThisDoc  As Boolean
' Word's AutoCorrect capitalises the first letter of a table cell and of a
' sentence, which turns "zel" into "Zel" the moment a cell is edited. Both are
' switched off while the selection is inside an interlinear example and put
' back on the way out; these hold what they were.
Private mAcSaved As Boolean
Private mAcSentence As Boolean
Private mAcCells As Boolean

' How many times the handlers have actually done work. Not used by the add-in --
' modDocTests reads it to prove that a re-wrap triggered from a handler does not
' re-enter the handler, which is what gBusy is there to prevent and what no amount
' of reading the code can establish.
Public mHandlerCount As Long

Public Sub Attach()
    Set mApp = Word.Application
    mLastTableStart = -1
    mLastDocName = ""
    mWarnedThisDoc = False
    mHandlerCount = 0
End Sub

Public Sub Detach()
    RestoreAutoCorrect
    Set mApp = Nothing
End Sub

' Off inside an example, back to the user's own settings outside one. Late-bound
' (As Object) so a build whose AutoCorrect lacks one of the two properties fails
' at run time under the trap rather than at compile time -- see wdStyleTableGrid.
Private Sub SuppressAutoCorrect()
    Dim ac As Object
    If mAcSaved Then Exit Sub
    On Error Resume Next
    Set ac = Application.AutoCorrect
    If ac Is Nothing Then Exit Sub
    mAcSentence = ac.CorrectSentenceCaps
    mAcCells = ac.CorrectTableCells
    If Err.Number <> 0 Then
        Err.Clear
        Exit Sub
    End If
    ac.CorrectSentenceCaps = False
    ac.CorrectTableCells = False
    Err.Clear
    mAcSaved = True
End Sub

Private Sub RestoreAutoCorrect()
    Dim ac As Object
    If Not mAcSaved Then Exit Sub
    On Error Resume Next
    Set ac = Application.AutoCorrect
    If Not ac Is Nothing Then
        ac.CorrectSentenceCaps = mAcSentence
        ac.CorrectTableCells = mAcCells
    End If
    Err.Clear
    mAcSaved = False
End Sub

'-----------------------------------------------------------------------------
' Re-wrap every example before the document is written out.
'
' The margins, the page size, the body font or the styles may all have changed
' since the examples were drawn, and this is the last moment to put that right.
' Failure is swallowed: a problem in the add-in must never stop a save.
'-----------------------------------------------------------------------------
Private Sub mApp_DocumentBeforeSave(ByVal Doc As Document, SaveAsUI As Boolean, Cancel As Boolean)
    On Error Resume Next
    If gBusy Then Exit Sub
    If Doc Is Nothing Then Exit Sub
    If Not SettingRewrapOnSave(Doc) Then Exit Sub
    mHandlerCount = mHandlerCount + 1
    RewrapDocument Doc, False
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
' Re-wrap an example as soon as the selection leaves it (opt in).
'
' Only fires on actually LEAVING a table, not on every cursor move inside one --
' otherwise it would fight the user mid-edit.
'-----------------------------------------------------------------------------
Private Sub mApp_WindowSelectionChange(ByVal Sel As Selection)
    Dim tbl As Table
    Dim nowStart As Long
    Dim doc As Document
    Dim leaving As Table
    Dim done As Table
    Dim errNum As Long, errDesc As String
    Dim msg As String

    On Error Resume Next
    If gBusy Then Exit Sub
    If Sel Is Nothing Then Exit Sub
    Set doc = Sel.Document
    If doc Is Nothing Then Exit Sub

    Set tbl = FindExampleAt(Sel.Range)
    If tbl Is Nothing Then
        nowStart = -1
        RestoreAutoCorrect
    Else
        nowStart = tbl.Range.Start
        SuppressAutoCorrect
    End If

    ' A different document, so the once-per-document warning starts again.
    If doc.Name <> mLastDocName Then mWarnedThisDoc = False

    ' Still in the same example: nothing to do.
    If nowStart = mLastTableStart And doc.Name = mLastDocName Then Exit Sub

    If SettingRewrapOnSelectionChange(doc) And mLastTableStart >= 0 And doc.Name = mLastDocName Then
        ' We have just left the example that started at mLastTableStart.
        Set leaving = ExampleStartingAt(doc, mLastTableStart)
        If Not leaving Is Nothing Then
            '---------------------------------------------------------------
            ' ONE UNDO STEP, AND A REAL ERROR TRAP.
            '
            ' A re-wrap deletes and rebuilds a table, so without BeginUndo /
            ' EndUndo the user needs an unknown number of Ctrl+Z presses to
            ' reverse something they never asked for -- this fires on a cursor
            ' move. Every command in modLingTeX wraps its work this way; this
            ' handler did not.
            '
            ' And the trap is narrowed to this call. The whole handler ran under
            ' one On Error Resume Next, which covered RewrapTable as well -- so
            ' when a re-wrap failed after deleting the old table, the example was
            ' destroyed on a cursor move with nothing reported anywhere.
            ' RewrapTable now plans before it deletes, so that window is small,
            ' but a handler that cannot report is not a place to rely on it.
            '---------------------------------------------------------------
            mHandlerCount = mHandlerCount + 1
            gBusy = True
            Application.ScreenUpdating = False
            On Error GoTo RewrapFailed
            BeginUndo "Re-wrap interlinear example"
            Set done = RewrapTable(leaving)
            EndUndo
            On Error Resume Next
            Application.ScreenUpdating = True
            gBusy = False
            ReleaseScratch

            If done Is Nothing Then
                ' Left alone rather than damaged -- RewrapTable plans first. Say so
                ' once; this fires on cursor movement and must not nag.
                If Not mWarnedThisDoc Then
                    mWarnedThisDoc = True
                    msg = "An interlinear example could not be re-wrapped "
                    msg = msg & "automatically, so it was left as it was." & vbCr & vbCr
                    msg = msg & IIf(gRenderError = "", "", gRenderError & vbCr & vbCr)
                    msg = msg & "Automatic re-wrapping on cursor movement can be turned "
                    msg = msg & "off in the settings."
                    Report msg, vbExclamation
                End If
            End If

            ' Positions moved, so re-read where we are now.
            Set tbl = FindExampleAt(Selection.Range)
            If tbl Is Nothing Then
                nowStart = -1
            Else
                nowStart = tbl.Range.Start
            End If
        End If
    End If

    mLastTableStart = nowStart
    mLastDocName = doc.Name
    Err.Clear
    Exit Sub

RewrapFailed:
    ' Only reachable if RewrapTable raised rather than returning Nothing.
    ' Captured before the On Error Resume Next below, which resets Err; read
    ' after it, the message said "0: " and the error was gone.
    errNum = Err.Number: errDesc = Err.Description
    On Error Resume Next
    EndUndo
    Application.ScreenUpdating = True
    gBusy = False
    ReleaseScratch
    If Not mWarnedThisDoc Then
        mWarnedThisDoc = True
        msg = "Automatic re-wrapping stopped with an error: "
        msg = msg & CStr(errNum) & ": " & errDesc & vbCr & vbCr
        msg = msg & "It can be turned off in the settings."
        Report msg, vbExclamation
    End If
    mLastTableStart = nowStart
    Err.Clear
End Sub

' The interlinear table beginning at a known position, or Nothing if the
' position no longer holds one.
Private Function ExampleStartingAt(doc As Document, ByVal startPos As Long) As Table
    Dim tbl As Table
    On Error Resume Next
    For Each tbl In doc.Tables
        If tbl.Range.Start = startPos Then
            If IsInterlinearTable(tbl) Then Set ExampleStartingAt = tbl
            Exit Function
        End If
    Next tbl
    Err.Clear
End Function
