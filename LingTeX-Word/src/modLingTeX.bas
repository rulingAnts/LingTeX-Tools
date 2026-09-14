Attribute VB_Name = "modLingTeX"
Option Explicit

'=============================================================================
' modLingTeX  --  LingTeX-Word
'
' The commands.  Everything the user can run from the ribbon, the Macros dialog
' (Alt+F8) or a keyboard shortcut lives here; the real work is in the modules
' below it.
'
' ---------------------------------------------------------------------------
' HOW TO INSERT AN EXAMPLE  (Phase 1)
'
' Either:
'   * Copy an interlinear selection in FLEx, put the cursor where it belongs, and
'     run LingTeXInsertInterlinear.  The clipboard is read and the example is
'     drawn at the cursor.
'   * Or paste the FLEx text into the document first, select it, and run the same
'     command.  The selection is replaced by the drawn example.
'
' Phase 2 adds a form with an editable data table in front of this; the engine
' below does not change when it arrives.  See ..\README.md.
' ---------------------------------------------------------------------------
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

' Re-entrancy guard.  Word has no Application.EnableEvents, so an event handler
' that edits the document would otherwise re-trigger itself.  clsAppEvents checks
' this before doing anything.
Public gBusy As Boolean

' Set by AutoExec.  Module-level so the events object outlives the procedure.
Private mEvents As clsAppEvents
' The label of an undo record BeginUndo has named but StartPendingUndo has
' not yet opened. See BeginUndo.
Private mPendingUndoLabel As String

' The ribbon, handed over by its onLoad callback, so the toggle buttons can be
' told to ask for their pressed state again when a setting or the active
' document changes (settings live in the document). Lost if the VBA project
' is reset -- an untrapped error, Run > Reset -- after which the toggles stop
' following changes until Word restarts; the known cost of this Office design.
Private mRibbon As Object
' Word's Format > Style dialog (WdWordDialog.wdDialogFormatStyle), as a number:
' Dialogs is reached late-bound, see ModifyStyleInWord.
Private Const DLG_FORMAT_STYLE As Long = 180

' Keyboard shortcuts, letter=command, installed by LingTeXInstallShortcuts and
' by the first run. The modifiers are per platform (ShortcutModifiers): on
' Windows Ctrl+Alt+Shift, which Word leaves free, where Ctrl+Alt alone is
' Print Preview, Insert Comment, AutoFormat and more; on Mac the same chord
' with Command for Ctrl (Seth: Cmd wherever Windows has Ctrl), Command+
' Option+Shift -- Shift kept because Command+Option alone is macOS's own Hide
' Others, Minimise and Close All on H, M and W, which Word cannot see to
' refuse. A key that is already bound to anything, built in or the user's
' own, is never taken (Seth): it is skipped and named -- so each command lists
' its letters in order of preference and the first free one is used (on Mac
' Cmd+Option+Shift+I is Mark Citation, +S the Styles pane, +L a ListNum
' field, +O a TOC entry, +U Update Fields). LingTeXShowShortcuts reports what
' actually landed.
'
' MAC WORD'S MODIFIER BITS ARE NOT WINDOWS'S. Found by a probe macro (deleted
' since; git history around 72a95ef) that asked Word to name what it had bound: Command 256, Shift 512,
' Option 2048, Control 4096. The Windows values (Shift 256, Ctrl 512, Alt
' 1024) are Command, Shift and "Invalid parameter" there, which is why every
' Cmd+Option attempt failed with 5853 and BuildKeyCode raised on it.
Private Const SHORTCUT_TABLE As String = _
    "IEJ=LingTeXInsertInterlinear|R=LingTeXRewrapCurrent|A=LingTeXRewrapAll|" & _
    "SXD=LingTeXSplitColumn|M=LingTeXMergeColumns|K=LingTeXCheckExample|" & _
    "T=LingTeXConvertTableToIgt|W=LingTeXAlignByWord|P=LingTeXAlignByMorpheme|" & _
    "H=LingTeXSettings|N=LingTeXToggleExampleNumbers|" & _
    "G=LingTeXIndentExample|LOUYQ=LingTeXOutdentExample|FBV=LingTeXTextToInterlinear"
Private Const MODS_WINDOWS As Long = 512 + 1024 + 256      ' Ctrl+Alt+Shift
Private Const MODS_MAC As Long = 256 + 2048 + 512          ' Command+Option+Shift

' How far Indent and Outdent move an example: half an inch, Word's own tab.
Private Const INDENT_STEP As Double = 36

' The first run: what the add-in does for itself the first time Word loads
' it from STARTUP, recorded in the Normal template so it happens once. Bump
' to run it again on every machine at the next start.
Private Const SETUP_VERSION As String = "3"      ' 3: H opens the dialog; F is Text to Interlinear
Private Const SETUP_VAR As String = "LingTeX_Setup"

'-----------------------------------------------------------------------------
' EVERY message to the user goes through Report or Confirm, never MsgBox.
'
' Not a style rule -- it is what makes the commands testable. A MsgBox blocks on a
' modal dialog, so a test that runs a command waits forever for a person to click
' OK, and modDocTests could not drive any of the seven commands at all. With this
' indirection a test sets gQuiet, runs the command, and asserts on gLastMessage:
' "the right thing was reported" becomes a comparison instead of a thing someone
' watched happen.
'
' gLastMessage is set whether or not a dialog is shown, so it is also the record
' of what the user was last told.
'-----------------------------------------------------------------------------
' The only two MsgBox calls in the module are in Report and Confirm below, and
' the title is a constant rather than a literal at each one: a bulk edit over this
' file can no longer silently take it off them.
Private Const DIALOG_TITLE As String = "LingTeX-Word"

Public gQuiet As Boolean            ' suppress dialogs (tests set this)
Public gQuietAnswer As Boolean      ' what Confirm returns while quiet
Public gQuietText As String         ' what Ask returns while quiet
Public gLastMessage As String       ' the last thing reported, dialog or not

Public Sub Report(ByVal msg As String, ByVal kind As Long)
    gLastMessage = msg
    If gQuiet Then Exit Sub
    MsgBox msg, kind, DIALOG_TITLE
End Sub

' A yes/no question.  Same contract: while quiet it answers gQuietAnswer rather
' than asking, so a test can exercise both the accept and the decline path.
Public Function Confirm(ByVal msg As String) As Boolean
    gLastMessage = msg
    If gQuiet Then
        Confirm = gQuietAnswer
        Exit Function
    End If
    Confirm = (MsgBox(msg, vbYesNo + vbQuestion, DIALOG_TITLE) = vbYes)
End Function

' A question with a typed answer. "" is Cancel (InputBox returns "" for it,
' and for an emptied box, which is treated the same). While quiet it answers
' gQuietText, so a test can exercise an answer and a cancel.
Public Function Ask(ByVal prompt As String, ByVal dflt As String) As String
    gLastMessage = prompt
    If gQuiet Then
        Ask = gQuietText
        Exit Function
    End If
    Ask = InputBox(prompt, DIALOG_TITLE, dflt)
End Function


'=============================================================================
' -- STARTUP ----------------------------------------------------------------
'=============================================================================

' Runs when Word loads the add-in from its STARTUP folder.
Public Sub AutoExec()
    On Error Resume Next
    ' Cleared here as well as set and unset around each command. gBusy wedged True
    ' -- by Ctrl+Break during a render, or a reset of the VBA project -- made every
    ' ribbon button do nothing at all, silently, for the rest of the Word session.
    ' Restarting Word fixed it, but only if you guessed that was the problem.
    gBusy = False
    Set mEvents = New clsAppEvents
    mEvents.Attach
    Err.Clear
    On Error GoTo 0
    ScheduleFirstRun
End Sub

'-----------------------------------------------------------------------------
' Everything a fresh install needs, done once, without being asked (Seth: the
' arming, installing and activating happen on first run). At present that is
' the shortcuts; the hooks are armed above and the ribbon comes with the file.
' Only when the template is loaded from Word's own STARTUP folder, which is
' where the installer puts it: the dev rig loads it from the clone and must
' see no dialog at Word start, or the test runner hangs on it. Recorded in
' Normal, which Word saves at quit; done again only when SETUP_VERSION moves.
'
' NOT DONE INSIDE AUTOEXEC. Word times how long each STARTUP template takes
' to load, and a modal message shown from AutoExec counts for as long as it is
' on screen: on Windows the first run earned an "add-in alert: it caused Word
' to start slowly", offering to disable us (Seth, 2026-09-12). So AutoExec only
' books the first run for a moment after startup is over, with OnTime, and
' LingTeXFirstRun does the work then.
'-----------------------------------------------------------------------------
Private Sub ScheduleFirstRun()
    Dim app As Object
    Dim done As String
    On Error Resume Next
    Set app = Application
    If Not LoadedFromStartup() Then Exit Sub
    done = app.NormalTemplate.Variables(SETUP_VAR).Value
    Err.Clear
    If done = SETUP_VERSION Then Exit Sub
    app.OnTime When:=Now + TimeValue("00:00:03"), Name:="LingTeXFirstRun"
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub LingTeXFirstRun()
    Dim app As Object
    Dim summary As String
    Dim done As String

    On Error Resume Next
    Set app = Application
    If Not LoadedFromStartup() Then Exit Sub
    done = app.NormalTemplate.Variables(SETUP_VAR).Value
    Err.Clear
    If done = SETUP_VERSION Then Exit Sub

    summary = InstallShortcuts()
    app.NormalTemplate.Variables(SETUP_VAR).Value = SETUP_VERSION
    If Err.Number <> 0 Then
        Err.Clear
        app.NormalTemplate.Variables.Add Name:=SETUP_VAR, Value:=SETUP_VERSION
    End If
    Err.Clear
    On Error GoTo 0

    Report "LingTeX-Word is installed." & vbCr & vbCr & _
           "The LingTeX tab is on the ribbon of every document: insert an " & _
           "interlinear example from FLEx or from text, re-wrap, split and " & _
           "merge columns, check the glossing. Examples are numbered; the " & _
           "Numbers button turns that off for a document." & vbCr & vbCr & _
           summary, vbInformation
