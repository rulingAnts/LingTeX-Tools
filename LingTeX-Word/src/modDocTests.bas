Attribute VB_Name = "modDocTests"
Option Explicit

'=============================================================================
' modDocTests  --  LingTeX-Word
'
' THE STAGE 2 GATE.  Run RunDocTests from the Immediate window (Ctrl+G):
'
'     RunDocTests
'
' Where modTests proves the ALGORITHMS, this proves the DOCUMENT WORK: that
' Word's object model behaves the way modStyles, modSettings, modMeasure,
' modRender, modReadBack and modLingTeX assume it does.  Every check here is a
' comparison, not something a person has to look at and judge.
'
' ---------------------------------------------------------------------------
' WHY THIS EXISTS RATHER THAN A CHECKLIST
'
' Almost every way the document layer can be wrong produces a WRONG LAYOUT
' SILENTLY rather than an error.  A failed font assignment, a style that was
' skipped, a measurement that returned zeros -- none of them raise, and all of
' them look exactly like "the wrap algorithm is broken", which is the one part of
' this project that is already proven.  Eyeballing a rendered example cannot tell
' those apart.  Arithmetic can.
'
' The assertions that earn their keep most are in the measurement section:
' strict monotonicity (which makes every silent-zero failure visible at once) and
' render/measure agreement (which is the only thing standing between this design
' and columns that are quietly the wrong width).
' ---------------------------------------------------------------------------
'
' WHAT IT DOES TO YOUR DOCUMENTS:  nothing.  Every test works in blank documents
' it creates and closes without saving.  It leaves the count of open documents
' where it found it, and asserts that it has.
'
' Safe to re-run.  Nothing is written to disk.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

Private mPass As Long
Private mFail As Long
Private mRpt  As String
Private mFirstFails As String
Private mDocsAtStart As Long
' The full names of every document open when the run began, so a crashed
' section's cleanup can tell scratch from the user's own -- and from ThisDocument.
Private mOpenAtStart As Collection

' Set by RunDocTestsToFile: report to a file, no dialog. See modTests.
Private mQuietRun As Boolean


'=============================================================================
' -- RUNNER -----------------------------------------------------------------
'=============================================================================

' The same suite, for a script: report to <document folder>/LingTeX-Word-reports/
' RunDocTests.txt, no dialog, no report document.
Public Sub RunDocTestsToFile()
    mQuietRun = True
    RunDocTests
    mQuietRun = False
End Sub

Public Sub RunDocTests()
    mPass = 0
    mFail = 0
    mRpt = ""
    mFirstFails = ""
    mDocsAtStart = Documents.Count
    RecordOpenDocuments

    Emit ""
    Emit "LingTeX-Word document tests"
    Emit "==========================="
    Emit "Open documents at start: " & CStr(mDocsAtStart)

    ' Each section behind its own error trap, so a run-time error reports which
    ' section died and the run CONTINUES. That is how stage 1's undiagnosed
    ' Overflow was finally cornered, and it is why no section is large.
    RunSection "styles"
    RunSection "stylecollide"
    RunSection "settings"
    RunSection "measure"
    RunSection "agreement"
    RunSection "rendering"
    RunSection "geometry"
    RunSection "scratch"
    RunSection "roundtrip"
    RunSection "commands"
    RunSection "events"

    ' Anything left open is a leak, and a leak is a finding.
    ReleaseScratch
    Ok "no documents leaked", (Documents.Count = mDocsAtStart)
    If Documents.Count <> mDocsAtStart Then
        Emit "         open now: " & CStr(Documents.Count) & _
             ", was " & CStr(mDocsAtStart)
    End If

    Emit ""
    If mFail = 0 Then
        Emit "ALL PASS -- " & CStr(mPass) & " passed"
    Else
        Emit "FAILURES -- " & CStr(mPass) & " passed, " & CStr(mFail) & " FAILED"
    End If

    DeliverResults
End Sub

Private Sub RunSection(ByVal which As String)
    On Error GoTo Crashed

    Emit ""
    Emit "-- " & which & " " & String$(IIf(Len(which) < 58, 58 - Len(which), 2), "-")

    Select Case which
        Case "styles":       TestStyles
        Case "stylecollide": TestStyleCollision
        Case "settings":     TestSettings
        Case "measure":      TestMeasure
        Case "agreement":    TestRenderMeasureAgreement
        Case "rendering":    TestRendering
        Case "geometry":     TestAvailableWidth
        Case "scratch":      TestScratchLifecycle
        Case "roundtrip":    TestRoundTrip
        Case "commands":     TestCommands
        Case "events":       TestEvents
        Case Else
            ' A section listed in RunDocTests with no arm here would otherwise run
            ' nothing at all and still report PASS for the whole suite -- silence
            ' that looks exactly like success. Caught here instead.
            mFail = mFail + 1
            Emit "  FAIL   section " & which & " has no arm in RunSection"
            NoteFailure "section " & which & " is not wired up"
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
    ' A crashed section may have left a document open. Clean up so the next
    ' section starts from a known state and the leak check stays meaningful.
    CloseAllScratchDocs
End Sub


'=============================================================================
' -- STYLES (modStyles) -----------------------------------------------------
'=============================================================================

Private Sub TestStyles()
    Dim doc As Document
    Dim before As Long, after As Long
    Dim errAfter As Long

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "styles: could create a blank document", False
        Exit Sub
    End If

    EnsureStyles doc, True
    ' Read Err IMMEDIATELY. EnsureTableStyle raises 4198 on Mac by design, and
    ' On Error GoTo 0 does not clear Err -- which is exactly how a successful
    ' re-wrap came to report "Re-wrapped 0 interlinear examples".
    errAfter = Err.Number
    Ok "EnsureStyles leaves Err.Number at 0", (errAfter = 0)
    If errAfter <> 0 Then Emit "         Err was " & CStr(errAfter)

    Ok "no style-name collision reported on a blank document", (gStyleError = "")

    CheckParaStyle doc, ROLE_VERNACULAR, 0
    CheckParaStyle doc, ROLE_MORPHEMES, 0
    CheckParaStyle doc, ROLE_GLOSS, 0
    CheckParaStyle doc, ROLE_WORDGLOSS, 0
    CheckParaStyle doc, ROLE_CATEGORY, 0
    CheckParaStyle doc, ROLE_FREE, 3

    Ok STYLE_GRAM & " exists as a CHARACTER style", _
        StyleExistsOfType(doc, STYLE_GRAM, wdStyleTypeCharacter)
    Ok STYLE_TABLE & " exists as a TABLE style", _
        StyleExistsOfType(doc, STYLE_TABLE, wdStyleTypeTable)
    Ok STYLE_GRAM & " has SmallCaps on", GramStyleIsSmallCaps(doc)

    ' Idempotent: a second run must add nothing.
    before = doc.Styles.Count
    EnsureStyles doc, True
    after = doc.Styles.Count
    Ok "EnsureStyles twice adds no styles", (before = after)
    If before <> after Then
        Emit "         " & CStr(before) & " styles before, " & CStr(after) & " after"
    End If

    Ok "EnsureStyles does not clobber a tuned style", NonClobberHolds(doc)

    CheckRoleRoundTrip
    Ok "BodyFontName is usable", BodyFontNameIsUsable(doc)
    Ok "BodyFontSize is plausible", _
        (BodyFontSize(doc) >= 4 And BodyFontSize(doc) <= 96)

    CloseNoSave doc
End Sub

' One paragraph style: present, right kind, right spacing, tight formatting.
Private Sub CheckParaStyle(doc As Document, ByVal role As String, _
        ByVal wantSpaceAfter As Double)

    Dim nm As String
    Dim got As Double

    nm = ParaStyleName(role)
    If Not StyleExistsOfType(doc, nm, wdStyleTypeParagraph) Then
        Ok nm & " exists as a PARAGRAPH style", False
        Exit Sub
    End If
    Ok nm & " exists as a PARAGRAPH style", True

    got = -1
    On Error Resume Next
    got = doc.Styles(nm).ParagraphFormat.SpaceAfter
    Err.Clear
    On Error GoTo 0
    Ok nm & " SpaceAfter = " & CStr(wantSpaceAfter), (got = wantSpaceAfter)
    If got <> wantSpaceAfter Then Emit "         got " & CStr(got)
End Sub

Private Function GramStyleIsSmallCaps(doc As Document) As Boolean
    On Error Resume Next
    GramStyleIsSmallCaps = (doc.Styles(STYLE_GRAM).Font.SmallCaps = True)
    Err.Clear
    On Error GoTo 0
End Function

' A user who has set their gloss font keeps it.
Private Function NonClobberHolds(doc As Document) As Boolean
    Dim nm As String
    Dim got As Double

    nm = ParaStyleName(ROLE_GLOSS)
    On Error Resume Next
    doc.Styles(nm).Font.Size = 19
    Err.Clear
    On Error GoTo 0

    EnsureStyles doc, True

    got = 0
    On Error Resume Next
    got = doc.Styles(nm).Font.Size
    Err.Clear
    On Error GoTo 0
    NonClobberHolds = (got = 19)
End Function

' The paragraph style of a row's first cell IS the tier role. That only works if
' the mapping inverts exactly.
Private Sub CheckRoleRoundTrip()
    Ok "role round trip: " & ROLE_VERNACULAR, _
        (RoleFromParaStyle(ParaStyleName(ROLE_VERNACULAR)) = ROLE_VERNACULAR)
    Ok "role round trip: " & ROLE_MORPHEMES, _
        (RoleFromParaStyle(ParaStyleName(ROLE_MORPHEMES)) = ROLE_MORPHEMES)
    Ok "role round trip: " & ROLE_GLOSS, _
        (RoleFromParaStyle(ParaStyleName(ROLE_GLOSS)) = ROLE_GLOSS)
    Ok "role round trip: " & ROLE_WORDGLOSS, _
        (RoleFromParaStyle(ParaStyleName(ROLE_WORDGLOSS)) = ROLE_WORDGLOSS)
    Ok "role round trip: " & ROLE_CATEGORY, _
        (RoleFromParaStyle(ParaStyleName(ROLE_CATEGORY)) = ROLE_CATEGORY)
    Ok "role round trip: " & ROLE_FREE, _
        (RoleFromParaStyle(ParaStyleName(ROLE_FREE)) = ROLE_FREE)

    ' The character style is not a tier, and neither is Normal.
    Ok "the gram-gloss character style is not a tier role", _
        (RoleFromParaStyle(STYLE_GRAM) = "")
    Ok "Normal is not a tier role", (RoleFromParaStyle("Normal") = "")
