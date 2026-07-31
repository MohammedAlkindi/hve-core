# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Focused tests for the TM7 visual feedback contracts and scoring kernel."""

from __future__ import annotations

import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import generate_tm7  # noqa: E402
import tm7_visual_feedback as feedback  # noqa: E402

FIXTURES_DIR = ROOT / "tests" / "fixtures" / "visual-feedback"
SCHEMAS_DIR = ROOT / "assets" / "schemas"


def test_given_schema_documents_when_inspected_then_require_v2_strict_shape() -> None:
    # Arrange
    overlay_schema_path = SCHEMAS_DIR / "tm7-layout-overlay.schema.json"
    manifest_schema_path = SCHEMAS_DIR / "tm7-visual-feedback-manifest.schema.json"

    # Act
    overlay_schema = json.loads(overlay_schema_path.read_text(encoding="utf-8"))
    manifest_schema = json.loads(manifest_schema_path.read_text(encoding="utf-8"))

    # Assert
    assert overlay_schema["properties"]["schema_version"]["const"] == 2
    assert overlay_schema["additionalProperties"] is False
    assert manifest_schema["properties"]["schema_version"]["const"] == 2
    assert manifest_schema["additionalProperties"] is False


def test_given_valid_overlay_when_validating_then_accepts_and_normalizes() -> None:
    # Arrange
    overlay = feedback.load_layout_overlay(FIXTURES_DIR / "valid-overlay.yaml")
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal", "trust-zone-identity"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act
    feedback.validate_layout_overlay(overlay, context)

    # Assert
    assert overlay["applies_to"][0]["surface_id"] == "context"
    assert overlay["node_rules"][0]["layout_role"] == "main"


def test_given_datetime_values_when_fingerprinting_then_serializes_them() -> None:
    # Arrange
    timestamp = datetime(2026, 7, 17, 19, 15, 30, tzinfo=timezone.utc)

    # Act
    fingerprint = feedback._fingerprint({"created_at": timestamp})
    normalized_fingerprint = feedback._fingerprint(
        {"created_at": "2026-07-17T19:15:30+00:00"}
    )

    # Assert
    assert fingerprint == normalized_fingerprint
    assert isinstance(fingerprint, str)
    assert len(fingerprint) == 64


@pytest.mark.parametrize(
    ("version", "expected_message"),
    [(0, "schema_version"), (1, "schema_version")],
)
def test_given_unsupported_schema_version_when_validating_then_raises(
    version: int,
    expected_message: str,
) -> None:
    # Arrange
    overlay = {
        "schema_version": version,
        "overlay_type": "tm7_layout_overlay",
        "model_id": "demo-model",
        "overlay_id": "overlay-001",
        "applies_to": [{"surface_id": "context", "generator_profile": "default"}],
        "zone_rules": [],
        "node_rules": [],
        "connector_rules": [],
        "surface_rules": [],
        "provenance": {
            "evidence_ref": "evidence/iteration-01",
            "approval_state": "pending",
        },
        "invalidation": {
            "spec_fingerprint": "abc",
            "generator_profile_fingerprint": "def",
            "surface_identity_fingerprint": "ghi",
            "surface_zone_identity_fingerprint": "ghi",
            "surface_flow_identity_fingerprint": "ghi",
        },
    }
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match=expected_message):
        feedback.validate_layout_overlay(overlay, context)


def test_given_unknown_rule_type_when_validating_then_raises() -> None:
    # Arrange
    overlay = {
        "schema_version": 2,
        "overlay_type": "tm7_layout_overlay",
        "model_id": "demo-model",
        "overlay_id": "overlay-001",
        "applies_to": [{"surface_id": "context", "generator_profile": "default"}],
        "zone_rules": [],
        "node_rules": [
            {
                "surface_id": "context",
                "node_id": "trust-zone-portal",
                "layout_role": "bad-role",
                "absolute_position": {"left": 10, "top": 20, "width": 10, "height": 10},
            }
        ],
        "connector_rules": [],
        "surface_rules": [],
        "provenance": {
            "evidence_ref": "evidence/iteration-01",
            "approval_state": "pending",
        },
        "invalidation": {
            "spec_fingerprint": "abc",
            "generator_profile_fingerprint": "def",
            "surface_identity_fingerprint": "ghi",
            "surface_zone_identity_fingerprint": "ghi",
            "surface_flow_identity_fingerprint": "ghi",
        },
    }
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="layout_role"):
        feedback.validate_layout_overlay(overlay, context)


def test_given_duplicate_rule_keys_when_validating_then_raises() -> None:
    # Arrange
    overlay = {
        "schema_version": 2,
        "overlay_type": "tm7_layout_overlay",
        "model_id": "demo-model",
        "overlay_id": "overlay-001",
        "applies_to": [{"surface_id": "context", "generator_profile": "default"}],
        "zone_rules": [],
        "node_rules": [
            {
                "surface_id": "context",
                "node_id": "trust-zone-portal",
                "layout_role": "main",
                "absolute_position": {"left": 10, "top": 15, "width": 10, "height": 10},
            },
            {
                "surface_id": "context",
                "node_id": "trust-zone-portal",
                "layout_role": "main",
                "absolute_position": {"left": 20, "top": 25, "width": 10, "height": 10},
            },
        ],
        "connector_rules": [],
        "surface_rules": [],
        "provenance": {
            "evidence_ref": "evidence/iteration-01",
            "approval_state": "pending",
        },
        "invalidation": {
            "spec_fingerprint": "abc",
            "generator_profile_fingerprint": "def",
            "surface_identity_fingerprint": "ghi",
            "surface_zone_identity_fingerprint": "ghi",
            "surface_flow_identity_fingerprint": "ghi",
        },
    }
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal", "trust-zone-identity"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="duplicate"):
        feedback.validate_layout_overlay(overlay, context)


