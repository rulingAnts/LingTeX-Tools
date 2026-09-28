Attribute VB_Name = "modPptFormat"
Option Explicit
'=============================================================================
' modPptFormat  --  LingTeX-PowerPoint
'
' How one cell's text goes into a TextRange2: the PowerPoint counterpart of
' modRender.WriteCellText in LingTeX-Word.  Used by the composer (drawing) AND
' by modPptMeasure, so a measured width can never disagree with what is drawn
' -- the same rule Word follows.
'
' The forms tier is italic.  Tiers of meta-language (glosses, categories) get
' small capitals on their grammatical segments, which are LOWERCASED first,
' because small capitals only affect lowercase letters: "ERG" under small caps
' renders as full capitals, "erg" as the small capitals Leipzig asks for.
' Read-back will upper-case the small-cap runs again, so the change is
' reversible, not lossy (Word does the same, marking the runs with a style;
' here the Smallcaps attribute itself is the mark).
'
' What is a segment, and what is grammatical, are the shared parser's:
' modFlexParse.SplitGlossSegments and IsGramGloss.  TierTakesSmallCaps and
' SmallCapsForm are copies of modRender's, five lines each, because modRender is
' Word-bound (Range, Document); when they move to a shared module, delete
' these two.
'
' Pure ASCII.  -1 and 0 for msoTrue and msoFalse.
'=============================================================================

Public Type PptTierFont
    Name   As String
    Size   As Double
    Italic As Boolean
End Type

' Tiers whose content is meta-language, and so take small caps on grammatical
' abbreviations.  Object-language rows never do: an all-caps vernacular word or
' a proper noun would be silently restyled.
Public Function TierTakesSmallCaps(ByVal role As String) As Boolean
    Select Case role
        Case ROLE_VERNACULAR, ROLE_MORPHEMES, ROLE_FREE
            TierTakesSmallCaps = False
        Case Else
            TierTakesSmallCaps = True
    End Select
End Function

' The lowercase form of a grammatical segment; initialCap keeps the first
' LETTER full-size (3SG -> 3Sg, ERG -> Erg).  Length is preserved either way,
' which WriteCell relies on to place the small-cap runs.
Public Function SmallCapsForm(ByVal part As String, ByVal initialCap As Boolean) As String
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

' The text as it will appear: grammatical segments lowercased on the tiers that
' take small caps; everything else as typed.
Public Function DisplayCellText(ByVal text As String, ByVal role As String, _
        ByVal lowercaseGram As Boolean, ByVal initialCap As Boolean) As String
    Dim parts() As String, n As Long, i As Long, out As String
    If Not TierTakesSmallCaps(role) Or Not lowercaseGram Then
        DisplayCellText = text
        Exit Function
    End If
    n = SplitGlossSegments(text, parts)
    For i = 0 To n - 1
        If IsGramGloss(parts(i)) Then
            out = out & SmallCapsForm(parts(i), initialCap)
        Else
            out = out & parts(i)
        End If
    Next i
    DisplayCellText = out
End Function

' Replace tr's text with one cell, in the tier's font: italic if the tier's
' font says so, small capitals on the grammatical segments of meta-language
' tiers.  tr is a TextRange2 (late-bound).
Public Sub WriteCell(ByVal tr As Object, ByVal text As String, ByVal role As String, _
        tf As PptTierFont, Optional ByVal lowercaseGram As Boolean = True, _
        Optional ByVal initialCap As Boolean = False)
    Dim shown As String
    shown = DisplayCellText(text, role, lowercaseGram, initialCap)
    tr.Text = shown
    With tr.Font
        .Name = tf.Name
        .Size = tf.Size
        If tf.Italic Then .Italic = -1 Else .Italic = 0
        .Smallcaps = 0
    End With
    If Len(shown) = 0 Then Exit Sub
    ApplyGramGlossRuns tr, text, role, 1
End Sub

' Set the grammatical segments of one cell in small capitals, the cell's text
' beginning at character startPos of tr (1-based).  Segments are those of the
' ORIGINAL text; SmallCapsForm keeps lengths, so the positions carry over to
' the text as shown.  Nothing happens on tiers that take no small caps.  The
' composer calls this once per cell of a paragraph; WriteCell once per cell box.
Public Sub ApplyGramGlossRuns(ByVal tr As Object, ByVal text As String, _
        ByVal role As String, ByVal startPos As Long)
    Dim parts() As String, n As Long, i As Long, pos As Long
    If Not TierTakesSmallCaps(role) Then Exit Sub
    If Len(text) = 0 Then Exit Sub
    n = SplitGlossSegments(text, parts)
    pos = startPos
    For i = 0 To n - 1
        If IsGramGloss(parts(i)) Then
            tr.Characters(pos, Len(parts(i))).Font.Smallcaps = -1
        End If
        pos = pos + Len(parts(i))
    Next i
End Sub
