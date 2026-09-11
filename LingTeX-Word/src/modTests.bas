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

'=============================================================================
' -- RUNNER -----------------------------------------------------------------
'=============================================================================

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
    mRpt = mRpt & s & vbCr
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
' -- WRAP DIAGNOSTIC --------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Run this when the wrap section crashes: DiagnoseWrap
'
' Performs the same work as the first wrap assertion, one step at a time, and
' prints a marker before each. Whatever the last marker is, the step after it is
' what failed -- so the output names the exact statement rather than the section.
'
' It builds the arrays by hand as well as by parsing, so it separates "the test
' harness cannot parse its own input" from "ComputeWrapLines itself fails".
'-----------------------------------------------------------------------------
Public Sub DiagnoseWrap()
    Dim wParts() As String, fParts() As String
    Dim parsedW() As Single, parsedF() As Boolean
    Dim fixedW(0 To 2) As Single
    Dim fixedF(0 To 2) As Boolean
    Dim lineStarts() As Long
    Dim i As Long
    Dim stepNo As Long
    Dim s As String

    mRpt = ""
    Emit "DiagnoseWrap"
    Emit "============"

    On Error GoTo Crashed

    stepNo = 1
    Emit "step 1  build fixed-size arrays by hand"
    fixedW(0) = 10
    fixedW(1) = 10
    fixedW(2) = 10
    fixedF(0) = False
    fixedF(1) = False
    fixedF(2) = False

    stepNo = 2
    Emit "step 2  call ComputeWrapLines with the hand-built arrays"
    lineStarts = ComputeWrapLines(fixedW, fixedF, 30, 0, 0)

    stepNo = 3
    Emit "step 3  read its bounds"
    Emit "        LBound=" & CStr(LBound(lineStarts)) & _
         "  UBound=" & CStr(UBound(lineStarts))

    stepNo = 4
    Emit "step 4  render the line starts"
    s = ""
    For i = LBound(lineStarts) To UBound(lineStarts)
        If s <> "" Then s = s & ","
        s = s & CStr(lineStarts(i))
    Next i
    Emit "        result = " & s & "   (expected 0)"

    stepNo = 5
    Emit "step 5  Split the width string"
    wParts = Split("10,10,10", ",")
    fParts = Split("0,0,0", ",")
    Emit "        UBound(wParts)=" & CStr(UBound(wParts)) & _
         "  UBound(fParts)=" & CStr(UBound(fParts))

    stepNo = 6
    Emit "step 6  ReDim the parsed arrays"
    ReDim parsedW(0 To UBound(wParts))
    ReDim parsedF(0 To UBound(wParts))

    stepNo = 7
    Emit "step 7  parse each width with Val then CSng"
    For i = 0 To UBound(wParts)
        Emit "        i=" & CStr(i) & " raw=[" & wParts(i) & "]"
        parsedW(i) = CSng(Val(Trim$(wParts(i))))
        parsedF(i) = False
        If i <= UBound(fParts) Then parsedF(i) = (Trim$(fParts(i)) = "1")
    Next i

    stepNo = 8
    Emit "step 8  call ComputeWrapLines with the parsed arrays"
    lineStarts = ComputeWrapLines(parsedW, parsedF, 30, 0, 0)
    Emit "        ok, UBound=" & CStr(UBound(lineStarts))

    stepNo = 9
    Emit "step 9  call PlanStarts end to end"
    Emit "        result = " & PlanStarts("10,10,10", "0,0,0", 30)

    Emit ""
    Emit "COMPLETED with no error. The crash is somewhere else."
    GoTo Done

Crashed:
    Emit ""
    Emit "CRASHED at the step AFTER marker " & CStr(stepNo) & _
         " -- run-time error " & CStr(Err.Number) & ": " & Err.Description
    Err.Clear

Done:
    Debug.Print mRpt
    MsgBox mRpt, vbInformation, "LingTeX-Word wrap diagnostic"
End Sub

'-----------------------------------------------------------------------------
' TypeCheck -- which numeric types actually work on this build?
'
' MicroDiagnose reported run-time error 6, Overflow, on "s1 = 10" where s1 is
' declared As Single. That is not a logic error: assigning the literal 10 to a
' Single cannot overflow on any correct implementation. Long assignment in the
' step before it worked.
'
' So this tests each numeric type in isolation, each in its own trap, and reports
' every result rather than stopping at the first failure. If Single is broken here
' and Double is not, the engine should not be using Single -- and this says so
' with evidence rather than assumption.
'-----------------------------------------------------------------------------
Public Sub TypeCheck()
    mRpt = ""
    Emit "TypeCheck -- numeric types on this build"
    Emit "========================================"
    Emit ""

    Emit TryLong()
    Emit TryInteger()
    Emit TrySingle()
    Emit TrySingleViaCSng()
    Emit TryDouble()
    Emit TryCurrency()
    Emit TryVariant()
    Emit TrySingleArray()
    Emit TryDoubleArray()
    Emit TrySingleArithmetic()
    Emit TryDoubleArithmetic()

    Emit ""
    Emit "Send this whole report back."

    Debug.Print mRpt
    MsgBox mRpt, vbInformation, "LingTeX-Word type check"
