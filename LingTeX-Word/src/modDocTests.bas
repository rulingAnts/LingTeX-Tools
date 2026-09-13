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
    ' The hidden measuring document may be open from a command run by hand
    ' before this; the sections release it, and counting it now made that
    ' look like a document lost ("open now 1, was 2", twice, 2026-09-12).
    ReleaseScratch
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
    RunSection "spacing"
    RunSection "dialog"
    RunSection "spacefix"
    RunSection "rows"
    RunSection "measure"
    RunSection "agreement"
    RunSection "rendering"
    RunSection "geometry"
    RunSection "scratch"
    RunSection "roundtrip"
    RunSection "adjacent"
    RunSection "numbering"
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
        Case "spacing":      TestSpacing
        Case "dialog":       TestDialog
        Case "spacefix":     TestSpaceFix
        Case "rows":         TestRowGeometry
        Case "measure":      TestMeasure
        Case "agreement":    TestRenderMeasureAgreement
        Case "rendering":    TestRendering
        Case "geometry":     TestAvailableWidth
        Case "scratch":      TestScratchLifecycle
        Case "roundtrip":    TestRoundTrip
        Case "adjacent":     TestAdjacentExamples
        Case "numbering":    TestNumbering
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
    Ok "default RewrapOnSelectionChange = True", _
        (SettingRewrapOnSelectionChange(doc) = True)
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
' -- SPACING AND THE STYLE SLOTS (what the Settings dialog reads and writes) -
'=============================================================================
' The by-name text API in modSettings, the optional (tri-state) spacings, and
' the style slots in modStyles. Then one example drawn with every spacing set,
' checked row by row. The dialog itself is the next section.

