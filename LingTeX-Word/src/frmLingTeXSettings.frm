VERSION 5.00
Begin {C62A69F0-16DC-11CE-9E8B-00AA00574A4F} frmLingTeXSettings
   Caption         =   "LingTeX-Word Settings"
   ClientHeight    =   9000
   ClientLeft      =   120
   ClientTop       =   465
   ClientWidth     =   10890
   StartUpPosition =   1  'CenterOwner
End
Attribute VB_Name = "frmLingTeXSettings"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

'=============================================================================
' frmLingTeXSettings  --  LingTeX-Word
'
' The Settings dialog: every document setting behind one form. How new
' examples are aligned and numbered, the small-capitals convention, the
' re-wrap triggers, every spacing at every level and in every direction, and
' the LingTeX styles, each of which opens in Word's own style dialog.
'
' THE FORM HAS NO CONTROLS AT DESIGN TIME. Every control is built in code by
' UserForm_Initialize, because a UserForm designed in the VBA editor exports
' as a .frm plus a binary .frx that nothing outside Word can author, review or
' diff. Built in code, the form is this one text file: tools/ImportModules.bas
' creates the component (VBComponents.Add, type 3) and installs this source the
' way it installs the two class modules, and a person can Insert > UserForm,
' name it frmLingTeXSettings, and paste. The header above carries no
' OleObjectBlob line, which is the .frx reference; there is none.
'
' EVENTS. A control added at run time raises nothing into the form module by
' name, so a Private Sub btnOK_Click would never fire. The buttons are therefore
' held in WithEvents variables declared below, and it is THEIR _Click
' procedures that run. Boxes, checks and the list need no events at all: they
' are read when a button is pressed.
'
' MODAL, AND HANDED BACK FOR ONE THING. Show is modal and returns when the form
' hides itself: OK applies and hides, Apply applies and stays, Cancel hides.
' Modify in Word hides the form with Result = "modify" and lets the CALLER
' (modLingTeX.LingTeXSettings) open Word's Style dialog and show the form
' again. Word's own dialog on top of a modal UserForm is unproven on Mac; a
' form that steps aside first needs nothing unproven.
'
' Pure ASCII, and NO LINE CONTINUATIONS. This file is installed with
' AddFromString, which on Mac Word double-spaces a CRLF string, and "_"
' followed by a blank line is a syntax error (clsAppEvents, 2026-09-12). Long
' strings are built in several statements; vba-lint.py enforces the rule for
' .cls and .frm alike.
'=============================================================================

' What the caller finds when Show returns: "ok", "cancel" or "modify".
Public Result As String

' The document whose settings the form shows and writes. Set by LoadFrom.
Private mDoc As Document

' The buttons, WithEvents so the _Click procedures below fire (see header).
Private WithEvents mOK As MSForms.CommandButton
Private WithEvents mApply As MSForms.CommandButton
Private WithEvents mCancel As MSForms.CommandButton
Private WithEvents mModify As MSForms.CommandButton
Private WithEvents mResetStyle As MSForms.CommandButton
Private WithEvents mResetAll As MSForms.CommandButton
Private WithEvents mDefaults As MSForms.CommandButton

' Layout, in points. One grid, so the form reads as one thing.
Private Const INSIDE_W As Double = 540
Private Const MARGIN As Double = 12
Private Const ROW_H As Double = 21
Private Const LABEL_H As Double = 15
Private Const BOX_W As Double = 34
Private Const BOX_H As Double = 17
Private Const BTN_H As Double = 22
Private Const BTN_W As Double = 72
Private Const LIST_W As Double = 306
' Tall enough for all eight styles at the Mac font size (seven showed, with a
' scrollbar, on the first Mac run).
Private Const LIST_H As Double = 116
' A spacing row: its label at the margin, then up to four label+box pairs
' from PAIRS_X on, PAIR_W apart, each box PAIR_BOX_DX into its pair.
Private Const PAIRS_X As Double = 104
Private Const PAIR_W As Double = 108
Private Const PAIR_BOX_DX As Double = 72

' Where the last row ended, so Initialize can size the form to its content.
Private mBottom As Double
' Unique names for the labels nobody needs to find again.
Private mSerial As Long


'=============================================================================
' -- BUILDING THE FORM ------------------------------------------------------
'=============================================================================

