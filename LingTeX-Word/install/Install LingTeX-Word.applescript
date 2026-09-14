(*
    INSTALL LINGTEX-WORD
    for Microsoft Word on the Mac (Word 2016 or later, Microsoft 365)

    TO INSTALL
    Click the Run button in the toolbar above (the triangle, like Play),
    or press Command-R. Then follow the messages.

    WHAT IT DOES
    LingTeX-Word is one file, LingTeX-Word.dotm: a Word template that adds an
    Interlinear tab to the ribbon. This script copies that file, which sits
    beside this script, into your own Word Startup folder:

        ~/Library/Group Containers/UBF8T346G9.Office/User Content/Startup/Word

    Word opens everything in that folder each time it starts, so from then on
    the Interlinear tab is on the ribbon of every document. That copy is the
    whole installation.

      - Upgrading: an earlier LingTeX-Word in that folder is simply replaced.
        Your documents are not touched.
      - Word must be closed while the file is copied. If it is open, the
        script asks you to quit it, and waits.
      - A downloaded file carries a quarantine mark, and Word will not load a
        Startup template that has one. The script clears it from the copy.
      - Nothing else on your Mac is changed, and no administrator password is
        needed.

    macOS may ask whether Script Editor may read files on this disk image, or
    use data from other apps (Word's folder). Click OK or Allow: that is the
    copy.

    AFTER INSTALLING
    Start Word. If it asks whether to enable macros in LingTeX-Word.dotm,
    choose Enable Macros. A message then says LingTeX-Word is installed and
    lists its keyboard shortcuts (Command-Option-Shift and a letter).

    TO REMOVE IT
    Run "Uninstall LingTeX-Word" from this disk image the same way.

    WHY A SCRIPT
    macOS blocks installer programs that are not registered with Apple. A
    script document opens freely, and every step it takes is written out
    below, where you can read it before you press Run.
*)

property templateName : "LingTeX-Word.dotm"
property devTemplateName : "LingTeX-Dev.dotm"
property dialogTitle : "Install LingTeX-Word"

on run
    try
        set source to findTemplate()
        checkWordIsInstalled()
        waitForWordToQuit()

        set folderPath to startupFolder()
        set destination to folderPath & "/" & templateName
        set upgrading to fileExists(destination)

        do shell script "mkdir -p " & quoted form of folderPath
        do shell script "cp -f " & quoted form of source & " " & quoted form of destination
        -- Word will not load a quarantined template from its Startup folder.
        do shell script "xattr -d com.apple.quarantine " & quoted form of destination & " 2>/dev/null; true"
        -- cmp fails, and so stops the script with its error, unless the copy is identical.
        do shell script "cmp -s " & quoted form of source & " " & quoted form of destination

        if upgrading then
            set resultText to "LingTeX-Word is upgraded."
        else
            set resultText to "LingTeX-Word is installed."
        end if
        set resultText to resultText & return & return & "Start Word. If it asks whether to enable macros in " & templateName & ", choose Enable Macros. A message then lists the keyboard shortcuts, and the Interlinear tab is on the ribbon of every document."
        if fileExists(folderPath & "/" & devTemplateName) then
            set resultText to resultText & return & return & "Note: " & devTemplateName & " is in the same folder. That is the development version, which loads its own copy of the code, so every command would exist twice. Move it out of the Startup folder while you use this one."
        end if

        set choice to showDialog(resultText, {"Show in Finder", "Done", "Start Word"}, "Start Word", "")
        if choice is "Start Word" then
            do shell script "open -b com.microsoft.Word"
        else if choice is "Show in Finder" then
            do shell script "open " & quoted form of folderPath
        end if
    on error errorText number errorNumber
        if errorNumber is not -128 then -- -128 is Cancel: nothing to say
            showDialog("LingTeX-Word was not installed." & return & return & errorText, {"OK"}, "OK", "")
        end if
    end try
end run

-- The template that came with this script: beside it, or wherever you point.
on findTemplate()
    try
        set scriptPath to POSIX path of (path to me)
        set candidate to (do shell script "dirname " & quoted form of scriptPath) & "/" & templateName
        if fileExists(candidate) then return candidate
    end try
    set chosen to POSIX path of (choose file with prompt "Where is " & templateName & "? It came with this script, on the same disk image.")
    if chosen does not end with ".dotm" then error "That is not " & templateName & ":" & return & chosen
    return chosen
end findTemplate

-- Word's Startup folder for the person running this. Word 2016 and later keep
-- it in the Office group container. Word names the folders with a hidden
-- .localized ending; an older setup may not, so whichever exists is used, and
-- the usual one is created when neither does.
on startupFolder()
    repeat with candidate in startupFolders()
        if folderExists(contents of candidate) then return contents of candidate
    end repeat
    return item 1 of startupFolders()
end startupFolder

on startupFolders()
    set base to (POSIX path of (path to home folder)) & "Library/Group Containers/UBF8T346G9.Office/"
    return {base & "User Content.localized/Startup.localized/Word", base & "User Content/Startup/Word"}
end startupFolders

on checkWordIsInstalled()
    set wordPath to do shell script "test -d '/Applications/Microsoft Word.app' && echo yes || mdfind \"kMDItemCFBundleIdentifier == 'com.microsoft.Word'\" | head -1"
    if wordPath is "" then
        showDialog("Microsoft Word was not found on this Mac. LingTeX-Word is an add-in for Word 2016 or later.", {"Cancel", "Install Anyway"}, "Cancel", "Cancel")
    end if
end checkWordIsInstalled

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
