---
id: "0011"
title: "Define the Vally baseline-equivalence evaluation policy"
description: "Fix the rubric source, gate separation, tier exit semantics, model scope, and judge-error posture for the baseline-equivalence suite so its verdict means one auditable thing."
author: "HVE Core Maintainers"
ms.date: "2026-08-01"
ms.topic: "reference"
status: "accepted"
proposed_date: "2026-08-01"
accepted_date: "2026-08-01"
deciders:
  - "HVE Core Maintainers"
consulted:
  - "HVE Core evaluation maintainers"
informed:
  - "hve-core contributors"
effort: "M"
tags:
  - "evaluation"
  - "vally"
  - "ci"
  - "baseline-equivalence"
affected_components:
  - "evals/baseline-equivalence/"
  - "scripts/evals/Invoke-BaselineEquivalence.ps1"
  - "scripts/evals/Invoke-VallyEvals.ps1"
  - "scripts/evals/lib/EquivalenceParsing.psm1"
  - "scripts/evals/lib/EquivalenceEnvironment.psm1"
supersedes: null
superseded-by: null
related:
  - path: "0002-adopt-vally-as-agent-and-skill-behavior-evaluation-framework.md"
    relation: "influenced-by"
    note: "Sets the evaluation policy for the baseline-equivalence guarantee ADR 0002 adopted Vally to provide."
  - path: "0010-stabilize-pr-time-vally-evaluation-execution.md"
    relation: "influenced-by"
    note: "Extends ADR 0010's typed-record parsing rule to the equivalence results reader and renames the tier vocabulary it described as PR and nightly."
asr_triggers:
  - kind: "maintainability"
    evidence: "The suite emitted a single verdict derived from a statistical comparison, so a failed customization guard and a statistically significant regression were indistinguishable in the reported result."
    note: "Two questions folded into one verdict left neither independently answerable or actionable."
  - kind: "compliance"
    evidence: "Comparison judging is model-backed, so the rubric source and judge model determine whether two runs are reproducibly comparable."
    note: "An unpinned judge or an implicit rubric makes a verdict unreproducible across runs."
  - kind: "maintainability"
    evidence: "The advisory and authoritative modes were named pr and nightly, which described CI triggers rather than exit policy, and each carried a different gating consequence."
    note: "Trigger-shaped names invited a caller to select an exit policy by accident."
success_criteria:
  - metric: "gate-separation"
    target: "every run reports equivalenceGate and documentedDivergenceGate independently, and verdict is the worse of the two"
    measurement_window: "every baseline-equivalence run"
    source: "scripts/evals/lib/EquivalenceParsing.psm1 and scripts/tests/evals/EquivalenceParsing.Tests.ps1"
  - metric: "structural-fail-closed"
    target: "zero-trial and data-quality failures report fail at every tier, including the advisory tier"
    measurement_window: "every baseline-equivalence run"
    source: "scripts/tests/evals/EquivalenceParsing.Tests.ps1"
  - metric: "contract-version-rejection"
    target: "a consumer reading an unsupported summary major version fails loudly rather than reading absent fields as zeros"
    measurement_window: "every equivalence dispatch"
    source: "scripts/tests/evals/Invoke-VallyEvals.Tests.ps1"
decisionMetadata:
  driverToTriggerMap:
    "Auditable verdict": "A single blended verdict could not distinguish an undocumented behavior change from a failed customization guard, so the two gates are reported and evaluated separately."
    "Reproducible judging": "Comparison is model-backed, so the rubric source and judge model are fixed and visible in the invocation rather than implied by a spec file."
    "Honest failure posture": "An incomplete comparison cannot evidence equivalence, so structural failures fail closed at every tier while statistical results stay advisory in the local loop."
    "Calibration honesty": "Thresholds that have not been calibrated are reported rather than enforced, so the gate never asserts a bar no one has validated."
    "Low local friction": "Contributors iterate against the suite locally, so the advisory tier never blocks on a model-backed statistical result while still failing closed on a structurally broken run."
---

## Context