Private Sub UserForm_Initialize()
    On Error Resume Next
    Me.Caption = "LingTeX-Word Settings"
    Me.StartUpPosition = 1                  ' centred on Word's window
    Err.Clear
    On Error GoTo 0
    BuildControls
    On Error Resume Next
    Me.Width = INSIDE_W + (Me.Width - Me.InsideWidth)
    Me.Height = mBottom + (Me.Height - Me.InsideHeight)
    Err.Clear
    On Error GoTo 0
End Sub

Private Sub BuildControls()
    Dim y As Double
    Dim lst As Object
    Dim i As Long
    Dim note As String

    '-- New examples -------------------------------------------------------
    y = 8
    AddHeader "New examples", y
    y = y + LABEL_H + 4
    AddOption "Word", "align", "One column per word", MARGIN, y, 200
    AddOption "Morpheme", "align", "One column per morpheme", 250, y, 270
    y = y + ROW_H
    AddCheck "Number", "Number them (1), (2)... in a first column", MARGIN, y, 232
    AddLabel "List level", 250, y + 2, 56
    AddBox "txtNumberLevel", 308, y, 28
    Me.Controls("txtNumberLevel").ControlTipText = "Which level of the LingTeX Example Number list style carries the number: 1, or 2 once level 1 is linked to Heading 1 for per-chapter numbering."
    y = y + ROW_H
    AddCheck "SmallCaps", "Grammatical glosses in small capitals", MARGIN, y, 232
    AddCheck "InitialCap", "with a full-size first capital (Erg, 3Sg)", 250, y, 270
    y = y + ROW_H
    AddCheck "RewrapSave", "Re-wrap every example when the document is saved", MARGIN, y, 236
    AddCheck "RewrapLeave", "Re-wrap an example when the cursor leaves it", 250, y, 270
    y = y + ROW_H
    AddLabel "A space inside a cell becomes", MARGIN, y + 2, 160
    AddOption "Dot", "space", ". (full stop)", 176, y, 90
    AddOption "Underscore", "space", "_ (underscore)", 272, y, 110
    y = y + ROW_H + 6

    '-- Spacing -------------------------------------------------------------
    AddHeader "Spacing, in points (6) or as a percentage of the font size (50% is half a line). An empty box means the default, in brackets.", y, 2
    y = y + 2 * LABEL_H + 4
    AddSpacingRow y, "Example", "ExampleBefore=Before (0)|ExampleAfter=After (3)|ExampleLeft=Left|ExampleRight=Right (0)"
    y = y + ROW_H
    AddSpacingRow y, "Wrap lines", "LineGap=Line gap (6)|ContIndent=Continuation (0)|TierGap=Tier gap (0)"
    y = y + ROW_H
    AddSpacingRow y, "Columns", "Gap=Column gap (6)|NumberHang=Number col. (36)"
    y = y + ROW_H
    AddSpacingRow y, "Cell padding", "PadLeft=Left (0)|PadRight=Right (0)|PadTop=Top (0)|PadBottom=Bottom (0)"
    y = y + ROW_H
    AddSpacingRow y, "Translation", "FreeAbove=Above (6)|FreeBetween=Between (0)"
    y = y + ROW_H + 6

    '-- Styles ----------------------------------------------------------------
    AddHeader "Styles", y
    y = y + LABEL_H + 4
    Set lst = Me.Controls.Add("Forms.ListBox.1", "lstStyles", True)
    lst.Left = MARGIN
    lst.Top = y
    lst.Width = LIST_W
    lst.Height = LIST_H
    For i = 0 To STYLE_SLOT_COUNT - 1
        lst.AddItem StyleSlotLabel(i) & "   (" & StyleSlotName(i) & ")"
    Next i
    On Error Resume Next
    lst.ListIndex = 0
    Err.Clear
    On Error GoTo 0
    Set mModify = AddButton("btnModify", "Modify in Word...", MARGIN + LIST_W + 12, y, INSIDE_W - MARGIN - (MARGIN + LIST_W + 12))
    Set mResetStyle = AddButton("btnResetStyle", "Reset This Style", MARGIN + LIST_W + 12, y + BTN_H + 6, INSIDE_W - MARGIN - (MARGIN + LIST_W + 12))
    Set mResetAll = AddButton("btnResetAll", "Reset the Six Tier Styles", MARGIN + LIST_W + 12, y + 2 * (BTN_H + 6), INSIDE_W - MARGIN - (MARGIN + LIST_W + 12))
    y = y + LIST_H + 6
    note = "Modify in Word opens Word's own style dialog on the selected style: font, size, colour, "
    note = note & "spacing, everything. Every example follows on its next re-wrap. Reset puts a style back "
    note = note & "to what a fresh document gets, following the Normal style."
    AddLabel note, MARGIN, y, INSIDE_W - 2 * MARGIN, 2 * LABEL_H
    y = y + 2 * LABEL_H + 8

    '-- Restore Defaults / OK / Apply / Cancel --------------------------------
    Set mDefaults = AddButton("btnDefaults", "Restore Defaults", MARGIN, y, 120)
    On Error Resume Next
    mDefaults.ControlTipText = "Every box and tick back to what a fresh document gets. Nothing is stored until OK or Apply. The styles have their own Reset buttons above."
    Err.Clear
    On Error GoTo 0
    Set mOK = AddButton("btnOK", "OK", INSIDE_W - MARGIN - 3 * BTN_W - 16, y, BTN_W)
    Set mApply = AddButton("btnApply", "Apply", INSIDE_W - MARGIN - 2 * BTN_W - 8, y, BTN_W)
    Set mCancel = AddButton("btnCancel", "Cancel", INSIDE_W - MARGIN - BTN_W, y, BTN_W)
    On Error Resume Next
    mOK.Default = True
    mCancel.Cancel = True
    Err.Clear
    On Error GoTo 0
    mBottom = y + BTN_H + MARGIN
