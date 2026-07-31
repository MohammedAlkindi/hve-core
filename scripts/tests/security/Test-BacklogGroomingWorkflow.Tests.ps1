#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path

    function Read-RepoFile {
        param([Parameter(Mandatory)] [string]$Path)

        return Get-Content -LiteralPath (Join-Path $script:RepoRoot $Path) -Raw
    }

    function Select-GroomingCohort {
        param(
            [Parameter(Mandatory)] [object[]]$Issues,
            [Parameter(Mandatory)] [int]$PreviousCursor,
            [Parameter(Mandatory)] [datetime]$PreviousRun,
            [Parameter(Mandatory)] [int]$Capacity
        )

        $ordered = @($Issues | Where-Object { $_.State -eq 'open' -and -not $_.PullRequest } | Sort-Object Number)
        $priority = @($ordered | Where-Object { $_.UpdatedAt -gt $PreviousRun })
        $roundRobin = @($ordered | Where-Object Number -GT $PreviousCursor) +
            @($ordered | Where-Object Number -LE $PreviousCursor)
        $selected = [System.Collections.Generic.List[object]]::new()
        $selectedNumbers = [System.Collections.Generic.HashSet[int]]::new()
        $roundRobinNumbers = [System.Collections.Generic.List[int]]::new()

        foreach ($issue in @($priority) + @($roundRobin)) {
            if ($selected.Count -ge $Capacity) { break }
            if (-not $selectedNumbers.Add($issue.Number)) { continue }

            $selected.Add($issue)
            if ($priority.Number -notcontains $issue.Number) {
                $roundRobinNumbers.Add($issue.Number)
            }
        }

        $nextCursor = if ($roundRobinNumbers.Count -gt 0) {
            $roundRobinNumbers[-1]
        }
        else {
            $PreviousCursor
        }

        return @{
            Selected = @($selected)
            Priority = @($priority.Number | Where-Object { $selectedNumbers.Contains($_) })
            RoundRobin = @($roundRobinNumbers)
            NextCursor = $nextCursor
        }
    }

    function New-GroomingReport {
        param(
            [Parameter(Mandatory)] [hashtable]$Run,
            [Parameter(Mandatory)] [object[]]$Rows
        )

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('# Backlog Grooming Report')
        $lines.Add('')
        $lines.Add('| Run timestamp | Total open inventory | Assessed | Priority cohort | Round-robin cohort | Deferred | Stop reason | Next cursor |')
        $lines.Add('|---|---|---|---|---|---|---|---|')
        $lines.Add("| $($Run.Timestamp) | $($Run.Total) | $($Run.Assessed) | $($Run.Priority) | $($Run.RoundRobin) | $($Run.Deferred) | $($Run.StopReason) | $($Run.NextCursor) |")
        $lines.Add('')
        $lines.Add('| Issue | Title | Selection reason | Activity and ownership context | Similarity outcome | Grooming finding | Recommended next step | Assessment status |')
        $lines.Add('|---|---|---|---|---|---|---|---|')
        foreach ($row in $Rows) {
            $lines.Add("| #$($row.Number) | $($row.Title) | $($row.SelectionReason) | $($row.Context) | $($row.Similarity) | $($row.Finding) | $($row.NextStep) | $($row.Status) |")
        }

        return $lines -join "`n"
    }

    function Publish-GroomingReport {
        param(
            [Parameter(Mandatory)] [string]$Report,
            [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Issues,
            [Parameter(Mandatory)] [scriptblock]$CreateSink,
            [Parameter(Mandatory)] [scriptblock]$UpdateSink,
            [Parameter(Mandatory)] [scriptblock]$SummarySink,
            [Parameter(Mandatory)] [scriptblock]$FailureSink
        )

        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $sanitizedReport = $Report -replace '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', ''
        $sanitizedReport = $sanitizedReport -replace '@(?=[a-z\d](?:[a-z\d-]{0,38})(?![\w-]))', "@`u{200b}"
        if ($sanitizedReport.Length -lt 20 -or $sanitizedReport.Length -gt 65000) {
            throw "Report length $($sanitizedReport.Length) is outside the allowed range"
        }

        $trackers = @($Issues | Where-Object {
                -not $_.PullRequest -and $_.Body.Contains($marker)
            })
        if ($trackers.Count -gt 1) {
            & $FailureSink "Expected at most one marker-bearing tracker, found $($trackers.Count)"
            return
        }

        $body = "$marker`n`n$sanitizedReport"
        if ($trackers.Count -eq 0) {
            & $CreateSink 'Backlog grooming tracker' $body
        }
        else {
            & $UpdateSink $trackers[0].Number $body 'open'
        }
        & $SummarySink $sanitizedReport
    }

    $script:Source = Read-RepoFile '.github/workflows/backlog-groom.md'
    $script:Lock = Read-RepoFile '.github/workflows/backlog-groom.lock.yml'
    $script:Policy = Read-RepoFile '.github/instructions/github/github-backlog-grooming.instructions.md'
    $script:Agent = Read-RepoFile '.github/agents/github/backlog-grooming.agent.md'
    $script:Manager = Read-RepoFile '.github/agents/github/github-backlog-manager.agent.md'
    $script:Executor = Read-RepoFile '.github/instructions/github/github-backlog-update.instructions.md'
}

