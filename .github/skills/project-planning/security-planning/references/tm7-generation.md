---
title: TM7 Generation Format Contract
description: OTM-aligned input schema, mapping reference, template profile contract, and current native feedback workflow for TM7 generation.
ms.date: 2026-07-17
ms.topic: reference
---

<!-- markdownlint-disable-file -->

## TM7 generation reference

This document records the phase-validated wire facts and the current input-contract decisions for the TM7 generation extension. The content is intentionally independent of the upstream OTM schema wording and is aligned to OTM concepts for interoperability rather than copied from the upstream document.

## Native TM7 visual feedback workflow

The skill also supports an opt-in, Windows-local feedback loop that replays a validated layout overlay through the generator and validates the result in the native Microsoft Threat Modeling Tool UI. The workflow is disabled unless `validate_tm7_with_tmt.py` is invoked with `--feedback-loop`, `--spec`, and `--overlay-output`. When those flags are absent, the default generation and validation behavior remains unchanged.

### Current CLI contract

The current parser accepts:

- `--feedback-loop` to enable the bounded native feedback loop
- `--spec` to supply the threat-model spec used for overlay invalidation and replay
- `--overlay-input` to replay an existing overlay payload
- `--overlay-output` to write the final pending overlay payload
- `--max-iterations` with a value from `1` through `3` for the number of refinement iterations after the baseline
- `--require-feedback-evidence` to require per-surface screenshot, UIA, metrics, and findings evidence before the run is accepted

The native harness also requires a positional input model, `--evidence-dir`, and the pinned Microsoft Threat Modeling Tool version `7.3.51110.1`. The current implementation treats the workflow as a local UI Automation workflow that must run on Windows with an interactive desktop session. The run stops as `tmt-unavailable` on non-Windows hosts or when TMT cannot be discovered, and it reports `version-mismatch`, `automation-timeout`, or `unexpected-modal` when the runtime environment diverges from the expected harness contract.

The feedback loop is operator-safe by contract: the operator should not interact with the mouse, keyboard, or windows while the harness is running. The harness announces the start of automation, surfaces baseline/refinement candidate progress, and emits a release notice once the loop completes or aborts so the operator knows the computer can be used again. The workflow may open, close, and reopen TMT more than once to complete save/reopen validation.

### Evidence layout

Each run writes a redacted evidence bundle rooted at the requested evidence directory. The root contains `manifest.json`, `status.json`, `action.log`, and the `screenshots/`, `uia/`, `exports/`, `summaries/`, and `logs/` folders. The run also writes `iterations/00-baseline` plus `iterations/01` through `iterations/03` as needed. Each iteration bundle contains per-surface screenshots, UIA snapshots, summaries, and the generated candidate model, and the loop writes an iteration-scoped `overlay.yaml` into the iteration bundle plus a final pending overlay to the explicit `--overlay-output` path; the payload carries `approval_state: pending` and the runtime never auto-promotes it to `approved`.

### Deterministic metrics, thresholds, and stop reasons

The deterministic geometry gates are separate from the advisory screenshot heuristics. The current implementation treats the following geometry findings as review or warning gates:

- `overlap_ratio > 0.03` becomes a review finding, while `overlap_ratio >= 0.01` becomes a warning
- `edge_node_intersections > 2` becomes a review finding, while `edge_node_intersections > 0` becomes a warning
- `edge_crossing_count > 2` becomes a review finding in non-dense layouts, while dense layouts warn at `>= 1`
- `min_spacing_ratio < 0.3` becomes a review finding, while `min_spacing_ratio < 0.6` becomes a warning
- a missing or incomplete surface capture is a review finding

Screenshot heuristics are advisory. They can raise a review finding when the image analysis indicates a likely defect, but they do not override deterministic geometry gates or the human semantic review step.

The loop uses the stable stop reasons `gates-cleared`, `repeated-defect-no-improvement`, `max-iterations`, `evidence-incomplete`, `semantic-regression`, `tmt-unavailable`, `version-mismatch`, `automation-timeout`, and `unexpected-modal`. A baseline run plus three refinement iterations is the maximum bounded execution. Semantic regression is evaluated against the baseline model identity and blocks promotion even when the geometry score improves.