The baseline-equivalence suite asks whether the hve-core customization layer changes underlying GitHub Copilot model behavior beyond the divergences the suite explicitly declares. ADR 0002 adopted Vally partly because `vally compare` offered that guarantee. ADR 0010 then corrected PR-time execution semantics and selected a faster low-profile model.

Neither ADR fixed the evaluation policy itself. The suite ran, but several policy questions were answered implicitly by whatever the driver happened to do:

* Which rubric judges a comparison, and which judge model applies it.
* Whether a failed customization guard and a statistically significant regression produce distinguishable results.
* What an advisory run means versus an authoritative one, and which failures are allowed to be advisory.
* Whether an uncalibrated threshold gates or reports.

Those answers were spread across a driver, a parser, and a CI dispatcher, and in some cases contradicted each other. The suite's verdict therefore did not mean one auditable thing, which is a problem for an evaluation whose entire purpose is producing a trustworthy signal.

## Decision Drivers

* Auditable verdict
* Reproducible judging
* Honest failure posture
* Calibration honesty
* Low local friction

## Considered Options

* Option A: Keep one blended verdict and document how to interpret it case by case.
* Option B: Separate the gates but keep the existing trigger-shaped tier names and the implicit rubric source.
* Option C: Separate the gates, fix the rubric and judge model explicitly, rename tiers to describe exit policy, and report uncalibrated thresholds instead of enforcing them.

## Decision Outcome

| Decision driver      | Option A: blended verdict | Option B: partial separation | Option C: full policy definition |
|----------------------|---------------------------|------------------------------|----------------------------------|
| Auditable verdict    | No                        | Yes                          | Yes                              |
| Reproducible judging | No                        | No                           | Yes                              |
| Honest failure posture | Partial                 | Partial                      | Yes                              |
| Calibration honesty  | No                        | No                           | Yes                              |
| Low local friction   | Yes                       | Yes                          | Yes                              |

Chosen option: **Option C**, because the policy questions are coupled. Separating the gates without fixing the rubric source leaves the verdict reproducible only by accident, and renaming tiers without defining which failures may be advisory leaves the exit policy ambiguous at the moment it matters most.

The decision has five parts.

**1. The rubric is Vally's embedded comparison default, and the judge model is pinned on the invocation.** `vally compare` treats `--eval-spec` as an optional override of its embedded rubric. The driver deliberately does not pass it, so the rubric source is the tool default rather than a repository file that could drift from it. The judge model is passed explicitly as `--judge-model`, defaulting to `claude-haiku-4.5`, so the pin is visible in the command rather than buried in a spec.

**2. Two gates are evaluated and reported independently.** The equivalence gate asks whether behavior that should not change stayed the same, reading confidence-interval bounds over the equivalent-policy population only. The documented-divergence gate asks whether declared customization guards held, reading per-guard conformance from the customized run. The `verdict` is the worse of the two. The 40 stimuli carry an explicit comparison policy tag: 33 `equivalent` and 7 `documented-divergence`, so intended divergence never enters the equivalence denominator.

**3. Tiers name their exit policy, not their trigger.** `devloop` is advisory and always exits 0. `ci` is authoritative and exits 1 on a failing verdict. The former `pr` and `nightly` names are rejected with a migration message rather than aliased, because they carried different exit policies and a silent alias would let a stale caller select the wrong one.

**4. Structural failures fail closed at every tier; statistical results are advisory only in `devloop`.** A run with zero trials or any data-quality violation reports `fail` even on `devloop`. An incomplete comparison cannot evidence equivalence regardless of who ran it, and reporting a pass from the records that happened to survive would assert something the run did not measure. Invariant, run-health, and guard-conformance failures downgrade to `warn` on `devloop` and `fail` on `ci`. A run that evaluated no divergence guards fails closed, because no signal is not conformance.

**5. Judge errors and thresholds are counted and reported, not enforced.** `judgeErrors` and `judgeErrorRate` appear in every summary but do not gate. Their acceptable bar is unresolved pending the calibration work, and a gate that enforces an uncalibrated threshold asserts a standard no one has validated. Model scope follows cost: `devloop` resolves an explicit `-Model` override, then the agent's frontmatter `model:` hint, then the low-cost default `gpt-5.6-luna`; `ci` sweeps a fixed three-model array.

