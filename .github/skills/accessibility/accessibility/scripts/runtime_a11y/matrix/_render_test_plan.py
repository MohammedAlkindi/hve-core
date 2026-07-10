# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT

"""Render manual accessibility test plans from unresolved matrix cells."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from runtime_a11y.matrix._model import Cell, Matrix
from runtime_a11y.matrix._render_md import (
    ACCESSIBILITY_DISCLAIMER,
    HUMAN_REVIEW_CHECKBOX,
)

_HUMAN_METHOD_PRIORITY = (
    "screen-reader",
    "manual-keyboard",
    "cognitive-walkthrough",
)


def _token(*parts: str) -> str:
    value = "-".join(parts).lower()
    return re.sub(r"[^a-z0-9]+", "-", value).strip("-") or "unknown"


def _recommended_method(cell: Cell) -> str | None:
    for method in _HUMAN_METHOD_PRIORITY:
        if method in cell.adequateMethods:
            return method
    return None


def build_manual_test_cases(matrix: Matrix) -> list[dict[str, Any]]:
    """Build unresolved cases that require a human-deciding method."""
    criterion_by_id = {criterion.id: criterion for criterion in matrix.criteria}
    surface_by_id = {surface.id: surface for surface in matrix.surfaces}
    cases: list[dict[str, Any]] = []

    for cell in matrix.cells:
        method = _recommended_method(cell)
        adequately_passed = (
            cell.status == "pass"
            and cell.verifiedByMethod is not None
            and cell.verifiedByMethod in cell.adequateMethods
        )
        if not cell.isApplicable or method is None or adequately_passed:
            continue

        criterion = criterion_by_id.get(cell.criterionId)
        surface = surface_by_id.get(cell.surfaceId)
        cases.append(
            {
                "id": f"manual-{_token(cell.criterionId, cell.surfaceId, cell.state)}",
                "criterionId": cell.criterionId,
                "framework": criterion.framework if criterion else "unknown",
                "criterionTitle": criterion.title if criterion else cell.criterionId,
                "surfaceId": cell.surfaceId,
                "surfaceName": surface.name if surface else cell.surfaceId,
                "platform": surface.platform if surface else "unknown",
                "state": cell.state,
                "currentStatus": cell.status,
                "recommendedMethod": method,
                "adequateMethods": sorted(cell.adequateMethods),
                "rationale": cell.rationale or "",
                "evidence": cell.evidence or "",
                "steps": [
                    f"Open the {surface.name if surface else cell.surfaceId} surface.",
                    f"Place the surface in the {cell.state} state.",
                    f"Evaluate the surface using {method}.",
                    "Record the observed result and evidence reference.",
                ],
                "expectedResult": (
                    f"The {criterion.title if criterion else cell.criterionId} "
                    "requirement is satisfied in this surface and state."
                ),
            }
        )

    return sorted(
        cases,
        key=lambda item: (
            item["framework"],
            item["criterionId"],
            item["surfaceId"],
            item["state"],
        ),
    )


def render_manual_test_plan_markdown(
    matrix: Matrix, out_path: Path, repo_slug: str
) -> None:
    """Write a human-readable manual accessibility test plan."""
    cases = build_manual_test_cases(matrix)
    lines = [
        "<!-- markdownlint-disable-file -->",
        "# Manual Accessibility Test Plan",
        "",
        ACCESSIBILITY_DISCLAIMER,
        "",
        HUMAN_REVIEW_CHECKBOX,
        "",
        f"- Repository: {repo_slug}",
        f"- Pending manual cases: {len(cases)}",
        "",
        "## Execution Rules",
        "",
        "* A qualified tester records observed output and an evidence URI.",
        "* A test result does not update matrix coverage until the evidence "
        "is ingested.",
        "* JAWS, braille, and cognitive outcomes remain human-decided.",
        "",
        "## Test Cases",
        "",
    ]
    if not cases:
        lines.extend(["* None", ""])
    for case in cases:
        lines.extend(
            [
                f"### {case['id']}",
                "",
                f"* Criterion: {case['framework']} {case['criterionId']} "
                f"({case['criterionTitle']})",
                f"* Surface: {case['surfaceName']} ({case['surfaceId']})",
                f"* Platform: {case['platform']}",
                f"* State: {case['state']}",
                f"* Current status: {case['currentStatus']}",
                f"* Recommended method: {case['recommendedMethod']}",
                "",
                "#### Steps",
                "",
            ]
        )
        lines.extend(
            f"{index}. {step}" for index, step in enumerate(case["steps"], start=1)
        )
        lines.extend(
            [
                "",
                "#### Expected Result",
                "",
                case["expectedResult"],
                "",
                "#### Result Record",
                "",
                "* Outcome: Not run",
                "* Observed result:",
                "* Evidence URI:",
                "* Tester:",
                "* Test date:",
                "",
            ]
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")


def _yaml_scalar(value: Any) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    return json.dumps(value, ensure_ascii=False)


def render_manual_test_plan_yaml(
    matrix: Matrix, out_path: Path, repo_slug: str
) -> None:
    """Write the machine-readable manual accessibility test plan as YAML."""
    cases = build_manual_test_cases(matrix)
    lines = [
        "version: 1",
        f"repository: {_yaml_scalar(repo_slug)}",
        "review:",
        "  required: true",
        "  completed: false",
        "cases:",
    ]
    if not cases:
        lines[-1] = "cases: []"
    for case in cases:
        lines.extend(
            [
                f"  - id: {_yaml_scalar(case['id'])}",
                f"    criterionId: {_yaml_scalar(case['criterionId'])}",
                f"    framework: {_yaml_scalar(case['framework'])}",
                f"    criterionTitle: {_yaml_scalar(case['criterionTitle'])}",
                f"    surfaceId: {_yaml_scalar(case['surfaceId'])}",
                f"    surfaceName: {_yaml_scalar(case['surfaceName'])}",
                f"    platform: {_yaml_scalar(case['platform'])}",
                f"    state: {_yaml_scalar(case['state'])}",
                f"    currentStatus: {_yaml_scalar(case['currentStatus'])}",
                f"    recommendedMethod: {_yaml_scalar(case['recommendedMethod'])}",
                "    adequateMethods:",
            ]
        )
        lines.extend(
            f"      - {_yaml_scalar(method)}" for method in case["adequateMethods"]
        )
        lines.append("    steps:")
        lines.extend(f"      - {_yaml_scalar(step)}" for step in case["steps"])
        lines.extend(
            [
                f"    expectedResult: {_yaml_scalar(case['expectedResult'])}",
                "    result:",
                '      outcome: "not-run"',
                '      observedResult: ""',
                '      evidenceUri: ""',
                '      tester: ""',
                '      testDate: ""',
            ]
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