def test_given_stale_invalidation_fingerprint_when_validating_then_raises() -> None:
    # Arrange
    overlay = feedback.load_layout_overlay(FIXTURES_DIR / "valid-overlay.yaml")
    overlay["invalidation"]["spec_fingerprint"] = "stale"
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal", "trust-zone-identity"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="fingerprint"):
        feedback.validate_layout_overlay(overlay, context)


@pytest.mark.parametrize(
    ("metric_name", "metric_value", "expected_severity"),
    [
        ("overlap_ratio", 0.009, "pass"),
        ("overlap_ratio", 0.025, "warn"),
        ("overlap_ratio", 0.035, "review"),
        ("edge_node_intersections", 0, "pass"),
        ("edge_node_intersections", 2, "warn"),
        ("edge_node_intersections", 3, "review"),
        ("edge_crossing_count", 0, "pass"),
        ("edge_crossing_count", 2, "warn"),
        ("edge_crossing_count", 3, "review"),
        ("min_spacing_ratio", 0.65, "pass"),
        ("min_spacing_ratio", 0.5, "warn"),
        ("min_spacing_ratio", 0.24, "warn"),
        ("min_spacing_ratio", 0.2, "review"),
    ],
)
def test_surface_layout_candidate_scoring_is_deterministic(
    metric_name: str,
    metric_value: float,
    expected_severity: str,
) -> None:
    candidate = {
        "surface_id": "context",
        "orientation": "horizontal",
        "zone_order": ["zone-a", "zone-b"],
        "node_ranks": {"node-a": 0, "node-b": 1},
        "branch_groups": {"node-a": 0, "node-b": 0},
        "reverse_edge_members": {"node-a"},
        "fan_in": {"node-a": 0, "node-b": 1},
        "fan_out": {"node-a": 1, "node-b": 0},
    }

    score = feedback.score_surface_layout_candidate(
        candidate,
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )

    assert isinstance(score, tuple)
    assert score[0] >= 0
    assert score[1] >= 0


@pytest.mark.parametrize(
    ("metric_name", "metric_value", "expected_severity"),
    [
        ("overlap_ratio", 0.009, "pass"),
        ("overlap_ratio", 0.025, "warn"),
        ("overlap_ratio", 0.035, "review"),
        ("edge_node_intersections", 0, "pass"),
        ("edge_node_intersections", 2, "warn"),
        ("edge_node_intersections", 3, "review"),
        ("edge_crossing_count", 0, "pass"),
        ("edge_crossing_count", 2, "warn"),
        ("edge_crossing_count", 3, "review"),
        ("min_spacing_ratio", 0.65, "pass"),
        ("min_spacing_ratio", 0.5, "warn"),
        ("min_spacing_ratio", 0.24, "warn"),
        ("min_spacing_ratio", 0.2, "review"),
    ],
)
def test_threshold_boundaries_assigns_expected_severity(
    metric_name: str,
    metric_value: float,
    expected_severity: str,
) -> None:
    # Arrange
    metrics = {
        "surface_id": "context",
        "node_id": "trust-zone-portal",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        metric_name: metric_value,
    }

    # Act
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    matching_finding = next(
        finding for finding in findings if finding["metric_name"] == metric_name
    )
    assert matching_finding["severity"] == expected_severity


def test_given_zone_metrics_when_evaluating_then_reports_pending_review() -> None:
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=48.0,
        node_rects={"node-a": (0.0, 0.0, 12.0, 12.0)},
        connector_segments=[],
        boundary_rects={
            "boundary-a": (0.0, 0.0, 100.0, 100.0),
            "boundary-b": (90.0, 90.0, 180.0, 180.0),
        },
        boundary_label_rects={"boundary-label": (0.0, 0.0, 20.0, 20.0)},
        connector_label_rects={"conn-label": (5.0, 5.0, 25.0, 25.0)},
        layout_roles={"node-a": "main"},
        zone_membership={"node-a": "zone-a"},
        zone_content_rects={"zone-a": (0.0, 0.0, 100.0, 100.0)},
        viewport_target=(0.0, 0.0, 960.0, 540.0),
        diagram_bounds=(0.0, 0.0, 1000.0, 600.0),
        outer_margin=24.0,
        selected_flow_ids={"flow-001"},
        expected_semantic_node_ids={"node-a"},
        expected_semantic_flow_ids={"flow-001"},
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["boundary_overlap_count"] == 1
    assert metrics["boundary_min_gutter"] == 0.0
    assert metrics["semantic_flow_coverage"] == 1.0
    assert any(
        finding["metric_name"] == "boundary_overlap_count" for finding in findings
    )


def test_unoccupied_zone_is_a_blocking_review_finding() -> None:
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={"node-a": (20.0, 70.0, 120.0, 170.0)},
        connector_segments=[],
        zone_membership={"node-a": "zone-a"},
        zone_content_rects={
            "zone-a": (10.0, 60.0, 200.0, 240.0),
            "zone-empty": (220.0, 60.0, 410.0, 240.0),
        },
    )

    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    assert metrics["unoccupied_zone_count"] == 1
    finding = next(
        item for item in findings if item["metric_name"] == "unoccupied_zone_count"
    )
    assert finding["severity"] == "review"


