#!/usr/bin/env python3

from __future__ import annotations

import base64
from http.client import HTTPSConnection, IncompleteRead
import hashlib
import json
from pathlib import Path
import ssl
import stat
import sys
import tempfile
import unittest
from urllib.parse import quote, urlsplit
import xml.etree.ElementTree as ElementTree


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import regression_remote_source as remote


FIXTURES = (
    (
        "generated-sdr-avc-bframe-aggregate-30s-v1",
        "sdr-bframe-aggregate-30s.mkv",
        bytes(range(256)) * 8,
    ),
    (
        "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
        "sdr-bframe-aggregate-30s.zh-CN.srt",
        b"1\n00:00:00,000 --> 00:00:01,000\nRemote subtitle\n",
    ),
    (
        "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
        "sdr-bframe-aggregate-30s.styled.ass",
        b"[Script Info]\nTitle: Remote styled subtitle\n",
    ),
)


class RemoteSourceTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="remote-source-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source_root = self.root / "TestMedia"
        self.source_root.mkdir()
        entries: list[dict[str, object]] = []
        self.bytes_by_name: dict[str, bytes] = {}
        for identifier, name, content in FIXTURES:
            relative = Path("TestVectors/Enchron/PlaybackBehavior") / name
            source = self.source_root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(content)
            self.bytes_by_name[name] = content
            entries.append(
                {
                    "id": identifier,
                    "deviceImportPath": relative.as_posix(),
                    "sha256": hashlib.sha256(content).hexdigest(),
                }
            )
        self.registry = self.root / "fixture-registry.json"
        self.registry.write_text(
            json.dumps(
                {
                    "schemaVersion": 2,
                    "deviceMediaRoot": "$WORKSPACE/TestMedia",
                    "fixtures": entries,
                }
            ),
            encoding="utf-8",
        )
        self.configuration = remote.ServiceConfiguration(
            runtime_root=self.root / "runtime",
            registry_path=self.registry,
            source_root=self.source_root,
            bind_host="127.0.0.1",
            port=0,
            allow_loopback=True,
        )
        self.controller = remote.RemoteSourceController(self.configuration)
        self.identity = self.controller.ensure()
        self.addCleanup(self.controller.stop)

    def runtime(self) -> dict[str, object]:
        return json.loads(self.configuration.runtime_file.read_text(encoding="utf-8"))

    def request(
        self,
        method: str,
        relative: str = "",
        *,
        headers: dict[str, str] | None = None,
        body: bytes | None = None,
        authenticated: bool = True,
        read_body: bool = True,
    ) -> tuple[int, dict[str, str], bytes]:
        runtime = self.runtime()
        endpoint = urlsplit(str(runtime["address"]))
        request_headers = dict(headers or {})
        if authenticated:
            token = base64.b64encode(
                f"{runtime['user']}:{runtime['password']}".encode("utf-8")
            ).decode("ascii")
            request_headers["Authorization"] = f"Basic {token}"
        connection = HTTPSConnection(
            endpoint.hostname,
            endpoint.port,
            timeout=2,
            context=ssl._create_unverified_context(),
        )
        path = endpoint.path + relative
        try:
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            payload = response.read() if read_body else b""
            return response.status, dict(response.getheaders()), payload
        finally:
            connection.close()

    def media_name(self) -> str:
        return FIXTURES[0][1]

    def activate(self, recipe: str) -> dict[str, object]:
        receipt = self.controller.activate(recipe)
        self.assertEqual(receipt["recipe"], recipe)
        self.assertIsNone(receipt["restoredStateDigest"])
        return receipt

    def restore(self, receipt: dict[str, object]) -> dict[str, object]:
        restored = self.controller.restore(str(receipt["receiptID"]))
        self.assertRegex(str(restored["restoredStateDigest"]), r"^sha256:[0-9a-f]{64}$")
        return restored


