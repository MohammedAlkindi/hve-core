---
title: Model experimentation conventions
description: CSE model-experimentation practice areas covering virtual environments, source and folder structure, experiment tracking, dataset and model abstractions, and model evaluation
---

## Source

Microsoft CSE Code-with-Engineering-Playbook, [Model Experimentation](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/model-experimentation/), documentation licensed CC BY 4.0. Content below is derived from that page and has been changed: it follows the five practice areas in upstream order, stays close to or matches upstream wording in most passages, and condenses the challenges narrative and the abstraction discussion. The notice recorded in `THIRD-PARTY-NOTICES` carries the attribution CC BY 4.0 requires. Tool and file names are preserved as identifiers.

## Why a semi-structured process

Model experimentation carries uncertainty about both expected results and future operationalization. The upstream response is a semi-structured process that balances engineering and research practice against rapid model and data exploration.

Five stated goals:

| Goal               | What it means                                                             |
|--------------------|---------------------------------------------------------------------------|
| Performance        | Find the best performing solution.                                        |
| Operationalization | Keep an eye toward production so operationalization stays feasible.       |
| Code quality       | Maintain code and artifact quality.                                       |
| Reproducibility    | Keep research active by allowing experiment tracking and reproducibility. |
| Collaboration      | Foster collaboration and joint work across the team.                      |

The corresponding challenges are worth naming, because they explain the conventions: trial and error is hard to plan and estimate; teams want to fail fast and stay quick and dirty; collaboration and brainstorming need a shared process; non-production research code still needs quality; and switching approaches can significantly affect operationalization, such as GPU versus CPU, batch versus online, parallel versus sequential, and runtime environments.

## The five practice areas

### Virtual environments

In languages like Python and R, always use virtual environments. They support reproducibility, collaboration, and productization, and they keep local development consistent with compute resources. Configuration files let the code be built from source consistently.

Framework choice depends on the complexity of the development environment and the ease of use of the framework. Upstream names three options: `venv`, included with Python and easiest to use but lacking dependency management; `Conda`, a popular package, dependency, and environment manager supporting multiple stacks and multiple versions of the same environment, with its own package repository; and `Poetry`, which manages dependencies through `pyproject.toml` and lock files and produces robust, reproducible environments where dependency issues are common.

**HVE Core substitution.** This repository uses `uv`. That is a repository convention, not an upstream recommendation. When advising a team that is still choosing, preserve upstream's selection rationale rather than presenting `uv` as the playbook answer.

Expected outcomes:

1. Documentation describing how to create the selected virtual environment and how to install dependencies.
2. Environment configuration files committed where applicable, such as `requirements.txt`, `environment.yml`, or `pyproject.toml`.

Stated benefits: productization, collaboration, reproducibility.

### Source control and folder or package structure

Applied ML projects contain source code, notebooks, devops scripts, documentation, scientific resources, datasets, and more. Agree on a folder structure to keep resources tidy. Consider a generic project structure containing folders such as `data`, `src`, `docs`, and `notebooks`, or adopt a popular structure such as CookieCutter Data Science.

Apply source control to enable collaboration, versioning, code review, traceability, and backup. In data science projects, source control is used for code; storing and versioning other artifacts such as data and scientific literature is decided per scenario.

Expected outcomes:

* A defined folder structure for all users, pushed to the repository.
* A `.gitignore` file determining which folders sync with git and which stay local.
* An explicit decision on how notebooks are stored and versioned. `nbstripout` is named upstream for stripping output from Jupyter notebooks.

Stated benefits: collaboration, reproducibility, code quality.

### Experiment tracking

Experiment tracking tools let data scientists and researchers keep track of previous experiments, both to understand the experimentation process and to reproduce experiments or models.

Frameworks differ in what metadata they collect and how they support comparison and analysis. Upstream notes that some require a deployment while others are SaaS, and names MLflow on Databricks and Azure ML Experimentation as commonly used in ISE.

Expected outcomes:

1. Decide on an experiment tracking framework.
2. Ensure it is accessible to all users.
3. Document set-up on local environments.
4. Define datasets and evaluation so that all experiments can be compared. **Consistency across datasets and evaluation is paramount for experiment comparison.**
5. Ensure full reproducibility by tracking all required details: **dataset names and versions**, parameters, code, and environment. Tracking a dataset name alone is a labelling practice, not reproducibility.

Stated benefits: model performance, reproducibility, collaboration, code quality.

### Datasets and models abstractions

Creating abstractions for building blocks such as datasets, models, and evaluators allows new logic to enter the experimentation pipeline while the agreed experimentation flow stays intact. These abstractions can be built with mechanisms such as object-oriented abstract classes; upstream points to scikit-learn's guidance on creating API-compatible estimators and PyTorch's guidance on extending the abstract dataset class.

Expected outcomes:

1. Different building blocks have defined APIs allowing them to be replaced or extended.
2. Replacing building blocks does not break the original experimentation flow.
3. Mock building blocks are used for unit tests.
4. APIs and mocks are shared with the engineering teams for integration with other modules.

Stated benefits: collaboration, code quality, reproducibility, operationalization, model performance.

### Model evaluation

When deciding on evaluation of the model or process, upstream supplies a checklist:

* Evaluation logic is approved by all stakeholders.
* The relationship between evaluation logic and business KPIs is analyzed and decided.
* The evaluation flow is applicable for all present and future models, meaning it does not assume some prediction structure or method-specific process.
* Evaluation code is unit-tested and reviewed by all team members.
* The evaluation flow facilitates further results and error analysis.

Evaluation development outcomes:

1. The evaluation strategy is agreed by all stakeholders.
2. Research and discussion on various evaluation methods and metrics is documented.
3. The code holding evaluation logic and data structures is reviewed and tested.
4. Documentation on how to apply evaluation is reviewed.
5. Performance metrics are automatically tracked into the experiment tracker.

Stated benefits: model performance, code quality, collaboration, reproducibility.

## Related guidance

The model-evaluation points overlap closely with the Evaluation and Metrics section of the ML Fundamentals Checklist. Cite one and cross-reference rather than restating both. See [ml-checklists.md](ml-checklists.md).

Unit-testing evaluation code is a testing concern; technique and mocking boundaries live in the `ds-dataops` skill.
