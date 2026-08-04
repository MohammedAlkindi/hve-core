---
title: Backlog Collections Consolidated into Project Planning
description: The ado, github, jira, and gitlab collections are retired; backlog and work management now ships in project-planning with commands that resolve your tracker at runtime
sidebar_position: 3
author: Microsoft
ms.date: 2026-08-03
ms.topic: concept
keywords:
  - breaking change
  - migration
  - collections
  - backlog
  - azure devops
  - github
  - jira
  - gitlab
estimated_reading_time: 4
---

## What Changed

Four collections have been retired: `ado`, `github`, `jira`, and `gitlab`. Their capability now lives in `project-planning`.

This is a breaking change. The four Marketplace extensions stop being published, and an already-installed extension receives no automatic signal because the Marketplace offers no deprecation or tombstone mechanism. If you installed one of them, you need to install a replacement.

## Why

Backlog management was split three ways because the artifacts were split three ways: a separate discovery prompt per tracker, a separate triage prompt per tracker, and so on. The workflows were near-identical; only the field names and API calls differed.

Those differences belong in a reference file, not in a separate command. The workflows are now two commands that resolve your tracker at runtime and read the matching per-platform reference. One triage workflow serves Azure DevOps, GitHub, and Jira.

## Extension Migration

| If you installed                | Install instead                                                                 |
|---------------------------------|---------------------------------------------------------------------------------|
| `ise-hve-essentials.hve-ado`    | `ise-hve-essentials.hve-project-planning`                                       |
| `ise-hve-essentials.hve-github` | `ise-hve-essentials.hve-project-planning` and `ise-hve-essentials.hve-security` |
| `ise-hve-essentials.hve-jira`   | `ise-hve-essentials.hve-project-planning`                                       |
| `ise-hve-essentials.hve-gitlab` | `ise-hve-essentials.hve-project-planning`                                       |

The `hve-github` row needs both extensions because its skills split across two collections. The backlog workflows moved to project planning, and the `gh-code-scanning` skill moved to security.

If you installed `ise-hve-essentials.hve-core-all`, you already have everything and no action is required.

Uninstall the retired extension after installing the replacement. Leaving it installed surfaces commands that no longer resolve.

## Command Migration

Eighteen platform-specific prompts are retired. Sixteen are replaced by two commands that resolve your tracker from the workspace, so you no longer choose a platform variant. The remaining two are absorbed by an agent and a skill section, as noted below.

### Read-only planning: `backlog-plan`

| Retired command                                | Replacement               |
|------------------------------------------------|---------------------------|
| `/ado-discover-work-items`                     | `/backlog-plan discover`  |
| `/github-discover-issues`                      | `/backlog-plan discover`  |
| `/jira-discover-issues`                        | `/backlog-plan discover`  |
| `/ado-triage-work-items`                       | `/backlog-plan triage`    |
| `/github-triage-issues`                        | `/backlog-plan triage`    |
| `/jira-triage-issues`                          | `/backlog-plan triage`    |
| `/ado-sprint-plan`                             | `/backlog-plan sprint`    |
| `/github-sprint-plan`                          | `/backlog-plan sprint`    |
| `/ado-get-my-work-items`                       | `/backlog-plan my-work`   |
| `/ado-process-my-work-items-for-task-planning` | `/backlog-plan task-plan` |
| `/github-suggest`                              | `/backlog-plan resume`    |

### Tracker changes: `backlog-execute`

| Retired command           | Replacement            |
|---------------------------|------------------------|
| `/ado-add-work-item`      | `/backlog-execute add` |
| `/github-add-issue`       | `/backlog-execute add` |
| `/ado-update-wit-items`   | `/backlog-execute run` |
| `/github-execute-backlog` | `/backlog-execute run` |
| `/jira-execute-backlog`   | `/backlog-execute run` |

### Absorbed elsewhere

| Retired command    | Replacement                                      |
|--------------------|--------------------------------------------------|
| `/jira-prd-to-wit` | The `Functional Planner` agent                   |
| `/jira-setup`      | The Credential Setup section of the `jira` skill |

### Relocated, not retired

`/ado-create-pull-request` and `/ado-get-build-info` are unchanged and now ship in the `hve-core` collection.

Three skills moved without changing behavior:

| Skill              | Now ships in       |
|--------------------|--------------------|
| `jira`             | `project-planning` |
| `gitlab`           | `project-planning` |
| `gh-code-scanning` | `security`         |

## Three Behaviors Got Wider

Three workflows now do more than their predecessors did, because runtime tracker resolution made the old restriction unnecessary:

* `/github-suggest` resumed GitHub sessions only. `/backlog-plan resume` resumes on any supported tracker.
* `/ado-get-my-work-items` and the task-planning pair were Azure DevOps only. Both now work on any supported tracker.
* Single-item creation used a fixed list of five Azure DevOps work item types. It now discovers the types your tracker actually offers, because that list is wrong on GitHub and Jira.

## Retired Agents

Seven agents are retired. Five are replaced by the two consolidated agents; two had no direct command equivalent.

| Retired agent             | Where its capability went                                                                                                                                     |
|---------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ADO Backlog Manager`     | The `Backlog Manager` agent, using `/backlog-plan` for read-only work and `/backlog-execute` for tracker changes                                              |
| `GitHub Backlog Manager`  | The `Backlog Manager` agent, using `/backlog-plan` for read-only work and `/backlog-execute` for tracker changes                                              |
| `Jira Backlog Manager`    | The `Backlog Manager` agent, using `/backlog-plan` for read-only work and `/backlog-execute` for tracker changes                                              |
| `ADO PRD to WIT`          | The `Functional Planner` agent, which plans read-only and emits a handoff for `/backlog-execute run`                                                          |
| `Jira PRD to WIT`         | The `Functional Planner` agent, which plans read-only and emits a handoff for `/backlog-execute run`                                                          |
| `Agile Coach`             | The work-item quality reference inside the backlog skill, applied during requirements-to-backlog work                                                         |
| `Product Manager Advisor` | Evidence-quality questioning and prioritization lenses in the `requirements-author` skill; hypothesis validation was already covered by `Experiment Designer` |

## What Did Not Change

* Autonomy tiers and content sanitization behave as before, and dry-run preview is available on the consolidated execution command.
* Planning file locations and formats are unchanged.
* MCP server configuration is unchanged. Configure the server matching the tracker you use.

*🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.*
