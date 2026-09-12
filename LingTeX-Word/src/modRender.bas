Attribute VB_Name = "modRender"
Option Explicit

' Word's hard limit on table columns. Tables.Add raises rather than clamping, so
' the plan is checked against it before anything is drawn.
Private Const MAX_TABLE_COLUMNS As Long = 63

' Why the last render or re-wrap gave up, for callers that report to the user.
' Empty after a successful one.
Public gRenderError As String

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
'
' THE NUMBER is a first column. When the document numbers its examples, every
' row gets one extra cell in front, as wide as the number hang; the first row's
' holds an empty paragraph in the LingTeX Example style, which is linked to the
' LingTeX Example Number list style, so it shows "(1)" by Word's own numbering
' -- on the vernacular line, where a linguist expects it, and travelling with
' the example when it is moved. The other rows' number cells are empty; on
' later wrap lines they are widened by the continuation indent. Nothing in that
' column is content: modReadBack skips it (NumberColumns), and the translation
' is indented past it.
'
' THE EXAMPLE'S INDENT is its rows' left indent (ExampleIndent), which a re-wrap
' reads and reproduces and the indent commands step. A fresh example takes the
' indent of the paragraph it is inserted into.
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
    Dim colW() As Double
    Dim lineStarts() As Long
    Dim interTiers() As Long, nInter As Long
    Dim nLines As Long, maxCols As Long
    Dim why As String
    Dim indent As Double, numW As Double, level As Long

    Set doc = target.Document
    ' A fresh example is numbered if the document says so: a number column as
    ' wide as the NumberHang setting. It sits where the paragraph it replaces
    ' sat, so an example inserted in an indented paragraph is indented too.
    indent = ParagraphIndentAt(target)
    level = SettingNumberLevel(doc)
    numW = 0
    If SettingNumberExamples(doc) Then
        EnsureStyles doc
        numW = SettingNumberHang(doc)
    End If
    If Not PlanExample(ex, target, doc, interTiers, nInter, colW, _
                       lineStarts, nLines, maxCols, why, indent + numW) Then
        gRenderError = why
        Exit Function
    End If

    Set RenderExample = DrawExample(ex, target, doc, interTiers, nInter, _
                                    colW, lineStarts, nLines, maxCols, _
                                    indent, numW, level, "")
End Function

' The left indent of the paragraph an example is being inserted into; 0 inside
' a table cell, where the cell is the container.
Private Function ParagraphIndentAt(target As Range) As Double
    Dim v As Double
    On Error Resume Next
    If target.Information(wdWithInTable) Then Exit Function
    v = target.Paragraphs(1).LeftIndent
    If Err.Number = 0 And v > 0 Then ParagraphIndentAt = v
    Err.Clear
    On Error GoTo 0
End Function

