---
description: "Shared decision-spine vocabulary: the six stages agents display to users, the mapping from every existing phase vocabulary, the annotation convention, and the Outside Resources grouping"
applyTo: '**/.github/instructions/**/*identity*.instructions.md, **/.github/instructions/security/sssc-planner.instructions.md, **/.github/instructions/shared/planner-identity-base.instructions.md, **/.github/agents/**/*planner*.agent.md, **/.github/agents/design-thinking/dt-coach.agent.md, **/.github/skills/rpi/**/SKILL.md'
---

# Decision Spine

HVE-Core workflows describe one engineering decision arc under several independent phase vocabularies. This file declares the shared vocabulary those workflows display to users, and the mapping from each existing vocabulary onto it.

This is a display and navigation layer. It changes nothing a machine reads.

## The Six Stages

| Stage        | Intent                                                                |
|--------------|-----------------------------------------------------------------------|
| `Understand` | Establish what is true, who is affected, and what constrains the work |
| `Explore`    | Widen the option space and gather the evidence that separates options |
| `Decide`     | Commit to an option and record the reasoning that justifies it        |
| `Challenge`  | Attack the commitment before acting on it                             |
| `Execute`    | Produce the change or artifact the decision authorized                |
| `Verify`     | Test the shipped result against what the decision predicted           |

### Challenge and Verify are not the same check

`Challenge` runs before acting and can still change the decision cheaply. Its question is whether the commitment survives scrutiny.

`Verify` runs after acting and measures the real result. Its question is whether the prediction held.

A workflow that only reviews its own output before handing it off has a `Challenge` gate, not a `Verify` gate.

### The arc is a loop

`Verify` returns evidence to `Understand`. A finding that closes one pass becomes an input to the next. A workflow that ends at `Execute` or `Challenge` hands its loop closure to whoever receives the handoff.

### Traversal order is workflow-specific

The stage table lists the canonical order of the arc. It does not promise that every workflow visits the stages in that order.

Two mapped workflows deliberately move against it. Planners reach `Execute` before `Challenge`. Design Thinking returns from `Decide` to `Explore` between methods 3 and 4.

When a transition moves against the canonical order, state the one-clause reason alongside the stage name. A user meeting the annotation mid-session sees only the parenthetical, never the prose that justifies it, so an unexplained backward step reads as regression. Each consuming file carries the reason for its own out-of-order transitions.

## Mapping From Existing Vocabularies

Existing phase names stay exactly as they are. These rows say which stage each phase serves.

### RPI

| Existing phase or skill        | Stage                   |
|--------------------------------|-------------------------|
| `rpi-research`                 | `Understand`, `Explore` |
| `rpi-plan`                     | `Decide`                |
| `rpi-plan-critique`            | `Challenge`             |
| `rpi-challenger`               | `Challenge`             |
| `rpi-implement`                | `Execute`               |
| `rpi-review`                   | `Verify`                |
| `rpi-quick`                    | all six                 |
| `rpi-walkthrough`              | `Understand`            |

### Five planners

Security, SSSC, RAI, Accessibility, and Privacy planners share one six-position shape, so the mapping is by position rather than by name.

| Phase position | Security                | SSSC                     | RAI                         | Accessibility        | Privacy       | Stage        |
|----------------|-------------------------|--------------------------|-----------------------------|----------------------|---------------|--------------|
| Phase 1        | Scoping                 | Scoping                  | AI System Scoping           | Discovery            | Capture       | `Understand` |
| Phase 2        | Bucket Analysis         | Supply Chain Assessment  | Risk Classification         | Framework Selection  | Data Mapping  | `Explore`    |
| Phase 3        | Standards Mapping       | Standards Mapping        | RAI Standards Mapping       | Standards Mapping    | Risk + DPIA   | `Explore`    |
| Phase 4        | Security Model Analysis | Gap Analysis             | RAI Security Model Analysis | Plan Risk Assessment | Controls      | `Decide`     |
| Phase 5        | Backlog Generation      | Backlog Generation       | RAI Impact Assessment       | Impact and Evidence  | Impact        | `Execute`    |
| Phase 6        | Review and Handoff      | Review and Handoff       | Review and Handoff          | Backlog Handoff      | Handoff       | `Challenge`  |

