import Foundation
import Testing
@testable import MediaLibrary

struct MediaLibraryUIStateTests {
    @MainActor
    @Test("view mode persists through the MediaLibraryFeature defaults suite")
    func viewModePersistsThroughFeatureReconstruction() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }
        let first = makeFeature(defaultsSuiteName: fixture.suiteName)

        first.uiState.viewMode = .list

        let reconstructed = makeFeature(defaultsSuiteName: fixture.suiteName)
        #expect(reconstructed.uiState.viewMode == .list)
    }

    @MainActor
    @Test("sort criteria persists through the MediaLibraryFeature defaults suite")
    func sortCriteriaPersistsThroughFeatureReconstruction() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }
        let first = makeFeature(defaultsSuiteName: fixture.suiteName)
        let expected = FileBrowsingDomain.SortCriteria(
            key: .modifiedDate,
            order: .descending
        )

        first.uiState.sortCriteria = expected

        let reconstructed = makeFeature(defaultsSuiteName: fixture.suiteName)
        #expect(reconstructed.uiState.sortCriteria == expected)
    }

    @MainActor
    @Test("empty storage uses grid and name ascending defaults")
    func emptyStorageUsesDefaults() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }

        let feature = makeFeature(defaultsSuiteName: fixture.suiteName)

        #expect(feature.uiState.viewMode == .grid)
        #expect(feature.uiState.sortCriteria == .nameAscending)
    }

    @MainActor
    @Test("corrupted storage uses grid and name ascending defaults")
    func corruptedStorageUsesDefaults() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }
        let store = UserDefaultsMediaLibraryPreferencesStore(defaults: fixture.defaults)
        store.savePreferences(Data("not valid JSON".utf8))

        let feature = makeFeature(defaultsSuiteName: fixture.suiteName)

        #expect(feature.uiState.viewMode == .grid)
        #expect(feature.uiState.sortCriteria == .nameAscending)
    }

    @MainActor
    @Test("shared sort state immediately updates the file browser")
    func sharedSortStateUpdatesFileBrowser() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }
        let feature = makeFeature(defaultsSuiteName: fixture.suiteName)
        let expected = FileBrowsingDomain.SortCriteria(
            key: .size,
            order: .descending
        )
        feature.browser.files = [
            .init(
                name: "Small.mkv",
                sizeInBytes: 10,
                modifiedAt: .distantPast,
                fileExtension: "mkv",
                url: URL(fileURLWithPath: "/Small.mkv")
            ),
            .init(
                name: "Large.mkv",
                sizeInBytes: 20,
                modifiedAt: .distantPast,
                fileExtension: "mkv",
                url: URL(fileURLWithPath: "/Large.mkv")
            )
        ]

        feature.uiState.sortCriteria = expected

        #expect(feature.browser.sortCriteria == expected)
        #expect(feature.browser.files.map(\.sizeInBytes) == [20, 10])
    }

    @MainActor
    @Test("shared sort state orders the folders of the level as well")
    func sharedSortStateOrdersFolders() throws {
        let fixture = try DefaultsFixture.make()
        defer { fixture.remove() }
        let feature = makeFeature(defaultsSuiteName: fixture.suiteName)
        let sourceID = UUID()
        feature.browser.folders = ["Zeta", "alpha", "Mid"].map { name in
            FileBrowsingDomain.MediaFolder(
                name: name,
                dataSourceID: sourceID,
                path: "/\(name)",
                url: URL(fileURLWithPath: "/\(name)")
            )
        }

        feature.uiState.sortCriteria = .init(key: .name, order: .descending)
        #expect(feature.browser.folders.map(\.name) == ["Zeta", "Mid", "alpha"])

        feature.uiState.sortCriteria = .init(key: .name, order: .ascending)
        #expect(feature.browser.folders.map(\.name) == ["alpha", "Mid", "Zeta"])

        feature.uiState.sortCriteria = .init(key: .size, order: .descending)
        #expect(feature.browser.folders.map(\.name) == ["Zeta", "Mid", "alpha"])
    }

    @MainActor
    private func makeFeature(defaultsSuiteName: String) -> MediaLibraryFeature {
        MediaLibraryFeature(defaultsSuiteName: defaultsSuiteName, onPlay: { _ in })
    }
}

private struct DefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    static func make() throws -> Self {
        let suiteName = "app.enchron.tests.media-library-ui-state.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Self(suiteName: suiteName, defaults: defaults)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
