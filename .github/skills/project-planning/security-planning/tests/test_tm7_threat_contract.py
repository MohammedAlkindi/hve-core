# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Mutation-focused tests for the shared TM7 threat contract."""

from __future__ import annotations

import copy
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import generate_tm7  # noqa: E402
import populate_tm7_threats  # noqa: E402
import tm7_threat_contract  # noqa: E402

TYPE_ID = "TH-test"
GUIDS = {
    "drawing_surface_guid": "11111111-1111-1111-1111-111111111111",
    "source_guid": "22222222-2222-2222-2222-222222222222",
    "flow_guid": "33333333-3333-3333-3333-333333333333",
    "target_guid": "44444444-4444-4444-4444-444444444444",
}


def _threat(source_id: str = "threat-01") -> dict[str, object]:
    interaction_key = tm7_threat_contract.build_interaction_key(
        GUIDS["source_guid"],
        GUIDS["flow_guid"],
        GUIDS["target_guid"],
    )
    dictionary_key = tm7_threat_contract.build_entry_key(
        TYPE_ID,
        GUIDS["source_guid"],
        GUIDS["flow_guid"],
        GUIDS["target_guid"],
    )
    return {
        "source_id": source_id,
        "interaction_ref": "flow-01",
        "title": "Threat title",
        "description": "Threat description",
        "category": "tampering",
        "state": "Open",
        "mitigations": "Apply mitigation",
        "type_id": TYPE_ID,
        **GUIDS,
        "interaction_key": interaction_key,
        "dictionary_key": dictionary_key,
    }


def _serialized_entries(count: int = 1) -> ET.Element:
    threats = [_threat(f"threat-{index:02d}") for index in range(1, count + 1)]
    if count > 1:
        for index, threat in enumerate(threats, start=1):
            flow_guid = f"33333333-3333-3333-3333-{index:012d}"
            threat["flow_guid"] = flow_guid
            threat["interaction_key"] = tm7_threat_contract.build_interaction_key(
                str(threat["source_guid"]),
                flow_guid,
                str(threat["target_guid"]),
            )
            threat["dictionary_key"] = tm7_threat_contract.build_entry_key(
                TYPE_ID,
                str(threat["source_guid"]),
                flow_guid,
                str(threat["target_guid"]),
            )
    root = ET.Element("ThreatModel")
    tm7_threat_contract.serialize_threat_instances(
        root,
        threats,
        type_ids={TYPE_ID},
    )
    threat_instances = root.find("ThreatInstances")
    assert threat_instances is not None
    return threat_instances


def _first_entry(threat_instances: ET.Element) -> ET.Element:
    entry = threat_instances.find("{*}KeyValueOfstringThreatpc_P0_PhOB")
    assert entry is not None
    return entry


@pytest.mark.parametrize("invalid_id", ["abc", "0", "-1"])
def test_given_invalid_numeric_id_when_validated_then_rejected(invalid_id: str) -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    id_node = entry.find("{*}Value/{*}Id")
    assert id_node is not None
    id_node.text = invalid_id

    # Act and assert
    with pytest.raises(
        tm7_threat_contract.ThreatContractError,
        match="positive integer",
    ):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_missing_type_id_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    type_node = entry.find("{*}Value/{*}TypeId")
    assert type_node is not None
    type_node.text = None

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="required"):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_connector_name_when_serialized_then_interaction_string_uses_name(
) -> None:
    # Arrange
    threat = _threat()
    threat["interaction_string"] = "Submit request over HTTPS"

    # Act
    properties = dict(tm7_threat_contract.build_threat_instance_properties(threat))

    # Assert
    assert properties["InteractionString"] == "Submit request over HTTPS"


def test_given_unknown_type_id_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())

    # Act and assert
    with pytest.raises(
        tm7_threat_contract.ThreatContractError,
        match="not embedded",
    ):
        tm7_threat_contract.validate_serialized_threat_entry(
            entry,
            type_ids={"another-type"},
        )


