---
title: Marketplace Packages
description: Compare HVE Core marketplace packages and choose the right extension or plugin for your workflow
sidebar_position: 3
author: Microsoft
ms.date: 2026-08-01
ms.topic: overview
---

## How HVE Artifacts Are Organized

HVE Core distributes agents, prompts, instructions, skills, and hooks through
marketplace packages. `.github/plugin/marketplace.json` is the package catalog:
its standard component fields declare membership, while `x-hve` records display,
maturity, documentation, and aggregate metadata.

Each package can produce two self-contained outputs from the same resolved
source set:

* A Copilot plugin published under an immutable `plugins-v<version>` tag
* A VS Code extension packaged as a `.vsix`

## Choosing a Package

Use `hve-core` for the flagship RPI workflow. Use `hve-core-all` when you want
the aggregate package. Domain packages provide narrower capabilities, and the
installer package supports selective workspace deployment.

| Package            | Display name                         | Maturity     | Purpose                                                        |
|--------------------|--------------------------------------|--------------|----------------------------------------------------------------|
| `ado`              | HVE Core - Azure DevOps Integration  | Stable       | Azure DevOps work items, builds, and pull requests             |
| `coding-standards` | HVE Core - Coding Standards          | Stable       | Language standards and pre-PR review                           |
| `data-science`     | HVE Core - Data Science              | Stable       | Data specifications, notebooks, dashboards, and evaluations    |
| `design-thinking`  | HVE Core - Design Thinking           | Preview      | Design Thinking coaching across nine methods                   |
| `experimental`     | HVE Core - Experimental              | Experimental | Early package content under active iteration                   |
| `github`           | HVE Core - GitHub Backlog Management | Stable       | GitHub issue discovery, triage, planning, and execution        |
| `gitlab`           | HVE Core - GitLab Integration        | Stable       | GitLab merge request and pipeline workflows                    |
| `hve-core`         | HVE Core                             | Stable       | RPI, HVE Builder, and Git workflows                            |
| `hve-core-all`     | HVE Core - All                       | Stable       | Aggregate package across all eligible domains                  |
| `installer`        | HVE Core - HVE Core Installer        | Stable       | Selective deployment across workspace configurations           |
| `jira`             | HVE Core - Jira Integration          | Stable       | Jira backlog, PRD planning, and issue operations               |
| `project-planning` | HVE Core - Project Planning          | Stable       | PRDs, BRDs, ADRs, and architecture diagrams                    |
| `rpi`              | HVE Core - RPI Skills                | Stable       | Skill-forward Research, Plan, Implement, Review, and Follow-up |
| `security`         | HVE Core - Security                  | Stable       | Security review, planning, response, and vulnerability work    |

## Package Relationships

Packages are self-contained. HVE Core does not use plugin dependencies,
`extensionPack`, or `extensionDependencies` to compose advertised content.
Shared marketplace projection resolves transitive agent handoffs before either
plugin or VSIX destination mapping.

`hve-core-all` is the validated aggregate package and must cover every eligible
PreRelease component. Individual domain packages remain independently
installable.

## Channels

Stable includes stable components only. PreRelease includes stable, preview,
and experimental components. Deprecated and removed components are excluded
from both channels; removed tombstones can remain in metadata for policy checks.

## After Installation

Once a package is installed:

1. Agents appear in the Copilot Chat agent picker.
2. Prompts are available as slash commands.
3. Instructions apply to matching files through their `applyTo` patterns.
4. Skills become available for semantic or explicit invocation.

The `hve-core` package includes `RPI Agent` and the `/rpi`, `/rpi-research`,
`/rpi-plan`, `/rpi-implement`, and `/rpi-review` entry points.

---

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
