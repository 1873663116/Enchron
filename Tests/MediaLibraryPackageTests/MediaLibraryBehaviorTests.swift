import CoreGraphics
import Foundation
import MediaSource
import Testing
@testable import MediaLibrary

struct MediaLibraryBehaviorTests {
    #if DEBUG
    @Test("artwork URLs stay known for folders the user has already visited")
    @MainActor
    func artworkURLsStayKnownAcrossFolderChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let artworkStore = ArtworkStore(debugRootURL: root)
        var library = FileBrowsingDomain.MediaLibrary()
        let first = try library.createFolder(named: "First")
        let second = try library.createFolder(named: "Second")
        let sourceID = UUID()
        let played = FileBrowsingDomain.MediaReference(
            name: "Played.mkv",
            locator: .sourceItem(dataSourceID: sourceID, path: "played")
        )
        let unplayed = FileBrowsingDomain.MediaReference(
            name: "Unplayed.mkv",
            locator: .sourceItem(dataSourceID: sourceID, path: "unplayed")
        )
        try library.add(played, to: first.id)
        try library.add(unplayed, to: second.id)
        let identity = MediaIdentity.remote(
            sourceKey: played.remoteSourceKey ?? "legacy:\(sourceID.uuidString.lowercased())",
            canonicalPath: "played"
        )
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: 4,
                height: 4,
                bitsPerComponent: 8,
                bytesPerRow: 16,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        try artworkStore.store(try #require(context.makeImage()), for: ArtworkKey(mediaIdentity: identity))

        let viewModel = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: .standard),
            resolver: MediaReferenceResolver(),
            artworkStore: artworkStore,
            initialLibrary: library,
            onPlay: { _ in }
        )

        viewModel.open(first)
        await viewModel.loadViewingStatesForCurrentFolder()
        let playedURL = try #require(viewModel.artworkURL(for: played))
        #expect(playedURL.isFileURL)

        viewModel.navigateToRoot()
        viewModel.open(second)
        await viewModel.loadViewingStatesForCurrentFolder()
        #expect(viewModel.artworkURL(for: played) == playedURL)
        #expect(viewModel.artworkURL(for: unplayed) == nil)

        viewModel.forgetArtwork()
        #expect(viewModel.artworkURL(for: played) == nil)
    }
    #endif

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
            locator: .sourceItem(dataSourceID: UUID(), path: "film")
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
            locator: .sourceItem(dataSourceID: UUID(), path: "first")
        )
        let second = FileBrowsingDomain.MediaReference(
            name: "Second.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "second")
        )
        let unselected = FileBrowsingDomain.MediaReference(
            name: "Keep.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "keep")
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

    @Test("removing a folder removes its virtual subtree")
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

    @Test("removing a folder rehomes references from its subtree to its parent")
    func removingFolderRehomesSubtreeReferencesToParent() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let destination = try library.createFolder(named: "Library")
        let removedRoot = try library.createFolder(named: "Series", in: destination.id)
        let descendant = try library.createFolder(named: "Season 1", in: removedRoot.id)
        let directReference = FileBrowsingDomain.MediaReference(
            name: "Special.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Series/Special.mkv")
        )
        let nestedReference = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Series/Season 1/Episode 01.mkv")
        )
        try library.add(directReference, to: removedRoot.id)
        try library.add(nestedReference, to: descendant.id)

        library.removeFolder(removedRoot.id)

        #expect(library.folder(id: removedRoot.id) == nil)
        #expect(library.folder(id: descendant.id) == nil)
        #expect(library.references(in: destination.id) == [directReference, nestedReference])
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
            locator: .sourceItem(dataSourceID: UUID(), path: "matrix")
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
            locator: .sourceItem(dataSourceID: UUID(), path: "episode-01")
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

    @MainActor
    @Test("importing a directory preserves every folder level")
    func importingDirectoryPreservesHierarchy() async throws {
        let fixture = try DirectoryImportFixture.make()
        defer { fixture.remove() }
        let viewModel = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: fixture.defaults),
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        await viewModel.addFolder(fixture.root)

        let importedRoot = try #require(viewModel.folders.only)
        #expect(importedRoot.name == "TestMedia")
        #expect(viewModel.references.isEmpty)

        viewModel.open(importedRoot)
        #expect(Set(viewModel.folders.map(\.name)) == ["Empty", "Season 01"])
        #expect(viewModel.references.map(\.name) == ["Root Movie.mp4"])

        let season = try #require(viewModel.folders.first { $0.name == "Season 01" })
        viewModel.open(season)
        #expect(viewModel.folders.map(\.name) == ["Bonus"])
        #expect(viewModel.references.map(\.name) == ["Episode 01.mkv"])

        let bonus = try #require(viewModel.folders.only)
        viewModel.open(bonus)
        let bonusReference = try #require(viewModel.references.only)
        #expect(bonusReference.name == "Behind the Scenes.mov")
        #expect(bonusReference.fileExtension == "mov")
        guard case .file(_, let relativePath) = bonusReference.locator else {
            Issue.record("The imported video did not retain its folder bookmark locator.")
            return
        }
        #expect(relativePath == "Season 01/Bonus/Behind the Scenes.mov")
    }

    @MainActor
    @Test("directory import de-duplicates entries and importing the same directory is idempotent")
    func repeatedDirectoryImportIsIdempotent() async throws {
        let fixture = try DirectoryImportFixture.make()
        defer { fixture.remove() }
        let store = UserDefaultsMediaLibraryStore(defaults: fixture.defaults)
        let viewModel = MediaLibraryViewModel(
            store: store,
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        await viewModel.addFolder(fixture.root)
        let firstLibrary = viewModel.library
        let firstRoot = try #require(viewModel.folders.only)

        await viewModel.addFolder(fixture.root)

        #expect(viewModel.library == firstLibrary)
        #expect(viewModel.folders == [firstRoot])
        #expect(try store.load() == firstLibrary)
        let relativePaths: [String] = viewModel.allFolders.flatMap { folder in
            viewModel.library.references(in: folder.id).compactMap { reference -> String? in
                guard case .file(_, let relativePath) = reference.locator else { return nil }
                return relativePath
            }
        }
        #expect(relativePaths.count == Set(relativePaths).count)
        #expect(relativePaths.count == 3)
    }

    @MainActor
    @Test("folder bookmarks cannot resolve a path outside the selected directory")
    func folderBookmarkRejectsParentTraversal() throws {
        let fixture = try DirectoryImportFixture.make()
        defer { fixture.remove() }
        let resolver = SecurityScopedFileReferenceResolver()

        #expect(throws: SecurityScopedFileReferenceResolver.ResolutionError.unavailable) {
            try resolver.resolve(
                bookmark: fixture.root.bookmarkData(
                    options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
                ),
                relativePath: "../Outside/Escape.mp4"
            )
        }
    }

    @Test("libraries saved before imported-directory metadata still decode")
    func legacyLibraryWithoutImportedDirectoriesDecodes() throws {
        let legacyJSON = Data(#"{"allFolders":[],"entries":[]}"#.utf8)

        let library = try JSONDecoder().decode(
            FileBrowsingDomain.MediaLibrary.self,
            from: legacyJSON
        )

        #expect(library == FileBrowsingDomain.MediaLibrary())
    }

    @MainActor
    @Test("a failed directory-import save does not publish a partial tree")
    func failedDirectoryImportSaveIsAtomic() async throws {
        let fixture = try DirectoryImportFixture.make()
        defer { fixture.remove() }
        let viewModel = MediaLibraryViewModel(
            store: FailingMediaLibraryStore(),
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        await viewModel.addFolder(fixture.root)

        #expect(viewModel.library == FileBrowsingDomain.MediaLibrary())
        #expect(viewModel.lastErrorMessage != nil)
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

private struct DirectoryImportFixture {
    let root: URL
    let defaults: UserDefaults
    let suiteName: String

    static func make() throws -> Self {
        let fileManager = FileManager.default
        let container = fileManager.temporaryDirectory.appending(
            path: "enchron-directory-import-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let root = container.appending(path: "TestMedia", directoryHint: .isDirectory)
        let outside = container.appending(path: "Outside", directoryHint: .isDirectory)
        let season = root.appending(path: "Season 01", directoryHint: .isDirectory)
        let bonus = season.appending(path: "Bonus", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: bonus, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appending(path: "Empty", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([0x01]).write(to: root.appending(path: "Root Movie.mp4"))
        try Data([0x02]).write(to: season.appending(path: "Episode 01.mkv"))
        try Data([0x03]).write(to: bonus.appending(path: "Behind the Scenes.mov"))
        try Data([0x04]).write(to: root.appending(path: "Notes.txt"))
        try Data([0x05]).write(to: outside.appending(path: "Escape.mp4"))
        try fileManager.createSymbolicLink(
            at: root.appending(path: "Escape", directoryHint: .isDirectory),
            withDestinationURL: outside
        )

        let suiteName = "app.enchron.tests.directory-import.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return Self(root: root, defaults: defaults, suiteName: suiteName)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct FailingMediaLibraryStore: MediaLibraryStoring {
    struct SaveFailure: Error {}

    func load() throws -> FileBrowsingDomain.MediaLibrary {
        FileBrowsingDomain.MediaLibrary()
    }

    func save(_: FileBrowsingDomain.MediaLibrary) throws {
        throw SaveFailure()
    }
}
