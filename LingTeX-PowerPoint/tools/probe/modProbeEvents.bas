Attribute VB_Name = "modProbeEvents"
Option Explicit

'=============================================================================
' modProbeEvents  --  LingTeX-PowerPoint
'
' PROBE ROUND 4: events and undo, the two things that need a person at the
' keyboard.  Run by run-in-powerpoint.sh, beside modLingTeXDev.
'
'   StartEventProbe   opens a presentation holding a text box to resize and
'                     starts logging application events (clsProbeEvents) to
'                     Events.<os>.txt.  First it resizes the box FROM CODE, so
'                     the log shows whether code fires the resize event too:
'                     a re-wrap started by that event resizes the box itself,
'                     and would otherwise start itself again.
'   StopEventProbe    stops logging.
'
'   UndoProbeMake     one macro run, six changes to one new shape: add it,
'                     colour it, move it, resize it, tag it, give it text.
'   UndoProbeUndo     asks PowerPoint to Undo once, from code (may not work on
'                     the Mac), then reports.
'   UndoProbeReport   writes Undo.<os>.txt: which of the six changes are still
'                     there.  After one Cmd+Z by hand, it shows whether one
'                     Undo takes back the whole macro or one change.
'
' Pure ASCII, and numbers instead of named constants, except where WithEvents
' needs a type (in the class).
'=============================================================================

Private mEvents As clsProbeEvents

Private Const SHAPE_RESIZE As String = "LingTeXResizeMe"
Private Const SHAPE_UNDO As String = "LingTeXUndoMe"

'-----------------------------------------------------------------------------
' Log lines, appended, with the time
'-----------------------------------------------------------------------------
Public Sub LogEvent(ByVal s As String)
    Dim fn As Integer
    On Error Resume Next
    fn = FreeFile
    Open DevReportPath("Events") For Append As #fn
    Print #fn, Format$(Now, "hh:nn:ss") & "  " & s
    Close #fn
End Sub

'-----------------------------------------------------------------------------
' Events
'-----------------------------------------------------------------------------
Public Sub StartEventProbe()
    Dim app As Object, pres As Object, sld As Object, shp As Object, fn As Integer
    Set app = Application
    On Error Resume Next
    Kill DevReportPath("Events")
    Err.Clear
    fn = FreeFile
    Open DevReportPath("Events") For Output As #fn
    Print #fn, "Event probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    Close #fn

    Set mEvents = New clsProbeEvents
    Set mEvents.App = Application
    If Err.Number <> 0 Then
        LogEvent "PROBLEM: the event object could not be attached (" & Err.Number & ": " & Err.Description & ")"
        Exit Sub
    End If
    LogEvent "-- listening"

    Set pres = app.Presentations.Add(-1)
    Set sld = pres.Slides.Add(1, 12)
    Set shp = sld.Shapes.AddTextbox(1, 100, 120, 500, 60)
    shp.Name = SHAPE_RESIZE
    shp.TextFrame2.TextRange.Text = "Drag my right-hand handle to make me narrower, then click outside me."
    shp.TextFrame2.TextRange.Font.Size = 24
    If Err.Number <> 0 Then
        LogEvent "PROBLEM: the test presentation could not be made (" & Err.Number & ": " & Err.Description & ")"
        Exit Sub
    End If
    LogEvent "-- code sets the box's width to 400 (a resize event just below means code fires it too)"
    shp.Width = 400
    LogEvent "-- code done; now over to the person at the keyboard"
End Sub

Public Sub StopEventProbe()
    LogEvent "-- stopped"
    Set mEvents = Nothing
End Sub