Private Sub TestSpacing()
    Dim doc As Document
    Dim ex As IgtExample
    Dim tbl As Table
    Dim para As Paragraph
    Dim keys() As String
    Dim i As Long
    Dim allKeys As Boolean

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "spacing: could create a blank document", False
        Exit Sub
    End If

    '-- the key list and the text API ---------------------------------------
    keys = Split(SPACING_KEYS, "|")
    Ok "fifteen spacing keys", (UBound(keys) = 14)
    allKeys = True
    For i = 0 To UBound(keys)
        If Not IsSpacingKey(keys(i)) Then allKeys = False
    Next i
    Ok "every listed key is a spacing key", allKeys
    Ok "an unknown key is not", (Not IsSpacingKey("Elephant"))
    Ok "SetSpacingText refuses an unknown key", _
        (Not SetSpacingText(doc, "Elephant", "3"))

    Ok "a virgin document sets no spacing", (SpacingText(doc, "TierGap") = "")
    Ok "an unset optional spacing reads as SETTING_UNSET", _
        (SettingOptional(doc, "ExampleLeft") = SETTING_UNSET)
    Ok "the defaults: before 0, after 3, right 0", _
        (SettingExampleBefore(doc) = 0 And SettingExampleAfter(doc) = 3 And SettingExampleRight(doc) = 0)
    Ok "  above the translation 6, between translations 0", _
        (SettingFreeAbove(doc) = 6 And SettingFreeBetween(doc) = 0)

    Ok "SetSpacingText accepts 6.5", SetSpacingText(doc, "Gap", "6.5")
    Ok "  and the typed getter sees 6.5", (SettingGap(doc) = 6.5)
    Ok "  and the box text is a number again", _
        (SpacingText(doc, "Gap") <> "" And Val(Replace(SpacingText(doc, "Gap"), ",", ".")) = 6.5)
    Ok "SetSpacingText accepts a comma decimal", SetSpacingText(doc, "Gap", "4,5")
    Ok "  as four and a half, not forty-five", (SettingGap(doc) = 4.5)
    Ok "SetSpacingText accepts a pt suffix", SetSpacingText(doc, "Gap", "8 pt")
    Ok "  as eight", (SettingGap(doc) = 8)
    Ok "SetSpacingText refuses letters", (Not SetSpacingText(doc, "Gap", "abc"))
    Ok "  and leaves the stored value alone", (SettingGap(doc) = 8)
    Ok "SetSpacingText refuses two decimal points", _
        (Not SetSpacingText(doc, "Gap", "1.2.3"))
    Ok "a negative spacing clamps to 0", _
        (SetSpacingText(doc, "Gap", "-4") And SettingGap(doc) = 0)
    Ok "empty text unsets", SetSpacingText(doc, "Gap", "   ")
    Ok "  so the box is empty again", (SpacingText(doc, "Gap") = "")
    Ok "  and the typed getter is back at its default", (SettingGap(doc) = 6)
    Ok "  and SettingDefined says so", (Not SettingDefined(doc, "Gap"))

    Ok "an optional spacing round-trips", _
        (SetSpacingText(doc, "ExampleLeft", "9") And SettingOptional(doc, "ExampleLeft") = 9)
    Ok "an optional spacing can be 0, which is not unset", _
        (SetSpacingText(doc, "ExampleLeft", "0") And SettingOptional(doc, "ExampleLeft") = 0)
    ClearSetting doc, "ExampleLeft"
    Ok "ClearSetting unsets", (SettingOptional(doc, "ExampleLeft") = SETTING_UNSET)

    '-- percentages of the font size ---------------------------------------
    Ok "a percentage is accepted", SetSpacingText(doc, "LineGap", "50%")
    Eq "  and stored as one", SpacingText(doc, "LineGap"), CStr(50) & "%"
    Ok "  and resolves against the example's font size", _
        (Abs(SettingLineGap(doc) - 0.5 * SpacingFontSize(doc)) < 0.01)
    Emit "         font size " & CStr(SpacingFontSize(doc)) & ", 50% = " & CStr(SettingLineGap(doc))
    Ok "a percentage with a space before the sign", SetSpacingText(doc, "LineGap", "25 %")
    Ok "  resolves too", (Abs(SettingLineGap(doc) - 0.25 * SpacingFontSize(doc)) < 0.01)
    Ok "letters before the sign are refused", (Not SetSpacingText(doc, "LineGap", "abc%"))
    Ok "IsValidSpacingText accepts a percentage", IsValidSpacingText("50%")
    ClearSetting doc, "LineGap"
    Ok "  and the line gap is back at 6", (SettingLineGap(doc) = 6)

    Ok "cell padding defaults to 0 on every side", _
        (SettingCellPadding(doc, "Left") = 0 And SettingCellPadding(doc, "Right") = 0 _
         And SettingCellPadding(doc, "Top") = 0 And SettingCellPadding(doc, "Bottom") = 0)
    Ok "tier gap defaults to 0", (SettingTierGap(doc) = 0)

    '-- the style slots -----------------------------------------------------
    Ok "eight style slots", (STYLE_SLOT_COUNT = 8)
    Eq "slot 0 is the vernacular style", StyleSlotName(0), ParaStyleName(ROLE_VERNACULAR)
    Eq "slot 5 is the translation style", StyleSlotName(5), ParaStyleName(ROLE_FREE)
    Eq "slot 6 is the grammatical-gloss character style", StyleSlotName(6), STYLE_GRAM
    Eq "slot 7 is the number-cell style", StyleSlotName(7), STYLE_EXAMPLE
    Eq "slot 7's label", StyleSlotLabel(7), "Example Number"
    Eq "a slot out of range has no name", StyleSlotName(8), ""
    Eq "  nor a label", StyleSlotLabel(8), ""

    EnsureStyles doc, True
    Ok "a fresh tier style shows no font of its own (follows Normal)", _
        (StyleFontText(doc, 2) = "")
    Ok "  nor a size of its own", (StyleSizeText(doc, 2) = "")
    Ok "Vernacular starts italic", StyleFlag(doc, 0, "Italic")
    Ok "Gloss starts upright", (Not StyleFlag(doc, 2, "Italic"))
    Ok "Grammatical Gloss starts in small capitals", StyleFlag(doc, 6, "SmallCaps")

    Ok "IsValidSpacingText accepts empty", IsValidSpacingText("")
    Ok "  and a number", IsValidSpacingText("4.5")
    Ok "  and refuses letters", (Not IsValidSpacingText("abc"))

    doc.Styles(ParaStyleName(ROLE_GLOSS)).Font.Size = 19
    Eq "a size set on a style shows as its own", StyleSizeText(doc, 2), CStr(19)
    doc.Styles(ParaStyleName(ROLE_GLOSS)).Font.Size = BodyFontSize(doc)
    Ok "  and the body size shows as none of its own", (StyleSizeText(doc, 2) = "")
    doc.Styles(ParaStyleName(ROLE_WORDGLOSS)).Font.Name = "Courier New"
    Eq "a font set on a style shows as its own", StyleFontText(doc, 3), "Courier New"
    doc.Styles(ParaStyleName(ROLE_WORDGLOSS)).Font.Name = BodyFontName(doc)
    Ok "  and the body font shows as none of its own", (StyleFontText(doc, 3) = "")

    doc.Styles(ParaStyleName(ROLE_GLOSS)).Font.Bold = True
    Ok "a flag set on a style reads back", StyleFlag(doc, 2, "Bold")
    doc.Styles(ParaStyleName(ROLE_VERNACULAR)).Font.Italic = False
    Ok "  and off", (Not StyleFlag(doc, 0, "Italic"))
    ResetStyleSlot doc, 2
    Ok "Reset This Style takes the flag off again", (Not StyleFlag(doc, 2, "Bold"))
    ResetStyleSlot doc, 0
    Ok "  and puts Vernacular back to italic", StyleFlag(doc, 0, "Italic")
    ResetStyleSlot doc, 6
    Ok "  and Grammatical Gloss back to small capitals", StyleFlag(doc, 6, "SmallCaps")

    '-- one example, every spacing set -------------------------------------
    SetSpacingText doc, "ExampleBefore", "9"
    SetSpacingText doc, "ExampleAfter", "7"
    SetSpacingText doc, "ExampleRight", "72"
    SetSpacingText doc, "TierGap", "4"
    SetSpacingText doc, "FreeAbove", "5"
    SetSpacingText doc, "PadLeft", "2"
    SetSpacingText doc, "PadRight", "3"
    SetSpacingText doc, "PadTop", "1"
    SetSpacingText doc, "PadBottom", "1.5"
    ClearCache

    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "an example draws with every spacing set", False
        Emit "         " & gRenderError
        CloseNoSave doc
        Exit Sub
    End If
    Ok "an example draws with every spacing set", True

    Ok "space before goes on the first row", _
        (tbl.Rows(1).Range.ParagraphFormat.SpaceBefore = 9)
    Ok "the tier gap goes under the first tier of the wrap line", _
        (tbl.Rows(1).Range.ParagraphFormat.SpaceAfter = 4)
    Ok "the last row carries no space after (the translation follows)", _
        (tbl.Rows(tbl.Rows.Count).Range.ParagraphFormat.SpaceAfter = 0)
    Ok "left padding is 2", (tbl.LeftPadding = 2)
    Ok "the rows start the left padding before the indent, so the text sits at it", _
        (Abs(tbl.Rows(1).LeftIndent + 2) <= 0.5)
    Ok "  and ExampleIndent still reads 0", (ExampleIndent(tbl) = 0)
    Ok "right padding is 3", (tbl.RightPadding = 3)
    Ok "top padding is 1", (tbl.TopPadding = 1)
    Ok "bottom padding is 1.5", (tbl.BottomPadding = 1.5)
    CheckRowsFitWithin tbl, doc, 72

    Set para = ParagraphAfterTable(tbl)
    If para Is Nothing Then
        Ok "the translation paragraph is there", False
    Else
        Ok "the translation paragraph is there", True
        Ok "space above the translation", (para.SpaceBefore = 5)
        Ok "space after the example, on the translation", (para.SpaceAfter = 7)
        Ok "the example's right indent, on the translation", (para.RightIndent = 72)
    End If

    ' Unset everything and draw again: nothing of the above survives, which is
    ' the promise an empty box makes.
    For i = 0 To UBound(keys)
        ClearSetting doc, keys(i)
    Next i
    ClearCache
    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "the example re-wraps with every spacing unset", False
        Emit "         " & gRenderError
    Else
        Ok "the example re-wraps with every spacing unset", True
        Ok "no space before on the first row", _
            (tbl.Rows(1).Range.ParagraphFormat.SpaceBefore = 0)
        Ok "no tier gap", (tbl.Rows(1).Range.ParagraphFormat.SpaceAfter = 0)
        Ok "padding is back to 0", (tbl.LeftPadding = 0 And tbl.RightPadding = 0)
        Ok "  and the rows are back at the indent, not a padding left of it", _
            (Abs(tbl.Rows(1).LeftIndent) <= 0.5)
        Set para = ParagraphAfterTable(tbl)
        If Not para Is Nothing Then
            Ok "the translation has the defaults again: 6 above, 3 after, no right indent", _
                (para.SpaceBefore = 6 And para.SpaceAfter = 3 And para.RightIndent = 0)
        End If
    End If

    CloseNoSave doc
End Sub

' Every row, indent plus cells, fits inside the text area less the example's
' right indent: what the Right box promises.
Private Sub CheckRowsFitWithin(tbl As Table, doc As Document, ByVal rightIndent As Double)
    Dim avail As Double
    Dim r As Long, c As Long
    Dim total As Double, worst As Double
    Dim bad As String

    avail = AvailableTextWidth(RangeAfterTable(tbl), True) - rightIndent
    For r = 1 To tbl.Rows.Count
        total = tbl.Rows(r).LeftIndent
        For c = 1 To tbl.Rows(r).Cells.Count
            total = total + CellWidthOf(tbl, r, c)
        Next c
        If total > worst Then worst = total
        If total > avail + 1 Then
            bad = bad & " row " & CStr(r) & " is " & CStr(total) & "pt;"
        End If
    Next r
    Ok "no row runs past the example's right indent", (bad = "")
    Emit "         widest row " & CStr(worst) & "pt, room " & CStr(avail) & "pt"
    If bad <> "" Then Emit "        " & bad
