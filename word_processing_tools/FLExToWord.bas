Attribute VB_Name = "FLExToWord"
Option Explicit

'=============================================================================
' FLExToWord.bas  —  Word VBA port of the LibreOffice FLExTextToFrames macro
' Original LibreOffice macro by Moss Doerksen
'
' Converts FLEx interlinear clipboard text into OMML nested-matrix frames,
' one per WORD.  The logic is identical to the LO macro; the only difference
' is the output: OMML matrices instead of LibreOffice inline text frames.
'
' Word-level architecture (same as LO macro):
'   • Morphemes are COLLAPSED into words  (kata░=░te  →  kata=te)
'   • Gloss dividers are assembled inline  (carry.CMP + = + SEQ  →  carry.CMP=SEQ)
'   • Each word → one <m:oMath>  containing a 1-column inner matrix
'   • Rows of the inner matrix = tiers (vernacular, gloss, wordcat, …)
'
' Per-cell formatting (identical to LO macro output):
'   Row 0  object language  italic, surrounding font
'   Row 1+ gloss / other    small caps on grammatical tokens, surrounding font
'
' Install:  Alt+F11 → Insert → Module → paste this file
' Run:      Select FLEx-copied interlinear text → run FLExTextToWord
'=============================================================================

' ── Paragraph style for free translation (must exist in your Word template) ─
Private Const STYLE_FREE_TRANS  As String = "Ex. Trans."

' ── Font fallback chain ──────────────────────────────────────────────────────
' 1. Font at the cursor position (reads your template automatically)
' 2. Document default paragraph font
' 3. Hard-coded last-resort fallback
' The LO template uses Times New Roman.  Change to match your Word template.
Private Const FALLBACK_FONT     As String = "Charis SIL"

' ── Internal parsing constants (identical to LO macro) ──────────────────────
' ░ U+2591: sentinel inserted around morpheme dividers by MassageFLExLine
Private Const MORPH_SEP         As String = Chr(9601)
' Characters that serve as morpheme dividers in the source data
Private Const MORPH_DIVIDERS    As String = "-<>=~"
' Valid FLEx line-type labels (same set as LO macro)
Private Const VALID_TYPES       As String = "/Word/WordGloss/Morphemes/LexEntries/LexGloss/WordCat/"

' ── OMML matrix properties (matches FLEx Word export document format) ────────
Private Const M_PROPS_1COL      As String = _
    "<m:mPr><m:baseJc m:val=""top""/><m:rSpRule m:val=""4""/><m:rSp m:val=""3""/>" & _
    "<m:mcs><m:mc><m:mcPr><m:count m:val=""1""/><m:mcJc m:val=""left""/>" & _
    "</m:mcPr></m:mc></m:mcs></m:mPr>"

' ── Grammatical gloss detection (mirrors LO grammaticalGlossRegex) ───────────
' Tokens are grammatical if they are ALL-CAPS (with optional digits/punctuation)
' or digit-initial (3sg, 1pl).  Single capital letter is excluded.


'=============================================================================
' ── PUBLIC ENTRY POINTS ──────────────────────────────────────────────────────
'=============================================================================

