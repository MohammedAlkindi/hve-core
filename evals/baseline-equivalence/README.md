---
title: Baseline Equivalence Suite
description: 'Pairs identical probes across baseline and customized environments to assert only documented divergences appear'
author: HVE Core Team
ms.date: 2026-08-06
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
├── compare.eval.yml    # comparison-judging contract: one rubric per canonical stimulus
├── stimuli.yml         # 40 prompts across 8 subcategories at 5 per subcategory
```

The baseline and customized specs are self-contained vally `eval` documents. The PowerShell driver invokes each spec in turn with `vally eval --eval-spec` and then joins the two run directories with `vally compare --eval-spec evals/baseline-equivalence/compare.eval.yml --judge-model <model> --baseline <baseline-run-dir> --treatment <customized-run-dir> --output <path>.jsonl`.

Comparison judging reads `compare.eval.yml`, supplied explicitly through `--eval-spec`. Without it, `vally compare` falls back to the rubric
embedded in the baseline trajectory and then to a general-purpose preference rubric that asks which response is better. Preference judging cannot
measure equivalence: two runs of one configuration still differ in wording, so the judge keeps picking winners and the tie ratio reports judge
tie-breaking rather than behavioral sameness. Each entry in the contract states the behavioral contract instead: `equivalent` stimuli instruct a tie
when both variants satisfy it, and `documented-divergence` stimuli state the expected direction and an explicit tie condition. The judge model is
pinned separately through the driver's `-ComparisonJudgeModel` parameter, so both the rubric and the judge are visible in the command.

The contract is validated deterministically before any model-backed run. A missing, duplicated, unknown, or policy-mismatched entry fails `npm run ci:eval:lint:schema` and the Pester sync suite rather than silently changing what the tie ratio measures.

## How to Run

The PowerShell driver at [scripts/evals/Invoke-BaselineEquivalence.ps1](../../scripts/evals/Invoke-BaselineEquivalence.ps1) is the single entry point. Invoke it through the npm wrapper:

```bash
# devloop (default): single primary model, advisory verdict, always exits 0
npm run ci:eval:equivalence -- -Agent rpi-agent -Tier devloop

# ci: two-model sweep (gpt-5.6-luna, claude-sonnet-4.6), authoritative verdict, exits non-zero on fail
npm run ci:eval:equivalence -- -Agent rpi-agent -Tier ci

