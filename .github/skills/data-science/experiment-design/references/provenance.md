---
title: experiment-design provenance and attribution
description: Source map, reproduction scope, HVE Core substitutions, and upstream silences for the experiment-design reference pack
---

## Purpose

This file records where each part of `experiment-design` comes from, what may be reproduced, and what is repository convention rather than upstream guidance.

## Licensing posture

Microsoft CSE Code With Engineering Playbook content is MIT licensed, which permits reproduction provided the copyright and permission notice is preserved; `THIRD-PARTY-NOTICES` carries that notice. The playbook-derived references in this pack stay close to upstream wording in most passages, and several reproduce it exactly. The scope column below states what each area actually reproduces. Checklist section headings and short item labels are structural identifiers.

[mve-coaching.md](mve-coaching.md) is outside this source set. It is repository-original content under CC BY 4.0 and is not derived from the playbook.

## Source map

| Content area                                                            | Upstream source                                                                                                                       | Reproduction scope                                                                                                                       |
|-------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| Model experimentation goals, five practice areas, and expected outcomes | [Model Experimentation](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/model-experimentation/)         | Area names, goal names, and tool and file identifiers as facts; goals and expected outcomes closely follow or reproduce upstream wording |
| ML Fundamentals Checklist structure                                     | [ML Fundamentals Checklist](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-fundamentals-checklist/) | Section headings and short item labels as structural identifiers; item text closely follows upstream wording                             |
| ML Model Production Checklist structure, scope, and caveat              | [ML Model Production Checklist](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-model-checklist/)    | Section headings as structural identifiers; item text closely follows upstream wording; purpose and caveat paraphrased                   |

MVE coaching content in this pack is HVE Core original material. It was consolidated here from a repository instruction file so that on-demand methodology has a single authoritative home. It is not derived from the CSE playbook.

## Paraphrases where precision is fragile

* Full reproducibility requires tracking dataset names **and versions**, parameters, code, and environment. Dropping "and versions" turns a reproducibility requirement into a labelling suggestion.
* The ML Model Production Checklist is scoped to teams that have already built or trained a model and are considering production. It explicitly allows that some scenarios cannot satisfy every item and directs teams to make informed, use-case-specific decisions. It is not a universal completion gate.
* Consistency across datasets and evaluation is what makes experiments comparable. A tracking framework alone does not deliver comparability.

## HVE Core substitutions and derivations

| Item                                                             | Upstream position                                                                                                             | Repository position                                                                                                                                                  |
|------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Virtual environment tooling                                      | Upstream names `venv`, `Conda`, and `Poetry`, and gives a selection rationale based on environment complexity and ease of use | HVE Core uses `uv`. This is a repository substitution. `uv` does not appear upstream; preserve upstream's selection rationale when advising a team that is choosing. |
| MVE methodology, vetting criteria, red flags, and backlog bridge | Not upstream                                                                                                                  | HVE Core original coaching material, consolidated into this pack                                                                                                     |

## Upstream silences

* Upstream does not select a universal experiment-tracking framework, evaluation metric, or folder structure. It requires that a team decide, document, and apply one consistently.
* Neither checklist names a data-tiering model, and neither states a pipeline-replayability requirement. The ML Fundamentals Checklist names reproducible, logged experiments, which is a different property.
* Cross-references between the checklists and the experimentation, testing, observability, and DataOps pages appear in shared site navigation rather than in checklist body content.
