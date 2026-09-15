Attribute VB_Name = "modTests"
Option Explicit

'=============================================================================
' modTests  --  LingTeX-Word
'
' Self-tests.  Run RunAllTests from the Immediate window (Ctrl+G) after importing
' the modules:
'
'     RunAllTests
'
' Results print as PASS / FAIL lines followed by a summary.  This is the main gate
' before trying anything in a real document, and it runs identically on Windows
' Word and Mac Word -- which is the whole point, since nothing else in this
' project can be executed on both.
'
' These cases MIRROR ..\tools\parity-test.js, which runs the same algorithms in
' JavaScript against docs\core.js and can therefore run in CI.  The golden vectors
' come from ..\..\PROMPT.md, the specification of the FLEx clipboard format, and
' have been checked byte-for-byte against core.js.  If you change an algorithm,
' change both test files.
'
' Everything here is pure computation: no documents are opened, nothing is drawn,
' and the measurement and rendering modules are not involved.  Those need a real
' Word document and are covered by ..\TESTING.md instead.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

Private mPass As Long
Private mFail As Long
Private mRpt  As String
Private mFirstFails As String

' Set by RunAllTestsToFile: the report goes to a file and no dialog is shown, so a
' script can drive the suite (tools/run-in-word.sh, tools/run-in-word.ps1) without
' someone having to click OK. Off in normal use.
Private mQuietRun As Boolean

' Where the quiet runners leave their reports: a folder beside the document that
' holds the project, which is the one place both the macro and the script driving
' it can find without being told. Word for Mac cannot pass an argument through
' "run VB macro", so this has to be a convention rather than a parameter.
Public Const REPORT_FOLDER As String = "LingTeX-Word-reports"

'=============================================================================
' -- RUNNER -----------------------------------------------------------------
'=============================================================================

' The same suite, for a script: report to <document folder>/LingTeX-Word-reports/
' RunAllTests.txt, no dialog, no report document.  Falls back to the normal
' delivery if the file cannot be written, so a sandbox refusal still shows a result.
Public Sub RunAllTestsToFile()
    mQuietRun = True
    RunAllTests
    mQuietRun = False
End Sub

Public Sub RunAllTests()
    mPass = 0
    mFail = 0
    mRpt = ""
    mFirstFails = ""

    Emit ""
    Emit "LingTeX-Word self-tests"
    Emit "======================="

    ' Each section runs behind its own error trap, so a run-time error reports
    ' which section died and the run CONTINUES to the next one.
    RunSection "golden"
    RunSection "projections"
    RunSection "routing"
    RunSection "linebreaks"
    RunSection "columns"
    RunSection "leipzig"
    RunSection "gramgloss"
    RunSection "wrap"

    Emit ""
    If mFail = 0 Then
        Emit "ALL PASS -- " & CStr(mPass) & " passed"
    Else
        Emit "FAILURES -- " & CStr(mPass) & " passed, " & CStr(mFail) & " FAILED"
    End If

    DeliverResults
End Sub

'-----------------------------------------------------------------------------
' Run one section behind its own error trap.
'
' VBA's try/catch is On Error GoTo <label>: execution jumps to the label, Err
' holds the number and description, and Resume or falling through carries on.
'
' A run-time error inside a test is itself a finding -- usually a VBA construct
' that compiles and then will not execute, which is exactly the class of problem
' this suite exists to surface and exactly what the JavaScript harness cannot
' find. Trapping per section means one run reports EVERY such failure with its
' error number, instead of stopping at the first and hiding the rest.
'-----------------------------------------------------------------------------
Private Sub RunSection(ByVal which As String)
    On Error GoTo Crashed

    Select Case which
        Case "golden":      TestGoldenVectors
        Case "projections": TestProjections
        Case "routing":     TestRouting
        Case "linebreaks":  TestLineBreaks
        Case "columns":     TestColumnEditing
        Case "leipzig":     TestLeipzigChecks
        Case "gramgloss":   TestGramGlossDetection
        Case "wrap":        TestWrapPlanner
    End Select
    Exit Sub

Crashed:
    mFail = mFail + 1
    Emit ""
    Emit "  CRASH  section " & which & " stopped with run-time error " & _
         CStr(Err.Number) & ": " & Err.Description
    Emit "         (everything printed above in this section did run)"
    NoteFailure "section " & which & " crashed: error " & CStr(Err.Number) & _
                " " & Err.Description
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
' Collect a line of the report.
'
' Debug.Print alone is not enough: it writes ONLY to the VBA editor's Immediate
' window, and with that window closed a completed run looks exactly like a macro
' that never ran.  Everything is therefore also accumulated for DeliverResults.
'-----------------------------------------------------------------------------
Private Sub Emit(ByVal s As String)
    Debug.Print s
    SettleDebugPrint 0#
    mRpt = mRpt & s & vbCr
End Sub

'-----------------------------------------------------------------------------
' Call this immediately after EVERY Debug.Print. The linter enforces it.
'
' On Mac Word 16.112 (Apple silicon), Debug.Print leaves the VBA interpreter in
' a state where the next floating-point assignment or comparison -- in the same
' frame, OR in the frame that called the printing procedure -- raises run-time
' error 6, Overflow. Any procedure call made after the print clears that state;
' Long arithmetic does not. An empty Sub taking one Double argument is the form
' that was proven (modDocTests, bisected across some fifty variants, 2026-09-12)
' to protect the printing procedure's callers as well as itself.
' Full account: DebugPrintDiagnose below, and QUICKSTART.md.
'-----------------------------------------------------------------------------
Public Sub SettleDebugPrint(ByVal d As Double)
End Sub

