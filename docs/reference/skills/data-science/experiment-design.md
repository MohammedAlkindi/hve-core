---
title: experiment-design
description: "Experiment design reference for Minimum Viable Experiment coaching, hypothesis formation, vetting and red flags, model-experimentation conventions, and ML checklist structure. Use when framing, vetting, or setting up an experiment and its evaluation."
sidebar_position: 2
ms.date: 2026-08-01
---

<!-- BEGIN AUTO-GENERATED: metadata -->
| Field       | Value                                           |
|-------------|-------------------------------------------------|
| Kind        | skill                                           |
| Source      | `.github/skills/data-science/experiment-design` |
| Invocation  | Loaded on demand by referencing agents          |
| Interactive | No                                              |
<!-- END AUTO-GENERATED: metadata -->

## What it does

<!-- BEGIN AUTO-GENERATED: overview -->
Experiment design reference for Minimum Viable Experiment coaching, hypothesis formation, vetting and red flags, model-experimentation conventions, and ML checklist structure. Use when framing, vetting, or setting up an experiment and its evaluation.
<!-- END AUTO-GENERATED: overview -->

## When to use it

Reach for this skill when work needs an experiment framed, vetted, or made reproducible:

* Shaping a Minimum Viable Experiment: choosing the experiment type, judging whether it is worth pursuing, and recognizing red flags that mean it is not.
* Turning a vague idea into a falsifiable hypothesis with a stated success threshold.
* Setting up experimentation hygiene: environment reproducibility, tracked runs, versioned datasets, and recorded metrics.
* Working through ML fundamentals or model-production readiness checklists.

The skill is general purpose. Despite living in the data-science collection, its MVE coaching applies to any experiment, not only machine-learning work.

Choose a different asset when:

* The question is about data tiering, pipeline invariants, or data test suites. Use the `ds-dataops` skill.
* The question is about MVE tracking-artifact naming or session-directory layout. That is governed by `experiment-designer.instructions.md`, which applies automatically under `.copilot-tracking/mve/`.
* You want an interactive coach rather than a reference. Use the `Experiment Designer` agent, which loads this skill.

## Example usage

Ask an agent that loads this skill to pressure-test an idea:

```text
We think adding a re-ranking step will improve retrieval quality.
Help me turn that into an MVE.
```

The skill supplies the hypothesis format, the vetting criteria used to decide whether the experiment earns its cost, and the red flags that mark an experiment as unfalsifiable or already answered. It then produces a hypothesis statement with an explicit success threshold and a backlog brief that hands the result to downstream planning.
