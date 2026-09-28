Attribute VB_Name = "modPptCompose"
Option Explicit
'=============================================================================
' modPptCompose  --  LingTeX-PowerPoint
'
' Draws an example into a text box: the PowerPoint counterpart of Word's
' modRender, on the one-text-box design settled by the probes (PLAN.md).
'
'   - one paragraph per interlinear tier per wrap line;
'   - that line's columns lined up with tab stops set for those paragraphs at
'     the measured positions (32 stops a paragraph, so 33 columns a line at
'     most: LimitLineColumns splits a wider plan);
'   - the example number hanging in the first line's indent: LeftIndent = the
'     hang, FirstLineIndent = -hang, a stop at the hang (probe round 1);
'   - the free translation as a paragraph below, in single quotes;
'   - the forms tier italic, grammatical glosses in small capitals, through
'     modPptFormat, so what is drawn is what was measured.
'
' Where it draws is the caller's business.  Insert and re-wrap compose into a
' text box in a SCRATCH presentation, copy, and put the result into the
' example's own box with ONE TextRange2.Paste (probe round 5): one undo entry,
' and the box's position, size and Tags untouched (round 6).
'
' Widths are the planner's: colWidths from modWrap.ColumnWidths, lineStarts
' from modWrap.ComputeWrapLines called with the same indents used here.
' Pure ASCII apart from the quotes, which come from modFlexParse.
'=============================================================================

Public Type PptLayout
    Gap           As Double        ' between columns, points (already inside colWidths)
    NumberHang    As Double        ' the numbered first line's indent; the number hangs in it
    ContIndent    As Double        ' indent of every later wrap line
    LowercaseGram As Boolean       ' ERG -> erg under small caps (Word's default: True)
    InitialCap    As Boolean       ' 3SG -> 3Sg
    FreeFont      As PptTierFont   ' the free translation's font
End Type

Private Const MAX_COLS_PER_LINE As Long = 33

' A plan with no wrap line wider than 33 columns: any wider line is cut into
' 33-column pieces.  lineStarts is 0-based, as ComputeWrapLines returns it.
Public Function LimitLineColumns(lineStarts() As Long, ByVal colCount As Long) As Long()
    Dim out() As Long, n As Long, i As Long, s As Long, e As Long, c As Long
    If colCount <= 0 Then
        ReDim out(-1 To -1)
        LimitLineColumns = out
        Exit Function
    End If
    ReDim out(0 To colCount - 1)
    n = 0
    For i = LBound(lineStarts) To UBound(lineStarts)
        s = lineStarts(i)
        e = WrapLineEnd(lineStarts, i, colCount)
        c = s
        Do
            out(n) = c
            n = n + 1
            c = c + MAX_COLS_PER_LINE
        Loop While c <= e
    Next i
    ReDim Preserve out(0 To n - 1)
    LimitLineColumns = out
End Function

