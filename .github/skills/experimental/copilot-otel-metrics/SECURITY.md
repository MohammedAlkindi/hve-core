---
title: Copilot OTel Metrics Skill Security Model
description: STRIDE threat model for the copilot-otel-metrics skill organized by assets, adversaries, and trust buckets (editor OTLP ingest, telemetry at rest, reference helper scripts, container image supply chain) with in-design mitigations and acknowledged enterprise readiness gaps
author: microsoft/hve-core
ms.date: 2026-07-27
ms.topic: reference
estimated_reading_time: 12
keywords:
  - security
  - STRIDE
  - copilot-otel-metrics
  - opentelemetry
  - threat model
---
<!-- markdownlint-disable-file -->
# Copilot OTel Metrics Skill Security Model

This document records the STRIDE threat model for the copilot-otel-metrics skill. The shipped runtime is `examples/compose.yaml` (the single-container stack definition), `examples/dashboards/copilot-otel.json` (the Grafana dashboard), and four reference helper scripts: `examples/verify.py`, `examples/baseline.py`, `examples/inspect_metrics.py`, and `examples/validate_dashboard.py`. The model is organized by trust bucket: editor OTLP ingest (B1), telemetry at rest and its query surfaces (B2), reference helper scripts to local service APIs (B3), and container image supply chain (B4). Each bucket enumerates all six STRIDE categories. Assets and adversaries are enumerated first. Acknowledged enterprise readiness gaps are listed at the end.

The skill ships no agent-executed code. Every file under `examples/` is reference material an operator runs deliberately. The threat model nonetheless covers that runtime, because the skill instructs a reader to stand up a telemetry endpoint that receives prompt-bearing spans.

