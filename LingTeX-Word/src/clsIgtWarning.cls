VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsIgtWarning"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'=============================================================================
' clsIgtWarning  --  LingTeX-Word
'
' One finding from modLeipzig.CheckExample.
'
' This is a class rather than a Type because VBA cannot store a user-defined
' type in a Collection or a Variant, and the checks return a variable number of
' findings.  It is a plain data holder: no behaviour, no Word objects.
'
' Code        stable identifier, safe to branch on (see modLeipzig)
' Column      alignment column the finding is about, or -1 for the whole example
' Tier        tier role the finding is about, or "" when it spans the column
' Message     text shown to the user
' Fixable     True when modLeipzig can repair it without a human decision
'=============================================================================

Public Code     As String
Public Column   As Long
Public Tier     As String
Public Message  As String
Public Fixable  As Boolean

Private Sub Class_Initialize()
    Column = -1
End Sub

' Human-readable one-liner, used by the warnings list and by modTests.
Public Function Describe() As String
    Dim s As String
    s = Code
    If Column >= 0 Then s = s & " col " & CStr(Column + 1)
    If Tier <> "" Then s = s & " (" & Tier & ")"
    Describe = s & ": " & Message
End Function
