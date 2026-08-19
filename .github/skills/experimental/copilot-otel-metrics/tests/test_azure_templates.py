# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Static checks over the Azure fleet templates.

These tests read the committed Bicep, Terraform, and Collector files as text and
YAML. Nothing here deploys, plans, or contacts Azure.
"""

from __future__ import annotations

import pathlib
import re

import pytest
import yaml
from _config_support import (
    COLLECTOR_PATH as LOCAL_COLLECTOR_PATH,
)
from _config_support import (
    DIGEST_REFERENCE,
    RELAY_COLLECTOR_PATH,
    RELAY_COMPOSE_PATH,
    load_yaml_file,
    redaction_policy,
    scrub_statements,
)

AZURE_DIR = pathlib.Path(__file__).resolve().parents[1] / "examples" / "azure"
COLLECTOR_PATH = AZURE_DIR / "otel-collector-config.yaml"
BICEP_PATH = AZURE_DIR / "main.bicep"
MAIN_TF_PATH = AZURE_DIR / "main.tf"
VARIABLES_TF_PATH = AZURE_DIR / "variables.tf"
OUTPUTS_TF_PATH = AZURE_DIR / "outputs.tf"

TEMPLATE_PATHS = [
    BICEP_PATH,
    MAIN_TF_PATH,
    VARIABLES_TF_PATH,
    OUTPUTS_TF_PATH,
    COLLECTOR_PATH,
    RELAY_COLLECTOR_PATH,
    RELAY_COMPOSE_PATH,
]

# The relay's runtime inputs, and the only values a rendered Compose document
# may carry. They are obvious non-secrets so a rendering failure cannot be
# mistaken for a leaked credential.
RELAY_SENTINELS = {
    "COPILOT_OTEL_FLEET_ENDPOINT": "https://sentinel-fleet.invalid",
    "COPILOT_OTEL_INGEST_TOKEN": "sentinel-token-not-a-credential",
    "COPILOT_OTEL_FLEET_CA_BUNDLE": "/sentinel/absolute/path/fleet-ca.pem",
}
RELAY_CA_MOUNT = "/run/copilot-otel/fleet-ca.pem"

# The managed-settings contract these relay files have to agree with.
ORG_DISTRIBUTION_PATH = (
    pathlib.Path(__file__).resolve().parents[1] / "references" / "org-distribution.md"
)

# Compose interpolation this skill uses: ${NAME:?message} for a required value
# and ${NAME} for a plain one.
COMPOSE_VARIABLE = re.compile(r"\$\{(?P<name>[A-Z0-9_]+)(?::\?(?P<message>[^}]*))?\}")

# Shapes that indicate a real credential rather than a placeholder or a
# reference to one.
SECRET_PATTERNS = (
    re.compile(r"InstrumentationKey=[0-9a-f]{8}-[0-9a-f]{4}", re.IGNORECASE),
    re.compile(r"gh[pousr]_[0-9A-Za-z]{16,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
)


@pytest.fixture(scope="module")
def collector() -> dict:
    return yaml.safe_load(COLLECTOR_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def local_collector() -> dict:
    """The local stack policy, which is this skill's minimization baseline."""
    return load_yaml_file(LOCAL_COLLECTOR_PATH)


@pytest.fixture(scope="module")
def relay() -> dict:
    """The shipped workstation relay Collector configuration."""
    return load_yaml_file(RELAY_COLLECTOR_PATH)


@pytest.fixture(scope="module")
def relay_compose() -> dict:
    """The relay Compose document with its required variables rendered.

    Rendering is what makes the mount and environment assertions mean
    something: an unrendered `${VAR:?...}` string satisfies any substring check
    while telling nothing about what the container would actually receive.
    """
    text = RELAY_COMPOSE_PATH.read_text(encoding="utf-8")
    rendered = COMPOSE_VARIABLE.sub(lambda match: RELAY_SENTINELS[match["name"]], text)
    return yaml.safe_load(rendered)


@pytest.fixture(scope="module")
def bicep() -> str:
    return BICEP_PATH.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def terraform() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in (MAIN_TF_PATH, VARIABLES_TF_PATH))


