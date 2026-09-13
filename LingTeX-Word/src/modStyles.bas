Attribute VB_Name = "modStyles"
Option Explicit

'=============================================================================
' modStyles  --  LingTeX-Word
'
' The Word styles that make a rendered interlinear example SELF-DESCRIBING, and
' the code that creates them on demand.
'
' ---------------------------------------------------------------------------
' WHY STYLES AND NOT HIDDEN METADATA
'
' Re-wrapping an example means reading it back out of the document.  That could
' be done by stashing the source text in a document variable, a bookmark or a
' custom XML part -- but every one of those is a side channel that can be lost by
' a copy-paste, a Track Changes accept, or a round trip through another editor,
' leaving a table the add-in no longer recognises.
'
' Instead the rendered table carries everything needed:
'
'   * The TABLE STYLE is the tag.  A table styled "LingTeX Interlinear" is an
'     auto-wrapping example; anything else is left alone.  One property test,
'     and it survives cut and paste, save and reopen, and Windows/Mac round
'     trips.
'   * The PARAGRAPH STYLE of a row's first cell is that row's tier role.  A new
'     wrap line begins wherever the first tier role comes round again, so
'     concatenating the cells group by group recovers the flat column list
'     exactly.
'   * The CHARACTER STYLE marks which gloss runs were grammatical abbreviations,
'     so read-back can restore "ERG" from the lowercased "erg" that small caps
'     requires.
'
' Two things fall out of this for free.  The user gets real control -- restyle
' "LingTeX Gloss" once and every example in the document follows -- and a real
' escape hatch: change a table's style and the add-in stops touching it.
' ---------------------------------------------------------------------------
'
' EnsureStyles NEVER overwrites a style that already exists.  A user who has
' tuned their gloss font keeps it; we only fill in what is missing.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-- The tag that marks a table as ours.
Public Const STYLE_TABLE As String = "LingTeX Interlinear"

'-- Paragraph styles, one per tier role.  The name is always
'   "LingTeX " & role, which is what lets ParaStyleName and RoleFromParaStyle be
'   exact inverses -- read-back depends on that.
Public Const STYLE_PREFIX As String = "LingTeX "

'-- Character style for grammatical gloss runs.
Public Const STYLE_GRAM As String = "LingTeX Gram Gloss"
' The list style whose level 1 numbers examples "(1)", "(2)"... Applied to the
' first cell's paragraph, so the number is Word's own: it renumbers when an
' example is deleted or moved, cross-references can point at it, and linking
' its level 1 to Heading 1 (then NumberLevel 2) restarts it per chapter.
Public Const STYLE_NUMBER As String = "LingTeX Example Number"
' The paragraph in an example's NUMBER CELL: the first cell of the first row,
' in the number column. Its style is linked to STYLE_NUMBER, so applying it
' numbers the paragraph, and modReadBack.HasNumberColumn recognises a numbered
' example by it. Never on a content cell.
Public Const STYLE_EXAMPLE As String = "LingTeX Example"

' Module-level state lives HERE, above the first procedure, or it does not exist:
' VBA's declarations section ends at the first Sub/Function, and a variable or
' Const placed after that is a compile error. vba-lint.py checks this now.

' A style name collided with a style of the wrong kind. Empty after a clean run.
Public gStyleError As String

' Remembered for the session. A document object identity check is enough to skip
' the common case of many examples in one document.
Private mStyledDoc As Document

' Set by the Ensure*Style helpers when they actually add a style.
Private mCreatedStyle As Boolean
' Whether this document has already been through EnsureStyles, recorded where the
' settings live so it survives save and reopen. Versioned, so a future change to
' the style set re-runs rather than trusting a stale mark.
Private Const STYLES_MADE_VAR As String = "LingTeX_StylesMade"
Private Const STYLES_VERSION As String = "1-num3-noproof"


