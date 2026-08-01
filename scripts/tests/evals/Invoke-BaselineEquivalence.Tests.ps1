#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '../../evals/Invoke-BaselineEquivalence.ps1'
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '../../..') | Select-Object -ExpandProperty Path
}

Describe 'Invoke-BaselineEquivalence.ps1 (dry-run)' -Tag 'Unit' {
    BeforeEach {
        $script:OutputPath = Join-Path $TestDrive "summary-$([Guid]::NewGuid()).json"
    }

    Context 'Devloop tier defaults' {
        BeforeEach {
            & $script:ScriptPath `
                -Tier 'devloop' `
                -RepoRoot $script:RepoRoot `
                -OutputPath $script:OutputPath `
                -WhatIf *> $null
            $script:Summary = Get-Content -LiteralPath $script:OutputPath -Raw | ConvertFrom-Json
        }

        It 'Exits with code 0' {
            $LASTEXITCODE | Should -Be 0
        }

        It 'Writes a summary JSON to the requested path' {
            Test-Path -LiteralPath $script:OutputPath | Should -BeTrue
        }

        It 'Records the agent slug' {
            $script:Summary.agent | Should -Be 'rpi-agent'
        }

        It 'Records tier=devloop' {
            $script:Summary.tier | Should -Be 'devloop'
        }

        It 'Selects exactly one PR-tier model' {
            $script:Summary.model | Should -Not -BeNullOrEmpty
            $script:Summary.plannedCommands.Count | Should -Be 3
        }

        It 'Includes workspace and skill-dir flags for baseline and customized runs' {
            $baselineCommand = $script:Summary.plannedCommands[0]
            $customizedCommand = $script:Summary.plannedCommands[1]

            $baselineCommand | Should -Match '--workspace'
            $baselineCommand | Should -Match '--skill-dir'
            $customizedCommand | Should -Match '--workspace'
            $customizedCommand | Should -Match '--skill-dir'
        }

        It 'Isolates the baseline run with empty workspace and skill-dir arguments' {
            $baselineCommand = $script:Summary.plannedCommands[0]

            $baselineCommand | Should -Match '--workspace ""'
            $baselineCommand | Should -Match '--skill-dir ""'
        }

        It 'Points the customized run at populated workspace and skill-dir paths' {
            $customizedCommand = $script:Summary.plannedCommands[1]

            $customizedCommand | Should -Match '--workspace "[^"]+"'
            # The customized skill directory is materialized per agent under the run
            # output root. Pointing it at the whole .github/skills tree would load every
            # skill for every agent, so two different agents would produce identical
            # customized runs and the comparison could not distinguish them.
            $customizedCommand | Should -Match '--skill-dir "[^"]+customized-skill-dir"'
            $customizedCommand | Should -Not -Match '--skill-dir "[^"]*\.github[/\\]skills"'
        }

        It 'Reports zeroed run/aggregate counters' {
            $script:Summary.runs | Should -Be 0
            $script:Summary.ties | Should -Be 0
            $script:Summary.baselineWins | Should -Be 0
            $script:Summary.treatmentWins | Should -Be 0
            $script:Summary.invariantFailures | Should -Be 0
            $script:Summary.runHealthFailures | Should -Be 0
            $script:Summary.divergenceGuardFailures | Should -Be 0
        }

        It 'Declares the reporting contract version' {
            # Consumers reject an unsupported major version rather than reading absent
            # fields as zeros, so the dry-run summary must carry it too.
            $script:Summary.schemaVersion | Should -Be '2.0.0'
        }

        It 'Carries no legacy A/B keys' {
            $script:Summary.PSObject.Properties.Name | Should -Not -Contain 'aWins'
            $script:Summary.PSObject.Properties.Name | Should -Not -Contain 'bWins'
            $script:Summary.PSObject.Properties.Name | Should -Not -Contain 'divergenceFailures'
        }

        It 'Sets verdict to dry-run' {
            $script:Summary.verdict | Should -Be 'dry-run'
        }

        It 'Records variant metadata for baseline (A) and customized (B)' {
            $script:Summary.variants | Should -Not -BeNullOrEmpty
            $script:Summary.variants.a | Should -Not -BeNullOrEmpty
            $script:Summary.variants.b | Should -Not -BeNullOrEmpty
            $script:Summary.variants.a.kind | Should -Be 'baseline'
            $script:Summary.variants.b.name | Should -Be 'rpi-agent'
            $script:Summary.variants.subject | Should -Be 'rpi-agent'
        }
    }

    Context 'CI tier expansion' {
        BeforeEach {
            & $script:ScriptPath `
                -Agent 'rpi-agent' `
                -Tier 'ci' `
                -RepoRoot $script:RepoRoot `
                -OutputPath $script:OutputPath `
                -WhatIf *> $null
            $script:Summary = Get-Content -LiteralPath $script:OutputPath -Raw | ConvertFrom-Json
        }

        It 'Records tier=ci' {
            $script:Summary.tier | Should -Be 'ci'
        }

        It 'Plans commands for three nightly models' {
            $script:Summary.plannedCommands.Count | Should -Be 9
        }

        It 'Selects gpt-5.5 as the primary nightly model' {
            $script:Summary.model | Should -Be 'gpt-5.5'
        }
    }

    Context 'Retired parameters and tiers' {
        BeforeAll {
            . $script:ScriptPath
        }

        It 'Rejects the removed StimulusFilter parameter' {
            # It was a no-op: it only appended a comment to dry-run command text and was
            # never passed to Vally, so a run believed to be filtered ran the full suite.
            { & $script:ScriptPath `
                    -Agent 'rpi-agent' `
                    -Tier 'devloop' `
                    -StimulusFilter '^code-' `
                    -RepoRoot $script:RepoRoot `
                    -OutputPath $script:OutputPath `
                    -WhatIf *> $null } | Should -Throw
        }

        It 'Rejects the retired pr tier by name' {
            # No alias: pr and nightly carried different exit policies, so silently
            # mapping one onto a new name would change a caller's gating behavior.
            $err = { Assert-SupportedTier -Tier 'pr' } | Should -Throw -PassThru
            $err.Exception.Message | Should -Match 'devloop'
        }

        It 'Rejects the retired nightly tier by name' {
            $err = { Assert-SupportedTier -Tier 'nightly' } | Should -Throw -PassThru
            $err.Exception.Message | Should -Match "'-Tier ci'"
        }

        It 'Accepts the supported tiers' {
            { Assert-SupportedTier -Tier 'devloop' } | Should -Not -Throw
            { Assert-SupportedTier -Tier 'ci' } | Should -Not -Throw
        }

        It 'Rejects an unknown tier without suggesting a migration' {
            $err = { Assert-SupportedTier -Tier 'staging' } | Should -Throw -PassThru
            $err.Exception.Message | Should -Match 'Unsupported tier'
        }
    }

    Context 'Model override' {
        It 'Pins the PR-tier model to the supplied override' {
            & $script:ScriptPath `
                -Agent 'rpi-agent' `
                -Tier 'devloop' `
                -Model 'gpt-5-mini' `
                -RepoRoot $script:RepoRoot `
                -OutputPath $script:OutputPath `
                -WhatIf *> $null

            $summary = Get-Content -LiteralPath $script:OutputPath -Raw | ConvertFrom-Json
            $summary.model | Should -Be 'gpt-5-mini'
            ($summary.plannedCommands -join "`n") | Should -Match 'gpt-5-mini'
        }

        It 'Ignores the override for the nightly tier' {
            & $script:ScriptPath `
                -Agent 'rpi-agent' `
                -Tier 'ci' `
                -Model 'gpt-5-mini' `
                -RepoRoot $script:RepoRoot `
                -OutputPath $script:OutputPath `
                -WhatIf *> $null

            $summary = Get-Content -LiteralPath $script:OutputPath -Raw | ConvertFrom-Json
            $summary.model | Should -Be 'gpt-5.5'
        }
    }

    Context 'Parameter validation' {
        It 'Rejects an unknown tier' {
            # Assert-SupportedTier throws, but the script's outer catch converts it to exit 3.
            & $script:ScriptPath -Tier 'weekly' -RepoRoot $script:RepoRoot -OutputPath $script:OutputPath -WhatIf *> $null
            $LASTEXITCODE | Should -Be 3
        }
    }
}