End Sub

' Is this template running from Word's STARTUP folder, as installed, rather
' than from a development clone?
Private Function LoadedFromStartup() As Boolean
    Dim app As Object
    Dim here As String, startup As String
    On Error Resume Next
    Set app = Application
    here = ThisDocument.Path
    startup = app.StartupPath
    Err.Clear
    On Error GoTo 0
    If here = "" Or startup = "" Then Exit Function
    LoadedFromStartup = (StrComp(here, startup, vbTextCompare) = 0)
End Function

Public Sub AutoExit()
    On Error Resume Next
    If Not mEvents Is Nothing Then mEvents.Detach
    Set mEvents = Nothing
    ReleaseScratch
    On Error GoTo 0
End Sub

' Attach the application hooks if nothing has yet: re-wrap on save, re-wrap
' on leaving an example, AutoCorrect kept out of cells. AutoExec does this when
' Word loads the add-in from STARTUP, but while the code lives in a .docm
' nobody runs it -- and Word for Mac's Macros dialog does not even list it --
' so two by-hand checks that depend on the hooks failed for no other reason
' (2026-09-12). Every command calls this first; it does nothing once armed.
' Deliberately not AutoExec itself, which also clears gBusy.
Public Sub EnsureHooks()
    On Error Resume Next
    If mEvents Is Nothing Then
        Set mEvents = New clsAppEvents
        mEvents.Attach
    End If
    Err.Clear
    On Error GoTo 0
End Sub

' AutoExec by a name that appears in the macro list. Not on the ribbon: every
' command arms the hooks on first use, so its one remaining job is to clear a
' wedged busy flag, which the busy message names it for.
Public Sub LingTeXStart()
    AutoExec
    Report "LingTeX-Word is armed for this Word session: examples re-wrap " & _
           "when a document is saved (and, if turned on, when the cursor " & _
           "leaves one), and AutoCorrect stays out of interlinear cells." & _
           vbCr & vbCr & "Every command arms this on first use as well; this " & _
           "also clears the busy flag if a command was interrupted.", _
           vbInformation
End Sub


'=============================================================================
' -- INSERTING --------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Insert an interlinear example from the selection, or from the clipboard when
' nothing is selected.
'-----------------------------------------------------------------------------
Public Sub LingTeXInsertInterlinear()
    Dim doc As Document
    Dim raw As String
    Dim ex As IgtExample
    Dim target As Range
    Dim fromClipboard As Boolean
    Dim lines() As String

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks
    Set doc = ActiveDocument

    If Selection.Type = wdSelectionIP Then
        raw = ClipboardText()
        fromClipboard = True
        If Trim$(raw) = "" Then
            Report "Nothing to insert." & vbCr & vbCr & _
                   "Copy an interlinear selection in FLEx first, or paste the " & _
                   "text into the document and select it before running this.", _
                   vbInformation
            Exit Sub
        End If
        Set target = Selection.Range.Duplicate
    Else
        raw = Selection.Range.Text
        Set target = SelectedParagraphRange()
    End If

    ex = ModelFromText(raw, SettingGranularity(doc))
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        ' Not FLEx text and not tab-separated rows. Selected lines of plain
        ' text -- words on one line, glosses on the next -- take the Text to
        ' Interlinear road, with its one question (Seth, 2026-09-14).
        If Not fromClipboard Then
            If InStr(raw, vbTab) = 0 Then
                lines = TextLines(raw)
                If UBound(lines) >= 1 Then
                    TextToInterlinearCore doc, target, raw
                    Exit Sub
                End If
            End If
        End If
        Report "That text could not be read as interlinear data." & vbCr & vbCr & _
               "Expected FLEx interlinear text (tab-separated, with tier labels " & _
               "such as Morphemes and Lex. Gloss), a plain tab-separated " & _
               "table with one row per tier, or selected lines of text: the " & _
               "words on one line, their glosses on the next.", vbExclamation
        Exit Sub
    End If

    DrawParsedExample ex, target, doc, "Insert interlinear"
    Exit Sub

Fail:
    Report "Error " & CStr(Err.Number) & ": " & Err.Description, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Draw a parsed example at a range, replacing what is there, inside one undo
' record, and say what needs saying: the drawing failed, or took but not as
' planned, or the glossing has something only a person can decide. Shared by
' Insert Interlinear and Text to Interlinear.
'-----------------------------------------------------------------------------
Private Sub DrawParsedExample(ByRef ex As IgtExample, target As Range, doc As Document, _
        ByVal label As String)
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim warnings As Collection

    On Error GoTo Fail
    ' Repair what has only one right answer before drawing, so the example does
    ' not arrive already violating its own invariants.
    FixCellSpaces ex, SettingSpaceReplacement(doc)

    gBusy = True
    BeginUndo label
    Application.ScreenUpdating = False

    Set tbl = RenderExample(ex, target)

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If tbl Is Nothing Then
        Report "The example could not be drawn." & _
               IIf(gRenderError = "", "", vbCr & vbCr & gRenderError), _
               vbExclamation
        Exit Sub
    End If

    ' A table came back, but something in the drawing did not take -- a cell width
    ' Word refused, a row that could not be trimmed. The example is on the page and
    ' may well look wrong, so it is worth saying rather than leaving the user to
    ' wonder whether the wrap planner is broken.
    If gRenderError <> "" Then
        Report "The example was drawn, but not exactly as planned:" & vbCr & vbCr & _
               gRenderError & vbCr & vbCr & _
               "Re-wrapping it may fix the layout.", vbExclamation
    End If

    ' Report only what a person has to decide; the rest was already fixed.
    Set warnings = CheckExample(ex)
    ReportWarnings warnings, False
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'=============================================================================
' -- TEXT TO INTERLINEAR ----------------------------------------------------
'=============================================================================
' Select lines typed by hand -- the words of a sentence on one line, their
' glosses on the next, the translation under them, blank lines anywhere --
' and draw them as an example (Seth, 2026-09-14). The lines become the model
' directly (modIgtModel, PLAIN TEXT LINES): a leading example number such as
' (1) is dropped, since the document numbers examples itself; the document's
' alignment is applied by ProjectToMorphemes when it says morphemes; and the
' one thing the text cannot say -- which of its last lines are translations
' -- is asked, with a guess (the trailing lines whose word count differs from
' the first line's) and every line shown with its count, so the guess is
' easy to check. Insert Interlinear takes the same road when its selection
' is plain lines.

Public Sub LingTeXTextToInterlinear()
    Dim doc As Document
    Dim target As Range
    Dim inTable As Boolean

    If gBusy Then
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    EnsureHooks
    On Error Resume Next
    Set doc = ActiveDocument
    Err.Clear
    On Error GoTo 0
    If doc Is Nothing Then
        Report "Open a document first.", vbInformation
        Exit Sub
    End If
    If Selection.Type = wdSelectionIP Then
        Report "Select the lines of the example first: the words on one line, " & _
               "their glosses on the next, and the translation under them. " & _
               "Blank lines between them do no harm.", vbInformation
        Exit Sub
    End If
    On Error Resume Next
    inTable = Selection.Information(wdWithInTable)
    Err.Clear
    On Error GoTo 0
    If inTable Then
        Report "The selection is inside a table. Convert Table turns a table into " & _
               "an example; this command wants lines of plain text.", vbInformation
        Exit Sub
    End If
    Set target = SelectedParagraphRange()
    TextToInterlinearCore doc, target, Selection.Range.Text
End Sub

' The shared road: lines out of the text, the question, the model, the draw.
Private Sub TextToInterlinearCore(doc As Document, target As Range, ByVal raw As String)
    Dim lines() As String
    Dim n As Long, nFree As Long
    Dim answer As String
    Dim ex As IgtExample

    lines = TextLines(raw)
    n = UBound(lines) + 1
    If n < 2 Then
        Report "Select at least two lines: the words of the example on one line " & _
               "and their glosses on the next, with any translation under them.", _
               vbInformation
        Exit Sub
    End If
    lines(0) = StripExampleNumber(lines(0))
    If lines(0) = "" Then
        Report "The first line holds only an example number. The words of the " & _
               "example come first; the document numbers it itself.", vbInformation
        Exit Sub
    End If

    nFree = GuessFreeLineCount(lines)
    answer = Trim$(Ask(FreeLinesPrompt(lines, nFree), CStr(nFree)))
    If answer = "" Then Exit Sub                     ' Cancel
    If Not IsDigitsOnly(answer) Then
        Report "A whole number of lines, please: 0, 1, 2...", vbExclamation
        Exit Sub
    End If
    nFree = CLng(Val(answer))
    If nFree > n - 1 Then
        Report "At least one line has to be the example itself: " & CStr(n) & _
               " lines are selected, so at most " & CStr(n - 1) & " of them can be " & _
               "translations.", vbExclamation
        Exit Sub
    End If

    ex = ModelFromLines(lines, nFree)
    If ex.TierCount = 0 Or ex.ColCount = 0 Then
        Report "Those lines could not be read as an example.", vbExclamation
        Exit Sub
    End If
    If SettingGranularity(doc) = igtMorphemeAligned Then ProjectToMorphemes ex
    DrawParsedExample ex, target, doc, "Text to interlinear"
End Sub

