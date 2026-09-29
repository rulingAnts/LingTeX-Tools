(*
    UNINSTALL LINGTEX-POWERPOINT
    for Microsoft PowerPoint on the Mac

    TO REMOVE LINGTEX-POWERPOINT
    Click the Run button in the toolbar above (the triangle, like Play), or
    press Command-R.

    WHAT IT DOES
    Deletes LingTeX-PowerPoint.ppam from your PowerPoint Startup folder:

        ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/PowerPoint

    From the next start of PowerPoint, the Interlinear tab is gone. Nothing
    else is deleted, and your presentations are not touched: their examples
    are ordinary text boxes and stay as they are; they only stop re-wrapping
    themselves. PowerPoint must be closed. If it is open, the script asks you
    to quit it, and waits.
*)

property addinName : "LingTeX-PowerPoint.ppam"
property dialogTitle : "Uninstall LingTeX-PowerPoint"

on run
    try
        set installedPath to ""
        repeat with candidate in startupFolders()
            if fileExists((contents of candidate) & "/" & addinName) then set installedPath to (contents of candidate) & "/" & addinName
        end repeat
        if installedPath is "" then
            showDialog("Nothing to remove: " & addinName & " is not in PowerPoint's Startup folder.", {"OK"}, "OK", "")
            return
        end if
        waitForPowerPointToQuit()
        do shell script "rm -f " & quoted form of installedPath
        showDialog("LingTeX-PowerPoint is removed. From the next start of PowerPoint, the Interlinear tab is gone.", {"OK"}, "OK", "")
    on error errorText number errorNumber
        if errorNumber is not -128 then -- -128 is Cancel: nothing to say
            showDialog("LingTeX-PowerPoint was not removed." & return & return & errorText, {"OK"}, "OK", "")
        end if
    end try
end run

on startupFolders()
    set base to (POSIX path of (path to home folder)) & "Library/Group Containers/UBF8T346G9.Office/"
    return {base & "User Content.localized/Startup.localized/PowerPoint", base & "User Content/Startup/PowerPoint"}
end startupFolders

-- PowerPoint holds its Startup add-ins open while it runs.
on waitForPowerPointToQuit()
    repeat while powerPointIsRunning()
        showDialog("Microsoft PowerPoint is open. Quit PowerPoint (PowerPoint menu > Quit PowerPoint), then click Continue.", {"Cancel", "Continue"}, "Continue", "Cancel")
    end repeat
end waitForPowerPointToQuit

on powerPointIsRunning()
    return (do shell script "pgrep -xq 'Microsoft PowerPoint' && echo yes || echo no") is "yes"
end powerPointIsRunning

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
