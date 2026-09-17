@{
    RootModule        = 'UpdateEverything.psm1'
    ModuleVersion     = '1.10.0'
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
            ReleaseNotes = '# 1.10.0

## Removing old versions

Installing never removed older versions, so they accumulated in both the
PowerShell and WindowsPowerShell module folders. This is not only untidy.
A scheduled task stores an absolute path to one specific version of the
manifest. The old copy therefore stays live and keeps running. On the
machine this was developed on, a weekly task had been running 1.0.0 for
as long as 1.9.0 had been installed, reporting success every week.

Remove-UpdateEverythingVersion is a separate command, not a side effect
of installing. Install.ps1 calls it only when given -RemoveOldVersions,
and only after the install succeeds. It refuses to guess. It never removes
the running version, the newest version, anything named in -Keep, or a
version a scheduled task points at unless -RepairTask moves the task to
the surviving version first.

Version folders that hold no manifest are treated as orphans and removed
only when genuinely empty. One that contains anything unidentifiable is
reported for a human to look at. Deletions are re-checked afterwards,
because OneDrive can restore a folder that Remove-Item has just reported
as gone.

## Reporting last run issues

A scheduled run finishes in a session nobody was watching, so the result
object it returned is gone. Only the logs survive. Reading them by hand
means knowing which stamp was the last run and which of thirty-odd step
logs belong to it.

Get-UpdateEverythingIssue reports the failures and warnings from the most
recent run and updates nothing. Update-Everything -IssuesFromLastRun does
the same thing by delegating to it. Each run now writes
Update-Everything-<stamp>.summary.json beside its transcript, holding the
status of every step and the exact text of any errors.

It does not re-decide what counted as a failure. Invoke-Step already made
that judgement during the run, discounting the ordinary stderr chatter
that npm, winget and wsl produce. Only lines carrying the timestamp
written by this module are read, because tools print the words FAILED and
ERROR in their own output all the time.

Skipped steps are left out unless -IncludeSkipped is given. A declined
install or a step filtered out by -Tag is a decision, not a fault. Runs
made before this version have no summary file, so reports about them fall
back to the logs and carry a count and a path rather than the error text.
A Source property on each issue says which of the two it came from.
'

        }
    }
}
