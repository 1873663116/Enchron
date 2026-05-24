import Foundation

public nonisolated final class UserDefaultsStore: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let resumePolicyKey = "xrplayer.preferences.resumePolicy"
    private static let defaultEnvironmentKey = "xrplayer.preferences.defaultEnvironment"
    private static let endBehaviorKey = "xrplayer.preferences.endBehavior"
    private static let defaultSpeedKey = "xrplayer.preferences.defaultSpeed"
    private static let screenShapeKey = "xrplayer.preferences.screenShape"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadPreferences() -> PersistenceDomain.UserPreferences {
        let policyRaw = defaults.string(forKey: Self.resumePolicyKey) ?? "askEveryTime"
        let policy: PersistenceDomain.ResumePolicy
        switch policyRaw {
        case "alwaysResume":
            policy = .alwaysResume
        case "alwaysStartFromBeginning":
            policy = .alwaysStartFromBeginning
        default:
            policy = .askEveryTime
        }

        let endBehaviorRaw = defaults.string(forKey: Self.endBehaviorKey) ?? "stop"
        let endBehavior: PersistenceDomain.PlaybackEndBehavior
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
        let isScreenCurved = defaults.bool(forKey: Self.screenShapeKey)

        return PersistenceDomain.UserPreferences(
            resumePolicy: policy,
            playbackEndBehavior: endBehavior,
            defaultPlaybackSpeed: defaultSpeed,
            defaultEnvironmentID: envID,
            isScreenCurved: isScreenCurved
        )
    }

    public func savePreferences(_ preferences: PersistenceDomain.UserPreferences) {
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
        defaults.set(preferences.isScreenCurved, forKey: Self.screenShapeKey)
    }
}
