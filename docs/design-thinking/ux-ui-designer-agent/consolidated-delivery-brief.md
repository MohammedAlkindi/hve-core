---
title: UX/UI Capability Consolidated Delivery Brief
description: Consolidated Design Thinking evidence, decisions, confidence, and research handoff for the UX agent ecosystem redesign.
sidebar_position: 1
author: Microsoft
ms.date: 2026-08-04
ms.topic: concept
---

<!-- markdownlint-disable-file -->

## UX/UI capability consolidated delivery brief

Consolidated output of the Design Thinking session `ux-ui-designer-agent`. This is the research-ready input for `rpi-research`.

**Status:** Design Thinking Methods 1–4 complete. Handing off at the Concept Validated boundary with reduced confidence — concepts are reasoned rather than user-tested. See Confidence and Gaps.

**Disclaimer.** This brief is the product of AI-assisted Design Thinking coaching. Personas, problem statements, themes, and concepts here are scaffolding for human research and judgment, not substitutes for real practitioner voice. No UX practitioner has been interviewed. Validate assumptions against actual practitioners before treating any part of this as a basis for product commitments.

---

## 1. What we are building

A UX/UI capability with two modes over a shared foundation:

* **A coaching practice** that helps a practitioner through a hard moment in their work — framing a problem, running a critique, making a case to a sceptic.
* **Artifact generation** that produces the deliverables the practitioner is accountable for, grounded in named, openly licensed methods.

Both modes operate over a **shared vocabulary and evidence model**, so that what a coached session surfaces is the same object an artifact renders and a review later checks against.

The capability is callable both as a standalone agent and as skills other agents reach for when a UX decision is live.

## 2. Who it serves

The **UX practitioner role**, whoever holds it. A dedicated designer or researcher where one exists; an engineer, product manager, or tech lead where one does not.

Distinct from the end users of whatever gets built. The capability succeeds when it changes what the practitioner does; user outcomes follow from that.

## 3. Why — the problem

> UI/UX practitioners are expected to produce a substantial and varied body of work — outcomes, personas, jobs analyses, journeys, trade studies, requirements, test plans, design systems, handoff specifications, and measurement definitions. Most of it is authored by hand, in inconsistent formats, disconnected from the engineering process that consumes it, and grounded in whatever methods the individual practitioner happens to know.
>
> Available agentic support covers a narrow slice of that body of work, speaks a vocabulary the surrounding engineering process does not use, and cites no methodological grounding a practitioner could point to and defend.

Three supporting problems:

* **Standards grounding is absent, not thin.** Established open methods exist for most of what practitioners do. Current support cites none of them.
* **The practice is fragmented, not unsupported.** Scanning, surface inventory, screen capture, review perspectives, and planning workflows all exist independently with no shared vocabulary or linkage.
* **Design intent and verification do not reference each other.** Verification evaluates built software against generic rules. A design decision that was never made is invisible to every tool in the chain.

## 4. Evidence base

| Finding                                                                                                    | Source                                                  | Confidence  |
|------------------------------------------------------------------------------------------------------------|---------------------------------------------------------|-------------|
| Component libraries deliver accessible chrome; authored data surfaces carry the meaning and lack semantics | Measured in a reference React codebase (~93 components) | validated   |
| Mature accessibility verification exists and runs in CI, disconnected from design authoring                | Measured — 17 Playwright specs, axe in 10               | validated   |
| The ISE playbook design chain has no step between framework selection and scanning the result              | Published guidance                                      | validated   |
| The UX profession defines itself by **capability at four levels**, not by deliverable                      | UK DDaT Capability Framework                            | validated   |
| A large share of the job is social — facilitation, advocacy, consensus, mentoring                          | DDaT: 3 of 7 design skills, 2 of 7 researcher skills    | validated   |
| Accessibility and inclusion are one skill among seven, expected from junior level                          | DDaT                                                    | validated   |
| JTBD is a family of schools with different IP postures, not one method                                     | Practice literature                                     | validated   |
| Existing repo capability is fragmented, not absent                                                         | Repository inventory                                    | validated   |
| Current agent output does not overlap playbook-prescribed assets (vocabulary mismatch)                     | Artifact comparison                                     | validated   |
| That mismatch explains low adoption                                                                        | Inference                                               | **assumed** |
| Practitioners want coaching support at these moments                                                       | Inference from role frameworks                          | **unknown** |