'-- Last-resort font when the document reports only a theme placeholder.
'   Charis SIL is the usual choice for fieldwork documents; change it to suit
'   your template.
Public Const FALLBACK_FONT As String = "Charis SIL"

'-- The STYLE SLOTS: every style the add-in owns, in the order the Settings
'   dialog lists them. Slots 0 to 5 are the tier paragraph styles, 6 the
'   grammatical-gloss character style, 7 the number-cell paragraph style.
Public Const STYLE_SLOT_COUNT As Long = 8
Private Const SLOT_LABELS As String = _
    "Vernacular|Morphemes|Gloss|Word Gloss|Category|Free Translation|" & _
    "Grammatical Gloss|Example Number"
' The space after the translation paragraph, as created: a little air under
' the example. The one paragraph-format default that is not zero.
Private Const FREE_SPACE_AFTER As Double = 3

' Paragraph style name for a tier role.
Public Function ParaStyleName(ByVal role As String) As String
    ParaStyleName = STYLE_PREFIX & role
End Function

' Tier role for a paragraph style name, or "" when the style is not one of ours.
Public Function RoleFromParaStyle(ByVal styleName As String) As String
    If Len(styleName) <= Len(STYLE_PREFIX) Then Exit Function
    If Left$(styleName, Len(STYLE_PREFIX)) <> STYLE_PREFIX Then Exit Function
    If styleName = STYLE_GRAM Then Exit Function          ' a character style
    RoleFromParaStyle = Mid$(styleName, Len(STYLE_PREFIX) + 1)
End Function


'=============================================================================
' -- CREATION ---------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Make sure every style the renderer needs exists in this document.
' Existing styles are left exactly as the user has them.
'-----------------------------------------------------------------------------
'-----------------------------------------------------------------------------
' Make sure every style the add-in needs exists in this document.
'
' Called once per render, and each call costs roughly eleven round trips into
' Word's object model -- which on Mac Word is slow enough to notice, multiplied by
' every example in a whole-document re-wrap. So the answer is remembered per
' document, in the same document-variable store the settings use, and the work is
' done once. mStyledDoc is the within-session fast path; the document variable
' survives save and reopen.
'
' Passing force:=True redoes the work regardless, for a test that has deliberately
' broken a style.
'-----------------------------------------------------------------------------
Public Sub EnsureStyles(doc As Document, Optional ByVal force As Boolean = False)
    Dim bodyFont As String, bodySize As Double
    Dim createdAny As Boolean

    If Not force Then
        If Not mStyledDoc Is Nothing Then
            If mStyledDoc Is doc Then Exit Sub
        End If
        ' The mark plus ONE probe, not eleven. The mark alone would be wrong for a
        ' document whose styles were deleted by hand after it was set.
        If StylesAlreadyMade(doc) Then
            If StyleExistsOfType(doc, STYLE_TABLE, wdStyleTypeTable) Then
                Set mStyledDoc = doc
                Exit Sub
            End If
        End If
    End If

    mCreatedStyle = False
    gStyleError = ""
    bodyFont = BodyFontName(doc)
    bodySize = BodyFontSize(doc)

    ' The object language is conventionally italic; the glosses upright.
    EnsureParaStyle doc, ROLE_VERNACULAR, bodyFont, bodySize, True, 0
    EnsureParaStyle doc, ROLE_MORPHEMES, bodyFont, bodySize, True, 0
    EnsureParaStyle doc, ROLE_GLOSS, bodyFont, bodySize, False, 0
    EnsureParaStyle doc, ROLE_WORDGLOSS, bodyFont, bodySize, False, 0
    EnsureParaStyle doc, ROLE_CATEGORY, bodyFont, bodySize, False, 0
    ' The free translation sits under the table and gets a little air under it.
    EnsureParaStyle doc, ROLE_FREE, bodyFont, bodySize, False, FREE_SPACE_AFTER

    EnsureGramStyle doc, bodyFont
    EnsureTableStyle doc
    EnsureNumberListStyle doc
    EnsureExampleParaStyle doc

    createdAny = mCreatedStyle

    ' A newly created or changed style invalidates every width measured under the
    ' old appearance. ClearCache's own comment has always said to call it here;
    ' until now nothing did, anywhere in the project.
    If createdAny Then ClearCache

    ' Only remember success. A wrong-kind name collision means some style is
    ' missing, so the next call has to look again and report again rather than
    ' take a stale mark for an answer.
    If gStyleError = "" Then
        Set mStyledDoc = doc
        MarkStylesMade doc
    Else
        Set mStyledDoc = Nothing
    End If
