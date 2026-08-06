# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for `scripts.scan_sensitive_content`.

Covers high-confidence PII and public internal-URL findings, benign ADR prose
true negatives, non-PII credential-shaped text, and the external-sink gating
contract that non-zero exit accompanies any high-confidence finding.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

scan_sensitive_content = pytest.importorskip("scripts.scan_sensitive_content")


def _invoke(args: list[str], capsys: pytest.CaptureFixture[str]) -> tuple[int, dict]:
    """Invoke `scan_sensitive_content.main` and return exit code plus parsed JSON."""
    try:
        exit_code = int(scan_sensitive_content.main(args) or 0)
    except SystemExit as exc:
        exit_code = int(exc.code or 0)
    out = capsys.readouterr().out
    report = json.loads(out) if out.strip() else {}
    return exit_code, report


class TestScanHighConfidenceTruePositives:
    @pytest.mark.parametrize(
        ("pii", "category"),
        [
            ("alice@example.com", "email_address"),
            ("425-555-0100", "phone_number"),
            ("123-45-6789", "national_identifier"),
        ],
    )
    def test_given_pii_when_scan_then_high_finding_and_nonzero_exit(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
        pii: str,
        category: str,
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text(f"Contact detail: {pii}\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke([str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_FAILURE
        categories = {f["category"] for f in report["findings"]}
        assert category in categories
        assert report["summary"]["high"] >= 1
        # The raw PII must not be echoed back verbatim (redaction contract).
        assert pii not in json.dumps(report)


class TestScanSafeNegatives:
    @pytest.mark.parametrize(
        "benign",
        [
            "We chose Postgres for ACID guarantees and operational maturity.",
            "See https://learn.microsoft.com/azure for guidance.",
            "The decision ID is 0007 and supersedes 0003.",
            "Latency budget is 200ms at p99 under peak load.",
        ],
    )
    def test_given_benign_prose_when_scan_then_no_findings_and_zero_exit(
        self,
        tmp_path: Path,
        benign: str,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text(benign + "\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke([str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        assert report["summary"]["high"] == 0

    @pytest.mark.parametrize(
        "provider_key_shape",
        [
            "-----BEGIN RSA PRIVATE KEY-----",
            "ghp_0123456789abcdefghijklmnopqrstuvwxyz",
            "AKIAIOSFODNN7EXAMPLE",
            "AIzaSyA0123456789abcdefghijklmnopqrstuvwxyz0",
            "example slack token placeholder",
            "sk-0123456789abcdefghijklmnopqrstuvwxyzABCDEF",
        ],
    )
    def test_given_provider_key_shape_when_scan_then_no_findings_and_zero_exit(
        self,
        tmp_path: Path,
        provider_key_shape: str,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text(f"Decision note includes {provider_key_shape} as sample text.\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke([str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        assert report["summary"] == {"high": 0, "warn": 0, "total": 0}


class TestScanInternalUrlVisibility:
    @pytest.mark.parametrize(
        "internal_url",
        [
            "http://localhost:8080/admin",
            "https://10.1.2.3/healthz",
            "http://db.corp/status",
        ],
    )
    def test_given_internal_url_when_private_then_no_high_and_zero_exit(
        self,
        tmp_path: Path,
        internal_url: str,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text(f"Service runs at {internal_url} today.\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke([str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        categories = {f["category"] for f in report["findings"]}
        assert "internal_url" not in categories
        assert report["summary"]["high"] == 0

    @pytest.mark.parametrize(
        "internal_url",
        [
            "http://localhost:8080/admin",
            "https://10.1.2.3/healthz",
            "http://db.corp/status",
        ],
    )
    def test_given_internal_url_when_public_then_high_and_nonzero_exit(
        self,
        tmp_path: Path,
        internal_url: str,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text(f"Service runs at {internal_url} today.\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke(["--public", str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_FAILURE
        categories = {f["category"] for f in report["findings"]}
        assert "internal_url" in categories
        assert report["summary"]["high"] >= 1


class TestScanStdin:
    def test_given_pii_on_stdin_when_scan_then_nonzero_exit(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        import io

        monkeypatch.setattr("sys.stdin", io.StringIO("Contact: alice@example.com\n"))

        # Act
        exit_code, report = _invoke([], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_FAILURE
        assert report["summary"]["high"] >= 1
        assert report["findings"][0]["source"] == scan_sensitive_content.STDIN_SOURCE


class TestScanDataMode:
    @pytest.mark.parametrize(
        ("content", "category", "confidence"),
        [
            ("columns: [ssn]", "sensitive_column_name", "high"),
            ("- name: patientId", "sensitive_column_name", "warn"),
            ("customer_id varchar(40)", None, None),
            ("Server=db;Initial Catalog=orders;User Id=app;Password=secret", "connection_string", "high"),
            ("url: jdbc:postgresql://db/orders", "jdbc_odbc_uri", "high"),
            ("url: postgres://user:secret@db/orders", "db_uri_with_credentials", "high"),
            ("AccountKey=YWJjZGVmZ2hpamtsbW5vcHFyc3R1", "storage_key", "high"),
            ("Authorization: Bearer abcdefghijklmnop", "bearer_token", "high"),
            ("national_insurance: AB123456C", "uk_national_insurance", "warn"),
            ("sin: 046 454 286", "canadian_sin", "warn"),
            ("phone: +442079460958", "international_phone", "warn"),
            (
                "url: https://acct.blob.core.windows.net/c?sp=r&se=2030-01-01&sig=secret",
                "sas_token",
                "high",
            ),
        ],
    )
    def test_given_data_rule_when_data_mode_then_expected_finding(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
        content: str,
        category: str | None,
        confidence: str | None,
    ) -> None:
        # Arrange
        target = tmp_path / "data.txt"
        target.write_text(content + "\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke(["--data", str(target)], capsys)

        # Assert
        categories = {finding["category"] for finding in report["findings"]}
        if category is None:
            assert exit_code == scan_sensitive_content.EXIT_SUCCESS
            assert categories == set()
        else:
            assert category in categories
            expected_exit = (
                scan_sensitive_content.EXIT_FAILURE
                if confidence == "high"
                else scan_sensitive_content.EXIT_SUCCESS
            )
            assert exit_code == expected_exit

    def test_given_sample_table_when_data_mode_then_warns_without_blocking(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "catalog.md"
        target.write_text(
            "## Sample rows\n\n| id | value |\n|----|-------|\n| 1 | synthetic |\n",
            encoding="utf-8",
        )

        # Act
        exit_code, report = _invoke(["--data", str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        assert any(finding["category"] == "sample_row" for finding in report["findings"])
        assert report["summary"]["warn"] >= 1

    def test_given_data_only_content_when_default_mode_then_preserves_empty_result(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "adr.md"
        target.write_text("columns: [ssn]\nurl: jdbc:postgresql://db/orders\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke([str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        assert report["summary"] == {"high": 0, "warn": 0, "total": 0}


class TestScanDenylist:
    def test_given_denylist_when_term_differs_by_case_then_blocks_without_leak(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        denylist = tmp_path / "terms.txt"
        denylist.write_text("Contoso-Blue\n\ncontoso-blue\n", encoding="utf-8")
        target = tmp_path / "artifact.md"
        target.write_text("Tenant: CONTOSO-BLUE\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke(
            ["--denylist", str(denylist), str(target)], capsys
        )

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_FAILURE
        denylist_findings = [
            finding
            for finding in report["findings"]
            if finding["category"] == "denylist_term"
        ]
        assert len(denylist_findings) == 1
        assert "contoso-blue" not in json.dumps(report).lower()

    def test_given_denylist_and_other_modes_when_scanned_then_rules_form_union(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        denylist = tmp_path / "terms.txt"
        denylist.write_text("tenant-seven\n", encoding="utf-8")
        target = tmp_path / "artifact.md"
        target.write_text(
            "tenant-seven\ncolumns: [dob]\nhttp://localhost/admin\n",
            encoding="utf-8",
        )

        # Act
        _, report = _invoke(
            ["--public", "--data", "--denylist", str(denylist), str(target)],
            capsys,
        )

        # Assert
        categories = {finding["category"] for finding in report["findings"]}
        assert {"denylist_term", "sensitive_column_name", "internal_url"} <= categories

    @pytest.mark.parametrize("kind", ["missing", "directory", "invalid-utf8"])
    def test_given_invalid_denylist_when_scanned_then_returns_error(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
        kind: str,
    ) -> None:
        # Arrange
        denylist = tmp_path / "terms.txt"
        if kind == "directory":
            denylist.mkdir()
        elif kind == "invalid-utf8":
            denylist.write_bytes(b"\xff\xfe")

        # Act
        exit_code, report = _invoke(["--denylist", str(denylist)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_ERROR
        assert report == {}


class TestScanPerformance:
    def test_given_long_benign_input_when_data_mode_then_completes_without_findings(
        self,
        tmp_path: Path,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Arrange
        target = tmp_path / "large.txt"
        target.write_text(("ordinary catalog context " * 20000) + "\n", encoding="utf-8")

        # Act
        exit_code, report = _invoke(["--data", str(target)], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_SUCCESS
        assert report["summary"] == {"high": 0, "warn": 0, "total": 0}


class TestScanPathTraversal:
    @pytest.mark.parametrize(
        "adversarial",
        [
            "../../../etc/passwd",
            "..\\..\\..\\Windows\\System32\\config\\SAM",
        ],
    )
    def test_given_traversal_path_when_scan_then_exits_error(
        self,
        adversarial: str,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        # Act
        exit_code, _ = _invoke([adversarial], capsys)

        # Assert
        assert exit_code == scan_sensitive_content.EXIT_ERROR