Describe 'Backlog grooming workflow source' -Tag 'Unit' {
    It 'declares weekly and manual triggers with the dedicated agent import' {
        $script:Source | Should -Match '(?m)^  schedule:$'
        $script:Source | Should -Match '(?m)^    - cron: "23 9 \* \* 3"$'
        $script:Source | Should -Match '(?m)^  workflow_dispatch:$'
        $script:Source | Should -Match '(?m)^  - \.\./agents/github/backlog-grooming\.agent\.md$'
    }

    It 'keeps model permissions read-only and safe outputs bounded' {
        $script:Source | Should -Match '(?ms)^permissions:\s+contents: read\s+issues: read$'
        $script:Source | Should -Match '(?ms)^  noop:\s+max: 1\s+report-as-issue: false'
        $script:Source | Should -Match '(?m)^    publish-backlog-grooming-report:$'
        $script:Source | Should -Match '(?ms)^      permissions:\s+issues: write$'
        $script:Source | Should -Not -Match '(?m)^\s+target: "\*"$'
        $script:Source | Should -Match '(?m)^  report-failure-as-issue: false$'
        $script:Source | Should -Match '(?m)^  report-incomplete: false$'
        $script:Source | Should -Match '(?m)^  missing-tool: false$'
        $script:Source | Should -Match '(?m)^  missing-data: false$'
    }

    It 'contains no prohibited mutation or code-scanning output' {
        $script:Source | Should -Not -Match '(?m)^  (create-issue|update-issue|close-issue|add-labels|remove-labels|create-code-scanning-alert):'
        $script:Source | Should -Not -Match '(?m)^\s*security-events: write$'
        $script:Source | Should -Not -Match '(?i)upload.*sarif'
    }

    It 'accepts absent or sole tracker state and fails closed for ambiguity' {
        $script:Source | Should -Match '<!-- gh-aw:backlog-grooming-tracker -->'
        $script:Source | Should -Match 'When no matching issue exists'
        $script:Source | Should -Match 'When exactly one matching issue exists'
        $script:Source | Should -Match 'When multiple matching issues'
        $script:Source | Should -Match 'state: "all"'
    }

    It 'persists every successful assessment through an independently resolved tracker lifecycle' {
        $script:Source | Should -Match 'After every successful assessment, call `publish-backlog-grooming-report` once'
        $script:Source | Should -Match 'This includes runs where no assessed issue'
        $script:Source | Should -Match 'issue\.body\?\.includes\(marker\)'
        $script:Source | Should -Match 'trackers\.length > 1'
        $script:Source | Should -Match 'github\.rest\.issues\.create\('
        $script:Source | Should -Match '"title": "Backlog grooming tracker"'
        $script:Source | Should -Match 'github\.rest\.issues\.update\('
        $script:Source | Should -Match 'issue_number: trackers\[0\]\.number'
        $script:Source | Should -Match 'state: "open"'
        $script:Source | Should -Not -Match 'issues\.createComment'
        $script:Source | Should -Match 'safe-output job independently revalidates tracker state'
    }

    It 'feeds one sanitized report variable to persistence before the Actions summary' {
        $script:Source | Should -Match 'const body = `\$\{marker\}\\n\\n\$\{report\}`;'
        $script:Source | Should -Match 'await core\.summary\.addRaw\(report\)\.write\(\);'
        $script:Source | Should -Match '(?s)issues\.create\(.*issues\.update\(.*core\.summary\.addRaw\(report\)'
    }
}