'-----------------------------------------------------------------------------
' Undo
'-----------------------------------------------------------------------------
Public Sub UndoProbeMake()
    Dim sld As Object, shp As Object
    On Error Resume Next
    Set sld = ProbeSlide()
    If sld Is Nothing Then
        WriteDevReport "Undo", "PROBLEM: no slide to work on (run StartEventProbe first)"
        Exit Sub
    End If
    DeleteShape sld, SHAPE_UNDO
    Set shp = sld.Shapes.AddShape(1, 100, 260, 120, 60)
    shp.Name = SHAPE_UNDO
    shp.Fill.ForeColor.RGB = RGB(200, 30, 30)
    shp.Left = 320
    shp.Width = 240
    shp.Tags.Add "LINGTEXSTEP", "tagged"
    shp.TextFrame2.TextRange.Text = "undo me"
    If Err.Number <> 0 Then
        WriteDevReport "Undo", "PROBLEM: making the changes: " & Err.Number & ": " & Err.Description
        Exit Sub
    End If
    UndoProbeReport
End Sub

Public Sub UndoProbeUndo()
    Dim app As Object, sld As Object, note As String
    Set app = Application
    On Error Resume Next
    ' Undo acts on the window in front, which might be the dev presentation or
    ' someone's own work: bring the probe's window forward first, or do nothing.
    Set sld = ProbeSlide()
    If sld Is Nothing Then
        UndoProbeReport "no probe slide, so no Undo was attempted"
        Exit Sub
    End If
    sld.Parent.Windows(1).Activate
    If Err.Number <> 0 Then
        UndoProbeReport "the probe's window could not be brought forward (" & Err.Description & "), so no Undo was attempted"
        Exit Sub
    End If
    If app.ActiveWindow.Presentation.FullName <> sld.Parent.FullName Then
        UndoProbeReport "another window stayed in front, so no Undo was attempted"
        Exit Sub
    End If
    app.CommandBars.ExecuteMso "Undo"
    If Err.Number <> 0 Then
        note = "ExecuteMso ""Undo"": ERROR " & Err.Number & ": " & Err.Description
    Else
        note = "ExecuteMso ""Undo"": no error"
    End If
    Err.Clear
    UndoProbeReport note
End Sub

Public Sub UndoProbeReport(Optional ByVal note As String = "")
    Dim sld As Object, shp As Object, s As String
    On Error Resume Next
    s = "Undo probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & vbLf
    If note <> "" Then s = s & note & vbLf
    Set sld = ProbeSlide()
    If sld Is Nothing Then
        WriteDevReport "Undo", s & "no probe slide"
        Exit Sub
    End If
    Set shp = sld.Shapes(SHAPE_UNDO)
    Err.Clear
    If shp Is Nothing Then
        s = s & "1 shape added:    NO (the whole macro was undone, if it was there before)" & vbLf
    Else
        s = s & "1 shape added:    yes" & vbLf
        s = s & "2 red fill:       " & IIf(shp.Fill.ForeColor.RGB = RGB(200, 30, 30), "yes", "no") & vbLf
        s = s & "3 moved to 320:   " & IIf(Abs(shp.Left - 320) < 0.5, "yes", "no (" & Format$(shp.Left, "0.0") & ")") & vbLf
        s = s & "4 width 240:      " & IIf(Abs(shp.Width - 240) < 0.5, "yes", "no (" & Format$(shp.Width, "0.0") & ")") & vbLf
        s = s & "5 tagged:         " & IIf(shp.Tags.Item("LINGTEXSTEP") = "tagged", "yes", "no") & vbLf
        s = s & "6 text 'undo me': " & IIf(shp.TextFrame2.TextRange.Text = "undo me", "yes", "no ('" & shp.TextFrame2.TextRange.Text & "')") & vbLf
    End If
    WriteDevReport "Undo", s
End Sub

' The slide StartEventProbe made: the first slide of an open presentation that
' holds the box to resize.
Private Function ProbeSlide() As Object
    Dim app As Object, p As Object, shp As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        Set shp = Nothing
        Set shp = p.Slides(1).Shapes(SHAPE_RESIZE)
        Err.Clear
        If Not shp Is Nothing Then
            Set ProbeSlide = p.Slides(1)
            Exit Function
        End If
    Next
End Function

Private Sub DeleteShape(ByVal sld As Object, ByVal nm As String)
    Dim shp As Object
    On Error Resume Next
    Set shp = sld.Shapes(nm)
    If Not shp Is Nothing Then shp.Delete
    Err.Clear
End Sub
