Attribute VB_Name = "modPptCommands"
Option Explicit
'=============================================================================
' modPptCommands  --  LingTeX-PowerPoint
'
' THE COMMANDS on an example that is already on a slide: Check Glossing,
' Split Column, Merge Columns, By Word, By Morpheme, Renumber -- the
' counterparts of Word's, on the one-text-box design.  Every one reads the
' example back from its box (modPptRewrap.ReadBackExample: the text is what
' the user typed, the tags the schema), changes the MODEL with the shared
' operations (modIgtModel, modLeipzig), and composes the result back IN
' PLACE (RecomposeExample): one macro run, one undo entry (probe round 8).
'
' WHERE THE CURSOR IS.  A column is found from the text cursor: the paragraph
' it is in says the wrap line and tier, the tabs before it in that paragraph
' say the cell, and the cells of the earlier wrap lines are counted in
' (ColumnAtChar) -- the mirror of how ComposeExample laid the text out and
' how ReadBackExample reads it.  On the first paragraph the number and its
' tab are not a cell.
'
' EVENTS.  LingTeXStart hooks clsPptEvents, which re-wraps an example whose
' box the user resized (AfterShapeSizeChange fires once, when the handle is
' let go: probe round 4).  A re-wrap changes the box's height and hears its
' own event after the macro has returned (round 4), so every composition
' records the size it left in TAG_SIZE and the handler ignores a resize to
' exactly that size.  gPptBusy guards against re-entry while a command runs.
'
' Pure ASCII.  Numbers instead of named constants.
'=============================================================================

Public Const TAG_SIZE As String = "LINGTEX_SIZE"
Public Const TAG_SUB As String = "LINGTEX_SUB"

Public gPptBusy As Boolean
Public gPptEvents As clsPptEvents

Private Const TITLE As String = "LingTeX"

'-----------------------------------------------------------------------------
' Start: hook the events.  Called by Auto_Open when the add-in loads, and
' by hand from the macro list.
'-----------------------------------------------------------------------------
Public Sub LingTeXStart()
    On Error Resume Next
    If gPptEvents Is Nothing Then Set gPptEvents = New clsPptEvents
    Set gPptEvents.App = Application
    gPptBusy = False
    Err.Clear
End Sub

Public Sub LingTeXStop()
    On Error Resume Next
    If Not gPptEvents Is Nothing Then Set gPptEvents.App = Nothing
    Set gPptEvents = Nothing
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
' Check Glossing: the Leipzig checks on the selected example; what has one
' right answer is fixed on request, the rest reported.
'-----------------------------------------------------------------------------
Public Sub LingTeXCheckGlossing()
    Dim shp As Object, ex As IgtExample, numberText As String, gran As Long
    Dim warnings As Collection, nFixable As Long, pres As Object
    Set shp = SelectedExampleBox()
    If shp Is Nothing Then
        MsgBox "Click into an interlinear example first.", 64, TITLE
        Exit Sub
    End If
    If Not ReadBackExample(shp, ex, numberText, gran) Then
        MsgBox "The example could not be read back: its tiers no longer have the same number of columns (a tab typed or deleted?).", 48, TITLE
        Exit Sub
    End If
    Set warnings = CheckExample(ex)
    If warnings.Count = 0 Then
        MsgBox "No problems found.", 64, TITLE
        Exit Sub
    End If
    nFixable = FixableCount(warnings)
    If nFixable = 0 Then
        MsgBox WarningsText(warnings), 48, TITLE
        Exit Sub
    End If
    If MsgBox(WarningsText(warnings) & Chr$(13) & Chr$(13) & CStr(nFixable) & _
              " of these can be fixed automatically. Fix them now?", 36, TITLE) <> 6 Then Exit Sub
    Set pres = PresentationOf(shp)
    FixWhatWeCan ex, SettingSpaceReplacement(pres)
    gPptBusy = True
    RecomposeExample shp, ex, numberText, gran
    ReleaseScratch
    gPptBusy = False
    Set warnings = CheckExample(ex)
    If warnings.Count > 0 Then MsgBox WarningsText(warnings), 48, TITLE
End Sub

' The repairs with one right answer: the break characters of every column,
' then spaces inside cells.
Public Sub FixWhatWeCan(ByRef ex As IgtExample, ByVal replacement As String)
    Dim c As Long
    For c = 0 To ex.ColCount - 1
        FixColumnBreakChars ex, c
    Next c
    FixCellSpaces ex, replacement
