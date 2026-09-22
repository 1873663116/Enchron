#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "verification"))

from harness import pre_live


class PreLiveGateTests(unittest.TestCase):
    def test_a_red_offline_check_is_reported_so_the_live_run_refuses(self) -> None:
        planted = "test_emby_hang_recovery.py"

        def runner(path: Path) -> int:
            return 1 if path.name == planted else 0

        failed = pre_live.failing_pre_live_checks(runner=runner)
        self.assertIn(planted, failed)
        self.assertTrue(pre_live.refusal_reason(failed))

    def test_all_green_yields_no_refusal(self) -> None:
        failed = pre_live.failing_pre_live_checks(runner=lambda path: 0)
        self.assertEqual(failed, [])

    def test_manifest_keeps_the_core_harness_logic_checks(self) -> None:
        for required in pre_live.REQUIRED_CHECKS:
            self.assertIn(required, pre_live.PRE_LIVE_CHECKS)
        for name in pre_live.PRE_LIVE_CHECKS:
            self.assertTrue((pre_live.RULES_DIRECTORY / name).exists(), name)

    def test_disabled_only_under_replay_or_explicit_skip(self) -> None:
        saved = {
            key: os.environ.pop(key, None)
            for key in ("ENCHRON_REPLAY", "ENCHRON_SKIP_PRELIVE")
        }
        try:
            self.assertFalse(pre_live.pre_live_disabled())
            os.environ["ENCHRON_REPLAY"] = "1"
            self.assertTrue(pre_live.pre_live_disabled())
            del os.environ["ENCHRON_REPLAY"]
            os.environ["ENCHRON_SKIP_PRELIVE"] = "1"
            self.assertTrue(pre_live.pre_live_disabled())
        finally:
            del os.environ["ENCHRON_SKIP_PRELIVE"]
            for key, value in saved.items():
                if value is not None:
                    os.environ[key] = value


if __name__ == "__main__":
    unittest.main()
