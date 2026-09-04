#!/usr/bin/env python3

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass, field
import errno
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import stat
import struct
import subprocess
from tempfile import TemporaryDirectory
from types import MappingProxyType
from typing import Any, Callable, Iterable, Iterator, Mapping, Sequence

from regression.core.contracts import BoundLane
from regression.core.digest import canonical_bytes, canonical_digest, digest_bytes
from regression.core.errors import RegressionError
from regression.core.ids import Digest, parse_identifier
from regression.core.plan import (
    BuildIdentity,
    EvidenceEnvironmentIdentity,
    LaneBuildArtifact,
    ToolchainIdentity,
)
from regression.agent_identity import agent_environment


INPUT_SCHEMA = "enchron.regression.execution-input"
INPUT_SCHEMA_VERSION = 2
LINK_PROVENANCE_SCHEMA = "enchron.regression.link-provenance"
LINK_PROVENANCE_SCHEMA_VERSION = 1
CONFIGURATION_RECEIPT_NAME = "configuration-receipt.json"
UI_TEST_TARGET = "EnchronAppUITests"
UI_TEST_IDENTIFIER = "InteractiveDeviceUITests/testInteractiveDeviceSession()"
RUNTIME_SOURCE_ROOTS = ("Scripts/regression", "Scripts/verification")
VISIONOS_SIMULATOR_RUNTIME_PREFIXES = (
    "com.apple.CoreSimulator.SimRuntime.visionOS-",
    "com.apple.CoreSimulator.SimRuntime.xrOS-",
)
_LANES = (BoundLane.SIMULATOR, BoundLane.DEVICE)
_MACHO_MAGIC_64_LE = 0xFEEDFACF
_CPU_TYPE_ARM64 = 0x0100000C
_MH_DYLIB = 0x6
_LC_SEGMENT_64 = 0x19
_LC_BUILD_VERSION = 0x32
_MACHO_PLATFORM = {BoundLane.DEVICE: 11, BoundLane.SIMULATOR: 12}
_MACRO = re.compile(r"__[A-Z][A-Z0-9_]*__")
_OPEN_BASE = os.O_RDONLY | getattr(os, "O_CLOEXEC", 0)
_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)
_DIRECTORY = getattr(os, "O_DIRECTORY", 0)


class ExecutionIdentityError(ValueError):
    pass


SimulatorUDIDSource = Callable[[], frozenset[str]]


@dataclass(frozen=True)
class PhysicalVisionOSDevice:
    hardware_udid: str
    coredevice_identifier: str

    def __post_init__(self) -> None:
        if not isinstance(self.hardware_udid, str) or not self.hardware_udid.strip():
            raise ExecutionIdentityError("physical device hardware UDID must be non-empty")
        if not isinstance(self.coredevice_identifier, str) or not self.coredevice_identifier.strip():
            raise ExecutionIdentityError("physical device CoreDevice identifier must be non-empty")


@dataclass(frozen=True)
class PhysicalVisionOSDeviceRegistry(Mapping[str, PhysicalVisionOSDevice]):
    devices: tuple[PhysicalVisionOSDevice, ...]
    _by_identifier: Mapping[str, PhysicalVisionOSDevice] = field(
        init=False, repr=False, compare=False
    )

    def __post_init__(self) -> None:
        devices = tuple(self.devices)
        by_identifier: dict[str, PhysicalVisionOSDevice] = {}
        for device in devices:
            if not isinstance(device, PhysicalVisionOSDevice):
                raise ExecutionIdentityError("physical device registry entries must be device records")
            for identifier in (device.hardware_udid, device.coredevice_identifier):
                existing = by_identifier.get(identifier)
                if existing is not None and existing != device:
                    raise ExecutionIdentityError(
                        "physical device registry maps one identifier to multiple devices"
                    )
                by_identifier[identifier] = existing or device
        object.__setattr__(self, "devices", devices)
        object.__setattr__(self, "_by_identifier", MappingProxyType(by_identifier))

    def __getitem__(self, identifier: str) -> PhysicalVisionOSDevice:
        return self._by_identifier[identifier]

    def __iter__(self) -> Iterator[str]:
        return iter(self._by_identifier)

    def __len__(self) -> int:
        return len(self._by_identifier)


PhysicalVisionOSDeviceRegistrySource = Callable[[], PhysicalVisionOSDeviceRegistry]


@dataclass(frozen=True)
class LinkProvenance:
    git_revision: str
    source_tree_digest: Digest
    toolchain: ToolchainIdentity

    def __post_init__(self) -> None:
        if not isinstance(self.git_revision, str) or not self.git_revision.strip():
            raise ExecutionIdentityError("link provenance git revision must be non-empty")
        object.__setattr__(
            self,
            "source_tree_digest",
            _digest(self.source_tree_digest, "link provenance sourceTreeDigest"),
        )
        if not isinstance(self.toolchain, ToolchainIdentity):
            raise ExecutionIdentityError(
                "link provenance must bind a ToolchainIdentity"
            )


@dataclass(frozen=True)
class PreparedLaneProvenance:
    lane: BoundLane
    path: Path
    digest: Digest
    identity: LinkProvenance
    xcode_build_setting: str

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise ExecutionIdentityError("prepared provenance lane must be concrete")
        path = _absolute_lexical(self.path, "prepared provenance path")
        object.__setattr__(self, "path", path)
        object.__setattr__(
            self,
            "digest",
            _digest(self.digest, "prepared provenance digest"),
        )
        if not isinstance(self.identity, LinkProvenance):
            raise ExecutionIdentityError(
                "prepared provenance must bind LinkProvenance"
            )
        if self.xcode_build_setting != _xcode_build_setting(path):
            raise ExecutionIdentityError(
                "prepared provenance has an invalid Xcode build setting"
            )


@dataclass(frozen=True)
class FrozenTestLaunch:
    lane: BoundLane
    target_id: str
    xctestrun_path: Path
    destination_specifier: str
    lane_artifact: LaneBuildArtifact

    def __post_init__(self) -> None:
        if not isinstance(self.lane, BoundLane):
            raise ExecutionIdentityError("frozen test launch lane must be concrete")
        if not isinstance(self.target_id, str) or not self.target_id.strip():
            raise ExecutionIdentityError("frozen test launch target ID must be non-empty")
        if not isinstance(self.lane_artifact, LaneBuildArtifact):
            raise ExecutionIdentityError("frozen test launch must bind a LaneBuildArtifact")
        if self.lane_artifact.lane is not self.lane:
            raise ExecutionIdentityError("frozen test launch artifact lane does not match its launch lane")
        expected = _destination_specifier(self.lane, self.target_id)
        if self.destination_specifier != expected:
            raise ExecutionIdentityError(
                "frozen test launch destination is not derived from its lane target"
            )
        object.__setattr__(
            self,
            "xctestrun_path",
            _absolute_lexical(self.xctestrun_path, "frozen .xctestrun path"),
        )


@dataclass(frozen=True)
class FrozenExecutionInput:
    repository_root: Path
    artifact_root: Path
    build_identity: BuildIdentity
    evidence_environment_identity: EvidenceEnvironmentIdentity
    launches: tuple[FrozenTestLaunch, ...]
    configuration_receipt: Path
    configuration_receipt_digest: Digest
    agent_model: str
    agent_executable: str
    bootstrap: bool = False

    def __post_init__(self) -> None:
        repository = _absolute_lexical(self.repository_root, "repository root")
        artifact = _absolute_lexical(self.artifact_root, "artifact root")
        _relative_path(repository, artifact, "artifact root")
        launches = tuple(sorted(self.launches, key=lambda item: _lane_key(item.lane)))
        if tuple(item.lane for item in launches) != _LANES:
            raise ExecutionIdentityError(
                "frozen execution input must bind simulator and device launches exactly"
            )
        artifacts = {item.lane: item for item in self.build_identity.lane_artifacts}
        if any(launch.lane_artifact != artifacts[launch.lane] for launch in launches):
            raise ExecutionIdentityError("frozen launches do not bind the BuildIdentity lane artifacts")
        configuration = _absolute_lexical(self.configuration_receipt, "configuration receipt")
        if configuration != artifact / CONFIGURATION_RECEIPT_NAME:
            raise ExecutionIdentityError("configuration receipt must use the fixed artifact-root path")
        if not isinstance(self.agent_model, str) or not self.agent_model.strip():
            raise ExecutionIdentityError("agent model must be non-empty")
        if not isinstance(self.agent_executable, str) or not self.agent_executable.strip():
            raise ExecutionIdentityError("agent executable must be non-empty")
        if type(self.bootstrap) is not bool:
            raise ExecutionIdentityError("bootstrap flag must be a boolean")
        object.__setattr__(self, "repository_root", repository)
        object.__setattr__(self, "artifact_root", artifact)
        object.__setattr__(self, "launches", launches)
        object.__setattr__(self, "configuration_receipt", configuration)

    @property
    def lane_targets(self) -> Mapping[BoundLane, str]:
        return MappingProxyType({launch.lane: launch.target_id for launch in self.launches})

    @property
    def xctestrun_paths(self) -> Mapping[BoundLane, Path]:
        return MappingProxyType({launch.lane: launch.xctestrun_path for launch in self.launches})


@dataclass(frozen=True)
class _EmbeddedProvenance:
    lane: BoundLane
    git_revision: str
    source_tree_digest: Digest
    toolchain: ToolchainIdentity


@dataclass(frozen=True)
class _ParsedMachO:
    platform: int
    sdk_version: tuple[int, int, int]
    provenance: _EmbeddedProvenance


@dataclass(frozen=True)
class _ParsedXCTestRun:
    test_bundle: Path
    test_host: Path
    ui_target_app: Path
    dependent_products: tuple[Path, ...]

    @property
    def product_roots(self) -> tuple[Path, ...]:
        return (
            self.ui_target_app,
            self.test_host,
            self.test_bundle,
            *self.dependent_products,
        )


@dataclass(frozen=True)
class _BoundLaneState:
    lane: BoundLane
    xctestrun_path: Path
    artifact: LaneBuildArtifact
    bundle_identifier: str


def _lane_key(lane: BoundLane) -> int:
    return 0 if lane is BoundLane.SIMULATOR else 1


