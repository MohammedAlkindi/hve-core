# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Behavioral tests for the shared helper input policy.

Every rejection case asserts that the refusal happens before any request or
write, which is the property that matters: a guard that rejects after the
side effect is not a guard.
"""

from __future__ import annotations

import io
import ipaddress
import json
import os
import pathlib
import subprocess
import sys
import urllib.request

import inspect_metrics
import pytest
import validate_dashboard
import verify
from _input_policy import (
    DEFAULT_ALLOWED_PORTS,
    PolicyError,
    check_url,
    contain_path,
    is_loopback_host,
    open_url,
    origin_of,
    require_credentials,
)

EXAMPLES_DIR = pathlib.Path(__file__).resolve().parents[1] / "examples"

# Address literals, so these tests exercise the policy rather than whatever
# DNS answers on the machine running them. 93.184.216.34 is globally routable
# and 10.0.0.7 is not; no test opens a connection to either.
GLOBAL_ADDRESS = "93.184.216.34"
PRIVATE_ADDRESS = "10.0.0.7"


@pytest.fixture
def resolves(monkeypatch: pytest.MonkeyPatch):
    """Pin what each name resolves to, so the rule under test is the policy.

    Resolution is the thing this policy now depends on, which makes real DNS a
    dependency of the test rather than a subject of it. An unroutable name and
    a name that answers with a routable address are both failures worth
    asserting, and neither is reliably reproducible against a real resolver.
    """

    def apply(mapping: dict[str, list[str]]) -> None:
        def fake(host: str) -> tuple:
            try:
                return (ipaddress.ip_address(host.strip("[]")),)
            except ValueError:
                pass
            if host not in mapping:
                raise PolicyError(f"refusing '{host}': it does not resolve")
            return tuple(ipaddress.ip_address(value) for value in mapping[host])

        monkeypatch.setattr("_input_policy.resolve_addresses", fake)

    return apply


class TestScheme:
    """Only http and https are addressable."""

    @pytest.mark.parametrize(
        "url",
        [
            "file:///etc/passwd",
            "ftp://localhost/data",
            "data:text/plain,hello",
            "gopher://localhost:70/",
            "//localhost:3000/api",
        ],
    )
    def test_a_non_http_scheme_is_refused(self, url: str) -> None:
        with pytest.raises(PolicyError):
            check_url(url)

    def test_loopback_http_is_allowed(self) -> None:
        assert check_url("http://localhost:3000/api/health").hostname == "localhost"


class TestAuthority:
    """Credentials, missing hosts, and malformed authorities are refused."""

    @pytest.mark.parametrize(
        "url",
        [
            "http://user@localhost:3000/",
            "http://user:pass@localhost:3000/",
            "http://:pass@localhost:3000/",
        ],
    )
    def test_userinfo_is_refused(self, url: str) -> None:
        with pytest.raises(PolicyError, match="credentials"):
            check_url(url)

    def test_a_missing_host_is_refused(self) -> None:
        with pytest.raises(PolicyError):
            check_url("http:///api/health")

    def test_a_malformed_port_is_refused(self) -> None:
        with pytest.raises(PolicyError):
            check_url("http://localhost:notaport/")


class TestPorts:
    """Local requests stay on the stack's own ports."""

    @pytest.mark.parametrize("port", sorted(DEFAULT_ALLOWED_PORTS))
    def test_each_stack_port_is_allowed(self, port: int) -> None:
        assert check_url(f"http://127.0.0.1:{port}/").port == port

    @pytest.mark.parametrize("port", [22, 80, 443, 8080, 5432])
    def test_an_unrelated_local_port_is_refused(self, port: int) -> None:
        with pytest.raises(PolicyError, match="local port"):
            check_url(f"http://127.0.0.1:{port}/")


