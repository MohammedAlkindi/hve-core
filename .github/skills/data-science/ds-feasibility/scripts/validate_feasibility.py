#!/usr/bin/env python3
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Validate Feasibility Study Interchange Profile Markdown artifacts."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, FormatChecker

EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_ERROR = 2
BEGIN_MARKER = "<!-- BEGIN FEASIBILITY-STUDY-INTERCHANGE -->"
END_MARKER = "<!-- END FEASIBILITY-STUDY-INTERCHANGE -->"
BLOCK_PATTERN = re.compile(
    re.escape(BEGIN_MARKER)
    + r"\s*```yaml\s*(.*?)\s*```\s*"
    + re.escape(END_MARKER),
    re.DOTALL,
)
PROHIBITED_YAML_PATTERN = re.compile(
    r"(^|[\s\[{,])(?:&[A-Za-z0-9_-]+|\*[A-Za-z0-9_-]+|<<\s*:|![^\s]+)",
    re.MULTILINE,
)
ALLOCATED_REQUIREMENT_PATTERN = re.compile(r"\b(?:FR|NFR)-[0-9]{3,}\b")
NARRATIVE_ANCHOR_PATTERN = re.compile(r"^###\s+(FS-[0-9]{3,})(?::|\s|$)", re.MULTILINE)


class FeasibilityValidationError(ValueError):
    """Raised when the profile block cannot be parsed safely."""


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
            raise FeasibilityValidationError("YAML keys must be strings")
        if key in mapping:
            raise FeasibilityValidationError(f"duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_unique_mapping
)


def extract_profile_yaml(markdown: str) -> str:
    """Extract the one authoritative profile block."""
    blocks = BLOCK_PATTERN.findall(markdown)
    if len(blocks) != 1:
        raise FeasibilityValidationError(
            "study must contain exactly one named FEASIBILITY-STUDY-INTERCHANGE block"
        )
    yaml_text = blocks[0]
    if PROHIBITED_YAML_PATTERN.search(yaml_text):
        raise FeasibilityValidationError(
            "profile YAML cannot use anchors, aliases, merge keys, or custom tags"
        )
    return yaml_text


