#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../../evals/lib/EquivalenceParsing.psm1'
    Import-Module $script:ModulePath -Force
    $script:FixturesRoot = Join-Path $PSScriptRoot 'fixtures/equivalence'
}

Describe 'Measure-CompareTrials' -Tag 'Unit' {
    BeforeAll {
        $script:Lines = Get-Content -LiteralPath (Join-Path $script:FixturesRoot 'vally-compare.jsonl')
        $script:Tally = Measure-CompareTrials -Lines $script:Lines
    }

    It 'Counts the total number of non-errored trials' {
        $script:Tally.Total | Should -Be 4
    }

    It 'Counts ties' {
        $script:Tally.Ties | Should -Be 2
    }

    It 'Counts baseline wins' {
        $script:Tally.BaselineWins | Should -Be 1
    }

    It 'Counts treatment wins' {
        $script:Tally.TreatmentWins | Should -Be 1
    }

    It 'Groups results per stimulus' {
        $script:Tally.PerStimulus.Keys | Should -Contain 'test-stim-a'
        $script:Tally.PerStimulus.Keys | Should -Contain 'test-stim-b'
        $script:Tally.PerStimulus['test-stim-a'].Ties | Should -Be 1
        $script:Tally.PerStimulus['test-stim-a'].BaselineWins | Should -Be 1
        $script:Tally.PerStimulus['test-stim-b'].TreatmentWins | Should -Be 1
    }

    It 'Excludes errored trials from the per-stimulus tally' {
        $script:Tally.PerStimulus['test-stim-a'].Ties | Should -Be 1
        $script:Tally.PerStimulus['test-stim-a'].BaselineWins | Should -Be 1
        $script:Tally.PerStimulus['test-stim-a'].TreatmentWins | Should -Be 0
    }

    It 'Carries the summary mean score and confidence interval' {
        $script:Tally.MeanScore | Should -Be 0.0
        $script:Tally.CiLow | Should -Be -0.3
        $script:Tally.CiHigh | Should -Be 0.3
    }

    It 'Carries the summary win rate' {
        $script:Tally.WinRate | Should -Be 0.25
    }

    It 'Reports a summary count for records carrying confidence-interval statistics' {
        $script:Tally.SummaryCount | Should -Be 1
    }

    It 'Reports zero summary count when a comparison record carries trials but no summary' {
        $record = '{"type":"comparison","stimuli":[{"stimulusName":"test-stim-a","trials":[{"trialIndex":0,"winner":"baseline"},{"trialIndex":1,"winner":"treatment"}]}]}'
        $result = Measure-CompareTrials -Lines @($record)
        $result.Total | Should -Be 2
        $result.SummaryCount | Should -Be 0
        $result.CiLow | Should -Be 0.0
        $result.CiHigh | Should -Be 0.0
    }

    It 'Excludes trials with an unrecognized winner from the total tally' {
        $record = '{"type":"comparison","stimuli":[{"stimulusName":"test-stim-a","trials":[{"trialIndex":0,"winner":"tie"},{"trialIndex":1,"winner":"unknown"}]}]}'
        $result = Measure-CompareTrials -Lines @($record)
        $result.Total | Should -Be 1
        $result.Ties | Should -Be 1
    }

    It 'Ignores non-JSON and non-comparison lines' {
        $result = Measure-CompareTrials -Lines @('not json', '{"type":"other"}')
        $result.Total | Should -Be 0
        $result.MeanScore | Should -Be 0.0
    }

    It 'Returns zeros for empty input' {
        $empty = Measure-CompareTrials -Lines @()
        $empty.Total | Should -Be 0
        $empty.Ties | Should -Be 0
        $empty.MeanScore | Should -Be 0.0
        $empty.CiLow | Should -Be 0.0
        $empty.CiHigh | Should -Be 0.0
        $empty.SummaryCount | Should -Be 0
    }

    It 'Returns zeros for null input from an empty file read' {
        $empty = Measure-CompareTrials -Lines $null
        $empty.Total | Should -Be 0
        $empty.SummaryCount | Should -Be 0
    }

    It 'Handles absent optional comparison properties under strict mode' {
        $record = '{"type":"comparison","stimuli":[{}, {"stimulusName":"test-stim","trials":[{}]}],"summary":{}}'
        { Measure-CompareTrials -Lines @($record) } | Should -Not -Throw
        $result = Measure-CompareTrials -Lines @($record)
        $result.Total | Should -Be 0
        $result.SummaryCount | Should -Be 0
    }

    It 'Combines confidence intervals across multiple comparison records' {
        $records = @(
            '{"type":"comparison","summary":{"meanScore":-0.1,"ciLow":-0.4,"ciHigh":0.2,"winRate":0.4}}',
            '{"type":"comparison","summary":{"meanScore":0.1,"ciLow":-0.1,"ciHigh":0.5,"winRate":0.6}}'
        )
        $result = Measure-CompareTrials -Lines $records
        $result.SummaryCount | Should -Be 2
        $result.MeanScore | Should -Be 0.0
        $result.WinRate | Should -Be 0.5
        $result.CiLow | Should -Be -0.1
        $result.CiHigh | Should -Be 0.2
    }

    It 'Excludes incomplete confidence intervals from aggregate bounds' {
        $records = @(
            '{"type":"comparison","summary":{"ciLow":0.9}}',
            '{"type":"comparison","summary":{"ciLow":-0.3,"ciHigh":0.4}}'
        )
        $result = Measure-CompareTrials -Lines $records
        $result.SummaryCount | Should -Be 1
        $result.CiLow | Should -Be -0.3
        $result.CiHigh | Should -Be 0.4
    }
}

