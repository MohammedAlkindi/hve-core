---
title: Validation, drift, and observability boundaries
description: The data-validation versus data-drift distinction with its correct source, the asymmetric remediation each triggers, and the ownership seam for telemetry and classification
---

## Sources

* Microsoft CSE Code-with-Engineering-Playbook, [ML Model Production Checklist](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-model-checklist/#how-will-incoming-data-quality-be-monitored), MIT licensed. This is the source of the validation-versus-drift distinction.
* Microsoft CSE Code-with-Engineering-Playbook, [Data and DataOps Fundamentals, Observability](https://microsoft.github.io/code-with-engineering-playbook/design/design-patterns/data-heavy-design-guidance/#observability), MIT licensed.
* Microsoft CSE Code-with-Engineering-Playbook, [Observability in Machine Learning](https://microsoft.github.io/code-with-engineering-playbook/observability/ml-observability/), MIT licensed.

Content below is derived from the upstream pages. The validation-versus-drift definitions, the remediation pair, and the data-validation practice list stay close to or match upstream wording; other passages are paraphrased. MIT permits this with the notice recorded in `THIRD-PARTY-NOTICES`. The validation-versus-drift distinction comes from the ML Model Production Checklist, not from the DataOps Fundamentals page or the testing page; cite the checklist for it.

## Validation and drift are different mechanisms

**Data validation detects errors in the data.** The upstream example is a datum falling outside its expected range.

**Data drift detection uncovers legitimate changes in the data** that are truly representative of the phenomenon being modeled, and are not erroneous. The upstream example is user preferences changing.

Both are worth monitoring. They are not the same signal and they do not share a response.

Before classifying an observed shift as drift, rule out an upstream ingestion or schema defect. A shift caused by a defect is a validation issue wearing drift's clothing, and routing it to retraining trains the model on corrupt data.

## The remediation is asymmetric

| Signal           | What it means                              | What it triggers                      |
|------------------|--------------------------------------------|---------------------------------------|
| Validation issue | The data is wrong                          | Re-routing and rectification          |
| Drift            | The world changed and the data reflects it | Adaptation or retraining of the model |

This asymmetry is the practical point of the distinction. Collapsing both into "trigger investigation" loses it.

## Data-validation practices

Upstream names three data-validation best practices:

* Employ automated data-quality testing processes at each stage of the data pipeline.
* Re-route data that fails quality tests to a separate data store for diagnosis and resolution.
* Employ end-to-end data observability across freshness, distribution, volume, schema, and lineage.

"Each stage" means each transformation boundary from Bronze onward. It does not authorize assertions at Bronze landing, which stays a faithful copy of the source so that replay remains possible. See [data-tiers-and-pipeline-invariants.md](data-tiers-and-pipeline-invariants.md) for that rationale.

The re-routing practice is the same behavior the DataOps guidance describes as sending failed records to a malformed-data store.

## Drift monitoring

Understanding whether production data differs significantly from training-phase data matters, as does confirming that distribution information can be obtained for incoming data. Drift monitoring can indicate when changes occur and what their character is, such as abrupt versus gradual, and can guide an effective adaptation or retraining strategy.

Upstream questions worth asking include which kinds of drift have been experienced or are expected, whether a drift-detection strategy exists and matches those expectations, whether anomalies in input data raise warnings, and whether an adaptation strategy exists.

## What ML observability does and does not supply

The Observability in Machine Learning page frames observability across experimentation and production. It names model experimentation and tuning, production, training and retraining, performance over time and data drift, and data versioning. Observable targets include code, model, and data changes, evaluation metrics, parameters, dataset versions, source and notebook snapshots, run output and logs, and production service observability.

That page is **silent** on:

* Data validation entirely, including checks, failure conditions, and remediation
* The validation-versus-drift comparison
* Drift thresholds, alerting, ownership, and automatic remediation
* Distinct data-quality or feature-distribution monitoring as separate concerns
* Metric naming, instrument types, units, and schemas

Use it for lifecycle framing and drift awareness. Do not ground validation rules or quantitative controls in it.

## Which signals matter

This skill selects the signals worth observing for data and model work. Upstream supports monitoring infrastructure, pipelines, and data, and specifically names the malformed record store as an area needing data monitoring.

Signal categories worth selecting:

* Records failing the Bronze-to-Silver validation boundary
* Validation stage cost
* Pipeline replay frequency, as evidence that idempotency is exercised
* Model serving latency
* Feature or input distribution shift

## Ownership seam

Selecting a signal is not the same as naming it. Respect these boundaries.

| Concern                                                                | Owner                            | This skill's relationship                                    |
|------------------------------------------------------------------------|----------------------------------|--------------------------------------------------------------|
| Metric naming pattern, instrument types, units, cardinality discipline | `telemetry-foundations`          | Conform. Do not invent names, instruments, or units here.    |
| PII in emitted telemetry                                               | `telemetry-foundations` denylist | Obey. A denylisted field cannot become a dimension.          |
| Data sensitivity classification and DPIA thresholds                    | `privacy-standards`              | Read the classification. **Never decide what is sensitive.** |
| Which data and model signals matter                                    | This skill                       | Own.                                                         |

Drift monitoring invites high-cardinality dimensions such as per-column, per-feature, per-source, and per-record. Cardinality discipline belongs to `telemetry-foundations`; apply its rules rather than restating them here.

## Upstream silence on thresholds

No page in this source set prescribes a drift threshold, an alerting policy, an ownership model, or an automatic remediation trigger. Thresholds are engagement-specific. State that plainly rather than supplying a number that would read as playbook-backed.