End Sub

' Theme fonts report as placeholders beginning with "+", which Word will not
' accept back as a font name.
Private Function BodyFontNameIsUsable(doc As Document) As Boolean
    Dim nm As String
    nm = BodyFontName(doc)
    BodyFontNameIsUsable = (nm <> "")
    If nm <> "" Then
        If Left$(nm, 1) = "+" Then BodyFontNameIsUsable = False
    End If
End Function


'=============================================================================
' -- STYLE NAME COLLISION ---------------------------------------------------
'=============================================================================

' A style of the right name and the WRONG KIND used to be silently accepted.
' EnsureParaStyle skipped creation, ApplyParaStyle failed without saying so,
' RowRole read "Normal", every role came back empty, and the whole wrapped table
' read back as one giant wrap line. The cause is three modules away from the
' symptom, which is why it gets a section to itself.
Private Sub TestStyleCollision()
    Dim doc As Document
    Dim nm As String
    Dim made As Boolean

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "collision: could create a blank document", False
        Exit Sub
    End If

    nm = ParaStyleName(ROLE_GLOSS)

    ' Plant a CHARACTER style where a paragraph style belongs.
    On Error Resume Next
    doc.Styles.Add Name:=nm, Type:=wdStyleTypeCharacter
    made = (Err.Number = 0)
    Err.Clear
    On Error GoTo 0

    If Not made Then
        Emit "  SKIP   could not plant a character style called " & nm
        CloseNoSave doc
        Exit Sub
    End If

    Ok "planted " & nm & " really is a character style", _
        StyleExistsOfType(doc, nm, wdStyleTypeCharacter)
    Ok "and is NOT seen as a paragraph style", _
        (Not StyleExistsOfType(doc, nm, wdStyleTypeParagraph))

    EnsureStyles doc, True
    Ok "EnsureStyles REPORTS the wrong-kind collision", (gStyleError <> "")
    If gStyleError <> "" Then Emit "         " & gStyleError

    ' And the renderer must refuse rather than draw role-less rows.
    Ok "a render into that document refuses", RenderRefusesOn(doc)

    CloseNoSave doc
End Sub

Private Function RenderRefusesOn(doc As Document) As Boolean
    Dim ex As IgtExample
    Dim tbl As Table

    ex = TwoTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    RenderRefusesOn = (tbl Is Nothing)
    If Not (tbl Is Nothing) Then
        Emit "         it drew a table anyway"
    ElseIf gRenderError <> "" Then
        Emit "         reason: " & gRenderError
    End If
End Function


'=============================================================================
' -- SETTINGS (modSettings) -------------------------------------------------
'=============================================================================

Private Sub TestSettings()
    Dim doc As Document

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "settings: could create a blank document", False
        Exit Sub
    End If

    '-- documented defaults on a virgin document --------------------------
    Ok "default Gap = 6", (SettingGap(doc) = 6)
    Ok "default LineGap = 6", (SettingLineGap(doc) = 6)
    Ok "default ContIndent = 0", (SettingContIndent(doc) = 0)
    Ok "default SpaceReplacement = .", (SettingSpaceReplacement(doc) = ".")
    Ok "default LowercaseGramGloss = True", (SettingLowercaseGramGloss(doc) = True)
    Ok "default RewrapOnSave = True", (SettingRewrapOnSave(doc) = True)
    Ok "default RewrapOnSelectionChange = False", _
        (SettingRewrapOnSelectionChange(doc) = False)
    Ok "default Granularity = word-aligned", _
        (SettingGranularity(doc) = igtWordAligned)

    '-- round trips, including a fractional Single --------------------------
    CheckSingleRoundTrip doc, "Gap"
    CheckSingleRoundTrip doc, "LineGap"
    CheckSingleRoundTrip doc, "ContIndent"

    SetSettingSpaceReplacement doc, "_"
    Ok "SpaceReplacement round trip", (SettingSpaceReplacement(doc) = "_")
    SetSettingSpaceReplacement doc, "x"
    Ok "SpaceReplacement rejects anything but . and _", _
        (SettingSpaceReplacement(doc) = ".")

    SetSettingLowercaseGramGloss doc, False
    Ok "LowercaseGramGloss round trip", (SettingLowercaseGramGloss(doc) = False)
    SetSettingLowercaseGramGloss doc, True

    SetSettingRewrapOnSave doc, False
    Ok "RewrapOnSave round trip", (SettingRewrapOnSave(doc) = False)
    SetSettingRewrapOnSave doc, True

    SetSettingRewrapOnSelectionChange doc, True
    Ok "RewrapOnSelectionChange round trip", _
        (SettingRewrapOnSelectionChange(doc) = True)
    SetSettingRewrapOnSelectionChange doc, False

    SetSettingGranularity doc, igtMorphemeAligned
    Ok "Granularity round trip", (SettingGranularity(doc) = igtMorphemeAligned)
    SetSettingGranularity doc, igtWordAligned

    '-- one variable per setting, however many times it is set --------------
    Ok "setting the same value twice adds no document variable", _
        VariableCountStable(doc)

    '-- clamping and bad input ---------------------------------------------
    Ok "a negative Gap clamps to 0 or the default", NegativeClamps(doc)
    Ok "a non-numeric Gap falls back to the default", NonNumericFallsBack(doc)

    '-- the setting is read from the TARGET document, not the active one ----
    Ok "LowercaseGramGloss reads the target document", _
        LowercaseReadsTarget(doc)

    CloseNoSave doc
End Sub

' 6.5 rather than 6, because a Single written with CStr and read with CSng is
' where a locale that writes "6,5" shows up.
Private Sub CheckSingleRoundTrip(doc As Document, ByVal which As String)
    Dim got As Double

    Select Case which
        Case "Gap"
            SetSettingGap doc, 6.5
            got = SettingGap(doc)
        Case "LineGap"
            SetSettingLineGap doc, 6.5
            got = SettingLineGap(doc)
        Case "ContIndent"
            SetSettingContIndent doc, 6.5
            got = SettingContIndent(doc)
    End Select

    Ok which & " round trips 6.5 exactly", (got = 6.5)
    If got <> 6.5 Then
        Emit "         got " & CStr(got) & _
             IIf(got = 65, "  (the decimal separator was dropped)", "")
    End If

    ' Put it back.
    Select Case which
        Case "Gap":        SetSettingGap doc, 6
        Case "LineGap":    SetSettingLineGap doc, 6
        Case "ContIndent": SetSettingContIndent doc, 0
    End Select
End Sub

Private Function VariableCountStable(doc As Document) As Boolean
    Dim before As Long
    SetSettingGap doc, 8
    before = doc.Variables.Count
    SetSettingGap doc, 8
    SetSettingGap doc, 8
    VariableCountStable = (doc.Variables.Count = before)
    If Not VariableCountStable Then
        Emit "         " & CStr(before) & " variables, then " & _
             CStr(doc.Variables.Count)
    End If
    SetSettingGap doc, 6
End Function

Private Function NegativeClamps(doc As Document) As Boolean
    WriteRawVar doc, "LingTeX_Gap", "-5"
    NegativeClamps = (SettingGap(doc) >= 0)
    If Not NegativeClamps Then Emit "         got " & CStr(SettingGap(doc))
    SetSettingGap doc, 6
End Function

Private Function NonNumericFallsBack(doc As Document) As Boolean
    WriteRawVar doc, "LingTeX_Gap", "abc"
    NonNumericFallsBack = (SettingGap(doc) = 6)
    If Not NonNumericFallsBack Then Emit "         got " & CStr(SettingGap(doc))
    SetSettingGap doc, 6
End Function

' Two documents with opposite settings: reading must follow the document passed
' in, not whichever happens to be active.
Private Function LowercaseReadsTarget(target As Document) As Boolean
    Dim other As Document
    Dim got As Boolean

    SetSettingLowercaseGramGloss target, False

    Set other = NewBlankDoc()
    If other Is Nothing Then
        LowercaseReadsTarget = False
        Exit Function
    End If
    SetSettingLowercaseGramGloss other, True
    other.Activate

    got = SettingLowercaseGramGloss(target)
    LowercaseReadsTarget = (got = False)
    If got <> False Then
        Emit "         read the ACTIVE document instead of the target"
    End If

    CloseNoSave other
    SetSettingLowercaseGramGloss target, True
End Function

Private Sub WriteRawVar(doc As Document, ByVal nm As String, ByVal v As String)
    On Error Resume Next
    doc.Variables(nm).Value = v
    If Err.Number <> 0 Then
        Err.Clear
        doc.Variables.Add Name:=nm, Value:=v
    End If
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- MEASUREMENT (modMeasure) -----------------------------------------------
'=============================================================================

Private Sub TestMeasure()
    Dim doc As Document
    Dim tf As TierFont
    Dim w() As Double

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "measure: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache

    tf = ResolveTierFont(doc, ROLE_GLOSS)

    '-- THE assertion. Everything that silently returns zeros fails here. ---
    w = WidthsOf(Array("i", "iii", "WWW"), tf, ROLE_GLOSS, doc)
    Ok "widths are strictly increasing for i < iii < WWW", _
        (w(0) > 0 And w(1) > w(0) And w(2) > w(1))
    Emit "         i=" & CStr(w(0)) & "  iii=" & CStr(w(1)) & "  WWW=" & CStr(w(2))
    Ok "measurement reported no failure", (Not gMeasureFailed)
    If gMeasureFailed Then Emit "         " & gMeasureError

    '-- against the numbers the probe actually recorded ---------------------
    w = WidthsOf(Array("i", "WWWWW"), tf, ROLE_GLOSS, doc)
    Ok "width of i is in 1..12pt", (w(0) >= 1 And w(0) <= 12)
    Ok "width of WWWWW is in 20..90pt", (w(1) >= 20 And w(1) <= 90)
    Emit "         i=" & CStr(w(0)) & "  WWWWW=" & CStr(w(1)) & _
         "   (probe recorded 3.0 and 53.3 at 12pt)"

    '-- blanks are zero, and a zero is now only ever a blank ---------------
    w = WidthsOf(Array("", " ", "x"), tf, ROLE_GLOSS, doc)
    Ok "empty string measures 0", (w(0) = 0)
    Ok "a single space measures 0", (w(1) = 0)
    Ok "a letter measures more than 0", (w(2) > 0)

    '-- a batch must agree with the same strings measured one at a time ----
    Ok "a batch agrees with single measurements", BatchEqualsSingles(tf, doc)

    '-- the role is part of the identity, not just the font ----------------
    Ok "role is part of the cache identity", RoleAffectsWidth(doc)

    '-- a cache hit must not touch Word at all -----------------------------
    Ok "a cache hit opens no document", CacheHitIsFree(tf, doc)
    Ok "ClearCache really invalidates", ClearCacheWorks(tf, doc)

    '-- MeasureExample's ByRef contract ------------------------------------
    CheckMeasureExampleShape doc

    CloseNoSave doc
