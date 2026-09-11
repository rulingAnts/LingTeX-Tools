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
'   MAC:      there is no equivalent setting in Word's interface, and the probe
'             (tools/probe/modProbe.bas section 14) found the access blocked on
'             Word 16.112 with no way to grant it.  On Mac, import the files by
'             hand instead -- see QUICKSTART.md.
'
' So in practice this is the Windows path. That is fine: the .dotm it produces is
' cross-platform, so you can build on Windows and test on Mac. Nothing about the
' template is Windows-specific.
'
' NOTE ON SECURITY.  That setting exists for a good reason -- it lets code rewrite
' code. This add-in never asks an end user to enable it, and its installer does
' not touch it. It is a setting for whoever BUILDS the template, on their own
' machine, and it is reasonable to turn it back off afterwards.
' ---------------------------------------------------------------------------
'
' HOW TO RUN
'   1. Set SRC_FOLDER below to the full path of LingTeX-Word/src in your clone.
'   2. Insert > Module, paste this file in (without its first line, which the
'      importer reads and which is a compile error if typed), name it modImport.
'   3. Run  ImportLingTeXModules  from the Immediate window.
'   4. Optionally run  SaveAsTemplate  to write LingTeX-Word.dotm.
'
' Re-running is safe: a module that is already present is replaced, so this is
' also how to pick up changes to src/ without rebuilding by hand.
'
' Pure ASCII on purpose -- see the header of modFlexParse.bas.
'=============================================================================

'-- SET THIS. The folder holding the .bas and .cls files, with no trailing
'   separator. A path is used rather than a file picker because
'   Application.FileDialog does not exist on Mac Word (probe section 15), and a
'   constant works the same everywhere.
'     Windows example:  "C:\Users\Seth\GIT\LingTeX-Tools\LingTeX-Word\src"
'     Mac example:      "/Users/Seth/GIT/LingTeX-Tools/LingTeX-Word/src"
Private Const SRC_FOLDER As String = ""

'-- Where SaveAsTemplate writes the template. Empty means "beside SRC_FOLDER",
'   i.e. the LingTeX-Word folder, which is where the repository expects it.
Private Const DOTM_PATH As String = ""

' Every module, in a deterministic order. VBA resolves names across the whole
' project, so the order does not affect compilation; it only makes the log
' readable and keeps stage 1 together at the top.
Private Const MODULE_LIST As String = _
    "modFlexParse.bas|modIgtModel.bas|modLeipzig.bas|modWrap.bas|" & _
    "clsIgtWarning.cls|modTests.bas|" & _
    "modStyles.bas|modSettings.bas|modMeasure.bas|modRender.bas|" & _
    "modReadBack.bas|modLingTeX.bas|modDocTests.bas|clsAppEvents.cls"


'=============================================================================
' -- IMPORT -----------------------------------------------------------------
'=============================================================================

Public Sub ImportLingTeXModules()
    Dim vbp As Object
    Dim names() As String
    Dim i As Long
    Dim leaf As String, fullPath As String
    Dim compName As String
    Dim note As String
    Dim log As String
    Dim okCount As Long, failCount As Long

    If SRC_FOLDER = "" Then
        MsgBox "Set SRC_FOLDER at the top of modImport to the full path of the " & _
               "LingTeX-Word/src folder in your clone, then run this again.", _
               vbExclamation, "LingTeX-Word import"
        Exit Sub
    End If

    Set vbp = GetProject()
    If vbp Is Nothing Then Exit Sub              ' GetProject explains why

    names = Split(MODULE_LIST, "|")

    For i = 0 To UBound(names)
        leaf = names(i)
        fullPath = JoinPath(SRC_FOLDER, leaf)
        compName = BaseName(leaf)

        If Not FileExists(fullPath) Then
            log = log & "  MISSING  " & leaf & vbCr
            failCount = failCount + 1
        Else
            ' Replace rather than duplicate, so re-running picks up edits.
            RemoveComponent vbp, compName

            note = ImportOne(vbp, fullPath, compName, IsClassFile(leaf))
            If note = "" Then
                log = log & "  ok       " & leaf & _
                      IIf(IsClassFile(leaf), "   (class module)", "") & vbCr
                okCount = okCount + 1
            Else
                log = log & "  FAILED   " & leaf & "  (" & note & ")" & vbCr
                failCount = failCount + 1
            End If
        End If
    Next i

    Report "Imported " & CStr(okCount) & " of " & CStr(UBound(names) + 1) & _
           " modules" & IIf(failCount > 0, ", " & CStr(failCount) & " FAILED", "") & _
           "." & vbCr & vbCr & log & vbCr & _
           "Next: run RunAllTests, then RunDocTests, then AutoExec.", _
           (failCount = 0)
End Sub

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
        target = JoinPath(ParentFolder(SRC_FOLDER), "LingTeX-Word.dotm")
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
' A whole text file as one string, with CRLF line endings.
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
    ' back to CRLF. Doing it in this order means a CRLF file is not turned into
    ' CR CR LF.
    buf = Replace(buf, vbCrLf, vbLf)
    buf = Replace(buf, vbCr, vbLf)
    ReadTextFile = Replace(buf, vbLf, vbCrLf)
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

    On Error Resume Next
    Set vbp = ActiveDocument.VBProject
    If Err.Number = 0 Then
        Set GetProject = vbp
        Exit Function
    End If

    If Err.Number = 6068 Then
        Err.Clear
        MsgBox "VBA is not allowed to see its own project on this machine, so " & _
               "the modules cannot be imported automatically." & vbCr & vbCr & _
               "WINDOWS: File > Options > Trust Center > Trust Center " & _
               "Settings... > Macro Settings, and tick ""Trust access to the " & _
               "VBA project object model"". Restart Word, then run this again." & _
               vbCr & vbCr & _
               "MAC: there is no equivalent setting. Import the files by hand " & _
               "with File > Import File... -- see QUICKSTART.md.", _
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
    MsgBox msg, IIf(good, vbInformation, vbExclamation), "LingTeX-Word import"
End Sub