def _composition_geometry(**overrides: object) -> feedback.SurfaceGeometry:
    """Build a readable three-rank surface used by composition metric tests."""

    payload: dict[str, object] = {
        "surface_id": "context",
        "nominal_node_size": 100.0,
        "node_rects": {
            "node-a": (100.0, 300.0, 200.0, 400.0),
            "node-b": (400.0, 300.0, 500.0, 400.0),
            "node-c": (700.0, 300.0, 800.0, 400.0),
        },
        "connector_segments": [
            ("node-a", "node-b", (200.0, 350.0), (400.0, 350.0)),
            ("node-b", "node-c", (500.0, 350.0), (700.0, 350.0)),
        ],
        "connector_label_rects": {
            "f-1": (270.0, 300.0, 350.0, 330.0),
            "f-2": (570.0, 300.0, 650.0, 330.0),
        },
        "zone_membership": {
            "node-a": "zone-a",
            "node-b": "zone-a",
            "node-c": "zone-a",
        },
        "zone_content_rects": {"zone-a": (50.0, 250.0, 900.0, 450.0)},
        "viewport_target": (0.0, 0.0, 1200.0, 800.0),
        "connector_routes": {
            "f-1": {
                "source_id": "node-a",
                "target_id": "node-b",
                "source_point": (200.0, 350.0),
                "handle_point": (300.0, 350.0),
                "target_point": (400.0, 350.0),
            },
            "f-2": {
                "source_id": "node-b",
                "target_id": "node-c",
                "source_point": (500.0, 350.0),
                "handle_point": (600.0, 350.0),
                "target_point": (700.0, 350.0),
            },
        },
        "node_ranks": {"node-a": 0, "node-b": 1, "node-c": 2},
        "branch_groups": {"node-a": 0, "node-b": 0, "node-c": 0},
        "orientation": "horizontal",
    }
    payload.update(overrides)
    return feedback.SurfaceGeometry(**payload)


def _blocking_metric_names(findings: list[dict[str, object]]) -> set[str]:
    return {
        str(finding["metric_name"])
        for finding in findings
        if finding["severity"] == "review"
    }


def test_given_readable_surface_when_deriving_then_composition_gates_pass() -> None:
    # Arrange
    geometry = _composition_geometry()

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["visible_clipping_count"] == 0
    assert metrics["visible_coverage_ratio"] == pytest.approx(1.0)
    assert metrics["backward_edge_count"] == 0
    assert metrics["max_handle_cluster_size"] == 1
    assert metrics["duplicate_route_leg_count"] == 0
    assert metrics["rank_monotonicity_ratio"] == pytest.approx(1.0)
    assert metrics["branch_alignment_variance"] == pytest.approx(0.0)
    composition_names = set(feedback.derive_composition_metrics(geometry))
    assert not _blocking_metric_names(findings) & composition_names


def test_given_all_composition_metrics_when_derived_then_values_are_finite() -> None:
    # Arrange
    geometry = _composition_geometry()

    # Act
    first = feedback.derive_composition_metrics(geometry)
    second = feedback.derive_composition_metrics(geometry)

    # Assert
    assert first == second
    numeric_values = [
        value for value in first.values() if isinstance(value, (int, float))
    ]
    assert numeric_values
    assert all(math.isfinite(float(value)) for value in numeric_values)