End Sub

' A row of the Spacing section: the row's label, then label+box pairs from a
' spec of the form "Key=Label|Key=Label", the key being the modSettings
' spacing key the box reads and writes (its control is named txt & key).
Private Sub AddSpacingRow(ByVal y As Double, ByVal rowLabel As String, ByVal spec As String)
    Dim pairs() As String
    Dim kv() As String
    Dim i As Long
    Dim x As Double
    Dim key As String
    AddLabel rowLabel, MARGIN, y + 2, PAIRS_X - MARGIN - 4
    pairs = Split(spec, "|")
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        key = kv(0)
        x = PAIRS_X + i * PAIR_W
        AddLabel kv(1), x, y + 2, PAIR_BOX_DX - 2, LABEL_H, "lbl" & key
        AddBox "txt" & key, x + PAIR_BOX_DX, y, BOX_W
        On Error Resume Next
        Me.Controls("txt" & key).ControlTipText = SpacingTip(key)
        Me.Controls("lbl" & key).ControlTipText = SpacingTip(key)
        Err.Clear
        On Error GoTo 0
    Next i
End Sub

Private Sub AddHeader(ByVal text As String, ByVal y As Double, Optional ByVal lines As Long = 1)
    Dim lbl As Object
    Set lbl = AddLabel(text, MARGIN, y, INSIDE_W - 2 * MARGIN, lines * LABEL_H)
    On Error Resume Next
    lbl.Font.Bold = True
    Err.Clear
    On Error GoTo 0
End Sub

' A label; named lbl & a serial unless a name is given (the spacing labels are
' found again by key, for tooltips and messages).
Private Function AddLabel(ByVal text As String, ByVal x As Double, ByVal y As Double, ByVal w As Double, Optional ByVal h As Double = LABEL_H, Optional ByVal nm As String = "") As Object
    Dim lbl As Object
    If nm = "" Then
        mSerial = mSerial + 1
        nm = "lbl" & CStr(mSerial)
    End If
    Set lbl = Me.Controls.Add("Forms.Label.1", nm, True)
    On Error Resume Next
    lbl.Caption = text
    lbl.Left = x
    lbl.Top = y
    lbl.Width = w
    lbl.Height = h
    lbl.WordWrap = True
    Err.Clear
    On Error GoTo 0
    Set AddLabel = lbl
End Function

Private Function AddBox(ByVal nm As String, ByVal x As Double, ByVal y As Double, ByVal w As Double) As Object
    Dim box As Object
    Set box = Me.Controls.Add("Forms.TextBox.1", nm, True)
    On Error Resume Next
    box.Left = x
    box.Top = y
    box.Width = w
    box.Height = BOX_H
    Err.Clear
    On Error GoTo 0
    Set AddBox = box
