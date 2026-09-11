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


'=============================================================================
' -- RUNNER -----------------------------------------------------------------
'=============================================================================

Public Sub RunDocTests()
    mPass = 0
    mFail = 0
    mRpt = ""
    mFirstFails = ""
    mDocsAtStart = Documents.Count

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
    RunSection "geometry"
    RunSection "scratch"

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
        Case "geometry":     TestAvailableWidth
        Case "scratch":      TestScratchLifecycle
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
        ByVal wantSpaceAfter As Single)

    Dim nm As String
    Dim got As Single

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
    Dim got As Single

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
    Dim got As Single

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
    Dim w() As Single

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
        ByVal role As String, doc As Document) As Single()

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
    Dim batch() As Single
    Dim one() As Single
    Dim a As Single, b As Single, c As Single

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
    Dim wG() As Single, wM() As Single

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
    Dim w() As Single

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
    Dim first() As Single, again() As Single

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
    Dim widths() As Single
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
    Dim measured() As Single
    Dim drawn As Single

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
        ByVal role As String) As Single

    Dim para As Range
    Dim startX As Single, endX As Single

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
    Dim w As Single

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
    Dim portrait As Single, landscape As Single

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
    Dim plain As Single, indented As Single

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

Private Sub SetPageGeometry(doc As Document, ByVal wide As Single, _
        ByVal high As Single, ByVal margin As Single)

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
    Dim w() As Single
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
' the end still means something. Never closes a document the user already had.
Private Sub CloseAllScratchDocs()
    Dim guard As Long

    ReleaseScratch
    Do While Documents.Count > mDocsAtStart
        guard = guard + 1
        If guard > 32 Then Exit Do
        On Error Resume Next
        Documents(Documents.Count).Close SaveChanges:=wdDoNotSaveChanges
        If Err.Number <> 0 Then
            Err.Clear
            Exit Do
        End If
        On Error GoTo 0
    Loop
End Sub


'=============================================================================
' -- REPORTING --------------------------------------------------------------
'=============================================================================

Private Sub Emit(ByVal s As String)
    Debug.Print s
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
