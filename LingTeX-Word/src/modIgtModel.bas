Attribute VB_Name = "modIgtModel"
Option Explicit

'=============================================================================
' modIgtModel  --  LingTeX-Word
'
' The in-memory interlinear example: a tier x column grid plus free
' translations, and the operations that edit it.
'
' A COLUMN IS AN ALIGNMENT SLOT, AGNOSTIC ABOUT WHAT IT HOLDS.
' It may be a whole word, a single morpheme, or part of a word.  An example may
' be word-aligned, morpheme-aligned, or a mixture -- one affix split out of an
' otherwise word-aligned example is normal and supported.  Nothing in this
' module, the renderer, the measurement pass or the wrap planner may assume
' "one column = one word".
'
' Two invariants hold over INTERLINEAR cells.  Free-translation rows are exempt
' from both, because a translation is prose, not an aligned slot.
'   1. Column break-character agreement.  If any cell in a column carries a
'      morpheme break character at an end, every other interlinear cell in that
'      column carries the same character at the same end.
'   2. No spaces inside an interlinear cell; use "." or "_".
' modLeipzig checks and repairs both.  SplitColumn below satisfies invariant 1
' by construction.
'
' Hand port of ..\tools\reference.js (modelFromBlock, projectColumns,
' mergeColumns, splitColumn).  reference.js is the executable specification and
' is covered by ..\tools\parity-test.js.  IF YOU CHANGE AN ALGORITHM HERE,
' CHANGE IT THERE TOO.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-- Tier roles.  These are also the suffixes of the Word paragraph styles the
'   renderer applies, which is what makes a rendered example self-describing.
Public Const ROLE_VERNACULAR As String = "Vernacular"
Public Const ROLE_MORPHEMES  As String = "Morphemes"
Public Const ROLE_GLOSS      As String = "Gloss"
Public Const ROLE_WORDGLOSS  As String = "Word Gloss"
Public Const ROLE_CATEGORY   As String = "Category"
Public Const ROLE_FREE       As String = "Free"

'-- Granularity of the initial projection from FLEx columns.
Public Enum IgtGranularity
    igtWordAligned = 0
    igtMorphemeAligned = 1
End Enum

'-- The model.  Cells is (tierIndex, columnIndex); columns are the LAST
'   dimension so that ReDim Preserve can grow them, which it can only do on the
'   final dimension.
Public Type IgtExample
    Tiers()     As String
    Cells()     As String
    TierCount   As Long
    ColCount    As Long
    FreeLines() As String
    FreeCount   As Long
    LineNum     As String
End Type


'=============================================================================
' -- CONSTRUCTION AND ACCESS ------------------------------------------------
'=============================================================================

Public Function NewExample(ByVal tierCount As Long, ByVal colCount As Long) As IgtExample
    Dim ex As IgtExample
    ex.TierCount = tierCount
    ex.ColCount = colCount
    If tierCount > 0 Then
        ReDim ex.Tiers(0 To tierCount - 1)
        ReDim ex.Cells(0 To tierCount - 1, 0 To IIf(colCount > 0, colCount - 1, 0))
    End If
    ReDim ex.FreeLines(0 To 7)
    ex.FreeCount = 0
    NewExample = ex
End Function

Public Function GetCell(ex As IgtExample, ByVal t As Long, ByVal c As Long) As String
    If t < 0 Or t >= ex.TierCount Then Exit Function
    If c < 0 Or c >= ex.ColCount Then Exit Function
    GetCell = ex.Cells(t, c)
End Function

Public Sub SetCell(ByRef ex As IgtExample, ByVal t As Long, ByVal c As Long, ByVal v As String)
    If t < 0 Or t >= ex.TierCount Then Exit Sub
    If c < 0 Or c >= ex.ColCount Then Exit Sub
    ex.Cells(t, c) = v
End Sub

' True for tiers bound by the interlinear invariants, i.e. everything but Free.
Public Function IsInterlinearTier(ByVal role As String) As Boolean
    IsInterlinearTier = (role <> ROLE_FREE)
End Function

Public Function TierIndex(ex As IgtExample, ByVal role As String) As Long
    Dim t As Long
    TierIndex = -1
    For t = 0 To ex.TierCount - 1
        If ex.Tiers(t) = role Then
            TierIndex = t
            Exit Function
        End If
    Next t
End Function

' Index of the first interlinear tier -- the object-language row.
Public Function FormTierIndex(ex As IgtExample) As Long
    Dim t As Long
    FormTierIndex = -1
    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            FormTierIndex = t
            Exit Function
        End If
    Next t
End Function

Public Sub AddFreeLine(ByRef ex As IgtExample, ByVal s As String)
    If Trim$(s) = "" Then Exit Sub
    If ex.FreeCount > UBound(ex.FreeLines) Then
        ReDim Preserve ex.FreeLines(0 To UBound(ex.FreeLines) * 2 + 1)
    End If
    ex.FreeLines(ex.FreeCount) = Trim$(s)
    ex.FreeCount = ex.FreeCount + 1