Describe 'Compiled backlog grooming workflow' -Tag 'Unit' {
    It 'is compiler-owned and preserves triggers and read-only model access' {
        $script:Lock | Should -Match '^# gh-aw-metadata:'
        $script:Lock | Should -Match '(?m)^  schedule:$'
        $script:Lock | Should -Match '(?m)^  workflow_dispatch:$'
        $script:Lock | Should -Match '(?m)^      issues: read$'
    }

    It 'allows only the tracker-bound publisher and noop from agent output' {
        $script:Lock | Should -Match 'publish_backlog_grooming_report'
        $script:Lock | Should -Match '"noop":\{"max":1,"report-as-issue":"false"\}'
        $script:Lock | Should -Not -Match '"add_comment"'
        $script:Lock | Should -Not -Match '"(create_issue|update_issue|close_issue|add_labels|remove_labels)"'
        $script:Lock | Should -Not -Match 'GH_AW_\w*CREATE_ISSUE'
        $script:Lock | Should -Not -Match 'issues\.createComment'
    }

    It 'publishes the validated report to the step summary without SARIF permissions' {
        $script:Lock | Should -Match 'Append agent step summary'
        $script:Lock | Should -Match 'await core\.summary\.addRaw\(report\)\.write\(\);'
        $script:Lock | Should -Not -Match '(?m)^\s*security-events: write$'
        $script:Lock | Should -Not -Match 'create_code_scanning_alert'
    }
}

Describe 'Backlog grooming policy and agent' -Tag 'Unit' {
    It 'requires complete all-open inventory and starvation-free continuation' {
        $script:Policy | Should -Match 'Every open non-pull-request issue except the workflow-owned marker-bearing'
        $script:Policy | Should -Match 'Paginate until the complete open-issue\s+metadata inventory'
        $script:Policy | Should -Match '(?s)beginning after the\s+previous successful run''s cursor'
        $script:Policy | Should -Match 'Wrap to the start of the inventory'
        $script:Policy | Should -Match 'Do not impose an age threshold or fixed semantic issue-count limit'
        $script:Policy | Should -Match 'When no issue requires a maintainer action'
        $script:Policy | Should -Match 'the model never supplies the destination issue number'
        $script:Policy | Should -Match 'create one open issue titled `Backlog\s+grooming tracker`'
        $script:Policy | Should -Match 'set\s+its state to open in the same update'
    }

    It 'defines the canonical tables and qualitative outcomes' {
        $script:Policy | Should -Match '\| Run timestamp \| Total open inventory \| Assessed \| Priority cohort \| Round-robin cohort \| Deferred \| Stop reason \| Next cursor \|'
        $script:Policy | Should -Match '\| Issue \| Title \| Selection reason \| Activity and ownership context \| Similarity outcome \| Grooming finding \| Recommended next step \| Assessment status \|'
        foreach ($outcome in @('Match', 'Similar', 'Distinct', 'Uncertain')) {
            $script:Policy | Should -Match "\* ``$outcome``"
        }
    }

    It 'keeps candidate content inert and sensitive output minimized' {
        $script:Agent | Should -Match 'untrusted\s+inert data'
        $script:Agent | Should -Match 'sensitive context omitted'
        $script:Agent | Should -Match 'Do not close, create, edit, assign, milestone, label, or comment on candidate'
    }
}

