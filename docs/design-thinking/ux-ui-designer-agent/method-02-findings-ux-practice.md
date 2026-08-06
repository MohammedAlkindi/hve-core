---
title: Method 02 Findings on UX Practice
description: Desk research on UX practitioner roles, capabilities, artifacts, and source licensing for the UX agent redesign.
sidebar_position: 5
author: Microsoft
ms.date: 2026-08-04
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 02 (return): Findings on what UX practitioners do

Targeted research to close the stakeholder-completeness gap flagged as T8/HMW9. Backward transition from Method 3 to Method 2, authorized by the sequencing guidance that iteration is expected and partial re-entry supported, and by the Method 3 instruction to conduct targeted research when the completeness dimension is weak.

**Fidelity note.** This is desk research on published role frameworks and practice literature. It is evidence about **how the profession defines itself**, not about how any individual practitioner spends a Tuesday. It does not close HMW9 — no practitioner has been interviewed. It substantially reduces the risk of designing from the coach's imagination.

## Primary source: UK Government Digital and Data Profession Capability Framework

<https://ddat-capability-framework.service.gov.uk/> — **Open Government Licence v3.0**, Crown copyright. Reusable with attribution.

This is the most authoritative openly-licensed description of UX practitioner roles found. It defines distinct roles, each with named skills assessed at four ascending levels: **awareness, working, practitioner, expert**.

### Roles in the user-centred design family

| Role                                                           | What they do (paraphrased from the framework)                                                                                                                                                   |
|----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| User researcher                                                | Plan, design and carry out research activities with users so teams deeply understand the people using a service; research informs policy, proposition, service, content, and interaction design |
| Interaction designer                                           | Work out the best way to let users interact with services, at the level of overall flow and of individual design elements                                                                       |
| Service designer                                               | Design the end-to-end journey of a service across digital and offline channels, often spanning multiple parts of an organisation                                                                |
| Content designer                                               | Make things easier for people to understand and use, working on single pieces of content or end-to-end journeys across digital and offline channels                                             |
| Graphic designer                                               | Listed in the framework as sharing the same design skill set                                                                                                                                    |
| Content strategist, technical writer, accessibility specialist | Adjacent roles in the same profession family                                                                                                                                                    |

### The design skill set (shared across content, interaction, service, and graphic designers)

Updated 2024–2026. Seven skills, deliberately shared across roles:

1. **Design communication** — explaining and justifying design decisions; documenting decisions, risks, and unresolved issues
2. **Designing for everyone** — inclusive, accessible, environmentally sustainable design; meeting standards and regulations; identifying barriers, biases, and assumptions that exclude or harm users
3. **Designing strategically** — aligning design work to organisational goals; using risks, opportunities, and constraints to shape work; creating patterns and components
4. **Designing together** — planning and running design sessions with teams, users, and stakeholders; building consensus; giving and receiving feedback; working across profession boundaries
5. **Evidence-based design** — framing ideas as testable design hypotheses; finding, analysing, and synthesising evidence; working with researchers and analysts
6. **Iterative design** — applying iterative and agile practice; creating material to test ideas at appropriate fidelity; iterating on successive rounds of research; using and iterating patterns
7. **Leading design** — leading and coordinating design work; advocating for user-centred design; mentoring; improving design processes

### The user researcher skill set

Distinct from the design skills. Seven skills:

1. **User research methods** — planning and conducting research; choosing and correctly applying methods; involving the team
2. **Analysis and synthesis** — applying analysis techniques; involving the team; presenting findings colleagues can use; critiquing others' findings
3. **Inclusive research** — understanding user diversity; including many kinds of users in research; advocating inclusive practice
4. **Research management, leadership and assurance** — defining research scope and purpose; working to standards including ethics and safeguarding; assuring quality
5. **Agile research practices** — designing research so findings embed into an agile workflow; adapting to product complexity
6. **Stakeholder relationship management** — identifying stakeholders, tailoring communication, building consensus, using evidence to explain decisions
7. **User-centred practice and advocacy** — advocating for the user; helping sceptical colleagues and inexperienced teams adopt user-centred practice

## Finding A — the profession defines itself by capability, not by deliverable