# Dry run: print planned vally commands and emit a placeholder summary without SDK calls
npm run ci:eval:equivalence -- -Agent rpi-agent -WhatIf
```

The former `pr` and `nightly` tier names are rejected with a migration message rather than aliased, because they carried different exit policies and a silent alias would let a stale caller select the wrong one.

`rpi-agent` is the only equivalence subject. The corpus backlinks nine agents, but its customization-boundary stimuli and guards encode the RPI
agent's contract, so another agent would fail them for reasons unrelated to equivalence. Those backlinks identify related artifacts for indexing;
they do not select subjects. The corpus is also excluded from generic tag-filtered dispatch, which previously produced partial and zero-stimulus
runs that reported success without measuring anything. Extending coverage to the remaining agents requires per-subject conditional guards and is
deferred until one clean run under the restored comparison contract exists.

The driver writes a machine-readable summary to `logs/baseline-equivalence-summary.json` and per-environment trajectories under `evals/results/`. The trajectory directories are gitignored.

### Driver output contract

Each `vally compare --eval-spec evals/baseline-equivalence/compare.eval.yml --judge-model <model> --baseline <baseline-run-dir> --treatment <customized-run-dir> --output <path>.jsonl` invocation writes one or more typed `type: "comparison"` records to `logs/vally-compare-<model>-<runId>.jsonl` (a console `.log` capture of the same invocation is kept alongside for troubleshooting, at the paths listed in `compareLogs`).
`Measure-CompareTrials` in [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1) reads that JSONL, tallies each non-errored trial's `winner` (`baseline` / `treatment` / `tie`), and carries forward the record's `summary` statistics (signed mean score, 95% confidence interval, win rate).
The driver aggregates one JSONL per model into a single JSON summary; the summary is the contract every downstream consumer reads. It carries `schemaVersion: "2.0.0"`, and consumers reject an unsupported major version rather than reading absent fields as zeros.
The compare invocation deliberately omits `--fail-on-regression` so `Get-EquivalenceGateResults` remains the single equivalence authority instead of double-counting the same regression signal.

| Field                                                                | Type        | Meaning                                                                                                                                                                                         |
|----------------------------------------------------------------------|-------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `schemaVersion`                                                      | string      | Reporting contract version. `2.0.0` is the current contract; consumers fail loudly on an unsupported major                                                                                      |
| `agent`                                                              | string      | Agent slug under test (matches `-Agent`)                                                                                                                                                        |
| `tier`                                                               | string      | `devloop` (advisory, exit 0) or `ci` (authoritative, exit 1 on fail)                                                                                                                            |
| `model`                                                              | string      | Primary model for the run: `devloop` resolves `-Model` override, then frontmatter `model:` hint, then the cheap default (`gpt-5.6-luna`); `ci` runs its fixed model array                       |
| `runs`                                                               | int         | Total non-errored comparison trials parsed across all `--output` JSONL files                                                                                                                    |
| `ties`                                                               | int         | Trials with `winner: "tie"`; neither environment showed a clear preference                                                                                                                      |
| `baselineWins`                                                       | int         | Trials with `winner: "baseline"`; the customization underperformed                                                                                                                              |
| `treatmentWins`                                                      | int         | Trials with `winner: "treatment"`; the customization outperformed                                                                                                                               |
| `meanScore`                                                          | number      | Unweighted average, across records and models, of signed treatment-relative `summary.meanScore` values (positive favors the customization); reporting only                                      |
| `ciLow`                                                              | number      | Conservative maximum lower bound of `summary.ciLow` across records and models; reporting only, not a gate input                                                                                 |
| `ciHigh`                                                             | number      | Conservative minimum upper bound of `summary.ciHigh` across records and models; reporting only, not a gate input                                                                                |
| `winRate`                                                            | number      | Unweighted average, across records and models, of `summary.winRate` values; reporting only                                                                                                      |
| `invariantFailures`                                                  | int         | Declared-invariant violations read from the baseline run's structured results                                                                                                                   |
| `runHealthFailures`                                                  | int         | Run-integrity signals: missing run directories, unparseable compare output, a nonzero `vally compare` exit, and a nonzero `vally eval` exit only when that run produced no usable grader signal |
| `divergenceGuardFailures`                                            | int         | Declared `customized_required` and `customized_disallow` guards that failed in the customized run                                                                                               |
| `divergenceGuardsEvaluated`                                          | int         | Declared guards actually evaluated; zero means the gate had no signal and fails closed                                                                                                          |
| `failedDivergenceGuards`                                             | list        | Up to 50 `stimulus/guard` identifiers for the failing guards                                                                                                                                    |
| `dataQualityViolations`                                              | int         | Malformed, unmatched, duplicate, missing, or unexpected records across comparison and declared-population reconciliation; any nonzero value fails closed at every tier                          |
| `dataQualityDiagnostics`                                             | list        | Up to 50 human-readable diagnostic strings explaining the counted data-quality violations; diagnostic aid, not a contractual enumeration                                                        |
| `judgeErrors`, `judgeErrorRate`                                      | int, number | Errored comparison trials and their share of attempted trials; counted and reported, not yet enforced                                                                                           |
| `equivalentTrials`, `equivalentTies`, `divergenceTrials`, `tieRatio` | int, number | Population split by comparison policy, so intended divergence is excluded from the equivalence denominator; `tieRatio` is the equivalence gate input                                            |
| `equivalenceGate`                                                    | string      | Whether behavior that should not change stayed the same                                                                                                                                         |
| `documentedDivergenceGate`                                           | string      | Whether declared customization guards held                                                                                                                                                      |
| `verdict`                                                            | string      | Worst of the two gates; see [Pass and Fail Interpretation](#pass-and-fail-interpretation)                                                                                                       |
| `variants`                                                           | list        | Per-model variant metadata (model id, baseline run directory, customized run directory)                                                                                                         |
| `compareLogs`                                                        | list        | Absolute paths to every captured `vally compare` console log; the sibling `--output` JSONL lives at `logs/vally-compare-<model>-<runId>.jsonl`                                                  |

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
   produce different customized environments, which is the property the comparison depends on. The baseline runs against the same shared seed project but no agent or
   customization surface, and is cached and reused across agents, keyed on model, Vally version, and a content hash covering the baseline spec plus the seed.
2. Divergence guards are declared inline per stimulus. Each `customization-boundary` stimulus names the specific completion claim its subject must
   not make, so a guard is satisfiable by prompt-appropriate behavior rather than by incidental vocabulary. `Resolve-AgentScopePattern` remains
   available in [scripts/evals/lib/EquivalenceEnvironment.psm1](../../scripts/evals/lib/EquivalenceEnvironment.psm1) for the deferred per-subject
   guard work, but stage 1 supplies no derived guard parameter, because a parameter no spec consumes would report a guard that never ran.
3. Add per-agent divergence graders inline in [customized/eval.yaml](customized/eval.yaml) (`customized_required` / `customized_disallow` graders attached to the relevant stimuli) for any behavior the shared guards cannot capture.

The driver resolves the agent's frontmatter `model:` hint automatically. No new PowerShell, no new stimulus library, and no new judge prompt are required unless the agent's domain materially differs from the existing corpus.

Persona loading remains outside Vally's flag surface. The agent file and `copilot-instructions.md` are present in the customized workspace, so the `instruction-bleed` stimuli have material to act on, but the boundary this suite measures is skill-and-instruction level rather than persona level. Any threshold proposal must state that boundary.

## Agent Coverage

Any agent in `.github/agents/` can be materialized without being registered anywhere. The driver copies the target agent's surface into an isolated
workspace at run time, so there is no onboarding list to join and no per-agent harness code to add. Stage 1 nevertheless evaluates `rpi-agent`
alone, because the customization-boundary guards encode that agent's contract; running another subject against them would report a failure the
run did not contain. Per-subject conditional guards are the deferred work that turns materialization into meaningful multi-agent coverage.

What does vary per agent is stimulus backlinking. Most stimuli are shared corpus prompts that any agent runs; a subset carries an explicit `tags.agent` backlink marking it as characteristic of that agent's domain. Those backlinks are the only per-agent data in this suite, and they are counted from [stimuli.yml](stimuli.yml):

| Agent                   | Backlinked Stimuli | Why                                                                     |
|-------------------------|--------------------|-------------------------------------------------------------------------|
| rpi-agent               | 23                 | The suite's primary subject; carries the RPI lifecycle and scope guards |
| documentation           | 4                  | README and documentation-coverage prompts                               |
| code-review             | 3                  | Code walkthrough, error explanation, and correcting a prior mistake     |
| issue-triage            | 3                  | Under-specified asks that need classification                           |
| brd-builder             | 2                  | Requirements elicitation on vague feature requests                      |
| github-backlog-manager  | 2                  | Grooming vague work items                                               |
| prd-builder             | 2                  | Requirements elicitation on vague feature requests                      |
| product-manager-advisor | 2                  | Requirements elicitation on vague feature requests                      |
| dependency-reviewer     | 1                  | Reviewing a new package dependency entry                                |

Counts sum to more than 40 because a stimulus may backlink several agents. An agent absent from this table is still fully runnable; it simply has no domain-specific prompt in the v1 corpus and is exercised through the shared stimuli and its derived scope guard.

## Pass and Fail Interpretation

The driver reports two independent gates via `Get-EquivalenceGateResults` in [scripts/evals/lib/EquivalenceParsing.psm1](../../scripts/evals/lib/EquivalenceParsing.psm1), and `verdict` is the worse of the two.

**Equivalence gate.** Asks whether behavior that should not change stayed the same. Equivalence holds when the conservative cross-model bounds (`ciLow`/`ciHigh`) straddle zero, meaning every contributing model's 95% confidence interval includes zero. These bounds are not a pooled confidence interval. Opposing significant model results can produce `ciLow > ciHigh`; that intentionally fails the straddle test and triggers review.

* `runs <= 0` or `dataQualityViolations > 0`: `fail` at **every** tier, including `devloop`. An incomplete comparison cannot evidence equivalence regardless of who runs it, and the summary is left on disk so the cause can be diagnosed from `compareLogs` and the sibling `--output` JSONL.
* `invariantFailures > 0` or `runHealthFailures > 0`: `warn` on `devloop`, `fail` on `ci`.
* Otherwise, `pass` when the equivalent-only tie ratio meets the floor (`tieRatio >= 0.80`); `warn` on `devloop` or `fail` on `ci` when it falls below. An `equivalentTrials` count of zero fails closed at every tier instead, because a ratio over zero trials is the absence of the measurement rather than a low score.

**Documented-divergence gate.** Asks whether the declared customization guards actually held, read per-guard from the customized run.

* `divergenceGuardsEvaluated == 0`: `fail`. No guard signal is not conformance; a run that evaluated nothing cannot evidence that its declared divergence held.
* `divergenceGuardFailures > 0`: `warn` on `devloop`, `fail` on `ci`.

Only the equivalent-policy population contributes to `tieRatio`, so intended divergence is not scored as an equivalence failure. There is no `inconclusive` bucket.
The `0.80` tie-ratio floor is inherited from the Vally 0.6-era driver rather than calibrated against the current corpus, so it is provisional and is tuned together with the configured trial count: at `runs: 5` across 35 equivalent stimuli the denominator is 175 trials, and the floor tolerates at most 35 non-tie trials.
The win-count symmetry heuristic from that era no longer applies. `devloop` verdicts stay advisory; `ci` verdicts gate. This split keeps the per-PR signal low-friction while preserving a hard regression gate.

`ciLow` and `ciHigh` are reporting-only diagnostics and are not gate inputs. Vally computes them over every compared stimulus, including the documented-divergence ones, so a strong expected win there could otherwise fail equivalence even when every equivalent trial tied. Read them as context for a failing tie ratio, not as the decision.

## Stimulus Shape

Each entry in [stimuli.yml](stimuli.yml) uses these keys:

| Key                   | Applies To      | Meaning                                                                                                                                           |
|-----------------------|-----------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `name`                | both            | Stimulus identifier; must match across both specs so `vally compare` pairs trajectories by name                                                   |
| `prompt`              | both            | The verbatim user-facing prompt sent to both environments                                                                                         |
| `invariants`          | both            | Named graders that gate the verdict. Measured on the baseline run, so a gating invariant must be evidence a reasonable baseline always produces   |
| `customized_required` | customized only | Named graders from `grader_registry.customized_required` that must match the customized trajectory; documents an expected divergence              |
| `customized_disallow` | customized only | Named graders from `grader_registry.customized_disallow` that must NOT match the customized trajectory; catches unintended persona or scope bleed |
| `tags`                | filter          | `category` and `subcategory` for stimulus selection and reporting                                                                                 |

A grader may run without gating. Omitting it from `invariants` while leaving it in `graders` keeps it executing and keeps its per-trial result in the run output, but removes it from the verdict.

That split exists because invariants are read from the baseline run only: a grader that records how the *uncustomized* model chose to respond cannot distinguish "the customization layer changed behavior" from "the underlying model answered differently," which is the only question this suite asks.
`asks-clarifying-question` and `mentions-print-paren` report under that rule.
`mentions-scripts-or-deps` still gates, because its stimulus reads a file the seed workspace provides and intermittent failure means the read itself is unreliable.

Reporting-without-gating is not a way to quiet a failing check. It applies when the grader measures the baseline model's preference rather than the customization's effect, and the reasoning belongs in the stimulus entry alongside the change.

Trajectory invariants live at the spec level (not per stimulus) and apply across the baseline-customized pair: model equality (`metadata.model` matches across A and B), baseline-no-customized-skills (the baseline trajectory invokes no skills the customization layer expects), and response length parity within plus or minus 25 percent.

## Declared Divergence Allow-List

The customization layer is allowed to differ from the baseline only in ways the suite declares. Those declarations live in [stimuli.yml](stimuli.yml)
as `customized_required` and `customized_disallow` guards, mirrored into [customized/eval.yaml](customized/eval.yaml) and enforced by the
synchronization check. On the `customization-boundary` stimuli each guard names the specific completion claim the customized variant must not make,
such as `avoids-external-write-claim` or `avoids-scope-bypass-edit-claim`; `writes-outside-allowed-dirs` is a shared invariant asserting neither
environment names an out-of-scope filesystem location. Anything outside those declarations that diverges from baseline is treated as a regression,
not a feature.

Guards assert observable behavior rather than vocabulary. An earlier revision required RPI lifecycle wording and the agent's tracking directory name
on every response, including replies to prompts as small as writing one temporary file. Every declared guard failed on every trial while the
responses themselves were on-topic, so the gate reported a customization failure that the runs did not contain.

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