## 5. Scope

### In

* Two modes — coaching/facilitation and artifact generation.
* A shared vocabulary and evidence model underneath both.
* Skills callable by other agents, not only the standalone agent.
* Every method grounded in a named, cited, appropriately licensed source.
* A source-attributed GOV.UK user-need form covering situation, motivation, and outcome.
* Accessibility and inclusion as one quality dimension among several.
* A distinct UI/UX coaching practice **derived from** DT coaching, sequenced on practice moments.

### Out

* Forking by practitioner role — DDaT shares design skills across roles; most users hold several at once.
* Forking by process phase — assumes linearity practitioners do not work in; the axis DT already occupies.
* Forking by artifact — what the current agent does, with weak adoption evidence.
* Exposing the fourteen DDaT skills as addressable surfaces — faithful to the source, unusable in practice.
* Rewriting any specific application. The reference codebase was a lens, not a client.

## 6. Coaching practice — derivation from DT

**Derivation, not dependency.** No runtime call into DT coaching; no DT session required. A practitioner who has never run a DT engagement can use it.

Inherited: coaching identity pattern (think, share observations, end with choices), progressive hinting, session state and resume, fidelity discipline, hat-switching.

UX-specific: sequenced on **practice moments** rather than DT methods; grounded in DDaT/GOV.UK/playbook/W3C rather than the DT method canon; assumes a practitioner with a live task rather than a team in a workshop; entered repeatedly at arbitrary points.

Accepted cost: some coaching-primitive duplication, judged better than coupling a practitioner tool to a workshop tool.

## 7. Practice moments — the spine

Twenty candidates identified, clustered by the capability each needs:

| Cluster                        | Moments           | Frequency | Difficulty | Current support | Uniqueness |
|--------------------------------|-------------------|-----------|------------|-----------------|------------|
| C-A Framing under uncertainty  | M1, M4, M6, M7    | High      | High       | Low             | Medium     |
| C-B Reasoning from evidence    | M5, M8, M17, M18  | Medium    | High       | Low             | Medium     |
| C-C Declaring intent precisely | M9, M10, M16, M19 | High      | Medium     | Partial         | **High**   |
| C-D Moving people              | M12–M15, M20      | High      | High       | **None**        | **High**   |
| C-E Calibrating effort         | M2, M3, M11       | High      | Medium     | Low             | Low        |

Value concentrates in C-C and C-D for opposite reasons: C-C needs **grounding** a general model lacks; C-D needs **structure** a general model does not apply.

### Recommended first set

| Moment                                        | Cluster | Why it earns a place                                        |
|-----------------------------------------------|---------|-------------------------------------------------------------|
| M10 Deciding what a surface must convey       | C-C     | No precedent anywhere; the gap the whole session uncovered  |
| M16 Handing intent to engineering             | C-C     | Where UX work meets the process that consumes it            |
| M19 Checking that what shipped matches intent | C-C     | Closes the loop against M10                                 |
| M13 Running a critique                        | C-D     | Most concrete facilitation moment; proves the coaching mode |
| M14 Making the case to a sceptic              | C-D     | Highest felt difficulty, thinnest published grounding       |
| M6 Deciding what the problem actually is      | C-A     | Gates everything downstream                                 |

Full twenty in `method-04-practice-moments.md`; value reasoning in `method-04-clustering-value.md`.

## 8. The load-bearing unknown

**The shared evidence model does not exist and has not been designed.**

M10 declares what a surface must convey. M19 checks that what shipped matches. Between them must pass an object precise enough to be verified and legible enough to be authored in a coached conversation. That object is what makes this one capability rather than two, and nothing in this session has specified it.

