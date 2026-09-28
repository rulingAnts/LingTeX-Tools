Attribute VB_Name = "modPptTests"
Option Explicit
'=============================================================================
' modPptTests  --  LingTeX-PowerPoint
'
' The suite that runs inside PowerPoint, through the dev rig:
'
'     sh LingTeX-PowerPoint/tools/run-in-powerpoint.sh --tests
'
' It writes LingTeX-PowerPoint-reports/Tests.<os>.txt, one PASS or FAIL a line
' and a summary, as LingTeX-Word's RunAllTests does.  Four sections:
'
'   1. The shared LingTeX-Word modules are present and answer (modFlexParse,
'      modIgtModel, clsIgtWarning, modLeipzig, modWrap, staged into
'      build/shared by tools/stage-shared.sh).
'   2. The fixture road: what Insert will do up to the point where drawing
'      starts, on the made-up sample.  The expected numbers come from the JS
'      reference (LingTeX-Word/tools/reference.js buildModels on the same file,
'      2026-09-28): one block, tiers Morphemes and Gloss, 15 word-aligned
'      columns, 22 morpheme-aligned, one free line.
'   3. Line breaks.  The same fixture joined with every break sequence a paste
'      can produce, through NormalizeClipboardText and ParseFlexBlocks.  The
'      cases marked "awaits CollapseDoubledLineBreaks" FAIL until the shared
'      collapse lands (modClipboardBreaks is a stub); they are the acceptance
'      test for it, and the measurement of what PowerPoint still gets wrong.
'   4. The live clipboard: what run-in-powerpoint.sh put there (the same
'      fixture, CR LF unless LINGTEX_CLIP_EOL=lf), read through the paste,
'      its counts and run profile reported, then parsed.
'
' Pure ASCII apart from ChrW$ in the generated fixture.  Break characters are
' Chr$(13), Chr$(10), Chr$(11); never vbCrLf.
'=============================================================================

Private mPass As Long, mFail As Long, mLog As String

Public Sub PptTestsRun()
    mPass = 0: mFail = 0: mLog = ""
    Note "PptTestsRun  " & Format$(Now, "yyyy-mm-dd hh:nn:ss")
    On Error GoTo Crash
    SectionShared
    SectionFixtureRoad
    SectionLineBreaks
    SectionClipboard
    Note ""
    If mFail = 0 Then
        Note "ALL PASS -- " & mPass & " passed"
    Else
        Note "FAILURES -- " & mPass & " passed, " & mFail & " failed"
    End If
    WriteDevReport "Tests", mLog
    Exit Sub
Crash:
    Note "CRASH: " & Err.Number & ": " & Err.Description & "  (after " & mPass & " passed, " & mFail & " failed)"
    WriteDevReport "Tests", mLog
End Sub

'-----------------------------------------------------------------------------
' 1. The shared modules answer
'-----------------------------------------------------------------------------
Private Sub SectionShared()
    Dim ex As IgtExample, w As Collection, cw() As Double, nb() As Boolean, lines() As Long
    Note ""
    Note "== 1. The shared modules"
    Eq "NormalizeLineBreaks maps CR LF to LF", NormalizeLineBreaks("a" & Chr$(13) & Chr$(10) & "b"), "a" & Chr$(10) & "b"
    Eq "NormalizeLineBreaks maps CR to LF", NormalizeLineBreaks("a" & Chr$(13) & "b"), "a" & Chr$(10) & "b"
    ex = NewExample(2, 3)
    Eq "NewExample(2, 3)", ex.TierCount & "x" & ex.ColCount, "2x3"
    Ok "LooksLikeFlex(fixture)", LooksLikeFlex(Fixture(Chr$(10)))
    Ok "LooksLikeFlex(plain prose) is False", Not LooksLikeFlex("The children bought bread.")
    ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
    Set w = CheckExample(ex)
    Ok "CheckExample returns a Collection", Not w Is Nothing, "warnings: " & w.Count
    ReDim cw(0 To 2): cw(0) = 100: cw(1) = 200: cw(2) = 150
    ReDim nb(0 To 2)
    lines = ComputeWrapLines(cw, nb, 300, 0, 0)
    Ok "ComputeWrapLines plans wrap lines", UBound(lines) >= 0, "lines: " & (UBound(lines) - LBound(lines) + 1)
End Sub

