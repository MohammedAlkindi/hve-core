---
name: security-planning
description: Security planning reference set for operational buckets, STRIDE analysis, standards mapping, NIST control families, backlog scaffolding, and deterministic TM7 (.tm7) plus markdown dual-output generation.
license: MIT
user-invocable: true
---

# Security Planning

This skill packages the durable security-planning reference material used by the Security Planner: operational bucket guidance, STRIDE analysis patterns, standards cross-references, NIST control-family references, and security-specific backlog formats.

## When to use

Use this skill when you need to:

* Classify application components into the operational security buckets used during planning.
* Evaluate threats with STRIDE-based analysis, including AI-specific extensions when `raiEnabled` is true.
* Map bucket findings to standards references and control families without re-embedding long standard tables.
* Derive security-specific backlog priorities and RAI work item categories for Phase 5 handoff.
* Generate a dual-output TM7 model plus markdown report from a YAML/JSON threat-model spec for human-reviewed audit workflows.

### TM7 generation workflow

When the user asks for a TM7 threat model, the runtime can generate a `.tm7` file and a matching markdown report from the same spec. The generator supports the `pre-populated-comprehensive` and `diagram-only-defer-to-tmt` modes and can update an existing model with `--update`. Use the `generate_tm7.py` and `generate_markdown.py` entry points with `--template` to select a profile.

The `.tm7` output mirrors the Microsoft Threat Modeling Tool's real `SerializableModelData` DataContract and opens in the tool without the deserialization dialog. Fidelity is validated against the tool's own assemblies by `scripts/Deserialize-Tm7.ps1`, which the pytest suite runs when the tool is installed and skips cleanly otherwise. See [references/tm7-generation.md](references/tm7-generation.md) for the verified contract.

### Native TM7 visual feedback workflow

The skill also supports an opt-in, Windows-local feedback loop for the native Microsoft Threat Modeling Tool UI. The feature is off by default. The generator and standard validator keep their existing portable behavior when the feedback flags are absent. Native feedback is enabled only when `validate_tm7_with_tmt.py` is run with `--feedback-loop`, `--spec`, and `--overlay-output`; optional `--overlay-input`, `--max-iterations`, and `--require-feedback-evidence` refine the execution contract.

The current native workflow requires Microsoft Threat Modeling Tool 7.3.51110.1, a Windows desktop session, and UI Automation access. On a non-Windows host, or when no trusted installation is discovered, the run stops as `tmt-unavailable` under `--require-tmt` and as `skipped` without it; a discovered installation at the wrong version stops as `version-mismatch`. The validator uses exit codes `0` for success, `1` for validation failure, `2` for generic error, `3` for missing TMT, `4` for version mismatch, `5` for automation timeout, `6` for unexpected modal, `7` for missing feedback evidence, and `8` for feedback non-convergence.

Operator safety is part of the harness contract. While the native feedback loop is active, the operator must not use the mouse, keyboard, or switch windows, because the harness controls TMT windows and may open, close, and reopen the app for save/reopen validation. The harness emits a start notice before automation begins, progress updates for the baseline and each refinement candidate, and a release notice when the loop completes or aborts so the operator knows when control is returned.

The loop records one evidence bundle per run under the requested evidence directory. The top level contains `manifest.json`, `status.json`, `action.log`, and the `screenshots/`, `uia/`, `exports/`, `summaries/`, and `logs/` folders. Each iteration writes its own bundle under `iterations/00-baseline` and `iterations/01` through `iterations/03` as needed, with per-surface screenshots, UI Automation snapshots, summaries, and a generated candidate model such as `candidate-00-baseline.tm7` stored in that iteration folder. The loop writes iteration-scoped overlay payloads as `overlay.yaml` in the iteration bundle and a final overlay to the explicit `--overlay-output` path when execution stops. The overlay payload remains in `approval_state: pending`, and no runtime path or flag auto-promotes it to `approved` or rewrites the canonical baseline.

The current scoring logic keeps deterministic geometry gates separate from advisory screenshot heuristics. Geometry metrics use thresholds of `overlap_ratio > 0.03` for review, `overlap_ratio >= 0.01` for warn, `edge_node_intersections > 2` for review, `edge_crossing_count > 2` for review in non-dense layouts, `min_spacing_ratio < 0.24` for review, and a missing or incomplete surface capture as a review gate.

Screenshot heuristics remain advisory and are not treated as a semantic approval signal. Human semantic review is still the authority for whether a pending overlay is acceptable.

A Windows-native example uses the skill's locked Windows dependency group:

```bash
uv run --project .github/skills/project-planning/security-planning --group windows \
  python scripts/validate_tm7_with_tmt.py model.tm7 \
  --evidence-dir ./artifacts/feedback \
  --feedback-loop \
  --spec ./specs/model.yaml \
  --overlay-output ./artifacts/feedback/overlay.json \
  --max-iterations 3 \
  --require-feedback-evidence
```

