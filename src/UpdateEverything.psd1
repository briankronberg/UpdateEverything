@{
    RootModule        = 'UpdateEverything.psm1'
    ModuleVersion     = '1.10.2'
    GUID              = 'e4e1f3eb-5967-4311-94af-c650fe192e95'
    Author            = 'Brian Kronberg'
    Copyright         = '(c) 2026 Brian Kronberg. Released under the MIT License.'
    Description       = 'Updates a Windows machine through every package manager and update channel it can find, running each as an isolated step so one failure does not stop the rest. Covers winget, the Microsoft Store, Windows Update, Microsoft 365 Apps, Defender, PowerShell modules, npm, pipx, uv, Chocolatey, Scoop, rustup, .NET tools and more. Can register itself as a scheduled task with toast notifications.'

    # 5.1 is the floor because the script has always supported Windows PowerShell,
    # and a maintenance tool that cannot run on a machine before it has been
    # updated is not much use.
    PowerShellVersion = '5.1'

    # Declared so the gallery can filter on it, and so a Core-only or
    # Desktop-only consumer is told before installing rather than after.
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Update-Everything'
        'Initialize-UpdateEverything'
        'Register-UpdateEverythingTask'
        'Unregister-UpdateEverythingTask'
        'Get-UpdateEverythingTask'
        'Test-PendingReboot'
        'Convert-PowerShell7ToMsi'
        'Remove-UpdateEverythingVersion'
        'Get-UpdateEverythingIssue'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Update-All')

    PrivateData = @{
        PSData = @{
            Tags         = @('Windows', 'Update', 'Maintenance', 'winget', 'WindowsUpdate', 'Chocolatey', 'Scoop', 'ScheduledTask', 'PSEdition_Desktop', 'PSEdition_Core')
            LicenseUri   = 'https://github.com/briankronberg/UpdateEverything/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/briankronberg/UpdateEverything'
            ReleaseNotes = '# 1.10.2

## Naming locked files

A step that fails because a file is locked now names the file and the
processes holding it. On the development machine, every scheduled run
reported that uv self update failed with exit code 2. The step log held the
reason: the process cannot access the file because it is being used by
another process. Six processes held it, all uvx or uv, all launched by the
desktop application that runs MCP servers through uvx. Because uv replaces
both executables together, anything started through uvx blocks the update
for as long as it runs.

The message now reads: Could not replace C:\Users\you\.local\bin\uvx.exe:
a process is using it. Likely holders: uvx.exe (pid 11708, parent
claude.exe), uvx.exe (pid 43336, parent claude.exe). Close them and run the
update again.

It remains an error. A lock is a real failure to update, not a benign cause
to excuse. Naming the reason does not downgrade the result.

## Where it stops

It finds a process whose own image is the locked file, which is the usual
case when replacing an executable. A process holding the file open some
other way is not found, so the wording says likely and never claims to be
the whole list. It matches the actual Windows sentence rather than guessing
from an exit code, so a failure for any other reason is reported exactly as
before. Looking for the holder never becomes the failure; if the process
table cannot be read, the lock is still reported without names. Only the uv
step uses it so far. Other steps still report a lock the way they always
did.
'

        }
    }
}
