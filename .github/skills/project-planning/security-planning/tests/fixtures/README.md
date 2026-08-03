---
title: TM7 test fixtures
description: Provenance, licensing, and maintenance rules for the TM7 test fixtures.
ms.date: 2026-08-02
ms.topic: reference
---

# TM7 test fixtures

Read-only inputs for the TM7 test suite. Nothing here is generated output, and
the generation runtime never writes to this directory.

## Provenance

Only `tmt-reference.tm7` is upstream-derived. The other fixtures were compared
against every `.tm7` in the upstream repository and match none of them.

* `tmt-reference.tm7` comes from `gholliday/tm7-cli`, `samples/demo.tm7`, and
  is MIT licensed. See the details below.
* `tmt-reference-threats.tm7` is first-party, authored for this repository.
* `expected.tm7` and `tmp-sample.tm7` are first-party pinned golden files.
* `comprehensive-spec.yaml` is first-party, copied from
  `docs/planning/threat-models/hve-core-comprehensive.yaml`.

### tmt-reference.tm7

* Upstream repository: <https://github.com/gholliday/tm7-cli>
* Upstream file: `samples/demo.tm7`
* Upstream revision: `715954acc5b0a42386d3c0a3a42cdf35c5f41cfc`
* Upstream license: MIT
* Local SHA-256:
  `a53a1510859b7f5f1958c5c1d665fdb8107fa9cf62a39050ce1baad6418a8b6f`
* Upstream SHA-256:
  `8c01c931b70388915113bc1b814424ea3400913088af01ce26e62d945b784dc3`

The local copy is not byte-identical to upstream. Three LF line breaks inside
`<b:string>` elements are stored as CRLF, which is the only difference and
accounts for the 3-byte size delta: upstream is 1,212,739 bytes and the local
copy is 1,212,742 bytes. With whitespace normalized, both files are
byte-identical at 1,190,991 bytes. The difference is consistent with a Windows
checkout applying line-ending translation rather than an edit to the model.

The embedded knowledge base in this fixture originates from the Microsoft
threat-modeling templates (`default.tb7`), which are MIT licensed. Attribution
for both sources is recorded in the repository `THIRD-PARTY-NOTICES`.

## Maintenance

Fixture bytes are load-bearing. Tests assert on serializer member order and
document structure, so re-saving a fixture through the Threat Modeling Tool
changes results even when the model is semantically unchanged. Replace a
fixture only with a recorded reason, and update the checksums above in the
same change.

`comprehensive-spec.yaml` duplicates the repository threat model. Tests assert
on its structure, including its 80 threats, its per-surface trust zones, and
identifiers such as `AX-1`, `flow-04`, and `flow-21`. Keep the two copies
aligned when the repository threat model changes, or the layout and population
tests will drift from the documented model.
