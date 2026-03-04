import Foundation

public protocol PreferencesStoring {
    func loadPreferences() -> PersistenceDomain.UserPreferences
    func savePreferences(_ preferences: PersistenceDomain.UserPreferences)
}
