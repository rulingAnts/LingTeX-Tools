Attribute VB_Name = "modPptSettings"
Option Explicit
'=============================================================================
' modPptSettings  --  LingTeX-PowerPoint
'
' The presentation's settings, in Presentation.Tags (PLAN.md: there are no
' document variables here; Tags survive save, copy and paste).  The
' PowerPoint counterpart of Word's modSettings, with the keys that carry
' over: the font and size every example is set in, the gap between columns,
' the number hang, the space between the examples of one copy, whether new
' examples are numbered, how grammatical glosses are cased, the alignment
' new examples take, what replaces a space in a cell, and whether a resized
' example re-wraps itself.  A missing tag reads as its default, so a
' presentation that never saw the add-in behaves like one with defaults.
'
' Also the two derived things every drawing needs: the tier fonts of an
' example (forms italic) and the layout (PptLayout) for a number.  Insert,
' re-wrap and the commands all take them from here, so they cannot disagree.
'
' Pure ASCII.
'=============================================================================

Private Const PFX As String = "LINGTEX_SET_"

Private Const DEF_FONT As String = "Times New Roman"
Private Const DEF_SIZE As Double = 24
Private Const DEF_GAP As Double = 6
Private Const DEF_NUMBER_HANG As Double = 36
Private Const DEF_BETWEEN As Double = 12
Private Const DEF_SPACE_REPL As String = "."

'-----------------------------------------------------------------------------
' Reads
'-----------------------------------------------------------------------------
Public Function SettingFont(ByVal pres As Object) As String
    SettingFont = ReadStr(pres, "Font", DEF_FONT)
End Function

Public Function SettingSize(ByVal pres As Object) As Double
    SettingSize = ReadNum(pres, "Size", DEF_SIZE)
    If SettingSize < 4 Then SettingSize = DEF_SIZE
End Function

Public Function SettingGap(ByVal pres As Object) As Double
    SettingGap = ReadNum(pres, "Gap", DEF_GAP)
End Function

Public Function SettingNumberHang(ByVal pres As Object) As Double
    SettingNumberHang = ReadNum(pres, "NumberHang", DEF_NUMBER_HANG)
    If SettingNumberHang < 6 Then SettingNumberHang = DEF_NUMBER_HANG
End Function

Public Function SettingBetween(ByVal pres As Object) As Double
    SettingBetween = ReadNum(pres, "Between", DEF_BETWEEN)
End Function

Public Function SettingNumberExamples(ByVal pres As Object) As Boolean
    SettingNumberExamples = ReadBool(pres, "NumberExamples", True)
End Function

Public Function SettingLowercaseGram(ByVal pres As Object) As Boolean
    SettingLowercaseGram = ReadBool(pres, "LowercaseGram", True)
End Function

Public Function SettingInitialCap(ByVal pres As Object) As Boolean
    SettingInitialCap = ReadBool(pres, "InitialCap", False)
End Function

Public Function SettingRewrapOnResize(ByVal pres As Object) As Boolean
    SettingRewrapOnResize = ReadBool(pres, "RewrapOnResize", True)
End Function

Public Function SettingGranularity(ByVal pres As Object) As IgtGranularity
    If ReadStr(pres, "Granularity", "0") = "1" Then
        SettingGranularity = igtMorphemeAligned
    Else
        SettingGranularity = igtWordAligned
    End If
End Function

Public Function SettingSpaceReplacement(ByVal pres As Object) As String
    Dim s As String
    s = ReadStr(pres, "SpaceReplacement", DEF_SPACE_REPL)
    If s <> "." And s <> "_" Then s = DEF_SPACE_REPL
    SettingSpaceReplacement = s
End Function

'-----------------------------------------------------------------------------
' Writes
'-----------------------------------------------------------------------------
Public Sub SetSettingFont(ByVal pres As Object, ByVal v As String)
    WriteTag pres, "Font", v
End Sub

Public Sub SetSettingSize(ByVal pres As Object, ByVal v As Double)
    WriteTag pres, "Size", NumStr(v)
End Sub

Public Sub SetSettingGap(ByVal pres As Object, ByVal v As Double)
    WriteTag pres, "Gap", NumStr(v)
End Sub

Public Sub SetSettingNumberHang(ByVal pres As Object, ByVal v As Double)
    WriteTag pres, "NumberHang", NumStr(v)
End Sub

Public Sub SetSettingBetween(ByVal pres As Object, ByVal v As Double)
    WriteTag pres, "Between", NumStr(v)
End Sub

Public Sub SetSettingNumberExamples(ByVal pres As Object, ByVal v As Boolean)
    WriteTag pres, "NumberExamples", BoolStr(v)
End Sub

Public Sub SetSettingLowercaseGram(ByVal pres As Object, ByVal v As Boolean)
    WriteTag pres, "LowercaseGram", BoolStr(v)
End Sub

Public Sub SetSettingInitialCap(ByVal pres As Object, ByVal v As Boolean)
    WriteTag pres, "InitialCap", BoolStr(v)
End Sub

Public Sub SetSettingRewrapOnResize(ByVal pres As Object, ByVal v As Boolean)
    WriteTag pres, "RewrapOnResize", BoolStr(v)
End Sub

Public Sub SetSettingGranularity(ByVal pres As Object, ByVal v As IgtGranularity)
    WriteTag pres, "Granularity", IIf(v = igtMorphemeAligned, "1", "0")
End Sub

Public Sub SetSettingSpaceReplacement(ByVal pres As Object, ByVal v As String)
    If v <> "." And v <> "_" Then v = DEF_SPACE_REPL
    WriteTag pres, "SpaceReplacement", v
End Sub

'-----------------------------------------------------------------------------
' Derived: the fonts and the layout a drawing takes.
'-----------------------------------------------------------------------------
' One font per tier: the presentation's font and size, italic on the forms.
Public Function TierFontsFor(ByVal pres As Object, ex As IgtExample) As PptTierFont()
    Dim fonts() As PptTierFont, tf As PptTierFont, t As Long
    tf = BaseFont(pres)
    If ex.TierCount <= 0 Then
        ReDim fonts(0 To 0)
        fonts(0) = tf
        TierFontsFor = fonts
        Exit Function
    End If
    ReDim fonts(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        fonts(t) = tf
        fonts(t).Italic = (ex.Tiers(t) = ROLE_VERNACULAR Or ex.Tiers(t) = ROLE_MORPHEMES)
    Next t
    TierFontsFor = fonts
End Function

' The presentation's font, upright: the free translation's, the number's.
Public Function BaseFont(ByVal pres As Object) As PptTierFont
    Dim tf As PptTierFont
    tf.Name = SettingFont(pres)
    tf.Size = SettingSize(pres)
    tf.Italic = False
    BaseFont = tf
End Function

' The layout for an example numbered numberText ("" for none): the hang is
' the setting, or wider when the number itself needs more.
Public Function LayoutFor(ByVal pres As Object, ByVal numberText As String) As PptLayout
    Dim lay As PptLayout, tf As PptTierFont, numW As Double
    tf = BaseFont(pres)
    lay.Gap = SettingGap(pres)
    lay.LowercaseGram = SettingLowercaseGram(pres)
    lay.InitialCap = SettingInitialCap(pres)
    lay.FreeFont = tf
    If Len(numberText) > 0 Then
        numW = MeasureText(numberText, ROLE_FREE, tf) + lay.Gap
        If numW > SettingNumberHang(pres) Then lay.NumberHang = numW Else lay.NumberHang = SettingNumberHang(pres)
    Else
        lay.NumberHang = 0
    End If
    lay.ContIndent = lay.NumberHang
    LayoutFor = lay
End Function

'-----------------------------------------------------------------------------
' Tags.  Item on a missing name gives "" here; guarded all the same.
'-----------------------------------------------------------------------------
Private Function ReadStr(ByVal pres As Object, ByVal nm As String, ByVal dflt As String) As String
    Dim v As String
    ReadStr = dflt
    If pres Is Nothing Then Exit Function
    On Error Resume Next
    v = pres.Tags.Item(PFX & nm)
    If Err.Number = 0 And v <> "" Then ReadStr = v
    Err.Clear
End Function

' Numbers are stored with "." whatever the locale (Str/Val), as Word's are.
Private Function ReadNum(ByVal pres As Object, ByVal nm As String, ByVal dflt As Double) As Double
    Dim s As String
    ReadNum = dflt
    s = ReadStr(pres, nm, "")
    If s = "" Then Exit Function
    ReadNum = Val(s)
    If ReadNum < 0 Then ReadNum = 0
End Function

Private Function ReadBool(ByVal pres As Object, ByVal nm As String, ByVal dflt As Boolean) As Boolean
    Dim s As String
    s = ReadStr(pres, nm, "")
    If s = "" Then
        ReadBool = dflt
    Else
        ReadBool = (s = "1" Or LCase$(s) = "true")
    End If
End Function

Private Sub WriteTag(ByVal pres As Object, ByVal nm As String, ByVal v As String)
    If pres Is Nothing Then Exit Sub
    On Error Resume Next
    pres.Tags.Add PFX & nm, v
    Err.Clear
End Sub

Private Function NumStr(ByVal v As Double) As String
    NumStr = Trim$(Str$(v))
End Function

Private Function BoolStr(ByVal v As Boolean) As String
    If v Then BoolStr = "1" Else BoolStr = "0"
End Function
