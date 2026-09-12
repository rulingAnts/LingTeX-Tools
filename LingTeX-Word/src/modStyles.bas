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
Private Const STYLES_VERSION As String = "1"


'-- Last-resort font when the document reports only a theme placeholder.
'   Charis SIL is the usual choice for fieldwork documents; change it to suit
'   your template.
Public Const FALLBACK_FONT As String = "Charis SIL"

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
    ' The free translation sits under the table and gets a little air above it.
    EnsureParaStyle doc, ROLE_FREE, bodyFont, bodySize, False, 3

    EnsureGramStyle doc, bodyFont
    EnsureTableStyle doc

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
        .Font.Italic = italic
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
