---
title: HVE Core Skills
description: Deduplicated union of every published HVE Core skill in one portable Agent Plugins package
sidebar_position: 15
ms.date: 2026-07-30
ms.topic: reference
---

Install every published HVE Core skill from one portable package. Membership is derived from the skills declared by the feature-rich Copilot packages after channel and maturity filtering, deduplicated by skill name, so a skill appears exactly once regardless of how many packages publish it.

This package carries skills only. Agents, prompts, instructions, and hooks remain in the packages that own them.

## Included Artifacts

<!-- BEGIN AUTO-GENERATED ARTIFACTS -->

### Skills

| Name | Description |
|------|-------------|
| **accessibility** | Consolidated accessibility skill entrypoint for WCAG 2.2, ARIA Authoring Practices, cognitive accessibility, Section 508, EN 301 549, and the Accessibility Planner workflow. |
| **adr-author** | Authoring skill for Architecture Decision Records (ADRs) supporting capture, from-planner-handoff, and adopt-template entry modes with selectable Y-Statement or MADR v4.0.0 output templates, supersession lineage, and ASR trigger evaluation. |
| **architecture-diagrams** | Architecture diagram authoring for cloud infrastructure: parse Azure IaC, map relationships, and render either ASCII block diagrams or Mermaid flowcharts based on the caller's chosen output format |
| **backlog-templates** | Shared work-item templates and conventions for ADO and GitHub backlog handoff across the RAI, Security, SSSC, Accessibility, and Privacy planners |
| **caveman** | Ultra-compressed response style that reduces output token count while preserving technical accuracy, with intensity levels and auto-clarity safety rules |
| **code-review** | Review code changes from multiple perspectives with context bootstrap, depth-tier rigor, and structured findings output. |
| **copilot-otel-metrics** | Set up GitHub Copilot OpenTelemetry capture: configure the VS Code export settings, generate a local Grafana stack and dashboard, or generate the Azure collector, infrastructure, and dashboard for an organization. |
| **customer-card-render** | Generate customer-card PowerPoint content YAML from Design Thinking canonical artifacts and build using the shared PowerPoint skill pipeline |
| **documentation** | Canonical documentation capability for audit, drift, validate, and author modes in hve-core. |
| **dt-coaching-foundation** | Design Thinking coaching foundation knowledge: coach identity and philosophy, quality and fidelity constraints, method sequencing, coaching state schema, and the canonical deck workflow |
| **dt-curriculum** | Design Thinking learning curriculum covering nine progressive modules across the full Problem, Solution, and Implementation Space methods plus a shared manufacturing reference scenario for teaching and practice |
| **dt-methods** | Design Thinking method coaching knowledge across all nine methods including per-method techniques, deep expertise, and industry context (energy, financial services, healthcare, manufacturing, nonprofit and social impact, pharmaceuticals and life sciences, professional services, public sector, retail and CPG) |
| **dt-rpi-integration** | Design Thinking handoff knowledge for research-ready rpi-research inputs and DT-aware rpi-plan, rpi-implement, and rpi-review context |
| **gh-code-scanning** | Retrieves and groups GitHub code scanning alerts by rule and severity using the gh CLI |
| **gitlab** | Manage GitLab merge requests and pipelines with a Python CLI |
| **hve-builder** | Author, review, or validate Copilot prompt-engineering artifacts through independent review, behavior testing, and host checks. |
| **hve-builder-tester** | Test HVE artifact behavior with black-box scenarios, contained simulation or approved native execution, independent grading, and evidence reports. |
| **hve-core-installer** | Decision-driven HVE-Core installer with multiple clone-based and extension install methods, environment detection, and agent customization |
| **jira** | Jira issue workflows for search, issue updates, transitions, comments, and field discovery via the Jira REST API. Use when you need to search with JQL, inspect an issue, create or update work items, move an issue between statuses, post comments, or discover required fields for issue creation. |
| **mural** | Mural workspace, room, mural, and widget workflows via the Mural REST API exposed through a Python CLI. Use when you need to read or write Mural content or automate widget creation. |
| **owasp-agentic** | OWASP Agentic Security Top 10 knowledge base for identifying, assessing, and remediating AI agent system security risks. |
| **owasp-cicd** | OWASP CI/CD Top 10 knowledge base for identifying, assessing, and remediating CI/CD pipeline security risks. |
| **owasp-infrastructure** | OWASP Infrastructure Top 10 knowledge base for identifying, assessing, and remediating internal IT infrastructure security risks. |
| **owasp-llm** | OWASP Top 10 for LLM Applications (2025) knowledge base for identifying, assessing, and remediating large language model security risks. |
| **owasp-mcp** | OWASP MCP Top 10 knowledge base for identifying, assessing, and remediating Model Context Protocol security risks. |
| **owasp-top-10** | OWASP Top 10 for Web Applications (2025) knowledge base for identifying, assessing, and remediating web application security risks. |
| **performance-slo-planner** | Performance, load, and reliability (SLO/SRE) planning for production readiness. Use when defining service level objectives, load characterization, capacity, latency budgets, stress/soak/spike test plans, false-positive baselines, and reliability targets. USE FOR: SLO/SLA definition, load testing plan, performance budget, capacity planning, reliability/SRE backlog, latency targets, error-budget policy. DO NOT USE FOR: executing load tests (use Azure Load Testing tooling), security threat modeling, RAI assessment, privacy/compliance planning, or authoring/restating PRD requirements (cite the PRD's existing NFR/FR ids instead). |
| **powerpoint** | PowerPoint slide deck generation and management using python-pptx with YAML-driven content and styling |
| **pr-reference** | Generates PR reference XML with commit history and unified diffs between branches, with extension and path filtering. Use when creating pull request descriptions, preparing code reviews, analyzing branch changes, discovering work items from diffs, or generating structured diff summaries. |
| **privacy-standards** | Privacy planning reference for data-flow reasoning, standards mapping, and DPIA thresholds |
| **prompt-analyze** | Compatibility alias for read-only prompt artifact review. Routes static and behavior analysis to hve-builder review mode. |
| **prompt-builder** | Compatibility alias for legacy prompt-building requests. Routes creation and improvement to the hve-builder skill. |
| **prompt-refactor** | Compatibility alias for behavior-preserving prompt artifact cleanup. Routes refactoring to hve-builder refactor mode. |
| **python-foundational** | Foundational Python best practices, idioms, and code quality fundamentals |
| **rai-planner** | On-demand RAI planner reference pack covering Phase 1 capture, Phase 2 risk classification, Phase 5 impact assessment, and Phase 6 review and backlog handoff. |
| **rai-standards** | Consolidated Responsible AI standards reference: NIST AI RMF 1.0, AI STRIDE threat-modeling overlay, EU AI Act risk tiers, and an open-standards catalog with phase mapping |
| **requirements-author** | Requirements authoring guide for BRD and PRD across Discover, Define, and Govern with canonical templates and handoff contracts |
| **rpi-challenger** | Challenge a confirmed task, decision, plan, or artifact through adaptive skeptical questions. Use when you need to expose assumptions before acting. |
| **rpi-implement** | Execute an approved RPI plan, maintain current planning state, and record implementation evidence. Use when implementation is ready to begin or resume. |
| **rpi-plan** | Create evidence-based RPI plans and phase details from supplied context, research, drafts, and decisions. Use when implementation planning is needed. |
| **rpi-plan-critique** | Independently critique an RPI plan and phase details against supplied evidence without editing plan sources. Use when planning credibility needs a read-only assessment. |
| **rpi-quick** | Sequence Research, Plan, Implement, Review, and Follow-up for an RPI task. Use when one workflow should coordinate the full delivery lifecycle. |
| **rpi-research** | Research-only RPI playbook that gathers task evidence, writes dated research artifacts under .copilot-tracking/research/, and hands off planning-ready findings. Use when the user needs evidence, alternatives, or task framing first. |
| **rpi-review** | Compare RPI planning and implementation evidence, record review findings, and route follow-up work. Use when an implementation needs acceptance review. |
| **rpi-walkthrough** | Guided, conversational walkthrough that explains code, UI, UX, features, or .copilot-tracking artifacts with navigable evidence links, deep subagent review, and a reconciled decisions-and-changes ledger. Use when the user wants to understand how something works or why it was changed. |
| **secure-by-design** | Secure by Design principles knowledge base for assessing security-first design, development, and deployment across the software lifecycle. |
| **security-planning** | Security planning reference set for operational buckets, STRIDE analysis, standards mapping, NIST control families, and backlog scaffolding. |
| **security-reviewer-formats** | Format specifications and data contracts for the security reviewer orchestrator and its subagents. |
| **supply-chain-security** | Software supply chain security reference for OpenSSF Scorecard, SLSA, Sigstore, SBOM, and posture/backlog taxonomies. |
| **telemetry-foundations** | Declarative OpenTelemetry-aligned telemetry vocabulary and instrumentation conventions for traces, metrics, logs, and PII handling |
| **tts-voiceover** | Text-to-speech voice-over generation from YAML speaker notes using Azure Speech SDK with SSML pronunciation control |
| **vally-tests** | Authors Vally conformance tests for prompts, instructions, agents, and skills, including refusals for jailbreak, prompt-injection, harmful-elicitation, TOS, CoC, and PII-extraction stimuli |
| **vex** | OpenVEX v0.2.0 specification reference plus VEX management playbooks - Brought to you by microsoft/hve-core. |
| **video-to-gif** | Video-to-GIF conversion with FFmpeg two-pass optimization |
| **vscode-playwright** | VS Code screenshot capture using Playwright MCP with serve-web for slide decks and documentation |

<!-- END AUTO-GENERATED ARTIFACTS -->