### Overlay schema and invalidation

The feedback overlay is a versioned payload with `schema_version`, `overlay_type`, `model_id`, `overlay_id`, `applies_to`, `rules`, `provenance`, and `invalidation` fields. The overlay schema accepts `position`, `relative_to`, and `keep_route_clear` rules and requires `approval_state: pending` for overlays emitted by automation. Invalidation is based on the spec fingerprint, generator-profile fingerprint, and a deterministic surface-identity fingerprint. These checks reject stale or tampered overlays before a candidate model is generated.

### Windows-local example

```bash
uv run --project .github/skills/project-planning/security-planning --group windows \
  python scripts/validate_tm7_with_tmt.py model.tm7 \
  --evidence-dir ./artifacts/feedback \
  --feedback-loop \
  --spec ./specs/model.yaml \
  --overlay-output ./artifacts/feedback/overlay.json \
  --max-iterations 3 \
  --require-feedback-evidence
```

Human approval remains the external review action. The automation writes pending overlays only and keeps the canonical baseline unchanged until a reviewer explicitly promotes a result outside this loop.

> This schema is an independently authored HVE-Core artifact and is not a verbatim copy of the Open Threat Model (OTM) specification. It is aligned to OTM concepts and terminology for interoperability and was informed by the OTM project maintained by IriusRisk: https://github.com/iriusrisk/OpenThreatModel. OTM is licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0), https://creativecommons.org/licenses/by-sa/4.0/. Any adaptation or redistribution should preserve this attribution and apply the same CC BY-SA terms where applicable.

## Canonical input schema

The generator accepts a vendor-neutral YAML or JSON threat-model spec whose top-level structure is intentionally generic and data-driven.

```yaml
project_metadata:
  name: Example service
  version: 1.0
  summary: Generic example threat model
  scope: Service boundary
  assumptions:
    - Traffic flows over a public network
  policy_values:
    cryptography_suites:
      - TLS 1.3
    identity_providers:
      - OpenID Connect compatible identity provider
    data_classification_labels:
      - public
      - internal
      - restricted

representations:
  context_diagrams:
    - id: ctx-01
      name: Context diagram
      description: System boundary and external entities
      elements: []
      flows: []
      trust_zone_ids: []
  functional_scenarios:
    - id: func-01
      name: Primary interaction
      description: Primary use case
      elements: []
      flows: []
      trust_zone_ids: []
  operational_views:
    - id: op-01
      name: Deployment and operations
      description: Managed deployment and operating model
      components: []
      trust_zone_ids: []

assets:
  - id: asset-01
    name: User content
    kind: data
    description: User-supplied content
    sensitivity: internal
    category: Content

components:
  - id: comp-01
    name: Application process
    kind: process
    asset_ids:
      - asset-01
    trust_zone_id: tz-01

trust_zones:
  - id: tz-01
    name: Application boundary
    description: In-scope boundary

data_flows:
  - id: flow-01
    source_ref: ext-01
    target_ref: comp-01
    ordinal: 1
    transport: HTTPS
    encryption: TLS 1.3
    authentication: bearer token
    authorization: scoped access token
    data_sensitivity: internal
    retention: 90 days
    notes: Primary request path

threats:
  - id: threat-01
    target_ref: comp-01
    interaction_ref: flow-01
    category: tampering
    title: Tampering of request payload
    description: An attacker could alter the payload in transit
    state: Open
    citations:
      stride:
        - T
      nist:
        - SC-8
      mitre: []
    mitigation_ids:
      - mitigation-01

mitigations:
  - id: mitigation-01
    name: Payload signature verification
    description: Validate request content integrity
    target_refs:
      - comp-01
    citations:
      nist:
        - SC-8

abuse_cases:
  - id: abuse-01
    title: Replay of a signed request
    description: An attacker reuses a previously valid request
    actor: External adversary
    objective: Bypass intended controls
    evil_user_story: As an authenticated low-privilege user, I want to manipulate the checkout flow so that I can bypass authorization
    flow_ids:
      - flow-01
    mitigation_ids:
      - mitigation-01

security_test_cases:
  - id: test-01
    title: Negative boundary input
    description: Submit malformed input and verify rejection
    target_refs:
      - comp-01
    test_type: negative-input
    expected_result: Request is rejected and logged
```

