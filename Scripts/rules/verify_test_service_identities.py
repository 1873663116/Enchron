#!/usr/bin/env python3

"""Identity and credential material that must not reach a published repository.

The registry at `Config/test_service_identities.json` is the only place that
names a tested service. Every identity-shaped variable in the tree must appear
in it, every value it carries in the environment must stay out of the tree, and
the shapes below catch what no registry entry covers.

A finding names the path, the line, the variable and the class. The value never
appears in the output, so a failing run can be pasted into an issue.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import verify_product_source_comments as sources


REPOSITORY_ROOT = sources.REPOSITORY_ROOT
REGISTRY_PATH = REPOSITORY_ROOT / "Config/test_service_identities.json"
SCHEMA = "enchron.verification.test-service-identities@1"
IDENTITY_CLASSES = frozenset({"identity", "credential", "harness"})
MINIMUM_VALUE_LENGTH = 4

IDENTITY_NAME = re.compile(
    r"""["']([A-Z][A-Z0-9]*_(?:USER|PASSWORD|ADDRESS|HOST|IDENTIFIER|TOKEN))["']"""
)
PRIVATE_KEY_BLOCK = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
URL_USERINFO = re.compile(
    r"\b[a-z][a-z0-9+.-]*://[^\s:/@\"']+:[^\s/@\"']+@[^\s/\"']+"
)
AUTHORIZATION_HEADER = re.compile(
    r"""authorization["']?\s*[:=]\s*["']?(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]{16,}""",
    re.IGNORECASE,
)
CERTIFICATE_FINGERPRINT = re.compile(
    r"(?:certificate[ _-]?fingerprint|fingerprint|certificate)"
    r"[\"']?\s*[:=]\s*[\"']?[0-9A-Fa-f]{2}(?:[:-]?[0-9A-Fa-f]{2}){15,}",
    re.IGNORECASE,
)
PLACEHOLDER_MARKERS = (
    "example",
    ".test",
    "fixture",
    "placeholder",
    "dummy",
    "redacted",
    "localhost",
    "invalid",
    "not-a-real",
    "changeme",
    "127.0.0.1",
    "0.0.0.0",
    "::1",
    "<",
    "{",
    "${",
)


def load_registry(path: Path = REGISTRY_PATH) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if document.get("schema") != SCHEMA:
        raise SystemExit(f"{path} does not declare {SCHEMA}")
    return document["variables"]


def scan_texts() -> list[tuple[Path, str]]:
    return [(path, path.read_text(encoding="utf-8")) for path in sources.first_party_files()]


def unclassified_variables(
    texts: list[tuple[Path, str]], registry: dict
) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for path, text in texts:
        for match in IDENTITY_NAME.finditer(text):
            name = match.group(1)
            if name in registry or name in seen:
                continue
            seen.add(name)
            line = text.count("\n", 0, match.start()) + 1
            found.append(
                f"{path.relative_to(REPOSITORY_ROOT)}:{line}: {name} is not in the registry"
            )
    return found


def malformed_registry(registry: dict) -> list[str]:
    found: list[str] = []
    for name, entry in sorted(registry.items()):
        if not isinstance(entry, dict):
            found.append(f"{name}: entry is not an object")
            continue
        if not entry.get("service"):
            found.append(f"{name}: no service named")
        if entry.get("class") not in IDENTITY_CLASSES:
            found.append(f"{name}: class {entry.get('class')!r} is not one of the known classes")
    return found


def environment_values(registry: dict) -> dict[str, str]:
    values: dict[str, str] = {}
    environment_file = REPOSITORY_ROOT / ".env"
    recorded: dict[str, str] = {}
    if environment_file.is_file():
        for line in environment_file.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("#") or "=" not in stripped:
                continue
            key, _, value = stripped.partition("=")
            recorded[key.strip()] = value.strip().strip("\"'")
    for name in registry:
        value = os.environ.get(name) or recorded.get(name, "")
        if len(value) >= MINIMUM_VALUE_LENGTH:
            values[name] = value
    return values


def is_placeholder(span: str) -> bool:
    lowered = span.lower()
    return any(marker in lowered for marker in PLACEHOLDER_MARKERS)


def value_leaks(
    texts: list[tuple[Path, str]], values: dict[str, str]
) -> list[str]:
    found: list[str] = []
    for path, text in texts:
        for name, value in sorted(values.items()):
            start = text.find(value)
            if start < 0:
                continue
            line = text.count("\n", 0, start) + 1
            found.append(
                f"{path.relative_to(REPOSITORY_ROOT)}:{line}: {name} appears in the tree"
            )
    return found


def shape_leaks(texts: list[tuple[Path, str]]) -> list[str]:
    found: list[str] = []
    rules = (
        (PRIVATE_KEY_BLOCK, "private key block"),
        (URL_USERINFO, "credential in a URL"),
        (AUTHORIZATION_HEADER, "literal authorization header"),
        (CERTIFICATE_FINGERPRINT, "certificate fingerprint"),
    )
    for path, text in texts:
        for pattern, category in rules:
            for match in pattern.finditer(text):
                if is_placeholder(match.group(0)):
                    continue
                line = text.count("\n", 0, match.start()) + 1
                found.append(
                    f"{path.relative_to(REPOSITORY_ROOT)}:{line}: {category}"
                )
    return found


def main() -> int:
    registry = load_registry()
    texts = scan_texts()
    found = malformed_registry(registry)
    found += unclassified_variables(texts, registry)
    values = environment_values(registry)
    found += value_leaks(texts, values)
    if not values:
        found += shape_leaks(texts)
    if found:
        for item in found:
            print(f"error: {item}", file=sys.stderr)
        print(
            "Register the variable in Config/test_service_identities.json, move the "
            "value out of the tree, and keep it in the environment or .env.",
            file=sys.stderr,
        )
        return 1
    covered = "value and shape" if values else "shape only"
    print(
        f"{len(registry)} registered identities over {len(texts)} files, {covered} coverage"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
