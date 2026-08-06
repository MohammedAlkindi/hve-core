---
title: Method 01 Scope Boundaries
description: Rough scope capture for the data viewer UX, including target surface, users, and measured evidence.
sidebar_position: 2
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## Method 01: Scope boundaries for the data viewer UX

Rough scope capture. Conversational, not requirements.

## The problem, as stated by the user

> data scientists and operators use the viewer to review training outputs from VLAs
>
> the ux for the data viewer [...] needs hella help ... it's a jumbled inaccessible hunk of code

A1 ("the current experience underperforms") is now **validated by owner report**. Still unvalidated by direct user observation — the people reviewing VLA outputs have not been interviewed in this session.

## Target surface

`azure-nvidia-robotics-reference-architecture/data-management/viewer` — "Dataset Analysis Tool". FastAPI backend, React + Vite + TypeScript frontend. ~93 components, 7 zustand stores, 17 test files.

## Users identified

| User            | Job being hired for                                              | Notes                                         |
|-----------------|------------------------------------------------------------------|-----------------------------------------------|
| Data scientists | Review training outputs from VLA (Vision-Language-Action) models | Exploratory, comparative, session-length work |
| Operators       | Review training outputs, annotate episodes                       | Task-driven, throughput-sensitive             |

Both are **unvalidated personas**. No interviews conducted. Their distinct needs have not been separated — this is a known gap, not a resolved question.

## Evidence gathered (measured from code)

### What is NOT broken

The characterization "jumbled inaccessible hunk of code" is **partially contradicted** by the evidence. The foundation layer is in better shape than reported:

* shadcn/ui over Radix primitives — 20 UI components inheriting correct ARIA and focus behavior.
* `eslint-plugin-jsx-a11y` installed and active in `eslint.config.js` with recommended rules.
* Semantic elements used throughout; no widespread `<div onClick>` anti-pattern found at component level.
* Global `focus-visible:ring-1` styling on interactive primitives.
* Design tokens in `src/index.css` — HSL custom properties, status color pairs, dark mode variant.
* Tests query by role and label (`getByRole`, `getByLabelText`), which passively enforces some accessibility.
* Centralized keyboard shortcut hook at `src/hooks/use-keyboard-shortcuts.ts`.

### Where accessibility actually falls off a cliff

Every gap clusters in one place: **the data visualization and media surfaces** — precisely the components that carry the actual analytical payload.

| Surface                                        | What it renders                           | Gap                                                                                                                                                           |
|------------------------------------------------|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `TrajectoryPlotChart.tsx`                      | 17 joints × frame count, recharts SVG     | No text alternative. Range selection is pointer-drag only (`onSelectionPointerDown/Move/Up`) with no keyboard equivalent. Tooltip portal has no role or ARIA. |
| `FramePreview.tsx`                             | Canvas-rendered frame with crop/transform | No alt, no text fallback. `ctx.drawImage` output is opaque to assistive technology.                                                                           |
| `VideoPlayer.tsx`                              | Multi-camera episode video                | No captions or track elements verified.                                                                                                                       |
| `Timeline.tsx` / `TimelineMarker.tsx`          | Anomaly severity clustering on scrubber   | SVG markers; tooltips render as HTML portal without ARIA labels.                                                                                              |
| `DetectionCharts.tsx`, `DetectionTimeline.tsx` | Detection confidence/coverage over frames | No text alternative.                                                                                                                                          |

Cross-cutting absences: **no `aria-live` anywhere** (nothing announces frame changes, save state, export progress, or annotation results), no `role="alert"` on error paths, no skip links, no `aria-describedby`, no undo/redo stack, and no axe/jest-axe integration in the 17 test files.

## The reframe this produces

The felt problem is real. The stated cause is not quite right, and the difference matters.

This is not a codebase that ignored accessibility. It is a codebase that **adopted an accessible component library and then hit the boundary of what component libraries solve.** Radix gives correct dialogs and buttons. Nothing in the shadcn ecosystem tells you how a screen-reader user understands a 17-joint trajectory over 400 frames, or how a keyboard user selects a frame range to create a subtask.

Reframed problem statement (draft, for validation):

> When a data scientist or operator reviews VLA training output, the analytical content itself — trajectories, frames, detections, anomalies over time — is only available through pointer-driven, visually-encoded surfaces. The interface chrome is accessible; the data is not. Standard component libraries do not solve this, and the team has no method for designing or verifying it.

## Why this is the interesting problem

WCAG 2.2, ARIA APG, and axe-core are strong on forms, navigation, and widgets. They are comparatively thin on time-series scientific visualization, spatial/robotic state, and synchronized multi-stream media. This is a genuine frontier, not a compliance backlog. It is also exactly where a standards-backed skill would earn its keep — because the standards alone do not answer the question, and the reasoning has to be constructed.

## Scope boundaries (draft)

In scope:

* The data viewer as the proving ground.
* Visualization and media accessibility as the core design problem.
* Connecting design authoring to verification tooling.

Out of scope for now:

* Rewriting the viewer.
* The docs platform (already has verification; different problem).
* `edge-ai` (not yet examined).
* Generalizing across all three surfaces before one is proven.

Deferred pending evidence:

* S7/S8 (mutating DT Methods 6/7). Still aspirational. Method 6's anti-polish discipline conflicts with standards-conformant output; unresolved.

## Open questions carried into Method 2

* Which user — data scientist or operator — is in more pain, and at what moment?
* Is anyone using assistive technology with this tool today, or is the accessibility concern anticipatory?
* What does a review session actually look like end to end? Nobody in this session has watched one.
* Is "jumbled" a separate complaint from "inaccessible"? Layout/IA problems and assistive-technology problems have different fixes.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
