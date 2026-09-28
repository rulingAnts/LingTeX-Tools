Attribute VB_Name = "modPptInsert"
Option Explicit
'=============================================================================
' modPptInsert  --  LingTeX-PowerPoint
'
' INSERT: clipboard -> parser -> measure -> plan -> compose out of sight ->
' ONE paste onto the user's slide.  The PowerPoint counterpart of Word's
' LingTeXInsertInterlinear.
'
' ONE UNDO ENTRY.  Every object-model write is its own undo entry here and
' there is no UndoRecord (probe rounds 4 and 6, and the type library).  So the
' example is built COMPLETE in a scratch presentation -- text, formatting,
' tags, name, position -- and put on the slide with one Shapes.Paste, which is
' one entry.  (A re-wrap, where the box already exists, is one TextRange2.Paste
' into it: round 5.)  Making the box on the slide first and pasting text into
' it would be two.
'
' THE USER'S CLIPBOARD is saved before the paste (a paste into a scratch box)
' and restored after (a Copy); neither touches the user's presentation, so
' neither is an undo entry.  For Insert the clipboard was the input, so a
' failed save is tolerable; probe round 7 measures what the save keeps.
'
' TAGS identify the example and hold what read-back and re-wrap need
' (Shape.Tags survive copy and paste: probe round 1):
'   LINGTEX        "1"
'   LINGTEX_TSV    the model, ModelToTsv(ex)
'   LINGTEX_NUMBER the number as drawn, e.g. "(1)"
'   LINGTEX_GRAN   "0" word-aligned, "1" morpheme-aligned
'
' SEVERAL EXAMPLES in one copy: one box each, one under another, numbered
' (1a), (1b) ... -- the owner's rule of one number for the group with
' sub-numbers, in the form a single text box allows.  Renumbering across the
' presentation is a later command (PLAN.md: numbering is plain text).
'
' Pure ASCII.  -1/0 for msoTrue/msoFalse; Presentations.Add(0) no window;
' Slides.Add(1, 12) blank; AddTextbox(1, ...) horizontal.
'=============================================================================

Public Const TAG_LINGTEX As String = "LINGTEX"
Public Const TAG_TSV As String = "LINGTEX_TSV"
Public Const TAG_NUMBER As String = "LINGTEX_NUMBER"
Public Const TAG_GRAN As String = "LINGTEX_GRAN"

' Defaults until settings live in Presentation.Tags: Word's numbers where they
' carry over (gap 6, hang 36), a slide-sized font.
Private Const DEF_FONT As String = "Times New Roman"
Private Const DEF_SIZE As Double = 24
Private Const DEF_GAP As Double = 6
Private Const DEF_NUMBER_HANG As Double = 36
Private Const DEF_BETWEEN As Double = 12   ' between two examples from one copy

'-----------------------------------------------------------------------------
' The command: the clipboard, onto the current slide, below the top margin.
'-----------------------------------------------------------------------------
Public Sub LingTeXInsertInterlinear()
    Dim app As Object, sld As Object, text As String, note As String, n As Long
    Dim w As Double, x0 As Double, y0 As Double
    Set app = Application
    text = ReadClipboardForParser(note)
    If text = "" Then
        MsgBox "Nothing to insert: the clipboard holds no text." & IIf(note <> "", " (" & note & ")", ""), 48, "LingTeX"
        Exit Sub
    End If
    On Error Resume Next
    Set sld = app.ActiveWindow.View.Slide
    On Error GoTo 0
    If sld Is Nothing Then
        MsgBox "Nothing to insert onto: no slide is showing.", 48, "LingTeX"
        Exit Sub
    End If
    w = app.ActivePresentation.PageSetup.SlideWidth * 0.8
    x0 = app.ActivePresentation.PageSetup.SlideWidth * 0.1
    y0 = app.ActivePresentation.PageSetup.SlideHeight * 0.2
    n = InsertExamples(text, sld, x0, y0, w)
    If n = 0 Then MsgBox "The clipboard's text is not an interlinear example LingTeX can read.", 48, "LingTeX"
End Sub

'-----------------------------------------------------------------------------
' Every example in text: one box each, stacked from (x0, y0), boxWidth wide.
' Returns how many were inserted.  firstNumber numbers the first one.
'-----------------------------------------------------------------------------
Public Function InsertExamples(ByVal text As String, ByVal sld As Object, _
        ByVal x0 As Double, ByVal y0 As Double, ByVal boxWidth As Double, _
        Optional ByVal firstNumber As Long = 1, _
        Optional ByVal gran As IgtGranularity = igtWordAligned) As Long
    Dim models() As IgtExample, n As Long, i As Long, y As Double, shp As Object, num As String
    models = ModelsFromText(text, gran, n)
    If n = 0 Then Exit Function
    y = y0
    For i = 0 To n - 1
        If n = 1 Then
            num = "(" & firstNumber & ")"
        Else
            num = "(" & firstNumber & Chr$(97 + i) & ")"
        End If
        Set shp = InsertOne(models(LBound(models) + i), sld, x0, y, boxWidth, num, gran)
        If shp Is Nothing Then Exit For
        y = y + shp.Height + DEF_BETWEEN
        InsertExamples = InsertExamples + 1
    Next i
    ReleaseScratch
