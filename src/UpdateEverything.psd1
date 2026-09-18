@{
    RootModule        = 'UpdateEverything.psm1'
    ModuleVersion     = '1.10.1'
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
            ReleaseNotes = '# 1.10.1

## Installing tagged releases

Install.ps1 built one download URL, archive/refs/heads/<ref>.zip, which
serves branches. GitHub serves tags from archive/refs/tags/. Measured
against the live repository, heads/main returned 200, heads/v1.10.0
returned 404, and tags/v1.10.0 returned 200. The -Ref parameter promised a
branch or tag since it was written, but only ever delivered a branch. Every
tagged release was uninstallable.

It now tries the branch path first and the tag path second. Asking GitHub
is better than guessing from the shape of the name, because a repository
can legitimately have a branch named like a version. The summary now
reports which kind was found, for example "main, branch" or "v1.10.0, tag".

## Dry run fixes

Two further bugs were found while proving the first fix. Both involved
-WhatIf reaching work that is not what the caller is deciding about. The
temporary download folder was created with New-Item, which honours -WhatIf.
Under -WhatIf the folder never existed, the download failed on a missing
path, and the fallback reported that as neither a branch nor a tag being
found. The folder is scaffolding rather than the operation, so it is now
created regardless.

With that cleared, -WhatIf reached Import-Module and failed with "no valid
module file was found" because nothing had been copied. Install.ps1 -WhatIf
had therefore never finished without an error. It now reports where it
would install and stops.

## Failure message

The failure message was also rewritten. It hard-coded the string "Failed to
download as tag" instead of the real exception, and captured the branch
error inside the inner catch, so it reported the tag failure under the
branch label and invented the other half. It now carries both real errors,
names both addresses tried, and mentions a private repository last rather
than first, where it had been sending readers to check the two things that
were not wrong.

## Where it stops

The fix ships in 1.10.1, so the copy of Install.ps1 inside the v1.10.0 tag
still cannot fetch tags. Installing v1.10.0 by tag works only with an
installer from 1.10.1 or later.
'

        }
    }
}