def test_given_bad_member_order_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    value = entry.find("{*}Value")
    assert value is not None
    first = value[0]
    value.remove(first)
    value.append(first)

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="order"):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_bad_dictionary_key_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    key = entry.find("{*}Key")
    assert key is not None
    key.text = "bad-key"

    # Act and assert
    with pytest.raises(
        tm7_threat_contract.ThreatContractError,
        match="dictionary_key",
    ):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_duplicate_numeric_id_when_collection_validated_then_rejected() -> None:
    # Arrange
    threat_instances = _serialized_entries(2)
    entries = threat_instances.findall("{*}KeyValueOfstringThreatpc_P0_PhOB")
    second_id = entries[1].find("{*}Value/{*}Id")
    assert second_id is not None
    second_id.text = "1"

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="duplicate"):
        tm7_threat_contract.validate_serialized_threat_entries(threat_instances)


def test_given_duplicate_key_when_collection_validated_then_rejected() -> None:
    # Arrange
    threat_instances = _serialized_entries(2)
    entries = threat_instances.findall("{*}KeyValueOfstringThreatpc_P0_PhOB")
    first_key = entries[0].findtext("{*}Key")
    second_key = entries[1].find("{*}Key")
    first_value = entries[0].find("{*}Value")
    second_value = entries[1].find("{*}Value")
    assert second_key is not None
    assert first_value is not None
    assert second_value is not None
    second_key.text = first_key
    entries[1].remove(second_value)
    cloned_value = copy.deepcopy(first_value)
    cloned_id = cloned_value.find("{*}Id")
    assert cloned_id is not None
    cloned_id.text = "2"
    entries[1].append(cloned_value)

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="duplicate"):
        tm7_threat_contract.validate_serialized_threat_entries(threat_instances)


def test_given_null_guid_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    source_guid = entry.find("{*}Value/{*}SourceGuid")
    assert source_guid is not None
    source_guid.text = tm7_threat_contract.NULL_GUID

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="non-null"):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_unsupported_state_when_validated_then_rejected() -> None:
    # Arrange
    entry = _first_entry(_serialized_entries())
    state = entry.find("{*}Value/{*}State")
    assert state is not None
    state.text = "Unsupported"

    # Act and assert
    with pytest.raises(tm7_threat_contract.ThreatContractError, match="unsupported"):
        tm7_threat_contract.validate_serialized_threat_entry(entry)


def test_given_missing_interaction_ref_when_mapping_validated_then_rejected() -> None:
    # Arrange
    spec = _mapping_spec()
    spec["threats"][0].pop("interaction_ref")

    # Act
    failures = tm7_threat_contract.collect_mapping_failures(spec)

    # Assert
    assert failures == ["threat-01: missing interaction_ref"]


def test_given_unknown_flow_when_mapping_validated_then_rejected() -> None:
    # Arrange
    spec = _mapping_spec()
    spec["threats"][0]["interaction_ref"] = "unknown"

    # Act
    failures = tm7_threat_contract.collect_mapping_failures(spec)

    # Assert
    assert failures == ["threat-01: unknown interaction_ref unknown"]


def test_given_non_endpoint_without_override_when_validated_then_rejected(
) -> None:
    # Arrange
    spec = _mapping_spec()
    spec["threats"][0]["target_ref"] = "target-02"

    # Act
    failures = tm7_threat_contract.collect_mapping_failures(spec)

    # Assert
    assert failures == [
        "threat-01: semantic target target-02 is not an endpoint of "
        "interaction_ref flow-01 and placement_override is required"
    ]


def test_given_reviewed_override_when_non_endpoint_validated_then_passes(
) -> None:
    # Arrange
    spec = _mapping_spec()
    spec["threats"][0]["target_ref"] = "target-02"
    spec["threats"][0]["placement_override"] = {
        "rationale": "The placement carrier is reviewed for this non-endpoint mapping.",
        "reviewed": True,
    }

    # Act
    failures = tm7_threat_contract.collect_mapping_failures(spec)

    # Assert
    assert failures == []


@pytest.mark.parametrize(
    "override",
    [
        {"rationale": "Needs review", "reviewed": False},
        {"rationale": "", "reviewed": True},
        {"reviewed": True},
        "reviewed",
    ],
)
def test_given_invalid_override_when_non_endpoint_mapping_validated_then_rejected(
    override: object,
) -> None:
    # Arrange
    spec = _mapping_spec()
    spec["threats"][0]["target_ref"] = "target-02"
    spec["threats"][0]["placement_override"] = override

    # Act
    failures = tm7_threat_contract.collect_mapping_failures(spec)

    # Assert
    assert failures == [
        "threat-01: semantic target target-02 is not an endpoint of "
        "interaction_ref flow-01 and placement_override is required"
    ]


