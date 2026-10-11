import Foundation
import CoreFoundation
import Playback

public nonisolated final class UserDefaultsStore: PreferencesStoring, PlaybackPreferencesProviding, @unchecked Sendable {
    private let defaults: UserDefaults
    private let playbackSpeedOverride: Double?
    private static let resumePolicyKey = "enchron.preferences.resumePolicy"
    private static let endBehaviorKey = "enchron.preferences.endBehavior"
    private static let defaultSpeedKey = "enchron.preferences.defaultSpeed"
    private static let controlsAutoHideKey = "enchron.preferences.controlsAutoHideSeconds"
    private static let developerModeKey = "enchron.preferences.developerMode"
    private static let surroundingsDimmingKey = "enchron.preferences.surroundingsDimming"
    private static let mediaLibraryTabsKey = "enchron.preferences.mediaLibraryTabs"

    public init(defaults: UserDefaults = .standard, playbackSpeedOverride: Double? = nil) {
        self.defaults = defaults
        self.playbackSpeedOverride = playbackSpeedOverride
    }

    public func loadPreferences() -> UserPreferences {
        let policyRaw = defaults.string(forKey: Self.resumePolicyKey) ?? "askEveryTime"
        let policy: ResumePolicy
        switch policyRaw {
        case "alwaysResume":
            policy = .alwaysResume
        case "alwaysStartFromBeginning":
            policy = .alwaysStartFromBeginning
        default:
            policy = .askEveryTime
        }

        let endBehavior: PlaybackEndBehavior
        switch defaults.string(forKey: Self.endBehaviorKey) {
        case "playNext":
            endBehavior = .playNext
        default:
            endBehavior = .repeatOne
        }

        let defaultSpeed = defaults.object(forKey: Self.defaultSpeedKey) as? Double ?? 1.0
        let controlsAutoHide = defaults.object(forKey: Self.controlsAutoHideKey) as? Int ?? 8
#if DEBUG
        let developerModeEnabled = defaults.bool(forKey: Self.developerModeKey)
#else
        let developerModeEnabled = false
#endif

        let storedTabs = defaults.dictionary(forKey: Self.mediaLibraryTabsKey)
        return UserPreferences(
            resumePolicy: policy,
            playbackEndBehavior: endBehavior,
            defaultPlaybackSpeed: defaultSpeed,
            controlsAutoHideSeconds: controlsAutoHide,
            developerModeEnabled: developerModeEnabled,
            surroundingsDimmingEnabled: defaults.object(forKey: Self.surroundingsDimmingKey) as? Bool ?? true,
            mediaLibraryTabs: MediaLibraryTabVisibility(
                emby: mediaLibraryTabIsVisible(storedTabs?["emby"]),
                plex: mediaLibraryTabIsVisible(storedTabs?["plex"]),
                jellyfin: mediaLibraryTabIsVisible(storedTabs?["jellyfin"])
            )
        )
    }

    public func savePreferences(_ preferences: UserPreferences) {
        let policyString: String
        switch preferences.resumePolicy {
        case .askEveryTime:
            policyString = "askEveryTime"
        case .alwaysResume:
            policyString = "alwaysResume"
        case .alwaysStartFromBeginning:
            policyString = "alwaysStartFromBeginning"
        }
        defaults.set(policyString, forKey: Self.resumePolicyKey)

        let endBehaviorString: String
        switch preferences.playbackEndBehavior {
        case .repeatOne:
            endBehaviorString = "repeatOne"
        case .playNext:
            endBehaviorString = "playNext"
        }
        defaults.set(endBehaviorString, forKey: Self.endBehaviorKey)
        defaults.set(preferences.defaultPlaybackSpeed, forKey: Self.defaultSpeedKey)
        defaults.set(preferences.controlsAutoHideSeconds, forKey: Self.controlsAutoHideKey)
        defaults.set(preferences.developerModeEnabled, forKey: Self.developerModeKey)
#if !DEBUG
        defaults.removeObject(forKey: Self.developerModeKey)
#endif
        defaults.set(preferences.surroundingsDimmingEnabled, forKey: Self.surroundingsDimmingKey)
        defaults.set([
            "emby": preferences.mediaLibraryTabs.emby,
            "plex": preferences.mediaLibraryTabs.plex,
            "jellyfin": preferences.mediaLibraryTabs.jellyfin
        ], forKey: Self.mediaLibraryTabsKey)
    }

    private func mediaLibraryTabIsVisible(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return true }
        return number.boolValue
    }

    public func loadPlaybackPreferences() -> PlaybackPreferences {
        let preferences = loadPreferences()
        return PlaybackPreferences(
            resumePolicy: preferences.resumePolicy,
            endBehavior: preferences.playbackEndBehavior,
            defaultSpeed: playbackSpeedOverride ?? preferences.defaultPlaybackSpeed
        )
    }
}
