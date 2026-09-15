Attribute VB_Name = "modProbePaste"
Option Explicit

'=============================================================================
' modProbePaste  --  LingTeX-PowerPoint
'
' PROBE ROUND 5: CAN A RE-WRAP BE ONE UNDO STEP?
'
' Round 4 found that every change a macro makes is its own undo step.  A
' re-wrap rewrites a whole example -- its text, each paragraph's tab stops,
' italics, small capitals -- so done change by change it would need dozens of
' Cmd+Z.  The idea tested here: compose the new example out of sight in a
' scratch presentation, copy it, and put it into the real box with ONE
' TextRange2.Paste.
'
'   PasteProbeSetup    puts an OLD example in a box on the probe slide (many
'                      undo steps: setup, not the test).
'   PasteProbeReplace  the measured run: composes a NEW example in a scratch
'                      presentation and pastes it over the old text -- the only
'                      change it makes to the probe slide -- then reports.
'   (a person presses Cmd+Z once, in the probe window)
'   PasteProbeReport   writes Paste.<os>.txt: does the box hold the OLD example
'                      whole, the NEW one whole, or a mixture; and did the tab
'                      stops, italics and small capitals come through the paste?
'
' Uses the probe presentation modProbeEvents tags (LINGTEXPROBE) when one is
' open, and otherwise makes one.  It uses the clipboard.  Pure ASCII, and
' numbers instead of named constants.
'=============================================================================

Private Const TARGET_NAME As String = "LingTeXPasteTarget"
Private Const PROBE_TAG As String = "LINGTEXPROBE"

'-----------------------------------------------------------------------------
' The two examples.  OLD: two lines, stops at 100 and 220.  NEW: three lines,
' stops at 80, 190 and 260 on the first two, a free translation below.  Forms
' italic, glosses in small capitals.
'-----------------------------------------------------------------------------
Private Sub FillOld(ByVal shp As Object)
    Dim tr As Object
    PrepareBox shp
    shp.TextFrame2.TextRange.Text = "Los" & Chr$(9) & "nin-o-s" & Chr$(9) & "de" & Chr$(13) & _
                                    "def.m.pl" & Chr$(9) & "child-m-pl" & Chr$(9) & "of"
    FormatBox shp
    Set tr = shp.TextFrame2.TextRange
    SetStops tr.Paragraphs(1), Array(100, 220)
    SetStops tr.Paragraphs(2), Array(100, 220)
    tr.Paragraphs(1).Font.Italic = -1
    tr.Paragraphs(2).Font.Smallcaps = -1
End Sub

Private Sub FillNew(ByVal shp As Object)
    Dim tr As Object
    PrepareBox shp
    shp.TextFrame2.TextRange.Text = "Los" & Chr$(9) & "nin-o-s" & Chr$(9) & "de" & Chr$(9) & "mi" & Chr$(13) & _
                                    "def.m.pl" & Chr$(9) & "child-m-pl" & Chr$(9) & "of" & Chr$(9) & "1sg.poss" & Chr$(13) & _
                                    "'My neighbor's children bought bread.'"
    FormatBox shp
    Set tr = shp.TextFrame2.TextRange
    SetStops tr.Paragraphs(1), Array(80, 190, 260)
    SetStops tr.Paragraphs(2), Array(80, 190, 260)
    tr.Paragraphs(1).Font.Italic = -1
    tr.Paragraphs(2).Font.Smallcaps = -1
End Sub

Private Sub PrepareBox(ByVal shp As Object)
    With shp.TextFrame2
        .WordWrap = -1
        .AutoSize = 1
        .MarginLeft = 0
        .MarginRight = 0
    End With
End Sub

Private Sub FormatBox(ByVal shp As Object)
    With shp.TextFrame2.TextRange.Font
        .Name = "Times New Roman"
        .Size = 20
        .Italic = 0
        .Smallcaps = 0
    End With
End Sub

