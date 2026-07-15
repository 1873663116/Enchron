import Foundation

/// In-memory `PreferencesStoring` fixture for tests and previews.
public nonisolated final class FakePreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var preferences: PersistenceDomain.UserPreferences

    public init(initial: PersistenceDomain.UserPreferences = PersistenceDomain.UserPreferences()) {
        self.preferences = initial
    }

    public func loadPreferences() -> PersistenceDomain.UserPreferences {
        lock.withLock { preferences }
    }

    public func savePreferences(_ preferences: PersistenceDomain.UserPreferences) {
        lock.withLock { self.preferences = preferences }
    }
}
