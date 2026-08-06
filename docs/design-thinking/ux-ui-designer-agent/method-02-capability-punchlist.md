---
title: Method 02 Candidate Capability Punch List
description: Candidate UX capabilities with evidence grade for each entry.
sidebar_position: 8
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 02: Candidate capability punch list

**Fidelity warning.** This is premature synthesis, produced on request during Method 2. Method 2's discipline is raw-data capture; theming and prioritization belong to Method 3. Treat every row as a **candidate**, not a decision. Evidence column states what actually supports each item today.

Evidence key:

* **Measured** — verified against repository or code state.
* **Document** — supported by desk research on published guidance.
* **Assumed** — no supporting evidence yet; carried from the original request.

## C1 — Standards reference pack (extend the existing accessibility skill)

| #    | Capability                                        | Evidence            | Note                                                                                  |
|------|---------------------------------------------------|---------------------|---------------------------------------------------------------------------------------|
| C1.1 | WAI-ARIA Graphics Module reference                | Document            | Directly addresses trajectory/detection charts. Absent from repo.                     |
| C1.2 | SVG Accessibility API Mappings reference          | Document            | Governs recharts SVG output. Absent from repo.                                        |
| C1.3 | ATAG 2.0 reference (Parts A and B)                | Document            | Governing standard for the tooling itself. Absent from repo.                          |
| C1.4 | WCAG-EM evaluation methodology reference          | Document            | Replaces "run axe" with a real sampling and reporting procedure.                      |
| C1.5 | Data-visualization accessibility patterns         | Document + Measured | Original prose. The frontier area; standards are thin, reasoning must be constructed. |
| C1.6 | Time-based media and synchronized-stream patterns | Measured            | Viewer has multi-camera video with no track elements.                                 |

## C2 — Authoring capabilities (assets the tooling emits)

Mapped to the playbook inventory in `method-02-findings-playbook-assets.md`.

| #     | Capability                                             | Playbook ref | Evidence | Note                                                                                                                                                        |
|-------|--------------------------------------------------------|--------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| C2.1  | Desired Outcomes                                       | P1           | Document | Playbook step 1. Agent does not produce it.                                                                                                                 |
| C2.2  | Personas including disabled users by default           | P2           | Document | Playbook is explicit and unambiguous here.                                                                                                                  |
| C2.3  | UX trade study                                         | P3           | Document | Playbook's actual decision instrument.                                                                                                                      |
| C2.4  | Usability requirements with measurable characteristics | P7           | Document | Source wording from CC BY playbook, never ISO 9241-11.                                                                                                      |
| C2.5  | Accessibility requirements bound to specific surfaces  | P6           | Measured | Current agent emits generic prose; viewer shows generic prose is insufficient.                                                                              |
| C2.6  | **Surface semantics specification**                    | none         | Measured | No playbook or standard equivalent. Declares what a non-visual user must be able to perceive and do for a given data surface. The genuinely novel artifact. |
| C2.7  | Usability test plan                                    | P8           | Document | Quant + qual per playbook.                                                                                                                                  |
| C2.8  | Design tokens / design system definition               | P9           | Document | Viewer already has tokens; format spec available (DTCG).                                                                                                    |
| C2.9  | Journey map                                            | P15          | Assumed  | Existing agent output. Value unvalidated.                                                                                                                   |
| C2.10 | JTBD analysis                                          | P14          | Assumed  | Existing agent output. Value unvalidated. Not in playbook.                                                                                                  |

## C3 — Evidence and observation capabilities

| #    | Capability                                 | Evidence | Note                                                                                       |
|------|--------------------------------------------|----------|--------------------------------------------------------------------------------------------|
| C3.1 | Runtime surface inventory                  | Measured | `Accessibility Surface Inventory` subagent already exists. Reuse, do not rebuild.          |
| C3.2 | axe scan integration                       | Measured | `accessibility` skill already ships `scripts/scan.py`. Reuse.                              |
| C3.3 | Screen capture                             | Measured | `vscode-playwright` skill exists; docs site has Playwright wired. Connect, do not rebuild. |
| C3.4 | Flow traversal / interaction-path analysis | Measured | Partially exists (`site-crawl.spec.ts`). Nothing equivalent for app surfaces.              |
| C3.5 | Keyboard-reachability audit                | Measured | Viewer's chart range-selection is pointer-only. Generic axe does not catch this.           |
| C3.6 | Assistive-technology narration preview     | Assumed  | "What would a screen reader actually say here?" No existing capability found.              |

## C4 — Loop-closure capabilities

The gap named in Method 1: verification exists, authoring exists, nothing connects them.

| #    | Capability                                  | Evidence | Note                                                                     |
|------|---------------------------------------------|----------|--------------------------------------------------------------------------|
| C4.1 | Design intent → executable check generation | Measured | Emit specs that become Playwright/axe assertions. ATAG Part B territory. |
| C4.2 | Scan findings → design authoring feedback   | Measured | Docs platform runs 17 a11y specs; nothing feeds design.                  |
| C4.3 | Suppression / deferral tracking             | Assumed  | `eslint-disable jsx-a11y` scan not yet run (Track A2 outstanding).       |
| C4.4 | Coverage gap reporting                      | Document | WCAG-EM sampling: which surfaces were never evaluated.                   |

## C5 — Integration capabilities

| #    | Capability                                  | Evidence | Note                                                                                                                                                  |
|------|---------------------------------------------|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| C5.1 | Skill callable from the standalone UX agent | Measured | Agent currently has zero backing skills.                                                                                                              |
| C5.2 | DT Method 7/8 integration                   | Document | Hi-fi and testing — real systems exist to observe. Natural fit.                                                                                       |
| C5.3 | DT Method 5/6 integration                   | Document | **Conflict.** Method 6's Prototype Builder hat enforces anti-polish. Standards-conformant specs are what it pushes back on. Unresolved from Method 1. |
| C5.4 | Code-review perspective integration         | Measured | `Code Review Accessibility` subagent already exists.                                                                                                  |
| C5.5 | Accessibility Planner handoff               | Measured | Six-phase planner already exists with backlog handoff.                                                                                                |

## Cross-cutting observations

**Substantially more exists than the original request assumed.** C3.1, C3.2, C3.3, C5.4, and C5.5 are all present in the repository today. The initial framing implied building a screen-capture and scanning system from scratch; the measured finding is that the missing piece is connective tissue, not tooling.

**One capability has no precedent anywhere.** C2.6 (surface semantics specification) is not in the playbook, not in WCAG, and not produced by any existing agent. It is the direct answer to the viewer's actual failure. It is also the highest-risk item, because there is no reference implementation to copy.

**Two capabilities rest on nothing but the original request.** C2.9 and C2.10 — journey maps and JTBD — are the current agent's only outputs and have zero validating evidence. They may be the most valuable things here or the least. Nobody has asked a builder.

**One item is a known unresolved conflict.** C5.3 should not be attempted until the Method 6 fidelity tension has an answer.

## Recommended next evidence, not next build

* Run Track A2 (`eslint-disable jsx-a11y` suppression scan) — resolves C4.3 and reveals whether accessibility was deferred deliberately or never surfaced.
* Run Track A4 (existing agent against a viewer surface) — resolves whether Finding 1's vocabulary mismatch is real.
* Run B1 (one builder interview) — the only thing that can validate or kill C2.9, C2.10, and the whole C2 ordering.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
