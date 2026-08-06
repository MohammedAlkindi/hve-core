---
title: Method 01 Request Stack and Assumptions Log
description: Unanalyzed capture of the request stack and the assumptions carried into the UX agent redesign.
sidebar_position: 3
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 01: Request stack and assumptions log

Rough capture. Not analyzed or prioritized yet.

## Initial request (verbatim)

> I want to do a session on improving out UI/UX designer agent, backing it with a standards based skill(s) and building out something that we can be wildly proud of ... I want you to look at the code with engineering playbook and figure out all the assets we might want to produce from a UIUX expereince, which standards we can reference from a licensing perspective, and build a stunning experience

## Follow-on request

> one other things we need is a screen cap and ui/ux flow analysis system ... and we need to tie into the accessiblity tooling too

## Third request

> i think it's a blend of both ... and if you want to go really deep ... we should look at the low-fi/hifi protoype handoff process OR more likely integrating the skill into the low-fi high fi prototyping process in design thinking and mutate DT to use the skill

## Classification

Frozen. Names a technology (skills, screen capture, flow analysis), a context (the existing UX/UI Designer agent), and a success bar ("wildly proud", "stunning"). Frozen requests are treated as pointing at a real problem while encoding a guess about its cause.

## Solution asks stated so far

| #  | Ask                                                                       | Stated as                                    |
|----|---------------------------------------------------------------------------|----------------------------------------------|
| S1 | Back the agent with standards-based skill(s)                              | Requirement                                  |
| S2 | Enumerate all assets a UX experience should produce                       | Requirement                                  |
| S3 | Determine which standards are safe to reference (licensing)               | Requirement                                  |
| S4 | Screen capture system                                                     | Requirement                                  |
| S5 | UI/UX flow analysis system                                                | Requirement                                  |
| S6 | Tie into accessibility tooling                                            | Requirement                                  |
| S7 | Integrate the UX skill into DT Method 6/7 prototyping and the 6→7 handoff | Aspiration ("if you want to go really deep") |
| S8 | Mutate DT itself to consume the skill                                     | Aspiration                                   |

## Scope growth

Three messages, eight solution asks, zero validated problems. Scope is expanding faster than evidence. Recorded as a coaching observation, not a blocker.

Surface area of S8, measured: `dt-methods` is 28 reference files / ~4,845 lines, plus 5 foundation references. "Mutate DT" is not a small edit.

## Tension: standards rigor vs Method 6 scrappiness

Method 6's core coaching discipline is anti-polish. Its Prototype Builder hat explicitly redirects over-polished artifacts back to rough drafts, enforces single-assumption prototypes, and caps build time at minutes-to-hours. A standards-backed UX skill that emits WCAG-conformant specs is precisely the kind of output Method 6 is designed to push back on.

This does not kill S7. It means the skill cannot present the same face at every method. Candidate split:

| Method       | Plausible skill role                               | Notes                         |
|--------------|----------------------------------------------------|-------------------------------|
| 5 (Concepts) | Concept framing, JTBD                              | Cheap, verbal, no polish risk |
| 6 (Lo-fi)    | Assumption-shaped a11y questions only, no specs    | Must not break scrappiness    |
| 7 (Hi-fi)    | Full standards specs, screen capture, axe scanning | Real system exists to scan    |
| 8 (Testing)  | Flow analysis against observed behavior            | Evidence available            |

## Existing assets found in repo (context, not yet assessed)

* `.github/agents/project-planning/ux-ui-designer.agent.md` — 7-step linear agent, all knowledge inlined, no backing skill.
* `.github/skills/accessibility/accessibility/` — consolidated skill; WCAG 2.2, ARIA APG, COGA, Section 508, EN 301 549; MIT licensed; ships an axe-core scanner CLI (`scripts/scan.py`).
* `.github/skills/experimental/vscode-playwright/` — Playwright MCP screenshot capture via `serve-web`.
* `.github/agents/**` — Accessibility Framework Assessor, Accessibility Surface Inventory subagents already exist.

