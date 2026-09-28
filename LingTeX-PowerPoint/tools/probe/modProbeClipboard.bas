Attribute VB_Name = "modProbeClipboard"
Option Explicit
'=============================================================================
' modProbeClipboard  --  LingTeX-PowerPoint
'
' PROBE ROUND 7: DOES THE USER'S CLIPBOARD SURVIVE THE ONE PASTE?
'
' Every insert and re-wrap is one TextRange2.Paste (round 5), which is a
' clipboard round trip: it overwrites whatever the user had copied.  The
' answer is to SAVE the clipboard first and RESTORE it after -- both outside
' the user's presentation, so neither is an undo entry there:
'
'   1. save     paste the clipboard into a text box in a scratch presentation
'   2. compose  the example, in another scratch box; Copy
'   3. paste    ONE TextRange2.Paste into the example's box  (the undo entry)
'   4. restore  Copy the saved box's text: the clipboard is the user's again
'
' Seth's requirement (2026-09-28): one UI action = one undo entry; two only
' if one is impossible at acceptable cost; never ten or twelve.  This probe
' measures what the sequence costs and what it loses.
'
'   A. Rich TEXT on the clipboard (italics, small capitals, tab stops): after
'      save, paste, restore, is the clipboard the user's snippet whole?
'   B. A SHAPE on the clipboard (not text): can a paste into a text box save
'      it at all, what does AppleScript see there, and does the shape survive
'      a set-the-clipboard-to-the-clipboard round trip?  This is the case a
'      text-box save cannot cover; the answer decides the fallback.
'
' The undo count is measured by the rig, not here: run-in-powerpoint.sh
' --undo-check reads the Edit menu's first item after this macro returns
' ("Undo Paste" is the expectation), presses Cmd+Z once, and reads it again;
' the target then holds the OLD example (as round 5 showed) and the next item
' up should be the setup's, not another paste.
'
' The target box sits on the probe presentation's slide (the one tagged
' LINGTEXPROBE, made if absent, with a window, so the Edit menu is live).
' Pure ASCII; numbers instead of named constants: Presentations.Add(0) no
' window, Slides.Add(1, 12) blank, AddTextbox(1, ...) horizontal, AddShape(1,
' ...) a rectangle.  Break characters Chr$(13)/Chr$(10), never vbCrLf.
'=============================================================================

Private Const PROBE_TAG As String = "LINGTEXPROBE"
Private Const TARGET_NAME As String = "LingTeXClipTarget"

Public Sub ProbeClipboardQuiet()
    Dim s As String
    s = "Clipboard probe (round 7)  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & Chr$(10)
    s = s & SectionText()
    s = s & SectionShape()
    WriteDevReport "Clipboard", s
End Sub

'-----------------------------------------------------------------------------
' A. Rich text, saved and restored around the one paste
'-----------------------------------------------------------------------------
Private Function SectionText() As String
    Dim app As Object, scratch As Object, sld As Object, target As Object
    Dim userBox As Object, saveBox As Object, exBox As Object, checkBox As Object
    Dim s As String, sigUser As String, sigSaved As String, sigEx As String, sigBack As String
    Set app = Application
    On Error Resume Next
    s = Chr$(10) & "== A. Rich TEXT on the clipboard, saved and restored around the one paste" & Chr$(10)

    Set target = ProbeTarget()
    If target Is Nothing Then
        SectionText = s & "PROBLEM: no target box could be made" & Chr$(10)
        Exit Function
    End If
    FillOld target
    s = s & Chk("setup: the target holds an OLD example (many undo entries: setup, not the test)")

    Set scratch = app.Presentations.Add(0)
    Set sld = scratch.Slides.Add(1, 12)
    ' The user's clipboard: a formatted snippet, copied from a scratch box.
    Set userBox = sld.Shapes.AddTextbox(1, 0, 0, 500, 60)
    FillUser userBox
    sigUser = Signature(userBox.TextFrame2.TextRange)
    userBox.TextFrame2.TextRange.Copy
    s = s & Chk("the user's clipboard: a snippet with italics, small capitals and tab stops")

    ' 1. save
    Set saveBox = sld.Shapes.AddTextbox(1, 0, 100, 500, 60)
    saveBox.TextFrame2.TextRange.Paste
    s = s & Chk("1 save: TextRange2.Paste into a scratch box")
    sigSaved = Signature(saveBox.TextFrame2.TextRange)
    s = s & "     saved box holds the snippet whole: " & Verdict(sigSaved = sigUser, sigUser, sigSaved)

    ' 2. compose + 3. the one write
    Set exBox = sld.Shapes.AddTextbox(1, 0, 200, 700, 80)
    FillExample exBox
    sigEx = Signature(exBox.TextFrame2.TextRange)
    exBox.TextFrame2.TextRange.Copy
    target.TextFrame2.TextRange.Paste
    s = s & Chk("2+3 compose, Copy, ONE TextRange2.Paste into the target (THE undo entry)")
    s = s & "     target holds the example whole: " & Verdict(Signature(target.TextFrame2.TextRange) = sigEx, sigEx, Signature(target.TextFrame2.TextRange))

    ' 4. restore
    saveBox.TextFrame2.TextRange.Copy
    s = s & Chk("4 restore: Copy from the saved box")

    ' check: what the clipboard holds now, by pasting it somewhere fresh
    Set checkBox = sld.Shapes.AddTextbox(1, 0, 300, 500, 60)
    checkBox.TextFrame2.TextRange.Paste
    sigBack = Signature(checkBox.TextFrame2.TextRange)
    s = s & "     clipboard after restore is the user's snippet whole: " & Verdict(sigBack = sigUser, sigUser, sigBack)
    s = s & "     AppleScript sees: '" & Esc(Left$(app.MacScript("the clipboard as text"), 60)) & "'" & Chk("") & Chr$(10)

    scratch.Saved = -1
    scratch.Close
    Err.Clear
    target.Parent.Parent.Windows(1).Activate
    Err.Clear
    SectionText = s
End Function

'-----------------------------------------------------------------------------
' B. A shape on the clipboard: the case a text box cannot save
'-----------------------------------------------------------------------------
Private Function SectionShape() As String
    Dim app As Object, scratch As Object, sld As Object, rect As Object, saveBox As Object
    Dim s As String, before As Long, after As Long, flavours As String
    Set app = Application
    On Error Resume Next
    s = Chr$(10) & "== B. A SHAPE on the clipboard (not text)" & Chr$(10)
    Set scratch = app.Presentations.Add(0)
    Set sld = scratch.Slides.Add(1, 12)
    Set rect = sld.Shapes.AddShape(1, 0, 0, 120, 60)
    rect.Name = "LingTeXClipRect"
    rect.Copy
    s = s & Chk("a rectangle copied to the clipboard")

    flavours = app.MacScript("set L to clipboard info" & Chr$(13) & "return (count of L) as text")
    s = s & "     AppleScript: clipboard info has " & flavours & " flavour(s)" & Chk("") & Chr$(10)
    s = s & "     first flavour: " & Esc(app.MacScript("return (item 1 of item 1 of (clipboard info)) as text")) & Chk("") & Chr$(10)

    Set saveBox = sld.Shapes.AddTextbox(1, 0, 100, 500, 60)
    saveBox.TextFrame2.TextRange.Paste
    s = s & Chk("a text-box save of it: TextRange2.Paste") & "     box text now: '" & Esc(saveBox.TextFrame2.TextRange.Text) & "'" & Chr$(10)

    before = sld.Shapes.Count
    sld.Shapes.Paste
    after = sld.Shapes.Count
    s = s & Chk("Shapes.Paste of it") & "     shapes " & before & " -> " & after & " (a shape came back: " & (after = before + 1) & ")" & Chr$(10)

    app.MacScript "set the clipboard to (the clipboard)"
    s = s & Chk("AppleScript: set the clipboard to (the clipboard)")
    before = sld.Shapes.Count
    sld.Shapes.Paste
    after = sld.Shapes.Count
    s = s & Chk("Shapes.Paste after that round trip") & "     shapes " & before & " -> " & after & " (the shape survived AppleScript: " & (after = before + 1) & ")" & Chr$(10)

    scratch.Saved = -1
    scratch.Close
    Err.Clear
    SectionShape = s
End Function

'-----------------------------------------------------------------------------
' The examples and the snippet
'-----------------------------------------------------------------------------
Private Sub FillUser(ByVal shp As Object)
    Dim tr As Object
    PrepareBox shp
    shp.TextFrame2.TextRange.Text = "The user's" & Chr$(9) & "own" & Chr$(9) & "copy" & Chr$(13) & "kept" & Chr$(9) & "whole"
    FormatBox shp
    Set tr = shp.TextFrame2.TextRange
    SetStops tr.Paragraphs(1), Array(90, 180)
    SetStops tr.Paragraphs(2), Array(90, 180)
    tr.Paragraphs(1).Font.Italic = -1
    tr.Paragraphs(2).Font.Smallcaps = -1
End Sub

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

Private Sub FillExample(ByVal shp As Object)
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
' Signatures, verdicts, the probe presentation
'-----------------------------------------------------------------------------
' Each paragraph's text, stops, and the italic and small-capital state of its
' first character, as one string.
Private Function Signature(ByVal tr As Object) As String
    Dim i As Long, s As String, t As String
    On Error Resume Next
    For i = 1 To tr.Paragraphs.Count
        t = tr.Paragraphs(i).Text
        t = Replace(Replace(t, Chr$(13), ""), Chr$(11), "")
        s = s & "|" & t & "#" & StopsOf(tr.Paragraphs(i)) & "#" & _
            tr.Paragraphs(i).Characters(1, 1).Font.Italic & "#" & _
            tr.Paragraphs(i).Characters(1, 1).Font.Smallcaps
    Next
    Signature = s
End Function

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

Private Function Verdict(ByVal same As Boolean, ByVal want As String, ByVal got As String) As String
    If same Then
        Verdict = "YES" & Chr$(10)
    Else
        Verdict = "NO" & Chr$(10) & "       want " & Esc(want) & Chr$(10) & "       got  " & Esc(got) & Chr$(10)
    End If
End Function

' "  ok   label" or "  ERR  label: number: description", and clears the error.
Private Function Chk(ByVal label As String) As String
    If Err.Number <> 0 Then
        Chk = "  ERR  " & label & ": " & Err.Number & ": " & Err.Description & Chr$(10)
        Err.Clear
    ElseIf label <> "" Then
        Chk = "  ok   " & label & Chr$(10)
    End If
End Function

Private Function Esc(ByVal s As String) As String
    s = Replace(s, Chr$(9), "\t")
    s = Replace(s, Chr$(13), "\r")
    s = Replace(s, Chr$(11), "\v")
    Esc = Replace(s, Chr$(10), "\n")
End Function

' The target box on the probe presentation's first slide: the presentation
' tagged LINGTEXPROBE, or a new one with a window; the box is replaced.
Private Function ProbeTarget() As Object
    Dim app As Object, p As Object, sld As Object, shp As Object
    Set app = Application
    On Error Resume Next
    For Each p In app.Presentations
        If p.Tags.Item(PROBE_TAG) = "1" Then Set sld = p.Slides(1)
    Next
    If sld Is Nothing Then
        Set p = app.Presentations.Add(-1)
        p.Tags.Add PROBE_TAG, "1"
        Set sld = p.Slides.Add(1, 12)
    End If
    Set shp = sld.Shapes(TARGET_NAME)
    If Not shp Is Nothing Then shp.Delete
    Err.Clear
    Set shp = sld.Shapes.AddTextbox(1, 60, 330, 700, 80)
    shp.Name = TARGET_NAME
    Set ProbeTarget = shp
End Function
