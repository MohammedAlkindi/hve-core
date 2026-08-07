# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

"""Tests for the design-intent verification adapter."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
import runtime_a11y.__main__ as cli
from runtime_a11y import _intent as intent
from runtime_a11y._errors import (
    EXIT_INTENT_DRIFT,
    EXIT_INTENT_UNCOVERED,
    EXIT_SUCCESS,
    EXIT_USAGE,
    ScriptError,
)

_REPO_ROOT = Path(__file__).resolve().parents[6]
_FIXTURE_REPO = _REPO_ROOT / "scripts/tests/fixtures/design-intent/valid-repo"
_FIXTURE_RECORD = _FIXTURE_REPO / "design-intent/valid-surface.intent.yaml"
_FIXTURE_RESULTS = _FIXTURE_REPO / "harness-results.json"
_FIXTURE_DIGEST = (
    "sha256:bf341bec83bde1e7d8a10d69c44675f46081d08675ce3336723b50d6613d540a"
)

# The shared contract fixture lives in the hve-core repository, not in the
# skill. When the skill is packaged into a consuming project those files are
# absent, so tests that assert parity with the reference validator skip rather
# than fail. Adapter behavior itself is covered by the self-contained tests.
_requires_contract_fixture = pytest.mark.skipif(
    not _FIXTURE_RECORD.exists(),
    reason="shared design-intent contract fixture is not present",
)


def _write_record(tmp_path: Path, body: str, surface_id: str = "s1") -> Path:
    record_dir = tmp_path / "design-intent"
    record_dir.mkdir(parents=True, exist_ok=True)
    path = record_dir / f"{surface_id}.intent.yaml"
    path.write_text(body, encoding="utf-8")
    return path


def _write_results(tmp_path: Path, rows: list[dict[str, object]]) -> Path:
    path = tmp_path / "results.json"
    path.write_text(json.dumps({"results": rows}), encoding="utf-8")
    return path


_SIMPLE_RECORD = """
schemaVersion: "1.0"
surfaceId: s1
title: Simple surface
owner: Team
status: accepted
decidedOn: "2026-01-01"
decidedBy:
  - A. Person
version: 1
intents:
  - id: INT-001
    conveys: Controls are reachable by keyboard.
    rationale: Keyboard users must reach every control.
    audience:
      - Keyboard users
    evidence: observed
    binding:
      state: default
    expectations:
      - id: EXP-001
        method: runtime-automation
        assert: probe-keyboard-traversal
        detail: Tab order reaches every control.
        criteria:
          - wcag-22:2.1.1
        role: decides
        blocking: true