'-----------------------------------------------------------------------------
' Put the results where they cannot be missed.
'
' A dialog always appears, carrying the counts and the first few failures, so the
' run is never silent even if nothing else works.  The full report also goes into
' a new document, which is far easier to select and copy than a dialog.
'
' Creating that document is the only thing in the whole of stage 1 that touches a
' document at all -- no test does.  That is deliberate: it keeps a stage-1 failure
' unambiguously about the logic rather than about Word.
'-----------------------------------------------------------------------------
Private Sub DeliverResults()
    Dim d As Document
    Dim placed As Boolean
    Dim msg As String

    If mQuietRun Then
        If WriteReportFile("RunAllTests." & PlatformTag() & ".txt", mRpt) Then Exit Sub
        ' Could not write: fall through and deliver the ordinary way.
    End If

    On Error Resume Next
    Set d = Documents.Add
    If Err.Number = 0 Then
        If Not d Is Nothing Then
            d.Content.Text = mRpt
            d.Content.Font.Name = "Courier New"
            d.Content.Font.Size = 9
            d.Content.ParagraphFormat.SpaceAfter = 0
            placed = (Err.Number = 0)
        End If
    End If
    Err.Clear
    On Error GoTo 0

    If mFail = 0 Then
        msg = "ALL PASS" & vbCr & vbCr & CStr(mPass) & " assertions passed."
    Else
        msg = "FAILURES" & vbCr & vbCr & _
              CStr(mPass) & " passed, " & CStr(mFail) & " FAILED." & vbCr & vbCr & _
              "First failures:" & vbCr & mFirstFails
    End If

    If placed Then
        msg = msg & vbCr & vbCr & _
              "The full report is in the new document that just opened. " & _
              "Select all of it, copy, and send it back."
    Else
        msg = msg & vbCr & vbCr & _
              "A document could not be created to hold the full report, so it is " & _
              "only in the Immediate window (View > Immediate Window)."
    End If

    MsgBox msg, IIf(mFail = 0, vbInformation, vbExclamation), "LingTeX-Word self-tests"
End Sub

Private Sub Ok(ByVal name As String, ByVal cond As Boolean)
    If cond Then
        mPass = mPass + 1
        Emit "  PASS  " & name
    Else
        mFail = mFail + 1
        Emit "  FAIL  " & name
        NoteFailure name
    End If
End Sub

Private Sub Eq(ByVal name As String, ByVal actual As String, ByVal expected As String)
    If actual = expected Then
        mPass = mPass + 1
        Emit "  PASS  " & name
    Else
        mFail = mFail + 1
        Emit "  FAIL  " & name
        Emit "          actual:   " & actual
        Emit "          expected: " & expected
        NoteFailure name
    End If
End Sub

' The first few failure names, for the dialog. A long list in a MsgBox is
' unreadable, and the document has the full detail anyway.
Private Sub NoteFailure(ByVal name As String)
    If mFail > 8 Then Exit Sub
    If mFail = 8 Then
        mFirstFails = mFirstFails & "  ... see the report for the rest" & vbCr
    Else
        mFirstFails = mFirstFails & "  " & name & vbCr
    End If
End Sub

Private Sub Section(ByVal title As String)
    Emit ""
    Emit title
End Sub


'=============================================================================
' -- DIAGNOSTICS -----------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' DebugPrintDiagnose -- the reproduction of the Overflow that was blamed on
' Single. Expected on Mac Word 16.112: A crashes with error 6, B passes. If A
' passes too, this build does not have the fault (Windows is expected not to).
' See SettleDebugPrint for the rule that follows from it.
'-----------------------------------------------------------------------------
Public Sub DebugPrintDiagnose()
    Dim rpt As String
    rpt = "DebugPrintDiagnose" & vbCr
    rpt = rpt & "A  Debug.Print, then a Double assignment:   " & _
          TryPrintThenAssign() & vbCr
    rpt = rpt & "B  the same, with SettleDebugPrint between: " & _
          TryPrintSettledThenAssign() & vbCr
    MsgBox rpt, vbInformation, "LingTeX-Word Debug.Print diagnostic"
End Sub

Private Function TryPrintThenAssign() As String
    Dim d As Double
    On Error GoTo Crashed
    Debug.Print "DebugPrintDiagnose A"   ' unsettled on purpose: the reproduction
    d = -1
    TryPrintThenAssign = "ok"
    Exit Function
Crashed:
    TryPrintThenAssign = "error " & CStr(Err.Number) & " " & Err.Description
    Err.Clear
End Function

Private Function TryPrintSettledThenAssign() As String
    Dim d As Double
    On Error GoTo Crashed
    Debug.Print "DebugPrintDiagnose B"
    SettleDebugPrint 0#
    d = -1
    TryPrintSettledThenAssign = "ok"
    Exit Function
Crashed:
    TryPrintSettledThenAssign = "error " & CStr(Err.Number) & " " & Err.Description
    Err.Clear
End Function

'=============================================================================
' -- GOLDEN VECTORS ---------------------------------------------------------
'=============================================================================
' From PROMPT.md.  Tabs are written as ChrW here rather than as literal tab
' characters, because a tab inside a .bas string literal is easy to destroy with
' an editor that trims or converts whitespace -- and a silently mangled vector
' would turn this gate into a rubber stamp.

