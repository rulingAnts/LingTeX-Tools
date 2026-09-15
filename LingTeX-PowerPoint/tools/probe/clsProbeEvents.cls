VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsProbeEvents"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'=============================================================================
' clsProbeEvents  --  LingTeX-PowerPoint
'
' Logs PowerPoint application events for modProbeEvents: every handler only
' appends a line to Events.<os>.txt through modProbeEvents.LogEvent.
'
' WithEvents needs the real type, so this names PowerPoint.Application.  A
' handler whose name matches no event on this platform is an ordinary
' procedure, so an event missing from Mac PowerPoint's type library cannot stop
' the class compiling: it simply never logs.  The signatures follow the
' PowerPoint object model; a wrong one would be a compile error.
'=============================================================================

Public WithEvents App As PowerPoint.Application

Private Sub App_WindowSelectionChange(ByVal Sel As Selection)
    Dim s As String
    On Error Resume Next
    s = "WindowSelectionChange  type " & Sel.Type
    If Sel.Type = 2 Or Sel.Type = 3 Then
        s = s & "  shape " & Sel.ShapeRange(1).Name & "  " & Format$(Sel.ShapeRange(1).Width, "0.0") & " wide"
    End If
    LogEvent s
End Sub

Private Sub App_AfterShapeSizeChange(ByVal shp As Shape)
    On Error Resume Next
    LogEvent "AfterShapeSizeChange  shape " & shp.Name & "  now " & Format$(shp.Width, "0.0") & " x " & Format$(shp.Height, "0.0")
End Sub

Private Sub App_SlideSelectionChanged(ByVal SldRange As SlideRange)
    On Error Resume Next
    LogEvent "SlideSelectionChanged  " & SldRange.Count & " slide(s)"
End Sub

Private Sub App_PresentationBeforeSave(ByVal Pres As Presentation, Cancel As Boolean)
    On Error Resume Next
    LogEvent "PresentationBeforeSave  " & Pres.Name
End Sub
