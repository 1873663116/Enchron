import Foundation
import Testing
@testable import MediaLibrary

struct MediaLibraryTests {
    @Test("adding a media reference keeps the original source outside the library")
    func addReferenceKeepsExternalSource() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let folder = try library.createFolder(named: "Series")
        let reference = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .file(bookmark: Data([0x01, 0x02]), relativePath: "Season 1/Episode 01.mkv")
        )

        try library.add(reference, to: folder.id)

        #expect(library.folders(in: nil) == [folder])
        #expect(library.references(in: folder.id) == [reference])
        #expect(library.references(in: folder.id).first?.locator == reference.locator)
    }

    @Test("moving and removing a reference only changes the virtual library")
    func moveAndRemoveReference() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let inbox = try library.createFolder(named: "Inbox")
        let series = try library.createFolder(named: "Series")
        let reference = FileBrowsingDomain.MediaReference(
            name: "Episode 02.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "photos-local-id")
        )
        try library.add(reference, to: inbox.id)

        try library.moveReference(reference.id, to: series.id)

        #expect(library.references(in: inbox.id).isEmpty)
        #expect(library.references(in: series.id).first?.locator == reference.locator)

        library.removeReference(reference.id)

        #expect(library.references(in: series.id).isEmpty)
    }

    @Test("moving and removing multiple references changes only the selected virtual entries")
    func moveAndRemoveMultipleReferences() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let inbox = try library.createFolder(named: "Inbox")
        let queue = try library.createFolder(named: "Queue")
        let first = FileBrowsingDomain.MediaReference(
            name: "First.mov",
            locator: .file(bookmark: Data([0x01]), relativePath: "First.mov")
        )
        let second = FileBrowsingDomain.MediaReference(
            name: "Second.mov",
            locator: .sourceItem(dataSourceID: UUID(), path: "second-asset")
        )
        let unselectedSourceID = UUID()
        let unselected = FileBrowsingDomain.MediaReference(
            name: "Keep.mov",
            locator: .sourceItem(dataSourceID: unselectedSourceID, path: "/Keep.mov")
        )
        try library.add(first, to: inbox.id)
        try library.add(second, to: inbox.id)
        try library.add(unselected, to: inbox.id)

        try library.moveReferences([first.id, second.id], to: queue.id)

        #expect(Set(library.references(in: queue.id).map(\.id)) == [first.id, second.id])
        #expect(library.references(in: queue.id).map(\.locator) == [first.locator, second.locator])
        #expect(library.references(in: inbox.id) == [unselected])

        library.removeReferences([first.id, second.id])

        #expect(library.references(in: queue.id).isEmpty)
        #expect(library.references(in: inbox.id) == [unselected])
        #expect(
            unselected.locator
                == .sourceItem(dataSourceID: unselectedSourceID, path: "/Keep.mov")
        )
    }

    @Test("renaming and deleting folders only changes virtual classification")
    func renameAndDeleteFolder() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let series = try library.createFolder(named: "Untitled")
        let season = try library.createFolder(named: "Season 1", in: series.id)
        let reference = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .file(bookmark: Data([0x01]), relativePath: "Episode 01.mkv")
        )
        try library.add(reference, to: season.id)

        try library.renameFolder(series.id, to: "Series")

        #expect(library.folder(id: series.id)?.name == "Series")
        #expect(library.references(in: season.id).first?.locator == reference.locator)

        library.removeFolder(series.id)

        #expect(library.folder(id: series.id) == nil)
        #expect(library.folder(id: season.id) == nil)
        #expect(library.references(in: season.id).isEmpty)
    }

    @Test("next episode follows the order inside one library folder")
    func nextReferenceUsesLibraryOrder() throws {
        var library = FileBrowsingDomain.MediaLibrary()
        let folder = try library.createFolder(named: "Season 1")
        let first = FileBrowsingDomain.MediaReference(
            name: "Episode 01.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Season 1/Episode 01.mkv")
        )
        let second = FileBrowsingDomain.MediaReference(
            name: "Episode 02.mkv",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Season 1/Episode 02.mkv")
        )
        try library.add(first, to: folder.id)
        try library.add(second, to: folder.id)

        #expect(library.nextReference(after: first.id) == second)
        #expect(library.nextReference(after: second.id) == nil)
    }

    @Test("media library persists external locators across app launches")
    func persistenceRoundTrip() throws {
        let suiteName = "app.enchron.tests.media-library.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMediaLibraryStore(defaults: defaults)
        var original = FileBrowsingDomain.MediaLibrary()
        let folder = try original.createFolder(named: "Mixed Sources")
        try original.add(
            .init(name: "Local.mov", locator: .file(bookmark: Data([0xA1]), relativePath: "Local.mov")),
            to: folder.id
        )
        try original.add(
            .init(name: "Remote.mkv", locator: .sourceItem(dataSourceID: UUID(), path: "/Remote.mkv")),
            to: folder.id
        )

        try store.save(original)

        #expect(try store.load() == original)
    }

    @Test("a persisted library with an unreadable entry drops only that entry")
    func unreadableEntryIsDroppedWithoutLosingOtherState() throws {
        let suiteName = "app.enchron.tests.media-library.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "enchron.mediaLibrary"
        let store = UserDefaultsMediaLibraryStore(defaults: defaults, key: key)

        let json = """
        {
          "allFolders": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "Mixed Sources", "parentID": null}
          ],
          "entries": [
            {
              "folderID": "11111111-1111-1111-1111-111111111111",
              "reference": {
                "id": "22222222-2222-2222-2222-222222222222",
                "name": "Local.mov",
                "locator": {"file": {"bookmark": "AQ==", "relativePath": "Local.mov"}},
                "sizeInBytes": 0,
                "modifiedAt": 0,
                "fileExtension": "mov",
                "remoteEntityTag": null,
                "remoteSourceKey": null
              }
            },
            {
              "folderID": "11111111-1111-1111-1111-111111111111",
              "reference": {
                "id": "33333333-3333-3333-3333-333333333333",
                "name": "Photos.mov",
                "locator": {"photoAsset": {"localIdentifier": "asset-id"}},
                "sizeInBytes": 0,
                "modifiedAt": 0,
                "fileExtension": "mov",
                "remoteEntityTag": null,
                "remoteSourceKey": null
              }
            },
            {
              "folderID": "11111111-1111-1111-1111-111111111111",
              "reference": {
                "id": "44444444-4444-4444-4444-444444444444",
                "name": "Remote.mkv",
                "locator": {"sourceItem": {"dataSourceID": "55555555-5555-5555-5555-555555555555", "path": "/Remote.mkv"}},
                "sizeInBytes": 0,
                "modifiedAt": 0,
                "fileExtension": "mkv",
                "remoteEntityTag": null,
                "remoteSourceKey": null
              }
            }
          ],
          "importedDirectories": []
        }
        """
        defaults.set(Data(json.utf8), forKey: key)

        let loaded = try store.load()

        let folder = try #require(loaded.folders(in: nil).first)
        #expect(folder.name == "Mixed Sources")
        let names = Set(loaded.references(in: folder.id).map(\.name))
        #expect(names == ["Local.mov", "Remote.mkv"])
    }

    @MainActor
    @Test("a folder bookmark resolves the original child without copying it")
    func folderBookmarkResolvesOriginalChild() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let video = root.appending(path: "Season 1/Episode 01.mkv")
        let unrelatedDestination = root.appending(path: "App Library/Episode 01.mkv")
        try fileManager.createDirectory(at: video.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x01, 0x02]).write(to: video)
        defer { try? fileManager.removeItem(at: root) }

        let resolver = SecurityScopedFileReferenceResolver()
        let resolved = try resolver.resolve(
            bookmark: root.bookmarkData(
                options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
            ),
            relativePath: "Season 1/Episode 01.mkv"
        )

        #expect(resolved.url.standardizedFileURL == video.standardizedFileURL)
        #expect(fileManager.fileExists(atPath: unrelatedDestination.path) == false)
    }

    @Test("bookmark creation asks for the minimal bookmark")
    @MainActor
    func bookmarkCreationMatchesTheTargetSandboxModel() {
        #expect(
            SecurityScopedFileReferenceResolver.bookmarkCreationOptions
                == .minimalBookmark
        )
    }
}
