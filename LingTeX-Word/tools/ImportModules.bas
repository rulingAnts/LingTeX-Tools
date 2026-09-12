Attribute VB_Name = "modImport"
Option Explicit

'=============================================================================
' modImport  --  LingTeX-Word
'
' ONE PASTE, THEN THE OTHER THIRTEEN MODULES IMPORT THEMSELVES.
'
' Replaces fourteen trips through File > Import File..., and can build the
' distributable template too.
'
' ---------------------------------------------------------------------------
' THIS ONLY WORKS IF VBA IS ALLOWED TO SEE ITS OWN PROJECT
'
' Reading or writing a VBA project from VBA is gated by a trust setting. Without
' it, every call below fails with error 6068, "Programmatic access to Visual Basic
' Project is not trusted."
'
'   WINDOWS:  File > Options > Trust Center > Trust Center Settings...
'             > Macro Settings > tick "Trust access to the VBA project object
'             model".  Then restart Word.
'
'   MAC:      Word > Preferences > Security & Privacy > tick the SAME setting,
'             "Trust access to the VBA project object model".  Then restart Word.
'
' It works on both. An earlier version of this comment said there was no such
' setting on Mac and that the access was blocked there with no way to grant it --
' because the probe (tools/probe/modProbe.bas section 14) reported BLOCKED on a Mac
' where the setting had not been ticked yet, and that one measurement got written
' down as a fact about the platform. Confirmed since on Mac Word 16.112: both
' ImportLingTeXModules and VerifyLingTeXModules, all fourteen modules, both
' classes as classes. There is no build-on-Windows, test-on-Mac split to make.
'
' NOTE ON SECURITY.  That setting exists for a good reason -- it lets code rewrite
' code. This add-in never asks an end user to enable it, and its installer does
' not touch it. It is a setting for whoever BUILDS the template, on their own
' machine, and it is reasonable to turn it back off afterwards.
' ---------------------------------------------------------------------------
'
' HOW TO RUN
'   1. Keep this document in your clone's LingTeX-Word folder, beside src/ --
'      that is where the modules are read from. (SRC_FOLDER below can override.)
'   2. Insert > Module, paste this file in (without its first line, which the
'      importer reads and which is a compile error if typed), name it modImport.
'   3. Run  ImportLingTeXModules  from the Immediate window.
'   4. Run  VerifyLingTeXModules   -- confirms all fourteen are there and the two
'      class modules really are classes. Do this before running any tests.
'   5. Optionally run  SaveAsTemplate  to write LingTeX-Word.dotm.
'
' THE TWELVE STANDARD MODULES AND THE TWO CLASS MODULES ARE NOT THE SAME JOB.
'
' The .bas files import cleanly and always have. The .cls files are the part that
' goes wrong: VBComponents.Import decides a file's component type by parsing its
' header, and when it misreads the .cls preamble it creates a STANDARD module with
' those lines left in the code as syntax errors -- which reads as a bug in the
' module, not as a bad import.
'
' So Import is never called on a .cls here. The classes are created explicitly
' instead, and if that does not work on your machine the report names the two files
' to paste and the four steps, rather than failing and leaving you to work it out.
' Set IMPORT_CLASS_MODULES to False to skip the attempt and go straight to pasting.
'
' Re-running is safe: a module that is already present is replaced, so this is
' also how to pick up changes to src/ without rebuilding by hand.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-- The folder holding the .bas and .cls files. Empty means "the src folder
'   beside this document": the document lives in LingTeX-Word/, so
'   ThisDocument.Path & "src" is right on every clone and both platforms, and
'   nothing has to be edited. Set it only to import from somewhere else. A path
'   rather than a file picker because Application.FileDialog does not exist on
'   Mac Word (probe section 15). No trailing separator.
'     Windows example:  "C:\GIT\LingTeX-Tools\LingTeX-Word\src"
'     Mac example:      "/Users/Seth/GIT/LingTeX-Tools/LingTeX-Word/src"
'   (Before 2026-09-12 this had to be set by hand, and a .docm committed from the
'   Mac carried the Mac path onto Windows, which imported from a stale clone.)
Private Const SRC_FOLDER As String = ""

'-- Where SaveAsTemplate writes the template. Empty means "beside SRC_FOLDER",
'   i.e. the LingTeX-Word folder, which is where the repository expects it.
Private Const DOTM_PATH As String = ""

