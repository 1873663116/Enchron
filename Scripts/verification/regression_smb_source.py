#!/usr/bin/env python3
"""Verify the fixed SMB TestMedia share and publish its typed runtime identity."""

from __future__ import annotations

import argparse
import ctypes
from dataclasses import dataclass
import hashlib
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import socket
import stat
import subprocess
import tempfile
from types import MappingProxyType
from typing import Mapping, Protocol
from urllib.parse import quote

from regression_paths import TEST_SERVICES_ROOT


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
DEFAULT_ENVIRONMENT_FILE = REPOSITORY_ROOT / ".env"
DEFAULT_RUNTIME_ROOT = TEST_SERVICES_ROOT / "smb"
SHARE_NAME = "TestMedia"
SHARE_LISTING_TIMEOUT_SECONDS = 30
REPORT_SCHEMA = "enchron.regression.smb-source-preflight@1"
SHA256_PREFIX = "sha256:"
RUNTIME_DOCUMENT_KEYS = frozenset(
    {
        "address",
        "user",
        "password",
        "shareName",
        "sourceIdentity",
        "aggregateDigest",
        "aggregateManifestHashes",
        "aggregatePaths",
        "hostShares",
    }
)


class SMBSourceError(RuntimeError):
    pass


class SMBSourceConfigurationError(SMBSourceError):
    pass


class SMBSourceUnavailable(SMBSourceError):
    pass


class SMBCredentialsRejected(SMBSourceUnavailable):
    pass


class SMBMountRejected(SMBSourceUnavailable):
    pass


@dataclass(frozen=True)
class SMBSourceConfiguration:
    runtime_root: Path
    registry_path: Path
    environment_file: Path
    address: str
    share_name: str = SHARE_NAME
    allow_loopback: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "runtime_root", Path(self.runtime_root).resolve())
        object.__setattr__(self, "registry_path", Path(self.registry_path).resolve())
        object.__setattr__(
            self, "environment_file", Path(self.environment_file).resolve()
        )
        try:
            parsed = ipaddress.ip_address(self.address)
        except ValueError:
            if self.address in {"localhost", "localhost.localdomain"}:
                if not self.allow_loopback:
                    raise SMBSourceConfigurationError("SMB address must be one literal LAN IPv4 address")
            elif not self.address.endswith(".local"):
                raise SMBSourceConfigurationError("SMB address must be one literal LAN IPv4 address or mDNS name")
            else:
                try:
                    infos = socket.getaddrinfo(self.address, None, socket.AF_INET, socket.SOCK_STREAM)
                except socket.gaierror as error:
                    raise SMBSourceConfigurationError("SMB mDNS name does not resolve") from error
                has_valid = False
                for info in infos:
                    candidate = info[4][0]
                    try:
                        ip = ipaddress.ip_address(candidate)
                    except ValueError:
                        continue
                    if ip.version == 4 and not ip.is_unspecified and not ip.is_multicast and (ip.is_private or ip.is_link_local or (ip.is_loopback and self.allow_loopback)):
                        if not ip.is_loopback or self.allow_loopback:
                            has_valid = True
                            break
                if not has_valid:
                    raise SMBSourceConfigurationError("SMB mDNS name must resolve to a LAN address")
            if self.share_name != SHARE_NAME:
                raise SMBSourceConfigurationError(f"SMB share must remain the fixed {SHARE_NAME} share")
            return
        if (
            parsed.version != 4
            or parsed.is_unspecified
            or parsed.is_multicast
            or (parsed.is_loopback and not self.allow_loopback)
            or not (parsed.is_private or parsed.is_link_local or parsed.is_loopback)
        ):
            raise SMBSourceConfigurationError(
                "SMB address must be one literal LAN IPv4 address"
            )
        if self.share_name != SHARE_NAME:
            raise SMBSourceConfigurationError(
                f"SMB share must remain the fixed {SHARE_NAME} share"
            )

    @property
    def runtime_file(self) -> Path:
        return self.runtime_root / "runtime.json"


@dataclass(frozen=True)
class _Credentials:
    user: str
    password: str


@dataclass(frozen=True)
class _AggregateObject:
    identifier: str
    relative_path: str
    digest: str


class MountBoundary(Protocol):
    def mount(
        self,
        address: str,
        share_name: str,
        user: str,
        password: str,
        mount_point: Path,
    ) -> None: ...

    def unmount(self, mount_point: Path) -> None: ...

    def shares(self, address: str, user: str, password: str) -> list[str]: ...