'-----------------------------------------------------------------------------
' Work out the layout without touching the document.
'
' Split out from the drawing for one reason: RewrapTable has to delete the old
' table before it can draw the new one in its place, and everything that is
' likely to fail lives in here -- measurement, the wrap plan, the column count.
' Running all of it BEFORE the delete means a failure costs nothing, where it used
' to cost the user their example.
'
' Returns False with a reason in why, and in that case nothing in the document has
' been read except its page geometry.
'-----------------------------------------------------------------------------
Private Function PlanExample(ex As IgtExample, target As Range, doc As Document, _
        ByRef interTiers() As Long, ByRef nInter As Long, _
        ByRef colW() As Double, ByRef lineStarts() As Long, _
        ByRef nLines As Long, ByRef maxCols As Long, _
        ByRef why As String, ByVal hang As Double) As Boolean

    Dim cellWidths() As Double
    Dim flags() As Boolean
    Dim avail As Double, gap As Double, contIndent As Double

    why = ""
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        why = "the example has no tiers or no columns"
        Exit Function
    End If

    EnsureStyles doc
    If gStyleError <> "" Then
        ' A style name collided with a style of the wrong kind. Drawing now would
        ' produce rows with no role on them, which read back as one giant wrap
        ' line -- a confusing result from a nameable cause.
        why = gStyleError
        Exit Function
    End If

    nInter = InterlinearTierList(ex, interTiers)
    If nInter = 0 Then
        why = "the example has no interlinear tiers, only free translations"
        Exit Function
    End If

    gap = SettingGap(doc)
    contIndent = SettingContIndent(doc)
    ' The full text width: the example's own indent and number column are hang,
    ' subtracted below, and the anchor paragraph's indent must not be subtracted
    ' as well -- on a re-wrap the anchor is the translation, whose indent is
    ' hang, which used to come off twice.
    avail = AvailableTextWidth(target, True)

    MeasureExample ex, doc, cellWidths
    If gMeasureFailed Then
        ' Zero widths would make roughly 78 columns "fit" a 468-point line, which
        ' is how this used to end up asking Word for more columns than a table can
        ' have. Stop here instead, while stopping is still free.
        why = "the text could not be measured: " & gMeasureError
        Exit Function
    End If

    colW = ColumnWidths(ex, cellWidths, gap)
    ' hang is the example's indent plus its number column: where the content of
    ' every wrap line starts.
    flags = NoBreakFlags(ex)
    lineStarts = ComputeWrapLines(colW, flags, avail, hang, contIndent + hang)

    nLines = UBound(lineStarts) - LBound(lineStarts) + 1

    ' An over-wide column. The planner's contract is to give it a wrap line of
    ' its own and let it overflow; the drawing's is not to run off the page.
    ' Capped at the room its line has, the cell wraps its text inside itself
    ' instead (found by hand, 2026-09-12: a 60-character form ran past the margin
    ' and off the page, because SetWidth was given the full measured width).
    CapColumnWidths colW, lineStarts, nLines, ex.ColCount, avail - hang, contIndent

    maxCols = MaxColumnsPerLine(lineStarts, ex.ColCount)
    If maxCols < 1 Then
        why = "the wrap planner produced no columns"
        Exit Function
    End If
    If maxCols > MAX_TABLE_COLUMNS Then
        ' A Word table cannot have more than 63 columns, and Tables.Add raises
        ' rather than clamping. With working measurement this is unreachable --
        ' 63 columns is over 370 points of inter-column gap alone, before any text
        ' -- so reaching it means something upstream is wrong, and saying so is
        ' more use than a truncated table.
        why = "one wrap line needs " & CStr(maxCols) & " columns; a Word table " & _
              "cannot have more than " & CStr(MAX_TABLE_COLUMNS)
        Exit Function
    End If

    PlanExample = True
End Function

'-----------------------------------------------------------------------------
' Draw the planned layout.  Everything here mutates the document.
'-----------------------------------------------------------------------------
' No column may be wider than the line it sits on. Only an over-wide column
' alone on its line can be, so this changes nothing for a normal example.
Private Sub CapColumnWidths(ByRef colW() As Double, lineStarts() As Long, _
        ByVal nLines As Long, ByVal nCols As Long, _
        ByVal avail As Double, ByVal contIndent As Double)

    Dim g As Long, c As Long
    Dim lineFirst As Long, lineLast As Long
    Dim room As Double

    For g = 0 To nLines - 1
        lineFirst = lineStarts(g)
        lineLast = WrapLineEnd(lineStarts, g, nCols)
        room = avail
        If g > 0 Then room = avail - contIndent
        If room < 36 Then room = 36
        For c = lineFirst To lineLast
            If colW(c) > room Then colW(c) = room
        Next c
    Next g
End Sub

' Measure an example that is already on the page, so its widths are in the
' cache before an undo record opens (see modLingTeX.BeginUndo). Failure is
' silent: the re-wrap that follows measures again and reports its own.
Public Sub WarmMeasureCache(tbl As Table)
    Dim ex As IgtExample
    Dim widths() As Double
    On Error Resume Next
    ex = ReadExampleFromTable(tbl)
    If ex.TierCount > 0 And ex.ColCount > 0 Then
        MeasureExample ex, tbl.Range.Document, widths
    End If
    Err.Clear
    On Error GoTo 0
End Sub