' The question: every line with its word count, then the ask.
Private Function FreeLinesPrompt(lines() As String, ByVal guess As Long) As String
    Dim s As String
    Dim i As Long
    Dim preview As String
    s = CStr(UBound(lines) + 1) & " lines selected:" & vbCr & vbCr
    For i = 0 To UBound(lines)
        preview = lines(i)
        If Len(preview) > 60 Then preview = Left$(preview, 57) & "..."
        s = s & CStr(i + 1) & ".  " & preview & "   (" & CStr(WordCount(lines(i))) & _
            " words)" & vbCr
    Next i
    s = s & vbCr & "How many of the LAST lines are free translations? The lines " & _
        "before them are the tiers, in order: the words, then their glosses. " & _
        "Type 0 if there is none."
    If guess > 0 Then
        s = s & vbCr & vbCr & "The last " & CStr(guess) & IIf(guess = 1, " line has", _
            " lines have") & " a different number of words from the first, so " & _
            IIf(guess = 1, "it looks", "they look") & " like the translation."
    End If
    FreeLinesPrompt = s
End Function

Private Function IsDigitsOnly(ByVal s As String) As Boolean
    Dim i As Long, ch As String
    If s = "" Then Exit Function
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        If ch < "0" Or ch > "9" Then Exit Function
    Next i
    IsDigitsOnly = True
End Function

'-----------------------------------------------------------------------------
' Adopt a plain Word table as an interlinear example: style it, and wrap it.
' For tables typed by hand or pasted from a spreadsheet.
'-----------------------------------------------------------------------------
Public Sub LingTeXConvertTableToIgt()
    Dim errNum As Long, errDesc As String
    Dim warmed() As Double
    Dim tbl As Table
    Dim ex As IgtExample
    Dim doc As Document
    Dim r As Long, c As Long
    Dim tsv As String, rowText As String

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    If Not Selection.Information(wdWithInTable) Then
        Report "Put the cursor inside the table you want to convert.", _
               vbInformation
        Exit Sub
    End If

    Set tbl = Selection.Tables(1)
    Set doc = ActiveDocument

    If IsInterlinearTable(tbl) Then
        Report "That table is already an interlinear example.", _
               vbInformation
        Exit Sub
    End If

    ' Read it as TSV, which is the shape ModelFromTsv already understands.
    For r = 1 To tbl.Rows.Count
        rowText = ""
        For c = 1 To tbl.Rows(r).Cells.Count
            If c > 1 Then rowText = rowText & vbTab
            rowText = rowText & CleanedCellText(tbl, r, c)
        Next c
        If tsv <> "" Then tsv = tsv & vbLf
        tsv = tsv & rowText
    Next r

    ex = ModelFromTsv(tsv)
    If ex.TierCount = 0 Then
        Report "That table could not be read as interlinear data.", _
               vbExclamation
        Exit Sub
    End If

    ' Styles and measurements BEFORE the undo record opens (see BeginUndo):
    ' creating a style and measuring both write outside the record's document.
    ' Then the record, then the delete -- which used to come first and sat in
    ' the undo list as two or three steps of its own.
    EnsureStyles doc
    MeasureExample ex, doc, warmed

    gBusy = True
    BeginUndo "Convert table to interlinear"
    Application.ScreenUpdating = False

    Dim anchor As Range
    Set anchor = doc.Range(tbl.Range.Start, tbl.Range.Start)
    StartPendingUndo
    tbl.Delete
    RenderExample ex, anchor

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    ' A row merged into a single cell is what the converter takes as a free
    ' translation (it reads the table as TSV, and an untabbed line is a
    ' translation). Say so when there was none, rather than leaving the user
    ' to wonder why the translation stayed inside the table (Seth, 2026-09-12).
    If ex.FreeCount = 0 Then
        Report "Converted. No free translation was found: a row whose cells " & _
               "are merged into ONE cell is taken as the translation, and every " & _
               "other row as a tier." & vbCr & vbCr & _
               "To add one now, type it in the paragraph under the example and " & _
               "give that paragraph the style LingTeX Free; it will be kept " & _
               "with the example from then on.", vbInformation
    End If
    ReportWarnings CheckExample(ex), False
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- RE-WRAPPING ------------------------------------------------------------
'=============================================================================

' Re-wrap the example containing the cursor.
Public Sub LingTeXRewrapCurrent()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    gBusy = True
    BeginUndo "Re-wrap interlinear"
    Application.ScreenUpdating = False
    RewrapTable tbl
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Move the example at the cursor half an inch right or left.
'
' The example's indent is its rows' left indent (modRender.ExampleIndent); the
' number column and the translation go with it. Done as a re-wrap at the new
' indent rather than by moving the rows, so the wrap is re-planned for the
' narrower or wider line and nothing changes if the plan fails.
'-----------------------------------------------------------------------------
Public Sub LingTeXIndentExample()
    StepExampleIndent INDENT_STEP, "Indent interlinear example"
End Sub

Public Sub LingTeXOutdentExample()
    StepExampleIndent -INDENT_STEP, "Outdent interlinear example"
End Sub

Private Sub StepExampleIndent(ByVal delta As Double, ByVal label As String)
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim v As Double

    If gBusy Then
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    v = ExampleIndent(tbl) + delta
    If v < 0 Then v = 0
    If Abs(v - ExampleIndent(tbl)) < 0.5 Then
        Report "The example is at the left margin already.", vbInformation
        Exit Sub
    End If

    gBusy = True
    BeginUndo label
    Application.ScreenUpdating = False
    RewrapTable tbl, v
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    If gRenderError <> "" Then
        Report "The example could not be moved: " & gRenderError, vbExclamation
    End If
    Exit Sub

Fail:
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Keep the selection through a re-wrap.
'
' A re-wrap deletes an example and draws it again, so the character count
' inside it changes, and the redraw inserts at the very position the old
' example occupied. Seth found what that does to a cursor parked on the empty
' paragraph right after the translation, the natural place to click to keep
' writing: the deletion pulls that position back to the anchor, the draw
' happens at it, and the cursor is now in the first cell of the new table.
' An absolute position cannot survive that. What does survive is the text
' before the first table redrawn and the text from the last table's end on
' (its translations are rewritten letter for letter, and after them nothing
' is touched). So the selection is remembered as an offset from the document's
' start when it lies before the span, from its end when it lies after; inside
' the span it is left to Word.
'
' firstStart and lastEnd are the first redrawn table's Range.Start and the
' last one's Range.End. mode comes back 0 = leave it, 1 = from the start,
' 2 = from the end.
'-----------------------------------------------------------------------------
Public Sub RememberSelection(doc As Document, ByVal firstStart As Long, _
        ByVal lastEnd As Long, ByRef mode As Long, ByRef pos As Long, _
        ByRef length As Long)
    Dim s As Long, e As Long
    mode = 0
    On Error Resume Next
    If Selection Is Nothing Then Exit Sub
    If Not (Selection.Document Is doc) Then Exit Sub
    s = Selection.Range.Start
    e = Selection.Range.End
    If Err.Number <> 0 Then
        Err.Clear
        Exit Sub
    End If
    On Error GoTo 0
    length = e - s
    If e <= firstStart Then
        mode = 1
        pos = s
    ElseIf s >= lastEnd Then
        mode = 2
        pos = doc.Content.End - s
    End If
End Sub

Public Sub RestoreSelection(doc As Document, ByVal mode As Long, _
        ByVal pos As Long, ByVal length As Long)
    Dim s As Long, e As Long
    If mode = 0 Then Exit Sub
    On Error Resume Next
    If mode = 1 Then
        s = pos
    Else
        s = doc.Content.End - pos
    End If
    If s < 0 Then s = 0
    e = s + length
    If e > doc.Content.End Then e = doc.Content.End
    If s > e Then s = e
    doc.Range(s, e).Select
    Err.Clear
    On Error GoTo 0
End Sub

' Re-wrap every example in the active document.
'
' ActiveDocument is evaluated behind a handler, unlike every other command here:
' with no document open it raises, and without this the user got a bare VBA error
' dialog with a line number in it.
Public Sub LingTeXRewrapAll()
    EnsureHooks
    Dim doc As Document

    On Error GoTo Fail
    Set doc = ActiveDocument
    On Error GoTo 0
    If doc Is Nothing Then
        Report "Open a document first.", vbInformation
        Exit Sub
    End If
    RewrapDocument doc, True
    Exit Sub

Fail:
    Report "Open a document first.", vbInformation
End Sub

