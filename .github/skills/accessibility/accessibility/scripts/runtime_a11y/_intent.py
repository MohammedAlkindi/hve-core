# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

"""Translate runtime probe results into a Design Intent verification artifact.

A Design Intent Record is human-authored, committed source that states what a
surface must convey and names the check that settles each claim. The runtime
harness reports findings per criterion. Neither knows about the other. This
module joins them and emits the verification sidecar the design-intent contract
defines, so that a declared intent becomes something a build can check.

The adapter never reads or writes human-authored content. It computes the
digest of the record it describes so a consumer can detect that results have
gone stale against a record that changed after the run.
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import yaml

from runtime_a11y._errors import EXIT_USAGE, ScriptError

SCHEMA_VERSION = "1.0"
ASSERTED_BY = "runtime_a11y intent adapter"

# EARL-derived outcome vocabulary, ordered worst first. An expectation is one
# claim over one or more criteria, so the worst criterion outcome governs.
_OUTCOME_PRECEDENCE = ("failed", "cantTell", "passed")

_STATUS_TO_OUTCOME = {
    "pass": "passed",
    "fail": "failed",
    "candidate": "cantTell",
    # A partial probe settled some but not all of what it examined. It is
    # evidence without a verdict, so it maps to cantTell explicitly rather
    # than reaching the default and looking like a deliberate mapping.
    "partial": "cantTell",
}

_CUSTOM_ASSERT = "custom"


def compute_intent_digest(raw_text: str) -> str:
    """Return the contract digest for an authored record's raw text.

    Line endings are normalized to LF so a CRLF checkout does not report false
    staleness. Callers must pass BOM-stripped text.
    """
    normalized = raw_text.replace("\r\n", "\n")
    digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
    return f"sha256:{digest}"


def read_record_text(record_path: Path) -> str:
    """Read an authored record as text, stripping any byte-order mark."""
    try:
        return record_path.read_text(encoding="utf-8-sig")
    except OSError as exc:
        raise ScriptError(
            f"Design intent record is unreadable: {record_path}", EXIT_USAGE
        ) from exc


def parse_record(raw_text: str, record_path: Path) -> dict[str, Any]:
    """Parse an authored record, requiring a YAML mapping at the root."""
    try:
        record = yaml.safe_load(raw_text)
    except yaml.YAMLError as exc:
        raise ScriptError(
            f"Design intent record is not valid YAML: {record_path}"
        ) from exc
    if not isinstance(record, dict):
        raise ScriptError(
            f"Design intent record must parse to a mapping: {record_path}"
        )
    return record


def load_results(results_path: Path) -> dict[str, Any]:
    """Load a harness results document, requiring a JSON object at the root."""
    try:
        payload = json.loads(results_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ScriptError(
            f"Results document is unreadable: {results_path}", EXIT_USAGE
        ) from exc
    except json.JSONDecodeError as exc:
        raise ScriptError(
            f"Results document is not valid JSON: {results_path}"
        ) from exc
    if not isinstance(payload, dict):
        raise ScriptError(f"Results document must be a JSON object: {results_path}")
    return payload


def split_criterion_reference(reference: str) -> tuple[str, str]:
    """Split a 'framework:criterionId' reference on its FIRST colon.

    Criterion ids may themselves contain colons, so only the leading segment is
    the framework. Splitting on every colon would silently drop a framework.
    """
    framework, separator, criterion = reference.partition(":")
    if not separator or not framework or not criterion:
        raise ScriptError(
            f"Criterion reference must be 'framework:criterionId': {reference}"
        )
    return framework, criterion


def _matching_rows(
    rows: Iterable[dict[str, Any]],
    surface_id: str,
    state: str,
    probe_id: str,
    criteria: set[tuple[str, str]],
) -> list[dict[str, Any]]:
    """Select result rows that answer one expectation."""
    matches = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        if row.get("surfaceId") != surface_id or row.get("state") != state:
            continue
        if row.get("probeId") != probe_id:
            continue
        key = (str(row.get("framework", "")), str(row.get("criterionId", "")))
        if key in criteria:
            matches.append(row)
    return matches


def _worst_outcome(rows: list[dict[str, Any]]) -> str:
    """Reduce matched rows to one outcome, worst result winning."""
    outcomes = {
        _STATUS_TO_OUTCOME.get(str(row.get("status", "")), "cantTell") for row in rows
    }
    for candidate in _OUTCOME_PRECEDENCE:
        if candidate in outcomes:
            return candidate
    return "cantTell"


def build_assertions(
    record: dict[str, Any], results: dict[str, Any]
) -> list[dict[str, Any]]:
    """Build exactly one assertion per authored expectation.

    An expectation the run did not cover reports 'untested' rather than being
    omitted, so a missing check is visible instead of silently absent.
    """
    surface_id = str(record.get("surfaceId", ""))
    rows = results.get("results")
    rows = rows if isinstance(rows, list) else []

    assertions: list[dict[str, Any]] = []
    for intent in _iter_intents(record):
        intent_id = intent.get("id")
        binding = intent.get("binding")
        if binding is not None and not isinstance(binding, dict):
            raise ScriptError(
                f"Intent '{intent_id}' binding must be a mapping, got "
                f"{type(binding).__name__}"
            )
        state = str((binding or {}).get("state", "default"))
        for expectation in _iter_expectations(intent):
            # Validate the blocking flag before anything is written. Deferring
            # it to evaluate_blocking would raise only after the artifact
            # exists, leaving a misleading file behind.
            is_blocking(expectation)
            assertions.append(
                _build_assertion(intent_id, expectation, surface_id, state, rows)
            )
    return assertions


def _iter_intents(record: dict[str, Any]) -> list[dict[str, Any]]:
    """Return the record's intents, rejecting a malformed nested shape.

    A record whose 'intents' is a list of strings would otherwise raise
    AttributeError deep in the walk. Failing here reports the documented
    typed error with the offending shape named.
    """
    intents = record.get("intents")
    if intents is None:
        return []
    if not isinstance(intents, list):
        raise ScriptError(
            f"Record 'intents' must be a list, got {type(intents).__name__}"
        )
    for entry in intents:
        if not isinstance(entry, dict):
            raise ScriptError(
                f"Each intent must be a mapping, got {type(entry).__name__}"
            )
    return intents


def _iter_expectations(intent: dict[str, Any]) -> list[dict[str, Any]]:
    """Return one intent's expectations, rejecting a malformed nested shape."""
    expectations = intent.get("expectations")
    if expectations is None:
        return []
    if not isinstance(expectations, list):
        raise ScriptError(
            f"Intent '{intent.get('id')}' expectations must be a list, got "
            f"{type(expectations).__name__}"
        )
    for entry in expectations:
        if not isinstance(entry, dict):
            raise ScriptError(
                f"Each expectation of intent '{intent.get('id')}' must be a "
                f"mapping, got {type(entry).__name__}"
            )
    return expectations


