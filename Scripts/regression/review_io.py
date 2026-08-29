from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from typing import Any, Dict, Iterable, List, Mapping, Tuple

from .core.digest import canonical_bytes, digest_bytes
from .core.errors import RegressionError
from .core.frontmatter import load_frontmatter
from .core.ids import Digest, parse_identifier
from .core.review import (
    BudgetAmount,
    BudgetUnit,
    ReviewActorIdentity,
    ReviewBudget,
    ReviewClass,
    ReviewPolicy,
    ReviewReceipt,
    ReviewUsage,
)


POLICY_SCHEMA = "enchron.regression.review-policy"
RECEIPT_SCHEMA = "enchron.regression.review-receipt"
SCHEMA_VERSION = 1


class _DuplicateKeyError(ValueError):
    pass


class _InvalidConstantError(ValueError):
    pass


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _object_without_duplicates(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKeyError(key)
        result[key] = value
    return result


def _reject_constant(value: str) -> Any:
    raise _InvalidConstantError(value)


def _keys(
    value: object, required: Iterable[str], location: str
) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise _error("review.io.not_object", location, "expected a JSON object")
    required_keys = frozenset(required)
    unknown = sorted(set(value) - required_keys)
    missing = sorted(required_keys - set(value))
    if unknown:
        raise _error(
            "review.io.unknown_field",
            location,
            "unknown field(s): " + ", ".join(unknown),
        )
    if missing:
        raise _error(
            "review.io.missing_field",
            location,
            "missing field(s): " + ", ".join(missing),
        )
    return value


def _schema(value: Mapping[str, Any], expected: str, location: str) -> None:
    if value["schema"] != expected:
        raise _error(
            "review.io.schema_mismatch",
            f"{location}.schema",
            f"expected schema {expected!r}",
        )
    if type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1:
        raise _error(
            "review.io.unsupported_schema_version",
            f"{location}.schemaVersion",
            "schemaVersion must be integer 1",
        )


def _amounts(value: object, location: str) -> Tuple[BudgetAmount, ...]:
    if not isinstance(value, Mapping) or not value:
        raise _error(
            "review.io.empty_budget",
            location,
            "a budget or usage object must contain a typed unit",
        )
    known = {unit.value: unit for unit in BudgetUnit}
    unknown = sorted(set(value) - set(known))
    if unknown:
        raise _error(
            "review.io.unknown_budget_unit",
            location,
            "unknown budget unit(s): " + ", ".join(unknown),
        )
    return tuple(
        BudgetAmount(known[name], value[name]) for name in sorted(value)
    )


def load_review_policy(path: Path) -> ReviewPolicy:
    path = Path(path)
    document = load_frontmatter(path)
    metadata = _keys(
        document.metadata,
        ("schema", "schemaVersion", "perPacketLimit", "totalBudget"),
        str(path),
    )
    _schema(metadata, POLICY_SCHEMA, str(path))
    return ReviewPolicy(
        ReviewBudget(
            _amounts(metadata["perPacketLimit"], f"{path}.perPacketLimit")
        ),
        ReviewBudget(_amounts(metadata["totalBudget"], f"{path}.totalBudget")),
    )


def review_receipt_payload(receipt: ReviewReceipt) -> Mapping[str, Any]:
    if not isinstance(receipt, ReviewReceipt):
        raise _error(
            "review.io.invalid_receipt", "receipt", "expected ReviewReceipt"
        )
    return {
        "schema": RECEIPT_SCHEMA,
        "schemaVersion": SCHEMA_VERSION,
        "packetDigest": str(receipt.packet_digest),
        "reviewer": receipt.reviewer.value,
        "actor": {
            "actorId": receipt.actor.actor_id,
            "environmentDigest": str(receipt.actor.environment_digest),
        },
        "reportDigest": str(receipt.report_digest),
        "accepted": receipt.accepted,
        "usage": receipt.usage.as_dict(),
        "issuedAt": receipt.issued_at,
        "assessmentDigest": (
            None
            if receipt.assessment_digest is None
            else str(receipt.assessment_digest)
        ),
        "receiptDigest": str(receipt.receipt_digest),
    }


def _decode_canonical_json(path: Path) -> Mapping[str, Any]:
    source = path.read_bytes()
    if not source.endswith(b"\n"):
        raise _error(
            "review.io.noncanonical_json",
            str(path),
            "review JSON must end with one newline",
        )
    try:
        value = json.loads(
            source.decode("utf-8"),
            object_pairs_hook=_object_without_duplicates,
            parse_constant=_reject_constant,
        )
    except UnicodeDecodeError as error:
        raise _error(
            "review.io.invalid_utf8", str(path), "review JSON must be UTF-8"
        ) from error
    except _DuplicateKeyError as error:
        raise _error(
            "review.io.duplicate_field",
            str(path),
            f"JSON field {error.args[0]!r} appears more than once",
        ) from error
    except _InvalidConstantError as error:
        raise _error(
            "review.io.invalid_json",
            str(path),
            f"invalid JSON constant {error.args[0]!r}",
        ) from error
    except json.JSONDecodeError as error:
        raise _error(
            "review.io.invalid_json", str(path), f"invalid JSON: {error}"
        ) from error
    if canonical_bytes(value) + b"\n" != source:
        raise _error(
            "review.io.noncanonical_json",
            str(path),
            "review JSON must use canonical encoding",
        )
    if not isinstance(value, Mapping):
        raise _error("review.io.not_object", str(path), "expected a JSON object")
    return value


def load_review_receipt(path: Path) -> ReviewReceipt:
    path = Path(path)
    value = _keys(
        _decode_canonical_json(path),
        (
            "schema",
            "schemaVersion",
            "packetDigest",
            "reviewer",
            "actor",
            "reportDigest",
            "accepted",
            "usage",
            "issuedAt",
            "assessmentDigest",
            "receiptDigest",
        ),
        str(path),
    )
    _schema(value, RECEIPT_SCHEMA, str(path))
    try:
        reviewer = ReviewClass(value["reviewer"])
    except (TypeError, ValueError) as error:
        raise _error(
            "review.io.invalid_reviewer",
            f"{path}.reviewer",
            f"unknown reviewer {value['reviewer']!r}",
        ) from error
    actor = _keys(
        value["actor"], ("actorId", "environmentDigest"), f"{path}.actor"
    )
    raw_assessment = value["assessmentDigest"]
    assessment_digest = (
        None
        if raw_assessment is None
        else Digest(
            parse_identifier(
                "digest", raw_assessment, f"{path}.assessmentDigest"
            )
        )
    )
    receipt = ReviewReceipt(
        packet_digest=Digest(
            parse_identifier("digest", value["packetDigest"], f"{path}.packetDigest")
        ),
        reviewer=reviewer,
        actor=ReviewActorIdentity(
            actor["actorId"],
            Digest(
                parse_identifier(
                    "digest",
                    actor["environmentDigest"],
                    f"{path}.actor.environmentDigest",
                )
            ),
        ),
        report_digest=Digest(
            parse_identifier("digest", value["reportDigest"], f"{path}.reportDigest")
        ),
        accepted=value["accepted"],
        usage=ReviewUsage(_amounts(value["usage"], f"{path}.usage")),
        issued_at=value["issuedAt"],
        assessment_digest=assessment_digest,
    )
    declared_digest = Digest(
        parse_identifier("digest", value["receiptDigest"], f"{path}.receiptDigest")
    )
    if receipt.receipt_digest != declared_digest:
        raise _error(
            "review.io.receipt_digest_mismatch",
            str(path),
            f"expected {receipt.receipt_digest}, found {declared_digest}",
        )
    return receipt


def receipt_path(root: Path, receipt: ReviewReceipt) -> Path:
    return (
        Path(root)
        / receipt.reviewer.value
        / (str(receipt.packet_digest).removeprefix("sha256:") + ".json")
    )


def load_review_receipts(root: Path) -> Tuple[ReviewReceipt, ...]:
    root = Path(root)
    receipts = []
    for path in sorted(root.glob("*/*.json"), key=lambda item: item.as_posix()):
        if path.parent.name not in {reviewer.value for reviewer in ReviewClass}:
            raise _error(
                "review.io.invalid_receipt_path",
                str(path),
                "receipt directory must name its reviewer class",
            )
        receipt = load_review_receipt(path)
        if path.parent.name != receipt.reviewer.value or path != receipt_path(
            root, receipt
        ):
            raise _error(
                "review.io.invalid_receipt_path",
                str(path),
                "receipt path must bind reviewer and packet digest",
            )
        receipts.append(receipt)
    packet_digests = tuple(item.packet_digest for item in receipts)
    if len(packet_digests) != len(set(packet_digests)):
        raise _error(
            "review.io.duplicate_packet_receipt",
            str(root),
            "a packet may have only one persisted receipt",
        )
    return tuple(receipts)


def _write_once(path: Path, source: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink() or path.parent.is_symlink():
        raise _error(
            "review.io.invalid_path", str(path), "review files cannot use symlinks"
        )
    if path.exists():
        if not path.is_file() or path.read_bytes() != source:
            raise _error(
                "review.io.write_conflict",
                str(path),
                "existing review file has different content",
            )
        return path
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".review-", dir=str(path.parent)
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(source)
            output.flush()
            os.fsync(output.fileno())
        try:
            os.link(str(temporary), str(path))
        except FileExistsError:
            if path.is_symlink() or path.read_bytes() != source:
                raise _error(
                    "review.io.write_conflict",
                    str(path),
                    "concurrent review file has different content",
                )
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
    return path


def write_review_receipt(root: Path, receipt: ReviewReceipt) -> Path:
    path = receipt_path(root, receipt)
    return _write_once(path, canonical_bytes(review_receipt_payload(receipt)) + b"\n")


def report_bytes(report: str) -> bytes:
    if not isinstance(report, str) or not report.strip():
        raise _error(
            "review.io.empty_report", "report", "review report must not be empty"
        )
    source = report.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    if not source.endswith(b"\n"):
        source += b"\n"
    return source


def write_review_report(root: Path, report: str) -> Tuple[Digest, Path]:
    source = report_bytes(report)
    digest = digest_bytes(source)
    path = (
        Path(root)
        / "reports"
        / "sha256"
        / (str(digest).removeprefix("sha256:") + ".md")
    )
    return digest, _write_once(path, source)


def write_review_assessment(
    root: Path, assessment: Mapping[str, Any]
) -> Tuple[Digest, Path]:
    source = canonical_bytes(assessment) + b"\n"
    digest = digest_bytes(source)
    path = (
        Path(root)
        / "assessments"
        / "sha256"
        / (str(digest).removeprefix("sha256:") + ".json")
    )
    return digest, _write_once(path, source)


def load_review_assessment(root: Path, digest: Digest) -> Mapping[str, Any]:
    parsed = Digest(parse_identifier("digest", digest, "assessmentDigest"))
    path = (
        Path(root)
        / "assessments"
        / "sha256"
        / (str(parsed).removeprefix("sha256:") + ".json")
    )
    if path.is_symlink() or not path.is_file():
        raise _error(
            "review.io.missing_assessment",
            str(path),
            "review assessment is absent",
        )
    if digest_bytes(path.read_bytes()) != parsed:
        raise _error(
            "review.io.assessment_digest_mismatch",
            str(path),
            "review assessment bytes do not match the receipt digest",
        )
    return _decode_canonical_json(path)


def load_review_report(root: Path, digest: Digest) -> str:
    parsed = Digest(parse_identifier("digest", digest, "reportDigest"))
    path = (
        Path(root)
        / "reports"
        / "sha256"
        / (str(parsed).removeprefix("sha256:") + ".md")
    )
    if path.is_symlink() or not path.is_file():
        raise _error("review.io.missing_report", str(path), "review report is absent")
    source = path.read_bytes()
    if digest_bytes(source) != parsed:
        raise _error(
            "review.io.report_digest_mismatch",
            str(path),
            "review report bytes do not match the receipt digest",
        )
    try:
        return source.decode("utf-8")
    except UnicodeDecodeError as error:
        raise _error(
            "review.io.invalid_utf8", str(path), "review report must be UTF-8"
        ) from error


__all__ = (
    "POLICY_SCHEMA",
    "RECEIPT_SCHEMA",
    "load_review_policy",
    "load_review_receipt",
    "load_review_assessment",
    "load_review_receipts",
    "load_review_report",
    "receipt_path",
    "report_bytes",
    "review_receipt_payload",
    "write_review_assessment",
    "write_review_receipt",
    "write_review_report",
)
