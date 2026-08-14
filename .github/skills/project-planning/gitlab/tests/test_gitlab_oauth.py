# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for GitLab public-client OAuth helpers."""

from __future__ import annotations

import http.client
import json
import socket
import threading
import urllib.error

import _gitlab_oauth as oauth
import pytest


class _Response:
    def __init__(self, payload: dict[str, object]) -> None:
        self.headers = {"Content-Type": "application/json"}
        self._body = json.dumps(payload).encode()

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *_args: object) -> bool:
        return False

    def read(self, _amount: int = -1) -> bytes:
        return self._body


def test_pkce_pair_is_s256_and_has_no_secret() -> None:
    verifier, challenge = oauth.generate_pkce_pair()
    url = oauth.build_authorize_url(
        "https://gitlab.example.com", "client", "state", challenge
    )

    assert 43 <= len(verifier) <= 128
    assert "code_challenge_method=S256" in url
    assert "client_secret" not in url


def test_token_profile_requires_rotating_refresh_token() -> None:
    with pytest.raises(oauth.OAuthError, match="refresh_token"):
        oauth.token_profile(
            {"access_token": "access", "expires_in": 7200},
            issuer="https://gitlab.example.com",
            client_id="client",
            now=100.0,
        )


def test_token_profile_uses_provider_expiry() -> None:
    profile = oauth.token_profile(
        {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 7200,
            "scope": "api",
        },
        issuer="https://gitlab.example.com",
        client_id="client",
        now=100.0,
    )

    assert profile["expires_at"] == 7300
    assert profile["scopes"] == ["api"]


@pytest.mark.parametrize(
    "payload",
    [
        {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": oauth.MAX_EXPIRES_IN_SECONDS + 1,
        },
        {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 7200,
            "token_type": "MAC",
        },
    ],
)
def test_token_profile_rejects_unbounded_or_unsupported_tokens(
    payload: dict[str, object],
) -> None:
    with pytest.raises(oauth.OAuthError):
        oauth.token_profile(
            payload,
            issuer="https://gitlab.example.com",
            client_id="client",
            now=100.0,
        )


def test_device_login_honors_pending_and_slow_down() -> None:
    responses: list[object] = [
        _Response(
            {
                "device_code": "device-secret",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://gitlab.example.com/oauth/device",
                "expires_in": 300,
                "interval": 5,
            }
        ),
        oauth.OAuthError(
            "GitLab OAuth request failed: authorization_pending",
            code="authorization_pending",
        ),
        oauth.OAuthError(
            "GitLab OAuth request failed: slow_down",
            code="slow_down",
        ),
        _Response(
            {
                "access_token": "access",
                "expires_in": 7200,
                "scope": "api",
            }
        ),
    ]
    times = [0.0]
    sleeps: list[float] = []

    def opener(*_args: object, **_kwargs: object) -> object:
        response = responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def sleep(seconds: float) -> None:
        sleeps.append(seconds)
        times[0] += seconds

    profile = oauth.device_login(
        "https://gitlab.example.com",
        "client",
        opener=opener,
        timeout=300,
        emit_instructions=lambda _uri, _code: None,
        now=lambda: times[0],
        monotonic=lambda: times[0],
        sleep=sleep,
    )

    assert profile["access_token"] == "access"
    assert profile["refresh_token"] == ""
    assert sleeps == [5, 5, 10]


def test_device_login_does_not_poll_past_deadline() -> None:
    responses: list[object] = [
        _Response(
            {
                "device_code": "device-secret",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://gitlab.example.com/oauth/device",
                "expires_in": 4,
                "interval": 10,
            }
        ),
        oauth.OAuthError("pending", code="authorization_pending"),
    ]
    times = [0.0]
    sleeps: list[float] = []

    def opener(*_args: object, **_kwargs: object) -> object:
        response = responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response

    def sleep(seconds: float) -> None:
        sleeps.append(seconds)
        times[0] += seconds

    with pytest.raises(oauth.OAuthError, match="timed out"):
        oauth.device_login(
            "https://gitlab.example.com",
            "client",
            opener=opener,
            timeout=300,
            emit_instructions=lambda _uri, _code: None,
            now=lambda: times[0],
            monotonic=lambda: times[0],
            sleep=sleep,
        )

    assert sleeps == [4]
    assert len(responses) == 1


def test_post_form_preserves_provider_error_code_and_retryability() -> None:
    error = urllib.error.HTTPError(
        url="https://gitlab.example.com/oauth/token",
        code=503,
        msg="unavailable",
        hdrs={"Content-Type": "application/json"},
        fp=None,
    )
    error.read = lambda _amount=-1: b'{"error":"temporarily_unavailable"}'  # type: ignore[method-assign]

    with pytest.raises(oauth.OAuthError) as exc_info:
        oauth.post_form(
            "https://gitlab.example.com",
            "/oauth/token",
            {"grant_type": "refresh_token"},
            opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(error),
            timeout=30,
            operation="oauth.refresh",
        )

    assert exc_info.value.code == "temporarily_unavailable"
    assert exc_info.value.retryable is True
    assert exc_info.value.completion_uncertain is True


