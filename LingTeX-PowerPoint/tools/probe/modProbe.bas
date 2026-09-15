Attribute VB_Name = "modProbe"
Option Explicit

'=============================================================================
' modProbe  --  LingTeX-PowerPoint
'
' ONE PASTE, ONE REPORT.  Probes PowerPoint's object model for what a
' PowerPoint version of LingTeX-Word would rest on, before any of it is built.
' Self-contained: nothing else is needed.
'
' ---------------------------------------------------------------------------
' WHAT IT ANSWERS
'
'   2  Can measuring happen out of sight, in a presentation with no window?
'   3  Can text be measured?  TextRange2.BoundWidth in a text box that does not
'      wrap and fits its text: does it scale with the text, and how fast is it?
'   4  Do small capitals render, and how wide are they?
'   5  THE DESIGN QUESTION.  In one text box, do paragraphs with the same tab
'      stops start their columns at the same x, and can each paragraph keep
'      stops of its own?  If so, one text box can hold a whole example: each
'      wrap line is a few paragraphs (one per tier) with that line's stops.
'   6  How many tab stops a paragraph holds.
'   7  What a tab line wider than a wrapping box does.
'   8  Whether indents make a hanging number column.
'   9  Reading clipboard text: Shapes.Paste, and a windowed View.PasteSpecial
'      (Shapes.PasteSpecial is not supported: round 1).  Tabs, line breaks,
'      and letters beyond ASCII.
'  10  Whether Tags survive Duplicate and Copy + Paste; how long a tag can be.
'  11  The fallback design: grouped text boxes with an invisible frame, and
'      what resizing the group does to them.
'  12  Why not a table: whether rows can differ in column width, and whether
'      a table can be grouped with another shape.
'  13  Whether VBA may see its own project (a build that imports its modules).
'  14  Which add-ins are loaded, and whether PowerPoint may write to Office's
'      Startup folder for PowerPoint.
'
' Events -- a re-wrap after the frame is resized -- need a class module, so
' they are a second, later probe.
'
' ---------------------------------------------------------------------------
' WHAT A VERDICT MEANS
'
' USABLE / CHECK / BLOCKED describe THIS machine in ITS current state, never
' the platform.  LingTeX-Word's probe once reported BLOCKED for a setting that
' had simply not been ticked, and it got written down as "the Mac cannot".
'
' ---------------------------------------------------------------------------
' HOW TO RUN
'
'   1. In PowerPoint, make a new blank presentation.
'   2. Tools > Macro > Visual Basic Editor (Mac), or Alt+F11 (Windows).
'   3. Insert > Module, and paste everything EXCEPT the first line
'      ("Attribute VB_Name = ...": the importer reads it; typed in, it is a
'      compile error).
'   4. View > Immediate Window, type  ProbePowerPoint  and press Return.
'   5. A dialog says where the report went; it is also printed in the
'      Immediate window.  Nothing needs saving: close the presentation.
'
' It works in a scratch presentation of its own and closes it.  It DOES use
' the clipboard: section 9 first reads whatever is on it (after step 3, this
' module's own text, pasted in from another application -- which is why the
' next line holds two tab characters), then copies and pastes a sample of its
' own, and section 10 copies a shape.
'
' TAB TEST:	a	b
'
' Pure ASCII, and numbers instead of named constants: a constant missing from
' Mac PowerPoint's type library is a compile error for the whole module.
' Application members are reached through Object for the same reason.
'=============================================================================

Private mRpt As String
Private mPres As Object
Private mSld As Object

Private Const TB As String = vbTab

'-----------------------------------------------------------------------------
' Entry points
'-----------------------------------------------------------------------------
Public Sub ProbePowerPoint()
    RunProbe
    MsgBox "LingTeX-PowerPoint probe finished." & vbCr & vbCr & DeliverReport(), _
           vbInformation, "LingTeX-PowerPoint probe"
End Sub

' The same with no dialog, for a script that runs the macro and reads the file.
Public Sub ProbePowerPointQuiet()
    RunProbe
    DeliverReport
End Sub

