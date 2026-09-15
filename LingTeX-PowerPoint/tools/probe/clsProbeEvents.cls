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
' Logs PowerPoint application events for modProbeEvents.  Only events in the
' probe presentation (tagged LINGTEXPROBE) are described; any other event is
' only counted, so no name from anyone's own presentations reaches a report.
'
' WithEvents needs the real type, so this names PowerPoint.Application.  A
' handler whose name matches no event on this platform is an ordinary
' procedure, so an event missing from Mac PowerPoint's type library cannot
' stop the class compiling: it simply never logs.  The signatures follow the
' PowerPoint object model; a wrong one would be a compile error.
'
' Whether an event is the probe's is worked out into a Boolean first: under
' On Error Resume Next, an error inside an If condition skips to the next
' line, which would be the logging.
'=============================================================================

Public WithEvents App As PowerPoint.Application

Private Sub App_WindowSelectionChange(ByVal Sel As Selection)
    Dim mine As Boolean, s As String
    On Error Resume Next
    mine = False
    mine = IsProbePresentation(App.ActiveWindow.Presentation)
    If Not mine Then
        CountOtherEvent
        Exit Sub
    End If
    s = "WindowSelectionChange  type " & Sel.Type
    If Sel.Type = 2 Or Sel.Type = 3 Then
        s = s & "  shape " & Sel.ShapeRange(1).Name & "  " & Format$(Sel.ShapeRange(1).Width, "0.0") & " wide"
    End If
    LogEvent s
End Sub

Private Sub App_AfterShapeSizeChange(ByVal shp As Shape)
    Dim mine As Boolean
    On Error Resume Next
    mine = False
    mine = IsProbePresentation(shp.Parent.Parent)
    If Not mine Then
        CountOtherEvent
        Exit Sub
    End If
    LogEvent "AfterShapeSizeChange  shape " & shp.Name & "  now " & Format$(shp.Width, "0.0") & " x " & Format$(shp.Height, "0.0")
End Sub

Private Sub App_SlideSelectionChanged(ByVal SldRange As SlideRange)
    Dim mine As Boolean
    On Error Resume Next
    mine = False
    mine = IsProbePresentation(App.ActiveWindow.Presentation)
    If Not mine Then
        CountOtherEvent
        Exit Sub
    End If
    LogEvent "SlideSelectionChanged  " & SldRange.Count & " slide(s)"
End Sub

Private Sub App_PresentationBeforeSave(ByVal Pres As Presentation, Cancel As Boolean)
    Dim mine As Boolean
    On Error Resume Next
    mine = False
    mine = IsProbePresentation(Pres)
    If Not mine Then
        CountOtherEvent
        Exit Sub
    End If
    LogEvent "PresentationBeforeSave  (the probe presentation)"
End Sub
