import Foundation
import Observation


public nonisolated enum PlaybackEndBehavior: Sendable, Hashable {
    case stop
    case repeatOne
    case playNext
}

public nonisolated enum ResumePolicy: Sendable, Hashable {
    case askEveryTime
    case alwaysResume
    case alwaysStartFromBeginning
}

public nonisolated struct UserPreferences: Sendable, Equatable {
    public var resumePolicy: ResumePolicy
    public var playbackEndBehavior: PlaybackEndBehavior
    public var defaultPlaybackSpeed: Double
    public var defaultEnvironmentID: String?
    public var controlsAutoHideSeconds: Int

    public init(
        resumePolicy: ResumePolicy = .askEveryTime,
        playbackEndBehavior: PlaybackEndBehavior = .stop,
        defaultPlaybackSpeed: Double = 1.0,
        defaultEnvironmentID: String? = nil,
        controlsAutoHideSeconds: Int = 8
    ) {
        self.resumePolicy = resumePolicy
        self.playbackEndBehavior = playbackEndBehavior
        self.defaultPlaybackSpeed = defaultPlaybackSpeed
        self.defaultEnvironmentID = defaultEnvironmentID
        self.controlsAutoHideSeconds = controlsAutoHideSeconds
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