Public Sub FLExTextToWord()
    ' Converts FLEx-copied interlinear text into OMML matrix frames.
    ' Select the FLEx text block, then run this macro.
    On Error GoTo ErrHandler

    If Selection.Type = wdSelectionIP Then
        MsgBox "Please select the FLEx interlinear text first.", vbExclamation
        Exit Sub
    End If

    Application.ScreenUpdating = False

    Dim targetFont  As String
    Dim rawText     As String
    Dim allLines()  As String
    Dim igtLines()  As String
    Dim freeLines() As String
    Dim lineTypes() As String
    Dim wordArrays()              ' Variant: each element is String() of tokens
    Dim morphWordArr() As String  ' Morphemes / LexEntries line tokens
    Dim glossWordArr() As String  ' LexGloss line tokens
    Dim hasLexGloss    As Boolean

    targetFont = GetContextFont()
    rawText    = NormalizeText(Selection.Text)

    allLines = SplitToLines(rawText)
    If UBound(allLines) < 0 Then
        MsgBox "Could not parse the selected text.", vbExclamation
        GoTo Cleanup
    End If

    Call SeparateFreeLines(allLines, igtLines, freeLines)
    If UBound(igtLines) < 0 Then
        MsgBox "No IGT lines found.", vbExclamation
        GoTo Cleanup
    End If

    If Not ClassifyLines(igtLines, lineTypes, wordArrays, morphWordArr, glossWordArr, hasLexGloss) Then
        GoTo Cleanup
    End If

    ' Capitalise first word of first line — same as LO SentenceCase()
    Dim fl() As String
    fl = wordArrays(0)
    If UBound(fl) >= 1 Then
        fl(1) = UCase(Left(fl(1), 1)) & Mid(fl(1), 2)
        wordArrays(0) = fl
    End If

    ' Build the OMML paragraph XML and replace the selection
    Dim paraXML As String
    paraXML = BuildParagraphXML(wordArrays, lineTypes, morphWordArr, glossWordArr, _
                                hasLexGloss, targetFont)
    Selection.Range.InsertXML paraXML

    ' Insert free translation line(s) after the IGT paragraph
    If UBound(freeLines) >= 0 Then
        Call InsertFreeLines(freeLines, targetFont)
    End If

Cleanup:
    Application.ScreenUpdating = True
    Exit Sub

ErrHandler:
    Application.ScreenUpdating = True
    MsgBox "Error " & Err.Number & ": " & Err.Description, vbCritical, "FLExTextToWord"
End Sub

' ─────────────────────────────────────────────────────────────────────────────

Public Sub ReplaceGlossWord()
    ' Replace a gloss throughout all interlinear examples.
    ' Word's Find/Replace reaches inside OMML <m:t> nodes.
    ' Same prompt as LO ReplaceGloss macro.
    Dim inp As String
    inp = InputBox( _
        "SAVE YOUR DOCUMENT BEFORE DOING THIS." & Chr(13) & _
        "This will only replace glosses inside interlinear examples." & Chr(13) & Chr(13) & _
        "Enter the morpheme form, the old gloss, and the new gloss, separated by spaces." & Chr(13) & Chr(13) & _
        "Example: ing CONT PROG | Example: my 1s.POSS 1s.GEN", "Replace a gloss")
    If inp = "" Then Exit Sub

    Dim parts() As String
    parts = Split(Trim(inp), " ")
    If UBound(parts) <> 2 Then
        MsgBox "You're doing it wrong.", vbExclamation
        Exit Sub
    End If

    Dim morpheme As String, oldGloss As String, newGloss As String
    morpheme = parts(0)
    oldGloss = parts(1)
    newGloss = parts(2)

    If MsgBox("Change the gloss for <" & morpheme & "> from '" & oldGloss & "' to '" & newGloss & "'?", _
              vbYesNo + vbQuestion, "Replace Gloss") <> vbYes Then Exit Sub

    ' Word's Find/Replace operates on the text content of <m:t> nodes.
    ' MatchWholeWord prevents partial replacements.
    With ActiveDocument.Content.Find
        .ClearFormatting
        .Replacement.ClearFormatting
        .Text             = LCase(oldGloss)   ' glosses stored lowercase (small-caps display)
        .Replacement.Text = LCase(newGloss)
        .MatchCase        = True
        .MatchWholeWord   = True
        .Forward          = True
        .Wrap             = wdFindContinue
        .Execute Replace:=wdReplaceAll
    End With

    MsgBox "Done. Note: replacement is document-wide — review and undo (Ctrl+Z) if needed.", _
           vbInformation
End Sub


'=============================================================================
' ── TEXT NORMALISATION AND PARSING ───────────────────────────────────────────
'=============================================================================

