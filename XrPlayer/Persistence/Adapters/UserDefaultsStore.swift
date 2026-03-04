import Foundation

public final class UserDefaultsStore: PreferencesStoring {
    public init() {}

    public func loadPreferences() -> PersistenceDomain.UserPreferences {
        fatalError("TODO: implement")
    }

    public func savePreferences(_ preferences: PersistenceDomain.UserPreferences) {
        _ = preferences
        fatalError("TODO: implement")
    }
}
