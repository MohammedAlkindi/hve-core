# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for native TB7 template generation."""

from __future__ import annotations

import re
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

SPEC_PATH = ROOT / "templates" / "threat-model-spec-example.yaml"
SOURCE_TEMPLATE_PATH = ROOT / "assets" / "templates" / "default.tb7"
SCRIPT_PATH = ROOT / "scripts" / "generate_tb7.py"


def _write_spec(path: Path, spec: dict) -> None:
    path.write_text(yaml.safe_dump(spec, sort_keys=False), encoding="utf-8")


def _iter_threat_types(root: ET.Element) -> list[ET.Element]:
    threat_types = root.find("ThreatTypes")
    assert threat_types is not None
    return list(threat_types.findall("ThreatType"))


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def test_generate_tb7_appends_manifest_and_threat_types(tmp_path: Path) -> None:
    spec_path = tmp_path / "spec.yaml"
    output_path = tmp_path / "generated.tb7"
    spec = {
        "project_metadata": {
            "name": "Widget Service",
            "version": "1.2.3",
            "summary": "Example",
        },
        "threats": [
            {
                "id": "threat-01",
                "title": "Payload tampering",
                "description": "An attacker tampers with requests",
                "category": "tampering",
                "citations": {"stride": ["T"], "nist": ["SC-8"], "mitre": []},
                "mitigation_ids": ["mitigation-01"],
            }
        ],
        "mitigations": [
            {
                "id": "mitigation-01",
                "name": "Request integrity validation",
                "description": "Validate request authenticity",
            }
        ],
    }
    _write_spec(spec_path, spec)

    subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(spec_path),
            str(SOURCE_TEMPLATE_PATH),
            "-o",
            str(output_path),
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    root = ET.parse(output_path).getroot()
    manifest = root.find("Manifest")
    assert manifest is not None
    assert manifest.get("name") == "Widget Service Threat Model Template"
    assert manifest.get("version") == "1.2.3"
    assert manifest.get("author") == "Microsoft Security Planning"
    assert re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        manifest.get("id", ""),
    )

    threat_types = _iter_threat_types(root)
    source_threat_types = list(
        ET.parse(SOURCE_TEMPLATE_PATH).getroot().find("ThreatTypes")
    )
    assert len(threat_types) == 1 + len(source_threat_types)


def test_generate_tb7_uses_deterministic_uuid_ids_and_no_stock_collisions(
    tmp_path: Path,
) -> None:
    spec_path = tmp_path / "spec.yaml"
    output_path = tmp_path / "generated.tb7"
    spec = {
        "project_metadata": {"name": "Widget Service", "version": "1.2.3"},
        "threats": [
            {
                "id": "threat-01",
                "title": "Payload tampering",
                "description": "desc",
                "category": "tampering",
            },
            {
                "id": "threat-02",
                "title": "Disclosure",
                "description": "desc",
                "category": "information-disclosure",
            },
        ],
    }
    _write_spec(spec_path, spec)

    subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(spec_path),
            str(SOURCE_TEMPLATE_PATH),
            "-o",
            str(output_path),
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    root = ET.parse(output_path).getroot()
    source_root = ET.parse(SOURCE_TEMPLATE_PATH).getroot()
    stock_ids = {
        (child.findtext("Id") or "").strip()
        for child in source_root.find("ThreatTypes")
        if _local_name(child.tag) == "ThreatType"
    }
    generated_ids = [
        (child.findtext("Id") or "").strip()
        for child in _iter_threat_types(root)
        if _local_name(child.tag) == "ThreatType"
    ]
    assert len(generated_ids) == len(set(generated_ids))
    assert set(generated_ids[-2:]).isdisjoint(stock_ids)

    expected_ids = [
        str(uuid.uuid5(uuid.NAMESPACE_URL, f"{SOURCE_TEMPLATE_PATH}:{item['id']}"))
        for item in spec["threats"]
    ]
    assert generated_ids[-2:] == expected_ids


