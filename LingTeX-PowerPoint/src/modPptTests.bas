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
'      can produce, through NormalizeClipboardText (shared, in modIgtModel since
'      2026-09-28: vertical tabs to LF and the doubled-break collapse, both only
'      for FLEx text; runs counted in break characters, before CR LF pairing)
'      and ParseFlexBlocks.  These are that normaliser's acceptance test.
'   4. The live clipboard: what run-in-powerpoint.sh put there (the same
'      fixture, CR LF unless LINGTEX_CLIP_EOL=lf), read through the paste,
'      its counts and run profile reported, then parsed.
'   5. Measuring: modPptMeasure and modPptFormat against the probe's numbers
'      ("neighbor-F" at 20 pt was 88.4 pt), the cache, small capitals, and
'      the whole fixture measured and handed to the shared planner.
'   6. Composing: the fixture drawn into a scratch box by modPptCompose and
'      inspected paragraph by paragraph -- count, the hanging number, tab
'      stops per line, italics, small capitals, the quoted free translation.
'   7. Insert: the fixture onto a slide of a scratch presentation as ONE
'      pasted shape, tagged; two examples in one copy as two boxes numbered
'      (1a), (1b); and the user's clipboard the same after as before.
'   8. Read-back and re-wrap: the inserted example reads back as the model
'      it came from (capitals restored from the small-cap runs); narrowing
'      the box re-wraps onto more lines, widening onto fewer, and a re-wrap
'      that changes nothing writes nothing.
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
    SectionMeasure
    SectionCompose
    SectionInsert
    SectionRewrap
    SectionSettings
    SectionCommands
    SectionRenumber
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
    Dim CR As String, LF As String, VT As String, plain As String, once As String, pasted As String
    CR = Chr$(13): LF = Chr$(10): VT = Chr$(11)
    Note ""
    Note "== 3. Line breaks (each: the fixture joined by that sequence)"
    RoadCase "LF", Fixture(LF), 1
    RoadCase "CR LF (FLEx on Windows)", Fixture(CR & LF), 1
    RoadCase "CR (PowerPoint paragraphs)", Fixture(CR), 1
    RoadCase "CR CR, doubled", Fixture(CR & CR), 1
    RoadCase "LF CR, Mac VBA's vbCrLf", Fixture(LF & CR), 1
    RoadCase "VT between rows, Shift+Return", Fixture(VT), 1
    RoadCase "two examples, blank line, LF", Fixture(LF) & LF & Fixture(LF), 2
    RoadCase "two examples, blank line, CR LF", Fixture(CR & LF) & CR & LF & Fixture(CR & LF), 2
    RoadCase "two examples, doubled: CR CR rows, CR CR CR CR between", _
             Fixture(CR & CR) & CR & CR & Fixture(CR & CR), 2
    RoadCase "two examples, LF CR rows, LF CR LF CR between", _
             Fixture(LF & CR) & LF & CR & Fixture(LF & CR), 2
    ' What the paste reports for a CR LF copy that ends in a break (section 4 measures it):
    ' the internal breaks doubled, the trailing one single, because the scratch box's last
    ' paragraph has no terminator. A run at either end of the payload is a terminator, not
    ' structure, and must not veto the collapse (the first live run failed here, 2026-09-28).
    pasted = Fixture(CR & CR): pasted = Left$(pasted, Len(pasted) - 1)
    RoadCase "one example, CR CR rows, trailing CR (what the paste reports)", pasted, 1
    RoadCase "two examples, doubled, trailing CR", Fixture(CR & CR) & CR & CR & pasted, 2
    Eq "LineBreakRunProfile of that", LineBreakRunProfile(Fixture(CR & CR) & CR & CR & pasted), "1x1,2x4,4x1"
    ' The guard: text that is not FLEx keeps its blank line even when every run is even.
    plain = "a" & Chr$(9) & "b" & LF & LF & "c" & Chr$(9) & "d"
    Eq "not FLEx: a blank line survives NormalizeClipboardText", CountLF(NormalizeClipboardText(plain)), 2
    ' The shared guard covers vertical tabs too: in text that is not FLEx a Chr$(11) is Word's
    ' soft break (CleanTextLine makes it a space), so it is left alone.
    Eq "not FLEx: a vertical tab is left alone", CountVT(NormalizeClipboardText("a" & Chr$(9) & "b" & VT & "c" & Chr$(9) & "d")), 1
    ' Applied twice, the boundary normaliser must change nothing the second time.
    once = NormalizeClipboardText(Fixture(CR & CR) & CR & CR & Fixture(CR & CR))
    Eq "NormalizeClipboardText is idempotent", NormalizeClipboardText(once), once
    Eq "LineBreakRunProfile on the doubled two-example text", LineBreakRunProfile(Fixture(CR & CR) & CR & CR & Fixture(CR & CR)), "2x5,4x1"
