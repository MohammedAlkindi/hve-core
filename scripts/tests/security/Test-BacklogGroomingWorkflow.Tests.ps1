#Requires -Modules Pester
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path

    function Read-RepoFile {
        param([Parameter(Mandatory)] [string]$Path)

        return Get-Content -LiteralPath (Join-Path $script:RepoRoot $Path) -Raw
    }

    function Test-GroomingMutationFields {
        param(
            [Parameter(Mandatory)] [ValidateSet('Update', 'Comment')] [string]$Action,
            [Parameter(Mandatory)] [string[]]$MutationFields
        )

        $allowedFields = if ($Action -eq 'Update') { @('title', 'body') } else { @('body') }
        return $MutationFields.Count -gt 0 -and
            @($MutationFields | Where-Object { $_ -notin $allowedFields }).Count -eq 0
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

        $nextCursor = if ($selected.Count -gt 0) {
            $selected[-1].Number
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
        $lines.Add('| Issue | Title | Selection reason | Activity and ownership context | Repository evidence | Similarity outcome | Disposition | Grooming finding | Recommended next step | Assessment status |')
        $lines.Add('|---|---|---|---|---|---|---|---|---|---|')
        foreach ($row in $Rows) {
            $lines.Add("| #$($row.Number) | $($row.Title) | $($row.SelectionReason) | $($row.Context) | $($row.Evidence) | $($row.Similarity) | $($row.Disposition) | $($row.Finding) | $($row.NextStep) | $($row.Status) |")
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
                -not $_.PullRequest -and
                $_.Body.Contains($marker) -and
                $_.User.Login -ceq 'github-actions[bot]' -and
                $_.User.Type -ceq 'Bot'
            })
        if ($trackers.Count -gt 1) {
            & $FailureSink "Expected at most one trusted marker-bearing tracker, found $($trackers.Count)"
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
    $script:Orchestrator = Read-RepoFile '.github/workflows/backlog-groom-orchestrator.yml'
    $script:Policy = Read-RepoFile '.github/instructions/github/github-backlog-grooming.instructions.md'
    $script:Agent = Read-RepoFile '.github/agents/github/backlog-grooming.agent.md'
    $script:Manager = Read-RepoFile '.github/agents/github/github-backlog-manager.agent.md'
    $script:Executor = Read-RepoFile '.github/instructions/github/github-backlog-update.instructions.md'
}

Describe 'Backlog grooming workflow source' -Tag 'Unit' {
    It 'declares only a reusable worker trigger with the dedicated agent import' {
        $script:Source | Should -Match '(?m)^  workflow_call:$'
        $script:Source | Should -Not -Match '(?m)^  schedule:$'
        $script:Source | Should -Not -Match '(?m)^  workflow_dispatch:$'
        $script:Orchestrator | Should -Match '(?m)^  workflow_dispatch:$'
        $script:Source | Should -Match '(?m)^  - \.\./agents/github/backlog-grooming\.agent\.md$'
        $script:Source | Should -Match '(?m)^  - \.\./instructions/github/github-backlog-grooming\.instructions\.md$'
    }

    It 'keeps model permissions read-only and safe outputs bounded' {
        $script:Source | Should -Match '(?ms)^permissions:\s+contents: read\s+issues: read$'
        $script:Source | Should -Match '(?ms)^  noop:\s+max: 1\s+report-as-issue: false'
        $script:Source | Should -Match '(?m)^    publish-backlog-grooming-result:$'
        $script:Source | Should -Match '(?ms)^    publish-backlog-grooming-result:.*?permissions: \{\}'
        $script:Source | Should -Not -Match '(?m)^\s+issues: write$'
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

    It 'binds assessment to the planned open non-pull-request candidate set' {
        $script:Source | Should -Match 'retrieve only the listed open issues'
        $script:Source | Should -Match 'missing, closed, or a pull request'
        $script:Source | Should -Match 'Report issue IDs do not match the planned shard candidates'
        $script:Source | Should -Match 'Worker candidate IDs must be unique positive integers in ascending order'
        $script:Source | Should -Match 'The orchestrator, not the worker,\s+owns inventory selection'
        $script:Source | Should -Not -Match '<!-- gh-aw:backlog-grooming-tracker -->'
    }

    It 'emits one independently validated immutable shard result' {
        $script:Source | Should -Match 'call `publish-backlog-grooming-result` exactly once'
        $script:Source | Should -Match 'const requests = agentOutput\.items\.filter'
        $script:Source | Should -Match 'item\.type === "publish_backlog_grooming_result"'
        $script:Source | Should -Match 'Expected one report publication request, found \$\{requests\.length\}'
        $script:Source | Should -Match 'fs\.writeFileSync\('
        $script:Source | Should -Match '(?m)^        - name: Upload immutable shard result$'
        $script:Source | Should -Match 'backlog-grooming-proof-\$\{\{ inputs\.orchestrator_run_id \}\}-\$\{\{ inputs\.orchestrator_attempt \}\}-\$\{\{ inputs\.shard_id \}\}'
        $script:Source | Should -Not -Match 'github\.rest\.issues\.(create|update|createComment)'
    }

    It 'validates structured report data and computes deterministic result provenance' {
        $script:Source | Should -Match 'JSON\.parse\(String\(requests\[0\]\["report-data"\]'
        $script:Source | Should -Match 'exactKeys\(payload, \["run", "issues"\]\)'
        $script:Source | Should -Match 'const similarities = new Set\(\["Match", "Similar", "Distinct", "Uncertain"\]\)'
        $script:Source | Should -Match 'const dispositions = new Set\(\["Still needed", "Likely completed", "Superseded", "Possible duplicate", "Needs correction", "Uncertain"\]\)'
        $script:Source | Should -Match 'row\.acceptance_signals'
        $script:Source | Should -Match 'const lineageKeys = \["original_delivery", "replacement_or_removal"\]'
        $script:Source | Should -Match 'Superseded requires distinct original-delivery and replacement-or-removal evidence'
        $script:Source | Should -Match 'assessedRows !== run\.assessed \|\| deferredRows !== run\.deferred'
        $script:Source | Should -Match 'Report row statuses do not match the run counts'
        $script:Source | Should -Match 'const canonicalize = \(value\) =>'
        $script:Source | Should -Match '\.createHash\("sha256"\)'
        $script:Source | Should -Match '\.update\(canonicalize\(result\)\)'
        $script:Source | Should -Match 'result_digest: resultDigest'
        $script:Source | Should -Match 'Shard timestamps must be valid and completion cannot precede start'
    }

    It 'reads the hyphenated report-data field from the safe-output envelope' {
        $agentOutput = @{
            items = @(
                @{
                    type = 'publish_backlog_grooming_report'
                    'report-data' = '{"run":{"timestamp":"2026-08-11T00:33:20Z"},"issues":[]}'
                }
            )
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json

        $request = $agentOutput.items | Where-Object type -EQ 'publish_backlog_grooming_report'
        $payload = $request.'report-data' | ConvertFrom-Json

        $payload.run.timestamp.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') |
            Should -Be '2026-08-11T00:33:20Z'
        $payload.issues.Count | Should -Be 0
        $script:Source | Should -Not -Match 'requests\[0\]\.report_data'
    }
}

Describe 'Compiled backlog grooming workflow' -Tag 'Unit' {
    It 'is compiler-owned and preserves the reusable trigger and read-only model access' {
        $script:Lock | Should -Match '^# gh-aw-metadata:'
        $script:Lock | Should -Match '(?m)^  workflow_call:$'
        $script:Lock | Should -Not -Match '(?m)^  schedule:$'
        $script:Lock | Should -Not -Match '(?m)^  workflow_dispatch:$'
        $script:Lock | Should -Match '(?m)^      issues: read$'
        $script:Lock | Should -Match 'runtime-import \.github/instructions/github/github-backlog-grooming\.instructions\.md'
    }

    It 'allows only the artifact-bound result job and noop from agent output' {
        $script:Lock | Should -Match 'publish_backlog_grooming_result'
        $script:Lock | Should -Match '"noop":\{"max":1,"report-as-issue":"false"\}'
        $script:Lock | Should -Match 'Upload immutable shard result'
        $script:Lock | Should -Match 'producer: "backlog-groom/result-job"'
        $script:Lock | Should -Not -Match '"add_comment"'
        $script:Lock | Should -Not -Match '"(create_issue|update_issue|close_issue|add_labels|remove_labels)"'
        $script:Lock | Should -Not -Match 'GH_AW_\w*CREATE_ISSUE'
        $script:Lock | Should -Not -Match 'issues\.createComment'
    }

    It 'uploads the validated result without issue-write or SARIF permissions' {
        $script:Lock | Should -Match 'JSON\.parse\(String\(requests\[0\]\["report-data"\]'
        $script:Lock | Should -Match 'Possible duplicate requires a Match or Similar outcome'
        $script:Lock | Should -Match 'Superseded requires distinct original-delivery and replacement-or-removal evidence'
        $script:Lock | Should -Match 'result-output/shard-result\.json'
        $script:Lock | Should -Match 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a'
        $script:Lock | Should -Not -Match '(?m)^\s*issues: write$'
        $script:Lock | Should -Not -Match '(?m)^\s*security-events: write$'
        $script:Lock | Should -Not -Match 'create_code_scanning_alert'
    }
}

Describe 'Backlog grooming sharded orchestration contracts' -Tag 'Unit' {
    It 'defines typed worker identity, manifest envelopes, and shard-specific generated concurrency' {
        foreach ($inputName in @('shard_id', 'manifest_digest', 'ordered_candidate_ids', 'orchestrator_run_id')) {
            $script:Source | Should -Match "(?ms)^      ${inputName}:\s+.*?required: true\s+type: string"
            $script:Lock | Should -Match "(?ms)^      ${inputName}:\s+.*?required: true\s+type: string"
        }
        foreach ($inputName in @('orchestrator_attempt', 'worker_timeout_minutes')) {
            $script:Source | Should -Match "(?ms)^      ${inputName}:\s+.*?type: number"
            $script:Lock | Should -Match "(?ms)^      ${inputName}:\s+.*?type: number"
        }

        $script:Source | Should -Match '(?m)^max-ai-credits: 1000$'
        $script:Source | Should -Match '(?m)^  job-discriminator: \$\{\{ inputs\.shard_id \|\| github\.run_id \}\}$'
        $script:Lock | Should -Match 'gh-aw-copilot-backlog-groom-\$\{\{ inputs\.shard_id \|\| github\.run_id \}\}'
        $script:Lock | Should -Match 'gh-aw-conclusion-backlog-groom-\$\{\{ inputs\.shard_id \|\| github\.run_id \}\}'

        foreach ($field in @(
                'schema_version', 'run_id', 'attempt', 'shard_id', 'manifest_digest',
                'ordered_candidate_ids', 'result_digest', 'producer', 'started_at', 'completed_at'
            )) {
            $script:Source | Should -Match ([regex]::Escape("``$field``"))
        }
        $script:Orchestrator | Should -Match 'schema_version: "backlog-grooming-proof-manifest/v1"'
        $script:Orchestrator | Should -Match 'createHash\("sha256"\)'
        $script:Orchestrator | Should -Match 'backlog-grooming-proof-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}-manifest'
        $script:Orchestrator | Should -Match 'plannedAiCredits = shardCount \* perWorkerAiCredits'
        $script:Orchestrator | Should -Match 'planned AI Credits \$\{plannedAiCredits\} exceed cap'
        $script:Orchestrator | Should -Match '(?ms)^  assess:.*?permissions:\s+actions: write\s+contents: read\s+issues: read'
        $script:Orchestrator | Should -Match '(?ms)^  assess:.*?secrets: inherit'
        $script:Orchestrator | Should -Not -Match '(?m)^\s+issues: write$'
        $script:Orchestrator | Should -Match 'terminal_rule: "exactly-one-current-run-result-per-planned-shard"'
        foreach ($rejection in @('missing', 'malformed', 'stale', 'unexpected', 'duplicate', 'conflicting', 'manifest-mismatched')) {
            $script:Orchestrator | Should -Match ([regex]::Escape("`"$rejection`""))
        }
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
        $script:Policy | Should -Match '[Tt]he model never supplies the destination\s+issue\s+number'
        $script:Policy | Should -Match 'create one open issue titled\s+`Backlog\s+grooming tracker`'
        $script:Policy | Should -Match 'set\s+its state to open in the same update'
    }

    It 'defines the canonical tables and qualitative outcomes' {
        $script:Policy | Should -Match '\| Run timestamp \| Total open inventory \| Assessed \| Priority cohort \| Round-robin cohort \| Deferred \| Stop reason \| Next cursor \|'
        $script:Policy | Should -Match '\| Issue \| Title \| Selection reason \| Activity and ownership context \| Acceptance signals \| Repository evidence \| Similarity outcome \| Disposition \| Grooming finding \| Recommended next step \| Assessment status \|'
        foreach ($outcome in @('Match', 'Similar', 'Distinct', 'Uncertain')) {
            $script:Policy | Should -Match "\* ``$outcome``"
        }
    }

    It 'gives the model the exact structured publisher contract' {
        foreach ($key in @('timestamp', 'total_open_inventory', 'assessed', 'priority_cohort', 'round_robin_cohort', 'deferred', 'stop_reason', 'next_cursor')) {
            $script:Agent | Should -Match ([regex]::Escape("`"$key`""))
        }
        foreach ($key in @('issue', 'title', 'selection_reason', 'activity_and_ownership_context', 'acceptance_signals', 'repository_evidence', 'lineage_evidence', 'original_delivery', 'replacement_or_removal', 'similarity_outcome', 'disposition', 'grooming_finding', 'recommended_next_step', 'assessment_status')) {
            $script:Agent | Should -Match ([regex]::Escape("`"$key`""))
        }
        $script:Agent | Should -Match 'Use integers without `#` or prose for `issue`, `next_cursor`, and every count'
        $script:Agent | Should -Match 'Use exactly `Assessed` or `Deferred` for `assessment_status`'
        $script:Agent | Should -Match 'put compared issue numbers in the finding rather than the\s+enum value'
    }

    It 'requires repository-grounded dispositions and evidence-backed maintainer actions' {
        $script:Agent | Should -Match 'extract.*requested outcomes.*acceptance signals'
        $script:Agent | Should -Match 'default branch.*code.*configuration.*documentation'
        $script:Agent | Should -Match 'open, merged, and closed pull requests'
        $script:Agent | Should -Match 'open and closed issues'
        $script:Agent | Should -Match 'commits or releases'
        $script:Agent | Should -Match 'Use `Uncertain` when'
        $script:Agent | Should -Match 'unlinked pull requests and commits as valid lineage evidence'
        $script:Policy | Should -Match 'Direct issue linkage is not required'
        $script:Source | Should -Match 'Do not require a direct issue link'
        $script:Policy | Should -Match '\| Issue \| Title \| Selection reason \| Activity and ownership context \| Acceptance signals \| Repository evidence \| Similarity outcome \| Disposition \|'
        foreach ($disposition in @('Still needed', 'Likely completed', 'Superseded', 'Possible duplicate', 'Needs correction', 'Uncertain')) {
            $script:Policy | Should -Match "\* ``$disposition``"
        }
        $script:Policy | Should -Match 'recommend that a maintainer close the\s+issue'
        $script:Policy | Should -Match 'recommend specific title or body corrections'
        $script:Agent | Should -Not -Match 'Do not add closure language, mutation proposals'
    }

    It 'requires complete legacy and replacement lineage for superseded work' {
        $script:Agent | Should -Match 'For `Superseded`, record both the original surface''s delivery lineage and its\s+removal or replacement lineage when both are available'
        $script:Policy | Should -Match 'cite the original\s+surface''s delivery issue or pull request and the later removal or replacement\s+issue or pull request'
        $script:Policy | Should -Match '`lineage_evidence` with exactly\s+`original_delivery` and `replacement_or_removal` arrays'
        $script:Policy | Should -Match 'Both arrays are\s+non-empty and contain distinct stable identifiers for `Superseded`'
    }

    It 'defines discriminating evidence rules for representative dispositions' -ForEach @(
        @{
            Scenario = 'implemented capability on the default branch with merged delivery history'
            Disposition = 'Likely completed'
            EvidencePattern = 'default-branch evidence satisfies.*acceptance signals.*merged pull-request, commit, or release evidence'
        },
        @{
            Scenario = 'legacy surface removed and replaced by a current capability'
            Disposition = 'Superseded'
            EvidencePattern = 'named surface was removed,\s+replaced, or intentionally abandoned.*replacement or\s+decision history'
        },
        @{
            Scenario = 'requested outcome remains absent with no completing work'
            Disposition = 'Still needed'
            EvidencePattern = 'requested outcome is\s+absent or incomplete.*no merged or closed work establishes completion'
        },
        @{
            Scenario = 'matching issue has no distinct repository need'
            Disposition = 'Possible duplicate'
            EvidencePattern = 'similarity outcome is `Match` or `Similar`.*same outcome.*does\s+not establish a distinct remaining need'
        },
        @{
            Scenario = 'issue text conflicts with current repository facts'
            Disposition = 'Needs correction'
            EvidencePattern = 'title or body conflicts with verified current\s+paths, names, behavior, or scope.*corrected issue would still describe\s+useful work'
        },
        @{
            Scenario = 'acceptance or repository history is ambiguous'
            Disposition = 'Uncertain'
            EvidencePattern = 'acceptance signals are ambiguous.*searches cannot be\s+completed.*evidence conflicts'
        }
    ) {
        $script:Policy | Should -Match "``$Disposition``:"
        $script:Policy | Should -Match "(?s)$EvidencePattern"
    }

    It 'keeps candidate content inert and sensitive output minimized' {
        $script:Agent | Should -Match 'untrusted\s+inert data'
        $script:Agent | Should -Match 'escape backslashes and pipe characters'
        $script:Agent | Should -Match 'replace line breaks with `<br>`'
        $script:Agent | Should -Match 'zero-width space after `@`'
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

    It 'enforces operation-specific Grooming mutation field allowlists' {
        foreach ($fields in @(@('title'), @('body'), @('title', 'body'))) {
            Test-GroomingMutationFields -Action Update -MutationFields $fields | Should -BeTrue
        }
        Test-GroomingMutationFields -Action Comment -MutationFields @('body') | Should -BeTrue

        foreach ($field in @('labels', 'assignees', 'milestone', 'state', 'state_reason', 'type', 'duplicate_of', 'unsupported')) {
            Test-GroomingMutationFields -Action Update -MutationFields @($field) | Should -BeFalse
        }
        Test-GroomingMutationFields -Action Comment -MutationFields @('title') | Should -BeFalse

        $script:Executor | Should -Match 'For a Grooming Update, accept `title` and `body` as the only mutation fields'
        $script:Executor | Should -Match 'For a Grooming Comment, accept `body` as the only mutation field'
        $script:Executor | Should -Match 'Reject `labels`, `assignees`, `milestone`, `state`, `state_reason`, `type`, `duplicate_of`'
        $script:Executor | Should -Match 'Immediately before each Grooming Update or Comment API call, revalidate'
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

    It 'uses the last assessed priority issue as the cursor when capacity is exhausted' {
        $run = Select-GroomingCohort -Issues $script:Inventory -PreviousCursor 100 -PreviousRun $script:Baseline -Capacity 1

        $run.Selected.Number | Should -Be @(105)
        $run.Priority | Should -Be @(105)
        $run.RoundRobin | Should -Be @()
        $run.NextCursor | Should -Be 105
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
            $tracker = [pscustomobject]@{
                Number = 10
                State = $state
                PullRequest = $false
                Body = "$marker`n`nOld report"
                User = [pscustomobject]@{ Login = 'github-actions[bot]'; Type = 'Bot' }
            }

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
                    [pscustomobject]@{
                        Number = 10 + $_
                        State = $states[$_]
                        PullRequest = $false
                        Body = $marker
                        User = [pscustomobject]@{ Login = 'github-actions[bot]'; Type = 'Bot' }
                    }
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
        $pullRequest = [pscustomobject]@{
            Number = 20
            State = 'open'
            PullRequest = $true
            Body = $marker
            User = [pscustomobject]@{ Login = 'github-actions[bot]'; Type = 'Bot' }
        }
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

    It 'ignores an untrusted marker-bearing issue and creates the tracker' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $untrusted = [pscustomobject]@{
            Number = 20
            State = 'open'
            PullRequest = $false
            Body = $marker
            User = [pscustomobject]@{ Login = 'contributor'; Type = 'User' }
        }
        $creates = [System.Collections.Generic.List[object]]::new()
        $updates = [System.Collections.Generic.List[object]]::new()

        Publish-GroomingReport -Report 'Canonical report with enough content' -Issues @($untrusted) `
            -CreateSink { param($title, $body) $creates.Add([pscustomobject]@{ Title = $title; Body = $body }) } `
            -UpdateSink { param($number, $body, $state) $updates.Add(@($number, $body, $state)) } `
            -SummarySink { param($value) } `
            -FailureSink { param($value) }

        $creates | Should -HaveCount 1
        $updates | Should -HaveCount 0
    }

    It 'updates only the trusted tracker in a mixed marker set' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $trusted = [pscustomobject]@{
            Number = 10
            State = 'open'
            PullRequest = $false
            Body = $marker
            User = [pscustomobject]@{ Login = 'github-actions[bot]'; Type = 'Bot' }
        }
        $untrusted = [pscustomobject]@{
            Number = 20
            State = 'open'
            PullRequest = $false
            Body = $marker
            User = [pscustomobject]@{ Login = 'contributor'; Type = 'User' }
        }
        $creates = [System.Collections.Generic.List[object]]::new()
        $updates = [System.Collections.Generic.List[object]]::new()

        Publish-GroomingReport -Report 'Canonical report with enough content' -Issues @($trusted, $untrusted) `
            -CreateSink { param($title, $body) $creates.Add([pscustomobject]@{ Title = $title; Body = $body }) } `
            -UpdateSink { param($number, $body, $state) $updates.Add([pscustomobject]@{ Number = $number; Body = $body; State = $state }) } `
            -SummarySink { param($value) } `
            -FailureSink { param($value) }

        $creates | Should -HaveCount 0
        $updates | Should -HaveCount 1
        $updates[0].Number | Should -Be 10
    }

    It 'does not write the summary when tracker persistence fails' {
        $marker = '<!-- gh-aw:backlog-grooming-tracker -->'
        $tracker = [pscustomobject]@{
            Number = 10
            State = 'open'
            PullRequest = $false
            Body = $marker
            User = [pscustomobject]@{ Login = 'github-actions[bot]'; Type = 'Bot' }
        }
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
                Evidence = 'src/current.md; PR #17 merged'
                Similarity = 'Distinct'
                Disposition = 'Still needed'
                Finding = 'Current'
                NextStep = 'No change'
                Status = 'Assessed'
            },
            [pscustomobject]@{
                Number = 2
                Title = 'Deferred issue'
                SelectionReason = 'Round-robin'
                Context = 'Not hydrated'
                Evidence = 'Not collected'
                Similarity = 'Uncertain'
                Disposition = 'Uncertain'
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
                Evidence = '-'
                Similarity = '-'
                Disposition = '-'
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
