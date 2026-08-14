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

AZURE_DIR = pathlib.Path(__file__).resolve().parents[1] / "examples" / "azure"
COLLECTOR_PATH = AZURE_DIR / "otel-collector-config.yaml"
BICEP_PATH = AZURE_DIR / "main.bicep"
MAIN_TF_PATH = AZURE_DIR / "main.tf"
VARIABLES_TF_PATH = AZURE_DIR / "variables.tf"
OUTPUTS_TF_PATH = AZURE_DIR / "outputs.tf"

TEMPLATE_PATHS = [BICEP_PATH, MAIN_TF_PATH, VARIABLES_TF_PATH, OUTPUTS_TF_PATH, COLLECTOR_PATH]

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
