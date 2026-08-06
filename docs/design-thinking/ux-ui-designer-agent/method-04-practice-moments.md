---
title: Method 04 Practice Moments
description: Candidate spine of UX practice moments considered for the agent ecosystem.
sidebar_position: 14
author: Microsoft
ms.date: 2026-08-05
ms.topic: concept
---

<!-- markdownlint-disable-file -->

## Method 04: Practice moments (candidate spine)

The coaching mode's organising axis. These are the moments a UX practitioner is doing something hard enough to want a coach — the equivalent of what the nine methods are to Design Thinking coaching.

**Licensing posture.** Every moment below is original prose authored for this repository (CC BY 4.0). Where a moment draws on an upstream source, the grounding column names it and the class column states the reuse posture. No upstream prose is reproduced anywhere in this file. Cite-only sources appear as citations, never as text.

Class shorthand: **OGL** UK Open Government Licence v3.0 · **CC BY** Creative Commons Attribution 4.0 · **W3C** W3C Document License · **PD** public domain · **CITE** cite-only, never reproduced · **ORIG** repository original content.

## Candidate moments

### Discovery and framing

| #  | Moment                                      | The hard part                                                                    | Grounding                                                                       | Class        |
|----|---------------------------------------------|----------------------------------------------------------------------------------|---------------------------------------------------------------------------------|--------------|
| M1 | Framing what we don't know                  | Turning a vague ask into researchable questions without smuggling in a solution  | DDaT user research methods; research management, leadership and assurance       | OGL          |
| M2 | Planning research that will survive contact | Choosing methods, sequencing, recruiting, and scoping under real time pressure   | DDaT user research methods; agile research practices; GOV.UK discovery practice | OGL          |
| M3 | Designing for inclusion from the start      | Deciding who might be excluded before anything is built                          | DDaT inclusive research; designing for everyone; WCAG/COGA framing              | OGL + W3C    |
| M4 | Framing demand as a job                     | Expressing user need as progress-in-a-circumstance rather than a feature request | Job story syntax (open); JTBD principle in original prose                       | ORIG + cited |

### Synthesis and sense-making

| #  | Moment                                      | The hard part                                                                      | Grounding                                                                    | Class       |
|----|---------------------------------------------|------------------------------------------------------------------------------------|------------------------------------------------------------------------------|-------------|
| M5 | Making sense of what we heard               | Moving from raw evidence to themes without pattern-forcing or confirmation bias    | DDaT analysis and synthesis                                                  | OGL         |
| M6 | Deciding what the problem actually is       | Committing to a problem framing when evidence is partial and stakeholders disagree | DDaT evidence-based design; ISE playbook desired outcomes                    | OGL + CC BY |
| M7 | Turning evidence into a testable hypothesis | Framing design ideas as hypotheses rather than convictions                         | DDaT evidence-based design (hypothesis framing is explicit in the framework) | OGL         |

### Design decisions

| #   | Moment                                | The hard part                                                                    | Grounding                                                | Class       |
|-----|---------------------------------------|----------------------------------------------------------------------------------|----------------------------------------------------------|-------------|
| M8  | Choosing between design directions    | Comparing options honestly when one is already favoured                          | ISE playbook trade studies; DDaT designing strategically | CC BY + OGL |
| M9  | Structuring information and flow      | Deciding how content and tasks are organised before visual design starts         | DDaT interaction design scope; IA practice               | OGL         |
| M10 | Deciding what a surface must convey   | Declaring what any user must perceive and be able to do — including non-visually | WAI-ARIA Graphics Module; SVG-AAM; ARIA APG              | W3C         |
| M11 | Choosing the right fidelity right now | Resisting polish when rough would learn faster, and vice versa                   | DDaT iterative design                                    | OGL         |

### Working with others

| #   | Moment                                    | The hard part                                                                  | Grounding                                                     | Class |
|-----|-------------------------------------------|--------------------------------------------------------------------------------|---------------------------------------------------------------|-------|
| M12 | Running a session that produces something | Designing and facilitating a working session rather than holding a meeting     | DDaT designing together                                       | OGL   |
| M13 | Running a critique that improves the work | Giving and receiving design feedback without defensiveness or vagueness        | DDaT designing together; design communication                 | OGL   |
| M14 | Making the case to a sceptic              | Justifying a design decision with evidence to someone unconvinced              | DDaT design communication; user-centred practice and advocacy | OGL   |
| M15 | Building consensus across boundaries      | Aligning people with different incentives, including outside the delivery team | DDaT designing together; stakeholder relationship management  | OGL   |

