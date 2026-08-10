---
title: How HVE Core Works
description: What HVE Core is, the six-stage decision spine every workflow shares, and how the pieces fit together
sidebar_position: 2
author: Microsoft
ms.date: 2026-08-09
ms.topic: concept
keywords:
  - decision spine
  - engineering rigor
  - how it works
  - concepts
estimated_reading_time: 6
---

## What HVE Core Is

HVE Core is the codification of engineering rigor in an agentic world.

Rigor is not a document you write once. It is a sequence of decisions. You understand a problem before solving it. You widen the options before committing. You commit deliberately and record why. You attack that commitment before acting on it. You build what was decided. You check the result against what was predicted.

Working with AI makes that sequence easy to skip. A model will produce a confident answer to a question nobody framed, and it will produce it fast enough that the missing steps are not obvious until much later. HVE Core exists to keep the sequence intact when the work moves quickly.

Everything here serves one of six stages of that sequence. Learn the six stages and you can predict where any part of the framework fits and what it is for.

## The Decision Spine

| Stage        | The question it answers                                  |
|--------------|----------------------------------------------------------|
| `Understand` | What is true, who is affected, and what constrains us?   |
| `Explore`    | What are the real options, and what separates them?      |
| `Decide`     | Which option, and why that one?                          |
| `Challenge`  | Does the decision survive an attack before we act on it? |
| `Execute`    | Build what the decision authorized.                      |
| `Verify`     | Did the result match the prediction?                     |

`Challenge` and `Verify` are different checks and both matter. `Challenge` runs before you act, while changing your mind is still cheap. `Verify` runs after you ship, when only measurement tells the truth.

The spine is a loop, not a line. `Verify` returns evidence to `Understand`, so what you learn from one pass becomes the starting condition for the next.

### Not every workflow owns every stage

Some workflows hand off rather than ship. A planning workflow produces a plan, reviews it, and passes it to whoever implements it. That workflow owns a `Challenge` gate at its boundary, but its `Verify` belongs to the team that receives the handoff.

This is a real property of the framework rather than a gap in the documentation, and naming it is the point. When you know which stages a workflow owns, you know which ones you still have to cover yourself.

## How the Pieces Fit

HVE Core ships four kinds of building block. They are not four separate systems. They are four ways of attaching knowledge to a point on the spine.

| Building block | What it contributes                                                        |
|----------------|----------------------------------------------------------------------------|
| Agents         | A persona that holds a conversation and moves you through stages           |
| Prompts        | A single command that starts a specific piece of stage work                |
| Instructions   | Rules that load automatically when you touch matching files                |
| Skills         | Deep domain knowledge that loads on demand when a task needs it            |

A working session usually combines them. You select an agent, it loads the instructions that match what you are editing, it pulls in a skill when the task reaches that domain, and you invoke prompts to jump to specific work. You do not assemble this by hand. The agent does it.

The rule that makes the framework predictable: a building block declares which stage it serves, and stage names are what you see rather than what the system stores. Underneath, each workflow keeps its own phase names, numbers, and identifiers unchanged, so sessions resume and tooling keeps working. The shared vocabulary is a layer for humans.

For the authoring-level view of how these compose, see [AI artifacts](../architecture/ai-artifacts).

## Outside Resources

Not everything in HVE Core sits on the spine, and pretending otherwise would be misleading.

`Outside Resources` groups the assets that support the framework without being a stage of it: experimental tooling for presentations, diagrams, media, and shared boards; the authoring tooling used to build and validate HVE Core itself; installation and distribution assets; and shared infrastructure such as licensing posture, content policy, and telemetry conventions.

This grouping is named but not yet triaged. Its contents are being sorted in a separate effort.

## Where to Start

1. [Install HVE Core](install) and pick the package that matches your scope.
2. [Have your first interaction](first-interaction) to see an agent respond.
3. [Run your first research pass](first-research) against your own codebase.
4. [Complete a full workflow](first-workflow) through the whole loop.

> [!TIP]
> The fastest way to feel the spine is to run one loop end to end on something small. Reading about `Challenge` is much less convincing than watching a critique find a hole in your own plan.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