The overlay contract is versioned and deterministic. It carries layout intent in the `zone_rules`, `node_rules`, `connector_rules`, and `surface_rules` collections, and it is invalidated unless a complete fingerprint block matches on all five of `spec_fingerprint`, `generator_profile_fingerprint`, `surface_identity_fingerprint`, `surface_zone_identity_fingerprint`, and `surface_flow_identity_fingerprint`.

The loop is bounded to a baseline run plus at most three refinement iterations, and it stops on a stable reason from `automated-ready-pending-human`, `repeated-defect-no-improvement`, `max-iterations`, `evidence-incomplete`, `semantic-regression`, `candidate-generation-failed`, `overlay-validation-failed`, `tmt-unavailable`, `skipped`, `version-mismatch`, `automation-timeout`, `unexpected-modal`, or `harness-error`. `automated-ready-pending-human` means the automated gates passed and a human review is still required; it is not an approval.

See [references/tm7-generation.md](references/tm7-generation.md) for the full CLI surface, the mode-flag behavior, and the operator runbook covering prerequisites, abort, recovery, and rollback.

### Agent-assisted visual review

Some layout defects never reach a metric. TM7 persists no connector label geometry and UI Automation exposes no label element, so label collisions, unreadable label text, and visual crowding are invisible to the deterministic gates. An agent that reads the iteration screenshots alongside `feedback-manifest.json` and each surface's UI Automation tree can see them and author corrections into the overlay the harness publishes. The capability is documented; it has not yet been demonstrated end to end on a real defect.

Two facts govern that work and cannot be inferred from the artifacts. Rendered geometry is available only from the UI Automation tree, in screen pixels at a uniform 1.5x zoom, so every rule value must be converted to model units. And `handle_point` is the only connector-label lever that reaches the renderer, where TMT draws the label centred on that point; `label_offset` moves nothing that is drawn.

A stopped run publishes the overlay seed the agent edits. The layout-exhaustion stops `repeated-defect-no-improvement` and `max-iterations` write a valid overlay with correct fingerprints and all four rule collections empty; a correctness or environment stop publishes no seed at all.

See [references/tm7-generation.md](references/tm7-generation.md) for the protocol, the accepted rule fields, the worked coordinate translation, and the constraints that bound an agent-authored overlay.

> [!CAUTION]
> **Disclaimer:** This agent is an assistive tool only. It does not provide legal, regulatory, or compliance advice and does not replace professional security review boards, penetration testing teams, compliance auditors, legal counsel, or other qualified human reviewers. The output consists of suggested actions and considerations to support a user's own internal security review and decision-making. All security plans, threat models, security models, and mitigation recommendations generated by this tool must be independently reviewed and validated by appropriate security and compliance reviewers before use. Outputs from this tool do not constitute security approval, compliance certification, or regulatory sign-off.

Before treating the generated `.tm7` or markdown output as authored or final, present the spec and the generated result to the human and wait for explicit confirmation.

## Skill layout

Load the reference file that matches the phase or topic you need.

| Reference                                                                          | Topic                                                                                     |
|------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| [references/00-index.md](references/00-index.md)                                   | Navigation catalog and consolidated attribution                                           |
| [references/operational-buckets.md](references/operational-buckets.md)             | Operational bucket definitions, GS overlay, and classification guidance                   |
| [references/stride-model.md](references/stride-model.md)                           | STRIDE methodology, AI extensions, risk matrix, and data-flow analysis                    |
| [references/standards-cross-reference.md](references/standards-cross-reference.md) | Bucket-to-standards mapping table and component mapping output format                     |
| [references/nist-control-families.md](references/nist-control-families.md)         | NIST 800-53 priority tiers and NIST AI RMF subcategory mappings                           |
| [references/backlog-formats.md](references/backlog-formats.md)                     | Security-specific prioritization and RAI work item categories                             |
| [references/data-classification.md](references/data-classification.md)             | Public-safe data-classification taxonomy, tiers/categories/retention, and schema mapping  |
| [references/threat-model-review.md](references/threat-model-review.md)             | Threat-model completeness checklist, PASS/INCOMPLETE verdict, and gap list                |
| [references/tm7-generation.md](references/tm7-generation.md)                       | TM7 input schema, dual-output generation contract, profile mapping, and emission contract |

The skill ships public defaults for the taxonomy and the completeness checklist. Organization-specific internal details such as internal data-type taxonomies, internal auth service names, and internal review-gate steps are supplied through a private overlay referenced by state.overlayConfigPath and are never embedded in the public skill.

## Attribution

The durable reference content in this skill is organized by reference file and summarized in [references/00-index.md](references/00-index.md). See that index for the consolidated attribution and delegation notes.
