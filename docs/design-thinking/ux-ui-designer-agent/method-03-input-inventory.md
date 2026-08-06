---
title: Method 03 Input Inventory and Coverage Assessment
description: Inventory of synthesis inputs and an assessment of what the evidence does and does not cover.
sidebar_position: 9
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 03: Input inventory and coverage assessment

Phase 1 of Method 3. Catalogs Method 1 and Method 2 inputs before clustering, and states honestly what the evidence base can and cannot support.

## Input inventory

| ID  | Input                                                                                                                                                       | Source type           | Method | Fidelity              |
|-----|-------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------|--------|-----------------------|
| I1  | Owner problem report ("the ux for the data viewer [...] jumbled inaccessible hunk of code")                                                                 | Stakeholder statement | 1      | Direct, single source |
| I2  | Viewer frontend code inventory (~93 components, 7 stores, 17 test files)                                                                                    | Artifact measurement  | 1      | Direct, verifiable    |
| I3  | Viewer accessibility gap distribution (chrome accessible, payload not)                                                                                      | Artifact measurement  | 1      | Direct, verifiable    |
| I4  | Docs platform a11y suite (17 Playwright specs, axe in 10, serve/e2e wired)                                                                                  | Artifact measurement  | 1      | Direct, verifiable    |
| I5  | Existing UX/UI Designer agent structure (7 linear steps, no backing skill)                                                                                  | Artifact measurement  | 1      | Direct, verifiable    |
| I6  | Existing repo capabilities (accessibility skill + scanner, vscode-playwright, surface inventory subagent, code-review a11y subagent, Accessibility Planner) | Artifact measurement  | 1–2    | Direct, verifiable    |
| I7  | ISE Playbook UI/UX design process chain                                                                                                                     | Published guidance    | 2      | Document              |
| I8  | ISE Playbook Design Ops asset list                                                                                                                          | Published guidance    | 2      | Document              |
| I9  | ISE Playbook accessibility + usability guidance                                                                                                             | Published guidance    | 2      | Document              |
| I10 | Standards licensing classification (Tier 1/2/3)                                                                                                             | Desk analysis         | 2      | Document              |
| I11 | Discovery that ATAG 2.0, WAI-ARIA Graphics Module, SVG-AAM are unreferenced in repo                                                                         | Artifact measurement  | 2      | Direct, verifiable    |
| I12 | Method 6 anti-polish coaching discipline vs standards-conformant output                                                                                     | Artifact measurement  | 1–2    | Direct, verifiable    |
| I13 | User's own scope evolution across the session (S1→S8, then the "stop indexing" correction)                                                                  | Session behavior      | 1–2    | Direct, single source |

## Source-type distribution

| Source type                              | Count | Share  |
|------------------------------------------|-------|--------|
| Artifact measurement                     | 7     | 54%    |
| Published guidance / desk analysis       | 4     | 31%    |
| Stakeholder statement / session behavior | 2     | 15%    |
| **Direct user observation**              | **0** | **0%** |
| **Builder interview**                    | **0** | **0%** |

## Coverage assessment

Strong coverage:

* What exists in the repository and in the reference codebase. Measured, repeatable, high confidence.
* What published guidance prescribes and what it omits. Document-grade, high confidence.
* Licensing classification of candidate standards. Document-grade, high confidence.

Absent coverage:

* No builder has been interviewed. Every claim about *why* builders behave as they do is inference from artifacts.
* No end user has been observed. The end-user experience is entirely inferred from code shape.
* No one has been observed using the existing UX/UI Designer agent. A1 rests on one owner report.
* Only one codebase examined in depth. Cross-project pattern claims are extrapolation from n=1 plus published guidance.

## What this evidence base can and cannot support

Can support:

* Claims about **artifacts** — what code contains, what guidance says, what the repo has and lacks.
* Claims about **structural gaps** — where a documented process chain has no step, where a standard is unreferenced.
* Claims about **licensing posture** — verifiable against published license terms.

Cannot support:

* Claims about **builder motivation** — why accessibility was deferred, what a builder would have done with better guidance.
* Claims about **end-user pain severity** — which failures actually cost people time.
* Claims about **adoption** — whether builders would use any of this.

Method 3 discipline: themes below are grounded only in what the inventory supports. Where a theme depends on inference, that is stated in the theme itself rather than hidden.

## Red-flag pre-check

Method 3 names seven synthesis failure modes. Three are live risks for this evidence base:

* **Single Source Dependency** — I1 and I13 both originate from the same person, who is also the session stakeholder. Themes must not rest on these alone.
* **Stakeholder Blind Spots** — builders and end users are entirely unrepresented as voices. Both are silent stakeholders in the literal sense.
* **Solution Bias** — the session opened with eight solution asks. Clustering must resist reorganizing those asks and calling the result a theme.

Not currently live: Pattern Forcing, Jargon Overload, Scope Creep, Premature Convergence — but Premature Convergence becomes a risk the moment themes get ranked.

## Synthesis approach

Cluster by **underlying mechanism**, not by capability category. The Method 2 punch list was organized by the coach's invented categories (C1–C5); re-using that structure would launder an assumption into a finding. Clustering starts from raw inputs and lets groupings emerge, then compares the result against C1–C5 as a check.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
