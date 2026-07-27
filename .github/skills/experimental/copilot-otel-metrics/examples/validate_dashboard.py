#!/usr/bin/env python3
# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Import the dashboard and confirm every panel query returns data.

A panel can resolve its datasource, raise no error, and still be empty because
the metric name is wrong. This runs each panel's query against the store so an
empty panel is distinguishable from a mistyped one.
"""

from __future__ import annotations

import base64
import json
import pathlib
import re
import time
import urllib.error
import urllib.parse
import urllib.request

GRAFANA = "http://localhost:3000"
PROM = "http://localhost:9090"
TEMPO = "http://localhost:3200"
AUTH = "Basic " + base64.b64encode(b"admin:admin").decode()
DASH = pathlib.Path(__file__).parent / "dashboards" / "copilot-otel.json"


def req(url: str, data: bytes | None = None, method: str = "GET") -> dict:
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", AUTH)
    if data:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=25) as resp:
        return json.load(resp)


dash = json.loads(DASH.read_text())
body = {"dashboard": dash, "overwrite": True, "folderId": 0, "message": "validated against live telemetry"}
res = req(f"{GRAFANA}/api/dashboards/db", json.dumps(body).encode(), "POST")
print(f"import: {res.get('status')}  ->  {GRAFANA}{res.get('url')}\n")

now = int(time.time())
print("=== panel query validation ===\n")
ok_count = empty_count = 0

for panel in dash["panels"]:
    if panel.get("type") == "row":
        print(f"-- {panel['title']}")
        continue
    ds = panel["datasource"]["type"]
    title = panel["title"]

    for target in panel.get("targets", []):
        expr = target.get("expr") or target.get("query", "")
        # substitute dashboard variables with match-all for validation
        expr_r = expr.replace("$model", ".*").replace("[$__range]", "[1h]")
        label = target.get("legendFormat", target["refId"])

        if ds == "prometheus":
            try:
                if target.get("instant"):
                    rows = req(f"{PROM}/api/v1/query?" + urllib.parse.urlencode({"query": expr_r}))["data"]["result"]
                else:
                    rows = req(
                        f"{PROM}/api/v1/query_range?"
                        + urllib.parse.urlencode({"query": expr_r, "start": now - 7200, "end": now, "step": "60"})
                    )["data"]["result"]
                n = len(rows)
            except urllib.error.HTTPError as exc:
                print(f"   [ERROR] {title:<44} {label:<28} {exc.read().decode()[:80]}")
                continue
        else:
            # A TraceQL metrics query aggregates span attributes over time and
            # uses a different endpoint than a search query.
            is_metrics = any(fn in expr_r for fn in ("rate()", "_over_time(", "quantile_over_time", "histogram_over_time"))
            try:
                if is_metrics:
                    res = req(
                        f"{TEMPO}/api/metrics/query_range?"
                        + urllib.parse.urlencode(
                            {"q": expr_r, "start": (now - 7200) * 10**9, "end": now * 10**9, "step": "5m"}
                        )
                    )
                    rows = [s for s in (res.get("series") or []) if s.get("samples")]
                else:
                    # Tempo search returns nothing without explicit bounds; Grafana always sends them.
                    rows = req(
                        f"{TEMPO}/api/search?"
                        + urllib.parse.urlencode(
                            {"q": expr_r, "limit": "20", "start": now - 7200, "end": now}
                        )
                    ).get("traces") or []
                n = len(rows)
            except urllib.error.HTTPError as exc:
                print(f"   [ERROR] {title:<44} {label:<28} {exc.code} {exc.read().decode()[:70]}")
                continue
            except Exception as exc:  # noqa: BLE001
                print(f"   [ERROR] {title:<44} {label:<28} {exc}")
                continue

        if n:
            ok_count += 1
            print(f"   [DATA ] {title:<44} {label:<28} {n} series/traces")
        else:
            empty_count += 1
            # distinguish "metric absent" from "metric present but no samples in window"
            metrics = set(re.findall(r"\b([a-z_][a-z0-9_]*(?:_total|_sum|_count|_bucket))\b", expr_r))
            missing = []
            if ds == "prometheus" and metrics:
                names = req(f"{PROM}/api/v1/label/__name__/values")["data"]
                missing = sorted(m for m in metrics if m not in names)
            reason = f"metric name absent: {missing}" if missing else "no samples in window"
            print(f"   [EMPTY] {title:<44} {label:<28} {reason}")

print(f"\nqueries with data: {ok_count}   empty: {empty_count}")
