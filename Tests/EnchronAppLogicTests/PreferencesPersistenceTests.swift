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
        prefs.playbackShortcutsEnabled = false
        prefs.holdPlaybackSpeed = 3.0
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
        XCTAssertTrue(loaded.playbackShortcutsEnabled)
        XCTAssertEqual(loaded.holdPlaybackSpeed, 2.0)
    }

    func testExistingPreferencesMigrateToEnabledSurfaceShortcutsAndTwoTimesHoldSpeed() throws {
        let suite = "enchron.tests.surfaceGestures.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("alwaysResume", forKey: "enchron.preferences.resumePolicy")
        defaults.set(1.5, forKey: "enchron.preferences.defaultSpeed")
        defaults.set(15, forKey: "enchron.preferences.controlsAutoHideSeconds")

        let loaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertTrue(loaded.playbackShortcutsEnabled)
        XCTAssertEqual(loaded.holdPlaybackSpeed, 2.0)
        XCTAssertEqual(loaded.resumePolicy, .alwaysResume)
        XCTAssertEqual(loaded.defaultPlaybackSpeed, 1.5)
        XCTAssertEqual(loaded.controlsAutoHideSeconds, 15)
    }

    func testSurfaceShortcutsLoadBooleanValuesAndIgnoreMalformedValues() throws {
        let suite = "enchron.tests.surfaceGestures.boundary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cases: [(Any?, Bool)] = [
            (nil, true), (false, false), (true, true),
            ("false", true), (0, true), (1, true), (["enabled": false], true)
        ]
        for (stored, expected) in cases {
            defaults.set(stored, forKey: "enchron.preferences.surfaceGesturesEnabled")
            XCTAssertEqual(UserDefaultsStore(defaults: defaults).loadPreferences().playbackShortcutsEnabled, expected)
        }
    }

    func testHoldPlaybackSpeedLoadsSupportedRangeAndRejectsMalformedValues() throws {
        let suite = "enchron.tests.holdPlaybackSpeed.boundary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cases: [(Any?, Double)] = [
            (nil, 2.0), ("3", 2.0), (false, 2.0), (true, 2.0),
            (Double.nan, 2.0), (Double.infinity, 2.0), (-Double.infinity, 2.0),
            (-1.0, 0.25), (0.0, 0.25), (0.25, 0.25), (1.0, 2.0), (2.37, 2.37), (1.5, 1.5),
            (2, 2.0), (3.0, 3.0), (5.0, 5.0), (100.0, 5.0)
        ]
        for (stored, expected) in cases {
            defaults.set(stored, forKey: "enchron.preferences.holdPlaybackSpeed")
            XCTAssertEqual(UserDefaultsStore(defaults: defaults).loadPreferences().holdPlaybackSpeed, expected)
        }
    }

    func testHoldPlaybackSpeedSaveUsesSupportedRangeAndFiniteFallback() throws {
        let suite = "enchron.tests.holdPlaybackSpeed.save.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        let cases: [(Double, Double)] = [
            (-1, 0.25), (0.25, 0.25), (0.5, 0.5), (0.75, 0.75),
            (1, 2), (1.01, 1.01), (0.99, 0.99), (2.37, 2.37), (1.25, 1.25), (1.5, 1.5), (1.75, 1.75),
            (2, 2), (3, 3), (5, 5), (100, 5),
            (.nan, 2), (.infinity, 2), (-.infinity, 2)
        ]
        for (speed, expected) in cases {
            store.savePreferences(UserPreferences(playbackShortcutsEnabled: false, holdPlaybackSpeed: speed))
            let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let restored = UserDefaultsStore(defaults: restoredDefaults).loadPreferences()
            XCTAssertFalse(restored.playbackShortcutsEnabled)
            XCTAssertEqual(restored.holdPlaybackSpeed, expected)
            XCTAssertEqual(restored.defaultPlaybackSpeed, 1.0)
        }
    }

    @MainActor
    func testSurfaceShortcutPreferencesSynchronizeAtStartupAndImmediatelyAfterChanges() throws {
        let suite = "enchron.tests.surfaceGestures.sync.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsStore(defaults: defaults)
        store.savePreferences(UserPreferences(
            defaultPlaybackSpeed: 1.5,
            playbackShortcutsEnabled: false,
            holdPlaybackSpeed: 3.0
        ))
        let session = PlaybackSessionModel()
        let settings = SettingsViewModel(store: store) { preferences in
            session.playbackShortcutsEnabled = preferences.playbackShortcutsEnabled
            session.holdPlaybackSpeed = preferences.holdPlaybackSpeed
        }
        XCTAssertFalse(session.playbackShortcutsEnabled)
        XCTAssertEqual(session.holdPlaybackSpeed, 3.0)

        settings.update { $0.playbackShortcutsEnabled = true }
        XCTAssertTrue(session.playbackShortcutsEnabled)
        settings.update { $0.holdPlaybackSpeed = 1 }
        XCTAssertEqual(session.holdPlaybackSpeed, 2)
        XCTAssertEqual(settings.preferences.holdPlaybackSpeed, 2)
        settings.update { $0.holdPlaybackSpeed = 0.5 }
        XCTAssertEqual(session.holdPlaybackSpeed, 0.5)

        let restored = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertTrue(restored.playbackShortcutsEnabled)
        XCTAssertEqual(restored.holdPlaybackSpeed, 0.5)
        XCTAssertEqual(restored.defaultPlaybackSpeed, 1.5)
    }

    @MainActor
    func testMediaLibraryTabsRoundTripEverySubset() throws {
        let subsets: [(Bool, Bool, Bool)] = [
            (false, false, false),
            (false, false, true),
            (false, true, false),
            (false, true, true),
            (true, false, false),
            (true, false, true),
            (true, true, false),
            (true, true, true)
        ]
        for (emby, plex, jellyfin) in subsets {
            let suite = "enchron.tests.mediaLibraryTabs.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let model = SettingsViewModel(store: UserDefaultsStore(defaults: defaults))
            model.update {
                $0.mediaLibraryTabs = MediaLibraryTabVisibility(
                    emby: emby, plex: plex, jellyfin: jellyfin
                )
            }

            let reloaded = SettingsViewModel(store: UserDefaultsStore(defaults: defaults))
            XCTAssertEqual(reloaded.preferences.mediaLibraryTabs.emby, emby)
            XCTAssertEqual(reloaded.preferences.mediaLibraryTabs.plex, plex)
            XCTAssertEqual(reloaded.preferences.mediaLibraryTabs.jellyfin, jellyfin)
        }
    }

    func testMediaLibraryTabsLoadDefaultsAndMalformedValues() throws {
        let suite = "enchron.tests.mediaLibraryTabs.boundary.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "enchron.preferences.mediaLibraryTabs"
        let cases: [(Any?, Bool, Bool, Bool)] = [
            (nil, true, true, true),
            ("invalid", true, true, true),
            (["emby": false], false, true, true),
            (["emby": "false", "plex": false, "jellyfin": 0] as [String: Any], true, false, true),
            (["emby": 1, "plex": "true", "jellyfin": false] as [String: Any], true, true, false),
            (["emby": false, "plex": false, "jellyfin": false, "future": true], false, false, false)
        ]
        for (stored, emby, plex, jellyfin) in cases {
            defaults.set(stored, forKey: key)
            let tabs = UserDefaultsStore(defaults: defaults).loadPreferences().mediaLibraryTabs
            XCTAssertEqual(tabs.emby, emby)
            XCTAssertEqual(tabs.plex, plex)
            XCTAssertEqual(tabs.jellyfin, jellyfin)
        }
    }

    @MainActor
    func testChangingMediaLibraryTabsImmediatelyPersistsWithoutReplacingOtherPreferences() throws {
        let suite = "enchron.tests.mediaLibraryTabs.change.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SettingsViewModel(store: UserDefaultsStore(defaults: defaults))
        let embyField: WritableKeyPath<MediaLibraryTabVisibility, Bool> = \.emby
        let hideEmby: (inout UserPreferences) -> Void = {
            $0.mediaLibraryTabs[keyPath: embyField] = false
        }
        model.update {
            $0.mediaLibraryTabs.plex = false
            $0.defaultPlaybackSpeed = 1.5
            $0.playbackEndBehavior = .playNext
            $0.surroundingsDimmingEnabled = false
        }
        model.update(hideEmby)
        let firstChange = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(firstChange.mediaLibraryTabs.emby, false)
        XCTAssertEqual(firstChange.mediaLibraryTabs.plex, false)
        XCTAssertEqual(firstChange.mediaLibraryTabs.jellyfin, true)
        XCTAssertEqual(firstChange.defaultPlaybackSpeed, 1.5)

        model.update { $0.mediaLibraryTabs.jellyfin = false }
        let reloaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(reloaded.mediaLibraryTabs.emby, false)
        XCTAssertEqual(reloaded.mediaLibraryTabs.plex, false)
        XCTAssertEqual(reloaded.mediaLibraryTabs.jellyfin, false)
        XCTAssertEqual(reloaded.defaultPlaybackSpeed, 1.5)
        XCTAssertEqual(reloaded.playbackEndBehavior, .playNext)
        XCTAssertEqual(reloaded.surroundingsDimmingEnabled, false)
    }

    @MainActor
    func testCompactEnvironmentKeepsWindowBarAndHidesTabs() {
        let compact = BrowserWindowVisibility(window: .main, playbackResidency: .browsing, isCompact: true)
        XCTAssertEqual(compact.tabBarVisibility, .hidden)
        XCTAssertEqual(compact.systemOverlays, .automatic)
        let expanded = BrowserWindowVisibility(window: .main, playbackResidency: .browsing)
        XCTAssertEqual(expanded.tabBarVisibility, .automatic)
    }

    @MainActor
    func testNavigationResolvesEveryTabForEveryVisibleSubset() {
        typealias Tab = AppModel.NavigationTab
        let tabs: [Tab] = [.files, .emby, .plex, .jellyfin, .settings, .environment]
        let cases: [(MediaLibraryTabVisibility, [Tab])] = [
            (.init(emby: false, plex: false, jellyfin: false), [.files, .files, .files, .files, .settings, .environment]),
            (.init(emby: false, plex: false, jellyfin: true), [.files, .files, .files, .jellyfin, .settings, .environment]),
            (.init(emby: false, plex: true, jellyfin: false), [.files, .files, .plex, .files, .settings, .environment]),
            (.init(emby: false, plex: true, jellyfin: true), [.files, .files, .plex, .jellyfin, .settings, .environment]),
            (.init(emby: true, plex: false, jellyfin: false), [.files, .emby, .files, .files, .settings, .environment]),
            (.init(emby: true, plex: false, jellyfin: true), [.files, .emby, .files, .jellyfin, .settings, .environment]),
            (.init(emby: true, plex: true, jellyfin: false), [.files, .emby, .plex, .files, .settings, .environment]),
            (.init(emby: true, plex: true, jellyfin: true), [.files, .emby, .plex, .jellyfin, .settings, .environment])
        ]
        for (visibility, expected) in cases {
            XCTAssertEqual(tabs.map { $0.contentDestination(in: visibility) }, expected)
            XCTAssertEqual(
                tabs.map { $0.contentDestination(in: visibility).contentDestination(in: visibility) },
                expected
            )
        }
    }
}
