import Foundation

public struct DecidePlaybackModeUseCase: PlaybackModeManaging, Sendable {
    public init() {}

    /// Stub: always returns .window → panorama/immersive routing tests FAIL.
    public func decideMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool,
        manualOverride: PlaybackMode?
    ) -> PlaybackMode {
        .window
    }
}