Describe 'Measure-CompareTrials against captured Vally 0.10 output' -Tag 'Unit' {
    # Fixture provenance: captured from Vally CLI 0.10.0 by running two temporary
    # eval specs (benign arithmetic and geography prompts, executor copilot-sdk,
    # model gpt-5.6-luna) and comparing the two run directories with
    # `vally compare --baseline <dir> --treatment <dir> --judge-model claude-haiku-4.5`.
    # Judge and grader rationale text was replaced during sanitization; every
    # structural field the parser reads is preserved verbatim.
    #
    # Capture limitation: the temporary specs lived outside the `paths.evals`
    # root configured in .vally.yaml. These fixtures are evidence of record shape
    # only, not of eval-spec path or skill-resolution behavior.
    BeforeAll {
        $script:V010Lines = @(Get-Content -LiteralPath (Join-Path $script:FixturesRoot 'vally-0.10-comparison.jsonl'))
        $script:V010Tally = Measure-CompareTrials -Lines $script:V010Lines
        $script:V010Record = $script:V010Lines[0] | ConvertFrom-Json -Depth 100
    }

    It 'Parses the 0.10 comparison record without contract changes' {
        $script:V010Tally.Total | Should -Be 2
        $script:V010Tally.Ties | Should -Be 2
        $script:V010Tally.BaselineWins | Should -Be 0
        $script:V010Tally.TreatmentWins | Should -Be 0
    }

    It 'Consumes native 0.10 summary statistics' {
        $script:V010Tally.SummaryCount | Should -Be 1
        $script:V010Tally.MeanScore | Should -Be 0.0
        $script:V010Tally.WinRate | Should -Be 0.0
        $script:V010Tally.CiLow | Should -Be 0.0
        $script:V010Tally.CiHigh | Should -Be 0.0
    }

    It 'Groups 0.10 trials per stimulus' {
        $script:V010Tally.PerStimulus.Keys | Should -Contain 'smoke-arithmetic'
        $script:V010Tally.PerStimulus.Keys | Should -Contain 'smoke-capital'
    }

    It 'Retains the 0.10 unmatched arrays that the tally does not currently count' {
        # Documents a known gap: unmatched trajectories never reach the tally, so
        # Total reflects only matched pairs. Policy work in a later phase makes
        # these counts observable rather than silent.
        @($script:V010Record.unmatchedBaseline).Count | Should -Be 1
        @($script:V010Record.unmatchedTreatment).Count | Should -Be 1
        $script:V010Tally.Total | Should -Be 2
    }

    It 'Counts the unmatched trajectories as data-quality signals' {
        # The counterpart to the assertion above. Total still reflects matched pairs
        # only, but the unmatched trajectories are now reported instead of vanishing,
        # so an incomplete comparison cannot present itself as a complete one.
        $script:V010Tally.UnmatchedBaseline | Should -Be 1
        $script:V010Tally.UnmatchedTreatment | Should -Be 1
    }

    It 'Exposes the 0.10 summary fields the reporting contract depends on' {
        $summary = $script:V010Record.summary
        $summary.trialCount | Should -Be 2
        $summary.erroredCount | Should -Be 0
        $summary.PSObject.Properties.Name | Should -Contain 'wins'
        $summary.PSObject.Properties.Name | Should -Contain 'losses'
        $summary.PSObject.Properties.Name | Should -Contain 'mcnemar'
        $summary.PSObject.Properties.Name | Should -Contain 'metricDeltas'
    }
}