'-----------------------------------------------------------------------------
' Re-wrap every example in a document.
'
' Tables are collected first and then walked in REVERSE document order.  Each
' re-wrap deletes and redraws a table, which shifts every position after it, so
' working backwards keeps the remaining references valid.
'-----------------------------------------------------------------------------
Public Sub RewrapDocument(doc As Document, ByVal showResult As Boolean)
    Dim errNum As Long, errDesc As String
    Dim tables As Collection
    Dim i As Long, n As Long, nFailed As Long, nDegraded As Long
    Dim done As Table
    Dim firstWhy As String
    Dim selMode As Long, selPos As Long, selLen As Long
    Dim firstStart As Long, lastEnd As Long

    If doc Is Nothing Then Exit Sub
    If gBusy Then
        ' Reported only when the user asked for this. RewrapDocument is ALSO the
        ' re-entrancy path -- clsAppEvents calls it on save with showResult False,
        ' and putting a dialog in front of someone saving a document would be worse
        ' than the silence it replaces. The seven commands report; this does not.
        If showResult Then
            Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
                   "If this keeps happening, run LingTeXStart from the macro " & _
                   "list (or restart Word) to clear it.", vbInformation
        End If
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tables = AllInterlinearTables(doc)
    If tables.Count = 0 Then
        If showResult Then
            Report "This document contains no interlinear examples.", _
                   vbInformation
        End If
        Exit Sub
    End If

    ' Remember where the user was, so an automatic re-wrap does not move them
    ' (see RememberSelection). The tables come in document order.
    firstStart = tables(1).Range.Start
    lastEnd = tables(tables.Count).Range.End
    RememberSelection doc, firstStart, lastEnd, selMode, selPos, selLen

    gBusy = True
    ' Measure everything BEFORE the undo record opens (see BeginUndo): with the
    ' cache warm, the re-wraps below touch the scratch document only for text
    ' the cache has never seen, so the record stays in one piece.
    For i = 1 To tables.Count
        WarmMeasureCache tables(i)
    Next i
    BeginUndo "Re-wrap all interlinear examples"
    Application.ScreenUpdating = False

    ' Count what actually came back, not what Err happens to hold.
    '
    ' This used to read "If Err.Number = 0 Then n = n + 1", which is wrong twice
    ' over. On Error Resume Next leaves Err set by anything that raised and was
    ' swallowed anywhere inside the render -- and EnsureTableStyle raises 4198 on
    ' Mac by design, on its six Style.Table.Borders lines, the first time an
    ' example is drawn in a fresh document. On Error GoTo 0 does not clear Err. So
    ' the first successful re-wrap in a new document reported as a failure, and
    ' "Re-wrapped 0 interlinear examples" was the message for a run that had just
    ' worked.
    n = 0
    nFailed = 0
    For i = tables.Count To 1 Step -1
        On Error Resume Next
        ' A document of twenty examples takes a few seconds and shows the busy
        ' cursor meanwhile; VBA has no thread to keep the window live, so the
        ' status bar says how far along it is.
        StatusLine "LingTeX: re-wrapping example " & _
                   CStr(tables.Count - i + 1) & " of " & CStr(tables.Count)
        Set done = RewrapTable(tables(i))
        If done Is Nothing Then
            nFailed = nFailed + 1
            If firstWhy = "" Then firstWhy = gRenderError
        Else
            n = n + 1
            ' Drawn, but not exactly as planned. Counted as a success because the
            ' example is on the page, and still reported, because a layout that is
            ' quietly wrong is the thing this whole suite of changes is about.
            If gRenderError <> "" Then
                nDegraded = nDegraded + 1
                If firstWhy = "" Then firstWhy = gRenderError
            End If
        End If
        Err.Clear
        On Error GoTo Fail
    Next i

    StatusLine ""

    RestoreSelection doc, selMode, selPos, selLen

    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If showResult Or nFailed > 0 Or nDegraded > 0 Then
        If nFailed = 0 And nDegraded = 0 Then
            Report "Re-wrapped " & CStr(n) & " interlinear example" & _
                   IIf(n = 1, "", "s") & ".", vbInformation
        Else
            ' Reported even when showResult is False -- an automatic re-wrap that
            ' skipped an example must not do so silently.
            Report "Re-wrapped " & CStr(n) & " interlinear example" & _
                   IIf(n = 1, "", "s") & ", and could not re-wrap " & _
                   CStr(nFailed) & "." & _
                   IIf(nDegraded = 0, "", vbCr & CStr(nDegraded) & _
                       " were drawn but not exactly as planned.") & _
                   IIf(firstWhy = "", "", vbCr & vbCr & "First problem: " & firstWhy) & _
                   vbCr & vbCr & "The examples that could not be re-wrapped were " & _
                   "left exactly as they were.", vbExclamation
        End If
    End If
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    If showResult Then
        Report "Error " & errNum & ": " & errDesc, vbCritical
    End If
End Sub


'=============================================================================
' -- ADJUSTING ALIGNMENT ----------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Split the column at the cursor at its first morpheme boundary.
'
' This is how an otherwise word-aligned example gets one affix, clitic or
' reduplicant pulled out into a column of its own.  The boundary character is
' carried onto the start of the new column on EVERY interlinear tier, so the
' column invariant holds without the user having to tidy up after it.
'-----------------------------------------------------------------------------
Public Sub LingTeXSplitColumn()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim flatCol As Long
    Dim shortTiers As String
    Dim okAll As Boolean

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor in the column you want to split.", _
               vbInformation
        Exit Sub
    End If

    If Selection.Cells(1).ColumnIndex <= NumberColumns(tbl) Then
        Report "Put the cursor in one of the example's word cells; the number " & _
               "is not a column.", vbInformation
        Exit Sub
    End If
    flatCol = FlatColumnAt(tbl, Selection.Cells(1).RowIndex, _
                                Selection.Cells(1).ColumnIndex)
    If flatCol < 0 Then
        Report "That column could not be located.", vbExclamation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    If Not ExampleWasRead(ex) Then Exit Sub
    AbsorbFreeParagraphs ex, tbl
    okAll = SplitColumn(ex, flatCol, 1, shortTiers)

    gBusy = True
    BeginUndo "Split interlinear column"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    If Not okAll Then
        ' Exactly the Leipzig rule 2 problem: the form has a morpheme break its
        ' gloss does not.  Guessing would rewrite the analysis, so say so instead.
        Report "No morpheme break was found in: " & shortTiers & vbCr & vbCr & _
               "Those cells were left whole and the new column is empty for " & _
               "them. Add the matching break, or undo with Ctrl+Z.", _
               vbExclamation
    End If
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub

'-----------------------------------------------------------------------------
' Merge columns back together.
' Select across several cells to merge exactly those; with the cursor in a single
' cell, that column is merged with the one after it.
'-----------------------------------------------------------------------------
Public Sub LingTeXMergeColumns()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim firstCol As Long, lastCol As Long
    Dim nCells As Long

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Select the columns you want to merge.", vbInformation
        Exit Sub
    End If

    nCells = Selection.Cells.Count
    If Selection.Cells(1).ColumnIndex <= NumberColumns(tbl) Then
        Report "Select the example's word cells; the number is not a column.", _
               vbInformation
        Exit Sub
    End If
    firstCol = FlatColumnAt(tbl, Selection.Cells(1).RowIndex, _
                                 Selection.Cells(1).ColumnIndex)
    If firstCol < 0 Then
        Report "Those columns could not be located.", vbExclamation
        Exit Sub
    End If

    If nCells > 1 Then
        lastCol = FlatColumnAt(tbl, Selection.Cells(nCells).RowIndex, _
                                     Selection.Cells(nCells).ColumnIndex)
    Else
        lastCol = firstCol + 1
    End If
    If lastCol <= firstCol Then
        Report "There is no following column to merge with.", _
               vbInformation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    If Not ExampleWasRead(ex) Then Exit Sub
    AbsorbFreeParagraphs ex, tbl
    If lastCol > ex.ColCount - 1 Then lastCol = ex.ColCount - 1
    If Not MergeColumns(ex, firstCol, lastCol) Then
        Report "Those columns could not be merged.", vbExclamation
        Exit Sub
    End If

    gBusy = True
    BeginUndo "Merge interlinear columns"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- CHECKING ---------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Check the example at the cursor against the column invariants and the Leipzig
' conventions, and offer to repair what has only one right answer.
'-----------------------------------------------------------------------------
Public Sub LingTeXCheckExample()
    Dim errNum As Long, errDesc As String
    Dim tbl As Table
    Dim ex As IgtExample
    Dim warnings As Collection
    Dim nFixable As Long

    If gBusy Then
        ' Not silence: a stuck flag would otherwise look like a dead button.
        Report "LingTeX-Word is busy with another operation." & vbCr & vbCr & _
               "If this keeps happening, run LingTeXStart from the macro list " & _
               "(or restart Word) to clear it.", vbInformation
        Exit Sub
    End If
    On Error GoTo Fail
    EnsureHooks

    Set tbl = FindExampleAt(Selection.Range)
    If tbl Is Nothing Then
        Report "Put the cursor inside an interlinear example first.", _
               vbInformation
        Exit Sub
    End If

    ex = ReadExampleFromTable(tbl)
    If Not ExampleWasRead(ex) Then Exit Sub
    AbsorbFreeParagraphs ex, tbl
    Set warnings = CheckExample(ex)

    If warnings.Count = 0 Then
        Report "No problems found.", vbInformation
        Exit Sub
    End If

    nFixable = FixableCount(warnings)
    If nFixable = 0 Then
        ReportWarnings warnings, True
        Exit Sub
    End If

    If Not Confirm(WarningText(warnings) & vbCr & vbCr & _
              CStr(nFixable) & " of these can be fixed automatically. " & _
              "Fix them now?") Then Exit Sub

    FixWhatWeCan ex, SettingSpaceReplacement(ActiveDocument)

    gBusy = True
    BeginUndo "Fix interlinear example"
    Application.ScreenUpdating = False
    ReplaceTableWith tbl, ex
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch

    ' Anything still standing needs a human decision.
    ReportWarnings CheckExample(ex), False
    Exit Sub

Fail:
    ' Captured FIRST. EndUndo ends with Err.Clear and ReleaseScratch opens with
    ' On Error Resume Next, either of which resets Err -- so reading Err.Number
    ' after them reported "Error 0: " and lost the error being hunted.
    errNum = Err.Number: errDesc = Err.Description
    Application.ScreenUpdating = True
    EndUndo
    gBusy = False
    ReleaseScratch
    Report "Error " & errNum & ": " & errDesc, vbCritical
End Sub


'=============================================================================
' -- SHARED HELPERS ---------------------------------------------------------
'=============================================================================