### Semantic target and placement interaction

`threats[].target_ref` identifies the component or element whose behavior is
threatened. `threats[].interaction_ref` identifies the concrete data flow used to
place the threat instance in TM7. The semantic target must be the source or target
endpoint of that interaction by default.

When TM7 cannot represent a reviewed component threat without using a nearby
carrier interaction, declare the exception rather than relying on same-surface
coexistence:

```yaml
placement_override:
  reviewed: true
  rationale: The selected interaction is the reviewed TM7 carrier for this component threat.
```

The portable validator rejects non-endpoint placement when the override is absent,
unreviewed, or lacks a rationale. Human review remains required; automated tooling
does not set `reviewed: true` on behalf of a reviewer.

### Authored-base reconciliation

Portable validation operates only on the threat-model specification. When an
existing TMT-authored base is supplied, run a separate reconciliation gate. That
gate verifies that each placement connector exists on its declared surface, all
surface and connector GUIDs are non-null, and connector endpoints match the
authored element identities corresponding to the declared source and target.

A portable pass does not imply that an authored base is complete. Missing elements,
missing connectors, wrong-surface connectors, and endpoint identity drift are
authored-base reconciliation failures.

### Native template upgrades

Treat TMT's `Threat Model Conversion Confirmation` prompt as a controlled
migration boundary. The native harness defaults to `fail` and requires one of
three explicit policies:

* `fail` — preserve the model and report that a newer template is available.
* `decline` — open against the embedded template without changing it.
* `apply` — apply the installed template to a harness-owned working copy.

Apply a newer template to a topology-complete model with zero threat instances,
then populate explicit threats only after the upgraded base passes save/reopen and
authored-base reconciliation. Applying a template after explicit population can
retain the threat rows as stale entries whose interaction is `Deleted`.

TMT's native conversion replaces the embedded KnowledgeBase. When the project
uses deterministic custom threat types, compose the upgraded stock template with
those custom types before population. The harness must verify the expected custom
type count and clean reopen before publishing the composed base.

Stale-threat deletion is independent from template application and remains off by
default. Enable it only through the explicit `--delete-stale-threats` option after
reviewing the impact on human-authored threat notes and state.

### CTM field inventory

| CTM    | Field path                                                                                                                                                                                       | Notes                                                              |
|--------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------|
| CTM-1  | `representations.context_diagrams`                                                                                                                                                               | Context/system view with external entities and boundaries          |
| CTM-2  | `representations.functional_scenarios`                                                                                                                                                           | Functional/scenario view with trust boundaries and data flows      |
| CTM-3  | `representations.operational_views`                                                                                                                                                              | Deployment and operating context                                   |
| CTM-4  | `threats` and `mitigations`                                                                                                                                                                      | Threat analysis with mitigations                                   |
| CTM-5  | `data_flows[].ordinal`                                                                                                                                                                           | Numbered flows                                                     |
| CTM-6  | `data_flows[].transport`, `data_flows[].encryption`, `data_flows[].authentication`, `data_flows[].authorization`, `data_flows[].data_sensitivity`, `data_flows[].retention`, `assets[].category` | Per-flow annotation fields and optional asset classification hints |
| CTM-7  | `threats[].state`, `threats[].citations`, `mitigations`                                                                                                                                          | Reviewable triage and status                                       |
| CTM-8  | `abuse_cases`, `abuse_cases[].evil_user_story`                                                                                                                                                   | Abuse-case and evil-user-story capture                             |
| CTM-9  | `security_test_cases`                                                                                                                                                                            | Negative and boundary-test artifacts                               |
| CTM-10 | `project_metadata`, `representations`, `threats`, `mitigations`, `abuse_cases`, `security_test_cases`                                                                                            | The complete spec must be rich enough to emit a reviewable model   |

