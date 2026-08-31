#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
from enum import Enum
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
from typing import Iterable

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import merge_evidence_tier as evidence_tier

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RUN_RECEIPT_SCHEMA = "enchron.merge-run-receipt/v1"
APPROVAL_RECEIPT_SCHEMA = "enchron.merge-approval-receipt/v1"


class ChangeKind(str, Enum):
    BEHAVIOR_PRESERVING_REFACTOR = "behavior-preserving-refactor"
    BUG_FIX = "bug-fix"
    NEW_FEATURE = "new-feature"
    REGRESSION_CONTRACT = "regression-contract"
    PUBLIC_API = "public-api"
    MODULE_OWNERSHIP = "module-ownership"
    PERSISTENCE = "persistence"
    CORE_DOMAIN_MODEL = "core-domain-model"


class AuthorityDecision(str, Enum):
    AUTO_MERGE_ELIGIBLE = "AutoMergeEligible"
    HUMAN_REVIEW_REQUIRED = "HumanReviewRequired"


AUTO_MERGE_CHANGE_KINDS = frozenset(
    {
        ChangeKind.BEHAVIOR_PRESERVING_REFACTOR,
        ChangeKind.BUG_FIX,
    }
)
HUMAN_REVIEW_CHANGE_KINDS = frozenset(ChangeKind) - AUTO_MERGE_CHANGE_KINDS
EVIDENCE_KINDS = frozenset(
    {
        evidence_tier.VERIFICATION_GREEN,
        evidence_tier.SIMULATOR_E2E,
        evidence_tier.DEVICE_HUB_INPUT,
        evidence_tier.REAL_DEVICE_DECODE,
    }
)
SPATIAL_TAP = re.compile(
    r"(?:^|\s)spatialTap\s+entity=(?P<entity>\S+)"
    r"(?P<fields>(?:\s+\S+=[^\s]+)*)"
)


class AuthorityError(ValueError):
    pass


@dataclass(frozen=True)
class RangeSnapshot:
    expression: str
    base_commit: str
    head_commit: str
    diff_sha256: str
    classifications: tuple[evidence_tier.Classification, ...]
    tier: str | None


@dataclass(frozen=True)
class EvidenceInput:
    kind: str
    path: Path


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def canonical_json(payload: object) -> bytes:
    return (
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            separators=(",", ": "),
        )
        + "\n"
    ).encode("utf-8")


def run_git(repository: Path, *arguments: str, text: bool = True) -> str | bytes:
    completed = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        capture_output=True,
        text=text,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() if text else completed.stderr.decode().strip()
        raise AuthorityError(detail or f"git {' '.join(arguments)} failed")
    return completed.stdout


def resolve_range(repository: Path, expression: str) -> RangeSnapshot:
    if expression.count("..") != 1 or "..." in expression:
        raise AuthorityError("range must have the form <base>..<head>")
    base, head = expression.split("..")
    if not base or not head:
        raise AuthorityError("range must name both base and head revisions")
    base_commit = str(run_git(repository, "rev-parse", "--verify", f"{base}^{{commit}}")).strip()
    head_commit = str(run_git(repository, "rev-parse", "--verify", f"{head}^{{commit}}")).strip()
    bound_range = f"{base_commit}..{head_commit}"
    paths = evidence_tier.changed_paths(repository, bound_range)
    verdict = evidence_tier.build_verdict(expression, paths)
    diff = run_git(
        repository,
        "diff",
        "--binary",
        "--full-index",
        base_commit,
        head_commit,
        text=False,
    )
    assert isinstance(diff, bytes)
    return RangeSnapshot(
        expression,
        base_commit,
        head_commit,
        sha256_bytes(diff),
        verdict.classifications,
        verdict.tier,
    )


def decide_authority(change_kinds: Iterable[ChangeKind]) -> AuthorityDecision:
    kinds = frozenset(change_kinds)
    if not kinds:
        raise AuthorityError("at least one ChangeKind declaration is required")
    if kinds <= AUTO_MERGE_CHANGE_KINDS:
        return AuthorityDecision.AUTO_MERGE_ELIGIBLE
    return AuthorityDecision.HUMAN_REVIEW_REQUIRED


