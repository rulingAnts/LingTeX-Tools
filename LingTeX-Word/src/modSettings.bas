Attribute VB_Name = "modSettings"
Option Explicit

'=============================================================================
' modSettings  --  LingTeX-Word
'
' Settings, stored as Word DOCUMENT VARIABLES.
'
' Document variables travel inside the .docx, so an example re-wrapped on another
' machine -- or by a colleague who has the add-in -- is laid out with the same gap
' and indent as the author chose.  They need no file I/O, which matters because
' Mac Word is sandboxed and this add-in deliberately never touches the disk.
'
' Every getter falls back to a default, so a document that has never seen the
' add-in behaves sensibly and nothing has to be initialised up front.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

Private Const VAR_PREFIX As String = "LingTeX_"

'-- Defaults ------------------------------------------------------------------
' Horizontal air between alignment columns, in points.  Enough to read the
' columns as separate without the example sprawling.
Private Const DEF_GAP As Double = 6
' Vertical air between wrap lines, in points.
Private Const DEF_LINE_GAP As Double = 6
' Indent applied to every wrap line after the first, in points.  Zero by default:
' a flush-left continuation keeps the columns of long examples comparable.
Private Const DEF_CONT_INDENT As Double = 0
' What replaces a space found inside an interlinear cell.
Private Const DEF_SPACE_REPL As String = "."
' Lowercase grammatical glosses so Word's small caps can render them.
Private Const DEF_LOWERCASE_GRAM As Boolean = True
' ...and leave the first LETTER of each a full-size capital (Erg, 3Sg). Seth's
' preference (2026-09-12); the Leipzig Glossing Rules print them uniform, which
' is what False gives.
Private Const DEF_GRAM_INITIAL_CAP As Boolean = True
' Re-wrap every example in the document when it is saved.
Private Const DEF_REWRAP_ON_SAVE As Boolean = True
' Re-wrap as soon as the selection leaves an example. ON by default (Seth,
' once the cursor was put back where the user clicked): it fires only on
' leaving a table, never on a move inside one, so it does not fight typing.
Private Const DEF_REWRAP_ON_SELECTION As Boolean = True
' Number new examples: Word list numbering "(1)", "(2)"... on the first cell,
' continuing through the document, so deleting or moving one renumbers the rest.
Private Const DEF_NUMBER_EXAMPLES As Boolean = True
' The hanging indent that holds the number, in points. Everything after the
' number -- the cells under it, later wrap lines, the translation -- starts here.
Private Const DEF_NUMBER_HANG As Double = 36
' Which level of the "LingTeX Example Number" list style carries the number.
' 1 by default; 2 once level 1 is linked to Heading 1 for per-chapter restarts.
Private Const DEF_NUMBER_LEVEL As Long = 1
' Vertical air between the tier rows of one wrap line, in points. Zero: the
' tiers sit as close as the fonts allow, which is how interlinear text is set.
Private Const DEF_TIER_GAP As Double = 0
' Cell padding, in points, each side. Zero, because measurement happens in
' paragraphs with no padding, and the column gap is the air between columns;
' padding is added ON TOP of the measured width when set.
Private Const DEF_PAD As Double = 0
' The spacings that have NO built-in value of their own -- space before and
' after an example, its default left indent and its right indent, the air above
' the translation and between translations -- are OPTIONAL: unset, the renderer
' leaves the paragraph or the style alone, which is what every document drawn
' before these settings existed gets. Read them with SettingOptional; a negative
' answer means "not set".
Public Const SETTING_UNSET As Double = -1
' Every spacing key the ribbon's edit boxes can show (SpacingText and
' SetSpacingText below), for the settings report and the tests. The key is the
' document-variable name less its prefix; Gap, LineGap, ContIndent and
' NumberHang are the names the typed getters have always used.
Public Const SPACING_KEYS As String = _
    "ExampleBefore|ExampleAfter|ExampleLeft|ExampleRight|" & _
    "LineGap|ContIndent|TierGap|Gap|NumberHang|" & _
    "PadLeft|PadRight|PadTop|PadBottom|FreeAbove|FreeBetween"


'=============================================================================
' -- TYPED GETTERS ----------------------------------------------------------
'=============================================================================

Public Function SettingGap(doc As Document) As Double
    SettingGap = ReadDouble(doc, "Gap", DEF_GAP)
End Function

Public Function SettingLineGap(doc As Document) As Double
    SettingLineGap = ReadDouble(doc, "LineGap", DEF_LINE_GAP)
End Function

Public Function SettingContIndent(doc As Document) As Double
    SettingContIndent = ReadDouble(doc, "ContIndent", DEF_CONT_INDENT)
End Function

Public Function SettingSpaceReplacement(doc As Document) As String
    Dim s As String
    s = ReadString(doc, "SpaceReplacement", DEF_SPACE_REPL)
    If s <> "." And s <> "_" Then s = DEF_SPACE_REPL
    SettingSpaceReplacement = s
End Function

'-----------------------------------------------------------------------------
' Lowercase grammatical glosses so small caps can draw them as small capitals?
'
' Takes the document explicitly, like every other getter. It used to read
' ActiveDocument instead, on the grounds that this is "a presentation choice that
' applies wherever text is being written" -- but it is stored per document, so
' rendering into a document that is not the active one read the WRONG document's
' answer. Measurement made that worse: the width cache keys on this, so a cached
' width could be taken under one document's setting and served under another's.
'
' doc may be Nothing, in which case the default applies.
'-----------------------------------------------------------------------------
Public Function SettingLowercaseGramGloss(doc As Document) As Boolean
    SettingLowercaseGramGloss = ReadBool(doc, "LowercaseGramGloss", _
                                         DEF_LOWERCASE_GRAM)
End Function

Public Function SettingNumberExamples(doc As Document) As Boolean
    SettingNumberExamples = ReadBool(doc, "NumberExamples", DEF_NUMBER_EXAMPLES)
End Function

Public Function SettingNumberHang(doc As Document) As Double
    Dim v As Double
    v = ReadDouble(doc, "NumberHang", DEF_NUMBER_HANG)
    If v < 6 Then v = DEF_NUMBER_HANG
    SettingNumberHang = v
End Function

Public Function SettingNumberLevel(doc As Document) As Long
    Dim v As Double
    v = ReadDouble(doc, "NumberLevel", DEF_NUMBER_LEVEL)
    If v < 1 Or v > 9 Then v = DEF_NUMBER_LEVEL
    SettingNumberLevel = CLng(v)
End Function

Public Function SettingTierGap(doc As Document) As Double
    SettingTierGap = ReadDouble(doc, "TierGap", DEF_TIER_GAP)
End Function

' Cell padding, one side at a time: side is "Left", "Right", "Top" or "Bottom".
Public Function SettingCellPadding(doc As Document, ByVal side As String) As Double
    SettingCellPadding = ReadDouble(doc, "Pad" & side, DEF_PAD)
End Function

'-----------------------------------------------------------------------------
' An OPTIONAL spacing, by key: "ExampleBefore", "ExampleAfter", "ExampleLeft",
' "ExampleRight", "FreeAbove" or "FreeBetween". SETTING_UNSET (negative) when
' the document does not set it, in which case the renderer does not touch the
' property and the style's own value shows through.
'-----------------------------------------------------------------------------
Public Function SettingOptional(doc As Document, ByVal key As String) As Double
    Dim s As String
    SettingOptional = SETTING_UNSET
    s = ReadString(doc, key, "")
    If s = "" Then Exit Function
    On Error Resume Next
    SettingOptional = CDbl(s)
    If Err.Number <> 0 Then SettingOptional = SETTING_UNSET
    Err.Clear
    On Error GoTo 0
    If SettingOptional < 0 Then SettingOptional = SETTING_UNSET
End Function

Public Function SettingGramGlossInitialCap(doc As Document) As Boolean
    SettingGramGlossInitialCap = ReadBool(doc, "GramGlossInitialCap", _
                                          DEF_GRAM_INITIAL_CAP)
End Function

Public Function SettingRewrapOnSave(doc As Document) As Boolean
    SettingRewrapOnSave = ReadBool(doc, "RewrapOnSave", DEF_REWRAP_ON_SAVE)
End Function

Public Function SettingRewrapOnSelectionChange(doc As Document) As Boolean
    SettingRewrapOnSelectionChange = ReadBool(doc, "RewrapOnSelection", _
        DEF_REWRAP_ON_SELECTION)
End Function

Public Function SettingGranularity(doc As Document) As IgtGranularity
    If LCase$(ReadString(doc, "Granularity", "word")) = "morpheme" Then
        SettingGranularity = igtMorphemeAligned
    Else
        SettingGranularity = igtWordAligned
    End If
End Function


'=============================================================================
' -- TYPED SETTERS ----------------------------------------------------------
'=============================================================================

Public Sub SetSettingGap(doc As Document, ByVal v As Double)
    WriteVar doc, "Gap", CStr(v)
End Sub

Public Sub SetSettingLineGap(doc As Document, ByVal v As Double)
    WriteVar doc, "LineGap", CStr(v)
End Sub

Public Sub SetSettingContIndent(doc As Document, ByVal v As Double)
    WriteVar doc, "ContIndent", CStr(v)
End Sub

Public Sub SetSettingSpaceReplacement(doc As Document, ByVal v As String)
    If v <> "." And v <> "_" Then v = DEF_SPACE_REPL
    WriteVar doc, "SpaceReplacement", v
End Sub

Public Sub SetSettingLowercaseGramGloss(doc As Document, ByVal v As Boolean)
    WriteVar doc, "LowercaseGramGloss", BoolStr(v)
End Sub

Public Sub SetSettingNumberExamples(doc As Document, ByVal v As Boolean)
    WriteVar doc, "NumberExamples", BoolStr(v)
End Sub

Public Sub SetSettingNumberHang(doc As Document, ByVal v As Double)
    WriteVar doc, "NumberHang", CStr(v)
End Sub

Public Sub SetSettingNumberLevel(doc As Document, ByVal v As Long)
    WriteVar doc, "NumberLevel", CStr(v)
End Sub

Public Sub SetSettingGramGlossInitialCap(doc As Document, ByVal v As Boolean)
    WriteVar doc, "GramGlossInitialCap", BoolStr(v)
End Sub

Public Sub SetSettingRewrapOnSave(doc As Document, ByVal v As Boolean)
    WriteVar doc, "RewrapOnSave", BoolStr(v)
End Sub

Public Sub SetSettingRewrapOnSelectionChange(doc As Document, ByVal v As Boolean)
    WriteVar doc, "RewrapOnSelection", BoolStr(v)
End Sub

Public Sub SetSettingGranularity(doc As Document, ByVal v As IgtGranularity)
    If v = igtMorphemeAligned Then
        WriteVar doc, "Granularity", "morpheme"
    Else
        WriteVar doc, "Granularity", "word"
    End If
End Sub


'=============================================================================
' -- SPACING SETTINGS BY NAME, FOR THE RIBBON -------------------------------
'=============================================================================
' The LingTeX Styles tab shows one edit box per spacing, and an edit box holds
' TEXT: what the document stores, or empty when it stores nothing. Empty is a
' real state -- "leave it to the default, or to the style" -- so these do not
' fall back to a default the way the typed getters do; they say what is set.
'
' The key is the document-variable name less its prefix. The spacings with a
' built-in default (Gap, LineGap, ContIndent, NumberHang, TierGap, Pad*) and
' the optional ones (see SettingOptional) go through the same two calls.

' Is this a key SetSpacingText accepts?
Public Function IsSpacingKey(ByVal key As String) As Boolean
    IsSpacingKey = (InStr(1, "|" & SPACING_KEYS & "|", "|" & key & "|", _
                          vbTextCompare) > 0)
End Function

' The stored value as text for an edit box: "" when unset, otherwise the number
' in the user's locale (CStr writes the decimal separator Word shows).
Public Function SpacingText(doc As Document, ByVal key As String) As String
    Dim s As String
    Dim v As Double
    s = ReadString(doc, key, "")
    If s = "" Then Exit Function
    On Error Resume Next
    v = CDbl(s)
    If Err.Number <> 0 Then
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If
    Err.Clear
    On Error GoTo 0
    SpacingText = CStr(v)
End Function

'-----------------------------------------------------------------------------
' Store what was typed into an edit box. Empty (or only spaces) UNSETS the
' spacing: the variable is removed, so the default or the style applies again.
' A number, with either decimal separator and with or without "pt", is stored
' in points. Returns False, storing nothing, for anything else -- the caller
' says so and refreshes the box back to the stored value.
'
' Parsed with Val after normalising the separator, because Val is not
' locale-aware and CDbl is: "6,5" must mean six and a half on every machine,
' not sixty-five on one and an error on another. Stored with CStr, read back
' with CDbl -- both locale-aware, and consistent with each other.
'-----------------------------------------------------------------------------
Public Function SetSpacingText(doc As Document, ByVal key As String, _
        ByVal text As String) As Boolean
    Dim t As String
    Dim v As Double
    Dim i As Long, ch As String

    If doc Is Nothing Then Exit Function
    If Not IsSpacingKey(key) Then Exit Function

    t = Trim$(text)
    If t = "" Then
        ClearSetting doc, key
        SetSpacingText = True
        Exit Function
    End If
    If LCase$(Right$(t, 2)) = "pt" Then t = Trim$(Left$(t, Len(t) - 2))
    t = Replace(t, ",", ".")
    ' Digits, at most one point, an optional leading sign; nothing else.
    If t = "" Or t = "." Or t = "-" Or t = "+" Then Exit Function
    For i = 1 To Len(t)
        ch = Mid$(t, i, 1)
        If (ch < "0" Or ch > "9") And ch <> "." Then
            If Not (i = 1 And (ch = "-" Or ch = "+")) Then Exit Function
        End If
    Next i
    If InStr(1, t, ".") <> InStrRev(t, ".") Then Exit Function
    v = Val(t)
    If v < 0 Then v = 0
    If v > 1584 Then v = 1584               ' 22 inches: Word's own ceiling
    WriteVar doc, key, CStr(v)
    SetSpacingText = True
End Function

' Is anything stored under this key?
Public Function SettingDefined(doc As Document, ByVal key As String) As Boolean
    SettingDefined = (ReadString(doc, key, "") <> "")
End Function

' Remove a stored setting, so its default (or the style) applies again.
Public Sub ClearSetting(doc As Document, ByVal key As String)
    If doc Is Nothing Then Exit Sub
    On Error Resume Next
    doc.Variables(VAR_PREFIX & key).Delete
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- STORAGE ----------------------------------------------------------------
'=============================================================================

' Document.Variables has no Exists, and reading a missing name raises, so every
' read is guarded and falls back to its default.
Private Function ReadString(doc As Document, ByVal nm As String, _
        ByVal dflt As String) As String
    Dim v As String
    ReadString = dflt
    If doc Is Nothing Then Exit Function
    On Error Resume Next
    v = doc.Variables(VAR_PREFIX & nm).Value
    If Err.Number = 0 And v <> "" Then ReadString = v
    Err.Clear
    On Error GoTo 0
End Function

Private Function ReadDouble(doc As Document, ByVal nm As String, _
        ByVal dflt As Double) As Double
    Dim s As String
    ReadDouble = dflt
    s = ReadString(doc, nm, "")
    If s = "" Then Exit Function
    On Error Resume Next
    ReadDouble = CDbl(s)
    If Err.Number <> 0 Then ReadDouble = dflt
    Err.Clear
    On Error GoTo 0
    If ReadDouble < 0 Then ReadDouble = 0
End Function

Private Function ReadBool(doc As Document, ByVal nm As String, _
        ByVal dflt As Boolean) As Boolean
    Dim s As String
    s = ReadString(doc, nm, "")
    If s = "" Then
        ReadBool = dflt
    Else
        ReadBool = (s = "1" Or LCase$(s) = "true")
    End If
End Function

Private Sub WriteVar(doc As Document, ByVal nm As String, ByVal v As String)
    If doc Is Nothing Then Exit Sub
    On Error Resume Next
    doc.Variables(VAR_PREFIX & nm).Value = v
    If Err.Number <> 0 Then
        Err.Clear
        doc.Variables.Add Name:=VAR_PREFIX & nm, Value:=v
    End If
    Err.Clear
    On Error GoTo 0
End Sub

Private Function BoolStr(ByVal v As Boolean) As String
    If v Then
        BoolStr = "1"
    Else
        BoolStr = "0"
    End If
End Function

' ActiveDocument raises when no document is open, which happens during startup.
Private Function ActiveDocumentOrNothing() As Document
    On Error Resume Next
    Set ActiveDocumentOrNothing = ActiveDocument
    Err.Clear
    On Error GoTo 0
End Function