Describe 'Measure-CompareTrials data-quality accounting' -Tag 'Unit' {
    Context 'Judge errors' {
        It 'Counts an errored trial instead of skipping it silently' {
            # Previously a bare continue dropped these, so a run whose comparisons
            # mostly errored could report a healthy tie ratio from the survivors.
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"winner":"tie"},{"trialIndex":1,"errored":true}]}]}'
            $result = Measure-CompareTrials -Lines @($record)
            $result.Total | Should -Be 1
            $result.JudgeErrors | Should -Be 1
        }

        It 'Computes the error rate against every attempted trial' {
            # The denominator must include the failures, or the rate shrinks as the
            # failures it measures increase.
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"winner":"tie"},{"trialIndex":1,"errored":true},{"trialIndex":2,"errored":true}]}]}'
            $result = Measure-CompareTrials -Lines @($record)
            $result.JudgeErrors | Should -Be 2
            $result.JudgeErrorRate | Should -Be ([math]::Round(2 / 3, 6))
        }

        It 'Reports a zero error rate when nothing errored' {
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"winner":"tie"}]}]}'
            (Measure-CompareTrials -Lines @($record)).JudgeErrorRate | Should -Be 0.0
        }

        It 'Attributes judge errors to their stimulus' {
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"errored":true}]}]}'
            (Measure-CompareTrials -Lines @($record)).PerStimulus['s'].JudgeErrors | Should -Be 1
        }
    }

    Context 'Structural violations' {
        It 'Counts a malformed line rather than ignoring it' {
            $result = Measure-CompareTrials -Lines @('{not valid json', '{"type":"comparison","summary":{}}')
            $result.MalformedRecords | Should -Be 1
        }

        It 'Counts an unrecognized winner as malformed' {
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"winner":"maybe"}]}]}'
            $result = Measure-CompareTrials -Lines @($record)
            $result.Total | Should -Be 0
            $result.MalformedRecords | Should -Be 1
        }

        It 'Counts unmatched trajectories on both sides' {
            $record = '{"type":"comparison","stimuli":[],"unmatchedBaseline":["a (trial 0)","b (trial 0)"],"unmatchedTreatment":["c (trial 0)"]}'
            $result = Measure-CompareTrials -Lines @($record)
            $result.UnmatchedBaseline | Should -Be 2
            $result.UnmatchedTreatment | Should -Be 1
        }

        It 'Counts a duplicate trial index' {
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"winner":"tie"},{"trialIndex":0,"winner":"tie"}]}]}'
            (Measure-CompareTrials -Lines @($record)).DuplicateTrials | Should -Be 1
        }

        It 'Records a diagnostic for each violation' {
            $record = '{"type":"comparison","stimuli":[{"stimulusName":"s","trials":[{"trialIndex":0,"errored":true}]}],"unmatchedBaseline":["x (trial 0)"]}'
            $result = Measure-CompareTrials -Lines @($record)
            @($result.Diagnostics).Count | Should -BeGreaterThan 1
            ($result.Diagnostics -join ' ') | Should -Match 'Judge error'
            ($result.Diagnostics -join ' ') | Should -Match 'Unmatched baseline'
        }

        It 'Counts comparison records so a missing pair is detectable' {
            $result = Measure-CompareTrials -Lines @('{"type":"comparison","summary":{}}')
            $result.ComparisonRecords | Should -Be 1
        }
    }

    Context 'Comparison policy denominator' {
        BeforeAll {
            $script:PolicyMap = @{ 'equal-one' = 'equivalent'; 'equal-two' = 'equivalent'; 'diverges' = 'documented-divergence' }
            $script:PolicyRecord = '{"type":"comparison","stimuli":[' +
                '{"stimulusName":"equal-one","trials":[{"trialIndex":0,"winner":"tie"}]},' +
                '{"stimulusName":"equal-two","trials":[{"trialIndex":0,"winner":"treatment"}]},' +
                '{"stimulusName":"diverges","trials":[{"trialIndex":0,"winner":"treatment"}]}]}'
        }

        It 'Excludes documented-divergence stimuli from the equivalence denominator' {
            # A stimulus expected to differ must not count against equivalence, which
            # is the scoring defect the policy tag exists to fix.
            $result = Measure-CompareTrials -Lines @($script:PolicyRecord) -StimulusPolicy $script:PolicyMap
            $result.EquivalentTotal | Should -Be 2
            $result.DivergenceTotal | Should -Be 1
        }

        It 'Computes the tie ratio over equivalent stimuli only' {
            $result = Measure-CompareTrials -Lines @($script:PolicyRecord) -StimulusPolicy $script:PolicyMap
            $result.TieRatio | Should -Be 0.5
        }

        It 'Still counts every trial in the overall total' {
            $result = Measure-CompareTrials -Lines @($script:PolicyRecord) -StimulusPolicy $script:PolicyMap
            $result.Total | Should -Be 3
        }

        It 'Treats all stimuli as equivalent when no policy map is supplied' {
            $result = Measure-CompareTrials -Lines @($script:PolicyRecord)
            $result.EquivalentTotal | Should -Be 3
            $result.DivergenceTotal | Should -Be 0
        }
    }
}