Private Sub RunProbe()
    mRpt = ""
    Say "LingTeX-PowerPoint probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    ProbeEnvironment
    If OpenScratch(False) Then
        If Not ProbeMeasure() Then
            Say "CHECK: nothing measured in a presentation with no window; again, with one"
            CloseScratch
            If Not OpenScratch(True) Then GoTo AfterScratch
            ProbeMeasure
        End If
        ProbeSmallCaps
        ProbeTabStops
        ProbeTabStopLimit
        ProbeWrapOverflow
        ProbeIndents
        ProbeClipboardText
        ProbeTags
        ProbeGroups
        ProbeTables
        CloseScratch
    End If
AfterScratch:
    ProbeVBProject
    ProbeAddIns
    Say ""
    Say "== end"
End Sub

'-----------------------------------------------------------------------------
' Report
'-----------------------------------------------------------------------------
Private Sub Say(ByVal s As String)
    mRpt = mRpt & s & vbLf
End Sub

Private Sub Heading(ByVal title As String)
    Say ""
    Say "== " & title
End Sub

Private Sub SayError(ByVal what As String)
    Say "ERROR " & Err.Number & " (" & what & "): " & Err.Description
    Err.Clear
End Sub

Private Function N2(ByVal v As Variant) As String
    N2 = Format$(v, "0.0")
End Function

Private Function Escape(ByVal s As String) As String
    s = Replace(s, vbTab, "\t")
    s = Replace(s, vbCr, "\r")
    s = Replace(s, vbLf, "\n")
    s = Replace(s, Chr$(11), "\v")
    Dim i As Long, ch As String, out As String
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If AscW(ch) > 126 Or AscW(ch) < 0 Then
            out = out & "\u" & Hex$(AscW(ch) And &HFFFF&)
        Else
            out = out & ch
        End If
    Next
    Escape = out
End Function

Private Function CountOf(ByVal s As String, ByVal what As String) As Long
    If Len(s) = 0 Then Exit Function
    CountOf = (Len(s) - Len(Replace(s, what, ""))) \ Len(what)
End Function

' The report goes to the Immediate window and to a file in the Documents folder
' PowerPoint itself may write to (on the Mac, inside its sandbox, so no access
' prompt can block a script that runs this).
Private Function DeliverReport() As String
    Dim home As String, sep As String, p As String, fn As Integer
    Debug.Print mRpt
#If Mac Then
    sep = "/"
#Else
    sep = "\"
#End If
    home = Environ$("HOME")
    If home = "" Then home = Environ$("USERPROFILE")
    On Error Resume Next
    MkDir home & sep & "Documents" & sep & "LingTeX-PowerPoint-reports"
    Err.Clear
#If Mac Then
    p = home & sep & "Documents" & sep & "LingTeX-PowerPoint-reports" & sep & "Probe.mac.txt"
#Else
    p = home & sep & "Documents" & sep & "LingTeX-PowerPoint-reports" & sep & "Probe.win.txt"
#End If
    fn = FreeFile
    Open p For Output As #fn
    If Err.Number <> 0 Then
        Err.Clear
        p = home & sep & "Documents" & sep & "LingTeX-PowerPoint-probe.txt"
        fn = FreeFile
        Open p For Output As #fn
    End If
    If Err.Number = 0 Then
        Print #fn, mRpt;
        Close #fn
    End If
    If Err.Number = 0 Then
        DeliverReport = "The report is saved in" & vbCr & p & vbCr & vbCr & _
                        "and printed in the VBA editor's Immediate window."
    Else
        DeliverReport = "The report could not be saved (" & Err.Description & _
                        "). It is in the VBA editor's Immediate window."
    End If
End Function