def test_given_portable_valid_spec_without_base_when_reconciled_then_passes() -> None:
    # Arrange
    spec = _mapping_spec()

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, None)

    # Assert
    assert failures == []


def test_given_authored_base_missing_connector_when_reconciled_then_reports_absence(
) -> None:
    # Arrange
    spec = _mapping_spec()
    authored_base = {
        "connectors": {},
        "elements": {"source-01": "source-guid", "target-01": "target-guid"},
        "surfaces": [{"guid": "surface-01"}],
    }

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, authored_base)

    # Assert
    assert failures == ["threat-01: authored-base connector flow-01 is absent"]


def test_given_wrong_authored_surface_when_reconciled_then_reports_mismatch(
) -> None:
    # Arrange
    spec = _mapping_spec()
    authored_base = {
        "connectors": {
            "flow-01": {
                "drawing_surface_guid": "surface-02",
                "flow_guid": "flow-guid",
                "source_guid": "source-guid",
                "target_guid": "target-guid",
            }
        },
        "elements": {"source-01": "source-guid", "target-01": "target-guid"},
        "surfaces": [{"guid": "surface-01"}, {"guid": "surface-02"}],
    }

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, authored_base)

    # Assert
    assert failures == ["threat-01: authored-base surface mismatch for flow-01"]


def test_given_null_authored_endpoints_when_reconciled_then_reports_null_guid(
) -> None:
    # Arrange
    spec = _mapping_spec()
    authored_base = {
        "connectors": {
            "flow-01": {
                "drawing_surface_guid": "surface-01",
                "flow_guid": "flow-guid",
                "source_guid": tm7_threat_contract.NULL_GUID,
                "target_guid": "target-guid",
            }
        },
        "elements": {"source-01": "source-guid", "target-01": "target-guid"},
        "surfaces": [{"guid": "surface-01"}],
    }

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, authored_base)

    # Assert
    assert failures == ["threat-01: authored-base connector flow-01 has null GUIDs"]


def test_given_authored_endpoint_mismatch_when_reconciled_then_reports_identity(
) -> None:
    # Arrange
    spec = _mapping_spec()
    authored_base = {
        "connectors": {
            "flow-01": {
                "drawing_surface_guid": "surface-01",
                "flow_guid": "flow-guid",
                "source_guid": "other-source-guid",
                "target_guid": "target-guid",
            }
        },
        "elements": {"source-01": "source-guid", "target-01": "target-guid"},
        "surfaces": [{"guid": "surface-01"}],
    }

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, authored_base)

    # Assert
    assert failures == [
        "threat-01: authored-base connector flow-01 endpoint identity mismatch"
    ]


def test_given_reordered_sources_when_prepared_then_numeric_ids_are_stable() -> None:
    # Arrange
    first = _threat("threat-a")
    second = copy.deepcopy(_threat("threat-b"))
    second["flow_guid"] = "55555555-5555-5555-5555-555555555555"
    second["interaction_key"] = tm7_threat_contract.build_interaction_key(
        str(second["source_guid"]),
        str(second["flow_guid"]),
        str(second["target_guid"]),
    )
    second["dictionary_key"] = tm7_threat_contract.build_entry_key(
        TYPE_ID,
        str(second["source_guid"]),
        str(second["flow_guid"]),
        str(second["target_guid"]),
    )

    # Act
    original = tm7_threat_contract.prepare_threat_instances([first, second])
    reordered = tm7_threat_contract.prepare_threat_instances([second, first])

    # Assert
    assert [(item["source_id"], item["id"]) for item in original] == [
        (item["source_id"], item["id"]) for item in reordered
    ]