The most authoritative openly-licensed description of UX practice contains **no artifact list**. It is organised entirely around skills demonstrated at ascending levels. Artifacts appear only as incidental examples — "mockups or drafts," "patterns and components," "metadata."

This directly challenges the framing carried through Methods 1 and 2, where the working assumption was that the capability should be defined by the assets it emits. The profession's own framework says a practitioner is defined by what they can **do**, and much of that doing is not document production.

Confidence: **High** for the claim about how the framework is organised. **Medium** for the inference that artifact-centred tooling therefore mismatches practitioner self-conception — that inference still needs a practitioner to confirm.

## Finding B — a large share of the job is not artifact production at all

Of the seven design skills, at least three are primarily **social and organisational**:

* Designing together — facilitation, session design, consensus-building, cross-boundary work
* Leading design — coordination, advocacy, mentoring, process improvement
* Design communication — explaining and justifying to teams and stakeholders

For user researchers, stakeholder relationship management and user-centred practice and advocacy are equally non-artifact skills. The framework describes advocating "with sceptical colleagues," building consensus "by challenging assumptions," and helping "inexperienced teams adopt user-centred practices."

A capability that only generates documents addresses roughly half of what the framework says the job is. The other half is facilitation, persuasion, and organisational change.

Confidence: **High** as a reading of the framework. Untested against practice.

## Finding C — accessibility and inclusion are already first-class, at every level

"Designing for everyone" is one of seven core design skills, present from awareness level upward, and inclusive research is one of seven researcher skills. The framework treats inclusion, accessibility, and environmental sustainability as ordinary parts of competent design practice, expected of a junior practitioner.

This validates keeping accessibility in scope and simultaneously validates the earlier scope correction. In the profession's own terms, accessibility is one skill among seven — not the definition of the work.

Confidence: **High.**

## Finding D — the artifact canon is real but almost entirely unstandardised

Practice literature yields a large, consistent artifact inventory. Grouped by phase:

| Phase       | Artifacts                                                                                                                                                                                                         |
|-------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Research    | Research plan, interview guide or protocol, interview transcripts, usability test plan, contextual inquiry notes, affinity diagram                                                                                |
| Synthesis   | Personas, empathy map, journey map, service blueprint, experience map, JTBD statements, heuristic evaluation, accessibility audit, research/insights report                                                       |
| Design      | User and task flows, information architecture and sitemap, wireframes, lo-fi prototype, hi-fi mockup, interactive prototype, design system and component library, design tokens, style guide, content style guide |
| Validation  | Usability findings report, task success rate, time on task, error rate, think-aloud transcript, heatmap, A/B test report                                                                                          |
| Handoff     | Redlines and annotations, tool-native dev specs, design token exports, component specifications, acceptance criteria, design QA checklist                                                                         |
| Measurement | UX metrics dashboard, standardised questionnaire results, ongoing benchmark reporting                                                                                                                             |

Standardisation status is the important part:

* **Formally standardised:** accessibility conformance (WCAG 2.2 and derivatives); human-centred design process activities and usability measurement concepts (ISO 9241 family — cite-only, never reproduced); design tokens format (W3C Community Group, in progress)
* **Openly published, not standardised:** Double Diamond, Google Design Sprint, GOV.UK service phases, all JTBD variants
* **Universal practice, no published spec:** personas, journey maps, wireframes, redlines, design QA, content style guides

Confidence: **High** for the inventory. **Medium** for standardisation status on individual items; several need verification before any reference material is authored.

## Finding E — JTBD is a family of schools, not one method

Directly relevant to the user's instruction that JTBD is a backing standard. There is no single JTBD; there are distinct schools with different canonical formats and different IP postures.

