Attribute VB_Name = "modReadBack"
Option Explicit

'=============================================================================
' modReadBack  --  LingTeX-Word
'
' Reads a rendered interlinear table back into an IgtExample, so it can be
' re-wrapped, re-split, or re-edited.
'
' ---------------------------------------------------------------------------
' HOW A TABLE DESCRIBES ITSELF
'
' Nothing is stored on the side.  The table is read the way a person reads it:
'
'   * It is one of ours if its TABLE STYLE is "LingTeX Interlinear".
'   * Each row's tier role is the PARAGRAPH STYLE of its first cell.
'   * A new wrap line begins wherever the FIRST tier role comes round again, so
'     the rows fall into groups of (tiers) rows each.
'   * Concatenating group 1's cells, then group 2's, and so on, recovers the flat
'     column list in its original order -- which is exactly what the wrap planner
'     needs, and why wrapping can be recomputed from scratch every time instead
'     of being remembered.
'   * A run carrying the "LingTeX Gram Gloss" CHARACTER STYLE was lowercased when
'     it was drawn, so it is uppercased on the way back.  That is what makes the
'     small-caps transform reversible rather than destructive.
'
' If the styles have been stripped -- by a paste into a document without them, or
' a pass through another editor -- the roles are inferred positionally instead, so
' the table is still recoverable, just with generic tier names.
' ---------------------------------------------------------------------------
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

' Word reports an undefined (mixed) formatting value as this.
Private Const WD_UNDEFINED As Long = 9999999

' Why the last read gave up. Empty after a clean one.
Public gReadBackError As String


'=============================================================================
' -- FINDING OUR TABLES -----------------------------------------------------
'=============================================================================

' Is this one of our auto-wrapping interlinear tables?
Public Function IsInterlinearTable(tbl As Table) As Boolean
    Dim nm As String
    If tbl Is Nothing Then Exit Function
    On Error Resume Next
    nm = tbl.Style
    Err.Clear
    On Error GoTo 0
    IsInterlinearTable = (nm = STYLE_TABLE)
End Function

'-----------------------------------------------------------------------------
' The interlinear table containing a range, or Nothing.
' Uses the innermost table, so a nested example is still found.
'-----------------------------------------------------------------------------
Public Function FindExampleAt(rng As Range) As Table
    Dim tbl As Table
    If rng Is Nothing Then Exit Function
    On Error Resume Next
    If Not rng.Information(wdWithInTable) Then Exit Function
    Set tbl = rng.Tables(1)
    Err.Clear
    On Error GoTo 0
    If IsInterlinearTable(tbl) Then Set FindExampleAt = tbl
End Function

' Every interlinear table in a document, in document order.
Public Function AllInterlinearTables(doc As Document) As Collection
    Dim res As New Collection
    Dim tbl As Table
    Set AllInterlinearTables = res
    If doc Is Nothing Then Exit Function
    For Each tbl In doc.Tables
        If IsInterlinearTable(tbl) Then res.Add tbl
    Next tbl
End Function