End Function

'-----------------------------------------------------------------------------
' One example, composed complete in a scratch presentation and pasted onto sld
' as a shape: ONE undo entry.  Returns the pasted shape, or Nothing.
'-----------------------------------------------------------------------------
Public Function InsertOne(ex As IgtExample, ByVal sld As Object, ByVal x0 As Double, _
        ByVal y0 As Double, ByVal boxWidth As Double, ByVal numberText As String, _
        ByVal gran As IgtGranularity) As Object
    Dim app As Object, scratch As Object, sbox As Object, saved As Object, pasted As Object
    Dim fonts() As PptTierFont, widths() As Double, cw() As Double, nb() As Boolean, lines() As Long
    Dim lay As PptLayout, t As Long, numW As Double, before As Long, tf As PptTierFont
    Set app = Application
    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Function

    ' Fonts and layout.
    tf.Name = DEF_FONT: tf.Size = DEF_SIZE: tf.Italic = False
    ReDim fonts(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        fonts(t) = tf
        fonts(t).Italic = (ex.Tiers(t) = ROLE_VERNACULAR Or ex.Tiers(t) = ROLE_MORPHEMES)
    Next t
    lay.Gap = DEF_GAP
    lay.LowercaseGram = True
    lay.InitialCap = False
    lay.FreeFont = tf
    If Len(numberText) > 0 Then
        numW = MeasureText(numberText, ROLE_FREE, tf) + DEF_GAP
        If numW > DEF_NUMBER_HANG Then lay.NumberHang = numW Else lay.NumberHang = DEF_NUMBER_HANG
    Else
        lay.NumberHang = 0
    End If
    lay.ContIndent = lay.NumberHang

    ' Measure and plan.
    MeasureExample ex, fonts, widths
    cw = ColumnWidths(ex, widths, lay.Gap)
    nb = NoBreakFlags(ex)
    lines = LimitLineColumns(ComputeWrapLines(cw, nb, boxWidth, lay.NumberHang, lay.ContIndent), ex.ColCount)

    ' Compose the complete box out of sight.
    On Error GoTo Fail
    Set scratch = app.Presentations.Add(0)
    Set sbox = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, x0, y0, boxWidth, 40)
    PrepareExampleBox sbox
    ComposeExample sbox, ex, fonts, cw, lines, numberText, lay
    sbox.Name = "LingTeX Example " & numberText
    sbox.Tags.Add TAG_LINGTEX, "1"
    sbox.Tags.Add TAG_TSV, ModelToTsv(ex)
    sbox.Tags.Add TAG_NUMBER, numberText
    sbox.Tags.Add TAG_GRAN, CStr(gran)

    ' Save the user's clipboard, paste the shape (THE undo entry), restore.
    Set saved = SaveClipboard(scratch)
    before = sld.Shapes.Count
    sbox.Copy
    sld.Shapes.Paste
    If sld.Shapes.Count = before + 1 Then Set pasted = sld.Shapes(sld.Shapes.Count)
    RestoreClipboard saved
    scratch.Saved = -1
    scratch.Close
    Set InsertOne = pasted
    Exit Function
Fail:
    On Error Resume Next
    RestoreClipboard saved
    If Not scratch Is Nothing Then
        scratch.Saved = -1
        scratch.Close
    End If
    Set InsertOne = Nothing
End Function

'-----------------------------------------------------------------------------
' The clipboard, kept in a text box of the scratch presentation: a paste into
' it (nothing in the user's presentation changes), and a Copy from it to put
' the clipboard back.  Nothing when there is nothing to keep.  What this keeps
' of a shape or a picture is what probe round 7 measures.
'-----------------------------------------------------------------------------
Public Function SaveClipboard(ByVal scratch As Object) As Object
    Dim box As Object
    On Error Resume Next
    Set box = scratch.Slides(1).Shapes.AddTextbox(1, 0, 400, 700, 40)
    box.Name = "LingTeX ClipboardKeep"
    box.TextFrame2.TextRange.Paste
    If Err.Number <> 0 Or Len(box.TextFrame2.TextRange.Text) = 0 Then
        Err.Clear
        box.Delete
        Set SaveClipboard = Nothing
    Else
        Set SaveClipboard = box
    End If
    Err.Clear
End Function

Public Sub RestoreClipboard(ByVal saved As Object)
    On Error Resume Next
    If saved Is Nothing Then Exit Sub
    saved.TextFrame2.TextRange.Copy
    Err.Clear
End Sub

' Is this shape one of ours?
Public Function IsLingTeXExample(ByVal shp As Object) As Boolean
    On Error Resume Next
    IsLingTeXExample = (shp.Tags.Item(TAG_LINGTEX) = "1")
    Err.Clear
End Function