class TestReceiverAuthentication:
    """The fleet receiver authenticates senders, in configuration and not in prose."""

    @pytest.mark.parametrize("protocol", ["http", "grpc"])
    def test_each_protocol_declares_an_authenticator(self, collector: dict, protocol: str) -> None:
        config = collector["receivers"]["otlp"]["protocols"][protocol]
        assert config["auth"]["authenticator"] == "bearertokenauth"

    def test_the_authenticator_extension_is_active(self, collector: dict) -> None:
        assert "bearertokenauth" in collector["extensions"]
        assert "bearertokenauth" in collector["service"]["extensions"]

    def test_the_token_is_an_environment_reference(self, collector: dict) -> None:
        token = collector["extensions"]["bearertokenauth"]["token"]
        assert token.startswith("${env:")

    def test_authentication_is_not_left_commented_out(self) -> None:
        text = COLLECTOR_PATH.read_text(encoding="utf-8")
        commented = [
            line
            for line in text.splitlines()
            if line.strip().startswith("#") and "bearertokenauth:" in line
        ]
        assert commented == [], "authentication is present only as a comment"


class TestReceiverTls:
    """TLS is configured, and its material comes from the environment."""

    @pytest.mark.parametrize("protocol", ["http", "grpc"])
    def test_each_protocol_configures_tls(self, collector: dict, protocol: str) -> None:
        tls = collector["receivers"]["otlp"]["protocols"][protocol]["tls"]
        assert tls["cert_file"].startswith("${env:")
        assert tls["key_file"].startswith("${env:")


class TestEnvironmentSeparation:
    """Separation comes from separate deployments, not from an attribute."""

    def test_bicep_requires_an_environment_parameter(self, bicep: str) -> None:
        assert re.search(r"^param environment string$", bicep, re.MULTILINE)
        assert "param environment string = " not in bicep, "environment must have no default"

    def test_terraform_requires_an_environment_variable(self, terraform: str) -> None:
        assert 'variable "environment"' in terraform
        block = terraform.split('variable "environment"', 1)[1].split("\nvariable ", 1)[0]
        assert "default" not in block, "environment must have no default"

    def test_bicep_resource_names_include_the_environment(self, bicep: str) -> None:
        for name in ("workspaceName", "appInsightsName", "dashboardName"):
            line = next(line for line in bicep.splitlines() if line.startswith(f"var {name}"))
            assert "${environment}" in line

    def test_terraform_resource_names_include_the_environment(self, terraform: str) -> None:
        assert 'resource_prefix = "${var.name_prefix}-${var.environment}"' in terraform
        assert "${local.resource_prefix}-copilot-logs" in terraform
        assert "${local.resource_prefix}-copilot-insights" in terraform

    def test_the_collector_environment_attribute_is_an_environment_reference(
        self, collector: dict
    ) -> None:
        attributes = collector["processors"]["resource/fleet"]["attributes"]
        by_key = {entry["key"]: entry for entry in attributes}
        assert by_key["deployment.environment.name"]["value"].startswith("${env:")

    def test_no_file_calls_a_resource_attribute_an_isolation_control(self) -> None:
        for path in TEMPLATE_PATHS:
            text = path.read_text(encoding="utf-8").lower()
            for claim in ("namespace provides isolation", "isolated by service.namespace"):
                assert claim not in text


class TestRetentionAndAccess:
    """Retention, caps, and reader scope agree across both templates."""

    def test_retention_defaults_match(self, bicep: str, terraform: str) -> None:
        assert "param retentionInDays int = 90" in bicep
        assert re.search(r'variable "retention_in_days"[\s\S]*?default\s*=\s*90', terraform)

    def test_daily_cap_defaults_match(self, bicep: str, terraform: str) -> None:
        assert "param dailyQuotaGb int = 5" in bicep
        assert re.search(r'variable "daily_quota_gb"[\s\S]*?default\s*=\s*5', terraform)

    def test_the_reader_assignment_is_opt_in(self, bicep: str, terraform: str) -> None:
        assert "if (!empty(readerPrincipalId))" in bicep
        assert 'count = var.reader_principal_id == "" ? 0 : 1' in terraform

    def test_the_reader_assignment_is_scoped_to_the_workspace(
        self, bicep: str, terraform: str
    ) -> None:
        assert "scope: workspace" in bicep
        assert "scope                = azurerm_log_analytics_workspace.this.id" in terraform

    def test_retention_is_described_as_the_deletion_boundary(
        self, bicep: str, terraform: str
    ) -> None:
        assert "deletion policy" in bicep.lower()
        assert "deletion policy" in terraform.lower()


