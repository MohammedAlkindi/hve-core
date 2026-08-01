#!/usr/bin/env pwsh
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

#Requires -Version 7.4

<#
.SYNOPSIS
    Runs the Vally baseline-vs-customized equivalence suite for a target hve-core agent.

.DESCRIPTION
    Drives the `evals/baseline-equivalence/` Vally suite end-to-end. Resolves the target
    agent's frontmatter `model:` hint, selects a model tier (PR or nightly), invokes
    `vally eval` once per environment (`baseline` and `rpi-agent-context`), invokes
    `vally compare` to produce comparison JSONL, and writes a machine-readable summary
    to `logs/baseline-equivalence-summary.json`.

    Exit policy by tier:
    - PR tier always exits 0. Equivalence failures surface as `verdict: warn` in the
      summary JSON. Advisory only.
    - Nightly tier exits non-zero (1) when `verdict == fail`. Source of truth.

    `-WhatIf` (dry-run) mode prints the planned `vally` command lines, emits a summary
    JSON populated with zeros and `verdict: dry-run`, and exits 0 without invoking any
    SDK or external command.

.PARAMETER Agent
    The target agent slug, matching the basename of an `.agent.md` file under
    `.github/agents/`. Defaults to `rpi-agent`.

.PARAMETER Tier
    The model tier to exercise. `pr` runs a single primary model; `nightly` runs a model
    array for broader coverage. Defaults to `pr`.

.PARAMETER StimulusFilter
    Optional regular expression filtering stimulus names. Defaults to `.*` (all stimuli).

.PARAMETER Model
    Optional explicit model id for the PR tier. When supplied it overrides the agent's
    frontmatter `model:` hint and the built-in default, letting callers pin a cheaper
    model for advisory PR-tier runs. Ignored for the `nightly` tier, which always runs
    its fixed model array.

.PARAMETER RepoRoot
    Repository root. Defaults to the result of `git rev-parse --show-toplevel`, falling
    back to the parent of `$PSScriptRoot`.

.PARAMETER OutputPath
    Path to the summary JSON. Defaults to `<RepoRoot>/logs/baseline-equivalence-summary.json`.

.EXAMPLE
    ./Invoke-BaselineEquivalence.ps1 -Agent rpi-agent -Tier pr -WhatIf

    Prints the planned commands and writes a dry-run summary.

.EXAMPLE
    npm run ci:eval:equivalence -- -Agent rpi-agent -Tier pr

    Runs the PR-tier flow via the npm wrapper.

.NOTES
    Runs via: npm run ci:eval:equivalence
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Agent = 'rpi-agent',

    [Parameter(Mandatory = $false)]
    [ValidateSet('pr', 'nightly')]
    [string]$Tier = 'pr',

    [Parameter(Mandatory = $false)]
    [string]$StimulusFilter = '.*',

    [Parameter(Mandatory = $false)]
    [string]$Model,

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    # The comparison judge was previously pinned inside compare.eval.yml. That file is
    # retired, so the pin lives here where it is visible to any operator reading the
    # invocation rather than buried in a spec the driver rendered at run time.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ComparisonJudgeModel = 'claude-haiku-4.5',

    [Parameter(Mandatory = $false)]
    [switch]$NoBaselineCache
)

$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot 'lib/EquivalenceParsing.psm1') -Force
Import-Module -Name (Join-Path $PSScriptRoot 'lib/EquivalenceEnvironment.psm1') -Force

#region Helper Functions

function Resolve-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Hint
    )

    if ($Hint) { return (Resolve-Path -LiteralPath $Hint).Path }

    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitRoot)) {
        return $gitRoot.Trim()
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
}

