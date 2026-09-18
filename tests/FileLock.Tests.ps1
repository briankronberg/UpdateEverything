#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0' }

BeforeAll {
    $script:ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
    Get-ChildItem "$script:ModuleRoot\Private\*.ps1", "$script:ModuleRoot\Public\*.ps1" |
        ForEach-Object { . $_.FullName }
}

Describe 'Get-FileLockMessage' -Tag 'Unit','FileLock' {

    BeforeEach {
        # Nothing here may read the real process table. What is running on this
        # machine changes by the hour, and a test that depends on it passes or
        # fails by the day rather than by the code.
        Mock Get-CimInstance { }
    }

    # $text rather than $input throughout: $input is the automatic variable
    # holding pipeline input, and assigning to it fails the analyzer.

    It 'recognises the single-quoted sharing violation form' {
        # The wording Windows actually produced on the machine this came from.
        $text = "The process cannot access the file 'C:\Users\brian\.local\bin\uvx.exe' because it is being used by another process"
        $result = Get-FileLockMessage -Output $text
        $result | Should-NotBeNull
        $result | Should-MatchString ([regex]::Escape('C:\Users\brian\.local\bin\uvx.exe'))
    }

    It 'recognises the double-quoted sharing violation form' {
        # Some tools quote the path the other way.
        $text = 'The process cannot access the file "C:\Users\brian\.local\bin\uvx.exe" because it is being used by another process'
        $result = Get-FileLockMessage -Output $text
        $result | Should-NotBeNull
        $result | Should-MatchString ([regex]::Escape('C:\Users\brian\.local\bin\uvx.exe'))
    }

    It 'recognises the bare unquoted sharing violation form' {
        # And some do not quote it at all.
        $text = 'The process cannot access the file C:\Users\brian\.local\bin\uvx.exe because it is being used by another process'
        $result = Get-FileLockMessage -Output $text
        $result | Should-NotBeNull
        $result | Should-MatchString ([regex]::Escape('C:\Users\brian\.local\bin\uvx.exe'))
    }

    It 'returns nothing when the sharing violation sentence is absent' {
        # The caller tests the result and falls back to its own message, so
        # returning nothing has to mean nothing rather than an empty string.
        $result = Get-FileLockMessage -Output 'all is well'
        $result | Should-BeNull
    }

    It 'returns nothing for an empty string' {
        # The parameter allows an empty string, so this must not throw.
        $result = Get-FileLockMessage -Output ''
        $result | Should-BeNull
    }

    It 'returns nothing for a path mentioned without the lock sentence' {
        # The one that stops an ordinary log line being read as a lock. Tools
        # print paths constantly; only the full sentence means a sharing
        # violation.
        $text = 'Copying C:\Users\brian\.local\bin\uvx.exe to destination'
        $result = Get-FileLockMessage -Output $text
        $result | Should-BeNull
    }

    It 'reports only the first locked file when several are named' {
        # One locked file explains the failure. Listing every one buries it.
        $text = @"
The process cannot access the file 'C:\first\file.exe' because it is being used by another process
The process cannot access the file 'C:\second\file.exe' because it is being used by another process
"@
        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString ([regex]::Escape('C:\first\file.exe'))
        $result | Should-NotMatchString ([regex]::Escape('C:\second\file.exe'))
    }

    # The function makes two different calls: one unfiltered, to list processes,
    # and one with -Filter, to resolve a parent. Pester binds named parameters
    # into variables, so the mocks are told apart by $Filter rather than by
    # $args, which is empty for a bound call.

    It 'names the holding process and its pid' {
        $lockedPath = 'C:\Users\brian\.local\bin\uvx.exe'
        $text = "The process cannot access the file '$lockedPath' because it is being used by another process"

        $holder = [pscustomobject]@{
            ExecutablePath  = $lockedPath
            Name            = 'uvx.exe'
            ProcessId       = 1234
            ParentProcessId = 5678
        }

        Mock Get-CimInstance -ParameterFilter { -not $Filter } { $holder }
        Mock Get-CimInstance -ParameterFilter { $Filter } { }

        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString 'uvx\.exe'
        $result | Should-MatchString '1234'
    }

    It 'names the parent when it can be resolved' {
        # The parent is the useful half when the holder is a generic runner:
        # "uvx.exe" says little, "parent claude.exe" says who to close.
        $lockedPath = 'C:\Users\brian\.local\bin\uvx.exe'
        $text = "The process cannot access the file '$lockedPath' because it is being used by another process"

        $holder = [pscustomobject]@{
            ExecutablePath  = $lockedPath
            Name            = 'uvx.exe'
            ProcessId       = 1234
            ParentProcessId = 5678
        }
        $parent = [pscustomobject]@{ Name = 'claude.exe' }

        Mock Get-CimInstance -ParameterFilter { -not $Filter } { $holder }
        Mock Get-CimInstance -ParameterFilter { $Filter } { $parent }

        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString 'claude\.exe'
    }

    It 'says so when no holder can be identified' {
        # A lock held by another user, or by a process that has since exited,
        # leaves nothing to name. Saying that beats an empty list.
        $lockedPath = 'C:\Users\brian\.local\bin\uvx.exe'
        $text = "The process cannot access the file '$lockedPath' because it is being used by another process"

        Mock Get-CimInstance { }

        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString 'No holding process could be identified'
    }

    It 'still reports the lock when the process query fails' {
        # Looking for the holder must never become the thing that fails. The
        # file is locked either way, and that is the part worth reporting.
        $lockedPath = 'C:\Users\brian\.local\bin\uvx.exe'
        $text = "The process cannot access the file '$lockedPath' because it is being used by another process"

        Mock Get-CimInstance { throw 'WMI is unavailable' }

        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString 'Could not replace'
        $result | Should-MatchString 'process is using it'
    }

    It 'caps the holder list and counts the rest' {
        # One tool spawning many children would otherwise turn a summary line
        # into a paragraph. Six holders, four listed, two counted.
        $lockedPath = 'C:\Users\brian\.local\bin\uvx.exe'
        $text = "The process cannot access the file '$lockedPath' because it is being used by another process"

        $holders = @()
        for ($i = 0; $i -lt 6; $i++) {
            $holders += [pscustomobject]@{
                ExecutablePath  = $lockedPath
                Name            = 'uvx.exe'
                ProcessId       = 1000 + $i
                ParentProcessId = 5678
            }
        }

        Mock Get-CimInstance -ParameterFilter { -not $Filter } { $holders }
        Mock Get-CimInstance -ParameterFilter { $Filter } { }

        $result = Get-FileLockMessage -Output $text
        $result | Should-MatchString 'and 2 more'
    }
}

