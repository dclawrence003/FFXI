Option Explicit

Dim shell, fileSystem, scriptDirectory, launcher, powerShell, command, exitCode

Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
launcher = fileSystem.BuildPath(scriptDirectory, "Start-InventoryCore.ps1")
powerShell = shell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"

command = Quote(powerShell) & _
    " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass" & _
    " -File " & Quote(launcher) & _
    " -NoBrowser -Foreground -SkipRefresh"

' WScript is a GUI-subsystem host, so neither it nor its hidden PowerShell
' child allocates a console window. Waiting preserves Task Scheduler's process
' supervision and exit status when InventoryCore itself owns the server.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
