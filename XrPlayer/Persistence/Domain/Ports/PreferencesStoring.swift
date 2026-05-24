import Foundation

public nonisolated protocol PreferencesStoring: Sendable {
    func loadPreferences() -> PersistenceDomain.UserPreferences
    func savePreferences(_ preferences: PersistenceDomain.UserPreferences)
}