class RemoteSourceProtocolTests(RemoteSourceTestCase):
    def test_ensure_is_idempotent_and_runtime_secret_file_is_exact_0600(self) -> None:
        second = remote.RemoteSourceController(self.configuration).ensure()
        self.assertEqual(second, self.identity)
        runtime = self.runtime()
        self.assertEqual(set(runtime), remote.RUNTIME_DOCUMENT_KEYS)
        self.assertEqual(
            stat.S_IMODE(self.configuration.runtime_file.stat().st_mode), 0o600
        )
        self.assertEqual(runtime["address"], self.identity["address"])
        serialized_identity = json.dumps(self.identity, sort_keys=True)
        self.assertNotIn(str(runtime["user"]), serialized_identity)
        self.assertNotIn(str(runtime["password"]), serialized_identity)

    def test_authenticated_propfind_and_rfc_range_get_and_head(self) -> None:
        status, headers, payload = self.request(
            "PROPFIND",
            headers={"Depth": "1", "Content-Type": "application/xml; charset=utf-8"},
            body=b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:allprop/></d:propfind>',
        )
        self.assertEqual(status, 207)
        self.assertEqual(headers["Content-Type"], "application/xml; charset=utf-8")
        root = ElementTree.fromstring(payload)
        hrefs = [item.text for item in root.findall(".//{DAV:}href")]
        for _, name, _ in FIXTURES:
            self.assertTrue(any(item and quote(name) in item for item in hrefs))
        for _, sidecar_name, sidecar_bytes in FIXTURES[1:]:
            sidecar_status, _, sidecar_payload = self.request(
                "GET", quote(sidecar_name)
            )
            self.assertEqual(sidecar_status, 200)
            self.assertEqual(sidecar_payload, sidecar_bytes)

        name = quote(self.media_name())
        status, headers, payload = self.request(
            "GET", name, headers={"Range": "bytes=2-5"}
        )
        self.assertEqual(status, 206)
        self.assertEqual(headers["Accept-Ranges"], "bytes")
        self.assertEqual(headers["Content-Range"], "bytes 2-5/2048")
        self.assertEqual(payload, self.bytes_by_name[self.media_name()][2:6])

        status, headers, payload = self.request(
            "GET", name, headers={"Range": "bytes=-4"}
        )
        self.assertEqual(status, 206)
        self.assertEqual(headers["Content-Range"], "bytes 2044-2047/2048")
        self.assertEqual(payload, self.bytes_by_name[self.media_name()][-4:])

        status, headers, payload = self.request(
            "HEAD", name, headers={"Range": "bytes=6-9"}
        )
        self.assertEqual(status, 206)
        self.assertEqual(headers["Content-Length"], "4")
        self.assertEqual(headers["Content-Range"], "bytes 6-9/2048")
        self.assertEqual(payload, b"")

        status, headers, payload = self.request(
            "GET", name, headers={"Range": "bytes=9000-9001"}
        )
        self.assertEqual(status, 416)
        self.assertEqual(headers["Content-Range"], "bytes */2048")
        self.assertEqual(payload, b"")

    def test_authentication_and_path_traversal_are_rejected_without_log_leakage(self) -> None:
        status, _, _ = self.request("PROPFIND", authenticated=False)
        self.assertEqual(status, 401)
        status, _, _ = self.request("GET", "%2e%2e/private-key.pem")
        self.assertEqual(status, 400)
        log = Path(str(self.identity["requestLogPath"])).read_text(encoding="utf-8")
        runtime = self.runtime()
        self.assertNotIn("Authorization", log)
        self.assertNotIn(str(runtime["password"]), log)
        self.assertNotIn("private-key", log)
        entries = [json.loads(line) for line in log.splitlines()]
        self.assertTrue(entries)
        self.assertTrue(all(item["generation"] == self.identity["generation"] for item in entries))
        self.assertIn("<rejected>", {item["path"] for item in entries})


