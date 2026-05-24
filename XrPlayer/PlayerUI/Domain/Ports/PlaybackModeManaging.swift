import Foundation

public nonisolated protocol PlaybackModeManaging: Sendable {
    func decideMode(
        for profile: PlaybackCoreDomain.MediaProfile,
        isEnvironmentActive: Bool,
        manualOverride: PlaybackMode?
    ) -> PlaybackMode
}