## CTM-to-carrier mapping

| CTM    | Input field(s)                                                                                             | OTM-like carrier                          | TM7 carrier                                                              |
|--------|------------------------------------------------------------------------------------------------------------|-------------------------------------------|--------------------------------------------------------------------------|
| CTM-1  | `representations.context_diagrams`                                                                         | representation and trust-zone context     | drawing surface with external-interactor/process/store/boundary elements |
| CTM-2  | `representations.functional_scenarios`                                                                     | scenario-oriented representation          | drawing surface with flow and boundary geometry                          |
| CTM-3  | `representations.operational_views`                                                                        | operational representation                | drawing surface with deployment-oriented components                      |
| CTM-4  | `threats`, `mitigations`                                                                                   | threats and mitigations                   | threat instances plus notes/properties                                   |
| CTM-5  | `data_flows[].ordinal`                                                                                     | numbered dataflow ordering                | connector properties and labels                                          |
| CTM-6  | `data_flows[].transport`, `encryption`, `authentication`, `authorization`, `data_sensitivity`, `retention` | dataflow attributes                       | connector properties                                                     |
| CTM-7  | `threats[].state`, `threats[].citations`                                                                   | review state and evidence                 | threat state and citation-bearing notes/properties                       |
| CTM-8  | `abuse_cases`                                                                                              | adversary narrative                       | threat entries and notes                                                 |
| CTM-9  | `security_test_cases`                                                                                      | test-plan evidence                        | notes or cross-references in the generated markdown twin                 |
| CTM-10 | whole spec                                                                                                 | complete threat-model interchange payload | the generated `.tm7` file itself                                         |

## Verified TM7 wire facts

### Namespaces

The generator uses the namespaces verified against the Threat Modeling Tool's own `SerializableModelData` DataContract (`ThreatModeling.ExternalStorage.OM.SerializableModelData`, serialized as `<ThreatModel>` in the Model namespace):

* Model namespace: `http://schemas.datacontract.org/2004/07/ThreatModeling.Model`
* Abstracts namespace: `http://schemas.datacontract.org/2004/07/ThreatModeling.Model.Abstracts`
* KnowledgeBase namespace: `http://schemas.datacontract.org/2004/07/ThreatModeling.KnowledgeBase`
* Serialization arrays namespace: `http://schemas.microsoft.com/2003/10/Serialization/Arrays`
* XML schema-instance namespace: `http://www.w3.org/2001/XMLSchema-instance`

### Element and threat serialization rules

These rules reflect the DataContract graph verified against the Threat Modeling Tool's own serializer: `SerializableModelData.GetSerializer()` deserializes the generated file with no `SerializationException`. They were extracted from a genuine, TMT-loadable reference export (`tests/fixtures/tmt-reference.tm7`), not a reverse-engineered inference.

