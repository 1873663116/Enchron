import CoreVideo
import Foundation
import Observation

public enum AppPlaybackMode: Sendable {
    case window
    case immersive
    case panorama
}

@Observable
@MainActor
public final class AppCoordinator: MediaProfileDetecting, PlaybackEventListening {
    public private(set) var session: PlaybackSession?
    public private(set) var currentMode: AppPlaybackMode = .window
    public weak var frameOutput: FrameOutput?

    private let player: PlaybackControlling

    public init(player: PlaybackControlling) {
        self.player = player
    }

    public func startPlayback(url: URL) async throws {
        session = PlaybackSession(
            mediaFile: PlaybackCoreDomain.MediaFile(url: url, containerFormat: url.pathExtension),
            state: .loading
        )
        try await player.play(url: url)
    }

    public func stopPlayback() {
        player.stop()
        session?.state = .stopped
    }

    public func switchPlaybackMode(to mode: AppPlaybackMode) async {
        currentMode = mode
    }

    public func routeFrame(_ pixelBuffer: CVPixelBuffer) {
        frameOutput?.didOutputFrame(pixelBuffer)
    }

    public func decidePlaybackMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool
    ) -> AppPlaybackMode {
        if profile.projectionType.isPanoramic {
            return .panorama
        }
        return isEnvironmentActive ? .immersive : .window
    }

    public func didDetectMediaProfile(_ profile: PlaybackCoreDomain.MediaProfile) {
        currentMode = decidePlaybackMode(for: profile, isEnvironmentActive: false)
    }

    public func playbackDidStart() {
        session?.state = .playing
    }

    public func playbackDidPause() {
        session?.state = .paused
    }

    public func playbackDidResume() {
        session?.state = .playing
    }

    public func playbackDidEnd() {
        session?.state = .ended
    }

    public func playbackDidUpdatePosition(_ position: PlaybackCoreDomain.PlaybackPosition) {
        session?.position = position
    }

    public func playbackDidChangeSpeed(_ speed: PlaybackCoreDomain.PlaybackSpeed) {
        session?.speed = speed
    }

    public func playbackDidSwitchTrack() {}

    public func playbackDidEncounterError(_ error: PlaybackError) {
        _ = error
        session?.state = .failed
    }
}
