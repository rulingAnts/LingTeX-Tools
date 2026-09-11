Attribute VB_Name = "modMeasure"
Option Explicit

'=============================================================================
' modMeasure  --  LingTeX-Word
'
' How wide is this text, in points, when Word draws it?
'
' Word exposes no text-measurement function, so the width has to be obtained by
' laying the text out and reading the result back.  Doing that in the user's own
' document would be both slow and visible, and a table wider than the page gets
' CLAMPED by autofit, which silently corrupts the measurement.  So measurement
' happens in a scratch document with a 22-inch page -- Word's maximum -- and zero
' margins, where nothing can clamp.
'
' Two methods are implemented behind one signature:
'
'   Primary (USE_AUTOFIT = True).  One table row per tier, one cell per column,
'   AutoFitBehavior wdAutoFitContent, then read Cell(1, c).Width.  This is ONE
'   Word round trip per tier rather than one per cell, which matters a lot on Mac
'   where each call into the object model is slow.
'
'   Fallback (USE_AUTOFIT = False).  One paragraph per cell, read
'   Range.Information(wdHorizontalPositionRelativeToTextBoundary) at the end of
'   the text.  Exact and immune to clamping, but O(columns x tiers) calls.
'
' If the autofit read turns out to misbehave on Mac Word, flip the constant; the
' rest of the add-in does not change.  Both are cached, so a re-wrap of text that
' has not been edited costs nothing.
'
' IMPORTANT: the text is measured with the SAME runs the renderer will draw,
' including small caps on grammatical glosses, by calling the renderer's own
' modRender.WriteCellText.  Measuring the raw source text instead would
' over-estimate, because full capitals are wider than small capitals.  Keeping a
' single routine for "put this text in this range" is what stops measurement and
' drawing from drifting apart.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-----------------------------------------------------------------------------
' IF COLUMNS COME OUT THE WRONG WIDTH, CHANGE THIS TO False AND RE-RUN.
'
' That switches from reading autofitted cell widths to reading
' Range.Information positions -- a complete second implementation of the same
' measurement, below.  It is the first thing to try before debugging anything
' else, because every column width flows from here: if the autofit read does not
' work on a given Word build, nothing downstream can look right.
'
' tools/probe/modProbe.bas reports which method works on a given install
' (section 3 for this one, section 5 for the fallback).  See QUICKSTART.md.
'-----------------------------------------------------------------------------
Private Const USE_AUTOFIT As Boolean = True

' Word's maximum page dimension is 22 inches.  Nothing an interlinear example
' contains comes close, so autofit never clamps at this width.
Private Const SCRATCH_PAGE_WIDTH_IN As Single = 22

Private mScratch As Document
Private mCache   As Collection

'-- Resolved appearance of one tier, used as part of the cache key ------------
Public Type TierFont
    Name      As String
    Size      As Single
    Bold      As Boolean
    Italic    As Boolean
    SmallCaps As Boolean
End Type


'=============================================================================
' -- AVAILABLE WIDTH --------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Usable text width at an insertion point, in points.
'
' This is the budget the wrap planner spends.  It accounts for the page, the
' margins, the binding gutter, multiple text columns, and the indents of the
' paragraph the example is being inserted into -- all of which a user can change
' after the fact, which is exactly why re-wrapping has to recompute instead of
' remembering.
'-----------------------------------------------------------------------------
Public Function AvailableTextWidth(rng As Range) As Single
    Dim w As Single
    Dim ps As PageSetup
    Dim para As Paragraph

    On Error GoTo Fallback

    ' Inside a table cell the cell is the container, not the page.
    If rng.Information(wdWithInTable) Then
        On Error Resume Next
        w = rng.Cells(1).Width
        On Error GoTo Fallback
        If w > 0 Then
            AvailableTextWidth = w
            Exit Function
        End If
    End If

    Set ps = rng.Sections(1).PageSetup
    w = ps.PageWidth - ps.LeftMargin - ps.RightMargin

    On Error Resume Next
    w = w - ps.Gutter
    If ps.TextColumns.Count > 1 Then w = ps.TextColumns(1).Width
    On Error GoTo Fallback

    Set para = rng.Paragraphs(1)
    w = w - para.LeftIndent - para.RightIndent

    If w < 36 Then w = 36                  ' never return an unusable budget
    AvailableTextWidth = w
    Exit Function

Fallback:
    ' Letter portrait with one-inch margins, as a last resort.
    AvailableTextWidth = 468
End Function