def test_generate_tb7_matches_native_schema_order_and_parses(tmp_path: Path) -> None:
    spec_path = tmp_path / "spec.yaml"
    output_path = tmp_path / "generated.tb7"
    spec = {
        "project_metadata": {"name": "Widget Service", "version": "1.2.3"},
        "threats": [
            {
                "id": "threat-01",
                "title": "Payload tampering",
                "description": "An attacker tampers",
                "category": "tampering",
            }
        ],
    }
    _write_spec(spec_path, spec)

    subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(spec_path),
            str(SOURCE_TEMPLATE_PATH),
            "-o",
            str(output_path),
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    root = ET.parse(output_path).getroot()
    threat_types = _iter_threat_types(root)
    appended = threat_types[-1]

    assert [child.tag for child in appended] == [
        "GenerationFilters",
        "Id",
        "ShortTitle",
        "Category",
        "Description",
        "PropertiesMetaData",
    ]
    properties = appended.find("PropertiesMetaData")
    assert properties is not None
    metadata_names = [
        child.findtext("Name") for child in properties.findall("ThreatMetaDatum")
    ]
    assert metadata_names == [
        "UserThreatDescription",
        "PossibleMitigations",
        "Priority",
        "SDLPhase",
    ]
    for child in properties.findall("ThreatMetaDatum"):
        assert child.findtext("Id") is not None
        assert child.findtext("AttributeType") is not None


def test_generate_tb7_uses_non_contradictory_generation_filter(tmp_path: Path) -> None:
    spec_path = tmp_path / "spec.yaml"
    output_path = tmp_path / "generated.tb7"
    spec = {
        "project_metadata": {"name": "Widget Service", "version": "1.2.3"},
        "threats": [
            {
                "id": "threat-01",
                "title": "Payload tampering",
                "description": "An attacker tampers",
                "category": "tampering",
            }
        ],
    }
    _write_spec(spec_path, spec)

    subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(spec_path),
            str(SOURCE_TEMPLATE_PATH),
            "-o",
            str(output_path),
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    root = ET.parse(output_path).getroot()
    threat_type = next(
        child
        for child in _iter_threat_types(root)
        if _local_name(child.tag) == "ThreatType"
        and child.findtext("ShortTitle") == "Payload tampering"
    )
    generation_filter = threat_type.findtext("GenerationFilters/Include")
    assert generation_filter == "source is 'ROOT'"


def test_generate_tb7_resolves_mitigations_and_citations_into_supported_values(
    tmp_path: Path,
) -> None:
    spec_path = tmp_path / "spec.yaml"
    output_path = tmp_path / "generated.tb7"
    spec = {
        "project_metadata": {"name": "Widget Service", "version": "1.2.3"},
        "threats": [
            {
                "id": "threat-01",
                "title": "Payload tampering",
                "description": "An attacker tampers with requests",
                "category": "tampering",
                "citations": {"stride": ["T"], "nist": ["SC-8"], "mitre": []},
                "mitigation_ids": ["mitigation-01"],
            }
        ],
        "mitigations": [
            {
                "id": "mitigation-01",
                "name": "Request integrity validation",
                "description": "Validate request authenticity",
            }
        ],
    }
    _write_spec(spec_path, spec)

    subprocess.run(
        [
            sys.executable,
            str(SCRIPT_PATH),
            str(spec_path),
            str(SOURCE_TEMPLATE_PATH),
            "-o",
            str(output_path),
        ],
        check=True,
        cwd=ROOT,
        capture_output=True,
        text=True,
    )

    root = ET.parse(output_path).getroot()
    appended = _iter_threat_types(root)[-1]
    properties = appended.find("PropertiesMetaData")
    assert properties is not None
    mitigation_meta = next(
        child
        for child in properties.findall("ThreatMetaDatum")
        if child.findtext("Name") == "PossibleMitigations"
    )
    values = [value.text or "" for value in mitigation_meta.findall("Values/Value")]
    assert any("Request integrity validation" in value for value in values)
    assert any("NIST: SC-8" in value for value in values)
    assert any("STRIDE: T" in value for value in values)