'=============================================================================
' -- READING ----------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Read a rendered table back into a model.
' Free translations are NOT collected here -- modRender.AbsorbFreeParagraphs does
' that, because they live outside the table.
'-----------------------------------------------------------------------------
Public Function ReadExampleFromTable(tbl As Table) As IgtExample
    Dim ex As IgtExample
    Dim nRows As Long, i As Long, g As Long, t As Long, c As Long
    Dim roles() As String
    Dim groupSize As Long, nGroups As Long
    Dim lineCols() As Long, totalCols As Long, outCol As Long
    Dim r As Long

    gReadBackError = ""
    If tbl Is Nothing Then Exit Function
    On Error GoTo Failed

    nRows = tbl.Rows.Count
    If nRows = 0 Then Exit Function

    '-- tier role per row, from the paragraph style of its first cell --------
    ReDim roles(1 To nRows)
    For i = 1 To nRows
        roles(i) = RowRole(tbl, i)
    Next i

    '-- how many rows make one wrap line ------------------------------------
    groupSize = DetectGroupSize(roles, nRows)
    If groupSize <= 0 Then groupSize = nRows
    nGroups = nRows \ groupSize
    If nGroups < 1 Then nGroups = 1

    '-- total columns, and how many each wrap line holds --------------------
    ReDim lineCols(0 To nGroups - 1)
    totalCols = 0
    For g = 0 To nGroups - 1
        lineCols(g) = RowCellCount(tbl, g * groupSize + 1)
        totalCols = totalCols + lineCols(g)
    Next g
    If totalCols = 0 Then Exit Function

    '-- assemble, group by group, which restores the original column order --
    ex = NewExample(groupSize, totalCols)
    For t = 0 To groupSize - 1
        ex.Tiers(t) = RoleOrDefault(roles(t + 1), t)
    Next t

    outCol = 0
    For g = 0 To nGroups - 1
        For c = 1 To lineCols(g)
            For t = 0 To groupSize - 1
                r = g * groupSize + t + 1
                If r <= nRows And c <= RowCellCount(tbl, r) Then
                    ex.Cells(t, outCol + c - 1) = CellTextRestored(tbl, r, c)
                End If
            Next t
        Next c
        outCol = outCol + lineCols(g)
    Next g

    ReadExampleFromTable = ex
    Exit Function

Failed:
    ' Return NOTHING, not what was assembled so far.
    '
    ' This used to fall through to "ReadExampleFromTable = ex", handing back a model
    ' with a full TierCount and ColCount and missing cells in the middle -- which
    ' RewrapTable then redrew, losing the user's text with nothing to distinguish it
    ' from a correct re-wrap. An empty example trips every caller's existing
    ' TierCount check instead.
    gReadBackError = "reading the table stopped at row " & CStr(r) & _
                     " (" & CStr(Err.Number) & ": " & Err.Description & ")"
    Err.Clear
    ReadExampleFromTable = NewExample(0, 0)
End Function

'-----------------------------------------------------------------------------
' Rows per wrap line: the distance to where the first row's role recurs.
' Falls back to the whole table, i.e. a single unwrapped line.
'-----------------------------------------------------------------------------
Private Function DetectGroupSize(roles() As String, ByVal nRows As Long) As Long
    Dim i As Long, first As String

    first = roles(1)
    If first = "" Then
        DetectGroupSize = nRows
        Exit Function
    End If

    For i = 2 To nRows
        If roles(i) = first Then
            ' Only believe it if it divides the table evenly; otherwise two tiers
            ' genuinely share a role and this is not a group boundary.
            If nRows Mod (i - 1) = 0 Then
                DetectGroupSize = i - 1
                Exit Function
            End If
        End If
    Next i

    DetectGroupSize = nRows
End Function

Private Function RowRole(tbl As Table, ByVal r As Long) As String
    Dim nm As String
    On Error Resume Next
    nm = tbl.Cell(r, 1).Range.Paragraphs(1).Style
    Err.Clear
    On Error GoTo 0
    RowRole = RoleFromParaStyle(nm)
End Function

' A generic role for a row whose style has been stripped, so the table is still
' readable even after a round trip through an editor that lost the styles.
'-----------------------------------------------------------------------------
' A role for a row whose paragraph style told us nothing -- a table whose styles
' were stripped, or one built by hand.
'
' Every index below six gets a DIFFERENT role. It used to return ROLE_CATEGORY for
' every index from three up, so a five-tier table recovered with two tiers sharing
' a role, which means two rows sharing a paragraph style and the tier distinction
' gone for good on the next render.
'
' There are only six roles, so a table with more than six tiers still has to repeat
' one. Six covers every real example -- FLEx offers about five tiers -- and the
' floor is at least explicit rather than starting at three.
'-----------------------------------------------------------------------------
Private Function RoleOrDefault(ByVal role As String, ByVal idx As Long) As String
    If role <> "" Then
        RoleOrDefault = role
        Exit Function
    End If
    Select Case idx
        Case 0: RoleOrDefault = ROLE_VERNACULAR
        Case 1: RoleOrDefault = ROLE_MORPHEMES
        Case 2: RoleOrDefault = ROLE_GLOSS
        Case 3: RoleOrDefault = ROLE_WORDGLOSS
        Case 4: RoleOrDefault = ROLE_CATEGORY
        Case 5: RoleOrDefault = ROLE_FREE
        Case Else: RoleOrDefault = ROLE_CATEGORY
    End Select
