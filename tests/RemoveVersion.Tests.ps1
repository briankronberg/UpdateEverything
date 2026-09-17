#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0' }

BeforeAll {
    $script:ModuleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
    Get-ChildItem "$script:ModuleRoot\Private\*.ps1", "$script:ModuleRoot\Public\*.ps1" |
        ForEach-Object { . $_.FullName }
}

Describe 'Remove-UpdateEverythingVersion Static Analysis' -Tag 'Static','VersionRemoval' {
    BeforeAll {
        $script:SourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Public\Remove-UpdateEverythingVersion.ps1'
        $script:SourceText = Get-Content -LiteralPath $script:SourcePath -Raw
        $script:Tokens = $null
        $script:Errors = $null
        $script:AST = [System.Management.Automation.Language.Parser]::ParseFile($script:SourcePath, [ref]$script:Tokens, [ref]$script:Errors)
    }

    # BUG 1: -RepairTask and -Force were declared but never read, making the switches no-ops.
    #
    # Two ways this test can lie, both of which it did before being rewritten:
    # the file-level ScriptBlockAst has no ParamBlock of its own, because the
    # param block belongs to the function inside it, so reading $AST.ParamBlock
    # compared an empty list and passed for anything. And a parameter always
    # appears in its own declaration, so searching the whole file finds every
    # parameter "used" even when nothing reads it. The param block's extent is
    # therefore excluded by offset.
    It 'reads every declared parameter in the function body' {
        $function = $script:AST.FindAll({
                param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) | Select-Object -First 1

        $paramBlock = $function.Body.ParamBlock
        $paramNames = @($paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $paramNames.Count | Should-BeGreaterThan 0 -Because 'finding no parameters at all would make this test vacuous'

        $blockEnd = $paramBlock.Extent.EndOffset
        $readAfterDeclaration = @($function.Body.FindAll({
                    param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst]
                }, $true) |
                Where-Object { $_.Extent.StartOffset -ge $blockEnd } |
                ForEach-Object { $_.VariablePath.UserPath })

        $unused = @($paramNames | Where-Object { $_ -notin $readAfterDeclaration })
        $unused | Should-BeNull -Because "these are declared but never read: $($unused -join ', ')"
    }

    # BUG 2: The function must not kill the caller's session.
    It 'never calls exit' {
        $script:SourceText | Should-NotMatchString '(?m)^\s*exit\b'
    }

    # BUG 3: House rule forbids assigning the global error preference.
    It 'never assigns $ErrorActionPreference' {
        $script:SourceText | Should-NotMatchString '\$ErrorActionPreference\s*='
    }

    # BUG 4: Set-ScheduledTask without -Action discards the mutated in-memory object.
    It 'always calls Set-ScheduledTask with -Action' {
        $commandAsts = $script:AST.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
        $setTaskCalls = @($commandAsts | Where-Object { $_.CommandOriginalText -eq 'Set-ScheduledTask' })

        foreach ($call in $setTaskCalls) {
            $hasAction = $false
            foreach ($arg in $call.CommandElements) {
                if ($arg -is [System.Management.Automation.Language.ArgumentAst]) {
                    foreach ($element in $arg.Elements) {
                        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $element.Value -eq '-Action') {
                            $hasAction = $true
                        }
                    }
                }
            }
            $hasAction | Should-BeTrue -Because "Set-ScheduledTask call does not include -Action"
        }
    }

    # BUG 5: "$var: text" is a parse error, because PowerShell reads $var: as a
    # drive or scope qualifier and then finds no name after it.
    #
    # Only a colon followed by a space or a dollar is the error. A colon followed
    # by a word character is a real qualifier, as in "$script:ModuleRoot" or
    # "$env:ProgramFiles", and flagging those would fail on correct code. $hits
    # rather than $matches: the latter is an automatic variable.
    It 'never writes a variable immediately followed by a colon in a string' {
        $hits = [regex]::Matches($script:SourceText, '\$[A-Za-z_]\w*:(?=[ $])')
        $hits.Count | Should-Be 0 -Because "these would not parse: $(($hits | ForEach-Object { $_.Value }) -join ', ')"
    }

    It 'parses with no errors' {
        $script:Errors | Should-BeNull
    }
}

Describe 'Remove-UpdateEverythingVersion Behaviour' -Tag 'Unit','VersionRemoval' {
    # BUG 6: -WhatIf must prevent deletion.
    It 'removes nothing when -WhatIf is used' {
        Mock Get-ScheduledTask { $null }
        Mock Test-Path { $false }
        Mock Get-ChildItem { $null }

        $result = Remove-UpdateEverythingVersion -WhatIf 6>$null
        @($result.Removed).Count | Should-Be 0
    }

    It 'returns an object with all five properties' {
        Mock Get-ScheduledTask { $null }
        Mock Test-Path { $false }
        Mock Get-ChildItem { $null }

        $result = Remove-UpdateEverythingVersion 6>$null
        $result.PSObject.Properties.Name | Should-ContainCollection 'Removed'
        $result.PSObject.Properties.Name | Should-ContainCollection 'Orphaned'
        $result.PSObject.Properties.Name | Should-ContainCollection 'Kept'
        $result.PSObject.Properties.Name | Should-ContainCollection 'Refused'
        $result.PSObject.Properties.Name | Should-ContainCollection 'TaskRepaired'
    }

    It 'has the correct PSTypeName' {
        Mock Get-ScheduledTask { $null }
        Mock Test-Path { $false }
        Mock Get-ChildItem { $null }

        $result = Remove-UpdateEverythingVersion 6>$null
        $result.PSObject.TypeNames[0] | Should-Be 'UpdateEverything.VersionRemoval'
    }

    # BUG 7: Kept list contained duplicates due to multiple writers.
    It 'contains no duplicate paths in Kept' {
        Mock Get-ScheduledTask { $null }
        Mock Test-Path { $false }
        Mock Get-ChildItem { $null }

        $result = Remove-UpdateEverythingVersion 6>$null
        $uniqueKept = @($result.Kept | Sort-Object -Unique)
        $result.Kept.Count | Should-Be $uniqueKept.Count
    }

    It 'never has a path in both Kept and Refused' {
        Mock Get-ScheduledTask { $null }
        Mock Test-Path { $false }
        Mock Get-ChildItem { $null }

        $result = Remove-UpdateEverythingVersion 6>$null
        $refusedPaths = @($result.Refused | ForEach-Object { $_.Path })
        $intersection = @($result.Kept | Where-Object { $_ -in $refusedPaths })
        $intersection | Should-BeNull
    }
}

Describe 'Remove-UpdateEverythingVersion Parameter Contract' -Tag 'Unit','VersionRemoval' {
    It 'has the required parameters' {
        $command = Get-Command Remove-UpdateEverythingVersion
        $command.Parameters.Keys | Should-ContainCollection 'Version'
        $command.Parameters.Keys | Should-ContainCollection 'Keep'
        $command.Parameters.Keys | Should-ContainCollection 'RepairTask'
        $command.Parameters.Keys | Should-ContainCollection 'Force'
    }

    It 'supports ShouldProcess' {
        $command = Get-Command Remove-UpdateEverythingVersion
        $command.Parameters.ContainsKey('WhatIf') | Should-BeTrue
    }
}