' The twelve standard modules, in a deterministic order. VBA resolves names across
' the whole project, so the order does not affect compilation; it only makes the log
' readable and keeps stage 1 together at the top.
Private Const MODULE_LIST As String = _
    "modFlexParse.bas|modIgtModel.bas|modLeipzig.bas|modWrap.bas|" & _
    "modTests.bas|" & _
    "modStyles.bas|modSettings.bas|modMeasure.bas|modRender.bas|" & _
    "modReadBack.bas|modLingTeX.bas|modDocTests.bas"

' The two class modules, kept separate because they are the part that goes wrong.
Private Const CLASS_LIST As String = "clsIgtWarning.cls|clsAppEvents.cls"

'-- Try to create the class modules from code, or leave them to you? ----------
'
' Importing a .cls is the one unreliable step here. VBComponents.Import decides what
' kind of component to create by parsing the file header, and when it misreads the
' preamble it makes a STANDARD module with those lines sitting in the code as syntax
' errors -- which then reads as a bug in the module rather than a bad import.
'
' So this macro never calls Import on a .cls. With this True it creates the
' component explicitly instead (VBComponents.Add, set the name, install the source),
' which has nothing left to guess at. With it False it skips them entirely and tells
' you which two files to paste into hand-made Class Modules.
'
' Either way the twelve standard modules come in the easy way, and the report at the
' end says exactly what is left to do.
Private Const IMPORT_CLASS_MODULES As Boolean = True

' Set by ImportLingTeXModulesQuiet: reports go to a file beside the document
' instead of a dialog, so a script can drive this. Same convention as the test
' suites (see modTests.ReportFolderPath); duplicated here because this module is
' pasted alone and may reference nothing in the engine.
Private mQuiet As Boolean
Private Const REPORT_FOLDER As String = "LingTeX-Word-reports"

' Where the clone's LingTeX-Word folder is, kept as a document variable INSIDE
' this file, so that the template can live in Word's STARTUP folder -- loaded
' as a global add-in, which is what gives every document the macros, the
' ribbon tab, the shortcuts and AutoExec -- and still read src/ and write its
' reports in the repository. Set once with SetDevRoot. Empty: the folder this
' file is in (a .docm sitting in LingTeX-Word/, the earlier arrangement).
Private Const DEV_ROOT_VAR As String = "LingTeX_DevRoot"

Private Function SrcFolder() As String
    SrcFolder = SRC_FOLDER
    If SrcFolder = "" Then SrcFolder = DevRoot() & Application.PathSeparator & "src"
End Function

' The clone's LingTeX-Word folder: the stored variable, else this file's folder.
Private Function DevRoot() As String
    Dim v As String
    On Error Resume Next
    v = CStr(ThisDocument.Variables(DEV_ROOT_VAR).Value)
    If Err.Number <> 0 Then v = ""
    Err.Clear
    If v = "" Then v = ThisDocument.Path
    Err.Clear
    On Error GoTo 0
    If Right$(v, 1) = Application.PathSeparator Then v = Left$(v, Len(v) - 1)
    DevRoot = v
End Function

' Tell this file where the clone is. Run it ONCE, from the template opened for
' editing (before it is moved to STARTUP is easiest, when the default is right),
' then save the template. The by-hand loop in TESTING-MAC.md walks through it.
Public Sub SetDevRoot()
    Dim v As String, sep As String
    sep = Application.PathSeparator
    v = InputBox("The LingTeX-Word folder of your clone (the one that holds " & _
                 "src/ and tools/). The modules are imported from its src/ and " & _
                 "the test reports are written beside it, wherever this " & _
                 "template itself lives.", "LingTeX-Word: where is the clone?", _
                 DevRoot())
    If v = "" Then Exit Sub
    If Right$(v, 1) = sep Then v = Left$(v, Len(v) - 1)
    If Dir(v & sep & "src", vbDirectory) = "" Then
        MsgBox "There is no src folder in " & v & ". Not saved.", vbExclamation, _
               "LingTeX-Word"
        Exit Sub
    End If
    On Error Resume Next
    ThisDocument.Variables(DEV_ROOT_VAR).Value = v
    If Err.Number <> 0 Then
        Err.Clear
        ThisDocument.Variables.Add Name:=DEV_ROOT_VAR, Value:=v
    End If
    Err.Clear
    On Error GoTo 0
    MsgBox "This template will import from" & vbCr & v & sep & "src" & vbCr & _
           "and write reports to" & vbCr & v & sep & REPORT_FOLDER & vbCr & vbCr & _
           "Save the template now (Cmd+S / Ctrl+S) so it remembers.", _
           vbInformation, "LingTeX-Word"