Private Function NormalizeText(s As String) As String
    ' Normalise line endings, strip tab/LTR/RTL marks, collapse spaces,
    ' remove leading paragraph number.  Mirrors LO SelectionToLines().
    s = Replace(s, Chr(13) & Chr(10), Chr(13))
    s = Replace(s, Chr(10), Chr(13))
    s = Replace(s, Chr(9), " ")
    s = Replace(s, Chr(8206), "")   ' U+200E LEFT-TO-RIGHT MARK
    s = Replace(s, Chr(8207), "")   ' U+200F RIGHT-TO-LEFT MARK

    Dim i As Integer
    For i = 1 To 6
        s = Replace(s, "  ", " ")
    Next i
    s = Trim(s)

    ' Strip leading paragraph number  e.g. "1. " or "1.2 "
    Dim j As Integer
    For j = 1 To Len(s)
        If Mid(s, j, 1) < "0" Or Mid(s, j, 1) > "9" Then Exit For
    Next j
    If j > 1 Then
        Dim rest As String
        rest = LTrim(Mid(s, j))
        If Left(rest, 1) = "." Then rest = LTrim(Mid(rest, 2))
        If Left(rest, 1) >= "A" Then s = rest   ' only strip if a label follows
    End If

    NormalizeText = Trim(s)
End Function

Private Function SplitToLines(s As String) As String()
    Dim raw()    As String
    Dim result() As String
    raw = Split(s, Chr(13))
    ReDim result(UBound(raw))
    Dim n As Integer, i As Integer
    n = 0
    For i = 0 To UBound(raw)
        Dim line As String
        line = Trim(raw(i))
        If line <> "" Then
            result(n) = line
            n = n + 1
        End If
    Next i
    If n = 0 Then ReDim result(-1 To -1) Else ReDim Preserve result(0 To n - 1)
    SplitToLines = result
End Function

Private Sub SeparateFreeLines(allLines() As String, _
        ByRef igtLines() As String, ByRef freeLines() As String)
    ' Split lines into IGT lines and Free translation lines.
    ' Free lines are wrapped in typographic single quotes.
    ' Mirrors LO FLExTextToFrames Free-line handling.
    ReDim igtLines(UBound(allLines))
    ReDim freeLines(UBound(allLines))
    Dim igtN As Integer, freeN As Integer
    igtN = 0 : freeN = 0
    Dim i As Integer
    For i = 0 To UBound(allLines)
        If Left(allLines(i), 4) = "Free" Then
            Dim freeText As String
            freeText = Trim(Mid(allLines(i), 5))
            freeLines(freeN) = Chr(8216) & freeText & Chr(8217)   ' ' … '
            freeN = freeN + 1
        Else
            igtLines(igtN) = MassageFLExLine(allLines(i))
            igtN = igtN + 1
        End If
    Next i
    If igtN  > 0 Then ReDim Preserve igtLines(0 To igtN - 1)   Else ReDim igtLines(-1 To -1)
    If freeN > 0 Then ReDim Preserve freeLines(0 To freeN - 1) Else ReDim freeLines(-1 To -1)
End Sub