def _assert_json_compatible(value: Any, path: str = "$") -> None:
    """Reject YAML-native values outside the JSON data model."""
    if value is None or isinstance(value, (str, int, float, bool)):
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _assert_json_compatible(item, f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise FeasibilityValidationError(f"{path} has a non-string key")
            _assert_json_compatible(item, f"{path}.{key}")
        return
    if isinstance(value, (dt.date, dt.datetime)):
        raise FeasibilityValidationError(f"{path} timestamp must be quoted")
    raise FeasibilityValidationError(
        f"{path} contains non-JSON YAML value {type(value).__name__}"
    )


def parse_profile(markdown: str) -> dict[str, Any]:
    """Parse the constrained YAML profile block."""
    try:
        parsed = yaml.load(extract_profile_yaml(markdown), Loader=UniqueKeyLoader)
    except yaml.YAMLError as error:
        raise FeasibilityValidationError(f"invalid YAML: {error}") from error
    if not isinstance(parsed, dict):
        raise FeasibilityValidationError("profile block must parse to an object")
    _assert_json_compatible(parsed)
    return parsed


def load_schema(skill_root: Path) -> dict[str, Any]:
    """Load the local profile schema."""
    schema_path = (
        skill_root
        / "assets"
        / "feasibility-study-interchange-1.0.0.schema.json"
    )
    return json.loads(schema_path.read_text(encoding="utf-8"))


def _duplicates(values: list[str]) -> set[str]:
    """Return duplicated strings."""
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return duplicates


def _find_cycles(parents: dict[str, str | None]) -> list[str]:
    """Return revision IDs participating in parent cycles."""
    cycles: set[str] = set()
    for start in parents:
        path: list[str] = []
        current: str | None = start
        while current is not None and current in parents:
            if current in path:
                cycles.update(path[path.index(current) :])
                break
            path.append(current)
            current = parents[current]
    return sorted(cycles)


def validate_profile(
    data: dict[str, Any], markdown: str, schema: dict[str, Any]
) -> list[str]:
    """Return structural, semantic, and Markdown-linkage errors."""
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = [error.message for error in sorted(validator.iter_errors(data), key=str)]
    if errors:
        return errors

    study = data["study"]
    items = data["items"]
    registry = data["revision_registry"]
    item_by_id = {item["item_id"]: item for item in items}

    concept_ids = [study["study_id"], *(item["item_id"] for item in items)]
    relation_ids = [
        relation["relation_id"]
        for item in items
        for relation in item["relations"]
    ]
    current_revision_ids = [
        study["study_revision_id"],
        *(item["item_revision_id"] for item in items),
    ]
    registry_revision_ids = [entry["revision_id"] for entry in registry]

    for label, values in (
        ("conceptual IDs", concept_ids),
        ("relation IDs", relation_ids),
        ("revision registry IDs", registry_revision_ids),
    ):
        duplicates = _duplicates(values)
        if duplicates:
            errors.append(f"{label} must be unique: {', '.join(sorted(duplicates))}")

    collisions = (set(concept_ids) | set(relation_ids)) & set(registry_revision_ids)
    if collisions:
        errors.append(
            "concept, relation, and revision identities must be disjoint: "
            + ", ".join(sorted(collisions))
        )

    registry_by_revision = {entry["revision_id"]: entry for entry in registry}
    for revision_id in current_revision_ids:
        if revision_id not in registry_by_revision:
            errors.append(f"current revision is absent from registry: {revision_id}")

    current_pairs = [
        (study["study_id"], study["study_revision_id"], study["revision_of"]),
        *(
            (item["item_id"], item["item_revision_id"], item["revision_of"])
            for item in items
        ),
    ]
    for concept_id, revision_id, revision_of in current_pairs:
        entry = registry_by_revision.get(revision_id)
        if entry and (
            entry["concept_id"] != concept_id or entry["revision_of"] != revision_of
        ):
            errors.append(
                f"current revision metadata disagrees with registry: {revision_id}"
            )

    revisions_by_concept: dict[str, set[str]] = {}
    for entry in registry:
        revisions_by_concept.setdefault(entry["concept_id"], set()).add(
            entry["revision_id"]
        )
    for entry in registry:
        parent = entry["revision_of"]
        known_revisions = revisions_by_concept[entry["concept_id"]]
        if parent is not None and parent not in known_revisions:
            errors.append(
                f"revision {entry['revision_id']} points outside its concept lineage"
            )
    cycles = _find_cycles(
        {entry["revision_id"]: entry["revision_of"] for entry in registry}
    )
    if cycles:
        errors.append("revision lineage is cyclic: " + ", ".join(cycles))

    known_items = set(item_by_id)
    for item in items:
        if item["display_ref"].lower() != item["narrative_anchor"]:
            errors.append(
                f"{item['display_ref']} narrative_anchor must match its alias"
            )
        review = item["review"]
        if review["needs_review"] != bool(review["reasons"]):
            errors.append(
                f"{item['display_ref']} review reasons must match needs_review"
            )
        criteria = item["acceptance_criteria"]
        if item["criteria_status"] == "defined" and not criteria:
            errors.append(f"{item['display_ref']} defined criteria cannot be empty")
        empty_statuses = {"not-yet-defined", "not-applicable"}
        if item["criteria_status"] in empty_statuses and criteria:
            errors.append(
                f"{item['display_ref']} criteria must be empty for "
                f"{item['criteria_status']}"
            )

        for evidence_id in item["evidence_refs"]:
            evidence = item_by_id.get(evidence_id)
            if evidence is None:
                errors.append(f"{item['display_ref']} has unknown evidence reference")
            elif evidence["class"] != "evidence":
                errors.append(
                    f"{item['display_ref']} evidence reference does not target evidence"
                )

        relation_types = {relation["type"] for relation in item["relations"]}
        for relation in item["relations"]:
            if relation["target"] not in known_items:
                errors.append(f"relation {relation['relation_id']} has unknown target")
            relation_review = relation["review"]
            if relation_review["needs_review"] != bool(relation_review["reasons"]):
                errors.append(
                    f"relation {relation['relation_id']} review reasons "
                    "are inconsistent"
                )

        lifecycle = item["lifecycle"]
        for target in lifecycle["predecessor_ids"] + lifecycle["successor_ids"]:
            if target not in known_items:
                errors.append(
                    f"{item['display_ref']} lifecycle target is unknown: {target}"
                )
        if item["status"] in {"withdrawn", "superseded"}:
            if lifecycle["effective_at"] is None or not lifecycle["reason"]:
                errors.append(
                    f"{item['display_ref']} has an incomplete "
                    f"{item['status']} tombstone"
                )
        if item["status"] == "superseded" and not lifecycle["successor_ids"]:
            errors.append(
                f"{item['display_ref']} superseded tombstone needs a successor"
            )
        if "split-from" in relation_types and not lifecycle["predecessor_ids"]:
            errors.append(f"{item['display_ref']} split lineage needs a predecessor")
        if "merged-from" in relation_types and len(lifecycle["predecessor_ids"]) < 2:
            errors.append(f"{item['display_ref']} merge lineage needs two predecessors")

    expected_anchors = {item["display_ref"] for item in items}
    actual_anchors = NARRATIVE_ANCHOR_PATTERN.findall(markdown)
    duplicate_anchors = _duplicates(actual_anchors)
    if duplicate_anchors:
        errors.append(
            "duplicate narrative anchors: " + ", ".join(sorted(duplicate_anchors))
        )
    missing_anchors = expected_anchors - set(actual_anchors)
    unknown_anchors = set(actual_anchors) - expected_anchors
    if missing_anchors:
        errors.append("orphaned YAML items: " + ", ".join(sorted(missing_anchors)))
    if unknown_anchors:
        errors.append(
            "unknown narrative anchors: " + ", ".join(sorted(unknown_anchors))
        )
    if ALLOCATED_REQUIREMENT_PATTERN.search(markdown):
        errors.append("feasibility studies cannot allocate FR or NFR identifiers")
    return errors


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(
        description="Validate a Feasibility Study Interchange Profile"
    )
    parser.add_argument("study", type=Path, help="Markdown study to validate")
    return parser


def run(study_path: Path) -> int:
    """Validate one study and print a JSON result."""
    skill_root = Path(__file__).resolve().parent.parent
    try:
        markdown = study_path.read_text(encoding="utf-8")
        data = parse_profile(markdown)
        errors = validate_profile(data, markdown, load_schema(skill_root))
    except (OSError, FeasibilityValidationError, json.JSONDecodeError) as error:
        print(json.dumps({"valid": False, "errors": [str(error)]}, indent=2))
        return EXIT_ERROR

    print(json.dumps({"valid": not errors, "errors": errors}, indent=2))
    return EXIT_FAILURE if errors else EXIT_SUCCESS


def main() -> int:
    """Run the feasibility profile validator CLI."""
    return run(create_parser().parse_args().study)


if __name__ == "__main__":
    sys.exit(main())