def normalized_change_kinds(values: Iterable[str | ChangeKind]) -> tuple[ChangeKind, ...]:
    try:
        kinds = {value if isinstance(value, ChangeKind) else ChangeKind(value) for value in values}
    except ValueError as error:
        allowed = ", ".join(kind.value for kind in ChangeKind)
        raise AuthorityError(f"unknown ChangeKind; expected one of: {allowed}") from error
    if not kinds:
        raise AuthorityError("undeclared semantic changes: pass at least one --change-kind")
    return tuple(sorted(kinds, key=lambda kind: kind.value))


def repository_path(repository: Path, value: Path) -> tuple[Path, str]:
    absolute = value if value.is_absolute() else repository / value
    absolute = absolute.resolve()
    try:
        relative = absolute.relative_to(repository.resolve()).as_posix()
    except ValueError as error:
        raise AuthorityError(f"artifact must be inside the repository: {value}") from error
    return absolute, relative


def artifact_files(path: Path) -> tuple[Path, ...]:
    if path.is_symlink():
        raise AuthorityError(f"artifact may not be a symbolic link: {path}")
    if path.is_file():
        return (path,)
    if not path.is_dir():
        raise AuthorityError(f"artifact does not exist: {path}")
    files = tuple(sorted(candidate for candidate in path.rglob("*") if candidate.is_file()))
    if not files:
        raise AuthorityError(f"artifact directory is empty: {path}")
    for candidate in files:
        if candidate.is_symlink():
            raise AuthorityError(f"artifact may not contain symbolic links: {candidate}")
    return files


def file_record(repository: Path, path: Path) -> dict[str, object]:
    _, pointer = repository_path(repository, path)
    content = path.read_bytes()
    return {"path": pointer, "bytes": len(content), "sha256": sha256_bytes(content)}


