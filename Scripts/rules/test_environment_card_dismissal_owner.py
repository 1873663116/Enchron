#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VOLUME_ROOT = REPO / "Modules/Playback/Views/SenseZoneVolumeRoot.swift"
EXECUTOR = REPO / "Modules/Playback/Platform/SpatialPlatformEffectExecutor.swift"
REVISION = "environmentCardDismissalRequestRevision"


class EnvironmentCardDismissalOwnerTests(unittest.TestCase):
    def test_the_volume_dismisses_itself_on_the_debug_request(self) -> None:
        source = VOLUME_ROOT.read_text(encoding="utf-8")
        handler = re.search(
            rf"\.onChange\(of: appModel\.{REVISION}\)(.*?)\n#endif",
            source,
            re.S,
        )
        self.assertIsNotNone(handler, "SenseZoneVolumeRoot must observe the dismissal revision")
        body = handler.group(1)
        self.assertIn("dismissWindow(id: PlaybackSessionModel.senseZoneVolumeID)", body)
        self.assertIn("testcmd dismissEnvironmentCard delivered", body)
        self.assertNotIn("windowIdentity", body)

    def test_no_window_bound_handler_remains_in_the_executor(self) -> None:
        source = EXECUTOR.read_text(encoding="utf-8")
        self.assertNotIn(
            f".onChange(of: appModel.{REVISION})",
            source,
            "the handover dismisses the main window during docked playback, so a handler bound to it never fires",
        )


if __name__ == "__main__":
    unittest.main()
