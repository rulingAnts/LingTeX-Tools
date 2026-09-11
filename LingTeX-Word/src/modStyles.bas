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
Public Sub EnsureStyles(doc As Document)
    Dim bodyFont As String, bodySize As Single

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
End Sub

Private Sub EnsureParaStyle(doc As Document, ByVal role As String, _
        ByVal fontName As String, ByVal fontSize As Single, _
        ByVal italic As Boolean, ByVal spaceAfter As Single)

    Dim nm As String
    Dim st As Style

    nm = ParaStyleName(role)
    If StyleExists(doc, nm) Then Exit Sub          ' never clobber the user's

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=nm, Type:=wdStyleTypeParagraph)
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    On Error Resume Next
    With st
        .Font.Name = fontName
        .Font.Size = fontSize
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
    End With
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
    If StyleExists(doc, STYLE_GRAM) Then Exit Sub

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_GRAM, Type:=wdStyleTypeCharacter)
    On Error GoTo 0
    If st Is Nothing Then Exit Sub

    On Error Resume Next
    st.Font.SmallCaps = True
    On Error GoTo 0
End Sub

'-----------------------------------------------------------------------------
' The table style: the tag, and the borderless look.
'
' Borders are switched off here rather than on each table so that a user who
' wants to see the grid while editing can turn them on once, centrally, without
' the renderer putting them back.
'-----------------------------------------------------------------------------
Private Sub EnsureTableStyle(doc As Document)
    Dim st As Style
    If StyleExists(doc, STYLE_TABLE) Then Exit Sub

    On Error Resume Next
    Set st = doc.Styles.Add(Name:=STYLE_TABLE, Type:=wdStyleTypeTable)
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
    On Error GoTo 0
End Sub

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
    On Error GoTo 0
    If fn = "" Or Left$(fn, 1) = "+" Then
        On Error Resume Next
        fn = doc.Styles(wdStyleDefaultParagraphFont).Font.Name
        On Error GoTo 0
    End If
    If fn = "" Or Left$(fn, 1) = "+" Then fn = FALLBACK_FONT
    BodyFontName = fn
End Function

Public Function BodyFontSize(doc As Document) As Single
    Dim sz As Single
    On Error Resume Next
    sz = doc.Styles(wdStyleNormal).Font.Size
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
