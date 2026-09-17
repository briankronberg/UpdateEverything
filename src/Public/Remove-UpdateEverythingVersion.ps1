function Remove-UpdateEverythingVersion {
    <#
    .SYNOPSIS
    Removes installed versions of the UpdateEverything module.

    .DESCRIPTION
    Scans the standard CurrentUser and AllUsers module roots for UpdateEverything
    version folders, protecting the running version, the newest version, any
    version listed in -Keep, and any version pinned by a scheduled task unless
    -RepairTask is supplied. Deleted paths are verified to be gone, because
    OneDrive sync on these machines can restore a folder after Remove-Item
    returns successfully. Also removes orphaned version-shaped folders that
    contain no manifest, as these are harmless litter from previous installs.
    .PARAMETER Version
    Specific version strings to remove, such as 1.0.0. When omitted, every
    installed version except the newest is a candidate for removal.
    .PARAMETER Keep
    Version strings to protect from removal, on top of the automatic
    protections for the running, newest, and task-pinned versions.
    .PARAMETER RepairTask
    When a scheduled task references a version being removed, re-point the task
    at the surviving newest version instead of refusing the removal.
    .PARAMETER Force
    Proceed without the interactive confirmation prompt.
    .EXAMPLE
    Remove-UpdateEverythingVersion
    Removes every installed version except the newest, the running version, and
    any version referenced by a scheduled task.
    .EXAMPLE
    Remove-UpdateEverythingVersion -Version 1.0.0, 1.1.0 -RepairTask
    Removes 1.0.0 and 1.1.0, re-pointing any scheduled task that references
    them at the newest surviving version.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Write-Host is the user interface of a console maintenance tool. Its output is progress a person watches, not data a caller consumes.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Version,
        [string[]] $Keep = @(),
        [switch] $RepairTask,
        [switch] $Force
    )

    # $ConfirmPreference is function-scoped and is NOT $ErrorActionPreference,
    # so the house rule forbidding assignments to the error preference does not apply.
    if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
        $ConfirmPreference = 'None'
    }

    $runningBase = $null
    if ($MyInvocation.MyCommand.Module -and $MyInvocation.MyCommand.Module.ModuleBase) {
        $runningBase = $MyInvocation.MyCommand.Module.ModuleBase
    } elseif ($script:ModuleRoot) {
        $runningBase = $script:ModuleRoot
    } elseif ($PSScriptRoot) {
        $runningBase = Split-Path -Parent $PSScriptRoot
    }

    $allVersions = [System.Collections.Generic.List[object]]::new()
    $orphans = [System.Collections.Generic.List[string]]::new()

    $editionNames = @('PowerShell', 'WindowsPowerShell')
    $currentDoc = [Environment]::GetFolderPath('MyDocuments')
    $roots = @()
    if ($currentDoc) { $roots += $currentDoc }
    if ($env:ProgramFiles) { $roots += $env:ProgramFiles }

    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        foreach ($edition in $editionNames) {
            $moduleBase = Join-Path $root ("{0}\Modules\UpdateEverything" -f $edition)
            if (-not (Test-Path -LiteralPath $moduleBase)) { continue }
            $subdirs = Get-ChildItem -LiteralPath $moduleBase -Directory -ErrorAction SilentlyContinue
            if (-not $subdirs) { continue }
            foreach ($dir in $subdirs) {
                $manifest = Join-Path $dir.FullName 'UpdateEverything.psd1'
                if (Test-Path -LiteralPath $manifest) {
                    $verStr = $dir.Name
                    $verObj = $null
                    if ([System.Version]::TryParse($verStr, [ref]$verObj)) {
                        $allVersions.Add([pscustomobject]@{ Path = $dir.FullName; Version = $verObj; VersionString = $verStr })
                    }
                } else {
                    # Orphaned folders are recorded separately. They must NOT be
                    # added to $allVersions because an empty folder named 9.9.9
                    # must not influence which version is considered "newest" and
                    # thus protected from removal.
                    $verStr = $dir.Name
                    $verObj = $null
                    if ([System.Version]::TryParse($verStr, [ref]$verObj)) {
                        $orphans.Add($dir.FullName)
                    }
                }
            }
        }
    }

    if (-not $allVersions.Count -and -not $orphans.Count) {
        Write-Host "No installed versions or orphaned folders of UpdateEverything found." -ForegroundColor Yellow
        return [pscustomobject]@{
            PSTypeName   = 'UpdateEverything.VersionRemoval'
            Removed      = @()
            Kept         = @()
            Refused      = @()
            TaskRepaired = @()
            Orphaned     = @()
        }
    }

    $sorted = $null
    $newestVerStr = $null
    if ($allVersions.Count -gt 0) {
        $sorted = $allVersions | Sort-Object { $_.Version } -Descending
        $newestVerStr = $sorted[0].VersionString
    }

    $keepSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Keep) { if ($k) { [void]$keepSet.Add($k.Trim()) } }

    $runningLeaf = $null
    if ($runningBase) {
        $runningLeaf = Split-Path -Leaf $runningBase
    }

    $taskPinnedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $tasksToRepair = [System.Collections.Generic.List[object]]::new()

    # Matches the full manifest path inside single quotes to avoid false positives
    # on bare version numbers elsewhere in the command line.
    $pattern = "'([^\']+UpdateEverything\\[\w.-]+\\UpdateEverything\.psd1)'"
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        if ($tasks) {
            foreach ($task in $tasks) {
                $actions = $task.Actions
                if (-not $actions) { continue }
                foreach ($action in $actions) {
                    $argsStr = $action.Arguments
                    if (-not $argsStr) { continue }
                    $match = [regex]::Match($argsStr, $pattern)
                    if ($match.Success) {
                        $pinnedManifest = $match.Groups[1].Value
                        $pinnedFolder = Split-Path -Parent $pinnedManifest
                        # Compare full paths case-insensitively to find the exact installed folder
                        $matchedEntry = $sorted | Where-Object { $_.Path -ieq $pinnedFolder } | Select-Object -First 1
                        if ($matchedEntry) {
                            # HashSet.Add returns a bool. Unassigned, it would
                            # join this function's output alongside the result.
                            [void] $taskPinnedPaths.Add($matchedEntry.Path)
                            $tasksToRepair.Add([pscustomobject]@{
                                Task = $task
                                PinnedPath = $matchedEntry.Path
                            })
                        }
                    }
                }
            }
        }
    } catch {
        Write-Verbose "Could not enumerate scheduled tasks: $($_.Exception.Message)"
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $refusedRunning = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($v in $allVersions) {
        $vPath = $v.Path
        $vVerStr = $v.VersionString

        if ($runningLeaf -and $vVerStr -eq $runningLeaf) {
            # If the caller explicitly asked to remove the running version, record it as refused
            if ($Version -and ($Version -contains $vVerStr)) {
                $reason = "This is the version the module is currently running from."
                $refusedRunning.Add([pscustomobject]@{ Path = $vPath; Reason = $reason })
            }
            continue
        }

        # Protect every folder carrying the newest version string, not just one path.
        if ($vVerStr -eq $newestVerStr -and -not ($Version -contains $vVerStr)) {
            continue
        }

        if ($Version -and -not ($Version -contains $vVerStr)) {
            continue
        }

        if ($keepSet.Contains($vVerStr)) {
            continue
        }

        $candidates.Add($v)
    }

    $removed = [System.Collections.Generic.List[string]]::new()
    $kept = [System.Collections.Generic.List[string]]::new()
    $refused = [System.Collections.Generic.List[pscustomobject]]::new()
    $taskRepaired = [System.Collections.Generic.List[string]]::new()
    $orphanedRemoved = [System.Collections.Generic.List[string]]::new()

    foreach ($r in $refusedRunning) {
        $refused.Add($r)
        Write-Host "Refused to remove $($r.Path) (running version)." -ForegroundColor Yellow
    }

    if ($RepairTask) {
        foreach ($taskInfo in $tasksToRepair) {
            $taskPinnedPath = $taskInfo.PinnedPath
            $isRemovingPinned = $candidates | Where-Object { $_.Path -ieq $taskPinnedPath } | Select-Object -First 1
            if (-not $isRemovingPinned) { continue }

            $task = $taskInfo.Task
            $taskName = $task.TaskName
            $taskPath = $task.TaskPath

            $repointed = $false
            foreach ($action in $task.Actions) {
                $argsStr = $action.Arguments
                if (-not $argsStr) { continue }
                $match = [regex]::Match($argsStr, $pattern)
                if (-not $match.Success) { continue }
                $oldPinnedManifest = $match.Groups[1].Value
                # Find the newest installed manifest path to replace with
                $newestManifest = Join-Path $sorted[0].Path 'UpdateEverything.psd1'
                if ($oldPinnedManifest -eq $newestManifest) { continue }

                # Replace the exact pinned manifest path with the newest one
                $newArgs = $argsStr -replace ([regex]::Escape($oldPinnedManifest)), $newestManifest
                if ($newArgs -ne $argsStr) {
                    $action.Arguments = $newArgs
                    $repointed = $true
                }
            }

            if ($repointed) {
                if ($PSCmdlet.ShouldProcess($taskName, 'Repair scheduled task to point at newest version')) {
                    try {
                        # -Action carries the modified arguments. Without it the
                        # mutated in-memory object is discarded and the task is
                        # left pointing at the old version while this reports
                        # success. Set-ScheduledTask also returns the task, which
                        # would otherwise leak into this function's output.
                        $null = Set-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $task.Actions -ErrorAction Stop
                        $taskRepaired.Add("$taskPath\$taskName")
                        # Freed: the removal loop below refuses anything still in
                        # this set, so a repaired version must leave it.
                        [void] $taskPinnedPaths.Remove($taskPinnedPath)
                        Write-Host "Re-pointed scheduled task '$taskName' at version $newestVerStr." -ForegroundColor Yellow
                    } catch {
                        $refused.Add([pscustomobject]@{ Path = $taskPinnedPath; Reason = "Could not repair task '$taskName': $($_.Exception.Message)" })
                        Write-Host "Failed to repair scheduled task '$taskName': $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }
        }
    }

    foreach ($c in $candidates) {
        $path = $c.Path
        $verStr = $c.VersionString

        if ($taskPinnedPaths.Contains($path)) {
            $refused.Add([pscustomobject]@{ Path = $path; Reason = "Pinned by a scheduled task; use -RepairTask to re-point it." })
            Write-Host "Refused to remove $verStr (task-pinned)." -ForegroundColor Yellow
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($path, "Remove UpdateEverything $verStr")) {
            # Do not add to $kept here. The final reconciliation loop below is
            # the only writer of $kept, so entries cannot double up.
            continue
        }

        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        } catch {
            $refused.Add([pscustomobject]@{ Path = $path; Reason = $_.Exception.Message })
            Write-Host "Failed to remove ${verStr}: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        if (Test-Path -LiteralPath $path) {
            $refused.Add([pscustomobject]@{ Path = $path; Reason = "Path reappeared after deletion; likely OneDrive sync restore." })
            Write-Host "Version $verStr reappeared after removal (OneDrive sync?)." -ForegroundColor Red
        } else {
            $removed.Add($path)
            Write-Host "Removed UpdateEverything $verStr." -ForegroundColor Green
        }
    }

    foreach ($orphanPath in $orphans) {
        # Confirm it really is empty before deleting. If anything is inside,
        # do not delete it; a folder with unknown contents needs a human.
        $contents = Get-ChildItem -LiteralPath $orphanPath -Recurse -ErrorAction SilentlyContinue
        if ($contents) {
            $refused.Add([pscustomobject]@{ Path = $orphanPath; Reason = "No manifest but folder is not empty; requires manual inspection." })
            Write-Host "Refused to remove orphaned folder (not empty): $orphanPath" -ForegroundColor Yellow
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($orphanPath, "Remove orphaned UpdateEverything folder")) {
            continue
        }

        try {
            Remove-Item -LiteralPath $orphanPath -Recurse -Force -ErrorAction Stop
        } catch {
            $refused.Add([pscustomobject]@{ Path = $orphanPath; Reason = $_.Exception.Message })
            Write-Host "Failed to remove orphaned folder: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }

        if (Test-Path -LiteralPath $orphanPath) {
            $refused.Add([pscustomobject]@{ Path = $orphanPath; Reason = "Path reappeared after deletion; likely OneDrive sync restore." })
            Write-Host "Orphaned folder reappeared after removal (OneDrive sync?)." -ForegroundColor Red
        } else {
            $orphanedRemoved.Add($orphanPath)
            Write-Host "Removed orphaned UpdateEverything folder." -ForegroundColor Green
        }
    }

    # Reconcile Kept for real versions only. Orphans are not versions and do
    # not participate in this list.
    if ($allVersions.Count -gt 0) {
        foreach ($v in $allVersions) {
            $path = $v.Path
            $isRemoved = $removed.Contains($path)
            $isRefused = $false
            foreach ($r in $refused) {
                if ($r.Path -ieq $path) {
                    $isRefused = $true
                    break
                }
            }
            if ($isRemoved -or $isRefused) { continue }
            $kept.Add($path)
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'UpdateEverything.VersionRemoval'
        Removed      = $removed.ToArray()
        Kept         = $kept.ToArray()
        Refused      = $refused.ToArray()
        TaskRepaired = $taskRepaired.ToArray()
        Orphaned     = $orphanedRemoved.ToArray()
    }
}
