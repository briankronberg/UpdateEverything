function Get-FileLockMessage {
    <#
        .SYNOPSIS
        Turns a Windows sharing-violation message into an actionable sentence.

        .DESCRIPTION
        A step that failed may say a file is locked. This pulls the path out of
        the standard Windows wording, asks the process table who is holding it,
        and returns one sentence naming both. The caller gets something it can
        print instead of pointing the reader at a log to open.

        Returns nothing when the output carries no sharing-violation sentence,
        so a caller can test the result and fall back to its own message.

        What it finds is a process whose own image is the locked file, which is
        the usual case when replacing an executable. A process holding the file
        open some other way will not appear. The sentence says "likely" for
        that reason and never claims to be the whole list.

        .PARAMETER Output
        The captured step output to search.

        .EXAMPLE
        $note = Get-FileLockMessage -Output ($output | Out-String)
        if ($note) { Write-Error $note }

        .EXAMPLE
        Get-FileLockMessage -Output 'all is well'

        Returns nothing, because the sharing-violation wording is absent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Output
    )

    # The standard Windows sentence, with the path in single quotes, double
    # quotes, or bare. Anchoring on the whole sentence rather than on the path
    # means an unrelated line that merely mentions a file cannot match.
    # Written with a double-quoted here-string so both quote characters can sit
    # in the character class without escaping games.
    $pattern = @"
The process cannot access the file\s+(?:'([^']+)'|"([^"]+)"|(\S+))\s+because it is being used by another process
"@
    $match = [regex]::Match($Output, $pattern.Trim())
    if (-not $match.Success) { return }

    $lockedPath = $match.Groups[1].Value
    if (-not $lockedPath) { $lockedPath = $match.Groups[2].Value }
    if (-not $lockedPath) { $lockedPath = $match.Groups[3].Value }

    # Only the first match. One locked file explains the failure, and listing
    # every one would bury the fact under a list.
    $baseSentence = "Could not replace ${lockedPath}: a process is using it."

    try {
        $holders = @(Get-CimInstance Win32_Process -ErrorAction Stop |
                Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -ieq $lockedPath) })

        if (-not $holders.Count) {
            return "$baseSentence No holding process could be identified; it may belong to another user or have exited."
        }

        # Capped, so one tool that spawns many children cannot turn a summary
        # line into a paragraph. The rest are counted instead.
        $maxListed = 4
        $limit = [Math]::Min($holders.Count, $maxListed)
        $described = [System.Collections.Generic.List[string]]::new()

        for ($i = 0; $i -lt $limit; $i++) {
            $holder = $holders[$i]
            $parentName = $null
            if ($holder.ParentProcessId) {
                $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($holder.ParentProcessId)" -ErrorAction SilentlyContinue
                if ($parent) { $parentName = $parent.Name }
            }

            if ($parentName) {
                $described.Add("$($holder.Name) (pid $($holder.ProcessId), parent ${parentName})")
            } else {
                # The parent is the useful part when the holder is a generic
                # runner, so omit it rather than printing an empty value.
                $described.Add("$($holder.Name) (pid $($holder.ProcessId))")
            }
        }

        $holdersText = $described -join ', '
        $extra = $holders.Count - $limit
        if ($extra -gt 0) { $holdersText = "$holdersText, and $extra more" }

        "$baseSentence Likely holders: ${holdersText}. Close them and run the update again."
    } catch {
        # Looking for the holder must never become the thing that fails. The
        # file is locked either way, and that is the part worth reporting.
        Write-Verbose "Could not query the process table for ${lockedPath}: $($_.Exception.Message)"
        $baseSentence
    }
}
