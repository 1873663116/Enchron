#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "verification"))

import journey_units
import merge_evidence_tier as tiers

TOOL = Path(__file__).resolve().parent / "merge_evidence_tier.py"


class PathTierTests(unittest.TestCase):
    def assertTier(self, path: str, tier: str, rule: str | None = None) -> None:
        found = tiers.classify_path(path)
        self.assertEqual(found.tier, tier, path)
        if rule is not None:
            self.assertEqual(found.rule, rule, path)

    def test_prose_is_w0(self) -> None:
        self.assertTier("docs/CONTEXT.md", tiers.W0)
        self.assertTier(".agents/skills/vp-e2e/SKILL.md", tiers.W0)

    def test_what_the_build_and_test_stage_covers_is_w1(self) -> None:
        self.assertTier("Tests/PlaybackPresentationTests/File.swift", tiers.W1)
        self.assertTier("Packages/PlaybackCore/Tests/CoreTests/File.swift", tiers.W1)
        self.assertTier("Scripts/verification/journey_units.py", tiers.W1, "Scripts/")
        self.assertTier("Scripts/rules/verify_glass_usage.py", tiers.W1, "Scripts/")
        self.assertTier("Config/verification_baseline.json", tiers.W1, "Config/")

    def test_what_a_simulator_journey_can_settle_is_w2(self) -> None:
        self.assertTier("Modules/Emby/EmbyClient.swift", tiers.W2)
        self.assertTier("Modules/MediaLibrary/Views/Grid.swift", tiers.W2)
        self.assertTier("Modules/DesignSystem/DesignTokens.swift", tiers.W2)
        self.assertTier("Modules/MediaSource/MediaByteStream.swift", tiers.W2)

    def test_what_needs_real_input_or_real_decoding_is_w3(self) -> None:
        self.assertTier("Apps/Enchron/MainView.swift", tiers.W3)
        self.assertTier("Modules/Playback/PlaybackRuntime.swift", tiers.W3)
        self.assertTier("Modules/Playback/Scenes/A.swift", tiers.W3)
        self.assertTier("Packages/PlaybackCore/Sources/Core/A.swift", tiers.W3)
        self.assertTier("Packages/RealityKitContent/Package.swift", tiers.W3)

    def test_config_is_enforcement_state_and_never_w0(self) -> None:
        self.assertTier(
            "Config/journey_operation_coverage.json", tiers.W1, "Config/"
        )
        self.assertTier("Config/swiftlint_baseline.json", tiers.W1, "Config/")

    def test_an_unmapped_path_up_levels_to_w3(self) -> None:
        self.assertTier("Mystery/file.txt", tiers.W3, tiers.UNCLASSIFIED_RULE)
        self.assertTier("AGENTS.md", tiers.W3, tiers.UNCLASSIFIED_RULE)
        self.assertTier("Enchron.xctestplan", tiers.W3, tiers.UNCLASSIFIED_RULE)
        self.assertTier(".githooks/pre-push", tiers.W3, tiers.UNCLASSIFIED_RULE)

    def test_the_package_test_prefix_beats_the_package_prefix(self) -> None:
        self.assertTier(
            "Packages/PlaybackCore/Tests/CoreTests/A.swift",
            tiers.W1,
            "Packages/PlaybackCore/Tests/",
        )


