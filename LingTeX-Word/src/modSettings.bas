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
Private Const DEF_GAP As Single = 6
' Vertical air between wrap lines, in points.
Private Const DEF_LINE_GAP As Single = 6
' Indent applied to every wrap line after the first, in points.  Zero by default:
' a flush-left continuation keeps the columns of long examples comparable.
Private Const DEF_CONT_INDENT As Single = 0
' What replaces a space found inside an interlinear cell.
Private Const DEF_SPACE_REPL As String = "."
' Lowercase grammatical glosses so Word's small caps can render them.
Private Const DEF_LOWERCASE_GRAM As Boolean = True
' Re-wrap every example in the document when it is saved.
Private Const DEF_REWRAP_ON_SAVE As Boolean = True
' Re-wrap as soon as the selection leaves an example.  OFF by default: it is
' correct but it moves the cursor and repaints while the user is still typing.
Private Const DEF_REWRAP_ON_SELECTION As Boolean = False


'=============================================================================
' -- TYPED GETTERS ----------------------------------------------------------
'=============================================================================

Public Function SettingGap(doc As Document) As Single
    SettingGap = ReadSingle(doc, "Gap", DEF_GAP)
End Function

Public Function SettingLineGap(doc As Document) As Single
    SettingLineGap = ReadSingle(doc, "LineGap", DEF_LINE_GAP)
End Function

Public Function SettingContIndent(doc As Document) As Single
    SettingContIndent = ReadSingle(doc, "ContIndent", DEF_CONT_INDENT)
End Function

Public Function SettingSpaceReplacement(doc As Document) As String
    Dim s As String
    s = ReadString(doc, "SpaceReplacement", DEF_SPACE_REPL)
    If s <> "." And s <> "_" Then s = DEF_SPACE_REPL
    SettingSpaceReplacement = s
End Function

' Called from modRender without a document, because it is a presentation choice
' that applies wherever text is being written.
Public Function SettingLowercaseGramGloss() As Boolean
    SettingLowercaseGramGloss = ReadBool(ActiveDocumentOrNothing(), _
        "LowercaseGramGloss", DEF_LOWERCASE_GRAM)
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

Public Sub SetSettingGap(doc As Document, ByVal v As Single)
    WriteVar doc, "Gap", CStr(v)
End Sub

Public Sub SetSettingLineGap(doc As Document, ByVal v As Single)
    WriteVar doc, "LineGap", CStr(v)
End Sub

Public Sub SetSettingContIndent(doc As Document, ByVal v As Single)
    WriteVar doc, "ContIndent", CStr(v)
End Sub

Public Sub SetSettingSpaceReplacement(doc As Document, ByVal v As String)
    If v <> "." And v <> "_" Then v = DEF_SPACE_REPL
    WriteVar doc, "SpaceReplacement", v
End Sub

Public Sub SetSettingLowercaseGramGloss(doc As Document, ByVal v As Boolean)
    WriteVar doc, "LowercaseGramGloss", BoolStr(v)
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

Private Function ReadSingle(doc As Document, ByVal nm As String, _
        ByVal dflt As Single) As Single
    Dim s As String
    ReadSingle = dflt
    s = ReadString(doc, nm, "")
    If s = "" Then Exit Function
    On Error Resume Next
    ReadSingle = CSng(s)
    If Err.Number <> 0 Then ReadSingle = dflt
    Err.Clear
    On Error GoTo 0
    If ReadSingle < 0 Then ReadSingle = 0
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
