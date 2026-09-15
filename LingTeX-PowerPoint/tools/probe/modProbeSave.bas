Attribute VB_Name = "modProbeSave"
Option Explicit

'=============================================================================
' modProbeSave  --  LingTeX-PowerPoint
'
' PROBE ROUND 6: UNDO ENTRIES, WHAT A PASTE LEAVES ALONE, SAVE FORMAT NUMBERS.
'
'   ProbeRound6Quiet  runs all three parts and writes Round6.<os>.txt.  Nobody
'                     needs to be at the keyboard.
'
'   1. Undo.  Does PowerPoint have Word's Application.UndoRecord (named undo)?
'      Does Application.StartNewUndoEntry exist here?
'   2. Paste.  Round 5 showed one TextRange2.Paste replaces an example's text
'      as one undo step.  Does that paste leave the box itself alone: its
'      name, Id, position, size, Tags, margins, wrap and AutoSize?
'   3. Save formats.  SaveCopyAs with no format and with every format number
'      from 0 to 40, into a new folder under PowerPoint's Documents folder.
'      The report gives each number's error, or its time; the script lists the
'      files each number wrote.  37, 39 and 40 are skipped: on Windows they
'      are video and animated GIF, which can run for a long time.  The report
'      is rewritten after every number, so a hang still leaves it.
'      12 is always skipped now.  On the Mac it writes a movie (.mov) in the
'      background; round 6 then closed the presentation while that was still
'      running, and PowerPoint crashed three seconds later (2026-09-15).
'      Never export a movie or pictures and close the presentation in the
'      same run.
'
' It uses the clipboard, and makes and closes its own windowless
' presentations.  Pure ASCII, and numbers instead of named constants.
'=============================================================================

Private Const SCAN_DIR As String = "LingTeX-PowerPoint-savescan"

Private mOut As String
Private mReport As String

' The second scan: format numbers 37 to 120.  Round 6 found no macro-enabled
' or add-in format below 41, so PowerPoint for Mac numbers them differently
' from Windows.  37, 39 and 40 are included this time: round 6's movie format
' (12) took no time on a one-slide presentation.  Writes SaveScan2.<os>.txt.
Public Sub ProbeSaveScan2Quiet()
    Dim app As Object
    Set app = Application
    mReport = "SaveScan2"
    mOut = "Save format scan 2  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & vbLf
    On Error GoTo Crash
    ProbeSaveFormats app, 37, 120, False
    Flush
    Exit Sub
Crash:
    Say "CRASH: " & Err.Number & ": " & Err.Description
    Flush
End Sub

Public Sub ProbeRound6Quiet()
    Dim app As Object
    Set app = Application
    mReport = "Round6"
    mOut = "Probe round 6  " & Format$(Now, "yyyy-mm-dd hh:nn:ss") & vbLf
    On Error Resume Next
    mOut = mOut & "PowerPoint " & app.Version & vbLf
    mOut = mOut & "build " & app.Build & vbLf
    mOut = mOut & "system " & app.OperatingSystem & vbLf
    Err.Clear
    On Error GoTo Crash
    Say ""
    ProbeUndoApi app
    Say ""
    ProbePasteKeepsBox app
    Say ""
    ProbeSaveFormats app, 0, 40, True
    Flush
    Exit Sub
Crash:
    Say "CRASH: " & Err.Number & ": " & Err.Description
    Flush
End Sub