Private Function MassageFLExLine(s As String) As String
    ' Normalise multi-word FLEx line labels to single tokens, then insert
    ' MORPH_SEP sentinels around morpheme-divider characters so that each
    ' word group can later be Split() into morpheme parts.
    ' Mirrors LO massageLines().
    s = Replace(s, "Lex. Entries", "LexEntries")
    s = Replace(s, "Lex. Gloss",   "LexGloss")
    s = Replace(s, "Word Gloss",   "WordGloss")
    s = Replace(s, "Word Cat.",    "WordCat")

    ' Separate line label from content
    Dim sp As Integer
    sp = InStr(s, " ")
    If sp = 0 Then MassageFLExLine = s : Exit Function
    Dim lbl As String, body As String
    lbl  = Left(s, sp)
    body = Mid(s, sp + 1)

    ' Mark morpheme boundaries: " -" or "- " → ░-░  etc.
    body = Replace(body, "- ",  MORPH_SEP & "-"  & MORPH_SEP)
    body = Replace(body, " -",  MORPH_SEP & "-"  & MORPH_SEP)
    body = Replace(body, " <",  MORPH_SEP & "<"  & MORPH_SEP)
    body = Replace(body, "> ",  MORPH_SEP & ">"  & MORPH_SEP)
    body = Replace(body, "= ",  MORPH_SEP & "="  & MORPH_SEP)
    body = Replace(body, " =",  MORPH_SEP & "="  & MORPH_SEP)
    body = Replace(body, " ~",  MORPH_SEP & "~"  & MORPH_SEP)
    body = Replace(body, "~ ",  MORPH_SEP & "~"  & MORPH_SEP)

    ' Tuck punctuation against preceding word (no space before . , ? etc.)
    body = Replace(body, " .", ".")  : body = Replace(body, " …", "…")
    body = Replace(body, " ,", ",")  : body = Replace(body, " ?", "?")
    body = Replace(body, " !", "!")  : body = Replace(body, " :", ":")
    body = Replace(body, " ;", ";")  : body = Replace(body, "( ", "(")
    body = Replace(body, " )", ")")  : body = Replace(body, "[ ", "[")
    body = Replace(body, " ]", "]")  : body = Replace(body, Chr(34) & " ", Chr(8220))
    body = Replace(body, Chr(8220) & " ", Chr(8220))
    body = Replace(body, "' ", Chr(8216)) : body = Replace(body, Chr(8216) & " ", Chr(8216))

    MassageFLExLine = lbl & body
End Function

