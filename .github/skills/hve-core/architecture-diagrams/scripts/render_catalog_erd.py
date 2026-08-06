#!/usr/bin/env python3
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Render a declared DS_CATALOG_V1 model as Mermaid or ASCII.

Usage:
    uv run python scripts/render_catalog_erd.py catalog.md --format mermaid
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Any

import yaml

EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_ERROR = 2

CONFIDENCE_VALUES = ("confirmed", "inferred", "assumed")
MINIMUM_VALUES = ("zero", "one")

# Maximum multiplicity for each endpoint, derived from the declared cardinality.
CARDINALITY_MAXIMUMS = {
    "one-to-one": ("one", "one"),
    "one-to-many": ("one", "many"),
    "many-to-many": ("many", "many"),
}

# Mermaid erDiagram notation keyed by (minimum, maximum). The left form mirrors
# the right so each marker points away from the entity it constrains.
MERMAID_LEFT = {
    ("zero", "one"): "|o",
    ("one", "one"): "||",
    ("zero", "many"): "}o",
    ("one", "many"): "}|",
}
MERMAID_RIGHT = {
    ("zero", "one"): "o|",
    ("one", "one"): "||",
    ("zero", "many"): "o{",
    ("one", "many"): "|{",
}
ASCII_MULTIPLICITY = {
    ("zero", "one"): "0..1",
    ("one", "one"): "1",
    ("zero", "many"): "0..*",
    ("one", "many"): "1..*",
}


class CatalogRenderError(ValueError):
    """Raised when a catalog cannot be rendered safely."""


class UniqueKeyLoader(yaml.SafeLoader):
    """YAML loader that rejects duplicate mapping keys."""


