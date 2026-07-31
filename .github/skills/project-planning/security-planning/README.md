---
title: Security Planning TM7 generation and feedback tools
description: Current generator, validator, feedback, schemas, and references shipped with the Security Planning skill
ms.date: 2026-07-16
ms.topic: reference
---

# Security Planning TM7 Generation

This package contains the current TM7 generation, validation, and native feedback assets for the Security Planning skill.

## Contents

- scripts/generate_tm7.py: deterministic TM7 generation entry point with optional overlay replay
- scripts/validate_tm7_with_tmt.py: native Microsoft Threat Modeling Tool harness entry point for probe, validate, compare-generation-state, upgrade-template, and feedback-loop modes
- scripts/tm7_visual_feedback.py: feedback-domain module for overlay validation, geometry metrics, ranking, and convergence
- assets/template-profiles/: bundled template-profile metadata used by the generator
- assets/schemas/tm7-layout-overlay.schema.json: versioned overlay schema for deterministic replay
- assets/schemas/tm7-visual-feedback-manifest.schema.json: evidence-manifest schema for native feedback runs
- references/tm7-generation.md: public TM7 contract, workflow notes, and current feedback-loop documentation
- SECURITY.md: skill-level STRIDE model for local generation, TMT automation, UI Automation, screenshots, and evidence handling
- tests/: focused regression coverage for generation, validation, and feedback-loop behavior

## Notes

The template-profile bundle is intentionally vendor-neutral and uses the verified generic stencil TypeIds from the current implementation. The native feedback loop is opt-in and remains local to Windows with the pinned TMT 7.3.51110.1 requirement. It writes redacted evidence bundles under the requested evidence directory, creates root-level `manifest.json`, `status.json`, `action.log`, and the `screenshots/`, `uia/`, `exports/`, `summaries/`, and `logs/` folders, writes iteration bundles under `iterations/00-baseline` and `iterations/01` through `iterations/03` as needed, keeps overlay output in `approval_state: pending`, and stops with a stable reason such as `gates-cleared`, `repeated-defect-no-improvement`, `max-iterations`, `evidence-incomplete`, `semantic-regression`, `tmt-unavailable`, `version-mismatch`, `automation-timeout`, or `unexpected-modal`.

🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.