End Function

' A check box, named flg & nm so FlagValue and SetFlag find it.
Private Sub AddCheck(ByVal nm As String, ByVal caption As String, ByVal x As Double, ByVal y As Double, ByVal w As Double)
    Dim c As Object
    Set c = Me.Controls.Add("Forms.CheckBox.1", "flg" & nm, True)
    On Error Resume Next
    c.Caption = caption
    c.Left = x
    c.Top = y
    c.Width = w
    c.Height = ROW_H - 3
    Err.Clear
    On Error GoTo 0
End Sub

' An option button in a named group, also flg & nm.
Private Sub AddOption(ByVal nm As String, ByVal group As String, ByVal caption As String, ByVal x As Double, ByVal y As Double, ByVal w As Double)
    Dim c As Object
    Set c = Me.Controls.Add("Forms.OptionButton.1", "flg" & nm, True)
    On Error Resume Next
    c.GroupName = group
    c.Caption = caption
    c.Left = x
    c.Top = y
    c.Width = w
    c.Height = ROW_H - 3
    Err.Clear
    On Error GoTo 0
End Sub

Private Function AddButton(ByVal nm As String, ByVal caption As String, ByVal x As Double, ByVal y As Double, ByVal w As Double) As Object
    Dim b As Object
    Set b = Me.Controls.Add("Forms.CommandButton.1", nm, True)
    On Error Resume Next
    b.Caption = caption
    b.Left = x
    b.Top = y
    b.Width = w
    b.Height = BTN_H
    Err.Clear
    On Error GoTo 0
    Set AddButton = b
End Function

' What each spacing box means, as its tooltip. The same words as README.md.
Private Function SpacingTip(ByVal key As String) As String
    Dim s As String
    Select Case key
        Case "ExampleBefore"
            s = "Space above the example, on its first row. Empty: 0."
        Case "ExampleAfter"
            s = "Space below the example: after the translation, or after the last row when there is none. Empty: 3."
        Case "ExampleLeft"
            s = "Left indent of every NEW example. Empty: a new example takes the indent of the paragraph it is inserted into. Indent and Outdent, and the ruler, still move an example already on the page."
        Case "ExampleRight"
            s = "Right indent: the wrap lines and the translation stop this far short of the right margin. Empty: 0."
        Case "LineGap"
            s = "Space between the wrap lines of an example, under the last tier of each wrap line but the last. Empty: 6."
        Case "ContIndent"
            s = "Extra indent of every wrap line after the first. Empty: 0, a flush-left continuation that keeps the columns of long examples comparable."
        Case "TierGap"
            s = "Space between the tiers of one wrap line, under every tier row but the last of its wrap line. Empty: 0."
        Case "Gap"
            s = "Space between alignment columns, added to the right of every column's widest cell. Empty: 6."
        Case "NumberHang"
            s = "Width of the number column, the cell that holds (1), (2)... at the start of every row of a numbered example. Empty: 36."
        Case "PadLeft", "PadRight"
            s = "Cell padding inside every cell; the columns are widened to keep the text at its measured width, and the table's edge moves out so the text stays at the example's indent, level with the translation. Empty: 0."
        Case "PadTop", "PadBottom"
            s = "Cell padding inside every cell of every row. Empty: 0."
        Case "FreeAbove"
            s = "Space between the last row and the first translation. Empty: 6, half a line."
        Case "FreeBetween"
            s = "Space between two translations, after every translation paragraph but the last. Empty: 0."
    End Select
    SpacingTip = s & " Points, or a percentage of the font size (50% is half a line)."
End Function


'=============================================================================
' -- LOADING AND APPLYING ---------------------------------------------------
'=============================================================================