class TestFleetPolicyParity:
    """The fleet filters at least as much as the local stack, on every signal.

    The destination here is a shared, retained workspace rather than one
    workstation's disposable container, so a fleet pipeline that filtered less
    than the local one would make the skill's pre-storage claims false in the
    place they matter most. Parity is asserted against the local document
    rather than restated, so drift in either file fails.
    """

    def test_the_fleet_allow_list_matches_the_local_allow_list(
        self, collector: dict, local_collector: dict
    ) -> None:
        assert (
            redaction_policy(collector)["allowed_keys"]
            == redaction_policy(local_collector)["allowed_keys"]
        )

    def test_the_fleet_blocked_values_match_the_local_blocked_values(
        self, collector: dict, local_collector: dict
    ) -> None:
        assert (
            redaction_policy(collector)["blocked_values"]
            == redaction_policy(local_collector)["blocked_values"]
        )

    def test_the_fleet_policy_is_fail_closed_and_silent(self, collector: dict) -> None:
        policy = redaction_policy(collector)
        assert policy["allow_all_keys"] is False
        assert policy["summary"] == "silent"

    def test_the_fleet_scrub_statements_match_the_local_scrub_statements(
        self, collector: dict, local_collector: dict
    ) -> None:
        assert scrub_statements(collector) == scrub_statements(local_collector)

    @pytest.mark.parametrize("signal", ["traces", "metrics", "logs"])
    def test_every_signal_applies_both_privacy_processors(
        self, collector: dict, signal: str
    ) -> None:
        processors = collector["service"]["pipelines"][signal]["processors"]
        assert "redaction" in processors, f"{signal} reaches storage unfiltered"
        assert "transform/scrub" in processors, f"{signal} keeps ungoverned carriers"

    @pytest.mark.parametrize("signal", ["traces", "metrics", "logs"])
    def test_the_privacy_processors_keep_their_local_relative_order(
        self, collector: dict, local_collector: dict, signal: str
    ) -> None:
        """The runtime carrier probe only substitutes definitions, not ordering."""
        privacy = ("redaction", "transform/scrub")
        fleet_order = [
            step
            for step in collector["service"]["pipelines"][signal]["processors"]
            if step in privacy
        ]
        local_order = [
            step
            for step in local_collector["service"]["pipelines"][signal]["processors"]
            if step in privacy
        ]
        assert fleet_order == local_order

    @pytest.mark.parametrize("signal", ["traces", "metrics", "logs"])
    def test_filtering_precedes_export_and_operator_identity(
        self, collector: dict, signal: str
    ) -> None:
        processors = collector["service"]["pipelines"][signal]["processors"]
        assert processors.index("memory_limiter") < processors.index("redaction")
        assert processors.index("transform/scrub") < processors.index("resource/fleet")
        assert processors.index("resource/fleet") < processors.index("batch")

    def test_the_superseded_delete_list_is_gone(self, collector: dict) -> None:
        """A delete-list cannot fail closed on an attribute it has never seen."""
        assert "attributes/strip-content" not in collector["processors"]
        for pipeline in collector["service"]["pipelines"].values():
            assert "attributes/strip-content" not in pipeline["processors"]


class TestRelayTopology:
    """The relay is reachable from this workstation and from nothing else."""

    def test_the_relay_declares_only_otlp_http(self, relay: dict) -> None:
        protocols = relay["receivers"]["otlp"]["protocols"]
        assert set(protocols) == {"http"}, "a second ingress protocol would be unexercised"

    def test_the_relay_receiver_takes_the_container_interface(self, relay: dict) -> None:
        """Host exposure is the port mapping's decision, exactly as the local stack does it."""
        assert relay["receivers"]["otlp"]["protocols"]["http"]["endpoint"] == "0.0.0.0:4318"

    def test_the_relay_receiver_requires_no_credential(self, relay: dict) -> None:
        """Both emitters export without one; requiring it here would drop everything."""
        assert "auth" not in relay["receivers"]["otlp"]["protocols"]["http"]

    def test_every_published_port_is_loopback(self, relay_compose: dict) -> None:
        ports = [str(entry) for entry in relay_compose["services"]["otel-relay"]["ports"]]
        assert ports, "the relay publishes nothing"
        for entry in ports:
            assert entry.startswith("127.0.0.1:"), f"{entry} is reachable off this workstation"
            assert "::" not in entry

    def test_the_only_otlp_mapping_is_http_on_4318(self, relay_compose: dict) -> None:
        ports = [str(entry) for entry in relay_compose["services"]["otel-relay"]["ports"]]
        assert "127.0.0.1:4318:4318" in ports
        assert not [entry for entry in ports if ":4317:" in entry], "gRPC is unsupported"


