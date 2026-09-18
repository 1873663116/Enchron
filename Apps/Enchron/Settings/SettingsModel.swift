import Foundation
import Playback
import Observation

public nonisolated struct UserPreferences: Sendable, Equatable {
    public var resumePolicy: ResumePolicy
    public var playbackEndBehavior: PlaybackEndBehavior
    public var defaultPlaybackSpeed: Double
    public var controlsAutoHideSeconds: Int
    public var developerModeEnabled: Bool
    public var surroundingsDimmingEnabled: Bool

    public init(
        resumePolicy: ResumePolicy = .askEveryTime,
        playbackEndBehavior: PlaybackEndBehavior = .repeatOne,
        defaultPlaybackSpeed: Double = 1.0,
        controlsAutoHideSeconds: Int = 8,
        developerModeEnabled: Bool = false,
        surroundingsDimmingEnabled: Bool = true
    ) {
        self.resumePolicy = resumePolicy
        self.playbackEndBehavior = playbackEndBehavior
        self.defaultPlaybackSpeed = defaultPlaybackSpeed
        self.controlsAutoHideSeconds = controlsAutoHideSeconds
        self.developerModeEnabled = developerModeEnabled
        self.surroundingsDimmingEnabled = surroundingsDimmingEnabled
    }
}

public nonisolated protocol PreferencesStoring: Sendable {
    func loadPreferences() -> UserPreferences
    func savePreferences(_ preferences: UserPreferences)
}

@MainActor
@Observable
public final class SettingsViewModel {
    public private(set) var preferences: UserPreferences
    public var onArtworkCacheCleared: (@MainActor () -> Void)?
    private let store: PreferencesStoring

    public init(store: PreferencesStoring = UserDefaultsStore()) {
        self.store = store
        self.preferences = store.loadPreferences()
    }

    public func update(_ mutate: (inout UserPreferences) -> Void) {
        mutate(&preferences)
        store.savePreferences(preferences)
    }
}
