---
title: Method 04 Divergent Concepts
description: Divergent component and interaction concepts considered during the UX agent ecosystem Design Thinking session.
sidebar_position: 12
author: Microsoft
ms.date: 2026-08-04
ms.topic: concept
---

<!-- markdownlint-disable-file -->

## Method 04: Divergent concepts

Method 4 opens the Solution Space. Discipline: generate multiple distinct directions grounded in the themes before converging on any one.

The user proposed a concrete direction (recorded as D1). It is strong and it arrived first. The alternatives below exist so D1 is chosen rather than defaulted into.

## D1 — Dual-mode agent forking to coaching skills and artifact skills

**User's proposal.** The agent supports both halves of the job identified in Finding B. A coaching/facilitation mode runs against a skill-defined list of conversation facilitations; an artifact mode generates deliverables. The agent routes to whichever the practitioner needs.

Grounding: Finding A (capability-defined profession), Finding B (half the job is social), HMW1, HMW3.

Strengths:

* Directly answers the strongest research finding. No other concept here addresses facilitation at all unless it copies this.
* Matches how practitioners actually move — a session is facilitated, then something gets written up.
* The two modes have genuinely different shapes: facilitation is turn-by-turn and adaptive; artifact generation is structured and templated. A single undifferentiated agent would do both badly.

Open questions:

* Is coaching-vs-artifact the right seam, or is it the most visible seam? See D2–D5.
* The facilitation half substantially overlaps existing Design Thinking coaching capability. Duplication risk is real and should be resolved deliberately, not discovered later.
* Two modes can become two products with one name. What holds them together?

## D2 — Role-forked capability

Fork by practitioner role rather than by mode: user researcher, interaction designer, service designer, content designer. Each fork carries its own methods, vocabulary, and outputs, following the DDaT role definitions.

Grounding: the DDaT framework's own primary organising axis.

Strengths: matches how the profession names itself; a researcher and a content designer genuinely do different work.
Weaknesses: DDaT deliberately *shares* the seven design skills across designer roles, so role-forking would duplicate the shared skills four times. Also poorly suited to the common case where one person holds all roles.

## D3 — Skill-forked capability

Fork along the seven DDaT design skills plus the seven researcher skills. Each skill becomes an addressable capability at awareness/working/practitioner/expert levels.

Grounding: Finding A taken to its logical conclusion.

Strengths: maximum fidelity to the openly-licensed source; the level structure gives natural depth control.
Weaknesses: fourteen skills is a large surface. Practitioners do not think "I need designing-strategically now." Risks being architecturally elegant and practically unusable.

## D4 — Phase-forked capability

Fork by process phase — discover, define, develop, deliver — following Double Diamond or GOV.UK service phases.

Grounding: the process frameworks in Finding D.

Strengths: familiar to practitioners and to stakeholders; maps cleanly onto engineering delivery.
Weaknesses: assumes linear progression, which HMW3 explicitly rejects. Also the axis Design Thinking already occupies.

## D5 — Artifact-forked capability

Fork by deliverable: a persona capability, a journey map capability, a research plan capability, and so on.

Grounding: the playbook asset list and the Finding D artifact canon.

Strengths: concrete, immediately legible, easy to scope and test.
Weaknesses: this is what the current agent already does with three artifacts, and adoption evidence is weak. Finding A says the profession does not define itself this way. Ignores facilitation entirely.

## D6 — Practice-embedded capability

No standalone agent. The capability is a set of skills that other agents and workflows reach for at the moment a UX decision is live — during planning, during review, during implementation.

Grounding: T3 (verification and authoring disconnected), T5 (fragmentation), HMW4, HMW6.

Strengths: solves the adoption problem by removing the need to remember a tool exists. Fits the loop-closure theme better than any other concept.
Weaknesses: no home for facilitation; a practitioner with a deliberate UX session has nowhere to go. Also the hardest to evaluate.

## Cross-cutting observation

D1 and D6 are not actually in competition. D1 gives the practitioner a place to go; D6 brings the practice to where work already happens. A serious design probably needs both, which suggests the real question is not *which fork* but *what is shared across forks*.

The candidate answer: a common vocabulary and a common evidence model. Whatever a facilitated session surfaces should be the same object an artifact renders and the same object a review references. That is the through-line HMW2 and HMW6 are pointing at.

## Duplication check against existing Design Thinking capability

