from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import machine
import reuse


DEVICE_LIST = """Name                       Hostname   Identifier                                    State                Model
------------------------   --------   -------------------------------------------   ------------------   -----------------------------------
Enchron Gestures                      9D09E501-89EC-47AD-96ED-CDCB1D62A3BF (UDID)   connected            Apple Vision Pro (RealityDevice14,1)   simulated
HUAWEI Mate70 Pro                     00008140-00115D022698801C (UDID)              available (paired)   iPhone 16 Pro (iPhone17,1)             physical
小坏滴柳橙红茶的Apple Vision Pro        00008142-001871A11491401C (UDID)              available (paired)   Apple Vision Pro (RealityDevice17,1)   physical
"""


class PhysicalDeviceTests(unittest.TestCase):
    def test_reads_the_paired_vision_pro(self) -> None:
        self.assertEqual(
            machine.parse_physical_vision_pro(DEVICE_LIST),
            "00008142-001871A11491401C",
        )

    def test_ignores_a_simulator(self) -> None:
        rows = "\n".join(DEVICE_LIST.splitlines()[:3]) + "\n"
        self.assertIsNone(machine.parse_physical_vision_pro(rows))

    def test_ignores_a_paired_phone(self) -> None:
        rows = "\n".join(
            [
                DEVICE_LIST.splitlines()[0],
                DEVICE_LIST.splitlines()[2],
            ]
        ) + "\n"
        self.assertIsNone(machine.parse_physical_vision_pro(rows))


class ReuseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        (self.root / "Apps").mkdir()
        (self.root / "Apps" / "Main.swift").write_text("let value = 1\n")
        self.evidence = self.root / "TestEvidence" / "console"
        self.unit = "unit:app.relaunch@1"
        self.directory = self.evidence / "unit-app.relaunch@1" / "2026-01-01T00-00-00"
        self.directory.mkdir(parents=True)

    def write_report(self, verdict: str, digest: str, product: str) -> None:
        payload = {
            "unit": self.unit,
            "digest": digest,
            "productDigest": product,
            "verdict": verdict,
        }
        (self.directory / "report.json").write_text(json.dumps(payload))

    def test_reuses_a_matching_passing_run(self) -> None:
        product = reuse.product_digest(self.root)
        self.write_report("passed", "plan-1", product)
        report = reuse.reusable_report(self.evidence, self.unit, "plan-1", product)
        self.assertIsNotNone(report)
        self.assertEqual(report["verdict"], "passed")

    def test_refuses_a_different_plan(self) -> None:
        product = reuse.product_digest(self.root)
        self.write_report("passed", "plan-1", product)
        self.assertIsNone(
            reuse.reusable_report(self.evidence, self.unit, "plan-2", product)
        )

    def test_refuses_a_changed_product(self) -> None:
        product = reuse.product_digest(self.root)
        self.write_report("passed", "plan-1", product)
        (self.root / "Apps" / "Main.swift").write_text("let value = 2\n")
        changed = reuse.product_digest(self.root)
        self.assertNotEqual(changed, product)
        self.assertIsNone(reuse.reusable_report(self.evidence, self.unit, "plan-1", changed))

    def test_refuses_a_failed_run(self) -> None:
        product = reuse.product_digest(self.root)
        self.write_report("failed", "plan-1", product)
        self.assertIsNone(reuse.reusable_report(self.evidence, self.unit, "plan-1", product))

    def test_passing_evidence_gates_an_assumption(self) -> None:
        product = reuse.product_digest(self.root)
        self.write_report("passed", "plan-1", product)
        self.assertTrue(reuse.passing_evidence(self.evidence, self.unit, "plan-1"))
        self.assertFalse(reuse.passing_evidence(self.evidence, self.unit, "plan-2"))

    def test_unknown_assumptions_are_reported(self) -> None:
        preconditions = ({"kind": "media-server", "provider": "emby"},)
        self.assertEqual(
            reuse.unknown_assumptions(preconditions, {"media-server:emby", "media-source"}),
            ["media-source"],
        )

    def test_assumed_preconditions_are_marked(self) -> None:
        preconditions = (
            {"kind": "media-server", "provider": "emby"},
            {"kind": "media-progress"},
        )
        outcomes, unknown = reuse.assumed_preconditions(preconditions, {"media-server:emby"})
        self.assertEqual(unknown, [])
        self.assertEqual(len(outcomes), 1)
        self.assertEqual(outcomes[0]["action"], "assumed")
        self.assertTrue(outcomes[0]["ok"])


if __name__ == "__main__":
    unittest.main()
