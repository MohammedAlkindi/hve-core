# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Static checks over the local stack configuration shipped with this skill.

These tests parse the committed Compose and Collector documents and simulate the
declared attribute policy. They never start a container and never assert that a
running Collector behaves as configured; they assert only that the configuration
this skill ships declares the intended policy.
"""

from __future__ import annotations

import json
import pathlib
import re
from dataclasses import dataclass
from typing import Any

import pytest
import yaml

SKILL_ROOT = pathlib.Path(__file__).resolve().parents[1]
EXAMPLES_DIR = SKILL_ROOT / "examples"
COMPOSE_PATH = EXAMPLES_DIR / "compose.yaml"
COLLECTOR_PATH = EXAMPLES_DIR / "otel-collector-local.yaml"
DASHBOARD_PATH = EXAMPLES_DIR / "dashboards" / "copilot-otel.json"
BASELINE_PATH = EXAMPLES_DIR / "baseline.py"

MASK = "****"
SCRUB = "[redacted]"

DIGEST_REFERENCE = re.compile(r"^[^\s@]+@sha256:[0-9a-f]{64}$")

# --- Shipped-consumer derivation -------------------------------------------
#
# The default disposition for a carrier the Collector does not govern is to
# scrub it. The only thing that earns an exception is a shipped consumer that
# reads it, so the consumer set has to be derived from the shipped artifacts
# rather than curated by hand. A hand-curated set cannot notice a newly
# required attribute, and a scrub decision made against a stale set breaks a
# panel silently.

# Label names Prometheus reserves or Grafana generates. Excluded by rule, not
# by listing the ones this dashboard happens to use today.
PROMETHEUS_RESERVED_LABELS = frozenset({"le", "quantile", "__name__", "job", "instance"})

# A metric reference is an identifier immediately followed by a label matcher
# or a range selector. A function is followed by "(", so this separates the two
# without enumerating PromQL's function set.
PROMQL_METRIC = re.compile(r"\b([a-z_][a-z0-9_]*)\s*[{\[]")
# Grafana resolves label_values(metric, label): metric first, label second.
PROMQL_LABEL_VALUES = re.compile(
    r"label_values\(\s*([a-z_][a-z0-9_]*)\s*,\s*([a-z_][a-z0-9_]*)\s*\)"
)
PROMQL_GROUPING = re.compile(r"\b(?:by|without)\s*\(([^)]*)\)")
PROMQL_MATCHER = re.compile(r"([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:=~|!~|=|!=)\s*\"")
# baseline.py reads label values directly rather than through a panel. Its
# reads are consumers too; leaving them out of the inventory is how a detection
# control gets scrubbed without anything noticing.
BASELINE_LABEL_READ = re.compile(r"label_values\(\s*\"([a-z_][a-z0-9_]*)\"\s*\)")

# TraceQL. The lookbehind keeps `service.name=` and `mode_name !=` from
# reading as span-name matchers; only a bare `name` is the intrinsic.
TRACEQL_SPAN_NAME = re.compile(r"(?<![\w.])name\s*(?:=~|!~|=|!=)\s*\"([^\"]*)\"")
TRACEQL_ATTRIBUTE = re.compile(r"\b(span|resource)\.([A-Za-z_][A-Za-z0-9_.]*)")


@dataclass(frozen=True)
class ShippedConsumers:
    """Everything the shipped artifacts read out of stored telemetry."""

    metric_names: frozenset[str]
    prometheus_labels: frozenset[str]
    span_name_matchers: tuple[str, ...]
    span_attributes: frozenset[str]
    resource_attributes: frozenset[str]
    trace_fields: frozenset[str]

    def protected_attribute_keys(self) -> frozenset[str]:
        """OTLP attribute keys a shipped consumer reads by their real name."""
        return self.span_attributes | self.resource_attributes


def _promql_labels(expr: str) -> set[str]:
    labels: set[str] = set()
    for clause in PROMQL_GROUPING.findall(expr):
        labels.update(part.strip() for part in clause.split(",") if part.strip())
    labels.update(PROMQL_MATCHER.findall(expr))
    return labels


def shipped_consumers() -> ShippedConsumers:
    """Derive the consumer inventory from the dashboard and the baseline helper."""
    dashboard = json.loads(DASHBOARD_PATH.read_text(encoding="utf-8"))

    metric_names: set[str] = set()
    labels: set[str] = set()
    span_names: list[str] = []
    span_attributes: set[str] = set()
    resource_attributes: set[str] = set()

    for variable in dashboard.get("templating", {}).get("list", []):
        query = variable.get("query")
        if isinstance(query, str):
            for metric, label in PROMQL_LABEL_VALUES.findall(query):
                metric_names.add(metric)
                labels.add(label)

    for panel in dashboard.get("panels", []):
        if panel.get("type") == "row":
            continue
        source = panel.get("datasource", {}).get("type")
        for target in panel.get("targets", []):
            expr = target.get("expr") or target.get("query") or ""
            if source == "prometheus":
                metric_names.update(PROMQL_METRIC.findall(expr))
                labels.update(_promql_labels(expr))
            elif source == "tempo":
                span_names.extend(TRACEQL_SPAN_NAME.findall(expr))
                for scope, key in TRACEQL_ATTRIBUTE.findall(expr):
                    target_set = span_attributes if scope == "span" else resource_attributes
                    target_set.add(key.rstrip("."))

    # A `$name` token is a Grafana template variable, not a stored label.
    labels = {label for label in labels if not label.startswith("$")}

    baseline_source = BASELINE_PATH.read_text(encoding="utf-8")
    labels.update(BASELINE_LABEL_READ.findall(baseline_source))
    labels = {
        label
        for label in labels
        if not label.startswith("$") and label not in PROMETHEUS_RESERVED_LABELS
    }
    trace_fields = {field for field in ("rootTraceName", "durationMs") if field in baseline_source}

    return ShippedConsumers(
        metric_names=frozenset(metric_names),
        prometheus_labels=frozenset(labels),
        span_name_matchers=tuple(span_names),
        span_attributes=frozenset(span_attributes),
        resource_attributes=frozenset(resource_attributes),
        trace_fields=frozenset(trace_fields),
    )


def prometheus_label_for(attribute_key: str) -> str:
    """Render an OTLP attribute key the way Prometheus stores it as a label.

    Comparing in this direction avoids inventing an OTLP spelling from a label.
    `copilot_chat_edit_source` has two plausible sources, and reconstructing one
    of them would be the guess this whole change exists to stop making.
    """
    return re.sub(r"[^a-zA-Z0-9_]", "_", attribute_key)


# Attributes observed carrying plaintext content on spans even with content
# capture left at its default. None may appear in the allow-list.
OBSERVED_CONTENT_ATTRIBUTES = frozenset(
    {
        "copilot_chat.user_request",
        "copilot_chat.reasoning_content",
        "gen_ai.input.messages",
        "gen_ai.output.messages",
        "gen_ai.system_instructions",
        "gen_ai.tool.call.arguments",
        "gen_ai.tool.call.result",
    }
)


class ConfigError(ValueError):
    """Raised when a configuration document cannot yield the requested value."""


def load_yaml_text(text: str) -> dict[str, Any]:
    """Parse YAML text into a mapping, raising ConfigError on anything else."""
    try:
        document = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        raise ConfigError(f"document is not valid YAML: {exc}") from exc
    if not isinstance(document, dict):
        raise ConfigError("document root is not a mapping")
    return document


def load_yaml_file(path: pathlib.Path) -> dict[str, Any]:
    """Parse a YAML file into a mapping."""
    if not path.is_file():
        raise ConfigError(f"missing configuration file: {path.name}")
    return load_yaml_text(path.read_text(encoding="utf-8"))


def published_ports(service: dict[str, Any]) -> list[str]:
    """Return the declared host port mappings for a Compose service."""
    return [str(entry) for entry in service.get("ports", []) or []]


def redaction_policy(collector: dict[str, Any]) -> dict[str, Any]:
    """Return the redaction processor configuration from a Collector document."""
    processors = collector.get("processors") or {}
    if not isinstance(processors, dict):
        raise ConfigError("processors is not a mapping")
    for name, config in processors.items():
        if name == "redaction" or str(name).startswith("redaction/"):
            return config or {}
    raise ConfigError("no redaction processor is declared")


def allowed_keys(collector: dict[str, Any]) -> frozenset[str]:
    """Return the allow-listed attribute keys declared by the redaction processor."""
    policy = redaction_policy(collector)
    return frozenset(str(key) for key in policy.get("allowed_keys", []) or [])


def blocked_values(collector: dict[str, Any]) -> tuple[re.Pattern[str], ...]:
    """Return the compiled value patterns the redaction processor masks."""
    policy = redaction_policy(collector)
    return tuple(re.compile(str(pattern)) for pattern in policy.get("blocked_values", []) or [])


def simulate_redaction(
    attributes: dict[str, str],
    allow: frozenset[str],
    blocked: tuple[re.Pattern[str], ...] = (),
    allow_all_keys: bool = False,
) -> dict[str, str]:
    """Model the Collector redaction processor's fail-closed key and value handling.

    Any key outside the allow-list is dropped rather than kept, so an attribute
    this skill has never seen cannot reach storage. Allowed values that still
    match a blocked pattern are masked rather than dropped.
    """
    result: dict[str, str] = {}
    for key, value in attributes.items():
        if not allow_all_keys and key not in allow:
            continue
        text = str(value)
        result[key] = MASK if any(pattern.search(text) for pattern in blocked) else text
    return result


@pytest.fixture(scope="module")
def compose() -> dict[str, Any]:
    """The committed local Compose document."""
    return load_yaml_file(COMPOSE_PATH)


@pytest.fixture(scope="module")
def collector() -> dict[str, Any]:
    """The committed local Collector document."""
    return load_yaml_file(COLLECTOR_PATH)


class TestConfigurationLoading:
    """The shipped documents parse and expose the structures later tests read."""

    def test_compose_declares_services(self, compose: dict[str, Any]) -> None:
        assert isinstance(compose.get("services"), dict)
        assert compose["services"], "compose declares no services"

    def test_yaml_loader_rejects_a_non_mapping_document(self) -> None:
        with pytest.raises(ConfigError):
            load_yaml_text("- just\n- a list\n")

    def test_yaml_loader_rejects_malformed_yaml(self) -> None:
        with pytest.raises(ConfigError):
            load_yaml_text("services: [unclosed\n")


class TestRedactionSimulation:
    """The policy simulator is fail-closed for keys and masking for values."""

    def test_unknown_keys_are_dropped(self) -> None:
        allow = frozenset({"service.name"})
        result = simulate_redaction({"service.name": "copilot", "prompt.text": "secret"}, allow)
        assert result == {"service.name": "copilot"}

    def test_allowed_values_matching_a_blocked_pattern_are_masked(self) -> None:
        allow = frozenset({"http.url"})
        blocked = (re.compile(r"[0-9a-f]{40}"),)
        result = simulate_redaction({"http.url": "a" * 40}, allow, blocked)
        assert result == {"http.url": MASK}

    def test_an_empty_allow_list_drops_everything(self) -> None:
        assert simulate_redaction({"any.key": "value"}, frozenset()) == {}


class TestTopology:
    """The Collector is the only OTLP ingress and LGTM is a private backend."""

    def test_the_collector_publishes_otlp_on_loopback_only(self, compose: dict[str, Any]) -> None:
        ports = published_ports(compose["services"]["otel-collector"])
        assert "127.0.0.1:4317:4317" in ports
        assert "127.0.0.1:4318:4318" in ports
        assert all(entry.startswith("127.0.0.1:") for entry in ports)

    def test_lgtm_publishes_no_otlp_port_to_the_host(self, compose: dict[str, Any]) -> None:
        ports = published_ports(compose["services"]["lgtm"])
        assert not [entry for entry in ports if ":4317:" in entry or ":4318:" in entry]

    def test_every_lgtm_host_mapping_is_loopback(self, compose: dict[str, Any]) -> None:
        assert all(
            entry.startswith("127.0.0.1:") for entry in published_ports(compose["services"]["lgtm"])
        )

    def test_both_services_share_one_declared_network(self, compose: dict[str, Any]) -> None:
        declared = set(compose.get("networks") or {})
        assert declared, "compose declares no explicit network"
        for name in ("otel-collector", "lgtm"):
            assert declared.issuperset(compose["services"][name]["networks"])

    def test_the_collector_exports_to_the_lgtm_service_only(
        self, collector: dict[str, Any]
    ) -> None:
        exporters = collector["exporters"]
        endpoints = {
            config.get("endpoint") for config in exporters.values() if isinstance(config, dict)
        }
        assert endpoints == {"lgtm:4317"}


class TestRedactionPolicy:
    """The declared policy is fail-closed and reaches every pipeline."""

    def test_the_policy_is_fail_closed(self, collector: dict[str, Any]) -> None:
        assert redaction_policy(collector).get("allow_all_keys") is False

    def test_every_pipeline_applies_redaction(self, collector: dict[str, Any]) -> None:
        pipelines = collector["service"]["pipelines"]
        assert set(pipelines) == {"traces", "metrics", "logs"}
        for name, pipeline in pipelines.items():
            assert "redaction" in pipeline["processors"], f"{name} pipeline skips redaction"

    def test_the_allow_list_covers_what_the_dashboards_read(
        self, collector: dict[str, Any]
    ) -> None:
        consumers = shipped_consumers()
        allow = allowed_keys(collector)
        missing = sorted(consumers.protected_attribute_keys() - allow)
        assert missing == [], f"the dashboard reads attributes the allow-list drops: {missing}"

    def test_every_prometheus_label_the_dashboard_reads_has_a_source_key(
        self, collector: dict[str, Any]
    ) -> None:
        """Compare in the OTLP-to-Prometheus direction, never the reverse.

        A label is derived from an attribute key by character substitution,
        and the substitution is not reversible. `copilot_chat_edit_source` has
        at least two plausible sources, so this asserts that some allow-listed
        key normalizes to each derived label rather than reconstructing one.
        """
        consumers = shipped_consumers()
        covered = {prometheus_label_for(key) for key in allowed_keys(collector)}
        uncovered = sorted(consumers.prometheus_labels - covered)
        assert uncovered == [], (
            f"the dashboard groups by labels no allow-listed key produces: {uncovered}. "
            "Add the source attribute or record the label as a known-empty gap; "
            "do not remove it from the derivation."
        )

    def test_the_derivation_finds_the_metric_names_the_dashboard_selects(self) -> None:
        """The derivation has to see metric names, not only attributes.

        Without this, a scrub rule could be licensed against metric names on
        the grounds that no consumer was named for them.
        """
        consumers = shipped_consumers()
        assert len(consumers.metric_names) > 15
        assert "gen_ai_client_token_usage_sum" in consumers.metric_names

    def test_the_derivation_finds_the_span_name_matchers(self) -> None:
        consumers = shipped_consumers()
        assert consumers.span_name_matchers, "no TraceQL span-name matcher was derived"
        assert all(matcher.startswith("invoke_agent") for matcher in consumers.span_name_matchers)

    def test_the_derivation_finds_the_baseline_trace_field(self) -> None:
        assert "rootTraceName" in shipped_consumers().trace_fields

    def test_observed_content_attributes_are_not_allowed(self, collector: dict[str, Any]) -> None:
        assert not (OBSERVED_CONTENT_ATTRIBUTES & allowed_keys(collector))

    def test_a_novel_attribute_is_dropped_rather_than_stored(
        self, collector: dict[str, Any]
    ) -> None:
        allow = allowed_keys(collector)
        emitted = {
            "service.name": "copilot-chat",
            "gen_ai.request.model": "gpt-5",
            # Neither key exists today. A delete-list would pass both through.
            "gen_ai.future.prompt_echo": "the user's entire prompt",
            "copilot_chat.unreleased_content": "a tool result",
        }
        kept = simulate_redaction(emitted, allow, blocked_values(collector))
        assert set(kept) == {"service.name", "gen_ai.request.model"}

    def test_known_content_attributes_are_dropped(self, collector: dict[str, Any]) -> None:
        emitted = dict.fromkeys(OBSERVED_CONTENT_ATTRIBUTES, "plaintext content")
        assert simulate_redaction(emitted, allowed_keys(collector), blocked_values(collector)) == {}

    def test_a_credential_in_an_allowed_value_is_masked(self, collector: dict[str, Any]) -> None:
        kept = simulate_redaction(
            {"gen_ai.request.model": "ghp_" + "a" * 36},
            allowed_keys(collector),
            blocked_values(collector),
        )
        assert kept == {"gen_ai.request.model": MASK}

    def test_the_processor_does_not_annotate_telemetry_with_removed_keys(
        self, collector: dict[str, Any]
    ) -> None:
        assert redaction_policy(collector).get("summary") == "silent"


class TestGrafanaAccess:
    """Grafana requires a credential the operator supplies."""

    def test_anonymous_access_is_disabled_and_the_login_form_is_restored(
        self, compose: dict[str, Any]
    ) -> None:
        environment = compose["services"]["lgtm"]["environment"]
        assert str(environment["GF_AUTH_ANONYMOUS_ENABLED"]).lower() == "false"
        assert str(environment["GF_AUTH_DISABLE_LOGIN_FORM"]).lower() == "false"

    def test_admin_credentials_are_required_environment_variables(
        self, compose: dict[str, Any]
    ) -> None:
        environment = compose["services"]["lgtm"]["environment"]
        for key, variable in (
            ("GF_SECURITY_ADMIN_USER", "COPILOT_OTEL_GRAFANA_USER"),
            ("GF_SECURITY_ADMIN_PASSWORD", "COPILOT_OTEL_GRAFANA_PASSWORD"),
        ):
            value = str(environment[key])
            assert value.startswith(f"${{{variable}:?"), f"{key} is not a required variable"

    def test_no_password_literal_is_committed(self) -> None:
        text = COMPOSE_PATH.read_text(encoding="utf-8")
        assert "GF_SECURITY_ADMIN_PASSWORD: admin" not in text
        assert "admin:admin" not in text

    def test_the_dashboard_helper_reads_the_same_credential_pair(self) -> None:
        text = (EXAMPLES_DIR / "validate_dashboard.py").read_text(encoding="utf-8")
        for variable in ("COPILOT_OTEL_GRAFANA_USER", "COPILOT_OTEL_GRAFANA_PASSWORD"):
            assert variable in text, f"{variable} is not read by the helper"
            # A default would make the helper usable against a credential the
            # operator never chose, which is the failure this pair exists to stop.
            assert f'"{variable}",' in text or f'"{variable}"\n' in text
            assert f'os.environ.get("{variable}",' not in text, f"{variable} has a default"
        assert "require_credentials(" in text, "credentials bypass the shared policy"


class TestImagePinning:
    """Both images are pinned by immutable digest."""

    @pytest.mark.parametrize("service", ["otel-collector", "lgtm"])
    def test_the_image_is_digest_pinned(self, compose: dict[str, Any], service: str) -> None:
        assert DIGEST_REFERENCE.match(compose["services"][service]["image"])


def scrub_statements(collector: dict[str, Any]) -> list[str]:
    """Every OTTL statement the content-scrub processor declares."""
    processor = collector["processors"].get("transform/scrub", {})
    statements: list[str] = []
    for key in ("trace_statements", "log_statements", "metric_statements"):
        for entry in processor.get(key) or []:
            if isinstance(entry, str):
                statements.append(entry)
            else:
                statements.extend(entry.get("statements", []))
    return statements


def statement_target(statement: str) -> str:
    """The path an OTTL statement writes to.

    Only the write target matters. A `where` clause may read `span.name`
    without endangering it, and treating a read as an overreach would push the
    scrub rules into contortions to avoid mentioning what they must not touch.
    """
    if "(" not in statement:
        return ""
    inner = statement.split("(", 1)[1]
    depth = 0
    for index, character in enumerate(inner):
        if character in "([":
            depth += 1
        elif character in ")]":
            if depth == 0:
                return inner[:index].strip()
            depth -= 1
        elif character == "," and depth == 0:
            return inner[:index].strip()
    return inner.strip()


# Intrinsics a shipped consumer reads directly. `span.name` is here because
# three TraceQL queries match on it; the metric intrinsics are here because
# every Prometheus query selects by metric name.
PROTECTED_INTRINSICS = frozenset({"span.name", "metric.name", "metric.description", "metric.unit"})

ATTRIBUTE_TARGET = re.compile(r"attributes\[\"([^\"]+)\"\]")


def overreaching_statements(
    statements: list[str], consumers: ShippedConsumers
) -> list[tuple[str, str]]:
    """Statements whose write target is something a shipped consumer reads."""
    protected_keys = consumers.protected_attribute_keys()
    findings: list[tuple[str, str]] = []
    for statement in statements:
        target = statement_target(statement)
        if target in PROTECTED_INTRINSICS:
            findings.append((statement, target))
            continue
        for key in ATTRIBUTE_TARGET.findall(target):
            if key in protected_keys:
                findings.append((statement, key))
    return findings


class TestScrubStaysInsideTheInventory:
    """A scrub rule may not target anything a shipped consumer reads.

    The code review's own suggested fix for the ungoverned-carrier finding was
    to normalize span names. That would have broken three dashboard queries and
    the baseline helper's `rootTraceName` read. This check is oriented at the
    rules that were changed, because asserting that unchanged dashboard files
    still contain their strings cannot fail.
    """

    def test_the_scrub_processor_declares_statements(self, collector: dict[str, Any]) -> None:
        assert scrub_statements(collector), "the content scrub declares no statements"

    def test_no_scrub_statement_targets_a_shipped_consumer(self, collector: dict[str, Any]) -> None:
        findings = overreaching_statements(scrub_statements(collector), shipped_consumers())
        assert findings == [], f"a scrub rule targets telemetry a shipped panel reads: {findings}"

    def test_the_check_catches_a_rule_that_normalizes_span_names(self) -> None:
        """The negative case. Without it this check could be vacuous."""
        overreach = ['set(span.name, "[redacted]")']
        assert overreaching_statements(overreach, shipped_consumers()) == [
            ('set(span.name, "[redacted]")', "span.name")
        ]

    def test_the_check_catches_a_rule_that_deletes_a_read_attribute(self) -> None:
        overreach = ['delete_key(span.attributes["gen_ai.request.model"], "x")']
        findings = overreaching_statements(overreach, shipped_consumers())
        assert findings and findings[0][1] == "gen_ai.request.model"

    def test_a_condition_that_reads_a_protected_field_is_not_an_overreach(self) -> None:
        """A `where` clause reads; it does not write."""
        reading = ['set(span.status.message, "[redacted]") where span.name != ""']
        assert overreaching_statements(reading, shipped_consumers()) == []


class TestExporterAlias:
    """The exporter uses the alias the pinned Collector asks for."""

    def test_no_pipeline_references_the_deprecated_alias(self, collector: dict[str, Any]) -> None:
        exporters = set(collector["exporters"])
        assert not any(name == "otlp" or name.startswith("otlp/") for name in exporters), (
            "the pinned Collector logs a deprecation warning once per signal for "
            "the `otlp` exporter alias; use `otlp_grpc`"
        )
        for name, pipeline in collector["service"]["pipelines"].items():
            assert set(pipeline["exporters"]) <= exporters, f"{name} names an undeclared exporter"

    def test_the_internal_hop_is_unchanged_by_the_rename(self, collector: dict[str, Any]) -> None:
        exporter = collector["exporters"]["otlp_grpc/lgtm"]
        assert exporter["endpoint"] == "lgtm:4317"
        assert exporter["tls"]["insecure"] is True