Private Function DrawExample(ex As IgtExample, target As Range, doc As Document, _
        interTiers() As Long, ByVal nInter As Long, _
        colW() As Double, lineStarts() As Long, _
        ByVal nLines As Long, ByVal maxCols As Long, _
        ByVal indent As Double, ByVal numW As Double, ByVal level As Long, _
        ByVal numText As String) As Table

    Dim tbl As Table
    Dim anchor As Range
    Dim nNum As Long

    If numW > 0 Then nNum = 1

    Set anchor = target.Duplicate
    StartPendingUndo                       ' the first change to the document
    anchor.Text = ""                       ' clear whatever we are replacing

    Set tbl = doc.Tables.Add(Range:=anchor, _
                             NumRows:=nLines * nInter, NumColumns:=maxCols + nNum)
    StyleTable tbl, doc

    gRenderError = ""
    FillTable tbl, ex, interTiers, nInter, lineStarts, colW, doc, indent, numW
    If nNum = 1 Then NumberFirstCell tbl, doc, level, numText

    '-- free translations, after the table ----------------------------------
    ' Written BEFORE the row keeps, so SetRowKeeps can see the first translation
    ' paragraph and keep the last row of the table with it. Done the other way
    ' round, a page break can fall between an example and its translation.
    WriteFreeLines ex, tbl, doc, indent + numW
    SetRowKeeps tbl, (ex.FreeCount > 0)

    ' Numbering never belongs in a content cell; a paragraph that carried list
    ' formatting can leak it into the first one when the table is added there.
    StripStrayNumber tbl, 1 + nNum

    Set DrawExample = tbl
End Function

'-----------------------------------------------------------------------------
' Number the example: the first row's first cell gets the LingTeX Example
' paragraph, numbered by the list style it is linked to (or by the template
' applied directly when the link could not be made), at the list level asked
' for. Whatever numbering leaked into the cell from the paragraph the table
' was added in goes first. The paragraph's own indents are zeroed, because a
' list level's indents (a text position of 36pt in a 36pt cell) would push
' the number onto a second line. Text a user had typed after the number
' (numText, read back before a re-wrap) is written back.
'-----------------------------------------------------------------------------
Private Sub NumberFirstCell(tbl As Table, doc As Document, ByVal level As Long, _
        ByVal numText As String)
    Dim rng As Range
    Dim para As Paragraph

    On Error Resume Next
    Set rng = tbl.Cell(1, 1).Range
    rng.End = rng.End - 1
    rng.ListFormat.RemoveNumbers
    rng.Style = doc.Styles(STYLE_EXAMPLE)
    Set para = rng.Paragraphs(1)
    Err.Clear
    On Error GoTo 0
    If para Is Nothing Then Exit Sub

    ApplyNumberToParagraph para, doc, level

    On Error Resume Next
    With para.Format
        .LeftIndent = 0
        .FirstLineIndent = 0
        .SpaceBefore = 0
        .SpaceAfter = 0
    End With
    If numText <> "" Then rng.Text = numText
    Err.Clear
    On Error GoTo 0
End Sub

' Make sure the paragraph is numbered: the style's link does it when the link
' could be made; otherwise the list template is applied here, continuing the
' previous example's list. A level above 1 is set on the paragraph.
Private Sub ApplyNumberToParagraph(para As Paragraph, doc As Document, ByVal level As Long)
    Dim tpl As Object
    On Error Resume Next
    If para.Range.ListFormat.ListType = wdListNoNumbering Then
        Set tpl = doc.Styles(STYLE_NUMBER).ListTemplate
        If tpl Is Nothing Then
            gRenderError = "the example could not be numbered: the list style " & _
                           STYLE_NUMBER & " is missing"
            Err.Clear
            Exit Sub
        End If
        para.Range.ListFormat.ApplyListTemplate ListTemplate:=tpl, ContinuePreviousList:=True
    End If
    If level > 1 Then para.Range.ListFormat.ListLevelNumber = level
    If Err.Number <> 0 Then
        gRenderError = "the example could not be numbered (" & CStr(Err.Number) & _
                       ": " & Err.Description & ")"
        Err.Clear
    End If
    On Error GoTo 0
End Sub

' The number-cell paragraph of a numbered example, or Nothing.
Public Function NumberParagraphOf(tbl As Table) As Paragraph
    On Error Resume Next
    If Not HasNumberColumn(tbl) Then Exit Function
    Set NumberParagraphOf = tbl.Cell(1, 1).Range.Paragraphs(1)
    Err.Clear
    On Error GoTo 0
End Function