class TestRemoteOptIn:
    """A remote target needs an explicit opt-in, TLS, and a globally routable address."""

    def test_a_remote_host_is_refused_without_opt_in(self, resolves) -> None:
        resolves({"grafana.example.com": [GLOBAL_ADDRESS]})
        with pytest.raises(PolicyError, match="non-loopback"):
            check_url("https://grafana.example.com/")

    def test_a_remote_host_is_allowed_with_opt_in(self, resolves) -> None:
        resolves({"grafana.example.com": [GLOBAL_ADDRESS]})
        assert check_url("https://grafana.example.com/", allow_remote=True).scheme == "https"

    def test_plaintext_remote_is_refused_even_with_opt_in(self, resolves) -> None:
        resolves({"grafana.example.com": [GLOBAL_ADDRESS]})
        with pytest.raises(PolicyError, match="plaintext"):
            check_url("http://grafana.example.com/", allow_remote=True)

    def test_an_opted_in_remote_name_resolving_inside_the_network_is_refused(
        self, resolves
    ) -> None:
        """The opt-in permits a remote target, not a route back into the network."""
        resolves({"grafana.example.com": [PRIVATE_ADDRESS]})
        with pytest.raises(PolicyError, match="non-global"):
            check_url("https://grafana.example.com/", allow_remote=True)


class TestHostResolution:
    """A name is classified by where it resolves, not by how it is spelled."""

    def test_a_local_looking_name_that_resolves_off_machine_is_not_local(self, resolves) -> None:
        resolves({"localhost": [GLOBAL_ADDRESS]})
        assert is_loopback_host("localhost") is False
        with pytest.raises(PolicyError, match="non-loopback"):
            check_url("http://localhost:3000/")

    def test_a_name_resolving_to_both_is_refused(self, resolves) -> None:
        """Treating a mixed answer as local would permit a connection off machine."""
        resolves({"split.example": ["127.0.0.1", GLOBAL_ADDRESS]})
        assert is_loopback_host("split.example") is False
        with pytest.raises(PolicyError, match="loopback and non-loopback"):
            check_url("http://split.example:3000/")

    def test_a_name_that_does_not_resolve_is_refused(self, resolves) -> None:
        resolves({})
        with pytest.raises(PolicyError, match="does not resolve"):
            check_url("http://nowhere.invalid:3000/")

    @pytest.mark.parametrize("literal", ["127.0.0.1", "[::1]"])
    def test_an_address_literal_needs_no_resolver(self, literal: str) -> None:
        assert is_loopback_host(literal) is True


class TestRedirects:
    """Policy is re-applied to redirect targets, not only the original URL."""

    def _handler(self) -> urllib.request.HTTPRedirectHandler:
        opener = open_url.__globals__["_PolicyRedirectHandler"]
        return opener(allow_remote=False, allowed_ports=DEFAULT_ALLOWED_PORTS)

    def test_a_redirect_off_loopback_is_refused(self) -> None:
        request = urllib.request.Request("http://localhost:3000/api")
        with pytest.raises(PolicyError, match="non-loopback"):
            self._handler().redirect_request(
                request, None, 302, "Found", {}, f"http://{GLOBAL_ADDRESS}/"
            )

    def test_a_redirect_to_a_file_url_is_refused(self) -> None:
        request = urllib.request.Request("http://localhost:3000/api")
        with pytest.raises(PolicyError, match="scheme"):
            self._handler().redirect_request(request, None, 302, "Found", {}, "file:///etc/passwd")

    def test_a_redirect_to_an_unrelated_local_port_is_refused(self) -> None:
        request = urllib.request.Request("http://localhost:3000/api")
        with pytest.raises(PolicyError, match="local port"):
            self._handler().redirect_request(
                request, None, 302, "Found", {}, "http://localhost:22/"
            )

    def test_open_url_refuses_before_opening_anything(self, monkeypatch) -> None:
        opened: list[str] = []
        monkeypatch.setattr(
            urllib.request.OpenerDirector,
            "open",
            lambda self, *a, **k: opened.append("opened"),
        )
        with pytest.raises(PolicyError):
            open_url("http://evil.example.com/")
        assert opened == [], "a refused URL still reached the opener"


