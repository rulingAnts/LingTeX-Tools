Attribute VB_Name = "modPptRewrap"
Option Explicit
'=============================================================================
' modPptRewrap  --  LingTeX-PowerPoint
'
' READ BACK an example from its box, and RE-WRAP it to the box's width.
' The PowerPoint counterparts of Word's modReadBack and of its re-wrap
' commands, on the one-text-box design.
'
' READ-BACK reads the TEXT, not the tags, so that what the user typed into the
' box is what gets re-wrapped: the tags give the SHAPE (which tiers, how many
' free lines, the number) and the paragraphs give the content.  A paragraph
' per interlinear tier per wrap line, then the free lines: cells split on
' tabs, the number dropped from the first paragraph, wrap lines joined back
' into one row per tier, the quotes stripped from the free lines.  Small
' capitals are put back to capitals from the Smallcaps attribute itself, so
' "erg" set in small capitals reads back as ERG -- the reverse of
' modPptFormat.  A box whose rows no longer agree (a tab typed or deleted)
' reads back False and is left alone, with a message from the command.
'
' RE-WRAP measures, plans for the box's current width, composes in a scratch
' box of the same width, and -- only if the result differs from what the box
' holds -- saves the clipboard, pastes ONCE into the box (round 5: one undo
' entry, position, size and Tags untouched), and restores the clipboard.  A
' re-wrap that changes nothing writes nothing: no undo entry, no clipboard
' round trip, and no resize event from our own change (PLAN.md, step 2).
'
' Pure ASCII apart from the quotes from modFlexParse.
'=============================================================================

Private Const DEF_FONT As String = "Times New Roman"
Private Const DEF_SIZE As Double = 24
Private Const DEF_GAP As Double = 6
Private Const DEF_NUMBER_HANG As Double = 36

'-----------------------------------------------------------------------------
' The command: every selected LingTeX example re-wrapped to its box's width.
'-----------------------------------------------------------------------------
Public Sub LingTeXRewrapSelected()
    Dim app As Object, sr As Object, shp As Object, n As Long, done As Long, bad As String
    Set app = Application
    On Error Resume Next
    Set sr = app.ActiveWindow.Selection.ShapeRange
    On Error GoTo 0
    If sr Is Nothing Then
        MsgBox "Select an example first.", 48, "LingTeX"
        Exit Sub
    End If
    For Each shp In sr
        If IsLingTeXExample(shp) Then
            n = n + 1
            Select Case RewrapExample(shp)
                Case 1: done = done + 1
                Case -1: bad = bad & shp.Name & Chr$(13)
            End Select
        End If
    Next shp
    ReleaseScratch
    If n = 0 Then
        MsgBox "None of the selected shapes is a LingTeX example.", 48, "LingTeX"
    ElseIf bad <> "" Then
        MsgBox "Could not read back:" & Chr$(13) & bad & "The tiers no longer have the same number of columns (a tab typed or deleted?).", 48, "LingTeX"
    End If
End Sub

'-----------------------------------------------------------------------------
' Re-wrap one example.  Returns 1 changed, 0 unchanged (nothing written), -1
' could not read back.
'-----------------------------------------------------------------------------
Public Function RewrapExample(ByVal shp As Object) As Long
    Dim app As Object, ex As IgtExample, numberText As String, gran As Long
    Dim fonts() As PptTierFont, tf As PptTierFont, t As Long, lay As PptLayout, numW As Double
    Dim widths() As Double, cw() As Double, nb() As Boolean, lines() As Long
    Dim scratch As Object, sbox As Object, saved As Object, w As Double
    Set app = Application
    If Not ReadBackExample(shp, ex, numberText, gran) Then
        RewrapExample = -1
        Exit Function
    End If
    w = shp.Width - shp.TextFrame2.MarginLeft - shp.TextFrame2.MarginRight

    tf.Name = DEF_FONT: tf.Size = DEF_SIZE: tf.Italic = False
    ReDim fonts(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        fonts(t) = tf
        fonts(t).Italic = (ex.Tiers(t) = ROLE_VERNACULAR Or ex.Tiers(t) = ROLE_MORPHEMES)
    Next t
    lay.Gap = DEF_GAP: lay.LowercaseGram = True: lay.InitialCap = False: lay.FreeFont = tf
    If Len(numberText) > 0 Then
        numW = MeasureText(numberText, ROLE_FREE, tf) + DEF_GAP
        If numW > DEF_NUMBER_HANG Then lay.NumberHang = numW Else lay.NumberHang = DEF_NUMBER_HANG
    End If
    lay.ContIndent = lay.NumberHang

    MeasureExample ex, fonts, widths
    cw = ColumnWidths(ex, widths, lay.Gap)
    nb = NoBreakFlags(ex)
    lines = LimitLineColumns(ComputeWrapLines(cw, nb, w, lay.NumberHang, lay.ContIndent), ex.ColCount)

    On Error GoTo Fail
    Set scratch = app.Presentations.Add(0)
    Set sbox = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, shp.Width, 40)
    PrepareExampleBox sbox
    ComposeExample sbox, ex, fonts, cw, lines, numberText, lay
    If BoxSignature(sbox.TextFrame2.TextRange) = BoxSignature(shp.TextFrame2.TextRange) Then
        scratch.Saved = -1
        scratch.Close
        RewrapExample = 0
        Exit Function
    End If
    Set saved = SaveClipboard(scratch)
    sbox.TextFrame2.TextRange.Copy
    shp.TextFrame2.TextRange.Paste
    RestoreClipboard saved
    scratch.Saved = -1
    scratch.Close
    shp.Tags.Add TAG_TSV, ModelToTsv(ex)
    RewrapExample = 1
    Exit Function