> **See also: repo-wide STRIDE model.** This skill participates in the repository-wide threat model at [`docs/security/security-model.md`](../../../../docs/security/security-model.md) and is registered in its [Skill Security Models](../../../../docs/security/security-model.md#skill-security-models) section.

## Executive Summary

The copilot-otel-metrics skill directs an operator to run a local observability stack and point GitHub Copilot Chat's OTLP exporter at it. Its highest-risk property is **not the code, it is the payload**. Spans emitted by the extension were directly observed carrying full prompt text, tool call arguments and results, and system instructions, on a configuration where content capture was left at its default. Anyone who follows this skill therefore accumulates a durable local corpus of prompt content in a Docker volume.

The design bounds that exposure by construction rather than by policy: every published port binds to `127.0.0.1`, the stack image tag is pinned, the skill omits `captureContent` from its settings block, and the documentation states plainly that the observed behavior contradicts the documented default so a reader verifies rather than assumes. Residual risk concentrates in three places the skill cannot close: the extension's own span content behavior, the absence of authentication on loopback service APIs, and the lack of encryption or expiry on the persistent volume.

The four helper scripts are low-risk by comparison. They are read-mostly, use only the Python standard library, target hard-coded loopback URLs, and send no telemetry. The single exception is `validate_dashboard.py`, which authenticates with Grafana's default credentials and imports with `overwrite: true`.

### Security Posture Overview

| Dimension          | Value                                                                                                                                  |
|--------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| Runtime surface    | Compose stack definition, Grafana dashboard JSON, four standard-library Python reference helpers                                       |
| Trust buckets      | B1 editor OTLP ingest, B2 telemetry at rest, B3 helper scripts to local APIs, B4 container image supply chain                          |
| Credentials        | Grafana default `admin`/`admin`, hard-coded in `validate_dashboard.py`; no tokens, keys, or secrets handled                            |
| Network egress     | None after the image pull. First run pulls `grafana/otel-lgtm:0.29.2` from a public registry; thereafter inbound OTLP on loopback only |
| Agent execution    | None. All example files are operator-run reference material                                                                            |
| Open residual gaps | 9 (highest: InfoDisc-High, prompt content present in spans despite the documented default)                                             |

## Contents

* [System Description](#system-description)
* [Trust Boundaries](#trust-boundaries)
* [Assets](#assets)
* [Adversaries](#adversaries)
* [Bucket B1: Editor OTLP ingest](#bucket-b1-editor-otlp-ingest)
* [Bucket B2: Telemetry at rest and query surfaces](#bucket-b2-telemetry-at-rest-and-query-surfaces)
* [Bucket B3: Reference helper scripts to local service APIs](#bucket-b3-reference-helper-scripts-to-local-service-apis)
* [Bucket B4: Container image supply chain](#bucket-b4-container-image-supply-chain)
* [Enterprise Readiness Gaps](#enterprise-readiness-gaps)
* [References](#references)

## System Description

### Components

1. `examples/compose.yaml` — declares one `grafana/otel-lgtm` container publishing five loopback-bound ports, mounting an external named volume at `/data`, and passing delta-to-cumulative conversion plus 120-day retention to Prometheus.
2. `examples/dashboards/copilot-otel.json` — Grafana dashboard referencing the pre-provisioned `prometheus` and `tempo` datasource uids. Contains PromQL and TraceQL queries only.
3. `examples/verify.py` — read-only. Queries Grafana, Prometheus, and Tempo health plus stored signal presence. Exits non-zero when the stack is unhealthy.
4. `examples/baseline.py` — read-mostly. Snapshots Prometheus label values and Tempo trace names, writes one JSON file under the user cache directory, and diffs a later store state against it.
5. `examples/inspect_metrics.py` — read-only. Enumerates `copilot_chat` and `gen_ai` series with labels and current values.
6. `examples/validate_dashboard.py` — the only writing helper. Imports the dashboard through the Grafana API with `overwrite: true`, then replays each panel query against Prometheus or Tempo.

### Data Flow

```mermaid
flowchart TD
    subgraph EDITOR["VS Code process (operator trust zone)"]
        EXT["Copilot Chat extension<br/>OTel exporter"]
        SETTINGS["User settings.json<br/>(application-scoped)"]
    end
    subgraph HOST["Operator workstation, loopback only (trust zone)"]
        HELPERS["verify.py / baseline.py<br/>inspect_metrics.py / validate_dashboard.py"]
        SNAP["~/.cache/copilot-otel/<br/>pre-enable-baseline.json"]
    end
    subgraph STACK["otel-lgtm container (trust zone)"]
        OTLP["OTLP receiver<br/>:4318 HTTP / :4317 gRPC"]
        PROM["Prometheus :9090"]
        TEMPO["Tempo :3200"]
        GRAF["Grafana :3000<br/>(default credentials)"]
        VOL[("copilot-otel-data<br/>volume /data")]
    end
    subgraph REGISTRY["Public container registry (external)"]
        IMG["grafana/otel-lgtm:0.29.2"]
    end
    SETTINGS -->|"configures endpoint"| EXT
    EXT -->|"OTLP/HTTP plaintext, spans carrying prompt content"| OTLP
    OTLP -->|"metrics"| PROM
    OTLP -->|"traces"| TEMPO
    PROM -->|"persists"| VOL
    TEMPO -->|"persists"| VOL
    GRAF -->|"PromQL / TraceQL"| PROM
    GRAF -->|"TraceQL"| TEMPO
    HELPERS -->|"HTTP GET, unauthenticated"| PROM
    HELPERS -->|"HTTP GET, unauthenticated"| TEMPO
    HELPERS -->|"HTTP POST dashboard import, basic auth admin:admin"| GRAF
    HELPERS -->|"writes snapshot"| SNAP
    IMG -.->|"docker pull, tag-pinned"| STACK
```

## Trust Boundaries

### Boundary Diagram

```text
┌──────────────────────────────────────────────────────────────┐
│ TRUST BOUNDARY: Operator workstation                          │
│                                                               │
│  ┌──────────────────┐        ┌────────────────────────────┐  │
│  │ VS Code +        │        │ Reference helper scripts   │  │
│  │ Copilot Chat     │        │ (stdlib only, loopback)    │  │
│  └────────┬─────────┘        └─────────────┬──────────────┘  │
│           │ OTLP/HTTP                       │ HTTP           │
│           │ prompt-bearing spans            │ queries        │
│  ─────────┼─────────────────────────────────┼─────────────   │
│           │   127.0.0.1 ONLY (no off-host listener)          │
│  ┌────────▼─────────────────────────────────▼──────────────┐ │
│  │ TRUST BOUNDARY: otel-lgtm container                      │ │
│  │  ┌──────────┐ ┌──────────┐ ┌────────┐ ┌───────────────┐ │ │
│  │  │ OTLP recv│ │Prometheus│ │ Tempo  │ │ Grafana       │ │ │
│  │  │ :4317/18 │ │  :9090   │ │ :3200  │ │ :3000 admin   │ │ │
│  │  └────┬─────┘ └────┬─────┘ └───┬────┘ └───────────────┘ │ │
│  │       └────────────┴───────────┘                        │ │
│  │                    │ persists                            │ │
│  │        ┌───────────▼────────────┐                        │ │
│  │        │ copilot-otel-data vol  │  prompt content at rest│ │
│  │        │ (unencrypted, 120d)    │  no expiry on traces   │ │
│  │        └────────────────────────┘                        │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────┬───────────────────────────────────┘
                            │ image pull (tag-pinned, not digest-pinned)
             ┌──────────────▼───────────────┐
             │ TRUST BOUNDARY: public       │
             │ container registry           │
             └──────────────────────────────┘
```

### Boundary Descriptions

| Boundary             | Assets Protected                                 | Controls Enforced                                                                                               |
|----------------------|--------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| Operator workstation | Prompt content in transit, snapshot file         | Loopback-only port publishing; `captureContent` omitted from the documented settings block; stdlib-only helpers |
| otel-lgtm container  | Stored metrics and traces, Grafana configuration | Container isolation; single named volume; default credentials paired with no off-host listener                  |
| Public registry      | Image integrity, stack availability              | Tag-pinned image reference; no build step and no third-party plugin installation                                |

## Assets

| Id | Asset                                 | Lifetime                            | Notes                                                                                         |
|----|---------------------------------------|-------------------------------------|-----------------------------------------------------------------------------------------------|
| A1 | Prompt and tool-call content in spans | Persisted in the volume             | Observed present despite content capture being left at its default. Highest-value asset here. |
| A2 | Usage and cost metrics                | Persisted, 120-day retention        | Token counts, AIU billing proxy, tool call counts. Commercially sensitive in aggregate.       |
| A3 | `copilot-otel-data` Docker volume     | Persistent until explicitly removed | Unencrypted at rest. Survives `docker compose down` by design.                                |
| A4 | Grafana instance and dashboards       | Persistent                          | Default `admin`/`admin` credentials; reachable on loopback only.                              |
| A5 | Baseline snapshot file                | Persistent under the user cache     | Contains metric and service names plus session ids, not content.                              |
| A6 | Stack container image                 | External, pulled on first run       | `grafana/otel-lgtm:0.29.2`, tag-pinned rather than digest-pinned.                             |

## Adversaries

| Id    | Adversary                                         | In-scope mitigations                                                                                                                          |
|-------|---------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| ADV-a | Off-host network attacker                         | Every published port binds `127.0.0.1`, so no listener is reachable off the host. Default Grafana credentials are never exposed to a network. |
| ADV-b | Malicious or compromised process on the same host | Not mitigated. Loopback services are unauthenticated and any local process can read or write them (G-SPF-1).                                  |
| ADV-c | Another user on a shared workstation              | Bounded by Docker socket access and filesystem permissions on the volume. Not otherwise mitigated (G-INF-2).                                  |
| ADV-d | Upstream image or registry compromise             | Tag pinning limits drift; no digest verification or signature check is performed (G-SUP-1).                                                   |
| ADV-e | Operator error redirecting the exporter off-host  | Documentation states the endpoint carries prompt content and must be treated as sensitive regardless of the capture setting.                  |

## Bucket B1: Editor OTLP ingest

Covers the path from the Copilot Chat exporter to the container's OTLP receiver.

### Spoofing

The OTLP receiver performs no authentication. Any process able to reach `127.0.0.1:4318` can submit spans and metrics using the `copilot-chat` service name and genuine Copilot metric names, making injected series indistinguishable from real editor output by inspection alone. `examples/baseline.py` exists specifically to make this detectable after the fact: it captures the pre-enablement store state and reports discriminators that require real editor activity. Detection, not prevention. Tracked as G-SPF-1.

### Tampering

An unauthenticated writer can also poison existing series by submitting conflicting samples for the same metric and label set. The stack applies no ingest-side validation or allow-listing. Loopback binding limits this to local processes.

### Repudiation

The receiver records no provenance for accepted payloads beyond the resource attributes the sender chooses to supply, so a submitting process cannot be identified after ingest. `service_version` and `session_id` label values are attacker-controlled in the injection case. `baseline.py` diffing provides a coarse before-and-after record rather than per-payload attribution.

### Information Disclosure

This is the material risk in the entire model. Spans emitted with content capture left at its documented default were directly observed carrying `copilot_chat.user_request` (full prompt text), `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.tool.call.arguments`, `gen_ai.tool.call.result`, and `gen_ai.system_instructions`. The transport is plaintext HTTP. On loopback this is contained; the moment `otlpEndpoint` is redirected to a shared or hosted collector, prompt content leaves the machine in clear text. The skill documents this discrepancy explicitly and supplies a `curl` check so a reader verifies rather than trusts the documented default. Tracked as G-INF-1 and G-TLS-1.

### Denial of Service

Prometheus drops delta-temporality metrics by default, and a dropped delta metric was observed failing an entire batched write, discarding co-batched cumulative metrics. `compose.yaml` sets `--enable-feature=otlp-deltatocumulative` so conversion replaces dropping. The conversion state is held in memory and resets when the container restarts, producing a bounded gap rather than a persistent failure. Unauthenticated ingest also permits volumetric flooding of the local store by a local process. Tracked as G-DOS-1.

### Elevation of Privilege

Not applicable. The receiver executes no submitted content; OTLP payloads are parsed as data into the metric and trace stores, and no code path evaluates them.

### Risk Rating

| Threat                                         | Likelihood | Impact | Residual Risk | Status                                                |
|------------------------------------------------|------------|--------|---------------|-------------------------------------------------------|
| Local process injects synthetic Copilot series | Low        | Medium | Medium        | Detectable via `baseline.py`; not prevented (G-SPF-1) |
| Prompt content traverses plaintext OTLP        | High       | High   | Medium        | Contained by loopback binding only (G-INF-1, G-TLS-1) |
| Batched write loss from delta temporality      | Low        | Low    | Low           | Mitigated by delta-to-cumulative conversion (G-DOS-1) |
| Local flooding of the ingest endpoint          | Low        | Low    | Low           | Accepted for a single-machine demonstration stack     |

## Bucket B2: Telemetry at rest and query surfaces

Covers the persistent volume, Prometheus, Tempo, and the Grafana UI.

### Spoofing

Grafana ships with `admin`/`admin` and the skill does not change them. Any local process or local user can authenticate as the Grafana administrator. The compensating control is that Grafana is published on `127.0.0.1:3000` only, so the weak credential is never presented to a network. Prometheus and Tempo expose no authentication at all. Tracked as G-SPF-1.

### Tampering

A Grafana administrator can alter or delete dashboards and datasource definitions. `examples/validate_dashboard.py` performs exactly this operation with `overwrite: true`, which is intended for the skill's own dashboard but would overwrite an unrelated dashboard occupying the same uid. The examples README directs the reader to run it against a throwaway Grafana. Direct volume access permits arbitrary modification of stored series. Tracked as G-TAM-1.

### Repudiation

Grafana's default configuration retains limited audit history, and Prometheus and Tempo record no query log. Actions taken through the shared `admin` account are attributable to the account, not to a person, so on a shared workstation no meaningful attribution exists.

### Information Disclosure

The volume holds A1 and A2 unencrypted for the life of the volume. Prometheus retention is set to 120 days deliberately, so monthly token aggregates are real rather than silently truncated at the 15-day default; the same setting extends how long usage data persists. Tempo retention is not configured here, so trace content carrying prompt text persists under the image's own default. Any local user with Docker access or filesystem access to the volume can read all of it. `docker compose down` deliberately preserves the volume, so an operator who believes they have torn the stack down has in fact retained the corpus. Teardown documentation states both variants explicitly. Tracked as G-INF-1 and G-INF-2.

### Denial of Service

The volume grows without bound for traces, because no Tempo retention limit is set. A long-running stack on a small disk can exhaust local storage. Prometheus is bounded by its 120-day retention setting.

### Elevation of Privilege

Grafana's administrator role is the highest privilege in this bucket and is reachable with published default credentials from any local process. That is privilege escalation within the stack, though not beyond the host user's existing authority, since the same actor could read the volume directly. Tracked as G-EOP-1.

### Risk Rating

| Threat                                            | Likelihood | Impact | Residual Risk | Status                                                |
|---------------------------------------------------|------------|--------|---------------|-------------------------------------------------------|
| Prompt content readable at rest by any local user | Medium     | High   | Medium        | Unencrypted volume; no expiry on traces (G-INF-2)     |
| Default Grafana credentials accepted              | High       | Medium | Low           | Loopback-only publishing (G-SPF-1, G-EOP-1)           |
| Dashboard overwritten by the validation helper    | Low        | Low    | Low           | Documented; run against a throwaway Grafana (G-TAM-1) |
| Unbounded trace growth exhausts disk              | Low        | Medium | Low           | Accepted; operator removes the volume to reclaim      |

## Bucket B3: Reference helper scripts to local service APIs

Covers the four Python files under `examples/`. None is agent-executed.

### Spoofing

Every helper targets hard-coded `http://localhost` URLs with no certificate or identity verification, which is inherent to plaintext loopback HTTP. A local process that binds one of these ports before the container does can impersonate the service and return fabricated results, causing `verify.py` to report a healthy stack that does not exist. Low likelihood, and it requires an adversary already executing on the host.

### Tampering

Three of the four helpers issue only HTTP GET requests and mutate nothing. `validate_dashboard.py` issues one POST to the Grafana dashboard import API. `baseline.py` writes a single JSON file, defaulting to `~/.cache/copilot-otel/pre-enable-baseline.json` and overridable through `COPILOT_OTEL_BASELINE`. The path is derived from the environment rather than from any service response, so a hostile service cannot redirect the write.

### Repudiation

Not applicable. The helpers are operator-invoked interactive tools that print their results to standard output and keep no log that a security decision depends on.

### Information Disclosure

The helpers print metric names, label values, and series values to the terminal. `inspect_metrics.py` prints label sets, which include model names, tool names, and session identifiers, but not span content: prompt-bearing attributes live on spans in Tempo and are not enumerated by any shipped helper. `baseline.py` persists metric names, service names, service versions, session ids, and trace names to its snapshot file. No helper writes prompt content to disk, and none transmits anything off the host. Terminal output may still be captured by shell history or a session recorder.

Everything returned from the store is untrusted data, never instructions. B1 Spoofing establishes that any local process can inject series carrying genuine Copilot names with attacker-controlled `service_version` and `session_id` values, and those values are exactly what these helpers print. The same applies to span attributes and trace names read through Tempo. Treat helper output, query results, and dashboard content as data to be inspected, and never act on text embedded in them.

### Denial of Service

`validate_dashboard.py` replays every dashboard panel query, which is the heaviest operation the skill performs against Prometheus and Tempo. It is bounded by the panel count and by per-request timeouts. `baseline.py` and `verify.py` issue one query per metric name, which scales with the store's cardinality. All are operator-triggered and none loops.

### Elevation of Privilege

Not applicable. The helpers run with the invoking user's privileges, spawn no subprocess, evaluate no fetched content, and require no elevation. They import only the Python standard library, so they introduce no third-party dependency.

### Risk Rating

| Threat                                              | Likelihood | Impact | Residual Risk | Status                                                    |
|-----------------------------------------------------|------------|--------|---------------|-----------------------------------------------------------|
| Local port impersonation misleads `verify.py`       | Low        | Low    | Low           | Accepted for loopback plaintext HTTP                      |
| Hard-coded default credentials in the import helper | Medium     | Low    | Low           | Matches the stack's own default; loopback only (G-TAM-1)  |
| Sensitive label values reach terminal output        | Medium     | Low    | Low           | Labels only; span content is never enumerated by a helper |

## Bucket B4: Container image supply chain

Covers acquisition of the `grafana/otel-lgtm` image.

### Spoofing

The image is referenced as `grafana/otel-lgtm:0.29.2` from the default public registry. A registry or namespace compromise able to repoint that tag would be accepted without challenge, because no digest pin and no signature verification are performed. Tracked as G-SUP-1.

### Tampering

Tags are mutable. A republished `0.29.2` would be pulled on any host that has not already cached the layers, and nothing in the skill would detect the substitution. Digest pinning is the standard control and is not applied here. Tracked as G-SUP-1.

### Repudiation

Docker records the resolved image digest locally after a pull, so the specific image actually running is identifiable on that host after the fact. The skill does not capture or compare that digest, so drift between two hosts pulling the same tag at different times goes unnoticed.

### Information Disclosure

Not applicable. The pull requests a public image by name and reveals nothing beyond ordinary registry access patterns. The skill supplies no credentials to the registry.

### Denial of Service

Registry unavailability blocks the first run only. Once layers are cached, `docker compose up -d` succeeds without network access, and `restart: unless-stopped` returns the stack after a host reboot.

### Elevation of Privilege

The container runs under the Docker daemon with whatever default privileges the image declares, and the compose definition adds no capabilities, no privileged flag, and no host mounts other than the single named data volume. A compromised image would nonetheless hold whatever authority the daemon grants, which on a typical developer workstation is root-equivalent. That is inherent to running any container and is bounded by the tag pin alone. Tracked as G-SUP-1 and G-EOP-2.

### Risk Rating

| Threat                                   | Likelihood | Impact | Residual Risk | Status                                          |
|------------------------------------------|------------|--------|---------------|-------------------------------------------------|
| Malicious image substitution under a tag | Low        | High   | Medium        | Tag-pinned, not digest-pinned (G-SUP-1)         |
| Compromised image gains daemon authority | Low        | High   | Medium        | No added capabilities or host mounts (G-EOP-2)  |
| Registry outage blocks first run         | Low        | Low    | Low           | Accepted; cached layers make later runs offline |

## Enterprise Readiness Gaps

| Id      | Severity        | Gap                                                                                                                                                                                                                                      | Status                                                                                                                        |
|---------|-----------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| G-INF-1 | InfoDisc-High   | Spans carry full prompt text, tool call arguments and results, and system instructions on a configuration where content capture was left at its documented default. The skill cannot change extension behavior and applies no redaction. | Documented prominently with a verification command. Contained only by loopback binding. Blocking for any non-local collector. |
| G-INF-2 | InfoDisc-Med    | The `copilot-otel-data` volume stores captured content unencrypted, with no Tempo retention limit and no expiry, and survives `docker compose down` by design.                                                                           | Accepted for a single-machine demonstration. Teardown documentation states both variants explicitly.                          |
| G-SPF-1 | Spoofing-Med    | OTLP ingest, Prometheus, and Tempo are unauthenticated, and Grafana accepts published default credentials. Any local process can read or write the store.                                                                                | Mitigated only by `127.0.0.1` port binding. `baseline.py` provides after-the-fact detection of injected series.               |
| G-SUP-1 | SupplyChain-Med | The stack image is pinned by tag rather than by digest, and no signature or provenance verification is performed before the container runs.                                                                                              | Open. Digest pinning would close the substitution vector at the cost of manual updates.                                       |
| G-EOP-1 | EoP-Low         | Grafana administrator access is reachable from any local process using published default credentials.                                                                                                                                    | Accepted. The same actor can already read the volume directly, so the escalation does not cross the host user boundary.       |
| G-EOP-2 | EoP-Med         | A compromised stack image would execute with Docker daemon authority, which is root-equivalent on a typical developer workstation.                                                                                                       | Bounded by the tag pin, by adding no capabilities, and by mounting no host paths beyond the named volume.                     |
| G-TAM-1 | Tampering-Low   | `validate_dashboard.py` imports with `overwrite: true` using default credentials, so it would replace an unrelated dashboard sharing the same uid.                                                                                       | Documented. The examples README directs the reader to run it against a throwaway Grafana.                                     |
| G-DOS-1 | DoS-Low         | Delta-to-cumulative conversion state is held in memory and resets on container restart, producing a bounded gap in converted series.                                                                                                     | Accepted. Without the flag the failure mode is worse, because a dropped delta metric can fail an entire batched write.        |
| G-TLS-1 | InfoDisc-Low    | OTLP ingest and all service queries use plaintext HTTP with no transport security.                                                                                                                                                       | Acceptable on loopback. Material the moment `otlpEndpoint` targets a remote collector, which the skill states explicitly.     |

## References

* [Monitor agent usage with OpenTelemetry](https://code.visualstudio.com/docs/agents/guides/monitoring-agents)
* [Manage AI settings in enterprise environments](https://code.visualstudio.com/docs/enterprise/ai-settings)
* [OTel GenAI semantic conventions](https://github.com/open-telemetry/semantic-conventions/blob/main/docs/gen-ai/)
* [Grafana OTel-LGTM image](https://github.com/grafana/docker-otel-lgtm)
* [Prometheus OTLP receiver documentation](https://prometheus.io/docs/guides/opentelemetry/)
* [Repo-wide STRIDE model](../../../../docs/security/security-model.md)

🤖 Crafted with precision by ✨Copilot following brilliant human instruction, then carefully refined by our team of discerning human reviewers.
