Attribute VB_Name = "modProbeEvents"
Option Explicit

'=============================================================================
' modProbeEvents  --  LingTeX-PowerPoint
'
' PROBE ROUND 4: events and undo, the two things that need a person at the
' keyboard.  Run by run-in-powerpoint.sh, beside modLingTeXDev.
'
' EVENTS
'   StartEventProbe   closes any earlier probe presentation, opens a new one
'                     (tagged LINGTEXPROBE) holding a text box to resize, and
'                     starts logging application events (clsProbeEvents).  It
'                     first resizes the box FROM CODE, so the log shows whether
'                     code fires the resize event too: a re-wrap started by
'                     that event resizes the box itself, and would otherwise
'                     start itself again.
'   StopEventProbe    stops logging, and says so plainly if listening had
'                     already stopped (a reset of the VBA project drops it).
'
'   The log is written live to Events.<os>.log, which the runner never deletes,
'   and copied to Events.<os>.txt, a report the runner collects, by
'   StartEventProbe and StopEventProbe.  BETWEEN StartEventProbe AND
'   StopEventProbe, RUN THE RUNNER ONLY WITH --no-import: an import removes this
'   module and the class, which ends listening.  Only events in the probe
'   presentation are described; events anywhere else are only counted, so
'   nothing about anyone's own presentations reaches a report.
'
' UNDO
'   UndoProbeMake     one macro run, six changes to one new shape: add it,
'                     colour it, move it, resize it, tag it, give it text.  It
'                     refuses to run while an earlier test shape is still there
'                     (deleting that in the same run would let one Undo bring
'                     the old, fully changed shape back, which reads as "nothing
'                     was undone"); UndoProbeReset clears it.  It records the
'                     new shape's Id outside the undo stack and brings the probe
'                     window forward, so a Cmd+Z by hand lands there.
'   UndoProbeReport   writes Undo.<os>.txt: which of the six changes are still
'                     there, on the shape UndoProbeMake made.
'   UndoProbeUndo     tries Undo from code.  Undo is a gallery control, which
'                     ExecuteMso is not documented to run on any platform, so an
'                     error here says nothing about the Mac: the answer is the
'                     Cmd+Z by hand.
'
' Pure ASCII, and numbers instead of named constants, except where WithEvents
' needs a type (in the class).
'=============================================================================

Private mEvents As clsProbeEvents
Private mOtherEvents As Long

Private Const SHAPE_RESIZE As String = "LingTeXResizeMe"
Private Const SHAPE_UNDO As String = "LingTeXUndoMe"
Private Const PROBE_TAG As String = "LINGTEXPROBE"

'-----------------------------------------------------------------------------
' Files.  <name>.<os>.log sits beside the reports but does not match the
' runner's *.<os>.txt clean-up, so it survives between runs.
'-----------------------------------------------------------------------------
Private Function LivePath(ByVal baseName As String) As String
    Dim p As String
    p = DevReportPath(baseName)
    LivePath = Left$(p, Len(p) - 4) & ".log"
End Function

Private Sub PublishEvents()
    On Error Resume Next
    Kill DevReportPath("Events")
    Err.Clear
    FileCopy LivePath("Events"), DevReportPath("Events")
End Sub

Public Sub LogEvent(ByVal s As String)
    Dim fn As Integer
    On Error Resume Next
    fn = FreeFile
    Open LivePath("Events") For Append As #fn
    Print #fn, Format$(Now, "hh:nn:ss") & "  " & s
    Close #fn
End Sub

' True for a presentation StartEventProbe made.
Public Function IsProbePresentation(ByVal pres As Object) As Boolean
    On Error Resume Next
    IsProbePresentation = (pres.Tags.Item(PROBE_TAG) = "1")
End Function

' An event in someone else's presentation: counted, never described.
Public Sub CountOtherEvent()
    mOtherEvents = mOtherEvents + 1
End Sub