End Sub


'=============================================================================
' -- BUILDING FROM FLEX -----------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Does this text carry FLEx tier labels?
'
' This matters because the FLEx parser treats column 0 of every row as a tier
' label.  Plain TSV -- a table the user built by hand, or this add-in's own TSV
' pasted back in -- has no label there, so sending it down the FLEx path would
' silently swallow the first cell of every row.
'
' Port of reference.js looksLikeFlex.
'-----------------------------------------------------------------------------
Public Function LooksLikeFlex(ByVal raw As String) As Boolean
    Dim lines() As String, i As Long, j As Long
    Dim ln As String, fields() As String, first As String

    raw = Replace(Replace(raw, vbCrLf, vbLf), vbCr, vbLf)
    lines = Split(raw, vbLf)

    For i = 0 To UBound(lines)
        ln = NormalizeLabels(StripInvisible(lines(i)))
        If Trim$(ln) = "" Then GoTo NextLine

        If InStr(ln, vbTab) > 0 Then
            fields = Split(ln, vbTab)
        Else
            fields = Split(Trim$(ln), " ")
        End If

        first = ""
        For j = 0 To UBound(fields)
            If Trim$(fields(j)) <> "" Then
                first = Trim$(fields(j))
                Exit For
            End If
        Next j
        If first = "" Then GoTo NextLine

        Select Case first
            Case TIER_WORD, TIER_MORPHEMES, TIER_LEXENTRIES, _
                 TIER_LEXGLOSS, TIER_WORDGLOSS, TIER_WORDCAT
                LooksLikeFlex = True
                Exit Function
        End Select
        If LCase$(Left$(first, 4)) = "free" Then
            LooksLikeFlex = True
            Exit Function
        End If
NextLine:
    Next i
End Function

' First example in raw text, routed by inspection to the FLEx or plain-TSV path.
Public Function ModelFromText(ByVal raw As String, _
        ByVal granularity As IgtGranularity) As IgtExample
    Dim models() As IgtExample, n As Long
    models = ModelsFromText(raw, granularity, n)
    If n > 0 Then ModelFromText = models(0)
End Function

' Every example in raw text, routed by inspection.
Public Function ModelsFromText(ByVal raw As String, _
        ByVal granularity As IgtGranularity, ByRef outCount As Long) As IgtExample()
    Dim models() As IgtExample
    Dim ex As IgtExample

    If LooksLikeFlex(raw) Then
        ModelsFromText = ModelsFromFlex(raw, granularity, outCount)
        Exit Function
    End If

    ex = ModelFromTsv(raw)
    If ex.TierCount = 0 Then
        outCount = 0
        ReDim models(-1 To -1)
    Else
        outCount = 1
        ReDim models(0 To 0)
        models(0) = ex
    End If
    ModelsFromText = models
End Function

' First block of FLEx-labelled text.  Prefer ModelFromText unless the caller
' already knows the input is FLEx output.
Public Function ModelFromFlex(ByVal raw As String, _
        ByVal granularity As IgtGranularity) As IgtExample
    Dim models() As IgtExample, n As Long
    models = ModelsFromFlex(raw, granularity, n)
    If n > 0 Then ModelFromFlex = models(0)
End Function

' Every block of raw FLEx or TSV text.
Public Function ModelsFromFlex(ByVal raw As String, _
        ByVal granularity As IgtGranularity, ByRef outCount As Long) As IgtExample()

    Dim blocks() As FlexBlock
    Dim models() As IgtExample
    Dim i As Long, n As Long
    Dim ex As IgtExample

    blocks = ParseFlexBlocks(raw)
    If UBound(blocks) < 0 Then
        outCount = 0
        ReDim models(-1 To -1)
        ModelsFromFlex = models
        Exit Function
    End If

    ReDim models(0 To UBound(blocks))
    n = 0
    For i = 0 To UBound(blocks)
        ex = ModelFromBlock(blocks(i), granularity)
        If ex.TierCount > 0 And ex.ColCount > 0 Then
            models(n) = ex
            n = n + 1
        End If
    Next i

    outCount = n
    If n = 0 Then
        ReDim models(-1 To -1)
    Else
        ReDim Preserve models(0 To n - 1)
    End If
    ModelsFromFlex = models
End Function

