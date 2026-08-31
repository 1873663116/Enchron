#!/usr/bin/env python3
"""Own the closed HTTPS WebDAV and remote-fault regression environment."""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import formatdate
import hashlib
import hmac
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import ipaddress
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import signal
import socket
import socketserver
import ssl
import stat
import subprocess
import sys
import tempfile
import threading
import time
from typing import Mapping, cast
from urllib.parse import quote, unquote_to_bytes, urlsplit
import xml.etree.ElementTree as ElementTree


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTRY = REPOSITORY_ROOT / "Tests/Fixtures/fixture-registry.json"
DEFAULT_SOURCE_ROOT = REPOSITORY_ROOT.parent / "TestMedia"
DEFAULT_RUNTIME_ROOT = REPOSITORY_ROOT / ".build/regression-remote-source"
SHA256_PREFIX = "sha256:"
MAX_PROPFIND_BODY = 16 * 1024

AGGREGATE_FIXTURE_IDS = (
    "generated-sdr-avc-bframe-aggregate-30s-v1",
    "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
    "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
)
RECIPE_NAMES = (
    "healthy",
    "credentials-rejected",
    "missing-object",
    "access-denied",
    "corrupt-media",
    "recoverable-read-interruption",
    "finite-reconnect",
    "buffer-absorbed-interruption",
    "certificate-rotation",
    "transport-interrupted",
)
RECONNECT_BACKOFF_MILLIS = (250, 500, 1000)
BASE_PATH = "/dav/regression/"
"""The served collection, fixed for the life of the service.

The generation used to be in this path, so every activation moved the endpoint
the product had already been told about. A recipe exists to reach the session a
Scenario opened before it, and a session bound to the previous path answered
404 before any recipe branch ran, which made all four injected faults produce
one signature and left every triggered-request assertion empty. Generation
still names the request log and the manifest, is still stamped on every logged
row, and still binds the receipt, so nothing that reads a generation lost its
binding; only the address the product holds stopped moving underneath it."""
RUNTIME_DOCUMENT_KEYS = frozenset(
    {
        "address",
        "user",
        "password",
        "serviceID",
        "generation",
        "requestLogPath",
        "manifestPath",
        "certificateFingerprint",
    }
)

_SPAWNED_PROCESSES: dict[int, subprocess.Popen[bytes]] = {}
_SPAWNED_PROCESSES_LOCK = threading.Lock()


class RemoteSourceError(RuntimeError):
    pass


class RemoteSourceConfigurationError(RemoteSourceError):
    pass


class RemoteSourceUnavailable(RemoteSourceError):
    pass