* Each `DrawingSurfaceModel` carries the base fields `GenericTypeId` (`DRAWINGSURFACE`), `Guid`, `Properties`, `TypeId`, then `Borders`, `Header`, `Lines`, and a trailing `Zoom` (default `1`).
* Every `Properties` display attribute is an `a:anyType` with a polymorphic `i:type` (`b:HeaderDisplayAttribute` or `b:StringDisplayAttribute`) in the KnowledgeBase namespace. Because `StringDisplayAttribute.Value` is typed as `object`, a present `<b:Value>` **must** carry `i:type="c:string"` (xsd:string); omitting the type hint makes the DataContract serializer reject the file with `Element Value ... cannot have child contents to be deserialized as an object`. `HeaderDisplayAttribute` uses an empty `<b:Name/>` and `<b:Value i:nil="true"/>`; `StringDisplayAttribute` sets `<b:Name>` to the property key.
* Shapes are stored in `Borders` as a GUID-keyed dictionary of `a:KeyValueOfguidanyType` entries (in the Serialization Arrays namespace). Each `a:Value` carries a polymorphic `i:type` — `StencilRectangle` (external interactor, `GE.EI`), `StencilEllipse` (process, `GE.P`), `StencilParallelLines` (data store, `GE.DS`), or `BorderBoundary` (trust boundary box, `GE.TB.B`) — plus base fields `GenericTypeId`, `Guid`, `Properties`, `TypeId` and geometry `Height`, `Left`, `StrokeDashArray`, `StrokeThickness`, `Top`, `Width`.
* Data flows are stored in `Lines` as `a:KeyValueOfguidanyType` entries whose `a:Value` uses `i:type="Connector"` (`GE.DF`) with `SourceGuid`, `SourceX`, `SourceY`, `TargetGuid`, `TargetX`, `TargetY`, `HandleX`, `HandleY`, and `StrokeThickness`. An unconnected endpoint uses the all-zero GUID sentinel `00000000-0000-0000-0000-000000000000`.
* The root model carries, in order, `DrawingSurfaceList`, `MetaInformation`, `Notes`, `ThreatInstances`, `ThreatGenerationEnabled`, `Validations`, `Version`, `KnowledgeBase`, and `Profile` (`<Profile><PromptedKb xmlns=""/></Profile>`).
* The verified `Version` string is `4.3`. All `z:Id` values form a single contiguous sequence: diagram objects are numbered `i1..iN` in document order, and the embedded `KnowledgeBase` root `z:Id` is renumbered to `i(N+1)` at generation time. Because no `z:Ref` targets the KnowledgeBase root, this keeps every id unique with no model-size ceiling (the earlier fixed `i36` start capped diagrams at ~35 objects).

### Threats, the embedded KnowledgeBase, and citations

A loadable `.tm7` derives its threats from an embedded DataContract KnowledgeBase, exactly as the reference file does — it does not hand-serialize threat instances.

* Generated output emits an **empty** `<ThreatInstances/>` and `<ThreatGenerationEnabled>false</ThreatGenerationEnabled>`, matching the loadable reference. TMT generates threats from the embedded KnowledgeBase when the model is opened.
* The generator embeds a verbatim DataContract `<KnowledgeBase>` from the bundled `assets/templates/default-kb.xml` asset. That asset was extracted from the genuine TMT reference export; it is Azure-flavored but includes the generic `GE.*` stencils this generator emits. Swapping in a smaller MIT SDL-core DataContract KnowledgeBase is tracked as follow-up work.
* Per-threat STRIDE + NIST SP 800-53 (+ optional MITRE ATT&CK/CAPEC) citations are surfaced in the synchronized markdown twin (`generate_markdown.py`), which reuses the generator's deterministic threat derivation. The `threats[].citations` field in the input spec remains the source-of-truth structure for those citations.
* The `bundled .tb7` under `assets/templates/` is a no-namespace XmlSerializer template and is NOT spliced into the `.tm7` directly; the DataContract `default-kb.xml` is the embeddable KnowledgeBase.

## STRIDE-per-element matrix

| Element kind        | Baseline STRIDE categories                                                                          |
|---------------------|-----------------------------------------------------------------------------------------------------|
| External interactor | Spoofing                                                                                            |
| Process             | Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege |
| Data store          | Tampering, Information Disclosure, Denial of Service, Repudiation for logging stores                |
| Data flow           | Tampering, Information Disclosure, Denial of Service                                                |
| Trust boundary      | No direct threat by itself; use it as a grouping and routing anchor                                 |

## Mode-flag behavior

* `pre-populated-comprehensive` is the default mode. The generator emits a full set of pre-populated threats and sets `ThreatGenerationEnabled` to avoid duplicate auto-generation in TMT.
* `diagram-only-defer-to-tmt` emits the diagram elements and flows without pre-populating threats, leaving TMT to generate them if desired.
* The two modes should not both populate the same threat set for the same model.

## Template-profile abstraction

