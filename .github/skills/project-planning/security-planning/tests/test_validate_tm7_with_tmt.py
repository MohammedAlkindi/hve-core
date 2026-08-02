# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Mocked tests for the native TM7 application harness."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import validate_tm7_with_tmt  # noqa: E402


class FakeProcess:
    """Minimal harness-owned process double."""

    def __init__(self) -> None:
        self.closed = False
        self.pid = 42

    def poll(self) -> int | None:
        return 0 if self.closed else None

    def terminate(self) -> None:
        self.closed = True

    def wait(self, timeout: float | None = None) -> int:
        self.closed = True
        return 0

    def kill(self) -> None:
        self.closed = True


class FakeRectangle:
    """Window rectangle test double."""

    def __init__(self, width: int, height: int) -> None:
        self._width = width
        self._height = height

    def width(self) -> int:
        return self._width

    def height(self) -> int:
        return self._height


class FakeWindow:
    """Top-level window selector test double."""

    def __init__(
        self,
        title: str,
        width: int,
        height: int,
        *,
        handle: int = 1,
        descendants: list[Any] | None = None,
        element_info: Any | None = None,
    ) -> None:
        self.title = title
        self.bounds = FakeRectangle(width, height)
        self.handle = handle
        self._descendants = descendants or []
        self._element_info = element_info
        self.maximize_calls = 0
        self.restore_calls = 0
        self.maximized = False

    def maximize(self) -> None:
        self.maximize_calls += 1
        self.maximized = True

    def restore(self) -> None:
        self.restore_calls += 1
        self.maximized = False

    def is_maximized(self) -> bool:
        return self.maximized

    def window_text(self) -> str:
        return self.title

    def rectangle(self) -> FakeRectangle:
        return self.bounds

    def process_id(self) -> int:
        return 42

    def descendants(self, control_type: str | None = None) -> list[Any]:
        return self._descendants

    @property
    def element_info(self) -> Any:
        return self._element_info

    def is_visible(self) -> bool:
        return True


class FakeControl:
    """UIA control double with element info and descendants."""

    def __init__(
        self,
        control_type: str,
        name: str,
        *,
        automation_id: str = "",
        handle: int = 0,
        descendants: list[Any] | None = None,
        left: int = 0,
        top: int = 0,
        width: int = 100,
        height: int = 100,
    ) -> None:
        self._element_info = type(
            "ElementInfo",
            (),
            {
                "control_type": control_type,
                "name": name,
                "automation_id": automation_id,
            },
        )()
        self._descendants = descendants or []
        self._rectangle = type(
            "Rectangle",
            (),
            {
                "left": lambda self: left,
                "top": lambda self: top,
                "right": lambda self: left + width,
                "bottom": lambda self: top + height,
                "width": lambda self: width,
                "height": lambda self: height,
            },
        )()
        self.handle = handle

    @property
    def element_info(self) -> Any:
        return self._element_info

    def rectangle(self) -> Any:
        return self._rectangle

    def descendants(self, control_type: str | None = None) -> list[Any]:
        return self._descendants

    def click_input(self) -> None:
        return None

    def is_visible(self) -> bool:
        return True


def _input_model(tmp_path: Path, name: str = "model.tm7") -> Path:
    path = tmp_path / name
    path.write_text("model", encoding="utf-8")
    return path


def _write_feedback_spec(path: Path) -> None:
    path.write_text(
        json.dumps(
            {
                "project_metadata": {"name": "demo"},
                "mode": "diagram-only-defer-to-tmt",
                "representations": {
                    "context_diagrams": [
                        {
                            "id": "context",
                            "name": "context",
                            "elements": [
                                {
                                    "id": "trust-zone-portal",
                                    "kind": "process",
                                    "name": "Portal",
                                }
                            ],
                            "flows": [],
                        }
                    ],
                    "functional_scenarios": [
                        {
                            "id": "other",
                            "name": "other",
                            "elements": [
                                {
                                    "id": "other-node",
                                    "kind": "process",
                                    "name": "Other node",
                                }
                            ],
                            "flows": [],
                        }
                    ],
                },
            }
        ),
        encoding="utf-8",
    )


def _patch_successful_automation(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> list[FakeProcess]:
    executable = tmp_path / "ThreatModeling.exe"
    executable.write_bytes(b"exe")
    processes: list[FakeProcess] = []

    def launch(*args: Any, **kwargs: Any) -> FakeProcess:
        process = FakeProcess()
        processes.append(process)
        return process

    def save_as(window: Any, destination: Path, timeout: float) -> None:
        destination.write_text("model", encoding="utf-8")

    def export(window: Any, destination: Path, timeout: float) -> None:
        destination.write_text("id,title\n1,Threat\n", encoding="utf-8")

    summary = {
        "sha256": "hash",
        "generation_enabled": "false",
        "instance_count": 1,
        "instances": [{"id": "1", "type_id": "TH-test"}],
        "knowledge_base_type_ids": ["TH-test"],
        "custom_type_ids": [],
        "drawing_surface_hash": "surface-hash",
        "knowledge_base_hash": "kb-hash",
    }
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=executable,
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "launch_tmt_process", launch)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_tmt_window",
        lambda *args, **kwargs: object(),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "detect_modal_dialog",
        lambda window: None,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda window: [],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: _write_test_png(path, 600, 400),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "build_uia_tree",
        lambda window: "Button|analysis|Analysis View\n",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "open_analysis_view",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "export_threat_csv", export)
    monkeypatch.setattr(validate_tm7_with_tmt, "save_model_as", save_as)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "save_current_model",
        lambda window, model_path, timeout: None,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "collect_semantic_summary",
        lambda path: {**summary, "path": str(path)},
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "sha256_file",
        lambda path: "sha256",
    )
    return processes


def test_given_cross_candidate_semantics_when_only_geometry_changes_then_does_not() -> (
    None
):
    # Arrange
    baseline_summary = {
        "instance_count": 1,
        "threat_count": 1,
        "threat_identities": ["threat|type|state"],
        "element_identities": ["context|node-a|store|TH-1|guid-a"],
        "flow_identities": ["context|flow-1|source|target|src|dst"],
        "drawing_surface_hash": "old-surface",
        "knowledge_base_hash": "old-kb",
    }
    current_summary = {
        "instance_count": 1,
        "threat_count": 1,
        "threat_identities": ["threat|type|state"],
        "element_identities": ["context|node-a|store|TH-1|guid-a"],
        "flow_identities": ["context|flow-1|source|target|src|dst"],
        "drawing_surface_hash": "new-surface",
        "knowledge_base_hash": "new-kb",
    }

    # Act
    regression = validate_tm7_with_tmt._evaluate_semantic_regression(
        current_summary=current_summary,
        baseline_summary=baseline_summary,
    )

    # Assert
    assert regression is False


