from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
import errno
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory
from typing import Any, Callable, Iterator, Mapping, Sequence

from regression.core.catalog import load_catalog
from regression.core.contracts import (
    AutomationScope,
    BoundLane,
    ContractReadiness,
    OperationRole,
)
from regression.materialize_catalog_v2 import EXACT_JOURNEY_EDGES
from regression.core.digest import canonical_bytes, canonical_digest, digest_bytes
from regression.core.expression import OracleResult
from regression.core import transition_trace
from regression.core.plan import (
    BuildIdentity,
    LaneBuildArtifact,
    ToolchainIdentity,
    compiled_plan_bytes,
)
from regression.core.replay import replay
from regression.core.review import ReviewClass
from regression.core.runview import NodeStatus, RunOutcome
from regression.execution_identity import (
    INPUT_SCHEMA_VERSION,
    load_execution_input,
    load_frozen_test_launch,
    repository_source_digest,
)
from regression.materialize_catalog_v2 import materialize
from regression.review_stage import _semantic_authority
from regression.runctl import (
    _view_payload,
    compile_execution_plan,
    load_current_reviewed_catalog,
)
from regression.write_set import WritePlan, WriteSetError


PREDICATE_NAMES = (
    "catalog_target_shape",
    "no_legacy_active_contracts",
    "autonomous_semantic_authority",
    "executable_operations_and_oracles",
    "current_review_receipts",
    "governance_guardrails",
    "target_source_topology",
    "retired_legacy_surfaces",
    "comment_boundary",
    "deterministic_checks_green",
    "product_builds_green",
    "both_runtime_lanes_proven",
    "immutable_final_full_run",
    "no_unverified_product_diff",
)

EXPECTED_COUNTS = {
    "promises": 65,
    "journeys": 14,
    "scenarios": 68,
    "operations": 35,
    "oracles": 11,
    "rubrics": 103,
    "preparations": 18,
}

EXPECTED_OPERATION_IDS = frozenset(
    {
        "operation:accessibility.activate@2",
        "operation:accessibility.inspect@2",
        "operation:accessibility.type@2",
        "operation:app.relaunch@1",
        "operation:diagnostics.browse-hierarchy@1",
        "operation:diagnostics.playback-state@1",
        "operation:diagnostics.surface-probe@1",
        "operation:evidence.capture-audio@2",
        "operation:evidence.capture-frames@1",
        "operation:evidence.structural-test@1",
        "operation:format.apply@2",
        "operation:harness.assert-channels@2",
        "operation:harness.ensure-session@1",
        "operation:harness.reset-product-state@2",
        "operation:host.preflight@1",
        "operation:input.device-hub-prepare@1",
        "operation:input.device-hub-pinch@2",
        "operation:issue.present@1",
        "operation:library.snapshot@1",
        "operation:media.import-staged@2",
        "operation:media.open@2",
        "operation:media.stage-fixture@2",
        "operation:navigation.select-tab@1",
        "operation:playback.await-window-state@1",
        "operation:playback.seek@2",
        "operation:playback.select-subtitle@1",
        "operation:playback.wait-position@2",
        "operation:preparation.local-directory-subtitle-source@1",
        "operation:presentation.enter-docked-skybox@1",
        "operation:presentation.enter-panorama@1",
        "operation:presentation.exit-spatial@1",
        "operation:storage.clear@1",
        "operation:transition-trace.arm@1",
        "operation:transition-trace.disarm@1",
        "operation:transition-trace.fetch@1",
    }
)

REQUIRED_PRODUCERS = {
    "operation:diagnostics.playback-state@1": (
        "playback.probe",
        "playback-probe@1",
    ),
    "operation:evidence.structural-test@1": (
        "structural.test",
        "structural-test@2",
    ),
}

REQUIRED_PRODUCT_OPERATIONS = frozenset(
    {"operation:playback.select-subtitle@1"}
)

REQUIRED_PREPARATION_OPERATIONS = {
    "operation:preparation.local-directory-subtitle-source@1": (
        (
            ("directoryName", "string", True),
            ("mediaFileName", "string", True),
            ("memberFileNames", "string-list", True),
        ),
        ("library.command", "library-command@1"),
    )
}

RETIRED_PATHS = (
    "Scripts/verification/regression_journeys.py",
    ".agents/skills/vp-e2e/references/journeys",
    "Scripts/verification/journey_units.py",
    "Config/journey_operation_coverage.json",
    ".claude/hooks/regression_journey_stop_gate.py",
    "Apps/Enchron/Screens/FilesScreen.swift",
)

ACTIVE_REFERENCE_ROOTS = (
    ".agents/skills",
    ".claude",
    ".githooks",
    "Apps",
    "Enchron.xcodeproj",
    "Modules",
    "Packages",
    "Scripts",
    "Tests",
    "Config",
    "Regression",
    "docs",
)

ACTIVE_TEXT_SUFFIXES = frozenset(
    {
        ".json",
        ".md",
        ".pbxproj",
        ".plist",
        ".py",
        ".resolved",
        ".sh",
        ".swift",
        ".toml",
        ".tsv",
        ".txt",
        ".xcconfig",
        ".xml",
        ".yaml",
        ".yml",
        ".zsh",
    }
)

REFERENCE_EXCLUSIONS = frozenset(
    {
        "Scripts/regression/completion.py",
        "Scripts/rules/verify_regression_refactor_complete.py",
        "Scripts/rules/test_regression_refactor_complete.py",
        "Config/retired_documents.json",
    }
)

REQUIRED_VERIFICATION_LAYERS = frozenset(
    {
        "Git hook installation",
        "Structure checks",
        "PlaybackCore tests",
        "Guard self-tests",
        "Domain tests",
        "Source parity",
        "Media discovery capability matrix",
        "Feature evidence coverage",
    }
)

REQUIRED_STRUCTURE_LOGS = frozenset(
    {
        "structure/package-membership.log",
        "structure/playback-surface-structure.log",
        "structure/product-source-comments.log",
        "structure/release-test-channel-absent.log",
        "structure/regression-core-layering.log",
        "structure/documentation-references.log",
        "structure/scripts-inventory.log",
        "structure/test-merge-authority.log",
        "structure/test-regression-write-set.log",
    }
)

EXPECTED_BUSINESS_DEPENDENCIES = {
    "MediaSource": frozenset(),
    "DesignSystem": frozenset(),
    "MediaLibrary": frozenset({"MediaSource", "DesignSystem"}),
    "Playback": frozenset({"MediaSource", "DesignSystem"}),
    "Emby": frozenset({"MediaSource", "DesignSystem", "Playback"}),
}

AUDIT_EVIDENCE_NAMES = (
    "no-comments",
    "interrogate",
    "blast-radius",
    "vp-e2e",
)

AUDIT_RESULT_SCHEMA = "enchron.regression.audit-result"
WRITE_SET_RECEIPT_SCHEMA = "enchron.regression.actual-write-set-receipt"
PRODUCT_SWIFT_COVERAGE_SCHEMA = "enchron.regression.product-swift-coverage"
XCODE_BUILD_RESULT_SCHEMA = "enchron.regression.xcode-build-result"

SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
FINAL_BUILD_LANES = (BoundLane.SIMULATOR, BoundLane.DEVICE)


class CompletionError(ValueError):
    pass


@dataclass(frozen=True)
class PredicateResult:
    name: str
    passed: bool
    detail: str

    def payload(self) -> dict[str, object]:
        return {
            "name": self.name,
            "passed": self.passed,
            "detail": self.detail,
        }


@dataclass(frozen=True)
class CompletionReport:
    predicates: tuple[PredicateResult, ...]

    def __post_init__(self) -> None:
        values = tuple(self.predicates)
        if tuple(item.name for item in values) != PREDICATE_NAMES:
            raise CompletionError("completion report must contain the exact DoD predicates")
        if any(type(item.passed) is not bool or not item.detail for item in values):
            raise CompletionError("completion results need a boolean and non-empty detail")
        object.__setattr__(self, "predicates", values)

    @property
    def done(self) -> bool:
        return all(item.passed for item in self.predicates)

    def payload(self) -> dict[str, object]:
        return {
            "done": self.done,
            "predicates": [item.payload() for item in self.predicates],
        }


@dataclass(frozen=True)
class CompletionPaths:
    repository_root: Path
    final_root: Path
    catalog_root: Path
    blueprint_path: Path
    policy_path: Path
    reviews_root: Path
    semantic_authority_path: Path
    configuration_receipt_path: Path
    execution_input_path: Path
    compiled_plan_path: Path
    full_run_directory: Path
    audit_manifest_path: Path
    test_override: bool = False

    @classmethod
    def for_repository(cls, repository_root: Path) -> "CompletionPaths":
        repository = _canonical_boundary_path(
            repository_root, "repository root"
        )
        return cls._build(repository, repository / ".scratch/Regression/final", False)

    @classmethod
    def for_tests(
        cls, repository_root: Path, final_root: Path
    ) -> "CompletionPaths":
        repository = _canonical_boundary_path(
            repository_root, "test repository root"
        )
        final = _canonical_boundary_path(final_root, "test final artifact root")
        try:
            final.relative_to(repository)
        except ValueError as error:
            raise CompletionError("test final root must stay inside the test repository") from error
        return cls._build(repository, final, True)

    @classmethod
    def _build(
        cls, repository: Path, final: Path, test_override: bool
    ) -> "CompletionPaths":
        return cls(
            repository,
            final,
            repository / "Regression",
            repository / "Config/regression/catalog-v2.json",
            repository / "Regression/review-policy.md",
            repository / "Regression/reviews",
            repository / "Regression/semantic-authority.json",
            final / "configuration-receipt.json",
            final / "execution-input.json",
            final / "compiled-plan.json",
            final / "full-run",
            final / "audit-manifest.json",
            test_override,
        )


@dataclass(frozen=True)
class AuditProof:
    manifest_path: Path
    verification_path: Path
    verification_record: dict[str, str]
    verification_summary: Mapping[str, Any]
    verification_log_records: tuple[dict[str, str], ...]
    verification_log_sources: Mapping[str, bytes]
    evidence_paths: Mapping[str, Path]
    write_set: "WriteSetProof"
    product_swift_coverage: "ProductSwiftCoverageProof"


@dataclass(frozen=True)
class ConfigurationProof:
    receipt_path: Path
    source_digest: str
    merge_receipt_path: Path
    build_results: Mapping[str, "BuildResultProof"]
    verification_record: dict[str, str]


@dataclass(frozen=True)
class BuildResultProof:
    result_path: Path
    lane: BoundLane
    source_digest: str
    command: tuple[str, ...]
    destination: str
    developer_directory: str
    toolchain: ToolchainIdentity
    xctestrun_path: Path
    lane_artifact: LaneBuildArtifact
    log_path: Path


@dataclass(frozen=True)
class WriteSetProof:
    receipt_path: Path
    source_digest: str
    range: Mapping[str, str]
    plan: WritePlan
    actual_paths: tuple[str, ...]


@dataclass(frozen=True)
class FocusedTestProof:
    identifier: str
    log_record: dict[str, str]


@dataclass(frozen=True)
class RuntimeObservationProof:
    node_id: str
    evidence_digest: str


@dataclass(frozen=True)
class ProductSwiftCoverageEntry:
    path: str
    focused_test: FocusedTestProof
    runtime_observation: RuntimeObservationProof


@dataclass(frozen=True)
class ProductSwiftCoverageProof:
    receipt_path: Path
    source_digest: str
    range: Mapping[str, str]
    files: tuple[ProductSwiftCoverageEntry, ...]


@dataclass(frozen=True)
class CatalogProof:
    blueprint: Mapping[str, Any]
    report: Mapping[str, Any]
    catalog: Any

    @property
    def blueprint_digest(self) -> str:
        return str(self.blueprint["contentDigest"])

    @property
    def catalog_digest(self) -> str:
        return str(self.catalog.digest)


@dataclass(frozen=True)
class ReviewProof:
    completed: Any

    @property
    def digest(self) -> str:
        return str(self.completed.digest)


@dataclass(frozen=True)
class SemanticProof:
    digest: str
    decision_digests: tuple[str, ...]


@dataclass(frozen=True)
class PlanProof:
    plan: Any
    execution: Any


@dataclass(frozen=True)
class RunProof:
    summary: Mapping[str, Any]
    view: Any


class _DuplicateKeyError(ValueError):
    pass


class _InvalidConstantError(ValueError):
    pass


