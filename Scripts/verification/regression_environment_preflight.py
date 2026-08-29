#!/usr/bin/env python3
"""Run the closed host-environment preflights for remote regressions."""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
from http.client import HTTPException, HTTPSConnection, IncompleteRead
import hashlib
import json
from pathlib import Path
import ssl
from typing import Callable, Mapping
from urllib.parse import quote, urlsplit
import xml.etree.ElementTree as ElementTree

import regression_remote_source as remote
import regression_emby_source as emby


DEFAULT_EMBY_CONFIGURATION = emby.DEFAULT_CONFIGURATION


class PreflightError(RuntimeError):
    pass


@dataclass(frozen=True)
class PreflightConfiguration:
    service: remote.ServiceConfiguration
    request_timeout_seconds: float = 3.0

    def __post_init__(self) -> None:
        if (
            not isinstance(self.request_timeout_seconds, (int, float))
            or isinstance(self.request_timeout_seconds, bool)
            or not 0 < self.request_timeout_seconds <= 30
        ):
            raise PreflightError("request timeout must be greater than zero and at most 30 seconds")


@dataclass(frozen=True)
class _HTTPResult:
    status: int
    headers: Mapping[str, str]
    body: bytes
    certificate_fingerprint: str


def _runtime(configuration: PreflightConfiguration) -> dict[str, object]:
    try:
        value = json.loads(
            configuration.service.runtime_file.read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as error:
        raise PreflightError("remote source runtime identity is unreadable") from error
    if not isinstance(value, dict) or set(value) != remote.RUNTIME_DOCUMENT_KEYS:
        raise PreflightError("remote source runtime identity has an unexpected schema")
    address = value.get("address")
    user = value.get("user")
    password = value.get("password")
    if not all(isinstance(item, str) and item for item in (address, user, password)):
        raise PreflightError("remote source runtime identity has incomplete UI inputs")
    return value


def _tls_context() -> ssl.SSLContext:
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def _request(
    configuration: PreflightConfiguration,
    method: str,
    relative_path: str = "",
    *,
    headers: Mapping[str, str] | None = None,
    body: bytes | None = None,
) -> _HTTPResult:
    runtime = _runtime(configuration)
    endpoint = urlsplit(str(runtime["address"]))
    if endpoint.scheme != "https" or endpoint.hostname is None or endpoint.port is None:
        raise PreflightError("remote source runtime address is not one exact HTTPS endpoint")
    token = base64.b64encode(
        f"{runtime['user']}:{runtime['password']}".encode("utf-8")
    ).decode("ascii")
    request_headers = {"Authorization": f"Basic {token}", **dict(headers or {})}
    connection = HTTPSConnection(
        endpoint.hostname,
        endpoint.port,
        timeout=float(configuration.request_timeout_seconds),
        context=_tls_context(),
    )
    try:
        connection.request(
            method,
            endpoint.path + relative_path,
            body=body,
            headers=request_headers,
        )
        response = connection.getresponse()
        certificate = (
            connection.sock.getpeercert(binary_form=True)
            if connection.sock is not None
            else None
        )
        if not certificate:
            raise PreflightError("HTTPS peer did not present a certificate")
        fingerprint = "sha256:" + hashlib.sha256(certificate).hexdigest()
        payload = response.read()
        return _HTTPResult(
            response.status,
            dict(response.getheaders()),
            payload,
            fingerprint,
        )
    finally:
        connection.close()


def _range_request(
    configuration: PreflightConfiguration, name: str, start: int, end: int
) -> _HTTPResult:
    return _request(
        configuration,
        "GET",
        quote(name),
        headers={"Range": f"bytes={start}-{end}"},
    )


def _require(condition: bool, reason: str) -> None:
    if not condition:
        raise PreflightError(reason)


def _log_digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def _restoration_receipt_path(
    configuration: PreflightConfiguration,
    activation_receipt_id: str,
) -> Path:
    name = hashlib.sha256(activation_receipt_id.encode("utf-8")).hexdigest()
    return configuration.service.runtime_root / "restorations" / f"{name}.json"


def _restoration_result(path: Path, document: Mapping[str, object]) -> dict[str, object]:
    return {
        **dict(document),
        "receiptPath": str(path),
        "receiptDigest": _log_digest(path),
    }


def activate_remote_recipe(
    configuration: PreflightConfiguration,
    recipe: str,
) -> dict[str, object]:
    if recipe not in remote.RECIPE_NAMES:
        raise PreflightError(f"unknown closed recipe: {recipe}")
    controller = remote.RemoteSourceController(configuration.service)
    identity = controller.ensure()
    candidate_id = f"receipt:g-{int(identity['generation']):06d}:{recipe}"
    if identity.get("recipe") == recipe:
        try:
            existing = controller.receipt(candidate_id)
        except remote.RemoteSourceConfigurationError:
            existing = None
        if existing is not None and existing.get("restoredStateDigest") is None:
            return existing
    if identity.get("recipe") != "healthy":
        raise PreflightError("restore the active remote recipe before activating another")
    receipt = controller.activate(recipe)
    if (
        receipt.get("schema") != "enchron.regression.remote-source-receipt@1"
        or receipt.get("recipe") != recipe
        or receipt.get("generation") != int(identity["generation"]) + 1
        or receipt.get("restoredStateDigest") is not None
    ):
        raise PreflightError("remote recipe activation returned an invalid receipt")
    return receipt


def restore_remote_recipe(
    configuration: PreflightConfiguration,
    activation_receipt_id: str,
) -> dict[str, object]:
    controller = remote.RemoteSourceController(configuration.service)
    activation = controller.receipt(activation_receipt_id)
    receipt_path = _restoration_receipt_path(configuration, activation_receipt_id)
    if receipt_path.is_file():
        try:
            existing = json.loads(receipt_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise PreflightError("remote restoration receipt is unreadable") from error
        if (
            not isinstance(existing, dict)
            or existing.get("schema")
            != "enchron.regression.remote-source-restoration@1"
            or existing.get("activationReceiptID") != activation_receipt_id
            or existing.get("verified") is not True
        ):
            raise PreflightError("remote restoration receipt identity drifted")
        return _restoration_result(receipt_path, existing)

    restored_activation = controller.restore(activation_receipt_id)
    if restored_activation.get("restoredStateDigest") is None:
        raise PreflightError("remote recipe restore omitted its terminal state digest")
    healthy = check_webdav_regression(configuration)
    terminal = controller.status()
    if (
        terminal.get("recipe") != "healthy"
        or healthy.get("generation") != terminal.get("generation")
        or healthy.get("endpointDigest") != terminal.get("endpointDigest")
        or healthy.get("certificateFingerprint")
        != terminal.get("certificateFingerprint")
    ):
        raise PreflightError("remote recipe restore did not converge to verified healthy")
    document = {
        "schema": "enchron.regression.remote-source-restoration@1",
        "receiptID": (
            f"restore:g-{int(terminal['generation']):06d}:"
            + hashlib.sha256(activation_receipt_id.encode("utf-8")).hexdigest()[:16]
        ),
        "activationReceiptID": activation_receipt_id,
        "activationRecipe": restored_activation["recipe"],
        "activationGeneration": restored_activation["generation"],
        "activationEndpointDigest": restored_activation["endpointDigest"],
        "activationLogPath": restored_activation["logPath"],
        "activationLogDigest": restored_activation["logDigest"],
        "restoredAt": remote._utc_now(),
        "restoredRecipe": "healthy",
        "restoredGeneration": terminal["generation"],
        "restoredStateDigest": restored_activation["restoredStateDigest"],
        "restoredEndpointDigest": terminal["endpointDigest"],
        "restoredCertificateFingerprint": terminal["certificateFingerprint"],
        "restoredRequestLogPath": healthy["requestLogPath"],
        "restoredRequestLogDigest": healthy["requestLogDigest"],
        "objectManifestHashes": healthy["objectManifestHashes"],
        "propfindStatus": healthy["propfindStatus"],
        "rangeStatus": healthy["rangeStatus"],
        "range": healthy["range"],
        "rangeDigest": healthy["rangeDigest"],
        "expectedRangeDigest": healthy["expectedRangeDigest"],
        "verified": True,
    }
    remote._write_json(receipt_path, document, mode=0o644)
    return _restoration_result(receipt_path, document)


def check_webdav_regression(
    configuration: PreflightConfiguration,
) -> dict[str, object]:
    manifest = remote.FixtureManifest.load(configuration.service)
    controller = remote.RemoteSourceController(configuration.service)
    identity = controller.ensure()
    propfind = _request(
        configuration,
        "PROPFIND",
        headers={
            "Depth": "1",
            "Content-Type": "application/xml; charset=utf-8",
        },
        body=b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>',
    )
    _require(propfind.status == 207, f"authenticated PROPFIND returned {propfind.status}")
    _require(
        propfind.certificate_fingerprint == identity["certificateFingerprint"],
        "served certificate fingerprint does not match runtime identity",
    )
    try:
        xml_root = ElementTree.fromstring(propfind.body)
    except ElementTree.ParseError as error:
        raise PreflightError("authenticated PROPFIND returned malformed DAV XML") from error
    hrefs = [item.text or "" for item in xml_root.findall(".//{DAV:}href")]
    for item in manifest.objects:
        _require(
            any(quote(item.name) in href for href in hrefs),
            f"PROPFIND omitted registered fixture {item.identifier}",
        )

    primary = manifest.primary
    start = 16 if primary.size > 64 else 0
    end = min(primary.size - 1, start + 47)
    with primary.source.open("rb") as source:
        source.seek(start)
        expected = source.read(end - start + 1)
    ranged = _range_request(configuration, primary.name, start, end)
    _require(ranged.status == 206, f"registered range GET returned {ranged.status}")
    _require(
        ranged.headers.get("Content-Range") == f"bytes {start}-{end}/{primary.size}",
        "registered range GET returned the wrong Content-Range",
    )
    _require(ranged.body == expected, "registered range bytes do not match TestMedia")
    _require(
        ranged.certificate_fingerprint == identity["certificateFingerprint"],
        "range GET certificate fingerprint drifted from runtime identity",
    )

    try:
        manifest_document = json.loads(
            Path(str(identity["manifestPath"])).read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as error:
        raise PreflightError("served object manifest is unreadable") from error
    served_hashes = {
        item.get("fixtureID"): item.get("digest")
        for item in manifest_document.get("objects", [])
        if isinstance(item, dict)
    }
    _require(served_hashes == manifest.hashes, "served object manifest hashes drifted")

    request_log = Path(str(identity["requestLogPath"]))
    _require(request_log.is_file(), "generation request log was not created")
    return {
        "check": "webdav-regression",
        "ready": True,
        "serviceID": identity["serviceID"],
        "generation": identity["generation"],
        "endpointDigest": identity["endpointDigest"],
        "certificateFingerprint": identity["certificateFingerprint"],
        "requestLogPath": str(request_log),
        "requestLogDigest": _log_digest(request_log),
        "objectManifestHashes": manifest.hashes,
        "propfindStatus": propfind.status,
        "rangeStatus": ranged.status,
        "range": f"bytes={start}-{end}",
        "rangeDigest": "sha256:" + hashlib.sha256(ranged.body).hexdigest(),
        "expectedRangeDigest": "sha256:" + hashlib.sha256(expected).hexdigest(),
        "realDeviceLimitation": (
            "Host preflight proves the served certificate fingerprint; installing or "
            "rotating that trust on a real device remains an explicit device Preparation."
        ),
    }


def _verify_log_causality(
    recipe: str, receipt: Mapping[str, object], *, fingerprint_changed: bool = False
) -> None:
    path = Path(str(receipt["logPath"]))
    _require(path.is_file(), f"{recipe} did not produce its generation request log")
    try:
        entries = [json.loads(line) for line in path.read_text().splitlines() if line]
    except json.JSONDecodeError as error:
        raise PreflightError(f"{recipe} request log is not valid JSONL") from error
    _require(entries, f"{recipe} produced no bound HTTP request")
    _require(
        all(
            isinstance(item, dict)
            and item.get("recipe") == recipe
            and item.get("generation") == receipt["generation"]
            for item in entries
        ),
        f"{recipe} request log is not bound to its recipe generation",
    )
    if recipe not in {"healthy", "certificate-rotation"}:
        _require(
            any(item.get("triggered") is True for item in entries),
            f"{recipe} never triggered from its declared request condition",
        )
    if recipe == "recoverable-read-interruption":
        triggered = [item for item in entries if item.get("triggered") is True]
        _require(
            len(triggered) == 1
            and triggered[0].get("recipeReadOrdinal") == 1
            and triggered[0].get("expectedBackoffMillis") == 250
            and triggered[0].get("disconnectOwner") == "remote-source-recipe",
            "recoverable-read-interruption lost its single source-owned fault",
        )
    if recipe == "finite-reconnect":
        _require(
            [item.get("recipeReadOrdinal") for item in entries] == [1, 2, 3, 4]
            and [item.get("expectedBackoffMillis") for item in entries]
            == [250, 500, 1000, None]
            and all(
                item.get("disconnectOwner") == "remote-source-recipe"
                for item in entries[:3]
            ),
            "finite-reconnect lost its bounded source-owned backoff contract",
        )
    if recipe == "certificate-rotation":
        _require(fingerprint_changed, "certificate-rotation did not change the fingerprint")


def _verify_recipe(
    configuration: PreflightConfiguration,
    controller: remote.RemoteSourceController,
    manifest: remote.FixtureManifest,
    recipe: str,
) -> dict[str, object]:
    before = controller.status()
    receipt = controller.activate(recipe)
    observed: dict[str, object] = {}
    action_error: Exception | None = None
    try:
        if recipe == "healthy":
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(result.status == 206, "healthy recipe did not serve ranged bytes")
            with manifest.primary.source.open("rb") as source:
                expected = source.read(64)
            _require(result.body == expected, "healthy recipe changed registered bytes")
            observed = {"statuses": [result.status]}
        elif recipe == "credentials-rejected":
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(result.status == 401, "credentials-rejected did not return 401")
            observed = {"statuses": [result.status]}
        elif recipe == "missing-object":
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(result.status == 404, "missing-object did not return 404")
            observed = {"statuses": [result.status]}
        elif recipe == "access-denied":
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(result.status == 403, "access-denied did not return 403")
            observed = {"statuses": [result.status]}
        elif recipe == "corrupt-media":
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            with manifest.primary.source.open("rb") as source:
                expected = source.read(64)
            _require(result.status == 206, "corrupt-media did not serve a ranged response")
            _require(
                len(result.body) == len(expected) and result.body != expected,
                "corrupt-media did not deterministically alter media bytes",
            )
            observed = {
                "statuses": [result.status],
                "alteredDigest": "sha256:" + hashlib.sha256(result.body).hexdigest(),
            }
        elif recipe == "recoverable-read-interruption":
            interrupted = False
            try:
                _range_request(configuration, manifest.primary.name, 0, 63)
            except IncompleteRead:
                interrupted = True
            _require(interrupted, "recoverable-read-interruption did not truncate its first read")
            recovered = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(recovered.status == 206 and len(recovered.body) == 64, "read did not recover")
            observed = {"interrupted": True, "recoveryStatus": recovered.status}
        elif recipe == "finite-reconnect":
            statuses = [
                _range_request(configuration, manifest.primary.name, 0, 63).status
                for _ in range(4)
            ]
            _require(
                statuses == [503, 503, 503, 206],
                "finite-reconnect did not expose three bounded failures then recover",
            )
            observed = {"statuses": statuses}
        elif recipe == "buffer-absorbed-interruption":
            statuses = [
                _range_request(configuration, manifest.primary.name, 0, 63).status
                for _ in range(3)
            ]
            _require(
                statuses == [206, 503, 206],
                "buffer-absorbed-interruption did not trigger after the buffer-filling read",
            )
            observed = {"statuses": statuses}
        elif recipe == "certificate-rotation":
            after = controller.status()
            result = _range_request(configuration, manifest.primary.name, 0, 63)
            _require(result.status == 206, "rotated certificate endpoint did not serve bytes")
            _require(
                before["certificateFingerprint"] != after["certificateFingerprint"],
                "certificate-rotation preserved the prior fingerprint",
            )
            _require(
                result.certificate_fingerprint == after["certificateFingerprint"],
                "rotated fingerprint is not the certificate served on the endpoint",
            )
            observed = {
                "statuses": [result.status],
                "priorCertificateFingerprint": before["certificateFingerprint"],
                "rotatedCertificateFingerprint": after["certificateFingerprint"],
            }
        else:
            raise AssertionError("closed recipe registry and verifier drifted")
    except Exception as error:
        action_error = error
    try:
        restored = controller.restore(str(receipt["receiptID"]))
    except Exception:
        if action_error is not None:
            raise action_error
        raise
    if action_error is not None:
        raise action_error
    fingerprint_changed = (
        recipe == "certificate-rotation"
        and observed.get("priorCertificateFingerprint")
        != observed.get("rotatedCertificateFingerprint")
    )
    _verify_log_causality(recipe, restored, fingerprint_changed=fingerprint_changed)
    _require(
        restored["logDigest"] == _log_digest(Path(str(restored["logPath"]))),
        f"{recipe} receipt log digest does not bind the generation log",
    )
    return {
        "recipe": recipe,
        "verified": True,
        "observed": observed,
        "receipt": restored,
    }


def check_remote_faults(
    configuration: PreflightConfiguration,
) -> dict[str, object]:
    manifest = remote.FixtureManifest.load(configuration.service)
    controller = remote.RemoteSourceController(configuration.service)
    identity = controller.ensure()
    recipes = [
        _verify_recipe(configuration, controller, manifest, recipe)
        for recipe in remote.RECIPE_NAMES
    ]
    final = controller.status()
    _require(final["recipe"] == "healthy", "remote source was not restored to healthy")
    return {
        "check": "remote-faults",
        "ready": True,
        "serviceID": identity["serviceID"],
        "recipes": recipes,
        "terminalState": {
            "generation": final["generation"],
            "recipe": final["recipe"],
            "endpointDigest": final["endpointDigest"],
            "certificateFingerprint": final["certificateFingerprint"],
        },
        "realDeviceLimitation": (
            "The bounded host integration proves protocol and recipe causality, but it "
            "does not assert that a particular real device has trusted the current certificate."
        ),
    }


CHECKS: Mapping[
    str, Callable[[PreflightConfiguration], dict[str, object]]
] = {
    "webdav-regression": check_webdav_regression,
    "remote-faults": check_remote_faults,
    "emby-aggregate": lambda _: emby.run_preflight(DEFAULT_EMBY_CONFIGURATION),
}


def _redact_reason(reason: str, configuration: PreflightConfiguration) -> str:
    if configuration.service.runtime_file.is_file():
        try:
            runtime = json.loads(
                configuration.service.runtime_file.read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            runtime = {}
        if isinstance(runtime, dict):
            for key in ("user", "password"):
                secret = runtime.get(key)
                if isinstance(secret, str) and secret:
                    reason = reason.replace(secret, "<redacted>")
    return reason


def run_checks(
    names: list[str] | tuple[str, ...], configuration: PreflightConfiguration
) -> dict[str, object]:
    unknown = [name for name in names if name not in CHECKS]
    if unknown:
        raise PreflightError("unknown fixed check: " + ", ".join(unknown))
    selected = list(names) or list(CHECKS)
    results: list[dict[str, object]] = []
    for name in selected:
        try:
            result = CHECKS[name](configuration)
        except (
            PreflightError,
            remote.RemoteSourceError,
            HTTPException,
            OSError,
            ssl.SSLError,
        ) as error:
            result = {
                "check": name,
                "ready": False,
                "reason": _redact_reason(str(error), configuration),
            }
        results.append(result)
    return {
        "schema": "enchron.regression.environment-preflight@1",
        "ready": all(result.get("ready") is True for result in results),
        "checks": results,
    }


def render_report(report: Mapping[str, object]) -> str:
    return json.dumps(dict(report), ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("names", nargs="*", choices=tuple(CHECKS))
    parser.add_argument("--runtime-root", type=Path, default=remote.DEFAULT_RUNTIME_ROOT)
    parser.add_argument("--registry", type=Path, default=remote.DEFAULT_REGISTRY)
    parser.add_argument("--source-root", type=Path, default=remote.DEFAULT_SOURCE_ROOT)
    parser.add_argument("--bind-host", required=True)
    parser.add_argument("--port", type=int, default=8443)
    parser.add_argument("--request-timeout", type=float, default=3.0)
    parser.add_argument("--allow-loopback", action="store_true", help=argparse.SUPPRESS)
    arguments = parser.parse_args(argv)
    try:
        configuration = PreflightConfiguration(
            service=remote.ServiceConfiguration(
                runtime_root=arguments.runtime_root,
                registry_path=arguments.registry,
                source_root=arguments.source_root,
                bind_host=arguments.bind_host,
                port=arguments.port,
                allow_loopback=arguments.allow_loopback,
            ),
            request_timeout_seconds=arguments.request_timeout,
        )
        report = run_checks(arguments.names or list(CHECKS), configuration)
    except PreflightError as error:
        report = {
            "schema": "enchron.regression.environment-preflight@1",
            "ready": False,
            "checks": [],
            "reason": str(error),
        }
    print(render_report(report), end="")
    return 0 if report["ready"] is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
