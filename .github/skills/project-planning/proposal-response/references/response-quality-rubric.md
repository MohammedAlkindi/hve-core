---
title: Proposal Response Quality Rubric
description: Advisory structural checks for traceable internal-review proposal responses without approval or release authority.
---

## Review Method

Evaluate every source question, claim, response, and unresolved item. Record failed checks as blocking IDs or qualifications in `RESPONSE_EVIDENCE_V1`; do not silently repair missing evidence.

## Advisory Checks

| Check               | Pass condition                                                                  | Failure behavior                                                           |
|---------------------|---------------------------------------------------------------------------------|----------------------------------------------------------------------------|
| Question fidelity   | Source wording, numbering, and reference are preserved                          | Correct the mapping or add an unresolved evidence item                     |
| Claim traceability  | Every factual claim cites approved evidence                                     | Mark the claim `unsupported` or `unreviewed` and do not present it as fact |
| Evidence fit        | Evidence directly supports the claim's scope and currency                       | Narrow and qualify the claim, or mark it `conflicting` or `stale`          |
| Ownership           | Business, product, and shared claims stay in their domains                      | Reclassify the claim or request the responsible contributor                |
| Response fidelity   | Draft text does not broaden its linked claims                                   | Narrow the response and retain qualifications                              |
| Decision visibility | Decisions, exceptions, estimates, and commitments name an unresolved human need | Add an unresolved item and block an unqualified response                   |
| Coverage integrity  | Counts and percentages match source-question states                             | Recalculate coverage from records                                          |
| Authority boundary  | Fixed internal-review and outside-scope markers are present                     | Set structural status to `not_ready` and remove authority-bearing language |

## Structural Readiness

Use `ready_for_internal_review` only when:

* every source question has a classified state;
* every drafted factual statement links to reviewed evidence;
* qualifications and unresolved items are visible beside affected responses;
* coverage values match the source-question records; and
* the fixed authority markers are present.

Otherwise use `not_ready` and apply the response contract's `blocking_ids` definition. `advisory_only` remains `true` in both states.

Structural readiness never means complete, correct, approved, authorized, externally usable, releasable, or submitted. A human review may still reject or revise a structurally ready draft.

## High-Risk Content

Require direct approved evidence or an explicit unresolved item for facts, measurements, credentials, customer references, security or compliance assertions, prices, schedules, staffing, service levels, exceptions, estimates, future commitments, and legal or commercial positions.

When sources conflict, preserve the competing references and ask the responsible human owner to resolve them. When evidence is stale, state its date or version and avoid current-tense assertions.

## Rendering Invariants

Every rendered draft identifies its source question and linked claims, preserves qualifications and unresolved items, and displays:

* `response_status: internal_review_draft`
* a deny-only `external_use_status`
* `release_decision: outside_skill_scope`

Do not hide unresolved items in footnotes or omit them from a polished response.
