Attribute VB_Name = "FLExToWord"
Option Explicit

'=============================================================================
' FLExToWord.bas  —  Word VBA macro for interlinear glossed text (IGT)
' Original LibreOffice macro by Moss Doerksen; Word port by Seth J
'
' Converts FLEx interlinear clipboard text into Word equation (OMath) frames,
' one per word.  Uses the Word OMath object model directly — no XML generation.
'
' Architecture:
'   • Morphemes are COLLAPSED into words  (kata░=░te  →  kata=te)
'   • Gloss dividers are assembled inline  (carry.CMP + = + SEQ  →  carry.CMP=SEQ)
'   • Each word → one OMath zone containing a T-row × 1-col matrix
'   • Rows = tiers (vernacular, gloss, wordcat, …)
'
' Per-cell formatting:
'   Row 0  object language  italic, document font
'   Row 1+ gloss / other    upright; grammatical tokens (ALLCAPS/digit-initial)
'                           stored lowercase and displayed via small caps
'
' ── INSTALLATION ─────────────────────────────────────────────────────────────
'
' OPTION A — Import the .bas file directly (recommended):
'   1. In Word, open the VBA IDE:  Alt+F11
'   2. File → Import File…  and select FLExToWord.bas
'   The module will be created and named automatically.
'   The "Attribute VB_Name" line at the top of this file is read by the
'   importer and must NOT be pasted into the code editor manually.
'
' OPTION B — Copy and paste:
'   1. In Word, open the VBA IDE:  Alt+F11
'   2. Insert → Module  to create a new module
'   3. In the Properties pane (F4), set the module Name to:  FLExToWord
'   4. Paste the contents of this file into the module, but OMIT the first
'      line ("Attribute VB_Name = ...") — it causes a compile error when
'      entered directly in the code editor.
'
' ── RUNNING ──────────────────────────────────────────────────────────────────
'   Select FLEx-copied interlinear text in your document, then run
'   FLExTextToWord via the Macros dialog (Alt+F8) or a toolbar button.
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
' ▁ U+2581 — MORPH_SEP: sentinel inserted around morpheme dividers by MassageFLExLine
'   Defined as Property Get below (VBA Const cannot use ChrW(), a runtime function)
' Characters that serve as morpheme dividers in the source data
Private Const MORPH_DIVIDERS    As String = "-<>=~"
' Valid FLEx line-type labels (same set as LO macro)
Private Const VALID_TYPES       As String = "/Word/WordGloss/Morphemes/LexEntries/LexGloss/WordCat/"

' ── OMML matrix properties — top-aligned, tight spacing (mirrors FLEx Word export) ─
Private Const M_PROPS_1COL As String = _
    "<m:mPr><m:baseJc m:val=""top""/><m:rSpRule m:val=""4""/><m:rSp m:val=""3""/>" & _
    "<m:mcs><m:mc><m:mcPr><m:count m:val=""1""/><m:mcJc m:val=""left""/>" & _
    "</m:mcPr></m:mc></m:mcs></m:mPr>"

' ── Grammatical gloss detection (mirrors LO grammaticalGlossRegex) ───────────
' Tokens are grammatical if they are ALL-CAPS (with optional digits/punctuation)
' or digit-initial (3sg, 1pl).  Single capital letter is excluded.


' ── MORPH_SEP property (replaces Const — ChrW() is not allowed in Const) ────
Private Property Get MORPH_SEP() As String
    MORPH_SEP = ChrW(9601)   ' ▁ U+2581 LOWER ONE EIGHTH BLOCK
