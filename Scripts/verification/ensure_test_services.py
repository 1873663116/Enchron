#!/usr/bin/env python3

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
import hashlib
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import socket
import ssl
import stat
import subprocess
import sys
import tempfile
import time
from typing import Callable, Mapping
from urllib.error import URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


if __package__:
    from . import regression_emby_source as emby
    from . import regression_remote_source as remote
    from . import regression_smb_source as smb
else:
    import regression_emby_source as emby
    import regression_remote_source as remote
    import regression_smb_source as smb


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RECEIPT_NAME = "ensure-receipt.json"
RECEIPT_SCHEMA = "enchron.verification.test-service-receipt@1"
SUMMARY_SCHEMA = "enchron.verification.test-services@1"
EMBY_APP = "EmbyServer"
EMBY_PORT = 8096
WEBDAV_PORT = 8443
SMB_PORT = 445
EMBY_START_SECONDS = 30
INET_LINE = re.compile(r"\binet (\d+\.\d+\.\d+\.\d+)\b")


@dataclass(frozen=True)
class Started:
    address: str
    identity: str
    observed: str


@dataclass(frozen=True)
class ServiceHooks:
    probe: Callable[[str], str | None]
    lan_hosts: Callable[[], tuple[str, ...]]
    mdns_hosts: Callable[[], tuple[str, ...]]
    port_open: Callable[[str, int], bool]
    start: Callable[[], Started | None]
    rewrite: Callable[[str], None]


@dataclass(frozen=True)
class ServiceSpec:
    name: str
    identity: str
    expected: str
    recorded_address: str | None
    receipt_file: Path
    port: int
    scheme: str
    path: str
    hooks: ServiceHooks


def branch_identity_mismatch(observed: str | None, expected: str) -> bool:
    return observed is not None and observed != expected


def branch_loopback(address: str) -> bool:
    return host_is_loopback(address)


def branch_no_candidate(observed: str | None) -> bool:
    return observed is None


def branch_start_failed(started: object | None) -> bool:
    return started is None


def host_is_loopback(address: str) -> bool:
    host = endpoint_host(address)
    if host in {"localhost", "localhost.localdomain"}:
        return True
    try:
        parsed = ipaddress.ip_address(host)
    except ValueError:
        return False
    return parsed.is_loopback


def endpoint_host(address: str) -> str:
    if "://" in address:
        return urlsplit(address).hostname or ""
    return address.split("%", 1)[0]


def format_address(scheme: str, host: str, port: int, path: str) -> str:
    if not scheme:
        return host
    origin = f"{scheme}://{host}:{port}"
    if not path:
        return origin
    if not path.startswith("/"):
        path = "/" + path
    return origin + path


