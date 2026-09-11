Attribute VB_Name = "modLeipzig"
Option Explicit

'=============================================================================
' modLeipzig  --  LingTeX-Word
'
' Checks an interlinear example against the two column invariants and the
' Leipzig Glossing Rules conventions that can be decided mechanically, and
' repairs the ones that have only one sensible repair.
'
' THESE FUNCTIONS TOUCH NO WORD OBJECTS and show no dialogs, so modTests.bas can
' test them exhaustively.  Presentation -- the warnings list, the per-cell
' highlighting, the fix buttons -- belongs to the form.
'
' ---------------------------------------------------------------------------
' WHAT IS AND IS NOT ENFORCED
'
' Enforced, because there is exactly one right answer:
'   * Column break-character agreement.  If any interlinear cell in a column
'     carries a morpheme break character at an end, every other interlinear cell
'     in that column must carry the same character at the same end.  A split-out
'     suffix column reads "-bi" over "-DIST", never "-bi" over "DIST".
'   * No spaces inside an interlinear cell.  Use "." or "_".
'
' Reported but never "corrected", because the answer is the linguist's:
'   * Two cells in a column disagreeing about WHICH break character belongs
'     there.
'   * A form and its gloss showing a different number of segmentable morpheme
'     breaks (rule 2).
'   * An unmatched infix bracket (rule 8).
'   * A column where some interlinear tiers are filled and others are not.
'
' NOT enforced, deliberately:
'   * Any notion of an approved abbreviation.  There is no list of Leipzig
'     glosses anywhere in this add-in.  Grammatical glosses are recognised
'     structurally by modFlexParse.IsGramGloss -- all-caps or digit-initial --
'     so an abbreviation nobody has ever published is still recognised and still
'     gets small caps.  The published Leipzig list is examples, not a vocabulary,
'     and linguists coin their own constantly.
'   * Rule 4's "." and ":" as morpheme breaks.  They mark one morpheme glossed
'     with several meta-language words, so they need no counterpart in the
'     object-language form and are never counted or split on.
' ---------------------------------------------------------------------------
'
' Hand port of ..\tools\reference.js (checkExample, fixColumnBreakChars,
' fixCellSpaces), covered by ..\tools\parity-test.js.
' IF YOU CHANGE AN ALGORITHM HERE, CHANGE IT THERE TOO.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-- Stable warning codes.  Branch on these, not on the message text.
Public Const WARN_BREAK_MISSING  As String = "break-char-missing"
Public Const WARN_BREAK_CONFLICT As String = "break-char-conflict"
Public Const WARN_SPACE_IN_CELL  As String = "space-in-cell"
Public Const WARN_PARITY         As String = "boundary-parity"
Public Const WARN_UNMATCHED      As String = "unmatched-angle"
Public Const WARN_EMPTY_CELL     As String = "empty-cell"

'=============================================================================
' -- CHECKING ---------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Check an example.  Returns a Collection of clsIgtWarning, never Nothing, and
' never mutates the model.
'-----------------------------------------------------------------------------
Public Function CheckExample(ex As IgtExample) As Collection
    Dim res As New Collection
    Dim c As Long, t As Long
    Dim cell As String
    Dim formIdx As Long, glossIdx As Long
    Dim fc As String, gc As String
    Dim nFilled As Long, nInterlinear As Long

    Set CheckExample = res
    If ex.TierCount = 0 Or ex.ColCount = 0 Then Exit Function

    formIdx = FormTierIndex(ex)
    glossIdx = TierIndex(ex, ROLE_GLOSS)

    For t = 0 To ex.TierCount - 1
        If IsInterlinearTier(ex.Tiers(t)) Then nInterlinear = nInterlinear + 1
    Next t

    For c = 0 To ex.ColCount - 1
        nFilled = 0

        '-- per-cell checks ------------------------------------------------
        For t = 0 To ex.TierCount - 1
            If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier
            cell = ex.Cells(t, c)
            If cell <> "" Then nFilled = nFilled + 1

            ' Invariant 2.  A space would break the column alignment the whole
            ' layout depends on, so it is never allowed in an interlinear cell.
            If InStr(cell, " ") > 0 Then
                AddWarning res, WARN_SPACE_IN_CELL, c, ex.Tiers(t), True, _
                    "Interlinear cells may not contain spaces; use ""."" or ""_""."
            End If

            ' Rule 8: an infix is written between angle brackets, so they pair.
            If CountChar(cell, "<") <> CountChar(cell, ">") Then
                AddWarning res, WARN_UNMATCHED, c, ex.Tiers(t), False, _
                    "Unmatched infix bracket (Leipzig rule 8)."
            End If