End Sub

' The warnings as lines, at most twelve, inside what a message box shows.
Public Function WarningsText(warnings As Collection) As String
    Dim w As Variant, s As String, n As Long
    If warnings Is Nothing Then Exit Function
    For Each w In warnings
        n = n + 1
        If n > 12 Then
            s = s & Chr$(13) & "... and " & CStr(warnings.Count - 12) & " more."
            Exit For
        End If
        If s <> "" Then s = s & Chr$(13)
        s = s & "- " & w.Describe
    Next w
    If Len(s) > 1000 Then s = Left$(s, 990) & "..."
    WarningsText = s
End Function

'-----------------------------------------------------------------------------
' Split Column: the column at the cursor, at its first morpheme boundary.
'-----------------------------------------------------------------------------
Public Sub LingTeXSplitColumn()
    Dim shp As Object, col As Long, shortTiers As String, okAll As Boolean
    Set shp = SelectedExampleBox()
    If shp Is Nothing Then
        MsgBox "Click in the column you want to split.", 64, TITLE
        Exit Sub
    End If
    col = ColumnAtSelection(shp)
    If col < 0 Then
        MsgBox "Click in one of the example's word cells; the number and the translation are not columns.", 64, TITLE
        Exit Sub
    End If
    okAll = SplitColumnInBox(shp, col, shortTiers)
    If shortTiers = "(read-back)" Then
        MsgBox "The example could not be read back: its tiers no longer have the same number of columns.", 48, TITLE
    ElseIf Not okAll Then
        MsgBox "No morpheme break was found in: " & shortTiers & Chr$(13) & Chr$(13) & _
               "Those cells were left whole and the new column is empty for them. Add the matching break, or undo.", 48, TITLE
    End If
End Sub

' Split column col of the example in shp and compose it back.  Returns what
' SplitColumn returns; shortTiers "(read-back)" when the box could not be read.
Public Function SplitColumnInBox(ByVal shp As Object, ByVal col As Long, ByRef shortTiers As String) As Boolean
    Dim ex As IgtExample, numberText As String, gran As Long
    shortTiers = ""
    If Not ReadBackExample(shp, ex, numberText, gran) Then
        shortTiers = "(read-back)"
        Exit Function
    End If
    SplitColumnInBox = SplitColumn(ex, col, 1, shortTiers)
    gPptBusy = True
    RecomposeExample shp, ex, numberText, gran
    ReleaseScratch
    gPptBusy = False
End Function

'-----------------------------------------------------------------------------
' Merge Columns: the selected cells, or the cursor's column with the next.
'-----------------------------------------------------------------------------
Public Sub LingTeXMergeColumns()
    Dim shp As Object, firstCol As Long, lastCol As Long, tr As Object
    Set shp = SelectedExampleBox()
    If shp Is Nothing Then
        MsgBox "Select the columns you want to merge.", 64, TITLE
        Exit Sub
    End If
    firstCol = ColumnAtSelection(shp)
    If firstCol < 0 Then
        MsgBox "Select the example's word cells; the number and the translation are not columns.", 64, TITLE
        Exit Sub
    End If
    lastCol = firstCol
    On Error Resume Next
    Set tr = Application.ActiveWindow.Selection.TextRange2
    If Not tr Is Nothing Then
        If tr.Length > 1 Then lastCol = ColumnAtChar(shp, tr.Start + tr.Length - 1)
    End If
    On Error GoTo 0
    If lastCol <= firstCol Then lastCol = firstCol + 1
    Select Case MergeColumnsInBox(shp, firstCol, lastCol)
        Case -1: MsgBox "The example could not be read back: its tiers no longer have the same number of columns.", 48, TITLE
        Case 0: MsgBox "There is no following column to merge with.", 64, TITLE
    End Select
End Sub

' Merge columns firstCol..lastCol of the example in shp and compose it back.
' Returns 1 merged, 0 nothing to merge, -1 could not read back.
Public Function MergeColumnsInBox(ByVal shp As Object, ByVal firstCol As Long, ByVal lastCol As Long) As Long
    Dim ex As IgtExample, numberText As String, gran As Long
    If Not ReadBackExample(shp, ex, numberText, gran) Then
        MergeColumnsInBox = -1
        Exit Function
    End If
    If lastCol > ex.ColCount - 1 Then lastCol = ex.ColCount - 1
    If lastCol <= firstCol Then Exit Function
    If Not MergeColumns(ex, firstCol, lastCol) Then Exit Function
    gPptBusy = True
    RecomposeExample shp, ex, numberText, gran
    ReleaseScratch
    gPptBusy = False
    MergeColumnsInBox = 1