def test_given_production_feedback_path_when_identity_changes_then_blocks(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The production path must reach the semantic evaluator on its own.

    `_validate_feedback_candidate` used to return a hardcoded
    `semantic_regression: False`, and the caller only recomputed when the value
    was None, so `_evaluate_semantic_regression` was never reached in
    production. This test patches the inner `_validate_candidate` seam instead,
    so the real feedback-candidate body and the real evaluator both run.
    """
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"

    def _summary(threat_identity: str) -> dict:
        return {
            "instance_count": 1,
            "threat_count": 1,
            "threat_identities": [threat_identity],
            "element_identities": ["context|node-a|store|TH-1|guid-a"],
            "flow_identities": ["context|flow-1|source|target|src|dst"],
            "instances": [{"id": "1"}],
            "drawing_surface_hash": "surface",
            "knowledge_base_hash": "kb",
        }

    calls: list[int] = []

    def _fake_validate_candidate(**kwargs: object) -> dict:
        calls.append(1)
        # The second candidate declares a different threat identity, which is a
        # semantic change rather than a geometry-only one.
        identity = "threat|type|state" if len(calls) == 1 else "threat|type|REPLACED"
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": _summary(identity),
            "after_summary": _summary(identity),
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 1,
                    "review_count": 1,
                    "warn_count": 0,
                    "max_severity_score": 3.0,
                    "constraint_type": "relative_to",
                    "capture_complete": True,
                    # An unresolved review finding keeps convergence from
                    # declaring readiness, so the loop runs a second candidate.
                    "findings": [
                        {
                            "surface_id": "context",
                            "metric_name": "node_spacing",
                            "severity": "review",
                            "category": "layout",
                        }
                    ],
                }
            ],
            "evidence_complete": True,
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_candidate",
        _fake_validate_candidate,
    )
    # Candidate regeneration is an unrelated collaborator here. Stubbing it
    # keeps the test focused on the semantic gate while leaving both
    # `_validate_feedback_candidate` and `_evaluate_semantic_regression` real.
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        lambda **kwargs: Path(str(kwargs["output_path"])).write_text(
            "candidate", encoding="utf-8"
        )
        or Path(str(kwargs["output_path"])),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=3,
        require_feedback_evidence=False,
    )

    # Assert
    assert len(calls) >= 2, (
        f"the loop must reach a second candidate to compare; "
        f"stopped with status={result.status} message={result.message}"
    )
    assert result.status == "semantic-regression"
    assert result.exit_code == validate_tm7_with_tmt.EXIT_VALIDATION_FAILURE
    assert result.status != "automated-ready-pending-human"


def test_given_strict_feedback_evidence_when_capture_is_missing_then_marks_incomplete(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "launch_tmt_process",
        lambda *args, **kwargs: FakeProcess(),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_tmt_window",
        lambda *args, **kwargs: FakeWindow("Threat Model", 800, 600),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "open_analysis_view", lambda *args, **kwargs: None
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: _write_test_png(path, 600, 400),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "build_uia_tree", lambda window: "")
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "export_threat_csv",
        lambda window, destination, timeout: destination.write_text(
            "id\n1\n", encoding="utf-8"
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "save_current_model",
        lambda window, model_path, timeout: None,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "close_owned_process", lambda process: None
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "collect_semantic_summary",
        lambda path: {
            "instance_count": 1,
            "instances": [{"id": "1", "type_id": "TH-test"}],
            "drawing_surface_hash": "surface",
            "knowledge_base_hash": "kb",
            "threat_identities": ["threat"],
            "element_identities": [],
            "flow_identities": [],
        },
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "compare_csv_exports", lambda before, after: True
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha256")
    monkeypatch.setattr(
        validate_tm7_with_tmt, "_capture_feedback_surface_evidence", lambda **kwargs: []
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "_derive_feedback_surface_metrics", lambda **kwargs: []
    )

    # Act
    output = validate_tm7_with_tmt._validate_candidate(
        executable=tmp_path / "ThreatModeling.exe",
        input_model=baseline_model,
        workspace=workspace,
        bundle=bundle,
        mode="validate",
        timeout_seconds=1.0,
        expected_threat_count=1,
        template_upgrade_policy="fail",
        delete_stale_threats=False,
        capture_feedback_surfaces=True,
        require_feedback_evidence=True,
    )

    # Assert
    assert output["evidence_complete"] is False


def _write_test_png(path: Path, width: int, height: int) -> None:
    image = Image.new("RGB", (width, height), color="white")
    image.save(path)


def test_given_excessive_scroll_extent_when_capture_then_marks_evidence_incomplete(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    model_path = _input_model(tmp_path, "surface.tm7")
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="context",
        surface_guid="guid-context",
        surface_name="System context",
        tab_index=0,
    )
    diagram_pane = FakeControl(
        "Pane",
        "Diagram",
        automation_id=validate_tm7_with_tmt.DIAGRAM_PANE_AUTOMATION_ID,
        left=0,
        top=0,
        width=1200,
        height=800,
    )
    scroll_interface = type(
        "ScrollInterface",
        (),
        {
            "CurrentHorizontalScrollPercent": 0.0,
            "CurrentVerticalScrollPercent": 0.0,
            "SetScrollPercent": lambda self, horizontal, vertical: None,
        },
    )()
    diagram_pane.iface_scroll = scroll_interface

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_diagram_pane",
        lambda window: diagram_pane,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "read_canvas_announcement",
        lambda pane: "Canvas",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: _write_test_png(path, 600, 400),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "build_uia_tree", lambda pane: "")

    # Act
    payload = validate_tm7_with_tmt.capture_surface_evidence(
        FakeWindow("Threat Model", 1400, 900),
        bundle,
        surface,
        model_path=model_path,
        require_feedback_evidence=False,
        scroll_extent_ratio_x=3.0,
        scroll_extent_ratio_y=1.0,
    )

    # Assert
    assert payload["scroll_coverage_complete"] is False
    assert payload["tile_manifest"]["consistent"] is False
    assert payload["tile_manifest"]["tile_count"] == 0


def test_given_tiled_surface_evidence_when_capture_then_binds_tile_manifest(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    model_path = _input_model(tmp_path, "surface.tm7")
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="context",
        surface_guid="guid-context",
        surface_name="System context",
        tab_index=0,
    )
    diagram_pane = FakeControl(
        "Pane",
        "Diagram",
        automation_id=validate_tm7_with_tmt.DIAGRAM_PANE_AUTOMATION_ID,
        left=0,
        top=0,
        width=1200,
        height=800,
    )
    scroll_interface = type(
        "ScrollInterface",
        (),
        {
            "CurrentHorizontalScrollPercent": 0.0,
            "CurrentVerticalScrollPercent": 0.0,
            "SetScrollPercent": lambda self, horizontal, vertical: None,
        },
    )()
    diagram_pane.iface_scroll = scroll_interface
    diagram_pane._descendants = [
        FakeControl("Pane", "Viewport", automation_id="Viewport"),
    ]

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_diagram_pane",
        lambda window: diagram_pane,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "read_canvas_announcement",
        lambda pane: "Canvas",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: _write_test_png(path, 600, 400),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "build_uia_tree", lambda pane: "")

    # Act
    payload = validate_tm7_with_tmt.capture_surface_evidence(
        FakeWindow("Threat Model", 1400, 900),
        bundle,
        surface,
        model_path=model_path,
        require_feedback_evidence=True,
        scroll_extent_ratio_x=2.0,
        scroll_extent_ratio_y=2.0,
    )

    # Assert
    assert payload["scroll_restored"] is True
    assert payload["screenshot_dimensions"]["width"] == 600
    assert payload["screenshot_dimensions"]["height"] == 400
    assert payload["crop_dimensions"]["width"] == 1200
    assert payload["crop_dimensions"]["height"] == 800
    assert payload["tile_manifest"]["position_count"] == 4
    assert payload["tile_manifest"]["max_axis_positions"] == 2
    assert payload["tile_manifest"]["consistent"] is True
    assert payload["tile_manifest"]["tile_count"] == 4
    assert payload["stitched_preview_path"].endswith(".png")

    calibration_contract = validate_tm7_with_tmt._build_layout_calibration_contract(
        [payload],
        calibration_context={
            "contract": "layout_calibration_v1",
            "scope": "same-run",
            "viewport_target": [0.0, 0.0, 1200.0, 800.0],
            "pane_rect": [0, 0, 1200, 800],
            "scroll_percentages": {"horizontal": 0.0, "vertical": 0.0},
            "effective_scale": {"x": 1.0, "y": 1.0},
            "screenshot_dimensions": {"width": 600, "height": 400},
            "crop_dimensions": {"width": 1200, "height": 800},
            "confidence": {
                "pane_measured": True,
                "scroll_interface_found": True,
                "consistent": True,
                "failure_reason": None,
            },
        },
    )
    assert calibration_contract["screenshot_dimensions"] == {
        "width": 600,
        "height": 400,
    }
    assert calibration_contract["crop_dimensions"] == {"width": 1200, "height": 800}


def test_calibration_contract_uses_measurements_not_fallback_defaults(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Derive effective scale and scroll percentages from real pane measurements."""
    # Arrange
    model_path = _input_model(tmp_path, "surface.tm7")
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="context",
        surface_guid="guid-context",
        surface_name="System context",
        tab_index=0,
    )
    diagram_pane = FakeControl(
        "Pane",
        "Diagram",
        automation_id=validate_tm7_with_tmt.DIAGRAM_PANE_AUTOMATION_ID,
        left=10,
        top=20,
        width=1200,
        height=800,
    )
    scroll_interface = type(
        "ScrollInterface",
        (),
        {
            "CurrentHorizontalScrollPercent": 25.0,
            "CurrentVerticalScrollPercent": 40.0,
            "SetScrollPercent": lambda self, horizontal, vertical: None,
        },
    )()
    diagram_pane.iface_scroll = scroll_interface

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_diagram_pane",
        lambda window: diagram_pane,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "read_canvas_announcement",
        lambda pane: "Canvas",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: _write_test_png(path, 600, 400),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "build_uia_tree", lambda pane: "")

    payload = validate_tm7_with_tmt.capture_surface_evidence(
        FakeWindow("Threat Model", 1400, 900),
        bundle,
        surface,
        model_path=model_path,
        require_feedback_evidence=True,
        scroll_extent_ratio_x=2.0,
        scroll_extent_ratio_y=2.0,
        viewport_target=(0.0, 0.0, 2000.0, 1000.0),
        pane_rect={"left": 10, "top": 20, "width": 1200, "height": 800},
        calibration_context={
            "contract": "layout_calibration_v1",
            "scope": "same-run",
            "viewport_target": [0.0, 0.0, 2000.0, 1000.0],
            "pane_rect": [10, 20, 1200, 800],
            "scroll_percentages": {"horizontal": 25.0, "vertical": 40.0},
            "effective_scale": {"x": 1.0, "y": 1.0},
            "screenshot_dimensions": {"width": 600, "height": 400},
            "crop_dimensions": {"width": 1200, "height": 800},
            "confidence": {
                "pane_measured": True,
                "scroll_interface_found": True,
                "consistent": True,
                "failure_reason": None,
            },
        },
    )

    # Act
    contract = validate_tm7_with_tmt._build_layout_calibration_contract(
        [payload],
        calibration_context=None,
    )

    # Assert
    assert contract["scroll_percentages"] == {"horizontal": 25.0, "vertical": 40.0}
    assert contract["effective_scale"] == {"x": 0.6, "y": 0.8}
    assert contract["pane_rect"] == [10, 20, 1200, 800]
    assert contract["confidence"]["consistent"] is True


def test_calibration_contract_marks_inconsistent_pane() -> None:
    """Reject calibration contracts when the pane or crop remains unmeasured."""
    # Arrange
    payload = {
        "pane_rect": {"left": 0, "top": 0, "width": 0, "height": 0},
        "viewport_target": [0.0, 0.0, 0.0, 0.0],
        "screenshot_dimensions": {"width": 600, "height": 400},
        "crop_dimensions": {"width": 0, "height": 0},
        "scroll_coverage_complete": True,
        "scroll_restored": True,
    }

    # Act
    contract = validate_tm7_with_tmt._build_layout_calibration_contract(
        [payload],
        calibration_context={
            "contract": "layout_calibration_v1",
            "scope": "same-run",
            "viewport_target": [0.0, 0.0, 1200.0, 800.0],
            "pane_rect": [0, 0, 0, 0],
            "scroll_percentages": {"horizontal": 0.0, "vertical": 0.0},
            "effective_scale": {"x": 1.0, "y": 1.0},
            "screenshot_dimensions": {"width": 600, "height": 400},
            "crop_dimensions": {"width": 0, "height": 0},
            "confidence": {
                "pane_measured": True,
                "scroll_interface_found": True,
                "consistent": True,
                "failure_reason": None,
            },
        },
    )

    # Assert
    assert contract["confidence"]["consistent"] is False
    assert contract["confidence"]["failure_reason"] is not None


def test_given_feedback_overlay_without_real_rule_then_raises() -> None:
    # Arrange
    candidate = {
        "surface_id": "context",
        "node_id": "trust-zone-portal",
        "constraint_type": "position",
        "rule": {},
    }
    overlay_context = validate_tm7_with_tmt.tm7_visual_feedback.OverlayContext(
        model_id="demo-model",
        spec_path=Path("spec.yaml"),
        spec_sha256="abc",
        generator_profile="default",
        generator_profile_sha256="def",
        surface_ids={"context"},
        surface_node_ids={"context": {"trust-zone-portal"}},
    )

    # Act / Assert
    with pytest.raises(ValueError, match="rule"):
        validate_tm7_with_tmt._build_feedback_overlay(
            spec_path=Path("spec.yaml"),
            candidate=candidate,
            overlay_context=overlay_context,
            iteration_id=1,
            spec_sha256="abc",
            generator_profile="default",
            generator_profile_sha256="def",
            candidate_path=Path("candidate.tm7"),
            ranking_key=(0, 0, 0, 0.0, "context", "trust-zone-portal", "position"),
        )


