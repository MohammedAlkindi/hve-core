---
title: ML checklists
description: The ML Fundamentals Checklist and ML Model Production Checklist structures, with their lifecycle scope and applicability caveats
---

## Sources

* Microsoft CSE Code-with-Engineering-Playbook, [ML Fundamentals Checklist](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-fundamentals-checklist/), MIT licensed.
* Microsoft CSE Code-with-Engineering-Playbook, [ML Model Production Checklist](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/ml-model-checklist/), MIT licensed.

Section headings and short item labels are preserved as structural identifiers. Item text is derived from the upstream checklists and in places stays close to upstream wording, because these are short factual requirements with little expressive range. Both pages are MIT licensed, which permits reproduction with notice; see `THIRD-PARTY-NOTICES` for the recorded notice and usage scope. Explanatory framing, the lifecycle caveat, and the routing table are repository-original.

## ML Fundamentals Checklist

Six sections covering engagement fundamentals.

### Data Quality and Governance

1. Data access is in place.
2. The dataset of interest carries labels.
3. Data quality has been evaluated.
4. Data lineage can be tracked.
5. Data origin is understood, along with any policy governing access to it.
6. Security and compliance requirements have been gathered.

### Feasibility Study

1. A feasibility study assessed whether the data supports the proposed tasks.
2. Exploratory data analysis was rigorous and covered data distribution.
3. Hypotheses were tested with enough evidence to support or reject an ML approach as feasible.
4. Return on investment was estimated and project risk analysed.
5. ML outputs and assets can integrate with the production system.
6. Recommendations for how to proceed are documented.

### Evaluation and Metrics

1. How performance will be measured is defined clearly.
2. The evaluation metrics connect to the success criteria.
3. The metrics are computable from the datasets available.
4. The evaluation flow applies across every model version.
5. Evaluation code is unit-tested and peer-reviewed across the team.
6. The evaluation flow supports downstream results analysis and error analysis.

### Model Baseline

1. A well-defined baseline model exists and its performance is measured.
2. Other ML models can be compared against that baseline.

### Experimentation setup

1. Train and test datasets are well defined and labelled.
2. Experiments are reproducible and logged in an environment every data scientist can reach, keeping iteration fast.
3. The experiments and hypotheses to test are defined.
4. Experiment results are documented.
5. Model hyperparameters are tuned systematically.
6. Candidate models are compared using the same performance metrics and consistent datasets.

### Production

1. The model readiness checklist has been reviewed.
2. Model reviews were performed, covering model debugging, the training and evaluation approaches, and model performance.
3. An inferencing data pipeline exists and carries end-to-end tests.
4. SLA requirements for the models are gathered and documented.
5. Data feeds and model output are monitored.
6. A consistent schema is used across the system, with expected input and output defined for each pipeline component, covering data processing as well as models.
7. Responsible AI has been reviewed.

## ML Model Production Checklist

### Lifecycle scope and caveat

Read this before applying the checklist. Upstream scopes it to teams that have **already built or trained** a model and are now considering putting it into production. Its stated purposes are confirming the model is ready for production before moving to scoring, and preparing a production plan.

Upstream also states that there may be scenarios where it is not possible to check every item, and advises going through all items and making informed decisions based on the specific use case.

Treat it as a structured readiness review with a lifecycle precondition, **not** as an unconditional gate.

### Checklist

Each item states the question it asks.

1. Whether a well-defined baseline exists, and whether the model beats it.
2. Whether ML performance metrics are defined for training and for scoring.
3. Whether the model has been benchmarked.
4. Whether ground truth can be obtained or inferred once in production.
5. Whether the data distribution across training, testing, and validation sets has been analysed.
6. Whether goals and hard limits for performance, prediction speed, and cost are established, so trade-offs can be weighed against them.
7. How the model will integrate with other systems, and what impact that carries.
8. How incoming data quality will be monitored.
9. How drift in data characteristics will be monitored.
10. How performance will be monitored.
11. Whether ethical concerns have been considered.

The same page expands each item under the grouping "Will Your Model Performance be Different in Production than During the Training Phase", using matching subheadings.

## Routing

Some items are owned elsewhere.

| Items                                                                          | Route to                                                                                           |
|--------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Incoming data quality monitoring, drift monitoring, and performance monitoring | `ds-dataops`, which carries the validation-versus-drift distinction and its asymmetric remediation |
| Ethical concerns                                                               | `rai-planner`                                                                                      |
| Experiment setup, tracking, and evaluation flow                                | [model-experimentation.md](model-experimentation.md)                                               |

## A distinction worth preserving

The ML Fundamentals Checklist names reproducible, logged experiments. That is **experiment reproducibility**, which is not the same as **pipeline replayability**. Neither checklist states a pipeline-replayability requirement, and neither names a data-tiering model. Collapsing the two loses technical precision; pipeline replay semantics belong to `ds-dataops`.