'-----------------------------------------------------------------------------
' Events
'-----------------------------------------------------------------------------
Public Sub StartEventProbe()
    Dim app As Object, pres As Object, sld As Object, shp As Object
    Dim fn As Integer, i As Long
    Set app = Application
    On Error Resume Next

    ' One probe presentation at a time: earlier ones (unsaved, tagged) close.
    For i = app.Presentations.Count To 1 Step -1
        Set pres = app.Presentations(i)
        If IsProbePresentation(pres) And pres.Path = "" Then
            pres.Saved = -1
            pres.Close
        End If
        Err.Clear
    Next
    Set pres = Nothing

    Kill LivePath("Events")
    Err.Clear
    fn = FreeFile
    Open LivePath("Events") For Output As #fn
    Print #fn, "Event probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    Close #fn
    mOtherEvents = 0

    Set mEvents = New clsProbeEvents
    Set mEvents.App = Application
    If Err.Number <> 0 Then
        LogEvent "PROBLEM: the event object could not be attached (" & Err.Number & ": " & Err.Description & ")"
        PublishEvents
        Exit Sub
    End If

    Set pres = app.Presentations.Add(-1)
    pres.Tags.Add PROBE_TAG, "1"
    Set sld = pres.Slides.Add(1, 12)
    Set shp = sld.Shapes.AddTextbox(1, 100, 120, 500, 60)
    shp.Name = SHAPE_RESIZE
    shp.TextFrame2.TextRange.Text = "Drag my right-hand handle to make me narrower, then click outside me."
    shp.TextFrame2.TextRange.Font.Size = 24
    If Err.Number <> 0 Then
        LogEvent "PROBLEM: the test presentation could not be made (" & Err.Number & ": " & Err.Description & ")"
        PublishEvents
        Exit Sub
    End If
    LogEvent "-- listening; code now sets the box's width to 400 (a resize event just below means code fires it too)"
    shp.Width = 400
    LogEvent "-- code done; over to the person at the keyboard"
    PublishEvents
End Sub

' Between StartEventProbe and this, the runner must run with --no-import.
Public Sub StopEventProbe()
    If mEvents Is Nothing Then
        LogEvent "PROBLEM: not listening when StopEventProbe ran: the VBA project was reset (an import, that is a runner run without --no-import, or a run-time error) or StartEventProbe never ran; events after the reset are missing"
    Else
        LogEvent "-- stopped (listening until now); events in other presentations, counted but not described: " & mOtherEvents
    End If
    Set mEvents = Nothing
    PublishEvents
End Sub

'-----------------------------------------------------------------------------
' Undo
'-----------------------------------------------------------------------------
Public Sub UndoProbeMake()
    Dim sld As Object, shp As Object, old As Object, fn As Integer
    On Error Resume Next
    Set sld = ProbeSlide()
    If sld Is Nothing Then
        WriteDevReport "Undo", "PROBLEM: no probe slide (run StartEventProbe first)"
        Exit Sub
    End If
    Set old = sld.Shapes(SHAPE_UNDO)
    Err.Clear
    If Not old Is Nothing Then
        WriteDevReport "Undo", "PROBLEM: an earlier " & SHAPE_UNDO & " is still on the probe slide. Run UndoProbeReset (or delete it by hand), then UndoProbeMake again."
        Exit Sub
    End If

    ' ---- the measured run: six changes in one macro ----
    Set shp = sld.Shapes.AddShape(1, 100, 260, 120, 60)
    shp.Name = SHAPE_UNDO
    shp.Fill.ForeColor.RGB = RGB(200, 30, 30)
    shp.Left = 320
    shp.Width = 240
    shp.Tags.Add "LINGTEXSTEP", "tagged"
    shp.TextFrame2.TextRange.Text = "undo me"
    ' -----------------------------------------------------
    If Err.Number <> 0 Then
        WriteDevReport "Undo", "PROBLEM: making the changes: " & Err.Number & ": " & Err.Description
        Exit Sub
    End If

    ' Which shape this run made, kept outside the undo stack.
    fn = FreeFile
    Open LivePath("UndoId") For Output As #fn
    Print #fn, CStr(shp.Id)
    Close #fn
    Err.Clear

    sld.Parent.Windows(1).Activate
    UndoProbeReport "made by UndoProbeMake: now press Cmd+Z once in the probe window, then run UndoProbeReport"
