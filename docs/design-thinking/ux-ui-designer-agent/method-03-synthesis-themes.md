---
title: Method 03 Synthesis Themes
description: Themes synthesized from Method 02 evidence, with confidence grading.
sidebar_position: 10
author: Microsoft
ms.date: 2026-08-05
ms.topic: concept
---

<!-- markdownlint-disable-file -->

## Method 03: Synthesis themes

Phase 2 of Method 3. Clusters built from the input inventory by underlying mechanism. Each theme states its supporting inputs and its evidence strength honestly.

Strength scale:

* **High** — multiple independent artifact measurements support it.
* **Medium** — artifact measurement plus published guidance, but no human evidence.
* **Low** — single source, or dependent on inference about motivation.

---

## T1 — Accessibility failure is concentrated where meaning lives, not where controls live

**Supporting inputs:** I3, I6, I7, I9

Across the evidence, accessible-by-default component libraries reliably deliver correct chrome — buttons, dialogs, menus, form controls. The failures cluster in surfaces the team authored themselves to carry the actual analytical payload: charts, canvases, timelines, synchronized media. Published guidance and available tooling both operate on generic DOM patterns, which is precisely why they succeed on chrome and are silent on payload.

The mechanism is not negligence. It is that **correctness is inherited for standard widgets and must be constructed for custom ones**, and nothing in the available guidance tells a builder how to construct it.

**Strength: High.** Independently measured in the reference codebase, and structurally predicted by what the guidance and tooling actually cover.

---

## T2 — The prescribed design process has no rung between "choose a framework" and "scan the result"

**Supporting inputs:** I7, I8, I9, I3

The playbook's chain runs Desired Outcomes → Personas → Trade Studies → Architecture. Accessibility appears as a cross-cutting concern and as post-hoc tooling (axe, Accessibility Insights, the W3C tools list). Every named tool evaluates rendered output against generic rules.

There is no step at which a builder decides *what a non-visual user should be able to perceive and do* for a surface they are about to author. A team following the guidance faithfully lands exactly where the reference codebase landed.

**Strength: High.** The omission is verifiable in the published guidance; the predicted consequence is independently measured.

---

## T3 — Verification and authoring are disconnected in both directions

**Supporting inputs:** I4, I6, I3

Where accessibility verification exists, it is mature, automated, and runs against already-built software. Nothing observed feeds verification results back into design authoring, and nothing feeds design intent forward into what gets verified. Design artifacts and test specs have no shared vocabulary and no linkage.

The consequence is that verification can only ever find violations of generic rules. It cannot detect that a surface's intended non-visual experience was never specified, because no artifact ever declared one.

**Strength: High.** Measured in two independent codebases.

---

## T4 — The tooling being designed is an authoring tool, and that is a solved problem class with an unused standard

**Supporting inputs:** I11, I10, I5

ATAG 2.0 Part B specifies what it means for an authoring tool to help its users produce accessible content — prompting, checking, repair assistance, accessible-by-default output, documentation. WAI-ARIA Graphics Module and SVG Accessibility API Mappings specify semantics for exactly the surface class T1 identifies. All three are W3C-licensed and buildable-from. None is referenced anywhere in the repository.

This reframes the deliverable. The goal is not an agent that knows more about accessibility; it is an authoring tool that makes accessible output the path of least resistance — a target with a published conformance structure.

**Strength: High** for the factual claims (specs exist, are unreferenced, are appropriately licensed). **Medium** for the framing claim that ATAG is the right organizing model, which is a design judgment.

---

## T5 — Existing capability is fragmented, not absent

**Supporting inputs:** I6, I5, I4

Surface inventory, axe scanning, screen capture, code-review accessibility perspective, and a six-phase Accessibility Planner all already exist. What does not exist is any connective path among them, or from any of them into design authoring. The standalone UX agent has no backing skill and shares no vocabulary with any of these.