'-----------------------------------------------------------------------------
' 1. Undo
'-----------------------------------------------------------------------------
Private Sub ProbeUndoApi(ByVal app As Object)
    Dim u As Object
    Say "1. Undo"
    On Error Resume Next
    Err.Clear
    Set u = app.UndoRecord
    If Err.Number <> 0 Then
        Say "   Application.UndoRecord: error " & Err.Number & ": " & Err.Description
    Else
        Say "   Application.UndoRecord: exists (" & TypeName(u) & ")"
    End If
    Err.Clear
    app.StartNewUndoEntry
    If Err.Number <> 0 Then
        Say "   Application.StartNewUndoEntry: error " & Err.Number & ": " & Err.Description
    Else
        Say "   Application.StartNewUndoEntry: ran with no error"
    End If
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
' 2. What one TextRange2.Paste leaves alone
'-----------------------------------------------------------------------------
Private Sub ProbePasteKeepsBox(ByVal app As Object)
    Dim target As Object, scratch As Object, tb As Object, sb As Object
    Dim before As String, after As String
    Say "2. What one TextRange2.Paste leaves alone"
    On Error Resume Next

    Set target = app.Presentations.Add(0)
    Set tb = target.Slides.Add(1, 12).Shapes.AddTextbox(1, 100, 120, 400, 60)
    If Err.Number <> 0 Or tb Is Nothing Then
        Say "   PROBLEM: making the target box: " & Err.Number & ": " & Err.Description
        GoTo Done
    End If
    tb.Name = "LingTeXKeepMe"
    tb.Tags.Add "LINGTEX", "example-1"
    tb.Tags.Add "LINGTEXWIDTH", "400"
    With tb.TextFrame2
        .WordWrap = -1
        .AutoSize = 1
        .MarginLeft = 3
        .MarginRight = 4
        .MarginTop = 5
        .MarginBottom = 6
        .TextRange.Text = "old" & Chr$(9) & "example"
    End With
    If Err.Number <> 0 Then
        Say "   PROBLEM: setting up the target box: " & Err.Number & ": " & Err.Description
        GoTo Done
    End If
    before = BoxState(tb)

    Set scratch = app.Presentations.Add(0)
    Set sb = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, 400, 60)
    sb.TextFrame2.TextRange.Text = "new" & Chr$(9) & "example" & Chr$(13) & "second" & Chr$(9) & "line"
    sb.TextFrame2.TextRange.Paragraphs(1).ParagraphFormat.TabStops.Add 1, 80
    sb.TextFrame2.TextRange.Copy
    If Err.Number <> 0 Then
        Say "   PROBLEM: composing or copying the new text: " & Err.Number & ": " & Err.Description
        GoTo Done
    End If

    tb.TextFrame2.TextRange.Paste
    If Err.Number <> 0 Then
        Say "   PROBLEM: TextRange2.Paste: " & Err.Number & ": " & Err.Description
        GoTo Done
    End If
    after = BoxState(tb)
    Say "   text after the paste: '" & Esc(tb.TextFrame2.TextRange.Text) & "'"
    CompareStates before, after

Done:
    Err.Clear
    If Not scratch Is Nothing Then
        scratch.Saved = -1
        scratch.Close
    End If
    If Not target Is Nothing Then
        target.Saved = -1
        target.Close
    End If
    Err.Clear
End Sub

' The box as one string of key=value items separated by "|".
Private Function BoxState(ByVal shp As Object) As String
    Dim s As String, i As Long, t As String
    On Error Resume Next
    s = "name=" & shp.Name
    s = s & "|id=" & shp.Id
    s = s & "|left=" & Format$(shp.Left, "0.0")
    s = s & "|top=" & Format$(shp.Top, "0.0")
    s = s & "|width=" & Format$(shp.Width, "0.0")
    s = s & "|height=" & Format$(shp.Height, "0.0")
    t = ""
    For i = 1 To shp.Tags.Count
        If i > 1 Then t = t & ";"
        t = t & shp.Tags.Name(i) & "=" & shp.Tags.Value(i)
    Next
    s = s & "|tags=" & t
    s = s & "|autosize=" & shp.TextFrame2.AutoSize
    s = s & "|wordwrap=" & shp.TextFrame2.WordWrap
    s = s & "|margins=" & shp.TextFrame2.MarginLeft & "," & shp.TextFrame2.MarginRight & "," & _
            shp.TextFrame2.MarginTop & "," & shp.TextFrame2.MarginBottom
    s = s & "|zorder=" & shp.ZOrderPosition
    Err.Clear
    BoxState = s
