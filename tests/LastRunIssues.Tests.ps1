#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0' }

BeforeAll {
    $script:ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
    Get-ChildItem "$script:ModuleRoot\Private\*.ps1", "$script:ModuleRoot\Public\*.ps1" |
        ForEach-Object { . $_.FullName }

    # Defined here, not in a Describe body. A Describe body runs during
    # discovery, so a function declared there has gone by the time an It
    # block runs and every test calling it fails as a missing command.
    function Invoke-CreateFixture {
        param(
            [string] $Dir,
            [string] $Stamp,
            [hashtable] $Steps = @{},
            [bool] $Finished = $true
        )
        # Write transcript
        $transcriptContent = "Maintenance run started"
        if ($Finished) {
            $transcriptContent += "`nFinished 0 steps in 1s"
        }
        Set-Content -LiteralPath (Join-Path $Dir "Update-Everything-$Stamp.log") -Value $transcriptContent

        foreach ($stepName in $Steps.Keys) {
            $status = $Steps[$stepName]
            $stepLogFile = Join-Path $Dir "$($stepName)-$Stamp.log"

            $lines = @()
            $lines += "2026-09-16 20:40:50 | STARTING $stepName"

            switch ($status) {
                'Failed' {
                    $lines += "2026-09-16 20:41:01 | FAILED | External command exited with code 1"
                }
                'Warning' {
                    $lines += "2026-09-16 20:41:01 | COMPLETED WITH ERRORS | 1 error record(s) | Duration: 11s"
                }
                'Skipped' {
                    $lines += "2026-09-16 20:41:01 | SKIPPED | installing PowerShell 7 was not approved"
                }
                'Completed' {
                    $lines += "2026-09-16 20:41:01 | COMPLETED | Duration: 2.1s"
                }
                'Interrupted' {
                    # No verdict line
                }
                default {
                    $lines += "2026-09-16 20:41:01 | COMPLETED | Duration: 1.0s"
                }
            }
            Set-Content -LiteralPath $stepLogFile -Value $lines
        }
    }
}

Describe 'Get-UpdateEverythingIssue' -Tag 'Unit','LastRun' {


    BeforeAll {
        $script:TestDriveDir = $TestDrive
    }

    It 'reports exactly one issue for a run with one FAILED step' {
        $dir = Join-Path $TestDrive "run1"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000001" -Steps @{ 'step-one' = 'Failed' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 1
        $result[0].Status | Should-Be 'Failed'
    }

    It 'carries the message from after the status keyword in Detail' {
        $dir = Join-Path $TestDrive "run2"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000002" -Steps @{ 'step-one' = 'Failed' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        $result[0].Detail | Should-ContainCollection 'External command exited with code 1'
    }

    It 'reports a COMPLETED WITH ERRORS step as Warning' {
        $dir = Join-Path $TestDrive "run3"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000003" -Steps @{ 'step-one' = 'Warning' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 1
        $result[0].Status | Should-Be 'Warning'
    }

    It 'does not report a step that only says COMPLETED' {
        $dir = Join-Path $TestDrive "run4"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000004" -Steps @{ 'step-one' = 'Completed' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 0
    }

    It 'excludes SKIPPED steps by default' {
        $dir = Join-Path $TestDrive "run5"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000005" -Steps @{ 'step-one' = 'Skipped' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 0
    }

    It 'includes SKIPPED steps with -IncludeSkipped' {
        $dir = Join-Path $TestDrive "run6"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000006" -Steps @{ 'step-one' = 'Skipped' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir -IncludeSkipped
        @($result).Count | Should-Be 1
        $result[0].Status | Should-Be 'Skipped'
    }

    It 'uses the step name from the STARTING line, not the file name' {
        $dir = Join-Path $TestDrive "run7"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        # File name is sanitised: winget-all-sources
        # STARTING line has real name: winget (all sources)
        $stamp = "20260101-000007"
        $transcript = "Maintenance run started`nFinished 0 steps in 1s"
        Set-Content -LiteralPath (Join-Path $dir "Update-Everything-$stamp.log") -Value $transcript

        $stepLog = Join-Path $dir "winget-all-sources-$stamp.log"
        $content = @(
            "2026-09-16 20:40:50 | STARTING winget (all sources)",
            "2026-09-16 20:41:01 | FAILED | Something broke"
        )
        Set-Content -LiteralPath $stepLog -Value $content

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        $result[0].Step | Should-Be 'winget (all sources)'
    }

    It 'ignores untimestamped lines that look like errors' {
        $dir = Join-Path $TestDrive "run8"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $stamp = "20260101-000008"
        $transcript = "Maintenance run started`nFinished 0 steps in 1s"
        Set-Content -LiteralPath (Join-Path $dir "Update-Everything-$stamp.log") -Value $transcript

        $stepLog = Join-Path $dir "step-$stamp.log"
        $content = @(
            "FAILED to contact the update server",
            "2026-09-16 20:40:50 | STARTING step",
            "2026-09-16 20:41:01 | COMPLETED | Duration: 1.0s"
        )
        Set-Content -LiteralPath $stepLog -Value $content

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 0
    }

    It 'returns nothing for an empty log directory' {
        $dir = Join-Path $TestDrive "run9"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        $result | Should-BeNull
    }

    It 'reports only the newest run by file name stamp' {
        $dir = Join-Path $TestDrive "run10"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $olderStamp = "20260101-000001"
        $newerStamp = "20260101-000002"

        # Create older run
        Invoke-CreateFixture -Dir $dir -Stamp $olderStamp -Steps @{ 'old-step' = 'Failed' }

        # Create newer run
        Invoke-CreateFixture -Dir $dir -Stamp $newerStamp -Steps @{ 'new-step' = 'Failed' }

        # Write older file LAST to make its LastWriteTime newer
        # We need to touch the file to update LastWriteTime
        (Get-Item (Join-Path $dir "Update-Everything-$olderStamp.log")).LastWriteTime = (Get-Date).AddMinutes(1)

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 1
        $result[0].Step | Should-Be 'new-step'
    }

    It 'reports Interrupted status for a run killed mid-step' {
        $dir = Join-Path $TestDrive "run11"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $stamp = "20260101-000011"
        # Transcript does not say Finished
        $transcript = "Maintenance run started"
        Set-Content -LiteralPath (Join-Path $dir "Update-Everything-$stamp.log") -Value $transcript

        # Step log has STARTING but no verdict
        $stepLog = Join-Path $dir "step-$stamp.log"
        $content = @(
            "2026-09-16 20:40:50 | STARTING step"
        )
        Set-Content -LiteralPath $stepLog -Value $content

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 1
        $result[0].Status | Should-Be 'Interrupted'
    }

    It 'has PSTypeName UpdateEverything.Issue' {
        $dir = Join-Path $TestDrive "run12"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Invoke-CreateFixture -Dir $dir -Stamp "20260101-000012" -Steps @{ 'step-one' = 'Failed' }

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        $result[0].PSObject.TypeNames[0] | Should-Be 'UpdateEverything.Issue'
    }

    It 'prefers the summary file over the logs' {
        $dir = Join-Path $TestDrive "run13"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $stamp = "20260101-000013"
        # Create log files with one step name
        Invoke-CreateFixture -Dir $dir -Stamp $stamp -Steps @{ 'log-step' = 'Failed' }

        # Create summary file with a different step name
        $summaryPath = Join-Path $dir "Update-Everything-$stamp.summary.json"
        $summary = @{
            Schema = 1
            RunStamp = $stamp
            Steps = @(@{
                Step = "summary-step"
                Status = "Failed"
                Detail = @("Summary detail")
                Log = "log-path"
            })
        }
        $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $summaryPath

        $result = Get-UpdateEverythingIssue -LogDirectory $dir
        @($result).Count | Should-Be 1
        $result[0].Step | Should-Be 'summary-step'
        $result[0].Source | Should-Be 'Summary'
    }
}