| School                          | Originator                                      | Canonical form                                                             | IP posture                                                                                                                                              |
|---------------------------------|-------------------------------------------------|----------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| Outcome-Driven Innovation       | Tony Ulwick, Strategyn                          | Job statement plus quantified desired outcomes; outcome-based segmentation | Methodology published openly in books; process material is © Strategyn. Not trademarked. Paraphrase-first; do not reproduce Strategyn process artifacts |
| Christensen / Innosight school  | Clayton Christensen and colleagues              | Job framed by circumstance and context rather than customer attributes     | Published in HBR and books; standard academic/commercial copyright. Cite and paraphrase; do not reproduce article text                                  |
| Job Stories                     | Alan Klement, associated with Intercom practice | No form adopted by this capability                                         | No verified reuse grant was located. Cite the school when relevant, but do not reproduce its template or examples.                                      |
| Switch interviews / demand-side | Bob Moesta                                      | Interview technique targeting switch moments and timelines                 | Primarily consulting and speaking; limited formal publication. Cite as practice, do not claim a canonical spec                                          |
| JTBD Playbook                   | Jim Kalbach                                     | Step-by-step activities and templates                                      | Commercially published book (Rosenfeld Media). Cite only; do not reproduce templates                                                                    |

Practical consequence: no JTBD template is adopted by this capability. Where a source is discussed, name its school and cite it without reproducing wording, process artifacts, scoring instruments, or examples. For a reusable situation, motivation, and outcome form, use the verified Open Government Licence source in the GOV.UK Service Manual instead.

Confidence: **High** on the existence and distinctness of the schools. **Medium** on precise IP posture per school — verify before authoring reference material.

## Finding F — licensing pitfalls confirmed and extended

| Source                                                               | Posture                                          | Note                                                                                                                                           |
|----------------------------------------------------------------------|--------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------|
| DDaT Capability Framework                                            | **OGL v3.0 — reusable with attribution**         | Best available openly-licensed description of UX roles and skills                                                                              |
| GOV.UK Service Manual and Design System                              | **OGL v3.0**                                     | Service phases, patterns, research practice                                                                                                    |
| ISE Engineering Playbook                                             | **CC BY 4.0**                                    | Design process, Design Ops, usability characteristics                                                                                          |
| USWDS                                                                | **Public domain**                                | Design system and token patterns                                                                                                               |
| W3C specs (WCAG, ARIA, APG, Graphics Module, SVG-AAM, ATAG, WCAG-EM) | **W3C Document License**                         | Paraphrase-first; verbatim with attribution                                                                                                    |
| Design Tokens Community Group format                                 | **W3C CG**                                       | Emerging; format spec usable                                                                                                                   |
| ISO 9241 family (-11 usability, -210 HCD)                            | **Cite-only**                                    | Never reproduce. Activity names and clause identifiers are facts; prose is not                                                                 |
| Nielsen's 10 heuristics                                              | **Cite-only, NN/g copyright**                    | Highest practical risk; routinely copy-pasted. Express as original prose or omit                                                               |
| NN/g UX maturity model                                               | **Cite-only**                                    | Assessment service, not an open spec                                                                                                           |
| Google HEART / GSM                                                   | **Widely referenced, no located canonical spec** | Treat as practice, cite carefully, do not claim a standard                                                                                     |
| SUS                                                                  | **Ambiguous**                                    | Brooke 1996 chapter, Taylor & Francis. Widely treated as free to use; **verify before reproducing the 10 items**. Paraphrase the method safely |
| SUPR-Q                                                               | **Proprietary (MeasuringU)**                     | Cite only                                                                                                                                      |
| NASA-TLX                                                             | **Public domain (NASA)**                         | Safe; useful for high-workload contexts                                                                                                        |
| Design Council Double Diamond                                        | **Openly published, Design Council terms**       | Verify reuse terms before reproducing diagrams or phase definitions                                                                            |
| Figma Dev Mode / Code Connect                                        | **Proprietary product**                          | Reference as tooling, not as standard                                                                                                          |

## What this changes

1. **The organising principle is contested.** Playbook says assets; profession framework says capabilities. Both are legitimate and openly licensed. The capability should probably be **capability-organised and asset-emitting**, but that is a Method 4 decision, not a finding.
2. **Facilitation is in scope or the tool serves half the job.** Session design, consensus-building, advocacy, and mentoring are named skills. None of them are documents.
3. **JTBD needs a named school.** Not a generic feature.
4. **The best-licensed source is OGL, not CC BY.** DDaT is more directly about practitioners than the ISE playbook, and it is reusable.

## Remaining gap

HMW9 is not closed. Zero practitioners interviewed. This research replaces the coach's imagination with published professional consensus — a real improvement, and still not a substitute for asking someone who does the job.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
