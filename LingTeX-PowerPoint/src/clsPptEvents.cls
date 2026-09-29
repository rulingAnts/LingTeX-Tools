VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsPptEvents"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'=============================================================================
' clsPptEvents  --  LingTeX-PowerPoint
'
' The add-in's application events.  Hooked by modPptCommands.LingTeXStart.
'
' RESIZE.  AfterShapeSizeChange fires once when the user lets go of a handle
' (probe round 4), so an example whose box was widened or narrowed re-wraps
' to its new width.  A re-wrap changes the box's height and hears its own
' event after the macro has returned (round 4 too), so a resize to exactly
' the size the last composition recorded (TAG_SIZE) is ignored, and gPptBusy
' keeps a command's own writes from starting one.  The setting
' RewrapOnResize turns it off.
'
' WithEvents needs the real type, so this names PowerPoint.Application.
' A handler whose name matches no event on this platform is an ordinary
' procedure, so an event missing from the Mac library cannot stop the class
' compiling.  Conditions are worked out into Booleans first: under On Error
' Resume Next an error inside an If skips to the next line.
'=============================================================================

Public WithEvents App As PowerPoint.Application

Private Sub App_AfterShapeSizeChange(ByVal shp As Shape)
    Dim mine As Boolean, wanted As Boolean, ours As Boolean
    On Error Resume Next
    If gPptBusy Then Exit Sub
    mine = False
    mine = IsLingTeXExample(shp)
    If Not mine Then Exit Sub
    wanted = False
    wanted = SettingRewrapOnResize(PresentationOf(shp))
    If Not wanted Then Exit Sub
    ours = False
    ours = SizeIsOurs(shp)
    If ours Then Exit Sub
    gPptBusy = True
    RewrapExample shp
    RecordSize shp
    ReleaseScratch
    gPptBusy = False
    Err.Clear
End Sub