def _write_json(path: Path, value: Mapping[str, object], *, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(dict(value), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
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


def port_open(host: str, port: int, timeout: float = 0.25) -> bool:
    try:
        socket.create_connection((host, port), timeout=timeout).close()
    except OSError:
        return False
    return True


def lan_ipv4_hosts() -> tuple[str, ...]:
    hosts: list[str] = []
    seen: set[str] = set()
    for interface in ("en0", "en1"):
        completed = subprocess.run(
            ["/usr/sbin/ipconfig", "getifaddr", interface],
            capture_output=True,
            text=True,
        )
        candidate = completed.stdout.strip()
        if completed.returncode != 0 or not candidate:
            continue
        try:
            ip = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if (
            ip.version != 4
            or ip.is_loopback
            or ip.is_unspecified
            or ip.is_multicast
            or not (ip.is_private or ip.is_link_local)
        ):
            continue
        network = ipaddress.ip_network(f"{ip}/24", strict=False)
        key = str(network)
        if key in seen:
            continue
        seen.add(key)
        hosts.extend(str(item) for item in network.hosts())
    return tuple(hosts)


def primary_lan_ipv4() -> str | None:
    for interface in ("en0", "en1"):
        completed = subprocess.run(
            ["/usr/sbin/ipconfig", "getifaddr", interface],
            capture_output=True,
            text=True,
        )
        candidate = completed.stdout.strip()
        if completed.returncode == 0 and candidate and not host_is_loopback(candidate):
            return candidate
    completed = subprocess.run(
        ["/sbin/ifconfig"], capture_output=True, text=True, timeout=5
    )
    for match in INET_LINE.finditer(completed.stdout):
        candidate = match.group(1)
        if candidate and not host_is_loopback(candidate):
            return candidate
    return None


def mdns_hostnames() -> tuple[str, ...]:
    names: list[str] = []
    completed = subprocess.run(
        ["/usr/sbin/scutil", "--get", "LocalHostName"],
        capture_output=True,
        text=True,
    )
    local_host = completed.stdout.strip()
    if completed.returncode == 0 and local_host:
        names.append(f"{local_host}.local")
    host = socket.gethostname()
    if host:
        names.append(host if host.endswith(".local") else f"{host}.local")
    return tuple(dict.fromkeys(names))


def resolve_lan_host(host: str) -> str | None:
    if host_is_loopback(host):
        return None
    try:
        ipaddress.ip_address(host)
        return host
    except ValueError:
        pass
    try:
        infos = socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror:
        return None
    for info in infos:
        candidate = info[4][0]
        if not host_is_loopback(candidate):
            return candidate
    return None


def probe_emby(address: str, timeout: float = 1.5) -> str | None:
    url = address.rstrip("/") + "/System/Info/Public"
    request = Request(url, headers={"Accept": "application/json"})
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (OSError, URLError, TimeoutError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    identifier = payload.get("Id") if isinstance(payload, dict) else None
    return identifier if isinstance(identifier, str) and identifier else None


def probe_webdav(address: str, timeout: float = 1.5) -> str | None:
    split = urlsplit(address)
    if split.hostname is None:
        return None
    port = split.port or WEBDAV_PORT
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection((split.hostname, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            with context.wrap_socket(sock, server_hostname=split.hostname) as wrapped:
                certificate = wrapped.getpeercert(binary_form=True)
    except (OSError, TimeoutError, ssl.SSLError):
        return None
    if not certificate:
        return None
    return "sha256:" + hashlib.sha256(certificate).hexdigest()


def probe_smb(address: str) -> str | None:
    host = endpoint_host(address)
    if not host:
        return None
    own = primary_lan_ipv4()
    if host != own and not port_open(host, SMB_PORT, timeout=0.5):
        return None
    try:
        configuration = smb.SMBSourceConfiguration(
            runtime_root=smb.DEFAULT_RUNTIME_ROOT,
            registry_path=smb.DEFAULT_REGISTRY,
            environment_file=smb.DEFAULT_ENVIRONMENT_FILE,
            address=host,
        )
    except smb.SMBSourceError:
        return None
    mount = smb.DarwinSMBMount()
    mounted = False
    configuration.runtime_root.mkdir(parents=True, exist_ok=True)
    os.chmod(configuration.runtime_root, 0o700)
    mount_point = Path(
        tempfile.mkdtemp(prefix="ensure-smb-", dir=configuration.runtime_root)
    )
    try:
        credentials = smb._read_credentials(configuration.environment_file)
        objects = smb._load_aggregate(configuration.registry_path)
        mount.mount(
            configuration.address,
            configuration.share_name,
            credentials.user,
            credentials.password,
            mount_point,
        )
        mounted = True
        hashes: dict[str, str] = {}
        paths: list[str] = []
        root = mount_point.resolve()
        for item in objects:
            candidate = mount_point.joinpath(*PurePosixPath(item.relative_path).parts)
            resolved = candidate.resolve()
            try:
                resolved.relative_to(root)
            except ValueError:
                return None
            if not resolved.is_file():
                return None
            observed = smb._file_digest(resolved)
            hashes[item.identifier] = observed
            paths.append(item.relative_path)
            if observed != item.digest:
                return observed
        return smb._digest({"manifestHashes": hashes, "paths": paths})
    except (smb.SMBSourceError, OSError):
        return None
    finally:
        if mounted:
            try:
                mount.unmount(mount_point)
            except smb.SMBSourceError:
                pass
        subprocess.run(["/bin/rm", "-rf", str(mount_point)], capture_output=True)


def start_emby(expected: str, port: int) -> Started | None:
    subprocess.run(["/usr/bin/open", "-a", EMBY_APP], capture_output=True, text=True)
    deadline = time.monotonic() + EMBY_START_SECONDS
    hosts: list[str] = []
    primary = primary_lan_ipv4()
    if primary is not None:
        hosts.append(primary)
    hosts.extend(mdns_hostnames())
    while time.monotonic() < deadline:
        for host in hosts:
            resolved = resolve_lan_host(host)
            if resolved is None:
                continue
            address = format_address("http", resolved, port, "")
            if branch_loopback(address):
                continue
            observed = probe_emby(address, timeout=0.8)
            if observed == expected:
                return Started(address, expected, observed)
        time.sleep(0.4)
    return None


def start_webdav() -> Started | None:
    host = primary_lan_ipv4()
    if host is None:
        return None
    configuration = remote.ServiceConfiguration(
        runtime_root=remote.DEFAULT_RUNTIME_ROOT,
        registry_path=remote.DEFAULT_REGISTRY,
        source_root=remote.DEFAULT_SOURCE_ROOT,
        bind_host=host,
        port=WEBDAV_PORT,
    )
    try:
        identity = remote.RemoteSourceController(configuration).ensure()
    except remote.RemoteSourceError:
        return None
    address = identity.get("address")
    service_id = identity.get("serviceID")
    fingerprint = identity.get("certificateFingerprint")
    if not isinstance(address, str) or not isinstance(service_id, str):
        return None
    if not isinstance(fingerprint, str) or not fingerprint:
        return None
    if branch_loopback(address):
        return None
    return Started(address, service_id, fingerprint)


def start_smb() -> Started | None:
    host = primary_lan_ipv4()
    if host is None:
        return None
    try:
        configuration = smb.SMBSourceConfiguration(
            runtime_root=smb.DEFAULT_RUNTIME_ROOT,
            registry_path=smb.DEFAULT_REGISTRY,
            environment_file=smb.DEFAULT_ENVIRONMENT_FILE,
            address=host,
        )
    except smb.SMBSourceError:
        return None
    report = smb.run_preflight(configuration)
    if report.get("ready") is not True:
        return None
    try:
        runtime = json.loads(configuration.runtime_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    address = runtime.get("address")
    identity = runtime.get("sourceIdentity")
    digest = runtime.get("aggregateDigest")
    if not all(isinstance(item, str) and item for item in (address, identity, digest)):
        return None
    if branch_loopback(str(address)):
        return None
    return Started(str(address), str(identity), str(digest))


def rewrite_emby(address: str) -> None:
    path = emby.DEFAULT_IDENTITY_FILE
    document = json.loads(path.read_text(encoding="utf-8"))
    document["address"] = address
    _write_json(path, document, mode=stat.S_IMODE(path.stat().st_mode))


def rewrite_webdav(address: str) -> None:
    path = remote.DEFAULT_RUNTIME_ROOT / "runtime.json"
    if not path.is_file():
        return
    document = json.loads(path.read_text(encoding="utf-8"))
    document["address"] = address
    _write_json(path, document, mode=0o600)


def rewrite_smb(address: str) -> None:
    path = smb.DEFAULT_RUNTIME_ROOT / "runtime.json"
    if not path.is_file():
        return
    document = json.loads(path.read_text(encoding="utf-8"))
    document["address"] = address
    share = document.get("shareName")
    digest = document.get("aggregateDigest")
    if isinstance(share, str) and isinstance(digest, str):
        document["sourceIdentity"] = "smb-source:" + smb._digest(
            {
                "address": address,
                "shareName": share,
                "aggregateDigest": digest,
            }
        ).removeprefix(smb.SHA256_PREFIX)[:24]
    _write_json(path, document, mode=0o600)


def classify(address: str, observed: str | None, expected: str) -> str:
    if branch_loopback(address):
        return "loopback"
    if branch_no_candidate(observed):
        return "unreachable"
    if branch_identity_mismatch(observed, expected):
        return "identity-mismatch"
    return "identity-match"


def candidate_addresses(spec: ServiceSpec) -> tuple[tuple[str, str], ...]:
    ordered: list[tuple[str, str]] = []
    seen: set[str] = set()

    def add(address: str, source: str) -> None:
        if not address or address in seen:
            return
        seen.add(address)
        ordered.append((address, source))

    if spec.recorded_address:
        add(spec.recorded_address, "recorded")
    for host in spec.hooks.lan_hosts():
        resolved = resolve_lan_host(host)
        if resolved is None:
            continue
        add(format_address(spec.scheme, resolved, spec.port, spec.path), "lan")
    for name in spec.hooks.mdns_hosts():
        resolved = resolve_lan_host(name)
        if resolved is None:
            continue
        add(format_address(spec.scheme, resolved, spec.port, spec.path), "mdns")
    return tuple(ordered)


def _lan_ports(spec: ServiceSpec, ordered: tuple[tuple[str, str], ...]) -> dict[str, bool]:
    targets = [address for address, source in ordered if source != "recorded"]
    if not targets:
        return {}

    def check(address: str) -> tuple[str, bool]:
        return address, spec.hooks.port_open(endpoint_host(address), spec.port)

    with ThreadPoolExecutor(max_workers=64) as pool:
        return dict(pool.map(check, targets))


def make_receipt(
    spec: ServiceSpec,
    *,
    action: str,
    address: str | None,
    candidates: list[dict[str, object]],
    previous: str | None = None,
    reason: str | None = None,
    identity: str | None = None,
    closed_ports: int = 0,
) -> dict[str, object]:
    evidence: dict[str, object] = {"candidates": candidates, "closedPorts": closed_ports}
    if reason:
        evidence["reason"] = reason
    return {
        "schema": RECEIPT_SCHEMA,
        "service": spec.name,
        "identity": spec.identity if identity is None else identity,
        "address": address,
        "action": action,
        "recordedAddress": spec.recorded_address,
        "previousAddress": previous,
        "evidence": evidence,
    }


def resolve(spec: ServiceSpec) -> dict[str, object]:
    candidates: list[dict[str, object]] = []
    match: str | None = None
    ordered = candidate_addresses(spec)
    open_ports = _lan_ports(spec, ordered)
    closed_ports = 0
    for address, source in ordered:
        if source != "recorded" and not open_ports.get(address, False):
            closed_ports += 1
            continue
        observed = spec.hooks.probe(address)
        result = classify(address, observed, spec.expected)
        candidates.append(
            {
                "address": address,
                "source": source,
                "result": result,
                "observedIdentity": observed,
            }
        )
        if result == "identity-mismatch" and source == "recorded":
            payload = make_receipt(
                spec,
                action="unavailable",
                address=None,
                candidates=candidates,
                closed_ports=closed_ports,
                reason="identity-mismatch",
            )
            _write_json(spec.receipt_file, payload, mode=0o644)
            return payload
        if result == "identity-match":
            match = address
            break
    if match is not None:
        previous = spec.recorded_address
        if previous == match:
            action = "found"
            previous = None
        else:
            action = "moved"
            spec.hooks.rewrite(match)
        payload = make_receipt(
            spec,
            action=action,
            address=match,
            candidates=candidates,
            closed_ports=closed_ports,
            previous=previous,
        )
        _write_json(spec.receipt_file, payload, mode=0o644)
        return payload
    started = spec.hooks.start()
    if branch_start_failed(started):
        payload = make_receipt(
            spec,
            action="unavailable",
            address=None,
            candidates=candidates,
            closed_ports=closed_ports,
            reason="start-failed",
        )
        _write_json(spec.receipt_file, payload, mode=0o644)
        return payload
    started_address = getattr(started, "address", None)
    started_identity = getattr(started, "identity", spec.identity)
    started_observed = getattr(started, "observed", spec.expected)
    if not started_address:
        payload = make_receipt(
            spec,
            action="started",
            address=None,
            candidates=candidates,
            closed_ports=closed_ports,
            identity=started_identity,
        )
        _write_json(spec.receipt_file, payload, mode=0o644)
        return payload
    observed = spec.hooks.probe(started_address)
    result = classify(started_address, observed, started_observed)
    candidates.append(
        {
            "address": started_address,
            "source": "started",
            "result": result,
            "observedIdentity": observed,
        }
    )
    if result != "identity-match":
        reason = "loopback" if result == "loopback" else (
            "identity-mismatch" if result == "identity-mismatch" else "start-failed"
        )
        payload = make_receipt(
            spec,
            action="unavailable",
            address=None,
            candidates=candidates,
            closed_ports=closed_ports,
            reason=reason,
        )
        _write_json(spec.receipt_file, payload, mode=0o644)
        return payload
    if spec.recorded_address != started_address:
        spec.hooks.rewrite(started_address)
    payload = make_receipt(
        spec,
        action="started",
        address=started_address,
        candidates=candidates,
        closed_ports=closed_ports,
        identity=started_identity,
    )
    _write_json(spec.receipt_file, payload, mode=0o644)
    return payload


def _read_object(path: Path) -> dict[str, object] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def emby_spec(hooks: ServiceHooks | None = None) -> ServiceSpec:
    document = _read_object(emby.DEFAULT_IDENTITY_FILE) or {}
    server_id = document.get("serverID")
    address = document.get("address")
    identity = server_id if isinstance(server_id, str) else ""
    recorded = address if isinstance(address, str) and address else None
    split = urlsplit(recorded) if recorded else None
    port = (split.port if split is not None and split.port else EMBY_PORT)
    scheme = (split.scheme if split is not None and split.scheme else "http")
    path = split.path if split is not None else ""
    live = hooks or ServiceHooks(
        probe=probe_emby,
        lan_hosts=lan_ipv4_hosts,
        mdns_hosts=mdns_hostnames,
        port_open=port_open,
        start=lambda: start_emby(identity, port),
        rewrite=rewrite_emby,
    )
    return ServiceSpec(
        name="emby",
        identity=identity,
        expected=identity,
        recorded_address=recorded,
        receipt_file=emby.DEFAULT_RUNTIME_ROOT / RECEIPT_NAME,
        port=port,
        scheme=scheme,
        path=path if path != "/" else "",
        hooks=live,
    )


def webdav_spec(hooks: ServiceHooks | None = None) -> ServiceSpec:
    runtime = _read_object(remote.DEFAULT_RUNTIME_ROOT / "runtime.json") or {}
    service_id = runtime.get("serviceID")
    fingerprint = runtime.get("certificateFingerprint")
    address = runtime.get("address")
    identity = service_id if isinstance(service_id, str) else ""
    expected = fingerprint if isinstance(fingerprint, str) else ""
    recorded = address if isinstance(address, str) and address else None
    split = urlsplit(recorded) if recorded else None
    port = split.port if split is not None and split.port else WEBDAV_PORT
    scheme = split.scheme if split is not None and split.scheme else "https"
    path = split.path if split is not None else ""
    live = hooks or ServiceHooks(
        probe=probe_webdav,
        lan_hosts=lan_ipv4_hosts,
        mdns_hosts=mdns_hostnames,
        port_open=port_open,
        start=start_webdav,
        rewrite=rewrite_webdav,
    )
    return ServiceSpec(
        name="webdav",
        identity=identity,
        expected=expected,
        recorded_address=recorded,
        receipt_file=remote.DEFAULT_RUNTIME_ROOT / RECEIPT_NAME,
        port=port,
        scheme=scheme,
        path=path,
        hooks=live,
    )


def webdav_expected_from_registry_digest() -> str:
    runtime = _read_object(remote.DEFAULT_RUNTIME_ROOT / "runtime.json") or {}
    fingerprint = runtime.get("certificateFingerprint")
    return fingerprint if isinstance(fingerprint, str) else ""


def smb_aggregate_identity() -> str:
    runtime = _read_object(smb.DEFAULT_RUNTIME_ROOT / "runtime.json") or {}
    digest = runtime.get("aggregateDigest")
    if isinstance(digest, str) and digest:
        return digest
    try:
        objects = smb._load_aggregate(smb.DEFAULT_REGISTRY)
    except smb.SMBSourceError:
        return ""
    hashes = {item.identifier: item.digest for item in objects}
    paths = [item.relative_path for item in objects]
    return smb._digest({"manifestHashes": hashes, "paths": paths})


def smb_spec(hooks: ServiceHooks | None = None) -> ServiceSpec:
    runtime = _read_object(smb.DEFAULT_RUNTIME_ROOT / "runtime.json") or {}
    source_identity = runtime.get("sourceIdentity")
    address = runtime.get("address")
    identity = source_identity if isinstance(source_identity, str) else ""
    expected = smb_aggregate_identity()
    recorded = address if isinstance(address, str) and address else None
    live = hooks or ServiceHooks(
        probe=probe_smb,
        lan_hosts=lan_ipv4_hosts,
        mdns_hosts=mdns_hostnames,
        port_open=port_open,
        start=start_smb,
        rewrite=rewrite_smb,
    )
    return ServiceSpec(
        name="smb",
        identity=identity,
        expected=expected,
        recorded_address=recorded,
        receipt_file=smb.DEFAULT_RUNTIME_ROOT / RECEIPT_NAME,
        port=SMB_PORT,
        scheme="",
        path="",
        hooks=live,
    )


def ensure_all(specs: tuple[ServiceSpec, ...] | None = None) -> tuple[list[dict[str, object]], int]:
    selected = specs if specs is not None else (emby_spec(), webdav_spec(), smb_spec())
    receipts = [resolve(spec) for spec in selected]
    code = 0 if all(item.get("action") != "unavailable" for item in receipts) else 1
    return receipts, code


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Resolve Emby, WebDAV, and SMB test services by identity."
    )
    parser.add_argument(
        "--service",
        choices=("emby", "webdav", "smb"),
        action="append",
    )
    arguments = parser.parse_args(argv)
    builders = {"emby": emby_spec, "webdav": webdav_spec, "smb": smb_spec}
    names = tuple(arguments.service) if arguments.service else ("emby", "webdav", "smb")
    specs = tuple(builders[name]() for name in names)
    receipts, code = ensure_all(specs)
    print(
        json.dumps(
            {"schema": SUMMARY_SCHEMA, "receipts": receipts},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
    )
    return code


if __name__ == "__main__":
    raise SystemExit(main())