'-----------------------------------------------------------------------------
' Scratch presentation and text boxes
'-----------------------------------------------------------------------------
Private Function OpenScratch(ByVal withWindow As Boolean) As Boolean
    Dim app As Object
    Set app = Application
    Heading "2. A scratch presentation" & IIf(withWindow, " (with a window)", "")
    Set mPres = Nothing
    Set mSld = Nothing
    On Error Resume Next
    If withWindow Then
        Set mPres = app.Presentations.Add(-1)
    Else
        Set mPres = app.Presentations.Add(0)
    End If
    If Err.Number <> 0 Or mPres Is Nothing Then
        SayError "Presentations.Add(WithWindow:=" & withWindow & ")"
        If withWindow Then Exit Function
        Set mPres = app.Presentations.Add(-1)
        If mPres Is Nothing Then SayError "Presentations.Add()": Exit Function
        Say "CHECK: only a presentation with a window could be made"
    ElseIf Not withWindow Then
        Say "USABLE: Presentations.Add(WithWindow:=False)"
    End If
    Set mSld = mPres.Slides.Add(1, 12)
    If mSld Is Nothing Then
        SayError "Slides.Add(1, ppLayoutBlank)"
        Set mSld = mPres.Slides.AddSlide(1, mPres.SlideMaster.CustomLayouts(1))
    End If
    If mSld Is Nothing Then SayError "Slides.AddSlide": Exit Function
    Say "slide " & mPres.PageSetup.SlideWidth & " x " & mPres.PageSetup.SlideHeight & " pt"
    OpenScratch = True
End Function

Private Sub CloseScratch()
    On Error Resume Next
    mPres.Saved = -1
    mPres.Close
    Set mSld = Nothing
    Set mPres = Nothing
End Sub

' A text box on the scratch slide, no inner margins, Times New Roman.
' wrap False: one line, and the box fits the text (what measuring needs).
' wrap True: the width stays as given and the height grows.
Private Function NewBox(ByVal txt As String, ByVal size As Single, _
        Optional ByVal wrap As Boolean = False, Optional ByVal w As Single = 600) As Object
    Dim shp As Object
    Set shp = mSld.Shapes.AddTextbox(1, 20, 20, w, 40)
    With shp.TextFrame2
        .MarginLeft = 0
        .MarginRight = 0
        .MarginTop = 0
        .MarginBottom = 0
        If wrap Then .WordWrap = -1 Else .WordWrap = 0
        .AutoSize = 1
        .TextRange.Text = txt
        .TextRange.Font.Name = "Times New Roman"
        .TextRange.Font.Size = size
    End With
    Set NewBox = shp
End Function

'-----------------------------------------------------------------------------
' 1. Environment
'-----------------------------------------------------------------------------
Private Sub ProbeEnvironment()
    Dim app As Object
    Set app = Application
    Heading "1. Environment"
    On Error Resume Next
    Say "PowerPoint " & app.Version
    If Err.Number <> 0 Then SayError "Version"
    Say "build " & app.Build
    If Err.Number <> 0 Then SayError "Build"
    Say "OS " & app.OperatingSystem
    If Err.Number <> 0 Then SayError "OperatingSystem"
    Say "HOME " & Environ$("HOME") & "   USERPROFILE " & Environ$("USERPROFILE")
End Sub

'-----------------------------------------------------------------------------
' 3. Measuring. True when something measured wider than nothing.
'-----------------------------------------------------------------------------
Private Function ProbeMeasure() As Boolean
    Dim a As Object, b As Object, c As Object, d As Object
    Dim i As Long, t As Single, total As Double
    Heading "3. Measuring text: TextRange2.BoundWidth, one line, the box fits the text"
    On Error GoTo Fail
    Set a = NewBox("W", 20)
    Set b = NewBox("WWWW", 20)
    Set c = NewBox("WWWW", 40)
    Set d = NewBox("neighbor-F buy-PST.3PL", 20)
    Say "'W' at 20pt: " & N2(a.TextFrame2.TextRange.BoundWidth) & "   (the box is " & N2(a.Width) & " wide)"
    Say "'WWWW' at 20pt: " & N2(b.TextFrame2.TextRange.BoundWidth) & _
        "   four times 'W': " & N2(4 * a.TextFrame2.TextRange.BoundWidth)
    Say "'WWWW' at 40pt: " & N2(c.TextFrame2.TextRange.BoundWidth) & _
        "   twice the 20pt width: " & N2(2 * b.TextFrame2.TextRange.BoundWidth)
    Say "'neighbor-F buy-PST.3PL': " & N2(d.TextFrame2.TextRange.BoundWidth) & _
        "   its second word alone, Characters(12, 11): " & _
        N2(d.TextFrame2.TextRange.Characters(12, 11).BoundWidth) & _
        " starting at x " & N2(d.TextFrame2.TextRange.Characters(12, 11).BoundLeft - d.Left)
    Say "which width is the text's: 'neighbor-F' whole range " & NewBoxWidths("neighbor-F", 20)
    Say "  at 40pt: " & NewBoxWidths("neighbor-F", 40)
    ProbeMeasure = (a.TextFrame2.TextRange.BoundWidth > 0)
    t = Timer
    For i = 1 To 200
        a.TextFrame2.TextRange.Text = "gloss" & i
        total = total + a.TextFrame2.TextRange.BoundWidth
    Next
    Say "200 measurements (set the text, read the width): " & Format$(Timer - t, "0.00") & " s"