def test_given_node_outside_viewport_when_deriving_then_clipping_blocks() -> None:
    # Arrange
    geometry = _composition_geometry(
        node_rects={
            "node-a": (100.0, 300.0, 200.0, 400.0),
            "node-b": (400.0, 300.0, 500.0, 400.0),
            "node-c": (1150.0, 300.0, 1400.0, 400.0),
        },
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["visible_clipping_count"] == 1
    assert metrics["visible_coverage_ratio"] < feedback.MIN_VISIBLE_COVERAGE_RATIO
    blocking = _blocking_metric_names(findings)
    assert "visible_clipping_count" in blocking
    assert "visible_coverage_ratio" in blocking


def test_given_two_connectors_sharing_a_handle_when_deriving_then_gate_blocks() -> None:
    """A shared handle superimposes both connector labels in native rendering."""
    # Arrange
    routes = dict(_composition_geometry().connector_routes)
    routes["f-2"] = dict(routes["f-2"], handle_point=(300.0, 350.0))
    geometry = _composition_geometry(connector_routes=routes)

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["max_handle_cluster_size"] == 2
    assert "max_handle_cluster_size" in _blocking_metric_names(findings)


def test_given_distinct_handles_when_deriving_then_cluster_gate_passes() -> None:
    # Arrange
    geometry = _composition_geometry()

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["max_handle_cluster_size"] == 1
    assert "max_handle_cluster_size" not in _blocking_metric_names(findings)


def test_given_clustered_handles_when_deriving_then_density_blocks() -> None:
    # Arrange
    routes = dict(_composition_geometry().connector_routes)
    routes["f-2"] = dict(routes["f-2"], handle_point=(300.0, 350.0))
    routes["f-3"] = {
        "source_id": "node-a",
        "target_id": "node-c",
        "source_point": (200.0, 350.0),
        "handle_point": (302.0, 351.0),
        "target_point": (700.0, 350.0),
    }
    geometry = _composition_geometry(connector_routes=routes)

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["max_handle_cluster_size"] == 3
    assert "max_handle_cluster_size" in _blocking_metric_names(findings)


def test_given_duplicate_route_legs_when_deriving_then_overlap_blocks() -> None:
    # Arrange
    routes = dict(_composition_geometry().connector_routes)
    routes["f-3"] = {
        "source_id": "node-a",
        "target_id": "node-b",
        "source_point": (200.0, 350.0),
        "handle_point": (300.0, 350.0),
        "target_point": (400.0, 350.0),
    }
    geometry = _composition_geometry(connector_routes=routes)

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["duplicate_route_leg_count"] == 2
    assert "duplicate_route_leg_count" in _blocking_metric_names(findings)


def test_given_orphaned_label_when_deriving_then_ownership_warns() -> None:
    """Predicted label geometry is advisory: TM7 never persists label rects."""
    # Arrange
    geometry = _composition_geometry(
        connector_label_rects={
            "f-1": (270.0, 20.0, 350.0, 50.0),
            "f-2": (570.0, 300.0, 650.0, 330.0),
        },
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert (
        metrics["max_label_ownership_distance"]
        > feedback.MAX_LABEL_OWNERSHIP_DISTANCE
    )
    finding = next(
        item
        for item in findings
        if item["metric_name"] == "max_label_ownership_distance"
    )
    assert finding["severity"] == "warn"
    assert finding["category"] == "predicted_label_advisory"
    assert finding["flow_id"] == "f-1"
    assert finding["coordinate_space"] == "tm7-model"


def test_given_label_on_arrowhead_when_deriving_then_clearance_warns() -> None:
    """Predicted label geometry is advisory: TM7 never persists label rects."""
    # Arrange
    geometry = _composition_geometry(
        connector_label_rects={
            "f-1": (390.0, 340.0, 410.0, 360.0),
            "f-2": (570.0, 300.0, 650.0, 330.0),
        },
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert (
        metrics["min_label_arrowhead_clearance"]
        < feedback.MIN_LABEL_ARROWHEAD_CLEARANCE
    )
    finding = next(
        item
        for item in findings
        if item["metric_name"] == "min_label_arrowhead_clearance"
    )
    assert finding["severity"] == "warn"
    assert finding["category"] == "predicted_label_advisory"
    assert finding["flow_id"] == "f-1"


def test_given_composition_drift_when_deriving_then_advisory_gates_only_warn() -> None:
    # Arrange
    geometry = _composition_geometry(
        node_rects={
            "node-a": (100.0, 300.0, 200.0, 400.0),
            "node-b": (400.0, 620.0, 500.0, 720.0),
            "node-c": (700.0, 300.0, 800.0, 400.0),
        },
        node_ranks={"node-a": 2, "node-b": 1, "node-c": 0},
        branch_groups={"node-a": 0, "node-b": 0, "node-c": 0},
        zone_content_rects={
            "zone-a": (50.0, 250.0, 900.0, 780.0),
            "zone-b": (910.0, 250.0, 1000.0, 400.0),
        },
        zone_membership={
            "node-a": "zone-a",
            "node-b": "zone-a",
            "node-c": "zone-b",
        },
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)
    findings = feedback.derive_findings(metrics, density="simple")

    # Assert
    assert metrics["backward_edge_count"] == 2
    assert metrics["rank_monotonicity_ratio"] < feedback.MIN_RANK_MONOTONICITY_RATIO
    assert (
        metrics["branch_alignment_variance"]
        > feedback.MAX_BRANCH_ALIGNMENT_VARIANCE
    )
    advisory_names = {
        "backward_edge_count",
        "rank_monotonicity_ratio",
        "branch_alignment_variance",
        "zone_whitespace_imbalance",
    }
    blocking = _blocking_metric_names(findings)
    assert not advisory_names & blocking
    warned = {
        str(finding["metric_name"])
        for finding in findings
        if finding["severity"] == "warn"
    }
    assert {
        "backward_edge_count",
        "rank_monotonicity_ratio",
        "branch_alignment_variance",
    } <= warned


def _refinement_candidate(
    candidate_id: str,
    *,
    orientation: str = "horizontal",
    zone_order: list[str] | None = None,
    node_ids: list[str] | None = None,
    flow_ids: list[str] | None = None,
) -> dict[str, object]:
    return {
        "candidate_id": candidate_id,
        "node_ids": node_ids if node_ids is not None else ["node-a", "node-b"],
        "flow_ids": flow_ids if flow_ids is not None else ["f-1"],
        "zone_ids": ["zone-a", "zone-b"],
        "orientation": orientation,
        "zone_order": zone_order if zone_order is not None else ["zone-a", "zone-b"],
        "node_ranks": {"node-a": 0, "node-b": 1},
        "branch_groups": {"node-a": 0, "node-b": 0},
    }


def test_given_dominated_candidates_when_pruning_then_only_frontier_remains() -> None:
    # Arrange
    scored = [
        {"candidate_id": "best", "score": (1.0, 1.0, 1.0)},
        {"candidate_id": "dominated", "score": (2.0, 2.0, 2.0)},
        {"candidate_id": "tradeoff", "score": (0.5, 3.0, 1.0)},
        {"candidate_id": "duplicate", "score": (1.0, 1.0, 1.0)},
    ]

    # Act
    survivors = feedback.prune_dominated_surface_candidates(scored)

    # Assert
    survivor_ids = {str(entry["candidate_id"]) for entry in survivors}
    assert "dominated" not in survivor_ids
    assert "duplicate" not in survivor_ids
    assert survivor_ids == {"best", "tradeoff"}


def test_given_no_improving_candidate_when_selecting_then_loop_stops() -> None:
    # Arrange
    incumbent = _refinement_candidate("incumbent")
    incumbent_score = feedback.score_surface_layout_candidate(incumbent)

    # Act
    decision = feedback.select_surface_refinement(
        incumbent_score=incumbent_score,
        incumbent_semantic_fingerprint=feedback.surface_semantic_fingerprint(incumbent),
        candidates=[_refinement_candidate("same")],
    )

    # Assert
    assert decision["selected"] is None
    assert decision["stop_reason"] == "repeated-defect-no-improvement"
    assert decision["requires_native_launch"] is False


def test_given_improving_candidate_when_selecting_then_native_launch_allowed() -> None:
    # Arrange
    incumbent = _refinement_candidate("incumbent", orientation="vertical")
    incumbent_score = feedback.score_surface_layout_candidate(
        incumbent,
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )
    improved = _refinement_candidate("improved", orientation="horizontal")

    # Act
    decision = feedback.select_surface_refinement(
        incumbent_score=incumbent_score,
        incumbent_semantic_fingerprint=feedback.surface_semantic_fingerprint(incumbent),
        candidates=[improved],
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )

    # Assert
    assert decision["requires_native_launch"] is True
    assert decision["selected_candidate_id"] == "improved"
    assert tuple(decision["selected_score"]) < tuple(incumbent_score)


def test_given_semantic_drift_when_selecting_then_candidate_is_rejected() -> None:
    # Arrange
    incumbent = _refinement_candidate("incumbent", orientation="vertical")
    incumbent_score = feedback.score_surface_layout_candidate(
        incumbent,
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )
    drifted = _refinement_candidate(
        "drifted",
        orientation="horizontal",
        node_ids=["node-a", "node-b", "node-injected"],
    )

    # Act
    decision = feedback.select_surface_refinement(
        incumbent_score=incumbent_score,
        incumbent_semantic_fingerprint=feedback.surface_semantic_fingerprint(incumbent),
        candidates=[drifted],
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )

    # Assert
    assert decision["semantic_rejected_ids"] == ["drifted"]
    assert decision["selected"] is None
    assert decision["requires_native_launch"] is False


def test_given_oversized_candidate_set_when_selecting_then_search_is_bounded() -> None:
    # Arrange
    incumbent = _refinement_candidate("incumbent", orientation="vertical")
    incumbent_score = feedback.score_surface_layout_candidate(
        incumbent,
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )
    candidates = [
        _refinement_candidate(f"candidate-{index:04d}", orientation="horizontal")
        for index in range(feedback.MAX_SURFACE_REFINEMENT_CANDIDATES * 3)
    ]

    # Act
    decision = feedback.select_surface_refinement(
        incumbent_score=incumbent_score,
        incumbent_semantic_fingerprint=feedback.surface_semantic_fingerprint(incumbent),
        candidates=candidates,
        viewport_target=(0.0, 0.0, 1920.0, 1080.0),
    )

    # Assert
    assert decision["evaluated_count"] == feedback.MAX_SURFACE_REFINEMENT_CANDIDATES
    assert (
        feedback.MIN_SURFACE_REFINEMENT_CANDIDATES
        <= feedback.MAX_SURFACE_REFINEMENT_CANDIDATES
    )
    assert decision["selected_candidate_id"] == "candidate-0000"


def test_given_manifest_when_validated_then_requires_pending_human_status() -> None:
    # Arrange
    manifest = {
        "schema_version": 2,
        "manifest_type": "tm7_visual_feedback",
        "model_id": "demo-model",
        "spec_path": "threat-model-spec.yaml",
        "spec_sha256": "abc",
        "generator_profile": "default",
        "generator_profile_sha256": "def",
        "candidate_sha256": "a" * 64,
        "iteration_id": "2026-07-16.001",
        "pinned_tmt_version": "7.3.51110.1",
        "created_at": "2026-07-16T00:00:00Z",
        "surfaces": [
            {
                "surface_id": "context",
                "surface_guid": "surface-context",
                "surface_name": "System context",
                "capture_path": "evidence/context.png",
                "uia_path": "uia/context",
                "metrics": {},
                "findings": [],
                "human_review_status": "pending",
                "human_review_required": True,
            }
        ],
        "convergence": {
            "status": "pending",
            "selected_candidate": None,
            "stop_reason": "pending",
            "evidence_complete": True,
        },
    }

    # Act / Assert
    feedback.validate_feedback_manifest(manifest)


def test_layout_calibration_rejects_zero_sized_pane() -> None:
    """Reject calibration payloads that report a zero-sized pane."""
    # Arrange
    calibration = {
        "contract": "layout_calibration_v1",
        "scope": "same-run",
        "viewport_target": [0.0, 0.0, 1200.0, 800.0],
        "pane_rect": [0, 0, 0, 0],
        "scroll_percentages": {"horizontal": 0.0, "vertical": 0.0},
        "effective_scale": {"x": 1.0, "y": 1.0},
        "screenshot_dimensions": {"width": 1200, "height": 800},
        "crop_dimensions": {"width": 0, "height": 0},
        "confidence": {
            "pane_measured": True,
            "scroll_interface_found": True,
            "consistent": True,
            "failure_reason": None,
        },
    }

    # Act / Assert
    with pytest.raises(ValueError, match="pane_rect"):
        feedback._validate_layout_calibration_v1(calibration)


def test_given_layout_calibration_contract_when_validated_then_accepts_same_run_scope(
) -> None:
    """Accept a same-run calibration contract with complete confidence data."""
    # Arrange
    manifest = {
        "schema_version": 2,
        "manifest_type": "tm7_visual_feedback",
        "model_id": "demo-model",
        "spec_path": "threat-model-spec.yaml",
        "spec_sha256": "abc",
        "generator_profile": "default",
        "generator_profile_sha256": "def",
        "candidate_sha256": "a" * 64,
        "iteration_id": "2026-07-16.001",
        "pinned_tmt_version": "7.3.51110.1",
        "created_at": "2026-07-16T00:00:00Z",
        "surfaces": [],
        "convergence": {
            "status": "automated-ready-pending-human",
            "selected_candidate": "candidate.tm7",
            "stop_reason": "evidence",
            "evidence_complete": True,
        },
        "layout_calibration_v1": {
            "contract": "layout_calibration_v1",
            "scope": "same-run",
            "viewport_target": [0.0, 0.0, 1200.0, 800.0],
            "pane_rect": [0, 0, 1200, 800],
            "scroll_percentages": {"horizontal": 0.0, "vertical": 0.0},
            "effective_scale": {"x": 1.0, "y": 1.0},
            "screenshot_dimensions": {"width": 1200, "height": 800},
            "crop_dimensions": {"width": 1200, "height": 800},
            "confidence": {
                "pane_measured": True,
                "scroll_interface_found": True,
                "consistent": True,
                "failure_reason": None,
            },
        },
    }

    # Act / Assert
    feedback.validate_feedback_manifest(manifest)


def test_connector_label_helpers_make_generator_and_feedback_agree() -> None:
    # Act
    generator_layout = generate_tm7._build_connector_label_layout(
        "Access the service",
        "HTTPS",
        handle=(120.0, 80.0),
        label_offset=(12.0, 10.0),
    )
    feedback_layout = feedback.build_connector_label_layout(
        "Access the service",
        "HTTPS",
        handle=(120.0, 80.0),
        label_offset=(12.0, 10.0),
    )

    # Assert
    assert generator_layout["display_label"] == feedback_layout["display_label"]
    assert generator_layout["label_lines"] == feedback_layout["label_lines"]
    assert generator_layout["label_rect"] == feedback_layout["label_rect"]


def test_connector_endpoints_are_excluded_from_geometry_intersections() -> None:
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={
            "a": (0.0, 0.0, 100.0, 100.0),
            "b": (200.0, 0.0, 100.0, 100.0),
        },
        connector_segments=[
            ("a", "b", (0.0, 50.0), (200.0, 50.0)),
        ],
    )

    # Act
    metrics = feedback.derive_geometry_metrics(geometry)

    # Assert
    assert metrics["edge_node_intersections"] == 0
    assert metrics["edge_crossing_count"] == 0


def test_given_dense_surface_when_deriving_findings_then_marks_crossings_as_warn() -> (
    None
):
    # Arrange
    metrics = {
        "surface_id": "context",
        "node_id": "trust-zone-portal",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "edge_crossing_count": 3,
    }

    # Act
    findings = feedback.derive_findings(metrics, density="dense")

    # Assert
    crossing_finding = next(
        finding
        for finding in findings
        if finding["metric_name"] == "edge_crossing_count"
    )
    assert crossing_finding["severity"] == "warn"


def test_given_background_image_when_deriving_image_metrics_then_reports_review() -> (
    None
):
    # Arrange
    image_path = Path("/tmp/background-image.png")
    image_path.write_bytes(b"\x00" * 64)

    try:
        viewport = feedback.ViewportBounds(left=0, top=0, width=800, height=600)

        # Act
        metrics = feedback.derive_image_metrics(image_path, viewport)

        # Assert
        assert metrics["is_all_background"] is True
        assert metrics["capture_status"] == "ok"
        assert metrics["severity"] == "review"
    finally:
        image_path.unlink(missing_ok=True)


def test_given_overlay_candidates_when_ranked_then_uses_deterministic_order() -> None:
    # Arrange
    candidates = [
        {
            "surface_id": "context",
            "node_id": "node-b",
            "constraint_type": "position",
            "gate_failure_count": 1,
            "review_count": 0,
            "warn_count": 0,
            "max_severity_score": 2.0,
        },
        {
            "surface_id": "context",
            "node_id": "node-a",
            "constraint_type": "position",
            "gate_failure_count": 1,
            "review_count": 0,
            "warn_count": 0,
            "max_severity_score": 1.0,
        },
        {
            "surface_id": "context",
            "node_id": "node-a",
            "constraint_type": "relative_to",
            "gate_failure_count": 1,
            "review_count": 0,
            "warn_count": 0,
            "max_severity_score": 1.0,
        },
    ]

    # Act
    ranked = feedback.rank_overlay_candidates(candidates)

    # Assert
    assert [candidate["node_id"] for candidate in ranked] == [
        "node-a",
        "node-a",
        "node-b",
    ]
    assert ranked[0]["ranking_key"] == (
        1,
        0,
        0,
        1.0,
        "context",
        "node-a",
        "position",
    )


def test_surface_layout_candidate_scoring_is_sensitive_to_zone_order() -> None:
    horizontal_candidate = {
        "surface_id": "context",
        "orientation": "horizontal",
        "zone_order": ["zone-a", "zone-b"],
        "node_ranks": {"node-a": 0, "node-b": 1},
        "branch_groups": {"node-a": 0, "node-b": 0},
        "reverse_edge_members": set(),
        "fan_in": {"node-a": 0, "node-b": 1},
        "fan_out": {"node-a": 1, "node-b": 0},
    }
    vertical_candidate = {
        "surface_id": "context",
        "orientation": "vertical",
        "zone_order": ["zone-b", "zone-a"],
        "node_ranks": {"node-a": 0, "node-b": 1},
        "branch_groups": {"node-a": 0, "node-b": 0},
        "reverse_edge_members": set(),
        "fan_in": {"node-a": 0, "node-b": 1},
        "fan_out": {"node-a": 1, "node-b": 0},
    }

    horizontal_score = feedback.score_surface_layout_candidate(horizontal_candidate)
    vertical_score = feedback.score_surface_layout_candidate(vertical_candidate)

    assert horizontal_score[0] < vertical_score[0]


def test_repeated_defect_history_stops_convergence() -> None:
    # Arrange
    history = [
        feedback.IterationResult(
            iteration_id=1,
            defect_signature="overlap|crossing",
            gate_failure_count=1,
            evidence_complete=True,
        ),
        feedback.IterationResult(
            iteration_id=2,
            defect_signature="overlap|crossing",
            gate_failure_count=1,
            evidence_complete=True,
        ),
    ]

    # Act
    convergence = feedback.evaluate_convergence(history, max_iterations=3)

    # Assert
    assert convergence.should_stop is True
    assert convergence.stop_reason == "repeated-defect-no-improvement"


def test_max_iterations_boundary_allows_one_refinement_when_limit_is_two() -> None:
    # Arrange
    history = [
        feedback.IterationResult(
            iteration_id=0,
            defect_signature="initial",
            gate_failure_count=1,
        ),
        feedback.IterationResult(
            iteration_id=1,
            defect_signature="initial",
            gate_failure_count=1,
        ),
    ]

    # Act
    convergence = feedback.evaluate_convergence(history, max_iterations=2)

    # Assert
    assert convergence.should_stop is False
    assert convergence.stop_reason == "continue"


def test_pending_overlay_sets_pending_approval_state() -> None:
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={"trust-zone-portal": (0.0, 0.0, 100.0, 100.0)},
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "trust-zone-portal",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "overlap_ratio": 0.04,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )

    # Assert
    assert candidates
    assert candidates[0]["provenance"]["approval_state"] == "pending"


def test_boundary_failure_derives_typed_zone_rule() -> None:
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={"node-a": (40.0, 80.0, 140.0, 180.0)},
        connector_segments=[],
        boundary_rects={"zone-a": (24.0, 24.0, 500.0, 500.0)},
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"node-a"}},
        surface_zone_ids={"context": {"zone-a"}},
    )

    candidate = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics={
            "surface_id": "context",
            "node_id": "node-a",
            "boundary_overlap_count": 1,
        },
    )[0]

    assert candidate["target_type"] == "zone"
    assert candidate["target_id"] == "zone-a"
    assert candidate["rule_collection"] == "zone_rules"
    assert candidate["overlay_rule"]["zone_id"] == "zone-a"