class TestRelayUpstream:
    """The upstream hop is authenticated and its certificate is verified."""

    def test_the_endpoint_is_an_environment_reference(self, relay: dict) -> None:
        exporter = relay["exporters"]["otlp_http/fleet"]
        assert exporter["endpoint"] == "${env:COPILOT_OTEL_FLEET_ENDPOINT}"

    def test_the_exporter_authenticates(self, relay: dict) -> None:
        assert relay["exporters"]["otlp_http/fleet"]["auth"]["authenticator"] == "bearertokenauth"
        assert relay["extensions"]["bearertokenauth"]["token"].startswith("${env:")
        assert "bearertokenauth" in relay["service"]["extensions"]

    def test_the_exporter_verifies_against_the_mounted_bundle(self, relay: dict) -> None:
        tls = relay["exporters"]["otlp_http/fleet"]["tls"]
        assert tls["ca_file"] == RELAY_CA_MOUNT
        assert "insecure" not in tls, "the upstream hop must not opt out of verification"
        assert "insecure_skip_verify" not in tls

    def test_no_pipeline_exports_anywhere_else(self, relay: dict) -> None:
        for name, pipeline in relay["service"]["pipelines"].items():
            assert pipeline["exporters"] == ["otlp_http/fleet"], f"{name} has a second destination"


class TestRelayPolicyParity:
    """Telemetry is minimized on the workstation that produced it."""

    def test_the_relay_allow_list_matches_the_local_allow_list(
        self, relay: dict, local_collector: dict
    ) -> None:
        assert (
            redaction_policy(relay)["allowed_keys"]
            == redaction_policy(local_collector)["allowed_keys"]
        )

    def test_the_relay_blocked_values_match_the_local_blocked_values(
        self, relay: dict, local_collector: dict
    ) -> None:
        assert (
            redaction_policy(relay)["blocked_values"]
            == redaction_policy(local_collector)["blocked_values"]
        )

    def test_the_relay_scrub_statements_match_the_local_scrub_statements(
        self, relay: dict, local_collector: dict
    ) -> None:
        assert scrub_statements(relay) == scrub_statements(local_collector)

    @pytest.mark.parametrize("signal", ["traces", "metrics", "logs"])
    def test_every_signal_is_filtered_before_it_leaves_the_workstation(
        self, relay: dict, signal: str
    ) -> None:
        processors = relay["service"]["pipelines"][signal]["processors"]
        assert processors.index("redaction") < processors.index("batch")
        assert processors.index("transform/scrub") < processors.index("batch")


class TestRelayRuntime:
    """The relay outlives VS Code, holds no committed credential, and is bounded."""

    def test_the_image_is_digest_pinned(self, relay_compose: dict) -> None:
        assert DIGEST_REFERENCE.match(relay_compose["services"]["otel-relay"]["image"])

    def test_the_relay_restarts_independently_of_the_editor(self, relay_compose: dict) -> None:
        assert relay_compose["services"]["otel-relay"]["restart"] == "unless-stopped"

    def test_the_container_is_hardened(self, relay_compose: dict) -> None:
        service = relay_compose["services"]["otel-relay"]
        assert service["read_only"] is True
        assert service["cap_drop"] == ["ALL"]
        assert "no-new-privileges:true" in service["security_opt"]
        assert service["mem_limit"] == "512m"

    @pytest.mark.parametrize("variable", sorted(RELAY_SENTINELS))
    def test_every_runtime_input_is_required(self, variable: str) -> None:
        """A defaulted input would start a relay that silently discards everything."""
        text = RELAY_COMPOSE_PATH.read_text(encoding="utf-8")
        matches = [match for match in COMPOSE_VARIABLE.finditer(text) if match["name"] == variable]
        assert matches, f"{variable} is not read by the relay Compose document"
        for match in matches:
            assert match["message"], f"{variable} has no failure message and may default to empty"

    def test_the_config_and_ca_bundle_are_mounted_read_only(self, relay_compose: dict) -> None:
        volumes = [str(entry) for entry in relay_compose["services"]["otel-relay"]["volumes"]]
        config_mount = next(entry for entry in volumes if entry.endswith("config.yaml:ro"))
        assert config_mount.startswith("./otel-collector-config.yaml:")
        ca_mount = next(entry for entry in volumes if RELAY_CA_MOUNT in entry)
        assert ca_mount == f"{RELAY_SENTINELS['COPILOT_OTEL_FLEET_CA_BUNDLE']}:{RELAY_CA_MOUNT}:ro"

    def test_the_ca_bundle_comes_from_outside_this_repository(self, relay_compose: dict) -> None:
        """The skill ships no certificate authority, and could not ship a useful one."""
        volumes = [str(entry) for entry in relay_compose["services"]["otel-relay"]["volumes"]]
        ca_mount = next(entry for entry in volumes if RELAY_CA_MOUNT in entry)
        assert ca_mount.startswith("/"), "the bundle path must be absolute"
        assert not ca_mount.startswith("./")

    def test_only_the_relay_service_receives_the_upstream_values(self, relay_compose: dict) -> None:
        rendered = yaml.safe_dump(relay_compose)
        for service, definition in relay_compose["services"].items():
            environment = definition.get("environment") or {}
            if service != "otel-relay":
                assert RELAY_SENTINELS["COPILOT_OTEL_INGEST_TOKEN"] not in str(environment)
        assert rendered.count(RELAY_SENTINELS["COPILOT_OTEL_INGEST_TOKEN"]) == 1