This is the first thing research should attack.

## 9. Standards and licensing posture

Binding rule: paraphrase-first everywhere. Reproduce only what the source class permits. Never reproduce cite-only sources, in whole or in part.

| Source                                | Class                | Use                                                                            |
|---------------------------------------|----------------------|--------------------------------------------------------------------------------|
| UK DDaT Capability Framework          | OGL v3.0             | Role and skill definitions — strongest available source                        |
| GOV.UK Service Manual / Design System | OGL v3.0             | Service phases, patterns, research practice                                    |
| ISE Engineering Playbook              | CC BY 4.0            | Design process, Design Ops, usability characteristics                          |
| USWDS                                 | Public domain        | Design system and token patterns                                               |
| WCAG 2.2, WAI-ARIA, ARIA APG, COGA    | W3C Document License | Accessibility criteria and widget patterns                                     |
| **WAI-ARIA Graphics Module**          | W3C                  | Chart and diagram semantics — **not referenced in repo today**                 |
| **SVG Accessibility API Mappings**    | W3C                  | SVG-to-AT mapping — **not referenced in repo today**                           |
| **ATAG 2.0**                          | W3C                  | Considered and declined as an organizing standard; no conformance goal adopted |
| WCAG-EM                               | W3C                  | Evaluation methodology                                                         |
| Design Tokens Community Group format  | W3C CG               | Token interchange                                                              |
| Section 508                           | Public domain        | Verbatim safe                                                                  |
| NASA-TLX                              | Public domain        | Workload measurement                                                           |

### Pitfalls confirmed

| Source                  | Posture                                                                                                                                   |
|-------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| Nielsen's 10 heuristics | **Cite-only, NN/g copyright.** Highest practical risk — routinely copy-pasted. Original prose or omit                                     |
| ISO 9241-11 / -210      | **Cite-only.** The playbook's effectiveness/efficiency/satisfaction triad derives from ISO — source it from the CC BY playbook, never ISO |
| EN 301 549              | **Cite-only (ETSI)**                                                                                                                      |
| NN/g UX maturity model  | **Cite-only**                                                                                                                             |
| SUPR-Q                  | Proprietary — cite only                                                                                                                   |
| SUS                     | **Ambiguous.** Verify before reproducing the 10 items; paraphrasing the method is safe                                                    |
| Google HEART / GSM      | No canonical spec located — treat as practice, do not claim a standard                                                                    |
| Double Diamond          | Verify Design Council reuse terms before reproducing phase definitions or diagrams                                                        |

### JTBD posture

Adopted source: the GOV.UK Service Manual user-need form covering situation, motivation, and outcome, under the Open Government Licence v3.0. Adapt it with attribution and a statement of changes.

JTBD posture: no verified reuse grant was located for job-story syntax or the examined commercial schools. Cite school names and canonical sources as facts when relevant, but do not reuse wording, templates, scoring instruments, examples, or visuals.

Never: Kalbach playbook templates; Strategyn process artifacts and outcome forms; Moesta interview scripts; Christensen article or book text.

**Binding:** ambiguity resolves to no reuse. UX assets use the verified GOV.UK source rather than presenting a JTBD school as an adopted format.

## 10. Existing capability to reuse, not rebuild

Measured as present in the repository:

| Capability                                | Note                                                                       |
|-------------------------------------------|----------------------------------------------------------------------------|
| Consolidated accessibility skill          | WCAG 2.2, ARIA APG, COGA, 508, EN 301 549; ships an axe-core scanner CLI   |
| Accessibility Surface Inventory subagent  | Runtime surface and interaction-state discovery                            |
| Accessibility Framework Assessor subagent | Framework-scoped assessment                                                |
| Code Review Accessibility subagent        | Diff-scoped accessibility perspective                                      |
| Accessibility Planner                     | Six-phase workflow with backlog handoff                                    |
| vscode-playwright skill                   | Screenshot capture                                                         |
| Docs site e2e suite                       | 17 Playwright a11y specs, axe in 10 — a working reference for verification |
| DT coaching foundation                    | Coaching primitives to derive from                                         |
| Existing UX/UI Designer agent             | JTBD and journey map output; no backing skill                              |

