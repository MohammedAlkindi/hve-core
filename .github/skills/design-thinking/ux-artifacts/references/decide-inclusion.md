---
title: "UX artifact mode: Decide inclusion"
description: Record concept-stage exclusion risks, cognitive and language demands, alternatives, capability assumptions, and research coverage gaps.
---

# Decide inclusion

Use this mode before technical implementation to make inclusion choices visible. It replaces generic conformance checklists with concept-stage reasoning about who may be excluded and what the experience demands.

## Inputs

* Concept, flow, or journey being assessed
* Represented users and access-needs evidence
* Tasks and information the experience requires people to perceive, remember, understand, or do
* Known alternatives and research coverage

## Output body

After the common evidence sections, write:

```markdown
## Inclusion Decisions

| Decision area                         | Current decision | Who may be excluded         | Basis and source                             | Alternative or mitigation | Status                  |
|---------------------------------------|------------------|-----------------------------|----------------------------------------------|---------------------------|-------------------------|
| Memory and attention                  | <decision>       | <affected users or Unknown> | <Observed, Reported, or Assumed plus source> | <alternative>             | <decided or unresolved> |
| Language and comprehension            | <decision>       | <affected users or Unknown> | <basis>                                      | <alternative>             | <decided or unresolved> |
| Sensory assumptions                   | <decision>       | <affected users or Unknown> | <basis>                                      | <alternative>             | <decided or unresolved> |
| Motor and interaction assumptions     | <decision>       | <affected users or Unknown> | <basis>                                      | <alternative>             | <decided or unresolved> |
| Environmental and situational demands | <decision>       | <affected users or Unknown> | <basis>                                      | <alternative>             | <decided or unresolved> |

## Research Coverage

* People with relevant access needs included: <supported statement or None known>
* Coverage gaps: <gaps>
* Participant accommodations or co-design needs: <known needs or Unresolved>

## Technical Accessibility Handoff

* Conformance questions for `accessibility`: <questions or None yet>
* Surface-specific meaning that may need a Design Intent Record: <decision or None>
```

## Responsibility boundary

This asset owns concept-stage decisions. It does not define or restate WCAG thresholds, keyboard behavior, screen-reader implementation, contrast values, target sizes, zoom requirements, ARIA patterns, or COGA patterns.

Route technical conformance, COGA guidance, runtime validation, and accessibility review to `accessibility`. A Design Intent Record remains the authoritative home for a surface-specific decision that must be checkable in a build.

## Completion conditions

* The artifact names concrete capability assumptions and their evidence strength.
* Alternatives are considered where the current concept excludes someone.
* Research coverage and missing practitioner or participant evidence stay explicit.
* Technical questions are handed off without a duplicated checklist.

## Stop conditions

Stop when the task is technical conformance rather than concept-stage inclusion. Return the current asset pointer and name `accessibility` as the appropriate capability without invoking it.
