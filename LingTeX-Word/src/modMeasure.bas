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
' wider than the page, so measurement happens in a scratch document with a
' 22-inch page -- Word's maximum -- and zero margins.
'
' THE METHOD: one paragraph per string, then read
' Range.Information(wdHorizontalPositionRelativeToTextBoundary) at the end of the
' text.  The horizontal position where a line of text ends IS its width.
'
' ---------------------------------------------------------------------------
' WHY NOT AUTOFIT, WHICH WOULD BE FEWER ROUND TRIPS
'
' The obvious approach is a single-row table, one cell per string, then
' AutoFitBehavior wdAutoFitContent and read Cell(1, c).Width back -- one Word
' round trip per tier instead of one per string.  It was implemented first and
' then deleted, because it does not work on Mac Word.  Measured on Word 16.112
' (tools/probe/modProbe.bas section 3), on a 1584 pt page:
'
'     width of "i"         394.7 pt
'     width of "iii"       394.7 pt
'     width of "WWW"       394.7 pt
'     width of "Edefina"   394.7 pt
'
' Four identical widths, and 394.7 x 4 = 1578.8, i.e. the page width divided
' equally.  wdAutoFitContent behaved like autofit-to-WINDOW and never consulted
' the content.  It fails silently: every column comes out the same width and
' nothing downstream can be right.
'
' Do not reintroduce it.  If you want the round trips back, re-run the probe on
' the Word builds you care about first -- and note that it also has to be
' reconciled with Columns(i).Width, which raises error 5991 on mixed widths on
' Windows but returned a value with no error on Mac precisely because the widths
' were not mixed.
' ---------------------------------------------------------------------------
'
' Results are cached, so re-wrapping text that has not been edited costs nothing.
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

' Word's maximum page dimension is 22 inches.  Wide enough that a single word
' never wraps, which is all the method requires.
Private Const SCRATCH_PAGE_WIDTH_IN As Single = 22

' Word's "mixed value" sentinel, returned by a font property read over a range
' whose runs disagree.
Private Const WD_UNDEFINED_SIZE As Single = 9999999

Private mScratch As Document
Private mCache   As Collection

'-----------------------------------------------------------------------------
' DID THE MEASUREMENT ACTUALLY WORK?
'
' A width of 0 is a legitimate answer -- an empty cell is 0 points wide -- so
' until this existed a total failure was indistinguishable from a row of empty
' cells, and nothing downstream could tell. That matters more than it sounds,
' because zeros do not fail loudly: ColumnWidths turns each one into bare gap,
' ComputeWrapLines then fits roughly 78 columns on a 468-point line, and
' Tables.Add is asked for more columns than Word's 63-column maximum. In
' RewrapTable the old table is already deleted by that point, so the raise lands
' after the user's example is gone.
'
' So failure gets its own channel. Cleared at the top of MeasureTexts, set on
' every path that gives up, and checked by RenderExample before it draws
' anything. A caller that ignores it still behaves as before; one that checks it
' cannot mistake a failure for a measurement.
'-----------------------------------------------------------------------------
Public gMeasureFailed As Boolean
Public gMeasureError  As String

Private Sub MeasureFail(ByVal what As String)
    gMeasureFailed = True
    If gMeasureError <> "" Then gMeasureError = gMeasureError & "; "
    gMeasureError = gMeasureError & what
    If Err.Number <> 0 Then
        gMeasureError = gMeasureError & " (" & CStr(Err.Number) & ": " & _
                        Err.Description & ")"
    End If
End Sub

' Called by MeasureExample and by any caller measuring a batch of its own.
Public Sub ClearMeasureFailure()
    gMeasureFailed = False
    gMeasureError = ""
End Sub

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

    ClearMeasureFailure

    ' ReDim BEFORE the guard, not after. widths() is a ByRef contract: a caller
    ' that is handed back an unallocated array raises error 9 on its first
    ' subscript, which is a confusing way to learn that the example was empty.
    ReDim widths(0 To IIf(ex.TierCount > 0, ex.TierCount - 1, 0), _
                 0 To IIf(ex.ColCount > 0, ex.ColCount - 1, 0))
    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Sub

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

    ' An unallocated texts() raises error 9 on UBound, which is the case that
    ' actually happens -- an allocated array always has at least one element, so
    ' the old "If n = 0" guard could never fire and sat after the ReDim it was
    ' meant to protect anyway.
    If Not IsArrayAllocated(texts) Then
        ReDim out(0 To 0)
        MeasureFail "MeasureTexts was given an unallocated array"
        MeasureTexts = out
        Exit Function
    End If

    n = UBound(texts) - LBound(texts) + 1
    ReDim out(0 To n - 1)

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
        fresh = MeasureByPosition(missText, tf, role)
        For i = 0 To nMiss - 1
            out(missIdx(i)) = fresh(i)
            CacheStore FontKey(tf) & "|" & missText(i), fresh(i)
        Next i
    End If

    MeasureTexts = out
End Function

