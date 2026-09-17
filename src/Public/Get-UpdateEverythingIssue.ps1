function Get-UpdateEverythingIssue {
    <#
        .SYNOPSIS
        Reports failures and warnings from recent Update-Everything runs.

        .DESCRIPTION
        Reads the structured summary JSON files or falls back to the log files
        to identify steps that ended in Failed, Warning, or Interrupted states.
        It does not re-evaluate the success of steps; it trusts the verdict
        recorded by Invoke-Step at run time.

        By default, skipped steps are excluded because they represent deliberate
        decisions (e.g., consent declined, tag exclusion) rather than failures.
        Use -IncludeSkipped to audit these decisions.

        If no runs are found, returns nothing and logs a verbose message indicating
        which directory was searched.

        .PARAMETER LogDirectory
        The directory containing the run logs and summaries. If not specified,
        the default location is resolved using Get-UpdateLogDirectory.

        .PARAMETER IncludeSkipped
        Include steps that were marked as Skipped in the output.

        .PARAMETER Last
        The number of most recent runs to examine. Defaults to 1.

        .EXAMPLE
        Get-UpdateEverythingIssue

        .EXAMPLE
        Get-UpdateEverythingIssue -IncludeSkipped -Last 3
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $LogDirectory,
        [switch] $IncludeSkipped,
        [int] $Last = 1
    )

    if (-not $LogDirectory) {
        # Resolve the standard log directory if not provided.
        $LogDirectory = Get-UpdateLogDirectory
    }

    # Find the most recent run stamps by looking for transcript files.
    # We use the transcript name because it is the definitive marker of a run's existence,
    # even if the summary is missing or corrupted.
    $transcripts = Get-ChildItem -LiteralPath $LogDirectory -Filter 'Update-Everything-*.log' -File -ErrorAction SilentlyContinue
    if (-not $transcripts -or -not $transcripts.Count) {
        Write-Verbose "No previous Update-Everything runs found in ${LogDirectory}"
        return
    }

    # Sort by name descending. The name contains the timestamp (yyyyMMdd-HHmmss),
    # which is more reliable for chronological ordering than LastWriteTime,
    # especially when transcripts are appended to by elevated child processes.
    $recentTranscripts = $transcripts | Sort-Object Name -Descending | Select-Object -First $Last

    foreach ($transcript in $recentTranscripts) {
        # Extract the run stamp from the filename: Update-Everything-<stamp>.log
        $fileName = $transcript.Name
        # The pattern assumes the format Update-Everything-<stamp>.log
        $stampMatch = [regex]::Match($fileName, 'Update-Everything-(?<stamp>[\d\-]+)\.log')
        if (-not $stampMatch.Success) {
            continue
        }
        $runStamp = $stampMatch.Groups['stamp'].Value

        # 1. Try to load the structured summary
        $summaryPath = Join-Path $LogDirectory "Update-Everything-$runStamp.summary.json"
        $issues = $null
        $source = 'Log' # Default fallback

        if (Test-Path -LiteralPath $summaryPath) {
            try {
                $summaryText = Get-Content -LiteralPath $summaryPath -Raw -ErrorAction Stop
                $summary = $summaryText | ConvertFrom-Json
                $source = 'Summary'

                # Build issues from summary
                $issues = [System.Collections.Generic.List[pscustomobject]]::new()
                foreach ($step in $summary.Steps) {
                    $status = $step.Status

                    # Determine if we should include this step
                    $shouldInclude = $false
                    if ($status -eq 'Failed' -or $status -eq 'Warning') {
                        $shouldInclude = $true
                    } elseif ($status -eq 'Skipped' -and $IncludeSkipped) {
                        $shouldInclude = $true
                    }

                    if (-not $shouldInclude) {
                        continue
                    }

                    $detailArray = @()
                    if ($step.Detail) {
                        if ($step.Detail -is [array]) {
                            $detailArray = $step.Detail
                        } else {
                            $detailArray = @($step.Detail)
                        }
                    }

                    $issues.Add([pscustomobject]@{
                        PSTypeName = 'UpdateEverything.Issue'
                        RunStamp   = $runStamp
                        Step       = $step.Step
                        Status     = $status
                        Detail     = $detailArray
                        Log        = $step.Log
                        Source     = $source
                    })
                }
            } catch {
                # If summary parsing fails, fall back to logs.
                Write-Verbose "Failed to parse summary ${summaryPath}: $($_.Exception.Message). Falling back to log parsing."
                $issues = $null
                $source = 'Log'
            }
        }

        # 2. If no summary was used (or it failed), parse the logs
        if (-not $issues) {
            $issues = [System.Collections.Generic.List[pscustomobject]]::new()
            $source = 'Log'

            # Find step logs for this run. They end with -<stamp>.log
            $stepLogs = Get-ChildItem -LiteralPath $LogDirectory -Filter "*-$runStamp.log" -File -ErrorAction SilentlyContinue

            # Exclude the main transcript from step logs if it matches the pattern (unlikely but safe)
            $stepLogs = $stepLogs | Where-Object { $_.Name -ne $transcript.Name }

            foreach ($stepLogFile in $stepLogs) {
                $stepName = $stepLogFile.Name
                # Strip the stamp and extension to get the sanitised step name
                # Format: <sanitised name>-<stamp>.log
                $stepName = $stepName -replace ("-$runStamp\.log$"), ''

                # Read the log content
                $logContent = Get-Content -LiteralPath $stepLogFile.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $logContent) {
                    continue
                }

                # We need to identify the final status of the step.
                # Status lines start with a timestamp: "2026-09-16 20:41:01 | STATUS | ..."
                # We must anchor on the timestamp to avoid matching raw tool output
                # that might contain words like "FAILED" or "ERROR".

                $foundStatus = $null
                $foundDetail = $null

                # The sanitising of step names for filenames is lossy (spaces, parens become hyphens),
                # so we read the exact name back from the STARTING line if present.
                $realStepName = $null
                $skipName = $null

                # Let's scan the log lines.
                # Split on the regex, not on a bare newline. Write-StepLog ends
                # every line with [Environment]::NewLine, which is CRLF here, so
                # splitting on "`n" alone leaves a carriage return on the end of
                # each line. It then travels into the step name, where it is
                # invisible on a console and breaks any comparison against it.
                $lines = $logContent -split "`r?`n"
                foreach ($line in $lines) {
                    if ($line -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \|') {
                        continue
                    }

                    # Extract the content after the timestamp and pipe
                    $content = $line -replace '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| ', ''

                    # Check for specific statuses.
                    if ($content -like 'COMPLETED WITH ERRORS*') {
                        # This is a Warning
                        # The error text is not in the status line, only the count.
                        # We report the count and direct the user to the log for details.
                        $status = 'Warning'
                        $countMatch = [regex]::Match($content, '(\d+) error record\(s\)')
                        $countText = if ($countMatch.Success) { "$($countMatch.Groups[1].Value) error record(s)" } else { 'Error records' }
                        $detail = "$countText. The messages are in the step log; runs from this version onward record them in the run summary."
                        $foundStatus = $status
                        $foundDetail = $detail
                    }
                    elseif ($content -like 'FAILED*') {
                        $status = 'Failed'
                        $detail = $content -replace '^FAILED \| ', ''
                        $foundStatus = $status
                        $foundDetail = $detail
                    }
                    elseif ($content -like 'SKIPPED*') {
                        $status = 'Skipped'
                        $detail = $content -replace '^SKIPPED \| ', ''
                        $foundStatus = $status
                        $foundDetail = $detail
                    }
                    elseif ($content -like 'SKIP*') {
                        # Early skip: "SKIP  Name (reason)"
                        $status = 'Skipped'

                        # Parse the name and reason from "SKIP  Name (reason)"
                        # Match the LAST ' (' to handle names with parentheses.
                        $skipMatch = [regex]::Match($content, '^SKIP\s+(?<name>.*)\s\((?<reason>[^)]+)\)$')
                        if ($skipMatch.Success) {
                            $skipName = $skipMatch.Groups['name'].Value.Trim()
                            $detail = $skipMatch.Groups['reason'].Value
                        } else {
                            # Fallback if the format is unexpected
                            $detail = $content -replace '^SKIP\s+', ''
                        }

                        $foundStatus = $status
                        $foundDetail = $detail
                    }
                    elseif ($content -like 'STARTING*') {
                        # Capture the real step name from the STARTING line
                        $realStepName = $content -replace '^STARTING\s+', ''
                    }
                }

                # Use the real step name if found, otherwise fall back to the file name stem
                # Name resolution order:
                # 1. STARTING line (most reliable, present for steps that started)
                # 2. SKIP line (present for steps skipped before starting)
                # 3. File name stem (lossy last resort)
                if ($realStepName) {
                    $stepName = $realStepName
                } elseif ($skipName) {
                    $stepName = $skipName
                }
                # Otherwise $stepName remains the sanitized file name stem

                # Check for Interrupted:
                # If the log has "STARTING" but no verdict (Failed, Warning, Skipped), it is interrupted.
                # We can detect this by checking if any "STARTING" line exists and $foundStatus is $null.
                # But we also need to ensure it wasn't just a successful completion.
                # If it was successful, there would be a "COMPLETED" line.
                # We should check for "COMPLETED" as well to exclude it.

                $hasStarting = $false
                $hasCompleted = $false
                foreach ($line in $lines) {
                    if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| STARTING') {
                        $hasStarting = $true
                    }
                    if ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| COMPLETED') {
                        $hasCompleted = $true
                    }
                }

                if (-not $foundStatus) {
                    if ($hasStarting -and -not $hasCompleted) {
                        $foundStatus = 'Interrupted'
                        $foundDetail = 'Run ended before the step finished'
                    }
                }

                if ($foundStatus) {
                    # Filter by IncludeSkipped
                    if ($foundStatus -eq 'Skipped' -and -not $IncludeSkipped) {
                        continue
                    }

                    $issues.Add([pscustomobject]@{
                        PSTypeName = 'UpdateEverything.Issue'
                        RunStamp   = $runStamp
                        Step       = $stepName
                        Status     = $foundStatus
                        Detail     = @($foundDetail)
                        Log        = $stepLogFile.FullName
                        Source     = $source
                    })
                }
            }
        }

        # Output the issues for this run
        foreach ($issue in $issues) {
            $issue
        }
    }
}