class RemoteSourceRecipeTests(RemoteSourceTestCase):
    def _status(self, recipe: str, expected: int) -> dict[str, object]:
        receipt = self.activate(recipe)
        status, _, _ = self.request("GET", quote(self.media_name()), headers={"Range": "bytes=0-31"})
        self.assertEqual(status, expected)
        return self.restore(receipt)

    def test_closed_status_and_corruption_recipes_have_request_bound_causality(self) -> None:
        receipts = [
            self._status("healthy", 206),
            self._status("credentials-rejected", 401),
            self._status("missing-object", 404),
            self._status("access-denied", 403),
        ]

        corrupt = self.activate("corrupt-media")
        status, _, payload = self.request(
            "GET", quote(self.media_name()), headers={"Range": "bytes=0-31"}
        )
        self.assertEqual(status, 206)
        self.assertEqual(len(payload), 32)
        self.assertNotEqual(payload, self.bytes_by_name[self.media_name()][:32])
        receipts.append(self.restore(corrupt))

        runtime = self.runtime()
        serialized = json.dumps(receipts, sort_keys=True)
        self.assertNotIn(str(runtime["user"]), serialized)
        self.assertNotIn(str(runtime["password"]), serialized)
        for receipt in receipts:
            self.assertRegex(str(receipt["endpointDigest"]), r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(str(receipt["priorStateDigest"]), r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(str(receipt["terminalStateDigest"]), r"^sha256:[0-9a-f]{64}$")
            log_path = Path(str(receipt["logPath"]))
            expected = "sha256:" + hashlib.sha256(log_path.read_bytes()).hexdigest()
            self.assertEqual(receipt["logDigest"], expected)
            entries = [json.loads(line) for line in log_path.read_text().splitlines()]
            self.assertTrue(all(item["recipe"] == receipt["recipe"] for item in entries))
            if receipt["recipe"] not in {"healthy"}:
                self.assertTrue(any(item["triggered"] for item in entries))

    def test_read_interruption_and_reconnect_recipes_trigger_then_recover(self) -> None:
        name = quote(self.media_name())

        receipt = self.activate("recoverable-read-interruption")
        with self.assertRaises(IncompleteRead):
            self.request("GET", name, headers={"Range": "bytes=0-63"})
        status, _, payload = self.request("GET", name, headers={"Range": "bytes=0-63"})
        self.assertEqual((status, len(payload)), (206, 64))
        self.restore(receipt)

        receipt = self.activate("finite-reconnect")
        statuses = [
            self.request("GET", name, headers={"Range": "bytes=0-31"})[0]
            for _ in range(4)
        ]
        self.assertEqual(statuses, [503, 503, 503, 206])
        restored = self.restore(receipt)
        entries = [
            json.loads(line)
            for line in Path(str(restored["logPath"])).read_text().splitlines()
        ]
        self.assertEqual(
            [item["recipeReadOrdinal"] for item in entries],
            [1, 2, 3, 4],
        )
        self.assertEqual(
            [item["expectedBackoffMillis"] for item in entries],
            [250, 500, 1000, None],
        )
        self.assertTrue(
            all(
                item["disconnectOwner"] == "remote-source-recipe"
                for item in entries[:3]
            )
        )
        self.assertEqual(entries[3]["disconnectOwner"], "none")
        self.assertEqual(
            [item["monotonicMillis"] for item in entries],
            sorted(item["monotonicMillis"] for item in entries),
        )

        receipt = self.activate("buffer-absorbed-interruption")
        statuses = [
            self.request("GET", name, headers={"Range": "bytes=0-31"})[0]
            for _ in range(3)
        ]
        self.assertEqual(statuses, [206, 503, 206])
        self.restore(receipt)

    def test_certificate_rotation_changes_the_served_certificate(self) -> None:
        prior = self.controller.status()
        runtime = self.runtime()
        endpoint = urlsplit(str(runtime["address"]))
        token = base64.b64encode(
            f"{runtime['user']}:{runtime['password']}".encode("utf-8")
        ).decode("ascii")
        existing = HTTPSConnection(
            endpoint.hostname,
            endpoint.port,
            timeout=2,
            context=ssl._create_unverified_context(),
        )
        existing.request(
            "GET",
            endpoint.path + quote(self.media_name()),
            headers={"Authorization": f"Basic {token}", "Range": "bytes=0-31"},
        )
        response = existing.getresponse()
        self.assertEqual(response.status, 206)
        self.assertEqual(len(response.read()), 32)
        old_socket = existing.sock
        self.assertIsNotNone(old_socket)

        receipt = self.activate("certificate-rotation")
        rotated = self.controller.status()
        self.assertNotEqual(
            prior["certificateFingerprint"], rotated["certificateFingerprint"]
        )
        assert old_socket is not None
        old_socket.settimeout(2)
        try:
            disconnected = old_socket.recv(1) == b""
        except (OSError, ssl.SSLError):
            disconnected = True
        existing.close()
        self.assertTrue(disconnected, "certificate rotation retained the old TLS connection")

        connection = HTTPSConnection(
            endpoint.hostname,
            endpoint.port,
            timeout=2,
            context=ssl._create_unverified_context(),
        )
        try:
            connection.connect()
            certificate = connection.sock.getpeercert(binary_form=True)
        finally:
            connection.close()
        fingerprint = "sha256:" + hashlib.sha256(certificate).hexdigest()
        self.assertEqual(fingerprint, rotated["certificateFingerprint"])
        restored = self.restore(receipt)
        self.assertEqual(restored, self.controller.restore(str(receipt["receiptID"])))

    def test_receipt_lookup_is_closed_generation_bound_and_secret_free(self) -> None:
        receipt = self.activate("missing-object")
        self.request(
            "GET",
            quote(self.media_name()),
            headers={"Range": "bytes=0-31"},
        )
        restored = self.restore(receipt)
        self.assertEqual(
            self.controller.receipt(str(receipt["receiptID"])),
            restored,
        )
        runtime = self.runtime()
        rendered = json.dumps(restored, sort_keys=True)
        self.assertNotIn(str(runtime["user"]), rendered)
        self.assertNotIn(str(runtime["password"]), rendered)
        with self.assertRaisesRegex(remote.RemoteSourceConfigurationError, "receipt"):
            self.controller.receipt("receipt:g-000001:unknown-recipe")

    def test_stop_is_idempotent(self) -> None:
        first = self.controller.stop()
        second = self.controller.stop()
        self.assertTrue(first["stopped"])
        self.assertTrue(second["stopped"])

    def test_ensure_after_stop_restarts_without_reusing_a_generation(self) -> None:
        prior_runtime = self.runtime()
        prior_generation = int(prior_runtime["generation"])
        self.controller.stop()
        restarted = self.controller.ensure()
        restarted_runtime = self.runtime()
        self.assertGreater(int(restarted["generation"]), prior_generation)
        self.assertEqual(restarted_runtime["user"], prior_runtime["user"])
        self.assertEqual(restarted_runtime["password"], prior_runtime["password"])


if __name__ == "__main__":
    unittest.main()