"""


def _row(**overrides: object) -> dict[str, object]:
    base = {
        "criterionId": "2.1.1",
        "framework": "wcag-22",
        "surfaceId": "s1",
        "state": "default",
        "status": "pass",
        "probeId": "probe-keyboard-traversal",
    }
    base.update(overrides)
    return base


class TestDigest:
    @_requires_contract_fixture
    def test_given_fixture_record_when_digest_then_matches_validator_value(
        self,
    ) -> None:
        raw = intent.read_record_text(_FIXTURE_RECORD)
        assert intent.compute_intent_digest(raw) == _FIXTURE_DIGEST

    def test_given_crlf_content_when_digest_then_equals_lf_digest(self) -> None:
        assert intent.compute_intent_digest("a\r\nb") == intent.compute_intent_digest(
            "a\nb"
        )

    def test_given_mutated_record_when_digest_then_differs(
        self, tmp_path: Path
    ) -> None:
        path = _write_record(tmp_path, _SIMPLE_RECORD)
        before = intent.compute_intent_digest(intent.read_record_text(path))
        path.write_text(_SIMPLE_RECORD + "\n# drift\n", encoding="utf-8")
        after = intent.compute_intent_digest(intent.read_record_text(path))
        assert before != after


class TestCriterionReference:
    def test_given_plain_reference_when_split_then_returns_pair(self) -> None:
        assert intent.split_criterion_reference("wcag-22:2.1.1") == ("wcag-22", "2.1.1")

    def test_given_reference_with_inner_colon_when_split_then_keeps_remainder(
        self,
    ) -> None:
        assert intent.split_criterion_reference(
            "aria-apg:APG:notification-live-region"
        ) == ("aria-apg", "APG:notification-live-region")

    @pytest.mark.parametrize("value", ["nocolon", ":missing", "missing:"])
    def test_given_malformed_reference_when_split_then_raises(self, value: str) -> None:
        with pytest.raises(ScriptError):
            intent.split_criterion_reference(value)


class TestOutcomeMapping:
    @pytest.mark.parametrize(
        ("status", "expected"),
        [("pass", "passed"), ("fail", "failed"), ("candidate", "cantTell")],
    )
    def test_given_status_when_build_then_maps_to_outcome(
        self, tmp_path: Path, status: str, expected: str
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status=status)])
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == expected

    def test_given_unknown_status_when_build_then_reports_cant_tell(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="weird")])
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == "cantTell"

    def test_given_partial_status_when_build_then_maps_explicitly_to_cant_tell(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="partial")])
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == "cantTell"


class TestJoin:
    @pytest.mark.parametrize(
        "override",
        [
            {"surfaceId": "other"},
            {"state": "error"},
            {"probeId": "probe-axe"},
            {"criterionId": "9.9.9"},
            {"framework": "other-framework"},
        ],
    )
    def test_given_non_matching_row_when_build_then_untested(
        self, tmp_path: Path, override: dict[str, object]
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(**override)])
        _, document = intent.generate(record_path, results_path)
        assertion = document["assertions"][0]
        assert assertion["outcome"] == "untested"
        assert assertion["info"]

    def test_given_non_dict_row_when_build_then_ignored(self, tmp_path: Path) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = tmp_path / "results.json"
        results_path.write_text(json.dumps({"results": ["junk"]}), encoding="utf-8")
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == "untested"

    def test_given_non_list_results_when_build_then_all_untested(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = tmp_path / "results.json"
        results_path.write_text(json.dumps({"results": "nope"}), encoding="utf-8")
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == "untested"


class TestAggregation:
    def test_given_mixed_criteria_when_build_then_worst_outcome_wins(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace(
            "          - wcag-22:2.1.1",
            "          - wcag-22:2.1.1\n          - wcag-22:2.1.2",
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(
            tmp_path,
            [
                _row(criterionId="2.1.1", status="pass"),
                _row(criterionId="2.1.2", status="fail"),
            ],
        )
        _, document = intent.generate(record_path, results_path)
        assert document["assertions"][0]["outcome"] == "failed"

    def test_given_pass_and_candidate_when_build_then_cant_tell_wins(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace(
            "          - wcag-22:2.1.1",
            "          - wcag-22:2.1.1\n          - wcag-22:2.1.2",
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(
            tmp_path,
            [
                _row(criterionId="2.1.1", status="pass"),
                _row(criterionId="2.1.2", status="candidate"),
            ],
        )
        _, document = intent.generate(record_path, results_path)
        assertion = document["assertions"][0]
        assert assertion["outcome"] == "cantTell"
        assert assertion["info"]


class TestFixtureRecord:
    @_requires_contract_fixture
    def test_given_fixture_when_generate_then_one_assertion_per_expectation(
        self, tmp_path: Path
    ) -> None:
        out = tmp_path / "valid-surface.earl.json"
        _, document = intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, out)
        assert len(document["assertions"]) == 5
        ids = [item["expectationId"] for item in document["assertions"]]
        assert ids == ["EXP-001", "EXP-002", "EXP-003", "EXP-004", "EXP-005"]

    @_requires_contract_fixture
    def test_given_fixture_when_generate_then_outcomes_are_mixed(
        self, tmp_path: Path
    ) -> None:
        out = tmp_path / "valid-surface.earl.json"
        _, document = intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, out)
        outcomes = {item["outcome"] for item in document["assertions"]}
        # Every outcome the adapter can produce from a probe run appears here,
        # so a stub emitting one blanket outcome cannot pass.
        assert outcomes == {"passed", "failed", "cantTell", "untested"}

    @_requires_contract_fixture
    def test_given_fixture_when_generate_then_each_expectation_resolves_as_declared(
        self, tmp_path: Path
    ) -> None:
        out = tmp_path / "valid-surface.earl.json"
        _, document = intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, out)
        by_id = {item["expectationId"]: item for item in document["assertions"]}
        assert by_id["EXP-001"]["outcome"] == "passed"
        # Worst-wins: a single failing criterion fails the whole expectation.
        assert by_id["EXP-002"]["outcome"] == "failed"
        # Worst-wins again, with one criterion passing and one undecided.
        assert by_id["EXP-003"]["outcome"] == "cantTell"
        assert by_id["EXP-004"]["outcome"] == "untested"
        assert by_id["EXP-005"]["outcome"] == "untested"

    @_requires_contract_fixture
    def test_given_fixture_when_only_non_blocking_fails_then_no_blocking_failure(
        self,
    ) -> None:
        raw = intent.read_record_text(_FIXTURE_RECORD)
        record = intent.parse_record(raw, _FIXTURE_RECORD)
        results = intent.load_results(_FIXTURE_RESULTS)
        assertions = intent.build_assertions(record, results)
        # EXP-002 fails but is declared non-blocking, so no blocking failure.
        verdict = intent.evaluate_blocking(record, assertions)
        assert verdict != intent.BLOCKING_FAILED
        # The fixture is not clean either: blocking EXP-003 declares two criteria
        # and the run settled only part of them, so its claim is unproven. The
        # old boolean gate reported success here, which is the silent pass this
        # contract now refuses. Blocking EXP-005 is untested but carries a human
        # override, so it does not contribute.
        assert verdict == intent.BLOCKING_UNCOVERED

    @_requires_contract_fixture
    def test_given_custom_assert_when_generate_then_untested_and_manual(
        self, tmp_path: Path
    ) -> None:
        out = tmp_path / "valid-surface.earl.json"
        _, document = intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, out)
        custom = next(
            item
            for item in document["assertions"]
            if item["expectationId"] == "EXP-004"
        )
        assert custom["outcome"] == "untested"
        assert custom["mode"] == "manual"
        assert custom["info"]

    @_requires_contract_fixture
    def test_given_fixture_when_generate_then_digest_matches_record(
        self, tmp_path: Path
    ) -> None:
        out = tmp_path / "valid-surface.earl.json"
        _, document = intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, out)
        assert document["intentDigest"] == _FIXTURE_DIGEST

    @_requires_contract_fixture
    def test_given_committed_fixture_sidecar_then_generation_does_not_touch_it(
        self, tmp_path: Path
    ) -> None:
        committed = (
            _FIXTURE_REPO / "design-intent/.verification/valid-surface.earl.json"
        )
        before = committed.read_bytes()
        intent.generate(_FIXTURE_RECORD, _FIXTURE_RESULTS, tmp_path / "out.json")
        assert committed.read_bytes() == before


class TestBlockingEvaluation:
    def test_given_blocking_failure_when_checked_then_true(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="fail")])
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)
        assert (
            intent.evaluate_blocking(record, document["assertions"])
            == intent.BLOCKING_FAILED
        )

    def test_given_non_blocking_failure_when_checked_then_false(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace("blocking: true", "blocking: false").replace(
            "role: decides", "role: informs"
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(tmp_path, [_row(status="fail")])
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)
        verdict = intent.evaluate_blocking(record, document["assertions"])
        assert verdict == intent.BLOCKING_OK

    def test_given_passing_run_when_checked_then_false(self, tmp_path: Path) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="pass")])
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)
        verdict = intent.evaluate_blocking(record, document["assertions"])
        assert verdict == intent.BLOCKING_OK

    def test_given_partial_coverage_for_blocking_when_checked_then_uncovered(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace(
            "          - wcag-22:2.1.1",
            "          - wcag-22:2.1.1\n          - wcag-22:2.1.2",
        )
        record_path = _write_record(tmp_path, body)
        rows = [_row(criterionId="2.1.1", status="pass")]
        results_path = _write_results(tmp_path, rows)
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)
        assert (
            intent.evaluate_blocking(record, document["assertions"])
            == intent.BLOCKING_UNCOVERED
        )

    def test_given_duplicate_expectation_id_across_intents_when_checked_then_no_cross(
        self, tmp_path: Path
    ) -> None:
        body = """