'-----------------------------------------------------------------------------
' 2. The fixture road, numbers from reference.js
'-----------------------------------------------------------------------------
Private Sub SectionFixtureRoad()
    Dim blocks() As FlexBlock, models() As IgtExample, n As Long, ex As IgtExample
    Note ""
    Note "== 2. The fixture road (Insert, up to drawing)"
    blocks = ParseFlexBlocks(Fixture(Chr$(10)))
    Eq "ParseFlexBlocks: one block", BlockCount(blocks), 1
    If BlockCount(blocks) = 1 Then
        Eq "  the block has 2 tiers", blocks(LBound(blocks)).TierCount, 2
        Eq "  and 1 free line", blocks(LBound(blocks)).FreeCount, 1
    End If
    models = ModelsFromText(Fixture(Chr$(10)), igtWordAligned, n)
    Eq "ModelsFromText, word-aligned: one model", n, 1
    If n = 1 Then
        ex = models(LBound(models))
        Eq "  tiers", ex.TierCount, 2
        Eq "  tier 0 is Morphemes", ex.Tiers(LBound(ex.Tiers)), ROLE_MORPHEMES
        Eq "  tier 1 is Gloss", ex.Tiers(LBound(ex.Tiers) + 1), ROLE_GLOSS
        Eq "  15 word-aligned columns (reference.js)", ex.ColCount, 15
        Eq "  free lines", ex.FreeCount, 1
        If ex.FreeCount = 1 Then Eq "  the free translation", ex.FreeLines(LBound(ex.FreeLines)), "(When) she picked her yams early."
        Eq "  first form cell", GetCell(ex, 0, 0), "zel"
        Eq "  first gloss cell", GetCell(ex, 1, 0), "yam"
    End If
    models = ModelsFromText(Fixture(Chr$(10)), igtMorphemeAligned, n)
    Eq "ModelsFromText, morpheme-aligned: one model", n, 1
    If n = 1 Then Eq "  22 morpheme-aligned columns (reference.js)", models(LBound(models)).ColCount, 22
End Sub

'-----------------------------------------------------------------------------
' 3. Line breaks, through NormalizeClipboardText
'-----------------------------------------------------------------------------
Private Sub SectionLineBreaks()
    Dim CR As String, LF As String, VT As String, plain As String, once As String
    CR = Chr$(13): LF = Chr$(10): VT = Chr$(11)
    Note ""
    Note "== 3. Line breaks (each: the fixture joined by that sequence)"
    RoadCase "LF", Fixture(LF), 1
    RoadCase "CR LF (FLEx on Windows)", Fixture(CR & LF), 1
    RoadCase "CR (PowerPoint paragraphs)", Fixture(CR), 1
    RoadCase "CR CR, doubled  (awaits CollapseDoubledLineBreaks)", Fixture(CR & CR), 1
    RoadCase "LF CR, Mac VBA's vbCrLf  (awaits CollapseDoubledLineBreaks)", Fixture(LF & CR), 1
    RoadCase "VT between rows, Shift+Return", Fixture(VT), 1
    RoadCase "two examples, blank line, LF", Fixture(LF) & LF & Fixture(LF), 2
    RoadCase "two examples, blank line, CR LF", Fixture(CR & LF) & CR & LF & Fixture(CR & LF), 2
    RoadCase "two examples, doubled: CR CR rows, CR CR CR CR between  (awaits CollapseDoubledLineBreaks)", _
             Fixture(CR & CR) & CR & CR & Fixture(CR & CR), 2
    RoadCase "two examples, LF CR rows, LF CR LF CR between  (awaits CollapseDoubledLineBreaks)", _
             Fixture(LF & CR) & LF & CR & Fixture(LF & CR), 2
    ' The guard: text that is not FLEx keeps its blank line even when every run is even.
    plain = "a" & Chr$(9) & "b" & LF & LF & "c" & Chr$(9) & "d"
    Eq "not FLEx: a blank line survives NormalizeClipboardText", CountLF(NormalizeClipboardText(plain)), 2
    ' Applied twice, the boundary normaliser must change nothing the second time.
    once = NormalizeClipboardText(Fixture(CR & CR) & CR & CR & Fixture(CR & CR))
    Eq "NormalizeClipboardText is idempotent", NormalizeClipboardText(once), once
    Eq "LineBreakRunProfile on the doubled two-example text", LineBreakRunProfile(Fixture(CR & CR) & CR & CR & Fixture(CR & CR)), "2x5,4x1"
End Sub

'-----------------------------------------------------------------------------
' 4. The live clipboard
'-----------------------------------------------------------------------------
Private Sub SectionClipboard()
    Dim raw As String, note As String, s As String, n As Long, models() As IgtExample
    Note ""
    Note "== 4. The clipboard (what run-in-powerpoint.sh put there)"
    raw = ReadClipboardText(note)
    If note <> "" Then Note "  " & note
    Ok "ReadClipboardText returned text", raw <> ""
    If raw = "" Then Exit Sub
    Note "  arrived: " & Len(raw) & " characters; " & BreakCounts(raw) & "; runs " & LineBreakRunProfile(raw)
    Note "  " & Left$(EscapeBreaks(raw), 160)
    s = NormalizeClipboardText(raw)
    Note "  normalised: " & BreakCounts(s) & "; runs " & LineBreakRunProfile(s)
    Ok "  LooksLikeFlex", LooksLikeFlex(s)
    RoadCase "the clipboard parses as one example", raw, 1
    models = ModelsFromText(s, igtWordAligned, n)
    If n >= 1 Then Eq "  15 word-aligned columns", models(LBound(models)).ColCount, 15
