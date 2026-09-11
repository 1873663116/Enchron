#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
from typing import Protocol

if str(Path(__file__).parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).parent))

import enchron_target


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
DEFAULT_BUNDLE_ID = "com.chen.Enchron"
SHA256 = "sha256:"


class FixtureStageError(ValueError):
    pass


@dataclass(frozen=True)
class RegisteredFixture:
    identifier: str
    import_path: PurePosixPath
    digest: str


@dataclass(frozen=True)
class FixtureRegistry:
    path: Path
    digest: str
    fixtures: tuple[RegisteredFixture, ...]
    total_count: int

    @classmethod
    def load(cls, path: Path) -> "FixtureRegistry":
        try:
            encoded = path.read_bytes()
            payload = json.loads(encoded)
        except (OSError, json.JSONDecodeError) as error:
            raise FixtureStageError(f"fixture registry cannot be read: {error}") from error
        if not isinstance(payload, dict) or payload.get("schemaVersion") != 2:
            raise FixtureStageError("fixture registry must use schemaVersion 2")
        entries = payload.get("fixtures")
        if not isinstance(entries, list):
            raise FixtureStageError("fixture registry fixtures must be a list")
        fixtures: list[RegisteredFixture] = []
        seen: set[str] = set()
        for index, entry in enumerate(entries):
            if not isinstance(entry, dict):
                raise FixtureStageError(f"fixtures[{index}] must be an object")
            identifier = entry.get("id")
            if not isinstance(identifier, str) or not identifier:
                raise FixtureStageError(f"fixtures[{index}].id must be nonempty")
            if identifier in seen:
                raise FixtureStageError(f"duplicate fixture id: {identifier}")
            seen.add(identifier)
            raw_import_path = entry.get("deviceImportPath")
            if raw_import_path is None:
                continue
            import_path = _safe_registry_path(raw_import_path, identifier)
            digest = entry.get("sha256")
            if not isinstance(digest, str) or not _is_sha256(digest):
                raise FixtureStageError(f"{identifier}.sha256 is not a SHA-256 hex digest")
            fixtures.append(RegisteredFixture(identifier, import_path, digest))
        return cls(
            path.resolve(),
            SHA256 + hashlib.sha256(encoded).hexdigest(),
            tuple(fixtures),
            len(entries),
        )

    def fixture(self, identifier: str) -> RegisteredFixture:
        for fixture in self.fixtures:
            if fixture.identifier == identifier:
                return fixture
        known = {fixture.identifier for fixture in self.fixtures}
        if identifier in known:
            raise AssertionError("unreachable fixture lookup")
        raise FixtureStageError(
            f"fixture {identifier!r} is unknown or has no deviceImportPath"
        )


class StageTransport(Protocol):
    lane: str
    target: str

    def copy_to_container(self, source: Path, destination: str) -> None: ...

    def copy_from_container(self, source: str, destination: Path) -> None: ...


@dataclass(frozen=True)
class EnchronStageTransport:
    lane: str
    target: str
    bundle_id: str
    developer_dir: str

    def __post_init__(self) -> None:
        if self.lane not in ("simulator", "device"):
            raise FixtureStageError("lane must be simulator or device")
        if not self.target:
            raise FixtureStageError("target must not be empty")
        actual_lane = "simulator" if enchron_target.is_simulator(self.target) else "device"
        if actual_lane != self.lane:
            raise FixtureStageError(
                f"target {self.target} belongs to {actual_lane}, not {self.lane}"
            )

    def copy_to_container(self, source: Path, destination: str) -> None:
        if self.lane == "simulator":
            container = enchron_target.simulator_container(self.target, self.bundle_id)
            if container is None:
                raise FixtureStageError(
                    f"cannot locate simulator container for {self.bundle_id}"
                )
            target = container / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            return
        identifier = enchron_target.core_device()
        if not identifier:
            raise FixtureStageError(enchron_target.MISSING_CORE_DEVICE)
        environment = {"DEVELOPER_DIR": self.developer_dir, "PATH": "/usr/bin:/bin"}
        try:
            completed = subprocess.run(
                [
                    "xcrun",
                    "devicectl",
                    "device",
                    "copy",
                    "to",
                    "--device",
                    identifier,
                    "--domain-type",
                    "appDataContainer",
                    "--domain-identifier",
                    self.bundle_id,
                    "--source",
                    str(source),
                    "--destination",
                    destination,
                ],
                capture_output=True,
                text=True,
                env=environment,
                timeout=600,
            )
        except subprocess.TimeoutExpired as error:
            raise FixtureStageError(f"device copy timed out for {source.name}") from error
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()[-500:]
            raise FixtureStageError(f"device copy failed: {detail}")

    def copy_from_container(self, source: str, destination: Path) -> None:
        completed = enchron_target.copy_from_container(
            target=self.target,
            bundle_id=self.bundle_id,
            source=source,
            destination=destination,
            developer_dir=self.developer_dir,
        )
        if completed.returncode != 0:
            detail = (completed.stderr or completed.stdout).strip()[-500:]
            raise FixtureStageError(f"copy-back verification failed: {detail}")