Private Function ClassifyLines(lines() As String, _
        ByRef lineTypes() As String, ByRef wordArrays(), _
        ByRef morphWordArr() As String, ByRef glossWordArr() As String, _
        ByRef hasLexGloss As Boolean) As Boolean
    Dim n As Integer
    n = UBound(lines)
    ReDim lineTypes(0 To n)
    ReDim wordArrays(0 To n)
    ReDim morphWordArr(-1 To -1)
    ReDim glossWordArr(-1 To -1)
    hasLexGloss = False

    Dim i As Integer
    For i = 0 To n
        Dim parts() As String
        parts = Split(lines(i), " ")
        lineTypes(i) = parts(0)
        wordArrays(i) = parts

        If InStr(VALID_TYPES, "/" & lineTypes(i) & "/") = 0 Then
            MsgBox "Unrecognised line type: """ & lineTypes(i) & """" & Chr(13) & Chr(13) & _
                   "Lines must begin with one of:" & Chr(13) & _
                   "Word, WordGloss, Morphemes, LexEntries, LexGloss, WordCat", vbExclamation
            ClassifyLines = False : Exit Function
        End If

        If lineTypes(i) = "Morphemes" Or lineTypes(i) = "LexEntries" Then morphWordArr = parts
        If lineTypes(i) = "LexGloss" Then
            glossWordArr = parts
            hasLexGloss  = True
        End If
    Next i

    ' First line must be a surface form
    If lineTypes(0) <> "Word" And lineTypes(0) <> "Morphemes" And _
       lineTypes(0) <> "LexEntries" Then
        MsgBox "First line must be a Word, Morphemes, or Lex. Entries line.", vbExclamation
        ClassifyLines = False : Exit Function
    End If

    ' LexGloss requires a morpheme line
    If hasLexGloss And UBound(morphWordArr) < 0 Then
        MsgBox "The Lex. Gloss line requires a Morpheme or Lex. Entries line.", vbExclamation
        ClassifyLines = False : Exit Function
    End If

    ClassifyLines = True
End Function


'=============================================================================
' ── FONT DETECTION ───────────────────────────────────────────────────────────
'=============================================================================

Private Function GetContextFont() As String
    ' 1. Try the font at the current cursor / selection
    ' 2. Fall back to document default paragraph font
    ' 3. Fall back to FALLBACK_FONT constant
    ' Theme-font placeholders start with "+" — treat as no font specified.
    Dim fn As String
    On Error Resume Next
    fn = Selection.Font.Name
    On Error GoTo 0
    If fn = "" Or Left(fn, 1) = "+" Then
        On Error Resume Next
        fn = ActiveDocument.Styles(wdStyleDefaultParagraphFont).Font.Name
        On Error GoTo 0
    End If
    If fn = "" Or Left(fn, 1) = "+" Then fn = FALLBACK_FONT
    GetContextFont = fn
End Function


'=============================================================================
' ── PARAGRAPH XML CONSTRUCTION ───────────────────────────────────────────────
'=============================================================================

Private Function BuildParagraphXML(wordArrays(), lineTypes() As String, _
        morphWordArr() As String, glossWordArr() As String, _
        hasLexGloss As Boolean, fontName As String) As String
    '
    ' Builds a <w:body><w:p>…</w:p></w:body> string ready for Range.InsertXML.
    ' One <m:oMath> per word, separated by ordinary Word spaces.
    ' Mirrors LO FLExTextToFrames: one frame per word, all tiers stacked.
    '
    Const NS As String = _
        "xmlns:w=""http://schemas.openxmlformats.org/wordprocessingml/2006/main"" " & _
        "xmlns:m=""http://schemas.openxmlformats.org/officeDocument/2006/math"""

    Dim firstLine() As String
    firstLine = wordArrays(0)
    Dim numWords As Integer
    numWords = UBound(firstLine)   ' index 0 = line-type label; words start at 1

    Dim body           As String
    Dim lexGlossOffset As Integer
    Dim missingText    As Boolean
    Dim missingGlosses As Boolean
    lexGlossOffset = 0

    Dim w As Integer
    For w = 1 To numWords

        ' Space between equation frames (plain Word run, not inside oMath)
        If w > 1 Then
            body = body & WRun(" ", fontName)
        End If

        ' Check for floating punctuation on first line (LO handles this too)
        Dim firstLineWord As String
        firstLineWord = firstLine(w)
        Dim wOffset As Integer
        wOffset = 0
        ' (Punctuation-only tokens on line 0 are passed through as-is;
        '  the LO code adjusts wO for such tokens — we keep it simpler here
        '  since FLEx rarely produces floating punctuation in the clipboard text.)

        ' ── Collect per-tier values for word position w ──────────────────────
        Dim tierValues() As String
        ReDim tierValues(0 To UBound(lineTypes))

        Dim t As Integer
        For t = 0 To UBound(lineTypes)
            Dim wa() As String
            wa = wordArrays(t)

            Select Case lineTypes(t)

                Case "Word", "WordGloss", "WordCat"
                    ' Word-level tier: one token per word, used directly
                    If w <= UBound(wa) Then
                        tierValues(t) = wa(w)
                    Else
                        missingText = True
                    End If

                Case "Morphemes", "LexEntries"
                    ' Morpheme-level tier: COLLAPSE morphemes into one word.
                    ' Split on MORPH_SEP, keep divider chars, join back.
                    ' Mirrors LO: words(t) = Join(Split(lineArrays(t)(wwO),"░"),"")
                    If w <= UBound(wa) Then
                        Dim morphParts() As String
                        morphParts = Split(wa(w), MORPH_SEP)
                        tierValues(t) = Join(morphParts, "")  ' e.g. kata=te
                    Else
                        missingText = True
                    End If

                Case "LexGloss"
                    ' Gloss-level tier: assemble morpheme glosses + dividers
                    ' into one string.  Mirrors LO LexGloss case in
                    ' FLExTextToFrames, including lexGlossOffset tracking.
                    Dim gi As Integer
                    gi = w + lexGlossOffset
                    Dim ga() As String
                    ga = glossWordArr

                    If gi <= UBound(ga) Then
                        tierValues(t) = ga(gi)   ' initial assignment
                    Else
                        missingGlosses = True
                    End If

                    ' If this word has morpheme splits, gather the corresponding
                    ' gloss tokens and assemble them with divider chars inline.
                    If UBound(morphWordArr) >= w And _
                       InStr(morphWordArr(w), MORPH_SEP) > 0 Then

                        Dim mparts() As String
                        mparts = Split(morphWordArr(w), MORPH_SEP)
                        Dim glossArray() As String
                        ReDim glossArray(UBound(mparts))

                        Dim y As Integer
                        For y = 0 To UBound(mparts)
                            If InStr(MORPH_DIVIDERS, mparts(y)) > 0 Then
                                ' It's a divider character (-, =, ~, etc.)
                                ' Use the divider itself; it doesn't consume a gloss slot
                                glossArray(y)  = mparts(y)
                                lexGlossOffset = lexGlossOffset - 1
                            Else
                                ' Actual morpheme — fetch the corresponding gloss token
                                If gi + y <= UBound(ga) Then
                                    glossArray(y) = ga(gi + y)
                                Else
                                    missingGlosses = True
                                End If
                            End If
                        Next y

                        ' Assemble: "carry.CMP" + "=" + "SEQ" → "carry.CMP=SEQ"
                        tierValues(t)  = Join(glossArray, "")
                        lexGlossOffset = lexGlossOffset + UBound(mparts)
                    End If
            End Select
        Next t

        ' ── Build the OMML matrix frame for this word ─────────────────────────
        body = body & BuildWordOMath(tierValues, lineTypes, fontName)
    Next w

    If missingText    Then MsgBox "Some lines appear to be missing text.",   vbInformation
    If missingGlosses Then MsgBox "Some gloss lines appear to be incomplete.", vbInformation

    BuildParagraphXML = "<w:body " & NS & "><w:p>" & body & "</w:p></w:body>"
