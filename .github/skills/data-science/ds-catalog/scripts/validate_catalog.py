#!/usr/bin/env python3
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Validate DS_CATALOG_V1 Markdown artifacts.

Usage:
    uv run python scripts/validate_catalog.py examples/northwind-catalog.md
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, FormatChecker

EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_ERROR = 2


class CatalogValidationError(ValueError):
    """Raised when a catalog violates the DS_CATALOG_V1 contract."""


class UniqueKeyLoader(yaml.SafeLoader):
    """YAML loader that rejects duplicate mapping keys."""


def _construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[str, Any]:
    """Construct a mapping while rejecting duplicate keys."""
    mapping: dict[str, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str):
            raise CatalogValidationError("YAML keys must be strings")
        if key in mapping:
            raise CatalogValidationError(f"duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_unique_mapping
)


def extract_frontmatter(markdown: str) -> str:
    """Extract YAML frontmatter from a Markdown catalog."""
    lines = markdown.splitlines()
    if not lines or lines[0] != "---":
        raise CatalogValidationError("catalog must start with YAML frontmatter")
    try:
        closing = lines.index("---", 1)
    except ValueError as error:
        raise CatalogValidationError("catalog frontmatter is not closed") from error
    return "\n".join(lines[1:closing])


def parse_catalog(markdown: str) -> dict[str, Any]:
    """Parse catalog frontmatter with duplicate-key protection."""
    try:
        parsed = yaml.load(extract_frontmatter(markdown), Loader=UniqueKeyLoader)
    except yaml.YAMLError as error:
        raise CatalogValidationError(f"invalid YAML: {error}") from error
    if not isinstance(parsed, dict):
        raise CatalogValidationError("catalog frontmatter must be an object")
    return parsed


def load_schema(skill_root: Path) -> dict[str, Any]:
    """Load the bundled DS_CATALOG_V1 schema."""
    schema_path = skill_root / "assets" / "ds-catalog-v1.schema.json"
    return json.loads(schema_path.read_text(encoding="utf-8"))


def validate_catalog(data: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    """Return structural and semantic catalog errors."""
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = [error.message for error in sorted(validator.iter_errors(data), key=str)]
    if errors:
        return errors

    entities = data["entities"]
    relationships = data["relationships"]
    entity_ids = [entity["id"] for entity in entities]
    relationship_ids = [relationship["id"] for relationship in relationships]

    if len(entity_ids) != len(set(entity_ids)):
        errors.append("entity IDs must be unique")
    if len(relationship_ids) != len(set(relationship_ids)):
        errors.append("relationship IDs must be unique")

    known_entities = set(entity_ids)
    for entity in entities:
        for source_id in entity["lineage"]["derived_from"]:
            if source_id not in known_entities:
                errors.append(
                    f"entity {entity['id']} has unknown lineage source {source_id}"
                )
        if entity["id"] in entity["lineage"]["derived_from"]:
            errors.append(f"entity {entity['id']} cannot derive from itself")

    for relationship in relationships:
        for endpoint in ("from", "to"):
            if relationship[endpoint] not in known_entities:
                errors.append(
                    f"relationship {relationship['id']} has unknown {endpoint} endpoint"
                )
        join_keys = relationship["join_keys"]
        if isinstance(join_keys["from_field"], list) and len(
            join_keys["from_field"]
        ) != len(join_keys["to_field"]):
            errors.append(
                f"relationship {relationship['id']} composite join keys "
                "must have equal length"
            )

    coverage = data["coverage"]
    classified = sum(
        entity["classification"]["sensitivity"] != "none"
        or any(
            entity["classification"][field] is not None
            for field in (
                "gdpr_article",
                "ccpa_section",
                "nist_pf_category",
                "nistir8062_objective",
                "owasp_privacy_id",
            )
        )
        for entity in entities
    )
    expected = {
        "entities_catalogued": len(entities),
        "entities_access_confirmed": sum(
            entity["source"]["access_confirmed"] for entity in entities
        ),
        "entities_classified": classified,
        "relationships_confirmed": sum(
            relationship["confidence"] == "confirmed"
            for relationship in relationships
        ),
        "relationships_inferred": sum(
            relationship["confidence"] == "inferred"
            for relationship in relationships
        ),
    }
    for field, expected_value in expected.items():
        if coverage[field] != expected_value:
            errors.append(
                f"coverage.{field} is {coverage[field]}, expected {expected_value}"
            )
    return errors


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(description="Validate a DS_CATALOG_V1 catalog")
    parser.add_argument("catalog", type=Path, help="Markdown catalog to validate")
    return parser


def run(catalog_path: Path) -> int:
    """Validate one catalog and print a JSON result."""
    skill_root = Path(__file__).resolve().parent.parent
    try:
        markdown = catalog_path.read_text(encoding="utf-8")
        data = parse_catalog(markdown)
        errors = validate_catalog(data, load_schema(skill_root))
    except (OSError, CatalogValidationError, json.JSONDecodeError) as error:
        print(json.dumps({"valid": False, "errors": [str(error)]}, indent=2))
        return EXIT_ERROR

    print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
    return EXIT_FAILURE if errors else EXIT_SUCCESS


def main() -> int:
    """Run the catalog validator CLI."""
    return run(create_parser().parse_args().catalog)


if __name__ == "__main__":
    sys.exit(main())