def _safe_registry_path(value: object, identifier: str) -> PurePosixPath:
    if not isinstance(value, str) or not value or "\\" in value:
        raise FixtureStageError(f"{identifier}.deviceImportPath must be a POSIX path")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.name in ("", ".", ".."):
        raise FixtureStageError(f"{identifier}.deviceImportPath escapes the source root")
    if path.name != value.split("/")[-1]:
        raise FixtureStageError(f"{identifier}.deviceImportPath has no file basename")
    return path


def _is_sha256(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def _digest(path: Path) -> tuple[str, int]:
    hasher = hashlib.sha256()
    byte_length = 0
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            byte_length += len(chunk)
            hasher.update(chunk)
    return hasher.hexdigest(), byte_length


def stage_registered_fixture(
    *,
    registry: FixtureRegistry,
    fixture_id: str,
    source_root: Path,
    transport: StageTransport,
) -> dict[str, object]:
    if not source_root.is_absolute():
        raise FixtureStageError("sourceRoot must be an absolute directory")
    resolved_root = source_root.resolve()
    if not resolved_root.is_dir():
        raise FixtureStageError(f"sourceRoot is not a directory: {resolved_root}")
    fixture = registry.fixture(fixture_id)
    source = (resolved_root / Path(*fixture.import_path.parts)).resolve()
    try:
        source.relative_to(resolved_root)
    except ValueError as error:
        raise FixtureStageError("registered fixture resolves outside sourceRoot") from error
    if not source.is_file():
        raise FixtureStageError(f"registered fixture source is missing: {source}")
    source_digest, byte_length = _digest(source)
    if source_digest != fixture.digest:
        raise FixtureStageError(
            f"source digest mismatch for {fixture_id}: expected {fixture.digest}, found {source_digest}"
        )
    destination = f"Documents/TestMediaInbox/{fixture.import_path.name}"
    transport.copy_to_container(source, destination)
    with tempfile.TemporaryDirectory(prefix="enchron-fixture-copyback-") as directory:
        copyback = Path(directory) / fixture.import_path.name
        transport.copy_from_container(destination, copyback)
        if not copyback.is_file():
            raise FixtureStageError("copy-back transport produced no regular file")
        round_trip_digest, round_trip_length = _digest(copyback)
    if round_trip_digest != source_digest or round_trip_length != byte_length:
        raise FixtureStageError(
            "round-trip fixture bytes differ from the registered source: "
            f"digest {round_trip_digest}, bytes {round_trip_length}"
        )
    receipt: dict[str, object] = {
        "schema": "fixture-stage-receipt@1",
        "fixtureID": fixture.identifier,
        "registry": {
            "path": registry.path.relative_to(REPOSITORY_ROOT).as_posix()
            if registry.path.is_relative_to(REPOSITORY_ROOT)
            else str(registry.path),
            "digest": registry.digest,
        },
        "source": {
            "root": str(resolved_root),
            "relativePath": fixture.import_path.as_posix(),
            "digest": SHA256 + source_digest,
            "byteLength": byte_length,
        },
        "lane": transport.lane,
        "target": transport.target,
        "destination": destination,
        "copyBack": {
            "digest": SHA256 + round_trip_digest,
            "byteLength": round_trip_length,
        },
    }
    canonical = json.dumps(
        receipt, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    receipt["receiptDigest"] = SHA256 + hashlib.sha256(canonical).hexdigest()
    return receipt


def active_developer_dir() -> str:
    completed = subprocess.run(
        ["xcode-select", "-p"], capture_output=True, text=True, check=True
    )
    return completed.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stage one registered fixture and prove destination byte identity."
    )
    parser.add_argument("--fixture-id", required=True)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--lane", required=True, choices=("simulator", "device"))
    parser.add_argument("--target", required=True)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    arguments = parser.parse_args()
    try:
        registry = FixtureRegistry.load(arguments.registry)
        transport = EnchronStageTransport(
            arguments.lane,
            arguments.target,
            arguments.bundle_id,
            active_developer_dir(),
        )
        receipt = stage_registered_fixture(
            registry=registry,
            fixture_id=arguments.fixture_id,
            source_root=arguments.source_root,
            transport=transport,
        )
    except (FixtureStageError, OSError, subprocess.SubprocessError) as error:
        print(f"fixture stage failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(receipt, indent=2, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