End Function


'=============================================================================
' ── OMML MATRIX BUILDER ───────────────────────────────────────────────────────
'=============================================================================

Private Function BuildWordOMath(tierValues() As String, lineTypes() As String, _
        fontName As String) As String
    '
    ' Builds the OMML for one word:
    '
    '   <m:oMath>
    '     outer 1×1 matrix
    '       └─ inner 1×T matrix  (T = number of tiers)
    '            row 0  vernacular  [italic]
    '            row 1+ gloss/other [small caps on grammatical tokens]
    '   </m:oMath>
    '
    ' The 1-column design mirrors the LO macro (one frame per word, not per
    ' morpheme).  Morpheme dividers appear inline in the cell text.
    '
    Dim innerRows As String
    Dim t         As Integer

    For t = 0 To UBound(tierValues)
        Dim cellText As String
        cellText = tierValues(t)
        If cellText = "" Then cellText = " "   ' keep matrix shape

        ' Trailing space matches FLEx Word export convention
        If Right(cellText, 1) <> " " Then cellText = cellText & " "

        Dim cellXML As String
        If t = 0 Then
            ' Row 0: object language — italic, same as LO firstLineFrameStyle
            cellXML = MathRun(cellText, fontName, True, False)
        Else
            ' Row 1+: gloss/other — small caps on grammatical tokens,
            ' same as LO insertGlosses() applied to otherLineFrameStyle rows
            cellXML = BuildGlossRunXML(cellText, fontName)
        End If

        innerRows = innerRows & "<m:mr><m:e>" & cellXML & "</m:e></m:mr>"
    Next t

    ' Inner matrix: 1 column, T rows
    Dim innerMat As String
    innerMat = "<m:m>" & M_PROPS_1COL & innerRows & "</m:m>"

    ' Outer matrix: 1 column, 1 row (wraps the inner matrix as a single unit)
    Dim outerMat As String
    outerMat = "<m:m>" & M_PROPS_1COL & "<m:mr><m:e>" & innerMat & "</m:e></m:mr></m:m>"

    BuildWordOMath = "<m:oMath>" & outerMat & "</m:oMath>"
End Function