End Function

Private Function RowCellCount(tbl As Table, ByVal r As Long) As Long
    On Error Resume Next
    RowCellCount = tbl.Rows(r).Cells.Count
    Err.Clear
    On Error GoTo 0
End Function


'=============================================================================
' -- CELL TEXT --------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' A cell's text, with small-capped grammatical glosses restored to capitals.
'
' Three paths, because reading formatting one character at a time is expensive
' over the Word object model -- noticeably so on Mac -- and almost every cell is
' uniform:
'
'   SmallCaps False        nothing was transformed; take the text as-is.
'   SmallCaps True         the whole cell is a grammatical gloss; uppercase it.
'   SmallCaps wdUndefined  mixed, e.g. "attack.cmp"; walk it character by
'                          character, which is the only way to tell which run is
'                          which.
'-----------------------------------------------------------------------------
' Set by modDocTests to force the slow, definitely-correct path, so the two can be
' compared on a real table. Never set in normal use.
Public gForceSlowRestore As Boolean

Public Function CellTextRestored(tbl As Table, ByVal r As Long, ByVal c As Long) As String
    Dim rng As Range
    Dim raw As String
    Dim sc As Long
    Dim i As Long, n As Long
    Dim ch As Range
    Dim out As String
    Dim nm As String

    On Error Resume Next
    Set rng = tbl.Cell(r, c).Range
    If rng Is Nothing Then Exit Function
    rng.End = rng.End - 1                    ' drop the end-of-cell marker
    raw = rng.Text
    Err.Clear
    On Error GoTo 0

    raw = CleanCellText(raw)
    If raw = "" Then Exit Function

    sc = WD_UNDEFINED
    On Error Resume Next
    sc = rng.Font.SmallCaps
    Err.Clear
    On Error GoTo 0

    If sc = 0 Then
        ' Nothing is in small caps, so nothing was lowercased.
        CellTextRestored = raw
        Exit Function
    End If

    '-----------------------------------------------------------------------
    ' Small caps are present somewhere. Decide PER CHARACTER, by the character
    ' STYLE, and read each character out of the RANGE.
    '
    ' Two bugs are avoided by doing it this way rather than by the uniform
    ' shortcut this used to take.
    '
    ' The style, not the font: a UNIFORMLY small-capped cell used to be
    ' upper-cased wholesale on the strength of Font.SmallCaps alone -- so a
    ' vernacular word a user had small-capped themselves came back as EDEFINA.
    ' Only runs carrying OUR character style were ever lowercased, so only those
    ' may be put back.
    '
    ' And reading from the range, not from a cleaned string: the text was cleaned
    ' and trimmed first, then indexed with Mid$ alongside rng.Characters(i) -- two
    ' indexes into different strings. One leading space in the cell desynchronised
    ' them and "erg" came back as "eRG".
    '-----------------------------------------------------------------------
    ' Fast path: the WHOLE cell is one grammatical gloss, which is the common case
    ' ("ERG", "FOC", "1SG"). Reading a character style off a range whose runs
    ' disagree either raises or reports something other than our style, so a false
    ' positive is not available -- and modDocTests asserts this path and the
    ' per-character one below agree, because the per-character path is the one that
    ' is definitely right and this is only here for speed. rng.Characters(i) is a
    ' round trip into Word per character, and Mac Word feels those.
    nm = ""
    On Error Resume Next
    nm = rng.Style
    Err.Clear
    On Error GoTo 0
    If nm = STYLE_GRAM And Not gForceSlowRestore Then
        CellTextRestored = UCase$(raw)
        Exit Function
    End If

    n = rng.Characters.Count
    For i = 1 To n
        nm = ""
        Set ch = Nothing
        On Error Resume Next
        Set ch = rng.Characters(i)
        If Not ch Is Nothing Then nm = ch.Style
        Err.Clear
        On Error GoTo 0
        If ch Is Nothing Then GoTo NextChar

        If nm = STYLE_GRAM Then
            out = out & UCase$(ch.Text)
        Else
            out = out & ch.Text
        End If
