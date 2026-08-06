---
title: Threat Models
description: Machine-readable threat-model specs for HVE Core and the generators that consume them
sidebar_position: 1
author: Microsoft
ms.date: 2026-08-05
ms.topic: reference
keywords:
  - threat model
  - security planning
  - tm7
---

## Overview

> [!WARNING]
> `hve-core-comprehensive.yaml` carries a `DRAFT` marker and has **not** been through human security review. Treat that spec, and every `.tm7` or markdown artifact generated from it, as unreviewed until a qualified human reviewer removes the marker from the spec itself. Do not cite it as an authored threat model.

Machine-readable threat-model specs consumed by the `security-planning` skill generators. Each spec is the versioned source; the `.tm7` and markdown outputs are build artifacts and are not committed.

## Specs

| Spec                                                       | Scope                                                                                                                             | Review status |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|---------------|
| [hve-core-comprehensive.yaml](hve-core-comprehensive.yaml) | Repository contents, CI/CD pipeline, developer workstation, dependency supply chain, dev container, and executable skill runtimes | DRAFT, not human-reviewed |

## Relationship to the prose model

[Security model](../../security/security-model) is the narrative STRIDE model and remains the source of truth for threat content. Per-skill `SECURITY.md` files cover individual skill runtimes. A spec in this directory encodes that same analysis in the schema the generators accept.

## Regenerating outputs

Generate a `.tm7` from a spec:

```bash
uv run --project .github/skills/project-planning/security-planning \
  python .github/skills/project-planning/security-planning/scripts/generate_tm7.py \
  docs/planning/threat-models/hve-core-comprehensive.yaml \
  -o <output>.tm7
```

Generate the synchronized markdown twin from the same spec:

```bash
uv run --project .github/skills/project-planning/security-planning \
  python .github/skills/project-planning/security-planning/scripts/generate_markdown.py \
  docs/planning/threat-models/hve-core-comprehensive.yaml \
  -o <output>.md
```

Both commands read the same spec and use the same deterministic threat derivation, so regenerate them together to keep the pair consistent. Generating a large spec takes a while because layout packing runs per surface.

Outputs are deterministic for a given spec and generator version, so they are regenerated on demand rather than stored. Validating a generated model against the native Threat Modeling Tool requires Windows and a pinned TMT version; see the skill's [README](https://github.com/microsoft/hve-core/blob/main/.github/skills/project-planning/security-planning/README.md) and the [operator runbook](https://github.com/microsoft/hve-core/blob/main/.github/skills/project-planning/security-planning/references/tm7-generation.md).

## Review status

A spec carrying a `DRAFT` marker at the top of its file has not been through human security review. `hve-core-comprehensive.yaml` currently carries that marker. Treat both the spec and anything generated from it as unreviewed until the marker is removed by a qualified human reviewer.

🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.