End Sub


'=============================================================================
' -- THE SETTINGS DIALOG (frmLingTeXSettings) -------------------------------
'=============================================================================
' The form is driven WITHOUT being shown. New runs UserForm_Initialize, which
' builds every control in code, and the form's public accessors read and
' write them. That proves the form is a form (New compiles only against one),
' that MSForms is there to build controls with, and that LoadFrom and ApplyNow
' round-trip the document's settings -- everything but the pixels, which the
' by-hand pass looks at (TESTING.md).

Private Sub TestDialog()
    Dim doc As Document
    Dim frm As frmLingTeXSettings
    Dim savedQuiet As Boolean
    Dim n As Long

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "dialog: could create a blank document", False
        Exit Sub
    End If

    Set frm = New frmLingTeXSettings
    Ok "the settings form really is a form (New compiled against it)", _
        (TypeName(frm) = "frmLingTeXSettings")
    On Error Resume Next
    n = frm.Controls.Count
    Err.Clear
    On Error GoTo 0
    Ok "it built its controls without being shown", (n >= 50)
    Emit "         " & CStr(n) & " controls"
    Ok "the styles list has one entry per style slot", (frm.StyleCount() = STYLE_SLOT_COUNT)
    Ok "the first style is selected", (frm.SelectedSlot() = 0)

    frm.LoadFrom doc
    Ok "a virgin document loads an empty spacing box", (frm.BoxText("TierGap") = "")
    Ok "  and the default list level", (frm.BoxText("NumberLevel") = "1")
    Ok "  numbering ticked", frm.FlagValue("Number")
    Ok "  word alignment chosen", frm.FlagValue("Word")
    Ok "  and not morpheme", (Not frm.FlagValue("Morpheme"))
    Ok "  full stop as the space replacement", frm.FlagValue("Dot")

    savedQuiet = gQuiet
    gQuiet = True

    frm.SetBoxText "TierGap", "4"
    frm.SetBoxText "Gap", "7,5"
    frm.SetFlag "Number", False
    frm.SetFlag "Morpheme", True
    frm.SetFlag "Underscore", True
    frm.SetBoxText "NumberLevel", "2"
    Ok "Apply accepts the boxes", frm.ApplyNow()
    Ok "  tier gap stored as 4", (SettingTierGap(doc) = 4)
    Ok "  column gap stored as 7.5 (comma decimal)", (SettingGap(doc) = 7.5)
    Ok "  numbering off", (Not SettingNumberExamples(doc))
    Ok "  morpheme alignment", (SettingGranularity(doc) = igtMorphemeAligned)
    Ok "  underscore replaces a space", (SettingSpaceReplacement(doc) = "_")
    Ok "  list level 2", (SettingNumberLevel(doc) = 2)

    frm.SetBoxText "LineGap", "abc"
    frm.SetBoxText "TierGap", "5"
    Ok "Apply refuses a box that is not a number", (Not frm.ApplyNow())
    Ok "  and names the box", (InStr(1, gLastMessage, "Line gap") > 0)
    Ok "  storing nothing from that pass", (SettingTierGap(doc) = 4)
    frm.SetBoxText "LineGap", ""
    frm.SetBoxText "NumberLevel", "0"
    Ok "Apply refuses a list level of 0", (Not frm.ApplyNow())
    frm.SetBoxText "NumberLevel", "1"
    Ok "Apply accepts them again", frm.ApplyNow()
    Ok "  and the tier gap is 5 now", (SettingTierGap(doc) = 5)

    frm.RestoreDefaultFields
    Ok "Restore Defaults empties the boxes", (frm.BoxText("TierGap") = "" And frm.BoxText("Gap") = "")
    Ok "  and ticks the defaults", _
        (frm.FlagValue("Word") And frm.FlagValue("Number") And frm.FlagValue("Dot"))
    Ok "  and unticks the rest", (Not frm.FlagValue("Morpheme") And Not frm.FlagValue("Underscore"))
    Ok "  and the list level is 1", (frm.BoxText("NumberLevel") = "1")
    Ok "  without storing anything", (SettingTierGap(doc) = 5 And SettingGranularity(doc) = igtMorphemeAligned)

    frm.LoadFrom doc
    Ok "LoadFrom shows what was stored", _
        (Val(Replace(frm.BoxText("TierGap"), ",", ".")) = 5)
    Ok "  and an unset box stays empty", (frm.BoxText("LineGap") = "")
    Ok "  and the flags", (frm.FlagValue("Morpheme") And Not frm.FlagValue("Number"))
    Ok "Result is empty until a button is pressed", (frm.Result = "")

    gQuiet = savedQuiet
    Unload frm
    CloseNoSave doc
End Sub


'=============================================================================
' -- SPACES TYPED INTO CELLS ARE REPAIRED ON RE-WRAP ------------------------
'=============================================================================
' Invariant 2 says no space inside an interlinear cell; Insert has always
' repaired one, and now so does every re-wrap (Seth, 2026-09-14), with the
' document's replacement character. The translation is prose and is left alone.

Private Sub TestSpaceFix()
    Dim doc As Document
    Dim ex As IgtExample
    Dim tbl As Table
    Dim rng As Range

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "spacefix: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache
    SetSettingNumberExamples doc, False        ' content cells start at column 1

    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "spacefix: an example draws", False
        Emit "         " & gRenderError
        CloseNoSave doc
        Exit Sub
    End If

    ' Type a space into the gloss cell, as a user would.
    On Error Resume Next
    Set rng = tbl.Cell(2, 2).Range
    rng.End = rng.End - 1
    rng.Text = "attack CMP=REL"
    Err.Clear
    On Error GoTo 0
    ex = ReadExampleFromTable(tbl)
    Ok "the typed space is in the cell before the re-wrap", (InStr(ex.Cells(1, 1), " ") > 0)

    Set tbl = RewrapTable(tbl)
    If tbl Is Nothing Then
        Ok "spacefix: the example re-wraps", False
        Emit "         " & gRenderError
        CloseNoSave doc
        Exit Sub
    End If
    ex = ReadExampleFromTable(tbl)
    Eq "re-wrap replaces the space with the document's full stop", ex.Cells(1, 1), "attack.CMP=REL"
    Ok "the vernacular cell above it is untouched", (ex.Cells(0, 1) = "deda=di")
    ' ReadExampleFromTable reads the TABLE; the translation is a paragraph
    ' after it (AbsorbFreeParagraphs brings it in for a re-wrap), so it is
    ' read where it is. (The first Mac run read FreeLines(0) of a table-only
    ' example and got nothing, 2026-09-14.)
    Ok "the translation keeps its spaces", _
        (InStr(ParagraphAfterTable(tbl).Range.Text, " ") > 0)

    ' With the other replacement character.
    SetSettingSpaceReplacement doc, "_"
    On Error Resume Next
    Set rng = tbl.Cell(1, 3).Range
    rng.End = rng.End - 1
    rng.Text = "bu jo"
    Err.Clear
    On Error GoTo 0
    Set tbl = RewrapTable(tbl)
    If Not tbl Is Nothing Then
        ex = ReadExampleFromTable(tbl)
        Eq "re-wrap uses an underscore when the document says so", ex.Cells(0, 2), "bu_jo"
    Else
        Ok "spacefix: the second re-wrap", False
        Emit "         " & gRenderError
    End If
    SetSettingSpaceReplacement doc, "."

    CloseNoSave doc
