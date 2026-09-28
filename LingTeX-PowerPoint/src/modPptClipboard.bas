Attribute VB_Name = "modPptClipboard"
Option Explicit
'=============================================================================
' modPptClipboard  --  LingTeX-PowerPoint
'
' Reads the clipboard as text, the one way that works in PowerPoint for Mac
' with no window (probe rounds 2 and 3): paste it into a text box in a scratch
' presentation and read the text back.  Shapes.PasteSpecial is 438 here, and
' TextRange.PasteSpecial and View.PasteSpecial are not supported; TextRange2.
' Paste works, tabs intact, letters beyond ASCII intact.
'
' What arrives is PowerPoint's rendering of the clipboard, not its bytes:
' paragraph breaks are CR (Chr 13).  The probe saw the source's CR LF arrive
' DOUBLED (CR CR) and its LF arrive as one CR -- and the report in the repo
' shows two breaks arriving as two CRs, so the doubling depends on the source
' or the path and must be measured, not assumed.  ReadClipboardText therefore
' returns the text RAW, and everything that decides what a break means is in
' NormalizeClipboardText (the shared normaliser; modClipboardBreaks until it
' lands), called once, here, at the boundary.
'
' Pure ASCII; numbers instead of named constants (the Mac type library lacks
' some): Presentations.Add(0) is a presentation with no window, Slides.Add(1,
' 12) the blank layout, AddTextbox(1, ...) a horizontal text box.
'=============================================================================

' The clipboard's text, exactly as PowerPoint pastes it; "" and a note when the
' paste fails (nothing on the clipboard, or not text).
Public Function ReadClipboardText(Optional ByRef note As String) As String
    Dim app As Object, scratch As Object, shp As Object, s As String
    Set app = Application
    On Error GoTo Fail
    Set scratch = app.Presentations.Add(0)
    Set shp = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, 700, 80)
    shp.TextFrame2.TextRange.Paste
    s = shp.TextFrame2.TextRange.Text
    scratch.Saved = -1
    scratch.Close
    ReadClipboardText = s
    Exit Function
Fail:
    note = "ReadClipboardText: " & Err.Number & ": " & Err.Description
    On Error Resume Next
    If Not scratch Is Nothing Then
        scratch.Saved = -1
        scratch.Close
    End If
    ReadClipboardText = ""
End Function

' The clipboard's text as the parser should see it: read, then normalised
' once.  This is the road Insert takes.
Public Function ReadClipboardForParser(Optional ByRef note As String) As String
    Dim raw As String
    raw = ReadClipboardText(note)
    If raw = "" Then Exit Function
    ReadClipboardForParser = NormalizeClipboardText(raw)
End Function

' "tabs 7, CR 2, LF 0, VT 0": what a paste is made of, for reports and tests.
Public Function BreakCounts(ByVal s As String) As String
    BreakCounts = "tabs " & CountOf(s, Chr$(9)) & ", CR " & CountOf(s, Chr$(13)) & _
                  ", LF " & CountOf(s, Chr$(10)) & ", VT " & CountOf(s, Chr$(11))
End Function

' Breaks and tabs made visible: \t \r \n \v.
Public Function EscapeBreaks(ByVal s As String) As String
    s = Replace(s, Chr$(9), "\t")
    s = Replace(s, Chr$(13), "\r")
    s = Replace(s, Chr$(11), "\v")
    EscapeBreaks = Replace(s, Chr$(10), "\n")
End Function

Private Function CountOf(ByVal s As String, ByVal what As String) As Long
    If Len(what) = 0 Then Exit Function
    CountOf = (Len(s) - Len(Replace(s, what, ""))) \ Len(what)
End Function
