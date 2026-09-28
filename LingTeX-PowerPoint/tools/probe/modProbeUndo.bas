Attribute VB_Name = "modProbeUndo"
Option Explicit

'=============================================================================
' modProbeUndo  --  LingTeX-PowerPoint, probe round 8
'
' The undo count of a REAL Insert, measured from outside the object model.
'
' ProbeInsertUndo: a new presentation with a window, one blank slide, the
' clipboard as run-in-powerpoint.sh left it (the made-up FLEx copy), then
' LingTeXInsertInterlinear -- the command itself, not its parts. It writes
' InsertUndo.mac.txt with the shape count before and after.
'
' Then run-in-powerpoint.sh --undo-check reads the Edit menu, presses Cmd+Z
' ONCE, reads the menu again, and --after-undo ProbeInsertUndoAfter counts
' the shapes a second time and closes the presentation.
'
' One UI action = one undo entry means: the menu offered "Undo Paste", and
' after one Cmd+Z there is no LingTeX shape left on the slide.
'
' Pure ASCII; Chr$(10) between lines (vbCrLf is LF CR on Mac VBA).
'=============================================================================

Public Sub ProbeInsertUndo()
    Dim app As Object, pres As Object, sld As Object
    Dim nBefore As Long, nAfter As Long, s As String
    Set app = Application
    s = "Insert undo probe (round 8)  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    On Error GoTo Fail
    Set pres = app.Presentations.Add(-1)          ' with a window: the Edit menu is its
    Set sld = pres.Slides.Add(1, 12)              ' ppLayoutBlank
    pres.Windows(1).Activate
    nBefore = sld.Shapes.Count
    pres.Tags.Add "LINGTEX_PROBE_BEFORE", CStr(nBefore)
    s = s & "  " & pres.Name & ", slide 1 blank; shapes before: " & nBefore & Chr$(10)
    LingTeXInsertInterlinear
    nAfter = sld.Shapes.Count
    s = s & "  after LingTeXInsertInterlinear: shapes " & nAfter & " (" & (nAfter - nBefore) & " added)" & Chr$(10)
    If nAfter > nBefore Then
        s = s & "  the new shape is tagged as ours: " & IsLingTeXExample(sld.Shapes(nAfter)) & Chr$(10)
        s = s & "  its paragraphs: " & sld.Shapes(nAfter).TextFrame2.TextRange.Paragraphs.Count & Chr$(10)
    End If
    ' The editor's window, when open, is what "activate" brings forward, and
    ' its Edit menu is not the presentation's: hide it for the check.
    On Error Resume Next
    s = s & "  the VBA editor was visible: " & app.VBE.MainWindow.Visible & Chr$(10)
    app.VBE.MainWindow.Visible = False
    pres.Windows(1).Activate
    On Error GoTo Fail
    s = s & "  next: the rig reads the Edit menu, presses Cmd+Z once, then ProbeInsertUndoAfter counts again" & Chr$(10)
    WriteDevReport "InsertUndo", s
    Exit Sub
Fail:
    WriteDevReport "InsertUndo", s & "  ERR " & Err.Number & ": " & Err.Description & Chr$(10)
End Sub

'-----------------------------------------------------------------------------
' The control: the same, with one plain object-model write (AddShape) instead
' of the Insert. If the rig's one Undo removes this rectangle but not the
' pasted example, the paste is what is not on the undo stack; if it removes
' neither, a macro's writes are not undoable here at all.
'-----------------------------------------------------------------------------
Public Sub ProbeShapeUndo()
    Dim app As Object, pres As Object, sld As Object
    Dim nBefore As Long, s As String
    Set app = Application
    s = "Shape undo probe (round 8, the control)  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    On Error GoTo Fail
    Set pres = app.Presentations.Add(-1)
    Set sld = pres.Slides.Add(1, 12)
    pres.Windows(1).Activate
    nBefore = sld.Shapes.Count
    pres.Tags.Add "LINGTEX_PROBE_BEFORE", CStr(nBefore)
    sld.Shapes.AddShape 1, 100, 100, 200, 100       ' msoShapeRectangle
    s = s & "  " & pres.Name & ": shapes before " & nBefore & ", after AddShape " & sld.Shapes.Count & Chr$(10)
    On Error Resume Next
    app.VBE.MainWindow.Visible = False
    pres.Windows(1).Activate
    On Error GoTo Fail
    WriteDevReport "ShapeUndo", s
    Exit Sub
