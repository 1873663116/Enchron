import Foundation

nonisolated extension FileBrowsingDomain {
    public struct LibraryFolder: Sendable, Equatable, Identifiable, Codable {
        public let id: UUID
        public var name: String
        public let parentID: UUID?

        public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
            self.id = id
            self.name = name
            self.parentID = parentID
        }
    }

    public struct MediaReference: Sendable, Equatable, Identifiable, Codable {
        public enum Locator: Sendable, Equatable, Codable {
            case file(bookmark: Data, relativePath: String)
            case photoAsset(localIdentifier: String)
            case sourceItem(dataSourceID: UUID, path: String)
        }

        public let id: UUID
        public var name: String
        public let locator: Locator
        public let sizeInBytes: Int64
        public let modifiedAt: Date
        public let fileExtension: String

        public init(
            id: UUID = UUID(),
            name: String,
            locator: Locator,
            sizeInBytes: Int64 = 0,
            modifiedAt: Date = .distantPast,
            fileExtension: String? = nil
        ) {
            self.id = id
            self.name = name
            self.locator = locator
            self.sizeInBytes = sizeInBytes
            self.modifiedAt = modifiedAt
            self.fileExtension = (fileExtension ?? (name as NSString).pathExtension).lowercased()
        }
    }

    public struct MediaLibrary: Sendable, Equatable, Codable {
        public enum LibraryError: LocalizedError {
            case emptyFolderName
            case folderNotFound

            public var errorDescription: String? {
                switch self {
                case .emptyFolderName:
                    return "Folder name is required."
                case .folderNotFound:
                    return "The library folder no longer exists."
                }
            }
        }

        private struct Entry: Sendable, Equatable, Codable {
            let folderID: UUID?
            let reference: MediaReference
        }

        private var allFolders: [LibraryFolder] = []
        private var entries: [Entry] = []

        public init() {}

        @discardableResult
        public mutating func createFolder(named name: String, in parentID: UUID? = nil) throws -> LibraryFolder {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { throw LibraryError.emptyFolderName }
            if let parentID, !allFolders.contains(where: { $0.id == parentID }) {
                throw LibraryError.folderNotFound
            }
            let folder = LibraryFolder(name: trimmedName, parentID: parentID)
            allFolders.append(folder)
            return folder
        }

        public mutating func add(_ reference: MediaReference, to folderID: UUID? = nil) throws {
            if let folderID, !allFolders.contains(where: { $0.id == folderID }) {
                throw LibraryError.folderNotFound
            }
            entries.append(Entry(folderID: folderID, reference: reference))
        }

        public mutating func renameFolder(_ folderID: UUID, to name: String) throws {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { throw LibraryError.emptyFolderName }
            guard let index = allFolders.firstIndex(where: { $0.id == folderID }) else {
                throw LibraryError.folderNotFound
            }
            let folder = allFolders[index]
            allFolders[index] = LibraryFolder(id: folder.id, name: trimmedName, parentID: folder.parentID)
        }

        public mutating func removeFolder(_ folderID: UUID) {
            var removedIDs: Set<UUID> = [folderID]
            while let child = allFolders.first(where: { folder in
                folder.parentID.map(removedIDs.contains) == true && !removedIDs.contains(folder.id)
            }) {
                removedIDs.insert(child.id)
            }
            allFolders.removeAll { removedIDs.contains($0.id) }
            entries.removeAll { $0.folderID.map(removedIDs.contains) == true }
        }

        public mutating func moveReference(_ referenceID: UUID, to folderID: UUID?) throws {
            if let folderID, !allFolders.contains(where: { $0.id == folderID }) {
                throw LibraryError.folderNotFound
            }
            guard let index = entries.firstIndex(where: { $0.reference.id == referenceID }) else {
                return
            }
            entries[index] = Entry(folderID: folderID, reference: entries[index].reference)
        }

        public mutating func removeReference(_ referenceID: UUID) {
            entries.removeAll { $0.reference.id == referenceID }
        }

        public func folders(in parentID: UUID?) -> [LibraryFolder] {
            allFolders.filter { $0.parentID == parentID }
        }

        public func references(in folderID: UUID?) -> [MediaReference] {
            entries.lazy.filter { $0.folderID == folderID }.map(\.reference)
        }

        public func folder(id: UUID) -> LibraryFolder? {
            allFolders.first { $0.id == id }
        }

        public func nextReference(after referenceID: UUID) -> MediaReference? {
            guard let currentIndex = entries.firstIndex(where: { $0.reference.id == referenceID }) else {
                return nil
            }
            let currentFolderID = entries[currentIndex].folderID
            return entries.dropFirst(currentIndex + 1).first { $0.folderID == currentFolderID }?.reference
        }
    }
}
