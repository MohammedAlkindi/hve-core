---
name: experiment-design
description: "Experiment design reference for Minimum Viable Experiment coaching, hypothesis formation, vetting and red flags, model-experimentation conventions, and ML checklist structure. Use when framing, vetting, or setting up an experiment and its evaluation."
license: MIT AND CC-BY-4.0
user-invocable: false
metadata:
  authors: "Microsoft (Code With Engineering Playbook); Microsoft (MVE coaching synthesis)"
  spec_version: "1.0"
  last_updated: "2026-08-01"
  content_based_on: "https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/model-experimentation/; https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-fundamentals-checklist/; https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-model-checklist/"
---

# Experiment Design Reference Pack

## Goal

Support experiment work end to end: turning unknowns into testable hypotheses, screening out work that is not a real experiment, and setting up reproducible experimentation and evaluation.

This pack is general purpose. It applies to data feasibility, architecture, LLM, performance, use-case, UX, prototyping, and hardware experiments, not to data science alone.

## Inputs

* The problem statement, customer context, and business driver
* Known unknowns, assumptions, and risks
* The decision the experiment is meant to unblock
* Existing environment, repository, tracking, and evaluation setup when experimentation is being stood up

## Reference index

Read only the reference that matches the active concern.

| Reference                                                       | Read this when                                                                                                                                                                             |
|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [mve-coaching.md](references/mve-coaching.md)                   | Framing an MVE, forming or sharpening hypotheses, applying vetting criteria and red flags, designing the experiment, evaluating results, or producing session and backlog-bridge artifacts |
| [model-experimentation.md](references/model-experimentation.md) | Standing up environments, repository and notebook structure, experiment tracking and reproducibility, dataset and model abstractions, or evaluation flow                                   |
| [ml-checklists.md](references/ml-checklists.md)                 | Checking ML engagement fundamentals or assessing whether a trained model is ready to move toward production                                                                                |
| [provenance.md](references/provenance.md)                       | Confirming what is upstream guidance, what is HVE Core derivation or repository convention, and where upstream is silent                                                                   |

## Success criteria

* Each hypothesis is testable, specific, falsifiable, and tied to a stated rationale.
* Work that is a demo, a mini-MVP, or an already-answered question is named as such rather than run as an experiment.
* Reproducibility keeps all four elements: dataset names and versions, parameters, code, and environment.
* Checklist section headings and short item labels are preserved, and applicability caveats travel with them.
* Experiment scope stays minimum-but-sufficient, and experiment code is treated as disposable.

## Constraints

* Prefer paraphrase, and reproduce upstream wording where paraphrase would distort a requirement or where a short factual statement has little expressive range. Attribute every reference and describe accurately what each reference reproduces.
* Preserve checklist section headings and short item labels as structural identifiers. Item text stays close to upstream wording; describe that accurately rather than calling it paraphrase.
* Label repository conventions as substitutions rather than upstream recommendations.
* Do not convert a checklist into an unconditional gate. Upstream scopes the production checklist and permits use-case-specific decisions.

## Ownership boundaries

| Concern                                                                         | Owner                                                                              |
|---------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| MVE session directory, artifact filenames, placement, and tracking-file hygiene | `experiment-designer.instructions.md`, applied automatically to MVE tracking paths |
| Phase order, gates, session writes, and coaching flow                           | The consuming experiment agent                                                     |
| Pipeline mechanics, data tiering, and DS/MLOps test technique                   | `ds-dataops`                                                                       |
| Telemetry naming and data sensitivity classification                            | `telemetry-foundations` and `privacy-standards`                                    |

## Stop rules

* Stop and name the red flag when the request is a demo, a scaled-down product build, or a question already answered elsewhere. Then offer either the falsifiable hypothesis hiding underneath it or an explicit non-experiment path, rather than halting on the refusal.
* Stop and separate concerns when the request is production implementation rather than experiment design.
* Stop and state the gap when upstream does not cover the request, such as a universal framework, tool, or metric choice made without project context.

## Attribution

This pack declares `MIT AND CC-BY-4.0` because it mixes two kinds of content.

[model-experimentation.md](references/model-experimentation.md) and [ml-checklists.md](references/ml-checklists.md) derive from Microsoft CSE Code With Engineering Playbook pages, which are MIT licensed, and stay close to upstream wording in many passages. MIT permits this with the notice recorded in `THIRD-PARTY-NOTICES`. Each cites its own upstream URL and states what it reproduces.

[mve-coaching.md](references/mve-coaching.md) is repository-original content under CC BY 4.0. It is not derived from the playbook and cites no upstream URL.

See [provenance.md](references/provenance.md) for the consolidated source map and derivation labels.