def _canonical_bytes(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _digest(value: object) -> str:
    return SHA256_PREFIX + hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _file_digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            hasher.update(chunk)
    return SHA256_PREFIX + hasher.hexdigest()


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace(
        "+00:00", "Z"
    )


def _write_json(path: Path, value: object, *, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    encoded = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.", dir=path.parent
    )
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(encoded)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        os.chmod(path, mode)
    finally:
        if temporary.exists():
            temporary.unlink()


def _read_object(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RemoteSourceConfigurationError(f"cannot read JSON object at {path}: {error}") from error
    if not isinstance(value, dict):
        raise RemoteSourceConfigurationError(f"{path} must contain one JSON object")
    return value


@dataclass(frozen=True)
class ServiceConfiguration:
    runtime_root: Path
    registry_path: Path
    source_root: Path
    bind_host: str
    port: int
    allow_loopback: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "runtime_root", Path(self.runtime_root).resolve())
        object.__setattr__(self, "registry_path", Path(self.registry_path).resolve())
        object.__setattr__(self, "source_root", Path(self.source_root).resolve())

    @property
    def runtime_file(self) -> Path:
        return self.runtime_root / "runtime.json"

    @property
    def process_file(self) -> Path:
        return self.runtime_root / "process.json"

    @property
    def receipts_root(self) -> Path:
        return self.runtime_root / "receipts"

    @property
    def control_socket(self) -> Path:
        suffix = hashlib.sha256(str(self.runtime_root).encode("utf-8")).hexdigest()[:20]
        return Path(tempfile.gettempdir()) / f"enchron-remote-source-{suffix}.sock"

    def canonical(self) -> dict[str, object]:
        return {
            "runtimeRoot": str(self.runtime_root),
            "registryPath": str(self.registry_path),
            "sourceRoot": str(self.source_root),
            "bindHost": self.bind_host,
            "port": self.port,
            "allowLoopback": self.allow_loopback,
        }

    @classmethod
    def from_canonical(cls, value: Mapping[str, object]) -> ServiceConfiguration:
        try:
            runtime_root = value["runtimeRoot"]
            registry_path = value["registryPath"]
            source_root = value["sourceRoot"]
            bind_host = value["bindHost"]
            port = value["port"]
            allow_loopback = value["allowLoopback"]
        except KeyError as error:
            raise RemoteSourceConfigurationError(
                f"service configuration is missing {error.args[0]}"
            ) from error
        if not all(
            isinstance(item, str)
            for item in (runtime_root, registry_path, source_root, bind_host)
        ):
            raise RemoteSourceConfigurationError("service paths and bindHost must be strings")
        if not isinstance(port, int) or isinstance(port, bool):
            raise RemoteSourceConfigurationError("service port must be an integer")
        if not isinstance(allow_loopback, bool):
            raise RemoteSourceConfigurationError("allowLoopback must be boolean")
        return cls(
            Path(runtime_root),
            Path(registry_path),
            Path(source_root),
            bind_host,
            port,
            allow_loopback,
        )

    @property
    def digest(self) -> str:
        return _digest(self.canonical())

    def validate(self) -> None:
        try:
            address = ipaddress.ip_address(self.bind_host)
        except ValueError as error:
            raise RemoteSourceConfigurationError(
                "bind host must be one literal IPv4 LAN address"
            ) from error
        if address.version != 4:
            raise RemoteSourceConfigurationError("only a literal IPv4 LAN address is supported")
        if address.is_unspecified or address.is_multicast:
            raise RemoteSourceConfigurationError("bind host cannot be wildcard or multicast")
        if address.is_loopback and not self.allow_loopback:
            raise RemoteSourceConfigurationError(
                "loopback endpoints are test-only; choose a literal LAN address"
            )
        if not (address.is_private or address.is_link_local or address.is_loopback):
            raise RemoteSourceConfigurationError("bind host must be a literal LAN address")
        if not isinstance(self.port, int) or isinstance(self.port, bool) or not 0 <= self.port <= 65535:
            raise RemoteSourceConfigurationError("port must be an integer from 0 through 65535")
        if not self.registry_path.is_file():
            raise RemoteSourceConfigurationError(f"fixture registry is missing: {self.registry_path}")
        if not self.source_root.is_dir():
            raise RemoteSourceConfigurationError(f"fixture source root is missing: {self.source_root}")


@dataclass(frozen=True)
class FixtureObject:
    identifier: str
    name: str
    source: Path
    digest: str
    size: int
    modified_at: float

    def canonical(self) -> dict[str, object]:
        return {
            "fixtureID": self.identifier,
            "name": self.name,
            "sourcePath": str(self.source),
            "digest": self.digest,
            "size": self.size,
        }


@dataclass(frozen=True)
class FixtureManifest:
    objects: tuple[FixtureObject, ...]

    @classmethod
    def load(cls, configuration: ServiceConfiguration) -> FixtureManifest:
        configuration.validate()
        registry = _read_object(configuration.registry_path)
        if registry.get("schemaVersion") != 2:
            raise RemoteSourceConfigurationError("fixture registry must use schemaVersion 2")
        if registry.get("deviceMediaRoot") != "$WORKSPACE/TestMedia":
            raise RemoteSourceConfigurationError(
                "fixture registry deviceMediaRoot changed from $WORKSPACE/TestMedia"
            )
        entries = registry.get("fixtures")
        if not isinstance(entries, list):
            raise RemoteSourceConfigurationError("fixture registry fixtures must be a list")
        selected: dict[str, FixtureObject] = {}
        source_root = configuration.source_root.resolve()
        for raw in entries:
            if not isinstance(raw, dict) or raw.get("id") not in AGGREGATE_FIXTURE_IDS:
                continue
            identifier = raw.get("id")
            relative = raw.get("deviceImportPath")
            expected = raw.get("sha256")
            if not isinstance(identifier, str) or identifier in selected:
                raise RemoteSourceConfigurationError("aggregate fixture IDs must be unique")
            if not isinstance(relative, str) or not relative:
                raise RemoteSourceConfigurationError(f"{identifier} has no deviceImportPath")
            posix = PurePosixPath(relative)
            if posix.is_absolute() or ".." in posix.parts or "\\" in relative:
                raise RemoteSourceConfigurationError(f"{identifier} has an unsafe fixture path")
            if not isinstance(expected, str) or re.fullmatch(r"[0-9a-f]{64}", expected) is None:
                raise RemoteSourceConfigurationError(f"{identifier} has no exact SHA-256")
            source = (source_root / Path(*posix.parts)).resolve()
            if not source.is_relative_to(source_root):
                raise RemoteSourceConfigurationError(f"{identifier} resolves outside source root")
            if not source.is_file():
                raise RemoteSourceConfigurationError(f"registered fixture is missing: {identifier}")
            actual = _file_digest(source)
            registered = SHA256_PREFIX + expected
            if actual != registered:
                raise RemoteSourceConfigurationError(
                    f"registered fixture digest mismatch: {identifier}"
                )
            info = source.stat()
            selected[identifier] = FixtureObject(
                identifier,
                posix.name,
                source,
                registered,
                info.st_size,
                info.st_mtime,
            )
        missing = [item for item in AGGREGATE_FIXTURE_IDS if item not in selected]
        if missing:
            raise RemoteSourceConfigurationError(
                "fixture registry is missing required aggregate IDs: " + ", ".join(missing)
            )
        objects = tuple(selected[item] for item in AGGREGATE_FIXTURE_IDS)
        names = [item.name for item in objects]
        if len(names) != len(set(names)):
            raise RemoteSourceConfigurationError("aggregate fixture URL names must be unique")
        return cls(objects)

    @property
    def primary(self) -> FixtureObject:
        return self.objects[0]

    @property
    def by_name(self) -> dict[str, FixtureObject]:
        return {item.name: item for item in self.objects}

    @property
    def hashes(self) -> dict[str, str]:
        return {item.identifier: item.digest for item in self.objects}


@dataclass(frozen=True)
class _Response:
    status: int
    headers: Mapping[str, str]
    body: bytes = b""
    truncate_after: int | None = None
    condition: str = "none"
    triggered: bool = False
    recipe_read_ordinal: int | None = None
    expected_backoff_millis: int | None = None
    disconnect_owner: str = "none"


class _WebDAVServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], service: RemoteSourceService):
        self.service = service
        super().__init__(address, _WebDAVHandler)


