(*
	Install LingTeX-Word  --  Microsoft Word for Mac

	TO INSTALL:  click the Run button in the toolbar above (the triangle),
	or press Command-R, and follow the messages.

	WHAT IT DOES
	Copies LingTeX-Word.dotm, the file that came in the same folder as this
	script, into Word's Startup folder:

	    ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word

	Word loads everything in that folder when it starts, so from the next
	start the Interlinear tab is on the ribbon of every document. Nothing
	else on the Mac is touched, and no administrator password is needed.
	Word has to be quit while the file is copied; the script checks, and
	waits for you.

	Word may then ask whether to enable macros in LingTeX-Word.dotm: choose
	Enable Macros (Word > Preferences > Security can make that permanent).
	A message says LingTeX-Word is installed and lists its keyboard shortcuts
	(Command-Option-Shift and a letter).

	TO REMOVE IT LATER
	Run "Uninstall LingTeX-Word.applescript" from this folder the same way,
	or drag LingTeX-Word.dotm out of the Startup folder above.

	WHY A SCRIPT
	macOS refuses to run a downloaded installer that is not signed by a
	registered developer. A script opened in Script Editor is a document you
	can read, not a program the system has to trust, so this is the honest
	way in: every line that does anything is below, in plain sight.
*)

property templateName : "LingTeX-Word.dotm"
property startupFolder : "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word"

on run
	try
		set startupPath to (POSIX path of (path to home folder)) & startupFolder
		set destination to startupPath & "/" & templateName
		
		set source to findTemplate()
		waitForWordToQuit()
		
		do shell script "mkdir -p " & quoted form of startupPath
		do shell script "cp -f " & quoted form of source & " " & quoted form of destination
		-- A file that came from the internet is quarantined, and Word will not
		-- load a quarantined template from Startup. The copy is cleared.
		do shell script "xattr -d com.apple.quarantine " & quoted form of destination & " 2>/dev/null || true"
		
		set devNote to ""
		if fileExists(startupPath & "/LingTeX-Dev.dotm") then
			set devNote to return & return & "NOTE: LingTeX-Dev.dotm is in the same folder. That is the development rig, which loads its own copy of the code; with both, every command exists twice. Move LingTeX-Dev.dotm out of the Startup folder to test this install."
		end if
		
		set answer to button returned of (display dialog "LingTeX-Word is installed." & return & return & "Start Word. If it asks whether to enable macros in " & templateName & ", choose Enable Macros. A message then says LingTeX-Word is installed and lists its keyboard shortcuts; the Interlinear tab is on the ribbon of every document." & devNote buttons {"Show in Finder", "Done", "Start Word"} default button "Start Word" with title "Install LingTeX-Word" with icon note)
		if answer is "Start Word" then
			do shell script "open -b com.microsoft.Word"
		else if answer is "Show in Finder" then
			do shell script "open " & quoted form of startupPath
		end if
	on error message number errorNumber
		if errorNumber is not -128 then -- -128 is Cancel: nothing to say
			display dialog "LingTeX-Word was not installed." & return & return & message buttons {"OK"} default button "OK" with title "Install LingTeX-Word" with icon stop
		end if
	end try
end run

-- The template beside this script; failing that, wherever you point.
on findTemplate()
	set candidate to ""
	try
		set scriptFolder to do shell script "dirname " & quoted form of (POSIX path of (path to me))
		set candidate to scriptFolder & "/" & templateName
	end try
	if candidate is not "" and fileExists(candidate) then return candidate
	set chosen to choose file with prompt "Where is " & templateName & "? It is in the folder you unzipped, next to this script." default location (path to downloads folder)
	set chosenPath to POSIX path of chosen
	if chosenPath does not end with templateName then
		error "That is not " & templateName & ": " & chosenPath
	end if
	return chosenPath
end findTemplate

-- Word rewrites its Startup folder's contents into memory at launch and
-- holds the files open, so the copy waits until Word is quit.
on waitForWordToQuit()
	repeat while wordIsRunning()
		display dialog "Microsoft Word is open. Quit Word (Word menu > Quit Word), then click Continue." buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with title "Install LingTeX-Word" with icon caution
	end repeat
end waitForWordToQuit

on wordIsRunning()
	set answer to do shell script "pgrep -xq 'Microsoft Word' && echo yes || echo no"
	return answer is "yes"
end wordIsRunning

on fileExists(posixPath)
	set answer to do shell script "test -f " & quoted form of posixPath & " && echo yes || echo no"
	return answer is "yes"
end fileExists