'-----------------------------------------------------------------------------
' Measure a batch of strings: one paragraph each, then read where each one ends.
'
' The document is built ONCE for the whole batch rather than once per string.
' The obvious loop -- clear the document, insert one string, measure, repeat --
' costs a full document rebuild per string, and on Mac Word every call into the
' object model is slow enough for that to be felt on a long example.
'
' The left edge is read once.  Every paragraph has LeftIndent, RightIndent and
' FirstLineIndent forced to zero, so they all start at the same x; reading it per
' paragraph would double the position calls for an answer that cannot differ.
'-----------------------------------------------------------------------------
Private Function MeasureByPosition(texts() As String, tf As TierFont, _
        ByVal role As String) As Single()

    Dim out() As Single
    Dim doc As Document
    Dim rng As Range, para As Range
    Dim i As Long, n As Long
    Dim baseX As Single, endX As Single
    Dim joined As String

    If Not IsArrayAllocated(texts) Then
        ReDim out(0 To 0)
        MeasureFail "MeasureByPosition was given an unallocated array"
        MeasureByPosition = out
        Exit Function
    End If

    n = UBound(texts) - LBound(texts) + 1
    ReDim out(0 To n - 1)

    Set doc = EnsureScratch()
    If doc Is Nothing Then
        MeasureFail "no scratch document"
        MeasureByPosition = out
        Exit Function
    End If

    ' One paragraph per string, in a single insertion.
    joined = texts(LBound(texts))
    For i = LBound(texts) + 1 To UBound(texts)
        joined = joined & vbCr & texts(i)
    Next i

    On Error GoTo Bail
    doc.Content.Delete
    Set rng = doc.Content
    rng.Text = joined
    With rng.ParagraphFormat
        .LeftIndent = 0
        .RightIndent = 0
        .FirstLineIndent = 0
        .SpaceBefore = 0
        .SpaceAfter = 0
        .Alignment = wdAlignParagraphLeft
    End With

    ' Format each paragraph as the renderer will draw it, small caps included.
    For i = 0 To n - 1
        Set para = ParagraphBody(doc, i + 1)
        If Not para Is Nothing Then
            ApplyTierFont para, tf
            ApplyGramGlossRuns para, texts(i), role, True
        End If
    Next i

    baseX = doc.Paragraphs(1).Range.Characters(1) _
               .Information(wdHorizontalPositionRelativeToTextBoundary)

    For i = 0 To n - 1
        Set para = ParagraphBody(doc, i + 1)
        If para Is Nothing Then
            out(i) = 0
        Else
            para.Collapse wdCollapseEnd
            endX = para.Information(wdHorizontalPositionRelativeToTextBoundary)
            out(i) = endX - baseX
            If out(i) < 0 Then out(i) = 0
        End If
    Next i

    MeasureByPosition = out
    Exit Function

Bail:
    ' Whatever is in out() at this point is partial at best. Say so rather than
    ' returning it as though it were measured.
    MeasureFail "position measurement stopped early"
    MeasureByPosition = out
End Function

' A paragraph's range without its paragraph mark, which would otherwise be
' measured as part of the text and is not drawn.
Private Function ParagraphBody(doc As Document, ByVal idx As Long) As Range
    Dim r As Range
    Dim wanted As Long

    On Error Resume Next
    If idx < 1 Or idx > doc.Paragraphs.Count Then Exit Function
    Set r = doc.Paragraphs(idx).Range.Duplicate
    If r Is Nothing Then
        MeasureFail "could not take paragraph " & CStr(idx)
        Err.Clear
        Exit Function
    End If

    ' Drop the paragraph mark, which is not drawn and would be measured.
    ' A failure here is NOT harmless: the returned range would still contain the
    ' mark, the end position would land at the start of the next paragraph, and
    ' the width would come back as 0 -- a failed range adjustment reported as
    ' "this text is zero points wide". So it is checked rather than cleared.
    If r.End > r.Start Then
        wanted = r.End - 1
        r.MoveEnd wdCharacter, -1
        If r.End <> wanted Then
            MeasureFail "could not exclude the paragraph mark of paragraph " & CStr(idx)
            Err.Clear
            Exit Function
        End If
    End If

    Set ParagraphBody = r
    Err.Clear
End Function

'-----------------------------------------------------------------------------
' Put the tier's appearance on the range.
'
' Verified afterwards, not assumed. If the size does not take, measurement runs
' at the scratch document's default size while the renderer draws at the real one,
' and every column comes out wrong with nothing raised anywhere.
'-----------------------------------------------------------------------------
Private Sub ApplyTierFont(rng As Range, tf As TierFont)
    Dim gotSize As Single

    On Error Resume Next
    With rng.Font
        .Name = tf.Name
        .Size = tf.Size
        .Bold = tf.Bold
        .Italic = tf.Italic
        .SmallCaps = tf.SmallCaps
    End With
    gotSize = rng.Font.Size
    If Err.Number <> 0 Then
        MeasureFail "could not set the measuring font"
        Err.Clear
        On Error GoTo 0
        Exit Sub
    End If
    Err.Clear
    On Error GoTo 0

    ' wdUndefined (9999999) means mixed, which cannot happen on a range we just
    ' set wholesale; anything else that is not the requested size means the
    ' assignment did not take.
    If gotSize <> tf.Size And gotSize <> WD_UNDEFINED_SIZE Then
        MeasureFail "measuring font size is " & CStr(gotSize) & _
                    ", asked for " & CStr(tf.Size)
    End If
End Sub

' True only for an array that has been allocated. UBound on an unallocated
' dynamic array raises error 9 rather than returning anything.
Private Function IsArrayAllocated(arr() As String) As Boolean
    On Error Resume Next
    IsArrayAllocated = (UBound(arr) >= LBound(arr))
    If Err.Number <> 0 Then
        IsArrayAllocated = False
        Err.Clear
    End If
    On Error GoTo 0
End Function

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