'-----------------------------------------------------------------------------
' Project one parsed FLEx block onto alignment columns.
' Port of reference.js modelFromBlock + projectColumns.
'-----------------------------------------------------------------------------
Public Function ModelFromBlock(b As FlexBlock, _
        ByVal granularity As IgtGranularity) As IgtExample

    Dim ex As IgtExample
    Dim t As Long, i As Long, s As Long, c As Long
    Dim morphIdx As Long, glossIdx As Long, wgIdx As Long, catIdx As Long, wordIdx As Long
    Dim formIdx As Long, dataStart As Long
    Dim formArr() As String, glossArr() As String
    Dim words() As IgtWord, nWords As Long
    Dim forms() As String, glosses() As String
    Dim spanStart() As Long, spanEnd() As Long
    Dim nCols As Long
    Dim tierRoles() As String, tierCols() As Variant, nTiers As Long

    morphIdx = -1: glossIdx = -1: wgIdx = -1: catIdx = -1: wordIdx = -1

    For t = 0 To b.TierCount - 1
        Select Case b.LineTypes(t)
            Case TIER_MORPHEMES, TIER_LEXENTRIES
                If morphIdx < 0 Then morphIdx = t
            Case TIER_LEXGLOSS
                If glossIdx < 0 Then glossIdx = t
            Case TIER_WORDGLOSS
                If wgIdx < 0 Then wgIdx = t
            Case TIER_WORDCAT
                If catIdx < 0 Then catIdx = t
            Case TIER_WORD
                If wordIdx < 0 Then wordIdx = t
        End Select
    Next t

    If morphIdx >= 0 Then
        formIdx = morphIdx
    Else
        formIdx = wordIdx
    End If
    If formIdx < 0 Then Exit Function          ' no recognisable form tier

    formArr = b.ColArrays(formIdx)
    If glossIdx >= 0 Then
        glossArr = b.ColArrays(glossIdx)
    Else
        ReDim glossArr(-1 To -1)
    End If

    ' Skip the tier label, and an example number if FLEx put one in column 1.
    dataStart = 1
    If UBound(formArr) >= dataStart Then
        If IsAllDigits(formArr(dataStart)) Then dataStart = dataStart + 1
    End If

    words = GroupSegmentsFromColumns(formArr, glossArr, dataStart, nWords)
    HandleStandalonePunctuation words, nWords
    If nWords = 0 Then Exit Function

    '-- Project the segment list at the requested granularity ----------------
    ReDim forms(0 To CountProjected(words, nWords, granularity) - 1)
    ReDim glosses(0 To UBound(forms))
    ReDim spanStart(0 To UBound(forms))
    ReDim spanEnd(0 To UBound(forms))

    nCols = 0
    For i = 0 To nWords - 1
        If granularity = igtMorphemeAligned Then
            For s = 0 To words(i).SegCount - 1
                ' The boundary character leads BOTH cells, which is exactly
                ' invariant 1 satisfied by construction.
                forms(nCols) = words(i).Segments(s).Bd & words(i).Segments(s).Form
                glosses(nCols) = words(i).Segments(s).Bd & words(i).Segments(s).Gloss
                If s = 0 Then
                    ' Only a word's first column carries its word-level tiers.
                    spanStart(nCols) = words(i).StartCol
                    spanEnd(nCols) = words(i).EndCol
                Else
                    spanStart(nCols) = -1
                    spanEnd(nCols) = -1
                End If
                nCols = nCols + 1
            Next s
        Else
            forms(nCols) = JoinForm(words(i))
            glosses(nCols) = JoinGloss(words(i))
            spanStart(nCols) = words(i).StartCol
            spanEnd(nCols) = words(i).EndCol
            nCols = nCols + 1
        End If
    Next i

    '-- Assemble the tier rows ----------------------------------------------
    ReDim tierRoles(0 To 5)
    ReDim tierCols(0 To 5)
    nTiers = 0

    ' A surface-word tier, when FLEx supplied one alongside the morpheme tier.
    If morphIdx >= 0 And wordIdx >= 0 Then
        tierRoles(nTiers) = ROLE_VERNACULAR
        tierCols(nTiers) = PerWordTier(b.ColArrays(wordIdx), spanStart, spanEnd, nCols)
        nTiers = nTiers + 1
    End If

    ' The form tier keeps the role FLEx gave it, so the paragraph style in the
    ' rendered table says whether the row is surface words or a breakdown.
    If morphIdx >= 0 Then
        tierRoles(nTiers) = ROLE_MORPHEMES
    Else
        tierRoles(nTiers) = ROLE_VERNACULAR
    End If
    tierCols(nTiers) = forms
    nTiers = nTiers + 1

    If glossIdx >= 0 Then
        tierRoles(nTiers) = ROLE_GLOSS
        tierCols(nTiers) = glosses
        nTiers = nTiers + 1
    End If

    If wgIdx >= 0 Then
        tierRoles(nTiers) = ROLE_WORDGLOSS
        tierCols(nTiers) = PerWordTier(b.ColArrays(wgIdx), spanStart, spanEnd, nCols)
        nTiers = nTiers + 1
    End If

    If catIdx >= 0 Then
        tierRoles(nTiers) = ROLE_CATEGORY
        tierCols(nTiers) = PerWordTier(b.ColArrays(catIdx), spanStart, spanEnd, nCols)
        nTiers = nTiers + 1
    End If

    ex = NewExample(nTiers, nCols)
    For t = 0 To nTiers - 1
        Dim src() As String
        src = tierCols(t)
        ex.Tiers(t) = tierRoles(t)
        For c = 0 To nCols - 1
            ex.Cells(t, c) = src(c)
        Next c
    Next t

    ex.LineNum = b.LineNum
    For i = 0 To b.FreeCount - 1
        AddFreeLine ex, b.FreeLines(i)
    Next i

    DropEmptyTiers ex
    ModelFromBlock = ex
