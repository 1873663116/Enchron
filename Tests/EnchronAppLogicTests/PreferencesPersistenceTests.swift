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
    func testSavingMediaLibraryTabsPreservesPreferencesChangedWhileEditing() throws {
        let suite = "enchron.tests.mediaLibraryTabs.save.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = SettingsViewModel(store: UserDefaultsStore(defaults: defaults))
        var draft = model.preferences.mediaLibraryTabs
        draft.emby = false
        draft.jellyfin = false

        model.update {
            $0.defaultPlaybackSpeed = 1.5
            $0.playbackEndBehavior = .playNext
            $0.surroundingsDimmingEnabled = false
        }
        XCTAssertEqual(model.preferences.mediaLibraryTabs.emby, true)
        XCTAssertEqual(model.preferences.mediaLibraryTabs.jellyfin, true)

        model.update { $0.mediaLibraryTabs = draft }
        let reloaded = UserDefaultsStore(defaults: defaults).loadPreferences()
        XCTAssertEqual(reloaded.mediaLibraryTabs.emby, false)
        XCTAssertEqual(reloaded.mediaLibraryTabs.plex, true)
        XCTAssertEqual(reloaded.mediaLibraryTabs.jellyfin, false)
        XCTAssertEqual(reloaded.defaultPlaybackSpeed, 1.5)
        XCTAssertEqual(reloaded.playbackEndBehavior, .playNext)
        XCTAssertEqual(reloaded.surroundingsDimmingEnabled, false)
    }

    @MainActor
    func testNavigationResolvesEveryTabForEveryVisibleSubset() {
        typealias Tab = AppModel.NavigationTab
        let tabs: [Tab] = [.files, .emby, .plex, .jellyfin, .settings, .environment]
        let cases: [(MediaLibraryTabVisibility, [Tab])] = [
            (.init(emby: false, plex: false, jellyfin: false), [.files, .files, .files, .files, .settings, .files]),
            (.init(emby: false, plex: false, jellyfin: true), [.files, .files, .files, .jellyfin, .settings, .files]),
            (.init(emby: false, plex: true, jellyfin: false), [.files, .files, .plex, .files, .settings, .files]),
            (.init(emby: false, plex: true, jellyfin: true), [.files, .files, .plex, .jellyfin, .settings, .files]),
            (.init(emby: true, plex: false, jellyfin: false), [.files, .emby, .files, .files, .settings, .files]),
            (.init(emby: true, plex: false, jellyfin: true), [.files, .emby, .files, .jellyfin, .settings, .files]),
            (.init(emby: true, plex: true, jellyfin: false), [.files, .emby, .plex, .files, .settings, .files]),
            (.init(emby: true, plex: true, jellyfin: true), [.files, .emby, .plex, .jellyfin, .settings, .files])
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