End Property

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

    ' ── Build OOXML for all words ────────────────────────────────────────────
    Dim wordXMLs() As String
    wordXMLs = BuildParagraphXML(wordArrays, lineTypes, morphWordArr, glossWordArr, _
                                 hasLexGloss, targetFont)

    ' ── Delete the selected FLEx text, keeping one empty paragraph ──────────
    Dim replaceRng As Range
    Set replaceRng = Selection.Range
    replaceRng.Start = replaceRng.Paragraphs(1).Range.Start
    replaceRng.End   = replaceRng.Paragraphs(replaceRng.Paragraphs.Count).Range.End - 1
    Dim insertStart As Long
    insertStart = replaceRng.Start
    replaceRng.Delete

    ' ── FlatOPC file-based insertion ─────────────────────────────────────────
    ' Range.InsertXML rejects <m:oMath> everywhere (Error 6145).
    ' Solution: write the OOXML as a FlatOPC XML file — the single-file
    ' variant of the OOXML package format that Word opens natively, exactly
    ' like opening a FLEx export .docx.  Word's native file reader has no
    ' restriction on math content.  We open the file, copy the equations,
    ' paste inline, then delete the temp file.
    Dim mainDoc As Document
    Set mainDoc = ActiveDocument

    Dim tmpPath As String
    tmpPath = GetTempFilePath()
    WriteXMLFile tmpPath, CreateFlatOpcXML(wordXMLs, targetFont)

    ' Open the FlatOPC file — format 21 = wdOpenFormatXMLDocumentSerialized
    Dim tmpDoc As Document
    Set tmpDoc = Documents.Open(Filename:=tmpPath, Format:=21)

    ' Copy first paragraph's content (exclude trailing paragraph mark)
    Dim copyRng As Range
    Set copyRng = tmpDoc.Paragraphs(1).Range
    copyRng.End = copyRng.End - 1
    copyRng.Copy

    tmpDoc.Close SaveChanges:=False
    On Error Resume Next
    Kill tmpPath           ' delete temp file (best effort)
    On Error GoTo ErrHandler

    ' Paste inline at the insertion point
    mainDoc.Activate
    Dim insertPt As Range
    Set insertPt = mainDoc.Range(insertStart, insertStart)
    insertPt.Select
    Selection.Paste

    ' ── Insert free translation line(s) after the IGT paragraph ─────────────
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
    s = Replace(s, ChrW(8206), "")   ' U+200E LEFT-TO-RIGHT MARK
    s = Replace(s, ChrW(8207), "")   ' U+200F RIGHT-TO-LEFT MARK

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
            freeLines(freeN) = ChrW(8216) & freeText & ChrW(8217)   ' ' … '
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
    body = Replace(body, " ]", "]")  : body = Replace(body, Chr(34) & " ", ChrW(8220))
    body = Replace(body, ChrW(8220) & " ", ChrW(8220))
    body = Replace(body, "' ", ChrW(8216)) : body = Replace(body, ChrW(8216) & " ", ChrW(8216))

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
' ── IGT PARAGRAPH CONSTRUCTION ───────────────────────────────────────────────
'=============================================================================

Private Function BuildParagraphXML(wordArrays(), lineTypes() As String, _
        morphWordArr() As String, glossWordArr() As String, _
        hasLexGloss As Boolean, fontName As String) As String()
    '
    ' Returns a 1-based String() — one <m:oMath>…</m:oMath> per word.
    ' Collects per-tier values for each word position and delegates the
    ' OOXML generation to BuildWordOMath.
    '
    Dim firstLine() As String
    firstLine = wordArrays(0)
    Dim numWords As Integer
    numWords = UBound(firstLine)   ' index 0 = line-type label; words start at 1

    Dim words() As String
    ReDim words(1 To numWords)
    Dim lexGlossOffset As Integer
    Dim missingText    As Boolean
    Dim missingGlosses As Boolean
    lexGlossOffset = 0

    Dim w As Integer
    For w = 1 To numWords

        Dim tierValues() As String
        ReDim tierValues(0 To UBound(lineTypes))

        Dim t As Integer
        For t = 0 To UBound(lineTypes)
            Dim wa() As String
            wa = wordArrays(t)

            Select Case lineTypes(t)

                Case "Word", "WordGloss", "WordCat"
                    If w <= UBound(wa) Then
                        tierValues(t) = wa(w)
                    Else
                        missingText = True
                    End If

                Case "Morphemes", "LexEntries"
                    If w <= UBound(wa) Then
                        Dim morphParts() As String
                        morphParts = Split(wa(w), MORPH_SEP)
                        tierValues(t) = Join(morphParts, "")
                    Else
                        missingText = True
                    End If

                Case "LexGloss"
                    Dim gi As Integer
                    gi = w + lexGlossOffset
                    Dim ga() As String
                    ga = glossWordArr

                    If gi <= UBound(ga) Then
                        tierValues(t) = ga(gi)
                    Else
                        missingGlosses = True
                    End If

                    If UBound(morphWordArr) >= w And _
                       InStr(morphWordArr(w), MORPH_SEP) > 0 Then

                        Dim mparts() As String
                        mparts = Split(morphWordArr(w), MORPH_SEP)
                        Dim glossArray() As String
                        ReDim glossArray(UBound(mparts))

                        Dim y As Integer
                        For y = 0 To UBound(mparts)
                            If InStr(MORPH_DIVIDERS, mparts(y)) > 0 Then
                                glossArray(y)  = mparts(y)
                                lexGlossOffset = lexGlossOffset - 1
                            Else
                                If gi + y <= UBound(ga) Then
                                    glossArray(y) = ga(gi + y)
                                Else
                                    missingGlosses = True
                                End If
                            End If
                        Next y

                        tierValues(t)  = Join(glossArray, "")
                        lexGlossOffset = lexGlossOffset + UBound(mparts)
                    End If

            End Select
        Next t

        words(w) = BuildWordOMath(tierValues, fontName)
    Next w

    If missingText    Then MsgBox "Some lines appear to be missing text.",    vbInformation
    If missingGlosses Then MsgBox "Some gloss lines appear to be incomplete.", vbInformation

    BuildParagraphXML = words
