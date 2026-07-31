---
title: Threat Models
description: Machine-readable threat-model specs for HVE Core and the generators that consume them
sidebar_position: 1
author: Microsoft
ms.date: 2026-07-31
ms.topic: reference
keywords:
  - threat model
  - security planning
  - tm7
---

## Overview

Machine-readable threat-model specs consumed by the `security-planning` skill generators. Each spec is the versioned source; the `.tm7` and markdown outputs are build artifacts and are not committed.

## Specs

| Spec                                                       | Scope                                                                                                                             |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------|
| [hve-core-comprehensive.yaml](hve-core-comprehensive.yaml) | Repository contents, CI/CD pipeline, developer workstation, dependency supply chain, dev container, and executable skill runtimes |

## Relationship to the prose model

[docs/security/security-model.md](../../security/security-model.md) is the narrative STRIDE model and remains the source of truth for threat content. Per-skill `SECURITY.md` files cover individual skill runtimes. A spec in this directory encodes that same analysis in the schema the generators accept.

## Regenerating outputs

Generate a `.tm7` from a spec:

```bash
uv run --project .github/skills/project-planning/security-planning \
  python .github/skills/project-planning/security-planning/scripts/generate_tm7.py \
  docs/planning/threat-models/hve-core-comprehensive.yaml \
  -o <output>.tm7
```

Outputs are deterministic for a given spec and generator version, so they are regenerated on demand rather than stored. Validating a generated model against the native Threat Modeling Tool requires Windows and a pinned TMT version; see the skill's [README](../../../.github/skills/project-planning/security-planning/README.md).

## Review status

A spec carrying a `DRAFT` marker has not been through human security review. Treat both the spec and anything generated from it as unreviewed until that marker is removed by a qualified human reviewer.

🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.