Fail:
    On Error Resume Next
    RestoreClipboard saved
    If Not scratch Is Nothing Then
        scratch.Saved = -1
        scratch.Close
    End If
    RewrapExample = -1
End Function

'-----------------------------------------------------------------------------
' Read the example back from the box's text, its shape from the tags.
'-----------------------------------------------------------------------------
Public Function ReadBackExample(ByVal shp As Object, ByRef ex As IgtExample, _
        ByRef numberText As String, ByRef gran As Long) As Boolean
    Dim schema As IgtExample, tsv As String, tr As Object, nParas As Long
    Dim tiers() As Long, nTiers As Long, t As Long, k As Long, nLines As Long, L As Long, para As Long
    Dim rows() As String, nCells() As Long, txt As String, cells() As String, i As Long
    Dim colCount As Long, f As Long
    On Error GoTo Fail
    tsv = ""
    On Error Resume Next
    tsv = shp.Tags.Item(TAG_TSV)
    numberText = shp.Tags.Item(TAG_NUMBER)
    gran = Val(shp.Tags.Item(TAG_GRAN))
    On Error GoTo Fail
    If tsv = "" Then Exit Function
    schema = ModelFromTsv(tsv)
    If schema.TierCount = 0 Then Exit Function

    ReDim tiers(0 To schema.TierCount)
    nTiers = 0
    For t = 0 To schema.TierCount - 1
        If IsInterlinearTier(schema.Tiers(t)) Then
            tiers(nTiers) = t
            nTiers = nTiers + 1
        End If
    Next t
    If nTiers = 0 Then Exit Function

    Set tr = shp.TextFrame2.TextRange
    nParas = tr.Paragraphs.Count
    If nParas < nTiers Then Exit Function
    If (nParas - schema.FreeCount) Mod nTiers <> 0 Then Exit Function
    nLines = (nParas - schema.FreeCount) \ nTiers

    ' One growing row per tier: cells appended wrap line by wrap line.
    ReDim rows(0 To nTiers - 1, 0 To 0)
    ReDim nCells(0 To nTiers - 1)
    para = 0
    For L = 1 To nLines
        For k = 0 To nTiers - 1
            para = para + 1
            txt = TextWithCapsRestored(tr.Paragraphs(para), TierTakesSmallCaps(schema.Tiers(tiers(k))))
            txt = Replace(Replace(txt, Chr$(13), ""), Chr$(11), "")
            If L = 1 And k = 0 And Len(numberText) > 0 Then
                If Left$(txt, Len(numberText) + 1) = numberText & Chr$(9) Then txt = Mid$(txt, Len(numberText) + 2)
            End If
            cells = Split(txt, Chr$(9))
            For i = LBound(cells) To UBound(cells)
                If nCells(k) > UBound(rows, 2) Then ReDim Preserve rows(0 To nTiers - 1, 0 To UBound(rows, 2) * 2 + 1)
                rows(k, nCells(k)) = cells(i)
                nCells(k) = nCells(k) + 1
            Next i
        Next k
    Next L
    colCount = nCells(0)
    For k = 1 To nTiers - 1
        If nCells(k) <> colCount Then Exit Function
    Next k
    If colCount = 0 Then Exit Function

    ex = NewExample(nTiers, colCount)
    For k = 0 To nTiers - 1
        ex.Tiers(k) = schema.Tiers(tiers(k))
        For i = 0 To colCount - 1
            SetCell ex, k, i, rows(k, i)
        Next i
    Next k
    For f = 1 To schema.FreeCount
        para = para + 1
        txt = tr.Paragraphs(para).Text
        txt = Replace(Replace(txt, Chr$(13), ""), Chr$(11), "")
        If Left$(txt, 1) = LeftSingleQuote Then txt = Mid$(txt, 2)
        If Right$(txt, 1) = RightSingleQuote Then txt = Left$(txt, Len(txt) - 1)
        AddFreeLine ex, txt
    Next f
    ex.LineNum = schema.LineNum
    ReadBackExample = True
    Exit Function
Fail:
    ReadBackExample = False
End Function

' A paragraph's text with every character set in small capitals upper-cased
' again -- only on tiers that take small caps; other tiers as they are.
Private Function TextWithCapsRestored(ByVal p As Object, ByVal restore As Boolean) As String
    Dim s As String, n As Long, i As Long, ch As String
    s = p.Text
    If Not restore Then
        TextWithCapsRestored = s
        Exit Function
    End If
    n = Len(s)
    For i = 1 To n
        ch = Mid$(s, i, 1)
        If ch <> Chr$(13) And ch <> Chr$(11) And ch <> Chr$(9) And ch <> " " Then
            If p.Characters(i, 1).Font.Smallcaps = -1 Then Mid$(s, i, 1) = UCase$(ch)
        End If
    Next i
    TextWithCapsRestored = s
End Function

' What a box holds, as one string: each paragraph's text and tab stops.  Two
' compositions with the same signature look the same on the slide.
Public Function BoxSignature(ByVal tr As Object) As String
    Dim i As Long, j As Long, s As String, t As String
    On Error Resume Next
    For i = 1 To tr.Paragraphs.Count
        t = tr.Paragraphs(i).Text
        t = Replace(Replace(t, Chr$(13), ""), Chr$(11), "")
        s = s & "|" & t & "#"
        With tr.Paragraphs(i).ParagraphFormat
            s = s & Format$(.LeftIndent, "0.#") & "/" & Format$(.FirstLineIndent, "0.#") & "["
            For j = 1 To .TabStops.Count
                If j > 1 Then s = s & ","
                s = s & Format$(.TabStops.Item(j).Position, "0.#")
            Next j
            s = s & "]"
        End With
    Next i
    BoxSignature = s
End Function