End Sub

Public Sub UndoProbeReset()
    Dim sld As Object
    On Error Resume Next
    Set sld = ProbeSlide()
    If Not sld Is Nothing Then DeleteShape sld, SHAPE_UNDO
    Kill LivePath("UndoId")
    Err.Clear
    UndoProbeReport "reset: the test shape was deleted"
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
        note = "ExecuteMso ""Undo"": ERROR " & Err.Number & ": " & Err.Description & _
               " (Undo is a gallery control, which ExecuteMso is not documented to run on any platform: this says nothing about the Mac)"
    Else
        note = "ExecuteMso ""Undo"": no error"
    End If
    Err.Clear
    UndoProbeReport note
End Sub

Public Sub UndoProbeReport(Optional ByVal note As String = "")
    Dim sld As Object, shp As Object, s As String, madeId As String, fn As Integer
    On Error Resume Next
    s = "Undo probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & vbLf
    If note <> "" Then s = s & note & vbLf
    Set sld = ProbeSlide()
    If sld Is Nothing Then
        WriteDevReport "Undo", s & "PROBLEM: no probe slide"
        Exit Sub
    End If
    s = s & "probe presentations open: " & ProbeCount() & vbLf

    fn = FreeFile
    Open LivePath("UndoId") For Input As #fn
    If Err.Number = 0 Then
        Line Input #fn, madeId
        Close #fn
    End If
    Err.Clear
    madeId = Trim$(madeId)

    Set shp = sld.Shapes(SHAPE_UNDO)
    Err.Clear
    If shp Is Nothing Then
        s = s & "1 shape added:    NO, gone"
        If madeId <> "" Then s = s & " (UndoProbeMake made Id " & madeId & ")"
        s = s & vbLf
    Else
        s = s & "1 shape added:    yes, Id " & shp.Id
        If madeId <> "" And CStr(shp.Id) <> madeId Then s = s & "  -- NOT the shape UndoProbeMake made (" & madeId & ")"
        s = s & vbLf
        s = s & "2 red fill:       " & YesNo(shp.Fill.ForeColor.RGB = RGB(200, 30, 30)) & vbLf
        s = s & "3 moved to 320:   " & YesNo(Abs(shp.Left - 320) < 0.5) & "  (left " & Format$(shp.Left, "0.0") & ")" & vbLf
        s = s & "4 width 240:      " & YesNo(Abs(shp.Width - 240) < 0.5) & "  (width " & Format$(shp.Width, "0.0") & ")" & vbLf
        s = s & "5 tagged:         " & YesNo(shp.Tags.Item("LINGTEXSTEP") = "tagged") & vbLf
        s = s & "6 text 'undo me': " & YesNo(shp.TextFrame2.TextRange.Text = "undo me") & "  (text '" & shp.TextFrame2.TextRange.Text & "')" & vbLf
    End If
    WriteDevReport "Undo", s
End Sub

Private Function YesNo(ByVal b As Boolean) As String
    If b Then YesNo = "yes" Else YesNo = "no"
End Function

' The first slide of the probe presentation (tagged by StartEventProbe).
Private Function ProbeSlide() As Object
    Dim app As Object, p As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        If IsProbePresentation(p) Then
            Set ProbeSlide = p.Slides(1)
            Exit Function
        End If
    Next
End Function

Private Function ProbeCount() As Long
    Dim app As Object, p As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        If IsProbePresentation(p) Then ProbeCount = ProbeCount + 1
    Next
End Function

Private Sub DeleteShape(ByVal sld As Object, ByVal nm As String)
    Dim shp As Object
    On Error Resume Next
    Set shp = sld.Shapes(nm)
    If Not shp Is Nothing Then shp.Delete
    Err.Clear
End Sub
