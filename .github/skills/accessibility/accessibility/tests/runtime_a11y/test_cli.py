# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
import runtime_a11y.__main__ as cli
from runtime_a11y._errors import EXIT_SUCCESS, EXIT_USAGE
from runtime_a11y.visual_review import build_visual_review_manifest


@pytest.fixture(autouse=True)
def patch_repo_root(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setattr(cli, "_REPO_ROOT", tmp_path)
    (tmp_path / ".copilot-tracking" / "accessibility" / "local-runs").mkdir(
        parents=True,
        exist_ok=True,
    )


@pytest.fixture()
def canned_probe_document() -> dict[str, object]:
    return {
        "probeId": "probe-axe",
        "results": [
            {
                "criterionId": "1.3.1",
                "surfaceId": "web",
                "state": "default",
                "status": "pass",
                "method": "runtime-automation",
            }
        ],
    }


def _allowed_run_path(tmp_path: Path, name: str) -> Path:
    run_root = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / name
    )
    run_root.mkdir(parents=True, exist_ok=True)
    return run_root


def _write_retained_preflight_bundle(
    tmp_path: Path, *, manifest_count: int = 10
) -> tuple[Path, Path, list[Path]]:
    retained_run_root = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "retained-preflight"
    )
    retained_run_root.mkdir(parents=True, exist_ok=True)
    manifest_paths: list[Path] = []
    runs: list[dict[str, str]] = []
    for index in range(manifest_count):
        manifest_dir = (
            retained_run_root
            / "runs"
            / f"surface-{index // 5 + 1}"
            / f"state-{index % 5 + 1}"
        )
        manifest_dir.mkdir(parents=True, exist_ok=True)
        artifact_dir = manifest_dir / "artifacts"
        artifact_dir.mkdir(parents=True, exist_ok=True)
        screenshot_path = artifact_dir / "screenshot.png"
        screenshot_path.write_bytes(f"bundle-{index}".encode("utf-8"))
        (artifact_dir / "trace.json").write_text("{}", encoding="utf-8")
        (artifact_dir / "measurements.json").write_text("{}", encoding="utf-8")
        manifest_payload = build_visual_review_manifest(
            run_root=manifest_dir,
            run_id=f"preflight-{index}",
            route="/",
            surface=f"surface-{index // 5 + 1}",
            state=f"state-{index % 5 + 1}",
            viewport={"width": 1440, "height": 900},
            browser={"name": "chrome", "version": "126.0"},
            platform={"os": "linux", "version": "local"},
            screenshot_path="artifacts/screenshot.png",
            trace_path="artifacts/trace.json",
            measurement_path="artifacts/measurements.json",
            deterministic_metrics={"score": 1},
            probe_outcomes=[],
            provenance={},
        )
        manifest_path = manifest_dir / "manifest.json"
        manifest_path.write_text(json.dumps(manifest_payload), encoding="utf-8")
        manifest_paths.append(manifest_path)
        runs.append(
            {"surface": f"surface-{index // 5 + 1}", "state": f"state-{index % 5 + 1}"}
        )

    output_path = retained_run_root / "visual-review-output.json"
    output_path.write_text(
        json.dumps(
            {
                "tool": "runtime_a11y",
                "command": "capture-visual-review",
                "manifestPaths": [str(path) for path in manifest_paths],
                "runRoot": str(retained_run_root),
                "runs": runs,
            }
        ),
        encoding="utf-8",
    )
    return retained_run_root, output_path, manifest_paths


def test_resolve_repo_path_rejects_required_empty_and_uri_inputs() -> None:
    with pytest.raises(cli.ScriptError, match="required"):
        cli._resolve_repo_path(None, kind="--config")

    with pytest.raises(cli.ScriptError, match="empty"):
        cli._resolve_repo_path("   ", kind="--config")

    with pytest.raises(cli.ScriptError, match="URI"):
        cli._resolve_repo_path("file:///tmp/file", kind="--config")


def test_resolve_within_root_rejects_invalid_inputs_and_directory(
    tmp_path: Path,
) -> None:
    allowed_root = tmp_path / ".copilot-tracking" / "accessibility" / "local-runs"
    allowed_root.mkdir(parents=True, exist_ok=True)

    with pytest.raises(cli.ScriptError, match="required"):
        cli._resolve_within_root(
            None, allowed_root=allowed_root, kind="--retained-preflight"
        )
    with pytest.raises(cli.ScriptError, match="empty"):
        cli._resolve_within_root(
            " ", allowed_root=allowed_root, kind="--retained-preflight"
        )
    with pytest.raises(cli.ScriptError, match="URI"):
        cli._resolve_within_root(
            "https://example.com/file.json",
            allowed_root=allowed_root,
            kind="--retained-preflight",
        )
    with pytest.raises(cli.ScriptError, match="resolve inside"):
        cli._resolve_within_root(
            tmp_path / "outside.json",
            allowed_root=allowed_root,
            kind="--retained-preflight",
        )
    with pytest.raises(cli.ScriptError, match="traversal"):
        cli._resolve_within_root(
            "../escape.json",
            base_dir=allowed_root / "run",
            allowed_root=allowed_root,
            kind="--retained-preflight",
        )
    retained_dir = allowed_root / "run"
    retained_dir.mkdir()
    with pytest.raises(cli.ScriptError, match="file"):
        cli._resolve_within_root(
            retained_dir,
            allowed_root=allowed_root,
            kind="--retained-preflight",
        )


def test_resolve_repo_path_enforces_allowed_root_defaults_and_traversal(
    tmp_path: Path,
) -> None:
    allowed_root = tmp_path / ".copilot-tracking" / "accessibility" / "local-runs"
    allowed_root.mkdir(parents=True, exist_ok=True)
    inside = allowed_root / "2026-07-22" / "child" / "report.json"

    resolved = cli._resolve_repo_path(
        str(inside),
        kind="--out",
        allowed_root=allowed_root,
    )
    assert resolved == inside.resolve()

    with pytest.raises(cli.ScriptError, match="resolve inside"):
        cli._resolve_repo_path(
            str(tmp_path / "outside" / "report.json"),
            kind="--out",
            allowed_root=allowed_root,
        )

    with pytest.raises(cli.ScriptError):
        cli._resolve_repo_path(
            "..\\outside.json", kind="--out", allowed_root=allowed_root
        )

    local_run_path = cli._local_runs_root() / "2026-07-22" / "custom-run"
    resolved_default = cli._resolve_repo_path(str(local_run_path), kind="--run-root")
    assert resolved_default == local_run_path.resolve()


def test_resolve_output_allowed_root_and_public_path_cover_fallback_branches(
    tmp_path: Path,
) -> None:
    local_runs_root = tmp_path / ".copilot-tracking" / "accessibility" / "local-runs"
    run_root = local_runs_root / "2026-07-22" / "run"
    out_path = run_root / "output.json"
    assert cli._resolve_output_allowed_root(run_root, out_path) == run_root.resolve()
    assert (
        cli._resolve_output_allowed_root(None, None) == cli._local_runs_root().resolve()
    )

    sibling_out = local_runs_root / "2026-07-22" / "output.json"
    assert (
        cli._resolve_output_allowed_root(run_root, sibling_out)
        == (local_runs_root / "2026-07-22").resolve()
    )
    assert cli._public_path(str(tmp_path / "docs" / "readme.md")) == "docs/readme.md"
    assert cli._public_path("/tmp/outside") == "C:/tmp/outside"
    assert cli._public_path(None) is None