Tidy:
    On Error Resume Next
    a.Delete
    b.Delete
    c.Delete
    d.Delete
    Exit Function
Fail:
    SayError "measuring"
    Resume Tidy
End Function

' "whole-range BoundWidth / Characters(1, n).BoundWidth / fitted box width" for
' one string: round 1 found the first about a quarter em wider than the text.
Private Function NewBoxWidths(ByVal txt As String, ByVal size As Single) As String
    Dim shp As Object, tr As Object
    Set shp = NewBox(txt, size)
    Set tr = shp.TextFrame2.TextRange
    NewBoxWidths = N2(tr.BoundWidth) & " / chars " & N2(tr.Characters(1, Len(txt)).BoundWidth) & _
                   " / box " & N2(shp.Width) & " / last char right edge " & _
                   N2(tr.Characters(Len(txt), 1).BoundLeft + tr.Characters(Len(txt), 1).BoundWidth - shp.Left)
    shp.Delete
End Function

'-----------------------------------------------------------------------------
' 4. Small capitals
'-----------------------------------------------------------------------------
Private Sub ProbeSmallCaps()
    Dim lo As Object, sc As Object, up As Object
    Dim wLo As Single, wSc As Single, wUp As Single
    Heading "4. Small capitals: Font2.Smallcaps"
    On Error GoTo Fail
    Set lo = NewBox("def.m.pl", 20)
    Set sc = NewBox("def.m.pl", 20)
    Set up = NewBox("DEF.M.PL", 20)
    sc.TextFrame2.TextRange.Font.Smallcaps = -1
    wLo = lo.TextFrame2.TextRange.BoundWidth
    wSc = sc.TextFrame2.TextRange.BoundWidth
    wUp = up.TextFrame2.TextRange.BoundWidth
    Say "lower case " & N2(wLo) & "   small caps " & N2(wSc) & "   capitals " & N2(wUp) & _
        "   (Smallcaps reads back " & sc.TextFrame2.TextRange.Font.Smallcaps & ")"
    If wSc > wLo And wSc < wUp Then
        Say "USABLE: small capitals are measured between lower case and capitals"
    Else
        Say "CHECK: small capitals did not measure between lower case and capitals"
    End If
Tidy:
    On Error Resume Next
    lo.Delete
    sc.Delete
    up.Delete
    Exit Sub
Fail:
    SayError "small caps"
    Resume Tidy
End Sub

'-----------------------------------------------------------------------------
' 5. Tab stops per paragraph
'-----------------------------------------------------------------------------
Private Sub ProbeTabStops()
    Dim shp As Object, tr As Object, i As Long
    Dim lefts(1 To 4) As String
    Heading "5. Tab stops per paragraph (the one-text-box design)"
    On Error GoTo Fail
    Set shp = NewBox("Los" & TB & "ninos" & TB & "de" & TB & "mi" & vbCr & _
                     "DEF.M.PL" & TB & "child-M-PL" & TB & "of" & TB & "1SG.POSS" & vbCr & _
                     "vecina" & TB & "compraron" & TB & "pan" & vbCr & _
                     "WWWWWWWW" & TB & "past its stop", 20)
    Set tr = shp.TextFrame2.TextRange
    Say "paragraphs: " & tr.Paragraphs.Count & " (4 expected)"
    AddStops tr.Paragraphs(1), Array(110, 230, 280)
    AddStops tr.Paragraphs(2), Array(110, 230, 280)
    AddStops tr.Paragraphs(3), Array(80, 190)
    AddStops tr.Paragraphs(4), Array(50, 300)
    For i = 1 To 4
        lefts(i) = ColumnLefts(tr.Paragraphs(i), shp.Left)
        Say "p" & i & " stops " & StopList(tr.Paragraphs(i)) & "   columns start at " & lefts(i)
    Next
    If lefts(1) = lefts(2) Then
        Say "USABLE: two paragraphs with the same stops start their columns at the same x"
    Else
        Say "CHECK: the same stops gave different column starts"
    End If
    If lefts(3) <> lefts(1) Then
        Say "USABLE: a paragraph keeps stops of its own (p3 differs from p1)"
    Else
        Say "CHECK: p3 came out like p1, so stops may apply to the whole box"
    End If
    Say "p4 is wider than its first stop (50): its second column shows where a tab goes then"
