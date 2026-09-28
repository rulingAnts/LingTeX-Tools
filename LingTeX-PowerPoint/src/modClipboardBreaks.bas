Attribute VB_Name = "modClipboardBreaks"
Option Explicit
'=============================================================================
' modClipboardBreaks  --  LingTeX-PowerPoint  --  A STUB, TO BE DELETED
'
' The clipboard-boundary normaliser, agreed with the line-break session
' (claude/lingtex-word-crlf) on 2026-09-28, who owns it and will write it in
' the shared modFlexParse so that Word, PowerPoint and the web tools repair a
' paste the same way.  Until it lands there, this module holds the SAME names
' so that PowerPoint compiles and its tests run against the real contract:
'
'   NormalizeClipboardText      the one call a clipboard reader makes
'   VerticalTabsToLineBreaks    Chr$(11) -> Chr$(10); a Shift+Return in FLEx
'                               is a ROW separator in a copy (in a Word
'                               document it is a soft break, which is why
'                               modIgtModel.CleanTextLine treats it as a space:
'                               same character, opposite meaning, decided by
'                               the source, so it is settled at the boundary)
'   CollapseDoubledLineBreaks   the lossy repair of a paste that doubled every
'                               break.  HERE AN IDENTITY: not written, on
'                               purpose -- it is the owner's, and it has
'                               design in it (below).  PowerPoint's tests for
'                               doubled breaks FAIL until the real one lands,
'                               and those failures are the measurement.
'   LineBreakRunProfile         diagnostics, e.g. "1x4,2x1": four runs of one
'                               break character, one run of two
'
' run-in-powerpoint.sh leaves this module out as soon as build/shared's
' modFlexParse defines NormalizeClipboardText, because two Public procedures
' of one name would not compile.  Then delete this file.
'
' WHAT THE REAL COLLAPSE WILL DO (so the tests here are right about it):
'   Run once, at the boundary, never inside the parser (ParseFlexBlocks
'   normalises twice per parse, and halving is not idempotent: all-4 halves to
'   all-2, which halves again, and a blank line between two examples is gone).
'   Decide on the WHOLE payload: let m be the shortest run of breaks; collapse
'   only if m is even and every run is a multiple of m; then divide every run
'   by m.  When the test says no, do NOT collapse -- an over-split example is
'   visible and recoverable by hand, a silently merged one is neither.
'   Guard with LooksLikeFlex: in FLEx output the tier rows of one block are
'   adjacent, one break apart, so an all-even payload can only be a doubled
'   one; for other text a blank line means what it says.
'
' Break characters are Chr$(13), Chr$(10) and Chr$(11), never vbCrLf or
' vbNewLine (Mac VBA's vbCrLf is LF CR).  Pure ASCII.
'=============================================================================

' Vertical tabs first, so that their runs count in the doubling test; then the
' lossless map to LF (the parser's own); then, for FLEx text only, the collapse.
Public Function NormalizeClipboardText(ByVal s As String) As String
    s = VerticalTabsToLineBreaks(s)
    s = NormalizeLineBreaks(s)
    If LooksLikeFlex(s) Then s = CollapseDoubledLineBreaks(s)
    NormalizeClipboardText = s
End Function

Public Function VerticalTabsToLineBreaks(ByVal s As String) As String
    VerticalTabsToLineBreaks = Replace(s, Chr$(11), Chr$(10))
End Function

' STUB: returns its input.  See the header.
Public Function CollapseDoubledLineBreaks(ByVal s As String) As String
    CollapseDoubledLineBreaks = s
End Function

' The lengths of the maximal runs of break characters (CR, LF, VT) in s, as
' "<length>x<count>" pairs, shortest first.  "" when there is no break.
Public Function LineBreakRunProfile(ByVal s As String) As String
    Dim i As Long, n As Long, run As Long, k As Long, j As Long
    Dim lens() As Long, counts() As Long, nKinds As Long
    Dim ch As String, out As String, tmp As Long
    n = Len(s)
    ReDim lens(0 To 0): ReDim counts(0 To 0)
    For i = 1 To n + 1
        If i <= n Then ch = Mid$(s, i, 1) Else ch = ""
        If ch = Chr$(13) Or ch = Chr$(10) Or ch = Chr$(11) Then
            run = run + 1
        ElseIf run > 0 Then
            For k = 0 To nKinds - 1
                If lens(k) = run Then Exit For
            Next
            If k = nKinds Then
                ReDim Preserve lens(0 To nKinds): ReDim Preserve counts(0 To nKinds)
                lens(nKinds) = run: counts(nKinds) = 0
                nKinds = nKinds + 1
            End If
            counts(k) = counts(k) + 1
            run = 0
        End If
    Next
    For i = 0 To nKinds - 2
        For j = i + 1 To nKinds - 1
            If lens(j) < lens(i) Then
                tmp = lens(i): lens(i) = lens(j): lens(j) = tmp
                tmp = counts(i): counts(i) = counts(j): counts(j) = tmp
            End If
        Next
    Next
    For i = 0 To nKinds - 1
        If i > 0 Then out = out & ","
        out = out & lens(i) & "x" & counts(i)
    Next
    LineBreakRunProfile = out
End Function