' The number line of the EARLIER design: a paragraph in the LingTeX Example
' style immediately above the table. Still recognised so that an example drawn
' before the number moved into the table is migrated by its next re-wrap
' (RedrawExampleAt) instead of being numbered twice.
Public Function LegacyNumberLineOf(tbl As Table) As Paragraph
    Dim doc As Document
    Dim para As Paragraph
    Dim startPos As Long

    On Error Resume Next
    Set doc = tbl.Range.Document
    startPos = tbl.Range.Start
    If startPos <= 0 Then Exit Function
    Set para = doc.Range(startPos - 1, startPos - 1).Paragraphs(1)
    If para Is Nothing Then Exit Function
    If para.Range.Information(wdWithInTable) Then Exit Function
    If para.Style = STYLE_EXAMPLE Then Set LegacyNumberLineOf = para
    Err.Clear
    On Error GoTo 0
End Function

' The number an example shows, e.g. "(3)"; empty when it is not numbered.
Public Function ExampleNumberString(tbl As Table) As String
    Dim para As Paragraph
    On Error Resume Next
    Set para = NumberParagraphOf(tbl)
    If para Is Nothing Then Set para = LegacyNumberLineOf(tbl)
    If para Is Nothing Then Exit Function
    If para.Range.ListFormat.ListType <> wdListNoNumbering Then
        ExampleNumberString = para.Range.ListFormat.ListString
    End If
    Err.Clear
    On Error GoTo 0
End Function

' The list level a numbered paragraph is on, or dflt when it is not numbered.
Private Function ListLevelOf(para As Paragraph, ByVal dflt As Long) As Long
    Dim v As Long
    ListLevelOf = dflt
    If para Is Nothing Then Exit Function
    On Error Resume Next
    If para.Range.ListFormat.ListType <> wdListNoNumbering Then
        v = para.Range.ListFormat.ListLevelNumber
        If Err.Number = 0 And v >= 1 And v <= 9 Then ListLevelOf = v
    End If
    Err.Clear
    On Error GoTo 0
End Function

' Where an example starts: its first row's left indent. What the indent
' commands step and a re-wrap keeps.
Public Function ExampleIndent(tbl As Table) As Double
    Dim v As Double
    On Error Resume Next
    v = tbl.Rows(1).LeftIndent
    If Err.Number = 0 And v > 0 Then ExampleIndent = v
    Err.Clear
    On Error GoTo 0
End Function

' Remove an example whole: table, translations, and a legacy number line.
Public Sub DeleteExample(tbl As Table)
    Dim numPara As Paragraph
    If tbl Is Nothing Then Exit Sub
    Set numPara = LegacyNumberLineOf(tbl)
    DeleteTableAndFreeLines tbl
    On Error Resume Next
    If Not numPara Is Nothing Then numPara.Range.Delete
    Err.Clear
    On Error GoTo 0
End Sub

' Numbering never belongs in a content cell: a paragraph that carried list
' numbering can leak it into the first cell when the table is added there.
' Take it off the first content cell (the cell after the number column).
Private Sub StripStrayNumber(tbl As Table, ByVal firstContent As Long)
    Dim rng As Range
    On Error Resume Next
    If tbl.Cell(1, firstContent).Range.ListFormat.ListType <> wdListNoNumbering Then
        Set rng = tbl.Cell(1, firstContent).Range
        rng.End = rng.End - 1
        rng.ListFormat.RemoveNumbers
    End If
    Err.Clear
    On Error GoTo 0
End Sub

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

    gRenderError = ""
    If tbl Is Nothing Then Exit Function

    ex = ReadExampleFromTable(tbl)
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        gRenderError = "the table could not be read as an interlinear example"
        Exit Function
    End If

    ' Absorb the free-translation paragraphs that belong to this example, so they
    ' are rewritten rather than duplicated.
    AbsorbFreeParagraphs ex, tbl

    Set RewrapTable = RedrawExampleAt(tbl, ex)
End Function

