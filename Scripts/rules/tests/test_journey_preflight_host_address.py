#!/usr/bin/env python3
from __future__ import annotations
import sys
from pathlib import Path
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import journey_preflight


class HostAddressTests(unittest.TestCase):
    def test_host_address_returns_mdns_host_kind_when_name_resolves(self) -> None:
        result = journey_preflight.host_address()
        self.assertIsInstance(result, journey_preflight.HostAddress)
        self.assertIn(result.hostKind, {"mdns", "loopback"})
        if result.hostKind == "mdns":
            self.assertTrue(result.host.endswith(".local"))
        else:
            self.assertEqual(result.host, "127.0.0.1")

    def test_host_address_prefers_mdns_over_loopback(self) -> None:
        with mock.patch.object(journey_preflight, "_mdns_hostnames", return_value=("Mac-mini.local", "other.local")):
            with mock.patch.object(journey_preflight, "_host_resolves", side_effect=lambda h: h == "Mac-mini.local"):
                result = journey_preflight.host_address()
                self.assertEqual(result.host, "Mac-mini.local")
                self.assertEqual(result.hostKind, "mdns")

    def test_host_address_falls_back_to_loopback_when_no_name_resolves(self) -> None:
        with mock.patch.object(journey_preflight, "_mdns_hostnames", return_value=("Mac-mini.local",)):
            with mock.patch.object(journey_preflight, "_host_resolves", return_value=False):
                result = journey_preflight.host_address()
                self.assertEqual(result.host, "127.0.0.1")
                self.assertEqual(result.hostKind, "loopback")

    def test_host_address_shape_is_not_silent_string(self) -> None:
        result = journey_preflight.host_address()
        self.assertTrue(hasattr(result, "host"))
        self.assertTrue(hasattr(result, "hostKind"))
        self.assertIsInstance(result.host, str)
        self.assertIsInstance(result.hostKind, str)

    def test_check_smb_uses_host_address_host(self) -> None:
        import regression_smb_source as smb
        expected = {"schema": smb.REPORT_SCHEMA, "check": "smb-aggregate", "ready": True}
        host_value = journey_preflight.HostAddress(host="Mac-mini.local", hostKind="mdns")
        with mock.patch.object(journey_preflight, "host_address", return_value=host_value):
            with mock.patch.object(journey_preflight.smb_source, "run_preflight", return_value=expected) as run:
                self.assertEqual(journey_preflight.check_smb(), expected)
            configuration = run.call_args.args[0]
            self.assertEqual(configuration.address, "Mac-mini.local")


if __name__ == "__main__":
    unittest.main()