def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def _digest(value: object) -> str:
    return SHA256_PREFIX + hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _file_digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            hasher.update(chunk)
    return SHA256_PREFIX + hasher.hexdigest()


def _parse_shares(listing: str) -> list[str]:
    shares: list[str] = []
    for line in listing.splitlines():
        columns = line.rsplit(None, 1) if line.strip() else []
        if len(columns) != 2 or columns[1] != "Disk":
            continue
        name = columns[0].strip()
        if name and name != "Share" and not name.endswith("$"):
            shares.append(name)
    return sorted(shares)


def host_shares(address: str, user: str, password: str) -> list[str]:
    """Ask the server which shares it offers, so the product can be compared to it.

    The fixture names one share, but this Mac answers `smbutil view` with six.
    A rubric that only looked for the fixture's share would pass a product that
    silently dropped the other five, which is the whole thing the SMB root is
    supposed to show.
    """
    target = f"//{quote(user, safe='')}:{quote(password, safe='')}@{address}"
    try:
        listing = subprocess.run(
            ["smbutil", "view", "-N", target],
            capture_output=True,
            text=True,
            timeout=SHARE_LISTING_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SMBSourceUnavailable("SMB share enumeration failed") from error
    if listing.returncode != 0:
        raise SMBSourceUnavailable("SMB share enumeration was refused")
    shares = _parse_shares(listing.stdout)
    if not shares:
        raise SMBSourceUnavailable("SMB server listed no non-administrative share")
    return sorted(shares)


def read_environment_credentials(
    path: Path, *, user_key: str, password_key: str
) -> _Credentials:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise SMBSourceConfigurationError("repository .env is unreadable") from error
    selected: dict[str, str] = {}
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line.removeprefix("export ").lstrip()
        key, separator, raw_value = line.partition("=")
        key = key.strip()
        if not separator or key not in {user_key, password_key}:
            continue
        if key in selected:
            raise SMBSourceConfigurationError(f"duplicate {key} in .env")
        value = raw_value.strip()
        if (
            len(value) >= 2
            and value[0] == value[-1]
            and value[0] in {"'", '"'}
        ):
            value = value[1:-1]
        if "\x00" in value or "\r" in value or "\n" in value:
            raise SMBSourceConfigurationError(f"invalid {key} in .env")
        selected[key] = value
    user = selected.get(user_key, "")
    password = selected.get(password_key, "")
    if not user or not password:
        raise SMBSourceConfigurationError(
            f"{user_key} or {password_key} is missing from .env"
        )
    return _Credentials(user, password)


def _read_credentials(path: Path) -> _Credentials:
    return read_environment_credentials(
        path, user_key="SMB_USER", password_key="SMB_PASSWORD"
    )


def _load_aggregate(registry_path: Path) -> tuple[_AggregateObject, ...]:
    try:
        registry = json.loads(registry_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SMBSourceConfigurationError("fixture registry is unreadable") from error
    if not isinstance(registry, dict) or registry.get("schemaVersion") != 2:
        raise SMBSourceConfigurationError("fixture registry must use schemaVersion 2")
    entries = registry.get("fixtures")
    if not isinstance(entries, list):
        raise SMBSourceConfigurationError("fixture registry fixtures must be a list")
    objects: list[_AggregateObject] = []
    for entry in entries:
        if not isinstance(entry, dict) or "remote-aggregate" not in entry.get(
            "regressionSets", []
        ):
            continue
        identifier = entry.get("id")
        relative_path = entry.get("deviceImportPath")
        digest = entry.get("sha256")
        if not isinstance(identifier, str) or not identifier:
            raise SMBSourceConfigurationError(
                "registered SMB aggregate object has no exact ID"
            )
        if not isinstance(relative_path, str) or not relative_path:
            raise SMBSourceConfigurationError(
                f"registered SMB aggregate object {identifier} has no path"
            )
        path = PurePosixPath(relative_path)
        if path.is_absolute() or ".." in path.parts:
            raise SMBSourceConfigurationError(
                f"registered SMB aggregate object {identifier} has an unsafe path"
            )
        if (
            not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            raise SMBSourceConfigurationError(
                f"registered SMB aggregate object {identifier} has no SHA-256"
            )
        objects.append(
            _AggregateObject(identifier, relative_path, SHA256_PREFIX + digest)
        )
    suffixes = sorted(PurePosixPath(item.relative_path).suffix.casefold() for item in objects)
    if len(objects) != 3 or suffixes != [".ass", ".mkv", ".srt"]:
        raise SMBSourceConfigurationError(
            "remote-aggregate must contain one MKV and its SRT/ASS sidecars"
        )
    if len({item.identifier for item in objects}) != len(objects):
        raise SMBSourceConfigurationError("duplicate registered SMB aggregate ID")
    return tuple(objects)


class DarwinSMBMount:
    """Use Apple's in-process SMBClient boundary so credentials never enter argv."""

    _FRAMEWORK = "/System/Library/PrivateFrameworks/SMBClient.framework/SMBClient"
    _OPTION_NO_PROMPT = 0x00000001
    _OPTION_FORCE_NEW_SESSION = 0x00000004
    _OPTION_SESSION_ONLY = 0x00010000
    _AUTHENTICATION_STATUSES = frozenset(
        {
            0xC0000064,
            0xC000006A,
            0xC000006D,
            0xC0000071,
            0xC0000224,
        }
    )

    def __init__(self) -> None:
        self._handles: dict[Path, tuple[object, ctypes.c_void_p]] = {}

    @staticmethod
    def _succeeded(status: int) -> bool:
        return status & 0xC0000000 == 0

    def _library(self) -> object:
        try:
            library = ctypes.CDLL(self._FRAMEWORK, use_errno=True)
        except OSError as error:
            raise SMBSourceUnavailable("Apple SMBClient framework is unavailable") from error
        library.SMBOpenServerEx.argtypes = (
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_uint64,
        )
        library.SMBOpenServerEx.restype = ctypes.c_uint32
        library.SMBMountShare.argtypes = (
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        )
        library.SMBMountShare.restype = ctypes.c_uint32
        library.SMBReleaseServer.argtypes = (ctypes.c_void_p,)
        library.SMBReleaseServer.restype = ctypes.c_uint32
        return library

    def shares(self, address: str, user: str, password: str) -> list[str]:
        return host_shares(address, user, password)

    def mount(
        self,
        address: str,
        share_name: str,
        user: str,
        password: str,
        mount_point: Path,
    ) -> None:
        library = self._library()
        encoded_user = quote(user, safe="")
        encoded_password = quote(password, safe="")
        encoded_share = quote(share_name, safe="")
        target = f"//{encoded_user}:{encoded_password}@{address}/{encoded_share}".encode(
            "utf-8"
        )
        handle = ctypes.c_void_p()
        options = (
            self._OPTION_NO_PROMPT
            | self._OPTION_FORCE_NEW_SESSION
            | self._OPTION_SESSION_ONLY
        )
        status = int(library.SMBOpenServerEx(target, ctypes.byref(handle), options))
        target = b""
        if not self._succeeded(status):
            if status in self._AUTHENTICATION_STATUSES:
                raise SMBCredentialsRejected("SMB credentials were rejected")
            raise SMBSourceUnavailable("SMB server connection failed")
        try:
            status = int(
                library.SMBMountShare(
                    handle,
                    None,
                    os.fsencode(mount_point),
                )
            )
            if not self._succeeded(status):
                if status in self._AUTHENTICATION_STATUSES:
                    raise SMBCredentialsRejected("SMB credentials were rejected")
                raise SMBMountRejected("SMB share mount failed")
        except Exception:
            library.SMBReleaseServer(handle)
            raise
        self._handles[mount_point] = (library, handle)

    def unmount(self, mount_point: Path) -> None:
        connection = self._handles.pop(mount_point, None)
        completed = subprocess.run(
            ["/sbin/umount", str(mount_point)],
            capture_output=True,
            text=True,
        )
        try:
            if completed.returncode != 0:
                raise SMBMountRejected("SMB share unmount failed")
        finally:
            if connection is not None:
                library, handle = connection
                library.SMBReleaseServer(handle)


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
        if temporary.exists():
            temporary.unlink()


def _runtime(path: Path) -> Mapping[str, object]:
    try:
        information = path.lstat()
        runtime = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SMBSourceConfigurationError("SMB runtime identity is unreadable") from error
    if (
        not stat.S_ISREG(information.st_mode)
        or information.st_uid != os.getuid()
        or stat.S_IMODE(information.st_mode) != 0o600
    ):
        raise SMBSourceConfigurationError(
            "SMB runtime identity must be an owner-only 0600 regular file"
        )
    if not isinstance(runtime, dict) or set(runtime) != RUNTIME_DOCUMENT_KEYS:
        raise SMBSourceConfigurationError("SMB runtime identity schema drifted")
    if not all(
        isinstance(runtime.get(key), str) and runtime[key]
        for key in (
            "address",
            "user",
            "password",
            "shareName",
            "sourceIdentity",
            "aggregateDigest",
        )
    ):
        raise SMBSourceConfigurationError("SMB runtime identity is incomplete")
    raw_address = str(runtime["address"])
    try:
        address = ipaddress.ip_address(raw_address)
    except ValueError:
        if raw_address in {"localhost", "localhost.localdomain"}:
            address = None
        elif not raw_address.endswith(".local"):
            raise SMBSourceConfigurationError("SMB runtime address is invalid")
        else:
            try:
                infos = socket.getaddrinfo(raw_address, None, socket.AF_INET, socket.SOCK_STREAM)
            except socket.gaierror as error:
                raise SMBSourceConfigurationError("SMB runtime address is invalid") from error
            has_valid = False
            for info in infos:
                candidate = info[4][0]
                try:
                    ip = ipaddress.ip_address(candidate)
                except ValueError:
                    continue
                if ip.version == 4 and not ip.is_unspecified and not ip.is_multicast and (ip.is_private or ip.is_link_local or ip.is_loopback):
                    has_valid = True
                    break
            if not has_valid:
                raise SMBSourceConfigurationError("SMB runtime address is invalid")
            address = None
    if address is not None:
        if (
            address.version != 4
            or address.is_unspecified
            or address.is_multicast
            or not (address.is_private or address.is_link_local or address.is_loopback)
        ):
            raise SMBSourceConfigurationError("SMB runtime address is invalid")
    if runtime["shareName"] != SHARE_NAME:
        raise SMBSourceConfigurationError("SMB runtime share name drifted")
    source_identity = str(runtime["sourceIdentity"])
    source_suffix = source_identity.removeprefix("smb-source:")
    if (
        not source_identity.startswith("smb-source:")
        or len(source_suffix) != 24
        or any(character not in "0123456789abcdef" for character in source_suffix)
    ):
        raise SMBSourceConfigurationError("SMB runtime source identity is invalid")
    if not _is_sha256(runtime["aggregateDigest"]):
        raise SMBSourceConfigurationError("SMB runtime aggregate digest is invalid")
    hashes = runtime.get("aggregateManifestHashes")
    paths = runtime.get("aggregatePaths")
    if not isinstance(hashes, dict) or len(hashes) != 3 or not all(
        isinstance(identifier, str)
        and identifier
        and _is_sha256(digest)
        for identifier, digest in hashes.items()
    ):
        raise SMBSourceConfigurationError("SMB runtime manifest hashes are invalid")
    if not isinstance(paths, list) or len(paths) != 3 or not all(
        isinstance(item, str)
        and item
        and not PurePosixPath(item).is_absolute()
        and ".." not in PurePosixPath(item).parts
        for item in paths
    ):
        raise SMBSourceConfigurationError("SMB runtime aggregate paths are invalid")
    suffixes = sorted(PurePosixPath(item).suffix.casefold() for item in paths)
    if suffixes != [".ass", ".mkv", ".srt"]:
        raise SMBSourceConfigurationError("SMB runtime aggregate paths drifted")
    shares = runtime.get("hostShares")
    if not isinstance(shares, list) or not shares or not all(
        isinstance(item, str) and item and not item.endswith("$") for item in shares
    ):
        raise SMBSourceConfigurationError("SMB runtime host shares are invalid")
    if SHARE_NAME not in shares or sorted(shares) != list(shares):
        raise SMBSourceConfigurationError("SMB runtime host shares drifted")
    expected_aggregate_digest = _digest(
        {"manifestHashes": hashes, "paths": paths}
    )
    if runtime["aggregateDigest"] != expected_aggregate_digest:
        raise SMBSourceConfigurationError("SMB runtime aggregate identity drifted")
    expected_source_identity = "smb-source:" + _digest(
        {
            "address": runtime["address"],
            "shareName": runtime["shareName"],
            "aggregateDigest": runtime["aggregateDigest"],
        }
    ).removeprefix(SHA256_PREFIX)[:24]
    if runtime["sourceIdentity"] != expected_source_identity:
        raise SMBSourceConfigurationError("SMB runtime source identity drifted")
    return MappingProxyType(runtime)


def _is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and value.startswith(SHA256_PREFIX)
        and len(value) == len(SHA256_PREFIX) + 64
        and all(character in "0123456789abcdef" for character in value[7:])
    )


def _reference(path: Path, key: str) -> dict[str, str]:
    return {"textFile": str(path), "textJSONKey": key}


def _sanitized_report(
    runtime_file: Path, runtime: Mapping[str, object]
) -> dict[str, object]:
    return {
        "schema": REPORT_SCHEMA,
        "check": "smb-aggregate",
        "ready": True,
        "runtimeIdentity": {
            "path": str(runtime_file),
            "mode": "0600",
            "addressReference": _reference(runtime_file, "address"),
            "userReference": _reference(runtime_file, "user"),
            "passwordReference": _reference(runtime_file, "password"),
            "shareName": runtime["shareName"],
            "sourceIdentity": runtime["sourceIdentity"],
            "aggregateDigest": runtime["aggregateDigest"],
        },
        "aggregateManifestHashes": dict(runtime["aggregateManifestHashes"]),
        "aggregatePaths": list(runtime["aggregatePaths"]),
        "hostShares": list(runtime["hostShares"]),
    }


def ensure(
    configuration: SMBSourceConfiguration,
    *,
    mount: MountBoundary | None = None,
) -> dict[str, object]:
    boundary = mount or DarwinSMBMount()
    mounted = False
    configuration.runtime_root.mkdir(parents=True, exist_ok=True)
    os.chmod(configuration.runtime_root, 0o700)
    mount_point = Path(
        tempfile.mkdtemp(prefix="mounted-share-", dir=configuration.runtime_root)
    )
    try:
        credentials = _read_credentials(configuration.environment_file)
        objects = _load_aggregate(configuration.registry_path)
        boundary.mount(
            configuration.address,
            configuration.share_name,
            credentials.user,
            credentials.password,
            mount_point,
        )
        mounted = True
        hashes: dict[str, str] = {}
        paths: list[str] = []
        mounted_root = mount_point.resolve()
        for item in objects:
            candidate = mount_point.joinpath(*PurePosixPath(item.relative_path).parts)
            resolved = candidate.resolve()
            try:
                resolved.relative_to(mounted_root)
            except ValueError as error:
                raise SMBSourceUnavailable(
                    f"registered aggregate path escaped the share: {item.identifier}"
                ) from error
            if not resolved.is_file():
                raise SMBSourceUnavailable(
                    f"registered aggregate object is missing: {item.identifier}"
                )
            observed = _file_digest(resolved)
            if observed != item.digest:
                raise SMBSourceUnavailable(
                    f"registered aggregate digest mismatch: {item.identifier}"
                )
            hashes[item.identifier] = observed
            paths.append(item.relative_path)
        aggregate_digest = _digest(
            {
                "manifestHashes": hashes,
                "paths": paths,
            }
        )
        source_digest = _digest(
            {
                "address": configuration.address,
                "shareName": configuration.share_name,
                "aggregateDigest": aggregate_digest,
            }
        )
        runtime: dict[str, object] = {
            "address": configuration.address,
            "user": credentials.user,
            "password": credentials.password,
            "shareName": configuration.share_name,
            "hostShares": boundary.shares(
                configuration.address, credentials.user, credentials.password
            ),
            "sourceIdentity": "smb-source:" + source_digest.removeprefix(SHA256_PREFIX)[:24],
            "aggregateDigest": aggregate_digest,
            "aggregateManifestHashes": hashes,
            "aggregatePaths": paths,
        }
        try:
            boundary.unmount(mount_point)
        finally:
            mounted = False
        _write_runtime(configuration.runtime_file, runtime)
        validated = _runtime(configuration.runtime_file)
        report = _sanitized_report(configuration.runtime_file, validated)
        validate_preflight_report(report, configuration.runtime_file)
        return report
    except Exception:
        try:
            configuration.runtime_file.unlink(missing_ok=True)
        except OSError:
            pass
        raise
    finally:
        if mounted:
            try:
                boundary.unmount(mount_point)
            except SMBSourceError:
                pass
        shutil.rmtree(mount_point, ignore_errors=True)


def _reject_secret_output(
    value: object,
    *,
    forbidden_exact_values: tuple[str, ...],
    secret_substrings: tuple[str, ...],
    location: str = "report",
) -> None:
    if isinstance(value, Mapping):
        for key, item in value.items():
            folded = str(key).casefold().replace("_", "").replace("-", "")
            if folded in {"user", "password", "authorization", "secretbytes"}:
                raise SMBSourceConfigurationError(
                    f"SMB preflight leaked a secret field at {location}.{key}"
                )
            _reject_secret_output(
                item,
                forbidden_exact_values=forbidden_exact_values,
                secret_substrings=secret_substrings,
                location=f"{location}.{key}",
            )
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _reject_secret_output(
                item,
                forbidden_exact_values=forbidden_exact_values,
                secret_substrings=secret_substrings,
                location=f"{location}[{index}]",
            )
    elif isinstance(value, str):
        if value in forbidden_exact_values or any(
            secret and secret in value for secret in secret_substrings
        ):
            raise SMBSourceConfigurationError(
                f"SMB preflight leaked secret bytes at {location}"
            )


def validate_preflight_report(report: object, runtime_file: Path) -> None:
    runtime = _runtime(Path(runtime_file))
    if not isinstance(report, dict):
        raise SMBSourceConfigurationError("SMB preflight report schema drifted")
    _reject_secret_output(
        report,
        forbidden_exact_values=(str(runtime["user"]),),
        secret_substrings=(str(runtime["password"]),),
    )
    if set(report) != {
        "schema",
        "check",
        "ready",
        "runtimeIdentity",
        "aggregateManifestHashes",
        "aggregatePaths",
        "hostShares",
    }:
        raise SMBSourceConfigurationError("SMB preflight report schema drifted")
    if (
        report.get("schema") != REPORT_SCHEMA
        or report.get("check") != "smb-aggregate"
        or report.get("ready") is not True
    ):
        raise SMBSourceConfigurationError("SMB preflight did not report ready")
    identity = report.get("runtimeIdentity")
    if not isinstance(identity, dict) or set(identity) != {
        "path",
        "mode",
        "addressReference",
        "userReference",
        "passwordReference",
        "shareName",
        "sourceIdentity",
        "aggregateDigest",
    }:
        raise SMBSourceConfigurationError("SMB runtime reference schema drifted")
    expected_references = {
        "addressReference": _reference(Path(runtime_file), "address"),
        "userReference": _reference(Path(runtime_file), "user"),
        "passwordReference": _reference(Path(runtime_file), "password"),
    }
    if any(identity.get(key) != value for key, value in expected_references.items()):
        raise SMBSourceConfigurationError("SMB runtime references drifted")
    expected_identity = {
        "path": str(runtime_file),
        "mode": "0600",
        "shareName": runtime["shareName"],
        "sourceIdentity": runtime["sourceIdentity"],
        "aggregateDigest": runtime["aggregateDigest"],
    }
    if any(identity.get(key) != value for key, value in expected_identity.items()):
        raise SMBSourceConfigurationError(
            "SMB preflight differs from its runtime identity"
        )
    if (
        report.get("aggregateManifestHashes")
        != runtime["aggregateManifestHashes"]
        or report.get("aggregatePaths") != runtime["aggregatePaths"]
        or report.get("hostShares") != runtime["hostShares"]
    ):
        raise SMBSourceConfigurationError(
            "SMB preflight differs from its mounted aggregate"
        )


def run_preflight(
    configuration: SMBSourceConfiguration,
    *,
    mount: MountBoundary | None = None,
) -> dict[str, object]:
    try:
        return ensure(configuration, mount=mount)
    except SMBSourceError as error:
        return {
            "schema": REPORT_SCHEMA,
            "check": "smb-aggregate",
            "ready": False,
            "reason": str(error),
        }
    except OSError:
        return {
            "schema": REPORT_SCHEMA,
            "check": "smb-aggregate",
            "ready": False,
            "reason": "SMB preflight host I/O failed",
        }


def render_report(report: Mapping[str, object]) -> str:
    return json.dumps(dict(report), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    ensure_parser = subparsers.add_parser("ensure")
    ensure_parser.add_argument("--address", required=True)
    ensure_parser.add_argument("--runtime-root", type=Path, default=DEFAULT_RUNTIME_ROOT)
    ensure_parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    ensure_parser.add_argument(
        "--environment-file", type=Path, default=DEFAULT_ENVIRONMENT_FILE
    )
    ensure_parser.add_argument("--allow-loopback", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args(argv)
    try:
        configuration = SMBSourceConfiguration(
            runtime_root=arguments.runtime_root,
            registry_path=arguments.registry,
            environment_file=arguments.environment_file,
            address=arguments.address,
            allow_loopback=arguments.allow_loopback,
        )
        report = run_preflight(configuration)
    except SMBSourceError as error:
        report = {
            "schema": REPORT_SCHEMA,
            "check": "smb-aggregate",
            "ready": False,
            "reason": str(error),
        }
    print(render_report(report), end="")
    return 0 if report.get("ready") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