The generator should support a pluggable profile abstraction where each profile maps generic DFD semantics to a concrete template's stencil `TypeId` values and a knowledge-base reference.

```yaml
template_profiles:
  sdl_core_generic:
    description: Generic SDL/Core profile for broad threat modeling
    asset_source: microsoft/threat-modeling-templates/default.tb7
    knowledge_base: default
    type_ids:
      external_interactor: GE.EI
      process: GE.P
      data_store: GE.DS
      data_flow: GE.DF
      trust_boundary_line: GE.TB.L
      trust_boundary_box: GE.TB.B
      annotation: GE.A
```

### Default shipped profile

The default profile is the generic SDL/Core profile and uses the verified generic stencil TypeIds:

* External interactor: `GE.EI`
* Process: `GE.P`
* Data store: `GE.DS`
* Data flow: `GE.DF`
* Trust boundary line: `GE.TB.L`
* Trust boundary box: `GE.TB.B`
* Annotation: `GE.A`

### Reference-only profile tables

The following profiles are documented as mapping-table references and are not bundled as redistributed template files because they are either domain-specific or were not confirmed as bundled MIT artifacts in the initial pass.

| Profile         | Status                       | Notes                                                                                                                                                                    |
|-----------------|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Azure           | Reference-only mapping table | Public Azure-oriented profile with examples such as `SE.P.TMCore.AzureAppServiceWebApp`, `SE.P.TMCore.AzureAD`, and `SE.P.TMCore.Host` from public tooling documentation |
| PatrickGallucci | Reference-only mapping table | Public profile catalog with a richer cloud-oriented threat vocabulary; keep as a mapping-table reference until a confirmed redistribution path is chosen                 |

## Standards rationale and public citations

The generated TM7 file and its markdown twin are justified by public, vendor-neutral standards and guidance:

* OWASP Threat Modeling Cheat Sheet: DFD completeness, trust boundaries, data flows, data stores, processes, and external entities. Source: <https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html>
* OWASP Abuse Case Cheat Sheet: abuse cases, adversary narratives, and security test cases. Source: <https://cheatsheetseries.owasp.org/cheatsheets/Abuse_Case_Cheat_Sheet.html>
* Threat Modeling Manifesto: methodology-neutral review questions and representation-driven analysis. Source: <https://www.threatmodelingmanifesto.org/>
* NIST Risk Management Framework: data-sensitivity and impact-based categorization. Source: <https://csrc.nist.gov/Projects/risk-management/about-rmf>
* MITRE ATT&CK and CAPEC: optional enrichment for abuse-case-driven threats. Source: <https://attack.mitre.org/> and <https://capec.mitre.org/>

The extension therefore uses a vendor-neutral, standards-aligned input contract and preserves traceability in the emitted TM7 model without copying the upstream OTM schema text.

## Verifying TMT deserialization

Generated files are validated against the Threat Modeling Tool's own assemblies rather than a hand-crafted schema. `tests/Deserialize-Tm7.ps1` locates the installed `ThreatModeling.ExternalStorage.Local.dll`, obtains the exact `DataContractSerializer` from `SerializableModelData.GetSerializer()`, and calls `ReadObject` on a target `.tm7`. The TMT assemblies are 32-bit, so the harness re-launches itself under the 32-bit Windows PowerShell host when invoked from a 64-bit process. It prints `DESERIALIZE_OK` (exit 0) on success, `DESERIALIZE_FAIL: <message>` (exit 1) on a contract mismatch, and `TMT_ASSEMBLIES_NOT_FOUND` (exit 3) when the tool is not installed.

The pytest suite drives this harness in `test_given_generated_tm7_when_deserialized_by_tmt_then_round_trips` for both generation modes and against the reference fixture. The tests skip cleanly on non-Windows hosts or when the assemblies are absent (for example, in CI) and run automatically when the tool is installed locally. Structural-parity tests additionally assert that the generated root and `DrawingSurfaceModel` member order match `tests/fixtures/tmt-reference.tm7`.