End Function

' ─────────────────────────────────────────────────────────────────────────────

Private Function GetTempFilePath() As String
    ' Returns a unique temp file path with an .xml extension.
    ' Uses the platform-appropriate temp directory.
    Dim tmpDir As String
    Dim sep    As String
    #If Mac Then
        tmpDir = Environ("TMPDIR")
        sep    = "/"
        If tmpDir = "" Then tmpDir = "/tmp/"
    #Else
        tmpDir = Environ("TEMP")
        If tmpDir = "" Then tmpDir = Environ("TMP")
        If tmpDir = "" Then tmpDir = "C:\Temp"
        sep = "\"
    #End If
    If Right(tmpDir, 1) <> sep Then tmpDir = tmpDir & sep
    GetTempFilePath = tmpDir & "flex_igt_" & Format(Now, "yyyymmddhhmmss") & ".xml"
End Function

' ─────────────────────────────────────────────────────────────────────────────

Private Sub WriteXMLFile(filePath As String, content As String)
    ' Writes an XML string to disk as a plain-text file.
    ' Because XmlEsc encodes all non-ASCII characters as &#xNNNN; entities,
    ' the content is pure ASCII and VBA's Open/Print/Close is safe on all
    ' platforms (no ADODB or FSO dependency needed).
    Dim fileNum As Integer
    fileNum = FreeFile
    Open filePath For Output As #fileNum
    Print #fileNum, content
    Close #fileNum
End Sub

' ─────────────────────────────────────────────────────────────────────────────