Describe 'Save-UpdateRunSummary' -Tag 'Unit','LastRun' {

    It 'writes a summary file with the expected name' {
        $dir = Join-Path $TestDrive "save1"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $result = Save-UpdateRunSummary -LogDirectory $dir -RunStamp "20260101-000001" -Steps @()

        $expectedPath = Join-Path $dir "Update-Everything-20260101-000001.summary.json"
        Test-Path -LiteralPath $expectedPath | Should-BeTrue
        $result | Should-Be $expectedPath
    }

    It 'round-trips JSON with Detail as an array' {
        $dir = Join-Path $TestDrive "save2"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $steps = @(@{
            Step = "test-step"
            Status = "Failed"
            Detail = @("Error 1", "Error 2")
            Seconds = 1.5
            Log = "log.log"
        })

        $path = Save-UpdateRunSummary -LogDirectory $dir -RunStamp "20260101-000002" -Steps $steps

        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $json.Steps[0].Detail | Should-BeCollection @("Error 1", "Error 2")
        $json.Steps[0].Detail.Count | Should-Be 2
    }

    It 'does not write a file with -WhatIf' {
        $dir = Join-Path $TestDrive "save3"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $result = Save-UpdateRunSummary -LogDirectory $dir -RunStamp "20260101-000003" -Steps @() -WhatIf
        $result | Should-BeNull

        $expectedPath = Join-Path $dir "Update-Everything-20260101-000003.summary.json"
        Test-Path -LiteralPath $expectedPath | Should-BeFalse
    }
}

Describe 'Update-Everything -IssuesFromLastRun' -Tag 'Static','LastRun' {

    BeforeAll {
        $script:SourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Public\Update-Everything.ps1'
        if (Test-Path -LiteralPath $script:SourcePath) {
            $script:SourceText = Get-Content -LiteralPath $script:SourcePath -Raw
        } else {
            $script:SourceText = ''
        }
    }

    It 'returns Get-UpdateEverythingIssue before invoking steps' {
        if (-not $script:SourceText) { return }

        $issuesPos = $script:SourceText.IndexOf('Get-UpdateEverythingIssue')
        $invokePos = $script:SourceText.IndexOf('Invoke-Step')

        $issuesPos | Should-BeGreaterThan -1
        $invokePos | Should-BeGreaterThan -1
        $issuesPos | Should-BeLessThan $invokePos
    }

    It 'declares -IssuesFromLastRun and -IncludeSkipped parameters' {
        if (-not $script:SourceText) { return }

        $script:SourceText | Should-MatchString '\[switch\]\s*\$IssuesFromLastRun'
        $script:SourceText | Should-MatchString '\[switch\]\s*\$IncludeSkipped'
    }
}