Private Sub SetStops(ByVal para As Object, ByVal stops As Variant)
    Dim i As Long
    With para.ParagraphFormat.TabStops
        Do While .Count > 0
            .Item(1).Clear
        Loop
        For i = LBound(stops) To UBound(stops)
            .Add 1, CSng(stops(i))
        Next
    End With
End Sub

'-----------------------------------------------------------------------------
' The runs
'-----------------------------------------------------------------------------
Public Sub PasteProbeSetup()
    Dim sld As Object, shp As Object
    On Error Resume Next
    Set sld = PasteSlide(True)
    If sld Is Nothing Then
        WriteDevReport "Paste", "PROBLEM: no probe slide could be made"
        Exit Sub
    End If
    DeleteTarget sld
    Set shp = sld.Shapes.AddTextbox(1, 60, 330, 700, 80)
    shp.Name = TARGET_NAME
    FillOld shp
    If Err.Number <> 0 Then
        WriteDevReport "Paste", "PROBLEM: setting up: " & Err.Number & ": " & Err.Description
        Exit Sub
    End If
    PasteProbeReport "set up: the box should hold the OLD example"
End Sub

Public Sub PasteProbeReplace()
    Dim app As Object, sld As Object, target As Object, scratch As Object, sb As Object
    Dim note As String
    Set app = Application
    On Error Resume Next
    Set sld = PasteSlide(False)
    If sld Is Nothing Then
        WriteDevReport "Paste", "PROBLEM: no probe slide (run PasteProbeSetup first)"
        Exit Sub
    End If
    Set target = sld.Shapes(TARGET_NAME)
    Err.Clear
    If target Is Nothing Then
        WriteDevReport "Paste", "PROBLEM: no target box (run PasteProbeSetup first)"
        Exit Sub
    End If

    ' Compose the new example out of sight, and copy it.
    Set scratch = app.Presentations.Add(0)
    Set sb = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, 700, 80)
    FillNew sb
    sb.TextFrame2.TextRange.Copy
    If Err.Number <> 0 Then
        note = "PROBLEM: composing or copying the new example: " & Err.Number & ": " & Err.Description
        Err.Clear
    Else
        ' THE MEASURED CHANGE: one paste over the whole old text.
        target.TextFrame2.TextRange.Paste
        If Err.Number <> 0 Then
            note = "PROBLEM: TextRange2.Paste: " & Err.Number & ": " & Err.Description
            Err.Clear
        Else
            note = "replaced by one TextRange2.Paste: now press Cmd+Z once in the probe window, then run PasteProbeReport"
        End If
    End If
    scratch.Saved = -1
    scratch.Close
    Err.Clear
    sld.Parent.Windows(1).Activate
    Err.Clear
    PasteProbeReport note
End Sub

Public Sub PasteProbeReport(Optional ByVal note As String = "")
    Dim sld As Object, target As Object, tr As Object, s As String, i As Long
    Dim sig As String, sigOld As String, sigNew As String
    On Error Resume Next
    s = "Paste probe  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & vbLf
    If note <> "" Then s = s & note & vbLf
    Set sld = PasteSlide(False)
    If Not sld Is Nothing Then Set target = sld.Shapes(TARGET_NAME)
    Err.Clear
    If target Is Nothing Then
        WriteDevReport "Paste", s & "PROBLEM: no target box"
        Exit Sub
    End If
    Set tr = target.TextFrame2.TextRange
    s = s & "paragraphs: " & tr.Paragraphs.Count & vbLf
    For i = 1 To tr.Paragraphs.Count
        s = s & "  p" & i & "  '" & Esc(tr.Paragraphs(i).Text) & "'" & _
            "  stops " & StopsOf(tr.Paragraphs(i)) & _
            "  italic " & tr.Paragraphs(i).Characters(1, 1).Font.Italic & _
            "  smallcaps " & tr.Paragraphs(i).Characters(1, 1).Font.Smallcaps & vbLf
    Next

    sig = Signature(tr)
    ReferenceSignatures sigOld, sigNew
    If sigOld = "" Or sigNew = "" Then
        s = s & "PROBLEM: the reference examples could not be built" & vbLf
    ElseIf sig = sigOld Then
        s = s & "HOLDS: the OLD example, whole" & vbLf
    ElseIf sig = sigNew Then
        s = s & "HOLDS: the NEW example, whole" & vbLf
    Else
        s = s & "HOLDS: neither whole -- a mixture, or the paste changed the formatting (compare with the paragraphs above)" & vbLf
        s = s & "  old would be: " & Esc(sigOld) & vbLf
        s = s & "  new would be: " & Esc(sigNew) & vbLf
    End If
    WriteDevReport "Paste", s