End Function

'-----------------------------------------------------------------------------
' By Morpheme / By Word: the selected examples re-projected, and the
' presentation's setting for new ones.
'-----------------------------------------------------------------------------
Public Sub LingTeXAlignByMorpheme()
    RealignSelected igtMorphemeAligned
End Sub

Public Sub LingTeXAlignByWord()
    RealignSelected igtWordAligned
End Sub

Private Sub RealignSelected(ByVal gran As IgtGranularity)
    Dim app As Object, sr As Object, shp As Object, pres As Object, n As Long
    Set app = Application
    On Error Resume Next
    Set pres = app.ActivePresentation
    Set sr = app.ActiveWindow.Selection.ShapeRange
    On Error GoTo 0
    If Not pres Is Nothing Then SetSettingGranularity pres, gran
    If sr Is Nothing Then Exit Sub
    For Each shp In sr
        If IsLingTeXExample(shp) Then
            n = n + 1
            RealignExample shp, gran
        End If
    Next shp
    ReleaseScratch
End Sub

' Re-project one example: by morpheme splits every column that splits on
' every tier (ProjectToMorphemes); by word folds every continuation column
' back into its head (NoBreakFlags).  Returns True when it was composed.
Public Function RealignExample(ByVal shp As Object, ByVal gran As IgtGranularity) As Boolean
    Dim ex As IgtExample, numberText As String, oldGran As Long, nb() As Boolean, c As Long
    If Not ReadBackExample(shp, ex, numberText, oldGran) Then Exit Function
    If gran = igtMorphemeAligned Then
        ProjectToMorphemes ex
    Else
        nb = NoBreakFlags(ex)
        For c = ex.ColCount - 1 To 1 Step -1
            If nb(c) Then MergeColumns ex, c - 1, c
        Next c
    End If
    gPptBusy = True
    RecomposeExample shp, ex, numberText, gran
    ReleaseScratch
    gPptBusy = False
    RealignExample = True
End Function

'-----------------------------------------------------------------------------
' Renumber: every example in the presentation, slide by slide, top to
' bottom.  A group from one copy keeps its letters: the first ("a", or no
' letter) takes the next number, the rest share it.
'-----------------------------------------------------------------------------
Public Sub LingTeXRenumber()
    Dim n As Long
    n = RenumberPresentation(Application.ActivePresentation)
    ReleaseScratch
    MsgBox CStr(n) & " example(s) numbered.", 64, TITLE
End Sub

Public Function RenumberPresentation(ByVal pres As Object) As Long
    Dim sld As Object, boxes() As Object, nBoxes As Long, i As Long
    Dim num As Long, sub_ As String, want As String
    Dim ex As IgtExample, numberText As String, gran As Long
    gPptBusy = True
    On Error GoTo Done
    For Each sld In pres.Slides
        nBoxes = ExampleBoxesInOrder(sld, boxes)
        For i = 0 To nBoxes - 1
            sub_ = SubLetterOf(boxes(i))
            If sub_ = "" Or sub_ = "a" Then num = num + 1
            want = "(" & CStr(num) & sub_ & ")"
            RenumberPresentation = RenumberPresentation + 1
            If TagOf(boxes(i), TAG_NUMBER) <> want Then
                If ReadBackExample(boxes(i), ex, numberText, gran) Then
                    RecomposeExample boxes(i), ex, want, gran
                End If
            End If
        Next i
    Next sld
Done:
    gPptBusy = False
End Function

' The next free example number in the presentation: one past the largest.
Public Function NextExampleNumber(ByVal pres As Object) As Long
    Dim sld As Object, shp As Object, v As Long
    NextExampleNumber = 1
    On Error Resume Next
    For Each sld In pres.Slides
        For Each shp In sld.Shapes
            If IsLingTeXExample(shp) Then
                v = NumberValueOf(TagOf(shp, TAG_NUMBER))
                If v >= NextExampleNumber Then NextExampleNumber = v + 1
            End If
        Next shp
    Next sld
    Err.Clear
