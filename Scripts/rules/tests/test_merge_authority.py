#!/usr/bin/env python3

from __future__ import annotations

import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import merge_authority as authority
import merge_evidence_tier as tiers

TOOL = Path(__file__).resolve().parents[1] / "merge_authority.py"


class Completed:
    def __init__(self, returncode: int, stdout: str, stderr: str) -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def fixture_environment(directory: Path) -> dict[str, str]:
    return {
        "PATH": os.environ["PATH"],
        "HOME": str(directory),
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@example.com",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@example.com",
    }


def run_git(repository: Path, environment: dict[str, str], *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repository), *arguments],
        capture_output=True,
        text=True,
        check=True,
        env=environment,
    )
    return completed.stdout.strip()


def write_commit(
    repository: Path,
    environment: dict[str, str],
    name: str,
    content: str,
) -> str:
    path = repository / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    run_git(repository, environment, "add", name)
    run_git(repository, environment, "commit", "-q", "-m", name)
    return run_git(repository, environment, "rev-parse", "HEAD")


def build_repository(root: Path, environment: dict[str, str]) -> dict[str, str]:
    run_git(root, environment, "init", "-q")
    seed = write_commit(root, environment, "README.md", "seed")
    w0 = write_commit(root, environment, "docs/note.md", "docs")
    w1 = write_commit(root, environment, "Scripts/example.py", "print('test')")
    w2 = write_commit(root, environment, "Modules/MediaServer/Shelf.swift", "feature")
    w3 = write_commit(root, environment, "Modules/Playback/Runtime.swift", "playback")
    evidence = root / ".evidence"
    evidence.mkdir()
    (evidence / "summary.json").write_text(
        json.dumps({"verdict": "passed", "mode": "quick"}), encoding="utf-8"
    )
    simulator = evidence / "simulator"
    simulator.mkdir()
    (simulator / "result.json").write_text(
        json.dumps({"unit": "playback.controls-window", "passed": True}),
        encoding="utf-8",
    )
    device_hub = evidence / "device-hub"
    device_hub.mkdir()
    (device_hub / "probe.log").write_text(
        "spatialTap entity=EnchronWindowInput.surface accepted=true\n",
        encoding="utf-8",
    )
    (device_hub / "diagnostics.json").write_text(
        json.dumps({"mode": "windowed"}), encoding="utf-8"
    )
    (evidence / "real-device.json").write_text(
        json.dumps({"capability": "hardware-decode", "passed": True}),
        encoding="utf-8",
    )
    return {
        tiers.W0: f"{seed}..{w0}",
        tiers.W1: f"{w0}..{w1}",
        tiers.W2: f"{w1}..{w2}",
        tiers.W3: f"{w2}..{w3}",
    }


class MergeAuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template_scratch = tempfile.TemporaryDirectory(prefix="merge-authority-template-")
        cls.template = Path(cls.template_scratch.name)
        cls.template_environment = fixture_environment(cls.template)
        cls.ranges = build_repository(cls.template, cls.template_environment)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.template_scratch.cleanup()

    def setUp(self) -> None:
        self.scratch = tempfile.TemporaryDirectory(prefix="merge-authority-")
        self.addCleanup(self.scratch.cleanup)
        self.repository = Path(self.scratch.name)
        shutil.copytree(self.template, self.repository, dirs_exist_ok=True)
        self.environment = fixture_environment(self.repository)
        self.ranges = self.__class__.ranges
        evidence = self.repository / ".evidence"
        self.summary = evidence / "summary.json"
        self.simulator = evidence / "simulator"
        self.device_hub = evidence / "device-hub"
        self.real_device = evidence / "real-device.json"

    def git(self, *arguments: str) -> str:
        return run_git(self.repository, self.environment, *arguments)

    def commit(self, name: str, content: str) -> str:
        return write_commit(self.repository, self.environment, name, content)

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

    def run_tool(self, *arguments: str) -> "Completed":
        saved_argv = sys.argv
        saved_stdout = sys.stdout
        saved_stderr = sys.stderr
        out = io.StringIO()
        err = io.StringIO()
        code = 0
        try:
            sys.argv = [str(TOOL), *arguments]
            sys.stdout = out
            sys.stderr = err
            try:
                code = authority.main() or 0
            except SystemExit as exit_requested:
                code = int(exit_requested.code or 0)
        finally:
            sys.argv = saved_argv
            sys.stdout = saved_stdout
            sys.stderr = saved_stderr
        return Completed(code, out.getvalue(), err.getvalue())

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

    def test_device_hub_current_surface_gesture_delivery_preserves_w3_authority(self) -> None:
        lines = (
            "surfaceGesture input=begin entity=EnchronWindowInput.surface",
            "2026-10-11T12:00:00Z probeSequence=5 probeRetention=diagnostic probeSession=none "
            "surfaceGesture input=begin entity=EnchronDockedInput.surface",
            "2026-10-11T12:00:00Z surfaceGesture input=begin entity=EnchronPanoramaInput.front",
        )
        for line in lines:
            with self.subTest(line=line):
                (self.device_hub / "probe.log").write_text(line + "\n", encoding="utf-8")
                receipt = authority.build_run_receipt(
                    self.repository,
                    self.ranges[tiers.W3],
                    [authority.ChangeKind.BUG_FIX],
                    self.evidence_for(tiers.W3),
                )
                self.assertEqual(receipt["tier"], "W3")
                self.assertEqual(receipt["authority"]["decision"], "AutoMergeEligible")

    def test_device_hub_rejects_cancelled_injected_or_substituted_surface_input(self) -> None:
        lines = (
            "surfaceGesture input=cancel",
            "surfaceGesture input=end",
            "gesture.phase=holding effectiveRate=2",
            "surfaceGesture input=begin entity=Injected",
            "surfaceGesture input=begin entity=EnchronWindowInput.surface source=test",
            "injected surfaceGesture input=begin entity=EnchronWindowInput.surface",
            'test result="surfaceGesture input=begin entity=EnchronWindowInput.surface"',
            "surfaceGesture input=beginning entity=EnchronWindowInput.surface",
            "surfaceGesture input=begin entity=",
            "spatialTap entity=EnchronWindowInput.surface accepted=false",
            "injected spatialTap entity=EnchronWindowInput.surface accepted=true",
        )
        for line in lines:
            with self.subTest(line=line):
                (self.device_hub / "probe.log").write_text(line + "\n", encoding="utf-8")
                with self.assertRaises(authority.AuthorityError):
                    authority.build_run_receipt(
                        self.repository,
                        self.ranges[tiers.W3],
                        [authority.ChangeKind.BUG_FIX],
                        self.evidence_for(tiers.W3),
                    )

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
