---
title: Method 04 Practice Moment Clustering and Value Assessment
description: Clustering of candidate practice moments with frequency, difficulty, support, and uniqueness assessment.
sidebar_position: 13
author: Microsoft
ms.date: 2026-08-05
ms.topic: concept
---

<!-- markdownlint-disable-file -->

## Method 04: Practice moment clustering and value assessment

Convergent exercise on the twenty candidate moments. Clusters by the underlying capability each moment needs, then assesses value.

Method note: the earlier grouping (discovery, synthesis, design, working with others, handoff) was organised by **when in a process** a moment happens. That axis was inherited from process frameworks, and it is the axis this project already ruled out for forking. Re-clustering here by **what kind of help the practitioner needs**, which is closer to how a coaching capability would actually be built.

## Clusters by capability needed

### C-A — Framing under uncertainty

Moments where the practitioner must commit to a framing before the evidence is complete.

M1 framing what we don't know · M4 framing demand as a job · M6 deciding what the problem is · M7 turning evidence into a hypothesis

Common capability: helping someone name a thing precisely without prematurely closing it. Coaching-heavy. Artifacts are short and high-leverage — a research question set, a job story, a problem statement, a hypothesis.

### C-B — Reasoning from evidence

Moments where the practitioner has material and must extract meaning from it without fooling themselves.

M5 making sense of what we heard · M8 choosing between directions · M17 deciding what good means · M18 planning an evaluation

Common capability: structured reasoning with bias resistance. Both modes needed — coaching to challenge, artifacts to record.

### C-C — Declaring intent precisely

Moments where a decision must be written down unambiguously enough to be built and checked against.

M9 structuring information and flow · M10 deciding what a surface must convey · M16 handing intent to engineering · M19 checking what shipped matches intent

Common capability: producing specifications a machine or an engineer can act on. Artifact-heavy. This is the cluster where the shared evidence model matters most — M10's declaration should be the same object M19 checks against.

### C-D — Moving people

Moments where the obstacle is other humans, not the design.

M12 running a session · M13 running a critique · M14 making the case to a sceptic · M15 building consensus · M20 growing the practice

Common capability: preparation, framing, and in-the-moment adaptation. Pure coaching. No artifact is the point; a session plan or an argument outline is scaffolding, not output.

### C-E — Calibrating effort

Moments about doing the right amount of work.

M2 planning research that survives contact · M3 designing for inclusion from the start · M11 choosing the right fidelity

Common capability: scoping judgment under constraint. Coaching-led with light artifacts.

## Value assessment

Four dimensions. Each rated High / Medium / Low with the reason stated. Evidence provenance marked: **[M]** measured in repo or code, **[D]** document-grounded, **[I]** inference.

| Cluster                        | Frequency  | Difficulty | Current support | Uniqueness |
|--------------------------------|------------|------------|-----------------|------------|
| C-A Framing under uncertainty  | High [D]   | High [D]   | Low [M]         | Medium     |
| C-B Reasoning from evidence    | Medium [D] | High [D]   | Low [M]         | Medium     |
| C-C Declaring intent precisely | High [D]   | Medium [D] | Partial [M]     | **High**   |
| C-D Moving people              | High [D]   | High [D]   | **None** [M]    | **High**   |
| C-E Calibrating effort         | High [I]   | Medium [D] | Low [M]         | Low        |

Column definitions:

* **Frequency** — how often a practitioner hits this.
* **Difficulty** — how hard it is to do well, per the DDaT skill-level descriptions.
* **Current support** — what already exists in this repository or in common tooling.
* **Uniqueness** — how much of this a general-purpose assistant would fail at without the standards grounding and structure being designed here.

### Where the value concentrates

**C-C and C-D are the two high-uniqueness clusters, for opposite reasons.**

C-C is unique because it needs **grounding a general model does not have**. Declaring what a surface must convey non-visually requires WAI-ARIA Graphics Module and SVG-AAM reasoning that is not general knowledge. This cluster also contains the only capability with no precedent anywhere (M10) and the only loop-closure opportunity (M10 declared, M19 checked). Existing partial support — scanners, review perspectives — verifies but never declares, which is exactly theme T3.

C-D is unique because it needs **structure a general model does not apply**. Asking a chat assistant "how do I run a critique" produces generic advice. The value is in a coached, prepared, adaptive sequence grounded in a named practice — and in *nothing existing at all* today. Highest difficulty, highest frequency, zero current support, and the entire justification for the coaching mode.

**C-A is high value but partially served.** Framing help is the thing general assistants are least bad at. The differentiator is standards grounding and the discipline of not closing prematurely — real, but narrower.

**C-B is valuable and hardest to prove.** Bias-resistant reasoning is genuinely difficult and genuinely underserved, but success is hard to observe. Worth building, poor choice for a first proof.

**C-E is the weakest.** Frequency rests on inference rather than evidence, difficulty is moderate, and scoping judgment is close to what experienced practitioners already do well. First candidate to defer.

## Revised recommendation

Lead with **C-C and C-D**. They are the two clusters where the designed capability is doing something a general-purpose assistant cannot, and together they preserve both modes by construction — C-C is the artifact half, C-D is the coaching half.

A defensible first set:

| Moment                                   | Cluster | Role                                                        |
|------------------------------------------|---------|-------------------------------------------------------------|
| M10 Deciding what a surface must convey  | C-C     | The unprecedented capability; declares intent               |
| M16 Handing intent to engineering        | C-C     | Where UX work reaches the process that consumes it          |
| M19 Checking what shipped matches intent | C-C     | Closes the loop against M10                                 |
| M13 Running a critique                   | C-D     | Most concrete facilitation moment; proves the coaching mode |
| M14 Making the case to a sceptic         | C-D     | Highest-felt, thinnest published grounding                  |
| M6 Deciding what the problem is          | C-A     | Gates everything; without it the rest floats                |

Six moments. Three declaring intent, two moving people, one framing.

### What changed from the earlier cut

The previous seven-moment cut was spread evenly across process phases and included M2, M5, and M8 — all well-documented, all things a general assistant handles passably. It included only one facilitation moment.

This cut drops M2, M5, and M8 and adds M14 and M19. The reasoning: **process-phase balance is not a value criterion.** Concentrating on the two clusters where the capability is genuinely differentiated is worth more than covering the whole process thinly.

M14 was previously cut for having the thinnest published grounding. On reflection that was backwards — thin published grounding and high felt difficulty is precisely where a designed capability earns its existence. Recorded as a correction rather than a preference change.

## Standing caveats

* Frequency and difficulty ratings are read from published role frameworks, not observed. HMW9 remains open.
* C-D has the least citable grounding of any cluster, which is both the reason it is valuable and the reason it is hardest to build defensibly.
* Loop closure between M10 and M19 assumes a shared evidence model that does not yet exist and has not been designed.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