schemaVersion: "1.0"
surfaceId: s1
title: Multi intent
owner: Team
status: accepted
decidedOn: "2026-01-01"
decidedBy:
  - A. Person
version: 1
intents:
  - id: INT-001
    conveys: Blocking expectation.
    rationale: r1
    audience: [A]
    evidence: observed
    binding: { state: default }
    expectations:
      - id: EXP-001
        method: runtime-automation
        assert: probe-keyboard-traversal
        detail: d1
        criteria: [wcag-22:2.1.1]
        role: decides
        blocking: true
  - id: INT-002
    conveys: Informing expectation with same id.
    rationale: r2
    audience: [B]
    evidence: observed
    binding: { state: default }
    expectations:
      - id: EXP-001
        method: runtime-automation
        assert: probe-keyboard-traversal
        detail: d2
        criteria: [wcag-22:2.1.2]
        role: informs
        blocking: false
"""
        record_path = _write_record(tmp_path, body)
        rows = [_row(criterionId="2.1.2", status="fail")]
        results_path = _write_results(tmp_path, rows)
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)
        verdict = intent.evaluate_blocking(record, document["assertions"])
        assert verdict == intent.BLOCKING_UNCOVERED

    def test_given_non_boolean_blocking_when_checked_then_raises(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace("blocking: true", "blocking: 'true'")
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(tmp_path, [_row(status="pass")])
        with pytest.raises(ScriptError, match="non-boolean"):
            intent.generate(record_path, results_path)

    def test_given_override_settles_uncovered_blocking_when_checked_then_ok(
        self, tmp_path: Path
    ) -> None:
        # A human review settled a blocking expectation the probe cannot drive.
        # The artifact still records 'untested', but the gate must not fire.
        body = _SIMPLE_RECORD.replace(
            "        blocking: true\n",
            "        blocking: true\n"
            "        override:\n"
            "          outcome: passed\n"
            "          rationale: Manual review on a platform the probe cannot drive.\n"
            "          reviewedBy: C. Reviewer\n"
            "          reviewedOn: \"2026-08-06\"\n",
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(tmp_path, [])
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)

        assert document["assertions"][0]["outcome"] == "untested"
        verdict = intent.evaluate_blocking(record, document["assertions"])
        assert verdict == intent.BLOCKING_OK

    def test_given_override_failed_when_checked_then_blocking_failed(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace(
            "        blocking: true\n",
            "        blocking: true\n"
            "        override:\n"
            "          outcome: failed\n"
            "          rationale: Manual review found the announcement missing.\n"
            "          reviewedBy: C. Reviewer\n"
            "          reviewedOn: \"2026-08-06\"\n",
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(tmp_path, [_row(status="pass")])
        raw = intent.read_record_text(record_path)
        record = intent.parse_record(raw, record_path)
        _, document = intent.generate(record_path, results_path)

        verdict = intent.evaluate_blocking(record, document["assertions"])
        assert verdict == intent.BLOCKING_FAILED

    def test_given_missing_expectation_id_when_generate_then_raises_before_write(
        self, tmp_path: Path
    ) -> None:
        body = _SIMPLE_RECORD.replace("      - id: EXP-001\n", "      -\n")
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(tmp_path, [_row(status="pass")])
        out = tmp_path / "out.json"
        with pytest.raises(ScriptError, match="needs an id"):
            intent.generate(record_path, results_path, out)
        assert not out.exists()


class TestFailurePaths:
    def test_given_missing_record_when_generate_then_usage_error(
        self, tmp_path: Path
    ) -> None:
        with pytest.raises(ScriptError) as excinfo:
            intent.generate(tmp_path / "absent.intent.yaml", tmp_path / "r.json")
        assert excinfo.value.exit_code == EXIT_USAGE

    def test_given_malformed_yaml_when_generate_then_raises_and_writes_nothing(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, "surfaceId: [unclosed\n")
        out = tmp_path / "out.json"
        with pytest.raises(ScriptError):
            intent.generate(record_path, tmp_path / "r.json", out)
        assert not out.exists()

    def test_given_non_mapping_record_when_generate_then_raises(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, "- just\n- a\n- list\n")
        with pytest.raises(ScriptError):
            intent.generate(record_path, tmp_path / "r.json")

    def test_given_record_without_surface_id_when_generate_then_raises(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, "title: no surface\n")
        with pytest.raises(ScriptError):
            intent.generate(record_path, tmp_path / "r.json")

    def test_given_surface_id_filename_mismatch_when_generate_then_raises(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(
            tmp_path, _SIMPLE_RECORD.replace("surfaceId: s1", "surfaceId: other")
        )
        with pytest.raises(ScriptError) as excinfo:
            intent.generate(record_path, tmp_path / "r.json")
        assert "does not match filename" in str(excinfo.value)

    def test_given_missing_results_when_generate_then_usage_error(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        with pytest.raises(ScriptError) as excinfo:
            intent.generate(record_path, tmp_path / "absent.json")
        assert excinfo.value.exit_code == EXIT_USAGE

    def test_given_invalid_results_json_when_generate_then_raises(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = tmp_path / "results.json"
        results_path.write_text("{not json", encoding="utf-8")
        with pytest.raises(ScriptError):
            intent.generate(record_path, results_path)

    def test_given_non_object_results_when_generate_then_raises(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = tmp_path / "results.json"
        results_path.write_text("[]", encoding="utf-8")
        with pytest.raises(ScriptError):
            intent.generate(record_path, results_path)


class TestOutputLocation:
    def test_given_no_out_path_when_generate_then_writes_contract_location(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row()])
        destination, _ = intent.generate(record_path, results_path)
        assert destination == record_path.parent / ".verification" / "s1.earl.json"
        assert destination.exists()

    def test_given_explicit_out_path_when_generate_then_creates_parents(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row()])
        out = tmp_path / "nested" / "deeper" / "artifact.json"
        destination, _ = intent.generate(record_path, results_path, out)
        assert destination == out
        assert json.loads(out.read_text(encoding="utf-8"))["surfaceId"] == "s1"

    def test_given_generation_when_complete_then_timestamp_is_populated(
        self, tmp_path: Path
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row()])
        _, document = intent.generate(record_path, results_path)
        assert document["timestamp"]
        assert document["assertedBy"] == intent.ASSERTED_BY
        assert document["schemaVersion"] == intent.SCHEMA_VERSION


class TestCli:
    def test_given_clean_run_when_verify_intent_then_exit_success(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="pass")])
        out = tmp_path / "out.json"
        code = cli.main(
            [
                "verify-intent",
                "--record",
                str(record_path),
                "--results",
                str(results_path),
                "--out",
                str(out),
            ]
        )
        assert code == EXIT_SUCCESS
        assert "Wrote" in capsys.readouterr().out

    def test_given_blocking_failure_when_verify_intent_then_exit_drift(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        record_path = _write_record(tmp_path, _SIMPLE_RECORD)
        results_path = _write_results(tmp_path, [_row(status="fail")])
        out = tmp_path / "out.json"
        code = cli.main(
            [
                "verify-intent",
                "--record",
                str(record_path),
                "--results",
                str(results_path),
                "--out",
                str(out),
            ]
        )
        assert code == EXIT_INTENT_DRIFT
        assert "blocking design intent expectation failed" in capsys.readouterr().err
        assert out.exists(), "the artifact is still written so CI can publish it"

    def test_given_blocking_uncovered_when_verify_intent_then_exit_uncovered(
        self, tmp_path: Path, capsys: pytest.CaptureFixture[str]
    ) -> None:
        body = _SIMPLE_RECORD.replace(
            "          - wcag-22:2.1.1",
            "          - wcag-22:2.1.1\n          - wcag-22:2.1.2",
        )
        record_path = _write_record(tmp_path, body)
        results_path = _write_results(
            tmp_path, [_row(criterionId="2.1.1", status="pass")]
        )
        out = tmp_path / "out.json"
        code = cli.main(
            [
                "verify-intent",
                "--record",
                str(record_path),
                "--results",
                str(results_path),
                "--out",
                str(out),
            ]
        )
        assert code == EXIT_INTENT_UNCOVERED
        assert (
            "blocking design intent expectation was never evaluated"
            in capsys.readouterr().err
        )
        assert out.exists(), "the artifact is still written so CI can publish it"

    def test_given_missing_record_when_verify_intent_then_usage_exit(
        self, tmp_path: Path
    ) -> None:
        code = cli.main(
            [
                "verify-intent",
                "--record",
                str(tmp_path / "absent.intent.yaml"),
                "--results",
                str(tmp_path / "absent.json"),
            ]
        )
        assert code == EXIT_USAGE
