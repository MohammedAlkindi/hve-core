# Copyright (c) 2026 Microsoft Corporation. All rights reserved.
# SPDX-License-Identifier: MIT
"""Scan authored content for guarded disclosure risks.

Deterministic, regex-based scanner that flags high-confidence PII and, for
public repositories, internal-only URLs/hostnames before durable writes or
external handoff emission. Optional data mode adds structured column,
connection, credential, sample-row, and international identifier detection.

Findings carry a ``confidence`` label:

* ``high`` -- PII or a public-repository internal URL that must block
    durable/external writes until redacted. Any high-confidence finding sets a
    non-zero exit.
* ``warn`` -- advisory matches that surface for review but do not block on
    their own.

Input may be one or more file paths or, when no paths are given, stdin. Output
is a JSON object on stdout with ``findings`` (a list) and summary counts.

Usage::

    python -m scripts.scan_sensitive_content <path> [<path> ...]
    python -m scripts.scan_sensitive_content --data --denylist terms.txt <path>
    cat adr.md | python -m scripts.scan_sensitive_content
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, NamedTuple

try:
    from ._utils import safe_resolve
except ImportError:  # executed directly as ``python scan_sensitive_content.py``
    from _utils import safe_resolve

EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_ERROR = 2

SKILL_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = SKILL_ROOT.parents[3] if len(SKILL_ROOT.parents) >= 4 else SKILL_ROOT

STDIN_SOURCE = "<stdin>"


class Rule(NamedTuple):
    """A named detection rule with a compiled pattern and confidence label."""

    category: str
    confidence: str
    pattern: re.Pattern[str]


# High-confidence PII blocks durable/external writes. Names and roles are not
# scanned because deterministic regexes produce too many false positives there.
RULES: tuple[Rule, ...] = (
    Rule(
        "email_address",
        "high",
        re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
    ),
    Rule(
        "phone_number",
        "high",
        re.compile(r"\b(?:\+?1[\s.-]?)?(?:\(?\d{3}\)?[\s.-]?)\d{3}[\s.-]?\d{4}\b"),
    ),
    Rule(
        "national_identifier",
        "high",
        re.compile(r"\b\d{3}-\d{2}-\d{4}\b"),
    ),
)


# Rules applied only when the target repository is public (``--public``).
# Internal-only URLs and hostnames are a leak concern only when the ADR or
# handoff content lands in a publicly visible repository; in a private repo
# they are expected operational references and flagging them is noise.
PUBLIC_ONLY_RULES: tuple[Rule, ...] = (
    Rule(
        "internal_url",
        "high",
        re.compile(
            r"https?://"
            r"(?:localhost|127\.0\.0\.1"
            r"|10\.\d{1,3}\.\d{1,3}\.\d{1,3}"
            r"|192\.168\.\d{1,3}\.\d{1,3}"
            r"|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}"
            r"|[A-Za-z0-9.-]+\.(?:corp|internal|local))"
            r"(?:[:/][^\s)\"']*)?",
            re.IGNORECASE,
        ),
    ),
)


# Rules applied only in data mode. Column-name and sample-row detection use
# dedicated structural scanners below so ordinary prose does not activate
# those heuristics.
DATA_ONLY_RULES: tuple[Rule, ...] = (
    Rule(
        "connection_string",
        "high",
        re.compile(
            r"\b(?:Server|Data\s+Source|Initial\s+Catalog|User\s+Id|Password)\s*="
            r"[^\r\n;]*(?:;[^\r\n;=]+=[^\r\n;]*)+",
            re.IGNORECASE,
        ),
    ),
    Rule(
        "jdbc_odbc_uri",
        "high",
        re.compile(r"\b(?:jdbc|odbc):[^\s\"']+", re.IGNORECASE),
    ),
    Rule(
        "db_uri_with_credentials",
        "high",
        re.compile(
            r"\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://"
            r"[^\s/@:]+:[^\s/@]+@[^\s\"']+",
            re.IGNORECASE,
        ),
    ),
    Rule(
        "storage_key",
        "high",
        re.compile(r"\bAccountKey\s*=\s*[A-Za-z0-9+/]{20,}={0,2}", re.IGNORECASE),
    ),
    Rule(
        "bearer_token",
        "high",
        re.compile(r"\bAuthorization\s*:\s*Bearer\s+[A-Za-z0-9._~+/-]{12,}", re.IGNORECASE),
    ),
    Rule(
        "uk_national_insurance",
        "warn",
        re.compile(r"\b[A-CEGHJ-PR-TW-Z]{2}\s?\d{2}\s?\d{2}\s?\d{2}\s?[A-D]\b", re.IGNORECASE),
    ),
    Rule(
        "canadian_sin",
        "warn",
        re.compile(r"\b\d{3}[ -]\d{3}[ -]\d{3}\b"),
    ),
    Rule(
        "international_phone",
        "warn",
        re.compile(r"(?<!\w)\+[2-9]\d{7,14}\b"),
    ),
)

HIGH_COLUMN_NAMES = frozenset(
    {
        "ssn",
        "social_security",
        "national_id",
        "passport",
        "tax_id",
        "drivers_license",
        "credit_card",
        "card_number",
        "cvv",
        "account_number",
        "routing_number",
    }
)
WARN_COLUMN_NAMES = frozenset(
    {
        "dob",
        "date_of_birth",
        "birth_date",
        "email",
        "phone",
        "address",
        "postal",
        "zip",
        "patient_id",
        "member_id",
        "mrn",
        "full_name",
        "first_name",
        "last_name",
        "salary",
        "compensation",
    }
)

STRUCTURED_COLUMN_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"^\s*-?\s*[\"']?(?:name|field|column)[\"']?\s*:\s*"
        r"[\"']?(?P<column>[A-Za-z][A-Za-z0-9_-]*)",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*[\"']?(?P<column>[A-Za-z][A-Za-z0-9_-]*)[\"']?\s*:",
        re.IGNORECASE,
    ),
    re.compile(
        r"^\s*[\"`\[]?(?P<column>[A-Za-z][A-Za-z0-9_-]*)[\"`\]]?\s+"
        r"(?:bigint|boolean|date|datetime|decimal|float|int|integer|numeric|"
        r"text|timestamp|varchar)\b",
        re.IGNORECASE,
    ),
)
INLINE_COLUMNS_PATTERN = re.compile(
    r"[\"']?(?:columns?|fields?)[\"']?\s*:\s*\[(?P<columns>[^\]]*)\]",
    re.IGNORECASE,
)
IDENTIFIER_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9_-]*")
SAMPLE_CONTEXT_PATTERN = re.compile(
    r"(?:^\s*#{1,6}\s*|^\s*[\"']?)(?:sample|example|preview)(?:\s+rows?|\s+data)?"
    r"(?:[\"']?\s*:|\s*$)",
    re.IGNORECASE,
)
MARKDOWN_TABLE_ROW_PATTERN = re.compile(r"^\s*\|(?:[^|]+\|){2,}\s*$")
JSON_ARRAY_PATTERN = re.compile(r"^\s*\[(?:[^\[\]]|\[[^\]]*\])*\]\s*,?\s*$")
SAS_URL_PATTERN = re.compile(r"https?://[^\s\"']+\?[^\s\"']+", re.IGNORECASE)


def _redact(match: str) -> str:
    """Return a masked preview of matched content for safe reporting."""
    stripped = match.strip()
    if len(stripped) <= 8:
        return stripped[0] + "***" if stripped else "***"
    return f"{stripped[:4]}***{stripped[-2:]}"


def _finding(
    source: str,
    line_number: int,
    column: int,
    category: str,
    confidence: str,
    match: str,
) -> dict[str, Any]:
    """Build one finding with a masked preview."""
    return {
        "source": source,
        "line": line_number,
        "column": column,
        "category": category,
        "confidence": confidence,
        "match": _redact(match),
    }


def _normalize_identifier(value: str) -> str:
    """Normalize snake, kebab, and camel-case identifiers for comparison."""
    value = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", value)
    return re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").lower()


def _scan_structured_columns(text: str, source: str) -> list[dict[str, Any]]:
    """Detect sensitive column names only in structured declarations."""
    findings: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        candidates: list[tuple[str, int]] = []
        for pattern in STRUCTURED_COLUMN_PATTERNS:
            match = pattern.search(line)
            if match:
                candidates.append((match.group("column"), match.start("column")))
                break
        inline = INLINE_COLUMNS_PATTERN.search(line)
        if inline:
            candidates.extend(
                (match.group(0), match.start())
                for match in IDENTIFIER_PATTERN.finditer(inline.group("columns"))
            )
        for candidate, column in candidates:
            normalized = _normalize_identifier(candidate)
            confidence = (
                "high"
                if normalized in HIGH_COLUMN_NAMES
                else "warn"
                if normalized in WARN_COLUMN_NAMES
                else None
            )
            if confidence:
                findings.append(
                    _finding(
                        source,
                        line_number,
                        column + 1,
                        "sensitive_column_name",
                        confidence,
                        candidate,
                    )
                )
    return findings


def _scan_sample_rows(text: str, source: str) -> list[dict[str, Any]]:
    """Warn on table or array rows in an explicit sample context."""
    findings: list[dict[str, Any]] = []
    sample_context = False
    for line_number, line in enumerate(text.splitlines(), start=1):
        if SAMPLE_CONTEXT_PATTERN.search(line):
            sample_context = True
            continue
        if sample_context and re.match(r"^\s*#{1,6}\s+", line):
            sample_context = False
        if not sample_context:
            continue
        if MARKDOWN_TABLE_ROW_PATTERN.match(line) or JSON_ARRAY_PATTERN.match(line):
            findings.append(
                _finding(source, line_number, 1, "sample_row", "warn", line)
            )
    return findings


def _scan_sas_tokens(text: str, source: str) -> list[dict[str, Any]]:
    """Detect SAS URLs only when signature, expiry, and permission fields coexist."""
    findings: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for match in SAS_URL_PATTERN.finditer(line):
            query = match.group(0).split("?", 1)[1].lower()
            fields = {part.split("=", 1)[0] for part in query.split("&") if "=" in part}
            if {"sig", "se", "sp"}.issubset(fields):
                findings.append(
                    _finding(
                        source,
                        line_number,
                        match.start() + 1,
                        "sas_token",
                        "high",
                        match.group(0),
                    )
                )
    return findings


def _build_denylist_rules(terms: list[str]) -> tuple[Rule, ...]:
    """Build case-insensitive literal high-confidence rules."""
    return tuple(
        Rule("denylist_term", "high", re.compile(re.escape(term), re.IGNORECASE))
        for term in terms
    )


def _load_denylist(path: Path) -> tuple[Rule, ...]:
    """Read unique nonblank UTF-8 denylist terms without exposing them."""
    try:
        if not path.is_file():
            raise OSError("path is not a readable file")
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ValueError("denylist must be a readable UTF-8 text file") from exc
    terms: list[str] = []
    seen: set[str] = set()
    for line in lines:
        term = line.strip()
        key = term.casefold()
        if term and key not in seen:
            terms.append(term)
            seen.add(key)
    return _build_denylist_rules(terms)


def scan_text(
    text: str,
    source: str,
    *,
    public: bool = False,
    data: bool = False,
    denylist_rules: tuple[Rule, ...] = (),
) -> list[dict[str, Any]]:
    """Return a list of finding dicts for ``text`` attributed to ``source``.

    When ``public`` is true, internal-URL rules are included; in a private
    repository those references are expected and are not flagged.
    """
    active_rules = RULES
    if public:
        active_rules = (*active_rules, *PUBLIC_ONLY_RULES)
    if data:
        active_rules = (*active_rules, *DATA_ONLY_RULES)
    active_rules = (*active_rules, *denylist_rules)
    findings: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        for rule in active_rules:
            for match in rule.pattern.finditer(line):
                findings.append(
                    _finding(
                        source,
                        line_number,
                        match.start() + 1,
                        rule.category,
                        rule.confidence,
                        match.group(0),
                    )
                )
    if data:
        findings.extend(_scan_structured_columns(text, source))
        findings.extend(_scan_sample_rows(text, source))
        findings.extend(_scan_sas_tokens(text, source))
    findings.sort(key=lambda finding: (finding["line"], finding["column"], finding["category"]))
    return findings


def create_parser() -> argparse.ArgumentParser:
    """Create the argument parser."""
    parser = argparse.ArgumentParser(
        prog="scan_sensitive_content",
        description=("Scan ADR/handoff content for high-confidence PII and public-repository internal URLs."),
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="File paths to scan; reads stdin when no paths are given.",
    )
    parser.add_argument(
        "--allow-root",
        type=Path,
        action="append",
        default=[],
        help="Additional directory under which scanned paths may live.",
    )
    parser.add_argument(
        "--public",
        action="store_true",
        help=(
            "Treat the target repository as public; enables internal-URL "
            "detection, which is suppressed for private repositories."
        ),
    )
    parser.add_argument(
        "--data",
        action="store_true",
        help=(
            "Enable structured column, connection, credential, sample-row, "
            "and international identifier detection for data artifacts."
        ),
    )
    parser.add_argument(
        "--denylist",
        type=Path,
        help=(
            "UTF-8 text file containing one literal customer-specific term "
            "per line; enables high-confidence matching independently."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    args = create_parser().parse_args(argv)

    findings: list[dict[str, Any]] = []
    try:
        denylist_rules = _load_denylist(args.denylist) if args.denylist else ()
    except ValueError as exc:
        print(f"scan_sensitive_content: {exc}", file=sys.stderr)
        return EXIT_ERROR

    if args.paths:
        auto_allow: list[Path] = [SKILL_ROOT, REPO_ROOT]
        for raw in args.paths:
            try:
                auto_allow.append(raw.expanduser().resolve().parent)
            except OSError:
                # Unresolvable path (e.g. broken symlink); skip adding its
                # parent to the allowlist and rely on safe_resolve below to
                # reject it explicitly.
                continue
        allow_roots = [
            *auto_allow,
            *(p.expanduser().resolve() for p in args.allow_root),
        ]
        for raw in args.paths:
            try:
                resolved = safe_resolve(raw, allow_roots)
            except ValueError as exc:
                print(
                    f"scan_sensitive_content: path error: {exc}",
                    file=sys.stderr,
                )
                return EXIT_ERROR
            try:
                text = resolved.read_text(encoding="utf-8")
            except OSError as exc:
                print(
                    f"scan_sensitive_content: failed to read '{raw}': {exc}",
                    file=sys.stderr,
                )
                return EXIT_FAILURE
            findings.extend(
                scan_text(
                    text,
                    str(raw),
                    public=args.public,
                    data=args.data,
                    denylist_rules=denylist_rules,
                )
            )
    else:
        text = sys.stdin.read()
        findings.extend(
            scan_text(
                text,
                STDIN_SOURCE,
                public=args.public,
                data=args.data,
                denylist_rules=denylist_rules,
            )
        )

    high_count = sum(1 for f in findings if f["confidence"] == "high")
    warn_count = sum(1 for f in findings if f["confidence"] == "warn")
    report = {
        "findings": findings,
        "summary": {
            "high": high_count,
            "warn": warn_count,
            "total": len(findings),
        },
    }
    print(json.dumps(report, indent=2))

    return EXIT_FAILURE if high_count else EXIT_SUCCESS


if __name__ == "__main__":
    sys.exit(main())
