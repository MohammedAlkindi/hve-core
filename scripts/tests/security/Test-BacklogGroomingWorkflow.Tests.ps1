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

    function Resolve-GroomingTracker {
        param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Issues)

        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $trackers = @($Issues | Where-Object {
                $_.State -eq 'open' -and -not $_.PullRequest -and $_.Body.Contains($marker)
            })
        if ($trackers.Count -ne 1) {
            throw "Expected one open marker-bearing tracker, found $($trackers.Count)"
        }

        return $trackers[0]
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

    It 'fails closed for every invalid tracker state' {
        $script:Source | Should -Match '<!-- gh-aw:backlog-grooming-tracker -->'
        $script:Source | Should -Match 'When no matching issue exists'
        $script:Source | Should -Match 'When matching issues exist but all are closed'
        $script:Source | Should -Match 'When multiple matching trackers are open'
        $script:Source | Should -Match 'Do not create a tracker or publish a comment'
    }

    It 'persists every successful assessment through an independently resolved tracker' {
        $script:Source | Should -Match 'After every successful assessment, call `publish-backlog-grooming-report` once'
        $script:Source | Should -Match 'This includes runs where no assessed issue'
        $script:Source | Should -Match 'issue\.body\?\.includes\(marker\)'
        $script:Source | Should -Match 'trackers\.length !== 1'
        $script:Source | Should -Match 'issue_number: trackers\[0\]\.number'
        $script:Source | Should -Match 'do not supply\s+an issue number'
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
    }

    It 'publishes the final response to the step summary without SARIF permissions' {
        $script:Lock | Should -Match 'Append agent step summary'
        $script:Lock | Should -Not -Match '(?m)^\s*security-events: write$'
        $script:Lock | Should -Not -Match 'create_code_scanning_alert'
    }
}

Describe 'Backlog grooming policy and agent' -Tag 'Unit' {
    It 'requires complete all-open inventory and starvation-free continuation' {
        $script:Policy | Should -Match 'Every open non-pull-request issue remains eligible'
        $script:Policy | Should -Match 'Paginate until the complete open-issue metadata inventory'
        $script:Policy | Should -Match '(?s)beginning after the\s+previous successful run''s cursor'
        $script:Policy | Should -Match 'Wrap to the start of the inventory'
        $script:Policy | Should -Match 'Do not impose an age threshold or fixed semantic issue-count limit'
        $script:Policy | Should -Match 'including when no maintainer action is recommended'
        $script:Policy | Should -Match 'the model never supplies the destination issue number'
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

    It 'rejects zero or multiple open marker-bearing trackers' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $tracker = [pscustomobject]@{ Number = 10; State = 'open'; PullRequest = $false; Body = $marker }
        Resolve-GroomingTracker -Issues @($tracker) | Select-Object -ExpandProperty Number | Should -Be 10
        { Resolve-GroomingTracker -Issues @() } | Should -Throw '*found 0*'
        { Resolve-GroomingTracker -Issues @($tracker, $tracker.PSObject.Copy()) } | Should -Throw '*found 2*'
    }

    It 'renders deferred rows identically for the summary and durable tracker digest' {
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

        $actionsSummary = $report
        $trackerDigest = $report
        $actionsSummary | Should -BeExactly $trackerDigest
        $report | Should -Match '\| #2 \| Deferred issue .*\| Deferred \|'
        $report | Should -Match '\| 2026-07-29T09:23:00Z \| 105 \| 1 \| 1 \| 1 \| 1 .*\| 2 \|'
    }
}