'=============================================================================
' -- TIER FONTS -------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Resolve how a tier will actually look in this document, by reading the
' paragraph style the renderer will apply.  Falls back to the document's body
' font when the style is missing, and to a named font when even that is a theme
' placeholder (theme fonts are reported as "+Body", which is not a real font).
'-----------------------------------------------------------------------------
Public Function ResolveTierFont(doc As Document, ByVal role As String) As TierFont
    Dim tf As TierFont
    Dim st As Style
    Dim styleName As String

    styleName = ParaStyleName(role)

    On Error Resume Next
    Set st = doc.Styles(styleName)
    On Error GoTo 0

    If Not st Is Nothing Then
        tf.Name = st.Font.Name
        tf.Size = st.Font.Size
        tf.Bold = (st.Font.Bold <> False)
        tf.Italic = (st.Font.Italic <> False)
        tf.SmallCaps = (st.Font.SmallCaps <> False)
    End If

    If tf.Name = "" Or Left$(tf.Name, 1) = "+" Then
        On Error Resume Next
        tf.Name = doc.Styles(wdStyleNormal).Font.Name
        If tf.Size <= 0 Then tf.Size = doc.Styles(wdStyleNormal).Font.Size
        On Error GoTo 0
    End If
    If tf.Name = "" Or Left$(tf.Name, 1) = "+" Then tf.Name = FALLBACK_FONT
    If tf.Size <= 0 Then tf.Size = 12

    ResolveTierFont = tf
End Function

Private Function FontKey(tf As TierFont) As String
    FontKey = tf.Name & "|" & CStr(tf.Size) & "|" & _
              CStr(tf.Bold) & CStr(tf.Italic) & CStr(tf.SmallCaps)
End Function


'=============================================================================
' -- CELL MEASUREMENT -------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Measure every cell of an example.  Fills widths(tier, col) with the rendered
' width in points.  Free-translation rows are measured as 0: they are laid out as
' paragraphs under the table, not as columns.
'-----------------------------------------------------------------------------
Public Sub MeasureExample(ex As IgtExample, doc As Document, ByRef widths() As Single)
    Dim t As Long, c As Long
    Dim tf As TierFont
    Dim texts() As String
    Dim rowWidths() As Single

    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Sub
    ReDim widths(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)

    For t = 0 To ex.TierCount - 1
        If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier

        tf = ResolveTierFont(doc, ex.Tiers(t))

        ReDim texts(0 To ex.ColCount - 1)
        For c = 0 To ex.ColCount - 1
            texts(c) = ex.Cells(t, c)
        Next c

        rowWidths = MeasureTexts(texts, tf, ex.Tiers(t))
        For c = 0 To ex.ColCount - 1
            widths(t, c) = rowWidths(c)
        Next c
NextTier:
    Next t
End Sub

'-----------------------------------------------------------------------------
' Measure an array of strings in one tier's appearance.  Cache hits are served
' without touching Word at all.
'-----------------------------------------------------------------------------
Public Function MeasureTexts(texts() As String, tf As TierFont, _
        ByVal role As String) As Single()

    Dim out() As Single
    Dim i As Long, n As Long
    Dim missIdx() As Long, missText() As String, nMiss As Long
    Dim key As String, w As Single
    Dim fresh() As Single

    n = UBound(texts) - LBound(texts) + 1
    ReDim out(0 To n - 1)
    If n = 0 Then
        MeasureTexts = out
        Exit Function
    End If

    EnsureCache

    ReDim missIdx(0 To n - 1)
    ReDim missText(0 To n - 1)
    nMiss = 0

    For i = 0 To n - 1
        If Trim$(texts(i)) = "" Then
            out(i) = 0
        ElseIf CacheLookup(FontKey(tf) & "|" & texts(i), w) Then
            out(i) = w
        Else
            missIdx(nMiss) = i
            missText(nMiss) = texts(i)
            nMiss = nMiss + 1
        End If
    Next i

    If nMiss > 0 Then
        ReDim Preserve missText(0 To nMiss - 1)
        If USE_AUTOFIT Then
            fresh = MeasureByAutofit(missText, tf, role)
        Else
            fresh = MeasureByPosition(missText, tf, role)
        End If
        For i = 0 To nMiss - 1
            out(missIdx(i)) = fresh(i)
            CacheStore FontKey(tf) & "|" & missText(i), fresh(i)
        Next i
    End If

    MeasureTexts = out
End Function