Tidy:
    On Error Resume Next
    shp.Delete
    Exit Sub
Fail:
    SayError "tab stops"
    Resume Tidy
End Sub

Private Sub AddStops(ByVal para As Object, ByVal stops As Variant)
    Dim i As Long
    For i = LBound(stops) To UBound(stops)
        para.ParagraphFormat.TabStops.Add 1, CSng(stops(i))
    Next
End Sub

Private Function StopList(ByVal para As Object) As String
    Dim i As Long, s As String
    With para.ParagraphFormat.TabStops
        For i = 1 To .Count
            If i > 1 Then s = s & ","
            s = s & N2(.Item(i).Position)
        Next
    End With
    StopList = "[" & s & "]"
End Function

' The x of each column's first character, measured from the box's left edge.
Private Function ColumnLefts(ByVal para As Object, ByVal boxLeft As Single) As String
    Dim txt As String, i As Long, s As String
    txt = para.Text
    s = N2(para.Characters(1, 1).BoundLeft - boxLeft)
    For i = 1 To Len(txt) - 1
        If Mid$(txt, i, 1) = vbTab Then
            s = s & "," & N2(para.Characters(i + 1, 1).BoundLeft - boxLeft)
        End If
    Next
    ColumnLefts = s
End Function

'-----------------------------------------------------------------------------
' 6. How many tab stops
'-----------------------------------------------------------------------------
Private Sub ProbeTabStopLimit()
    Dim shp As Object, para As Object, i As Long
    Heading "6. How many tab stops one paragraph holds"
    On Error Resume Next
    Set shp = NewBox("x", 12, True, 600)
    Set para = shp.TextFrame2.TextRange.Paragraphs(1)
    For i = 1 To 60
        para.ParagraphFormat.TabStops.Add 1, CSng(i * 9)
        If Err.Number <> 0 Then SayError "adding stop " & i: Exit For
    Next
    Say "stops held: " & para.ParagraphFormat.TabStops.Count & " (up to 60 asked for)"
    shp.Delete
End Sub

'-----------------------------------------------------------------------------
' 7. A tab line wider than a wrapping box
'-----------------------------------------------------------------------------
Private Sub ProbeWrapOverflow()
    Dim shp As Object, tr As Object, i As Long, s As String
    Heading "7. A tab line wider than a box that wraps"
    On Error GoTo Fail
    Set shp = NewBox("aaaa" & TB & "bbbb" & TB & "cccc" & TB & "dddd" & TB & "eeee", 20, True, 150)
    Set tr = shp.TextFrame2.TextRange
    AddStops tr.Paragraphs(1), Array(60, 120, 180, 240)
    Say "box " & N2(shp.Width) & " wide (150 asked), " & N2(shp.Height) & " high, " & tr.Lines.Count & " line(s)"
    For i = 1 To tr.Lines.Count
        If i > 1 Then s = s & "  |  "
        s = s & "'" & Escape(tr.Lines(i).Text) & "' at x " & _
            N2(tr.Lines(i).Characters(1, 1).BoundLeft - shp.Left)
    Next
    Say s
Tidy:
    On Error Resume Next
    shp.Delete
    Exit Sub
Fail:
    SayError "wrapping"
    Resume Tidy