@pytest.mark.parametrize(
    ("error", "completion_uncertain"),
    [
        (TimeoutError("timed out"), True),
        (ConnectionResetError("reset"), True),
        (http.client.IncompleteRead(b"partial"), True),
        (http.client.BadStatusLine("bad"), True),
        (urllib.error.URLError(socket.gaierror("dns")), False),
        (urllib.error.URLError(ConnectionRefusedError("refused")), False),
    ],
)
def test_post_form_classifies_transport_failures(
    error: Exception,
    completion_uncertain: bool,
) -> None:
    with pytest.raises(oauth.OAuthError) as exc_info:
        oauth.post_form(
            "https://gitlab.example.com",
            "/oauth/token",
            {"grant_type": "refresh_token"},
            opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(error),
            timeout=30,
            operation="oauth.refresh",
        )

    assert exc_info.value.retryable is True
    assert exc_info.value.completion_uncertain is completion_uncertain
    assert exc_info.value.__cause__ is error


def test_refresh_profile_rejects_binding_mismatch_before_network() -> None:
    profile = oauth.token_profile(
        {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 7200,
        },
        issuer="https://gitlab.example.com",
        client_id="client",
        now=100.0,
    )

    with pytest.raises(oauth.OAuthError, match="not bound"):
        oauth.refresh_profile(
            profile,
            expected_issuer="https://other.example.com",
            expected_client_id="client",
            opener=lambda *_args, **_kwargs: (_ for _ in ()).throw(
                AssertionError("network must not run")
            ),
            timeout=30,
        )


def test_refresh_profile_marks_malformed_success_as_uncertain() -> None:
    profile = oauth.token_profile(
        {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_in": 7200,
        },
        issuer="https://gitlab.example.com",
        client_id="client",
        now=100.0,
    )

    with pytest.raises(oauth.OAuthError) as exc_info:
        oauth.refresh_profile(
            profile,
            expected_issuer="https://gitlab.example.com",
            expected_client_id="client",
            opener=lambda *_args, **_kwargs: _Response(
                {"access_token": "replacement", "expires_in": 7200}
            ),
            timeout=30,
        )

    assert exc_info.value.completion_uncertain is True


def test_authorization_login_converts_callback_bind_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        oauth,
        "_CallbackServer",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(OSError("in use")),
    )

    with pytest.raises(oauth.OAuthError, match="device-login"):
        oauth.authorization_code_login(
            "https://gitlab.example.com",
            "client",
            opener=lambda *_args, **_kwargs: None,
            timeout=1,
        )


def test_callback_ignores_wrong_path_then_accepts_valid_state(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    server = oauth._CallbackServer(
        (oauth.CALLBACK_HOST, 0),
        oauth._CallbackHandler,
    )
    server.callback_result = oauth._CallbackResult()
    server.callback_received = threading.Event()
    server.stop_requested = threading.Event()
    server.expected_state = "expected-state"
    port = server.server_address[1]
    monkeypatch.setattr(oauth, "CALLBACK_PORT", port)

    def serve_two_requests() -> None:
        for _ in range(2):
            server.handle_request()

    thread = threading.Thread(target=serve_two_requests)
    thread.start()
    try:
        wrong = http.client.HTTPConnection(oauth.CALLBACK_HOST, port, timeout=1)
        wrong.request("GET", "/wrong", headers={"Host": f"127.0.0.1:{port}"})
        assert wrong.getresponse().status == 404
        wrong.close()
        assert server.callback_received.is_set() is False

        valid = http.client.HTTPConnection(oauth.CALLBACK_HOST, port, timeout=1)
        valid.request(
            "GET",
            "/callback?code=authorization-code&state=expected-state",
            headers={"Host": f"127.0.0.1:{port}"},
        )
        assert valid.getresponse().status == 200
        valid.close()
        thread.join(timeout=1)
    finally:
        server.server_close()

    assert server.callback_received.is_set() is True
    assert server.callback_result.code == "authorization-code"


def test_callback_socket_has_bounded_read_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(oauth, "CALLBACK_REQUEST_TIMEOUT_SECONDS", 0.05)
    server = oauth._CallbackServer((oauth.CALLBACK_HOST, 0), oauth._CallbackHandler)
    port = server.server_address[1]
    peer = socket.create_connection((oauth.CALLBACK_HOST, port), timeout=1)

    thread = threading.Thread(target=server.handle_request)
    thread.start()
    thread.join(timeout=0.5)
    peer.close()
    server.server_close()

    assert thread.is_alive() is False


def test_device_login_uses_injected_monotonic_clock() -> None:
    responses: list[object] = [
        _Response(
            {
                "device_code": "device-secret",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://gitlab.example.com/oauth/device",
                "expires_in": 4,
                "interval": 10,
            }
        )
    ]
    elapsed = [0.0]

    def opener(*_args: object, **_kwargs: object) -> object:
        return responses.pop(0)

    def sleep(seconds: float) -> None:
        elapsed[0] += seconds

    with pytest.raises(oauth.OAuthError, match="timed out"):
        oauth.device_login(
            "https://gitlab.example.com",
            "client",
            opener=opener,
            timeout=300,
            emit_instructions=lambda _uri, _code: None,
            monotonic=lambda: elapsed[0],
            sleep=sleep,
        )

    assert elapsed == [4.0]
