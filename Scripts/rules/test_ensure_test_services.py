#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import ensure_test_services as services
import run_verification as verification


IDENTITY = "wanted-server"
OTHER = "other-server"
RECORDED = "http://mac-mini.local:8096"
RECORDED_IP = "http://192.168.5.20:8096"
LAN = "http://192.168.5.28:8096"
MDNS = "http://mac-mini.local:8096"
LOOPBACK = "http://127.0.0.1:8096"

IDENTITY_MISMATCH_SOURCE = (
    "def branch_identity_mismatch(observed: str | None, expected: str) -> bool:\n"
    "    return observed is not None and observed != expected\n"
)
LOOPBACK_SOURCE = (
    "def branch_loopback(address: str) -> bool:\n"
    "    return host_is_loopback(address)\n"
)
NO_CANDIDATE_SOURCE = (
    "def branch_no_candidate(observed: str | None) -> bool:\n"
    "    return observed is None\n"
)
START_FAILED_SOURCE = (
    "def branch_start_failed(started: object | None) -> bool:\n"
    "    return started is None\n"
)
NEUTER = "    return False\n"


class World:
    def __init__(
        self,
        probes: dict[str, str | None],
        *,
        lan: tuple[str, ...] = (),
        mdns: tuple[str, ...] = (),
        start: services.Started | None = None,
        recorded: str | None = RECORDED,
        expected: str = IDENTITY,
        identity: str = IDENTITY,
    ) -> None:
        self.probes = dict(probes)
        self.lan = lan
        self.mdns = mdns
        self.start_result = start
        self.recorded = recorded
        self.expected = expected
        self.identity = identity
        self.rewritten: list[str] = []
        self.start_calls = 0

    def hooks(self) -> services.ServiceHooks:
        return services.ServiceHooks(
            probe=lambda address: self.probes.get(address),
            lan_hosts=lambda: self.lan,
            mdns_hosts=lambda: self.mdns,
            port_open=lambda host, port: True,
            start=self._start,
            rewrite=self.rewritten.append,
        )

    def _start(self) -> services.Started | None:
        self.start_calls += 1
        started = self.start_result
        if started is not None:
            self.probes[started.address] = started.observed
        return started

    def spec(self, module, receipt_file: Path) -> object:
        return module.ServiceSpec(
            name="emby",
            identity=self.identity,
            expected=self.expected,
            recorded_address=self.recorded,
            receipt_file=receipt_file,
            port=8096,
            scheme="http",
            path="",
            hooks=self.hooks(),
        )


def _resolve(module, world: World, directory: Path) -> dict[str, object]:
    directory.mkdir(parents=True, exist_ok=True)
    receipt_file = directory / "ensure-receipt.json"
    return module.resolve(world.spec(module, receipt_file))


def run_found(module, directory: Path) -> dict[str, object]:
    world = World({RECORDED: IDENTITY})
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "found", receipt
    assert receipt["address"] == RECORDED, receipt
    assert receipt["previousAddress"] is None, receipt
    assert world.rewritten == []
    assert world.start_calls == 0
    return receipt


def run_moved(module, directory: Path) -> dict[str, object]:
    world = World(
        {RECORDED: None, LAN: IDENTITY},
        lan=("192.168.5.28",),
    )
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "moved", receipt
    assert receipt["address"] == LAN, receipt
    assert receipt["previousAddress"] == RECORDED, receipt
    assert world.rewritten == [LAN], world.rewritten
    return receipt


def run_started(module, directory: Path) -> dict[str, object]:
    started = services.Started(LAN, IDENTITY, IDENTITY)
    world = World({RECORDED: None}, start=started)
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "started", receipt
    assert receipt["address"] == LAN, receipt
    assert world.start_calls == 1
    assert world.rewritten == [LAN]
    return receipt


def run_identity_mismatch(module, directory: Path) -> dict[str, object]:
    world = World({RECORDED: OTHER}, start=services.Started(LAN, IDENTITY, IDENTITY))
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "unavailable", receipt
    assert receipt["address"] is None, receipt
    assert receipt["evidence"]["reason"] == "identity-mismatch", receipt
    assert world.start_calls == 0
    assert world.rewritten == []
    recorded = receipt["evidence"]["candidates"][0]
    assert recorded["result"] == "identity-mismatch", receipt
    assert recorded["observedIdentity"] == OTHER, receipt
    return receipt


def run_loopback(module, directory: Path) -> dict[str, object]:
    loopback_start = services.Started(LOOPBACK, IDENTITY, IDENTITY)
    world = World({LOOPBACK: IDENTITY}, recorded=LOOPBACK, start=loopback_start)
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "unavailable", receipt
    assert receipt["address"] is None, receipt
    assert receipt["address"] != LOOPBACK
    results = [item["result"] for item in receipt["evidence"]["candidates"]]
    assert "loopback" in results, receipt
    assert world.rewritten == []
    return receipt