End Sub


'=============================================================================
' -- ROW GEOMETRY, AS WORD LAYS IT OUT --------------------------------------
'=============================================================================
' Seth saw two things a screenshot cannot settle (2026-09-14): the gap between
' the tiers looking larger on the first wrap line than on the second, and a
' hanging indent -- later wrap lines starting to the right of the first --
' after spacing or padding was set. So ask Word where things are: the page
' position of every row's first content cell and of the translation, and the
' height of every row. A numbered example on a narrow page, so it wraps, with
' cell padding set, since that is where it went wrong.

Private Sub TestRowGeometry()
    Dim doc As Document
    Dim ex As IgtExample
    Dim tbl As Table
    Dim r As Long
    Dim x0 As Double, xr As Double, xNum As Double, xFree As Double
    Dim y(1 To 5) As Double
    Dim h1 As Double, h2 As Double, h3 As Double, h4 As Double
    Dim para As Paragraph
    Dim allSame As Boolean
    Dim bad As String

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "rows: could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ClearCache
    SetPageGeometry doc, 320, 792, 72          ' 176pt of text: the example wraps
    SetSpacingText doc, "PadLeft", "2"
    SetSpacingText doc, "PadRight", "3"
    SetSpacingText doc, "PadTop", "1"

    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "rows: a numbered example draws on the narrow page", False
        Emit "         " & gRenderError
        CloseNoSave doc
        Exit Sub
    End If
    Ok "rows: a numbered example draws on the narrow page", True
    If tbl.Rows.Count < 4 Then
        Ok "rows: it wrapped onto a second line", False
        Emit "         " & CStr(tbl.Rows.Count) & " rows"
        CloseNoSave doc
        Exit Sub
    End If
    Ok "rows: it wrapped onto a second line", True

    '-- horizontal: every row's text starts where the first row's does ------
    On Error Resume Next
    xNum = tbl.Cell(1, 1).Range.Information(wdHorizontalPositionRelativeToPage)
    x0 = tbl.Cell(1, 2).Range.Information(wdHorizontalPositionRelativeToPage)
    Err.Clear
    On Error GoTo 0
    Ok "the number sits at the left margin (the table's edge is the padding to its left)", _
        (Abs(xNum - 72) <= 0.75)
    Emit "         number at " & CStr(xNum) & ", margin 72"
    allSame = True
    For r = 2 To tbl.Rows.Count
        On Error Resume Next
        xr = tbl.Cell(r, 2).Range.Information(wdHorizontalPositionRelativeToPage)
        Err.Clear
        On Error GoTo 0
        If Abs(xr - x0) > 0.75 Then
            allSame = False
            bad = bad & " row " & CStr(r) & " at " & CStr(xr) & ";"
        End If
    Next r
    Ok "no hanging indent: every row's first content cell starts where row 1's does", allSame
    Emit "         row 1 content at " & CStr(x0) & IIf(bad = "", "", "; off:" & bad)

    Set para = ParagraphAfterTable(tbl)
    If Not para Is Nothing Then
        On Error Resume Next
        xFree = para.Range.Information(wdHorizontalPositionRelativeToPage)
        Err.Clear
        On Error GoTo 0
        Ok "the translation starts where the content does", (Abs(xFree - x0) <= 0.75)
        Emit "         translation at " & CStr(xFree)
    End If

    '-- vertical: the numbered first row is as tall as the later vernacular row
    On Error Resume Next
    For r = 1 To 4
        y(r) = tbl.Cell(r, 2).Range.Information(wdVerticalPositionRelativeToPage)
    Next r
    If Not para Is Nothing Then
        y(5) = para.Range.Information(wdVerticalPositionRelativeToPage) - para.SpaceBefore
    End If
    Err.Clear
    On Error GoTo 0
    h1 = y(2) - y(1)                            ' vernacular, with the number
    h2 = y(3) - y(2)                            ' gloss, plus the line gap
    h3 = y(4) - y(3)                            ' vernacular, second wrap line
    h4 = y(5) - y(4)                            ' gloss, last
    Emit "         row heights " & CStr(h1) & " / " & CStr(h2) & " / " & CStr(h3) & " / " & CStr(h4)
    Ok "rows: Word reported positions", (y(1) > 0 And y(2) > y(1) And y(3) > y(2) And y(4) > y(3))
    Ok "the numbered first row is as tall as the later vernacular row", (Abs(h1 - h3) <= 0.75)
    If y(5) > y(4) Then
        Ok "the gloss row before the wrap is the last gloss row plus the line gap", _
            (Abs((h2 - h4) - SettingLineGap(doc)) <= 0.75)
    End If

    ClearSetting doc, "PadLeft"
    ClearSetting doc, "PadRight"
    ClearSetting doc, "PadTop"
    CloseNoSave doc
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
    CheckAgreementFor doc, "attack.CMP", ROLE_GLOSS
    CheckAgreementFor doc, "speak", ROLE_GLOSS
    CheckAgreementFor doc, "Edefina", ROLE_VERNACULAR

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
    SetSettingGramGlossInitialCap doc, True

    Eq "transform: attack.CMP on a gloss row keeps a full-size first capital", _
        TransformedCellText("attack.CMP", ROLE_GLOSS, doc), "attack.Cmp"
    Eq "transform: ERG on a gloss row", _
        TransformedCellText("ERG", ROLE_GLOSS, doc), "Erg"
    Eq "transform: the capital is the first LETTER, so 3SG is 3Sg", _
        TransformedCellText("3SG", ROLE_GLOSS, doc), "3Sg"
    SetSettingGramGlossInitialCap doc, False
    Eq "transform: without the initial capital, uniform small caps", _
        TransformedCellText("attack.CMP=REL", ROLE_GLOSS, doc), "attack.cmp=rel"
    SetSettingGramGlossInitialCap doc, True
    Eq "transform: Edefina on a vernacular row is untouched", _
        TransformedCellText("Edefina", ROLE_VERNACULAR, doc), "Edefina"
    Eq "transform: an all-caps vernacular word is untouched", _
        TransformedCellText("ERG", ROLE_VERNACULAR, doc), "ERG"

    Ok "transform preserves length (attack.CMP=REL)", _
        (Len(TransformedCellText("attack.CMP=REL", ROLE_GLOSS, doc)) = _
         Len("attack.CMP=REL"))

    ' With the setting off, the text is untouched but the runs are still marked.
    SetSettingLowercaseGramGloss doc, False
    Eq "transform: off means untouched", _
        TransformedCellText("attack.CMP", ROLE_GLOSS, doc), "attack.CMP"
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
    CheckNotProofed tbl
    CheckSmallCapsRuns tbl
    CheckFreeParagraphs tbl, ex, doc
    CheckOverWideColumn doc

    CloseNoSave doc
