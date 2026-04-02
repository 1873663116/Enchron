import Foundation

public struct DecidePlaybackModeUseCase: PlaybackModeManaging, Sendable {
    public init() {}

    public func decideMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool,
        manualOverride: PlaybackMode?
    ) -> PlaybackMode {
        if let override = manualOverride {
            return override
        }

        if profile.projectionType.isPanoramic {
            return .panorama
        }

        if isEnvironmentActive {
            return .immersive
        }

        return .window
    }
}