End Function

' The digits of "(12b)": 12.  0 when there are none.
Public Function NumberValueOf(ByVal numberText As String) As Long
    Dim i As Long, ch As String, s As String
    For i = 1 To Len(numberText)
        ch = Mid$(numberText, i, 1)
        If ch >= "0" And ch <= "9" Then
            s = s & ch
        ElseIf s <> "" Then
            Exit For
        End If
    Next i
    If s <> "" Then NumberValueOf = CLng(s)
End Function

' The sub-letter of an example: its TAG_SUB, or the letter after the digits
' of its number ("(12b)" -> "b") for a box tagged before TAG_SUB existed.
Public Function SubLetterOf(ByVal shp As Object) As String
    Dim s As String, i As Long, ch As String, seenDigit As Boolean
    s = TagOf(shp, TAG_SUB)
    If s <> "" Then
        SubLetterOf = s
        Exit Function
    End If
    s = TagOf(shp, TAG_NUMBER)
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch >= "0" And ch <= "9" Then
            seenDigit = True
        ElseIf seenDigit And ch >= "a" And ch <= "z" Then
            SubLetterOf = ch
            Exit Function
        ElseIf seenDigit Then
            Exit Function
        End If
    Next i
End Function

' The LingTeX example boxes of a slide, top to bottom then left to right.
Public Function ExampleBoxesInOrder(ByVal sld As Object, ByRef boxes() As Object) As Long
    Dim shp As Object, n As Long, i As Long, j As Long, tmp As Object
    ReDim boxes(0 To sld.Shapes.Count)
    For Each shp In sld.Shapes
        If IsLingTeXExample(shp) Then
            Set boxes(n) = shp
            n = n + 1
        End If
    Next shp
    For i = 1 To n - 1
        Set tmp = boxes(i)
        j = i - 1
        Do While j >= 0
            If boxes(j).Top < tmp.Top Or (boxes(j).Top = tmp.Top And boxes(j).Left <= tmp.Left) Then Exit Do
            Set boxes(j + 1) = boxes(j)
            j = j - 1
        Loop
        Set boxes(j + 1) = tmp
    Next i
    ExampleBoxesInOrder = n
End Function

'-----------------------------------------------------------------------------
' Compose a model back into its box, in place: measured and planned for the
' box's width with the presentation's settings; the tags brought up to date,
' TAG_SIZE last so the event handler can tell this resize from the user's.
'-----------------------------------------------------------------------------
Public Sub RecomposeExample(ByVal shp As Object, ex As IgtExample, ByVal numberText As String, _
        ByVal gran As Long)
    Dim pres As Object, fonts() As PptTierFont, lay As PptLayout
    Dim widths() As Double, cw() As Double, nb() As Boolean, lines() As Long, w As Double
    Set pres = PresentationOf(shp)
    fonts = TierFontsFor(pres, ex)
    lay = LayoutFor(pres, numberText)
    w = shp.Width - shp.TextFrame2.MarginLeft - shp.TextFrame2.MarginRight
    MeasureExample ex, fonts, widths
    cw = ColumnWidths(ex, widths, lay.Gap)
    nb = NoBreakFlags(ex)
    lines = LimitLineColumns(ComputeWrapLines(cw, nb, w, lay.NumberHang, lay.ContIndent), ex.ColCount)
    ComposeExample shp, ex, fonts, cw, lines, numberText, lay
    shp.Tags.Add TAG_TSV, ModelToTsv(ex)
    shp.Tags.Add TAG_NUMBER, numberText
    shp.Tags.Add TAG_GRAN, CStr(gran)
    shp.Name = "LingTeX Example " & numberText
    RecordSize shp
End Sub

' The size a composition left, for the event handler.
Public Sub RecordSize(ByVal shp As Object)
    On Error Resume Next
    shp.Tags.Add TAG_SIZE, SizeText(shp)
    Err.Clear
End Sub

Public Function SizeText(ByVal shp As Object) As String
    SizeText = Format$(shp.Width, "0.0") & "x" & Format$(shp.Height, "0.0")
End Function

' Is this the size the last composition left?  Then the resize was ours.
Public Function SizeIsOurs(ByVal shp As Object) As Boolean
    SizeIsOurs = (TagOf(shp, TAG_SIZE) = SizeText(shp))
End Function

