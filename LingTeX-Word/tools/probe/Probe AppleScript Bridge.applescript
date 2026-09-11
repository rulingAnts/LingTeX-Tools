-- ===========================================================================
-- LingTeX-Word  --  does Mac Word expose a VBA bridge to AppleScript?
--
-- WHAT THIS DOES
--   Asks Word, at run time, whether it understands any of the AppleScript terms
--   that can run VBA. Nothing is installed, created or changed. It only asks.
--
--   If one of them works, three things become possible. If none works, the
--   fallback is File > Import File... thirteen times: dull, but reliable.
--
--   1. THE BUILD BECOMES SCRIPTED. A script could inject a bootstrap macro, run
--      it to import all thirteen modules, and save the template -- no pasting and
--      no clicking. This is the main prize.
--
--   2. THE MAC INSTALLER COULD VERIFY ITSELF. Today it can only copy the .dotm
--      into Word's startup folder and hope. With a VBA bridge it could restart
--      Word, run a macro, and confirm the add-in actually loaded. That matters:
--      the known silent failure is macOS quarantining a .dotm downloaded inside a
--      zip, after which Word refuses to load it and the user sees a successful
--      install and no ribbon.
--
--   3. (Possible, probably not worth it.) The installer could build the .dotm on
--      the user's machine from the .bas files, removing the committed binary
--      entirely. Attractive, but only on Mac: the Windows equivalent needs the
--      AccessVBOM registry setting flipped, which is a macro-security change not
--      worth asking of users. Asymmetric installers cost more than the binary
--      does, especially as CI already verifies the binary has not drifted from
--      the sources.
--
-- HOW TO RUN
--   1. Double-click this file. It opens in Script Editor as plain text.
--   2. Press the Run button (or Command-R).
--   3. Word will launch if it is not already open. That is expected.
--   4. Copy the result text and send it back.
--
-- WHY IT IS WRITTEN THE WAY IT IS
--   Each candidate term is wrapped in `run script` with the code as a STRING.
--   AppleScript normally compiles a whole script before running it, so naming a
--   term Word does not understand would stop the file compiling at all and we
--   would learn nothing. `run script` defers compilation to run time, which turns
--   "Word has never heard of this" into an error we can catch and report.
-- ===========================================================================

set report to {}

-- 0. Is Word scriptable at all, and which version?
try
	set v to run script "tell application \"Microsoft Word\" to return version as text"
	set end of report to "Word is scriptable.  version = " & v
on error errMsg number errNum
	set end of report to "Word is NOT scriptable: " & errNum & "  " & errMsg
	set end of report to "Everything below will fail for the same reason."
end try

-- 1. `do Visual Basic` -- the Excel-for-Mac style bridge. If Word has it, a
--    script can execute arbitrary VBA directly, which is all we need.
try
	run script "tell application \"Microsoft Word\" to do Visual Basic \"Dim s As String\""
	set end of report to "do Visual Basic              WORKS  <-- fully scriptable build"
on error errMsg number errNum
	set end of report to "do Visual Basic              no  (" & errNum & ")"
end try

-- 2. `run VB macro` -- runs a macro that already exists. Weaker, but enough:
--    one pasted bootstrap could then be driven from a script.
try
	run script "tell application \"Microsoft Word\" to run VB macro macro name \"LingTeXNoSuchMacro\""
	set end of report to "run VB macro                 WORKS (and found a macro, unexpectedly)"
on error errMsg number errNum
	if errNum is -1708 or errMsg contains "doesn" then
		set end of report to "run VB macro                 TERM EXISTS  (macro not found, as expected) <-- usable"
	else
		set end of report to "run VB macro                 no  (" & errNum & "  " & errMsg & ")"
	end if
end try

-- 3. Can a script save a document as a macro-enabled template? Even with no VBA
--    bridge, this would automate the final Save As step of the build.
try
	run script "tell application \"Microsoft Word\" to return name of default file converter"
	set end of report to "file converters reachable    yes"
on error errNum
	set end of report to "file converters reachable    no"
end try

-- 4. Where Word keeps its startup add-ins, so the installer can be certain.
try
	set p to run script "tell application \"Microsoft Word\" to return path to special folder \"startup\" as text"
	set end of report to "startup folder               " & p
on error errMsg number errNum
	set end of report to "startup folder               not reported  (" & errNum & ")"
end try

set out to "LingTeX-Word  --  AppleScript bridge probe" & return
set out to out & "==========================================" & return
repeat with r in report
	set out to out & (r as text) & return
end repeat

-- Shown in the Result pane, and also as a dialog so it is easy to copy.
display dialog out buttons {"OK"} default button "OK"
return out
