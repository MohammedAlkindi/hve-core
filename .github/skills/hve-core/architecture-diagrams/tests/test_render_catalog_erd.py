# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for catalog-driven ERD rendering."""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any

import pytest
import yaml
from render_catalog_erd import (
    CatalogRenderError,
    parse_catalog,
    render_ascii,
    render_mermaid,
    run,
)

REPO_ROOT = Path(__file__).resolve().parents[5]
CATALOG_FIXTURE = (
    REPO_ROOT
    / ".github"
    / "skills"
    / "data-science"
    / "ds-catalog"
    / "examples"
    / "northwind-catalog.md"
)


def _catalog() -> dict:
    return copy.deepcopy(parse_catalog(CATALOG_FIXTURE.read_text(encoding="utf-8")))


def _to_markdown(data: dict) -> str:
    """Serialize a catalog dictionary into Markdown frontmatter."""
    return f"---\n{yaml.safe_dump(data, sort_keys=False)}---\n"


def _minimal(**overrides: Any) -> dict:
    """Build a two-entity catalog with one overridable relationship."""
    relationship: dict[str, Any] = {
        "id": "rel-a-b",
        "from": "alpha",
        "to": "beta",
        "cardinality": "one-to-many",
        "from_minimum": "one",
        "to_minimum": "zero",
        "join_keys": {"from_field": "alpha_id", "to_field": "alpha_id"},
        "confidence": "confirmed",
        "basis": "Confirmed by the data owner",
    }
    relationship.update(overrides)
    return {
        "catalog_version": "DS_CATALOG_V1",
        "engagement": "demo",
        "entities": [
            {"id": "alpha", "name": "Alpha"},
            {"id": "beta", "name": "Beta"},
        ],
        "relationships": [relationship],
    }


@pytest.mark.parametrize("renderer", [render_mermaid, render_ascii])
def test_given_catalog_when_rendered_then_document_sections_are_present(
    renderer,
) -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = renderer(data)

    # Assert
    assert rendered.startswith("## northwind-modernization Data Model")
    assert "### Legend" in rendered
    assert "### Key Relationships" in rendered


@pytest.mark.parametrize("renderer", [render_mermaid, render_ascii])
def test_given_catalog_when_rendered_then_every_declared_fact_survives(
    renderer,
) -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = renderer(data)

    # Assert
    for entity in data["entities"]:
        assert entity["name"] in rendered
    for relationship in data["relationships"]:
        assert relationship["id"] in rendered
        assert relationship["basis"] in rendered


def test_given_catalog_when_rendered_as_mermaid_then_uses_er_diagram() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_mermaid(data)

    # Assert
    assert "```mermaid" in rendered
    assert "erDiagram" in rendered
    assert "flowchart" not in rendered


def test_given_catalog_when_rendered_as_ascii_then_no_mermaid_block() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_ascii(data)

    # Assert
    assert "```mermaid" not in rendered
    assert "```text" in rendered


@pytest.mark.parametrize(
    ("cardinality", "from_minimum", "to_minimum", "notation"),
    [
        ("one-to-one", "one", "one", "||--||"),
        ("one-to-one", "zero", "zero", "|o--o|"),
        ("one-to-many", "one", "zero", "||--o{"),
        ("one-to-many", "zero", "one", "|o--|{"),
        ("many-to-many", "one", "one", "}|--|{"),
        ("many-to-many", "zero", "zero", "}o--o{"),
    ],
)
def test_given_multiplicity_when_rendered_as_mermaid_then_notation_matches(
    cardinality: str, from_minimum: str, to_minimum: str, notation: str
) -> None:
    # Arrange
    data = _minimal(
        cardinality=cardinality,
        from_minimum=from_minimum,
        to_minimum=to_minimum,
    )

    # Act
    rendered = render_mermaid(data)

    # Assert
    assert f"entity_alpha {notation} entity_beta" in rendered


@pytest.mark.parametrize(
    ("cardinality", "from_minimum", "to_minimum", "notation"),
    [
        ("one-to-one", "one", "one", "1 --- 1"),
        ("one-to-one", "zero", "zero", "0..1 --- 0..1"),
        ("one-to-many", "one", "zero", "1 --- 0..*"),
        ("many-to-many", "zero", "one", "0..* --- 1..*"),
    ],
)
def test_given_multiplicity_when_rendered_as_ascii_then_notation_matches(
    cardinality: str, from_minimum: str, to_minimum: str, notation: str
) -> None:
    # Arrange
    data = _minimal(
        cardinality=cardinality,
        from_minimum=from_minimum,
        to_minimum=to_minimum,
    )

    # Act
    rendered = render_ascii(data)

    # Assert
    assert notation in rendered