def test_given_feedback_success_when_run_then_emits_start_progress_and_release(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"
    evidence_dir = tmp_path / "evidence"
    caplog.set_level("INFO")

    def fake_generate_candidate(
        *, spec_path: Path, output_path: Path, **_: Any
    ) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def fake_validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "threat_identities": ["threat"],
                "element_identities": [],
                "flow_identities": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "threat_identities": ["threat"],
                "element_identities": [],
                "flow_identities": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 0,
                    "review_count": 0,
                    "warn_count": 0,
                    "max_severity_score": 0.0,
                    "constraint_type": "position",
                    "findings": [],
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "semantic_summary": {"instance_count": 1},
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe", version="7.3.51110.1", source="test"
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        fake_generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "_validate_feedback_candidate", fake_validate_candidate
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha256")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=evidence_dir,
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.status == "automated-ready-pending-human"
    assert caplog.text.count("Native TMT UI automation will control") == 1
    assert caplog.text.count("Candidate baseline") == 1
    assert caplog.text.count("Native TMT UI automation is complete") == 1


def test_given_feedback_loop_when_validation_failure_then_emits_single_release_notice(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"
    evidence_dir = tmp_path / "evidence"
    caplog.set_level("INFO")

    def fake_generate_candidate(
        *, spec_path: Path, output_path: Path, **_: Any
    ) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def fake_validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        raise validate_tm7_with_tmt.HarnessFailure(
            "boom",
            validate_tm7_with_tmt.EXIT_VALIDATION_FAILURE,
        )

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe", version="7.3.51110.1", source="test"
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        fake_generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "_validate_feedback_candidate", fake_validate_candidate
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha256")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=evidence_dir,
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_VALIDATION_FAILURE
    assert caplog.text.count("Native TMT UI automation will control") == 1
    assert caplog.text.count("Native TMT UI automation is complete") == 1


def test_given_feedback_loop_when_clean_iteration_then_manifest_stop_reason_is(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"
    evidence_dir = tmp_path / "evidence"

    def fake_generate_candidate(
        *, spec_path: Path, output_path: Path, **_: Any
    ) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def fake_validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "threat_identities": ["threat"],
                "element_identities": [],
                "flow_identities": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "threat_identities": ["threat"],
                "element_identities": [],
                "flow_identities": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 0,
                    "review_count": 0,
                    "warn_count": 0,
                    "max_severity_score": 0.0,
                    "constraint_type": "position",
                    "findings": [],
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "semantic_summary": {"instance_count": 1},
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe", version="7.3.51110.1", source="test"
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        fake_generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt, "_validate_feedback_candidate", fake_validate_candidate
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha256")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=evidence_dir,
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.status == "automated-ready-pending-human"
    manifest = json.loads((evidence_dir / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["stop_reason"] == "automated-ready-pending-human"


def test_given_flat_geometry_when_scored_then_uses_real_rectangles(
    tmp_path: Path,
) -> None:
    # Arrange
    candidate_model = tmp_path / "candidate.tm7"
    candidate_model.write_text(
        """<ThreatModel>
  <DrawingSurfaceList>
    <DrawingSurfaceModel>
      <Header>context</Header>
      <Guid>surface-guid</Guid>
      <Borders>
        <KeyValueOfguidanyType>
          <Value>
            <Id>node-1</Id>
            <Kind>process</Kind>
            <Name>Portal</Name>
            <Left>10</Left>
            <Top>20</Top>
            <Width>100</Width>
            <Height>90</Height>
            <Guid>node-guid-1</Guid>
          </Value>
        </KeyValueOfguidanyType>
      </Borders>
      <Lines>
        <KeyValueOfguidanyType>
          <Value>
            <Id>flow-1</Id>
            <SourceGuid>node-guid-1</SourceGuid>
            <TargetGuid>node-guid-2</TargetGuid>
            <SourceX>10</SourceX>
            <SourceY>20</SourceY>
            <TargetX>120</TargetX>
            <TargetY>40</TargetY>
          </Value>
        </KeyValueOfguidanyType>
      </Lines>
    </DrawingSurfaceModel>
  </DrawingSurfaceList>
</ThreatModel>""",
        encoding="utf-8",
    )

    payloads = [{"surface_id": "context", "screenshot_path": "ignored.png"}]

    # Act
    metrics = validate_tm7_with_tmt._derive_feedback_surface_metrics(
        surface_payloads=payloads,
        bundle=validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence"),
        candidate_model_path=candidate_model,
    )

    # Assert
    assert metrics[0]["surface_id"] == "context"
    assert metrics[0]["node_id"] == "node-1"
    assert metrics[0]["capture_status"] == "incomplete"


def test_given_feedback_loop_when_stop_status_is_normalized_then_returns() -> None:
    # Act
    reason = validate_tm7_with_tmt._normalize_feedback_stop_reason(
        "passed",
        require_feedback_evidence=True,
        exit_code=validate_tm7_with_tmt.EXIT_SUCCESS,
    )

    # Assert
    assert reason == "automated-ready-pending-human"


def test_given_surface_payloads_when_scored_then_persists_metrics_and_findings(
    tmp_path: Path,
) -> None:
    # Arrange
    candidate_model = tmp_path / "candidate.tm7"
    candidate_model.write_text(
        """<ThreatModel>
    <DrawingSurfaceList>
        <DrawingSurfaceModel>
            <Header>context</Header>
            <Guid>surface-guid</Guid>
            <Borders>
                <KeyValueOfguidanyType>
                    <Value>
                        <Id>node-1</Id>
                        <Kind>process</Kind>
                        <Name>Portal</Name>
                        <Left>10</Left>
                        <Top>20</Top>
                        <Width>100</Width>
                        <Height>90</Height>
                        <Guid>node-guid-1</Guid>
                    </Value>
                </KeyValueOfguidanyType>
            </Borders>
            <Lines />
        </DrawingSurfaceModel>
    </DrawingSurfaceList>
</ThreatModel>""",
        encoding="utf-8",
    )
    evidence_dir = tmp_path / "evidence"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "surface_id": "context",
        "surface_name": "context",
        "capture_scope": "pane",
        "annotation": "review",
        "crop": {"left": 0, "top": 0, "width": 100, "height": 100},
        "screenshot_path": "screenshots/context.png",
    }
    (evidence_dir / "screenshots").mkdir(parents=True, exist_ok=True)
    (evidence_dir / "screenshots" / "context.png").write_bytes(b"\x00" * 32)

    # Act
    metrics = validate_tm7_with_tmt._derive_feedback_surface_metrics(
        surface_payloads=[payload],
        bundle=validate_tm7_with_tmt.EvidenceBundle(evidence_dir),
        candidate_model_path=candidate_model,
    )

    # Assert
    assert metrics[0]["surface_id"] == "context"
    assert metrics[0]["node_id"] == "node-1"
    assert metrics[0]["findings"]
    assert metrics[0]["capture_scope"] == "pane"


def test_given_clean_feedback_when_completed_then_emits_no_movement_rule(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"
    evidence_dir = tmp_path / "evidence"

    def fake_generate_candidate(
        *, spec_path: Path, output_path: Path, **_: Any
    ) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def fake_validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 1,
                "instances": [{"id": "1"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [{"id": "1"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 0,
                    "review_count": 0,
                    "warn_count": 0,
                    "max_severity_score": 0.0,
                    "constraint_type": "position",
                    "findings": [],
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "semantic_summary": {"instance_count": 1},
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        fake_generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        fake_validate_candidate,
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=evidence_dir,
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_SUCCESS
    payload = json.loads(overlay_output.read_text(encoding="utf-8"))
    assert payload["node_rules"] == []
    assert "rules" not in payload
    assert "ranking_key" not in payload


def test_given_one_failing_surface_when_loop_runs_then_does_not_clear_gates(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    validation_calls = 0

    def generate_candidate(*, spec_path: Path, output_path: Path, **_: Any) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        nonlocal validation_calls
        validation_calls += 1
        summary = {
            "instance_count": 1,
            "threat_identities": ["threat"],
            "element_identities": ["element"],
            "flow_identities": [],
        }
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": summary,
            "after_summary": summary,
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "overlap_ratio": 0.0,
                    "edge_node_intersections": 0,
                    "edge_crossing_count": 0,
                    "min_spacing_ratio": 1.0,
                    "surface_geometry": {
                        "surface_id": "context",
                        "nominal_node_size": 100.0,
                        "node_rects": {"trust-zone-portal": [0.0, 0.0, 100.0, 100.0]},
                        "connector_segments": [],
                    },
                },
                {
                    "surface_id": "other",
                    "node_id": "other-node",
                    "overlap_ratio": 0.04,
                    "edge_node_intersections": 0,
                    "edge_crossing_count": 0,
                    "min_spacing_ratio": 1.0,
                    "surface_geometry": {
                        "surface_id": "other",
                        "nominal_node_size": 100.0,
                        "node_rects": {"other-node": [0.0, 0.0, 100.0, 100.0]},
                        "connector_segments": [],
                    },
                },
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        validate_candidate,
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=1,
    )

    # Assert
    manifest = json.loads(
        (tmp_path / "evidence" / "manifest.json").read_text(encoding="utf-8")
    )
    assert result.exit_code == validate_tm7_with_tmt.EXIT_FEEDBACK_NON_CONVERGENCE
    assert manifest["stop_reason"] == "max-iterations"
    assert manifest["iterations"][0]["gate_failure_count"] == 1
    assert validation_calls == 2


def test_given_captured_surface_when_binding_then_guid_resolves_the_surface(
    tmp_path: Path,
) -> None:
    # Arrange
    payloads = [
        {
            "surface_id": "captured-tab-0",
            "surface_guid": "guid-context",
            "surface_name": "System context",
            "capture_scope": "pane",
            "annotation": "System context",
            "crop": {"left": 0, "top": 0, "width": 1200, "height": 800},
            "screenshot_path": "surfaces/context.png",
            "surface_geometry": {"node_rects": {}},
        }
    ]
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    model_path = _input_model(tmp_path, "surface.tm7")

    # Act
    metrics = validate_tm7_with_tmt._derive_feedback_surface_metrics(
        surface_payloads=payloads,
        bundle=bundle,
        candidate_model_path=model_path,
        surface_id_by_guid={"guid-context": "context"},
    )

    # Assert
    assert [metric["surface_id"] for metric in metrics] == ["context"]


def test_given_unbound_screenshot_guid_when_deriving_then_capture_is_incomplete(
    tmp_path: Path,
) -> None:
    # Arrange
    payloads = [
        {
            "surface_id": "captured-tab-0",
            "surface_guid": "guid-unknown",
            "surface_name": "",
            "capture_scope": "pane",
            "annotation": "",
            "crop": {"left": 0, "top": 0, "width": 1200, "height": 800},
            "screenshot_path": "surfaces/unknown.png",
            "surface_geometry": {"node_rects": {}},
        }
    ]
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    model_path = _input_model(tmp_path, "surface.tm7")

    # Act
    metrics = validate_tm7_with_tmt._derive_feedback_surface_metrics(
        surface_payloads=payloads,
        bundle=bundle,
        candidate_model_path=model_path,
        surface_id_by_guid={"guid-context": "context"},
    )

    # Assert
    assert metrics[0]["capture_status"] == "incomplete"


def test_given_clean_surfaces_when_building_manifest_then_human_review_stays_pending(
) -> None:
    # Arrange
    manifest = validate_tm7_with_tmt.tm7_visual_feedback.build_feedback_manifest(
        model_id="model",
        spec_path="spec.yaml",
        spec_sha256="a" * 64,
        generator_profile="profile",
        generator_profile_sha256="b" * 64,
        candidate_sha256="c" * 64,
        iteration_id="1",
        pinned_tmt_version="7.3.51110.1",
        surfaces=[{"surface_id": "context"}],
        convergence={
            "status": "automated-ready-pending-human",
            "stop_reason": "automated-ready-pending-human",
            "selected_candidate": None,
        },
    )

    # Act
    validate_tm7_with_tmt.tm7_visual_feedback.validate_feedback_manifest(manifest)

    # Assert
    assert manifest["surfaces"][0]["human_review_status"] == "pending"
    assert manifest["surfaces"][0]["human_review_required"] is True
    assert manifest["convergence"]["status"] == "automated-ready-pending-human"


def test_given_approved_surface_when_validating_manifest_then_it_is_rejected() -> None:
    # Arrange
    manifest = validate_tm7_with_tmt.tm7_visual_feedback.build_feedback_manifest(
        model_id="model",
        spec_path="spec.yaml",
        spec_sha256="a" * 64,
        generator_profile="profile",
        generator_profile_sha256="b" * 64,
        candidate_sha256="c" * 64,
        iteration_id="1",
        pinned_tmt_version="7.3.51110.1",
        surfaces=[{"surface_id": "context"}],
        convergence={
            "status": "automated-ready-pending-human",
            "stop_reason": "automated-ready-pending-human",
            "selected_candidate": None,
        },
    )
    manifest["surfaces"][0]["human_review_status"] = "approved"

    # Act & Assert
    with pytest.raises(ValueError, match="human_review_status must be pending"):
        validate_tm7_with_tmt.tm7_visual_feedback.validate_feedback_manifest(manifest)


def test_given_refinement_gate_when_loop_stops_then_iteration_is_recorded(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The refinement gate must not discard the iteration it stopped on."""
    # Arrange
    baseline_model = _input_model(tmp_path, "baseline.tm7")
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)

    def generate_candidate(*args: Any, **kwargs: Any) -> Path:
        output_path = Path(kwargs.get("output_path") or (tmp_path / "candidate.tm7"))
        output_path.write_bytes(baseline_model.read_bytes())
        return output_path

    def validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        summary = {
            "instance_count": 1,
            "threat_identities": ["threat"],
            "element_identities": ["element"],
            "flow_identities": [],
        }
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": summary,
            "after_summary": summary,
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "overlap_ratio": 0.04,
                    "edge_node_intersections": 0,
                    "edge_crossing_count": 0,
                    "min_spacing_ratio": 1.0,
                    "surface_geometry": {
                        "surface_id": "context",
                        "orientation": "horizontal",
                        "nominal_node_size": 100.0,
                        "node_rects": {"trust-zone-portal": [0.0, 0.0, 100.0, 100.0]},
                        "connector_segments": [],
                        "zone_content_rects": {"zone-a": [0.0, 0.0, 400.0, 400.0]},
                        "node_ranks": {"trust-zone-portal": 0},
                        "branch_groups": {"trust-zone-portal": 0},
                        "viewport_target": [0.0, 0.0, 1920.0, 1080.0],
                    },
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        validate_candidate,
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=3,
    )

    # Assert
    manifest = json.loads(
        (tmp_path / "evidence" / "manifest.json").read_text(encoding="utf-8")
    )
    assert result.exit_code == validate_tm7_with_tmt.EXIT_FEEDBACK_NON_CONVERGENCE
    assert manifest["stop_reason"] == "repeated-defect-no-improvement"
    assert manifest["iterations"], "the stopping iteration must be recorded"
    assert manifest["iterations"][0]["gate_failure_count"] > 0


def test_given_clean_surfaces_when_loop_runs_then_refinement_gate_defers(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A candidate that clears every gate must reach pending-human review."""
    # Arrange
    baseline_model = _input_model(tmp_path, "baseline.tm7")
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)

    def generate_candidate(*args: Any, **kwargs: Any) -> Path:
        output_path = Path(kwargs.get("output_path") or (tmp_path / "candidate.tm7"))
        output_path.write_bytes(baseline_model.read_bytes())
        return output_path

    def validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        summary = {
            "instance_count": 1,
            "threat_identities": ["threat"],
            "element_identities": ["element"],
            "flow_identities": [],
        }
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": summary,
            "after_summary": summary,
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "overlap_ratio": 0.0,
                    "edge_node_intersections": 0,
                    "edge_crossing_count": 0,
                    "min_spacing_ratio": 1.0,
                    "findings": [],
                    "surface_geometry": {
                        "surface_id": "context",
                        "orientation": "horizontal",
                        "nominal_node_size": 100.0,
                        "node_rects": {"trust-zone-portal": [0.0, 0.0, 100.0, 100.0]},
                        "connector_segments": [],
                        "zone_content_rects": {"zone-a": [0.0, 0.0, 400.0, 400.0]},
                        "node_ranks": {"trust-zone-portal": 0},
                        "branch_groups": {"trust-zone-portal": 0},
                        "viewport_target": [0.0, 0.0, 1920.0, 1080.0],
                    },
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        validate_candidate,
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=3,
    )

    # Assert
    manifest = json.loads(
        (tmp_path / "evidence" / "manifest.json").read_text(encoding="utf-8")
    )
    assert result.exit_code == validate_tm7_with_tmt.EXIT_SUCCESS
    assert manifest["stop_reason"] == "automated-ready-pending-human"


def test_given_window_when_maximizing_then_state_is_reported() -> None:
    # Arrange
    window = FakeWindow("Threat Model", 1400, 900)

    # Act
    maximized = validate_tm7_with_tmt.maximize_window(window)

    # Assert
    assert maximized is True
    assert window.maximize_calls == 1


def test_given_bounded_element_when_building_tree_then_rect_is_recorded() -> None:
    # Arrange
    rect = type("Rect", (), {"left": 10, "top": 20, "right": 130, "bottom": 44})()
    info = type(
        "Info",
        (),
        {
            "control_type": "Custom",
            "automation_id": "",
            "name": "reads config",
            "rectangle": rect,
        },
    )()
    window = type("Ctl", (), {"element_info": info, "descendants": lambda self: []})()

    # Act
    tree = validate_tm7_with_tmt.build_uia_tree(window)

    # Assert
    assert tree == "0|Custom||reads config|10|20|130|44\n"


def test_given_unmeasurable_element_when_building_tree_then_bounds_are_blank() -> None:
    # Arrange: a missing rectangle must not be reported as a zero-area rect,
    # which would read as a real measurement of a label drawn at the origin.
    info = type(
        "Info",
        (),
        {
            "control_type": "Custom",
            "automation_id": "",
            "name": "offscreen",
            "rectangle": None,
        },
    )()
    window = type("Ctl", (), {"element_info": info, "descendants": lambda self: []})()

    # Act
    tree = validate_tm7_with_tmt.build_uia_tree(window)

    # Assert
    assert tree == "0|Custom||offscreen||||\n"


def test_given_capture_when_screenshotting_then_window_is_not_restored(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Screenshots must not shrink an already maximized window."""
    # Arrange
    window = FakeWindow("Threat Model", 1400, 900)
    captured: dict[str, Any] = {}

    class FakeImage:
        def save(self, path: Any) -> None:
            captured["path"] = str(path)
            Path(path).write_bytes(b"\x89PNG\r\n\x1a\n")

    class FakeImageGrab:
        @staticmethod
        def grab(window: int) -> FakeImage:
            captured["handle"] = window
            return FakeImage()

    monkeypatch.setitem(sys.modules, "PIL", type("PIL", (), {}))
    monkeypatch.setitem(
        sys.modules,
        "PIL.ImageGrab",
        type("ImageGrab", (), {"grab": FakeImageGrab.grab}),
    )

    # Act
    validate_tm7_with_tmt.capture_window_screenshot(window, tmp_path / "shot.png")

    # Assert
    assert window.restore_calls == 0
    assert window.maximize_calls >= 1
    assert window.maximized is True


def test_given_structureless_surface_when_refining_then_gate_defers() -> None:
    # Arrange
    surface_metrics = [
        {
            "surface_id": "other",
            "surface_geometry": {
                "surface_id": "other",
                "node_rects": {"other-node": [0.0, 0.0, 100.0, 100.0]},
            },
        }
    ]

    # Act
    decision = validate_tm7_with_tmt._evaluate_surface_refinement(
        surface_metrics=surface_metrics,
        failing_candidates=[{"surface_id": "other"}],
        semantic_surfaces={},
    )

    # Assert
    assert decision is None


def test_given_no_improving_alternative_when_refining_then_launch_is_refused() -> None:
    # Arrange
    surface_metrics = [
        {
            "surface_id": "context",
            "surface_geometry": {
                "surface_id": "context",
                "orientation": "horizontal",
                "node_rects": {"node-a": [0.0, 0.0, 100.0, 100.0]},
                "zone_content_rects": {"zone-a": [0.0, 0.0, 400.0, 400.0]},
                "node_ranks": {"node-a": 0},
                "branch_groups": {"node-a": 0},
                "viewport_target": [0.0, 0.0, 1920.0, 1080.0],
            },
        }
    ]

    # Act
    decision = validate_tm7_with_tmt._evaluate_surface_refinement(
        surface_metrics=surface_metrics,
        failing_candidates=[{"surface_id": "context"}],
        semantic_surfaces={},
    )

    # Assert
    assert decision is not None
    assert decision["requires_native_launch"] is False
    assert decision["stop_reason"] == "repeated-defect-no-improvement"


def test_given_improvable_surface_when_refining_then_launch_is_allowed() -> None:
    # Arrange
    surface_metrics = [
        {
            "surface_id": "context",
            "surface_geometry": {
                "surface_id": "context",
                "orientation": "vertical",
                "node_rects": {"node-a": [0.0, 0.0, 100.0, 100.0]},
                "zone_content_rects": {
                    "zone-a": [0.0, 0.0, 400.0, 400.0],
                    "zone-b": [410.0, 0.0, 800.0, 400.0],
                },
                "node_ranks": {"node-a": 0},
                "branch_groups": {"node-a": 0},
                "viewport_target": [0.0, 0.0, 1920.0, 1080.0],
            },
        }
    ]

    # Act
    decision = validate_tm7_with_tmt._evaluate_surface_refinement(
        surface_metrics=surface_metrics,
        failing_candidates=[{"surface_id": "context"}],
        semantic_surfaces={},
    )

    # Assert
    assert decision is not None
    assert decision["requires_native_launch"] is True
    assert decision["selected"]["orientation"] == "horizontal"


def test_given_refinement_search_when_building_then_count_is_bounded() -> None:
    # Arrange
    incumbent = {
        "candidate_id": "context:incumbent",
        "node_ids": [f"node-{index}" for index in range(12)],
        "flow_ids": [f"f-{index}" for index in range(12)],
        "zone_ids": [f"zone-{index}" for index in range(10)],
        "orientation": "horizontal",
        "zone_order": [f"zone-{index}" for index in range(10)],
        "node_ranks": {f"node-{index}": index for index in range(12)},
        "branch_groups": {f"node-{index}": index % 3 for index in range(12)},
    }

    # Act
    candidates = validate_tm7_with_tmt._build_surface_refinement_candidates(
        surface_id="context",
        incumbent=incumbent,
        semantic_surface={},
    )

    # Assert
    assert (
        len(candidates)
        <= validate_tm7_with_tmt.tm7_visual_feedback.MAX_SURFACE_REFINEMENT_CANDIDATES
    )
    assert (
        len(candidates)
        >= validate_tm7_with_tmt.tm7_visual_feedback.MIN_SURFACE_REFINEMENT_CANDIDATES
    )
    incumbent_fingerprint = (
        validate_tm7_with_tmt.tm7_visual_feedback.surface_semantic_fingerprint(
            incumbent
        )
    )
    assert all(
        validate_tm7_with_tmt.tm7_visual_feedback.surface_semantic_fingerprint(
            candidate
        )
        == incumbent_fingerprint
        for candidate in candidates
    )


def test_given_same_surface_rules_when_merged_then_both_are_preserved() -> None:
    # Arrange
    first = {
        "surface_id": "func-oauth",
        "rule": {"node_id": "ext-dev", "constraint": "position", "left": 80},
    }
    second = {
        "surface_id": "func-oauth",
        "rule": {
            "node_id": "ext-mural-api",
            "constraint": "position",
            "left": 500,
        },
    }

    # Act
    rules, surface_id = validate_tm7_with_tmt._merge_accumulated_rule([], None, first)
    rules, surface_id = validate_tm7_with_tmt._merge_accumulated_rule(
        rules, surface_id, second
    )

    # Assert
    assert surface_id == "func-oauth"
    assert [rule["node_id"] for rule in rules] == ["ext-dev", "ext-mural-api"]


def test_given_new_surface_rule_when_merged_then_prior_surface_is_preserved() -> None:
    # Arrange
    rules = [{"node_id": "ext-dev", "constraint": "position", "left": 80}]
    candidate = {
        "surface_id": "dom-docproc",
        "rule": {
            "node_id": "comp-logsink",
            "constraint": "position",
            "left": 500,
        },
    }

    # Act
    merged, surface_id = validate_tm7_with_tmt._merge_accumulated_rule(
        rules,
        "func-oauth",
        candidate,
    )

    # Assert
    assert surface_id == "dom-docproc"
    assert len(merged) == 2
    assert {rule["_surface_id"] for rule in merged} == {
        "func-oauth",
        "dom-docproc",
    }


def test_given_feedback_loop_when_missing_overlay_output_then_fails_before_discovery(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)

    def explode() -> None:
        raise AssertionError("discovery should not run")

    monkeypatch.setattr(validate_tm7_with_tmt, "discover_tmt_application", explode)

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=None,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_ERROR
    assert "overlay-output" in result.message.lower()


def test_given_feedback_loop_when_candidate_is_clean_then_writes_pending_overlay(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    evidence_dir = tmp_path / "evidence"
    overlay_output = tmp_path / "overlay-output.yaml"
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")

    def fake_generate_candidate(
        *,
        spec_path: Path,
        output_path: Path,
        **_: Any,
    ) -> Path:
        output_path.write_text("candidate", encoding="utf-8")
        return output_path

    def fake_validate_candidate(*args: Any, **kwargs: Any) -> dict[str, Any]:
        return {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [{"id": "1", "type_id": "TH-test"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 0,
                    "review_count": 0,
                    "warn_count": 0,
                    "max_severity_score": 0.0,
                    "constraint_type": "relative_to",
                }
            ],
            "evidence_complete": True,
            "semantic_regression": False,
            "semantic_summary": {"instance_count": 1},
            "candidate_path": str(baseline_model),
        }

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt.generate_tm7,
        "generate_tm7_candidate",
        fake_generate_candidate,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        fake_validate_candidate,
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=evidence_dir,
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_SUCCESS
    assert result.status == "automated-ready-pending-human"
    assert overlay_output.exists()
    payload = json.loads(overlay_output.read_text(encoding="utf-8"))
    assert payload["provenance"]["approval_state"] == "pending"
    feedback_manifest = json.loads(
        (evidence_dir / "feedback-manifest.json").read_text(encoding="utf-8")
    )
    assert len(feedback_manifest["candidate_sha256"]) == 64
    assert feedback_manifest["surfaces"]
    assert all(
        surface["human_review_status"] == "pending"
        and surface["human_review_required"] is True
        for surface in feedback_manifest["surfaces"]
    )


def test_given_feedback_loop_when_tmt_is_unavailable_then_reports_feedback_status(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")

    def explode() -> None:
        raise AssertionError("discovery should not be skipped")

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=None, version=None, source="test"
        ),
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=1,
        require_feedback_evidence=True,
    )

    # Assert
    assert result.status == "tmt-unavailable"
    assert result.exit_code == validate_tm7_with_tmt.EXIT_MISSING_TMT


def test_given_feedback_loop_when_strict_evidence_is_missing_then_stops(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        lambda *args, **kwargs: {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 1,
                "instances": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [],
            "evidence_complete": False,
            "semantic_regression": False,
            "semantic_summary": {},
            "candidate_path": str(baseline_model),
        },
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=1,
        require_feedback_evidence=True,
    )

    # Assert
    assert result.status == "evidence-incomplete"
    assert result.exit_code == validate_tm7_with_tmt.EXIT_MISSING_FEEDBACK_EVIDENCE


def test_given_feedback_loop_when_semantic_regression_is_detected_then_skips(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)
    baseline_model = tmp_path / "baseline.tm7"
    baseline_model.write_text("baseline", encoding="utf-8")
    overlay_output = tmp_path / "overlay.yaml"

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(
            path=tmp_path / "ThreatModeling.exe",
            version="7.3.51110.1",
            source="test",
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_validate_feedback_candidate",
        lambda *args, **kwargs: {
            "working_model": str(baseline_model),
            "saved_model": str(baseline_model),
            "before_summary": {
                "instance_count": 2,
                "instances": [{"id": "1"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "after_summary": {
                "instance_count": 1,
                "instances": [{"id": "2"}],
                "drawing_surface_hash": "surface",
                "knowledge_base_hash": "kb",
            },
            "surface_metrics": [
                {
                    "surface_id": "context",
                    "node_id": "trust-zone-portal",
                    "gate_failure_count": 0,
                    "review_count": 0,
                    "warn_count": 0,
                    "max_severity_score": 0.0,
                    "constraint_type": "relative_to",
                }
            ],
            "evidence_complete": True,
            "semantic_regression": True,
            "semantic_summary": {},
            "candidate_path": str(baseline_model),
        },
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "sha")

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=baseline_model,
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=overlay_output,
        max_iterations=1,
        require_feedback_evidence=False,
    )

    # Assert
    assert result.status == "semantic-regression"
    assert result.exit_code == validate_tm7_with_tmt.EXIT_VALIDATION_FAILURE
    assert not overlay_output.exists()


def test_given_feedback_loop_when_max_iterations_are_out_of_range_then_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    spec_path = tmp_path / "spec.yaml"
    _write_feedback_spec(spec_path)

    def explode() -> None:
        raise AssertionError("discovery should not run")

    monkeypatch.setattr(validate_tm7_with_tmt, "discover_tmt_application", explode)

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        feedback_loop=True,
        spec_path=spec_path,
        overlay_output=tmp_path / "overlay.yaml",
        max_iterations=4,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_ERROR
    assert "max-iterations" in result.message.lower()


def test_given_exact_version_when_checking_policy_then_allows() -> None:
    # Arrange
    policy = validate_tm7_with_tmt.TmtVersionPolicy(
        pinned_version="7.3.51110.1",
        observed_version="7.3.51110.1",
    )

    # Act
    outcome = validate_tm7_with_tmt.evaluate_version_policy(policy)

    # Assert
    assert outcome.allowed is True
    assert outcome.exit_code == validate_tm7_with_tmt.EXIT_SUCCESS


def test_given_surface_model_when_reading_then_returns_descriptors(
    tmp_path: Path,
) -> None:
    # Arrange
    model_path = tmp_path / "surfaces.tm7"
    model_path.write_text(
        """<ThreatModel xmlns=\"http://schemas.datacontract.org/2004/07/ThreatModeling.Model\">
  <DrawingSurfaceList>
    <DrawingSurfaceModel>
      <Header>Primary interaction</Header>
      <Guid>guid-1</Guid>
    </DrawingSurfaceModel>
    <DrawingSurfaceModel>
      <Header>Deployment and operations</Header>
      <Guid>guid-2</Guid>
    </DrawingSurfaceModel>
  </DrawingSurfaceList>
</ThreatModel>""",
        encoding="utf-8",
    )

    # Act
    surfaces = validate_tm7_with_tmt.read_expected_surfaces(model_path)

    # Assert
    assert [surface.surface_name for surface in surfaces] == [
        "Primary interaction",
        "Deployment and operations",
    ]
    assert [surface.surface_guid for surface in surfaces] == ["guid-1", "guid-2"]
    assert [surface.tab_index for surface in surfaces] == [0, 1]


def test_given_matching_tabs_when_selecting_surface_then_returns_tab() -> None:
    # Arrange
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="primary",
        surface_guid="guid-1",
        surface_name="Primary interaction",
        tab_index=0,
    )
    tab = FakeControl("TabItem", "Primary interaction")

    # Act
    selected = validate_tm7_with_tmt.select_surface_tab(
        FakeWindow("Window", 100, 100),
        surface,
        [tab],
    )

    # Assert
    assert selected is tab


def test_given_ambiguous_tab_names_when_selecting_surface_then_fails() -> None:
    # Arrange
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="primary",
        surface_guid="guid-1",
        surface_name="Primary interaction",
        tab_index=0,
    )
    tabs = [
        FakeControl("TabItem", "Primary interaction"),
        FakeControl("TabItem", "Primary interaction"),
    ]

    # Act
    selected = validate_tm7_with_tmt.select_surface_tab(
        FakeWindow("Window", 100, 100),
        surface,
        tabs,
    )

    # Assert
    assert selected is tabs[0]


def test_generic_diagram_tabs_are_selected_by_surface_order() -> None:
    tabs = [
        validate_tm7_with_tmt.SurfaceTab(
            control=FakeControl("TabItem", "Diagram"),
            name="Diagram",
            tab_index=index,
        )
        for index in range(3)
    ]
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="third",
        surface_guid="guid-3",
        surface_name="Third semantic surface",
        tab_index=2,
    )

    selected = validate_tm7_with_tmt.select_surface_tab(
        FakeWindow("Window", 100, 100),
        surface,
        tabs,
    )

    assert selected is tabs[2].control


def test_tmt_document_tabs_exclude_messages_and_notes() -> None:
    document_tabs = [
        FakeControl("TabItem", "DocumentView, Title Diagram") for _ in range(8)
    ]
    other_tabs = [
        FakeControl(
            "TabItem", "View, Title Messages - Disabled", automation_id="TAB_Messages"
        ),
        FakeControl(
            "TabItem", "View, Title Notes - no entries", automation_id="TAB_Notes"
        ),
    ]
    window = FakeWindow(
        "TMT",
        1000,
        800,
        descendants=[*document_tabs, *other_tabs],
    )

    tabs = validate_tm7_with_tmt.enumerate_surface_tabs(window)

    assert len(tabs) == 8
    assert [tab.tab_index for tab in tabs] == list(range(8))


def test_window_origin_rectangle_crop_returns_window_relative_bounds() -> None:
    # Arrange
    class NumericRectangle:
        left = 180
        top = 140
        right = 420
        bottom = 320

    class NumericWindowRectangle:
        left = 100
        top = 80
        right = 600
        bottom = 400

    class NumericWindow:
        def rectangle(self) -> NumericWindowRectangle:
            return NumericWindowRectangle()

    class NumericControl:
        def rectangle(self) -> NumericRectangle:
            return NumericRectangle()

    # Act
    crop = validate_tm7_with_tmt._control_rectangle(NumericControl(), NumericWindow())

    # Assert
    assert crop == {
        "left": 80,
        "top": 60,
        "right": 320,
        "bottom": 240,
        "width": 240,
        "height": 180,
    }


def test_given_diagram_pane_when_reading_announcement_then_returns_text() -> None:
    # Arrange
    pane = FakeControl(
        "Pane",
        "Diagram",
        automation_id="83b774ee-20a7-5ce1-ac3e-36286067963b",
    )

    # Act
    announcement = validate_tm7_with_tmt.read_canvas_announcement(pane)

    # Assert
    assert announcement == "Diagram"


def test_given_strict_surface_capture_when_pane_missing_then_fails(
    tmp_path: Path,
) -> None:
    # Arrange
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="primary",
        surface_guid="guid-1",
        surface_name="Primary interaction",
        tab_index=0,
    )
    window = FakeWindow("Window", 1000, 800)

    # Act / Assert
    with pytest.raises(validate_tm7_with_tmt.HarnessFailure):
        validate_tm7_with_tmt.capture_surface_evidence(
            window,
            bundle,
            surface,
            model_path=tmp_path / "model.tm7",
            require_feedback_evidence=True,
        )


def test_scrollable_surface_captures_deduplicated_corners_and_restores(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class ScrollInterface:
        CurrentHorizontalScrollPercent = 25.0
        CurrentVerticalScrollPercent = 40.0

        def __init__(self) -> None:
            self.positions: list[tuple[float, float]] = []

        def SetScrollPercent(self, horizontal: float, vertical: float) -> None:
            self.positions.append((horizontal, vertical))

    scroll = ScrollInterface()
    pane = FakeControl("Pane", "Diagram")
    pane.iface_scroll = scroll
    window = FakeWindow("TMT", 1000, 800)
    monkeypatch.setattr(validate_tm7_with_tmt, "find_diagram_pane", lambda _: pane)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda _window, path: path.write_bytes(b"png"),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "build_uia_tree",
        lambda _: "diagram",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "read_canvas_announcement",
        lambda _: "Diagram",
    )
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="context",
        surface_guid="surface-guid",
        surface_name="Context",
        tab_index=0,
    )

    payload = validate_tm7_with_tmt.capture_surface_evidence(
        window,
        bundle,
        surface,
        scroll_extent_ratio_x=1.5,
        scroll_extent_ratio_y=1.5,
    )

    assert len(payload["scroll_tiles"]) == 4
    assert scroll.positions[:4] == [
        (0.0, 0.0),
        (100.0, 0.0),
        (0.0, 100.0),
        (100.0, 100.0),
    ]
    assert scroll.positions[-1] == (25.0, 40.0)


def test_strict_scrollable_surface_without_scroll_pattern_fails(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    pane = FakeControl("Pane", "Diagram")
    monkeypatch.setattr(validate_tm7_with_tmt, "find_diagram_pane", lambda _: pane)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda _window, path: path.write_bytes(b"png"),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_control_rectangle",
        lambda *args, **kwargs: {
            "left": 0,
            "top": 0,
            "right": 100,
            "bottom": 100,
            "width": 100,
            "height": 100,
        },
    )

    class FakeImage:
        size = (100, 100)

        def crop(self, bounds):
            return self

        def save(self, path):
            path.write_bytes(b"png")

    class FakeImageModule:
        @staticmethod
        def open(path):
            return FakeImage()

    class FakePillow:
        Image = FakeImageModule

    monkeypatch.setitem(sys.modules, "PIL", FakePillow)
    monkeypatch.setitem(sys.modules, "PIL.Image", FakeImageModule)
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    surface = validate_tm7_with_tmt.SurfaceDescriptor(
        surface_id="context",
        surface_guid="surface-guid",
        surface_name="Context",
        tab_index=0,
    )

    with pytest.raises(
        validate_tm7_with_tmt.HarnessFailure,
        match="scroll coverage",
    ):
        validate_tm7_with_tmt.capture_surface_evidence(
            FakeWindow("TMT", 1000, 800),
            bundle,
            surface,
            require_feedback_evidence=True,
            scroll_extent_ratio_x=1.5,
        )


def test_given_startup_pane_and_main_window_when_finding_then_selects_main(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    startup = FakeWindow("Please wait while the application opens", 500, 300)
    main = FakeWindow("Microsoft Threat Modeling Tool", 1400, 900)
    process = FakeProcess()
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_visible_process_windows",
        lambda process_id: [startup, main],
    )

    # Act
    selected = validate_tm7_with_tmt.find_tmt_window(process, 1)

    # Assert
    assert selected is main


def test_given_nested_dialogs_when_detecting_modal_then_reports_all(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    license_window = FakeWindow(
        "MICROSOFT LICENSE TERMS WINDOW",
        1000,
        800,
        handle=2,
    )
    exception_window = FakeWindow("Unhandled exception", 600, 400, handle=3)
    main = FakeWindow(
        "Microsoft Threat Modeling Tool",
        1400,
        900,
        descendants=[license_window, exception_window],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_visible_process_windows",
        lambda process_id: [main],
    )

    # Act
    modal = validate_tm7_with_tmt.detect_modal_dialog(main)

    # Assert
    assert modal == "MICROSOFT LICENSE TERMS WINDOW; Unhandled exception"


def test_given_hidden_nested_dialog_when_detecting_modal_then_ignores_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    hidden = FakeWindow("Hidden conversion", 600, 400, handle=2)
    hidden.is_visible = lambda: False
    main = FakeWindow(
        "Microsoft Threat Modeling Tool",
        1400,
        900,
        descendants=[hidden],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_visible_process_windows",
        lambda process_id: [main],
    )

    # Act
    modal = validate_tm7_with_tmt.detect_modal_dialog(main)

    # Assert
    assert modal is None


def test_given_window_handle_when_capturing_then_uses_exact_hwnd(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    window = FakeWindow("TMT modal", 600, 400, handle=73)
    output = tmp_path / "window.png"
    captured: dict[str, Any] = {}

    class FakeImage:
        def save(self, path: Path) -> None:
            captured["path"] = path
            path.write_bytes(b"png")

    class FakeImageGrab:
        @staticmethod
        def grab(*, window: int):
            captured["handle"] = window
            return FakeImage()

    class FakePillow:
        ImageGrab = FakeImageGrab

    monkeypatch.setitem(sys.modules, "PIL", FakePillow)
    monkeypatch.setitem(sys.modules, "PIL.ImageGrab", FakeImageGrab)

    # Act
    validate_tm7_with_tmt.capture_window_screenshot(window, output)

    # Assert
    assert captured == {"handle": 73, "path": output}
    assert output.read_bytes() == b"png"


def test_given_transient_capture_error_when_retrying_then_uses_exact_hwnd(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    window = FakeWindow("TMT modal", 600, 400, handle=73)
    output = tmp_path / "window.png"
    state = {"attempts": 0}

    class FakeImage:
        def save(self, path: Path) -> None:
            path.write_bytes(b"png")

    class FakeImageGrab:
        @staticmethod
        def grab(*, window: int):
            state["attempts"] += 1
            if state["attempts"] == 1:
                raise OSError("transient")
            assert window == 73
            return FakeImage()

    class FakePillow:
        ImageGrab = FakeImageGrab

    monkeypatch.setitem(sys.modules, "PIL", FakePillow)
    monkeypatch.setitem(sys.modules, "PIL.ImageGrab", FakeImageGrab)

    # Act
    validate_tm7_with_tmt.capture_window_screenshot(window, output)

    # Assert
    assert state["attempts"] == 2
    assert output.read_bytes() == b"png"


def test_given_stale_restore_when_capturing_then_uses_exact_hwnd(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    window = FakeWindow("TMT", 600, 400, handle=73)
    window.restore = lambda: (_ for _ in ()).throw(RuntimeError("stale"))
    window.set_focus = lambda: (_ for _ in ()).throw(RuntimeError("stale"))
    output = tmp_path / "window.png"

    class FakeImage:
        def save(self, path: Path) -> None:
            path.write_bytes(b"png")

    class FakeImageGrab:
        @staticmethod
        def grab(*, window: int) -> FakeImage:
            assert window == 73
            return FakeImage()

    class FakePillow:
        ImageGrab = FakeImageGrab

    monkeypatch.setitem(sys.modules, "PIL", FakePillow)
    monkeypatch.setitem(sys.modules, "PIL.ImageGrab", FakeImageGrab)

    # Act
    validate_tm7_with_tmt.capture_window_screenshot(window, output)

    # Assert
    assert output.read_bytes() == b"png"


def test_given_tmt_launch_when_started_then_uses_installation_directory(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    executable = tmp_path / "install" / "ThreatModeling.exe"
    executable.parent.mkdir()
    executable.write_bytes(b"exe")
    model = tmp_path / "model.tm7"
    model.write_text("model", encoding="utf-8")
    captured: dict[str, Any] = {}

    def popen(command, **kwargs):
        captured["command"] = command
        captured.update(kwargs)
        return FakeProcess()

    monkeypatch.setattr(validate_tm7_with_tmt.subprocess, "Popen", popen)

    # Act
    validate_tm7_with_tmt.launch_tmt_process(executable, model)

    # Assert
    assert captured["command"] == [str(executable), str(model)]
    assert captured["cwd"] == executable.parent


def test_given_save_button_when_saving_current_model_then_clicks_visible_control(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    model = _input_model(tmp_path)
    state = {"clicked": False, "hash_calls": 0}

    class SaveControl:
        def click_input(self) -> None:
            state["clicked"] = True

    class SaveWindow:
        def window_text(self) -> str:
            return "Saved model"

    def file_hash(path: Path) -> str:
        state["hash_calls"] += 1
        return "before" if state["hash_calls"] == 1 else "after"

    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", file_hash)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_load_pywinauto",
        lambda: (object(), lambda keys: None, TimeoutError),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_find_control",
        lambda window, pattern, control_types: SaveControl(),
    )

    # Act
    validate_tm7_with_tmt.save_current_model(SaveWindow(), model, 1)

    # Assert
    assert state["clicked"] is True


def test_given_clean_model_when_save_is_noop_then_accepts_clean_state(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    model = _input_model(tmp_path)

    class SaveControl:
        def click_input(self) -> None:
            pass

    class SaveWindow:
        def window_text(self) -> str:
            return "Saved model"

    monkeypatch.setattr(validate_tm7_with_tmt, "sha256_file", lambda path: "same")
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_load_pywinauto",
        lambda: (object(), lambda keys: None, TimeoutError),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_find_control",
        lambda window, pattern, control_types: SaveControl(),
    )

    # Act and assert
    validate_tm7_with_tmt.save_current_model(SaveWindow(), model, 0.01)


def test_given_native_file_dialog_when_saving_then_uses_file_name_edit(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    destination = tmp_path / "threats.csv"
    state: dict[str, Any] = {}

    class Edit:
        def __init__(self, identifier: str) -> None:
            self.identifier = identifier

        def class_name(self) -> str:
            return "Edit"

        def set_focus(self) -> None:
            state["focused"] = self.identifier

        def set_edit_text(self, value: str) -> None:
            state[self.identifier] = value

    class Button:
        def class_name(self) -> str:
            return "Button"

        def window_text(self) -> str:
            return "Save"

        def click_input(self) -> None:
            state["clicked"] = True
            destination.write_text("export", encoding="utf-8")

    class Dialog:
        def process_id(self) -> int:
            return 42

        def descendants(self) -> list[Any]:
            return [Edit("search"), Edit("filename"), Button()]

    class Desktop:
        def __init__(self, backend: str) -> None:
            assert backend == "win32"

        def windows(
            self,
            class_name: str,
            visible_only: bool,
        ) -> list[Dialog]:
            assert class_name == "#32770"
            assert visible_only is True
            return [Dialog()]

    class TimeoutError(Exception):
        pass

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_load_pywinauto",
        lambda: (Desktop, object(), TimeoutError),
    )

    # Act
    validate_tm7_with_tmt._save_dialog_path(42, destination, 1)

    # Assert
    assert state["filename"] == str(destination)
    assert "search" not in state
    assert state["focused"] == "filename"
    assert state["clicked"] is True


def test_given_dashboard_and_model_when_waiting_then_selects_analysis_window(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    analysis = FakeWindow(
        "Switch To Analysis View",
        100,
        30,
        element_info=type(
            "ElementInfo",
            (),
            {"control_type": "Button", "name": "Switch To Analysis View"},
        )(),
    )
    dashboard = FakeWindow("Dashboard", 1400, 900)
    model = FakeWindow(
        "Threat Model",
        1400,
        900,
        descendants=[
            analysis,
            FakeControl("Pane", "Threat List"),
            FakeControl("DataGrid", "MainList"),
            FakeControl("Button", "Export Csv"),
        ],
    )
    process = FakeProcess()
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_visible_process_windows",
        lambda process_id: [dashboard, model],
    )

    # Act
    selected = validate_tm7_with_tmt.wait_for_analysis_window(process, 1)

    # Assert
    assert selected is model


def test_given_switch_click_without_analysis_state_when_opening_then_times_out() -> (
    None
):
    # Arrange
    window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )

    # Act and assert
    with pytest.raises(
        validate_tm7_with_tmt.HarnessFailure,
        match="Analysis View was not confirmed",
    ):
        validate_tm7_with_tmt.open_analysis_view(window, timeout_seconds=0.01)


def test_given_analysis_ready_state_when_exporting_then_export_runs_after_readiness(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    window = FakeWindow("Threat Model", 800, 600)
    state: dict[str, Any] = {}

    def open_analysis(
        window: Any,
        *,
        timeout_seconds: float = 1.0,
        modal_handler: Any | None = None,
    ) -> None:
        setattr(window, "analysis_ready", True)

    def export(window: Any, destination: Path, timeout: float) -> None:
        state["exported"] = validate_tm7_with_tmt._analysis_view_ready(window)
        destination.write_text("id,title\n1,Threat\n", encoding="utf-8")

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_tmt_window",
        lambda *args, **kwargs: window,
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "open_analysis_view", open_analysis)
    monkeypatch.setattr(validate_tm7_with_tmt, "export_threat_csv", export)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_analysis_view_ready",
        lambda current: bool(getattr(current, "analysis_ready", False)),
    )

    # Act
    validate_tm7_with_tmt._validate_candidate(
        executable=tmp_path / "ThreatModeling.exe",
        input_model=_input_model(tmp_path),
        workspace=workspace,
        bundle=validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence"),
        mode="validate",
        timeout_seconds=1.0,
        expected_threat_count=1,
        template_upgrade_policy="fail",
        delete_stale_threats=False,
    )

    # Assert
    assert state["exported"] is True


def test_given_exact_export_csv_button_when_exporting_then_finds_export_control(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    destination = tmp_path / "threats.csv"
    window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[
            FakeControl("Pane", "Threat List"),
            FakeControl("DataGrid", "MainList"),
            FakeControl("Button", "Export Csv"),
        ],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_analysis_view_ready",
        lambda current: True,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_save_dialog_path",
        lambda process_id, output_path, timeout: output_path.write_text(
            "id,title\n1,Threat\n",
            encoding="utf-8",
        ),
    )

    # Act
    validate_tm7_with_tmt.export_threat_csv(window, destination, 1.0)

    # Assert
    assert destination.exists()
    assert destination.read_text(encoding="utf-8") == "id,title\n1,Threat\n"


def test_given_deleted_interaction_export_when_validated_then_fails(
    tmp_path: Path,
) -> None:
    # Arrange
    export_path = tmp_path / "threats.csv"
    export_path.write_text(
        "Id,Title,Interaction\n1,Threat,Deleted\n",
        encoding="utf-8",
    )

    # Act and assert
    with pytest.raises(
        validate_tm7_with_tmt.HarnessFailure,
        match="Deleted interactions",
    ):
        validate_tm7_with_tmt.validate_exported_interactions(export_path)


def test_given_design_view_when_checked_then_not_ready() -> None:
    # Arrange
    window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )

    # Act
    ready = validate_tm7_with_tmt._analysis_view_ready(window)

    # Assert
    assert ready is False


def test_given_template_conversion_dialog_when_opening_analysis_then_modal_is_cleared(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )
    state: dict[str, Any] = {"modal_calls": 0}

    def modal_handler() -> None:
        state["modal_calls"] += 1
        setattr(window, "analysis_ready", True)

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_analysis_view_ready",
        lambda current: bool(getattr(current, "analysis_ready", False)),
    )

    # Act
    validate_tm7_with_tmt.open_analysis_view(
        window,
        timeout_seconds=0.01,
        modal_handler=modal_handler,
    )

    # Assert
    assert state["modal_calls"] >= 1


def test_given_stale_analysis_window_when_reacquired_then_uses_active_window(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    stale_window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )
    active_window = FakeWindow(
        "Threat Model",
        1000,
        700,
        descendants=[
            FakeControl("Pane", "Threat List"),
            FakeControl("DataGrid", "MainList"),
            FakeControl("Button", "Export Csv"),
        ],
    )
    click_count = 0

    def clicker() -> None:
        nonlocal click_count
        click_count += 1

    stale_window.descendants()[0].click_input = clicker  # type: ignore[assignment]

    def reacquire() -> FakeWindow:
        return active_window

    monkeypatch.setattr(validate_tm7_with_tmt.time, "sleep", lambda _: None)

    # Act
    returned_window = validate_tm7_with_tmt.open_analysis_view(
        stale_window,
        timeout_seconds=0.05,
        reacquire_window=reacquire,
    )

    # Assert
    assert returned_window is active_window
    assert click_count == 1


def test_given_delayed_analysis_transition_when_opening_then_waits_for_ready_window(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    initial_window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )
    ready_window = FakeWindow(
        "Threat Model",
        1000,
        700,
        descendants=[
            FakeControl("Pane", "Threat List"),
            FakeControl("DataGrid", "Threats List"),
            FakeControl("Button", "Export Csv"),
        ],
    )
    attempts = iter([initial_window, initial_window, ready_window])

    def reacquire() -> FakeWindow:
        return next(attempts)

    monkeypatch.setattr(validate_tm7_with_tmt.time, "sleep", lambda _: None)

    # Act
    returned_window = validate_tm7_with_tmt.open_analysis_view(
        initial_window,
        timeout_seconds=0.05,
        reacquire_window=reacquire,
    )

    # Assert
    assert returned_window is ready_window


def test_given_delayed_conversion_modal_when_opening_analysis_then_reacquires(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    initial_window = FakeWindow(
        "Threat Model",
        800,
        600,
        descendants=[FakeControl("Button", "Switch To Analysis View")],
    )
    ready_window = FakeWindow(
        "Threat Model",
        1000,
        700,
        descendants=[
            FakeControl("Pane", "Threat List"),
            FakeControl("DataGrid", "MainList"),
            FakeControl("Button", "Export Csv"),
        ],
    )
    modal_calls = 0

    def modal_handler(window: Any) -> None:
        nonlocal modal_calls
        modal_calls += 1
        if modal_calls == 1:
            setattr(window, "analysis_ready", True)

    def reacquire() -> FakeWindow:
        return ready_window

    monkeypatch.setattr(validate_tm7_with_tmt.time, "sleep", lambda _: None)

    # Act
    returned_window = validate_tm7_with_tmt.open_analysis_view(
        initial_window,
        timeout_seconds=0.05,
        modal_handler=modal_handler,
        reacquire_window=reacquire,
    )

    # Assert
    assert returned_window is ready_window
    assert modal_calls >= 1


def test_given_unknown_modal_when_captured_then_fail_closed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    window = FakeWindow("Threat Model", 800, 600)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "detect_modal_dialog",
        lambda current: "Unexpected warning",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda current: [FakeWindow("Unexpected warning", 400, 300)],
    )
    monkeypatch.setattr(validate_tm7_with_tmt, "build_uia_tree", lambda current: "")
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda current, path: path.write_bytes(b"png"),
    )

    # Act and assert
    with pytest.raises(
        validate_tm7_with_tmt.HarnessFailure,
        match="Unexpected modal",
    ):
        validate_tm7_with_tmt._capture_modal(
            window,
            bundle,
            template_upgrade_policy="decline",
            timeout_seconds=1.0,
        )


def test_given_wrong_version_without_override_when_checked_then_rejected() -> None:
    # Arrange
    policy = validate_tm7_with_tmt.TmtVersionPolicy(
        pinned_version="7.3.51110.1",
        observed_version="7.4.0.0",
    )

    # Act
    outcome = validate_tm7_with_tmt.evaluate_version_policy(policy)

    # Assert
    assert outcome.allowed is False
    assert outcome.exit_code == validate_tm7_with_tmt.EXIT_VERSION_MISMATCH


@pytest.mark.parametrize(
    ("require_tmt", "expected_status", "expected_exit"),
    [
        (False, "skipped", validate_tm7_with_tmt.EXIT_SUCCESS),
        (True, "missing-tmt", validate_tm7_with_tmt.EXIT_MISSING_TMT),
    ],
)
def test_given_missing_tmt_when_running_then_policy_is_stable(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    require_tmt: bool,
    expected_status: str,
    expected_exit: int,
) -> None:
    # Arrange
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "discover_tmt_application",
        lambda: validate_tm7_with_tmt.TmtDiscovery(path=None),
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        mode="probe",
        require_tmt=require_tmt,
    )

    # Assert
    assert result.status == expected_status
    assert result.exit_code == expected_exit


def test_given_timeout_when_window_never_appears_then_failure_bundle_is_retained(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    processes = _patch_successful_automation(monkeypatch, tmp_path)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "find_tmt_window",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            validate_tm7_with_tmt.HarnessFailure(
                "window timeout",
                validate_tm7_with_tmt.EXIT_AUTOMATION_TIMEOUT,
            )
        ),
    )
    workspace = tmp_path / "workspace"

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        workspace_root=workspace,
        require_tmt=True,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_AUTOMATION_TIMEOUT
    assert workspace.exists()
    assert processes and all(process.closed for process in processes)
    assert (tmp_path / "evidence" / "status.json").exists()


def test_given_modal_when_detected_then_uia_and_screenshot_are_retained(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "detect_modal_dialog",
        lambda window: "Unexpected warning",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda window: [],
    )
    evidence = tmp_path / "evidence"

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=evidence,
        require_tmt=True,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_UNEXPECTED_MODAL
    assert (evidence / "uia" / "unexpected-modal.txt").exists()
    assert (evidence / "screenshots" / "unexpected-modal.png").exists()


def test_given_license_modal_when_detected_then_reports_human_gate(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "detect_modal_dialog",
        lambda window: validate_tm7_with_tmt.LICENSE_MODAL_TITLE,
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda window: [],
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        require_tmt=True,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_UNEXPECTED_MODAL
    assert "Human acceptance" in result.message


@pytest.mark.parametrize(
    ("policy", "button_name", "expected"),
    [("apply", "Yes", "applied"), ("decline", "No", "declined")],
)
def test_given_template_prompt_when_policy_selected_then_modal_is_handled(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    policy: str,
    button_name: str,
    expected: str,
) -> None:
    # Arrange
    state = {"open": True, "checked": False, "button": ""}

    class ControlInfo:
        def __init__(self, control_type: str, name: str) -> None:
            self.control_type = control_type
            self.name = name
            self.automation_id = ""

    class FakeControl:
        def __init__(self, control_type: str, name: str) -> None:
            self.element_info = ControlInfo(control_type, name)

        def get_toggle_state(self) -> int:
            return int(state["checked"])

        def click_input(self) -> None:
            if self.element_info.control_type == "CheckBox":
                state["checked"] = not state["checked"]
            else:
                state["button"] = self.element_info.name
                state["open"] = False

    checkbox = FakeControl("CheckBox", "Do you want to delete stale threats?")
    yes = FakeControl("Button", "Yes")
    no = FakeControl("Button", "No")
    conversion = FakeWindow(
        validate_tm7_with_tmt.TEMPLATE_CONVERSION_MODAL_TITLE,
        800,
        500,
        handle=7,
        descendants=[checkbox, yes, no],
    )
    main = FakeWindow("Microsoft Threat Modeling Tool", 1400, 900)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda window: [conversion] if state["open"] else [],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "build_uia_tree",
        lambda window: "template conversion\n",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: path.write_bytes(b"png"),
    )
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")

    # Act
    result = validate_tm7_with_tmt._handle_template_conversion(
        main,
        bundle,
        policy=policy,
        delete_stale=False,
        timeout_seconds=1,
    )

    # Assert
    assert result == expected
    assert state["button"] == button_name
    assert state["checked"] is False


def test_given_template_prompt_when_policy_fail_then_requires_explicit_choice(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    conversion = FakeWindow(
        validate_tm7_with_tmt.TEMPLATE_CONVERSION_MODAL_TITLE,
        800,
        500,
        handle=7,
    )
    main = FakeWindow("Microsoft Threat Modeling Tool", 1400, 900)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_modal_windows",
        lambda window: [conversion],
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "build_uia_tree",
        lambda window: "template conversion\n",
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "capture_window_screenshot",
        lambda window, path: path.write_bytes(b"png"),
    )
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")

    # Act and assert
    with pytest.raises(
        validate_tm7_with_tmt.HarnessFailure,
        match="explicit template upgrade policy",
    ):
        validate_tm7_with_tmt._handle_template_conversion(
            main,
            bundle,
            policy="fail",
            delete_stale=False,
            timeout_seconds=1,
        )


def test_given_upgrade_mode_when_successful_then_upgraded_model_is_published(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_capture_modal",
        lambda *args, **kwargs: (
            "applied" if kwargs.get("template_upgrade_policy") == "apply" else None
        ),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "wait_for_analysis_window",
        lambda process, timeout: object(),
    )
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_wait_for_modal_window",
        lambda window, title, timeout: object(),
    )
    output = tmp_path / "upgraded.tm7"

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        mode="upgrade-template",
        upgraded_model_output=output,
        require_tmt=True,
        expected_threat_count=1,
    )

    # Assert
    assert result.status == "passed"
    assert output.read_text(encoding="utf-8") == "model"


def test_given_native_upgrade_when_custom_types_removed_then_restores_from_source(
    tmp_path: Path,
) -> None:
    # Arrange
    source = tmp_path / "source.tm7"
    target = tmp_path / "target.tm7"
    source.write_text(
        f'<ThreatModel xmlns="{validate_tm7_with_tmt.MODEL_NS}" '
        f'xmlns:a="{validate_tm7_with_tmt.KNOWLEDGE_NS}">'
        "<KnowledgeBase><a:ThreatTypes><a:ThreatType>"
        "<a:Id>THC-custom</a:Id><a:ShortTitle>Custom</a:ShortTitle>"
        "</a:ThreatType></a:ThreatTypes></KnowledgeBase></ThreatModel>",
        encoding="utf-8",
    )
    target.write_text(
        f'<ThreatModel xmlns="{validate_tm7_with_tmt.MODEL_NS}" '
        f'xmlns:a="{validate_tm7_with_tmt.KNOWLEDGE_NS}">'
        "<KnowledgeBase><a:ThreatTypes><a:ThreatType>"
        "<a:Id>TH1</a:Id><a:ShortTitle>Stock</a:ShortTitle>"
        "</a:ThreatType></a:ThreatTypes></KnowledgeBase></ThreatModel>",
        encoding="utf-8",
    )

    # Act
    restored = validate_tm7_with_tmt.restore_custom_threat_types(source, target)
    root = validate_tm7_with_tmt._parse_xml(target)
    type_ids = {node.findtext("{*}Id") for node in root.findall(".//{*}ThreatType")}

    # Assert
    assert restored == 1
    assert type_ids == {"TH1", "THC-custom"}


def test_given_probe_mode_when_successful_then_initial_evidence_is_complete(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    processes = _patch_successful_automation(monkeypatch, tmp_path)
    evidence = tmp_path / "evidence"
    workspace = tmp_path / "workspace"

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=evidence,
        mode="probe",
        require_tmt=True,
        workspace_root=workspace,
    )

    # Assert
    assert result.status == "passed"
    assert not workspace.exists()
    assert processes and all(process.closed for process in processes)
    assert (evidence / "screenshots" / "initial-open.png").exists()
    assert (evidence / "uia" / "initial-open.txt").exists()


def test_given_calibration_smoke_when_measured_then_writes_same_run_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    processes = _patch_successful_automation(monkeypatch, tmp_path)
    evidence = tmp_path / "evidence"
    captured: dict[str, Any] = {}

    def capture_surfaces(**kwargs: Any) -> list[dict[str, Any]]:
        captured.update(kwargs)
        return [
            {
                "surface_id": "context",
                "pane_rect": {"left": 8, "top": 12, "width": 1440, "height": 900},
                "viewport_target": [0.0, 0.0, 1920.0, 1080.0],
                "screenshot_dimensions": {"width": 1600, "height": 1000},
                "crop_dimensions": {"width": 1440, "height": 900},
                "scroll_percentages": {"horizontal": 0.0, "vertical": 0.0},
                "scroll_coverage_complete": True,
                "scroll_restored": True,
            }
        ]

    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_capture_feedback_surface_evidence",
        capture_surfaces,
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=evidence,
        mode="calibration-smoke",
        require_tmt=True,
    )

    # Assert
    assert result.status == "passed"
    assert captured["surface_limit"] == 1
    assert captured["require_feedback_evidence"] is True
    assert captured["calibration_context"] is None
    assert processes and all(process.closed for process in processes)
    summary = json.loads(
        (evidence / "summaries" / "calibration-smoke.json").read_text(encoding="utf-8")
    )
    calibration = summary["layout_calibration_v1"]
    assert calibration["scope"] == "same-run"
    assert calibration["pane_rect"] == [8, 12, 1440, 900]
    assert calibration["effective_scale"]["x"] == pytest.approx(1440 / 1920)
    assert calibration["confidence"]["pane_measured"] is True


def test_given_unmeasured_pane_when_calibration_smoke_then_fails_closed(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    monkeypatch.setattr(
        validate_tm7_with_tmt,
        "_capture_feedback_surface_evidence",
        lambda **kwargs: [],
    )

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        mode="calibration-smoke",
        require_tmt=True,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_VALIDATION_FAILURE
    assert "Calibration smoke" in result.message


def test_given_validate_mode_when_successful_then_closure_evidence_is_complete(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    evidence = tmp_path / "evidence"

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=evidence,
        mode="validate",
        require_tmt=True,
        expected_threat_count=1,
    )

    # Assert
    assert result.status == "passed"
    required = {
        "screenshots/initial-open.png",
        "screenshots/analysis-view.png",
        "screenshots/post-save.png",
        "screenshots/reopen-analysis-view.png",
        "uia/initial-open.txt",
        "uia/analysis-view.txt",
        "uia/reopen-analysis.txt",
        "exports/before-save.csv",
        "exports/after-reopen.csv",
        "summaries/before-save.json",
        "summaries/after-reopen.json",
        "manifest.json",
        "status.json",
        "action.log",
    }
    actual = {
        str(path.relative_to(evidence)).replace("\\", "/")
        for path in evidence.rglob("*")
        if path.is_file()
    }
    assert required <= actual
    assert "PASS save-workspace-copy" in (evidence / "action.log").read_text(
        encoding="utf-8"
    )


def test_given_declined_template_when_reopened_then_declines_again(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)
    policies: list[str] = []

    def capture_modal(*args: Any, **kwargs: Any) -> None:
        policies.append(str(kwargs["template_upgrade_policy"]))

    monkeypatch.setattr(validate_tm7_with_tmt, "_capture_modal", capture_modal)

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        require_tmt=True,
        expected_threat_count=1,
        template_upgrade_policy="decline",
    )

    # Assert
    assert result.status == "passed"
    assert policies == ["decline", "decline"]


def test_given_compare_mode_without_second_candidate_then_returns_usage_error(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Arrange
    _patch_successful_automation(monkeypatch, tmp_path)

    # Act
    result = validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=tmp_path / "evidence",
        mode="compare-generation-state",
        require_tmt=True,
    )

    # Assert
    assert result.exit_code == validate_tm7_with_tmt.EXIT_ERROR
    assert "comparison-model" in result.message


def test_given_secret_manifest_values_when_written_then_all_are_redacted(
    tmp_path: Path,
) -> None:
    # Arrange
    bundle = validate_tm7_with_tmt.EvidenceBundle(tmp_path / "evidence")
    secret = "do-not-persist"

    # Act
    bundle.write_manifest(
        {
            "client_secret": secret,
            "authorization": f"Bearer {secret}",
            "url": f"https://example.test/path?sig={secret}",
        }
    )
    manifest_text = bundle.manifest_path.read_text(encoding="utf-8")

    # Assert
    assert secret not in manifest_text
    assert "[REDACTED]" in manifest_text
    assert "?sig=" not in manifest_text


def test_given_status_when_written_then_version_inventory_is_auditable(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _patch_successful_automation(monkeypatch, tmp_path)
    evidence = tmp_path / "evidence"

    validate_tm7_with_tmt.run_harness(
        input_model=_input_model(tmp_path),
        evidence_dir=evidence,
        mode="probe",
        require_tmt=True,
    )
    status = json.loads((evidence / "status.json").read_text(encoding="utf-8"))

    assert status["required_tmt_version"] == "7.3.51110.1"
    assert status["observed_tmt_version"] == "7.3.51110.1"
    assert status["evidence_schema_version"] == 1
    assert "evidence_files" in status