Describe 'Measure-DeclaredInvariantFailures' -Tag 'Unit' {
    BeforeAll {
        function New-RunFixture {
            param(
                [Parameter(Mandatory = $true)][string]$Root,
                [Parameter(Mandatory = $true)][string[]]$Lines
            )
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Root 'results.jsonl') -Value $Lines -Encoding UTF8
        }

        $script:PassLine = '{"gradeResult":{"stimulusName":"s","details":[{"name":"answers-four","kind":"code","passed":true},{"name":"response-quality","kind":"llm","passed":true}]}}'
        $script:JudgeFailLine = '{"gradeResult":{"stimulusName":"s","details":[{"name":"answers-four","kind":"code","passed":true},{"name":"response-quality","kind":"llm","passed":false}]}}'
        $script:InvariantFailLine = '{"gradeResult":{"stimulusName":"s","details":[{"name":"answers-four","kind":"code","passed":false}]}}'
    }

    It 'Reports no signal when the run directory is missing' {
        # Previously indistinguishable from zero failures, which let a run that never
        # produced a report read as clean.
        $result = Measure-DeclaredInvariantFailures -RunDir (Join-Path ([System.IO.Path]::GetTempPath()) 'absent-run')
        $result.HasSignal | Should -BeFalse
        $result.Failed | Should -Be 0
    }

    It 'Reports no signal when results.jsonl is absent' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        try {
            (Measure-DeclaredInvariantFailures -RunDir $root).HasSignal | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Reports signal with zero failures for a clean run' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @($script:PassLine)
            $result = Measure-DeclaredInvariantFailures -RunDir $root -InvariantNames @('answers-four')
            $result.HasSignal | Should -BeTrue
            $result.Failed | Should -Be 0
            $result.Evaluated | Should -Be 1
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Counts a failing declared invariant' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @($script:InvariantFailLine)
            $result = Measure-DeclaredInvariantFailures -RunDir $root -InvariantNames @('answers-four')
            $result.Failed | Should -Be 1
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Ignores a failing LLM quality judge when invariants are declared' {
        # The strict half of the verdict must stay deterministic. A subjective miss on
        # a benign prompt previously failed the entire run.
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @($script:JudgeFailLine)
            $result = Measure-DeclaredInvariantFailures -RunDir $root -InvariantNames @('answers-four')
            $result.HasSignal | Should -BeTrue
            $result.Failed | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Falls back to deterministic graders when no invariants are declared' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @($script:JudgeFailLine)
            $result = Measure-DeclaredInvariantFailures -RunDir $root
            $result.Evaluated | Should -Be 1
            $result.Failed | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Reports no signal when a declared invariant never appears' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @($script:PassLine)
            (Measure-DeclaredInvariantFailures -RunDir $root -InvariantNames @('never-present')).HasSignal | Should -BeFalse
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Tolerates a malformed line without losing the rest of the run' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        try {
            New-RunFixture -Root $root -Lines @('{broken', $script:InvariantFailLine)
            $result = Measure-DeclaredInvariantFailures -RunDir $root -InvariantNames @('answers-four')
            $result.HasSignal | Should -BeTrue
            $result.Failed | Should -Be 1
            ($result.Diagnostics -join ' ') | Should -Match 'Malformed'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Measure-InvariantFailures' -Tag 'Unit' {
    BeforeAll {
        $script:Pass = [char]::ConvertFromUtf32(0x2705)
        $script:Fail = [char]::ConvertFromUtf32(0x274C)
        $script:Lines = @(
            '| invariant | detail | verdict |',
            '| --- | --- | --- |',
            "| no-secrets-leaked | passed | $script:Pass |",
            "| no-pii-emitted | failed | $script:Fail |"
        )
        $script:Inv = Measure-InvariantFailures -Lines $script:Lines
    }

    It 'Counts every invariant row' {
        $script:Inv.Total | Should -Be 2
    }

    It 'Counts non-pass rows as failures' {
        $script:Inv.Failed | Should -Be 1
    }

    It 'Returns zeros for empty input' {
        $empty = Measure-InvariantFailures -Lines @()
        $empty.Total | Should -Be 0
        $empty.Failed | Should -Be 0
    }
}

Describe 'Get-EquivalenceGateResults' -Tag 'Unit' {
    BeforeAll {
        # Most cases assert the equivalence gate, so supply a healthy divergence signal
        # by default. Without it every case would fail on the divergence gate instead,
        # which would hide whatever the case is actually testing.
        $script:Healthy = @{ DivergenceHasSignal = $true; DivergenceGuardFailures = 0 }
    }

    It 'Returns fail when there are zero runs' {
        (Get-EquivalenceGateResults -Runs 0 -CiLow 0 -CiHigh 0 -InvariantFailures 0 -Tier 'pr' @script:Healthy).EquivalenceGate | Should -Be 'fail'
    }

    It 'Returns fail for a zero-run nightly evaluation' {
        (Get-EquivalenceGateResults -Runs 0 -CiLow 0 -CiHigh 0 -InvariantFailures 0 -Tier 'nightly' @script:Healthy).EquivalenceGate | Should -Be 'fail'
    }

    It 'Returns pass when the 95% confidence interval straddles zero' {
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 0 -Tier 'pr' @script:Healthy
        $r.EquivalenceGate | Should -Be 'pass'
        $r.Verdict | Should -Be 'pass'
    }

    It 'Returns warn on PR when invariants fail' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 1 -Tier 'pr' @script:Healthy).EquivalenceGate | Should -Be 'warn'
    }

    It 'Returns fail on nightly when invariants fail' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 1 -Tier 'nightly' @script:Healthy).EquivalenceGate | Should -Be 'fail'
    }

    It 'Returns warn on PR when the confidence interval excludes zero on the negative side (regression)' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow -0.6 -CiHigh -0.1 -InvariantFailures 0 -Tier 'pr' @script:Healthy).EquivalenceGate | Should -Be 'warn'
    }

    It 'Returns fail on nightly when the confidence interval excludes zero on the negative side (regression)' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow -0.6 -CiHigh -0.1 -InvariantFailures 0 -Tier 'nightly' @script:Healthy).EquivalenceGate | Should -Be 'fail'
    }

    It 'Returns warn on PR when the confidence interval excludes zero on the positive side (unexpected improvement)' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow 0.1 -CiHigh 0.6 -InvariantFailures 0 -Tier 'pr' @script:Healthy).EquivalenceGate | Should -Be 'warn'
    }

    It 'Returns fail on nightly when the confidence interval excludes zero on the positive side (unexpected improvement)' {
        (Get-EquivalenceGateResults -Runs 10 -CiLow 0.1 -CiHigh 0.6 -InvariantFailures 0 -Tier 'nightly' @script:Healthy).EquivalenceGate | Should -Be 'fail'
    }

    It 'Fails a data-quality violation closed even on the advisory tier' {
        # An incomplete comparison cannot evidence equivalence at any tier. Only a
        # statistical or guard result is advisory.
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 0 -DataQualityViolations 3 -Tier 'pr' @script:Healthy
        $r.EquivalenceGate | Should -Be 'fail'
        $r.Verdict | Should -Be 'fail'
    }

    It 'Fails the divergence gate when a declared guard fails' {
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 0 -Tier 'nightly' -DivergenceHasSignal $true -DivergenceGuardFailures 1
        $r.DocumentedDivergenceGate | Should -Be 'fail'
        $r.EquivalenceGate | Should -Be 'pass'
        $r.Verdict | Should -Be 'fail'
    }

    It 'Fails the divergence gate when the customized run produced no guard signal' {
        # No signal is not conformance. Treating an absent result as a pass is the
        # defect that made the retired signature subsystem look healthy for months.
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 0 -Tier 'nightly' -DivergenceHasSignal $false
        $r.DocumentedDivergenceGate | Should -Be 'fail'
        $r.Verdict | Should -Be 'fail'
    }

    It 'Downgrades a failing divergence gate to warn on the advisory tier' {
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow -0.2 -CiHigh 0.2 -InvariantFailures 0 -Tier 'pr' -DivergenceHasSignal $true -DivergenceGuardFailures 2
        $r.DocumentedDivergenceGate | Should -Be 'warn'
        $r.Verdict | Should -Be 'warn'
    }

    It 'Reports the two gates independently' {
        $r = Get-EquivalenceGateResults -Runs 10 -CiLow 0.1 -CiHigh 0.6 -InvariantFailures 0 -Tier 'nightly' @script:Healthy
        $r.EquivalenceGate | Should -Be 'fail'
        $r.DocumentedDivergenceGate | Should -Be 'pass'
    }
}