'=============================================================================
' ── GLOSS FORMATTING ─────────────────────────────────────────────────────────
'=============================================================================

Private Function BuildGlossRunXML(text As String, fontName As String) As String
    '
    ' Splits gloss text at morpheme punctuation and applies small caps to
    ' grammatical tokens.  Mirrors LO insertGlosses() + splitPunctuation().
    '
    ' Example:  "carry.CMP=SEQ "
    '   → segments: "carry", ".", "CMP", "=", "SEQ", " "
    '   → output:   carry  .  CMP  =  SEQ  (CMP and SEQ in small caps)
    '
    Dim segs() As String
    segs = SplitPunctuation(text)

    Dim result As String
    Dim i      As Integer
    For i = 0 To UBound(segs)
        Dim seg As String
        seg = segs(i)
        If IsGrammatical(seg, text) Then
            ' Small caps: store as lowercase (display as small caps via w:smallCaps)
            ' Mirrors LO: charCaseMap=4 + insertString(lcase(segment))
            result = result & MathRun(LCase(seg), fontName, False, True)
        Else
            result = result & MathRun(seg, fontName, False, False)
        End If
    Next i

    BuildGlossRunXML = result
End Function

Private Function SplitPunctuation(text As String) As String()
    '
    ' Splits gloss text at morpheme punctuation, keeping delimiters as their
    ' own tokens.  Mirrors LO splitPunctuation(text, true).
    '
    ' Delimiters: - = ~ < > : . | / \ ; +
    '
    Dim s As String
    s = text
    s = Replace(s, "-",  " - ")  : s = Replace(s, "=",  " = ")
    s = Replace(s, "~",  " ~ ")  : s = Replace(s, "<",  " < ")
    s = Replace(s, ">",  " > ")  : s = Replace(s, ":",  " : ")
    s = Replace(s, ".",  " . ")  : s = Replace(s, "|",  " | ")
    s = Replace(s, "/",  " / ")  : s = Replace(s, "\",  " \ ")
    s = Replace(s, ";",  " ; ")  : s = Replace(s, "+",  " + ")

    Dim i As Integer
    For i = 1 To 4
        s = Replace(s, "  ", " ")
    Next i

    Dim raw()    As String
    Dim result() As String
    raw = Split(Trim(s), " ")
    ReDim result(UBound(raw))
    Dim n As Integer
    n = 0
    For i = 0 To UBound(raw)
        If raw(i) <> "" Then
            result(n) = raw(i)
            n = n + 1
        End If
    Next i
    If n = 0 Then
        ReDim result(0)
        result(0) = text
    Else
        ReDim Preserve result(0 To n - 1)
    End If
    SplitPunctuation = result
End Function

Private Function IsGrammatical(seg As String, fullLine As String) As Boolean
    '
    ' Returns True for grammatical-gloss tokens.
    ' Mirrors LO:  Len(Refind(seg, grammaticalGlossRegex)) > 0
    '          AND Len(Refind(fullLine, "^[A-ZŊ]\.$")) = 0
    '
    ' grammaticalGlossRegex = "^[^\w]*([0-9A-Z]+|[0-9]\w+)[^\w]*$"
    '   → ALLCAPS (with optional leading/trailing punctuation)
    '   → OR digit-initial (3sg, 1pl)
    '
    ' Exclusion: single capital letter followed by period ("A.", "N.")
    ' which is a list/abbreviation marker, not a grammatical gloss.
    '

    If Len(seg) = 0 Then Exit Function

    ' Exclusion: whole segment is a single capital + period  (mirrors "^[A-ZŊ]\.$")
    If Len(Trim(seg)) = 2 Then
        Dim fc As String, sc As String
        fc = Left(Trim(seg), 1)
        sc = Mid(Trim(seg), 2, 1)
        If fc >= "A" And fc <= "Z" And sc = "." Then Exit Function
    End If

    ' Strip leading/trailing non-alphanumeric to get the core token
    Dim core As String
    core = seg
    Do While Len(core) > 0 And Not IsAlNum(Left(core, 1))
        core = Mid(core, 2)
    Loop
    Do While Len(core) > 0 And Not IsAlNum(Right(core, 1))
        core = Left(core, Len(core) - 1)
    Loop
    If Len(core) = 0 Then Exit Function   ' pure punctuation, not grammatical

    ' Single capital letter alone — not a grammatical gloss
    If Len(core) = 1 And core >= "A" And core <= "Z" Then Exit Function

    ' Digit-initial  (3sg, 1pl, 2SG …)
    Dim first As String
    first = Left(core, 1)
    If first >= "0" And first <= "9" Then
        IsGrammatical = True
        Exit Function
    End If

    ' ALLCAPS: no lowercase letters anywhere in the core
    Dim i As Integer
    For i = 1 To Len(core)
        If Mid(core, i, 1) >= "a" And Mid(core, i, 1) <= "z" Then
            Exit Function    ' lowercase found → lexical gloss, not grammatical
        End If
    Next i
    IsGrammatical = True
End Function

Private Function IsAlNum(c As String) As Boolean
    IsAlNum = (c >= "A" And c <= "Z") Or (c >= "a" And c <= "z") Or (c >= "0" And c <= "9")
End Function


'=============================================================================
' ── LOW-LEVEL XML HELPERS ────────────────────────────────────────────────────
'=============================================================================

Private Function MathRun(text As String, fontName As String, _
        isItalic As Boolean, isSmallCaps As Boolean) As String
    '
    ' Builds an <m:r> element:
    '   <m:rPr><m:nor/></m:rPr>   ← disables Cambria Math / math-italic
    '   <w:rPr>…</w:rPr>          ← explicit font + style (italic / small caps)
    '   <m:t>…</m:t>
    '
    Dim rPr As String
    rPr = "<w:rPr>" & _
          "<w:rFonts w:ascii=""" & fontName & """ w:hAnsi=""" & fontName & _
          """ w:cs=""" & fontName & """ w:eastAsia=""" & fontName & """/>"
    If isItalic    Then rPr = rPr & "<w:i/><w:iCs/>"
    If isSmallCaps Then rPr = rPr & "<w:smallCaps/>"
    rPr = rPr & "</w:rPr>"

    MathRun = "<m:r><m:rPr><m:nor/></m:rPr>" & rPr & _
              "<m:t xml:space=""preserve"">" & XmlEsc(text) & "</m:t></m:r>"
End Function

Private Function WRun(text As String, fontName As String) As String
    ' Plain Word run — used for spaces between <m:oMath> elements
    WRun = "<w:r><w:rPr><w:rFonts w:ascii=""" & fontName & _
           """ w:hAnsi=""" & fontName & """/></w:rPr>" & _
           "<w:t xml:space=""preserve"">" & XmlEsc(text) & "</w:t></w:r>"
End Function

Private Function XmlEsc(s As String) As String
    s = Replace(s, "&", "&amp;")
    s = Replace(s, "<", "&lt;")
    s = Replace(s, ">", "&gt;")
    XmlEsc = s
End Function


'=============================================================================
' ── FREE TRANSLATION INSERTION ───────────────────────────────────────────────
'=============================================================================

Private Sub InsertFreeLines(freeLines() As String, fontName As String)
    ' Insert free translation paragraph(s) after the IGT line.
    ' Mirrors LO Postcursor + free-line insertion logic.
    Selection.Collapse wdCollapseEnd
    Dim i As Integer
    For i = 0 To UBound(freeLines)
        Selection.TypeParagraph

        On Error Resume Next
        Selection.Style = ActiveDocument.Styles(STYLE_FREE_TRANS)
        On Error GoTo 0

        ' Clear any inherited equation formatting
        With Selection.Font
            .Name      = fontName
            .Italic    = False
            .SmallCaps = False
            .Bold      = False
        End With

        Selection.TypeText freeLines(i)
    Next i
End Sub