End Sub

'=============================================================================
' -- IMPORT -----------------------------------------------------------------
'=============================================================================

' Import, then verify, with every report appended to
' <document folder>/LingTeX-Word-reports/ImportModules.txt and no dialogs.
' For tools/run-in-word.sh and tools/run-in-word.ps1.
Public Sub ImportLingTeXModulesQuiet()
    mQuiet = True
    ImportLingTeXModules
    VerifyLingTeXModules
    SaveThisFile
    mQuiet = False
End Sub

' Save the file the modules were just imported into, so a template loaded from
' STARTUP carries the current modules on disk for the next Word launch. Whether
' Word lets a loaded global template save itself is the kind of thing the log
' has to say rather than the code assume.
Private Sub SaveThisFile()
    On Error Resume Next
    ThisDocument.Save
    If Err.Number = 0 Then
        AppendReport "saved " & ThisDocument.Name & " with the modules just imported" & vbCr
    Else
        AppendReport "NOT saved: " & ThisDocument.Name & " (" & CStr(Err.Number) & _
                     ": " & Err.Description & "); the modules are current in " & _
                     "memory until Word quits" & vbCr
        Err.Clear
    End If
    On Error GoTo 0
End Sub

Public Sub ImportLingTeXModules()
    Dim vbp As Object
    Dim log As String
    Dim okCount As Long, failCount As Long, todoCount As Long
    Dim todo As String
    Dim msg As String

    If SrcFolder() = "" Or SrcFolder() = Application.PathSeparator & "src" Then
        MsgBox "This document has no folder yet (save it inside LingTeX-Word/), " & _
               "or set SRC_FOLDER at the top of modImport to the full path of the " & _
               "LingTeX-Word/src folder in your clone, then run this again.", _
               vbExclamation, "LingTeX-Word import"
        Exit Sub
    End If

    Set vbp = GetProject()
    If vbp Is Nothing Then Exit Sub              ' GetProject explains why

    log = log & "  from     " & SrcFolder() & vbCr
    '-- the twelve standard modules: Import, which is reliable for these ------
    ImportGroup vbp, MODULE_LIST, False, log, okCount, failCount, todo, todoCount

    '-- the two class modules: explicitly created, or left to you -------------
    If IMPORT_CLASS_MODULES Then
        ImportGroup vbp, CLASS_LIST, True, log, okCount, failCount, todo, todoCount
    Else
        log = log & "  skipped  clsIgtWarning.cls   (paste by hand)" & vbCr
        log = log & "  skipped  clsAppEvents.cls    (paste by hand)" & vbCr
        todo = todo & PasteInstructions("clsIgtWarning", "05") & _
               PasteInstructions("clsAppEvents", "14")
        todoCount = todoCount + 2
    End If

    msg = "Imported " & CStr(okCount) & " of " & CStr(TotalModuleCount()) & _
          " modules"
    If failCount > 0 Then msg = msg & ", " & CStr(failCount) & " FAILED"
    msg = msg & "." & vbCr & vbCr & log

    If todoCount > 0 Then
        msg = msg & vbCr & "STILL TO DO -- " & CStr(todoCount) & _
              " module(s) you have to add by hand:" & vbCr & todo & vbCr & _
              "Run  sh LingTeX-Word/tools/make-paste-bundle.sh  first if you have " & _
              "not already; it writes the stripped, paste-ready copies." & vbCr
    End If

    msg = msg & vbCr & "Then:  VerifyLingTeXModules" & vbCr & _
          "It confirms all fourteen are present and the two classes really are " & _
          "classes, before you run anything."

    Report msg, (failCount = 0 And todoCount = 0)
End Sub