Private Function T() As String
    T = vbTab
End Function

' PROMPT.md example 1, input.
Private Function Vector1Raw() As String
    Vector1Raw = _
        "Morphemes" & T & "z" & T & "zuvo" & T & "ixo" & T & T & "vu" & T & "=ve" & _
            T & "levo" & T & T & T & "=zi" & T & "zo" & T & "z" & T & "zuvo" & vbLf & _
        T & "Lex. Gloss" & T & "1SG" & T & "dream" & T & "DEM" & T & "***" & T & "fox" & _
            T & "ERG" & T & T & "follow" & T & ".CMP" & T & "REL" & T & "FOC" & _
            T & "1SG" & T & "dream" & vbLf & _
        "Free Eng Concerning what I'm dreaming about."
End Function

Private Function Vector1Forms() As String
    Vector1Forms = "z" & T & "zuvo" & T & "ixo" & T & T & "vu=ve" & T & "levo=zi" & _
                   T & "zo" & T & "z" & T & "zuvo"
End Function

Private Function Vector1Glosses() As String
    Vector1Glosses = "1SG" & T & "dream" & T & "DEM" & T & "***" & T & "fox=ERG" & _
                     T & "follow.CMP=REL" & T & "FOC" & T & "1SG" & T & "dream"
End Function

' PROMPT.md example 2, input.  Exercises prefix and suffix stacking, a proper
' noun gloss, punctuation attachment, and double enclitics.
Private Function Vector2Raw() As String
    Vector2Raw = _
        "Morphemes" & T & "zel" & T & "vimo" & T & T & T & "rixu" & T & T & T & "=xo" & _
            T & "xu" & T & "=zevi" & T & "Ozivela" & T & "ze" & T & ":" & _
            T & "zel" & T & "vimo" & T & T & T & "rixu" & T & T & T & "=xo" & _
            T & "Vo" & T & "vu" & T & "=ve" & T & "levo" & T & T & T & "=zi" & _
            T & "zo" & T & "z" & T & "zuvo" & T & "=ve" & T & "=zi" & vbLf & _
        T & "Lex. Gloss" & T & "yam" & T & T & "pick" & T & ".CMP" & T & T & "stack" & _
            T & ".CMP" & T & "SEQ" & T & "3SG" & T & "all" & T & "P.N." & T & "ACMP" & _
            T & T & "yam" & T & T & "pick" & T & ".CMP" & T & T & "stack" & T & ".CMP" & _
            T & "SEQ" & T & "P.N." & T & "fox" & T & "ERG" & T & T & "follow" & _
            T & ".CMP" & T & "REL" & T & "FOC" & T & "1SG" & T & "dream" & T & "ABL" & _
            T & "REL" & vbLf & _
        "Free Eng (When) she picked her yams."
End Function

Private Function Vector2Forms() As String
    Vector2Forms = "zel" & T & "vimo" & T & "rixu=xo" & T & "xu=zevi" & T & "Ozivela" & _
        T & "ze:" & T & "zel" & T & "vimo" & T & "rixu=xo" & T & "Vo" & T & "vu=ve" & _
        T & "levo=zi" & T & "zo" & T & "z" & T & "zuvo=ve=zi"
End Function

Private Function Vector2Glosses() As String
    Vector2Glosses = "yam" & T & "pick.CMP" & T & "stack.CMP=SEQ" & T & "3SG=all" & _
        T & "P.N." & T & "ACMP" & T & "yam" & T & "pick.CMP" & T & "stack.CMP=SEQ" & _
        T & "P.N." & T & "fox=ERG" & T & "follow.CMP=REL" & T & "FOC" & T & "1SG" & _
        T & "dream=ABL=REL"
End Function

Private Sub TestGoldenVectors()
    Section "Golden vectors (PROMPT.md)"
    CheckVector "example 1", Vector1Raw(), Vector1Forms(), Vector1Glosses(), _
                "Concerning what I'm dreaming about."
    CheckVector "example 2", Vector2Raw(), Vector2Forms(), Vector2Glosses(), _
                "(When) she picked her yams."
End Sub

Private Sub CheckVector(ByVal name As String, ByVal raw As String, _
        ByVal wantForms As String, ByVal wantGlosses As String, ByVal wantFree As String)

    Dim ex As IgtExample
    ex = ModelFromText(raw, igtWordAligned)

    Ok name & ": parsed", (ex.TierCount >= 2 And ex.ColCount > 0)
    If ex.TierCount < 2 Then Exit Sub

    Eq name & ": word-aligned forms", RowText(ex, 0), wantForms
    Eq name & ": word-aligned glosses", RowText(ex, 1), wantGlosses
    Ok name & ": free translation captured", (ex.FreeCount = 1)
    If ex.FreeCount = 1 Then Eq name & ": free translation text", ex.FreeLines(0), wantFree
End Sub

Private Function RowText(ex As IgtExample, ByVal t As Long) As String
    Dim c As Long, s As String
    For c = 0 To ex.ColCount - 1
        If c > 0 Then s = s & vbTab
        s = s & ex.Cells(t, c)
    Next c
    RowText = s
End Function


'=============================================================================
' -- PROJECTIONS ------------------------------------------------------------
'=============================================================================