'-----------------------------------------------------------------------------
' Replace the table (and its translations) with a fresh drawing of ex. The one
' definition of "delete and redraw", used by re-wrap, split, merge and fix.
'
' PLAN BEFORE DELETING. Re-wrapping cannot draw the new table until the old one
' is gone, so a failure after the delete destroys the user's example -- and in
' RewrapDocument and the selection-change handler that raise is swallowed, so it
' destroys it silently. Planning first means every failure that can be
' anticipated is found while the table is still on the page. It is also what
' keeps the undo record whole: planning measures, measuring touches the hidden
' scratch document, and the record must not open until that is done (see
' modLingTeX.BeginUndo). So: plan, open the record, delete, draw.
'
' Planned against the paragraph AFTER the table, never against tbl.Range.
' AvailableTextWidth treats a range inside a table as "the cell is the
' container" and returns that cell's width -- correct when inserting into a
' cell, and exactly wrong here, where it made every re-wrap plan against a few
' points of budget.
'-----------------------------------------------------------------------------
Public Function RedrawExampleAt(tbl As Table, ex As IgtExample) As Table
    Dim doc As Document
    Dim anchor As Range
    Dim startPos As Long
    Dim colW() As Double
    Dim lineStarts() As Long
    Dim interTiers() As Long, nInter As Long
    Dim nLines As Long, maxCols As Long
    Dim why As String
    Dim indent As Double, numW As Double, level As Long
    Dim numText As String
    Dim numPara As Paragraph, legacy As Paragraph

    gRenderError = ""
    If tbl Is Nothing Then Exit Function
    Set doc = tbl.Range.Document

    ' What the example is, before anything is touched: numbered or not (and on
    ' which list level, with what typed after the number), and how far it is
    ' indented. A numbered example keeps its number; the column's width comes
    ' from the setting, so changing NumberHang reaches every example on its
    ' next re-wrap.
    indent = ExampleIndent(tbl)
    level = SettingNumberLevel(doc)
    numW = 0
    Set numPara = NumberParagraphOf(tbl)
    If Not numPara Is Nothing Then
        numW = SettingNumberHang(doc)
        level = ListLevelOf(numPara, level)
        numText = Trim$(ParaText(numPara))
    Else
        ' The earlier design, a number line above the table: the number moves
        ' into the table, the line goes, and the example's indent is where the
        ' line's number stood (its left indent less the hanging part).
        Set legacy = LegacyNumberLineOf(tbl)
        If Not legacy Is Nothing Then
            numW = SettingNumberHang(doc)
            level = ListLevelOf(legacy, level)
            numText = Trim$(ParaText(legacy))
            On Error Resume Next
            indent = legacy.LeftIndent + legacy.FirstLineIndent
            Err.Clear
            On Error GoTo 0
            If indent < 0 Then indent = 0
        End If
    End If

    If Not PlanExample(ex, RangeAfterTable(tbl), doc, interTiers, nInter, colW, _
                       lineStarts, nLines, maxCols, why, indent + numW) Then
        gRenderError = why
        Exit Function                      ' table untouched
    End If

    startPos = tbl.Range.Start
    If Not legacy Is Nothing Then startPos = legacy.Range.Start
    StartPendingUndo                       ' the first change to the document
    DeleteTableAndFreeLines tbl
    If Not legacy Is Nothing Then
        On Error Resume Next
        legacy.Range.Delete
        Err.Clear
        On Error GoTo 0
    End If

    Set anchor = doc.Range(startPos, startPos)

    ' Past this point the old table is gone, so a failure here has to leave the
    ' content behind in SOME form rather than nothing at all.
    On Error GoTo DrawFailed
    Set RedrawExampleAt = DrawExample(ex, anchor, doc, interTiers, nInter, _
                                      colW, lineStarts, nLines, maxCols, _
                                      indent, numW, level, numText)
    Exit Function