'-----------------------------------------------------------------------------
' Bring in one group of files, accumulating the log and the counts.
'-----------------------------------------------------------------------------
Private Sub ImportGroup(vbp As Object, ByVal fileList As String, _
        ByVal asClass As Boolean, ByRef log As String, _
        ByRef okCount As Long, ByRef failCount As Long, _
        ByRef todo As String, ByRef todoCount As Long)

    Dim names() As String
    Dim i As Long
    Dim leaf As String, fullPath As String, compName As String
    Dim note As String

    names = Split(fileList, "|")
    For i = 0 To UBound(names)
        leaf = names(i)
        fullPath = JoinPath(SrcFolder(), leaf)
        compName = BaseName(leaf)

        If Not FileExists(fullPath) Then
            log = log & "  MISSING  " & leaf & vbCr
            failCount = failCount + 1
        Else
            ' Replace rather than duplicate, so re-running picks up edits.
            RemoveComponent vbp, compName

            note = ImportOne(vbp, fullPath, compName, asClass)
            If note = "" Then
                log = log & "  ok       " & leaf & _
                      IIf(asClass, "   (class module, created explicitly)", "") & vbCr
                okCount = okCount + 1
            ElseIf asClass Then
                ' A class that could not be created from code is not a failure to
                ' argue with -- it is two minutes of pasting. Say which file.
                log = log & "  by hand  " & leaf & "  (" & note & ")" & vbCr
                todo = todo & PasteInstructions(compName, _
                           IIf(compName = "clsIgtWarning", "05", "14"))
                todoCount = todoCount + 1
            Else
                log = log & "  FAILED   " & leaf & "  (" & note & ")" & vbCr
                failCount = failCount + 1
            End If
        End If
    Next i
End Sub

Private Function TotalModuleCount() As Long
    TotalModuleCount = UBound(Split(MODULE_LIST, "|")) + 1 + _
                       UBound(Split(CLASS_LIST, "|")) + 1
End Function

Private Function PasteInstructions(ByVal compName As String, _
        ByVal num As String) As String

    PasteInstructions = _
        "  " & compName & vbCr & _
        "    1. Insert > Class Module   (NOT Insert > Module)" & vbCr & _
        "    2. Open  LingTeX-Word/build/paste/" & num & "-" & compName & ".txt" & _
        vbCr & _
        "       and paste the whole thing in" & vbCr & _
        "    3. Properties pane, (Name) row:  " & compName & vbCr & _
        "    4. Instancing should read  1 - Private  (the default; check it)" & vbCr
End Function

'-----------------------------------------------------------------------------
' IS THE PROJECT ACTUALLY COMPLETE?
'
' Run this after importing, before running any tests. It is here because the ways
' this goes wrong are all quiet: a class that came in as a standard module compiles
' nowhere and the error names a line in the middle of it; a module that failed to
' import leaves the whole project failing to compile on a name that is simply
' absent; and a missing module looks exactly like a bug in the module that calls it.
'
' It reads the component TYPE out of the VBA project, which is the authoritative
' answer. It deliberately does NOT do "Set o = New clsIgtWarning" as a second
' opinion, however tempting: this module is pasted on its own into a bare project,
' so a reference to clsIgtWarning would stop the project compiling until the classes
' were present -- and the macro whose job is to bring them in would not run. The
' linter has a rule for that now.
'
' Type it yourself in the Immediate window once everything is in, if you want the
' second opinion:
'
'     ?TypeName(New clsIgtWarning)
'
' which prints clsIgtWarning if it is really a class and errors if it is not.
' RunDocTests checks both classes this way too.
'
' Needs the Trust Center setting, like the import itself.
'-----------------------------------------------------------------------------
Public Sub VerifyLingTeXModules()
    Dim vbp As Object
    Dim names() As String
    Dim i As Long
    Dim compName As String
    Dim log As String
    Dim problems As Long
    Dim kind As Long

    Set vbp = GetProject()
    If vbp Is Nothing Then Exit Sub

    names = Split(MODULE_LIST & "|" & CLASS_LIST, "|")
    For i = 0 To UBound(names)
        compName = BaseName(names(i))
        kind = ComponentKind(vbp, compName)

        Select Case kind
            Case 0
                log = log & "  MISSING       " & compName & vbCr
                problems = problems + 1
            Case 1                                  ' vbext_ct_StdModule
                If IsClassFile(names(i)) Then
                    log = log & "  WRONG KIND    " & compName & _
                          "  -- it is a standard module and must be a CLASS" & vbCr
                    problems = problems + 1
                Else
                    log = log & "  ok            " & compName & vbCr
                End If
            Case 2                                  ' vbext_ct_ClassModule
                If IsClassFile(names(i)) Then
                    log = log & "  ok  (class)   " & compName & vbCr
                Else
                    log = log & "  WRONG KIND    " & compName & _
                          "  -- it is a class and must be a standard module" & vbCr
                    problems = problems + 1
                End If
            Case Else
                log = log & "  ODD KIND      " & compName & _
                      "  (component type " & CStr(kind) & ")" & vbCr
                problems = problems + 1
        End Select
    Next i

    If problems = 0 Then
        Report "All " & CStr(UBound(names) + 1) & " modules present and of the " & _
               "right kind." & vbCr & vbCr & log & vbCr & _
               "Next:  RunAllTests    (expect ALL PASS, 79 checks)" & vbCr & _
               "then:  RunDocTests    (expect ALL PASS, about 250 checks)" & vbCr & _
               "then:  AutoExec       (arms the save hook)", True
    Else
        Report CStr(problems) & " problem(s) with the project:" & vbCr & vbCr & log & _
               vbCr & "A class module that came in as a standard module is the " & _
               "usual one. Delete it and redo it with Insert > Class Module and " & _
               "the matching file in LingTeX-Word/build/paste/.", False
    End If
