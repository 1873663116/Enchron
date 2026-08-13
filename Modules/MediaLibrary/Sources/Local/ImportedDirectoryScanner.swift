import Foundation
import MediaSource

struct ImportedDirectorySnapshot: Sendable {
    struct Directory: Sendable {
        let name: String
        let relativePath: String
        let parentRelativePath: String
        let pathComponents: [String]
    }

    struct File: Sendable {
        let name: String
        let relativePath: String
        let parentRelativePath: String
        let sizeInBytes: Int64
        let modifiedAt: Date
        let fileExtension: String
    }

    let name: String
    let sourceIdentity: String
    let bookmark: Data
    let directories: [Directory]
    let files: [File]
}

enum ImportedDirectoryScanner {
    enum ScanError: LocalizedError {
        case unavailableDirectory
        case itemOutsideAuthorizedDirectory
        case duplicateRelativePath

        var errorDescription: String? {
            switch self {
            case .unavailableDirectory:
                return "The selected folder is unavailable. Choose it again to restore access."
            case .itemOutsideAuthorizedDirectory:
                return "The selected folder contains an item outside its authorized directory."
            case .duplicateRelativePath:
                return "The selected folder contains duplicate relative paths."
            }
        }
    }

    nonisolated static func scan(_ selectedURL: URL) throws -> ImportedDirectorySnapshot {
        let accessStarted = selectedURL.startAccessingSecurityScopedResource()
        defer { if accessStarted { selectedURL.stopAccessingSecurityScopedResource() } }

        let rootURL = selectedURL.standardizedFileURL
        let rootValues = try rootURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileResourceIdentifierKey,
        ])
        guard rootValues.isDirectory == true,
              let sourceIdentity = VersionedMediaIdentity.localIdentity(rootURL)?.storageKey else {
            throw ScanError.unavailableDirectory
        }
        let bookmark = try selectedURL.bookmarkData(
            options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
        )
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw ScanError.unavailableDirectory
        }

        var directories: [ImportedDirectorySnapshot.Directory] = []
        var files: [ImportedDirectorySnapshot.File] = []
        var relativePaths: Set<String> = []
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true || values.isPackage == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let components = try relativePathComponents(of: itemURL, under: rootURL)
            let relativePath = components.joined(separator: "/")
            guard relativePaths.insert(relativePath).inserted else {
                throw ScanError.duplicateRelativePath
            }
            let parentRelativePath = components.dropLast().joined(separator: "/")

            if values.isDirectory == true {
                directories.append(.init(
                    name: itemURL.lastPathComponent,
                    relativePath: relativePath,
                    parentRelativePath: parentRelativePath,
                    pathComponents: components
                ))
            } else if values.isRegularFile == true,
                      FileBrowsingDomain.FileFilter.playable.matches(fileURL: itemURL) {
                files.append(.init(
                    name: itemURL.lastPathComponent,
                    relativePath: relativePath,
                    parentRelativePath: parentRelativePath,
                    sizeInBytes: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    fileExtension: itemURL.pathExtension
                ))
            }
        }
        if let enumerationError { throw enumerationError }

        return ImportedDirectorySnapshot(
            name: rootURL.lastPathComponent,
            sourceIdentity: sourceIdentity,
            bookmark: bookmark,
            directories: directories,
            files: files
        )
    }

    private nonisolated static func relativePathComponents(
        of itemURL: URL,
        under rootURL: URL
    ) throws -> [String] {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let itemComponents = itemURL.standardizedFileURL.pathComponents
        guard itemComponents.count > rootComponents.count,
              itemComponents.starts(with: rootComponents) else {
            throw ScanError.itemOutsideAuthorizedDirectory
        }
        let relativeComponents = Array(itemComponents.dropFirst(rootComponents.count))
        guard relativeComponents.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".." && !component.contains("/")
        }) else {
            throw ScanError.itemOutsideAuthorizedDirectory
        }
        return relativeComponents
    }
}