' Draw a model over the top of an existing table, keeping its position.
Private Sub ReplaceTableWith(tbl As Table, ex As IgtExample)

    ' modRender owns "how much of the document is this example" and the order
    ' that keeps the undo record whole (plan, open the record, delete, draw), so
    ' there is only one definition of it. Deleting here first, as this used to,
    ' put the delete outside the record: two or three stray undo steps.
    RedrawExampleAt tbl, ex
End Sub

'-----------------------------------------------------------------------------
' Whole paragraphs covered by the selection.
' The pasted FLEx text occupies entire paragraphs, so the replacement has to
' cover them entirely or a stray paragraph mark is left behind.
'-----------------------------------------------------------------------------
Private Function SelectedParagraphRange() As Range
    Dim r As Range
    Set r = Selection.Range.Duplicate
    r.Start = r.Paragraphs(1).Range.Start
    r.End = r.Paragraphs(r.Paragraphs.Count).Range.End
    ' Keep the final paragraph mark so the document structure survives.
    If r.End > r.Start Then r.End = r.End - 1
    Set SelectedParagraphRange = r
End Function

'-----------------------------------------------------------------------------
' Read the clipboard as plain text.
'
' Deliberately NOT via MSForms.DataObject, which is unreliable or absent on Mac
' Word.  Instead a hidden document is used as the landing pad: Word's own paste
' works identically on both platforms, and wdPasteText asks for the text/plain
' flavour, which for FLEx is the tab-separated form this add-in wants.
'-----------------------------------------------------------------------------
Public Function ClipboardText() As String
    Dim tmp As Document
    Dim s As String

    On Error Resume Next
    Set tmp = Documents.Add(Visible:=False)
    If tmp Is Nothing Then
        Set tmp = Documents.Add
        If Not tmp Is Nothing Then
            If tmp.Windows.Count > 0 Then tmp.Windows(1).Visible = False
        End If
    End If
    If tmp Is Nothing Then
        Err.Clear
        Exit Function
    End If

    tmp.Content.PasteSpecial DataType:=wdPasteText
    s = tmp.Content.Text
    tmp.Close SaveChanges:=wdDoNotSaveChanges
    Err.Clear
    On Error GoTo 0

    ClipboardText = s
End Function

Private Function CleanedCellText(tbl As Table, ByVal r As Long, ByVal c As Long) As String
    Dim s As String
    On Error Resume Next
    s = tbl.Cell(r, c).Range.Text
    Err.Clear
    On Error GoTo 0
    s = Replace(s, Chr$(7), "")
    s = Replace(s, vbCr, "")
    s = Replace(s, vbLf, "")
    CleanedCellText = Trim$(s)
End Function


'=============================================================================
' -- WARNING PRESENTATION ---------------------------------------------------
'=============================================================================

Private Function WarningText(warnings As Collection) As String
    Dim w As Variant, s As String, n As Long
    If warnings Is Nothing Then Exit Function
    For Each w In warnings
        n = n + 1
        If n > 12 Then
            s = s & vbCr & "... and " & CStr(warnings.Count - 12) & " more."
            Exit For
        End If
        If s <> "" Then s = s & vbCr
        s = s & "- " & w.Describe
    Next w
    WarningText = s
End Function

'-----------------------------------------------------------------------------
' Did the read actually produce a model?
'
' AbsorbFreeParagraphs calls AddFreeLine, which does UBound(ex.FreeLines) -- and on
' a model that never went through NewExample that array is unallocated and UBound
' raises error 9. ReadExampleFromTable returns exactly such a model when it bails
' out early. RewrapTable always checked first; the three column commands did not,
' so each of them could die with a bare VBA error on a table it could not read.
'-----------------------------------------------------------------------------
Private Function ExampleWasRead(ex As IgtExample) As Boolean
    If ex.TierCount > 0 And ex.ColCount > 0 Then
        ExampleWasRead = True
        Exit Function
    End If
    Report "That example could not be read." & _
           IIf(gReadBackError = "", "", vbCr & vbCr & gReadBackError), _
           vbExclamation
End Function

' Show the findings.  Silent when there are none, so it is safe to call after
' every operation.
Private Sub ReportWarnings(warnings As Collection, ByVal alsoWhenEmpty As Boolean)
    If warnings Is Nothing Then Exit Sub
    If warnings.Count = 0 Then
        If alsoWhenEmpty Then
            Report "No problems found.", vbInformation
        End If
        Exit Sub
    End If
    Report WarningText(warnings), vbExclamation
End Sub


'=============================================================================
' -- UNDO -------------------------------------------------------------------
'=============================================================================
' Application.UndoRecord collapses a whole operation into ONE undo step, which
' matters because re-wrapping deletes and rebuilds a table: without it, undoing
' one re-wrap takes an unknown number of presses.
'
' There is deliberately NO "#If Mac Then" guard here.  An earlier version assumed
' UndoRecord was Windows-only and compiled it out on Mac, which silently gave Mac
' users multi-step undo for no reason -- the probe
' (tools/probe/modProbe.bas section 12) found it present on Word 16.112 for Mac.
'
' It is reached late-bound through Object and every call is error-guarded, so a
' build that genuinely lacks it degrades to Word's own undo stack instead of
' failing to compile.  That is what makes the guard unnecessary: there is nothing
' to compile out.

' Public so clsAppEvents can collapse an automatic re-wrap into one undo step too.
' Without that, reversing a re-wrap nobody asked for -- it fires on a cursor move --
' takes an unknown number of Ctrl+Z presses.
Public Sub BeginUndo(ByVal label As String)
    ' The record is NOT opened here, only named. Measuring text writes to a
    ' hidden scratch document, and a custom undo record that sees a change in
    ' another document is closed by it -- on Mac every drawing step then lists
    ' separately in the undo menu after the record's own label, so one insert
    ' took dozens of Cmd+Z (Seth's screenshot, 2026-09-12). StartPendingUndo
    ' opens the record at the first change to the user's document -- DrawExample,
    ' or RewrapTable just before it deletes -- after every measurement is done,
    ' and RewrapDocument warms the measurement cache before it starts.
    mPendingUndoLabel = label
End Sub

' Open the record BeginUndo named, if it has not been opened yet. Called by the
' renderer immediately before its first change to the document.
Public Sub StartPendingUndo()
    Dim ur As Object
    If mPendingUndoLabel = "" Then Exit Sub
    On Error Resume Next
    Set ur = Application.UndoRecord
    If Not ur Is Nothing Then
        If Not ur.IsRecordingCustomRecord Then ur.StartCustomRecord mPendingUndoLabel
    End If
    Err.Clear
    On Error GoTo 0
    mPendingUndoLabel = ""
End Sub

Public Sub EndUndo()
    Dim ur As Object
    mPendingUndoLabel = ""
    On Error Resume Next
    Set ur = Application.UndoRecord
    If Not ur Is Nothing Then
        If ur.IsRecordingCustomRecord Then ur.EndCustomRecord
    End If
    Err.Clear
    On Error GoTo 0
End Sub


'=============================================================================
' -- INSTALL VERIFICATION ---------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' Returns an identifying string, and exists to be called from outside Word.
'
' Mac Word's AppleScript dictionary has no `do Visual Basic`, so a script cannot
' execute arbitrary VBA -- but it does have `run VB macro`, which runs a macro that
' already exists (confirmed by tools/probe/Probe AppleScript Bridge.applescript).
'
' That is exactly enough for the Mac installer to CHECK ITS OWN WORK. After
' copying the template into Word's startup folder it can relaunch Word and run
' this; a result means the add-in genuinely loaded, an error means it did not.
'
' Worth having because the known silent failure is macOS quarantining a .dotm that
' arrived inside a downloaded zip: Word then refuses to load it and the user sees
' a successful install and no ribbon. Without a callable hook there is no way for
' the installer to tell those apart.
'
' Keep it trivial, dependency-free and never-throwing: it is a heartbeat, and
' anything it touched could become a reason for it to fail misleadingly.
'-----------------------------------------------------------------------------
Public Function LingTeXPing() As String
    LingTeXPing = "LingTeX-Word loaded"
End Function


'=============================================================================
'=============================================================================
' -- SETTINGS COMMANDS ------------------------------------------------------
'=============================================================================
' Zero-argument, so they appear in Tools > Macro > Macros and can sit on the
' ribbon; the typed setters in modSettings take arguments and cannot. Each one
' acts on the active document, stores the value in it, and says what it did.
' Added because "type this in the Immediate window" turned out to be the one
' step of the by-hand checklist nobody could follow (2026-09-12).

Private Function DocForSetting() As Document
    On Error Resume Next
    Set DocForSetting = ActiveDocument
    On Error GoTo 0
    If DocForSetting Is Nothing Then
        Report "Open a document first: settings are stored in the document.", vbInformation
    End If
End Function

Public Sub LingTeXAlignByWord()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    SetSettingGranularity doc, igtWordAligned
    RefreshRibbon
    Report "New examples in this document will be WORD-aligned: one column per " & _
           "word, with enclitics kept in their host's column." & vbCr & vbCr & _
           "Examples already on the page are unchanged until inserted again.", _
           vbInformation
End Sub

Public Sub LingTeXAlignByMorpheme()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    SetSettingGranularity doc, igtMorphemeAligned
    RefreshRibbon
    Report "New examples in this document will be MORPHEME-aligned: one column " & _
           "per morpheme, with enclitic columns never starting a wrap line." & _
           vbCr & vbCr & _
           "Examples already on the page are unchanged until inserted again.", _
           vbInformation
End Sub

Public Sub LingTeXToggleRewrapOnSave()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingRewrapOnSave(doc)
    SetSettingRewrapOnSave doc, v
    RefreshRibbon
    Report "Re-wrap every example when this document is saved: now " & _
           IIf(v, "ON", "OFF") & ".", vbInformation