End Sub

' 0 = not present, otherwise the VBComponent Type (1 standard, 2 class, 3 form).
Private Function ComponentKind(vbp As Object, ByVal compName As String) As Long
    Dim c As Object
    On Error Resume Next
    Set c = vbp.VBComponents(compName)
    If Err.Number = 0 Then
        If Not c Is Nothing Then ComponentKind = c.Type
    End If
    Err.Clear
    On Error GoTo 0
End Function

'-----------------------------------------------------------------------------
' Save the active document as the macro-enabled template.
'
' Run this on a document that has the modules imported. It does NOT inject the
' ribbon -- that is a separate step done outside Word, because the ribbon lives in
' a plain-XML part of the package and tools/build-dotm.sh can add it with nothing
' but zip. Save from Word first, inject afterwards.
'-----------------------------------------------------------------------------
Public Sub SaveAsTemplate()
    Dim target As String

    target = DOTM_PATH
    If target = "" Then
        target = JoinPath(ParentFolder(SrcFolder()), "LingTeX-Word.dotm")
    End If

    On Error Resume Next
    ' 13 = wdFormatXMLTemplateMacroEnabled
    ActiveDocument.SaveAs2 FileName:=target, FileFormat:=13
    If Err.Number <> 0 Then
        Report "Could not save the template:" & vbCr & vbCr & _
               CStr(Err.Number) & ": " & Err.Description, False
        Err.Clear
        Exit Sub
    End If
    On Error GoTo 0

    Report "Saved:" & vbCr & vbCr & target & vbCr & vbCr & _
           "Now run tools/build-dotm.sh to inject the ribbon and write the " & _
           "source manifest.", True
End Sub

'=============================================================================
' -- HELPERS ----------------------------------------------------------------
'=============================================================================

'-----------------------------------------------------------------------------
' The VBA project, or Nothing with an explanation.
'
' 6068 is the one error worth handling by name, because the fix is a setting
' rather than anything about this code, and the message is otherwise cryptic.
'-----------------------------------------------------------------------------
'-----------------------------------------------------------------------------
' Bring one file in. Returns "" on success, or a description of what failed.
'
' A CLASS MODULE IS NEVER IMPORTED. VBComponents.Import decides what kind of
' component to create by parsing the file header, and when it misreads the
'
'     VERSION 1.0 CLASS
'     BEGIN
'       MultiUse = -1  'True
'     END
'
' preamble it creates a STANDARD module instead, leaving those four lines in the
' code as syntax errors. The module then cannot compile at all -- clsAppEvents
' declares "Private WithEvents mApp As Word.Application", which is legal only in a
' class module -- and the failure reads as a bug in the module rather than as a
' bad import. A bare-LF .cls is one way to trigger it (the repository pins CRLF in
' .gitattributes for exactly this reason), but rather than depend on that holding,
' classes are built explicitly here: create the component, name it, and put the
' source in. There is nothing left to guess at.
'
' Standard modules still go through Import, which reads Attribute VB_Name and so
' names them without being told.
'-----------------------------------------------------------------------------
Private Function ImportOne(vbp As Object, ByVal fullPath As String, _
        ByVal compName As String, ByVal asClass As Boolean) As String

    Dim comp As Object
    Dim code As String

    If Not asClass Then
        On Error Resume Next
        vbp.VBComponents.Import fullPath
        If Err.Number <> 0 Then
            ImportOne = CStr(Err.Number) & ": " & Err.Description
            Err.Clear
        End If
        On Error GoTo 0
        Exit Function
    End If

    code = ReadTextFile(fullPath)
    If code = "" Then
        ImportOne = "could not read the file, or it is empty"
        Exit Function
    End If
    code = StripVbaMetadata(code)

    On Error Resume Next
    ' 2 = vbext_ct_ClassModule. The constant is not available late-bound.
    Set comp = vbp.VBComponents.Add(2)
    If Err.Number <> 0 Or comp Is Nothing Then
        ImportOne = "could not add a class module (" & CStr(Err.Number) & ": " & _
                    Err.Description & ")"
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If

    comp.Name = compName
    If Err.Number <> 0 Then
        ImportOne = "could not name it " & compName & " (" & CStr(Err.Number) & _
                    ": " & Err.Description & ")"
        Err.Clear
        On Error GoTo 0
        Exit Function
    End If

    ' A new class module may already carry Option Explicit, depending on the
    ' editor's "Require Variable Declaration" setting, and a second one is a
    ' compile error. Clear it out before adding the source.
    With comp.CodeModule
        If .CountOfLines > 0 Then .DeleteLines 1, .CountOfLines
        .AddFromString code
    End With
    If Err.Number <> 0 Then
        ImportOne = "could not add the code (" & CStr(Err.Number) & ": " & _
                    Err.Description & ")"
        Err.Clear
    End If
    On Error GoTo 0