End Sub

'-----------------------------------------------------------------------------
' 4. The live clipboard
'-----------------------------------------------------------------------------
Private Sub SectionClipboard()
    Dim raw As String, clipNote As String, s As String, n As Long, models() As IgtExample
    Note ""
    Note "== 4. The clipboard (what run-in-powerpoint.sh put there)"
    raw = ReadClipboardText(clipNote)
    If clipNote <> "" Then Note "  " & clipNote
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
' 5. Measuring
'-----------------------------------------------------------------------------
Private Sub SectionMeasure()
    Dim tf As PptTierFont, w1 As Double, w2 As Double, w3 As Double, wCaps As Double, wSc As Double
    Dim ex As IgtExample, widths() As Double, fonts() As PptTierFont, t As Long
    Dim cw() As Double, nb() As Boolean, lines() As Long
    Note ""
    Note "== 5. Measuring (a scratch presentation with no window)"
    On Error GoTo Fail
    tf.Name = "Times New Roman": tf.Size = 20: tf.Italic = False
    w1 = MeasureText("neighbor-F", ROLE_VERNACULAR, tf)
    Ok "a form measures to a positive width", w1 > 0, Format$(w1, "0.0") & " pt; the probe measured 88.4"
    Ok "  within 80..100 pt of the probe's number", w1 > 80 And w1 < 100
    w2 = MeasureText("neighbor-F", ROLE_VERNACULAR, tf)
    Eq "  measured again: the cache gives the same width", w2, w1
    tf.Italic = True
    w3 = MeasureText("neighbor-F", ROLE_VERNACULAR, tf)
    Ok "  italic measures (a different key)", w3 > 0, Format$(w3, "0.0") & " pt"
    Eq "  empty text measures 0", MeasureText("", ROLE_VERNACULAR, tf), 0
    tf.Italic = False
    wCaps = MeasureText("ERG", ROLE_VERNACULAR, tf)
    wSc = MeasureText("ERG", ROLE_GLOSS, tf)
    Ok "  small capitals (gloss tier) are narrower than full capitals (form tier)", wSc < wCaps, Format$(wSc, "0.0") & " < " & Format$(wCaps, "0.0")
    Eq "  DisplayCellText lowercases the grammatical part only", DisplayCellText("follow.CMP=REL", ROLE_GLOSS, True, False), "follow.cmp=rel"
    Eq "  ...and leaves a form tier alone", DisplayCellText("follow.CMP", ROLE_MORPHEMES, True, False), "follow.CMP"
    Eq "  initial cap: 3SG -> 3Sg", DisplayCellText("3SG", ROLE_GLOSS, True, True), "3Sg"
    ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
    ReDim fonts(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        fonts(t) = tf
        fonts(t).Italic = (t = 0)
    Next t
    MeasureExample ex, fonts, widths
    Ok "MeasureExample fills tiers x columns", UBound(widths, 1) = ex.TierCount - 1 And UBound(widths, 2) = ex.ColCount - 1
    Ok "  the first form cell has a width", widths(0, 0) > 0, Format$(widths(0, 0), "0.0") & " pt for 'zel'"
    Ok "  the first gloss cell has a width", widths(1, 0) > 0, Format$(widths(1, 0), "0.0") & " pt for 'yam'"
    cw = ColumnWidths(ex, widths, 6)
    nb = NoBreakFlags(ex)
    lines = ComputeWrapLines(cw, nb, 400, 0, 0)
    Ok "  the shared planner wraps the measured fixture at 400 pt", UBound(lines) >= 0, (UBound(lines) - LBound(lines) + 1) & " wrap line(s) for " & ex.ColCount & " columns"
    ReleaseScratch
    Exit Sub
Fail:
    Fail "measuring", Err.Number & ": " & Err.Description
    ReleaseScratch
End Sub

'-----------------------------------------------------------------------------
' 6. Composing
'-----------------------------------------------------------------------------
Private Sub SectionCompose()
    Dim ex As IgtExample, fonts() As PptTierFont, widths() As Double, tf As PptTierFont
    Dim cw() As Double, nb() As Boolean, lines() As Long, lay As PptLayout
    Dim app As Object, scratch As Object, box As Object, tr As Object, p As Object
    Dim t As Long, nLines As Long, cols1 As Long, i As Long, hit As Long, s As String
    Note ""
    Note "== 6. Composing (the fixture drawn into a scratch box)"
    On Error GoTo Fail
    tf.Name = "Times New Roman": tf.Size = 20: tf.Italic = False
    ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
    ReDim fonts(0 To ex.TierCount - 1)
    For t = 0 To ex.TierCount - 1
        fonts(t) = tf
        fonts(t).Italic = (t = 0)
    Next t
    MeasureExample ex, fonts, widths
    cw = ColumnWidths(ex, widths, 6)
    nb = NoBreakFlags(ex)
    lay.Gap = 6: lay.NumberHang = 36: lay.ContIndent = 36: lay.LowercaseGram = True: lay.InitialCap = False
    lay.FreeFont = tf
    lines = LimitLineColumns(ComputeWrapLines(cw, nb, 400, lay.NumberHang, lay.ContIndent), ex.ColCount)
    nLines = UBound(lines) - LBound(lines) + 1
    cols1 = WrapLineEnd(lines, LBound(lines), ex.ColCount) - lines(LBound(lines)) + 1
    Ok "a plan at 400 pt wraps the 15 columns onto more than one line", nLines > 1, nLines & " lines; " & cols1 & " columns on the first"
    Ok "no line exceeds 33 columns", MaxColumnsPerLine(lines, ex.ColCount) <= 33

    Set app = Application
    Set scratch = app.Presentations.Add(0)
    Set box = scratch.Slides.Add(1, 12).Shapes.AddTextbox(1, 0, 0, 400, 80)
    PrepareExampleBox box
    ComposeExample box, ex, fonts, cw, lines, "(1)", lay
    Set tr = box.TextFrame2.TextRange
    Eq "paragraphs = wrap lines x 2 tiers + 1 free line", tr.Paragraphs.Count, nLines * 2 + 1
    Ok "the first paragraph begins with the number and a tab", Left$(tr.Paragraphs(1).Text, 4) = "(1)" & Chr$(9)
    Eq "  its indent is the hang", tr.Paragraphs(1).ParagraphFormat.LeftIndent, lay.NumberHang
    Eq "  its first line hangs back by the same", tr.Paragraphs(1).ParagraphFormat.FirstLineIndent, -lay.NumberHang
    Eq "  its tab stops: one at the hang, then one per column after the first", tr.Paragraphs(1).ParagraphFormat.TabStops.Count, cols1
    Eq "the gloss paragraph of line 1 has one stop per column after the first", tr.Paragraphs(2).ParagraphFormat.TabStops.Count, cols1 - 1
    Eq "  and the continuation indent on line 2", tr.Paragraphs(3).ParagraphFormat.LeftIndent, lay.ContIndent
    Ok "the forms paragraph is italic", tr.Paragraphs(1).Characters(5, 1).Font.Italic = -1
    Ok "the gloss paragraph is not italic", tr.Paragraphs(2).Characters(1, 1).Font.Italic = 0
    Ok "the first gloss cell 'yam' is not small capitals", tr.Paragraphs(2).Characters(1, 3).Font.Smallcaps = 0
    hit = 0
    For i = 1 To tr.Paragraphs.Count
        s = tr.Paragraphs(i).Text
        If InStr(1, s, "seq") > 0 Then hit = i: Exit For
    Next i
    Ok "a grammatical gloss (SEQ) appears lowercased", hit > 0
    If hit > 0 Then Ok "  and is set in small capitals", tr.Paragraphs(hit).Characters(InStr(1, tr.Paragraphs(hit).Text, "seq"), 3).Font.Smallcaps = -1
    s = tr.Paragraphs(tr.Paragraphs.Count).Text
    s = Replace(Replace(s, Chr$(13), ""), Chr$(11), "")
    Eq "the last paragraph is the free translation in single quotes", s, LeftSingleQuote & "(When) she picked her yams early." & RightSingleQuote
    Ok "  not italic", tr.Paragraphs(tr.Paragraphs.Count).Characters(2, 1).Font.Italic = 0
    Note "  box after autosize: " & Format$(box.Width, "0") & " x " & Format$(box.Height, "0") & " pt"
    scratch.Saved = -1
    scratch.Close
    ReleaseScratch
    Exit Sub
Fail:
    Fail "composing", Err.Number & ": " & Err.Description
    On Error Resume Next
    If Not scratch Is Nothing Then scratch.Saved = -1: scratch.Close
    ReleaseScratch
End Sub

'-----------------------------------------------------------------------------
' 7. Insert
'-----------------------------------------------------------------------------
Private Sub SectionInsert()
    Dim app As Object, host As Object, sld As Object, keep As Object, chk As Object, shp As Object
    Dim n As Long, before As Long, ex As IgtExample, s As String, t As String
    Note ""
    Note "== 7. Insert (onto a slide of a scratch presentation)"
    On Error GoTo Fail
    Set app = Application
    Set host = app.Presentations.Add(0)
    Set sld = host.Slides.Add(1, 12)
    ' Something of the user's on the clipboard first: a known string.
    Set keep = sld.Shapes.AddTextbox(1, 0, 500, 300, 30)
    keep.TextFrame2.TextRange.Text = "the user's own copy"
    keep.TextFrame2.TextRange.Copy
    before = sld.Shapes.Count
    n = InsertExamples(Fixture(Chr$(10)), sld, 40, 40, 400)
    Eq "one example from one copy", n, 1
    Eq "  one box added", sld.Shapes.Count - before, 1
    If sld.Shapes.Count = before + 1 Then
        Set shp = sld.Shapes(sld.Shapes.Count)
        Ok "  it is tagged as ours", IsLingTeXExample(shp)
        Eq "  its number tag", shp.Tags.Item(TAG_NUMBER), "(1)"
        ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
        Eq "  its TSV tag is the model", shp.Tags.Item(TAG_TSV), ModelToTsv(ex)
        Ok "  its text begins with the number", Left$(shp.TextFrame2.TextRange.Text, 4) = "(1)" & Chr$(9)
        Ok "  it sits where asked", Abs(shp.Left - 40) < 0.5 And Abs(shp.Top - 40) < 0.5, Format$(shp.Left, "0") & "," & Format$(shp.Top, "0")
        Ok "  its width is the wrap width", Abs(shp.Width - 400) < 0.5, Format$(shp.Width, "0")
        Ok "  more than one wrap line drawn", shp.TextFrame2.TextRange.Paragraphs.Count > 3, shp.TextFrame2.TextRange.Paragraphs.Count & " paragraphs"
    End If
    ' The user's clipboard, after.
    Set chk = sld.Shapes.AddTextbox(1, 0, 550, 300, 30)
    chk.TextFrame2.TextRange.Paste
    s = Replace(chk.TextFrame2.TextRange.Text, Chr$(13), "")
    Eq "the user's clipboard is what it was", s, "the user's own copy"
    ' Two examples in one copy.
    before = sld.Shapes.Count
    n = InsertExamples(Fixture(Chr$(10)) & Chr$(10) & Fixture(Chr$(10)), sld, 40, 300, 400, 2)
    Eq "two examples from one copy", n, 2
    If sld.Shapes.Count = before + 2 Then
        Eq "  numbered (2a)", sld.Shapes(before + 1).Tags.Item(TAG_NUMBER), "(2a)"
        Eq "  and (2b)", sld.Shapes(before + 2).Tags.Item(TAG_NUMBER), "(2b)"
        Ok "  the second sits below the first", sld.Shapes(before + 2).Top > sld.Shapes(before + 1).Top + sld.Shapes(before + 1).Height - 0.5
    End If
    Eq "text that is not an example inserts nothing", InsertExamples("just a sentence", sld, 40, 40, 400), 0
    host.Saved = -1
    host.Close
    ReleaseScratch
    Exit Sub
Fail:
    Fail "insert", Err.Number & ": " & Err.Description
    On Error Resume Next
    If Not host Is Nothing Then host.Saved = -1: host.Close
    ReleaseScratch
End Sub

'-----------------------------------------------------------------------------
' 8. Read-back and re-wrap
'-----------------------------------------------------------------------------
Private Sub SectionRewrap()
    Dim app As Object, host As Object, sld As Object, shp As Object
    Dim ex As IgtExample, back As IgtExample, num As String, gran As Long
    Dim n1 As Long, n2 As Long, n3 As Long, r As Long
    Note ""
    Note "== 8. Read-back and re-wrap"
    On Error GoTo Fail
    Set app = Application
    Set host = app.Presentations.Add(0)
    Set sld = host.Slides.Add(1, 12)
    If InsertExamples(Fixture(Chr$(10)), sld, 40, 40, 400) <> 1 Then
        Fail "read-back: the fixture did not insert", ""
        GoTo Tidy
    End If
    Set shp = sld.Shapes(sld.Shapes.Count)
    ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
    Ok "ReadBackExample reads the box", ReadBackExample(shp, back, num, gran)
    Eq "  the number", num, "(1)"
    Eq "  the model, with capitals restored (ModelToTsv equal)", ModelToTsv(back), ModelToTsv(ex)
    n1 = shp.TextFrame2.TextRange.Paragraphs.Count
    r = RewrapExample(shp)
    Eq "re-wrap at the same width changes nothing (0 = nothing written)", r, 0
    shp.Width = 250
    r = RewrapExample(shp)
    n2 = shp.TextFrame2.TextRange.Paragraphs.Count
    Eq "narrowed to 250 pt: re-wrap writes (1)", r, 1
    Ok "  and more paragraphs than at 400", n2 > n1, n1 & " -> " & n2
    Ok "  the box kept its width", Abs(shp.Width - 250) < 0.5, Format$(shp.Width, "0")
    Ok "  it still reads back as the same model", ReadBackExample(shp, back, num, gran) And ModelToTsv(back) = ModelToTsv(ex)
    shp.Width = 600
    r = RewrapExample(shp)
    n3 = shp.TextFrame2.TextRange.Paragraphs.Count
    Eq "widened to 600 pt: re-wrap writes (1)", r, 1
    Ok "  and fewer paragraphs than at 250", n3 < n2, n2 & " -> " & n3
    Eq "  re-wrap again: nothing written", RewrapExample(shp), 0
Tidy:
    On Error Resume Next
    host.Saved = -1
    host.Close
    ReleaseScratch
    Exit Sub
Fail:
    Fail "read-back / re-wrap", Err.Number & ": " & Err.Description
    Resume Tidy
End Sub

'-----------------------------------------------------------------------------
' 9. Settings in Presentation.Tags
'-----------------------------------------------------------------------------
Private Sub SectionSettings()
    Dim app As Object, host As Object
    Note ""
    Note "== 9. Settings (Presentation.Tags)"
    On Error GoTo Fail
    Set app = Application
    Set host = app.Presentations.Add(0)
    Eq "default font", SettingFont(host), "Times New Roman"
    Eq "default size", SettingSize(host), 24
    Eq "default gap", SettingGap(host), 6
    Eq "default number hang", SettingNumberHang(host), 36
    Eq "default between", SettingBetween(host), 12
    Ok "default: examples numbered", SettingNumberExamples(host)
    Ok "default: grammatical glosses lowercased", SettingLowercaseGram(host)
    Ok "default: no initial capital", Not SettingInitialCap(host)
    Ok "default: re-wrap on resize", SettingRewrapOnResize(host)
    Eq "default granularity: by word", SettingGranularity(host), igtWordAligned
    Eq "default space replacement", SettingSpaceReplacement(host), "."
    SetSettingFont host, "Charis SIL"
    SetSettingSize host, 18.5
    SetSettingGap host, 4
    SetSettingNumberHang host, 40
    SetSettingBetween host, 8
    SetSettingNumberExamples host, False
    SetSettingLowercaseGram host, False
    SetSettingInitialCap host, True
    SetSettingRewrapOnResize host, False
    SetSettingGranularity host, igtMorphemeAligned
    SetSettingSpaceReplacement host, "_"
    Eq "font written and read", SettingFont(host), "Charis SIL"
    Eq "size written and read (a decimal, locale-proof)", SettingSize(host), 18.5
    Eq "gap written and read", SettingGap(host), 4
    Eq "hang written and read", SettingNumberHang(host), 40
    Eq "between written and read", SettingBetween(host), 8
    Ok "numbering off", Not SettingNumberExamples(host)
    Ok "lowercasing off", Not SettingLowercaseGram(host)
    Ok "initial capital on", SettingInitialCap(host)
    Ok "re-wrap on resize off", Not SettingRewrapOnResize(host)
    Eq "granularity by morpheme", SettingGranularity(host), igtMorphemeAligned
    Eq "space replacement _", SettingSpaceReplacement(host), "_"
    SetSettingSpaceReplacement host, "x"
    Eq "a space replacement that is neither falls back to .", SettingSpaceReplacement(host), "."
    Ok "the tags are on the presentation", host.Tags.Item("LINGTEX_SET_Font") = "Charis SIL"
    host.Saved = -1
    host.Close
    Exit Sub
Fail:
    Fail "settings", Err.Number & ": " & Err.Description
    On Error Resume Next
    If Not host Is Nothing Then host.Saved = -1: host.Close
End Sub

'-----------------------------------------------------------------------------
' 10. Commands on a box: the cursor's column, split, merge, realign, check
'-----------------------------------------------------------------------------
Private Sub SectionCommands()
    Dim app As Object, host As Object, sld As Object, shp As Object
    Dim ex As IgtExample, back As IgtExample, num As String, gran As Long
    Dim tr As Object, txt As String, p1 As Long, p2 As Long, pos As Long, nParas As Long
    Dim c As Long, splitAt As Long, cell As String, i As Long, shortTiers As String, okAll As Boolean
    Dim tsv0 As String, warnings As Collection, nCols As Long
    Note ""
    Note "== 10. Commands (on a box of a scratch presentation)"
    On Error GoTo Fail
    Set app = Application
    Set host = app.Presentations.Add(0)
    Set sld = host.Slides.Add(1, 12)
    If InsertExamples(Fixture(Chr$(10)), sld, 40, 40, 400) <> 1 Then
        Fail "commands: the fixture did not insert", ""
        GoTo Tidy
    End If
    Set shp = sld.Shapes(sld.Shapes.Count)
    ex = ModelFromText(Fixture(Chr$(10)), igtWordAligned)
    tsv0 = ModelToTsv(ex)
    Ok "the box records the size it was composed at", SizeIsOurs(shp)
    Eq "its sub-letter tag is empty (a single example)", shp.Tags.Item(TAG_SUB), ""

    '-- the cursor's column, from a character position -----------------------
    Set tr = shp.TextFrame2.TextRange
    txt = tr.Paragraphs(1).Text
    p1 = InStr(1, txt, Chr$(9))                  ' after the number
    p2 = InStr(p1 + 1, txt, Chr$(9))             ' after the first cell
    pos = tr.Paragraphs(1).Start + p2             ' the first character of the second cell
    Eq "a character in the first line's second cell is column 1", ColumnAtChar(shp, pos), 1
    Eq "a character in the first cell is column 0", ColumnAtChar(shp, tr.Paragraphs(1).Start + p1), 0
    Eq "a character on the number is -1", ColumnAtChar(shp, tr.Paragraphs(1).Start), -1
    pos = tr.Paragraphs(2).Start
    Eq "the first character of the gloss paragraph is column 0", ColumnAtChar(shp, pos), 0
    nParas = tr.Paragraphs.Count
    Eq "a character on the free translation is -1", ColumnAtChar(shp, tr.Paragraphs(nParas).Start), -1
    If nParas > 3 Then
        ' The second wrap line: its first cell is the first column not on line 1.
        c = CountTabsIn(tr.Paragraphs(1).Text)      ' cells on line 1, the number's tab included
        Eq "the first cell of the second wrap line follows line 1's cells", ColumnAtChar(shp, tr.Paragraphs(3).Start), c
    End If

    '-- split at the first column with a boundary, then merge back -----------
    splitAt = -1
    For c = 0 To ex.ColCount - 1
        cell = ex.Cells(0, c)
        For i = 2 To Len(cell)
            If IsBoundary(Mid$(cell, i, 1)) Then splitAt = c: Exit For
        Next i
        If splitAt >= 0 Then Exit For
    Next c
    Ok "the fixture has a column with a morpheme break to split", splitAt >= 0, "column " & splitAt
    If splitAt >= 0 Then
        okAll = SplitColumnInBox(shp, splitAt, shortTiers)
        Ok "SplitColumnInBox splits on every tier", okAll, shortTiers
        Ok "  the box reads back", ReadBackExample(shp, back, num, gran)
        Eq "  with one more column", back.ColCount, ex.ColCount + 1
        Ok "  the size tag follows the composition", SizeIsOurs(shp)
        Eq "MergeColumnsInBox merges it back (1)", MergeColumnsInBox(shp, splitAt, splitAt + 1), 1
        Ok "  and the box reads back", ReadBackExample(shp, back, num, gran)
        Eq "  as the model it started from", StripOwnMarks(ModelToTsv(back)), StripOwnMarks(tsv0)
        Eq "merging past the last column merges nothing (0)", MergeColumnsInBox(shp, ex.ColCount - 1, ex.ColCount), 0
    End If

    '-- by morpheme and back by word -----------------------------------------
    nCols = back.ColCount
    Ok "RealignExample by morpheme composes", RealignExample(shp, igtMorphemeAligned)
    Ok "  the box reads back", ReadBackExample(shp, back, num, gran)
    Ok "  with more columns", back.ColCount > nCols, nCols & " -> " & back.ColCount
    Eq "  its granularity tag says morpheme", shp.Tags.Item(TAG_GRAN), CStr(igtMorphemeAligned)
    Ok "RealignExample by word composes", RealignExample(shp, igtWordAligned)
    Ok "  the box reads back", ReadBackExample(shp, back, num, gran)
    Eq "  with the columns it had", back.ColCount, nCols
    Eq "  as the model it started from", StripOwnMarks(ModelToTsv(back)), StripOwnMarks(tsv0)

    '-- check glossing on the model --------------------------------------------
    Set warnings = CheckExample(back)
    Ok "CheckExample answers on the read-back model", Not warnings Is Nothing, warnings.Count & " warning(s)"
    Ok "WarningsText fits a message box", Len(WarningsText(warnings)) <= 1000
Tidy:
    On Error Resume Next
    host.Saved = -1
    host.Close
    ReleaseScratch
    Exit Sub
Fail:
    Fail "commands", Err.Number & ": " & Err.Description
    Resume Tidy
End Sub

Private Function CountTabsIn(ByVal s As String) As Long
    CountTabsIn = Len(s) - Len(Replace(s, Chr$(9), ""))
End Function

'-----------------------------------------------------------------------------
' 11. Renumbering, and the next free number
'-----------------------------------------------------------------------------
Private Sub SectionRenumber()
    Dim app As Object, host As Object, sld As Object, boxes() As Object, n As Long
    Note ""
    Note "== 11. Renumber"
    On Error GoTo Fail
    Set app = Application
    Set host = app.Presentations.Add(0)
    Set sld = host.Slides.Add(1, 12)
    Eq "an empty presentation's next number is 1", NextExampleNumber(host), 1
    If InsertExamples(Fixture(Chr$(10)), sld, 40, 40, 400, 5) <> 1 Then
        Fail "renumber: the fixture did not insert", ""
        GoTo Tidy
    End If
    Eq "after (5) the next number is 6", NextExampleNumber(host), 6
    If InsertExamples(Fixture(Chr$(10)) & Chr$(10) & Fixture(Chr$(10)), sld, 40, 300, 400, 9) <> 2 Then
        Fail "renumber: the pair did not insert", ""
        GoTo Tidy
    End If
    n = ExampleBoxesInOrder(sld, boxes)
    Eq "three example boxes, top to bottom", n, 3
    Eq "  the top one is (5)", boxes(0).Tags.Item(TAG_NUMBER), "(5)"
    Eq "  then (9a)", boxes(1).Tags.Item(TAG_NUMBER), "(9a)"
    Eq "  with sub-letter a", SubLetterOf(boxes(1)), "a"
    Eq "  then (9b)", boxes(2).Tags.Item(TAG_NUMBER), "(9b)"
    Eq "the next number is 10", NextExampleNumber(host), 10
    Eq "NumberValueOf reads the digits", NumberValueOf("(12b)"), 12
    Eq "RenumberPresentation numbers three", RenumberPresentation(host), 3
    n = ExampleBoxesInOrder(sld, boxes)
    Eq "  the top one is now (1)", boxes(0).Tags.Item(TAG_NUMBER), "(1)"
    Eq "  the pair is (2a)", boxes(1).Tags.Item(TAG_NUMBER), "(2a)"
    Eq "  and (2b)", boxes(2).Tags.Item(TAG_NUMBER), "(2b)"
    Ok "  the text shows the new number", Left$(boxes(0).TextFrame2.TextRange.Text, 4) = "(1)" & Chr$(9)
    Ok "  and the pair's", Left$(boxes(2).TextFrame2.TextRange.Text, 5) = "(2b)" & Chr$(9)
    Eq "  the next number is 3", NextExampleNumber(host), 3
    Eq "renumbering again changes nothing and counts three", RenumberPresentation(host), 3
Tidy:
    On Error Resume Next
    host.Saved = -1
    host.Close
    ReleaseScratch
    Exit Sub
Fail:
    Fail "renumber", Err.Number & ": " & Err.Description
    Resume Tidy
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

Private Function CountVT(ByVal s As String) As Long
    CountVT = Len(s) - Len(Replace(s, Chr$(11), ""))
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
    ' As FLEx copies a free line shown in one language: direction marks and
    ' no code (a code appears only when a further language follows; a word
    ' is never taken for one by its shape -- PROMPT.md rule 10, 2026-09-29).
    r3 = ChrW(&H200E) & "Free " & ChrW(&H200E) & ChrW(&H200E) & "(When) she picked her yams early."
    Fixture = r1 & sep & r2 & sep & r3 & sep
End Function