End Sub

Public Sub LingTeXToggleRewrapOnSelectionChange()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingRewrapOnSelectionChange(doc)
    SetSettingRewrapOnSelectionChange doc, v
    RefreshRibbon
    Report "Re-wrap an example as soon as the cursor leaves it: now " & _
           IIf(v, "ON", "OFF") & " for this document." & vbCr & vbCr & _
           IIf(v, "Off is the default, because this repaints while you type.", _
                  ""), vbInformation
End Sub

Public Sub LingTeXToggleExampleNumbers()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingNumberExamples(doc)
    SetSettingNumberExamples doc, v
    RefreshRibbon
    Report "New examples in this document are " & IIf(v, "NUMBERED: (1), (2)... " & _
           "in a first column, with Word's own list numbering, continuing " & _
           "through the document.", "NOT numbered.") & vbCr & vbCr & _
           "Examples already on the page keep whatever they have; a re-wrap " & _
           "keeps a number an example carries.", vbInformation
End Sub

Public Sub LingTeXToggleGramGlossInitialCap()
    Dim doc As Document
    Dim v As Boolean
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    v = Not SettingGramGlossInitialCap(doc)
    SetSettingGramGlossInitialCap doc, v
    RefreshRibbon
    Report "Grammatical glosses in small capitals now " & _
           IIf(v, "begin with a full-size capital (Erg, 3Sg)", _
                  "are uniform small capitals throughout (erg, 3sg), as the " & _
                  "Leipzig Glossing Rules print them") & "." & vbCr & vbCr & _
           "Re-wrap the examples to apply it.", vbInformation
End Sub

' The LingTeX paragraph styles follow the document's Normal style -- size
' inherited, font pinned from the body font -- but only from when they are
' created; a style is never clobbered once it exists. A document whose styles
' were made before that rule keeps their pinned size, so making Normal bigger
' changes nothing (Seth, 2026-09-12). This resets the six to follow Normal
' again, then re-wraps. It IS a clobber, of any tuning too, and says so.
Public Sub LingTeXResetStyles()
    Dim doc As Document
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    If Not Confirm("Reset the LingTeX paragraph styles to follow this " & _
                   "document's Normal style (its font and size), and re-wrap " & _
                   "every example?" & vbCr & vbCr & "Any size or font you set " & _
                   "on a LingTeX style yourself is replaced.") Then Exit Sub
    ResetParaStylesToBody doc
    RewrapDocument doc, True
End Sub

Public Sub LingTeXShowSettings()
    Dim doc As Document
    Dim msg As String
    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    msg = "LingTeX-Word settings stored in " & doc.Name & ":" & vbCr & vbCr
    msg = msg & "Alignment: " & IIf(SettingGranularity(doc) = igtMorphemeAligned, _
                                    "by morpheme", "by word") & vbCr
    msg = msg & "Gap between columns: " & CStr(SettingGap(doc)) & " pt" & vbCr
    msg = msg & "Gap between wrap lines: " & CStr(SettingLineGap(doc)) & " pt" & vbCr
    msg = msg & "Continuation indent: " & CStr(SettingContIndent(doc)) & " pt" & vbCr
    msg = msg & "Space inside a cell becomes: " & SettingSpaceReplacement(doc) & vbCr
    msg = msg & "Small capitals for grammatical glosses: " & _
                IIf(SettingLowercaseGramGloss(doc), "on", "off") & vbCr
    msg = msg & "  with a full-size first capital: " & _
                IIf(SettingGramGlossInitialCap(doc), "on", "off") & vbCr
    msg = msg & "Number new examples: " & IIf(SettingNumberExamples(doc), "on", "off") & _
                " (number column " & CStr(SettingNumberHang(doc)) & " pt, list level " & _
                CStr(SettingNumberLevel(doc)) & ")" & vbCr
    msg = msg & "Re-wrap on save: " & IIf(SettingRewrapOnSave(doc), "on", "off") & vbCr
    msg = msg & "Re-wrap when the cursor leaves an example: " & _
                IIf(SettingRewrapOnSelectionChange(doc), "on", "off") & vbCr & vbCr
    msg = msg & "Spacing set in this document (the rest are at their " & _
                "defaults):" & vbCr & SpacingReport(doc) & vbCr
    msg = msg & "Styles (font, size; blank follows Normal):" & vbCr & _
                StyleReport(doc) & vbCr
    msg = msg & "Every one of these is set in the Settings dialog " & _
                "(LingTeXSettings, or Settings on the ribbon). Commands: " & _
                "LingTeXAlignByWord, LingTeXAlignByMorpheme, " & _
                "LingTeXToggleRewrapOnSave, LingTeXToggleRewrapOnSelectionChange, " & _
                "LingTeXToggleGramGlossInitialCap, LingTeXToggleExampleNumbers, " & _
                "LingTeXResetStyles."
    Report msg, vbInformation
End Sub

' One line per spacing the document sets, or a note that it sets none.
Private Function SpacingReport(doc As Document) As String
    Dim keys() As String
    Dim i As Long
    Dim t As String
    Dim s As String
    keys = Split(SPACING_KEYS, "|")
    For i = 0 To UBound(keys)
        t = SpacingText(doc, keys(i))
        If t <> "" Then
            ' A percentage of the font size carries its own unit.
            If Right$(t, 1) = "%" Then
                s = s & "  " & keys(i) & ": " & t & vbCr
            Else
                s = s & "  " & keys(i) & ": " & t & " pt" & vbCr
            End If
        End If
    Next i
    If s = "" Then s = "  (none)" & vbCr
    SpacingReport = s
End Function

' One line per style slot: its label, then the font and size it sets itself.
Private Function StyleReport(doc As Document) As String
    Dim i As Long
    Dim fn As String, sz As String, flags As String
    Dim s As String
    For i = 0 To STYLE_SLOT_COUNT - 1
        fn = StyleFontText(doc, i)
        sz = StyleSizeText(doc, i)
        flags = ""
        If StyleFlag(doc, i, "Bold") Then flags = flags & " bold"
        If StyleFlag(doc, i, "Italic") Then flags = flags & " italic"
        If StyleFlag(doc, i, "SmallCaps") Then flags = flags & " small caps"
        s = s & "  " & StyleSlotLabel(i) & ": " & IIf(fn = "", "-", fn) & ", " & _
            IIf(sz = "", "-", sz & " pt") & flags & vbCr
    Next i
    StyleReport = s
End Function


'=============================================================================
' -- THE SETTINGS DIALOG ----------------------------------------------------
'=============================================================================
' One form over every document setting (Seth, 2026-09-14: a pop-up when the
' user clicks Settings, not a ribbon tab): alignment and numbering of new
' examples, the small-capitals convention, the re-wrap triggers, every spacing
' at every level and in every direction, and the LingTeX styles, each of
' which opens in Word's OWN style dialog. frmLingTeXSettings builds its
' controls in code and says why.
'
' Show is modal and returns when the form hides itself. OK and Apply have
' written the document and re-wrapped it by then; Cancel has done nothing.
' Modify in Word hands back "modify", and THIS loop opens Word's Style dialog
' on the selected style and shows the form again -- Word's own dialog on top
' of a modal UserForm is unproven on Mac, and a form that steps aside first
' needs nothing unproven.
Public Sub LingTeXSettings()
    Dim doc As Document
    Dim frm As frmLingTeXSettings

    Set doc = DocForSetting()
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    On Error GoTo Failed
    Set frm = New frmLingTeXSettings
    frm.LoadFrom doc
    Do
        frm.Show
        If frm.Result <> "modify" Then Exit Do
        ModifyStyleInWord doc, frm.SelectedSlot()
    Loop
    Unload frm
    RefreshRibbon
    Exit Sub

Failed:
    Report "The settings dialog could not be opened here (" & CStr(Err.Number) & _
           ": " & Err.Description & ")." & vbCr & vbCr & "LingTeXShowSettings " & _
           "still lists every setting, and the ribbon toggles still work.", _
           vbExclamation
    On Error Resume Next
    Unload frm
    Err.Clear
    On Error GoTo 0
End Sub

' Open Word's own Style dialog on one of the add-in's styles, for everything
' a style can hold: font, size, colour, borders, language, the paragraph
' format. Display rather than Show, so the dialog's Apply does not restyle
' the user's paragraph; changes made through its Modify button are applied
' all the same, and the examples are re-wrapped for them.
'
' The dialog opens on the style of the SELECTION. Its Name argument is set as
' well, but Mac Word does not act on it (2026-09-14: the dialog opened on the
' paragraph's style), so first something in the style is selected -- Find by
' style, the first run or paragraph that carries it -- and the cursor is put
' back afterwards. A document nothing of which uses the style yet cannot be
' navigated that way, and the message says what to pick.
Private Sub ModifyStyleInWord(doc As Document, ByVal slot As Long)
    Dim dlg As Object
    Dim nm As String
    Dim failed As Boolean
    Dim was As Range

    nm = StyleSlotName(slot)
    If StyleSlotObject(doc, slot, True) Is Nothing Then
        Report "The style " & nm & " could not be found or created in this document." & _
               IIf(gStyleError <> "", vbCr & vbCr & gStyleError, ""), vbExclamation
        Exit Sub
    End If

    On Error Resume Next
    Set was = Selection.Range.Duplicate
    Err.Clear
    On Error GoTo 0
    If Not SelectTextInStyle(doc, nm) Then
        Report "Nothing in " & doc.Name & " uses " & nm & " yet, so Word's Style " & _
               "dialog cannot open on it. In the dialog, set List to All styles, " & _
               "select " & nm & " and click Modify.", vbInformation
    End If

    On Error Resume Next
    Set dlg = Application.Dialogs(DLG_FORMAT_STYLE)
    If Err.Number <> 0 Or dlg Is Nothing Then
        failed = True
    Else
        dlg.Name = nm
        Err.Clear
        dlg.Display
        failed = (Err.Number <> 0)
    End If
    Err.Clear
    If Not was Is Nothing Then was.Select
    Err.Clear
    On Error GoTo 0
    If failed Then
        Report "Word's Style dialog could not be opened from here. Use Format > " & _
               "Style (Mac) or the Styles pane (Windows) and modify " & nm & ".", _
               vbInformation
        Exit Sub
    End If
    ClearCache
    RewrapDocument doc, False
