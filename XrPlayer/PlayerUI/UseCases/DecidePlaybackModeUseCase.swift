import Foundation

public struct DecidePlaybackModeUseCase: PlaybackModeManaging, Sendable {
    public init() {}

    /// Returns the set of playback modes geometrically compatible with the given projection type.
    /// Panorama mode requires panoramic content; immersive (virtual cinema) is always available.
    /// When projection type is nil (not yet detected), defaults to [.window, .immersive].
    public static func allowedModes(
        for projectionType: PlaybackCoreDomain.ProjectionType?
    ) -> Set<PlaybackMode> {
        guard let projectionType else { return [.window, .immersive] }
        if projectionType.isPanoramic {
            return [.window, .immersive, .panorama]
        }
        return [.window, .immersive]
    }

    public func decideMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool,
        manualOverride: PlaybackMode?
    ) -> PlaybackMode {
        if let override = manualOverride {
            let allowed = Self.allowedModes(for: profile.projectionType)
            if allowed.contains(override) {
                return override
            }
            return .window
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