DrawFailed:
    gRenderError = "drawing failed after the old table was removed (" & _
                   CStr(Err.Number) & ": " & Err.Description & _
                   "); the example was written back as tab-separated text"
    On Error Resume Next
    doc.Range(startPos, startPos).InsertBefore ModelToTsv(ex) & vbCr
    Err.Clear
    On Error GoTo 0
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
        ByVal nInter As Long, lineStarts() As Long, colW() As Double, doc As Document, _
        ByVal indent As Double, ByVal numW As Double)

    Dim g As Long, i As Long, c As Long, r As Long
    Dim lineFirst As Long, lineLast As Long, lineCols As Long
    Dim nLines As Long, maxCols As Long
    Dim surplus As Long, k As Long
    Dim role As String
    Dim cellRng As Range
    Dim lineGap As Double
    Dim contIndent As Double
    Dim nNum As Long
    Dim numCellW As Double

    nLines = UBound(lineStarts) - LBound(lineStarts) + 1
    maxCols = MaxColumnsPerLine(lineStarts, ex.ColCount)
    lineGap = SettingLineGap(doc)
    contIndent = SettingContIndent(doc)
    If numW > 0 Then nNum = 1

    For g = 0 To nLines - 1
        lineFirst = lineStarts(g)
        lineLast = WrapLineEnd(lineStarts, g, ex.ColCount)
        lineCols = lineLast - lineFirst + 1

        For i = 0 To nInter - 1
            r = g * nInter + i + 1                 ' Word rows are 1-based
            role = ex.Tiers(interTiers(i))

            ' Trim this row down to the columns this wrap line actually holds.
            ' Deleting from the left-most surplus position repeatedly works because
            ' Word shifts the remaining cells left each time.
            surplus = maxCols - lineCols
            For k = 1 To surplus
                On Error Resume Next
                ' The shift is named, not defaulted: an unspecified ShiftCells is the
                ' one path by which this could raise a "Delete Cells" question.
                tbl.Rows(r).Cells(lineCols + nNum + 1).Delete ShiftCells:=wdDeleteCellsShiftLeft
                Err.Clear
                On Error GoTo 0
            Next k

            ' Verified, because the deletions above were swallowed one at a time:
            ' a row that kept its surplus cells gets text and an explicit width on
            ' only the first lineCols of them, and Word distributes the rest as it
            ' sees fit -- so the row is wider than the plan and the example runs
            ' past the margin. Recorded rather than raised, so the rest of the
            ' example still draws and the reason is reportable.
            If Not RowHasCells(tbl, r, lineCols + nNum) Then
                gRenderError = "could not trim row " & CStr(r) & " to " & _
                               CStr(lineCols) & " cells; the wrap line may run " & _
                               "past the right margin"
            End If

            ' The number cell: empty, as wide as the hang, widened by the
            ' continuation indent on later wrap lines so their content starts
            ' further in with the table's left edge kept straight. It takes the
            ' tier's paragraph style so it adds no height to the row; the first
            ' row's is restyled and numbered afterwards (NumberFirstCell).
            If nNum = 1 Then
                numCellW = numW
                If g > 0 Then numCellW = numW + contIndent
                On Error Resume Next
                Set cellRng = tbl.Cell(r, 1).Range
                cellRng.End = cellRng.End - 1
                ApplyParaStyle cellRng, doc, role
                tbl.Cell(r, 1).SetWidth ColumnWidth:=numCellW, RulerStyle:=wdAdjustNone
                If Err.Number <> 0 Then
                    gRenderError = "could not set the width of the number cell in row " & _
                                   CStr(r) & " (" & CStr(Err.Number) & ": " & _
                                   Err.Description & ")"
                    Err.Clear
                End If
                On Error GoTo 0
            End If

            For c = 0 To lineCols - 1
                Set cellRng = tbl.Cell(r, c + 1 + nNum).Range
                cellRng.End = cellRng.End - 1      ' exclude end-of-cell marker

                ApplyParaStyle cellRng, doc, role
                WriteCellText cellRng, ex.Cells(interTiers(i), lineFirst + c), _
                              role, False, doc

                ' The explicit per-cell width IS the layout -- there is no
                ' autofit to fall back on, AllowAutoFit being off. A swallowed
                ' failure here leaves the cell at whatever width Word chose, which
                ' breaks the one invariant the design rests on: that every row of a
                ' wrap line reports the same width for the same column, so each
                ' form sits directly above its gloss.
                On Error Resume Next
                tbl.Cell(r, c + 1 + nNum).SetWidth _
                    ColumnWidth:=colW(lineFirst + c), RulerStyle:=wdAdjustNone
                If Err.Number <> 0 Then
                    gRenderError = "could not set the width of row " & CStr(r) & _
                                   " column " & CStr(c + 1 + nNum) & " (" & _
                                   CStr(Err.Number) & ": " & Err.Description & ")"
                    Err.Clear
                End If
                On Error GoTo 0
            Next c

            ' Where the row starts: at the example's indent. Without a number
            ' column, later wrap lines go further in by the continuation indent
            ' (with one, the number cell carries it, above).
            On Error Resume Next
            If g = 0 Or nNum = 1 Then
                tbl.Rows(r).LeftIndent = indent
            Else
                tbl.Rows(r).LeftIndent = indent + contIndent
            End If
            Err.Clear
            On Error GoTo 0

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
'-----------------------------------------------------------------------------
' Stop a page break falling inside an example.
'
' Every row keeps with the next, so the wrap lines and the tiers within them stay
' together. The LAST row keeps with the next only when a free translation follows
' it: a translation stranded at the top of the following page is the same defect
' as a split example, and keepLast is what prevents it. With nothing after the
' table the last row must NOT keep, or it drags the following body paragraph along.
'-----------------------------------------------------------------------------
' Does a row have exactly this many cells?  Rows in an interlinear table are
' deliberately RAGGED -- a short wrap line is a row with fewer cells, not a row
' with empty ones -- so this is how the trimming above is confirmed.
Private Function RowHasCells(tbl As Table, ByVal r As Long, _
        ByVal want As Long) As Boolean

    Dim got As Long
    got = -1
    On Error Resume Next
    got = tbl.Rows(r).Cells.Count
    Err.Clear
    On Error GoTo 0
    RowHasCells = (got = want)