End Sub

' MeasureTexts takes a String array; Array() gives a Variant array.
Private Function WidthsOf(vals As Variant, tf As TierFont, _
        ByVal role As String, doc As Document) As Double()

    Dim texts() As String
    Dim i As Long

    ReDim texts(0 To UBound(vals))
    For i = 0 To UBound(vals)
        texts(i) = CStr(vals(i))
    Next i

    ClearMeasureFailure
    WidthsOf = MeasureTexts(texts, tf, role, doc)
End Function

' Measuring three strings in one pass puts three paragraphs in the scratch
' document and reads a position at the end of each. If the paragraph indexing is
' off by one, or the positions are relative to something other than the text
' boundary, this is where it shows -- because measuring each string alone cannot
' make either mistake.
Private Function BatchEqualsSingles(tf As TierFont, doc As Document) As Boolean
    Dim batch() As Double
    Dim one() As Double
    Dim a As Double, b As Double, c As Double

    ClearCache
    batch = WidthsOf(Array("i", "iii", "WWW"), tf, ROLE_GLOSS, doc)

    ClearCache
    one = WidthsOf(Array("i"), tf, ROLE_GLOSS, doc)
    a = one(0)
    ClearCache
    one = WidthsOf(Array("iii"), tf, ROLE_GLOSS, doc)
    b = one(0)
    ClearCache
    one = WidthsOf(Array("WWW"), tf, ROLE_GLOSS, doc)
    c = one(0)

    BatchEqualsSingles = (Abs(batch(0) - a) <= 0.5) And _
                         (Abs(batch(1) - b) <= 0.5) And _
                         (Abs(batch(2) - c) <= 0.5)
    If Not BatchEqualsSingles Then
        Emit "         batch " & CStr(batch(0)) & "/" & CStr(batch(1)) & "/" & _
             CStr(batch(2)) & " vs singles " & CStr(a) & "/" & CStr(b) & "/" & CStr(c)
    End If
End Function

' "PST" on a Gloss row is drawn as small capitals; on a Morphemes row it is drawn
' as typed. Same font, different width. With the role missing from the cache key
' the first measurement was served to both.
Private Function RoleAffectsWidth(doc As Document) As Boolean
    Dim tfG As TierFont, tfM As TierFont
    Dim wG() As Double, wM() As Double

    tfG = ResolveTierFont(doc, ROLE_GLOSS)
    tfM = ResolveTierFont(doc, ROLE_MORPHEMES)

    ' Force the two tiers to share a font, so only the role can tell them apart.
    tfM.Italic = tfG.Italic
    tfM.Name = tfG.Name
    tfM.Size = tfG.Size

    ClearCache
    wG = WidthsOf(Array("PST"), tfG, ROLE_GLOSS, doc)
    wM = WidthsOf(Array("PST"), tfM, ROLE_MORPHEMES, doc)

    RoleAffectsWidth = (wG(0) <> wM(0))
    Emit "         PST as a gloss " & CStr(wG(0)) & _
         ", as a morpheme " & CStr(wM(0))
    If wG(0) = wM(0) Then
        Emit "         (equal means the role is not in the cache key, OR that"
        Emit "          small caps made no difference to this font's width)"
    End If
End Function

Private Function CacheHitIsFree(tf As TierFont, doc As Document) As Boolean
    Dim n As Long
    Dim w() As Double

    ClearCache
    w = WidthsOf(Array("cachecheck"), tf, ROLE_GLOSS, doc)
    ReleaseScratch
    n = Documents.Count

    w = WidthsOf(Array("cachecheck"), tf, ROLE_GLOSS, doc)
    CacheHitIsFree = (Documents.Count = n)
    If Not CacheHitIsFree Then
        Emit "         document count went " & CStr(n) & " -> " & _
             CStr(Documents.Count)
    End If
End Function

Private Function ClearCacheWorks(tf As TierFont, doc As Document) As Boolean
    Dim first() As Double, again() As Double

    ClearCache
    first = WidthsOf(Array("clearcheck"), tf, ROLE_GLOSS, doc)
    ClearCache
    again = WidthsOf(Array("clearcheck"), tf, ROLE_GLOSS, doc)

    ' Re-measured from scratch, and must land on the same answer.
    ClearCacheWorks = (Abs(first(0) - again(0)) <= 0.5) And (first(0) > 0)
    If Not ClearCacheWorks Then
        Emit "         " & CStr(first(0)) & " then " & CStr(again(0))
    End If
End Function

' widths() is a ByRef contract: a caller handed an unallocated array raises
' error 9 on its first subscript, which is a confusing way to learn the example
' was empty.
Private Sub CheckMeasureExampleShape(doc As Document)
    Dim ex As IgtExample
    Dim widths() As Double
    Dim okShape As Boolean
    Dim freeIdx As Long, c As Long
    Dim allZero As Boolean

    ex = ThreeTierExample()
    MeasureExample ex, doc, widths

    okShape = False
    On Error Resume Next
    okShape = (UBound(widths, 1) = ex.TierCount - 1) And _
              (UBound(widths, 2) = ex.ColCount - 1)
    Err.Clear
    On Error GoTo 0
    Ok "MeasureExample sizes widths() to the example", okShape

    ' The free tier is laid out as paragraphs under the table, never as columns.
    freeIdx = -1
    For c = 0 To ex.TierCount - 1
        If ex.Tiers(c) = ROLE_FREE Then freeIdx = c
    Next c
    If freeIdx >= 0 Then
        allZero = True
        For c = 0 To ex.ColCount - 1
            If widths(freeIdx, c) <> 0 Then allZero = False
        Next c
        Ok "the free tier measures 0 in every column", allZero
    End If

    ' The degenerate case must still leave widths() allocated.
    ex = NewExample(0, 0)
    MeasureExample ex, doc, widths
    okShape = False
    On Error Resume Next
    okShape = (UBound(widths, 1) >= 0)
    Err.Clear
    On Error GoTo 0
    Ok "an empty example still leaves widths() allocated", okShape
End Sub


'=============================================================================
' -- RENDER / MEASURE AGREEMENT ---------------------------------------------
'=============================================================================

' THE MOST VALUABLE TEST IN THE FILE.
'
' Measurement and drawing are two separate code paths that must produce the same
' glyphs. They did not: measurement inserted the model text "ERG" and turned small
' caps on, but Word's small caps only affects LOWERCASE letters, so it measured
' full-size capitals -- while the renderer wrote "erg" and let the style draw true
' small capitals, which are narrower. Every grammatical gloss was over-measured,
' every column came out too wide, every example wrapped earlier than it needed to,
' and nothing reported a problem.
'
' Nothing in the design catches that. Only this comparison does.
Private Sub TestRenderMeasureAgreement()
    Dim doc As Document

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "agreement: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache

    CheckAgreementFor doc, "ERG", ROLE_GLOSS
    CheckAgreementFor doc, "follow.CMP", ROLE_GLOSS
    CheckAgreementFor doc, "dream", ROLE_GLOSS
    CheckAgreementFor doc, "Ozivela", ROLE_VERNACULAR

    ' And the transform itself, which needs no document at all.
    CheckTransform doc

    CloseNoSave doc
End Sub

Private Sub CheckAgreementFor(doc As Document, ByVal text As String, _
        ByVal role As String)

    Dim tf As TierFont
    Dim measured() As Double
    Dim drawn As Double

    tf = ResolveTierFont(doc, role)
    ClearCache
    measured = WidthsOf(Array(text), tf, role, doc)
    drawn = DrawnWidthOf(doc, text, role)

    If drawn < 0 Then
        Emit "  SKIP   could not measure the drawn width of " & text
        Exit Sub
    End If

    Ok "measured width of " & text & " matches the drawn width", _
        (Abs(measured(0) - drawn) <= 1)
    Emit "         measured " & CStr(measured(0)) & ", drawn " & CStr(drawn)
End Sub

' Write the text the way the RENDERER writes it -- through WriteCellText, with the
' real character style -- then read where it ends. Returns -1 if that could not
' be done.
Private Function DrawnWidthOf(doc As Document, ByVal text As String, _
        ByVal role As String) As Double

    Dim para As Range
    Dim startX As Double, endX As Double

    DrawnWidthOf = -1

    On Error GoTo Failed
    doc.Content.Delete
    Set para = doc.Content
    ApplyParaStyle para, doc, role

    Set para = doc.Paragraphs(1).Range.Duplicate
    If para.End > para.Start Then para.MoveEnd wdCharacter, -1
    WriteCellText para, text, role, False, doc

    Set para = doc.Paragraphs(1).Range.Duplicate
    para.Collapse wdCollapseStart
    startX = para.Information(wdHorizontalPositionRelativeToTextBoundary)

    Set para = doc.Paragraphs(1).Range.Duplicate
    If para.End > para.Start Then para.MoveEnd wdCharacter, -1
    para.Collapse wdCollapseEnd
    endX = para.Information(wdHorizontalPositionRelativeToTextBoundary)

    DrawnWidthOf = endX - startX
    Exit Function

Failed:
    Err.Clear
End Function