End Sub

'-----------------------------------------------------------------------------
' 8. Indents
'-----------------------------------------------------------------------------
Private Sub ProbeIndents()
    Dim shp As Object, tr As Object
    Heading "8. Indents: a hanging number column"
    On Error GoTo Fail
    Set shp = NewBox("(1)" & TB & "Los" & TB & "ninos" & vbCr & "DEF.M.PL" & TB & "child-M-PL", 20)
    Set tr = shp.TextFrame2.TextRange
    With tr.Paragraphs(1).ParagraphFormat
        .LeftIndent = 40
        .FirstLineIndent = -40
    End With
    tr.Paragraphs(2).ParagraphFormat.LeftIndent = 40
    AddStops tr.Paragraphs(1), Array(40, 150)
    AddStops tr.Paragraphs(2), Array(150)
    Say "p1 indent " & N2(tr.Paragraphs(1).ParagraphFormat.LeftIndent) & _
        ", first line " & N2(tr.Paragraphs(1).ParagraphFormat.FirstLineIndent) & _
        "   columns start at " & ColumnLefts(tr.Paragraphs(1), shp.Left)
    Say "p2 indent " & N2(tr.Paragraphs(2).ParagraphFormat.LeftIndent) & _
        "   columns start at " & ColumnLefts(tr.Paragraphs(2), shp.Left)
    Say "wanted: p1 at 0,40,150 and p2 at 40,150"
Tidy:
    On Error Resume Next
    shp.Delete
    Exit Sub
Fail:
    SayError "indents"
    Resume Tidy
End Sub

'-----------------------------------------------------------------------------
' 9. Clipboard text
'-----------------------------------------------------------------------------
Private Sub ProbeClipboardText()
    Dim sr As Object, src As Object, got As String, sample As String
    Dim app As Object, wp As Object, ws As Object, n As Long
    Set app = Application
    Heading "9. Clipboard text"
    On Error Resume Next
    ' a. Whatever is on the clipboard now (run-in-powerpoint.sh puts a
    '    FLEx-shaped sample there), with Shapes.Paste on the scratch slide.
    Set sr = mSld.Shapes.Paste
    If Err.Number <> 0 Then
        SayError "Shapes.Paste of the current clipboard"
    Else
        got = sr.Item(1).TextFrame2.TextRange.Text
        If Err.Number <> 0 Then
            SayError "reading the pasted shape's text (type " & sr.Item(1).Type & ")"
        Else
            Say "Shapes.Paste: " & ClipSummary(got)
        End If
        sr.Delete
        Set sr = Nothing
    End If
    Err.Clear
    ' b. The same clipboard through a window's View.PasteSpecial, as text.
    Set wp = app.Presentations.Add(-1)
    If Err.Number <> 0 Then
        SayError "a windowed presentation"
    Else
        Set ws = wp.Slides.Add(1, 12)
        wp.Windows(1).Activate
        wp.Windows(1).View.GotoSlide 1
        n = ws.Shapes.Count
        wp.Windows(1).View.PasteSpecial 2
        If Err.Number <> 0 Then
            SayError "View.PasteSpecial(ppPasteText)"
        ElseIf ws.Shapes.Count = n Then
            Say "View.PasteSpecial(ppPasteText): no error, but nothing was pasted"
        Else
            got = ws.Shapes(ws.Shapes.Count).TextFrame2.TextRange.Text
            Say "View.PasteSpecial(ppPasteText): " & ClipSummary(got)
        End If
        Err.Clear
        wp.Saved = -1
        wp.Close
    End If
    Err.Clear
    ' c. A round trip: text copied from a text box, pasted with Shapes.Paste.
    sample = "Word" & TB & "Los" & TB & "ninos" & vbCr & _
             "Morphemes" & TB & "Los" & TB & "nin" & TB & "-o" & TB & "-s" & vbCr & _
             "Free" & TB & "The children."
    Set src = NewBox(sample, 12)
    src.TextFrame2.TextRange.Copy
    If Err.Number <> 0 Then SayError "copying the sample": GoTo Tidy
    Set sr = mSld.Shapes.Paste
    If Err.Number <> 0 Then SayError "Shapes.Paste of the sample": GoTo Tidy
    got = sr.Item(1).TextFrame2.TextRange.Text
    If got = sample Then
        Say "round trip (Copy, Shapes.Paste): IDENTICAL"
    Else
        Say "round trip (Copy, Shapes.Paste): DIFFERENT -- got " & Escape(got)
    End If