Describe 'ConvertFrom-EquivalenceResults' -Tag 'Unit' {
    BeforeAll {
        $script:Records = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'baseline') -WarningAction SilentlyContinue
    }

    It 'Loads one record per JSONL line' {
        $script:Records.Count | Should -Be 2
    }

    It 'Extracts the stimulus name' {
        @($script:Records | Where-Object { $_.stimulusName -eq 'test-stim-a' }).Count | Should -Be 1
    }

    It 'Numbers trials per stimulus starting at zero' {
        ($script:Records | Where-Object { $_.stimulusName -eq 'test-stim-a' }).trial | Should -Be 0
    }

    It 'Computes a deterministic output hash' {
        $a = ($script:Records | Where-Object { $_.stimulusName -eq 'test-stim-a' })[0]
        $a.outputHash | Should -Match '^[0-9a-f]{64}$'
    }

    It 'Captures metrics' {
        $a = ($script:Records | Where-Object { $_.stimulusName -eq 'test-stim-a' })[0]
        $a.wallTimeMs | Should -Be 100
        $a.totalTokens | Should -Be 50
    }

    It 'Buckets known grader kinds' {
        $a = ($script:Records | Where-Object { $_.stimulusName -eq 'test-stim-a' })[0]
        $a.details.code.Count | Should -Be 1
        $a.details.llm.Count | Should -Be 1
    }

    It 'Buckets unknown grader kinds under other and warns' {
        $warnings = $null
        $records = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'baseline') -WarningVariable warnings -WarningAction SilentlyContinue
        $b = ($records | Where-Object { $_.stimulusName -eq 'test-stim-b' })[0]
        $b.details.other.Count | Should -Be 1
        $warnings | Where-Object { $_ -match 'weirdkind' } | Should -Not -BeNullOrEmpty
    }

    It 'Throws when the run directory does not exist' {
        { ConvertFrom-EquivalenceResults -RunDir (Join-Path $TestDrive 'missing') } | Should -Throw
    }

    It 'Throws when no results.jsonl files exist under the run directory' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        { ConvertFrom-EquivalenceResults -RunDir $empty } | Should -Throw
    }
}

Describe 'Merge-EquivalenceStimuli' -Tag 'Unit' {
    BeforeAll {
        $script:Baseline = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'baseline') -WarningAction SilentlyContinue
        $script:Customized = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'customized') -WarningAction SilentlyContinue
        $script:Compare = Measure-CompareTrials -Lines (Get-Content -LiteralPath (Join-Path $script:FixturesRoot 'vally-compare.jsonl'))
        $script:Merged = Merge-EquivalenceStimuli -Baseline $script:Baseline -Customized $script:Customized -Compare $script:Compare
    }

    It 'Produces one row per stimulus' {
        $script:Merged.Count | Should -Be 2
    }

    It 'Counts identical outputs by hash' {
        $a = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-a' }
        $a.identicalCount | Should -Be 1
        $a.identicalTotal | Should -Be 1
        $b = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-b' }
        $b.identicalCount | Should -Be 0
        $b.identicalTotal | Should -Be 1
    }

    It 'Computes pass rates for each side' {
        $a = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-a' }
        $a.baselinePassRate | Should -Be 1.0
        $a.customizedPassRate | Should -Be 1.0
        $b = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-b' }
        $b.baselinePassRate | Should -Be 1.0
        $b.customizedPassRate | Should -Be 0.0
    }

    It 'Computes mean wall-time and token deltas' {
        $a = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-a' }
        $a.meanWallTimeDeltaMs | Should -Be 20
        $a.meanTokenDelta | Should -Be 5
    }

    It 'Carries per-stimulus compare tallies through' {
        $a = $script:Merged | Where-Object { $_.stimulusName -eq 'test-stim-a' }
        $a.ties | Should -Be 1
        $a.baselineWins | Should -Be 1
        $a.treatmentWins | Should -Be 0
    }

    It 'Handles missing-side stimuli with zero pass rate' {
        $bOnly = [pscustomobject]@{
            stimulusName = 'lonely'
            trial        = 0
            output       = 'x'
            outputHash   = 'h'
            passed       = $true
            score        = 1
            wallTimeMs   = 1
            totalTokens  = 1
            details      = @{ code = @(); llm = @(); human = @(); other = @() }
        }
        $merged = Merge-EquivalenceStimuli -Baseline @($bOnly) -Customized @() -Compare @{ PerStimulus = @{} }
        ($merged | Where-Object { $_.stimulusName -eq 'lonely' }).customizedPassRate | Should -Be 0
    }
}