' TransformedCellText is a pure string property. Its length invariant is what
' ApplyGramGlossRuns relies on to line its offsets up with the text in the range.
Private Sub CheckTransform(doc As Document)
    SetSettingLowercaseGramGloss doc, True

    Eq "transform: follow.CMP on a gloss row", _
        TransformedCellText("follow.CMP", ROLE_GLOSS, doc), "follow.cmp"
    Eq "transform: ERG on a gloss row", _
        TransformedCellText("ERG", ROLE_GLOSS, doc), "erg"
    Eq "transform: Ozivela on a vernacular row is untouched", _
        TransformedCellText("Ozivela", ROLE_VERNACULAR, doc), "Ozivela"
    Eq "transform: an all-caps vernacular word is untouched", _
        TransformedCellText("ERG", ROLE_VERNACULAR, doc), "ERG"

    Ok "transform preserves length (follow.CMP=REL)", _
        (Len(TransformedCellText("follow.CMP=REL", ROLE_GLOSS, doc)) = _
         Len("follow.CMP=REL"))

    ' With the setting off, the text is untouched but the runs are still marked.
    SetSettingLowercaseGramGloss doc, False
    Eq "transform: off means untouched", _
        TransformedCellText("follow.CMP", ROLE_GLOSS, doc), "follow.CMP"
    SetSettingLowercaseGramGloss doc, True
End Sub


'=============================================================================
' -- AVAILABLE WIDTH --------------------------------------------------------
'=============================================================================

Private Sub TestAvailableWidth()
    Dim doc As Document
    Dim w As Double

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "geometry: could create a blank document", False
        Exit Sub
    End If

    '-- Letter portrait, one-inch margins ---------------------------------
    SetPageGeometry doc, 612, 792, 72
    w = AvailableTextWidth(doc.Content)
    Ok "Letter portrait with 1in margins gives 468pt", (Abs(w - 468) <= 1)
    Emit "         got " & CStr(w)
    Ok "and it was computed, not a fallback", (Not gAvailWidthFellBack)

    '-- half-inch margins give 540, which the fallback cannot produce -----
    SetPageGeometry doc, 612, 792, 36
    w = AvailableTextWidth(doc.Content)
    Ok "half-inch margins give 540pt", (Abs(w - 540) <= 1)
    Emit "         got " & CStr(w) & "   (the 468 fallback cannot produce this)"

    '-- landscape is wider than portrait ---------------------------------
    Ok "landscape is wider than portrait", LandscapeIsWider(doc)

    '-- an indent comes straight off the budget --------------------------
    Ok "a 36pt left indent subtracts exactly 36", IndentSubtracts(doc)

    '-- and the floor holds on an absurd page ---------------------------
    SetPageGeometry doc, 90, 792, 36
    w = AvailableTextWidth(doc.Content)
    Ok "a 1.25in page still returns at least 36pt", (w >= 36)
    Emit "         got " & CStr(w)

    CloseNoSave doc
End Sub

Private Function LandscapeIsWider(doc As Document) As Boolean
    Dim portrait As Double, landscape As Double

    SetPageGeometry doc, 612, 792, 72
    portrait = AvailableTextWidth(doc.Content)
    SetPageGeometry doc, 792, 612, 72
    landscape = AvailableTextWidth(doc.Content)

    LandscapeIsWider = (landscape > portrait)
    If Not LandscapeIsWider Then
        Emit "         portrait " & CStr(portrait) & ", landscape " & CStr(landscape)
    End If
    SetPageGeometry doc, 612, 792, 72
End Function

Private Function IndentSubtracts(doc As Document) As Boolean
    Dim plain As Double, indented As Double

    SetPageGeometry doc, 612, 792, 72
    On Error Resume Next
    doc.Content.ParagraphFormat.LeftIndent = 0
    Err.Clear
    On Error GoTo 0
    plain = AvailableTextWidth(doc.Content)

    On Error Resume Next
    doc.Content.ParagraphFormat.LeftIndent = 36
    Err.Clear
    On Error GoTo 0
    indented = AvailableTextWidth(doc.Content)

    IndentSubtracts = (Abs((plain - indented) - 36) <= 1)
    If Not IndentSubtracts Then
        Emit "         " & CStr(plain) & " plain, " & CStr(indented) & " indented"
    End If

    On Error Resume Next
    doc.Content.ParagraphFormat.LeftIndent = 0
    Err.Clear
    On Error GoTo 0
End Function

Private Sub SetPageGeometry(doc As Document, ByVal wide As Double, _
        ByVal high As Double, ByVal margin As Double)

    On Error Resume Next
    With doc.PageSetup
        .PageWidth = wide
        .PageHeight = high
        .LeftMargin = margin
        .RightMargin = margin
        .Gutter = 0
        .TextColumns.SetCount NumColumns:=1
    End With
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- THE SCRATCH DOCUMENT ---------------------------------------------------
'=============================================================================

Private Sub TestScratchLifecycle()
    Dim doc As Document
    Dim tf As TierFont
    Dim w() As Double
    Dim n As Long

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "scratch: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    tf = ResolveTierFont(doc, ROLE_GLOSS)

    ReleaseScratch
    n = Documents.Count

    ' Two batches in a row must reuse one scratch document, not create two.
    ClearCache
    w = WidthsOf(Array("alpha"), tf, ROLE_GLOSS, doc)
    w = WidthsOf(Array("beta"), tf, ROLE_GLOSS, doc)
    Ok "two measuring batches create at most one document", _
        (Documents.Count <= n + 1)
    Emit "         " & CStr(n) & " open before, " & CStr(Documents.Count) & " after"

    ReleaseScratch
    Ok "ReleaseScratch puts the document count back", (Documents.Count = n)

    ' And calling it again must not raise.
    ReleaseScratch
    Ok "ReleaseScratch twice does not raise", True

    ' Measuring after a release must work again, not stay broken.
    ClearCache
    w = WidthsOf(Array("gamma"), tf, ROLE_GLOSS, doc)
    Ok "measuring works again after a release", (w(0) > 0)
    ReleaseScratch

    CloseNoSave doc
End Sub


'=============================================================================
' -- RENDERING (modRender) --------------------------------------------------
'=============================================================================

' Everything the drawn table must be true of, as arithmetic. "Each form sits
' directly above its gloss" and "nothing extends past the right margin" are the
' two things a person checks by looking; both are comparisons here.
Private Sub TestRendering()
    Dim doc As Document
    Dim ex As IgtExample
    Dim tbl As Table

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "rendering: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache

    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "an example can be drawn at all", False
        Emit "         " & gRenderError
        CloseNoSave doc
        Exit Sub
    End If
    Ok "an example can be drawn at all", True
    Ok "nothing was reported as drawn-but-not-as-planned", (gRenderError = "")
    If gRenderError <> "" Then Emit "         " & gRenderError

    CheckTableShape tbl, ex, doc
    CheckTableStyling tbl, doc
    CheckColumnAlignment tbl, ex
    CheckRowWidthsFit tbl, doc
    CheckRowRoles tbl, ex
    CheckSmallCapsRuns tbl
    CheckFreeParagraphs tbl, ex, doc

    CloseNoSave doc
End Sub

Private Sub CheckTableShape(tbl As Table, ex As IgtExample, doc As Document)
    Dim nInter As Long
    Dim interTiers() As Long
    Dim expectRows As Long

    nInter = InterlinearTierList(ex, interTiers)
    Ok "InterlinearTierList excludes the free tier", (nInter = ex.TierCount - 1)

    ' One row per interlinear tier per wrap line, and nothing else.
    Ok "rows are a whole number of tier groups", _
        (nInter > 0 And (tbl.Rows.Count Mod nInter) = 0)
    expectRows = tbl.Rows.Count
    Emit "         " & CStr(expectRows) & " rows, " & CStr(nInter) & _
         " tiers per wrap line, " & CStr(expectRows \ nInter) & " wrap line(s)"

    ' Ragged on purpose: a short wrap line is a row with FEWER cells, not a row
    ' with empty ones. Word has to support that, and the renderer has to achieve
    ' it -- the per-cell deletions used to be swallowed one at a time.
    Ok "the whole column count is recovered from the ragged rows", _
        (TableColumnCount(tbl) = ex.ColCount)
    If TableColumnCount(tbl) <> ex.ColCount Then
        Emit "         counted " & CStr(TableColumnCount(tbl)) & _
             ", the example has " & CStr(ex.ColCount)
    End If
End Sub

Private Sub CheckTableStyling(tbl As Table, doc As Document)
    Ok "the table carries the interlinear style (which IS the tag)", _
        TableStyleIs(tbl, STYLE_TABLE)
    Ok "autofit is off (explicit widths are the layout)", (tbl.AllowAutoFit = False)
    Ok "rows do not break across pages", _
        (tbl.Rows.AllowBreakAcrossPages = False)

    ' On Mac, setting borders on a table STYLE fails with 4198, so the per-table
    ' setting in StyleTable is the only thing making the example borderless.
    Ok "inside borders are off", _
        (tbl.Borders.InsideLineStyle = wdLineStyleNone)
    Ok "outside borders are off", _
        (tbl.Borders.OutsideLineStyle = wdLineStyleNone)

    ' Measurement happens in paragraphs, which have no cell padding. A drawn table
    ' keeping Word's default 5.4pt each side makes every cell ~10.8pt too narrow
    ' and wraps text inside it -- so a non-zero value FAILS rather than shrugs.
    Ok "left padding is 0", (tbl.LeftPadding = 0)
    Ok "right padding is 0", (tbl.RightPadding = 0)
    Ok "top padding is 0", (tbl.TopPadding = 0)
    Ok "bottom padding is 0", (tbl.BottomPadding = 0)
End Sub

Private Function TableStyleIs(tbl As Table, ByVal nm As String) As Boolean
    Dim got As String
    On Error Resume Next
    got = tbl.Style
    Err.Clear
    On Error GoTo 0
    TableStyleIs = (got = nm)
End Function

' THE ALIGNMENT INVARIANT. Within a wrap line, every tier row must report the same
' width for the same column -- that is what puts each form directly above its
' gloss, and it is the one thing the whole design rests on.
Private Sub CheckColumnAlignment(tbl As Table, ex As IgtExample)
    Dim nInter As Long
    Dim interTiers() As Long
    Dim nLines As Long
    Dim g As Long, i As Long, c As Long
    Dim firstRow As Long, cells As Long
    Dim w0 As Double, wi As Double
    Dim bad As String

    nInter = InterlinearTierList(ex, interTiers)
    If nInter < 2 Then Exit Sub
    nLines = tbl.Rows.Count \ nInter

    For g = 0 To nLines - 1
        firstRow = g * nInter + 1
        cells = tbl.Rows(firstRow).Cells.Count

        ' Every row of the group must hold the same number of cells, too.
        For i = 1 To nInter - 1
            If tbl.Rows(firstRow + i).Cells.Count <> cells Then
                bad = bad & " row " & CStr(firstRow + i) & " has " & _
                      CStr(tbl.Rows(firstRow + i).Cells.Count) & _
                      " cells, not " & CStr(cells) & ";"
            End If
        Next i

        For c = 1 To cells
            w0 = CellWidthOf(tbl, firstRow, c)
            For i = 1 To nInter - 1
                wi = CellWidthOf(tbl, firstRow + i, c)
                If Abs(wi - w0) > 0.5 Then
                    bad = bad & " line " & CStr(g + 1) & " column " & CStr(c) & _
                          ": " & CStr(w0) & " vs " & CStr(wi) & ";"
                End If
            Next i
        Next c
    Next g

    Ok "every form sits directly above its gloss (equal column widths)", (bad = "")
    If bad <> "" Then Emit "        " & bad
