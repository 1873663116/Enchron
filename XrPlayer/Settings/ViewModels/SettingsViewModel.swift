import Foundation
import Observation

/// Drives the Settings screen's two-way binding to persisted `UserPreferences`.
///
/// Every mutation goes through `update`, which writes through to the injected
/// `PreferencesStoring` so changes persist immediately (SET-12). The app injects
/// `UserDefaultsStore` (survives relaunch); tests inject `FakePreferencesStore`.
@MainActor
@Observable
public final class SettingsViewModel {
    public private(set) var preferences: PersistenceDomain.UserPreferences
    private let store: PreferencesStoring

    public init(store: PreferencesStoring = UserDefaultsStore()) {
        self.store = store
        self.preferences = store.loadPreferences()
    }

    /// Mutate preferences in place and persist the result.
    public func update(_ mutate: (inout PersistenceDomain.UserPreferences) -> Void) {
        mutate(&preferences)
        store.savePreferences(preferences)
    }
}