'-----------------------------------------------------------------------------
' Where the cursor is
'-----------------------------------------------------------------------------
' The one LingTeX example the selection is in or on, or Nothing.
Public Function SelectedExampleBox() As Object
    Dim sel As Object, sr As Object
    On Error Resume Next
    Set sel = Application.ActiveWindow.Selection
    If sel Is Nothing Then Exit Function
    If sel.Type = 2 Or sel.Type = 3 Then
        Set sr = sel.ShapeRange
        If Not sr Is Nothing Then
            If sr.Count >= 1 Then
                If IsLingTeXExample(sr(1)) Then Set SelectedExampleBox = sr(1)
            End If
        End If
    End If
    Err.Clear
End Function

' The column the text cursor is in, or -1 (no text cursor, the number, a
' free line).
Public Function ColumnAtSelection(ByVal shp As Object) As Long
    Dim sel As Object, tr As Object
    ColumnAtSelection = -1
    On Error Resume Next
    Set sel = Application.ActiveWindow.Selection
    If sel Is Nothing Then Exit Function
    If sel.Type <> 3 Then Exit Function
    Set tr = sel.TextRange2
    If tr Is Nothing Then Exit Function
    On Error GoTo 0
    ColumnAtSelection = ColumnAtChar(shp, tr.Start)
End Function

' The flat column of character charPos (1-based, in the box's text), read
' the way ReadBackExample reads the box: paragraph -> wrap line and tier,
' tabs before the character -> cell, earlier wrap lines' cells counted in.
' -1 when the character is on the number, on a free line, or outside.
Public Function ColumnAtChar(ByVal shp As Object, ByVal charPos As Long) As Long
    Dim schema As IgtExample, tsv As String, numberText As String
    Dim tr As Object, nParas As Long, nTiers As Long, t As Long, nLines As Long
    Dim p As Long, pStart As Long, pLen As Long, para As Object, txt As String
    Dim L As Long, k As Long, cell As Long, acc As Long, i As Long, first As Object
    ColumnAtChar = -1
    On Error GoTo Done
    tsv = TagOf(shp, TAG_TSV)
    numberText = TagOf(shp, TAG_NUMBER)
    If tsv = "" Then Exit Function
    schema = ModelFromTsv(tsv)
    For t = 0 To schema.TierCount - 1
        If IsInterlinearTier(schema.Tiers(t)) Then nTiers = nTiers + 1
    Next t
    If nTiers = 0 Then Exit Function
    Set tr = shp.TextFrame2.TextRange
    nParas = tr.Paragraphs.Count
    If (nParas - schema.FreeCount) Mod nTiers <> 0 Then Exit Function
    nLines = (nParas - schema.FreeCount) \ nTiers
    ' The paragraph holding the character.
    For p = 1 To nParas
        Set para = tr.Paragraphs(p)
        pStart = para.Start
        pLen = para.Length
        If charPos >= pStart And charPos < pStart + pLen Then Exit For
    Next p
    If p > nLines * nTiers Then Exit Function          ' a free line, or past the end
    L = (p - 1) \ nTiers
    k = (p - 1) Mod nTiers
    txt = para.Text
    cell = CountTabs(Left$(txt, charPos - pStart))
    If L = 0 And k = 0 And Len(numberText) > 0 Then cell = cell - 1
    If cell < 0 Then Exit Function                       ' on the number
    ' The cells of the earlier wrap lines, from each line's first paragraph.
    For i = 0 To L - 1
        Set first = tr.Paragraphs(i * nTiers + 1)
        acc = acc + CountTabs(first.Text) + 1
        If i = 0 And Len(numberText) > 0 Then acc = acc - 1
    Next i
    ColumnAtChar = acc + cell
Done:
End Function

Private Function CountTabs(ByVal s As String) As Long
    CountTabs = Len(s) - Len(Replace(s, Chr$(9), ""))
End Function

'-----------------------------------------------------------------------------
' Small helpers
'-----------------------------------------------------------------------------
Public Function PresentationOf(ByVal shp As Object) As Object
    On Error Resume Next
    Set PresentationOf = shp.Parent.Parent
    If PresentationOf Is Nothing Then Set PresentationOf = Application.ActivePresentation
    Err.Clear
End Function

Public Function TagOf(ByVal shp As Object, ByVal nm As String) As String
    On Error Resume Next
    TagOf = shp.Tags.Item(nm)
    Err.Clear
End Function