class TestProxyNeutralization:
    """A permitted loopback request is not routed through an ambient proxy.

    `build_opener` adds to the default handler chain, so the default
    `ProxyHandler` is installed unless an empty one is passed explicitly.
    `proxy_bypass` does not exempt loopback, so without that the request goes
    to whatever `HTTP_PROXY` names -- carrying the Grafana Basic credential
    that `validate_dashboard` attaches. `no_proxy` is cleared here on purpose:
    an environment where it already covers loopback would pass either way.
    """

    def _built_opener(self, monkeypatch) -> urllib.request.OpenerDirector:
        monkeypatch.setenv("HTTP_PROXY", "http://proxy.invalid:3128")
        monkeypatch.setenv("http_proxy", "http://proxy.invalid:3128")
        monkeypatch.setenv("NO_PROXY", "")
        monkeypatch.setenv("no_proxy", "")
        captured: list[urllib.request.OpenerDirector] = []
        monkeypatch.setattr(
            urllib.request.OpenerDirector,
            "open",
            lambda self, *a, **k: captured.append(self),
        )
        open_url("http://127.0.0.1:3000/api/health")
        return captured[0]

    def test_the_built_opener_carries_no_proxy_configuration(self, monkeypatch) -> None:
        opener = self._built_opener(monkeypatch)
        configured = {
            scheme: target
            for handler in opener.handlers
            if isinstance(handler, urllib.request.ProxyHandler)
            for scheme, target in handler.proxies.items()
        }
        assert configured == {}, f"open_url would proxy loopback traffic to {configured}"

    def test_the_built_opener_keeps_the_policy_redirect_handler(self, monkeypatch) -> None:
        policy_handler = open_url.__globals__["_PolicyRedirectHandler"]
        opener = self._built_opener(monkeypatch)
        assert any(isinstance(handler, policy_handler) for handler in opener.handlers), (
            "the redirect allow-list re-check and cross-origin credential stripping were dropped"
        )


class TestPathContainment:
    """A configurable path cannot escape its root."""

    def test_a_contained_relative_path_resolves(self, tmp_path: pathlib.Path) -> None:
        assert contain_path("snapshot.json", tmp_path) == (tmp_path / "snapshot.json").resolve()

    def test_traversal_is_refused(self, tmp_path: pathlib.Path) -> None:
        with pytest.raises(PolicyError):
            contain_path("../../etc/passwd", tmp_path)

    def test_an_absolute_path_outside_the_root_is_refused(self, tmp_path: pathlib.Path) -> None:
        outside = tmp_path.parent / "outside.json"
        with pytest.raises(PolicyError):
            contain_path(outside, tmp_path)

    def test_a_symlink_pointing_outside_the_root_is_refused(self, tmp_path: pathlib.Path) -> None:
        root = tmp_path / "root"
        root.mkdir()
        target = tmp_path / "outside"
        target.mkdir()
        link = root / "escape"
        try:
            link.symlink_to(target, target_is_directory=True)
        except (OSError, NotImplementedError):
            pytest.skip("symlink creation is not permitted in this environment")
        with pytest.raises(PolicyError):
            contain_path(link / "snapshot.json", root)

    def test_the_root_itself_is_allowed(self, tmp_path: pathlib.Path) -> None:
        assert contain_path(tmp_path, tmp_path) == tmp_path.resolve()