class VerdictTests(unittest.TestCase):
    def test_a_mixed_range_takes_the_highest_tier(self) -> None:
        verdict = tiers.build_verdict(
            "a..b", ["docs/x.md", "Tests/y.swift", "Modules/Emby/z.swift"]
        )
        self.assertEqual(verdict.tier, tiers.W2)
        self.assertFalse(verdict.free_merge)

    def test_w0_and_w1_are_free_merge_and_say_so(self) -> None:
        for paths, tier in (
            (["docs/x.md"], tiers.W0),
            (["docs/x.md", "Tests/y.swift"], tiers.W1),
        ):
            verdict = tiers.build_verdict("a..b", paths)
            self.assertEqual(verdict.tier, tier)
            self.assertTrue(verdict.free_merge)
            self.assertIn(
                f"verdict: {tiers.FREE_MERGE_PHRASE}", tiers.render(verdict)
            )

    def test_w2_and_w3_are_review_required_with_their_evidence_list(self) -> None:
        verdict = tiers.build_verdict(
            "a..b", ["Modules/Playback/Scenes/A.swift"]
        )
        self.assertEqual(verdict.tier, tiers.W3)
        self.assertFalse(verdict.free_merge)
        rendered = "\n".join(tiers.render(verdict))
        self.assertIn(tiers.REVIEW_PHRASE, rendered)
        self.assertIn(tiers.VERIFICATION_GREEN, rendered)
        self.assertIn(tiers.SIMULATOR_E2E, rendered)
        self.assertIn(tiers.PROBE_CONTRACT_SHAPE, rendered)

    def test_an_empty_range_judges_nothing_and_passes(self) -> None:
        verdict = tiers.build_verdict("a..a", [])
        self.assertIsNone(verdict.tier)
        self.assertTrue(verdict.free_merge)
        self.assertIn("empty range", verdict.reason)

    def test_an_unresolved_range_up_levels_instead_of_failing(self) -> None:
        verdict = tiers.unresolved_verdict("@{upstream}..HEAD", "no upstream")
        self.assertEqual(verdict.tier, tiers.W3)
        self.assertFalse(verdict.free_merge)
        self.assertIn("up-leveled", verdict.reason)

    def test_the_evidence_table_matches_the_approved_tiers(self) -> None:
        self.assertEqual(
            tiers.TIER_EVIDENCE[tiers.W0], (tiers.VERIFICATION_GREEN,)
        )
        self.assertEqual(
            tiers.TIER_EVIDENCE[tiers.W1], (tiers.VERIFICATION_GREEN,)
        )
        self.assertEqual(
            tiers.TIER_EVIDENCE[tiers.W2],
            (tiers.VERIFICATION_GREEN, tiers.SIMULATOR_E2E),
        )
        self.assertEqual(
            tiers.TIER_EVIDENCE[tiers.W3],
            (tiers.VERIFICATION_GREEN, tiers.SIMULATOR_E2E, tiers.DEVICE_HUB_INPUT),
        )
        self.assertEqual(
            tiers.FREE_MERGE_ENABLED_TIERS, (tiers.W0, tiers.W1)
        )


def device_hub_unit() -> str:
    registered = tiers.registered_device_hub_units()
    return sorted(registered)[0]


def w3_manifest() -> dict[str, object]:
    return {
        "version": 1,
        "range": "a..b",
        "declaredTier": "W3",
        "verification": {
            "runDirectory": ".scratch/Verification/runs/20260825T000000Z-1",
            "summary": ".scratch/Verification/runs/20260825T000000Z-1/summary.json",
            "verdict": "passed",
            "mode": "quick",
        },
        "simulatorE2E": [
            {
                "unit": device_hub_unit(),
                "artifacts": [".scratch/e2e/controls-window/run1"],
            }
        ],
        "deviceHubInput": [
            {
                "unit": device_hub_unit(),
                "target": "PlayerUI-window-playback-surface",
                "entity": "EnchronWindowInput.surface",
                "probe": "spatialTap entity=EnchronWindowInput.surface accepted=true",
                "probeLog": "TestEvidence/device-hub/probe-lines.log",
                "diagnostics": "TestEvidence/device-hub/diagnostics.json",
            }
        ],
    }