def validate_verification(files: tuple[Path, ...]) -> None:
    summaries = [path for path in files if path.name == "summary.json"]
    if not summaries and len(files) == 1:
        summaries = list(files)
    if len(summaries) != 1:
        raise AuthorityError(
            "verification-green must resolve to exactly one summary.json"
        )
    try:
        payload = json.loads(summaries[0].read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuthorityError(f"verification summary is not valid JSON: {error}") from error
    if payload.get("verdict") != "passed":
        raise AuthorityError("verification summary verdict must be 'passed'")


def validate_device_hub(files: tuple[Path, ...]) -> None:
    diagnostics = [path for path in files if path.name == "diagnostics.json"]
    if not diagnostics:
        raise AuthorityError("device-hub-input needs diagnostics.json")
    try:
        for path in diagnostics:
            json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuthorityError(f"device-hub diagnostics are not valid JSON: {error}") from error
    probe_found = False
    for path in files:
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                match = SPATIAL_TAP.search(line)
                fields = () if match is None else tuple(match.group("fields").split())
                if match and "accepted=true" in fields:
                    probe_found = True
                    break
        except UnicodeDecodeError:
            continue
    if not probe_found:
        raise AuthorityError(
            "device-hub-input needs an app-side spatialTap entity=<entity> ... accepted=true probe"
        )


def validate_real_device_decode(files: tuple[Path, ...]) -> None:
    proven = False
    for path in files:
        if path.suffix != ".json":
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        if not isinstance(payload, dict):
            continue
        capability = payload.get("capability")
        passed = payload.get("passed") is True or payload.get("verdict") == "passed"
        if isinstance(capability, str) and capability.strip() and passed:
            proven = True
            break
    if not proven:
        raise AuthorityError(
            "real-device-decode needs a JSON result with capability and a passed verdict"
        )


def evidence_record(repository: Path, item: EvidenceInput) -> dict[str, object]:
    if item.kind not in EVIDENCE_KINDS:
        raise AuthorityError(
            f"unknown evidence kind {item.kind!r}; expected: {', '.join(sorted(EVIDENCE_KINDS))}"
        )
    path, pointer = repository_path(repository, item.path)
    files = artifact_files(path)
    if item.kind == evidence_tier.VERIFICATION_GREEN:
        validate_verification(files)
    elif item.kind == evidence_tier.DEVICE_HUB_INPUT:
        validate_device_hub(files)
    elif item.kind == evidence_tier.REAL_DEVICE_DECODE:
        validate_real_device_decode(files)
    records = [file_record(repository, candidate) for candidate in files]
    aggregate = sha256_bytes(canonical_json(records))
    return {
        "kind": item.kind,
        "path": pointer,
        "bytes": sum(int(record["bytes"]) for record in records),
        "sha256": aggregate,
        "files": records,
    }


def evidence_records(
    repository: Path, inputs: Iterable[EvidenceInput]
) -> list[dict[str, object]]:
    records = [evidence_record(repository, item) for item in inputs]
    records.sort(key=lambda item: (str(item["kind"]), str(item["path"])))
    if len({(item["kind"], item["path"]) for item in records}) != len(records):
        raise AuthorityError("duplicate evidence pointer")
    return records


def prove_evidence(tier: str | None, records: list[dict[str, object]]) -> None:
    if tier is None:
        return
    present = {str(record["kind"]) for record in records}
    required = {evidence_tier.VERIFICATION_GREEN}
    if tier == evidence_tier.W2:
        required.add(evidence_tier.SIMULATOR_E2E)
    elif tier == evidence_tier.W3:
        if evidence_tier.REAL_DEVICE_DECODE in present:
            required.add(evidence_tier.REAL_DEVICE_DECODE)
        else:
            required.update(
                {
                    evidence_tier.SIMULATOR_E2E,
                    evidence_tier.DEVICE_HUB_INPUT,
                }
            )
    missing = sorted(required - present)
    if missing:
        raise AuthorityError(
            f"evidence below {tier}: missing {', '.join(missing)}"
        )


def snapshot_payload(snapshot: RangeSnapshot) -> dict[str, object]:
    return {
        "expression": snapshot.expression,
        "baseCommit": snapshot.base_commit,
        "headCommit": snapshot.head_commit,
        "diffSha256": snapshot.diff_sha256,
    }


def classification_payload(snapshot: RangeSnapshot) -> list[dict[str, str]]:
    return [
        {"path": item.path, "tier": item.tier, "rule": item.rule}
        for item in snapshot.classifications
    ]


def tool_identity() -> dict[str, str]:
    tool_files = (
        Path(__file__).resolve(),
        Path(evidence_tier.__file__).resolve(),
    )
    bound = [
        {"name": path.name, "sha256": sha256_bytes(path.read_bytes())}
        for path in sorted(tool_files, key=lambda item: item.name)
    ]
    return {
        "name": "merge-authority",
        "sha256": sha256_bytes(canonical_json(bound)),
    }


def environment_identity(repository: Path) -> dict[str, str]:
    git_version = str(run_git(repository, "--version")).strip()
    developer_directory = os.environ.get("DEVELOPER_DIR")
    if developer_directory is None:
        selected = subprocess.run(
            ["xcode-select", "-p"], capture_output=True, text=True
        )
        developer_directory = (
            selected.stdout.strip() if selected.returncode == 0 else "unavailable"
        )
    xcode = subprocess.run(
        ["xcodebuild", "-version"], capture_output=True, text=True
    )
    xcode_version = (
        xcode.stdout.strip().replace("\n", "; ")
        if xcode.returncode == 0
        else "unavailable"
    )
    return {
        "python": platform.python_version(),
        "pythonImplementation": platform.python_implementation(),
        "operatingSystem": platform.system(),
        "operatingSystemRelease": platform.release(),
        "machine": platform.machine(),
        "git": git_version,
        "developerDirectory": developer_directory,
        "xcode": xcode_version,
    }


def approval_payload(
    snapshot: RangeSnapshot,
    change_kinds: tuple[ChangeKind, ...],
    authority: str,
    reference: str,
) -> dict[str, object]:
    if not authority.strip() or not reference.strip():
        raise AuthorityError("approval authority and reference must be non-empty")
    return {
        "schema": APPROVAL_RECEIPT_SCHEMA,
        "range": snapshot_payload(snapshot),
        "classifications": classification_payload(snapshot),
        "tier": snapshot.tier,
        "changeKinds": [kind.value for kind in change_kinds],
        "decision": decide_authority(change_kinds).value,
        "approval": {
            "authority": authority,
            "reference": reference,
        },
    }


def load_json(path: Path, label: str) -> tuple[dict[str, object], bytes]:
    try:
        raw = path.read_bytes()
        payload = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise AuthorityError(f"{label} is not valid JSON: {error}") from error
    if not isinstance(payload, dict):
        raise AuthorityError(f"{label} must be a JSON object")
    return payload, raw


def validate_approval(
    repository: Path,
    path_value: Path,
    snapshot: RangeSnapshot,
    change_kinds: tuple[ChangeKind, ...],
) -> dict[str, object]:
    path, pointer = repository_path(repository, path_value)
    payload, raw = load_json(path, "approval receipt")
    if raw != canonical_json(payload):
        raise AuthorityError("approval receipt is not canonical deterministic JSON")
    approval = payload.get("approval")
    if not isinstance(approval, dict):
        raise AuthorityError("approval receipt is missing approval authority")
    authority = approval.get("authority")
    reference = approval.get("reference")
    if not isinstance(authority, str) or not isinstance(reference, str):
        raise AuthorityError("approval receipt authority and reference must be strings")
    expected = approval_payload(snapshot, change_kinds, authority, reference)
    if payload != expected:
        raise AuthorityError("approval receipt is stale or does not bind this change")
    return {
        "path": pointer,
        "bytes": len(raw),
        "sha256": sha256_bytes(raw),
        "authority": authority,
        "reference": reference,
    }


def build_run_receipt(
    repository: Path,
    range_expression: str,
    change_kind_values: Iterable[str | ChangeKind],
    inputs: Iterable[EvidenceInput],
    approval_path: Path | None = None,
) -> dict[str, object]:
    repository = repository.resolve()
    snapshot = resolve_range(repository, range_expression)
    change_kinds = normalized_change_kinds(change_kind_values)
    decision = decide_authority(change_kinds)
    records = evidence_records(repository, inputs)
    prove_evidence(snapshot.tier, records)
    approval = None
    if approval_path is not None:
        approval = validate_approval(
            repository, approval_path, snapshot, change_kinds
        )
    if decision == AuthorityDecision.HUMAN_REVIEW_REQUIRED and approval is None:
        raise AuthorityError(
            "missing authority: HumanReviewRequired needs an approval receipt"
        )
    return {
        "schema": RUN_RECEIPT_SCHEMA,
        "range": snapshot_payload(snapshot),
        "classifications": classification_payload(snapshot),
        "tier": snapshot.tier,
        "changeKinds": [kind.value for kind in change_kinds],
        "authority": {
            "decision": decision.value,
            "status": "approved" if approval is not None else "evidence-proven",
            "approval": approval,
        },
        "tool": tool_identity(),
        "environment": environment_identity(repository),
        "evidence": records,
    }


def parse_evidence(value: str) -> EvidenceInput:
    if "=" not in value:
        raise argparse.ArgumentTypeError("evidence must have the form <kind>=<path>")
    kind, path = value.split("=", 1)
    if not kind or not path:
        raise argparse.ArgumentTypeError("evidence must have the form <kind>=<path>")
    return EvidenceInput(kind, Path(path))


def write_payload(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_json(payload))


def create_approval(arguments: argparse.Namespace) -> int:
    repository = arguments.repository.resolve()
    snapshot = resolve_range(repository, arguments.range)
    kinds = normalized_change_kinds(arguments.change_kind)
    write_payload(
        arguments.output,
        approval_payload(snapshot, kinds, arguments.authority, arguments.reference),
    )
    print(f"wrote approval receipt: {arguments.output}")
    return 0


def generate(arguments: argparse.Namespace) -> int:
    payload = build_run_receipt(
        arguments.repository,
        arguments.range,
        arguments.change_kind,
        arguments.evidence,
        arguments.approval,
    )
    write_payload(arguments.output, payload)
    print(f"wrote RunReceipt: {arguments.output}")
    return 0


def verify(arguments: argparse.Namespace) -> int:
    repository = arguments.repository.resolve()
    receipt_path = arguments.receipt.resolve()
    payload, raw = load_json(receipt_path, "RunReceipt")
    if payload.get("schema") != RUN_RECEIPT_SCHEMA:
        raise AuthorityError(
            f"unsupported RunReceipt schema; expected {RUN_RECEIPT_SCHEMA}"
        )
    if raw != canonical_json(payload):
        raise AuthorityError("RunReceipt is not canonical deterministic JSON")
    range_payload = payload.get("range")
    authority_payload = payload.get("authority")
    if not isinstance(range_payload, dict) or not isinstance(authority_payload, dict):
        raise AuthorityError("RunReceipt is missing range or authority")
    expression = range_payload.get("expression")
    kinds = payload.get("changeKinds")
    records = payload.get("evidence")
    if not isinstance(expression, str) or not isinstance(kinds, list) or not isinstance(records, list):
        raise AuthorityError("RunReceipt has invalid range, ChangeKind, or evidence fields")
    inputs = []
    for record in records:
        if not isinstance(record, dict):
            raise AuthorityError("RunReceipt evidence entries must be objects")
        kind = record.get("kind")
        path = record.get("path")
        if not isinstance(kind, str) or not isinstance(path, str):
            raise AuthorityError("RunReceipt evidence entries need kind and path")
        inputs.append(EvidenceInput(kind, Path(path)))
    approval_entry = authority_payload.get("approval")
    approval_path = None
    if approval_entry is not None:
        if not isinstance(approval_entry, dict) or not isinstance(approval_entry.get("path"), str):
            raise AuthorityError("RunReceipt approval pointer is invalid")
        approval_path = Path(str(approval_entry["path"]))
    expected = build_run_receipt(
        repository,
        expression,
        kinds,
        inputs,
        approval_path,
    )
    if payload != expected:
        raise AuthorityError(
            "RunReceipt is stale or tampered; regenerate it from current artifacts"
        )
    print(
        f"RunReceipt valid: {authority_payload.get('decision')} "
        f"({authority_payload.get('status')})"
    )
    return 0


def add_common_range_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("range")
    parser.add_argument("--repository", type=Path, default=REPOSITORY_ROOT)
    parser.add_argument(
        "--change-kind",
        action="append",
        default=[],
        choices=[kind.value for kind in ChangeKind],
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate and verify content-bound merge RunReceipts. Hand-authored "
            "evidence manifests are not accepted."
        )
    )
    commands = parser.add_subparsers(dest="command", required=True)

    approval = commands.add_parser("approve", help="bind explicit human approval")
    add_common_range_arguments(approval)
    approval.add_argument("--authority", required=True)
    approval.add_argument("--reference", required=True)
    approval.add_argument("--output", type=Path, required=True)
    approval.set_defaults(handler=create_approval)

    generate_parser = commands.add_parser("generate", help="generate a RunReceipt")
    add_common_range_arguments(generate_parser)
    generate_parser.add_argument(
        "--evidence", type=parse_evidence, action="append", default=[]
    )
    generate_parser.add_argument("--approval", type=Path)
    generate_parser.add_argument("--output", type=Path, required=True)
    generate_parser.set_defaults(handler=generate)

    verify_parser = commands.add_parser("verify", help="verify a RunReceipt")
    verify_parser.add_argument("--repository", type=Path, default=REPOSITORY_ROOT)
    verify_parser.add_argument("--receipt", type=Path, required=True)
    verify_parser.set_defaults(handler=verify)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        return arguments.handler(arguments)
    except (AuthorityError, OSError) as error:
        print(f"FAIL {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