End Sub

'-----------------------------------------------------------------------------
' What an example looks like, as one string: each paragraph's text, stops,
' and the italic and small-capitals state of its first character.
'-----------------------------------------------------------------------------
Private Function Signature(ByVal tr As Object) As String
    Dim i As Long, s As String, t As String
    For i = 1 To tr.Paragraphs.Count
        t = tr.Paragraphs(i).Text
        t = Replace(Replace(t, Chr$(13), ""), Chr$(11), "")
        s = s & "|" & t & "#" & StopsOf(tr.Paragraphs(i)) & "#" & _
            tr.Paragraphs(i).Characters(1, 1).Font.Italic & "#" & _
            tr.Paragraphs(i).Characters(1, 1).Font.Smallcaps
    Next
    Signature = s
End Function

' The signatures of OLD and NEW, built in a scratch presentation each time, so
' the report compares like with like instead of with hand-written strings.
Private Sub ReferenceSignatures(ByRef sigOld As String, ByRef sigNew As String)
    Dim app As Object, scratch As Object, sld As Object, a As Object, b As Object
    Set app = Application
    On Error Resume Next
    Set scratch = app.Presentations.Add(0)
    Set sld = scratch.Slides.Add(1, 12)
    Set a = sld.Shapes.AddTextbox(1, 0, 0, 700, 80)
    Set b = sld.Shapes.AddTextbox(1, 0, 200, 700, 80)
    FillOld a
    FillNew b
    If Err.Number = 0 Then
        sigOld = Signature(a.TextFrame2.TextRange)
        sigNew = Signature(b.TextFrame2.TextRange)
    End If
    scratch.Saved = -1
    scratch.Close
    Err.Clear
End Sub

Private Function StopsOf(ByVal para As Object) As String
    Dim i As Long, s As String
    On Error Resume Next
    With para.ParagraphFormat.TabStops
        For i = 1 To .Count
            If i > 1 Then s = s & ","
            s = s & Format$(.Item(i).Position, "0")
        Next
    End With
    StopsOf = "[" & s & "]"
End Function

Private Function Esc(ByVal s As String) As String
    s = Replace(s, Chr$(9), "\t")
    s = Replace(s, Chr$(13), "\r")
    s = Replace(s, Chr$(11), "\v")
    Esc = Replace(s, Chr$(10), "\n")
End Function

'-----------------------------------------------------------------------------
' The probe presentation: the one tagged LINGTEXPROBE, or a new one.
'-----------------------------------------------------------------------------
Private Function PasteSlide(ByVal makeIfNone As Boolean) As Object
    Dim app As Object, p As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        If p.Tags.Item(PROBE_TAG) = "1" Then
            Set PasteSlide = p.Slides(1)
            Exit Function
        End If
    Next
    If Not makeIfNone Then Exit Function
    Set p = app.Presentations.Add(-1)
    p.Tags.Add PROBE_TAG, "1"
    Set PasteSlide = p.Slides.Add(1, 12)
End Function

Private Sub DeleteTarget(ByVal sld As Object)
    Dim shp As Object
    On Error Resume Next
    Set shp = sld.Shapes(TARGET_NAME)
    If Not shp Is Nothing Then shp.Delete
    Err.Clear
End Sub
