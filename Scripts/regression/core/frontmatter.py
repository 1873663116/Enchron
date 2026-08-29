from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from types import MappingProxyType
from typing import Any, Dict, List, Mapping, Tuple, Union

from .digest import digest_bytes, normalize_text_bytes
from .errors import RegressionError
from .ids import Digest


@dataclass(frozen=True)
class FrontMatterDocument:
    metadata: Mapping[str, Any]
    body: str
    source_digest: Digest


class _DuplicateKeyError(ValueError):
    def __init__(self, key: str) -> None:
        self.key = key
        super().__init__(key)


class _InvalidConstantError(ValueError):
    pass


def _object_without_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKeyError(key)
        result[key] = value
    return result


def _reject_constant(value: str) -> Any:
    raise _InvalidConstantError(value)


def _decode_json_object(source: str, location: str) -> Dict[str, Any]:
    try:
        value = json.loads(
            source,
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except _DuplicateKeyError as error:
        raise RegressionError(
            "frontmatter.duplicate_key",
            location,
            f"Front matter declares {error.key!r} more than once.",
        ) from error
    except (_InvalidConstantError, json.JSONDecodeError) as error:
        raise RegressionError(
            "frontmatter.invalid_json",
            location,
            f"Front matter is not valid JSON: {error}.",
        ) from error
    if not isinstance(value, dict):
        raise RegressionError(
            "frontmatter.not_object",
            location,
            "Front matter must be a JSON object.",
        )
    return value


def _freeze_json(value: Any) -> Any:
    if isinstance(value, dict):
        return MappingProxyType({key: _freeze_json(item) for key, item in value.items()})
    if isinstance(value, list):
        return tuple(_freeze_json(item) for item in value)
    return value


def _is_second_front_matter(body: str) -> bool:
    if not body.startswith("---\n"):
        return False
    lines = body.splitlines(keepends=True)
    for index, line in enumerate(lines[1:], start=1):
        if line.removesuffix("\n") != "---":
            continue
        candidate = "".join(lines[1:index])
        try:
            value = json.loads(
                candidate,
                object_pairs_hook=_object_without_duplicates,
                parse_constant=_reject_constant,
            )
        except ValueError:
            return False
        return isinstance(value, dict)
    return False


def parse_frontmatter(
    source: Union[str, bytes], location: str = "<memory>"
) -> FrontMatterDocument:
    if isinstance(source, str):
        try:
            source_bytes = source.encode("utf-8")
        except UnicodeEncodeError as error:
            raise RegressionError(
                "frontmatter.invalid_utf8",
                location,
                "Front matter source is not valid UTF-8 text.",
            ) from error
    elif isinstance(source, bytes):
        source_bytes = source
    else:
        raise RegressionError(
            "frontmatter.not_string",
            location,
            "Front matter source must be text or bytes.",
        )

    normalized = normalize_text_bytes(source_bytes)
    try:
        text = normalized.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RegressionError(
            "frontmatter.invalid_utf8",
            location,
            "Front matter source is not valid UTF-8 text.",
        ) from error

    lines = text.splitlines(keepends=True)
    if not lines or lines[0].removesuffix("\n") != "---":
        raise RegressionError(
            "frontmatter.missing_opening_boundary",
            location,
            "The first line must be '---'.",
        )

    closing_index = None
    for index, line in enumerate(lines[1:], start=1):
        if line.removesuffix("\n") == "---":
            closing_index = index
            break
    if closing_index is None:
        raise RegressionError(
            "frontmatter.missing_closing_boundary",
            location,
            "Front matter has no closing '---' line.",
        )

    metadata_source = "".join(lines[1:closing_index])
    metadata = _decode_json_object(metadata_source, location)
    body = "".join(lines[closing_index + 1:])
    if _is_second_front_matter(body):
        raise RegressionError(
            "frontmatter.multiple_blocks",
            location,
            "A document may contain only one front matter block.",
        )

    return FrontMatterDocument(
        metadata=_freeze_json(metadata),
        body=body,
        source_digest=digest_bytes(normalized),
    )


def load_frontmatter(path: Path) -> FrontMatterDocument:
    return parse_frontmatter(path.read_bytes(), str(path))


__all__ = ("FrontMatterDocument", "load_frontmatter", "parse_frontmatter")