Private Sub TestProjections()
    Section "Projections (word-aligned vs morpheme-aligned)"
    CheckProjection "example 1", Vector1Raw()
    CheckProjection "example 2", Vector2Raw()
End Sub

Private Sub CheckProjection(ByVal name As String, ByVal raw As String)
    Dim word As IgtExample, morph As IgtExample
    Dim warnings As Collection
    Dim w As Variant
    Dim nBreakWarnings As Long
    Dim flags() As Boolean
    Dim c As Long

    word = ModelFromText(raw, igtWordAligned)
    morph = ModelFromText(raw, igtMorphemeAligned)

    Ok name & ": morpheme-aligned has at least as many columns", _
       (morph.ColCount >= word.ColCount)

    ' A morpheme-aligned projection must satisfy invariant 1 BY CONSTRUCTION:
    ' the boundary character is written onto both cells of every split.
    Set warnings = CheckExample(morph)
    For Each w In warnings
        If w.Code = WARN_BREAK_MISSING Or w.Code = WARN_BREAK_CONFLICT Then
            nBreakWarnings = nBreakWarnings + 1
        End If
    Next w
    Ok name & ": morpheme-aligned satisfies break-char agreement", (nBreakWarnings = 0)

    ' Merging every continuation column back into its head must reproduce the
    ' word-aligned projection: the two are views of one segment list, not two
    ' separate parsers.
    flags = NoBreakFlags(morph)
    For c = morph.ColCount - 1 To 1 Step -1
        If flags(c) Then MergeColumns morph, c - 1, c
    Next c
    Eq name & ": merging continuations reproduces word-aligned forms", _
       RowText(morph, 0), RowText(word, 0)
    Eq name & ": merging continuations reproduces word-aligned glosses", _
       RowText(morph, 1), RowText(word, 1)
End Sub


'=============================================================================
' -- INPUT ROUTING ----------------------------------------------------------
'=============================================================================

Private Sub TestRouting()
    Dim ex As IgtExample
    Dim tsv As String

    Section "Input routing"

    Ok "recognises FLEx text by its tier labels", LooksLikeFlex(Vector1Raw())
    Ok "recognises a space-separated labelled block", _
       LooksLikeFlex("Morphemes zomu -xa" & vbLf & "LexGloss go DIST")
    Ok "recognises the spaced label spellings", _
       LooksLikeFlex("Morphemes" & T & "zomu" & vbLf & T & "Lex. Gloss" & T & "go")
    Ok "does NOT mistake plain TSV for FLEx", _
       (LooksLikeFlex("zomu-xa" & T & "vu" & vbLf & "go-DIST" & T & "fox") = False)

    ' The FLEx parser treats column 0 as a tier label, so plain TSV sent down that
    ' path would lose the first cell of every row.  This is the round trip that
    ' matters: the add-in's own TSV has to come back in unchanged.
    tsv = "zomu-xa" & T & "vu" & vbLf & "go-DIST" & T & "fox" & vbLf & "He went far away."
    ex = ModelFromText(tsv, igtWordAligned)
    Ok "plain TSV parses", (ex.TierCount = 2 And ex.ColCount = 2)
    If ex.TierCount = 2 Then
        Eq "plain TSV keeps its first column", RowText(ex, 0), "zomu-xa" & T & "vu"
        Eq "plain TSV keeps its gloss row", RowText(ex, 1), "go-DIST" & T & "fox"
    End If
    Ok "plain TSV lifts the untabbed line to a free translation", (ex.FreeCount = 1)

    ' Full round trip: FLEx in, TSV out, TSV back in, same grid.
    Dim first As IgtExample, again As IgtExample
    first = ModelFromText(Vector1Raw(), igtWordAligned)
    again = ModelFromText(ModelToTsv(first), igtWordAligned)
    Eq "TSV round trip preserves the form row", RowText(again, 0), RowText(first, 0)
    Eq "TSV round trip preserves the gloss row", RowText(again, 1), RowText(first, 1)
End Sub


'=============================================================================
' -- LINE BREAKS ------------------------------------------------------------
'=============================================================================

' Text from Windows, and text PowerPoint takes off the clipboard, ends its lines
' in CR LF; Word for Mac hands the parsers CR, a paragraph mark.  All of it must
' parse as LF text does.  The CR LF is built from Chr$(13) & Chr$(10), never
' from vbCrLf: in PowerPoint for Mac 16.112 that is LF then CR, the parsers
' once normalised with it, and every CR LF became two line breaks -- a blank
' line after each tier row, where ParseFlexBlocks ends an example.
Private Sub TestLineBreaks()
    Dim lf As String
    Dim mixed As String

    Section "Line breaks (CR LF and CR input parse as LF input does)"
    Emit "  note  " & LineBreakConstantsLine()

    Eq "LINE_CRLF is CR then LF", CharCodes(LINE_CRLF), "[13+10]"
    mixed = "a" & Chr$(13) & Chr$(10) & "b" & Chr$(13) & "c" & Chr$(10) & "d"
    Eq "NormalizeLineBreaks makes CR LF, CR and LF one LF each", _
       ShowBreaks(NormalizeLineBreaks(mixed)), "a<LF>b<LF>c<LF>d"

    ' A FLEx block: Morphemes, Lex. Gloss and Free lines.
    CheckLineBreakVariants "FLEx block", Vector1Raw(), 2, 1

    ' A plain TSV example, ending in a line break as copied text usually does.
    lf = "zomu-xa" & T & "vu" & vbLf & "go-DIST" & T & "fox" & vbLf & _
         "He went far away." & vbLf
    CheckLineBreakVariants "TSV example", lf, 3, 1

    ' Two FLEx examples separated by one blank line: two, not one and not four.
    lf = Vector1Raw() & vbLf & vbLf & Vector2Raw()
    CheckLineBreakVariants "two FLEx examples", lf, 5, 2
    CheckTwoExamplesCrLf lf
