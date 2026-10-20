import Foundation
import Playback
import Observation

public nonisolated struct MediaLibraryTabVisibility: Sendable, Equatable {
    public var emby: Bool
    public var plex: Bool
    public var jellyfin: Bool

    public init(emby: Bool = true, plex: Bool = true, jellyfin: Bool = true) {
        self.emby = emby
        self.plex = plex
        self.jellyfin = jellyfin
    }
}

public nonisolated struct UserPreferences: Sendable, Equatable {
    public var resumePolicy: ResumePolicy
    public var playbackEndBehavior: PlaybackEndBehavior
    public var defaultPlaybackSpeed: Double
    public var playbackShortcutsEnabled: Bool
    public var holdPlaybackSpeed: Double
    public var controlsAutoHideSeconds: Int
    public var developerModeEnabled: Bool
    public var surroundingsDimmingEnabled: Bool
    public var mediaLibraryTabs: MediaLibraryTabVisibility
    public var moonlightEnabled: Bool

    public init(
        resumePolicy: ResumePolicy = .askEveryTime,
        playbackEndBehavior: PlaybackEndBehavior = .repeatOne,
        defaultPlaybackSpeed: Double = 1.0,
        playbackShortcutsEnabled: Bool = true,
        holdPlaybackSpeed: Double = 2.0,
        controlsAutoHideSeconds: Int = 8,
        developerModeEnabled: Bool = false,
        surroundingsDimmingEnabled: Bool = true,
        mediaLibraryTabs: MediaLibraryTabVisibility = .init(),
        moonlightEnabled: Bool = false
    ) {
        self.resumePolicy = resumePolicy
        self.playbackEndBehavior = playbackEndBehavior
        self.defaultPlaybackSpeed = defaultPlaybackSpeed
        self.playbackShortcutsEnabled = playbackShortcutsEnabled
        self.holdPlaybackSpeed = Self.normalizedHoldPlaybackSpeed(holdPlaybackSpeed)
        self.controlsAutoHideSeconds = controlsAutoHideSeconds
        self.developerModeEnabled = developerModeEnabled
        self.surroundingsDimmingEnabled = surroundingsDimmingEnabled
        self.mediaLibraryTabs = mediaLibraryTabs
        self.moonlightEnabled = moonlightEnabled
    }

    static func normalizedHoldPlaybackSpeed(_ value: Double) -> Double {
        guard value.isFinite, value != 1 else { return 2 }
        return PlaybackModel.PlaybackSpeed(value).value
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
    @ObservationIgnored private let onPreferencesChanged: (@MainActor (UserPreferences) -> Void)?

    public init(
        store: PreferencesStoring = UserDefaultsStore(),
        onPreferencesChanged: (@MainActor (UserPreferences) -> Void)? = nil
    ) {
        self.store = store
        self.onPreferencesChanged = onPreferencesChanged
        self.preferences = store.loadPreferences()
        onPreferencesChanged?(preferences)
    }

    public func update(_ mutate: (inout UserPreferences) -> Void) {
        mutate(&preferences)
        preferences.holdPlaybackSpeed = UserPreferences.normalizedHoldPlaybackSpeed(preferences.holdPlaybackSpeed)
        store.savePreferences(preferences)
        onPreferencesChanged?(preferences)
    }
}