End Function

Private Function CountProjected(words() As IgtWord, ByVal nWords As Long, _
        ByVal granularity As IgtGranularity) As Long
    Dim i As Long, n As Long
    If granularity = igtMorphemeAligned Then
        For i = 0 To nWords - 1
            n = n + words(i).SegCount
        Next i
    Else
        n = nWords
    End If
    If n = 0 Then n = 1
    CountProjected = n
End Function

'-----------------------------------------------------------------------------
' A per-word tier such as Word Gloss or Word Cat. holds one value per word
' group, not one per morpheme, so its cells are collected from the source
' columns the word spans.  docs\core.js emits a placeholder for these tiers
' instead of rendering them; this renders them properly.
'
' Several values inside one span are joined with "." rather than a space,
' because a space inside an interlinear cell would violate invariant 2.
'-----------------------------------------------------------------------------
Private Function PerWordTier(srcV As Variant, spanStart() As Long, _
        spanEnd() As Long, ByVal nCols As Long) As String()

    Dim src() As String, out() As String
    Dim c As Long, k As Long, v As String, acc As String

    src = srcV
    ReDim out(0 To IIf(nCols > 0, nCols - 1, 0))

    For c = 0 To nCols - 1
        acc = ""
        If spanStart(c) >= 0 Then
            For k = spanStart(c) To spanEnd(c)
                If k >= LBound(src) And k <= UBound(src) Then
                    v = Trim$(src(k))
                    If v <> "" Then
                        If acc <> "" Then acc = acc & "."
                        acc = acc & v
                    End If
                End If
            Next k
        End If
        out(c) = acc
    Next c

    PerWordTier = out
End Function

' Remove tiers that ended up with no data in any column.  This is the
' "renders those that have data" rule: an empty tier is not drawn at all.
Public Sub DropEmptyTiers(ByRef ex As IgtExample)
    Dim keep() As Boolean, t As Long, c As Long, nKeep As Long
    ' Not named "any": Any is a reserved word in VBA (it appears in Declare
    ' statements as "As Any"), so Dim any As Boolean is a syntax error.
    Dim hasData As Boolean

    If ex.TierCount = 0 Then Exit Sub
    ReDim keep(0 To ex.TierCount - 1)

    For t = 0 To ex.TierCount - 1
        hasData = False
        For c = 0 To ex.ColCount - 1
            If ex.Cells(t, c) <> "" Then
                hasData = True
                Exit For
            End If
        Next c
        keep(t) = hasData
        If hasData Then nKeep = nKeep + 1
    Next t

    If nKeep = ex.TierCount Then Exit Sub
    KeepTiers ex, keep, nKeep
End Sub

' Rebuild the grid keeping only the flagged tiers.  The tier dimension is
' first, and ReDim Preserve can only resize the last, so this rebuilds rather
' than resizing.
Private Sub KeepTiers(ByRef ex As IgtExample, keep() As Boolean, ByVal nKeep As Long)
    Dim newTiers() As String, newCells() As String
    Dim t As Long, c As Long, d As Long

    If nKeep = 0 Then
        ex.TierCount = 0
        ex.ColCount = 0
        Exit Sub
    End If

    ReDim newTiers(0 To nKeep - 1)
    ReDim newCells(0 To nKeep - 1, 0 To IIf(ex.ColCount > 0, ex.ColCount - 1, 0))

    d = 0
    For t = 0 To ex.TierCount - 1
        If keep(t) Then
            newTiers(d) = ex.Tiers(t)
            For c = 0 To ex.ColCount - 1
                newCells(d, c) = ex.Cells(t, c)
            Next c
            d = d + 1
        End If
    Next t

    ex.Tiers = newTiers
    ex.Cells = newCells
    ex.TierCount = nKeep
End Sub

Private Function IsAllDigits(ByVal s As String) As Boolean
    Dim i As Long, ch As String
    If Len(s) = 0 Then Exit Function
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch < "0" Or ch > "9" Then Exit Function
    Next i
    IsAllDigits = True
End Function


'=============================================================================
' -- TSV ROUND TRIP ---------------------------------------------------------
'=============================================================================

