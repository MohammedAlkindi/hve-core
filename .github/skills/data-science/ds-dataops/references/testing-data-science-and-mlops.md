---
title: Testing data science and MLOps code
description: The five testable operation categories, their concrete pytest technique, and where mocking stops in each
---

## Source

Microsoft CSE Code-with-Engineering-Playbook, [Testing Data Science and MLOps Code](https://microsoft.github.io/code-with-engineering-playbook/ml-and-ai-projects/testing-data-science-and-mlops-code/), documentation licensed CC BY 4.0. Content below is derived from that page and has been changed. The category and mocking-boundary table and the ML unit-test scope guard stay close to or match upstream wording; other passages are paraphrased. `THIRD-PARTY-NOTICES` carries the attribution CC BY 4.0 requires. pytest API names are preserved as identifiers, and upstream code examples are described rather than copied.

## Approach

Testing MLOps and data-science code follows the same principles as any other software project. Some scenarios look harder to test, so start with a test design session focused on inputs, outputs, exceptions, and the behavior of data transformations. Designing tests first forces a more modular style in which each function has one purpose and shared functionality is extracted.

Upstream enumerates five common operations:

* Saving and loading data
* Transforming data
* Model load or predict
* Data validation
* Model testing

## Category, technique, and mocking boundary

| Category                                | What is under test                                                              | Technique                                                                                 | Where mocking stops                                                                                                                                                                                                                                                                                                            |
|-----------------------------------------|---------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Saving and loading data                 | The function's own branching and parameter passing, not the third-party library | Patch the module-scoped references and assert call arguments and call counts              | **Mock the I/O boundary.** Mock `isfile` and `read_csv` as referenced inside the module under test. Mock only the specific functions that module references; others run normally.                                                                                                                                              |
| Saving and loading data, shared samples | Reuse of one sample across several tests                                        | `pytest.fixture` returning the sample, passed as a test parameter                         | No additional mocking. Sample data stays hard-coded and no larger than the tests require.                                                                                                                                                                                                                                      |
| Transforming data                       | Fixed input to fixed output, one verification per test                          | Separate tests per property; `pytest.mark.parametrize` for input matrices                 | **No mocking.** Transformation logic is exercised directly. This is why transformation code must be separated from data access. When a function mixes the two, recommend splitting it before writing transformation tests. Testing a reshape through a mocked `read_csv` satisfies neither category and defeats the invariant. |
| Model load or predict                   | Code paths around model load and prediction                                     | Mock load and predict; `pytest.mark.longrunning` to segregate smoke and integration tests | **Mock the model boundary** exactly as file access is mocked. Real model loads belong behind the mark, outside the unit loop.                                                                                                                                                                                                  |
| Data validation                         | Pipeline robustness against bad input                                           | Test cases for no data supplied, unexpected format, null values, and outliers             | No stated boundary. Inputs are constructed, not mocked.                                                                                                                                                                                                                                                                        |
| Model testing                           | Model robustness and subgroup behavior                                          | Adversarial and boundary tests; verify accuracy for under-represented classes             | Outside the unit-test boundary entirely. Occurs during training, debugging, and validation.                                                                                                                                                                                                                                    |

## Saving and loading data

There is no need to test the third-party functions themselves; leave `read_csv` and `isfile` to the pandas and os maintainers. Test only the function's own logic: that it loads when the file exists with the correct index column, that it does not load when the file is absent, and that it returns the expected result.

Supplying real sample files makes the same test pass on one machine and fail on a build server. Mocking `isfile` and `read_csv` removes that dependency, so no files are needed in the repository and the test behaves identically anywhere.

## Transforming data

For cleaning and transformation, test fixed input against fixed output and limit each test to one verification. For example, write one test for output shape and a separate test for padding behavior. Use `pytest.mark.parametrize` to drive different input and expected-output combinations automatically.

## Model load or predict

When unit testing, mock model load and model predictions the same way file access is mocked. Loading a real model for smoke or integration tests is legitimate but slower, so those tests must be separable from the unit loop. Upstream's mechanism is the `pytest.mark.longrunning` mark, with the unit loop run as `pytest -v -m "not longrunning"`.

## Scope guard: ML unit tests check code quality

**ML unit tests are not intended to check the accuracy or performance of a model.** They are code-quality checks. The two diagnostic questions are:

* Does the model accept correctly shaped inputs and produce correctly shaped outputs?
* Do the weights of the model update when `fit` runs?

Because of this, ML model tests deliberately depart from strict unit-testing practice: **not all outside calls are mocked.** Upstream describes them as closer to a narrow integration test and accepts that trade-off. The stated benefit is preventing a poorly configured model from spending hours in training while still producing poor results. Without the non-mocking clause the guidance reads as an inconsistency rather than a deliberate trade-off.

Upstream gives three implementation examples for deep-learning models:

* Build the model and compare the input-layer shape to example source data, then compare the output-layer shape to the expected output.
* Record each layer's weights, run a single training epoch on a dummy dataset, and check only that the values changed.
* Train on a dummy dataset for a single epoch and validate with dummy data, checking only that the prediction is correctly formatted. This model will not be accurate.

## Data validation

Include data-validation test cases in unit testing: no data supplied, data not in the expected format, data containing null values, and outliers. These confirm the data-processing pipeline is robust.

## Model testing

Beyond unit testing, models can be tested, debugged, and validated during training. Two options are named: adversarial and boundary tests to increase robustness, and verifying accuracy for under-represented classes.

## Relationship to the DataOps invariants

These five categories are how a team satisfies an invariant the DataOps guidance already asserts: transformation code must be separable from data-access code so unit tests can target transformation logic. See [data-tiers-and-pipeline-invariants.md](data-tiers-and-pipeline-invariants.md).