Describe 'Interactive grooming route and fresh-state execution' -Tag 'Unit' {
    It 'classifies grooming without stealing triage or ordinary single-issue requests' {
        foreach ($signal in @('groom', 'grooming', 'staleness', 'backlog health')) {
            $script:Manager | Should -Match ([regex]::Escape($signal))
        }
        $script:Manager | Should -Match 'needs-triage` always indicates Triage'
        $script:Manager | Should -Match 'explicit issue number scopes the request to Single Issue unless the request explicitly reviews a grooming digest'
    }

    It 'limits grooming handoffs to one approved non-closing operation per issue' {
        $script:Policy | Should -Match 'only\s+`Update` or `Comment` operations'
        $script:Policy | Should -Match 'at most one mutating operation per issue'
        $script:Policy | Should -Match 'It never contains `Close`'
        $script:Policy | Should -Match 'Require explicit per-field approval'
    }

    It 'suppresses stale mutations and requires renewed approval' {
        $script:Executor | Should -Match 'Immediately before an Update or Comment carrying `Expected Updated At`'
        $script:Executor | Should -Match 'Compare the returned `updated_at` string exactly'
        $script:Executor | Should -Match 'do not call a mutation tool'
        $script:Executor | Should -Match 'Skipped: stale approval'
        $script:Executor | Should -Match 'Expected Updated At` and `Observed Updated At`'
        $script:Executor | Should -Match 'rehydrate the issue and obtain renewed approval'
    }
}