End Sub

Private Function TryLong() As String
    Dim v As Long
    On Error GoTo E
    v = 10
    TryLong = "  Long             ok    (" & CStr(v) & ")"
    Exit Function
E:
    TryLong = "  Long             FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryInteger() As String
    Dim v As Integer
    On Error GoTo E
    v = 10
    TryInteger = "  Integer          ok    (" & CStr(v) & ")"
    Exit Function
E:
    TryInteger = "  Integer          FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TrySingle() As String
    Dim v As Single
    On Error GoTo E
    v = 10
    TrySingle = "  Single           ok    (" & CStr(v) & ")"
    Exit Function
E:
    TrySingle = "  Single           FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TrySingleViaCSng() As String
    Dim v As Single
    On Error GoTo E
    v = CSng(10)
    TrySingleViaCSng = "  Single via CSng  ok    (" & CStr(v) & ")"
    Exit Function
E:
    TrySingleViaCSng = "  Single via CSng  FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryDouble() As String
    Dim v As Double
    On Error GoTo E
    v = 10
    TryDouble = "  Double           ok    (" & CStr(v) & ")"
    Exit Function
E:
    TryDouble = "  Double           FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryCurrency() As String
    Dim v As Currency
    On Error GoTo E
    v = 10
    TryCurrency = "  Currency         ok    (" & CStr(v) & ")"
    Exit Function
E:
    TryCurrency = "  Currency         FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryVariant() As String
    Dim v As Variant
    On Error GoTo E
    v = 10
    TryVariant = "  Variant          ok    (" & CStr(v) & ")"
    Exit Function
E:
    TryVariant = "  Variant          FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TrySingleArray() As String
    Dim v(0 To 2) As Single
    On Error GoTo E
    v(0) = 10
    TrySingleArray = "  Single array     ok    (" & CStr(v(0)) & ")"
    Exit Function
E:
    TrySingleArray = "  Single array     FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryDoubleArray() As String
    Dim v(0 To 2) As Double
    On Error GoTo E
    v(0) = 10
    TryDoubleArray = "  Double array     ok    (" & CStr(v(0)) & ")"
    Exit Function
E:
    TryDoubleArray = "  Double array     FAIL  error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TrySingleArithmetic() As String
    Dim a As Single
    Dim b As Single
    On Error GoTo E
    a = 10
    b = 20
    a = a + b
    TrySingleArithmetic = "  Single arithmetic ok   (" & CStr(a) & ")"
    Exit Function
E:
    TrySingleArithmetic = "  Single arithmetic FAIL error " & CStr(Err.Number) & ": " & Err.Description
End Function

Private Function TryDoubleArithmetic() As String
    Dim a As Double
    Dim b As Double
    On Error GoTo E
    a = 10
    b = 20
    a = a + b
    TryDoubleArithmetic = "  Double arithmetic ok   (" & CStr(a) & ")"
    Exit Function
E:
    TryDoubleArithmetic = "  Double arithmetic FAIL error " & CStr(Err.Number) & ": " & Err.Description
End Function

'-----------------------------------------------------------------------------
' MicroDiagnose -- find which VBA primitive fails.
'
' DiagnoseWrap died on a line that merely assigns 10 to a Single array element,
' which cannot overflow. Two possibilities remain and this separates them: either
' the colon-separated statement form was mis-parsed (VBA reads a bare number
' before a colon as an old-style line-number label), or something more basic is
' wrong on this build.
'
' So: one statement per line, no colons anywhere, and a marker string set before
' each step so the handler can name the exact step rather than a range of them.
' It starts from the most trivial operation possible and works up.
'-----------------------------------------------------------------------------
Public Sub MicroDiagnose()
    Dim marker As String
    Dim s1 As Single
    Dim n1 As Long
    Dim fixedS(0 To 2) As Single
    Dim fixedB(0 To 2) As Boolean
    Dim dynS() As Single
    Dim dynB() As Boolean
    Dim starts() As Long

    mRpt = ""
    Emit "MicroDiagnose"
    Emit "============="

    On Error GoTo Crashed

    marker = "A  assign a Long variable"
    n1 = 10

    marker = "B  assign a Single variable"
    s1 = 10

    marker = "C  assign a Single variable from a Long"
    s1 = n1

    marker = "D  assign element 0 of a fixed Single array"
    fixedS(0) = 10

    marker = "E  assign elements 1 and 2"
    fixedS(1) = 10
    fixedS(2) = 10

    marker = "F  assign a fixed Boolean array"
    fixedB(0) = False
    fixedB(1) = False
    fixedB(2) = False

    marker = "G  ReDim a dynamic Single array and fill it"
    ReDim dynS(0 To 2)
    dynS(0) = 10
    dynS(1) = 10
    dynS(2) = 10

    marker = "H  ReDim a dynamic Boolean array and fill it"
    ReDim dynB(0 To 2)
    dynB(0) = False
    dynB(1) = False
    dynB(2) = False

    marker = "I  read UBound of the fixed arrays"
    Emit "   UBound(fixedS)=" & CStr(UBound(fixedS))
    Emit "   UBound(fixedB)=" & CStr(UBound(fixedB))

    marker = "J  call ComputeWrapLines with the FIXED arrays"
    starts = ComputeWrapLines(fixedS, fixedB, 30, 0, 0)

    marker = "K  read the result bounds"
    Emit "   LBound(starts)=" & CStr(LBound(starts))
    Emit "   UBound(starts)=" & CStr(UBound(starts))

    marker = "L  read element 0 of the result"
    Emit "   starts(0)=" & CStr(starts(0))

    marker = "M  call ComputeWrapLines with the DYNAMIC arrays"
    starts = ComputeWrapLines(dynS, dynB, 30, 0, 0)
    Emit "   UBound(starts)=" & CStr(UBound(starts))

    Emit ""
    Emit "ALL MICRO STEPS COMPLETED with no error."
    GoTo Done