## Candidate targets named by user (2026-08-01)

* `docs/docusaurus` — the HVE Core docs platform. Real, running, in-repo. `node_modules` present.
* Physical AI toolchain.
* `~/src/edge-ai` — present locally as a sibling repo.

## Verified state of the docs platform (measured, not assumed)

The docs site already ships a substantial Playwright-driven accessibility verification suite at `docs/docusaurus/e2e/` — 17 spec files, ~900 lines, with axe integrated across 10 of them:

| Spec                                                                                  | Concern                         |
|---------------------------------------------------------------------------------------|---------------------------------|
| `contrast.spec.ts`                                                                    | Color contrast                  |
| `focus-management.spec.ts`, `_helpers/focus.ts`                                       | Focus order and visibility      |
| `keyboard-nav.spec.ts`, `skip-link.spec.ts`                                           | Keyboard operability            |
| `forced-colors.spec.ts`, `color-mode.spec.ts`                                         | High-contrast and theme modes   |
| `heading-order.spec.ts`, `structural-baseline.spec.ts`                                | Document structure              |
| `reflow.spec.ts`, `target-size.spec.ts`, `mobile-menu.spec.ts`                        | WCAG 2.2 reflow and target size |
| `screen-reader/exploration.spec.ts`                                                   | Assistive-technology traversal  |
| `site-crawl.spec.ts`, `doc-navigation.spec.ts`, `home-hero.spec.ts`, `search.spec.ts` | Flow and navigation             |
| `_helpers/a11yInvariants.ts`, `_helpers/pages.ts`, `_helpers/targetSize.ts`           | Shared invariants               |

Serving is already wired: `serve:ci` (`e2e/static-server.mjs`), `serve:preview`, `ci:test:e2e`.

### Consequence for A4 and S4/S5/S6

A4 ("the gap is lack of real UI input") is now **partially falsified for this target**. Screen access, crawling, flow traversal, and accessibility scanning all already exist for the docs platform. S4/S5/S6 are therefore less "build the tooling" and more "connect authoring to tooling that already runs."

The sharper open question this exposes: this verification suite runs in CI against a site that was *already built*. Nothing appears to feed its results back into UX **design** authoring, and nothing appears to feed design intent forward into what the suite checks. That gap — between verification and authoring — is the most concrete problem surfaced so far, and it is the first one grounded in measured repo state rather than assumption.

## Assumptions to validate

| #  | Assumption                                                | Source             | Status                                               |
|----|-----------------------------------------------------------|--------------------|------------------------------------------------------|
| A1 | The current agent underperforms in practice               | Implied by request | Unvalidated — no usage evidence offered yet          |
| A2 | The gap is knowledge grounding (missing standards)        | Stated             | Unvalidated                                          |
| A3 | The gap is artifact coverage (too few asset types)        | Stated             | Unvalidated                                          |
| A4 | The gap is lack of real UI input (no screens to look at)  | Implied by S4/S5   | Unvalidated                                          |
| A5 | Users want more artifacts rather than fewer, better ones  | Implied            | Unvalidated, and contradicted by common failure mode |
| A6 | Accessibility is currently disconnected from UX authoring | Implied by S6      | Partially checkable in repo                          |

## Open questions

* Has anyone run the UX/UI Designer agent end to end? What happened?
* Who is the user — an engineer with no designer, or a designer using AI as an accelerant?
* What does "wildly proud" mean in observable terms?

## Emerging hypothesis (coach's, unvalidated)

S4 and S5 shift the agent from *interviewing a human about a hypothetical UI* to *observing an actual UI*. That is an evidence-source change, not a knowledge change. If the real failure is "the agent produces plausible-sounding research about a product it has never seen," then standards grounding alone does not fix it, and screen capture is the load-bearing ask rather than a side request.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
