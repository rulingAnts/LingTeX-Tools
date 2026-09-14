(*
    UNINSTALL LINGTEX-WORD
    for Microsoft Word on the Mac

    TO REMOVE LINGTEX-WORD
    Click the Run button in the toolbar above (the triangle, like Play), or
    press Command-R.

    WHAT IT DOES
    Deletes LingTeX-Word.dotm from your Word Startup folder:

        ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word

    From the next start of Word, the Interlinear tab is gone. Nothing else is
    deleted, and your documents are not touched: their examples are ordinary
    Word tables and stay as they are; they only stop re-wrapping themselves.
    Word must be closed. If it is open, the script asks you to quit it, and
    waits.

    Word may have kept the add-in's keyboard shortcuts in its Normal template.
    To remove those too, run LingTeXRemoveShortcuts from Tools > Macro >
    Macros in Word before you uninstall.
*)

property templateName : "LingTeX-Word.dotm"
property dialogTitle : "Uninstall LingTeX-Word"

on run
    try
        set installedPath to ""
        repeat with candidate in startupFolders()
            if fileExists((contents of candidate) & "/" & templateName) then set installedPath to (contents of candidate) & "/" & templateName
        end repeat
        if installedPath is "" then
            showDialog("Nothing to remove: " & templateName & " is not in Word's Startup folder.", {"OK"}, "OK", "")
            return
        end if
        waitForWordToQuit()
        do shell script "rm -f " & quoted form of installedPath
        showDialog("LingTeX-Word is removed. From the next start of Word, the Interlinear tab is gone.", {"OK"}, "OK", "")
    on error errorText number errorNumber
        if errorNumber is not -128 then -- -128 is Cancel: nothing to say
            showDialog("LingTeX-Word was not removed." & return & return & errorText, {"OK"}, "OK", "")
        end if
    end try
end run

on startupFolders()
    set base to (POSIX path of (path to home folder)) & "Library/Group Containers/UBF8T346G9.Office/"
    return {base & "User Content.localized/Startup.localized/Word", base & "User Content/Startup/Word"}
end startupFolders

-- Word holds its Startup templates open while it runs.
on waitForWordToQuit()
    repeat while wordIsRunning()
        showDialog("Microsoft Word is open. Quit Word (Word menu > Quit Word), then click Continue.", {"Cancel", "Continue"}, "Continue", "Cancel")
    end repeat
end waitForWordToQuit

on wordIsRunning()
    return (do shell script "pgrep -xq 'Microsoft Word' && echo yes || echo no") is "yes"
end wordIsRunning

on fileExists(posixPath)
    return (do shell script "test -f " & quoted form of posixPath & " && echo yes || echo no") is "yes"
end fileExists

-- Every message goes through here. cancelName, unless it is "", names the
-- button that stops the script.
on showDialog(promptText, buttonNames, defaultName, cancelName)
    if cancelName is "" then
        return button returned of (display dialog promptText buttons buttonNames default button defaultName with title dialogTitle)
    end if
    return button returned of (display dialog promptText buttons buttonNames default button defaultName cancel button cancelName with title dialogTitle)
end showDialog
