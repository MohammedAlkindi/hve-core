---
title: Proposal Response Claim and Evidence Model
description: Stable question, claim, evidence, response, coverage, and authority semantics for RESPONSE_EVIDENCE_V1.
---

## Record Identity

Assign IDs in source encounter order and preserve them across operations:

* `SQ-001`: source question
* `CLM-001`: claim
* `RSP-001`: drafted response
* `UNR-001`: unresolved item

Never renumber existing records when new material is added. Link records by ID rather than by list position.

## Source Questions

Each source question contains:

```yaml
id: SQ-001
source_ref: questionnaire.xlsx#Q12
text: Describe the service availability commitment.
classification: business | product | shared | legal_or_commercial | unknown
response_state: unaddressed | addressed | qualified | unresolved
claim_ids: []
```

`legal_or_commercial` identifies a decision boundary; it does not authorize the skill to answer. Preserve source numbering and wording when available.

## Claims

Each claim contains:

```yaml
id: CLM-001
owner_domain: business | product | shared
statement: The service target is defined in NFR-014.
source_question_ids: [SQ-001]
evidence_refs: [approved-prd.md#NFR-014]
evidence_review: supported | partially_supported | unsupported | conflicting | stale | unreviewed
qualification: null
```

A claim is `supported` only when approved evidence directly supports its wording. Use `partially_supported` when evidence supports a narrower statement and put that limitation in `qualification`. Estimates and future commitments remain `unreviewed` until the responsible human owner confirms them, even when a draft artifact mentions them.

## Responses

Draft responses contain:

```yaml
id: RSP-001
source_question_id: SQ-001
text: The approved product requirement defines the availability target in NFR-014.
claim_ids: [CLM-001]
qualifications: []
unresolved_item_ids: []
```

Response text may synthesize supported claims but may not broaden them. Keep qualifications and unresolved IDs visible for reviewers.

## Unresolved Items

Use `evidence`, `decision`, `exception`, or `conflict` as the unresolved type. Record a concise description, affected question and claim IDs, the human ownership domain, and the smallest clearing action. Do not encode a decision outcome.

```yaml
id: UNR-001
type: decision
description: A commercial owner must decide whether the requested term is acceptable.
source_question_ids: [SQ-004]
claim_ids: []
owner_domain: business
clearing_action: Obtain the commercial owner's decision and approved source record.
```

## Coverage

Calculate coverage from source-question records:

* `question_count`: all normalized source questions
* `addressed_count`: questions with `response_state: addressed`
* `qualified_count`: questions with `response_state: qualified`
* `unresolved_count`: questions with `response_state: unresolved`
* `addressed_percent`: `addressed_count / question_count * 100`, or `0.0` when no questions exist

Qualified questions are not included in `addressed_count`. Coverage measures response structure, not correctness, approval, or permission for external use.

## Fixed Authority Semantics

`response_status` is always `internal_review_draft`. `external_use_status` is either `internal_review_only` or `external_use_prohibited`; both values deny external use. `release_decision` is always `outside_skill_scope`.

No record may represent approval, authorization, permission, submission, release, approver identity, or a binding commitment. Human decisions appear only as unresolved needs or approved source evidence supplied after the decision occurred outside this skill.