End Sub

' The same text with LF, CR LF and CR line breaks must give the same examples:
' as many of them, with the same tiers, cells and free translations.
Private Sub CheckLineBreakVariants(ByVal name As String, ByVal lfText As String, _
        ByVal wantBreaks As Long, ByVal wantExamples As Long)
    Dim crlfText As String, crText As String
    Dim lfLines() As String, crlfLines() As String
    Dim lfBlocks() As FlexBlock, crlfBlocks() As FlexBlock, crBlocks() As FlexBlock
    Dim lfModels() As IgtExample, nLf As Long

    crlfText = Replace(lfText, Chr$(10), Chr$(13) & Chr$(10))
    crText = Replace(lfText, Chr$(10), Chr$(13))

    ' Guards the test itself: the LF text is built with vbLf, and a vbLf that
    ' was not Chr$(10) would leave nothing here to convert.
    Ok name & ": the CR LF input has " & CStr(wantBreaks) & " CR LF pairs and no lone LF", _
       (CountOf(crlfText, Chr$(13) & Chr$(10)) = wantBreaks And CountOf(crlfText, Chr$(10)) = wantBreaks)
    Eq name & ": CR LF normalises to the LF text, no break doubled", _
       ShowBreaks(NormalizeLineBreaks(crlfText)), ShowBreaks(lfText)
    Eq name & ": routed the same with CR LF", _
       CStr(LooksLikeFlex(crlfText)), CStr(LooksLikeFlex(lfText))

    lfLines = TextLines(lfText)
    crlfLines = TextLines(crlfText)
    Eq name & ": TextLines gives the same lines with CR LF", _
       Join(crlfLines, " / "), Join(lfLines, " / ")

    If LooksLikeFlex(lfText) Then
        lfBlocks = ParseFlexBlocks(lfText)
        crlfBlocks = ParseFlexBlocks(crlfText)
        crBlocks = ParseFlexBlocks(crText)
        Eq name & ": ParseFlexBlocks finds as many blocks with CR LF", _
           CStr(UBound(crlfBlocks) + 1), CStr(UBound(lfBlocks) + 1)
        Eq name & ": ParseFlexBlocks finds as many blocks with CR", _
           CStr(UBound(crBlocks) + 1), CStr(UBound(lfBlocks) + 1)
    End If

    lfModels = ModelsFromText(lfText, igtWordAligned, nLf)
    Eq name & ": examples in the LF text", CStr(nLf), CStr(wantExamples)
    CheckSameExamples name & ", CR LF", lfText, crlfText
    CheckSameExamples name & ", CR", lfText, crText
End Sub

Private Sub CheckSameExamples(ByVal name As String, ByVal lfText As String, _
        ByVal otherText As String)
    Dim want() As IgtExample, got() As IgtExample
    Dim nWant As Long, nGot As Long
    Dim a As IgtExample, b As IgtExample
    Dim i As Long

    want = ModelsFromText(lfText, igtWordAligned, nWant)
    got = ModelsFromText(otherText, igtWordAligned, nGot)
    Eq name & ": as many examples", CStr(nGot), CStr(nWant)
    If nGot <> nWant Then Exit Sub

    For i = 0 To nGot - 1
        a = got(i)
        b = want(i)
        Eq name & ": example " & CStr(i + 1) & " is the same", _
           ExampleText(a), ExampleText(b)
    Next i
End Sub

' Neither example absorbed nor split: each block is the PROMPT.md example it
' was built from.
Private Sub CheckTwoExamplesCrLf(ByVal lfText As String)
    Dim models() As IgtExample, n As Long
    Dim ex As IgtExample

    models = ModelsFromText(Replace(lfText, Chr$(10), Chr$(13) & Chr$(10)), igtWordAligned, n)
    If n <> 2 Then Exit Sub                  ' already reported as a count
    ex = models(0)
    Eq "two FLEx examples, CR LF: the first is example 1", RowText(ex, 0), Vector1Forms()
    ex = models(1)
    Eq "two FLEx examples, CR LF: the second is example 2", RowText(ex, 0), Vector2Forms()
End Sub

' An example as one line: each tier's role and cells, then its free lines,
' with any control character left in them spelled out.
Private Function ExampleText(ex As IgtExample) As String
    Dim i As Long, s As String
    For i = 0 To ex.TierCount - 1
        s = s & ex.Tiers(i) & ": " & ShowBreaks(RowText(ex, i)) & " / "
    Next i
    For i = 0 To ex.FreeCount - 1
        s = s & "Free: " & ShowBreaks(ex.FreeLines(i)) & " / "
    Next i
    ExampleText = s
End Function

' CR, LF and tab spelled out, so a report shows where the breaks are.
Private Function ShowBreaks(ByVal s As String) As String
    s = Replace(s, Chr$(13), "<CR>")
    s = Replace(s, Chr$(10), "<LF>")
    ShowBreaks = Replace(s, vbTab, "<TAB>")
End Function

