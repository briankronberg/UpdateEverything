function Save-UpdateRunSummary {
    <#
        .SYNOPSIS
        Writes a machine-readable JSON summary of a completed run.

        .DESCRIPTION
        Creates a .summary.json file in the log directory containing the run stamp,
        completion time, elevation status, reboot requirements, and per-step results
        including status, duration, log path, and detailed error messages.

        The JSON format is versioned with a Schema property to allow future readers
        to distinguish between different formats. This structured record complements
        the human-readable transcript by providing reliable access to error details
        without parsing PowerShell's edition-specific error rendering.

        .PARAMETER LogDirectory
        The directory where the summary file will be written.

        .PARAMETER RunStamp
        The unique identifier for this run, typically a timestamp.

        .PARAMETER Steps
        Array of step result objects from the run.

        .PARAMETER Elevated
        Whether the run executed with elevated privileges.

        .PARAMETER RebootPending
        Whether a system reboot is required after this run.

        .PARAMETER RebootReason
        Reasons why a reboot is pending, if any.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $LogDirectory,
        [Parameter(Mandatory)][string] $RunStamp,
        [object[]] $Steps = @(),
        [bool] $Elevated,
        [bool] $RebootPending,
        [string[]] $RebootReason = @()
    )

    $summaryPath = Join-Path $LogDirectory "Update-Everything-$RunStamp.summary.json"

    if (-not $PSCmdlet.ShouldProcess($summaryPath, 'Save run summary')) {
        return
    }

    $stepEntries = @()
    foreach ($step in $Steps) {
        $stepEntries += [pscustomobject]@{
            Step    = $step.Step
            Status  = $step.Status
            Seconds = $step.Seconds
            Log     = $step.Log
            Detail  = $step.Detail
        }
    }

    $summary = [pscustomobject]@{
        Schema        = 1
        RunStamp      = $RunStamp
        Finished      = (Get-Date).ToString('o')
        Elevated      = $Elevated
        RebootPending = $RebootPending
        RebootReason  = $RebootReason
        Steps         = $stepEntries
    }

    # Depth 5 is required because Detail is an array nested within each step object.
    # The default depth of 2 would render nested arrays as type names instead of their contents.
    $json = $summary | ConvertTo-Json -Depth 5

    try {
        # WriteAllText with explicit UTF8Encoding($false) avoids BOM and encoding inconsistencies
        # across PowerShell editions, matching the approach used in Write-StepLog.
        [System.IO.File]::WriteAllText(
            $summaryPath,
            $json,
            [System.Text.UTF8Encoding]::new($false))

        $summaryPath
    } catch {
        # A run whose summary could not be written is still a successful run;
        # the work was completed, only the record of it failed to persist.
        Write-Warning "Could not save run summary to '$summaryPath': $($_.Exception.Message)"
    }
}