function Get-AgentModelHint {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,
        [Parameter(Mandatory)]
        [string]$Agent
    )

    $agentsRoot = Join-Path $RepoRoot '.github/agents'
    if (-not (Test-Path -LiteralPath $agentsRoot)) { return $null }

    $candidate = Get-ChildItem -Path $agentsRoot -Recurse -Filter "$Agent.agent.md" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $candidate) { return $null }

    $match = Select-String -Path $candidate.FullName -Pattern '^\s*model\s*:\s*(.+)\s*$' -List
    if (-not $match) { return $null }

    return $match.Matches[0].Groups[1].Value.Trim().Trim('"').Trim("'")
}

function Resolve-ModelList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Tier,
        [string]$Hint,
        [string]$ModelOverride
    )

    if ($Tier -eq 'nightly') {
        return @('gpt-5.5', 'claude-opus-4.6', 'claude-sonnet-latest')
    }

    if ($ModelOverride) { return @($ModelOverride) }
    if ($Hint) { return @($Hint) }
    return @('gpt-5.6-luna')
}

function New-DryRunSummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Agent,
        [Parameter(Mandatory)]
        [string]$Tier,
        [Parameter(Mandatory)]
        [string]$Model,
        [Parameter(Mandatory)]
        [string]$StimulusFilter,
        [Parameter(Mandatory)]
        [string[]]$PlannedCommands,
        [hashtable]$Variants
    )

    return [ordered]@{
        agent              = $Agent
        tier               = $Tier
        model              = $Model
        stimulusFilter     = $StimulusFilter
        runs               = 0
        ties               = 0
        aWins              = 0
        bWins              = 0
        meanScore          = 0.0
        ciLow              = 0.0
        ciHigh             = 0.0
        winRate            = 0.0
        invariantFailures  = 0
        divergenceFailures = 0
        verdict            = 'dry-run'
        variants           = $Variants
        plannedCommands    = $PlannedCommands
    }
}

function Invoke-VallyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & vally @Arguments
    return $LASTEXITCODE
}

function Invoke-VallyCommandWithCapture {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [string]$LogPath
    )

    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $raw = & vally @Arguments 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $prev
    }

    $lines = @($raw | ForEach-Object { $_.ToString() })
    foreach ($line in $lines) { Write-Host $line }

    if ($LogPath) {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Set-Content -LiteralPath $LogPath -Value $lines -Encoding utf8NoBOM
    }

    return @{ ExitCode = $code; Lines = $lines }
}

function Get-CanonicalStimulusPolicy {
    <#
    .SYNOPSIS
        Reads comparison policy and declared invariants from the canonical library.
    .DESCRIPTION
        The comparison JSONL identifies stimuli by name only, so policy and invariant
        membership have to come from `stimuli.yml`. Without them the parser would count
        intentional divergence against equivalence, and the invariant tally would fall
        back to every deterministic grader rather than the ones actually declared.
    .OUTPUTS
        [hashtable] With keys Policy (name to policy) and Invariants (unique names).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $result = @{ Policy = @{}; Invariants = @() }
    $path = Join-Path $RepoRoot 'evals/baseline-equivalence/stimuli.yml'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $result }

    try {
        $parsed = ConvertFrom-Yaml (Get-Content -LiteralPath $path -Raw)
    }
    catch {
        return $result
    }

    $invariants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($stimulus in @($parsed.stimuli)) {
        if (-not $stimulus) { continue }
        $name = [string]$stimulus.name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $policy = ''
        if ($stimulus.ContainsKey('tags') -and $stimulus.tags -and $stimulus.tags.Contains('policy')) {
            $policy = [string]$stimulus.tags['policy']
        }
        $result.Policy[$name] = $policy

        if ($stimulus.ContainsKey('invariants') -and $stimulus.invariants) {
            foreach ($invariant in @($stimulus.invariants)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$invariant)) { [void]$invariants.Add([string]$invariant) }
            }
        }
    }

    $result.Invariants = @($invariants)
    return $result
}

