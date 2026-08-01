---
title: Baseline Equivalence Suite
description: 'Pairs identical probes across baseline and customized environments to assert only documented divergences appear'
author: HVE Core Team
ms.date: 2026-07-23
---

## Purpose

This suite proves that the hve-core customization layer does not alter underlying GitHub Copilot
model behavior beyond documented divergences. The agent layer is the independent variable:
identical stimuli run twice against the same GHCP model, once against an empty baseline environment
and once against an environment that materializes a target agent (frontmatter, subagents, skills,
and `copilot-instructions.md`) into a fresh temp workdir. The `vally compare` comparison-mode
judge then asks whether the customized response differs from the baseline only in ways the
curated allow-list permits.

The suite answers a single question per stimulus: did customization change the model's answer, or did it change only the framing the customization explicitly requires?

## Layout

```text
evals/baseline-equivalence/
├── README.md           # this file
├── baseline/
│   ├── eval.yaml       # executable spec for the empty baseline run (invariant graders + response-quality)
│   └── variant.yaml    # baseline variant metadata
├── customized/
│   ├── eval.yaml       # executable spec for the materialized agent run (adds customized_required / customized_disallow)
│   └── variant.yaml    # RPI Agent variant metadata
├── stimuli.yml         # 40 prompts across 8 subcategories at 5 per subcategory
```

The baseline and customized specs are self-contained vally `eval` documents. The PowerShell driver invokes each spec in turn with `vally eval --eval-spec` and then joins the two run directories with `vally compare --judge-model <model> --baseline <baseline-run-dir> --treatment <customized-run-dir> --output <path>.jsonl`.

Comparison uses Vally's embedded default rubric. The judge model is pinned explicitly on the compare invocation by the driver's `-ComparisonJudgeModel` parameter, so the pin is visible in the command rather than buried in a spec file.

## How to Run

The PowerShell driver at [scripts/evals/Invoke-BaselineEquivalence.ps1](../../scripts/evals/Invoke-BaselineEquivalence.ps1) is the single entry point. Invoke it through the npm wrapper:

```bash
# devloop (default): single primary model, advisory verdict, always exits 0
npm run ci:eval:equivalence -- -Agent rpi-agent -Tier devloop

# ci: three-model sweep, authoritative verdict, exits non-zero on fail
npm run ci:eval:equivalence -- -Agent rpi-agent -Tier ci

# Dry run: print planned vally commands and emit a placeholder summary without SDK calls
npm run ci:eval:equivalence -- -Agent rpi-agent -WhatIf
```

The former `pr` and `nightly` tier names are rejected with a migration message rather than aliased, because they carried different exit policies and a silent alias would let a stale caller select the wrong one.

The driver writes a machine-readable summary to `logs/baseline-equivalence-summary.json` and per-environment trajectories under `evals/results/`. The trajectory directories are gitignored.

### Driver output contract

Each `vally compare --judge-model <model> --baseline <baseline-run-dir> --treatment <customized-run-dir> --output <path>.jsonl` invocation writes one or more typed `type: "comparison"` records to `logs/vally-compare-<model>-<runId>.jsonl` (a console `.log` capture of the same invocation is kept alongside for troubleshooting, at the paths listed in `compareLogs`).
`Measure-CompareTrials` in [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1) reads that JSONL, tallies each non-errored trial's `winner` (`baseline` / `treatment` / `tie`), and carries forward the record's `summary` statistics (signed mean score, 95% confidence interval, win rate).
The driver aggregates one JSONL per model into a single JSON summary; the summary is the contract every downstream consumer reads. It carries `schemaVersion: "2.0.0"`, and consumers reject an unsupported major version rather than reading absent fields as zeros.
The compare invocation deliberately omits `--fail-on-regression` so `Get-EquivalenceGateResults` remains the single equivalence authority instead of double-counting the same regression signal.