End Sub

'-----------------------------------------------------------------------------
' Helpers
'-----------------------------------------------------------------------------
' raw through NormalizeClipboardText and ParseFlexBlocks: wantBlocks blocks,
' each with 2 tiers and 1 free line.
Private Sub RoadCase(ByVal label As String, ByVal raw As String, ByVal wantBlocks As Long)
    Dim s As String, blocks() As FlexBlock, i As Long, shape As String
    s = NormalizeClipboardText(raw)
    blocks = ParseFlexBlocks(s)
    If BlockCount(blocks) <> wantBlocks Then
        Fail label, "blocks: " & BlockCount(blocks) & ", want " & wantBlocks & "  (runs " & LineBreakRunProfile(raw) & " -> " & LineBreakRunProfile(s) & ")"
        Exit Sub
    End If
    For i = LBound(blocks) To UBound(blocks)
        If blocks(i).TierCount <> 2 Or blocks(i).FreeCount <> 1 Then
            shape = shape & " block" & (i - LBound(blocks) + 1) & ": " & blocks(i).TierCount & " tiers, " & blocks(i).FreeCount & " free;"
        End If
    Next
    If shape <> "" Then Fail label, Trim$(shape) & " (want 2 tiers, 1 free)" Else Pass label
End Sub

Private Function BlockCount(blocks() As FlexBlock) As Long
    If LBound(blocks) = -1 And UBound(blocks) = -1 Then Exit Function
    BlockCount = UBound(blocks) - LBound(blocks) + 1
End Function

Private Function CountLF(ByVal s As String) As Long
    CountLF = Len(s) - Len(Replace(s, Chr$(10), ""))
End Function

Private Sub Ok(ByVal label As String, ByVal cond As Boolean, Optional ByVal detail As String = "")
    If cond Then Pass label, detail Else Fail label, detail
End Sub

Private Sub Eq(ByVal label As String, ByVal got As Variant, ByVal want As Variant)
    If CStr(got) = CStr(want) Then
        Pass label
    Else
        Fail label, "got '" & EscapeBreaks(CStr(got)) & "', want '" & EscapeBreaks(CStr(want)) & "'"
    End If
End Sub

Private Sub Pass(ByVal label As String, Optional ByVal detail As String = "")
    mPass = mPass + 1
    Note "  PASS  " & label & IIf(detail <> "", "  (" & detail & ")", "")
End Sub

Private Sub Fail(ByVal label As String, Optional ByVal detail As String = "")
    mFail = mFail + 1
    Note "  FAIL  " & label & IIf(detail <> "", "  " & detail, "")
End Sub

Private Sub Note(ByVal s As String)
    mLog = mLog & s & Chr$(10)
End Sub

' The made-up sample LingTeX-Word/samples/checklist-sample.txt -- identical in
' structure to a real two-line FLEx copy (Morphemes and Lex. Gloss rows, then
' the free translation), joined by sep, with a break at the end as a FLEx copy
' has.  Generated from the file; do not edit by hand.
Public Function Fixture(ByVal sep As String) As String
    Dim T As String, r1 As String, r2 As String, r3 As String
    T = Chr$(9)
    r1 = "Morphemes" & T & "zel" & T & "vimo" & T & T & T & _
         "rixu" & T & T & T & "=xo" & T & "xu" & T & _
         "=zevi" & T & "Ozivela" & T & "ze" & T & ChrW$(&H2D0) & T & _
         "zel" & T & "vimo" & T & T & T & "rixu" & T & _
         T & T & "=xo" & T & "Vo" & T & "vu" & T & _
         "=ve" & T & "levo" & T & T & T & "=zi" & T & _
         "zo" & T & "z" & T & "zuvo" & T & "=ve" & T & _
         "=zi"
    r2 = T & "Lex. Gloss" & T & "yam" & T & T & "pick" & T & _
         ".CMP" & T & T & "stack" & T & ".CMP" & T & "SEQ" & _
         T & "3SG" & T & "all" & T & "P.N." & T & "ACMP" & _
         T & T & "yam" & T & T & "pick" & T & ".CMP" & _
         T & T & "stack" & T & ".CMP" & T & "SEQ" & T & _
         "P.N." & T & "fox" & T & "ERG" & T & T & "follow" & _
         T & ".CMP" & T & "REL" & T & "FOC" & T & "1SG" & _
         T & "dream" & T & "ABL" & T & "REL"
    r3 = "Free Eng (When) she picked her yams early."
    Fixture = r1 & sep & r2 & sep & r3 & sep
End Function
