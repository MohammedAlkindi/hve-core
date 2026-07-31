# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Regression tests for TM7 threat population and TB7 filter stability."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[3]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import generate_tb7  # noqa: E402
import generate_tm7  # noqa: E402
import populate_tm7_threats  # noqa: E402
import tm7_threat_contract  # noqa: E402

COMPREHENSIVE_SPEC_PATH = (
    REPO_ROOT
    / ".copilot-tracking"
    / "security-plans"
    / "hve-core-comprehensive"
    / "threat-model-spec.yaml"
)
COMPREHENSIVE_MODEL_PATH = (
    REPO_ROOT
    / ".copilot-tracking"
    / "security-plans"
    / "hve-core-comprehensive"
    / "HVE-Core-Comprehensive-TMT-Authored.tm7"
)


def _write_complete_base(tmp_path: Path) -> Path:
    spec = generate_tm7.load_spec(COMPREHENSIVE_SPEC_PATH)
    profile = generate_tm7.resolve_profile(spec, None, ROOT)
    profile["name"] = "sdl_core_generic"
    payload = generate_tm7.build_tm7_payload(
        spec,
        profile,
        "pre-populated-comprehensive",
        threat_generation_enabled=False,
    )
    xml_text = generate_tm7.render_tm7_xml(
        payload,
        ROOT,
        "sdl_core_generic",
    )
    base_path = tmp_path / "complete-base.tm7"
    base_path.write_text(xml_text, encoding="utf-8")
    return base_path


def test_given_tb7_generation_when_filters_are_built_then_expression_is_safe() -> None:
    filters = generate_tb7._build_generation_filters()
    include_text = filters.findtext("Include") or ""
    exclude_text = filters.findtext("Exclude") or ""

    assert include_text == "source is 'ROOT'"
    assert exclude_text == ""
    assert "and" not in include_text.lower()


def test_given_comprehensive_spec_when_populated_then_has_expected_count() -> None:
    result = populate_tm7_threats.populate_tm7_threats(
        COMPREHENSIVE_SPEC_PATH,
        COMPREHENSIVE_MODEL_PATH,
        generation_state=False,
    )

    assert result["ThreatGenerationEnabled"] is False
    assert len(result["ThreatInstances"]) == 80
    assert result["counts"]["threat_instances"] == 80
    assert result["counts"]["custom_types"] == 80
    assert result["hashes"]["drawing_surface_list_before"] == (
        result["hashes"]["drawing_surface_list_after"]
    )
    assert result["hashes"]["knowledge_base_before"] == (
        result["hashes"]["knowledge_base_after"]
    )


def test_given_comprehensive_spec_when_validated_then_all_mappings_resolve() -> None:
    with COMPREHENSIVE_SPEC_PATH.open("r", encoding="utf-8") as handle:
        spec = yaml.safe_load(handle) or {}

    threats = spec.get("threats") or []
    assert len(threats) == 80

    errors = tm7_threat_contract.collect_mapping_failures(spec)

    assert errors == []


def test_given_reordered_threats_when_populated_then_output_is_deterministic(
    tmp_path: Path,
) -> None:
    with COMPREHENSIVE_SPEC_PATH.open("r", encoding="utf-8") as handle:
        spec = yaml.safe_load(handle) or {}
    spec["threats"] = list(reversed(spec.get("threats") or []))

    spec_path = tmp_path / "reordered-spec.yaml"
    spec_path.write_text(yaml.safe_dump(spec), encoding="utf-8")
    base_path = _write_complete_base(tmp_path)
    output_path = tmp_path / "reordered.tm7"
    original_output_path = tmp_path / "original.tm7"

    result = populate_tm7_threats.populate_tm7_threats(
        spec_path,
        base_path,
        output_path=output_path,
        generation_state=False,
    )
    populate_tm7_threats.populate_tm7_threats(
        COMPREHENSIVE_SPEC_PATH,
        base_path,
        output_path=original_output_path,
        generation_state=False,
    )

    instance_ids = [item["id"] for item in result["ThreatInstances"]]
    assert instance_ids == list(range(1, 81))
    assert output_path.read_bytes() == original_output_path.read_bytes()


def test_given_non_endpoint_mapping_without_override_when_populated_then_rejected(
    tmp_path: Path,
) -> None:
    with COMPREHENSIVE_SPEC_PATH.open("r", encoding="utf-8") as handle:
        spec = yaml.safe_load(handle) or {}
    first_threat = next(
        threat for threat in spec.get("threats") or [] if isinstance(threat, dict)
    )
    first_threat["target_ref"] = "target-02"
    spec_path = tmp_path / "invalid-topology.yaml"
    spec_path.write_text(yaml.safe_dump(spec), encoding="utf-8")

    with pytest.raises(
        populate_tm7_threats.GenerationError,
        match=r"placement_override is required",
    ):
        populate_tm7_threats.populate_tm7_threats(
            spec_path,
            COMPREHENSIVE_MODEL_PATH,
            generation_state=False,
        )


