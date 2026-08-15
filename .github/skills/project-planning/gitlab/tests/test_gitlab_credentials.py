# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Tests for GitLab OAuth profile persistence."""

from __future__ import annotations

import json
import os
import pathlib
import threading
import time

import _gitlab_credentials as credentials
import pytest


def _profile() -> credentials.Profile:
    return {
        "issuer": "https://gitlab.example.com",
        "client_id": "client",
        "access_token": "access",
        "refresh_token": "refresh",
        "token_type": "Bearer",
        "obtained_at": 1,
        "expires_at": 2,
        "scopes": ["api"],
        "usable": True,
    }


def test_store_round_trip_uses_private_directory_and_mode_0600(
    tmp_path: pathlib.Path,
) -> None:
    path = tmp_path / "gitlab" / "gitlab-token.json"
    store = {"schema_version": 1, "profiles": {"default": _profile()}}

    credentials.save_store(path, store)

    assert credentials.load_store(path) == store
    if os.name != "nt":
        assert path.stat().st_mode & 0o777 == 0o600
        assert path.parent.stat().st_mode & 0o777 == 0o700


def test_load_store_rejects_unsafe_permissions(tmp_path: pathlib.Path) -> None:
    if os.name == "nt":
        pytest.skip("POSIX permission semantics")
    path = tmp_path / "gitlab-token.json"
    path.write_text(json.dumps({"schema_version": 1, "profiles": {}}))
    path.chmod(0o644)

    with pytest.raises(credentials.CredentialSecurityError, match="owned by the user"):
        credentials.load_store(path)


def test_save_store_rejects_unsafe_existing_parent(tmp_path: pathlib.Path) -> None:
    if os.name == "nt":
        pytest.skip("POSIX permission semantics")
    parent = tmp_path / "shared"
    parent.mkdir(mode=0o755)
    parent.chmod(0o755)
    path = parent / "gitlab-token.json"

    with pytest.raises(
        credentials.CredentialSecurityError,
        match="directory must be owned",
    ):
        credentials.save_store(
            path,
            {"schema_version": 1, "profiles": {"default": _profile()}},
        )


def test_load_store_rejects_symlink(tmp_path: pathlib.Path) -> None:
    if os.name == "nt" or not hasattr(os, "O_NOFOLLOW"):
        pytest.skip("POSIX no-follow semantics")
    target = tmp_path / "target.json"
    target.write_text(json.dumps({"schema_version": 1, "profiles": {}}))
    target.chmod(0o600)
    link = tmp_path / "gitlab-token.json"
    link.symlink_to(target)

    with pytest.raises(credentials.CredentialSecurityError, match="opened safely"):
        credentials.load_store(link)


def test_load_store_normalizes_invalid_utf8(tmp_path: pathlib.Path) -> None:
    path = tmp_path / "gitlab-token.json"
    path.write_bytes(b"\xff")
    path.chmod(0o600)

    with pytest.raises(credentials.CredentialValidationError, match="valid JSON"):
        credentials.load_store(path)


def test_windows_store_fails_closed_before_filesystem_access(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: pathlib.Path,
) -> None:
    monkeypatch.setattr(credentials.os, "name", "nt")
    opened: list[object] = []
    monkeypatch.setattr(
        credentials.os,
        "open",
        lambda *_args, **_kwargs: opened.append(True),
    )

    with pytest.raises(credentials.CredentialSecurityError, match="unavailable"):
        credentials.load_store(tmp_path / "gitlab-token.json")

    assert opened == []


def _raise_inside_store_lock(path: pathlib.Path) -> None:
    """Raise from inside a held store lock so the caller can assert release."""
    with credentials.store_lock(path):
        raise RuntimeError("boom")


def test_store_lock_releases_after_body_error(tmp_path: pathlib.Path) -> None:
    path = tmp_path / "gitlab" / "gitlab-token.json"

    with pytest.raises(RuntimeError, match="boom"):
        _raise_inside_store_lock(path)

    reacquired = False
    with credentials.store_lock(path):
        reacquired = True

    assert reacquired, "store_lock must be re-acquirable after its body raised"


def test_store_lock_serializes_threads(tmp_path: pathlib.Path) -> None:
    path = tmp_path / "gitlab" / "gitlab-token.json"
    entered: list[int] = []
    first_entered = threading.Event()
    release_first = threading.Event()

    def worker(identifier: int) -> None:
        with credentials.store_lock(path):
            entered.append(identifier)
            if identifier == 1:
                first_entered.set()
                release_first.wait(timeout=2)

    first = threading.Thread(target=worker, args=(1,))
    second = threading.Thread(target=worker, args=(2,))
    first.start()
    first_entered.wait(timeout=1)
    second.start()
    time.sleep(0.05)
    assert entered == [1]
    release_first.set()
    first.join(timeout=1)
    second.join(timeout=1)

    assert entered == [1, 2]


def test_save_failure_preserves_existing_store(
    tmp_path: pathlib.Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    path = tmp_path / "gitlab" / "gitlab-token.json"
    original = {"schema_version": 1, "profiles": {"default": _profile()}}
    credentials.save_store(path, original)
    monkeypatch.setattr(
        credentials.os,
        "replace",
        lambda *_args: (_ for _ in ()).throw(OSError("disk failure")),
    )

    with pytest.raises(credentials.CredentialSecurityError, match="written safely"):
        credentials.save_store(
            path,
            {"schema_version": 1, "profiles": {}},
        )

    assert credentials.load_store(path) == original


def test_default_store_path_uses_dedicated_private_leaf(
    tmp_path: pathlib.Path,
) -> None:
    path = credentials.resolve_store_path({"XDG_DATA_HOME": str(tmp_path)})

    assert path == tmp_path / "hve-core" / "gitlab" / "gitlab-token.json"


@pytest.mark.parametrize("name", ["", ".bad", "bad/name", "bad name", "x" * 33])
def test_validate_profile_name_rejects_unsafe(name: str) -> None:
    with pytest.raises(ValueError):
        credentials.validate_profile_name(name)


def test_profile_binding_fields_are_required() -> None:
    profile: dict[str, object] = dict(_profile())
    profile.pop("issuer")

    with pytest.raises(ValueError, match="missing keys"):
        credentials.validate_profile(profile)


def test_profile_issuer_must_be_origin_only() -> None:
    profile = _profile()
    profile["issuer"] = "https://gitlab.example.com/attacker"

    with pytest.raises(
        credentials.CredentialValidationError,
        match="origin-only",
    ):
        credentials.validate_profile(profile)


def test_delete_profile_reports_presence() -> None:
    store = {"schema_version": 1, "profiles": {"default": _profile()}}

    assert credentials.delete_profile(store, "default") is True
    assert credentials.delete_profile(store, "default") is False