NextTier:
        Next t

        '-- invariant 1, at each end of the column independently -------------
        CheckColumnEnd ex, c, True, res
        CheckColumnEnd ex, c, False, res

        '-- rule 2: form and gloss must agree on the number of breaks --------
        If glossIdx >= 0 And formIdx >= 0 And formIdx <> glossIdx Then
            fc = ex.Cells(formIdx, c)
            gc = ex.Cells(glossIdx, c)
            If fc <> "" And gc <> "" Then
                If CountBoundaries(fc) <> CountBoundaries(gc) Then
                    AddWarning res, WARN_PARITY, c, "", False, _
                        "Form """ & fc & """ and gloss """ & gc & """ show a " & _
                        "different number of morpheme breaks (Leipzig rule 2)."
                End If
            End If
        End If

        '-- a partly filled column is legal but usually a mistake ------------
        If nFilled > 0 And nFilled < nInterlinear Then
            AddWarning res, WARN_EMPTY_CELL, c, "", False, _
                "Some interlinear tiers are empty in this column."
        End If
    Next c
End Function

'-----------------------------------------------------------------------------
' Invariant 1 for one end of one column.
' atStart = True checks the leading character, False the trailing one.
'-----------------------------------------------------------------------------
Private Sub CheckColumnEnd(ex As IgtExample, ByVal c As Long, _
        ByVal atStart As Boolean, ByRef res As Collection)

    Dim t As Long, cell As String, ch As String
    Dim distinct As String, nDistinct As Long
    Dim nAbsent As Long
    Dim endName As String

    For t = 0 To ex.TierCount - 1
        If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier
        cell = ex.Cells(t, c)
        If cell = "" Then GoTo NextTier          ' an empty cell claims nothing

        If atStart Then
            ch = LeadChar(cell)
        Else
            ch = TrailChar(cell)
        End If

        If ch = "" Then
            nAbsent = nAbsent + 1
        ElseIf InStr(distinct, ch) = 0 Then
            distinct = distinct & ch
            nDistinct = nDistinct + 1
        End If
NextTier:
    Next t

    If nDistinct = 0 Then Exit Sub               ' no break character here at all

    If atStart Then
        endName = "starts"
    Else
        endName = "ends"
    End If

    If nDistinct > 1 Then
        ' Two tiers claim different break characters.  Only the linguist knows
        ' which is right, so this is reported and never repaired.
        AddWarning res, WARN_BREAK_CONFLICT, c, "", False, _
            "Cells in this column disagree about the break character it " & _
            endName & " with (" & SpaceOut(distinct) & "); pick one by hand."
    ElseIf nAbsent > 0 Then
        AddWarning res, WARN_BREAK_MISSING, c, "", True, _
            "This column " & endName & " with """ & distinct & """ on some " & _
            "tiers but not all; every interlinear cell in a column must agree."
    End If
End Sub

Private Sub AddWarning(ByRef res As Collection, ByVal code As String, _
        ByVal col As Long, ByVal tier As String, ByVal fixable As Boolean, _
        ByVal msg As String)
    Dim w As clsIgtWarning
    Set w = New clsIgtWarning
    w.Code = code
    w.Column = col
    w.Tier = tier
    w.Fixable = fixable
    w.Message = msg
    res.Add w
End Sub

Private Function CountChar(ByVal s As String, ByVal ch As String) As Long
    Dim i As Long, n As Long
    For i = 1 To Len(s)
        If Mid$(s, i, 1) = ch Then n = n + 1
    Next i
    CountChar = n
End Function

' "-=" becomes "- vs =", for a readable conflict message.
Private Function SpaceOut(ByVal s As String) As String
    Dim i As Long, out As String
    For i = 1 To Len(s)
        If out <> "" Then out = out & " vs "
        out = out & Mid$(s, i, 1)
    Next i
    SpaceOut = out
End Function


'=============================================================================
' -- FIXING -----------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Invariant 1 repair: give every non-empty interlinear cell in the column the
' column's agreed leading and trailing break characters.
'
' Returns False without touching anything when the cells disagree about which
' character belongs there.  Guessing would silently rewrite the linguist's
' analysis, so a conflict is left for a human.
'-----------------------------------------------------------------------------
Public Function FixColumnBreakChars(ByRef ex As IgtExample, ByVal col As Long) As Boolean
    Dim changed As Boolean
    If col < 0 Or col >= ex.ColCount Then Exit Function
    If FixColumnEnd(ex, col, True) Then changed = True
    If FixColumnEnd(ex, col, False) Then changed = True
    FixColumnBreakChars = changed
End Function

Private Function FixColumnEnd(ByRef ex As IgtExample, ByVal col As Long, _
        ByVal atStart As Boolean) As Boolean

    Dim t As Long, cell As String, ch As String
    Dim distinct As String, nDistinct As Long
    Dim target As String, changed As Boolean

    For t = 0 To ex.TierCount - 1
        If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo Scan
        cell = ex.Cells(t, col)
        If cell = "" Then GoTo Scan
        If atStart Then
            ch = LeadChar(cell)
        Else
            ch = TrailChar(cell)
        End If
        If ch <> "" Then
            If InStr(distinct, ch) = 0 Then
                distinct = distinct & ch
                nDistinct = nDistinct + 1
            End If
        End If
Scan:
    Next t

    If nDistinct <> 1 Then Exit Function         ' absent, or conflicting
    target = distinct

    For t = 0 To ex.TierCount - 1
        If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier
        cell = ex.Cells(t, col)
        If cell = "" Then GoTo NextTier
        If atStart Then
            If LeadChar(cell) <> target Then
                ex.Cells(t, col) = target & cell
                changed = True
            End If
        Else
            If TrailChar(cell) <> target Then
                ex.Cells(t, col) = cell & target
                changed = True
            End If
        End If
NextTier:
    Next t

    FixColumnEnd = changed
End Function

'-----------------------------------------------------------------------------
' Invariant 2 repair: replace runs of spaces inside interlinear cells.
' Free-translation rows keep their spaces -- they are prose.
' Returns the number of cells changed.
'-----------------------------------------------------------------------------
Public Function FixCellSpaces(ByRef ex As IgtExample, _
        ByVal replacement As String) As Long

    Dim t As Long, c As Long, cell As String
    Dim parts() As String, i As Long, out As String
    Dim fixed As Long

    If replacement = "" Then replacement = "."

    For t = 0 To ex.TierCount - 1
        If Not IsInterlinearTier(ex.Tiers(t)) Then GoTo NextTier
        For c = 0 To ex.ColCount - 1
            cell = ex.Cells(t, c)
            If InStr(cell, " ") = 0 Then GoTo NextCol
            parts = Split(cell, " ")
            out = ""
            For i = 0 To UBound(parts)
                If parts(i) <> "" Then
                    If out <> "" Then out = out & replacement
                    out = out & parts(i)
                End If
            Next i
            ex.Cells(t, c) = out
            fixed = fixed + 1
NextCol:
        Next c
NextTier:
    Next t

    FixCellSpaces = fixed
End Function

'-----------------------------------------------------------------------------
' Apply every repair that has only one sensible outcome, across the whole
' example.  Returns a count of changes; warnings that need a human decision are
' deliberately left in place for CheckExample to report again.
'-----------------------------------------------------------------------------
Public Function FixWhatWeCan(ByRef ex As IgtExample, _
        ByVal spaceReplacement As String) As Long

    Dim c As Long, n As Long
    n = FixCellSpaces(ex, spaceReplacement)
    For c = 0 To ex.ColCount - 1
        If FixColumnBreakChars(ex, c) Then n = n + 1
    Next c
    FixWhatWeCan = n
End Function

' Count of findings that FixWhatWeCan would resolve.
Public Function FixableCount(warnings As Collection) As Long
    Dim w As Variant, n As Long
    If warnings Is Nothing Then Exit Function
    For Each w In warnings
        If w.Fixable Then n = n + 1
    Next w
    FixableCount = n
End Function