def _construct_unique_mapping(
    loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False
) -> dict[str, Any]:
    """Construct one mapping while rejecting duplicate keys."""
    mapping: dict[str, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if not isinstance(key, str):
            raise CatalogRenderError("catalog YAML keys must be strings")
        if key in mapping:
            raise CatalogRenderError(f"duplicate catalog YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_unique_mapping
)


def extract_frontmatter(markdown: str) -> str:
    """Extract YAML frontmatter from a Markdown catalog."""
    lines = markdown.splitlines()
    if not lines or lines[0] != "---":
        raise CatalogRenderError("catalog must start with YAML frontmatter")
    try:
        closing = lines.index("---", 1)
    except ValueError as error:
        raise CatalogRenderError("catalog frontmatter is not closed") from error
    return "\n".join(lines[1:closing])


def parse_catalog(markdown: str) -> dict[str, Any]:
    """Parse a catalog and reject every malformed rendering-critical fact."""
    try:
        data = yaml.load(extract_frontmatter(markdown), Loader=UniqueKeyLoader)
    except yaml.YAMLError as error:
        raise CatalogRenderError(f"invalid catalog YAML: {error}") from error
    if not isinstance(data, dict):
        raise CatalogRenderError("catalog frontmatter must be an object")
    if data.get("catalog_version") != "DS_CATALOG_V1":
        raise CatalogRenderError("unsupported catalog_version; expected DS_CATALOG_V1")

    entities = data.get("entities")
    relationships = data.get("relationships")
    if not isinstance(entities, list) or not isinstance(relationships, list):
        raise CatalogRenderError("catalog entities and relationships must be arrays")

    entity_ids: set[str] = set()
    node_ids: dict[str, str] = {}
    for entity in entities:
        if not isinstance(entity, dict):
            raise CatalogRenderError("every catalog entity must be an object")
        entity_id = _require_nonempty_string(entity.get("id"), "entity id")
        _require_nonempty_string(entity.get("name"), f"entity {entity_id} name")
        if entity_id in entity_ids:
            raise CatalogRenderError(f"duplicate catalog entity id: {entity_id}")
        node = _node_id(entity_id)
        if node in node_ids:
            raise CatalogRenderError(
                f"entity ids {node_ids[node]} and {entity_id} collide as "
                "Mermaid identifiers"
            )
        entity_ids.add(entity_id)
        node_ids[node] = entity_id

    relationship_ids: set[str] = set()
    for relationship in relationships:
        if not isinstance(relationship, dict):
            raise CatalogRenderError("every catalog relationship must be an object")
        relationship_id = _require_nonempty_string(
            relationship.get("id"), "relationship id"
        )
        if relationship_id in relationship_ids:
            raise CatalogRenderError(
                f"duplicate catalog relationship id: {relationship_id}"
            )
        relationship_ids.add(relationship_id)

        if (
            relationship.get("from") not in entity_ids
            or relationship.get("to") not in entity_ids
        ):
            raise CatalogRenderError(
                f"relationship {relationship_id} endpoints must resolve "
                "declared entities"
            )
        if relationship.get("cardinality") not in CARDINALITY_MAXIMUMS:
            raise CatalogRenderError(
                f"relationship {relationship_id} cardinality is unsupported"
            )
        for side in ("from_minimum", "to_minimum"):
            if relationship.get(side) not in MINIMUM_VALUES:
                raise CatalogRenderError(
                    f"relationship {relationship_id} {side} must be 'zero' or 'one'"
                )
        if relationship.get("confidence") not in CONFIDENCE_VALUES:
            raise CatalogRenderError(
                f"relationship {relationship_id} confidence is unsupported"
            )
        _require_nonempty_string(
            relationship.get("basis"), f"relationship {relationship_id} basis"
        )
        _validate_join_keys(relationship.get("join_keys"), relationship_id)
    return data


def _require_nonempty_string(value: Any, description: str) -> str:
    """Return a non-empty string value or raise a render error."""
    if not isinstance(value, str) or not value.strip():
        raise CatalogRenderError(f"{description} must be a non-empty string")
    return value


def _validate_join_keys(join_keys: Any, relationship_id: str) -> list[tuple[str, str]]:
    """Return ordered join-key pairs, rejecting any malformed declaration."""
    if not isinstance(join_keys, dict):
        raise CatalogRenderError(
            f"relationship {relationship_id} join_keys must be an object"
        )
    from_field = join_keys.get("from_field")
    to_field = join_keys.get("to_field")

    if isinstance(from_field, str) and isinstance(to_field, str):
        from_values: list[Any] = [from_field]
        to_values: list[Any] = [to_field]
    elif isinstance(from_field, list) and isinstance(to_field, list):
        from_values = from_field
        to_values = to_field
    else:
        raise CatalogRenderError(
            f"relationship {relationship_id} join keys must both be strings "
            "or both be arrays"
        )

    if not from_values or len(from_values) != len(to_values):
        raise CatalogRenderError(
            f"relationship {relationship_id} join keys must be non-empty and "
            "of equal length"
        )
    pairs = list(zip(from_values, to_values, strict=True))
    for index, (source, target) in enumerate(pairs):
        _require_nonempty_string(
            source, f"relationship {relationship_id} from_field[{index}]"
        )
        _require_nonempty_string(
            target, f"relationship {relationship_id} to_field[{index}]"
        )
    return pairs


def _node_id(entity_id: str) -> str:
    """Convert a catalog entity ID into a collision-free Mermaid identifier."""
    escaped = re.sub(
        r"[^a-z0-9]", lambda match: f"_{ord(match.group()):02x}", entity_id.lower()
    )
    return f"entity_{escaped}"


def _quote(value: str) -> str:
    """Make a value safe to embed inside a Mermaid double-quoted string."""
    return value.replace('"', "'")


def _endpoints(relationship: dict[str, Any]) -> tuple[tuple[str, str], tuple[str, str]]:
    """Return the (minimum, maximum) pair for each relationship endpoint."""
    from_max, to_max = CARDINALITY_MAXIMUMS[relationship["cardinality"]]
    return (
        (relationship["from_minimum"], from_max),
        (relationship["to_minimum"], to_max),
    )


def _join_key_label(relationship: dict[str, Any]) -> str:
    """Render ordered join-key pairs without implying a key role."""
    pairs = _validate_join_keys(relationship["join_keys"], relationship["id"])
    return ", ".join(f"{source} = {target}" for source, target in pairs)


def _confidence_suffix(confidence: str) -> str:
    """Return the label suffix for a confidence value."""
    return "" if confidence == "confirmed" else f" ({confidence})"


def _title(data: dict[str, Any]) -> str:
    """Return the catalog output title."""
    engagement = data.get("engagement")
    name = engagement if isinstance(engagement, str) and engagement.strip() else "Catalog"
    return f"## {name} Data Model"


def _key_relationship_lines(data: dict[str, Any]) -> list[str]:
    """Return the Key Relationships section body."""
    entity_by_id = {entity["id"]: entity for entity in data["entities"]}
    if not data["relationships"]:
        return ["No relationships are declared in this catalog."]

    lines = []
    for relationship in data["relationships"]:
        source = entity_by_id[relationship["from"]]["name"]
        target = entity_by_id[relationship["to"]]["name"]
        (from_min, from_max), (to_min, to_max) = _endpoints(relationship)
        lines.append(
            f"* `{relationship['id']}`: {source} "
            f"({ASCII_MULTIPLICITY[from_min, from_max]}) to {target} "
            f"({ASCII_MULTIPLICITY[to_min, to_max]}) on "
            f"{_join_key_label(relationship)}; confidence "
            f"`{relationship['confidence']}` because {relationship['basis']}"
        )
    return lines


def render_mermaid(data: dict[str, Any]) -> str:
    """Render declared entities and relationships as a Mermaid ER diagram."""
    lines = [_title(data), "", "```mermaid", "erDiagram"]

    attributes: dict[str, list[str]] = {entity["id"]: [] for entity in data["entities"]}
    for relationship in data["relationships"]:
        for source, target in _validate_join_keys(
            relationship["join_keys"], relationship["id"]
        ):
            attributes[relationship["from"]].append(source)
            attributes[relationship["to"]].append(target)

    for entity in data["entities"]:
        lines.append(f'    {_node_id(entity["id"])}["{_quote(entity["name"])}"] {{')
        seen: set[str] = set()
        for field in attributes[entity["id"]]:
            if field not in seen:
                seen.add(field)
                lines.append(f"        string {field}")
        lines.append("    }")

    for relationship in data["relationships"]:
        (from_min, from_max), (to_min, to_max) = _endpoints(relationship)
        notation = (
            f"{MERMAID_LEFT[from_min, from_max]}--{MERMAID_RIGHT[to_min, to_max]}"
        )
        label = _join_key_label(relationship) + _confidence_suffix(
            relationship["confidence"]
        )
        lines.append(
            f'    {_node_id(relationship["from"])} {notation} '
            f'{_node_id(relationship["to"])} : "{_quote(label)}"'
        )
    lines.append("```")

    lines.extend(
        [
            "",
            "### Legend",
            "",
            "* `||` requires exactly one, `|o` allows zero or one, `}|` requires "
            "one or many, and `}o` allows zero or many on that side.",
            "* Attributes list declared join-key field names only. They do not "
            "declare primary keys, foreign keys, or uniqueness.",
            "* Labels show the declared join-key pairing. An unmarked label is "
            "`confirmed`; `(inferred)` and `(assumed)` mark unconfirmed "
            "relationships.",
            "* All connectors are solid. Identifying and non-identifying "
            "semantics are not modelled by this catalog.",
            "",
            "### Key Relationships",
            "",
        ]
    )
    lines.extend(_key_relationship_lines(data))
    return "\n".join(lines) + "\n"


def render_ascii(data: dict[str, Any]) -> str:
    """Render declared entities and relationships as compact ASCII."""
    lines = [_title(data), "", "```text", "Entities:"]
    for entity in data["entities"]:
        lines.append(f'  [{entity["name"]}] ({entity["id"]})')

    lines.extend(["", "Relationships:"])
    if data["relationships"]:
        for relationship in data["relationships"]:
            (from_min, from_max), (to_min, to_max) = _endpoints(relationship)
            label = _join_key_label(relationship) + _confidence_suffix(
                relationship["confidence"]
            )
            lines.append(
                f'  [{relationship["from"]}] '
                f"{ASCII_MULTIPLICITY[from_min, from_max]} --- "
                f"{ASCII_MULTIPLICITY[to_min, to_max]} "
                f'[{relationship["to"]}] : {label}'
            )
    else:
        lines.append("  No relationships are declared in this catalog.")
    lines.append("```")

    lines.extend(
        [
            "",
            "### Legend",
            "",
            "* `1` requires exactly one, `0..1` allows zero or one, `1..*` "
            "requires one or many, and `0..*` allows zero or many on that side.",
            "* Each multiplicity sits beside the entity it constrains.",
            "* Join-key pairs show declared field names only. They do not declare "
            "primary keys, foreign keys, or uniqueness.",
            "* An unmarked relationship is `confirmed`; `(inferred)` and "
            "`(assumed)` mark unconfirmed relationships.",
            "",
            "### Key Relationships",
            "",
        ]
    )
    lines.extend(_key_relationship_lines(data))
    return "\n".join(lines) + "\n"


def create_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(
        description="Render declared DS_CATALOG_V1 relationships as an ERD"
    )
    parser.add_argument("catalog", type=Path, help="DS_CATALOG_V1 Markdown catalog")
    parser.add_argument(
        "--format",
        choices=("ascii", "mermaid"),
        required=True,
        help="Caller-selected output format",
    )
    return parser


def run(catalog_path: Path, output_format: str) -> int:
    """Read one catalog and print its ERD."""
    try:
        data = parse_catalog(catalog_path.read_text(encoding="utf-8"))
        rendered = (
            render_mermaid(data) if output_format == "mermaid" else render_ascii(data)
        )
    except (OSError, CatalogRenderError) as error:
        print(f"render_catalog_erd: {error}", file=sys.stderr)
        return EXIT_ERROR
    print(rendered, end="")
    return EXIT_SUCCESS


def main() -> int:
    """Run the catalog ERD renderer."""
    args = create_parser().parse_args()
    return run(args.catalog, args.format)


if __name__ == "__main__":
    sys.exit(main())
