Attribute VB_Name = "modWrap"
Option Explicit

'=============================================================================
' modWrap  --  LingTeX-Word
'
' The wrap planner.  Given the rendered width of each alignment column and the
' usable text width, decide which column each wrap line starts at.
'
' THIS MODULE TOUCHES NO WORD OBJECTS.  It takes arrays in and returns an array
' out, which is what makes it the one part of the layout engine that
' modTests.bas can test exhaustively without a document on screen.  Keep it
' that way: measurement belongs in modMeasure, drawing in modRender.
'
' Hand port of ..\tools\reference.js (noBreakFlags, computeWrapLines,
' wrapRanges), which is covered by ..\tools\parity-test.js.
' IF YOU CHANGE AN ALGORITHM HERE, CHANGE IT THERE TOO.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-----------------------------------------------------------------------------
' Flag the columns a wrap line must not start on.
'
' A column whose interlinear cells begin with a morpheme boundary character is a
' continuation of the column before it, so starting a line there would split a
' word across two lines.  This one flag is why a morpheme-aligned example still
' wraps at word boundaries even though nothing in this add-in knows what a word
' is -- the knowledge lives in the data, as a leading "-" or "=", not in the
' code.  A column holding a single attaching punctuation mark gets the same
' treatment, so a stray comma never begins a line.
'
' Free-translation rows are ignored: they are prose, not aligned slots.
'-----------------------------------------------------------------------------
Public Function NoBreakFlags(ex As IgtExample) As Boolean()
    Dim flags() As Boolean
    Dim c As Long, t As Long
    Dim cell As String, flag As Boolean

    If ex.ColCount = 0 Then
        ReDim flags(0 To 0)
        NoBreakFlags = flags
        Exit Function
    End If

    ReDim flags(0 To ex.ColCount - 1)

    For c = 0 To ex.ColCount - 1
        flag = False
        For t = 0 To ex.TierCount - 1
            If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier
            cell = ex.Cells(t, c)
            If cell = "" Then GoTo NextTier
            If LeadChar(cell) <> "" Then
                flag = True
                Exit For
            ElseIf IsAttachPunct(cell) Then
                flag = True
                Exit For
            End If
NextTier:
        Next t
        ' Column 0 can never be a continuation: there is nothing before it.
        flags(c) = (c > 0 And flag)
    Next c

    NoBreakFlags = flags
End Function

'-----------------------------------------------------------------------------
' Greedy first-fit wrap.  Returns the starting column index of each wrap line.
'
' The plan is recomputed from the FULL column list on every re-wrap and never
' diffed against the layout already on the page.  That is the whole trick: it
' means pulling columns back up after the margins widen, the font shrinks, or
' columns are deleted needs no separate code path and no special cases, and any
' number of wrap lines works.  Do not turn this into an incremental differ --
' the symmetry is the feature.
'
' colWidths     rendered width of each column, in points, including its gap
' noBreakBefore from NoBreakFlags
' availWidth    usable text width, in points
' firstIndent   indent of the first wrap line
' contIndent    indent of every later wrap line
'-----------------------------------------------------------------------------
Public Function ComputeWrapLines(colWidths() As Double, noBreakBefore() As Boolean, _
        ByVal availWidth As Double, ByVal firstIndent As Double, _
        ByVal contIndent As Double) As Long()

    Dim lines() As Long, nLines As Long
    Dim n As Long, i As Long, j As Long, k As Long
    Dim cur As Long, curW As Double, budget As Double

    n = UBound(colWidths) - LBound(colWidths) + 1
    If n <= 0 Then
        ReDim lines(-1 To -1)
        ComputeWrapLines = lines
        Exit Function
    End If

    ReDim lines(0 To n - 1)
    nLines = 0
    cur = 0
    curW = colWidths(0)

    For i = 1 To n - 1
        If nLines = 0 Then
            budget = availWidth - firstIndent
        Else
            budget = availWidth - contIndent
        End If

        If curW + colWidths(i) <= budget Then
            curW = curW + colWidths(i)
        Else
            ' Back up past any column that must not start a line, so a word is
            ' carried down whole rather than broken at a morpheme boundary.
            k = i
            Do While k > cur
                If Not noBreakBefore(k) Then Exit Do
                k = k - 1
            Loop
            ' If backing up all the way would leave this line empty, break at i
            ' after all: a single unit wider than the budget has to overflow and
            ' wrap inside its own cell, which is the only sane option.
            If k = cur Then k = i

            lines(nLines) = cur
            nLines = nLines + 1
            cur = k
            curW = 0
            For j = cur To i
                curW = curW + colWidths(j)
            Next j
        End If
    Next i

    lines(nLines) = cur
    nLines = nLines + 1

    ReDim Preserve lines(0 To nLines - 1)
    ComputeWrapLines = lines
End Function

' Last column index of the wrap line starting at lineStarts(idx).
Public Function WrapLineEnd(lineStarts() As Long, ByVal idx As Long, _
        ByVal colCount As Long) As Long
    If idx < UBound(lineStarts) Then
        WrapLineEnd = lineStarts(idx + 1) - 1
    Else
        WrapLineEnd = colCount - 1
    End If
End Function

' Widest wrap line, in columns -- the cell count the table must be created with.
Public Function MaxColumnsPerLine(lineStarts() As Long, ByVal colCount As Long) As Long
    Dim i As Long, w As Long
    For i = LBound(lineStarts) To UBound(lineStarts)
        w = WrapLineEnd(lineStarts, i, colCount) - lineStarts(i) + 1
        If w > MaxColumnsPerLine Then MaxColumnsPerLine = w
    Next i
End Function

'-----------------------------------------------------------------------------
' Per-column width: the widest cell in the column across the interlinear tiers,
' plus the inter-column gap.  Free rows are excluded -- a translation is laid
' out as a paragraph under the table, not as a column.
'
' cellWidths is (tierIndex, columnIndex), as produced by modMeasure.
'-----------------------------------------------------------------------------
Public Function ColumnWidths(ex As IgtExample, cellWidths() As Double, _
        ByVal gap As Double) As Double()

    Dim widths() As Double
    Dim c As Long, t As Long, w As Double

    If ex.ColCount = 0 Then
        ReDim widths(0 To 0)
        ColumnWidths = widths
        Exit Function
    End If

    ReDim widths(0 To ex.ColCount - 1)
    For c = 0 To ex.ColCount - 1
        w = 0
        For t = 0 To ex.TierCount - 1
            If IsInterlinearTier(ex.Tiers(t)) Then
                If cellWidths(t, c) > w Then w = cellWidths(t, c)
            End If
        Next t
        widths(c) = w + gap
    Next c

    ColumnWidths = widths
End Function