End Sub

' NOTHING EXTENDS PAST THE RIGHT MARGIN, as arithmetic rather than as a look.
Private Sub CheckRowWidthsFit(tbl As Table, doc As Document)
    Dim avail As Double
    Dim r As Long, c As Long
    Dim total As Double
    Dim worst As Double
    Dim bad As String

    ' From outside the table. doc.Content starts at position 0, inside the table
    ' just drawn there, and AvailableTextWidth inside a table answers with the
    ' cell's width -- which would have compared every row against a few points.
    avail = AvailableTextWidth(RangeAfterTable(tbl))

    For r = 1 To tbl.Rows.Count
        total = 0
        For c = 1 To tbl.Rows(r).Cells.Count
            total = total + CellWidthOf(tbl, r, c)
        Next c
        If total > worst Then worst = total
        If total > avail + 1 Then
            bad = bad & " row " & CStr(r) & " is " & CStr(total) & "pt;"
        End If
    Next r

    Ok "no row is wider than the text area", (bad = "")
    Emit "         widest row " & CStr(worst) & "pt, text area " & CStr(avail) & "pt"
    If bad <> "" Then Emit "        " & bad
End Sub

Private Function CellWidthOf(tbl As Table, ByVal r As Long, ByVal c As Long) As Double
    On Error Resume Next
    CellWidthOf = tbl.Cell(r, c).Width
    Err.Clear
    On Error GoTo 0
End Function

' The paragraph style of a row's first cell IS the tier role, and read-back depends
' on it. A row drawn without one reads back with no role at all, which collapses
' every wrap line into one.
Private Sub CheckRowRoles(tbl As Table, ex As IgtExample)
    Dim nInter As Long
    Dim interTiers() As Long
    Dim nLines As Long
    Dim g As Long, i As Long, r As Long
    Dim want As String, got As String
    Dim bad As String

    nInter = InterlinearTierList(ex, interTiers)
    If nInter = 0 Then Exit Sub
    nLines = tbl.Rows.Count \ nInter

    For g = 0 To nLines - 1
        For i = 0 To nInter - 1
            r = g * nInter + i + 1
            want = ParaStyleName(ex.Tiers(interTiers(i)))
            got = FirstCellParaStyle(tbl, r)
            If got <> want Then
                bad = bad & " row " & CStr(r) & ": " & got & " not " & want & ";"
            End If
        Next i
    Next g

    Ok "every row's first cell carries its tier's paragraph style", (bad = "")
    If bad <> "" Then Emit "        " & bad
End Sub

Private Function FirstCellParaStyle(tbl As Table, ByVal r As Long) As String
    On Error Resume Next
    FirstCellParaStyle = tbl.Cell(r, 1).Range.Paragraphs(1).Style
    Err.Clear
    On Error GoTo 0
End Function

' Small caps have to be applied to the GRAMMATICAL segments only, through the
' character style, so read-back can restore the capitals. "follow.CMP" is the case
' that matters: a lexical part and a grammatical part in one cell.
Private Sub CheckSmallCapsRuns(tbl As Table)
    Dim found As Boolean
    Dim r As Long, c As Long
    Dim txt As String

    ' The example's gloss cell is "follow.CMP=REL" -- word-aligned, so the
    ' grammatical parts share the cell with the lexical part and with each
    ' other. Drawn, it must read "follow.cmp=rel" with the gram-gloss style on
    ' exactly the two abbreviations: character 8 is the c of cmp, 12 the r of
    ' rel, 1 the f of follow. (An earlier version looked for a cell that was
    ' exactly "follow.cmp", found none, and skipped -- a silent pass.)
    For r = 1 To tbl.Rows.Count
        For c = 1 To tbl.Rows(r).Cells.Count
            txt = CleanText(CellTextOf(tbl, r, c))
            If Left$(txt, 10) = "follow.cmp" Then
                found = True
                Eq "follow.CMP=REL is drawn lower-cased for small caps", txt, "follow.cmp=rel"
                Ok "the lexical part carries no gram-gloss style", _
                    (Not CharHasGramStyle(tbl, r, c, 1))
                Ok "the first grammatical part carries the gram-gloss style", _
                    CharHasGramStyle(tbl, r, c, 8)
                Ok "the second grammatical part carries it too", _
                    CharHasGramStyle(tbl, r, c, 12)
            ElseIf txt = "vu=ve" Then
                ' A vernacular cell is drawn verbatim, with no run restyled, or an
                ' all-caps object-language word would be silently small-capped.
                Ok "a vernacular cell carries no gram-gloss style", _
                    (Not CharHasGramStyle(tbl, r, c, 1))
            End If
        Next c
    Next r

    Ok "the follow.CMP=REL cell was found to check its small-caps runs", found
End Sub

Private Function CellTextOf(tbl As Table, ByVal r As Long, ByVal c As Long) As String
    Dim rng As Range
    On Error Resume Next
    Set rng = tbl.Cell(r, c).Range
    If Not rng Is Nothing Then
        rng.End = rng.End - 1
        CellTextOf = rng.Text
    End If
    Err.Clear
    On Error GoTo 0
End Function

Private Function CharHasGramStyle(tbl As Table, ByVal r As Long, _
        ByVal c As Long, ByVal idx As Long) As Boolean

    Dim rng As Range
    Dim nm As String

    On Error Resume Next
    Set rng = tbl.Cell(r, c).Range
    If rng Is Nothing Then Exit Function
    rng.End = rng.End - 1
    nm = rng.Characters(idx).Style
    Err.Clear
    On Error GoTo 0
    CharHasGramStyle = (nm = STYLE_GRAM)
End Function

Private Function CleanText(ByVal s As String) As String
    s = Replace(s, Chr$(7), "")
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    CleanText = Trim$(s)
End Function

' The translation goes under the table, in quotes, with no stray empty paragraph on
' either side of it -- and kept with the table, so a page break cannot separate
' them.
Private Sub CheckFreeParagraphs(tbl As Table, ex As IgtExample, doc As Document)
    Dim para As Paragraph
    Dim n As Long
    Dim txt As String
    Dim guard As Long
    Dim allQuoted As Boolean
    Dim allStyled As Boolean

    If ex.FreeCount = 0 Then Exit Sub

    allQuoted = True
    allStyled = True
    Set para = ParagraphAfterTable(tbl)

    Do While Not para Is Nothing
        guard = guard + 1
        If guard > 16 Then Exit Do
        txt = CleanText(para.Range.Text)
        If txt = "" Then Exit Do
        If Not IsFreeParagraph(para) Then Exit Do
        n = n + 1
        If Left$(txt, 1) <> LeftSingleQuote Then allQuoted = False
        If Right$(txt, 1) <> RightSingleQuote Then allQuoted = False
        Set para = NextParagraph(para)
    Loop

    Ok "there is one styled paragraph per free translation", (n = ex.FreeCount)
    If n <> ex.FreeCount Then
        Emit "         found " & CStr(n) & ", expected " & CStr(ex.FreeCount)
    End If
    Ok "each translation is wrapped in single quotation marks", allQuoted

    ' The last row of the table must keep with the translation, or a page break can
    ' fall between an example and its own gloss of itself.
    Ok "the last table row keeps with the translation", _
        LastRowKeepsWithNext(tbl)

    ' StripQuotes is what read-back uses to take them off again, so the pair has to
    ' invert. A pure string property, checked directly.
    Eq "quotes round trip off a translation", _
        StripQuotes(LeftSingleQuote & "a fox followed her" & RightSingleQuote), _
        "a fox followed her"
    Eq "StripQuotes leaves unquoted text alone", _
        StripQuotes("a fox followed her"), "a fox followed her"
End Sub

Private Function LastRowKeepsWithNext(tbl As Table) As Boolean
    Dim v As Variant
    On Error Resume Next
    v = tbl.Rows(tbl.Rows.Count).Range.ParagraphFormat.KeepWithNext
    Err.Clear
    On Error GoTo 0
    LastRowKeepsWithNext = (v = True)
End Function


'=============================================================================
' -- ROUND TRIP (modRender + modReadBack) -----------------------------------
'=============================================================================

' THE THESIS OF THE DESIGN, AS A TEST.
'
' "The wrap planner recomputes from the full column list every time, rather than
' patching what is there" is the claim that makes pull-back-up work without a
' second code path: widen the margins and the columns come back up because the plan
' is recomputed, not diffed. Two properties establish it.
'
'   Round trip       Reading back a drawn example gives the model it was drawn
'                    from, field for field. If that holds, the document really is
'                    self-describing and no state is kept anywhere else.
'   Idempotence      Re-wrapping twice leaves the document byte-identical. If that
'                    holds, a re-wrap is a function of the model and the available
'                    width alone.
'
' Both are run at widths that force one, two and three wrap lines, because a bug in
' the ragged-row assembly only shows up once there is more than one group.
Private Sub TestRoundTrip()
    Dim doc As Document

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "round trip: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache

    ' Letter portrait: one wrap line for a short example.
    SetPageGeometry doc, 612, 792, 72
    CheckRoundTripAt doc, "wide page"

    ' Narrow enough to force wrapping.
    SetPageGeometry doc, 306, 792, 72
    CheckRoundTripAt doc, "narrow page"

    ' Narrower still.
    SetPageGeometry doc, 234, 792, 72
    CheckRoundTripAt doc, "very narrow page"

    SetPageGeometry doc, 612, 792, 72
    CheckIdempotence doc
    CheckPullBackUp doc
    CheckSmallCapsRestored doc
    CheckRestoreFastPathAgrees doc
    CheckEscapeHatch doc
    CheckReadBackIsReadOnly doc
    CheckDefaultRoles

    CloseNoSave doc