class TestManagedSettingsMatchTheRelay:
    """The distributed managed block has to describe the relay that was shipped.

    An endpoint or protocol that drifts from the relay's single listener is not
    a documentation defect; it is a fleet that stops reporting after the
    managed settings change.
    """

    def test_the_managed_endpoint_is_the_relay_listener(self, relay_compose: dict) -> None:
        text = ORG_DISTRIBUTION_PATH.read_text(encoding="utf-8")
        assert '"endpoint": "http://127.0.0.1:4318"' in text
        ports = [str(entry) for entry in relay_compose["services"]["otel-relay"]["ports"]]
        assert "127.0.0.1:4318:4318" in ports

    def test_the_managed_protocol_is_the_one_the_relay_serves(self, relay: dict) -> None:
        text = ORG_DISTRIBUTION_PATH.read_text(encoding="utf-8")
        assert '"protocol": "otlp-http"' in text
        assert set(relay["receivers"]["otlp"]["protocols"]) == {"http"}

    def test_managed_settings_carry_no_fleet_credential(self) -> None:
        text = ORG_DISTRIBUTION_PATH.read_text(encoding="utf-8")
        block = text.split("```json", 1)[1].split("```", 1)[0]
        assert "headers" not in block, "the managed block must not distribute the fleet token"
        assert "Bearer" not in block

    def test_grpc_is_named_unsupported_rather_than_untested(self) -> None:
        text = ORG_DISTRIBUTION_PATH.read_text(encoding="utf-8").lower()
        assert "no grpc listener" in text or "there is no grpc listener" in text

    def test_the_relay_prerequisite_precedes_the_managed_change(self) -> None:
        text = ORG_DISTRIBUTION_PATH.read_text(encoding="utf-8").lower()
        assert "distributing this block" in text
        assert "sends no telemetry at all" in text
        assert "rolling back" in text or "rollback" in text


class TestStateAndSecrets:
    """No template carries a credential, and state sensitivity is stated."""

    @pytest.mark.parametrize("path", TEMPLATE_PATHS, ids=lambda p: p.name)
    def test_no_literal_secret_is_committed(self, path: pathlib.Path) -> None:
        text = path.read_text(encoding="utf-8")
        for pattern in SECRET_PATTERNS:
            assert not pattern.search(text), f"{path.name} matches {pattern.pattern}"

    def test_the_connection_string_output_is_marked_sensitive(self) -> None:
        text = OUTPUTS_TF_PATH.read_text(encoding="utf-8")
        block = text.split('output "connection_string"', 1)[1]
        assert "sensitive   = true" in block

    def test_state_sensitivity_is_documented_rather_than_implied(self) -> None:
        text = MAIN_TF_PATH.read_text(encoding="utf-8").lower()
        assert "state file" in text
        assert "does not remove it from state" in text

    def test_bicep_emits_a_command_rather_than_the_connection_string(self, bicep: str) -> None:
        assert "output connectionStringCommand string" in bicep
        assert "output connectionString string =" not in bicep