Describe 'Measure-InvariantFailures' -Tag 'Unit' {
    BeforeAll {
        . $script:ScriptPath
        $script:Pass = [char]::ConvertFromUtf32(0x2705)
        $script:Fail = [char]::ConvertFromUtf32(0x274C)
        $script:Warn = [char]::ConvertFromUtf32(0x1F7E1)
        $script:Header = '| Stimulus | Graders | Pass Rate | pass@k | pass^k | Duration | Tokens | Verdict |'
        $script:Sep = '|---|---|---|---|---|---|---|---|'
    }

    It 'Returns zero failures when all rows pass' {
        $lines = @(
            $script:Header,
            $script:Sep,
            "| s1 | $script:Pass g 5/5 | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |",
            "| s2 | $script:Pass g 5/5 | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |"
        )
        $result = Measure-InvariantFailures -Lines $lines
        $result.Total | Should -Be 2
        $result.Failed | Should -Be 0
    }

    It 'Counts failed and warned rows as failures' {
        $lines = @(
            $script:Header,
            $script:Sep,
            "| s1 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |",
            "| s2 | g | 0%   | 0.00 | 0.00 | 1s | 10 | $script:Fail |",
            "| s3 | g | 60%  | 0.60 | 0.30 | 1s | 10 | $script:Warn |",
            "| s4 | g | 0%   | 0.00 | 0.00 | 1s | 10 | $script:Fail |"
        )
        $result = Measure-InvariantFailures -Lines $lines
        $result.Total | Should -Be 4
        $result.Failed | Should -Be 3
    }

    It 'Ignores header and separator rows' {
        $lines = @(
            $script:Header,
            $script:Sep,
            "| s1 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |"
        )
        $result = Measure-InvariantFailures -Lines $lines
        $result.Total | Should -Be 1
        $result.Failed | Should -Be 0
    }

    It 'Strips ANSI escape sequences before matching' {
        $ansiLine = "`e[32m| s1 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Fail |`e[0m"
        $result = Measure-InvariantFailures -Lines @($ansiLine)
        $result.Total | Should -Be 1
        $result.Failed | Should -Be 1
    }

    It 'Handles empty input' {
        $result = Measure-InvariantFailures -Lines @()
        $result.Total | Should -Be 0
        $result.Failed | Should -Be 0
    }

    It 'Ignores non-table lines' {
        $lines = @(
            '# Eval Results',
            '',
            'Some prose here.',
            $script:Header,
            $script:Sep,
            "| s1 | g | 0% | 0.00 | 0.00 | 1s | 10 | $script:Fail |"
        )
        $result = Measure-InvariantFailures -Lines $lines
        $result.Total | Should -Be 1
        $result.Failed | Should -Be 1
    }
}