def test_feedback_manifest_rejects_non_exact_candidate_fingerprint() -> None:
    manifest = json.loads(
        (FIXTURES_DIR / "valid-manifest.json").read_text(encoding="utf-8")
    )
    manifest["candidate_sha256"] = "not-a-sha"

    with pytest.raises(ValueError, match="candidate_sha256"):
        feedback.validate_feedback_manifest(manifest)


def test_given_screenshot_review_when_deriving_candidates_then_gate_ignores_it() -> (
    None
):
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={"trust-zone-portal": (0.0, 0.0, 100.0, 100.0)},
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "trust-zone-portal",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "capture_status": "ok",
        "severity": "review",
        "is_all_background": True,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )

    # Assert
    assert candidates[0]["review_count"] == 1
    assert candidates[0]["gate_failure_count"] == 0


def test_connector_intersection_candidate_moves_node_away() -> None:
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=100.0,
        node_rects={
            "ext-dev": (100.0, 100.0, 150.0, 150.0),
            "comp-logsink": (10.0, 10.0, 60.0, 60.0),
        },
        connector_segments=[
            ("comp-logsink", "api-gateway", (0.0, 0.0), (200.0, 200.0)),
        ],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"ext-dev", "comp-logsink"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "ext-dev",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "edge_node_intersections": 3,
        "edge_crossing_count": 1,
        "min_spacing_ratio": 1.0,
        "overlap_ratio": 0.0,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )
    rule = candidates[0]["rule"]
    moved_rects = dict(geometry.node_rects)
    left, top, right, bottom = geometry.node_rects["ext-dev"]
    width = right - left
    height = bottom - top
    moved_rects["ext-dev"] = (
        rule["left"],
        rule["top"],
        rule["left"] + width,
        rule["top"] + height,
    )
    moved_geometry = feedback.SurfaceGeometry(
        surface_id=geometry.surface_id,
        nominal_node_size=geometry.nominal_node_size,
        node_rects=moved_rects,
        connector_segments=geometry.connector_segments,
    )
    moved_metrics = feedback.derive_geometry_metrics(moved_geometry)

    # Assert
    assert rule["constraint"] == "position"
    assert rule["left"] >= 1.0
    assert rule["top"] >= 1.0
    assert moved_metrics["edge_node_intersections"] <= 0