Tidy:
    On Error Resume Next
    src.Delete
    sr.Delete
End Sub

Private Function ClipSummary(ByVal got As String) As String
    ClipSummary = Len(got) & " characters; tabs " & CountOf(got, vbTab) & ", CR " & CountOf(got, vbCr) & _
                  ", LF " & CountOf(got, vbLf) & ", VT " & CountOf(got, Chr$(11)) & _
                  "   " & Escape(Left$(got, 90))
End Function

'-----------------------------------------------------------------------------
' 10. Tags
'-----------------------------------------------------------------------------
Private Sub ProbeTags()
    Dim shp As Object, dup As Object, pasted As Object
    Heading "10. Tags: set, Duplicate, Copy + Paste, a long value"
    On Error Resume Next
    Set shp = NewBox("tagged", 20)
    shp.Tags.Add "LingTeX", "example v1"
    If Err.Number <> 0 Then SayError "Tags.Add": GoTo Tidy
    Say "set: LINGTEX = '" & shp.Tags.Item("LINGTEX") & "' (" & shp.Tags.Count & " tag)"
    Set dup = shp.Duplicate.Item(1)
    If Err.Number <> 0 Then
        SayError "Duplicate"
    Else
        Say "Duplicate keeps it: '" & dup.Tags.Item("LINGTEX") & "'"
    End If
    shp.Copy
    If Err.Number <> 0 Then SayError "Copy"
    Set pasted = mSld.Shapes.Paste.Item(1)
    If Err.Number <> 0 Then
        SayError "Shapes.Paste"
    Else
        Say "Copy + Paste keeps it: '" & pasted.Tags.Item("LINGTEX") & "'"
    End If
    shp.Tags.Add "LingTeXBig", String$(20000, "x")
    If Err.Number <> 0 Then
        SayError "a 20,000-character tag"
    Else
        Say "a 20,000-character tag reads back as " & Len(shp.Tags.Item("LINGTEXBIG")) & " characters"
    End If
Tidy:
    On Error Resume Next
    shp.Delete
    dup.Delete
    pasted.Delete
End Sub

'-----------------------------------------------------------------------------
' 11. Grouped text boxes in an invisible frame
'-----------------------------------------------------------------------------
Private Sub ProbeGroups()
    Dim a As Object, b As Object, fr As Object, g As Object
    Dim nmA As String, nmB As String, nmF As String
    Heading "11. The fallback design: grouped text boxes in an invisible frame"
    On Error GoTo Fail
    Set a = NewBox("Los", 20)
    Set b = NewBox("DEF.M.PL", 20)
    b.Top = a.Top + 30
    Set fr = mSld.Shapes.AddShape(1, 20, 20, 300, 80)
    fr.Fill.Visible = 0
    fr.Line.Visible = 0
    nmA = a.Name
    nmB = b.Name
    nmF = fr.Name
    Set g = mSld.Shapes.Range(Array(nmA, nmB, nmF)).Group
    Say "grouped " & g.GroupItems.Count & " shapes; the group is " & N2(g.Width) & " wide (the frame, 300)"
    g.Tags.Add "LingTeX", "group"
    g.Width = 150
    Say "group.Width = 150: frame " & N2(g.GroupItems.Item(nmF).Width) & _
        ", text box " & N2(g.GroupItems.Item(nmB).Width) & " wide, its font " & _
        g.GroupItems.Item(nmB).TextFrame2.TextRange.Font.Size & "pt (20 before)"
    g.GroupItems.Item(nmA).TextFrame2.TextRange.Text = "Las"
    Say "a grouped box's text can be set: '" & g.GroupItems.Item(nmA).TextFrame2.TextRange.Text & _
        "'; the group's tag reads '" & g.Tags.Item("LINGTEX") & "'"