D1's coaching half must be positioned against the existing DT coaching capability, which already provides method-based coaching, hats, progressive hinting, and session state.

|                     | Existing DT coaching            | Proposed UX facilitation              |
|---------------------|---------------------------------|---------------------------------------|
| Organising axis     | Nine DT methods                 | UX practice skills                    |
| Audience            | Team working a design challenge | UX practitioner doing their job       |
| Session shape       | Long-running, staged, stateful  | Likely shorter, task-bound, recurring |
| Standards grounding | DT method canon                 | DDaT, GOV.UK, W3C, playbook           |

Three viable resolutions:

1. **Reuse** — UX facilitation calls DT coaching for anything DT already covers.
2. **Distinct scope** — DT coaches a challenge end to end; UX facilitation coaches a single practice moment (running a critique, framing a research plan, facilitating a prioritisation).
3. **Shared substrate** — both draw on one facilitation primitive library, with different sequencing.

Option 3 is most consistent with the cross-cutting observation. Unresolved; a Method 4 decision, not a finding.

### Decision (2026-08-01)

**A distinct UI/UX coaching practice, derived from DT coaching rather than reusing it.**

Rationale given: the audience is targeted. DT coaching serves a team working a design challenge; UX coaching serves a practitioner doing their job. Same coaching lineage, different audience, different sequencing.

What is inherited from the DT coaching foundation:

* The coaching identity pattern — think internally, share observations, end with choices rather than directives.
* Progressive hinting with escalation levels rather than jumping to answers.
* Session state persistence and resume.
* Fidelity discipline — refusing to over-polish early work.
* The hat-switching pattern: one stable coaching identity, swappable domain expertise.

What is UX-specific and does not come from DT:

* Sequencing axis. DT sequences nine methods across problem/solution/implementation space. UX coaching sequences **practice moments** — framing a research plan, running a critique, facilitating prioritisation, preparing a handoff, planning an evaluation.
* Standards grounding. DDaT skills, GOV.UK service practice, ISE playbook, W3C specs — not the DT method canon.
* Audience assumption. A practitioner with a live task, not a team in a workshop.
* Entry pattern. DT expects a staged engagement; UX coaching is entered repeatedly at arbitrary points.

Relationship to DT coaching: **derivation, not dependency.** The UX practice borrows proven coaching structure. It does not call DT coaching at runtime and does not require a DT session to exist. A practitioner who has never run a DT engagement can use it.

Cost accepted: some coaching-primitive duplication between the two practices. Judged acceptable because the alternative — coupling a practitioner-facing tool to a team-workshop tool — constrains both.

## User-need licensing correction

Later source verification supersedes the earlier JTBD decision in this session artifact.

Use now:

* The GOV.UK Service Manual user-need form covering situation, motivation, and outcome
* Source: <https://www.gov.uk/service-manual/user-research/start-by-learning-user-needs>
* Licence: Open Government Licence v3.0, <https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/>
* Adaptation rule: cite the source and licence, identify changes, and use original wording around the minimal form

Do not reuse:

* Job-story syntax or examples, because no verified reuse grant was located
* Ulwick or Strategyn process material, templates, scoring instruments, or outcome-statement forms
* Christensen article or book text and canonical examples
* Kalbach templates or activity instructions
* Moesta interview scripts

Names, authors, book titles, and canonical URLs may be cited as facts. Inconclusive terms resolve to no reuse, not to a marginal argument for using the material.

## Not yet decided

* Which practice moments make the first cut, and how they are named.
* What the shared vocabulary and evidence model actually are.
* Which assets make a first cut.
* How deeply the capability embeds into other agents' workflows.

## Decided

* Two modes: coaching/facilitation and artifact generation, over a shared vocabulary and evidence model.
* Skills callable by other agents, not only by the standalone agent.
* Every method grounded in a named, cited, appropriately licensed source.
* The verified GOV.UK OGL user-need form replaces the earlier job-story entry point.
* Accessibility and inclusion as one quality dimension among several.
* A distinct UI/UX coaching practice derived from DT coaching, sequenced on practice moments rather than DT methods.

## Ruled out

* Forking by practitioner role — DDaT shares design skills across roles; most users hold several roles at once.
* Forking by process phase — assumes linearity that HMW3 rejects; the axis DT already occupies.
* Forking by artifact — what the current agent already does, with weak adoption evidence.
* Exposing the fourteen DDaT skills as addressable surfaces — faithful to the source, unusable in practice.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