Describe 'Get-FileLockMessage source' -Tag 'Static','FileLock' {

    BeforeAll {
        $script:SourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Private\Get-FileLockMessage.ps1'
        $script:SourceText = Get-Content -LiteralPath $script:SourcePath -Raw
    }

    It 'never calls exit' {
        $script:SourceText | Should-NotMatchString '(?m)^\s*exit\b'
    }

    It 'never assigns $ErrorActionPreference' {
        $script:SourceText | Should-NotMatchString '\$ErrorActionPreference\s*='
    }

    It 'never writes a variable immediately followed by a colon' {
        # "$path: text" reads as a drive qualifier and does not parse.
        $script:SourceText | Should-NotMatchString '\$[A-Za-z_]\w*:(?=[ $])'
    }
}

Describe 'The uv step uses it' -Tag 'Static','FileLock' {

    # A helper nothing calls is a helper that rots. uv replaces uv.exe and
    # uvx.exe together, and anything launched through uvx holds the latter open
    # for as long as it runs, so this is the step where a lock actually recurs.
    # Bounded by the step, not by a character window: a proximity check would
    # break the next time a comment is added above it.
    BeforeAll {
        $script:MainText = Get-Content `
            (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Public\Update-Everything.ps1') -Raw
    }

    It 'calls Get-FileLockMessage inside the uv step' {
        $start = $script:MainText.IndexOf("Invoke-Step -Name 'uv'")
        $start | Should-BeGreaterThan -1

        $next = $script:MainText.IndexOf('Invoke-Step -Name', $start + 1)
        if ($next -lt 0) { $next = $script:MainText.Length }

        $step = $script:MainText.Substring($start, $next - $start)
        $step | Should-MatchString 'Get-FileLockMessage'
    }

    It 'still reports a locked binary as an error, not as success' {
        # A lock is a real failure to update. Naming the cause must not quietly
        # downgrade it, which would drop it out of the summary entirely.
        $start = $script:MainText.IndexOf("Invoke-Step -Name 'uv'")
        $next = $script:MainText.IndexOf('Invoke-Step -Name', $start + 1)
        if ($next -lt 0) { $next = $script:MainText.Length }

        $step = $script:MainText.Substring($start, $next - $start)
        $step | Should-MatchString '(?s)lockNote.*Write-Error'
    }
}