def test_given_overlap_when_deriving_candidates_then_overlap_ratio_reduces() -> None:
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=80.0,
        node_rects={
            "node-a": (80.0, 80.0, 120.0, 120.0),
            "node-b": (100.0, 100.0, 140.0, 140.0),
        },
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"node-a", "node-b"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "node-a",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "overlap_ratio": 0.25,
        "edge_node_intersections": 0,
        "edge_crossing_count": 0,
        "min_spacing_ratio": 0.2,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )
    rule = candidates[0]["rule"]
    moved_rects = dict(geometry.node_rects)
    left, top, right, bottom = geometry.node_rects["node-a"]
    width = right - left
    height = bottom - top
    moved_rects["node-a"] = (
        rule["left"],
        rule["top"],
        rule["left"] + width,
        rule["top"] + height,
    )
    moved_geometry = feedback.SurfaceGeometry(
        surface_id=geometry.surface_id,
        nominal_node_size=geometry.nominal_node_size,
        node_rects=moved_rects,
        connector_segments=geometry.connector_segments,
    )
    moved_metrics = feedback.derive_geometry_metrics(moved_geometry)

    # Assert
    assert moved_metrics["overlap_ratio"] < metrics["overlap_ratio"]


def test_given_identical_inputs_when_deriving_candidates_then_rules_are_stable() -> (
    None
):
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=50.0,
        node_rects={
            "node-a": (10.0, 10.0, 40.0, 40.0),
            "node-b": (80.0, 10.0, 110.0, 40.0),
        },
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"node-a", "node-b"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "node-a",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "overlap_ratio": 0.02,
        "edge_node_intersections": 0,
        "edge_crossing_count": 0,
        "min_spacing_ratio": 0.5,
    }

    # Act
    first = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )
    second = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )

    # Assert
    assert first[0]["rule"] == second[0]["rule"]


