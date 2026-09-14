import XCTest
import Playback
@testable import Enchron

nonisolated final class PreferencesPersistenceTests: XCTestCase {
    func testUserDefaultsStoreRoundTripsExtendedFields() {
        let suite = "enchron.tests.preferences"
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
        prefs.controlsAutoHideSeconds = 15
        store.savePreferences(prefs)

        let reloaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(reloaded, prefs)
    }

    func testDefaultsMatchSpecifiedFallbacks() {
        let suite = "enchron.tests.preferences.empty"
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