@pytest.mark.parametrize("renderer", [render_mermaid, render_ascii])
def test_given_confirmed_relationship_when_rendered_then_label_is_unmarked(
    renderer,
) -> None:
    # Arrange
    data = _minimal(confidence="confirmed")

    # Act
    rendered = renderer(data)

    # Assert
    assert "(confirmed)" not in rendered
    assert "alpha_id = alpha_id" in rendered


@pytest.mark.parametrize("renderer", [render_mermaid, render_ascii])
@pytest.mark.parametrize("confidence", ["inferred", "assumed"])
def test_given_unconfirmed_relationship_when_rendered_then_label_is_suffixed(
    renderer, confidence: str
) -> None:
    # Arrange
    data = _minimal(confidence=confidence)

    # Act
    rendered = renderer(data)

    # Assert
    assert f"alpha_id = alpha_id ({confidence})" in rendered


def test_given_composite_keys_when_rendered_then_order_is_preserved() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_mermaid(data)

    # Assert
    assert "tenant_id = tenant_id, customer_id = customer_id" in rendered


def test_given_scalar_keys_when_rendered_then_pairing_is_visible() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_ascii(data)

    # Assert
    assert "customer_id = account_ref" in rendered


def test_given_catalog_when_rendered_as_mermaid_then_keys_are_role_neutral() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_mermaid(data)

    # Assert
    assert "catalog_id" not in rendered
    assert " PK" not in rendered
    assert " FK" not in rendered
    assert "        string tenant_id" in rendered


def test_given_repeated_join_key_when_rendered_then_attribute_is_deduplicated() -> None:
    # Arrange
    data = _catalog()

    # Act
    rendered = render_mermaid(data)
    block = rendered.split('entity_sales_2dorder_2dline["Sales Order Line"]')[1]
    block = block.split("    }")[0]

    # Assert
    assert block.count("string tenant_id") == 1


@pytest.mark.parametrize("renderer", [render_mermaid, render_ascii])
def test_given_no_relationships_when_rendered_then_entities_and_notice_appear(
    renderer,
) -> None:
    # Arrange
    data = _minimal()
    data["relationships"] = []

    # Act
    rendered = renderer(data)

    # Assert
    assert "Alpha" in rendered
    assert "Beta" in rendered
    assert "No relationships are declared in this catalog." in rendered


def test_given_unknown_endpoint_when_parsed_then_raises() -> None:
    # Arrange
    markdown = CATALOG_FIXTURE.read_text(encoding="utf-8").replace(
        "to: sales-order-line", "to: missing-entity"
    )

    # Act and assert
    with pytest.raises(CatalogRenderError, match="endpoints"):
        parse_catalog(markdown)


def test_given_unsupported_version_when_parsed_then_raises() -> None:
    # Arrange
    markdown = CATALOG_FIXTURE.read_text(encoding="utf-8").replace(
        "catalog_version: DS_CATALOG_V1", "catalog_version: DS_CATALOG_V2"
    )

    # Act and assert
    with pytest.raises(CatalogRenderError, match="unsupported catalog_version"):
        parse_catalog(markdown)


def test_given_missing_frontmatter_when_parsed_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogRenderError, match="must start"):
        parse_catalog("# Catalog\n")


def test_given_unclosed_frontmatter_when_parsed_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogRenderError, match="not closed"):
        parse_catalog("---\ncatalog_version: DS_CATALOG_V1\n")


def test_given_duplicate_yaml_key_when_parsed_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogRenderError, match="duplicate catalog YAML key"):
        parse_catalog(
            "---\ncatalog_version: DS_CATALOG_V1\ncatalog_version: other\n---\n"
        )


@pytest.mark.parametrize(
    ("overrides", "message"),
    [
        ({"cardinality": "one-to-some"}, "cardinality is unsupported"),
        ({"confidence": "likely"}, "confidence is unsupported"),
        ({"basis": "  "}, "basis must be a non-empty string"),
        ({"id": ""}, "relationship id must be a non-empty string"),
        ({"from_minimum": "maybe"}, "from_minimum must be"),
        ({"to_minimum": 0}, "to_minimum must be"),
    ],
)
def test_given_malformed_relationship_when_parsed_then_raises(
    overrides: dict, message: str
) -> None:
    # Arrange
    data = _minimal(**overrides)

    # Act and assert
    with pytest.raises(CatalogRenderError, match=message):
        parse_catalog(_to_markdown(data))