def _absolute_lexical(path: Path, label: str) -> Path:
    try:
        text = os.fspath(path)
    except TypeError as error:
        raise ExecutionIdentityError(f"{label} must be a filesystem path") from error
    if not text:
        raise ExecutionIdentityError(f"{label} must be non-empty")
    return Path(os.path.abspath(text))


def _canonical_absolute_path(value: object, location: str) -> Path:
    text = _text(value, location)
    candidate = Path(text)
    if not candidate.is_absolute() or ".." in candidate.parts:
        raise ExecutionIdentityError(f"{location} must be a canonical absolute path")
    normalized = _absolute_lexical(candidate, location)
    if str(normalized) != text:
        raise ExecutionIdentityError(f"{location} must be a canonical absolute path")
    return normalized


def _relative_path(root: Path, path: Path, label: str) -> Path:
    root = _absolute_lexical(root, f"{label} root")
    path = _absolute_lexical(path, label)
    try:
        relative = path.relative_to(root)
    except ValueError as error:
        raise ExecutionIdentityError(f"{label} escapes its required root") from error
    if ".." in relative.parts:
        raise ExecutionIdentityError(f"{label} escapes its required root")
    return relative


def _validated_relative(value: Path | str, label: str) -> Path:
    path = Path(value)
    if path.is_absolute() or not path.parts or path == Path("."):
        raise ExecutionIdentityError(f"{label} must be a non-empty relative path")
    if any(part in ("", ".", "..") for part in path.parts):
        raise ExecutionIdentityError(f"{label} contains a path escape")
    return path


def _metadata_key(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _open_directory_absolute(path: Path, label: str) -> int:
    if not _NOFOLLOW:
        raise ExecutionIdentityError("this platform does not provide O_NOFOLLOW")
    absolute = _absolute_lexical(path, label)
    descriptor = os.open("/", _OPEN_BASE | _DIRECTORY)
    try:
        for component in absolute.parts[1:]:
            child = os.open(
                component,
                _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                dir_fd=descriptor,
            )
            os.close(descriptor)
            descriptor = child
        metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(metadata.st_mode):
            raise ExecutionIdentityError(f"{label} must be a real directory")
        return descriptor
    except OSError as error:
        os.close(descriptor)
        raise ExecutionIdentityError(
            f"{label} contains a symlink, is missing, or is not a directory"
        ) from error
    except BaseException:
        os.close(descriptor)
        raise


@contextmanager
def _directory_descriptor(path: Path, label: str) -> Iterator[int]:
    descriptor = _open_directory_absolute(path, label)
    identity = os.fstat(descriptor)
    try:
        yield descriptor
        verification = _open_directory_absolute(path, label)
        try:
            current = os.fstat(verification)
            if (identity.st_dev, identity.st_ino) != (current.st_dev, current.st_ino):
                raise ExecutionIdentityError(f"{label} path changed while it was open")
        finally:
            os.close(verification)
    finally:
        os.close(descriptor)


def _open_relative_directory(root_descriptor: int, relative: Path | str, label: str) -> int:
    path = Path(relative)
    if path == Path("."):
        return os.dup(root_descriptor)
    path = _validated_relative(path, label)
    descriptor = os.dup(root_descriptor)
    try:
        for component in path.parts:
            child = os.open(
                component,
                _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                dir_fd=descriptor,
            )
            os.close(descriptor)
            descriptor = child
        return descriptor
    except OSError as error:
        os.close(descriptor)
        raise ExecutionIdentityError(
            f"{label} contains a symlink, is missing, or is not a directory"
        ) from error


def _open_relative_entry(root_descriptor: int, relative: Path | str, label: str) -> int:
    path = _validated_relative(relative, label)
    parent = os.dup(root_descriptor)
    try:
        for component in path.parts[:-1]:
            child = os.open(
                component,
                _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                dir_fd=parent,
            )
            os.close(parent)
            parent = child
        return os.open(path.name, _OPEN_BASE | _NOFOLLOW, dir_fd=parent)
    except OSError as error:
        raise ExecutionIdentityError(
            f"{label} contains a symlink, is missing, or cannot be opened"
        ) from error
    finally:
        os.close(parent)


def _open_relative_parent(
    root_descriptor: int, relative: Path | str, label: str
) -> tuple[int, str]:
    path = _validated_relative(relative, label)
    parent = os.dup(root_descriptor)
    try:
        for component in path.parts[:-1]:
            child = os.open(
                component,
                _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                dir_fd=parent,
            )
            os.close(parent)
            parent = child
        return parent, path.name
    except OSError as error:
        os.close(parent)
        raise ExecutionIdentityError(
            f"{label} contains a symlink, is missing, or cannot be opened"
        ) from error


def _stable_regular_bytes(descriptor: int, label: str) -> tuple[bytes, os.stat_result]:
    before = os.fstat(descriptor)
    if not stat.S_ISREG(before.st_mode):
        raise ExecutionIdentityError(f"{label} must be a regular file")
    os.lseek(descriptor, 0, os.SEEK_SET)
    chunks: list[bytes] = []
    while True:
        chunk = os.read(descriptor, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
    source = b"".join(chunks)
    after = os.fstat(descriptor)
    if _metadata_key(before) != _metadata_key(after) or len(source) != after.st_size:
        raise ExecutionIdentityError(f"{label} changed while it was read")
    return source, after


def _read_regular_at(
    root_descriptor: int, relative: Path | str, label: str
) -> tuple[bytes, os.stat_result]:
    path = _validated_relative(relative, label)
    parent, name = _open_relative_parent(root_descriptor, path, label)
    descriptor = -1
    try:
        before = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode):
            raise ExecutionIdentityError(f"{label} must be a regular file without symlinks")
        descriptor = os.open(name, _OPEN_BASE | _NOFOLLOW, dir_fd=parent)
        opened = os.fstat(descriptor)
        if _metadata_key(before) != _metadata_key(opened):
            raise ExecutionIdentityError(f"{label} changed before it was read")
        source, stable = _stable_regular_bytes(descriptor, label)
        current = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if _metadata_key(stable) != _metadata_key(current):
            raise ExecutionIdentityError(f"{label} changed after it was read")
    except OSError as error:
        raise ExecutionIdentityError(
            f"{label} contains a symlink, is missing, or changed while it was read"
        ) from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        os.close(parent)
    verification = _open_relative_entry(root_descriptor, path, label)
    try:
        if _metadata_key(stable) != _metadata_key(os.fstat(verification)):
            raise ExecutionIdentityError(f"{label} path changed after it was read")
    finally:
        os.close(verification)
    return source, stable


def _read_absolute_regular(path: Path, label: str) -> bytes:
    absolute = _absolute_lexical(path, label)
    if absolute == Path("/"):
        raise ExecutionIdentityError(f"{label} must be a regular file")
    with _directory_descriptor(absolute.parent, f"{label} parent") as parent_descriptor:
        source, _ = _read_regular_at(parent_descriptor, Path(absolute.name), label)
    return source


def _create_descendant_directory(repository: Path, relative: Path, label: str) -> None:
    relative = _validated_relative(relative, label)
    with _directory_descriptor(repository, "repository root") as repository_descriptor:
        descriptor = os.dup(repository_descriptor)
        try:
            for component in relative.parts:
                try:
                    child = os.open(
                        component,
                        _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                        dir_fd=descriptor,
                    )
                except OSError as error:
                    if error.errno != errno.ENOENT:
                        raise ExecutionIdentityError(
                            f"{label} contains a symlink or non-directory component"
                        ) from error
                    os.mkdir(component, mode=0o755, dir_fd=descriptor)
                    child = os.open(
                        component,
                        _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                        dir_fd=descriptor,
                    )
                os.close(descriptor)
                descriptor = child
        finally:
            os.close(descriptor)


def _atomic_replace_regular_at(
    parent_descriptor: int, name: str, source: bytes, label: str
) -> None:
    try:
        existing = os.stat(name, dir_fd=parent_descriptor, follow_symlinks=False)
    except FileNotFoundError:
        existing = None
    if existing is not None and not stat.S_ISREG(existing.st_mode):
        raise ExecutionIdentityError(f"{label} destination must be a regular file")
    temporary = f".{name}.{secrets.token_hex(8)}.tmp"
    descriptor = -1
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | _NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
            0o644,
            dir_fd=parent_descriptor,
        )
        view = memoryview(source)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.replace(
            temporary,
            name,
            src_dir_fd=parent_descriptor,
            dst_dir_fd=parent_descriptor,
        )
        os.fsync(parent_descriptor)
    except OSError as error:
        raise ExecutionIdentityError(f"cannot write {label}") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary, dir_fd=parent_descriptor)
        except FileNotFoundError:
            pass


def _write_once_regular_at(parent_descriptor: int, name: str, source: bytes, label: str) -> None:
    descriptor = -1
    try:
        descriptor = os.open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | _NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
            0o644,
            dir_fd=parent_descriptor,
        )
        view = memoryview(source)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = -1
        os.fsync(parent_descriptor)
    except FileExistsError as error:
        raise ExecutionIdentityError("execution input already exists") from error
    except OSError as error:
        try:
            os.unlink(name, dir_fd=parent_descriptor)
        except FileNotFoundError:
            pass
        raise ExecutionIdentityError(f"cannot write {label}") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _run_git(repository: Path, *arguments: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(repository), *arguments], capture_output=True, check=False
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ExecutionIdentityError(detail or f"git {' '.join(arguments)} failed")
    return completed.stdout


