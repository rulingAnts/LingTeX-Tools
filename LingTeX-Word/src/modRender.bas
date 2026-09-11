Attribute VB_Name = "modRender"
Option Explicit

'=============================================================================
' modRender  --  LingTeX-Word
'
' Draws an interlinear example as a BORDERLESS WORD TABLE, one table column per
' alignment slot and one table row per tier, wrapped to the page width.
'
' ---------------------------------------------------------------------------
' ONE TABLE, SEVERAL WRAP LINES
'
' Word will not wrap a table, so the example is wrapped here and the result is
' drawn as successive ROW GROUPS inside a SINGLE table: group 1 holds the first
' wrap line's columns, group 2 the next, and so on, each group being one row per
' tier.  A Word table is row-based, so rows are free to have different cell
' counts and different cell widths -- which is what makes this possible.
'
' One table rather than one table per wrap line, because:
'   * the example stays a single object to select, move, style and delete;
'   * there is no inter-table paragraph to accumulate stray spacing;
'   * Rows.AllowBreakAcrossPages = False plus KeepWithNext is then enough to stop
'     a page break landing inside a stack of aligned cells.
'
' Free translations are written as paragraphs AFTER the table, never as a row, so
' they never take part in wrapping and are exempt from the column invariants.
' ---------------------------------------------------------------------------
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'=============================================================================
' -- RENDERING --------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Draw an example at a range, replacing whatever the range covers.
' Returns the table created, or Nothing if there was nothing to draw.
'-----------------------------------------------------------------------------
Public Function RenderExample(ex As IgtExample, target As Range) As Table
    Dim doc As Document
    Dim cellWidths() As Single, colW() As Single
    Dim flags() As Boolean, lineStarts() As Long
    Dim avail As Single, gap As Single, contIndent As Single
    Dim interTiers() As Long, nInter As Long
    Dim nLines As Long, maxCols As Long
    Dim tbl As Table
    Dim anchor As Range

    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Function
    Set doc = target.Document
    EnsureStyles doc

    nInter = InterlinearTierList(ex, interTiers)
    If nInter = 0 Then Exit Function

    '-- plan ----------------------------------------------------------------
    gap = SettingGap(doc)
    contIndent = SettingContIndent(doc)
    avail = AvailableTextWidth(target)

    MeasureExample ex, doc, cellWidths
    colW = ColumnWidths(ex, cellWidths, gap)
    flags = NoBreakFlags(ex)
    lineStarts = ComputeWrapLines(colW, flags, avail, 0, contIndent)

    nLines = UBound(lineStarts) - LBound(lineStarts) + 1
    maxCols = MaxColumnsPerLine(lineStarts, ex.ColCount)
    If maxCols < 1 Then Exit Function

    '-- draw ----------------------------------------------------------------
    Set anchor = target.Duplicate
    anchor.Text = ""                       ' clear whatever we are replacing

    Set tbl = doc.Tables.Add(Range:=anchor, _
                             NumRows:=nLines * nInter, NumColumns:=maxCols)
    StyleTable tbl, doc

    FillTable tbl, ex, interTiers, nInter, lineStarts, colW, doc
    SetRowKeeps tbl, nInter, nLines, doc

    '-- free translations, after the table ----------------------------------
    WriteFreeLines ex, tbl, doc

    Set RenderExample = tbl
End Function

'-----------------------------------------------------------------------------
' Re-wrap an existing example in place.
'
' Reads the table back into a model, then draws it again from scratch.  Because
' the plan is recomputed from the full column list rather than patched, this
' single path handles columns moving DOWN when space runs out and columns moving
' back UP when it is freed -- after a margin change, a font change, an
' orientation flip, or an edit.  It is idempotent: running it on an example that
' is already correct changes nothing visible.
'-----------------------------------------------------------------------------
Public Function RewrapTable(tbl As Table) As Table
    Dim ex As IgtExample
    Dim doc As Document
    Dim anchor As Range
    Dim startPos As Long

    If tbl Is Nothing Then Exit Function
    Set doc = tbl.Range.Document

    ex = ReadExampleFromTable(tbl)
    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Function

    ' Absorb the free-translation paragraphs that belong to this example, so they
    ' are rewritten rather than duplicated.
    AbsorbFreeParagraphs ex, tbl

    startPos = tbl.Range.Start
    DeleteTableAndFreeLines tbl

    Set anchor = doc.Range(startPos, startPos)
    Set RewrapTable = RenderExample(ex, anchor)
End Function


'=============================================================================
' -- TABLE CONSTRUCTION -----------------------------------------------------
'=============================================================================

' Indices of the tiers that become table rows, i.e. everything but Free.
Public Function InterlinearTierList(ex As IgtExample, ByRef outIdx() As Long) As Long
    Dim t As Long, n As Long
    ReDim outIdx(0 To IIf(ex.TierCount > 0, ex.TierCount - 1, 0))
    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            outIdx(n) = t
            n = n + 1
        End If
    Next t
    InterlinearTierList = n