def is_blocking(expectation: dict[str, Any]) -> bool:
    """Return one expectation's blocking flag, rejecting a non-boolean value.

    A quoted 'true' is not a boolean. Coercing it would silently disable the
    gate for an expectation the author marked blocking, so it fails closed.
    """
    blocking = expectation.get("blocking", False)
    if blocking is None:
        return False
    if not isinstance(blocking, bool):
        raise ScriptError(
            f"Expectation '{expectation.get('id')}' has a non-boolean "
            f"'blocking' value {blocking!r}; use an unquoted true or false"
        )
    return blocking


def _build_assertion(
    intent_id: Any,
    expectation: dict[str, Any],
    surface_id: str,
    state: str,
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    """Resolve one authored expectation against the run's result rows."""
    expectation_id = expectation.get("id")
    assert_id = str(expectation.get("assert", ""))

    if assert_id == _CUSTOM_ASSERT:
        # A custom assertion names no registered implementation, so no probe
        # result can settle it. The contract already holds it non-blocking.
        return {
            "intentId": intent_id,
            "expectationId": expectation_id,
            "outcome": "untested",
            "mode": "manual",
            "pointer": None,
            "info": (
                "Custom assertion has no registered runtime implementation; "
                "resolve it through human review."
            ),
        }

    criteria = {
        split_criterion_reference(str(reference))
        for reference in expectation.get("criteria") or []
    }
    matches = _matching_rows(rows, surface_id, state, assert_id, criteria)

    if not matches:
        return {
            "intentId": intent_id,
            "expectationId": expectation_id,
            "outcome": "untested",
            "mode": "automatic",
            "pointer": None,
            "info": (
                f"No result row for probe '{assert_id}' on surface "
                f"'{surface_id}' state '{state}' matched this expectation's "
                "criteria."
            ),
        }

    outcome = _worst_outcome(matches)
    covered = {
        (str(row.get("framework", "")), str(row.get("criterionId", "")))
        for row in matches
    }
    uncovered = criteria - covered
    info = None
    if uncovered:
        # Some declared criterion was never evaluated. The expectation is one
        # claim over all of its criteria, so an unevaluated criterion means the
        # claim is unsettled no matter how the evaluated ones resolved. Without
        # this, a partially covered expectation resolves 'passed'.
        missing = ", ".join(sorted(f"{f}:{c}" for f, c in uncovered))
        if outcome != "failed":
            outcome = "cantTell"
        info = (
            f"Probe '{assert_id}' did not evaluate every declared criterion "
            f"for this expectation; missing: {missing}."
        )
    elif outcome == "cantTell":
        info = (
            f"Probe '{assert_id}' gathered evidence but did not settle every "
            "criterion for this expectation."
        )
    return {
        "intentId": intent_id,
        "expectationId": expectation_id,
        "outcome": outcome,
        "mode": "automatic",
        "pointer": None,
        "info": info,
    }


def build_verification(
    record: dict[str, Any],
    raw_text: str,
    results: dict[str, Any],
    timestamp: str | None = None,
) -> dict[str, Any]:
    """Build the complete verification artifact for one authored record."""
    generated_at = timestamp or datetime.now(timezone.utc).isoformat()
    assertions = build_assertions(record, results)
    _validate_identifiers(assertions)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "surfaceId": record.get("surfaceId"),
        "intentDigest": compute_intent_digest(raw_text),
        "assertedBy": ASSERTED_BY,
        "timestamp": generated_at,
        "assertions": assertions,
    }