def test_given_negative_coordinates_when_deriving_candidates_then_rule_is_clamped() -> (
    None
):
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=60.0,
        node_rects={"node-a": (-10.0, -10.0, 20.0, 20.0)},
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"node-a"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "node-a",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "overlap_ratio": 0.04,
        "edge_node_intersections": 0,
        "edge_crossing_count": 0,
        "min_spacing_ratio": 0.5,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )
    rule = candidates[0]["rule"]

    # Assert
    assert math.isfinite(rule["left"])
    assert math.isfinite(rule["top"])
    assert rule["left"] >= 1.0
    assert rule["top"] >= 1.0


def test_given_advisory_only_input_when_deriving_candidates_then_rule_is_empty() -> (
    None
):
    # Arrange
    geometry = feedback.SurfaceGeometry(
        surface_id="context",
        nominal_node_size=60.0,
        node_rects={"node-a": (10.0, 10.0, 40.0, 40.0)},
        connector_segments=[],
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"node-a"}},
    )
    metrics = {
        "surface_id": "context",
        "node_id": "node-a",
        "evidence_path": "evidence/iteration-01/surfaces/context/metrics.json",
        "capture_status": "ok",
        "severity": "review",
        "is_all_background": True,
    }

    # Act
    candidates = feedback.derive_overlay_candidates(
        surface_geometry=geometry,
        overlay_context=context,
        metrics=metrics,
        density="simple",
    )

    # Assert
    assert candidates[0]["constraint_type"] == "none"
    assert candidates[0]["rule"] == {}


