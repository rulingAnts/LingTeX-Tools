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

Public Sub Attach()
    Set mApp = Word.Application
    mLastTableStart = -1
End Sub

Public Sub Detach()
    Set mApp = Nothing
End Sub

'-----------------------------------------------------------------------------
' Re-wrap every example before the document is written out.
'
' The margins, the page size, the body font or the styles may all have changed
' since the examples were drawn, and this is the last moment to put that right.
' Failure is swallowed: a problem in the add-in must never stop a save.
'-----------------------------------------------------------------------------
Private Sub mApp_DocumentBeforeSave(ByVal Doc As Document, _
        SaveAsUI As Boolean, Cancel As Boolean)
    On Error Resume Next
    If gBusy Then Exit Sub
    If Doc Is Nothing Then Exit Sub
    If Not SettingRewrapOnSave(Doc) Then Exit Sub
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

    On Error Resume Next
    If gBusy Then Exit Sub
    If Sel Is Nothing Then Exit Sub
    Set doc = Sel.Document
    If doc Is Nothing Then Exit Sub

    Set tbl = FindExampleAt(Sel.Range)
    If tbl Is Nothing Then
        nowStart = -1
    Else
        nowStart = tbl.Range.Start
    End If

    ' Still in the same example: nothing to do.
    If nowStart = mLastTableStart And doc.Name = mLastDocName Then Exit Sub

    If SettingRewrapOnSelectionChange(doc) _
       And mLastTableStart >= 0 And doc.Name = mLastDocName Then
        ' We have just left the example that started at mLastTableStart.
        Set leaving = ExampleStartingAt(doc, mLastTableStart)
        If Not leaving Is Nothing Then
            gBusy = True
            Application.ScreenUpdating = False
            RewrapTable leaving
            Application.ScreenUpdating = True
            gBusy = False
            ReleaseScratch
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