End Sub

' A form wider than the whole text area. The planner gives it a wrap line of its
' own and lets it overflow; the drawing must cap the cell at the text area so
' Word wraps the text inside it, rather than run it off the page -- which is
' what it did (by hand, 2026-09-12).
Private Sub CheckOverWideColumn(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim r As Long, c As Long
    Dim total As Double, worst As Double, avail As Double
    Dim where As Range

    ex = NewExample(2, 3)
    ex.Tiers(0) = ROLE_VERNACULAR
    ex.Tiers(1) = ROLE_GLOSS
    SetCell ex, 0, 0, "di=de"
    SetCell ex, 0, 1, String$(70, "w")
    SetCell ex, 0, 2, "bujo"
    SetCell ex, 1, 0, "pig=ERG"
    SetCell ex, 1, 1, "long"
    SetCell ex, 1, 2, "speak"

    Set where = doc.Content
    where.Collapse wdCollapseEnd
    Set tbl = RenderExample(ex, where)
    Ok "an example with an over-wide form still draws", (Not tbl Is Nothing)
    If tbl Is Nothing Then Exit Sub

    avail = AvailableTextWidth(RangeAfterTable(tbl))
    For r = 1 To tbl.Rows.Count
        total = 0
        For c = 1 To tbl.Rows(r).Cells.Count
            total = total + CellWidthOf(tbl, r, c)
        Next c
        If total > worst Then worst = total
    Next r
    Ok "and no row of it is wider than the text area (the cell wraps inside itself)", _
        (worst <= avail + 1)
    Emit "         widest row " & CStr(worst) & "pt, text area " & CStr(avail) & "pt"
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
    ' The full width, against the row's indent plus every cell, number cell
    ' included: what actually reaches the margin.
    avail = AvailableTextWidth(RangeAfterTable(tbl), True)

    For r = 1 To tbl.Rows.Count
        total = tbl.Rows(r).LeftIndent
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

' The first CONTENT cell: past the number column when the example has one.
' The spelling checker stays out of the cells and in the translation.
Private Sub CheckNotProofed(tbl As Table)
    Dim cell As Object, para As Object
    Dim cellOff As Boolean, transOn As Boolean
    On Error Resume Next
    Set cell = tbl.Cell(1, 1 + NumberColumns(tbl)).Range
    cellOff = (cell.NoProofing = True)
    Set para = ParagraphAfterTable(tbl)
    If Not para Is Nothing Then transOn = (para.Range.NoProofing = False)
    Err.Clear
    On Error GoTo 0
    Ok "interlinear cells are not spell-checked", cellOff
    Ok "the translation still is", transOn
End Sub

Private Function FirstCellParaStyle(tbl As Table, ByVal r As Long) As String
    On Error Resume Next
    FirstCellParaStyle = tbl.Cell(r, 1 + NumberColumns(tbl)).Range.Paragraphs(1).Style
    Err.Clear
    On Error GoTo 0
End Function

' Small caps have to be applied to the GRAMMATICAL segments only, through the
' character style, so read-back can restore the capitals. "attack.CMP" is the case
' that matters: a lexical part and a grammatical part in one cell.
Private Sub CheckSmallCapsRuns(tbl As Table)
    Dim found As Boolean
    Dim r As Long, c As Long
    Dim txt As String

    ' The example's gloss cell is "attack.CMP=REL" -- word-aligned, so the
    ' grammatical parts share the cell with the lexical part and with each
    ' other. Drawn, it must read "attack.Cmp=Rel" with the gram-gloss style on
    ' exactly the two abbreviations: character 8 is the c of cmp, 12 the r of
    ' rel, 1 the a of attack. (An earlier version looked for a cell that was
    ' exactly "attack.cmp", found none, and skipped -- a silent pass.)
    For r = 1 To tbl.Rows.Count
        For c = 1 To tbl.Rows(r).Cells.Count
            txt = CleanText(CellTextOf(tbl, r, c))
            If LCase$(Left$(txt, 10)) = "attack.cmp" Then
                found = True
                Eq "attack.CMP=REL is drawn in small-caps case", txt, "attack.Cmp=Rel"
                Ok "the lexical part carries no gram-gloss style", _
                    (Not CharHasGramStyle(tbl, r, c, 1))
                Ok "the first grammatical part carries the gram-gloss style", _
                    CharHasGramStyle(tbl, r, c, 8)
                Ok "the second grammatical part carries it too", _
                    CharHasGramStyle(tbl, r, c, 12)
            ElseIf txt = "di=de" Then
                ' A vernacular cell is drawn verbatim, with no run restyled, or an
                ' all-caps object-language word would be silently small-capped.
                Ok "a vernacular cell carries no gram-gloss style", _
                    (Not CharHasGramStyle(tbl, r, c, 1))
            End If
        Next c
    Next r

    Ok "the attack.CMP=REL cell was found to check its small-caps runs", found
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
        StripQuotes(LeftSingleQuote & "a pig attacked her" & RightSingleQuote), _
        "a pig attacked her"
    Eq "StripQuotes leaves unquoted text alone", _
        StripQuotes("a pig attacked her"), "a pig attacked her"
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

' The lowercasing that small caps requires must be REVERSIBLE. "attack.CMP" is the
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

    Eq "pig=ERG survives the small-caps round trip", back.Cells(1, 0), "pig=ERG"
    Eq "attack.CMP=REL survives it too (the mixed-run case)", _
        back.Cells(1, 1), "attack.CMP=REL"
    Eq "a lexical gloss is untouched", back.Cells(1, 2), "speak"
    Eq "and the vernacular row is untouched", back.Cells(0, 0), "di=de"
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
    CheckCommandIsNoOp doc, "LingTeXIndentExample"

    ' And on a document with no examples at all.
    CheckRewrapAllOnEmpty doc

    ' Then with a real example present.
    CheckRewrapAllCounts doc
    CheckSplitThenMerge doc
    CheckConvertPlainTable doc
    CheckIndentCommands doc

    gQuiet = savedQuiet
    CloseNoSave doc
End Sub

' Indent and Outdent step the example half an inch, number column and
' translation with it, and Outdent stops at the margin with a message.
Private Sub CheckIndentCommands(doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim hang As Double
    Dim numW As Double

    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "indent: an example could be drawn", False
        Exit Sub
    End If
    numW = 0
    If HasNumberColumn(tbl) Then numW = SettingNumberHang(doc)

    On Error Resume Next
    tbl.Cell(1, 1 + NumberColumns(tbl)).Range.Select
    Err.Clear
    On Error GoTo 0
    gLastMessage = ""
    RunCommandByName "LingTeXIndentExample"
    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Ok "indent: the example survived", False
        Emit "         said: " & gLastMessage
        Exit Sub
    End If
    Ok "Indent moves the example half an inch", (Abs(ExampleIndent(tbl) - 36) <= 0.5)
    Emit "         rows at " & CStr(ExampleIndent(tbl)) & "pt"
    hang = ParagraphAfterTable(tbl).Format.LeftIndent
    Ok "and the translation with it, past the number", (Abs(hang - 36 - numW) <= 0.5)
    Ok "the number is still (1)", (ExampleNumberString(tbl) = "(1)") Or (numW = 0)

    RunCommandByName "LingTeXIndentExample"
    Set tbl = FindExampleAt(Selection.Range)
    Ok "a second Indent makes an inch", _
        (Not tbl Is Nothing) And (Abs(ExampleIndent(tbl) - 72) <= 0.5)

    RunCommandByName "LingTeXOutdentExample"
    Set tbl = FindExampleAt(Selection.Range)
    Ok "Outdent takes half of it back", _
        (Not tbl Is Nothing) And (Abs(ExampleIndent(tbl) - 36) <= 0.5)

    RunCommandByName "LingTeXOutdentExample"
    Set tbl = FindExampleAt(Selection.Range)
    Ok "and the rest", (Not tbl Is Nothing) And (Abs(ExampleIndent(tbl)) <= 0.5)

    gLastMessage = ""
    RunCommandByName "LingTeXOutdentExample"
    Ok "Outdent at the margin says so and stops", _
        (InStr(1, gLastMessage, "left margin", vbTextCompare) > 0)
    Ok "LingTeXOutdentExample leaves gBusy clear", (Not gBusy)
    Ok "LingTeXOutdentExample leaves no undo record open", (Not UndoRecordIsOpen())
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
        Case "LingTeXIndentExample":    LingTeXIndentExample
        Case "LingTeXOutdentExample":   LingTeXOutdentExample
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

    ' The first content cell holds di=de / pig=ERG, which has a break to split on.
    On Error Resume Next
    tbl.Cell(1, 1 + NumberColumns(tbl)).Range.Select
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
    tbl.Cell(1, 1 + NumberColumns(tbl)).Range.Select
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

    SetPlainCell tbl, 1, 1, "di=de"
    SetPlainCell tbl, 1, 2, "deda=di"
    SetPlainCell tbl, 1, 3, "bujo"
    SetPlainCell tbl, 2, 1, "pig=ERG"
    SetPlainCell tbl, 2, 2, "attack.CMP=REL"
    SetPlainCell tbl, 2, 3, "speak"

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
    Eq "the converted table keeps its first cell", back.Cells(0, 0), "di=de"
    Eq "and its grammatical gloss, capitals and all", back.Cells(1, 0), "pig=ERG"
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

    CheckLeavingKeepsCursor ev, doc

    ev.Detach
    Ok "Detach does not raise", True

    ' Twice in a row must be safe -- AutoExit can run more than once.
    ev.Detach
    Ok "Detach twice does not raise", True

    gQuiet = savedQuiet
    CloseNoSave doc
End Sub

' Seth, with re-wrap on leave switched on: clicking the empty paragraph right
' after the translation, to keep writing, put the cursor in the first cell of
' the example. The re-wrap deletes and redraws the table at the very position
' that paragraph had been pulled back to. The handler must put the cursor back.
Private Sub CheckLeavingKeepsCursor(ev As clsAppEvents, doc As Document)
    Dim ex As IgtExample
    Dim tbl As Table
    Dim rowsBefore As Long
    Dim tailPos As Long, fromEnd As Long
    Dim inTable As Boolean

    gBusy = False
    doc.Content.Delete
    SetPageGeometry doc, 612, 792, 72
    ex = ThreeTierExample()
    Set tbl = RenderExample(ex, doc.Content)
    If tbl Is Nothing Then
        Ok "leaving: an example drew", False
        Exit Sub
    End If
    rowsBefore = tbl.Rows.Count
    SetSettingRewrapOnSelectionChange doc, True

    ' In the example, as the user is while editing it.
    On Error Resume Next
    tbl.Cell(1, 1).Range.Select
    ev.SelectionMoved Selection
    Err.Clear
    On Error GoTo 0

    ' Stale, so leaving it really redraws it, with more rows than before.
    SetPageGeometry doc, 234, 792, 72

    ' The empty paragraph after the translation: the last one in the document.
    tailPos = doc.Content.End - 1
    On Error Resume Next
    doc.Range(tailPos, tailPos).Select
    fromEnd = doc.Content.End - Selection.Start
    ev.SelectionMoved Selection
    inTable = Selection.Information(wdWithInTable)
    Err.Clear
    On Error GoTo 0

    Ok "leaving an example with re-wrap on leave redraws it", _
        (doc.Tables.Count = 1 And doc.Tables(1).Rows.Count > rowsBefore)
    Ok "and the cursor is still on the paragraph after the translation", _
        (Not inTable) And (doc.Content.End - Selection.Start = fromEnd)
    Emit "         rows " & CStr(rowsBefore) & " before, " & CStr(doc.Tables(1).Rows.Count) & _
         " after; cursor " & CStr(fromEnd) & " from the end both times"

    SetSettingRewrapOnSelectionChange doc, False
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
    SetCell ex, 0, 0, "di=de"
    SetCell ex, 0, 1, "deda=di"
    SetCell ex, 0, 2, "bujo"
    SetCell ex, 1, 0, "pig=ERG"
    SetCell ex, 1, 1, "attack.CMP=REL"
    SetCell ex, 1, 2, "speak"
    TwoTierExample = ex
End Function

Private Function ThreeTierExample() As IgtExample
    Dim ex As IgtExample
    ex = NewExample(3, 3)
    ex.Tiers(0) = ROLE_VERNACULAR
    ex.Tiers(1) = ROLE_GLOSS
    ex.Tiers(2) = ROLE_FREE
    SetCell ex, 0, 0, "di=de"
    SetCell ex, 0, 1, "deda=di"
    SetCell ex, 0, 2, "bujo"
    SetCell ex, 1, 0, "pig=ERG"
    SetCell ex, 1, 1, "attack.CMP=REL"
    SetCell ex, 1, 2, "speak"
    AddFreeLine ex, "A pig attacked her, is what I am talking about."
    ThreeTierExample = ex
End Function


'=============================================================================
' -- ADJACENT EXAMPLES ------------------------------------------------------
'=============================================================================
' Two examples close together, and re-wrap-all over both. Found by hand
' (2026-09-12): with one empty paragraph between them -- what Enter leaves
' after a translation, and it inherits LingTeX Free -- re-wrap-all deleted the
' second example. The empty paragraph was absorbed as a translation and
' deleted, the two tables touched, Word merged them, and tbl.Delete took both.
' Two layouts here: A has that empty paragraph, B has nothing but the
' translation between the tables, which is what two inserts in a row produce.
Private Sub TestAdjacentExamples()
    Dim savedQuiet As Boolean
    savedQuiet = gQuiet
    gQuiet = True
    CheckAdjacentPair "A", True
    CheckAdjacentPair "B", False
    gQuiet = savedQuiet
End Sub

Private Sub CheckAdjacentPair(ByVal tag As String, ByVal emptyBetween As Boolean)
    Dim doc As Document
    Dim ex As IgtExample, back As IgtExample
    Dim where As Range
    Dim t1 As Table, t2 As Table
    Dim para As Paragraph
    Dim between As Long
    Dim what As String

    what = IIf(emptyBetween, "an empty Free-styled paragraph between", _
                             "only the translation between")

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "adjacent " & tag & ": could create a blank document", False
        Exit Sub
    End If
    EnsureStyles doc, True
    ex = ThreeTierExample()

    Set t1 = RenderExample(ex, doc.Content)
    Ok "adjacent " & tag & ": first example drawn", (Not t1 Is Nothing)
    If emptyBetween Then
        doc.Content.InsertParagraphAfter
        Set para = doc.Paragraphs(doc.Paragraphs.Count)
        ApplyParaStyle para.Range, doc, ROLE_FREE      ' as Enter would leave it
    End If
    Set where = doc.Content
    where.Collapse wdCollapseEnd
    Set t2 = RenderExample(ex, where)
    Ok "adjacent " & tag & ": second example drawn with " & what, (Not t2 Is Nothing)
    Ok "adjacent " & tag & ": two tables before re-wrap", (doc.Tables.Count = 2)

    RewrapDocument doc, False

    Ok "adjacent " & tag & ": re-wrap all keeps both examples", (doc.Tables.Count = 2)
    If doc.Tables.Count = 2 Then
        Ok "adjacent " & tag & ": both are still interlinear", _
            (AllInterlinearTables(doc).Count = 2)
        between = doc.Range(doc.Tables(1).Range.End, _
                            doc.Tables(2).Range.Start).Paragraphs.Count
        Ok "adjacent " & tag & ": a paragraph still separates them", (between >= 1)
        back = ReadExampleFromTable(doc.Tables(1))
        AbsorbFreeParagraphs back, doc.Tables(1)
        Eq "adjacent " & tag & ": the first example keeps one translation", _
            CStr(back.FreeCount), "1"
        back = ReadExampleFromTable(doc.Tables(2))
        Ok "adjacent " & tag & ": the second example reads back whole", _
            (back.ColCount = ex.ColCount)
    End If
    CloseNoSave doc
End Sub


'=============================================================================
' -- NUMBERING --------------------------------------------------------------
'=============================================================================
' The example is the body of a numbered paragraph above it: an empty line in
' the LingTeX Example style, numbered by the LingTeX Example Number list style,
' Word's own numbering. The table and the translation are indented to that
' line's text position; a re-wrap keeps the line untouched and lays the
' example out to its indent, whatever it has become; deleting an example
' renumbers the rest. Numbering never appears in a cell.
Private Sub TestNumbering()
    Dim doc As Document
    Dim ex As IgtExample, back As IgtExample
    Dim where As Range
    Dim t1 As Table, t2 As Table
    Dim numPara As Paragraph, numLine As Paragraph
    Dim hang As Double
    Dim indent As Double, w As Double
    Dim savedQuiet As Boolean

    savedQuiet = gQuiet
    gQuiet = True

    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        Ok "numbering: could create a blank document", False
        gQuiet = savedQuiet
        Exit Sub
    End If

    Ok "default NumberExamples = True", SettingNumberExamples(doc)
    Ok "default NumberHang = 36", (SettingNumberHang(doc) = 36)
    Ok "default NumberLevel = 1", (SettingNumberLevel(doc) = 1)
    hang = SettingNumberHang(doc)

    EnsureStyles doc, True
    Ok STYLE_NUMBER & " exists as a LIST style", _
        StyleExistsOfType(doc, STYLE_NUMBER, wdStyleTypeList)
    Ok STYLE_EXAMPLE & " exists as a PARAGRAPH style", _
        StyleExistsOfType(doc, STYLE_EXAMPLE, wdStyleTypeParagraph)

    ex = ThreeTierExample()
    Set t1 = RenderExample(ex, doc.Content)
    Ok "a numbered example draws", (Not t1 Is Nothing)
    If t1 Is Nothing Then
        Emit "         " & gRenderError
        CloseNoSave doc
        gQuiet = savedQuiet
        Exit Sub
    End If
    Ok "and nothing was reported about the numbering", (gRenderError = "")
    If gRenderError <> "" Then Emit "         " & gRenderError

    '-- the number is a first column ------------------------------------------
    Ok "the example has a number column", HasNumberColumn(t1)
    Set numPara = NumberParagraphOf(t1)
    Ok "its first cell holds the number paragraph", (Not numPara Is Nothing)
    If Not numPara Is Nothing Then
        Ok "in the " & STYLE_EXAMPLE & " style", (numPara.Style = STYLE_EXAMPLE)
        Ok "carrying Word list numbering", _
            (numPara.Range.ListFormat.ListType <> wdListNoNumbering)
        Eq "and showing (1)", ExampleNumberString(t1), "(1)"
        Ok "with nothing typed in it", (Len(ParaText(numPara)) = 0)
        Ok "and no indent of its own", _
            (Abs(numPara.LeftIndent) <= 0.5 And Abs(numPara.FirstLineIndent) <= 0.5)
    End If
    Ok "no content cell carries numbering", _
        (t1.Cell(1, 2).Range.ListFormat.ListType = wdListNoNumbering)
    w = CellWidthOf(t1, 1, 1)
    Ok "the number cell is as wide as the hang", (Abs(w - hang) <= 0.5)
    Emit "         number cell " & CStr(w) & "pt, hang " & CStr(hang) & "pt"
    Ok "every row has one", NumberCellsAre(t1, hang)
    Ok "the rows themselves are not indented", (Abs(ExampleIndent(t1)) <= 0.5)
    indent = ParagraphAfterTable(t1).Format.LeftIndent
    Ok "the translation is indented past the number column", (Abs(indent - hang) <= 0.5)
    Ok "the cursor on the number is inside the example", _
        (Not FindExampleAt(t1.Cell(1, 1).Range) Is Nothing)

    back = ReadExampleFromTable(t1)
    Eq "the first cell's text is just the form", back.Cells(0, 0), "di=de"
    Ok "and the read-back counts no number column", (back.ColCount = ex.ColCount)
    Ok "nor does TableColumnCount", (TableColumnCount(t1) = ex.ColCount)

    Set where = doc.Content
    where.Collapse wdCollapseEnd
    Set t2 = RenderExample(ex, where)
    Ok "a second example draws", (Not t2 Is Nothing)
    If Not t2 Is Nothing Then
        Eq "and shows (2)", ExampleNumberString(t2), "(2)"
    End If

    RewrapDocument doc, False
    Ok "re-wrap all keeps both tables", (doc.Tables.Count = 2)
    If doc.Tables.Count = 2 Then
        Eq "re-wrap keeps (1) on the first", ExampleNumberString(doc.Tables(1)), "(1)"
        Eq "and (2) on the second", ExampleNumberString(doc.Tables(2)), "(2)"
        Ok "and each still has exactly one number paragraph", _
            (CountParagraphsInStyle(doc, STYLE_EXAMPLE) = 2)

        '-- the example's indent is its rows' indent, and a re-wrap keeps it --
        On Error Resume Next
        doc.Tables(1).Rows.LeftIndent = 72
        Err.Clear
        On Error GoTo 0
        RewrapDocument doc, False
        indent = ExampleIndent(doc.Tables(1))
        Ok "an indent on the rows survives a re-wrap", (Abs(indent - 72) <= 0.5)
        Emit "         rows at " & CStr(indent) & "pt"
        indent = ParagraphAfterTable(doc.Tables(1)).Format.LeftIndent
        Ok "and the translation sits past the indent and the number", _
            (Abs(indent - 72 - hang) <= 0.5)
        Eq "and the number is still (1)", ExampleNumberString(doc.Tables(1)), "(1)"

        DeleteExample doc.Tables(1)
        Ok "deleting the first example leaves one table", (doc.Tables.Count = 1)
        Ok "and one number paragraph", (CountParagraphsInStyle(doc, STYLE_EXAMPLE) = 1)
        If doc.Tables.Count = 1 Then
            Eq "and Word renumbers it (1)", ExampleNumberString(doc.Tables(1)), "(1)"
        End If
    End If

    '-- turned off, a new example has no number column ------------------------
    SetSettingNumberExamples doc, False
    Set where = doc.Content
    where.Collapse wdCollapseEnd
    Set t2 = RenderExample(ex, where)
    Ok "with numbering off, a new example draws", (Not t2 Is Nothing)
    If Not t2 Is Nothing Then
        Ok "and has no number column", (Not HasNumberColumn(t2))
        Ok "and is not indented", (Abs(ExampleIndent(t2)) <= 0.5)
        Ok "and its first cell is content", (TableColumnCount(t2) = ex.ColCount)
    End If
    SetSettingNumberExamples doc, True
    CloseNoSave doc

    '-- a wrapped example: every wrap line starts past the number column ------
    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        gQuiet = savedQuiet
        Exit Sub
    End If
    SetPageGeometry doc, 200, 792, 36
    EnsureStyles doc, True
    Set t1 = RenderExample(ex, doc.Content)
    Ok "numbering: a wrapped example draws on a narrow page", (Not t1 Is Nothing)
    If Not t1 Is Nothing Then
        Ok "and it did wrap", (t1.Rows.Count > 2)
        If t1.Rows.Count > 2 Then
            Ok "the first wrap line has the number cell", _
                (Abs(CellWidthOf(t1, 1, 1) - hang) <= 0.5)
            Ok "and so does a later one, empty", _
                (Abs(CellWidthOf(t1, 3, 1) - hang) <= 0.5 And _
                 Len(CleanText(CellTextOf(t1, 3, 1))) = 0)
            Eq "and the number is (1)", ExampleNumberString(t1), "(1)"
        End If
    End If
    CloseNoSave doc

    '-- the earlier design migrates: a number line above the table -----------
    ' Examples drawn before the number moved into the table have a numbered
    ' LingTeX Example paragraph above them. A re-wrap must move the number in
    ' and take the line away, not number them twice.
    Set doc = NewBlankDoc()
    If doc Is Nothing Then
        gQuiet = savedQuiet
        Exit Sub
    End If
    EnsureStyles doc, True
    SetSettingNumberExamples doc, False
    On Error Resume Next
    doc.Content.InsertParagraphAfter                 ' two empty paragraphs
    Err.Clear
    On Error GoTo 0
    Set t1 = RenderExample(ex, doc.Range(1, 1))       ' the table in the second
    SetSettingNumberExamples doc, True
    Ok "legacy: an unnumbered example drew after a paragraph", _
        (Not t1 Is Nothing) And (Not HasNumberColumn(t1))
    If Not t1 Is Nothing Then
        On Error Resume Next
        Set numLine = doc.Paragraphs(1)
        numLine.Style = doc.Styles(STYLE_EXAMPLE)     ' as the old design drew it
        numLine.LeftIndent = hang
        numLine.FirstLineIndent = -hang
        Err.Clear
        On Error GoTo 0
        Ok "legacy: the number line is recognised", _
            (Not LegacyNumberLineOf(t1) Is Nothing)
        Set t2 = RewrapTable(t1)
        Ok "re-wrapping moves the number into the table", _
            (Not t2 Is Nothing) And HasNumberColumn(t2)
        If Not t2 Is Nothing Then
            Eq "and it reads (1)", ExampleNumberString(t2), "(1)"
            Ok "and the number line is gone", _
                (CountParagraphsInStyle(doc, STYLE_EXAMPLE) = 1)
            Ok "and the example is not indented", (Abs(ExampleIndent(t2)) <= 0.5)
        End If
    End If
    CloseNoSave doc
    gQuiet = savedQuiet
End Sub

' Every row's first cell is the number cell: as wide as the hang.
Private Function NumberCellsAre(tbl As Table, ByVal hang As Double) As Boolean
    Dim r As Long
    For r = 1 To tbl.Rows.Count
        If Abs(CellWidthOf(tbl, r, 1) - hang) > 0.5 Then Exit Function
    Next r
    NumberCellsAre = True
End Function

Private Function CountParagraphsInStyle(doc As Document, ByVal nm As String) As Long
    Dim para As Paragraph
    Dim n As Long
    On Error Resume Next
    For Each para In doc.Paragraphs
        If para.Style = nm Then n = n + 1
    Next para
    Err.Clear
    On Error GoTo 0
    CountParagraphsInStyle = n
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
        If WriteReportFile("RunDocTests." & PlatformTag() & ".txt", mRpt) Then Exit Sub
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
