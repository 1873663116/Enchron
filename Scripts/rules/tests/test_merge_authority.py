#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import merge_authority as authority
import merge_evidence_tier as tiers

TOOL = Path(__file__).resolve().parents[1] / "merge_authority.py"


class MergeAuthorityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="merge-authority-")
        self.addCleanup(self.scratch.cleanup)
        self.repository = Path(self.scratch.name)
        self.environment = {
            "PATH": os.environ["PATH"],
            "HOME": self.scratch.name,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        self.git("init", "-q")
        seed = self.commit("README.md", "seed")
        w0 = self.commit("docs/note.md", "docs")
        w1 = self.commit("Scripts/example.py", "print('test')")
        w2 = self.commit("Modules/Emby/Shelf.swift", "feature")
        w3 = self.commit("Modules/Playback/Runtime.swift", "playback")
        self.ranges = {
            tiers.W0: f"{seed}..{w0}",
            tiers.W1: f"{w0}..{w1}",
            tiers.W2: f"{w1}..{w2}",
            tiers.W3: f"{w2}..{w3}",
        }
        evidence = self.repository / ".evidence"
        evidence.mkdir()
        self.summary = evidence / "summary.json"
        self.summary.write_text(
            json.dumps({"verdict": "passed", "mode": "quick"}), encoding="utf-8"
        )
        self.simulator = evidence / "simulator"
        self.simulator.mkdir()
        (self.simulator / "result.json").write_text(
            json.dumps({"unit": "playback.controls-window", "passed": True}),
            encoding="utf-8",
        )
        self.device_hub = evidence / "device-hub"
        self.device_hub.mkdir()
        (self.device_hub / "probe.log").write_text(
            "spatialTap entity=EnchronWindowInput.surface accepted=true\n",
            encoding="utf-8",
        )
        (self.device_hub / "diagnostics.json").write_text(
            json.dumps({"mode": "windowed"}), encoding="utf-8"
        )
        self.real_device = evidence / "real-device.json"
        self.real_device.write_text(
            json.dumps({"capability": "hardware-decode", "passed": True}),
            encoding="utf-8",
        )

    def git(self, *arguments: str) -> str:
        completed = subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            capture_output=True,
            text=True,
            check=True,
            env=self.environment,
        )
        return completed.stdout.strip()

    def commit(self, name: str, content: str) -> str:
        path = self.repository / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        self.git("add", name)
        self.git("commit", "-q", "-m", name)
        return self.git("rev-parse", "HEAD")

    def evidence_for(self, tier: str) -> list[authority.EvidenceInput]:
        inputs = [
            authority.EvidenceInput(tiers.VERIFICATION_GREEN, self.summary)
        ]
        if tier in (tiers.W2, tiers.W3):
            inputs.append(
                authority.EvidenceInput(tiers.SIMULATOR_E2E, self.simulator)
            )
        if tier == tiers.W3:
            inputs.append(
                authority.EvidenceInput(tiers.DEVICE_HUB_INPUT, self.device_hub)
            )
        return inputs

    def approval_for(
        self, range_expression: str, kind: authority.ChangeKind
    ) -> Path:
        snapshot = authority.resolve_range(self.repository, range_expression)
        payload = authority.approval_payload(
            snapshot,
            (kind,),
            "reviewer@example.com",
            "decision://approved-governance-cutover",
        )
        path = self.repository / ".evidence" / f"approval-{kind.value}.json"
        path.write_bytes(authority.canonical_json(payload))
        return path

    def run_tool(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL), *arguments],
            capture_output=True,
            text=True,
            env=self.environment,
        )

    def test_change_kind_by_tier_cross_product(self) -> None:
        self.assertEqual(len(authority.ChangeKind), 8)
        for tier, range_expression in self.ranges.items():
            for kind in authority.ChangeKind:
                approval = (
                    self.approval_for(range_expression, kind)
                    if kind in authority.HUMAN_REVIEW_CHANGE_KINDS
                    else None
                )
                receipt = authority.build_run_receipt(
                    self.repository,
                    range_expression,
                    [kind],
                    self.evidence_for(tier),
                    approval,
                )
                self.assertEqual(receipt["tier"], tier)
                expected = (
                    authority.AuthorityDecision.AUTO_MERGE_ELIGIBLE.value
                    if kind in authority.AUTO_MERGE_CHANGE_KINDS
                    else authority.AuthorityDecision.HUMAN_REVIEW_REQUIRED.value
                )
                self.assertEqual(receipt["authority"]["decision"], expected)

    def test_human_review_kinds_never_become_auto_merge_eligible(self) -> None:
        for kind in authority.HUMAN_REVIEW_CHANGE_KINDS:
            for tier in tiers.TIERS:
                receipt = authority.build_run_receipt(
                    self.repository,
                    self.ranges[tier],
                    [kind],
                    self.evidence_for(tier),
                    self.approval_for(self.ranges[tier], kind),
                )
                self.assertEqual(
                    receipt["authority"]["decision"],
                    authority.AuthorityDecision.HUMAN_REVIEW_REQUIRED.value,
                )

    def test_mixed_change_kinds_take_human_review(self) -> None:
        kinds = (
            authority.ChangeKind.BUG_FIX,
            authority.ChangeKind.PUBLIC_API,
        )
        snapshot = authority.resolve_range(self.repository, self.ranges[tiers.W0])
        approval = self.repository / ".evidence" / "approval-mixed.json"
        approval.write_bytes(
            authority.canonical_json(
                authority.approval_payload(
                    snapshot, kinds, "reviewer", "decision://mixed"
                )
            )
        )
        receipt = authority.build_run_receipt(
            self.repository,
            self.ranges[tiers.W0],
            kinds,
            self.evidence_for(tiers.W0),
            approval,
        )
        self.assertEqual(
            receipt["authority"]["decision"],
            authority.AuthorityDecision.HUMAN_REVIEW_REQUIRED.value,
        )

    def test_missing_change_kind_fails_closed(self) -> None:
        with self.assertRaisesRegex(authority.AuthorityError, "undeclared semantic"):
            authority.build_run_receipt(
                self.repository,
                self.ranges[tiers.W0],
                [],
                self.evidence_for(tiers.W0),
            )

    def test_human_review_without_approval_fails_closed(self) -> None:
        with self.assertRaisesRegex(authority.AuthorityError, "missing authority"):
            authority.build_run_receipt(
                self.repository,
                self.ranges[tiers.W0],
                [authority.ChangeKind.NEW_FEATURE],
                self.evidence_for(tiers.W0),
            )

    def test_evidence_below_each_nonempty_tier_fails_closed(self) -> None:
        for tier in tiers.TIERS:
            with self.subTest(tier=tier):
                with self.assertRaisesRegex(authority.AuthorityError, "evidence below"):
                    authority.build_run_receipt(
                        self.repository,
                        self.ranges[tier],
                        [authority.ChangeKind.BUG_FIX],
                        [],
                    )

    def test_w3_real_device_decode_is_the_decode_capability_exception(self) -> None:
        receipt = authority.build_run_receipt(
            self.repository,
            self.ranges[tiers.W3],
            [authority.ChangeKind.BUG_FIX],
            [
                authority.EvidenceInput(tiers.VERIFICATION_GREEN, self.summary),
                authority.EvidenceInput(tiers.REAL_DEVICE_DECODE, self.real_device),
            ],
        )
        self.assertEqual(receipt["tier"], tiers.W3)

    def test_run_receipt_binds_artifact_bytes_and_detects_tampering(self) -> None:
        receipt = authority.build_run_receipt(
            self.repository,
            self.ranges[tiers.W2],
            [authority.ChangeKind.BUG_FIX],
            self.evidence_for(tiers.W2),
        )
        path = self.repository / ".evidence" / "run-receipt.json"
        path.write_bytes(authority.canonical_json(receipt))
        (self.simulator / "result.json").write_text("tampered", encoding="utf-8")
        completed = self.run_tool(
            "verify", "--repository", str(self.repository), "--receipt", str(path)
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("stale or tampered", completed.stderr)

    def test_run_receipt_detects_a_stale_symbolic_range(self) -> None:
        base = self.ranges[tiers.W3].split("..", 1)[0]
        expression = f"{base}..HEAD"
        receipt = authority.build_run_receipt(
            self.repository,
            expression,
            [authority.ChangeKind.BUG_FIX],
            self.evidence_for(tiers.W3),
        )
        path = self.repository / ".evidence" / "stale-receipt.json"
        path.write_bytes(authority.canonical_json(receipt))
        self.commit("Modules/Playback/Later.swift", "later")
        completed = self.run_tool(
            "verify", "--repository", str(self.repository), "--receipt", str(path)
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("stale or tampered", completed.stderr)

    def test_approval_receipt_is_bound_and_stale_approval_is_rejected(self) -> None:
        kind = authority.ChangeKind.PUBLIC_API
        approval = self.approval_for(self.ranges[tiers.W0], kind)
        changed_range = self.ranges[tiers.W1]
        with self.assertRaisesRegex(authority.AuthorityError, "stale"):
            authority.build_run_receipt(
                self.repository,
                changed_range,
                [kind],
                self.evidence_for(tiers.W1),
                approval,
            )

    def test_receipt_json_is_deterministic_and_binds_tool_environment(self) -> None:
        arguments = (
            self.repository,
            self.ranges[tiers.W2],
            [authority.ChangeKind.BEHAVIOR_PRESERVING_REFACTOR],
            self.evidence_for(tiers.W2),
        )
        first = authority.canonical_json(authority.build_run_receipt(*arguments))
        second = authority.canonical_json(authority.build_run_receipt(*arguments))
        self.assertEqual(first, second)
        payload = json.loads(first)
        self.assertRegex(payload["tool"]["sha256"], r"^[0-9a-f]{64}$")
        self.assertIn("python", payload["environment"])
        self.assertIn("git", payload["environment"])

    def test_no_w4_exists_or_can_be_injected_into_a_receipt(self) -> None:
        self.assertFalse(hasattr(tiers, "W4"))
        receipt = authority.build_run_receipt(
            self.repository,
            self.ranges[tiers.W0],
            [authority.ChangeKind.BUG_FIX],
            self.evidence_for(tiers.W0),
        )
        receipt["tier"] = "W4"
        path = self.repository / ".evidence" / "w4.json"
        path.write_bytes(authority.canonical_json(receipt))
        completed = self.run_tool(
            "verify", "--repository", str(self.repository), "--receipt", str(path)
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("stale or tampered", completed.stderr)

    def test_cli_has_no_manual_manifest_compatibility_path(self) -> None:
        completed = self.run_tool(
            "verify",
            "--receipt",
            "run-receipt.json",
            "--manifest",
            "old-v1.json",
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("unrecognized arguments", completed.stderr)

    def test_generated_receipt_round_trips_through_cli_verification(self) -> None:
        receipt = authority.build_run_receipt(
            self.repository,
            self.ranges[tiers.W3],
            [authority.ChangeKind.BUG_FIX],
            self.evidence_for(tiers.W3),
        )
        path = self.repository / ".evidence" / "valid.json"
        path.write_bytes(authority.canonical_json(receipt))
        completed = self.run_tool(
            "verify", "--repository", str(self.repository), "--receipt", str(path)
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("AutoMergeEligible", completed.stdout)

    def test_device_hub_probe_validation_has_no_legacy_journey_dependency(self) -> None:
        source = Path(authority.__file__).read_text(encoding="utf-8")
        self.assertNotIn("journey_units", source)
        (self.device_hub / "probe.log").write_text(
            "spatialTap entity=EnchronWindowInput.surface accepted=false\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(authority.AuthorityError, "accepted=true"):
            authority.evidence_record(
                self.repository,
                authority.EvidenceInput(tiers.DEVICE_HUB_INPUT, self.device_hub),
            )

    def test_cli_generates_and_binds_explicit_approval(self) -> None:
        approval = self.repository / ".evidence" / "cli-approval.json"
        receipt = self.repository / ".evidence" / "cli-receipt.json"
        range_expression = self.ranges[tiers.W0]
        approved = self.run_tool(
            "approve",
            range_expression,
            "--repository",
            str(self.repository),
            "--change-kind",
            authority.ChangeKind.NEW_FEATURE.value,
            "--authority",
            "reviewer@example.com",
            "--reference",
            "decision://new-feature",
            "--output",
            str(approval),
        )
        self.assertEqual(approved.returncode, 0, approved.stderr)
        generated = self.run_tool(
            "generate",
            range_expression,
            "--repository",
            str(self.repository),
            "--change-kind",
            authority.ChangeKind.NEW_FEATURE.value,
            "--evidence",
            f"{tiers.VERIFICATION_GREEN}={self.summary}",
            "--approval",
            str(approval),
            "--output",
            str(receipt),
        )
        self.assertEqual(generated.returncode, 0, generated.stderr)
        verified = self.run_tool(
            "verify",
            "--repository",
            str(self.repository),
            "--receipt",
            str(receipt),
        )
        self.assertEqual(verified.returncode, 0, verified.stderr)
        self.assertIn("HumanReviewRequired", verified.stdout)


if __name__ == "__main__":
    unittest.main()