End Function

Private Sub StyleTable(tbl As Table, doc As Document)
    On Error Resume Next
    tbl.Style = doc.Styles(STYLE_TABLE)
    On Error GoTo 0

    On Error Resume Next
    ' Explicit widths only: autofit would undo the plan the moment Word
    ' recalculated the layout.
    tbl.AllowAutoFit = False
    ' Borders are switched off HERE, per table, not left to the table style.
    ' Setting borders on a table style fails on Mac Word with error 4198, so on
    ' Mac these two lines are the only thing making the example borderless.
    ' See the table-style comment in modStyles.bas.
    tbl.Borders.InsideLineStyle = wdLineStyleNone
    tbl.Borders.OutsideLineStyle = wdLineStyleNone
    tbl.Range.Cells.VerticalAlignment = wdCellAlignVerticalTop
    tbl.Rows.AllowBreakAcrossPages = False
    tbl.Rows.Alignment = wdAlignRowLeft
    On Error GoTo 0

    ZeroTablePadding tbl
End Sub

'-----------------------------------------------------------------------------
' Fill the rows, one wrap line at a time.
'
' Rows that hold fewer columns than the widest wrap line have their surplus
' cells deleted.  Deleting from the left-most surplus position repeatedly works
' because Word shifts the remaining cells left each time.
'-----------------------------------------------------------------------------
Private Sub FillTable(tbl As Table, ex As IgtExample, interTiers() As Long, _
        ByVal nInter As Long, lineStarts() As Long, colW() As Single, doc As Document)

    Dim g As Long, i As Long, c As Long, r As Long
    Dim lineFirst As Long, lineLast As Long, lineCols As Long
    Dim nLines As Long, maxCols As Long
    Dim surplus As Long, k As Long
    Dim role As String
    Dim cellRng As Range
    Dim lineGap As Single

    nLines = UBound(lineStarts) - LBound(lineStarts) + 1
    maxCols = MaxColumnsPerLine(lineStarts, ex.ColCount)
    lineGap = SettingLineGap(doc)

    For g = 0 To nLines - 1
        lineFirst = lineStarts(g)
        lineLast = WrapLineEnd(lineStarts, g, ex.ColCount)
        lineCols = lineLast - lineFirst + 1

        For i = 0 To nInter - 1
            r = g * nInter + i + 1                 ' Word rows are 1-based
            role = ex.Tiers(interTiers(i))

            ' Trim this row down to the columns this wrap line actually holds.
            surplus = maxCols - lineCols
            For k = 1 To surplus
                On Error Resume Next
                tbl.Rows(r).Cells(lineCols + 1).Delete
                On Error GoTo 0
            Next k

            For c = 0 To lineCols - 1
                Set cellRng = tbl.Cell(r, c + 1).Range
                cellRng.End = cellRng.End - 1      ' exclude end-of-cell marker

                ApplyParaStyle cellRng, doc, role
                WriteCellText cellRng, ex.Cells(interTiers(i), lineFirst + c), role, False

                On Error Resume Next
                tbl.Cell(r, c + 1).SetWidth _
                    ColumnWidth:=colW(lineFirst + c), RulerStyle:=wdAdjustNone
                On Error GoTo 0
            Next c

            ' Air between wrap lines goes on the last tier row of each group,
            ' except the final group, which is followed by the free translation.
            On Error Resume Next
            If i = nInter - 1 And g < nLines - 1 Then
                tbl.Rows(r).Range.ParagraphFormat.SpaceAfter = lineGap
            Else
                tbl.Rows(r).Range.ParagraphFormat.SpaceAfter = 0
            End If
            On Error GoTo 0
        Next i
    Next g
End Sub

'-----------------------------------------------------------------------------
' Keep the example together across a page break.
' AllowBreakAcrossPages already stops a single row splitting; KeepWithNext on
' every row but the last stops the stack being separated tier from tier.
'-----------------------------------------------------------------------------
Private Sub SetRowKeeps(tbl As Table, ByVal nInter As Long, _
        ByVal nLines As Long, doc As Document)
    Dim r As Long, last As Long
    On Error Resume Next
    last = tbl.Rows.Count
    For r = 1 To last
        tbl.Rows(r).Range.ParagraphFormat.KeepWithNext = (r < last)
    Next r
    On Error GoTo 0
End Sub


'=============================================================================
' -- CELL TEXT AND SMALL CAPS -----------------------------------------------
'=============================================================================