'-----------------------------------------------------------------------------
' Primary method: a one-row table, autofitted to its contents, read back cell by
' cell.  One round trip per call instead of one per string.
'
' The clamp guard matters: if the row somehow totals more than the scratch page
' can hold, Word shrinks the columns and every width is wrong.  Rather than trust
' a 22-inch page blindly, detect the condition and split the batch.
'-----------------------------------------------------------------------------
Private Function MeasureByAutofit(texts() As String, tf As TierFont, _
        ByVal role As String) As Single()

    Dim out() As Single
    Dim doc As Document
    Dim tbl As Table
    Dim rng As Range
    Dim i As Long, n As Long
    Dim total As Single, limit As Single
    Dim halfA() As String, halfB() As String
    Dim resA() As Single, resB() As Single
    Dim mid As Long

    n = UBound(texts) - LBound(texts) + 1
    ReDim out(0 To n - 1)
    If n = 0 Then
        MeasureByAutofit = out
        Exit Function
    End If

    Set doc = EnsureScratch()
    Set rng = doc.Content
    rng.Delete

    Set tbl = doc.Tables.Add(Range:=doc.Content, NumRows:=1, NumColumns:=n)
    ZeroTablePadding tbl
    tbl.Borders.InsideLineStyle = wdLineStyleNone
    tbl.Borders.OutsideLineStyle = wdLineStyleNone

    For i = 0 To n - 1
        Set rng = tbl.Cell(1, i + 1).Range
        rng.End = rng.End - 1                  ' exclude the end-of-cell marker
        WriteMeasuredText rng, texts(i), tf, role
    Next i

    tbl.AllowAutoFit = True
    tbl.PreferredWidthType = wdPreferredWidthAuto
    tbl.AutoFitBehavior wdAutoFitContent

    total = 0
    For i = 0 To n - 1
        ' Read CELLS, never Columns(i).Width: the latter raises error 5991 as
        ' soon as a table has mixed cell widths, which this one always does.
        out(i) = tbl.Cell(1, i + 1).Width
        total = total + out(i)
    Next i

    limit = ScratchTextWidth(doc)
    tbl.Delete

    ' Clamped: the batch did not fit even on a 22-inch page.  Halve and recurse.
    If n > 1 And total >= limit - 1 Then
        mid = n \ 2
        ReDim halfA(0 To mid - 1)
        ReDim halfB(0 To n - mid - 1)
        For i = 0 To mid - 1
            halfA(i) = texts(i)
        Next i
        For i = mid To n - 1
            halfB(i - mid) = texts(i)
        Next i
        resA = MeasureByAutofit(halfA, tf, role)
        resB = MeasureByAutofit(halfB, tf, role)
        For i = 0 To mid - 1
            out(i) = resA(i)
        Next i
        For i = mid To n - 1
            out(i) = resB(i - mid)
        Next i
    End If

    MeasureByAutofit = out
End Function

'-----------------------------------------------------------------------------
' Fallback method: the horizontal position at the end of a non-wrapping
' paragraph is the width of the text on it.  Immune to clamping, but one Word
' round trip per string.
'-----------------------------------------------------------------------------
Private Function MeasureByPosition(texts() As String, tf As TierFont, _
        ByVal role As String) As Single()

    Dim out() As Single
    Dim doc As Document
    Dim rng As Range
    Dim i As Long, n As Long
    Dim startPos As Single

    n = UBound(texts) - LBound(texts) + 1
    ReDim out(0 To n - 1)
    Set doc = EnsureScratch()

    For i = 0 To n - 1
        doc.Content.Delete
        Set rng = doc.Content
        rng.ParagraphFormat.LeftIndent = 0
        rng.ParagraphFormat.RightIndent = 0
        rng.ParagraphFormat.FirstLineIndent = 0
        WriteMeasuredText rng, texts(i), tf, role

        Set rng = doc.Content
        startPos = doc.Paragraphs(1).Range.Characters(1) _
                      .Information(wdHorizontalPositionRelativeToTextBoundary)
        rng.Collapse wdCollapseEnd
        out(i) = rng.Information(wdHorizontalPositionRelativeToTextBoundary) - startPos
        If out(i) < 0 Then out(i) = 0
    Next i

    MeasureByPosition = out
End Function

