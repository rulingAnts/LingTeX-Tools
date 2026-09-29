Attribute VB_Name = "modPptRibbon"
Option Explicit
'=============================================================================
' modPptRibbon  --  LingTeX-PowerPoint
'
' The ribbon's callbacks (src/customUI14.xml), and the add-in's start and
' stop.  Every onAction is a one-line call into the command it names; the
' toggles show and change the active presentation's settings
' (modPptSettings).  Controls are typed As Variant rather than As
' IRibbonControl so the project needs no reference to the Office object
' library, as in LingTeX-Word.
'
' Auto_Open runs when PowerPoint loads the add-in from its Startup folder
' (PLAN.md: a .ppam there loads at every start): it hooks the events.
'
' Pure ASCII.
'=============================================================================

Private mRibbon As Object

Public Sub Auto_Open()
    LingTeXStart
End Sub

Public Sub Auto_Close()
    LingTeXStop
End Sub

Public Sub RbnOnLoad(ribbon As Variant)
    On Error Resume Next
    Set mRibbon = ribbon
    Err.Clear
End Sub

Public Sub RefreshRibbon()
    On Error Resume Next
    If Not mRibbon Is Nothing Then mRibbon.Invalidate
    Err.Clear
End Sub

'-- the toggles ---------------------------------------------------------------
Public Sub RbnGetPressed(control As Variant, ByRef returnedVal As Variant)
    Dim pres As Object
    returnedVal = False
    On Error Resume Next
    Set pres = Application.ActivePresentation
    If pres Is Nothing Then Exit Sub
    Select Case control.Id
        Case "LingTeXAlignWord"
            returnedVal = (SettingGranularity(pres) = igtWordAligned)
        Case "LingTeXAlignMorpheme"
            returnedVal = (SettingGranularity(pres) = igtMorphemeAligned)
        Case "LingTeXNumbersToggle"
            returnedVal = SettingNumberExamples(pres)
        Case "LingTeXInitialCapToggle"
            returnedVal = SettingInitialCap(pres)
        Case "LingTeXRewrapOnResizeToggle"
            returnedVal = SettingRewrapOnResize(pres)
    End Select
    Err.Clear
End Sub

Public Sub RbnToggle(control As Variant, pressed As Boolean)
    Dim pres As Object
    On Error Resume Next
    Set pres = Application.ActivePresentation
    If pres Is Nothing Then Exit Sub
    Select Case control.Id
        Case "LingTeXAlignWord"
            LingTeXAlignByWord
        Case "LingTeXAlignMorpheme"
            LingTeXAlignByMorpheme
        Case "LingTeXNumbersToggle"
            SetSettingNumberExamples pres, pressed
        Case "LingTeXInitialCapToggle"
            SetSettingInitialCap pres, pressed
        Case "LingTeXRewrapOnResizeToggle"
            SetSettingRewrapOnResize pres, pressed
    End Select
    Err.Clear
    RefreshRibbon
End Sub

'-- the buttons ---------------------------------------------------------------
Public Sub RbnInsert(control As Variant)
    LingTeXInsertInterlinear
End Sub

Public Sub RbnRewrapCurrent(control As Variant)
    LingTeXRewrapSelected
End Sub

Public Sub RbnRewrapAll(control As Variant)
    LingTeXRewrapAll
End Sub

Public Sub RbnRenumber(control As Variant)
    LingTeXRenumber
End Sub

Public Sub RbnSplitColumn(control As Variant)
    LingTeXSplitColumn
End Sub

Public Sub RbnMergeColumns(control As Variant)
    LingTeXMergeColumns
End Sub

Public Sub RbnCheck(control As Variant)
    LingTeXCheckGlossing
End Sub