Crashed:
    Emit ""
    Emit "CRASHED at step " & marker
    Emit "   run-time error " & CStr(Err.Number) & ": " & Err.Description
    Err.Clear

Done:
    Debug.Print mRpt
    MsgBox mRpt, vbInformation, "LingTeX-Word micro diagnostic"
End Sub

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

Private Sub TestWrapPlanner()
    Section "Wrap planner"

    Eq "exact fit stays on one line", _
       PlanStarts("10,10,10", "0,0,0", 30), "0"
    Eq "one column over the budget wraps", _
       PlanStarts("10,10,10", "0,0,0", 25), "0,2"
    Eq "three wrap lines", _
       PlanStarts("10,10,10,10,10,10", "0,0,0,0,0,0", 25), "0,2,4"
    Eq "an over-wide single column gets its own line and overflows", _
       PlanStarts("10,100,10", "0,0,0", 25), "0,1,2"
    Eq "widening pulls columns back up (same input, bigger budget)", _
       PlanStarts("10,10,10,10", "0,0,0,0", 100), "0"

    ' A leading-boundary column must never start a line, so the break moves back
    ' and "zomu" stays with "-xa".
    Eq "a wrap line never starts on a continuation column", _
       PlanStarts("10,10,10", "0,0,1", 25), "0,1"
    Eq "backing up is abandoned rather than emptying a line", _
       PlanStarts("10,10", "0,1", 15), "0,1"

    ' The same flags derived from real data rather than written by hand.
    Dim ex As IgtExample
    Dim flags() As Boolean
    ex = ModelFromText(Vector2Raw(), igtMorphemeAligned)
    flags = NoBreakFlags(ex)
    Ok "NoBreakFlags never flags the first column", (flags(0) = False)
    Ok "NoBreakFlags flags the enclitic columns of example 2", (CountTrue(flags) > 0)
End Sub

'-----------------------------------------------------------------------------
' Plan a wrap from comma-separated widths and flags, and render the resulting
' line starts as "0,2,4".
'
' Deliberately ONE function with ONE local array, rather than a Plan() that
' returns an array and a Starts() that takes one. VBA is awkward about arrays
' crossing function boundaries -- a function's array return cannot be passed
' straight into an array parameter, because that parameter is ByRef and a result
' has nothing to refer to -- and every boundary is somewhere for that to go
' wrong at RUN time rather than compile time. The only array here is local, and
' the only call out is to ComputeWrapLines itself, which is the thing under test.
'
' Val() rather than CSng(): Val always reads "." as the decimal separator, while
' CSng follows the machine's locale. This is a tool for fieldwork linguists, who
' are not reliably on an English-locale machine.
'-----------------------------------------------------------------------------
Private Function PlanStarts(ByVal widthCsv As String, ByVal flagCsv As String, _
        ByVal avail As Single) As String

    Dim wParts() As String, fParts() As String
    Dim widths() As Single, flags() As Boolean
    Dim lineStarts() As Long
    Dim i As Long, s As String

    wParts = Split(widthCsv, ",")
    fParts = Split(flagCsv, ",")
    ReDim widths(0 To UBound(wParts))
    ReDim flags(0 To UBound(wParts))

    For i = 0 To UBound(wParts)
        widths(i) = CSng(Val(Trim$(wParts(i))))
        ' VBA's And does NOT short-circuit, so the bounds test has to be its own
        ' statement; as one condition, fParts(i) would still be evaluated.
        flags(i) = False
        If i <= UBound(fParts) Then flags(i) = (Trim$(fParts(i)) = "1")
    Next i

    lineStarts = ComputeWrapLines(widths, flags, avail, 0, 0)

    For i = LBound(lineStarts) To UBound(lineStarts)
        If s <> "" Then s = s & ","
        s = s & CStr(lineStarts(i))
    Next i
    PlanStarts = s
End Function

Private Function CountTrue(flags() As Boolean) As Long
    Dim i As Long, n As Long
    For i = LBound(flags) To UBound(flags)
        If flags(i) Then n = n + 1
    Next i
    CountTrue = n
End Function
