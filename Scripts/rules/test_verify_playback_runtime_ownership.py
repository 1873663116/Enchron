#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

RULES = Path(__file__).resolve().parent
if str(RULES) not in sys.path:
    sys.path.insert(0, str(RULES))

import verify_playback_runtime_ownership as checker


CLEAN_RUNTIME = """import Foundation

@MainActor
public final class PlaybackRuntime {
    private let coordinator: RendererTransferCoordinator
    private let interpreter: MediaFormatInterpreter

    public private(set) var lifecycle: PlaybackLifecycle = .idle

    public func play() {
        coordinator.resume()
    }
}
"""

CLEAN_INTERPRETER = """import Foundation

public struct MediaFormatInterpreter {
    public func interpret(_ declaration: MediaFormatDeclaration) -> MediaFormatProjection {
        MediaFormatProjection(declaration: declaration)
    }
}
"""

CLEAN_COORDINATOR = """import Foundation

@MainActor
public final class PlaybackLaunchCoordinator {
    public func stopPlayback(reason: PlaybackLeaveReason) {
        playbackRuntime.leavePlayback(reason: reason)
    }
}
"""

CLEAN_PAGE = """import SwiftUI

enum BrowserWindowSurfacePolicy {
    static func showsBrowser(
        residency: PlaybackResidency,
        transitionIsActive: Bool
    ) -> Bool {
        switch residency {
        case .browsing, .closing:
            true
        case .playing(let host):
            transitionIsActive == false && host == .window
        }
    }
}
"""

CLEAN_VIEW = """import SwiftUI

struct PlayerInfoBarView: View {
    var body: some View {
        Button("Back") { launcher.stopPlayback(reason: .backButton) }
    }
}
"""

BUDGETED_CLOSE = """
extension PlaybackRuntime {
    func closeDeadline() -> Duration { PlaybackCloseBudget.deadline }
}
"""


class PlaybackOwnershipTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name).resolve()
        patcher = patch.object(checker, "REPOSITORY_ROOT", self.repository)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.runtime(CLEAN_RUNTIME)
        self.interpreter(CLEAN_INTERPRETER)
        self.write(checker.COORDINATOR_SOURCE, CLEAN_COORDINATOR)
        self.write(checker.PAGE_SOURCE, CLEAN_PAGE)
        self.write("Modules/Playback/Views/PlayerInfoBarView.swift", CLEAN_VIEW)

    def write(self, relative: str, contents: str) -> None:
        path = self.repository / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def runtime(self, contents: str) -> None:
        self.write(checker.RUNTIME_SOURCE, contents + BUDGETED_CLOSE)

    def interpreter(self, contents: str) -> None:
        self.write(checker.INTERPRETER_SOURCE, contents)

    def test_a_runtime_that_owns_nothing_underneath_passes(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_a_runtime_that_picks_the_active_driver_fails(self) -> None:
        self.runtime(CLEAN_RUNTIME + "\nextension PlaybackRuntime { var current: Driver? { activeDriver } }\n")

        self.assertIn("driver-selection", " ".join(checker.failures()))

    def test_a_runtime_that_names_the_prepared_driver_fails(self) -> None:
        self.runtime(CLEAN_RUNTIME.replace("coordinator.resume()", "preparedDriver?.resume()"))

        self.assertIn("driver-selection", " ".join(checker.failures()))

    def test_a_runtime_that_holds_a_core_session_fails(self) -> None:
        self.runtime(
            CLEAN_RUNTIME.replace(
                "private let interpreter: MediaFormatInterpreter",
                "private var session: PlaybackMediaSessionDriver.SessionResource?",
            )
        )

        self.assertIn("core-session-types", " ".join(checker.failures()))

    def test_a_runtime_that_holds_a_sample_buffer_renderer_fails(self) -> None:
        self.runtime(CLEAN_RUNTIME.replace("PlaybackLifecycle = .idle", "AVSampleBufferVideoRenderer? = nil"))

        self.assertIn("core-session-types", " ".join(checker.failures()))

    def test_a_runtime_that_carries_a_cutover_token_fails(self) -> None:
        self.runtime(CLEAN_RUNTIME + "\nextension PlaybackRuntime { func hand(_ token: CutoverToken) {} }\n")

        self.assertIn("transfer-internals", " ".join(checker.failures()))

    def test_a_runtime_that_decides_stereo_layout_fails(self) -> None:
        self.runtime(CLEAN_RUNTIME + "\nextension PlaybackRuntime { var layout: VideoStereoLayout { .mono } }\n")

        self.assertIn("format-policy", " ".join(checker.failures()))

    def test_a_runtime_that_computes_field_of_view_fails(self) -> None:
        self.runtime(
            CLEAN_RUNTIME + "\nextension PlaybackRuntime { var fov: Double { normalizedHorizontalFieldOfViewDegrees } }\n"
        )

        self.assertIn("format-policy", " ".join(checker.failures()))

    def test_a_forbidden_reference_inside_a_comment_is_ignored(self) -> None:
        self.runtime(CLEAN_RUNTIME + "\n// activeDriver moved to RendererTransferCoordinator\n")

        self.assertEqual(checker.failures(), [])

    def test_an_interpreter_that_imports_the_engine_fails(self) -> None:
        self.interpreter("import PlaybackCore\n" + CLEAN_INTERPRETER)

        self.assertIn("must not import PlaybackCore", " ".join(checker.failures()))

    def test_an_interpreter_that_imports_a_platform_media_framework_fails(self) -> None:
        self.interpreter("import AVFoundation\n" + CLEAN_INTERPRETER)

        self.assertIn("must not import AVFoundation", " ".join(checker.failures()))

    def test_an_interpreter_that_imports_realitykit_fails(self) -> None:
        self.interpreter("import RealityKit\n" + CLEAN_INTERPRETER)

        self.assertIn("must not import RealityKit", " ".join(checker.failures()))

    def test_a_view_that_leaves_playback_directly_fails(self) -> None:
        self.write(
            "Modules/Playback/Views/PlayerInfoBarView.swift",
            CLEAN_VIEW.replace(
                "launcher.stopPlayback(reason: .backButton)",
                "runtime.leavePlayback(reason: .backButton)",
            ),
        )

        self.assertIn("leave-entry", " ".join(checker.failures()))

    def test_the_scene_wiring_awaiting_a_leave_directly_fails(self) -> None:
        self.write(
            "Apps/Enchron/EnchronApplication.swift",
            "await playbackRuntime.leavePlaybackAndWait(reason: .failure)\n",
        )

        self.assertIn("leave-entry", " ".join(checker.failures()))

    def test_the_coordinator_leaving_playback_passes(self) -> None:
        self.assertEqual(checker.failures(), [])

    def test_a_leave_call_inside_a_comment_is_ignored(self) -> None:
        self.write(
            "Modules/Playback/Views/PlayerInfoBarView.swift",
            CLEAN_VIEW + "// runtime.leavePlayback(reason: .backButton)\n",
        )

        self.assertEqual(checker.failures(), [])

    def test_a_source_that_still_stops_the_runtime_fails(self) -> None:
        self.write(
            "Modules/Playback/Views/WindowPlayerDeck.swift",
            "playbackRuntime.stop(releasingSourceAccess: true)\n",
        )

        self.assertIn("leave-reason", " ".join(checker.failures()))

    def test_a_page_policy_that_reads_the_scene_state_fails(self) -> None:
        self.write(
            checker.PAGE_SOURCE,
            CLEAN_PAGE.replace(
                "residency: PlaybackResidency",
                "hasActivePlaybackRequest: Bool",
            ),
        )

        self.assertIn("page-authority", " ".join(checker.failures()))

    def test_an_absent_page_fails(self) -> None:
        (self.repository / checker.PAGE_SOURCE).unlink()

        self.assertIn("MainView.swift is absent", " ".join(checker.failures()))

    def test_an_unbounded_close_fails(self) -> None:
        self.write(checker.RUNTIME_SOURCE, CLEAN_RUNTIME)

        self.assertIn("close-budget", " ".join(checker.failures()))

    def test_an_absent_runtime_fails(self) -> None:
        (self.repository / checker.RUNTIME_SOURCE).unlink()

        self.assertIn("is absent", " ".join(checker.failures()))

    def test_an_absent_interpreter_fails(self) -> None:
        (self.repository / checker.INTERPRETER_SOURCE).unlink()

        self.assertIn("is absent", " ".join(checker.failures()))


class RepositoryTests(unittest.TestCase):
    def test_the_shipped_runtime_and_interpreter_hold_the_boundary(self) -> None:
        self.assertEqual(checker.failures(), [])


if __name__ == "__main__":
    unittest.main()