End Function

Private Function IsClassFile(ByVal leaf As String) As Boolean
    IsClassFile = (LCase$(Right$(leaf, 4)) = ".cls")
End Function

'-----------------------------------------------------------------------------
' A whole text file as one string, with this platform's line endings.
'
' Read as binary rather than with Line Input so the file's own line endings do
' not matter: both are normalised here. That is the point of doing it this way --
' the bug being avoided is a line-ending bug.
'-----------------------------------------------------------------------------
Private Function ReadTextFile(ByVal fullPath As String) As String
    Dim fn As Integer
    Dim buf As String

    On Error GoTo Failed
    fn = FreeFile
    Open fullPath For Binary Access Read As #fn
    If LOF(fn) > 0 Then
        buf = Space$(LOF(fn))
        Get #fn, 1, buf
    End If
    Close #fn

    ' CRLF -> LF -> CR -> LF collapses every convention to LF, then one pass
    ' back to THIS platform's newline: CRLF on Windows, CR on Mac (vbNewLine).
    ' Mac Word's AddFromString treats CR and LF as two line breaks, so a CRLF
    ' string arrives double-spaced -- harmless until a "_" continuation is
    ' followed by one of those blank lines, which is a syntax error (found in
    ' clsAppEvents, 2026-09-12). Doing it in this order means a CRLF file is not
    ' turned into CR CR LF.
    buf = Replace(buf, vbCrLf, vbLf)
    buf = Replace(buf, vbCr, vbLf)
    ReadTextFile = Replace(buf, vbLf, vbNewLine)
    Exit Function

Failed:
    On Error Resume Next
    Close #fn
    Err.Clear
    On Error GoTo 0
End Function

'-----------------------------------------------------------------------------
' Strip what the importer reads and the editor rejects: the .cls preamble and
' every Attribute line, including the member attribute buried mid-file in
' clsAppEvents.  Mirrors strip_metadata in tools/make-paste-bundle.sh.
'-----------------------------------------------------------------------------
Private Function StripVbaMetadata(ByVal code As String) As String
    Dim lines() As String
    Dim i As Long
    Dim ln As String, t As String
    Dim inPre As Boolean, started As Boolean
    Dim out As String

    lines = Split(code, vbCrLf)
    For i = 0 To UBound(lines)
        ln = lines(i)
        t = Trim$(ln)

        If Left$(t, 12) = "VERSION 1.0 " Then
            ' skip
        ElseIf t = "BEGIN" And Not started Then
            inPre = True
        ElseIf t = "END" And inPre Then
            inPre = False
        ElseIf inPre Then
            ' skip the MultiUse line and anything else in the preamble
        ElseIf Left$(t, 10) = "Attribute " Then
            ' skip
        ElseIf Not started And t = "" Then
            ' skip leading blanks so the result begins at Option Explicit
        Else
            started = True
            If out = "" Then
                out = ln
            Else
                out = out & vbCrLf & ln
            End If
        End If
    Next i

    StripVbaMetadata = out
