import Foundation
import XCTest
@testable import EnchronMacOS

nonisolated final class EnchronApplicationAutoplayTests: XCTestCase {
    @MainActor
    func testRealMediaAutoplayReachesThePlaybackRuntime() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "../TestMedia/Generated/sdr-bframe-multiaudio-avsync-120s.mp4")
            .standardizedFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

        let application = EnchronApplication(environment: [
            "ENCHRON_AUTOPLAY_FILE": fixture.path,
            "ENCHRON_RESET_MEDIA_LIBRARY": "1",
        ])

        let deadline = ContinuousClock.now + .seconds(3)
        while application.playbackRuntime.hasActivePlaybackRequest == false,
              application.mediaLibraryViewModel.lastErrorMessage == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertNil(application.mediaLibraryViewModel.lastErrorMessage)
        XCTAssertTrue(application.playbackRuntime.hasActivePlaybackRequest)
        XCTAssertEqual(
            application.playbackRuntime.currentLaunchRequest?.url,
            fixture
        )
    }
}
