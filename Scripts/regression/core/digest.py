from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .ids import Digest


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        allow_nan=False,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def digest_bytes(value: bytes) -> Digest:
    return Digest("sha256:" + hashlib.sha256(value).hexdigest())


def canonical_digest(value: Any) -> Digest:
    return digest_bytes(canonical_bytes(value))


def normalize_text_bytes(value: bytes) -> bytes:
    return value.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def digest_text_file(path: Path) -> Digest:
    return digest_bytes(normalize_text_bytes(path.read_bytes()))


__all__ = (
    "canonical_bytes",
    "canonical_digest",
    "digest_bytes",
    "digest_text_file",
    "normalize_text_bytes",
)