' How many times part occurs in s.
Private Function CountOf(ByVal s As String, ByVal part As String) As Long
    CountOf = (Len(s) - Len(Replace(s, part, ""))) \ Len(part)
End Function

' The character codes of a string: "[13+10]".
Private Function CharCodes(ByVal s As String) As String
    Dim i As Long, out As String
    For i = 1 To Len(s)
        If i > 1 Then out = out & "+"
        out = out & CStr(AscW(Mid$(s, i, 1)))
    Next i
    CharCodes = "[" & out & "]"
End Function

' What this host's line-break constants really are.  Recorded, not asserted:
' nothing may depend on them.
Private Function LineBreakConstantsLine() As String
    LineBreakConstantsLine = "here vbCr is " & CharCodes(vbCr) & _
        ", vbLf " & CharCodes(vbLf) & _
        ", vbCrLf " & CharCodes(vbCrLf) & _
        ", vbNewLine " & CharCodes(vbNewLine)
End Function

' The same line on its own, for  tools/run-in-word.sh --macro LogLineBreakConstants:
' written to LingTeX-Word-reports/LineBreaks.<mac|win>.txt, no dialog.
Public Sub LogLineBreakConstants()
    Dim s As String
    s = LineBreakConstantsLine()
    If Not WriteReportFile("LineBreaks." & PlatformTag() & ".txt", s) Then
        MsgBox s, vbInformation, "LingTeX-Word line breaks"
    End If
End Sub


'=============================================================================
' -- COLUMN EDITING ---------------------------------------------------------
'=============================================================================

Private Function TwoTier(ByVal form As String, ByVal gloss As String) As IgtExample
    Dim ex As IgtExample
    Dim f() As String, g() As String
    Dim c As Long

    f = Split(form, vbTab)
    g = Split(gloss, vbTab)
    ex = NewExample(2, UBound(f) + 1)
    ex.Tiers(0) = ROLE_MORPHEMES
    ex.Tiers(1) = ROLE_GLOSS
    For c = 0 To UBound(f)
        ex.Cells(0, c) = f(c)
        If c <= UBound(g) Then ex.Cells(1, c) = g(c)
    Next c
    TwoTier = ex
End Function

Private Sub TestColumnEditing()
    Dim ex As IgtExample
    Dim shortTiers As String
    Dim okAll As Boolean

    Section "Column split and merge"

    '-- a clean split --------------------------------------------------------
    ex = TwoTier("zomu-xa" & T & "vu", "go-DIST" & T & "fox")
    okAll = SplitColumn(ex, 0, 1, shortTiers)
    Ok "split: reports success", okAll
    Eq "split: form pieces", ex.Cells(0, 0) & "|" & ex.Cells(0, 1), "zomu|-xa"
    Eq "split: gloss pieces", ex.Cells(1, 0) & "|" & ex.Cells(1, 1), "go|-DIST"
    Ok "split: the boundary leads both new cells, so invariant 1 holds", _
       (CountBreakWarnings(ex) = 0)
    Eq "split: the untouched column moved right", ex.Cells(0, 2), "vu"

    MergeColumns ex, 0, 1
    Eq "merge: restores the form", ex.Cells(0, 0), "zomu-xa"
    Eq "merge: restores the gloss", ex.Cells(1, 0), "go-DIST"

    '-- a tier with no matching boundary is never guessed at ----------------
    ex = TwoTier("zomu-xa", "gone")
    okAll = SplitColumn(ex, 0, 1, shortTiers)
    Ok "split: reports failure when a tier has no boundary", (okAll = False)
    Eq "split: names the short tier", shortTiers, ROLE_GLOSS
    Eq "split: the short tier keeps its cell whole on the left", ex.Cells(1, 0), "gone"
    Eq "split: the short tier leaves the right column empty", ex.Cells(1, 1), ""

    '-- a leading boundary belongs to the column, it is not a split point ---
    ex = TwoTier("=ve=zi", "=ABL=REL")
    SplitColumn ex, 0, 1, shortTiers
    Eq "split: does not split on a leading boundary", _
       ex.Cells(0, 0) & "|" & ex.Cells(0, 1), "=ve|=zi"

    '-- insert and delete ---------------------------------------------------
    ex = TwoTier("a" & T & "b", "A" & T & "B")
    InsertColumn ex, 1
    Eq "insert: shifts the tail right", _
       ex.Cells(0, 0) & "|" & ex.Cells(0, 1) & "|" & ex.Cells(0, 2), "a||b"
    DeleteColumn ex, 1
    Eq "delete: closes the gap", ex.Cells(0, 0) & "|" & ex.Cells(0, 1), "a|b"
End Sub

Private Function CountBreakWarnings(ex As IgtExample) As Long
    Dim w As Variant, n As Long
    For Each w In CheckExample(ex)
        If w.Code = WARN_BREAK_MISSING Or w.Code = WARN_BREAK_CONFLICT Then n = n + 1
    Next w
    CountBreakWarnings = n
End Function

Private Function HasWarning(ex As IgtExample, ByVal code As String) As Boolean
    Dim w As Variant
    For Each w In CheckExample(ex)
        If w.Code = code Then
            HasWarning = True
            Exit Function
        End If
    Next w
End Function


'=============================================================================
' -- LEIPZIG CHECKS ---------------------------------------------------------
'=============================================================================

