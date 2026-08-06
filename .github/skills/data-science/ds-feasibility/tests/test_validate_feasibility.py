# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for the Feasibility Study Interchange Profile validator."""

from __future__ import annotations

import copy
from pathlib import Path

import pytest
from validate_feasibility import (
    BEGIN_MARKER,
    END_MARKER,
    FeasibilityValidationError,
    extract_profile_yaml,
    load_schema,
    parse_profile,
    run,
    validate_profile,
)

SKILL_ROOT = Path(__file__).resolve().parent.parent
VALID_PATH = SKILL_ROOT / "examples" / "valid-study.md"


def _valid() -> tuple[dict, str]:
    markdown = VALID_PATH.read_text(encoding="utf-8")
    return parse_profile(markdown), markdown


def test_given_valid_study_when_validated_then_has_no_errors() -> None:
    # Arrange
    data, markdown = _valid()

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert errors == []


def test_given_unsupported_version_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    data["profile_version"] = "2.0.0"

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert errors


def test_given_duplicate_concept_id_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    duplicate = copy.deepcopy(data["items"][1])
    duplicate["display_ref"] = "FS-003"
    duplicate["narrative_anchor"] = "fs-003"
    data["items"].append(duplicate)
    markdown += "\n### FS-003: Duplicate concept\n"

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("conceptual IDs must be unique" in error for error in errors)


def test_given_malformed_uuid_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    data["items"][0]["item_id"] = "not-a-uuid"

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert errors


def test_given_broken_relation_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    data["items"][1]["relations"][0]["target"] = (
        "urn:uuid:99999999-0000-4000-8000-000000000001"
    )

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("unknown target" in error for error in errors)


def test_given_cyclic_revision_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    registry = data["revision_registry"]
    registry[0]["revision_of"] = registry[1]["revision_id"]

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("cyclic" in error for error in errors)


def test_given_incomplete_tombstone_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    item = data["items"][1]
    item["status"] = "superseded"

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("incomplete superseded tombstone" in error for error in errors)


def test_given_prohibited_yaml_when_parsed_then_raises() -> None:
    # Arrange
    markdown = (
        f"{BEGIN_MARKER}\n```yaml\nprofile: &p feasibility-study-interchange\n"
        f"copy: *p\n```\n{END_MARKER}\n"
    )

    # Act and assert
    with pytest.raises(FeasibilityValidationError, match="cannot use anchors"):
        parse_profile(markdown)


def test_given_orphaned_item_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    markdown = markdown.replace(
        "### FS-002: Rank recommendation candidates",
        "### Candidate narrative without an alias",
    )

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("orphaned YAML items" in error for error in errors)


def test_given_requirement_id_when_validated_then_fails() -> None:
    # Arrange
    data, markdown = _valid()
    markdown += "\nAssigned downstream identifier FR-123.\n"

    # Act
    errors = validate_profile(data, markdown, load_schema(SKILL_ROOT))

    # Assert
    assert any("cannot allocate FR or NFR" in error for error in errors)


def test_given_multiple_blocks_when_extracted_then_raises() -> None:
    # Arrange
    block = (
        f"{BEGIN_MARKER}\n```yaml\nprofile: feasibility-study-interchange\n"
        f"```\n{END_MARKER}\n"
    )

    # Act and assert
    with pytest.raises(FeasibilityValidationError, match="exactly one"):
        extract_profile_yaml(block + block)


def test_given_valid_file_when_run_then_returns_success(capsys) -> None:
    # Act
    result = run(VALID_PATH)

    # Assert
    assert result == 0
    assert '"valid": true' in capsys.readouterr().out