The original request assumed screen capture and scanning needed building. They exist. The missing piece is connective tissue.

## 11. Research questions for `rpi-research`

Ordered by leverage.

1. **What is the shared evidence model?** What object passes between a coached decision, a generated artifact, and an automated check? What is its schema, and what existing formats could carry it?
2. **How should accessibility ownership be divided?** Record ATAG-shaped convergence as considered and declined, then define concept-stage inclusion versus technical conformance ownership.
3. **What is the artifact set for the first six moments?** Names, structures, and which openly licensed method grounds each.
4. **How do the coaching primitives get shared or duplicated with DT coaching?** Reuse, distinct scope, or shared substrate — with the cost of each.
5. **How do other agents call these skills?** Invocation surface, context requirements, output contracts.
6. **What does M10 actually produce?** The unprecedented capability. Graphics Module and SVG-AAM are the grounding; the artifact form is undefined.
7. **Verify licensing on: SUS instrument text, Double Diamond reuse terms, Design Tokens CG spec status, Ulwick paraphrase boundaries.**

## 12. Confidence and gaps

| Item                                | Confidence                                              |
|-------------------------------------|---------------------------------------------------------|
| Problem definition                  | validated (document + artifact evidence)                |
| Two-mode structure                  | assumed (reasoned from DDaT, not user-tested)           |
| Practice moment list                | assumed (derived from published frameworks)             |
| Value ranking of clusters           | assumed (read from role frameworks, not observed)       |
| First-set selection                 | assumed                                                 |
| Shared evidence model               | **unknown — not designed**                              |
| Practitioner demand for any of this | **unknown — zero practitioners interviewed**            |
| Licensing classification            | validated for most; four items flagged for verification |

### The standing gap

No UX practitioner has been interviewed, observed, or shown any of this. Every claim about what practitioners need is inference from published role frameworks — a real improvement over imagination, and not the same as evidence.

Two specific risks this creates:

* The moment list may be well-documented rather than actually painful. Documentation density is not difficulty.
* The two-mode split is reasoned from a capability framework, not from watching anyone work.

Recommended mitigation: the concept sketches deferred at Method 5 are exactly what you would put in front of a practitioner. Producing one C-C and one C-D sketch would both close this gap and force the evidence model into the open.

## 13. Session artifacts

State: `.copilot-tracking/design-thinking-sessions/ux-ui-designer-agent/coaching-state.md`

| Artifact                                   | Method |
|--------------------------------------------|--------|
| `method-01-assumptions-log.md`             | 1      |
| `method-01-scope-boundaries.md`            | 1      |
| `method-02-research-plan.md`               | 2      |
| `method-02-findings-playbook-assets.md`    | 2      |
| `method-02-findings-ux-practice.md`        | 2      |
| `method-02-standards-licensing-catalog.md` | 2      |
| `method-02-capability-punchlist.md`        | 2      |
| `method-03-input-inventory.md`             | 3      |
| `method-03-synthesis-themes.md`            | 3      |
| `method-03-problem-definition.md`          | 3      |
| `method-04-divergent-concepts.md`          | 4      |
| `method-04-practice-moments.md`            | 4      |
| `method-04-clustering-value.md`            | 4      |

All under `docs/design-thinking/ux-ui-designer-agent/`.

**Note on the standards catalog:** `method-02-standards-licensing-catalog.md` was authored while the session scope was narrowed to accessibility and is lopsided toward accessibility specs. The licensing table in section 9 of this brief supersedes it.

---

## Handoff

* **Exit point:** concept-validated (reduced confidence — reasoned, not user-tested)
* **Last DT method:** 4
* **Space exited:** solution
* **Target:** `rpi-research`
* **Recommended first research topic:** the shared evidence model (question 1), because it gates the coherence of everything else.

Coaching remains available. If research surfaces questions needing DT methods, the session resumes from recorded state.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
