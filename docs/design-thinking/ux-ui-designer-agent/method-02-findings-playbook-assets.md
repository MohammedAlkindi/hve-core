---
title: Method 02 Findings on Engineering Playbook UX Assets
description: Desk research findings on the engineering playbook UX asset inventory.
sidebar_position: 6
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 02: Findings on the engineering playbook UX asset inventory

Track A desk research. Source: ISE Engineering Fundamentals Playbook (`microsoft/code-with-engineering-playbook`), docs licensed CC BY 4.0.

Pages read:

* <https://microsoft.github.io/code-with-engineering-playbook/UI-UX/>
* <https://microsoft.github.io/code-with-engineering-playbook/non-functional-requirements/accessibility/>
* <https://microsoft.github.io/code-with-engineering-playbook/non-functional-requirements/usability/>
* <https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/trade-studies/> (referenced)

## What the playbook actually prescribes

Paraphrased. The playbook's UI/UX design process is a short, ordered chain, and it is more specific about sequence than most UX guidance:

1. **Desired Outcomes** — a plain list of what the solution must accomplish, expressed as stakeholder-voiced statements.
2. **User Personas** — prose paragraphs describing user types. The playbook is explicit that persona sets must always include disabled users, and that a user set assumed to be non-disabled today carries no guarantee of remaining so.
3. **Trade Studies** — the first one is high-level and solution-oriented (should this even be a UI?), focused on users; subsequent ones dive into implementation and weigh developer experience.
4. **Architecture selection** — framework choice deferred until after the user picture is settled.

Four cross-cutting concerns are named as the things every UI team must understand: **accessibility, usability, maintainability, stability**.

A separate **Design Ops** section names durable operational assets: design systems with reusable components and design tokens, component documentation (Storybook is named), design-to-development handoff validation, regular design reviews including product owners and end users, and KPIs with A/B testing for long-lived projects.

The accessibility page adds: inclusive design methodology (recognize exclusion; solve for one, extend to many; learn from diversity), automated tooling as necessary-but-insufficient, and explicit instruction to augment automated tests with manual ones.

The usability page defines the measurable characteristics: effectiveness, efficiency, satisfaction, plus learnability, memorability, errors, simplicity, comprehensibility. It prescribes usability testing producing both quantitative and qualitative data.

## Asset list derivable from the playbook

| #   | Asset                                                      | Playbook basis                 | Produced by current UX/UI Designer agent?                         |
|-----|------------------------------------------------------------|--------------------------------|-------------------------------------------------------------------|
| P1  | Desired Outcomes list                                      | Design Process step 1          | No                                                                |
| P2  | User personas (including disabled users by default)        | Design Process step 2          | No — agent asks discovery questions but emits no persona artifact |
| P3  | UX trade study (solution-level)                            | Design Process step 3          | No                                                                |
| P4  | Implementation trade study (developer-experience weighted) | Design Process step 3          | No                                                                |
| P5  | Architecture/framework decision record                     | Establishing architecture      | No                                                                |
| P6  | Accessibility requirements                                 | NFR: accessibility             | Partial — inline WCAG AA prose in Step 4                          |
| P7  | Usability requirements with measurable characteristics     | NFR: usability                 | No                                                                |
| P8  | Usability test plan (quant + qual)                         | NFR: usability implementations | No                                                                |
| P9  | Design system / token definitions                          | Design Ops                     | No                                                                |
| P10 | Component documentation                                    | Design Ops (Storybook)         | No                                                                |
| P11 | Design-to-dev handoff validation                           | Design Ops                     | Partial — Step 6 handoff prose                                    |
| P12 | Design review cadence and records                          | Design Ops feedback loops      | No                                                                |
| P13 | UX KPIs / metrics definition                               | Design Ops metrics             | No                                                                |
| P14 | JTBD analysis                                              | Not in playbook                | Yes                                                               |
| P15 | Journey map                                                | Not in playbook                | Yes                                                               |

## Two findings worth stating plainly

**Finding 1 — the current agent and the playbook barely overlap.**
The agent produces JTBD analysis and journey maps (P14, P15), neither of which the playbook asks for. The playbook asks for desired outcomes, personas, and trade studies (P1–P4), none of which the agent produces. This is not a quality gap; it is a **vocabulary mismatch**. An engineer following the playbook and an engineer using the agent are working in two different idioms, which is a plausible mechanical explanation for A1 (agent unused) that does not require anyone to have found the output bad.

**Finding 2 — the playbook stops where the viewer broke.**
The playbook names accessibility as a first-class concern and points at axe, Accessibility Insights, and the W3C tools list. Every one of those operates on **rendered DOM against generic rules**. None of them, and no part of the playbook, addresses how a builder decides what a screen-reader user should hear when the payload is a 17-joint trajectory across 400 frames. The playbook's design-process chain also terminates at architecture selection — it has no step where visualization semantics get designed.

This is consistent with the viewer evidence from Method 1: accessible chrome, inaccessible payload. The playbook would have produced exactly that outcome if followed faithfully. That makes the viewer's shape less an indictment of its builders and more a **reproducible consequence of the guidance available to them**.

## Reframed opportunity

The gap is not "the playbook is wrong." It is that the playbook's UX chain has no rung between *choose a framework* and *run axe on the result*. Data-dense and media-dense surfaces fall through that gap by construction.

## Fidelity note

This is desk research (Method 2 Track A). It is evidence about **documents**, not about **people**. It cannot tell us why any specific builder did anything. Findings 1 and 2 are hypotheses with document-level support, confidence Medium at best. B1/B3 interviews remain unrun.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