def _snapshot_record_at(repository_descriptor: int, relative: str) -> Mapping[str, Any]:
    path = _validated_relative(relative, "source tree entry")
    parent, name = _open_relative_parent(
        repository_descriptor, path, f"source tree entry {relative}"
    )
    try:
        before = os.stat(name, dir_fd=parent, follow_symlinks=False)
        if stat.S_ISLNK(before.st_mode):
            content = os.fsencode(os.readlink(name, dir_fd=parent))
            after = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if _metadata_key(before) != _metadata_key(after):
                raise ExecutionIdentityError(f"source tree entry changed during freeze: {relative}")
            verification_parent, verification_name = _open_relative_parent(
                repository_descriptor, path, f"source tree entry {relative}"
            )
            try:
                verification = os.stat(
                    verification_name,
                    dir_fd=verification_parent,
                    follow_symlinks=False,
                )
                verification_content = os.fsencode(
                    os.readlink(verification_name, dir_fd=verification_parent)
                )
            finally:
                os.close(verification_parent)
            if (
                _metadata_key(after) != _metadata_key(verification)
                or content != verification_content
            ):
                raise ExecutionIdentityError(
                    f"source tree entry path changed during freeze: {relative}"
                )
            kind = "symlink"
        elif stat.S_ISREG(before.st_mode):
            content, after = _read_regular_at(
                repository_descriptor, path, f"source tree entry {relative}"
            )
            if _metadata_key(before) != _metadata_key(after):
                raise ExecutionIdentityError(
                    f"source tree entry changed during freeze: {relative}"
                )
            kind = "file"
        else:
            raise ExecutionIdentityError(
                f"source tree entry is not a regular file or symlink: {relative}"
            )
    except FileNotFoundError as error:
        raise ExecutionIdentityError(
            f"source tree entry disappeared during freeze: {relative}"
        ) from error
    except OSError as error:
        raise ExecutionIdentityError(
            f"source tree entry changed during freeze: {relative}"
        ) from error
    finally:
        os.close(parent)
    return {
        "path": relative,
        "kind": kind,
        "mode": stat.S_IMODE(after.st_mode),
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def repository_source_digest(repository_root: Path) -> Digest:
    repository = _absolute_lexical(repository_root, "repository root")
    with _directory_descriptor(repository, "repository root") as descriptor:
        source = _run_git(
            repository,
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        )
        try:
            paths = tuple(
                sorted(item.decode("utf-8") for item in source.split(b"\0") if item)
            )
        except UnicodeDecodeError as error:
            raise ExecutionIdentityError("source tree paths must be UTF-8") from error
        if not paths:
            raise ExecutionIdentityError("source tree snapshot is empty")
        records = [_snapshot_record_at(descriptor, relative) for relative in paths]
    return canonical_digest(records)


def deterministic_runtime_digest(repository_root: Path) -> Digest:
    repository = _absolute_lexical(repository_root, "repository root")
    candidates: set[str] = set()
    for relative_root in RUNTIME_SOURCE_ROOTS:
        root = repository / relative_root
        if not root.is_dir() or root.is_symlink():
            continue
        for path in root.rglob("*.py"):
            if "__pycache__" not in path.parts:
                candidates.add(path.relative_to(repository).as_posix())
    if not candidates:
        raise ExecutionIdentityError("deterministic runtime source set is empty")
    records = []
    with _directory_descriptor(repository, "repository root") as descriptor:
        for relative in sorted(candidates):
            record = _snapshot_record_at(descriptor, relative)
            if record["kind"] == "file":
                records.append(record)
    if not records:
        raise ExecutionIdentityError("deterministic runtime source set is empty")
    return canonical_digest(records)


def _clean(repository: Path) -> bool:
    return not bool(_run_git(repository, "status", "--porcelain", "--untracked-files=normal"))


def _revision(repository: Path) -> str:
    return _run_git(repository, "rev-parse", "--verify", "HEAD^{commit}").decode("ascii").strip()


def _require_ignored_artifact_root(repository: Path, artifact_root: Path) -> None:
    relative = _relative_path(repository, artifact_root, "artifact root")
    if relative == Path("."):
        raise ExecutionIdentityError("artifact root must not be the repository root")
    completed = subprocess.run(
        [
            "git",
            "-C",
            str(repository),
            "check-ignore",
            "-q",
            "--",
            (relative / ".enchron-ignore-probe").as_posix(),
        ],
        capture_output=True,
        check=False,
    )
    if completed.returncode == 1:
        raise ExecutionIdentityError(
            "artifact root must be excluded from the repository source snapshot"
        )
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise ExecutionIdentityError(detail or "cannot verify that artifact root is ignored")


def _validated_roots(
    repository_root: Path, artifact_root: Path, *, create_artifact: bool
) -> tuple[Path, Path]:
    repository = _absolute_lexical(repository_root, "repository root")
    artifact = _absolute_lexical(artifact_root, "artifact root")
    relative = _relative_path(repository, artifact, "artifact root")
    with _directory_descriptor(repository, "repository root"):
        pass
    _require_ignored_artifact_root(repository, artifact)
    if create_artifact:
        _create_descendant_directory(repository, relative, "artifact root")
    with _directory_descriptor(artifact, "artifact root"):
        pass
    return repository, artifact


def _run_text(command: Sequence[str], label: str) -> str:
    try:
        completed = subprocess.run(
            list(command), capture_output=True, check=False, text=True, timeout=30
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ExecutionIdentityError(f"cannot query {label}: {error}") from error
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout).strip()
        raise ExecutionIdentityError(detail or f"cannot query {label}")
    value = completed.stdout.strip()
    if not value:
        raise ExecutionIdentityError(f"{label} query returned no value")
    return value


def query_toolchain_identity() -> ToolchainIdentity:
    xcode_lines = _run_text(("xcodebuild", "-version"), "Xcode version").splitlines()
    if (
        len(xcode_lines) != 2
        or not xcode_lines[0].startswith("Xcode ")
        or not xcode_lines[1].startswith("Build version ")
    ):
        raise ExecutionIdentityError("xcodebuild returned an unsupported version record")

    def sdk_value(sdk: str, option: str, label: str) -> str:
        return _run_text(("xcrun", "--sdk", sdk, option), label)

    return ToolchainIdentity(
        xcode_lines[0].removeprefix("Xcode ").strip(),
        xcode_lines[1].removeprefix("Build version ").strip(),
        sdk_value("xros", "--show-sdk-version", "visionOS SDK version"),
        sdk_value("xros", "--show-sdk-build-version", "visionOS SDK build"),
        sdk_value("xrsimulator", "--show-sdk-version", "visionOS Simulator SDK version"),
        sdk_value("xrsimulator", "--show-sdk-build-version", "visionOS Simulator SDK build"),
    )


def _toolchain_payload(toolchain: ToolchainIdentity) -> Mapping[str, str]:
    return {
        "xcodeVersion": toolchain.xcode_version,
        "xcodeBuild": toolchain.xcode_build,
        "visionOSSDKVersion": toolchain.visionos_sdk_version,
        "visionOSSDKBuild": toolchain.visionos_sdk_build,
        "visionOSSimulatorSDKVersion": toolchain.visionos_simulator_sdk_version,
        "visionOSSimulatorSDKBuild": toolchain.visionos_simulator_sdk_build,
    }


def _xcode_build_setting(path: Path) -> str:
    absolute = _absolute_lexical(path, "link provenance stamp path")
    text = str(absolute)
    if "," in text or any(character.isspace() for character in text):
        raise ExecutionIdentityError(
            "link provenance stamp path cannot contain comma or whitespace"
        )
    return (
        "ENCHRON_REGRESSION_LINK_PROVENANCE_FLAG="
        f"-Wl,-sectcreate,__TEXT,__enchsrc,{text}"
    )


def _build_provenance_payload(
    lane: BoundLane,
    git_revision: str,
    source_tree_digest: Digest,
    toolchain: ToolchainIdentity,
) -> Mapping[str, Any]:
    return {
        "schema": LINK_PROVENANCE_SCHEMA,
        "schemaVersion": LINK_PROVENANCE_SCHEMA_VERSION,
        "lane": lane.value,
        "gitRevision": git_revision,
        "sourceTreeDigest": str(source_tree_digest),
        "toolchain": _toolchain_payload(toolchain),
    }


def _build_provenance_bytes(
    lane: BoundLane,
    git_revision: str,
    source_tree_digest: Digest,
    toolchain: ToolchainIdentity,
) -> bytes:
    return canonical_bytes(
        _build_provenance_payload(lane, git_revision, source_tree_digest, toolchain)
    ) + b"\n"


def prepare_build_provenance(
    repo_root: Path, artifact_root: Path
) -> tuple[PreparedLaneProvenance, ...]:
    repository, artifact = _validated_roots(repo_root, artifact_root, create_artifact=True)
    if not _clean(repository):
        raise ExecutionIdentityError("build provenance requires a clean integrated worktree")
    revision = _revision(repository)
    source_digest = repository_source_digest(repository)
    toolchain = query_toolchain_identity()
    link_identity = LinkProvenance(revision, source_digest, toolchain)
    provenance_relative = Path("build-provenance")
    lane_paths = {
        lane: artifact / provenance_relative / f"{lane.value}.json"
        for lane in _LANES
    }
    build_settings = {
        lane: _xcode_build_setting(lane_paths[lane]) for lane in _LANES
    }
    artifact_relative = _relative_path(repository, artifact, "artifact root")
    _create_descendant_directory(
        repository,
        artifact_relative / provenance_relative,
        "build provenance directory",
    )
    prepared = []
    with _directory_descriptor(artifact, "artifact root") as artifact_descriptor:
        provenance_descriptor = _open_relative_directory(
            artifact_descriptor, provenance_relative, "build provenance directory"
        )
        try:
            for lane in _LANES:
                source = _build_provenance_bytes(lane, revision, source_digest, toolchain)
                name = f"{lane.value}.json"
                _atomic_replace_regular_at(
                    provenance_descriptor,
                    name,
                    source,
                    f"{lane.value} build provenance",
                )
                current, _ = _read_regular_at(
                    provenance_descriptor,
                    Path(name),
                    f"{lane.value} build provenance",
                )
                if current != source:
                    raise ExecutionIdentityError(
                        f"{lane.value} build provenance changed after writing"
                    )
                prepared.append(
                    PreparedLaneProvenance(
                        lane,
                        lane_paths[lane],
                        digest_bytes(source),
                        link_identity,
                        build_settings[lane],
                    )
                )
        finally:
            os.close(provenance_descriptor)
    return tuple(prepared)


def _lane_map(values: Mapping[BoundLane, Any], label: str) -> dict[BoundLane, Any]:
    result = dict(values)
    if set(result) != set(_LANES):
        raise ExecutionIdentityError(f"{label} must cover simulator and device exactly")
    return result


def registered_simulator_udids() -> frozenset[str]:
    try:
        listing = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "--json"],
            check=False,
            text=True,
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ExecutionIdentityError(
            f"cannot read the current simctl device registry: {error}"
        ) from error
    if listing.returncode != 0:
        detail = (listing.stderr or listing.stdout).strip()
        raise ExecutionIdentityError(detail or "cannot read the current simctl device registry")
    try:
        document = json.loads(listing.stdout)
    except json.JSONDecodeError as error:
        raise ExecutionIdentityError("simctl returned an invalid device registry document") from error
    if not isinstance(document, dict) or not isinstance(document.get("devices"), dict):
        raise ExecutionIdentityError("simctl returned an invalid device registry document")
    udids: set[str] = set()
    for runtime_identifier, entries in document["devices"].items():
        if not isinstance(runtime_identifier, str):
            raise ExecutionIdentityError("simctl returned an invalid device registry document")
        if not runtime_identifier.startswith(VISIONOS_SIMULATOR_RUNTIME_PREFIXES):
            continue
        if not isinstance(entries, list):
            raise ExecutionIdentityError("simctl returned an invalid device registry document")
        for entry in entries:
            if not isinstance(entry, dict):
                raise ExecutionIdentityError("simctl returned an invalid device registry document")
            udid = entry.get("udid")
            if not isinstance(udid, str) or not udid.strip():
                raise ExecutionIdentityError("simctl returned an invalid device registry document")
            udids.add(udid)
    return frozenset(udids)