class ManifestTests(unittest.TestCase):
    def test_a_complete_w3_manifest_is_sufficient(self) -> None:
        self.assertEqual(tiers.manifest_complaints(w3_manifest(), tiers.W3), [])

    def test_the_probe_contract_predicate_is_the_journey_units_one(self) -> None:
        self.assertTrue(
            journey_units.probe_matches_contract(
                "EnchronWindowInput.surface",
                "spatialTap entity=EnchronWindowInput.surface accepted=true",
            )
        )
        self.assertFalse(
            journey_units.probe_matches_contract(
                "EnchronWindowInput.surface",
                "toggle source=channel showControls=true",
            )
        )

    def test_a_channel_style_probe_is_rejected(self) -> None:
        manifest = w3_manifest()
        manifest["deviceHubInput"][0]["probe"] = (
            "toggle source=channel showControls=true"
        )
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("spatialTap" in item for item in complaints))

    def test_a_probe_for_another_entity_is_rejected(self) -> None:
        manifest = w3_manifest()
        manifest["deviceHubInput"][0]["probe"] = (
            "spatialTap entity=SomethingElse accepted=true"
        )
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("spatialTap" in item for item in complaints))

    def test_an_unregistered_unit_is_rejected(self) -> None:
        manifest = w3_manifest()
        manifest["deviceHubInput"][0]["unit"] = "made.up-unit"
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(
            any("registered device-hub unit" in item for item in complaints)
        )

    def test_w3_without_device_hub_or_decode_evidence_is_insufficient(self) -> None:
        manifest = w3_manifest()
        del manifest["deviceHubInput"]
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("W3 needs" in item for item in complaints))

    def test_a_decode_capability_exception_carries_its_own_evidence(self) -> None:
        manifest = w3_manifest()
        del manifest["deviceHubInput"]
        del manifest["simulatorE2E"]
        manifest["realDeviceDecode"] = [
            {
                "capability": "dolby-vision-profile-20",
                "reason": "decoder behaviour only exists on device",
                "evidence": ["TestEvidence/decode/dovi-p20-report.json"],
            }
        ]
        self.assertEqual(tiers.manifest_complaints(manifest, tiers.W3), [])

    def test_a_decode_exception_without_evidence_is_insufficient(self) -> None:
        manifest = w3_manifest()
        del manifest["deviceHubInput"]
        manifest["realDeviceDecode"] = [{"capability": "x", "reason": ""}]
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("realDeviceDecode[0]" in item for item in complaints))

    def test_a_failed_verification_is_never_evidence(self) -> None:
        manifest = w3_manifest()
        manifest["verification"]["verdict"] = "failed"
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("verification.verdict" in item for item in complaints))

    def test_declaring_below_the_computed_tier_is_rejected(self) -> None:
        manifest = w3_manifest()
        manifest["declaredTier"] = "W1"
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(any("only declare upward" in item for item in complaints))

    def test_declaring_above_the_computed_tier_is_allowed(self) -> None:
        self.assertEqual(tiers.manifest_complaints(w3_manifest(), tiers.W0), [])

    def test_a_w0_manifest_needs_only_the_verification(self) -> None:
        manifest = {
            "version": 1,
            "declaredTier": "W0",
            "verification": {
                "runDirectory": ".scratch/Verification/runs/x",
                "summary": ".scratch/Verification/runs/x/summary.json",
                "verdict": "passed",
            },
        }
        self.assertEqual(tiers.manifest_complaints(manifest, tiers.W0), [])

    def test_missing_simulator_artifacts_are_named(self) -> None:
        manifest = w3_manifest()
        manifest["simulatorE2E"] = [{"unit": device_hub_unit(), "artifacts": []}]
        complaints = tiers.manifest_complaints(manifest, tiers.W3)
        self.assertTrue(
            any("simulatorE2E[0].artifacts" in item for item in complaints)
        )


class CommitRangeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.scratch = tempfile.TemporaryDirectory(prefix="merge-evidence-tier-")
        cls.repository = Path(cls.scratch.name)
        cls.environment = {
            "PATH": os.environ["PATH"],
            "HOME": cls.scratch.name,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        cls.git("init", "-q")
        cls.revisions = [
            cls.commit({"README.md": "seed"}),
            cls.commit({"docs/note.md": "docs"}),
            cls.commit({"Tests/Probe/ProbeTests.swift": "test"}),
            cls.commit({"Modules/Emby/EmbyShelf.swift": "feature"}),
            cls.commit(
                {
                    "docs/more.md": "docs",
                    "Modules/Playback/Scenes/Scene.swift": "playback",
                }
            ),
            cls.commit(
                {
                    "Scripts/verification/tool.py": "tool",
                    "Config/some_baseline.json": "{}",
                }
            ),
            cls.commit({"Mystery/file.txt": "unknown"}),
        ]

    @classmethod
    def tearDownClass(cls) -> None:
        cls.scratch.cleanup()

    @classmethod
    def git(cls, *arguments: str) -> str:
        completed = subprocess.run(
            ["git", "-C", str(cls.repository), *arguments],
            capture_output=True,
            text=True,
            check=True,
            env=cls.environment,
        )
        return completed.stdout.strip()

    @classmethod
    def commit(cls, files: dict[str, str]) -> str:
        for name, content in files.items():
            path = cls.repository / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        cls.git("add", "-A")
        cls.git("commit", "-q", "-m", "step")
        return cls.git("rev-parse", "HEAD")

    def classify(self, *arguments: str) -> tuple[int, dict[str, object]]:
        completed = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "--repository",
                str(self.repository),
                "--json",
                *arguments,
            ],
            capture_output=True,
            text=True,
            env=self.environment,
        )
        payload = json.loads(completed.stdout) if completed.stdout else {}
        return completed.returncode, payload

    def test_a_docs_only_range_is_w0_free_merge(self) -> None:
        code, payload = self.classify(f"{self.revisions[0]}..{self.revisions[1]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W0")
        self.assertTrue(payload["freeMerge"])

    def test_a_tests_only_range_is_w1_free_merge(self) -> None:
        code, payload = self.classify(f"{self.revisions[1]}..{self.revisions[2]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W1")
        self.assertTrue(payload["freeMerge"])

    def test_a_feature_module_range_is_w2_review(self) -> None:
        code, payload = self.classify(f"{self.revisions[2]}..{self.revisions[3]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W2")
        self.assertFalse(payload["freeMerge"])

    def test_a_mixed_docs_and_playback_range_is_w3(self) -> None:
        code, payload = self.classify(f"{self.revisions[3]}..{self.revisions[4]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W3")
        self.assertFalse(payload["freeMerge"])

    def test_a_scripts_and_config_range_lands_on_w1(self) -> None:
        code, payload = self.classify(f"{self.revisions[4]}..{self.revisions[5]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W1")
        rules = {entry["path"]: entry["rule"] for entry in payload["paths"]}
        self.assertEqual(rules["Config/some_baseline.json"], "Config/")
        self.assertEqual(rules["Scripts/verification/tool.py"], "Scripts/")

    def test_an_unmapped_path_up_levels_through_the_cli(self) -> None:
        code, payload = self.classify(f"{self.revisions[5]}..{self.revisions[6]}")
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W3")
        self.assertEqual(
            payload["paths"][0]["rule"], tiers.UNCLASSIFIED_RULE
        )

    def test_an_empty_range_reports_nothing_to_judge(self) -> None:
        code, payload = self.classify(f"{self.revisions[1]}..{self.revisions[1]}")
        self.assertEqual(code, 0)
        self.assertIsNone(payload["tier"])
        self.assertTrue(payload["freeMerge"])

    def test_a_repo_without_upstream_up_levels_and_still_exits_zero(self) -> None:
        code, payload = self.classify()
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], "W3")
        self.assertFalse(payload["freeMerge"])
        self.assertIn("up-leveled", payload["reason"])

    def test_an_explicit_bad_range_is_a_usage_error(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "--repository",
                str(self.repository),
                "no-such..range",
            ],
            capture_output=True,
            text=True,
            env=self.environment,
        )
        self.assertEqual(completed.returncode, 2)

    def test_the_manifest_flag_judges_sufficiency_end_to_end(self) -> None:
        manifest_path = self.repository / "manifest.json"
        manifest_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "declaredTier": "W0",
                    "verification": {
                        "runDirectory": ".scratch/Verification/runs/x",
                        "summary": ".scratch/Verification/runs/x/summary.json",
                        "verdict": "passed",
                    },
                }
            ),
            encoding="utf-8",
        )
        completed = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "--repository",
                str(self.repository),
                f"{self.revisions[0]}..{self.revisions[1]}",
                "--manifest",
                str(manifest_path),
            ],
            capture_output=True,
            text=True,
            env=self.environment,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        insufficient = subprocess.run(
            [
                sys.executable,
                str(TOOL),
                "--repository",
                str(self.repository),
                f"{self.revisions[3]}..{self.revisions[4]}",
                "--manifest",
                str(manifest_path),
            ],
            capture_output=True,
            text=True,
            env=self.environment,
        )
        self.assertEqual(insufficient.returncode, 1)
        self.assertIn("only declare upward", insufficient.stdout)


class VerificationRegistrationTests(unittest.TestCase):
    def test_the_verification_runs_the_classifier_and_its_tests_in_quick_mode(self) -> None:
        import run_verification as verification

        registered = {
            check.identifier: check
            for check in verification.STRUCTURE_CHECKS + verification.discovered_test_checks()
        }
        self.assertIn("merge-evidence-tier", registered)
        self.assertIn("test-merge-evidence-tier", registered)
        self.assertEqual(
            registered["merge-evidence-tier"].filename, "merge_evidence_tier.py"
        )
        self.assertEqual(
            registered["test-merge-evidence-tier"].filename,
            "test_merge_evidence_tier.py",
        )
        self.assertTrue(registered["merge-evidence-tier"].runs_in_quick_mode)
        self.assertTrue(registered["test-merge-evidence-tier"].runs_in_quick_mode)

    def test_the_gate_never_turns_a_w3_range_into_a_failure(self) -> None:
        repository = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, repository, ignore_errors=True)
        run = lambda *arguments: subprocess.run(
            ["git", *arguments], cwd=repository, capture_output=True, text=True, check=True
        )
        run("init", "--quiet")
        run("config", "user.email", "verification@enchron.invalid")
        run("config", "user.name", "verification")
        for name, body in (
            ("README.md", "seed"),
            ("Modules/Playback/PlaybackRuntime.swift", "pipeline"),
        ):
            path = repository / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
            run("add", "--all")
            run("commit", "--quiet", "--message", name)

        completed = subprocess.run(
            [sys.executable, str(TOOL), "--repository", str(repository), "HEAD^..HEAD"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("W3", completed.stdout)
        self.assertIn(tiers.REVIEW_PHRASE, completed.stdout)


if __name__ == "__main__":
    unittest.main()
