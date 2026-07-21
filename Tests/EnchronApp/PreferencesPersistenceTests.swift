import XCTest
@testable import Enchron

/// Verifies the extended `UserPreferences` fields survive a save→load round-trip
/// through the real `UserDefaultsStore` (SET-12: settings persist across launches).
nonisolated final class PreferencesPersistenceTests: XCTestCase {
    func testUserDefaultsStoreRoundTripsExtendedFields() {
        let suite = "xrplayer.tests.preferences"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsStore(defaults: defaults)

        var prefs = UserPreferences()
        prefs.resumePolicy = .alwaysResume
        prefs.playbackEndBehavior = .playNext
        prefs.defaultPlaybackSpeed = 1.5
        prefs.defaultEnvironmentID = "Starry Night"
        prefs.controlsAutoHideSeconds = 15
        store.savePreferences(prefs)

        // A fresh store reading the same backing store simulates a relaunch.
        let reloaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(reloaded, prefs)
    }

    func testDefaultsMatchSpecifiedFallbacks() {
        let suite = "xrplayer.tests.preferences.empty"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create test UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let loaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(loaded.controlsAutoHideSeconds, 8)
    }
}