def test_given_unknown_flow_reference_when_validated_then_reports_source_threat(
    tmp_path: Path,
) -> None:
    with COMPREHENSIVE_SPEC_PATH.open("r", encoding="utf-8") as handle:
        spec = yaml.safe_load(handle) or {}
    first_threat = next(
        threat for threat in spec.get("threats") or [] if isinstance(threat, dict)
    )
    first_threat["interaction_ref"] = "missing-flow"
    spec_path = tmp_path / "invalid-spec.yaml"
    spec_path.write_text(yaml.safe_dump(spec), encoding="utf-8")

    with pytest.raises(
        populate_tm7_threats.GenerationError,
        match=r"S-1: unknown interaction_ref missing-flow",
    ):
        populate_tm7_threats.populate_tm7_threats(
            spec_path,
            COMPREHENSIVE_MODEL_PATH,
            generation_state=False,
        )


def test_given_output_path_matches_base_when_populated_then_refuses_in_place_write(
    tmp_path: Path,
) -> None:
    output_path = tmp_path / "population.tm7"
    output_path.write_text("placeholder", encoding="utf-8")

    with pytest.raises(
        populate_tm7_threats.GenerationError,
        match="Refusing to overwrite",
    ):
        populate_tm7_threats.populate_tm7_threats(
            COMPREHENSIVE_SPEC_PATH,
            output_path,
            output_path=output_path,
            generation_state=False,
        )


def test_given_production_base_when_writing_then_missing_connectors_block_output(
    tmp_path: Path,
) -> None:
    output_path = tmp_path / "blocked.tm7"

    with pytest.raises(
        populate_tm7_threats.GenerationError,
        match=r"AX-1: authored-base connector flow-21 is absent",
    ):
        populate_tm7_threats.populate_tm7_threats(
            COMPREHENSIVE_SPEC_PATH,
            COMPREHENSIVE_MODEL_PATH,
            output_path=output_path,
            generation_state=False,
        )

    assert not output_path.exists()


def test_given_comprehensive_spec_when_inspected_then_ax_1_uses_scan_target_flow(
) -> None:
    # Arrange
    with COMPREHENSIVE_SPEC_PATH.open("r", encoding="utf-8") as handle:
        spec = yaml.safe_load(handle) or {}

    # Act
    threat = next(
        item
        for item in spec.get("threats") or []
        if isinstance(item, dict) and item.get("id") == "AX-1"
    )
    flow = next(
        item
        for item in spec.get("data_flows") or []
        if isinstance(item, dict) and item.get("id") == "flow-21"
    )

    # Assert
    assert threat["interaction_ref"] == "flow-21"
    assert threat["target_ref"] == "ext-scan-target"
    assert flow["source_ref"] == "ext-axe"
    assert flow["target_ref"] == "ext-scan-target"


def test_given_output_without_generation_state_when_populated_then_defaults_false(
    tmp_path: Path,
) -> None:
    base_path = _write_complete_base(tmp_path)
    output_path = tmp_path / "candidate.tm7"

    result = populate_tm7_threats.populate_tm7_threats(
        COMPREHENSIVE_SPEC_PATH,
        base_path,
        output_path=output_path,
    )

    assert result["ThreatGenerationEnabled"] is False
    assert output_path.exists()


@pytest.mark.parametrize("subtree_name", ["DrawingSurfaceList", "KnowledgeBase"])
def test_given_semantic_subtree_mutation_when_populated_then_rejected(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    subtree_name: str,
) -> None:
    base_path = _write_complete_base(tmp_path)
    original_serializer = populate_tm7_threats.serialize_threat_instances

    def mutate_subtree(root, threats, *, type_ids=None):
        prepared = original_serializer(root, threats, type_ids=type_ids)
        subtree = root.find(f"{{*}}{subtree_name}")
        assert subtree is not None
        subtree.set("mutated", "true")
        return prepared

    monkeypatch.setattr(
        populate_tm7_threats,
        "serialize_threat_instances",
        mutate_subtree,
    )

    with pytest.raises(populate_tm7_threats.GenerationError, match="mutated"):
        populate_tm7_threats.populate_tm7_threats(
            COMPREHENSIVE_SPEC_PATH,
            base_path,
            generation_state=False,
        )


def test_given_separate_output_when_populated_then_base_bytes_remain_unchanged(
    tmp_path: Path,
) -> None:
    base_path = _write_complete_base(tmp_path)
    original_bytes = base_path.read_bytes()

    output_path = tmp_path / "candidate.tm7"
    result = populate_tm7_threats.populate_tm7_threats(
        COMPREHENSIVE_SPEC_PATH,
        base_path,
        output_path=output_path,
        generation_state=True,
    )

    assert base_path.read_bytes() == original_bytes
    assert result["ThreatGenerationEnabled"] is True
    assert result["hashes"]["base_sha256_before"] == result["hashes"][
        "base_sha256_after"
    ]
    xml_text = output_path.read_text(encoding="utf-8")
    assert f'xmlns="{populate_tm7_threats.MODEL_NS}"' in xml_text
    assert f'xmlns:b="{populate_tm7_threats.KNOWLEDGE_NS}"' in xml_text
    assert f'xmlns:c="{populate_tm7_threats.XSD_NS}"' in xml_text