Tidy:
    On Error Resume Next
    g.Delete
    a.Delete
    b.Delete
    fr.Delete
    Exit Sub
Fail:
    SayError "groups"
    Resume Tidy
End Sub

'-----------------------------------------------------------------------------
' 12. Tables
'-----------------------------------------------------------------------------
Private Sub ProbeTables()
    Dim t As Object, tb As Object, r As Object, g As Object
    Dim w1 As Single, w2 As Single
    Heading "12. Tables: one grid for every row? can a table be grouped?"
    On Error Resume Next
    Set t = mSld.Shapes.AddTable(2, 3, 20, 200, 300, 60)
    If Err.Number <> 0 Then SayError "AddTable": Exit Sub
    Set tb = t.Table
    tb.Columns(1).Width = 80
    Say "column 1 set to 80: row 1 cell " & N2(tb.Cell(1, 1).Shape.Width) & _
        ", row 2 cell " & N2(tb.Cell(2, 1).Shape.Width)
    tb.Cell(2, 1).Shape.Width = 40
    If Err.Number <> 0 Then SayError "setting one cell's width"
    w1 = tb.Cell(1, 1).Shape.Width
    w2 = tb.Cell(2, 1).Shape.Width
    Say "asked row 2's cell 1 for 40: row 1 cell " & N2(w1) & ", row 2 cell " & N2(w2)
    If Abs(w1 - w2) < 0.5 Then
        Say "CONFIRMED: one grid -- every row keeps the same column widths"
    Else
        Say "CHECK: rows CAN differ in column width"
    End If
    Set r = mSld.Shapes.AddShape(1, 20, 300, 20, 20)
    Set g = mSld.Shapes.Range(Array(t.Name, r.Name)).Group
    If Err.Number <> 0 Then
        SayError "grouping a table with a rectangle"
    Else
        Say "a table CAN be grouped with another shape (" & g.GroupItems.Count & " items)"
        g.Delete
    End If
    t.Delete
    r.Delete
End Sub

'-----------------------------------------------------------------------------
' 13. The VBA project
'-----------------------------------------------------------------------------
Private Sub ProbeVBProject()
    Dim app As Object, n As Long
    Set app = Application
    Heading "13. Can VBA see its own project? (a build that imports its modules)"
    On Error Resume Next
    n = app.VBE.ActiveVBProject.VBComponents.Count
    If Err.Number <> 0 Then
        SayError "VBE.ActiveVBProject.VBComponents"
        Say "BLOCKED on this machine now. Look for ""Trust access to the VBA project object"
        Say "model"" in PowerPoint's security settings before concluding anything."
    Else
        Say "AVAILABLE: this project has " & n & " component(s)"
    End If
End Sub

'-----------------------------------------------------------------------------
' 14. Add-ins and the Startup folder
'-----------------------------------------------------------------------------
Private Sub ProbeAddIns()
    Dim app As Object, a As Object, i As Long, folder As String, fn As Integer, p As Long
    Set app = Application
    Heading "14. Add-ins, and Office's Startup folder for PowerPoint"
    On Error Resume Next
    Say "add-ins registered: " & app.AddIns.Count
    If Err.Number <> 0 Then SayError "AddIns"
    For i = 1 To app.AddIns.Count
        Set a = app.AddIns(i)
        Say "  " & a.Name & "  loaded " & a.Loaded & ", autoload " & a.AutoLoad & ", " & a.FullName
        Err.Clear
    Next
#If Mac Then
    folder = Environ$("HOME")
    p = InStr(folder, "/Library/Containers/")
    If p > 0 Then folder = Left$(folder, p - 1)
    folder = folder & "/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint"
    Say "Startup folder: " & folder
    fn = FreeFile
    Open folder & "/LingTeX-write-test.txt" For Output As #fn
    If Err.Number <> 0 Then
        SayError "writing a file there"
    Else
        Print #fn, "test"
        Close #fn
        Kill folder & "/LingTeX-write-test.txt"
        Say "USABLE: PowerPoint may write to it (a file was written and deleted)"
    End If
#Else
    Say "Windows: PowerPoint registers add-ins; there is no Startup folder to test"
#End If
End Sub
