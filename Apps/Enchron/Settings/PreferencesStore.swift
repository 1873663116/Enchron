import Foundation


public nonisolated final class UserDefaultsStore: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let resumePolicyKey = "xrplayer.preferences.resumePolicy"
    private static let defaultEnvironmentKey = "xrplayer.preferences.defaultEnvironment"
    private static let endBehaviorKey = "xrplayer.preferences.endBehavior"
    private static let defaultSpeedKey = "xrplayer.preferences.defaultSpeed"
    private static let controlsAutoHideKey = "xrplayer.preferences.controlsAutoHideSeconds"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

        let endBehaviorRaw = defaults.string(forKey: Self.endBehaviorKey) ?? "stop"
        let endBehavior: PlaybackEndBehavior
        switch endBehaviorRaw {
        case "repeatOne":
            endBehavior = .repeatOne
        case "playNext":
            endBehavior = .playNext
        default:
            endBehavior = .stop
        }

        let defaultSpeed = defaults.object(forKey: Self.defaultSpeedKey) as? Double ?? 1.0
        let envID = defaults.string(forKey: Self.defaultEnvironmentKey)
        let controlsAutoHide = defaults.object(forKey: Self.controlsAutoHideKey) as? Int ?? 8

        return UserPreferences(
            resumePolicy: policy,
            playbackEndBehavior: endBehavior,
            defaultPlaybackSpeed: defaultSpeed,
            defaultEnvironmentID: envID,
            controlsAutoHideSeconds: controlsAutoHide
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
        case .stop:
            endBehaviorString = "stop"
        case .repeatOne:
            endBehaviorString = "repeatOne"
        case .playNext:
            endBehaviorString = "playNext"
        }
        defaults.set(endBehaviorString, forKey: Self.endBehaviorKey)
        defaults.set(preferences.defaultPlaybackSpeed, forKey: Self.defaultSpeedKey)
        defaults.set(preferences.defaultEnvironmentID, forKey: Self.defaultEnvironmentKey)
        defaults.set(preferences.controlsAutoHideSeconds, forKey: Self.controlsAutoHideKey)
    }
}


/// In-memory `PreferencesStoring` fixture for tests and previews.
public nonisolated final class FakePreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: UserPreferences

    public init(initial: UserPreferences = UserPreferences()) {
        self.preferences = initial
    }

    public func loadPreferences() -> UserPreferences {
        lock.withLock { preferences }
    }

    public func savePreferences(_ preferences: UserPreferences) {
        lock.withLock { self.preferences = preferences }
    }
}