Describe 'Backlog grooming continuation behavior' -Tag 'Unit' {
    BeforeAll {
        $script:Baseline = [datetime]'2026-07-01T00:00:00Z'
        $script:Inventory = @(1..105 | ForEach-Object {
                [pscustomobject]@{
                    Number = $_
                    State = 'open'
                    PullRequest = $false
                    UpdatedAt = if ($_ -eq 105) { $script:Baseline.AddDays(1) } else { $script:Baseline.AddDays(-1) }
                }
            })
    }

    It 'advances across successive runs while preserving priority and wraparound cohorts' {
        $firstRun = Select-GroomingCohort -Issues $script:Inventory -PreviousCursor 100 -PreviousRun $script:Baseline -Capacity 4
        $firstRun.Selected.Number | Should -Be @(105, 101, 102, 103)
        $firstRun.Priority | Should -Be @(105)
        $firstRun.RoundRobin | Should -Be @(101, 102, 103)
        $firstRun.NextCursor | Should -Be 103

        $secondRun = Select-GroomingCohort -Issues $script:Inventory -PreviousCursor $firstRun.NextCursor -PreviousRun $script:Baseline.AddDays(2) -Capacity 4
        $secondRun.Selected.Number | Should -Be @(104, 105, 1, 2)
        $secondRun.RoundRobin | Should -Be @(104, 105, 1, 2)
        $secondRun.NextCursor | Should -Be 2
    }

    It 'creates the fixed-title tracker when no non-pull-request match exists' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $creates = [System.Collections.Generic.List[object]]::new()
        $updates = [System.Collections.Generic.List[object]]::new()
        $summaries = [System.Collections.Generic.List[string]]::new()
        $failures = [System.Collections.Generic.List[string]]::new()

        Publish-GroomingReport -Report 'Canonical report with enough content' -Issues @() `
            -CreateSink { param($title, $body) $creates.Add([pscustomobject]@{ Title = $title; Body = $body }) } `
            -UpdateSink { param($number, $body, $state) $updates.Add([pscustomobject]@{ Number = $number; Body = $body; State = $state }) } `
            -SummarySink { param($value) $summaries.Add($value) } `
            -FailureSink { param($value) $failures.Add($value) }

        $creates | Should -HaveCount 1
        $creates[0].Title | Should -BeExactly 'Backlog grooming tracker'
        $creates[0].Body | Should -BeExactly "$marker`n`n$($summaries[0])"
        $updates | Should -HaveCount 0
        $failures | Should -HaveCount 0
    }

    It 'updates and reopens the sole tracker with full body replacement' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        foreach ($state in @('open', 'closed')) {
            $creates = [System.Collections.Generic.List[object]]::new()
            $updates = [System.Collections.Generic.List[object]]::new()
            $summaries = [System.Collections.Generic.List[string]]::new()
            $failures = [System.Collections.Generic.List[string]]::new()
            $tracker = [pscustomobject]@{ Number = 10; State = $state; PullRequest = $false; Body = "$marker`n`nOld report" }

            Publish-GroomingReport -Report "Replacement report for $state tracker" -Issues @($tracker) `
                -CreateSink { param($title, $body) $creates.Add([pscustomobject]@{ Title = $title; Body = $body }) } `
                -UpdateSink { param($number, $body, $newState) $updates.Add([pscustomobject]@{ Number = $number; Body = $body; State = $newState }) } `
                -SummarySink { param($value) $summaries.Add($value) } `
                -FailureSink { param($value) $failures.Add($value) }

            $creates | Should -HaveCount 0
            $updates | Should -HaveCount 1
            $updates[0].Number | Should -Be 10
            $updates[0].State | Should -BeExactly 'open'
            $updates[0].Body | Should -BeExactly "$marker`n`n$($summaries[0])"
            $updates[0].Body | Should -Not -Match 'Old report'
            $failures | Should -HaveCount 0
        }
    }

    It 'fails without mutation for every multiple-tracker state combination' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        foreach ($states in @(@('open', 'open'), @('closed', 'closed'), @('open', 'closed'))) {
            $issues = @(0..1 | ForEach-Object {
                    [pscustomobject]@{ Number = 10 + $_; State = $states[$_]; PullRequest = $false; Body = $marker }
                })
            $creates = [System.Collections.Generic.List[object]]::new()
            $updates = [System.Collections.Generic.List[object]]::new()
            $summaries = [System.Collections.Generic.List[string]]::new()
            $failures = [System.Collections.Generic.List[string]]::new()

            Publish-GroomingReport -Report 'Canonical report with enough content' -Issues $issues `
                -CreateSink { param($title, $body) $creates.Add(@($title, $body)) } `
                -UpdateSink { param($number, $body, $state) $updates.Add(@($number, $body, $state)) } `
                -SummarySink { param($value) $summaries.Add($value) } `
                -FailureSink { param($value) $failures.Add($value) }

            $creates | Should -HaveCount 0
            $updates | Should -HaveCount 0
            $summaries | Should -HaveCount 0
            $failures | Should -HaveCount 1
        }
    }

    It 'excludes marker-bearing pull requests and creates the tracker' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $pullRequest = [pscustomobject]@{ Number = 20; State = 'open'; PullRequest = $true; Body = $marker }
        $creates = [System.Collections.Generic.List[object]]::new()
        $updates = [System.Collections.Generic.List[object]]::new()

        Publish-GroomingReport -Report 'Canonical report with enough content' -Issues @($pullRequest) `
            -CreateSink { param($title, $body) $creates.Add([pscustomobject]@{ Title = $title; Body = $body }) } `
            -UpdateSink { param($number, $body, $state) $updates.Add(@($number, $body, $state)) } `
            -SummarySink { param($value) } `
            -FailureSink { param($value) }

        $creates | Should -HaveCount 1
        $updates | Should -HaveCount 0
    }

    It 'does not write the summary when tracker persistence fails' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $tracker = [pscustomobject]@{ Number = 10; State = 'open'; PullRequest = $false; Body = $marker }
        foreach ($issues in @(@(), @($tracker))) {
            $summaryReports = [System.Collections.Generic.List[string]]::new()

            {
                Publish-GroomingReport -Report 'Canonical report with enough content' -Issues $issues `
                    -CreateSink { param($title, $body) throw 'Persistence failed' } `
                    -UpdateSink { param($number, $body, $state) throw 'Persistence failed' } `
                    -SummarySink { param($value) $summaryReports.Add($value) } `
                    -FailureSink { param($value) }
            } | Should -Throw '*Persistence failed*'

            $summaryReports | Should -HaveCount 0
        }
    }

    It 'publishes one sanitized deferred report identically to persistence and summary' {
        $report = New-GroomingReport -Run @{
            Timestamp = '2026-07-29T09:23:00Z'
            Total = 105
            Assessed = 1
            Priority = 1
            RoundRobin = 1
            Deferred = 1
            StopReason = 'Budget reserved for report publication'
            NextCursor = 2
        } -Rows @(
            [pscustomobject]@{
                Number = 105
                Title = 'Assigned issue'
                SelectionReason = 'Priority'
                Context = 'Assigned today'
                Similarity = 'Distinct'
                Finding = 'Current'
                NextStep = 'No change'
                Status = 'Assessed'
            },
            [pscustomobject]@{
                Number = 2
                Title = 'Deferred issue'
                SelectionReason = 'Round-robin'
                Context = 'Not hydrated'
                Similarity = 'Uncertain'
                Finding = 'Deferred: report budget reached'
                NextStep = 'Assess next run'
                Status = 'Deferred'
            }
        )

        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $summaryReports = [System.Collections.Generic.List[string]]::new()
        $trackerBodies = [System.Collections.Generic.List[string]]::new()
        Publish-GroomingReport -Report "$report`nOwner: @maintainer`u{0007}" `
            -Issues @() `
            -CreateSink { param($title, $body) $trackerBodies.Add($body) } `
            -UpdateSink { param($number, $body, $state) } `
            -SummarySink { param($value) $summaryReports.Add($value) } `
            -FailureSink { param($value) }

        $summaryReports.Count | Should -Be 1
        $trackerBodies.Count | Should -Be 1
        $trackerBodies[0] | Should -BeExactly "$marker`n`n$($summaryReports[0])"
        $summaryReports[0] | Should -Match '@\u200bmaintainer'
        $summaryReports[0] | Should -Not -Match '\x07'
        $summaryReports[0] | Should -Match '\| #2 \| Deferred issue .*\| Deferred \|'
        $summaryReports[0] | Should -Match '\| 2026-07-29T09:23:00Z \| 105 \| 1 \| 1 \| 1 \| 1 .*\| 2 \|'
    }

    It 'persists a successful no-action report before writing the summary' {
        $report = New-GroomingReport -Run @{
            Timestamp = '2026-07-30T09:23:00Z'
            Total = 0
            Assessed = 0
            Priority = 0
            RoundRobin = 0
            Deferred = 0
            StopReason = 'No open issues'
            NextCursor = 0
        } -Rows @(
            [pscustomobject]@{
                Number = '-'
                Title = 'No issues assessed'
                SelectionReason = '-'
                Context = '-'
                Similarity = '-'
                Finding = 'No maintainer action'
                NextStep = 'None'
                Status = 'Assessed'
            }
        )
        $summaryReports = [System.Collections.Generic.List[string]]::new()
        $trackerBodies = [System.Collections.Generic.List[string]]::new()

        Publish-GroomingReport -Report $report `
            -Issues @() `
            -CreateSink { param($title, $body) $trackerBodies.Add($body) } `
            -UpdateSink { param($number, $body, $state) } `
            -SummarySink { param($value) $summaryReports.Add($value) } `
            -FailureSink { param($value) }

        $summaryReports | Should -HaveCount 1
        $trackerBodies | Should -HaveCount 1
        $trackerBodies[0] | Should -Match ([regex]::Escape($summaryReports[0]))
        $trackerBodies[0] | Should -Match 'No issues assessed'
        $trackerBodies[0] | Should -Match 'No maintainer action'
    }
}
