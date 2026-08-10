---
title: Shared/Decision Spine
description: "Shared decision-spine vocabulary: the six stages agents display to users, the mapping from every existing phase vocabulary, the annotation convention, and the Outside Resources grouping"
sidebar_position: 3
ms.date: 2026-08-09
---

<!-- BEGIN AUTO-GENERATED: metadata -->
| Field       | Value                                                                                                                                                                                                                                                                                                                                                  |
|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Kind        | instruction                                                                                                                                                                                                                                                                                                                                            |
| Source      | `.github/instructions/shared/decision-spine.instructions.md`                                                                                                                                                                                                                                                                                           |
| Invocation  | Applied automatically to `**/.github/instructions/**/*identity*.instructions.md, **/.github/instructions/security/sssc-planner.instructions.md, **/.github/instructions/shared/planner-identity-base.instructions.md, **/.github/agents/**/*planner*.agent.md, **/.github/agents/design-thinking/dt-coach.agent.md, **/.github/skills/rpi/**/SKILL.md` |
| Interactive | No                                                                                                                                                                                                                                                                                                                                                     |
<!-- END AUTO-GENERATED: metadata -->

## What it does

<!-- BEGIN AUTO-GENERATED: overview -->
Shared decision-spine vocabulary: the six stages agents display to users, the mapping from every existing phase vocabulary, the annotation convention, and the Outside Resources grouping
<!-- END AUTO-GENERATED: overview -->

## When to use it

This file is the single source for the six stage names HVE-Core agents speak to users: `Understand`, `Explore`, `Decide`, `Challenge`, `Execute`, and `Verify`. Reach for it when you are authoring or editing any artifact that names a phase, and you need to know which stage that phase occupies.

It applies automatically to the planner identity instructions, the shared planner scaffold, the planner agents, the Design Thinking coach, and the RPI skills. Those artifacts display stage names rather than restating the mapping, so a change here propagates instead of forking.

Use it when you need to answer any of these:

* Which stage does a given phase, method, or skill occupy.
* Whether two workflows that share a phase name, such as ADR `Govern` and requirements-authoring `Govern`, mean the same position.
* What the annotation convention is, so a new artifact does not invent an eighth vocabulary.
* What counts as out of bounds, which is every value a machine reads: state schema fields, phase enum values, internal slugs, and skill section anchors.

Reach for something else when the numbering you are looking at is a procedure rather than a decision arc. Backlog and pull request workflows that number steps `Phase 1` through `Phase 6`, and session-lifecycle numbering such as an agent's initialization, active-work, transition, and closure phases, carry no stage and are never annotated.

## Example usage

A planner instruction file annotates its phase heading by appending the stage in parentheses, leaving the phase number and name untouched:

```markdown
### Phase 4: Security Model Analysis (Decide)
```

When a heading already carries a second vocabulary, such as the RAI planner's NIST function names or the Accessibility planner's internal slugs, the file adds a same-file mapping table instead of a second parenthetical, so the existing annotation survives:

```markdown
### Decision Spine Stages

| Phase   | Slug                   | Stage        |
|---------|------------------------|--------------|
| Phase 1 | `discovery`            | `Understand` |
| Phase 2 | `framework-selection`  | `Explore`    |
```

At runtime an agent renders the stage beside the vocabulary the user already sees, never in place of it:

```text
Method 4: Brainstorming, solution space, stage Explore
```

The stage is display text in every case. It changes no phase number, phase name, internal slug, gate, transition, or persisted `state.json` value.
