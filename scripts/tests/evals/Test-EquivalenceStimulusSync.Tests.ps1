#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../../evals/Test-EvalSpec.ps1')).Path

    if (-not (Get-Module -ListAvailable -Name 'powershell-yaml')) {
        throw "Pester suite requires 'powershell-yaml'. Install via Install-Module powershell-yaml -Scope CurrentUser."
    }
    Import-Module powershell-yaml -ErrorAction Stop

    . $script:ScriptPath -SkipAgentCoverage *> $null

    function New-EquivalenceFixture {
        <#
        .SYNOPSIS
            Writes a canonical stimulus library and its two executable specs into a
            temporary root, applying optional per-file mutations.
        #>
        param(
            [Parameter(Mandatory = $true)][string]$Root,
            [Parameter(Mandatory = $false)][scriptblock]$Mutate
        )

        $canonical = @{
            name    = 'fixture-stimuli'
            stimuli = @(
                @{
                    name       = 'shared-basic'
                    prompt     = 'What is 2 + 2?'
                    invariants = @('answers-four')
                    tags       = @{ category = 'baseline-equivalence'; subcategory = 'factual-recall'; policy = 'equivalent' }
                    graders    = @(
                        @{ type = 'output-matches'; name = 'answers-four'; config = @{ pattern = '4' } }
                        @{ type = 'prompt'; name = 'response-quality'; config = @{ prompt = 'Correct?' } }
                    )
                },
                @{
                    # customized_disallow forbids persona bleed, so this stimulus asserts
                    # sameness and stays in the equivalence denominator.
                    name                = 'bleed-guarded'
                    prompt              = 'Tell me a short joke.'
                    invariants          = @('non-empty')
                    customized_disallow = @('agent-self-reference')
                    tags                = @{ category = 'baseline-equivalence'; subcategory = 'instruction-bleed'; policy = 'equivalent' }
                    graders             = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                    )
                },
                @{
                    # customized_required documents behavior expected only in the
                    # customized run, so this stimulus is excluded from equivalence.
                    name                = 'true-divergence'
                    prompt              = 'Edit the README.'
                    invariants          = @('non-empty')
                    customized_required = @('routes-through-lifecycle')
                    tags                = @{ category = 'baseline-equivalence'; subcategory = 'customization-boundary'; policy = 'documented-divergence' }
                    graders             = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                    )
                }
            )
        }

        $baseline = @{
            name    = 'fixture-baseline'
            type    = 'capability'
            stimuli = @(
                @{
                    name    = 'shared-basic'
                    prompt  = 'What is 2 + 2?'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'factual-recall'; policy = 'equivalent' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'answers-four'; config = @{ pattern = '4' } }
                        @{ type = 'prompt'; name = 'response-quality'; config = @{ prompt = 'Correct?' } }
                    )
                },
                @{
                    name    = 'bleed-guarded'
                    prompt  = 'Tell me a short joke.'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'instruction-bleed'; policy = 'equivalent' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                    )
                },
                @{
                    name    = 'true-divergence'
                    prompt  = 'Edit the README.'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'customization-boundary'; policy = 'documented-divergence' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                    )
                }
            )
        }

        $customized = @{
            name    = 'fixture-customized'
            type    = 'capability'
            stimuli = @(
                @{
                    name    = 'shared-basic'
                    prompt  = 'What is 2 + 2?'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'factual-recall'; policy = 'equivalent' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'answers-four'; config = @{ pattern = '4' } }
                        @{ type = 'prompt'; name = 'response-quality'; config = @{ prompt = 'Correct?' } }
                    )
                },
                @{
                    name    = 'bleed-guarded'
                    prompt  = 'Tell me a short joke.'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'instruction-bleed'; policy = 'equivalent' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                        @{ type = 'output-matches'; name = 'agent-self-reference'; config = @{ pattern = 'agent' } }
                    )
                },
                @{
                    name    = 'true-divergence'
                    prompt  = 'Edit the README.'
                    tags    = @{ category = 'baseline-equivalence'; subcategory = 'customization-boundary'; policy = 'documented-divergence' }
                    graders = @(
                        @{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } }
                        @{ type = 'output-matches'; name = 'routes-through-lifecycle'; config = @{ pattern = 'lifecycle' } }
                    )
                }
            )
        }

        $bag = @{ Canonical = $canonical; Baseline = $baseline; Customized = $customized }
        if ($Mutate) { & $Mutate $bag }

        $canonicalDir = Join-Path $Root 'evals/baseline-equivalence'
        New-Item -ItemType Directory -Path (Join-Path $canonicalDir 'baseline') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $canonicalDir 'customized') -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $canonicalDir 'stimuli.yml') -Value (ConvertTo-Yaml $bag.Canonical) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $canonicalDir 'baseline/eval.yaml') -Value (ConvertTo-Yaml $bag.Baseline) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $canonicalDir 'customized/eval.yaml') -Value (ConvertTo-Yaml $bag.Customized) -Encoding UTF8
    }

    function Invoke-SyncCheck {
        param(
            [Parameter(Mandatory = $false)][scriptblock]$Mutate
        )
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-EquivalenceFixture -Root $root -Mutate $Mutate
            return Test-EquivalenceStimulusSync -RepoRoot $root
        }
        finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-EquivalenceStimulusSync' -Tag 'Unit' {
    Context 'Synchronized specs' {
        It 'Reports no violations when canonical and executable specs agree' {
            $result = Invoke-SyncCheck
            @($result.violations).Count | Should -Be 0
            $result.checkedCount | Should -Be 3
        }

        It 'Accepts a customized-only guard that canonical declares' {
            $result = Invoke-SyncCheck
            @($result.violations | Where-Object { $_.field -eq 'customized_disallow' }).Count | Should -Be 0
        }
    }

    Context 'Drift detection' {
        It 'Fails when a prompt differs from canonical' {
            $result = Invoke-SyncCheck -Mutate { param($b) $b.Customized.stimuli[0].prompt = 'What is 3 + 3?' }
            @($result.violations | Where-Object { $_.field -eq 'prompt' }).Count | Should -Be 1
        }

        It 'Fails when tags differ from canonical' {
            $result = Invoke-SyncCheck -Mutate { param($b) $b.Baseline.stimuli[0].tags.subcategory = 'drifted' }
            @($result.violations | Where-Object { $_.field -eq 'tags' }).Count | Should -Be 1
        }

        It 'Fails when a canonical grader is missing from an executable spec' {
            $result = Invoke-SyncCheck -Mutate { param($b) $b.Baseline.stimuli[0].graders = @($b.Baseline.stimuli[0].graders[0]) }
            @($result.violations | Where-Object { $_.field -eq 'graders' }).Count | Should -BeGreaterThan 0
        }

        It 'Fails when a stimulus is missing from an executable spec' {
            $result = Invoke-SyncCheck -Mutate { param($b) $b.Customized.stimuli = @($b.Customized.stimuli[0]) }
            @($result.violations | Where-Object { $_.field -eq 'name' }).Count | Should -BeGreaterThan 0
        }

        It 'Fails when an executable spec declares a stimulus absent from canonical' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Baseline.stimuli += @{
                    name    = 'unknown-stimulus'
                    prompt  = 'Unlisted.'
                    tags    = @{ category = 'baseline-equivalence' }
                    graders = @(@{ type = 'output-matches'; name = 'non-empty'; config = @{ pattern = '\S' } })
                }
            }
            @($result.violations | Where-Object { $_.stimulusName -eq 'unknown-stimulus' }).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Invariant and guard placement' {
        It 'Fails when an invariant is enforced only in the customized spec' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Canonical.stimuli[0].graders = @($b.Canonical.stimuli[0].graders[1])
                $b.Baseline.stimuli[0].graders = @($b.Baseline.stimuli[0].graders[1])
            }
            $invariantViolations = @($result.violations | Where-Object { $_.field -eq 'invariants' })
            $invariantViolations.Count | Should -BeGreaterThan 0
            $invariantViolations[0].message | Should -Match 'customized_required'
        }

        It 'Fails when a customized-only guard leaks into the baseline spec' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Baseline.stimuli[1].graders += @{ type = 'output-matches'; name = 'agent-self-reference'; config = @{ pattern = 'agent' } }
            }
            $guardViolations = @($result.violations | Where-Object { $_.field -eq 'customized_disallow' })
            $guardViolations.Count | Should -BeGreaterThan 0
            $guardViolations[0].message | Should -Match 'baseline'
        }

        It 'Fails when a declared guard has no matching customized grader' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Customized.stimuli[1].graders = @($b.Customized.stimuli[1].graders[0])
            }
            @($result.violations | Where-Object { $_.field -eq 'customized_disallow' }).Count | Should -BeGreaterThan 0
        }

        It 'Fails when the customized spec adds an undeclared grader' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Customized.stimuli[0].graders += @{ type = 'output-matches'; name = 'undeclared-guard'; config = @{ pattern = 'x' } }
            }
            $graderViolations = @($result.violations | Where-Object { $_.field -eq 'graders' })
            $graderViolations.Count | Should -BeGreaterThan 0
            $graderViolations[0].message | Should -Match 'undeclared-guard'
        }
    }

    Context 'Missing or unreadable inputs' {
        It 'Skips cleanly when no baseline-equivalence suite is present' {
            # An absent suite is not a broken suite. A repository or fixture root that
            # never had the suite must not fail validation.
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            try {
                $result = Test-EquivalenceStimulusSync -RepoRoot $root
                $result.suitePresent | Should -BeFalse
                @($result.violations).Count | Should -Be 0
                $result.checkedCount | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Reports a violation when the suite is only partially present' {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
            try {
                New-EquivalenceFixture -Root $root
                Remove-Item -LiteralPath (Join-Path $root 'evals/baseline-equivalence/baseline/eval.yaml') -Force
                $result = Test-EquivalenceStimulusSync -RepoRoot $root
                $result.suitePresent | Should -BeTrue
                @($result.violations).Count | Should -BeGreaterThan 0
                @($result.violations)[0].message | Should -Match 'partially present'
            }
            finally {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Comparison policy classification' {
        It 'Counts equivalent and documented-divergence stimuli separately' {
            $result = Invoke-SyncCheck
            $result.equivalent | Should -Be 2
            $result.divergence | Should -Be 1
        }

        It 'Keeps a customized_disallow stimulus in the equivalence denominator' {
            # A disallow guard forbids persona bleed, so it asserts sameness. Tagging it
            # documented-divergence would exempt the suite's strongest equivalence signal
            # from the tie ratio.
            $result = Invoke-SyncCheck
            @($result.violations).Count | Should -Be 0
            $result.equivalent | Should -Be 2
        }

        It 'Fails when a stimulus has no policy tag' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                foreach ($spec in @($b.Canonical, $b.Baseline, $b.Customized)) {
                    $spec.stimuli[0].tags.Remove('policy')
                }
            }
            $policyViolations = @($result.violations | Where-Object { $_.field -eq 'policy' })
            $policyViolations.Count | Should -Be 1
            $policyViolations[0].message | Should -Match 'exactly one comparison policy'
        }

        It 'Fails when a policy tag is unrecognized' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                foreach ($spec in @($b.Canonical, $b.Baseline, $b.Customized)) {
                    $spec.stimuli[0].tags.policy = 'mostly-equivalent'
                }
            }
            @($result.violations | Where-Object { $_.field -eq 'policy' }).Count | Should -Be 1
        }

        It 'Fails when documented-divergence is claimed without a customized_required guard' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                foreach ($spec in @($b.Canonical, $b.Baseline, $b.Customized)) {
                    $spec.stimuli[0].tags.policy = 'documented-divergence'
                }
            }
            $policyViolations = @($result.violations | Where-Object { $_.field -eq 'policy' })
            $policyViolations.Count | Should -Be 1
            $policyViolations[0].message | Should -Match 'without evidence'
        }

        It 'Fails when a customized_required stimulus is tagged equivalent' {
            $result = Invoke-SyncCheck -Mutate {
                param($b)
                foreach ($spec in @($b.Canonical, $b.Baseline, $b.Customized)) {
                    $spec.stimuli[2].tags.policy = 'equivalent'
                }
            }
            $policyViolations = @($result.violations | Where-Object { $_.field -eq 'policy' })
            $policyViolations.Count | Should -Be 1
            $policyViolations[0].message | Should -Match 'tie ratio'
        }
    }

    Context 'Repository specs' {
        It 'Reports no violations for the committed baseline-equivalence suite' {
            $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
            $result = Test-EquivalenceStimulusSync -RepoRoot $repoRoot
            $result.checkedCount | Should -Be 40
            $result.violations | Should -BeNullOrEmpty
        }

        It 'Classifies every committed stimulus into exactly one policy' {
            $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
            $result = Test-EquivalenceStimulusSync -RepoRoot $repoRoot
            ($result.equivalent + $result.divergence) | Should -Be 40
            $result.divergence | Should -Be 7
        }
    }

    Context 'Violation count reporting' {
        # Regression guard for a PowerShell counting hazard. A pipeline that yields
        # exactly one hashtable reports that hashtable's key count rather than 1
        # when .Count is read without an enclosing array subexpression, so a single
        # violation silently measures as 3. Callers that gate on the count must
        # therefore see an exact 1 here, not merely a truthy value.
        It 'Reports exactly one violation when a single field drifts' {
            $result = Invoke-SyncCheck -Mutate { param($b) $b.Customized.stimuli[0].prompt = 'What is 3 + 3?' }
            @($result.violations).Count | Should -Be 1
            @($result.violations)[0].field | Should -Be 'prompt'
        }

        It 'Reports a violation collection that measures correctly at every size' {
            $none = Invoke-SyncCheck
            $one = Invoke-SyncCheck -Mutate { param($b) $b.Customized.stimuli[0].prompt = 'drifted' }
            $two = Invoke-SyncCheck -Mutate {
                param($b)
                $b.Customized.stimuli[0].prompt = 'drifted'
                $b.Baseline.stimuli[0].prompt = 'drifted differently'
            }

            @($none.violations).Count | Should -Be 0
            @($one.violations).Count | Should -Be 1
            @($two.violations).Count | Should -Be 2
        }
    }
}