End Sub


' Make the six tier styles follow Normal again: based on it, size inherited,
' font pinned from the body font. For documents whose styles predate that
' rule, and for a user who wants their tuning undone. See LingTeXResetStyles.
Public Sub ResetParaStylesToBody(doc As Document)
    Dim roles(0 To 5) As String
    Dim i As Long
    Dim st As Style
    Dim bodyFont As String, bodySize As Double

    roles(0) = ROLE_VERNACULAR
    roles(1) = ROLE_MORPHEMES
    roles(2) = ROLE_GLOSS
    roles(3) = ROLE_WORDGLOSS
    roles(4) = ROLE_CATEGORY
    roles(5) = ROLE_FREE
    bodyFont = BodyFontName(doc)
    bodySize = BodyFontSize(doc)

    For i = 0 To 5
        If StyleExistsOfType(doc, ParaStyleName(roles(i)), wdStyleTypeParagraph) Then
            On Error Resume Next
            Set st = doc.Styles(ParaStyleName(roles(i)))
            st.BaseStyle = doc.Styles(wdStyleNormal)
            st.Font.Name = bodyFont
            ' Equal to the base's value, which Word stores as "no difference",
            ' so from here on the size follows Normal.
            st.Font.Size = bodySize
            Err.Clear
            On Error GoTo 0
        End If
    Next i
    ClearCache
End Sub

