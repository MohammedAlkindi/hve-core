# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for the DS_CATALOG_V1 validator."""

from __future__ import annotations

import copy
from pathlib import Path

import pytest
from validate_catalog import (
    CatalogValidationError,
    extract_frontmatter,
    load_schema,
    parse_catalog,
    run,
    validate_catalog,
)

SKILL_ROOT = Path(__file__).resolve().parent.parent


def _valid_catalog() -> dict:
    markdown = (SKILL_ROOT / "examples" / "northwind-catalog.md").read_text(
        encoding="utf-8"
    )
    return parse_catalog(markdown)


def test_given_valid_example_when_validated_then_has_no_errors() -> None:
    # Arrange
    data = _valid_catalog()

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors == []


def test_given_example_when_inspected_then_covers_full_relationship_surface() -> None:
    # Arrange
    data = _valid_catalog()
    relationships = data["relationships"]

    # Act
    confidences = {relationship["confidence"] for relationship in relationships}
    scalar = [
        relationship
        for relationship in relationships
        if isinstance(relationship["join_keys"]["from_field"], str)
    ]
    composite = [
        relationship
        for relationship in relationships
        if isinstance(relationship["join_keys"]["from_field"], list)
    ]
    minimums = {
        (relationship["from_minimum"], relationship["to_minimum"])
        for relationship in relationships
    }

    # Assert
    assert confidences == {"confirmed", "inferred", "assumed"}
    assert scalar and composite
    assert {"zero", "one"} <= {value for pair in minimums for value in pair}


def test_given_scalar_join_keys_when_validated_then_has_no_errors() -> None:
    # Arrange
    data = _valid_catalog()
    relationship = data["relationships"][0]
    relationship["join_keys"] = {
        "from_field": "customer_id",
        "to_field": "customer_id",
    }

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors == []


def test_given_duplicate_entity_id_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    duplicate = copy.deepcopy(data["entities"][0])
    data["entities"].append(duplicate)
    data["coverage"]["entities_catalogued"] += 1
    data["coverage"]["entities_access_confirmed"] += 1
    data["coverage"]["entities_classified"] += 1

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert "entity IDs must be unique" in errors


def test_given_unknown_endpoint_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["to"] = "missing"

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert any("unknown to endpoint" in error for error in errors)


def test_given_unknown_and_self_lineage_when_validated_then_reports_errors() -> None:
    # Arrange
    data = _valid_catalog()
    data["entities"][0]["lineage"]["derived_from"] = ["missing", "customer"]

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert any("unknown lineage source" in error for error in errors)
    assert any("cannot derive from itself" in error for error in errors)


def test_given_unequal_composite_keys_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["join_keys"]["to_field"].pop()

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert any("equal length" in error for error in errors)


def test_given_duplicate_relationship_id_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    duplicate = copy.deepcopy(data["relationships"][0])
    data["relationships"].append(duplicate)
    data["coverage"]["relationships_confirmed"] += 1

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert "relationship IDs must be unique" in errors


def test_given_unknown_property_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["cardinallity"] = "one-to-many"

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


@pytest.mark.parametrize(
    "join_keys",
    [
        {"from_field": "customer_id", "to_field": ["customer_id"]},
        {"from_field": [], "to_field": []},
        {"from_field": [1], "to_field": ["customer_id"]},
        {"from_field": "", "to_field": "customer_id"},
    ],
    ids=["mixed-forms", "empty-arrays", "non-string-value", "empty-string"],
)
def test_given_malformed_join_keys_when_validated_then_reports_error(
    join_keys: dict,
) -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["join_keys"] = join_keys

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


@pytest.mark.parametrize(
    "mutation",
    [
        {"from_minimum": None},
        {"to_minimum": None},
        {"from_minimum": "zero", "to_minimum": "maybe"},
        {"from_minimum": "0", "to_minimum": "one"},
    ],
    ids=["omitted-from", "omitted-to", "invalid-to", "invalid-from"],
)
def test_given_bad_endpoint_minimum_when_validated_then_reports_error(
    mutation: dict,
) -> None:
    # Arrange
    data = _valid_catalog()
    relationship = data["relationships"][0]
    for field, value in mutation.items():
        if value is None:
            relationship.pop(field)
        else:
            relationship[field] = value

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


@pytest.mark.parametrize("confidence", ["confirmed", "inferred", "assumed"])
def test_given_each_confidence_when_validated_then_coverage_must_match(
    confidence: str,
) -> None:
    # Arrange
    data = _valid_catalog()
    for relationship in data["relationships"]:
        relationship["confidence"] = confidence
        relationship["basis"] = "Recorded evidence for this relationship"
    total = len(data["relationships"])
    data["coverage"]["relationships_confirmed"] = (
        total if confidence == "confirmed" else 0
    )
    data["coverage"]["relationships_inferred"] = (
        total if confidence == "inferred" else 0
    )

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors == []


def test_given_invalid_confidence_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["confidence"] = "likely"

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


def test_given_empty_basis_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["relationships"][0]["basis"] = ""

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


def test_given_bad_coverage_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["coverage"]["entities_catalogued"] = 99

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert any("entities_catalogued" in error for error in errors)


def test_given_mixed_confidence_coverage_when_validated_then_reports_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["coverage"]["relationships_inferred"] = 0

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert any("relationships_inferred" in error for error in errors)


def test_given_duplicate_yaml_key_when_parsed_then_raises() -> None:
    # Arrange
    markdown = "---\ncatalog_version: DS_CATALOG_V1\ncatalog_version: bad\n---\n"

    # Act and assert
    with pytest.raises(CatalogValidationError, match="duplicate YAML key"):
        parse_catalog(markdown)


def test_given_missing_frontmatter_when_extracted_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogValidationError, match="must start"):
        extract_frontmatter("# Catalog\n")


def test_given_unclosed_frontmatter_when_extracted_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogValidationError, match="not closed"):
        extract_frontmatter("---\ncatalog_version: DS_CATALOG_V1\n")


def test_given_schema_violation_when_validated_then_returns_error() -> None:
    # Arrange
    data = _valid_catalog()
    data["catalog_version"] = "DS_CATALOG_V2"

    # Act
    errors = validate_catalog(data, load_schema(SKILL_ROOT))

    # Assert
    assert errors


def test_given_valid_file_when_run_then_returns_success(capsys) -> None:
    # Arrange
    path = SKILL_ROOT / "examples" / "northwind-catalog.md"

    # Act
    result = run(path)

    # Assert
    assert result == 0
    assert '"valid": true' in capsys.readouterr().out


def test_given_missing_file_when_run_then_returns_error(tmp_path, capsys) -> None:
    # Act
    result = run(tmp_path / "missing.md")

    # Assert
    assert result == 2
    assert '"valid": false' in capsys.readouterr().out
