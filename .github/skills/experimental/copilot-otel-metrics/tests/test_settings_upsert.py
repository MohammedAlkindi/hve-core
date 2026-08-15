# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Behavioral tests for the settings upsert executable.

Every test runs against a temporary file. Nothing here reads or writes a real
VS Code settings file.
"""

from __future__ import annotations

import json
import pathlib

import pytest
from settings_upsert import (
    SCHEMA,
    SCHEMA_SOURCE,
    SettingsError,
    apply_changes,
    backup_path_for,
    check_policy,
    main,
    parse_assignment,
    strip_jsonc,
    summarize,
    top_level_spans,
    upsert,
)

ENABLED = "github.copilot.chat.otel.enabled"
EXPORTER = "github.copilot.chat.otel.exporterType"
ENDPOINT = "github.copilot.chat.otel.otlpEndpoint"
CAPTURE = "github.copilot.chat.otel.captureContent"
OUTFILE = "github.copilot.chat.otel.outfile"
MAXSIZE = "github.copilot.chat.otel.maxAttributeSizeChars"

EXISTING = """{
  // A comment the edit must not disturb.
  "editor.fontSize": 13,
  "github.copilot.chat.otel.enabled": false,
  /* block comment */
  "workbench.colorTheme": "Default Dark+"
}
"""


@pytest.fixture()
def settings_file(tmp_path: pathlib.Path) -> pathlib.Path:
    path = tmp_path / "settings.json"
    path.write_text(EXISTING, encoding="utf-8")
    return path


class TestSchemaProvenance:
    """The schema records where it came from and matches the verified build."""

    def test_provenance_names_a_version_and_artifact(self) -> None:
        for field in ("artifact", "extension", "version", "retrieved_from", "verified"):
            assert SCHEMA_SOURCE[field]

    def test_the_schema_is_the_verified_seven_keys(self) -> None:
        assert len(SCHEMA) == 7
        assert all(key.startswith("github.copilot.chat.otel.") for key in SCHEMA)


class TestAssignmentParsing:
    """Keys and types are checked before anything else happens."""

    def test_an_unknown_key_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="unknown key"):
            parse_assignment("github.copilot.chat.otel.protocol=grpc")

    def test_a_key_without_a_value_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="key=value"):
            parse_assignment(ENABLED)

    def test_a_boolean_key_refuses_a_non_boolean(self) -> None:
        with pytest.raises(SettingsError, match="boolean"):
            parse_assignment(f"{ENABLED}=yes")

    def test_an_integer_key_refuses_a_non_integer(self) -> None:
        with pytest.raises(SettingsError, match="integer"):
            parse_assignment(f"{MAXSIZE}=lots")

    @pytest.mark.parametrize(("raw", "expected"), [("true", True), ("false", False)])
    def test_booleans_are_coerced(self, raw: str, expected: bool) -> None:
        assert parse_assignment(f"{ENABLED}={raw}") == (ENABLED, expected)

    def test_integers_are_coerced(self) -> None:
        assert parse_assignment(f"{MAXSIZE}=2048") == (MAXSIZE, 2048)


class TestPolicy:
    """Value combinations the schema cannot express are refused."""

    def test_enabling_content_capture_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="captureContent"):
            check_policy({CAPTURE: True})

    def test_disabling_content_capture_is_allowed(self) -> None:
        check_policy({CAPTURE: False})

    def test_an_unknown_exporter_type_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="exporterType"):
            check_policy({EXPORTER: "otlp-quic"})

    @pytest.mark.parametrize(
        "endpoint",
        [
            "http://evil.example.com:4318",
            "file:///tmp/spans",
            "http://user:pass@localhost:4318",
            "http://localhost:22",
        ],
    )
    def test_an_unsafe_endpoint_is_refused(self, endpoint: str) -> None:
        with pytest.raises(SettingsError, match="otlpEndpoint"):
            check_policy({ENDPOINT: endpoint})

    def test_the_local_collector_endpoint_is_allowed(self) -> None:
        check_policy({ENDPOINT: "http://localhost:4318"})

    def test_outfile_with_an_otlp_exporter_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="outfile"):
            check_policy({OUTFILE: "/tmp/spans.jsonl", EXPORTER: "otlp-http"})

    def test_outfile_with_the_file_exporter_is_allowed(self) -> None:
        check_policy({OUTFILE: "/tmp/spans.jsonl", EXPORTER: "file"})

    def test_a_negative_truncation_limit_is_refused(self) -> None:
        with pytest.raises(SettingsError, match="negative"):
            check_policy({MAXSIZE: -1})


class TestJsoncHandling:
    """Comments survive, offsets line up, and only the target value moves."""

    def test_comments_are_blanked_without_shifting_offsets(self) -> None:
        stripped = strip_jsonc(EXISTING)
        assert len(stripped) == len(EXISTING)
        assert "//" not in stripped
        assert "block comment" not in stripped
        assert json.loads(stripped)["editor.fontSize"] == 13

    def test_a_comment_inside_a_string_is_preserved(self) -> None:
        text = '{"a": "http://example.com/x"}'
        assert json.loads(strip_jsonc(text))["a"] == "http://example.com/x"

    def test_top_level_spans_find_each_key(self) -> None:
        spans = top_level_spans(EXISTING)
        assert set(spans) >= {"editor.fontSize", ENABLED, "workbench.colorTheme"}
        start, end = spans[ENABLED]
        assert EXISTING[start:end] == "false"

    def test_upsert_replaces_only_the_target_value(self) -> None:
        updated = upsert(EXISTING, {ENABLED: True})
        assert "// A comment the edit must not disturb." in updated
        assert "/* block comment */" in updated
        assert json.loads(strip_jsonc(updated))[ENABLED] is True
        assert json.loads(strip_jsonc(updated))["editor.fontSize"] == 13

    def test_upsert_appends_a_missing_key(self) -> None:
        updated = upsert(EXISTING, {ENDPOINT: "http://localhost:4318"})
        assert json.loads(strip_jsonc(updated))[ENDPOINT] == "http://localhost:4318"
        assert "// A comment the edit must not disturb." in updated

    def test_upsert_handles_an_empty_object(self) -> None:
        updated = upsert("{}\n", {ENABLED: True})
        assert json.loads(strip_jsonc(updated)) == {ENABLED: True}

    def test_a_nested_key_of_the_same_name_is_not_targeted(self) -> None:
        """A language-scoped override must not absorb the edit.

        The span scanner is hand-written, so this is the case most likely to
        break silently under a later change: the write would land in a
        `"[python]"` block and the user's real setting would stay unchanged.
        """
        nested = '{\n  "[python]": { "' + ENABLED + '": false },\n  "' + ENABLED + '": false\n}\n'
        assert set(top_level_spans(nested)) == {"[python]", ENABLED}

        parsed = json.loads(strip_jsonc(upsert(nested, {ENABLED: True})))
        assert parsed[ENABLED] is True, "the top-level key was not updated"
        assert parsed["[python]"][ENABLED] is False, "the nested override was overwritten"


class TestCommandLine:
    """Argument handling refuses ambiguous input before touching a file."""

    def test_a_duplicate_key_is_refused(self, settings_file: pathlib.Path) -> None:
        code = main(
            [
                "--settings",
                str(settings_file),
                "--set",
                f"{ENABLED}=true",
                "--set",
                f"{ENABLED}=false",
                "--apply",
            ]
        )
        assert code == 1
        assert settings_file.read_text(encoding="utf-8") == EXISTING

    def test_no_assignment_is_refused(self, settings_file: pathlib.Path) -> None:
        assert main(["--settings", str(settings_file)]) == 1
        assert settings_file.read_text(encoding="utf-8") == EXISTING


class TestApply:
    """Dry runs write nothing; applied edits are backed up and reversible."""

    def test_a_dry_run_leaves_the_file_untouched(self, settings_file: pathlib.Path) -> None:
        apply_changes(settings_file, {ENABLED: True}, apply=False)
        assert settings_file.read_text(encoding="utf-8") == EXISTING

    def test_an_applied_edit_writes_and_backs_up(self, settings_file: pathlib.Path) -> None:
        apply_changes(settings_file, {ENABLED: True}, apply=True)
        assert json.loads(strip_jsonc(settings_file.read_text(encoding="utf-8")))[ENABLED] is True
        backups = list(settings_file.parent.glob(f"{settings_file.name}.*.bak"))
        assert len(backups) == 1
        assert backups[0].read_text(encoding="utf-8") == EXISTING

    def test_unrelated_settings_survive(self, settings_file: pathlib.Path) -> None:
        apply_changes(settings_file, {ENABLED: True}, apply=True)
        parsed = json.loads(strip_jsonc(settings_file.read_text(encoding="utf-8")))
        assert parsed["editor.fontSize"] == 13
        assert parsed["workbench.colorTheme"] == "Default Dark+"

    def test_a_refused_edit_writes_nothing(self, settings_file: pathlib.Path) -> None:
        with pytest.raises(SettingsError):
            apply_changes(settings_file, {CAPTURE: True}, apply=True)
        assert settings_file.read_text(encoding="utf-8") == EXISTING
        assert list(settings_file.parent.glob(f"{settings_file.name}.*.bak")) == []

    def test_a_malformed_existing_file_is_refused(self, tmp_path: pathlib.Path) -> None:
        broken = tmp_path / "settings.json"
        broken.write_text('{"a": [1, 2', encoding="utf-8")
        with pytest.raises(SettingsError, match="not valid JSONC"):
            apply_changes(broken, {ENABLED: True}, apply=True)
        assert broken.read_text(encoding="utf-8") == '{"a": [1, 2'

    def test_a_missing_file_starts_from_an_empty_object(self, tmp_path: pathlib.Path) -> None:
        target = tmp_path / "settings.json"
        apply_changes(target, {ENABLED: True}, apply=True)
        assert json.loads(strip_jsonc(target.read_text(encoding="utf-8"))) == {ENABLED: True}


class TestAudit:
    """Audit evidence is durable and carries no sensitive value verbatim."""

    def test_an_audit_record_is_appended(self, settings_file: pathlib.Path) -> None:
        audit = settings_file.parent / "audit.jsonl"
        apply_changes(settings_file, {ENABLED: True}, apply=True, audit_path=audit)
        record = json.loads(audit.read_text(encoding="utf-8").strip())
        assert record["changes"][ENABLED] == {"from": False, "to": True}
        assert record["schema_version"] == SCHEMA_SOURCE["version"]

    def test_audit_records_accumulate(self, settings_file: pathlib.Path) -> None:
        audit = settings_file.parent / "audit.jsonl"
        apply_changes(settings_file, {ENABLED: True}, apply=True, audit_path=audit)
        apply_changes(settings_file, {ENABLED: False}, apply=True, audit_path=audit)
        assert len(audit.read_text(encoding="utf-8").strip().splitlines()) == 2

    def test_a_sensitive_value_is_summarized_not_copied(self) -> None:
        summarized = summarize(OUTFILE, "/home/someone/private/spans.jsonl")
        assert "private" not in str(summarized)
        assert "length" in str(summarized)

    def test_an_ordinary_value_is_recorded_directly(self) -> None:
        assert summarize(ENABLED, True) is True

    def test_an_endpoint_keeps_its_authority_and_loses_its_path(self) -> None:
        """A path or query on an OTLP endpoint is operator-supplied.

        It is where a tenant identifier or a token would sit, and it is not
        needed to answer the question the record is kept for.
        """
        summarized = summarize(ENDPOINT, "https://ingest.example.com:4318/v1/traces?token=abc123")
        assert summarized == "https://ingest.example.com:4318"
        assert "token" not in str(summarized)
        assert "v1/traces" not in str(summarized)

    def test_a_loopback_endpoint_is_still_recognizable(self) -> None:
        assert summarize(ENDPOINT, "http://localhost:4318/v1/traces") == "http://localhost:4318"

    def test_an_unparseable_endpoint_is_reduced_rather_than_copied(self) -> None:
        summarized = summarize(ENDPOINT, "not-a-url-at-all/secret-path")
        assert "secret-path" not in str(summarized)

    def test_an_absent_value_records_as_absent(self) -> None:
        assert summarize(ENDPOINT, None) is None


class TestBackupRetention:
    """A backup that overwrites the previous backup is not a backup.

    The original defect was a constant `.bak` name: the first run preserved the
    operator's file, and the second run replaced that preserved copy with the
    already-edited one, destroying the only record of the original.
    """

    def test_a_second_apply_does_not_overwrite_the_first_backup(
        self, settings_file: pathlib.Path
    ) -> None:
        apply_changes(settings_file, {ENABLED: True}, apply=True)
        after_first = settings_file.read_text(encoding="utf-8")
        apply_changes(settings_file, {ENABLED: False}, apply=True)

        backups = sorted(settings_file.parent.glob(f"{settings_file.name}.*.bak"))
        assert len(backups) == 2
        contents = {path.read_text(encoding="utf-8") for path in backups}
        assert EXISTING in contents, "the operator's original file was not retained"
        assert after_first in contents

    def test_a_same_second_collision_gets_its_own_name(self, tmp_path: pathlib.Path) -> None:
        settings = tmp_path / "settings.json"
        settings.write_text("{}\n", encoding="utf-8")
        first = backup_path_for(settings)
        first.write_text("taken", encoding="utf-8")
        second = backup_path_for(settings)
        assert second != first
        assert not second.exists()

    def test_the_backup_sits_beside_the_settings_file(self, tmp_path: pathlib.Path) -> None:
        settings = tmp_path / "settings.json"
        assert backup_path_for(settings).parent == tmp_path
        assert backup_path_for(settings).name.startswith("settings.json.")
        assert backup_path_for(settings).name.endswith(".bak")


class TestTrailingCommas:
    """A trailing comma is accepted; a comma inside a string is untouchable.

    The suggested fix for this finding was a regex that removed any comma
    followed by a closing brace. That rewrites string literals too, and the
    untouched-key comparison guarding this edit could not have caught it,
    because both sides of that comparison are produced by the same pass.
    """

    def test_a_trailing_comma_in_an_object_parses(self) -> None:
        assert json.loads(strip_jsonc('{"a": 1,}')) == {"a": 1}

    def test_a_trailing_comma_in_an_array_parses(self) -> None:
        assert json.loads(strip_jsonc('{"a": [1, 2,],}')) == {"a": [1, 2]}

    def test_a_trailing_comma_followed_by_a_comment_parses(self) -> None:
        assert json.loads(strip_jsonc('{"a": 1, // note\n}')) == {"a": 1}

    def test_a_comma_inside_a_string_literal_survives_byte_for_byte(self) -> None:
        source = '{"note": "literal, }", "a": 1,}'
        stripped = strip_jsonc(source)
        assert len(stripped) == len(source), "offsets were not preserved"
        assert '"literal, }"' in stripped, "a comma inside a string was rewritten"
        assert json.loads(stripped) == {"note": "literal, }", "a": 1}

    def test_the_scan_preserves_every_offset(self) -> None:
        source = '{\n  "a": 1, // trailing\n}\n'
        assert len(strip_jsonc(source)) == len(source)

    def test_an_edit_survives_a_document_with_a_trailing_comma(
        self, tmp_path: pathlib.Path
    ) -> None:
        settings = tmp_path / "settings.json"
        settings.write_text('{\n  "editor.fontSize": 13,\n}\n', encoding="utf-8")
        apply_changes(settings, {ENABLED: True}, apply=True)
        parsed = json.loads(strip_jsonc(settings.read_text(encoding="utf-8")))
        assert parsed[ENABLED] is True
        assert parsed["editor.fontSize"] == 13

    def test_a_string_containing_a_brace_is_not_read_as_structure(
        self, tmp_path: pathlib.Path
    ) -> None:
        settings = tmp_path / "settings.json"
        settings.write_text('{\n  "note": "literal, }",\n}\n', encoding="utf-8")
        apply_changes(settings, {ENABLED: True}, apply=True)
        text = settings.read_text(encoding="utf-8")
        assert '"literal, }"' in text
        assert json.loads(strip_jsonc(text))["note"] == "literal, }"