class TestCredentials:
    """Missing configuration is reported as configuration, before any request."""

    def test_both_missing_variables_are_named(self, monkeypatch) -> None:
        monkeypatch.delenv("COPILOT_OTEL_GRAFANA_USER", raising=False)
        monkeypatch.delenv("COPILOT_OTEL_GRAFANA_PASSWORD", raising=False)
        with pytest.raises(PolicyError) as excinfo:
            require_credentials("COPILOT_OTEL_GRAFANA_USER", "COPILOT_OTEL_GRAFANA_PASSWORD")
        assert "COPILOT_OTEL_GRAFANA_USER" in str(excinfo.value)
        assert "COPILOT_OTEL_GRAFANA_PASSWORD" in str(excinfo.value)

    def test_a_single_missing_variable_is_named(self, monkeypatch) -> None:
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_USER", "admin")
        monkeypatch.delenv("COPILOT_OTEL_GRAFANA_PASSWORD", raising=False)
        with pytest.raises(PolicyError, match="COPILOT_OTEL_GRAFANA_PASSWORD"):
            require_credentials("COPILOT_OTEL_GRAFANA_USER", "COPILOT_OTEL_GRAFANA_PASSWORD")

    def test_an_empty_value_counts_as_missing(self, monkeypatch) -> None:
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_USER", "admin")
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_PASSWORD", "")
        with pytest.raises(PolicyError, match="COPILOT_OTEL_GRAFANA_PASSWORD"):
            require_credentials("COPILOT_OTEL_GRAFANA_USER", "COPILOT_OTEL_GRAFANA_PASSWORD")

    def test_supplied_credentials_are_returned_in_order(self, monkeypatch) -> None:
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_USER", "operator")
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_PASSWORD", "chosen-by-the-user")
        assert require_credentials(
            "COPILOT_OTEL_GRAFANA_USER", "COPILOT_OTEL_GRAFANA_PASSWORD"
        ) == ("operator", "chosen-by-the-user")


def run_helper(
    name: str, args: list[str], env_overrides: dict[str, str]
) -> subprocess.CompletedProcess[str]:
    """Run a bundled helper in its own process with a controlled environment.

    A refusal exits before argparse and before any socket is opened. Running
    the helpers as processes is what proves the wiring; importing the policy
    module directly would only re-test the module these tests already cover.
    """
    env = dict(os.environ)
    env.update(env_overrides)
    env["COPILOT_OTEL_ALLOW_REMOTE"] = "0"
    return subprocess.run(
        [sys.executable, str(EXAMPLES_DIR / name), *args],
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
        cwd=str(EXAMPLES_DIR),
        check=False,
    )


class TestHelperWiring:
    """Each helper actually calls the shared policy, not merely imports it.

    Without these, deleting a `contain_path` call from a helper would leave the
    policy tests above green while restoring the exact write this change closed.
    """

    def test_baseline_refuses_a_snapshot_path_outside_the_cache_root(
        self, tmp_path: pathlib.Path
    ) -> None:
        target = tmp_path / "escaped-snapshot.json"
        result = run_helper("baseline.py", ["capture"], {"COPILOT_OTEL_BASELINE": str(target)})
        assert result.returncode != 0
        assert "refusing a path outside" in (result.stderr + result.stdout)
        assert not target.exists(), "a refused snapshot path was still written"

    def test_baseline_refuses_a_traversal_snapshot_path(self, tmp_path: pathlib.Path) -> None:
        result = run_helper(
            "baseline.py", ["capture"], {"COPILOT_OTEL_BASELINE": "../../escaped.json"}
        )
        assert result.returncode != 0
        assert "refusing a path outside" in (result.stderr + result.stdout)

    def test_validate_dashboard_reports_a_malformed_dashboard_without_a_traceback(
        self, tmp_path: pathlib.Path
    ) -> None:
        broken = tmp_path / "generated-dashboard.json"
        broken.write_text("{not json", encoding="utf-8")
        result = run_helper(
            "validate_dashboard.py",
            [str(broken)],
            {
                "COPILOT_OTEL_GRAFANA_USER": "operator",
                "COPILOT_OTEL_GRAFANA_PASSWORD": "chosen-by-the-user",
            },
        )
        assert result.returncode == 1
        combined = result.stderr + result.stdout
        assert "not valid JSON" in combined
        assert "Traceback" not in combined

    def test_validate_dashboard_refuses_a_non_loopback_endpoint_without_opt_in(self) -> None:
        result = run_helper(
            "validate_dashboard.py",
            [],
            {
                "COPILOT_OTEL_GRAFANA": f"https://{GLOBAL_ADDRESS}:3000",
                "COPILOT_OTEL_GRAFANA_USER": "operator",
                "COPILOT_OTEL_GRAFANA_PASSWORD": "chosen-by-the-user",
            },
        )
        assert result.returncode != 0
        assert "non-loopback" in (result.stderr + result.stdout)

    def test_validate_dashboard_refuses_an_unguarded_query_endpoint(self) -> None:
        """The Prometheus override was previously unchecked entirely."""
        result = run_helper(
            "validate_dashboard.py",
            [],
            {
                "COPILOT_OTEL_PROMETHEUS": f"http://{GLOBAL_ADDRESS}:9090",
                "COPILOT_OTEL_GRAFANA_USER": "operator",
                "COPILOT_OTEL_GRAFANA_PASSWORD": "chosen-by-the-user",
            },
        )
        assert result.returncode != 0
        assert "non-loopback" in (result.stderr + result.stdout)

    def test_validate_dashboard_reports_missing_credentials_as_configuration(self) -> None:
        result = run_helper(
            "validate_dashboard.py",
            [],
            {"COPILOT_OTEL_GRAFANA_USER": "", "COPILOT_OTEL_GRAFANA_PASSWORD": ""},
        )
        assert result.returncode != 0
        combined = result.stderr + result.stdout
        assert "COPILOT_OTEL_GRAFANA_USER" in combined
        assert "COPILOT_OTEL_GRAFANA_PASSWORD" in combined