Private Sub TestLeipzigChecks()
    Dim ex As IgtExample
    Dim n As Long

    Section "Leipzig checks"

    '-- invariant 1: a column where only some cells carry the break char ---
    ex = TwoTier("-xa", "DIST")
    Ok "detects a column where only some cells carry the break character", _
       HasWarning(ex, WARN_BREAK_MISSING)
    Ok "auto-fix adds the agreed character", FixColumnBreakChars(ex, 0)
    Eq "auto-fix result", ex.Cells(1, 0), "-DIST"
    Ok "no break-char warning remains", (CountBreakWarnings(ex) = 0)

    '-- a conflict is reported, never silently resolved ---------------------
    ex = TwoTier("-xa", "=DIST")
    Ok "detects conflicting break characters", HasWarning(ex, WARN_BREAK_CONFLICT)
    Ok "auto-fix refuses to pick one", (FixColumnBreakChars(ex, 0) = False)

    '-- invariant 2: no spaces in an interlinear cell ----------------------
    ex = TwoTier("zomu", "went away")
    Ok "detects a space inside an interlinear cell", HasWarning(ex, WARN_SPACE_IN_CELL)
    n = FixCellSpaces(ex, ".")
    Ok "space fix reports one cell changed", (n = 1)
    Eq "space fix result", ex.Cells(1, 0), "went.away"
    Ok "no space warning remains", (HasWarning(ex, WARN_SPACE_IN_CELL) = False)

    '-- a free-translation row keeps its spaces ----------------------------
    ex = TwoTier("zomu", "go")
    InsertTierRow ex, 2, ROLE_FREE
    ex.Cells(2, 0) = "He went away."
    Ok "a free row is exempt from the space rule", _
       (HasWarning(ex, WARN_SPACE_IN_CELL) = False)
    FixCellSpaces ex, "."
    Eq "a free row keeps its spaces through a fix", ex.Cells(2, 0), "He went away."

    '-- rule 2 counts segmentable breaks only ------------------------------
    ex = TwoTier("rixu=xo", "stack.CMP=SEQ")
    Ok "rule 2 ignores "".""  and "":""", (HasWarning(ex, WARN_PARITY) = False)
    ex = TwoTier("rixu=xo", "stack-CMP=SEQ")
    Ok "rule 2 flags a real boundary mismatch", HasWarning(ex, WARN_PARITY)

    '-- rule 8 ------------------------------------------------------------
    ex = TwoTier("k<um>ain", "eat<INF")
    Ok "detects an unmatched infix bracket", HasWarning(ex, WARN_UNMATCHED)
End Sub


'=============================================================================
' -- GRAMMATICAL GLOSS DETECTION --------------------------------------------
'=============================================================================

Private Sub TestGramGlossDetection()
    Section "Grammatical-gloss detection (no abbreviation allow-list)"

    ' Cases from word_processing_tools\FLExToWord_TestChecklist.md section 11,
    ' with one correction.  That table claims "3sg" is NOT a grammatical gloss
    ' while also claiming "1s" IS one, "(digit-initial)" -- it contradicts itself.
    ' docs\core.js settles it: the second branch of its pattern is [0-9]\w+ and its
    ' docblock reads "OR digit-initial (3sg, 1pl)".  That is also the right answer
    ' typographically: someone writing "3sg" means the same category as "3SG" and
    ' wants the same small caps.
    CheckGram "FOC", True
    CheckGram "3SG", True
    CheckGram "3sg", True
    CheckGram "1s", True
    CheckGram "bark", False
    CheckGram "P.N.", False
    CheckGram "N.", False
    CheckGram "A.", False
    CheckGram "DIST", True
    CheckGram "CMP", True
    CheckGram "ERG", True
    CheckGram "POSS", True
    ' The point of having no allow-list: an abbreviation nobody has ever published
    ' is still recognised, because recognition is structural.
    CheckGram "NOTALEIPZIGABBREVIATION", True
End Sub

Private Sub CheckGram(ByVal tok As String, ByVal want As Boolean)
    Ok "IsGramGloss(" & tok & ") = " & CStr(want), (IsGramGloss(tok) = want)
End Sub


'=============================================================================
' -- WRAP PLANNER -----------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Wrap planner tests.
'
' Structured as one tiny function per case, each with its own error trap that
' returns the error as its RESULT rather than letting it propagate. So a case
' that blows up shows as a failure with the error number printed inline, next to
' the case that caused it, and every other case still runs.
'
' That shape is deliberate. The previous version was a single Sub that died with
' run-time error 6 on its first assertion, right after an Emit; splitting it into
' small functions moved each assertion away from the print and "fixed" it. The
' cause was Debug.Print (see SettleDebugPrint), understood only later; the shape
' stays because a case that fails still shows its error inline, next to the case
' that caused it, and every other case still runs.
'
' Widths and flags come in as Variant arrays from Array(), so there is no string
' parsing between the test and the thing under test.
'-----------------------------------------------------------------------------
Private Sub TestWrapPlanner()
    Section "Wrap planner"

    Eq "exact fit stays on one line", _
       WrapOf(Array(10, 10, 10), Array(0, 0, 0), 30), "0"
    Eq "one column over the budget wraps", _
       WrapOf(Array(10, 10, 10), Array(0, 0, 0), 25), "0,2"
    Eq "three wrap lines", _
       WrapOf(Array(10, 10, 10, 10, 10, 10), Array(0, 0, 0, 0, 0, 0), 25), "0,2,4"
    Eq "an over-wide single column gets its own line and overflows", _
       WrapOf(Array(10, 100, 10), Array(0, 0, 0), 25), "0,1,2"
    Eq "widening pulls columns back up (same input, bigger budget)", _
       WrapOf(Array(10, 10, 10, 10), Array(0, 0, 0, 0), 100), "0"

    ' A leading-boundary column must never start a line, so the break moves back
    ' and "zomu" stays with "-xa".
    Eq "a wrap line never starts on a continuation column", _
       WrapOf(Array(10, 10, 10), Array(0, 0, 1), 25), "0,1"
    Eq "backing up is abandoned rather than emptying a line", _
       WrapOf(Array(10, 10), Array(0, 1), 15), "0,1"

    TestNoBreakFlagsFromData