def run_no_candidate(module, directory: Path) -> dict[str, object]:
    started = services.Started(LAN, IDENTITY, IDENTITY)
    world = World({RECORDED: None}, start=started)
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "started", receipt
    recorded = receipt["evidence"]["candidates"][0]
    assert recorded["address"] == RECORDED, receipt
    assert recorded["result"] == "unreachable", receipt
    assert receipt["address"] != RECORDED, receipt
    return receipt


def run_start_failure(module, directory: Path) -> dict[str, object]:
    world = World({}, recorded=None, start=None)
    receipt = _resolve(module, world, directory)
    assert receipt["action"] == "unavailable", receipt
    assert receipt["evidence"]["reason"] == "start-failed", receipt
    assert world.start_calls == 1
    assert receipt["address"] is None, receipt
    return receipt


NEGATIVE_CASES = (
    ("identity-mismatch", run_identity_mismatch),
    ("loopback", run_loopback),
    ("no-candidate", run_no_candidate),
    ("start-failed", run_start_failure),
)
MUTATIONS = (
    ("identity-mismatch", IDENTITY_MISMATCH_SOURCE),
    ("loopback", LOOPBACK_SOURCE),
    ("no-candidate", NO_CANDIDATE_SOURCE),
    ("start-failed", START_FAILED_SOURCE),
)


class EnsureTestServicesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="ensure-test-services-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_found_when_recorded_address_matches_identity(self) -> None:
        receipt = run_found(services, self.root)
        self.assertEqual(receipt["schema"], services.RECEIPT_SCHEMA)
        self.assertEqual(receipt["service"], "emby")
        self.assertEqual(receipt["identity"], IDENTITY)

    def test_moved_rewrites_recorded_address_and_keeps_both(self) -> None:
        receipt = run_moved(services, self.root)
        self.assertEqual(receipt["recordedAddress"], RECORDED)
        self.assertEqual(receipt["previousAddress"], RECORDED)
        self.assertEqual(receipt["address"], LAN)

    def test_started_when_nothing_matched_and_start_matches(self) -> None:
        receipt = run_started(services, self.root)
        self.assertEqual(receipt["action"], "started")
        sources = [item["source"] for item in receipt["evidence"]["candidates"]]
        self.assertIn("started", sources)

    def test_identity_mismatch_is_not_adopted(self) -> None:
        run_identity_mismatch(services, self.root)

    def test_loopback_is_rejected(self) -> None:
        run_loopback(services, self.root)

    def test_no_candidate_found_is_not_treated_as_a_match(self) -> None:
        run_no_candidate(services, self.root)

    def test_start_failure_is_unavailable(self) -> None:
        run_start_failure(services, self.root)

    def test_registered_to_run_in_full_mode_before_domain_tests(self) -> None:
        check = next(
            item
            for item in verification.STRUCTURE_CHECKS
            if item.filename == "ensure_test_services.py"
        )
        self.assertEqual(check.identifier, "ensure-test-services")
        self.assertFalse(check.runs_in_quick_mode)
        identifiers = [item.identifier for item in verification.STRUCTURE_CHECKS]
        self.assertLess(
            identifiers.index("ensure-test-services"),
            identifiers.index("organic-architecture-xcode"),
        )

    def test_each_negative_case_is_bound_to_its_branch(self) -> None:
        source = Path(services.__file__).read_text(encoding="utf-8")
        turned_red: dict[str, str] = {}
        for branch, fragment in MUTATIONS:
            self.assertIn(fragment, source)
            mutated_source = source.replace(fragment, _neuter(fragment), 1)
            self.assertNotEqual(source, mutated_source)
            module = _load_mutated(self.root / f"{branch}.py", mutated_source)
            failed: list[str] = []
            for name, runner in NEGATIVE_CASES:
                try:
                    runner(module, self.root / branch / name)
                except Exception:
                    failed.append(name)
            self.assertEqual(
                failed,
                [branch],
                f"neutering {branch} turned red {failed!r}, expected only {branch}",
            )
            turned_red[branch] = failed[0]
        self.assertEqual(
            turned_red,
            {
                "identity-mismatch": "identity-mismatch",
                "loopback": "loopback",
                "no-candidate": "no-candidate",
                "start-failed": "start-failed",
            },
        )

    def test_service_endpoint_shape_and_host_kind(self) -> None:
        endpoint = services.ServiceEndpoint("http", "mac-mini.local", 8096, "", "mdns")
        self.assertEqual(endpoint.scheme, "http")
        self.assertEqual(endpoint.host, "mac-mini.local")
        self.assertEqual(endpoint.port, 8096)
        self.assertEqual(endpoint.path, "")
        self.assertEqual(endpoint.hostKind, "mdns")
        self.assertIn(endpoint.hostKind, {"mdns", "lan-ip", "loopback"})
        address = services._endpoint_address(endpoint)
        self.assertEqual(address, "http://mac-mini.local:8096")
        self.assertEqual(services._host_kind("Mac-mini.local"), "mdns")
        self.assertEqual(services._host_kind("mac-mini.local"), "mdns")
        self.assertEqual(services._host_kind("192.168.5.28"), "lan-ip")
        self.assertEqual(services._host_kind("127.0.0.1"), "loopback")
        self.assertEqual(services._host_kind("localhost"), "loopback")

    def test_candidate_order_recorded_mdns_lan(self) -> None:
        world = World(
            {RECORDED: None, MDNS: IDENTITY, LAN: OTHER},
            lan=("192.168.5.28",),
            mdns=("mac-mini.local",),
        )
        receipt = _resolve(services, world, self.root / "order-mdns-first")
        self.assertEqual(receipt["address"], MDNS)
        self.assertEqual(receipt["hostKind"], "mdns")
        world2 = World(
            {RECORDED: None, MDNS: None, LAN: IDENTITY},
            lan=("192.168.5.28",),
            mdns=("mac-mini.local",),
        )
        receipt2 = _resolve(services, world2, self.root / "order-lan-fallback")
        self.assertEqual(receipt2["address"], LAN)
        self.assertEqual(receipt2["evidence"]["reason"], "lan-fallback")
        self.assertEqual(receipt2["hostKind"], "lan-ip")

    def test_recorded_ip_is_ignored(self) -> None:
        world = World(
            {RECORDED_IP: IDENTITY, MDNS: IDENTITY},
            lan=(),
            mdns=("mac-mini.local",),
            recorded=RECORDED_IP,
        )
        spec = world.spec(services, self.root / "ignored-ip" / "ensure-receipt.json")
        ordered = services.candidate_addresses(spec)
        addresses = [a for a, s in ordered]
        self.assertNotIn(RECORDED_IP, addresses)
        self.assertIn(MDNS, addresses)

    def test_resolve_lan_host_does_not_replace_name_with_ip(self) -> None:
        result = services.resolve_lan_host("Mac-mini.local")
        if result is not None:
            self.assertEqual(result, "Mac-mini.local")
        result2 = services.resolve_lan_host("mac-mini.local")
        if result2 is not None:
            self.assertEqual(result2, "mac-mini.local")
        self.assertEqual(services.resolve_lan_host("192.168.5.28"), "192.168.5.28")
        self.assertIsNone(services.resolve_lan_host("127.0.0.1"))
        self.assertIsNone(services.resolve_lan_host("localhost"))

    def test_receipt_contains_resolved_evidence_and_host_kind(self) -> None:
        world = World({MDNS: IDENTITY}, mdns=("mac-mini.local",), recorded=None)
        receipt = _resolve(services, world, self.root / "resolved-evidence")
        self.assertIn("hostKind", receipt)
        self.assertEqual(receipt["hostKind"], "mdns")
        self.assertIn("endpoint", receipt)
        self.assertEqual(receipt["endpoint"]["hostKind"], "mdns")
        self.assertEqual(receipt["endpoint"]["host"], "mac-mini.local")
        candidate = receipt["evidence"]["candidates"][0]
        self.assertIn("hostKind", candidate)
        self.assertEqual(candidate["hostKind"], "mdns")
        self.assertIn("resolvedAddresses", candidate)
        self.assertIsInstance(candidate["resolvedAddresses"], list)

    def test_lan_fallback_is_reported_with_reason(self) -> None:
        world = World(
            {LAN: IDENTITY},
            lan=("192.168.5.28",),
            recorded=None,
        )
        receipt = _resolve(services, world, self.root / "lan-fallback-reason")
        self.assertEqual(receipt["address"], LAN)
        self.assertEqual(receipt["hostKind"], "lan-ip")
        self.assertEqual(receipt["evidence"]["reason"], "lan-fallback")


def _neuter(fragment: str) -> str:
    header, _, _ = fragment.partition("\n")
    return header + "\n" + NEUTER


def _load_mutated(path: Path, source: str):
    path.write_text(source, encoding="utf-8")
    name = f"mutated_{path.stem.replace('-', '_')}"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


if __name__ == "__main__":
    unittest.main()
