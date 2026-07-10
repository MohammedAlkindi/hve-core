#!/usr/bin/env python3
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

"""CLI entry point for the runtime accessibility probe harness.

Subcommands:
    run-all   Run every scoped probe and aggregate the normalized results.
    probe     Run a single probe by id across its scoped surfaces and states.
    render-artifacts
              Render the coverage matrix, EARL report, manual test plans, and
              artifact manifest from a matrix JSON document.

The harness invokes the Playwright probes with the skill-local Node package under
``scripts/runtime_a11y`` (``package.json`` + ``package-lock.json``). Install the
dependencies once with ``npm ci`` in that directory; the probes then resolve
Playwright, axe-core, and the virtual screen reader from the local
``node_modules``. Config is passed to the Node runner through environment
variables. Exit code is 0 on a completed run even when findings exist; a non-zero
exit signals a harness error (bad config, missing dependencies, missing Node or
browser, or a blocked target).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

from runtime_a11y._config import load_validated_config
from runtime_a11y._errors import EXIT_SUCCESS, EXIT_USAGE, ScriptError
from runtime_a11y.matrix import Matrix, compute_coverage, render_artifact_bundle

_PACKAGE_DIR = Path(__file__).resolve().parent
_RUNNER_INDEX = _PACKAGE_DIR / "runner" / "index.mjs"
_PROBE_MAP_PATH = _PACKAGE_DIR / "probe-criteria-map.json"
_NODE_MODULES = _PACKAGE_DIR / "node_modules"


def _all_probe_ids() -> list[str]:
    payload = json.loads(_PROBE_MAP_PATH.read_text(encoding="utf-8"))
    return [probe["probeId"] for probe in payload.get("probes", [])]


def _normalize_probe_id(name: str, known: set[str]) -> str | None:
    """Resolve a config probe name to a known runner probe id, or None."""
    if name in known:
        return name
    prefixed = name if name.startswith("probe-") else f"probe-{name}"
    if prefixed in known:
        return prefixed
    matches = [pid for pid in known if name in pid]
    return matches[0] if len(matches) == 1 else None


def _iter_runs(
    config: dict[str, Any], probe_filter: str | None = None
) -> Iterator[tuple[str, str, str]]:
    """Yield (probeId, surfaceId, state) combinations to execute."""
    known = set(_all_probe_ids())
    surfaces = {s["id"]: s for s in config.get("surfaces", []) if "id" in s}
    scoping = config.get("probeScoping") or []
    if scoping:
        for entry in scoping:
            probe = _normalize_probe_id(str(entry.get("probe", "")), known)
            if probe is None:
                continue
            if probe_filter and probe != probe_filter:
                continue
            surface_ids = entry.get("surfaces") or list(surfaces)
            states = entry.get("states") or ["default"]
            for sid in surface_ids:
                for state in states:
                    yield probe, sid, state
        return
    probes = [probe_filter] if probe_filter else sorted(known)
    for probe in probes:
        for sid, surface in surfaces.items():
            states = [st.get("state") for st in surface.get("states", [])] or [
                "default"
            ]
            for state in states:
                yield probe, sid, state


def _run_probe(
    config: dict[str, Any],
    probe_id: str,
    surface_id: str,
    state: str,
    base_url: str,
    trace: bool,
) -> dict[str, Any]:
    """Invoke the Node runner for one probe/surface/state and parse its JSON."""
    if not _NODE_MODULES.exists():
        raise ScriptError(
            "Runtime probe dependencies are not installed. Run 'npm ci' in "
            f"{_PACKAGE_DIR} to install Playwright, axe-core, and the virtual "
            "screen reader before running the harness.",
            EXIT_USAGE,
        )
    command = [
        "node",
        str(_RUNNER_INDEX),
        probe_id,
    ]
    env = {
        **os.environ,
        "RUNTIME_A11Y_CONFIG": json.dumps(config),
        "RUNTIME_A11Y_PROBE_ID": probe_id,
        "RUNTIME_A11Y_SURFACE_ID": surface_id,
        "RUNTIME_A11Y_STATE": state,
        "RUNTIME_A11Y_BASE_URL": base_url,
        "RUNTIME_A11Y_TRACE": "1" if trace else "0",
    }
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=True,
            env=env,
            cwd=str(_PACKAGE_DIR),
        )
    except FileNotFoundError as exc:
        raise ScriptError(
            "Node is unavailable. Install Node.js and system Google Chrome, then "
            f"run 'npm ci' in {_PACKAGE_DIR}, to run runtime probes.",
            EXIT_USAGE,
        ) from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip() or "No probe output captured"
        raise ScriptError(
            f"Probe '{probe_id}' failed for surface '{surface_id}' "
            f"state '{state}': {stderr}"
        ) from exc

    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise ScriptError(f"Probe '{probe_id}' returned invalid JSON output") from exc


def run(
    config: dict[str, Any],
    probe_filter: str | None,
    base_url: str,
    trace: bool,
) -> dict[str, Any]:
    """Execute the scoped runs and aggregate normalized probe results."""
    runs: list[dict[str, Any]] = []
    results: list[dict[str, Any]] = []
    for probe_id, surface_id, state in _iter_runs(config, probe_filter):
        payload = _run_probe(config, probe_id, surface_id, state, base_url, trace)
        runs.append(
            {
                "probeId": payload.get("probeId", probe_id),
                "surfaceId": surface_id,
                "state": state,
            }
        )
        for item in payload.get("results", []):
            results.append(item)
    return {
        "tool": "runtime_a11y",
        "runAt": datetime.now(timezone.utc).isoformat(),
        "baseUrl": base_url,
        "runs": runs,
        "results": results,
    }


def _write_output(document: dict[str, Any], out_path: Path | None) -> None:
    payload = json.dumps(document, indent=2)
    if out_path is None:
        print(payload)
        return
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(payload + "\n", encoding="utf-8")


def _render_artifacts(
    matrix_path: Path, output_dir: Path, repo_slug: str
) -> dict[str, Any]:
    """Load a matrix document and render its canonical evidence bundle."""
    try:
        payload = json.loads(matrix_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ScriptError(
            f"Unable to read matrix JSON from {matrix_path}: {exc}", EXIT_USAGE
        ) from exc

    matrix = Matrix.from_dict(payload)
    if not matrix.criteria or not matrix.surfaces:
        raise ScriptError(
            "Matrix JSON must contain non-empty criteria and surfaces arrays.",
            EXIT_USAGE,
        )
    coverage = payload.get("coverage") or compute_coverage(matrix)
    paths = render_artifact_bundle(matrix, coverage, output_dir, repo_slug)
    return {
        "tool": "runtime_a11y",
        "command": "render-artifacts",
        "repository": repo_slug,
        "manifest": str(paths.manifest_json),
        "artifacts": paths.relative_manifest(output_dir),
    }


def create_parser() -> argparse.ArgumentParser:
    """Create and configure the argument parser."""
    parser = argparse.ArgumentParser(
        prog="runtime_a11y",
        description="Run project-parameterized accessibility runtime probes.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    def _add_common(sub: argparse.ArgumentParser) -> None:
        sub.add_argument(
            "--config",
            type=Path,
            required=True,
            help="Path to a11y-runtime.config.json",
        )
        sub.add_argument(
            "--out",
            type=Path,
            default=None,
            help="Path to write the aggregated results JSON (defaults to stdout)",
        )
        sub.add_argument(
            "--base-url",
            default=None,
            help="Override the config baseUrl",
        )
        sub.add_argument(
            "--trace",
            action="store_true",
            help="Capture Playwright traces and screenshots for each run",
        )
        sub.add_argument(
            "--allow-external",
            action="store_true",
            help="Confirm intentional probing of a non-loopback host",
        )

    run_all = subparsers.add_parser("run-all", help="Run every scoped probe")
    _add_common(run_all)

    probe = subparsers.add_parser("probe", help="Run a single probe by id")
    probe.add_argument("probe_id", help="Probe id, e.g. probe-axe")
    _add_common(probe)

    render = subparsers.add_parser(
        "render-artifacts",
        help="Render coverage, EARL, and manual test-plan artifacts",
    )
    render.add_argument("--matrix", type=Path, required=True)
    render.add_argument("--output-dir", type=Path, required=True)
    render.add_argument("--repo-slug", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "render-artifacts":
            document = _render_artifacts(args.matrix, args.output_dir, args.repo_slug)
            _write_output(document, None)
            return EXIT_SUCCESS
        config = load_validated_config(args.config, allow_external=args.allow_external)
        base_url = args.base_url or config.get("baseUrl", "")
        probe_filter = getattr(args, "probe_id", None)
        document = run(config, probe_filter, base_url, args.trace)
    except ScriptError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return exc.exit_code

    _write_output(document, args.out)
    return EXIT_SUCCESS


if __name__ == "__main__":
    sys.exit(main())