' Fill every control from the document's settings, and remember the document.
Public Sub LoadFrom(doc As Document)
    Dim keys() As String
    Dim i As Long
    Set mDoc = doc
    Result = ""
    If doc Is Nothing Then Exit Sub
    keys = Split(SPACING_KEYS, "|")
    For i = 0 To UBound(keys)
        SetBoxText keys(i), SpacingText(doc, keys(i))
    Next i
    SetBoxText "NumberLevel", CStr(SettingNumberLevel(doc))
    SetFlag "Word", (SettingGranularity(doc) = igtWordAligned)
    SetFlag "Morpheme", (SettingGranularity(doc) = igtMorphemeAligned)
    SetFlag "Number", SettingNumberExamples(doc)
    SetFlag "SmallCaps", SettingLowercaseGramGloss(doc)
    SetFlag "InitialCap", SettingGramGlossInitialCap(doc)
    SetFlag "RewrapSave", SettingRewrapOnSave(doc)
    SetFlag "RewrapLeave", SettingRewrapOnSelectionChange(doc)
    SetFlag "Dot", (SettingSpaceReplacement(doc) = ".")
    SetFlag "Underscore", (SettingSpaceReplacement(doc) = "_")
    On Error Resume Next
    Me.Caption = "LingTeX-Word Settings  -  " & doc.Name
    Err.Clear
    On Error GoTo 0
End Sub

