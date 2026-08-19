# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Static checks over the local stack configuration shipped with this skill.

These tests parse the committed Compose and Collector documents and simulate the
declared attribute policy. They never start a container and never assert that a
running Collector behaves as configured; they assert only that the configuration
this skill ships declares the intended policy. Runtime behaviour is the subject
of `test_collector_carriers.py`, which is marked `slow` and does start one.
"""

from __future__ import annotations

import re
from typing import Any

import pytest
from _config_support import (
    COLLECTOR_PATH,
    COMPOSE_PATH,
    DIGEST_REFERENCE,
    EXAMPLES_DIR,
    MASK,
    OBSERVED_CONTENT_ATTRIBUTES,
    ConfigError,
    allowed_keys,
    blocked_values,
    load_yaml_file,
    load_yaml_text,
    overreaching_statements,
    prometheus_label_for,
    published_ports,
    redaction_policy,
    scrub_statements,
    shipped_consumers,
    simulate_redaction,
)


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


class TestContainerBounds:
    """The Collector's declared memory bound has to resolve against something.

    `memory_limiter` uses percentages, and those resolve against the cgroup
    limit when one exists and against total host memory when one does not.
    Without a declared limit, the configuration's stated bound is 80% of the
    developer's machine, in front of an ingress any local process can reach.
    """

    def test_the_collector_declares_a_cgroup_memory_limit(self, compose: dict[str, Any]) -> None:
        assert compose["services"]["otel-collector"]["mem_limit"] == "512m"

    def test_the_collector_drops_every_capability(self, compose: dict[str, Any]) -> None:
        assert compose["services"]["otel-collector"]["cap_drop"] == ["ALL"]

    def test_the_collector_cannot_gain_privileges(self, compose: dict[str, Any]) -> None:
        assert "no-new-privileges:true" in compose["services"]["otel-collector"]["security_opt"]

    def test_the_collector_root_filesystem_is_read_only(self, compose: dict[str, Any]) -> None:
        assert compose["services"]["otel-collector"]["read_only"] is True


class TestCredentialShapeCoverage:
    """The value patterns are masking of recognizable shapes, not secret detection."""

    @pytest.mark.parametrize(
        "value",
        [
            "ghp_" + "a" * 36,
            "ASIA" + "B" * 16,
            "AKIA" + "C" * 16,
            "eyJhbGciOiJub25l.eyJzdWIiOiIxMjM0NTY3.",
            "AccountKey=" + "d" * 24,
            "sk-ant-" + "e" * 24,
            "AIza" + "f" * 35,
        ],
        ids=[
            "github-token",
            "aws-temporary-key-id",
            "aws-long-term-key-id",
            "unsigned-jwt",
            "azure-account-key",
            "anthropic-api-key",
            "google-api-key",
        ],
    )
    def test_a_recognizable_credential_shape_is_masked(
        self, collector: dict[str, Any], value: str
    ) -> None:
        kept = simulate_redaction(
            {"gen_ai.request.model": value},
            allowed_keys(collector),
            blocked_values(collector),
        )
        assert kept == {"gen_ai.request.model": MASK}

    def test_an_ordinary_value_is_not_masked(self, collector: dict[str, Any]) -> None:
        """Without this, a pattern broad enough to mask everything would pass."""
        kept = simulate_redaction(
            {"gen_ai.request.model": "gpt-5"},
            allowed_keys(collector),
            blocked_values(collector),
        )
        assert kept == {"gen_ai.request.model": "gpt-5"}


class TestScrubFailureDirection:
    """The scrub is fail-open per statement, and that is recorded where it lives."""

    def test_the_scrub_error_mode_is_documented_as_deliberate(
        self, collector: dict[str, Any]
    ) -> None:
        assert collector["processors"]["transform/scrub"]["error_mode"] == "ignore"
        text = COLLECTOR_PATH.read_text(encoding="utf-8")
        assert "fail-open per statement" in text, (
            "the asymmetry with the fail-closed allow-list is not recorded"
        )


class TestImagePinning:
    """Both images are pinned by immutable digest."""

    @pytest.mark.parametrize("service", ["otel-collector", "lgtm"])
    def test_the_image_is_digest_pinned(self, compose: dict[str, Any], service: str) -> None:
        assert DIGEST_REFERENCE.match(compose["services"][service]["image"])


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