Describe 'Edit-HtmlEscape' -Tag 'Unit' {
    It 'Escapes ampersands first' {
        Edit-HtmlEscape '&' | Should -Be '&amp;'
    }

    It 'Escapes angle brackets' {
        Edit-HtmlEscape '<x>' | Should -Be '&lt;x&gt;'
    }

    It 'Escapes double quotes' {
        Edit-HtmlEscape '"x"' | Should -Be '&quot;x&quot;'
    }

    It "Escapes apostrophes" {
        Edit-HtmlEscape "it's" | Should -Be 'it&#39;s'
    }

    It 'Returns empty string for null input' {
        Edit-HtmlEscape $null | Should -Be ''
    }

    It 'Returns empty string for empty input' {
        Edit-HtmlEscape '' | Should -Be ''
    }

    It 'Passes through text with no special characters unchanged' {
        Edit-HtmlEscape 'plain text 123' | Should -Be 'plain text 123'
    }

    It 'Escapes ampersand before other entities so injected entities are double-escaped' {
        Edit-HtmlEscape '&lt;' | Should -Be '&amp;lt;'
    }

    It 'Escapes every special character in a combined payload' {
        Edit-HtmlEscape '<a href="x">it''s & co</a>' |
            Should -Be '&lt;a href=&quot;x&quot;&gt;it&#39;s &amp; co&lt;/a&gt;'
    }
}