def registered_physical_visionos_devices() -> PhysicalVisionOSDeviceRegistry:
    with TemporaryDirectory(prefix="enchron-coredevice-registry-") as temporary:
        output_path = Path(temporary).resolve() / "devices.json"
        try:
            listing = subprocess.run(
                [
                    "xcrun",
                    "devicectl",
                    "list",
                    "devices",
                    "--json-output",
                    str(output_path),
                ],
                check=False,
                text=True,
                capture_output=True,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ExecutionIdentityError(
                f"cannot read the current CoreDevice registry: {error}"
            ) from error
        if listing.returncode != 0:
            detail = (listing.stderr or listing.stdout).strip()
            raise ExecutionIdentityError(detail or "cannot read the current CoreDevice registry")
        try:
            source = _read_absolute_regular(output_path, "CoreDevice registry document")
            document = json.loads(source.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ExecutionIdentityError(
                "devicectl returned an invalid device registry document"
            ) from error

    if not isinstance(document, dict):
        raise ExecutionIdentityError("devicectl returned an invalid device registry document")
    result = document.get("result")
    if not isinstance(result, dict) or not isinstance(result.get("devices"), list):
        raise ExecutionIdentityError("devicectl returned an invalid device registry document")
    devices: list[PhysicalVisionOSDevice] = []
    for entry in result["devices"]:
        if not isinstance(entry, dict):
            raise ExecutionIdentityError("devicectl returned an invalid device registry document")
        properties = entry.get("properties")
        if not isinstance(properties, dict):
            raise ExecutionIdentityError("devicectl returned an invalid device registry document")
        hardware = properties.get("hardware")
        connection = properties.get("connection")
        if not isinstance(hardware, dict) or not isinstance(connection, dict):
            raise ExecutionIdentityError("devicectl returned an invalid device registry document")
        if (
            hardware.get("platform") != "visionOS"
            or hardware.get("reality") != "physical"
            or connection.get("pairingState") != "paired"
        ):
            continue
        hardware_udid = hardware.get("udid")
        identifier = entry.get("identifier")
        if not isinstance(hardware_udid, str) or not hardware_udid.strip():
            raise ExecutionIdentityError(
                "a paired physical visionOS device has no hardware UDID"
            )
        if not isinstance(identifier, str) or not identifier.strip():
            raise ExecutionIdentityError(
                "a paired physical visionOS device has no CoreDevice identifier"
            )
        devices.append(PhysicalVisionOSDevice(hardware_udid, identifier))
    return PhysicalVisionOSDeviceRegistry(tuple(devices))


def _validated_lane_targets(
    values: Mapping[BoundLane, Any],
    label: str,
    simulator_udid_source: SimulatorUDIDSource | None = None,
    physical_visionos_device_registry_source: PhysicalVisionOSDeviceRegistrySource | None = None,
) -> dict[BoundLane, str]:
    targets = _lane_map(values, label)
    if any(not isinstance(value, str) or not value.strip() for value in targets.values()):
        raise ExecutionIdentityError(f"{label} must be non-empty text")
    simulator = targets[BoundLane.SIMULATOR]
    device = targets[BoundLane.DEVICE]
    if simulator == device:
        raise ExecutionIdentityError(f"{label} must be distinct")
    registered = (simulator_udid_source or registered_simulator_udids)()
    if not isinstance(registered, frozenset) or any(not isinstance(item, str) for item in registered):
        raise ExecutionIdentityError("simulator registry source returned the wrong value")
    if simulator not in registered:
        raise ExecutionIdentityError(
            "simulator lane target must be a currently registered simctl UDID"
        )
    if device in registered:
        raise ExecutionIdentityError(
            "device lane target must not be a registered simulator UDID"
        )
    physical = (
        physical_visionos_device_registry_source or registered_physical_visionos_devices
    )()
    if not isinstance(physical, PhysicalVisionOSDeviceRegistry):
        raise ExecutionIdentityError("physical device registry source returned the wrong value")
    if device not in physical:
        raise ExecutionIdentityError(
            "device lane target must be a paired physical visionOS device ID"
        )
    hardware_udid = physical[device].hardware_udid
    if hardware_udid == simulator or hardware_udid in registered:
        raise ExecutionIdentityError(
            "device lane target resolves to a registered simulator UDID"
        )
    targets[BoundLane.DEVICE] = hardware_udid
    return targets


def _destination_specifier(lane: BoundLane, target_id: str) -> str:
    platform = "visionOS Simulator" if lane is BoundLane.SIMULATOR else "visionOS"
    return f"platform={platform},id={target_id}"


def _directory_stable(before: os.stat_result, descriptor: int, label: str) -> None:
    if _metadata_key(before) != _metadata_key(os.fstat(descriptor)):
        raise ExecutionIdentityError(f"{label} changed while it was enumerated")


def _discover_xctestruns(
    directory_descriptor: int, relative: Path = Path(".")
) -> list[Path]:
    before = os.fstat(directory_descriptor)
    try:
        entries = sorted(os.scandir(directory_descriptor), key=lambda item: item.name)
    except OSError as error:
        raise ExecutionIdentityError("cannot enumerate Xcode Products") from error
    found: list[Path] = []
    for entry in entries:
        child_relative = Path(entry.name) if relative == Path(".") else relative / entry.name
        metadata = entry.stat(follow_symlinks=False)
        if stat.S_ISLNK(metadata.st_mode):
            if entry.name.endswith(".xctestrun"):
                raise ExecutionIdentityError(".xctestrun must not be a symlink")
            continue
        if stat.S_ISDIR(metadata.st_mode):
            try:
                child = os.open(
                    entry.name,
                    _OPEN_BASE | _DIRECTORY | _NOFOLLOW,
                    dir_fd=directory_descriptor,
                )
            except OSError as error:
                raise ExecutionIdentityError(
                    "Xcode Products changed during .xctestrun discovery"
                ) from error
            try:
                found.extend(_discover_xctestruns(child, child_relative))
            finally:
                os.close(child)
        elif entry.name.endswith(".xctestrun"):
            if not stat.S_ISREG(metadata.st_mode):
                raise ExecutionIdentityError(".xctestrun must be a regular file")
            found.append(child_relative)
    _directory_stable(before, directory_descriptor, "Xcode Products")
    return found


def _macro_product_path(
    value: object,
    field: str,
    products_root: Path,
    replacements: Mapping[str, Path],
    allowed: frozenset[str],
) -> Path:
    text = _text(value, field)
    macros = set(_MACRO.findall(text))
    unknown = sorted(macros - allowed)
    if unknown:
        raise ExecutionIdentityError(
            f"{field} uses unsupported Xcode macro(s): {', '.join(unknown)}"
        )
    expanded = text
    for macro in sorted(macros):
        replacement = replacements.get(macro)
        if replacement is None:
            raise ExecutionIdentityError(f"{field} cannot resolve Xcode macro {macro}")
        expanded = expanded.replace(macro, str(replacement))
    if _MACRO.search(expanded) or "__" in expanded:
        raise ExecutionIdentityError(f"{field} contains an unresolved Xcode macro")
    path = Path(expanded)
    if not path.is_absolute() or ".." in path.parts:
        raise ExecutionIdentityError(
            f"{field} must resolve to a canonical absolute product path"
        )
    normalized = _absolute_lexical(path, field)
    relative = _relative_path(products_root, normalized, field)
    if relative == Path("."):
        raise ExecutionIdentityError(f"{field} must identify a product")
    return _validated_relative(relative, field)


def _plist_bool(value: Mapping[str, Any], key: str, location: str) -> bool:
    if key not in value:
        return True
    result = value[key]
    if type(result) is not bool:
        raise ExecutionIdentityError(f"{location}.{key} must be a boolean")
    return result


def _parse_xctestrun(source: bytes, products_root: Path) -> _ParsedXCTestRun:
    try:
        root = plistlib.loads(source)
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        raise ExecutionIdentityError(".xctestrun must be a valid property list") from error
    if not isinstance(root, dict):
        raise ExecutionIdentityError(".xctestrun must contain a property-list dictionary")
    metadata = root.get("__xctestrun_metadata__")
    if (
        not isinstance(metadata, dict)
        or type(metadata.get("FormatVersion")) is not int
        or metadata["FormatVersion"] != 2
    ):
        raise ExecutionIdentityError(".xctestrun must use Xcode format version 2")
    configurations = root.get("TestConfigurations")
    if not isinstance(configurations, list) or not configurations:
        raise ExecutionIdentityError(".xctestrun has no test configurations")
    names: set[str] = set()
    enabled_configurations: list[Mapping[str, Any]] = []
    for index, configuration in enumerate(configurations):
        location = f"TestConfigurations[{index}]"
        if not isinstance(configuration, dict):
            raise ExecutionIdentityError(f"{location} must be a dictionary")
        name = _text(configuration.get("Name"), f"{location}.Name")
        if name in names:
            raise ExecutionIdentityError(".xctestrun configuration names must be unique")
        names.add(name)
        targets = configuration.get("TestTargets")
        if not isinstance(targets, list):
            raise ExecutionIdentityError(f"{location}.TestTargets must be an array")
        if _plist_bool(configuration, "IsEnabled", location):
            enabled_configurations.append(configuration)
    if len(enabled_configurations) != 1:
        raise ExecutionIdentityError(".xctestrun must enable exactly one test configuration")
    targets = enabled_configurations[0]["TestTargets"]
    enabled_targets: list[Mapping[str, Any]] = []
    for index, target in enumerate(targets):
        location = f"enabled TestTargets[{index}]"
        if not isinstance(target, dict):
            raise ExecutionIdentityError(f"{location} must be a dictionary")
        if _plist_bool(target, "IsEnabled", location):
            enabled_targets.append(target)
    if len(enabled_targets) != 1:
        raise ExecutionIdentityError(".xctestrun must enable exactly one test target")
    target = enabled_targets[0]
    if target.get("BlueprintName") != UI_TEST_TARGET:
        raise ExecutionIdentityError(".xctestrun may only enable EnchronAppUITests")
    if target.get("OnlyTestIdentifiers") != [UI_TEST_IDENTIFIER]:
        raise ExecutionIdentityError(
            ".xctestrun must select only the interactive device session test"
        )
    skipped = target.get("SkipTestIdentifiers", [])
    if not isinstance(skipped, list) or any(not isinstance(item, str) for item in skipped):
        raise ExecutionIdentityError("SkipTestIdentifiers must be an array of strings")
    if UI_TEST_IDENTIFIER in skipped:
        raise ExecutionIdentityError(
            ".xctestrun skips the required interactive device session test"
        )
    if "UseDestinationArtifacts" in target:
        use_destination = target["UseDestinationArtifacts"]
        if type(use_destination) is not bool:
            raise ExecutionIdentityError("UseDestinationArtifacts must be a boolean")
        if use_destination:
            raise ExecutionIdentityError(".xctestrun must use the frozen local test products")
    replacements = {"__TESTROOT__": products_root}
    test_host = _macro_product_path(
        target.get("TestHostPath"),
        "TestHostPath",
        products_root,
        replacements,
        frozenset({"__TESTROOT__", "__PLATFORMS__"}),
    )
    replacements["__TESTHOST__"] = products_root / test_host
    test_bundle = _macro_product_path(
        target.get("TestBundlePath"),
        "TestBundlePath",
        products_root,
        replacements,
        frozenset({"__TESTROOT__", "__TESTHOST__"}),
    )
    ui_target = _macro_product_path(
        target.get("UITargetAppPath"),
        "UITargetAppPath",
        products_root,
        replacements,
        frozenset({"__TESTROOT__"}),
    )
    dependencies_value = target.get("DependentProductPaths")
    if not isinstance(dependencies_value, list) or not dependencies_value:
        raise ExecutionIdentityError("DependentProductPaths must be a non-empty array")
    dependencies = tuple(
        _macro_product_path(
            value,
            f"DependentProductPaths[{index}]",
            products_root,
            replacements,
            frozenset({"__TESTROOT__"}),
        )
        for index, value in enumerate(dependencies_value)
    )
    if ui_target.name != "Enchron.app":
        raise ExecutionIdentityError("UITargetAppPath must identify Enchron.app")
    if test_host.name != "EnchronAppUITests-Runner.app":
        raise ExecutionIdentityError(
            "TestHostPath must identify EnchronAppUITests-Runner.app"
        )
    if test_bundle.name != "EnchronAppUITests.xctest":
        raise ExecutionIdentityError("TestBundlePath must identify EnchronAppUITests.xctest")
    try:
        test_bundle.relative_to(test_host)
    except ValueError as error:
        raise ExecutionIdentityError("TestBundlePath must reside inside the UI test runner") from error
    return _ParsedXCTestRun(test_bundle, test_host, ui_target, dependencies)


def _file_record(relative: Path, source: bytes, metadata: os.stat_result) -> Mapping[str, Any]:
    return {
        "path": relative.as_posix(),
        "type": "regular",
        "mode": stat.S_IMODE(metadata.st_mode),
        "bytes": len(source),
        "sha256": hashlib.sha256(source).hexdigest(),
    }


def _collect_product_entry(
    root_descriptor: int,
    relative: Path,
    records: dict[str, Mapping[str, Any]],
    label: str,
) -> None:
    descriptor = _open_relative_entry(root_descriptor, relative, label)
    try:
        metadata = os.fstat(descriptor)
        if stat.S_ISREG(metadata.st_mode):
            source, stable = _stable_regular_bytes(descriptor, label)
            record = _file_record(relative, source, stable)
            existing = records.get(relative.as_posix())
            if existing is not None and existing != record:
                raise ExecutionIdentityError(
                    f"product changed while closure was deduplicated: {relative}"
                )
            records[relative.as_posix()] = record
            verification = _open_relative_entry(root_descriptor, relative, label)
            try:
                if _metadata_key(stable) != _metadata_key(os.fstat(verification)):
                    raise ExecutionIdentityError(
                        f"test product path changed while it was read: {relative}"
                    )
            finally:
                os.close(verification)
            return
        if not stat.S_ISDIR(metadata.st_mode):
            raise ExecutionIdentityError(
                f"test product closure contains a non-regular entry: {relative}"
            )
        _collect_product_directory(descriptor, relative, records)
        verification = _open_relative_entry(root_descriptor, relative, label)
        try:
            if _metadata_key(metadata) != _metadata_key(os.fstat(verification)):
                raise ExecutionIdentityError(
                    f"test product path changed while it was enumerated: {relative}"
                )
        finally:
            os.close(verification)
    finally:
        os.close(descriptor)


def _collect_product_directory(
    directory_descriptor: int,
    relative: Path,
    records: dict[str, Mapping[str, Any]],
) -> None:
    before = os.fstat(directory_descriptor)
    entries = sorted(os.scandir(directory_descriptor), key=lambda item: item.name)
    for entry in entries:
        child_relative = relative / entry.name
        metadata = entry.stat(follow_symlinks=False)
        if stat.S_ISLNK(metadata.st_mode):
            raise ExecutionIdentityError(
                f"test product closure contains a symlink: {child_relative}"
            )
        descriptor = -1
        try:
            descriptor = os.open(
                entry.name, _OPEN_BASE | _NOFOLLOW, dir_fd=directory_descriptor
            )
            current = os.fstat(descriptor)
            if stat.S_ISREG(current.st_mode):
                source, stable = _stable_regular_bytes(
                    descriptor, f"test product {child_relative}"
                )
                record = _file_record(child_relative, source, stable)
                existing = records.get(child_relative.as_posix())
                if existing is not None and existing != record:
                    raise ExecutionIdentityError(
                        f"product changed while closure was deduplicated: {child_relative}"
                    )
                records[child_relative.as_posix()] = record
            elif stat.S_ISDIR(current.st_mode):
                _collect_product_directory(descriptor, child_relative, records)
            else:
                raise ExecutionIdentityError(
                    f"test product closure contains a non-regular entry: {child_relative}"
                )
        except OSError as error:
            raise ExecutionIdentityError(
                f"test product changed or became a symlink: {child_relative}"
            ) from error
        finally:
            if descriptor >= 0:
                os.close(descriptor)
    _directory_stable(before, directory_descriptor, f"test product {relative}")


def _test_products_digest(products_descriptor: int, roots: Sequence[Path]) -> Digest:
    records: dict[str, Mapping[str, Any]] = {}
    for index, root in enumerate(roots):
        _collect_product_entry(
            products_descriptor,
            root,
            records,
            f"test product root[{index}] {root}",
        )
    if not records:
        raise ExecutionIdentityError("test product closure contains no regular files")
    return canonical_digest([records[path] for path in sorted(records)])


def _decode_plist(source: bytes, label: str) -> Mapping[str, Any]:
    try:
        value = plistlib.loads(source)
    except (plistlib.InvalidFileException, ValueError, TypeError) as error:
        raise ExecutionIdentityError(f"{label} must be a valid property list") from error
    if not isinstance(value, dict):
        raise ExecutionIdentityError(f"{label} must contain a dictionary")
    return value


def _application_code(
    products_descriptor: int, app_path: Path
) -> tuple[str, bytes, Path]:
    info_path = app_path / "Info.plist"
    info_source, _ = _read_regular_at(
        products_descriptor, info_path, "Enchron.app Info.plist"
    )
    info = _decode_plist(info_source, "Enchron.app Info.plist")
    bundle_identifier = _text(
        info.get("CFBundleIdentifier"), "Enchron.app CFBundleIdentifier"
    )
    executable = _text(info.get("CFBundleExecutable"), "Enchron.app CFBundleExecutable")
    if executable != "Enchron":
        raise ExecutionIdentityError("Enchron.app CFBundleExecutable must identify Enchron")
    code_path = app_path / f"{executable}.debug.dylib"
    code, _ = _read_regular_at(products_descriptor, code_path, "Enchron.debug.dylib")
    return bundle_identifier, code, code_path


def _fixed_macho_name(source: bytes, label: str) -> str:
    value, separator, padding = source.partition(b"\0")
    if separator and any(padding):
        raise ExecutionIdentityError(f"{label} has invalid Mach-O name padding")
    try:
        return value.decode("ascii")
    except UnicodeDecodeError as error:
        raise ExecutionIdentityError(f"{label} must be ASCII") from error


def _sdk_tuple(value: str, label: str) -> tuple[int, int, int]:
    parts = value.split(".")
    if not 1 <= len(parts) <= 3 or any(not item.isdigit() for item in parts):
        raise ExecutionIdentityError(f"{label} has an unsupported version")
    numbers = [int(item) for item in parts]
    numbers.extend([0] * (3 - len(numbers)))
    if numbers[0] > 0xFFFF or any(item > 0xFF for item in numbers[1:]):
        raise ExecutionIdentityError(f"{label} is outside Mach-O version bounds")
    return (numbers[0], numbers[1], numbers[2])


def _packed_sdk_tuple(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFFFF, (value >> 8) & 0xFF, value & 0xFF)


def _parse_macho(
    source: bytes, lane: BoundLane, expected_toolchain: ToolchainIdentity
) -> _ParsedMachO:
    if len(source) < 32:
        raise ExecutionIdentityError("Enchron.debug.dylib has a truncated Mach-O header")
    (
        magic,
        cpu_type,
        _cpu_subtype,
        file_type,
        command_count,
        command_bytes,
        _flags,
        _reserved,
    ) = struct.unpack_from("<8I", source, 0)
    if magic != _MACHO_MAGIC_64_LE:
        raise ExecutionIdentityError(
            "Enchron.debug.dylib must be thin little-endian 64-bit Mach-O"
        )
    if cpu_type != _CPU_TYPE_ARM64:
        raise ExecutionIdentityError("Enchron.debug.dylib must contain arm64 code")
    if file_type != _MH_DYLIB:
        raise ExecutionIdentityError("Enchron.debug.dylib must be an MH_DYLIB")
    if command_count == 0 or command_count > 65535:
        raise ExecutionIdentityError("Enchron.debug.dylib has invalid load commands")
    commands_end = 32 + command_bytes
    if command_bytes < command_count * 8 or commands_end > len(source):
        raise ExecutionIdentityError("Enchron.debug.dylib load commands are out of bounds")
    offset = 32
    build_versions: list[tuple[int, int, int]] = []
    provenance_ranges: list[tuple[int, int]] = []
    for _ in range(command_count):
        if offset + 8 > commands_end:
            raise ExecutionIdentityError("Enchron.debug.dylib has a truncated load command")
        command, command_size = struct.unpack_from("<II", source, offset)
        if command_size < 8 or command_size % 8 or offset + command_size > commands_end:
            raise ExecutionIdentityError("Enchron.debug.dylib has an invalid load command")
        if command == _LC_BUILD_VERSION:
            if command_size < 24:
                raise ExecutionIdentityError("LC_BUILD_VERSION is truncated")
            platform, minimum_os, sdk, tool_count = struct.unpack_from(
                "<4I", source, offset + 8
            )
            if command_size != 24 + tool_count * 8 or minimum_os == 0 or sdk == 0:
                raise ExecutionIdentityError("LC_BUILD_VERSION has an invalid shape")
            build_versions.append((platform, minimum_os, sdk))
        elif command == _LC_SEGMENT_64:
            if command_size < 72:
                raise ExecutionIdentityError("LC_SEGMENT_64 is truncated")
            segment_name = _fixed_macho_name(
                source[offset + 8 : offset + 24], "segment"
            )
            (
                _vm_address,
                _vm_size,
                file_offset,
                file_size,
                _maximum_protection,
                _initial_protection,
                section_count,
                _segment_flags,
            ) = struct.unpack_from("<QQQQiiII", source, offset + 24)
            if command_size != 72 + section_count * 80:
                raise ExecutionIdentityError("LC_SEGMENT_64 has an invalid section table")
            if file_offset > len(source) or file_size > len(source) - file_offset:
                raise ExecutionIdentityError("Mach-O segment file range is out of bounds")
            section_offset = offset + 72
            for _section_index in range(section_count):
                section_name = _fixed_macho_name(
                    source[section_offset : section_offset + 16], "section"
                )
                declared_segment = _fixed_macho_name(
                    source[section_offset + 16 : section_offset + 32], "section segment"
                )
                if declared_segment != segment_name:
                    raise ExecutionIdentityError(
                        "Mach-O section declares the wrong containing segment"
                    )
                _address, size, data_offset = struct.unpack_from(
                    "<QQI", source, section_offset + 32
                )
                if section_name == "__enchsrc":
                    if segment_name != "__TEXT":
                        raise ExecutionIdentityError(
                            "__enchsrc must reside in the __TEXT segment"
                        )
                    end = data_offset + size
                    segment_end = file_offset + file_size
                    if (
                        size == 0
                        or data_offset < file_offset
                        or end > segment_end
                        or end > len(source)
                    ):
                        raise ExecutionIdentityError("__TEXT,__enchsrc section is out of bounds")
                    provenance_ranges.append((data_offset, end))
                section_offset += 80
        offset += command_size
    if offset != commands_end:
        raise ExecutionIdentityError(
            "Enchron.debug.dylib load-command size does not match its header"
        )
    if len(build_versions) != 1:
        raise ExecutionIdentityError(
            "Enchron.debug.dylib must contain exactly one LC_BUILD_VERSION"
        )
    if len(provenance_ranges) != 1:
        raise ExecutionIdentityError(
            "Enchron.debug.dylib must contain exactly one __TEXT,__enchsrc section"
        )
    platform, _minimum_os, packed_sdk = build_versions[0]
    if platform != _MACHO_PLATFORM[lane]:
        raise ExecutionIdentityError(
            f"{lane.value} Enchron.debug.dylib has the wrong Mach-O platform"
        )
    sdk_text = (
        expected_toolchain.visionos_simulator_sdk_version
        if lane is BoundLane.SIMULATOR
        else expected_toolchain.visionos_sdk_version
    )
    expected_sdk = _sdk_tuple(sdk_text, f"{lane.value} SDK version")
    actual_sdk = _packed_sdk_tuple(packed_sdk)
    if actual_sdk != expected_sdk:
        raise ExecutionIdentityError(
            f"{lane.value} Enchron.debug.dylib SDK differs from the toolchain"
        )
    start, end = provenance_ranges[0]
    provenance = _parse_build_provenance(source[start:end])
    return _ParsedMachO(platform, actual_sdk, provenance)


def _parse_build_provenance(source: bytes) -> _EmbeddedProvenance:
    root = _object(
        _decode_canonical_json(source, "embedded build provenance"),
        ("schema", "schemaVersion", "lane", "gitRevision", "sourceTreeDigest", "toolchain"),
        "embedded build provenance",
    )
    if (
        root["schema"] != LINK_PROVENANCE_SCHEMA
        or type(root["schemaVersion"]) is not int
        or root["schemaVersion"] != LINK_PROVENANCE_SCHEMA_VERSION
    ):
        raise ExecutionIdentityError("embedded build provenance schema is unsupported")
    try:
        lane = BoundLane(root["lane"])
    except (TypeError, ValueError) as error:
        raise ExecutionIdentityError("embedded build provenance lane is invalid") from error
    return _EmbeddedProvenance(
        lane,
        _text(root["gitRevision"], "embedded build provenance.gitRevision"),
        _digest(root["sourceTreeDigest"], "embedded build provenance.sourceTreeDigest"),
        _parse_toolchain(root["toolchain"], "embedded build provenance.toolchain"),
    )


def _bind_lane(
    artifact_root: Path,
    artifact_descriptor: int,
    lane: BoundLane,
    revision: str,
    source_digest: Digest,
    toolchain: ToolchainIdentity,
) -> _BoundLaneState:
    products_relative = Path("lanes") / lane.value / "DerivedData" / "Build" / "Products"
    products_root = artifact_root / products_relative
    products_descriptor = _open_relative_directory(
        artifact_descriptor,
        products_relative,
        f"{lane.value} Xcode Products root",
    )
    try:
        candidates = _discover_xctestruns(products_descriptor)
        if len(candidates) != 1:
            raise ExecutionIdentityError(
                f"{lane.value} lane must contain exactly one Xcode-generated .xctestrun"
            )
        xctestrun_relative = candidates[0]
        xctestrun_source, _ = _read_regular_at(
            products_descriptor,
            xctestrun_relative,
            f"{lane.value} .xctestrun",
        )
        parsed = _parse_xctestrun(xctestrun_source, products_root)
        products_digest = _test_products_digest(products_descriptor, parsed.product_roots)
        bundle_identifier, code, _code_path = _application_code(
            products_descriptor, parsed.ui_target_app
        )
        macho = _parse_macho(code, lane, toolchain)
        expected_provenance = _EmbeddedProvenance(lane, revision, source_digest, toolchain)
        if macho.provenance != expected_provenance:
            raise ExecutionIdentityError(
                f"{lane.value} embedded build provenance is stale or cross-bound"
            )
        artifact = LaneBuildArtifact(
            lane,
            digest_bytes(xctestrun_source),
            products_digest,
            digest_bytes(code),
        )
        return _BoundLaneState(
            lane,
            products_root / xctestrun_relative,
            artifact,
            bundle_identifier,
        )
    finally:
        os.close(products_descriptor)


def _configuration_receipt(
    artifact_descriptor: int, expected_source_digest: Digest
) -> tuple[Digest, bytes]:
    source, _ = _read_regular_at(
        artifact_descriptor, Path(CONFIGURATION_RECEIPT_NAME), "configuration receipt"
    )
    root = _object(
        _decode_canonical_json(source, "configuration receipt"),
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
        root["schema"] != "enchron.regression.configuration-receipt"
        or type(root["schemaVersion"]) is not int
        or root["schemaVersion"] != 1
    ):
        raise ExecutionIdentityError("configuration receipt schema is unsupported")
    if _digest(root["sourceDigest"], "configuration receipt.sourceDigest") != expected_source_digest:
        raise ExecutionIdentityError("configuration receipt binds a different source tree")
    for field_name in (
        "blueprintDigest",
        "catalogDigest",
        "reviewCompletionDigest",
        "semanticAuthorityDigest",
    ):
        _digest(root[field_name], f"configuration receipt.{field_name}")
    return digest_bytes(source), source


def _assert_no_lane_collisions(artifacts: Sequence[LaneBuildArtifact]) -> None:
    by_lane = {item.lane: item for item in artifacts}
    simulator = by_lane[BoundLane.SIMULATOR]
    device = by_lane[BoundLane.DEVICE]
    for name, label in (
        ("xctestrun_digest", ".xctestrun"),
        ("test_products_digest", "test-product closure"),
        ("application_code_digest", "application code"),
    ):
        if getattr(simulator, name) == getattr(device, name):
            raise ExecutionIdentityError(
                f"simulator and device {label} digests must not collide"
            )


def _bootstrap_configuration_digest(source_digest: Digest) -> Digest:
    return digest_bytes(canonical_bytes({"bootstrap": str(source_digest)}) + b"\n")


def _freeze_current(
    repository: Path,
    artifact: Path,
    targets: Mapping[BoundLane, str],
    agent_model: str,
    agent_executable: str,
    bootstrap: bool = False,
) -> FrozenExecutionInput:
    if type(bootstrap) is not bool:
        raise ExecutionIdentityError("bootstrap flag must be a boolean")
    if not _clean(repository):
        raise ExecutionIdentityError("execution freeze requires a clean integrated worktree")
    revision = _revision(repository)
    source_digest = repository_source_digest(repository)
    toolchain = query_toolchain_identity()
    if bootstrap:
        configuration_digest = _bootstrap_configuration_digest(source_digest)
        with _directory_descriptor(artifact, "artifact root") as artifact_descriptor:
            states = tuple(
                _bind_lane(
                    artifact,
                    artifact_descriptor,
                    lane,
                    revision,
                    source_digest,
                    toolchain,
                )
                for lane in _LANES
            )
    else:
        with _directory_descriptor(artifact, "artifact root") as artifact_descriptor:
            configuration_digest, _ = _configuration_receipt(artifact_descriptor, source_digest)
            states = tuple(
                _bind_lane(
                    artifact,
                    artifact_descriptor,
                    lane,
                    revision,
                    source_digest,
                    toolchain,
                )
                for lane in _LANES
            )
    bundle_identifiers = {state.bundle_identifier for state in states}
    if len(bundle_identifiers) != 1:
        raise ExecutionIdentityError(
            "simulator and device Enchron apps have different bundle identifiers"
        )
    artifacts = tuple(state.artifact for state in states)
    _assert_no_lane_collisions(artifacts)
    build = BuildIdentity(
        next(iter(bundle_identifiers)),
        revision,
        source_digest,
        configuration_digest,
        toolchain,
        artifacts,
    )
    evidence = EvidenceEnvironmentIdentity(
        deterministic_runtime_digest(repository),
        agent_environment(agent_model, agent_executable),
    )
    launches = tuple(
        FrozenTestLaunch(
            state.lane,
            targets[state.lane],
            state.xctestrun_path,
            _destination_specifier(state.lane, targets[state.lane]),
            state.artifact,
        )
        for state in states
    )
    return FrozenExecutionInput(
        repository,
        artifact,
        build,
        evidence,
        launches,
        artifact / CONFIGURATION_RECEIPT_NAME,
        configuration_digest,
        agent_model,
        agent_executable,
        bootstrap,
    )


def freeze_execution_input(
    repo_root: Path,
    artifact_root: Path,
    lane_targets: Mapping[BoundLane, str],
    agent_model: str,
    agent_executable: str = "codex",
    bootstrap: bool = False,
) -> FrozenExecutionInput:
    repository, artifact = _validated_roots(repo_root, artifact_root, create_artifact=False)
    targets = _validated_lane_targets(lane_targets, "lane targets")
    if not isinstance(agent_model, str) or not agent_model.strip():
        raise ExecutionIdentityError("agent model must be non-empty")
    if not isinstance(agent_executable, str) or not agent_executable.strip():
        raise ExecutionIdentityError("agent executable must be non-empty")
    if type(bootstrap) is not bool:
        raise ExecutionIdentityError("bootstrap flag must be a boolean")
    return _freeze_current(repository, artifact, targets, agent_model, agent_executable, bootstrap)


def _stored_relative(root: Path, path: Path, label: str) -> str:
    return _relative_path(root, path, label).as_posix()


def execution_input_payload(value: FrozenExecutionInput) -> Mapping[str, Any]:
    build = value.build_identity
    agent = value.evidence_environment_identity.agent_environment
    if agent is None:
        raise ExecutionIdentityError("execution input requires an Agent environment")
    payload: dict[str, Any] = {
        "schema": INPUT_SCHEMA,
        "schemaVersion": INPUT_SCHEMA_VERSION,
        "repositoryRoot": str(value.repository_root),
        "artifactRoot": str(value.artifact_root),
        "buildIdentity": {
            "bundleIdentifier": build.bundle_identifier,
            "gitRevision": build.git_revision,
            "sourceTreeDigest": str(build.source_tree_digest),
            "configurationDigest": str(build.configuration_digest),
            "toolchain": _toolchain_payload(build.toolchain),
            "laneArtifacts": [
                {
                    "lane": artifact.lane.value,
                    "xctestrunDigest": str(artifact.xctestrun_digest),
                    "testProductsDigest": str(artifact.test_products_digest),
                    "applicationCodeDigest": str(artifact.application_code_digest),
                }
                for artifact in build.lane_artifacts
            ],
        },
        "evidenceEnvironmentIdentity": {
            "deterministicRuntimeDigest": str(
                value.evidence_environment_identity.deterministic_runtime_digest
            ),
            "agentEnvironment": {
                "model": agent.model,
                "promptDigest": str(agent.prompt_digest),
                "configurationDigest": str(agent.configuration_digest),
                "executable": value.agent_executable,
            },
        },
        "configurationReceipt": {
            "path": _stored_relative(
                value.artifact_root, value.configuration_receipt, "configuration receipt"
            ),
            "digest": str(value.configuration_receipt_digest),
        },
        "lanes": [
            {
                "lane": launch.lane.value,
                "targetId": launch.target_id,
                "xctestrunPath": _stored_relative(
                    value.artifact_root,
                    launch.xctestrun_path,
                    f"{launch.lane.value} .xctestrun",
                ),
            }
            for launch in value.launches
        ],
    }
    if value.bootstrap:
        payload["bootstrap"] = True
    return payload


def write_execution_input(
    path: Path, value: FrozenExecutionInput, *, replace: bool = False
) -> Path:
    if replace:
        raise ExecutionIdentityError("schema v2 execution input is immutable")
    destination = _absolute_lexical(path, "execution input path")
    relative = _relative_path(value.artifact_root, destination, "execution input path")
    if relative == Path("."):
        raise ExecutionIdentityError("execution input path must identify a file")
    source = canonical_bytes(execution_input_payload(value)) + b"\n"
    with _directory_descriptor(value.artifact_root, "artifact root") as artifact_descriptor:
        parent_descriptor = (
            os.dup(artifact_descriptor)
            if relative.parent == Path(".")
            else _open_relative_directory(
                artifact_descriptor, relative.parent, "execution input parent"
            )
        )
        try:
            _write_once_regular_at(
                parent_descriptor, relative.name, source, "execution input"
            )
        finally:
            os.close(parent_descriptor)
    return destination


def _decode_canonical_json(source: bytes, label: str) -> Mapping[str, Any]:
    if not source.endswith(b"\n"):
        raise ExecutionIdentityError(f"{label} must be canonical JSON with a newline")

    def unique(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ExecutionIdentityError(f"{label} repeats field {key!r}")
            result[key] = value
        return result

    def reject_constant(value: str) -> None:
        raise ExecutionIdentityError(f"{label} rejects JSON constant {value}")

    try:
        value = json.loads(
            source.decode("utf-8"),
            object_pairs_hook=unique,
            parse_constant=reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ExecutionIdentityError(f"{label} must be valid UTF-8 JSON") from error
    if not isinstance(value, dict):
        raise ExecutionIdentityError(f"{label} must be a JSON object")
    if canonical_bytes(value) + b"\n" != source:
        raise ExecutionIdentityError(f"{label} must use canonical JSON encoding")
    return value


def _object(value: object, fields: Iterable[str], location: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ExecutionIdentityError(f"{location} must be a JSON object")
    expected = frozenset(fields)
    unknown = sorted(set(value) - expected)
    missing = sorted(expected - set(value))
    if unknown:
        raise ExecutionIdentityError(
            f"{location} has unknown field(s): {', '.join(unknown)}"
        )
    if missing:
        raise ExecutionIdentityError(
            f"{location} misses field(s): {', '.join(missing)}"
        )
    return value


def _text(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ExecutionIdentityError(f"{location} must be non-empty text")
    return value


def _digest(value: object, location: str) -> Digest:
    text = _text(value, location)
    try:
        return Digest(parse_identifier("digest", text, location))
    except RegressionError as error:
        raise ExecutionIdentityError(f"{location} must be a SHA-256 identity") from error


def _parse_toolchain(value: object, location: str) -> ToolchainIdentity:
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
    try:
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
    except RegressionError as error:
        raise ExecutionIdentityError(f"{location} is invalid") from error


def _parse_build_identity(value: object) -> BuildIdentity:
    build = _object(
        value,
        (
            "bundleIdentifier",
            "gitRevision",
            "sourceTreeDigest",
            "configurationDigest",
            "toolchain",
            "laneArtifacts",
        ),
        "buildIdentity",
    )
    artifacts_value = build["laneArtifacts"]
    if not isinstance(artifacts_value, list) or len(artifacts_value) != 2:
        raise ExecutionIdentityError(
            "buildIdentity.laneArtifacts must contain simulator and device"
        )
    artifacts = []
    for index, value in enumerate(artifacts_value):
        location = f"buildIdentity.laneArtifacts[{index}]"
        parsed = _object(
            value,
            ("lane", "xctestrunDigest", "testProductsDigest", "applicationCodeDigest"),
            location,
        )
        try:
            lane = BoundLane(parsed["lane"])
        except (TypeError, ValueError) as error:
            raise ExecutionIdentityError(f"{location}.lane is invalid") from error
        artifacts.append(
            LaneBuildArtifact(
                lane,
                _digest(parsed["xctestrunDigest"], f"{location}.xctestrunDigest"),
                _digest(parsed["testProductsDigest"], f"{location}.testProductsDigest"),
                _digest(
                    parsed["applicationCodeDigest"], f"{location}.applicationCodeDigest"
                ),
            )
        )
    try:
        return BuildIdentity(
            _text(build["bundleIdentifier"], "buildIdentity.bundleIdentifier"),
            _text(build["gitRevision"], "buildIdentity.gitRevision"),
            _digest(build["sourceTreeDigest"], "buildIdentity.sourceTreeDigest"),
            _digest(build["configurationDigest"], "buildIdentity.configurationDigest"),
            _parse_toolchain(build["toolchain"], "buildIdentity.toolchain"),
            tuple(artifacts),
        )
    except RegressionError as error:
        raise ExecutionIdentityError("buildIdentity is invalid") from error


def _parse_lanes(
    value: object, artifact_root: Path, build: BuildIdentity
) -> tuple[FrozenTestLaunch, ...]:
    if not isinstance(value, list) or len(value) != 2:
        raise ExecutionIdentityError("lanes must contain simulator and device")
    artifacts = {artifact.lane: artifact for artifact in build.lane_artifacts}
    launches = []
    for index, item in enumerate(value):
        location = f"lanes[{index}]"
        parsed = _object(item, ("lane", "targetId", "xctestrunPath"), location)
        try:
            lane = BoundLane(parsed["lane"])
        except (TypeError, ValueError) as error:
            raise ExecutionIdentityError(f"{location}.lane is invalid") from error
        relative = _validated_relative(
            _text(parsed["xctestrunPath"], f"{location}.xctestrunPath"),
            f"{location}.xctestrunPath",
        )
        expected_prefix = (
            Path("lanes") / lane.value / "DerivedData" / "Build" / "Products"
        )
        try:
            relative.relative_to(expected_prefix)
        except ValueError as error:
            raise ExecutionIdentityError(
                f"{location}.xctestrunPath is outside the fixed lane Products root"
            ) from error
        target = _text(parsed["targetId"], f"{location}.targetId")
        launches.append(
            FrozenTestLaunch(
                lane,
                target,
                artifact_root / relative,
                _destination_specifier(lane, target),
                artifacts[lane],
            )
        )
    launches.sort(key=lambda item: _lane_key(item.lane))
    if tuple(item.lane for item in launches) != _LANES:
        raise ExecutionIdentityError("lanes must cover simulator and device exactly")
    return tuple(launches)


def load_execution_input(path: Path) -> FrozenExecutionInput:
    source_path = _absolute_lexical(path, "execution input")
    source = _read_absolute_regular(source_path, "execution input")
    raw_root = _decode_canonical_json(source, "execution input")
    bootstrap_raw = raw_root.get("bootstrap")
    if bootstrap_raw is not None:
        if bootstrap_raw is not True:
            raise ExecutionIdentityError("bootstrap flag must be true when present")
        bootstrap = True
        filtered = dict(raw_root)
        filtered.pop("bootstrap", None)
        root = _object(
            filtered,
            (
                "schema",
                "schemaVersion",
                "repositoryRoot",
                "artifactRoot",
                "buildIdentity",
                "evidenceEnvironmentIdentity",
                "configurationReceipt",
                "lanes",
            ),
            "execution input",
        )
    else:
        bootstrap = False
        root = _object(
            raw_root,
            (
                "schema",
                "schemaVersion",
                "repositoryRoot",
                "artifactRoot",
                "buildIdentity",
                "evidenceEnvironmentIdentity",
                "configurationReceipt",
                "lanes",
            ),
            "execution input",
        )
    if (
        root["schema"] != INPUT_SCHEMA
        or type(root["schemaVersion"]) is not int
        or root["schemaVersion"] != INPUT_SCHEMA_VERSION
    ):
        raise ExecutionIdentityError("execution input schema identity is unsupported")
    repository = _canonical_absolute_path(root["repositoryRoot"], "repositoryRoot")
    artifact = _canonical_absolute_path(root["artifactRoot"], "artifactRoot")
    repository, artifact = _validated_roots(repository, artifact, create_artifact=False)
    _relative_path(artifact, source_path, "execution input")
    build = _parse_build_identity(root["buildIdentity"])
    evidence_value = _object(
        root["evidenceEnvironmentIdentity"],
        ("deterministicRuntimeDigest", "agentEnvironment"),
        "evidenceEnvironmentIdentity",
    )
    agent_value = _object(
        evidence_value["agentEnvironment"],
        ("model", "promptDigest", "configurationDigest", "executable"),
        "agentEnvironment",
    )
    configuration_value = _object(
        root["configurationReceipt"],
        ("path", "digest"),
        "configurationReceipt",
    )
    if configuration_value["path"] != CONFIGURATION_RECEIPT_NAME:
        raise ExecutionIdentityError(
            "configurationReceipt.path must use the fixed artifact-root path"
        )
    revision = _revision(repository)
    if revision != build.git_revision:
        raise ExecutionIdentityError("git revision differs from the frozen identity")
    source_digest = repository_source_digest(repository)
    if source_digest != build.source_tree_digest:
        raise ExecutionIdentityError("source tree differs from the frozen digest")
    toolchain = query_toolchain_identity()
    if toolchain != build.toolchain:
        raise ExecutionIdentityError("toolchain differs from the frozen identity")
    launches = _parse_lanes(root["lanes"], artifact, build)
    targets = _validated_lane_targets(
        {launch.lane: launch.target_id for launch in launches}, "lane targets"
    )
    if bootstrap:
        expected_configuration_digest = _bootstrap_configuration_digest(source_digest)
        with _directory_descriptor(artifact, "artifact root") as artifact_descriptor:
            states = tuple(
                _bind_lane(
                    artifact,
                    artifact_descriptor,
                    lane,
                    revision,
                    source_digest,
                    toolchain,
                )
                for lane in _LANES
            )
            relative_input = _relative_path(artifact, source_path, "execution input")
            current_source, _ = _read_regular_at(
                artifact_descriptor, relative_input, "execution input"
            )
        if current_source != source:
            raise ExecutionIdentityError("execution input changed while it was loaded")
        if _digest(configuration_value["digest"], "configurationReceipt.digest") != expected_configuration_digest:
            raise ExecutionIdentityError("bootstrap configuration receipt digest is invalid")
        if build.configuration_digest != expected_configuration_digest:
            raise ExecutionIdentityError(
                "BuildIdentity configuration digest does not bind the bootstrap receipt"
            )
        configuration_digest = expected_configuration_digest
    else:
        with _directory_descriptor(artifact, "artifact root") as artifact_descriptor:
            configuration_digest, _ = _configuration_receipt(artifact_descriptor, source_digest)
            states = tuple(
                _bind_lane(
                    artifact,
                    artifact_descriptor,
                    lane,
                    revision,
                    source_digest,
                    toolchain,
                )
                for lane in _LANES
            )
            relative_input = _relative_path(artifact, source_path, "execution input")
            current_source, _ = _read_regular_at(
                artifact_descriptor, relative_input, "execution input"
            )
        if current_source != source:
            raise ExecutionIdentityError("execution input changed while it was loaded")
        expected_configuration_digest = _digest(
            configuration_value["digest"], "configurationReceipt.digest"
        )
        if configuration_digest != expected_configuration_digest:
            raise ExecutionIdentityError("configuration receipt differs from the frozen digest")
        if build.configuration_digest != configuration_digest:
            raise ExecutionIdentityError(
                "BuildIdentity configuration digest does not bind the receipt"
            )
    bundle_identifiers = {state.bundle_identifier for state in states}
    if len(bundle_identifiers) != 1:
        raise ExecutionIdentityError(
            "simulator and device Enchron apps have different bundle identifiers"
        )
    actual_artifacts = tuple(state.artifact for state in states)
    _assert_no_lane_collisions(actual_artifacts)
    actual_build = BuildIdentity(
        next(iter(bundle_identifiers)),
        revision,
        source_digest,
        configuration_digest,
        toolchain,
        actual_artifacts,
    )
    if actual_build != build:
        raise ExecutionIdentityError(
            "Xcode execution products differ from the frozen BuildIdentity"
        )
    stored_paths = {launch.lane: launch.xctestrun_path for launch in launches}
    actual_paths = {state.lane: state.xctestrun_path for state in states}
    if stored_paths != actual_paths:
        raise ExecutionIdentityError(
            "a lane .xctestrun path differs from exact Xcode discovery"
        )
    runtime_digest = _digest(
        evidence_value["deterministicRuntimeDigest"], "deterministicRuntimeDigest"
    )
    if deterministic_runtime_digest(repository) != runtime_digest:
        raise ExecutionIdentityError("deterministic runtime differs from the frozen digest")
    model = _text(agent_value["model"], "agentEnvironment.model")
    executable = _text(agent_value["executable"], "agentEnvironment.executable")
    current_agent = agent_environment(model, executable)
    if (
        current_agent.prompt_digest
        != _digest(agent_value["promptDigest"], "agentEnvironment.promptDigest")
        or current_agent.configuration_digest
        != _digest(
            agent_value["configurationDigest"],
            "agentEnvironment.configurationDigest",
        )
    ):
        raise ExecutionIdentityError("Agent environment differs from the frozen identity")
    evidence = EvidenceEnvironmentIdentity(runtime_digest, current_agent)
    actual_launches = tuple(
        FrozenTestLaunch(
            state.lane,
            targets[state.lane],
            state.xctestrun_path,
            _destination_specifier(state.lane, targets[state.lane]),
            state.artifact,
        )
        for state in states
    )
    value = FrozenExecutionInput(
        repository,
        artifact,
        actual_build,
        evidence,
        actual_launches,
        artifact / CONFIGURATION_RECEIPT_NAME,
        configuration_digest,
        model,
        executable,
        bootstrap,
    )
    if canonical_bytes(execution_input_payload(value)) + b"\n" != source:
        raise ExecutionIdentityError("execution input does not bind its current values")
    return value


def load_frozen_test_launch(
    path: Path, lane: BoundLane, target_id: str
) -> FrozenTestLaunch:
    if not isinstance(lane, BoundLane):
        raise ExecutionIdentityError("requested test lane must be concrete")
    if not isinstance(target_id, str) or not target_id.strip():
        raise ExecutionIdentityError("requested test target ID must be non-empty")
    execution = load_execution_input(path)
    launch = next(item for item in execution.launches if item.lane is lane)
    if launch.target_id != target_id:
        raise ExecutionIdentityError(
            "requested test target differs from the frozen lane target"
        )
    return launch


__all__ = (
    "ExecutionIdentityError",
    "FrozenExecutionInput",
    "FrozenTestLaunch",
    "INPUT_SCHEMA",
    "INPUT_SCHEMA_VERSION",
    "LinkProvenance",
    "LINK_PROVENANCE_SCHEMA",
    "LINK_PROVENANCE_SCHEMA_VERSION",
    "PhysicalVisionOSDevice",
    "PhysicalVisionOSDeviceRegistry",
    "PhysicalVisionOSDeviceRegistrySource",
    "PreparedLaneProvenance",
    "SimulatorUDIDSource",
    "deterministic_runtime_digest",
    "execution_input_payload",
    "freeze_execution_input",
    "load_execution_input",
    "load_frozen_test_launch",
    "prepare_build_provenance",
    "query_toolchain_identity",
    "registered_physical_visionos_devices",
    "registered_simulator_udids",
    "repository_source_digest",
    "write_execution_input",
)
