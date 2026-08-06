---
title: Method 02 Standards and Licensing Catalog
description: Catalog of candidate UX standards and their licensing posture for reuse in this repository.
sidebar_position: 7
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 02: Standards and licensing catalog for UX tooling

Track A desk research. Classifies candidate standards against the repository licensing posture in `.github/instructions/hve-core/licensing-posture.instructions.md`.

Class shorthand:

* **PD** — public domain (US government work). Verbatim permitted with attribution.
* **W3C** — W3C Document License. Paraphrase-first; verbatim normative quotes permitted with the canonical URL and W3C attribution line.
* **CC** — Creative Commons (BY or 0). Follow the specific license.
* **OGL** — UK Open Government Licence v3.0. Reuse with attribution.
* **OSS** — code license (tooling, not prose).
* **CITE-ONLY** — never reproduced in this repository under any circumstance.

## Tier 1 — Safe to build reference material from

| Standard                                               | Class     | Why it matters here                                                                                                                                                                                  |
|--------------------------------------------------------|-----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| WCAG 2.2                                               | W3C       | Baseline success criteria. Already vendored in the `accessibility` skill.                                                                                                                            |
| WAI-ARIA 1.2                                           | W3C       | Roles, states, properties.                                                                                                                                                                           |
| ARIA Authoring Practices Guide (APG)                   | W3C       | Widget patterns. Already in the `accessibility` skill.                                                                                                                                               |
| **WAI-ARIA Graphics Module**                           | W3C       | `graphics-document`, `graphics-object`, `graphics-symbol`. **The missing piece for the trajectory chart problem.** Not currently referenced anywhere in this repo.                                   |
| **SVG Accessibility API Mappings**                     | W3C       | How SVG structure maps to accessibility APIs. Directly governs recharts output. Not currently referenced.                                                                                            |
| **ATAG 2.0** (Authoring Tool Accessibility Guidelines) | W3C       | Part A: the authoring tool's own UI is accessible. Part B: the tool helps authors produce accessible content. **This is the governing standard for what we are building.** Not currently referenced. |
| WCAG-EM (Evaluation Methodology)                       | W3C       | Structured conformance evaluation procedure — sampling, scoping, reporting. Gives the review workflow a real methodology instead of "run axe."                                                       |
| Cognitive Accessibility (COGA)                         | W3C       | Already in the `accessibility` skill. Relevant to alert triage and dense data.                                                                                                                       |
| Section 508 / US Access Board                          | PD        | Verbatim safe. Already in the `accessibility` skill.                                                                                                                                                 |
| ISE Engineering Playbook                               | CC BY 4.0 | Design process, Design Ops, usability characteristics. Repo precedent exists in `adr-standards.instructions.md`.                                                                                     |
| U.S. Web Design System (USWDS)                         | PD        | Design-token and component patterns from a government design system.                                                                                                                                 |
| GOV.UK Design System / Service Manual                  | OGL v3.0  | Strong, genuinely reusable patterns; notably good on error handling and service journeys.                                                                                                            |
| Design Tokens Community Group format                   | W3C CG    | Interoperable token definition format for P9.                                                                                                                                                        |
| Open UI                                                | W3C CG    | Component semantics research.                                                                                                                                                                        |

## Tier 2 — Usable with care

| Standard                     | Class                            | Constraint                                                                                                                                                                          |
|------------------------------|----------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Material Design              | Apache 2.0 (code) / CC BY (docs) | Attribution required; avoid brand assets.                                                                                                                                           |
| Fluent UI                    | MIT (code)                       | Playbook names it as the ISE default. Code only — docs and brand are separate.                                                                                                      |
| System Usability Scale (SUS) | Widely treated as free to use    | Provenance is 1986 Brooke / Digital Equipment Corp. **Verify before vendoring the instrument text.** Paraphrase the method; do not reproduce the 10 items without confirming terms. |
| NASA-TLX                     | PD (NASA)                        | Workload measurement. Useful for operator-under-pressure scenarios.                                                                                                                 |
| Microsoft Inclusive Design   | Microsoft proprietary site       | The three principles are already paraphrased in the CC BY 4.0 playbook — **cite the playbook, not the toolkit site**, to stay inside a clean license.                               |

## Tier 3 — Cite only, never reproduce

| Standard                            | Class                         | Note                                                                                                                                                                                         |
|-------------------------------------|-------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| EN 301 549                          | CITE-ONLY (ETSI)              | Already classified in repo posture. Link the catalog entry; copy nothing.                                                                                                                    |
| ISO 9241-11 (usability definitions) | CITE-ONLY (ISO)               | **Live pitfall.** The playbook's effectiveness/efficiency/satisfaction triad derives from ISO 9241-11. Source any such text from the CC BY playbook or write original prose. Never from ISO. |
| ISO 9241-210 (human-centred design) | CITE-ONLY (ISO)               | Same pitfall for process-model language.                                                                                                                                                     |
| Nielsen's 10 Usability Heuristics   | CITE-ONLY (NN/g, copyrighted) | **Highest practical risk.** Routinely copy-pasted verbatim across the industry. The playbook links to it. Express as original prose or omit; never paste the canonical list.                 |

## Tooling licenses

| Tool                   | License    | Note                                                                     |
|------------------------|------------|--------------------------------------------------------------------------|
| axe-core               | MPL 2.0    | Already wrapped by the `accessibility` skill scanner.                    |
| Accessibility Insights | MIT        | Named by the playbook.                                                   |
| Playwright             | Apache 2.0 | Already used by `docs/docusaurus` e2e and the `vscode-playwright` skill. |
| eslint-plugin-jsx-a11y | MIT        | Already active in the viewer.                                            |
| Storybook              | MIT        | Named by the playbook for P10.                                           |

## The headline finding

Three W3C specifications directly address the exact gap Method 1 uncovered, and **none of them is referenced anywhere in this repository today**:

1. **WAI-ARIA Graphics Module** — semantics for charts and diagrams.
2. **SVG Accessibility API Mappings** — how SVG structure surfaces to assistive technology.
3. **ATAG 2.0** — the standard for authoring tools that help authors produce accessible content.

ATAG 2.0 deserves particular attention. The tooling under design here *is an authoring tool*. ATAG Part B is a published, W3C-licensed, structurally complete answer to the question "what does it mean for a tool to help its users produce accessible output?" That is the design brief for this project, already written down, already in a license class we can build reference material from.

The earlier assumption A2 ("the gap is knowledge grounding") was recorded as unvalidated. It is now **partially supported** — but not in the way the original request implied. The missing knowledge was never WCAG. It was the graphics and authoring-tool specs nobody had reached for.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