class TestDashboardSelection:
    """A generated dashboard is the normal subject, not an intrusion.

    Confining the argument to the installed skill directory made the workflow
    the README documents impossible: the dashboard worth checking is usually
    one that was just produced somewhere else. What replaces the containment
    check is a controlled failure for every way a selected file can be wrong.
    """

    def _dashboard(self) -> dict:
        return {"panels": [{"title": "one", "type": "row"}]}

    def test_a_generated_dashboard_outside_the_skill_is_accepted(
        self, tmp_path: pathlib.Path
    ) -> None:
        generated = tmp_path / "generated.json"
        generated.write_text(json.dumps(self._dashboard()), encoding="utf-8")
        assert validate_dashboard.load_dashboard(str(generated)) == self._dashboard()

    def test_a_relative_path_resolves_against_the_current_directory(
        self, tmp_path: pathlib.Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        (tmp_path / "generated.json").write_text(json.dumps(self._dashboard()), encoding="utf-8")
        monkeypatch.chdir(tmp_path)
        assert validate_dashboard.load_dashboard("generated.json") == self._dashboard()

    def test_the_bundled_dashboard_is_the_default(self) -> None:
        assert validate_dashboard.load_dashboard(None)["panels"]

    def test_a_missing_file_is_reported_as_a_missing_file(self, tmp_path: pathlib.Path) -> None:
        with pytest.raises(PolicyError, match="no dashboard at"):
            validate_dashboard.load_dashboard(str(tmp_path / "absent.json"))

    def test_a_directory_is_reported_as_a_directory(self, tmp_path: pathlib.Path) -> None:
        with pytest.raises(PolicyError, match="not a dashboard file"):
            validate_dashboard.load_dashboard(str(tmp_path))

    def test_invalid_json_is_reported_as_invalid_json(self, tmp_path: pathlib.Path) -> None:
        broken = tmp_path / "broken.json"
        broken.write_text("{not json", encoding="utf-8")
        with pytest.raises(PolicyError, match="not valid JSON"):
            validate_dashboard.load_dashboard(str(broken))

    @pytest.mark.parametrize("content", ["[]", '{"title": "no panels"}', '{"panels": {}}'])
    def test_json_that_is_not_a_dashboard_is_reported_as_such(
        self, tmp_path: pathlib.Path, content: str
    ) -> None:
        candidate = tmp_path / "not-a-dashboard.json"
        candidate.write_text(content, encoding="utf-8")
        with pytest.raises(PolicyError, match="no panels array"):
            validate_dashboard.load_dashboard(str(candidate))


def _json_response(payload: dict) -> io.BytesIO:
    """A minimal stand-in for what open_url returns."""
    return io.BytesIO(json.dumps(payload).encode("utf-8"))


# Shaped to satisfy every reader in validate_dashboard at once: a Grafana
# import result, a Prometheus query result, a Prometheus label listing, a Tempo
# search result, and a TraceQL metrics result.
_ANY_STORE_RESPONSE = {
    "status": "success",
    "url": "/d/copilot-otel/copilot",
    "data": {"result": []},
    "traces": [],
    "series": [],
}


class TestGrafanaCredentialLiveness:
    """`verify.py` reports which admin credential is live, not only whether ours works.

    Grafana applies `GF_SECURITY_ADMIN_*` only when it creates its database, so
    a stack on a pre-existing database can be running on `admin`/`admin` while
    the configured pair was supplied and ignored. A check that tried only the
    configured pair would report that as a mismatch rather than as a live
    default credential, which is the condition worth failing the run for.
    """

    @pytest.fixture(autouse=True)
    def _isolated_results(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setattr(verify, "results", [])

    def _probe(self, monkeypatch: pytest.MonkeyPatch, answers: dict) -> None:
        monkeypatch.setattr(
            verify, "grafana_accepts", lambda user, password: answers.get((user, password), False)
        )

    def _outcome(self, name: str) -> tuple[bool, str]:
        return next((ok, detail) for recorded, ok, detail in verify.results if recorded == name)

    def _configure(self, monkeypatch: pytest.MonkeyPatch, user: str, password: str) -> None:
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_USER", user)
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_PASSWORD", password)

    def test_an_adopted_credential_passes_both_checks(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._configure(monkeypatch, "operator", "chosen-by-the-user")
        self._probe(monkeypatch, {("operator", "chosen-by-the-user"): True})
        verify.check_grafana_credentials()
        assert self._outcome("configured grafana credential works")[0] is True
        assert self._outcome("grafana default credential inactive")[0] is True

    def test_a_live_default_credential_is_reported_as_such(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._configure(monkeypatch, "operator", "chosen-by-the-user")
        self._probe(monkeypatch, {("admin", "admin"): True})
        verify.check_grafana_credentials()
        ok, detail = self._outcome("grafana default credential inactive")
        assert ok is False
        assert "admin/admin authenticates" in detail

    def test_a_rejected_configured_credential_is_reported_separately(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._configure(monkeypatch, "operator", "chosen-by-the-user")
        self._probe(monkeypatch, {("admin", "admin"): True})
        verify.check_grafana_credentials()
        ok, detail = self._outcome("configured grafana credential works")
        assert ok is False
        assert "database predates this password" in detail

    def test_an_unanswered_probe_is_not_reported_as_a_rejection(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._configure(monkeypatch, "operator", "chosen-by-the-user")
        monkeypatch.setattr(verify, "grafana_accepts", lambda user, password: None)
        verify.check_grafana_credentials()
        assert "no answer from Grafana" in self._outcome("configured grafana credential works")[1]

    def test_missing_configuration_is_named_rather_than_probed(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("COPILOT_OTEL_GRAFANA_USER", raising=False)
        monkeypatch.delenv("COPILOT_OTEL_GRAFANA_PASSWORD", raising=False)
        self._probe(monkeypatch, {})
        verify.check_grafana_credentials()
        ok, detail = self._outcome("configured grafana credential works")
        assert ok is False
        assert "are not both set" in detail

    def test_configuring_the_default_pair_fails_the_default_check(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        self._configure(monkeypatch, "admin", "admin")
        self._probe(monkeypatch, {("admin", "admin"): True})
        verify.check_grafana_credentials()
        ok, detail = self._outcome("grafana default credential inactive")
        assert ok is False
        assert "is the image default" in detail


class TestGrafanaCredentialScope:
    """The Grafana credential reaches Grafana and nothing else.

    The defect this replaces was a shared request builder that attached the
    header unconditionally. Five of the six call sites address Prometheus or
    Tempo, neither of which authenticates against Grafana, so every panel
    replay handed a third-party store an admin credential for a fourth.
    """

    def test_a_request_built_without_a_credential_carries_no_authorization(self) -> None:
        request = validate_dashboard.build_request("http://localhost:9090/api/v1/query")
        assert "Authorization" not in request.headers

    def test_a_request_built_with_a_credential_carries_it(self) -> None:
        request = validate_dashboard.build_request(
            "http://localhost:3000/api/dashboards/db",
            b"{}",
            "POST",
            authorization="Basic supplied-at-the-call-site",
        )
        assert request.headers["Authorization"] == "Basic supplied-at-the-call-site"

    def test_only_the_grafana_request_carries_the_credential_end_to_end(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Drive the real tool and inspect every request it actually builds.

        This is the assertion that covers all six call sites rather than a
        representative one: the shipped dashboard is walked, every panel query
        is issued, and each resulting request object is inspected.
        """
        sent: list[urllib.request.Request] = []

        def fake_open_url(request, **kwargs):  # noqa: ANN001, ANN202
            sent.append(request)
            return _json_response(_ANY_STORE_RESPONSE)

        monkeypatch.setattr(validate_dashboard, "open_url", fake_open_url)
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_USER", "operator")
        monkeypatch.setenv("COPILOT_OTEL_GRAFANA_PASSWORD", "chosen-by-the-user")
        monkeypatch.delenv("COPILOT_OTEL_ALLOW_REMOTE", raising=False)

        assert validate_dashboard.main([]) == 0

        authorized = [r for r in sent if "Authorization" in r.headers]
        assert len(sent) > 1, "the dashboard walk issued no store queries"
        assert len(authorized) == 1, (
            f"exactly one request may carry the Grafana credential; {len(authorized)} did"
        )
        assert authorized[0].full_url.startswith("http://localhost:3000/")
        for request in sent:
            if request is authorized[0]:
                continue
            assert "Authorization" not in request.headers, (
                f"{request.full_url} received the Grafana credential"
            )


class TestRedirectCredentialHandling:
    """A redirect may not carry a credential to an origin it was not issued for."""

    def _handler(self, *, allow_remote: bool = False) -> urllib.request.HTTPRedirectHandler:
        handler = open_url.__globals__["_PolicyRedirectHandler"]
        return handler(allow_remote=allow_remote, allowed_ports=DEFAULT_ALLOWED_PORTS)

    def _redirect(
        self, start: str, target: str, *, allow_remote: bool = False
    ) -> urllib.request.Request:
        request = urllib.request.Request(start)
        request.add_header("Authorization", "Basic issued-for-the-original-origin")
        request.add_header("Proxy-Authorization", "Basic proxy")
        request.add_header("Cookie", "session=abc")
        request.add_header("Accept", "application/json")
        return self._handler(allow_remote=allow_remote).redirect_request(
            request, None, 302, "Found", {}, target
        )

    @pytest.mark.parametrize("header", ["Authorization", "Proxy-Authorization", "Cookie"])
    def test_a_redirect_to_another_local_port_drops_each_credential_header(
        self, header: str
    ) -> None:
        redirected = self._redirect("http://localhost:3000/api", "http://localhost:9090/api")
        assert not any(name.lower() == header.lower() for name in redirected.headers)

    def test_a_same_origin_redirect_keeps_the_credential(self) -> None:
        redirected = self._redirect("http://localhost:3000/api", "http://localhost:3000/other")
        assert redirected.headers["Authorization"] == "Basic issued-for-the-original-origin"

    def test_an_explicit_default_port_is_the_same_origin(self, resolves) -> None:
        """`https://h/x` and `https://h:443/y` are one origin, not two."""
        resolves({"grafana.example.com": [GLOBAL_ADDRESS]})
        redirected = self._redirect(
            "https://grafana.example.com/api",
            "https://grafana.example.com:443/other",
            allow_remote=True,
        )
        assert redirected.headers["Authorization"] == "Basic issued-for-the-original-origin"

    def test_a_different_remote_host_drops_the_credential(self, resolves) -> None:
        resolves(
            {
                "grafana.example.com": [GLOBAL_ADDRESS],
                "someone-else.example.com": [GLOBAL_ADDRESS],
            }
        )
        redirected = self._redirect(
            "https://grafana.example.com/api",
            "https://someone-else.example.com/api",
            allow_remote=True,
        )
        assert "Authorization" not in redirected.headers

    def test_a_different_remote_port_drops_the_credential(self, resolves) -> None:
        resolves({"grafana.example.com": [GLOBAL_ADDRESS]})
        redirected = self._redirect(
            "https://grafana.example.com/api",
            "https://grafana.example.com:9090/api",
            allow_remote=True,
        )
        assert "Authorization" not in redirected.headers

    def test_a_non_credential_header_survives_an_origin_change(self) -> None:
        redirected = self._redirect("http://localhost:3000/api", "http://localhost:9090/api")
        assert redirected.headers["Accept"] == "application/json"

    def test_the_credential_headers_are_dropped_together(self) -> None:
        redirected = self._redirect("http://localhost:3000/api", "http://localhost:9090/api")
        remaining = {name.lower() for name in redirected.headers}
        assert remaining.isdisjoint({"authorization", "proxy-authorization", "cookie"})


class TestOriginNormalization:
    """Origin comparison is the mechanism the redirect rule rests on."""

    @pytest.mark.parametrize(
        ("one", "other"),
        [
            ("http://h/a", "http://h:80/b"),
            ("https://h/a", "https://h:443/b"),
            ("http://H/a", "http://h/b"),
        ],
    )
    def test_equivalent_urls_share_an_origin(self, one: str, other: str) -> None:
        assert origin_of(one) == origin_of(other)

    @pytest.mark.parametrize(
        ("one", "other"),
        [
            ("http://h/a", "https://h/a"),
            ("http://h/a", "http://other/a"),
            ("http://h:3000/a", "http://h:9090/a"),
        ],
    )
    def test_different_urls_have_different_origins(self, one: str, other: str) -> None:
        assert origin_of(one) != origin_of(other)


class TestPolicyRoutedHelpers:
    """Both previously bypassing helpers reach the network only through policy.

    Their endpoints are loopback constants today, so the bypass was not
    currently exploitable. It was a maintenance defect: a later endpoint change
    in either file would have escaped every control the other helpers inherit.
    """

    @pytest.mark.parametrize("module", [verify, inspect_metrics], ids=lambda m: m.__name__)
    def test_the_helper_reaches_http_through_the_policy_boundary(
        self, module, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        opened: list[str] = []

        def fake_open_url(url, **kwargs):  # noqa: ANN001, ANN202
            opened.append(url)
            return _json_response({"data": []})

        monkeypatch.setattr(module, "open_url", fake_open_url)
        module.api(module.PROM, "/api/v1/label/__name__/values")
        assert opened == ["http://localhost:9090/api/v1/label/__name__/values"]

    @pytest.mark.parametrize(
        "name", ["verify.py", "inspect_metrics.py", "validate_dashboard.py", "baseline.py"]
    )
    def test_no_bundled_helper_opens_a_url_outside_the_policy_module(self, name: str) -> None:
        source = (EXAMPLES_DIR / name).read_text(encoding="utf-8")
        assert "urlopen(" not in source, (
            f"{name} opens a URL directly; every helper must go through open_url "
            "so scheme, authority, port, redirect, and remote-opt-in rules apply"
        )