| Field                                                                | Type        | Meaning                                                                                                                                                                   |
|----------------------------------------------------------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `schemaVersion`                                                      | string      | Reporting contract version. `2.0.0` is the current contract; consumers fail loudly on an unsupported major                                                                |
| `agent`                                                              | string      | Agent slug under test (matches `-Agent`)                                                                                                                                  |
| `tier`                                                               | string      | `devloop` (advisory, exit 0) or `ci` (authoritative, exit 1 on fail)                                                                                                      |
| `model`                                                              | string      | Primary model for the run: `devloop` resolves `-Model` override, then frontmatter `model:` hint, then the cheap default (`gpt-5.6-luna`); `ci` runs its fixed model array |
| `runs`                                                               | int         | Total non-errored comparison trials parsed across all `--output` JSONL files                                                                                              |
| `ties`                                                               | int         | Trials with `winner: "tie"`; neither environment showed a clear preference                                                                                                |
| `baselineWins`                                                       | int         | Trials with `winner: "baseline"`; the customization underperformed                                                                                                        |
| `treatmentWins`                                                      | int         | Trials with `winner: "treatment"`; the customization outperformed                                                                                                         |
| `meanScore`                                                          | number      | Unweighted average, across records and models, of signed treatment-relative `summary.meanScore` values (positive favors the customization); reporting only                |
| `ciLow`                                                              | number      | Conservative maximum lower bound of `summary.ciLow` across records and models                                                                                             |
| `ciHigh`                                                             | number      | Conservative minimum upper bound of `summary.ciHigh` across records and models                                                                                            |
| `winRate`                                                            | number      | Unweighted average, across records and models, of `summary.winRate` values; reporting only                                                                                |
| `invariantFailures`                                                  | int         | Declared-invariant violations read from the baseline run's structured results                                                                                             |
| `runHealthFailures`                                                  | int         | Run-integrity signals: nonzero `vally eval` or `vally compare` exits, missing run directories, and unparseable compare output                                             |
| `divergenceGuardFailures`                                            | int         | Declared `customized_required` and `customized_disallow` guards that failed in the customized run                                                                         |
| `divergenceGuardsEvaluated`                                          | int         | Declared guards actually evaluated; zero means the gate had no signal and fails closed                                                                                    |
| `failedDivergenceGuards`                                             | list        | Up to 50 `stimulus/guard` identifiers for the failing guards                                                                                                              |
| `dataQualityViolations`                                              | int         | Malformed, unmatched, or duplicate comparison records; any nonzero value fails closed at every tier                                                                       |
| `judgeErrors`, `judgeErrorRate`                                      | int, number | Errored comparison trials and their share of attempted trials; counted and reported, not yet enforced                                                                     |
| `equivalentTrials`, `equivalentTies`, `divergenceTrials`, `tieRatio` | int, number | Population split by comparison policy, so intended divergence is excluded from the equivalence denominator                                                                |
| `equivalenceGate`                                                    | string      | Whether behavior that should not change stayed the same                                                                                                                   |
| `documentedDivergenceGate`                                           | string      | Whether declared customization guards held                                                                                                                                |
| `verdict`                                                            | string      | Worst of the two gates; see [Pass and Fail Interpretation](#pass-and-fail-interpretation)                                                                                 |
| `variants`                                                           | list        | Per-model variant metadata (model id, baseline run directory, customized run directory)                                                                                   |
| `compareLogs`                                                        | list        | Absolute paths to every captured `vally compare` console log; the sibling `--output` JSONL lives at `logs/vally-compare-<model>-<runId>.jsonl`                            |

The gates are derived by `Get-EquivalenceGateResults` in [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1); the exact rule is documented below.

`meanScore` and `winRate` are unweighted diagnostics, not pooled estimates.

### Lint commands

The baseline-equivalence specs live in two subdirectories (`baseline/eval.yaml` and `customized/eval.yaml`) so the driver can invoke them as a paired set. The repository-wide `npm run ci:eval:lint:vally` task runs `vally lint --eval-spec evals/` and discovers both nested specs. Use the explicit commands below for targeted validation:

| Command                                                                  | Purpose                                                                            |
|--------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| `vally lint --eval-spec evals/baseline-equivalence/baseline/eval.yaml`   | Schema-validate the empty baseline spec                                            |
| `vally lint --eval-spec evals/baseline-equivalence/customized/eval.yaml` | Schema-validate the materialized customized spec (includes the divergence graders) |
| `npm run ci:eval:run:equivalence`                                        | Run both specs end to end via `vally eval --eval-spec ...` (no driver, no compare) |

Run both `vally lint` commands before pushing a change to this suite. The presence linter ([scripts/evals/Test-StimulusPresence.ps1](../../scripts/evals/Test-StimulusPresence.ps1)) is wired into the changed-artifact lane and is documented in [docs/contributing/evals-ci.md](../../docs/contributing/evals-ci.md).

## How to Extend Per-Agent

Onboarding a new agent (for example `security-planner`) does not require harness code changes:

1. The driver materializes the target agent's surface into an isolated workspace automatically.
   [scripts/evals/lib/EquivalenceEnvironment.psm1](../../scripts/evals/lib/EquivalenceEnvironment.psm1) copies the agent file, its declared
   instructions, its subagents, `copilot-instructions.md`, and only the skills that agent actually references. Two different agents therefore
   produce different customized environments, which is the property the comparison depends on. The baseline runs against a deliberately emptied
   workspace and is cached and reused across agents, keyed on model, Vally version, and stimulus content hash.
2. The scope-language guard is derived automatically. `Resolve-AgentScopePattern` reads the first `.copilot-tracking/<scope>` reference in the agent body and passes it to the customized run as `--param SCOPE_PATTERN=...`. An agent that references no tracking directory is reported as exempt in the run output rather than silently passing a guard that asserts nothing.
3. Add per-agent divergence graders inline in [customized/eval.yaml](customized/eval.yaml) (`customized_required` / `customized_disallow` graders attached to the relevant stimuli) for any behavior the derived scope pattern cannot capture.

The driver resolves the agent's frontmatter `model:` hint automatically. No new PowerShell, no new stimulus library, and no new judge prompt are required unless the agent's domain materially differs from the existing corpus.

Persona loading remains outside Vally's flag surface. The agent file and `copilot-instructions.md` are present in the customized workspace, so the `instruction-bleed` stimuli have material to act on, but the boundary this suite measures is skill-and-instruction level rather than persona level. Any threshold proposal must state that boundary.

## Onboarded Agents

The suite covers the agents listed below. `Tracking Scope` is the directory the scope-language guard asserts for that agent, derived at run time from the agent file; `exempt` marks an advisory agent that writes no tracking artifacts and therefore has no scope to assert. Stimulus coverage counts the entries in [stimuli.yml](stimuli.yml) whose `tags.agent` includes the agent slug; an empty count means the agent relies on shared corpus coverage rather than per-agent backlinks.

| Agent                        | Collection       | Tracking Scope                               | Stimulus Coverage | Status        |
|------------------------------|------------------|----------------------------------------------|-------------------|---------------|
| ado-backlog-manager          | ado              | `.copilot-tracking/workitems`                | 0                 | authoritative |
| ado-prd-to-wit               | ado              | `.copilot-tracking/workitems`                | 0                 | authoritative |
| adr-creation                 | project-planning | `.copilot-tracking/adr-plans`                | 0                 | authoritative |
| agentic-workflows            | root             | exempt (no tracking scope)                   | 0                 | authoritative |
| agile-coach                  | project-planning | exempt (no tracking scope)                   | 0                 | authoritative |
| arch-diagram-builder         | project-planning | exempt (no tracking scope)                   | 0                 | authoritative |
| brd-builder                  | project-planning | `.copilot-tracking/brd-sessions`             | 2                 | authoritative |
| code-review                  | coding-standards | `.copilot-tracking/pr`                       | 3                 | authoritative |
| dependency-reviewer          | root             | exempt (no tracking scope)                   | 1                 | authoritative |
| documentation                | hve-core         | `.copilot-tracking/documentation`            | 4                 | authoritative |
| dt-coach                     | design-thinking  | `.copilot-tracking/design-thinking-sessions` | 0                 | authoritative |
| dt-learning-tutor            | design-thinking  | exempt (no tracking scope)                   | 0                 | authoritative |
| eval-dataset-creator         | data-science     | exempt (no tracking scope)                   | 0                 | authoritative |
| experiment-designer          | experimental     | `.copilot-tracking/mve`                      | 0                 | advisory      |
| gen-data-spec                | data-science     | exempt (no tracking scope)                   | 0                 | authoritative |
| gen-jupyter-notebook         | data-science     | exempt (no tracking scope)                   | 0                 | authoritative |
| gen-streamlit-dashboard      | data-science     | exempt (no tracking scope)                   | 0                 | authoritative |
| github-backlog-manager       | github           | `.copilot-tracking/research`                 | 2                 | authoritative |
| issue-triage                 | root             | exempt (no tracking scope)                   | 3                 | authoritative |
| jira-backlog-manager         | jira             | `.copilot-tracking/jira-issues`              | 0                 | authoritative |
| jira-prd-to-wit              | jira             | `.copilot-tracking/jira-issues`              | 0                 | authoritative |
| meeting-analyst              | project-planning | `.copilot-tracking/prd-sessions`             | 0                 | authoritative |
| network-isa95-planner        | project-planning | `.copilot-tracking/plans`                    | 0                 | authoritative |
| pptx                         | experimental     | `.copilot-tracking/ppt`                      | 0                 | advisory      |
| prd-builder                  | project-planning | `.copilot-tracking/prd-sessions`             | 2                 | authoritative |
| product-manager-advisor      | project-planning | exempt (no tracking scope)                   | 2                 | authoritative |
| rai-planner                  | rai-planning     | `.copilot-tracking/rai-plans`                | 0                 | authoritative |
| rpi-agent                    | hve-core         | `.copilot-tracking/rpi-sessions`             | 23                | authoritative |
| security-planner             | security         | `.copilot-tracking/security-plans`           | 0                 | authoritative |
| security-reviewer            | security         | `.copilot-tracking/security`                 | 0                 | authoritative |
| sssc-planner                 | security         | `.copilot-tracking/security-plans`           | 0                 | authoritative |
| system-architecture-reviewer | project-planning | exempt (no tracking scope)                   | 0                 | authoritative |
| test-streamlit-dashboard     | data-science     | exempt (no tracking scope)                   | 0                 | authoritative |
| ux-ui-designer               | project-planning | exempt (no tracking scope)                   | 0                 | authoritative |

The `security-planner`, `security-reviewer`, and `sssc-planner` rows show stimulus coverage `0` for the same reason: their domains (threat modeling and RAI impact, security review and vulnerability assessment, and supply-chain hardening) do not map to any of the v1 stimulus categories. They are covered indirectly through dependency-map dispatch when other agents invoke their subagents, and through the derived scope-language guard on every baseline-equivalence run.

The `adr-creation`, `agile-coach`, `arch-diagram-builder`, `meeting-analyst`, `network-isa95-planner`, `system-architecture-reviewer`, and `ux-ui-designer` rows show stimulus coverage `0`
because their project-planning domains do not map to any of the v1 stimulus categories. They are covered indirectly through dependency-map dispatch when other agents invoke them as subagents
or via their declared instruction and skill chains, and through the derived scope-language guard on every baseline-equivalence run.

The `ado-backlog-manager`, `ado-prd-to-wit`, `jira-backlog-manager`, and `jira-prd-to-wit` rows show stimulus coverage `0` because their domains (Azure DevOps and Jira work-item lifecycle, PRD-to-work-item planning) do not map to any of the v1 stimulus categories. They are covered indirectly through dependency-map dispatch when other agents invoke them as subagents, and through the derived scope-language guard on every baseline-equivalence run.

The `dt-coach` and `dt-learning-tutor` rows show stimulus coverage `0` because their Design Thinking coaching and curriculum domains do not map to any of the v1 stimulus categories. They are covered indirectly through dependency-map dispatch when other agents invoke them as subagents, and through the derived scope-language guard on every baseline-equivalence run.

The `eval-dataset-creator`, `gen-data-spec`, `gen-jupyter-notebook`, `gen-streamlit-dashboard`, and `test-streamlit-dashboard` rows show stimulus coverage `0` because their data-science and dashboard-generation domains do not map to any of the v1 stimulus categories. They are covered indirectly through dependency-map dispatch when other agents invoke them as subagents, and through the derived scope-language guard on every baseline-equivalence run.

The `code-review` agent is backlinked onto the two existing `code-qa` walkthrough prompts (`code-walkthrough-fizzbuzz` and `code-error-explain-indexerror`) because step-by-step code explanation is a natural fit for a review-focused agent, and onto `multi-turn-correct-misunderstanding` because standards-driven correction of a prior mistake is a natural fit for that agent's domain.

The `brd-builder`, `prd-builder`, and `product-manager-advisor` agents are backlinked onto the two most generic `ambiguous-spec` prompts (`vague-feature` and `update-thing`) because requirements elicitation is a natural response to under-specified asks.

The `experiment-designer` and `pptx` rows show stimulus coverage `0` because their experimental domains (MVE / hypothesis design and slide-deck generation) do not map to any of the v1 stimulus categories. They land with `advisory` status per collection tier convention and are covered indirectly through dependency-map dispatch when other agents invoke them as subagents, and through the derived scope-language guard on every baseline-equivalence run.

The `rai-planner` row shows stimulus coverage `0` because its responsible-AI risk-assessment domain (NIST AI RMF, AI STRIDE, impact assessment) does not map to any of the v1 stimulus categories. It is covered indirectly through dependency-map dispatch and through the derived scope-language guard on every baseline-equivalence run.

The `agentic-workflows` row shows stimulus coverage `0` because its cross-cutting domain (workflow orchestration) does not map to any of the v1 stimulus categories. It is covered indirectly through dependency-map dispatch and through the derived scope-language guard on every baseline-equivalence run.

The `dependency-reviewer` agent is backlinked onto `customization-boundary-edit-package-json` because reviewing a new package dependency entry is a natural fit for that agent's domain.
The `documentation` agent is backlinked onto `customization-boundary-edit-readme` because verifying a README modification is a natural fit for that agent's documentation-coverage focus.
The `issue-triage` and `github-backlog-manager` agents are backlinked onto the generic `ambiguous-spec` prompts (`vague-feature`, `update-thing`, plus `fix-bug` for `issue-triage`)
because classifying under-specified asks and grooming vague work items are natural responses for triage and backlog-management agents.

## Pass and Fail Interpretation

The driver reports two independent gates via `Get-EquivalenceGateResults` in [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1), and `verdict` is the worse of the two.

**Equivalence gate.** Asks whether behavior that should not change stayed the same. Equivalence holds when the conservative cross-model bounds (`ciLow`/`ciHigh`) straddle zero, meaning every contributing model's 95% confidence interval includes zero. These bounds are not a pooled confidence interval. Opposing significant model results can produce `ciLow > ciHigh`; that intentionally fails the straddle test and triggers review.

* `runs <= 0` or `dataQualityViolations > 0`: `fail` at **every** tier, including `devloop`. An incomplete comparison cannot evidence equivalence regardless of who runs it, and the summary is left on disk so the cause can be diagnosed from `compareLogs` and the sibling `--output` JSONL.
* `invariantFailures > 0` or `runHealthFailures > 0`: `warn` on `devloop`, `fail` on `ci`.
* Otherwise, `pass` when the interval straddles zero (`ciLow <= 0 <= ciHigh`); `warn` on `devloop` or `fail` on `ci` when it excludes zero on either side.

**Documented-divergence gate.** Asks whether the declared customization guards actually held, read per-guard from the customized run.

* `divergenceGuardsEvaluated == 0`: `fail`. No guard signal is not conformance; a run that evaluated nothing cannot evidence that its declared divergence held.
* `divergenceGuardFailures > 0`: `warn` on `devloop`, `fail` on `ci`.

Only the equivalent-policy population contributes to `tieRatio`, so intended divergence is not scored as an equivalence failure. There is no `inconclusive` bucket and no fixed tie-ratio or symmetry threshold; the 0.80 tie-ratio and `|aWins - bWins|` symmetry heuristic from the Vally 0.6-era driver no longer applies. `devloop` verdicts stay advisory; `ci` verdicts gate. This split keeps the per-PR signal low-friction while preserving a hard regression gate.

A confidence interval excluding zero on the negative side (`ciHigh < 0`) signals a statistically significant regression: the baseline outperformed the customization.
This is the same condition `vally compare --fail-on-regression` would flag, which this driver deliberately does not pass on the compare invocation so the gate function remains the single equivalence authority (see [Driver output contract](#driver-output-contract)).
A confidence interval excluding zero on the positive side (`ciLow > 0`) signals the opposite: an unexpected, statistically significant improvement. Both directions are documented-divergence review triggers for an equivalence suite, since its purpose is proving no undocumented behavior change occurred rather than proving the customization is better.

## Stimulus Shape

Each entry in [stimuli.yml](stimuli.yml) uses these keys:

| Key                   | Applies To      | Meaning                                                                                                                                           |
|-----------------------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `name`                | both            | Stimulus identifier; must match across both specs so `vally compare` pairs trajectories by name                                                   |
| `prompt`              | both            | The verbatim user-facing prompt sent to both environments                                                                                         |
| `invariants`          | both            | Named graders from `grader_registry.invariants` that must pass on both the baseline and customized trajectories                                   |
| `customized_required` | customized only | Named graders from `grader_registry.customized_required` that must match the customized trajectory; documents an expected divergence              |
| `customized_disallow` | customized only | Named graders from `grader_registry.customized_disallow` that must NOT match the customized trajectory; catches unintended persona or scope bleed |
| `tags`                | filter          | `category` and `subcategory` for stimulus selection and reporting                                                                                 |

Trajectory invariants live at the spec level (not per stimulus) and apply across the baseline-customized pair: model equality (`metadata.model` matches across A and B), baseline-no-customized-skills (the baseline trajectory invokes no skills the customization layer expects), and response length parity within plus or minus 25 percent.

## Declared Divergence Allow-List

The customization layer is allowed to differ from the baseline only in ways the suite declares. Those declarations live in [stimuli.yml](stimuli.yml)
as `customized_required` and `customized_disallow` guards, mirrored into [customized/eval.yaml](customized/eval.yaml) and enforced by the
synchronization check. On the `customization-boundary` stimuli the guards are the `routes-through-rpi-lifecycle` requirement and the per-agent
`scope-language` pattern; `writes-outside-allowed-dirs` is a shared invariant asserting neither environment names an out-of-scope filesystem
location. Anything outside those declarations that diverges from baseline is treated as a regression, not a feature.

This framing is intentional. The suite is not a free-form quality grader; it asks the narrow question "does customization change anything beyond what we said it would?" Curated allowances keep the question crisp.

## Non-Goals

The suite does NOT assert:

* Latency or wall-clock time. Both environments share the same model; throughput differences are not the customization layer's responsibility.
* Streaming behavior. `vally compare` grading runs on completed responses.
* Multi-turn conversation dynamics. v1 stimuli are single-turn.
* MCP server behavior. Both environments configure `mcpServers: {}` to isolate the agent layer from external tool variability.
* Absolute billing cost. Length parity within plus or minus 25 percent bounds the proxy for cost; dollar amounts are out of scope.
* Cross-model behavioral equivalence. Each run compares baseline to customized against the SAME model; differences between models (for example `claude-opus-4.7` vs `gpt-5.5`) are the model vendor's domain.

## References

* [evals/README.md](../README.md) for the suite catalog and shared anti-patterns.
* [baseline/eval.yaml](baseline/eval.yaml) and [customized/eval.yaml](customized/eval.yaml) for the executable specs invoked by the driver.
* [scripts/evals/Invoke-BaselineEquivalence.ps1](../../scripts/evals/Invoke-BaselineEquivalence.ps1) for driver parameters and exit codes.
* [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1) for the parser and verdict aggregator that produce `logs/baseline-equivalence-summary.json`.
* [docs/contributing/evals-ci.md](../../docs/contributing/evals-ci.md) for the stimulus presence linter, the spec-text linter, moderation lanes, and CI auth contract.

🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.