Planners run `Challenge` last because their `Execute` produces a plan rather than a shipped change. The final review guards the handoff boundary, so the challenge sits between the plan and the engineering work it authorizes.

No planner owns `Verify`. Loop closure belongs to whoever implements the handed-off backlog.

### Architecture decision records

| Existing phase | Stage                   |
|----------------|-------------------------|
| Frame          | `Understand`, `Explore` |
| Decide         | `Decide`                |
| Govern         | `Execute`               |

The ADR workflow owns no `Challenge` position and no `Verify` position.

### Requirements authoring

| Existing phase or gate  | Stage                   |
|-------------------------|-------------------------|
| Discover                | `Understand`, `Explore` |
| Define                  | `Decide`                |
| Quality reviewer gate   | `Challenge`             |
| Govern                  | `Execute`               |

`Govern` occupies `Execute` in both workflows, but it does different work in each: the ADR workflow publishes a decision record, and requirements authoring packages a handoff for a downstream team. Same stage, different activity, same word.

Requirements authoring owns no `Verify` position.

The seven-phase PRD lifecycle in the same skill is not mapped here. Its phase order interleaves procedure steps with decision work, and assigning stages to it needs a deliberate pass rather than an inference from the phase names. Until that mapping exists, do not infer a stage from a PRD phase name.

### Design Thinking

`space` is derived from method number and stays derived from method number. Stage is derived the same way.

| Methods | Space            | Stage        |
|---------|------------------|--------------|
| 1 to 2  | `problem`        | `Understand` |
| 3       | `problem`        | `Decide`     |
| 4       | `solution`       | `Explore`    |
| 5       | `solution`       | `Decide`     |
| 6       | `solution`       | `Challenge`  |
| 7       | `implementation` | `Execute`    |
| 8 to 9  | `implementation` | `Verify`     |

Design Thinking converges twice, so `Decide` appears twice. Method 3 commits to a problem statement and method 5 commits to a concept.

## Annotation Convention

Display the stage beside the existing phase name. Never in place of it.

The default form appends the stage in parentheses after the existing display title:

```markdown
### Phase 2: Bucket Analysis (Explore)
```

When a heading already carries a parenthetical, such as a framework attribution or an internal slug, a second parenthetical degrades readability. Use a same-file mapping table instead and leave every heading untouched.

### What is out of bounds

Anything a machine reads keeps its current value. Annotating any of the following is a defect:

* State schema field names, enum values, and integer phase numbers
* Internal phase slugs such as `framework-selection` or `frame`
* Skill section anchors such as `SKILL.md#govern`
* File names, directory names, and frontmatter keys
* Skill routing descriptions and command names
* Eval assertion targets that match against internal values

Anything a person reads may gain a stage name.

### Referencing this file

Consuming agents and instruction files reference this file rather than restating the stage definitions. Skills state the stage or stage span they serve as display text, because the skill packaging convention does not use cross-kind file references.

## Outside Resources

Not every HVE-Core asset sits on the decision spine. Those that do not are grouped as `Outside Resources` so the gap is named rather than unexplained.

The grouping currently covers these asset categories:

* Experimental assets, including presentation, diagramming, media, and board-integration tooling
* Framework-authoring assets used to build and validate HVE-Core artifacts themselves
* Installer and distribution assets
* Shared infrastructure assets such as licensing posture, content policy, and telemetry conventions

Triage is pending. No individual artifact is assigned to this grouping yet.

Backlog and pull request workflows that number their steps `Phase 1` through `Phase 6` are procedures rather than decision arcs. Session-lifecycle numbering, such as an agent's initialization, active-work, transition, and closure phases, is likewise a procedure. Those numbers carry no spine meaning, are not mapped here, and are never annotated.