End Sub

' Select the first text in the document carrying this style (paragraph or
' character), so a dialog that reads the selection reads that style. False
' when nothing does.
Private Function SelectTextInStyle(doc As Document, ByVal nm As String) As Boolean
    Dim rng As Range
    Dim hit As Boolean
    On Error Resume Next
    Set rng = doc.Content
    With rng.Find
        .ClearFormatting
        .Text = ""
        .Style = doc.Styles(nm)
        .Format = True
        .Forward = True
        .MatchWildcards = False
        hit = .Execute
    End With
    If Err.Number <> 0 Then hit = False
    Err.Clear
    If hit Then rng.Select
    If Err.Number <> 0 Then hit = False
    Err.Clear
    On Error GoTo 0
    SelectTextInStyle = hit
End Function


'=============================================================================
' -- KEYBOARD SHORTCUTS -----------------------------------------------------
'=============================================================================
' Installed into this template (or Normal), so they work in every document,
' and removable the same way. Word resolves a macro key binding by name when
' the key is pressed. Added because Tools > Macro > Macros... for every one of
' sixty-six checks was making the by-hand pass take far longer than it needed
' to (Seth, 2026-09-12).
'
' EVERYTHING HERE IS LATE-BOUND. KeyBindings, FindKey, BuildKeyCode,
' CustomizationContext and NormalTemplate are reached through an Object, and
' the key constants are their numbers (macro category 2, Control 512, Alt
' 1024), because a member missing from Mac Word's type library is a COMPILE
' error for this whole module -- and in a template loaded as an add-in that
' means every load, unload and command raises "Compile error in hidden
' module: modLingTeX", endlessly (2026-09-12). Late-bound, a missing member
' is a run-time error inside the trap below, and nothing else suffers.

Public Sub LingTeXInstallShortcuts()
    Report InstallShortcuts(), vbInformation
End Sub

' Install every shortcut that can be installed, and say what happened: which
' were installed and where, which keys were left alone because they already
' do something, and what Word said if it refused one.
Private Function InstallShortcuts() As String
    Dim pairs() As String, kv() As String
    Dim i As Long, n As Long, total As Long
    Dim app As Object
    Dim homes(1) As Object, homeNames(1) As String, nHomes As Long
    Dim names(1) As String
    Dim h As Long, k As Long
    Dim why As String, refused As String, taken As String, usedHome As String
    Dim installed As String, busy As String
    Dim code As Long
    Dim bound As Boolean
    Dim owner As String, letter As String
    Dim j As Long
    Dim kb As Object

    ' Where a binding may live, in order of preference: this template when the
    ' code is in one (so the shortcuts ship with it), else Normal; and Normal
    ' as the fallback when the template refuses them. Every combination is
    ' tried in turn, and when none works the report says what Word said.
    On Error Resume Next
    Set app = Application
    If ThisDocument.Type = 1 Then          ' 1 = a template
        Set homes(0) = ThisDocument
        homeNames(0) = "the template " & ThisDocument.Name
        Set homes(1) = app.NormalTemplate
        homeNames(1) = "the Normal template"
        nHomes = 2
    Else
        Set homes(0) = app.NormalTemplate
        homeNames(0) = "the Normal template"
        nHomes = 1
    End If
    Err.Clear
    On Error GoTo 0

    pairs = Split(SHORTCUT_TABLE, "|")
    total = UBound(pairs) + 1
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        names(0) = kv(1)
        names(1) = ProjectName() & ".modLingTeX." & kv(1)
        bound = False
        busy = ""
        ' The letters in order of preference; the first one free is taken.
        For j = 1 To Len(kv(0))
            letter = Mid$(kv(0), j, 1)
            code = KeyCodeFor(app, letter)
            ' Never take a key that already does something -- Word's own command
            ' or a binding the user made -- unless it is already ours.
            owner = KeyOwner(app, homes(0), code)
            If owner <> "" And InStr(1, owner, "LingTeX", vbTextCompare) = 0 Then
                busy = busy & IIf(busy = "", "", ", ") & KeyName(letter) & " (" & owner & ")"
            Else
                ' The bare macro name, then the qualified one Word sometimes
                ' insists on for a macro that lives in another template.
                For h = 0 To nHomes - 1
                    For k = 0 To 1
                        why = TryBindKey(app, homes(h), names(k), code)
                        If why = "" Then
                            bound = True
                            If usedHome = "" Then usedHome = homeNames(h)
                            ' The name Word gives the key, which is the truth about
                            ' what the modifier bits mean on this platform.
                            Set kb = Nothing
                            Set kb = app.FindKey(code)
                            If kb Is Nothing Then
                                installed = installed & "  " & KeyName(letter) & "  " & ShortName(kv(1)) & vbCr
                            Else
                                installed = installed & "  " & kb.KeyString & "  " & ShortName(kv(1)) & vbCr
                            End If
                            Exit For
                        End If
                        If refused = "" Then
                            refused = names(k) & " in " & homeNames(h) & ": " & why
                        End If
                    Next k
                    If bound Then Exit For
                Next h
            End If
            If bound Then Exit For
        Next j
        If bound Then
            n = n + 1
        ElseIf busy <> "" Then
            taken = taken & IIf(taken = "", "", "; ") & ShortName(kv(1)) & ": " & busy
        End If
    Next i

    ' Bindings stored in this template last only if the template is saved, and
    ' Word would otherwise ask about it at quit. Saved here; a failure (the
    ' Mac sandbox refusing a file outside Word's own folders) is not fatal:
    ' the shortcuts work for this session and the first run tries again.
    If n > 0 And nHomes = 2 Then
        If usedHome = homeNames(0) Then SaveThisTemplate
    End If

    If n = 0 Then
        InstallShortcuts = "No keyboard shortcuts could be installed." & vbCr
        If refused <> "" Then InstallShortcuts = InstallShortcuts & "Word said: " & refused
    Else
        InstallShortcuts = CStr(n) & " of " & CStr(total) & " shortcuts installed, in " & _
                           usedHome & ":" & vbCr & installed & vbCr
        If refused <> "" Then
            InstallShortcuts = InstallShortcuts & "Word refused one: " & refused & vbCr
        End If
    End If
    If taken <> "" Then
        InstallShortcuts = InstallShortcuts & "No free key for " & taken & vbCr
    End If
    InstallShortcuts = InstallShortcuts & vbCr & "Change any by hand: Tools > Customize " & _
                       "Keyboard, category Macros. LingTeXRemoveShortcuts takes ours out."
    ' A dialog shows 1024 characters and garbage after that.
    If Len(InstallShortcuts) > 1000 Then InstallShortcuts = Left$(InstallShortcuts, 997) & "..."
End Function

Private Sub SaveThisTemplate()
    Dim d As Object
    On Error Resume Next
    Set d = ThisDocument
    If Not d.Saved Then d.Save
    Err.Clear
    On Error GoTo 0
End Sub

' What a key does now, as Word describes it, or "" when it is free.
Private Function KeyOwner(app As Object, home As Object, ByVal code As Long) As String
    Dim kb As Object
    On Error Resume Next
    app.CustomizationContext = home
    Set kb = app.FindKey(code)
    If Not kb Is Nothing Then KeyOwner = kb.Command
    Err.Clear
    On Error GoTo 0
End Function

' Command/Ctrl + Option/Alt + a letter. BuildKeyCode when Word offers it; the
' same sum by hand when the call itself is what raises.
Private Function KeyCodeFor(app As Object, ByVal letter As String) As Long
    On Error Resume Next
    KeyCodeFor = ShortcutModifiers() + Asc(letter)
    Err.Clear
    On Error GoTo 0
End Function

' The modifier bits for this platform (see SHORTCUT_TABLE).
Private Function ShortcutModifiers() As Long
    If Application.PathSeparator = "/" Then
        ShortcutModifiers = MODS_MAC
    Else
        ShortcutModifiers = MODS_WINDOWS
    End If
End Function

' A command name without its prefix: "LingTeXSplitColumn" is "SplitColumn".
Private Function ShortName(ByVal cmd As String) As String
    If Left$(cmd, 7) = "LingTeX" Then
        ShortName = Mid$(cmd, 8)
    Else
        ShortName = cmd
    End If
End Function

' A shortcut as a person reads it, from the bits; what Word shows is KeyString.
Private Function KeyName(ByVal letter As String) As String
    Dim m As Long, s As String
    m = ShortcutModifiers()
    If Application.PathSeparator = "/" Then
        If (m And 256) <> 0 Then s = s & "Cmd+"
        If (m And 4096) <> 0 Then s = s & "Control+"
        If (m And 2048) <> 0 Then s = s & "Option+"
        If (m And 512) <> 0 Then s = s & "Shift+"
    Else
        If (m And 512) <> 0 Then s = s & "Ctrl+"
        If (m And 1024) <> 0 Then s = s & "Alt+"
        If (m And 256) <> 0 Then s = s & "Shift+"
    End If
    KeyName = s & letter
End Function

