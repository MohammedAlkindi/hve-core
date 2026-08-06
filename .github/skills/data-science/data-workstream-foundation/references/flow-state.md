---
title: Data Workstream Flow-State Protocol
description: Interruption gates, durable-write scanning, resume announcements, and completion choices for focused data-workstream coaching
---

# Data Workstream Flow-State Protocol

## Purpose

Keep the coaching conversation focused while interrupting at the few moments
where user authority, durable safety, or lifecycle integrity requires it.

## Interrupt only for

* Initial project and job selection
* An ambiguous or proposed job transition
* A hard gate in a bounded job
* A privacy or data-sensitivity threshold crossing
* A proposed durable customer-artifact write, before the write occurs
* State reconstruction confirmation
* Session closure confirmation

Do not interrupt for reference loading, ordinary episodic work in progress, or
catalog enrichment that has not reached a durable write or sensitivity gate.

## Durable-write gate

Before creating or changing any durable customer artifact:

1. Confirm the destination is inside the customer's repository. Suggest
   `docs/data/` when no convention exists, but record only a user-confirmed
   output root.
2. Assemble the exact proposed content in memory or a contained temporary
   representation.
3. Run `adr-author`, the architecture-decision authoring skill that owns the
   reusable sensitive-content scanner, in data mode. Add a caller-confirmed
   denylist when one applies.
4. If a high-confidence finding exists, do not write. Report only the category
   and masked preview, ask the user to redact the source content, then rescan.
5. If warning findings exist without a high-confidence finding, surface them
   for review and allow the user to decide whether to continue.
6. Write only the scanned content. Record the artifact and scan disposition in
   session state after the write succeeds.

If the data-mode scanner capability is unavailable, stop the customer-artifact
write and state the missing dependency. Session-state updates may record the
blocked attempt, but they are not a substitute for the scan.

## Resume behavior

On every resume, announce current state before asking a question. Include the
active foreground job, bounded phase and gate state when applicable, paused
bounded work, active continuous context, and completed work that will not be
re-entered without an explicit request.

## Completion behavior

When a job or episodic invocation completes:

1. Name what finished and what it connects to.
2. Persist the artifact, invocation, or terminal bounded state.
3. Surface active continuous and paused bounded work.
4. Offer choices such as close, resume, enrich, revise explicitly, or select a
   different job.

Do not choose or start the next job for the user.

## Provenance

This flow-state protocol is repository-original guidance licensed under
CC BY 4.0. It does not reproduce or summarize an external standard.
