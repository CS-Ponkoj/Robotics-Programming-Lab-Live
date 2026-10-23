' Starts run-live.ps1 with no visible window for the RPL-Live scheduled task.
' Window style 0 never shows a console, unlike powershell -WindowStyle Hidden.
Dim shell, logFile, command
Set shell = CreateObject("WScript.Shell")
logFile = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\RoboticsProgrammingLab\runtime\RPL-Live\logs\startup.log"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command " & _
    """& 'C:\RPL-Live\scripts\run-live.ps1' -SkipBuild *>> '" & logFile & "'"""
shell.Run command, 0, True
