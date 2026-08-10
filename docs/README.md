---
title: HVE Core Documentation
description: Documentation hub for HVE Core, the codification of engineering rigor in an agentic world
sidebar_position: 1
author: Microsoft
ms.date: 2026-08-09
ms.topic: overview
keywords:
  - hve core
  - documentation
  - decision spine
  - engineering rigor
  - copilot customizations
estimated_reading_time: 3
---

HVE Core is the codification of engineering rigor in an agentic world. Every workflow here moves through the same six stages: understand the problem, explore the options, decide, challenge the decision before acting, execute, and verify the result. Working with AI makes those stages easy to skip, and HVE Core exists to keep them intact.

## Start Here

1. [How HVE Core works](getting-started/how-it-works) explains the six stages and how the pieces fit. Read this first.
2. [Install HVE Core](getting-started/install) covers the setup paths from marketplace extension to developer clone.
3. [Run your first workflow](getting-started/first-workflow) walks an end-to-end example through the whole loop.

## Choose Your Installation

| Option       | HVE Core Extension                                                                                      | Selective Clone                                                            |
|--------------|---------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------|
| What you get | Every active agent, prompt, instruction, and skill                                                      | Starter or custom agents, prompts, instructions, and complete skills       |
| Best for     | Teams that want managed updates and the complete content set                                            | Teams that want repository-owned, reviewable component selection           |
| Start        | [Install HVE Core](https://marketplace.visualstudio.com/items?itemName=ise-hve-essentials.hve-core-all) | Use the included `hve-core-installer` skill with a pinned or cloned source |

> Narrower packages exist for single domains such as security, Jira, or coding standards. See [packages](getting-started/packages) for the full list, or the [installation methods comparison](getting-started/methods/comparison) for a detailed breakdown.

## Other Ways In

The paths below are useful once you know what HVE Core is. If you are new, start with the three steps above.

### Leading a Team?

Set up HVE Core for your team with governance, selective adoption, and customization options.

* [Team adoption guide](customization/team-adoption.md) covers governance, naming conventions, and onboarding
* [HVE Core identity and channels](getting-started/packages.md) explains how artifacts are bundled and distributed
* [Customization guide](customization/README.md) covers the full spectrum from lightweight instructions to fork-and-extend

### Contributing to HVE Core?

Create and maintain agents, prompts, instructions, and skills for the framework.

* [Contributing guide](contributing/) explains artifact authoring standards
* [Templates](templates/) provide starting points for ADRs, BRDs, and security plans
* [Architecture overview](architecture/) documents system design, components, and build pipelines

### Going Deeper?

Explore advanced capabilities including Design Thinking coaching, security planning, and methodology reference.

* [Design Thinking](design-thinking/README.md) guides teams through nine methods across three spaces
* [Project Planning](agents/project-planning/) covers ADR creation, BRD/PRD building, architecture diagrams, and security plan generation
* [Security documentation](security/README.md) covers threat modeling and security planning
* [RPI methodology](rpi/) explains the Research, Plan, Implement, Review, and Follow-up workflow

## Roles

HVE Core provides dedicated tooling for 10 engineering roles, each with curated agents, prompts, and starter workflows. Find your role guide on the [Role Guides](hve-guide/roles/) page.

## AI-Assisted Project Lifecycle

HVE Core supports a 9-stage lifecycle from initial setup through ongoing operations. Each stage maps to specific agents, prompts, and role-specific guidance.

* [Stage overview](hve-guide/lifecycle/) provides a full lifecycle map
* [Implementation (Stage 6)](hve-guide/lifecycle/implementation.md) is the highest-density stage with 30+ assets
* [Discovery (Stage 2)](hve-guide/lifecycle/discovery.md) covers research, requirements, and BRD creation

**[Explore the full lifecycle →](hve-guide/lifecycle/)**

## Agent Systems

Specialized agents are organized into functional groups that combine agents, prompts, and instruction files into cohesive workflows.

* [RPI Orchestration](rpi/) separates complex tasks into research, planning, implementation, and review phases
* [Project Planning](agents/project-planning/) creates ADRs, BRDs, PRDs, architecture diagrams, and security plans through guided AI workflows
* [GitHub Backlog Manager](agents/github-backlog/) automates issue discovery, triage, sprint planning, and execution
* Additional systems are documented in the [Agent Catalog](agents/)

**[Browse the Agent Catalog →](agents/)**

## RPI Methodology

Research, Plan, Implement, Review (RPI) decomposes complex engineering tasks into phase skills coordinated by RPI Agent or invoked directly.

* [Why RPI?](rpi/why-rpi.md) explains the problem statement and design rationale
* [RPI overview](rpi/) introduces RPI Agent, `/rpi`, and the direct `rpi-*` phase skills
* [Using Together](rpi/using-together.md) describes phase coordination and durable handoffs

**[RPI Documentation →](rpi/)**

## Design Thinking

The dt-coach agent guides teams through nine Design Thinking methods across problem space, solution space, and validation.

* [Design Thinking Guide](design-thinking/README.md) provides the overview and method catalog
* [Why Design Thinking?](design-thinking/why-design-thinking.md) explains when to reach for DT
* [Using the DT Coach](design-thinking/dt-coach.md) covers agent usage

**[Browse all Design Thinking docs →](design-thinking/)**

## Prompt Engineering

HVE Core structures AI artifacts with protocol patterns, input variables, and evidence-backed quality gates.

* The `hve-builder` skill creates, improves, refactors, replaces, reviews, and validates AI artifacts through one lifecycle
* [AI Artifacts Overview](contributing/ai-artifacts-common.md) covers common patterns across artifact types
* [Activation Context](architecture/ai-artifacts.md#activation-context) explains when artifacts activate within workflows

## Quick Links

| Resource                                                                                | Description                        |
|-----------------------------------------------------------------------------------------|------------------------------------|
| [Customization Guide](customization/)                                                   | Adapt HVE Core to your workflow    |
| [CHANGELOG](https://github.com/microsoft/hve-core/blob/main/CHANGELOG.md)               | Release history and version notes  |
| [CONTRIBUTING](https://github.com/microsoft/hve-core/blob/main/CONTRIBUTING.md)         | Repository contribution guidelines |
| [Scripts README](https://github.com/microsoft/hve-core/blob/main/scripts/README.md)     | Automation script reference        |
| [Extension README](https://github.com/microsoft/hve-core/blob/main/extension/README.md) | VS Code extension documentation    |

<!-- markdownlint-disable MD036 -->
*🤖 Crafted with precision by ✨Copilot following brilliant human instruction,
then carefully refined by our team of discerning human reviewers.*
<!-- markdownlint-enable MD036 -->