def test_resolve_output_allowed_root_handles_relative_and_outside_paths(
    tmp_path: Path,
) -> None:
    relative_run = Path(
        ".copilot-tracking/accessibility/local-runs/2026-07-22/relative-run"
    )
    relative_out = relative_run / "output.json"
    expected_run = (tmp_path / relative_run).resolve()
    assert cli._resolve_output_allowed_root(relative_run, relative_out) == expected_run

    outside = tmp_path / "outside" / "output.json"
    assert (
        cli._resolve_output_allowed_root(expected_run, outside)
        == cli._local_runs_root()
    )

    with pytest.raises(cli.ScriptError, match="child path"):
        cli._resolve_repo_path(cli._local_runs_root(), kind="--run-root")


def test_resolve_repo_path_accepts_relative_allowed_root_and_rejects_traversal(
    tmp_path: Path,
) -> None:
    allowed_root = Path("nested/allowed")
    resolved = cli._resolve_repo_path(
        str(allowed_root / "child" / "report.json"),
        kind="--out",
        allowed_root=allowed_root,
    )

    assert resolved == (tmp_path / allowed_root / "child" / "report.json").resolve()

    with pytest.raises(cli.ScriptError, match="traversal segments"):
        cli._resolve_repo_path(
            "nested/../nested/allowed/child/report.json",
            kind="--out",
            allowed_root=allowed_root,
        )