' The VBA project's name, for the qualified macro name; "Project" (Word's
' default for a template) when it cannot be read, which on Windows it cannot
' without trust access to the project object model.
Private Function ProjectName() As String
    Dim d As Object
    On Error Resume Next
    Set d = ThisDocument
    ProjectName = d.VBProject.Name
    If Err.Number <> 0 Or ProjectName = "" Then ProjectName = "Project"
    Err.Clear
    On Error GoTo 0
End Function

Public Sub LingTeXRemoveShortcuts()
    Dim i As Long, n As Long, h As Long
    Dim kb As Object
    Dim app As Object
    Dim homes(1) As Object, nHomes As Long

    ' Every binding that runs one of our macros, on whatever key, in either
    ' home -- so a set installed under an earlier key scheme goes as well.
    On Error Resume Next
    Set app = Application
    Set homes(0) = app.NormalTemplate
    nHomes = 1
    If ThisDocument.Type = 1 Then
        Set homes(1) = ThisDocument
        nHomes = 2
    End If
    For h = 0 To nHomes - 1
        app.CustomizationContext = homes(h)
        If Err.Number <> 0 Then
            Err.Clear
        Else
            For i = app.KeyBindings.Count To 1 Step -1
                Set kb = app.KeyBindings(i)
                If InStr(1, kb.Command, "LingTeX", vbTextCompare) > 0 Then
                    kb.Clear
                    n = n + 1
                End If
                Err.Clear
            Next i
        End If
    Next h
    Err.Clear
    On Error GoTo 0
    Report CStr(n) & " LingTeX shortcuts removed.", vbInformation
End Sub

' One attempt: the customization context, then the binding. Empty on success,
' else what Word said, prefixed "context" when it was the context that failed.
Private Function TryBindKey(app As Object, home As Object, ByVal cmd As String, _
        ByVal code As Long) As String
    On Error Resume Next
    app.CustomizationContext = home
    If Err.Number <> 0 Then
        TryBindKey = "context: " & CStr(Err.Number) & ": " & Err.Description
        Err.Clear
        Exit Function
    End If
    app.KeyBindings.Add 2, cmd, code       ' 2 = wdKeyCategoryMacro
    If Err.Number <> 0 Then TryBindKey = CStr(Err.Number) & ": " & Err.Description
    Err.Clear
    On Error GoTo 0
End Function

' The status bar, late-bound: a progress line while a long command runs.
Private Sub StatusLine(ByVal s As String)
    Dim app As Object
    On Error Resume Next
    Set app = Application
    app.StatusBar = s
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub LingTeXShowShortcuts()
    Dim have As String
    have = InstalledShortcutList()
    If have = "" Then
        Report "No LingTeX-Word keyboard shortcuts are installed yet. Install " & _
               "Shortcuts (or LingTeXInstallShortcuts) would try:" & vbCr & vbCr & _
               ShortcutList(), vbInformation
    Else
        Report "LingTeX-Word keyboard shortcuts:" & vbCr & vbCr & have, vbInformation
    End If
End Sub

' Every binding that runs one of our macros, in either home, by the name Word
' gives the key.
Private Function InstalledShortcutList() As String
    Dim app As Object, kb As Object
    Dim homes(1) As Object, nHomes As Long
    Dim h As Long, i As Long
    Dim cmd As String, p As Long

    On Error Resume Next
    Set app = Application
    Set homes(0) = app.NormalTemplate
    nHomes = 1
    If ThisDocument.Type = 1 Then
        Set homes(1) = ThisDocument
        nHomes = 2
    End If
    For h = 0 To nHomes - 1
        app.CustomizationContext = homes(h)
        If Err.Number <> 0 Then
            Err.Clear
        Else
            For i = 1 To app.KeyBindings.Count
                Set kb = app.KeyBindings(i)
                cmd = kb.Command
                p = InStr(1, cmd, "LingTeX", vbTextCompare)
                If p > 0 Then
                    InstalledShortcutList = InstalledShortcutList & "  " & kb.KeyString & _
                                            "  " & ShortName(Mid$(cmd, p)) & vbCr
                End If
                Err.Clear
            Next i
        End If
    Next h
    Err.Clear
    On Error GoTo 0
End Function

' The table's first-choice keys, for when nothing is installed yet.
Private Function ShortcutList() As String
    Dim pairs() As String, kv() As String
    Dim i As Long
    Dim s As String

    pairs = Split(SHORTCUT_TABLE, "|")
    For i = 0 To UBound(pairs)
        kv = Split(pairs(i), "=")
        s = s & "  " & KeyName(Left$(kv(0), 1)) & "  " & ShortName(kv(1)) & vbCr
    Next i
    ShortcutList = s
End Function

' -- RIBBON CALLBACKS -------------------------------------------------------
'=============================================================================
' The ribbon passes an IRibbonControl.  These are typed as Variant rather than
' IRibbonControl so the project needs no reference to the Office object library,
' which keeps the module importable into a bare VBA project on either platform.

' -- the toggles: state shown on the button, no message ----------------------
' getPressed: Word asks what to show; onAction: the user clicked. Both look at
' the ACTIVE document, because that is where the settings live. The two
' alignment buttons behave as a pair: pressing either sets that alignment and
' both are refreshed.

Public Sub RbnOnLoad(ribbon As Variant)
    On Error Resume Next
    Set mRibbon = ribbon
    Err.Clear
    On Error GoTo 0
End Sub

' Ask every ribbon control to refresh. Called after any setting changes and
' when the active document changes (clsAppEvents).
Public Sub RefreshRibbon()
    On Error Resume Next
    If Not mRibbon Is Nothing Then mRibbon.Invalidate
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub RbnGetPressed(control As Variant, ByRef returnedVal As Variant)
    Dim doc As Document
    returnedVal = False
    On Error Resume Next
    Set doc = ActiveDocument
    If doc Is Nothing Then Exit Sub
    Select Case control.Id
        Case "LingTeXAlignWord"
            returnedVal = (SettingGranularity(doc) = igtWordAligned)
        Case "LingTeXAlignMorpheme"
            returnedVal = (SettingGranularity(doc) = igtMorphemeAligned)
        Case "LingTeXRewrapOnSaveToggle"
            returnedVal = SettingRewrapOnSave(doc)
        Case "LingTeXRewrapOnLeaveToggle"
            returnedVal = SettingRewrapOnSelectionChange(doc)
        Case "LingTeXInitialCapToggle"
            returnedVal = SettingGramGlossInitialCap(doc)
        Case "LingTeXNumbersToggle"
            returnedVal = SettingNumberExamples(doc)
    End Select
    Err.Clear
    On Error GoTo 0
End Sub

Public Sub RbnToggle(control As Variant, pressed As Boolean)
    Dim doc As Document
    On Error Resume Next
    Set doc = ActiveDocument
    If doc Is Nothing Then Exit Sub
    EnsureHooks
    Select Case control.Id
        Case "LingTeXAlignWord"
            SetSettingGranularity doc, igtWordAligned
        Case "LingTeXAlignMorpheme"
            SetSettingGranularity doc, igtMorphemeAligned
        Case "LingTeXRewrapOnSaveToggle"
            SetSettingRewrapOnSave doc, pressed
        Case "LingTeXRewrapOnLeaveToggle"
            SetSettingRewrapOnSelectionChange doc, pressed
        Case "LingTeXInitialCapToggle"
            SetSettingGramGlossInitialCap doc, pressed
        Case "LingTeXNumbersToggle"
            SetSettingNumberExamples doc, pressed
    End Select
    Err.Clear
    On Error GoTo 0
    RefreshRibbon
End Sub

Public Sub RbnInsert(control As Variant)
    LingTeXInsertInterlinear
End Sub

Public Sub RbnRewrapCurrent(control As Variant)
    LingTeXRewrapCurrent
End Sub

Public Sub RbnRewrapAll(control As Variant)
    LingTeXRewrapAll
End Sub

Public Sub RbnIndent(control As Variant)
    LingTeXIndentExample
End Sub

Public Sub RbnOutdent(control As Variant)
    LingTeXOutdentExample
End Sub

Public Sub RbnSplitColumn(control As Variant)
    LingTeXSplitColumn
End Sub

Public Sub RbnMergeColumns(control As Variant)
    LingTeXMergeColumns
End Sub

Public Sub RbnCheck(control As Variant)
    LingTeXCheckExample
End Sub

Public Sub RbnConvertTable(control As Variant)
    LingTeXConvertTableToIgt
End Sub

Public Sub RbnFromText(control As Variant)
    LingTeXTextToInterlinear
End Sub

Public Sub RbnAlignByWord(control As Variant)
    LingTeXAlignByWord
End Sub

Public Sub RbnAlignByMorpheme(control As Variant)
    LingTeXAlignByMorpheme
End Sub

Public Sub RbnToggleRewrapOnSave(control As Variant)
    LingTeXToggleRewrapOnSave
End Sub

Public Sub RbnToggleRewrapOnSelectionChange(control As Variant)
    LingTeXToggleRewrapOnSelectionChange
End Sub

Public Sub RbnToggleGramGlossInitialCap(control As Variant)
    LingTeXToggleGramGlossInitialCap
End Sub

Public Sub RbnShowSettings(control As Variant)
    LingTeXSettings
End Sub

Public Sub RbnInstallShortcuts(control As Variant)
    LingTeXInstallShortcuts
End Sub

Public Sub RbnShowShortcuts(control As Variant)
    LingTeXShowShortcuts
End Sub

Public Sub RbnToggleExampleNumbers(control As Variant)
    LingTeXToggleExampleNumbers
End Sub

Public Sub RbnResetStyles(control As Variant)
    LingTeXResetStyles
End Sub