Describe 'Resolve-ModelList' -Tag 'Unit' {
    BeforeAll {
        . $script:ScriptPath
    }

    It 'Uses GPT-5.6 Luna as the low-cost PR default' {
        $models = Resolve-ModelList -Tier 'devloop' -Hint '' -ModelOverride ''

        $models | Should -Be @('gpt-5.6-luna')
    }
}

Describe 'Comparison judge pin' -Tag 'Unit' {
    BeforeAll {
        . $script:ScriptPath
    }

    It 'Defaults to the reviewed low-cost judge' {
        # The pin previously lived only inside compare.eval.yml. That file is retired, so
        # this default is the sole carrier and a silent change to it would alter what the
        # comparison measures without any recorded decision.
        $param = (Get-Command $script:ScriptPath).Parameters['ComparisonJudgeModel']
        $param | Should -Not -BeNullOrEmpty

        $driverText = Get-Content -LiteralPath $script:ScriptPath -Raw
        $driverText | Should -Match "ComparisonJudgeModel\s*=\s*'claude-haiku-4\.5'"
    }

    It 'Passes the judge model on the compare invocation' {
        $driverText = Get-Content -LiteralPath $script:ScriptPath -Raw
        $driverText | Should -Match "'--judge-model',\s*\`$ComparisonJudgeModel"
    }

    It 'No longer renders or reads a compare eval spec' {
        # Asserts on executable surface, not prose. The driver retains comments
        # explaining why the judge pin moved, and those must not fail this check.
        $driverText = Get-Content -LiteralPath $script:ScriptPath -Raw
        $driverText | Should -Not -Match 'New-RenderedCompareSpec'
        $driverText | Should -Not -Match 'Resolve-AgentSurfaceSignaturePath'
        $driverText | Should -Not -Match 'surface_signatures'
        $driverText | Should -Not -Match "'--eval-spec',\s*\`$renderedSpecRelative"
    }
}