End Sub

' Draw, read back, compare every field.
Private Sub CheckRoundTripAt(doc As Document, ByVal what As String)
    Dim ex As IgtExample, back As IgtExample
    Dim tbl As Table
    Dim nLines As Long

    ex = ThreeTierExample()
    doc.Content.Delete
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "round trip (" & what & "): drawn", False
        Emit "         " & gRenderError
        Exit Sub
    End If

    nLines = tbl.Rows.Count \ 2          ' two interlinear tiers in the fixture
    back = ReadExampleFromTable(tbl)
    AbsorbFreeParagraphs back, tbl

    Emit "  ..     " & what & ": " & CStr(nLines) & " wrap line(s), " & _
         CStr(tbl.Rows.Count) & " rows"
    CompareExamples what, ex, back
End Sub

' Field for field, with the free tier accounted for: the free translations come back
' through AbsorbFreeParagraphs rather than as a tier of columns.
Private Sub CompareExamples(ByVal what As String, ex As IgtExample, back As IgtExample)
    Dim t As Long, c As Long
    Dim interIn As Long, interOut As Long
    Dim idxIn() As Long, idxOut() As Long
    Dim bad As String

    Eq "round trip (" & what & "): column count", _
        CStr(back.ColCount), CStr(ex.ColCount)

    interIn = InterlinearTierList(ex, idxIn)
    interOut = InterlinearTierList(back, idxOut)
    Eq "round trip (" & what & "): interlinear tier count", _
        CStr(interOut), CStr(interIn)

    If interOut <> interIn Or back.ColCount <> ex.ColCount Then Exit Sub

    For t = 0 To interIn - 1
        If back.Tiers(idxOut(t)) <> ex.Tiers(idxIn(t)) Then
            bad = bad & " tier " & CStr(t) & ": " & back.Tiers(idxOut(t)) & _
                  " not " & ex.Tiers(idxIn(t)) & ";"
        End If
        For c = 0 To ex.ColCount - 1
            If back.Cells(idxOut(t), c) <> ex.Cells(idxIn(t), c) Then
                bad = bad & " (" & CStr(t) & "," & CStr(c) & "): [" & _
                      back.Cells(idxOut(t), c) & "] not [" & _
                      ex.Cells(idxIn(t), c) & "];"
            End If
        Next c
    Next t

    Ok "round trip (" & what & "): every cell and tier comes back unchanged", _
        (bad = "")
    If bad <> "" Then Emit "        " & bad

    Eq "round trip (" & what & "): free translation count", _
        CStr(back.FreeCount), CStr(ex.FreeCount)
    If back.FreeCount = ex.FreeCount And ex.FreeCount > 0 Then
        Eq "round trip (" & what & "): the translation text", _
            back.FreeLines(0), ex.FreeLines(0)
    End If
End Sub