End Function

Private Sub CompareStates(ByVal before As String, ByVal after As String)
    Dim a As Variant, b As Variant, i As Long, key As String, va As String, vb As String, p As Long
    a = Split(before, "|")
    b = Split(after, "|")
    If UBound(a) <> UBound(b) Then
        Say "   PROBLEM: the two states have different items"
        Say "   before: " & before
        Say "   after:  " & after
        Exit Sub
    End If
    For i = LBound(a) To UBound(a)
        p = InStr(a(i), "=")
        key = Left$(a(i), p - 1)
        va = Mid$(a(i), p + 1)
        vb = Mid$(b(i), InStr(b(i), "=") + 1)
        If va = vb Then
            Say "   " & key & ": same (" & va & ")"
        Else
            Say "   " & key & ": changed from " & va & " to " & vb
        End If
    Next
End Sub

'-----------------------------------------------------------------------------
' 3. SaveCopyAs format numbers
'-----------------------------------------------------------------------------
Private Sub ProbeSaveFormats(ByVal app As Object, ByVal fromN As Long, ByVal toN As Long, _
                             ByVal skipVideo As Boolean)
    Dim pres As Object, folder As String, fmt As Long, t0 As Single
    Say "3. SaveCopyAs format numbers " & fromN & " to " & toN
    On Error Resume Next

    folder = DevDocuments() & PSep() & SCAN_DIR
    MkDir folder
    Err.Clear
    folder = folder & PSep() & Format$(Now, "yyyymmdd-hhnnss")
    MkDir folder
    If Err.Number <> 0 Then
        Say "   PROBLEM: could not make the folder " & folder & ": " & Err.Number & ": " & Err.Description
        Exit Sub
    End If
    Say "   folder: " & folder

    Set pres = app.Presentations.Add(0)
    pres.Slides.Add(1, 12).Shapes.AddTextbox(1, 50, 50, 300, 40).TextFrame2.TextRange.Text = "save scan"
    If Err.Number <> 0 Then
        Say "   PROBLEM: making the presentation to save: " & Err.Number & ": " & Err.Description
        Exit Sub
    End If
    Flush

    If fromN = 0 Then
        Err.Clear
        t0 = Timer
        pres.SaveCopyAs folder & PSep() & "fdefault"
        SayResult "no format", t0
        Flush
    End If

    For fmt = fromN To toN
        If fmt = 12 Or (skipVideo And (fmt = 37 Or fmt = 39 Or fmt = 40)) Then
            Say "   " & Format$(fmt, "00") & ": skipped"
        Else
            Err.Clear
            t0 = Timer
            pres.SaveCopyAs folder & PSep() & "f" & Format$(fmt, "000"), fmt
            SayResult Format$(fmt, "000"), t0
        End If
        Flush
    Next

    Err.Clear
    pres.Saved = -1
    pres.Close
    Err.Clear
End Sub

Private Sub SayResult(ByVal label As String, ByVal t0 As Single)
    If Err.Number <> 0 Then
        Say "   " & label & ": error " & Err.Number & ": " & Err.Description
    Else
        Say "   " & label & ": no error (" & Format$(Timer - t0, "0.00") & " s)"
    End If
    Err.Clear
End Sub

'-----------------------------------------------------------------------------
' Helpers
'-----------------------------------------------------------------------------
Private Sub Say(ByVal s As String)
    mOut = mOut & s & vbLf
End Sub

Private Sub Flush()
    If mReport = "" Then mReport = "Round6"
    WriteDevReport mReport, mOut
End Sub

Private Function PSep() As String
#If Mac Then
    PSep = "/"
#Else
    PSep = "\"
#End If
End Function

Private Function Esc(ByVal s As String) As String
    s = Replace(s, Chr$(9), "\t")
    s = Replace(s, Chr$(13), "\r")
    s = Replace(s, Chr$(11), "\v")
    Esc = Replace(s, Chr$(10), "\n")
End Function
