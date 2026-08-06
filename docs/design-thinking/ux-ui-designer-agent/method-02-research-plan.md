---
title: Method 02 Research Plan
description: Planning artifact defining the desk research approach for the UX agent redesign.
sidebar_position: 4
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 02: Research plan

Planning artifact. Phase 1 of Method 2. No research executed yet.

## The reframe that reset this plan

Stated by the user on 2026-08-01:

> we're not here to troubleshoot the data viewer but rather use that framing to design the agentic tooling base that will make projects like that successful from a UI/UX perspective

This changes the research subject. The data viewer is a **lens**, not the client.

|                      | Before reframe                                 | After reframe                                                 |
|----------------------|------------------------------------------------|---------------------------------------------------------------|
| Who we design for    | Data scientists and operators using the viewer | Teams building UIs like the viewer                            |
| What "success" means | The viewer becomes accessible                  | Projects like the viewer don't end up here in the first place |
| The viewer's role    | The patient                                    | The autopsy                                                   |

## Nested user structure

The agentic tooling has a user. That user has a user. Both matter, but only one of them is ours.

```text
HVE UX tooling  →  builder (engineer/data scientist writing the viewer)  →  end user (data scientist/operator reviewing VLA output)
                   ^^^^^^^ our user                                         ^^^^^^^ our user's user
```

Design consequence: our tooling succeeds when it changes what the **builder** does. Accessibility for the end user is the outcome, not the interface. A skill that produces perfect WCAG specs which no builder ever reads has failed, regardless of the quality of the specs.

## Research objectives (prioritized)

| #  | Objective                                                                        | Why it matters                                                                                    | Confidence today            |
|----|----------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|-----------------------------|
| O1 | Understand what builders actually did, and when, on the viewer                   | The gaps cluster in visualization surfaces — was that a decision, a deferral, or invisible?       | None                        |
| O2 | Find the moment accessibility was decidable but not decided                      | Tooling has to intervene at a real moment in a real workflow, not "during design" in the abstract | None                        |
| O3 | Determine why the existing UX/UI Designer agent went unused                      | A1 validated by owner report, but the failure mode is unknown                                     | None                        |
| O4 | Establish what standards genuinely cover vs. where reasoning must be constructed | Determines whether the skill is a lookup table or a reasoning aid                                 | Partial (Method 1 evidence) |
| O5 | Separate the "jumbled" complaint from the "inaccessible" complaint               | Deliberately deferred in Method 1; still unresolved                                               | None                        |

## Tiered research targets

| Tier | Who                                                                  | Access                        | Priority            |
|------|----------------------------------------------------------------------|-------------------------------|---------------------|
| 1    | Engineers who built the viewer frontend                              | Unknown — must be established | Highest             |
| 1    | The person who described it as "a jumbled inaccessible hunk of code" | Available (session user)      | Highest             |
| 2    | Data scientists and operators reviewing VLA outputs                  | Unknown                       | High — validates O5 |
| 2    | Anyone who has tried the existing UX/UI Designer agent               | Unknown                       | High — O3           |
| 3    | Accessibility practitioners with scientific-visualization experience | External                      | Medium — O4         |

Access strategy is an open gap. No Tier 1 or Tier 2 contact has been established.

## Method selection

Two tracks, deliberately paired. Track A is cheap and available now; Track B is the one that produces genuine discovery. Track A is not a substitute for Track B.

### Track A — Artifact archaeology (available immediately, no human access needed)

Legitimate research when direct access is constrained. Code and history are behavioral traces: they record what builders did under real pressure.

| Study                                           | Question it answers                                                                                                       | Source                         |
|-------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------|--------------------------------|
| A1. Git archaeology on `data-management/viewer` | When did visualization components land relative to a11y-adjacent commits? Was accessibility ever attempted and abandoned? | Commit history, PR titles      |
| A2. jsx-a11y suppression scan                   | Are there `eslint-disable jsx-a11y` comments? Each one is a moment where a builder saw a warning and chose to move on.    | Source scan                    |
| A3. Component chronology                        | Did the accessible-chrome / inaccessible-payload split emerge early or late?                                              | File history                   |
| A4. Existing agent output review                | What does the current UX/UI Designer agent actually produce for a surface like this?                                      | Run it                         |
| A5. Standards coverage probe                    | Which viewer surfaces map cleanly to WCAG/APG success criteria, and which have no applicable criterion?                   | Accessibility skill references |

### Track B — Direct engagement (required for genuine discovery)

| Study                          | Target                                    | Method                                                                                                 |
|--------------------------------|-------------------------------------------|--------------------------------------------------------------------------------------------------------|
| B1. Builder workflow interview | Viewer frontend engineers                 | Walk me through building `TrajectoryPlotChart`. What did you consider? What did you not have time for? |
| B2. Review-session observation | Data scientist or operator                | Watch an actual VLA output review end to end. Do not ask about accessibility.                          |
| B3. Agent post-mortem          | Anyone who tried the UX/UI Designer agent | What did you ask it? What did you do with the output?                                                  |

## Interview question drafts (Track B)

For builders (B1) — target the decision moment, not the opinion:

* Walk me through the day you built the trajectory chart. What was the goal?
* When you picked recharts, what were you trading off?
* Did an accessibility concern ever come up? What happened to it?
* You have jsx-a11y running. What do you do when it flags something?
* If someone had handed you a document about accessible time-series charts that morning, what would you have done with it?

For end users (B2) — observe, do not lead:

* Show me how you review a training run. (Then be quiet.)
* What are you looking for when you scrub the timeline?
* What do you do when something looks wrong?
* Tell me about the last time this tool made you redo work.

Anti-patterns to avoid: asking "do you care about accessibility" (everyone says yes), asking users to validate the tooling concept, asking builders to self-report failures.

## Assumption validation targets

Carried from Method 1. Each needs a study assigned.

| ID | Assumption                                | Validating study                                 |
|----|-------------------------------------------|--------------------------------------------------|
| A1 | Current agent underperforms               | O3 via A4, B3                                    |
| A2 | Gap is knowledge grounding                | A5                                               |
| A3 | Gap is artifact coverage                  | B1, B3                                           |
| A4 | Gap is lack of real UI input              | Partially falsified for docs; retest here via A4 |
| A5 | Users want more artifacts                 | B3 — actively suspect                            |
| A6 | Accessibility disconnected from authoring | A1, A2, B1                                       |

## Known research gaps (stated explicitly)

* No Tier 1 or Tier 2 human contact established. Track A alone cannot resolve O1, O2, O3, or O5.
* No evidence any assistive-technology user has ever used the viewer. The accessibility concern may be anticipatory rather than reported — which is legitimate but changes urgency framing.
* `edge-ai` and the docs platform are excluded for now. Findings may not generalize; this is accepted deliberately.
* The session user is both stakeholder and proxy user. Convenient, and a confirmation-bias risk worth naming.

## Exit criteria for Phase 1

Research plan exists with prioritized objectives, tiered targets, selected methods, and named gaps. Met by this document.

## Exit criteria for Phase 2

Raw notes exist per study with direct quotes and specific observations. Not started.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
