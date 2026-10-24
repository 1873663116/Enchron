#!/usr/bin/env python3
"""Seed and verify the fixed Simulator Files import fixture."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import time
from typing import Mapping, Protocol


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
DEFAULT_FIXTURE_ROOT = REPOSITORY_ROOT.parent / "TestMedia"
DEFAULT_RUNTIME_ROOT = REPOSITORY_ROOT / ".build/regression-system-import"
FIXTURE_ID = "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1"
VISIBLE_FILENAME = "Enchron-System-Import-30s.mp4"
LOCAL_STORAGE_GROUP = "group.com.apple.FileProvider.LocalStorage"
REPORT_SCHEMA = "enchron.regression.system-import-preflight@1"
RUNTIME_SCHEMA = "enchron.regression.system-import-runtime@1"
SHA256_PREFIX = "sha256:"
UUID_PATTERN = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-"
    r"[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}$"
)


class SystemImportError(RuntimeError):
    pass


class SystemImportConfigurationError(SystemImportError):
    pass


class SystemImportUnavailable(SystemImportError):
    pass


@dataclass(frozen=True)
class SystemImportConfiguration:
    device_identifier: str
    runtime_root: Path = DEFAULT_RUNTIME_ROOT
    registry_path: Path = DEFAULT_REGISTRY
    fixture_root: Path = DEFAULT_FIXTURE_ROOT

    def __post_init__(self) -> None:
        if not UUID_PATTERN.fullmatch(self.device_identifier):
            raise SystemImportConfigurationError(
                "system import target must be one exact Simulator UUID"
            )
        object.__setattr__(self, "runtime_root", Path(self.runtime_root).resolve())
        object.__setattr__(self, "registry_path", Path(self.registry_path).resolve())
        object.__setattr__(self, "fixture_root", Path(self.fixture_root).resolve())

    @property
    def runtime_file(self) -> Path:
        return self.runtime_root / self.device_identifier / "runtime.json"


@dataclass(frozen=True)
class _Fixture:
    identifier: str
    path: Path
    digest: str
    size: int
    duration_seconds: float


class SimulatorBoundary(Protocol):
    def resolve_booted_visionos_data_root(self, device_identifier: str) -> Path: ...


def _file_digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            hasher.update(chunk)
    return SHA256_PREFIX + hasher.hexdigest()


def _canonical_digest(value: object) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return SHA256_PREFIX + hashlib.sha256(encoded).hexdigest()


def _is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and value.startswith(SHA256_PREFIX)
        and len(value) == len(SHA256_PREFIX) + 64
        and all(character in "0123456789abcdef" for character in value[7:])
    )


def _load_fixture(configuration: SystemImportConfiguration) -> _Fixture:
    try:
        document = json.loads(configuration.registry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemImportConfigurationError(
            "fixture registry is unreadable"
        ) from error
    if not isinstance(document, dict) or document.get("schemaVersion") != 2:
        raise SystemImportConfigurationError(
            "fixture registry must use schemaVersion 2"
        )
    fixtures = document.get("fixtures")
    if not isinstance(fixtures, list):
        raise SystemImportConfigurationError(
            "fixture registry fixtures must be a list"
        )
    matches = [
        item
        for item in fixtures
        if isinstance(item, dict) and item.get("id") == FIXTURE_ID
    ]
    if len(matches) != 1:
        raise SystemImportConfigurationError(
            "system import fixture must appear exactly once"
        )
    entry = matches[0]
    relative = entry.get("deviceImportPath")
    digest = entry.get("sha256")
    duration = entry.get("durationSeconds")
    regression_sets = entry.get("regressionSets")
    if not isinstance(relative, str) or not relative:
        raise SystemImportConfigurationError(
            "system import fixture has no device import path"
        )
    pure_path = PurePosixPath(relative)
    if pure_path.is_absolute() or ".." in pure_path.parts:
        raise SystemImportConfigurationError(
            "system import fixture path is unsafe"
        )
    if (
        not isinstance(digest, str)
        or len(digest) != 64
        or any(character not in "0123456789abcdef" for character in digest)
    ):
        raise SystemImportConfigurationError(
            "system import fixture has no exact SHA-256"
        )
    if not isinstance(duration, (int, float)) or duration <= 0:
        raise SystemImportConfigurationError(
            "system import fixture has no positive duration"
        )
    if not isinstance(regression_sets, list) or "system-import" not in regression_sets:
        raise SystemImportConfigurationError(
            "system import fixture is outside the system-import set"
        )
    candidate = configuration.fixture_root.joinpath(*pure_path.parts).resolve()
    try:
        candidate.relative_to(configuration.fixture_root)
    except ValueError as error:
        raise SystemImportConfigurationError(
            "system import fixture escaped its root"
        ) from error
    if not candidate.is_file() or candidate.is_symlink():
        raise SystemImportUnavailable("system import fixture is missing")
    observed = _file_digest(candidate)
    expected = SHA256_PREFIX + digest
    if observed != expected:
        raise SystemImportUnavailable("system import fixture digest mismatch")
    return _Fixture(
        FIXTURE_ID,
        candidate,
        expected,
        candidate.stat().st_size,
        float(duration),
    )


class SimctlBoundary:
    def _run(self, arguments: list[str]) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                ["xcrun", "simctl", *arguments],
                check=True,
                capture_output=True,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise SystemImportUnavailable("simctl operation failed") from error

    def resolve_booted_visionos_data_root(self, device_identifier: str) -> Path:
        completed = self._run(["list", "devices", "--json"])
        try:
            document = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise SystemImportUnavailable("simctl device inventory is invalid") from error
        devices = document.get("devices") if isinstance(document, dict) else None
        if not isinstance(devices, dict):
            raise SystemImportUnavailable("simctl device inventory is invalid")
        matches: list[dict[str, object]] = []
        for runtime, values in devices.items():
            if (
                not runtime.startswith("com.apple.CoreSimulator.SimRuntime.")
                or not runtime.split(".")[-1].startswith(("xrOS-", "visionOS-"))
                or not isinstance(values, list)
            ):
                continue
            matches.extend(
                value
                for value in values
                if isinstance(value, dict)
                and value.get("udid") == device_identifier
                and value.get("state") == "Booted"
                and value.get("isAvailable", True) is True
            )
        if len(matches) != 1:
            raise SystemImportUnavailable(
                "system import target is not one booted visionOS Simulator"
            )
        home = self._run(["getenv", device_identifier, "HOME"]).stdout.strip()
        if not home:
            raise SystemImportUnavailable("Simulator data root is unavailable")
        root = Path(home).resolve()
        if (
            root.name != "data"
            or root.parent.name != device_identifier
            or root.parent.parent.name != "Devices"
            or not root.is_dir()
        ):
            raise SystemImportUnavailable("Simulator data root shape is invalid")
        return root

def _local_storage_root(data_root: Path) -> Path:
    app_groups = data_root / "Containers/Shared/AppGroup"
    matches: list[Path] = []
    try:
        candidates = sorted(app_groups.iterdir())
    except OSError as error:
        raise SystemImportUnavailable(
            "Simulator File Provider groups are unavailable"
        ) from error
    for candidate in candidates:
        metadata = candidate / ".com.apple.mobile_container_manager.metadata.plist"
        try:
            with metadata.open("rb") as source:
                document = plistlib.load(source)
        except (OSError, plistlib.InvalidFileException):
            continue
        if (
            isinstance(document, dict)
            and document.get("MCMMetadataIdentifier") == LOCAL_STORAGE_GROUP
        ):
            matches.append(candidate / "File Provider Storage")
    if len(matches) != 1:
        raise SystemImportUnavailable(
            "Simulator local File Provider storage is not unique"
        )
    storage = matches[0].resolve()
    try:
        storage.relative_to(data_root)
    except ValueError as error:
        raise SystemImportUnavailable(
            "Simulator local File Provider escaped the data root"
        ) from error
    if not storage.is_dir():
        raise SystemImportUnavailable(
            "Simulator local File Provider storage is missing"
        )
    return storage


def _copy_fixture_to_files_provider(fixture: _Fixture, storage: Path) -> Path:
    destination = storage / VISIBLE_FILENAME
    if destination.is_symlink():
        raise SystemImportUnavailable("Files import fixture destination is a symlink")
    if destination.exists():
        if not destination.is_file():
            raise SystemImportUnavailable(
                "Files import fixture destination is not a regular file"
            )
        if _file_digest(destination) == fixture.digest:
            return destination
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{VISIBLE_FILENAME}.", dir=storage
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output, fixture.path.open("rb") as source:
            shutil.copyfileobj(source, output, length=1024 * 1024)
            output.flush()
            os.fsync(output.fileno())
        if _file_digest(temporary) != fixture.digest:
            raise SystemImportUnavailable("Files import fixture copy changed bytes")
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    if _file_digest(destination) != fixture.digest:
        raise SystemImportUnavailable("Files import fixture verification failed")
    return destination


def _write_runtime(path: Path, document: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    encoded = (
        json.dumps(dict(document), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")
    try:
        information = path.lstat()
        current = path.read_bytes() if stat.S_ISREG(information.st_mode) else None
    except OSError:
        information = None
        current = None
    if (
        current == encoded
        and information is not None
        and information.st_uid == os.getuid()
    ):
        os.chmod(path, 0o600)
        return
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
    finally:
        temporary.unlink(missing_ok=True)


def _runtime_document(
    configuration: SystemImportConfiguration,
    fixture: _Fixture,
    data_root: Path,
    files_path: Path,
) -> dict[str, object]:
    facts: dict[str, object] = {
        "deviceIdentifier": configuration.device_identifier,
        "fixture": {
            "id": fixture.identifier,
            "digest": fixture.digest,
            "size": fixture.size,
            "durationSeconds": fixture.duration_seconds,
        },
        "filesPicker": {
            "authorizationMode": "system-picker-security-scoped",
            "provider": "local-storage",
            "displayName": VISIBLE_FILENAME,
            "path": str(files_path),
            "digest": _file_digest(files_path),
        },
        "simulatorDataRoot": str(data_root),
    }
    return {
        "schema": RUNTIME_SCHEMA,
        "environmentIdentity": "system-import:"
        + _canonical_digest(facts).removeprefix(SHA256_PREFIX)[:24],
        **facts,
    }


def validate_runtime(path: Path) -> dict[str, object]:
    try:
        information = path.lstat()
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemImportConfigurationError(
            "system import runtime identity is unreadable"
        ) from error
    if (
        not stat.S_ISREG(information.st_mode)
        or information.st_uid != os.getuid()
        or stat.S_IMODE(information.st_mode) != 0o600
    ):
        raise SystemImportConfigurationError(
            "system import runtime identity must be an owner-only 0600 regular file"
        )
    expected_keys = {
        "schema",
        "environmentIdentity",
        "deviceIdentifier",
        "fixture",
        "filesPicker",
        "simulatorDataRoot",
    }
    if not isinstance(document, dict) or set(document) != expected_keys:
        raise SystemImportConfigurationError(
            "system import runtime identity schema drifted"
        )
    if document.get("schema") != RUNTIME_SCHEMA:
        raise SystemImportConfigurationError(
            "system import runtime identity version drifted"
        )
    identity = document.get("environmentIdentity")
    if (
        not isinstance(identity, str)
        or not re.fullmatch(r"system-import:[0-9a-f]{24}", identity)
    ):
        raise SystemImportConfigurationError(
            "system import environment identity is invalid"
        )
    facts = {key: document[key] for key in expected_keys - {"schema", "environmentIdentity"}}
    expected_identity = "system-import:" + _canonical_digest(facts).removeprefix(
        SHA256_PREFIX
    )[:24]
    if identity != expected_identity:
        raise SystemImportConfigurationError(
            "system import environment identity is not bound to its facts"
        )
    fixture = document.get("fixture")
    files = document.get("filesPicker")
    if (
        not isinstance(fixture, dict)
        or set(fixture) != {"id", "digest", "size", "durationSeconds"}
        or fixture.get("id") != FIXTURE_ID
        or not _is_sha256(fixture.get("digest"))
        or not isinstance(fixture.get("size"), int)
        or fixture["size"] <= 0
        or not isinstance(fixture.get("durationSeconds"), (int, float))
    ):
        raise SystemImportConfigurationError("system import fixture identity is invalid")
    if (
        not isinstance(files, dict)
        or set(files)
        != {"authorizationMode", "provider", "displayName", "path", "digest"}
        or files.get("authorizationMode") != "system-picker-security-scoped"
        or files.get("provider") != "local-storage"
        or files.get("displayName") != VISIBLE_FILENAME
        or not _is_sha256(files.get("digest"))
        or not isinstance(files.get("path"), str)
    ):
        raise SystemImportConfigurationError("Files picker identity is invalid")
    if files["digest"] != fixture["digest"]:
        raise SystemImportConfigurationError(
            "system import picker bytes are not bound to the fixture"
        )
    return document


def _report(path: Path, runtime: Mapping[str, object]) -> dict[str, object]:
    return {
        "schema": REPORT_SCHEMA,
        "check": "system-import-fixtures",
        "ready": True,
        "runtimeIdentity": {
            "path": str(path),
            "mode": "0600",
            "environmentIdentity": runtime["environmentIdentity"],
        },
        "target": {
            "kind": "visionos-simulator",
            "deviceIdentifier": runtime["deviceIdentifier"],
        },
        "fixture": dict(runtime["fixture"]),
        "filesPicker": {
            key: runtime["filesPicker"][key]
            for key in ("authorizationMode", "provider", "displayName", "digest")
        },
    }


def ensure(
    configuration: SystemImportConfiguration,
    *,
    boundary: SimulatorBoundary | None = None,
) -> dict[str, object]:
    simulator = boundary or SimctlBoundary()
    data_root = simulator.resolve_booted_visionos_data_root(
        configuration.device_identifier
    )
    fixture = _load_fixture(configuration)
    storage = _local_storage_root(data_root)
    files_path = _copy_fixture_to_files_provider(fixture, storage)
    runtime_document = _runtime_document(
        configuration,
        fixture,
        data_root,
        files_path,
    )
    _write_runtime(configuration.runtime_file, runtime_document)
    runtime = validate_runtime(configuration.runtime_file)
    return _report(configuration.runtime_file, runtime)


def run_preflight(
    configuration: SystemImportConfiguration,
    *,
    boundary: SimulatorBoundary | None = None,
) -> dict[str, object]:
    try:
        return ensure(configuration, boundary=boundary)
    except SystemImportError as error:
        configuration.runtime_file.unlink(missing_ok=True)
        return {
            "schema": REPORT_SCHEMA,
            "check": "system-import-fixtures",
            "ready": False,
            "reason": str(error),
        }


def validate_preflight_report(
    report: object,
    *,
    device_identifier: str,
    runtime_file: Path | None = None,
) -> bool:
    if not isinstance(report, Mapping):
        return False
    target = report.get("target")
    identity = report.get("runtimeIdentity")
    if not isinstance(target, Mapping) or not isinstance(identity, Mapping):
        return False
    if (
        target.get("kind") != "visionos-simulator"
        or target.get("deviceIdentifier") != device_identifier
    ):
        return False
    expected_runtime = (
        Path(runtime_file).resolve()
        if runtime_file is not None
        else SystemImportConfiguration(device_identifier).runtime_file
    )
    if identity.get("path") != str(expected_runtime):
        return False
    try:
        runtime = validate_runtime(expected_runtime)
    except (OSError, SystemImportError):
        return False
    return dict(report) == _report(expected_runtime, runtime)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Seed and verify the fixed visionOS Simulator import fixture."
    )
    parser.add_argument("command", choices=("ensure",))
    parser.add_argument("--device", required=True)
    parser.add_argument("--runtime-root", type=Path, default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--fixture-root", type=Path, default=DEFAULT_FIXTURE_ROOT)
    return parser


def main(arguments: list[str] | None = None) -> int:
    options = _parser().parse_args(arguments)
    configuration = SystemImportConfiguration(
        device_identifier=options.device,
        runtime_root=options.runtime_root,
        registry_path=options.registry,
        fixture_root=options.fixture_root,
    )
    report = run_preflight(configuration)
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if report.get("ready") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