NextChar:
    Next i

    ' Cleaned only at the end, so the control characters Word keeps in cell text
    ' never take part in the indexing above.
    CellTextRestored = CleanCellText(out)
End Function

' Strip the control characters Word puts in cell text, and any stray whitespace.
' An interlinear cell may not contain a space anyway, so trimming is safe.
Private Function CleanCellText(ByVal s As String) As String
    s = Replace(s, Chr$(7), "")              ' end-of-cell / end-of-row marker
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    s = Replace(s, vbTab, "")
    CleanCellText = Trim$(s)
End Function


'=============================================================================
' -- LOCATING A COLUMN ------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Map a cell's position in the rendered table to its index in the flat column
' list, which is what the model and the split/merge operations speak in.
'
' Needed because a wrapped example draws column 12 as, say, row group 2 cell 3:
' the user clicks a cell, and the model has to be told which alignment slot that
' is.  Returns -1 when the position cannot be resolved.
'-----------------------------------------------------------------------------
Public Function FlatColumnAt(tbl As Table, ByVal rowIdx As Long, _
        ByVal cellIdx As Long) As Long

    Dim nRows As Long, i As Long, g As Long
    Dim roles() As String
    Dim groupSize As Long, nGroups As Long
    Dim acc As Long

    FlatColumnAt = -1
    If tbl Is Nothing Then Exit Function
    On Error GoTo Done

    nRows = tbl.Rows.Count
    If nRows = 0 Or rowIdx < 1 Or rowIdx > nRows Then Exit Function

    ReDim roles(1 To nRows)
    For i = 1 To nRows
        roles(i) = RowRole(tbl, i)
    Next i

    groupSize = DetectGroupSize(roles, nRows)
    If groupSize <= 0 Then groupSize = nRows
    nGroups = nRows \ groupSize
    If nGroups < 1 Then nGroups = 1

    ' Wrap line this row belongs to.
    g = (rowIdx - 1) \ groupSize
    If g >= nGroups Then Exit Function

    ' Columns on every earlier wrap line come first in the flat list.
    acc = 0
    For i = 0 To g - 1
        acc = acc + RowCellCount(tbl, i * groupSize + 1)
    Next i

    If cellIdx < 1 Or cellIdx > RowCellCount(tbl, rowIdx) Then Exit Function
    FlatColumnAt = acc + cellIdx - 1

Done:
End Function

' Total alignment columns in a rendered table, summed across its wrap lines.
Public Function TableColumnCount(tbl As Table) As Long
    Dim nRows As Long, i As Long, g As Long
    Dim roles() As String
    Dim groupSize As Long, nGroups As Long

    If tbl Is Nothing Then Exit Function
    On Error GoTo Done

    nRows = tbl.Rows.Count
    If nRows = 0 Then Exit Function

    ReDim roles(1 To nRows)
    For i = 1 To nRows
        roles(i) = RowRole(tbl, i)
    Next i

    groupSize = DetectGroupSize(roles, nRows)
    If groupSize <= 0 Then groupSize = nRows
    nGroups = nRows \ groupSize
    If nGroups < 1 Then nGroups = 1

    For g = 0 To nGroups - 1
        TableColumnCount = TableColumnCount + RowCellCount(tbl, g * groupSize + 1)
    Next g

Done:
End Function