Describe 'ConvertTo-EquivalenceHtml' -Tag 'Unit' {
    BeforeAll {
        $script:Baseline = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'baseline') -WarningAction SilentlyContinue
        $script:Customized = ConvertFrom-EquivalenceResults -RunDir (Join-Path $script:FixturesRoot 'customized') -WarningAction SilentlyContinue
        $script:Compare = Measure-CompareTrials -Lines (Get-Content -LiteralPath (Join-Path $script:FixturesRoot 'vally-compare.jsonl'))
        $script:Merged = Merge-EquivalenceStimuli -Baseline $script:Baseline -Customized $script:Customized -Compare $script:Compare
        $script:Html = ConvertTo-EquivalenceHtml -Stimuli $script:Merged -Model 'test-model' -RunId 'test-run-id' -Agent 'sample-agent'
    }

    It 'Includes the model and run id in escaped form' {
        $script:Html | Should -Match 'test-model'
        $script:Html | Should -Match 'test-run-id'
    }

    It 'Renders the Agent identity in the meta line' {
        $script:Html | Should -Match 'Agent: <strong>sample-agent</strong>'
        $script:Html | Should -Not -Match 'Subject: <strong>'
    }

    It 'Marks -Agent as a mandatory parameter' {
        $param = (Get-Command ConvertTo-EquivalenceHtml).Parameters['Agent']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Contain $true
    }

    It 'HTML-escapes the Agent value in the meta line' {
        $html = ConvertTo-EquivalenceHtml -Stimuli $script:Merged -Model 'm' -RunId 'r' -Agent '<x>'
        $html | Should -Match 'Agent: <strong>&lt;x&gt;</strong>'
        $html | Should -Not -Match 'Agent: <strong><x>'
    }

    It 'Embeds the run data inside a script tag' {
        $script:Html | Should -Match '<script id="data"'
    }

    It 'Does not reference any external http resources' {
        $script:Html | Should -Not -Match 'http://'
        $script:Html | Should -Not -Match 'https://'
    }

    It 'Escapes raw less-than from stimulus content' {
        $stim = [pscustomobject]@{
            stimulusName        = '<script>alert(1)</script>'
            baselineTrials      = 1
            customizedTrials    = 1
            baselinePassed      = 1
            customizedPassed    = 1
            baselinePassRate    = 1.0
            customizedPassRate  = 1.0
            identicalCount      = 1
            identicalTotal      = 1
            ties                = 1
            baselineWins        = 0
            treatmentWins       = 0
            meanWallTimeDeltaMs = 0
            meanTokenDelta      = 0
            trials              = @()
        }
        $html = ConvertTo-EquivalenceHtml -Stimuli @($stim) -Model '<m>' -RunId '<r>' -Agent 'agent-x'
        $html | Should -Match '&lt;m&gt;'
        $html | Should -Match '&lt;r&gt;'
        $html | Should -Not -Match '<script>alert\(1\)</script>'
    }

    It 'Neutralizes script-close sequences via JSON forward-slash escape (IV-001)' {
        $stim = [pscustomobject]@{
            stimulusName        = '</script><script>alert(1)</script>'
            baselineTrials      = 1
            customizedTrials    = 1
            baselinePassed      = 1
            customizedPassed    = 1
            baselinePassRate    = 1.0
            customizedPassRate  = 1.0
            identicalCount      = 1
            identicalTotal      = 1
            ties                = 1
            baselineWins        = 0
            treatmentWins       = 0
            meanWallTimeDeltaMs = 0
            meanTokenDelta      = 0
            trials              = @()
        }
        $html = ConvertTo-EquivalenceHtml -Stimuli @($stim) -Model 'm' -RunId 'r' -Agent 'agent-x'
        $html | Should -Not -Match '</script><script>alert'
        $html | Should -Match '\\u003c\\/script\\u003e'
    }

    It 'Renders custom variant labels, kinds, descriptions, and applied lists' {
        $stim = [pscustomobject]@{
            stimulusName        = 'simple-test'
            baselineTrials      = 1
            customizedTrials    = 1
            baselinePassed      = 1
            customizedPassed    = 1
            baselinePassRate    = 1.0
            customizedPassRate  = 1.0
            identicalCount      = 1
            identicalTotal      = 1
            ties                = 1
            baselineWins        = 0
            treatmentWins       = 0
            meanWallTimeDeltaMs = 0
            meanTokenDelta      = 0
            trials              = @()
        }
        $variants = @{
            a       = @{ kind = 'baseline'; name = 'empty'; label = 'Baseline-Custom'; description = 'desc-a'; applied = @('p1') }
            b       = @{ kind = 'prompt';   name = 'varB';  label = 'VarB-Custom';     description = 'desc-b'; applied = @('p2', 'p3') }
            subject = 'varB'
        }
        $html = ConvertTo-EquivalenceHtml -Stimuli @($stim) -Model 'm' -RunId 'r' -Agent 'agent-x' -Variants $variants
        $html | Should -Match 'Baseline-Custom'
        $html | Should -Match 'VarB-Custom'
        $html | Should -Match 'desc-a'
        $html | Should -Match 'desc-b'
        $html | Should -Match '<li>p1</li>'
        $html | Should -Match '<li>p2</li>'
        $html | Should -Match '<li>p3</li>'
        $html | Should -Match 'Baseline-Custom pass'
        $html | Should -Match 'VarB-Custom pass'
        $html | Should -Match 'Baseline-Custom wins'
        $html | Should -Match 'VarB-Custom wins'
        $html | Should -Not -Match 'Baseline \(A\)'
        $html | Should -Not -Match 'Customized \(B\)'
    }

    It 'Suppresses default variant labels when custom -Variants labels are supplied' {
        $stim = [pscustomobject]@{
            stimulusName        = 'simple-test'
            baselineTrials      = 1
            customizedTrials    = 1
            baselinePassed      = 1
            customizedPassed    = 1
            baselinePassRate    = 1.0
            customizedPassRate  = 1.0
            identicalCount      = 1
            identicalTotal      = 1
            ties                = 1
            baselineWins        = 0
            treatmentWins       = 0
            meanWallTimeDeltaMs = 0
            meanTokenDelta      = 0
            trials              = @()
        }
        $variants = @{
            a       = @{ kind = 'baseline'; name = 'one'; label = 'Side One'; description = 'd1'; applied = @() }
            b       = @{ kind = 'prompt';   name = 'two'; label = 'Side Two'; description = 'd2'; applied = @() }
            subject = 'two'
        }
        $html = ConvertTo-EquivalenceHtml -Stimuli @($stim) -Model 'm' -RunId 'r' -Agent 'agent-x' -Variants $variants
        $html | Should -Match 'Side One'
        $html | Should -Match 'Side Two'
        $html | Should -Not -Match 'Baseline \(A\)'
        $html | Should -Not -Match 'Customized \(B\)'
    }

    It 'Falls back to default variant labels when -Variants is omitted' {
        $stim = [pscustomobject]@{
            stimulusName        = 'simple-test'
            baselineTrials      = 1
            customizedTrials    = 1
            baselinePassed      = 1
            customizedPassed    = 1
            baselinePassRate    = 1.0
            customizedPassRate  = 1.0
            identicalCount      = 1
            identicalTotal      = 1
            ties                = 1
            baselineWins        = 0
            treatmentWins       = 0
            meanWallTimeDeltaMs = 0
            meanTokenDelta      = 0
            trials              = @()
        }
        $html = ConvertTo-EquivalenceHtml -Stimuli @($stim) -Model 'm' -RunId 'r' -Agent 'agent-x'
        $html | Should -Match 'Baseline \(A\)'
        $html | Should -Match 'Customized \(B\)'
    }
}