function Get-InvariantFailureCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RunDir
    )

    if (-not $RunDir -or -not (Test-Path -LiteralPath $RunDir)) { return $null }
    $resultsMd = Join-Path $RunDir 'eval-results.md'
    if (-not (Test-Path -LiteralPath $resultsMd)) { return $null }
    try {
        $lines = Get-Content -LiteralPath $resultsMd -ErrorAction Stop
    }
    catch {
        return $null
    }
    $tally = Measure-InvariantFailures -Lines $lines
    if ($tally.Total -le 0) { return $null }
    return [int]$tally.Failed
}

function Get-PlannedCommands {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Models,
        [Parameter(Mandatory)]
        [string]$StimulusFilter,
        [Parameter(Mandatory)]
        [string]$OutputRoot,
        [Parameter(Mandatory)]
        [string]$RunId,
        [Parameter(Mandatory)]
        [string]$JudgeModel,
        [string]$BaselineWorkspacePath,
        [string]$BaselineSkillDirPath,
        [string]$CustomizedWorkspacePath,
        [string]$CustomizedSkillDirPath
    )

    $filterTag = if ($StimulusFilter -eq '.*') { '' } else { "  # filter: $StimulusFilter" }
    $plan = [System.Collections.Generic.List[string]]::new()
    foreach ($model in $Models) {
        $aDir = Join-Path $OutputRoot "$model/$RunId/baseline"
        $bDir = Join-Path $OutputRoot "$model/$RunId/customized"
        $baselineWorkspaceArg = if ([string]::IsNullOrEmpty($BaselineWorkspacePath)) { '""' } else { '"' + $BaselineWorkspacePath + '"' }
        $baselineSkillArg = if ([string]::IsNullOrEmpty($BaselineSkillDirPath)) { '""' } else { '"' + $BaselineSkillDirPath + '"' }
        $customizedWorkspaceArg = if ([string]::IsNullOrEmpty($CustomizedWorkspacePath)) { '""' } else { '"' + $CustomizedWorkspacePath + '"' }
        $customizedSkillArg = if ([string]::IsNullOrEmpty($CustomizedSkillDirPath)) { '""' } else { '"' + $CustomizedSkillDirPath + '"' }
        $plan.Add("vally eval --eval-spec evals/baseline-equivalence/baseline/eval.yaml --model $model --output-dir $aDir --workspace $baselineWorkspaceArg --skill-dir $baselineSkillArg$filterTag")
        $plan.Add("vally eval --eval-spec evals/baseline-equivalence/customized/eval.yaml --model $model --output-dir $bDir --workspace $customizedWorkspaceArg --skill-dir $customizedSkillArg$filterTag")
        $plan.Add("vally compare --judge-model $JudgeModel --baseline <resolved baseline run> --treatment <resolved customized run> --output <compare jsonl path>")
    }
    return $plan.ToArray()
}

function Resolve-LatestRunDir {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$OutputDir
    )

    if (-not (Test-Path -LiteralPath $OutputDir)) { return $null }
    $latest = Get-ChildItem -LiteralPath $OutputDir -Directory -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { return $null }
    return $latest.FullName
}

function Write-SummaryJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Summary,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -Confirm:$false | Out-Null
    }

    $json = $Summary | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8NoBOM -WhatIf:$false -Confirm:$false
}

#endregion Helper Functions

