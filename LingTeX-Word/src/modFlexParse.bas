Attribute VB_Name = "modFlexParse"
Option Explicit

'=============================================================================
' modFlexParse  --  LingTeX-Word
'
' Parses FLEx (FieldWorks Language Explorer) interlinear clipboard text into
' tier rows and alignment columns, and groups the morpheme columns into words
' while KEEPING the per-morpheme segments.
'
' Hand port of ..\tools\reference.js (groupSegments,
' handleStandalonePunctuation) and of docs\core.js (stripInvisible,
' isGramGloss, massageLine, parseFLExBlock).  reference.js is the executable
' specification: it is covered by ..\tools\parity-test.js, which VBA cannot be.
' IF YOU CHANGE AN ALGORITHM HERE, CHANGE IT THERE TOO.
'
' The FLEx clipboard format is specified in ..\..\PROMPT.md.  In short: tabs
' separate columns, one column per morpheme slot; a boundary character is
' attached as a PREFIX on its morpheme ("=ve", not a standalone "=" column);
' an empty morpheme column is either a one-to-many gloss continuation or a
' zero-morpheme slot, depending on whether the preceding morpheme's own gloss
' column was filled.
'
' ---------------------------------------------------------------------------
' THIS FILE IS DELIBERATELY PURE ASCII.
' A .bas file is imported in the system ANSI code page, not UTF-8, so a
' non-ASCII literal typed into the source arrives in Word as mojibake -- and
' differently on Windows and Mac.  Every non-ASCII character is therefore built
' with ChrW() at run time.  VBA's Const cannot hold a ChrW() call (it is a
' function, not a literal), which is why these are Property Get / Function
' rather than Const.  Do not "tidy" them into Const.
'
' Line breaks are character codes too -- Chr$(13) and Chr$(10), through
' LINE_CR, LINE_LF, LINE_CRLF and NormalizeLineBreaks -- and never vbCrLf or
' vbNewLine, which are not what their names say on every host.  See LINE
' BREAKS below.
' ---------------------------------------------------------------------------
'=============================================================================

' Morpheme boundary characters: Leipzig rule 2 (-), 6 (=), 7 (~), 8 (< >).
Public Const MORPH_DIVS As String = "-=~<>"

' FLEx tier labels, after NormalizeLabels has collapsed the spaced forms.
Public Const TIER_WORD      As String = "Word"
Public Const TIER_MORPHEMES As String = "Morphemes"
Public Const TIER_LEXENTRIES As String = "LexEntries"
Public Const TIER_LEXGLOSS  As String = "LexGloss"
Public Const TIER_WORDGLOSS As String = "WordGloss"
Public Const TIER_WORDCAT   As String = "WordCat"

'-- One morpheme inside a word -----------------------------------------------
' Bd     the boundary character introducing this segment ("" for the first)
' Form   the morpheme form without its boundary character
' Gloss  that morpheme's gloss, with any one-to-many continuation parts folded
'        in: FLEx spreads "follow" and ".CMP" over two columns but both belong
'        to the single morpheme "levo".
Public Type IgtSegment
    Bd    As String
    Form  As String
    Gloss As String
End Type

'-- One word: a run of segments, and the source columns it came from ---------
Public Type IgtWord
    Segments()  As IgtSegment
    SegCount    As Long
    StartCol    As Long
    EndCol      As Long
End Type

'-- One parsed interlinear block --------------------------------------------
' ColArrays(i) is a String() holding tier i's cells, cell 0 being the label.
Public Type FlexBlock
    LineTypes()  As String
    ColArrays()  As Variant
    TierCount    As Long
    FreeLines()  As String
    FreeCount    As Long
    LineNum      As String
End Type


'=============================================================================
' -- NON-ASCII LITERALS ------------------------------------------------------
'=============================================================================

' U+2591 LIGHT SHADE -- the morpheme-boundary sentinel used by the
' space-separated fallback path.  docs\core.js uses this character; the
' superseded word_processing_tools\FLExToWord.bas used U+2581 instead.  They
' disagreed; this one wins because core.js is the repo's source of truth.
Public Property Get MORPH_SENTINEL() As String
    MORPH_SENTINEL = ChrW(&H2591)
End Property

' Single characters that attach to the preceding form rather than standing as
' their own alignment column.  Every entry is one UTF-16 unit, so VBA's Len()
' test is correct here -- unlike the Rust port, which compares UTF-8 byte
' length and therefore never matches the ellipsis or the dashes.
Public Function AttachPunct() As String
    ' ... and the IPA length marks (U+02D0, U+02D1): a lengthened segment written
    ' as a separate token belongs to the form before it, as ":" does.
    AttachPunct = "-,:;.!?/|&" _
        & ChrW(&H2026) _
        & ChrW(&H2012) & ChrW(&H2013) & ChrW(&H2014) & ChrW(&H2015) _
        & ChrW(&H2D0) & ChrW(&H2D1)
End Function

Public Property Get LeftSingleQuote() As String
    LeftSingleQuote = ChrW(&H2018)
End Property

Public Property Get RightSingleQuote() As String
    RightSingleQuote = ChrW(&H2019)
End Property


'=============================================================================
' -- LINE BREAKS -------------------------------------------------------------
'=============================================================================

' Line breaks are found, split and normalised with these, never with vbCrLf or
' vbNewLine.  In the VBA of Word and of PowerPoint for Mac 16.112, vbCrLf is LF
' then CR -- the reverse of a real CR LF -- and vbNewLine is LF alone (measured
' 2026-09-15; RunAllTests records them on every host it runs on).  So
' Replace(s, vbCrLf, vbLf) matched no CR LF, and the vbCr pass after it turned
' each one into two line breaks: a blank line after every tier row, which
' ParseFlexBlocks reads as the end of an example.  Word hands these modules
' text from a document, where a paragraph ends in CR, so it never met the bug;
' LingTeX-PowerPoint, which shares them, would have.  Property Get, not Const,
' for the reason in the header: a Const cannot hold Chr$().
Public Property Get LINE_CR() As String
    LINE_CR = Chr$(13)
End Property

Public Property Get LINE_LF() As String
    LINE_LF = Chr$(10)
End Property

Public Property Get LINE_CRLF() As String
    LINE_CRLF = Chr$(13) & Chr$(10)
End Property

' Every line break as LF: CR LF (Windows text), CR (a Word paragraph mark) and
' LF.  CR LF goes first, or each one would become two.
Public Function NormalizeLineBreaks(ByVal s As String) As String
    NormalizeLineBreaks = Replace(Replace(s, LINE_CRLF, LINE_LF), LINE_CR, LINE_LF)
End Function


'=============================================================================
' -- LOW-LEVEL HELPERS ------------------------------------------------------
'=============================================================================

' True when ch is a morpheme boundary character.
' InStr returns 1 for an empty needle, so the empty case must be rejected
' first or every empty string would read as a boundary.
Public Function IsBoundary(ch As String) As Boolean
    If Len(ch) <> 1 Then Exit Function
    IsBoundary = (InStr(MORPH_DIVS, ch) > 0)
End Function

' The boundary character a cell starts with, or "".
Public Function LeadChar(s As String) As String
    If Len(s) = 0 Then Exit Function
    If IsBoundary(Left$(s, 1)) Then LeadChar = Left$(s, 1)
End Function

' The boundary character a cell ends with, or "".
Public Function TrailChar(s As String) As String
    If Len(s) = 0 Then Exit Function
    If IsBoundary(Right$(s, 1)) Then TrailChar = Right$(s, 1)
End Function

' Number of segmentable boundaries in a cell.  Leipzig rule 4's "." and ":"
' are NOT counted: they mark one morpheme glossed with several meta-language
' words, so they need no counterpart in the object-language form.
Public Function CountBoundaries(s As String) As Long
    Dim i As Long, n As Long
    For i = 1 To Len(s)
        If IsBoundary(Mid$(s, i, 1)) Then n = n + 1
    Next i
    CountBoundaries = n
End Function

' True when the whole cell is one attaching punctuation character.
Public Function IsAttachPunct(s As String) As Boolean
    If Len(s) <> 1 Then Exit Function
    IsAttachPunct = (InStr(AttachPunct(), s) > 0)
End Function

' Remove zero-width and bidirectional marks that FLEx and Word both emit.
Public Function StripInvisible(ByVal s As String) As String
    s = Replace(s, ChrW(&H200B), "")     ' zero width space
    s = Replace(s, ChrW(&H200E), "")     ' left-to-right mark
    s = Replace(s, ChrW(&H200F), "")     ' right-to-left mark
    s = Replace(s, ChrW(&H202A), "")     ' left-to-right embedding
    s = Replace(s, ChrW(&H202B), "")     ' right-to-left embedding
    s = Replace(s, ChrW(&H202C), "")     ' pop directional formatting
    s = Replace(s, ChrW(&H202D), "")     ' left-to-right override
    s = Replace(s, ChrW(&H202E), "")     ' right-to-left override
    StripInvisible = s
End Function

Private Function IsAlNum(ch As String) As Boolean
    IsAlNum = (ch >= "A" And ch <= "Z") _
           Or (ch >= "a" And ch <= "z") _
           Or (ch >= "0" And ch <= "9")
End Function

'-----------------------------------------------------------------------------
' Is this token a grammatical gloss abbreviation, and so small-capped?
'
' Equivalent to the docs\core.js pattern
'     /^[^\w]*([0-9A-Z]+|[0-9]\w+)[^\w]*$/
' with the exclusion  /^[A-Z + U+014A/U+014B eng]\.$/  -- written as a
' character scan
' because VBScript.RegExp does not exist on Mac Word.
'
' So: all-caps, or digit-initial.  A lone capital followed by a period ("N.",
' "A.", and the same for the African eng) is a list marker, not a gloss.
'
' Recognition is STRUCTURAL on purpose.  There is no list of approved Leipzig
' abbreviations anywhere in this add-in: linguists coin their own constantly,
' and the published list is examples, not a vocabulary.  An abbreviation
' nobody has ever published is still recognised.
'-----------------------------------------------------------------------------
Public Function IsGramGloss(ByVal seg As String) As Boolean
    Dim core As String, i As Long, ch As String
    Dim t As String

    If Len(seg) = 0 Then Exit Function
    t = Trim$(seg)

    ' Exclusion: a single capital letter (or eng) plus a period.
    If Len(t) = 2 And Mid$(t, 2, 1) = "." Then
        ch = Left$(t, 1)
        If (ch >= "A" And ch <= "Z") _
           Or ch = ChrW(&H14A) Or ch = ChrW(&H14B) Then Exit Function
    End If

    ' Strip leading and trailing non-alphanumerics to find the core token.
    core = t
    Do While Len(core) > 0
        If IsAlNum(Left$(core, 1)) Then Exit Do
        core = Mid$(core, 2)
    Loop
    Do While Len(core) > 0
        If IsAlNum(Right$(core, 1)) Then Exit Do
        core = Left$(core, Len(core) - 1)
    Loop
    If Len(core) = 0 Then Exit Function          ' punctuation only

    ' A lone capital letter is not a gloss.
    If Len(core) = 1 And core >= "A" And core <= "Z" Then Exit Function

    ' Digit-initial: 3SG, 3sg, 1pl, 1s.  The lowercase spellings count -- the
    ' writer means the same category and wants the same small caps.
    ' Matches the [0-9]\w+ branch, so the rest must be word characters.
    ch = Left$(core, 1)
    If ch >= "0" And ch <= "9" Then
        For i = 2 To Len(core)
            ch = Mid$(core, i, 1)
            If Not (IsAlNum(ch) Or ch = "_") Then Exit Function
        Next i
        IsGramGloss = True
        Exit Function
    End If

    ' All caps: EVERY character of the core must be an uppercase letter or a
    ' digit.  Matches the [0-9A-Z]+ branch.
    '
    ' Testing merely for "contains no lowercase" is not the same thing, and gets
    ' "P.N." wrong: stripping the outer dots leaves "P.N", which has no lowercase
    ' but does have an interior dot, so the pattern does not match and the token
    ' is a proper-noun abbreviation rather than a grammatical gloss.  The pattern
    ' allows non-word characters only at the ENDS, which the stripping above has
    ' already removed.
    For i = 1 To Len(core)
        ch = Mid$(core, i, 1)
        If Not ((ch >= "A" And ch <= "Z") Or (ch >= "0" And ch <= "9")) Then Exit Function
    Next i
    IsGramGloss = True
End Function


'=============================================================================
' -- LINE NORMALISATION -----------------------------------------------------
'=============================================================================

' Collapse FLEx's spaced tier labels into single tokens.
Public Function NormalizeLabels(ByVal s As String) As String
    s = Replace(s, "Lex. Entries", TIER_LEXENTRIES)
    s = Replace(s, "Lex. Gloss", TIER_LEXGLOSS)
    s = Replace(s, "Word Gloss", TIER_WORDGLOSS)
    s = Replace(s, "Word Cat.", TIER_WORDCAT)
    NormalizeLabels = s
End Function

'-----------------------------------------------------------------------------
' Space-separated fallback path, for text that has lost its tabs (pasted
' through a plain-text editor, or typed by hand).  Sentinels are inserted
' around morpheme dividers so the body can later be split into morphemes, and
' punctuation is tucked against the preceding word.
'
' Port of docs\core.js massageLine.  Not used for real tab-separated FLEx
' output, which keeps its column structure and needs none of this.
'-----------------------------------------------------------------------------
Public Function MassageLine(ByVal s As String) As String
    Dim sp As Long, lbl As String, body As String, sen As String

    s = NormalizeLabels(StripInvisible(s))

    sp = InStr(s, " ")
    If sp = 0 Then
        MassageLine = s
        Exit Function
    End If
    lbl = Left$(s, sp)
    body = Mid$(s, sp + 1)

    sen = MORPH_SENTINEL
    body = Replace(body, "- ", sen & "-" & sen)
    body = Replace(body, " -", sen & "-" & sen)
    body = Replace(body, " <", sen & "<" & sen)
    body = Replace(body, "> ", sen & ">" & sen)
    body = Replace(body, "= ", sen & "=" & sen)
    body = Replace(body, " =", sen & "=" & sen)
    body = Replace(body, " ~", sen & "~" & sen)
    body = Replace(body, "~ ", sen & "~" & sen)

    body = Replace(body, " .", ".")
    body = Replace(body, " " & ChrW(&H2026), ChrW(&H2026))
    body = Replace(body, " ,", ",")
    body = Replace(body, " ?", "?")
    body = Replace(body, " !", "!")
    body = Replace(body, " :", ":")
    body = Replace(body, " " & ChrW(&H2D0), ChrW(&H2D0))
    body = Replace(body, " ;", ";")
    body = Replace(body, "( ", "(")
    body = Replace(body, " )", ")")
    body = Replace(body, "[ ", "[")
    body = Replace(body, " ]", "]")

    MassageLine = lbl & body
End Function


'=============================================================================
' -- BLOCK PARSING ----------------------------------------------------------
'=============================================================================

' True when a line opens a new numbered example.
Private Function IsBlockStart(ByVal s As String) As Boolean
    Dim i As Long, ch As String, seenDigit As Boolean
    s = Trim$(StripInvisible(s))
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch >= "0" And ch <= "9" Then
            seenDigit = True
        ElseIf ch = "." And seenDigit Then
            ' "1.2" style numbering: keep scanning.
        ElseIf ch = " " Or ch = vbTab Then
            Exit For
        Else
            Exit Function
        End If
    Next i
    IsBlockStart = seenDigit
End Function

'-----------------------------------------------------------------------------
' Split raw clipboard text into blocks and parse each one.
' Blocks are separated by a blank line; failing that, by a numbered-example
' line, because FLEx does not always leave a blank line between examples.
' Port of docs\core.js parseFLExBlocks.
'-----------------------------------------------------------------------------
Public Function ParseFlexBlocks(ByVal raw As String) As FlexBlock()
    Dim lines() As String, i As Long
    Dim chunks() As String, nChunks As Long
    Dim blocks() As FlexBlock, nBlocks As Long
    Dim b As FlexBlock
    Dim blank As Boolean, started As Boolean

    raw = NormalizeLineBreaks(raw)
    lines = Split(raw, LINE_LF)

    ReDim chunks(0 To UBound(lines) + 1)
    nChunks = 0
    chunks(0) = ""
    started = False

    For i = 0 To UBound(lines)
        blank = (Trim$(lines(i)) = "")
        If blank Then
            If started Then
                nChunks = nChunks + 1
                chunks(nChunks) = ""
                started = False
            End If
        Else
            If started And IsBlockStart(lines(i)) Then
                nChunks = nChunks + 1
                chunks(nChunks) = ""
            End If
            If Len(chunks(nChunks)) > 0 Then chunks(nChunks) = chunks(nChunks) & LINE_LF
            chunks(nChunks) = chunks(nChunks) & lines(i)
            started = True
        End If
    Next i

    ReDim blocks(0 To nChunks)
    nBlocks = 0
    For i = 0 To nChunks
        If Trim$(chunks(i)) <> "" Then
            b = ParseFlexBlock(chunks(i))
            If b.TierCount > 0 Then
                blocks(nBlocks) = b
                nBlocks = nBlocks + 1
            End If
        End If
    Next i

    If nBlocks = 0 Then
        ReDim blocks(-1 To -1)
    Else
        ReDim Preserve blocks(0 To nBlocks - 1)
    End If
    ParseFlexBlocks = blocks
End Function

'-----------------------------------------------------------------------------
' Parse one block into tier labels and raw column arrays.
' Port of docs\core.js parseFLExBlock.
'-----------------------------------------------------------------------------
Public Function ParseFlexBlock(ByVal text As String) As FlexBlock
    Dim res As FlexBlock
    Dim lines() As String, i As Long, j As Long
    Dim ln As String, clean As String
    Dim cols() As String
    Dim seenFree As Boolean
    Dim numPart As String

    text = NormalizeLineBreaks(text)
    lines = Split(text, LINE_LF)

    ReDim res.LineTypes(0 To UBound(lines))
    ReDim res.ColArrays(0 To UBound(lines))
    ReDim res.FreeLines(0 To UBound(lines))
    res.TierCount = 0
    res.FreeCount = 0
    res.LineNum = ""

    For i = 0 To UBound(lines)
        ln = lines(i)
        ' Strip trailing blanks but keep interior tabs: an empty trailing
        ' column is meaningful, an empty trailing run of spaces is not.
        Do While Len(ln) > 0
            If Right$(ln, 1) = " " Or Right$(ln, 1) = vbTab Then
                ln = Left$(ln, Len(ln) - 1)
            Else
                Exit Do
            End If
        Loop
        If Trim$(ln) = "" Then GoTo NextLine

        ' An example number on the first line becomes the block's reference.
        If res.LineNum = "" Then
            numPart = LeadingNumber(ln)
            If numPart <> "" Then
                res.LineNum = numPart
                ln = Trim$(Mid$(LTrim$(ln), Len(numPart) + 1))
                If ln = "" Then GoTo NextLine
            End If
        End If

        clean = Trim$(StripInvisible(ln))

        ' Free translation: "Free", optionally followed by a language tag.
        If LCase$(Left$(clean, 4)) = "free" Then
            seenFree = True
            AddFreeLine res, StripFreeLabel(clean)
            GoTo NextLine
        End If
        ' After a Free line, a bare language tag introduces another one.
        If seenFree And IsShortTag(clean) Then
            AddFreeLine res, Trim$(Mid$(clean, InStr(clean, " ") + 1))
            GoTo NextLine
        End If

        If InStr(ln, vbTab) > 0 Then
            ' Real FLEx output: tabs already carry the column structure.
            cols = Split(NormalizeLabels(StripInvisible(ln)), vbTab)
            For j = 0 To UBound(cols)
                cols(j) = Trim$(cols(j))
            Next j
            ' The Lex. Gloss row often has its label in column 1, not 0, so a
            ' leading empty column is dropped.  The bounds test has to come
            ' FIRST and in its own If: VBA does not short-circuit And, and
            ' ShiftLeft on a one-element array would ReDim to 0 To -1.
            If UBound(cols) >= 1 Then
                If cols(0) = "" Then cols = ShiftLeft(cols)
            End If
        Else
            cols = Split(Trim$(MassageLine(ln)), " ")
            cols = DropEmpty(cols)
        End If

        If UBound(cols) < 0 Then GoTo NextLine
        res.LineTypes(res.TierCount) = cols(0)
        res.ColArrays(res.TierCount) = cols
        res.TierCount = res.TierCount + 1

NextLine:
    Next i

    If res.TierCount > 0 Then
        ReDim Preserve res.LineTypes(0 To res.TierCount - 1)
        ReDim Preserve res.ColArrays(0 To res.TierCount - 1)
    End If
    If res.FreeCount > 0 Then
        ReDim Preserve res.FreeLines(0 To res.FreeCount - 1)
    End If

    ParseFlexBlock = res
End Function

Private Sub AddFreeLine(ByRef res As FlexBlock, ByVal s As String)
    If Trim$(s) = "" Then Exit Sub
    res.FreeLines(res.FreeCount) = Trim$(s)
    res.FreeCount = res.FreeCount + 1
End Sub

' "Free" or "Free Eng" prefix removed.
Private Function StripFreeLabel(ByVal s As String) As String
    Dim rest As String, tag As String, sp As Long
    rest = Trim$(Mid$(s, 5))                      ' past "Free"
    sp = InStr(rest, " ")
    If sp > 0 Then
        tag = Left$(rest, sp - 1)
    Else
        tag = rest
    End If
    If IsAlphaTag(tag) Then
        If sp > 0 Then
            rest = Trim$(Mid$(rest, sp + 1))
        Else
            rest = ""
        End If
    End If
    StripFreeLabel = rest
End Function

' A 2-to-8 letter writing-system tag such as "Eng" or "Tok".
Private Function IsAlphaTag(ByVal s As String) As Boolean
    Dim i As Long, ch As String
    If Len(s) < 2 Or Len(s) > 8 Then Exit Function
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If Not ((ch >= "A" And ch <= "Z") Or (ch >= "a" And ch <= "z")) Then Exit Function
    Next i
    IsAlphaTag = True
End Function

Private Function IsShortTag(ByVal s As String) As Boolean
    Dim sp As Long
    sp = InStr(s, " ")
    If sp < 2 Then Exit Function
    IsShortTag = IsAlphaTag(Left$(s, sp - 1))
End Function

' The digits (optionally "1.2") a line starts with, or "".
Private Function LeadingNumber(ByVal s As String) As String
    Dim i As Long, ch As String, res As String
    s = LTrim$(s)
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch >= "0" And ch <= "9" Then
            res = res & ch
        ElseIf ch = "." And res <> "" And i < Len(s) Then
            If Mid$(s, i + 1, 1) >= "0" And Mid$(s, i + 1, 1) <= "9" Then
                res = res & ch
            Else
                Exit For
            End If
        Else
            Exit For
        End If
    Next i
    ' Only a number followed by whitespace or end of line counts.
    If res <> "" And i <= Len(s) Then
        ch = Mid$(s, i, 1)
        If ch <> " " And ch <> vbTab Then res = ""
    End If
    LeadingNumber = res
End Function

Private Function ShiftLeft(arr() As String) As String()
    Dim out() As String, i As Long
    ReDim out(0 To UBound(arr) - 1)
    For i = 1 To UBound(arr)
        out(i - 1) = arr(i)
    Next i
    ShiftLeft = out
End Function

Private Function DropEmpty(arr() As String) As String()
    Dim out() As String, i As Long, n As Long
    ReDim out(0 To UBound(arr))
    For i = 0 To UBound(arr)
        If arr(i) <> "" Then
            out(n) = arr(i)
            n = n + 1
        End If
    Next i
    If n = 0 Then
        ReDim out(-1 To -1)
    Else
        ReDim Preserve out(0 To n - 1)
    End If
    DropEmpty = out
End Function


'=============================================================================
' -- SEGMENT GROUPING -------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Group morpheme columns into words, keeping each word's morpheme segments.
'
' Port of ..\tools\reference.js groupSegments, which extends
' docs\core.js groupWordsFromColumns.  core.js joins the form into one string
' and so discards the form segments; keeping them is what lets an alignment
' column hold a word, a morpheme, or part of a word, with word-aligned and
' morpheme-aligned output being two projections of one segment list rather
' than two different algorithms.
'
' morphemes   column array for the Morphemes / Lex. Entries tier
' lexGlosses  column array for the Lex. Gloss tier
' startIdx    index of the first data column (past the label)
' outCount    number of words returned
'-----------------------------------------------------------------------------
Public Function GroupSegmentsFromColumns(morphemes() As String, _
        lexGlosses() As String, ByVal startIdx As Long, _
        ByRef outCount As Long) As IgtWord()

    Dim words() As IgtWord, nWords As Long
    Dim cur As IgtWord, haveCur As Boolean
    Dim col As Long, n As Long
    Dim m As String, g As String, bd As String, form As String
    Dim contG As String

    n = UBound(morphemes) + 1
    ReDim words(0 To IIf(n > 0, n, 1))
    nWords = 0
    haveCur = False

    For col = startIdx To n - 1
        m = Trim$(CellAt(morphemes, col))
        g = Trim$(CellAt(lexGlosses, col))

        If m <> "" Then
            bd = LeadChar(m)
            If bd <> "" Then
                form = Mid$(m, 2)
            Else
                form = m
            End If

            If bd <> "" Then
                ' Suffix, enclitic or reduplicant: another segment of this word.
                If haveCur Then
                    AddSegment cur, bd, form, g
                    cur.EndCol = col
                End If
            Else
                ' No boundary character, so this starts a new word.
                If haveCur Then
                    words(nWords) = cur
                    nWords = nWords + 1
                End If
                cur = NewWord(form, g, col)
                haveCur = True

                If g = "" Then
                    ' The morpheme's own gloss column is empty, so the
                    ' following empty-morpheme columns are one-to-many gloss
                    ' continuations belonging to THIS morpheme, not new ones.
                    Do While col + 1 <= n - 1
                        If Trim$(CellAt(morphemes, col + 1)) <> "" Then Exit Do
                        col = col + 1
                        contG = Trim$(CellAt(lexGlosses, col))
                        If contG <> "" Then
                            cur.Segments(0).Gloss = cur.Segments(0).Gloss & contG
                        End If
                        cur.EndCol = col
                    Loop
                End If
            End If
        Else
            ' Empty morpheme column whose predecessor's gloss was already
            ' satisfied: a zero-morpheme slot with an alignment column to itself.
            If haveCur Then
                words(nWords) = cur
                nWords = nWords + 1
                haveCur = False
            End If
            If g <> "" Then
                words(nWords) = NewWord("", g, col)
                nWords = nWords + 1
            End If
        End If
    Next col

    If haveCur Then
        words(nWords) = cur
        nWords = nWords + 1
    End If

    outCount = nWords
    If nWords = 0 Then
        ReDim words(-1 To -1)
    Else
        ReDim Preserve words(0 To nWords - 1)
    End If
    GroupSegmentsFromColumns = words
End Function

Private Function CellAt(arr() As String, ByVal i As Long) As String
    If i < LBound(arr) Or i > UBound(arr) Then Exit Function
    CellAt = arr(i)
End Function

Private Function NewWord(ByVal form As String, ByVal gloss As String, _
        ByVal col As Long) As IgtWord
    Dim w As IgtWord
    ReDim w.Segments(0 To 7)
    w.Segments(0).Bd = ""
    w.Segments(0).Form = form
    w.Segments(0).Gloss = gloss
    w.SegCount = 1
    w.StartCol = col
    w.EndCol = col
    NewWord = w
End Function

Private Sub AddSegment(ByRef w As IgtWord, ByVal bd As String, _
        ByVal form As String, ByVal gloss As String)
    If w.SegCount > UBound(w.Segments) Then
        ReDim Preserve w.Segments(0 To UBound(w.Segments) * 2 + 1)
    End If
    w.Segments(w.SegCount).Bd = bd
    w.Segments(w.SegCount).Form = form
    w.Segments(w.SegCount).Gloss = gloss
    w.SegCount = w.SegCount + 1
End Sub

'-----------------------------------------------------------------------------
' Fold a word that is bare punctuation into the preceding word's last segment,
' so "ze" followed by ":" becomes the single form "ze:" with its gloss intact.
' Port of reference.js handleStandalonePunctuation.
'-----------------------------------------------------------------------------
Public Sub HandleStandalonePunctuation(ByRef words() As IgtWord, ByRef count As Long)
    Dim i As Long, j As Long, k As Long

    i = 1
    Do While i < count
        If words(i).SegCount = 1 _
           And words(i).Segments(0).Gloss = "" _
           And words(i).Segments(0).Bd = "" _
           And IsAttachPunct(words(i).Segments(0).Form) Then

            k = words(i - 1).SegCount - 1
            words(i - 1).Segments(k).Form = _
                words(i - 1).Segments(k).Form & words(i).Segments(0).Form
            words(i - 1).EndCol = words(i).EndCol

            For j = i To count - 2
                words(j) = words(j + 1)
            Next j
            count = count - 1
        Else
            i = i + 1
        End If
    Loop
End Sub


'=============================================================================
' -- PROJECTIONS ------------------------------------------------------------
'=============================================================================

' Word-aligned form: every segment of the word joined into one cell.
Public Function JoinForm(w As IgtWord) As String
    Dim i As Long, s As String
    For i = 0 To w.SegCount - 1
        s = s & w.Segments(i).Bd & w.Segments(i).Form
    Next i
    JoinForm = s
End Function

' Word-aligned gloss.  The first segment contributes its gloss bare; later
' segments contribute their boundary character plus gloss, so an affix with no
' gloss of its own still leaves its boundary visible.  Matches the
' glossParts.join("") of docs\core.js.
Public Function JoinGloss(w As IgtWord) As String
    Dim i As Long, s As String
    For i = 0 To w.SegCount - 1
        If i = 0 Then
            s = s & w.Segments(i).Gloss
        Else
            s = s & w.Segments(i).Bd & w.Segments(i).Gloss
        End If
    Next i
    JoinGloss = s
End Function