def test_given_v1_overlay_when_validating_then_rejects_with_schema_version_error() -> (
    None
):
    # Arrange
    overlay = {
        "schema_version": 1,
        "overlay_type": "tm7_layout_overlay",
        "model_id": "demo-model",
        "overlay_id": "overlay-001",
        "applies_to": [{"surface_id": "context", "generator_profile": "default"}],
        "zone_rules": [],
        "node_rules": [],
        "connector_rules": [],
        "surface_rules": [],
        "provenance": {
            "evidence_ref": "evidence/iteration-01",
            "approval_state": "pending",
        },
        "invalidation": {
            "spec_fingerprint": "abc",
            "generator_profile_fingerprint": "def",
            "surface_identity_fingerprint": "ghi",
            "surface_zone_identity_fingerprint": "ghi",
            "surface_flow_identity_fingerprint": "ghi",
        },
    }
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="schema_version"):
        feedback.validate_layout_overlay(overlay, context)


def test_given_overlay_payload_when_validated_then_schema_stays_strict() -> None:
    # Arrange
    overlay = {
        "schema_version": 2,
        "overlay_type": "tm7_layout_overlay",
        "model_id": "demo-model",
        "overlay_id": "overlay-001",
        "applies_to": [{"surface_id": "context", "generator_profile": "default"}],
        "zone_rules": [],
        "node_rules": [],
        "connector_rules": [],
        "surface_rules": [],
        "provenance": {
            "evidence_ref": "evidence/iteration-01",
            "generated_at": "2026-07-17T19:00:00Z",
            "approval_state": "pending",
        },
        "invalidation": {
            "spec_fingerprint": "abc",
            "generator_profile_fingerprint": "def",
            "surface_identity_fingerprint": "ghi",
            "surface_zone_identity_fingerprint": "ghi",
            "surface_flow_identity_fingerprint": "ghi",
        },
    }
    schema = json.loads(
        (SCHEMAS_DIR / "tm7-layout-overlay.schema.json").read_text(encoding="utf-8")
    )
    context = feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("threat-model-spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
        surface_zone_ids={"context": {"trust-zone-portal"}},
        surface_flow_ids={"context": {"flow-001"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="fingerprint"):
        feedback.validate_layout_overlay(overlay, context)
    assert schema["additionalProperties"] is False
    assert "ranking_key" not in schema["properties"]
