(*
	Uninstall LingTeX-Word  --  Microsoft Word for Mac

	TO REMOVE LINGTEX-WORD:  click the Run button in the toolbar above (the
	triangle), or press Command-R.

	WHAT IT DOES
	Deletes LingTeX-Word.dotm from Word's Startup folder:

	    ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word

	From the next start of Word the Interlinear tab is gone. Your documents
	are not touched: the examples in them are ordinary Word tables and stay
	exactly as they are; they simply stop re-wrapping themselves. Nothing
	else is deleted. Word has to be quit while the file is removed; the
	script checks, and waits for you.

	The keyboard shortcuts the add-in installed live in Word's Normal
	template. To take those out too, run LingTeXRemoveShortcuts from Tools >
	Macro > Macros before you uninstall.
*)

property templateName : "LingTeX-Word.dotm"
property startupFolder : "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word"

on run
	try
		set target to (POSIX path of (path to home folder)) & startupFolder & "/" & templateName
		if not fileExists(target) then
			display dialog "Nothing to remove: " & templateName & " is not in Word's Startup folder." buttons {"OK"} default button "OK" with title "Uninstall LingTeX-Word" with icon note
			return
		end if
		waitForWordToQuit()
		do shell script "rm -f " & quoted form of target
		display dialog "LingTeX-Word is removed. The Interlinear tab is gone from the next start of Word." buttons {"OK"} default button "OK" with title "Uninstall LingTeX-Word" with icon note
	on error message number errorNumber
		if errorNumber is not -128 then
			display dialog "LingTeX-Word was not removed." & return & return & message buttons {"OK"} default button "OK" with title "Uninstall LingTeX-Word" with icon stop
		end if
	end try
end run

on waitForWordToQuit()
	repeat while wordIsRunning()
		display dialog "Microsoft Word is open. Quit Word (Word menu > Quit Word), then click Continue." buttons {"Cancel", "Continue"} default button "Continue" cancel button "Cancel" with title "Uninstall LingTeX-Word" with icon caution
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
