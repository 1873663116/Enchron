import Foundation
import Testing
@testable import MediaLibrary

struct MediaLibraryBehaviorTests {
    @Test("folder names are normalized and unique within one parent")
    func folderNamesAreUniqueWithinOneParent() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let first = try library.createFolder(named: "  Series  ")

        #expect(first.name == "Series")
        #expect(throws: FileBrowsingDomain.MediaLibrary.LibraryError.duplicateFolderName) {
            try library.createFolder(named: "series")
        }
        #expect(library.folders(in: nil) == [first])
    }

    @Test("the same folder name is allowed under different parents")
    func sameFolderNameIsAllowedUnderDifferentParents() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let firstParent = try library.createFolder(named: "Shows")
        let secondParent = try library.createFolder(named: "Films")

        let first = try library.createFolder(named: "Favorites", in: firstParent.id)
        let second = try library.createFolder(named: "favorites", in: secondParent.id)

        #expect(library.folders(in: firstParent.id) == [first])
        #expect(library.folders(in: secondParent.id) == [second])
    }

    @Test("renaming preserves state when a sibling already has the normalized name")
    func duplicateRenamePreservesState() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let first = try library.createFolder(named: "Series")
        let second = try library.createFolder(named: "Archive")

        #expect(throws: FileBrowsingDomain.MediaLibrary.LibraryError.duplicateFolderName) {
            try library.renameFolder(second.id, to: " series ")
        }
        #expect(library.folder(id: first.id)?.name == "Series")
        #expect(library.folder(id: second.id)?.name == "Archive")
    }

    @Test("empty folder names are rejected without changing the library")
    func emptyFolderNamesAreRejected() {
        var library = FileBrowsingDomain.MediaLibrary()

        #expect(throws: FileBrowsingDomain.MediaLibrary.LibraryError.emptyFolderName) {
            try library.createFolder(named: " \n ")
        }
        #expect(library.folders(in: nil).isEmpty)
    }

    @Test("moving references changes organization without changing media identity")
    func movingReferencesPreservesIdentity() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let folder = try library.createFolder(named: "Watch Later")
        let reference = FileBrowsingDomain.MediaReference(
            name: "Film.mkv",
            locator: .photoAsset(localIdentifier: "film")
        )
        try library.add(reference)

        try library.moveReference(reference.id, to: folder.id)

        #expect(library.references(in: nil).isEmpty)
        #expect(library.references(in: folder.id) == [reference])
    }

    @Test("batch management moves and removes only selected virtual references")
    func batchManagementPreservesUnselectedReferences() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let folder = try library.createFolder(named: "Watch Later")
        let first = FileBrowsingDomain.MediaReference(
            name: "First.mkv",
            locator: .photoAsset(localIdentifier: "first")
        )
        let second = FileBrowsingDomain.MediaReference(
            name: "Second.mkv",
            locator: .photoAsset(localIdentifier: "second")
        )
        let unselected = FileBrowsingDomain.MediaReference(
            name: "Keep.mkv",
            locator: .photoAsset(localIdentifier: "keep")
        )
        try library.add(first)
        try library.add(second)
        try library.add(unselected)

        try library.moveReferences([first.id, second.id], to: folder.id)

        #expect(library.references(in: nil) == [unselected])
        #expect(library.references(in: folder.id) == [first, second])

        library.removeReferences([first.id, second.id])

        #expect(library.references(in: folder.id).isEmpty)
        #expect(library.references(in: nil) == [unselected])
    }

    @Test("removing a folder removes its virtual subtree and references")
    func removingFolderRemovesVirtualSubtree() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let parent = try library.createFolder(named: "Series")
        let child = try library.createFolder(named: "Season 1", in: parent.id)
        let reference = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Series/Episode 01.mkv")
        )
        try library.add(reference, to: child.id)

        library.removeFolder(parent.id)

        #expect(library.folder(id: parent.id) == nil)
        #expect(library.folder(id: child.id) == nil)
        #expect(library.references(in: child.id).isEmpty)
    }

    @Test("folder organization persists through the production store")
    func folderOrganizationPersists() throws {
        let suiteName = "app.enchron.tests.media-library.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMediaLibraryStore(defaults: defaults)
        var library = FileBrowsingDomain.MediaLibrary()
        let parent = try library.createFolder(named: "Series")
        _ = try library.createFolder(named: "Season 1", in: parent.id)

        try store.save(library)

        #expect(try store.load() == library)
    }

    @Test("search uses the visible media name without its extension")
    func searchUsesVisibleMediaName() {
        let reference = FileBrowsingDomain.MediaReference(
            name: "The Matrix.mkv",
            locator: .photoAsset(localIdentifier: "matrix")
        )

        #expect(MediaLibrarySearch.matches(reference, query: " matrix "))
        #expect(MediaLibrarySearch.matches(reference, query: "MATRIX"))
        #expect(!MediaLibrarySearch.matches(reference, query: "mkv"))
    }

    @Test("folder search uses the complete visible folder name")
    func folderSearchUsesCompleteVisibleName() {
        let folder = FileBrowsingDomain.LibraryFolder(name: "Season 01.mkv")

        #expect(MediaLibrarySearch.matches(folder, query: "01.MKV"))
        #expect(!MediaLibrarySearch.matches(folder, query: "season 02"))
    }

    @MainActor
    @Test("library navigation restores locations through back and forward history")
    func libraryNavigationRestoresLocations() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let series = try library.createFolder(named: "Series")
        let season = try library.createFolder(named: "Season 1", in: series.id)
        let episode = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .photoAsset(localIdentifier: "episode-01")
        )
        try library.add(episode, to: season.id)
        let viewModel = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: .standard),
            resolver: MediaReferenceResolver(),
            initialLibrary: library,
            onPlay: { _ in }
        )

        viewModel.open(series)
        viewModel.open(season)
        #expect(viewModel.currentFolderName == "Season 1")
        #expect(viewModel.references == [episode])

        viewModel.navigateBack()
        #expect(viewModel.currentFolderName == "Series")
        #expect(viewModel.folders == [season])
        #expect(viewModel.canNavigateForward)

        viewModel.navigateForward()
        #expect(viewModel.currentFolderName == "Season 1")
        #expect(viewModel.references == [episode])
    }
}