### Handoff and quality

| #   | Moment                                          | The hard part                                                                       | Grounding                                                      | Class                           |
|-----|-------------------------------------------------|-------------------------------------------------------------------------------------|----------------------------------------------------------------|---------------------------------|
| M16 | Handing design intent to engineering            | Communicating intent so it survives implementation, including states and edge cases | ISE playbook Design Ops; component and token practice          | CC BY + W3C                     |
| M17 | Deciding what "good" means here                 | Defining measurable quality expectations before building                            | ISE playbook usability characteristics; measurement frameworks | CC BY (+ CITE for ISO concepts) |
| M18 | Planning an evaluation                          | Designing a usability or accessibility evaluation that answers a real question      | DDaT user research methods; WCAG-EM methodology                | OGL + W3C                       |
| M19 | Checking that what shipped is what was designed | Comparing implementation to intent without becoming a pixel police officer          | ISE playbook Design Ops feedback loops                         | CC BY                           |

### Practice and growth

| #   | Moment                          | The hard part                                                             | Grounding                                               | Class |
|-----|---------------------------------|---------------------------------------------------------------------------|---------------------------------------------------------|-------|
| M20 | Growing the practice around you | Advocating for user-centred work, mentoring, improving how the team works | DDaT leading design; user-centred practice and advocacy | OGL   |

## Observations on the shape

**Twenty is too many.** DT has nine. A first cut should be substantially smaller. This list is deliberately over-generated so cutting is a decision rather than an omission.

**Five moments are pure facilitation.** M12–M15 and M20 produce no document at all. These are the ones that justify the coaching mode existing — and the ones most likely to be cut by an artifact-minded reviewer, which would quietly re-narrow the project the way Method 3 got narrowed.

**Several moments pair naturally with artifacts.** M2 with a research plan, M6 with a problem statement, M8 with a trade study, M10 with a surface semantics spec, M17 with quality criteria. This is where the shared evidence model earns its place: the same object is coached toward and then rendered.

**M10 is the one with no precedent.** Everything else has an established practice somewhere. Deciding what a surface must convey — including non-visually — is the gap found in Method 1, and the W3C graphics specs are the only real grounding available.

**M4 carries the JTBD licensing decision.** Job story syntax is the safe entry point; the underlying principle gets expressed in original prose with attribution to originators; ODI outcome statements are cited and paraphrased, never templated. Any output names its school.

## Candidate first cut

If forced to pick a defensible starting set today, on current evidence:

| Keep                                    | Why                                                             |
|-----------------------------------------|-----------------------------------------------------------------|
| M2 Planning research                    | Highest-frequency practitioner task with a clear artifact       |
| M5 Making sense of what we heard        | Named DDaT skill, hard, poorly supported by tooling             |
| M6 Deciding what the problem is         | Gates everything downstream                                     |
| M8 Choosing between directions          | The playbook's actual decision instrument                       |
| M10 Deciding what a surface must convey | The genuine gap; nothing else fills it                          |
| M13 Running a critique                  | The most concrete facilitation moment; proves the coaching mode |
| M16 Handing intent to engineering       | Where UX work meets the process that consumes it                |

Seven. Three research-and-synthesis, two design-decision, one facilitation, one handoff. Preserves both modes.

**This cut is a hypothesis, not a recommendation.** It is derived from published frameworks and repository evidence, with zero practitioner input. The most likely error is keeping moments that are well documented over moments that are actually painful — documentation density is not the same as difficulty.

## Open questions

* Is twenty the right granularity, or are several of these the same moment named differently?
* Which moments do practitioners actually get stuck in? Unanswerable without HMW9.
* Do the facilitation moments need session state the way DT coaching does, or are they short enough to be stateless?
* Does M20 belong in a practitioner tool at all, or is it a different audience?

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