End Function

Private Sub SetRowKeeps(tbl As Table, ByVal keepLast As Boolean)
    Dim r As Long, last As Long
    On Error Resume Next
    last = tbl.Rows.Count
    For r = 1 To last
        tbl.Rows(r).Range.ParagraphFormat.KeepWithNext = (r < last) Or keepLast
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
' srcDoc is the document whose SETTINGS apply -- which is not always rng.Document.
' When measuring, rng lives in the hidden scratch document while the settings
' belong to the user's.
Public Sub WriteCellText(rng As Range, ByVal text As String, _
        ByVal role As String, ByVal directFormat As Boolean, srcDoc As Document)
    rng.Text = TransformedCellText(text, role, srcDoc)
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
Public Function TransformedCellText(ByVal text As String, ByVal role As String, _
        srcDoc As Document) As String
    Dim parts() As String, nParts As Long, i As Long, out As String
    Dim initialCap As Boolean

    If Not TierTakesSmallCaps(role) Then
        TransformedCellText = text
        Exit Function
    End If
    If Not SettingLowercaseGramGloss(srcDoc) Then
        TransformedCellText = text
        Exit Function
    End If

    initialCap = SettingGramGlossInitialCap(srcDoc)
    nParts = SplitGlossSegments(text, parts)
    For i = 0 To nParts - 1
        If IsGramGloss(parts(i)) Then
            out = out & SmallCapsForm(parts(i), initialCap)
        Else
            out = out & parts(i)
        End If
    Next i
    TransformedCellText = out
End Function

' The text stored for a grammatical gloss the small-caps style will draw. All
' lowercase, so the style renders every letter as a small capital; with
' initialCap the first LETTER stays full-size -- the first letter, not the first
' character, so 3SG becomes 3Sg and ERG becomes Erg. Length is preserved either
' way, which ApplyGramGlossRuns relies on. Read-back upper-cases the whole run,
' so both forms restore to ERG.
Private Function SmallCapsForm(ByVal part As String, ByVal initialCap As Boolean) As String
    Dim s As String, i As Long, ch As String
    s = LCase$(part)
    If initialCap Then
        For i = 1 To Len(s)
            ch = Mid$(s, i, 1)
            If LCase$(ch) <> UCase$(ch) Then
                s = Left$(s, i - 1) & UCase$(ch) & Mid$(s, i + 1)
                Exit For
            End If
        Next i
    End If
    SmallCapsForm = s
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
Private Sub WriteFreeLines(ex As IgtExample, tbl As Table, doc As Document, _
        ByVal hang As Double)
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
    ' The translation lines up with the example's text: past its indent and,
    ' when it is numbered, past the number column.
    If hang > 0 Then
        On Error Resume Next
        after.ParagraphFormat.LeftIndent = hang
        Err.Clear
        On Error GoTo 0
    End If

    ' Several translations hold together; the last one releases, so the example
    ' does not drag the following body text onto its page.
    On Error Resume Next
    after.ParagraphFormat.KeepWithNext = True
    If after.Paragraphs.Count > 0 Then
        after.Paragraphs(after.Paragraphs.Count).KeepWithNext = False
    End If
    Err.Clear
    On Error GoTo 0
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
        If Not IsTranslationParagraph(para) Then Exit Do
        AddFreeLine ex, StripQuotes(ParaText(para))
        Set para = NextParagraph(para)
    Loop
