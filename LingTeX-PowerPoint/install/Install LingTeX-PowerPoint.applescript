(*
    INSTALL LINGTEX-POWERPOINT
    for Microsoft PowerPoint on the Mac (PowerPoint 2016 or later, Microsoft 365)

    TO INSTALL
    Click the Run button in the toolbar above (the triangle, like Play),
    or press Command-R. Then follow the messages.

    WHAT IT DOES
    LingTeX-PowerPoint is one file, LingTeX-PowerPoint.ppam: a PowerPoint
    add-in that puts an Interlinear tab on the ribbon. This script copies that
    file, which sits beside this script, into your own PowerPoint Startup
    folder:

        ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/PowerPoint

    PowerPoint loads everything in that folder each time it starts, so from
    then on the Interlinear tab is on the ribbon in every presentation. That
    copy is the whole installation.

      - Upgrading: an earlier LingTeX-PowerPoint in that folder is simply
        replaced. Your presentations are not touched.
      - PowerPoint must be closed while the file is copied. If it is open, the
        script asks you to quit it, and waits.
      - A downloaded file carries a quarantine mark, and PowerPoint will not
        load a Startup add-in that has one. The script clears it from the copy.
      - Nothing else on your Mac is changed, and no administrator password is
        needed.

    macOS may ask whether Script Editor may read files on this disk image, or
    use data from other apps (PowerPoint's folder). Click OK or Allow: that is
    the copy.

    AFTER INSTALLING
    Start PowerPoint. If it asks whether to enable macros in
    LingTeX-PowerPoint.ppam, choose Enable Macros. The Interlinear tab is then
    on the ribbon.

    TO REMOVE IT
    Run "Uninstall LingTeX-PowerPoint" from this disk image the same way.

    WHY A SCRIPT
    macOS blocks installer programs that are not registered with Apple. A
    script document opens freely, and every step it takes is written out
    below, where you can read it before you press Run.
*)

property addinName : "LingTeX-PowerPoint.ppam"
property probeName : "LingTeXStartupProbe.ppam"
property dialogTitle : "Install LingTeX-PowerPoint"

on run
    try
        set source to findAddin()
        checkPowerPointIsInstalled()
        waitForPowerPointToQuit()

        set folderPath to startupFolder()
        set destination to folderPath & "/" & addinName
        set upgrading to fileExists(destination)

        do shell script "mkdir -p " & quoted form of folderPath
        installCopy(source, folderPath, destination)

        if upgrading then
            set resultText to "LingTeX-PowerPoint is upgraded."
        else
            set resultText to "LingTeX-PowerPoint is installed."
        end if
        set resultText to resultText & return & return & "Start PowerPoint. If it asks whether to enable macros in " & addinName & ", choose Enable Macros. The Interlinear tab is then on the ribbon in every presentation."
        if fileExists(folderPath & "/" & probeName) then
            set resultText to resultText & return & return & "Note: " & probeName & " is in the same folder. That is a test add-in from development; it can be deleted."
        end if

        set choice to showDialog(resultText, {"Show in Finder", "Done", "Start PowerPoint"}, "Start PowerPoint", "")
        if choice is "Start PowerPoint" then
            do shell script "open -b com.microsoft.Powerpoint"
        else if choice is "Show in Finder" then
            do shell script "open " & quoted form of folderPath
        end if
    on error errorText number errorNumber
        if errorNumber is not -128 then -- -128 is Cancel: nothing to say
            showDialog("LingTeX-PowerPoint was not installed." & return & return & errorText, {"OK"}, "OK", "")
        end if
    end try
end run

-- The add-in that came with this script: beside it, or wherever you point.
on findAddin()
    try
        set scriptPath to POSIX path of (path to me)
        set candidate to (do shell script "dirname " & quoted form of scriptPath) & "/" & addinName
        if fileExists(candidate) then return candidate
    end try
    set chosen to POSIX path of (choose file with prompt "Where is " & addinName & "? It came with this script, on the same disk image.")
    if chosen does not end with ".ppam" then error "That is not " & addinName & ":" & return & chosen
    return chosen
end findAddin

-- The new add-in goes in under a temporary name, and only once it is
-- complete, identical and cleared of quarantine is it moved over the old one,
-- in a single step. A copy that fails therefore leaves the installed version
-- where it was. The temporary name does not end in .ppam, so PowerPoint never
-- tries to load it.
on installCopy(source, folderPath, destination)
    set staging to folderPath & "/LingTeX-PowerPoint.installing"
    try
        do shell script "cp " & quoted form of source & " " & quoted form of staging
        do shell script "xattr -d com.apple.quarantine " & quoted form of staging & " 2>/dev/null; true"
        do shell script "cmp -s " & quoted form of source & " " & quoted form of staging & " || { echo 'The copy is not identical to the original.' >&2; exit 1; }"
        do shell script "mv -f " & quoted form of staging & " " & quoted form of destination
    on error errorText number errorNumber
        try
            do shell script "rm -f " & quoted form of staging
        end try
        error errorText number errorNumber
    end try
end installCopy

-- PowerPoint's Startup folder for the person running this, in the Office group
-- container. The folders carry a hidden .localized ending; an older setup may
-- not, so whichever exists is used, and the usual one is created when neither does.
on startupFolder()
    repeat with candidate in startupFolders()
        if folderExists(contents of candidate) then return contents of candidate
    end repeat
    return item 1 of startupFolders()
end startupFolder

on startupFolders()
    set base to (POSIX path of (path to home folder)) & "Library/Group Containers/UBF8T346G9.Office/"
    return {base & "User Content.localized/Startup.localized/PowerPoint", base & "User Content/Startup/PowerPoint"}
end startupFolders

on checkPowerPointIsInstalled()
    set appPath to do shell script "test -d '/Applications/Microsoft PowerPoint.app' && echo yes || mdfind \"kMDItemCFBundleIdentifier == 'com.microsoft.Powerpoint'\" | head -1"
    if appPath is "" then
        showDialog("Microsoft PowerPoint was not found on this Mac. LingTeX-PowerPoint is an add-in for PowerPoint 2016 or later.", {"Cancel", "Install Anyway"}, "Cancel", "Cancel")
    end if
end checkPowerPointIsInstalled

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

on folderExists(posixPath)
    return (do shell script "test -d " & quoted form of posixPath & " && echo yes || echo no") is "yes"
end folderExists

-- Every message goes through here. cancelName, unless it is "", names the
-- button that stops the script.
on showDialog(promptText, buttonNames, defaultName, cancelName)
    if cancelName is "" then
        return button returned of (display dialog promptText buttons buttonNames default button defaultName with title dialogTitle)
    end if
    return button returned of (display dialog promptText buttons buttonNames default button defaultName cancel button cancelName with title dialogTitle)
end showDialog
