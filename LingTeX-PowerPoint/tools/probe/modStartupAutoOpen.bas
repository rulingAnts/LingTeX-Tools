Attribute VB_Name = "modStartupAutoOpen"
Option Explicit

'=============================================================================
' modStartupAutoOpen  --  LingTeX-PowerPoint
'
' The Startup-folder load test, the way that needs no save format.  PowerPoint
' for Mac 16.112 would not save an add-in from VBA (SaveAs 30: "Invalid
' enumeration value"; 25: "Failed"; a bare name wrote a legacy .ppt named
' "<name>.ppam.ppt" -- modStartupProbe, 2026-09-15).  So this module is
' imported into the dev presentation, the runner copies that .pptm, changes the
' main part's content type to an add-in's and installs it in the Startup folder.
' When PowerPoint starts and loads it, Auto_Open writes StartupAddIn.<os>.txt.
' In a presentation (not an add-in) Auto_Open does not run, so it is harmless
' in the dev presentation itself.
'=============================================================================

Public Sub Auto_Open()
    Dim app As Object, fn As Integer, home As String, sep As String, i As Long, s As String
    On Error Resume Next
    Set app = Application
#If Mac Then
    sep = "/"
    s = "mac"
#Else
    sep = "\"
    s = "win"
#End If
    home = Environ$("HOME")
    If home = "" Then home = Environ$("USERPROFILE")
    fn = FreeFile
    Open home & sep & "Documents" & sep & "LingTeX-PowerPoint-reports" & sep & "StartupAddIn." & s & ".txt" For Output As #fn
    Print #fn, "Auto_Open ran at " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    For i = 1 To app.AddIns.Count
        Print #fn, "  add-in " & app.AddIns(i).Name & "  loaded " & app.AddIns(i).Loaded & _
                   ", autoload " & app.AddIns(i).AutoLoad & ", " & app.AddIns(i).FullName
    Next
    Close #fn
End Sub