' Fill box (a Shape with a TextFrame2) with the example.  numberText "" means
' no number.  fonts(t) is tier t's font; colWidths(c) is column c's width
' including the gap; lineStarts is the wrap plan.
Public Sub ComposeExample(ByVal box As Object, ex As IgtExample, fonts() As PptTierFont, _
        colWidths() As Double, lineStarts() As Long, ByVal numberText As String, lay As PptLayout)
    Dim tr As Object, p As Object, txt As String
    Dim tiers() As Long, nTiers As Long, t As Long, k As Long
    Dim L As Long, s As Long, e As Long, c As Long, f As Long, para As Long
    Dim numbered As Boolean, firstPara As Boolean, lineIndent As Double, x As Double
    Dim cellText As String, pos As Long

    ' The interlinear tiers, in order; free rows are prose below.
    ReDim tiers(0 To ex.TierCount)
    nTiers = 0
    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            tiers(nTiers) = t
            nTiers = nTiers + 1
        End If
    Next t
    numbered = (Len(numberText) > 0)

    ' 1. The whole text, paragraph by paragraph, in one assignment.
    txt = ""
    For L = LBound(lineStarts) To UBound(lineStarts)
        s = lineStarts(L)
        e = WrapLineEnd(lineStarts, L, ex.ColCount)
        For k = 0 To nTiers - 1
            t = tiers(k)
            If Len(txt) > 0 Then txt = txt & Chr$(13)
            If L = LBound(lineStarts) And k = 0 And numbered Then txt = txt & numberText & Chr$(9)
            For c = s To e
                If c > s Then txt = txt & Chr$(9)
                txt = txt & DisplayCellText(GetCell(ex, t, c), ex.Tiers(t), lay.LowercaseGram, lay.InitialCap)
            Next c
        Next k
    Next L
    For f = 0 To ex.FreeCount - 1
        If Len(txt) > 0 Then txt = txt & Chr$(13)
        txt = txt & LeftSingleQuote & ex.FreeLines(LBound(ex.FreeLines) + f) & RightSingleQuote
    Next f
    Set tr = box.TextFrame2.TextRange
    tr.Text = txt

    ' 2. Paragraph by paragraph: font, indents, stops, small-capital runs.
    para = 0
    For L = LBound(lineStarts) To UBound(lineStarts)
        s = lineStarts(L)
        e = WrapLineEnd(lineStarts, L, ex.ColCount)
        If L = LBound(lineStarts) Then
            If numbered Then lineIndent = lay.NumberHang Else lineIndent = 0
        Else
            lineIndent = lay.ContIndent
        End If
        For k = 0 To nTiers - 1
            t = tiers(k)
            para = para + 1
            firstPara = (L = LBound(lineStarts) And k = 0 And numbered)
            Set p = tr.Paragraphs(para)
            SetParagraphFont p, fonts(t)
            With p.ParagraphFormat
                .LeftIndent = lineIndent
                If firstPara Then .FirstLineIndent = -lay.NumberHang Else .FirstLineIndent = 0
            End With
            ClearStops p
            If firstPara Then AddStop p, lay.NumberHang
            x = lineIndent
            For c = s To e - 1
                x = x + colWidths(c)
                AddStop p, x
            Next c
            If TierTakesSmallCaps(ex.Tiers(t)) Then
                pos = 1
                If firstPara Then pos = pos + Len(numberText) + 1
                For c = s To e
                    cellText = GetCell(ex, t, c)
                    ApplyGramGlossRuns p, cellText, ex.Tiers(t), pos
                    pos = pos + Len(cellText) + 1
                Next c
            End If
        Next k
    Next L
    For f = 0 To ex.FreeCount - 1
        para = para + 1
        Set p = tr.Paragraphs(para)
        SetParagraphFont p, lay.FreeFont
        With p.ParagraphFormat
            If numbered Then .LeftIndent = lay.NumberHang Else .LeftIndent = lay.ContIndent
            .FirstLineIndent = 0
        End With
        ClearStops p
    Next f
End Sub

' The example box's frame settings: the planner's breaks are the only breaks
' that should happen, but wrap stays on as the safety net probe round 1 showed
' to be exact; AutoSize 1 (shape to fit text) so the height follows the text
' and the width -- the wrap width -- is the user's.
Public Sub PrepareExampleBox(ByVal box As Object)
    With box.TextFrame2
        .WordWrap = -1
        .AutoSize = 1
        .MarginLeft = 0
        .MarginRight = 0
    End With
End Sub

'-----------------------------------------------------------------------------
Private Sub SetParagraphFont(ByVal p As Object, tf As PptTierFont)
    With p.Font
        .Name = tf.Name
        .Size = tf.Size
        If tf.Italic Then .Italic = -1 Else .Italic = 0
        .Smallcaps = 0
    End With
End Sub

Private Sub ClearStops(ByVal p As Object)
    With p.ParagraphFormat.TabStops
        Do While .Count > 0
            .Item(1).Clear
        Loop
    End With
End Sub

Private Sub AddStop(ByVal p As Object, ByVal x As Double)
    p.ParagraphFormat.TabStops.Add 1, CSng(x)
End Sub