def test_given_equivalent_threats_when_both_producers_run_then_contracts_agree(
) -> None:
    """Both TM7 producers must agree on type identity and threat properties.

    ``generate_tm7`` and ``populate_tm7_threats`` emit the same ThreatInstance
    DataContract. Divergent slug derivation makes custom type identifiers differ
    for punctuation-bearing ids, and an unresolved mitigation leaves
    ``PossibleMitigations`` empty on one path only.
    """
    # Arrange
    spec = {
        "mitigations": [
            {"id": "M-1", "description": "Pin every dependency by digest."},
        ],
        "threats": [
            {
                "id": "S--1",
                "title": "Punctuated identifier",
                "description": "Adjacent punctuation in the identifier.",
                "mitigation_ids": ["M-1"],
            }
        ],
    }
    threat = spec["threats"][0]

    # Act
    generated_type_id = generate_tm7._stable_custom_threat_type_id("S--1", threat)
    populated_type_id = populate_tm7_threats._resolve_type_id(threat, {}, {})
    mitigation_text = populate_tm7_threats._mitigation_text(spec, threat)
    generated_properties = dict(
        tm7_threat_contract.build_threat_instance_properties(
            {
                **threat,
                "mitigations": generate_tm7._resolve_mitigation_text(spec, threat),
            }
        )
    )
    populated_properties = dict(
        tm7_threat_contract.build_threat_instance_properties(
            {**threat, "mitigations": mitigation_text}
        )
    )

    # Assert
    assert generated_type_id == populated_type_id
    assert generated_properties == populated_properties
    assert generated_properties["PossibleMitigations"] == (
        "Pin every dependency by digest."
    )


def test_given_authored_labels_when_reconciled_then_semantic_ids_resolve() -> None:
    """Authored-base lookup must key on the stable identifier, not the label.

    A connector's first display attribute is its human-facing ``Name``, which the
    generator sets from ``display_label``. Keying the authored-base index on that
    value makes every relabelled flow unresolvable, because reconciliation looks
    the connector up by ``interaction_ref``.
    """
    # Arrange
    spec = _mapping_spec()
    spec["data_flows"][0]["display_label"] = "Authenticated read path"
    authored_base = ET.fromstring(
        """
        <ThreatModel>
          <DrawingSurfaceList>
            <DrawingSurfaceModel>
              <Guid>surface-01</Guid>
              <Borders>
                <KeyValueOfguidanyType>
                  <Value>
                    <Guid>source-guid</Guid>
                    <Properties>
                      <anyType>
                        <DisplayName>Name</DisplayName>
                        <Value>Source Node</Value>
                      </anyType>
                      <anyType>
                        <DisplayName>SemanticId</DisplayName>
                        <Value>source-01</Value>
                      </anyType>
                    </Properties>
                  </Value>
                </KeyValueOfguidanyType>
                <KeyValueOfguidanyType>
                  <Value>
                    <Guid>target-guid</Guid>
                    <Properties>
                      <anyType>
                        <DisplayName>Name</DisplayName>
                        <Value>Target Node</Value>
                      </anyType>
                      <anyType>
                        <DisplayName>SemanticId</DisplayName>
                        <Value>target-01</Value>
                      </anyType>
                    </Properties>
                  </Value>
                </KeyValueOfguidanyType>
              </Borders>
              <Lines>
                <KeyValueOfguidanyType>
                  <Value>
                    <Guid>flow-guid</Guid>
                    <Properties>
                      <anyType>
                        <DisplayName>Name</DisplayName>
                        <Value>Authenticated read path</Value>
                      </anyType>
                      <anyType>
                        <DisplayName>SemanticId</DisplayName>
                        <Value>flow-01</Value>
                      </anyType>
                    </Properties>
                    <SourceGuid>source-guid</SourceGuid>
                    <TargetGuid>target-guid</TargetGuid>
                  </Value>
                </KeyValueOfguidanyType>
              </Lines>
            </DrawingSurfaceModel>
          </DrawingSurfaceList>
        </ThreatModel>
        """.strip()
    )

    # Act
    failures = tm7_threat_contract.reconcile_authored_base(spec, authored_base)

    # Assert
    assert failures == []


def _mapping_spec() -> dict[str, object]:
    return {
        "representations": {
            "context_diagrams": [
                {
                    "id": "surface-01",
                    "elements": [
                        {"id": "source-01"},
                        {"id": "target-01"},
                        {"id": "target-02"},
                    ],
                    "flows": ["flow-01"],
                }
            ]
        },
        "data_flows": [
            {
                "id": "flow-01",
                "source_ref": "source-01",
                "target_ref": "target-01",
            }
        ],
        "threats": [
            {
                "id": "threat-01",
                "target_ref": "target-01",
                "interaction_ref": "flow-01",
            }
        ],
    }