Describe 'Invoke-BaselineEquivalence.ps1 (stubbed nightly run)' -Tag 'Unit' {
    BeforeEach {
        $script:StubRepoRoot = Join-Path $TestDrive 'repo'
        $baselineRoot = Join-Path $script:StubRepoRoot 'evals/baseline-equivalence'
        $workspaceRoot = Join-Path $baselineRoot 'customized/workspace'
        New-Item -ItemType Directory -Path $workspaceRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:StubRepoRoot '.github/skills') -Force | Out-Null
        # The driver materializes a per-agent customized environment, so the stub repo
        # needs the agent file it will look for. Without it the run records a
        # materialization failure and this test would count that instead of the compare
        # failures it exists to measure.
        $stubAgentsDir = Join-Path $script:StubRepoRoot '.github/agents/hve-core'
        New-Item -ItemType Directory -Path $stubAgentsDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $stubAgentsDir 'rpi-agent.agent.md') -Encoding UTF8 -Value "---`nname: RPI Agent`n---`n`nStub agent for driver tests."

        $script:StubOutputPath = Join-Path $script:StubRepoRoot 'logs/summary.json'
        $stubVally = Join-Path $PSScriptRoot 'fixtures/stub-vally.ps1'
        Set-Alias -Name vally -Value $stubVally -Scope Global
        $env:STUB_VALLY_COMPARE_MODE = 'fail-empty'
    }

    AfterEach {
        Remove-Item Alias:vally -Force -ErrorAction SilentlyContinue
        Remove-Item Env:STUB_VALLY_COMPARE_MODE -ErrorAction SilentlyContinue
    }

    It 'Counts each failed empty compare once across nightly models' {
        & $script:ScriptPath `
            -Agent 'rpi-agent' `
            -Tier 'ci' `
            -RepoRoot $script:StubRepoRoot `
            -OutputPath $script:StubOutputPath *> $null

        $summary = Get-Content -LiteralPath $script:StubOutputPath -Raw | ConvertFrom-Json
        $summary.runHealthFailures | Should -Be 3
        $summary.runs | Should -Be 0
        $summary.verdict | Should -Be 'fail'
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Get-InvariantFailureCount' -Tag 'Unit' {
    BeforeAll {
        . $script:ScriptPath
        $script:Pass = [char]::ConvertFromUtf32(0x2705)
        $script:Fail = [char]::ConvertFromUtf32(0x274C)
        $script:Warn = [char]::ConvertFromUtf32(0x1F7E1)
        $script:Header = '| Stimulus | Graders | Pass Rate | pass@k | pass^k | Duration | Tokens | Verdict |'
        $script:Sep = '|---|---|---|---|---|---|---|---|'
    }

    It 'Returns $null when RunDir is empty' {
        Get-InvariantFailureCount -RunDir '' | Should -BeNullOrEmpty
    }

    It 'Returns $null when RunDir does not exist' {
        Get-InvariantFailureCount -RunDir (Join-Path $TestDrive 'nope') | Should -BeNullOrEmpty
    }

    It 'Returns $null when eval-results.md is missing' {
        $dir = Join-Path $TestDrive 'no-md'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Get-InvariantFailureCount -RunDir $dir | Should -BeNullOrEmpty
    }

    It 'Returns $null when the markdown table has no data rows' {
        $dir = Join-Path $TestDrive 'empty-table'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $md = Join-Path $dir 'eval-results.md'
        Set-Content -LiteralPath $md -Value @($script:Header, $script:Sep) -Encoding utf8NoBOM
        Get-InvariantFailureCount -RunDir $dir | Should -BeNullOrEmpty
    }

    It 'Returns the failed-stimulus count parsed from eval-results.md' {
        $dir = Join-Path $TestDrive 'with-failures'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $md = Join-Path $dir 'eval-results.md'
        $lines = @(
            $script:Header,
            $script:Sep,
            "| s1 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |",
            "| s2 | g | 0%   | 0.00 | 0.00 | 1s | 10 | $script:Fail |",
            "| s3 | g | 60%  | 0.60 | 0.30 | 1s | 10 | $script:Warn |"
        )
        Set-Content -LiteralPath $md -Value $lines -Encoding utf8NoBOM
        Get-InvariantFailureCount -RunDir $dir | Should -Be 2
    }

    It 'Returns 0 when all stimuli pass' {
        $dir = Join-Path $TestDrive 'all-pass'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $md = Join-Path $dir 'eval-results.md'
        $lines = @(
            $script:Header,
            $script:Sep,
            "| s1 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |",
            "| s2 | g | 100% | 1.00 | 1.00 | 1s | 10 | $script:Pass |"
        )
        Set-Content -LiteralPath $md -Value $lines -Encoding utf8NoBOM
        Get-InvariantFailureCount -RunDir $dir | Should -Be 0
    }
}
