import Foundation

public final class UserDefaultsStore: PreferencesStoring {
    private let defaults: UserDefaults
    private static let resumePolicyKey = "xrplayer.preferences.resumePolicy"
    private static let defaultEnvironmentKey = "xrplayer.preferences.defaultEnvironment"

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

        let envID = defaults.string(forKey: Self.defaultEnvironmentKey)

        return PersistenceDomain.UserPreferences(
            resumePolicy: policy,
            defaultEnvironmentID: envID
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
        defaults.set(preferences.defaultEnvironmentID, forKey: Self.defaultEnvironmentKey)
    }
}