'-----------------------------------------------------------------------------
' Write every control back to the document and re-wrap it, so the page shows
' the result behind the form. Every box is checked BEFORE anything is stored,
' so a slip in one box leaves the document exactly as it was, and the message
' names the box. False when something was refused.
'-----------------------------------------------------------------------------
Public Function ApplyNow() As Boolean
    Dim keys() As String
    Dim i As Long
    Dim t As String
    Dim lvl As Double
    Dim msg As String

    If mDoc Is Nothing Then Exit Function
    keys = Split(SPACING_KEYS, "|")
    For i = 0 To UBound(keys)
        If Not IsValidSpacingText(BoxText(keys(i))) Then
            msg = "The box " & BoxLabel(keys(i)) & " holds """ & BoxText(keys(i)) & """."
            msg = msg & vbCr & vbCr & "Type a number of points, such as 6 or 4.5, or leave the box empty for the default."
            Report msg, vbExclamation
            FocusBox keys(i)
            Exit Function
        End If
    Next i
    t = Trim$(BoxText("NumberLevel"))
    If t = "" Then t = "1"
    lvl = -1
    If Len(t) = 1 Then
        If t >= "1" And t <= "9" Then lvl = Val(t)
    End If
    If lvl < 1 Then
        Report "The list level must be a single digit from 1 to 9.", vbExclamation
        FocusBox "NumberLevel"
        Exit Function
    End If

    For i = 0 To UBound(keys)
        SetSpacingText mDoc, keys(i), BoxText(keys(i))
    Next i
    SetSettingNumberLevel mDoc, CLng(lvl)
    If FlagValue("Morpheme") Then
        SetSettingGranularity mDoc, igtMorphemeAligned
    Else
        SetSettingGranularity mDoc, igtWordAligned
    End If
    SetSettingNumberExamples mDoc, FlagValue("Number")
    SetSettingLowercaseGramGloss mDoc, FlagValue("SmallCaps")
    SetSettingGramGlossInitialCap mDoc, FlagValue("InitialCap")
    SetSettingRewrapOnSave mDoc, FlagValue("RewrapSave")
    SetSettingRewrapOnSelectionChange mDoc, FlagValue("RewrapLeave")
    If FlagValue("Underscore") Then
        SetSettingSpaceReplacement mDoc, "_"
    Else
        SetSettingSpaceReplacement mDoc, "."
    End If

    ' Widths measured under the old settings are stale (the small-capitals
    ' convention is part of the cache key, but not everything is).
    ClearCache
    RewrapDocument mDoc, False
    RefreshRibbon
    ApplyNow = True
End Function


' Every box and tick back to what a fresh document gets -- the defaults in
' modSettings, so this cannot drift from them. The document is untouched
' until OK or Apply; the styles have their own Reset buttons.
Public Sub RestoreDefaultFields()
    Dim keys() As String
    Dim flags() As String
    Dim i As Long
    keys = Split(SPACING_KEYS, "|")
    For i = 0 To UBound(keys)
        SetBoxText keys(i), ""
    Next i
    SetBoxText "NumberLevel", CStr(DefaultNumberLevel())
    flags = Split("Word|Morpheme|Number|SmallCaps|InitialCap|RewrapSave|RewrapLeave|Dot|Underscore", "|")
    For i = 0 To UBound(flags)
        SetFlag flags(i), DefaultFlag(flags(i))
    Next i
End Sub


'=============================================================================
' -- THE CONTROLS BY NAME ---------------------------------------------------
'=============================================================================
' Public so the doc tests can drive the form without showing it.

' The text of a spacing box (or "NumberLevel"); "" when there is no such box.
Public Function BoxText(ByVal key As String) As String
    On Error Resume Next
    BoxText = Me.Controls("txt" & key).Text
    Err.Clear
    On Error GoTo 0
End Function

Public Sub SetBoxText(ByVal key As String, ByVal text As String)
    On Error Resume Next
    Me.Controls("txt" & key).Text = text
    Err.Clear
    On Error GoTo 0
End Sub

' The label beside a spacing box, for messages.
Private Function BoxLabel(ByVal key As String) As String
    On Error Resume Next
    BoxLabel = Me.Controls("lbl" & key).Caption
    Err.Clear
    On Error GoTo 0
    If BoxLabel = "" Then BoxLabel = key
End Function

Private Sub FocusBox(ByVal key As String)
    On Error Resume Next
    Me.Controls("txt" & key).SetFocus
    Err.Clear
    On Error GoTo 0
End Sub

' A check box or option button, by the name it was added under.
Public Function FlagValue(ByVal nm As String) As Boolean
    On Error Resume Next
    FlagValue = (Me.Controls("flg" & nm).Value = True)
    Err.Clear
    On Error GoTo 0
End Function

Public Sub SetFlag(ByVal nm As String, ByVal v As Boolean)
    On Error Resume Next
    Me.Controls("flg" & nm).Value = v
    Err.Clear
    On Error GoTo 0
End Sub

' The style slot selected in the list (modStyles' order); 0 when none is.
Public Function SelectedSlot() As Long
    Dim i As Long
    On Error Resume Next
    i = Me.Controls("lstStyles").ListIndex
    If Err.Number <> 0 Then i = 0
    Err.Clear
    On Error GoTo 0
    If i < 0 Then i = 0
    SelectedSlot = i
End Function

Public Function StyleCount() As Long
    On Error Resume Next
    StyleCount = Me.Controls("lstStyles").ListCount
    Err.Clear
    On Error GoTo 0
End Function


'=============================================================================
' -- THE BUTTONS ------------------------------------------------------------
'=============================================================================

Private Sub mOK_Click()
    If ApplyNow() Then
        Result = "ok"
        Me.Hide
    End If
End Sub

Private Sub mApply_Click()
    Dim ok As Boolean
    ok = ApplyNow()
End Sub

Private Sub mCancel_Click()
    Result = "cancel"
    Me.Hide
End Sub

Private Sub mDefaults_Click()
    RestoreDefaultFields
End Sub

' Step aside and let the caller open Word's Style dialog; see the header.
Private Sub mModify_Click()
    Result = "modify"
    Me.Hide
End Sub

Private Sub mResetStyle_Click()
    Dim msg As String
    If mDoc Is Nothing Then Exit Sub
    msg = "Reset the style " & StyleSlotName(SelectedSlot()) & " to follow this document's Normal style again, and re-wrap every example?"
    msg = msg & vbCr & vbCr & "Anything set on this style by hand -- font, size, colour, spacing -- is replaced."
    If Not Confirm(msg) Then Exit Sub
    ResetStyleSlot mDoc, SelectedSlot()
    ClearCache
    RewrapDocument mDoc, False
End Sub

Private Sub mResetAll_Click()
    Dim msg As String
    If mDoc Is Nothing Then Exit Sub
    msg = "Reset the six tier styles (Vernacular, Morphemes, Gloss, Word Gloss, Category, Free Translation) to follow this document's Normal style, and re-wrap every example?"
    msg = msg & vbCr & vbCr & "Any font or size you set on them yourself is replaced."
    If Not Confirm(msg) Then Exit Sub
    ResetParaStylesToBody mDoc
    RewrapDocument mDoc, False
End Sub

' The close box behaves as Cancel and the form STAYS LOADED, so the caller can
' read Result and Unload once. Closed by the box, the form would be unloaded
' under the caller, whose next touch would re-create it from scratch.
Private Sub UserForm_QueryClose(Cancel As Integer, CloseMode As Integer)
    If CloseMode = 0 Then
        Cancel = 1
        Result = "cancel"
        Me.Hide
    End If
End Sub