The original framing assumed missing tooling. The measured finding is missing **integration**.

**Strength: High.** Direct inventory.

---

## T6 — The existing agent speaks a different language than the engineering process around it

**Supporting inputs:** I5, I7, I8, I1

The agent emits JTBD analyses and journey maps. The playbook asks for desired outcomes, personas, and trade studies. Neither vocabulary appears in the other. An engineer working from the playbook has no slot to put the agent's output into, and the agent has no awareness of the artifacts the playbook expects.

This is a plausible mechanical explanation for low adoption that requires no one to have judged the output poor.

**Strength: Medium.** The vocabulary mismatch is verifiable. The adoption inference is not — no builder has been asked, and A1 rests on a single owner report.

---

## T7 — Standards-conformant output conflicts with early-stage design discipline

**Supporting inputs:** I12

Lo-fi prototyping discipline explicitly redirects polished artifacts back toward roughness and constrains build effort to minutes-to-hours. Standards-conformant specifications are, structurally, the kind of artifact that discipline pushes back on. A capability that presents the same face at every stage will either break early-stage practice or be rejected by it.

**Strength: Medium.** The tension is measurable in the two artifacts. Whether it manifests in practice is untested.

---

## T8 — The problem is defined almost entirely from artifacts, with no human voice

**Supporting inputs:** I13, and the coverage gaps in the input inventory

Zero builders interviewed. Zero end users observed. Zero observed uses of the existing agent. Fifty-four percent of inputs are artifact measurements; the human-sourced inputs both originate from the same person, who is also the session stakeholder.

This is a finding about the evidence base itself, and it constrains every theme above. T1 through T5 are claims about artifacts and survive. T6 and T7 make claims about human behavior and do not have human evidence behind them.

**Strength: High** as an observation about the evidence base.

---

## Cross-check against the Method 2 punch list

The punch list was organized as C1 standards, C2 authoring, C3 evidence, C4 loop-closure, C5 integration. Comparing against emergent themes:

| Punch-list group          | Theme correspondence | Assessment                                                                              |
|---------------------------|----------------------|-----------------------------------------------------------------------------------------|
| C1 Standards reference    | T4                   | Survives, and T4 sharpens it — ATAG is the organizing spec, not one entry among several |
| C2 Authoring capabilities | T2, T6               | Survives, but T6 says the **vocabulary** matters as much as the artifact list           |
| C3 Evidence capabilities  | T5                   | Largely dissolves — mostly already exists                                               |
| C4 Loop closure           | T3                   | Survives and strengthens; T3 makes it bidirectional, C4 treated it as mostly one-way    |
| C5 Integration            | T5, T7               | Survives, with T7 as a live constraint on where integration is safe                     |

Two structural corrections the clustering produced:

* C3 was overweighted. Treating evidence-gathering as a build area was an artifact of the original request, not of the evidence.
* T1 had no home in C1–C5. The single strongest theme — that failure concentrates in authored meaning-bearing surfaces — was not represented as a category at all, only as a scattered note inside C1.5 and C2.6.

---

## Validation across the five dimensions

| Dimension                | Assessment      | Notes                                                                 |
|--------------------------|-----------------|-----------------------------------------------------------------------|
| Research fidelity        | **Strong**      | Themes trace to specific inputs; inference is labeled where present   |
| Stakeholder completeness | **Weak**        | Builders and end users unrepresented; see T8                          |
| Pattern robustness       | **Mixed**       | T1–T5 multi-source; T6–T7 thinner; T7 single-source                   |
| Actionability            | **Strong**      | T1–T5 translate into problem statements without prescribing solutions |
| Team alignment           | **Unconfirmed** | Requires user confirmation before transition                          |

Method 3 guidance on weak dimensions: conduct targeted research for completeness gaps. That points at builder contact, which remains unavailable. Proceeding to Method 4 is defensible provided the completeness gap travels forward as a stated constraint rather than being quietly dropped.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