class _WebDAVHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "EnchronRegressionWebDAV/1"
    sys_version = ""

    @property
    def service(self) -> RemoteSourceService:
        return cast(_WebDAVServer, self.server).service

    def setup(self) -> None:
        super().setup()
        self.service.register_connection(self.connection)

    def finish(self) -> None:
        try:
            super().finish()
        finally:
            self.service.unregister_connection(self.connection)

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_OPTIONS(self) -> None:
        self._dispatch()

    def do_PROPFIND(self) -> None:
        self._dispatch()

    def do_GET(self) -> None:
        self._dispatch()

    def do_HEAD(self) -> None:
        self._dispatch()

    def _request_body(self) -> bytes | None:
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            return b""
        if re.fullmatch(r"[0-9]+", raw_length) is None:
            return None
        length = int(raw_length)
        if length > MAX_PROPFIND_BODY:
            return None
        return self.rfile.read(length)

    def _dispatch(self) -> None:
        body = self._request_body()
        response = self.service.respond(
            self.command,
            self.path,
            {key: value for key, value in self.headers.items()},
            body,
        )
        self.send_response(response.status)
        for key, value in response.headers.items():
            self.send_header(key, value)
        self.end_headers()
        if self.command == "HEAD" or not response.body:
            return
        limit = response.truncate_after
        if limit is None:
            self.wfile.write(response.body)
            return
        try:
            self.wfile.write(response.body[:limit])
            self.wfile.flush()
        finally:
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class RemoteSourceService:
    """A deep in-process service; the controller adds cross-process idempotence."""

    def __init__(self, configuration: ServiceConfiguration, user: str, password: str):
        if not isinstance(user, str) or not user or user.strip() != user:
            raise RemoteSourceConfigurationError("service user must be one nonempty exact string")
        if not isinstance(password, str) or not password:
            raise RemoteSourceConfigurationError("service password must be nonempty")
        self.configuration = configuration
        self.manifest = FixtureManifest.load(configuration)
        self._user = user
        self._password = password
        self._lock = threading.RLock()
        self._server: _WebDAVServer | None = None
        self._server_thread: threading.Thread | None = None
        self._context: ssl.SSLContext | None = None
        self._active_connections: set[socket.socket] = set()
        self._certificate_fingerprint = ""
        self._certificate_sequence = 0
        self._generation = self._latest_persisted_generation()
        self._recipe = "healthy"
        self._request_sequence = 0
        self._recipe_counter = 0
        self._request_log = Path()
        self._manifest_path = Path()
        self._base_path = BASE_PATH
        self._endpoint_digest = ""
        self._active_receipt_id: str | None = None
        self._receipts: dict[str, dict[str, object]] = {}
        self._running = False
        self._service_id = "remote-source:" + self.configuration.digest.removeprefix(
            SHA256_PREFIX
        )[:24]
        self.configuration.runtime_root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.configuration.runtime_root, 0o700)

    def _latest_persisted_generation(self) -> int:
        latest = 0
        for directory, pattern in (
            (self.configuration.runtime_root / "request-logs", r"generation-(\d+)\.jsonl"),
            (self.configuration.runtime_root / "manifests", r"generation-(\d+)\.json"),
        ):
            if not directory.is_dir():
                continue
            for path in directory.iterdir():
                match = re.fullmatch(pattern, path.name)
                if match is not None:
                    latest = max(latest, int(match.group(1)))
        return latest

    def start(self) -> dict[str, object]:
        with self._lock:
            if self._running:
                return self._identity_locked()
            certificate, key, fingerprint = self._mint_certificate_locked()
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            context.load_cert_chain(certificate, key)
            server = _WebDAVServer(
                (self.configuration.bind_host, self.configuration.port), self
            )
            server.socket = context.wrap_socket(server.socket, server_side=True)
            self._context = context
            self._certificate_fingerprint = fingerprint
            self._server = server
            self._running = True
            self._advance_state_locked("healthy")
            thread = threading.Thread(
                target=server.serve_forever,
                name="regression-webdav",
                daemon=True,
            )
            self._server_thread = thread
            thread.start()
            return self._identity_locked()

    def status(self) -> dict[str, object]:
        with self._lock:
            if not self._running:
                raise RemoteSourceUnavailable("remote source service is not running")
            return self._identity_locked()

    def register_connection(self, connection: socket.socket) -> None:
        with self._lock:
            if self._running:
                self._active_connections.add(connection)

    def unregister_connection(self, connection: socket.socket) -> None:
        with self._lock:
            self._active_connections.discard(connection)

    def activate(self, recipe: str) -> dict[str, object]:
        if recipe not in RECIPE_NAMES:
            raise RemoteSourceConfigurationError(f"unknown closed recipe: {recipe}")
        connections_to_interrupt: tuple[socket.socket, ...] = ()
        with self._lock:
            if not self._running:
                raise RemoteSourceUnavailable("remote source service is not running")
            if self._active_receipt_id is not None:
                raise RemoteSourceError("restore the active recipe before activating another")
            prior_state = self._state_digest_locked()
            prior_certificate_fingerprint = self._certificate_fingerprint
            if recipe == "certificate-rotation":
                certificate, key, fingerprint = self._mint_certificate_locked()
                if self._context is None:
                    raise RemoteSourceUnavailable("TLS context is not running")
                self._context.load_cert_chain(certificate, key)
                self._certificate_fingerprint = fingerprint
            self._advance_state_locked(recipe)
            receipt_id = f"receipt:g-{self._generation:06d}:{recipe}"
            receipt: dict[str, object] = {
                "schema": "enchron.regression.remote-source-receipt@1",
                "receiptID": receipt_id,
                "recipe": recipe,
                "generation": self._generation,
                "endpointDigest": self._endpoint_digest,
                "activationTime": _utc_now(),
                "priorStateDigest": prior_state,
                "terminalStateDigest": self._state_digest_locked(),
                "restoredStateDigest": None,
                "logPath": str(self._request_log),
                "logDigest": _file_digest(self._request_log),
                "objectManifestHashes": self.manifest.hashes,
                "priorCertificateFingerprint": prior_certificate_fingerprint,
                "certificateFingerprint": self._certificate_fingerprint,
            }
            self._active_receipt_id = receipt_id
            self._receipts[receipt_id] = receipt
            self._write_receipt_locked(receipt)
            if recipe == "certificate-rotation":
                connections_to_interrupt = tuple(self._active_connections)
            result = dict(receipt)
        for connection in connections_to_interrupt:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        return result

    def restore(self, receipt_id: str) -> dict[str, object]:
        if not isinstance(receipt_id, str) or not receipt_id:
            raise RemoteSourceConfigurationError("receiptID must be one nonempty exact string")
        with self._lock:
            receipt = self._receipts.get(receipt_id)
            if receipt is None:
                receipt_path = self._receipt_path(receipt_id)
                if receipt_path.is_file():
                    receipt = _read_object(receipt_path)
                    self._receipts[receipt_id] = receipt
            if receipt is None:
                raise RemoteSourceConfigurationError(f"unknown recipe receipt: {receipt_id}")
            if receipt.get("restoredStateDigest") is not None:
                return dict(receipt)
            if self._active_receipt_id != receipt_id:
                raise RemoteSourceError("recipe receipt is not the active generation")
            receipt["logDigest"] = _file_digest(Path(str(receipt["logPath"])))
            self._advance_state_locked("healthy")
            receipt["restoredStateDigest"] = self._state_digest_locked()
            self._active_receipt_id = None
            self._write_receipt_locked(receipt)
            return dict(receipt)

    def stop(self) -> dict[str, object]:
        with self._lock:
            if not self._running:
                return {"stopped": True, "alreadyStopped": True}
            server = self._server
            thread = self._server_thread
            self._running = False
            self._server = None
            self._server_thread = None
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=3)
        return {"stopped": True, "alreadyStopped": False}

    def respond(
        self,
        method: str,
        raw_path: str,
        headers: Mapping[str, str],
        request_body: bytes | None,
    ) -> _Response:
        with self._lock:
            response, logged_path = self._respond_locked(
                method, raw_path, headers, request_body
            )
            self._request_sequence += 1
            requested_range = headers.get("Range")
            logged_range = (
                requested_range
                if isinstance(requested_range, str)
                and len(requested_range) <= 80
                and re.fullmatch(r"[A-Za-z0-9=\- ,]+", requested_range)
                else ("<invalid>" if requested_range is not None else None)
            )
            transmitted = len(response.body)
            if response.truncate_after is not None:
                transmitted = min(transmitted, response.truncate_after)
            entry: dict[str, object] = {
                "schema": "enchron.regression.remote-source-request@1",
                "sequence": self._request_sequence,
                "generation": self._generation,
                "recipe": self._recipe,
                "time": _utc_now(),
                "monotonicMillis": time.monotonic_ns() // 1_000_000,
                "method": method,
                "path": logged_path,
                "range": logged_range,
                "status": response.status,
                "declaredBytes": len(response.body),
                "responseBytes": 0 if method == "HEAD" else transmitted,
                "condition": response.condition,
                "triggered": response.triggered,
                "recipeReadOrdinal": response.recipe_read_ordinal,
                "expectedBackoffMillis": response.expected_backoff_millis,
                "disconnectOwner": response.disconnect_owner,
            }
            with self._request_log.open("a", encoding="utf-8") as output:
                output.write(_canonical_bytes(entry).decode("utf-8") + "\n")
                output.flush()
            return response

    def _respond_locked(
        self,
        method: str,
        raw_path: str,
        headers: Mapping[str, str],
        request_body: bytes | None,
    ) -> tuple[_Response, str]:
        if not self._running:
            return self._empty(503), "<rejected>"
        target_kind, target_name, logged_path = self._parse_target_locked(raw_path)
        expected = "Basic " + base64.b64encode(
            f"{self._user}:{self._password}".encode("utf-8")
        ).decode("ascii")
        supplied = headers.get("Authorization", "")
        authenticated = hmac.compare_digest(supplied, expected)
        if not authenticated or self._recipe == "credentials-rejected":
            return (
                self._empty(
                    401,
                    {"WWW-Authenticate": 'Basic realm="Enchron Regression"'},
                    condition="authenticated-request",
                    triggered=self._recipe == "credentials-rejected" and authenticated,
                ),
                logged_path,
            )
        if target_kind == "rejected":
            return self._empty(400, condition="sanitized-path"), logged_path
        if target_kind == "outside":
            return self._empty(404, condition="served-collection-path"), logged_path
        if method == "OPTIONS":
            return (
                self._empty(
                    200,
                    {"Allow": "OPTIONS, PROPFIND, GET, HEAD", "DAV": "1"},
                ),
                logged_path,
            )
        if method == "PROPFIND":
            return self._propfind_locked(
                target_kind, target_name, headers, request_body
            ), logged_path
        if method not in {"GET", "HEAD"}:
            return self._empty(405, {"Allow": "OPTIONS, PROPFIND, GET, HEAD"}), logged_path
        if target_kind != "object" or target_name is None:
            return self._empty(404), logged_path
        item = self.manifest.by_name.get(target_name)
        if item is None:
            return self._empty(404), logged_path
        is_primary = item.identifier == self.manifest.primary.identifier
        if is_primary and self._recipe == "missing-object":
            return self._empty(404, condition="primary-object-read", triggered=True), logged_path
        if is_primary and self._recipe == "access-denied":
            return self._empty(403, condition="primary-object-read", triggered=True), logged_path
        if is_primary and self._recipe == "transport-interrupted":
            return (
                self._empty(
                    503,
                    {"Retry-After": "0"},
                    condition="primary-object-read",
                    triggered=True,
                ),
                logged_path,
            )
        selection = self._select_range(headers.get("Range"), item.size)
        if selection is None:
            return (
                self._empty(
                    416,
                    {"Content-Range": f"bytes */{item.size}"},
                    condition="valid-byte-range",
                ),
                logged_path,
            )
        start, end, ranged = selection
        response_headers: dict[str, str] = {
            "Accept-Ranges": "bytes",
            "Content-Type": mimetypes.guess_type(item.name)[0] or "application/octet-stream",
            "Content-Length": str(end - start + 1),
            "Last-Modified": formatdate(item.modified_at, usegmt=True),
            "ETag": f'"{item.digest.removeprefix(SHA256_PREFIX)}"',
        }
        status = 206 if ranged else 200
        if ranged:
            response_headers["Content-Range"] = f"bytes {start}-{end}/{item.size}"
        if method == "HEAD":
            return _Response(status, response_headers), logged_path

        if is_primary and ranged and self._recipe == "finite-reconnect":
            self._recipe_counter += 1
            ordinal = self._recipe_counter
            if ordinal <= len(RECONNECT_BACKOFF_MILLIS):
                return (
                    self._empty(
                        503,
                        {"Retry-After": "0"},
                        condition="first-three-ranged-reads",
                        triggered=True,
                        recipe_read_ordinal=ordinal,
                        expected_backoff_millis=RECONNECT_BACKOFF_MILLIS[
                            ordinal - 1
                        ],
                        disconnect_owner="remote-source-recipe",
                    ),
                    logged_path,
                )
            finite_read_ordinal = ordinal
        else:
            finite_read_ordinal = None
        if is_primary and ranged and self._recipe == "buffer-absorbed-interruption":
            self._recipe_counter += 1
            if self._recipe_counter == 2:
                return (
                    self._empty(
                        503,
                        {"Retry-After": "0"},
                        condition="ranged-read-after-buffer-fill",
                        triggered=True,
                    ),
                    logged_path,
                )

        with item.source.open("rb") as source:
            source.seek(start)
            payload = source.read(end - start + 1)
        if len(payload) != end - start + 1:
            return self._empty(500, condition="registered-object-stability"), logged_path
        condition = "none"
        triggered = False
        if is_primary and self._recipe == "corrupt-media":
            payload = bytes(byte ^ 0x01 for byte in payload)
            condition = "primary-object-read"
            triggered = True
        if (
            is_primary
            and ranged
            and self._recipe == "recoverable-read-interruption"
            and self._recipe_counter == 0
        ):
            self._recipe_counter = 1
            return (
                _Response(
                    status,
                    response_headers,
                    payload,
                    truncate_after=max(1, len(payload) // 2),
                    condition="first-ranged-read",
                    triggered=True,
                    recipe_read_ordinal=1,
                    expected_backoff_millis=RECONNECT_BACKOFF_MILLIS[0],
                    disconnect_owner="remote-source-recipe",
                ),
                logged_path,
            )
        return _Response(
            status,
            response_headers,
            payload,
            condition=condition,
            triggered=triggered,
            recipe_read_ordinal=finite_read_ordinal,
        ), logged_path

    def _propfind_locked(
        self,
        target_kind: str,
        target_name: str | None,
        headers: Mapping[str, str],
        request_body: bytes | None,
    ) -> _Response:
        if headers.get("Transfer-Encoding") is not None:
            return self._empty(400, condition="bounded-propfind-body")
        if request_body is None:
            return self._empty(400, condition="bounded-propfind-body")
        depth = headers.get("Depth", "1")
        if depth not in {"0", "1"}:
            return self._empty(403, condition="bounded-propfind-depth")
        if request_body:
            upper = request_body.upper()
            if b"<!DOCTYPE" in upper or b"<!ENTITY" in upper:
                return self._empty(400, condition="sanitized-propfind-xml")
            try:
                root = ElementTree.fromstring(request_body)
            except ElementTree.ParseError:
                return self._empty(400, condition="sanitized-propfind-xml")
            if root.tag.split("}")[-1].lower() != "propfind":
                return self._empty(400, condition="sanitized-propfind-xml")
        if target_kind == "object" and target_name not in self.manifest.by_name:
            return self._empty(404)

        ElementTree.register_namespace("d", "DAV:")
        multistatus = ElementTree.Element("{DAV:}multistatus")
        if target_kind == "root":
            self._append_propfind_response(multistatus, None)
            if depth == "1":
                for item in self.manifest.objects:
                    if (
                        self._recipe == "missing-object"
                        and item.identifier == self.manifest.primary.identifier
                    ):
                        continue
                    self._append_propfind_response(multistatus, item)
        else:
            self._append_propfind_response(
                multistatus, self.manifest.by_name[str(target_name)]
            )
        payload = ElementTree.tostring(
            multistatus, encoding="utf-8", xml_declaration=True
        )
        return _Response(
            207,
            {
                "Content-Type": "application/xml; charset=utf-8",
                "Content-Length": str(len(payload)),
                "DAV": "1",
            },
            payload,
        )

    def _append_propfind_response(
        self, multistatus: ElementTree.Element, item: FixtureObject | None
    ) -> None:
        response = ElementTree.SubElement(multistatus, "{DAV:}response")
        href = ElementTree.SubElement(response, "{DAV:}href")
        href.text = self._base_path if item is None else self._base_path + quote(item.name)
        propstat = ElementTree.SubElement(response, "{DAV:}propstat")
        prop = ElementTree.SubElement(propstat, "{DAV:}prop")
        resource_type = ElementTree.SubElement(prop, "{DAV:}resourcetype")
        if item is None:
            ElementTree.SubElement(resource_type, "{DAV:}collection")
        else:
            length = ElementTree.SubElement(prop, "{DAV:}getcontentlength")
            length.text = str(item.size)
            modified = ElementTree.SubElement(prop, "{DAV:}getlastmodified")
            modified.text = formatdate(item.modified_at, usegmt=True)
            etag = ElementTree.SubElement(prop, "{DAV:}getetag")
            etag.text = f'"{item.digest.removeprefix(SHA256_PREFIX)}"'
        status = ElementTree.SubElement(propstat, "{DAV:}status")
        status.text = "HTTP/1.1 200 OK"

    def _parse_target_locked(self, raw_path: str) -> tuple[str, str | None, str]:
        split = urlsplit(raw_path)
        if split.query or split.fragment or re.search(r"%(?![0-9A-Fa-f]{2})", split.path):
            return "rejected", None, "<rejected>"
        try:
            decoded = unquote_to_bytes(split.path).decode("utf-8", errors="strict")
        except UnicodeDecodeError:
            return "rejected", None, "<rejected>"
        if "\x00" in decoded or "\\" in decoded:
            return "rejected", None, "<rejected>"
        parts = PurePosixPath(decoded).parts
        if any(part in {".", ".."} for part in parts):
            return "rejected", None, "<rejected>"
        if not decoded.startswith(self._base_path):
            return "outside", None, "<outside-collection>"
        relative = decoded[len(self._base_path) :]
        if not relative:
            return "root", None, self._base_path
        if "/" in relative:
            return "rejected", None, "<rejected>"
        return "object", relative, self._base_path + quote(relative)

    @staticmethod
    def _select_range(value: str | None, size: int) -> tuple[int, int, bool] | None:
        if value is None:
            return 0, size - 1, False
        match = re.fullmatch(r"bytes=(\d*)-(\d*)", value.strip())
        if match is None:
            return None
        first, last = match.groups()
        if not first and not last:
            return None
        if first:
            start = int(first)
            end = size - 1 if not last else min(int(last), size - 1)
        else:
            suffix = int(last)
            if suffix == 0:
                return None
            start = max(0, size - suffix)
            end = size - 1
        if start >= size or start > end:
            return None
        return start, end, True

    @staticmethod
    def _empty(
        status: int,
        headers: Mapping[str, str] | None = None,
        *,
        condition: str = "none",
        triggered: bool = False,
        recipe_read_ordinal: int | None = None,
        expected_backoff_millis: int | None = None,
        disconnect_owner: str = "none",
    ) -> _Response:
        combined = {"Content-Length": "0", **dict(headers or {})}
        return _Response(
            status,
            combined,
            condition=condition,
            triggered=triggered,
            recipe_read_ordinal=recipe_read_ordinal,
            expected_backoff_millis=expected_backoff_millis,
            disconnect_owner=disconnect_owner,
        )

    def _mint_certificate_locked(self) -> tuple[Path, Path, str]:
        openssl = shutil.which("openssl")
        if openssl is None:
            raise RemoteSourceConfigurationError(
                "openssl is required at the certificate-generation boundary"
            )
        self._certificate_sequence += 1
        directory = self.configuration.runtime_root / "certificates"
        directory.mkdir(parents=True, exist_ok=True)
        os.chmod(directory, 0o700)
        nonce = f"{os.getpid()}-{time.time_ns()}-{self._certificate_sequence}"
        certificate = directory / f"certificate-{nonce}.pem"
        private_key = directory / f"private-key-{nonce}.pem"
        command = [
            openssl,
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-sha256",
            "-nodes",
            "-days",
            "7",
            "-keyout",
            str(private_key),
            "-out",
            str(certificate),
            "-subj",
            "/CN=Enchron Regression Remote Source",
            "-addext",
            f"subjectAltName=IP:{self.configuration.bind_host}",
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=15)
        if result.returncode != 0:
            raise RemoteSourceConfigurationError(
                "openssl could not mint the regression HTTPS certificate"
            )
        os.chmod(private_key, 0o600)
        os.chmod(certificate, 0o644)
        try:
            der = ssl.PEM_cert_to_DER_cert(certificate.read_text(encoding="ascii"))
        except (OSError, ValueError) as error:
            raise RemoteSourceConfigurationError(
                "generated HTTPS certificate cannot be decoded"
            ) from error
        fingerprint = SHA256_PREFIX + hashlib.sha256(der).hexdigest()
        return certificate, private_key, fingerprint

    def _advance_state_locked(self, recipe: str) -> None:
        self._generation += 1
        self._recipe = recipe
        self._request_sequence = 0
        self._recipe_counter = 0
        logs = self.configuration.runtime_root / "request-logs"
        logs.mkdir(parents=True, exist_ok=True)
        os.chmod(logs, 0o700)
        self._request_log = logs / f"generation-{self._generation:06d}.jsonl"
        self._request_log.touch(exist_ok=False)
        os.chmod(self._request_log, 0o644)
        manifests = self.configuration.runtime_root / "manifests"
        self._manifest_path = manifests / f"generation-{self._generation:06d}.json"
        manifest_document = {
            "schema": "enchron.regression.remote-source-manifest@1",
            "generation": self._generation,
            "objects": [item.canonical() for item in self.manifest.objects],
        }
        _write_json(self._manifest_path, manifest_document, mode=0o644)
        self._endpoint_digest = _digest(
            {
                "serviceID": self._service_id,
                "host": self.configuration.bind_host,
                "port": self._actual_port_locked(),
                "path": self._base_path,
                "certificateFingerprint": self._certificate_fingerprint,
            }
        )
        self._write_runtime_locked()

    def _actual_port_locked(self) -> int:
        if self._server is None:
            raise RemoteSourceUnavailable("remote source endpoint is not bound")
        return int(self._server.server_address[1])

    def _identity_locked(self) -> dict[str, object]:
        return {
            "schema": "enchron.regression.remote-source-identity@1",
            "serviceID": self._service_id,
            "configDigest": self.configuration.digest,
            "pid": os.getpid(),
            "address": f"https://{self.configuration.bind_host}:{self._actual_port_locked()}{self._base_path}",
            "generation": self._generation,
            "recipe": self._recipe,
            "endpointDigest": self._endpoint_digest,
            "certificateFingerprint": self._certificate_fingerprint,
            "requestLogPath": str(self._request_log),
            "manifestPath": str(self._manifest_path),
            "runtimePath": str(self.configuration.runtime_file),
        }

    def _state_digest_locked(self) -> str:
        return _digest(
            {
                "serviceID": self._service_id,
                "generation": self._generation,
                "recipe": self._recipe,
                "endpointDigest": self._endpoint_digest,
                "certificateFingerprint": self._certificate_fingerprint,
                "objectManifestHashes": self.manifest.hashes,
            }
        )

    def _write_runtime_locked(self) -> None:
        runtime = {
            "address": f"https://{self.configuration.bind_host}:{self._actual_port_locked()}{self._base_path}",
            "user": self._user,
            "password": self._password,
            "serviceID": self._service_id,
            "generation": self._generation,
            "requestLogPath": str(self._request_log),
            "manifestPath": str(self._manifest_path),
            "certificateFingerprint": self._certificate_fingerprint,
        }
        if set(runtime) != RUNTIME_DOCUMENT_KEYS:
            raise AssertionError("runtime document key contract drifted")
        _write_json(self.configuration.runtime_file, runtime, mode=0o600)

    def _receipt_path(self, receipt_id: str) -> Path:
        safe = hashlib.sha256(receipt_id.encode("utf-8")).hexdigest()
        return self.configuration.receipts_root / f"{safe}.json"

    def _write_receipt_locked(self, receipt: Mapping[str, object]) -> None:
        _write_json(
            self._receipt_path(str(receipt["receiptID"])), dict(receipt), mode=0o644
        )


class _ControlServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(self, path: str, daemon: _RemoteSourceDaemon):
        self.daemon_runtime = daemon
        super().__init__(path, _ControlHandler)


class _ControlHandler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        line = self.rfile.readline(1024 * 1024 + 1)
        if not line or len(line) > 1024 * 1024:
            response: dict[str, object] = {"ok": False, "error": "invalid control request"}
        else:
            try:
                payload = json.loads(line)
                if not isinstance(payload, dict):
                    raise ValueError
                response = cast(_ControlServer, self.server).daemon_runtime.dispatch(
                    payload
                )
            except (json.JSONDecodeError, ValueError):
                response = {"ok": False, "error": "invalid control request"}
        self.wfile.write(_canonical_bytes(response) + b"\n")
        self.wfile.flush()


class _RemoteSourceDaemon:
    def __init__(
        self, configuration: ServiceConfiguration, user: str, password: str
    ) -> None:
        self.configuration = configuration
        self.service = RemoteSourceService(configuration, user, password)
        self.stop_event = threading.Event()
        self.control_server: _ControlServer | None = None

    def dispatch(self, payload: Mapping[str, object]) -> dict[str, object]:
        command = payload.get("command")
        try:
            if command == "status":
                result: object = self.service.status()
            elif command == "activate" and set(payload) == {"command", "recipe"}:
                recipe = payload.get("recipe")
                if not isinstance(recipe, str):
                    raise RemoteSourceConfigurationError("recipe must be a string")
                result = self.service.activate(recipe)
            elif command == "restore" and set(payload) == {"command", "receiptID"}:
                receipt_id = payload.get("receiptID")
                if not isinstance(receipt_id, str):
                    raise RemoteSourceConfigurationError("receiptID must be a string")
                result = self.service.restore(receipt_id)
            elif command == "stop" and set(payload) == {"command"}:
                result = {"stopped": True, "alreadyStopped": False}
                threading.Timer(0.05, self.stop_event.set).start()
            else:
                raise RemoteSourceConfigurationError("unknown closed control command")
            return {"ok": True, "result": result}
        except RemoteSourceError as error:
            return {"ok": False, "error": str(error)}

    def run(self) -> int:
        socket_path = self.configuration.control_socket
        _unlink_owned_socket(socket_path)
        identity = self.service.start()
        server = _ControlServer(str(socket_path), self)
        self.control_server = server
        os.chmod(socket_path, 0o600)
        control_thread = threading.Thread(
            target=server.serve_forever,
            name="regression-remote-control",
            daemon=True,
        )
        control_thread.start()
        self._write_process("running", identity)
        self.stop_event.wait()
        server.shutdown()
        server.server_close()
        control_thread.join(timeout=3)
        _unlink_owned_socket(socket_path)
        self.service.stop()
        self._write_process("stopped", None)
        return 0

    def _write_process(
        self, status_value: str, identity: Mapping[str, object] | None
    ) -> None:
        document: dict[str, object] = {
            "schema": "enchron.regression.remote-source-process@1",
            "status": status_value,
            "pid": os.getpid(),
            "configDigest": self.configuration.digest,
            "controlSocketPath": str(self.configuration.control_socket),
        }
        if identity is not None:
            document["identity"] = dict(identity)
        _write_json(self.configuration.process_file, document, mode=0o644)


def _unlink_owned_socket(path: Path) -> None:
    try:
        information = path.lstat()
    except FileNotFoundError:
        return
    if information.st_uid != os.getuid() or not stat.S_ISSOCK(information.st_mode):
        raise RemoteSourceUnavailable(f"refusing to replace non-owned control path: {path}")
    path.unlink()


def _pid_alive(pid: object) -> bool:
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


class RemoteSourceController:
    """Idempotent process boundary for the closed service lifecycle and recipes."""

    def __init__(self, configuration: ServiceConfiguration):
        self.configuration = configuration

    def ensure(self) -> dict[str, object]:
        self.configuration.validate()
        FixtureManifest.load(self.configuration)
        try:
            existing = self.status()
        except RemoteSourceUnavailable:
            existing = None
        if existing is not None:
            if existing.get("configDigest") != self.configuration.digest:
                raise RemoteSourceUnavailable(
                    "running remote source has a different configuration digest"
                )
            self._validate_runtime_file(existing)
            return existing

        if self.configuration.process_file.is_file():
            process = _read_object(self.configuration.process_file)
            if process.get("status") == "running" and _pid_alive(process.get("pid")):
                raise RemoteSourceUnavailable(
                    "remote source process is alive but its control socket is unavailable"
                )
        _unlink_owned_socket(self.configuration.control_socket)
        self.configuration.runtime_root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.configuration.runtime_root, 0o700)
        user, password = self._credentials()
        launch = {
            "configuration": self.configuration.canonical(),
            "user": user,
            "password": password,
        }
        stdout_path = self.configuration.runtime_root / "daemon.stdout.log"
        stderr_path = self.configuration.runtime_root / "daemon.stderr.log"
        with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
            process = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "_serve"],
                stdin=subprocess.PIPE,
                stdout=stdout,
                stderr=stderr,
                start_new_session=True,
            )
            if process.stdin is None:
                raise RemoteSourceUnavailable("cannot open daemon launch channel")
            process.stdin.write(_canonical_bytes(launch) + b"\n")
            process.stdin.close()
        with _SPAWNED_PROCESSES_LOCK:
            _SPAWNED_PROCESSES[process.pid] = process
        deadline = time.monotonic() + 10
        last_error: RemoteSourceError | None = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                with _SPAWNED_PROCESSES_LOCK:
                    _SPAWNED_PROCESSES.pop(process.pid, None)
                process.wait()
                raise RemoteSourceUnavailable(
                    f"remote source daemon exited during startup; inspect {stderr_path}"
                )
            try:
                status_value = self.status()
            except RemoteSourceError as error:
                last_error = error
                time.sleep(0.05)
                continue
            if status_value.get("configDigest") != self.configuration.digest:
                raise RemoteSourceUnavailable("remote source daemon reported the wrong configuration")
            self._validate_runtime_file(status_value)
            return status_value
        raise RemoteSourceUnavailable(
            f"remote source daemon did not become ready: {last_error or 'control timeout'}"
        )

    def status(self) -> dict[str, object]:
        return self._request({"command": "status"})

    def activate(self, recipe: str) -> dict[str, object]:
        if recipe not in RECIPE_NAMES:
            raise RemoteSourceConfigurationError(f"unknown closed recipe: {recipe}")
        return self._request({"command": "activate", "recipe": recipe})

    def restore(self, receipt_id: str) -> dict[str, object]:
        return self._request({"command": "restore", "receiptID": receipt_id})

    def receipt(self, receipt_id: str) -> dict[str, object]:
        match = re.fullmatch(r"receipt:g-([0-9]{6}):([a-z][a-z-]*)", receipt_id)
        if match is None or match.group(2) not in RECIPE_NAMES:
            raise RemoteSourceConfigurationError("recipe receipt ID is invalid")
        safe = hashlib.sha256(receipt_id.encode("utf-8")).hexdigest()
        path = self.configuration.receipts_root / f"{safe}.json"
        if not path.is_file():
            raise RemoteSourceConfigurationError(f"unknown recipe receipt: {receipt_id}")
        receipt = _read_object(path)
        if (
            receipt.get("schema") != "enchron.regression.remote-source-receipt@1"
            or receipt.get("receiptID") != receipt_id
            or receipt.get("recipe") != match.group(2)
            or receipt.get("generation") != int(match.group(1))
        ):
            raise RemoteSourceConfigurationError("recipe receipt identity drifted")
        log_path = Path(str(receipt.get("logPath", ""))).resolve()
        log_root = (self.configuration.runtime_root / "request-logs").resolve()
        if not log_path.is_relative_to(log_root) or not log_path.is_file():
            raise RemoteSourceConfigurationError("recipe receipt log binding is invalid")
        if receipt.get("restoredStateDigest") is not None:
            expected = _file_digest(log_path)
            if receipt.get("logDigest") != expected:
                raise RemoteSourceConfigurationError("recipe receipt log digest drifted")
        return receipt

    def stop(self) -> dict[str, object]:
        try:
            result = self._request({"command": "stop"})
        except RemoteSourceUnavailable:
            result = {"stopped": True, "alreadyStopped": True}
        self._wait_for_stopped()
        return result

    def _wait_for_stopped(self) -> None:
        deadline = time.monotonic() + 5
        pid: int | None = None
        while time.monotonic() < deadline:
            if self.configuration.process_file.is_file():
                process_state = _read_object(self.configuration.process_file)
                raw_pid = process_state.get("pid")
                pid = raw_pid if isinstance(raw_pid, int) else None
                if process_state.get("status") == "stopped" or not _pid_alive(pid):
                    break
            elif not self.configuration.control_socket.exists():
                break
            time.sleep(0.05)
        else:
            raise RemoteSourceUnavailable("remote source daemon did not stop cleanly")
        if pid is not None:
            with _SPAWNED_PROCESSES_LOCK:
                child = _SPAWNED_PROCESSES.pop(pid, None)
            if child is not None:
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired as error:
                    with _SPAWNED_PROCESSES_LOCK:
                        _SPAWNED_PROCESSES[pid] = child
                    raise RemoteSourceUnavailable(
                        "remote source daemon remained alive after stop receipt"
                    ) from error

    def _request(self, payload: Mapping[str, object]) -> dict[str, object]:
        path = self.configuration.control_socket
        if not path.exists():
            raise RemoteSourceUnavailable("remote source control socket is unavailable")
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(3)
        try:
            client.connect(str(path))
            client.sendall(_canonical_bytes(dict(payload)) + b"\n")
            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = client.recv(64 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
                total += len(chunk)
                if total > 1024 * 1024:
                    raise RemoteSourceUnavailable("remote source control response is oversized")
                if b"\n" in chunk:
                    break
        except (OSError, TimeoutError) as error:
            raise RemoteSourceUnavailable("remote source control socket is unavailable") from error
        finally:
            client.close()
        try:
            response = json.loads(b"".join(chunks).splitlines()[0])
        except (IndexError, json.JSONDecodeError) as error:
            raise RemoteSourceUnavailable("remote source control response is invalid") from error
        if not isinstance(response, dict) or not isinstance(response.get("ok"), bool):
            raise RemoteSourceUnavailable("remote source control response has no verdict")
        if not response["ok"]:
            reason = response.get("error")
            raise RemoteSourceError(str(reason) if isinstance(reason, str) else "control request failed")
        result = response.get("result")
        if not isinstance(result, dict):
            raise RemoteSourceUnavailable("remote source control result must be an object")
        return result

    def _credentials(self) -> tuple[str, str]:
        path = self.configuration.runtime_file
        if path.is_file():
            try:
                runtime = _read_object(path)
            except RemoteSourceConfigurationError:
                runtime = {}
            user = runtime.get("user")
            password = runtime.get("password")
            service_id = runtime.get("serviceID")
            expected_id = "remote-source:" + self.configuration.digest.removeprefix(
                SHA256_PREFIX
            )[:24]
            if (
                set(runtime) == RUNTIME_DOCUMENT_KEYS
                and isinstance(user, str)
                and user
                and isinstance(password, str)
                and password
                and service_id == expected_id
            ):
                return user, password
        return "enchron-regression", secrets.token_urlsafe(32)

    def _validate_runtime_file(self, identity: Mapping[str, object]) -> None:
        path = self.configuration.runtime_file
        try:
            information = path.stat()
        except OSError as error:
            raise RemoteSourceUnavailable("remote source runtime identity is missing") from error
        if (
            not stat.S_ISREG(information.st_mode)
            or information.st_uid != os.getuid()
            or stat.S_IMODE(information.st_mode) != 0o600
        ):
            raise RemoteSourceUnavailable(
                "remote source runtime identity must be an owner-only 0600 regular file"
            )
        runtime = _read_object(path)
        if set(runtime) != RUNTIME_DOCUMENT_KEYS:
            raise RemoteSourceUnavailable("remote source runtime identity schema drifted")
        bindings = {
            "address": "address",
            "serviceID": "serviceID",
            "generation": "generation",
            "requestLogPath": "requestLogPath",
            "manifestPath": "manifestPath",
            "certificateFingerprint": "certificateFingerprint",
        }
        if any(runtime[key] != identity[value] for key, value in bindings.items()):
            raise RemoteSourceUnavailable(
                "remote source runtime identity does not match the running generation"
            )
        if not all(
            isinstance(runtime.get(key), str) and runtime[key]
            for key in ("user", "password")
        ):
            raise RemoteSourceUnavailable("remote source runtime UI inputs are incomplete")


def _serve_from_stdin() -> int:
    line = sys.stdin.buffer.readline(1024 * 1024 + 1)
    if not line or len(line) > 1024 * 1024:
        print("remote source daemon launch document is invalid", file=sys.stderr)
        return 2
    try:
        launch = json.loads(line)
        configuration_value = launch["configuration"]
        user = launch["user"]
        password = launch["password"]
        if not isinstance(configuration_value, dict):
            raise TypeError
        if not isinstance(user, str) or not isinstance(password, str):
            raise TypeError
        configuration = ServiceConfiguration.from_canonical(configuration_value)
        daemon = _RemoteSourceDaemon(configuration, user, password)
    except (KeyError, TypeError, json.JSONDecodeError, RemoteSourceError) as error:
        print(f"remote source daemon launch rejected: {error}", file=sys.stderr)
        return 2

    def request_stop(signum: int, frame: object) -> None:
        daemon.stop_event.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    try:
        return daemon.run()
    except RemoteSourceError as error:
        print(f"remote source daemon failed: {error}", file=sys.stderr)
        return 1


def _configuration_from_arguments(arguments: argparse.Namespace) -> ServiceConfiguration:
    return ServiceConfiguration(
        arguments.runtime_root,
        arguments.registry,
        arguments.source_root,
        arguments.bind_host,
        arguments.port,
        arguments.allow_loopback,
    )


def _add_configuration_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--runtime-root", type=Path, default=DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--source-root", type=Path, default=DEFAULT_SOURCE_ROOT)
    parser.add_argument("--bind-host", required=True)
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--allow-loopback", action="store_true", help=argparse.SUPPRESS)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("ensure", "status", "stop"):
        child = subparsers.add_parser(name)
        _add_configuration_arguments(child)
    activate = subparsers.add_parser("activate")
    _add_configuration_arguments(activate)
    activate.add_argument("recipe", choices=RECIPE_NAMES)
    restore = subparsers.add_parser("restore")
    _add_configuration_arguments(restore)
    restore.add_argument("receipt_id")
    subparsers.add_parser("_serve", help=argparse.SUPPRESS)
    arguments = parser.parse_args(argv)
    if arguments.command == "_serve":
        return _serve_from_stdin()
    try:
        controller = RemoteSourceController(_configuration_from_arguments(arguments))
        if arguments.command == "ensure":
            result = controller.ensure()
        elif arguments.command == "status":
            result = controller.status()
        elif arguments.command == "activate":
            result = controller.activate(arguments.recipe)
        elif arguments.command == "restore":
            result = controller.restore(arguments.receipt_id)
        elif arguments.command == "stop":
            result = controller.stop()
        else:
            raise AssertionError("unreachable command")
    except RemoteSourceError as error:
        print(json.dumps({"ready": False, "reason": str(error)}, sort_keys=True))
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