@pytest.mark.parametrize(
    ("missing_key", "expected_message"),
    [
        ("surface", "surface metadata is missing"),
        ("state", "state metadata is missing"),
    ],
)
def test_import_retained_preflight_bundle_reports_missing_manifest_metadata(
    tmp_path: Path,
    missing_key: str,
    expected_message: str,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    manifest_payload = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    manifest_payload.pop(missing_key, None)
    manifest_paths[0].write_text(json.dumps(manifest_payload), encoding="utf-8")

    monkeypatch.setattr(
        cli,
        "validate_visual_review_manifest",
        lambda manifest, *, run_root: manifest,
    )

    with pytest.raises(cli.ScriptError, match=expected_message):
        cli._import_retained_preflight_bundle(
            output_path,
            run_root=tmp_path / "imported-run",
        )


def test_import_retained_preflight_bundle_falls_back_to_copying_artifacts(
    tmp_path: Path,
    mocker,
) -> None:
    _, output_path, _ = _write_retained_preflight_bundle(tmp_path, manifest_count=10)
    mocker.patch.object(cli.os, "link", side_effect=OSError("link failed"))

    imported_bundle = cli._import_retained_preflight_bundle(
        output_path,
        run_root=tmp_path / "imported-run",
    )

    assert imported_bundle["retainedBundleValidated"] is True
    assert (tmp_path / "imported-run" / "retained-preflight").exists()


def test_given_script_entrypoint_when_invoked_directly_then_module_imports_work(
    tmp_path: Path,
) -> None:
    cli_path = Path(cli.__file__).resolve().parent

    completed = subprocess.run(
        [sys.executable, str(cli_path), "--help"],
        capture_output=True,
        text=True,
        cwd=tmp_path,
        check=False,
    )

    assert completed.returncode == 0, completed.stderr
    assert "usage:" in completed.stdout.lower()


def test_materialize_visual_artifact_copies_and_rejects_escape(
    tmp_path: Path,
) -> None:
    run_root = tmp_path / "run-root"
    manifest_dir = tmp_path / "manifest"
    run_root.mkdir(parents=True, exist_ok=True)
    manifest_dir.mkdir(parents=True, exist_ok=True)
    artifact_path = run_root / "artifacts" / "screenshot.png"
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path.write_bytes(b"artifact-data")

    relative_artifact = cli._materialize_visual_review_artifact(
        "artifacts/screenshot.png",
        run_root=run_root,
        manifest_dir=manifest_dir,
    )

    assert relative_artifact == "artifacts/screenshot.png"
    copied = manifest_dir / "artifacts" / "screenshot.png"
    assert copied.read_bytes() == b"artifact-data"

    with pytest.raises(cli.ScriptError, match="containment"):
        cli._materialize_visual_review_artifact(
            "../escape.png",
            run_root=run_root,
            manifest_dir=manifest_dir,
        )

    with pytest.raises(cli.ScriptError, match="relative for containment"):
        cli._materialize_visual_review_artifact(
            "https://example.com/screenshot.png",
            run_root=run_root,
            manifest_dir=manifest_dir,
        )


def test_visual_review_server_helpers_probe_and_start_handlers(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    class FakeResponse:
        def __enter__(self) -> "FakeResponse":
            return self

        def __exit__(self, exc_type, exc, tb) -> bool:
            return False

        def getcode(self) -> int:
            return 200

    def fake_urlopen(url: str, timeout: float) -> FakeResponse:
        assert url.startswith("http://127.0.0.1")
        return FakeResponse()

    monkeypatch.setattr(cli, "urlopen", fake_urlopen)
    assert cli._probe_visual_review_server("http://127.0.0.1:3000/") is True
    assert cli._probe_visual_review_server("http://example.com/") is False

    monkeypatch.setattr(cli, "_REPO_ROOT", tmp_path)
    (tmp_path / "docs" / "docusaurus").mkdir(parents=True, exist_ok=True)

    class FakeProcess:
        def poll(self) -> int | None:
            return None

        def terminate(self) -> None:
            return None

        def wait(self, timeout: int | None = None) -> None:
            return None

    def fake_popen(command, cwd, stdout, stderr, stdin, text) -> FakeProcess:
        assert command[0] == "npm"
        return FakeProcess()

    monkeypatch.setattr(cli.subprocess, "Popen", fake_popen)
    monkeypatch.setattr(cli.time, "sleep", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(
        cli, "_probe_visual_review_server", lambda *_args, **_kwargs: True
    )

    process = cli._start_visual_review_server("http://127.0.0.1:3000/")
    assert isinstance(process, FakeProcess)

    monkeypatch.setattr(
        cli, "_probe_visual_review_server", lambda *_args, **_kwargs: False
    )
    monkeypatch.setattr(
        cli, "_start_visual_review_server", lambda *_args, **_kwargs: "started"
    )
    assert cli._ensure_visual_review_server("http://127.0.0.1:3000/") == (
        "started",
        True,
    )


def test_given_run_all_when_subprocess_returns_probe_data_then_aggregates_results(
    mocker, canned_probe_document: dict[str, object], tmp_path: Path
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(
            stdout=json.dumps(canned_probe_document), stderr=""
        ),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "a11y-runtime.config.json"
    config_path.write_text(
        '{"baseUrl": "http://127.0.0.1:3000", '
        '"surfaces": [{"id": "web", "type": "page"}], '
        '"probeScoping": [{"probe": "probe-axe", '
        '"surfaces": ["web"], "states": ["default"]}]}',
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "results.json"
    )

    exit_code = cli.main(
        ["run-all", "--config", str(config_path), "--out", str(out_path)]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["tool"] == "runtime_a11y"
    assert document["results"][0]["criterionId"] == "1.3.1"
    assert document["runs"][0]["probeId"] == "probe-axe"


def test_given_calibration_run_when_run_root_override_is_provided_then_subprocess_receives_it(  # noqa: E501
    mocker,
    tmp_path: Path,
) -> None:
    captured: dict[str, object] = {}
    allowed_run_root = _allowed_run_path(tmp_path, "custom-run-root")

    def fake_run(command, capture_output, text, check, env, cwd):
        captured["env"] = env
        return SimpleNamespace(
            stdout=json.dumps(
                {
                    "tool": "runtime_a11y",
                    "command": "run-calibration",
                    "aggregate": {"status": "successful"},
                }
            ),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(
        cli, "resolve_run_root", return_value=tmp_path / "calibration-run"
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--run-root",
            str(allowed_run_root),
        ]
    )

    assert exit_code == EXIT_SUCCESS
    assert captured["env"]["RUNTIME_A11Y_RUN_ROOT"] == str(allowed_run_root)


def test_calibration_run_passes_base_url_override(
    mocker,
    tmp_path: Path,
) -> None:
    captured: dict[str, object] = {}

    def fake_run(command, capture_output, text, check, env, cwd):
        captured["env"] = env
        return SimpleNamespace(
            stdout=json.dumps(
                {
                    "tool": "runtime_a11y",
                    "command": "run-calibration",
                    "aggregate": {"status": "successful"},
                }
            ),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--base-url",
            "http://127.0.0.1:3001",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    payload = json.loads(captured["env"]["RUNTIME_A11Y_CONFIG"])
    assert payload["baseUrl"] == "http://127.0.0.1:3001"
    assert captured["env"]["RUNTIME_A11Y_BASE_URL"] == "http://127.0.0.1:3001"


def test_given_calibration_run_when_prerequisite_only_then_reports_readiness(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout="", stderr=""),
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--prerequisite-only",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["aggregate"]["status"] == "successful"
    assert document["aggregate"]["reason"] == "Calibration prerequisites are ready."


def test_run_calibration_emits_start_and_finish_notices_for_live_execution(
    mocker,
    tmp_path: Path,
    capsys,
) -> None:
    mocker.patch.object(
        cli,
        "_run_calibration_session",
        return_value={"aggregate": {"status": "successful"}},
    )
    mocker.patch.object(cli, "_ensure_visual_review_server", return_value=(None, False))
    mocker.patch.object(cli, "_stop_visual_review_server")
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = _allowed_run_path(tmp_path, "live-notice") / "calibration-output.json"

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
        ]
    )

    assert exit_code == EXIT_SUCCESS
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.splitlines()[0] == cli._LIVE_TEST_START_NOTICE
    assert captured.err.splitlines()[1].startswith("Run root: ")
    assert "Journey count: 1" in captured.err.splitlines()[1]
    assert captured.err.splitlines()[-1] == cli._LIVE_TEST_FINISH_NOTICE


def test_run_calibration_does_not_emit_live_notices_for_prerequisite_only(
    mocker,
    tmp_path: Path,
    capsys,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout="", stderr=""),
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        _allowed_run_path(tmp_path, "prerequisite-notice") / "calibration-output.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--prerequisite-only",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    captured = capsys.readouterr()
    assert captured.err == ""


@pytest.mark.parametrize("failure", [cli.ScriptError("failed"), KeyboardInterrupt()])
def test_live_notice_finishes_after_owned_cleanup_on_failure(
    mocker,
    tmp_path: Path,
    capsys,
    failure: BaseException,
) -> None:
    events: list[str] = []
    mocker.patch.object(
        cli,
        "_ensure_visual_review_server",
        return_value=(SimpleNamespace(), True),
    )
    mocker.patch.object(
        cli,
        "_stop_visual_review_server",
        side_effect=lambda _process: events.append("cleanup"),
    )
    mocker.patch.object(
        cli,
        "_emit_live_test_finish_notice",
        side_effect=lambda: events.append("finish"),
    )
    mocker.patch.object(cli, "_run_calibration_session", side_effect=failure)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "visualReview": {"enabled": True},
                "calibration": {"journeys": [{"id": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = _allowed_run_path(tmp_path, "failure-notice") / "output.json"

    if isinstance(failure, KeyboardInterrupt):
        with pytest.raises(KeyboardInterrupt):
            cli.main(
                [
                    "run-calibration",
                    "--config",
                    str(config_path),
                    "--out",
                    str(out_path),
                ]
            )
    else:
        assert (
            cli.main(
                [
                    "run-calibration",
                    "--config",
                    str(config_path),
                    "--out",
                    str(out_path),
                ]
            )
            == failure.exit_code
        )

    assert events == ["cleanup", "finish"]
    assert cli._LIVE_TEST_START_NOTICE in capsys.readouterr().err


def test_stop_owned_server_kills_after_wait_timeout(mocker) -> None:
    process = SimpleNamespace(
        poll=lambda: None,
        terminate=mocker.Mock(),
        wait=mocker.Mock(side_effect=subprocess.TimeoutExpired("server", 5)),
        kill=mocker.Mock(),
    )

    cli._stop_visual_review_server(process)

    process.terminate.assert_called_once()
    process.kill.assert_called_once()


def test_prerequisite_probe_invalid_json_falls_back_ready(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout="not-json", stderr=""),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    mocker.patch.object(
        cli, "resolve_run_root", return_value=tmp_path / "calibration-run"
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--prerequisite-only",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["aggregate"]["reason"] == "Calibration prerequisites are ready."


def test_calibration_session_no_output_reports_usage_error(
    mocker,
    tmp_path: Path,
    capsys,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout="", stderr=""),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}),
        encoding="utf-8",
    )

    exit_code = cli.main(["run-calibration", "--config", str(config_path)])

    assert exit_code == EXIT_USAGE
    captured = capsys.readouterr()
    assert "Calibration produced no JSON output" in captured.err


def test_given_calibration_session_when_subprocess_errors_then_reports_failure(
    mocker,
    tmp_path: Path,
    capsys,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        side_effect=subprocess.CalledProcessError(
            1,
            ["node"],
            stderr="calibration exploded",
        ),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    mocker.patch.object(
        cli, "resolve_run_root", return_value=tmp_path / "calibration-run"
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}),
        encoding="utf-8",
    )

    exit_code = cli.main(["run-calibration", "--config", str(config_path)])

    assert exit_code == 1
    captured = capsys.readouterr()
    assert "calibration exploded" in captured.err


def test_nvda_only_checkpoint_resolves_run_root_and_mode(
    mocker,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _allowed_run_path(tmp_path, "out")
    captured: dict[str, object] = {}

    def fake_run(command, capture_output, text, check, env, cwd):
        captured["env"] = env
        return SimpleNamespace(
            stdout=json.dumps(
                {
                    "tool": "runtime_a11y",
                    "command": "run-calibration",
                    "aggregate": {"status": "successful"},
                }
            ),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    monkeypatch.chdir(tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--nvda-only",
            "--checkpoint-path",
            ".copilot-tracking/accessibility/local-runs/2026-07-22/out/checkpoint.json",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert (
        document["runRoot"]
        == ".copilot-tracking/accessibility/local-runs/2026-07-22/out"
    )
    assert (
        document["checkpointPath"]
        == ".copilot-tracking/accessibility/local-runs/2026-07-22/out/checkpoint.json"
    )
    payload = json.loads(captured["env"]["RUNTIME_A11Y_CONFIG"])
    assert payload["calibration"]["mode"] == "nvdaOnly"


def test_import_retained_preflight_bundle_accepts_valid_two_by_five_bundle(
    tmp_path: Path,
) -> None:
    _, output_path, _ = _write_retained_preflight_bundle(tmp_path, manifest_count=10)

    imported_bundle = cli._import_retained_preflight_bundle(
        output_path,
        run_root=tmp_path / "imported-run",
    )

    assert imported_bundle["bundleId"] == "visual-preflight"
    assert imported_bundle["retainedBundleValidated"] is True
    assert len(imported_bundle["artifactHashes"]) == 30
    assert (tmp_path / "imported-run" / "retained-preflight").exists()


@pytest.mark.parametrize(
    ("payload", "expected_message"),
    [
        ("[]", "JSON object"),
        ({"command": "capture-visual-review"}, "manifestPaths"),
        (
            {
                "command": "run-calibration",
                "manifestPaths": ["/tmp/manifest.json"] * 10,
            },
            "capture-visual-review",
        ),
        (
            {"command": "capture-visual-review", "manifestPaths": "not-a-list"},
            "manifestPaths as a list",
        ),
        (
            {
                "command": "capture-visual-review",
                "manifestPaths": ["/tmp/manifest.json"],
            },
            "exactly 10",
        ),
        (
            {"command": "capture-visual-review", "manifestPaths": ["a"] * 9},
            "exactly 10",
        ),
        (
            {"command": "capture-visual-review", "manifestPaths": ["a"] * 11},
            "exactly 10",
        ),
    ],
)
def test_import_retained_preflight_bundle_rejects_invalid_payload_contract(
    tmp_path: Path,
    payload: object,
    expected_message: str,
) -> None:
    retained_run_root = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "retained-preflight"
    )
    retained_run_root.mkdir(parents=True, exist_ok=True)
    output_path = retained_run_root / "visual-review-output.json"
    if isinstance(payload, str):
        output_path.write_text(payload, encoding="utf-8")
    else:
        output_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(cli.ScriptError, match=expected_message):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_rejects_missing_directory_and_bad_json(
    tmp_path: Path,
) -> None:
    allowed_root = (
        tmp_path / ".copilot-tracking" / "accessibility" / "local-runs" / "2026-07-22"
    )
    allowed_root.mkdir(parents=True)
    missing = allowed_root / "missing.json"
    with pytest.raises(cli.ScriptError, match="does not exist"):
        cli._import_retained_preflight_bundle(
            missing, run_root=tmp_path / "imported-run"
        )

    directory = allowed_root / "directory"
    directory.mkdir()
    with pytest.raises(cli.ScriptError, match="file"):
        cli._import_retained_preflight_bundle(
            directory, run_root=tmp_path / "imported-run"
        )

    invalid_json = allowed_root / "invalid.json"
    invalid_json.write_text("{", encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="Unable to read"):
        cli._import_retained_preflight_bundle(
            invalid_json, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_rejects_invalid_runs_contract(
    tmp_path: Path,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    payload = json.loads(output_path.read_text(encoding="utf-8"))

    payload["runs"] = "invalid"
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="runs must be a list"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    payload["runs"] = [{"surface": "one", "state": "state"}]
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="run count"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    payload["manifestPaths"] = [str(path) for path in manifest_paths]
    payload["runs"] = [None, *[{"surface": "one", "state": "state"}] * 9]
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="entries must be objects"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


@pytest.mark.parametrize(
    ("run_entry", "expected_message"),
    [
        ({"surface": "", "state": "state-1"}, "surface values"),
        ({"surface": "surface-1", "state": ""}, "state values"),
    ],
)
def test_import_retained_preflight_rejects_incomplete_run_metadata(
    tmp_path: Path,
    run_entry: dict[str, str],
    expected_message: str,
) -> None:
    _, output_path, _ = _write_retained_preflight_bundle(tmp_path, manifest_count=10)
    payload = json.loads(output_path.read_text(encoding="utf-8"))
    payload["runs"][0] = run_entry
    output_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(cli.ScriptError, match=expected_message):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_rejects_empty_and_malformed_manifests(
    tmp_path: Path,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    payload = json.loads(output_path.read_text(encoding="utf-8"))
    payload["manifestPaths"][0] = ""
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="non-empty strings"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    payload["manifestPaths"][0] = str(manifest_paths[0])
    manifest_paths[0].write_text("{", encoding="utf-8")
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="Unable to read retained preflight"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_bundle_rejects_missing_manifest_and_bad_schema(
    tmp_path: Path,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    payload = {
        "tool": "runtime_a11y",
        "command": "capture-visual-review",
        "manifestPaths": [
            str(manifest_paths[0]),
            str(tmp_path / "missing.json"),
            *[str(manifest_paths[index]) for index in range(2, 10)],
        ],
        "runRoot": str(
            tmp_path
            / ".copilot-tracking"
            / "accessibility"
            / "local-runs"
            / "2026-07-22"
            / "retained-preflight"
        ),
        "runs": [
            {"surface": f"surface-{index // 5 + 1}", "state": f"state-{index % 5 + 1}"}
            for index in range(10)
        ],
    }
    output_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(cli.ScriptError, match="resolve inside"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    broken_manifest = manifest_paths[0]
    broken_manifest.write_text("{}", encoding="utf-8")
    payload["manifestPaths"] = [str(broken_manifest)] * 10
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="relative path"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_bundle_rejects_invalid_hashes_and_artifacts(
    tmp_path: Path,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    manifest_payload = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    manifest_payload["artifacts"]["screenshots"][0]["sha256"] = "short"
    manifest_paths[0].write_text(json.dumps(manifest_payload), encoding="utf-8")
    payload = {
        "tool": "runtime_a11y",
        "command": "capture-visual-review",
        "manifestPaths": [str(manifest_paths[0])]
        + [str(path) for path in manifest_paths[1:]],
        "runRoot": str(
            tmp_path
            / ".copilot-tracking"
            / "accessibility"
            / "local-runs"
            / "2026-07-22"
            / "retained-preflight"
        ),
        "runs": [
            {"surface": f"surface-{index // 5 + 1}", "state": f"state-{index % 5 + 1}"}
            for index in range(10)
        ],
    }
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="64-character"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    manifest_payload = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    manifest_payload["artifacts"]["screenshots"][0]["sha256"] = hashlib.sha256(
        b"ok"
    ).hexdigest()
    manifest_payload["artifacts"]["screenshots"][0]["path"] = "../escape.png"
    manifest_paths[0].write_text(json.dumps(manifest_payload), encoding="utf-8")
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="containment"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    manifest_payload = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    manifest_payload["artifacts"]["screenshots"][0]["path"] = "artifacts/screenshot.png"
    manifest_payload["artifacts"]["screenshots"][0]["sha256"] = hashlib.sha256(
        b"wrong"
    ).hexdigest()
    manifest_paths[0].write_text(json.dumps(manifest_payload), encoding="utf-8")
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="hashes do not match"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )

    manifest_payload = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
    manifest_payload["artifacts"]["screenshots"][0]["path"] = "artifacts/missing.png"
    manifest_paths[0].write_text(json.dumps(manifest_payload), encoding="utf-8")
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises(cli.ScriptError, match="artifact does not exist"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_import_retained_preflight_bundle_rejects_surface_state_mismatch(
    tmp_path: Path,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    payload = {
        "tool": "runtime_a11y",
        "command": "capture-visual-review",
        "manifestPaths": [str(path) for path in manifest_paths],
        "runRoot": str(
            tmp_path
            / ".copilot-tracking"
            / "accessibility"
            / "local-runs"
            / "2026-07-22"
            / "retained-preflight"
        ),
        "runs": [{"surface": "surface-2", "state": "state-1"} for _ in manifest_paths],
    }
    output_path.write_text(json.dumps(payload), encoding="utf-8")

    with pytest.raises(cli.ScriptError, match="surface-state"):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


@pytest.mark.parametrize(
    ("mutation", "expected_message"),
    [
        ("non-pass", "deterministic-pass"),
        ("capture-failure", "capture failures"),
        ("duplicate", "duplicate surface-state"),
    ],
)
def test_import_retained_preflight_rejects_invalid_evidence_matrix(
    tmp_path: Path,
    mutation: str,
    expected_message: str,
) -> None:
    _, output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    if mutation == "duplicate":
        payload = json.loads(output_path.read_text(encoding="utf-8"))
        payload["runs"][1] = payload["runs"][0]
        manifest = json.loads(manifest_paths[1].read_text(encoding="utf-8"))
        manifest["surface"] = payload["runs"][0]["surface"]
        manifest["state"] = payload["runs"][0]["state"]
        manifest_paths[1].write_text(json.dumps(manifest), encoding="utf-8")
        output_path.write_text(json.dumps(payload), encoding="utf-8")
    else:
        manifest = json.loads(manifest_paths[0].read_text(encoding="utf-8"))
        if mutation == "non-pass":
            manifest["evidenceState"] = "ambiguous"
        else:
            manifest["probeOutcomes"] = [{"status": "capture-failure"}]
        manifest_paths[0].write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(cli.ScriptError, match=expected_message):
        cli._import_retained_preflight_bundle(
            output_path, run_root=tmp_path / "imported-run"
        )


def test_main_rejects_retained_preflight_flag_misuse(tmp_path: Path) -> None:
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {"baseUrl": "http://127.0.0.1:3000", "calibration": {"journeys": []}}
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--retained-preflight",
            "bundle.json",
        ]
    )
    assert exit_code == cli.EXIT_USAGE

    with pytest.raises(SystemExit):
        cli.main(["unknown-command"])


def test_given_retained_preflight_when_nvda_only_then_checkpoint_imports_bundle(
    mocker,
    tmp_path: Path,
) -> None:
    _, retained_output_path, manifest_paths = _write_retained_preflight_bundle(
        tmp_path, manifest_count=10
    )
    payload = json.loads(retained_output_path.read_text(encoding="utf-8"))
    payload["manifestPaths"] = [str(path) for path in manifest_paths]
    payload["runs"] = [
        {"surface": f"surface-{index // 5 + 1}", "state": f"state-{index % 5 + 1}"}
        for index in range(10)
    ]
    retained_output_path.write_text(json.dumps(payload), encoding="utf-8")

    captured: dict[str, object] = {}

    def fake_run(command, capture_output, text, check, env, cwd):
        captured["env"] = env
        return SimpleNamespace(
            stdout=json.dumps(
                {
                    "tool": "runtime_a11y",
                    "command": "run-calibration",
                    "aggregate": {"status": "successful"},
                }
            ),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            str(out_path),
            "--nvda-only",
            "--retained-preflight",
            str(retained_output_path),
        ]
    )

    assert exit_code == EXIT_SUCCESS
    checkpoint_path = Path(str(captured["env"]["RUNTIME_A11Y_CHECKPOINT_PATH"]))
    assert checkpoint_path.exists()
    checkpoint_payload = json.loads(checkpoint_path.read_text(encoding="utf-8"))
    assert (
        checkpoint_payload["state"]["visualPreflightBundle"]["retainedBundleValidated"]
        is True
    )
    assert checkpoint_payload["state"]["visualPreflightBundle"]["artifactHashes"]
    assert captured["env"]["RUNTIME_A11Y_CHECKPOINT_PATH"] == str(checkpoint_path)


def test_given_calibration_run_when_subprocess_succeeds_then_document_contains_evidence(
    mocker,
    tmp_path: Path,
) -> None:
    _allowed_run_path(tmp_path, "calibration-run")
    payload = {
        "tool": "runtime_a11y",
        "command": "run-calibration",
        "aggregate": {"status": "successful", "reason": "Calibration completed"},
        "journeys": ["14399", "14410"],
        "checkpoints": [{"journeyId": "14399", "ordinal": 0, "classification": "pass"}],
        "state": {"journeys": {}},
    }
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout=json.dumps(payload), stderr=""),
    )
    mocker.patch.object(
        cli, "resolve_run_root", return_value=tmp_path / "calibration-run"
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {
                    "journeys": [
                        {"id": "14399", "bugId": "14399"},
                        {"id": "14410", "bugId": "14410"},
                    ]
                },
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        ["run-calibration", "--config", str(config_path), "--out", str(out_path)]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["command"] == "run-calibration"
    assert document["aggregate"]["status"] == "successful"
    assert document["journeys"] == ["14399", "14410"]


def test_given_calibration_run_when_aggregate_is_missing_then_document_reports_unsuccessful(  # noqa: E501
    mocker,
    tmp_path: Path,
) -> None:
    _allowed_run_path(tmp_path, "calibration-run")
    payload = {
        "tool": "runtime_a11y",
        "command": "run-calibration",
        "journeys": ["14399"],
        "checkpoints": [],
        "state": {"journeys": []},
    }
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout=json.dumps(payload), stderr=""),
    )
    mocker.patch.object(
        cli, "resolve_run_root", return_value=tmp_path / "calibration-run"
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "calibration": {"journeys": [{"id": "14399", "bugId": "14399"}]},
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "calibration.json"
    )

    exit_code = cli.main(
        ["run-calibration", "--config", str(config_path), "--out", str(out_path)]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["aggregate"]["status"] == "unsuccessful"
    assert (
        document["aggregate"]["reason"]
        == "Calibration completed without an aggregate status."
    )


def test_repo_relative_paths_dispatch_as_absolute(
    mocker,
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    captured: dict[str, object] = {}
    allowed_root = tmp_path / ".copilot-tracking" / "accessibility" / "local-runs"
    allowed_root.mkdir(parents=True, exist_ok=True)
    (tmp_path / "elsewhere").mkdir(parents=True, exist_ok=True)
    monkeypatch.chdir(tmp_path / "elsewhere")

    def fake_run(command, capture_output, text, check, env, cwd):
        captured["env"] = env
        return SimpleNamespace(
            stdout=json.dumps(
                {
                    "tool": "runtime_a11y",
                    "command": "run-calibration",
                    "aggregate": {"status": "successful"},
                }
            ),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}), encoding="utf-8"
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "report.json"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--out",
            ".copilot-tracking/accessibility/local-runs/2026-07-22/report.json",
            "--run-root",
            ".copilot-tracking/accessibility/local-runs/2026-07-22/custom-run",
            "--checkpoint-path",
            ".copilot-tracking/accessibility/local-runs/2026-07-22/custom-run/checkpoint.json",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    assert captured["env"]["RUNTIME_A11Y_RUN_ROOT"] == str(
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "custom-run"
    )
    assert captured["env"]["RUNTIME_A11Y_CHECKPOINT_PATH"] == str(
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "custom-run"
        / "checkpoint.json"
    )
    assert out_path.exists()


def test_given_calibration_run_when_run_root_is_outside_allowed_tree_then_rejects(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}), encoding="utf-8"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--run-root",
            "../outside",
        ]
    )

    assert exit_code == EXIT_USAGE


@pytest.mark.skipif(not hasattr(os, "symlink"), reason="symlink support required")
def test_given_calibration_run_when_checkpoint_path_uses_symlink_escape_then_rejects(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    allowed_root = tmp_path / ".copilot-tracking" / "accessibility" / "local-runs"
    allowed_root.mkdir(parents=True, exist_ok=True)
    outside_dir = tmp_path / "outside"
    outside_dir.mkdir(parents=True, exist_ok=True)
    link_path = allowed_root / "escaped"
    os.symlink(outside_dir, link_path)
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps({"baseUrl": "http://127.0.0.1:3000"}), encoding="utf-8"
    )

    exit_code = cli.main(
        [
            "run-calibration",
            "--config",
            str(config_path),
            "--checkpoint-path",
            str(link_path / "checkpoint.json"),
        ]
    )

    assert exit_code == EXIT_USAGE


def test_given_visual_review_server_when_process_becomes_ready_then_returns_it(
    mocker,
    tmp_path: Path,
) -> None:
    docs_dir = tmp_path / "docs" / "docusaurus"
    docs_dir.mkdir(parents=True, exist_ok=True)
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    mocker.patch("runtime_a11y.__main__._probe_visual_review_server", return_value=True)
    fake_process = SimpleNamespace(
        poll=lambda: None,
        terminate=lambda: None,
        wait=lambda timeout=None: None,
    )
    mocker.patch("runtime_a11y.__main__.subprocess.Popen", return_value=fake_process)

    process = cli._start_visual_review_server("http://127.0.0.1:3000")

    assert process is fake_process


def test_given_visual_review_server_when_stopping_then_terminates_owned_process(
    tmp_path: Path,
) -> None:
    class FakeProcess:
        def __init__(self) -> None:
            self.terminated = False
            self.wait_calls = 0

        def poll(self) -> None:
            return None

        def terminate(self) -> None:
            self.terminated = True

        def wait(self, timeout: int = 5) -> None:
            self.wait_calls += 1

    process = FakeProcess()

    cli._stop_visual_review_server(process)

    assert process.terminated is True
    assert process.wait_calls == 1


def test_given_visual_review_server_when_starting_then_reports_ownership(
    mocker,
    tmp_path: Path,
) -> None:
    docs_dir = tmp_path / "docs" / "docusaurus"
    docs_dir.mkdir(parents=True, exist_ok=True)
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    mocker.patch(
        "runtime_a11y.__main__._probe_visual_review_server",
        side_effect=[False, True],
    )
    fake_process = SimpleNamespace(
        poll=lambda: None,
        terminate=lambda: None,
        wait=lambda timeout=None: None,
    )
    mocker.patch("runtime_a11y.__main__.subprocess.Popen", return_value=fake_process)

    process, owned = cli._ensure_visual_review_server("http://127.0.0.1:3000")

    assert process is fake_process
    assert owned is True


def test_given_prerequisite_probe_when_node_modules_missing_then_returns_usage_error(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path / "missing")

    with pytest.raises(cli.ScriptError, match="Runtime probe dependencies"):
        cli._run_prerequisite_probe(
            {"baseUrl": "http://127.0.0.1:3000"},
            "http://127.0.0.1:3000",
        )


def test_given_calibration_session_when_node_modules_missing_then_returns_usage_error(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path / "missing")

    with pytest.raises(cli.ScriptError, match="Runtime probe dependencies"):
        cli._run_calibration_session(
            {"baseUrl": "http://127.0.0.1:3000"},
            "http://127.0.0.1:3000",
            None,
            None,
        )


def test_given_calibration_session_when_subprocess_returns_invalid_json_then_raises(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout="not-json", stderr=""),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)

    with pytest.raises(cli.ScriptError, match="invalid JSON output"):
        cli._run_calibration_session(
            {"baseUrl": "http://127.0.0.1:3000"},
            "http://127.0.0.1:3000",
            None,
            None,
        )


def test_given_visual_review_artifact_when_remote_path_then_rejects(
    tmp_path: Path,
) -> None:
    with pytest.raises(cli.ScriptError, match="relative for containment"):
        cli._materialize_visual_review_artifact(
            "https://example.com/artifact.png",
            run_root=tmp_path,
            manifest_dir=tmp_path / "manifest",
        )


def test_given_visual_review_server_when_probe_parsing_fails_then_returns_false(
    mocker,
) -> None:
    mocker.patch("runtime_a11y.__main__.urlparse", side_effect=ValueError("bad"))

    assert cli._probe_visual_review_server("http://127.0.0.1:3000") is False


def test_given_visual_review_server_when_startup_times_out_then_terminates_and_raises(
    mocker,
    tmp_path: Path,
) -> None:
    docs_dir = tmp_path / "docs" / "docusaurus"
    docs_dir.mkdir(parents=True, exist_ok=True)
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    mocker.patch(
        "runtime_a11y.__main__._probe_visual_review_server", return_value=False
    )
    values = iter([0.0, 0.0, 21.0, 21.0])
    mocker.patch(
        "runtime_a11y.__main__.time.monotonic", side_effect=lambda: next(values)
    )

    class FakeProcess:
        def __init__(self) -> None:
            self.terminated = False
            self.wait_calls = 0

        def poll(self) -> int | None:
            return None

        def terminate(self) -> None:
            self.terminated = True

        def wait(self, timeout: int = 5) -> None:
            self.wait_calls += 1

    process = FakeProcess()
    mocker.patch("runtime_a11y.__main__.subprocess.Popen", return_value=process)

    with pytest.raises(cli.ScriptError, match="did not become ready"):
        cli._start_visual_review_server("http://127.0.0.1:3000")

    assert process.terminated is True


def test_given_visual_review_capture_when_subprocess_succeeds_then_manifest_is_written(
    mocker,
    tmp_path: Path,
) -> None:
    payload = {
        "runs": [
            {
                "route": "/",
                "surface": "home",
                "state": "default",
                "viewport": {"width": 1440, "height": 900},
                "screenshotPath": "artifacts/screenshot.png",
                "measurementPath": "artifacts/measurements.json",
                "tracePath": "artifacts/trace.json",
                "deterministicMetrics": {"rootHorizontalOverflow": False},
                "probeOutcomes": [{"id": "clock", "status": "pass"}],
                "browser": {"name": "chrome", "version": "126.0"},
            }
        ]
    }
    run_root = tmp_path / "run-root"
    run_root.mkdir(parents=True, exist_ok=True)
    (run_root / "artifacts").mkdir(parents=True, exist_ok=True)
    (run_root / "artifacts" / "screenshot.png").write_bytes(b"image")
    (run_root / "artifacts" / "measurements.json").write_bytes(b"{}")
    (run_root / "artifacts" / "trace.json").write_bytes(b"{}")
    mocker.patch.object(cli, "resolve_run_root", return_value=run_root)
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        return_value=SimpleNamespace(stdout=json.dumps(payload), stderr=""),
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "visualReview": {
                    "enabled": True,
                    "evidenceRoot": str(tmp_path / "evidence"),
                },
            }
        ),
        encoding="utf-8",
    )
    out_path = (
        tmp_path
        / ".copilot-tracking"
        / "accessibility"
        / "local-runs"
        / "2026-07-22"
        / "visual-review.json"
    )

    exit_code = cli.main(
        ["capture-visual-review", "--config", str(config_path), "--out", str(out_path)]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["command"] == "capture-visual-review"
    assert document["manifestPaths"]
    assert document["runs"][0]["surface"] == "home"


def test_given_surface_and_state_filters_when_running_then_only_selected_runs_execute(
    mocker, tmp_path: Path
) -> None:
    collected: list[tuple[str, str, str]] = []

    def fake_run(command, capture_output, text, check, env, cwd):
        surface_id = env["RUNTIME_A11Y_SURFACE_ID"]
        state = env["RUNTIME_A11Y_STATE"]
        collected.append((surface_id, state, env["RUNTIME_A11Y_PROBE_ID"]))
        return SimpleNamespace(
            stdout=json.dumps({"probeId": env["RUNTIME_A11Y_PROBE_ID"], "results": []}),
            stderr="",
        )

    mocker.patch("runtime_a11y.__main__.subprocess.run", side_effect=fake_run)
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "a11y-runtime.config.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "surfaces": [
                    {"id": "web", "route": "/", "states": [{"state": "default"}]},
                    {"id": "search", "route": "/search", "states": [{"state": "open"}]},
                ],
                "probeScoping": [
                    {
                        "probe": "probe-axe",
                        "surfaces": ["web", "search"],
                        "states": ["default", "open"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(
        [
            "run-all",
            "--config",
            str(config_path),
            "--surface",
            "search",
            "--state",
            "open",
        ]
    )

    assert exit_code == EXIT_SUCCESS
    assert collected == [("search", "open", "probe-axe")]


def test_given_visual_review_capture_when_disabled_then_returns_usage_error(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {"baseUrl": "http://127.0.0.1:3000", "visualReview": {"enabled": False}}
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(["capture-visual-review", "--config", str(config_path)])

    assert exit_code == EXIT_USAGE


def test_given_absolute_visual_review_artifact_path_when_materializing_then_rejects(
    tmp_path: Path,
) -> None:
    with pytest.raises(cli.ScriptError, match="containment"):
        cli._materialize_visual_review_artifact(
            "/tmp/escape.png",
            run_root=tmp_path,
            manifest_dir=tmp_path / "manifest",
        )


def test_given_absolute_artifact_under_run_root_when_materializing_then_copies(
    tmp_path: Path,
) -> None:
    run_root = tmp_path / "run-root"
    manifest_dir = tmp_path / "manifest"
    source_path = run_root / "artifacts" / "screenshot.png"
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_bytes(b"image")

    relative_path = cli._materialize_visual_review_artifact(
        str(source_path),
        run_root=run_root,
        manifest_dir=manifest_dir,
    )

    assert relative_path == "artifacts/screenshot.png"
    assert (manifest_dir / "artifacts" / "screenshot.png").exists()


def test_given_visual_review_selection_with_unknown_values_when_validating_then_rejects(
    tmp_path: Path,
) -> None:
    config = {
        "baseUrl": "http://127.0.0.1:3000",
        "visualReview": {
            "enabled": True,
            "routes": [{"path": "/", "surfaceId": "home"}],
            "states": ["desktop", "reflow-320"],
        },
    }

    with pytest.raises(cli.ScriptError, match="surface"):
        cli._select_visual_review_plan(config, surfaces=["missing"], states=["desktop"])

    with pytest.raises(cli.ScriptError, match="state"):
        cli._select_visual_review_plan(config, surfaces=["home"], states=["unknown"])

    selected = cli._select_visual_review_plan(
        config, surfaces=["home"], states=["desktop"]
    )
    assert selected["surfaces"] == ["home"]
    assert selected["states"] == ["desktop"]


def test_given_existing_healthy_server_when_enforcing_then_leaves_it_untouched(
    mocker,
) -> None:
    probe = mocker.patch(
        "runtime_a11y.__main__._probe_visual_review_server", return_value=True
    )
    start = mocker.patch("runtime_a11y.__main__._start_visual_review_server")

    process, owned = cli._ensure_visual_review_server("http://127.0.0.1:3000")

    assert process is None
    assert owned is False
    probe.assert_called_once()
    start.assert_not_called()


def test_given_capture_when_subprocess_is_unavailable_then_returns_usage_error(
    mocker,
    tmp_path: Path,
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        side_effect=FileNotFoundError("node"),
    )
    config_path = tmp_path / "runtime.json"
    config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "visualReview": {
                    "enabled": True,
                    "evidenceRoot": str(tmp_path / "evidence"),
                },
            }
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(["capture-visual-review", "--config", str(config_path)])

    assert exit_code == EXIT_USAGE


def test_given_visual_review_server_probe_when_host_is_invalid_then_returns_false() -> (
    None
):
    assert cli._probe_visual_review_server("ftp://example.com") is False
    assert cli._probe_visual_review_server("http://example.com") is False


def test_given_visual_review_server_start_when_docs_dir_is_missing_then_raises(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(cli, "_REPO_ROOT", tmp_path)

    with pytest.raises(cli.ScriptError, match="docs/docusaurus"):
        cli._start_visual_review_server("http://127.0.0.1:3000")


def test_given_visual_review_server_start_when_process_exits_before_ready_then_raises(
    mocker, tmp_path: Path
) -> None:
    docs_dir = tmp_path / "docs" / "docusaurus"
    docs_dir.mkdir(parents=True, exist_ok=True)
    mocker.patch.object(cli, "_REPO_ROOT", tmp_path)
    mocker.patch(
        "runtime_a11y.__main__._probe_visual_review_server", return_value=False
    )
    mocker.patch(
        "runtime_a11y.__main__.subprocess.Popen",
        return_value=SimpleNamespace(poll=lambda: 1),
    )

    with pytest.raises(cli.ScriptError, match="exited before"):
        cli._start_visual_review_server("http://127.0.0.1:3000")


def test_given_capture_failure_run_when_writing_manifests_then_skips_it(
    tmp_path: Path,
) -> None:
    payload = {
        "runs": [
            {
                "route": "/",
                "surface": "home",
                "state": "default",
                "probeOutcomes": [{"status": "capture-failure"}],
            }
        ]
    }

    manifest_paths = cli._write_visual_review_manifests(payload, tmp_path)

    assert manifest_paths == []


def test_given_artifact_bytes_ceiling_when_writing_manifests_then_raises(
    tmp_path: Path,
) -> None:
    run_root = tmp_path / "run-root"
    artifacts_dir = run_root / "artifacts"
    artifacts_dir.mkdir(parents=True, exist_ok=True)
    (artifacts_dir / "screenshot.png").write_bytes(b"abc")
    (artifacts_dir / "measurements.json").write_bytes(b"{}")
    (artifacts_dir / "trace.json").write_bytes(b"{}")
    payload = {
        "runs": [
            {
                "route": "/",
                "surface": "home",
                "state": "default",
                "screenshotPath": "artifacts/screenshot.png",
                "measurementPath": "artifacts/measurements.json",
                "tracePath": "artifacts/trace.json",
                "probeOutcomes": [],
                "viewport": {"width": 1440, "height": 900},
                "browser": {"name": "chrome", "version": "126"},
                "deterministicMetrics": {},
            }
        ]
    }

    with pytest.raises(cli.ScriptError, match="byte ceiling"):
        cli._write_visual_review_manifests(payload, run_root, max_artifact_bytes=1)


def test_given_case_navigation_triggers_when_asserting_urls_then_accepts_them() -> None:
    cli._assert_case_urls_allowed(
        {"baseUrl": "http://127.0.0.1:3000"},
        {"route": "/home"},
        {"action": "navigate", "value": "/next"},
        allow_external=False,
    )
    cli._assert_case_urls_allowed(
        {"baseUrl": "http://127.0.0.1:3000"},
        None,
        {"action": "visit", "target": {"value": "/visit"}},
        allow_external=False,
    )


def test_given_run_at_plan_without_eligible_variants_when_forcing_then_executes(
    mocker,
    tmp_path: Path,
) -> None:
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                    }
                ],
                "surfaces": [
                    {
                        "id": "dialog",
                        "name": "Dialog",
                        "platform": "web",
                        "widgetPattern": "dialog-modal",
                        "states": ["open"],
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "dialog",
                        "state": "open",
                        "status": "partial",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    mocker.patch(
        "runtime_a11y.__main__._run_at_plan_case",
        return_value={"caseId": "manual-4-1-2-dialog-open", "status": "ok"},
    )

    exit_code = cli.main(
        ["run-at-plan", "--matrix", str(matrix_path), "--driver", "synthetic"]
    )

    assert exit_code == EXIT_SUCCESS


def test_given_runtime_config_when_deriving_cases_then_context_is_sanitized(
    tmp_path: Path,
) -> None:
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        (
            Path(__file__).parent / "fixtures" / "aria-at-modal-dialog-matrix.json"
        ).read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    runtime_config_path = tmp_path / "runtime.json"
    runtime_config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "privateKey": "shh",
                "realScreenReader": {"token": "do-not-forward"},
                "surfaces": [
                    {
                        "id": "dialog",
                        "route": "/dialog",
                        "selector": {"kind": "css", "value": "#dialog"},
                        "states": [
                            {
                                "state": "open",
                                "trigger": {
                                    "action": "click",
                                    "target": {"kind": "css", "value": "#open"},
                                },
                            }
                        ],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    cases = cli._derive_at_plan_cases(matrix_path, runtime_config_path)

    assert cases
    case = next(item for item in cases if item["surfaceId"] == "dialog")
    assert case["baseUrl"] == "http://127.0.0.1:3000"
    assert case["surface"]["id"] == "dialog"
    assert case["surface"]["route"] == "/dialog"
    assert case["surface"]["selector"] == {"kind": "css", "value": "#dialog"}
    assert case["trigger"]["action"] == "click"
    assert case["trigger"]["target"] == {"kind": "css", "value": "#open"}
    assert "privateKey" not in case["runtimeConfig"]
    assert case["runtimeConfig"] == {"baseUrl": "http://127.0.0.1:3000"}


def test_given_external_surface_route_when_deriving_cases_then_target_is_blocked(
    tmp_path: Path,
) -> None:
    # Arrange
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        (
            Path(__file__).parent / "fixtures" / "aria-at-modal-dialog-matrix.json"
        ).read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    runtime_config_path = tmp_path / "runtime.json"
    runtime_config_path.write_text(
        json.dumps(
            {
                "baseUrl": "http://127.0.0.1:3000",
                "surfaces": [
                    {
                        "id": "dialog",
                        "route": "https://example.com/dialog",
                        "states": [{"state": "open"}],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    # Act & Assert
    with pytest.raises(cli.ScriptError, match="Refusing to probe"):
        cli._derive_at_plan_cases(matrix_path, runtime_config_path)

    cases = cli._derive_at_plan_cases(
        matrix_path,
        runtime_config_path,
        allow_external=True,
    )
    case = cases[0]
    assert case["surface"]["route"] == "https://example.com/dialog"
    assert case["sourceMatrixRef"] == matrix_path.name
    assert case["sourceMatrixMetadata"]["path"] == matrix_path.name


def test_given_probe_command_when_subprocess_fails_then_returns_usage_error(
    mocker, tmp_path: Path
) -> None:
    mocker.patch(
        "runtime_a11y.__main__.subprocess.run",
        side_effect=FileNotFoundError("node"),
    )
    mocker.patch.object(cli, "_NODE_MODULES", tmp_path)
    config_path = tmp_path / "a11y-runtime.config.json"
    config_path.write_text(
        '{"baseUrl": "http://127.0.0.1:3000", "surfaces": '
        '[{"id": "web", "type": "page"}]}',
        encoding="utf-8",
    )

    exit_code = cli.main(["probe", "probe-axe", "--config", str(config_path)])

    assert exit_code == EXIT_USAGE


def test_given_external_target_without_allowlist_when_run_all_then_returns_usage_error(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "a11y-runtime.config.json"
    config_path.write_text(
        '{"baseUrl": "https://example.com", '
        '"surfaces": [{"id": "web", "type": "page"}]}',
        encoding="utf-8",
    )

    exit_code = cli.main(["run-all", "--config", str(config_path)])

    assert exit_code == EXIT_USAGE


def test_given_matrix_document_when_rendering_artifacts_then_bundle_is_written(
    tmp_path: Path, capsys
) -> None:
    # Arrange
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
                "surfaces": [
                    {
                        "id": "search",
                        "name": "Search",
                        "platform": "web",
                        "states": ["open"],
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "search",
                        "state": "open",
                        "status": "partial",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    output_dir = tmp_path / "artifacts"

    # Act
    exit_code = cli.main(
        [
            "render-artifacts",
            "--matrix",
            str(matrix_path),
            "--output-dir",
            str(output_dir),
            "--repo-slug",
            "octo/repo",
        ]
    )

    # Assert
    summary = json.loads(capsys.readouterr().out)
    assert exit_code == EXIT_SUCCESS
    assert summary["command"] == "render-artifacts"
    assert (output_dir / "accessibility-artifacts-octo-repo.json").exists()
    assert (output_dir / "accessibility-results-octo-repo.earl.jsonld").exists()


def test_given_runtime_config_file_when_rendering_artifacts_then_it_is_used(
    tmp_path: Path, capsys
) -> None:
    # Arrange
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                    }
                ],
                "surfaces": [
                    {
                        "id": "dialog",
                        "name": "Dialog",
                        "platform": "web",
                        "states": ["open"],
                        "widgetPattern": "dialog-modal",
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "dialog",
                        "state": "open",
                        "status": "unknown",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    runtime_config_path = tmp_path / "runtime.json"
    runtime_config_path.write_text(
        json.dumps(
            {
                "surfaces": [
                    {
                        "id": "dialog",
                        "widgetPattern": "dialog-modal",
                        "states": [{"state": "open"}],
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    output_dir = tmp_path / "artifacts"

    # Act
    exit_code = cli.main(
        [
            "render-artifacts",
            "--matrix",
            str(matrix_path),
            "--output-dir",
            str(output_dir),
            "--repo-slug",
            "octo/repo",
            "--runtime-config",
            str(runtime_config_path),
        ]
    )

    # Assert
    assert exit_code == EXIT_SUCCESS
    summary = json.loads(capsys.readouterr().out)
    assert summary["artifacts"]["manualTestPlanMarkdown"].endswith(
        "manual-at-testplan-octo-repo.md"
    )


@pytest.mark.parametrize(
    "payload",
    [
        "not-json",
        '{"criteria": [], "surfaces": [], "cells": []}',
    ],
)
def test_given_invalid_matrix_when_rendering_artifacts_then_returns_usage_error(
    tmp_path: Path, payload: str
) -> None:
    # Arrange
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(payload, encoding="utf-8")

    # Act
    exit_code = cli.main(
        [
            "render-artifacts",
            "--matrix",
            str(matrix_path),
            "--output-dir",
            str(tmp_path / "out"),
            "--repo-slug",
            "octo/repo",
        ]
    )

    # Assert
    assert exit_code == EXIT_USAGE


def test_given_run_at_plan_when_listing_cases_then_uses_matrix_without_runtime_config(
    tmp_path: Path,
) -> None:
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                    }
                ],
                "surfaces": [
                    {
                        "id": "dialog",
                        "name": "Dialog",
                        "platform": "web",
                        "widgetPattern": "dialog-modal",
                        "states": ["open"],
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "dialog",
                        "state": "open",
                        "status": "partial",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(["run-at-plan", "--matrix", str(matrix_path), "--list"])

    assert exit_code == EXIT_SUCCESS


def test_given_run_at_plan_when_case_is_unknown_then_returns_usage_error(
    tmp_path: Path,
) -> None:
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                    }
                ],
                "surfaces": [
                    {
                        "id": "dialog",
                        "name": "Dialog",
                        "platform": "web",
                        "widgetPattern": "dialog-modal",
                        "states": ["open"],
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "dialog",
                        "state": "open",
                        "status": "partial",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    exit_code = cli.main(
        ["run-at-plan", "--matrix", str(matrix_path), "--case-id", "missing"]
    )

    assert exit_code == EXIT_USAGE


def test_given_run_at_plan_when_target_is_external_then_requires_allow_external(
    tmp_path: Path,
) -> None:
    matrix_path = tmp_path / "matrix.json"
    matrix_path.write_text(
        json.dumps(
            {
                "criteria": [
                    {
                        "id": "4.1.2",
                        "framework": "wcag-22",
                        "title": "Name, Role, Value",
                    }
                ],
                "surfaces": [
                    {
                        "id": "dialog",
                        "name": "Dialog",
                        "platform": "web",
                        "widgetPattern": "dialog-modal",
                        "states": ["open"],
                    }
                ],
                "cells": [
                    {
                        "criterionId": "4.1.2",
                        "surfaceId": "dialog",
                        "state": "open",
                        "status": "partial",
                        "adequateMethods": ["screen-reader"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps({"baseUrl": "https://example.com", "surfaces": []}),
        encoding="utf-8",
    )

    exit_code = cli.main(
        [
            "run-at-plan",
            "--matrix",
            str(matrix_path),
            "--config",
            str(config_path),
            "--case-id",
            "manual-4-1-2-dialog-open",
        ]
    )

    assert exit_code == EXIT_USAGE