def _unique_object(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise _DuplicateKeyError(key)
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise _InvalidConstantError(value)


def _current_file(path: Path, label: str) -> Path:
    candidate = Path(path)
    if candidate.is_symlink() or not candidate.is_file():
        raise CompletionError(f"missing current {label}: {candidate}")
    return candidate


def _decode_json_bytes(source: bytes, label: str) -> Any:
    try:
        return json.loads(
            source.decode("utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except UnicodeDecodeError as error:
        raise CompletionError(f"{label} must be UTF-8") from error
    except _DuplicateKeyError as error:
        raise CompletionError(f"{label} repeats field {error.args[0]!r}") from error
    except (_InvalidConstantError, json.JSONDecodeError) as error:
        raise CompletionError(f"{label} is not valid JSON: {error}") from error


def _load_json(path: Path, label: str, *, canonical: bool = False) -> Any:
    source_path = _current_file(path, label)
    source = source_path.read_bytes()
    value = _decode_json_bytes(source, label)
    if canonical and canonical_bytes(value) + b"\n" != source:
        raise CompletionError(f"{label} must use canonical JSON with one newline")
    return value


def _object(
    value: object, fields: Sequence[str], location: str
) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise CompletionError(f"{location} must be a JSON object")
    expected = frozenset(fields)
    missing = sorted(expected - set(value))
    unknown = sorted(set(value) - expected)
    if missing:
        raise CompletionError(f"{location} misses field(s): {', '.join(missing)}")
    if unknown:
        raise CompletionError(f"{location} has unknown field(s): {', '.join(unknown)}")
    return value


def _digest(value: object, location: str) -> str:
    if not isinstance(value, str) or SHA256.fullmatch(value) is None:
        raise CompletionError(f"{location} must be a SHA-256 identity")
    return value


def _text(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CompletionError(f"{location} must be non-empty text")
    return value


def _receipt_range(value: object, location: str) -> Mapping[str, str]:
    parsed = _object(
        value,
        ("expression", "baseCommit", "headCommit", "diffSha256"),
        location,
    )
    expression = _text(parsed["expression"], f"{location}.expression")
    commits: dict[str, str] = {}
    for field in ("baseCommit", "headCommit"):
        commit = _text(parsed[field], f"{location}.{field}")
        if re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit) is None:
            raise CompletionError(f"{location}.{field} must be a full Git object ID")
        commits[field] = commit
    return {
        "expression": expression,
        **commits,
        "diffSha256": _digest(parsed["diffSha256"], f"{location}.diffSha256"),
    }


def _toolchain_identity(value: object, location: str) -> ToolchainIdentity:
    parsed = _object(
        value,
        (
            "xcodeVersion",
            "xcodeBuild",
            "visionOSSDKVersion",
            "visionOSSDKBuild",
            "visionOSSimulatorSDKVersion",
            "visionOSSimulatorSDKBuild",
        ),
        location,
    )
    return ToolchainIdentity(
        _text(parsed["xcodeVersion"], f"{location}.xcodeVersion"),
        _text(parsed["xcodeBuild"], f"{location}.xcodeBuild"),
        _text(parsed["visionOSSDKVersion"], f"{location}.visionOSSDKVersion"),
        _text(parsed["visionOSSDKBuild"], f"{location}.visionOSSDKBuild"),
        _text(
            parsed["visionOSSimulatorSDKVersion"],
            f"{location}.visionOSSimulatorSDKVersion",
        ),
        _text(
            parsed["visionOSSimulatorSDKBuild"],
            f"{location}.visionOSSimulatorSDKBuild",
        ),
    )


def _canonical_boundary_path(path: Path, label: str) -> Path:
    absolute = Path(os.path.abspath(os.fspath(path)))
    parts = absolute.parts
    if not absolute.is_absolute() or not parts:
        raise CompletionError(f"{label} must be an absolute path")
    if len(parts) == 1:
        return absolute
    system_entry = Path(absolute.anchor) / parts[1]
    try:
        canonical_entry = system_entry.resolve(strict=True)
    except FileNotFoundError as error:
        raise CompletionError(f"missing current {label}: {absolute}") from error
    except OSError as error:
        raise CompletionError(
            f"{label} cannot canonicalize its system ancestor: {absolute}"
        ) from error
    except RuntimeError as error:
        raise CompletionError(
            f"{label} contains an invalid symbolic link: {absolute}"
        ) from error
    return canonical_entry.joinpath(*parts[2:])


def _no_follow_directory_flags() -> int:
    no_follow = getattr(os, "O_NOFOLLOW", None)
    directory = getattr(os, "O_DIRECTORY", None)
    if no_follow is None or directory is None:
        raise CompletionError(
            "completion artifact verification requires no-follow directory access"
        )
    return os.O_RDONLY | directory | no_follow


@contextmanager
def _open_directory_boundary(
    path: Path, label: str
) -> Iterator[tuple[Path, int]]:
    root = _canonical_boundary_path(path, label)
    flags = _no_follow_directory_flags()
    opened: list[int] = []
    try:
        current_fd = os.open(root.anchor, flags)
        opened.append(current_fd)
        for component in root.parts[1:]:
            current_fd = os.open(
                component,
                flags,
                dir_fd=current_fd,
            )
            opened.append(current_fd)
    except OSError as error:
        for descriptor in reversed(opened):
            os.close(descriptor)
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            detail = "contains a symbolic link or non-directory component"
        elif error.errno == errno.ENOENT:
            raise CompletionError(f"missing current {label}: {root}") from error
        else:
            detail = f"cannot be opened: {error.strerror or error}"
        raise CompletionError(f"{label} {detail}: {root}") from error
    try:
        yield root, current_fd
    finally:
        for descriptor in reversed(opened):
            os.close(descriptor)


def _artifact_root(final_root: Path) -> Path:
    with _open_directory_boundary(
        final_root, "final artifact root"
    ) as (root, _):
        return root


def artifact_record(path: Path, final_root: Path) -> dict[str, str]:
    root = _artifact_root(final_root)
    candidate = _canonical_boundary_path(path, "artifact")
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise CompletionError(f"artifact must stay inside final root: {candidate}") from error
    _, _, source = _read_boundary_file(
        root,
        relative.as_posix(),
        "artifact",
        "final artifact root",
    )
    return {
        "path": relative.as_posix(),
        "sha256": str(digest_bytes(source)),
    }


def _resolve_artifact_source(
    value: object, final_root: Path, location: str
) -> tuple[Path, dict[str, str], bytes]:
    record = _object(value, ("path", "sha256"), location)
    path_value = record["path"]
    if not isinstance(path_value, str) or not path_value:
        raise CompletionError(f"{location}.path must be non-empty text")
    relative = PurePosixPath(path_value)
    if relative.is_absolute() or ".." in relative.parts or relative.as_posix() != path_value:
        raise CompletionError(f"{location}.path must be normalized and relative")
    expected = _digest(record["sha256"], f"{location}.sha256")
    _, resolved, source = _read_boundary_file(
        final_root,
        path_value,
        f"{location} artifact",
        "final artifact root",
    )
    actual = str(digest_bytes(source))
    if actual != expected:
        raise CompletionError(f"{location} artifact digest differs from recorded digest")
    return resolved, {"path": path_value, "sha256": expected}, source


def _resolve_artifact(
    value: object, final_root: Path, location: str
) -> tuple[Path, dict[str, str]]:
    path, record, _ = _resolve_artifact_source(value, final_root, location)
    return path, record


def _full_run_root(path: Path) -> Path:
    with _open_directory_boundary(
        path, "FullRun directory"
    ) as (root, _):
        return root


def _relative_parts(value: object, location: str) -> tuple[str, ...]:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise CompletionError(f"{location} must be a normalized relative POSIX path")
    relative = PurePosixPath(value)
    parts = relative.parts
    if (
        relative.is_absolute()
        or not parts
        or any(part in ("", ".", "..") for part in parts)
        or "/".join(parts) != value
    ):
        raise CompletionError(f"{location} must be a normalized relative POSIX path")
    return parts


def _read_boundary_file(
    root_path: Path,
    relative_path: object,
    label: str,
    root_label: str,
) -> tuple[Path, Path, bytes]:
    parts = _relative_parts(relative_path, f"{label} path")
    no_follow = getattr(os, "O_NOFOLLOW", None)
    directory = getattr(os, "O_DIRECTORY", None)
    if no_follow is None or directory is None:
        raise CompletionError(
            "completion artifact verification requires no-follow directory access"
        )
    opened: list[int] = []
    with _open_directory_boundary(root_path, root_label) as (root, root_fd):
        try:
            current_fd = root_fd
            for component in parts[:-1]:
                current_fd = os.open(
                    component,
                    os.O_RDONLY | directory | no_follow,
                    dir_fd=current_fd,
                )
                opened.append(current_fd)
            file_fd = os.open(
                parts[-1],
                os.O_RDONLY | os.O_NONBLOCK | no_follow,
                dir_fd=current_fd,
            )
            opened.append(file_fd)
            metadata = os.fstat(file_fd)
            if not stat.S_ISREG(metadata.st_mode):
                raise CompletionError(f"{label} must be a regular non-symlink file")
            chunks: list[bytes] = []
            while True:
                chunk = os.read(file_fd, 1024 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
            return root, root.joinpath(*parts), b"".join(chunks)
        except CompletionError:
            raise
        except OSError as error:
            location = root.joinpath(*parts)
            if error.errno in (errno.ELOOP, errno.ENOTDIR):
                detail = "contains a symbolic link or non-directory component"
            elif error.errno == errno.ENOENT:
                raise CompletionError(
                    f"missing current {label}: {location}"
                ) from error
            else:
                detail = f"cannot be read: {error.strerror or error}"
            raise CompletionError(f"{label} {detail}: {location}") from error
        finally:
            for descriptor in reversed(opened):
                os.close(descriptor)


def _read_full_run_file(
    full_run_directory: Path,
    relative_path: object,
    label: str,
) -> bytes:
    _, _, source = _read_boundary_file(
        full_run_directory,
        relative_path,
        label,
        "FullRun directory",
    )
    return source


def _load_full_run_json(
    full_run_directory: Path,
    relative_path: str,
    label: str,
    *,
    canonical: bool = False,
) -> Any:
    source = _read_full_run_file(
        full_run_directory,
        relative_path,
        label,
    )
    value = _decode_json_bytes(source, label)
    if canonical and canonical_bytes(value) + b"\n" != source:
        raise CompletionError(f"{label} must use canonical JSON with one newline")
    return value


def _read_boundary_path(
    path: Path,
    root_path: Path,
    label: str,
    root_label: str,
) -> tuple[Path, bytes]:
    root = _canonical_boundary_path(root_path, root_label)
    candidate = _canonical_boundary_path(path, label)
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise CompletionError(f"{label} must stay inside {root_label}") from error
    _, resolved, source = _read_boundary_file(
        root_path,
        relative.as_posix(),
        label,
        root_label,
    )
    return resolved, source


def _load_boundary_json(
    path: Path,
    root_path: Path,
    label: str,
    root_label: str,
    *,
    canonical: bool = False,
) -> tuple[Path, Any]:
    resolved, source = _read_boundary_path(
        path,
        root_path,
        label,
        root_label,
    )
    value = _decode_json_bytes(source, label)
    if canonical and canonical_bytes(value) + b"\n" != source:
        raise CompletionError(f"{label} must use canonical JSON with one newline")
    return resolved, value


def _attachment_relative_path(
    full_run_directory: Path,
    lease_id: object,
    value: object,
    location: str,
) -> str:
    if not isinstance(value, str) or not value:
        raise CompletionError(f"{location}.path must be non-empty text")
    candidate = Path(value)
    if not candidate.is_absolute():
        raise CompletionError(
            f"{location}.path must be inside the current assignment attachment directory"
        )
    root = _full_run_root(full_run_directory)
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise CompletionError(
            f"{location}.path must be inside the current assignment attachment directory"
        ) from error
    parts = _relative_parts(relative.as_posix(), f"{location}.path")
    lease_component = str(lease_id)
    expected_prefix = (
        "assignments",
        lease_component,
        "evidence",
        "attachments",
    )
    if (
        _relative_parts(lease_component, f"{location} lease ID")
        != (lease_component,)
        or len(parts) <= len(expected_prefix)
        or parts[: len(expected_prefix)] != expected_prefix
    ):
        raise CompletionError(
            f"{location}.path must be inside the current assignment attachment directory"
        )
    return "/".join(parts)


def _validate_evidence_attachments(
    full_run_directory: Path,
    lease_id: object,
    evidence: object,
    location: str,
) -> None:
    if not isinstance(evidence, dict):
        raise CompletionError(f"{location} must be a JSON object")
    attachments = evidence.get("attachments")
    if not isinstance(attachments, list):
        raise CompletionError(f"{location}.attachments must be an array")
    for index, value in enumerate(attachments):
        attachment_location = f"{location}.attachments[{index}]"
        attachment = _object(
            value,
            ("role", "mediaType", "path", "byteLength", "digest"),
            attachment_location,
        )
        relative_path = _attachment_relative_path(
            full_run_directory,
            lease_id,
            attachment["path"],
            attachment_location,
        )
        data = _read_full_run_file(
            full_run_directory,
            relative_path,
            f"{attachment_location} attachment",
        )
        byte_length = attachment["byteLength"]
        if type(byte_length) is not int or byte_length < 0:
            raise CompletionError(
                f"{attachment_location}.byteLength must be a non-negative integer"
            )
        if len(data) != byte_length:
            raise CompletionError(
                f"{attachment_location} attachment length differs from evidence JSON"
            )
        expected_digest = _digest(
            attachment["digest"], f"{attachment_location}.digest"
        )
        if str(digest_bytes(data)) != expected_digest:
            raise CompletionError(
                f"{attachment_location} attachment digest differs from evidence JSON"
            )


def _validate_accepted_artifacts(full_run_directory: Path, view: Any) -> None:
    root = _full_run_root(full_run_directory)
    for lease in view.leases:
        lease_id = str(lease.lease_id)
        for index, artifact in enumerate(lease.evidence):
            location = f"accepted artifact {lease_id}[{index}]"
            digest = _digest(str(artifact.digest), f"{location}.digest")
            byte_length = artifact.byte_length
            if type(byte_length) is not int or byte_length <= 0:
                raise CompletionError(f"{location}.byteLength must be positive")
            expected_object_path = f"objects/sha256/{digest[7:]}"
            if artifact.object_path != expected_object_path:
                raise CompletionError(
                    f"{location} CAS evidence object must use its digest path inside FullRun"
                )
            object_bytes = _read_full_run_file(
                root,
                artifact.object_path,
                f"{location} CAS evidence object",
            )
            if len(object_bytes) != byte_length:
                raise CompletionError(
                    f"{location} CAS evidence object byte length differs from the ledger"
                )
            if str(digest_bytes(object_bytes)) != digest:
                raise CompletionError(
                    f"{location} CAS evidence object digest differs from the ledger"
                )

            receipt_value = {
                "leaseId": lease_id,
                "evidenceSchema": str(artifact.evidence_schema),
                "relativePath": artifact.relative_path,
                "byteLength": byte_length,
                "digest": digest,
                "objectPath": artifact.object_path,
            }
            receipt_digest = _digest(
                str(artifact.receipt_digest), f"{location}.receiptDigest"
            )
            if str(canonical_digest(receipt_value)) != receipt_digest:
                raise CompletionError(
                    f"{location} artifact receipt digest does not bind the ledger fields"
                )
            receipt_path = f"receipts/artifacts/{receipt_digest[7:]}.json"
            receipt_bytes = _read_full_run_file(
                root,
                receipt_path,
                f"{location} artifact receipt",
            )
            if receipt_bytes != canonical_bytes(receipt_value) + b"\n":
                raise CompletionError(
                    f"{location} artifact receipt must be canonical JSON and exactly bind "
                    "lease ID, evidence schema, relative path, byte length, digest, and object path"
                )

            evidence = _decode_json_bytes(
                object_bytes, f"{location} CAS evidence object"
            )
            if canonical_bytes(evidence) + b"\n" != object_bytes:
                raise CompletionError(
                    f"{location} CAS evidence object must use canonical JSON encoding"
                )
            _validate_evidence_attachments(root, lease_id, evidence, location)


def _verification_summary(
    path: Path, *, source: bytes | None = None
) -> Mapping[str, Any]:
    value = _object(
        (
            _load_json(path, "pre-freeze verification summary")
            if source is None
            else _decode_json_bytes(source, "pre-freeze verification summary")
        ),
        (
            "version",
            "startedAt",
            "finishedAt",
            "mode",
            "repository",
            "developerDirectory",
            "layers",
            "verdict",
        ),
        "pre-freeze verification summary",
    )
    if value["version"] != 1 or value["mode"] != "full" or value["verdict"] != "passed":
        raise CompletionError("pre-freeze verification must be version 1 full mode with verdict passed")
    for field in ("repository", "developerDirectory"):
        if not isinstance(value[field], str) or not value[field].strip():
            raise CompletionError(f"pre-freeze verification {field} must be non-empty text")
    timestamps: list[datetime] = []
    for field in ("startedAt", "finishedAt"):
        raw = value[field]
        if not isinstance(raw, str) or not raw.strip():
            raise CompletionError(f"pre-freeze verification {field} must be an RFC 3339 timestamp")
        candidate = raw[:-1] + "+00:00" if raw.endswith("Z") else raw
        try:
            parsed = datetime.fromisoformat(candidate)
        except ValueError as error:
            raise CompletionError(f"pre-freeze verification {field} must be an RFC 3339 timestamp") from error
        if parsed.tzinfo is None:
            raise CompletionError(f"pre-freeze verification {field} must include a UTC offset")
        timestamps.append(parsed)
    if timestamps[1] < timestamps[0]:
        raise CompletionError("pre-freeze verification finishedAt precedes startedAt")
    layers = value["layers"]
    if not isinstance(layers, list) or not layers:
        raise CompletionError("pre-freeze verification layers must be non-empty")
    names: set[str] = set()
    structure_logs: frozenset[str] = frozenset()
    all_logs: set[str] = set()
    for index, item in enumerate(layers):
        layer = _object(item, ("name", "state", "detail", "logs"), f"verification.layers[{index}]")
        name = layer["name"]
        if not isinstance(name, str) or not name or name in names:
            raise CompletionError("pre-freeze verification layer names must be unique non-empty text")
        names.add(name)
        if layer["state"] != "PASS":
            raise CompletionError(f"pre-freeze verification layer {name!r} is failed or skipped")
        if not isinstance(layer["detail"], str) or not layer["detail"]:
            raise CompletionError(f"pre-freeze verification layer {name!r} has no detail")
        logs = layer["logs"]
        if not isinstance(logs, list) or any(not isinstance(log, str) or not log for log in logs):
            raise CompletionError(f"pre-freeze verification layer {name!r} has invalid logs")
        if len(logs) != len(set(logs)):
            raise CompletionError(f"pre-freeze verification layer {name!r} repeats a log")
        overlap = all_logs & set(logs)
        if overlap:
            raise CompletionError(
                "pre-freeze verification repeats log(s) across layers: "
                + ", ".join(sorted(overlap))
            )
        all_logs.update(logs)
        if name == "Structure checks":
            structure_logs = frozenset(logs)
    missing_layers = sorted(REQUIRED_VERIFICATION_LAYERS - names)
    if missing_layers:
        raise CompletionError("pre-freeze verification misses layer(s): " + ", ".join(missing_layers))
    missing_logs = sorted(REQUIRED_STRUCTURE_LOGS - structure_logs)
    if missing_logs:
        raise CompletionError("pre-freeze verification misses structure log(s): " + ", ".join(missing_logs))
    return value


def _verification_log_names(summary: Mapping[str, Any]) -> tuple[str, ...]:
    return tuple(
        log
        for layer in summary["layers"]
        for log in layer["logs"]
    )


def verification_log_records(
    verification_path: Path,
    final_root: Path,
) -> tuple[dict[str, str], ...]:
    resolved, source = _read_boundary_path(
        verification_path,
        final_root,
        "pre-freeze verification summary",
        "final artifact root",
    )
    summary = _verification_summary(resolved, source=source)
    root = _artifact_root(final_root)
    summary_parent = resolved.relative_to(root).parent
    records: list[dict[str, str]] = []
    for name in _verification_log_names(summary):
        parts = _relative_parts(name, "pre-freeze verification log")
        relative = PurePosixPath(summary_parent.as_posix(), *parts).as_posix()
        _, _, log_source = _read_boundary_file(
            root,
            relative,
            f"pre-freeze verification log {name}",
            "final artifact root",
        )
        if not log_source:
            raise CompletionError(
                f"pre-freeze verification log {name} must not be empty"
            )
        records.append(
            {"path": relative, "sha256": str(digest_bytes(log_source))}
        )
    return tuple(sorted(records, key=lambda item: item["path"]))


def _canonical_artifact_json(source: bytes, location: str) -> Mapping[str, Any]:
    value = _decode_json_bytes(source, location)
    if canonical_bytes(value) + b"\n" != source:
        raise CompletionError(f"{location} must use canonical JSON with one newline")
    if not isinstance(value, dict):
        raise CompletionError(f"{location} must be a JSON object")
    return value


def _audit_result(
    source: bytes,
    name: str,
    expected_source_digest: str,
) -> None:
    location = f"evidence.{name}"
    value = _object(
        _canonical_artifact_json(source, location),
        ("schema", "schemaVersion", "audit", "sourceDigest", "verdict"),
        location,
    )
    if value["schema"] != AUDIT_RESULT_SCHEMA or value["schemaVersion"] != 1:
        raise CompletionError(f"{location} audit result schema is unsupported")
    if value["audit"] != name:
        raise CompletionError(f"{location} has the wrong audit type")
    if _digest(value["sourceDigest"], f"{location}.sourceDigest") != expected_source_digest:
        raise CompletionError(f"{location} source digest is stale")
    if value["verdict"] != "passed":
        raise CompletionError(f"{location} audit verdict is not passed")


def _write_set_proof(
    path: Path,
    source: bytes,
    expected_source_digest: str,
) -> WriteSetProof:
    location = "actual write-set receipt"
    value = _object(
        _canonical_artifact_json(source, location),
        ("schema", "schemaVersion", "sourceDigest", "range", "tasks"),
        location,
    )
    if value["schema"] != WRITE_SET_RECEIPT_SCHEMA or value["schemaVersion"] != 1:
        raise CompletionError("actual write-set receipt schema is unsupported")
    source_digest = _digest(value["sourceDigest"], f"{location}.sourceDigest")
    if source_digest != expected_source_digest:
        raise CompletionError("actual write-set receipt source digest is stale")
    receipt_range = _receipt_range(value["range"], f"{location}.range")
    raw_tasks = value["tasks"]
    if not isinstance(raw_tasks, list) or not raw_tasks:
        raise CompletionError("actual write-set receipt tasks must be non-empty")
    plan_tasks: list[dict[str, object]] = []
    actual_paths: list[str] = []
    for index, raw_task in enumerate(raw_tasks):
        task_location = f"{location}.tasks[{index}]"
        task = _object(
            raw_task,
            ("id", "dependsOn", "writes", "actualPaths"),
            task_location,
        )
        identifier = _text(task["id"], f"{task_location}.id")
        dependencies = task["dependsOn"]
        writes = task["writes"]
        claimed = task["actualPaths"]
        if not isinstance(dependencies, list):
            raise CompletionError(f"{task_location}.dependsOn must be an array")
        if not isinstance(writes, list):
            raise CompletionError(f"{task_location}.writes must be an array")
        if not isinstance(claimed, list):
            raise CompletionError(f"{task_location}.actualPaths must be an array")
        plan_tasks.append(
            {"id": identifier, "dependsOn": dependencies, "writes": writes}
        )
        normalized_claims: list[str] = []
        for claim_index, claimed_path in enumerate(claimed):
            parts = _relative_parts(
                claimed_path,
                f"{task_location}.actualPaths[{claim_index}]",
            )
            normalized_claims.append("/".join(parts))
        if normalized_claims != sorted(set(normalized_claims)):
            raise CompletionError(
                f"{task_location}.actualPaths must be sorted and unique"
            )
        actual_paths.extend(normalized_claims)
    try:
        plan = WritePlan.parse({"version": 1, "tasks": plan_tasks})
    except WriteSetError as error:
        raise CompletionError(f"actual write-set receipt is invalid: {error}") from error
    if plan.conflicts():
        raise CompletionError("actual write-set receipt contains unordered writers")
    task_by_id = {task.identifier: task for task in plan.tasks}
    for raw_task in raw_tasks:
        task = task_by_id[str(raw_task["id"])]
        for claimed_path in raw_task["actualPaths"]:
            if not any(scope.contains(claimed_path) for scope in task.writes):
                raise CompletionError(
                    f"actual write {claimed_path} escapes task {task.identifier}'s write set"
                )
    if actual_paths != sorted(set(actual_paths)):
        raise CompletionError(
            "actual write-set receipt must assign each changed path exactly once"
        )
    return WriteSetProof(
        path,
        source_digest,
        receipt_range,
        plan,
        tuple(actual_paths),
    )


def _product_swift_coverage_proof(
    path: Path,
    source: bytes,
    final_root: Path,
    expected_source_digest: str,
    verification_records: Mapping[str, tuple[dict[str, str], bytes]],
) -> ProductSwiftCoverageProof:
    location = "product Swift coverage receipt"
    value = _object(
        _canonical_artifact_json(source, location),
        ("schema", "schemaVersion", "sourceDigest", "range", "files"),
        location,
    )
    if (
        value["schema"] != PRODUCT_SWIFT_COVERAGE_SCHEMA
        or value["schemaVersion"] != 1
    ):
        raise CompletionError("product Swift coverage receipt schema is unsupported")
    source_digest = _digest(value["sourceDigest"], f"{location}.sourceDigest")
    if source_digest != expected_source_digest:
        raise CompletionError("product Swift coverage receipt source digest is stale")
    receipt_range = _receipt_range(value["range"], f"{location}.range")
    raw_files = value["files"]
    if not isinstance(raw_files, list):
        raise CompletionError("product Swift coverage receipt files must be an array")
    entries: list[ProductSwiftCoverageEntry] = []
    for index, raw_entry in enumerate(raw_files):
        entry_location = f"{location}.files[{index}]"
        entry = _object(
            raw_entry,
            ("path", "focusedTest", "runtimeObservation"),
            entry_location,
        )
        product_path = "/".join(
            _relative_parts(entry["path"], f"{entry_location}.path")
        )
        focused = _object(
            entry["focusedTest"],
            ("identifier", "log"),
            f"{entry_location}.focusedTest",
        )
        identifier = _text(
            focused["identifier"], f"{entry_location}.focusedTest.identifier"
        )
        if "test" not in identifier.lower():
            raise CompletionError(
                f"{entry_location}.focusedTest.identifier must name a test"
            )
        _, log_record, log_source = _resolve_artifact_source(
            focused["log"],
            final_root,
            f"{entry_location}.focusedTest.log",
        )
        expected_log = verification_records.get(log_record["path"])
        if expected_log is None or expected_log[0] != log_record:
            raise CompletionError(
                f"{entry_location} focused test log is not named by verification"
            )
        if identifier.encode("utf-8") not in log_source:
            raise CompletionError(
                f"{entry_location} focused test identifier is absent from its log"
            )
        if b"passed" not in log_source.lower() and b"** TEST SUCCEEDED **" not in log_source:
            raise CompletionError(
                f"{entry_location} focused test log has no passing result"
            )
        runtime = _object(
            entry["runtimeObservation"],
            ("nodeId", "evidenceDigest"),
            f"{entry_location}.runtimeObservation",
        )
        entries.append(
            ProductSwiftCoverageEntry(
                product_path,
                FocusedTestProof(identifier, log_record),
                RuntimeObservationProof(
                    _text(
                        runtime["nodeId"],
                        f"{entry_location}.runtimeObservation.nodeId",
                    ),
                    _digest(
                        runtime["evidenceDigest"],
                        f"{entry_location}.runtimeObservation.evidenceDigest",
                    ),
                ),
            )
        )
    paths = [entry.path for entry in entries]
    if paths != sorted(set(paths)):
        raise CompletionError(
            "product Swift coverage receipt files must be sorted and unique"
        )
    return ProductSwiftCoverageProof(
        path,
        source_digest,
        receipt_range,
        tuple(entries),
    )


def validate_audit_manifest(
    manifest_path: Path, final_root: Path, expected_source_digest: str
) -> AuditProof:
    resolved_manifest_path, manifest_value = _load_boundary_json(
        manifest_path,
        final_root,
        "final audit manifest",
        "final artifact root",
        canonical=True,
    )
    manifest = _object(
        manifest_value,
        (
            "schema",
            "schemaVersion",
            "sourceDigest",
            "preFreezeVerification",
            "verificationLogs",
            "evidence",
            "writeSetReceipt",
            "productSwiftCoverage",
        ),
        "final audit manifest",
    )
    if (
        manifest["schema"] != "enchron.regression.final-audit-manifest"
        or manifest["schemaVersion"] != 2
    ):
        raise CompletionError("final audit manifest schema identity is unsupported")
    source_digest = _digest(manifest["sourceDigest"], "final audit manifest.sourceDigest")
    if source_digest != expected_source_digest:
        raise CompletionError("final audit manifest source digest is stale")
    verification_path, verification_record, verification_source = (
        _resolve_artifact_source(
            manifest["preFreezeVerification"],
            final_root,
            "preFreezeVerification",
        )
    )
    summary = _verification_summary(
        verification_path, source=verification_source
    )
    expected_log_records = verification_log_records(
        verification_path,
        final_root,
    )
    raw_log_records = manifest["verificationLogs"]
    if not isinstance(raw_log_records, list):
        raise CompletionError("final audit verificationLogs must be an array")
    log_records: list[dict[str, str]] = []
    log_sources: dict[str, bytes] = {}
    for index, raw_record in enumerate(raw_log_records):
        _, record, log_source = _resolve_artifact_source(
            raw_record,
            final_root,
            f"verificationLogs[{index}]",
        )
        if not log_source:
            raise CompletionError(
                f"verificationLogs[{index}] artifact must not be empty"
            )
        log_records.append(record)
        log_sources[record["path"]] = log_source
    if tuple(log_records) != expected_log_records:
        raise CompletionError(
            "final audit verification logs differ from the exact logs named by the summary"
        )
    verification_records = {
        record["path"]: (record, log_sources[record["path"]])
        for record in log_records
    }
    evidence = _object(manifest["evidence"], AUDIT_EVIDENCE_NAMES, "final audit manifest.evidence")
    evidence_paths: dict[str, Path] = {}
    for name in AUDIT_EVIDENCE_NAMES:
        evidence_path, _, evidence_source = _resolve_artifact_source(
            evidence[name], final_root, f"evidence.{name}"
        )
        _audit_result(evidence_source, name, expected_source_digest)
        evidence_paths[name] = evidence_path
    if len(set(evidence_paths.values())) != len(AUDIT_EVIDENCE_NAMES):
        raise CompletionError("final audit evidence names must bind distinct files")
    if verification_path in set(evidence_paths.values()):
        raise CompletionError("pre-freeze verification must be distinct from audit evidence")
    write_set_path, _, write_set_source = _resolve_artifact_source(
        manifest["writeSetReceipt"],
        final_root,
        "writeSetReceipt",
    )
    write_set = _write_set_proof(
        write_set_path,
        write_set_source,
        expected_source_digest,
    )
    coverage_path, _, coverage_source = _resolve_artifact_source(
        manifest["productSwiftCoverage"],
        final_root,
        "productSwiftCoverage",
    )
    coverage = _product_swift_coverage_proof(
        coverage_path,
        coverage_source,
        final_root,
        expected_source_digest,
        verification_records,
    )
    reserved_paths = {
        verification_path,
        write_set_path,
        coverage_path,
        *evidence_paths.values(),
    }
    if len(reserved_paths) != 3 + len(AUDIT_EVIDENCE_NAMES):
        raise CompletionError(
            "verification, audit, write-set, and product coverage artifacts must be distinct"
        )
    root = _artifact_root(final_root)
    verification_log_paths = {
        root / record["path"] for record in log_records
    }
    if reserved_paths & verification_log_paths:
        raise CompletionError(
            "verification logs must be distinct from receipts and audit results"
        )
    return AuditProof(
        resolved_manifest_path,
        verification_path,
        verification_record,
        summary,
        tuple(log_records),
        log_sources,
        evidence_paths,
        write_set,
        coverage,
    )


def _command_option(command: tuple[str, ...], option: str, location: str) -> str:
    indexes = [index for index, value in enumerate(command) if value == option]
    if len(indexes) != 1 or indexes[0] + 1 >= len(command):
        raise CompletionError(f"{location} must contain exactly one {option} value")
    return command[indexes[0] + 1]


def _build_result(
    result_path: Path,
    source: bytes,
    final_root: Path,
    lane: BoundLane,
    expected_source_digest: str,
    expected_developer_directory: str,
) -> BuildResultProof:
    location = f"configuration.buildLogs.{lane.value}"
    value = _object(
        _canonical_artifact_json(source, location),
        (
            "schema",
            "schemaVersion",
            "lane",
            "sourceDigest",
            "command",
            "destination",
            "developerDirectory",
            "toolchain",
            "xctestrun",
            "laneArtifact",
            "log",
            "verdict",
        ),
        location,
    )
    if value["schema"] != XCODE_BUILD_RESULT_SCHEMA or value["schemaVersion"] != 1:
        raise CompletionError(f"{location} build result schema is unsupported")
    if value["lane"] != lane.value:
        raise CompletionError(f"{location} binds the wrong lane")
    source_digest = _digest(value["sourceDigest"], f"{location}.sourceDigest")
    if source_digest != expected_source_digest:
        raise CompletionError(f"{location} source digest is stale")
    if value["verdict"] != "passed":
        raise CompletionError(f"{location} verdict is not passed")
    raw_command = value["command"]
    if (
        not isinstance(raw_command, list)
        or not raw_command
        or any(
            not isinstance(item, str)
            or not item
            or "\x00" in item
            or "\n" in item
            for item in raw_command
        )
    ):
        raise CompletionError(f"{location}.command must be a non-empty string array")
    command = tuple(raw_command)
    if Path(command[0]).name != "xcodebuild" or command.count("build-for-testing") != 1:
        raise CompletionError(
            f"{location}.command must invoke xcodebuild build-for-testing exactly"
        )
    destination = _text(value["destination"], f"{location}.destination")
    if _command_option(command, "-destination", f"{location}.command") != destination:
        raise CompletionError(f"{location} destination differs from its exact command")
    destination_prefix = (
        "platform=visionOS Simulator,id="
        if lane is BoundLane.SIMULATOR
        else "platform=visionOS,id="
    )
    if not destination.startswith(destination_prefix) or not destination.removeprefix(
        destination_prefix
    ):
        raise CompletionError(f"{location} destination does not identify its lane target")
    derived_data_text = _command_option(
        command,
        "-derivedDataPath",
        f"{location}.command",
    )
    derived_data = Path(derived_data_text)
    if not derived_data.is_absolute() or str(derived_data) != derived_data_text:
        raise CompletionError(f"{location} derived data path must be exact and absolute")
    developer_directory = _text(
        value["developerDirectory"], f"{location}.developerDirectory"
    )
    if (
        not Path(developer_directory).is_absolute()
        or developer_directory != expected_developer_directory
    ):
        raise CompletionError(
            f"{location} developer directory differs from pre-freeze verification"
        )
    toolchain = _toolchain_identity(value["toolchain"], f"{location}.toolchain")
    xctestrun_path, xctestrun_record, xctestrun_source = _resolve_artifact_source(
        value["xctestrun"],
        final_root,
        f"{location}.xctestrun",
    )
    if not xctestrun_source or xctestrun_path.suffix != ".xctestrun":
        raise CompletionError(f"{location} must bind a non-empty .xctestrun")
    products_root = derived_data / "Build/Products"
    try:
        xctestrun_path.relative_to(products_root)
    except ValueError as error:
        raise CompletionError(
            f"{location} .xctestrun is outside the command's DerivedData products"
        ) from error
    artifact_value = _object(
        value["laneArtifact"],
        ("xctestrunDigest", "testProductsDigest", "applicationCodeDigest"),
        f"{location}.laneArtifact",
    )
    lane_artifact = LaneBuildArtifact(
        lane,
        _digest(
            artifact_value["xctestrunDigest"],
            f"{location}.laneArtifact.xctestrunDigest",
        ),
        _digest(
            artifact_value["testProductsDigest"],
            f"{location}.laneArtifact.testProductsDigest",
        ),
        _digest(
            artifact_value["applicationCodeDigest"],
            f"{location}.laneArtifact.applicationCodeDigest",
        ),
    )
    if str(lane_artifact.xctestrun_digest) != xctestrun_record["sha256"]:
        raise CompletionError(
            f"{location} .xctestrun digest differs from its lane artifact"
        )
    log_path, _, log_source = _resolve_artifact_source(
        value["log"], final_root, f"{location}.log"
    )
    exact_invocation = ("$ " + shlex.join(command) + "\n").encode("utf-8")
    if not log_source.startswith(exact_invocation):
        raise CompletionError(f"{location} log does not start with its exact command")
    if b"** BUILD SUCCEEDED **" not in log_source:
        raise CompletionError(f"{location} log has no successful Xcode result")
    if log_path in (result_path, xctestrun_path):
        raise CompletionError(f"{location} result, log, and .xctestrun must be distinct")
    return BuildResultProof(
        result_path,
        lane,
        source_digest,
        command,
        destination,
        developer_directory,
        toolchain,
        xctestrun_path,
        lane_artifact,
        log_path,
    )


def validate_configuration_receipt(
    receipt_path: Path,
    final_root: Path,
    *,
    expected_source_digest: str,
    expected_blueprint_digest: str,
    expected_catalog_digest: str,
    expected_review_digest: str,
    expected_semantic_authority_digest: str,
    expected_verification_record: Mapping[str, str],
    expected_developer_directory: str,
) -> ConfigurationProof:
    resolved_receipt_path, receipt_value = _load_boundary_json(
        receipt_path,
        final_root,
        "configuration receipt",
        "final artifact root",
        canonical=True,
    )
    receipt = _object(
        receipt_value,
        (
            "schema",
            "schemaVersion",
            "sourceDigest",
            "blueprintDigest",
            "catalogDigest",
            "reviewCompletionDigest",
            "semanticAuthorityDigest",
            "preFreezeVerification",
            "mergeRunReceipt",
            "buildLogs",
        ),
        "configuration receipt",
    )
    if (
        receipt["schema"] != "enchron.regression.configuration-receipt"
        or receipt["schemaVersion"] != 1
    ):
        raise CompletionError("configuration receipt schema identity is unsupported")
    identities = {
        "sourceDigest": expected_source_digest,
        "blueprintDigest": expected_blueprint_digest,
        "catalogDigest": expected_catalog_digest,
        "reviewCompletionDigest": expected_review_digest,
        "semanticAuthorityDigest": expected_semantic_authority_digest,
    }
    for field, expected in identities.items():
        if _digest(receipt[field], f"configuration receipt.{field}") != expected:
            raise CompletionError(f"configuration receipt {field} is stale")
    _, verification_record, _ = _resolve_artifact_source(
        receipt["preFreezeVerification"], final_root, "configuration.preFreezeVerification"
    )
    if verification_record != dict(expected_verification_record):
        raise CompletionError("configuration receipt binds a different pre-freeze verification summary")
    merge_path, _, _ = _resolve_artifact_source(
        receipt["mergeRunReceipt"], final_root, "configuration.mergeRunReceipt"
    )
    logs = _object(receipt["buildLogs"], ("simulator", "device"), "configuration.buildLogs")
    build_results: dict[str, BuildResultProof] = {}
    for lane in FINAL_BUILD_LANES:
        result_path, _, source = _resolve_artifact_source(
            logs[lane.value],
            final_root,
            f"configuration.buildLogs.{lane.value}",
        )
        build_results[lane.value] = _build_result(
            result_path,
            source,
            final_root,
            lane,
            expected_source_digest,
            expected_developer_directory,
        )
    result_paths = {item.result_path for item in build_results.values()}
    if len(result_paths) != len(FINAL_BUILD_LANES):
        raise CompletionError("simulator and device must have distinct build results")
    if merge_path in result_paths:
        raise CompletionError("merge RunReceipt must be distinct from build results")
    if len({item.log_path for item in build_results.values()}) != len(FINAL_BUILD_LANES):
        raise CompletionError("simulator and device must have distinct build logs")
    if len({item.xctestrun_path for item in build_results.values()}) != len(FINAL_BUILD_LANES):
        raise CompletionError("simulator and device must have distinct .xctestrun files")
    if len({item.toolchain for item in build_results.values()}) != 1:
        raise CompletionError("simulator and device build results bind different toolchains")
    return ConfigurationProof(
        resolved_receipt_path,
        expected_source_digest,
        merge_path,
        build_results,
        verification_record,
    )


def _regular_source(path: Path, label: str) -> str:
    source_path = _current_file(path, label)
    try:
        return source_path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        raise CompletionError(f"{label} must be UTF-8") from error


def _command(
    arguments: Sequence[str], repository: Path, label: str
) -> str:
    completed = subprocess.run(
        list(arguments),
        cwd=repository,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise CompletionError(f"{label} failed: {detail or f'exit {completed.returncode}'}")
    return completed.stdout


class _CompletionContext:
    def __init__(self, paths: CompletionPaths) -> None:
        self.paths = paths
        self._cache: dict[str, object] = {}

    def _memo(self, key: str, build: Callable[[], Any]) -> Any:
        if key not in self._cache:
            try:
                self._cache[key] = build()
            except Exception as error:
                self._cache[key] = error
        value = self._cache[key]
        if isinstance(value, Exception):
            raise value
        return value

    def source_digest(self) -> str:
        def build() -> str:
            if not self.paths.test_override:
                expected = self.paths.repository_root / ".scratch/Regression/final"
                if self.paths.final_root != expected:
                    raise CompletionError("default final root is not .scratch/Regression/final")
                ignored = subprocess.run(
                    (
                        "git",
                        "-C",
                        str(self.paths.repository_root),
                        "check-ignore",
                        "--no-index",
                        "-q",
                        ".scratch/Regression/final",
                    ),
                    capture_output=True,
                    check=False,
                )
                if ignored.returncode != 0:
                    raise CompletionError("default final root is not ignored by Git")
            return str(repository_source_digest(self.paths.repository_root))

        return self._memo(
            "source",
            build,
        )

    def catalog(self) -> CatalogProof:
        def build() -> CatalogProof:
            _current_file(self.paths.blueprint_path, "Catalog v2 blueprint")
            if not self.paths.catalog_root.is_dir():
                raise CompletionError(f"missing current Markdown Catalog: {self.paths.catalog_root}")
            with TemporaryDirectory(prefix="enchron-completion-catalog-") as temporary:
                scratch = Path(temporary)
                try:
                    report = materialize(
                        self.paths.blueprint_path,
                        scratch / "Catalog",
                        scratch / "report.json",
                        self.paths.catalog_root,
                    )
                except Exception as error:
                    detail = str(error).replace(str(scratch), "<staged-catalog>")
                    raise CompletionError(f"Catalog v2 materialization failed: {detail}") from error
            blueprint = _load_json(self.paths.blueprint_path, "Catalog v2 blueprint")
            if not isinstance(blueprint, dict):
                raise CompletionError("Catalog v2 blueprint must be a JSON object")
            if report.get("blueprintDigest") != blueprint.get("contentDigest"):
                raise CompletionError("Catalog v2 blueprint changed during verification")
            catalog = load_catalog(self.paths.catalog_root)
            analysis = report.get("coreAnalysis")
            if (
                not isinstance(analysis, dict)
                or analysis.get("coreCatalogDigest") != str(catalog.digest)
            ):
                raise CompletionError("Markdown Catalog changed during verification")
            return CatalogProof(blueprint, report, catalog)

        return self._memo("catalog", build)

    def reviews(self) -> ReviewProof:
        def build() -> ReviewProof:
            _, completed = load_current_reviewed_catalog(
                self.paths.repository_root,
                self.paths.catalog_root,
                self.paths.policy_path,
                self.paths.reviews_root,
            )
            return ReviewProof(completed)

        return self._memo("reviews", build)

    def semantic(self) -> SemanticProof:
        def build() -> SemanticProof:
            source_path = _current_file(
                self.paths.semantic_authority_path, "semantic authority"
            )
            authority = _semantic_authority(self.paths.repository_root)
            source = source_path.read_bytes()
            if str(digest_bytes(source)) != str(authority.digest):
                raise CompletionError("semantic authority changed during verification")
            value = _object(
                _load_json(self.paths.semantic_authority_path, "semantic authority"),
                ("version", "authority", "decisions"),
                "semantic authority",
            )
            if source_path.read_bytes() != source:
                raise CompletionError("semantic authority changed during verification")
            decisions = value["decisions"]
            if not isinstance(decisions, list):
                raise CompletionError("semantic authority decisions must be an array")
            digests = tuple(str(canonical_digest(item)) for item in decisions)
            if len(digests) != 24 or len(set(digests)) != 24:
                raise CompletionError("semantic authority decisions need 24 stable unique content identities")
            return SemanticProof(str(authority.digest), digests)

        return self._memo("semantic", build)

    def audit(self) -> AuditProof:
        def build() -> AuditProof:
            return validate_audit_manifest(
                self.paths.audit_manifest_path,
                self.paths.final_root,
                self.source_digest(),
            )

        return self._memo("audit", build)

    def configuration(self) -> ConfigurationProof:
        def build() -> ConfigurationProof:
            catalog = self.catalog()
            reviews = self.reviews()
            semantic = self.semantic()
            audit = self.audit()
            return validate_configuration_receipt(
                self.paths.configuration_receipt_path,
                self.paths.final_root,
                expected_source_digest=self.source_digest(),
                expected_blueprint_digest=catalog.blueprint_digest,
                expected_catalog_digest=catalog.catalog_digest,
                expected_review_digest=reviews.digest,
                expected_semantic_authority_digest=semantic.digest,
                expected_verification_record=audit.verification_record,
                expected_developer_directory=_text(
                    audit.verification_summary["developerDirectory"],
                    "pre-freeze verification developerDirectory",
                ),
            )

        return self._memo("configuration", build)

    def execution(self) -> Any:
        def build() -> Any:
            if INPUT_SCHEMA_VERSION != 2:
                raise CompletionError(
                    "completion requires FrozenExecutionInput schema version 2"
                )
            final_root = _artifact_root(self.paths.final_root)
            execution_path, frozen_source = _read_boundary_path(
                self.paths.execution_input_path,
                final_root,
                "frozen execution input",
                "final artifact root",
            )
            execution = load_execution_input(execution_path)
            if execution.bootstrap:
                raise CompletionError(
                    "frozen execution input was produced with --bootstrap, which "
                    "carries no configuration receipt; completion requires the "
                    "configuration-bound freeze taken after verification passes"
                )
            revalidated_path, revalidated_source = _read_boundary_path(
                self.paths.execution_input_path,
                final_root,
                "frozen execution input",
                "final artifact root",
            )
            if (
                revalidated_path != execution_path
                or revalidated_source != frozen_source
            ):
                raise CompletionError(
                    "execution input changed during schema-v2 revalidation"
                )
            configuration = self.configuration()
            if execution.configuration_receipt != configuration.receipt_path:
                raise CompletionError("execution input binds a different configuration receipt")
            if execution.artifact_root != final_root:
                raise CompletionError("execution input artifact root is not the canonical final root")
            return execution

        return self._memo("execution", build)

    def plan(self) -> PlanProof:
        def build() -> PlanProof:
            execution = self.execution()
            plan, reloaded = compile_execution_plan(
                self.paths.repository_root,
                self.paths.execution_input_path,
                self.paths.catalog_root,
                self.paths.policy_path,
                self.paths.reviews_root,
                self.paths.blueprint_path,
            )
            if reloaded != execution:
                raise CompletionError("execution input changed between reloads")
            _, recorded = _read_boundary_path(
                self.paths.compiled_plan_path,
                self.paths.final_root,
                "recorded compiled plan",
                "final artifact root",
            )
            expected = compiled_plan_bytes(plan) + b"\n"
            if recorded != expected:
                raise CompletionError("current full plan does not compile byte-identically to the recorded plan")
            return PlanProof(plan, execution)

        return self._memo("plan", build)

    def run(self) -> RunProof:
        def build() -> RunProof:
            plan = self.plan().plan
            full_run_root = _full_run_root(self.paths.full_run_directory)
            summary = _object(
                _load_full_run_json(
                    full_run_root,
                    "summary.json",
                    "FullRun summary",
                    canonical=True,
                ),
                (
                    "schema",
                    "schemaVersion",
                    "catalogDigest",
                    "catalogGateDigest",
                    "buildIdentityDigest",
                    "evidenceEnvironmentDigest",
                    "completedByLane",
                    "executionErrors",
                    "run",
                ),
                "FullRun summary",
            )
            if (
                summary["schema"] != "enchron.regression.full-run-summary"
                or summary["schemaVersion"] != 1
            ):
                raise CompletionError("FullRun summary schema identity is unsupported")
            view = replay(full_run_root)
            if summary["run"] != _view_payload(view):
                raise CompletionError("FullRun summary does not match canonical ledger replay")
            bindings = {
                "catalogDigest": str(plan.catalog_digest),
                "catalogGateDigest": str(plan.catalog_gate_digest),
                "buildIdentityDigest": str(plan.build_identity.digest),
                "evidenceEnvironmentDigest": str(plan.evidence_environment_identity.digest),
            }
            for field, expected in bindings.items():
                if summary[field] != expected:
                    raise CompletionError(f"FullRun summary {field} does not bind the current plan")
            if view.plan_digest != plan.plan_digest:
                raise CompletionError("ledger replay plan digest does not bind the current plan")
            _validate_accepted_artifacts(full_run_root, view)
            return RunProof(summary, view)

        return self._memo("run", build)


def _catalog_shape(context: _CompletionContext) -> str:
    proof = context.catalog()
    expected = proof.blueprint.get("expectedCounts")
    if not isinstance(expected, dict):
        raise CompletionError("Catalog v2 blueprint expectedCounts must be an object")
    report_counts = proof.report.get("counts")
    if not isinstance(report_counts, dict):
        raise CompletionError("materialized Catalog report counts must be an object")
    for name, count in EXPECTED_COUNTS.items():
        if expected.get(name) != count:
            raise CompletionError(f"Catalog v2 blueprint {name} count must be {count}")
        if report_counts.get(name) != count:
            raise CompletionError(f"materialized Catalog report {name} count must be {count}")
    catalog_counts = {
        "promises": len(proof.catalog.promises),
        "journeys": len(proof.catalog.journeys),
        "scenarios": len(proof.catalog.scenarios),
        "operations": len(proof.catalog.operations),
        "oracles": len(proof.catalog.oracles),
        "rubrics": len(proof.catalog.rubrics),
        "preparations": len(proof.catalog.preparations),
    }
    if catalog_counts != EXPECTED_COUNTS:
        raise CompletionError(f"current Markdown Catalog counts differ: {catalog_counts}")
    operation_ids = frozenset(str(item.id) for item in proof.catalog.operations)
    if operation_ids != EXPECTED_OPERATION_IDS:
        missing = sorted(EXPECTED_OPERATION_IDS - operation_ids)
        extra = sorted(operation_ids - EXPECTED_OPERATION_IDS)
        raise CompletionError(
            f"current Markdown Catalog Operation allowlist differs: missing={missing}, extra={extra}"
        )
    if any(item.scope is not AutomationScope.INCLUDED for item in proof.catalog.promises):
        raise CompletionError("all 65 current Promises must be included")
    if any(item.readiness is not ContractReadiness.READY for item in proof.catalog.scenarios):
        raise CompletionError(
            f"all {EXPECTED_COUNTS['scenarios']} current Scenarios must have v2 readiness ready"
        )
    if any(
        item.readiness is not ContractReadiness.READY or item.blockers
        for item in proof.catalog.preparations
    ):
        raise CompletionError("all 18 current Preparations must have v2 readiness ready")
    if proof.report.get("scenarioReadiness") != {"ready": EXPECTED_COUNTS["scenarios"]}:
        raise CompletionError(
            f"materialized Scenario readiness is not exactly {EXPECTED_COUNTS['scenarios']} ready"
        )
    if proof.report.get("preparationReadiness") != {"ready": 18}:
        raise CompletionError("materialized Preparation readiness is not exactly 18 ready")
    if proof.report.get("scenarioReadinessGaps"):
        raise CompletionError("materialized Catalog contains Scenario readiness gaps")
    if proof.report.get("preparationReadinessGaps"):
        raise CompletionError("materialized Catalog contains Preparation readiness gaps")
    return (
        f"{EXPECTED_COUNTS['promises']} included Promises, {EXPECTED_COUNTS['journeys']} Journeys, "
        f"{EXPECTED_COUNTS['scenarios']} ready Scenarios, {EXPECTED_COUNTS['operations']} Operations, "
        f"{EXPECTED_COUNTS['oracles']} Oracles, {EXPECTED_COUNTS['rubrics']} Rubrics, "
        f"and {EXPECTED_COUNTS['preparations']} ready Preparations match v2"
    )


def _no_legacy_contracts(context: _CompletionContext) -> str:
    proof = context.catalog()
    values = tuple(_walk_json(proof.blueprint))
    forbidden = {
        "evidence-bundle",
        "human",
        "wearer",
        "skipped",
        "voided",
        "notApplicable",
    }
    found = sorted(forbidden & set(values))
    if found:
        raise CompletionError("active Catalog contains forbidden legacy values: " + ", ".join(found))
    for value in values:
        if value.startswith("fixture:"):
            raise CompletionError(f"active Catalog retains symbolic fixture alias {value}")
    if proof.report.get("journeyEdges") is None or len(
        proof.report["journeyEdges"]
    ) != len(EXACT_JOURNEY_EDGES):
        raise CompletionError(
            "active Catalog does not have the exact executable Journey edges"
        )
    return "materialization rejects retired contracts, arbitrary dispatch, fixture aliases, evidence bundles, and narrative-only Journey edges"


def _semantic_authority_predicate(context: _CompletionContext) -> str:
    semantic = context.semantic()
    catalog = context.catalog()
    configuration = context.configuration()
    if configuration.source_digest != context.source_digest():
        raise CompletionError("semantic configuration does not bind current source")
    if len(semantic.decision_digests) != 24:
        raise CompletionError("semantic authority does not contain 24 decisions")
    forbidden = {"skipped", "voided", "notApplicable"}
    runtime_values = {item for item in _walk_json(catalog.blueprint)}
    if forbidden & runtime_values:
        raise CompletionError("runtime Catalog exposes a prohibited non-verdict")
    if {item.value for item in OracleResult} != {"satisfied", "violated", "indeterminate"}:
        raise CompletionError("runtime Oracle result domain contains an unauthorized verdict")
    return "HC-000..023 are exact, decided, content-identified, source-bound, and runtime human actors remain forbidden"


def _executable_closure(context: _CompletionContext) -> str:
    proof = context.catalog()
    operations = {str(item.id): item for item in proof.catalog.operations}
    for identifier in REQUIRED_PRODUCT_OPERATIONS:
        operation = operations.get(identifier)
        if operation is None:
            raise CompletionError(f"missing required product Operation {identifier}")
        if operation.role is not OperationRole.PRODUCT_BEHAVIOR:
            raise CompletionError(
                f"required product Operation {identifier} has role {operation.role.value}"
            )
    for identifier, (fields, pair) in REQUIRED_PREPARATION_OPERATIONS.items():
        operation = operations.get(identifier)
        if operation is None:
            raise CompletionError(f"missing required Preparation Operation {identifier}")
        if operation.role is not OperationRole.SETUP:
            raise CompletionError(
                f"required Preparation Operation {identifier} has role {operation.role.value}"
            )
        actual_fields = tuple(
            (field.name, field.value_type.value, field.required)
            for field in operation.argument_schema.fields
        )
        if actual_fields != fields:
            raise CompletionError(
                f"required Preparation Operation {identifier} has argument closure {actual_fields}"
            )
        actual = {
            (str(item.evidence_type), str(item.evidence_schema))
            for item in operation.evidence_schemas
        }
        if actual != {pair}:
            raise CompletionError(
                f"required Preparation Operation {identifier} has evidence closure {sorted(actual)}"
            )
    for identifier, pair in REQUIRED_PRODUCERS.items():
        operation = operations.get(identifier)
        if operation is None:
            raise CompletionError(f"missing dedicated producer {identifier}")
        actual = {(str(item.evidence_type), str(item.evidence_schema)) for item in operation.evidence_schemas}
        if actual != {pair}:
            raise CompletionError(f"dedicated producer {identifier} has evidence closure {sorted(actual)}")
    for oracle in proof.catalog.oracles:
        if len(oracle.evidence_schemas) != 1:
            raise CompletionError(f"Oracle {oracle.id} must consume exactly one semantic evidence pair")
    for scenario in proof.blueprint["scenarios"]:
        if _contains_two_of_three(scenario["success"]):
            raise CompletionError(
                f"{scenario['id']} contains a forced 2-of-3 runtime contract"
            )
        for failure in transition_trace.failures(scenario):
            raise CompletionError(failure)
    transition_count = transition_trace.count(proof.blueprint["scenarios"])
    if transition_count == 0:
        raise CompletionError("active Catalog contains no transition capture sequence")
    return f"all runtime registry routes close without a 2-of-3 quorum; playback subtitle selection, local-directory Preparation, two dedicated evidence producers, 11 narrow Oracles, and {transition_count} arm/action/fetch/disarm traces are exact"


def _review_receipts(context: _CompletionContext) -> str:
    proof = context.reviews()
    catalog = context.catalog()
    reviewers = {packet.reviewer for packet in proof.completed.packets}
    if reviewers != set(ReviewClass):
        raise CompletionError("review packets do not contain all three current review classes")
    if any(not receipt.accepted for receipt in proof.completed.receipts):
        raise CompletionError("current review completion contains a rejected receipt")
    if str(proof.completed.catalog_digest) != catalog.catalog_digest:
        raise CompletionError("current review completion does not bind the current Catalog")
    context.configuration()
    return f"Deterministic, AgentOperability, and HumanCoverage are complete and content-bound by {proof.digest}"


def _merge_receipt_value(context: _CompletionContext) -> Mapping[str, Any]:
    configuration = context.configuration()
    _, source = _read_boundary_path(
        configuration.merge_receipt_path,
        context.paths.final_root,
        "merge RunReceipt",
        "final artifact root",
    )
    return _object(
        _decode_json_bytes(source, "merge RunReceipt"),
        (
            "schema",
            "range",
            "classifications",
            "tier",
            "changeKinds",
            "authority",
            "tool",
            "environment",
            "evidence",
        ),
        "merge RunReceipt",
    )


def _classification_paths(receipt: Mapping[str, Any]) -> tuple[str, ...]:
    classifications = receipt["classifications"]
    if not isinstance(classifications, list):
        raise CompletionError("merge RunReceipt classifications must be an array")
    paths: list[str] = []
    for index, value in enumerate(classifications):
        location = f"merge RunReceipt.classifications[{index}]"
        item = _object(value, ("path", "tier", "rule"), location)
        path = "/".join(_relative_parts(item["path"], f"{location}.path"))
        _text(item["tier"], f"{location}.tier")
        _text(item["rule"], f"{location}.rule")
        paths.append(path)
    if paths != sorted(set(paths)):
        raise CompletionError(
            "merge RunReceipt classifications must name sorted unique paths"
        )
    return tuple(paths)


def _validate_actual_write_set(
    proof: WriteSetProof,
    merge_receipt: Mapping[str, Any],
) -> None:
    merge_range = _receipt_range(
        merge_receipt["range"], "merge RunReceipt.range"
    )
    if dict(proof.range) != dict(merge_range):
        raise CompletionError(
            "actual write-set receipt binds a different commit range"
        )
    changed_paths = _classification_paths(merge_receipt)
    if proof.actual_paths != changed_paths:
        missing = sorted(set(changed_paths) - set(proof.actual_paths))
        extra = sorted(set(proof.actual_paths) - set(changed_paths))
        raise CompletionError(
            "actual write-set population differs from the merge diff: "
            f"missing={missing}, extra={extra}"
        )


def _governance(context: _CompletionContext) -> str:
    repository = context.paths.repository_root
    tier_path = _current_file(repository / "Scripts/rules/merge_evidence_tier.py", "merge evidence Tier guard")
    authority_path = _current_file(repository / "Scripts/rules/merge_authority.py", "merge authority guard")
    tier_source = tier_path.read_text(encoding="utf-8")
    authority_source = authority_path.read_text(encoding="utf-8")
    if re.search(r"^W4\s*=", tier_source, flags=re.MULTILINE) or '"W4"' in tier_source:
        raise CompletionError("merge evidence Tier W4 exists")
    expected_kinds = {
        "behavior-preserving-refactor",
        "bug-fix",
        "new-feature",
        "regression-contract",
        "public-api",
        "module-ownership",
        "persistence",
        "core-domain-model",
    }
    declared_kinds = set(re.findall(r'= "([a-z-]+)"', authority_source)) & expected_kinds
    if declared_kinds != expected_kinds:
        raise CompletionError("merge authority ChangeKind domain is not exact")
    if "TIERS = (W0, W1, W2, W3)" not in tier_source:
        raise CompletionError("merge evidence Tier domain is not exactly W0-W3")
    conflict = WritePlan.parse(
        {
            "version": 1,
            "tasks": [
                {"id": "a", "writes": ["Modules/Playback/**"]},
                {"id": "b", "writes": ["Modules/Playback/PlaybackRuntime.swift"]},
            ],
        }
    )
    if not conflict.conflicts():
        raise CompletionError("write-set guard accepted an unordered conflict")
    safe = WritePlan.parse(
        {
            "version": 1,
            "tasks": [
                {"id": "a", "writes": ["Modules/Playback/**"]},
                {"id": "b", "writes": ["Modules/MediaLibrary/**"]},
            ],
        }
    )
    if safe.conflicts():
        raise CompletionError("write-set guard rejected disjoint writers")
    configuration = context.configuration()
    receipt = _merge_receipt_value(context)
    if receipt["schema"] != "enchron.merge-run-receipt/v1":
        raise CompletionError("merge RunReceipt schema identity is unsupported")
    authority = _object(receipt["authority"], ("decision", "status", "approval"), "merge RunReceipt.authority")
    if authority["decision"] != "HumanReviewRequired" or authority["status"] != "approved" or authority["approval"] is None:
        raise CompletionError("refactor merge RunReceipt lacks explicit content-bound authority")
    kinds = receipt["changeKinds"]
    required = {"behavior-preserving-refactor", "regression-contract", "module-ownership"}
    if not isinstance(kinds, list) or not required <= set(kinds):
        raise CompletionError("refactor merge RunReceipt omits required semantic ChangeKinds")
    head = _command(("git", "rev-parse", "--verify", "HEAD^{commit}"), repository, "current revision").strip()
    receipt_range = _receipt_range(receipt["range"], "merge RunReceipt.range")
    if receipt_range["headCommit"] != head:
        raise CompletionError("merge RunReceipt range does not end at the current revision")
    _validate_actual_write_set(context.audit().write_set, receipt)
    _command(
        (
            sys.executable,
            str(authority_path),
            "verify",
            "--repository",
            str(repository),
            "--receipt",
            str(configuration.merge_receipt_path),
        ),
        repository,
        "merge RunReceipt guard",
    )
    return "W0-W3 and eight ChangeKinds remain orthogonal; current authority and the source-bound actual write-set population revalidate with negative conflict proof"


def _target_topology(context: _CompletionContext) -> str:
    repository = context.paths.repository_root
    package_source = _regular_source(repository / "Package.swift", "root Package.swift")
    target_blocks = _swiftpm_target_blocks(package_source)
    if set(target_blocks) != set(EXPECTED_BUSINESS_DEPENDENCIES):
        raise CompletionError(f"root package business targets differ: {sorted(target_blocks)}")
    business_names = set(EXPECTED_BUSINESS_DEPENDENCIES)
    for target, expected in EXPECTED_BUSINESS_DEPENDENCIES.items():
        dependencies = frozenset(re.findall(r'"([A-Za-z][A-Za-z0-9]*)"', target_blocks[target])) & business_names
        if dependencies != expected:
            raise CompletionError(f"SwiftPM dependency direction differs for {target}: {sorted(dependencies)}")
    expected_files = {
        "PlaybackMediaSessionDriver": repository / "Modules/Playback/Session/PlaybackMediaSessionDriver.swift",
        "RendererTransferCoordinator": repository / "Modules/Playback/Session/RendererTransferCoordinator.swift",
        "MediaFormatInterpreter": repository / "Modules/Playback/Domain/MediaFormatInterpreter.swift",
        "PlaybackRuntimeControlling": repository / "Modules/Playback/Domain/PlaybackRuntimeControlling.swift",
        "FilesScreen": repository / "Modules/MediaLibrary/Views/FilesScreen.swift",
    }
    superseded_paths = (
        repository / "Modules/Playback/PlaybackMediaSessionDriver.swift",
        repository / "Modules/Playback/RendererTransferCoordinator.swift",
        repository / "Modules/Playback/MediaFormatInterpreter.swift",
        repository / "Modules/Playback/PlaybackRuntimeControlling.swift",
    )
    if any(path.exists() or path.is_symlink() for path in superseded_paths):
        raise CompletionError("Playback retains a compatibility path outside the target topology")
    sources = {name: _regular_source(path, name) for name, path in expected_files.items()}
    runtime = _regular_source(repository / "Modules/Playback/PlaybackRuntime.swift", "PlaybackRuntime facade")
    playback_sources = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((repository / "Modules/Playback").rglob("*.swift"))
    )
    declarations = {
        "PlaybackMediaSessionDriver": r"\b(?:final\s+)?class\s+PlaybackMediaSessionDriver\b",
        "RendererTransferCoordinator": r"\b(?:final\s+)?class\s+RendererTransferCoordinator\b",
        "MediaFormatInterpreter": r"\benum\s+MediaFormatInterpreter\b",
        "PlaybackRuntimeControlling": r"\bprotocol\s+PlaybackRuntimeControlling\b",
    }
    for name, pattern in declarations.items():
        if len(re.findall(pattern, playback_sources)) != 1:
            raise CompletionError(f"Playback must declare {name} exactly once")
    if re.search(
        r"@Observable\s+public\s+final\s+class\s+PlaybackRuntime\s*:\s*PlaybackRuntimeControlling",
        runtime,
    ) is None:
        raise CompletionError("PlaybackRuntime does not expose the reduced real facade protocol")
    for collaborator in ("PlaybackMediaSessionDriver", "RendererTransferCoordinator", "MediaFormatInterpreter"):
        if collaborator not in runtime:
            raise CompletionError(f"PlaybackRuntime facade does not delegate to {collaborator}")
    pure = sources["MediaFormatInterpreter"]
    if "@MainActor" in pure or re.search(r"^import\s+(SwiftUI|RealityKit|AVFoundation)\b", pure, flags=re.MULTILINE):
        raise CompletionError("MediaFormatInterpreter is not a pure domain component")
    if re.search(r"\bstruct\s+FilesScreen\b", sources["FilesScreen"]) is None:
        raise CompletionError("MediaLibrary does not own the FilesScreen declaration")
    app_sources = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((repository / "Apps/Enchron").rglob("*.swift"))
    )
    if re.search(r"\bstruct\s+FilesScreen\b", app_sources):
        raise CompletionError("App still owns a FilesScreen declaration")
    for path in sorted((repository / "Modules/MediaLibrary").rglob("*.swift")):
        if re.search(r"^\s*import\s+Playback\b", path.read_text(encoding="utf-8"), flags=re.MULTILINE):
            raise CompletionError(f"MediaLibrary imports Playback: {path.relative_to(repository)}")
    launch = _regular_source(
        repository / "Modules/Playback/PlaybackLaunchCoordinator.swift",
        "PlaybackLaunchCoordinator",
    )
    if "any PlaybackRuntimeControlling" not in launch:
        raise CompletionError("Playback callers do not consume the reduced facade protocol")
    context.audit()
    return "five SwiftPM targets retain their dependency direction; Playback delegates through the extracted session, transfer, format, and protocol owners; FilesScreen belongs to MediaLibrary"


def _retired_surfaces(context: _CompletionContext) -> str:
    repository = context.paths.repository_root
    _current_file(repository / "Config/retired_documents.json", "retired document registry")
    present = [relative for relative in RETIRED_PATHS if (repository / relative).exists() or (repository / relative).is_symlink()]
    if present:
        raise CompletionError("retired legacy path(s) remain: " + ", ".join(present))
    references: list[str] = []
    needles = (
        "Scripts/verification/regression_journeys.py",
        "regression_journeys.py",
        ".agents/skills/vp-e2e/references/journeys",
        "Scripts/verification/journey_units.py",
        "journey_units.py",
        "Config/journey_operation_coverage.json",
        "journey_operation_coverage.json",
        ".claude/hooks/regression_journey_stop_gate.py",
        "regression_journey_stop_gate.py",
        "Apps/Enchron/Screens/FilesScreen.swift",
    )
    for path in _active_text_files(repository):
        relative = path.relative_to(repository).as_posix()
        if relative in REFERENCE_EXCLUSIONS:
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if any(needle in source for needle in needles):
            references.append(relative)
    if references:
        raise CompletionError("active source/docs still reference retired legacy surfaces: " + ", ".join(sorted(references)))
    registry = _load_json(repository / "Config/retired_documents.json", "retired document registry")
    retired = registry.get("retired") if isinstance(registry, dict) else None
    if not isinstance(retired, list) or not any(
        isinstance(item, dict)
        and str(item.get("path", "")).rstrip("/")
        == ".agents/skills/vp-e2e/references/journeys"
        for item in retired
    ):
        raise CompletionError("generated journey references are absent but not recorded in retired_documents.json")
    return "journey generator/references/coverage registry/Stop hook and old App Files screen are absent from active paths and references"


def _comment_boundary(context: _CompletionContext) -> str:
    repository = context.paths.repository_root
    guard = _current_file(repository / "Scripts/rules/verify_product_source_comments.py", "product comment guard")
    _command((sys.executable, str(guard)), repository, "product source comment guard")
    context.audit()
    return "the active product-source comment guard passes current source and its full-run invocation is source-bound"


def _deterministic_checks(context: _CompletionContext) -> str:
    audit = context.audit()
    if audit.verification_summary.get("repository") != str(context.paths.repository_root):
        raise CompletionError("pre-freeze verification summary names a different repository")
    context.configuration()
    return "pre-freeze deterministic verification is full, passed, contains every required layer and guard log, and has no failed or skipped layer"


def _validate_frozen_build_identity(identity: BuildIdentity) -> None:
    if not isinstance(identity, BuildIdentity):
        raise CompletionError("frozen execution input has no BuildIdentity")
    artifacts = tuple(identity.lane_artifacts)
    if tuple(item.lane for item in artifacts) != FINAL_BUILD_LANES:
        raise CompletionError(
            "frozen BuildIdentity must contain exactly one simulator and one device artifact"
        )
    for artifact in artifacts:
        for field, label in (
            ("xctestrun_digest", ".xctestrun"),
            ("test_products_digest", "test-product closure"),
            ("application_code_digest", "application code"),
        ):
            if not SHA256.fullmatch(str(getattr(artifact, field))):
                raise CompletionError(
                    f"{artifact.lane.value} {label} digest is not a SHA-256 identity"
                )
    for field, label in (
        ("xctestrun_digest", ".xctestrun"),
        ("test_products_digest", "test-product closure"),
        ("application_code_digest", "application code"),
    ):
        if len({getattr(item, field) for item in artifacts}) != 2:
            raise CompletionError(
                f"simulator and device {label} digests must remain distinct"
            )


def _assert_same_build_identity(
    actual: BuildIdentity, expected: BuildIdentity, location: str
) -> None:
    if not isinstance(actual, BuildIdentity):
        raise CompletionError(f"{location} has no BuildIdentity")
    if actual == expected:
        return
    comparisons = (
        ("source_tree_digest", "source tree"),
        ("configuration_digest", "configuration"),
        ("toolchain", "toolchain"),
        ("lane_artifacts", "lane artifacts"),
    )
    for field, label in comparisons:
        if getattr(actual, field) != getattr(expected, field):
            raise CompletionError(
                f"{location} {label} differ from the frozen BuildIdentity"
            )
    raise CompletionError(f"{location} differs from the frozen BuildIdentity")


def _validate_main_gate_launch_provenance(
    execution: Any,
    plan: Any,
    view: Any,
    execution_input_path: Path,
) -> None:
    artifacts = {item.lane: item for item in execution.build_identity.lane_artifacts}
    for gate in plan.main_gates:
        accepted = tuple(
            lease
            for lease in view.leases
            if lease.node_id == gate.node_id
            and lease.envelope_status == "accepted"
            and lease.evidence
        )
        if len(accepted) != 1:
            raise CompletionError(
                f"{gate.lane.value} MainGate must have one accepted evidence lease"
            )
        invocations = tuple(
            invocation
            for invocation in accepted[0].invocations
            if str(invocation.operation) == "operation:harness.ensure-session@1"
            and invocation.completed
            and invocation.succeeded is True
            and invocation.outputs is not None
        )
        if len(invocations) != 1:
            raise CompletionError(
                f"{gate.lane.value} MainGate must retain one successful frozen runner launch"
            )
        output = invocations[0].outputs.payload()
        session = output.get("session")
        provenance = (
            session.get("launchProvenance")
            if isinstance(session, Mapping)
            else None
        )
        if not isinstance(provenance, Mapping):
            raise CompletionError(
                f"{gate.lane.value} MainGate launch provenance is absent"
            )
        target_id = execution.lane_targets[gate.lane]
        launch = load_frozen_test_launch(
            execution_input_path,
            gate.lane,
            target_id,
        )
        artifact = artifacts[gate.lane]
        if launch.lane != gate.lane or launch.target_id != target_id:
            raise CompletionError(
                f"{gate.lane.value} frozen launch resolved to a different lane target"
            )
        if launch.lane_artifact != artifact:
            raise CompletionError(
                f"{gate.lane.value} frozen launch uses different lane artifacts"
            )
        expected = {
            "executionInputPath": str(execution_input_path),
            "lane": gate.lane.value,
            "targetId": target_id,
            "xctestrunPath": str(launch.xctestrun_path),
            "destinationSpecifier": launch.destination_specifier,
            "xctestrunDigest": str(artifact.xctestrun_digest),
            "testProductsDigest": str(artifact.test_products_digest),
            "applicationCodeDigest": str(artifact.application_code_digest),
        }
        for field, value in expected.items():
            if provenance.get(field) != value:
                raise CompletionError(
                    f"{gate.lane.value} MainGate launch {field} differs from the frozen execution input"
                )
        if (
            type(provenance.get("processId")) is not int
            or provenance["processId"] <= 0
        ):
            raise CompletionError(
                f"{gate.lane.value} MainGate launch has no successful process identity"
            )


def _product_builds(context: _CompletionContext) -> str:
    configuration = context.configuration()
    if set(configuration.build_results) != {"simulator", "device"}:
        raise CompletionError("configuration build results do not cover both product destinations")
    execution = context.execution()
    identity = execution.build_identity
    _validate_frozen_build_identity(identity)
    artifacts = {item.lane: item for item in identity.lane_artifacts}
    launches = {item.lane: item for item in execution.launches}
    for lane in FINAL_BUILD_LANES:
        proof = configuration.build_results[lane.value]
        launch = launches.get(lane)
        if launch is None:
            raise CompletionError(f"{lane.value} frozen launch is absent")
        if proof.source_digest != str(identity.source_tree_digest):
            raise CompletionError(f"{lane.value} build result binds a different source tree")
        if proof.toolchain != identity.toolchain:
            raise CompletionError(f"{lane.value} build result binds a different toolchain")
        if proof.destination != launch.destination_specifier:
            raise CompletionError(f"{lane.value} build destination differs from the frozen launch")
        if proof.xctestrun_path != launch.xctestrun_path:
            raise CompletionError(f"{lane.value} build result binds a different .xctestrun")
        if proof.lane_artifact != artifacts[lane]:
            raise CompletionError(f"{lane.value} build result binds different lane artifacts")
    return "typed Xcode build results bind each exact command, destination, developer directory, toolchain, .xctestrun, test-product closure, and application-code identity"


def _runtime_lanes(context: _CompletionContext) -> str:
    proof = context.run()
    plan = context.plan().plan
    summary = proof.summary
    view = proof.view
    if summary["executionErrors"] != []:
        raise CompletionError("FullRun contains execution errors")
    completed = _object(summary["completedByLane"], ("simulator", "device"), "FullRun completedByLane")
    if any(type(completed[lane]) is not int or completed[lane] <= 0 for lane in ("simulator", "device")):
        raise CompletionError("both runtime lanes must complete positive work")
    if view.outcome is not RunOutcome.PASSED:
        raise CompletionError("FullRun outcome is not passed")
    if {item.lane for item in view.lanes} != {BoundLane.SIMULATOR, BoundLane.DEVICE}:
        raise CompletionError("ledger replay does not contain both lanes")
    if any(item.interrupted or item.active_lease_id is not None for item in view.lanes):
        raise CompletionError("a runtime lane is interrupted or retains an active lease")
    if {str(item.node_id) for item in view.nodes} != {str(item.id) for item in plan.nodes}:
        raise CompletionError("ledger node population differs from the current plan")
    if any(item.status is not NodeStatus.PASSED for item in view.nodes):
        raise CompletionError("not every current plan node reached Passed")
    by_id = {item.node_id: item for item in view.nodes}
    if {item.lane for item in plan.main_gates} != {BoundLane.SIMULATOR, BoundLane.DEVICE}:
        raise CompletionError("current plan does not contain both MainGates")
    if any(by_id[item.node_id].status is not NodeStatus.PASSED for item in plan.main_gates):
        raise CompletionError("both MainGates did not reach Passed")
    return f"both lanes completed work; all {len(plan.nodes)} plan nodes and both MainGates replay as Passed"


def _immutable_run(context: _CompletionContext) -> str:
    proof = context.plan()
    run = context.run()
    identity = proof.execution.build_identity
    _validate_frozen_build_identity(identity)
    if str(identity.source_tree_digest) != context.source_digest():
        raise CompletionError("frozen BuildIdentity source digest differs from current source")
    _assert_same_build_identity(
        proof.plan.build_identity,
        identity,
        "compiled plan",
    )
    if proof.plan.evidence_environment_identity != proof.execution.evidence_environment_identity:
        raise CompletionError("compiled plan does not retain the frozen evidence environment")
    by_id = {item.id: item for item in proof.plan.nodes}
    gate_ids = {item.node_id for item in proof.plan.main_gates}
    for gate in proof.plan.main_gates:
        node = by_id.get(gate.node_id)
        if node is None or not hasattr(node, "build_identity"):
            raise CompletionError(
                f"{gate.lane.value} MainGate does not identify a Scenario evidence node"
            )
        _assert_same_build_identity(
            node.build_identity,
            identity,
            f"{gate.lane.value} MainGate evidence",
        )
    evidence_nodes = tuple(
        item
        for item in proof.plan.nodes
        if hasattr(item, "build_identity") and item.id not in gate_ids
    )
    if not evidence_nodes:
        raise CompletionError("FullRun plan contains no non-MainGate evidence nodes")
    for node in evidence_nodes:
        _assert_same_build_identity(
            node.build_identity,
            identity,
            f"FullRun evidence node {node.id}",
        )
    if run.summary["buildIdentityDigest"] != str(identity.digest):
        raise CompletionError(
            "FullRun summary differs from the frozen BuildIdentity"
        )
    _validate_main_gate_launch_provenance(
        proof.execution,
        proof.plan,
        run.view,
        context.paths.execution_input_path,
    )
    return "schema-v2 execution input revalidates the current source, toolchain, .xctestrun files, product closures, and application code; MainGate and FullRun evidence retain that exact two-lane BuildIdentity"


def _is_product_swift_path(path: str) -> bool:
    if not path.endswith(".swift"):
        return False
    parts = PurePosixPath(path).parts
    if not parts:
        return False
    if parts[0] in ("Apps", "Modules"):
        return True
    return parts[0] == "Packages" and "Sources" in parts[1:]


def _validate_product_swift_population(
    coverage: ProductSwiftCoverageProof,
    merge_receipt: Mapping[str, Any],
) -> None:
    merge_range = _receipt_range(
        merge_receipt["range"], "merge RunReceipt.range"
    )
    if dict(coverage.range) != dict(merge_range):
        raise CompletionError(
            "product Swift coverage binds a different commit range"
        )
    expected = tuple(
        path
        for path in _classification_paths(merge_receipt)
        if _is_product_swift_path(path)
    )
    actual = tuple(item.path for item in coverage.files)
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise CompletionError(
            "product Swift coverage differs from the exact merge diff: "
            f"missing={missing}, extra={extra}"
        )


def _validate_product_runtime_observations(
    coverage: ProductSwiftCoverageProof,
    view: Any,
) -> None:
    passed_nodes = {
        str(node.node_id)
        for node in view.nodes
        if node.status is NodeStatus.PASSED
    }
    accepted_evidence = {
        (str(lease.node_id), str(artifact.digest))
        for lease in view.leases
        if lease.envelope_status == "accepted"
        for artifact in lease.evidence
    }
    for entry in coverage.files:
        observation = entry.runtime_observation
        if observation.node_id not in passed_nodes:
            raise CompletionError(
                f"{entry.path} runtime observation node is not Passed"
            )
        if (observation.node_id, observation.evidence_digest) not in accepted_evidence:
            raise CompletionError(
                f"{entry.path} runtime observation is absent from accepted FullRun evidence"
            )


def _no_unverified_diff(context: _CompletionContext) -> str:
    audit = context.audit()
    configuration = context.configuration()
    run = context.run()
    if audit.verification_record != configuration.verification_record:
        raise CompletionError("audit and configuration receipts bind different deterministic verification")
    if set(audit.evidence_paths) != set(AUDIT_EVIDENCE_NAMES):
        raise CompletionError("final audit evidence population is incomplete")
    merge_receipt = _merge_receipt_value(context)
    coverage = audit.product_swift_coverage
    _validate_product_swift_population(coverage, merge_receipt)
    _validate_product_runtime_observations(coverage, run.view)
    fresh_source_digest = str(repository_source_digest(context.paths.repository_root))
    if fresh_source_digest != context.source_digest():
        raise CompletionError("repository source changed during completion verification")
    fresh_audit = validate_audit_manifest(
        context.paths.audit_manifest_path,
        context.paths.final_root,
        fresh_source_digest,
    )
    if fresh_audit != audit:
        raise CompletionError("final audit artifacts changed during completion verification")
    catalog = context.catalog()
    fresh_configuration = validate_configuration_receipt(
        context.paths.configuration_receipt_path,
        context.paths.final_root,
        expected_source_digest=fresh_source_digest,
        expected_blueprint_digest=catalog.blueprint_digest,
        expected_catalog_digest=catalog.catalog_digest,
        expected_review_digest=context.reviews().digest,
        expected_semantic_authority_digest=context.semantic().digest,
        expected_verification_record=fresh_audit.verification_record,
        expected_developer_directory=_text(
            fresh_audit.verification_summary["developerDirectory"],
            "pre-freeze verification developerDirectory",
        ),
    )
    if fresh_configuration != configuration:
        raise CompletionError(
            "configuration build artifacts changed during completion verification"
        )
    plan_proof = context.plan()
    execution = plan_proof.execution
    execution_path, frozen_execution_source = _read_boundary_path(
        context.paths.execution_input_path,
        context.paths.final_root,
        "frozen execution input",
        "final artifact root",
    )
    reloaded_execution = load_execution_input(execution_path)
    if reloaded_execution != execution:
        raise CompletionError("execution input changed during completion verification")
    revalidated_execution_path, revalidated_execution_source = _read_boundary_path(
        context.paths.execution_input_path,
        context.paths.final_root,
        "frozen execution input",
        "final artifact root",
    )
    if (
        revalidated_execution_path != execution_path
        or revalidated_execution_source != frozen_execution_source
    ):
        raise CompletionError(
            "execution input bytes changed during completion verification"
        )
    _, receipt_source = _read_boundary_path(
        configuration.receipt_path,
        context.paths.final_root,
        "configuration receipt",
        "final artifact root",
    )
    if str(digest_bytes(receipt_source)) != str(
        execution.configuration_receipt_digest
    ):
        raise CompletionError("configuration receipt changed during completion verification")
    _, recorded_plan = _read_boundary_path(
        context.paths.compiled_plan_path,
        context.paths.final_root,
        "recorded compiled plan",
        "final artifact root",
    )
    if recorded_plan != compiled_plan_bytes(plan_proof.plan) + b"\n":
        raise CompletionError("compiled plan changed during completion verification")
    full_run_root = _full_run_root(context.paths.full_run_directory)
    fresh_summary = _load_full_run_json(
        full_run_root,
        "summary.json",
        "FullRun summary",
        canonical=True,
    )
    if fresh_summary != run.summary:
        raise CompletionError("FullRun summary changed during completion verification")
    fresh_view = replay(full_run_root)
    if _view_payload(fresh_view) != run.summary["run"]:
        raise CompletionError("FullRun ledger changed during completion verification")
    _validate_accepted_artifacts(full_run_root, fresh_view)
    return f"all {len(coverage.files)} product Swift diff files bind a focused passing log and accepted FullRun evidence; typed audits and every verification log remain source-bound"


def _walk_json(value: object) -> Sequence[str]:
    found: list[str] = []
    if isinstance(value, str):
        found.append(value)
    elif isinstance(value, list):
        for item in value:
            found.extend(_walk_json(item))
    elif isinstance(value, dict):
        for item in value.values():
            found.extend(_walk_json(item))
    return found


def _contains_two_of_three(value: object) -> bool:
    if isinstance(value, dict):
        candidate = value.get("atLeast")
        if (
            isinstance(candidate, dict)
            and candidate.get("count") == 2
            and isinstance(candidate.get("of"), list)
            and len(candidate["of"]) == 3
        ):
            return True
        return any(_contains_two_of_three(item) for item in value.values())
    if isinstance(value, list):
        return any(_contains_two_of_three(item) for item in value)
    return False


def _swiftpm_target_blocks(source: str) -> dict[str, str]:
    marker = re.compile(r"\.target\(\s*name:\s*\"([A-Za-z][A-Za-z0-9]*)\"")
    blocks: dict[str, str] = {}
    for match in marker.finditer(source):
        depth = 1
        cursor = match.end()
        while cursor < len(source) and depth:
            if source[cursor] == "(":
                depth += 1
            elif source[cursor] == ")":
                depth -= 1
            cursor += 1
        if depth:
            raise CompletionError(f"unterminated SwiftPM target declaration for {match.group(1)}")
        blocks[match.group(1)] = source[match.end() : cursor - 1]
    return blocks


def _active_text_files(repository: Path) -> Sequence[Path]:
    paths: set[Path] = set()
    for relative in ACTIVE_REFERENCE_ROOTS:
        root = repository / relative
        if not root.exists() or root.is_symlink():
            continue
        for path in root.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            relative_path = path.relative_to(repository)
            if "__pycache__" in relative_path.parts:
                continue
            if relative_path.parts[:2] == ("docs", "archive"):
                continue
            if path.suffix.lower() not in ACTIVE_TEXT_SUFFIXES:
                continue
            if path.stat().st_size > 5_000_000:
                continue
            paths.add(path)
    for relative in ("AGENTS.md", "ARCHITECTURE.md", "Package.swift"):
        path = repository / relative
        if path.is_file() and not path.is_symlink():
            paths.add(path)
    return tuple(sorted(paths))


def _detail(error: Exception) -> str:
    value = " ".join(str(error).split())
    value = value or type(error).__name__
    limit = 800
    return value if len(value) <= limit else value[:limit] + " [truncated]"


def verify_completion(paths: CompletionPaths) -> CompletionReport:
    context = _CompletionContext(paths)
    checks: tuple[Callable[[_CompletionContext], str], ...] = (
        _catalog_shape,
        _no_legacy_contracts,
        _semantic_authority_predicate,
        _executable_closure,
        _review_receipts,
        _governance,
        _target_topology,
        _retired_surfaces,
        _comment_boundary,
        _deterministic_checks,
        _product_builds,
        _runtime_lanes,
        _immutable_run,
        _no_unverified_diff,
    )
    results: list[PredicateResult] = []
    for name, check in zip(PREDICATE_NAMES, checks, strict=True):
        try:
            results.append(PredicateResult(name, True, check(context)))
        except Exception as error:
            results.append(PredicateResult(name, False, _detail(error)))
    return CompletionReport(tuple(results))


__all__ = (
    "AuditProof",
    "BuildResultProof",
    "CompletionError",
    "CompletionPaths",
    "CompletionReport",
    "ConfigurationProof",
    "PREDICATE_NAMES",
    "PredicateResult",
    "ProductSwiftCoverageProof",
    "WriteSetProof",
    "artifact_record",
    "validate_audit_manifest",
    "validate_configuration_receipt",
    "verification_log_records",
    "verify_completion",
)
