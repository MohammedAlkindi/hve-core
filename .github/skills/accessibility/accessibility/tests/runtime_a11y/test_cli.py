# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
import runtime_a11y.__main__ as cli
from runtime_a11y._errors import EXIT_SUCCESS, EXIT_USAGE


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
    out_path = tmp_path / "results.json"

    exit_code = cli.main(
        ["run-all", "--config", str(config_path), "--out", str(out_path)]
    )

    assert exit_code == EXIT_SUCCESS
    document = json.loads(out_path.read_text(encoding="utf-8"))
    assert document["tool"] == "runtime_a11y"
    assert document["results"][0]["criterionId"] == "1.3.1"
    assert document["runs"][0]["probeId"] == "probe-axe"


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