Describe 'Get-AppliedArtifacts' -Tag 'Unit' {
    BeforeAll {
        $script:WorkspaceRoot = Join-Path $TestDrive 'workspace'
        $script:Anchors = @(
            '.github/agents',
            '.github/skills/foo',
            '.github/skills/bar',
            '.github/instructions',
            '.github/prompts'
        )
        foreach ($a in $script:Anchors) {
            New-Item -ItemType Directory -Path (Join-Path $script:WorkspaceRoot $a) -Force | Out-Null
        }
        $script:SeededFiles = @(
            '.github/agents/example.agent.md',
            '.github/skills/foo/SKILL.md',
            '.github/skills/bar/SKILL.md',
            '.github/instructions/example.instructions.md',
            '.github/prompts/example.prompt.md'
        )
        foreach ($f in $script:SeededFiles) {
            Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot $f) -Value 'x' -Encoding utf8NoBOM
        }
        # README must not be enumerated.
        Set-Content -LiteralPath (Join-Path $script:WorkspaceRoot '.github/agents/README.md') -Value 'x' -Encoding utf8NoBOM

        $script:Result = Get-AppliedArtifacts -WorkspaceRoot $script:WorkspaceRoot
    }

    It 'Returns one entry per seeded artifact' {
        $script:Result.Count | Should -Be 5
    }

    It 'Includes every seeded artifact path' {
        foreach ($f in $script:SeededFiles) {
            $script:Result | Should -Contain $f
        }
    }

    It 'Retains distinct SKILL.md files in different subdirectories' {
        @($script:Result | Where-Object { $_ -like '*SKILL.md' }).Count | Should -Be 2
    }

    It 'Excludes README.md' {
        $script:Result | Should -Not -Contain '.github/agents/README.md'
    }

    It 'Returns results in sorted order' {
        $sorted = @($script:Result | Sort-Object)
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $script:Result[$i] | Should -Be $sorted[$i]
        }
    }

    It 'Uses forward slashes in every returned path' {
        foreach ($entry in $script:Result) {
            $entry | Should -Not -Match '\\'
        }
    }

    It 'Returns an empty array when the workspace path is missing' {
        $missing = Join-Path $TestDrive 'does-not-exist'
        $result = Get-AppliedArtifacts -WorkspaceRoot $missing
        @($result).Count | Should -Be 0
    }

    It 'Returns an empty array when the workspace path is empty string' {
        $result = Get-AppliedArtifacts -WorkspaceRoot ''
        @($result).Count | Should -Be 0
    }

    It 'Returns an empty array when no anchor directories exist' {
        $bareRoot = Join-Path $TestDrive 'bare'
        New-Item -ItemType Directory -Path $bareRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $bareRoot 'stray.md') -Value 'x' -Encoding utf8NoBOM
        $result = Get-AppliedArtifacts -WorkspaceRoot $bareRoot
        @($result).Count | Should -Be 0
    }
}

Describe 'Measure-DivergenceGuardResults' -Tag 'Unit' {
    BeforeAll {
        function New-GuardRun {
            <#
            .SYNOPSIS
                Writes a results.jsonl shaped like a customized run's grader output.
            #>
            param(
                [Parameter(Mandatory)][string]$Root,
                [Parameter(Mandatory)][array]$Details
            )
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            $record = @{
                type        = 'trial-result'
                gradeResult = @{
                    stimulusName = 'customization-boundary-write-tmp'
                    details      = $Details
                }
            }
            Set-Content -LiteralPath (Join-Path $Root 'results.jsonl') -Encoding utf8NoBOM `
                -Value ($record | ConvertTo-Json -Depth 10 -Compress)
        }

        $script:GuardNames = @('routes-through-rpi-lifecycle', 'scope-language')
    }

    It 'Reports no signal when the run directory is missing' {
        $r = Measure-DivergenceGuardResults -RunDir (Join-Path $TestDrive 'absent') -GuardNames $script:GuardNames
        $r.HasSignal | Should -BeFalse
        $r.Failed | Should -Be 0
    }

    It 'Reports no signal when no guards are declared' {
        # An empty declared set means the gate has nothing to assert. Returning a pass
        # would claim conformance the run never demonstrated.
        $root = Join-Path $TestDrive 'noguards'
        New-GuardRun -Root $root -Details @(@{ name = 'routes-through-rpi-lifecycle'; passed = $true; kind = 'code' })
        $r = Measure-DivergenceGuardResults -RunDir $root -GuardNames @()
        $r.HasSignal | Should -BeFalse
    }

    It 'Counts a failing declared guard' {
        $root = Join-Path $TestDrive 'failing'
        New-GuardRun -Root $root -Details @(
            @{ name = 'routes-through-rpi-lifecycle'; passed = $true; kind = 'code' },
            @{ name = 'scope-language'; passed = $false; kind = 'code' }
        )
        $r = Measure-DivergenceGuardResults -RunDir $root -GuardNames $script:GuardNames
        $r.HasSignal | Should -BeTrue
        $r.Evaluated | Should -Be 2
        $r.Failed | Should -Be 1
        $r.FailedGuards | Should -Contain 'customization-boundary-write-tmp/scope-language'
    }

    It 'Reports zero failures when every declared guard passes' {
        $root = Join-Path $TestDrive 'passing'
        New-GuardRun -Root $root -Details @(
            @{ name = 'routes-through-rpi-lifecycle'; passed = $true; kind = 'code' },
            @{ name = 'scope-language'; passed = $true; kind = 'code' }
        )
        $r = Measure-DivergenceGuardResults -RunDir $root -GuardNames $script:GuardNames
        $r.HasSignal | Should -BeTrue
        $r.Failed | Should -Be 0
        $r.Evaluated | Should -Be 2
    }

    It 'Ignores graders that are not declared guards' {
        # A failing response-quality judge must not reach the divergence gate, for the
        # same reason it was removed from the invariant tally.
        $root = Join-Path $TestDrive 'unrelated'
        New-GuardRun -Root $root -Details @(
            @{ name = 'scope-language'; passed = $true; kind = 'code' },
            @{ name = 'response-quality'; passed = $false; kind = 'prompt' }
        )
        $r = Measure-DivergenceGuardResults -RunDir $root -GuardNames $script:GuardNames
        $r.Failed | Should -Be 0
        $r.Evaluated | Should -Be 1
    }

    It 'Reports no signal when the run produced no declared guard results' {
        $root = Join-Path $TestDrive 'nosignal'
        New-GuardRun -Root $root -Details @(@{ name = 'response-quality'; passed = $true; kind = 'prompt' })
        $r = Measure-DivergenceGuardResults -RunDir $root -GuardNames $script:GuardNames
        $r.HasSignal | Should -BeFalse
    }
}