' Build a model from plain TSV: one row per tier, columns tab separated.
' Roles are assigned positionally; a row with no tabs is taken as a free
' translation, which is how a pasted block can carry its own translation line.
Public Function ModelFromTsv(ByVal tsv As String) As IgtExample
    Dim ex As IgtExample
    Dim lines() As String, i As Long, c As Long
    Dim rows() As Variant, roles() As String, nRows As Long
    Dim cols() As String, maxCols As Long
    Dim freeAcc() As String, nFree As Long

    tsv = Replace(Replace(tsv, vbCrLf, vbLf), vbCr, vbLf)
    lines = Split(tsv, vbLf)

    ReDim rows(0 To UBound(lines))
    ReDim roles(0 To UBound(lines))
    ReDim freeAcc(0 To UBound(lines))

    For i = 0 To UBound(lines)
        If Trim$(lines(i)) = "" Then GoTo NextLine
        If InStr(lines(i), vbTab) = 0 Then
            freeAcc(nFree) = Trim$(lines(i))
            nFree = nFree + 1
            GoTo NextLine
        End If
        cols = Split(lines(i), vbTab)
        For c = 0 To UBound(cols)
            cols(c) = Trim$(cols(c))
        Next c
        rows(nRows) = cols
        roles(nRows) = PositionalRole(nRows)
        If UBound(cols) + 1 > maxCols Then maxCols = UBound(cols) + 1
        nRows = nRows + 1
NextLine:
    Next i

    If nRows = 0 Then Exit Function

    ex = NewExample(nRows, maxCols)
    For i = 0 To nRows - 1
        Dim src() As String
        src = rows(i)
        ex.Tiers(i) = roles(i)
        For c = 0 To maxCols - 1
            If c <= UBound(src) Then ex.Cells(i, c) = src(c)
        Next c
    Next i
    For i = 0 To nFree - 1
        AddFreeLine ex, freeAcc(i)
    Next i

    ModelFromTsv = ex
End Function

' Row 1 is the object language, row 2 its gloss, then the word-level tiers.
Private Function PositionalRole(ByVal i As Long) As String
    Select Case i
        Case 0: PositionalRole = ROLE_VERNACULAR
        Case 1: PositionalRole = ROLE_GLOSS
        Case 2: PositionalRole = ROLE_WORDGLOSS
        Case 3: PositionalRole = ROLE_CATEGORY
        Case Else: PositionalRole = ROLE_CATEGORY
    End Select
End Function

Public Function ModelToTsv(ex As IgtExample) As String
    Dim t As Long, c As Long, s As String, row As String
    For t = 0 To ex.TierCount - 1
        row = ""
        For c = 0 To ex.ColCount - 1
            If c > 0 Then row = row & vbTab
            row = row & ex.Cells(t, c)
        Next c
        If s <> "" Then s = s & vbLf
        s = s & row
    Next t
    For t = 0 To ex.FreeCount - 1
        If s <> "" Then s = s & vbLf
        s = s & ex.FreeLines(t)
    Next t
    ModelToTsv = s
End Function


'=============================================================================
' -- COLUMN EDITING ---------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Concatenate columns first..last into one.
' Interlinear cells join with nothing, so "zomu" + "-xa" becomes "zomu-xa".
' Free rows are prose, so they join with a space instead.
'-----------------------------------------------------------------------------
Public Function MergeColumns(ByRef ex As IgtExample, _
        ByVal firstIdx As Long, ByVal lastIdx As Long) As Boolean

    Dim t As Long, c As Long, acc As String, span As Long
    Dim sep As String

    If firstIdx < 0 Or lastIdx >= ex.ColCount Or lastIdx <= firstIdx Then Exit Function
    span = lastIdx - firstIdx

    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            sep = ""
        Else
            sep = " "
        End If
        acc = ""
        For c = firstIdx To lastIdx
            If acc <> "" And ex.Cells(t, c) <> "" And sep <> "" Then acc = acc & sep
            acc = acc & ex.Cells(t, c)
        Next c
        ex.Cells(t, firstIdx) = acc
        ' Shift the tail left over the columns just consumed.
        For c = lastIdx + 1 To ex.ColCount - 1
            ex.Cells(t, c - span) = ex.Cells(t, c)
        Next c
    Next t

    ex.ColCount = ex.ColCount - span
    ' ReDim Preserve may only change the LAST bound, so the tier bound is
    ' restated unchanged and only ColCount moves.
    ReDim Preserve ex.Cells(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)
    MergeColumns = True
End Function

