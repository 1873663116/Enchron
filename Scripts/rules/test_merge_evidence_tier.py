#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GIT_REDIRECTS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_PREFIX",
    "GIT_QUARANTINE_PATH",
)
"""Outrank cwd, so a fixture repository built under them is not the one built."""
import merge_evidence_tier as tiers

TOOL = Path(__file__).resolve().parent / "merge_evidence_tier.py"


class PathTierTests(unittest.TestCase):
    def assertTier(self, path: str, tier: str, rule: str | None = None) -> None:
        found = tiers.classify_path(path)
        self.assertEqual(found.tier, tier, path)
        if rule is not None:
            self.assertEqual(found.rule, rule, path)

    def test_path_mapping_uses_only_w0_through_w3(self) -> None:
        self.assertEqual(tiers.TIERS, ("W0", "W1", "W2", "W3"))
        self.assertNotIn("W4", tiers.TIERS)
        for path, expected in (
            ("docs/CONTEXT.md", tiers.W0),
            (".agents/skills/vp-e2e/SKILL.md", tiers.W0),
            ("Regression/promises/playback.md", tiers.W1),
            ("Scripts/rules/check.py", tiers.W1),
            ("Config/baseline.json", tiers.W1),
            ("Tests/ProbeTests.swift", tiers.W1),
            ("Packages/PlaybackCore/Tests/CoreTests/A.swift", tiers.W1),
            ("Modules/Emby/Client.swift", tiers.W2),
            ("Modules/MediaLibrary/Grid.swift", tiers.W2),
            ("Modules/DesignSystem/Tokens.swift", tiers.W2),
            ("Modules/MediaSource/Stream.swift", tiers.W2),
            ("Apps/Enchron/MainView.swift", tiers.W3),
            ("Apps/Enchron/Screens/PlayerScreen.swift", tiers.W2),
            ("Modules/Playback/Runtime.swift", tiers.W3),
            ("Packages/PlaybackCore/Sources/Core/A.swift", tiers.W3),
            ("Packages/OceanEnvironment/Package.swift", tiers.W3),
        ):
            self.assertTier(path, expected)

    def test_longest_prefix_keeps_the_screens_directory_at_w2(self) -> None:
        self.assertTier(
            "Apps/Enchron/Screens/PlayerScreen.swift",
            tiers.W2,
            "Apps/Enchron/Screens/",
        )
        self.assertTier("Apps/Enchron/AppModel.swift", tiers.W3, "Apps/Enchron/")

    def test_longest_prefix_keeps_playback_core_tests_at_w1(self) -> None:
        self.assertTier(
            "Packages/PlaybackCore/Tests/CoreTests/A.swift",
            tiers.W1,
            "Packages/PlaybackCore/Tests/",
        )

    def test_unmapped_paths_fail_up_to_w3(self) -> None:
        self.assertTier("AGENTS.md", tiers.W3, tiers.UNCLASSIFIED_RULE)


class VerdictTests(unittest.TestCase):
    def test_mixed_range_takes_the_highest_evidence_tier(self) -> None:
        verdict = tiers.build_verdict(
            "a..b", ["docs/x.md", "Tests/y.swift", "Modules/Emby/z.swift"]
        )
        self.assertEqual(verdict.tier, tiers.W2)

    def test_tier_payload_contains_no_merge_authority_decision(self) -> None:
        payload = tiers.verdict_payload(tiers.build_verdict("a..b", ["docs/x.md"]))
        self.assertEqual(payload["tier"], tiers.W0)
        self.assertNotIn("freeMerge", payload)
        self.assertNotIn("authority", payload)

    def test_empty_range_has_no_evidence_tier(self) -> None:
        verdict = tiers.build_verdict("a..a", [])
        self.assertIsNone(verdict.tier)
        self.assertIn("empty range", verdict.reason)

    def test_unresolved_default_range_fails_up_to_w3(self) -> None:
        verdict = tiers.unresolved_verdict("@{upstream}..HEAD", "no upstream")
        self.assertEqual(verdict.tier, tiers.W3)
        self.assertIn("raised", verdict.reason)


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
            cls.commit({"Modules/Emby/Shelf.swift": "feature"}),
            cls.commit({"Modules/Playback/Scene.swift": "playback"}),
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

    def classify(self, range_expression: str | None = None) -> tuple[int, dict[str, object]]:
        command = [
            sys.executable,
            str(TOOL),
            "--repository",
            str(self.repository),
            "--json",
        ]
        if range_expression is not None:
            command.append(range_expression)
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            env=self.environment,
        )
        return completed.returncode, json.loads(completed.stdout) if completed.stdout else {}

    def test_cli_reports_evidence_strength_without_merge_authority(self) -> None:
        expected = (tiers.W0, tiers.W2, tiers.W3)
        for index, tier in enumerate(expected):
            code, payload = self.classify(
                f"{self.revisions[index]}..{self.revisions[index + 1]}"
            )
            self.assertEqual(code, 0)
            self.assertEqual(payload["tier"], tier)
            self.assertNotIn("freeMerge", payload)

    def test_default_unresolved_range_fails_up_but_does_not_break_structure_check(self) -> None:
        code, payload = self.classify()
        self.assertEqual(code, 0)
        self.assertEqual(payload["tier"], tiers.W3)

    def test_manual_manifest_option_has_no_compatibility_path(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(TOOL), "--manifest", "manifest.json"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("unrecognized arguments", completed.stderr)


if __name__ == "__main__":
    unittest.main()
