Attribute VB_Name = "modPptMeasure"
Option Explicit
'=============================================================================
' modPptMeasure  --  LingTeX-PowerPoint
'
' The widths of an example's cells, in points, as the shared wrap planner
' wants them: cellWidths(tierIndex, columnIndex), fed to modWrap.ColumnWidths.
' The PowerPoint counterpart of LingTeX-Word's modMeasure, with the same names
' where the job is the same (MeasureExample, MeasureText, EnsureScratch,
' ReleaseScratch, ClearMeasureCache).
'
' HOW A WIDTH IS MEASURED (probe rounds 1 to 3, PLAN.md): a scratch
' presentation with no window holds one wide text box; the cell is written into
' it by modPptFormat.WriteCell -- the very routine that draws it -- and
' Characters(1, n).BoundWidth is read back.  That is the text's own width
' ("neighbor-F" at 20 pt: 88.4 pt, the right edge of its last character); a
' whole range's BoundWidth adds about a quarter em, so it is not used.  200
' measurements took 0.05 s.
'
' CACHE: by font, size, italic, tier role and text, like modMeasure's
' MeasureKey.  A re-wrap on every resize would otherwise measure the same
' strings again and again.
'
' SCRATCH: EnsureScratch makes the presentation on first use and keeps it;
' ReleaseScratch closes it -- call it when an operation ends, as Word's
' modMeasure asks.  Presentations.Add(0) is a presentation with no window;
' Slides.Add(1, 12) the blank layout; AddTextbox(1, ...) horizontal; AutoSize 0
' is none, so the box never resizes under the measurement.  Pure ASCII.
'=============================================================================

Private mScratch As Object      ' the scratch presentation
Private mBox As Object          ' its one text box
Private mCache As Collection    ' key -> width

' widths(t, c) for every interlinear tier; free rows are left at 0.
Public Sub MeasureExample(ex As IgtExample, fonts() As PptTierFont, ByRef widths() As Double)
    Dim t As Long, c As Long
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        ReDim widths(0 To 0, 0 To 0)
        Exit Sub
    End If
    ReDim widths(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)
    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            For c = 0 To ex.ColCount - 1
                widths(t, c) = MeasureText(GetCell(ex, t, c), ex.Tiers(t), fonts(t))
            Next c
        End If
    Next t
End Sub

' One string's width as it will be drawn on a tier of the given role.
Public Function MeasureText(ByVal text As String, ByVal role As String, tf As PptTierFont) As Double
    Dim key As String, box As Object, n As Long, w As Double
    If Len(text) = 0 Then Exit Function
    key = MeasureKey(tf, role, text)
    If CacheLookup(key, w) Then
        MeasureText = w
        Exit Function
    End If
    Set box = EnsureScratch()
    WriteCell box.TextFrame2.TextRange, text, role, tf
    n = Len(box.TextFrame2.TextRange.Text)
    If n > 0 Then w = box.TextFrame2.TextRange.Characters(1, n).BoundWidth
    CacheStore key, w
    MeasureText = w
End Function

Public Sub ClearMeasureCache()
    Set mCache = Nothing
End Sub

' Close the scratch presentation.  Safe to call when there is none.
Public Sub ReleaseScratch()
    On Error Resume Next
    If Not mScratch Is Nothing Then
        mScratch.Saved = -1
        mScratch.Close
    End If
    Set mScratch = Nothing
    Set mBox = Nothing
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
Private Function MeasureKey(tf As PptTierFont, ByVal role As String, ByVal text As String) As String
    Dim it As String
    If tf.Italic Then it = "i" Else it = "r"
    MeasureKey = tf.Name & "|" & Format$(tf.Size, "0.##") & "|" & it & "|" & role & "|" & text
End Function

Private Function CacheLookup(ByVal key As String, ByRef w As Double) As Boolean
    On Error Resume Next
    If mCache Is Nothing Then Exit Function
    w = mCache.Item(key)
    CacheLookup = (Err.Number = 0)
    Err.Clear
End Function

Private Sub CacheStore(ByVal key As String, ByVal w As Double)
    On Error Resume Next
    If mCache Is Nothing Then Set mCache = New Collection
    mCache.Add w, key
    Err.Clear
End Sub

' The scratch box, made on first use.  If PowerPoint closed the presentation
' behind our back, touching the box errors, and a new one is made.
Private Function EnsureScratch() As Object
    Dim app As Object, nm As String
    On Error Resume Next
    If Not mBox Is Nothing Then
        nm = mBox.Name
        If Err.Number = 0 Then
            Set EnsureScratch = mBox
            Exit Function
        End If
        Err.Clear
        Set mScratch = Nothing
        Set mBox = Nothing
    End If
    On Error GoTo 0
    Set app = Application
    Set mScratch = app.Presentations.Add(0)
    Set mBox = mScratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, 2000, 100)
    With mBox.TextFrame2
        .WordWrap = 0
        .AutoSize = 0
        .MarginLeft = 0
        .MarginRight = 0
        .MarginTop = 0
        .MarginBottom = 0
    End With
    Set EnsureScratch = mBox
End Function