'-----------------------------------------------------------------------------
' Split column colIdx at the nth (1-based) segmentable boundary in each
' interlinear cell.
'
' The boundary character goes to the START of the right-hand piece, because in
' Leipzig notation the boundary belongs to the affix -- which also means the new
' column satisfies invariant 1 by construction.
'
' "." and ":" are rule 4 one-to-many markers inside a single gloss and are never
' split points.  A leading boundary belongs to this column, so the scan starts
' at character 2.
'
' Returns False when some interlinear tier had fewer boundaries than asked for:
' that is exactly the rule 2 parity problem, so the cell is left whole on the
' left with the right column empty and outShortTiers names the tiers, rather
' than guessing where the morpheme break should have been.
'-----------------------------------------------------------------------------
Public Function SplitColumn(ByRef ex As IgtExample, ByVal colIdx As Long, _
        ByVal occurrence As Long, ByRef outShortTiers As String) As Boolean

    Dim t As Long, c As Long, i As Long
    Dim leftPart() As String, rightPart() As String
    Dim cell As String, seen As Long, at As Long

    ' Each early exit names its own reason. The caller reports
    ' "No morpheme break was found in: " & outShortTiers, so an empty string here
    ' produced a message that stopped at the colon with nothing after it.
    outShortTiers = ""
    If colIdx < 0 Or colIdx >= ex.ColCount Then
        outShortTiers = "(that column is outside the example)"
        Exit Function
    End If
    If occurrence < 1 Then occurrence = 1
    If ex.TierCount = 0 Then
        outShortTiers = "(the example has no tiers)"
        Exit Function
    End If

    ReDim leftPart(0 To ex.TierCount - 1)
    ReDim rightPart(0 To ex.TierCount - 1)

    For t = 0 To ex.TierCount - 1
        cell = ex.Cells(t, colIdx)
        If Not IsInterlinearTier(ex.Tiers(t)) Then
            ' A free-translation row has no column structure to split.
            leftPart(t) = cell
            rightPart(t) = ""
        Else
            seen = 0
            at = 0
            For i = 2 To Len(cell)
                If IsBoundary(Mid$(cell, i, 1)) Then
                    seen = seen + 1
                    If seen = occurrence Then
                        at = i
                        Exit For
                    End If
                End If
            Next i
            If at = 0 Then
                leftPart(t) = cell
                rightPart(t) = ""
                If cell <> "" Then
                    If outShortTiers <> "" Then outShortTiers = outShortTiers & ", "
                    outShortTiers = outShortTiers & ex.Tiers(t)
                End If
            Else
                leftPart(t) = Left$(cell, at - 1)
                rightPart(t) = Mid$(cell, at)
            End If
        End If
    Next t

    ' Grow by one column and shift the tail right.
    ex.ColCount = ex.ColCount + 1
    ' ReDim Preserve may only change the LAST bound, so the tier bound is
    ' restated unchanged and only ColCount moves.
    ReDim Preserve ex.Cells(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)
    For t = 0 To ex.TierCount - 1
        For c = ex.ColCount - 1 To colIdx + 2 Step -1
            ex.Cells(t, c) = ex.Cells(t, c - 1)
        Next c
        ex.Cells(t, colIdx) = leftPart(t)
        ex.Cells(t, colIdx + 1) = rightPart(t)
    Next t

    SplitColumn = (outShortTiers = "")
End Function

Public Sub InsertColumn(ByRef ex As IgtExample, ByVal atIdx As Long)
    Dim t As Long, c As Long
    If atIdx < 0 Then atIdx = 0
    If atIdx > ex.ColCount Then atIdx = ex.ColCount
    ex.ColCount = ex.ColCount + 1
    ' ReDim Preserve may only change the LAST bound, so the tier bound is
    ' restated unchanged and only ColCount moves.
    ReDim Preserve ex.Cells(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)
    For t = 0 To ex.TierCount - 1
        For c = ex.ColCount - 1 To atIdx + 1 Step -1
            ex.Cells(t, c) = ex.Cells(t, c - 1)
        Next c
        ex.Cells(t, atIdx) = ""
    Next t
End Sub

Public Sub DeleteColumn(ByRef ex As IgtExample, ByVal atIdx As Long)
    Dim t As Long, c As Long
    If atIdx < 0 Or atIdx >= ex.ColCount Then Exit Sub
    For t = 0 To ex.TierCount - 1
        For c = atIdx To ex.ColCount - 2
            ex.Cells(t, c) = ex.Cells(t, c + 1)
        Next c
    Next t
    ex.ColCount = ex.ColCount - 1
    If ex.ColCount > 0 Then
        ' ReDim Preserve may only change the LAST bound, so the tier bound is
    ' restated unchanged and only ColCount moves.
    ReDim Preserve ex.Cells(0 To ex.TierCount - 1, 0 To ex.ColCount - 1)
    End If
End Sub

Public Sub InsertTierRow(ByRef ex As IgtExample, ByVal atIdx As Long, ByVal role As String)
    Dim newTiers() As String, newCells() As String
    Dim t As Long, c As Long, d As Long

    If atIdx < 0 Then atIdx = 0
    If atIdx > ex.TierCount Then atIdx = ex.TierCount

    ReDim newTiers(0 To ex.TierCount)
    ReDim newCells(0 To ex.TierCount, 0 To IIf(ex.ColCount > 0, ex.ColCount - 1, 0))

    d = 0
    For t = 0 To ex.TierCount
        If t = atIdx Then
            newTiers(t) = role
        Else
            newTiers(t) = ex.Tiers(d)
            For c = 0 To ex.ColCount - 1
                newCells(t, c) = ex.Cells(d, c)
            Next c
            d = d + 1
        End If
    Next t

    ex.Tiers = newTiers
    ex.Cells = newCells
    ex.TierCount = ex.TierCount + 1
End Sub