Fail:
    WriteDevReport "ShapeUndo", s & "  ERR " & Err.Number & ": " & Err.Description & Chr$(10)
End Sub

'-----------------------------------------------------------------------------
' Several object-model writes in ONE macro run: a slide, three rectangles, a
' text. If the rig's one Undo removes all of them, PowerPoint keeps one undo
' entry per macro run, not per write -- which decides how re-wrap must be
' built. Round 8's first Insert run hinted at it: one "Undo Last" took the
' slide the macro had added along with the pasted example (2026-09-28).
'-----------------------------------------------------------------------------
Public Sub ProbeManyWritesUndo()
    Dim app As Object, pres As Object, sld As Object, shp As Object
    Dim i As Long, s As String
    Set app = Application
    s = "Many-writes undo probe (round 8)  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    On Error GoTo Fail
    Set pres = app.Presentations.Add(-1)
    pres.Tags.Add "LINGTEX_PROBE_BEFORE", "0"
    pres.Tags.Add "LINGTEX_PROBE_SLIDES_BEFORE", CStr(pres.Slides.Count)
    s = s & "  " & pres.Name & ": slides before " & pres.Slides.Count & Chr$(10)
    Set sld = pres.Slides.Add(1, 12)
    pres.Windows(1).Activate
    For i = 1 To 3
        Set shp = sld.Shapes.AddShape(1, 60 + 120 * i, 100, 100, 60)
        shp.TextFrame2.TextRange.Text = "write " & (i + 1)
    Next i
    s = s & "  in one macro run: Slides.Add, then 3 x AddShape, each given a text -- 7 writes" & Chr$(10)
    s = s & "  now: slides " & pres.Slides.Count & ", shapes on slide 1: " & sld.Shapes.Count & Chr$(10)
    On Error Resume Next
    app.VBE.MainWindow.Visible = False
    pres.Windows(1).Activate
    On Error GoTo Fail
    WriteDevReport "ManyWritesUndo", s
    Exit Sub
Fail:
    WriteDevReport "ManyWritesUndo", s & "  ERR " & Err.Number & ": " & Err.Description & Chr$(10)
End Sub

Public Sub ProbeInsertUndoAfter()
    Dim app As Object, pres As Object, sld As Object
    Dim i As Long, ours As Long, s As String
    Set app = Application
    s = "Insert undo probe (round 8), after one Cmd+Z  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    On Error GoTo Fail
    Set pres = app.ActivePresentation
    s = s & "  " & pres.Name & ": slides " & pres.Slides.Count & Chr$(10)
    If pres.Slides.Count = 0 Then
        s = s & "  VERDICT: the one Undo removed the slide the macro added, and everything on it" & Chr$(10)
        s = s & "  -- the whole macro run was one undo entry" & Chr$(10)
        GoTo Done
    End If
    Set sld = pres.Slides(1)
    For i = 1 To sld.Shapes.Count
        If IsLingTeXExample(sld.Shapes(i)) Then ours = ours + 1
    Next i
    s = s & "  shapes on slide 1: " & sld.Shapes.Count & ", LingTeX examples among them: " & ours & Chr$(10)
    s = s & "  shapes before the write, per the presentation's tag: " & pres.Tags("LINGTEX_PROBE_BEFORE") & Chr$(10)
    If CStr(sld.Shapes.Count) = pres.Tags("LINGTEX_PROBE_BEFORE") Then
        s = s & "  VERDICT: the one Undo removed the whole write -- one UI action, one undo entry" & Chr$(10)
    Else
        s = s & "  VERDICT: the write is still there after the one Undo" & Chr$(10)
    End If
Done:
    WriteDevReport "InsertUndoAfter", s
    pres.Saved = -1
    pres.Close
    Exit Sub
Fail:
    WriteDevReport "InsertUndoAfter", s & "  ERR " & Err.Number & ": " & Err.Description & Chr$(10)
End Sub