@pytest.mark.parametrize(
    ("join_keys", "message"),
    [
        ({"from_field": "a", "to_field": ["a"]}, "must both be strings"),
        ({"from_field": [], "to_field": []}, "non-empty"),
        ({"from_field": ["a", "b"], "to_field": ["a"]}, "equal length"),
        ({"from_field": ["a", ""], "to_field": ["a", "b"]}, r"from_field\[1\]"),
        ({"from_field": ["a"], "to_field": [5]}, r"to_field\[0\]"),
        ("not-an-object", "join_keys must be an object"),
    ],
)
def test_given_malformed_join_keys_when_parsed_then_raises(
    join_keys: Any, message: str
) -> None:
    # Arrange
    data = _minimal(join_keys=join_keys)

    # Act and assert
    with pytest.raises(CatalogRenderError, match=message):
        parse_catalog(_to_markdown(data))


def test_given_missing_endpoint_minimum_when_parsed_then_raises() -> None:
    # Arrange
    data = _minimal()
    del data["relationships"][0]["to_minimum"]

    # Act and assert
    with pytest.raises(CatalogRenderError, match="to_minimum must be"):
        parse_catalog(_to_markdown(data))


def test_given_duplicate_entity_id_when_parsed_then_raises() -> None:
    # Arrange
    data = _minimal()
    data["entities"].append({"id": "alpha", "name": "Alpha Again"})

    # Act and assert
    with pytest.raises(CatalogRenderError, match="duplicate catalog entity id"):
        parse_catalog(_to_markdown(data))


def test_given_duplicate_relationship_id_when_parsed_then_raises() -> None:
    # Arrange
    data = _minimal()
    data["relationships"].append(copy.deepcopy(data["relationships"][0]))

    # Act and assert
    with pytest.raises(CatalogRenderError, match="duplicate catalog relationship id"):
        parse_catalog(_to_markdown(data))


def test_given_colliding_entity_ids_when_parsed_then_raises() -> None:
    # Arrange
    data = _minimal()
    data["entities"].append({"id": "Alpha", "name": "Upper Alpha"})

    # Act and assert
    with pytest.raises(CatalogRenderError, match="collide as"):
        parse_catalog(_to_markdown(data))


def test_given_entity_without_name_when_parsed_then_raises() -> None:
    # Arrange
    data = _minimal()
    data["entities"][0].pop("name")

    # Act and assert
    with pytest.raises(CatalogRenderError, match="entity alpha name"):
        parse_catalog(_to_markdown(data))


def test_given_non_object_frontmatter_when_parsed_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogRenderError, match="must be an object"):
        parse_catalog("---\n- one\n- two\n---\n")


def test_given_non_array_entities_when_parsed_then_raises() -> None:
    # Act and assert
    with pytest.raises(CatalogRenderError, match="must be arrays"):
        parse_catalog(
            "---\ncatalog_version: DS_CATALOG_V1\n"
            "entities: {}\nrelationships: []\n---\n"
        )


@pytest.mark.parametrize("output_format", ["mermaid", "ascii"])
def test_given_valid_fixture_when_run_then_returns_success(
    output_format: str, capsys: pytest.CaptureFixture[str]
) -> None:
    # Act
    result = run(CATALOG_FIXTURE, output_format)

    # Assert
    assert result == 0
    assert "Data Model" in capsys.readouterr().out


def test_given_missing_file_when_run_then_returns_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    # Act
    result = run(tmp_path / "missing.md", "mermaid")

    # Assert
    assert result == 2
    assert "render_catalog_erd:" in capsys.readouterr().err


def test_given_malformed_catalog_when_run_then_errors_without_output(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    # Arrange
    path = tmp_path / "catalog.md"
    path.write_text(_to_markdown(_minimal(from_minimum="maybe")), encoding="utf-8")

    # Act
    result = run(path, "mermaid")

    # Assert
    captured = capsys.readouterr()
    assert result == 2
    assert captured.out == ""
    assert "from_minimum must be" in captured.err