' Tiers whose content is meta-language and so takes small caps on grammatical
' abbreviations.  The object-language rows never do: an all-caps vernacular word
' or a proper noun would be silently restyled.
Public Function TierTakesSmallCaps(ByVal role As String) As Boolean
    Select Case role
        Case ROLE_VERNACULAR, ROLE_MORPHEMES, ROLE_FREE
            TierTakesSmallCaps = False
        Case Else
            TierTakesSmallCaps = True
    End Select
End Function

'-----------------------------------------------------------------------------
' Put one cell's text into a range, with grammatical glosses in small caps.
' Used by the renderer AND by modMeasure, so a measured width can never
' disagree with what is drawn.
'-----------------------------------------------------------------------------
Public Sub WriteCellText(rng As Range, ByVal text As String, _
        ByVal role As String, ByVal directFormat As Boolean)
    rng.Text = TransformedCellText(text, role)
    ApplyGramGlossRuns rng, text, role, directFormat
End Sub

'-----------------------------------------------------------------------------
' The text as it will appear on the page.
'
' Grammatical segments are LOWERCASED, because Word's small-caps attribute only
' affects lowercase letters: "ERG" under small caps renders as full-size
' capitals, "erg" renders as the small capitals that Leipzig asks for.  The
' character style records which runs were transformed, so modReadBack can put the
' capitals back -- the change is reversible, not lossy.
'
' A user who would rather keep their capitals as typed can turn this off in the
' settings; then the style still marks the runs but the text is untouched.
'-----------------------------------------------------------------------------
Public Function TransformedCellText(ByVal text As String, ByVal role As String) As String
    Dim parts() As String, nParts As Long, i As Long, out As String

    If Not TierTakesSmallCaps(role) Then
        TransformedCellText = text
        Exit Function
    End If
    If Not SettingLowercaseGramGloss() Then
        TransformedCellText = text
        Exit Function
    End If

    nParts = SplitGlossSegments(text, parts)
    For i = 0 To nParts - 1
        If IsGramGloss(parts(i)) Then
            out = out & LCase$(parts(i))
        Else
            out = out & parts(i)
        End If
    Next i
    TransformedCellText = out
End Function

'-----------------------------------------------------------------------------
' Apply the grammatical-gloss character style (or direct small caps, when
' measuring) to each grammatical segment of a cell.
'
' Offsets are computed over the TRANSFORMED text, which is what is actually in
' the range.  Lowercasing never changes a string's length in VBA, so the segment
' boundaries line up either way, but the transformed text is used regardless so
' the two can never drift.
'-----------------------------------------------------------------------------
Public Sub ApplyGramGlossRuns(rng As Range, ByVal sourceText As String, _
        ByVal role As String, ByVal directFormat As Boolean)

    Dim parts() As String, nParts As Long, i As Long
    Dim offset As Long, segLen As Long
    Dim sub_ As Range
    Dim doc As Document

    If Not TierTakesSmallCaps(role) Then Exit Sub
    If Len(sourceText) = 0 Then Exit Sub

    Set doc = rng.Document
    nParts = SplitGlossSegments(sourceText, parts)

    offset = 0
    For i = 0 To nParts - 1
        segLen = Len(parts(i))
        If segLen > 0 Then
            If IsGramGloss(parts(i)) Then
                Set sub_ = rng.Duplicate
                On Error Resume Next
                sub_.SetRange rng.Start + offset, rng.Start + offset + segLen
                If directFormat Then
                    sub_.Font.SmallCaps = True
                Else
                    sub_.Style = doc.Styles(STYLE_GRAM)
                End If
                Err.Clear
                On Error GoTo 0
            End If
            offset = offset + segLen
        End If
    Next i
End Sub

'-----------------------------------------------------------------------------
' Split a gloss cell into segments, keeping the delimiters as segments of their
' own so they can be reassembled unchanged.
'
' Splits on the morpheme boundaries AND on Leipzig rule 4's "." and ":" and on
' ";", because "follow.CMP" is one morpheme whose gloss has a lexical part and a
' grammatical part, and only the grammatical part takes small caps.
'
' Port of the segmentation inside docs\core.js wrapGlosses.
' Returns the number of segments; parts is filled by reference.
'-----------------------------------------------------------------------------
Public Function SplitGlossSegments(ByVal text As String, _
        ByRef parts() As String) As Long

    Dim i As Long, n As Long, ch As String, cur As String

    ReDim parts(0 To Len(text) * 2 + 1)
    n = 0
    cur = ""

    For i = 1 To Len(text)
        ch = Mid$(text, i, 1)
        If IsBoundary(ch) Or ch = "." Or ch = ":" Or ch = ";" Then
            If cur <> "" Then
                parts(n) = cur
                n = n + 1
                cur = ""
            End If
            parts(n) = ch
            n = n + 1
        Else
            cur = cur & ch
        End If
    Next i
    If cur <> "" Then
        parts(n) = cur
        n = n + 1
    End If

    SplitGlossSegments = n
End Function