Private Sub EnsureParaStyle(doc As Document, ByVal role As String, _
        ByVal fontName As String, ByVal fontSize As Double, _
        ByVal italic As Boolean, ByVal spaceAfter As Double)

    Dim nm As String
    Dim st As Style

    nm = ParaStyleName(role)
    If StyleExistsOfType(doc, nm, wdStyleTypeParagraph) Then Exit Sub  ' never clobber
    If StyleExists(doc, nm) Then
        ' Right name, wrong kind. Creating it is impossible and skipping it leaves
        ' every row of every example unstyled, so say so.
        gStyleError = "A style called """ & nm & """ already exists in this " & _
                      "document but is not a paragraph style, so interlinear rows " & _
                      "cannot be tagged. Rename or delete it and try again."
        Exit Sub
    End If

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=nm, Type:=wdStyleTypeParagraph)
    If Not st Is Nothing Then mCreatedStyle = True
    Err.Clear
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    ApplyTierStyleDefaults doc, st, role, fontName, fontSize, italic, spaceAfter
End Sub

' What a tier paragraph style looks like as created. Shared by creation and by
' Reset This Style on the ribbon, so a reset gives back exactly what a fresh
' document gets.
Private Sub ApplyTierStyleDefaults(doc As Document, st As Style, ByVal role As String, _
        ByVal fontName As String, ByVal fontSize As Double, _
        ByVal italic As Boolean, ByVal spaceAfter As Double)

    On Error Resume Next
    With st
        ' Based on Normal, with the SIZE inherited, so a document whose body
        ' text grows or shrinks takes its examples with it on the next re-wrap
        ' (by hand, 2026-09-12: sizing the cells directly was lost on re-wrap,
        ' as any direct formatting is -- the styles are the description). The
        ' font NAME is pinned at creation, from the body font: what the
        ' measurer reads back from a style must be a name the scratch document
        ' can apply, and a theme placeholder ("+Body") is not.
        .BaseStyle = doc.Styles(wdStyleNormal)
        .Font.Name = fontName
        .Font.Size = fontSize
        .Font.Bold = False
        .Font.Italic = italic
        .Font.SmallCaps = False
        ' Tight, unjustified, unhyphenated: a cell holds one alignment slot and
        ' must not be re-laid-out by Word behind the planner's back.
        With .ParagraphFormat
            .Alignment = wdAlignParagraphLeft
            .LeftIndent = 0
            .RightIndent = 0
            .FirstLineIndent = 0
            .SpaceBefore = 0
            .SpaceAfter = spaceAfter
            .LineSpacingRule = wdLineSpaceSingle
            .WidowControl = False
            .Hyphenation = False
        End With
        .NoSpaceBetweenParagraphsOfSameStyle = True
        ' Enter after a translation gives an ORDINARY paragraph, not another
        ' LingTeX Free one -- otherwise the blank line a person leaves between
        ' two examples looks like part of the first (see IsTranslationParagraph).
        ' Inside a cell the following paragraph keeps the tier's style.
        If role = ROLE_FREE Then .NextParagraphStyle = doc.Styles(wdStyleNormal)
    End With
    Err.Clear
    On Error GoTo 0
    ' Vernacular forms and glosses are not English, and the spelling checker
    ' underlining every cell is noise (Seth). The interlinear tier styles are
    ' marked "do not check spelling or grammar"; the translation stays checked.
    ' Late-bound: NoProofing is unproven on Mac, and a missing member would be
    ' a compile error for the whole module.
    If role <> ROLE_FREE Then SetNoProofing st
End Sub

' Mark a style, or a range, as not to be proofed.
Public Sub SetNoProofing(target As Object)
    On Error Resume Next
    target.NoProofing = True
    Err.Clear
    On Error GoTo 0
End Sub

'-----------------------------------------------------------------------------
' The grammatical-gloss character style.
'
' SmallCaps is the point of it.  Word's small-caps attribute only affects
' LOWERCASE letters, so the renderer stores "erg" and lets the style draw it as
' small capitals; storing "ERG" would render as full-size capitals and look
' wrong.  Because the style marks exactly which runs were transformed,
' modReadBack can restore "ERG" losslessly -- the lowercasing is reversible, not
' destructive.
'-----------------------------------------------------------------------------
Private Sub EnsureGramStyle(doc As Document, ByVal fontName As String)
    Dim st As Style
    If StyleExistsOfType(doc, STYLE_GRAM, wdStyleTypeCharacter) Then Exit Sub
    If StyleExists(doc, STYLE_GRAM) Then
        gStyleError = "A style called """ & STYLE_GRAM & """ already exists but is " & _
                      "not a character style, so small capitals cannot be marked " & _
                      "reversibly. Rename or delete it and try again."
        Exit Sub
    End If

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_GRAM, Type:=wdStyleTypeCharacter)
    If Not st Is Nothing Then mCreatedStyle = True
    Err.Clear
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    On Error Resume Next
    st.Font.SmallCaps = True
    Err.Clear
    On Error GoTo 0
End Sub

'-----------------------------------------------------------------------------
' The table style.  Its real job is to be THE TAG: a table carrying this style is
' an auto-wrapping interlinear example, and one that does not is left alone.
' Creating it works on both platforms (probe section 9).
'
' It also tries to carry the borderless look, so a user who wants to see the grid
' while editing could switch it on centrally. That part is best-effort only:
' setting Style.Table.Borders fails on Mac Word with error 4198, "Command
' failed" (probe section 9 again). So modRender.StyleTable ALSO switches borders
' off on each table it draws, and on Mac that is the only thing actually doing it.
'
' Do not "simplify" by removing the per-table border setting in modRender on the
' grounds that the style handles it -- on Mac the style does not.
'-----------------------------------------------------------------------------
' NOTE ON Err.Clear, throughout this module.
'
' Every "On Error Resume Next" block here is followed by Err.Clear before
' "On Error GoTo 0", and that is load-bearing rather than tidiness: On Error
' GoTo 0 disables the handler but does NOT reset Err. EnsureTableStyle below
' raises 4198 on Mac by design -- Style.Table.Borders is not settable there -- so
' without the clear, Err stayed set with 4198 all the way out of EnsureStyles, and
' a caller that tested Err.Number to decide whether its own work had succeeded
' concluded that it had not. RewrapDocument did exactly that, and reported
' "Re-wrapped 0 interlinear examples" for a run that had just re-wrapped them all.
' The example-number list style. Missing, examples draw unnumbered and
' ApplyExampleNumber says so in gRenderError; it never blocks a render.
Private Sub EnsureNumberListStyle(doc As Document)
    Dim st As Style

    If StyleExistsOfType(doc, STYLE_NUMBER, wdStyleTypeList) Then Exit Sub
    If StyleExists(doc, STYLE_NUMBER) Then Exit Sub    ' wrong kind; drawn unnumbered

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_NUMBER, Type:=wdStyleTypeList)
    If Not st Is Nothing Then mCreatedStyle = True
    Err.Clear
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    ' The number sits alone in a cell as wide as the hang, so the level puts
    ' it at the cell's left edge with nothing after it: a trailing tab or a
    ' text position would push it onto a second line inside the cell.
    On Error Resume Next
    With st.ListTemplate.ListLevels(1)
        .NumberFormat = "(%1)"
        .NumberStyle = wdListNumberStyleArabic
        .TrailingCharacter = wdTrailingNone
        .NumberPosition = 0
        .TextPosition = 0
        .TabPosition = 0
    End With
    Err.Clear
    On Error GoTo 0
End Sub

' The number-cell paragraph style. Based on Normal so the number matches the
' body text in size, no space around it (it shares a row with the vernacular
' line, and space would push it down), and linked to the example-number list
' style so applying it numbers the paragraph. If the link cannot be made the
' number is applied to each paragraph directly instead.
Private Sub EnsureExampleParaStyle(doc As Document)
    Dim st As Style
    If StyleExistsOfType(doc, STYLE_EXAMPLE, wdStyleTypeParagraph) Then Exit Sub
    If StyleExists(doc, STYLE_EXAMPLE) Then Exit Sub

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_EXAMPLE, Type:=wdStyleTypeParagraph)
    If Not st Is Nothing Then mCreatedStyle = True
    Err.Clear
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    On Error Resume Next
    With st
        .BaseStyle = doc.Styles(wdStyleNormal)
        With .ParagraphFormat
            .KeepWithNext = True
            .SpaceBefore = 0
            .SpaceAfter = 0
            ' Single, not Normal's multiple: the number shares a row with the
            ' vernacular line and must not make that row taller than the rest.
            .LineSpacingRule = wdLineSpaceSingle
            .Alignment = wdAlignParagraphLeft
            .WidowControl = False
        End With
        .NextParagraphStyle = doc.Styles(wdStyleNormal)
        If StyleExistsOfType(doc, STYLE_NUMBER, wdStyleTypeList) Then
            .LinkToListTemplate ListTemplate:=doc.Styles(STYLE_NUMBER).ListTemplate, _
                                ListLevelNumber:=1
        End If
    End With
    Err.Clear
    On Error GoTo 0
End Sub

Private Sub EnsureTableStyle(doc As Document)
    Dim st As Style
    If StyleExistsOfType(doc, STYLE_TABLE, wdStyleTypeTable) Then Exit Sub
    If StyleExists(doc, STYLE_TABLE) Then
        gStyleError = "A style called """ & STYLE_TABLE & """ already exists but is " & _
                      "not a table style, so examples cannot be tagged as " & _
                      "interlinear. Rename or delete it and try again."
        Exit Sub
    End If

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_TABLE, Type:=wdStyleTypeTable)
    If Not st Is Nothing Then mCreatedStyle = True
    Err.Clear
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    On Error Resume Next
    With st.Table
        .Borders(wdBorderTop).LineStyle = wdLineStyleNone
        .Borders(wdBorderBottom).LineStyle = wdLineStyleNone
        .Borders(wdBorderLeft).LineStyle = wdLineStyleNone
        .Borders(wdBorderRight).LineStyle = wdLineStyleNone
        .Borders(wdBorderHorizontal).LineStyle = wdLineStyleNone
        .Borders(wdBorderVertical).LineStyle = wdLineStyleNone
        .LeftPadding = 0
        .RightPadding = 0
        .TopPadding = 0
        .BottomPadding = 0
        .Spacing = 0
    End With
    Err.Clear
    On Error GoTo 0
End Sub

Private Function StylesAlreadyMade(doc As Document) As Boolean
    Dim v As String
    On Error Resume Next
    v = CStr(doc.Variables(STYLES_MADE_VAR).Value)
    Err.Clear
    On Error GoTo 0
    StylesAlreadyMade = (v = STYLES_VERSION)
End Function

Private Sub MarkStylesMade(doc As Document)
    On Error Resume Next
    doc.Variables(STYLES_MADE_VAR).Value = STYLES_VERSION
    If Err.Number <> 0 Then
        Err.Clear
        doc.Variables.Add Name:=STYLES_MADE_VAR, Value:=STYLES_VERSION
    End If
    Err.Clear
    On Error GoTo 0
End Sub

'-----------------------------------------------------------------------------
' Does a style of this name AND THIS KIND exist?
'
' The type check is the point. Without it, a document that already has a
' CHARACTER style called "LingTeX Gloss" -- from an earlier paste, a template, or
' another tool -- made EnsureParaStyle skip creating the paragraph style it
' needed. ApplyParaStyle then failed silently, RowRole read the paragraph style and
' got "Normal", every role came back empty, and DetectGroupSize fell back to the
' row count: the entire wrapped table read back as one giant wrap line. A name
' collision of the wrong kind is worth noticing, not skipping.
'
' wantType of 0 means "any kind", for callers that only care about the name.
'-----------------------------------------------------------------------------
Public Function StyleExistsOfType(doc As Document, ByVal nm As String, _
        ByVal wantType As Long) As Boolean

    Dim st As Style
    Dim got As Long

    On Error Resume Next
    Set st = doc.Styles(nm)
    If Err.Number <> 0 Or st Is Nothing Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    If wantType = 0 Then
        StyleExistsOfType = True
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    got = st.Type
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    Err.Clear
    On Error GoTo 0
    StyleExistsOfType = (got = wantType)
End Function

' The name alone, for callers that genuinely do not care about the kind.
Public Function StyleExists(doc As Document, ByVal nm As String) As Boolean
    Dim st As Style
    On Error Resume Next
    Set st = doc.Styles(nm)
    StyleExists = (Err.Number = 0 And Not st Is Nothing)
    Err.Clear
    On Error GoTo 0
End Function

'-----------------------------------------------------------------------------
' The document's body font.  Theme fonts are reported as placeholders beginning
' with "+", which is not a font name Word will accept back, so those are
' rejected in favour of the hard fallback.
'-----------------------------------------------------------------------------
Public Function BodyFontName(doc As Document) As String
    Dim fn As String
    On Error Resume Next
    fn = doc.Styles(wdStyleNormal).Font.Name
    Err.Clear
    On Error GoTo 0
    If fn = "" Or Left$(fn, 1) = "+" Then
        On Error Resume Next
        fn = doc.Styles(wdStyleDefaultParagraphFont).Font.Name
        Err.Clear
        On Error GoTo 0
    End If
    If fn = "" Or Left$(fn, 1) = "+" Then fn = FALLBACK_FONT
    BodyFontName = fn
End Function

Public Function BodyFontSize(doc As Document) As Double
    Dim sz As Double
    On Error Resume Next
    sz = doc.Styles(wdStyleNormal).Font.Size
    Err.Clear
    On Error GoTo 0
    If sz <= 0 Then sz = 12
    BodyFontSize = sz
End Function

'-----------------------------------------------------------------------------
' Apply a paragraph style to a range, tolerating its absence.
' A missing style must not abort a render: the example still needs to appear,
' just with the surrounding formatting.
'-----------------------------------------------------------------------------
Public Sub ApplyParaStyle(rng As Range, doc As Document, ByVal role As String)
    On Error Resume Next
    rng.Style = doc.Styles(ParaStyleName(role))
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- THE STYLE SLOTS: THE STYLES THE SETTINGS DIALOG LISTS ------------------
'=============================================================================
' The Settings dialog lists the add-in's styles and opens the selected one in
' Word's OWN style dialog (Seth, 2026-09-14: list them, and Modify in Word;
' no font boxes of our own). So nothing here writes a font: the readers below
' say what a style sets of its own, for the settings report, and ResetStyleSlot
' puts one back to what a fresh document gets. "Of its own" means different
' from the base style (Normal): a value equal to the base's IS the inherited
' state as far as Word is concerned, since it stores no difference.

' The Word style name of a slot; "" for an index out of range.
Public Function StyleSlotName(ByVal i As Long) As String
    Select Case i
        Case 0: StyleSlotName = ParaStyleName(ROLE_VERNACULAR)
        Case 1: StyleSlotName = ParaStyleName(ROLE_MORPHEMES)
        Case 2: StyleSlotName = ParaStyleName(ROLE_GLOSS)
        Case 3: StyleSlotName = ParaStyleName(ROLE_WORDGLOSS)
        Case 4: StyleSlotName = ParaStyleName(ROLE_CATEGORY)
        Case 5: StyleSlotName = ParaStyleName(ROLE_FREE)
        Case 6: StyleSlotName = STYLE_GRAM
        Case 7: StyleSlotName = STYLE_EXAMPLE
    End Select
End Function

' What the drop-down calls the slot.
Public Function StyleSlotLabel(ByVal i As Long) As String
    Dim parts() As String
    parts = Split(SLOT_LABELS, "|")
    If i < 0 Then Exit Function
    If i > UBound(parts) Then Exit Function
    StyleSlotLabel = parts(i)
End Function

' The tier role of a paragraph slot, "" for the two that are not tiers.
Private Function StyleSlotRole(ByVal i As Long) As String
    If i >= 0 And i <= 5 Then StyleSlotRole = RoleFromParaStyle(StyleSlotName(i))
End Function

' The style object of a slot. With create:=True the LingTeX styles are made
' first if the document has none yet, so the dialog can open a style in Word
' before any example is drawn -- the WRITERS pass that. The readers do not: a
' report must not leave ten styles (and a dirty flag) in a document its owner
' only asked about. Nothing when the slot is out of range or the style is
' absent or could not be made.
Public Function StyleSlotObject(doc As Document, ByVal i As Long, _
        Optional ByVal create As Boolean = False) As Style
    Dim nm As String
    If doc Is Nothing Then Exit Function
    nm = StyleSlotName(i)
    If nm = "" Then Exit Function
    If create Then EnsureStyles doc
    On Error Resume Next
    Set StyleSlotObject = doc.Styles(nm)
    Err.Clear
    On Error GoTo 0
End Function

' The font name every slot inherits when it sets none: the body font, as a
' name the measurer can use (never a theme placeholder).
Private Function SlotBaseFontName(doc As Document) As String
    SlotBaseFontName = BodyFontName(doc)
End Function

' A style's own font name, resolved past a theme placeholder the same way the
' base is, so the comparison is between two real names.
Private Function SlotFontName(doc As Document, st As Style) As String
    Dim fn As String
    On Error Resume Next
    fn = st.Font.Name
    Err.Clear
    On Error GoTo 0
    If fn = "" Or Left$(fn, 1) = "+" Then fn = SlotBaseFontName(doc)
    SlotFontName = fn
End Function

' The slot's font name, "" when it is the base's.
Public Function StyleFontText(doc As Document, ByVal i As Long) As String
    Dim st As Style
    Dim fn As String
    Set st = StyleSlotObject(doc, i)
    If st Is Nothing Then Exit Function
    fn = SlotFontName(doc, st)
    If StrComp(fn, SlotBaseFontName(doc), vbTextCompare) = 0 Then Exit Function
    StyleFontText = fn
End Function

' The slot's font size, "" when it is the base's.
Public Function StyleSizeText(doc As Document, ByVal i As Long) As String
    Dim st As Style
    Dim sz As Double
    Set st = StyleSlotObject(doc, i)
    If st Is Nothing Then Exit Function
    On Error Resume Next
    sz = st.Font.Size
    Err.Clear
    On Error GoTo 0
    If sz <= 0 Then Exit Function
    If sz = BodyFontSize(doc) Then Exit Function
    StyleSizeText = CStr(sz)
End Function

' Bold, Italic or SmallCaps as the style resolves it (the EFFECTIVE value).
Public Function StyleFlag(doc As Document, ByVal i As Long, ByVal which As String) As Boolean
    Dim st As Style
    Dim v As Long
    Set st = StyleSlotObject(doc, i)
    If st Is Nothing Then Exit Function
    On Error Resume Next
    Select Case which
        Case "Bold":      v = st.Font.Bold
        Case "Italic":    v = st.Font.Italic
        Case "SmallCaps": v = st.Font.SmallCaps
    End Select
    Err.Clear
    On Error GoTo 0
    StyleFlag = (v <> False)
End Function

'-----------------------------------------------------------------------------
' Put one slot back to what a fresh document gets: based on Normal, the body
' font and size (so it follows Normal from here on), italic for the two
' object-language tiers, small capitals for the grammatical-gloss style, and
' the tier paragraph format (tight, left-aligned, no indents). It IS a
' clobber of anything set on that style by hand, and the command says so.
'-----------------------------------------------------------------------------
Public Sub ResetStyleSlot(doc As Document, ByVal i As Long)
    Dim st As Style
    Dim role As String
    Dim bodyFont As String, bodySize As Double
    Set st = StyleSlotObject(doc, i, True)
    If st Is Nothing Then Exit Sub
    bodyFont = BodyFontName(doc)
    bodySize = BodyFontSize(doc)
    role = StyleSlotRole(i)
    Select Case i
        Case 0, 1
            ApplyTierStyleDefaults doc, st, role, bodyFont, bodySize, True, 0
        Case 2, 3, 4
            ApplyTierStyleDefaults doc, st, role, bodyFont, bodySize, False, 0
        Case 5
            ApplyTierStyleDefaults doc, st, role, bodyFont, bodySize, False, FREE_SPACE_AFTER
        Case 6
            ' A character style inherits from the paragraph it sits in; the body
            ' font and size are that, for every paragraph the add-in writes.
            On Error Resume Next
            st.Font.Name = bodyFont
            st.Font.Size = bodySize
            st.Font.Bold = False
            st.Font.Italic = False
            st.Font.SmallCaps = True
            Err.Clear
            On Error GoTo 0
        Case 7
            On Error Resume Next
            st.BaseStyle = doc.Styles(wdStyleNormal)
            st.Font.Name = bodyFont
            st.Font.Size = bodySize
            st.Font.Bold = False
            st.Font.Italic = False
            st.Font.SmallCaps = False
            st.ParagraphFormat.SpaceBefore = 0
            st.ParagraphFormat.SpaceAfter = 0
            st.ParagraphFormat.LineSpacingRule = wdLineSpaceSingle
            Err.Clear
            On Error GoTo 0
    End Select
    ClearCache
End Sub