def _validate_identifiers(assertions: list[dict[str, Any]]) -> None:
    """Reject missing or duplicated assertion identity before anything writes.

    Downstream consumers key on the (intentId, expectationId) pair. A null or
    duplicated pair produces an artifact that looks well formed while silently
    conflating two claims, so it fails before the file is emitted rather than
    after a consumer has trusted it.
    """
    seen: set[tuple[Any, Any]] = set()
    for item in assertions:
        intent_id = item["intentId"]
        expectation_id = item["expectationId"]
        if not intent_id or not expectation_id:
            raise ScriptError(
                "Every intent and expectation needs an id; found "
                f"intentId={intent_id!r} expectationId={expectation_id!r}"
            )
        key = (intent_id, expectation_id)
        if key in seen:
            raise ScriptError(
                f"Duplicate expectation id '{expectation_id}' within intent "
                f"'{intent_id}'; ids must be unique inside their intent"
            )
        seen.add(key)


BLOCKING_OK = "ok"
BLOCKING_FAILED = "failed"
BLOCKING_UNCOVERED = "uncovered"


def _effective_outcome(expectation: dict[str, Any], observed: str) -> str:
    """Return the gate-level outcome for one expectation.

    The artifact records the observed outcome only. The exit code is the
    consumer-facing signal, so it applies the contract's effective outcome:
    'override.outcome' when a human authored one, otherwise the observed value.
    Without this, a blocking expectation settled by a documented human review
    on a platform no probe can drive would gate forever.
    """
    override = expectation.get("override")
    if isinstance(override, dict):
        outcome = override.get("outcome")
        if isinstance(outcome, str) and outcome:
            return outcome
    return observed


def evaluate_blocking(record: dict[str, Any], assertions: list[dict[str, Any]]) -> str:
    """Classify the record's blocking expectations against their assertions.

    Returns BLOCKING_FAILED when a blocking expectation resolved 'failed',
    BLOCKING_UNCOVERED when one was never evaluated, and BLOCKING_OK otherwise.
    A failure outranks missing coverage because it is the stronger signal.

    Blocking identity is the (intentId, expectationId) pair. Expectation ids are
    unique only within their intent, so matching on a bare id lets one intent's
    blocking flag govern another intent's assertion.
    """
    blocking = {
        (intent.get("id"), expectation.get("id")): expectation
        for intent in _iter_intents(record)
        for expectation in _iter_expectations(intent)
        if is_blocking(expectation)
    }
    if not blocking:
        return BLOCKING_OK

    uncovered = False
    for item in assertions:
        expectation = blocking.get((item["intentId"], item["expectationId"]))
        if expectation is None:
            continue
        outcome = _effective_outcome(expectation, item["outcome"])
        if outcome == "failed":
            return BLOCKING_FAILED
        if outcome in ("untested", "cantTell"):
            uncovered = True
    return BLOCKING_UNCOVERED if uncovered else BLOCKING_OK


def default_output_path(record_path: Path, surface_id: str) -> Path:
    """Return the contract location for a record's verification artifact."""
    return record_path.parent / ".verification" / f"{surface_id}.earl.json"


def generate(
    record_path: Path,
    results_path: Path,
    out_path: Path | None = None,
    timestamp: str | None = None,
    *,
    prepared: tuple[str, dict[str, Any]] | None = None,
) -> tuple[Path, dict[str, Any]]:
    """Generate and write a verification artifact for one authored record.

    Nothing is written when the record, results, or surface binding is invalid,
    so a failed run never leaves a misleading artifact behind.

    Pass 'prepared' as the (raw_text, record) a caller already read so the
    digest and the blocking verdict describe the same revision. Reading twice
    lets an edit between reads produce an artifact whose digest and verdict
    disagree.
    """
    if prepared is None:
        raw_text = read_record_text(record_path)
        record = parse_record(raw_text, record_path)
    else:
        raw_text, record = prepared
    surface_id = record.get("surfaceId")
    if not isinstance(surface_id, str) or not surface_id:
        raise ScriptError(f"Record declares no surfaceId: {record_path}")

    stem = record_path.name.removesuffix(".intent.yaml")
    if stem != surface_id:
        raise ScriptError(
            f"Record surfaceId '{surface_id}' does not match filename "
            f"'{record_path.name}'"
        )

    results = load_results(results_path)
    document = build_verification(record, raw_text, results, timestamp)

    destination = out_path or default_output_path(record_path, surface_id)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return destination, document