'=============================================================================
' -- FREE TRANSLATIONS ------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Write the free translations as paragraphs after the table, in single quotes,
' matching the convention the superseded LibreOffice and Word macros used.
'-----------------------------------------------------------------------------
Private Sub WriteFreeLines(ex As IgtExample, tbl As Table, doc As Document)
    Dim i As Long
    Dim s As String
    Dim after As Range

    If ex.FreeCount = 0 Then Exit Sub

    ' Built as one string and inserted once.  Inserting paragraph by paragraph
    ' immediately after a table is fragile -- Word already keeps a paragraph there,
    ' and it is easy to end up writing into that one instead of the new one.
    For i = 0 To ex.FreeCount - 1
        s = s & LeftSingleQuote & ex.FreeLines(i) & RightSingleQuote & vbCr
    Next i

    Set after = doc.Range(tbl.Range.End, tbl.Range.End)
    after.InsertBefore s
    ' InsertBefore grows the range over what it inserted, so this styles exactly
    ' the paragraphs just added and nothing else.
    ApplyParaStyle after, doc, ROLE_FREE
End Sub

'-----------------------------------------------------------------------------
' Take the free-translation paragraphs that follow a table back into the model,
' so a re-wrap rewrites them instead of leaving duplicates behind.
' Recognised purely by their paragraph style, like everything else here.
'-----------------------------------------------------------------------------
Public Sub AbsorbFreeParagraphs(ByRef ex As IgtExample, tbl As Table)
    Dim para As Paragraph
    Dim guard As Long

    ex.FreeCount = 0
    Set para = ParagraphAfterTable(tbl)

    Do While Not para Is Nothing
        guard = guard + 1
        If guard > 64 Then Exit Do             ' nothing legitimate runs this long
        If Not IsFreeParagraph(para) Then Exit Do
        AddFreeLine ex, StripQuotes(ParaText(para))
        Set para = NextParagraph(para)
    Loop
End Sub

'-----------------------------------------------------------------------------
' Delete a table together with the free-translation paragraphs that belong to it.
' Public because both the re-wrap path here and the commands in modLingTeX need
' it, and two copies of "how much of the document is this example" would be a
' good way to leave a stray translation behind.
'-----------------------------------------------------------------------------
Public Sub DeleteTableAndFreeLines(tbl As Table)
    Dim para As Paragraph
    Dim guard As Long

    If tbl Is Nothing Then Exit Sub

    ' The translations come first: deleting the table would invalidate the
    ' position they are found from.
    Do
        guard = guard + 1
        If guard > 64 Then Exit Do
        Set para = ParagraphAfterTable(tbl)
        If para Is Nothing Then Exit Do
        If Not IsFreeParagraph(para) Then Exit Do
        para.Range.Delete
    Loop

    tbl.Delete
End Sub

' The paragraph immediately after a table, in O(1).  Walking
' Document.Paragraphs to find it is O(n), and doing that inside a loop over
' every example in the document is O(n squared) -- slow enough to notice on a
' long grammar.
Private Function ParagraphAfterTable(tbl As Table) As Paragraph
    Dim doc As Document
    Dim endPos As Long
    On Error Resume Next
    Set doc = tbl.Range.Document
    endPos = tbl.Range.End
    If endPos >= doc.Content.End Then Exit Function
    Set ParagraphAfterTable = doc.Range(endPos, endPos).Paragraphs(1)
    Err.Clear
    On Error GoTo 0
End Function

Private Function NextParagraph(para As Paragraph) As Paragraph
    On Error Resume Next
    Set NextParagraph = para.Next
    Err.Clear
    On Error GoTo 0
End Function

Private Function IsFreeParagraph(para As Paragraph) As Boolean
    Dim nm As String
    On Error Resume Next
    If para.Range.Information(wdWithInTable) Then Exit Function
    nm = para.Style
    On Error GoTo 0
    IsFreeParagraph = (nm = ParaStyleName(ROLE_FREE))
End Function

Private Function ParaText(para As Paragraph) As String
    Dim s As String
    s = para.Range.Text
    ' Drop the trailing paragraph mark.
    Do While Len(s) > 0
        If Right$(s, 1) = vbCr Or Right$(s, 1) = vbLf Or Right$(s, 1) = Chr$(7) Then
            s = Left$(s, Len(s) - 1)
        Else
            Exit Do
        End If
    Loop
    ParaText = s
End Function

Private Function StripQuotes(ByVal s As String) As String
    s = Trim$(s)
    If Len(s) >= 2 Then
        If Left$(s, 1) = LeftSingleQuote And Right$(s, 1) = RightSingleQuote Then
            s = Mid$(s, 2, Len(s) - 2)
        ElseIf Left$(s, 1) = "'" And Right$(s, 1) = "'" Then
            s = Mid$(s, 2, Len(s) - 2)
        End If
    End If
    StripQuotes = s
End Function