End Function

Private Function GetProject() As Object
    Dim vbp As Object

    ' THIS file's project -- the template's, when it is loaded as a global
    ' add-in and the active document is whatever the user has open. It used to
    ' be ActiveDocument.VBProject, which is the same thing only while the file
    ' holding the code is the one in front.
    On Error Resume Next
    Set vbp = ThisDocument.VBProject
    If Err.Number = 0 Then
        Set GetProject = vbp
        Exit Function
    End If

    If Err.Number = 6068 Then
        Err.Clear
        MsgBox "VBA is not allowed to see its own project on this machine yet, " & _
               "so the modules cannot be imported automatically." & vbCr & vbCr & _
               "Tick ""Trust access to the VBA project object model"", restart " & _
               "Word, and run this again. It lives at:" & vbCr & vbCr & _
               "WINDOWS: File > Options > Trust Center > Trust Center " & _
               "Settings... > Macro Settings" & vbCr & _
               "MAC:     Word > Preferences > Security & Privacy" & vbCr & vbCr & _
               "Same label on both.", _
               vbExclamation, "LingTeX-Word import"
    Else
        MsgBox "Could not reach the VBA project: " & CStr(Err.Number) & ": " & _
               Err.Description, vbExclamation, "LingTeX-Word import"
        Err.Clear
    End If
    On Error GoTo 0
End Function

' Remove a component if it is already there, so importing is idempotent.
' Never removes the module this code is running from, which VBA would refuse.
Private Sub RemoveComponent(vbp As Object, ByVal compName As String)
    Dim c As Object
    If LCase$(compName) = "modimport" Then Exit Sub
    On Error Resume Next
    Set c = vbp.VBComponents(compName)
    If Err.Number = 0 Then
        If Not c Is Nothing Then vbp.VBComponents.Remove c
    End If
    Err.Clear
    On Error GoTo 0
End Sub

Private Function FileExists(ByVal p As String) As Boolean
    On Error Resume Next
    FileExists = (Dir(p) <> "")
    Err.Clear
    On Error GoTo 0
End Function

Private Function JoinPath(ByVal folder As String, ByVal leaf As String) As String
    Dim sep As String
    sep = Application.PathSeparator
    If Right$(folder, 1) = sep Then folder = Left$(folder, Len(folder) - 1)
    JoinPath = folder & sep & leaf
End Function

Private Function ParentFolder(ByVal p As String) As String
    Dim sep As String, i As Long
    sep = Application.PathSeparator
    If Right$(p, 1) = sep Then p = Left$(p, Len(p) - 1)
    i = InStrRev(p, sep)
    If i > 0 Then
        ParentFolder = Left$(p, i - 1)
    Else
        ParentFolder = p
    End If
End Function

Private Function BaseName(ByVal leaf As String) As String
    Dim i As Long
    i = InStrRev(leaf, ".")
    If i > 1 Then
        BaseName = Left$(leaf, i - 1)
    Else
        BaseName = leaf
    End If
End Function

' Same delivery as the probe and the tests: a dialog always, because Debug.Print
' alone is invisible unless the Immediate window happens to be open.
Private Sub Report(ByVal msg As String, ByVal good As Boolean)
    Debug.Print msg
    If mQuiet Then
        If AppendReport(IIf(good, "OK", "PROBLEM") & vbCr & msg) Then Exit Sub
    End If
    MsgBox msg, IIf(good, vbInformation, vbExclamation), "LingTeX-Word import"
End Sub

' Append one report to ImportModules.txt beside the document. True on success; a
' failure falls back to the dialog rather than raising.
Private Function AppendReport(ByVal text As String) As Boolean
    Dim folder As String, path As String, sep As String
    Dim fn As Integer

    On Error Resume Next
    folder = DevRoot()
    sep = Application.PathSeparator
    Err.Clear
    On Error GoTo 0
    If folder = "" Then Exit Function
    folder = folder & sep & REPORT_FOLDER

    On Error Resume Next
    If Dir(folder, vbDirectory) = "" Then MkDir folder
    Err.Clear
    On Error GoTo 0

    path = folder & sep & "ImportModules.txt"
    On Error GoTo Failed
    fn = FreeFile
    Open path For Append As #fn
    Print #fn, text
    Print #fn, ""
    Close #fn
    AppendReport = True
    Exit Function

Failed:
    On Error Resume Next
    Close #fn
    Err.Clear
End Function