' Re-wrapping twice must leave the document byte-identical. This is what proves a
' re-wrap is a function of the model and the width, with nothing accumulating.
Private Sub CheckIdempotence(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim after1 As String, after2 As String, after3 As String

    ex = ThreeTierExample()
    doc.Content.Delete
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "idempotence: drawn", False
        Exit Sub
    End If

    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "idempotence: the first re-wrap worked", False
        Emit "         " & gRenderError
        Exit Sub
    End If
    after1 = doc.Content.Text

    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "idempotence: the second re-wrap worked", False
        Emit "         " & gRenderError
        Exit Sub
    End If
    after2 = doc.Content.Text

    Set tbl = RewrapTable(tbl)
    after3 = doc.Content.Text

    Ok "re-wrapping twice leaves the document identical", (after1 = after2)
    Ok "and a third time changes nothing either", (after2 = after3)
    If after1 <> after2 Then
        Emit "         length " & CStr(Len(after1)) & " then " & CStr(Len(after2))
    End If
End Sub

' PUSH DOWN, THEN PULL BACK UP. The round trip that needs no separate code path,
' because the plan is recomputed rather than patched.
Private Sub CheckPullBackUp(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim wide As Long, narrow As Long, backWide As Long

    ex = ThreeTierExample()
    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "pull back up: drawn", False
        Exit Sub
    End If
    wide = tbl.Rows.Count

    ' Narrow the page: columns must push down onto more rows.
    SetPageGeometry doc, 234, 792, 72
    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "pull back up: re-wrapped narrow", False
        Emit "         " & gRenderError
        Exit Sub
    End If
    narrow = tbl.Rows.Count

    ' Widen it again: they must come back up.
    SetPageGeometry doc, 612, 792, 72
    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "pull back up: re-wrapped wide again", False
        Emit "         " & gRenderError
        Exit Sub
    End If
    backWide = tbl.Rows.Count

    Ok "narrowing the page pushes columns down", (narrow > wide)
    Ok "widening it pulls them back up", (backWide = wide)
    Emit "         rows: " & CStr(wide) & " wide, " & CStr(narrow) & _
         " narrow, " & CStr(backWide) & " wide again"

    ' And the content survived both.
    CheckContentSurvived ex, tbl
End Sub

Private Sub CheckContentSurvived(ex As IgtExample, tbl As Table)
    Dim back As IgtExample
    back = ReadExampleFromTable(tbl)
    If back.TierCount > 0 Then AbsorbFreeParagraphs back, tbl
    CompareExamples "after push down and pull back up", ex, back
End Sub

' The lowercasing that small caps requires must be REVERSIBLE. "follow.CMP" is the
' case that matters: one cell, a lexical part and a grammatical part.
Private Sub CheckSmallCapsRestored(doc As Document)
    Dim ex As IgtExample, back As IgtExample
    Dim tbl As Table

    ex = TwoTierExample()
    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "small caps restored: drawn", False
        Exit Sub
    End If
    back = ReadExampleFromTable(tbl)
    If back.TierCount = 0 Then
        Ok "small caps restored: read back", False
        Exit Sub
    End If

    Eq "fox=ERG survives the small-caps round trip", back.Cells(1, 0), "fox=ERG"
    Eq "follow.CMP=REL survives it too (the mixed-run case)", _
        back.Cells(1, 1), "follow.CMP=REL"
    Eq "a lexical gloss is untouched", back.Cells(1, 2), "dream"
    Eq "and the vernacular row is untouched", back.Cells(0, 0), "vu=ve"
End Sub

' CellTextRestored has a fast path for a cell that is entirely one grammatical
' gloss, and a per-character path that is definitely right. The fast path reads a
' character style off a whole range, which the probe never covered -- so rather than
' trust it, assert the two agree on a real table.
Private Sub CheckRestoreFastPathAgrees(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim fast As String, slow As String
    Dim r As Long, c As Long
    Dim bad As String

    ex = TwoTierExample()
    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then Exit Sub

    For r = 1 To tbl.Rows.Count
        For c = 1 To tbl.Rows(r).Cells.Count
            gForceSlowRestore = False
            fast = CellTextRestored(tbl, r, c)
            gForceSlowRestore = True
            slow = CellTextRestored(tbl, r, c)
            gForceSlowRestore = False
            If fast <> slow Then
                bad = bad & " (" & CStr(r) & "," & CStr(c) & "): fast [" & fast & _
                      "] slow [" & slow & "];"
            End If
        Next c
    Next r

    Ok "the restore fast path agrees with the per-character path", (bad = "")
    If bad <> "" Then
        Emit "        " & bad
        Emit "        The per-character path is the correct one. If this fails,"
        Emit "        reading a character style off a whole range does not behave"
        Emit "        as assumed on this build, and the fast path must go."
    End If
End Sub

' Changing a table's style is the documented escape hatch: the add-in stops touching
' it. That has to actually work, or a user cannot opt a table out.
Private Sub CheckEscapeHatch(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim before As Long

    ex = TwoTierExample()
    doc.Content.Delete
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then Exit Sub

    Ok "a drawn table is recognised as interlinear", IsInterlinearTable(tbl)
    before = AllInterlinearTables(doc).Count

    ' "Normal Table" is a built-in name and may be localised, so the change is
    ' verified rather than assumed -- otherwise a failed assignment would look like a
    ' broken escape hatch.
    If Not ChangeTableStyle(tbl, doc) Then
        Emit "  SKIP   could not change the table's style to opt it out"
        Exit Sub
    End If

    Ok "changing the style opts the table out", (Not IsInterlinearTable(tbl))
    Ok "and it drops out of the document's list", _
        (AllInterlinearTables(doc).Count = before - 1)
    Ok "FindExampleAt no longer finds it", _
        (FindExampleAt(tbl.Range) Is Nothing)
End Sub

' Off the interlinear style, by whatever name the built-in table style has here.
' By NAME, not enum: wdStyleTableGrid is not defined in Mac Word's type library,
' and a constant that does not exist is a compile error that surfaces only when
' the procedure is first reached -- half-way through a run, as a dialog.
Private Function ChangeTableStyle(tbl As Table, doc As Document) As Boolean
    On Error Resume Next
    tbl.Style = doc.Styles("Table Grid")
    If Err.Number <> 0 Then
        Err.Clear
        tbl.Style = doc.Styles("Normal Table")
    End If
    Err.Clear
    On Error GoTo 0
    ChangeTableStyle = (Not TableStyleIs(tbl, STYLE_TABLE))
End Function

' The fallback roles for a table whose paragraph styles told us nothing. A pure
' function, and two separate properties that pull in different directions.
Private Sub CheckDefaultRoles()
    Dim i As Long, j As Long
    Dim dup As String

    ' 1. DISTINCT. All six indices used to collapse to ROLE_CATEGORY from three up,
    '    so a five-tier table recovered with two tiers sharing a role -- and
    '    therefore a paragraph style, losing the distinction permanently.
    For i = 0 To 5
        For j = i + 1 To 5
            If RoleOrDefault("", i) = RoleOrDefault("", j) Then
                dup = dup & " " & CStr(i) & "=" & CStr(j) & " both " & _
                      RoleOrDefault("", i) & ";"
            End If
        Next j
    Next i
    Ok "the six fallback roles are all different", (dup = "")
    If dup <> "" Then Emit "        " & dup

    ' 2. AND THE COMMON CASE STILL WORKS. A hand-built table is usually two rows,
    '    form over gloss, and only Gloss takes small capitals. Index 1 being
    '    ROLE_MORPHEMES would look reasonable and silently stop every converted
    '    two-row table drawing its grammatical glosses in small caps.
    Eq "fallback role 0 is Vernacular", RoleOrDefault("", 0), ROLE_VERNACULAR
    Eq "fallback role 1 is Gloss", RoleOrDefault("", 1), ROLE_GLOSS
    Ok "so a two-row table's second row takes small capitals", _
        TierTakesSmallCaps(RoleOrDefault("", 1))
    Ok "and its first row does not", _
        (Not TierTakesSmallCaps(RoleOrDefault("", 0)))

    ' 3. A real role is never overridden.
    Eq "a known role is passed through", _
        RoleOrDefault(ROLE_CATEGORY, 0), ROLE_CATEGORY
End Sub

' Reading must not change anything. A read that edits the document would make
' idempotence meaningless.
Private Sub CheckReadBackIsReadOnly(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim textBefore As String, endBefore As Long

    ex = ThreeTierExample()
    doc.Content.Delete
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then Exit Sub

    textBefore = doc.Content.Text
    endBefore = doc.Content.End

    ex = ReadExampleFromTable(tbl)
    AbsorbFreeParagraphs ex, tbl
    ex = ReadExampleFromTable(tbl)

    Ok "reading a table changes no text", (doc.Content.Text = textBefore)
    Ok "and moves nothing", (doc.Content.End = endBefore)
End Sub


'=============================================================================
' -- COMMANDS (modLingTeX) --------------------------------------------------
'=============================================================================

' Every command, on a success path AND a forced-failure path, must leave the world
' as it found it: gBusy clear, screen updating on, no scratch document leaked, no
' custom undo record open. Seven commands times two paths from one loop, which is
' TESTING.md's "after any command" checklist made mechanical.
'
' Possible at all only because every message now goes through Report: with MsgBox
' these would each block on a modal dialog.
Private Sub TestCommands()
    Dim doc As Document
    Dim savedQuiet As Boolean

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "commands: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    doc.Activate

    savedQuiet = gQuiet
    gQuiet = True
    gQuietAnswer = False

    Eq "LingTeXPing answers (so the project compiled)", _
        LingTeXPing(), "LingTeX-Word loaded"

    ' Cursor outside any example: every command must be a clean no-op.
    CheckCommandIsNoOp doc, "LingTeXRewrapCurrent"
    CheckCommandIsNoOp doc, "LingTeXSplitColumn"
    CheckCommandIsNoOp doc, "LingTeXMergeColumns"
    CheckCommandIsNoOp doc, "LingTeXCheckExample"
    CheckCommandIsNoOp doc, "LingTeXConvertTableToIgt"

    ' And on a document with no examples at all.
    CheckRewrapAllOnEmpty doc

    ' Then with a real example present.
    CheckRewrapAllCounts doc
    CheckSplitThenMerge doc
    CheckConvertPlainTable doc

    gQuiet = savedQuiet
    CloseNoSave doc
End Sub

' Run a command with the cursor in ordinary text. Nothing may change, and the state
' must be clean afterwards.
Private Sub CheckCommandIsNoOp(doc As Document, ByVal name As String)
    Dim before As String
    Dim tablesBefore As Long, docsBefore As Long

    doc.Content.Delete
    doc.Content.Text = "Just some ordinary prose." & vbCr
    doc.Range(0, 0).Select

    before = doc.Content.Text
    tablesBefore = doc.Tables.Count
    ReleaseScratch
    docsBefore = Documents.Count
    gLastMessage = ""

    RunCommandByName name

    Ok name & " outside an example changes no text", (doc.Content.Text = before)
    Ok name & " outside an example adds no table", _
        (doc.Tables.Count = tablesBefore)
    Ok name & " says something rather than nothing", (gLastMessage <> "")
    CheckStateIsClean name, docsBefore
End Sub

' gBusy clear, screen updating on, no leaked document, no open undo record.
Private Sub CheckStateIsClean(ByVal name As String, ByVal docsBefore As Long)
    Ok name & " leaves gBusy clear", (gBusy = False)
    Ok name & " leaves ScreenUpdating on", (Application.ScreenUpdating = True)
    ReleaseScratch
    Ok name & " leaks no document", (Documents.Count = docsBefore)
    Ok name & " leaves no undo record open", (Not UndoRecordIsOpen())
End Sub

' A custom undo record left open swallows everything the user does next into it.
Private Function UndoRecordIsOpen() As Boolean
    Dim ur As Object
    On Error Resume Next
    Set ur = Application.UndoRecord
    If ur Is Nothing Then
        Err.Clear
        On Error GoTo 0
        Exit Function               ' no UndoRecord on this build: nothing to leave open
    End If
    UndoRecordIsOpen = ur.IsRecordingCustomRecord
    Err.Clear
    On Error GoTo 0
End Function

Private Sub RunCommandByName(ByVal name As String)
    On Error Resume Next
    Select Case name
        Case "LingTeXRewrapCurrent":    LingTeXRewrapCurrent
        Case "LingTeXRewrapAll":        LingTeXRewrapAll
        Case "LingTeXSplitColumn":      LingTeXSplitColumn
        Case "LingTeXMergeColumns":     LingTeXMergeColumns
        Case "LingTeXCheckExample":     LingTeXCheckExample
        Case "LingTeXConvertTableToIgt": LingTeXConvertTableToIgt
        Case "LingTeXInsertInterlinear": LingTeXInsertInterlinear
    End Select
    Err.Clear
    On Error GoTo 0
End Sub

Private Sub CheckRewrapAllOnEmpty(doc As Document)
    Dim before As String
    Dim docsBefore As Long

    doc.Content.Delete
    doc.Content.Text = "No examples here." & vbCr
    before = doc.Content.Text
    ReleaseScratch
    docsBefore = Documents.Count
    gLastMessage = ""

    RunCommandByName "LingTeXRewrapAll"

    Ok "RewrapAll on a document with no examples changes nothing", _
        (doc.Content.Text = before)
    Ok "and says so", (InStr(gLastMessage, "no interlinear examples") > 0)
    If InStr(gLastMessage, "no interlinear examples") = 0 Then
        Emit "         said: " & gLastMessage
    End If
    CheckStateIsClean "LingTeXRewrapAll (empty)", docsBefore
End Sub

' The count must be what was actually re-wrapped. This reported 0 for a successful
' run, because it read Err.Number -- which EnsureTableStyle leaves set to 4198 on
' Mac by design, the first time an example is drawn in a fresh document.
Private Sub CheckRewrapAllCounts(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim docsBefore As Long

    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "RewrapAll count: an example could be drawn", False
        Exit Sub
    End If

    ReleaseScratch
    docsBefore = Documents.Count
    gLastMessage = ""
    RunCommandByName "LingTeXRewrapAll"

    Ok "RewrapAll reports re-wrapping 1 example, not 0", _
        (InStr(gLastMessage, "Re-wrapped 1 interlinear example") > 0)
    Emit "         said: " & gLastMessage
    CheckStateIsClean "LingTeXRewrapAll (one example)", docsBefore
End Sub

' Split then merge must be the identity. Split is how a user takes one aligned slot
' apart; merge is how they put it back, and a pair that does not invert loses text.
Private Sub CheckSplitThenMerge(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim before As String, afterSplit As String, afterMerge As String

    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    ex = TwoTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "split/merge: an example could be drawn", False
        Exit Sub
    End If
    before = TsvOfTable(tbl)

    ' Cell (1,1) holds vu=ve / fox=ERG, which has a break to split on.
    On Error Resume Next
    tbl.Cell(1, 1).Range.Select
    Err.Clear
    On Error GoTo 0

    gLastMessage = ""
    RunCommandByName "LingTeXSplitColumn"
    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Ok "split/merge: the example survived the split", False
        Emit "         said: " & gLastMessage
        Exit Sub
    End If
    afterSplit = TsvOfTable(tbl)

    Ok "splitting a column changes the model", (afterSplit <> before)
    Ok "and the split column count is one higher", _
        (TableColumnCount(tbl) = ex.ColCount + 1)

    ' Put it back.
    On Error Resume Next
    tbl.Cell(1, 1).Range.Select
    Err.Clear
    On Error GoTo 0

    gLastMessage = ""
    RunCommandByName "LingTeXMergeColumns"
    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Ok "split/merge: the example survived the merge", False
        Emit "         said: " & gLastMessage
        Exit Sub
    End If
    afterMerge = TsvOfTable(tbl)

    Eq "split then merge is the identity", afterMerge, before
End Sub

' A plain table typed by hand or pasted from a spreadsheet must be adoptable.
Private Sub CheckConvertPlainTable(doc As Document)
    Dim tbl As Table
    Dim back As IgtExample
    Dim docsBefore As Long

    doc.Content.Delete
    Set tbl = Nothing
    On Error Resume Next
    Set tbl = doc.Tables.Add(Range:=doc.Content, NumRows:=2, NumColumns:=3)
    Err.Clear
    On Error GoTo 0
    If tbl Is Nothing Then
        Emit "  SKIP   could not add a plain table to convert"
        Exit Sub
    End If

    SetPlainCell tbl, 1, 1, "vu=ve"
    SetPlainCell tbl, 1, 2, "levo=zi"
    SetPlainCell tbl, 1, 3, "zuvo"
    SetPlainCell tbl, 2, 1, "fox=ERG"
    SetPlainCell tbl, 2, 2, "follow.CMP=REL"
    SetPlainCell tbl, 2, 3, "dream"

    Ok "a plain table is not yet interlinear", (Not IsInterlinearTable(tbl))

    On Error Resume Next
    tbl.Cell(1, 1).Range.Select
    Err.Clear
    On Error GoTo 0

    ReleaseScratch
    docsBefore = Documents.Count
    gLastMessage = ""
    RunCommandByName "LingTeXConvertTableToIgt"

    Set tbl = FindExampleAt(Selection.Range)
    Ok "converting adopts the table as interlinear", (Not tbl Is Nothing)
    If tbl Is Nothing Then
        Emit "         said: " & gLastMessage
        Exit Sub
    End If

    back = ReadExampleFromTable(tbl)
    Eq "the converted table keeps its first cell", back.Cells(0, 0), "vu=ve"
    Eq "and its grammatical gloss, capitals and all", back.Cells(1, 0), "fox=ERG"
    CheckStateIsClean "LingTeXConvertTableToIgt", docsBefore
End Sub

' A table's model as tab-separated text, through a local rather than by passing a
' function's UDT return straight into a ByRef UDT parameter -- IgtExample carries
' three dynamic array members, and the array form of that pattern fails at RUN time
' in VBA rather than at compile time.
Private Function TsvOfTable(tbl As Table) As String
    Dim ex As IgtExample
    ex = ReadExampleFromTable(tbl)
    TsvOfTable = ModelToTsv(ex)
End Function

Private Sub SetPlainCell(tbl As Table, ByVal r As Long, ByVal c As Long, _
        ByVal v As String)
    Dim rng As Range
    On Error Resume Next
    Set rng = tbl.Cell(r, c).Range
    If Not rng Is Nothing Then
        rng.End = rng.End - 1
        rng.Text = v
    End If
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- EVENTS (clsAppEvents) --------------------------------------------------
'=============================================================================

' Whether the event handlers fire at all, and whether the re-entrancy guard holds.
' Neither can be established by reading the code: WithEvents on Word.Application is
' one of the things the probe never covered, and "gBusy prevents re-entry" is a
' claim about what Word does while our code is running.
Private Sub TestEvents()
    Dim ev As clsAppEvents
    Dim doc As Document
    Dim savedQuiet As Boolean

    ' New compiles only against a class module, so these two assertions are the
    ' definitive answer to "did the class modules come in as classes" -- the failure
    ' that is most likely of all, because importing a .cls is unreliable. They live
    ' here rather than in modImport, which is pasted alone into a bare project and so
    ' cannot name a class at all.
    Set ev = New clsAppEvents
    Ok "clsAppEvents really is a class module", (TypeName(ev) = "clsAppEvents")
    Ok "clsIgtWarning really is a class module too", WarningClassIsAClass()

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "events: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    doc.Activate

    savedQuiet = gQuiet
    gQuiet = True

    ev.Attach
    Ok "Attach resets the handler counter", (ev.mHandlerCount = 0)

    ' DocumentBeforeSave only fires on a real save, and this suite writes nothing to
    ' disk, so the save path stays a manual check -- see TESTING.md. What IS checked
    ' here is the part that can be: the class instantiates as a class, Attach and
    ' Detach work, and the re-entrancy guard holds.
    SetSettingRewrapOnSave doc, True
    Ok "rewrap-on-save reads back as on", (SettingRewrapOnSave(doc) = True)

    ' Re-entrancy: with gBusy set, a handler must do nothing at all.
    gBusy = True
    CheckHandlerRespectsBusy ev, doc
    gBusy = False

    ev.Detach
    Ok "Detach does not raise", True

    ' Twice in a row must be safe -- AutoExit can run more than once.
    ev.Detach
    Ok "Detach twice does not raise", True

    gQuiet = savedQuiet
    CloseNoSave doc
End Sub

Private Function WarningClassIsAClass() As Boolean
    Dim w As clsIgtWarning
    On Error Resume Next
    Set w = New clsIgtWarning
    Err.Clear
    On Error GoTo 0
    If w Is Nothing Then Exit Function
    WarningClassIsAClass = (TypeName(w) = "clsIgtWarning")
End Function

' The handler must not act while a command is in flight. Word has no
' Application.EnableEvents, so gBusy is the only thing preventing an edit made by a
' re-wrap from triggering another re-wrap.
Private Sub CheckHandlerRespectsBusy(ev As clsAppEvents, doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim textBefore As String
    Dim countBefore As Long

    gBusy = False
    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then Exit Sub

    ' Make the table stale, so a re-wrap WOULD change something if one happened.
    SetPageGeometry doc, 234, 792, 72

    gBusy = True
    countBefore = ev.mHandlerCount
    textBefore = doc.Content.Text

    ' Moving the cursor is what the selection handler watches.
    On Error Resume Next
    doc.Range(0, 0).Select
    Err.Clear
    On Error GoTo 0

    Ok "while busy, a cursor move re-wraps nothing", _
        (doc.Content.Text = textBefore)
    Ok "and the handler did no work", (ev.mHandlerCount = countBefore)

    gBusy = False
    SetPageGeometry doc, 612, 792, 72
End Sub


'=============================================================================
' -- FIXTURES ---------------------------------------------------------------
'=============================================================================

Private Function TwoTierExample() As IgtExample
    Dim ex As IgtExample
    ex = NewExample(2, 3)
    ex.Tiers(0) = ROLE_VERNACULAR
    ex.Tiers(1) = ROLE_GLOSS
    SetCell ex, 0, 0, "vu=ve"
    SetCell ex, 0, 1, "levo=zi"
    SetCell ex, 0, 2, "zuvo"
    SetCell ex, 1, 0, "fox=ERG"
    SetCell ex, 1, 1, "follow.CMP=REL"
    SetCell ex, 1, 2, "dream"
    TwoTierExample = ex
End Function

Private Function ThreeTierExample() As IgtExample
    Dim ex As IgtExample
    ex = NewExample(3, 3)
    ex.Tiers(0) = ROLE_VERNACULAR
    ex.Tiers(1) = ROLE_GLOSS
    ex.Tiers(2) = ROLE_FREE
    SetCell ex, 0, 0, "vu=ve"
    SetCell ex, 0, 1, "levo=zi"
    SetCell ex, 0, 2, "zuvo"
    SetCell ex, 1, 0, "fox=ERG"
    SetCell ex, 1, 1, "follow.CMP=REL"
    SetCell ex, 1, 2, "dream"
    AddFreeLine ex, "A fox followed her, is what I am talking about."
    ThreeTierExample = ex
End Function


'=============================================================================
' -- DOCUMENT HOUSEKEEPING --------------------------------------------------
'=============================================================================

' A blank document to test in. Visible, unlike the measuring scratch document,
' because a test that leaves one behind should be easy to notice.
Private Function NewBlankDoc() As Document
    Dim d As Document
    On Error Resume Next
    Set d = Documents.Add
    Err.Clear
    On Error GoTo 0
    If d Is Nothing Then Exit Function
    SetPageGeometry d, 612, 792, 72
    Set NewBlankDoc = d
End Function

Private Sub CloseNoSave(doc As Document)
    On Error Resume Next
    If Not doc Is Nothing Then doc.Close SaveChanges:=wdDoNotSaveChanges
    Err.Clear
    On Error GoTo 0
End Sub

' After a crashed section, shut anything extra that is open so the leak check at
' the end still means something. Never closes a document the user already had,
' and NEVER the document holding this code: on Mac Word, Documents(Documents.Count)
' is not the newest document, and closing ThisDocument from its own macro ends the
' run silently -- no report, no dialog, the rest of the suite simply never runs.
' That is how a styles-section crash became a suite that "wrote nothing".
Private Sub CloseAllScratchDocs()
    Dim i As Long
    Dim d As Document

    ReleaseScratch
    On Error Resume Next
    For i = Documents.Count To 1 Step -1
        If Documents.Count <= mDocsAtStart Then Exit For
        Set d = Documents(i)
        If Not d Is ThisDocument Then
            If Not WasOpenAtStart(d) Then
                d.Close SaveChanges:=wdDoNotSaveChanges
            End If
        End If
        Err.Clear
    Next i
    On Error GoTo 0
End Sub

Private Sub RecordOpenDocuments()
    Dim d As Document
    Set mOpenAtStart = New Collection
    On Error Resume Next
    For Each d In Documents
        mOpenAtStart.Add d.FullName
    Next d
    Err.Clear
    On Error GoTo 0
End Sub

Private Function WasOpenAtStart(d As Document) As Boolean
    Dim i As Long
    Dim nm As String

    If mOpenAtStart Is Nothing Then Exit Function
    On Error Resume Next
    nm = d.FullName
    Err.Clear
    On Error GoTo 0
    For i = 1 To mOpenAtStart.Count
        If mOpenAtStart(i) = nm Then
            WasOpenAtStart = True
            Exit Function
        End If
    Next i
End Function


'=============================================================================
' -- REPORTING --------------------------------------------------------------
'=============================================================================

Private Sub Emit(ByVal s As String)
    Debug.Print s
    SettleDebugPrint 0#   ' see modTests: Debug.Print arms an Overflow on Mac
    mRpt = mRpt & s & vbCr
End Sub

Private Sub Ok(ByVal name As String, ByVal cond As Boolean)
    If cond Then
        mPass = mPass + 1
        Emit "  PASS   " & name
    Else
        mFail = mFail + 1
        Emit "  FAIL   " & name
        NoteFailure name
    End If
End Sub

Private Sub Eq(ByVal name As String, ByVal actual As String, _
        ByVal expected As String)

    If actual = expected Then
        mPass = mPass + 1
        Emit "  PASS   " & name
    Else
        mFail = mFail + 1
        Emit "  FAIL   " & name
        Emit "         expected: " & expected
        Emit "         actual:   " & actual
        NoteFailure name
    End If
End Sub

Private Sub NoteFailure(ByVal name As String)
    If mFail > 8 Then Exit Sub
    If mFail = 8 Then
        mFirstFails = mFirstFails & "  ... see the report for the rest" & vbCr
    Else
        mFirstFails = mFirstFails & "  " & name & vbCr
    End If
End Sub

' Same delivery as modTests: a dialog always, because Debug.Print writes only to
' the Immediate window and a completed run with that window closed looks exactly
' like a macro that never ran.
Private Sub DeliverResults()
    Dim d As Document
    Dim placed As Boolean
    Dim msg As String

    If mQuietRun Then
        If WriteReportFile("RunDocTests.txt", mRpt) Then Exit Sub
    End If

    On Error Resume Next
    Set d = Documents.Add
    If Err.Number = 0 Then
        If Not d Is Nothing Then
            d.Content.Text = mRpt
            d.Content.Font.Name = "Courier New"
            d.Content.Font.Size = 9
            placed = True
        End If
    End If
    Err.Clear
    On Error GoTo 0

    If mFail = 0 Then
        msg = "ALL PASS -- " & CStr(mPass) & " document checks passed."
    Else
        msg = "FAILURES -- " & CStr(mPass) & " passed, " & CStr(mFail) & _
              " FAILED." & vbCr & vbCr & mFirstFails
    End If
    If placed Then
        msg = msg & vbCr & "The full report is in the new document."
    Else
        msg = msg & vbCr & "(Could not open a document for the report; " & _
              "see the Immediate window.)"
    End If

    MsgBox msg, IIf(mFail = 0, vbInformation, vbExclamation), _
           "LingTeX-Word document tests"
End Sub