'-----------------------------------------------------------------------------
' Put text into a measurement range exactly as the renderer will draw it.
'
' Direct formatting is used rather than the LingTeX paragraph styles, so the
' scratch document needs no styles of its own; the appearance has already been
' resolved from the target document by ResolveTierFont.  The per-run small caps
' still come from the renderer's own routine, so the two cannot diverge.
'-----------------------------------------------------------------------------
Private Sub WriteMeasuredText(rng As Range, ByVal text As String, _
        tf As TierFont, ByVal role As String)
    rng.Text = text
    With rng.Font
        .Name = tf.Name
        .Size = tf.Size
        .Bold = tf.Bold
        .Italic = tf.Italic
        .SmallCaps = tf.SmallCaps
    End With
    ' Small caps on the grammatical segments, by the same rule the renderer uses.
    ApplyGramGlossRuns rng, text, role, True
End Sub


'=============================================================================
' -- SCRATCH DOCUMENT -------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' The hidden 22-inch measuring document, created on demand and reused.
' ReleaseScratch must be called when an operation finishes, or the document
' leaks for the rest of the Word session.
'-----------------------------------------------------------------------------
Private Function EnsureScratch() As Document
    Dim doc As Document

    On Error Resume Next
    If Not mScratch Is Nothing Then
        ' Touch it: if the user closed it behind our back this raises.
        If mScratch.Name <> "" Then
            Set EnsureScratch = mScratch
            Exit Function
        End If
    End If
    Set mScratch = Nothing
    Err.Clear
    On Error GoTo 0

    On Error Resume Next
    Set doc = Documents.Add(Visible:=False)
    If doc Is Nothing Then
        ' Older or stricter hosts may reject the Visible argument.
        Set doc = Documents.Add
        If Not doc Is Nothing Then
            If doc.Windows.Count > 0 Then doc.Windows(1).Visible = False
        End If
    End If
    On Error GoTo 0
    If doc Is Nothing Then Exit Function

    With doc.PageSetup
        On Error Resume Next
        .TopMargin = 0
        .BottomMargin = 0
        .LeftMargin = 0
        .RightMargin = 0
        .Gutter = 0
        .PageWidth = InchesToPoints(SCRATCH_PAGE_WIDTH_IN)
        .TextColumns.SetCount NumColumns:=1
        On Error GoTo 0
    End With

    Set mScratch = doc
    Set EnsureScratch = doc
End Function

Private Function ScratchTextWidth(doc As Document) As Single
    On Error Resume Next
    ScratchTextWidth = doc.PageSetup.PageWidth _
                     - doc.PageSetup.LeftMargin - doc.PageSetup.RightMargin
    On Error GoTo 0
    If ScratchTextWidth <= 0 Then ScratchTextWidth = InchesToPoints(SCRATCH_PAGE_WIDTH_IN)
End Function

' Cell padding is zeroed on both the measurement table and the rendered table, so
' the measured number is pure content width and the space between columns is
' controlled entirely by the configured gap.  Wrapped in error handling because
' these properties are the least certain part of the object model on Mac Word --
' if they are missing, both tables simply keep Word's default padding and the
' measurement stays consistent with the drawing.
Public Sub ZeroTablePadding(tbl As Table)
    On Error Resume Next
    tbl.LeftPadding = 0
    tbl.RightPadding = 0
    tbl.TopPadding = 0
    tbl.BottomPadding = 0
    tbl.Spacing = 0
    On Error GoTo 0
End Sub

' Close the scratch document.  Safe to call when there is none.
Public Sub ReleaseScratch()
    On Error Resume Next
    If Not mScratch Is Nothing Then mScratch.Close SaveChanges:=wdDoNotSaveChanges
    On Error GoTo 0
    Set mScratch = Nothing
End Sub


'=============================================================================
' -- CACHE ------------------------------------------------------------------
'=============================================================================
' A VBA Collection keyed by string, because Scripting.Dictionary does not exist
' on Mac Word.  Collection has no Exists, so a lookup is a guarded read.

Private Sub EnsureCache()
    If mCache Is Nothing Then Set mCache = New Collection
End Sub

Private Function CacheLookup(ByVal key As String, ByRef outWidth As Single) As Boolean
    Dim v As Variant
    EnsureCache
    On Error Resume Next
    v = mCache(key)
    If Err.Number = 0 Then
        outWidth = CSng(v)
        CacheLookup = True
    End If
    Err.Clear
    On Error GoTo 0
End Function

Private Sub CacheStore(ByVal key As String, ByVal w As Single)
    EnsureCache
    On Error Resume Next
    mCache.Add w, key
    Err.Clear
    On Error GoTo 0
End Sub

' Drop every cached width.  Call after a font or style change, which invalidates
' measurements taken under the old appearance.
Public Sub ClearCache()
    Set mCache = Nothing
End Sub