Private Function CreateFlatOpcXML(wordXMLs() As String, fontName As String) As String
    '
    ' Builds a FlatOPC XML package string from per-word <m:oMath> fragments.
    ' FlatOPC (single-file OOXML) is opened by Word with
    '   Documents.Open(Filename:=path, Format:=21)   ' wdOpenFormatXMLDocumentSerialized
    ' Word's native file reader handles <m:oMath> freely — unlike InsertXML
    ' which rejects math content at inline positions (Error 6145).
    '
    ' Package structure (mirrors FLEx Word export):
    '   /_rels/.rels          → points to word/document.xml
    '   /word/document.xml    → one <w:p> with all oMath + space-run elements
    '
    Const NS_PKG  As String = "http://schemas.microsoft.com/office/2006/xmlPackage"
    Const NS_REL  As String = "http://schemas.openxmlformats.org/package/2006/relationships"
    Const NS_W    As String = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    Const NS_M    As String = "http://schemas.openxmlformats.org/officeDocument/2006/math"
    Const TYPE_DOC As String = _
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Const CT_RELS As String = _
        "application/vnd.openxmlformats-package.relationships+xml"
    Const CT_DOC  As String = _
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"

    ' Build paragraph body: oMath elements interleaved with space runs
    Dim paraBody As String
    Dim w As Integer
    For w = LBound(wordXMLs) To UBound(wordXMLs)
        If w > LBound(wordXMLs) Then paraBody = paraBody & WRun(" ", fontName)
        paraBody = paraBody & wordXMLs(w)
    Next w

    ' Assemble the FlatOPC package
    Dim x As String
    x = "<?xml version=""1.0"" encoding=""utf-8""?>" & vbLf
    x = x & "<?mso-application progid=""Word.Document""?>" & vbLf
    x = x & "<pkg:package xmlns:pkg=""" & NS_PKG & """>" & vbLf

    '── /_rels/.rels ─────────────────────────────────────────────────────────
    x = x & "<pkg:part pkg:name=""/_rels/.rels"""
    x = x & " pkg:contentType=""" & CT_RELS & """"
    x = x & " pkg:padding=""512"">" & vbLf
    x = x & "<pkg:xmlData>"
    x = x & "<Relationships xmlns=""" & NS_REL & """>"
    x = x & "<Relationship Id=""rId1"" Type=""" & TYPE_DOC & """"
    x = x & " Target=""word/document.xml""/>"
    x = x & "</Relationships>"
    x = x & "</pkg:xmlData></pkg:part>" & vbLf

    '── /word/document.xml ───────────────────────────────────────────────────
    x = x & "<pkg:part pkg:name=""/word/document.xml"""
    x = x & " pkg:contentType=""" & CT_DOC & """>" & vbLf
    x = x & "<pkg:xmlData>"
    x = x & "<w:document xmlns:w=""" & NS_W & """ xmlns:m=""" & NS_M & """>"
    x = x & "<w:body>"
    x = x & "<w:p>" & paraBody & "</w:p>"
    x = x & "<w:sectPr/>"
    x = x & "</w:body>"
    x = x & "</w:document>"
    x = x & "</pkg:xmlData></pkg:part>" & vbLf

    x = x & "</pkg:package>"
    CreateFlatOpcXML = x
End Function


'=============================================================================
' ── OMML GENERATION ──────────────────────────────────────────────────────────
'=============================================================================

Private Function BuildWordOMath(tierValues() As String, fontName As String) As String
    '
    ' Returns <m:oMath>…</m:oMath> for one IGT word: a T×1 matrix.
    '   Row 0  — object language: italic, <m:nor/> overrides Cambria Math
    '   Row 1+ — gloss/other:     upright; grammatical tokens in small caps
    '
    Dim innerRows As String
    Dim t As Integer
    For t = 0 To UBound(tierValues)
        Dim cellText As String
        cellText = tierValues(t)
        If cellText = "" Then cellText = " "
        If Right(cellText, 1) <> " " Then cellText = cellText & " "

        Dim cellXML As String
        If t = 0 Then
            cellXML = MathRun(cellText, fontName, True, False)
        Else
            cellXML = BuildGlossRunXML(cellText, fontName)
        End If
        innerRows = innerRows & "<m:mr><m:e>" & cellXML & "</m:e></m:mr>"
    Next t

    Dim mat As String
    mat = "<m:m>" & M_PROPS_1COL & innerRows & "</m:m>"
    BuildWordOMath = "<m:oMath>" & mat & "</m:oMath>"
End Function

' ─────────────────────────────────────────────────────────────────────────────

Private Function BuildGlossRunXML(text As String, fontName As String) As String
    '
    ' Splits gloss text at morpheme punctuation; applies small caps to
    ' grammatical tokens (stored as lowercase + <w:smallCaps/>).
    '
    Dim segs() As String
    segs = SplitPunctuation(text)
    Dim result As String
    Dim i As Integer
    For i = 0 To UBound(segs)
        If IsGrammatical(segs(i), text) Then
            result = result & MathRun(LCase(segs(i)), fontName, False, True)
        Else
            result = result & MathRun(segs(i), fontName, False, False)
        End If
    Next i
    BuildGlossRunXML = result
End Function

' ─────────────────────────────────────────────────────────────────────────────

Private Function MathRun(text As String, fontName As String, _
        isItalic As Boolean, isSmallCaps As Boolean) As String
    '
    ' One <m:r> element with:
    '   <m:rPr><m:nor/></m:rPr>  — disables Cambria Math / math auto-italic
    '   <w:rPr>…</w:rPr>         — explicit font, italic, small caps
    '   <m:t>…</m:t>
    '
    Dim rPr As String
    rPr = "<w:rPr><w:rFonts w:ascii=""" & fontName & """ w:hAnsi=""" & fontName & _
          """ w:cs=""" & fontName & """ w:eastAsia=""" & fontName & """/>"
    If isItalic    Then rPr = rPr & "<w:i/><w:iCs/>"
    If isSmallCaps Then rPr = rPr & "<w:smallCaps/>"
    rPr = rPr & "</w:rPr>"
    MathRun = "<m:r><m:rPr><m:nor/></m:rPr>" & rPr & _
              "<m:t xml:space=""preserve"">" & XmlEsc(text) & "</m:t></m:r>"
End Function

Private Function WRun(text As String, fontName As String) As String
    ' Plain Word run — space between <m:oMath> elements in the paragraph
    WRun = "<w:r><w:rPr><w:rFonts w:ascii=""" & fontName & _
           """ w:hAnsi=""" & fontName & """/></w:rPr>" & _
           "<w:t xml:space=""preserve"">" & XmlEsc(text) & "</w:t></w:r>"
End Function

Private Function XmlEsc(s As String) As String
    ' Escapes XML special characters AND encodes all non-ASCII code points as
    ' &#xNNNN; numeric character references.  This keeps the serialised file
    ' pure ASCII so VBA's Open/Print/Close is safe on Windows (ANSI) and Mac
    ' (UTF-8) alike — no ADODB.Stream or FSO needed.
    s = Replace(s, "&", "&amp;")    ' must come first
    s = Replace(s, "<", "&lt;")
    s = Replace(s, ">", "&gt;")

    Dim result As String
    Dim i      As Integer
    Dim cp     As Long
    Dim ch     As String
    result = ""
    For i = 1 To Len(s)
        ch = Mid(s, i, 1)
        cp = AscW(ch)
        If cp < 0 Then cp = cp + 65536    ' AscW returns -ve for code points > 32767
        If cp > 127 Then
            result = result & "&#x" & Hex(cp) & ";"
        Else
            result = result & ch
        End If
    Next i
    XmlEsc = result
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