End Sub

'-----------------------------------------------------------------------------
' Plan a wrap and render the line starts as "0,2,4".
' Returns the error text instead of raising, so one bad case cannot hide the rest.
'-----------------------------------------------------------------------------
Private Function WrapOf(widthsV As Variant, flagsV As Variant, _
        ByVal avail As Double) As String

    Dim widths() As Double
    Dim flags() As Boolean
    Dim starts() As Long
    Dim i As Long
    Dim s As String

    On Error GoTo Failed

    ReDim widths(0 To UBound(widthsV))
    ReDim flags(0 To UBound(widthsV))
    For i = 0 To UBound(widthsV)
        widths(i) = CDbl(widthsV(i))
        flags(i) = (CLng(flagsV(i)) <> 0)
    Next i

    starts = ComputeWrapLines(widths, flags, avail, 0, 0)

    For i = LBound(starts) To UBound(starts)
        If s <> "" Then s = s & ","
        s = s & CStr(starts(i))
    Next i
    WrapOf = s
    Exit Function

Failed:
    WrapOf = "ERROR " & CStr(Err.Number) & ": " & Err.Description
End Function

' The same flags derived from real data rather than written by hand.
' Separated out so its IgtExample local is not in scope for the cases above.
Private Sub TestNoBreakFlagsFromData()
    Dim ex As IgtExample
    Dim flags() As Boolean

    On Error GoTo Failed
    ex = ModelFromText(Vector2Raw(), igtMorphemeAligned)
    flags = NoBreakFlags(ex)
    Ok "NoBreakFlags never flags the first column", (flags(0) = False)
    Ok "NoBreakFlags flags the enclitic columns of example 2", (CountTrue(flags) > 0)
    Exit Sub

Failed:
    Ok "NoBreakFlags from real data (error " & CStr(Err.Number) & ": " & _
       Err.Description & ")", False
End Sub

Private Function CountTrue(flags() As Boolean) As Long
    Dim i As Long, n As Long
    For i = LBound(flags) To UBound(flags)
        If flags(i) Then n = n + 1
    Next i
    CountTrue = n
End Function


'=============================================================================
' -- REPORT FILES (for the scripted runners) --------------------------------
'=============================================================================

' The folder the quiet runners write to, created on demand.  Beside the document
' that holds the VBA project -- ThisDocument -- because that path is known to the
' script that opened it.  Empty if there is no such path (an unsaved document).
' "mac" or "win": the reports of the two platforms sit side by side in the
' repository (RunAllTests.mac.txt, RunAllTests.win.txt) and never overwrite each
' other, so a run on one can be compared with the other.
Public Function PlatformTag() As String
    If Application.PathSeparator = "/" Then
        PlatformTag = "mac"
    Else
        PlatformTag = "win"
    End If
End Function

Public Function ReportFolderPath() As String
    Dim base As String, sep As String
    ' The clone's LingTeX-Word folder if the file holding the code has been
    ' told where it is (a document variable set by SetDevRoot in modImport, so
    ' the template can live in Word's STARTUP folder); else the file's own.
    On Error Resume Next
    base = CStr(ThisDocument.Variables("LingTeX_DevRoot").Value)
    If Err.Number <> 0 Then base = ""
    Err.Clear
    If base = "" Then base = ThisDocument.Path
    sep = Application.PathSeparator
    Err.Clear
    On Error GoTo 0
    If base = "" Then Exit Function
    If Right$(base, 1) = sep Then base = Left$(base, Len(base) - 1)
    ReportFolderPath = base & sep & REPORT_FOLDER
End Function

' Write one report.  True on success.  Shared by modDocTests, which is why it is
' Public; a failure is never raised, only returned, so the caller can fall back to
' showing the report the ordinary way.
Public Function WriteReportFile(ByVal leaf As String, ByVal text As String) As Boolean
    Dim folder As String, path As String
    Dim fn As Integer

    folder = ReportFolderPath()
    If folder = "" Then Exit Function

    On Error Resume Next
    If Dir(folder, vbDirectory) = "" Then MkDir folder
    Err.Clear
    On Error GoTo 0

    path = folder & Application.PathSeparator & leaf
    On Error GoTo Failed
    fn = FreeFile
    Open path For Output As #fn
    ' The report is built with vbCr between lines. Write it with this platform's
    ' newline (CRLF on Windows, CR on Mac): a bare CR in a Windows console is
    ' "return to the start of the line", and the runner's printout came out as
    ' every line overwriting the last (Windows run, 2026-09-12).
    Print #fn, Replace(text, vbCr, vbNewLine)
    Close #fn
    WriteReportFile = True
    Exit Function

Failed:
    On Error Resume Next
    Close #fn
    Err.Clear
End Function