End Sub

' A paragraph that belongs to the example as one of its translations: styled
' LingTeX Free AND not empty. The empty paragraph a person gets by pressing
' Enter after a translation inherits the style, and counting it as a
' translation is how re-wrap-all deleted the second of two examples
' (2026-09-12): absorbed, then deleted, it was the only paragraph between two
' tables; they touched, Word merged them, and tbl.Delete took both. An empty
' paragraph ENDS an example.
Public Function IsTranslationParagraph(para As Paragraph) As Boolean
    If Not IsFreeParagraph(para) Then Exit Function
    IsTranslationParagraph = (Len(Trim$(ParaText(para))) > 0)
End Function

' True when the paragraph's mark is the last thing before a table.
Private Function ParagraphPrecedesTable(para As Paragraph) As Boolean
    Dim nxt As Paragraph
    On Error Resume Next
    Set nxt = para.Next
    If nxt Is Nothing Then Exit Function
    ParagraphPrecedesTable = nxt.Range.Information(wdWithInTable)
    Err.Clear
    On Error GoTo 0
End Function

'-----------------------------------------------------------------------------
' Delete a table together with the free-translation paragraphs that belong to it.
' Public because both the re-wrap path here and the commands in modLingTeX need
' it, and two copies of "how much of the document is this example" would be a
' good way to leave a stray translation behind.
'-----------------------------------------------------------------------------
Public Sub DeleteTableAndFreeLines(tbl As Table)
    Dim para As Paragraph
    Dim rng As Range
    Dim guard As Long

    If tbl Is Nothing Then Exit Sub

    ' The translations come first: deleting the table would invalidate the
    ' position they are found from.
    Do
        guard = guard + 1
        If guard > 64 Then Exit Do
        Set para = ParagraphAfterTable(tbl)
        If para Is Nothing Then Exit Do
        If Not IsTranslationParagraph(para) Then Exit Do
        If ParagraphPrecedesTable(para) Then
            ' Its paragraph mark is the only thing between this example and the
            ' next table. Removing it makes Word merge the two tables, and
            ' tbl.Delete below then takes both. The text goes; the mark stays,
            ' and the redraw writes the translation back in front of it.
            Set rng = para.Range
            rng.MoveEnd wdCharacter, -1
            If rng.End > rng.Start Then rng.Delete
            Exit Do
        End If
        para.Range.Delete
    Loop

    tbl.Delete
End Sub

' The paragraph immediately after a table, in O(1).  Walking
' Document.Paragraphs to find it is O(n), and doing that inside a loop over
' every example in the document is O(n squared) -- slow enough to notice on a
' long grammar.
' A collapsed range at the table's end: the first position outside it. Word keeps
' a paragraph after every table, so this always exists. Used wherever the page
' geometry around a table is wanted rather than the geometry of a cell in it.
Public Function RangeAfterTable(tbl As Table) As Range
    Set RangeAfterTable = tbl.Range.Document.Range(tbl.Range.End, tbl.Range.End)
End Function

' These five walk and read the paragraphs that follow a table -- the free
' translations. Public rather than Private so modDocTests can assert on THESE
' rather than on a copy of them: a test that reimplements the logic it is checking
' verifies the copy and nothing else.
Public Function ParagraphAfterTable(tbl As Table) As Paragraph
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

Public Function NextParagraph(para As Paragraph) As Paragraph
    On Error Resume Next
    Set NextParagraph = para.Next
    Err.Clear
    On Error GoTo 0
End Function

Public Function IsFreeParagraph(para As Paragraph) As Boolean
    Dim nm As String
    On Error Resume Next
    If para.Range.Information(wdWithInTable) Then Exit Function
    nm = para.Style
    On Error GoTo 0
    IsFreeParagraph = (nm = ParaStyleName(ROLE_FREE))
End Function

Public Function ParaText(para As Paragraph) As String
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

Public Function StripQuotes(ByVal s As String) As String
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