#region Main Execution
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $resolvedRoot = Resolve-RepoRoot -Hint $RepoRoot
        if (-not $OutputPath) {
            $OutputPath = Join-Path $resolvedRoot 'logs/baseline-equivalence-summary.json'
        }

        # Compare output, compare logs, and the summary all land under logs/. Create it
        # up front rather than relying on some earlier step to have made it as a side
        # effect, which is how a missing directory previously surfaced as a late and
        # confusing WriteAllText failure partway through a run.
        $logsRoot = Join-Path $resolvedRoot 'logs'
        if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $logsRoot -Force -WhatIf:$false -Confirm:$false | Out-Null
        }

        $modelHint = Get-AgentModelHint -RepoRoot $resolvedRoot -Agent $Agent
        $models = @(Resolve-ModelList -Tier $Tier -Hint $modelHint -ModelOverride $Model)
        $primaryModel = $models[0]

        $outputRoot = Join-Path $resolvedRoot 'evals/results/baseline-equivalence'
        $runId = (Get-Date -AsUTC).ToString('yyyyMMddTHHmmssfffZ')

        $defaultVariantA = @{ kind = 'baseline'; name = 'baseline';   label = 'Baseline (A)';   description = ''; applied = @() }
        $defaultVariantB = @{ kind = 'agent';    name = $Agent;       label = $Agent;            description = ''; applied = @() }
        $variantA = Get-VariantMetadata -VariantYamlPath (Join-Path $resolvedRoot 'evals/baseline-equivalence/baseline/variant.yaml') -Default $defaultVariantA
        $variantB = Get-VariantMetadata -VariantYamlPath (Join-Path $resolvedRoot 'evals/baseline-equivalence/customized/variant.yaml') -Default $defaultVariantB
        $workspaceRoot = Join-Path $resolvedRoot 'evals/baseline-equivalence/customized/workspace'
        $variantB.applied = @(Get-AppliedArtifacts -WorkspaceRoot $workspaceRoot)
        $variants = @{ a = $variantA; b = $variantB; subject = [string]$variantB.name }

        Write-Host "Baseline equivalence: agent=$Agent tier=$Tier model(s)=$($models -join ',')" -ForegroundColor Cyan
        Write-Host "   Stimulus filter: $StimulusFilter" -ForegroundColor DarkGray
        Write-Host "   Summary output:  $OutputPath" -ForegroundColor DarkGray
        Write-Host "   Results root:    $outputRoot" -ForegroundColor DarkGray
        Write-Host "   Run id:          $runId" -ForegroundColor DarkGray

        # Baseline reuse is keyed on the inputs that would change baseline behavior. A
        # cached run captured under a different Vally version must not be reused, or a
        # tooling change would be attributed to the customization under test. The version
        # is read from the lockfile rather than by invoking the CLI, because the pinned
        # dependency is what actually determines the runtime and the read cannot fail
        # partway or cost a subprocess.
        $vallyVersion = 'unknown'
        $lockPath = Join-Path $resolvedRoot 'package-lock.json'
        if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
            try {
                # -AsHashtable is required: the lockfile's packages map uses an empty
                # string as the key for the root project, which ConvertFrom-Json rejects
                # when producing PSCustomObject.
                $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable
                $node = $lock.packages['node_modules/@microsoft/vally-cli']
                if ($node -and $node.version) { $vallyVersion = [string]$node.version }
            }
            catch {
                $null = $_
            }
        }
        $baselineCacheRoot = Join-Path $resolvedRoot 'evals/results/baseline-equivalence/_baseline-cache'
        Write-Host "   Vally version:   $vallyVersion" -ForegroundColor DarkGray

        $dependencyMap = $null
        $dependencyMapPath = Join-Path $resolvedRoot 'logs/agent-dependency-map.json'
        if (Test-Path -LiteralPath $dependencyMapPath -PathType Leaf) {
            try {
                $dependencyMap = Get-Content -LiteralPath $dependencyMapPath -Raw | ConvertFrom-Json
            }
            catch {
                $dependencyMap = $null
            }
        }

        $customizedWorkspacePath = $workspaceRoot
        $customizedSkillDirPath = Join-Path $outputRoot "$($models[0])/$runId/customized-skill-dir"
        $plannedCommands = Get-PlannedCommands -Models $models -StimulusFilter $StimulusFilter -OutputRoot $outputRoot -RunId $runId -JudgeModel $ComparisonJudgeModel -BaselineWorkspacePath '' -BaselineSkillDirPath '' -CustomizedWorkspacePath $customizedWorkspacePath -CustomizedSkillDirPath $customizedSkillDirPath

        if ($WhatIfPreference) {
            Write-Host "Dry-run mode: skipping live SDK calls." -ForegroundColor Yellow
            foreach ($cmd in $plannedCommands) {
                Write-Host "   $cmd" -ForegroundColor DarkGray
            }

            $dry = New-DryRunSummary `
                -Agent $Agent `
                -Tier $Tier `
                -Model $primaryModel `
                -StimulusFilter $StimulusFilter `
                -PlannedCommands $plannedCommands `
                -Variants $variants
            Write-SummaryJson -Summary $dry -Path $OutputPath
            Write-Host "Dry-run summary written: $OutputPath" -ForegroundColor Green
            exit 0
        }

        $totalRuns = 0
        $totalTies = 0
        $totalA = 0
        $totalB = 0
        $invariantFailures = 0
        $divergenceFailures = 0
        $dataQualityViolations = 0
        $totalJudgeErrors = 0
        $totalEquivalent = 0
        $totalEquivalentTies = 0
        $totalDivergence = 0
        $dataQualityDiagnostics = [System.Collections.Generic.List[string]]::new()

        # Policy and invariant membership come from the canonical library, because the
        # comparison JSONL identifies stimuli by name only.
        $canonical = Get-CanonicalStimulusPolicy -RepoRoot $resolvedRoot
        $canonicalPolicy = $canonical.Policy
        $canonicalInvariants = @($canonical.Invariants)
        Write-Host "   Canonical policy: $($canonicalPolicy.Count) stimulus/stimuli, $($canonicalInvariants.Count) declared invariant(s)" -ForegroundColor DarkGray
        $compareLogs = [System.Collections.Generic.List[string]]::new()
        $meanScores = [System.Collections.Generic.List[double]]::new()
        $winRates = [System.Collections.Generic.List[double]]::new()
        $ciLows = [System.Collections.Generic.List[double]]::new()
        $ciHighs = [System.Collections.Generic.List[double]]::new()

        foreach ($model in $models) {
            $aDir = Join-Path $outputRoot "$model/$runId/baseline"
            $bDir = Join-Path $outputRoot "$model/$runId/customized"
            $baselineWorkspacePath = Join-Path $outputRoot "$model/$runId/baseline-workspace"
            $baselineSkillDirPath = Join-Path $outputRoot "$model/$runId/baseline-skill-dir"
            foreach ($dir in @($aDir, $bDir, $baselineWorkspacePath, $baselineSkillDirPath)) {
                if (-not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
            }
            foreach ($dir in @($baselineWorkspacePath, $baselineSkillDirPath)) {
                if (Test-Path -LiteralPath $dir) {
                    Get-ChildItem -LiteralPath $dir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            foreach ($dir in @($aDir, $bDir)) {
                if (-not (Test-Path -LiteralPath $dir)) {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
            }

            # The customized side must be specific to the agent under test. Passing the
            # whole skills tree would load every skill for every agent, so two different
            # agents would produce identical customized runs and the comparison could not
            # tell them apart.
            $customizedSkillDirForModel = Join-Path $outputRoot "$model/$runId/customized-skill-dir"
            try {
                $customized = New-CustomizedEnvironment `
                    -RepoRoot $resolvedRoot `
                    -Agent $Agent `
                    -WorkspacePath $workspaceRoot `
                    -SkillDirPath $customizedSkillDirForModel `
                    -DependencyMap $dependencyMap
                $variantB.applied = @($customized.Applied)
                $variants.b = $variantB
                Write-Host "   Customized surface: $($customized.Applied.Count) artifact(s)" -ForegroundColor DarkGray
            }
            catch {
                # A customized environment that cannot be built is a divergence failure,
                # not a crash. Recording it keeps the summary readable and lets the
                # verdict reflect the problem instead of losing the run entirely.
                Write-Host "   Customized environment not materialized: $($_.Exception.Message)" -ForegroundColor Yellow
                $divergenceFailures++
                if (-not (Test-Path -LiteralPath $customizedSkillDirForModel)) {
                    New-Item -ItemType Directory -Path $customizedSkillDirForModel -Force | Out-Null
                }
            }

            # The baseline is identical for every agent, so running it per agent doubles
            # cost for no signal. Reuse a persisted baseline whenever the inputs that
            # shaped it are unchanged, and regenerate when they are not.
            $stimulusHash = Get-StimulusContentHash -SpecPath (Join-Path $resolvedRoot 'evals/baseline-equivalence/baseline/eval.yaml')
            $cacheKey = Get-BaselineCacheKey -Model $model -VallyVersion $vallyVersion -StimulusHash $stimulusHash
            $baselineRunDir = $null
            $baselineReused = $false
            if (-not $NoBaselineCache) {
                $baselineRunDir = Get-BaselineCacheEntry -CacheRoot $baselineCacheRoot -CacheKey $cacheKey
                if ($baselineRunDir) {
                    $baselineReused = $true
                    Write-Host "   Baseline: reusing cached run for $model (vally $vallyVersion)" -ForegroundColor DarkGray
                }
            }

            # The scope-language guard asserts the customized run names its own tracking
            # directory. Both eval specs are shared across every agent, so the guard is
            # always present and the per-agent value arrives through --param. An agent
            # that writes no tracking artifacts is exempt and reports as such, because a
            # vacuous guard that passed silently would repeat the defect this replaced.
            $scopeResolution = Resolve-AgentScopePattern -RepoRoot $resolvedRoot -Agent $Agent
            if ($scopeResolution.Exempt) {
                Write-Host "   Scope guard: exempt (agent '$Agent' declares no tracking scope)" -ForegroundColor DarkGray
            }
            else {
                Write-Host "   Scope guard: .copilot-tracking/$($scopeResolution.Scope)" -ForegroundColor DarkGray
            }

            $evalBaseline = @(
                'eval',
                '--eval-spec', 'evals/baseline-equivalence/baseline/eval.yaml',
                '--model', $model,
                '--output-dir', $aDir,
                '--workspace', $baselineWorkspacePath,
                '--skill-dir', $baselineSkillDirPath
            )
            $evalCustomized = @(
                'eval',
                '--eval-spec', 'evals/baseline-equivalence/customized/eval.yaml',
                '--model', $model,
                '--output-dir', $bDir,
                '--workspace', $workspaceRoot,
                '--skill-dir', $customizedSkillDirPath,
                '--param', "SCOPE_PATTERN=$($scopeResolution.Pattern)"
            )

            if ($baselineReused) {
                # A reused baseline was already graded when it was captured. Its invariant
                # tally is re-read from the cached run so the verdict still accounts for it.
                $baselineTally = Measure-DeclaredInvariantFailures -RunDir $baselineRunDir -InvariantNames $canonicalInvariants
                if ($baselineTally.HasSignal) {
                    $invariantFailures += $baselineTally.Failed
                }
                else {
                    # A cached baseline that yields no invariant signal is unusable, not
                    # clean. Treating it as zero failures would let a corrupted cache
                    # entry silently pass every later agent.
                    $dataQualityViolations++
                    $dataQualityDiagnostics.Add('Cached baseline produced no invariant signal.')
                }
            }
            else {
                $codeA = Invoke-VallyCommand -Arguments $evalBaseline
                $baselineRunDir = Resolve-LatestRunDir -OutputDir $aDir
                $baselineTally = Measure-DeclaredInvariantFailures -RunDir $baselineRunDir -InvariantNames $canonicalInvariants
                if ($baselineTally.HasSignal) {
                    $invariantFailures += $baselineTally.Failed
                }
                else {
                    # Previously a missing or unparsable report read as zero failures,
                    # so a baseline that never produced a usable result looked clean.
                    $dataQualityViolations++
                    $dataQualityDiagnostics.Add('Baseline run produced no invariant signal.')
                    if ($codeA -ne 0) { $invariantFailures++ }
                }

                if (-not $NoBaselineCache -and $baselineRunDir -and $codeA -eq 0 -and $baselineTally.HasSignal) {
                    $baselineRunDir = Save-BaselineCacheEntry `
                        -CacheRoot $baselineCacheRoot `
                        -CacheKey $cacheKey `
                        -RunDir $baselineRunDir `
                        -Model $model `
                        -VallyVersion $vallyVersion `
                        -StimulusHash $stimulusHash
                    Write-Host "   Baseline: cached for reuse by later agents" -ForegroundColor DarkGray
                }
            }
            foreach ($diagnostic in @($baselineTally.Diagnostics)) { $dataQualityDiagnostics.Add($diagnostic) }

            $codeB = Invoke-VallyCommand -Arguments $evalCustomized
            if ($codeB -ne 0) { $divergenceFailures++ }

            $aRunDir = $baselineRunDir
            $bRunDir = Resolve-LatestRunDir -OutputDir $bDir
            if (-not $aRunDir -or -not $bRunDir) {
                Write-Host "   Compare skipped: missing run dir (a=$aRunDir b=$bRunDir)" -ForegroundColor Yellow
                $divergenceFailures++
            }
            else {
                $compareJsonlPath = Join-Path $resolvedRoot "logs/vally-compare-$model-$runId.jsonl"
                # The judge is pinned explicitly. It was previously carried only by
                # compare.eval.yml, so deleting that file without naming a judge here
                # would silently fall back to a Vally default and change what the
                # comparison measures without any recorded decision.
                $compareArgs = @(
                    'compare',
                    '--judge-model', $ComparisonJudgeModel,
                    '--baseline', $aRunDir,
                    '--treatment', $bRunDir,
                    '--output', $compareJsonlPath
                )
                $compareLog = Join-Path $resolvedRoot "logs/vally-compare-$model-$runId.log"
                $resultC = Invoke-VallyCommandWithCapture -Arguments $compareArgs -LogPath $compareLog
                $compareFailed = $resultC.ExitCode -ne 0
                if ($compareFailed) { $divergenceFailures++ }
                $compareLogs.Add($compareLog)

                $jsonlLines = if (Test-Path -LiteralPath $compareJsonlPath) { @(Get-Content -LiteralPath $compareJsonlPath -Encoding utf8) } else { @() }
                $tally = Measure-CompareTrials -Lines $jsonlLines -StimulusPolicy $canonicalPolicy
                if ($tally.Total -le 0) {
                    Write-Host "   Compare emitted no parseable comparison records: $compareJsonlPath" -ForegroundColor Yellow
                    if (-not $compareFailed) { $divergenceFailures++ }
                }
                elseif ($tally.SummaryCount -le 0) {
                    Write-Host "   Compare records carried no summary statistics; cannot assess equivalence: $compareJsonlPath" -ForegroundColor Yellow
                    if (-not $compareFailed) { $divergenceFailures++ }
                }

                # Records that could not be scored are counted rather than dropped. An
                # unmatched trajectory or malformed record means the comparison is
                # incomplete, and reporting a tie ratio computed only from the survivors
                # would overstate equivalence.
                $structural = $tally.MalformedRecords + $tally.UnmatchedBaseline + $tally.UnmatchedTreatment + $tally.DuplicateTrials
                if ($structural -gt 0) {
                    $dataQualityViolations += $structural
                    Write-Host "   Data quality: $($tally.MalformedRecords) malformed, $($tally.UnmatchedBaseline) unmatched baseline, $($tally.UnmatchedTreatment) unmatched treatment, $($tally.DuplicateTrials) duplicate" -ForegroundColor Yellow
                }
                if ($tally.JudgeErrors -gt 0) {
                    Write-Host "   Judge errors: $($tally.JudgeErrors) of $($tally.Total + $tally.JudgeErrors) attempted trial(s)" -ForegroundColor Yellow
                }
                foreach ($diagnostic in @($tally.Diagnostics)) { $dataQualityDiagnostics.Add($diagnostic) }

                $totalRuns += $tally.Total
                $totalTies += $tally.Ties
                $totalA   += $tally.AWins
                $totalB   += $tally.BWins
                $totalJudgeErrors += $tally.JudgeErrors
                $totalEquivalent += $tally.EquivalentTotal
                $totalEquivalentTies += $tally.EquivalentTies
                $totalDivergence += $tally.DivergenceTotal
                if ($tally.SummaryCount -gt 0) {
                    $meanScores.Add([double]$tally.MeanScore)
                    $winRates.Add([double]$tally.WinRate)
                    $ciLows.Add([double]$tally.CiLow)
                    $ciHighs.Add([double]$tally.CiHigh)
                }
            }
        }

        $aggregateMeanScore = if ($meanScores.Count -gt 0) { ($meanScores | Measure-Object -Average).Average } else { 0.0 }
        $aggregateWinRate = if ($winRates.Count -gt 0) { ($winRates | Measure-Object -Average).Average } else { 0.0 }
        $aggregateCiLow = if ($ciLows.Count -gt 0) { ($ciLows | Measure-Object -Maximum).Maximum } else { 0.0 }
        $aggregateCiHigh = if ($ciHighs.Count -gt 0) { ($ciHighs | Measure-Object -Minimum).Minimum } else { 0.0 }

        $verdict = Get-VerdictFromAggregate `
            -Runs $totalRuns `
            -CiLow $aggregateCiLow `
            -CiHigh $aggregateCiHigh `
            -InvariantFailures $invariantFailures `
            -DivergenceFailures $divergenceFailures `
            -DataQualityViolations $dataQualityViolations `
            -Tier $Tier

        $summary = [ordered]@{
            agent              = $Agent
            tier               = $Tier
            model              = $primaryModel
            stimulusFilter     = $StimulusFilter
            runs               = $totalRuns
            ties               = $totalTies
            aWins              = $totalA
            bWins              = $totalB
            meanScore          = [math]::Round($aggregateMeanScore, 4)
            ciLow              = [math]::Round($aggregateCiLow, 4)
            ciHigh             = [math]::Round($aggregateCiHigh, 4)
            winRate            = [math]::Round($aggregateWinRate, 4)
            invariantFailures  = $invariantFailures
            divergenceFailures = $divergenceFailures
            dataQualityViolations = $dataQualityViolations
            judgeErrors        = $totalJudgeErrors
            judgeErrorRate     = if (($totalRuns + $totalJudgeErrors) -gt 0) { [math]::Round($totalJudgeErrors / ($totalRuns + $totalJudgeErrors), 6) } else { 0.0 }
            equivalentTrials   = $totalEquivalent
            equivalentTies     = $totalEquivalentTies
            divergenceTrials   = $totalDivergence
            tieRatio           = if ($totalEquivalent -gt 0) { [math]::Round($totalEquivalentTies / $totalEquivalent, 4) } else { 0.0 }
            dataQualityDiagnostics = @($dataQualityDiagnostics | Select-Object -First 50)
            verdict            = $verdict
            variants           = $variants
            compareLogs        = @($compareLogs)
        }

        Write-SummaryJson -Summary $summary -Path $OutputPath
        Write-Host "Summary written: $OutputPath ($verdict)" -ForegroundColor Cyan

        if ($Tier -eq 'pr') {
            exit 0
        }

        if ($verdict -eq 'fail') {
            Write-Host "Nightly verdict: fail" -ForegroundColor Red
            exit 1
        }

        exit 0
    }
    catch {
        Write-Error -ErrorAction Continue "Invoke-BaselineEquivalence failed: $($_.Exception.Message)"
        exit 3
    }
}
#endregion Main Execution
