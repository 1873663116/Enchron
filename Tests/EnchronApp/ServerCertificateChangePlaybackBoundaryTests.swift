import Foundation
import MediaSource
import Playback
import XCTest
@testable import Enchron

@MainActor
private final class ServerCertificateChangePlaybackBoundaryRecorder {
    var hasActivePlayback = true
    var isPlaybackPlaying = true
    var pauseCount = 0
    var issue: PlaybackUserVisibleIssue?
    var diagnostics: [String] = []
}

nonisolated final class ServerCertificateChangePlaybackBoundaryTests: XCTestCase {
    @MainActor
    func testCertificateChangeRecordsPausesAndPresentsDedicatedIssue() {
        let recorder = ServerCertificateChangePlaybackBoundaryRecorder()
        let boundary = makeBoundary(recorder: recorder)

        boundary.receive(makeCertificateChange())

        XCTAssertEqual(recorder.pauseCount, 1)
        XCTAssertEqual(recorder.issue, .serverCertificateChanged)
        XCTAssertEqual(
            recorder.diagnostics,
            ["certificateBoundary changed previous=AA:BB new=CC:DD"]
        )
    }

    @MainActor
    func testActiveFailureCannotReplaceCertificateIssueUntilPlaybackStops() {
        let recorder = ServerCertificateChangePlaybackBoundaryRecorder()
        let boundary = makeBoundary(recorder: recorder)
        let failure = makeActiveFailure()
        let genericIssue = PlaybackUserVisibleIssue.activePlaybackFailure(failure)
        let activeFailureObservation = PlaybackRuntimeObservation(
            generation: failure.runtimeGeneration,
            event: .activeFailure(failure)
        )
        boundary.receive(makeCertificateChange())

        recorder.issue = genericIssue
        boundary.receive(activeFailureObservation)

        XCTAssertEqual(recorder.issue, .serverCertificateChanged)

        boundary.receive(
            PlaybackRuntimeObservation(
                generation: failure.runtimeGeneration,
                event: .stopped
            )
        )
        recorder.issue = genericIssue
        boundary.receive(activeFailureObservation)

        XCTAssertEqual(recorder.issue, genericIssue)
    }

    @MainActor
    func testCertificateChangeWithoutPlayingSessionDoesNotPause() {
        let recorder = ServerCertificateChangePlaybackBoundaryRecorder()
        recorder.hasActivePlayback = false
        recorder.isPlaybackPlaying = false
        let boundary = makeBoundary(recorder: recorder)

        boundary.receive(makeCertificateChange())

        XCTAssertEqual(recorder.pauseCount, 0)
        XCTAssertEqual(recorder.issue, .serverCertificateChanged)
    }

    @MainActor
    private func makeBoundary(
        recorder: ServerCertificateChangePlaybackBoundaryRecorder
    ) -> ServerCertificateChangePlaybackBoundary {
        ServerCertificateChangePlaybackBoundary(
            hasActivePlayback: { recorder.hasActivePlayback },
            isPlaybackPlaying: { recorder.isPlaybackPlaying },
            pausePlayback: { recorder.pauseCount += 1 },
            setUserVisibleIssue: { recorder.issue = $0 },
            recordDiagnostic: { recorder.diagnostics.append($0) }
        )
    }

    private func makeCertificateChange() -> ServerCertificateChange {
        ServerCertificateChange(
            address: "media.example:443",
            previousFingerprint: "AA:BB",
            currentFingerprint: "CC:DD"
        )
    }

    @MainActor
    private func makeActiveFailure() -> PlaybackActiveFailure {
        PlaybackActiveFailure(
            cause: .connectionInterrupted,
            causalPosition: .init(seconds: 20, duration: 120),
            runtimeGeneration: 9,
            requestID: URL(fileURLWithPath: "/tests/movie.mkv"),
            mediaSessionID: "session-9"
        )
    }
}