The reporting contract carries `schemaVersion: "2.0.0"`. Consumers reject an unsupported major version loudly rather than reading absent fields as zeros, which previously let a renamed field degrade a successful run into a silent `runs=0` and `verdict=unknown`.

### Consequences

* Good, because a reviewer can tell from the summary alone whether a run failed because customization changed something it should not have, or because a declared guard did not hold.
* Good, because the judge model and rubric source are visible in the invocation, so two runs of the same commit are comparable.
* Good, because an incomplete or structurally broken run can never report a pass, at any tier.
* Good, because the local loop stays non-blocking, so contributors are not gated on a model-backed statistical result while iterating.
* Bad, because two gates and a schema version are more surface to understand than one verdict, and the reporting contract is now a versioned interface that downstream consumers must track.
* Bad, because judge-error and threshold enforcement remain open until calibration completes, so the suite currently detects a class of problem it does not yet gate on.

### Confirmation

Approval of the migration pull request confirms this decision. The gate separation, fail-closed rules, and contract-version rejection are each covered by tests in `scripts/tests/evals/EquivalenceParsing.Tests.ps1` and `scripts/tests/evals/Invoke-VallyEvals.Tests.ps1`, and those tests were verified to fail when the corresponding rule is removed.

## Pros and Cons of the Options

### Option A: Keep one blended verdict

* Good, because it is the smallest change and the existing consumers keep working unmodified.
* Bad, because the verdict conflates two independent questions, so an operator cannot act on a failure without re-reading the raw comparison output.
* Bad, because case-by-case interpretation guidance rots faster than code.

### Option B: Separate the gates only

* Good, because it resolves the most visible problem, which is the ambiguous verdict.
* Good, because it requires no change to the tier vocabulary or the CI dispatch surface.
* Bad, because the rubric source stays implicit, so a comparison remains reproducible only as long as nothing changes the spec files the judge might read.
* Bad, because trigger-shaped tier names continue to invite selecting an exit policy by accident.

### Option C: Full policy definition

* Good, because every policy question has one recorded answer that a reviewer can check against the code.
* Good, because the fail-closed and advisory rules are explicit, so the suite cannot quietly report a pass it did not measure.
* Bad, because it is the largest change and touches the driver, the parser, the dispatcher, and the reporting contract at once.

## Affected Components

* evals/baseline-equivalence/
* scripts/evals/Invoke-BaselineEquivalence.ps1
* scripts/evals/Invoke-VallyEvals.ps1
* scripts/evals/lib/EquivalenceParsing.psm1
* scripts/evals/lib/EquivalenceEnvironment.psm1

## More Information

* [evals/baseline-equivalence/](../../../evals/baseline-equivalence/) holds the stimulus corpus and the paired baseline and customized specs this policy governs; its [README.md](../../../evals/baseline-equivalence/README.md) documents the runtime behavior, the summary field contract, and the pass and fail interpretation rules.
* [scripts/evals/Invoke-BaselineEquivalence.ps1](../../../scripts/evals/Invoke-BaselineEquivalence.ps1) is the single entry point that owns tier validation, model resolution, the pinned judge invocation, and the exit policy in parts 1, 3, and 4.
* [scripts/evals/lib/EquivalenceParsing.psm1](../../../scripts/evals/lib/EquivalenceParsing.psm1) computes both gates and the verdict described in parts 2 and 4, and reads comparison and guard results.
* [scripts/evals/lib/EquivalenceEnvironment.psm1](../../../scripts/evals/lib/EquivalenceEnvironment.psm1) materializes the per-agent customized environment and derives the scope guard whose conformance the documented-divergence gate reads.
* [scripts/evals/Invoke-VallyEvals.ps1](../../../scripts/evals/Invoke-VallyEvals.ps1) dispatches the suite in CI and is the consumer that rejects an unsupported reporting-contract major version.
* ADR 0002 adopted Vally and identified the baseline-equivalence guarantee this policy governs.
* ADR 0010 corrected PR-time execution semantics; its typed-record parsing rule is extended here to the equivalence results reader, and the tier vocabulary it described as PR and nightly is renamed by part 3 of this decision.

---

🤖 *Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
