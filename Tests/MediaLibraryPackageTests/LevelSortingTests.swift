import Foundation
@testable import MediaLibrary
import Testing

struct LevelSortingTests {
    @Test("folders order by name under the size key and follow the ascending choice")
    func foldersIgnoreTheSizeKey() {
        let ordered = FileBrowsingDomain.SortCriteria(key: .size, order: .ascending)
            .sorted(Self.folders)
        #expect(ordered.map(\.name) == ["alpha", "Mid", "Zeta"])

        let reversed = FileBrowsingDomain.SortCriteria(key: .size, order: .descending)
            .sorted(Self.folders)
        #expect(reversed.map(\.name) == ["Zeta", "Mid", "alpha"])
    }

    @Test("folders order by their modification time and undated folders sink to the end")
    func foldersOrderByModificationTime() {
        let ascending = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: .ascending)
            .sorted(Self.folders)
        #expect(ascending.map(\.name) == ["Zeta", "alpha", "Mid"])

        let descending = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: .descending)
            .sorted(Self.folders)
        #expect(descending.map(\.name) == ["alpha", "Zeta", "Mid"])
    }

    @Test("folders sharing a modification time keep name order in both directions")
    func tiedFoldersKeepNameOrder() {
        let shared = Date(timeIntervalSince1970: 100)
        let tied = ["Zeta", "alpha", "Mid"].map { name in
            Self.folder(named: name, modifiedAt: shared)
        }

        let ascending = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: .ascending)
            .sorted(tied)
        #expect(ascending.map(\.name) == ["alpha", "Mid", "Zeta"])

        let descending = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: .descending)
            .sorted(tied)
        #expect(descending.map(\.name) == ["alpha", "Mid", "Zeta"])
    }

    @Test("a level offers only the keys its own items can answer")
    func availableKeysFollowTheLevel() {
        let folderOnly = FileBrowsingDomain.SortKeyAvailability(datedItemCount: 2, sizedItemCount: 0)
        #expect(folderOnly.canOrder(by: .name))
        #expect(folderOnly.canOrder(by: .modifiedDate))
        #expect(folderOnly.canOrder(by: .size) == false)

        let undatedFolderOnly = FileBrowsingDomain.SortKeyAvailability(
            datedItemCount: 0,
            sizedItemCount: 0
        )
        #expect(undatedFolderOnly.canOrder(by: .name))
        #expect(undatedFolderOnly.canOrder(by: .modifiedDate) == false)
        #expect(undatedFolderOnly.canOrder(by: .size) == false)

        let mixed = FileBrowsingDomain.SortKeyAvailability(datedItemCount: 5, sizedItemCount: 3)
        #expect(mixed.canOrder(by: .name))
        #expect(mixed.canOrder(by: .modifiedDate))
        #expect(mixed.canOrder(by: .size))
    }

    @Test("a library folder stored before folders carried a creation date decodes as undated")
    func libraryFolderWithoutACreationDateDecodes() throws {
        let stored = """
        {"id":"\(UUID().uuidString)","name":"Watch Later"}
        """
        let folder = try JSONDecoder().decode(
            FileBrowsingDomain.LibraryFolder.self,
            from: Data(stored.utf8)
        )
        #expect(folder.createdAt == nil)
        #expect(FileBrowsingDomain.LibraryFolder(name: "New").createdAt != nil)
    }

    @Test("library folders order by creation date and undated folders sink to the end")
    func libraryFoldersOrderByCreationDate() {
        let folders = [
            FileBrowsingDomain.LibraryFolder(
                name: "alpha",
                createdAt: Date(timeIntervalSince1970: 300)
            ),
            FileBrowsingDomain.LibraryFolder(name: "Mid", createdAt: nil),
            FileBrowsingDomain.LibraryFolder(
                name: "Zeta",
                createdAt: Date(timeIntervalSince1970: 100)
            )
        ].sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let ascending = FileBrowsingDomain.SortCriteria.dated(folders, order: .ascending) {
            $0.createdAt
        }
        #expect(ascending.map(\.name) == ["Zeta", "alpha", "Mid"])

        let descending = FileBrowsingDomain.SortCriteria.dated(folders, order: .descending) {
            $0.createdAt
        }
        #expect(descending.map(\.name) == ["alpha", "Zeta", "Mid"])
    }

    private static func folder(named name: String, modifiedAt: Date?) -> FileBrowsingDomain.MediaFolder {
        FileBrowsingDomain.MediaFolder(
            name: name,
            dataSourceID: sourceID,
            path: "/\(name)",
            url: URL(fileURLWithPath: "/\(name)"),
            modifiedAt: modifiedAt
        )
    }

    private static let sourceID = UUID()

    private static var folders: [FileBrowsingDomain.MediaFolder] {
        [
            folder(named: "Zeta", modifiedAt: Date(timeIntervalSince1970: 100)),
            folder(named: "alpha", modifiedAt: Date(timeIntervalSince1970: 300)),
            folder(named: "Mid", modifiedAt: nil)
        ]
    }
}