Public Sub DeleteTierRow(ByRef ex As IgtExample, ByVal atIdx As Long)
    Dim keep() As Boolean, t As Long, nKeep As Long
    If atIdx < 0 Or atIdx >= ex.TierCount Then Exit Sub
    ReDim keep(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        keep(t) = (t <> atIdx)
        If keep(t) Then nKeep = nKeep + 1
    Next t
    KeepTiers ex, keep, nKeep
End Sub


'=============================================================================
' -- PLAIN TEXT LINES: WHAT A PERSON TYPES ----------------------------------
'=============================================================================
' The words of a sentence on one line, their glosses on the next, a
' translation under them, blank lines anywhere (Seth, 2026-09-14): the input
' of LingTeXTextToInterlinear. These turn it into an example -- the tier lines
' split at spaces into columns, positional roles as ModelFromTsv gives them,
' the trailing lines the user names as translations -- and morpheme-align the
' result when the document says so. Pure string work, so it lives with the
' model and the doc tests drive it without a document.
'
' Word's own "convert text to table" was the first idea. It would have made an
' empty cell of every second space, needed the translation rows merged, and
' then been read back as a table; the model is the shorter road, and the
' tested one.

' The non-empty lines of a text, cleaned: a paragraph mark or line feed ends
' a line; a manual line break (Chr 11), a tab or a non-breaking space is a
' space; runs of spaces are one; invisible marks are gone; ends are trimmed.
' 0-based, or (-1 To -1) when there is none, as ModelsFromText returns.
Public Function TextLines(ByVal raw As String) As String()
    Dim parts() As String
    Dim out() As String
    Dim i As Long, n As Long
    Dim ln As String

    raw = Replace(Replace(raw, vbCrLf, vbLf), vbCr, vbLf)
    parts = Split(raw, vbLf)
    If UBound(parts) < 0 Then                ' "" splits to nothing at all
        ReDim out(-1 To -1)
        TextLines = out
        Exit Function
    End If
    ReDim out(0 To UBound(parts))
    For i = 0 To UBound(parts)
        ln = CleanTextLine(parts(i))
        If ln <> "" Then
            out(n) = ln
            n = n + 1
        End If
    Next i
    If n = 0 Then
        ReDim out(-1 To -1)
    Else
        ReDim Preserve out(0 To n - 1)
    End If
    TextLines = out
End Function

' One line as TextLines wants it. Word's own control characters go too: a
' cell mark (7), an inline shape (1), a footnote or comment mark (2, 5), a
' drawn object (8), field marks (19, 20, 21), an optional hyphen (31) -- a
' whole cell selected in a table ends in a cell mark, which would otherwise
' be a one-"word" line of its own (the review, 2026-09-14). A column break
' (14) is a space, a non-breaking hyphen (30) a hyphen.
Public Function CleanTextLine(ByVal s As String) As String
    s = StripInvisible(s)
    s = Replace(s, Chr(11), " ")           ' manual line break: the same line
    s = Replace(s, Chr(12), " ")           ' page break
    s = Replace(s, Chr(14), " ")           ' column break
    s = Replace(s, vbTab, " ")
    s = Replace(s, ChrW(&HA0), " ")        ' non-breaking space
    s = Replace(s, Chr(30), "-")           ' non-breaking hyphen
    s = Replace(s, Chr(1), "")
    s = Replace(s, Chr(2), "")
    s = Replace(s, Chr(5), "")
    s = Replace(s, Chr(7), "")
    s = Replace(s, Chr(8), "")
    s = Replace(s, Chr(19), "")
    s = Replace(s, Chr(20), "")
    s = Replace(s, Chr(21), "")
    s = Replace(s, Chr(31), "")
    Do While InStr(s, "  ") > 0
        s = Replace(s, "  ", " ")
    Loop
    CleanTextLine = Trim$(s)
End Function

' Words in a cleaned line.
Public Function WordCount(ByVal ln As String) As Long
    ln = Trim$(ln)
    If ln = "" Then Exit Function
    WordCount = UBound(Split(ln, " ")) + 1
End Function

' A leading example number -- (1), (12a), 1), 1. -- dropped from a line: the
' document numbers its examples itself, and the token would otherwise become
' a column. The line unchanged when it does not begin with one.
Public Function StripExampleNumber(ByVal ln As String) As String
    Dim sp As Long
    StripExampleNumber = ln
    sp = InStr(ln, " ")
    If sp = 0 Then Exit Function           ' one word is never a number to drop
    If IsExampleNumberToken(Left$(ln, sp - 1)) Then
        StripExampleNumber = Trim$(Mid$(ln, sp + 1))
    End If
End Function

' (1) (12a) 1) 1. 1a. -- digits, an optional letter, in brackets or before a
' closing bracket or a full stop. A bare 1 is a word.
Public Function IsExampleNumberToken(ByVal tok As String) As Boolean
    Dim t As String, ch As String
    Dim i As Long
    Dim bracketed As Boolean

    t = tok
    If Left$(t, 1) = "(" Then
        bracketed = True
        t = Mid$(t, 2)
    End If
    If Right$(t, 1) = ")" Or Right$(t, 1) = "." Then
        t = Left$(t, Len(t) - 1)
    ElseIf Not bracketed Then
        Exit Function
    End If
    If t = "" Then Exit Function
    ch = Right$(t, 1)
    If ch < "0" Or ch > "9" Then           ' an optional letter: (12a)
        If LCase$(ch) < "a" Or LCase$(ch) > "z" Then Exit Function
        t = Left$(t, Len(t) - 1)
        If t = "" Then Exit Function
    End If
    For i = 1 To Len(t)
        ch = Mid$(t, i, 1)
        If ch < "0" Or ch > "9" Then Exit Function
    Next i
    IsExampleNumberToken = True
End Function

' How many of the last lines look like translations: counted from the end,
' every line whose word count differs from the first line's, until one
' matches. Never every line: the first is the example. A guess for the user
' to confirm, not a decision.
Public Function GuessFreeLineCount(lines() As String) As Long
    Dim n As Long, i As Long, first As Long, k As Long
    n = UBound(lines) - LBound(lines) + 1
    If n < 2 Then Exit Function
    first = WordCount(lines(LBound(lines)))
    For i = UBound(lines) To LBound(lines) + 1 Step -1
        If WordCount(lines(i)) = first Then Exit For
        k = k + 1
    Next i
    If k > n - 1 Then k = n - 1
    GuessFreeLineCount = k
End Function

' The example: the first n - nFree lines are tiers, one column per word, with
' the positional roles ModelFromTsv gives (Vernacular, Gloss, Word Gloss,
' Category); the last nFree lines are translations, verbatim. Short tier
' lines leave their trailing columns empty, which Check Glossing reports.
Public Function ModelFromLines(lines() As String, ByVal nFree As Long) As IgtExample
    Dim ex As IgtExample
    Dim n As Long, nTiers As Long, i As Long, c As Long, maxCols As Long
    Dim words() As String

    n = UBound(lines) - LBound(lines) + 1
    If n <= 0 Then Exit Function
    If nFree < 0 Then nFree = 0
    If nFree > n - 1 Then nFree = n - 1
    nTiers = n - nFree
    For i = 0 To nTiers - 1
        c = WordCount(lines(LBound(lines) + i))
        If c > maxCols Then maxCols = c
    Next i
    If maxCols = 0 Then Exit Function

    ex = NewExample(nTiers, maxCols)
    For i = 0 To nTiers - 1
        ex.Tiers(i) = PositionalRole(i)
        words = Split(lines(LBound(lines) + i), " ")
        For c = 0 To UBound(words)
            If c < maxCols Then ex.Cells(i, c) = words(c)
        Next c
    Next i
    For i = nTiers To n - 1
        AddFreeLine ex, lines(LBound(lines) + i)
    Next i
    ModelFromLines = ex
End Function

'-----------------------------------------------------------------------------
' Morpheme-align a word-aligned example in place: split every column at every
' morpheme boundary, on every interlinear tier at once, so a column holds one
' morpheme and a wrap line never starts on a continuation. What Split Column
' does for the column at the cursor, for the whole example -- how text typed
' word by word gets the document's morpheme alignment, since the FLEx path
' applies it while parsing and plain rows have nothing to say until now.
'
' A column is split only when EVERY non-empty interlinear cell in it has a
' boundary to split at. A form with two morphemes over a gloss with one is
' the linguist's to decide (Check Glossing reports it), not this routine's to
' guess -- and SplitColumn would grow the example and leave the short tier's
' new cell empty. Boundaries are IsBoundary's (- = ~ < >), never a leading one.
' Idempotent: an example already by morpheme has no column left to split.
'-----------------------------------------------------------------------------
Public Sub ProjectToMorphemes(ByRef ex As IgtExample)
    Dim c As Long
    Dim shortTiers As String
    Dim guard As Long

    c = 0
    Do While c < ex.ColCount
        guard = guard + 1
        If guard > 4000 Then Exit Do
        If ColumnSplitsEverywhere(ex, c) Then
            ' Cannot fail after the check; if it somehow did, stop rather than
            ' loop on the same column.
            If Not SplitColumn(ex, c, 1, shortTiers) Then Exit Do
            ' The right part now sits in c + 1 and is looked at next; c is done.
        End If
        c = c + 1
    Loop
End Sub

' Does every non-empty interlinear cell of the column have a morpheme boundary
' after its first character? False for an all-empty column.
Public Function ColumnSplitsEverywhere(ex As IgtExample, ByVal colIdx As Long) As Boolean
    Dim t As Long, i As Long
    Dim cell As String
    Dim found As Boolean, anyCell As Boolean

    If colIdx < 0 Or colIdx >= ex.ColCount Then Exit Function
    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then
            cell = ex.Cells(t, colIdx)
            If cell <> "" Then
                anyCell = True
                found = False
                For i = 2 To Len(cell)
                    If IsBoundary(Mid$(cell, i, 1)) Then
                        found = True
                        Exit For
                    End If
                Next i
                If Not found Then Exit Function
            End If
        End If
    Next t
    ColumnSplitsEverywhere = anyCell
End Function
